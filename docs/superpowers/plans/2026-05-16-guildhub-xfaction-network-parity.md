# GuildHub XFaction Network Parity + History Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port XFaction's 25-tag rate-limit bypass, BNetChatThrottleLib priority queuing, and guild-channel peer discovery into GuildHub, then add a first-responder history-sync protocol that delivers missed messages since last logout over BULK priority.

**Architecture:** BNetChat.lua replaces its single `GHXC` channel prefix with a 25-tag rotating pool (`GHCH01`–`GHCH25`), wraps all addon-channel sends through BNetChatThrottleLib at ALERT/NORMAL/BULK priority, and expands the PING broadcast from BNet-only to both BNet and the GUILD channel. On first PONG received, the logging-in player sends a HIST_REQ (targeted by name) to that peer; the peer responds with HIST_CHUNK batches of up to 10 messages each at BULK priority.

**Tech Stack:** Lua 5.1 (WoW runtime), BNetChatThrottleLib (embedded, copied from XFaction), WoW addon APIs (`C_ChatInfo`, `BNSendGameData`, `CHAT_MSG_ADDON`, `BN_CHAT_MSG_ADDON`), GuildHub's existing `GH.DB`, `GH:Debug()`, and `GH:GetTimestamp()`.

**Spec:** `docs/superpowers/specs/2026-05-16-guildhub-xfaction-network-design.md`

---

## File Map

| File | Change |
| --- | --- |
| `Library/BNetChatThrottleLib.lua` | **Create** — copy from XFaction |
| `GuildHub.toc` | **Modify** — add lib entry at top |
| `BNetChat.lua` | **Modify** — tag pool, CTL helpers, guild PING, HIST protocol |
| `Database.lua` | **Modify** — three new methods |
| `Main.lua` | **Modify** — PLAYER_LOGOUT hook |
| `ProfileSync.lua` | **Modify** — replace 0.5 s OnUpdate queue with CTL |

---

## Task 1: Bundle BNetChatThrottleLib

**Files:**
- Create: `Interface/Addons/GuildHub/Library/BNetChatThrottleLib.lua`
- Modify: `Interface/Addons/GuildHub/GuildHub.toc`

- [ ] **Step 1: Copy the library**

```powershell
Copy-Item `
  "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\Addons\XFaction\Library\ChatThrottleLib\BNetChatThrottleLib.lua" `
  "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\Addons\GuildHub\Library\BNetChatThrottleLib.lua"
```

Expected: no output, file appears at the destination path.

- [ ] **Step 2: Add to GuildHub.toc before Core.lua**

In `GuildHub.toc`, the current first line is `Core.lua`. Insert the library line above it:

```
## Interface: 120005
## Title: GuildHub
## Notes: Modern guild social window — members, group presets, persistent chats, events, and recruitment
## Author: Storm
## Version: 1.0
## SavedVariables: GuildHubDB

Library/BNetChatThrottleLib.lua
Core.lua
Debug.lua
...rest unchanged...
```

- [ ] **Step 3: Verify the library loads**

Enable debug mode in-game: `/gh debug`

Then type in chat: `/run print(BNetChatThrottleLib and BNetChatThrottleLib.version or "nil")`

Expected output in chat: a version number (e.g. `24`), not `nil`. If it prints `nil`, the TOC path is wrong — recheck that `Library/BNetChatThrottleLib.lua` is the exact relative path used in the TOC.

- [ ] **Step 4: Commit**

```bash
git add Library/BNetChatThrottleLib.lua GuildHub.toc
git commit -m "chore: bundle BNetChatThrottleLib for priority-queued addon sends"
```

---

## Task 2: Tag Pool + CTL Send Helpers

**Files:**
- Modify: `Interface/Addons/GuildHub/BNetChat.lua`

The changes in this task touch the constant block (lines 10–23), the `ChanSend` / new `GuildSend` helpers (lines 109–125), `SendToChannel` (line 123), `RelayGuildChat` (lines 131–145), and `Initialize` (lines 346–399).

- [ ] **Step 1: Replace the `PREFIX_CHAN` constant block**

Find and replace in `BNetChat.lua`:

```lua
-- old (remove these two lines)
local PREFIX_BNET  = "GHBN"   -- addon prefix carried in BNSendGameData calls
local PREFIX_CHAN   = "GHXC"  -- addon prefix for the optional channel relay bus
```

```lua
-- new
local PREFIX_BNET = "GHBN"   -- addon prefix for BNSendGameData calls (BNet-only)
local TAG_COUNT   = 25
local PRIO_LIVE   = "ALERT"  -- live guild chat relay
local PRIO_META   = "NORMAL" -- PING, PONG, profile sync
local PRIO_HIST   = "BULK"   -- history chunks

-- Populated at module load; used for O(1) receive filtering and random tag picks.
local _TAGS    = {}  -- [prefixString] = true
local _TAG_ARR = {}  -- [1..TAG_COUNT] = prefixString
for i = 1, TAG_COUNT do
    local t = string.format("GHCH%02d", i)
    _TAGS[t]    = true
    _TAG_ARR[i] = t
end

local function GetRandomTag()
    return _TAG_ARR[math.random(TAG_COUNT)]
end
```

- [ ] **Step 2: Replace `ChanSend` and add `GuildSend`**

Find the existing `ChanSend` function (around line 109):

```lua
local function ChanSend(wire)
    if not BNC._chanNum then return end
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if C_ChatInfo then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX_CHAN, wire, "CHANNEL", BNC._chanNum)
    end
end
```

Replace with:

```lua
local function ChanSend(wire, prio)
    if not BNC._chanNum then return end
    local ctl = rawget(_G, "BNetChatThrottleLib")
    if ctl then
        pcall(ctl.SendAddonMessage, ctl, prio or PRIO_META,
              GetRandomTag(), wire, "CHANNEL", BNC._chanNum)
    end
end

local function GuildSend(wire, prio)
    local ctl = rawget(_G, "BNetChatThrottleLib")
    if ctl then
        pcall(ctl.SendAddonMessage, ctl, prio or PRIO_META,
              GetRandomTag(), wire, "GUILD")
    end
end
```

- [ ] **Step 3: Add `prio` parameter to `SendToChannel`**

Find:

```lua
local function SendToChannel(frags)
    for _, f in ipairs(frags) do ChanSend(f) end
end
```

Replace with:

```lua
local function SendToChannel(frags, prio)
    for _, f in ipairs(frags) do ChanSend(f, prio) end
end
```

- [ ] **Step 4: Pass `PRIO_LIVE` in `RelayGuildChat`**

Find in `BNC:RelayGuildChat`:

```lua
    SendToChannel(chFrags)
```

Replace with:

```lua
    SendToChannel(chFrags, PRIO_LIVE)
```

Also remove the now-unused `chFrags` local — the same `frags` variable can be reused since both BNet and channel use the same `PACKET_BN` size:

Current code:
```lua
    local bnFrags  = Fragment(payload, key, PACKET_BN)
    local chFrags  = Fragment(payload, key, PACKET_CH)
    SendToPeers(bnFrags)
    SendToChannel(chFrags)
```

Replace with:

```lua
    local frags = Fragment(payload, key, PACKET_BN)
    SendToPeers(frags)
    SendToChannel(frags, PRIO_LIVE)
```

- [ ] **Step 5: Update `Initialize` — register tag pool, remove old prefix**

Find in `Initialize`:

```lua
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_BNET)
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_CHAN)
    end
```

Replace with:

```lua
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_BNET)
        for _, t in ipairs(_TAG_ARR) do
            C_ChatInfo.RegisterAddonMessagePrefix(t)
        end
    end
```

- [ ] **Step 6: Update `chFrame` receive handler to use `_TAGS` lookup**

Find the `chFrame` event script (around line 362):

```lua
    local chFrame = CreateFrame("Frame")
    chFrame:RegisterEvent("CHAT_MSG_ADDON")
    chFrame:SetScript("OnEvent", function(_, _, prefix, msg)
        if prefix == PREFIX_CHAN then
            OnReceive(prefix, msg, "CHANNEL", nil)
        end
    end)
```

Replace with:

```lua
    local chFrame = CreateFrame("Frame")
    chFrame:RegisterEvent("CHAT_MSG_ADDON")
    chFrame:SetScript("OnEvent", function(_, _, prefix, msg, distrib)
        if _TAGS[prefix] then
            local proto = (distrib == "GUILD") and "GUILD" or "CHANNEL"
            OnReceive(prefix, msg, proto, nil)
        end
    end)
```

- [ ] **Step 7: Verify in-game**

Reload UI (`/reload`), enable debug: `/gh debug`

Send a guild chat message. Expected debug output in chat:
```
BNetChat: RelayGuildChat key=<8chars>
```

Then type: `/run print(GetNumRegisteredAddonMessagePrefixes and GetNumRegisteredAddonMessagePrefixes() or "api missing")`

Expected: a number ≥ 26 (25 GHCH tags + GHBN + any other addons).

- [ ] **Step 8: Commit**

```bash
git add BNetChat.lua
git commit -m "feat: replace single channel prefix with 25-tag pool and BNetChatThrottleLib send helpers"
```

---

## Task 3: Database Methods

**Files:**
- Modify: `Interface/Addons/GuildHub/Database.lua`

Add three methods after the existing `AddCommunityMessage` block (around line 550).

- [ ] **Step 1: Add `GetLastLogoutTime` and `SetLastLogoutTime`**

After the closing `end` of `DB:AddCommunityMessage` (around line 550), add:

```lua
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
```

- [ ] **Step 2: Add `GetMessagesSince`**

Immediately after the above two methods, add:

```lua
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
```

- [ ] **Step 3: Verify in-game**

Reload UI. In chat:

```lua
/run local msgs = GuildHub.DB:GetMessagesSince(0); print("msgs since epoch:", #msgs)
/run print("lastLogout:", GuildHub.DB:GetLastLogoutTime())
/run GuildHub.DB:SetLastLogoutTime(1000); print("set:", GuildHub.DB:GetLastLogoutTime())
```

Expected:
- First line: `msgs since epoch: <N>` where N is your stored history count.
- Second line: `lastLogout: 0` (not yet set by logout hook).
- Third line: `set: 1000`.

- [ ] **Step 4: Commit**

```bash
git add Database.lua
git commit -m "feat: add GetLastLogoutTime, SetLastLogoutTime, GetMessagesSince to Database"
```

---

## Task 4: PLAYER_LOGOUT Hook

**Files:**
- Modify: `Interface/Addons/GuildHub/Main.lua`

The `initFrame` in Main.lua (line 115) already handles `ADDON_LOADED`, `PLAYER_LOGIN`, and `GUILD_ROSTER_UPDATE`. We add `PLAYER_LOGOUT` to the same frame.

- [ ] **Step 1: Register the event**

Find in `Main.lua` (around line 115):

```lua
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
```

Replace with:

```lua
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
initFrame:RegisterEvent("PLAYER_LOGOUT")
```

- [ ] **Step 2: Handle the event**

Find the `OnEvent` handler's closing section (around line 143):

```lua
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Fallback: GetGuildInfo("player") may not be reliable at PLAYER_LOGIN time.
        ActivateGuildNamespace()
        if _guildActivated then
            initFrame:UnregisterEvent("GUILD_ROSTER_UPDATE")
        end
    end
end)
```

Replace with:

```lua
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Fallback: GetGuildInfo("player") may not be reliable at PLAYER_LOGIN time.
        ActivateGuildNamespace()
        if _guildActivated then
            initFrame:UnregisterEvent("GUILD_ROSTER_UPDATE")
        end
    elseif event == "PLAYER_LOGOUT" then
        GH.DB:SetLastLogoutTime(time())
    end
end)
```

- [ ] **Step 3: Verify**

Log out of WoW (or use `/reload` — note PLAYER_LOGOUT does NOT fire on `/reload`, only on actual logout/quit). After logging back in:

```lua
/run print("lastLogout:", GuildHub.DB:GetLastLogoutTime())
```

Expected: a Unix timestamp matching roughly when you logged out (e.g. `lastLogout: 1747680000`). If it still shows `0`, test by calling it manually: `/run GuildHub.DB:SetLastLogoutTime(time()); print(GuildHub.DB:GetLastLogoutTime())` — if that works but logout doesn't, verify `PLAYER_LOGOUT` is spelled correctly and fires in the test environment (some emulators don't fire it).

- [ ] **Step 4: Commit**

```bash
git add Main.lua
git commit -m "feat: persist last-logout timestamp on PLAYER_LOGOUT for history sync"
```

---

## Task 5: ProfileSync Throttle Migration

**Files:**
- Modify: `Interface/Addons/GuildHub/ProfileSync.lua`

Replace the 0.5 s OnUpdate frame and manual queue with a direct CTL call. The send prefix and receive path are **not** changed — ProfileSync stays on `GH.ADDON_PREFIX`.

- [ ] **Step 1: Remove the queue, add CTL-based `_Send`**

Find and remove the entire outbound-queue block (lines 28–43):

```lua
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
```

Replace with:

```lua
local function _Send(msg)
    if #msg > 250 then return end
    if not GH:IsInGuild() then return end
    local ctl = rawget(_G, "BNetChatThrottleLib")
    if ctl then
        pcall(ctl.SendAddonMessage, ctl, "NORMAL",
              GH.ADDON_PREFIX, msg, "GUILD")
    else
        pcall(C_ChatInfo.SendAddonMessage, GH.ADDON_PREFIX, msg, "GUILD")
    end
end
```

- [ ] **Step 2: Remove the throttle frame from `Initialize`**

Find in `ProfileSync:Initialize()` (lines 48–57):

```lua
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
```

Delete those 9 lines entirely. The rest of `Initialize` (the listen frame and the C_Timer.After) is unchanged.

- [ ] **Step 3: Replace all `_Enqueue` calls with `_Send`**

There are 8 `_Enqueue(...)` calls in ProfileSync.lua. Replace every one:

```lua
-- Find (replace_all):
_Enqueue(
-- Replace with:
_Send(
```

Verify with a search that no `_Enqueue` or `_outQueue` or `_queueFrame` references remain:

```bash
grep -n "_Enqueue\|_outQueue\|_queueFrame\|_FlushQueue" "Interface/Addons/GuildHub/ProfileSync.lua"
```

Expected: no matches.

- [ ] **Step 4: Verify in-game**

Reload UI. Trigger a profile sync: `/run GuildHub.ProfileSync:RequestSync()`

With `/gh debug` on, expected output: no Lua errors and sync messages flow to other online GuildHub users without any 0.5 s batching visible.

- [ ] **Step 5: Commit**

```bash
git add ProfileSync.lua
git commit -m "refactor: replace ProfileSync 0.5s OnUpdate queue with BNetChatThrottleLib NORMAL priority"
```

---

## Task 6: Extended PING + Guild Channel Discovery

**Files:**
- Modify: `Interface/Addons/GuildHub/BNetChat.lua`

This task extends the PING payload to carry `lastLogoutTs`, broadcasts PING on the GUILD channel, updates `RegisterPeer` to store the new fields, and updates `DispatchPayload` to handle guild-channel PING/PONG (where `senderGameID` is nil).

- [ ] **Step 1: Extend `RegisterPeer` signature**

Find (around line 188):

```lua
local function RegisterPeer(gameID, name, guild)
    local isNew = BNC._peers[gameID] == nil
    BNC._peers[gameID] = { name = name, guild = guild, lastSeen = time() }
    if isNew and GH.UI and GH.UI.OnChannelListChanged then
        GH.UI:OnChannelListChanged()
    end
end
```

Replace with:

```lua
local function RegisterPeer(peerKey, name, guild, lastLogoutTs, protocol)
    local isNew = BNC._peers[peerKey] == nil
    BNC._peers[peerKey] = {
        name         = name,
        guild        = guild,
        lastSeen     = time(),
        lastLogoutTs = tonumber(lastLogoutTs) or 0,
        protocol     = protocol or "BNET",
    }
    if isNew and GH.UI and GH.UI.OnChannelListChanged then
        GH.UI:OnChannelListChanged()
    end
end
```

- [ ] **Step 2: Update `PingAllFriends` to include `lastLogoutTs` and broadcast on GUILD**

Find `BNC:PingAllFriends` (around line 148):

```lua
function BNC:PingAllFriends()
    local payload = table.concat({ MSG_PING, GH:GetPlayerName(), GH:GetGuildName() }, SEP)
    local frags   = Fragment(payload, NewKey(), PACKET_BN)
    local targets = OnlineWoWGameIDs()
    for _, gid in ipairs(targets) do
        for _, f in ipairs(frags) do BNSend(gid, f) end
    end
    GH:Debug("BNetChat", "PingAllFriends: %d online friends probed", #targets)
end
```

Replace with:

```lua
function BNC:PingAllFriends()
    local payload = table.concat(
        { MSG_PING, GH:GetPlayerName(), GH:GetGuildName(),
          tostring(GH.DB:GetLastLogoutTime()) }, SEP)
    local key   = NewKey()
    local frags = Fragment(payload, key, PACKET_BN)

    -- BNet: whisper each online WoW friend
    local targets = OnlineWoWGameIDs()
    for _, gid in ipairs(targets) do
        for _, f in ipairs(frags) do BNSend(gid, f) end
    end

    -- Guild channel: broadcast for same-realm guildmates (no BNet required)
    for _, f in ipairs(frags) do GuildSend(f, PRIO_META) end

    GH:Debug("BNetChat", "PingAllFriends: %d BNet friends + guild broadcast", #targets)
end
```

- [ ] **Step 3: Update `ReplyPong` to accept a return-channel option**

Find `ReplyPong` (around line 158):

```lua
local function ReplyPong(gameID)
    local payload = table.concat({ MSG_PONG, GH:GetPlayerName(), GH:GetGuildName() }, SEP)
    local frags   = Fragment(payload, NewKey(), PACKET_BN)
    for _, f in ipairs(frags) do BNSend(gameID, f) end
end
```

Replace with:

```lua
local function ReplyPong(gameID)
    local payload = table.concat({ MSG_PONG, GH:GetPlayerName(), GH:GetGuildName() }, SEP)
    local frags   = Fragment(payload, NewKey(), PACKET_BN)
    if gameID then
        for _, f in ipairs(frags) do BNSend(gameID, f) end
    else
        -- Received via guild channel; reply on the same channel
        for _, f in ipairs(frags) do GuildSend(f, PRIO_META) end
    end
end
```

- [ ] **Step 4: Update `DispatchPayload` MSG_PING and MSG_PONG cases**

Find the MSG_PING case in `DispatchPayload` (around line 206):

```lua
    if kind == MSG_PING and senderGameID then
        RegisterPeer(senderGameID, fields[2] or "?", fields[3] or "?")
        GH:Debug("BNetChat", "Ping from %s [%s]", fields[2], fields[3])
        ReplyPong(senderGameID)
```

Replace with:

```lua
    if kind == MSG_PING then
        local peerKey  = senderGameID or ("guild:" .. (fields[2] or "unknown"))
        local protocol = senderGameID and "BNET" or "GUILD"
        RegisterPeer(peerKey, fields[2] or "?", fields[3] or "?", fields[4], protocol)
        GH:Debug("BNetChat", "Ping from %s [%s] via %s", fields[2], fields[3], protocol)
        ReplyPong(senderGameID)  -- nil → replies via guild channel
```

Find the MSG_PONG case (around line 212):

```lua
    elseif kind == MSG_PONG and senderGameID then
        RegisterPeer(senderGameID, fields[2] or "?", fields[3] or "?")
        GH:Debug("BNetChat", "Pong from %s [%s]", fields[2], fields[3])
```

Replace with:

```lua
    elseif kind == MSG_PONG then
        local peerKey  = senderGameID or ("guild:" .. (fields[2] or "unknown"))
        local protocol = senderGameID and "BNET" or "GUILD"
        RegisterPeer(peerKey, fields[2] or "?", fields[3] or "?", nil, protocol)
        GH:Debug("BNetChat", "Pong from %s [%s] via %s", fields[2], fields[3], protocol)
```

- [ ] **Step 5: Verify in-game**

Reload UI with `/gh debug` on. Log in (or wait the 20 s PING_DELAY). Expected debug output:

```
BNetChat: PingAllFriends: N BNet friends + guild broadcast
BNetChat: Ping from <name> [<guild>] via GUILD   ← (your own ping echoes back via guild channel)
```

If a second GuildHub client is online and in your guild, you should also see:
```
BNetChat: Pong from <name> [<guild>] via GUILD
```

- [ ] **Step 6: Commit**

```bash
git add BNetChat.lua
git commit -m "feat: extend PING with lastLogoutTs and broadcast on GUILD channel for same-realm peer discovery"
```

---

## Task 7: History Sync Protocol

**Files:**
- Modify: `Interface/Addons/GuildHub/BNetChat.lua`

Adds the HIST_REQ / HIST_CHUNK message types, the `_RequestHistory` function, the first-PONG trigger, the responding-peer dispatch, and the receiving-peer dispatch.

- [ ] **Step 1: Add new constants and state**

In the constants block at the top of `BNetChat.lua`, after the existing `MSG_GCHAT` line:

```lua
-- existing:
local MSG_GCHAT    = "G"      -- cross-guild chat payload
-- add after:
local MSG_HIST_REQ   = "R"   -- request history since a timestamp
local MSG_HIST_CHUNK = "C"   -- one batch of historical messages
local MSG_HIST_SEP   = "\31" -- inner field separator within a chunk (avoids clash with SEP=\30)
```

In the state block (after `BNC._chanNum`):

```lua
-- existing:
BNC._chanNum   = nil  -- WoW channel slot number, set after JoinTemporaryChannel
-- add after:
BNC._pendingHistReq = nil   -- requestId we sent; nil once fulfilled or no history needed
BNC._histChunks     = {}    -- [requestId] = {total=N, received=0, [1..N]=fields}
```

- [ ] **Step 2: Add `BNC:_RequestHistory`**

Add this function after `ReplyPong` and before `AcceptFragment`:

```lua
function BNC:_RequestHistory(peer)
    if not peer then return end
    local reqId   = NewKey()
    local sinceTs = GH.DB:GetLastLogoutTime()
    BNC._pendingHistReq = reqId
    BNC._seen[reqId]    = time()   -- pre-register so our own echo is ignored

    local payload = table.concat(
        { MSG_HIST_REQ, reqId, tostring(sinceTs), peer.name }, SEP)
    local frags = Fragment(payload, NewKey(), PACKET_BN)

    if peer.protocol == "BNET" then
        -- Direct BNet whisper — only that peer receives it
        for gid, p in pairs(BNC._peers) do
            if p.name == peer.name then
                for _, f in ipairs(frags) do BNSend(gid, f) end
                break
            end
        end
    else
        -- Guild-channel broadcast; targetName field (fields[4]) keeps only
        -- the named peer from responding
        for _, f in ipairs(frags) do GuildSend(f, PRIO_HIST) end
    end

    GH:Debug("BNetChat", "_RequestHistory reqId=%s since=%s target=%s",
             reqId, tostring(sinceTs), peer.name)
end
```

- [ ] **Step 3: Trigger `_RequestHistory` on first PONG**

In `DispatchPayload`, find the MSG_PONG block added in Task 6:

```lua
    elseif kind == MSG_PONG then
        local peerKey  = senderGameID or ("guild:" .. (fields[2] or "unknown"))
        local protocol = senderGameID and "BNET" or "GUILD"
        RegisterPeer(peerKey, fields[2] or "?", fields[3] or "?", nil, protocol)
        GH:Debug("BNetChat", "Pong from %s [%s] via %s", fields[2], fields[3], protocol)
```

Add one line at the end of that block (before the next `elseif`):

```lua
    elseif kind == MSG_PONG then
        local peerKey  = senderGameID or ("guild:" .. (fields[2] or "unknown"))
        local protocol = senderGameID and "BNET" or "GUILD"
        RegisterPeer(peerKey, fields[2] or "?", fields[3] or "?", nil, protocol)
        GH:Debug("BNetChat", "Pong from %s [%s] via %s", fields[2], fields[3], protocol)
        if not BNC._pendingHistReq then
            BNC:_RequestHistory(BNC._peers[peerKey])
        end
```

- [ ] **Step 4: Add MSG_HIST_REQ dispatch (responding peer)**

In `DispatchPayload`, after the MSG_GCHAT `elseif` block and before the closing `end`, add:

```lua
    elseif kind == MSG_HIST_REQ and #fields >= 4 then
        local reqId   = fields[2]
        local sinceTs = tonumber(fields[3]) or 0
        local target  = fields[4]

        -- Only the named target responds; all others silently discard
        if target ~= GH:GetPlayerName() then return end

        local msgs = GH.DB:GetMessagesSince(sinceTs)
        if #msgs == 0 then
            GH:Debug("BNetChat", "HIST_REQ from %s: no messages since %s", target, tostring(sinceTs))
            return
        end

        local BATCH       = 10
        local totalChunks = math.ceil(#msgs / BATCH)
        GH:Debug("BNetChat", "HIST_REQ: sending %d msgs in %d chunks to %s",
                 #msgs, totalChunks, target)

        for ci = 1, totalChunks do
            local parts = { MSG_HIST_CHUNK, reqId,
                            tostring(ci), tostring(totalChunks) }
            for mi = (ci - 1) * BATCH + 1, math.min(ci * BATCH, #msgs) do
                local m = msgs[mi]
                parts[#parts + 1] = table.concat(
                    { tostring(m.ts or 0),
                      m.sender  or "",
                      m.text    or "",
                      m.sourceLabel or m.communityId or "" },
                    MSG_HIST_SEP)
            end
            local payload = table.concat(parts, SEP)
            local frags   = Fragment(payload, NewKey(), PACKET_BN)

            -- Prefer BNet whisper back to requester; fall back to guild channel
            if senderGameID then
                for _, f in ipairs(frags) do BNSend(senderGameID, f) end
            else
                for _, f in ipairs(frags) do GuildSend(f, PRIO_HIST) end
            end
        end
```

- [ ] **Step 5: Add MSG_HIST_CHUNK dispatch (receiving peer)**

Immediately after the MSG_HIST_REQ block (still inside `DispatchPayload`), add:

```lua
    elseif kind == MSG_HIST_CHUNK and #fields >= 4 then
        local reqId = fields[2]
        -- Ignore chunks not addressed to our pending request
        if reqId ~= BNC._pendingHistReq then return end

        local ci    = tonumber(fields[3])
        local total = tonumber(fields[4])
        if not ci or not total then return end

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
            BNC._pendingHistReq      = nil
            BNC._histChunks[reqId]   = nil
            local Chat = GH.Chat
            local inserted = 0
            for i = 1, bucket.total do
                for fi = 5, #bucket[i] do
                    local raw = bucket[i][fi]
                    local parts = {}
                    for v in (raw .. MSG_HIST_SEP)
                                :gmatch("([^" .. MSG_HIST_SEP .. "]*)" .. MSG_HIST_SEP) do
                        parts[#parts + 1] = v
                    end
                    if #parts >= 3 then
                        local entry = {
                            ts          = tonumber(parts[1]) or 0,
                            sender      = parts[2],
                            text        = parts[3],
                            sourceLabel = parts[4] or "",
                            communityId = "bnet:" .. (parts[4] or ""),
                            isBNet      = true,
                        }
                        local isNew = GH.DB:AddCommunityMessage(entry)
                        if isNew and Chat then
                            Chat.communityMsgs[#Chat.communityMsgs + 1] = entry
                            if #Chat.communityMsgs > 2000 then
                                table.remove(Chat.communityMsgs, 1)
                            end
                            inserted = inserted + 1
                        end
                    end
                end
            end
            GH:Debug("BNetChat", "History sync complete: %d new messages inserted", inserted)
            if inserted > 0 and GH.UI and GH.UI.OnChatMessage then
                GH.UI:OnChatMessage(Chat and Chat.XGUILD_ID or "__XGUILD__")
            end
        end
```

- [ ] **Step 6: Verify in-game (two clients required)**

On Client A (the one logging in): `/gh debug`

On Client B (already online in the same guild):

```
/gh debug
```

Log Client A out, then back in. After the 20 s PING_DELAY, expected sequence on Client A:

```
BNetChat: PingAllFriends: N BNet friends + guild broadcast
BNetChat: Pong from <ClientB> [<guild>] via GUILD
BNetChat: _RequestHistory reqId=<8chars> since=<ts> target=<ClientB>
BNetChat: History sync complete: N new messages inserted
```

Expected on Client B:

```
BNetChat: Ping from <ClientA> [<guild>] via GUILD
BNetChat: HIST_REQ: sending N msgs in M chunks to <ClientA>
```

If `lastLogoutTime` is still `0` (Task 4 not yet tested with a real logout), history sync will request everything since epoch — expected to return up to 500 messages. That is correct behaviour.

- [ ] **Step 7: Commit**

```bash
git add BNetChat.lua
git commit -m "feat: add first-responder history sync protocol (HIST_REQ/HIST_CHUNK) for missed messages since last logout"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** Tag pool ✓ (Task 2) · CTL ✓ (Tasks 2, 5) · Guild PING ✓ (Task 6) · Peer shape ✓ (Task 6) · HIST_REQ/CHUNK ✓ (Task 7) · DB methods ✓ (Task 3) · PLAYER_LOGOUT ✓ (Task 4) · 500-msg cap ✓ (Task 3) · senderGameID reply path ✓ (Task 7 Step 4)
- [x] **No placeholders:** All steps have complete code blocks.
- [x] **Type consistency:** `peerKey` (string, `gameID` or `"guild:<name>"`) used consistently across Tasks 6–7. `BNC._peers[peerKey]` accessed the same way everywhere. `_RequestHistory(peer)` receives a peer table, always via `BNC._peers[peerKey]`. `GetMessagesSince` returns `{ts, sender, text, sourceLabel, communityId, ...}` matching `AddCommunityMessage` field names.
