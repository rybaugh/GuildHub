-- GuildHub - Database
-- All SavedVariables access goes through this module.
-- GuildHubDB is declared as SavedVariables in the TOC; WoW populates it at login.
--
-- Isolation model:
--   GuildHubDB.guilds[guildName]                 — guild-wide data (events, guildMessages, …)
--   GuildHubDB.guilds[guildName].chars[charName] — per-character data (groups, chats)
--   GuildHubDB.settings                          — account-wide settings
--   GuildHubDB.sessionLog                        — account-wide debug log
--
-- DB._activeGuild / DB._activeChar are set via DB:SetActiveGuild(name) during
-- PLAYER_LOGIN once GetGuildInfo("player") is reliable.  All CRUD methods return
-- empty / no-op until SetActiveGuild has been called.

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
    },
    guilds     = {},
    sessionLog = {},
}

-- Guild-wide: shared across all characters in the same guild.
local GUILD_DEFAULTS = {
    guildMessages        = {},
    events               = {},
    recruit              = {},
    lfmPoints            = {},
    memberNotes          = {},
    memberScores         = {},
    communityLinks       = {},   -- [id] = {clubId, streamId, label, enabled}
    communityMessages    = {},   -- persisted cross-guild history (14-day / 2000-msg ring)
    crossGuildLabel      = nil,  -- nil → "Cross Guild Chat"
    crossGuildSendTarget = nil,  -- clubId string to send to, nil = guild chat
    communityJoinRequests = {},  -- [playerName] = {clubId, communityLabel, ts}
    chars                = {},   -- [charName] = CHAR_DEFAULTS
}

-- Per-character: groups joined and custom chat channels are toon-specific so that
-- alts in the same guild don't inherit another character's team memberships or history.
local CHAR_DEFAULTS = {
    groups = {},
    chats  = {},
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
-- Creates/migrates the per-guild and per-character namespaces and marks both active.
function DB:SetActiveGuild(name)
    if not name or name == "" or name == "No Guild" then return end
    local db = sv()
    if not db then return end

    -- Always establish the guild namespace first so guild-wide data (guildMessages,
    -- events, …) is immediately accessible regardless of character-name availability.
    db.guilds = db.guilds or {}
    if not db.guilds[name] then
        db.guilds[name] = self:_DeepCopy(GUILD_DEFAULTS)
    else
        -- Backfill any guild-level keys added in newer versions.
        local gd = db.guilds[name]
        for k, v in pairs(GUILD_DEFAULTS) do
            if gd[k] == nil then gd[k] = self:_DeepCopy(v) end
        end
    end

    self._activeGuild = name   -- guild data accessible from this point on

    -- Per-character namespace: requires a valid character name.
    -- UnitName("player") can return nil briefly during PLAYER_LOGIN on some builds;
    -- in that case guild data stays accessible while char data is deferred.
    local charName = GH:GetPlayerName()
    if not charName or charName == "" or charName == "Unknown" then return end

    local gd = db.guilds[name]

    -- Migrate: groups/chats used to live at the guild level (shared across all
    -- characters).  Move them under the current toon; others start fresh.
    if gd.groups ~= nil or gd.chats ~= nil then
        gd.chars = gd.chars or {}
        if not gd.chars[charName] then
            gd.chars[charName] = {
                groups = gd.groups or {},
                chats  = gd.chats  or {},
            }
        end
        gd.groups = nil
        gd.chats  = nil
    end

    -- Set up (or backfill) the per-character record.
    gd.chars = gd.chars or {}
    if not gd.chars[charName] then
        gd.chars[charName] = self:_DeepCopy(CHAR_DEFAULTS)
    else
        for k, v in pairs(CHAR_DEFAULTS) do
            if gd.chars[charName][k] == nil then
                gd.chars[charName][k] = self:_DeepCopy(v)
            end
        end
    end

    self._activeChar = charName
end

-- Returns the active per-guild data table, or nil if no guild is active yet.
function DB:_GuildData()
    local db = sv()
    if not db or not self._activeGuild then return nil end
    return db.guilds and db.guilds[self._activeGuild]
end

-- Returns the active per-character data table, or nil if not ready yet.
function DB:_CharData()
    local gd = self:_GuildData()
    if not gd or not self._activeChar then return nil end
    return gd.chars and gd.chars[self._activeChar]
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

-- Groups — per-character ----------------------------------------------------

function DB:GetGroups()
    local cd = self:_CharData()
    return (cd and cd.groups) or {}
end

function DB:SaveGroup(id, data)
    local cd = self:_CharData()
    if cd then cd.groups[id] = data end
end

function DB:DeleteGroup(id)
    local cd = self:_CharData()
    if cd then cd.groups[id] = nil end
end

-- Chats — per-character -----------------------------------------------------

function DB:GetChats()
    local cd = self:_CharData()
    return (cd and cd.chats) or {}
end

function DB:GetChat(id)
    local cd = self:_CharData()
    return cd and cd.chats[id]
end

function DB:SaveChat(id, data)
    local cd = self:_CharData()
    if cd then cd.chats[id] = data end
end

function DB:DeleteChat(id)
    local cd = self:_CharData()
    if cd then cd.chats[id] = nil end
end

function DB:AddChatMessage(chatId, msg)
    local cd = self:_CharData()
    if not cd then return end
    local chat = cd.chats[chatId]
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

-- Community Join Requests ---------------------------------------------------

function DB:GetJoinRequests()
    local gd = self:_GuildData()
    return (gd and gd.communityJoinRequests) or {}
end

function DB:SaveJoinRequest(name, data)
    local gd = self:_GuildData()
    if gd then
        gd.communityJoinRequests = gd.communityJoinRequests or {}
        gd.communityJoinRequests[name] = data
    end
end

function DB:ClearJoinRequest(name)
    local gd = self:_GuildData()
    if gd and gd.communityJoinRequests then
        gd.communityJoinRequests[name] = nil
    end
end
