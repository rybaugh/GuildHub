-- GuildHub - ProfileSync
-- Peer-to-peer sync of player profile data between GuildHub users in the guild.
-- Uses the existing GH addon message protocol (pipe-delimited, GUILD channel).
-- Throttled to one outbound message per 0.5 s to avoid flooding.

local GH          = GuildHub
local ProfileSync = GH.ProfileSync

-- ── Message codes ─────────────────────────────────────────────────────────────
-- All messages are routed through the shared GH.ADDON_PREFIX.
-- The first decoded field identifies the subsystem ("PP") and the operation.

local PP = "PP"  -- sub-prefix for all profile-sync messages

local OP = {
    JOIN_DATE    = "PP_JD",
    RANK_HIST    = "PP_RH",
    BIRTHDAY     = "PP_BD",
    ALT_GROUP    = "PP_AL",
    CUSTOM_NOTE  = "PP_CN",
    BAN          = "PP_BN",
    UNBAN        = "PP_UB",
    REQUEST      = "PP_REQ",
    SYNC_CHUNK   = "PP_SYN",
}

-- ── Outbound queue & throttle ─────────────────────────────────────────────────

local _outQueue   = {}
local _queueFrame = nil

local function _FlushQueue()
    if #_outQueue == 0 then return end
    local msg = table.remove(_outQueue, 1)
    if GH:IsInGuild() then
        pcall(C_ChatInfo.SendAddonMessage, GH.ADDON_PREFIX, msg, "GUILD")
    end
end

local function _Enqueue(msg)
    if #msg > 250 then return end  -- safety guard
    _outQueue[#_outQueue + 1] = msg
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function ProfileSync:Initialize()
    -- Throttle frame: flush one message every 0.5 s
    _queueFrame = CreateFrame("Frame")
    local elapsed = 0
    _queueFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            _FlushQueue()
        end
    end)

    -- Listen for incoming messages (shares the CHAT_MSG_ADDON frame with other modules)
    local listenFrame = CreateFrame("Frame")
    listenFrame:RegisterEvent("CHAT_MSG_ADDON")
    listenFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
        if prefix == GH.ADDON_PREFIX then
            ProfileSync:OnAddonMessage(message, sender)
        end
    end)

    -- Request a full sync from online GuildHub users after a short delay at login
    C_Timer.After(15, function()
        if GH:IsInGuild() and GH.DB:GetSetting("rosterSyncEnabled") ~= false then
            ProfileSync:RequestSync()
        end
    end)
end

-- ── Incoming message handler ──────────────────────────────────────────────────

function ProfileSync:OnAddonMessage(message, sender)
    if GH.DB:GetSetting("rosterProfilesEnabled") == false then return end
    if GH.DB:GetSetting("rosterSyncEnabled") == false then return end

    local parts = GH:Decode(message)
    if not parts or #parts < 1 then return end
    local op = parts[1]

    -- Don't apply our own messages
    local me = GH:GetPlayerName()
    if sender and (sender == me or sender:match("^([^%-]+)") == me) then return end

    if op == OP.JOIN_DATE and #parts >= 4 then
        local name, ts, verified = parts[2], tonumber(parts[3]), parts[4] == "1"
        if name and ts then GH.Profiles:ReceiveJoinDate(name, ts, verified, sender) end

    elseif op == OP.RANK_HIST and #parts >= 5 then
        local name, rankName, rankIndex, ts = parts[2], parts[3], tonumber(parts[4]), tonumber(parts[5])
        if name and rankName and ts then
            GH.Profiles:ReceiveRankHistory(name, rankName, rankIndex or 0, ts, sender)
        end

    elseif op == OP.BIRTHDAY and #parts >= 5 then
        local name, month, day, year = parts[2], tonumber(parts[3]), tonumber(parts[4]), tonumber(parts[5])
        if name and month and day then GH.Profiles:ReceiveBirthday(name, month, day, year, sender) end

    elseif op == OP.ALT_GROUP and #parts >= 4 then
        -- PP_AL|groupId|ts|main|alt1|alt2|...
        local groupId, ts, main = parts[2], tonumber(parts[3]), parts[4]
        if groupId and ts and main then
            local alts = {}
            for i = 4, #parts do alts[#alts + 1] = parts[i] end
            GH.Profiles:ReceiveAltGroup(groupId, main, alts, ts, sender)
        end

    elseif op == OP.CUSTOM_NOTE and #parts >= 5 then
        local name, note, editor, ts = parts[2], parts[3], parts[4], tonumber(parts[5])
        if name and ts then GH.Profiles:ReceiveCustomNote(name, note, editor, ts, sender) end

    elseif op == OP.BAN and #parts >= 5 then
        if not GH:IsOfficer() then return end
        local name, reason, bannedBy, ts = parts[2], parts[3], parts[4], tonumber(parts[5])
        if name and ts then GH.Profiles:ReceiveBan(name, reason, bannedBy, ts, sender) end

    elseif op == OP.UNBAN and #parts >= 3 then
        local name, ts = parts[2], tonumber(parts[3])
        if name and ts then GH.Profiles:ReceiveUnban(name, ts, sender) end

    elseif op == OP.REQUEST then
        -- Another client wants a full sync; send our data in chunks
        C_Timer.After(math.random(1, 5), function()
            ProfileSync:SendFullSync()
        end)

    elseif op == OP.SYNC_CHUNK and #parts >= 2 then
        self:_ReceiveSyncChunk(parts[2], sender)
    end
end

-- ── Broadcast helpers ─────────────────────────────────────────────────────────

local function _CanPush()
    local minRank = GH.DB:GetSetting("rosterSyncMinRank") or 4
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex ~= nil and rankIndex <= minRank
end

function ProfileSync:BroadcastJoinDate(name, ts, verified)
    if not _CanPush() then return end
    _Enqueue(GH:Encode(OP.JOIN_DATE, name, tostring(ts), verified and "1" or "0"))
end

function ProfileSync:BroadcastRankHistory(name, rankName, rankIndex, ts)
    if not _CanPush() then return end
    _Enqueue(GH:Encode(OP.RANK_HIST, name, rankName, tostring(rankIndex), tostring(ts)))
end

function ProfileSync:BroadcastBirthday(name, month, day, year)
    if not _CanPush() then return end
    _Enqueue(GH:Encode(OP.BIRTHDAY, name, tostring(month), tostring(day), tostring(year or 0)))
end

function ProfileSync:BroadcastAltGroup(groupId, group)
    if not _CanPush() then return end
    local args = { OP.ALT_GROUP, groupId, tostring(group.ts or 0), group.main }
    for _, alt in ipairs(group.alts or {}) do
        args[#args + 1] = alt
    end
    local msg = GH:Encode(unpack(args))
    if #msg <= 250 then _Enqueue(msg) end
end

function ProfileSync:BroadcastCustomNote(name, note, editor, ts)
    if not _CanPush() then return end
    _Enqueue(GH:Encode(OP.CUSTOM_NOTE, name, note or "", editor or "", tostring(ts)))
end

function ProfileSync:BroadcastBan(name, reason, bannedBy, ts)
    if not GH:IsOfficer() then return end
    _Enqueue(GH:Encode(OP.BAN, name, reason or "", bannedBy or "", tostring(ts)))
end

function ProfileSync:BroadcastUnban(name, ts)
    if not GH:IsOfficer() then return end
    _Enqueue(GH:Encode(OP.UNBAN, name, tostring(ts)))
end

function ProfileSync:RequestSync()
    _Enqueue(GH:Encode(OP.REQUEST, GH:GetPlayerName()))
end

-- ── Full sync (chunked) ───────────────────────────────────────────────────────
-- Sends a condensed snapshot of all known join dates so recipients can fill gaps.
-- Each chunk covers up to 15 players to stay within 250 bytes.

function ProfileSync:SendFullSync()
    if not GH:IsInGuild() then return end
    local profiles = GH.DB:GetAllPlayerProfiles()

    local batch = {}
    local count = 0

    local function flush()
        if count == 0 then return end
        -- Encode as: PP_SYN|name1:ts1:v1|name2:ts2:v2|...
        local parts = { OP.SYNC_CHUNK }
        for _, entry in ipairs(batch) do
            parts[#parts + 1] = entry.name .. ":" .. tostring(entry.ts) .. ":" .. (entry.v and "1" or "0")
        end
        local msg = GH:Encode(unpack(parts))
        if #msg <= 250 then _Enqueue(msg) end
        batch = {}
        count = 0
    end

    for name, profile in pairs(profiles) do
        if profile.joinDate then
            batch[#batch + 1] = { name = name, ts = profile.joinDate, v = profile.joinDateVerified }
            count = count + 1
            if count >= 12 then flush() end
        end
    end
    flush()
end

function ProfileSync:_ReceiveSyncChunk(payload, sender)
    -- payload is a single pipe-encoded field containing colon-separated entries
    -- Because GH:Decode already split on pipes, payload is the second field of the outer message.
    -- Each token: name:ts:verified
    for token in payload:gmatch("[^|]+") do
        local name, ts, v = token:match("^([^:]+):(%d+):([01])$")
        if name and ts then
            GH.Profiles:ReceiveJoinDate(name, tonumber(ts), v == "1", sender)
        end
    end
end
