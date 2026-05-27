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
    if clipW == 0 then return end
    local innerW   = 0
    for _, entry in ipairs(_tabBtns) do
        innerW = innerW + entry.btn:GetWidth() + 4
    end
    _tabScrollX = math.max(0, math.min(_tabScrollX, math.max(0, innerW - clipW)))
    tabInner:ClearAllPoints()
    tabInner:SetPoint("TOPLEFT", frame.tabClip, "TOPLEFT", -_tabScrollX, 0)
    frame.leftArrow:SetShown(_tabScrollX > 0)
    frame.rightArrow:SetShown(innerW > clipW and _tabScrollX < math.max(0, innerW - clipW))
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
