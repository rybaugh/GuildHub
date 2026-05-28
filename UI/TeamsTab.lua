-- GuildHub - Teams Tab
-- Horizontal team tab strip at top, member presence strip, full-width chat area.

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local CreateFrame = _G.CreateFrame
local GetTime     = _G.GetTime

local selected  = nil
local lastMsgTs = 0
local lastMsgId = nil

local TAB_H    = 38
local INP_H    = 46
local ROSTER_W = 190

-- ── Helpers ───────────────────────────────────────────────────────────────

local function EnsureTeamChannel(groupId)
    local g = GH.Groups:Get(groupId)
    if not g then return nil end
    if g.channelId and GH.DB:GetChat(g.channelId) then
        return g.channelId
    end
    local myName     = GH:GetPlayerName()
    local chanMembers = {}
    local hasMe      = false
    for _, n in ipairs(g.members or {}) do
        chanMembers[#chanMembers + 1] = n
        if n == myName then hasMe = true end
    end
    if not hasMe then chanMembers[#chanMembers + 1] = myName end
    local channelId = GH.Chat:CreateChannel(g.name, chanMembers, groupId)
    GH.Groups:SetChannel(groupId, channelId)
    return channelId
end

local function HexToRGB(hex)
    hex = hex or "7289DA"
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r or 0.45, g or 0.54, b or 0.85
end

-- ── Construction ──────────────────────────────────────────────────────────

function UI:CreateTeamsTab(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.TeamsTab = frame

    -- ── Team tab strip ─────────────────────────────────────────────────────
    local tabStrip = CreateFrame("Frame", nil, frame)
    tabStrip:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    tabStrip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tabStrip:SetHeight(TAB_H)
    S:GradientBg(tabStrip, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL_HDR_B[1], S.COLOR.PANEL_HDR_B[2], S.COLOR.PANEL_HDR_B[3], 1)
    frame.tabStrip = tabStrip

    local stripDiv = tabStrip:CreateTexture(nil, "ARTWORK")
    stripDiv:SetPoint("BOTTOMLEFT",  tabStrip)
    stripDiv:SetPoint("BOTTOMRIGHT", tabStrip)
    stripDiv:SetHeight(1)
    stripDiv:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.15)

    -- Right-pinned action buttons (always visible, guards handle nothing-selected)
    local newTeamBtn = S:Button(tabStrip, "+ New Team", 96, 26)
    newTeamBtn:SetPoint("RIGHT", tabStrip, "RIGHT", -8, 0)
    newTeamBtn:SetScript("OnClick", function()
        UI:ShowTeamNameDialog(nil, function(name)
            local groupId = GH.Groups:Create(name)
            selected = groupId
            UI:RefreshTeamsGroupList()
            UI:ShowTeamView(groupId)
        end)
    end)

    local deleteBtn = S:DangerButton(tabStrip, "Delete", 70, 26)
    deleteBtn:SetPoint("RIGHT", newTeamBtn, "LEFT", -6, 0)
    deleteBtn:SetScript("OnClick", function()
        if not selected or not GH:CanManageTeam(selected) then return end
        GH.Groups:Delete(selected)
        selected = nil
        UI:RefreshTeamsGroupList()
        frame.placeholder:Show()
        frame.rosterPanel:Hide()
        frame:UpdateLayout(false)
        frame.deleteBtn:SetAlpha(0.35)
        frame.membersBtn:SetAlpha(0.35)
        frame.inviteBtn:SetAlpha(0.35)
    end)

    local membersBtn = S:Button(tabStrip, "Members", 78, 26)
    membersBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -4, 0)
    membersBtn:SetScript("OnClick", function()
        if selected then UI:ShowTeamMembersDialog(selected) end
    end)

    local inviteBtn = S:Button(tabStrip, "Invite All Online", 140, 26)
    inviteBtn:SetPoint("RIGHT", membersBtn, "LEFT", -4, 0)
    inviteBtn:SetScript("OnClick", function()
        if selected then GH.Groups:InviteAll(selected) end
    end)

    -- Start dimmed (no team selected); officer-only buttons are shown/hidden in OnShow
    deleteBtn:SetAlpha(0.35)
    membersBtn:SetAlpha(0.35)
    inviteBtn:SetAlpha(0.35)

    frame.newTeamBtn = newTeamBtn
    frame.deleteBtn  = deleteBtn
    frame.membersBtn = membersBtn
    frame.inviteBtn  = inviteBtn

    local applyBtn = S:Button(tabStrip, "Apply", 80, 26)
    applyBtn:SetPoint("RIGHT", inviteBtn, "LEFT", -4, 0)
    applyBtn:Hide()
    frame.applyBtn = applyBtn

    local appsBtn = S:Button(tabStrip, "Applications", 110, 26)
    appsBtn:SetPoint("RIGHT", applyBtn, "LEFT", -4, 0)
    appsBtn:Hide()
    frame.appsBtn = appsBtn

    applyBtn:SetScript("OnClick", function()
        if not selected then return end
        local app = GH.TeamApps:GetMyApplication(selected)
        if app and app.status == "pending" then return end
        GH.UI:ShowTeamApplicationForm(selected)
    end)

    appsBtn:SetScript("OnClick", function()
        if selected then GH.UI:ShowTeamApplicationsDialog(selected) end
    end)

    -- Tab container (fills left portion of strip, horizontal scroll)
    local tabScrollFrame = CreateFrame("ScrollFrame", nil, tabStrip)
    tabScrollFrame:SetPoint("TOPLEFT",    tabStrip,  "TOPLEFT",    2, 0)
    tabScrollFrame:SetPoint("BOTTOMLEFT", tabStrip,  "BOTTOMLEFT", 2, 0)
    tabScrollFrame:SetPoint("RIGHT",      inviteBtn, "LEFT", -8, 0)
    tabScrollFrame:EnableMouseWheel(true)
    tabScrollFrame:SetScript("OnMouseWheel", function(sf, delta)
        local max = sf:GetHorizontalScrollRange()
        sf:SetHorizontalScroll(math.max(0, math.min(max, sf:GetHorizontalScroll() - delta * 80)))
    end)
    frame.tabScrollFrame = tabScrollFrame

    frame.tabScrollFrame:ClearAllPoints()
    frame.tabScrollFrame:SetPoint("TOPLEFT",    tabStrip, "TOPLEFT",    2, 0)
    frame.tabScrollFrame:SetPoint("BOTTOMLEFT", tabStrip, "BOTTOMLEFT", 2, 0)
    frame.tabScrollFrame:SetPoint("RIGHT",      appsBtn,  "LEFT",       -8, 0)

    local tabArea = CreateFrame("Frame", nil, tabScrollFrame)
    tabArea:SetHeight(TAB_H)
    tabScrollFrame:SetScrollChild(tabArea)
    frame.tabArea = tabArea

    -- ── Team roster sidebar ───────────────────────────────────────────────────
    local rosterPanel = CreateFrame("Frame", nil, frame)
    rosterPanel:SetWidth(ROSTER_W)
    rosterPanel:SetPoint("TOPRIGHT",    tabStrip, "BOTTOMRIGHT", 0, -1)
    rosterPanel:SetPoint("BOTTOMRIGHT", frame,    "BOTTOMRIGHT", 0, INP_H)
    rosterPanel:Hide()
    frame.rosterPanel = rosterPanel
    S:GradientBg(rosterPanel, "VERTICAL",
        S.COLOR.SIDEBAR[1] + 0.005, S.COLOR.SIDEBAR[2] + 0.004, S.COLOR.SIDEBAR[3] + 0.010, 1,
        S.COLOR.SIDEBAR[1],         S.COLOR.SIDEBAR[2],         S.COLOR.SIDEBAR[3],          1)

    local rosterDiv = rosterPanel:CreateTexture(nil, "BORDER")
    rosterDiv:SetWidth(1)
    rosterDiv:SetPoint("TOPLEFT",    rosterPanel, "TOPLEFT",    0, 0)
    rosterDiv:SetPoint("BOTTOMLEFT", rosterPanel, "BOTTOMLEFT", 0, 0)
    rosterDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.6)

    local rosterHdr = CreateFrame("Frame", nil, rosterPanel)
    rosterHdr:SetPoint("TOPLEFT",  rosterPanel, "TOPLEFT",  0, 0)
    rosterHdr:SetPoint("TOPRIGHT", rosterPanel, "TOPRIGHT", 0, 0)
    rosterHdr:SetHeight(34)
    S:GradientBg(rosterHdr, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL_HDR_B[1], S.COLOR.PANEL_HDR_B[2], S.COLOR.PANEL_HDR_B[3], 1)
    local rosterHdrSep = rosterHdr:CreateTexture(nil, "ARTWORK")
    rosterHdrSep:SetPoint("BOTTOMLEFT",  rosterHdr, "BOTTOMLEFT")
    rosterHdrSep:SetPoint("BOTTOMRIGHT", rosterHdr, "BOTTOMRIGHT")
    rosterHdrSep:SetHeight(1)
    rosterHdrSep:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

    local rosterCountFS = S:FS(rosterHdr, "OVERLAY")
    rosterCountFS:SetPoint("LEFT",  rosterHdr, "LEFT",  10, 0)
    rosterCountFS:SetPoint("RIGHT", rosterHdr, "RIGHT", -6, 0)
    rosterCountFS:SetJustifyH("LEFT")
    rosterCountFS:SetText("Members")
    rosterCountFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    frame.rosterCountFS = rosterCountFS

    local rosterSf = CreateFrame("ScrollFrame", nil, rosterPanel)
    rosterSf:SetPoint("TOPLEFT",     rosterPanel, "TOPLEFT",     1, -36)
    rosterSf:SetPoint("BOTTOMRIGHT", rosterPanel, "BOTTOMRIGHT", -4, 4)
    rosterSf:EnableMouseWheel(true)
    rosterSf:SetScript("OnMouseWheel", function(sf, delta)
        local max = sf:GetVerticalScrollRange()
        sf:SetVerticalScroll(math.max(0, math.min(max, sf:GetVerticalScroll() - delta * 30)))
    end)
    local rosterContent = CreateFrame("Frame", nil, rosterSf)
    rosterSf:SetScrollChild(rosterContent)
    local function SyncRosterWidth()
        local w = rosterSf:GetWidth()
        if w > 0 then rosterContent:SetWidth(w) end
    end
    rosterSf:SetScript("OnSizeChanged", SyncRosterWidth)
    C_Timer.After(0, SyncRosterWidth)
    frame.rosterContent = rosterContent
    frame.rosterRows    = {}

    -- ── Message area ──────────────────────────────────────────────────────
    local msgPanel = CreateFrame("Frame", nil, frame)
    msgPanel:SetPoint("TOPLEFT",     tabStrip, "BOTTOMLEFT",  0, -1)
    msgPanel:SetPoint("BOTTOMRIGHT", frame,    "BOTTOMRIGHT", -ROSTER_W, INP_H)
    S:Bg(msgPanel, 0, 0, 0, 0.08)
    frame.msgPanel = msgPanel

    function frame:UpdateLayout(rosterShown)
        msgPanel:ClearAllPoints()
        msgPanel:SetPoint("TOPLEFT",     tabStrip, "BOTTOMLEFT",  0, -1)
        msgPanel:SetPoint("BOTTOMRIGHT", frame,    "BOTTOMRIGHT", rosterShown and -ROSTER_W or 0, INP_H)
    end

    -- Plain scroll frame (no template) so no scrollbar widget can escape the
    -- window edge at any width.  Mouse wheel scrolls history; new messages
    -- auto-scroll to the bottom via SetVerticalScroll.
    local msgSf = CreateFrame("ScrollFrame", nil, msgPanel)
    msgSf:SetPoint("TOPLEFT",     msgPanel, "TOPLEFT",     4, -4)
    msgSf:SetPoint("BOTTOMRIGHT", msgPanel, "BOTTOMRIGHT", -4, 4)
    msgSf:EnableMouseWheel(true)
    msgSf:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange()
        local new = math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40))
        self:SetVerticalScroll(new)
        local atBottom = max <= 0 or new >= max - 1
        frame._scrolledUp = not atBottom
        if frame.scrollToBottomBtn then frame.scrollToBottomBtn:SetShown(not atBottom) end
    end)

    local scrollToBottomBtn = CreateFrame("Button", nil, msgPanel)
    scrollToBottomBtn:SetSize(34, 34)
    scrollToBottomBtn:SetPoint("BOTTOMRIGHT", msgPanel, "BOTTOMRIGHT", -10, 10)
    scrollToBottomBtn:SetFrameLevel(msgPanel:GetFrameLevel() + 20)
    scrollToBottomBtn:Hide()
    local _stbArrow = scrollToBottomBtn:CreateTexture(nil, "ARTWORK")
    _stbArrow:SetAllPoints()
    _stbArrow:SetTexture("Interface/Buttons/UI-ScrollBar-ScrollDownButton-Up")
    scrollToBottomBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(scrollToBottomBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Jump to latest", 1, 1, 1)
        GameTooltip:Show()
    end)
    scrollToBottomBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    scrollToBottomBtn:SetScript("OnClick", function()
        msgSf:SetVerticalScroll(msgSf:GetVerticalScrollRange())
        frame._scrolledUp = false
        scrollToBottomBtn:Hide()
    end)
    frame.scrollToBottomBtn = scrollToBottomBtn

    local msgContent = CreateFrame("Frame", nil, msgSf)
    msgContent:SetHeight(10)
    msgSf:SetScrollChild(msgContent)

    -- Keep content width matched to the scroll frame at all times.
    local function SyncTeamMsgWidth()
        local sfW = msgSf:GetWidth()
        if sfW > 0 then msgContent:SetWidth(sfW) end
    end
    msgSf:SetScript("OnSizeChanged", SyncTeamMsgWidth)
    C_Timer.After(0, SyncTeamMsgWidth)

    frame.msgScrollFrame   = msgSf
    frame.msgScrollContent = msgContent

    local ph = S:FS(msgPanel, "OVERLAY", "normal")
    ph:SetPoint("CENTER", msgPanel, "CENTER")
    ph:SetText("Select a team or create a new one")
    ph:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame.placeholder = ph

    -- ── Input bar ─────────────────────────────────────────────────────────
    local inputBar = CreateFrame("Frame", nil, frame)
    inputBar:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
    inputBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    inputBar:SetHeight(INP_H)
    S:Bg(inputBar, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    local inputTopLine = inputBar:CreateTexture(nil, "ARTWORK")
    inputTopLine:SetPoint("TOPLEFT",  inputBar, "TOPLEFT")
    inputTopLine:SetPoint("TOPRIGHT", inputBar, "TOPRIGHT")
    inputTopLine:SetHeight(1)
    inputTopLine:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.6)

    local tvInput = S:EditBox(inputBar, 0, 28, 255)
    tvInput:SetPoint("LEFT",  inputBar, "LEFT",  10, 0)
    tvInput:SetPoint("RIGHT", inputBar, "RIGHT", -94, 0)
    frame.inputBox = tvInput

    local tvSend = S:Button(inputBar, "Send", 82, 30)
    tvSend:SetPoint("RIGHT", inputBar, "RIGHT", -8, 0)

    local function DoSend()
        if not selected then return end
        local g = GH.Groups:Get(selected)
        local channelId = g and g.channelId
        if not channelId then return end
        local text = tvInput:GetText():match("^%s*(.-)%s*$")
        if text == "" then return end
        GH.Chat:SendMessage(channelId, text)
        tvInput:SetText("")
        tvInput:ClearFocus()
        lastMsgTs = 0
        frame._scrolledUp = false
        if frame.scrollToBottomBtn then frame.scrollToBottomBtn:Hide() end
        UI:RefreshTeamChatMessages(selected)
        C_Timer.After(0.05, function()
            if frame.msgScrollFrame then
                frame.msgScrollFrame:SetVerticalScroll(
                    frame.msgScrollFrame:GetVerticalScrollRange())
            end
        end)
    end
    tvSend:SetScript("OnClick", DoSend)
    tvInput:SetScript("OnEnterPressed", function(eb) DoSend(); eb:ClearFocus() end)

    frame:SetScript("OnShow", function()
        local isOfficer = GH:IsOfficer()
        frame.newTeamBtn:SetShown(isOfficer)
        frame.deleteBtn:SetShown(isOfficer)
        frame.applyBtn:Hide()
        frame.appsBtn:Hide()
        UI:RefreshTeamsGroupList()
        if selected then UI:ShowTeamView(selected) end

        -- GM: find any teams still marked pending and queue conflict dialogs
        if GH:IsGuildMaster() then
            for pendingId, pg in pairs(GH.DB:GetGroups()) do
                if pg.pending then
                    for canonicalId, cg in pairs(GH.DB:GetGroups()) do
                        if canonicalId ~= pendingId
                           and cg.name:lower() == pg.name:lower()
                           and not cg.pending then
                            UI:EnqueueConflict(pendingId, canonicalId)
                        end
                    end
                end
            end
        end
    end)

    UI:RefreshTeamsGroupList()
end

-- ── Team tab strip ────────────────────────────────────────────────────────

function UI:RefreshTeamsGroupList()
    local frame = UI.TeamsTab
    if not frame then return end

    local tabArea = frame.tabArea
    for i = tabArea:GetNumChildren(), 1, -1 do
        select(i, tabArea:GetChildren()):Hide()
    end

    -- Reset selection if the team was deleted
    if selected and not GH.Groups:Get(selected) then
        selected = nil
        frame.placeholder:Show()
        frame.rosterPanel:Hide()
        frame:UpdateLayout(false)
        frame.deleteBtn:SetAlpha(0.35)
        frame.membersBtn:SetAlpha(0.35)
        frame.inviteBtn:SetAlpha(0.35)
    end

    local groups = GH.Groups:GetAllForBrowsing()
    local xOff   = 0

    for _, g in ipairs(groups) do
        local isActive = (selected == g.id)
        local tr, tg, tb = HexToRGB(g.color)

        local tabW = math.max(100, math.min(200, #g.name * 7 + 70 + (g.pending and 60 or 0)))

        local tab = CreateFrame("Button", nil, tabArea)
        tab:SetPoint("TOPLEFT",    tabArea, "TOPLEFT",    xOff, 0)
        tab:SetPoint("BOTTOMLEFT", tabArea, "BOTTOMLEFT", xOff, 1)
        tab:SetWidth(tabW)
        tab:Show()

        -- Background
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if isActive then
            bg:SetColorTexture(S.COLOR.BG[1] + 0.03, S.COLOR.BG[2] + 0.03, S.COLOR.BG[3] + 0.07, 1)
        else
            bg:SetColorTexture(0, 0, 0, 0)
        end

        -- Active bottom accent (team color)
        if isActive then
            local accentF = CreateFrame("Frame", nil, tab)
            accentF:SetPoint("BOTTOMLEFT",  tab, "BOTTOMLEFT",  2, 0)
            accentF:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 0)
            accentF:SetHeight(2)
            accentF:Show()
            local accentT = accentF:CreateTexture(nil, "ARTWORK")
            accentT:SetAllPoints()
            accentT:SetColorTexture(tr, tg, tb, 1)
        end

        tab:SetScript("OnEnter", function()
            if not isActive then bg:SetColorTexture(1, 1, 1, 0.04) end
        end)
        tab:SetScript("OnLeave", function()
            if not isActive then bg:SetColorTexture(0, 0, 0, 0) end
        end)

        -- Color swatch (team color, small rounded square)
        local swatchF = CreateFrame("Frame", nil, tab)
        swatchF:SetSize(10, 20)
        swatchF:SetPoint("LEFT", tab, "LEFT", 8, 0)
        swatchF:Show()
        local swatchT = swatchF:CreateTexture(nil, "OVERLAY")
        swatchT:SetAllPoints()
        swatchT:SetColorTexture(tr, tg, tb, isActive and 0.9 or 0.5)

        -- Team name
        local nameFs = S:FS(tab, "OVERLAY")
        nameFs:SetPoint("LEFT",  tab, "LEFT",  22, 0)
        nameFs:SetPoint("RIGHT", tab, "RIGHT", -8, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        if g.pending then
            nameFs:SetText(g.name .. " |cff888888(pending)|r")
            nameFs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2] * 0.6, S.COLOR.TEXT_DIM[3] * 0.6)
        elseif isActive then
            nameFs:SetText(g.name)
            nameFs:SetTextColor(1, 1, 1)
        else
            nameFs:SetText(g.name)
            nameFs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end

        local capturedId = g.id
        tab:SetScript("OnClick", function()
            selected = capturedId
            UI:RefreshTeamsGroupList()
            UI:ShowTeamView(capturedId)
        end)

        xOff = xOff + tabW
    end

    tabArea:SetWidth(math.max(xOff, 1))

    -- Scroll to reveal the selected tab if it's out of view
    if selected and frame.tabScrollFrame then
        C_Timer.After(0, function()
            local sf  = frame.tabScrollFrame
            local sfW = sf:GetWidth()
            if sfW <= 0 then return end
            local selX, selW = 0, 0
            local xCheck = 0
            for _, g in ipairs(GH.Groups:GetAll()) do
                local tw = math.max(100, math.min(200, #g.name * 7 + 70 + (g.pending and 60 or 0)))
                if g.id == selected then selX = xCheck; selW = tw; break end
                xCheck = xCheck + tw
            end
            local scroll = sf:GetHorizontalScroll()
            if selX < scroll then
                sf:SetHorizontalScroll(selX)
            elseif selX + selW > scroll + sfW then
                sf:SetHorizontalScroll(selX + selW - sfW)
            end
        end)
    end
end

function UI:RefreshTeamsApplicationsBadge()
    local frame = UI.TeamsTab
    if not frame or not selected then return end
    if not frame.appsBtn then return end

    if not GH:CanManageTeam(selected) then
        frame.appsBtn:Hide()
        return
    end

    local count = GH.TeamApps:GetPendingCount(selected)
    if count > 0 then
        frame.appsBtn:SetText("Applications (" .. count .. ")")
        frame.appsBtn:Show()
    else
        frame.appsBtn:Hide()
    end
end

-- ── Team view ─────────────────────────────────────────────────────────────

function UI:ShowTeamView(groupId)
    local frame = UI.TeamsTab
    if not frame then return end
    local g = GH.Groups:Get(groupId)
    if not g then return end

    -- Determine membership and management status
    local myName    = GH:GetPlayerName()
    local isMember  = false
    for _, n in ipairs(g.members or {}) do
        if n == myName then isMember = true; break end
    end
    local canManage = GH:CanManageTeam(groupId)
    local isVisible = isMember or canManage

    frame.placeholder:Hide()

    frame.deleteBtn:SetAlpha(canManage and 1 or 0.35)

    if isVisible then
        frame.membersBtn:SetAlpha(1)
        frame.inviteBtn:SetAlpha(1)
        frame.applyBtn:Hide()

        EnsureTeamChannel(groupId)
        UI:RefreshTeamRoster(groupId)
        frame._scrolledUp = false
        if frame.scrollToBottomBtn then frame.scrollToBottomBtn:Hide() end
        lastMsgTs = 0
        UI:RefreshTeamChatMessages(groupId)
    else
        frame.membersBtn:SetAlpha(0.35)
        frame.inviteBtn:SetAlpha(0.35)

        local app = GH.TeamApps:GetMyApplication(groupId)
        if app and app.status == "pending" then
            frame.applyBtn:SetText("Application Pending")
            frame.applyBtn:SetAlpha(0.5)
            frame.applyBtn:SetScript("OnClick", nil)
        else
            frame.applyBtn:SetText("Apply")
            frame.applyBtn:SetAlpha(1)
            frame.applyBtn:SetScript("OnClick", function()
                GH.UI:ShowTeamApplicationForm(groupId)
            end)
        end
        frame.applyBtn:Show()

        frame.rosterPanel:Hide()
        frame:UpdateLayout(false)

        local memberCount = #(g.members or {})
        frame.placeholder:SetText(
            "|cffffd700" .. g.name .. "|r\n" ..
            memberCount .. " member" .. (memberCount == 1 and "" or "s") .. "\n\n" ..
            "|cff888888Apply using the button above to request membership.|r")
        frame.placeholder:Show()
    end

    UI:RefreshTeamsApplicationsBadge()
end

function UI:RefreshTeamRoster(groupId)
    local frame = UI.TeamsTab
    if not frame then return end

    local rosterPanel   = frame.rosterPanel
    local rosterContent = frame.rosterContent
    local rows          = frame.rosterRows

    local g = groupId and GH.Groups:Get(groupId)
    if not g or #(g.members or {}) == 0 then
        rosterPanel:Hide()
        frame:UpdateLayout(false)
        return
    end

    local sorted = {}
    for _, name in ipairs(g.members) do
        local info = GH.GuildData:FindMember(name)
        sorted[#sorted + 1] = { name = name, info = info, online = info and info.online }
    end
    table.sort(sorted, function(a, b)
        if a.online ~= b.online then return (a.online and 1 or 0) > (b.online and 1 or 0) end
        return a.name < b.name
    end)

    local onlineNum = 0
    for _, m in ipairs(sorted) do if m.online then onlineNum = onlineNum + 1 end end
    frame.rosterCountFS:SetText("Members — |cff22cc44" .. onlineNum .. "|r/" .. #sorted)

    local ROW_H = 28
    for _, row in ipairs(rows) do row:Hide() end

    for i, m in ipairs(sorted) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, rosterContent)
            row:SetHeight(ROW_H)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(0, 0, 0, 0)
            row.rowBg = rowBg

            local dot = row:CreateTexture(nil, "OVERLAY")
            dot:SetSize(7, 7)
            dot:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.dot = dot

            local nameFS = S:FS(row, "OVERLAY")
            nameFS:SetPoint("LEFT",  row, "LEFT",  20, 0)
            nameFS:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            nameFS:SetJustifyH("LEFT")
            row.nameFS = nameFS

            rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  rosterContent, "TOPLEFT",  0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", rosterContent, "TOPRIGHT", 0, -(i - 1) * ROW_H)

        local cr, cg, cb = 0.7, 0.7, 0.7
        if m.info then cr, cg, cb = GH.GuildData:GetClassColor(m.info.classFileName) end
        if not m.online then cr, cg, cb = cr * 0.55, cg * 0.55, cb * 0.55 end

        if m.online then
            local status = m.info and m.info.status or 0
            if     status == 1 then row.dot:SetColorTexture(S.COLOR.AFK[1],    S.COLOR.AFK[2],    S.COLOR.AFK[3],    1)
            elseif status == 2 then row.dot:SetColorTexture(S.COLOR.DND[1],    S.COLOR.DND[2],    S.COLOR.DND[3],    1)
            else                    row.dot:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 1)
            end
        else
            row.dot:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.5)
        end

        row.nameFS:SetText(m.name)
        row.nameFS:SetTextColor(cr, cg, cb)
        row:Show()
    end

    rosterContent:SetHeight(math.max(#sorted * ROW_H, 10))
    rosterPanel._groupId = groupId
    rosterPanel:Show()
    frame:UpdateLayout(true)
end

function UI:RefreshTeamChatMessages(groupId)
    if selected ~= groupId then return end
    local frame = UI.TeamsTab
    if not frame or not frame:IsShown() then return end

    local g = GH.Groups:Get(groupId)
    local channelId = g and g.channelId
    if not channelId then return end

    local now = GetTime and GetTime() or 0
    if channelId == lastMsgId and now - lastMsgTs < 0.08 then return end
    lastMsgId = channelId
    lastMsgTs = now

    local messages = GH.Chat:GetMessages(channelId)
    local myName   = GH:GetPlayerName()
    UI:RenderChatMessages(frame.msgScrollContent, messages, myName)

    C_Timer.After(0.05, function()
        if frame.msgScrollFrame and not frame._scrolledUp then
            frame.msgScrollFrame:SetVerticalScroll(
                frame.msgScrollFrame:GetVerticalScrollRange())
        end
    end)
end

-- ── ChatManager callbacks ─────────────────────────────────────────────────
-- TeamsTab.lua is loaded after ChatTab.lua, so this definition is final.
-- Both tabs' needs are handled here.

function UI:OnChatMessage(channelId)
    UI:UpdateChatBadge()
    if UI.ChatTab and UI.ChatTab:IsShown() then
        UI:RefreshChatMessages(channelId)
    end
    if UI.TeamsTab and UI.TeamsTab:IsShown() and selected then
        local g = GH.Groups:Get(selected)
        if g and g.channelId == channelId then
            lastMsgTs = 0
            UI:RefreshTeamChatMessages(selected)
        end
    end
end

function UI:OnChannelListChanged()
    if UI.ChatTab and UI.ChatTab:IsShown() then
        UI:RefreshChatChannelList()
    end
end

-- ── Shared chat renderer ──────────────────────────────────────────────────
-- Used by TeamsTab and MembersTab.

function UI:RenderChatMessages(content, messages, _)
    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    local GAP_THRESHOLD = 3600
    local yOff   = 4
    local prevTs = nil
    local rowIdx = 0

    for _, msg in ipairs(messages) do
        if msg.text ~= nil then
            rowIdx = rowIdx + 1

            if prevTs and msg.ts - prevTs > GAP_THRESHOLD then
                local gapRow = CreateFrame("Frame", nil, content)
                gapRow:SetPoint("TOPLEFT",  content, "TOPLEFT",  4, -yOff)
                gapRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -yOff)
                gapRow:SetHeight(22)
                gapRow:Show()
                local line = gapRow:CreateTexture(nil, "BACKGROUND")
                line:SetPoint("LEFT",  gapRow, "LEFT",  4, 0)
                line:SetPoint("RIGHT", gapRow, "RIGHT", -4, 0)
                line:SetHeight(1)
                line:SetColorTexture(0.5, 0.5, 0.6, 0.4)
                local gapText = S:FS(gapRow, "OVERLAY")
                gapText:SetPoint("CENTER", gapRow, "CENTER")
                gapText:SetText("History gap — some messages may be missing")
                gapText:SetTextColor(0.7, 0.7, 0.8)
                yOff = yOff + 26
            end
            prevTs = msg.ts

            local shortSender = msg.sender:match("^([^%-]+)") or msg.sender
            local myName      = GH:GetPlayerName()
            local isSelf      = (shortSender == myName)

            local nr, ng, nb
            local memberInfo = GH.GuildData:FindMember(msg.sender)
            if memberInfo then
                nr, ng, nb = GH.GuildData:GetClassColor(memberInfo.classFileName)
            elseif isSelf then
                nr, ng, nb = S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3]
            else
                nr, ng, nb = S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3]
            end

            local row = CreateFrame("Frame", nil, content)
            row:SetPoint("TOPLEFT",  content, "TOPLEFT",  4, -yOff)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -yOff)
            row:Show()

            if rowIdx % 2 == 0 then
                local stripe = row:CreateTexture(nil, "BACKGROUND")
                stripe:SetAllPoints()
                stripe:SetColorTexture(1, 1, 1, 0.025)
            end

            local timeFs = S:FS(row, "OVERLAY")
            timeFs:SetPoint("LEFT", row, "LEFT", 0, 0)
            timeFs:SetText("|cff555566[" .. GH:FormatTime(msg.ts) .. "]|r ")
            timeFs:SetTextColor(1, 1, 1)
            local timeW = timeFs:GetStringWidth() + 2

            local senderBtn = CreateFrame("Button", nil, row)
            senderBtn:SetPoint("LEFT", row, "LEFT", timeW, 0)
            senderBtn:SetHeight(14)
            local senderFs = S:FS(senderBtn, "OVERLAY", "normal")
            senderFs:SetAllPoints()
            senderFs:SetJustifyH("LEFT")
            senderFs:SetText(shortSender .. ":")
            senderFs:SetTextColor(nr, ng, nb)
            local senderW = senderFs:GetStringWidth() + 6
            senderBtn:SetWidth(senderW)

            if not isSelf then
                local capturedSender = msg.sender
                senderBtn:SetScript("OnClick", function()
                    local fn = rawget(_G, "ChatFrame_OpenChat")
                    if fn then fn("/w " .. capturedSender .. " ") end
                end)
                senderBtn:SetScript("OnEnter", function()
                    local gt = rawget(_G, "GameTooltip")
                    if gt then
                        gt:SetOwner(senderBtn, "ANCHOR_TOP")
                        gt:SetText("Whisper " .. shortSender, 1, 1, 1)
                        gt:Show()
                    end
                end)
                senderBtn:SetScript("OnLeave", function()
                    local gt = rawget(_G, "GameTooltip")
                    if gt then gt:Hide() end
                end)
            end

            local bodyIndent = timeW + senderW + 4
            local bodyFs = S:FS(row, "OVERLAY")
            bodyFs:SetPoint("LEFT",  row, "LEFT",  bodyIndent, 0)
            bodyFs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            bodyFs:SetJustifyH("LEFT")
            bodyFs:SetJustifyV("TOP")
            bodyFs:SetText(" " .. msg.text)
            bodyFs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
            bodyFs:SetWordWrap(true)
            bodyFs:SetNonSpaceWrap(false)

            local rowH = math.max(bodyFs:GetStringHeight(), 14) + 8
            row:SetHeight(rowH)
            yOff = yOff + rowH + 1
        end
    end

    content:SetHeight(math.max(yOff + 4, 10))
end

-- ── Dialogs ───────────────────────────────────────────────────────────────

function UI:ShowTeamMembersDialog(groupId)
    local g = GH.Groups:Get(groupId)
    if not g then return end

    local isOfficer = GH:CanManageTeam(groupId)
    local dlgH = isOfficer and 390 or 310

    local dlg = CreateFrame("Frame", "GuildHubTeamMembersDialog", UIParent)
    dlg:SetSize(300, dlgH)
    dlg:ClearAllPoints()
    local mainWin = rawget(_G, "GuildHubMainWindow")
    if mainWin then
        dlg:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", 4, 0)
    else
        dlg:SetPoint("CENTER")
    end
    dlg:SetFrameStrata("DIALOG")
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local accent = dlg:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.80)

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -14)
    title:SetText(g.name .. " — Members")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local roleNote = S:FS(dlg, "OVERLAY")
    roleNote:SetPoint("TOP", title, "BOTTOM", 0, -2)
    if isOfficer then
        roleNote:SetText("Officers only: invite members who are currently online")
        roleNote:SetTextColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3])
    else
        roleNote:SetText("Contact an officer to join or leave this team")
        roleNote:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    local listBottom = isOfficer and 80 or 40
    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     dlg, "TOPLEFT",     10, -44)
    sf:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -24, listBottom)
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(256, 10)
    sf:SetScrollChild(sc)

    local function PopulateMembers()
        for i = sc:GetNumChildren(), 1, -1 do select(i, sc:GetChildren()):Hide() end
        local grp = GH.Groups:Get(groupId)
        if not grp then return end
        for i, memberName in ipairs(grp.members or {}) do
            local row = CreateFrame("Frame", nil, sc)
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(i - 1) * 30)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(i - 1) * 30)
            row:SetHeight(28)
            row:Show()

            local info   = GH.GuildData.byName[memberName]
            local online = info and info.online
            local cr, cg, cb = 0.7, 0.7, 0.7
            if info then cr, cg, cb = GH.GuildData:GetClassColor(info.classFileName) end

            local dot = row:CreateTexture(nil, "OVERLAY")
            dot:SetSize(7, 7)
            dot:SetPoint("LEFT", row, "LEFT", 6, 0)
            if online then
                dot:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 1)
            else
                dot:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 1)
            end

            local nm = S:FS(row, "OVERLAY", "normal")
            nm:SetPoint("LEFT", row, "LEFT", 20, 0)
            nm:SetText(memberName)
            nm:SetTextColor(cr, cg, cb)

            if isOfficer then
                local capturedName = memberName
                local rmBtn = S:DangerButton(row, "x", 22, 20)
                rmBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                rmBtn:SetScript("OnClick", function()
                    GH.Groups:RemoveMember(groupId, capturedName)
                    local grp2 = GH.Groups:Get(groupId)
                    if grp2 and grp2.channelId then
                        GH.Chat:RemoveMember(grp2.channelId, capturedName)
                    end
                    PopulateMembers()
                    UI:RefreshTeamsGroupList()
                end)
            end
        end
        local grp2 = GH.Groups:Get(groupId)
        sc:SetHeight(math.max(#(grp2 and grp2.members or {}) * 30, 10))
    end
    PopulateMembers()

    if isOfficer then
        local inviteBox = S:EditBox(dlg, 180, 26, 60)
        inviteBox:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 10, 42)

        local inviteBtn = S:Button(dlg, "Invite", 72, 26)
        inviteBtn:SetPoint("LEFT", inviteBox, "RIGHT", 4, 0)

        local hint = S:FS(inviteBox, "OVERLAY")
        hint:SetPoint("LEFT", inviteBox, "LEFT", 8, 0)
        hint:SetTextColor(0.4, 0.4, 0.5)
        hint:SetText("Online member name…")
        inviteBox:SetScript("OnEditFocusGained", function() hint:Hide() end)
        inviteBox:SetScript("OnEditFocusLost", function()
            if inviteBox:GetText() == "" then hint:Show() end
        end)

        local sugFrame = CreateFrame("Frame", nil, dlg)
        sugFrame:SetPoint("BOTTOMLEFT",  inviteBox, "TOPLEFT",  0, 4)
        sugFrame:SetPoint("BOTTOMRIGHT", inviteBtn,  "TOPRIGHT", 0, 4)
        sugFrame:SetHeight(110)
        S:Bg(sugFrame, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.95)
        sugFrame:Hide()

        local sugSf = CreateFrame("ScrollFrame", nil, sugFrame, "UIPanelScrollFrameTemplate")
        sugSf:SetPoint("TOPLEFT",     sugFrame, "TOPLEFT",     0,   0)
        sugSf:SetPoint("BOTTOMRIGHT", sugFrame, "BOTTOMRIGHT", -18, 0)
        local sugC = CreateFrame("Frame", nil, sugSf)
        sugC:SetPoint("TOPLEFT",  sugSf, "TOPLEFT",  0, 0)
        sugC:SetPoint("TOPRIGHT", sugSf, "TOPRIGHT", -18, 0)
        sugC:SetHeight(10)
        sugSf:SetScrollChild(sugC)

        local sugRows = {}

        local function IsMember(name)
            local grp = GH.Groups:Get(groupId)
            for _, n in ipairs(grp and grp.members or {}) do
                if n == name then return true end
            end
            return false
        end

        local function UpdateSuggestions()
            local filter  = inviteBox:GetText():match("^%s*(.-)%s*$") or ""
            local matches = filter == "" and {} or GH.GuildData:GetMembers(filter)
            local shown   = 0
            local numC    = select("#", sugC:GetChildren())
            for i = 1, numC do select(i, sugC:GetChildren()):Hide() end
            for _, member in ipairs(matches) do
                if shown >= 6 then break end
                if member.online and not IsMember(member.name) then
                    shown = shown + 1
                    local r = sugRows[shown]
                    if not r then
                        r = CreateFrame("Button", nil, sugC)
                        r:SetHeight(22)
                        r:SetPoint("LEFT",  sugC, "LEFT",  0, 0)
                        r:SetPoint("RIGHT", sugC, "RIGHT", 0, 0)
                        r.text = S:FS(r, "OVERLAY")
                        r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
                        r.text:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
                        r.bg = r:CreateTexture(nil, "BACKGROUND")
                        r.bg:SetAllPoints()
                        r.bg:SetColorTexture(0, 0, 0, 0)
                        r:SetScript("OnEnter", function(btn)
                            btn.bg:SetColorTexture(0.4, 0.4, 0.5, 0.25)
                        end)
                        r:SetScript("OnLeave", function(btn)
                            btn.bg:SetColorTexture(0, 0, 0, 0)
                        end)
                        r:SetScript("OnClick", function(btn)
                            inviteBox:SetText(btn.memberName)
                            sugFrame:Hide()
                            inviteBox:SetFocus()
                        end)
                        sugRows[shown] = r
                    end
                    r.memberName = member.name
                    r.text:SetText(member.name .. " |cff22cc44●|r")
                    r:SetPoint("TOPLEFT",  sugC, "TOPLEFT",  0, -(shown - 1) * 24)
                    r:SetPoint("TOPRIGHT", sugC, "TOPRIGHT", 0, -(shown - 1) * 24)
                    r:Show()
                end
            end
            if shown == 0 then sugFrame:Hide(); return end
            sugC:SetHeight(shown * 24)
            sugFrame:Show()
        end

        inviteBox:SetScript("OnTextChanged", UpdateSuggestions)

        local function DoInvite()
            local name = inviteBox:GetText():match("^%s*(.-)%s*$")
            if name ~= "" then
                if GH.Groups:SendInvite(groupId, name) then
                    inviteBox:SetText("")
                    hint:Show()
                    sugFrame:Hide()
                end
            end
        end
        inviteBtn:SetScript("OnClick", DoInvite)
        inviteBox:SetScript("OnEnterPressed", function(eb) DoInvite(); eb:ClearFocus() end)
    end

    local closeBtn = S:Button(dlg, "Close", 80, 26)
    closeBtn:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 10)
    closeBtn:SetScript("OnClick", function() dlg:Hide() end)
end

-- ── Team invite popup ─────────────────────────────────────────────────────

function UI:ShowTeamInvitePopup(groupId, teamName, inviterName)
    local dlg = rawget(_G, "GuildHubTeamInvitePopup")
    if dlg then dlg:Hide() end

    dlg = CreateFrame("Frame", "GuildHubTeamInvitePopup", UIParent)
    dlg:SetSize(340, 124)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetMovable(true)
    dlg:EnableMouse(true)
    dlg:SetScript("OnMouseDown", function() dlg:StartMoving() end)
    dlg:SetScript("OnMouseUp",   function() dlg:StopMovingOrSizing() end)
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local accent = dlg:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.80)

    local heading = S:FS(dlg, "OVERLAY", "normal")
    heading:SetPoint("TOP", dlg, "TOP", 0, -14)
    heading:SetText("Team Invite")
    heading:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local body = S:FS(dlg, "OVERLAY")
    body:SetPoint("TOP", heading, "BOTTOM", 0, -6)
    body:SetText("|cffffd700" .. inviterName .. "|r invited you to join |cffffd700"
                 .. teamName .. "|r")
    body:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

    local acceptBtn = S:Button(dlg, "Accept", 110, 28)
    acceptBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 26, 12)
    acceptBtn:SetScript("OnClick", function()
        GH.Groups:AcceptInvite(groupId)
        dlg:Hide()
    end)

    local declineBtn = S:DangerButton(dlg, "Decline", 110, 28)
    declineBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -26, 12)
    declineBtn:SetScript("OnClick", function()
        GH.Groups:DeclineInvite(groupId)
        dlg:Hide()
    end)

    dlg:Show()

    C_Timer.After(90, function()
        if dlg and dlg:IsShown() then
            GH.Groups.pendingInvites[groupId] = nil
            dlg:Hide()
        end
    end)
end

-- ── Name dialogs ──────────────────────────────────────────────────────────

function UI:ShowTeamNameDialog(existingName, callback)
    local dlg = CreateFrame("Frame", "GuildHubTeamNameDialog", UIParent)
    dlg:SetSize(320, 130)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    dlg:SetFrameStrata("DIALOG")
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText(existingName and "Rename Team" or "New Team Name")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local eb = S:EditBox(dlg, 280, 28, 60)
    eb:SetPoint("TOP", title, "BOTTOM", 0, -10)
    if existingName then eb:SetText(existingName) end
    eb:SetFocus()

    local errorFs = S:FS(dlg, "OVERLAY")
    errorFs:SetPoint("TOP", eb, "BOTTOM", 0, -4)
    errorFs:SetTextColor(1, 0.3, 0.3)
    errorFs:Hide()

    local okBtn = S:Button(dlg, "OK", 80, 26)
    okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 12)

    local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 12)

    local normalizedExisting = existingName and existingName:lower()

    local function Confirm()
        local name = eb:GetText():match("^%s*(.-)%s*$")
        if name == "" then return end
        local lower = name:lower()
        for _, g in ipairs(GH.Groups:GetAll()) do
            if g.name:lower() == lower and g.name:lower() ~= normalizedExisting then
                errorFs:SetText('"' .. name .. '" already exists.')
                errorFs:Show()
                return
            end
        end
        callback(name)
        dlg:Hide()
    end
    okBtn:SetScript("OnClick", Confirm)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    eb:SetScript("OnEnterPressed", Confirm)
end

function UI:ShowGroupNameDialog(existingName, callback)
    UI:ShowTeamNameDialog(existingName, callback)
end

-- ── GM duplicate conflict queue ───────────────────────────────────────────

UI._conflictQueue    = {}
UI._conflictShown    = false

function UI:EnqueueConflict(pendingId, canonicalId)
    -- Dedup: skip if this pair is already queued or being shown
    for _, entry in ipairs(UI._conflictQueue) do
        if entry[1] == pendingId and entry[2] == canonicalId then return end
    end
    if UI._conflictActive
       and UI._conflictActive[1] == pendingId
       and UI._conflictActive[2] == canonicalId then
        return
    end
    UI._conflictQueue[#UI._conflictQueue + 1] = { pendingId, canonicalId }
    if not UI._conflictShown then
        local next = table.remove(UI._conflictQueue, 1)
        if next then UI:ShowTeamConflictDialog(next[1], next[2]) end
    end
end

function UI:ShowTeamConflictDialog(pendingId, canonicalId)
    UI._conflictShown  = true
    UI._conflictActive = { pendingId, canonicalId }

    local pendingGroup   = GH.DB:GetGroups()[pendingId]
    local canonicalGroup = GH.DB:GetGroups()[canonicalId]
    if not pendingGroup or not canonicalGroup then
        UI._conflictShown  = false
        UI._conflictActive = nil
        local next = table.remove(UI._conflictQueue, 1)
        if next then UI:ShowTeamConflictDialog(next[1], next[2]) end
        return
    end

    local teamName = canonicalGroup.name

    local dlg = CreateFrame("Frame", nil, UIParent)
    dlg:SetSize(400, 320)
    dlg:SetFrameStrata("DIALOG")
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

    local titleFs = S:FS(dlg, "OVERLAY", "normal")
    titleFs:SetPoint("TOP", dlg, "TOP", 0, -14)
    titleFs:SetText("Duplicate Team Detected")
    titleFs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local bodyFs = S:FS(dlg, "OVERLAY")
    bodyFs:SetPoint("TOP", titleFs, "BOTTOM", 0, -6)
    bodyFs:SetText('Two teams share the name "' .. teamName .. '". Choose a resolution.')
    bodyFs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

    -- Helper: count online members
    local function OnlineCount(members)
        local n = 0
        for _, name in ipairs(members or {}) do
            local info = GH.GuildData.byName[name]
            if info and info.online then n = n + 1 end
        end
        return n
    end

    -- Side-by-side info panels
    local function MakePanel(parent, label, group, xAnchor, xOff)
        local pf = CreateFrame("Frame", nil, parent)
        pf:SetSize(172, 80)
        pf:SetPoint(xAnchor, parent, xAnchor, xOff, -80)
        S:Bg(pf, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

        local lbl = S:FS(pf, "OVERLAY")
        lbl:SetPoint("TOP", pf, "TOP", 0, -6)
        lbl:SetText(label)
        lbl:SetTextColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3])

        local nm = S:FS(pf, "OVERLAY", "normal")
        nm:SetPoint("TOP", lbl, "BOTTOM", 0, -2)
        nm:SetText(group.name)
        nm:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

        local total   = #(group.members or {})
        local online  = OnlineCount(group.members)
        local countFs = S:FS(pf, "OVERLAY")
        countFs:SetPoint("TOP", nm, "BOTTOM", 0, -4)
        countFs:SetText("Members: |cff22cc44" .. online .. "|r/" .. total)
        countFs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        return pf
    end

    MakePanel(dlg, "(older — canonical)", canonicalGroup, "TOPLEFT",  14)
    MakePanel(dlg, "(newer — pending)",   pendingGroup,   "TOPRIGHT", -14)

    -- Shared close logic
    local function CloseAndNext()
        UI._conflictShown  = false
        UI._conflictActive = nil
        dlg:Hide()
        local next = table.remove(UI._conflictQueue, 1)
        if next then
            C_Timer.After(0.1, function() UI:ShowTeamConflictDialog(next[1], next[2]) end)
        end
    end

    -- Shared resolution dispatcher
    local function Resolve(action, newName)
        local payload = table.concat(
            { "TMGMR", action, pendingId, canonicalId, newName or "" }, "\30")
        GH.Groups:_Send(payload)
        GH.Groups:_ExecuteResolution(action, pendingId, canonicalId, newName)
        CloseAndNext()
    end

    -- Rename sub-panel (hidden until Rename button clicked)
    -- Positioned between info panels and action buttons (100px above dialog bottom).
    local renamePanel = CreateFrame("Frame", nil, dlg)
    renamePanel:SetPoint("TOPLEFT",  dlg, "BOTTOMLEFT",  10, 100)
    renamePanel:SetPoint("TOPRIGHT", dlg, "BOTTOMRIGHT", -10, 100)
    renamePanel:SetHeight(50)
    renamePanel:Hide()

    local renameEb = S:EditBox(renamePanel, 230, 26, 60)
    renameEb:SetPoint("LEFT", renamePanel, "LEFT", 0, 0)

    local renameConfirm = S:Button(renamePanel, "Confirm", 90, 26)
    renameConfirm:SetPoint("LEFT", renameEb, "RIGHT", 6, 0)

    local renameErrorFs = S:FS(renamePanel, "OVERLAY")
    renameErrorFs:SetPoint("TOPLEFT", renameEb, "BOTTOMLEFT", 0, -2)
    renameErrorFs:SetTextColor(1, 0.3, 0.3)
    renameErrorFs:Hide()

    renameConfirm:SetScript("OnClick", function()
        local newName = renameEb:GetText():match("^%s*(.-)%s*$")
        if newName == "" then return end
        local lower = newName:lower()
        for _, g in ipairs(GH.Groups:GetAll()) do
            if g.name:lower() == lower and g.id ~= pendingId then
                renameErrorFs:SetText('"' .. newName .. '" already exists.')
                renameErrorFs:Show()
                return
            end
        end
        Resolve("rename", newName)
    end)

    -- Four action buttons
    local btnY = 14
    local btnH = 26

    local mergeBtn = S:Button(dlg, "Merge Members", 110, btnH)
    mergeBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 10, btnY)
    mergeBtn:SetScript("OnClick", function() Resolve("merge") end)

    local keepBtn = S:Button(dlg, "Keep Both", 84, btnH)
    keepBtn:SetPoint("LEFT", mergeBtn, "RIGHT", 4, 0)
    keepBtn:SetScript("OnClick", function() Resolve("keep") end)

    local deleteBtn = S:DangerButton(dlg, "Delete Newer", 100, btnH)
    deleteBtn:SetPoint("LEFT", keepBtn, "RIGHT", 4, 0)
    deleteBtn:SetScript("OnClick", function() Resolve("delete") end)

    local renameBtn = S:Button(dlg, "Rename Newer", 106, btnH)
    renameBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)
    renameBtn:SetScript("OnClick", function()
        renamePanel:SetShown(not renamePanel:IsShown())
        if renamePanel:IsShown() then renameEb:SetFocus() end
    end)

    dlg:Show()
end
