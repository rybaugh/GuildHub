# Guild News Persistence — Design Spec
**Date:** 2026-05-17

## Problem

Guild news shown in the sidebar is not retained across logins or between characters on the same account. The root cause is a stale-reference bug:

`UI/MainWindow.lua:582` captures the news buffer at window creation time (`ADDON_LOADED`), before `ActivateGuildNamespace` runs during `PLAYER_LOGIN` and sets `DB._activeGuild`. At capture time `GH.DB:GetNewsBuffer()` returns a fresh empty `{}` (because `_GuildData()` returns nil with no active guild). Every subsequent `RefreshGuildNews` call reads from that empty table, ignoring the real persisted buffer entirely.

The per-guild `newsBuffer` in `GuildHubDB.guilds[name]` is account-wide (`SavedVariables`, not `SavedVariablesPerCharacter`), so all characters in the same guild share it — the DB layer is correct. Only the UI read path is broken.

## Goal

- News persists across logins for every character in the same guild.
- Sidebar always shows the most recently captured items first.
- No visible timestamp added to rows (internal `ts` field only, used for ordering).

## Out of Scope

- Visible timestamps on news rows.
- Age-based pruning (the existing 50-entry cap is sufficient).
- Cross-character news sync via addon messages.

## Change Sites (3 total)

### 1. `Database.lua` — `AddNewsEntry`

Add `ts = GH:GetTimestamp()` to every stored entry. After inserting, sort the buffer by `ts` descending so newest-first order survives SavedVariables serialization. Dedup logic (`name + desc` equality check) is unchanged.

```lua
function DB:AddNewsEntry(entry)
    local gd = self:_GuildData()
    if not gd or not entry or not entry.desc then return end
    gd.newsBuffer = gd.newsBuffer or {}
    for _, e in ipairs(gd.newsBuffer) do
        if e.desc == entry.desc and e.name == entry.name then return end
    end
    entry.ts = entry.ts or GH:GetTimestamp()
    table.insert(gd.newsBuffer, 1, entry)
    table.sort(gd.newsBuffer, function(a, b)
        return (a.ts or 0) > (b.ts or 0)
    end)
    while #gd.newsBuffer > 50 do
        table.remove(gd.newsBuffer)
    end
end
```

### 2. `UI/MainWindow.lua` — Remove stale cache (line 582)

Delete:
```lua
win.newsBuffer = GH.DB:GetNewsBuffer()  -- persistent across sessions
```

This field is never valid (always captures `{}`) and must not exist.

### 3. `UI/MainWindow.lua` — `RefreshGuildNews` Source 2 loop

Change:
```lua
for _, entry in ipairs(win.newsBuffer or {}) do
```
To:
```lua
for _, entry in ipairs(GH.DB:GetNewsBuffer()) do
```

Every call to `RefreshGuildNews` now reads the live DB table. By the time the user can open the window, `_activeGuild` is set and the real buffer is returned.

## Data Flow After Fix

```
ADDON_LOADED  → DB:Initialize()          (GuildHubDB loaded, _activeGuild = nil)
PLAYER_LOGIN  → ActivateGuildNamespace() (_activeGuild = "GuildName")
              → GUILD_NEWS_UPDATE / CHAT_MSG_GUILD_ACHIEVEMENT
                  → AddNewsEntry({name, desc, iconTex, rawLink, ts})
                      → gd.newsBuffer sorted newest-first, capped 50

User opens window → UI:Show() → RefreshGuildNews()
    Source 1: live WoW API (GetGuildNewsItem)   — persists new entries to DB
    Source 2: GH.DB:GetNewsBuffer()             — reads real buffer, newest-first
    Dedup: shown{} table prevents double-display across both sources
```

## Files Changed

| File | Change |
|------|--------|
| `Database.lua` | `AddNewsEntry`: stamp `ts`, sort after insert |
| `UI/MainWindow.lua` | Remove `win.newsBuffer` capture (line 582) |
| `UI/MainWindow.lua` | `RefreshGuildNews` Source 2: read `GH.DB:GetNewsBuffer()` directly |
