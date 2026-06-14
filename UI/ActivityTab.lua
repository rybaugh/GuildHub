-- GuildHub - ActivityTab
-- Shows the guild activity log: joins, leaves, promotions, demotions,
-- level-ups, note changes, bans, and other roster events.
-- Color-coded rows with filters by event type and name search.

local GH  = GuildHub
local S   = GH.Styles
local UI  = GH.UI

local ROW_H = 34

-- ── Color map for event types ─────────────────────────────────────────────────

local TYPE_COLOR = {
    JOIN         = { 0.13, 0.85, 0.30 },   -- green
    REJOIN       = { 0.40, 0.90, 0.55 },   -- lighter green
    LEAVE        = { 0.88, 0.32, 0.32 },   -- red
    KICK         = { 0.90, 0.25, 0.25 },
    PROMOTE      = { 0.95, 0.80, 0.30 },   -- gold
    DEMOTE       = { 0.88, 0.56, 0.20 },   -- orange
    LEVEL_UP     = { 0.42, 0.54, 0.85 },   -- accent blue
    NOTE_CHANGE  = { 0.55, 0.60, 0.90 },
    OFFICER_NOTE = { 0.45, 0.50, 0.85 },
    BAN_REJOIN   = { 0.80, 0.20, 0.20 },   -- dark red
    BAN          = { 0.80, 0.15, 0.15 },
    UNBAN        = { 0.30, 0.75, 0.30 },
    NAME_CHANGE  = { 0.70, 0.70, 0.70 },
    TEAM_ROLE    = { 0.60, 0.45, 0.90 },  -- purple
}

local function TypeColor(t)
    local c = TYPE_COLOR[t]
    return c and c[1] or 0.7, c and c[2] or 0.7, c and c[3] or 0.7
end

-- ── Build tab ─────────────────────────────────────────────────────────────────

function UI:CreateActivityTab(parent, w, h)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    frame:SetScript("OnShow", function() UI:RefreshActivityTab() end)
    UI.ActivityTab = frame

    -- ── Toolbar ───────────────────────────────────────────────────────────────
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  10, -6)
    toolbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -6)
    toolbar:SetHeight(30)

    -- Search box
    local searchBox = S:EditBox(toolbar, 200, 26, 80)
    searchBox:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    local hint = S:FS(searchBox, "OVERLAY")
    hint:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    hint:SetText("Filter by name…")
    hint:SetTextColor(0.4, 0.4, 0.5)
    searchBox:SetScript("OnEditFocusGained", function() hint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function()
        if searchBox:GetText() == "" then hint:Show() end
    end)
    searchBox:SetScript("OnTextChanged", function() UI:RefreshActivityTab() end)
    frame.searchBox = searchBox

    -- Clear log button (officer only)
    if GH:IsOfficer() then
        local clearBtn = S:DangerButton(toolbar, "Clear Log", 80, 26)
        clearBtn:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
        clearBtn:SetScript("OnClick", function()
            GH.DB:ClearActivityLog()
            UI:RefreshActivityTab()
        end)
    end

    -- Count label
    local countLabel = S:FS(toolbar, "OVERLAY")
    countLabel:SetPoint("RIGHT", toolbar, "RIGHT", GH:IsOfficer() and -90 or 0, 0)
    countLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame.countLabel = countLabel

    -- ── Filter chips ──────────────────────────────────────────────────────────
    local filterBar = CreateFrame("Frame", nil, frame)
    filterBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  10, -42)
    filterBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -42)
    filterBar:SetHeight(26)

    local FILTER_TYPES = {
        { key = "JOIN",      label = "Join",    all = {"JOIN","REJOIN"} },
        { key = "LEAVE",     label = "Leave",   all = {"LEAVE","KICK"} },
        { key = "PROMOTE",   label = "Promote", all = {"PROMOTE","DEMOTE"} },
        { key = "LEVEL_UP",  label = "Level",   all = {"LEVEL_UP"} },
        { key = "NOTE",      label = "Notes",   all = {"NOTE_CHANGE","OFFICER_NOTE"} },
        { key = "BAN",       label = "Ban",     all = {"BAN","UNBAN","BAN_REJOIN"} },
        { key = "TEAM_ROLE", label = "Teams",   all = {"TEAM_ROLE"} },
    }

    local activeFilters = {}  -- key -> true when chip is active
    local chipBtns = {}

    local chipX = 0
    for _, ft in ipairs(FILTER_TYPES) do
        local chip = CreateFrame("Button", nil, filterBar)
        chip:SetHeight(22)
        chip:SetPoint("LEFT", filterBar, "LEFT", chipX, 0)

        local chipBg = chip:CreateTexture(nil, "BACKGROUND")
        chipBg:SetAllPoints()
        chip.chipBg = chipBg

        local chipLbl = S:FS(chip, "OVERLAY")
        chipLbl:SetPoint("CENTER", chip, "CENTER")
        chipLbl:SetText(ft.label)
        chip.chipLbl = chipLbl

        chip:SetWidth(chipLbl:GetStringWidth() + 18)
        chipX = chipX + chip:GetWidth() + 4

        local cr, cg, cb = TypeColor(ft.all[1])

        local function UpdateChip()
            if activeFilters[ft.key] then
                chipBg:SetColorTexture(cr * 0.5, cg * 0.5, cb * 0.5, 0.9)
                chipLbl:SetTextColor(cr, cg, cb)
            else
                chipBg:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.8)
                chipLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
            end
        end
        UpdateChip()

        local capturedFt = ft
        chip:SetScript("OnClick", function()
            activeFilters[capturedFt.key] = not activeFilters[capturedFt.key]
            UpdateChip()
            UI:RefreshActivityTab()
        end)
        chip:SetScript("OnEnter", function()
            chipBg:SetColorTexture(cr * 0.4, cg * 0.4, cb * 0.4, 0.8)
        end)
        chip:SetScript("OnLeave", UpdateChip)

        chipBtns[ft.key] = { btn = chip, types = ft.all, refresh = UpdateChip }
    end

    frame.activeFilters = activeFilters
    frame.filterDefs    = FILTER_TYPES
    frame.chipBtns      = chipBtns

    -- ── Scroll list ───────────────────────────────────────────────────────────
    local sf = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     frame, "TOPLEFT",     10, -74)
    sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 10)

    local scrollBg = sf:CreateTexture(nil, "BACKGROUND", nil, -2)
    scrollBg:SetAllPoints()
    scrollBg:SetColorTexture(0, 0, 0, 0.15)

    local contentW = (w or 800) - 10 - 36
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(contentW, 10)
    sf:SetScrollChild(sc)
    frame.scrollContent = sc

    -- Pool of row frames
    frame._rowPool = {}

    -- Register for live updates
    GH.ActivityLog:RegisterCallback("activityTab", function()
        if UI.ActivityTab and UI.ActivityTab:IsShown() then
            UI:RefreshActivityTab()
        end
    end)

    UI:RefreshActivityTab()
end

-- ── Row pool ──────────────────────────────────────────────────────────────────

local function GetOrCreateActivityRow(frame, idx, parent)
    local row = frame._rowPool[idx]
    if row then return row end

    row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    row.rowBg = rowBg

    -- Left color bar (event type indicator)
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetSize(3, ROW_H - 6)
    bar:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.bar = bar

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    -- Timestamp
    local tsFS = S:FS(row, "OVERLAY")
    tsFS:SetPoint("LEFT", row, "LEFT", 30, 0)
    tsFS:SetWidth(90)
    tsFS:SetJustifyH("LEFT")
    tsFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    row.tsFS = tsFS

    -- Description
    local descFS = S:FS(row, "OVERLAY")
    descFS:SetPoint("LEFT",  row, "LEFT",  124, 0)
    descFS:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    descFS:SetJustifyH("LEFT")
    descFS:SetWordWrap(false)
    row.descFS = descFS

    frame._rowPool[idx] = row
    return row
end

-- ── Refresh ───────────────────────────────────────────────────────────────────

function UI:RefreshActivityTab()
    local frame = self.ActivityTab
    if not frame then return end

    local activeFilters = frame.activeFilters
    local filterDefs    = frame.filterDefs

    -- Build active type set
    local typeSet = nil
    for _, fd in ipairs(filterDefs) do
        if activeFilters[fd.key] then
            typeSet = typeSet or {}
            for _, t in ipairs(fd.all) do typeSet[t] = true end
        end
    end

    local nameFilter = frame.searchBox and frame.searchBox:GetText():lower() or ""

    local entries = GH.ActivityLog:GetLog({
        types = typeSet,
        name  = (nameFilter ~= "" and nameFilter or nil),
    })

    local sc = frame.scrollContent
    -- Hide existing rows
    for _, row in ipairs(frame._rowPool) do row:Hide() end

    local shown = 0
    for i, entry in ipairs(entries) do
        local row = GetOrCreateActivityRow(frame, i, sc)
        row:SetParent(sc)
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(shown) * ROW_H)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(shown) * ROW_H)
        row:Show()

        local cr, cg, cb = TypeColor(entry.type)
        row.bar:SetColorTexture(cr, cg, cb, 0.9)

        local iconTex = GH.ActivityLog.TYPE_ICON[entry.type]
        if iconTex then row.icon:SetTexture(iconTex) end

        row.tsFS:SetText(GH:FormatTime(entry.ts))

        local desc = GH.ActivityLog:FormatEntry(entry)
        row.descFS:SetText(desc)
        row.descFS:SetTextColor(cr * 0.9 + 0.1, cg * 0.9 + 0.1, cb * 0.9 + 0.1)

        if shown % 2 == 0 then
            row.rowBg:SetColorTexture(
                S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.4)
        else
            row.rowBg:SetColorTexture(0, 0, 0, 0)
        end

        shown = shown + 1
    end

    sc:SetHeight(math.max(shown * ROW_H, 10))

    if frame.countLabel then
        frame.countLabel:SetText(shown .. " events")
    end
end
