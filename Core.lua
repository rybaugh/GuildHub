-- GuildHub - Core
GuildHub = GuildHub or {}
local GH = GuildHub

GH.VERSION = "1.0"
GH.ADDON_NAME = "GuildHub"
GH.ADDON_PREFIX = "GuildHub"

GH.DB = GH.DB or {}
GH.UI = GH.UI or {}
GH.GuildData = GH.GuildData or {}
GH.Groups = GH.Groups or {}
GH.Chat = GH.Chat or {}
GH.BNetChat = GH.BNetChat or {}
GH.Events = GH.Events or {}
GH.Recruit = GH.Recruit or {}
GH.GuildRecruit = GH.GuildRecruit or {}
GH.Profiles = GH.Profiles or {}
GH.ProfileSync = GH.ProfileSync or {}
GH.ActivityLog = GH.ActivityLog or {}

function GH:Initialize()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.ADDON_PREFIX)
    end

    self.DB:Initialize()
    self.GuildData:Initialize()
    self.Groups:Initialize()
    self.Chat:Initialize()
    self.BNetChat:Initialize()
    self.Events:Initialize()
    self.Recruit:Initialize()
    self.GuildRecruit:Initialize()
    self.Profiles:Initialize()
    self.ActivityLog:Initialize()
    self.ProfileSync:Initialize()
    self.UI:Initialize()

    print("|cff7289daGuildHub|r loaded! Type |cffffd700/gh|r to open.")
end

function GH:IsInGuild()
    if C_GuildInfo and C_GuildInfo.HasGuildInfo then
        return C_GuildInfo.HasGuildInfo()
    end
    return GetGuildInfo("player") ~= nil
end

function GH:IsGuildMaster()
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex == 0
end

-- Walks WoW guild rank flags to find the highest rank index that still has
-- officer chat access (flags 3/4 in GuildControlGetRankFlags cover speak/listen).
-- Caches the result for the session; re-detects if guild data wasn't loaded yet.
function GH:DetectOfficerThreshold()
    if GH._cachedOfficerThreshold then
        return GH._cachedOfficerThreshold
    end
    local getNumRanks  = rawget(_G, "GuildControlGetNumRanks")
    local getRankFlags = rawget(_G, "GuildControlGetRankFlags")
    if not getNumRanks or not getRankFlags then return 1 end

    local numRanks = getNumRanks() or 0
    if numRanks < 2 then return 1 end  -- guild data not loaded yet; safe fallback, not cached

    local threshold = 0
    for ri = 1, numRanks - 1 do
        pcall(function()
            -- GuildControlGetRankFlags returns one value per permission slot.
            -- Slots 3 and 4 correspond to officer-chat speak and listen across
            -- the WoW versions GuildHub targets.
            local f = { getRankFlags(ri) }
            if f[3] == 1 or f[3] == true or f[4] == 1 or f[4] == true then
                threshold = ri
            end
        end)
    end
    GH._cachedOfficerThreshold = threshold
    return threshold
end

function GH:IsOfficer()
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == nil then return false end
    local threshold = GH.DB and GH.DB:GetSetting("officerRankThreshold")
    if threshold == nil then
        threshold = GH:DetectOfficerThreshold()
    end
    return rankIndex <= threshold
end

-- Returns true if the player can create teams or handle team protocol messages.
-- Tied to the officer threshold so only ranks that see officer chat can create teams.
function GH:CanManageTeams()
    return GH:IsOfficer()
end

-- Returns true if the player can delete, add, or remove members from a specific team.
-- The team creator and any rank above the creator (lower rankIndex) have this permission.
-- Falls back to IsOfficer() for legacy teams that predate creator tracking.
function GH:CanManageTeam(groupId)
    local _, _, myRankIndex = GetGuildInfo("player")
    if myRankIndex == nil then return false end
    local g = GH.DB and GH.DB.GetGroups and GH.DB:GetGroups()[groupId]
    if not g then return false end
    if not g.creator then return GH:IsOfficer() end
    if myRankIndex == 0 then return true end
    if g.creator == GH:GetPlayerName() then return true end
    if g.creatorRank and myRankIndex < g.creatorRank then return true end
    return false
end

function GH:GetGuildName()
    local name = GetGuildInfo("player")
    return name or "No Guild"
end

function GH:GetPlayerName()
    return UnitName("player") or "Unknown"
end

function GH:GetTimestamp()
    return time()
end

function GH:FormatTime(ts)
    if not ts then return "" end
    local fmt = (self.DB and self.DB:GetSetting("timeFormat")) or "24h"
    if fmt == "12h" then
        return date("%m/%d %I:%M %p", ts)
    end
    return date("%m/%d %H:%M", ts)
end

-- Encode a table into a pipe-delimited string for addon messages
function GH:Encode(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = tostring(select(i, ...) or "")
        v = v:gsub("|", "\29")  -- replace pipe with unit separator
        parts[i] = v
    end
    return table.concat(parts, "|")
end

-- Decode a pipe-delimited addon message string
function GH:Decode(str)
    local parts = {}
    for part in (str .. "|"):gmatch("([^|]*)|") do
        parts[#parts + 1] = part:gsub("\29", "|")
    end
    return parts
end
