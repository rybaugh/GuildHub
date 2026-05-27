# GuildHub — Permissions System & Guild Note Editing

**Date:** 2026-05-27

## Problem

GuildHub currently uses a single `GH:IsOfficer()` check (based on officer-chat-speak rank flags) for all privileged actions. This ignores the granular per-rank permissions that guild masters configure in WoW's guild control panel. As a result:

- Officers who have Promote but not Kick still see the Kick button.
- Members with Edit Public Note permission cannot edit guild notes from GuildHub at all.
- The permission logic is tangled into Core.lua via a fragile threshold-detection heuristic.

## Goals

1. Read actual WoW rank permission flags and cache them per rank.
2. Expose named, single-purpose permission checks used by all UI code.
3. Wire up guild note editing (read + write) using the correct permission.
4. Replace all existing ad-hoc `IsOfficer()` call sites with the appropriate specific check.

## Architecture

### New file: `Permissions.lua`

Loaded before `Main.lua` in the TOC.

Contains:

- `GH.PERM` — named constants table mapping permission names to `GuildControlGetRankFlags` return indices:

```lua
GUILD_CHAT_LISTEN   = 1
GUILD_CHAT_SPEAK    = 2
OFFICER_CHAT_LISTEN = 3
OFFICER_CHAT_SPEAK  = 4   -- confirmed by existing DetectOfficerThreshold code
PROMOTE             = 5
DEMOTE              = 6
INVITE              = 7
REMOVE              = 8   -- kick / uninvite
SET_MOTD            = 9
EDIT_PUBLIC_NOTE    = 10
VIEW_OFFICER_NOTE   = 11
EDIT_OFFICER_NOTE   = 12
MODIFY_GUILD_INFO   = 13
```

Indices 3 and 4 are confirmed. All others match the order of permissions shown in WoW's Guild Control UI. All are defined as named constants so an off-by-one is a one-line fix.

- `GH._rankFlags` — table keyed by rankIndex, value is the raw flags array from `GuildControlGetRankFlags`.

- `GH.Permissions:Initialize()` — registers for `GUILD_ROSTER_UPDATE` and `PLAYER_GUILD_UPDATE`, calls `LoadRankPermissions()` immediately.

- `GH.Permissions:LoadRankPermissions()` — walks every rank via `GuildControlGetNumRanks` / `GuildControlGetRankFlags`, stores results in `GH._rankFlags`. Guards against API unavailability. No-ops if NumRanks < 2 (guild data not loaded yet; will retry on next event).

- `GH:HasPermission(flag)` — reads player's current `rankIndex` from `GetGuildInfo("player")`, looks up `GH._rankFlags[rankIndex][flag]`, returns true/false. Returns false if data not yet loaded.

### `Core.lua` changes

Remove `DetectOfficerThreshold`, `_cachedOfficerThreshold`.

Redefine `GH:IsOfficer()` as a thin wrapper:

```lua
function GH:IsOfficer()
    return GH:HasPermission(GH.PERM.OFFICER_CHAT_SPEAK)
end
```

Add named wrappers (one-liners):

```lua
GH:CanEditPublicNote()   → HasPermission(GH.PERM.EDIT_PUBLIC_NOTE)
GH:CanPromote()          → HasPermission(GH.PERM.PROMOTE)
GH:CanDemote()           → HasPermission(GH.PERM.DEMOTE)
GH:CanInvite()           → HasPermission(GH.PERM.INVITE)
GH:CanRemoveMember()     → HasPermission(GH.PERM.REMOVE)
GH:CanViewOfficerNote()  → HasPermission(GH.PERM.VIEW_OFFICER_NOTE)
GH:CanEditOfficerNote()  → HasPermission(GH.PERM.EDIT_OFFICER_NOTE)
```

Add `GH.Permissions = GH.Permissions or {}` to the namespace block.
Add `self.Permissions:Initialize()` early in `GH:Initialize()`, before `self.UI:Initialize()`.

`GH:CanManageTeams()` and `GH:CanManageTeam()` remain unchanged — they use `IsOfficer()` which now delegates to `HasPermission`.

## UI Call-Site Changes

### `MembersTab.lua` — `ShowMemberContextMenu`

| Action | Check |
| --- | --- |
| Whisper, Invite to Group, Edit Personal Note | always shown |
| Set as Main, Add Alt, Ban/Unban | `GH:IsOfficer()` (addon-specific, no WoW equivalent) |
| **Edit Guild Note** (new item) | `GH:CanEditPublicNote()` |
| Promote | `GH:CanPromote()` |
| Demote | `GH:CanDemote()` |
| Kick from Guild | `GH:CanRemoveMember()` |

Macro Tool and Ban List toolbar buttons stay `GH:IsOfficer()`.

### `ProfilePanel.lua` — `ShowProfilePanel`

| Widget | Check |
| --- | --- |
| `setJoinDateBtn`, `saveNoteBtn` / `noteBox`, `setMainBtn`, `addAltBtn`, `removeAltBtn`, `setBdayBtn`, `banBtn`, `unbanBtn` | `GH:IsOfficer()` (addon-specific) |
| **`editGuildNoteBtn`** (new) | `GH:CanEditPublicNote()` |

`panel.editGuildNoteBtn` ("Edit Guild Note", full-width, 24px tall) is added to the Guild Note section, placed in `Reflow()` directly below `guildNoteFS`. Hidden when `GH:CanEditPublicNote()` is false.

## Guild Note Write-Back

### `UI:ShowGuildNoteDialog(member)`

New dialog in `ProfilePanel.lua`, following the `ShowPersonalNoteDialog` pattern:

- Frame: 380×145, `DIALOG` strata, centered
- Title: `"Guild note for |cffffd700[name]|r"`
- Subtitle: `"Visible to all guild members"` (dimmed)
- Single-line EditBox, pre-filled with `member.note`
- Character counter: `x/31` (WoW server limit is 31 chars), counter turns red if exceeded
- Save / Cancel buttons; Enter key triggers Save
- On Save:
  1. Call `GuildRosterSetPublicNote(member.rosterIndex, note)`
  2. Call `RequestRosterUpdate()` (existing helper in GuildData.lua) to trigger `GUILD_ROSTER_UPDATE`
  3. Hide dialog

`member.rosterIndex` is already captured in `GD:Refresh()` for every roster member.

### After-save data flow

`GUILD_ROSTER_UPDATE` → `GD:Refresh()` → `member.note` updated → `UI:OnRosterRefresh()` → `UI:RefreshMembersTab()` refreshes the Note column.

`OnRosterRefresh` does not re-render the profile panel, so the dialog's Save handler must explicitly call `UI:ShowProfilePanel(member)` if `UI.ProfilePanel` is shown and `panel.currentName == member.fullName`.

## TOC Change

Add `Permissions.lua` to `GuildHub.toc` before `Main.lua`.

## Out of Scope

- Officer note display/editing (a separate feature; `CanViewOfficerNote` / `CanEditOfficerNote` wrappers are added but no UI is built in this pass).
- Any guild bank permission flags.
- Persisting the rank-flags cache across sessions (WoW always provides fresh data on login).
