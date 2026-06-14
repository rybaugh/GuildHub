-- GuildHub - Guild Recruit Tab
-- Officers post the guild to the in-game Guild/Club Finder and manage applicants.
-- Read-only for non-officers (they can still see current settings and applicants).

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local CreateFrame = _G.CreateFrame

-- ──────────────────────────────────────────────────────────
-- Local helpers
-- ──────────────────────────────────────────────────────────

local function CC(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), tostring(text))
end

local function TimeAgo(ts)
    local diff = (GH:GetTimestamp() or time()) - (ts or 0)
    if diff < 60    then return "just now" end
    if diff < 3600  then return math.floor(diff / 60) .. "m ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
    return math.floor(diff / 86400) .. "d ago"
end

-- WoW class file name → display colour
local CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 }, PALADIN    = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 }, ROGUE      = { 1.00, 0.96, 0.41 },
    PRIEST      = { 1.00, 1.00, 1.00 }, DEATHKNIGHT= { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.00, 0.44, 0.87 }, MAGE       = { 0.41, 0.80, 0.94 },
    WARLOCK     = { 0.58, 0.51, 0.79 }, MONK       = { 0.00, 1.00, 0.59 },
    DRUID       = { 1.00, 0.49, 0.04 }, DEMONHUNTER= { 0.64, 0.19, 0.79 },
    EVOKER      = { 0.20, 0.58, 0.50 },
}

local function ClassColor(cls)
    local c = cls and CLASS_COLORS[cls:upper()]
    return c and c[1] or S.COLOR.TEXT[1],
           c and c[2] or S.COLOR.TEXT[2],
           c and c[3] or S.COLOR.TEXT[3]
end

-- ──────────────────────────────────────────────────────────
-- Dropdown widget
-- ──────────────────────────────────────────────────────────

local _activeDrop = nil

local function MakeDrop(parent, x, y, w, items, defaultIdx, enabled)
    local state = { idx = defaultIdx or 1 }

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, 26)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local bbg = btn:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)
    local bborder = btn:CreateTexture(nil, "BORDER")
    bborder:SetAllPoints()
    bborder:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.55)

    local labelFS = S:FS(btn, "OVERLAY")
    labelFS:SetPoint("LEFT",  btn, "LEFT",  8, 0)
    labelFS:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
    labelFS:SetJustifyH("LEFT")
    labelFS:SetText(items[state.idx] or "")

    local arrowFS = S:FS(btn, "OVERLAY", "normal")
    arrowFS:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrowFS:SetText("▾")

    if not enabled then
        btn:SetAlpha(0.5)
        btn:Disable()
        labelFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        arrowFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    else
        labelFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        arrowFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        btn:SetScript("OnEnter", function()
            bbg:SetColorTexture(S.COLOR.PANEL[1]+0.06, S.COLOR.PANEL[2]+0.06, S.COLOR.PANEL[3]+0.08, 1)
        end)
        btn:SetScript("OnLeave", function()
            bbg:SetColorTexture(S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)
        end)
    end

    local ROW_H = 24
    local popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("DIALOG")
    popup:SetWidth(w)
    popup:SetHeight(math.min(#items, 8) * ROW_H + 4)
    popup:Hide()
    S:Bg(popup, S.COLOR.BG[1]+0.03, S.COLOR.BG[2]+0.03, S.COLOR.BG[3]+0.04, 0.98)
    local pb = popup:CreateTexture(nil, "BORDER")
    pb:SetAllPoints()
    pb:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.65)

    if enabled then
        btn:SetScript("OnClick", function()
            if _activeDrop and _activeDrop ~= popup then _activeDrop:Hide() end
            if popup:IsShown() then popup:Hide(); _activeDrop = nil; return end

            for i = popup:GetNumChildren(), 1, -1 do select(i, popup:GetChildren()):Hide() end

            local showMax = math.min(#items, 8)
            popup:SetHeight(showMax * ROW_H + 4)
            for i = 1, showMax do
                local item = items[i]
                local row  = CreateFrame("Button", nil, popup)
                row:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -(i-1)*ROW_H - 2)
                row:SetSize(w - 2, ROW_H)
                row:Show()
                local rbg = row:CreateTexture(nil, "BACKGROUND")
                rbg:SetAllPoints()
                rbg:SetColorTexture(state.idx==i and S.COLOR.NAV_ACTIVE[1] or 0,
                                    state.idx==i and S.COLOR.NAV_ACTIVE[2] or 0,
                                    state.idx==i and S.COLOR.NAV_ACTIVE[3] or 0,
                                    state.idx==i and 0.85 or 0)
                local rfs = S:FS(row, "OVERLAY")
                rfs:SetPoint("LEFT", row, "LEFT", 8, 0)
                rfs:SetText(item)
                rfs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
                row:SetScript("OnEnter", function()
                    rbg:SetColorTexture(S.COLOR.NAV_ACTIVE[1], S.COLOR.NAV_ACTIVE[2], S.COLOR.NAV_ACTIVE[3], 0.85)
                    rfs:SetTextColor(1, 1, 1)
                end)
                row:SetScript("OnLeave", function()
                    rbg:SetColorTexture(0, 0, 0, 0)
                    rfs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
                end)
                local captIdx = i
                row:SetScript("OnClick", function()
                    state.idx = captIdx
                    labelFS:SetText(items[captIdx])
                    popup:Hide(); _activeDrop = nil
                end)
            end
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            popup:Show(); popup:Raise()
            _activeDrop = popup
        end)
    end

    state.getValue    = function() return items[state.idx] end
    state.setByValue  = function(val)
        for i, v in ipairs(items) do
            if v == val then state.idx = i; labelFS:SetText(v); return end
        end
    end
    return state
end

-- ──────────────────────────────────────────────────────────
-- Role/tag chip row
-- Chips are toggle-style buttons; selectedSet[key] = true when active.
-- ──────────────────────────────────────────────────────────

local CHIP_W = { Tank=52, Healer=62, DPS=46, Caster=60, Melee=56, Ranged=62 }

local function MakeChips(parent, x, y, roles, selectedSet, enabled)
    local chips = {}
    local cx    = x
    for _, role in ipairs(roles) do
        local cw  = CHIP_W[role] or 66
        local chip = CreateFrame("Button", nil, parent)
        chip:SetSize(cw, 20)
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, y)
        cx = cx + cw + 5

        local cbg = chip:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        chip.cbg = cbg

        local cfs = S:FS(chip, "OVERLAY")
        cfs:SetAllPoints()
        cfs:SetText(role)
        chip.cfs = cfs
        chip._role = role

        if not enabled then chip:SetAlpha(0.5); chip:Disable() end

        local function RefreshChip()
            local active = selectedSet[role]
            cbg:SetColorTexture(
                active and S.COLOR.ACCENT[1] or (S.COLOR.PANEL[1]+0.04),
                active and S.COLOR.ACCENT[2] or (S.COLOR.PANEL[2]+0.04),
                active and S.COLOR.ACCENT[3] or (S.COLOR.PANEL[3]+0.06),
                active and 0.90 or 1)
            cfs:SetTextColor(active and 1 or S.COLOR.TEXT_DIM[1],
                             active and 1 or S.COLOR.TEXT_DIM[2],
                             active and 1 or S.COLOR.TEXT_DIM[3])
        end
        chip.Refresh = RefreshChip
        RefreshChip()

        if enabled then
            chip:SetScript("OnEnter", function()
                cbg:SetColorTexture(S.COLOR.ACCENT[1]*0.75, S.COLOR.ACCENT[2]*0.75, S.COLOR.ACCENT[3]*0.75, 0.8)
            end)
            chip:SetScript("OnLeave", RefreshChip)
            chip:SetScript("OnClick", function()
                if selectedSet[role] then selectedSet[role] = nil else selectedSet[role] = true end
                RefreshChip()
            end)
        end

        chips[#chips + 1] = chip
    end
    return chips
end

-- ──────────────────────────────────────────────────────────
-- Build the Guild Recruit tab
-- ──────────────────────────────────────────────────────────

function UI:CreateGuildRecruitTab(parent, w)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.RecruitTab = frame

    local PAD      = 10
    local isOff    = GH:IsOfficer()
    local settings = GH.DB:GetGuildRecruitSettings()

    -- ── Posting panel ─────────────────────────────────────
    local PANEL_H = 228

    local pp = CreateFrame("Frame", nil, frame)
    pp:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, -PAD)
    pp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
    pp:SetHeight(PANEL_H)
    S:Bg(pp, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    local topBar = pp:CreateTexture(nil, "ARTWORK")
    topBar:SetPoint("TOPLEFT"); topBar:SetPoint("TOPRIGHT"); topBar:SetHeight(2)
    topBar:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 1)

    -- "GUILD RECRUITMENT" header
    S:Header(pp, "GUILD RECRUITMENT"):SetPoint("TOPLEFT", pp, "TOPLEFT", 10, -10)

    -- Listed checkbox
    local listedChk = CreateFrame("CheckButton", nil, pp, "UICheckButtonTemplate")
    listedChk:SetSize(20, 20)
    listedChk:SetPoint("TOPLEFT", pp, "TOPLEFT", 10, -28)
    listedChk:SetChecked(settings.listed or false)
    if not isOff then listedChk:SetAlpha(0.5); listedChk:Disable() end
    frame._listedChk = listedChk
    if isOff then
        listedChk:SetScript("OnClick", function()
            local checked = listedChk:GetChecked() == true
            local msg = frame._msgBox and frame._msgBox:GetText():match("^%s*(.-)%s*$") or ""
            GH.GuildRecruit:_SetFinderListed(checked, msg)
        end)
    end

    local listedLbl = S:FS(pp, "OVERLAY", "normal")
    listedLbl:SetPoint("LEFT", listedChk, "RIGHT", 3, 0)
    listedLbl:SetText("List My Guild in Guild Finder")
    listedLbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

    -- ── Left column (x=10..370) ───────────────────────────
    local L_W = 360  -- left column width

    -- Focus label + dropdown
    local focusLbl = S:FS(pp, "OVERLAY")
    focusLbl:SetPoint("TOPLEFT", pp, "TOPLEFT", 10, -58)
    focusLbl:SetText("Focus:")
    focusLbl:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local focusItems  = GH.GuildRecruit.FOCUS_TYPES
    local focusDefIdx = 1
    for i, v in ipairs(focusItems) do if v == settings.focus then focusDefIdx = i; break end end
    local focusDrop = MakeDrop(pp, 10, -74, 160, focusItems, focusDefIdx, isOff)
    frame._focusDrop = focusDrop

    -- Language label + dropdown (right of focus)
    local langLbl = S:FS(pp, "OVERLAY")
    langLbl:SetPoint("TOPLEFT", pp, "TOPLEFT", 180, -58)
    langLbl:SetText("Language:")
    langLbl:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local langItems  = GH.GuildRecruit.LANGUAGES
    local langDefIdx = 1
    for i, v in ipairs(langItems) do if v == settings.language then langDefIdx = i; break end end
    local langDrop = MakeDrop(pp, 180, -74, 160, langItems, langDefIdx, isOff)
    frame._langDrop = langDrop

    -- Looking For chips (two rows of 3)
    local lfLbl = S:FS(pp, "OVERLAY")
    lfLbl:SetPoint("TOPLEFT", pp, "TOPLEFT", 10, -110)
    lfLbl:SetText("Looking For:")
    lfLbl:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local selectedRoles = {}
    for _, r in ipairs(settings.lookingFor or {}) do selectedRoles[r] = true end
    frame._selectedRoles = selectedRoles

    local allRoles = GH.GuildRecruit.ROLE_TYPES
    local row1     = { allRoles[1], allRoles[2], allRoles[3] }  -- Tank Healer DPS
    local row2     = { allRoles[4], allRoles[5], allRoles[6] }  -- Caster Melee Ranged
    frame._roleChips = {}
    for _, chip in ipairs(MakeChips(pp, 10, -126, row1, selectedRoles, isOff)) do
        frame._roleChips[#frame._roleChips+1] = chip
    end
    for _, chip in ipairs(MakeChips(pp, 10, -150, row2, selectedRoles, isOff)) do
        frame._roleChips[#frame._roleChips+1] = chip
    end

    -- Requirements row
    local maxLvlChk = CreateFrame("CheckButton", nil, pp, "UICheckButtonTemplate")
    maxLvlChk:SetSize(18, 18)
    maxLvlChk:SetPoint("BOTTOMLEFT", pp, "BOTTOMLEFT", 10, 36)
    maxLvlChk:SetChecked(settings.maxLevelOnly ~= false)
    if not isOff then maxLvlChk:SetAlpha(0.5); maxLvlChk:Disable() end
    frame._maxLvlChk = maxLvlChk

    local maxLvlLbl = S:FS(pp, "OVERLAY")
    maxLvlLbl:SetPoint("LEFT", maxLvlChk, "RIGHT", 2, 0)
    maxLvlLbl:SetText("Max Level Only")
    maxLvlLbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    if not isOff then maxLvlLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3]) end

    local minIlvlChk = CreateFrame("CheckButton", nil, pp, "UICheckButtonTemplate")
    minIlvlChk:SetSize(18, 18)
    minIlvlChk:SetPoint("LEFT", maxLvlLbl, "RIGHT", 18, 0)
    minIlvlChk:SetChecked(settings.minIlvlEnabled or false)
    if not isOff then minIlvlChk:SetAlpha(0.5); minIlvlChk:Disable() end
    frame._minIlvlChk = minIlvlChk

    local minIlvlLbl = S:FS(pp, "OVERLAY")
    minIlvlLbl:SetPoint("LEFT", minIlvlChk, "RIGHT", 2, 0)
    minIlvlLbl:SetText("Min. Item Level")
    minIlvlLbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    if not isOff then minIlvlLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3]) end

    local ilvlEB = S:EditBox(pp, 72, 20, 7)
    ilvlEB:SetPoint("LEFT", minIlvlLbl, "RIGHT", 6, 0)
    ilvlEB:SetText(settings.minIlvl and settings.minIlvl > 0 and tostring(settings.minIlvl) or "")
    if not isOff then ilvlEB:SetEnabled(false); ilvlEB:SetAlpha(0.5) end
    frame._ilvlEB = ilvlEB

    -- ── Right column: Recruitment Message ────────────────
    local RIGHT_X = L_W + 22   -- px from panel left edge

    local msgLbl = S:FS(pp, "OVERLAY")
    msgLbl:SetPoint("TOPLEFT", pp, "TOPLEFT", RIGHT_X, -10)
    msgLbl:SetText("Recruitment Message:")
    msgLbl:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    -- Height: panel_h minus label area minus bottom-button row minus top-accent
    local msgH = PANEL_H - 28 - 38 - 4
    local msgW = w - 2*PAD - RIGHT_X - 10
    if msgW < 180 then msgW = 180 end

    local msgBg = pp:CreateTexture(nil, "BACKGROUND")
    msgBg:SetPoint("TOPLEFT",  pp, "TOPLEFT",  RIGHT_X, -26)
    msgBg:SetPoint("TOPLEFT",  pp, "TOPLEFT",  RIGHT_X, -26)
    msgBg:SetSize(msgW, msgH)
    msgBg:SetColorTexture(S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)
    local msgBorder = pp:CreateTexture(nil, "BORDER")
    msgBorder:SetPoint("TOPLEFT",  pp, "TOPLEFT",  RIGHT_X, -26)
    msgBorder:SetSize(msgW, msgH)
    msgBorder:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.55)

    local msgBox = CreateFrame("EditBox", nil, pp)
    msgBox:SetSize(msgW - 10, msgH - 8)
    msgBox:SetPoint("TOPLEFT", pp, "TOPLEFT", RIGHT_X + 5, -30)
    msgBox:SetFontObject(S.FontSmall)
    msgBox:SetAutoFocus(false)
    msgBox:SetMultiLine(true)
    msgBox:SetMaxLetters(500)
    msgBox:SetTextInsets(4, 4, 4, 4)
    msgBox:SetText(settings.message or "")
    msgBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if not isOff then msgBox:SetEnabled(false); msgBox:SetAlpha(0.6) end
    frame._msgBox = msgBox

    -- Char counter
    local charCountFS = S:FS(pp, "OVERLAY")
    charCountFS:SetPoint("BOTTOMRIGHT", pp, "TOPLEFT", RIGHT_X + msgW, -26 + msgH - 2)
    charCountFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    local function RefreshCharCount()
        local len = #(msgBox:GetText())
        charCountFS:SetText(tostring(len) .. "/500")
        if len >= 480 then
            charCountFS:SetTextColor(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3])
        else
            charCountFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end
    end
    msgBox:SetScript("OnTextChanged", RefreshCharCount)
    RefreshCharCount()

    -- ── Action buttons ────────────────────────────────────
    if isOff then
        local saveBtn = S:Button(pp, "Save & Post", 110, 26)
        saveBtn:SetPoint("BOTTOMRIGHT", pp, "BOTTOMRIGHT", -10, 10)
        saveBtn:SetScript("OnClick", function()
            if _activeDrop then _activeDrop:Hide(); _activeDrop = nil end
            UI:_SaveAndPost()
        end)

        local nativeBtn = CreateFrame("Button", nil, pp)
        nativeBtn:SetSize(100, 26)
        nativeBtn:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)
        local nbg = nativeBtn:CreateTexture(nil, "BACKGROUND")
        nbg:SetAllPoints()
        nbg:SetColorTexture(S.COLOR.PANEL[1]+0.08, S.COLOR.PANEL[2]+0.08, S.COLOR.PANEL[3]+0.10, 1)
        local nborder = nativeBtn:CreateTexture(nil, "BORDER")
        nborder:SetAllPoints()
        nborder:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.55)
        local nlbl = S:FS(nativeBtn, "OVERLAY")
        nlbl:SetAllPoints()
        nlbl:SetText("Open Finder")
        nlbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        nativeBtn:SetScript("OnEnter", function()
            nbg:SetColorTexture(S.COLOR.PANEL[1]+0.16, S.COLOR.PANEL[2]+0.16, S.COLOR.PANEL[3]+0.20, 1)
        end)
        nativeBtn:SetScript("OnLeave", function()
            nbg:SetColorTexture(S.COLOR.PANEL[1]+0.08, S.COLOR.PANEL[2]+0.08, S.COLOR.PANEL[3]+0.10, 1)
        end)
        nativeBtn:SetScript("OnClick", function()
            GH.GuildRecruit:OpenNativeWindow()
        end)
    end

    -- Last-updated strip
    local updatedFS = S:FS(pp, "OVERLAY")
    updatedFS:SetPoint("BOTTOMLEFT", pp, "BOTTOMLEFT", 10, 14)
    frame._updatedFS = updatedFS
    UI:_RefreshRecruitInfo()

    -- Officer-only lock notice for non-officers
    if not isOff then
        local lockFS = S:FS(pp, "OVERLAY")
        lockFS:SetPoint("BOTTOMRIGHT", pp, "BOTTOMRIGHT", -10, 14)
        lockFS:SetText(CC("Officer access required to edit", S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3]))
    end

    -- ── Applicants panel ──────────────────────────────────
    local ap = CreateFrame("Frame", nil, frame)
    ap:SetPoint("TOPLEFT",    pp,    "BOTTOMLEFT",   0,    -8)
    ap:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD,  4)
    S:Bg(ap, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.45)

    local apBar = ap:CreateTexture(nil, "ARTWORK")
    apBar:SetPoint("TOPLEFT"); apBar:SetPoint("TOPRIGHT"); apBar:SetHeight(2)
    apBar:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.55)

    S:Header(ap, "APPLICANTS"):SetPoint("TOPLEFT", ap, "TOPLEFT", 10, -10)

    local refreshBtn = S:Button(ap, "↺ Refresh", 80, 18)
    refreshBtn:SetPoint("TOPRIGHT", ap, "TOPRIGHT", -8, -4)
    refreshBtn:SetScript("OnClick", function()
        GH.GuildRecruit:RequestApplicants()
        UI:RefreshApplicantsList()
    end)

    -- Column headers
    local HDR_Y = -28
    local function ApHdr(text, x, cw, just)
        local fs = S:FS(ap, "OVERLAY")
        fs:SetPoint("TOPLEFT", ap, "TOPLEFT", x, HDR_Y)
        fs:SetWidth(cw)
        fs:SetJustifyH(just or "LEFT")
        fs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        fs:SetText(text)
    end
    ApHdr("Name",    14,  130)
    ApHdr("Class",  150,  110)
    ApHdr("Level",  264,   52, "CENTER")
    ApHdr("Message", 320, 230)
    -- action col implied

    -- Divider under headers
    local hdrDiv = ap:CreateTexture(nil, "ARTWORK")
    hdrDiv:SetPoint("TOPLEFT",  ap, "TOPLEFT",  6, HDR_Y - 16)
    hdrDiv:SetPoint("TOPRIGHT", ap, "TOPRIGHT", -6, HDR_Y - 16)
    hdrDiv:SetHeight(1)
    hdrDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, ap)
    sf:SetPoint("TOPLEFT",    ap, "TOPLEFT",    4, HDR_Y - 18)
    sf:SetPoint("BOTTOMRIGHT", ap, "BOTTOMRIGHT", -8, 4)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(sf2, delta)
        local mx = sf2:GetVerticalScrollRange()
        sf2:SetVerticalScroll(math.max(0, math.min(mx, sf2:GetVerticalScroll() - delta * 30)))
    end)

    local appContent = CreateFrame("Frame", nil, sf)
    appContent:SetSize(sf:GetWidth() or 720, 10)
    sf:SetScrollChild(appContent)
    frame.appContent = appContent

    -- Empty-state holder
    local emptyHolder = CreateFrame("Frame", nil, appContent)
    emptyHolder:SetPoint("TOP", appContent, "TOP", 0, -22)
    emptyHolder:SetSize(500, 24)
    local emptyFS = S:FS(emptyHolder, "OVERLAY", "normal")
    emptyFS:SetAllPoints()
    emptyFS:SetJustifyH("CENTER")
    emptyFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    emptyHolder:Hide()
    frame.appEmptyHolder = emptyHolder
    frame.appEmptyFS     = emptyFS

    UI:RefreshApplicantsList()
end

-- ──────────────────────────────────────────────────────────
-- Save & Post
-- ──────────────────────────────────────────────────────────

function UI:_SaveAndPost()
    local frame = UI.RecruitTab
    if not frame then return end

    local roles = {}
    for role, active in pairs(frame._selectedRoles) do
        if active then roles[#roles + 1] = role end
    end
    table.sort(roles)

    local minIlvl = 0
    if frame._minIlvlChk:GetChecked() then
        minIlvl = tonumber(frame._ilvlEB:GetText()) or 0
    end

    local new = {
        listed         = frame._listedChk:GetChecked() == true,
        focus          = frame._focusDrop.getValue(),
        language       = frame._langDrop.getValue(),
        lookingFor     = roles,
        message        = frame._msgBox:GetText():match("^%s*(.-)%s*$") or "",
        maxLevelOnly   = frame._maxLvlChk:GetChecked() == true,
        minIlvlEnabled = frame._minIlvlChk:GetChecked() == true,
        minIlvl        = minIlvl,
    }

    GH.GuildRecruit:SaveSettings(new)
    local posted = GH.GuildRecruit:PostToFinder(new)
    UI:_RefreshRecruitInfo()

    -- Flash confirmation
    local fs = frame._updatedFS
    if fs then
        local msg
        if not new.listed then
            msg = CC("Settings saved.", S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
                .. " Enable |cffF2CF00List My Guild in Guild Finder|r to publish."
        elseif posted then
            msg = CC("Saved & Listed!", S.COLOR.GREEN[1], S.COLOR.GREEN[2], S.COLOR.GREEN[3])
        else
            msg = CC("Saved, but listing failed — see chat for details.", S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3])
        end
        fs:SetText(msg)
        C_Timer.After(2.5, function() UI:_RefreshRecruitInfo() end)
    end
end

-- ──────────────────────────────────────────────────────────
-- Info strip (last updated / not-posted state)
-- ──────────────────────────────────────────────────────────

function UI:_RefreshRecruitInfo()
    local frame = UI.RecruitTab
    if not frame or not frame._updatedFS then return end
    local s = GH.DB:GetGuildRecruitSettings()
    if s and s.updatedAt and s.updatedBy then
        frame._updatedFS:SetText(
            "Last posted by "
            .. CC(s.updatedBy, S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
            .. "  "
            .. CC(TimeAgo(s.updatedAt), S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3]))
    else
        frame._updatedFS:SetText(
            CC("Not yet posted — fill in the form above and click Save & Post.",
               S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3]))
    end
end

-- ──────────────────────────────────────────────────────────
-- Applicants list
-- ──────────────────────────────────────────────────────────

function UI:RefreshApplicantsList()
    local frame = UI.RecruitTab
    if not frame or not frame.appContent then return end

    local content = frame.appContent

    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    local applicants = GH.GuildRecruit:GetApplicants()

    if #applicants == 0 then
        if GH.GuildRecruit:HasClubFinderAPI() then
            frame.appEmptyFS:SetText("No pending applicants.")
        else
            frame.appEmptyFS:SetText(
                "Guild Finder API not available.  "
                .. CC("Use the native Guild Finder for applicant management.",
                      S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3]))
        end
        frame.appEmptyHolder:Show()
        content:SetHeight(60)
        return
    end

    local ROW_H = 38
    local GAP   = 2

    for i, app in ipairs(applicants) do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i-1)*(ROW_H+GAP))
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i-1)*(ROW_H+GAP))
        row:SetHeight(ROW_H)
        row:Show()

        S:Bg(row, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], i%2==0 and 0.55 or 0)

        -- Class-coloured left accent bar
        local cr, cg, cb = ClassColor(app.class)
        local bar = row:CreateTexture(nil, "ARTWORK")
        bar:SetSize(3, ROW_H - 4)
        bar:SetPoint("LEFT", row, "LEFT", 0, 0)
        bar:SetColorTexture(cr, cg, cb, 0.85)

        -- Name
        local nameFS = S:FS(row, "OVERLAY")
        nameFS:SetPoint("LEFT", row, "LEFT", 10, 4)
        nameFS:SetWidth(130)
        nameFS:SetText(app.name or "?")
        nameFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

        -- Role badge under name (if present)
        if app.role and app.role ~= "" then
            local roleFS = S:FS(row, "OVERLAY")
            roleFS:SetPoint("LEFT", row, "LEFT", 10, -10)
            roleFS:SetWidth(130)
            roleFS:SetText(CC(app.role, S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3]))
        end

        -- Class
        local classFS = S:FS(row, "OVERLAY")
        classFS:SetPoint("LEFT", row, "LEFT", 150, 0)
        classFS:SetWidth(110)
        local disp = app.class and (app.class:sub(1,1):upper() .. app.class:sub(2):lower()) or "?"
        classFS:SetText(CC(disp, cr, cg, cb))

        -- Level
        local lvlFS = S:FS(row, "OVERLAY")
        lvlFS:SetPoint("LEFT", row, "LEFT", 264, 0)
        lvlFS:SetWidth(52)
        lvlFS:SetJustifyH("CENTER")
        lvlFS:SetText(app.level and app.level > 0 and tostring(app.level) or "?")
        lvlFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

        -- Application message
        local msgFS = S:FS(row, "OVERLAY")
        msgFS:SetPoint("LEFT",  row, "LEFT",  320, 0)
        if GH:IsOfficer() then
            msgFS:SetPoint("RIGHT", row, "RIGHT", -164, 0)
        else
            msgFS:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        end
        local msgText = (app.comment and app.comment ~= "") and app.comment
                     or CC("No message", S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        msgFS:SetText(msgText)
        msgFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

        -- Accept / Decline buttons (officers only)
        if GH:IsOfficer() then
            local captApp = app

            -- Accept (green)
            local accBtn = S:Button(row, "✓ Accept", 78, 24)
            accBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            accBtn.bg:SetColorTexture(
                S.COLOR.GREEN[1]*0.45, S.COLOR.GREEN[2]*0.45, S.COLOR.GREEN[3]*0.45, 0.95)
            accBtn:SetScript("OnEnter", function(b)
                b.bg:SetColorTexture(
                    S.COLOR.GREEN[1]*0.65, S.COLOR.GREEN[2]*0.65, S.COLOR.GREEN[3]*0.65, 1)
            end)
            accBtn:SetScript("OnLeave", function(b)
                b.bg:SetColorTexture(
                    S.COLOR.GREEN[1]*0.45, S.COLOR.GREEN[2]*0.45, S.COLOR.GREEN[3]*0.45, 0.95)
            end)
            accBtn:SetScript("OnClick", function()
                if GH.GuildRecruit:AcceptApplicant(captApp.id) then
                    UI:RefreshApplicantsList()
                end
            end)

            -- Decline (red)
            local decBtn = S:DangerButton(row, "✕ Decline", 80, 24)
            decBtn:SetPoint("RIGHT", accBtn, "LEFT", -4, 0)
            decBtn:SetScript("OnClick", function()
                if GH.GuildRecruit:DeclineApplicant(captApp.id) then
                    UI:RefreshApplicantsList()
                end
            end)

            -- Applied timestamp
            local ageFS = S:FS(row, "OVERLAY")
            ageFS:SetPoint("RIGHT", decBtn, "LEFT", -6, 0)
            ageFS:SetWidth(62)
            ageFS:SetJustifyH("RIGHT")
            ageFS:SetText(TimeAgo(app.ts or 0))
            ageFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end
    end

    content:SetHeight(math.max(#applicants * (ROW_H + GAP), 10))
end

-- ──────────────────────────────────────────────────────────
-- Callbacks from GuildRecruitPost
-- ──────────────────────────────────────────────────────────

function UI:OnGuildRecruitUpdated()
    local win = self.window
    if win and win:IsShown() and win.activeTab == "Recruit" then
        UI:RefreshApplicantsList()
        UI:_RefreshRecruitInfo()
    end
end
