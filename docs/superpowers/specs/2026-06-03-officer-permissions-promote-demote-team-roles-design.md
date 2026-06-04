# GuildHub — Officer Permissions, Promote/Demote & Team Roles

**Date:** 2026-06-03

## Problem

Officers in the guild experience three broken or missing areas:

1. **Permissions too narrow** — `IsOfficer()` gates all officer features behind the `OFFICER_CHAT_SPEAK` flag. Officers whose rank has Promote/Demote/Invite/Remove but not officer chat are treated as regular members: custom notes are disabled, they can't manage team members, and officer-only UI is hidden.

2. **No guild rank editing** — There are no Promote/Demote buttons anywhere in GuildHub's UI. Officers must use the default WoW guild panel to change member ranks.

3. **No team role system** — Teams have a flat member list. Officers can't distinguish Roster from Bench from Trial. "Invite All Online" invites everyone regardless, so there's no way to mass-invite only the raid team.

## Goals

1. Widen the officer check so any rank with meaningful management permissions is recognised.
2. Add Promote/Demote buttons to the profile panel, respecting WoW's native rank flags.
3. Add team roles (Roster, Bench, Backup, Trial, Alt) visible only to officers/team managers.
4. Sync roles across all officers via a new `TMROL` addon message.
5. Replace "Invite All Online" with a role-filtered dropdown.

---

## Part 1 — Permissions Fix

### `Core.lua` — `GH:IsOfficer()`

Widen the primary flag check from `OFFICER_CHAT_SPEAK` alone to any of the meaningful management flags:

```lua
function GH:IsOfficer()
    if GH:IsGuildMaster() then return true end
    if next(GH._rankFlags) then
        return GH:HasPermission(GH.PERM.OFFICER_CHAT_SPEAK)
            or GH:HasPermission(GH.PERM.PROMOTE)
            or GH:HasPermission(GH.PERM.DEMOTE)
            or GH:HasPermission(GH.PERM.REMOVE)
    end
    -- existing fallbacks unchanged
    local canInvite = rawget(_G, "CanGuildInvite")
    if canInvite and canInvite() then return true end
    local canRemove = rawget(_G, "CanGuildRemove")
    if canRemove and canRemove() then return true end
    return false
end
```

No other call sites change. Everything gated on `IsOfficer()` — custom notes, team management, officer-only toolbar buttons — automatically unlocks for correctly permissioned officers.

---

## Part 2 — Promote/Demote Buttons

### Location

Added to `UI/ProfilePanel.lua` in the **Rank History** section, directly below `rankHistFS`. Two half-width buttons using the existing `bw` width variable (same pattern as Set Main / Add Alt).

### Widgets

```lua
panel.promoteBtn = S:Button(content, "Promote", bw, 24)
panel.demoteBtn  = S:DangerButton(content, "Demote", bw, 24)
```

### Visibility rules (evaluated in `ShowProfilePanel`)

- `panel.promoteBtn:SetShown(GH:CanGuildPromote(memberData.rankIndex) and memberData.fullName ~= GH:GetPlayerName())`
- `panel.demoteBtn:SetShown(GH:CanGuildDemote(memberData.rankIndex) and memberData.fullName ~= GH:GetPlayerName())`
- Hidden when viewing your own profile (can't self-promote/demote).

### On click

```lua
panel.promoteBtn:SetScript("OnClick", function()
    if memberData.rosterIndex then
        GuildRosterPromote(memberData.rosterIndex)
        C_GuildInfo.GuildRoster()
    end
end)
panel.demoteBtn:SetScript("OnClick", function()
    if memberData.rosterIndex then
        GuildRosterDemote(memberData.rosterIndex)
        C_GuildInfo.GuildRoster()
    end
end)
```

`GUILD_ROSTER_UPDATE` fires after `C_GuildInfo.GuildRoster()`, which triggers `GD:Refresh()` → `UI:RefreshMembersTab()`. The profile panel itself is re-rendered from the `OnClick` via a deferred `C_Timer.After(0.3, ...)` to give the server time to process the rank change.

### `Reflow()` placement

In the Rank History section of `Reflow()`, after `placeFS(self.rankHistFS)`:

```lua
if self.promoteBtn:IsShown() or self.demoteBtn:IsShown() then
    self.promoteBtn:ClearAllPoints()
    self.promoteBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 2)
    self.demoteBtn:ClearAllPoints()
    self.demoteBtn:SetPoint("LEFT", self.promoteBtn, "RIGHT", 4, 0)
    y = y - 30
end
```

---

## Part 3 — Team Roles

### Data Model

Each group record in the DB gains an optional `memberRoles` field:

```lua
g.memberRoles = {
    ["Cobalt"]   = "Roster",
    ["Darksassy"] = "Bench",
    ["Warrtag"]  = "Trial",
    -- nil entries = unassigned
}
```

Stored via `GH.DB:SaveGroup(id, g)` alongside existing fields. `memberRoles` defaults to `{}` if absent.

### Role values

The valid role strings are: `"Roster"`, `"Bench"`, `"Backup"`, `"Trial"`, `"Alt"`.  
`nil` / absent key = unassigned.

---

## Part 4 — `TMROL` Protocol

### New message type

Add constant at top of `GroupManager.lua` alongside existing `TM_INV`, `TM_OFC`, etc.:

```lua
local TM_ROL = "TMROL"
```

Message format:

```text
TMROL \30 groupId \30 memberName \30 role
```

- `role` is the role string, or `""` to clear.
- Sent via `Groups:_Send()` (subject to 250-char limit; always fits since groupId + name + role ≪ 250 chars).
- Handled in `Groups:OnAddonMessage()` using the `TM_ROL` constant.

### Sending (officer side)

New function in `GroupManager.lua`:

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
    local payload = table.concat({ "TMROL", groupId, memberName, role or "" }, "\30")
    Groups:_Send(payload)
    if GH.UI then GH.UI:RefreshTeamRoster(groupId) end
end
```

### Receiving (all clients)

In `Groups:OnAddonMessage()`, new branch:

```lua
elseif msgType == "TMROL" then
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

### Login sync

In `Groups:Initialize()`, the existing officer login sync (20s timer) is extended: after sending TMOFC for each team, also send one TMROL per member who has a non-nil role, staggered 200ms apart in the same delay loop.

### Member removal cleanup

In `Groups:RemoveMember()`, after removing the name from `g.members`, also clear `g.memberRoles[memberName]`.

---

## Part 5 — Roles UI

### Roster Sidebar (`UI/TeamsTab.lua` — `RefreshTeamRoster`)

Only rendered when `GH:CanManageTeam(groupId)` is true.

Each row in the roster sidebar (`rosterContent`) gains:

- A role badge `FontString` anchored to the right of the row (right-aligned, `-6` from the right edge).
- Badge text is the role string, or hidden if nil.
- Color per role:
  - Roster → `#4aaa4a` (green) on `#1a2e1a` background
  - Bench  → `#aaaa30` (yellow) on `#2e2a10`
  - Backup → `#7a9a7a` (muted green) on `#1a2e1a`
  - Trial  → `#cc6666` (red) on `#2e1a1a`
  - Alt    → `#6688aa` (blue) on `#1a1e2e`
- Name `FontString` right-edge point changes to `badge - 4px` when a badge is shown, preserving layout.

Each row registers an `OnMouseUp` (right-button) handler — if `CanManageTeam` and button is 2 (right-click), calls `UI:ShowTeamRoleMenu(groupId, memberName, row)`.

### Role context menu (`UI/TeamsTab.lua` — `ShowTeamRoleMenu`)

New function. Creates a small dropdown frame anchored to the clicked row:

```text
Set Role
──────────
● Roster
● Bench
● Backup
● Trial
● Alt
──────────
✕ Clear
```

Each item calls `GH.Groups:SetMemberRole(groupId, memberName, role)` and hides the menu. Clicking outside dismisses it via an `OnMouseDown` on `WorldFrame`.

### Invite dropdown (`UI/TeamsTab.lua` — `CreateTeamsTab`)

The existing `inviteBtn` label changes to `"Invite All Online ▾"`. Clicking it opens a dropdown frame anchored below the button. No split-button widget is needed — the whole button is the trigger.

Dropdown options (always shown; hardcoded to cover the most common raid-management cases):

```text
All online members
──────────────────
Roster only
Roster + Bench
Trial only
```

Each option calls `GH.Groups:InviteAll(selected, roles)` with the appropriate roles table (or `nil` for "All online members") and hides the dropdown. Clicking outside dismisses it via an `OnMouseDown` on `WorldFrame`.

`Groups:InviteAll(id)` gains an optional `roles` parameter — a table of role strings. When present, only members whose `g.memberRoles[name]` matches an entry in the table and are online get invited.

```lua
function Groups:InviteAll(id, roles)
    local g = GH.DB:GetGroups()[id]
    if not g then return end
    local myName = GH:GetPlayerName()
    local doInvite = InviteUnit or (C_PartyInfo and C_PartyInfo.InviteUnit)
    if not doInvite then return end
    for _, memberName in ipairs(g.members) do
        if memberName ~= myName then
            if not roles or (g.memberRoles and tContains(roles, g.memberRoles[memberName])) then
                local info = GH.GuildData:FindMember(memberName)
                if info and info.online then doInvite(info.fullName) end
            end
        end
    end
end
```

---

## Files Changed

| File | Change |
| --- | --- |
| `Core.lua` | Widen `IsOfficer()` |
| `UI/ProfilePanel.lua` | Add `promoteBtn`, `demoteBtn`; wire up `Reflow()` |
| `GroupManager.lua` | `SetMemberRole()`, `TMROL` handler, login sync, member removal cleanup |
| `UI/TeamsTab.lua` | Role badges in roster rows, `ShowTeamRoleMenu()`, invite dropdown |

## Out of Scope

- Roles visible to non-officer team members.
- Per-guild custom role names.
- Role history / audit log.
- Role display in the Members tab team column.
