-- GuildHub - Groups Tab
-- Officer-defined raid/social group presets with one-click invite.

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local CreateFrame = _G.CreateFrame

local selectedGroupId = nil

function UI:CreateGroupsTab(parent, w, h)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.GroupsTab = frame

    -- Left panel: group list
    local listPanel = CreateFrame("Frame", nil, frame)
    listPanel:SetPoint("TOPLEFT",    frame, "TOPLEFT",    10, -10)
    listPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    listPanel:SetWidth(200)
    S:Bg(listPanel, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    local listHeader = S:Header(listPanel, "  GROUP PRESETS")
    listHeader:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 6, -8)

    local newGroupBtn = S:Button(listPanel, "+ New Group", 180, 26)
    newGroupBtn:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 10, -26)
    newGroupBtn:SetScript("OnClick", function()
        if not GH:IsOfficer() then
            print("|cff7289daGuildHub:|r Only officers can create group presets.")
            return
        end
        UI:ShowGroupNameDialog(nil, function(name)
            GH.Groups:Create(name)
            UI:RefreshGroupsTab()
        end)
    end)

    local sf = CreateFrame("ScrollFrame", nil, listPanel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     listPanel, "TOPLEFT",     4,  -58)
    sf:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -18, 4)
    local listContent = CreateFrame("Frame", nil, sf)
    listContent:SetSize(178, 10)
    sf:SetScrollChild(listContent)
    listPanel.listContent = listContent

    -- Right panel: group detail
    local detailPanel = CreateFrame("Frame", nil, frame)
    detailPanel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     218, -10)
    detailPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    S:Bg(detailPanel, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.5)
    frame.detailPanel = detailPanel

    local detailTitle = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailTitle:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 12, -12)
    detailTitle:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    frame.detailTitle = detailTitle

    -- Invite All button
    local inviteBtn = S:Button(detailPanel, "Invite All Online", 150, 28)
    inviteBtn:SetPoint("TOPRIGHT", detailPanel, "TOPRIGHT", -10, -10)
    inviteBtn:SetScript("OnClick", function()
        if selectedGroupId then
            GH.Groups:InviteAll(selectedGroupId)
        end
    end)
    frame.inviteBtn = inviteBtn

    -- Delete group button (officer only)
    local deleteBtn = S:DangerButton(detailPanel, "Delete Group", 110, 28)
    deleteBtn:SetPoint("RIGHT", inviteBtn, "LEFT", -8, 0)
    deleteBtn:SetScript("OnClick", function()
        if not selectedGroupId then return end
        if not GH:IsOfficer() then
            print("|cff7289daGuildHub:|r Only officers can delete group presets.")
            return
        end
        GH.Groups:Delete(selectedGroupId)
        selectedGroupId = nil
        UI:RefreshGroupsTab()
    end)

    -- Member list inside detail
    local memberSf = CreateFrame("ScrollFrame", nil, detailPanel, "UIPanelScrollFrameTemplate")
    memberSf:SetPoint("TOPLEFT",     detailPanel, "TOPLEFT",     10,  -48)
    memberSf:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", -20, 50)
    local memberContent = CreateFrame("Frame", nil, memberSf)
    memberContent:SetSize(w - 248, 10)
    memberSf:SetScrollChild(memberContent)
    frame.memberContent = memberContent

    -- Add member controls (bottom of detail)
    local addLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("BOTTOMLEFT", detailPanel, "BOTTOMLEFT", 12, 20)
    addLabel:SetText("Add member:")
    addLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    local addBox = S:EditBox(detailPanel, 180, 24, 60)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 6, 0)
    local addBtn = S:Button(detailPanel, "Add", 60, 24)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
    addBtn:SetScript("OnClick", function()
        if not selectedGroupId then return end
        local name = addBox:GetText():match("^%s*(.-)%s*$")
        if name ~= "" then
            GH.Groups:AddMember(selectedGroupId, name)
            addBox:SetText("")
            UI:RefreshGroupDetail(selectedGroupId)
        end
    end)

    -- "Select a group" placeholder
    local placeholder = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetAllPoints(detailPanel)
    placeholder:SetText("Select a group from the left\nor create a new one.")
    placeholder:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    placeholder:SetJustifyH("CENTER")
    frame.placeholder = placeholder

    frame.addBox    = addBox
    frame.listPanel = listPanel

    UI:RefreshGroupsTab()
end

function UI:RefreshGroupsTab()
    local frame = UI.GroupsTab
    if not frame then return end

    local content = frame.listPanel.listContent
    -- Clear existing buttons
    for i = content:GetNumChildren(), 1, -1 do
        local child = select(i, content:GetChildren())
        child:Hide()
    end

    local groups = GH.Groups:GetAll()
    local totalH = 0
    for i, g in ipairs(groups) do
        local btn = CreateFrame("Button", nil, content)
        btn:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * 36)
        btn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * 36)
        btn:SetHeight(34)
        btn:Show()

        local isSelected = (g.id == selectedGroupId)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(
            isSelected and S.COLOR.NAV_ACTIVE[1] or 0,
            isSelected and S.COLOR.NAV_ACTIVE[2] or 0,
            isSelected and S.COLOR.NAV_ACTIVE[3] or 0,
            isSelected and 1 or 0
        )

        local memberCount = g.members and #g.members or 0
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", btn, "LEFT", 10, 2)
        label:SetText(g.name)
        label:SetTextColor(isSelected and 1 or S.COLOR.TEXT[1], isSelected and 1 or S.COLOR.TEXT[2], isSelected and 1 or S.COLOR.TEXT[3])

        local countLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countLabel:SetPoint("LEFT", btn, "LEFT", 10, -10)
        countLabel:SetText(memberCount .. " member" .. (memberCount == 1 and "" or "s"))
        countLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

        btn:SetScript("OnClick", function()
            selectedGroupId = g.id
            UI:RefreshGroupsTab()
            UI:RefreshGroupDetail(g.id)
        end)

        totalH = totalH + 36
    end
    content:SetHeight(math.max(totalH, 10))

    if selectedGroupId then
        UI:RefreshGroupDetail(selectedGroupId)
    else
        if frame.placeholder then frame.placeholder:Show() end
        if frame.detailTitle  then frame.detailTitle:SetText("") end
    end
end

function UI:RefreshGroupDetail(groupId)
    local frame = UI.GroupsTab
    if not frame then return end

    local g = GH.Groups:Get(groupId)
    if not g then return end

    frame.placeholder:Hide()
    frame.detailTitle:SetText(g.name)

    local content = frame.memberContent
    for i = content:GetNumChildren(), 1, -1 do
        local child = select(i, content:GetChildren())
        child:Hide()
    end

    local members = g.members or {}
    for i, memberName in ipairs(members) do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * 30)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -(i - 1) * 30)
        row:SetHeight(28)
        row:Show()

        if i % 2 == 0 then
            S:Bg(row, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.6)
        end

        local info = GH.GuildData.byName[memberName]
        local cr, cg, cb = 0.7, 0.7, 0.7
        local online = false
        if info then
            cr, cg, cb = GH.GuildData:GetClassColor(info.classFileName)
            online = info.online
        end

        local dot = row:CreateTexture(nil, "OVERLAY")
        dot:SetSize(7, 7)
        dot:SetPoint("LEFT", row, "LEFT", 6, 0)
        if online then
            dot:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 1)
        else
            dot:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 1)
        end

        local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("LEFT", row, "LEFT", 20, 0)
        nameLabel:SetText(memberName)
        nameLabel:SetTextColor(cr, cg, cb)

        if info and info.rank then
            local rankLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            rankLabel:SetPoint("LEFT", row, "LEFT", 180, 0)
            rankLabel:SetText(info.rank)
            rankLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end

        local removeBtn = S:DangerButton(row, "×", 22, 20)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        local capturedName = memberName
        removeBtn:SetScript("OnClick", function()
            GH.Groups:RemoveMember(groupId, capturedName)
            UI:RefreshGroupDetail(groupId)
        end)
    end

    content:SetHeight(math.max(#members * 30, 10))
end

-- Simple single-line name input dialog reused by Groups and Chat tabs.
function UI:ShowGroupNameDialog(existingName, callback)
    local dlg = CreateFrame("Frame", "GuildHubNameDialog", UIParent)
    dlg:SetSize(320, 110)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    dlg:SetFrameStrata("DIALOG")
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText(existingName and "Rename" or "New Group Name")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local eb = S:EditBox(dlg, 280, 28, 60)
    eb:SetPoint("TOP", title, "BOTTOM", 0, -10)
    if existingName then eb:SetText(existingName) end
    eb:SetFocus()

    local okBtn = S:Button(dlg, "OK", 80, 26)
    okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 12)
    okBtn:SetScript("OnClick", function()
        local name = eb:GetText():match("^%s*(.-)%s*$")
        if name ~= "" then callback(name) end
        dlg:Hide()
    end)

    local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 12)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)

    eb:SetScript("OnEnterPressed", function()
        local name = eb:GetText():match("^%s*(.-)%s*$")
        if name ~= "" then callback(name) end
        dlg:Hide()
    end)
end
