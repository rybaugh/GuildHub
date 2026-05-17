# Design: Event Create Dialog — Dropdown Selectors

**Date:** 2026-05-17  
**Status:** Approved

## Problem

The Schedule New Event dialog uses click-through cycle buttons for Type, Repeat, and Host Team. Users must click repeatedly to reach the option they want, with no visibility of all available choices. Dropdowns are a more discoverable and efficient pattern.

## Approach

Add a reusable `S:Dropdown()` factory to `UI/Styles.lua`, consistent with existing factories (`S:Button`, `S:EditBox`, etc.). Replace the three cycler buttons in `UI/EventsTab.lua` with dropdown instances.

## Component: `S:Dropdown(parent, options, w, h)`

### Signature

```lua
-- options: array of { label = string, value = any }
-- Returns a frame with the interface below.
local dd = S:Dropdown(parent, options, w, h)
```

### Returned frame interface

| Member | Type | Description |
|---|---|---|
| `dd.GetValue()` | function | Returns `options[idx].value` for the selected item |
| `dd.GetIndex()` | function | Returns the current 1-based index |
| `dd.GetLabel()` | function | Returns `options[idx].label` |
| `dd.SetOptions(newOpts)` | function | Replaces the option list; resets to index 1 |
| `dd.Reset()` | function | Resets selection to index 1 |
| `dd.bg` | texture | Background texture (same convention as `S:Button`) |
| `dd.label` | FontString | Displays the current selection label |

### Visual structure

```
┌─────────────────────────────┐
│  Current selection label  ▾ │  ← button face (same dark-blue accent as S:Button)
└─────────────────────────────┘

  (on click, popup appears below)

┌─────────────────────────────┐
│  Option A                   │  ← hover: accent highlight row
│  Option B                   │
│  Option C                   │
└─────────────────────────────┘
```

### Behavior

- **Toggle:** Clicking the button opens the popup if closed, closes it if already open.
- **Popup parent:** `UIParent`, strata `DIALOG` + level 10 — renders above the dialog frame.
- **Popup position:** Anchored `TOPLEFT` of popup → `BOTTOMLEFT` of button, with a 2 px gap.
- **Popup width:** Matches the button width exactly.
- **Row height:** 22 px per row, matching existing list row density.
- **Selection:** Clicking a row sets that index, updates `dd.label`, fires `dd.onChange(idx, value)` if set, and closes the popup.
- **Close-outside:** A full-screen invisible intercept frame (`DIALOG` strata, level 9) is shown behind the popup. Any click on it closes the popup without changing selection.
- **Chevron:** A `▾` character appended to the label area (right-aligned separate FontString) to visually distinguish it from a plain button.
- **Styling:** Button face uses `S.COLOR.ACCENT` bg at 0.82 alpha (identical to `S:Button`). Popup bg uses `S.COLOR.INPUT_BG`. Row hover uses `S.COLOR.NAV_ACTIVE` at 0.6 alpha. Border via `S.COLOR.BORDER`.

### `onChange` callback

```lua
dd.onChange = function(idx, value) ... end
```

Fired after selection changes. Optional — nil by default.

---

## Changes: `UI/EventsTab.lua` — `ShowEventCreateDialog`

### Type selector

Replace:
```lua
dlg.typeIdx = 1
local typeBtn = S:Button(dlg, GH.Events.EVENT_TYPES[1], 174, 26)
typeBtn:SetScript("OnClick", function()
    dlg.typeIdx = (dlg.typeIdx % #GH.Events.EVENT_TYPES) + 1
    typeBtn.label:SetText(GH.Events.EVENT_TYPES[dlg.typeIdx])
end)
```

With:
```lua
local typeOpts = {}
for _, t in ipairs(GH.Events.EVENT_TYPES) do
    typeOpts[#typeOpts + 1] = { label = t, value = t }
end
local typeDd = S:Dropdown(dlg, typeOpts, 174, 26)
typeDd:SetPoint("TOPLEFT", typeLbl, "BOTTOMLEFT", 0, -4)
```

`Create` handler reads `GH.Events.EVENT_TYPES[typeDd.GetIndex()]` (or `typeDd.GetValue()`).  
`ResetPickers` calls `typeDd.Reset()`.

### Repeat selector

Replace the `repeatBtn` cycler with:
```lua
local repeatDd = S:Dropdown(dlg, REPEAT_OPTS, 110, 26)
repeatDd:SetPoint("LEFT", repeatLabel, "RIGHT", 4, 0)
```

`Create` handler reads `REPEAT_OPTS[repeatDd.GetIndex()].value` (or `repeatDd.GetValue()`).  
`ResetPickers` calls `repeatDd.Reset()`.

### Host Team selector

Replace the `teamBtn` cycler with:
```lua
local teamDd = S:Dropdown(dlg, teamOpts, 174, 26)
teamDd:SetPoint("TOPLEFT", hostLbl, "BOTTOMLEFT", 0, -4)
```

`ResetPickers` calls:
```lua
teamOpts = BuildTeamOpts()
teamDd.SetOptions(teamOpts)
```

`Create` handler reads `teamDd.GetValue()` for `hostTeamId` (already `nil` for "All Guild").

---

## Files changed

| File | Change |
|---|---|
| `UI/Styles.lua` | Add `S:Dropdown()` factory (~80 lines) |
| `UI/EventsTab.lua` | Replace 3 cycler buttons with `S:Dropdown()` calls; update `Create` handler and `ResetPickers` |

## Out of scope

- Dropdowns elsewhere in the addon (other tabs are not affected).
- Keyboard navigation within the dropdown.
- Scrolling within the popup (all lists are short: ≤6 types, ≤4 repeat options, teams are guild-bounded).
