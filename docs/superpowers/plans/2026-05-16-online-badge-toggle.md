# Online Badge Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the "Online: X / Y" sidebar badge clickable so it toggles `showOfflineMembers` and immediately refreshes the roster.

**Architecture:** Replace the bare `FontString` at `UI/MainWindow.lua:622–626` with an invisible `Button` that hosts the `FontString` as a child. `win.onlineBadge` continues to point to the `FontString`, so all `SetText(...)` call sites are untouched.

**Tech Stack:** Lua, WoW FrameXML API (`CreateFrame`, `SetScript`, `SetCursor`), GuildHub `GH.DB` / `UI` modules.

---

### Task 1: Replace FontString with clickable Button

**Files:**
- Modify: `Interface/Addons/GuildHub/UI/MainWindow.lua:622–626`

- [ ] **Step 1: Replace lines 622–626**

Replace this block:

```lua
    -- Online count badge at sidebar bottom
    local onlineBadge = S:FS(sidebar, "OVERLAY")
    onlineBadge:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 12, 10)
    onlineBadge:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    win.onlineBadge = onlineBadge
```

With this block:

```lua
    -- Online count badge at sidebar bottom (Button wrapper makes it clickable)
    local onlineBadgeBtn = CreateFrame("Button", nil, sidebar)
    onlineBadgeBtn:SetSize(120, 16)
    onlineBadgeBtn:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 12, 10)
    local onlineBadge = S:FS(onlineBadgeBtn, "OVERLAY")
    onlineBadge:SetAllPoints()
    onlineBadge:SetJustifyH("LEFT")
    onlineBadge:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    onlineBadgeBtn:SetScript("OnClick", function()
        local cur = GH.DB:GetSetting("showOfflineMembers")
        if cur == nil then cur = true end
        GH.DB:SetSetting("showOfflineMembers", not cur)
        UI:RefreshMembersTab()
    end)
    onlineBadgeBtn:SetScript("OnEnter", function() SetCursor("Interface/Cursor/Point") end)
    onlineBadgeBtn:SetScript("OnLeave", function() SetCursor(nil) end)
    win.onlineBadge = onlineBadge
```

- [ ] **Step 2: Verify no other files need changes**

Confirm `win.onlineBadge:SetText(...)` at line 691 is untouched and still works — the variable still points to the `FontString`, nothing else changed.

- [ ] **Step 3: Test in-game**

  1. `/reload` in WoW.
  2. Open GuildHub. Confirm "Online: X / Y" text looks identical to before.
  3. Hover over the badge — cursor should change to a pointer hand.
  4. Click the badge — offline members should disappear from the Members roster.
  5. Click again — offline members should reappear.
  6. Open Settings and confirm the "Show Offline Members" toggle reflects the new state.
  7. Toggle it in Settings, then click the badge again — both controls should stay in sync.

- [ ] **Step 4: Commit**

```bash
git add Interface/Addons/GuildHub/UI/MainWindow.lua
git commit -m "feat: make online badge clickable to toggle offline members"
```
