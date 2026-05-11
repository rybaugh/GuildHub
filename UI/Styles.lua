-- GuildHub - UI Styles
-- Centralised colour/size constants used across all UI frames.

local GH = GuildHub
GH.Styles = {}
local S = GH.Styles

-- Colours (r, g, b, a)
S.COLOR = {
    BG          = { 0.06, 0.06, 0.10, 0.97 },  -- main window background
    SIDEBAR     = { 0.04, 0.04, 0.08, 1.00 },  -- left nav panel
    PANEL       = { 0.10, 0.10, 0.16, 1.00 },  -- content cards / rows
    PANEL_HOVER = { 0.16, 0.16, 0.26, 1.00 },
    BORDER      = { 0.25, 0.25, 0.40, 0.80 },
    ACCENT      = { 0.42, 0.54, 0.85, 1.00 },  -- blue highlight
    GOLD        = { 0.85, 0.65, 0.13, 1.00 },  -- WoW gold
    TEXT        = { 0.90, 0.90, 0.92, 1.00 },
    TEXT_DIM    = { 0.55, 0.55, 0.65, 1.00 },
    TEXT_GOLD   = { 0.95, 0.80, 0.30, 1.00 },
    ONLINE      = { 0.20, 0.88, 0.30, 1.00 },
    OFFLINE     = { 0.40, 0.40, 0.45, 1.00 },
    AFK         = { 0.85, 0.65, 0.10, 1.00 },
    DND         = { 0.90, 0.25, 0.25, 1.00 },
    GREEN       = { 0.20, 0.80, 0.35, 1.00 },
    RED         = { 0.85, 0.25, 0.25, 1.00 },
    INPUT_BG    = { 0.08, 0.08, 0.14, 1.00 },
    SCROLLBAR   = { 0.20, 0.20, 0.35, 0.80 },
    NAV_ACTIVE  = { 0.18, 0.30, 0.60, 1.00 },
}

S.WINDOW_W   = 960
S.WINDOW_H   = 580
S.SIDEBAR_W  = 155
S.TITLEBAR_H = 36
S.BANNER_H   = 28
S.ROW_H      = 34

-- Apply a solid colour background texture to a frame.
function S:Bg(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- Apply a 1-pixel border around a frame using four thin textures.
function S:Border(frame, r, g, b, a)
    local c = { r or 0.25, g or 0.25, b or 0.40, a or 0.80 }
    local width, height = frame:GetSize()
    local function edge(point, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetSize(w, h)
        t:SetPoint(point)
        t:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    edge("TOPLEFT",     width, 1)
    edge("BOTTOMLEFT",  width, 1)
    edge("TOPLEFT",  1, height)
    edge("TOPRIGHT", 1, height)
end

-- Create a simple button with hover effect.
function S:Button(parent, text, w, h)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w or 120, h or 28)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.85)
    btn.bg = bg
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints()
    label:SetText(text or "")
    label:SetTextColor(1, 1, 1, 1)
    btn.label = label
    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.55, 0.65, 1.0, 0.95)
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.85)
    end)
    return btn
end

-- Create a destructive (red) action button.
function S:DangerButton(parent, text, w, h)
    local btn = self:Button(parent, text, w, h)
    btn.bg:SetColorTexture(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3], 0.85)
    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1.0, 0.40, 0.40, 0.95)
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3], 0.85)
    end)
    return btn
end

-- Create a labelled single-line edit box.
function S:EditBox(parent, w, h, maxLetters)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(w or 200, h or 26)
    eb:SetFontObject("GameFontNormalSmall")
    eb:SetAutoFocus(false)
    if h and h > 26 then
        eb:SetMultiLine(true)
    end
    eb:SetMaxLetters(maxLetters or 255)
    eb:SetTextInsets(8, 8, 6, 6)
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)
    local border = eb:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.6)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

-- Create a scrollable text area (read-only).
function S:ScrollText(parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetSize(w, h)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(w - 20, h)
    sf:SetScrollChild(content)
    local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    text:SetWidth(w - 30)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    sf.textContent = text
    sf.contentFrame = content
    return sf
end

-- Divider line texture.
function S:HLine(parent, w)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(w or 200, 1)
    t:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
    return t
end

-- Section header font string.
function S:Header(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text or "")
    fs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    return fs
end
