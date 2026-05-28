-- GuildHub - Team Applications
-- Handles application submission, review, and background sync so no
-- application or decision is lost due to offline players.
--
-- Addon message protocol (all prefixed GH.ADDON_PREFIX, sent over "GUILD"):
--   TMAPP  \30 groupId \30 applicant \30 role \30 main \30 alts \30 logURL \30 notes \30 ts
--   TMAPPR \30 groupId \30 applicant \30 status      (accepted|declined)
--   TMAPPW \30 groupId \30 applicant                 (withdrawal)
--   TMAPPC \30 applicantName                         (login sync check)

local GH       = GuildHub
local TeamApps = GH.TeamApps

local SEP     = "\30"
local TM_APP  = "TMAPP"
local TM_APPR = "TMAPPR"
local TM_APPW = "TMAPPW"
local TM_APPC = "TMAPPC"

-- ── Initialization ────────────────────────────────────────────────────────

function TeamApps:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, prefix, payload, _, _)
        if prefix == GH.ADDON_PREFIX then
            TeamApps:OnAddonMessage(payload)
        end
    end)

    -- Login re-broadcast: re-send pending apps so late-arriving managers
    -- receive them. Random jitter (0–10s) spreads bursts across online clients.
    C_Timer.After(20 + math.random(0, 10), function()
        if not GH:IsInGuild() then return end
        local cutoff = time() - 30 * 86400
        local delay  = 0
        for groupId, apps in pairs(GH.DB:GetAllTeamApplications()) do
            for applicant, app in pairs(apps) do
                if app.status == "pending" and (app.ts or 0) > cutoff then
                    local g, a = groupId, app
                    local n    = applicant
                    C_Timer.After(delay, function()
                        TeamApps:_SendApp(g, n, a)
                    end)
                    delay = delay + 0.2
                end
            end
        end
    end)

    -- Applicant login sync: if we have pending apps, ask online clients
    -- whether any have been resolved while we were offline.
    C_Timer.After(12, function()
        if not GH:IsInGuild() then return end
        local myName = GH:GetPlayerName()
        for _, apps in pairs(GH.DB:GetAllTeamApplications()) do
            if apps[myName] and apps[myName].status == "pending" then
                local payload = table.concat({ TM_APPC, myName }, SEP)
                TeamApps:_Send(payload)
                return   -- one broadcast covers all pending apps
            end
        end
    end)
end

-- ── Public API ────────────────────────────────────────────────────────────

-- Called by UI on form submit.
function TeamApps:Submit(groupId, role, main, alts, logURL, notes)
    local myName = GH:GetPlayerName()
    local ts     = time()
    local data   = {
        role   = role,
        main   = main,
        alts   = alts   or "",
        logURL = logURL or "",
        notes  = notes  or "",
        ts     = ts,
        status = "pending",
    }
    GH.DB:SaveTeamApplication(groupId, myName, data)
    TeamApps:_SendApp(groupId, myName, data)
end

-- Called by manager UI on Accept.
function TeamApps:Accept(groupId, applicant)
    local existing = GH.DB:GetTeamApplications(groupId)[applicant]
    if not existing then return end
    existing.status = "accepted"
    GH.DB:SaveTeamApplication(groupId, applicant, existing)
    local payload = table.concat({ TM_APPR, groupId, applicant, "accepted" }, SEP)
    TeamApps:_Send(payload)
    GH.Groups:AddMember(groupId, applicant)
    TeamApps:_NotifyUIRefresh()
end

-- Called by manager UI on Decline.
function TeamApps:Decline(groupId, applicant)
    local existing = GH.DB:GetTeamApplications(groupId)[applicant]
    if not existing then return end
    existing.status = "declined"
    GH.DB:SaveTeamApplication(groupId, applicant, existing)
    local payload = table.concat({ TM_APPR, groupId, applicant, "declined" }, SEP)
    TeamApps:_Send(payload)
    TeamApps:_NotifyUIRefresh()
end

-- Called by applicant UI on Withdraw.
function TeamApps:Withdraw(groupId)
    local myName   = GH:GetPlayerName()
    local existing = GH.DB:GetTeamApplications(groupId)[myName]
    if not existing then return end
    existing.status = "withdrawn"
    GH.DB:SaveTeamApplication(groupId, myName, existing)
    local payload = table.concat({ TM_APPW, groupId, myName }, SEP)
    TeamApps:_Send(payload)
    TeamApps:_NotifyUIRefresh()
end

-- Returns the current player's application record for groupId, or nil.
function TeamApps:GetMyApplication(groupId)
    local myName = GH:GetPlayerName()
    return GH.DB:GetTeamApplications(groupId)[myName]
end

-- Returns true if the current player has a pending application for groupId.
function TeamApps:HasPendingApplication(groupId)
    local app = TeamApps:GetMyApplication(groupId)
    return app ~= nil and app.status == "pending"
end

-- Returns the count of pending applications for groupId.
function TeamApps:GetPendingCount(groupId)
    local count = 0
    for _, app in pairs(GH.DB:GetTeamApplications(groupId)) do
        if app.status == "pending" then count = count + 1 end
    end
    return count
end

-- ── Internal send helpers ─────────────────────────────────────────────────

function TeamApps:_SendApp(groupId, applicant, app)
    local payload = table.concat({
        TM_APP, groupId, applicant,
        app.role, app.main,
        app.alts   or "",
        app.logURL or "",
        app.notes  or "",
        tostring(app.ts or 0),
    }, SEP)
    TeamApps:_Send(payload)
end

function TeamApps:_Send(payload)
    if #payload > 250 then return end
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if C_ChatInfo then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
end

function TeamApps:_NotifyUIRefresh()
    if GH.UI and GH.UI.RefreshTeamsApplicationsBadge then
        GH.UI:RefreshTeamsApplicationsBadge()
    end
end

-- ── Addon message routing ─────────────────────────────────────────────────

function TeamApps:OnAddonMessage(payload)
    -- Quick pre-filter: only handle TMAP* messages
    if payload:sub(1, 4) ~= "TMAP" then return end

    local parts = {}
    for p in (payload .. SEP):gmatch("([^" .. SEP .. "]*)" .. SEP) do
        parts[#parts + 1] = p
    end
    if #parts < 1 then return end

    local msgType = parts[1]

    if msgType == TM_APP and #parts >= 9 then
        TeamApps:_HandleApp(parts)
    elseif msgType == TM_APPR and #parts >= 4 then
        TeamApps:_HandleResponse(parts)
    elseif msgType == TM_APPW and #parts >= 3 then
        TeamApps:_HandleWithdrawal(parts)
    elseif msgType == TM_APPC and #parts >= 2 then
        TeamApps:_HandleCheck(parts)
    end
end

function TeamApps:_HandleApp(parts)
    local groupId   = parts[2]
    local applicant = parts[3]
    local role      = parts[4]
    local main      = parts[5]
    local alts      = parts[6]
    local logURL    = parts[7]
    local notes     = parts[8]
    local ts        = tonumber(parts[9]) or 0

    -- De-duplicate: if already stored with the same timestamp, ignore.
    local existing = GH.DB:GetTeamApplications(groupId)[applicant]
    if existing and existing.ts == ts then return end

    -- Preserve a non-pending status if we already reviewed this application.
    local status = "pending"
    if existing and existing.status ~= "pending" then
        status = existing.status
    end

    GH.DB:SaveTeamApplication(groupId, applicant, {
        role   = role,
        main   = main,
        alts   = alts,
        logURL = logURL,
        notes  = notes,
        ts     = ts,
        status = status,
    })
    TeamApps:_NotifyUIRefresh()
end

function TeamApps:_HandleResponse(parts)
    local groupId   = parts[2]
    local applicant = parts[3]
    local status    = parts[4]

    local existing = GH.DB:GetTeamApplications(groupId)[applicant]
    if existing then
        existing.status = status
        GH.DB:SaveTeamApplication(groupId, applicant, existing)
    else
        GH.DB:SaveTeamApplication(groupId, applicant, {
            role   = "",
            main   = applicant,
            alts   = "",
            logURL = "",
            notes  = "",
            ts     = 0,
            status = status,
        })
    end

    -- Notify the applicant if this is their own application.
    local myName = GH:GetPlayerName()
    if applicant == myName then
        local g        = GH.DB:GetGroups()[groupId]
        local teamName = g and g.name or "a team"
        if status == "accepted" then
            print("|cff7289daGuildHub:|r Your application to |cffffd700"
                  .. teamName .. "|r was accepted!")
        else
            print("|cff7289daGuildHub:|r Your application to |cffffd700"
                  .. teamName .. "|r was declined.")
        end
        if GH.UI then GH.UI:RefreshTeamsGroupList() end
    end

    TeamApps:_NotifyUIRefresh()
end

function TeamApps:_HandleWithdrawal(parts)
    local groupId   = parts[2]
    local applicant = parts[3]
    local existing  = GH.DB:GetTeamApplications(groupId)[applicant]
    if existing then
        existing.status = "withdrawn"
        GH.DB:SaveTeamApplication(groupId, applicant, existing)
    end
    TeamApps:_NotifyUIRefresh()
end

function TeamApps:_HandleCheck(parts)
    -- Applicant is asking for status updates on their pending apps.
    -- Respond for any application we have stored with a resolved status.
    local applicant = parts[2]
    local myName    = GH:GetPlayerName()
    if applicant == myName then return end  -- ignore our own echo

    C_Timer.After(math.random(1, 5), function()
        for groupId, apps in pairs(GH.DB:GetAllTeamApplications()) do
            local app = apps[applicant]
            if app and app.status ~= "pending" and app.status ~= "withdrawn" then
                local payload = table.concat(
                    { TM_APPR, groupId, applicant, app.status }, SEP)
                TeamApps:_Send(payload)
            end
        end
    end)
end
