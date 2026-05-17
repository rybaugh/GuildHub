-- GuildHub - Database
-- All SavedVariables access goes through this module.
-- GuildHubDB is declared as SavedVariables in the TOC; WoW populates it at login.
--
-- Isolation model:
--   GuildHubDB.guilds[guildName]  — all guild-specific data (groups, chats, events, etc.)
--   GuildHubDB.settings           — account-wide settings
--   GuildHubDB.sessionLog         — account-wide debug log
--
-- DB._activeGuild is set via DB:SetActiveGuild(name) during PLAYER_LOGIN, once
-- GetGuildInfo("player") is reliable.  All guild-specific CRUD methods return
-- empty/no-op until SetActiveGuild has been called.

local GH = GuildHub
local DB = GH.DB

local function sv() return rawget(_G, "GuildHubDB") end

local DEFAULTS = {
    settings = {
        officerRankThreshold  = 4,
        teamRankThreshold     = 4,
        replaceGuildFrame     = false,
        minimapAngle          = math.rad(225),
        timeFormat            = "12h",
        showOfflineMembers    = true,
        hideDefaultGuildFrame = true,
        debugMode             = false,
        fontSize              = 10,
        federationChannel     = "",   -- optional cross-realm relay channel name
        federationPassword    = "",   -- optional relay channel password
        -- Roster Profiles feature settings
        rosterProfilesEnabled = true,
        rosterShowMouseover   = true,
        rosterShowBirthdays   = true,
        rosterSyncEnabled     = true,
        rosterSyncMinRank     = 4,
        rosterAutoJoinDate    = false,
        rosterJoinDateTarget  = "custom",
        -- General behavior
        showAtLogon           = false,
        onlyShowIfLogChanges  = false,
        -- Sync extras
        syncAutoTriggerDelay  = 60,
        syncRestrictIncoming  = true,
        syncBanListMinRank    = 4,
        syncCustomNotes       = true,
        displaySyncMessages   = false,
        -- Officer / auto-tagging
        joinTagText           = "Joined:",
        rejoinTagText         = "Rejoined:",
        addEventsToCalendar   = false,
        -- Scan options
        scanIntervalSecs      = 30,
        inactiveReturnDays    = 14,
        announceEventsDays    = 14,
        announceAnniversaries = true,
        announceBirthdays     = true,
        onlyMainForBdayAnn    = false,
        announceLoginBirthday = true,
        reportLevelUps        = true,
        levelReportMin        = 10,
    },
    guilds     = {},
    sessionLog = {},
}

local GUILD_DEFAULTS = {
    groups              = {},
    chats               = {},
    guildMessages       = {},
    events              = {},
    recruit             = {},
    lfmPoints           = {},
    memberNotes         = {},
    memberScores        = {},
    communityLinks      = {},   -- [id] = {clubId, streamId, label, enabled}
    communityMessages   = {},   -- persisted cross-guild history (14-day / 2000-msg ring)
    crossGuildLabel     = nil,  -- nil → "Cross Guild Chat"
    crossGuildSendTarget = nil, -- clubId string to send to, nil = guild chat
    -- Roster Profiles
    playerProfiles      = {},   -- [name] = { joinDate, joinDateVerified, joinDateHistory,
                                --            rankHistory, birthday, altGroupId,
                                --            customNote, customNoteEditor, customNoteTs,
                                --            isBanned, banReason, banDate, bannedBy }
    altGroups           = {},   -- [groupId] = { main, alts={}, ts }
    activityLog         = {},   -- [{type, player, ts, detail, actor}]  capped 2000
    newsBuffer          = {},   -- [{name, desc, iconTex, rawLink}]  capped 50, newest-first
    -- Guild Recruitment (posting to in-game Guild Finder)
    guildRecruitSettings = {
        listed         = false,
        focus          = "Raids",
        lookingFor     = {},
        language       = "English",
        message        = "",
        maxLevelOnly   = true,
        minIlvlEnabled = false,
        minIlvl        = 0,
        updatedAt      = nil,
        updatedBy      = nil,
    },
}

function DB:Initialize()
    if not sv() then
        rawset(_G, "GuildHubDB", self:_DeepCopy(DEFAULTS))
    else
        local db = sv()

        -- Migrate legacy flat format: groups/chats/etc. lived at the top level.
        if db.groups ~= nil and db.guilds == nil then
            local legacyGuild = (type(db.guildName) == "string" and db.guildName ~= "")
                                and db.guildName or "__legacy__"
            db.guilds = {}
            db.guilds[legacyGuild] = {
                groups        = db.groups        or {},
                chats         = db.chats         or {},
                guildMessages = db.guildMessages or {},
                events        = db.events        or {},
                recruit       = db.recruit       or {},
                lfmPoints     = db.lfmPoints     or {},
                memberNotes   = db.memberNotes   or {},
                memberScores  = db.memberScores  or {},
            }
            db.groups = nil; db.chats = nil; db.guildMessages = nil
            db.events = nil; db.recruit = nil; db.lfmPoints = nil
            db.memberNotes = nil; db.memberScores = nil; db.guildName = nil
        end

        -- Add any missing top-level keys.
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = self:_DeepCopy(v) end
        end
        for k, v in pairs(DEFAULTS.settings) do
            if db.settings[k] == nil then db.settings[k] = v end
        end
    end
end

-- Called from PLAYER_LOGIN once GetGuildInfo("player") is reliable.
-- Creates the per-guild namespace if absent and sets it as active.
function DB:SetActiveGuild(name)
    if not name or name == "" or name == "No Guild" then return end
    local db = sv()
    if not db then return end
    db.guilds = db.guilds or {}
    if not db.guilds[name] then
        db.guilds[name] = self:_DeepCopy(GUILD_DEFAULTS)
    else
        for k, v in pairs(GUILD_DEFAULTS) do
            if db.guilds[name][k] == nil then
                db.guilds[name][k] = self:_DeepCopy(v)
            end
        end
    end
    self._activeGuild = name
end

-- Returns the active per-guild data table, or nil if no guild is active yet.
function DB:_GuildData()
    local db = sv()
    if not db or not self._activeGuild then return nil end
    return db.guilds and db.guilds[self._activeGuild]
end

-- Settings (account-wide) ---------------------------------------------------

function DB:GetSetting(key)
    local db = sv()
    return db and db.settings and db.settings[key]
end

function DB:SetSetting(key, value)
    local db = sv()
    if db then db.settings[key] = value end
end

-- Groups --------------------------------------------------------------------

function DB:GetGroups()
    local gd = self:_GuildData()
    return (gd and gd.groups) or {}
end

function DB:SaveGroup(id, data)
    local gd = self:_GuildData()
    if gd then gd.groups[id] = data end
end

function DB:DeleteGroup(id)
    local gd = self:_GuildData()
    if gd then gd.groups[id] = nil end
end

-- Chats ---------------------------------------------------------------------

function DB:GetChats()
    local gd = self:_GuildData()
    return (gd and gd.chats) or {}
end

function DB:GetChat(id)
    local gd = self:_GuildData()
    return gd and gd.chats[id]
end

function DB:SaveChat(id, data)
    local gd = self:_GuildData()
    if gd then gd.chats[id] = data end
end

function DB:DeleteChat(id)
    local gd = self:_GuildData()
    if gd then gd.chats[id] = nil end
end

function DB:AddChatMessage(chatId, msg)
    local gd = self:_GuildData()
    if not gd then return end
    local chat = gd.chats[chatId]
    if not chat then return end
    chat.messages = chat.messages or {}
    table.insert(chat.messages, msg)
    while #chat.messages > 200 do
        table.remove(chat.messages, 1)
    end
end

-- Guild chat history --------------------------------------------------------

function DB:GetGuildMessages()
    local gd = self:_GuildData()
    if not gd then return {} end
    return gd.guildMessages or {}
end

-- Store a guild chat message verbatim.  Returns true if the entry was new.
-- Deduplication uses msg.mid (the messageId.epoch from C_Club.GetMessageInfo,
-- a microsecond-precision unique ID).  Falls back to ts+sender if mid absent.
-- Prunes entries older than 14 days and caps at 2000 messages.
function DB:AddGuildMessage(msg)
    local gd = self:_GuildData()
    if not gd then return false end
    gd.guildMessages = gd.guildMessages or {}
    if not msg or not msg.ts or not msg.sender or msg.text == nil then return false end

    if msg.mid then
        for _, existing in ipairs(gd.guildMessages) do
            if existing.mid == msg.mid then return false end
        end
    else
        for _, existing in ipairs(gd.guildMessages) do
            if existing.ts == msg.ts and existing.sender == msg.sender
               and existing.text == msg.text then
                return false
            end
        end
    end

    table.insert(gd.guildMessages, msg)
    table.sort(gd.guildMessages, function(a, b) return a.ts < b.ts end)

    local cutoff = GH:GetTimestamp() - 14 * 86400
    while #gd.guildMessages > 0 and gd.guildMessages[1].ts < cutoff do
        table.remove(gd.guildMessages, 1)
    end
    while #gd.guildMessages > 2000 do
        table.remove(gd.guildMessages, 1)
    end

    return true
end

-- Events --------------------------------------------------------------------

function DB:GetEvents()
    local gd = self:_GuildData()
    return (gd and gd.events) or {}
end

function DB:SaveEvent(id, data)
    local gd = self:_GuildData()
    if gd then gd.events[id] = data end
end

function DB:DeleteEvent(id)
    local gd = self:_GuildData()
    if gd then gd.events[id] = nil end
end

-- Recruitment ---------------------------------------------------------------

function DB:GetRecruitPosts()
    local gd = self:_GuildData()
    return (gd and gd.recruit) or {}
end

function DB:SaveRecruitPost(id, data)
    local gd = self:_GuildData()
    if gd then gd.recruit[id] = data end
end

function DB:DeleteRecruitPost(id)
    local gd = self:_GuildData()
    if gd then gd.recruit[id] = nil end
end

-- LFM Points ----------------------------------------------------------------

function DB:GetLFMPoints(name)
    local gd = self:_GuildData()
    return (gd and gd.lfmPoints and gd.lfmPoints[name]) or 0
end

function DB:AddLFMPoints(name, amount)
    local gd = self:_GuildData()
    if not gd then return end
    gd.lfmPoints = gd.lfmPoints or {}
    gd.lfmPoints[name] = (gd.lfmPoints[name] or 0) + (amount or 0)
end

function DB:GetAllLFMPoints()
    local gd = self:_GuildData()
    return (gd and gd.lfmPoints) or {}
end

function DB:MergeLFMPoints(name, pts)
    local gd = self:_GuildData()
    if not gd then return end
    gd.lfmPoints = gd.lfmPoints or {}
    if (pts or 0) > (gd.lfmPoints[name] or 0) then
        gd.lfmPoints[name] = pts
    end
end

-- Member notes & scores -----------------------------------------------------

function DB:GetMemberNote(name)
    local gd = self:_GuildData()
    return gd and gd.memberNotes and gd.memberNotes[name]
end

function DB:SetMemberNote(name, note)
    local gd = self:_GuildData()
    if gd then
        gd.memberNotes = gd.memberNotes or {}
        gd.memberNotes[name] = note
    end
end

function DB:GetMemberScore(name)
    local gd = self:_GuildData()
    return gd and gd.memberScores and gd.memberScores[name]
end

function DB:SetMemberScore(name, score)
    local gd = self:_GuildData()
    if gd then
        gd.memberScores = gd.memberScores or {}
        gd.memberScores[name] = score
    end
end

-- Helpers -------------------------------------------------------------------

function DB:_DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and self:_DeepCopy(v) or v
    end
    return copy
end

function DB:NewId()
    return tostring(time()) .. "_" .. tostring(math.random(100000, 999999))
end

-- Player Profiles -----------------------------------------------------------

function DB:GetPlayerProfile(name)
    local gd = self:_GuildData()
    if not gd then return nil end
    gd.playerProfiles = gd.playerProfiles or {}
    if not gd.playerProfiles[name] then
        gd.playerProfiles[name] = {
            joinDate         = nil,
            joinDateVerified = false,
            joinDateHistory  = {},
            rankHistory      = {},
            birthday         = nil,
            altGroupId       = nil,
            customNote       = "",
            customNoteEditor = nil,
            customNoteTs     = nil,
            isBanned         = false,
            banReason        = nil,
            banDate          = nil,
            bannedBy         = nil,
        }
    end
    return gd.playerProfiles[name]
end

function DB:GetAllPlayerProfiles()
    local gd = self:_GuildData()
    return (gd and gd.playerProfiles) or {}
end

function DB:SavePlayerProfile(name, data)
    local gd = self:_GuildData()
    if gd then
        gd.playerProfiles = gd.playerProfiles or {}
        gd.playerProfiles[name] = data
    end
end

-- Alt Groups ----------------------------------------------------------------

function DB:GetAltGroups()
    local gd = self:_GuildData()
    return (gd and gd.altGroups) or {}
end

function DB:GetAltGroup(groupId)
    local gd = self:_GuildData()
    return gd and gd.altGroups and gd.altGroups[groupId]
end

function DB:SaveAltGroup(groupId, data)
    local gd = self:_GuildData()
    if gd then
        gd.altGroups = gd.altGroups or {}
        gd.altGroups[groupId] = data
    end
end

function DB:DeleteAltGroup(groupId)
    local gd = self:_GuildData()
    if gd and gd.altGroups then gd.altGroups[groupId] = nil end
end

-- Activity Log --------------------------------------------------------------

function DB:GetActivityLog()
    local gd = self:_GuildData()
    return (gd and gd.activityLog) or {}
end

function DB:AddActivityLog(entry)
    local gd = self:_GuildData()
    if not gd then return end
    gd.activityLog = gd.activityLog or {}
    table.insert(gd.activityLog, entry)
    while #gd.activityLog > 2000 do
        table.remove(gd.activityLog, 1)
    end
end

function DB:ClearActivityLog()
    local gd = self:_GuildData()
    if gd then gd.activityLog = {} end
end

function DB:SetActivityLog(newLog)
    local gd = self:_GuildData()
    if gd then gd.activityLog = newLog end
end

-- Guild News Buffer ---------------------------------------------------------

function DB:GetNewsBuffer()
    local gd = self:_GuildData()
    if not gd then return {} end
    gd.newsBuffer = gd.newsBuffer or {}
    return gd.newsBuffer
end

function DB:AddNewsEntry(entry)
    local gd = self:_GuildData()
    if not gd or not entry or not entry.desc then return end
    gd.newsBuffer = gd.newsBuffer or {}
    for _, e in ipairs(gd.newsBuffer) do
        if e.desc == entry.desc and e.name == entry.name then return end
    end
    entry.ts = entry.ts or GH:GetTimestamp()
    table.insert(gd.newsBuffer, entry)
    table.sort(gd.newsBuffer, function(a, b)
        return (a.ts or 0) > (b.ts or 0)
    end)
    while #gd.newsBuffer > 50 do
        table.remove(gd.newsBuffer)
    end
end

-- Community Links -----------------------------------------------------------

function DB:GetCommunityLinks()
    local gd = self:_GuildData()
    return (gd and gd.communityLinks) or {}
end

function DB:SaveCommunityLink(id, data)
    local gd = self:_GuildData()
    if gd then
        gd.communityLinks = gd.communityLinks or {}
        gd.communityLinks[id] = data
    end
end

function DB:DeleteCommunityLink(id)
    local gd = self:_GuildData()
    if gd and gd.communityLinks then gd.communityLinks[id] = nil end
end

-- Community Messages --------------------------------------------------------

function DB:GetCommunityMessages()
    local gd = self:_GuildData()
    if not gd then return {} end
    return gd.communityMessages or {}
end

function DB:AddCommunityMessage(msg)
    local gd = self:_GuildData()
    if not gd then return false end
    gd.communityMessages = gd.communityMessages or {}
    if not msg or not msg.ts or not msg.sender or msg.text == nil then return false end

    if msg.mid then
        for _, existing in ipairs(gd.communityMessages) do
            if existing.mid == msg.mid then return false end
        end
    else
        for _, existing in ipairs(gd.communityMessages) do
            if existing.ts == msg.ts and existing.sender == msg.sender
               and existing.text == msg.text and existing.communityId == msg.communityId then
                return false
            end
        end
    end

    table.insert(gd.communityMessages, msg)
    table.sort(gd.communityMessages, function(a, b) return a.ts < b.ts end)

    local cutoff = GH:GetTimestamp() - 14 * 86400
    while #gd.communityMessages > 0 and gd.communityMessages[1].ts < cutoff do
        table.remove(gd.communityMessages, 1)
    end
    while #gd.communityMessages > 2000 do
        table.remove(gd.communityMessages, 1)
    end
    return true
end

-- Cross-Guild Label & Send Target -------------------------------------------

function DB:GetCrossGuildLabel()
    local gd = self:_GuildData()
    return (gd and gd.crossGuildLabel) or "Cross Guild Chat"
end

function DB:SetCrossGuildLabel(label)
    local gd = self:_GuildData()
    if gd then gd.crossGuildLabel = (label and label ~= "" and label or nil) end
end

function DB:GetCrossGuildSendTarget()
    local gd = self:_GuildData()
    return gd and gd.crossGuildSendTarget
end

function DB:SetCrossGuildSendTarget(clubId)
    local gd = self:_GuildData()
    if gd then gd.crossGuildSendTarget = clubId end
end

-- Guild Recruitment Settings ------------------------------------------------

function DB:GetGuildRecruitSettings()
    local gd = self:_GuildData()
    if not gd then
        return { listed=false, focus="Raids", lookingFor={}, language="English",
                 message="", maxLevelOnly=true, minIlvlEnabled=false, minIlvl=0 }
    end
    gd.guildRecruitSettings = gd.guildRecruitSettings or {
        listed=false, focus="Raids", lookingFor={}, language="English",
        message="", maxLevelOnly=true, minIlvlEnabled=false, minIlvl=0,
    }
    return gd.guildRecruitSettings
end

function DB:SaveGuildRecruitSettings(data)
    local gd = self:_GuildData()
    if gd then gd.guildRecruitSettings = data end
end

-- Last-logout timestamp (account-wide) -------------------------------------

function DB:GetLastLogoutTime()
    local db = sv()
    if not db or not db.settings then return 0 end
    return db.settings.lastLogoutTime or 0
end

function DB:SetLastLogoutTime(ts)
    local db = sv()
    if db and db.settings then
        db.settings.lastLogoutTime = ts
    end
end

-- Returns up to 500 messages (guildMessages + communityMessages) with ts > sinceTs,
-- sorted ascending. Capped at 500 to bound the HIST_CHUNK burst size.
function DB:GetMessagesSince(sinceTs)
    local gd = self:_GuildData()
    if not gd then return {} end
    local out = {}
    for _, m in ipairs(gd.guildMessages or {}) do
        if (m.ts or 0) > sinceTs then out[#out + 1] = m end
    end
    for _, m in ipairs(gd.communityMessages or {}) do
        if (m.ts or 0) > sinceTs then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    if #out > 500 then
        local trimmed = {}
        for i = #out - 499, #out do trimmed[#trimmed + 1] = out[i] end
        return trimmed
    end
    return out
end
