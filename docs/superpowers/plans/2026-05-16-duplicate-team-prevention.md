# Duplicate Team Prevention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent duplicate teams by blocking creation-time collisions and routing sync-time duplicates through a GM approval dialog with four resolution options.

**Architecture:** Two enforcement points — a UI-layer creation guard in `ShowTeamNameDialog` and a protocol-layer dedup in the `TM_OFC` handler. Pending teams are flagged in the DB and carried in `TM_OFC`, making the state durable across offline periods. A new GM conflict dialog serialises resolution via two new addon message types (`TMDPC`, `TMGMR`).

**Tech Stack:** Lua 5.1 (WoW addon environment), WoW addon message API (`C_ChatInfo.SendAddonMessage`), `GetGuildInfo` for rank checks. No test framework — each task is verified in-game via `/reload`.

---

## File Map

| File | Changes |
|------|---------|
| `GroupManager.lua` | `Groups:Create()` adds `createdAt`. `Groups:GetAll()` exposes `pending`/`createdAt`. `_OfficerSync` carries two new TM_OFC fields. TM_OFC handler reads them. New `_CheckForDuplicate` and `_ExecuteResolution` helpers. New `TM_DPC`/`TM_GMR` constants and handlers in `OnAddonMessage`. |
| `UI/TeamsTab.lua` | `ShowTeamNameDialog` gains inline error + name-collision check. `RefreshTeamsGroupList` renders pending tabs. `UI:EnqueueConflict` and `UI:ShowTeamConflictDialog` (GM dialog with 4 buttons). `TeamsTab:OnShow` scans for pending conflicts. |

---

### Task 1: Add `createdAt` to group creation and expose `pending` in `GetAll`

**Files:**
- Modify: `GroupManager.lua:76-92` (`Groups:Create`)
- Modify: `GroupManager.lua:46-69` (`Groups:GetAll`)

- [ ] **Step 1: Update `Groups:Create` to store `createdAt`**

In `GroupManager.lua`, replace the `GH.DB:SaveGroup` call inside `Groups:Create`:

```lua
function Groups:Create(name)
    local id = GH.DB:NewId()
    local _, _, rankIndex = GetGuildInfo("player")
    GH.DB:SaveGroup(id, {
        name        = name,
        members     = { GH:GetPlayerName() },
        color       = "7289DA",
        creator     = GH:GetPlayerName(),
        creatorRank = rankIndex or 1,
        createdAt   = time(),
    })
    C_Timer.After(0.5, function()
        local g = GH.DB:GetGroups()[id]
        if g then Groups:_OfficerSync(id, g) end
    end)
    return id
end
```

- [ ] **Step 2: Expose `pending` and `createdAt` in `Groups:GetAll`**

In `Groups:GetAll`, replace the `out[#out + 1] = { ... }` table:

```lua
        out[#out + 1] = {
            id        = id,
            name      = g.name,
            members   = members,
            color     = g.color,
            channelId = g.channelId,
            pending   = g.pending,
            createdAt = g.createdAt,
        }
```

- [ ] **Step 3: Reload and verify**

In-game: `/reload`, open the Teams tab, create a new team named "TestDupe". Then run in chat:
```
/run local g = GH.DB:GetGroups(); for id,v in pairs(g) do if v.name=="TestDupe" then print(id, v.createdAt, v.pending) end end
```
Expected: prints the group ID, a non-zero Unix timestamp, and `nil` (pending not set).

- [ ] **Step 4: Commit**

```
git add Interface/Addons/GuildHub/GroupManager.lua
git commit -m "feat: add createdAt to group creation; expose pending/createdAt in GetAll"
```

---

### Task 2: Update `_OfficerSync` to broadcast `createdAt` + `pending` in TM_OFC

**Files:**
- Modify: `GroupManager.lua:278-289` (`Groups:_OfficerSync`)

- [ ] **Step 1: Replace `Groups:_OfficerSync`**

```lua
function Groups:_OfficerSync(groupId, g)
    local membersStr   = table.concat(g.members or {}, ",")
    local createdAtStr = tostring(g.createdAt or 0)
    local pendingStr   = g.pending and "1" or "0"
    local payload = table.concat(
        { TM_OFC, groupId, g.name, membersStr, g.channelId or "",
          tostring(g.creatorRank or ""), g.creator or "",
          createdAtStr, pendingStr }, SEP)
    if #payload > 250 then
        payload = table.concat(
            { TM_OFC, groupId, g.name, "", g.channelId or "",
              tostring(g.creatorRank or ""), g.creator or "",
              createdAtStr, pendingStr }, SEP)
    end
    Groups:_Send(payload)
end
```

- [ ] **Step 2: Reload and verify no regressions**

In-game: `/reload`, open Teams tab, confirm existing teams still appear for all online officers.

- [ ] **Step 3: Commit**

```
git add Interface/Addons/GuildHub/GroupManager.lua
git commit -m "feat: carry createdAt and pending in TM_OFC officer sync"
```

---

### Task 3: Update TM_OFC handler to read `createdAt` + `pending` and persist them

**Files:**
- Modify: `GroupManager.lua:409-446` (TM_OFC branch in `OnAddonMessage`)

- [ ] **Step 1: Replace the TM_OFC handler block**

Find the `elseif msgType == TM_OFC then` block and replace its entire body:

```lua
    elseif msgType == TM_OFC then
        if GH:IsOfficer() then
            if #parts >= 5 then
                local groupId           = parts[2]
                local teamName          = parts[3]
                local membersStr        = parts[4]
                local channelId         = parts[5] ~= "" and parts[5] or nil
                local creatorRank       = tonumber(parts[6])
                local creator           = (parts[7] and parts[7] ~= "") and parts[7] or nil
                local incomingCreatedAt = tonumber(parts[8]) or 0
                local incomingPending   = parts[9] == "1"

                local members = {}
                if membersStr ~= "" then
                    for n in (membersStr .. ","):gmatch("([^,]*),") do
                        if n ~= "" then members[#members + 1] = n end
                    end
                end

                local existing = GH.DB:GetGroups()[groupId]
                GH.DB:SaveGroup(groupId, {
                    name        = teamName,
                    members     = #members > 0 and members or (existing and existing.members or {}),
                    channelId   = channelId or (existing and existing.channelId),
                    color       = existing and existing.color or "7289DA",
                    creator     = creator or (existing and existing.creator),
                    creatorRank = creatorRank or (existing and existing.creatorRank),
                    createdAt   = incomingCreatedAt ~= 0 and incomingCreatedAt
                                  or (existing and existing.createdAt) or 0,
                    pending     = incomingPending or (existing and existing.pending) or false,
                })

                if channelId and not GH.DB:GetChat(channelId) then
                    GH.DB:SaveChat(channelId, {
                        name     = teamName,
                        members  = members,
                        messages = {},
                    })
                end

                Groups:_CheckForDuplicate(groupId, teamName)
                if GH.UI then GH.UI:RefreshTeamsGroupList() end
            end
        end
```

Note: `Groups:_CheckForDuplicate` is a no-op stub until Task 4; calling it here is harmless.

- [ ] **Step 2: Add a temporary stub for `_CheckForDuplicate` so the file loads**

Immediately after `Groups:_OfficerSync` add:

```lua
function Groups:_CheckForDuplicate(_groupId, _teamName) end
```

This will be replaced in Task 4.

- [ ] **Step 3: Reload and verify**

In-game: `/reload`. Open Teams tab, confirm teams still display. Verify `pending` and `createdAt` are being saved by running:
```
/run local g = GH.DB:GetGroups(); for id,v in pairs(g) do print(v.name, v.createdAt, v.pending) end
```
Expected: each team prints its name, a timestamp (or 0 for old teams), and `nil`/`false` for pending.

- [ ] **Step 4: Commit**

```
git add Interface/Addons/GuildHub/GroupManager.lua
git commit -m "feat: parse createdAt and pending from TM_OFC; wire _CheckForDuplicate stub"
```

---

### Task 4: Implement `Groups:_CheckForDuplicate`

**Files:**
- Modify: `GroupManager.lua` (replace the stub from Task 3)

- [ ] **Step 1: Add `TM_DPC` and `TM_GMR` constants at the top of `GroupManager.lua`**

After the existing constant declarations (`local TM_OFC = "TMOFC"` etc.), add:

```lua
local TM_DPC = "TMDPC"   -- duplicate conflict notification → GM
local TM_GMR = "TMGMR"   -- GM resolution broadcast → all officers
```

- [ ] **Step 2: Replace the `_CheckForDuplicate` stub with the real implementation**

```lua
function Groups:_CheckForDuplicate(incomingId, incomingName)
    local normalizedName = incomingName:lower()
    local incomingGroup  = GH.DB:GetGroups()[incomingId]
    if not incomingGroup then return end

    local canonicalId, pendingId

    for id, g in pairs(GH.DB:GetGroups()) do
        if id ~= incomingId and g.name:lower() == normalizedName then
            local incomingTs = incomingGroup.createdAt or 0
            local existingTs = g.createdAt or 0
            if incomingTs < existingTs or (incomingTs == existingTs and incomingId < id) then
                canonicalId = incomingId
                pendingId   = id
            else
                canonicalId = id
                pendingId   = incomingId
            end
            break
        end
    end

    if not pendingId then return end

    local pendingGroup = GH.DB:GetGroups()[pendingId]
    if pendingGroup and not pendingGroup.pending then
        pendingGroup.pending = true
        GH.DB:SaveGroup(pendingId, pendingGroup)
    end

    if GH:IsGuildMaster() then
        if GH.UI and GH.UI.EnqueueConflict then
            GH.UI:EnqueueConflict(pendingId, canonicalId)
        end
    else
        local payload = table.concat({ TM_DPC, pendingId, canonicalId }, SEP)
        Groups:_Send(payload)
    end
end
```

- [ ] **Step 3: Verify in-game**

Manually insert a duplicate into the DB to test:
```
/run local db=GH.DB:GetGroups(); local id="test_dupe_99999"; db[id]={name="TestDupe",members={},createdAt=time()+100,pending=false}; GH.Groups:_CheckForDuplicate(id,"TestDupe")
```
Expected: the team with the later `createdAt` gets `pending=true`. Run:
```
/run for id,g in pairs(GH.DB:GetGroups()) do if g.name=="TestDupe" then print(id, g.pending, g.createdAt) end end
```
Expected: one entry shows `pending=true`, the other `nil`/`false`.

Clean up: `/run GH.DB:DeleteGroup("test_dupe_99999"); GH.UI:RefreshTeamsGroupList()`

- [ ] **Step 4: Commit**

```
git add Interface/Addons/GuildHub/GroupManager.lua
git commit -m "feat: implement _CheckForDuplicate with createdAt-based canonical determination"
```

---

### Task 5: Add `TMDPC` and `TMGMR` handlers in `OnAddonMessage` + `_ExecuteResolution`

**Files:**
- Modify: `GroupManager.lua` (`OnAddonMessage`, new `_ExecuteResolution`)

- [ ] **Step 1: Add `TMDPC` handler in `OnAddonMessage`**

Inside `Groups:OnAddonMessage`, after the `TM_DLT` handler block, add:

```lua
    -- ── TMDPC: duplicate team conflict notification (received by GM) ─────────
    elseif msgType == TM_DPC then
        if GH:IsGuildMaster() and #parts >= 3 then
            local pendingId   = parts[2]
            local canonicalId = parts[3]
            if GH.DB:GetGroups()[pendingId] and GH.DB:GetGroups()[canonicalId] then
                if GH.UI and GH.UI.EnqueueConflict then
                    GH.UI:EnqueueConflict(pendingId, canonicalId)
                end
            end
        end

    -- ── TMGMR: GM resolution — all officers execute ──────────────────────────
    elseif msgType == TM_GMR then
        if GH:IsOfficer() and #parts >= 4 then
            local action      = parts[2]
            local pendingId   = parts[3]
            local canonicalId = parts[4]
            local newName     = (parts[5] and parts[5] ~= "") and parts[5] or nil
            Groups:_ExecuteResolution(action, pendingId, canonicalId, newName)
        end
```

- [ ] **Step 2: Add `Groups:_ExecuteResolution` after `_CheckForDuplicate`**

```lua
function Groups:_ExecuteResolution(action, pendingId, canonicalId, newName)
    local pendingGroup   = GH.DB:GetGroups()[pendingId]
    local canonicalGroup = GH.DB:GetGroups()[canonicalId]

    if action == "merge" then
        if pendingGroup and canonicalGroup then
            for _, name in ipairs(pendingGroup.members or {}) do
                local inCanonical = false
                for _, n in ipairs(canonicalGroup.members or {}) do
                    if n == name then inCanonical = true; break end
                end
                if not inCanonical then
                    canonicalGroup.members[#canonicalGroup.members + 1] = name
                end
            end
            GH.DB:SaveGroup(canonicalId, canonicalGroup)
            for _, name in ipairs(pendingGroup.members or {}) do
                Groups:_SyncToMember(canonicalId, canonicalGroup, name)
            end
        end
        for _, name in ipairs(pendingGroup and pendingGroup.members or {}) do
            Groups:_SendRemoved(pendingId, name)
        end
        GH.DB:DeleteGroup(pendingId)

    elseif action == "keep" then
        if pendingGroup then
            pendingGroup.pending = false
            GH.DB:SaveGroup(pendingId, pendingGroup)
        end

    elseif action == "delete" then
        if pendingGroup then
            for _, name in ipairs(pendingGroup.members or {}) do
                Groups:_SendRemoved(pendingId, name)
            end
        end
        GH.DB:DeleteGroup(pendingId)

    elseif action == "rename" and newName and newName ~= "" then
        if pendingGroup then
            pendingGroup.name    = newName
            pendingGroup.pending = false
            GH.DB:SaveGroup(pendingId, pendingGroup)
            Groups:_OfficerSync(pendingId, pendingGroup)
        end
    end

    if GH.UI then GH.UI:RefreshTeamsGroupList() end
end
```

Note: The GM's own TMGMR echo will re-enter `_ExecuteResolution` after the GM already executed it locally (from the dialog in Task 9). By then the pending team no longer exists in the DB, so all branches are no-ops. No explicit sender guard is needed.

- [ ] **Step 3: Reload and verify file loads without errors**

In-game: `/reload`. Open Teams tab. Check `!BugGrabber`/`BugSack` for Lua errors.

- [ ] **Step 4: Commit**

```
git add Interface/Addons/GuildHub/GroupManager.lua
git commit -m "feat: add TMDPC/TMGMR handlers and _ExecuteResolution for conflict resolution"
```

---

### Task 6: Creation-time guard in `ShowTeamNameDialog`

**Files:**
- Modify: `UI/TeamsTab.lua:960-991` (`UI:ShowTeamNameDialog`)

- [ ] **Step 1: Replace `UI:ShowTeamNameDialog`**

```lua
function UI:ShowTeamNameDialog(existingName, callback)
    local dlg = CreateFrame("Frame", "GuildHubTeamNameDialog", UIParent)
    dlg:SetSize(320, 130)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    dlg:SetFrameStrata("DIALOG")
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText(existingName and "Rename Team" or "New Team Name")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local eb = S:EditBox(dlg, 280, 28, 60)
    eb:SetPoint("TOP", title, "BOTTOM", 0, -10)
    if existingName then eb:SetText(existingName) end
    eb:SetFocus()

    local errorFs = S:FS(dlg, "OVERLAY")
    errorFs:SetPoint("TOP", eb, "BOTTOM", 0, -4)
    errorFs:SetTextColor(1, 0.3, 0.3)
    errorFs:Hide()

    local okBtn = S:Button(dlg, "OK", 80, 26)
    okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 12)

    local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 12)

    local normalizedExisting = existingName and existingName:lower()

    local function Confirm()
        local name = eb:GetText():match("^%s*(.-)%s*$")
        if name == "" then return end
        local lower = name:lower()
        for _, g in ipairs(GH.Groups:GetAll()) do
            if g.name:lower() == lower and g.name:lower() ~= normalizedExisting then
                errorFs:SetText('"' .. name .. '" already exists.')
                errorFs:Show()
                return
            end
        end
        callback(name)
        dlg:Hide()
    end
    okBtn:SetScript("OnClick", Confirm)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    eb:SetScript("OnEnterPressed", Confirm)
end
```

- [ ] **Step 2: Verify in-game**

In-game: `/reload`. Open Teams tab. Click "+ New Team", type the exact name of an existing team, click OK. Expected: the dialog stays open and shows `"<name>" already exists.` in red below the input. Type a unique name, click OK — team should be created normally.

- [ ] **Step 3: Commit**

```
git add Interface/Addons/GuildHub/UI/TeamsTab.lua
git commit -m "feat: block duplicate team names at creation time with inline error"
```

---

### Task 7: Render pending teams in the tab strip

**Files:**
- Modify: `UI/TeamsTab.lua:389-401` (name label block inside `UI:RefreshTeamsGroupList`)

- [ ] **Step 1: Replace the name label block in `RefreshTeamsGroupList`**

Find the block that creates `nameFs` and sets its text/color. Replace it:

```lua
        local nameFs = S:FS(tab, "OVERLAY")
        nameFs:SetPoint("LEFT",  tab, "LEFT",  22, 0)
        nameFs:SetPoint("RIGHT", tab, "RIGHT", -8, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        if g.pending then
            nameFs:SetText(g.name .. " |cff888888(pending)|r")
            nameFs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2] * 0.6, S.COLOR.TEXT_DIM[3] * 0.6)
        elseif isActive then
            nameFs:SetText(g.name)
            nameFs:SetTextColor(1, 1, 1)
        else
            nameFs:SetText(g.name)
            nameFs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end
```

- [ ] **Step 2: Verify in-game**

Manually mark a team as pending to confirm rendering:
```
/run local g=GH.DB:GetGroups(); for id,v in pairs(g) do v.pending=true; break end; GH.UI:RefreshTeamsGroupList()
```
Expected: one team tab shows `"<name> (pending)"` in dimmed text.

Undo: `/run for id,g in pairs(GH.DB:GetGroups()) do g.pending=false end; GH.UI:RefreshTeamsGroupList()`

- [ ] **Step 3: Commit**

```
git add Interface/Addons/GuildHub/UI/TeamsTab.lua
git commit -m "feat: render pending teams with (pending) suffix in tab strip"
```

---

### Task 8: GM conflict dialog — `EnqueueConflict` + `ShowTeamConflictDialog`

**Files:**
- Modify: `UI/TeamsTab.lua` (append after `UI:ShowGroupNameDialog`)

- [ ] **Step 1: Add queue state and `UI:EnqueueConflict`**

After the final line of `UI:ShowGroupNameDialog`, append:

```lua
-- ── GM duplicate conflict queue ───────────────────────────────────────────

UI._conflictQueue    = {}
UI._conflictShown    = false

function UI:EnqueueConflict(pendingId, canonicalId)
    -- Dedup: skip if this pair is already queued or being shown
    for _, entry in ipairs(UI._conflictQueue) do
        if entry[1] == pendingId and entry[2] == canonicalId then return end
    end
    if UI._conflictActive
       and UI._conflictActive[1] == pendingId
       and UI._conflictActive[2] == canonicalId then
        return
    end
    UI._conflictQueue[#UI._conflictQueue + 1] = { pendingId, canonicalId }
    if not UI._conflictShown then
        local next = table.remove(UI._conflictQueue, 1)
        if next then UI:ShowTeamConflictDialog(next[1], next[2]) end
    end
end
```

- [ ] **Step 2: Add `UI:ShowTeamConflictDialog`**

```lua
function UI:ShowTeamConflictDialog(pendingId, canonicalId)
    UI._conflictShown  = true
    UI._conflictActive = { pendingId, canonicalId }

    local pendingGroup   = GH.DB:GetGroups()[pendingId]
    local canonicalGroup = GH.DB:GetGroups()[canonicalId]
    if not pendingGroup or not canonicalGroup then
        UI._conflictShown  = false
        UI._conflictActive = nil
        local next = table.remove(UI._conflictQueue, 1)
        if next then UI:ShowTeamConflictDialog(next[1], next[2]) end
        return
    end

    local teamName = canonicalGroup.name

    local dlg = CreateFrame("Frame", "GuildHubConflictDialog", UIParent)
    dlg:SetSize(400, 320)
    dlg:SetFrameStrata("DIALOG")
    local mainWin = rawget(_G, "GuildHubMainWindow")
    if mainWin then
        dlg:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", 4, 0)
    else
        dlg:SetPoint("CENTER")
    end
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local accent = dlg:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("TOPRIGHT"); accent:SetHeight(2)
    accent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.80)

    local titleFs = S:FS(dlg, "OVERLAY", "normal")
    titleFs:SetPoint("TOP", dlg, "TOP", 0, -14)
    titleFs:SetText("Duplicate Team Detected")
    titleFs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local bodyFs = S:FS(dlg, "OVERLAY")
    bodyFs:SetPoint("TOP", titleFs, "BOTTOM", 0, -6)
    bodyFs:SetText('Two teams share the name "' .. teamName .. '". Choose a resolution.')
    bodyFs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

    -- Helper: count online members
    local function OnlineCount(members)
        local n = 0
        for _, name in ipairs(members or {}) do
            local info = GH.GuildData.byName[name]
            if info and info.online then n = n + 1 end
        end
        return n
    end

    -- Side-by-side info panels
    local function MakePanel(parent, label, group, xAnchor, xOff)
        local pf = CreateFrame("Frame", nil, parent)
        pf:SetSize(172, 80)
        pf:SetPoint(xAnchor, parent, xAnchor, xOff, -80)
        S:Bg(pf, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

        local lbl = S:FS(pf, "OVERLAY")
        lbl:SetPoint("TOP", pf, "TOP", 0, -6)
        lbl:SetText(label)
        lbl:SetTextColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3])

        local nm = S:FS(pf, "OVERLAY", "normal")
        nm:SetPoint("TOP", lbl, "BOTTOM", 0, -2)
        nm:SetText(group.name)
        nm:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

        local total   = #(group.members or {})
        local online  = OnlineCount(group.members)
        local countFs = S:FS(pf, "OVERLAY")
        countFs:SetPoint("TOP", nm, "BOTTOM", 0, -4)
        countFs:SetText("Members: |cff22cc44" .. online .. "|r/" .. total)
        countFs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        return pf
    end

    MakePanel(dlg, "(older — canonical)", canonicalGroup, "TOPLEFT",  14)
    MakePanel(dlg, "(newer — pending)",   pendingGroup,   "TOPRIGHT", -14)

    -- Shared close logic
    local function CloseAndNext()
        UI._conflictShown  = false
        UI._conflictActive = nil
        dlg:Hide()
        local next = table.remove(UI._conflictQueue, 1)
        if next then
            C_Timer.After(0.1, function() UI:ShowTeamConflictDialog(next[1], next[2]) end)
        end
    end

    -- Shared resolution dispatcher
    local function Resolve(action, newName)
        local payload = table.concat(
            { "TMGMR", action, pendingId, canonicalId, newName or "" }, "\30")
        GH.Groups:_Send(payload)
        GH.Groups:_ExecuteResolution(action, pendingId, canonicalId, newName)
        CloseAndNext()
    end

    -- Rename sub-panel (hidden until Rename button clicked)
    -- Positioned between info panels and action buttons (100px above dialog bottom).
    local renamePanel = CreateFrame("Frame", nil, dlg)
    renamePanel:SetPoint("TOPLEFT",  dlg, "BOTTOMLEFT",  10, 100)
    renamePanel:SetPoint("TOPRIGHT", dlg, "BOTTOMRIGHT", -10, 100)
    renamePanel:SetHeight(50)
    renamePanel:Hide()

    local renameEb = S:EditBox(renamePanel, 230, 26, 60)
    renameEb:SetPoint("LEFT", renamePanel, "LEFT", 0, 0)

    local renameConfirm = S:Button(renamePanel, "Confirm", 90, 26)
    renameConfirm:SetPoint("LEFT", renameEb, "RIGHT", 6, 0)

    local renameErrorFs = S:FS(renamePanel, "OVERLAY")
    renameErrorFs:SetPoint("TOPLEFT", renameEb, "BOTTOMLEFT", 0, -2)
    renameErrorFs:SetTextColor(1, 0.3, 0.3)
    renameErrorFs:Hide()

    renameConfirm:SetScript("OnClick", function()
        local newName = renameEb:GetText():match("^%s*(.-)%s*$")
        if newName == "" then return end
        local lower = newName:lower()
        for _, g in ipairs(GH.Groups:GetAll()) do
            if g.name:lower() == lower and g.id ~= pendingId then
                renameErrorFs:SetText('"' .. newName .. '" already exists.')
                renameErrorFs:Show()
                return
            end
        end
        Resolve("rename", newName)
    end)

    -- Four action buttons
    local btnY  = 14
    local btnH  = 26

    local mergeBtn = S:Button(dlg, "Merge Members", 110, btnH)
    mergeBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 10, btnY)
    mergeBtn:SetScript("OnClick", function() Resolve("merge") end)

    local keepBtn = S:Button(dlg, "Keep Both", 84, btnH)
    keepBtn:SetPoint("LEFT", mergeBtn, "RIGHT", 4, 0)
    keepBtn:SetScript("OnClick", function() Resolve("keep") end)

    local deleteBtn = S:DangerButton(dlg, "Delete Newer", 100, btnH)
    deleteBtn:SetPoint("LEFT", keepBtn, "RIGHT", 4, 0)
    deleteBtn:SetScript("OnClick", function() Resolve("delete") end)

    local renameBtn = S:Button(dlg, "Rename Newer", 106, btnH)
    renameBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)
    renameBtn:SetScript("OnClick", function()
        renamePanel:SetShown(not renamePanel:IsShown())
        if renamePanel:IsShown() then renameEb:SetFocus() end
    end)

    dlg:Show()
end
```

- [ ] **Step 3: Verify the dialog renders**

Manually trigger the dialog as a GM:
```
/run GH.UI:EnqueueConflict("fake_pending_id", "fake_canonical_id")
```
Expected: dialog appears (though both panels will be blank since the IDs are fake — that's fine for rendering verification). Close it manually or test with real pending groups from Task 4's test setup.

To test with real data: follow Task 4's manual injection steps to create a real pending team, then:
```
/run for id,g in pairs(GH.DB:GetGroups()) do if g.pending then for id2,g2 in pairs(GH.DB:GetGroups()) do if id2~=id and g2.name:lower()==g.name:lower() then GH.UI:EnqueueConflict(id,id2) end end end end
```

- [ ] **Step 4: Commit**

```
git add Interface/Addons/GuildHub/UI/TeamsTab.lua
git commit -m "feat: add GM conflict dialog with merge/keep/delete/rename resolution options"
```

---

### Task 9: Scan for pending conflicts on `TeamsTab:OnShow`

**Files:**
- Modify: `UI/TeamsTab.lua:304-310` (`frame:SetScript("OnShow", ...)`)

- [ ] **Step 1: Extend the OnShow handler**

Replace the existing `frame:SetScript("OnShow", ...)` block:

```lua
    frame:SetScript("OnShow", function()
        local isOfficer = GH:IsOfficer()
        frame.newTeamBtn:SetShown(isOfficer)
        frame.deleteBtn:SetShown(isOfficer)
        UI:RefreshTeamsGroupList()
        if selected then UI:ShowTeamView(selected) end

        -- GM: find any teams still marked pending and queue conflict dialogs
        if GH:IsGuildMaster() then
            for pendingId, pg in pairs(GH.DB:GetGroups()) do
                if pg.pending then
                    for canonicalId, cg in pairs(GH.DB:GetGroups()) do
                        if canonicalId ~= pendingId
                           and cg.name:lower() == pg.name:lower()
                           and not cg.pending then
                            UI:EnqueueConflict(pendingId, canonicalId)
                        end
                    end
                end
            end
        end
    end)
```

- [ ] **Step 2: Verify in-game**

As a GM: use Task 4's injection to create a pending team, then `/reload`, open the Teams tab. Expected: conflict dialog appears automatically.

As a non-GM officer: open the Teams tab. Expected: no conflict dialog appears.

- [ ] **Step 3: Commit**

```
git add Interface/Addons/GuildHub/UI/TeamsTab.lua
git commit -m "feat: auto-show conflict dialog for GMs when pending teams exist on tab open"
```

---

### Task 10: End-to-end smoke test

This task has no code changes — it verifies the full flow works correctly with two clients.

- [ ] **Scenario A — Creation-time guard**

1. Log in as any officer. Note an existing team name (e.g. "MT6").
2. Click "+ New Team", type "MT6", click OK.
3. Expected: dialog stays open, error `"MT6" already exists.` shown in red.
4. Type a unique name, click OK. Expected: team created normally.

- [ ] **Scenario B — Offline duplicate → GM approval**

1. Officer A logs out.
2. Officer B creates a team "TestOff" while A is offline.
3. Officer A logs back in. Their client broadcasts TM_OFC for their "TestOff".
4. Expected: Officer B's client detects the collision, marks their "TestOff" as pending, broadcasts TMDPC.
5. If GM is online: GM conflict dialog appears immediately.
6. If GM was offline: GM logs in, opens Teams tab, conflict dialog appears.

- [ ] **Verify all four resolution paths**

For each, manually create a duplicate pair using the Task 4 injection method:

**Merge:** Click "Merge Members". Expected: members combined into canonical team; duplicate tab disappears; merged members now only see canonical.

**Keep Both:** Click "Keep Both". Expected: both tabs remain, neither shows "(pending)".

**Delete Newer:** Click "Delete Newer". Expected: pending tab disappears; members of pending team receive "removed from a team" message.

**Rename Newer:** Click "Rename Newer", type a unique name, click Confirm. Expected: pending tab shows new name, no longer marked pending.

- [ ] **Verify rename collision guard**

In the conflict dialog, click "Rename Newer", type an existing team name, click Confirm. Expected: inline error shown, dialog stays open.
