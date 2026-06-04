# Officer Permissions, Promote/Demote & Team Roles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix officer permission detection, add promote/demote buttons to the profile panel, and add a synced team role system (Roster/Bench/Backup/Trial/Alt) with role-filtered invites.

**Architecture:** Four Lua files change. `Core.lua` widens `IsOfficer()`. `UI/ProfilePanel.lua` gains Promote/Demote buttons. `GroupManager.lua` adds `SetMemberRole()`, a `TMROL` addon message handler, and extends `InviteAll()`. `UI/TeamsTab.lua` adds role badges to the roster sidebar, a right-click role menu, and converts "Invite All Online" to a dropdown.

**Tech Stack:** Lua 5.1, WoW 11.x addon API (no external libraries, no test runner — verification is manual in-game).

---

## File Map

| File | Change |
| --- | --- |
| `Core.lua` | Widen `IsOfficer()` (lines 61-73) |
| `UI/ProfilePanel.lua` | Add `promoteBtn`/`demoteBtn` widgets, `Reflow()` placement, `ShowProfilePanel()` logic |
| `GroupManager.lua` | `TM_ROL` constant, `SetMemberRole()`, TMROL handler in `OnAddonMessage()`, login sync extension, `RemoveMember()` cleanup, `InviteAll()` roles param |
| `UI/TeamsTab.lua` | Role badges + right-click in `RefreshTeamRoster()`, `ShowTeamRoleMenu()`, invite dropdown in `CreateTeamsTab()` |

---

## Task 1: Widen `IsOfficer()` in `Core.lua`

**Files:**
- Modify: `Core.lua:61-73`

- [ ] **Step 1: Edit `IsOfficer()`**

  In `Core.lua`, replace the body of `GH:IsOfficer()` so the rank-flags branch checks any meaningful management flag, not just officer chat speak:

  ```lua
  function GH:IsOfficer()
      if GH:IsGuildMaster() then return true end
      if next(GH._rankFlags) then
          return GH:HasPermission(GH.PERM.OFFICER_CHAT_SPEAK)
              or GH:HasPermission(GH.PERM.PROMOTE)
              or GH:HasPermission(GH.PERM.DEMOTE)
              or GH:HasPermission(GH.PERM.REMOVE)
      end
      local canInvite = rawget(_G, "CanGuildInvite")
      if canInvite and canInvite() then return true end
      local canRemove = rawget(_G, "CanGuildRemove")
      if canRemove and canRemove() then return true end
      return false
  end
  ```

- [ ] **Step 2: Verify in-game**

  Load the addon (`/reload`). As an officer whose rank has Promote/Demote but NOT officer chat speak:
  - Open the Members tab → profile panel for any member → confirm "Save Note" button is enabled and the note box is editable.
  - Open Teams tab → click a team you created → click Members → confirm the invite box and remove buttons are visible.

- [ ] **Step 3: Commit**

  ```
  git add Core.lua
  git commit -m "fix: widen IsOfficer to include promote/demote/remove rank flags"
  ```

---

## Task 2: Add Promote/Demote Widgets to `ProfilePanel.lua`

**Files:**
- Modify: `UI/ProfilePanel.lua`

### Step group A — Widget creation in `CreateProfilePanel`

- [ ] **Step 1: Add `promoteBtn` and `demoteBtn` after `rankHistFS`**

  In `UI/ProfilePanel.lua`, locate the line:

  ```lua
  panel.rankHistFS:SetSpacing(3)
  ```

  Add immediately after it:

  ```lua
  panel.promoteBtn = S:Button(content, "Promote", bw, 24)
  panel.demoteBtn  = S:DangerButton(content, "Demote", bw, 24)
  panel.promoteBtn:Hide()
  panel.demoteBtn:Hide()
  ```

### Step group B — `Reflow()` placement

- [ ] **Step 2: Add promote/demote row to `Reflow()`**

  In `Reflow()`, locate:

  ```lua
      -- Rank History
      placeSection(self.rankHistHdr, self.rankHistLine)
      placeFS(self.rankHistFS)
  ```

  Add immediately after `placeFS(self.rankHistFS)`:

  ```lua
      if self.promoteBtn:IsShown() or self.demoteBtn:IsShown() then
          self.promoteBtn:ClearAllPoints()
          self.promoteBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 2)
          self.demoteBtn:ClearAllPoints()
          self.demoteBtn:SetPoint("LEFT", self.promoteBtn, "RIGHT", 4, 0)
          y = y - 30
      end
  ```

### Step group C — `ShowProfilePanel()` wiring

- [ ] **Step 3: Show/hide and wire click handlers**

  In `ShowProfilePanel()`, locate the rank history block (the section that sets `panel.rankHistFS:SetText(...)`). After that block ends, add:

  ```lua
      -- Promote / Demote
      local isSelf = (memberData.fullName == GH:GetPlayerName() or memberData.name == GH:GetPlayerName())
      panel.promoteBtn:SetShown(not isSelf and GH:CanGuildPromote(memberData.rankIndex))
      panel.demoteBtn:SetShown(not isSelf and GH:CanGuildDemote(memberData.rankIndex))

      local function RankAction(apiFn)
          if memberData.rosterIndex then
              apiFn(memberData.rosterIndex)
              if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
              C_Timer.After(0.3, function()
                  for _, m in ipairs(GH.GuildData:GetMembers()) do
                      if m.fullName == memberData.fullName then
                          UI:ShowProfilePanel(m)
                          break
                      end
                  end
              end)
          end
      end
      panel.promoteBtn:SetScript("OnClick", function()
          RankAction(GuildRosterPromote)
      end)
      panel.demoteBtn:SetScript("OnClick", function()
          RankAction(GuildRosterDemote)
      end)
  ```

- [ ] **Step 4: Verify in-game**

  `/reload`. Open Members tab, click a member lower rank than yours:
  - Confirm "Promote" button appears in the Rank History section.
  - Click Promote → rank changes → panel refreshes with updated rank.
  - Click your own name → confirm neither button appears.
  - As a rank without Promote permission → confirm button is hidden.

- [ ] **Step 5: Commit**

  ```
  git add UI/ProfilePanel.lua
  git commit -m "feat: add promote/demote buttons to profile panel"
  ```

---

## Task 3: `GroupManager.lua` — `TM_ROL` Constant and `SetMemberRole()`

**Files:**
- Modify: `GroupManager.lua`

- [ ] **Step 1: Add `TM_ROL` constant**

  In `GroupManager.lua`, locate the constants block at the top (the lines starting `local TM_INV`, `TM_ACC`, etc.). Add after the last constant in that block:

  ```lua
  local TM_ROL = "TMROL"
  ```

  Also update the protocol comment at the top of the file. Locate:

  ```lua
  --   TMGMR \30 action \30 pendingId \30 canonicalId \30 [newName]  (GM resolution)
  ```

  Add after it:

  ```lua
  --   TMROL \30 groupId \30 memberName \30 role                     (role assignment; "" clears)
  ```

- [ ] **Step 2: Add `Groups:SetMemberRole()`**

  Add this function after `Groups:SetChannel()` (around line 319):

  ```lua
  function Groups:SetMemberRole(groupId, memberName, role)
      if not GH:CanManageTeam(groupId) then return end
      local g = GH.DB:GetGroups()[groupId]
      if not g then return end
      g.memberRoles = g.memberRoles or {}
      if role and role ~= "" then
          g.memberRoles[memberName] = role
      else
          g.memberRoles[memberName] = nil
      end
      GH.DB:SaveGroup(groupId, g)
      local payload = table.concat({ TM_ROL, groupId, memberName, role or "" }, SEP)
      Groups:_Send(payload)
      if GH.UI then GH.UI:RefreshTeamRoster(groupId) end
  end
  ```

- [ ] **Step 3: Add TMROL handler in `OnAddonMessage()`**

  In `Groups:OnAddonMessage()`, locate the final `elseif` block before the closing `end` of the function. Add a new branch after the last existing `elseif`:

  ```lua
      -- ── TMROL: team member role assignment ───────────────────────────────
      elseif msgType == TM_ROL then
          if #parts >= 4 then
              local groupId    = parts[2]
              local memberName = parts[3]
              local role       = parts[4] ~= "" and parts[4] or nil
              local g = GH.DB:GetGroups()[groupId]
              if g then
                  g.memberRoles = g.memberRoles or {}
                  g.memberRoles[memberName] = role
                  GH.DB:SaveGroup(groupId, g)
                  if GH.UI then GH.UI:RefreshTeamRoster(groupId) end
              end
          end
  ```

  Make sure this branch is inside the existing `if payload:sub(1, 2) ~= "TM" then return end` guard and within the same if/elseif chain.

- [ ] **Step 4: Verify — no errors on load**

  `/reload`. Type `/gh` to open GuildHub. Confirm no Lua errors in chat. Open Teams, select a team — roster sidebar loads normally.

- [ ] **Step 5: Commit**

  ```
  git add GroupManager.lua
  git commit -m "feat: add TMROL message type and SetMemberRole() to GroupManager"
  ```

---

## Task 4: `GroupManager.lua` — Login Sync, Cleanup, and `InviteAll` Filter

**Files:**
- Modify: `GroupManager.lua`

- [ ] **Step 1: Extend `RemoveMember()` to clear roles**

  In `Groups:RemoveMember()`, locate the `table.remove(g.members, i)` line inside the members loop. Add immediately after it:

  ```lua
              if g.memberRoles then
                  g.memberRoles[memberName] = nil
              end
  ```

- [ ] **Step 2: Extend login sync to broadcast roles**

  In `Groups:Initialize()`, locate the `C_Timer.After(20, function() ... end)` block. Inside that function, after the existing loop that calls `Groups:_SyncToMember(...)` and `Groups:_OfficerSync(...)`, add a second pass to stagger TMROL messages. The full block becomes:

  ```lua
  C_Timer.After(20, function()
      if not GH:CanManageTeams() then return end
      local myName = GH:GetPlayerName()
      local delay  = 0
      -- Existing: push TMSYN to online team members
      for groupId, g in pairs(GH.DB:GetGroups()) do
          for _, memberName in ipairs(g.members or {}) do
              if memberName ~= myName then
                  local info = GH.GuildData:FindMember(memberName)
                  if info and info.online then
                      local gid, gData, mName = groupId, g, memberName
                      C_Timer.After(delay, function()
                          Groups:_SyncToMember(gid, gData, mName)
                      end)
                      delay = delay + 0.2
                  end
              end
          end
      end
      -- New: push TMROL for each assigned role
      for groupId, g in pairs(GH.DB:GetGroups()) do
          if g.memberRoles then
              for memberName, role in pairs(g.memberRoles) do
                  if role then
                      local gid, mName, r = groupId, memberName, role
                      C_Timer.After(delay, function()
                          local p = table.concat({ TM_ROL, gid, mName, r }, SEP)
                          Groups:_Send(p)
                      end)
                      delay = delay + 0.2
                  end
              end
          end
      end
  end)
  ```

- [ ] **Step 3: Add `roles` filter parameter to `InviteAll()`**

  Replace the existing `Groups:InviteAll()` function with:

  ```lua
  function Groups:InviteAll(id, roles)
      local g = GH.DB:GetGroups()[id]
      if not g then return end
      local myName = GH:GetPlayerName()
      local doInvite = InviteUnit
                    or (C_PartyInfo and C_PartyInfo.InviteUnit)
      if not doInvite then return end
      for _, memberName in ipairs(g.members) do
          if memberName ~= myName then
              local roleMatch = not roles
                  or (g.memberRoles and tContains(roles, g.memberRoles[memberName]))
              if roleMatch then
                  local info = GH.GuildData:FindMember(memberName)
                  if info and info.online then
                      doInvite(info.fullName)
                  end
              end
          end
      end
  end
  ```

  `tContains(tbl, value)` is a WoW built-in that returns true if `value` is present in the array `tbl`.

- [ ] **Step 4: Verify in-game**

  `/reload`. Open Teams → select a team with multiple members → Click old "Invite All Online" (the button still exists, the dropdown is added in Task 6). No errors. Remove a member from the team → confirm no Lua errors.

- [ ] **Step 5: Commit**

  ```
  git add GroupManager.lua
  git commit -m "feat: role login sync, RemoveMember cleanup, InviteAll role filter"
  ```

---

## Task 5: `TeamsTab.lua` — Role Badges and Right-Click in `RefreshTeamRoster`

**Files:**
- Modify: `UI/TeamsTab.lua`

- [ ] **Step 1: Add `canManage` check and `badgeFS` widget to row pool**

  In `UI:RefreshTeamRoster()`, locate the line at the top that reads the group:

  ```lua
  local g = groupId and GH.Groups:Get(groupId)
  ```

  After the guard that returns early when no members, add:

  ```lua
  local canManage = GH:CanManageTeam(groupId)
  ```

  Then in the `if not row then` block that creates new row widgets (the block with `row.dot`, `row.nameFS`), add after `row.nameFS = nameFS`:

  ```lua
              local badgeFS = S:FS(row, "OVERLAY")
              badgeFS:SetJustifyH("RIGHT")
              badgeFS:Hide()
              row.badgeFS = badgeFS
  ```

  Also, in that same `if not row then` block, **remove** the `nameFS:SetPoint("RIGHT", ...)` line entirely (you'll set it dynamically below):

  The block currently ends with lines like:
  ```lua
              nameFS:SetPoint("LEFT",  row, "LEFT",  20, 0)
              nameFS:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  ```
  Change it to only set the LEFT anchor:
  ```lua
              nameFS:SetPoint("LEFT", row, "LEFT", 20, 0)
  ```

- [ ] **Step 2: Set badge and name anchor in the refresh loop**

  In the same `RefreshTeamRoster` function, after the lines that set `row.nameFS:SetText(m.name)` and its color, add:

  ```lua
          -- Role badge (officers/team managers only)
          local role = canManage and g.memberRoles and g.memberRoles[m.name]
          row.nameFS:ClearAllPoints()
          row.nameFS:SetPoint("LEFT", row, "LEFT", 20, 0)
          if role then
              local roleColors = {
                  Roster = { 0.29, 0.67, 0.29 },
                  Bench  = { 0.67, 0.67, 0.19 },
                  Backup = { 0.48, 0.60, 0.48 },
                  Trial  = { 0.80, 0.40, 0.40 },
                  Alt    = { 0.40, 0.53, 0.67 },
              }
              local rc = roleColors[role] or { 0.55, 0.55, 0.55 }
              row.badgeFS:ClearAllPoints()
              row.badgeFS:SetPoint("RIGHT", row, "RIGHT", -6, 0)
              row.badgeFS:SetText(role)
              row.badgeFS:SetTextColor(rc[1], rc[2], rc[3])
              row.badgeFS:Show()
              row.nameFS:SetPoint("RIGHT", row.badgeFS, "LEFT", -4, 0)
          else
              row.badgeFS:SetText("")
              row.badgeFS:Hide()
              row.nameFS:SetPoint("RIGHT", row, "RIGHT", -6, 0)
          end
  ```

- [ ] **Step 3: Add right-click handler per row**

  Immediately after the badge block, add:

  ```lua
          -- Right-click to set role (officers/team managers only)
          if canManage then
              local capturedId   = groupId
              local capturedName = m.name
              row:EnableMouse(true)
              row:SetScript("OnMouseUp", function(self, button)
                  if button == "RightButton" then
                      GH.UI:ShowTeamRoleMenu(capturedId, capturedName, self)
                  end
              end)
          else
              row:EnableMouse(false)
              row:SetScript("OnMouseUp", nil)
          end
  ```

- [ ] **Step 4: Verify in-game**

  `/reload`. Open Teams → select a team. As an officer/team manager, confirm the roster sidebar loads with no errors. If any members have roles already set in the DB, confirm their badge appears. Right-click a name → no crash (menu function doesn't exist yet — a Lua error for `ShowTeamRoleMenu` is expected; fix arrives in Task 6).

- [ ] **Step 5: Commit**

  ```
  git add UI/TeamsTab.lua
  git commit -m "feat: role badges and right-click handler in team roster sidebar"
  ```

---

## Task 6: `TeamsTab.lua` — `ShowTeamRoleMenu()`

**Files:**
- Modify: `UI/TeamsTab.lua`

- [ ] **Step 1: Add module-level menu reference**

  Near the top of `UI/TeamsTab.lua`, after the existing module-level locals (`selected`, `lastMsgTs`, etc.), add:

  ```lua
  local activeRoleMenu = nil
  ```

- [ ] **Step 2: Add `UI:ShowTeamRoleMenu()`**

  Add this new function anywhere after `UI:RefreshTeamRoster()`:

  ```lua
  function UI:ShowTeamRoleMenu(groupId, memberName, anchorRow)
      -- Dismiss any existing menu
      if activeRoleMenu then activeRoleMenu:Hide(); activeRoleMenu = nil end

      local menu = CreateFrame("Frame", "GuildHubTeamRoleMenu", UIParent)
      menu:SetFrameStrata("DIALOG")
      menu:SetSize(120, 160)
      menu:SetPoint("TOPRIGHT", anchorRow, "BOTTOMRIGHT", 0, -2)
      S:Bg(menu, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
      activeRoleMenu = menu

      local roles = { "Roster", "Bench", "Backup", "Trial", "Alt" }
      local roleColors = {
          Roster = { 0.29, 0.67, 0.29 },
          Bench  = { 0.67, 0.67, 0.19 },
          Backup = { 0.48, 0.60, 0.48 },
          Trial  = { 0.80, 0.40, 0.40 },
          Alt    = { 0.40, 0.53, 0.67 },
      }

      -- Header
      local hdr = S:FS(menu, "OVERLAY")
      hdr:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -6)
      hdr:SetText("Set Role")
      hdr:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

      -- Divider under header
      local div1 = menu:CreateTexture(nil, "ARTWORK")
      div1:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, -24)
      div1:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -24)
      div1:SetHeight(1)
      div1:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

      local ROW_H = 22
      local yOff  = -28
      for _, role in ipairs(roles) do
          local btn = CreateFrame("Button", nil, menu)
          btn:SetPoint("TOPLEFT",  menu, "TOPLEFT",  2, yOff)
          btn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, yOff)
          btn:SetHeight(ROW_H)
          local bg = btn:CreateTexture(nil, "BACKGROUND")
          bg:SetAllPoints()
          bg:SetColorTexture(0, 0, 0, 0)
          btn:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.06) end)
          btn:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
          local fs = S:FS(btn, "OVERLAY")
          fs:SetPoint("LEFT", btn, "LEFT", 8, 0)
          local rc = roleColors[role]
          fs:SetText(role)
          fs:SetTextColor(rc[1], rc[2], rc[3])
          local capRole = role
          btn:SetScript("OnClick", function()
              GH.Groups:SetMemberRole(groupId, memberName, capRole)
              menu:Hide()
              activeRoleMenu = nil
          end)
          yOff = yOff - ROW_H
      end

      -- Divider before Clear
      local div2 = menu:CreateTexture(nil, "ARTWORK")
      div2:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, yOff)
      div2:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, yOff)
      div2:SetHeight(1)
      div2:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
      yOff = yOff - 4

      -- Clear button
      local clearBtn = CreateFrame("Button", nil, menu)
      clearBtn:SetPoint("TOPLEFT",  menu, "TOPLEFT",  2, yOff)
      clearBtn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, yOff)
      clearBtn:SetHeight(ROW_H)
      local clearBg = clearBtn:CreateTexture(nil, "BACKGROUND")
      clearBg:SetAllPoints()
      clearBg:SetColorTexture(0, 0, 0, 0)
      clearBtn:SetScript("OnEnter", function() clearBg:SetColorTexture(1, 1, 1, 0.04) end)
      clearBtn:SetScript("OnLeave", function() clearBg:SetColorTexture(0, 0, 0, 0) end)
      local clearFS = S:FS(clearBtn, "OVERLAY")
      clearFS:SetPoint("LEFT", clearBtn, "LEFT", 8, 0)
      clearFS:SetText("Clear")
      clearFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
      clearBtn:SetScript("OnClick", function()
          GH.Groups:SetMemberRole(groupId, memberName, nil)
          menu:Hide()
          activeRoleMenu = nil
      end)

      -- Full-screen overlay to dismiss on outside click
      local overlay = CreateFrame("Frame", nil, UIParent)
      overlay:SetAllPoints(UIParent)
      overlay:SetFrameStrata("HIGH")
      overlay:SetFrameLevel(menu:GetFrameLevel() - 2)
      overlay:EnableMouse(true)
      overlay:SetScript("OnMouseDown", function()
          menu:Hide()
          activeRoleMenu = nil
          overlay:Hide()
      end)
      menu:SetScript("OnHide", function() overlay:Hide() end)

      menu:Show()
  end
  ```

- [ ] **Step 3: Verify in-game**

  `/reload`. Open Teams → select a team with members → right-click a name in the roster sidebar:
  - Role menu appears with Roster / Bench / Backup / Trial / Alt / Clear.
  - Click a role → badge updates on that row, menu closes.
  - Click outside the menu → menu closes.
  - Click Clear on a member with a role → badge disappears.
  - As a non-officer member → no right-click menu (row has no handler).

- [ ] **Step 4: Commit**

  ```
  git add UI/TeamsTab.lua
  git commit -m "feat: ShowTeamRoleMenu for right-click role assignment in roster"
  ```

---

## Task 7: `TeamsTab.lua` — Invite Dropdown

**Files:**
- Modify: `UI/TeamsTab.lua`

- [ ] **Step 1: Add module-level invite menu reference**

  Near the existing `local activeRoleMenu = nil` line, add:

  ```lua
  local activeInviteMenu = nil
  ```

- [ ] **Step 2: Replace `inviteBtn` click handler**

  In `UI:CreateTeamsTab()`, locate:

  ```lua
      local inviteBtn = S:Button(tabStrip, "Invite All Online", 140, 26)
      inviteBtn:SetPoint("RIGHT", membersBtn, "LEFT", -4, 0)
      inviteBtn:SetScript("OnClick", function()
          if selected then GH.Groups:InviteAll(selected) end
      end)
  ```

  Replace with:

  ```lua
      local inviteBtn = S:Button(tabStrip, "Invite All Online \226\150\190", 152, 26)
      inviteBtn:SetPoint("RIGHT", membersBtn, "LEFT", -4, 0)
      inviteBtn:SetScript("OnClick", function()
          if not selected then return end
          -- Dismiss existing
          if activeInviteMenu then activeInviteMenu:Hide(); activeInviteMenu = nil end

          local opts = {
              { label = "All online members", roles = nil },
              { label = "Roster only",        roles = { "Roster" } },
              { label = "Roster + Bench",     roles = { "Roster", "Bench" } },
              { label = "Trial only",         roles = { "Trial" } },
          }
          local ROW_H = 22
          local menuH = #opts * ROW_H + 8 + 4  -- rows + padding + divider gap
          local menu = CreateFrame("Frame", nil, UIParent)
          menu:SetFrameStrata("DIALOG")
          menu:SetSize(168, menuH)
          menu:SetPoint("TOPRIGHT", inviteBtn, "BOTTOMRIGHT", 0, -2)
          S:Bg(menu, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
          activeInviteMenu = menu

          local yOff = -4
          for i, opt in ipairs(opts) do
              -- Divider before role-specific options
              if i == 2 then
                  local div = menu:CreateTexture(nil, "ARTWORK")
                  div:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, yOff)
                  div:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, yOff)
                  div:SetHeight(1)
                  div:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
                  yOff = yOff - 4
              end
              local btn = CreateFrame("Button", nil, menu)
              btn:SetPoint("TOPLEFT",  menu, "TOPLEFT",  2, yOff)
              btn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, yOff)
              btn:SetHeight(ROW_H)
              local bg = btn:CreateTexture(nil, "BACKGROUND")
              bg:SetAllPoints()
              bg:SetColorTexture(0, 0, 0, 0)
              btn:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.06) end)
              btn:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
              local fs = S:FS(btn, "OVERLAY")
              fs:SetPoint("LEFT", btn, "LEFT", 8, 0)
              fs:SetText(opt.label)
              fs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
              local capRoles = opt.roles
              local capSel   = selected
              btn:SetScript("OnClick", function()
                  GH.Groups:InviteAll(capSel, capRoles)
                  menu:Hide()
                  activeInviteMenu = nil
              end)
              yOff = yOff - ROW_H
          end

          -- Full-screen overlay to dismiss on outside click
          local overlay = CreateFrame("Frame", nil, UIParent)
          overlay:SetAllPoints(UIParent)
          overlay:SetFrameStrata("HIGH")
          overlay:SetFrameLevel(menu:GetFrameLevel() - 2)
          overlay:EnableMouse(true)
          overlay:SetScript("OnMouseDown", function()
              menu:Hide()
              activeInviteMenu = nil
              overlay:Hide()
          end)
          menu:SetScript("OnHide", function() overlay:Hide() end)
          menu:Show()
      end)
  ```

  > Note: `"\226\150\190"` is the UTF-8 byte sequence for the ▾ (▾ U+25BE) character, which Lua can embed as decimal escape sequences.

- [ ] **Step 3: Verify in-game**

  `/reload`. Open Teams → select a team → click "Invite All Online ▾":
  - Dropdown appears with four options.
  - "All online members" → invites all online members (unchanged behaviour).
  - "Roster only" → only members tagged Roster get invited.
  - "Roster + Bench" → members tagged Roster or Bench get invited.
  - "Trial only" → only Trial-tagged members get invited.
  - Click outside → dropdown closes.
  - Dimmed state (no team selected) → clicking the button does nothing (guard in handler).

- [ ] **Step 4: Commit**

  ```
  git add UI/TeamsTab.lua
  git commit -m "feat: invite all online dropdown with role-filtered options"
  ```

---

## Done

All four files changed, seven commits. Verify the full flow end-to-end:

1. Log in as an officer with Promote/Demote but no officer chat speak → confirm GuildHub treats you as an officer throughout.
2. Open a member's profile → confirm Promote/Demote buttons appear (or are hidden) correctly based on your rank vs theirs.
3. Open a team you manage → right-click roster members → assign roles → confirm badges appear and persist after `/reload`.
4. Have a second officer online → assign a role → confirm the second officer's roster updates within a few seconds.
5. Click "Invite All Online ▾" → test each dropdown option.
