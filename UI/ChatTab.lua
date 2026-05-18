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
local tabScrollX    = 0  -- horizontal pixel offset into the tab strip

local TAB_H   = 38
local INP_H   = 46
local PANEL_W = 190

local function GuildId()     return GH.Chat.GUILD_ID   end
local function OfficerId()   return GH.Chat.OFFICER_ID  end
local function IsBuiltin(id) return id == GuildId() or id == OfficerId() end

-- Returns true if this channel is owned by a team (managed via the Teams tab).
local function IsTeamChannel(channelId)
    for _, g in ipairs(GH.Groups:GetAll()) do
        if g.channelId == channelId then return true end
    end
    return false
end

-- ── Construction ──────────────────────────────────────────────────────────

function UI:CreateChatTab(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.ChatTab = frame

    -- ── Channel tab strip ─────────────────────────────────────────────────
    local tabStrip = CreateFrame("Frame", nil, frame)
    tabStrip:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    tabStrip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tabStrip:SetHeight(TAB_H)
    S:GradientBg(tabStrip, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL_HDR_B[1], S.COLOR.PANEL_HDR_B[2], S.COLOR.PANEL_HDR_B[3], 1)

    local stripDiv = tabStrip:CreateTexture(nil, "ARTWORK")
    stripDiv:SetPoint("BOTTOMLEFT",  tabStrip)
    stripDiv:SetPoint("BOTTOMRIGHT", tabStrip)
    stripDiv:SetHeight(1)
    stripDiv:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.15)

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

    -- Tab-strip scroll arrows (shown when tabs overflow the available width)
    local scrollRBtn = S:Button(tabStrip, ">", 22, 26)
    scrollRBtn:SetPoint("RIGHT", manageBtn, "LEFT", -8, 0)
    scrollRBtn:SetScript("OnClick", function()
        tabScrollX = tabScrollX + 120
        UI:RefreshChatChannelList()
    end)

    local scrollLBtn = S:Button(tabStrip, "<", 22, 26)
    scrollLBtn:SetPoint("RIGHT", scrollRBtn, "LEFT", -2, 0)
    scrollLBtn:SetScript("OnClick", function()
        tabScrollX = math.max(0, tabScrollX - 120)
        UI:RefreshChatChannelList()
    end)

    frame.scrollLBtn = scrollLBtn
    frame.scrollRBtn = scrollRBtn

    -- Tab container: fills left portion of strip, clips overflow
    local tabArea = CreateFrame("Frame", nil, tabStrip)
    tabArea:SetPoint("TOPLEFT",    tabStrip,  "TOPLEFT",    2, 0)
    tabArea:SetPoint("BOTTOMLEFT", tabStrip,  "BOTTOMLEFT", 2, 0)
    tabArea:SetPoint("RIGHT",      scrollLBtn, "LEFT", -4, 0)
    tabArea:SetClipsChildren(true)
    frame.tabArea = tabArea

    -- ── Chat members panel (right sidebar) ───────────────────────────────
    local chatMembersPanel = CreateFrame("Frame", nil, frame)
    chatMembersPanel:SetWidth(PANEL_W)
    chatMembersPanel:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0, -(TAB_H + 1))
    chatMembersPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, INP_H)
    S:GradientBg(chatMembersPanel, "VERTICAL",
        S.COLOR.SIDEBAR[1] + 0.005, S.COLOR.SIDEBAR[2] + 0.004, S.COLOR.SIDEBAR[3] + 0.010, 1,
        S.COLOR.SIDEBAR[1],         S.COLOR.SIDEBAR[2],         S.COLOR.SIDEBAR[3],          1)

    local panelDiv = chatMembersPanel:CreateTexture(nil, "BORDER")
    panelDiv:SetWidth(1)
    panelDiv:SetPoint("TOPLEFT",    chatMembersPanel, "TOPLEFT",    0, 0)
    panelDiv:SetPoint("BOTTOMLEFT", chatMembersPanel, "BOTTOMLEFT", 0, 0)
    panelDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.6)

    local panelHdr = CreateFrame("Frame", nil, chatMembersPanel)
    panelHdr:SetPoint("TOPLEFT",  chatMembersPanel, "TOPLEFT",  0, 0)
    panelHdr:SetPoint("TOPRIGHT", chatMembersPanel, "TOPRIGHT", 0, 0)
    panelHdr:SetHeight(34)
    S:GradientBg(panelHdr, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL_HDR_B[1], S.COLOR.PANEL_HDR_B[2], S.COLOR.PANEL_HDR_B[3], 1)
    local panelHdrSep = panelHdr:CreateTexture(nil, "ARTWORK")
    panelHdrSep:SetPoint("BOTTOMLEFT",  panelHdr, "BOTTOMLEFT")
    panelHdrSep:SetPoint("BOTTOMRIGHT", panelHdr, "BOTTOMRIGHT")
    panelHdrSep:SetHeight(1)
    panelHdrSep:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

    local panelCountFS = S:FS(panelHdr, "OVERLAY")
    panelCountFS:SetPoint("LEFT",  panelHdr, "LEFT",  10, 0)
    panelCountFS:SetPoint("RIGHT", panelHdr, "RIGHT", -6, 0)
    panelCountFS:SetJustifyH("LEFT")
    panelCountFS:SetText("Members")
    panelCountFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local panelSf = CreateFrame("ScrollFrame", nil, chatMembersPanel)
    panelSf:SetPoint("TOPLEFT",     chatMembersPanel, "TOPLEFT",     1, -36)
    panelSf:SetPoint("BOTTOMRIGHT", chatMembersPanel, "BOTTOMRIGHT", -4, 4)
    panelSf:EnableMouseWheel(true)
    panelSf:SetScript("OnMouseWheel", function(sf, delta)
        local max = sf:GetVerticalScrollRange()
        sf:SetVerticalScroll(math.max(0, math.min(max, sf:GetVerticalScroll() - delta * 30)))
    end)
    local panelContent = CreateFrame("Frame", nil, panelSf)
    panelSf:SetScrollChild(panelContent)
    local function SyncPanelWidth()
        local w = panelSf:GetWidth()
        if w > 0 then panelContent:SetWidth(w) end
    end
    panelSf:SetScript("OnSizeChanged", SyncPanelWidth)
    C_Timer.After(0, SyncPanelWidth)

    frame.chatMembersPanel   = chatMembersPanel
    frame.chatMembersContent = panelContent
    frame.chatMembersCountFS = panelCountFS
    frame.chatMemberRows     = {}

    -- ── Message area ──────────────────────────────────────────────────────
    local msgPanel = CreateFrame("Frame", nil, frame)
    msgPanel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, -(TAB_H + 1))
    msgPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PANEL_W, INP_H)
    S:Bg(msgPanel, 0, 0, 0, 0.08)
    frame.msgPanel = msgPanel

    -- Plain scroll frame — no template scrollbar widget to escape the window edge.
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

    local function SyncChatMsgWidth()
        local sfW = msgSf:GetWidth()
        if sfW > 0 then msgContent:SetWidth(sfW) end
    end
    msgSf:SetScript("OnSizeChanged", SyncChatMsgWidth)
    C_Timer.After(0, SyncChatMsgWidth)

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
        frame._scrolledUp = false
        if frame.scrollToBottomBtn then frame.scrollToBottomBtn:Hide() end
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

    local placeholder = S:FS(msgPanel, "OVERLAY", "normal")
    placeholder:SetPoint("CENTER", msgPanel, "CENTER")
    placeholder:SetText("Select a channel")
    placeholder:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame.chatPlaceholder = placeholder

    local _onShowBusy = false
    frame:SetScript("OnShow", function()
        if _onShowBusy then return end
        _onShowBusy = true
        if not activeChatId then activeChatId = GuildId() end
        UI:RefreshChatChannelList()
        UI:SelectChatChannel(activeChatId)
        _onShowBusy = false
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
    local xOff = -tabScrollX

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
        local nameFs = S:FS(tab, "OVERLAY")
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
            local badgeFs = S:FS(badgeF, "OVERLAY")
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

    -- Show/enable scroll arrows based on overflow state.
    -- xOff here = totalTabWidth - tabScrollX, so totalTabWidth = xOff + tabScrollX.
    local areaW = tabArea:GetWidth()
    local totalTabW = xOff + tabScrollX
    local canLeft  = tabScrollX > 0
    local canRight = areaW > 0 and totalTabW > tabScrollX + areaW

    -- Clamp scroll so we never over-scroll past the end.
    if areaW > 0 and tabScrollX > 0 and not canRight then
        local maxScroll = math.max(0, totalTabW - areaW)
        if tabScrollX > maxScroll then
            tabScrollX = maxScroll
        end
    end

    frame.scrollLBtn:SetShown(canLeft or canRight)
    frame.scrollRBtn:SetShown(canLeft or canRight)
    frame.scrollLBtn:SetEnabled(canLeft)
    frame.scrollRBtn:SetEnabled(canRight)
    frame.scrollLBtn:SetAlpha(canLeft  and 1 or 0.35)
    frame.scrollRBtn:SetAlpha(canRight and 1 or 0.35)
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
    if frame then
        frame._scrolledUp = false
        if frame.scrollToBottomBtn then frame.scrollToBottomBtn:Hide() end
    end
    UI:RefreshChatMessages(channelId)
    UI:RefreshChatMembersPanel(channelId)
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

            local gapText = S:FS(gapRow, "OVERLAY")
            gapText:SetPoint("CENTER", gapRow, "CENTER", 0, 0)
            gapText:SetText("History gap — some messages may be missing while you were offline")
            gapText:SetTextColor(0.7, 0.7, 0.8, 1)

            yOff = yOff + 26
        end

        local shortSender  = msg.sender:match("^([^%-]+)") or msg.sender
        local isSelf       = (shortSender == myName)
        local isCrossGuild = (msg.sourceLabel ~= nil)

        local nr, ng, nb
        local memberInfo = GH.GuildData:FindMember(msg.sender)
        if memberInfo then
            nr, ng, nb = GH.GuildData:GetClassColor(memberInfo.classFileName)
        elseif isCrossGuild then
            -- Distinct teal for confederation members from other guilds.
            nr, ng, nb = 0.35, 0.85, 0.75
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

        local timeFs = S:FS(row, "OVERLAY")
        timeFs:SetPoint("LEFT", row, "LEFT", 0, 0)
        timeFs:SetText("|cff555566[" .. GH:FormatTime(msg.ts) .. "]|r ")
        timeFs:SetTextColor(1, 1, 1)
        local timeW = timeFs:GetStringWidth() + 2

        local senderBtn = CreateFrame("Button", nil, row)
        senderBtn:SetPoint("LEFT", row, "LEFT", timeW, 0)
        senderBtn:SetHeight(14)

        local senderFs = S:FS(senderBtn, "OVERLAY")
        senderFs:SetAllPoints()
        senderFs:SetJustifyH("LEFT")
        local senderLabel = shortSender
        if isCrossGuild then
            senderLabel = "|cff338866[" .. msg.sourceLabel .. "]|r " .. shortSender
        end
        senderFs:SetText(senderLabel .. ":")
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

        local bodyFs = S:FS(row, "OVERLAY")
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
        if frame.msgScrollFrame and not frame._scrolledUp then
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

        local title = S:FS(dlg, "OVERLAY", "large")
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

-- ── Chat members panel ────────────────────────────────────────────────────

function UI:RefreshChatMembersPanel(channelId)
    local frame = UI.ChatTab
    if not frame or not frame.chatMembersPanel then return end

    local sc       = frame.chatMembersContent
    local rows     = frame.chatMemberRows
    local countFS  = frame.chatMembersCountFS

    local members = {}
    local title   = "Members"

    if channelId == GuildId() then
        title = "Online"
        for _, m in ipairs(GH.GuildData:GetMembers("")) do
            if m.online then
                members[#members + 1] = { name = m.name, info = m, online = true }
            end
        end
        table.sort(members, function(a, b)
            local as, bs = a.info.status or 0, b.info.status or 0
            if as ~= bs then return as < bs end
            return a.name < b.name
        end)
        countFS:SetText("Online — |cff22cc44" .. #members .. "|r")

    elseif channelId == OfficerId() then
        title = "Officers"
        local threshold = GH.DB:GetSetting("officerRankThreshold") or 1
        for _, m in ipairs(GH.GuildData:GetMembers("")) do
            if (m.rankIndex or 999) <= threshold then
                members[#members + 1] = { name = m.name, info = m, online = m.online }
            end
        end
        table.sort(members, function(a, b)
            if a.online ~= b.online then return (a.online and 1 or 0) > (b.online and 1 or 0) end
            return a.name < b.name
        end)
        local on = 0
        for _, m in ipairs(members) do if m.online then on = on + 1 end end
        countFS:SetText(title .. " — |cff22cc44" .. on .. "|r/" .. #members)

    else
        -- Team channel or custom channel
        local teamGroup
        for _, g in ipairs(GH.Groups:GetAll()) do
            if g.channelId == channelId then teamGroup = g; break end
        end

        if teamGroup then
            title = teamGroup.name
            for _, name in ipairs(teamGroup.members or {}) do
                local info = GH.GuildData:FindMember(name)
                members[#members + 1] = { name = name, info = info, online = info and info.online }
            end
        else
            local ch = GH.Chat:GetChannel(channelId)
            if ch then
                title = ch.name
                for _, name in ipairs(ch.members or {}) do
                    local info = GH.GuildData:FindMember(name)
                    members[#members + 1] = { name = name, info = info, online = info and info.online }
                end
            end
        end

        table.sort(members, function(a, b)
            if a.online ~= b.online then return (a.online and 1 or 0) > (b.online and 1 or 0) end
            return a.name < b.name
        end)
        local on = 0
        for _, m in ipairs(members) do if m.online then on = on + 1 end end
        countFS:SetText(title .. " — |cff22cc44" .. on .. "|r/" .. #members)
    end

    local ROW_H = 28
    for _, row in ipairs(rows) do row:Hide() end

    for i, m in ipairs(members) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, sc)
            row:SetHeight(ROW_H)

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
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(i - 1) * ROW_H)

        local cr, cg, cb = 0.7, 0.7, 0.7
        if m.info then cr, cg, cb = GH.GuildData:GetClassColor(m.info.classFileName) end

        if m.online then
            local status = m.info and (m.info.status or 0) or 0
            if     status == 1 then row.dot:SetColorTexture(S.COLOR.AFK[1],    S.COLOR.AFK[2],    S.COLOR.AFK[3],    1)
            elseif status == 2 then row.dot:SetColorTexture(S.COLOR.DND[1],    S.COLOR.DND[2],    S.COLOR.DND[3],    1)
            else                    row.dot:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 1)
            end
        else
            cr, cg, cb = cr * 0.55, cg * 0.55, cb * 0.55
            row.dot:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.5)
        end

        row.nameFS:SetText(m.name)
        row.nameFS:SetTextColor(cr, cg, cb)
        row:Show()
    end

    sc:SetHeight(math.max(#members * ROW_H, 10))
end

function UI:RefreshCurrentChatMembersPanel()
    if activeChatId then
        UI:RefreshChatMembersPanel(activeChatId)
    end
end

-- ── Real-time callbacks ───────────────────────────────────────────────────

function UI:OnChatMessage(channelId)
    UI:UpdateChatBadge()
    if UI.ChatTab and UI.ChatTab:IsShown() then
        UI:RefreshChatMessages(channelId)
    end
end

function UI:OnChannelListChanged()
    tabScrollX = 0
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

    local title = S:FS(dlg, "OVERLAY", "normal")
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
            local nm = S:FS(row, "OVERLAY")
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
                    row.text = S:FS(row, "OVERLAY")
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
