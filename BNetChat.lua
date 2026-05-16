-- GuildHub - BNetChat
-- Cross-realm/faction guild chat using three transport layers:
--   1) BNSendGameData whispers to each discovered GuildHub peer
--   2) SendAddonMessage on a named temporary channel as a relay bus
--   3) Probabilistic relay selection to prevent bus flooding

local GH = GuildHub
local BNC = GH.BNetChat

-- ── Constants ──────────────────────────────────────────────────────────────────
local PREFIX_BNET  = "GHBN"   -- addon prefix carried in BNSendGameData calls
local PREFIX_CHAN   = "GHXC"  -- addon prefix for the optional channel relay bus
local MSG_PING     = "P"      -- peer presence probe
local MSG_PONG     = "Q"      -- peer presence reply
local MSG_GCHAT    = "G"      -- cross-guild chat payload
local SEP          = "\30"    -- field separator (unit-separator byte, safe in addon messages)
local KEY_LEN      = 8        -- characters in a generated message key
local PACKET_BN    = 220      -- max payload bytes per BNet packet
local PACKET_CH    = 220      -- max payload bytes per channel packet
local STALE_SECS   = 90       -- discard messages older than this many seconds
local MAX_RELAY_AT = 8        -- only relay BNet→channel when peer count is at most this
local MAX_RING     = 2000     -- communityMsgs ring size (matches ChatManager)
local PING_DELAY   = 20       -- seconds after login before the first peer sweep

-- Wire format for fragmented payloads:
--   [KEY : KEY_LEN bytes][N : 2 bytes][T : 2 bytes][payload fragment ...]
-- KEY  — shared across all fragments of one logical message (used for reassembly and dedup)
-- N    — this fragment's 1-based index, zero-padded to 2 digits
-- T    — total fragment count, zero-padded to 2 digits
-- The fixed header is KEY_LEN + 4 bytes; payload starts at byte KEY_LEN + 5.
local HDR_LEN = KEY_LEN + 4

-- ── State ──────────────────────────────────────────────────────────────────────
BNC._peers     = {}   -- [gameID : string] = {name, guild, lastSeen}
BNC._seen      = {}   -- [key] = timestamp — keys of fully-assembled messages (dedup)
BNC._fragments = {}   -- [key] = {total=N, received=count, [1]=frag, ...}
BNC._chanNum   = nil  -- WoW channel slot number, set after JoinTemporaryChannel

-- ── Key generator ─────────────────────────────────────────────────────────────
local _POOL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local function NewKey()
    local out = {}
    local len = #_POOL
    for i = 1, KEY_LEN do
        out[i] = _POOL:sub(math.random(len), math.random(len))
    end
    return table.concat(out)
end

-- ── BNet friend enumeration ───────────────────────────────────────────────────
local function OnlineWoWGameIDs()
    local list = {}
    local count = 0
    pcall(function()
        count = BNGetNumFriends and select(1, BNGetNumFriends()) or 0
    end)
    for i = 1, count do
        pcall(function()
            local info = C_BattleNet
                and C_BattleNet.GetFriendAccountInfo
                and C_BattleNet.GetFriendAccountInfo(i)
            if not info then return end
            local g = info.gameAccountInfo
            local wowClient = rawget(_G, "BNET_CLIENT_WOW") or "WoW"
            if g and g.isOnline and not g["isWowMobile"] and g.clientProgram == wowClient then
                list[#list + 1] = tostring(g.gameAccountID)
            end
        end)
    end
    return list
end

-- ── Fragmentation ─────────────────────────────────────────────────────────────
-- Breaks a payload string into fragments no larger than maxBytes each.
-- Each fragment is prefixed with the shared key and its sequence position.
local function Fragment(payload, key, maxBytes)
    local frags = {}
    local pos   = 1
    while pos <= #payload do
        frags[#frags + 1] = payload:sub(pos, pos + maxBytes - 1)
        pos = pos + maxBytes
    end
    if #frags == 0 then frags[1] = payload end
    local total   = math.min(#frags, 99)
    local packets = {}
    for i = 1, total do
        packets[i] = key .. string.format("%02d%02d", i, total) .. frags[i]
    end
    return packets
end

-- ── Wire parsing ──────────────────────────────────────────────────────────────
local function ParseHeader(raw)
    if #raw <= HDR_LEN then return nil end
    local key   = raw:sub(1, KEY_LEN)
    local n     = tonumber(raw:sub(KEY_LEN + 1, KEY_LEN + 2))
    local total = tonumber(raw:sub(KEY_LEN + 3, KEY_LEN + 4))
    local body  = raw:sub(KEY_LEN + 5)
    if not n or not total or n < 1 or total < 1 then return nil end
    return key, n, total, body
end

-- ── Low-level send ────────────────────────────────────────────────────────────
local function BNSend(gameID, wire)
    local fn = rawget(_G, "BNSendGameData")
    if fn then pcall(fn, tonumber(gameID), PREFIX_BNET, wire) end
end

local function ChanSend(wire)
    if not BNC._chanNum then return end
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if C_ChatInfo then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX_CHAN, wire, "CHANNEL", BNC._chanNum)
    end
end

local function SendToPeers(frags)
    for gid in pairs(BNC._peers) do
        for _, f in ipairs(frags) do BNSend(gid, f) end
    end
end

local function SendToChannel(frags)
    for _, f in ipairs(frags) do ChanSend(f) end
end

-- ── Outbound relay ────────────────────────────────────────────────────────────
-- Called when the local player's guild chat fires — relays to all known peers
-- and to the optional channel bus so non-BNet-connected confederation members
-- can also receive the message.
function BNC:RelayGuildChat(text)
    local key     = NewKey()
    local payload = table.concat(
        { MSG_GCHAT, GH:GetPlayerName(), GH:GetGuildName(), text, tostring(GH:GetTimestamp()) },
        SEP)

    BNC._seen[key] = time()  -- pre-register so our own echo is ignored on arrival

    local bnFrags  = Fragment(payload, key, PACKET_BN)
    local chFrags  = Fragment(payload, key, PACKET_CH)
    SendToPeers(bnFrags)
    SendToChannel(chFrags)

    GH:Debug("BNetChat", "RelayGuildChat key=%s", key)
end

-- ── Peer discovery ────────────────────────────────────────────────────────────
function BNC:PingAllFriends()
    local payload = table.concat({ MSG_PING, GH:GetPlayerName(), GH:GetGuildName() }, SEP)
    local frags   = Fragment(payload, NewKey(), PACKET_BN)
    local targets = OnlineWoWGameIDs()
    for _, gid in ipairs(targets) do
        for _, f in ipairs(frags) do BNSend(gid, f) end
    end
    GH:Debug("BNetChat", "PingAllFriends: %d online friends probed", #targets)
end

local function ReplyPong(gameID)
    local payload = table.concat({ MSG_PONG, GH:GetPlayerName(), GH:GetGuildName() }, SEP)
    local frags   = Fragment(payload, NewKey(), PACKET_BN)
    for _, f in ipairs(frags) do BNSend(gameID, f) end
end

-- ── Fragment reassembly ───────────────────────────────────────────────────────
local function AcceptFragment(key, n, total, body)
    local bucket = BNC._fragments[key]
    if not bucket then
        bucket = { total = total, received = 0 }
        BNC._fragments[key] = bucket
    end
    if not bucket[n] then
        bucket[n]        = body
        bucket.received  = bucket.received + 1
    end
    return bucket.received >= bucket.total
end

local function Reassemble(key)
    local bucket = BNC._fragments[key]
    local parts  = {}
    for i = 1, bucket.total do
        parts[i] = bucket[i] or ""
    end
    BNC._fragments[key] = nil
    return table.concat(parts)
end

-- ── Register a discovered peer ────────────────────────────────────────────────
local function RegisterPeer(gameID, name, guild)
    local isNew = BNC._peers[gameID] == nil
    BNC._peers[gameID] = { name = name, guild = guild, lastSeen = time() }
    if isNew and GH.UI and GH.UI.OnChannelListChanged then
        GH.UI:OnChannelListChanged()
    end
end

-- ── Payload dispatch ──────────────────────────────────────────────────────────
local function DispatchPayload(payload, protocol, senderGameID)
    local fields = {}
    for v in (payload .. SEP):gmatch("([^" .. SEP .. "]*)" .. SEP) do
        fields[#fields + 1] = v
    end
    if #fields < 1 then return end

    local kind = fields[1]

    if kind == MSG_PING and senderGameID then
        RegisterPeer(senderGameID, fields[2] or "?", fields[3] or "?")
        GH:Debug("BNetChat", "Ping from %s [%s]", fields[2], fields[3])
        ReplyPong(senderGameID)

    elseif kind == MSG_PONG and senderGameID then
        RegisterPeer(senderGameID, fields[2] or "?", fields[3] or "?")
        GH:Debug("BNetChat", "Pong from %s [%s]", fields[2], fields[3])

    elseif kind == MSG_GCHAT and #fields >= 5 then
        local sender    = fields[2]
        local guildName = fields[3]
        local text      = fields[4]
        local ts        = tonumber(fields[5]) or GH:GetTimestamp()

        if math.abs(time() - ts) > STALE_SECS then return end
        if sender == GH:GetPlayerName() then return end

        GH:Debug("BNetChat", "GCHAT %s [%s]: %s", sender, guildName, text)

        -- Deliver into the existing Cross Guild Chat view.
        local Chat = GH.Chat
        if Chat then
            local entry = {
                sender      = sender,
                text        = text,
                ts          = ts,
                communityId = "bnet:" .. guildName,
                sourceLabel = guildName,
                isBNet      = true,
            }
            -- Dedup against recent ring entries.
            local cid = entry.communityId
            local dup = false
            for i = math.max(1, #Chat.communityMsgs - 30), #Chat.communityMsgs do
                local m = Chat.communityMsgs[i]
                if m and m.communityId == cid
                   and m.sender == sender and m.text == text then
                    dup = true; break
                end
            end
            if not dup then
                Chat.communityMsgs[#Chat.communityMsgs + 1] = entry
                if #Chat.communityMsgs > MAX_RING then
                    table.remove(Chat.communityMsgs, 1)
                end
                GH.DB:AddCommunityMessage(entry)
                -- Surface in guild chat tab (cross-guild flows into the main chat).
                Chat.unread[Chat.GUILD_ID] = (Chat.unread[Chat.GUILD_ID] or 0) + 1
                if GH.UI and GH.UI.UpdateChatBadge then GH.UI:UpdateChatBadge() end
                if GH.UI and GH.UI.OnChatMessage   then GH.UI:OnChatMessage(Chat.GUILD_ID) end
            end
        end

        -- When a message arrives via BNet, forward it to the channel bus so peers
        -- who share the channel but are not directly BNet-connected can receive it.
        -- Only relay when the peer count is small enough that flooding is unlikely.
        if protocol == "BNET" and BNC._chanNum then
            local peerCount = 0
            for _ in pairs(BNC._peers) do peerCount = peerCount + 1 end
            if peerCount <= MAX_RELAY_AT then
                local relayPayload = table.concat(
                    { MSG_GCHAT, sender, guildName, text, tostring(ts) }, SEP)
                local rkey  = NewKey()
                BNC._seen[rkey] = ts
                local frags = Fragment(relayPayload, rkey, PACKET_CH)
                SendToChannel(frags)
            end
        end
    end
end

-- ── Unified receive entry point ───────────────────────────────────────────────
local function OnReceive(prefix, raw, protocol, senderGameID)
    if prefix ~= PREFIX_BNET and prefix ~= PREFIX_CHAN then return end

    local key, n, total, body = ParseHeader(raw)
    if not key then return end

    if BNC._seen[key] then return end  -- already processed this message

    local complete = AcceptFragment(key, n, total, body)
    if complete then
        BNC._seen[key] = time()
        local payload = Reassemble(key)
        DispatchPayload(payload, protocol, senderGameID)
    end
end

-- ── Federation channel management ─────────────────────────────────────────────
local function PollChannelSlot(name, attempt)
    local slot = GetChannelName and GetChannelName(name)
    if slot and slot > 0 then
        BNC._chanNum = slot
        GH:Debug("BNetChat", "Channel '%s' is slot #%d", name, slot)
    elseif (attempt or 1) < 8 then
        C_Timer.After(2, function() PollChannelSlot(name, (attempt or 1) + 1) end)
    end
end

function BNC:JoinFederationChannel(name, password)
    if not name or name == "" then return end
    local fn = rawget(_G, "JoinTemporaryChannel")
    if not fn then return end
    pcall(fn, name, password or "")
    C_Timer.After(1, function() PollChannelSlot(name) end)
    GH:Debug("BNetChat", "Joining federation channel '%s'", name)
end

function BNC:SetFederationChannel(name, password)
    local old = GH.DB:GetSetting("federationChannel") or ""
    if old ~= "" and old ~= (name or "") then
        local fn = rawget(_G, "LeaveChannelByName")
        if fn then pcall(fn, old) end
        BNC._chanNum = nil
    end
    GH.DB:SetSetting("federationChannel", name or "")
    GH.DB:SetSetting("federationPassword", password or "")
    if name and name ~= "" then
        BNC:JoinFederationChannel(name, password)
    end
end

function BNC:GetFederationChannelName()
    return GH.DB:GetSetting("federationChannel") or ""
end

-- ── Public accessors ──────────────────────────────────────────────────────────
function BNC:GetPeerCount()
    local n = 0
    for _ in pairs(BNC._peers) do n = n + 1 end
    return n
end

function BNC:HasPeers()
    return next(BNC._peers) ~= nil
end

-- ── Initialization ────────────────────────────────────────────────────────────
function BNC:Initialize()
    BNC._startTime = time()

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_BNET)
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_CHAN)
    end

    -- BN_CHAT_MSG_ADDON delivers BNet game-data messages.
    local bnFrame = CreateFrame("Frame")
    bnFrame:RegisterEvent("BN_CHAT_MSG_ADDON")
    bnFrame:SetScript("OnEvent", function(_, _, prefix, msg, _, senderGameID)
        OnReceive(prefix, msg, "BNET", tostring(senderGameID))
    end)
    BNC._bnFrame = bnFrame

    -- CHAT_MSG_ADDON delivers messages from the optional channel relay bus.
    local chFrame = CreateFrame("Frame")
    chFrame:RegisterEvent("CHAT_MSG_ADDON")
    chFrame:SetScript("OnEvent", function(_, _, prefix, msg)
        if prefix == PREFIX_CHAN then
            OnReceive(prefix, msg, "CHANNEL", nil)
        end
    end)
    BNC._chFrame = chFrame

    -- Capture the local player's own guild chat and relay it to peers.
    -- Use the GUID (arg 12) instead of the sender name (arg 2) because the name
    -- arrives as a secret string in tainted execution and cannot be compared with ==.
    -- Guard with issecretvalue() first, matching XFaction's pattern.
    local gcFrame = CreateFrame("Frame")
    gcFrame:RegisterEvent("CHAT_MSG_GUILD")
    gcFrame:SetScript("OnEvent", function(_, _, message, _, _, _, _, _, _, _, _, _, guid)
        if issecretvalue(guid) then return end
        if guid == UnitGUID("player") then
            BNC:RelayGuildChat(message)
        end
    end)
    BNC._gcFrame = gcFrame

    -- Rejoin the configured federation channel after login settles.
    local chanName = GH.DB:GetSetting("federationChannel") or ""
    local chanPwd  = GH.DB:GetSetting("federationPassword") or ""
    if chanName ~= "" then
        C_Timer.After(5, function()
            BNC:JoinFederationChannel(chanName, chanPwd)
        end)
    end

    -- Probe all online BNet friends to identify GuildHub peers.
    C_Timer.After(PING_DELAY, function() BNC:PingAllFriends() end)

    GH:Debug("BNetChat", "Initialized")
end
