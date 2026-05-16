-- GuildHub - BanListDialog
-- Full CRUD UI for the guild ban list.
-- Shows all banned players with Name, Rank, Ban Date columns.
-- Officers can Add, Edit reason, or Remove bans.
-- Non-officers see the list read-only.

local GH  = GuildHub
local S   = GH.Styles
local UI  = GH.UI

local DIALOG_W = 560
local DIALOG_H = 440
local ROW_H    = 30

-- ── Public entry point ────────────────────────────────────────────────────────

function UI:ShowBanListDialog()
    if GH.DB:GetSetting("rosterProfilesEnabled") == false then
        print("|cff7289daGuildHub:|r Enable Roster Profiles to use the Ban List.")
        return
    end

    local dlg = rawget(_G, "GuildHubBanListWindow")
    if dlg then
        dlg:Show()
        UI:_RefreshBanList(dlg)
        return
    end

    dlg = CreateFrame("Frame", "GuildHubBanListWindow", UIParent)
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
    tinsert(UISpecialFrames, "GuildHubBanListWindow")

    -- ── Title bar ─────────────────────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, dlg)
    titleBar:SetPoint("TOPLEFT",  dlg, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", dlg, "TOPRIGHT")
    titleBar:SetHeight(38)
    S:Bg(titleBar, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    -- Accent line
    local accent = titleBar:CreateTexture(nil, "ARTWORK")
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT",  titleBar, "TOPLEFT")
    accent:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT")
    accent:SetColorTexture(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3], 0.9)

    local titleFS = S:FS(titleBar, "OVERLAY", "large")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
    titleFS:SetText("Ban List")
    titleFS:SetTextColor(S.COLOR.RED[1] + 0.1, S.COLOR.RED[2] + 0.05, S.COLOR.RED[3] + 0.05)

    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 2, 0)
    closeBtn:SetScript("OnClick", function() dlg:Hide() end)

    -- ── Toolbar ───────────────────────────────────────────────────────────────
    local toolbar = CreateFrame("Frame", nil, dlg)
    toolbar:SetPoint("TOPLEFT",  dlg, "TOPLEFT",  10, -46)
    toolbar:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -10, -46)
    toolbar:SetHeight(30)

    local isOfficer = GH:IsOfficer()

    local addBtn = S:Button(toolbar, "Add Ban", 80, 26)
    addBtn:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    if not isOfficer then addBtn:SetAlpha(0.35); addBtn:Disable() end

    local removeBtn = S:DangerButton(toolbar, "Remove Ban", 90, 26)
    removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    if not isOfficer then removeBtn:SetAlpha(0.35); removeBtn:Disable() end

    local editBtn = S:Button(toolbar, "Edit Reason", 90, 26)
    editBtn:SetPoint("LEFT", removeBtn, "RIGHT", 6, 0)
    if not isOfficer then editBtn:SetAlpha(0.35); editBtn:Disable() end

    -- Search box
    local searchBox = S:EditBox(toolbar, 160, 26, 64)
    searchBox:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    local hint = S:FS(searchBox, "OVERLAY")
    hint:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    hint:SetText("Player Search…")
    hint:SetTextColor(0.4, 0.4, 0.5)
    searchBox:SetScript("OnEditFocusGained", function() hint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function()
        if searchBox:GetText() == "" then hint:Show() end
    end)
    searchBox:SetScript("OnTextChanged", function() UI:_RefreshBanList(dlg) end)
    dlg.searchBox = searchBox

    -- ── Column headers ────────────────────────────────────────────────────────
    local headerRow = CreateFrame("Frame", nil, dlg)
    headerRow:SetPoint("TOPLEFT",  dlg, "TOPLEFT",  10, -82)
    headerRow:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -10, -82)
    headerRow:SetHeight(22)
    S:Bg(headerRow, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    local function ColHeader(parent, text, x, w)
        local fs = S:FS(parent, "OVERLAY")
        fs:SetPoint("LEFT", parent, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    end
    ColHeader(headerRow, "Name",     10, 140)
    ColHeader(headerRow, "Rank",    155, 100)
    ColHeader(headerRow, "Ban Date",260, 110)
    ColHeader(headerRow, "Reason",  375, 160)

    -- ── Scroll list ───────────────────────────────────────────────────────────
    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     dlg, "TOPLEFT",     10, -106)
    sf:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -26, 44)

    local scrollBg = sf:CreateTexture(nil, "BACKGROUND", nil, -2)
    scrollBg:SetAllPoints()
    scrollBg:SetColorTexture(0, 0, 0, 0.18)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(DIALOG_W - 38, 10)
    sf:SetScrollChild(sc)
    dlg.listContent = sc
    dlg._rowPool    = {}
    dlg._selectedName = nil

    -- ── Status bar ────────────────────────────────────────────────────────────
    local statusFS = S:FS(dlg, "OVERLAY")
    statusFS:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 14)
    statusFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    dlg._statusFS = statusFS

    -- ── Button wiring ─────────────────────────────────────────────────────────
    addBtn:SetScript("OnClick", function()
        UI:_ShowAddBanDialog(dlg)
    end)

    removeBtn:SetScript("OnClick", function()
        local name = dlg._selectedName
        if not name then
            dlg._statusFS:SetText("|cffff4444Select a player first.|r")
            return
        end
        GH.Profiles:UnbanPlayer(name)
        dlg._selectedName = nil
        UI:_RefreshBanList(dlg)
        dlg._statusFS:SetText("|cff22cc44Ban removed for " .. name .. ".|r")
    end)

    editBtn:SetScript("OnClick", function()
        local name = dlg._selectedName
        if not name then
            dlg._statusFS:SetText("|cffff4444Select a player first.|r")
            return
        end
        UI:_ShowEditBanDialog(dlg, name)
    end)

    dlg:Show()
    UI:_RefreshBanList(dlg)
end

-- ── List refresh ──────────────────────────────────────────────────────────────

function UI:_RefreshBanList(dlg)
    local filter = dlg.searchBox and dlg.searchBox:GetText():lower() or ""
    local banned = GH.Profiles:GetBannedPlayers()
    local sc     = dlg.listContent

    for _, row in ipairs(dlg._rowPool) do row:Hide() end

    local shown = 0
    for _, entry in ipairs(banned) do
        if filter == "" or entry.name:lower():find(filter, 1, true) then
            shown = shown + 1
            local row = dlg._rowPool[shown]
            if not row then
                row = CreateFrame("Button", nil, sc)
                row:SetHeight(ROW_H)
                row:RegisterForClicks("LeftButtonUp")

                local rowBg = row:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints()
                row.rowBg = rowBg

                local redBar = row:CreateTexture(nil, "ARTWORK")
                redBar:SetSize(3, ROW_H - 6)
                redBar:SetPoint("LEFT", row, "LEFT", 0, 0)
                redBar:SetColorTexture(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3], 0.8)

                local nameFS = S:FS(row, "OVERLAY", "normal")
                nameFS:SetPoint("LEFT", row, "LEFT", 10, 0)
                nameFS:SetWidth(140)
                nameFS:SetJustifyH("LEFT")
                row.nameFS = nameFS

                local rankFS = S:FS(row, "OVERLAY")
                rankFS:SetPoint("LEFT", row, "LEFT", 155, 0)
                rankFS:SetWidth(100)
                rankFS:SetJustifyH("LEFT")
                rankFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
                row.rankFS = rankFS

                local dateFS = S:FS(row, "OVERLAY")
                dateFS:SetPoint("LEFT", row, "LEFT", 260, 0)
                dateFS:SetWidth(110)
                dateFS:SetJustifyH("LEFT")
                dateFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
                row.dateFS = dateFS

                local reasonFS = S:FS(row, "OVERLAY")
                reasonFS:SetPoint("LEFT", row, "LEFT", 375, 0)
                reasonFS:SetWidth(155)
                reasonFS:SetJustifyH("LEFT")
                reasonFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
                row.reasonFS = reasonFS

                dlg._rowPool[shown] = row
            end

            local capEntry = entry
            row:SetParent(sc)
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(shown - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(shown - 1) * ROW_H)

            local isSelected = (dlg._selectedName == entry.name)
            if isSelected then
                row.rowBg:SetColorTexture(0.5, 0.12, 0.12, 0.6)
            elseif shown % 2 == 0 then
                row.rowBg:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.4)
            else
                row.rowBg:SetColorTexture(0, 0, 0, 0)
            end

            -- Get rank from current roster
            local rankName = ""
            local totalMembers = GetNumGuildMembers and GetNumGuildMembers() or 0
            for i = 1, totalMembers do
                local n, rn = GetGuildRosterInfo(i)
                if n and n:match("^([^%-]+)") == entry.name then
                    rankName = rn or ""
                    break
                end
            end

            row.nameFS:SetText(entry.name)
            row.rankFS:SetText(rankName ~= "" and rankName or "|cff555566—|r")
            row.dateFS:SetText(entry.date and GH.Profiles.FormatDate(entry.date) or "|cff555566Unknown|r")
            row.reasonFS:SetText(entry.reason ~= "" and entry.reason or "|cff555566No reason|r")

            row:SetScript("OnClick", function()
                dlg._selectedName = (dlg._selectedName == capEntry.name) and nil or capEntry.name
                UI:_RefreshBanList(dlg)
            end)
            row:SetScript("OnEnter", function(self)
                if not isSelected then
                    self.rowBg:SetColorTexture(
                        S.COLOR.PANEL_HOVER[1], S.COLOR.PANEL_HOVER[2], S.COLOR.PANEL_HOVER[3], 1)
                end
            end)
            row:SetScript("OnLeave", function(self)
                if dlg._selectedName ~= capEntry.name then
                    if shown % 2 == 0 then
                        self.rowBg:SetColorTexture(
                            S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.4)
                    else
                        self.rowBg:SetColorTexture(0, 0, 0, 0)
                    end
                end
            end)

            row:Show()
        end
    end

    sc:SetHeight(math.max(shown * ROW_H, 10))

    local total = #banned
    dlg._statusFS:SetText(
        shown == total and (total .. " banned player" .. (total ~= 1 and "s" or ""))
        or (shown .. " of " .. total .. " shown"))
end

-- ── Add ban dialog ────────────────────────────────────────────────────────────

function UI:_ShowAddBanDialog(parentDlg)
    local dlg = rawget(_G, "GuildHubAddBanDialog")
    if not dlg then
        dlg = CreateFrame("Frame", "GuildHubAddBanDialog", UIParent)
        dlg:SetSize(400, 170)
        dlg:SetFrameStrata("TOOLTIP")
        dlg:SetPoint("CENTER")
        S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
        S:Border(dlg)
    end
    dlg:Show()
    for i = dlg:GetNumChildren(), 1, -1 do select(i, dlg:GetChildren()):Hide() end

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -14)
    title:SetText("Add Ban")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    title:Show()

    local nameLabel = S:FS(dlg, "OVERLAY")
    nameLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 20, -40)
    nameLabel:SetText("Player Name:")
    nameLabel:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    nameLabel:Show()

    local nameEB = S:EditBox(dlg, 240, 24, 64)
    nameEB:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
    nameEB:SetFocus()
    nameEB:Show()

    local reasonLabel = S:FS(dlg, "OVERLAY")
    reasonLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 20, -72)
    reasonLabel:SetText("Reason (optional):")
    reasonLabel:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    reasonLabel:Show()

    local reasonEB = S:EditBox(dlg, 240, 24, 128)
    reasonEB:SetPoint("LEFT", reasonLabel, "RIGHT", 8, 0)
    reasonEB:Show()

    local confirmBtn = S:DangerButton(dlg, "Ban Player", 100, 26)
    confirmBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 20, 14)
    confirmBtn:Show()

    local cancelBtn = S:Button(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -20, 14)
    cancelBtn:Show()

    local function DoBan()
        local name   = nameEB:GetText():match("^%s*(.-)%s*$")
        local reason = reasonEB:GetText():match("^%s*(.-)%s*$")
        if name == "" then return end
        GH.Profiles:BanPlayer(name, reason, GH:GetPlayerName())
        dlg:Hide()
        if parentDlg and parentDlg:IsShown() then
            UI:_RefreshBanList(parentDlg)
            parentDlg._statusFS:SetText("|cffcc2222" .. name .. " has been banned.|r")
        end
    end

    confirmBtn:SetScript("OnClick", DoBan)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    nameEB:SetScript("OnEnterPressed", function() reasonEB:SetFocus() end)
    reasonEB:SetScript("OnEnterPressed", DoBan)
end

-- ── Edit ban reason dialog ────────────────────────────────────────────────────

function UI:_ShowEditBanDialog(parentDlg, name)
    local profile = GH.Profiles:GetProfile(name)
    local dlg     = rawget(_G, "GuildHubEditBanDialog")
    if not dlg then
        dlg = CreateFrame("Frame", "GuildHubEditBanDialog", UIParent)
        dlg:SetSize(400, 140)
        dlg:SetFrameStrata("TOOLTIP")
        dlg:SetPoint("CENTER")
        S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
        S:Border(dlg)
    end
    dlg:Show()
    for i = dlg:GetNumChildren(), 1, -1 do select(i, dlg:GetChildren()):Hide() end

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -14)
    title:SetText("Edit Ban — |cfff2c617" .. name .. "|r")
    title:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    title:Show()

    local reasonLabel = S:FS(dlg, "OVERLAY")
    reasonLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 20, -44)
    reasonLabel:SetText("New Reason:")
    reasonLabel:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    reasonLabel:Show()

    local reasonEB = S:EditBox(dlg, 240, 24, 128)
    reasonEB:SetPoint("LEFT", reasonLabel, "RIGHT", 8, 0)
    reasonEB:SetText(profile.banReason or "")
    reasonEB:SetFocus()
    reasonEB:Show()

    local saveBtn = S:Button(dlg, "Save", 80, 26)
    saveBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 20, 14)
    saveBtn:Show()

    local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -20, 14)
    cancelBtn:Show()

    local function DoSave()
        local reason = reasonEB:GetText():match("^%s*(.-)%s*$")
        profile.banReason = reason
        GH.DB:SavePlayerProfile(name, profile)
        GH.ProfileSync:BroadcastBan(name, reason, profile.bannedBy, profile.banDate)
        dlg:Hide()
        if parentDlg and parentDlg:IsShown() then
            UI:_RefreshBanList(parentDlg)
            parentDlg._statusFS:SetText("|cff22cc44Ban reason updated.|r")
        end
    end

    saveBtn:SetScript("OnClick", DoSave)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    reasonEB:SetScript("OnEnterPressed", DoSave)
end
