-- GuildHub - Core
GuildHub = GuildHub or {}
local GH = GuildHub

GH.VERSION = "0.81"
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
GH.Communities = GH.Communities or {}
GH.Permissions = GH.Permissions or {}
GH.TeamApps = GH.TeamApps or {}

function GH:Initialize()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.ADDON_PREFIX)
    end

    self.DB:Initialize()
    self.Permissions:Initialize()
    self.GuildData:Initialize()
    self.Groups:Initialize()
    self.Chat:Initialize()
    self.BNetChat:Initialize()
    self.Events:Initialize()
    self.Recruit:Initialize()
    self.GuildRecruit:Initialize()
    self.Profiles:Initialize()
    self.ActivityLog:Initialize()
    self.TeamApps:Initialize()
    self.ProfileSync:Initialize()
    self.Communities:Initialize()
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
    if GH:IsGuildMaster() then return true end
    if next(GH._rankFlags) then
        return GH:HasPermission(GH.PERM.OFFICER_CHAT_SPEAK)
            or GH:HasPermission(GH.PERM.PROMOTE)
            or GH:HasPermission(GH.PERM.DEMOTE)
            or GH:HasPermission(GH.PERM.REMOVE)
    end
    local canInvite = rawget(_G, "CanGuildInvite")
    if canInvite and canInvite() then return true end
    local canRemove = rawget(_G, "CanGuildRemove")
    if canRemove and canRemove() then return true end
    return false
end

function GH:CanEditPublicNote()
    if next(GH._rankFlags) then
        return GH:HasPermission(GH.PERM.EDIT_PUBLIC_NOTE)
    end
    -- Fallback: editing public notes is an officer-level action
    return GH:IsOfficer()
end

function GH:CanPromote()
    if next(GH._rankFlags) then
        return GH:HasPermission(GH.PERM.PROMOTE)
    end
    local fn = rawget(_G, "CanGuildPromote")
    return fn and fn() or false
end

function GH:CanDemote()
    if next(GH._rankFlags) then
        return GH:HasPermission(GH.PERM.DEMOTE)
    end
    local fn = rawget(_G, "CanGuildDemote")
    return fn and fn() or false
end

function GH:CanInvite()
    if next(GH._rankFlags) then
        return GH:HasPermission(GH.PERM.INVITE)
    end
    local fn = rawget(_G, "CanGuildInvite")
    return fn and fn() or false
end

function GH:CanRemoveMember()
    if next(GH._rankFlags) then
        return GH:HasPermission(GH.PERM.REMOVE)
    end
    local fn = rawget(_G, "CanGuildRemove")
    return fn and fn() or false
end

function GH:CanViewOfficerNote()
    return GH:HasPermission(GH.PERM.VIEW_OFFICER_NOTE)
end

function GH:CanEditOfficerNote()
    return GH:HasPermission(GH.PERM.EDIT_OFFICER_NOTE)
end

-- Returns true if the player can create teams or handle team protocol messages.
-- Tied to the officer threshold so only ranks that see officer chat can create teams.
function GH:CanManageTeams()
    return GH:IsOfficer()
end

-- Checks a specific WoW guild rank permission flag for the given 0-based rankIndex.
-- Flag indices (1-based in the returned table from GuildControlGetRankFlags):
--   3=oChatListen, 4=oChatSpeak, 5=editPublicNote, 6=viewOfficerNote,
--   7=editOfficerNote, 8=promoteMember, 9=demoteMember, 10=inviteMember,
--   11=removeMember, 12=setMOTD
local function HasRankFlag(rankIndex, flagIndex)
    local getRankFlags = rawget(_G, "GuildControlGetRankFlags")
    if not getRankFlags then return false end
    local ok, flags = pcall(function() return { getRankFlags(rankIndex) } end)
    if not (ok and flags) then return false end
    return flags[flagIndex] == 1 or flags[flagIndex] == true
end

-- Returns true if the current player can promote the given target (by their rankIndex).
-- Mirrors the default UI: requires the "Promote Member" flag and outranking the target.
function GH:CanGuildPromote(targetRankIndex)
    local _, _, myRankIndex = GetGuildInfo("player")
    if myRankIndex == nil then return false end
    if myRankIndex == 0 then return true end
    if targetRankIndex ~= nil and myRankIndex >= targetRankIndex then return false end
    if not rawget(_G, "GuildControlGetRankFlags") then return GH:IsOfficer() end
    return HasRankFlag(myRankIndex, 8)
end

-- Returns true if the current player can demote the given target.
function GH:CanGuildDemote(targetRankIndex)
    local _, _, myRankIndex = GetGuildInfo("player")
    if myRankIndex == nil then return false end
    if myRankIndex == 0 then return true end
    if targetRankIndex ~= nil and myRankIndex >= targetRankIndex then return false end
    if not rawget(_G, "GuildControlGetRankFlags") then return GH:IsOfficer() end
    return HasRankFlag(myRankIndex, 9)
end

-- Returns true if the current player can kick the given target from the guild.
function GH:CanGuildKick(targetRankIndex)
    local _, _, myRankIndex = GetGuildInfo("player")
    if myRankIndex == nil then return false end
    if myRankIndex == 0 then return true end
    if targetRankIndex ~= nil and myRankIndex >= targetRankIndex then return false end
    if not rawget(_G, "GuildControlGetRankFlags") then return GH:IsOfficer() end
    return HasRankFlag(myRankIndex, 11)
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
