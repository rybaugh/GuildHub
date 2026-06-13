# Full-Name Keying for Team Rosters

**Date:** 2026-06-13
**Status:** Approved

## Problem

`g.members` stores short character names (e.g. `"Scrams"`). The TM_INV routing compares
`parts[5] == UnitName("player")` — also a short name. On connected realms two guild members
can share the same short name but have different `fullName` values (`"Scrams-Silvermoon"` vs
`"Scrams-OtherRealm"`), causing both to receive and accept the same invite, or appearing
interchangeably everywhere the roster is read by short name.

## Solution

Use `memberInfo.fullName` (the "Name-Realm" string from `GetGuildRosterInfo`, which for
home-realm players is just `"Name"` with no suffix) as the canonical team roster key everywhere.

## Changes

### `Core.lua` — new helper

Add `GH:GetFullPlayerName()` that looks up the current player in `GuildData` to get their
canonical `fullName`. Falls back to `UnitName("player")` if the roster isn't loaded yet.

### `GroupManager.lua`

- `SendInvite`: store `memberInfo.fullName` (not `.name`) as `canonical`
- TM_INV receive: compare `parts[5] == GH:GetFullPlayerName()`
- TM_ACC / TM_DEC / TM_CHK sends: `GetPlayerName()` → `GetFullPlayerName()`
- TM_ACC receive: `accepter` is a full name; duplicate check unchanged
- TM_REM receive: compare `parts[3] == GH:GetFullPlayerName()`
- Login sync "isMember" check: use `GetFullPlayerName()`
- Add `Groups:NormalizeMemberNames()`: one pass over all `g.members`, upgrades any entry
  without a `"-"` via guild roster lookup. Called from the existing 20-second login-sync timer.

### `GuildData.lua`

`GetMemberTeams` / `GetMemberTeam` callers updated to pass `m.fullName` so the string matches
what is now stored in `g.members`.

### `UI/MembersTab.lua`

Pass `m.fullName` when calling `GH.GuildData:GetMemberTeam()`.

### `UI/TeamsTab.lua`

- Display `name:match("^([^%-]+)") or name` in roster rows so cross-realm members show as
  `"Scrams"` not `"Scrams-OtherRealm"`.
- Role badge lookup key updated to match the full-name stored in `g.memberRoles`.

## Migration

`NormalizeMemberNames()` runs in the existing 20-second login timer (after the guild roster is
populated). For each group, for each entry without a `"-"`, looks up the guild roster and
replaces with `fullName`, then saves. Players not in the guild at that moment stay as short
names and are removed naturally on the next officer action.

## Protocol Note

The wire format is unversioned. During the transition window an old client may send TM_INV with
a short name; a fully-updated client won't route it. This is brief and self-healing once all
clients `/reload`.
