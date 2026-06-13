# Guild Member Count Display

**Date:** 2026-06-12  
**Status:** Approved

## Goal

Show online and total guild member counts in the Members tab toolbar so officers can monitor proximity to WoW's 1,000-member guild cap at a glance.

## Scope

Single file: `UI/MembersTab.lua`. No new APIs, no new modules.

## Design

### Label placement

A `FontString` anchored to the `RIGHT` of the existing toolbar frame in `UI:CreateMembersTab()`, stored as `frame.countLabel`. The existing buttons are left-anchored and are unaffected.

### Data sources

- **Total count**: `GetNumGuildMembers()` — WoW global, returns the live roster size unaffected by any search filter.
- **Online count**: iterate `GH.GuildData.members` (the full unfiltered cache populated by `GD:Refresh()`) and count entries where `m.online == true`.

### Label format

```
32 online · 247 / 1000
```

The online portion is colored with `S.COLOR.ACCENT` (blue-white). The total portion color shifts based on roster size:

| Total | Color |
|-------|-------|
| < 900 | `S.COLOR.TEXT_DIM` |
| 900–949 | Yellow `(1, 0.85, 0.1)` |
| ≥ 950 | `S.COLOR.RED` |

### Update cadence

`RefreshMembersTab()` already fires on every roster change event and after every user interaction. The count label is updated at the end of that function — no separate timer or event needed.

## Files Changed

| File | Change |
|------|--------|
| `UI/MembersTab.lua` | Add `frame.countLabel` FontString in `CreateMembersTab`; update it in `RefreshMembersTab` |

## Out of Scope

- Showing filtered count ("showing X of Y") — not requested.
- Persisting or alerting via chat — not requested.
