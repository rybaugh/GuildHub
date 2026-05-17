-- GuildHub - UI Styles  (Midnight Forge design system)
-- Centralised colour/size constants and component factories.

local GH = GuildHub
GH.Styles = {}
local S = GH.Styles

-- ── Colour palette ────────────────────────────────────────────────────────
-- All values are (r, g, b [, a]) in [0,1] float space.
-- Background: deep charcoal with a hint of warm slate — avoids the cold
-- "Discord clone" look while staying very dark for readability.
S.COLOR = {
    BG          = { 0.055, 0.052, 0.088, 0.98 },  -- deep warm charcoal
    SIDEBAR     = { 0.034, 0.032, 0.064, 1.00 },  -- near-black with slate tint
    PANEL       = { 0.085, 0.082, 0.140, 1.00 },  -- purple-charcoal content cards
    PANEL_ALT   = { 0.110, 0.106, 0.172, 1.00 },  -- lighter alternating row
    PANEL_HOVER = { 0.145, 0.140, 0.230, 1.00 },  -- hover state
    BORDER      = { 0.220, 0.210, 0.360, 0.70 },  -- subtle cool border
    BORDER_GOLD = { 0.600, 0.480, 0.160, 0.60 },  -- warm gold border accent
    ACCENT      = { 0.340, 0.510, 1.000, 1.00 },  -- electric sapphire
    ACCENT_DIM  = { 0.220, 0.340, 0.720, 1.00 },  -- muted sapphire (inactive)
    GOLD        = { 0.960, 0.800, 0.220, 1.00 },  -- rich WoW gold
    TEXT        = { 0.920, 0.918, 0.950, 1.00 },  -- near-white, cool-neutral
    TEXT_DIM    = { 0.480, 0.472, 0.580, 1.00 },  -- muted label text
    TEXT_GOLD   = { 0.980, 0.830, 0.260, 1.00 },  -- gold headings
    TEXT_ACCENT = { 0.560, 0.680, 1.000, 1.00 },  -- accent-tinted text
    ONLINE      = { 0.220, 0.900, 0.440, 1.00 },  -- vivid emerald green
    OFFLINE     = { 0.360, 0.355, 0.420, 1.00 },  -- muted steel
    AFK         = { 0.940, 0.720, 0.140, 1.00 },  -- warm amber
    DND         = { 0.920, 0.220, 0.220, 1.00 },  -- vivid red
    GREEN       = { 0.220, 0.840, 0.440, 1.00 },
    RED         = { 0.880, 0.210, 0.210, 1.00 },
    INPUT_BG    = { 0.050, 0.048, 0.090, 1.00 },  -- very dark input well
    SCROLLBAR   = { 0.200, 0.195, 0.340, 0.80 },
    NAV_ACTIVE  = { 0.130, 0.250, 0.600, 1.00 },  -- deep sapphire nav active
    TITLE_TOP   = { 0.025, 0.024, 0.055, 1.00 },  -- title bar gradient top
    TITLE_BOT   = { 0.042, 0.040, 0.078, 1.00 },  -- title bar gradient bottom
    PANEL_HDR_T = { 0.100, 0.095, 0.175, 1.00 },  -- panel header gradient top
    PANEL_HDR_B = { 0.070, 0.068, 0.120, 1.00 },  -- panel header gradient bottom
}

S.WINDOW_W    = 1120   -- default width  (saved per-account in DB)
S.WINDOW_H    = 660    -- default height (saved per-account in DB)
S.SIDEBAR_W   = 155
S.TITLEBAR_H  = 36
S.BANNER_H    = 28
S.INVITE_BAR_H = 30
S.ROW_H       = 34

-- ── Gradient helper ───────────────────────────────────────────────────────
-- Applies a two-stop gradient to a new BACKGROUND texture on `frame`.
-- `orient` = "VERTICAL" or "HORIZONTAL".
--
-- SetGradient applies vertex colors to an existing texture — it needs a white
-- base image (Interface/Buttons/WHITE8X8) or the result is fully transparent.
-- If the gradient API is unavailable or throws, falls back to a solid fill
-- using the start color so the frame is never accidentally transparent.
function S:GradientBg(frame, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()

    local gradOk = false
    pcall(function()
        -- White base texture required for SetGradient vertex colouring.
        t:SetTexture("Interface/Buttons/WHITE8X8")
        t:SetGradient(orient,
            CreateColor(r1, g1, b1, a1 or 1),
            CreateColor(r2, g2, b2, a2 or 1))
        gradOk = true
    end)

    if not gradOk then
        -- Fallback: solid colour — always opaque and always visible.
        t:SetColorTexture(r1, g1, b1, a1 or 1)
    end

    return t
end

-- ── Solid background ──────────────────────────────────────────────────────
function S:Bg(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- ── Border (four 1-px hairline edges) ────────────────────────────────────
function S:Border(frame, r, g, b, a)
    local c = { r or S.COLOR.BORDER[1], g or S.COLOR.BORDER[2],
                b or S.COLOR.BORDER[3], a or S.COLOR.BORDER[4] }
    local w, h = frame:GetSize()
    local function edge(pt, ew, eh)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetSize(ew, eh)
        t:SetPoint(pt)
        t:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    edge("TOPLEFT",     w, 1)
    edge("BOTTOMLEFT",  w, 1)
    edge("TOPLEFT",  1, h)
    edge("TOPRIGHT", 1, h)
end

-- ── Gold-tinted accent border (panels / dialogs) ──────────────────────────
-- Creates a two-layer border: subtle inner glow + hairline outer edge.
function S:AccentBorder(frame)
    -- Outer hairline in the standard border colour
    self:Border(frame)

    -- Top accent stripe (2 px, gold-gradient) for visual "lift"
    local stripe = frame:CreateTexture(nil, "OVERLAY")
    stripe:SetPoint("TOPLEFT",  frame, "TOPLEFT",  1, -1)
    stripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    stripe:SetHeight(2)
    local ok = pcall(function()
        stripe:SetGradient("HORIZONTAL",
            CreateColor(S.COLOR.BORDER_GOLD[1], S.COLOR.BORDER_GOLD[2], S.COLOR.BORDER_GOLD[3], 0),
            CreateColor(S.COLOR.BORDER_GOLD[1], S.COLOR.BORDER_GOLD[2], S.COLOR.BORDER_GOLD[3], 0.45))
    end)
    if not ok then
        stripe:SetColorTexture(S.COLOR.BORDER_GOLD[1], S.COLOR.BORDER_GOLD[2],
                               S.COLOR.BORDER_GOLD[3], 0.30)
    end
end

-- ── Horizontal divider line ───────────────────────────────────────────────
function S:HLine(parent, w)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(w or 200, 1)
    t:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
    return t
end

-- Gradient fade-out divider (opaque centre → transparent edges).
function S:FadeDivider(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    local ok = pcall(function()
        t:SetGradient("HORIZONTAL",
            CreateColor(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0),
            CreateColor(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.55))
    end)
    if not ok then
        t:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.35)
    end
    return t
end

-- ── Section header font string ────────────────────────────────────────────
function S:Header(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(S.FontSmall)
    fs:SetText(text or "")
    fs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    return fs
end

-- Panel section label: small-caps gold text with a slim underline rule.
function S:SectionLabel(parent, text, xOff, yOff)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(S.FontSmall)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff or 10, yOff or -10)
    fs:SetText(text or "")
    fs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT",  fs, "BOTTOMLEFT",  0,  -3)
    rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(xOff or 10),
        select(2, fs:GetPoint(1)) - fs:GetHeight() - 3)
    rule:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.20)
    return fs
end

-- ── Standard interactive button ───────────────────────────────────────────
-- Returns a Button with .bg (texture) and .label (FontString) fields.
-- Hover: brightens background + adds a subtle shimmer.
function S:Button(parent, text, w, h)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w or 120, h or 28)

    -- Background: solid fill (games don't use gradients on small buttons)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.82)
    btn.bg = bg

    -- Top highlight shimmer (very subtle, gives a slight 3-D lift)
    local shimmer = btn:CreateTexture(nil, "ARTWORK")
    shimmer:SetPoint("TOPLEFT")
    shimmer:SetPoint("TOPRIGHT")
    shimmer:SetHeight(math.max(1, math.floor((h or 28) * 0.35)))
    local sok = pcall(function()
        shimmer:SetGradient("VERTICAL",
            CreateColor(1, 1, 1, 0.08),
            CreateColor(1, 1, 1, 0))
    end)
    if not sok then shimmer:SetColorTexture(1, 1, 1, 0.05) end
    btn.shimmer = shimmer

    -- Label
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(S.FontSmall)
    label:SetAllPoints()
    label:SetText(text or "")
    label:SetTextColor(1, 1, 1, 1)
    btn.label = label

    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.52, 0.66, 1.00, 0.95)
        self.label:SetTextColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.82)
        self.label:SetTextColor(1, 1, 1, 1)
    end)
    return btn
end

-- ── Danger (destructive) button ───────────────────────────────────────────
function S:DangerButton(parent, text, w, h)
    local btn = self:Button(parent, text, w, h)
    btn.bg:SetColorTexture(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3], 0.82)
    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1.0, 0.38, 0.38, 0.95)
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3], 0.82)
    end)
    return btn
end

-- ── Single-line edit box ──────────────────────────────────────────────────
function S:EditBox(parent, w, h, maxLetters)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(w or 200, h or 26)
    eb:SetFontObject(S.FontSmall)
    eb:SetAutoFocus(false)
    if h and h > 26 then eb:SetMultiLine(true) end
    eb:SetMaxLetters(maxLetters or 255)
    eb:SetTextInsets(8, 8, 6, 6)

    -- Dark input well with gradient
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)

    -- Border
    local border = eb:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.60)
    bg:SetPoint("TOPLEFT",     1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)

    -- Subtle top line to indicate input field
    local topLine = eb:CreateTexture(nil, "OVERLAY")
    topLine:SetPoint("TOPLEFT",  1, -1)
    topLine:SetPoint("TOPRIGHT", -1, -1)
    topLine:SetHeight(1)
    topLine:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.25)

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

-- ── Dropdown selector ─────────────────────────────────────────────────────
-- options: array of { label = string, value = any }
-- Returns a button-like frame. Interface:
--   .GetIndex()          → current 1-based index
--   .GetValue()          → options[idx].value
--   .GetLabel()          → options[idx].label
--   .SetOptions(newOpts) → replace list, reset to index 1
--   .Reset()             → reset to index 1
--   .onChange            → optional function(idx, value) fired on selection
function S:Dropdown(parent, options, w, h)
    w = w or 174
    h = h or 26

    local current = 1
    local opts    = options

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.82)
    btn.bg = bg

    local shimmer = btn:CreateTexture(nil, "ARTWORK")
    shimmer:SetPoint("TOPLEFT")
    shimmer:SetPoint("TOPRIGHT")
    shimmer:SetHeight(math.max(1, math.floor(h * 0.35)))
    local sok = pcall(function()
        shimmer:SetGradient("VERTICAL",
            CreateColor(1, 1, 1, 0.08), CreateColor(1, 1, 1, 0))
    end)
    if not sok then shimmer:SetColorTexture(1, 1, 1, 0.05) end
    btn.shimmer = shimmer

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(S.FontSmall)
    label:SetPoint("LEFT",  btn, "LEFT",   8,   0)
    label:SetPoint("RIGHT", btn, "RIGHT", -20,  0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(1, 1, 1, 1)
    btn.label = label

    local chevron = btn:CreateFontString(nil, "OVERLAY")
    chevron:SetFontObject(S.FontSmall)
    chevron:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    chevron:SetText("\226\150\190")  -- ▾ (UTF-8 bytes: E2 96 BE)
    chevron:SetTextColor(1, 1, 1, 0.65)

    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.52, 0.66, 1.00, 0.95)
        self.label:SetTextColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.82)
        self.label:SetTextColor(1, 1, 1, 1)
    end)

    -- Popup (UIParent-parented so it floats above the dialog)
    local popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(10)
    popup:SetClampedToScreen(true)
    popup:Hide()

    -- Border layer (drawn first so bg sits inside it)
    local popupBorder = popup:CreateTexture(nil, "BORDER")
    popupBorder:SetAllPoints()
    popupBorder:SetColorTexture(
        S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.7)

    local popupBg = popup:CreateTexture(nil, "BACKGROUND")
    popupBg:SetPoint("TOPLEFT",     1, -1)
    popupBg:SetPoint("BOTTOMRIGHT", -1,  1)
    popupBg:SetColorTexture(
        S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)

    -- Intercept: full-screen invisible frame at DIALOG-9, closes popup on outside click
    local intercept = CreateFrame("Frame", nil, UIParent)
    intercept:SetAllPoints(UIParent)
    intercept:SetFrameStrata("DIALOG")
    intercept:SetFrameLevel(9)
    intercept:EnableMouse(true)
    intercept:Hide()
    intercept:SetScript("OnMouseDown", function()
        popup:Hide()
        intercept:Hide()
    end)

    local ROW_H = 22
    local rows  = {}

    local function Refresh()
        label:SetText(opts[current] and opts[current].label or "")
    end

    local function RebuildRows()
        for _, r in ipairs(rows) do
            r:SetParent(nil)
            r:Hide()
        end
        rows = {}
        if #opts == 0 then
            popup:SetSize(w, 0)
            return
        end
        popup:SetSize(w, ROW_H * #opts)
        for i, opt in ipairs(opts) do
            local row = CreateFrame("Button", nil, popup)
            row:SetPoint("TOPLEFT",  popup, "TOPLEFT",  0, -(i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, -(i - 1) * ROW_H)
            row:SetHeight(ROW_H)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(0, 0, 0, 0)

            local rowLabel = row:CreateFontString(nil, "OVERLAY")
            rowLabel:SetFontObject(S.FontSmall)
            rowLabel:SetPoint("LEFT",  row, "LEFT",   8, 0)
            rowLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            rowLabel:SetJustifyH("LEFT")
            rowLabel:SetText(opt.label)
            rowLabel:SetTextColor(1, 1, 1, 1)

            row:SetScript("OnEnter", function()
                rowBg:SetColorTexture(
                    S.COLOR.NAV_ACTIVE[1], S.COLOR.NAV_ACTIVE[2], S.COLOR.NAV_ACTIVE[3], 0.6)
            end)
            row:SetScript("OnLeave", function()
                rowBg:SetColorTexture(0, 0, 0, 0)
            end)

            local capturedIdx = i
            row:SetScript("OnClick", function()
                current = capturedIdx
                Refresh()
                popup:Hide()
                intercept:Hide()
                if btn.onChange then btn.onChange(current, opts[current].value) end
            end)

            rows[i] = row
        end
    end

    RebuildRows()
    Refresh()

    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
            intercept:Hide()
        else
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            popup:Show()
            intercept:Show()
        end
    end)

    btn.GetIndex   = function() return current end
    btn.GetValue   = function() return opts[current] and opts[current].value end
    btn.GetLabel   = function() return opts[current] and opts[current].label or "" end
    btn.SetOptions = function(newOpts)
        opts    = newOpts
        current = 1
        RebuildRows()
        Refresh()
    end
    btn.Reset = function()
        current = 1
        Refresh()
    end

    return btn
end

-- ── Scrollable read-only text area ───────────────────────────────────────
function S:ScrollText(parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetSize(w, h)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(w - 20, h)
    sf:SetScrollChild(content)
    local text = content:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(S.FontSmall)
    text:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    text:SetWidth(w - 30)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    sf.textContent = text
    sf.contentFrame = content
    return sf
end

-- ── Status glow dot ───────────────────────────────────────────────────────
-- Returns a small circular indicator texture with a soft outer glow ring.
-- Pass the parent frame and the pixel size (default 8).
-- Call :SetStatus("online" | "offline" | "afk" | "dnd") to recolour.
function S:StatusDot(parent, size)
    size = size or 8
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(size + 4, size + 4)

    -- Outer glow ring (larger, more transparent)
    local glow = container:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(size + 4, size + 4)
    glow:SetAllPoints()
    glow:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 0.18)
    container.glow = glow

    -- Inner solid dot
    local dot = container:CreateTexture(nil, "ARTWORK")
    dot:SetSize(size, size)
    dot:SetPoint("CENTER")
    dot:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 1)
    container.dot = dot

    function container:SetStatus(status)
        local r, g, b
        if     status == "online"  then r, g, b = S.COLOR.ONLINE[1],  S.COLOR.ONLINE[2],  S.COLOR.ONLINE[3]
        elseif status == "afk"     then r, g, b = S.COLOR.AFK[1],     S.COLOR.AFK[2],     S.COLOR.AFK[3]
        elseif status == "dnd"     then r, g, b = S.COLOR.DND[1],     S.COLOR.DND[2],     S.COLOR.DND[3]
        else                            r, g, b = S.COLOR.OFFLINE[1],  S.COLOR.OFFLINE[2],  S.COLOR.OFFLINE[3]
        end
        dot:SetColorTexture(r, g, b, status == "offline" and 0.55 or 1)
        glow:SetColorTexture(r, g, b, status == "offline" and 0 or 0.18)
    end

    return container
end

-- ── Panel header bar (gradient, used for "POST A GROUP" etc.) ─────────────
-- Draws a gradient header band as a child of `parent`, anchored to its top.
-- Returns the header frame so callers can anchor content inside.
function S:PanelHeader(parent, height)
    height = height or 36
    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetPoint("TOPLEFT",  parent, "TOPLEFT")
    hdr:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    hdr:SetHeight(height)

    self:GradientBg(hdr, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL_HDR_B[1], S.COLOR.PANEL_HDR_B[2], S.COLOR.PANEL_HDR_B[3], 1)

    -- Bottom separator
    local sep = hdr:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("BOTTOMLEFT",  hdr, "BOTTOMLEFT")
    sep:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT")
    sep:SetHeight(1)
    sep:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.55)

    return hdr
end

-- ── Shared font objects ───────────────────────────────────────────────────
-- Created at module load; sized by S:ApplyFontSize() before any UI builds.
-- All UI font strings reference these via SetFontObject so a single
-- ApplyFontSize call updates every font string live.
S.FontSmall  = CreateFont("GuildHubFontSmall")
S.FontNormal = CreateFont("GuildHubFontNormal")
S.FontLarge  = CreateFont("GuildHubFontLarge")
do
    local path, _, flags = GameFontNormal:GetFont()
    path  = path  or "Fonts\\FRIZQT__.TTF"
    flags = flags or ""
    S.FontSmall:SetFont(path,  10, flags)
    S.FontNormal:SetFont(path, 12, flags)
    S.FontLarge:SetFont(path,  14, flags)
end

-- Apply a new base size to all three tiers.
-- FontSmall = baseSize, FontNormal = baseSize+2, FontLarge = baseSize+4.
-- Font path is derived from WoW's built-in GameFontNormal to respect locale.
function S:ApplyFontSize(baseSize)
    local path, _, flags = GameFontNormal:GetFont()
    path  = path  or "Fonts\\FRIZQT__.TTF"
    flags = flags or ""
    self.FontSmall:SetFont(path,  baseSize,     flags)
    self.FontNormal:SetFont(path, baseSize + 2, flags)
    self.FontLarge:SetFont(path,  baseSize + 4, flags)
end

-- Factory helper: create a font string and assign the correct font tier.
-- tier: "small" (default, 10pt at default size)
--       "normal" (12pt at default size)
--       "large"  (14pt at default size)
function S:FS(parent, layer, tier)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    if     tier == "normal" then fs:SetFontObject(self.FontNormal)
    elseif tier == "large"  then fs:SetFontObject(self.FontLarge)
    else                         fs:SetFontObject(self.FontSmall)
    end
    return fs
end
