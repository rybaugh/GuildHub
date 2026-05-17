# Event Create Dialog — Dropdown Selectors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three click-through cycle buttons (Type, Repeat, Host Team) in the Schedule New Event dialog with reusable dropdown selectors.

**Architecture:** Add `S:Dropdown()` factory to `UI/Styles.lua` following the existing component pattern (`S:Button`, `S:EditBox`). The factory returns a button-like frame that opens a floating popup list on click, with a full-screen intercept frame to close-on-outside-click. Then replace the three cycler buttons in `ShowEventCreateDialog` with `S:Dropdown()` calls and update the Create handler and `ResetPickers` accordingly.

**Tech Stack:** Lua, WoW Retail addon API (CreateFrame, UIParent, DIALOG strata). No external libraries. No test framework — verification is in-game via `/reload` and manual interaction.

---

## File Map

| File | Change |
|---|---|
| `UI/Styles.lua` | Add `S:Dropdown()` factory after `S:EditBox` (~90 lines) |
| `UI/EventsTab.lua` | Replace 3 cycler buttons; update `BuildTeamOpts`, Create handler, `ResetPickers`, and stored `dlg.*` refs |

---

### Task 1: Add `S:Dropdown()` to Styles.lua

**Files:**
- Modify: `UI/Styles.lua` — insert after the `S:EditBox` function (after line 265)

- [ ] **Step 1: Insert the Dropdown factory into Styles.lua**

Add this block immediately after the closing `end` of `S:EditBox` (after line 265 in `UI/Styles.lua`):

```lua
-- ── Dropdown selector ─────────────────────────────────────────────────────
-- options: array of { label = string, value = any }
-- Returns a button-like frame. Interface:
--   .GetIndex()          → current 1-based index
--   .GetValue()          → options[idx].value
--   .GetLabel()          → options[idx].label
--   .SetOptions(newOpts) → replace list, reset to index 1
--   .Reset()             → reset to index 1
--   .onChange            → optional function(idx, value) fired on selection
function S:Dropdown(parent, options, w, h)
    w = w or 174
    h = h or 26

    local current = 1
    local opts    = options

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.82)
    btn.bg = bg

    local shimmer = btn:CreateTexture(nil, "ARTWORK")
    shimmer:SetPoint("TOPLEFT")
    shimmer:SetPoint("TOPRIGHT")
    shimmer:SetHeight(math.max(1, math.floor(h * 0.35)))
    local sok = pcall(function()
        shimmer:SetGradient("VERTICAL",
            CreateColor(1, 1, 1, 0.08), CreateColor(1, 1, 1, 0))
    end)
    if not sok then shimmer:SetColorTexture(1, 1, 1, 0.05) end

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(S.FontSmall)
    label:SetPoint("LEFT",  btn, "LEFT",   8,   0)
    label:SetPoint("RIGHT", btn, "RIGHT", -20,  0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(1, 1, 1, 1)
    btn.label = label

    local chevron = btn:CreateFontString(nil, "OVERLAY")
    chevron:SetFontObject(S.FontSmall)
    chevron:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    chevron:SetText("\226\150\190")  -- ▾ (UTF-8 bytes: E2 96 BE)
    chevron:SetTextColor(1, 1, 1, 0.65)

    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.52, 0.66, 1.00, 0.95)
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.82)
    end)

    -- Popup (UIParent-parented so it floats above the dialog)
    local popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(10)
    popup:SetClampedToScreen(true)
    popup:Hide()

    -- Border layer (drawn first so bg sits inside it)
    local popupBorder = popup:CreateTexture(nil, "BORDER")
    popupBorder:SetAllPoints()
    popupBorder:SetColorTexture(
        S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.7)

    local popupBg = popup:CreateTexture(nil, "BACKGROUND")
    popupBg:SetPoint("TOPLEFT",     1, -1)
    popupBg:SetPoint("BOTTOMRIGHT", -1,  1)
    popupBg:SetColorTexture(
        S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)

    -- Intercept: full-screen invisible frame at DIALOG-9, closes popup on outside click
    local intercept = CreateFrame("Frame", nil, UIParent)
    intercept:SetAllPoints(UIParent)
    intercept:SetFrameStrata("DIALOG")
    intercept:SetFrameLevel(9)
    intercept:EnableMouse(true)
    intercept:Hide()
    intercept:SetScript("OnMouseDown", function()
        popup:Hide()
        intercept:Hide()
    end)

    local ROW_H = 22
    local rows  = {}

    local function Refresh()
        label:SetText(opts[current] and opts[current].label or "")
    end

    local function RebuildRows()
        for _, r in ipairs(rows) do r:Hide() end
        rows = {}
        popup:SetSize(w, ROW_H * #opts)
        for i, opt in ipairs(opts) do
            local row = CreateFrame("Button", nil, popup)
            row:SetPoint("TOPLEFT",  popup, "TOPLEFT",  0, -(i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, -(i - 1) * ROW_H)
            row:SetHeight(ROW_H)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(0, 0, 0, 0)

            local rowLabel = row:CreateFontString(nil, "OVERLAY")
            rowLabel:SetFontObject(S.FontSmall)
            rowLabel:SetPoint("LEFT",  row, "LEFT",   8, 0)
            rowLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            rowLabel:SetJustifyH("LEFT")
            rowLabel:SetText(opt.label)
            rowLabel:SetTextColor(1, 1, 1, 1)

            row:SetScript("OnEnter", function()
                rowBg:SetColorTexture(
                    S.COLOR.NAV_ACTIVE[1], S.COLOR.NAV_ACTIVE[2], S.COLOR.NAV_ACTIVE[3], 0.6)
            end)
            row:SetScript("OnLeave", function()
                rowBg:SetColorTexture(0, 0, 0, 0)
            end)

            local capturedIdx = i
            row:SetScript("OnClick", function()
                current = capturedIdx
                Refresh()
                popup:Hide()
                intercept:Hide()
                if btn.onChange then btn.onChange(current, opts[current].value) end
            end)

            rows[i] = row
        end
    end

    RebuildRows()
    Refresh()

    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
            intercept:Hide()
        else
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            popup:Show()
            intercept:Show()
        end
    end)

    btn.GetIndex   = function() return current end
    btn.GetValue   = function() return opts[current] and opts[current].value end
    btn.GetLabel   = function() return opts[current] and opts[current].label or "" end
    btn.SetOptions = function(newOpts)
        opts    = newOpts
        current = 1
        RebuildRows()
        Refresh()
    end
    btn.Reset = function()
        current = 1
        Refresh()
    end

    return btn
end
```

- [ ] **Step 2: Reload and confirm no Lua errors**

In-game: `/reload`  
Expected: no error frame, addon loads normally.

- [ ] **Step 3: Commit**

```bash
git add "UI/Styles.lua"
git commit -m "feat: add S:Dropdown() factory to design system"
```

---

### Task 2: Replace Type and Repeat cyclers in EventsTab.lua

**Files:**
- Modify: `UI/EventsTab.lua` — inside `ShowEventCreateDialog`, lines ~662–689

- [ ] **Step 1: Replace the Type cycler**

Find this block (around line 662):
```lua
    -- Type
    local typeLbl = Label("Type:", monthPicker, -8)
    dlg.typeIdx   = 1
    local typeBtn = S:Button(dlg, GH.Events.EVENT_TYPES[1], 174, 26)
    typeBtn:SetPoint("TOPLEFT", typeLbl, "BOTTOMLEFT", 0, -4)
    typeBtn:SetScript("OnClick", function()
        dlg.typeIdx = (dlg.typeIdx % #GH.Events.EVENT_TYPES) + 1
        typeBtn.label:SetText(GH.Events.EVENT_TYPES[dlg.typeIdx])
    end)
```

Replace it with:
```lua
    -- Type
    local typeLbl  = Label("Type:", monthPicker, -8)
    local typeOpts = {}
    for _, t in ipairs(GH.Events.EVENT_TYPES) do
        typeOpts[#typeOpts + 1] = { label = t, value = t }
    end
    local typeDd = S:Dropdown(dlg, typeOpts, 174, 26)
    typeDd:SetPoint("TOPLEFT", typeLbl, "BOTTOMLEFT", 0, -4)
```

- [ ] **Step 2: Replace the Repeat cycler**

Find this block (around line 673):
```lua
    -- Repeat
    local REPEAT_OPTS = {
        { label = "No Repeat", value = nil        },
        { label = "Weekly",    value = "weekly"   },
        { label = "Bi-Weekly", value = "biweekly" },
        { label = "Monthly",   value = "monthly"  },
    }
    local repeatLabel = S:FS(dlg, "OVERLAY")
    repeatLabel:SetPoint("LEFT", typeBtn, "RIGHT", 10, 0)
    repeatLabel:SetText("Repeat:")
    repeatLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    dlg.repeatIdx = 1
    local repeatBtn = S:Button(dlg, REPEAT_OPTS[1].label, 110, 26)
    repeatBtn:SetPoint("LEFT", repeatLabel, "RIGHT", 4, 0)
    repeatBtn:SetScript("OnClick", function()
        dlg.repeatIdx = (dlg.repeatIdx % #REPEAT_OPTS) + 1
        repeatBtn.label:SetText(REPEAT_OPTS[dlg.repeatIdx].label)
    end)
```

Replace it with:
```lua
    -- Repeat
    local REPEAT_OPTS = {
        { label = "No Repeat", value = nil        },
        { label = "Weekly",    value = "weekly"   },
        { label = "Bi-Weekly", value = "biweekly" },
        { label = "Monthly",   value = "monthly"  },
    }
    local repeatLabel = S:FS(dlg, "OVERLAY")
    repeatLabel:SetPoint("LEFT", typeDd, "RIGHT", 10, 0)
    repeatLabel:SetText("Repeat:")
    repeatLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    local repeatDd = S:Dropdown(dlg, REPEAT_OPTS, 110, 26)
    repeatDd:SetPoint("LEFT", repeatLabel, "RIGHT", 4, 0)
```

- [ ] **Step 3: Reload and verify**

In-game: `/reload`, open the Events tab, click **+ Schedule Event**.  
Expected:
- Type row shows a dropdown button labeled "Raid" with a `▾` chevron
- Clicking it opens a popup with: Raid, Dungeon, PvP, Social, Competition, Other
- Selecting an option updates the button label and closes the popup
- Repeat row shows a dropdown labeled "No Repeat" with the same behavior
- Clicking outside the popup closes it without changing the selection

- [ ] **Step 4: Commit**

```bash
git add "UI/EventsTab.lua"
git commit -m "feat: replace Type and Repeat cyclers with dropdowns"
```

---

### Task 3: Replace Host Team cycler and update BuildTeamOpts

**Files:**
- Modify: `UI/EventsTab.lua` — `BuildTeamOpts`, Host Team block (~line 692–713), Create handler (~line 750–768), `ResetPickers` (~line 776–798), and stored `dlg.*` refs (~line 800–805)

- [ ] **Step 1: Update BuildTeamOpts to use `value` instead of `id`**

Find:
```lua
    local function BuildTeamOpts()
        local opts = { { label = "All Guild", id = nil } }
        for _, t in ipairs(GH.Groups:GetAll()) do
            opts[#opts + 1] = { label = t.name, id = t.id }
        end
        return opts
    end
```

Replace with:
```lua
    local function BuildTeamOpts()
        local opts = { { label = "All Guild", value = nil } }
        for _, t in ipairs(GH.Groups:GetAll()) do
            opts[#opts + 1] = { label = t.name, value = t.id }
        end
        return opts
    end
```

- [ ] **Step 2: Replace the Host Team cycler and fix teamOnlyLbl anchor**

Find:
```lua
    local hostLbl = S:FS(dlg, "OVERLAY")
    hostLbl:SetPoint("TOPLEFT", typeBtn, "BOTTOMLEFT", 0, -8)
    hostLbl:SetText("Host Team:")
    hostLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    dlg.teamIdx = 1
    local teamBtn = S:Button(dlg, teamOpts[1].label, 174, 26)
    teamBtn:SetPoint("TOPLEFT", hostLbl, "BOTTOMLEFT", 0, -4)
    teamBtn:SetScript("OnClick", function()
        dlg.teamIdx = (dlg.teamIdx % #teamOpts) + 1
        teamBtn.label:SetText(teamOpts[dlg.teamIdx].label)
    end)

    -- "Team Only" ON/OFF toggle (shown inline to the right of the team button)
    local teamOnlyLbl = S:FS(dlg, "OVERLAY")
    teamOnlyLbl:SetPoint("LEFT", teamBtn, "RIGHT", 10, 0)
```

Replace with:
```lua
    local hostLbl = S:FS(dlg, "OVERLAY")
    hostLbl:SetPoint("TOPLEFT", typeDd, "BOTTOMLEFT", 0, -8)
    hostLbl:SetText("Host Team:")
    hostLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    local teamDd = S:Dropdown(dlg, teamOpts, 174, 26)
    teamDd:SetPoint("TOPLEFT", hostLbl, "BOTTOMLEFT", 0, -4)

    -- "Team Only" ON/OFF toggle (shown inline to the right of the team dropdown)
    local teamOnlyLbl = S:FS(dlg, "OVERLAY")
    teamOnlyLbl:SetPoint("LEFT", teamDd, "RIGHT", 10, 0)
```

- [ ] **Step 3: Update the Create handler**

Find (inside the `okBtn:SetScript("OnClick", ...)` handler):
```lua
        local selTeam = teamOpts[dlg.teamIdx]
        GH.Events:Create(evTitle, evDesc, ts,
            GH.Events.EVENT_TYPES[dlg.typeIdx],
            REPEAT_OPTS[dlg.repeatIdx].value,
            selTeam.id,
            selTeam.id and dlg.teamOnly or false)
```

Replace with:
```lua
        GH.Events:Create(evTitle, evDesc, ts,
            typeDd.GetValue(),
            repeatDd.GetValue(),
            teamDd.GetValue(),
            teamDd.GetValue() and dlg.teamOnly or false)
```

- [ ] **Step 4: Update ResetPickers**

Find (inside `dlg.ResetPickers = function()`):
```lua
        dlg.repeatIdx = 1; repeatBtn.label:SetText(REPEAT_OPTS[1].label)
        dlg.typeIdx   = 1; typeBtn.label:SetText(GH.Events.EVENT_TYPES[1])
        -- Refresh team list in case teams were added/removed since last open
        teamOpts = BuildTeamOpts()
        dlg.teamIdx = 1; teamBtn.label:SetText(teamOpts[1].label)
        dlg.teamOnly = false
        tObg:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.5)
        tOlbl:SetText("OFF")
```

Replace with:
```lua
        typeDd.Reset()
        repeatDd.Reset()
        teamOpts = BuildTeamOpts()
        teamDd.SetOptions(teamOpts)
        dlg.teamOnly = false
        tObg:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.5)
        tOlbl:SetText("OFF")
```

- [ ] **Step 5: Update stored dialog references**

Find at the bottom of `ShowEventCreateDialog`:
```lua
    dlg.titleBox  = titleBox
    dlg.descBox   = descBox
    dlg.typeBtn   = typeBtn
    dlg.repeatBtn = repeatBtn
    dlg.teamBtn   = teamBtn
```

Replace with:
```lua
    dlg.titleBox  = titleBox
    dlg.descBox   = descBox
    dlg.typeDd    = typeDd
    dlg.repeatDd  = repeatDd
    dlg.teamDd    = teamDd
```

- [ ] **Step 6: Reload and verify full flow**

In-game: `/reload`, open Events tab, click **+ Schedule Event**.

Check each dropdown:
- **Type:** opens list (Raid, Dungeon, PvP, Social, Competition, Other), selection persists on button
- **Repeat:** opens list (No Repeat, Weekly, Bi-Weekly, Monthly), selection persists
- **Host Team:** opens list with "All Guild" + any existing teams, selection persists
- Click-outside closes any open popup without changing selection
- Fill in a title, pick non-default Type + Repeat + Host Team, click **Create** — verify the event appears in the list with the correct type color and repeat badge
- Re-open the dialog — all three dropdowns should reset to their defaults (Raid / No Repeat / All Guild)

- [ ] **Step 7: Commit**

```bash
git add "UI/EventsTab.lua"
git commit -m "feat: replace Host Team cycler with dropdown, wire all three to Create/ResetPickers"
```
