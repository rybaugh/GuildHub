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
GH.Events = GH.Events or {}
GH.Recruit = GH.Recruit or {}

function GH:Initialize()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.ADDON_PREFIX)
    end

    self.DB:Initialize()
    self.GuildData:Initialize()
    self.Groups:Initialize()
    self.Chat:Initialize()
    self.Events:Initialize()
    self.Recruit:Initialize()
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

function GH:IsOfficer()
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == nil then return false end
    -- Rank 0 = Guild Master, rank 1 = typically Officer
    local threshold = GH.DB and GH.DB:GetSetting("officerRankThreshold") or 4
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
