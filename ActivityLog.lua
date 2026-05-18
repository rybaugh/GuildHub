-- GuildHub - ActivityLog
-- Detects guild roster changes and builds a persistent activity log.
-- Diffs snapshots on GUILD_ROSTER_UPDATE to find joins, leaves, promotions,
-- demotions, level-ups, and note changes.

local GH          = GuildHub
local ActivityLog = GH.ActivityLog

-- Snapshot of the previous roster state: [name] = {rankIndex, level, note, officerNote}
local _prevSnapshot   = {}
local _initialised    = false
local _pendingTimer   = false  -- debounce flag so rapid GUILD_ROSTER_UPDATE events collapse
local _postInitPruned = false  -- pruning runs once after the first real diff

-- Registered UI callbacks notified when new entries are added.
local _callbacks = {}

-- ── Event type constants ──────────────────────────────────────────────────────

ActivityLog.TYPES = {
    JOIN            = "JOIN",
    REJOIN          = "REJOIN",
    LEAVE           = "LEAVE",
    KICK            = "KICK",
    PROMOTE         = "PROMOTE",
    DEMOTE          = "DEMOTE",
    LEVEL_UP        = "LEVEL_UP",
    NOTE_CHANGE     = "NOTE_CHANGE",
    OFFICER_NOTE    = "OFFICER_NOTE",
    BAN_REJOIN      = "BAN_REJOIN",
    BAN             = "BAN",
    UNBAN           = "UNBAN",
    NAME_CHANGE     = "NAME_CHANGE",
}

-- Icons used in the Activity tab UI.
ActivityLog.TYPE_ICON = {
    JOIN         = "Interface/Icons/Achievement_GuildPerk_HaveGroupWillTravel",
    REJOIN       = "Interface/Icons/Spell_Holy_Resurrection",
    LEAVE        = "Interface/Icons/Ability_Rogue_Sprint",
    KICK         = "Interface/Icons/Ability_Warrior_Challange",
    PROMOTE      = "Interface/Icons/Achievement_GuildPerk_MassResurrection",
    DEMOTE       = "Interface/Icons/Ability_Druid_CatFormClaw",
    LEVEL_UP     = "Interface/Icons/XP_Icon",
    NOTE_CHANGE  = "Interface/Icons/INV_Misc_Note_01",
    OFFICER_NOTE = "Interface/Icons/INV_Misc_Note_06",
    BAN_REJOIN   = "Interface/Icons/Ability_Warrior_Challange",
    BAN          = "Interface/Icons/Spell_Shadow_NetherTear",
    UNBAN        = "Interface/Icons/Spell_Holy_BlessingOfSalvagation",
    NAME_CHANGE  = "Interface/Icons/Inv_Misc_QuestionMark",
}

-- ── Initialisation ────────────────────────────────────────────────────────────

function ActivityLog:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function(_, event)
        if event ~= "GUILD_ROSTER_UPDATE" then return end
        -- Debounce: collapse rapid-fire events into one call 0.5 s after the last.
        -- This also ensures GetGuildRosterInfo returns fresh data, not a stale snapshot.
        if _pendingTimer then return end
        _pendingTimer = true
        C_Timer.After(0.5, function()
            _pendingTimer = false
            ActivityLog:_OnRosterUpdate()
        end)
    end)

    -- Periodic scan timer: force a roster request + diff on a configurable interval.
    -- This catches events that don't fire GUILD_ROSTER_UPDATE reliably (e.g. level-ups
    -- for offline members, note edits by a GM while we're in a dungeon, etc.)
    C_Timer.After(20, function() ActivityLog:_StartScanTimer() end)
end

function ActivityLog:_StartScanTimer()
    local function Tick()
        local interval = GH.DB:GetSetting("scanIntervalSecs") or 30
        if interval < 10 then interval = 10 end
        if GH:IsInGuild() and GH.DB._activeGuild then
            -- Request fresh data; GUILD_ROSTER_UPDATE will fire and trigger the diff.
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            else
                local fn = rawget(_G, "GuildRoster")
                if fn then fn() end
            end
        end
        C_Timer.After(interval, Tick)
    end
    local interval = GH.DB:GetSetting("scanIntervalSecs") or 30
    C_Timer.After(interval, Tick)
end

-- ── Snapshot diff ─────────────────────────────────────────────────────────────

function ActivityLog:_BuildSnapshot()
    local snap = {}
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, total do
        local name, rankName, rankIndex, level, _, _, note, officerNote = GetGuildRosterInfo(i)
        if name then
            snap[name] = {
                rankName    = rankName or "",
                rankIndex   = rankIndex or 0,
                level       = level or 1,
                note        = note or "",
                officerNote = officerNote or "",
            }
        end
    end
    return snap
end

function ActivityLog:_OnRosterUpdate()
    if GH.DB:GetSetting("rosterProfilesEnabled") == false then return end
    if not GH.DB._activeGuild then return end

    local now  = GH:GetTimestamp()
    local snap = self:_BuildSnapshot()

    if not _initialised then
        local size = 0
        for _ in pairs(snap) do size = size + 1 end
        if size == 0 then return end
        _prevSnapshot = snap
        _initialised  = true
        self:_PruneSpuriousLoginEvents()
        self:_PruneSpuriousRankHistory()
        return
    end

    local prev = _prevSnapshot

    -- Detect leaves/kicks: in prev but not in snap
    for name, data in pairs(prev) do
        if not snap[name] then
            -- Can't reliably distinguish kick from leave without officer log access
            -- Use LEAVE as default; BAN_REJOIN overrides when ban data exists
            self:Add(self.TYPES.LEAVE, name, now, { rank = data.rankName })
            -- Record in rank history as "left"
            local profile = GH.DB:GetPlayerProfile(name)
            profile.joinDate = profile.joinDate  -- preserve existing
            GH.DB:SavePlayerProfile(name, profile)
        end
    end

    -- Detect joins/promotions/demotions/level-ups/note changes
    for name, data in pairs(snap) do
        local old = prev[name]
        if not old then
            -- New member
            local profile = GH.DB:GetPlayerProfile(name)
            local evType  = (profile.joinDate and
                             (now - profile.joinDate) > 86400)
                            and self.TYPES.REJOIN or self.TYPES.JOIN
            self:Add(evType, name, now, { rank = data.rankName })

            -- Set or update join date
            if evType == self.TYPES.JOIN then
                GH.Profiles:SetJoinDate(name, now, false)
            end

            -- Seed first rank history entry
            GH.Profiles:AddRankHistory(name, data.rankName, data.rankIndex, now)

        else
            -- Existing member — check for changes
            if data.rankIndex < old.rankIndex then
                self:Add(self.TYPES.PROMOTE, name, now, {
                    from = old.rankName, to = data.rankName
                })
                GH.Profiles:AddRankHistory(name, data.rankName, data.rankIndex, now)

            elseif data.rankIndex > old.rankIndex then
                self:Add(self.TYPES.DEMOTE, name, now, {
                    from = old.rankName, to = data.rankName
                })
                GH.Profiles:AddRankHistory(name, data.rankName, data.rankIndex, now)
            end

            if data.level > old.level then
                self:Add(self.TYPES.LEVEL_UP, name, now, {
                    from = old.level, to = data.level
                })
            end

            if data.note ~= old.note then
                self:Add(self.TYPES.NOTE_CHANGE, name, now, {
                    from = old.note, to = data.note
                })
            end

            if data.officerNote ~= old.officerNote and GH:IsOfficer() then
                self:Add(self.TYPES.OFFICER_NOTE, name, now, {
                    from = old.officerNote, to = data.officerNote
                })
            end
        end
    end

    _prevSnapshot = snap
    if not _postInitPruned then
        _postInitPruned = true
        self:_PruneSpuriousLoginEvents()
    end
    self:_NotifyCallbacks()
end

function ActivityLog:_PruneSpuriousLoginEvents()
    local log = GH.DB:GetActivityLog()
    if #log == 0 then return end

    -- Count JOIN/LEAVE events per exact timestamp.
    local tsCounts = {}
    for _, entry in ipairs(log) do
        if entry.type == "JOIN" or entry.type == "LEAVE" or entry.type == "REJOIN" then
            tsCounts[entry.ts] = (tsCounts[entry.ts] or 0) + 1
        end
    end

    -- 5+ events at the same second is impossible organically; mark as spurious.
    local spurious = {}
    local found    = false
    for ts, count in pairs(tsCounts) do
        if count >= 5 then
            spurious[ts] = true
            found = true
        end
    end
    if not found then return end

    -- Rebuild log without the spurious JOIN/LEAVE entries.
    local cleaned = {}
    for _, entry in ipairs(log) do
        local isBadType = entry.type == "JOIN" or entry.type == "LEAVE" or entry.type == "REJOIN"
        if not (isBadType and spurious[entry.ts]) then
            cleaned[#cleaned + 1] = entry
        end
    end
    GH.DB:SetActivityLog(cleaned)
end

function ActivityLog:_PruneSpuriousRankHistory()
    local profiles = GH.DB:GetAllPlayerProfiles()
    for name, profile in pairs(profiles) do
        local hist = profile.rankHistory
        if type(hist) == "table" and #hist >= 2 then
            table.sort(hist, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
            local pruned = { hist[1] }
            for i = 2, #hist do
                if hist[i].rankName ~= pruned[#pruned].rankName then
                    pruned[#pruned + 1] = hist[i]
                end
            end
            if #pruned ~= #hist then
                profile.rankHistory = pruned
                GH.DB:SavePlayerProfile(name, profile)
            end
        end
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ActivityLog:Add(eventType, playerName, ts, detail)
    local entry = {
        type   = eventType,
        player = playerName,
        ts     = ts or GH:GetTimestamp(),
        detail = detail or {},
    }
    GH.DB:AddActivityLog(entry)
    self:_NotifyCallbacks()
end

function ActivityLog:GetLog(filter)
    local log = GH.DB:GetActivityLog()
    if not filter then
        -- Return newest first
        local out = {}
        for i = #log, 1, -1 do out[#out + 1] = log[i] end
        return out
    end

    local out = {}
    for i = #log, 1, -1 do
        local entry = log[i]
        local ok    = true
        if filter.types and not filter.types[entry.type] then ok = false end
        if filter.name  and not entry.player:lower():find(filter.name:lower(), 1, true) then
            ok = false
        end
        if ok then out[#out + 1] = entry end
    end
    return out
end

function ActivityLog:FormatEntry(entry)
    local t = entry.type
    local p = entry.player or "?"
    local d = entry.detail or {}

    if t == self.TYPES.JOIN then
        return p .. " joined the guild"
    elseif t == self.TYPES.REJOIN then
        return p .. " rejoined the guild"
    elseif t == self.TYPES.LEAVE then
        return p .. " left the guild"
    elseif t == self.TYPES.KICK then
        local by = d.actor and (" (by " .. d.actor .. ")") or ""
        return p .. " was kicked" .. by
    elseif t == self.TYPES.PROMOTE then
        return p .. " was promoted: " .. (d.from or "?") .. " -> " .. (d.to or "?")
    elseif t == self.TYPES.DEMOTE then
        return p .. " was demoted: " .. (d.from or "?") .. " -> " .. (d.to or "?")
    elseif t == self.TYPES.LEVEL_UP then
        return p .. " reached level " .. (d.to or "?")
    elseif t == self.TYPES.NOTE_CHANGE then
        return p .. " note changed"
    elseif t == self.TYPES.OFFICER_NOTE then
        return p .. " officer note changed"
    elseif t == self.TYPES.BAN_REJOIN then
        return "|cffff4444[BAN]|r " .. p .. " (banned) rejoined the guild"
    elseif t == self.TYPES.BAN then
        return "|cffcc2222[BANNED]|r " .. p .. " — " .. (d.reason or "no reason")
    elseif t == self.TYPES.UNBAN then
        return p .. " ban was removed"
    elseif t == self.TYPES.NAME_CHANGE then
        return p .. " changed their name"
    end
    return p .. " — " .. (t or "unknown event")
end

-- ── Callback system ───────────────────────────────────────────────────────────

function ActivityLog:RegisterCallback(key, fn)
    _callbacks[key] = fn
end

function ActivityLog:UnregisterCallback(key)
    _callbacks[key] = nil
end

function ActivityLog:_NotifyCallbacks()
    for _, fn in pairs(_callbacks) do
        pcall(fn)
    end
end
