# Permissions System & Guild Note Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace GuildHub's single `IsOfficer()` check with WoW-native per-rank permission flags, and add guild note editing for any rank that has the Edit Public Note permission.

**Architecture:** A new `Permissions.lua` module reads `GuildControlGetRankFlags` for every rank on load and on guild update events, caches results in `GH._rankFlags`, and exposes `GH:HasPermission(flag)` plus named per-action wrappers. `Core.lua` is updated to remove the old threshold-detection heuristic and redefine all permission checks against the new system. UI call sites in `MembersTab.lua` and `ProfilePanel.lua` are updated to use specific checks, and a new guild note dialog is added.

**Tech Stack:** Lua, WoW 12.x addon API (`GuildControlGetNumRanks`, `GuildControlGetRankFlags`, `GetGuildInfo`, `GuildRosterSetPublicNote`)

---

### Task 1: Create `Permissions.lua`

**Files:**
- Create: `Permissions.lua`
- Modify: `GuildHub.toc`

- [ ] **Step 1: Create `Permissions.lua` with full content**

Create `c:\Program Files (x86)\World of Warcraft\_retail_\Interface\Addons\GuildHub\Permissions.lua` with:

```lua
-- GuildHub - Permissions
-- Reads WoW rank permission flags and exposes named per-action checks.
-- GuildControlGetRankFlags uses the same 0-based rankIndex as GetGuildInfo("player").
-- Rank 0 (Guild Master) is handled as a special case — always has all permissions.

local GH = GuildHub
local P  = GH.Permissions

-- Flag slot indices returned by GuildControlGetRankFlags.
-- Indices 3 and 4 (officer chat) are confirmed by the prior DetectOfficerThreshold code.
-- Others match the WoW Guild Control UI order; adjust if a specific check misbehaves.
GH.PERM = {
    GUILD_CHAT_LISTEN   = 1,
    GUILD_CHAT_SPEAK    = 2,
    OFFICER_CHAT_LISTEN = 3,
    OFFICER_CHAT_SPEAK  = 4,
    PROMOTE             = 5,
    DEMOTE              = 6,
    INVITE              = 7,
    REMOVE              = 8,
    SET_MOTD            = 9,
    EDIT_PUBLIC_NOTE    = 10,
    VIEW_OFFICER_NOTE   = 11,
    EDIT_OFFICER_NOTE   = 12,
    MODIFY_GUILD_INFO   = 13,
}

-- GH._rankFlags[rankIndex] = array of flag values from GuildControlGetRankFlags
GH._rankFlags = {}

function P:LoadRankPermissions()
    local getNumRanks  = rawget(_G, "GuildControlGetNumRanks")
    local getRankFlags = rawget(_G, "GuildControlGetRankFlags")
    if not getNumRanks or not getRankFlags then return end

    local numRanks = getNumRanks() or 0
    if numRanks < 2 then return end  -- guild data not ready; GUILD_ROSTER_UPDATE will retry

    GH._rankFlags = {}
    for ri = 1, numRanks - 1 do  -- skip 0 (GM); GM handled as special case in HasPermission
        local ok, flags = pcall(function() return { getRankFlags(ri) } end)
        if ok and flags then
            GH._rankFlags[ri] = flags
        end
    end
end

function GH:HasPermission(flag)
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == nil then return false end
    if rankIndex == 0 then return true end  -- GM always has all permissions
    local flags = GH._rankFlags[rankIndex]
    if not flags then return false end
    local v = flags[flag]
    return v == 1 or v == true
end

function P:Initialize()
    self:LoadRankPermissions()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function()
        P:LoadRankPermissions()
    end)
end
```

- [ ] **Step 2: Add `Permissions.lua` to the TOC after `Core.lua`**

In `GuildHub.toc`, change:

```
Library/BNetChatThrottleLib.lua
Core.lua
Debug.lua
```

to:

```
Library/BNetChatThrottleLib.lua
Core.lua
Permissions.lua
Debug.lua
```

- [ ] **Step 3: Verify the file loads without error**

Log in to WoW (or `/reload`). Confirm no Lua error appears in chat. Then open the GuildHub window with `/gh` and confirm it still opens normally.

- [ ] **Step 4: Commit**

```
git add Permissions.lua GuildHub.toc
git commit -m "feat: add Permissions module with rank-flag cache and HasPermission"
```

---

### Task 2: Update `Core.lua`

**Files:**
- Modify: `Core.lua`

- [ ] **Step 1: Add `GH.Permissions` to the namespace block and wire `Initialize`**

In `Core.lua`, change the namespace block (lines 9–20) from:

```lua
GH.DB = GH.DB or {}
GH.UI = GH.UI or {}
GH.GuildData = GH.GuildData or {}
GH.Groups = GH.Groups or {}
GH.Chat = GH.Chat or {}
GH.BNetChat = GH.BNetChat or {}
GH.Events = GH.Events or {}
GH.Recruit = GH.Recruit or {}
GH.GuildRecruit = GH.GuildRecruit or {}
GH.Profiles = GH.Profiles or {}
GH.ProfileSync = GH.ProfileSync or {}
GH.ActivityLog = GH.ActivityLog or {}
```

to:

```lua
GH.DB = GH.DB or {}
GH.UI = GH.UI or {}
GH.GuildData = GH.GuildData or {}
GH.Groups = GH.Groups or {}
GH.Chat = GH.Chat or {}
GH.BNetChat = GH.BNetChat or {}
GH.Events = GH.Events or {}
GH.Recruit = GH.Recruit or {}
GH.GuildRecruit = GH.GuildRecruit or {}
GH.Profiles = GH.Profiles or {}
GH.ProfileSync = GH.ProfileSync or {}
GH.ActivityLog = GH.ActivityLog or {}
GH.Permissions = GH.Permissions or {}
```

Then in `GH:Initialize()`, add `self.Permissions:Initialize()` immediately after `self.DB:Initialize()`:

```lua
function GH:Initialize()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.ADDON_PREFIX)
    end

    self.DB:Initialize()
    self.Permissions:Initialize()
    self.GuildData:Initialize()
    self.Groups:Initialize()
    self.Chat:Initialize()
    self.BNetChat:Initialize()
    self.Events:Initialize()
    self.Recruit:Initialize()
    self.GuildRecruit:Initialize()
    self.Profiles:Initialize()
    self.ActivityLog:Initialize()
    self.ProfileSync:Initialize()
    self.UI:Initialize()

    print("|cff7289daGuildHub|r loaded! Type |cffffd700/gh|r to open.")
end
```

- [ ] **Step 2: Remove `DetectOfficerThreshold` and replace `IsOfficer`**

Delete the entire `GH:DetectOfficerThreshold()` function (the block starting with the comment `-- Walks WoW guild rank flags…` through the closing `end` of the function, lines ~55–83).

Replace the existing `GH:IsOfficer()` function with the new version plus all named wrappers. The old `IsOfficer` block to remove:

```lua
function GH:IsOfficer()
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == nil then return false end
    local threshold = GH.DB and GH.DB:GetSetting("officerRankThreshold")
    if threshold == nil then
        threshold = GH:DetectOfficerThreshold()
    end
    return rankIndex <= threshold
end
```

Replace with:

```lua
function GH:IsOfficer()
    return GH:HasPermission(GH.PERM.OFFICER_CHAT_SPEAK)
end

function GH:CanEditPublicNote()
    return GH:HasPermission(GH.PERM.EDIT_PUBLIC_NOTE)
end

function GH:CanPromote()
    return GH:HasPermission(GH.PERM.PROMOTE)
end

function GH:CanDemote()
    return GH:HasPermission(GH.PERM.DEMOTE)
end

function GH:CanInvite()
    return GH:HasPermission(GH.PERM.INVITE)
end

function GH:CanRemoveMember()
    return GH:HasPermission(GH.PERM.REMOVE)
end

function GH:CanViewOfficerNote()
    return GH:HasPermission(GH.PERM.VIEW_OFFICER_NOTE)
end

function GH:CanEditOfficerNote()
    return GH:HasPermission(GH.PERM.EDIT_OFFICER_NOTE)
end
```

- [ ] **Step 3: Verify in-game**

`/reload`. Confirm no Lua errors. Open `/gh` → Members tab. Verify:
- If you are an officer (or GM), the Promote / Demote / Kick options still appear in the right-click context menu.
- The Recruit tab is still visible for officers.

- [ ] **Step 4: Commit**

```
git add Core.lua
git commit -m "feat: wire Permissions into Core, replace IsOfficer with flag-based checks"
```

---

### Task 3: Update `MembersTab.lua` Context Menu

**Files:**
- Modify: `UI/MembersTab.lua`

- [ ] **Step 1: Replace the Promote/Demote/Kick block with specific checks**

In `UI:ShowMemberContextMenu`, find and replace the officer action block (the final `if GH:IsOfficer() then` block that adds Promote, Demote, and Kick):

```lua
    if GH:IsOfficer() then
        sep()
        item("Promote", function()
            local fn = rawget(_G, "GuildPromote")
            if fn then fn(member.name)
            elseif C_GuildInfo and C_GuildInfo.Promote then C_GuildInfo.Promote(member.name)
            end
        end)
        item("Demote", function()
            local fn = rawget(_G, "GuildDemote")
            if fn then fn(member.name)
            elseif C_GuildInfo and C_GuildInfo.Demote then C_GuildInfo.Demote(member.name)
            end
        end)
        item("Kick from Guild", function()
            local fn = rawget(_G, "GuildUninvite")
            if fn then fn(member.name)
            elseif C_GuildInfo and C_GuildInfo.KickMember then C_GuildInfo.KickMember(member.name)
            end
        end, true)
    end
```

Replace with:

```lua
    local canPromote = GH:CanPromote()
    local canDemote  = GH:CanDemote()
    local canRemove  = GH:CanRemoveMember()
    if canPromote or canDemote or canRemove then
        sep()
        if canPromote then
            item("Promote", function()
                local fn = rawget(_G, "GuildPromote")
                if fn then fn(member.name)
                elseif C_GuildInfo and C_GuildInfo.Promote then C_GuildInfo.Promote(member.name)
                end
            end)
        end
        if canDemote then
            item("Demote", function()
                local fn = rawget(_G, "GuildDemote")
                if fn then fn(member.name)
                elseif C_GuildInfo and C_GuildInfo.Demote then C_GuildInfo.Demote(member.name)
                end
            end)
        end
        if canRemove then
            item("Kick from Guild", function()
                local fn = rawget(_G, "GuildUninvite")
                if fn then fn(member.name)
                elseif C_GuildInfo and C_GuildInfo.KickMember then C_GuildInfo.KickMember(member.name)
                end
            end, true)
        end
    end
```

- [ ] **Step 2: Add "Edit Guild Note" to the context menu**

Find the "Edit Personal Note" item:

```lua
    item("Edit Personal Note", function()
        UI:ShowPersonalNoteDialog(member.fullName)
    end)
```

Add "Edit Guild Note" directly after it:

```lua
    item("Edit Personal Note", function()
        UI:ShowPersonalNoteDialog(member.fullName)
    end)
    if GH:CanEditPublicNote() then
        item("Edit Guild Note", function()
            UI:ShowGuildNoteDialog(member)
        end)
    end
```

- [ ] **Step 3: Verify in-game**

`/reload`. Right-click a guild member in the Members tab:
- As GM/officer with all perms: Promote, Demote, Kick, and Edit Guild Note all appear.
- Verify that a rank without Kick permission would not show Kick (if you can test with an alt account or ask a guildie to check).

- [ ] **Step 4: Commit**

```
git add UI/MembersTab.lua
git commit -m "feat: specific permission checks in context menu, add Edit Guild Note item"
```

---

### Task 4: Add `editGuildNoteBtn` to `ProfilePanel.lua`

**Files:**
- Modify: `UI/ProfilePanel.lua`

- [ ] **Step 1: Add the button widget in `CreateProfilePanel`**

In `UI:CreateProfilePanel`, find the Guild Note widget block:

```lua
    panel.guildNoteHdr,    panel.guildNoteLine    = MakeSectionHdr("Guild Note")
    panel.guildNoteFS = MakeFS()
```

Add the button on the next line:

```lua
    panel.guildNoteHdr,    panel.guildNoteLine    = MakeSectionHdr("Guild Note")
    panel.guildNoteFS = MakeFS()
    panel.editGuildNoteBtn = S:Button(content, "Edit Guild Note", PANEL_W - 30, 24)
```

- [ ] **Step 2: Wire `editGuildNoteBtn` into `Reflow`**

In `panel:Reflow()`, find the Guild Note section:

```lua
        -- Guild Note
        placeSection(self.guildNoteHdr, self.guildNoteLine)
        placeFS(self.guildNoteFS)
```

Change to:

```lua
        -- Guild Note
        placeSection(self.guildNoteHdr, self.guildNoteLine)
        placeFS(self.guildNoteFS)
        if self.editGuildNoteBtn:IsShown() then
            placeBtn(self.editGuildNoteBtn, 24)
        end
```

- [ ] **Step 3: Show/hide and wire the button in `ShowProfilePanel`**

In `UI:ShowProfilePanel`, find the guild note display:

```lua
    -- Guild note (WoW public note on this character)
    local guildNote = memberData.note or ""
    panel.guildNoteFS:SetText(
        guildNote ~= "" and guildNote or "|cff888888No guild note|r")
```

Add button visibility and click handler immediately after:

```lua
    -- Guild note (WoW public note on this character)
    local guildNote = memberData.note or ""
    panel.guildNoteFS:SetText(
        guildNote ~= "" and guildNote or "|cff888888No guild note|r")
    panel.editGuildNoteBtn:SetShown(GH:CanEditPublicNote())
    panel.editGuildNoteBtn:SetScript("OnClick", function()
        UI:ShowGuildNoteDialog(memberData)
    end)
```

- [ ] **Step 4: Verify in-game**

`/reload`. Click a guild member row to open the Profile Panel:
- As GM/officer with Edit Public Note permission: an "Edit Guild Note" button appears below the guild note text.
- As a rank without that permission: the button is absent and the Guild Note section flows normally.

- [ ] **Step 5: Commit**

```
git add UI/ProfilePanel.lua
git commit -m "feat: add Edit Guild Note button to Profile Panel"
```

---

### Task 5: Implement `ShowGuildNoteDialog`

**Files:**
- Modify: `UI/ProfilePanel.lua`

- [ ] **Step 1: Add `UI:ShowGuildNoteDialog` at the bottom of `ProfilePanel.lua`**

Append the following function after `UI:ShowAddAltDialog` (the last function in the file):

```lua
function UI:ShowGuildNoteDialog(member)
    local dlg = rawget(_G, "GuildHubGuildNoteDialog")
    if not dlg then
        dlg = CreateFrame("Frame", "GuildHubGuildNoteDialog", UIParent)
        dlg:SetSize(380, 145)
        dlg:SetFrameStrata("DIALOG")
        S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

        local title = S:FS(dlg, "OVERLAY", "normal")
        title:SetPoint("TOP", dlg, "TOP", 0, -12)
        title:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        dlg._title = title

        local subLabel = S:FS(dlg, "OVERLAY")
        subLabel:SetPoint("TOP", title, "BOTTOM", 0, -2)
        subLabel:SetText("Visible to all guild members")
        subLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        dlg._subLabel = subLabel

        local eb = S:EditBox(dlg, 300, 26, 31)
        eb:SetPoint("TOP", subLabel, "BOTTOM", 0, -8)
        dlg._eb = eb

        local counter = S:FS(dlg, "OVERLAY")
        counter:SetPoint("TOPRIGHT", eb, "BOTTOMRIGHT", 0, -2)
        counter:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        counter:SetText("0/31")
        dlg._counter = counter

        eb:SetScript("OnTextChanged", function(self)
            local len = #self:GetText()
            dlg._counter:SetText(len .. "/31")
            if len > 31 then
                dlg._counter:SetTextColor(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3])
            else
                dlg._counter:SetTextColor(
                    S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
            end
        end)

        local okBtn = S:Button(dlg, "Save", 80, 26)
        okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 10)
        dlg._okBtn = okBtn

        local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
        cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 10)
        cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    end

    dlg._title:SetText("Guild note for |cffffd700" .. member.name .. "|r")
    dlg._eb:SetText(member.note or "")
    dlg._eb:SetFocus()
    dlg._member = member

    local function Save()
        local note = dlg._eb:GetText():match("^%s*(.-)%s*$"):sub(1, 31)
        local m = dlg._member

        -- Re-fetch current rosterIndex in case roster order shifted since last refresh
        local fresh = GH.GuildData:FindMember(m.fullName)
        local idx = fresh and fresh.rosterIndex or m.rosterIndex

        local fn = rawget(_G, "GuildRosterSetPublicNote")
        if fn and idx then
            pcall(fn, idx, note)
            -- Optimistic local update so the UI reflects the new note immediately,
            -- before GUILD_ROSTER_UPDATE fires and GD:Refresh() overwrites it from server.
            if fresh then fresh.note = note end
        end

        -- Ask WoW to refresh the roster (fires GUILD_ROSTER_UPDATE → GD:Refresh)
        local rfn = rawget(_G, "GuildRoster")
        if rfn then rfn()
        elseif C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        end

        dlg:Hide()
        UI:RefreshMembersTab()

        -- Re-render profile panel if it is showing this member
        local pp = UI.ProfilePanel
        if pp and pp:IsShown() and pp.currentName == m.fullName then
            local target = GH.GuildData:FindMember(m.fullName)
            if target then UI:ShowProfilePanel(target) end
        end
    end

    dlg._okBtn:SetScript("OnClick", Save)
    dlg._eb:SetScript("OnEnterPressed", Save)

    dlg:SetPoint("CENTER")
    dlg:Show()
end
```

- [ ] **Step 2: Verify the dialog opens and saves correctly**

`/reload`. In the Members tab:
1. Right-click a member → click "Edit Guild Note". Confirm the dialog opens with the member's current note pre-filled and the title shows the correct name.
2. Type a note (stay under 31 chars). Hit Save. Confirm the dialog closes, the Note column in the roster updates, and the Profile Panel (if open) shows the new note.
3. Open the dialog again. Type more than 31 characters — confirm the counter turns red.
4. Type a note, hit Enter — confirm Save fires (same as clicking Save).
5. Open the dialog and click Cancel — confirm it closes without changing the note.

- [ ] **Step 3: Commit**

```
git add UI/ProfilePanel.lua
git commit -m "feat: add ShowGuildNoteDialog for in-addon guild note editing"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered by |
| --- | --- |
| `GH.PERM` constants table | Task 1 |
| `GH._rankFlags` cache keyed by rankIndex | Task 1 |
| `LoadRankPermissions` walks all ranks | Task 1 |
| `HasPermission` + GM special case | Task 1 |
| Registers for `GUILD_ROSTER_UPDATE` / `PLAYER_GUILD_UPDATE` | Task 1 |
| `GH.Permissions` in namespace block | Task 2 |
| `Permissions:Initialize()` called in `GH:Initialize()` | Task 2 |
| Remove `DetectOfficerThreshold` | Task 2 |
| Redefine `IsOfficer()` via `HasPermission` | Task 2 |
| Named wrappers (CanPromote, CanDemote, etc.) | Task 2 |
| TOC entry for `Permissions.lua` | Task 1 |
| Context menu: Promote → `CanPromote()` | Task 3 |
| Context menu: Demote → `CanDemote()` | Task 3 |
| Context menu: Kick → `CanRemoveMember()` | Task 3 |
| Context menu: Edit Guild Note → `CanEditPublicNote()` | Task 3 |
| `editGuildNoteBtn` widget in Profile Panel | Task 4 |
| `editGuildNoteBtn` in `Reflow` | Task 4 |
| Show/hide `editGuildNoteBtn` in `ShowProfilePanel` | Task 4 |
| `ShowGuildNoteDialog` with 31-char limit + counter | Task 5 |
| Calls `GuildRosterSetPublicNote` on save | Task 5 |
| Requests roster refresh after save | Task 5 |
| Re-renders profile panel after save | Task 5 |
| Out of scope: officer note UI | ✓ not implemented (wrappers added only) |

**No placeholder patterns found.** All steps contain actual code.

**Type consistency verified:** `member.rosterIndex`, `member.note`, `member.fullName`, `member.name` are all fields present on the member tables built in `GD:Refresh()`. `GH.GuildData:FindMember()` is defined in `GuildData.lua:444`. `UI:ShowGuildNoteDialog` is referenced in Tasks 3 and 4 and defined in Task 5 — ensure Tasks 3 and 4 are loaded before the dialog is ever invoked (it is, since the dialog is created lazily on first call).
