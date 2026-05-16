# Design: Duplicate Team Prevention

Date: 2026-05-16

## Problem

Teams use randomly-generated UUIDs as IDs. Two officers who are offline from each other can
independently create a team with the same name and both survive the sync — resulting in duplicate
tabs (e.g., two "MT6" tabs) with no collision detection or resolution path.

This happens at two points:
1. An officer creates a team whose name already exists in their local DB (simple case).
2. An officer creates a team while no one with the original team in their DB is online; when those
   players come back online their `TM_OFC` broadcasts cause a name collision (the hard case).

---

## Architecture Overview

Two independent enforcement points:

```
Creation-time guard (UI layer)
  └── ShowTeamNameDialog → name-collision check → inline error, dialog stays open

Sync-time dedup (protocol layer)
  └── TM_OFC receipt → name-collision check → pending flag in DB → TMDPC broadcast
        └── GM online  → real-time conflict dialog (queued)
        └── GM offline → pending persists in DB → dialog fires on next GM login
              └── GM resolves → TMGMR broadcast → all officers execute
```

Non-duplicate sync paths are unaffected. The `pending` field is additive to the group DB record.
`TMDPC` and `TMGMR` are handled alongside existing `TM_*` routing in `GroupManager.lua`. The GM
conflict dialog is a self-contained new function in `TeamsTab.lua`.

---

## Section 1 — DB Changes

`Groups:Create()` stores `createdAt = time()` on the group record at creation time.

Group records gain two optional fields:
- `createdAt` (integer) — Unix timestamp of creation. Used to determine canonical vs pending when
  a collision is detected. A record without this field is treated as `createdAt = 0` (canonical
  by default — unknown age loses to known-age newer duplicates safely).
- `pending` (boolean) — `true` when this team is a known duplicate awaiting GM resolution.
  Persists across reloads. Carried in `TM_OFC` so other officers learn the pending state.

---

## Section 2 — Creation-Time Guard

In `UI:ShowTeamNameDialog`, when the officer confirms the name (OK button or Enter):

1. Trim whitespace from the typed name; compare case-insensitively against all teams in
   `GH.Groups:GetAll()`.
2. If any team's name matches: display an inline error label below the edit box —
   *"A team named 'MT6' already exists."* — and do not invoke the callback. The dialog stays open
   so the officer can type a different name.
3. If no match: proceed as today (`GH.Groups:Create(name)`).

No network messages involved. Guards against collisions visible in the officer's local DB only.
The offline-duplicate case is handled by the sync-time path below.

---

## Section 3 — Sync-Time Conflict Detection

### Canonical vs pending determination

When two teams share a name, the one with the earlier `createdAt` is canonical; the one with the
later `createdAt` is pending. Both officers independently compute the same result once they see
both timestamps, so no coordination message is needed to agree on the assignment.

Edge: if `createdAt` values are equal (clock skew or both zero), fall back to lexicographic
comparison of group IDs — `min(id1, id2)` is canonical.

### Detection flow

Collision detection runs inside the existing `TM_OFC` handler, immediately after saving the
incoming group record. It scans the local DB for any team with the same name but a different ID:

```
incoming: def456, name="MT6", createdAt=2000
local:    abc123, name="MT6", createdAt=1000
→ 1000 < 2000  →  abc123 is canonical, def456 is pending
```

On collision detected:
- Save/update the pending team with `pending = true` in the local DB.
- If `GH:IsGM()`: enqueue `{pendingId, canonicalId}` in `UI._conflictQueue` and show the
  conflict dialog if none is currently displayed.
- Otherwise: broadcast `TMDPC \30 pendingId \30 canonicalId` so the GM sees it in real-time if
  online.

### Offline GM path

The `pending = true` flag persists in the DB and is carried in subsequent `TM_OFC` broadcasts
(via the new `pending` field). When the GM logs in and their `TMCHK` triggers officer responses,
any officer holding a pending team includes it in their `TM_OFC` reply. The GM receives it, sees
`pending = true`, and enqueues the conflict — no live `TMDPC` required.

---

## Section 4 — Message Protocol

### Updated: `TM_OFC`

Two optional trailing fields appended to the existing format:

```
TMOFC \30 groupId \30 teamName \30 membersCSV \30 channelId \30 creatorRank \30 creator
      \30 createdAt \30 pending
```

- `createdAt`: integer Unix timestamp string ("0" if unknown).
- `pending`: `"1"` if this team is a known duplicate awaiting GM resolution; omitted or `"0"`
  otherwise.

Existing clients that don't read these fields ignore them — fully backward compatible. An incoming
`TM_OFC` without `createdAt` defaults to `0` (canonical fallback).

### New: `TMDPC` — Duplicate conflict notification

```
TMDPC \30 pendingId \30 canonicalId
```

- Sent by any officer who detects a name collision (non-GM officers only; GM handles it locally).
- GM client picks it up and enqueues the conflict dialog.
- GM deduplicates before enqueuing: skip if `{pendingId, canonicalId}` is already queued or
  currently displayed.

### New: `TMGMR` — GM resolution broadcast

```
TMGMR \30 action \30 pendingId \30 canonicalId \30 [newName]
```

- `action`: one of `"merge"`, `"keep"`, `"delete"`, `"rename"`.
- `newName`: only present when `action = "rename"`.
- Broadcast by the GM after selecting a resolution. GM executes the same logic immediately
  (skips own echo in the handler).

Both new types are well under the 250-character addon message limit.

---

## Section 5 — GM Conflict Dialog

New function `UI:ShowTeamConflictDialog(pendingId, canonicalId)` in `TeamsTab.lua`.

### Layout

Fixed ~380×260 frame, `DIALOG` strata, anchored to the main window's right edge (matches existing
dialog positioning). Follows the same visual pattern as `ShowTeamMembersDialog`:

- Gold accent bar at top.
- Title: *"Duplicate Team Detected"* in gold.
- Body: *"Two teams share the name 'MT6'. Please choose how to resolve this."*
- Two side-by-side info panels:
  - Left: canonical team — name, member count, online count, labeled *"(older)"*.
  - Right: pending team — same fields, labeled *"(newer)"*.
- Four buttons across the bottom: **Merge Members** | **Keep Both** | **Delete Newer** |
  **Rename Newer**.
- **Rename Newer** reveals an inline edit box (same style as `ShowTeamNameDialog`) with a
  **Confirm** button. The edit box runs the same name-collision check; if the typed name already
  exists, shows the inline error and stays open.

### Queue management

```lua
UI._conflictQueue = {}   -- {pendingId, canonicalId} pairs
```

`UI:ShowTeamConflictDialog` pops and displays one entry at a time. Closing or resolving a dialog
automatically shows the next queued entry.

### Trigger points

1. `TMDPC` received and `GH:IsGM()` → enqueue (dedup check first) → show if nothing displayed.
2. `TM_OFC` received with `pending = "1"` and `GH:IsGM()` → same enqueue path.
3. `TeamsTab:OnShow` (and addon load after init delay) → scan DB for `pending = true` teams,
   enqueue any found, show if GM.

### `GH:IsGM()` helper

New thin helper in `Core.lua`:

```lua
function GH:IsGM()
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex == 1
end
```

GM is always rank index 1 in WoW (rank 0 in some API contexts — verify against the existing
`officerRankThreshold` pattern in the codebase).

---

## Section 6 — Resolution Execution

The GM's dialog broadcasts `TMGMR` and the GM executes locally immediately (no echo wait).
All other online officers execute on `TMGMR` receipt.

| Action | What every officer does |
|--------|------------------------|
| **merge** | Copy members from `pendingId` not already in `canonicalId` into `canonicalId`. Send `TM_REM` to members who were *only* on the pending team (they receive re-sync via updated `TM_SYN`). Delete `pendingId` locally. Refresh UI. |
| **keep** | Remove `pending = true` from `pendingId`. Refresh UI — both teams now display normally. |
| **delete** | Send `TM_REM` to each member of `pendingId`. Delete `pendingId` locally. Refresh UI. |
| **rename** | Set `pendingId.name = newName`, remove `pending = true`. Broadcast `TM_OFC` for `pendingId` with the new name so non-officer members learn the rename. Refresh UI. |

**Members-only clients** learn outcomes through existing messages: `TM_REM` for delete/merge
removal, updated `TM_OFC` for rename/keep. No new handling needed on their side.

**Offline officers** at resolution time receive the correct state on next login via `TMCHK` —
the pending team will either be absent or have `pending = false` by then.

---

## Section 7 — Edge Cases

| Scenario | Handling |
|----------|----------|
| Multiple simultaneous conflicts | `UI._conflictQueue` serializes them; GM resolves one at a time, next dialog opens automatically. |
| Two officers both detect the same conflict and both send `TMDPC` | GM deduplicates before enqueuing: skip if `{pendingId, canonicalId}` pair already queued or displayed. |
| GM never online | Pending teams persist indefinitely. Out of scope: a future "senior officer override" path could be added. |
| Pending team's creator goes offline before resolution | `pending = true` persists in DB; state is correct when they return. |
| Three-way collision (three officers each create "MT6" offline) | Each pair is its own `TMDPC` entry. GM resolves sequentially. After each merge/delete the remaining pending entries are re-evaluated naturally. |
| Officer with empty local DB creates duplicate, original owner comes online first | When the original owner's `TM_OFC` arrives, `createdAt` comparison correctly marks the locally-created (newer) team as pending. |
| Rename chosen but new name also collides | The rename edit box runs the same creation-time name check — inline error shown, dialog stays open. |
| `createdAt` clock skew / both zero | Fall back to `min(id1, id2)` lexicographic comparison — deterministic, both parties agree. |

---

## Files Changed

| File | Change |
|------|--------|
| `GroupManager.lua` | `Groups:Create()` stores `createdAt`. `TM_OFC` sends/reads two new trailing fields. New handlers for `TMDPC` and `TMGMR`. Collision detection logic in the `TM_OFC` handler. `Groups:_OfficerSync()` carries `createdAt` and `pending`. |
| `UI/TeamsTab.lua` | `UI:ShowTeamConflictDialog()`. `UI._conflictQueue`. `TeamsTab:OnShow` scans for pending teams. Tab strip renders pending teams with `"(pending)"` suffix and dimmed/italic style. `ShowTeamNameDialog` gains inline error label and name-collision check on confirm. |
| `Core.lua` | `GH:IsGM()` helper. |
