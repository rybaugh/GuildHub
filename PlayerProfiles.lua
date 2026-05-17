-- GuildHub - PlayerProfiles
-- Manages per-player extended data: join date, rank history, custom notes,
-- alt/main groupings, birthdays, and ban list.

local GH       = GuildHub
local Profiles = GH.Profiles

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function Enabled()
    return GH.DB:GetSetting("rosterProfilesEnabled") ~= false
end

local function FormatDate(ts)
    if not ts then return "Unknown" end
    return date("%b %d, %Y", ts)
end
Profiles.FormatDate = FormatDate

-- ── Initialisation ────────────────────────────────────────────────────────────

function Profiles:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event)
        if event == "GUILD_ROSTER_UPDATE" then
            Profiles:_OnRosterUpdate()
        elseif event == "PLAYER_LOGIN" then
            C_Timer.After(5, function() Profiles:_OnLogin() end)
        end
    end)
end

-- ── Login handler ─────────────────────────────────────────────────────────────

function Profiles:_OnLogin()
    if not Enabled() then return end
    if not GH.DB._activeGuild then return end

    -- Show GuildHub at logon if setting is enabled
    if GH.DB:GetSetting("showAtLogon") then
        local hasChanges = #GH.DB:GetActivityLog() > 0
        local onlyIfChanges = GH.DB:GetSetting("onlyShowIfLogChanges")
        if not onlyIfChanges or hasChanges then
            C_Timer.After(2, function()
                if GH.UI and GH.UI.Show then GH.UI:Show() end
                if GH.UI and GH.UI.window then
                    GH.UI.window.SelectTab("Activity")
                end
            end)
        end
    end

    -- Check upcoming birthdays and anniversaries
    self:_CheckAnnouncements()
end

-- ── Announcement scanner ──────────────────────────────────────────────────────

function Profiles:_CheckAnnouncements()
    if not Enabled() then return end
    local announceAnn  = GH.DB:GetSetting("announceAnniversaries") ~= false
    local announceBday = GH.DB:GetSetting("announceBirthdays") ~= false
    local onlyMain     = GH.DB:GetSetting("onlyMainForBdayAnn") == true
    local daysAhead    = GH.DB:GetSetting("announceEventsDays") or 14
    local addCal       = GH.DB:GetSetting("addEventsToCalendar") == true

    if not announceAnn and not announceBday then return end

    local now     = GH:GetTimestamp()
    local nowDate = date("*t")
    local year    = tonumber(nowDate.year) or 2026

    for name, profile in pairs(GH.DB:GetAllPlayerProfiles()) do
        -- Skip alts when onlyMain is set
        local skip = false
        if onlyMain then
            local group = self:GetAltGroup(name)
            if group and group.main ~= name then skip = true end
        end

        if not skip then
            -- Anniversary check
            if announceAnn and profile.joinDate and profile.joinDateVerified then
                local jt = date("*t", profile.joinDate)
                local annTs = time({
                    year = year, month = jt.month, day = jt.day,
                    hour = 12,   min   = 0,         sec = 0,
                })
                local daysUntil = math.floor((annTs - now) / 86400)
                if daysUntil >= 0 and daysUntil <= daysAhead then
                    local years = year - (jt.year or year)
                    local when  = daysUntil == 0 and "TODAY"
                                  or (daysUntil == 1 and "tomorrow"
                                  or ("in " .. daysUntil .. " days"))
                    print("|cff7289daGuildHub:|r " .. name .. "'s " ..
                          "|cfff2c617" .. years .. "-year anniversary|r is " .. when .. "!")
                    if addCal and daysUntil == 0 then
                        self:AddAnniversaryToCalendar(name)
                    end
                end
            end

            -- Birthday check
            if announceBday and profile.birthday then
                local b = profile.birthday
                local bdayTs = time({
                    year = year, month = b.month, day = b.day,
                    hour = 12,   min   = 0,        sec = 0,
                })
                local daysUntil = math.floor((bdayTs - now) / 86400)
                if daysUntil >= 0 and daysUntil <= daysAhead then
                    local when = daysUntil == 0 and "TODAY"
                                 or (daysUntil == 1 and "tomorrow"
                                 or ("in " .. daysUntil .. " days"))
                    print("|cff7289daGuildHub:|r " .. name ..
                          "'s birthday is " .. when .. "!")
                    if addCal and daysUntil == 0 then
                        self:AddBirthdayToCalendar(name)
                    end
                end
            end
        end
    end
end

-- Called on every GUILD_ROSTER_UPDATE to seed join dates for new members
-- and check returning banned players.
function Profiles:_OnRosterUpdate()
    if not Enabled() then return end
    if not GH.DB._activeGuild then return end

    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    local now   = GH:GetTimestamp()

    for i = 1, total do
        local name, _, _, _, _, _, note, officerNote, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local shortName = name:match("^([^%-]+)")
            local profile   = GH.DB:GetPlayerProfile(shortName)

            -- Seed join date only if completely unknown
            if not profile.joinDate then
                -- WoW doesn't expose join date directly; mark as unverified placeholder
                profile.joinDate         = now
                profile.joinDateVerified = false
                GH.DB:SavePlayerProfile(shortName, profile)
            end

            -- Check if a banned player just rejoined
            if profile.isBanned then
                GH.ActivityLog:Add("BAN_REJOIN", shortName, now, {
                    banReason = profile.banReason,
                    bannedBy  = profile.bannedBy,
                })
                -- Alert the current player if they are an officer
                if GH:IsOfficer() then
                    print("|cff7289daGuildHub:|r |cffff4444[Ban Alert]|r " .. shortName ..
                          " has rejoined the guild. Reason: " .. (profile.banReason or "none"))
                end
            end
        end
    end
end

-- ── Profile getters / setters ─────────────────────────────────────────────────

function Profiles:GetProfile(name)
    return GH.DB:GetPlayerProfile(name)
end

function Profiles:SetJoinDate(name, ts, verified)
    local profile = GH.DB:GetPlayerProfile(name)
    profile.joinDate         = ts
    profile.joinDateVerified = verified ~= false

    -- Insert into history if it's a new entry
    local hist = profile.joinDateHistory
    if #hist == 0 or hist[#hist].ts ~= ts then
        table.insert(hist, { ts = ts, verified = profile.joinDateVerified })
    end

    GH.DB:SavePlayerProfile(name, profile)

    -- Auto-tag the guild note if the feature is enabled
    if GH.DB:GetSetting("rosterAutoJoinDate") and verified ~= false then
        self:AutoTagJoinDate(name, ts)
    end

    GH.ProfileSync:BroadcastJoinDate(name, ts, profile.joinDateVerified)
end

function Profiles:AddRankHistory(name, rankName, rankIndex, ts)
    local profile = GH.DB:GetPlayerProfile(name)
    local hist    = profile.rankHistory
    -- Only append if different from the last entry
    if #hist == 0 or hist[#hist].rankName ~= rankName then
        table.insert(hist, { rankName = rankName, rankIndex = rankIndex, ts = ts or GH:GetTimestamp() })
    end
    GH.DB:SavePlayerProfile(name, profile)
    GH.ProfileSync:BroadcastRankHistory(name, rankName, rankIndex, ts or GH:GetTimestamp())
end

function Profiles:SetBirthday(name, month, day, year)
    local profile    = GH.DB:GetPlayerProfile(name)
    profile.birthday = { month = month, day = day, year = year }
    GH.DB:SavePlayerProfile(name, profile)
    GH.ProfileSync:BroadcastBirthday(name, month, day, year)
end

function Profiles:SetCustomNote(name, text, editor)
    local profile            = GH.DB:GetPlayerProfile(name)
    profile.customNote       = (text or ""):sub(1, 150)
    profile.customNoteEditor = editor or GH:GetPlayerName()
    profile.customNoteTs     = GH:GetTimestamp()
    GH.DB:SavePlayerProfile(name, profile)
    GH.ProfileSync:BroadcastCustomNote(name, profile.customNote, profile.customNoteEditor, profile.customNoteTs)
end

-- ── Alt / Main management ─────────────────────────────────────────────────────

function Profiles:GetAltGroup(name)
    local profile = GH.DB:GetPlayerProfile(name)
    if not profile.altGroupId then return nil end
    return GH.DB:GetAltGroup(profile.altGroupId)
end

function Profiles:GetMain(name)
    local group = self:GetAltGroup(name)
    return group and group.main
end

function Profiles:GetAlts(name)
    local group = self:GetAltGroup(name)
    if not group then return {} end
    local alts = {}
    for _, alt in ipairs(group.alts or {}) do
        if alt ~= name then alts[#alts + 1] = alt end
    end
    return alts
end

function Profiles:SetMain(mainName, ts)
    local existing = self:GetAltGroup(mainName)
    local groupId, group

    if existing then
        -- find which group this person is in and set them as main
        local profile = GH.DB:GetPlayerProfile(mainName)
        groupId = profile.altGroupId
        group   = GH.DB:GetAltGroup(groupId)
        group.main = mainName
        group.ts   = ts or GH:GetTimestamp()
    else
        groupId = GH.DB:NewId()
        group   = { main = mainName, alts = { mainName }, ts = ts or GH:GetTimestamp() }
        local profile = GH.DB:GetPlayerProfile(mainName)
        profile.altGroupId = groupId
        GH.DB:SavePlayerProfile(mainName, profile)
    end

    GH.DB:SaveAltGroup(groupId, group)
    GH.ProfileSync:BroadcastAltGroup(groupId, group)
end

function Profiles:AddAlt(mainName, altName, ts)
    local mainProfile = GH.DB:GetPlayerProfile(mainName)
    local groupId     = mainProfile.altGroupId

    if not groupId then
        -- Create a new group for the main first
        self:SetMain(mainName, ts)
        mainProfile = GH.DB:GetPlayerProfile(mainName)
        groupId     = mainProfile.altGroupId
    end

    local group = GH.DB:GetAltGroup(groupId)
    if not group then return end

    -- Add alt if not already in group
    local found = false
    for _, n in ipairs(group.alts) do
        if n == altName then found = true; break end
    end
    if not found then
        table.insert(group.alts, altName)
        group.ts = ts or GH:GetTimestamp()
    end

    -- Link alt profile to the group
    local altProfile = GH.DB:GetPlayerProfile(altName)
    altProfile.altGroupId = groupId
    GH.DB:SavePlayerProfile(altName, altProfile)

    GH.DB:SaveAltGroup(groupId, group)
    GH.ProfileSync:BroadcastAltGroup(groupId, group)
end

function Profiles:RemoveFromAltGroup(name)
    local profile = GH.DB:GetPlayerProfile(name)
    local groupId = profile.altGroupId
    if not groupId then return end

    local group = GH.DB:GetAltGroup(groupId)
    if not group then return end

    -- Remove from the alts list
    local newAlts = {}
    for _, n in ipairs(group.alts or {}) do
        if n ~= name then newAlts[#newAlts + 1] = n end
    end
    group.alts = newAlts
    group.ts   = GH:GetTimestamp()

    -- If this was the main, promote the first remaining alt
    if group.main == name then
        group.main = newAlts[1]
    end

    -- If group is now empty or has 1 member, clean up
    if #newAlts <= 1 then
        if newAlts[1] then
            local lastProfile = GH.DB:GetPlayerProfile(newAlts[1])
            lastProfile.altGroupId = nil
            GH.DB:SavePlayerProfile(newAlts[1], lastProfile)
        end
        GH.DB:DeleteAltGroup(groupId)
    else
        GH.DB:SaveAltGroup(groupId, group)
        GH.ProfileSync:BroadcastAltGroup(groupId, group)
    end

    profile.altGroupId = nil
    GH.DB:SavePlayerProfile(name, profile)
end

-- Returns a sorted list of all alt groups (each entry has .main and .alts)
function Profiles:GetAllAltGroups()
    local groups = GH.DB:GetAltGroups()
    local out    = {}
    for id, g in pairs(groups) do
        out[#out + 1] = { id = id, main = g.main, alts = g.alts, ts = g.ts }
    end
    table.sort(out, function(a, b)
        return (a.main or ""):lower() < (b.main or ""):lower()
    end)
    return out
end

-- ── Ban management ────────────────────────────────────────────────────────────

function Profiles:BanPlayer(name, reason, bannedBy, ts)
    local profile    = GH.DB:GetPlayerProfile(name)
    profile.isBanned = true
    profile.banReason = reason or ""
    profile.banDate   = ts or GH:GetTimestamp()
    profile.bannedBy  = bannedBy or GH:GetPlayerName()
    GH.DB:SavePlayerProfile(name, profile)

    GH.ActivityLog:Add("BAN", name, profile.banDate, {
        reason   = profile.banReason,
        bannedBy = profile.bannedBy,
    })
    GH.ProfileSync:BroadcastBan(name, profile.banReason, profile.bannedBy, profile.banDate)
end

function Profiles:UnbanPlayer(name, ts)
    local profile    = GH.DB:GetPlayerProfile(name)
    profile.isBanned = false
    profile.banReason = nil
    profile.banDate   = nil
    profile.bannedBy  = nil
    GH.DB:SavePlayerProfile(name, profile)

    GH.ActivityLog:Add("UNBAN", name, ts or GH:GetTimestamp(), {})
    GH.ProfileSync:BroadcastUnban(name, ts or GH:GetTimestamp())
end

function Profiles:IsBanned(name)
    local profile = GH.DB:GetPlayerProfile(name)
    return profile and profile.isBanned == true
end

function Profiles:GetBannedPlayers()
    local out = {}
    for name, profile in pairs(GH.DB:GetAllPlayerProfiles()) do
        if profile.isBanned then
            out[#out + 1] = { name = name, reason = profile.banReason,
                               date = profile.banDate, bannedBy = profile.bannedBy }
        end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

-- ── Auto join-date tagging ────────────────────────────────────────────────────

function Profiles:AutoTagJoinDate(name, ts)
    if not GH:IsOfficer() then return end
    local target  = GH.DB:GetSetting("rosterJoinDateTarget") or "custom"
    local dateStr = "[Joined: " .. FormatDate(ts) .. "]"

    if target == "custom" then
        -- Store in our own custom note; no guild API call needed
        local profile = GH.DB:GetPlayerProfile(name)
        if not (profile.customNote and profile.customNote:find("%[Joined:")) then
            local newNote = ((profile.customNote or "") ~= "" and (profile.customNote .. " ") or "")
                            .. dateStr
            self:SetCustomNote(name, newNote:sub(1, 150), GH:GetPlayerName())
        end
        return
    end

    -- For public/officer notes we need a roster index
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, total do
        local rName = GetGuildRosterInfo(i)
        if rName and rName:match("^([^%-]+)") == name then
            if target == "public" then
                local _, _, _, _, _, _, note = GetGuildRosterInfo(i)
                if not (note and note:find("%[Joined:")) then
                    GuildRosterSetPublicNote(i, ((note or "") .. " " .. dateStr):sub(1, 31))
                end
            elseif target == "officer" then
                local _, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
                if not (officerNote and officerNote:find("%[Joined:")) then
                    GuildRosterSetOfficerNote(i, ((officerNote or "") .. " " .. dateStr):sub(1, 31))
                end
            end
            break
        end
    end
end

-- ── Calendar integration ──────────────────────────────────────────────────────

function Profiles:AddBirthdayToCalendar(name)
    local profile = GH.DB:GetPlayerProfile(name)
    if not profile.birthday then return end
    local b = profile.birthday
    local year = tonumber(date("%Y"))

    if C_Calendar and C_Calendar.CreatePlayerEvent then
        pcall(function()
            C_Calendar.CreatePlayerEvent()
            C_Calendar.EventSetTitle(name .. "'s Birthday")
            C_Calendar.EventSetDescription("GuildHub: Happy birthday to " .. name .. "!")
            C_Calendar.EventSetDate(b.month, b.day, year)
            C_Calendar.EventSetTime(12, 0)
            C_Calendar.EventSave()
        end)
    end
end

function Profiles:AddAnniversaryToCalendar(name)
    local profile = GH.DB:GetPlayerProfile(name)
    if not profile.joinDate then return end
    local jt    = date("*t", profile.joinDate)
    local year  = tonumber(date("%Y"))
    local years = year - (jt.year or year)

    if C_Calendar and C_Calendar.CreatePlayerEvent then
        pcall(function()
            C_Calendar.CreatePlayerEvent()
            C_Calendar.EventSetTitle(name .. " — " .. years .. " Year Anniversary")
            C_Calendar.EventSetDescription("GuildHub: " .. name .. " has been a member for " .. years .. " year(s)!")
            C_Calendar.EventSetDate(jt.month, jt.day, year)
            C_Calendar.EventSetTime(12, 0)
            C_Calendar.EventSave()
        end)
    end
end

-- ── Sync receive handlers (called by ProfileSync) ─────────────────────────────

function Profiles:ReceiveJoinDate(name, ts, verified, sender)
    local profile = GH.DB:GetPlayerProfile(name)
    local existing = profile.joinDate or 0
    -- Accept if newer or if existing is unverified and incoming is verified
    if ts > existing or (verified and not profile.joinDateVerified) then
        profile.joinDate         = ts
        profile.joinDateVerified = verified
        local hist = profile.joinDateHistory
        if #hist == 0 or hist[#hist].ts ~= ts then
            table.insert(hist, { ts = ts, verified = verified })
        end
        GH.DB:SavePlayerProfile(name, profile)
    end
end

function Profiles:ReceiveRankHistory(name, rankName, rankIndex, ts, sender)
    local profile = GH.DB:GetPlayerProfile(name)
    local hist    = profile.rankHistory
    for _, entry in ipairs(hist) do
        if entry.ts == ts and entry.rankName == rankName then return end
    end
    table.insert(hist, { rankName = rankName, rankIndex = rankIndex, ts = ts })
    table.sort(hist, function(a, b) return a.ts < b.ts end)
    -- Strip consecutive same-rankName entries that spurious broadcasts can produce
    local deduped = { hist[1] }
    for i = 2, #hist do
        if hist[i].rankName ~= deduped[#deduped].rankName then
            deduped[#deduped + 1] = hist[i]
        end
    end
    profile.rankHistory = deduped
    GH.DB:SavePlayerProfile(name, profile)
end

function Profiles:ReceiveBirthday(name, month, day, year, sender)
    local profile    = GH.DB:GetPlayerProfile(name)
    profile.birthday = { month = month, day = day, year = year }
    GH.DB:SavePlayerProfile(name, profile)
end

function Profiles:ReceiveCustomNote(name, note, editor, ts, sender)
    local profile = GH.DB:GetPlayerProfile(name)
    -- Accept newer notes only
    if not profile.customNoteTs or ts >= profile.customNoteTs then
        profile.customNote       = (note or ""):sub(1, 150)
        profile.customNoteEditor = editor
        profile.customNoteTs     = ts
        GH.DB:SavePlayerProfile(name, profile)
    end
end

function Profiles:ReceiveAltGroup(groupId, main, alts, ts, sender)
    local existing = GH.DB:GetAltGroup(groupId)
    -- Accept if newer
    if not existing or ts >= (existing.ts or 0) then
        local group = { main = main, alts = alts, ts = ts }
        GH.DB:SaveAltGroup(groupId, group)
        -- Update profile links
        for _, n in ipairs(alts) do
            local profile = GH.DB:GetPlayerProfile(n)
            profile.altGroupId = groupId
            GH.DB:SavePlayerProfile(n, profile)
        end
    end
end

function Profiles:ReceiveBan(name, reason, bannedBy, ts, sender)
    if not GH:IsOfficer() then return end
    local profile = GH.DB:GetPlayerProfile(name)
    if not profile.banDate or ts >= profile.banDate then
        profile.isBanned  = true
        profile.banReason = reason
        profile.banDate   = ts
        profile.bannedBy  = bannedBy
        GH.DB:SavePlayerProfile(name, profile)
    end
end

function Profiles:ReceiveUnban(name, ts, sender)
    local profile = GH.DB:GetPlayerProfile(name)
    if profile.isBanned and (not profile.banDate or ts >= profile.banDate) then
        profile.isBanned  = false
        profile.banReason = nil
        profile.banDate   = nil
        profile.bannedBy  = nil
        GH.DB:SavePlayerProfile(name, profile)
    end
end
