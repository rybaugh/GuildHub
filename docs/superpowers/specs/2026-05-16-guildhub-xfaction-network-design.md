# GuildHub — XFaction Network Parity + History Sync

**Date:** 2026-05-16
**Status:** Approved, ready for implementation

---

## Goals

1. Replace GuildHub's single `GHXC` channel prefix with a 25-tag rotating pool (XFaction pattern) to multiply the effective addon-message rate limit.
2. Adopt ChatThrottleLib (CTL) for all addon-channel sends with three priority tiers: ALERT, NORMAL, BULK.
3. Expand peer discovery to include the GUILD addon channel so same-realm guildmates become peers without requiring BNet friendship.
4. Add a first-responder history-sync protocol that delivers missed messages (since last logout) over BULK priority at login.

---

## Scope

**Files changed:**

- `GuildHub.toc` — add CTL library entry
- `BNetChat.lua` — all network changes (tag pool, CTL, guild PING, HIST protocol)
- `Database.lua` — three new methods
- `Main.lua` — PLAYER_LOGOUT hook
- `ProfileSync.lua` — remove 0.5 s OnUpdate queue; route through CTL

**New file:**

- `Library/ChatThrottleLib/ChatThrottleLib.lua` — copied from XFaction's bundled version

---

## Section 1: Tag Pool + ChatThrottleLib

### Tag pool

Replace `local PREFIX_CHAN = "GHXC"` with 25 registered prefixes `GHCH01`–`GHCH25`.

```lua
local TAG_COUNT = 25
local _TAGS     = {}   -- [prefixString] = true  (O(1) receive filter)
local _TAG_ARR  = {}   -- ordered array for random pick

-- built in BNC:Initialize():
for i = 1, TAG_COUNT do
    local t = string.format("GHCH%02d", i)
    _TAGS[t]   = true
    _TAG_ARR[i] = t
    C_ChatInfo.RegisterAddonMessagePrefix(t)
end

local function GetRandomTag()
    return _TAG_ARR[math.random(TAG_COUNT)]
end
```

`GHBN` (BNet prefix) is unchanged — BNet has independent throttling.

### Priority constants

```lua
local PRIO_LIVE = "ALERT"   -- live guild chat relay
local PRIO_META = "NORMAL"  -- PING, PONG, profile sync
local PRIO_HIST = "BULK"    -- history chunks
```

### CTL send helpers (replace existing `ChanSend` / add `GuildSend`)

```lua
local function ChanSend(wire, prio)
    if not BNC._chanNum then return end
    local ctl = rawget(_G, "ChatThrottleLib")
    if ctl then
        pcall(ctl.SendAddonMessage, ctl, prio or PRIO_META,
              GetRandomTag(), wire, "CHANNEL", BNC._chanNum)
    end
end

local function GuildSend(wire, prio)
    local ctl = rawget(_G, "ChatThrottleLib")
    if ctl then
        pcall(ctl.SendAddonMessage, ctl, prio or PRIO_META,
              GetRandomTag(), wire, "GUILD")
    end
end
```

### ProfileSync change

Remove the 0.5 s OnUpdate flush frame. Each outbound profile-sync payload passes directly to `GuildSend(payload, PRIO_META)` — CTL paces it automatically.

### GuildHub.toc change

Add before `BNetChat.lua`:

```text
Library/ChatThrottleLib/ChatThrottleLib.lua
```

### Receive path change

The `chFrame` OnEvent handler currently checks `prefix == PREFIX_CHAN`. Replace with:

```lua
chFrame:SetScript("OnEvent", function(_, _, prefix, msg, distrib)
    if _TAGS[prefix] then
        local proto = (distrib == "GUILD") and "GUILD" or "CHANNEL"
        OnReceive(prefix, msg, proto, nil)
    end
end)
```

`distrib` (6th arg of `CHAT_MSG_ADDON`) identifies whether the packet arrived over the GUILD channel or the federation channel, so `DispatchPayload` can route correctly.

---

## Section 2: Guild Channel PING Discovery

### PING payload extended

```lua
-- was:  P|playerName|guildName
-- now:  P|playerName|guildName|lastLogoutTs
```

The fourth field piggybacks the sender's last-logout timestamp so responding peers immediately know whether they have relevant history — no extra round-trip.

### `BNC:PingAllFriends()` — dual broadcast

```lua
function BNC:PingAllFriends()
    local payload = table.concat(
        { MSG_PING, GH:GetPlayerName(), GH:GetGuildName(),
          tostring(GH.DB:GetLastLogoutTime()) }, SEP)
    local key     = NewKey()
    local frags   = Fragment(payload, key, PACKET_BN)

    -- Existing: BNet whisper to all online WoW friends
    for _, gid in ipairs(OnlineWoWGameIDs()) do
        for _, f in ipairs(frags) do BNSend(gid, f) end
    end

    -- New: broadcast on GUILD addon channel for same-realm guildmates
    for _, f in ipairs(frags) do GuildSend(f, PRIO_META) end
end
```

### PONG reply path

When a peer receives a PING (from either BNet or GUILD channel), they reply PONG via the same transport. Non-BNet guildmates complete the full handshake entirely over the GUILD addon channel.

### Peer entry shape

```lua
BNC._peers[gameID] = {
    name         = name,
    guild        = guild,
    lastSeen     = time(),
    lastLogoutTs = tonumber(lastLogoutTs) or 0,
    protocol     = "BNET" | "GUILD",  -- how this peer was discovered
}
```

`protocol` drives Section 3's decision on whether HIST_REQ goes via BNet whisper or guild channel broadcast.

---

## Section 3: History Sync Protocol (First-Responder)

### New message types

```lua
local MSG_HIST_REQ   = "R"    -- request history since timestamp
local MSG_HIST_CHUNK = "C"    -- one batch of historical messages
local MSG_HIST_SEP   = "\31"  -- inner field separator within a chunk
```

### New state

```lua
BNC._pendingHistReq = nil   -- requestId we sent; nil once fulfilled
BNC._histChunks     = {}    -- [requestId] = {total, received, [1..n]=fields}
```

### Login flow

On the **first PONG received** this session (and only the first), fire `BNC:_RequestHistory(peer)`:

```lua
-- in DispatchPayload, MSG_PONG branch:
elseif kind == MSG_PONG and senderGameID then
    RegisterPeer(senderGameID, fields[2], fields[3])
    if not BNC._pendingHistReq then
        BNC:_RequestHistory(BNC._peers[senderGameID])
    end
```

### `BNC:_RequestHistory(peer)`

```lua
function BNC:_RequestHistory(peer)
    local reqId   = NewKey()
    local sinceTs = GH.DB:GetLastLogoutTime()
    BNC._pendingHistReq = reqId
    BNC._seen[reqId]    = time()   -- suppress our own echo

    local payload = table.concat(
        { MSG_HIST_REQ, reqId, tostring(sinceTs), peer.name }, SEP)
    local frags = Fragment(payload, NewKey(), PACKET_BN)

    if peer.protocol == "BNET" then
        for gid, p in pairs(BNC._peers) do
            if p.name == peer.name then
                for _, f in ipairs(frags) do BNSend(gid, f) end
                break
            end
        end
    else
        -- Guild-channel broadcast; embedded targetName keeps only the target responding
        for _, f in ipairs(frags) do GuildSend(f, PRIO_HIST) end
    end
end
```

### Responding peer — `MSG_HIST_REQ` dispatch

```lua
elseif kind == MSG_HIST_REQ and #fields >= 4 then
    local reqId   = fields[2]
    local sinceTs = tonumber(fields[3]) or 0
    local target  = fields[4]

    if target ~= GH:GetPlayerName() then return end  -- not addressed to us

    local msgs = GH.DB:GetMessagesSince(sinceTs)
    if #msgs == 0 then return end

    local BATCH       = 10
    local totalChunks = math.ceil(#msgs / BATCH)
    for ci = 1, totalChunks do
        local parts = { MSG_HIST_CHUNK, reqId,
                        tostring(ci), tostring(totalChunks) }
        for mi = (ci-1)*BATCH+1, math.min(ci*BATCH, #msgs) do
            local m = msgs[mi]
            parts[#parts+1] = table.concat(
                { tostring(m.ts), m.sender, m.text,
                  m.sourceLabel or "" }, MSG_HIST_SEP)
        end
        local payload = table.concat(parts, SEP)
        local frags   = Fragment(payload, NewKey(), PACKET_BN)

        -- If the request arrived via BNet (senderGameID non-nil), whisper chunks
        -- directly back. Otherwise broadcast on guild channel; the requester
        -- identifies its own chunks via reqId == _pendingHistReq.
        if senderGameID then
            for _, f in ipairs(frags) do BNSend(senderGameID, f) end
        else
            for _, f in ipairs(frags) do GuildSend(f, PRIO_HIST) end
        end
    end
```

### Receiving peer — `MSG_HIST_CHUNK` dispatch

```lua
elseif kind == MSG_HIST_CHUNK and #fields >= 4 then
    local reqId  = fields[2]
    if reqId ~= BNC._pendingHistReq then return end   -- not for us

    local ci    = tonumber(fields[3])
    local total = tonumber(fields[4])

    local bucket = BNC._histChunks[reqId]
    if not bucket then
        bucket = { total = total, received = 0 }
        BNC._histChunks[reqId] = bucket
    end
    if not bucket[ci] then
        bucket[ci]      = fields
        bucket.received = bucket.received + 1
    end

    if bucket.received >= bucket.total then
        BNC._pendingHistReq  = nil
        BNC._histChunks[reqId] = nil
        for i = 1, bucket.total do
            for fi = 5, #bucket[i] do
                local parts = {}
                for v in (bucket[i][fi] .. MSG_HIST_SEP)
                            :gmatch("([^"..MSG_HIST_SEP.."]*)"..MSG_HIST_SEP) do
                    parts[#parts+1] = v
                end
                if #parts >= 3 then
                    GH.DB:AddCommunityMessage({
                        ts          = tonumber(parts[1]) or 0,
                        sender      = parts[2],
                        text        = parts[3],
                        sourceLabel = parts[4] or "",
                        communityId = "bnet:" .. (parts[4] or ""),
                        isBNet      = true,
                    })
                end
            end
        end
        if GH.UI and GH.UI.OnChatMessage then
            GH.UI:OnChatMessage(Chat.XGUILD_ID)
        end
    end
```

### Database additions (`Database.lua`)

```lua
function DB:SetLastLogoutTime(ts)
    local s = sv(); if not s then return end
    s.settings.lastLogoutTime = ts
end

function DB:GetLastLogoutTime()
    local s = sv(); if not s then return 0 end
    return s.settings.lastLogoutTime or 0
end

-- Returns {ts, sender, text, sourceLabel} for all stored messages newer than sinceTs,
-- sorted ascending by ts. Covers both guildMessages and communityMsgs.
function DB:GetMessagesSince(sinceTs)
    local g = self:_guild(); if not g then return {} end
    local out = {}
    for _, m in ipairs(g.guildMessages or {}) do
        if (m.ts or 0) > sinceTs then out[#out+1] = m end
    end
    for _, m in ipairs(g.communityMsgs or {}) do
        if (m.ts or 0) > sinceTs then out[#out+1] = m end
    end
    table.sort(out, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return out
end
```

### `Main.lua` — persist logout time

```lua
frame:RegisterEvent("PLAYER_LOGOUT")
-- in OnEvent handler:
if event == "PLAYER_LOGOUT" then
    GH.DB:SetLastLogoutTime(time())
end
```

---

## Rate Budget

| Traffic | Priority | Worst-case packets | Impact |
| --- | --- | --- | --- |
| Live GCHAT relay | ALERT | 1–2 per message | Immediate, never queued |
| PING at login | NORMAL | ~5 total | Once per session |
| PONG replies | NORMAL | ~5 per peer | Once per session |
| HIST_CHUNK delivery | BULK | 200 msgs ÷ 10 × ~3 frags = **60** | Trickles; never touches ALERT/NORMAL budget |

With 25 rotating tags, CTL has 25 independent quota slots. History sync at BULK saturates none of them.

---

## Open Questions / Constraints

- `senderName` must be available inside `DispatchPayload` for `MSG_HIST_REQ` to whisper the reply back correctly. Thread it through from the `CHAT_MSG_ADDON` event arg or peer lookup.
- `DB:GetMessagesSince()` returns up to 2000 + 2000 entries. If a player was offline for weeks, the batch count could be very large. Implement a cap of 500 total messages returned (roughly 50 BULK chunks) to bound the delivery time.
- ChatThrottleLib must be loaded before `BNetChat.lua` — enforce via TOC order.
- Existing clients sending on `GHXC` will be silently ignored by upgraded clients (prefix not in `_TAGS`). This is acceptable during the rollout window.
