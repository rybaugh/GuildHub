-- GuildHub - Team Application Dialogs
local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local CreateFrame = _G.CreateFrame

-- ── Application Form (member submitting an application) ───────────────────

function UI:ShowTeamApplicationForm(groupId)
    local g = GH.DB:GetGroups()[groupId]
    if not g then return end

    -- Close any existing dialog of this type
    local existing = rawget(_G, "GuildHubTeamAppFormDialog")
    if existing then existing:Hide() end

    local dlg = CreateFrame("Frame", "GuildHubTeamAppFormDialog", UIParent)
    dlg:SetSize(340, 310)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetMovable(true)
    dlg:EnableMouse(true)
    dlg:SetScript("OnMouseDown", function() dlg:StartMoving() end)
    dlg:SetScript("OnMouseUp",   function() dlg:StopMovingOrSizing() end)

    local mainWin = rawget(_G, "GuildHubMainWindow")
    if mainWin then
        dlg:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", 4, 0)
    else
        dlg:SetPoint("CENTER")
    end

    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
    local accent = dlg:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("TOPRIGHT"); accent:SetHeight(2)
    accent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.80)

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -14)
    title:SetText("Apply to " .. g.name)
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    -- Role selector
    local roleLabel = S:FS(dlg, "OVERLAY")
    roleLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 14, -38)
    roleLabel:SetText("Role")
    roleLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    local ROLES    = { "Tank", "Healer", "DPS", "Support" }
    local selectedRole = nil
    local roleBtns = {}

    local roleColors = {
        Tank    = { 0.20, 0.45, 0.90 },
        Healer  = { 0.20, 0.75, 0.35 },
        DPS     = { 0.85, 0.25, 0.25 },
        Support = { 0.75, 0.55, 0.15 },
    }

    local roleBtnW = 70
    for i, role in ipairs(ROLES) do
        local btn = CreateFrame("Button", nil, dlg)
        btn:SetSize(roleBtnW, 26)
        btn:SetPoint("TOPLEFT", dlg, "TOPLEFT", 14 + (i - 1) * (roleBtnW + 4), -52)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)
        btn.bg = bg

        local fs = S:FS(btn, "OVERLAY", "normal")
        fs:SetPoint("CENTER")
        fs:SetText(role)
        btn.fs = fs

        local capturedRole = role
        btn:SetScript("OnClick", function()
            selectedRole = capturedRole
            for _, rb in ipairs(roleBtns) do
                local rc = roleColors[rb.roleName]
                if rb.roleName == selectedRole then
                    rb.bg:SetColorTexture(rc[1], rc[2], rc[3], 0.55)
                    rb.fs:SetTextColor(1, 1, 1)
                else
                    rb.bg:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)
                    rb.fs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
                end
            end
        end)

        btn.roleName = role
        btn.bg  = bg
        btn.fs  = fs
        roleBtns[i] = btn

        fs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- Helper to build a labelled field row
    local function MakeField(label, yOff, maxChars, placeholder, multiline)
        local lbl = S:FS(dlg, "OVERLAY")
        lbl:SetPoint("TOPLEFT", dlg, "TOPLEFT", 14, yOff)
        lbl:SetText(label)
        lbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

        local fieldH = multiline and 44 or 26
        local eb = S:EditBox(dlg, 312, fieldH, maxChars)
        eb:SetPoint("TOPLEFT", dlg, "TOPLEFT", 14, yOff - 14)
        if multiline then
            eb:SetMultiLine(true)
        end

        -- Placeholder text
        local ph = S:FS(eb, "OVERLAY")
        ph:SetPoint("LEFT", eb, "LEFT", 8, 0)
        ph:SetTextColor(0.35, 0.34, 0.45)
        ph:SetText(placeholder)
        eb:SetScript("OnEditFocusGained", function() ph:Hide() end)
        eb:SetScript("OnEditFocusLost",   function()
            if eb:GetText() == "" then ph:Show() end
        end)

        return eb
    end

    local mainEB = MakeField("Main Character",   -90,  20, GH:GetPlayerName())
    mainEB:SetText(GH:GetPlayerName())

    local altsEB  = MakeField("Alt Characters (optional)", -134, 35, "Alt1, Alt2…")
    local logEB   = MakeField("Log Link (optional)",        -178, 80, "https://www.warcraftlogs.com/…")
    local notesEB = MakeField("Additional Info (optional)", -222, 50, "Schedule, experience…", true)

    -- Error label
    local errorFS = S:FS(dlg, "OVERLAY")
    errorFS:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 46)
    errorFS:SetTextColor(1, 0.3, 0.3)
    errorFS:Hide()

    -- Submit button
    local submitBtn = S:Button(dlg, "Submit Application", 150, 28)
    submitBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 12)
    submitBtn:SetScript("OnClick", function()
        if not selectedRole then
            errorFS:SetText("Please select a role.")
            errorFS:Show()
            return
        end
        local main = mainEB:GetText():match("^%s*(.-)%s*$")
        if main == "" then
            errorFS:SetText("Main character name is required.")
            errorFS:Show()
            return
        end
        local alts   = altsEB:GetText():match("^%s*(.-)%s*$")
        local logURL = logEB:GetText():match("^%s*(.-)%s*$")
        local notes  = notesEB:GetText():match("^%s*(.-)%s*$")
        GH.TeamApps:Submit(groupId, selectedRole, main, alts, logURL, notes)
        print("|cff7289daGuildHub:|r Application submitted to |cffffd700" .. g.name .. "|r!")
        if GH.UI then GH.UI:RefreshTeamsGroupList() end
        dlg:Hide()
    end)

    -- Cancel button
    local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 28)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 12)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)

    dlg:Show()
end

-- ── Application Review Dialog (team manager reviewing applications) ────────

function UI:ShowTeamApplicationsDialog(groupId)
    local g = GH.DB:GetGroups()[groupId]
    if not g then return end

    local existing = rawget(_G, "GuildHubTeamAppReviewDialog")
    if existing then existing:Hide() end

    local dlg = CreateFrame("Frame", "GuildHubTeamAppReviewDialog", UIParent)
    dlg:SetSize(360, 440)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetMovable(true)
    dlg:EnableMouse(true)
    dlg:SetScript("OnMouseDown", function() dlg:StartMoving() end)
    dlg:SetScript("OnMouseUp",   function() dlg:StopMovingOrSizing() end)

    local mainWin = rawget(_G, "GuildHubMainWindow")
    if mainWin then
        dlg:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", 4, 0)
    else
        dlg:SetPoint("CENTER")
    end

    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
    local accent = dlg:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("TOPRIGHT"); accent:SetHeight(2)
    accent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.80)

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -14)
    title:SetText(g.name .. " — Applications")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    -- Scroll area
    local sf = CreateFrame("ScrollFrame", nil, dlg)
    sf:SetPoint("TOPLEFT",     dlg, "TOPLEFT",     8, -36)
    sf:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -8, 40)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
    end)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(344)
    sc:SetHeight(10)
    sf:SetScrollChild(sc)
    sf:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w > 0 then sc:SetWidth(w) end
    end)

    local roleColors = {
        Tank    = { 0.20, 0.45, 0.90 },
        Healer  = { 0.20, 0.75, 0.35 },
        DPS     = { 0.85, 0.25, 0.25 },
        Support = { 0.75, 0.55, 0.15 },
    }

    local function PopulateApps()
        -- Clear existing children
        for i = sc:GetNumChildren(), 1, -1 do
            select(i, sc:GetChildren()):Hide()
        end

        local apps = GH.DB:GetTeamApplications(groupId)

        -- Sort: pending first, then by timestamp descending
        local sorted = {}
        for applicant, app in pairs(apps) do
            sorted[#sorted + 1] = { name = applicant, app = app }
        end
        table.sort(sorted, function(a, b)
            local ap, bp = a.app.status == "pending", b.app.status == "pending"
            if ap ~= bp then return ap end
            return (a.app.ts or 0) > (b.app.ts or 0)
        end)

        if #sorted == 0 then
            local none = S:FS(sc, "OVERLAY")
            none:SetPoint("TOP", sc, "TOP", 0, -20)
            none:SetText("No applications yet.")
            none:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
            sc:SetHeight(50)
            return
        end

        local yOff = 0

        for _, entry in ipairs(sorted) do
            local applicant = entry.name
            local app       = entry.app
            local isPending = app.status == "pending"

            local card = CreateFrame("Frame", nil, sc)
            card:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -yOff)
            card:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -yOff)
            local cardH = isPending and 120 or 80
            card:SetHeight(cardH)
            card:Show()

            -- Card background
            local cbg = card:CreateTexture(nil, "BACKGROUND")
            cbg:SetAllPoints()
            cbg:SetColorTexture(
                isPending and S.COLOR.PANEL[1] + 0.01 or S.COLOR.PANEL[1] * 0.7,
                isPending and S.COLOR.PANEL[2] + 0.01 or S.COLOR.PANEL[2] * 0.7,
                isPending and S.COLOR.PANEL[3] + 0.01 or S.COLOR.PANEL[3] * 0.7,
                isPending and 1 or 0.6)

            -- Separator line at bottom
            local sep = card:CreateTexture(nil, "BORDER")
            sep:SetPoint("BOTTOMLEFT",  card, "BOTTOMLEFT",  4, 0)
            sep:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -4, 0)
            sep:SetHeight(1)
            sep:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.4)

            -- Applicant name
            local nameFS = S:FS(card, "OVERLAY", "normal")
            nameFS:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
            nameFS:SetText(applicant)
            nameFS:SetTextColor(
                isPending and S.COLOR.TEXT_GOLD[1] or S.COLOR.TEXT_DIM[1],
                isPending and S.COLOR.TEXT_GOLD[2] or S.COLOR.TEXT_DIM[2],
                isPending and S.COLOR.TEXT_GOLD[3] or S.COLOR.TEXT_DIM[3])

            -- Role badge
            local rc = roleColors[app.role] or { 0.5, 0.5, 0.5 }
            local roleBadge = CreateFrame("Frame", nil, card)
            roleBadge:SetSize(58, 16)
            roleBadge:SetPoint("LEFT", nameFS, "RIGHT", 6, 0)
            local rbg = roleBadge:CreateTexture(nil, "BACKGROUND")
            rbg:SetAllPoints()
            rbg:SetColorTexture(rc[1], rc[2], rc[3], isPending and 0.55 or 0.25)
            local roleFS = S:FS(roleBadge, "OVERLAY")
            roleFS:SetPoint("CENTER")
            roleFS:SetText(app.role or "?")
            roleFS:SetTextColor(1, 1, 1)

            -- Timestamp (relative)
            local now  = time()
            local diff = now - (app.ts or now)
            local timeStr
            if diff < 60 then
                timeStr = "just now"
            elseif diff < 3600 then
                timeStr = math.floor(diff / 60) .. "m ago"
            elseif diff < 86400 then
                timeStr = math.floor(diff / 3600) .. "h ago"
            else
                timeStr = math.floor(diff / 86400) .. "d ago"
            end
            local tsFS = S:FS(card, "OVERLAY")
            tsFS:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
            tsFS:SetText(timeStr)
            tsFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

            -- Main / Alts line
            local altText = (app.alts and app.alts ~= "") and ("  |cff888888Alts:|r " .. app.alts) or ""
            local charFS = S:FS(card, "OVERLAY")
            charFS:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -26)
            charFS:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -26)
            charFS:SetText("|cff888888Main:|r " .. (app.main or "?") .. altText)
            charFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
            charFS:SetWordWrap(false)

            -- Log URL (read-only EditBox so user can select and copy)
            if app.logURL and app.logURL ~= "" then
                local logEB = CreateFrame("EditBox", nil, card)
                logEB:SetPoint("TOPLEFT",  card, "TOPLEFT",  10, -42)
                logEB:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -42)
                logEB:SetHeight(16)
                logEB:SetMultiLine(false)
                logEB:SetAutoFocus(false)
                logEB:SetFont(S:FS(card, "OVERLAY"):GetFont())
                logEB:SetTextColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3])
                logEB:SetText(app.logURL)
                logEB:SetCursorPosition(0)
                logEB:Disable()
                -- Re-enable on click so user can select text
                logEB:SetScript("OnMouseDown", function(self)
                    self:Enable()
                    self:SetFocus()
                    self:HighlightText()
                end)
                logEB:SetScript("OnEditFocusLost", function(self)
                    self:Disable()
                    self:HighlightText(0, 0)
                end)
            end

            -- Notes
            if app.notes and app.notes ~= "" then
                local notesFS = S:FS(card, "OVERLAY")
                notesFS:SetPoint("TOPLEFT",  card, "TOPLEFT",  10, -60)
                notesFS:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -60)
                notesFS:SetText('"' .. app.notes .. '"')
                notesFS:SetTextColor(0.65, 0.65, 0.75)
                notesFS:SetWordWrap(true)
            end

            -- Status badge for resolved apps
            if not isPending then
                local statusFS = S:FS(card, "OVERLAY")
                statusFS:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
                if app.status == "accepted" then
                    statusFS:SetText("Accepted")
                    statusFS:SetTextColor(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3])
                elseif app.status == "declined" then
                    statusFS:SetText("Declined")
                    statusFS:SetTextColor(S.COLOR.DND[1], S.COLOR.DND[2], S.COLOR.DND[3])
                else
                    statusFS:SetText(app.status)
                    statusFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
                end
            end

            -- Accept / Decline buttons (pending only)
            if isPending then
                local capturedApplicant = applicant
                local acceptBtn = S:Button(card, "Accept", 90, 24)
                acceptBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
                acceptBtn:SetScript("OnClick", function()
                    GH.TeamApps:Accept(groupId, capturedApplicant)
                    PopulateApps()
                end)

                local declineBtn = S:DangerButton(card, "Decline", 90, 24)
                declineBtn:SetPoint("LEFT", acceptBtn, "RIGHT", 6, 0)
                declineBtn:SetScript("OnClick", function()
                    GH.TeamApps:Decline(groupId, capturedApplicant)
                    PopulateApps()
                end)
            end

            yOff = yOff + cardH + 4
        end

        sc:SetHeight(math.max(yOff, 10))
    end

    PopulateApps()

    local closeBtn = S:Button(dlg, "Close", 80, 26)
    closeBtn:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 10)
    closeBtn:SetScript("OnClick", function() dlg:Hide() end)

    dlg:Show()
end
