-- GuildHub - GroupManager
-- Officer-defined raid/social group presets with invite system.
--
-- Addon message protocol (all prefixed with GH.ADDON_PREFIX):
--   TMINV \30 groupId \30 teamName \30 inviterName \30 targetName
--   TMACC \30 groupId \30 accepterName
--   TMDEC \30 groupId \30 declinerName
--   TMREM \30 groupId \30 removedName
--   TMCHK \30 requesterName              (login sync request)
--   TMSYN \30 groupId \30 teamName \30 membersCSV \30 channelId \30 targetName
--   TMOFC \30 groupId \30 teamName \30 membersCSV \30 channelId \30 creatorRank \30 creator \30 createdAt \30 pending
--   TMDLT \30 groupId
--   TMDPC \30 pendingId \30 canonicalId  (duplicate conflict → GM)
--   TMGMR \30 action \30 pendingId \30 canonicalId \30 [newName]  (GM resolution)
--   TMROL \30 groupId \30 memberName \30 role                     (role assignment; "" clears)

local GH     = GuildHub
local Groups = GH.Groups

local InviteUnit = rawget(_G, "InviteUnit")
local SEP        = "\30"

local TM_INV = "TMINV"
local TM_ACC = "TMACC"
local TM_DEC = "TMDEC"
local TM_REM = "TMREM"
local TM_CHK = "TMCHK"
local TM_SYN = "TMSYN"
local TM_OFC = "TMOFC"   -- officer visibility sync (no membership implied)
local TM_DLT = "TMDLT"  -- broadcast team deletion to all officers
local TM_DPC = "TMDPC"  -- duplicate conflict notification → GM
local TM_GMR = "TMGMR"  -- GM resolution broadcast → all officers
local TM_ROL = "TMROL"

Groups.pendingInvites = {}   -- [groupId] = { teamName, inviter }

-- ── Initialisation ────────────────────────────────────────────────────────

function Groups:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, prefix, payload, _, sender)
        if prefix == GH.ADDON_PREFIX then
            Groups:OnAddonMessage(payload, sender)
        end
    end)

    -- After login, ask online officers to verify team membership.
    -- Retry a few times so a delayed officer login still delivers the sync.
    local function TrySyncRequest(attempt)
        if not GH:IsInGuild() then return end
        -- Stop retrying once we already have at least one team with our name.
        if attempt > 1 then
            local myName = GH:GetPlayerName()
            for _, g in pairs(GH.DB:GetGroups()) do
                for _, n in ipairs(g.members or {}) do
                    if n == myName then return end
                end
            end
        end
        Groups:RequestTeamSync()
        if attempt < 4 then
            C_Timer.After(90, function() TrySyncRequest(attempt + 1) end)
        end
    end
    C_Timer.After(12, function() TrySyncRequest(1) end)

    -- Officers: on login, proactively push TMSYN to online team members whose
    -- TMCHK retry window may have already closed before this client logged in.
    -- Fires once, 20s after login (roster is populated by then via GUILD_ROSTER_UPDATE).
    -- Sends are staggered 200 ms apart to avoid flooding the addon message queue.
    C_Timer.After(20, function()
        if not GH:CanManageTeams() then return end
        local myName = GH:GetPlayerName()
        local delay  = 0
        for groupId, g in pairs(GH.DB:GetGroups()) do
            for _, memberName in ipairs(g.members or {}) do
                if memberName ~= myName then
                    local info = GH.GuildData:FindMember(memberName)
                    if info and info.online then
                        local gid, gData, mName = groupId, g, memberName
                        C_Timer.After(delay, function()
                            Groups:_SyncToMember(gid, gData, mName)
                        end)
                        delay = delay + 0.2
                    end
                end
            end
        end
    end)
end

-- ── Basic group CRUD ──────────────────────────────────────────────────────

function Groups:GetAll()
    local myName    = GH:GetPlayerName()
    local isOfficer = GH:IsOfficer()
    local out        = {}
    local includedIds = {}

    for id, g in pairs(GH.DB:GetGroups()) do
        local members = g.members or {}
        local isMember = false
        for _, n in ipairs(members) do
            if n == myName then isMember = true; break end
        end
        -- Fall back to chat membership to handle desync where the group member list
        -- was never updated locally (e.g. TMSYN missed because no officer was online).
        local isEmpty    = (#members == 0)
        local chatMember = not isMember and g.channelId and GH.Chat:IsMember(g.channelId, myName)
        if isMember or isOfficer or chatMember or (isEmpty and GH:CanManageTeams()) then
            out[#out + 1] = {
                id        = id,
                name      = g.name,
                members   = members,
                color     = g.color,
                channelId = g.channelId,
                pending   = g.pending,
                createdAt = g.createdAt,
            }
            includedIds[id] = true
        end
    end

    -- Fallback: also surface teams where the group record is entirely missing but the
    -- chat record still exists and lists us as a member.  Determine a candidate groupId:
    --   1. ch.groupId if already stamped, else
    --   2. reverse-lookup from existing groups by channelId, else
    --   3. chatId itself as a provisional key (cleaned up when a real TMSYN arrives).
    for chatId, ch in pairs(GH.DB:GetChats()) do
        local gid = ch.groupId
        if not gid then
            for existingId, g in pairs(GH.DB:GetGroups()) do
                if g.channelId == chatId then gid = existingId; break end
            end
        end
        if not gid then gid = chatId end   -- provisional: use chatId as temp key

        if not includedIds[gid] then
            local isChatMember = false
            for _, n in ipairs(ch.members or {}) do
                if n == myName then isChatMember = true; break end
            end
            if isChatMember then
                if not GH.DB:GetGroups()[gid] then
                    GH.DB:SaveGroup(gid, {
                        name      = ch.name,
                        members   = ch.members,
                        channelId = chatId,
                        color     = "7289DA",
                    })
                end
                out[#out + 1] = {
                    id        = gid,
                    name      = ch.name,
                    members   = ch.members,
                    color     = "7289DA",
                    channelId = chatId,
                }
                includedIds[gid] = true
            end
        end
    end

    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Groups:Get(id)
    return GH.DB:GetGroups()[id]
end

-- Returns all teams stored in the local DB, regardless of membership or rank.
-- Each entry includes isMember = true|false for the current player.
-- Pending (conflict-duplicate) teams are excluded for non-officers.
-- Used by the Teams tab to render the full team browser including Apply buttons.
-- GetAll() is unchanged and continues to be used everywhere else.
function Groups:GetAllForBrowsing()
    local myName    = GH:GetPlayerName()
    local isOfficer = GH:IsOfficer()

    -- Start with the regular GetAll result and tag each entry.
    local existing = Groups:GetAll()
    local seen     = {}
    for _, g in ipairs(existing) do
        local isMem = false
        for _, n in ipairs(g.members or {}) do
            if n == myName then isMem = true; break end
        end
        g.isMember = isMem
        seen[g.id] = true
    end

    -- Add any teams from the DB not returned by GetAll.
    -- Pending teams are only shown to officers (same rule as GetAll).
    for id, g in pairs(GH.DB:GetGroups()) do
        if not seen[id] and (not g.pending or isOfficer) then
            existing[#existing + 1] = {
                id        = id,
                name      = g.name,
                members   = g.members,
                color     = g.color,
                channelId = g.channelId,
                pending   = g.pending,
                createdAt = g.createdAt,
                isMember  = false,
            }
        end
    end

    table.sort(existing, function(a, b) return a.name < b.name end)
    return existing
end

function Groups:Create(name)
    local id = GH.DB:NewId()
    local _, _, rankIndex = GetGuildInfo("player")
    GH.DB:SaveGroup(id, {
        name        = name,
        members     = { GH:GetPlayerName() },
        color       = "7289DA",
        creator     = GH:GetPlayerName(),
        creatorRank = rankIndex or 1,
        createdAt   = time(),
    })
    -- Notify all online officers so they see the new team immediately.
    C_Timer.After(0.5, function()
        local g = GH.DB:GetGroups()[id]
        if g then Groups:_OfficerSync(id, g) end
    end)
    return id
end

function Groups:Rename(id, name)
    local g = GH.DB:GetGroups()[id]
    if g then
        g.name = name
        GH.DB:SaveGroup(id, g)
    end
end

-- Delete team and notify all members they have been removed.
-- Caller must have already checked CanManageTeam(id).
function Groups:Delete(id)
    local g = GH.DB:GetGroups()[id]
    if g then
        local myName = GH:GetPlayerName()
        for _, memberName in ipairs(g.members or {}) do
            if memberName ~= myName then
                Groups:_SendRemoved(id, memberName)
            end
        end
    end
    GH.DB:DeleteGroup(id)
    -- Broadcast deletion so officers remove the team from their local DB.
    local payload = table.concat({ TM_DLT, id }, SEP)
    Groups:_Send(payload)
end

-- Add a member without an invite (used internally after acceptance).
function Groups:AddMember(id, memberName)
    local g = GH.DB:GetGroups()[id]
    if not g then return end
    for _, n in ipairs(g.members) do
        if n == memberName then return end
    end
    g.members[#g.members + 1] = memberName
    GH.DB:SaveGroup(id, g)
    -- Sync full team data to the new member and update watching officers.
    Groups:_SyncToMember(id, g, memberName)
    Groups:_OfficerSync(id, g)
end

-- Remove a member and notify their client.
function Groups:RemoveMember(id, memberName)
    local g = GH.DB:GetGroups()[id]
    if not g then return end
    for i, n in ipairs(g.members) do
        if n == memberName then
            table.remove(g.members, i)
            break
        end
    end
    GH.DB:SaveGroup(id, g)
    Groups:_SendRemoved(id, memberName)
    -- Update watching officers with the new member list.
    Groups:_OfficerSync(id, g)
end

function Groups:InviteAll(id)
    local g = GH.DB:GetGroups()[id]
    if not g then return end
    local myName = GH:GetPlayerName()
    local doInvite = InviteUnit
                  or (C_PartyInfo and C_PartyInfo.InviteUnit)
    if not doInvite then return end
    for _, memberName in ipairs(g.members) do
        if memberName ~= myName then
            local info = GH.GuildData:FindMember(memberName)
            if info and info.online then
                doInvite(info.fullName)
            end
        end
    end
end

function Groups:SetColor(id, hex)
    local g = GH.DB:GetGroups()[id]
    if g then
        g.color = hex
        GH.DB:SaveGroup(id, g)
    end
end

function Groups:SetChannel(id, channelId)
    local g = GH.DB:GetGroups()[id]
    if g then
        g.channelId = channelId
        GH.DB:SaveGroup(id, g)
    end
end

function Groups:SetMemberRole(groupId, memberName, role)
    if not GH:CanManageTeam(groupId) then return end
    local g = GH.DB:GetGroups()[groupId]
    if not g then return end
    g.memberRoles = g.memberRoles or {}
    if role and role ~= "" then
        g.memberRoles[memberName] = role
    else
        g.memberRoles[memberName] = nil
    end
    GH.DB:SaveGroup(groupId, g)
    local payload = table.concat({ TM_ROL, groupId, memberName, role or "" }, SEP)
    Groups:_Send(payload)
    if GH.UI then GH.UI:RefreshTeamRoster(groupId) end
end

-- ── Invite API (called from UI) ───────────────────────────────────────────

-- Officer sends a team invite to an online guild member.
-- Returns true if sent successfully, false otherwise (prints reason).
function Groups:SendInvite(groupId, targetName)
    if not GH:CanManageTeam(groupId) then
        print("|cff7289daGuildHub:|r You do not have permission to invite members to this team.")
        return false
    end
    -- Case-insensitive lookup so "stormart" finds "Stormart"
    local memberInfo = GH.GuildData:FindMember(targetName)
    if not memberInfo then
        print("|cff7289daGuildHub:|r |cffffd700" .. targetName
              .. "|r was not found in the guild roster.")
        return false
    end
    if not memberInfo.online then
        local display = memberInfo.fullName ~= memberInfo.name
                        and memberInfo.fullName or memberInfo.name
        print("|cff7289daGuildHub:|r |cffffd700" .. display
              .. "|r must be online to receive a team invite.")
        return false
    end
    local g = Groups:Get(groupId)
    if not g then return false end
    -- Use canonical short name for the roster entry
    local canonical = memberInfo.name
    for _, n in ipairs(g.members or {}) do
        if n == canonical then
            print("|cff7289daGuildHub:|r " .. canonical .. " is already on this team.")
            return false
        end
    end
    -- Payload target field uses short name; receiver compares against UnitName("player")
    local payload = table.concat(
        { TM_INV, groupId, g.name, GH:GetPlayerName(), canonical }, SEP)
    Groups:_Send(payload)
    local display = memberInfo.fullName ~= memberInfo.name
                    and memberInfo.fullName or memberInfo.name
    print("|cff7289daGuildHub:|r Team invite sent to |cffffd700" .. display .. "|r.")
    return true
end

-- Invitee accepts a pending team invite.
function Groups:AcceptInvite(groupId)
    local invite = Groups.pendingInvites[groupId]
    if not invite then return end
    Groups.pendingInvites[groupId] = nil
    local payload = table.concat({ TM_ACC, groupId, GH:GetPlayerName() }, SEP)
    Groups:_Send(payload)
    print("|cff7289daGuildHub:|r You joined team |cffffd700" .. invite.teamName .. "|r!")
end

-- Invitee declines a pending team invite.
function Groups:DeclineInvite(groupId)
    local invite = Groups.pendingInvites[groupId]
    if not invite then return end
    Groups.pendingInvites[groupId] = nil
    local payload = table.concat({ TM_DEC, groupId, GH:GetPlayerName() }, SEP)
    Groups:_Send(payload)
end

-- Broadcast a check request; online officers respond with each team this player is on.
function Groups:RequestTeamSync()
    if not GH:IsInGuild() then return end
    local payload = table.concat({ TM_CHK, GH:GetPlayerName() }, SEP)
    Groups:_Send(payload)
end

-- ── Internal helpers ──────────────────────────────────────────────────────

function Groups:_Send(payload)
    if #payload > 250 then return end
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if C_ChatInfo then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
end

function Groups:_SyncToMember(groupId, g, targetName)
    local membersStr = table.concat(g.members or {}, ",")
    local payload = table.concat(
        { TM_SYN, groupId, g.name, membersStr, g.channelId or "", targetName }, SEP)
    -- If member list makes it too long, omit it (member can still chat)
    if #payload > 250 then
        payload = table.concat(
            { TM_SYN, groupId, g.name, "", g.channelId or "", targetName }, SEP)
    end
    Groups:_Send(payload)
end

function Groups:_CheckForDuplicate(incomingId, incomingName)
    local normalizedName = incomingName:lower()
    local incomingGroup  = GH.DB:GetGroups()[incomingId]
    if not incomingGroup then return end

    local canonicalId, pendingId

    for id, g in pairs(GH.DB:GetGroups()) do
        if id ~= incomingId and g.name:lower() == normalizedName then
            local incomingTs = incomingGroup.createdAt or 0
            local existingTs = g.createdAt or 0
            if incomingTs < existingTs or (incomingTs == existingTs and incomingId < id) then
                canonicalId = incomingId
                pendingId   = id
            else
                canonicalId = id
                pendingId   = incomingId
            end
            break
        end
    end

    if not pendingId then return end

    local pendingGroup = GH.DB:GetGroups()[pendingId]
    if pendingGroup and not pendingGroup.pending then
        pendingGroup.pending = true
        GH.DB:SaveGroup(pendingId, pendingGroup)
    end

    if GH:IsGuildMaster() then
        if GH.UI and GH.UI.EnqueueConflict then
            GH.UI:EnqueueConflict(pendingId, canonicalId)
        end
    else
        local payload = table.concat({ TM_DPC, pendingId, canonicalId }, SEP)
        Groups:_Send(payload)
    end
end

function Groups:_ExecuteResolution(action, pendingId, canonicalId, newName)
    local pendingGroup   = GH.DB:GetGroups()[pendingId]
    local canonicalGroup = GH.DB:GetGroups()[canonicalId]

    if action == "merge" then
        if pendingGroup and canonicalGroup then
            for _, name in ipairs(pendingGroup.members or {}) do
                local inCanonical = false
                for _, n in ipairs(canonicalGroup.members or {}) do
                    if n == name then inCanonical = true; break end
                end
                if not inCanonical then
                    canonicalGroup.members[#canonicalGroup.members + 1] = name
                end
            end
            GH.DB:SaveGroup(canonicalId, canonicalGroup)
            for _, name in ipairs(pendingGroup.members or {}) do
                Groups:_SyncToMember(canonicalId, canonicalGroup, name)
            end
            Groups:_OfficerSync(canonicalId, canonicalGroup)
        end
        for _, name in ipairs(pendingGroup and pendingGroup.members or {}) do
            Groups:_SendRemoved(pendingId, name)
        end
        GH.DB:DeleteGroup(pendingId)

    elseif action == "keep" then
        if pendingGroup then
            pendingGroup.pending = false
            GH.DB:SaveGroup(pendingId, pendingGroup)
        end

    elseif action == "delete" then
        if pendingGroup then
            for _, name in ipairs(pendingGroup.members or {}) do
                Groups:_SendRemoved(pendingId, name)
            end
        end
        GH.DB:DeleteGroup(pendingId)

    elseif action == "rename" and newName and newName ~= "" then
        if pendingGroup then
            pendingGroup.name    = newName
            pendingGroup.pending = false
            GH.DB:SaveGroup(pendingId, pendingGroup)
            Groups:_OfficerSync(pendingId, pendingGroup)
        end
    end

    if GH.UI then GH.UI:RefreshTeamsGroupList() end
end

function Groups:_SendRemoved(groupId, memberName)
    local payload = table.concat({ TM_REM, groupId, memberName }, SEP)
    Groups:_Send(payload)
end

-- Broadcast team data to all officers without implying membership.
-- Sent on team creation, member changes, and login sync for officer requesters.
function Groups:_OfficerSync(groupId, g)
    local membersStr   = table.concat(g.members or {}, ",")
    local createdAtStr = tostring(g.createdAt or 0)
    local pendingStr   = g.pending and "1" or "0"
    local payload = table.concat(
        { TM_OFC, groupId, g.name, membersStr, g.channelId or "",
          tostring(g.creatorRank or ""), g.creator or "",
          createdAtStr, pendingStr }, SEP)
    if #payload > 250 then
        payload = table.concat(
            { TM_OFC, groupId, g.name, "", g.channelId or "",
              tostring(g.creatorRank or ""), g.creator or "",
              createdAtStr, pendingStr }, SEP)
    end
    Groups:_Send(payload)
end

-- ── Addon message routing ─────────────────────────────────────────────────

function Groups:OnAddonMessage(payload, _)
    -- Quick pre-filter: ignore messages that don't start with "TM"
    if payload:sub(1, 2) ~= "TM" then return end

    local parts = {}
    for p in (payload .. SEP):gmatch("([^" .. SEP .. "]*)" .. SEP) do
        parts[#parts + 1] = p
    end
    if #parts < 1 then return end

    local msgType = parts[1]
    local myName  = GH:GetPlayerName()

    -- ── TMINV: team invite addressed to us ───────────────────────────────
    if msgType == TM_INV then
        if #parts >= 5 and parts[5] == myName then
            local groupId  = parts[2]
            local teamName = parts[3]
            local inviter  = parts[4]
            Groups.pendingInvites[groupId] = { teamName = teamName, inviter = inviter }
            if GH.UI and GH.UI.ShowTeamInvitePopup then
                GH.UI:ShowTeamInvitePopup(groupId, teamName, inviter)
            end
        end

    -- ── TMACC: someone accepted our invite ───────────────────────────────
    elseif msgType == TM_ACC then
        if #parts >= 3 and GH:CanManageTeams() then
            local groupId  = parts[2]
            local accepter = parts[3]
            if accepter == myName then return end   -- our own echo
            local g = Groups:Get(groupId)
            if g then
                local alreadyIn = false
                for _, n in ipairs(g.members or {}) do
                    if n == accepter then alreadyIn = true; break end
                end
                if not alreadyIn then
                    g.members[#g.members + 1] = accepter
                    GH.DB:SaveGroup(groupId, g)
                    if g.channelId then
                        GH.Chat:AddMember(g.channelId, accepter)
                    end
                    Groups:_SyncToMember(groupId, g, accepter)
                    if GH.UI then GH.UI:RefreshTeamsGroupList() end
                    print("|cff7289daGuildHub:|r |cffffd700" .. accepter
                          .. "|r joined " .. g.name .. ".")
                end
            end
        end

    -- ── TMDEC: someone declined our invite ───────────────────────────────
    elseif msgType == TM_DEC then
        if #parts >= 3 and GH:CanManageTeams() then
            local groupId  = parts[2]
            local decliner = parts[3]
            if decliner == myName then return end
            local g = Groups:Get(groupId)
            print("|cff7289daGuildHub:|r |cffffd700" .. decliner
                  .. "|r declined the invite to " .. (g and g.name or "your team") .. ".")
        end

    -- ── TMREM: we were removed from a team ───────────────────────────────
    elseif msgType == TM_REM then
        if #parts >= 3 and parts[3] == myName then
            local groupId = parts[2]
            local g       = GH.DB:GetGroups()[groupId]
            local chanId  = g and g.channelId
            GH.DB:DeleteGroup(groupId)
            -- Remove ourselves from the channel member list locally
            if chanId then
                local ch = GH.DB:GetChat(chanId)
                if ch then
                    for i, n in ipairs(ch.members or {}) do
                        if n == myName then
                            table.remove(ch.members, i)
                            break
                        end
                    end
                    GH.DB:SaveChat(chanId, ch)
                end
            end
            if GH.UI then GH.UI:RefreshTeamsGroupList() end
            print("|cff7289daGuildHub:|r You have been removed from a team.")
        end

    -- ── TMCHK: login sync request — team managers respond ────────────────
    elseif msgType == TM_CHK then
        if #parts >= 2 and GH:CanManageTeams() then
            local requester = parts[2]
            if requester ~= myName then
                -- Stagger replies to avoid everyone flooding at once
                C_Timer.After(math.random(1, 5), function()
                    for groupId, g in pairs(GH.DB:GetGroups()) do
                        local isOnTeam = false
                        for _, n in ipairs(g.members or {}) do
                            if n == requester then isOnTeam = true; break end
                        end

                        if isOnTeam then
                            Groups:_SyncToMember(groupId, g, requester)
                        end
                        -- Always broadcast team data so all guild members can display
                        -- team assignments in the member list, even for teams they
                        -- aren't personally on.
                        Groups:_OfficerSync(groupId, g)
                    end
                end)
            end
        end

    -- ── TMOFC: team roster broadcast — processed by all guild members ───────
    -- All clients store this so the Members tab can show team assignments for
    -- every guild member, not only officers and personal team members.
    elseif msgType == TM_OFC then
        if #parts >= 5 then
            local groupId           = parts[2]
            local teamName          = parts[3]
            local membersStr        = parts[4]
            local channelId         = parts[5] ~= "" and parts[5] or nil
            local creatorRank       = tonumber(parts[6])
            local creator           = (parts[7] and parts[7] ~= "") and parts[7] or nil
            local incomingCreatedAt = tonumber(parts[8]) or 0
            local incomingPending   = parts[9] == "1"

            local members = {}
            if membersStr ~= "" then
                for n in (membersStr .. ","):gmatch("([^,]*),") do
                    if n ~= "" then members[#members + 1] = n end
                end
            end

            local existing = GH.DB:GetGroups()[groupId]
            GH.DB:SaveGroup(groupId, {
                name        = teamName,
                members     = #members > 0 and members or (existing and existing.members or {}),
                channelId   = channelId or (existing and existing.channelId),
                color       = existing and existing.color or "7289DA",
                creator     = creator or (existing and existing.creator),
                creatorRank = creatorRank or (existing and existing.creatorRank),
                createdAt   = incomingCreatedAt ~= 0 and incomingCreatedAt
                              or (existing and existing.createdAt) or 0,
                pending     = incomingPending or (existing and existing.pending) or false,
            })

            if channelId and not GH.DB:GetChat(channelId) then
                GH.DB:SaveChat(channelId, {
                    name     = teamName,
                    members  = members,
                    messages = {},
                })
            end

            -- Duplicate conflict detection only makes sense for officers who manage teams.
            if GH:IsOfficer() then
                Groups:_CheckForDuplicate(groupId, teamName)
            end
            if GH.UI then GH.UI:RefreshTeamsGroupList() end
        end

    -- ── TMDLT: broadcast team deletion ───────────────────────────────────
    elseif msgType == TM_DLT then
        if #parts >= 2 then
            local groupId = parts[2]
            -- Remove from local DB if present (applies to watching officers and members).
            if GH.DB:GetGroups()[groupId] then
                GH.DB:DeleteGroup(groupId)
                if GH.UI then GH.UI:RefreshTeamsGroupList() end
            end
        end

    -- ── TMDPC: duplicate team conflict notification (received by GM) ─────────
    elseif msgType == TM_DPC then
        if GH:IsGuildMaster() and #parts >= 3 then
            local pendingId   = parts[2]
            local canonicalId = parts[3]
            if GH.DB:GetGroups()[pendingId] and GH.DB:GetGroups()[canonicalId] then
                if GH.UI and GH.UI.EnqueueConflict then
                    GH.UI:EnqueueConflict(pendingId, canonicalId)
                end
            end
        end

    -- ── TMGMR: GM resolution — all officers execute ──────────────────────────
    elseif msgType == TM_GMR then
        if GH:IsOfficer() and #parts >= 4 then
            local action      = parts[2]
            local pendingId   = parts[3]
            local canonicalId = parts[4]
            local newName     = (parts[5] and parts[5] ~= "") and parts[5] or nil
            Groups:_ExecuteResolution(action, pendingId, canonicalId, newName)
        end

    -- ── TMSYN: team data synced to us ────────────────────────────────────
    elseif msgType == TM_SYN then
        if #parts >= 6 and parts[6] == myName then
            local groupId    = parts[2]
            local teamName   = parts[3]
            local membersStr = parts[4]
            local channelId  = parts[5] ~= "" and parts[5] or nil

            -- Parse member list (may be empty if truncated)
            local members = {}
            if membersStr ~= "" then
                for n in (membersStr .. ","):gmatch("([^,]*),") do
                    if n ~= "" then members[#members + 1] = n end
                end
            end
            -- Ensure we're listed (in case list was truncated)
            local hasMe = false
            for _, n in ipairs(members) do
                if n == myName then hasMe = true; break end
            end
            if not hasMe then members[#members + 1] = myName end

            -- Remove any provisional stub that was using this channelId as a temp key
            -- (created by GetAll when no group record existed and TMSYN hadn't arrived).
            if channelId and channelId ~= groupId then
                local provisional = GH.DB:GetGroups()[channelId]
                if provisional and provisional.channelId == channelId then
                    GH.DB:DeleteGroup(channelId)
                end
            end

            -- Save / update local team record
            local existing = GH.DB:GetGroups()[groupId]
            GH.DB:SaveGroup(groupId, {
                name      = teamName,
                members   = #members > 0 and members or (existing and existing.members or {}),
                channelId = channelId or (existing and existing.channelId),
                color     = existing and existing.color or "7289DA",
            })

            -- Bootstrap or update channel record; stamp groupId so chats can be linked
            -- back to their group even if the group record itself is later lost.
            if channelId then
                local existingChat = GH.DB:GetChat(channelId)
                if not existingChat then
                    GH.DB:SaveChat(channelId, {
                        name     = teamName,
                        members  = members,
                        messages = {},
                        groupId  = groupId,
                    })
                elseif not existingChat.groupId then
                    existingChat.groupId = groupId
                    GH.DB:SaveChat(channelId, existingChat)
                end
            end

            if GH.UI then GH.UI:RefreshTeamsGroupList() end
        end

    -- ── TMROL: team member role assignment ───────────────────────────────
    elseif msgType == TM_ROL then
        if #parts >= 4 then
            local groupId    = parts[2]
            local memberName = parts[3]
            local role       = parts[4] ~= "" and parts[4] or nil
            local g = GH.DB:GetGroups()[groupId]
            if g then
                g.memberRoles = g.memberRoles or {}
                g.memberRoles[memberName] = role
                GH.DB:SaveGroup(groupId, g)
                if GH.UI then GH.UI:RefreshTeamRoster(groupId) end
            end
        end
    end
end
