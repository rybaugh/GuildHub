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
