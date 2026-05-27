-- GuildHub - Permissions
-- Reads WoW rank permission flags and exposes named per-action checks.
-- GuildControlGetRankFlags uses the same 0-based rankIndex as GetGuildInfo("player").
-- Rank 0 (Guild Master) is handled as a special case — always has all permissions.

local GH = GuildHub
GH.Permissions = GH.Permissions or {}
local P  = GH.Permissions

-- Flag slot indices returned by GuildControlGetRankFlags.
-- Indices 3 and 4 (officer chat) are confirmed by the prior DetectOfficerThreshold code.
-- Others match the WoW Guild Control UI order; adjust if a specific check misbehaves.
GH.PERM = {
    GUILD_CHAT_LISTEN   = 1,
    GUILD_CHAT_SPEAK    = 2,
    OFFICER_CHAT_LISTEN = 3,
    OFFICER_CHAT_SPEAK  = 4,
    PROMOTE             = 5,
    DEMOTE              = 6,
    INVITE              = 7,
    REMOVE              = 8,
    SET_MOTD            = 9,
    EDIT_PUBLIC_NOTE    = 10,
    VIEW_OFFICER_NOTE   = 11,
    EDIT_OFFICER_NOTE   = 12,
    MODIFY_GUILD_INFO   = 13,
}

-- GH._rankFlags[rankIndex] = array of flag values from GuildControlGetRankFlags
GH._rankFlags = {}

function P:LoadRankPermissions()
    local getNumRanks  = rawget(_G, "GuildControlGetNumRanks")
    local getRankFlags = rawget(_G, "GuildControlGetRankFlags")
    if not getNumRanks or not getRankFlags then return end

    local numRanks = getNumRanks() or 0
    if numRanks < 2 then return end  -- guild data not ready; GUILD_ROSTER_UPDATE will retry

    local fresh = {}
    for ri = 1, numRanks - 1 do  -- skip 0 (GM); GM handled as special case in HasPermission
        local ok, flags = pcall(function() return { getRankFlags(ri) } end)
        if ok and flags then
            fresh[ri] = flags
        end
    end
    GH._rankFlags = fresh
end

function GH:HasPermission(flag)
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == nil then return false end
    if rankIndex == 0 then return true end  -- GM always has all permissions
    local flags = GH._rankFlags[rankIndex]
    if not flags then return false end
    local v = flags[flag]
    return v == 1 or v == true
end

function P:Initialize()
    self:LoadRankPermissions()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function()
        P:LoadRankPermissions()
    end)
    P.eventFrame = frame
end
