-- GuildHub - GuildData
-- Wraps WoW guild roster APIs and maintains a cached member list.

local GH = GuildHub
local GD = GH.GuildData

-- WoW API aliases
local GetNumGuildMembers = _G.GetNumGuildMembers
local GetGuildRosterInfo = _G.GetGuildRosterInfo
local CreateFrame        = _G.CreateFrame

-- GuildRoster() was removed in 12.x; use C_GuildInfo.GuildRoster() on Retail.
local function RequestRosterUpdate()
    local fn = rawget(_G, "GuildRoster")
    if fn then
        fn()
    elseif C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

GD.members  = {}   -- array of member info tables, sorted online-first then alphabetically
GD.byName   = {}   -- shortName -> member table

GD._prevOnlineNames = {}  -- [name]=true for members online at last Refresh

local CLASS_COLORS = {
    DEATHKNIGHT = {0.77, 0.12, 0.23},
    DEMONHUNTER = {0.64, 0.19, 0.79},
    DRUID       = {1.00, 0.49, 0.04},
    EVOKER      = {0.20, 0.58, 0.50},
    HUNTER      = {0.67, 0.83, 0.45},
    MAGE        = {0.25, 0.78, 0.92},
    MONK        = {0.00, 1.00, 0.60},
    PALADIN     = {0.96, 0.55, 0.73},
    PRIEST      = {1.00, 1.00, 1.00},
    ROGUE       = {1.00, 0.96, 0.41},
    SHAMAN      = {0.00, 0.44, 0.87},
    WARLOCK     = {0.53, 0.53, 0.93},
    WARRIOR     = {0.78, 0.61, 0.43},
}

function GD:GetClassColor(classFileName)
    local c = classFileName and CLASS_COLORS[classFileName:upper()]
    if c then return c[1], c[2], c[3] end
    return 0.8, 0.8, 0.8
end

-- ── M+ score fetching ──────────────────────────────────────────────────────

-- Snapshot of shortName→unitToken for the current party/raid.
local function BuildUnitTokenMap()
    local map = {}
    local function index(token)
        if UnitExists and UnitExists(token) then
            local n = UnitName and UnitName(token)
            if n then map[n:match("^([^%-]+)") or n] = token end
        end
    end
    index("player")
    for i = 1, 4  do index("party" .. i) end
    for i = 1, 40 do index("raid"  .. i) end
    return map
end

-- C_PlayerInfo.GetPlayerMythicPlusRatingSummary only accepts unit tokens
-- ("player", "party1"…"party4", "raid1"…"raid40", "target", etc.).
-- Passing a GUID or name silently returns nil, so this only works for self
-- and current party/raid members.
local function FetchScoreFromAPI(member, unitTokenMap)
    if not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then return 0 end
    local token = unitTokenMap and unitTokenMap[member.name]
    if not token then return 0 end
    local ok, result = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, token)
    if ok and result and type(result) == "table" then
        return math.floor(result.currentSeasonScore or 0)
    end
    return 0
end

-- RaiderIO ships an offline player database so it can return scores for any
-- tracked player without a network request. The correct global is "RaiderIO"
-- (mixed case). Handles both the current API format (mythicKeystoneProfile)
-- and older formats (mythicPlusScore / score).
local _ownRealm = nil
local function GetOwnRealm()
    if not _ownRealm then
        if UnitFullName then
            local _, r = UnitFullName("player")
            _ownRealm = (r and r ~= "") and r or ""
        end
    end
    return _ownRealm or ""
end

local function FetchScoreFromRaiderIO(member)
    local rio = rawget(_G, "RaiderIO")
    if not (rio and type(rio.GetProfile) == "function") then return 0 end

    -- RaiderIO.GetProfile(name, realm) — name without realm suffix
    local name  = member.name
    local realm = member.fullName:find("-", 1, true)
                  and member.fullName:match("-(.+)$")
                  or GetOwnRealm()
    if not realm or realm == "" then return 0 end

    local ok, profile = pcall(rio.GetProfile, name, realm)
    if not (ok and type(profile) == "table") then return 0 end

    -- Current format: profile.mythicKeystoneProfile.mplusCurrent.score
    local mkp = profile.mythicKeystoneProfile
    if mkp and mkp.mplusCurrent and type(mkp.mplusCurrent.score) == "number"
    and mkp.mplusCurrent.score > 0 then
        return math.floor(mkp.mplusCurrent.score)
    end

    -- Older format: profile.mythicPlusScore or profile.score (table or number)
    local s = profile.mythicPlusScore or profile.score
    if type(s) == "table" then
        if type(s.all) == "table" and type(s.all.score) == "number" then
            return math.floor(s.all.score)
        end
        if type(s.score) == "number" then return math.floor(s.score) end
    end
    if type(s) == "number" and s > 0 then return math.floor(s) end

    return 0
end

-- Combined: WoW API (live, for self/group) then RaiderIO (offline DB, for all).
local function FetchMythicScore(member, unitTokenMap)
    local score = FetchScoreFromAPI(member, unitTokenMap)
    if score > 0 then return score end
    return FetchScoreFromRaiderIO(member)
end

-- ── Online-member score retry queue ───────────────────────────────────────
-- When a member comes online their WoW API data may not be cached yet.
-- We retry every RETRY_DELAY seconds up to MAX_ATTEMPTS times.

local RETRY_DELAY   = 5
local MAX_ATTEMPTS  = 6

local _fetchQueue   = {}
local _fetchRunning = false

local function DrainFetchQueue()
    _fetchRunning = false
    if #_fetchQueue == 0 then return end

    local unitTokenMap = BuildUnitTokenMap()
    local remaining    = {}

    for _, entry in ipairs(_fetchQueue) do
        local fresh = GD.byName[entry.member.name]
        if fresh and fresh.online then
            local score = FetchMythicScore(fresh, unitTokenMap)
            if score > 0 then
                GH.DB:SetMemberScore(fresh.name, score)
                if GH.UI and GH.UI.window and GH.UI.window:IsShown()
                and GH.UI.window.activeTab == "Members" then
                    GH.UI:RefreshMembersTab()
                end
            elseif entry.attempts < MAX_ATTEMPTS then
                remaining[#remaining + 1] = { member = entry.member, attempts = entry.attempts + 1 }
            end
        end
    end

    _fetchQueue = remaining
    if #_fetchQueue > 0 then
        _fetchRunning = true
        C_Timer.After(RETRY_DELAY, DrainFetchQueue)
    end
end

local function EnqueueForRetry(member)
    for _, entry in ipairs(_fetchQueue) do
        if entry.member.name == member.name then return end
    end
    _fetchQueue[#_fetchQueue + 1] = { member = member, attempts = 0 }
    if not _fetchRunning then
        _fetchRunning = true
        C_Timer.After(RETRY_DELAY, DrainFetchQueue)
    end
end

-- ── Addon message prefixes ─────────────────────────────────────────────────

local GD_PREFIX_SCORE   = "GD|SC|"
local GD_PREFIX_REQUEST = "GD|SR|"
local GD_PREFIX_SYNC    = "GD|SA|"

function GD:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("INSPECT_READY")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "GUILD_ROSTER_UPDATE" then
            GD:Refresh()
        elseif event == "PLAYER_GUILD_UPDATE" then
            RequestRosterUpdate()
        elseif event == "CHAT_MSG_ADDON" then
            local prefix, payload = ...
            if prefix == GH.ADDON_PREFIX then
                GD:OnAddonMessage(payload)
            end
        elseif event == "INSPECT_READY" then
            GD:OnInspectReady()
        end
    end)
    GD.eventFrame = frame
    if GH:IsInGuild() then
        RequestRosterUpdate()
    end
    C_Timer.After(8,  function() GD:BroadcastMyData() end)
    C_Timer.After(12, function() GD:RequestScoresFromGuild() end)
end

-- Broadcast own M+ score to the guild (called on login and when requested).
function GD:BroadcastMyData()
    if not GH:IsInGuild() then return end
    local myName = GH:GetPlayerName()
    local score  = 0
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        if ok and summary then
            score = math.floor(summary.currentSeasonScore or 0)
        end
    end
    if score > 0 then
        GH.DB:SetMemberScore(myName, score)
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX,
            GD_PREFIX_SCORE .. myName .. "|" .. score, "GUILD")
    end
end

-- Ask all online guild members running GuildHub to re-broadcast their scores.
function GD:RequestScoresFromGuild()
    if not GH:IsInGuild() then return end
    C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX,
        GD_PREFIX_REQUEST .. GH:GetPlayerName(), "GUILD")
end

function GD:OnAddonMessage(payload)
    if payload:sub(1, #GD_PREFIX_SCORE) == GD_PREFIX_SCORE then
        local rest = payload:sub(#GD_PREFIX_SCORE + 1)
        local name, scoreStr = rest:match("^([^|]+)|(%d+)$")
        if name and scoreStr then
            GH.DB:SetMemberScore(name, tonumber(scoreStr))
            if GH.UI and GH.UI.window and GH.UI.window:IsShown()
            and GH.UI.window.activeTab == "Members" then
                GH.UI:RefreshMembersTab()
            end
        end

    elseif payload:sub(1, #GD_PREFIX_REQUEST) == GD_PREFIX_REQUEST then
        GD:BroadcastMyData()

    elseif payload:sub(1, #GD_PREFIX_SYNC) == GD_PREFIX_SYNC then
        local requester = payload:sub(#GD_PREFIX_SYNC + 1)
        if requester ~= GH:GetPlayerName() then
            local jitter = math.random(1, 8)
            C_Timer.After(jitter, function()
                GD:BroadcastMyData()
                GH.Recruit:BroadcastAll()
                C_Timer.After(2, function() GH.Events:BroadcastAll() end)
                C_Timer.After(4, function() GH.Chat:BroadcastAllChannels() end)
            end)
        end
    end
end

function GD:RequestFullSync()
    if not GH:IsInGuild() then return end
    C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX,
        GD_PREFIX_SYNC .. GH:GetPlayerName(), "GUILD")
end

function GD:SetPersonalNote(targetName, note)
    GH.DB:SetMemberNote(targetName, note)
end

function GD:GetPersonalNote(targetName)
    return GH.DB:GetMemberNote(targetName)
end

function GD:GetMemberTeam(memberName)
    for _, g in pairs(GH.DB:GetGroups()) do
        for _, n in ipairs(g.members or {}) do
            if n == memberName then return g end
        end
    end
    return nil
end

function GD:GetMemberTeams(memberName)
    local out = {}
    for id, g in pairs(GH.DB:GetGroups()) do
        for _, n in ipairs(g.members or {}) do
            if n == memberName then
                out[#out + 1] = { id = id, name = g.name, color = g.color, channelId = g.channelId }
                break
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function GD:Refresh()
    self.members = {}
    self.byName  = {}

    local total = GetNumGuildMembers()
    for i = 1, total do
        local name, rank, rankIndex, level, classDisplayName,
              zone, note, officerNote, online, status, classFileName = GetGuildRosterInfo(i)
        if name then
            local shortName = name:match("^([^%-]+)") or name
            local member = {
                name          = shortName,
                fullName      = name,
                rank          = rank,
                rankIndex     = rankIndex,
                level         = level,
                class         = classDisplayName,
                classFileName = classFileName and classFileName:upper() or "WARRIOR",
                zone          = zone or "",
                note          = note or "",
                officerNote   = officerNote or "",
                online        = online,
                status        = status,
                rosterIndex   = i,
                guid          = select(17, GetGuildRosterInfo(i)),
            }
            self.members[#self.members + 1] = member
            self.byName[shortName] = member
        end
    end

    table.sort(self.members, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)

    -- Fetch M+ scores for every member.
    -- For self/party/raid: live data from the WoW API via unit token.
    -- For all others: RaiderIO offline player database.
    local unitTokenMap = BuildUnitTokenMap()
    for _, member in ipairs(self.members) do
        local score = FetchMythicScore(member, unitTokenMap)
        if score > 0 then
            GH.DB:SetMemberScore(member.name, score)
        end
    end

    -- Newly-online members whose score still came back 0 (neither WoW API nor
    -- RaiderIO had data yet) are queued for periodic retries.
    for _, member in ipairs(self.members) do
        if member.online and not GD._prevOnlineNames[member.name] then
            if (GH.DB:GetMemberScore(member.name) or 0) == 0 then
                EnqueueForRetry(member)
            end
        end
    end

    GD._prevOnlineNames = {}
    for _, member in ipairs(self.members) do
        if member.online then GD._prevOnlineNames[member.name] = true end
    end

    if GH.UI and GH.UI.OnRosterRefresh then
        GH.UI:OnRosterRefresh()
    end
end

-- INSPECT_READY fires when we inspect a nearby player via the standard UI.
-- Captures their score and removes them from the retry queue.
function GD:OnInspectReady()
    if not C_PlayerInfo or not C_PlayerInfo.GetPlayerMythicPlusRatingSummary then return end
    local ok, result = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "target")
    if not (ok and result and type(result) == "table") then return end
    local score = math.floor(result.currentSeasonScore or 0)
    if score <= 0 then return end
    local name = UnitName and UnitName("target")
    if not name then return end
    local shortName = name:match("^([^%-]+)") or name
    GH.DB:SetMemberScore(shortName, score)
    local pruned = {}
    for _, entry in ipairs(_fetchQueue) do
        if entry.member.name ~= shortName then pruned[#pruned + 1] = entry end
    end
    _fetchQueue = pruned
    if GH.UI and GH.UI.window and GH.UI.window:IsShown()
    and GH.UI.window.activeTab == "Members" then
        GH.UI:RefreshMembersTab()
    end
end

function GD:GetMembers(filter)
    if not filter or filter == "" then return self.members end
    local lf = filter:lower()
    local out = {}
    for _, m in ipairs(self.members) do
        local score = GH.DB:GetMemberScore(m.name) or 0
        local team = self:GetMemberTeam(m.name)
        local personal = GH.DB:GetMemberNote(m.name) or ""
        local levelStr = tostring(m.level or "")
        local scoreStr = score > 0 and tostring(score) or ""

        if m.name:lower():find(lf, 1, true)
        or (m.fullName and m.fullName:lower():find(lf, 1, true))
        or (m.rank and m.rank:lower():find(lf, 1, true))
        or (m.zone and m.zone:lower():find(lf, 1, true))
        or (m.class and m.class:lower():find(lf, 1, true))
        or (m.classFileName and m.classFileName:lower():find(lf, 1, true))
        or (m.note and m.note:lower():find(lf, 1, true))
        or (m.officerNote and m.officerNote:lower():find(lf, 1, true))
        or levelStr:find(lf, 1, true)
        or scoreStr:find(lf, 1, true)
        or (team and team.name:lower():find(lf, 1, true))
        or personal:lower():find(lf, 1, true)
        then
            out[#out + 1] = m
        end
    end
    return out
end

function GD:FindMember(nameInput)
    if not nameInput or nameInput == "" then return nil end
    local shortInput = nameInput:match("^([^%%-]+)") or nameInput
    local m = self.byName[nameInput] or self.byName[shortInput]
    if m then return m end
    local lower = nameInput:lower()
    local shortLower = shortInput:lower()
    for _, member in ipairs(self.members) do
        if member.name:lower() == lower
        or member.name:lower() == shortLower
        or (member.fullName and member.fullName:lower() == lower) then
            return member
        end
    end
    return nil
end

function GD:GetOnlineCount()
    local on = 0
    for _, m in ipairs(self.members) do
        if m.online then on = on + 1 end
    end
    return on, #self.members
end
