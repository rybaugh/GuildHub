# Activity Log Timestamp Fix + Font Size Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix spurious join/leave events flooding the Activity tab on every login, and add a live-updating font size spinner to the Settings page.

**Architecture:** Feature 1 simplifies ActivityLog initialization to seed the baseline snapshot immediately on the first non-empty roster build (instead of waiting for two consecutive same-size calls), then prunes existing bad events heuristically. Feature 2 introduces three shared `CreateFont()` objects in Styles.lua; all UI font strings reference them via `SetFontObject()`, so a single `ApplyFontSize()` call updates every font string live.

**Tech Stack:** WoW Lua addon (no unit test framework — all verification is done in-game via `/reload` and visual inspection of the Activity tab and Settings page)

---

## File Map

**Feature 1 — Activity Log Fix:**
- Modify: `Interface/Addons/GuildHub/ActivityLog.lua`
- Modify: `Interface/Addons/GuildHub/Database.lua` (add `SetActivityLog`)

**Feature 2 — Font Size:**
- Modify: `Interface/Addons/GuildHub/UI/Styles.lua` (font objects, helpers, update existing helpers)
- Modify: `Interface/Addons/GuildHub/Database.lua` (add `fontSize` default)
- Modify: `Interface/Addons/GuildHub/UI/MainWindow.lua` (startup call + settings row + CreateFontString refactor)
- Modify (CreateFontString refactor — direct calls not going through Styles helpers):
  - `Interface/Addons/GuildHub/UI/ActivityTab.lua`
  - `Interface/Addons/GuildHub/UI/BanListDialog.lua`
  - `Interface/Addons/GuildHub/UI/ChatTab.lua`
  - `Interface/Addons/GuildHub/UI/EventsTab.lua`
  - `Interface/Addons/GuildHub/UI/ExportDialog.lua`
  - `Interface/Addons/GuildHub/UI/GroupsTab.lua`
  - `Interface/Addons/GuildHub/UI/GuildRecruitTab.lua`
  - `Interface/Addons/GuildHub/UI/MacroDialog.lua`
  - `Interface/Addons/GuildHub/UI/MembersTab.lua`
  - `Interface/Addons/GuildHub/UI/MouseoverWindow.lua`
  - `Interface/Addons/GuildHub/UI/ProfilePanel.lua`
  - `Interface/Addons/GuildHub/UI/RecruitTab.lua`
  - `Interface/Addons/GuildHub/UI/TeamsTab.lua`

---

## Task 1: Fix ActivityLog initialization and add spurious-event pruning

**Files:**
- Modify: `Interface/Addons/GuildHub/ActivityLog.lua`
- Modify: `Interface/Addons/GuildHub/Database.lua`

- [ ] **Step 1.1 — Add `DB:SetActivityLog` to Database.lua**

  Find `DB:ClearActivityLog` and add the new method directly after it:

  ```lua
  function DB:SetActivityLog(newLog)
      local gd = self:_GuildData()
      if gd then gd.activityLog = newLog end
  end
  ```

- [ ] **Step 1.2 — Remove `_prevSnapshotSize` from ActivityLog.lua**

  At the top of `ActivityLog.lua`, find and remove `_prevSnapshotSize`:

  ```lua
  -- BEFORE (lines 11-13):
  local _prevSnapshot     = {}
  local _prevSnapshotSize = 0      -- member count of the last candidate snapshot
  local _initialised      = false

  -- AFTER:
  local _prevSnapshot = {}
  local _initialised  = false
  ```

- [ ] **Step 1.3 — Simplify the initialization block in `_OnRosterUpdate`**

  Inside `ActivityLog:_OnRosterUpdate()`, find the `if not _initialised then` block and replace it entirely:

  ```lua
  -- BEFORE:
      if not _initialised then
          local size = 0
          for _ in pairs(snap) do size = size + 1 end
          if size == 0 then return end
          if size ~= _prevSnapshotSize then
              _prevSnapshot     = snap
              _prevSnapshotSize = size
              return
          end
          -- Same count as last call: roster is stable.
          _prevSnapshot = snap
          _initialised  = true
          return
      end

  -- AFTER:
      if not _initialised then
          local size = 0
          for _ in pairs(snap) do size = size + 1 end
          if size == 0 then return end
          _prevSnapshot = snap
          _initialised  = true
          self:_PruneSpuriousLoginEvents()
          return
      end
  ```

- [ ] **Step 1.4 — Add `_PruneSpuriousLoginEvents` to ActivityLog.lua**

  Add this method in the `── Snapshot diff ──` section, directly after `_OnRosterUpdate`:

  ```lua
  function ActivityLog:_PruneSpuriousLoginEvents()
      local log = GH.DB:GetActivityLog()
      if #log == 0 then return end

      -- Count JOIN/LEAVE events per exact timestamp.
      local tsCounts = {}
      for _, entry in ipairs(log) do
          if entry.type == "JOIN" or entry.type == "LEAVE" then
              tsCounts[entry.ts] = (tsCounts[entry.ts] or 0) + 1
          end
      end

      -- 5+ events at the same second is impossible organically; mark as spurious.
      local spurious = {}
      local found    = false
      for ts, count in pairs(tsCounts) do
          if count >= 5 then
              spurious[ts] = true
              found = true
          end
      end
      if not found then return end

      -- Rebuild log without the spurious JOIN/LEAVE entries.
      local cleaned = {}
      for _, entry in ipairs(log) do
          local isBadType = entry.type == "JOIN" or entry.type == "LEAVE"
          if not (isBadType and spurious[entry.ts]) then
              cleaned[#cleaned + 1] = entry
          end
      end
      GH.DB:SetActivityLog(cleaned)
  end
  ```

- [ ] **Step 1.5 — In-game verification**

  Log in and open GuildHub → Activity tab.
  - The tab should show only real events (promotions, level-ups, notes), not a flood of everyone joined/left.
  - Previous bad entries (any group of 5+ JOIN or LEAVE events sharing the same timestamp) should now be gone.
  - If you had no previous events, the tab should be empty or show only real activity.

- [ ] **Step 1.6 — Commit**

  ```bash
  git add Interface/Addons/GuildHub/ActivityLog.lua Interface/Addons/GuildHub/Database.lua
  git commit -m "fix: simplify ActivityLog init and prune spurious login join/leave events"
  ```

---

## Task 2: Add shared font infrastructure to Styles.lua

**Files:**
- Modify: `Interface/Addons/GuildHub/UI/Styles.lua`

- [ ] **Step 2.1 — Update `S:Header` to use the shared font object**

  Find `S:Header` (around line 151) and change the font string creation:

  ```lua
  -- BEFORE:
  function S:Header(parent, text)
      local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  -- AFTER:
  function S:Header(parent, text)
      local fs = parent:CreateFontString(nil, "OVERLAY")
      fs:SetFontObject(S.FontSmall)
  ```

- [ ] **Step 2.2 — Update `S:SectionLabel` to use the shared font object**

  Find `S:SectionLabel` (around line 159):

  ```lua
  -- BEFORE:
  function S:SectionLabel(parent, text, xOff, yOff)
      local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  -- AFTER:
  function S:SectionLabel(parent, text, xOff, yOff)
      local fs = parent:CreateFontString(nil, "OVERLAY")
      fs:SetFontObject(S.FontSmall)
  ```

- [ ] **Step 2.3 — Update `S:Button` label to use the shared font object**

  Find `S:Button` (around line 181). The label creation is near the end of the function body:

  ```lua
  -- BEFORE:
      local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  -- AFTER:
      local label = btn:CreateFontString(nil, "OVERLAY")
      label:SetFontObject(S.FontSmall)
  ```

- [ ] **Step 2.4 — Update `S:EditBox` to use the shared font object**

  Find `S:EditBox` (around line 236):

  ```lua
  -- BEFORE:
      eb:SetFontObject("GameFontNormalSmall")

  -- AFTER:
      eb:SetFontObject(S.FontSmall)
  ```

- [ ] **Step 2.5 — Update `S:ScrollText` to use the shared font object**

  Find `S:ScrollText` (around line 269):

  ```lua
  -- BEFORE:
      local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  -- AFTER:
      local text = content:CreateFontString(nil, "OVERLAY")
      text:SetFontObject(S.FontSmall)
  ```

- [ ] **Step 2.6 — Add font objects, `S:ApplyFontSize`, and `S:FS` at the bottom of Styles.lua**

  Append after all existing code (after `S:PanelHeader`):

  ```lua
  -- ── Shared font objects ───────────────────────────────────────────────────
  -- Created at module load; sized by S:ApplyFontSize() before any UI builds.
  -- All UI font strings reference these via SetFontObject so a single
  -- ApplyFontSize call updates every font string live.
  S.FontSmall  = CreateFont("GuildHubFontSmall")
  S.FontNormal = CreateFont("GuildHubFontNormal")
  S.FontLarge  = CreateFont("GuildHubFontLarge")

  -- Apply a new base size to all three tiers.
  -- FontSmall = baseSize, FontNormal = baseSize+2, FontLarge = baseSize+4.
  -- Font path is derived from WoW's built-in GameFontNormal to respect locale.
  function S:ApplyFontSize(baseSize)
      local path, _, flags = GameFontNormal:GetFont()
      path  = path  or "Fonts\\FRIZQT__.TTF"
      flags = flags or ""
      self.FontSmall:SetFont(path,  baseSize,     flags)
      self.FontNormal:SetFont(path, baseSize + 2, flags)
      self.FontLarge:SetFont(path,  baseSize + 4, flags)
  end

  -- Factory helper: create a font string and assign the right font tier.
  -- tier: "small" (default, 10pt at default size)
  --       "normal" (12pt at default size)
  --       "large"  (14pt at default size)
  function S:FS(parent, layer, tier)
      local fs = parent:CreateFontString(nil, layer or "OVERLAY")
      if     tier == "normal" then fs:SetFontObject(self.FontNormal)
      elseif tier == "large"  then fs:SetFontObject(self.FontLarge)
      else                         fs:SetFontObject(self.FontSmall)
      end
      return fs
  end
  ```

- [ ] **Step 2.7 — Commit**

  ```bash
  git add Interface/Addons/GuildHub/UI/Styles.lua
  git commit -m "feat: add shared GuildHub font objects and S:FS/ApplyFontSize helpers"
  ```

---

## Task 3: DB fontSize default + startup apply

**Files:**
- Modify: `Interface/Addons/GuildHub/Database.lua`
- Modify: `Interface/Addons/GuildHub/UI/MainWindow.lua`

- [ ] **Step 3.1 — Add `fontSize` to DEFAULTS.settings in Database.lua**

  In `DEFAULTS.settings`, add after `debugMode`:

  ```lua
          debugMode             = false,
          fontSize              = 10,
  ```

  The existing migration loop (`for k, v in pairs(DEFAULTS.settings) do if db.settings[k] == nil then...`) automatically applies this default to existing save files on next login.

- [ ] **Step 3.2 — Call `ApplyFontSize` at the start of `UI:Initialize()` in MainWindow.lua**

  Find:
  ```lua
  function UI:Initialize()
      self:CreateMainWindow()
  end
  ```

  Replace with:
  ```lua
  function UI:Initialize()
      S:ApplyFontSize(GH.DB:GetSetting("fontSize") or 10)
      self:CreateMainWindow()
  end
  ```

- [ ] **Step 3.3 — In-game verification**

  `/reload` in-game. GuildHub should open and all text should look identical to before (size 10 = WoW default for small fonts). No Lua errors in chat.

- [ ] **Step 3.4 — Commit**

  ```bash
  git add Interface/Addons/GuildHub/Database.lua Interface/Addons/GuildHub/UI/MainWindow.lua
  git commit -m "feat: add fontSize DB setting and apply shared fonts at UI startup"
  ```

---

## Task 4: Refactor direct CreateFontString calls in UI files

**Background — the transformation rule:**

Every direct `CreateFontString` call that passes a named WoW font as its third argument must be converted to use `S:FS()`. The mapping is:

| Before | After |
|--------|-------|
| `parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")` | `S:FS(parent, "OVERLAY")` |
| `parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")` | `S:FS(parent, "OVERLAY", "normal")` |
| `parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")` | `S:FS(parent, "OVERLAY", "large")` |
| `parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")` | `S:FS(parent, "ARTWORK")` |

`S` is already aliased at the top of every UI file as `local S = GH.Styles`.

**Files:** `MainWindow.lua` already has `local S = GH.Styles` at the top. All other UI files listed in the file map do too. Verify each file has this alias before starting.

**To find all callsites in a file, run (from the GuildHub addon directory):**
```
grep -n "CreateFontString" Interface/Addons/GuildHub/UI/<filename>.lua
```

- [ ] **Step 4.1 — Refactor `ActivityTab.lua`**

  Apply the rule to these lines (verify line numbers with grep before editing — they may shift):

  - Hint text on search box: `searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")` → `S:FS(searchBox, "OVERLAY")`
  - Count label: `toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")` → `S:FS(toolbar, "OVERLAY")`
  - Chip label: `chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")` → `S:FS(chip, "OVERLAY")`
  - Row timestamp (`tsFS`): `row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")` → `S:FS(row, "OVERLAY")`
  - Row description (`descFS`): `row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")` → `S:FS(row, "OVERLAY")`

- [ ] **Step 4.2 — Refactor `MainWindow.lua`**

  Run `grep -n "CreateFontString" Interface/Addons/GuildHub/UI/MainWindow.lua` and apply the rule to every result. Key locations include:
  - Title text (uses `"GameFontNormalLarge"`) → `S:FS(titleBar, "OVERLAY", "large")`
  - Banner font string (uses `"GameFontNormalSmall"`) → `S:FS(bannerInner, "OVERLAY")`
  - News section labels and row name/desc font strings → `S:FS(..., "OVERLAY")`
  - Online badge → `S:FS(sidebar, "OVERLAY")`
  - All font strings in `BuildSettingsPage` — section headers use `"GameFontNormal"` → `"normal"` tier; hint text and row labels use `"GameFontNormalSmall"` → default tier; the Settings page title uses `"GameFontNormalLarge"` → `"large"` tier.

  Do NOT change the `MakeSpinner` display label — it uses `"GameFontNormal"` and should become `S:FS(row, "OVERLAY", "normal")` inside `MakeSpinner`.

- [ ] **Step 4.3 — Refactor remaining UI files**

  For each file below, run `grep -n "CreateFontString"`, then apply the transformation rule to every result:

  - `BanListDialog.lua`
  - `ChatTab.lua`
  - `EventsTab.lua`
  - `ExportDialog.lua`
  - `GroupsTab.lua`
  - `GuildRecruitTab.lua`
  - `MacroDialog.lua`
  - `MembersTab.lua`
  - `MouseoverWindow.lua`
  - `ProfilePanel.lua`
  - `RecruitTab.lua`
  - `TeamsTab.lua`

  After each file, do a quick `/reload` in-game and open the corresponding tab to confirm text renders and no Lua errors appear in chat.

- [ ] **Step 4.4 — Full in-game sweep**

  After all files are done:
  1. `/reload`
  2. Open every tab: Members, Activity, Chat, Teams, Events, LFM, Recruit
  3. Open Settings (gear icon) — check all rows have readable labels and hint text
  4. Hover over a member in the Members tab to trigger the mouseover window
  5. Confirm no Lua errors and all text is visible

- [ ] **Step 4.5 — Commit**

  ```bash
  git add Interface/Addons/GuildHub/UI/
  git commit -m "refactor: use shared GuildHub font objects across all UI files"
  ```

---

## Task 5: Add Font Size spinner to the Settings page

**Files:**
- Modify: `Interface/Addons/GuildHub/UI/MainWindow.lua`

- [ ] **Step 5.1 — Insert the Font Size row in `BuildSettingsPage`**

  In `BuildSettingsPage`, find the `-- 0 — Window Size` block and its closing `end`. Immediately after that `end`, and before the `-- 1 — Time Format` block, insert:

  ```lua
      -- Font Size
      local rowFont = MakeRow("Font Size", rowY)
      rowY = rowY - ROW_H
      do
          local MIN_SIZE, MAX_SIZE = 9, 15

          local sizeDisplay = S:FS(rowFont, "OVERLAY", "normal")
          sizeDisplay:SetPoint("LEFT", rowFont, "LEFT", 230, 0)
          sizeDisplay:SetWidth(26)
          sizeDisplay:SetJustifyH("CENTER")
          sizeDisplay:SetTextColor(
              S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

          local function GetSize() return GH.DB:GetSetting("fontSize") or 10 end
          local function RefreshDisplay() sizeDisplay:SetText(tostring(GetSize())) end
          RefreshDisplay()

          local minusBtn = S:Button(rowFont, "−", 26, 26)
          minusBtn:SetPoint("LEFT", rowFont, "LEFT", 260, 0)
          minusBtn:SetScript("OnClick", function()
              local newSize = math.max(MIN_SIZE, GetSize() - 1)
              GH.DB:SetSetting("fontSize", newSize)
              S:ApplyFontSize(newSize)
              RefreshDisplay()
          end)

          local plusBtn = S:Button(rowFont, "+", 26, 26)
          plusBtn:SetPoint("LEFT", minusBtn, "RIGHT", 4, 0)
          plusBtn:SetScript("OnClick", function()
              local newSize = math.min(MAX_SIZE, GetSize() + 1)
              GH.DB:SetSetting("fontSize", newSize)
              S:ApplyFontSize(newSize)
              RefreshDisplay()
          end)

          local hint = S:FS(rowFont, "OVERLAY")
          hint:SetPoint("LEFT", rowFont, "LEFT", 410, 0)
          hint:SetText("Text size throughout GuildHub, 9–15 (applies immediately)")
          hint:SetTextColor(
              S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
      end
  ```

- [ ] **Step 5.2 — In-game verification**

  `/reload`, open Settings (gear icon):
  - Confirm a "Font Size" row appears between "Window Size" and "Time Format"
  - The current value (10) is displayed
  - Clicking `+` increases the size and all text in GuildHub visibly grows immediately
  - Clicking `−` decreases it
  - Hold `+` to 15 — the button should stop changing the value (max)
  - Hold `−` to 9 — the button should stop (min)
  - Close GuildHub, reopen — the saved size persists

- [ ] **Step 5.3 — Commit**

  ```bash
  git add Interface/Addons/GuildHub/UI/MainWindow.lua
  git commit -m "feat: add Font Size setting with live-update spinner (9–15pt)"
  ```

---

## Self-Review Checklist (already completed before saving this plan)

- [x] **Spec coverage:** All spec requirements have a task: simplified init ✓, pruning ✓, `_prevSnapshotSize` removal ✓, `DB:SetActivityLog` ✓, three font objects ✓, `S:ApplyFontSize` ✓, `S:FS` helper ✓, `fontSize` DB default ✓, startup apply ✓, all 13 UI files + Styles helpers ✓, settings spinner row ✓
- [x] **No placeholders:** All steps show complete code or exact commands
- [x] **Type consistency:** `S.FontSmall/Normal/Large`, `S:ApplyFontSize(baseSize)`, `S:FS(parent, layer, tier)`, `DB:SetActivityLog(newLog)` are named consistently across all tasks
