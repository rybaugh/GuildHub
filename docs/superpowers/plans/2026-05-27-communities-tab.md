# Communities Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Communities tab to GuildHub showing the player's non-guild communities with per-community member roster, live chat, and a community finder/creator — all using WoW 12.x APIs.

**Architecture:** `CommunityData.lua` wraps all `C_Club`/`C_ClubFinder` calls and fires UI callbacks on `CLUB_*` events. `UI/CommunitiesTab.lua` owns the full tab UI — selector bar, roster panel, chat panel, and finder panel. `MainWindow.lua` registers the new tab; `Core.lua` initializes the module.

**Tech Stack:** Lua, WoW 12.x AddOn API (`C_Club`, `C_ClubFinder`, `Enum.ClubType`, `Enum.ClubMemberPresence`, `Enum.ClubRoleIdentifier`, `C_CreatureInfo`), GuildHub `GH.Styles` system.

---

### Task 1: CommunityData module

**Files:**
- Create: `CommunityData.lua`

- [ ] **Step 1: Create `CommunityData.lua` with the full data layer**

```lua
-- GuildHub - CommunityData
-- Wraps C_Club and C_ClubFinder APIs. UI never calls WoW APIs directly.

local GH = GuildHub
local CD = GH.Communities

-- Presence values that count as "online" in WoW 12.x
local ONLINE_PRESENCES = {}
if Enum and Enum.ClubMemberPresence then
    ONLINE_PRESENCES[Enum.ClubMemberPresence.Online]       = true
    ONLINE_PRESENCES[Enum.ClubMemberPresence.OnlineMobile] = true
    ONLINE_PRESENCES[Enum.ClubMemberPresence.Away]         = true
    ONLINE_PRESENCES[Enum.ClubMemberPresence.Busy]         = true
end

function CD:IsOnline(presence)
    return ONLINE_PRESENCES[presence] == true
end

-- Returns all subscribed non-guild communities.
function CD:GetAll()
    if not (C_Club and C_Club.GetSubscribedClubs) then return {} end
    local clubs = C_Club.GetSubscribedClubs() or {}
    local out = {}
    for _, club in ipairs(clubs) do
        if club.clubType ~= Enum.ClubType.Guild then
            out[#out + 1] = club
        end
    end
    return out
end

-- Returns members of a community, sorted online-first then alphabetically.
function CD:GetMembers(clubId)
    if not (C_Club and C_Club.GetClubMembers) then return {} end
    local ok, members = pcall(C_Club.GetClubMembers, clubId)
    if not ok or not members then return {} end
    table.sort(members, function(a, b)
        local aOn = CD:IsOnline(a.presence)
        local bOn = CD:IsOnline(b.presence)
        if aOn ~= bOn then return aOn end
        return (a.name or "") < (b.name or "")
    end)
    return members
end

-- Returns the first (General) stream for a community, or nil if none.
function CD:GetStream(clubId)
    if not (C_Club and C_Club.GetStreams) then return nil end
    local ok, streams = pcall(C_Club.GetStreams, clubId)
    if not ok or not streams or #streams == 0 then return nil end
    return streams[1]
end

-- Returns up to 50 most-recent messages. Returns empty table on failure.
function CD:GetMessages(clubId, streamId)
    if not (C_Club and C_Club.GetMessageHistory) then return {} end
    local ok, result = pcall(C_Club.GetMessageHistory, clubId, streamId, nil, 50)
    if not ok or type(result) ~= "table" then return {} end
    return result.messages or {}
end

-- Requests 25 messages older than oldestMessageId. Results arrive via
-- CLUB_MESSAGE_HISTORY_RECEIVED -> UI:OnCommunityHistoryReceived.
function CD:RequestOlderMessages(clubId, streamId, oldestMessageId)
    if not (C_Club and C_Club.RequestMoreMessagesBefore) then return end
    pcall(C_Club.RequestMoreMessagesBefore, clubId, streamId, oldestMessageId, 25)
end

-- Sends a message to the active community stream.
function CD:SendMessage(clubId, streamId, text)
    if not (C_Club and C_Club.SendMessage) then return end
    if not text or text:match("^%s*$") then return end
    pcall(C_Club.SendMessage, clubId, streamId, text)
end

-- Marks all messages in the stream as read.
function CD:MarkRead(clubId, streamId)
    if not (C_Club and C_Club.AdvanceStreamViewMarker) then return end
    pcall(C_Club.AdvanceStreamViewMarker, clubId, streamId)
end

-- Initiates a community search. Results arrive via CLUB_FINDER_CLUBS_LOADED.
function CD:SearchFinder(searchTerm)
    if not (C_ClubFinder and C_ClubFinder.SearchClubs) then return end
    -- Parameters: searchTerm, clubType, locale, ageRating, language,
    --   minLevel, maxLevel, minMemberCount, maxMemberCount, playstyle, characteristics
    pcall(C_ClubFinder.SearchClubs, searchTerm, Enum.ClubType.BattleNet,
          GetLocale(), 0, "", 0, 0, 0, 0, 0, 0)
end

-- Caches finder results after CLUB_FINDER_CLUBS_LOADED fires.
-- Returns cached array of ClubFinderCandidateClubData.
function CD:CacheFinderResults()
    if not (C_ClubFinder and C_ClubFinder.GetRecruitingClubs) then
        self._finderResults = {}
        return {}
    end
    local ok, results = pcall(C_ClubFinder.GetRecruitingClubs, 0, 50)
    self._finderResults = (ok and type(results) == "table") and results or {}
    return self._finderResults
end

-- Submits an application to a club found via the finder.
function CD:ApplyToClub(clubFinderGUID, comment)
    if not (C_ClubFinder and C_ClubFinder.ApplyToClub) then return end
    pcall(C_ClubFinder.ApplyToClub, clubFinderGUID, comment or "")
end

-- Creates a new BattleNet community.
function CD:CreateCommunity(name, shortName, description)
    if not (C_Club and C_Club.CreateClub) then return end
    pcall(C_Club.CreateClub, name, shortName or "", description or "",
          0, Enum.ClubType.BattleNet)
end

function CD:Initialize()
    if not C_Club then return end   -- guard: Classic / API not present
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CLUB_ADDED")
    frame:RegisterEvent("CLUB_REMOVED")
    frame:RegisterEvent("CLUB_UPDATED")
    frame:RegisterEvent("CLUB_ROSTER_UPDATE")
    frame:RegisterEvent("CLUB_MEMBER_ADDED")
    frame:RegisterEvent("CLUB_MEMBER_REMOVED")
    frame:RegisterEvent("CLUB_MEMBER_UPDATED")
    frame:RegisterEvent("CLUB_MESSAGE_ADDED")
    frame:RegisterEvent("CLUB_MESSAGE_HISTORY_RECEIVED")
    frame:RegisterEvent("CLUB_FINDER_CLUBS_LOADED")
    frame:SetScript("OnEvent", function(_, event, ...)
        CD:OnEvent(event, ...)
    end)
    CD.eventFrame = frame
end

function CD:OnEvent(event, ...)
    if event == "CLUB_ADDED" or event == "CLUB_REMOVED" or event == "CLUB_UPDATED" then
        if GH.UI and GH.UI.OnCommunitiesChanged then
            GH.UI:OnCommunitiesChanged(event)
        end
    elseif event == "CLUB_ROSTER_UPDATE"   or event == "CLUB_MEMBER_ADDED"
        or event == "CLUB_MEMBER_REMOVED"  or event == "CLUB_MEMBER_UPDATED" then
        if GH.UI and GH.UI.OnCommunityRosterUpdate then
            GH.UI:OnCommunityRosterUpdate(...)
        end
    elseif event == "CLUB_MESSAGE_ADDED" then
        if GH.UI and GH.UI.OnCommunityMessageAdded then
            GH.UI:OnCommunityMessageAdded(...)
        end
    elseif event == "CLUB_MESSAGE_HISTORY_RECEIVED" then
        if GH.UI and GH.UI.OnCommunityHistoryReceived then
            GH.UI:OnCommunityHistoryReceived(...)
        end
    elseif event == "CLUB_FINDER_CLUBS_LOADED" then
        CD:CacheFinderResults()
        if GH.UI and GH.UI.OnClubFinderLoaded then
            GH.UI:OnClubFinderLoaded()
        end
    end
end
```

- [ ] **Step 2: Verify file loads cleanly**

`/reload` in WoW. If the file isn't wired yet, no error is expected — this step is just confirming the file content is syntactically valid by checking the Lua error frame after the next task wires it in.

---

### Task 2: Wire module into the project

**Files:**
- Modify: `GuildHub.toc`
- Modify: `Core.lua`
- Modify: `UI/MainWindow.lua`

- [ ] **Step 1: Add new files to `GuildHub.toc`**

Add `CommunityData.lua` after `ActivityLog.lua` (before UI files) and `UI/CommunitiesTab.lua` after `UI/ActivityTab.lua`:

```
## After ActivityLog.lua, add:
CommunityData.lua

## After UI/ActivityTab.lua, add:
UI/CommunitiesTab.lua
```

The full load order for the new entries:
```
ActivityLog.lua
CommunityData.lua        ← ADD
UI/Styles.lua
UI/MainWindow.lua
UI/TeamsTab.lua
UI/MembersTab.lua
UI/EventsTab.lua
UI/RecruitTab.lua
UI/GuildRecruitTab.lua
UI/ChatTab.lua
UI/ActivityTab.lua
UI/CommunitiesTab.lua    ← ADD
UI/ProfilePanel.lua
...
```

- [ ] **Step 2: Initialize `GH.Communities` in `Core.lua`**

In `Core.lua`, add the table declaration alongside the existing module tables (around line 11):

```lua
GH.Communities = GH.Communities or {}
```

In `GH:Initialize()` (around line 37, before `self.UI:Initialize()`):

```lua
self.Communities:Initialize()
```

- [ ] **Step 3: Add Communities to the tab list in `UI/MainWindow.lua`**

At line 8, change the `TABS` table:

```lua
local TABS = { "Members", "Activity", "Chat", "Teams", "Events", "LFM", "Recruit", "Communities" }
```

- [ ] **Step 4: Add nav button guard for Communities in the TABS loop**

Inside the `for i, tabName in ipairs(TABS) do` loop (around line 421), after the existing `"Recruit"` guard, add:

```lua
-- Communities tab hidden when C_Club API is unavailable (Classic guard)
if tabName == "Communities" and not (C_Club and C_Club.GetSubscribedClubs) then
    nb:Hide()
end
```

- [ ] **Step 5: Wire tab click refresh for Communities**

In the same loop's `OnClick` handler (around line 483), add:

```lua
if tabName == "Communities" then UI:RefreshCommunitiesTab() end
```

- [ ] **Step 6: Add `CreateCommunitiesTab` call after the other tab creations**

Around line 652, after `UI:CreateGuildRecruitTab(content, contentW)`, add:

```lua
UI:CreateCommunitiesTab(content, contentW, contentH)
```

- [ ] **Step 7: Add Communities dialog to the OnHide orphan cleanup list**

In the `win:SetScript("OnHide", ...)` block (around line 42), add to the `orphans` table:

```lua
"GuildHubCreateCommunityDialog",
```

- [ ] **Step 8: Reload and verify no errors**

`/reload` in WoW. Open GuildHub (`/gh`). Confirm:
- No Lua errors in chat
- "Communities" nav button appears in the sidebar (if C_Club is available)
- Clicking it does not throw (tab frame will be blank — `CreateCommunitiesTab` doesn't exist yet)

---

### Task 3: CommunitiesTab shell, selector bar, and empty state

**Files:**
- Create: `UI/CommunitiesTab.lua`

- [ ] **Step 1: Create `UI/CommunitiesTab.lua` with the frame shell, selector bar, and empty state**

```lua
-- GuildHub - CommunitiesTab
-- Selector bar, roster panel, chat panel, and finder panel for communities.

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local BAR_H  = 38    -- selector bar height
local INP_H  = 46    -- chat input bar height
local ROST_W = 280   -- roster panel fixed width

-- Module-level state
local _activeClubId   = nil
local _activeStreamId = nil
local _tabBtns        = {}   -- array of {btn, clubId}
local _tabScrollX     = 0

local ROLE_LABELS = {}
if Enum and Enum.ClubRoleIdentifier then
    ROLE_LABELS[Enum.ClubRoleIdentifier.Owner]     = "Owner"
    ROLE_LABELS[Enum.ClubRoleIdentifier.Leader]    = "Leader"
    ROLE_LABELS[Enum.ClubRoleIdentifier.Moderator] = "Moderator"
    ROLE_LABELS[Enum.ClubRoleIdentifier.Member]    = "Member"
end

-- ── Helper: class color from classID (C_CreatureInfo, WoW 12.x) ──────────────
local function ClassColorFromId(classID)
    if not classID or classID == 0 then return 0.8, 0.8, 0.8 end
    local ok, info = pcall(C_CreatureInfo.GetClassInfo, classID)
    if ok and info and info.classFile then
        return GH.GuildData:GetClassColor(info.classFile)
    end
    return 0.8, 0.8, 0.8
end

-- ── Main creation ─────────────────────────────────────────────────────────────

function UI:CreateCommunitiesTab(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.CommunitiesTab = frame

    -- ── Selector bar ──────────────────────────────────────────────────────────
    local selectorBar = CreateFrame("Frame", nil, frame)
    selectorBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    selectorBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    selectorBar:SetHeight(BAR_H)
    S:GradientBg(selectorBar, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL_HDR_B[1], S.COLOR.PANEL_HDR_B[2], S.COLOR.PANEL_HDR_B[3], 1)

    local barDiv = selectorBar:CreateTexture(nil, "ARTWORK")
    barDiv:SetPoint("BOTTOMLEFT",  selectorBar, "BOTTOMLEFT")
    barDiv:SetPoint("BOTTOMRIGHT", selectorBar, "BOTTOMRIGHT")
    barDiv:SetHeight(1)
    barDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
    frame.selectorBar = selectorBar

    -- "Find a Community" button — pinned to right
    local findBtn = S:Button(selectorBar, "Find a Community", 130, 26)
    findBtn:SetPoint("RIGHT", selectorBar, "RIGHT", -8, 0)
    findBtn:SetScript("OnClick", function() UI:ShowCommunityFinder() end)
    frame.findBtn = findBtn

    -- Divider left of "Find" button
    local findDiv = selectorBar:CreateTexture(nil, "ARTWORK")
    findDiv:SetSize(1, BAR_H - 10)
    findDiv:SetPoint("RIGHT", findBtn, "LEFT", -8, 0)
    findDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

    -- Clipping region for community tab buttons (excludes "Find" button area)
    local tabClip = CreateFrame("Frame", nil, selectorBar)
    tabClip:SetPoint("TOPLEFT",  selectorBar, "TOPLEFT",  24, 0)
    tabClip:SetPoint("TOPRIGHT", findDiv, "TOPLEFT", -4, 0)
    tabClip:SetHeight(BAR_H)
    tabClip:SetClipsChildren(true)
    frame.tabClip = tabClip

    -- Scrollable inner frame for tab buttons
    local tabInner = CreateFrame("Frame", nil, tabClip)
    tabInner:SetHeight(BAR_H)
    tabInner:SetWidth(4000)
    tabInner:SetPoint("TOPLEFT", tabClip, "TOPLEFT", 0, 0)
    frame.tabInner = tabInner

    -- Left scroll arrow
    local leftArrow = CreateFrame("Button", nil, selectorBar)
    leftArrow:SetSize(22, BAR_H)
    leftArrow:SetPoint("LEFT", selectorBar, "LEFT", 0, 0)
    local leftTex = leftArrow:CreateTexture(nil, "ARTWORK")
    leftTex:SetAllPoints()
    leftTex:SetTexture("Interface/Buttons/Arrow-Left-Up")
    leftTex:SetAlpha(0.7)
    leftArrow:Hide()
    frame.leftArrow = leftArrow

    -- Right scroll arrow
    local rightArrow = CreateFrame("Button", nil, selectorBar)
    rightArrow:SetSize(22, BAR_H)
    rightArrow:SetPoint("RIGHT", findDiv, "LEFT", -4, 0)
    local rightTex = rightArrow:CreateTexture(nil, "ARTWORK")
    rightTex:SetAllPoints()
    rightTex:SetTexture("Interface/Buttons/Arrow-Right-Up")
    rightTex:SetAlpha(0.7)
    rightArrow:Hide()
    frame.rightArrow = rightArrow

    local SCROLL_STEP = 80
    leftArrow:SetScript("OnClick", function()
        _tabScrollX = math.max(0, _tabScrollX - SCROLL_STEP)
        UI:_UpdateCommTabScroll()
    end)
    rightArrow:SetScript("OnClick", function()
        _tabScrollX = _tabScrollX + SCROLL_STEP
        UI:_UpdateCommTabScroll()
    end)

    -- ── Main area (below selector bar) ───────────────────────────────────────
    local mainArea = CreateFrame("Frame", nil, frame)
    mainArea:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, -BAR_H)
    mainArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.mainArea = mainArea

    -- Empty state (shown when player has no communities)
    local emptyFS = S:FS(mainArea, "OVERLAY", "normal")
    emptyFS:SetPoint("CENTER", mainArea, "CENTER", 0, 20)
    emptyFS:SetText("You are not a member of any communities.")
    emptyFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    emptyFS:Hide()
    frame.emptyFS = emptyFS

    local emptyFindBtn = S:Button(mainArea, "Find a Community", 150, 28)
    emptyFindBtn:SetPoint("TOP", emptyFS, "BOTTOM", 0, -10)
    emptyFindBtn:SetScript("OnClick", function() UI:ShowCommunityFinder() end)
    emptyFindBtn:Hide()
    frame.emptyFindBtn = emptyFindBtn

    -- Sub-panels created in subsequent tasks
    UI:_CreateCommunityRosterPanel(mainArea)
    UI:_CreateCommunityChatPanel(mainArea)
    UI:_CreateCommunityFinderPanel(mainArea)

    -- Vertical divider between roster and chat
    local splitDiv = mainArea:CreateTexture(nil, "ARTWORK")
    splitDiv:SetWidth(1)
    splitDiv:SetPoint("TOPLEFT",    mainArea, "TOPLEFT",    ROST_W, 0)
    splitDiv:SetPoint("BOTTOMLEFT", mainArea, "BOTTOMLEFT", ROST_W, 0)
    splitDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
    frame.splitDiv = splitDiv   -- referenced by ShowCommunityFinder / _HideCommunityFinder
end

-- ── Selector bar helpers ──────────────────────────────────────────────────────

function UI:_UpdateCommTabScroll()
    local frame    = UI.CommunitiesTab
    local tabInner = frame and frame.tabInner
    if not tabInner then return end
    local clipW    = frame.tabClip:GetWidth()
    local innerW   = 0
    for _, entry in ipairs(_tabBtns) do
        innerW = innerW + entry.btn:GetWidth() + 4
    end
    _tabScrollX = math.max(0, math.min(_tabScrollX, math.max(0, innerW - clipW)))
    tabInner:ClearAllPoints()
    tabInner:SetPoint("TOPLEFT", frame.tabClip, "TOPLEFT", -_tabScrollX, 0)
    frame.leftArrow:SetShown(_tabScrollX > 0)
    frame.rightArrow:SetShown(innerW > clipW and _tabScrollX < innerW - clipW)
end

function UI:_RebuildSelectorBar()
    local frame = UI.CommunitiesTab
    if not frame then return end
    -- Release existing tab buttons
    for _, entry in ipairs(_tabBtns) do
        entry.btn:Hide()
        entry.btn:SetParent(nil)
    end
    _tabBtns  = {}
    _tabScrollX = 0

    local clubs = GH.Communities:GetAll()
    local xOff  = 0
    for _, club in ipairs(clubs) do
        local label = club.name or "Community"
        local btn   = S:Button(frame.tabInner, label, math.max(80, #label * 7 + 16), 26)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", frame.tabInner, "LEFT", xOff, 0)
        xOff = xOff + btn:GetWidth() + 4
        local capturedId = club.clubId
        btn:SetScript("OnClick", function()
            UI:_SelectCommunity(capturedId)
        end)
        _tabBtns[#_tabBtns + 1] = { btn = btn, clubId = club.clubId }
    end

    -- Show empty state when no communities
    local hasClubs = #clubs > 0
    frame.emptyFS:SetShown(not hasClubs)
    frame.emptyFindBtn:SetShown(not hasClubs)

    -- Auto-select first community if none active or active no longer exists
    local found = false
    for _, entry in ipairs(_tabBtns) do
        if entry.clubId == _activeClubId then found = true break end
    end
    if not found and #_tabBtns > 0 then
        _activeClubId = _tabBtns[1].clubId
    elseif #_tabBtns == 0 then
        _activeClubId = nil
    end

    UI:_RefreshSelectorHighlight()
    UI:_UpdateCommTabScroll()
end

function UI:_RefreshSelectorHighlight()
    for _, entry in ipairs(_tabBtns) do
        local isActive = entry.clubId == _activeClubId
        if entry.btn.bg then
            entry.btn.bg:SetColorTexture(
                isActive and S.COLOR.ACCENT[1] or S.COLOR.PANEL[1],
                isActive and S.COLOR.ACCENT[2] or S.COLOR.PANEL[2],
                isActive and S.COLOR.ACCENT[3] or S.COLOR.PANEL[3], 0.9)
        end
    end
end

function UI:_SelectCommunity(clubId)
    _activeClubId   = clubId
    local stream    = GH.Communities:GetStream(clubId)
    _activeStreamId = stream and stream.streamId or nil
    UI:_RefreshSelectorHighlight()
    UI:_RefreshCommunityRoster()
    UI:_RefreshCommunityChat()
    UI:_HideCommunityFinder()
    if _activeClubId and _activeStreamId then
        GH.Communities:MarkRead(_activeClubId, _activeStreamId)
    end
end

-- ── Public entry points ───────────────────────────────────────────────────────

function UI:RefreshCommunitiesTab()
    UI:_RebuildSelectorBar()
    if _activeClubId then
        UI:_SelectCommunity(_activeClubId)
    end
end

-- Event callbacks (called by CommunityData:OnEvent)
function UI:OnCommunitiesChanged(_event)
    if not UI.CommunitiesTab or not UI.CommunitiesTab:IsShown() then return end
    UI:_RebuildSelectorBar()
    if _activeClubId then UI:_SelectCommunity(_activeClubId) end
end

function UI:OnCommunityRosterUpdate(clubId)
    if clubId ~= _activeClubId then return end
    if not UI.CommunitiesTab or not UI.CommunitiesTab:IsShown() then return end
    UI:_RefreshCommunityRoster()
end

function UI:OnCommunityMessageAdded(clubId, streamId, _messageId)
    if clubId ~= _activeClubId or streamId ~= _activeStreamId then return end
    if not UI.CommunitiesTab or not UI.CommunitiesTab:IsShown() then return end
    UI:_RefreshCommunityChat()
end

function UI:OnCommunityHistoryReceived(clubId, streamId)
    if clubId ~= _activeClubId or streamId ~= _activeStreamId then return end
    if not UI.CommunitiesTab or not UI.CommunitiesTab:IsShown() then return end
    UI:_RefreshCommunityChat()
end

function UI:OnClubFinderLoaded()
    if not UI.CommunitiesTab or not UI.CommunitiesTab:IsShown() then return end
    UI:_PopulateFinderResults()
end

-- Stub implementations for panels (filled in Tasks 4–6)
function UI:_CreateCommunityRosterPanel(_parent) end
function UI:_CreateCommunityChatPanel(_parent)   end
function UI:_CreateCommunityFinderPanel(_parent) end
function UI:_RefreshCommunityRoster()            end
function UI:_RefreshCommunityChat()              end
function UI:_HideCommunityFinder()               end
function UI:ShowCommunityFinder()                end
function UI:_PopulateFinderResults()             end
```

- [ ] **Step 2: Reload and verify**

`/reload` → `/gh` → click Communities. Confirm:
- No Lua errors
- Selector bar renders with community name buttons (or empty state if none)
- "Find a Community" button visible at right of bar
- Left/right scroll arrows appear only when buttons overflow

- [ ] **Step 3: Commit**

```
git add UI/CommunitiesTab.lua
git commit -m "feat: add Communities tab shell and selector bar"
```

---

### Task 4: Roster panel

**Files:**
- Modify: `UI/CommunitiesTab.lua` (replace stubs `_CreateCommunityRosterPanel` and `_RefreshCommunityRoster`)

- [ ] **Step 1: Replace the roster panel stub with the full implementation**

Remove the two stub functions and add the following:

```lua
-- ── Roster panel ─────────────────────────────────────────────────────────────

local _rosterPool       = {}
local _rosterActiveRows = {}

local function AcquireRosterRow(parent)
    local row = table.remove(_rosterPool)
    if row then row:SetParent(parent); return row end

    row = CreateFrame("Frame", nil, parent)
    row:SetHeight(S.ROW_H)

    -- Alternating stripe background
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    row.stripe = stripe

    -- Online dot
    local dot = row:CreateTexture(nil, "ARTWORK")
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.dot = dot

    -- Name
    local nameFS = S:FS(row, "OVERLAY", "normal")
    nameFS:SetPoint("LEFT",  row, "LEFT",  22, 0)
    nameFS:SetWidth(110)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    row.nameFS = nameFS

    -- Level
    local lvlFS = S:FS(row, "OVERLAY")
    lvlFS:SetPoint("LEFT", row, "LEFT", 136, 0)
    lvlFS:SetWidth(30)
    lvlFS:SetJustifyH("LEFT")
    row.lvlFS = lvlFS

    -- Role
    local roleFS = S:FS(row, "OVERLAY")
    roleFS:SetPoint("LEFT", row, "LEFT", 170, 0)
    roleFS:SetWidth(78)
    roleFS:SetJustifyH("LEFT")
    row.roleFS = roleFS

    -- Zone
    local zoneFS = S:FS(row, "OVERLAY")
    zoneFS:SetPoint("LEFT",  row, "LEFT",  252, 0)
    zoneFS:SetPoint("RIGHT", row, "RIGHT", -6,  0)
    zoneFS:SetJustifyH("LEFT")
    zoneFS:SetWordWrap(false)
    row.zoneFS = zoneFS

    return row
end

local function ReleaseRosterRow(row)
    row:Hide()
    _rosterPool[#_rosterPool + 1] = row
end

function UI:_CreateCommunityRosterPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT",    parent, "TOPLEFT",    0, 0)
    panel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    panel:SetWidth(ROST_W)
    UI.CommunitiesTab.rosterPanel = panel

    -- Header bar
    local hdr = CreateFrame("Frame", nil, panel)
    hdr:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, 0)
    hdr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    hdr:SetHeight(32)
    S:GradientBg(hdr, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL_HDR_B[1], S.COLOR.PANEL_HDR_B[2], S.COLOR.PANEL_HDR_B[3], 1)

    local hdrFS = S:FS(hdr, "OVERLAY", "normal")
    hdrFS:SetPoint("LEFT", hdr, "LEFT", 10, 0)
    hdrFS:SetPoint("RIGHT", hdr, "RIGHT", -6, 0)
    hdrFS:SetJustifyH("LEFT")
    hdrFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    panel.hdrFS = hdrFS

    local hdrDiv = hdr:CreateTexture(nil, "ARTWORK")
    hdrDiv:SetPoint("BOTTOMLEFT",  hdr, "BOTTOMLEFT")
    hdrDiv:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT")
    hdrDiv:SetHeight(1)
    hdrDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.4)

    -- Column header
    local colHdr = CreateFrame("Frame", nil, panel)
    colHdr:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -32)
    colHdr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -32)
    colHdr:SetHeight(20)
    S:Bg(colHdr, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    local function ColLabel(text, x, w)
        local fs = S:FS(colHdr, "OVERLAY")
        fs:SetPoint("LEFT", colHdr, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end
    ColLabel("Name",  22,  110)
    ColLabel("Lvl",   136,  30)
    ColLabel("Role",  170,  78)
    ColLabel("Zone",  252,  ROST_W - 258)

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0, -52)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 0)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetHeight(10)
    sf:SetScrollChild(sc)
    local function SyncW() sc:SetWidth(math.max(sf:GetWidth(), 1)) end
    sf:SetScript("OnSizeChanged", SyncW)
    C_Timer.After(0, SyncW)

    panel.scrollFrame   = sf
    panel.scrollContent = sc
end

function UI:_RefreshCommunityRoster()
    local frame = UI.CommunitiesTab
    local panel = frame and frame.rosterPanel
    if not panel then return end

    -- Release existing rows
    for _, row in ipairs(_rosterActiveRows) do ReleaseRosterRow(row) end
    _rosterActiveRows = {}

    if not _activeClubId then return end

    local members = GH.Communities:GetMembers(_activeClubId)

    -- Update header
    local onCount = 0
    for _, m in ipairs(members) do
        if GH.Communities:IsOnline(m.presence) then onCount = onCount + 1 end
    end
    local clubInfo = C_Club and C_Club.GetClubInfo and C_Club.GetClubInfo(_activeClubId)
    local clubName = (clubInfo and clubInfo.name) or "Community"
    panel.hdrFS:SetText(clubName .. "  |cff888899" .. onCount .. "/" .. #members .. " online|r")

    local sc    = panel.scrollContent
    local rowY  = 0
    local rowI  = 0

    for _, member in ipairs(members) do
        if member.name and not member.isBanned then
            rowI = rowI + 1
            local row = AcquireRosterRow(sc)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -rowY)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -rowY)
            rowY = rowY + S.ROW_H

            -- Alternating stripe
            if rowI % 2 == 0 then
                row.stripe:SetColorTexture(
                    S.COLOR.PANEL_ALT[1], S.COLOR.PANEL_ALT[2], S.COLOR.PANEL_ALT[3], 0.55)
            else
                row.stripe:SetColorTexture(0, 0, 0, 0)
            end

            -- Online dot color
            local online = GH.Communities:IsOnline(member.presence)
            if online then
                row.dot:SetColorTexture(
                    S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 1)
            else
                row.dot:SetColorTexture(
                    S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 1)
            end

            -- Name with class color
            local r, g, b = ClassColorFromId(member.classID)
            row.nameFS:SetText(member.name or "")
            row.nameFS:SetTextColor(r, g, b)

            -- Level
            row.lvlFS:SetText(member.level and tostring(member.level) or "")
            row.lvlFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

            -- Role
            local roleLabel = ROLE_LABELS[member.role] or "Member"
            row.roleFS:SetText(roleLabel)
            row.roleFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

            -- Zone
            row.zoneFS:SetText(member.zone or "")
            row.zoneFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

            row:Show()
            _rosterActiveRows[#_rosterActiveRows + 1] = row
        end
    end

    sc:SetHeight(math.max(rowY, 10))
end
```

- [ ] **Step 2: Reload and verify**

`/reload` → `/gh` → Communities tab → click a community button. Confirm:
- Member list renders with online dots, class-colored names, level, role, zone
- Alternating row stripes appear
- Header shows correct community name and online count
- Empty communities show empty list with correct header

- [ ] **Step 3: Commit**

```
git add UI/CommunitiesTab.lua
git commit -m "feat: add community roster panel"
```

---

### Task 5: Chat panel

**Files:**
- Modify: `UI/CommunitiesTab.lua` (replace stubs `_CreateCommunityChatPanel` and `_RefreshCommunityChat`)

- [ ] **Step 1: Replace the chat panel stubs with the full implementation**

Remove the two stub functions and add:

```lua
-- ── Chat panel ────────────────────────────────────────────────────────────────

local _msgRows       = {}
local _oldestMsgId   = nil
local _chatScrolledUp = false

local function AcquireMsgRow(parent)
    local row = table.remove(_msgRows)
    if row then row:SetParent(parent); return row end

    row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)

    local fs = S:FS(row, "OVERLAY")
    fs:SetPoint("TOPLEFT",  row, "TOPLEFT",  6, 0)
    fs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    row.fs = fs

    return row
end

local function ReleaseMsgRow(row)
    row:Hide()
    _msgRows[#_msgRows + 1] = row
end

function UI:_CreateCommunityChatPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT",     parent, "TOPLEFT",     ROST_W + 1, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    UI.CommunitiesTab.chatPanel = panel

    -- Input bar (built first so message area can anchor to it)
    local inputBar = CreateFrame("Frame", nil, panel)
    inputBar:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT",  0, 0)
    inputBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    inputBar:SetHeight(INP_H)
    S:Bg(inputBar, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    local inputTopLine = inputBar:CreateTexture(nil, "ARTWORK")
    inputTopLine:SetPoint("TOPLEFT",  inputBar, "TOPLEFT")
    inputTopLine:SetPoint("TOPRIGHT", inputBar, "TOPRIGHT")
    inputTopLine:SetHeight(1)
    inputTopLine:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.6)

    local inputBox = S:EditBox(inputBar, 0, 28, 255)
    inputBox:SetPoint("LEFT",  inputBar, "LEFT",  10, 0)
    inputBox:SetPoint("RIGHT", inputBar, "RIGHT", -96, 0)
    panel.inputBox = inputBox

    -- Placeholder text inside input box
    local inputHint = S:FS(inputBox, "OVERLAY")
    inputHint:SetPoint("LEFT", inputBox, "LEFT", 6, 0)
    inputHint:SetTextColor(0.35, 0.35, 0.45)
    panel.inputHint = inputHint
    inputBox:SetScript("OnEditFocusGained", function() inputHint:Hide() end)
    inputBox:SetScript("OnEditFocusLost", function()
        if inputBox:GetText() == "" then inputHint:Show() end
    end)

    local sendBtn = S:Button(inputBar, "Send", 82, 30)
    sendBtn:SetPoint("RIGHT", inputBar, "RIGHT", -8, 0)

    local function DoSend()
        if not (_activeClubId and _activeStreamId) then return end
        local text = inputBox:GetText():match("^%s*(.-)%s*$")
        if text == "" then return end
        GH.Communities:SendMessage(_activeClubId, _activeStreamId, text)
        inputBox:SetText("")
        inputBox:ClearFocus()
        inputHint:Show()
        _chatScrolledUp = false
        -- Small delay to let the server echo the message back via CLUB_MESSAGE_ADDED
        C_Timer.After(0.15, function() UI:_RefreshCommunityChat() end)
    end

    sendBtn:SetScript("OnClick", DoSend)
    inputBox:SetScript("OnEnterPressed", function(eb) DoSend(); eb:ClearFocus() end)
    inputBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)

    -- Message scroll frame
    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",    panel, "TOPLEFT",    0, 0)
    sf:SetPoint("BOTTOMRIGHT", inputBar, "TOPRIGHT", -20, 0)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetHeight(10)
    sf:SetScrollChild(sc)
    local function SyncW() sc:SetWidth(math.max(sf:GetWidth(), 1)) end
    sf:SetScript("OnSizeChanged", SyncW)
    C_Timer.After(0, SyncW)

    -- Detect scroll-to-top for lazy loading older messages
    sf:SetScript("OnVerticalScroll", function(self, offset)
        _chatScrolledUp = offset < self:GetVerticalScrollRange()
        if offset < 20 and _activeClubId and _activeStreamId and _oldestMsgId then
            GH.Communities:RequestOlderMessages(_activeClubId, _activeStreamId, _oldestMsgId)
            _oldestMsgId = nil   -- prevent duplicate requests
        end
    end)

    panel.msgScrollFrame   = sf
    panel.msgScrollContent = sc

    -- "↓ Jump to latest" button
    local jumpBtn = S:Button(panel, "↓ Latest", 80, 22)
    jumpBtn:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 4)
    jumpBtn:Hide()
    jumpBtn:SetScript("OnClick", function()
        sf:SetVerticalScroll(sf:GetVerticalScrollRange())
        _chatScrolledUp = false
        jumpBtn:Hide()
    end)
    panel.jumpBtn = jumpBtn
end

local _activeMsgRows = {}

function UI:_RefreshCommunityChat()
    local frame = UI.CommunitiesTab
    local panel = frame and frame.chatPanel
    if not panel then return end

    -- Release existing rows
    for _, row in ipairs(_activeMsgRows) do ReleaseMsgRow(row) end
    _activeMsgRows = {}

    -- Update input placeholder with community name
    if panel.inputHint then
        local clubInfo = _activeClubId and C_Club and C_Club.GetClubInfo
                         and C_Club.GetClubInfo(_activeClubId)
        local cName = (clubInfo and clubInfo.name) or "community"
        panel.inputHint:SetText("Message " .. cName .. "…")
        if panel.inputBox and panel.inputBox:GetText() == "" then
            panel.inputHint:Show()
        end
    end

    if not (_activeClubId and _activeStreamId) then return end

    local messages = GH.Communities:GetMessages(_activeClubId, _activeStreamId)
    local sc       = panel.msgScrollContent
    local rowY     = 0
    _oldestMsgId   = nil

    for idx, msg in ipairs(messages) do
        if not msg.destroyed and msg.content and msg.content ~= "" then
            -- Track oldest message for lazy-load paging
            if idx == 1 then _oldestMsgId = msg.id end

            local row = AcquireMsgRow(sc)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -rowY)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -rowY)

            -- Build message line
            local timeStr = (msg.id and msg.id.epoch)
                            and GH:FormatTime(msg.id.epoch) or ""
            local author  = msg.author
            local aName   = (author and author.name) or "Unknown"
            local r, g, b = ClassColorFromId(author and author.classID or 0)
            local nameTag = string.format("|cff%02x%02x%02x%s|r",
                math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), aName)
            local fullLine = "|cff888899[" .. timeStr .. "]|r  " .. nameTag .. ":  " .. msg.content

            row.fs:SetText(fullLine)
            row.fs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

            -- Dynamic row height based on wrapped text
            local lineH = math.max(18, row.fs:GetStringHeight() + 4)
            row:SetHeight(lineH)
            row:Show()
            rowY = rowY + lineH
            _activeMsgRows[#_activeMsgRows + 1] = row
        end
    end

    sc:SetHeight(math.max(rowY, 10))

    -- Scroll to bottom unless user has scrolled up
    if not _chatScrolledUp then
        C_Timer.After(0, function()
            if panel.msgScrollFrame then
                panel.msgScrollFrame:SetVerticalScroll(
                    panel.msgScrollFrame:GetVerticalScrollRange())
            end
        end)
        if panel.jumpBtn then panel.jumpBtn:Hide() end
    else
        if panel.jumpBtn then panel.jumpBtn:Show() end
    end
end
```

- [ ] **Step 2: Reload and verify**

`/reload` → `/gh` → Communities tab → select a community. Confirm:
- Message history loads in chronological order (oldest top, newest bottom)
- Author names are class-colored
- Timestamps display correctly
- Input placeholder shows community name
- Send button sends a message (visible after server echo)
- Scroll to top triggers "request older messages" (verify no Lua error; history loads on next scroll if server has older messages)
- "↓ Latest" button appears when scrolled up

- [ ] **Step 3: Commit**

```
git add UI/CommunitiesTab.lua
git commit -m "feat: add community chat panel with history and input"
```

---

### Task 6: Finder panel and Create Community dialog

**Files:**
- Modify: `UI/CommunitiesTab.lua` (replace stubs `_CreateCommunityFinderPanel`, `_PopulateFinderResults`, `_HideCommunityFinder`, `ShowCommunityFinder`)

- [ ] **Step 1: Replace finder-related stubs with the full implementation**

Remove all four stub functions and add:

```lua
-- ── Finder panel ─────────────────────────────────────────────────────────────

local _finderResultRows  = {}
local _expandedResultIdx = nil

local function AcquireFinderRow(parent)
    local row = table.remove(_finderResultRows)
    if row then row:SetParent(parent); return row end

    row = CreateFrame("Frame", nil, parent)
    row:SetHeight(44)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row.bg = bg

    local namefs = S:FS(row, "OVERLAY", "normal")
    namefs:SetPoint("TOPLEFT",  row, "TOPLEFT",  10, -6)
    namefs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -120, -6)
    namefs:SetJustifyH("LEFT")
    namefs:SetWordWrap(false)
    row.namefs = namefs

    local countfs = S:FS(row, "OVERLAY")
    countfs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -6)
    countfs:SetJustifyH("RIGHT")
    row.countfs = countfs

    local descfs = S:FS(row, "OVERLAY")
    descfs:SetPoint("TOPLEFT",  row, "TOPLEFT",  10, -24)
    descfs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -120, -24)
    descfs:SetJustifyH("LEFT")
    descfs:SetWordWrap(true)
    descfs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    row.descfs = descfs

    local applyBtn = S:Button(row, "Apply", 72, 24)
    applyBtn:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    applyBtn:Hide()
    row.applyBtn = applyBtn

    local commentBox = S:EditBox(row, 160, 22, 255)
    commentBox:SetPoint("RIGHT", applyBtn, "LEFT", -6, 0)
    commentBox:Hide()
    row.commentBox = commentBox

    local commentHint = S:FS(commentBox, "OVERLAY")
    commentHint:SetPoint("LEFT", commentBox, "LEFT", 6, 0)
    commentHint:SetText("Add a comment…")
    commentHint:SetTextColor(0.35, 0.35, 0.45)
    commentBox:SetScript("OnEditFocusGained", function() commentHint:Hide() end)
    commentBox:SetScript("OnEditFocusLost", function()
        if commentBox:GetText() == "" then commentHint:Show() end
    end)
    row.commentHint = commentHint

    return row
end

local function ReleaseFinderRow(row)
    row:Hide()
    _finderResultRows[#_finderResultRows + 1] = row
end

local _activeFinderRows = {}

function UI:_CreateCommunityFinderPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()
    UI.CommunitiesTab.finderPanel = panel

    -- Background
    S:Bg(panel, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 1)

    -- Header bar
    local hdr = CreateFrame("Frame", nil, panel)
    hdr:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, 0)
    hdr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    hdr:SetHeight(44)
    S:GradientBg(hdr, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL_HDR_B[1], S.COLOR.PANEL_HDR_B[2], S.COLOR.PANEL_HDR_B[3], 1)

    local backBtn = S:Button(hdr, "← Back", 70, 26)
    backBtn:SetPoint("LEFT", hdr, "LEFT", 10, 0)
    backBtn:SetScript("OnClick", function() UI:_HideCommunityFinder() end)

    local hdrTitle = S:FS(hdr, "OVERLAY", "large")
    hdrTitle:SetPoint("CENTER", hdr, "CENTER")
    hdrTitle:SetText("Find a Community")
    hdrTitle:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local hdrDiv = hdr:CreateTexture(nil, "ARTWORK")
    hdrDiv:SetPoint("BOTTOMLEFT",  hdr, "BOTTOMLEFT")
    hdrDiv:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT")
    hdrDiv:SetHeight(1)
    hdrDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

    -- Search bar row
    local searchRow = CreateFrame("Frame", nil, panel)
    searchRow:SetPoint("TOPLEFT",  panel, "TOPLEFT",  10, -54)
    searchRow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -54)
    searchRow:SetHeight(30)

    local searchBox = S:EditBox(searchRow, 0, 26, 128)
    searchBox:SetPoint("LEFT",  searchRow, "LEFT",  0, 0)
    searchBox:SetPoint("RIGHT", searchRow, "RIGHT", -180, 0)
    local sHint = S:FS(searchBox, "OVERLAY")
    sHint:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    sHint:SetText("Search communities…")
    sHint:SetTextColor(0.35, 0.35, 0.45)
    searchBox:SetScript("OnEditFocusGained", function() sHint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function()
        if searchBox:GetText() == "" then sHint:Show() end
    end)
    panel.searchBox = searchBox

    local searchBtn = S:Button(searchRow, "Search", 72, 26)
    searchBtn:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)

    local createBtn = S:Button(searchRow, "Create Community", 130, 26)
    createBtn:SetPoint("RIGHT", searchRow, "RIGHT", 0, 0)
    createBtn:SetScript("OnClick", function()
        UI:_ShowCreateCommunityDialog()
    end)

    local statusFS = S:FS(searchRow, "OVERLAY")
    statusFS:SetPoint("LEFT", searchBtn, "RIGHT", 10, 0)
    statusFS:SetPoint("RIGHT", createBtn, "LEFT", -6, 0)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    panel.statusFS = statusFS

    local function DoSearch()
        local term = searchBox:GetText():match("^%s*(.-)%s*$")
        statusFS:SetText("Searching…")
        GH.Communities:SearchFinder(term)
    end
    searchBtn:SetScript("OnClick", DoSearch)
    searchBox:SetScript("OnEnterPressed", function(eb) DoSearch(); eb:ClearFocus() end)
    searchBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)

    -- Results scroll frame
    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0, -94)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 0)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetHeight(10)
    sf:SetScrollChild(sc)
    local function SyncW() sc:SetWidth(math.max(sf:GetWidth(), 1)) end
    sf:SetScript("OnSizeChanged", SyncW)
    C_Timer.After(0, SyncW)

    panel.resultsScrollContent = sc
end

function UI:ShowCommunityFinder()
    local frame = UI.CommunitiesTab
    if not frame then return end
    if frame.rosterPanel then frame.rosterPanel:Hide() end
    if frame.chatPanel   then frame.chatPanel:Hide()   end
    if frame.splitDiv    then frame.splitDiv:Hide()    end
    if frame.finderPanel then frame.finderPanel:Show() end
    _expandedResultIdx = nil
end

function UI:_HideCommunityFinder()
    local frame = UI.CommunitiesTab
    if not frame then return end
    if frame.finderPanel then frame.finderPanel:Hide() end
    if frame.rosterPanel then frame.rosterPanel:Show() end
    if frame.chatPanel   then frame.chatPanel:Show()   end
    if frame.splitDiv    then frame.splitDiv:Show()    end
end

function UI:_PopulateFinderResults()
    local frame = UI.CommunitiesTab
    local panel = frame and frame.finderPanel
    if not panel or not panel:IsShown() then return end

    -- Release existing rows
    for _, row in ipairs(_activeFinderRows) do ReleaseFinderRow(row) end
    _activeFinderRows = {}

    local results = GH.Communities._finderResults or {}
    panel.statusFS:SetText(#results > 0 and (#results .. " results") or "No communities found.")

    local sc   = panel.resultsScrollContent
    local rowY = 0

    for idx, club in ipairs(results) do
        local row = AcquireFinderRow(sc)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -rowY)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -rowY)

        local isExpanded = (idx == _expandedResultIdx)
        local rowH = isExpanded and 80 or 44
        row:SetHeight(rowH)

        -- Alternating stripe
        if idx % 2 == 0 then
            row.bg:SetColorTexture(
                S.COLOR.PANEL_ALT[1], S.COLOR.PANEL_ALT[2], S.COLOR.PANEL_ALT[3], 0.55)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row.namefs:SetText(club.name or "Unknown")
        row.namefs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        row.countfs:SetText((club.memberCount or 0) .. " members")
        row.countfs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

        local desc = (club.description or ""):sub(1, isExpanded and 200 or 80)
        if not isExpanded and #(club.description or "") > 80 then desc = desc .. "…" end
        row.descfs:SetText(desc)

        row.applyBtn:SetShown(isExpanded)
        row.commentBox:SetShown(isExpanded)
        row.commentHint:SetShown(isExpanded and row.commentBox:GetText() == "")

        -- Click row to expand/collapse
        local capturedIdx  = idx
        local capturedGUID = club.clubFinderGUID
        row:SetScript("OnMouseUp", function()
            _expandedResultIdx = (capturedIdx == _expandedResultIdx) and nil or capturedIdx
            UI:_PopulateFinderResults()
        end)

        -- Apply button
        row.applyBtn:SetScript("OnClick", function()
            local comment = row.commentBox:GetText():match("^%s*(.-)%s*$")
            GH.Communities:ApplyToClub(capturedGUID, comment)
            row.applyBtn:SetText("Applied!")
            row.applyBtn:Disable()
            C_Timer.After(3, function() row.applyBtn:SetText("Apply"); row.applyBtn:Enable() end)
        end)

        rowY = rowY + rowH + 2
        row:Show()
        _activeFinderRows[#_activeFinderRows + 1] = row
    end

    sc:SetHeight(math.max(rowY, 10))
end

-- ── Create Community dialog ───────────────────────────────────────────────────

function UI:_ShowCreateCommunityDialog()
    local dlg = rawget(_G, "GuildHubCreateCommunityDialog")
    if dlg then dlg:Show(); return end

    dlg = CreateFrame("Frame", "GuildHubCreateCommunityDialog", UIParent)
    dlg:SetSize(400, 260)
    dlg:SetPoint("CENTER", UIParent, "CENTER")
    dlg:SetFrameStrata("DIALOG")
    dlg:SetMovable(true)
    dlg:EnableMouse(true)
    dlg:SetScript("OnMouseDown", function() dlg:StartMoving() end)
    dlg:SetScript("OnMouseUp",   function() dlg:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "GuildHubCreateCommunityDialog")

    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    -- Border
    local function EdgeLine(p1, p2, isHoriz)
        local t = dlg:CreateTexture(nil, "BORDER")
        t:SetPoint(p1, dlg, p1); t:SetPoint(p2, dlg, p2)
        if isHoriz then t:SetHeight(1) else t:SetWidth(1) end
        t:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.55)
    end
    EdgeLine("TOPLEFT", "TOPRIGHT", true); EdgeLine("BOTTOMLEFT", "BOTTOMRIGHT", true)
    EdgeLine("TOPLEFT", "BOTTOMLEFT", false); EdgeLine("TOPRIGHT", "BOTTOMRIGHT", false)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, dlg)
    titleBar:SetPoint("TOPLEFT", dlg, "TOPLEFT"); titleBar:SetPoint("TOPRIGHT", dlg, "TOPRIGHT")
    titleBar:SetHeight(34)
    S:GradientBg(titleBar, "VERTICAL",
        S.COLOR.TITLE_TOP[1], S.COLOR.TITLE_TOP[2], S.COLOR.TITLE_TOP[3], 1,
        S.COLOR.TITLE_BOT[1], S.COLOR.TITLE_BOT[2], S.COLOR.TITLE_BOT[3], 1)

    local titleFS = S:FS(titleBar, "OVERLAY", "normal")
    titleFS:SetPoint("CENTER", titleBar, "CENTER")
    titleFS:SetText("Create Community")
    titleFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local closeX = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeX:SetPoint("RIGHT", titleBar, "RIGHT", 2, 0)
    closeX:SetSize(28, 28)
    closeX:SetScript("OnClick", function() dlg:Hide() end)

    -- Fields
    local function MakeField(label, yOff, maxLen, hint)
        local lbl = S:FS(dlg, "OVERLAY")
        lbl:SetPoint("TOPLEFT", dlg, "TOPLEFT", 16, yOff)
        lbl:SetText(label)
        lbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

        local eb = S:EditBox(dlg, 340, 24, maxLen)
        eb:SetPoint("TOPLEFT", dlg, "TOPLEFT", 16, yOff - 18)
        if hint then
            local h = S:FS(eb, "OVERLAY")
            h:SetPoint("LEFT", eb, "LEFT", 6, 0)
            h:SetText(hint); h:SetTextColor(0.35, 0.35, 0.45)
            eb:SetScript("OnEditFocusGained", function() h:Hide() end)
            eb:SetScript("OnEditFocusLost", function()
                if eb:GetText() == "" then h:Show() end
            end)
        end
        return eb
    end

    local nameEB = MakeField("Name", -44, 64, "Community name…")
    local shortEB = MakeField("Short Name (optional)", -100, 24, "Abbreviated…")
    local descEB  = MakeField("Description (optional)", -156, 255, "What is this community about?")

    -- Confirm / Cancel
    local confirmBtn = S:Button(dlg, "Create", 90, 28)
    confirmBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -16, 12)
    confirmBtn:SetScript("OnClick", function()
        local name = nameEB:GetText():match("^%s*(.-)%s*$")
        if name == "" then return end
        local short = shortEB:GetText():match("^%s*(.-)%s*$")
        local desc  = descEB:GetText():match("^%s*(.-)%s*$")
        GH.Communities:CreateCommunity(name, short, desc)
        dlg:Hide()
    end)

    local cancelBtn = S:Button(dlg, "Cancel", 80, 28)
    cancelBtn:SetPoint("RIGHT", confirmBtn, "LEFT", -8, 0)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)

    dlg:Show()
end
```

- [ ] **Step 2: Reload and verify**

`/reload` → `/gh` → Communities → "Find a Community":
- Finder panel opens, hides roster and chat
- Search bar submits query; results populate from `_finderResults` on `CLUB_FINDER_CLUBS_LOADED`
- Clicking a result row expands it with full description, comment box, and Apply button
- Clicking Apply sends the application and briefly shows "Applied!"
- "← Back" restores the roster+chat split
- "Create Community" opens the dialog; filling name and clicking Create calls `CreateCommunity`

- [ ] **Step 3: Commit**

```
git add UI/CommunitiesTab.lua
git commit -m "feat: add community finder panel and create community dialog"
```

---

### Task 7: Live event wiring and final polish

**Files:**
- Modify: `UI/CommunitiesTab.lua` (add `OnShow` handler and finalize event plumbing)

- [ ] **Step 1: Add `OnShow` handler to `CommunitiesTab` so it bootstraps on first display**

In `UI:CreateCommunitiesTab`, before the final `end`, add:

```lua
frame:SetScript("OnShow", function()
    UI:RefreshCommunitiesTab()
end)
```

- [ ] **Step 2: Verify the full event round-trip for roster updates**

In WoW with the addon loaded (`/gh debug on`):
1. Have a friend join or leave your community.
2. `CLUB_MEMBER_ADDED` / `CLUB_MEMBER_REMOVED` fires → `CD:OnEvent` → `UI:OnCommunityRosterUpdate` → `UI:_RefreshCommunityRoster`.
3. Confirm the roster list updates without needing a manual refresh.

If no friend is available: open the Communities tab while another GuildHub session is running (alt account), then watch the roster update when that character changes zones (triggers `CLUB_MEMBER_UPDATED` with new zone).

- [ ] **Step 3: Verify the full event round-trip for new messages**

In WoW with the addon loaded:
1. Send a community message from another character or ask a community member to post.
2. `CLUB_MESSAGE_ADDED` fires → `CD:OnEvent` → `UI:OnCommunityMessageAdded` → `UI:_RefreshCommunityChat`.
3. Confirm the message appears at the bottom of the chat panel without manual refresh.

- [ ] **Step 4: Verify `CLUB_ADDED` / `CLUB_REMOVED` rebuilds the selector bar**

In WoW:
1. Join a new community while the Communities tab is open (or use `/run C_Club.AcceptInvitation(...)` if you have a pending invite).
2. Confirm the new community's button appears in the selector bar immediately.
3. Leave a community (via the default WoW community UI if needed).
4. Confirm its button disappears and the tab auto-selects the next community.

- [ ] **Step 5: Final smoke test — open the tab cold**

`/reload` → `/gh` → click Communities. Confirm the full flow:
- Selector bar shows all non-guild communities
- First community auto-selected
- Roster loads with correct online/offline indicators and class colors
- Chat history loads with timestamped, class-colored messages
- "Find a Community" opens the finder, Back returns to community view
- No Lua errors throughout

- [ ] **Step 6: Commit**

```
git add CommunityData.lua Core.lua GuildHub.toc UI/CommunitiesTab.lua UI/MainWindow.lua
git commit -m "feat: Communities tab — roster, chat, finder, live event wiring"
```
