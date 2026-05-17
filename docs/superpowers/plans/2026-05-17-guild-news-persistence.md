# Guild News Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix guild news so it persists across logins and between characters in the same guild by removing a stale table-reference bug and adding internal timestamps for newest-first ordering.

**Architecture:** Three surgical edits across two files. `Database.lua:AddNewsEntry` stamps a `ts` field and sorts the buffer descending on write. `UI/MainWindow.lua` drops the stale `win.newsBuffer` capture (which always captured an empty `{}` before `SetActiveGuild` ran) and makes `RefreshGuildNews` call `GH.DB:GetNewsBuffer()` directly on every refresh.

**Tech Stack:** Lua 5.1, WoW SavedVariables (`GuildHubDB`). No automated test framework — verification is in-game via `/reload` and character switching.

---

### Task 1: Stamp `ts` and sort on write in `AddNewsEntry`

**Files:**
- Modify: `Database.lua:479-490`

**Context:** `AddNewsEntry` currently inserts at index 1 (newest-first) but doesn't stamp a timestamp. Ordering is fragile after SavedVariables round-trips. We add `ts` so the sort is stable and entries written before this change (no `ts`) fall to the bottom via `a.ts or 0`.

- [ ] **Step 1: Open `Database.lua` and locate `AddNewsEntry` (lines 479-490)**

Current code:
```lua
function DB:AddNewsEntry(entry)
    local gd = self:_GuildData()
    if not gd or not entry or not entry.desc then return end
    gd.newsBuffer = gd.newsBuffer or {}
    for _, e in ipairs(gd.newsBuffer) do
        if e.desc == entry.desc and e.name == entry.name then return end
    end
    table.insert(gd.newsBuffer, 1, entry)
    while #gd.newsBuffer > 50 do
        table.remove(gd.newsBuffer)
    end
end
```

- [ ] **Step 2: Replace `AddNewsEntry` with the timestamped, sorted version**

```lua
function DB:AddNewsEntry(entry)
    local gd = self:_GuildData()
    if not gd or not entry or not entry.desc then return end
    gd.newsBuffer = gd.newsBuffer or {}
    for _, e in ipairs(gd.newsBuffer) do
        if e.desc == entry.desc and e.name == entry.name then return end
    end
    entry.ts = entry.ts or GH:GetTimestamp()
    table.insert(gd.newsBuffer, entry)
    table.sort(gd.newsBuffer, function(a, b)
        return (a.ts or 0) > (b.ts or 0)
    end)
    while #gd.newsBuffer > 50 do
        table.remove(gd.newsBuffer)
    end
end
```

Key changes:
- `entry.ts = entry.ts or GH:GetTimestamp()` — stamps the current time on write; existing entries with no `ts` sort to the bottom via `or 0`
- `table.insert(gd.newsBuffer, entry)` — appends (sort handles order, so position 1 insertion isn't needed)
- `table.sort(...)` — ensures newest-first regardless of insertion order or SavedVariables round-trips

- [ ] **Step 3: Commit**

```bash
git add Database.lua
git commit -m "fix(news): stamp ts on news entries and sort newest-first on write"
```

---

### Task 2: Remove stale `win.newsBuffer` capture

**Files:**
- Modify: `UI/MainWindow.lua:582`

**Context:** This line runs during `ADDON_LOADED`, before `PLAYER_LOGIN` → `ActivateGuildNamespace()` sets `DB._activeGuild`. At that moment `GetNewsBuffer()` returns a fresh empty `{}` (not the real DB table). Every `RefreshGuildNews` then reads from that empty table. The field must be deleted entirely.

- [ ] **Step 1: Open `UI/MainWindow.lua` and find line 582**

```lua
win.newsBuffer = GH.DB:GetNewsBuffer()  -- persistent across sessions
```

- [ ] **Step 2: Delete that line entirely**

The line and its comment are removed. `win.newsBuffer` must not exist anywhere in the file after this step. Verify with a search for `win.newsBuffer` — the only remaining reference should be the Source 2 loop you will fix in Task 3.

- [ ] **Step 3: Commit**

```bash
git add UI/MainWindow.lua
git commit -m "fix(news): remove stale win.newsBuffer capture that always read empty table"
```

---

### Task 3: Read DB directly in `RefreshGuildNews` Source 2 loop

**Files:**
- Modify: `UI/MainWindow.lua:1659-1674` (line numbers shift by -1 after Task 2's deletion)

**Context:** Source 2 of `RefreshGuildNews` fills remaining news rows from the persistent buffer. After Task 2 removes `win.newsBuffer`, this loop must read `GH.DB:GetNewsBuffer()` directly. By the time a user can open the window, `_activeGuild` is set, so `GetNewsBuffer()` returns the real buffer.

- [ ] **Step 1: Locate the Source 2 comment block in `RefreshGuildNews`**

```lua
-- ── Source 2: persistent buffer (achievements + saved WoW API news) ────────
for _, entry in ipairs(win.newsBuffer or {}) do
```

- [ ] **Step 2: Replace `win.newsBuffer or {}` with `GH.DB:GetNewsBuffer()`**

```lua
-- ── Source 2: persistent buffer (achievements + saved WoW API news) ────────
for _, entry in ipairs(GH.DB:GetNewsBuffer()) do
```

No other changes in this loop — `shown{}` dedup, row population, and the `rowIdx >= #rows` guard are all correct as-is.

- [ ] **Step 3: Verify no remaining references to `win.newsBuffer` in the file**

Search `UI/MainWindow.lua` for `newsBuffer`. The only matches should be:
- The two `GH.DB:AddNewsEntry({...})` call sites (lines ~616 and ~1648) — correct, unchanged
- `GH.DB:GetNewsBuffer()` in the Source 2 loop — the line you just changed

If any `win.newsBuffer` reference remains, remove it.

- [ ] **Step 4: Commit**

```bash
git add UI/MainWindow.lua
git commit -m "fix(news): read DB directly in RefreshGuildNews instead of stale cache"
```

---

### Task 4: In-game verification

**Context:** WoW addons have no automated test runner. Verification is in-game.

- [ ] **Step 1: Test persistence across `/reload`**

1. Log in with any character that is in a guild.
2. Open GuildHub (`/gh`). Note which news items appear in the sidebar (or note "No recent news" if the guild has none yet).
3. Wait for a guild achievement to fire, or manually trigger a `GUILD_NEWS_UPDATE` by opening the default Guild window briefly, then closing it.
4. Confirm news appears in the GuildHub sidebar.
5. Type `/reload` in chat.
6. Open GuildHub again. The same news items must still appear — they should not reset to "No recent news".

Expected: News survives the reload.

- [ ] **Step 2: Test persistence across a character switch**

1. Note the news items visible on Character A (same guild as Character B).
2. Log out to character select and log in as Character B (same guild).
3. Open GuildHub on Character B.

Expected: The same news items appear. The sidebar is not empty.

- [ ] **Step 3: Test newest-first ordering**

1. Have two news items in the buffer. The one added most recently should appear at the top of the sidebar.
2. If no new news arrives naturally, inspect `GuildHubDB.guilds[guildName].newsBuffer` via the Lua console or `/gh debugdump` to confirm entries have a `ts` field and are sorted descending.

Expected: Entries have `ts` values; highest `ts` is at index 1.

- [ ] **Step 4: Final commit (if any cleanup needed)**

```bash
git add -A
git commit -m "fix(news): guild news persists across logins and characters"
```

If no files changed after verification, skip this step.
