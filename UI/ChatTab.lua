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

    local configureBtn = S:Button(tabStrip, "Configure", 90, 26)
    configureBtn:SetPoint("RIGHT", tabStrip, "RIGHT", -8, 0)
    configureBtn:SetScript("OnClick", function() UI:ShowCommunityLinksDialog() end)
    configureBtn:Hide()

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

    frame.newChanBtn  = newChanBtn
    frame.configureBtn = configureBtn
    frame.manageBtn   = manageBtn
    frame.deleteBtn   = deleteBtn

    -- Tab container: fills left portion of strip, clips overflow
    local tabArea = CreateFrame("Frame", nil, tabStrip)
    tabArea:SetPoint("TOPLEFT",    tabStrip,  "TOPLEFT",    2, 0)
    tabArea:SetPoint("BOTTOMLEFT", tabStrip,  "BOTTOMLEFT", 2, 0)
    tabArea:SetPoint("RIGHT",      manageBtn, "LEFT", -8, 0)
    tabArea:SetClipsChildren(true)
    frame.tabArea = tabArea

    -- ── Notice panel (XGuild join/invite banners) ─────────────────────────
    -- Sits between the tab strip and the message area. Height collapses to 0
    -- when there are no notices, so msgPanel is unaffected.
    local noticePanel = CreateFrame("Frame", nil, frame)
    noticePanel:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -(TAB_H + 1))
    noticePanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(TAB_H + 1))
    noticePanel:SetHeight(0)
    S:Bg(noticePanel, 0.07, 0.05, 0.03, 0.97)
    frame.noticePanel = noticePanel

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
    -- Arrow buttons extend outside the scrollbar frame, so hide them to prevent
    -- overlap with the notice panel (Request Access) and input bar (Send).
    local sb = msgSf.ScrollBar
    if sb then
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT",    msgPanel, "TOPRIGHT",    -2, -4)
        sb:SetPoint("BOTTOMRIGHT", msgPanel, "BOTTOMRIGHT", -2,  4)
        if sb.ScrollUpButton   then sb.ScrollUpButton:Hide()   end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
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
        elseif ch.isGuild  then tabW = math.max(130, math.min(200, #ch.name * 7 + 48))
        else                     tabW = math.max(80,  math.min(160, #ch.name * 7 + 48))
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
            elseif ch.isGuild then
                accentT:SetColorTexture(0.20, 0.80, 0.75, 1)
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
        elseif ch.isGuild then
            iconT:SetTexture("Interface\\Icons\\Achievement_GuildPerk_WorkingAsATeam")
            iconT:SetVertexColor(0.20, 0.85, 0.80, alpha)
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
            elseif ch.isGuild then
                nameFs:SetTextColor(0.30, 0.95, 0.90)
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
    local isGuildTab = (channelId == GuildId())
    local isTeamChan = not isBuiltin and IsTeamChannel(channelId)
    frame.chatPlaceholder:Hide()

    -- Configure button lives on the Guild Chat tab for officers.
    local showConfigure = isGuildTab and GH:IsOfficer()
    if showConfigure then
        local nReqs = 0
        for _ in pairs(GH.DB:GetJoinRequests()) do nReqs = nReqs + 1 end
        frame.configureBtn:SetText(nReqs > 0 and ("Configure (" .. nReqs .. ")") or "Configure")
    end
    frame.configureBtn:SetShown(showConfigure)
    frame.newChanBtn:SetShown(not isGuildTab or not showConfigure)

    -- Team channels are managed exclusively via the Teams tab; hide both buttons for everyone.
    -- Non-team custom channels: any member can manage members or delete.
    -- Officers can delete team channels if needed.
    frame.manageBtn:SetShown(not isBuiltin and not isTeamChan)
    frame.deleteBtn:SetShown(not isBuiltin and (not isTeamChan or GH:CanManageTeams()))

    if channelId == GuildId() then
        GH.Chat:LoadGuildHistory()
        GH.Chat:LoadOfficerHistory()
    elseif channelId == OfficerId() then
        GH.Chat:LoadOfficerHistory()
    end

    GH.Chat:MarkRead(channelId)
    lastRefreshTs = 0
    UI:UpdateXGuildNotice()
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

    -- Build a clubId → current label map for community source tags in guild chat.
    local communityLabels = {}
    if isGuild then
        for _, link in pairs(GH.DB:GetCommunityLinks()) do
            communityLabels[tostring(link.clubId)] = link.label or "Community"
        end
    end

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
        local isCommunity = msg.communityId ~= nil

        local nr, ng, nb
        local memberInfo = GH.GuildData:FindMember(msg.sender)
        if memberInfo then
            nr, ng, nb = GH.GuildData:GetClassColor(memberInfo.classFileName)
        elseif isOfficer or (isGuild and msg.isOfficer) then
            nr, ng, nb = 0.85, 0.40, 1.00
        elseif isGuild and isCommunity then
            if isSelf then nr,ng,nb = 0.45,0.85,0.80
            else            nr,ng,nb = 0.30, 0.75, 0.70 end
        elseif isGuild or isGuild then
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

        -- Source tag: shown for officer and community messages in the guild chat view.
        local sourceW = 0
        if isGuild and msg.isOfficer then
            local tagFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tagFs:SetPoint("LEFT", row, "LEFT", timeW, 0)
            tagFs:SetText("[Officer] ")
            tagFs:SetTextColor(0.70, 0.30, 0.90)
            sourceW = tagFs:GetStringWidth() + 2
        elseif isGuild and isCommunity then
            local tagLabel = communityLabels[msg.communityId] or msg.sourceLabel or "Community"
            local tagFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tagFs:SetPoint("LEFT", row, "LEFT", timeW, 0)
            tagFs:SetText("[" .. tagLabel .. "] ")
            tagFs:SetTextColor(0.20, 0.75, 0.70)
            sourceW = tagFs:GetStringWidth() + 2
        end

        local senderBtn = CreateFrame("Button", nil, row)
        senderBtn:SetPoint("LEFT", row, "LEFT", timeW + sourceW, 0)
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

        local bodyIndent = timeW + sourceW + senderW + 4
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

-- ── XGuild notice panel ───────────────────────────────────────────────────

function UI:UpdateXGuildNotice()
    local frame = UI.ChatTab
    if not (frame and frame.noticePanel) then return end
    local panel = frame.noticePanel

    -- Clear existing rows.
    for i = panel:GetNumChildren(), 1, -1 do
        select(i, panel:GetChildren()):Hide()
    end

    -- Only show banners when Guild Chat is active.
    if activeChatId ~= GuildId() then
        panel:SetHeight(0)
        return
    end

    local links = GH.DB:GetCommunityLinks()
    local NOTICE_H = 36
    local rows = {}

    -- If the player is already in any configured community, suppress all notices.
    local anySubscribed = false
    for _, link in pairs(links) do
        if link.enabled ~= false and GH.Chat:IsSubscribedToCommunity(link.clubId) then
            anySubscribed = true
            break
        end
    end

    if not anySubscribed then
        local seenClubs = {}
        for _, link in pairs(links) do
            if link.enabled ~= false then
                local cid = tostring(link.clubId)
                if not seenClubs[cid] then
                    seenClubs[cid] = true
                    local pending = GH.Chat:GetPendingInviteForClub(link.clubId)
                    rows[#rows + 1] = {
                        kind    = pending and "invite" or "request",
                        clubId  = link.clubId,
                        label   = link.label or "Community",
                        pending = pending,
                    }
                end
            end
        end
    end

    local msgPanel = frame.msgPanel
    if #rows == 0 then
        panel:SetHeight(0)
        if msgPanel then
            msgPanel:ClearAllPoints()
            msgPanel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, -(TAB_H + 1))
            msgPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, INP_H)
        end
        return
    end

    panel:SetHeight(#rows * NOTICE_H)
    if msgPanel then
        msgPanel:ClearAllPoints()
        msgPanel:SetPoint("TOPLEFT",     panel, "BOTTOMLEFT",  0, 0)
        msgPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, INP_H)
    end

    for i, row in ipairs(rows) do
        local yOff = (i - 1) * NOTICE_H
        local rowF = CreateFrame("Frame", nil, panel)
        rowF:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -yOff)
        rowF:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -yOff)
        rowF:SetHeight(NOTICE_H)
        rowF:Show()

        -- Colour-coded left accent bar.
        local accent = rowF:CreateTexture(nil, "ARTWORK")
        accent:SetPoint("TOPLEFT",    rowF, "TOPLEFT",    0, 0)
        accent:SetPoint("BOTTOMLEFT", rowF, "BOTTOMLEFT", 0, 0)
        accent:SetWidth(3)
        if row.kind == "invite" then
            accent:SetColorTexture(0.20, 0.80, 0.95, 1)
        else
            accent:SetColorTexture(0.90, 0.65, 0.10, 1)
        end

        -- Divider between rows.
        if i > 1 then
            local div = rowF:CreateTexture(nil, "BACKGROUND")
            div:SetPoint("TOPLEFT",  rowF, "TOPLEFT")
            div:SetPoint("TOPRIGHT", rowF, "TOPRIGHT")
            div:SetHeight(1)
            div:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.4)
        end

        local capturedClubId = row.clubId
        local capturedLabel  = row.label

        if row.kind == "invite" then
            -- Pending invite: Accept / Decline buttons.
            local acceptBtn = S:Button(rowF, "Accept", 72, 22)
            acceptBtn:SetPoint("RIGHT", rowF, "RIGHT", -8, 0)
            acceptBtn:SetScript("OnClick", function()
                GH.Chat:AcceptCommunityInvite(capturedClubId)
            end)

            local declineBtn = S:DangerButton(rowF, "Decline", 64, 22)
            declineBtn:SetPoint("RIGHT", acceptBtn, "LEFT", -4, 0)
            declineBtn:SetScript("OnClick", function()
                GH.Chat:DeclineCommunityInvite(capturedClubId)
            end)

            local lbl = rowF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT",  rowF,       "LEFT",  10, 0)
            lbl:SetPoint("RIGHT", declineBtn, "LEFT",  -8, 0)
            lbl:SetText("|cff33c8f0Invite pending for [" .. capturedLabel .. "]|r — accept to join and view messages")
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
        else
            -- Not subscribed: Request Access button.
            local reqBtn = S:Button(rowF, "Request Access", 114, 22)
            reqBtn:SetPoint("RIGHT", rowF, "RIGHT", -8, 0)
            reqBtn:SetScript("OnClick", function()
                GH.Chat:RequestCommunityAccess(capturedClubId, capturedLabel)
                reqBtn:SetText("Requested!")
                reqBtn:SetEnabled(false)
            end)

            local lbl = rowF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT",  rowF,   "LEFT",  10, 0)
            lbl:SetPoint("RIGHT", reqBtn, "LEFT",  -8, 0)
            lbl:SetText("|cffffb700Not in [" .. capturedLabel .. "]|r — join this community to send and receive its messages")
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
        end
    end
end

-- ── Community links dialog ────────────────────────────────────────────────

function UI:ShowCommunityLinksDialog()
    local dlg = _G.GuildHubCommunityLinksDialog
    if dlg then dlg:Show(); UI:_RefreshCommunityLinksDialog(); return end

    dlg = CreateFrame("Frame", "GuildHubCommunityLinksDialog", UIParent)
    dlg:SetSize(380, 420)
    dlg:SetPoint("CENTER")
    dlg:SetFrameStrata("DIALOG")
    dlg:SetClampedToScreen(true)
    dlg:EnableMouse(true)
    dlg:SetToplevel(true)
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.98)
    S:Border(dlg)
    dlg:SetMovable(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", dlg.StartMoving)
    dlg:SetScript("OnDragStop",  dlg.StopMovingOrSizing)

    local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", dlg, "TOP", 0, -14)
    title:SetText("Cross-Guild Chat Settings")
    title:SetTextColor(0.30, 0.95, 0.90)

    local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() dlg:Hide() end)

    -- ── Label rename (guild leader / officer) ─────────────────────────────
    local labelHeader = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelHeader:SetPoint("TOPLEFT", dlg, "TOPLEFT", 14, -44)
    labelHeader:SetText("Tab Label")
    labelHeader:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local labelBox = S:EditBox(dlg, 240, 24, 60)
    labelBox:SetPoint("TOPLEFT", labelHeader, "BOTTOMLEFT", 0, -4)
    dlg.labelBox = labelBox

    local saveLabelBtn = S:Button(dlg, "Save", 60, 24)
    saveLabelBtn:SetPoint("LEFT", labelBox, "RIGHT", 6, 0)
    saveLabelBtn:SetScript("OnClick", function()
        local txt = labelBox:GetText():match("^%s*(.-)%s*$")
        if txt ~= "" then
            GH.Chat:SetCrossGuildLabel(txt)
        end
    end)

    if not GH:IsOfficer() then
        labelBox:SetEnabled(false)
        saveLabelBtn:SetEnabled(false)
    end

    -- ── Linked communities list ───────────────────────────────────────────
    local linksHeader = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    linksHeader:SetPoint("TOPLEFT", labelBox, "BOTTOMLEFT", 0, -14)
    linksHeader:SetText("Linked Communities")
    linksHeader:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local linksSf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    linksSf:SetPoint("TOPLEFT",  linksHeader, "BOTTOMLEFT",  0,  -4)
    linksSf:SetPoint("TOPRIGHT", dlg,         "TOPRIGHT",   -26, -96)
    linksSf:SetHeight(110)
    local linksSc = CreateFrame("Frame", nil, linksSf)
    linksSc:SetSize(320, 10)
    linksSf:SetScrollChild(linksSc)
    dlg.linksSc = linksSc
    dlg.linksSf = linksSf

    -- ── Join requests (officers only) ─────────────────────────────────────
    local reqHeader = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reqHeader:SetPoint("TOPLEFT", linksSf, "BOTTOMLEFT", 0, -14)
    reqHeader:SetText("Join Requests")
    reqHeader:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    reqHeader:SetShown(GH:IsOfficer())

    local reqSf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    reqSf:SetPoint("TOPLEFT",  reqHeader, "BOTTOMLEFT",  0,  -4)
    reqSf:SetPoint("TOPRIGHT", dlg,       "TOPRIGHT",   -26, -210)
    reqSf:SetHeight(80)
    local reqSc = CreateFrame("Frame", nil, reqSf)
    reqSc:SetSize(320, 10)
    reqSf:SetScrollChild(reqSc)
    reqSf:SetShown(GH:IsOfficer())
    dlg.reqSc = reqSc

    -- ── Send-to target ────────────────────────────────────────────────────
    local sendHeader = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sendHeader:SetPoint("TOPLEFT", GH:IsOfficer() and reqSf or linksSf, "BOTTOMLEFT", 0, -14)
    sendHeader:SetText("Send Messages To")
    sendHeader:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local sendSf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sendSf:SetPoint("TOPLEFT",  sendHeader, "BOTTOMLEFT",  0,  -4)
    sendSf:SetPoint("TOPRIGHT", dlg,        "TOPRIGHT",   -26, -225)
    sendSf:SetHeight(80)
    local sendSc = CreateFrame("Frame", nil, sendSf)
    sendSc:SetSize(320, 10)
    sendSf:SetScrollChild(sendSc)
    dlg.sendSc = sendSc

    -- ── Add community ─────────────────────────────────────────────────────
    local addHeader = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addHeader:SetPoint("TOPLEFT", sendSf, "BOTTOMLEFT", 0, -14)
    addHeader:SetText("Add Community")
    addHeader:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    -- Dropdown-style picker: a button that shows a popup list
    local pickerBtn = S:Button(dlg, "Select community...", 240, 24)
    pickerBtn:SetPoint("TOPLEFT", addHeader, "BOTTOMLEFT", 0, -4)
    dlg.pickerBtn    = pickerBtn
    dlg.pickerChoice = nil  -- {clubId, streamId, name}

    local addBtn = S:Button(dlg, "Add", 60, 24)
    addBtn:SetPoint("LEFT", pickerBtn, "RIGHT", 6, 0)
    addBtn:SetScript("OnClick", function()
        if not dlg.pickerChoice then return end
        local c = dlg.pickerChoice
        GH.Chat:AddCommunityLink(c.clubId, c.streamId, c.name)
        dlg.pickerChoice = nil
        pickerBtn:SetText("Select community...")
        UI:_RefreshCommunityLinksDialog()
    end)

    if not GH:IsOfficer() then
        pickerBtn:SetEnabled(false)
        addBtn:SetEnabled(false)
    end

    -- Dropdown popup
    local popup = CreateFrame("Frame", nil, dlg)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetWidth(240)
    S:Bg(popup, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.97)
    S:Border(popup)
    popup:Hide()
    dlg.communityPopup = popup

    pickerBtn:SetScript("OnClick", function()
        if popup:IsShown() then popup:Hide(); return end
        local avail = GH.Chat:GetAvailableCommunities()
        -- Clear old rows
        for i = popup:GetNumChildren(), 1, -1 do
            select(i, popup:GetChildren()):Hide()
        end
        if #avail == 0 then
            local noRow = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noRow:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -8)
            noRow:SetText("No communities available")
            noRow:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
            popup:SetHeight(30)
        else
            local pH = 4
            for _, opt in ipairs(avail) do
                local row = CreateFrame("Button", nil, popup)
                row:SetHeight(24)
                row:SetPoint("TOPLEFT",  popup, "TOPLEFT",  2, -(pH))
                row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, -(pH))
                row:Show()
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0, 0, 0)
                local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                lbl:SetPoint("LEFT", row, "LEFT", 6, 0)
                lbl:SetText(opt.name)
                lbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
                local capturedOpt = opt
                row:SetScript("OnEnter", function() bg:SetColorTexture(0.3, 0.3, 0.4, 0.3) end)
                row:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
                row:SetScript("OnClick", function()
                    dlg.pickerChoice = capturedOpt
                    pickerBtn:SetText(capturedOpt.name)
                    popup:Hide()
                end)
                pH = pH + 26
            end
            popup:SetHeight(pH + 4)
        end
        popup:SetPoint("BOTTOMLEFT", pickerBtn, "TOPLEFT", 0, 2)
        popup:Show()
    end)

    local closeBtn2 = S:Button(dlg, "Close", 80, 26)
    closeBtn2:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 10)
    closeBtn2:SetScript("OnClick", function() dlg:Hide() end)

    dlg:Show()
    UI:_RefreshCommunityLinksDialog()
end

function UI:_RefreshCommunityLinksDialog()
    -- Keep the configure button badge in sync regardless of whether the dialog is open.
    if UI.ChatTab and GH:IsOfficer() then
        local nReqs = 0
        for _ in pairs(GH.DB:GetJoinRequests()) do nReqs = nReqs + 1 end
        UI.ChatTab.configureBtn:SetText(
            nReqs > 0 and ("Configure (" .. nReqs .. ")") or "Configure")
    end

    local dlg = _G.GuildHubCommunityLinksDialog
    if not dlg then return end

    -- Update label field
    if dlg.labelBox then dlg.labelBox:SetText(GH.DB:GetCrossGuildLabel()) end

    -- Rebuild linked communities list
    local sc = dlg.linksSc
    for j = sc:GetNumChildren(), 1, -1 do select(j, sc:GetChildren()):Hide() end
    local links  = GH.DB:GetCommunityLinks()
    local yOff   = 0
    local hasAny = false
    for id, link in pairs(links) do
        if link.enabled ~= false then
            hasAny = true
            local row = CreateFrame("Frame", nil, sc)
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -yOff)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -yOff)
            row:SetHeight(26)
            row:Show()
            local dot = row:CreateTexture(nil, "ARTWORK")
            dot:SetSize(8, 8)
            dot:SetPoint("LEFT", row, "LEFT", 4, 0)
            dot:SetColorTexture(0.20, 0.85, 0.80, 1)
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT",  row, "LEFT",  18, 0)
            lbl:SetPoint("RIGHT", row, "RIGHT", -70, 0)
            lbl:SetText(link.label or "Community")
            lbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
            if GH:IsOfficer() then
                local removeBtn = S:DangerButton(row, "Remove", 62, 20)
                removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                local capturedId = id
                removeBtn:SetScript("OnClick", function()
                    GH.Chat:RemoveCommunityLink(capturedId)
                    UI:_RefreshCommunityLinksDialog()
                end)
            end
            yOff = yOff + 28
        end
    end
    if not hasAny then
        local none = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        none:SetPoint("TOPLEFT", sc, "TOPLEFT", 6, 0)
        none:SetText("No communities linked yet")
        none:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        yOff = 20
    end
    sc:SetHeight(math.max(yOff, 10))

    -- Relay warning: shown when 2+ communities are linked.
    if not dlg.relayWarning then
        local w = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        w:SetPoint("TOPLEFT",  dlg.linksSf, "BOTTOMLEFT",  0, -4)
        w:SetPoint("TOPRIGHT", dlg,     "TOPRIGHT",   -14, -4)
        w:SetJustifyH("LEFT")
        w:SetWordWrap(true)
        dlg.relayWarning = w
    end
    local linkedCount = 0
    for _, link in pairs(links) do
        if link.enabled ~= false then linkedCount = linkedCount + 1 end
    end
    if linkedCount >= 2 then
        dlg.relayWarning:SetText(
            "|cffffb700All officers should join every linked community.|r " ..
            "GuildHub relays messages between communities — the more officers " ..
            "are in all of them, the more reliably everyone sees everything.")
        dlg.relayWarning:Show()
    else
        dlg.relayWarning:SetText("")
        dlg.relayWarning:Hide()
    end

    -- Rebuild send-target radio list
    local ssc = dlg.sendSc
    for k = ssc:GetNumChildren(), 1, -1 do select(k, ssc:GetChildren()):Hide() end
    local currentTarget = GH.DB:GetCrossGuildSendTarget()
    local targets = { { id = nil, label = "Guild Chat (default)" } }
    for _, link in pairs(links) do
        if link.enabled ~= false then
            targets[#targets + 1] = { id = tostring(link.clubId), label = link.label or "Community" }
        end
    end
    local sOff = 0
    for _, opt in ipairs(targets) do
        local row = CreateFrame("Frame", nil, ssc)
        row:SetPoint("TOPLEFT",  ssc, "TOPLEFT",  0, -sOff)
        row:SetPoint("TOPRIGHT", ssc, "TOPRIGHT", 0, -sOff)
        row:SetHeight(22)
        row:Show()
        local isSelected = (opt.id == currentTarget) or (opt.id == nil and currentTarget == nil)
        local radio = row:CreateTexture(nil, "ARTWORK")
        radio:SetSize(10, 10)
        radio:SetPoint("LEFT", row, "LEFT", 4, 0)
        if isSelected then
            radio:SetColorTexture(0.20, 0.85, 0.80, 1)
        else
            radio:SetColorTexture(0.35, 0.35, 0.40, 1)
        end
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
        lbl:SetText(opt.label)
        lbl:SetTextColor(isSelected and 1 or S.COLOR.TEXT_DIM[1],
                         isSelected and 1 or S.COLOR.TEXT_DIM[2],
                         isSelected and 1 or S.COLOR.TEXT_DIM[3])
        if GH:IsOfficer() then
            local capturedId = opt.id
            local clickArea = CreateFrame("Button", nil, row)
            clickArea:SetAllPoints(row)
            clickArea:SetScript("OnClick", function()
                GH.Chat:SetCrossGuildSendTarget(capturedId)
                UI:_RefreshCommunityLinksDialog()
            end)
        end
        sOff = sOff + 24
    end
    ssc:SetHeight(math.max(sOff, 10))

    -- Rebuild join requests list (officers only).
    if not dlg.reqSc then return end
    local rsc = dlg.reqSc
    for j = rsc:GetNumChildren(), 1, -1 do select(j, rsc:GetChildren()):Hide() end
    local requests = GH.DB:GetJoinRequests()
    local rOff = 0
    local hasReqs = false
    local EXPIRY = 86400  -- ignore requests older than 24 h
    local now = GH:GetTimestamp()
    for playerName, req in pairs(requests) do
        if now - (req.ts or 0) <= EXPIRY then
            hasReqs = true
            local row = CreateFrame("Frame", nil, rsc)
            row:SetPoint("TOPLEFT",  rsc, "TOPLEFT",  0, -rOff)
            row:SetPoint("TOPRIGHT", rsc, "TOPRIGHT", 0, -rOff)
            row:SetHeight(26)
            row:Show()

            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT",  row, "LEFT",  4, 0)
            lbl:SetPoint("RIGHT", row, "RIGHT", -74, 0)
            lbl:SetText(playerName .. " → [" .. (req.communityLabel or "?") .. "]")
            lbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

            local inviteBtn = S:Button(row, "Send Invite", 66, 20)
            inviteBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            local capturedName   = playerName
            local capturedClubId = req.clubId
            inviteBtn:SetScript("OnClick", function()
                local ok = GH.Chat:SendCommunityInvite(capturedClubId, capturedName)
                if ok then
                    inviteBtn:SetText("Sent!")
                    inviteBtn:SetEnabled(false)
                else
                    inviteBtn:SetText("Failed")
                    inviteBtn:SetEnabled(false)
                end
                -- Refresh the configure button badge.
                if UI.ChatTab then
                    local nReqs = 0
                    for _ in pairs(GH.DB:GetJoinRequests()) do nReqs = nReqs + 1 end
                    UI.ChatTab.configureBtn:SetText(
                        nReqs > 0 and ("Configure (" .. nReqs .. ")") or "Configure")
                end
            end)

            rOff = rOff + 28
        end
    end
    if not hasReqs then
        local none = rsc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        none:SetPoint("TOPLEFT", rsc, "TOPLEFT", 6, 0)
        none:SetText("No pending requests")
        none:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        rOff = 20
    end
    rsc:SetHeight(math.max(rOff, 10))
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
-- UI:OnChatMessage and UI:OnChannelListChanged are defined in TeamsTab.lua,
-- which is loaded after this file and handles both the Chat and Teams tabs.

-- ── Chat members dialog (custom channels only) ────────────────────────────

function UI:ShowChatMembersDialog(channelId)
    local ch = GH.Chat:GetChannel(channelId)
    if not ch then return end

    if UI._chatMembersDlg then UI._chatMembersDlg:Hide() end

    local dlg = CreateFrame("Frame", nil, UIParent)
    UI._chatMembersDlg = dlg
    dlg:SetSize(300, 340)
    dlg:SetPoint("CENTER")
    dlg:SetFrameStrata("DIALOG")
    dlg:SetClampedToScreen(true)
    dlg:EnableMouse(true)
    dlg:SetToplevel(true)
    dlg:SetMovable(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", dlg.StartMoving)
    dlg:SetScript("OnDragStop",  dlg.StopMovingOrSizing)
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
    S:Border(dlg)

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

    -- Suggestion dropdown: plain frame (no scroll template) sized dynamically.
    local suggestionFrame = CreateFrame("Frame", nil, dlg)
    suggestionFrame:SetFrameStrata("TOOLTIP")
    suggestionFrame:SetPoint("BOTTOMLEFT", addBox, "TOPLEFT", 0, 2)
    suggestionFrame:SetWidth(244)
    suggestionFrame:SetHeight(10)
    S:Bg(suggestionFrame, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.97)
    S:Border(suggestionFrame)
    suggestionFrame:Hide()

    local suggestionRows = {}

    local function IsMemberAlreadyAdded(name)
        local chan = GH.Chat:GetChannel(channelId)
        for _, memberName in ipairs(chan and chan.members or {}) do
            if memberName == name then return true end
        end
        return false
    end

    local function UpdateSuggestions()
        local filter = addBox:GetText():match("^%s*(.-)%s*$") or ""
        if filter == "" then
            suggestionFrame:Hide()
            return
        end
        local lf = filter:lower()
        local shown = 0

        for i = 1, #suggestionRows do suggestionRows[i]:Hide() end

        for _, m in ipairs(GH.GuildData.members) do
            if shown >= 6 then break end
            if m.name:lower():find(lf, 1, true) and not IsMemberAlreadyAdded(m.name) then
                shown = shown + 1
                local row = suggestionRows[shown]
                if not row then
                    row = CreateFrame("Button", nil, suggestionFrame)
                    row:SetHeight(26)
                    local rowBg = row:CreateTexture(nil, "BACKGROUND")
                    rowBg:SetAllPoints()
                    rowBg:SetColorTexture(0, 0, 0, 0)
                    row.bg = rowBg
                    local rowText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    rowText:SetPoint("LEFT",  row, "LEFT",  8, 0)
                    rowText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                    rowText:SetJustifyH("LEFT")
                    rowText:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
                    row.text = rowText
                    row:RegisterForClicks("LeftButtonUp")
                    row:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.4, 0.4, 0.6, 0.3) end)
                    row:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0, 0, 0, 0) end)
                    row:SetScript("OnClick", function(self)
                        addBox:SetText(self.memberName)
                        suggestionFrame:Hide()
                        addBox:SetFocus()
                    end)
                    suggestionRows[shown] = row
                end
                row.memberName = m.name
                row.text:SetText(m.name)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  suggestionFrame, "TOPLEFT",  0, -(shown - 1) * 26)
                row:SetPoint("TOPRIGHT", suggestionFrame, "TOPRIGHT", 0, -(shown - 1) * 26)
                row:Show()
            end
        end

        if shown == 0 then
            suggestionFrame:Hide()
            return
        end
        suggestionFrame:SetHeight(shown * 26)
        suggestionFrame:Show()
    end

    addBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput then UpdateSuggestions() end
    end)

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
