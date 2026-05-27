-- GuildHub - LFM Tab (Looking for More)
-- Guild members browse and post groups for dungeons, raids, battlegrounds, and arena.

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

local function ActColor(actType)
    local c = GH.Recruit.ACTIVITY_COLORS and GH.Recruit.ACTIVITY_COLORS[actType]
    if c then return c[1], c[2], c[3] end
    return 0.55, 0.55, 0.65
end

local function RoleColor(role)
    local c = GH.Recruit.ROLE_COLORS and GH.Recruit.ROLE_COLORS[role]
    if c then return c[1], c[2], c[3] end
    return 0.6, 0.6, 0.7
end

local function TimeRemaining(ts)
    local expireAt  = (ts or 0) + (GH.Recruit.EXPIRE_SECS or 1800)
    local remaining = expireAt - (GH:GetTimestamp() or time())
    if remaining <= 60  then return "|cffff4444<1m left|r" end
    return math.ceil(remaining / 60) .. "m left"
end

-- Compact open-slots string, e.g. "1T 1H 3D" or "Full"
local function SlotSummary(post)
    local total = GH.Recruit:TotalOpen(post)
    if total == 0 then return "Full" end
    local abbrs = GH.Recruit.ROLE_ABBR or {}
    local parts = {}
    for _, need in ipairs(post.needs or {}) do
        local open = GH.Recruit:OpenSlotsForRole(post, need.role)
        if open > 0 then
            parts[#parts + 1] = tostring(open) .. (abbrs[need.role] or "?")
        end
    end
    return table.concat(parts, " ")
end

-- ──────────────────────────────────────────────────────────
-- Returns how many of each broad role are currently in the player's group.
local function GetCurrentGroupRoles()
    local counts = { Tank = 0, Healer = 0, DPS = 0 }
    local units  = {}
    if rawget(_G, "IsInRaid") and IsInRaid() then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, n do units[#units + 1] = "raid" .. i end
    elseif rawget(_G, "IsInGroup") and IsInGroup() then
        units[#units + 1] = "player"
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for i = 1, n do units[#units + 1] = "party" .. i end
    else
        units[#units + 1] = "player"
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
            if     role == "TANK"    then counts.Tank   = counts.Tank   + 1
            elseif role == "HEALER"  then counts.Healer = counts.Healer + 1
            elseif role == "DAMAGER" then counts.DPS    = counts.DPS    + 1
            end
        end
    end
    return counts
end

-- Sets dungeon spinner values to reflect only the slots still needed
-- (standard M+ composition minus roles already covered by current group members).
local function AutoFillDungeonSpinners(frame)
    if not frame._dungeonStates then return end
    local g = GetCurrentGroupRoles()
    local vals = {
        math.max(0, 1 - g.Tank),    -- Tank  cap = 1
        math.max(0, 1 - g.Healer),  -- Healer cap = 1
        math.max(0, 3 - g.DPS),     -- DPS   cap = 3
    }
    for i, state in ipairs(frame._dungeonStates) do
        state.val = vals[i]
        if state.refresh then state.refresh() end
    end
end

-- ──────────────────────────────────────────────────────────
-- Role card widget  (replaces the old MakeSpinner)
-- A compact self-contained card: role name → large count → −/+ strip.
-- ──────────────────────────────────────────────────────────

local ROLE_SHORT = {
    Tank = "TANK", Healer = "HEAL", DPS = "DPS",
    ["Melee DPS"] = "MELEE", ["Ranged DPS"] = "RANGED",
}

local function MakeRoleCard(parent, role, x, y, default, minV, maxV)
    local r, g, b  = RoleColor(role)
    local CARD_W, CARD_H, BTN_H = 80, 56, 18

    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(CARD_W, CARD_H)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    -- Background tinted with role colour
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    card.bg = bg

    -- Top accent strip
    local topBar = card:CreateTexture(nil, "ARTWORK")
    topBar:SetPoint("TOPLEFT"); topBar:SetPoint("TOPRIGHT"); topBar:SetHeight(3)
    topBar:SetColorTexture(r, g, b, 0.90)

    -- Role name
    local nameFS = S:FS(card, "OVERLAY")
    nameFS:SetPoint("TOP", card, "TOP", 0, -6)
    nameFS:SetText(ROLE_SHORT[role] or role:upper())
    nameFS:SetTextColor(r, g, b, 0.90)

    -- Count
    local state = { val = tonumber(default) or 0, minV = minV or 0, maxV = maxV or 25 }
    local countFS = S:FS(card, "OVERLAY", "large")
    countFS:SetPoint("CENTER", card, "CENTER", 0, -4)

    local function Upd()
        local active = state.val > 0
        countFS:SetText(tostring(state.val))
        countFS:SetTextColor(
            active and S.COLOR.TEXT_GOLD[1] or 0.30,
            active and S.COLOR.TEXT_GOLD[2] or 0.30,
            active and S.COLOR.TEXT_GOLD[3] or 0.30)
        bg:SetColorTexture(
            r * (active and 0.16 or 0.06),
            g * (active and 0.16 or 0.06),
            b * (active and 0.16 or 0.06), 0.95)
    end
    state.refresh = Upd
    Upd()

    -- Bottom −/+ strip split into two halves
    local function MakeBtn(isPlus)
        local btn = CreateFrame("Button", nil, card)
        btn:SetSize(CARD_W / 2, BTN_H)
        btn:SetPoint(isPlus and "BOTTOMRIGHT" or "BOTTOMLEFT", card,
                     isPlus and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, 0)
        local sbg = btn:CreateTexture(nil, "BACKGROUND")
        sbg:SetAllPoints()
        sbg:SetColorTexture(0.13, 0.13, 0.20, 0.90)
        local sfs = S:FS(btn, "OVERLAY", "normal")
        sfs:SetAllPoints(); sfs:SetText(isPlus and "+" or "−")
        sfs:SetTextColor(0.55, 0.60, 0.80)
        btn:SetScript("OnEnter", function()
            sbg:SetColorTexture(r*0.28, g*0.28, b*0.28, 1); sfs:SetTextColor(1, 1, 1)
        end)
        btn:SetScript("OnLeave", function()
            sbg:SetColorTexture(0.13, 0.13, 0.20, 0.90); sfs:SetTextColor(0.55, 0.60, 0.80)
        end)
        btn:SetScript("OnClick", function()
            if isPlus then state.val = math.min(state.maxV, state.val + 1)
            else            state.val = math.max(state.minV, state.val - 1) end
            Upd()
        end)
    end
    MakeBtn(false); MakeBtn(true)

    return state
end

-- ──────────────────────────────────────────────────────────
-- Instance picker widget  (simple dropdown for dungeons/raids)
-- ──────────────────────────────────────────────────────────

local _activePicker = nil   -- only one picker open at a time

local function MakePicker(parent, x, y, w, placeholder, getItemsFn)
    local state = { value = nil }

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, 28)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local bbg = btn:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)
    local bborder = btn:CreateTexture(nil, "BORDER")
    bborder:SetAllPoints()
    bborder:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.55)

    local labelFS = S:FS(btn, "OVERLAY")
    labelFS:SetPoint("LEFT", btn, "LEFT", 8, 0)
    labelFS:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    labelFS:SetJustifyH("LEFT")
    labelFS:SetText(placeholder)
    labelFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    local arrowFS = S:FS(btn, "OVERLAY", "normal")
    arrowFS:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrowFS:SetText("▾")
    arrowFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    btn:SetScript("OnEnter", function()
        bbg:SetColorTexture(S.COLOR.PANEL[1]+0.06, S.COLOR.PANEL[2]+0.06, S.COLOR.PANEL[3]+0.08, 1)
    end)
    btn:SetScript("OnLeave", function()
        bbg:SetColorTexture(S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)
    end)

    -- Popup list
    local popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("DIALOG")
    popup:SetWidth(w)
    popup:Hide()
    S:Bg(popup, S.COLOR.BG[1]+0.03, S.COLOR.BG[2]+0.03, S.COLOR.BG[3]+0.04, 0.98)
    local pb = popup:CreateTexture(nil, "BORDER")
    pb:SetAllPoints()
    pb:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.65)

    local ROW_H = 24

    btn:SetScript("OnClick", function()
        if _activePicker and _activePicker ~= popup then _activePicker:Hide() end
        if popup:IsShown() then popup:Hide(); _activePicker = nil; return end

        -- Clear old rows
        for i = popup:GetNumChildren(), 1, -1 do select(i, popup:GetChildren()):Hide() end

        local items = getItemsFn()
        popup:SetHeight(math.min(#items, 8) * ROW_H + 4)

        for i, item in ipairs(items) do
            if i > 8 then break end
            local row = CreateFrame("Button", nil, popup)
            row:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -(i-1)*ROW_H - 2)
            row:SetSize(w - 2, ROW_H); row:Show()
            local rbg = row:CreateTexture(nil, "BACKGROUND")
            rbg:SetAllPoints(); rbg:SetColorTexture(0, 0, 0, 0)
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
            local captItem = item
            row:SetScript("OnClick", function()
                state.value = captItem
                labelFS:SetText(captItem)
                labelFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
                popup:Hide(); _activePicker = nil
            end)
        end

        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        popup:Show(); popup:Raise()
        _activePicker = popup
    end)

    state.getValue = function() return state.value end
    state.reset    = function()
        state.value = nil
        labelFS:SetText(placeholder)
        labelFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end
    state.setDefault = function(val)
        state.value = val
        labelFS:SetText(val)
        labelFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    end
    return state
end

-- Returns current season M+ dungeon names.
-- Tries several API spellings and falls back to an empty list + "Custom".
local function GetSeasonDungeons()
    local out = {}
    if C_ChallengeMode then
        -- Try both spellings; Midnight may have renamed or added the API.
        local ids = {}
        if C_ChallengeMode.GetActiveChallengeMapIDs then
            ids = C_ChallengeMode.GetActiveChallengeMapIDs() or {}
        end
        if #ids == 0 and C_ChallengeMode.GetMapTable then
            ids = C_ChallengeMode.GetMapTable() or {}
        end
        for _, id in ipairs(ids) do
            if C_ChallengeMode.GetMapUIInfo then
                local ok, name = pcall(function()
                    return select(1, C_ChallengeMode.GetMapUIInfo(id))
                end)
                if ok and name and name ~= "" then out[#out+1] = name end
            end
        end
        table.sort(out)
    end
    out[#out+1] = "Custom"
    return out
end

-- Known Midnight Season 1 raids (fallback when EJ API returns nothing).
local MIDNIGHT_S1_RAIDS = { "Voidspire", "March on Quel'Danas", "The Dreamrift" }

-- Returns current expansion's raid names via the Encounter Journal,
-- falling back to the known Midnight Season 1 list.
local function GetCurrentRaids()
    local out = {}
    local ok, numTiers = pcall(function()
        return (rawget(_G, "EJ_GetNumTiers") and EJ_GetNumTiers()) or 0
    end)
    if ok and numTiers and numTiers > 0 then
        for tier = numTiers, math.max(1, numTiers - 1), -1 do
            pcall(function() EJ_SelectTier(tier) end)
            local ok2, numInst = pcall(function()
                local fn = rawget(_G, "EJ_GetNumInstances")
                return fn and (fn(tier) or fn()) or 0
            end)
            if ok2 and numInst and numInst > 0 then
                for i = 1, numInst do
                    pcall(function()
                        local name, _, _, _, _, _, _, _, _, isRaid = EJ_GetInstanceInfo(i)
                        if isRaid and name and name ~= "" then out[#out+1] = name end
                    end)
                end
            end
            if #out > 0 then break end
        end
    end
    if #out == 0 then
        for _, n in ipairs(MIDNIGHT_S1_RAIDS) do out[#out+1] = n end
    end
    out[#out+1] = "Custom"
    return out
end

-- ──────────────────────────────────────────────────────────
-- Sign-up role popup
-- ──────────────────────────────────────────────────────────

local _popup = nil   -- lazily created, reused

local function HideSignupPopup()
    if _popup then _popup:Hide() end
end

local function ShowSignupPopup(postId, post, anchor)
    local openRoles = GH.Recruit:GetOpenRoles(post)
    if #openRoles == 0 then return end

    -- Build popup lazily
    if not _popup then
        _popup = CreateFrame("Frame", "GHLFMSignupPopup", UIParent)
        _popup:SetFrameStrata("DIALOG")
        _popup:SetClampedToScreen(true)
        S:Bg(_popup, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
        local acc = _popup:CreateTexture(nil, "ARTWORK")
        acc:SetPoint("TOPLEFT"); acc:SetPoint("TOPRIGHT"); acc:SetHeight(2)
        acc:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.80)
        tinsert(UISpecialFrames, "GHLFMSignupPopup")
    end

    -- Clear previous role buttons
    for i = _popup:GetNumChildren(), 1, -1 do
        local c = select(i, _popup:GetChildren())
        c:Hide()
    end

    local title = S:FS(_popup, "OVERLAY")
    title:SetPoint("TOP", _popup, "TOP", 0, -8)
    title:SetText("Sign up as:")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local BTN_W, BTN_H, PAD = 120, 26, 8
    local popW = BTN_W + PAD * 2
    local popH = 24 + #openRoles * (BTN_H + 4) + PAD

    _popup:SetSize(popW, popH)

    for i, role in ipairs(openRoles) do
        local r, g, b = RoleColor(role)
        local open    = GH.Recruit:OpenSlotsForRole(post, role)
        local btn     = S:Button(_popup, role .. "  (" .. open .. " open)", BTN_W, BTN_H)
        btn:SetPoint("TOPLEFT", _popup, "TOPLEFT", PAD, -22 - (i - 1) * (BTN_H + 4))
        btn.bg:SetColorTexture(r * 0.45, g * 0.45, b * 0.45, 0.95)
        btn:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(r * 0.65, g * 0.65, b * 0.65, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(r * 0.45, g * 0.45, b * 0.45, 0.95)
        end)
        local captRole = role
        local captId   = postId
        btn:SetScript("OnClick", function()
            HideSignupPopup()
            if GH.Recruit:Signup(captId, captRole) then
                UI:RefreshLFMList()
            end
        end)
        btn:Show()
    end

    -- Position above the anchor button
    _popup:ClearAllPoints()
    _popup:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
    _popup:Show()
    _popup:Raise()
end

-- ──────────────────────────────────────────────────────────
-- Applicants panel  (shown when the poster clicks their own row)
-- ──────────────────────────────────────────────────────────

local _appPanel  = nil
local _lbPanel   = nil

local MEDAL_COLORS = {
    { 0.95, 0.80, 0.30 },   -- 1st: gold
    { 0.72, 0.72, 0.76 },   -- 2nd: silver
    { 0.78, 0.48, 0.22 },   -- 3rd: bronze
}

local function ShowApplicantsPanel(post)
    if not _appPanel then
        _appPanel = CreateFrame("Frame", "GHLFMApplicantsPanel", UIParent)
        _appPanel:SetFrameStrata("DIALOG")
        _appPanel:SetClampedToScreen(true)
        _appPanel:SetMovable(true)
        _appPanel:EnableMouse(true)
        _appPanel:RegisterForDrag("LeftButton")
        _appPanel:SetScript("OnDragStart", _appPanel.StartMoving)
        _appPanel:SetScript("OnDragStop",  _appPanel.StopMovingOrSizing)
        S:Bg(_appPanel, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
        local acc = _appPanel:CreateTexture(nil, "ARTWORK")
        acc:SetPoint("TOPLEFT"); acc:SetPoint("TOPRIGHT"); acc:SetHeight(2)
        acc:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.80)
        local closeBtn = S:DangerButton(_appPanel, "✕ Close", 72, 22)
        closeBtn:SetPoint("BOTTOMRIGHT", _appPanel, "BOTTOMRIGHT", -8, 8)
        closeBtn:SetScript("OnClick", function() _appPanel:Hide() end)
        _appPanel._closeBtn = closeBtn
        -- Create fixed FontStrings once so they don't accumulate on re-open
        local title = S:FS(_appPanel, "OVERLAY", "normal")
        title:SetPoint("TOP", _appPanel, "TOP", 0, -10)
        title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        _appPanel._title = title
        local empty = S:FS(_appPanel, "OVERLAY", "normal")
        empty:SetPoint("CENTER", _appPanel, "CENTER", 0, 6)
        empty:SetText("No signups yet.")
        empty:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        _appPanel._emptyText = empty
    end

    -- Clear dynamic children (keep close button)
    for i = _appPanel:GetNumChildren(), 1, -1 do
        local child = select(i, _appPanel:GetChildren())
        if child ~= _appPanel._closeBtn then child:Hide() end
    end

    local titleStr = (post.instanceName or post.activityType) .. " — Signups"
    _appPanel._title:SetText(titleStr)
    _appPanel._title:Show()

    local signups = post.signups or {}
    local ROW_H   = 28

    if #signups == 0 then
        _appPanel._emptyText:Show()
    else
        for i, signup in ipairs(signups) do
            local row = CreateFrame("Frame", nil, _appPanel)
            row:SetPoint("TOPLEFT",  _appPanel, "TOPLEFT",  10, -28 - (i-1)*ROW_H)
            row:SetPoint("TOPRIGHT", _appPanel, "TOPRIGHT", -10, -28 - (i-1)*ROW_H)
            row:SetHeight(ROW_H)
            row:Show()
            if i % 2 == 0 then
                S:Bg(row, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.5)
            end
            local r, g, b = RoleColor(signup.role or "Any")
            local roleTag = signup.role and CC("[" .. signup.role .. "]", r, g, b) or ""
            local nameFS = S:FS(row, "OVERLAY")
            nameFS:SetPoint("LEFT", row, "LEFT", 6, 0)
            nameFS:SetText(roleTag .. "  " .. (signup.name or "?"))
            nameFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
            local ageFS = S:FS(row, "OVERLAY")
            ageFS:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            ageFS:SetText(TimeRemaining(signup.ts or 0))
            ageFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end
    end

    _appPanel._currentPostId = post.id
    _appPanel:SetSize(280, 42 + math.max(1, #signups) * ROW_H + 10)
    _appPanel:ClearAllPoints()
    _appPanel:SetPoint("CENTER", UIParent, "CENTER")
    _appPanel:Show()
    _appPanel:Raise()
end

local function RefreshApplicantsPanelIfOpen()
    if not (_appPanel and _appPanel:IsShown() and _appPanel._currentPostId) then return end
    local postId = _appPanel._currentPostId
    for _, p in ipairs(GH.Recruit:GetAll()) do
        if p.id == postId then
            ShowApplicantsPanel(p)
            return
        end
    end
    _appPanel:Hide()
end

-- ──────────────────────────────────────────────────────────
-- Build the LFM tab
-- ──────────────────────────────────────────────────────────

function UI:CreateLFMTab(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.LFMTab = frame

    local PAD = 10

    -- Per-frame state
    frame._selType  = GH.Recruit.ACTIVITY_TYPES[1]
    frame._filter   = "All"
    frame._typeBtns = {}

    -- ── Post a Group panel ────────────────────────────────
    local pp = CreateFrame("Frame", nil, frame)
    pp:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, -PAD)
    pp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
    pp:SetHeight(192)
    S:GradientBg(pp, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL[1],       S.COLOR.PANEL[2],       S.COLOR.PANEL[3],       1)

    -- Top accent stripe: gold gradient
    local accent = pp:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("TOPRIGHT"); accent:SetHeight(2)
    local _ppAccOk = pcall(function()
        accent:SetGradient("HORIZONTAL",
            CreateColor(S.COLOR.GOLD[1] * 0.5, S.COLOR.GOLD[2] * 0.5, S.COLOR.GOLD[3] * 0.3, 0.6),
            CreateColor(S.COLOR.GOLD[1],        S.COLOR.GOLD[2],        S.COLOR.GOLD[3],        0.9))
    end)
    if not _ppAccOk then
        accent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.7)
    end

    S:Header(pp, "POST A GROUP"):SetPoint("TOPLEFT", pp, "TOPLEFT", 10, -10)

    -- Row 1: activity type toggles
    local actLbl = S:FS(pp, "OVERLAY")
    actLbl:SetPoint("TOPLEFT", pp, "TOPLEFT", 10, -32)
    actLbl:SetText("Activity:")
    actLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    -- Row 2: note / description field
    local descLbl = S:FS(pp, "OVERLAY")
    descLbl:SetPoint("TOPLEFT", pp, "TOPLEFT", 10, -60)
    descLbl:SetText("Title:")
    descLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    local descBox = S:EditBox(pp, 0, 22, 80)
    descBox:SetPoint("TOPLEFT",  pp, "TOPLEFT",  52, -64)
    descBox:SetPoint("TOPRIGHT", pp, "TOPRIGHT", -10, -64)
    frame._descBox = descBox

    -- Row 3: role section (instance picker + role cards)
    -- All three sub-frames are anchored at the same spot; only one is visible at a time.
    local ROLE_Y   = -92    -- top of role row within pp
    local CW       = 80     -- card width
    local CG       = 8      -- card gap
    local INST_W   = 155   -- instance picker width
    local DIFF_W   = 96    -- difficulty picker width
    local CARDS_X  = INST_W + 6 + DIFF_W + 10  -- 267

    -- Dungeon frame: instance picker + difficulty picker + 3 role cards
    local dungeonFrame = CreateFrame("Frame", nil, pp)
    dungeonFrame:SetPoint("TOPLEFT",  pp, "TOPLEFT",  10, ROLE_Y)
    dungeonFrame:SetPoint("TOPRIGHT", pp, "TOPRIGHT", -10, ROLE_Y)
    dungeonFrame:SetHeight(60)
    frame._dungeonFrame = dungeonFrame

    frame._dungeonPicker = MakePicker(
        dungeonFrame, 0, -16, INST_W, "Select dungeon…", GetSeasonDungeons)

    frame._dungeonDiffPicker = MakePicker(
        dungeonFrame, INST_W + 6, -16, DIFF_W, "Difficulty",
        function() return { "Mythic+", "Heroic", "Normal" } end)
    frame._dungeonDiffPicker.setDefault("Mythic+")

    frame._dungeonStates = {
        MakeRoleCard(dungeonFrame, "Tank",   CARDS_X,            0, 1, 0, 1),
        MakeRoleCard(dungeonFrame, "Healer", CARDS_X + (CW+CG),  0, 1, 0, 1),
        MakeRoleCard(dungeonFrame, "DPS",    CARDS_X + (CW+CG)*2,0, 3, 0, 3),
    }
    frame._dungeonRoles = { "Tank", "Healer", "DPS" }

    -- Raid frame: instance picker + difficulty picker + 4 role cards
    local raidFrame = CreateFrame("Frame", nil, pp)
    raidFrame:SetPoint("TOPLEFT",  pp, "TOPLEFT",  10, ROLE_Y)
    raidFrame:SetPoint("TOPRIGHT", pp, "TOPRIGHT", -10, ROLE_Y)
    raidFrame:SetHeight(60)
    raidFrame:Hide()
    frame._raidFrame = raidFrame

    frame._raidPicker = MakePicker(
        raidFrame, 0, -16, INST_W, "Select raid…", GetCurrentRaids)

    frame._raidDiffPicker = MakePicker(
        raidFrame, INST_W + 6, -16, DIFF_W, "Difficulty",
        function() return { "Mythic", "Heroic", "Normal", "LFR" } end)
    frame._raidDiffPicker.setDefault("Mythic")

    frame._raidStates = {
        MakeRoleCard(raidFrame, "Tank",        CARDS_X,              0, 0, 0, 10),
        MakeRoleCard(raidFrame, "Healer",      CARDS_X + (CW+CG),    0, 0, 0, 10),
        MakeRoleCard(raidFrame, "Melee DPS",   CARDS_X + (CW+CG)*2,  0, 0, 0, 25),
        MakeRoleCard(raidFrame, "Ranged DPS",  CARDS_X + (CW+CG)*3,  0, 0, 0, 25),
    }
    frame._raidRoles = { "Tank", "Healer", "Melee DPS", "Ranged DPS" }

    -- PvP frame (Battleground / Arena): no picker, 3 cards flush-left
    local pvpFrame = CreateFrame("Frame", nil, pp)
    pvpFrame:SetPoint("TOPLEFT",  pp, "TOPLEFT",  10, ROLE_Y)
    pvpFrame:SetPoint("TOPRIGHT", pp, "TOPRIGHT", -10, ROLE_Y)
    pvpFrame:SetHeight(60)
    pvpFrame:Hide()
    frame._pvpFrame = pvpFrame

    frame._pvpStates = {
        MakeRoleCard(pvpFrame, "Tank",   0,         0, 0, 0, 15),
        MakeRoleCard(pvpFrame, "Healer", CW + CG,   0, 0, 0, 15),
        MakeRoleCard(pvpFrame, "DPS",   (CW+CG)*2,  0, 0, 0, 40),
    }
    frame._pvpRoles = { "Tank", "Healer", "DPS" }

    -- Show/hide role sub-frame based on selected type
    local function UpdateRoleSection()
        frame._dungeonFrame:Hide()
        frame._raidFrame:Hide()
        frame._pvpFrame:Hide()
        local at = frame._selType
        if at == "Dungeon" then
            AutoFillDungeonSpinners(frame)
            frame._dungeonFrame:Show()
        elseif at == "Raid" then
            frame._raidFrame:Show()
        else
            frame._pvpFrame:Show()
        end
    end
    frame._UpdateRoleSection = UpdateRoleSection

    -- Activity type toggle buttons
    local function RefreshTypeBtns()
        for _, info in ipairs(frame._typeBtns) do
            local r, g, b = ActColor(info.actType)
            if info.actType == frame._selType then
                info.btn.bg:SetColorTexture(r * 0.60, g * 0.60, b * 0.60, 1)
                info.btn.label:SetTextColor(1, 1, 1)
            else
                info.btn.bg:SetColorTexture(
                    S.COLOR.PANEL[1]+0.04, S.COLOR.PANEL[2]+0.04, S.COLOR.PANEL[3]+0.06, 1)
                info.btn.label:SetTextColor(
                    S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
            end
        end
    end

    local tbX = 70
    for _, actType in ipairs(GH.Recruit.ACTIVITY_TYPES) do
        local bw  = (actType == "Battleground") and 108 or 84
        local btn = S:Button(pp, actType, bw, 20)
        btn:SetPoint("TOPLEFT", pp, "TOPLEFT", tbX, -30)
        local cap = actType
        btn:SetScript("OnClick", function()
            frame._selType = cap
            RefreshTypeBtns()
            UpdateRoleSection()
        end)
        btn:SetScript("OnEnter", function(btn2)
            local r, g, b = ActColor(cap)
            btn2.bg:SetColorTexture(
                cap == frame._selType and r*0.75 or r*0.30,
                cap == frame._selType and g*0.75 or g*0.30,
                cap == frame._selType and b*0.75 or b*0.30, 1)
        end)
        btn:SetScript("OnLeave", function() RefreshTypeBtns() end)
        tbX = tbX + bw + 5
        table.insert(frame._typeBtns, { btn = btn, actType = actType })
    end
    RefreshTypeBtns()
    UpdateRoleSection()

    -- Guild chat checkbox (bottom-left, same row as Post Group button)
    local guildChatChk = CreateFrame("CheckButton", nil, pp, "UICheckButtonTemplate")
    guildChatChk:SetSize(22, 22)
    guildChatChk:SetPoint("BOTTOMLEFT", pp, "BOTTOMLEFT", 10, 11)
    guildChatChk:SetChecked(true)
    frame._guildChatChk = guildChatChk

    local guildChatLbl = S:FS(pp, "OVERLAY")
    guildChatLbl:SetPoint("LEFT", guildChatChk, "RIGHT", 2, 0)
    guildChatLbl:SetText("Post to guild chat")
    guildChatLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    guildChatChk:SetScript("OnEnter", function()
        guildChatLbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    end)
    guildChatChk:SetScript("OnLeave", function()
        guildChatLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end)

    -- Post Group button
    local postBtn = S:Button(pp, "Post Group", 106, 26)
    postBtn:SetPoint("BOTTOMRIGHT", pp, "BOTTOMRIGHT", -10, 10)
    postBtn:SetScript("OnClick", function()
        HideSignupPopup()
        if _activePicker then _activePicker:Hide(); _activePicker = nil end

        local at = frame._selType

        -- Instance name is required for Dungeon and Raid
        local instanceName = nil
        if at == "Dungeon" then
            instanceName = frame._dungeonPicker and frame._dungeonPicker.getValue()
            if not instanceName then return end
        elseif at == "Raid" then
            instanceName = frame._raidPicker and frame._raidPicker.getValue()
            if not instanceName then return end
        end

        local desc = descBox:GetText():match("^%s*(.-)%s*$") or ""

        local stateMap = {
            Dungeon      = { states = frame._dungeonStates, roles = frame._dungeonRoles },
            Raid         = { states = frame._raidStates,    roles = frame._raidRoles    },
            Battleground = { states = frame._pvpStates,     roles = frame._pvpRoles     },
            Arena        = { states = frame._pvpStates,     roles = frame._pvpRoles     },
        }
        local entry = stateMap[at]
        local needs = {}
        for i, state in ipairs(entry.states) do
            if state.val > 0 then
                needs[#needs + 1] = { role = entry.roles[i], count = state.val }
            end
        end
        if #needs == 0 then return end

        local difficulty = nil
        if at == "Dungeon" then
            difficulty = frame._dungeonDiffPicker and frame._dungeonDiffPicker.getValue()
        elseif at == "Raid" then
            difficulty = frame._raidDiffPicker and frame._raidDiffPicker.getValue()
        end

        local sendChat = frame._guildChatChk and frame._guildChatChk:GetChecked()
        GH.Recruit:Post(at, desc, needs, instanceName, sendChat ~= false, difficulty)
        descBox:SetText("")
        if frame._dungeonPicker then frame._dungeonPicker.reset() end
        if frame._raidPicker    then frame._raidPicker.reset()    end
        if frame._dungeonDiffPicker then frame._dungeonDiffPicker.setDefault("Mythic+") end
        if frame._raidDiffPicker    then frame._raidDiffPicker.setDefault("Mythic")     end
        UI:RefreshLFMList()
    end)

    -- ── Listings panel ────────────────────────────────────
    local lp = CreateFrame("Frame", nil, frame)
    lp:SetPoint("TOPLEFT",    pp,    "BOTTOMLEFT",  0,    -8)
    lp:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD,  34)
    S:GradientBg(lp, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 0.70,
        S.COLOR.PANEL[1],       S.COLOR.PANEL[2],       S.COLOR.PANEL[3],       0.35)

    S:Header(lp, "ACTIVE GROUPS"):SetPoint("TOPLEFT", lp, "TOPLEFT", 10, -10)

    -- Filter buttons
    local fLbl = S:FS(lp, "OVERLAY")
    fLbl:SetPoint("TOPLEFT", lp, "TOPLEFT", 120, -8)
    fLbl:SetText("Filter:")
    fLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    frame._filterBtns = {}
    local function RefreshFilterBtns()
        for _, fb in ipairs(frame._filterBtns) do
            if fb.key == frame._filter then
                fb.btn.bg:SetColorTexture(
                    S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.9)
                fb.btn.label:SetTextColor(1, 1, 1)
            else
                fb.btn.bg:SetColorTexture(
                    S.COLOR.PANEL[1]+0.04, S.COLOR.PANEL[2]+0.04, S.COLOR.PANEL[3]+0.06, 1)
                fb.btn.label:SetTextColor(
                    S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
            end
        end
    end

    local fAnchor = fLbl
    for _, ft in ipairs({ "All", "Dungeon", "Raid", "Battleground", "Arena" }) do
        local key = ft
        local bw  = (ft == "Battleground") and 102 or 58
        local fb  = S:Button(lp, ft, bw, 18)
        fb:SetPoint("LEFT", fAnchor, "RIGHT", 4, 0)
        fb:SetScript("OnClick", function()
            frame._filter = key
            RefreshFilterBtns()
            UI:RefreshLFMList()
        end)
        fAnchor = fb
        table.insert(frame._filterBtns, { btn = fb, key = key })
    end
    RefreshFilterBtns()

    local reBroadcastBtn = S:Button(lp, "|TInterface/Buttons/UI-RefreshButton:13:13:0:0|t Refresh", 96, 18)
    reBroadcastBtn:SetPoint("TOPRIGHT", lp, "TOPRIGHT", -8, -4)
    reBroadcastBtn:SetScript("OnClick", function()
        GH.Recruit:BroadcastAll()
        UI:RefreshLFMList()
    end)

    -- Column headers (lp-relative; scroll frame is at lp x=4)
    local HDR_Y = -38
    local function ColHdr(text, x, cw, just)
        local fs = S:FS(lp, "OVERLAY")
        fs:SetPoint("TOPLEFT", lp, "TOPLEFT", x, HDR_Y)
        fs:SetWidth(cw)
        fs:SetJustifyH(just or "LEFT")
        fs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        fs:SetText(text)
    end
    ColHdr("Type",              14,  80)
    ColHdr("Posted By",        98, 112)
    ColHdr("Instance / Note", 214, 218)
    ColHdr("Slots",           436,  76, "CENTER")
    ColHdr("Expires",         516,  58, "CENTER")

    -- Scroll frame (no template: avoids the broken square arrow buttons in WoW 12.x;
    -- mouse wheel scrolling is used instead).
    local sf = CreateFrame("ScrollFrame", nil, lp)
    sf:SetPoint("TOPLEFT",    lp, "TOPLEFT",    4,  HDR_Y - 18)
    sf:SetPoint("BOTTOMRIGHT", lp, "BOTTOMRIGHT", -8, 4)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(sf2, delta)
        local max = sf2:GetVerticalScrollRange()
        sf2:SetVerticalScroll(math.max(0, math.min(max,
            sf2:GetVerticalScroll() - delta * 32)))
    end)
    local listContent = CreateFrame("Frame", nil, sf)
    listContent:SetSize(sf:GetWidth() or 660, 10)
    sf:SetScrollChild(listContent)
    frame.lfmListContent = listContent

    -- Empty-state placeholder: a Frame child (not a bare FontString) so
    -- GetNumChildren()/GetChildren() can hide it along with row frames.
    local emptyHolder = CreateFrame("Frame", nil, listContent)
    emptyHolder:SetPoint("TOP", listContent, "TOP", 0, -20)
    emptyHolder:SetSize(400, 24)
    local emptyFS = S:FS(emptyHolder, "OVERLAY", "normal")
    emptyFS:SetAllPoints(emptyHolder)
    emptyFS:SetJustifyH("CENTER")
    emptyFS:SetText("No active groups. Post one above!")
    emptyFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    emptyHolder:Hide()
    frame.lfmEmptyHolder = emptyHolder

    -- ── Footer ────────────────────────────────────────────
    local lbBtn = S:Button(frame, "Leaderboard", 96, 22)
    lbBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 7)
    lbBtn:SetScript("OnClick", function() UI:ShowLeaderboardPanel() end)

    local footer = S:FS(frame, "OVERLAY")
    footer:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  PAD + 4, 12)
    footer:SetPoint("BOTTOMRIGHT", lbBtn, "BOTTOMLEFT",  -8,       0)
    footer:SetJustifyH("LEFT")
    footer:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame._footer = footer

    -- Re-auto-fill dungeon spinners whenever the party roster changes
    -- (e.g. a tank joins → Tank spinner drops to 0 automatically).
    local rosterEvtFrame = CreateFrame("Frame")
    rosterEvtFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rosterEvtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rosterEvtFrame:SetScript("OnEvent", function()
        local f = UI.LFMTab
        if f and f._selType == "Dungeon" and f._UpdateRoleSection then
            AutoFillDungeonSpinners(f)
        end
    end)

    -- Auto-refresh the listing every 30 seconds while the LFM tab is visible.
    local _autoRefreshElapsed = 0
    local autoRefreshFrame = CreateFrame("Frame")
    autoRefreshFrame:SetScript("OnUpdate", function(_, elapsed)
        if not (UI.LFMTab and UI.LFMTab:IsShown()) then return end
        _autoRefreshElapsed = _autoRefreshElapsed + elapsed
        if _autoRefreshElapsed >= 30 then
            _autoRefreshElapsed = 0
            GH.Recruit:CleanupExpired()
            UI:RefreshLFMList()
            RefreshApplicantsPanelIfOpen()
        end
    end)

    UI:RefreshLFMList()
end

-- ──────────────────────────────────────────────────────────
-- Refresh listings
-- ──────────────────────────────────────────────────────────

function UI:RefreshLFMList()
    local frame = UI.LFMTab
    if not frame or not frame.lfmListContent then return end

    HideSignupPopup()

    local content = frame.lfmListContent
    local filter  = frame._filter or "All"
    local me      = GH:GetPlayerName()

    -- Hide all Frame children (rows + emptyHolder)
    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    -- Filter posts
    local all   = GH.Recruit:GetAll()
    local posts = {}
    for _, p in ipairs(all) do
        if filter == "All" or p.activityType == filter then
            posts[#posts + 1] = p
        end
    end

    if #posts == 0 then
        frame.lfmEmptyHolder:Show()
        content:SetHeight(60)
        self:_RefreshLFMFooter()
        return
    end

    local ROW_H = 38
    local GAP   = 2

    for i, post in ipairs(posts) do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * (ROW_H + GAP))
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * (ROW_H + GAP))
        row:SetHeight(ROW_H)
        row:Show()

        if i % 2 == 0 then
            S:Bg(row, S.COLOR.PANEL_ALT[1], S.COLOR.PANEL_ALT[2], S.COLOR.PANEL_ALT[3], 0.55)
        end

        -- Activity colour bar
        local r, g, b = ActColor(post.activityType)
        local bar = row:CreateTexture(nil, "ARTWORK")
        bar:SetSize(4, ROW_H - 4)
        bar:SetPoint("LEFT", row, "LEFT", 0, 0)
        bar:SetColorTexture(r, g, b, 1)

        -- Column positions must leave room for the 64px action widget at x=572.
        -- Activity type
        local typeFS = S:FS(row, "OVERLAY")
        typeFS:SetPoint("LEFT", row, "LEFT", 10, 0)
        typeFS:SetWidth(80)
        typeFS:SetText(CC(post.activityType, r, g, b))

        -- Poster
        local posterFS = S:FS(row, "OVERLAY")
        posterFS:SetPoint("LEFT", row, "LEFT", 94, 0)
        posterFS:SetWidth(112)
        local pName = post.author
        if post.author == me then
            pName = pName .. CC(" (You)", S.COLOR.GREEN[1], S.COLOR.GREEN[2], S.COLOR.GREEN[3])
        end
        posterFS:SetText(pName)
        posterFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

        -- Description: instance name (gold) + optional note
        local descFS = S:FS(row, "OVERLAY")
        descFS:SetPoint("LEFT", row, "LEFT", 210, 0)
        descFS:SetWidth(218)
        if post.instanceName and post.instanceName ~= "" then
            local note = (post.body and post.body ~= "")
                and (CC("  · ", 0.40, 0.40, 0.50) .. post.body) or ""
            descFS:SetText(
                CC(post.instanceName, S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
                .. note)
        else
            descFS:SetText(post.body or "")
            descFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        end

        -- Slots summary
        local summary = SlotSummary(post)
        local slotFS  = S:FS(row, "OVERLAY")
        slotFS:SetPoint("LEFT", row, "LEFT", 432, 0)
        slotFS:SetWidth(76)
        slotFS:SetJustifyH("CENTER")
        if summary == "Full" then
            slotFS:SetText(CC("Full", S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3]))
        else
            slotFS:SetText(CC(summary, S.COLOR.GREEN[1], S.COLOR.GREEN[2], S.COLOR.GREEN[3]))
        end

        -- Age
        local ageFS = S:FS(row, "OVERLAY")
        ageFS:SetPoint("LEFT", row, "LEFT", 512, 0)
        ageFS:SetWidth(58)
        ageFS:SetJustifyH("CENTER")
        ageFS:SetText(TimeRemaining(post.ts))
        ageFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

        -- Action widget — anchored to RIGHT so it sits just inside the content edge.
        local pid = post.id
        if post.author == me then
            -- Row is clickable: click anywhere (except Cancel) to view signups.
            local captPost = post
            row:EnableMouse(true)
            row:SetScript("OnMouseDown", function(_, btn)
                if btn == "LeftButton" then ShowApplicantsPanel(captPost) end
            end)
            row:SetScript("OnEnter", function()
                if GameTooltip then
                    GameTooltip:SetOwner(row, "ANCHOR_TOP")
                    GameTooltip:SetText("Click to view signups", 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            local del = S:DangerButton(row, "Cancel", 62, 22)
            del:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            del:SetScript("OnClick", function()
                GH.Recruit:Delete(pid)
                UI:RefreshLFMList()
            end)
        elseif GH.Recruit:HasSignedUp(post) then
            local fs = S:FS(row, "OVERLAY")
            fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            fs:SetWidth(66)
            fs:SetJustifyH("CENTER")
            fs:SetText(CC("✓ Signed Up", S.COLOR.GREEN[1], S.COLOR.GREEN[2], S.COLOR.GREEN[3]))
        elseif GH.Recruit:TotalOpen(post) > 0 then
            local captPost = post
            local sig = S:Button(row, "Sign Up", 62, 22)
            sig:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            sig:SetScript("OnClick", function()
                ShowSignupPopup(pid, captPost, sig)
            end)
        else
            local fs = S:FS(row, "OVERLAY")
            fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            fs:SetWidth(66)
            fs:SetJustifyH("CENTER")
            fs:SetText(CC("Full", S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3]))
        end
    end

    content:SetHeight(math.max(#posts * (ROW_H + GAP), 10))
    self:_RefreshLFMFooter()
end

-- ──────────────────────────────────────────────────────────
-- Footer
-- ──────────────────────────────────────────────────────────

function UI:_RefreshLFMFooter()
    local frame = UI.LFMTab
    if not frame or not frame._footer then return end
    local pts = GH.DB:GetLFMPoints(GH:GetPlayerName())
    local ps  = GH.Recruit.POINTS_SIGNUP     or 5
    local pg  = GH.Recruit.POINTS_GOT_SIGNUP or 2
    frame._footer:SetText(
        "Guild Points: "
        .. CC(tostring(pts), S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        .. "  ·  +" .. ps .. " pts per signup"
        .. "  ·  +" .. pg .. " pts when someone joins your group")
end

-- ──────────────────────────────────────────────────────────
-- Callback from RecruitManager
-- ──────────────────────────────────────────────────────────

function UI:OnLFMUpdated()
    local win = self.window
    if win and win:IsShown() and win.activeTab == "LFM" then
        local f = UI.LFMTab
        if f and f._selType == "Dungeon" then AutoFillDungeonSpinners(f) end
        self:RefreshLFMList()
        RefreshApplicantsPanelIfOpen()
    end
end

-- ──────────────────────────────────────────────────────────
-- Guild Points Leaderboard panel
-- ──────────────────────────────────────────────────────────

function UI:ShowLeaderboardPanel()
    if _lbPanel and _lbPanel:IsShown() then
        _lbPanel:Hide()
        return
    end

    if not _lbPanel then
        _lbPanel = CreateFrame("Frame", "GHLFMLeaderboardPanel", UIParent)
        _lbPanel:SetFrameStrata("DIALOG")
        _lbPanel:SetSize(440, 520)
        _lbPanel:SetClampedToScreen(true)
        _lbPanel:SetPoint("TOPLEFT", UI.window, "TOPRIGHT", 10, 0)

        S:Bg(_lbPanel, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

        -- Gold top accent
        local acc = _lbPanel:CreateTexture(nil, "ARTWORK")
        acc:SetPoint("TOPLEFT"); acc:SetPoint("TOPRIGHT"); acc:SetHeight(2)
        acc:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.90)

        -- Title bar (drag handle)
        local titleBar = CreateFrame("Frame", nil, _lbPanel)
        titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT"); titleBar:SetHeight(38)
        S:Bg(titleBar, 0.04, 0.04, 0.08, 1)

        local titleFS = S:FS(titleBar, "OVERLAY", "large")
        titleFS:SetPoint("CENTER", titleBar, "CENTER", -14, 0)
        titleFS:SetText("Guild Points Leaderboard")
        titleFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

        local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 2, 0)
        closeBtn:SetSize(28, 28)
        closeBtn:SetScript("OnClick", function() _lbPanel:Hide() end)

        -- Column headers
        local function LbHdr(text, xOff, cw, just)
            local fs = S:FS(_lbPanel, "OVERLAY")
            fs:SetPoint("TOPLEFT", _lbPanel, "TOPLEFT", xOff, -44)
            fs:SetWidth(cw)
            fs:SetJustifyH(just or "LEFT")
            fs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
            fs:SetText(text)
        end
        LbHdr("#",       12,  32)
        LbHdr("Name",    50, 172)
        LbHdr("Points", 230,  74, "RIGHT")
        LbHdr("Class",  316, 110)

        -- Divider under headers
        local div = _lbPanel:CreateTexture(nil, "ARTWORK")
        div:SetPoint("TOPLEFT",  _lbPanel, "TOPLEFT",  6, -58)
        div:SetPoint("TOPRIGHT", _lbPanel, "TOPRIGHT", -6, -58)
        div:SetHeight(1)
        div:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.7)

        -- Scroll frame
        local sf = CreateFrame("ScrollFrame", nil, _lbPanel)
        sf:SetPoint("TOPLEFT",     _lbPanel, "TOPLEFT",     4, -60)
        sf:SetPoint("BOTTOMRIGHT", _lbPanel, "BOTTOMRIGHT", -4, 38)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self2, delta)
            local max = self2:GetVerticalScrollRange()
            self2:SetVerticalScroll(
                math.max(0, math.min(max, self2:GetVerticalScroll() - delta * 28)))
        end)

        local lbContent = CreateFrame("Frame", nil, sf)
        lbContent:SetSize(430, 10)
        sf:SetScrollChild(lbContent)
        _lbPanel._content = lbContent

        -- Footer
        local footerFS = S:FS(_lbPanel, "OVERLAY")
        footerFS:SetPoint("BOTTOMLEFT",  _lbPanel, "BOTTOMLEFT",  10, 12)
        footerFS:SetPoint("BOTTOMRIGHT", _lbPanel, "BOTTOMRIGHT", -10, 12)
        footerFS:SetJustifyH("CENTER")
        footerFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        _lbPanel._footer = footerFS
    end

    -- ── Populate ──────────────────────────────────────────
    local me      = GH:GetPlayerName()
    local allPts  = GH.DB:GetAllLFMPoints()
    local content = _lbPanel._content

    -- Hide previous rows
    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    -- Build sorted list (only players with at least 1 point)
    local list = {}
    for name, pts in pairs(allPts) do
        if (pts or 0) > 0 then
            list[#list + 1] = { name = name, pts = pts }
        end
    end
    table.sort(list, function(a, b)
        return a.pts ~= b.pts and a.pts > b.pts or a.name < b.name
    end)

    if #list == 0 then
        local holder = CreateFrame("Frame", nil, content)
        holder:SetPoint("TOP", content, "TOP", 0, -20)
        holder:SetSize(400, 24)
        holder:Show()
        local fs = S:FS(holder, "OVERLAY", "normal")
        fs:SetAllPoints()
        fs:SetJustifyH("CENTER")
        fs:SetText("No guild points earned yet.")
        fs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        content:SetHeight(60)
        _lbPanel._footer:SetText(
            CC("+" .. (GH.Recruit.POINTS_SIGNUP or 5) .. " pts",
               S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
            .. " per signup  ·  "
            .. CC("+" .. (GH.Recruit.POINTS_GOT_SIGNUP or 2) .. " pts",
               S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
            .. " when someone joins your group")
        _lbPanel:Show()
        _lbPanel:Raise()
        return
    end

    local ROW_H = 30
    local GAP   = 1
    local myRank = nil

    for i, entry in ipairs(list) do
        if entry.name == me then myRank = i end

        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * (ROW_H + GAP))
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * (ROW_H + GAP))
        row:SetHeight(ROW_H)
        row:Show()

        -- Row background
        if entry.name == me then
            S:Bg(row, S.COLOR.NAV_ACTIVE[1], S.COLOR.NAV_ACTIVE[2], S.COLOR.NAV_ACTIVE[3], 0.28)
        elseif i % 2 == 0 then
            S:Bg(row, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.55)
        end

        local mc = i <= 3 and MEDAL_COLORS[i] or nil

        -- Left accent bar for top 3
        if mc then
            local bar = row:CreateTexture(nil, "ARTWORK")
            bar:SetSize(3, ROW_H - 6)
            bar:SetPoint("LEFT", row, "LEFT", 0, 0)
            bar:SetColorTexture(mc[1], mc[2], mc[3], 0.90)
        end

        -- Rank
        local rankFS = S:FS(row, "OVERLAY", "normal")
        rankFS:SetPoint("LEFT", row, "LEFT", 8, 0)
        rankFS:SetWidth(32)
        rankFS:SetJustifyH("CENTER")
        if mc then
            rankFS:SetText(CC(tostring(i), mc[1], mc[2], mc[3]))
        else
            rankFS:SetText(tostring(i))
            rankFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end

        -- Name
        local nameFS = S:FS(row, "OVERLAY", "normal")
        nameFS:SetPoint("LEFT", row, "LEFT", 46, 0)
        nameFS:SetWidth(172)
        local suffix = entry.name == me and CC(" (You)", S.COLOR.GREEN[1], S.COLOR.GREEN[2], S.COLOR.GREEN[3]) or ""
        if mc then
            nameFS:SetText(CC(entry.name, mc[1], mc[2], mc[3]) .. (entry.name == me and CC(" (You)", 0.6, 0.9, 0.6) or ""))
        else
            nameFS:SetText(entry.name .. suffix)
            nameFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        end

        -- Points
        local ptsFS = S:FS(row, "OVERLAY", "normal")
        ptsFS:SetPoint("LEFT", row, "LEFT", 226, 0)
        ptsFS:SetWidth(74)
        ptsFS:SetJustifyH("RIGHT")
        if mc then
            ptsFS:SetText(CC(tostring(entry.pts), mc[1], mc[2], mc[3]))
        else
            ptsFS:SetText(tostring(entry.pts))
            ptsFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        end

        -- Class (from local roster cache)
        local member = GH.GuildData and GH.GuildData.byName and GH.GuildData.byName[entry.name]
        if member and member.class then
            local classFS = S:FS(row, "OVERLAY")
            classFS:SetPoint("LEFT", row, "LEFT", 312, 0)
            classFS:SetWidth(110)
            classFS:SetText(member.class)
            classFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end
    end

    content:SetHeight(math.max(#list * (ROW_H + GAP), 10))

    local myPts = GH.DB:GetLFMPoints(me)
    local footerParts = {
        "Your points: " .. CC(tostring(myPts),
            S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3]),
    }
    if myRank then
        footerParts[#footerParts + 1] = "Rank: " .. CC(
            "#" .. myRank .. " of " .. #list,
            S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    end
    _lbPanel._footer:SetText(table.concat(footerParts, "   ·   "))

    _lbPanel:Show()
    _lbPanel:Raise()
end
