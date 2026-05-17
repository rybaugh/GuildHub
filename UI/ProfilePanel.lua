-- GuildHub - ProfilePanel
-- Slide-in detail panel shown on the right side of the Members tab when
-- a player row is selected. Displays join date, rank history, custom note,
-- alt group, birthday, and ban status. Officers can edit all fields.

local GH  = GuildHub
local S   = GH.Styles
local UI  = GH.UI

local PANEL_W = 268

-- ── Create the panel ──────────────────────────────────────────────────────────

function UI:CreateProfilePanel(parent)
    local panel = CreateFrame("Frame", "GuildHubProfilePanel", parent)
    panel:SetWidth(PANEL_W)
    panel:SetPoint("TOPRIGHT",    parent, "TOPRIGHT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    S:Bg(panel, 0.05, 0.05, 0.09, 0.98)

    -- Left edge divider
    local divider = panel:CreateTexture(nil, "BORDER")
    divider:SetSize(1, panel:GetHeight() or 600)
    divider:SetPoint("TOPLEFT",    panel, "TOPLEFT",    0, 0)
    divider:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    divider:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.7)

    -- Header bar
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    header:SetHeight(50)
    S:Bg(header, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    local nameLabel = S:FS(header, "OVERLAY", "normal")
    nameLabel:SetPoint("LEFT",  header, "LEFT",  12,  9)
    nameLabel:SetPoint("RIGHT", header, "RIGHT", -28, 9)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    panel.nameLabel = nameLabel

    local realmLabel = S:FS(header, "OVERLAY")
    realmLabel:SetPoint("LEFT",  header, "LEFT",  12,  -8)
    realmLabel:SetPoint("RIGHT", header, "RIGHT", -28, -8)
    realmLabel:SetJustifyH("LEFT")
    realmLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    panel.realmLabel = realmLabel

    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    closeBtn:SetScript("OnClick", function()
        UI._selectedMemberName = nil
        panel:Hide()
        if UI.MembersTab and UI.MembersTab.rosterPanel then
            UI.MembersTab.rosterPanel:SetPoint("BOTTOMRIGHT", UI.MembersTab, "BOTTOMRIGHT", 0, 0)
        end
    end)

    -- ── Scrollable content ────────────────────────────────────────────────────
    local sf = CreateFrame("ScrollFrame", nil, panel)
    sf:SetPoint("TOPLEFT",     panel, "TOPLEFT",     4, -54)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max,
            self:GetVerticalScroll() - delta * 40)))
    end)
    panel.sf = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(PANEL_W - 10)
    content:SetHeight(600)
    sf:SetScrollChild(content)

    -- Helpers: create widgets without initial position (Reflow sets them).
    local function MakeSectionHdr(title)
        local hdr = S:FS(content, "OVERLAY")
        hdr:SetText(title)
        hdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
        return hdr, line
    end

    local function MakeFS()
        local fs = S:FS(content, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        return fs
    end

    -- ── Widget creation (positions assigned by Reflow) ────────────────────────
    local bw = math.floor((PANEL_W - 26) / 2) - 2  -- half-row button width

    panel.guildNoteHdr,    panel.guildNoteLine    = MakeSectionHdr("Guild Note")
    panel.guildNoteFS = MakeFS()

    panel.personalNoteHdr, panel.personalNoteLine = MakeSectionHdr("Personal Note")
    panel.personalNoteFS = MakeFS()
    panel.personalNoteFS:SetTextColor(0.65, 0.75, 0.90)
    panel.editPersonalBtn = S:Button(content, "Edit Personal Note", PANEL_W - 30, 24)

    panel.joinDateHdr,     panel.joinDateLine     = MakeSectionHdr("Join Date")
    panel.joinDateLabel = MakeFS()
    panel.joinDateLabel:SetWordWrap(false)
    panel.setJoinDateBtn = S:Button(content, "Set Join Date", PANEL_W - 30, 24)

    panel.rankHistHdr,     panel.rankHistLine     = MakeSectionHdr("Rank History")
    panel.rankHistFS = MakeFS()
    panel.rankHistFS:SetSpacing(3)

    panel.customNoteHdr,   panel.customNoteLine   = MakeSectionHdr("Custom Note")
    panel.noteBox = S:EditBox(content, PANEL_W - 26, 64, 150)
    panel.noteBox:SetMultiLine(true)
    panel.noteCounter = S:FS(content, "OVERLAY")
    panel.noteCounter:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    panel.noteCounter:SetText("0/150")
    panel.noteBox:SetScript("OnTextChanged", function(self)
        local len = #self:GetText()
        panel.noteCounter:SetText(len .. "/150")
        if len > 150 then
            panel.noteCounter:SetTextColor(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3])
        else
            panel.noteCounter:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end
    end)
    panel.saveNoteBtn = S:Button(content, "Save Note", PANEL_W - 30, 24)

    panel.altGroupHdr,     panel.altGroupLine     = MakeSectionHdr("Alt / Main")
    panel.altGroupFS = MakeFS()
    panel.altGroupFS:SetSpacing(3)
    panel.setMainBtn   = S:Button(content,      "Set as Main",       bw, 24)
    panel.addAltBtn    = S:Button(content,       "Add Alt…",          bw, 24)
    panel.removeAltBtn = S:DangerButton(content, "Remove from Group", PANEL_W - 30, 22)

    panel.birthdayHdr,     panel.birthdayLine     = MakeSectionHdr("Birthday")
    panel.bdayLabel  = MakeFS()
    panel.bdayLabel:SetWordWrap(false)
    panel.setBdayBtn = S:Button(content, "Set Birthday",    bw, 24)
    panel.addCalBtn  = S:Button(content, "Add to Calendar", bw, 24)

    panel.banStatusHdr,    panel.banStatusLine    = MakeSectionHdr("Ban Status")
    panel.banLabel = MakeFS()
    panel.banBtn   = S:DangerButton(content, "Ban Player",  bw, 24)
    panel.unbanBtn = S:Button(content,       "Remove Ban",  bw, 24)

    -- ── Reflow: re-anchor every widget top-to-bottom using actual heights ──────
    -- Called after text/visibility is set so GetStringHeight() is accurate.
    function panel:Reflow()
        local y = 0

        local function placeSection(hdr, line)
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 10)
            y = y - 26
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT",  content, "TOPLEFT",  8,  y + 4)
            line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y + 4)
        end

        -- Anchors fs left+right (establishes wrap width), then reads actual height.
        local function placeFS(fs, fixedH)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT",  content, "TOPLEFT",  12, y - 2)
            fs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y - 2)
            local h = fixedH or math.max(fs:GetStringHeight(), 14)
            y = y - (h + 8)
        end

        local function placeBtn(btn, h)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 2)
            y = y - ((h or 24) + 6)
        end

        -- Guild Note
        placeSection(self.guildNoteHdr, self.guildNoteLine)
        placeFS(self.guildNoteFS)

        -- Personal Note
        placeSection(self.personalNoteHdr, self.personalNoteLine)
        placeFS(self.personalNoteFS)
        placeBtn(self.editPersonalBtn, 24)

        -- Join Date
        placeSection(self.joinDateHdr, self.joinDateLine)
        if self.joinDateLabel:IsShown() then
            placeFS(self.joinDateLabel, 16)
        end
        if self.setJoinDateBtn:IsShown() then
            placeBtn(self.setJoinDateBtn, 24)
        end

        -- Rank History
        placeSection(self.rankHistHdr, self.rankHistLine)
        placeFS(self.rankHistFS)

        -- Custom Note
        placeSection(self.customNoteHdr, self.customNoteLine)
        self.noteBox:ClearAllPoints()
        self.noteBox:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 2)
        y = y - 68
        self.noteCounter:ClearAllPoints()
        self.noteCounter:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y + 4)
        placeBtn(self.saveNoteBtn, 24)

        -- Alt / Main
        placeSection(self.altGroupHdr, self.altGroupLine)
        placeFS(self.altGroupFS)
        if self.setMainBtn:IsShown() then
            self.setMainBtn:ClearAllPoints()
            self.setMainBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 2)
            self.addAltBtn:ClearAllPoints()
            self.addAltBtn:SetPoint("LEFT", self.setMainBtn, "RIGHT", 4, 0)
            y = y - 30
        end
        if self.removeAltBtn:IsShown() then
            placeBtn(self.removeAltBtn, 22)
        end

        -- Birthday
        placeSection(self.birthdayHdr, self.birthdayLine)
        if self.bdayLabel:IsShown() then
            placeFS(self.bdayLabel, 16)
        end
        local bdayBtnsShown = self.setBdayBtn:IsShown() or self.addCalBtn:IsShown()
        if bdayBtnsShown then
            if self.setBdayBtn:IsShown() then
                self.setBdayBtn:ClearAllPoints()
                self.setBdayBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 2)
                self.addCalBtn:ClearAllPoints()
                self.addCalBtn:SetPoint("LEFT", self.setBdayBtn, "RIGHT", 4, 0)
            else
                self.addCalBtn:ClearAllPoints()
                self.addCalBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 2)
            end
            y = y - 30
        end

        -- Ban Status
        placeSection(self.banStatusHdr, self.banStatusLine)
        placeFS(self.banLabel)
        if self.banBtn:IsShown() then
            self.banBtn:ClearAllPoints()
            self.banBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 2)
            self.unbanBtn:ClearAllPoints()
            self.unbanBtn:SetPoint("LEFT", self.banBtn, "RIGHT", 4, 0)
            y = y - 30
        elseif self.unbanBtn:IsShown() then
            placeBtn(self.unbanBtn, 24)
        end

        content:SetHeight(math.abs(y) + 20)
    end

    UI.ProfilePanel = panel
    panel.content   = content

    -- Raise above roster panel siblings so the background fully covers column headers.
    panel:Raise()

    return panel
end

-- ── Populate the panel for a given member ─────────────────────────────────────

function UI:ShowProfilePanel(memberData)
    if GH.DB:GetSetting("rosterProfilesEnabled") == false then return end
    if not UI.ProfilePanel then return end
    if not memberData then
        UI.ProfilePanel:Hide()
        return
    end

    local panel = UI.ProfilePanel
    local name  = memberData.name
    local profile = GH.Profiles:GetProfile(name)

    panel.currentName = name
    panel.nameLabel:SetText(name)

    local realm = memberData.fullName and memberData.fullName:match("%-(.+)$")
    if realm and realm ~= "" then
        panel.realmLabel:SetText(realm)
        panel.realmLabel:Show()
    else
        panel.realmLabel:Hide()
    end

    -- Narrow the roster panel to make room
    if UI.MembersTab and UI.MembersTab.rosterPanel then
        UI.MembersTab.rosterPanel:SetPoint("BOTTOMRIGHT", UI.MembersTab, "BOTTOMRIGHT",
            -PANEL_W, 0)
    end
    panel:Show()
    panel:Raise()  -- ensure it stays above the roster panel on every open

    -- Guild note (WoW public note on this character)
    local guildNote = memberData.note or ""
    panel.guildNoteFS:SetText(
        guildNote ~= "" and guildNote or "|cff888888No guild note|r")

    -- Personal note (GuildHub private note, only visible to this player)
    local personalNote = GH.GuildData:GetPersonalNote(name) or ""
    panel.personalNoteFS:SetText(
        personalNote ~= "" and personalNote or "|cff888888No personal note|r")
    panel.editPersonalBtn:SetScript("OnClick", function()
        UI:ShowPersonalNoteDialog(name)
    end)

    -- Join date
    if profile.joinDate and profile.joinDateVerified then
        panel.joinDateLabel:SetText(GH.Profiles.FormatDate(profile.joinDate))
        panel.joinDateLabel:Show()
    else
        panel.joinDateLabel:Hide()
    end

    -- Set Join Date button
    local isOfficer = GH:IsOfficer()
    panel.setJoinDateBtn:SetShown(isOfficer)
    panel.setJoinDateBtn:SetScript("OnClick", function()
        UI:ShowSetJoinDateDialog(name)
    end)

    -- Rank history — single FontString, updated each time (no accumulation)
    local hist = profile.rankHistory or {}
    if #hist <= 1 then
        panel.rankHistFS:SetText("|cff888888No history recorded|r")
    else
        local lines = {}
        for i = #hist, math.max(1, #hist - 4), -1 do
            local entry = hist[i]
            lines[#lines + 1] = entry.rankName ..
                "  |cff8c8ca5" .. GH.Profiles.FormatDate(entry.ts) .. "|r"
        end
        panel.rankHistFS:SetText(table.concat(lines, "\n"))
    end

    -- Custom note
    panel.noteBox:SetText(profile.customNote or "")
    panel.noteBox:SetEnabled(true)
    if not isOfficer then
        panel.noteBox:SetEnabled(false)
        panel.saveNoteBtn:Disable()
        panel.saveNoteBtn:SetAlpha(0.4)
    else
        panel.saveNoteBtn:Enable()
        panel.saveNoteBtn:SetAlpha(1)
    end
    panel.saveNoteBtn:SetScript("OnClick", function()
        local text = panel.noteBox:GetText():match("^%s*(.-)%s*$")
        GH.Profiles:SetCustomNote(name, text:sub(1, 150))
    end)

    -- Alt group — single FontString, updated each time (no accumulation)
    local group = GH.Profiles:GetAltGroup(name)
    if group then
        local mainName = group.main or "?"
        local lines = { "Main: |cfff2c617" .. mainName .. "|r" }
        for _, alt in ipairs(group.alts or {}) do
            if alt ~= mainName then
                lines[#lines + 1] = "  |cff8c8ca5" .. alt .. "|r"
            end
        end
        panel.altGroupFS:SetText(table.concat(lines, "\n"))
    else
        panel.altGroupFS:SetText("|cff888888Not in any alt group|r")
    end

    panel.setMainBtn:SetShown(isOfficer)
    panel.addAltBtn:SetShown(isOfficer)
    panel.removeAltBtn:SetShown(isOfficer and (group ~= nil))

    panel.setMainBtn:SetScript("OnClick", function()
        GH.Profiles:SetMain(name)
        UI:ShowProfilePanel(memberData)
    end)
    panel.addAltBtn:SetScript("OnClick", function()
        UI:ShowAddAltDialog(name, memberData)
    end)
    panel.removeAltBtn:SetScript("OnClick", function()
        GH.Profiles:RemoveFromAltGroup(name)
        UI:ShowProfilePanel(memberData)
    end)

    -- Birthday
    local bday = profile.birthday
    if bday then
        local months = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
        local mName  = months[bday.month] or tostring(bday.month)
        panel.bdayLabel:SetText(mName .. " " .. bday.day .. (bday.year and bday.year > 0 and (", " .. bday.year) or ""))
    else
        panel.bdayLabel:SetText("|cff888888Not set|r")
    end
    panel.setBdayBtn:SetShown(isOfficer)
    panel.setBdayBtn:SetScript("OnClick", function()
        UI:ShowSetBirthdayDialog(name, memberData)
    end)
    if GH.DB:GetSetting("rosterShowBirthdays") == false then
        panel.bdayLabel:Hide()
        panel.setBdayBtn:Hide()
        panel.addCalBtn:Hide()
    else
        panel.bdayLabel:Show()
        panel.setBdayBtn:SetShown(isOfficer)
        panel.addCalBtn:Show()
    end
    panel.addCalBtn:SetScript("OnClick", function()
        GH.Profiles:AddAnniversaryToCalendar(name)
        if bday then GH.Profiles:AddBirthdayToCalendar(name) end
    end)

    -- Ban status
    if profile.isBanned then
        panel.banLabel:SetText("|cffcc2222Banned|r by " .. (profile.bannedBy or "?")
            .. "\n|cff888888" .. (profile.banReason or "no reason") .. "|r")
        panel.banLabel:SetTextColor(1, 0.3, 0.3)
    else
        panel.banLabel:SetText("|cff22cc44Not Banned|r")
    end
    panel.banBtn:SetShown(isOfficer and not profile.isBanned)
    panel.unbanBtn:SetShown(isOfficer and profile.isBanned == true)
    panel.banBtn:SetScript("OnClick", function()
        UI:ShowBanDialog(name, memberData)
    end)
    panel.unbanBtn:SetScript("OnClick", function()
        GH.Profiles:UnbanPlayer(name)
        UI:ShowProfilePanel(memberData)
    end)

    -- Reset scroll to top and reflow with actual content heights.
    -- Two passes: immediate (repositions everything so widths are established),
    -- then deferred one frame so GetStringHeight reflects the new text.
    panel.sf:SetVerticalScroll(0)
    panel:Reflow()
    C_Timer.After(0, function()
        if panel:IsShown() and panel.currentName == name then
            panel:Reflow()
        end
    end)
end

-- ── Helper dialogs ────────────────────────────────────────────────────────────

function UI:ShowSetJoinDateDialog(name)
    local dlg = rawget(_G, "GuildHubSetJoinDateDialog")
    if not dlg then
        dlg = CreateFrame("Frame", "GuildHubSetJoinDateDialog", UIParent)
        dlg:SetSize(340, 150)
        dlg:SetFrameStrata("DIALOG")
        dlg:SetPoint("CENTER")
        S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
    end
    dlg:Show()

    for i = dlg:GetNumChildren(), 1, -1 do select(i, dlg:GetChildren()):Hide() end

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText("Set Join Date for |cfff2c617" .. name .. "|r")
    title:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    title:Show()

    local hint = S:FS(dlg, "OVERLAY")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetText("Format: MM/DD/YYYY")
    hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    hint:Show()

    local profile = GH.Profiles:GetProfile(name)
    local existing = profile.joinDate and date("%m/%d/%Y", profile.joinDate) or ""

    local eb = S:EditBox(dlg, 300, 26, 20)
    eb:SetPoint("TOP", hint, "BOTTOM", 0, -8)
    eb:SetText(existing)
    eb:SetFocus()
    eb:Show()

    local okBtn = S:Button(dlg, "Save", 80, 26)
    okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 10)
    okBtn:Show()

    local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 10)
    cancelBtn:Show()

    local function TrySave()
        local str = eb:GetText():match("^%s*(.-)%s*$")
        local m, d, y = str:match("(%d+)/(%d+)/(%d+)")
        if m and d and y then
            local ts = time({ year = tonumber(y) or 2000, month = tonumber(m) or 1,
                              day = tonumber(d) or 1, hour = 0, min = 0, sec = 0 })
            GH.Profiles:SetJoinDate(name, ts, true)
            dlg:Hide()
            if UI.ProfilePanel and UI.ProfilePanel:IsShown() then
                local members = GH.GuildData:GetMembers()
                for _, mb in ipairs(members) do
                    if mb.name == name then UI:ShowProfilePanel(mb); break end
                end
            end
        end
    end

    okBtn:SetScript("OnClick", TrySave)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    eb:SetScript("OnEnterPressed", TrySave)
end

function UI:ShowSetBirthdayDialog(name, memberData)
    local dlg = rawget(_G, "GuildHubSetBirthdayDialog")
    if not dlg then
        dlg = CreateFrame("Frame", "GuildHubSetBirthdayDialog", UIParent)
        dlg:SetSize(340, 155)
        dlg:SetFrameStrata("DIALOG")
        dlg:SetPoint("CENTER")
        S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
    end
    dlg:Show()
    for i = dlg:GetNumChildren(), 1, -1 do select(i, dlg:GetChildren()):Hide() end

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText("Set Birthday for |cfff2c617" .. name .. "|r")
    title:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    title:Show()

    local hint = S:FS(dlg, "OVERLAY")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetText("Format: MM/DD  or  MM/DD/YYYY")
    hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    hint:Show()

    local profile  = GH.Profiles:GetProfile(name)
    local existing = ""
    if profile.birthday then
        local b = profile.birthday
        existing = string.format("%02d/%02d", b.month, b.day)
        if b.year and b.year > 0 then existing = existing .. "/" .. b.year end
    end

    local eb = S:EditBox(dlg, 300, 26, 10)
    eb:SetPoint("TOP", hint, "BOTTOM", 0, -8)
    eb:SetText(existing)
    eb:SetFocus()
    eb:Show()

    local okBtn = S:Button(dlg, "Save", 80, 26)
    okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 10)
    okBtn:Show()

    local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 10)
    cancelBtn:Show()

    local function TrySave()
        local str = eb:GetText():match("^%s*(.-)%s*$")
        local m, d, y = str:match("(%d+)/(%d+)/(%d+)")
        if not m then m, d = str:match("(%d+)/(%d+)") end
        if m and d then
            GH.Profiles:SetBirthday(name, tonumber(m), tonumber(d), tonumber(y) or 0)
            dlg:Hide()
            if memberData then UI:ShowProfilePanel(memberData) end
        end
    end

    okBtn:SetScript("OnClick", TrySave)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    eb:SetScript("OnEnterPressed", TrySave)
end

function UI:ShowBanDialog(name, memberData)
    local dlg = rawget(_G, "GuildHubBanDialog")
    if not dlg then
        dlg = CreateFrame("Frame", "GuildHubBanDialog", UIParent)
        dlg:SetSize(380, 145)
        dlg:SetFrameStrata("DIALOG")
        dlg:SetPoint("CENTER")
        S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
    end
    dlg:Show()
    for i = dlg:GetNumChildren(), 1, -1 do select(i, dlg:GetChildren()):Hide() end

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText("Ban |cfff2c617" .. name .. "|r  — reason (optional)")
    title:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    title:Show()

    local eb = S:EditBox(dlg, 340, 26, 100)
    eb:SetPoint("TOP", title, "BOTTOM", 0, -10)
    eb:SetFocus()
    eb:Show()

    local banBtn = S:DangerButton(dlg, "Confirm Ban", 100, 26)
    banBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 10)
    banBtn:Show()

    local cancelBtn = S:Button(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 10)
    cancelBtn:Show()

    local function DoBan()
        local reason = eb:GetText():match("^%s*(.-)%s*$")
        GH.Profiles:BanPlayer(name, reason, GH:GetPlayerName())
        dlg:Hide()
        if memberData then UI:ShowProfilePanel(memberData) end
    end

    banBtn:SetScript("OnClick", DoBan)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    eb:SetScript("OnEnterPressed", DoBan)
end

function UI:ShowAddAltDialog(mainName, mainMemberData)
    local members = GH.GuildData:GetMembers()
    local ITEM_H  = 28

    local dlg = rawget(_G, "GuildHubAddAltDialog")
    if not dlg then
        dlg = CreateFrame("Frame", "GuildHubAddAltDialog", UIParent)
        dlg:SetSize(260, 360)
        dlg:SetFrameStrata("DIALOG")
        dlg:SetPoint("CENTER")
        S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
    end
    dlg:Show()
    for i = dlg:GetNumChildren(), 1, -1 do select(i, dlg:GetChildren()):Hide() end

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText("Add Alt to |cfff2c617" .. mainName .. "|r")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    title:Show()

    local searchBox = S:EditBox(dlg, 220, 24, 50)
    searchBox:SetPoint("TOP", title, "BOTTOM", 0, -8)
    searchBox:Show()
    local hint = S:FS(searchBox, "OVERLAY")
    hint:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    hint:SetText("Search…")
    hint:SetTextColor(0.4, 0.4, 0.5)
    searchBox:SetScript("OnEditFocusGained", function() hint:Hide() end)
    searchBox:SetScript("OnEditFocusLost",   function()
        if searchBox:GetText() == "" then hint:Show() end
    end)

    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     dlg, "TOPLEFT",     10, -76)
    sf:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -26, 44)
    sf:Show()

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(220)
    sc:SetHeight(10)
    sf:SetScrollChild(sc)

    local rowBtns = {}

    local function PopulateList(filter)
        for _, btn in ipairs(rowBtns) do btn:Hide() end
        rowBtns = {}
        local idx = 0
        for _, m in ipairs(members) do
            if m.name ~= mainName then
                local show = filter == "" or m.name:lower():find(filter:lower(), 1, true)
                if show then
                    local btn = CreateFrame("Button", nil, sc)
                    btn:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -idx * ITEM_H)
                    btn:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -idx * ITEM_H)
                    btn:SetHeight(ITEM_H)
                    local bg = btn:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    bg:SetColorTexture(0, 0, 0, 0)
                    local lbl = S:FS(btn, "OVERLAY")
                    lbl:SetPoint("LEFT", btn, "LEFT", 8, 0)
                    local cr, cg, cb = GH.GuildData:GetClassColor(m.classFileName)
                    lbl:SetText(m.name)
                    lbl:SetTextColor(cr, cg, cb)
                    btn:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.06) end)
                    btn:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
                    local capName = m.name
                    btn:SetScript("OnClick", function()
                        GH.Profiles:AddAlt(mainName, capName)
                        dlg:Hide()
                        if mainMemberData then UI:ShowProfilePanel(mainMemberData) end
                    end)
                    idx = idx + 1
                    rowBtns[#rowBtns + 1] = btn
                end
            end
        end
        sc:SetHeight(math.max(idx * ITEM_H, 10))
    end

    searchBox:SetScript("OnTextChanged", function(self) PopulateList(self:GetText()) end)
    PopulateList("")

    local cancelBtn = S:Button(dlg, "Cancel", 100, 26)
    cancelBtn:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 10)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    cancelBtn:Show()
end
