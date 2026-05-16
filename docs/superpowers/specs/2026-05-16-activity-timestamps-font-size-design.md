# Design: Activity Log Timestamp Fix + Font Size Setting

Date: 2026-05-16

## Problem Summary

1. **Spurious join/leave events**: Every login, the Activity tab floods with JOIN and LEAVE events
   for every guild member, all sharing the same timestamp (login time). WoW provides no API for
   historical guild join/leave dates, so these events are meaningless noise.

2. **No font size control**: All UI text is hardcoded to WoW's named font objects
   (`GameFontNormal`, `GameFontNormalSmall`). Users cannot adjust text size.

---

## Feature 1: Spurious Event Fix

### Root Cause

`ActivityLog._OnRosterUpdate()` uses a "two consecutive same-size calls" guard to avoid seeding
the baseline snapshot from partial data during WoW's login burst. However, the 0.5s debounce
already collapses all burst events into a single callback. This means only one call ever runs
during the login burst — the second "confirmation" never arrives naturally, leaving
`_initialised = false`. When the scan timer eventually forces another GUILD_ROSTER_UPDATE, the
second call arrives with the same count and sets `_initialised = true`, but edge cases in timing
(guild activity, scan timer delay) can cause a diff to run against an empty or stale
`_prevSnapshot`, logging the entire roster as joined or left.

### Fix: Simplified Initialization

Seed `_prevSnapshot` on the **first non-empty snapshot** after `_activeGuild` is set. Set
`_initialised = true` immediately. Remove the two-call wait entirely. The 0.5s debounce is
sufficient to ensure the roster data is complete.

**Before** (in `_OnRosterUpdate`):
```lua
if not _initialised then
    local size = 0
    for _ in pairs(snap) do size = size + 1 end
    if size == 0 then return end
    if size ~= _prevSnapshotSize then
        _prevSnapshot     = snap
        _prevSnapshotSize = size
        return
    end
    _prevSnapshot = snap
    _initialised  = true
    return
end
```

**After**:
```lua
if not _initialised then
    local size = 0
    for _ in pairs(snap) do size = size + 1 end
    if size == 0 then return end
    _prevSnapshot = snap
    _initialised  = true
    ActivityLog:_PruneSpuriousLoginEvents()
    return
end
```

### Fix: Prune Existing Bad Events

`ActivityLog:_PruneSpuriousLoginEvents()` runs once per session immediately after the baseline
is seeded. It scans the saved activity log for timestamps where **5 or more JOIN or LEAVE events
share the exact same `ts` value** — a pattern impossible in real play — and removes all events
at those timestamps.

```
for each unique ts in activityLog:
    count JOIN/LEAVE events at ts
    if count >= 5:
        remove all entries where ts == that timestamp
```

This cleans up events from all previous bugged logins without touching legitimate events (a real
simultaneous mass-join/leave in WoW is impossible through normal gameplay).

### Cleanup

The `_prevSnapshotSize` local variable in `ActivityLog.lua` is no longer needed and should be
removed along with its references.

### Files Changed
- `Interface/Addons/GuildHub/ActivityLog.lua`

---

## Feature 2: Font Size Setting

### Architecture: Shared Font Objects

Three shared font objects are created at addon load time in `Styles.lua` using WoW's
`CreateFont()` API. All UI font strings reference these objects via `SetFontObject()` rather
than WoW's built-in named fonts. Updating the shared object propagates live to every font string
tracking it — no reload required.

| Object | Default size | Role |
|---|---|---|
| `S.FontSmall` | 10pt | Most content: timestamps, descriptions, hints, chips |
| `S.FontNormal` | 12pt | Labels, row labels, nav text |
| `S.FontLarge` | 14pt | Window title, section headers |

Font path is derived from `GameFontNormal:GetFont()` to respect the active WoW locale's font
file (e.g., Chinese/Korean clients use different paths).

`S:ApplyFontSize(baseSize)` sets:
- `FontSmall  = baseSize`
- `FontNormal = baseSize + 2`
- `FontLarge  = baseSize + 4`

### Helper: `S:FS(parent, layer, tier)`

A factory function added to Styles.lua to avoid duplicating `CreateFontString` + `SetFontObject`
at every callsite:

```lua
function S:FS(parent, layer, tier)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    if tier == "normal" then
        fs:SetFontObject(S.FontNormal)
    elseif tier == "large" then
        fs:SetFontObject(S.FontLarge)
    else  -- default: "small"
        fs:SetFontObject(S.FontSmall)
    end
    return fs
end
```

### Refactor Scope

All 13 UI files replace `parent:CreateFontString(nil, layer, "GameFontNormal")` style calls
with `S:FS(parent, layer, "normal")` (or `"small"` / `"large"`). The existing pattern is
consistent enough that this is mechanical. Files affected:

- `UI/ActivityTab.lua`
- `UI/BanListDialog.lua`
- `UI/ChatTab.lua`
- `UI/EventsTab.lua`
- `UI/ExportDialog.lua`
- `UI/GroupsTab.lua`
- `UI/GuildRecruitTab.lua`
- `UI/MacroDialog.lua`
- `UI/MainWindow.lua`
- `UI/MembersTab.lua`
- `UI/MouseoverWindow.lua`
- `UI/ProfilePanel.lua`
- `UI/RecruitTab.lua`
- `UI/TeamsTab.lua`

### DB Setting

Add to `DEFAULTS.settings` in `Database.lua`:

```lua
fontSize = 10,  -- base size for S.FontSmall; Normal = +2, Large = +4
```

Migration: existing databases without this key receive the default via the existing
"add any missing settings keys" loop in `DB:Initialize()`.

### Settings Page Row

In `MainWindow.lua:BuildSettingsPage()`, add a "Font Size" row in the top section (after
Window Size, before Time Format) using the existing `MakeSpinner` helper:

```
Font Size     [9] [−] [+]     Sets the text size throughout GuildHub (applies immediately)
```

Range: 9–15. Default: 10. The spinner's `OnClick` additionally calls `S:ApplyFontSize(newVal)`
after saving to DB.

### Initialization

Call `S:ApplyFontSize(GH.DB:GetSetting("fontSize") or 10)` at the **start of
`UI:Initialize()`** in `MainWindow.lua`. By that point in `GH:Initialize()`, `DB:Initialize()`
has already run, so the saved value is available. The font objects themselves are created at
module load (Styles.lua top level), so they exist before any UI code runs.

### Files Changed
- `Interface/Addons/GuildHub/UI/Styles.lua` (add font objects, S:FS helper, S:ApplyFontSize)
- `Interface/Addons/GuildHub/Database.lua` (add fontSize default)
- `Interface/Addons/GuildHub/UI/MainWindow.lua` (settings row + startup apply)
- All 13 UI files listed above (CreateFontString refactor)

---

## Out of Scope

- Historical join date population from any source (WoW API does not expose this)
- Per-tab font size overrides
- Font family selection
- Scaling of non-text UI elements (buttons, row heights, icons)
