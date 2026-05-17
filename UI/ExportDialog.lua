-- GuildHub - ExportDialog
-- CSV export tool for guild member data. Supports current members,
-- former members (from activity log), and the raw activity log itself.
-- Output appears in a read-only editbox for manual copy-paste.

local GH  = GuildHub
local S   = GH.Styles
local UI  = GH.UI

local DIALOG_W = 540
local DIALOG_H = 460

-- ── Public entry point ────────────────────────────────────────────────────────

function UI:ShowExportDialog()
    local dlg = rawget(_G, "GuildHubExportDialog")
    if dlg then
        dlg:Show()
        return
    end

    dlg = CreateFrame("Frame", "GuildHubExportDialog", UIParent)
    dlg:SetSize(DIALOG_W, DIALOG_H)
    dlg:SetPoint("CENTER")
    dlg:SetFrameStrata("DIALOG")
    dlg:SetMovable(true)
    dlg:SetClampedToScreen(true)
    dlg:EnableMouse(true)
    dlg:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    dlg:SetScript("OnMouseUp",   function(self) self:StopMovingOrSizing() end)
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
    S:Border(dlg)
    tinsert(UISpecialFrames, "GuildHubExportDialog")

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, dlg)
    titleBar:SetPoint("TOPLEFT",  dlg, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", dlg, "TOPRIGHT")
    titleBar:SetHeight(36)
    S:Bg(titleBar, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    local titleFS = S:FS(titleBar, "OVERLAY", "large")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
    titleFS:SetText("Export")
    titleFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 2, 0)
    closeBtn:SetScript("OnClick", function() dlg:Hide() end)

    -- ── Options area ──────────────────────────────────────────────────────────
    local optFrame = CreateFrame("Frame", nil, dlg)
    optFrame:SetPoint("TOPLEFT",  dlg, "TOPLEFT",  12, -44)
    optFrame:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -12, -44)
    optFrame:SetHeight(110)
    S:Bg(optFrame, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.45)

    -- Scope selector
    local scopeLabel = S:FS(optFrame, "OVERLAY")
    scopeLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 10, -8)
    scopeLabel:SetText("Export:")
    scopeLabel:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

    local SCOPES = { "Current Members", "Activity Log" }
    local scopeSel = 1
    local scopeBtns = {}

    local bx = 60
    for i, sc_name in ipairs(SCOPES) do
        local btn = S:Button(optFrame, sc_name, 120, 22)
        btn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", bx, -5)
        bx = bx + 126

        local captI = i
        btn:SetScript("OnClick", function()
            scopeSel = captI
            for j, b in ipairs(scopeBtns) do
                if j == scopeSel then
                    b.bg:SetColorTexture(
                        S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.9)
                else
                    b.bg:SetColorTexture(
                        S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.8)
                end
            end
        end)
        scopeBtns[i] = btn
    end
    -- Mark first as selected
    scopeBtns[1].bg:SetColorTexture(
        S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.9)

    -- Delimiter selector
    local delimLabel = S:FS(optFrame, "OVERLAY")
    delimLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 10, -36)
    delimLabel:SetText("Delimiter:")
    delimLabel:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

    local DELIMS = { { label = "Comma", char = "," }, { label = "Tab", char = "\t" },
                     { label = "Pipe",  char = "|" } }
    local delimSel = 1
    local delimBtns = {}
    local dx = 82
    for i, dm in ipairs(DELIMS) do
        local btn = S:Button(optFrame, dm.label, 68, 22)
        btn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", dx, -33)
        dx = dx + 74
        local captI = i
        btn:SetScript("OnClick", function()
            delimSel = captI
            for j, b in ipairs(delimBtns) do
                if j == delimSel then
                    b.bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.9)
                else
                    b.bg:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.8)
                end
            end
        end)
        delimBtns[i] = btn
    end
    delimBtns[1].bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.9)

    -- Field checkboxes
    local FIELDS = {
        { key = "name",     label = "Name",        def = true  },
        { key = "rank",     label = "Rank",        def = true  },
        { key = "level",    label = "Level",       def = true  },
        { key = "class",    label = "Class",       def = true  },
        { key = "joinDate", label = "Join Date",   def = true  },
        { key = "rankHist", label = "Last Promo",  def = false },
        { key = "note",     label = "Cust. Note",  def = true  },
        { key = "alts",     label = "Alts",        def = false },
        { key = "birthday", label = "Birthday",    def = false },
        { key = "score",    label = "M+ Score",    def = true  },
        { key = "banned",   label = "Ban Status",  def = false },
    }
    local fieldChecked = {}
    for _, f in ipairs(FIELDS) do fieldChecked[f.key] = f.def end

    local cbY = -62
    local cbX = 10
    for i, f in ipairs(FIELDS) do
        local cb = CreateFrame("CheckButton", nil, optFrame, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        cb:SetPoint("TOPLEFT", optFrame, "TOPLEFT", cbX, cbY)
        cb:SetChecked(f.def)
        local lbl = S:FS(optFrame, "OVERLAY")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(f.label)
        lbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        cbX = cbX + 88
        if cbX > 460 then cbX = 10; cbY = cbY - 22 end

        local captKey = f.key
        cb:SetScript("OnClick", function(self)
            fieldChecked[captKey] = self:GetChecked()
        end)
    end

    -- ── Output editbox ────────────────────────────────────────────────────────
    local outputBg = CreateFrame("Frame", nil, dlg)
    outputBg:SetPoint("TOPLEFT",     dlg, "TOPLEFT",     12, -162)
    outputBg:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -12, 44)
    S:Bg(outputBg, S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)

    local sf = CreateFrame("ScrollFrame", nil, outputBg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     outputBg, "TOPLEFT",     4, -4)
    sf:SetPoint("BOTTOMRIGHT", outputBg, "BOTTOMRIGHT", -20, 4)

    local outputEdit = CreateFrame("EditBox", nil, sf)
    outputEdit:SetSize(DIALOG_W - 50, 10)
    outputEdit:SetMultiLine(true)
    outputEdit:SetAutoFocus(false)
    outputEdit:SetFontObject(S.FontSmall)
    outputEdit:SetTextInsets(4, 4, 4, 4)
    sf:SetScrollChild(outputEdit)
    dlg._outputEdit = outputEdit

    -- Hint
    local hintFS = S:FS(outputBg, "OVERLAY")
    hintFS:SetPoint("TOPLEFT", outputBg, "TOPLEFT", 8, -6)
    hintFS:SetText("Click Export to generate — then Ctrl+A, Ctrl+C to copy")
    hintFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    dlg._hintFS = hintFS

    -- ── Bottom bar ────────────────────────────────────────────────────────────
    local exportBtn = S:Button(dlg, "Export", 120, 28)
    exportBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 12, 10)
    exportBtn:SetScript("OnClick", function()
        local sep = DELIMS[delimSel].char
        local csv = UI:_BuildCSV(scopeSel, sep, fieldChecked, FIELDS)
        dlg._outputEdit:SetText(csv)
        dlg._outputEdit:SetFocus()
        dlg._outputEdit:HighlightText()
        if dlg._hintFS then dlg._hintFS:SetText("") end
    end)

    local cancelBtn = S:DangerButton(dlg, "Close", 80, 28)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -12, 10)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)

    dlg._scopeSel    = function() return scopeSel end
    dlg._delimSel    = function() return delimSel end
    dlg._fieldChecked = fieldChecked

    dlg:Show()
end

-- ── CSV builder ───────────────────────────────────────────────────────────────

function UI:_BuildCSV(scopeSel, sep, fieldChecked, FIELDS)
    local months = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}

    local function Esc(v)
        v = tostring(v or "")
        if v:find(sep, 1, true) or v:find('"', 1, true) or v:find('\n', 1, true) then
            v = '"' .. v:gsub('"', '""') .. '"'
        end
        return v
    end

    local lines = {}

    if scopeSel == 1 then
        -- Current members
        local header = {}
        for _, f in ipairs(FIELDS) do
            if fieldChecked[f.key] then header[#header + 1] = Esc(f.label) end
        end
        lines[#lines + 1] = table.concat(header, sep)

        local members = GH.GuildData:GetMembers()
        for _, m in ipairs(members) do
            local profile = GH.Profiles:GetProfile(m.name)
            local row = {}
            for _, f in ipairs(FIELDS) do
                if fieldChecked[f.key] then
                    local v = ""
                    if f.key == "name" then
                        v = m.name
                    elseif f.key == "rank" then
                        v = m.rank or ""
                    elseif f.key == "level" then
                        v = tostring(m.level or "")
                    elseif f.key == "class" then
                        v = m.class or ""
                    elseif f.key == "joinDate" then
                        v = (profile.joinDate and profile.joinDateVerified) and GH.Profiles.FormatDate(profile.joinDate) or ""
                    elseif f.key == "rankHist" then
                        local hist = profile.rankHistory or {}
                        if #hist > 0 then
                            local last = hist[#hist]
                            v = last.rankName .. " (" .. GH.Profiles.FormatDate(last.ts) .. ")"
                        end
                    elseif f.key == "note" then
                        v = profile.customNote or ""
                    elseif f.key == "alts" then
                        local group = GH.Profiles:GetAltGroup(m.name)
                        if group then
                            local altList = {}
                            for _, alt in ipairs(group.alts or {}) do
                                if alt ~= group.main then altList[#altList + 1] = alt end
                            end
                            v = table.concat(altList, "; ")
                        end
                    elseif f.key == "birthday" then
                        if profile.birthday then
                            local b = profile.birthday
                            v = (months[b.month] or "?") .. " " .. b.day
                            if b.year and b.year > 0 then v = v .. ", " .. b.year end
                        end
                    elseif f.key == "score" then
                        local sc = GH.DB:GetMemberScore(m.name)
                        v = (sc and sc > 0) and tostring(sc) or ""
                    elseif f.key == "banned" then
                        v = profile.isBanned and "Yes" or "No"
                    end
                    row[#row + 1] = Esc(v)
                end
            end
            lines[#lines + 1] = table.concat(row, sep)
        end

    elseif scopeSel == 2 then
        -- Activity log
        lines[#lines + 1] = table.concat({
            Esc("Time"), Esc("Type"), Esc("Player"), Esc("Detail")
        }, sep)

        local log = GH.ActivityLog:GetLog()
        for _, entry in ipairs(log) do
            lines[#lines + 1] = table.concat({
                Esc(GH:FormatTime(entry.ts)),
                Esc(entry.type or ""),
                Esc(entry.player or ""),
                Esc(GH.ActivityLog:FormatEntry(entry)),
            }, sep)
        end
    end

    return table.concat(lines, "\n")
end
