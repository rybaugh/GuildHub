# Communities Tab — Design Spec
**Date:** 2026-05-27
**Status:** Approved

## Problem

GuildHub replaces the WoW Guild window, but the WoW Guild & Communities window also surfaces non-guild communities the player belongs to. Players currently have to open the default WoW window just to see their communities. This spec adds a Communities tab to GuildHub covering member rosters, chat, and a community finder.

---

## Scope

- View all subscribed non-guild communities in GuildHub
- Per-community: member roster (with online status, class color, role, zone) and chat (history + send)
- Community Finder: search existing communities and apply; create a new community
- WoW 12.x API only (`C_Club.*`, `C_ClubFinder.*`, `Enum.ClubType`, `Enum.ClubMemberPresence`)

Out of scope for v1:
- Multi-stream (channel) support within a community
- Per-community settings or notifications
- Community management (kick, ban, promote)

---

## Architecture

### New files

**`CommunityData.lua`**
Registered as `GH.Communities`. Wraps all `C_Club` and `C_ClubFinder` API calls. The UI never calls WoW APIs directly.

**`UI/CommunitiesTab.lua`**
All Communities tab UI — selector bar, roster panel, chat panel, finder panel.

### Modified files

| File | Change |
|---|---|
| `GuildHub.toc` | Add `CommunityData.lua` and `UI/CommunitiesTab.lua` |
| `Core.lua` | Add `GH.Communities = GH.Communities or {}`, call `self.Communities:Initialize()` |
| `UI/MainWindow.lua` | Add `"Communities"` to `TABS`; hide nav button when `C_Club` is nil or player has zero non-guild communities; add Communities tab to `CreateMainWindow` call list |

---

## Data Layer — `CommunityData.lua`

### Public API

```lua
GH.Communities:GetAll()
-- Returns array of ClubInfo tables for non-guild clubs only.
-- Filter: club.clubType ~= Enum.ClubType.Guild
-- Source: C_Club.GetSubscribedClubs()

GH.Communities:GetMembers(clubId)
-- Returns array of ClubMemberInfo from C_Club.GetClubMembers(clubId).
-- Sorted: online-first (Enum.ClubMemberPresence check), then alphabetically by name.

GH.Communities:GetStream(clubId)
-- Returns the first stream from C_Club.GetStreams(clubId) (the General stream).
-- Returns nil if no streams exist; callers must guard against nil.

GH.Communities:GetMessages(clubId, streamId)
-- Returns message array from C_Club.GetMessageHistory(clubId, streamId, nil, 50).

GH.Communities:RequestOlderMessages(clubId, streamId, oldestMessageId)
-- Calls C_Club.RequestMoreMessagesBefore(clubId, streamId, oldestMessageId, 25).

GH.Communities:SendMessage(clubId, streamId, text)
-- Calls C_Club.SendMessage(clubId, streamId, text).

GH.Communities:MarkRead(clubId, streamId)
-- Calls C_Club.AdvanceStreamViewMarker(clubId, streamId).

GH.Communities:CreateCommunity(name, shortName, description, avatarId, clubType)
-- Calls C_Club.CreateClub(...). clubType defaults to Enum.ClubType.BattleNet.

GH.Communities:SearchFinder(searchTerm)
-- Calls C_ClubFinder.SearchClubs(searchTerm, ...) with default filters.

GH.Communities:ApplyToClub(clubFinderGUID, comment)
-- Calls C_ClubFinder.ApplyToClub(clubFinderGUID, comment).
```

### Online presence helper

```lua
-- Returns true for any presence that means "online"
local ONLINE_PRESENCES = {
    [Enum.ClubMemberPresence.Online]       = true,
    [Enum.ClubMemberPresence.OnlineMobile] = true,
    [Enum.ClubMemberPresence.Away]         = true,
    [Enum.ClubMemberPresence.Busy]         = true,
}
function GH.Communities:IsOnline(presence)
    return ONLINE_PRESENCES[presence] == true
end
```

### Events registered in `Initialize()`

| WoW Event | Handler action |
|---|---|
| `CLUB_ADDED` | Rebuild tab bar; re-evaluate nav button visibility |
| `CLUB_REMOVED` | Rebuild tab bar; if active club removed, select first remaining |
| `CLUB_UPDATED` | Rebuild tab bar labels |
| `CLUB_ROSTER_UPDATE` | Refresh roster panel if Communities tab is active |
| `CLUB_MEMBER_ADDED` / `CLUB_MEMBER_REMOVED` / `CLUB_MEMBER_UPDATED` | Refresh roster panel |
| `CLUB_MESSAGE_ADDED` | Append message to chat panel if matching community is active |
| `CLUB_MESSAGE_HISTORY_RECEIVED` | Populate / prepend chat history |
| `CLUB_FINDER_CLUBS_LOADED` | Populate finder results list |

---

## UI — `UI/CommunitiesTab.lua`

### Tab frame

`UI:CreateCommunitiesTab(parent, contentW, contentH)` — mirrors existing `CreateMembersTab`, `CreateChatTab` patterns. Stores reference as `UI.CommunitiesTab`.

`UI:RefreshCommunitiesTab()` — called on tab switch and by data-layer event callbacks.

### Community selector bar

- Fixed-height strip (~36px) at the top of the tab content area.
- One button per club in `GH.Communities:GetAll()`. Active button highlighted with `S.COLOR.ACCENT`.
- If buttons overflow horizontally: left/right arrow scroll buttons appear on each side (hide when not needed). Scroll is pixel-based, not page-based.
- **"Find a Community"** button pinned to the right end of the bar, visually separated by a 1px divider.
- When zero non-guild communities exist: bar is hidden; a centered message is shown — *"You are not a member of any communities."* — with the "Find a Community" button below it.
- Clicking a community button: sets `_activeCommunity = {clubId, streamId}`, refreshes roster + chat panels, closes Finder if open.
- Clicking "Find a Community": hides roster+chat, shows Finder panel.

### Roster panel (left ~35%)

- **Header:** Community name + `"X members, Y online"` badge.
- **Scroll list:** One row per member from `GH.Communities:GetMembers(clubId)`.
  - Online dot: green (`S.COLOR.ONLINE`) if `GH.Communities:IsOnline(presence)`, grey otherwise.
  - Name: colored by class using `GH.GuildData:GetClassColor(classId)` — `ClubMemberInfo.classID` maps to a class file name via `C_CreatureInfo.GetClassInfo(classID).classFile`.
  - Level: `ClubMemberInfo.level`
  - Role: `ClubMemberInfo.role` (Leader / Moderator / Member)
  - Zone: `ClubMemberInfo.zone`
- No search box in v1.
- Uses a local row pool defined in `CommunitiesTab.lua` (reuse row frames, hide extras) — not shared with the pool in `MembersTab.lua`.

### Chat panel (right ~65%)

- **Message scroll area** (fills panel minus input bar height):
  - Messages from `GH.Communities:GetMessages(clubId, streamId)`, newest at bottom.
  - Each row: `[HH:MM]  Name: message text`. Name is class-colored where info is available.
  - Scroll-to-top triggers `GH.Communities:RequestOlderMessages(...)` and prepends results on `CLUB_MESSAGE_HISTORY_RECEIVED`.
  - `GH.Communities:MarkRead(clubId, streamId)` called when the Communities tab becomes visible.
- **Input bar** (fixed ~30px at bottom):
  - `S:EditBox` matching Chat tab style.
  - Placeholder: `"Message [community name]…"`
  - Enter or "Send" button calls `GH.Communities:SendMessage(clubId, streamId, text)` then clears the box.

### Finder panel (full main area, shown instead of roster+chat)

- **"← Back"** button top-left — hides Finder, restores last active community view.
- **Search bar** + **"Search"** button — calls `GH.Communities:SearchFinder(term)`. Results populate on `CLUB_FINDER_CLUBS_LOADED`.
- **"Create Community"** button to the right of the search bar — opens a minimal dialog (`GuildHubCreateCommunityDialog`): name field, short-name field, description field, type dropdown (BattleNet / Character), Confirm/Cancel. Confirm calls `GH.Communities:CreateCommunity(...)`.
- **Results scroll list:**
  - Each row: community name, member count, truncated description.
  - Clicking a row expands it inline to show full description + **"Apply"** button.
  - "Apply" opens a single-line comment input inline, then calls `GH.Communities:ApplyToClub(guid, comment)`.

---

## Nav button visibility logic

The nav button is shown whenever `C_Club` is available — even when the player has zero non-guild communities. This ensures the player can always reach the Finder to discover and join communities. The empty-state message and Finder button inside the tab handle the zero-communities case.

```lua
local function ShouldShowCommunitiesTab()
    return C_Club ~= nil and C_Club.GetSubscribedClubs ~= nil
end
```

Called once on load. If `C_Club` is absent (Classic guard), the nav button is hidden permanently. Falling back to the Members tab only happens if Communities is the active tab when `C_Club` becomes unavailable (an edge case — safe to ignore for now).

---

## Styling

Follows existing `GH.Styles` patterns throughout — no new colors or font sizes introduced. Roster row height and column layout match the Members tab proportionally. Chat panel matches the Chat tab's message area.

---

## Out of scope (v1)

- Multiple streams / channels per community
- Community management actions (kick, ban, promote, demote)
- Per-community unread badge on the nav button
- Community events integration
