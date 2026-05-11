-- GuildHub - Chat Tab
-- Horizontal channel tab strip at top, full-width message area, input bar at bottom.

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local CreateFrame = _G.CreateFrame
local GetTime     = _G.GetTime

local activeChatId  = nil
local lastRefreshTs = 0
local lastRefreshId = nil

local TAB_H = 38
local INP_H = 46

local function GuildId()     return GH.Chat.GUILD_ID   end
local function OfficerId()   return GH.Chat.OFFICER_ID  end
local function XGuildId()    return GH.Chat.XGUILD_ID   end
local function IsBuiltin(id) return id == GuildId() or id == OfficerId() or id == XGuildId() end

-- Returns true if this channel is owned by a team (managed via the Teams tab).
local function IsTeamChannel(channelId)
    for _, g in ipairs(GH.Groups:GetAll()) do
        if g.channelId == channelId then return true end
    end
    return false
end

-- ── Construction ──────────────────────────────────────────────────────────

function UI:CreateChatTab(parent, w)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.ChatTab = frame

    -- ── Channel tab strip ─────────────────────────────────────────────────
    local tabStrip = CreateFrame("Frame", nil, frame)
    tabStrip:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    tabStrip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tabStrip:SetHeight(TAB_H)
    S:Bg(tabStrip, S.COLOR.SIDEBAR[1], S.COLOR.SIDEBAR[2], S.COLOR.SIDEBAR[3], 1)

    local stripDiv = tabStrip:CreateTexture(nil, "ARTWORK")
    stripDiv:SetPoint("BOTTOMLEFT",  tabStrip)
    stripDiv:SetPoint("BOTTOMRIGHT", tabStrip)
    stripDiv:SetHeight(1)
    stripDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.7)

    -- Right-pinned action buttons
    local newChanBtn = S:Button(tabStrip, "+ New Channel", 112, 26)
    newChanBtn:SetPoint("RIGHT", tabStrip, "RIGHT", -8, 0)
    newChanBtn:SetScript("OnClick", function()
        UI:ShowGroupNameDialog(nil, function(name)
            local id = GH.Chat:CreateChannel(name, { GH:GetPlayerName() })
            activeChatId = id
            UI:RefreshChatChannelList()
            UI:SelectChatChannel(id)
        end)
    end)

    local deleteBtn = S:DangerButton(tabStrip, "Delete", 70, 26)
    deleteBtn:SetPoint("RIGHT", newChanBtn, "LEFT", -6, 0)
    deleteBtn:SetScript("OnClick", function()
        if not activeChatId or IsBuiltin(activeChatId) then return end
        GH.Chat:DeleteChannel(activeChatId)
        activeChatId = GuildId()
        UI:RefreshChatChannelList()
        UI:SelectChatChannel(GuildId())
    end)

    local manageBtn = S:Button(tabStrip, "Members", 78, 26)
    manageBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -4, 0)
    manageBtn:SetScript("OnClick", function()
        if activeChatId and not IsBuiltin(activeChatId) then
            UI:ShowChatMembersDialog(activeChatId)
        end
    end)

    frame.manageBtn = manageBtn
    frame.deleteBtn = deleteBtn

    -- Tab container: fills left portion of strip, clips overflow
    local tabArea = CreateFrame("Frame", nil, tabStrip)
    tabArea:SetPoint("TOPLEFT",    tabStrip,  "TOPLEFT",    2, 0)
    tabArea:SetPoint("BOTTOMLEFT", tabStrip,  "BOTTOMLEFT", 2, 0)
    tabArea:SetPoint("RIGHT",      manageBtn, "LEFT", -8, 0)
    tabArea:SetClipsChildren(true)
    frame.tabArea = tabArea

    -- ── Message area ──────────────────────────────────────────────────────
    local msgPanel = CreateFrame("Frame", nil, frame)
    msgPanel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, -(TAB_H + 1))
    msgPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, INP_H)
    S:Bg(msgPanel, 0, 0, 0, 0.08)
    frame.msgPanel = msgPanel

    local msgSf = CreateFrame("ScrollFrame", nil, msgPanel, "UIPanelScrollFrameTemplate")
    msgSf:SetPoint("TOPLEFT",     msgPanel, "TOPLEFT",     4, -4)
    msgSf:SetPoint("BOTTOMRIGHT", msgPanel, "BOTTOMRIGHT", -20, 4)

    -- The template scrollbar is anchored to the right of msgSf and can extend
    -- past the window border in 12.x. Pin it explicitly inside msgPanel.
    local sb = msgSf.ScrollBar
    if sb then
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT",    msgPanel, "TOPRIGHT",    -2, -4)
        sb:SetPoint("BOTTOMRIGHT", msgPanel, "BOTTOMRIGHT", -2,  4)
    end

    local msgContent = CreateFrame("Frame", nil, msgSf)
    msgContent:SetSize(w - 26, 10)
    msgSf:SetScrollChild(msgContent)
    frame.msgScrollFrame   = msgSf
    frame.msgScrollContent = msgContent

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

    local inputBox = S:EditBox(inputBar, 0, 28, 255)
    inputBox:SetPoint("LEFT",  inputBar, "LEFT",  10, 0)
    inputBox:SetPoint("RIGHT", inputBar, "RIGHT", -94, 0)
    frame.inputBox = inputBox

    local sendBtn = S:Button(inputBar, "Send", 82, 30)
    sendBtn:SetPoint("RIGHT", inputBar, "RIGHT", -8, 0)

    local function DoSend()
        if not activeChatId then return end
        local text = inputBox:GetText():match("^%s*(.-)%s*$")
        if text == "" then return end
        GH.Chat:SendMessage(activeChatId, text)
        inputBox:SetText("")
        inputBox:ClearFocus()
        if not IsBuiltin(activeChatId) then
            lastRefreshTs = 0
            UI:RefreshChatMessages(activeChatId)
        end
        C_Timer.After(0.05, function()
            if frame.msgScrollFrame then
                frame.msgScrollFrame:SetVerticalScroll(
                    frame.msgScrollFrame:GetVerticalScrollRange())
            end
        end)
    end

    sendBtn:SetScript("OnClick", DoSend)
    inputBox:SetScript("OnEnterPressed", function(eb)
        DoSend()
        eb:ClearFocus()
    end)

    local placeholder = msgPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetPoint("CENTER", msgPanel, "CENTER")
    placeholder:SetText("Select a channel")
    placeholder:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame.chatPlaceholder = placeholder

    frame:SetScript("OnShow", function()
        if not activeChatId then activeChatId = GuildId() end
        UI:RefreshChatChannelList()
        UI:SelectChatChannel(activeChatId)
    end)

    UI:RefreshChatChannelList()
end

-- ── Channel tab strip ─────────────────────────────────────────────────────

function UI:RefreshChatChannelList()
    local frame = UI.ChatTab
    if not frame then return end

    local tabArea = frame.tabArea
    for i = tabArea:GetNumChildren(), 1, -1 do
        select(i, tabArea:GetChildren()):Hide()
    end

    local channels = GH.Chat:GetChannels()
    local xOff = 0

    for idx, ch in ipairs(channels) do
        local isActive  = (ch.id == activeChatId)
        local isBuiltin = IsBuiltin(ch.id)
        local unread    = GH.Chat:GetUnreadCount(ch.id)

        -- Separator between built-in and first custom channel
        if idx > 1 and not isBuiltin and IsBuiltin(channels[idx - 1].id) then
            local sep = CreateFrame("Frame", nil, tabArea)
            sep:SetPoint("TOPLEFT",    tabArea, "TOPLEFT",    xOff, -6)
            sep:SetPoint("BOTTOMLEFT", tabArea, "BOTTOMLEFT", xOff,  6)
            sep:SetWidth(1)
            sep:Show()
            local sepTex = sep:CreateTexture(nil, "ARTWORK")
            sepTex:SetAllPoints()
            sepTex:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.45)
            xOff = xOff + 9
        end

        local tabW
        if     ch.isGuild   then tabW = 128
        elseif ch.isOfficer then tabW = 110
        else                     tabW = math.max(80, math.min(160, #ch.name * 7 + 48))
        end

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

        -- Active bottom accent line
        if isActive then
            local accentF = CreateFrame("Frame", nil, tab)
            accentF:SetPoint("BOTTOMLEFT",  tab, "BOTTOMLEFT",  2, 0)
            accentF:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 0)
            accentF:SetHeight(2)
            accentF:Show()
            local accentT = accentF:CreateTexture(nil, "ARTWORK")
            accentT:SetAllPoints()
            if ch.isGuild then
                accentT:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 1)
            elseif ch.isOfficer then
                accentT:SetColorTexture(0.68, 0.28, 0.92, 1)
            else
                accentT:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 1)
            end
        end

        tab:SetScript("OnEnter", function()
            if not isActive then bg:SetColorTexture(1, 1, 1, 0.04) end
        end)
        tab:SetScript("OnLeave", function()
            if not isActive then bg:SetColorTexture(0, 0, 0, 0) end
        end)

        -- Icon (child frame so it hides with the tab)
        local iconF = CreateFrame("Frame", nil, tab)
        iconF:SetSize(14, 14)
        iconF:SetPoint("LEFT", tab, "LEFT", 8, 1)
        iconF:Show()
        local iconT = iconF:CreateTexture(nil, "OVERLAY")
        iconT:SetAllPoints()
        local alpha = isActive and 1 or 0.5
        if ch.isGuild then
            local bgTex     = iconF:CreateTexture(nil, "BACKGROUND")
            bgTex:SetAllPoints()
            local borderTex = iconF:CreateTexture(nil, "BORDER")
            borderTex:SetAllPoints()
            local logoTex   = iconF:CreateTexture(nil, "OVERLAY")
            logoTex:SetAllPoints()
            local ok = SetGuildTabardTextures and pcall(SetGuildTabardTextures, "player", logoTex, bgTex, borderTex)
            if ok then
                iconT:Hide()
                bgTex:SetAlpha(alpha)
                borderTex:SetAlpha(alpha)
                logoTex:SetAlpha(alpha)
            else
                bgTex:Hide(); borderTex:Hide(); logoTex:Hide()
                iconT:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")
                iconT:SetVertexColor(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], alpha)
            end
        elseif ch.isOfficer then
            iconT:SetTexture("Interface\\Icons\\Ability_Warrior_OffensiveStance")
            iconT:SetVertexColor(0.70, 0.30, 0.90, alpha)
        else
            iconT:SetTexture("Interface\\Icons\\INV_Letter_06")
            iconT:SetVertexColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], alpha)
        end

        -- Name label
        local nameFs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFs:SetPoint("LEFT",  tab, "LEFT",  26, 0)
        nameFs:SetPoint("RIGHT", tab, "RIGHT", unread > 0 and -34 or -6, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        nameFs:SetText(
            ch.isGuild   and "Guild Chat" or
            ch.isOfficer and "Officer"    or
            ch.name)
        if isActive then
            if ch.isGuild then
                nameFs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
            elseif ch.isOfficer then
                nameFs:SetTextColor(0.85, 0.55, 1.0)
            else
                nameFs:SetTextColor(1, 1, 1)
            end
        else
            nameFs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end

        -- Unread badge
        if unread > 0 then
            local badgeF = CreateFrame("Frame", nil, tab)
            badgeF:SetSize(28, 14)
            badgeF:SetPoint("RIGHT", tab, "RIGHT", -4, 0)
            badgeF:Show()
            local badgeBg = badgeF:CreateTexture(nil, "BACKGROUND")
            badgeBg:SetAllPoints()
            badgeBg:SetColorTexture(0.85, 0.15, 0.15, 0.90)
            local badgeFs = badgeF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            badgeFs:SetAllPoints()
            badgeFs:SetJustifyH("CENTER")
            badgeFs:SetText(unread > 99 and "99+" or tostring(unread))
            badgeFs:SetTextColor(1, 1, 1)
        end

        local capturedId = ch.id
        tab:SetScript("OnClick", function()
            activeChatId = capturedId
            GH.Chat:MarkRead(capturedId)
            UI:RefreshChatChannelList()
            UI:SelectChatChannel(capturedId)
        end)

        xOff = xOff + tabW
    end
end

-- ── Channel selection ─────────────────────────────────────────────────────

function UI:SelectChatChannel(channelId)
    GH:Debug("UI", "SelectChatChannel: channelId=%s guildClubId=%s guildMsgs=%d",
        tostring(channelId), tostring(GH.Chat.guildClubId), #GH.Chat.guildMsgs)
    local frame = UI.ChatTab
    if not frame then return end

    local isBuiltin  = IsBuiltin(channelId)
    local isTeamChan = not isBuiltin and IsTeamChannel(channelId)
    frame.chatPlaceholder:Hide()
    -- Team channels are managed exclusively via the Teams tab; hide both buttons for everyone.
    -- Non-team custom channels: any member can manage members or delete.
    -- Officers can delete team channels if needed.
    frame.manageBtn:SetShown(not isBuiltin and not isTeamChan)
    frame.deleteBtn:SetShown(not isBuiltin and (not isTeamChan or GH:CanManageTeams()))

    if channelId == GuildId() then
        GH.Chat:LoadGuildHistory()
    elseif channelId == OfficerId() then
        GH.Chat:LoadOfficerHistory()
    end

    GH.Chat:MarkRead(channelId)
    lastRefreshTs = 0
    UI:RefreshChatMessages(channelId)
end

-- ── Message display ───────────────────────────────────────────────────────

function UI:RefreshChatMessages(channelId)
    if channelId ~= activeChatId then return end
    local frame = UI.ChatTab
    if not frame or not frame:IsShown() then return end

    local now = GetTime()
    if channelId == lastRefreshId and now - lastRefreshTs < 0.08 then return end
    lastRefreshId = channelId
    lastRefreshTs = now
    GH.Chat:MarkRead(channelId)

    local content = frame.msgScrollContent
    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    local messages  = GH.Chat:GetMessages(channelId)
    GH:Debug("UI", "RefreshChatMessages: channelId=%s messages=%d guildClubId=%s",
        tostring(channelId), #messages, tostring(GH.Chat.guildClubId))
    local myName    = GH:GetPlayerName()
    local isOfficer = (channelId == OfficerId())
    local isGuild   = (channelId == GuildId())
    local GAP_THRESHOLD = 3600
    local yOff      = 4
    local prevTs    = nil

    for idx, msg in ipairs(messages) do
        if isGuild and prevTs and msg.ts - prevTs > GAP_THRESHOLD then
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

            local gapText = gapRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            gapText:SetPoint("CENTER", gapRow, "CENTER", 0, 0)
            gapText:SetText("History gap — some messages may be missing while you were offline")
            gapText:SetTextColor(0.7, 0.7, 0.8, 1)

            yOff = yOff + 26
        end

        local shortSender = msg.sender:match("^([^%-]+)") or msg.sender
        local isSelf      = (shortSender == myName)

        local nr, ng, nb
        local memberInfo = GH.GuildData:FindMember(msg.sender)
        if memberInfo then
            nr, ng, nb = GH.GuildData:GetClassColor(memberInfo.classFileName)
        elseif isOfficer then
            nr, ng, nb = 0.85, 0.40, 1.00
        elseif isGuild then
            if isSelf then nr,ng,nb = 0.45,0.70,1.00
            else            nr,ng,nb = 0.95,0.75,0.20 end
        else
            if isSelf then nr,ng,nb = S.COLOR.ACCENT[1],S.COLOR.ACCENT[2],S.COLOR.ACCENT[3]
            else            nr,ng,nb = S.COLOR.TEXT_GOLD[1],S.COLOR.TEXT_GOLD[2],S.COLOR.TEXT_GOLD[3] end
        end

        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  4, -yOff)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -yOff)
        row:Show()
        row:EnableMouse(true)
        row:SetHyperlinksEnabled(true)

        if idx % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            stripe:SetColorTexture(1, 1, 1, 0.025)
        end

        local timeFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeFs:SetPoint("LEFT", row, "LEFT", 0, 0)
        timeFs:SetText("|cff555566[" .. GH:FormatTime(msg.ts) .. "]|r ")
        timeFs:SetTextColor(1, 1, 1)
        local timeW = timeFs:GetStringWidth() + 2

        local senderBtn = CreateFrame("Button", nil, row)
        senderBtn:SetPoint("LEFT", row, "LEFT", timeW, 0)
        senderBtn:SetHeight(14)

        local senderFs = senderBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
                    gt:SetText("Whisper " .. capturedSender, 1, 1, 1)
                    gt:Show()
                end
            end)
            senderBtn:SetScript("OnLeave", function()
                local gt = rawget(_G, "GameTooltip")
                if gt then gt:Hide() end
            end)
        end

        local bodyIndent = timeW + senderW + 4
        local bodyW = math.max(1, content:GetWidth() - bodyIndent - 12)

        local bodyFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bodyFs:SetPoint("LEFT", row, "LEFT", bodyIndent, 0)
        bodyFs:SetWidth(bodyW)
        bodyFs:SetJustifyH("LEFT")
        bodyFs:SetJustifyV("TOP")
        bodyFs:SetText(" " .. (msg.text or ""))
        bodyFs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        bodyFs:SetWordWrap(true)
        bodyFs:SetNonSpaceWrap(false)

        local bodyH = bodyFs:GetStringHeight()
        local rowH  = math.max(bodyH, 14) + 8
        row:SetHeight(rowH)

        local capturedText = msg.text or ""
        local gt = rawget(_G, "GameTooltip")

        row:SetScript("OnHyperlinkEnter", function(self, link)
            if gt and link then
                gt:SetOwner(self, "ANCHOR_CURSOR")
                pcall(gt.SetHyperlink, gt, link)
                gt:Show()
            end
        end)
        row:SetScript("OnHyperlinkLeave", function()
            if gt then gt:Hide() end
        end)
        row:SetScript("OnHyperlinkClick", function(self, link, _, button)
            if button == "RightButton" then
                UI:ShowCopyDialog(capturedText)
            elseif link and gt then
                gt:SetOwner(self, "ANCHOR_CURSOR")
                pcall(gt.SetHyperlink, gt, link)
                gt:Show()
            end
        end)
        row:SetScript("OnMouseUp", function(_, btn)
            if btn == "RightButton" then UI:ShowCopyDialog(capturedText) end
        end)

        prevTs = msg.ts
        yOff = yOff + rowH + 3
    end

    content:SetHeight(math.max(yOff + 4, 10))

    C_Timer.After(0.05, function()
        if frame.msgScrollFrame then
            frame.msgScrollFrame:SetVerticalScroll(
                frame.msgScrollFrame:GetVerticalScrollRange())
        end
    end)
end

-- ── Copy dialog ───────────────────────────────────────────────────────────

function UI:ShowCopyDialog(text)
    local dlg = _G.GuildHubCopyDialog
    if not dlg then
        dlg = CreateFrame("Frame", "GuildHubCopyDialog", UIParent)
        dlg:SetSize(440, 140)
        dlg:SetPoint("CENTER")
        dlg:SetFrameStrata("DIALOG")
        dlg:SetClampedToScreen(true)
        dlg:EnableMouse(true)
        dlg:SetToplevel(true)
        S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.98)
        S:Border(dlg)

        local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", dlg, "TOP", 0, -14)
        title:SetText("Copy Message")
        title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

        local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -6, -6)
        closeBtn:SetScript("OnClick", function() dlg:Hide() end)

        local eb = S:EditBox(dlg, 400, 28, 500)
        eb:SetPoint("TOP", title, "BOTTOM", 0, -20)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function(self)
            dlg:Hide()
        end)
        dlg.editBox = eb
    end
    dlg.editBox:SetText(text or "")
    dlg.editBox:HighlightText()
    dlg:Show()
end

-- ── Real-time callbacks ───────────────────────────────────────────────────

function UI:OnChatMessage(channelId)
    UI:UpdateChatBadge()
    if UI.ChatTab and UI.ChatTab:IsShown() then
        UI:RefreshChatMessages(channelId)
    end
end

function UI:OnChannelListChanged()
    if UI.ChatTab and UI.ChatTab:IsShown() then
        UI:RefreshChatChannelList()
    end
end

-- ── Chat members dialog (custom channels only) ────────────────────────────

function UI:ShowChatMembersDialog(channelId)
    local ch = GH.Chat:GetChannel(channelId)
    if not ch then return end

    local dlg = CreateFrame("Frame", "GuildHubChatMembersDialog", UIParent)
    dlg:SetSize(300, 340)
    dlg:SetPoint("CENTER")
    dlg:SetFrameStrata("DIALOG")
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText("Members of #" .. ch.name)
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",  dlg, "TOPLEFT",  10,  -34)
    sf:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -24, -34)
    sf:SetHeight(220)
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(256, 10)
    sf:SetScrollChild(sc)

    local function PopulateMembers()
        for i = sc:GetNumChildren(), 1, -1 do select(i, sc:GetChildren()):Hide() end
        local chan = GH.Chat:GetChannel(channelId)
        if not chan then return end
        for i, memberName in ipairs(chan.members or {}) do
            local row = CreateFrame("Frame", nil, sc)
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(i-1)*28)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(i-1)*28)
            row:SetHeight(26)
            row:Show()
            local nm = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nm:SetPoint("LEFT", row, "LEFT", 6, 0)
            nm:SetText(memberName)
            nm:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
            local removeBtn = S:DangerButton(row, "x", 22, 20)
            removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            local capturedName = memberName
            removeBtn:SetScript("OnClick", function()
                GH.Chat:RemoveMember(channelId, capturedName)
                PopulateMembers()
            end)
        end
        sc:SetHeight(math.max(#(chan.members or {})*28, 10))
    end
    PopulateMembers()

    local addBox = S:EditBox(dlg, 180, 24, 60)
    addBox:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 10, 40)

    local addBtn = S:Button(dlg, "Add", 60, 24)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 4, 0)

    local suggestionFrame = CreateFrame("Frame", nil, dlg)
    suggestionFrame:SetPoint("BOTTOMLEFT", addBox, "TOPLEFT", 0, 6)
    suggestionFrame:SetPoint("TOPRIGHT", addBtn, "TOPRIGHT", 0, 90)
    S:Bg(suggestionFrame, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.9)
    suggestionFrame:Hide()

    local suggestionScroll = CreateFrame("ScrollFrame", nil, suggestionFrame, "UIPanelScrollFrameTemplate")
    suggestionScroll:SetAllPoints()
    local suggestionContent = CreateFrame("Frame", nil, suggestionScroll)
    suggestionContent:SetPoint("TOPLEFT",  suggestionScroll, "TOPLEFT",  0, 0)
    suggestionContent:SetPoint("TOPRIGHT", suggestionScroll, "TOPRIGHT", -18, 0)
    suggestionContent:SetHeight(10)
    suggestionScroll:SetScrollChild(suggestionContent)

    local suggestionRows = {}

    local function IsMemberAlreadyAdded(name)
        for _, memberName in ipairs(ch.members or {}) do
            if memberName == name then return true end
        end
        return false
    end

    local function UpdateSuggestions()
        local filter = addBox:GetText():match("^%s*(.-)%s*$") or ""
        local matches = filter == "" and {} or GH.GuildData:GetMembers(filter)
        local shown = 0

        local numChildren = select("#", suggestionContent:GetChildren())
        for i = 1, numChildren do
            select(i, suggestionContent:GetChildren()):Hide()
        end

        for _, member in ipairs(matches) do
            if shown >= 6 then break end
            if not IsMemberAlreadyAdded(member.name) then
                shown = shown + 1
                local row = suggestionRows[shown]
                if not row then
                    row = CreateFrame("Button", nil, suggestionContent)
                    row:SetHeight(24)
                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.text:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.bg:SetColorTexture(0, 0, 0, 0)
                    row:RegisterForClicks("LeftButtonUp")
                    row:SetScript("OnEnter", function(self)
                        self.bg:SetColorTexture(0.4, 0.4, 0.5, 0.25)
                    end)
                    row:SetScript("OnLeave", function(self)
                        self.bg:SetColorTexture(0, 0, 0, 0)
                    end)
                    row:SetScript("OnClick", function(self)
                        addBox:SetText(self.memberName)
                        suggestionFrame:Hide()
                        addBox:SetFocus()
                    end)
                    suggestionRows[shown] = row
                end
                row.memberName = member.name
                row.text:SetText(member.name)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  suggestionContent, "TOPLEFT",  0, -(shown - 1) * 26)
                row:SetPoint("TOPRIGHT", suggestionContent, "TOPRIGHT", 0, -(shown - 1) * 26)
                row:Show()
            end
        end

        if shown == 0 then
            suggestionFrame:Hide()
            return
        end

        suggestionContent:SetHeight(shown * 26)
        suggestionFrame:Show()
    end

    addBox:SetScript("OnTextChanged", function() UpdateSuggestions() end)

    addBtn:SetScript("OnClick", function()
        local name = addBox:GetText():match("^%s*(.-)%s*$")
        if name ~= "" then
            GH.Chat:AddMember(channelId, name)
            addBox:SetText("")
            suggestionFrame:Hide()
            PopulateMembers()
        end
    end)

    local closeBtn = S:Button(dlg, "Close", 80, 26)
    closeBtn:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 8)
    closeBtn:SetScript("OnClick", function() dlg:Hide() end)
end
