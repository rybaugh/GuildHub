# Online Badge Toggle — Design Spec

**Date:** 2026-05-16  
**Status:** Approved

## Summary

Clicking the "Online: X / Y" text at the bottom-left of the GuildHub sidebar toggles `showOfflineMembers` and immediately refreshes the Members roster. Visual appearance of the text does not change.

## Architecture

Single-file change: `UI/MainWindow.lua`.

Replace the bare FontString (`onlineBadge`) with an invisible Button that hosts the FontString as a child. All existing `win.onlineBadge:SetText(...)` call sites remain unchanged — `win.onlineBadge` still points to the FontString.

## Implementation Details

**Frame change (lines 622–626):**
- Create a `Button` parented to `sidebar`, anchored `BOTTOMLEFT` at `(12, 10)`, sized `(120, 16)`.
- Create the FontString as a child of that Button (same layer, same font, same color as today).
- `win.onlineBadge = <the FontString>` — no call-site changes needed.

**Click handler:**
```lua
btn:SetScript("OnClick", function()
    local cur = GH.DB:GetSetting("showOfflineMembers")
    if cur == nil then cur = true end
    GH.DB:SetSetting("showOfflineMembers", not cur)
    UI:RefreshMembersTab()
end)
```

**Hover cursor** (signals interactivity without changing text color):
```lua
btn:SetScript("OnEnter", function() SetCursor("Interface/Cursor/Point") end)
btn:SetScript("OnLeave", function() SetCursor(nil) end)
```

## Scope

- No changes to `MembersTab.lua`, `Database.lua`, or any other file.
- Settings page toggle for `showOfflineMembers` continues to work independently.
- `win.onlineBadge:SetText(...)` in `OnRosterRefresh` (line 691) requires no modification.

## Out of Scope

- Tooltip on hover.
- Visual indicator on the badge itself (color change, icon) reflecting current state.
