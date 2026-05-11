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

local TAB_H = 38
local MBR_H = 42
local INP_H = 46

-- ── Helpers ───────────────────────────────────────────────────────────────

local function EnsureTeamChannel(groupId)
    local g = GH.Groups:Get(groupId)
    if not g then return nil end
    if g.channelId then
        -- If the DB returned the group, _activeGuild is set and GetChat is authoritative.
        -- If it returns nil here the record is genuinely missing, so fall through to create.
        if GH.DB:GetChat(g.channelId) then return g.channelId end
    end
    -- Only create a new channel when the DB is confirmed active (Groups:Get succeeded,
    -- so _GuildData is non-nil).  If channelId was already set but the chat record is
    -- gone, we create a fresh one; otherwise this is the first-time setup path.
    local myName     = GH:GetPlayerName()
    local chanMembers = {}
    local hasMe      = false
    for _, n in ipairs(g.members or {}) do
        chanMembers[#chanMembers + 1] = n
        if n == myName then hasMe = true end
    end
    if not hasMe then chanMembers[#chanMembers + 1] = myName end
    local channelId = GH.Chat:CreateChannel(g.name, chanMembers)
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

function UI:CreateTeamsTab(parent, w, _)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.TeamsTab = frame

    -- ── Team tab strip ─────────────────────────────────────────────────────
    local tabStrip = CreateFrame("Frame", nil, frame)
    tabStrip:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    tabStrip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tabStrip:SetHeight(TAB_H)
    S:Bg(tabStrip, S.COLOR.SIDEBAR[1], S.COLOR.SIDEBAR[2], S.COLOR.SIDEBAR[3], 1)
    frame.tabStrip = tabStrip

    local stripDiv = tabStrip:CreateTexture(nil, "ARTWORK")
    stripDiv:SetPoint("BOTTOMLEFT",  tabStrip)
    stripDiv:SetPoint("BOTTOMRIGHT", tabStrip)
    stripDiv:SetHeight(1)
    stripDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.7)

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
        frame.memberStrip:Hide()
        frame.placeholder:Show()
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

    -- Tab container (fills left portion of strip, clips overflow)
    local tabArea = CreateFrame("Frame", nil, tabStrip)
    tabArea:SetPoint("TOPLEFT",    tabStrip,  "TOPLEFT",    2, 0)
    tabArea:SetPoint("BOTTOMLEFT", tabStrip,  "BOTTOMLEFT", 2, 0)
    tabArea:SetPoint("RIGHT",      inviteBtn, "LEFT", -8, 0)
    tabArea:SetClipsChildren(true)
    frame.tabArea = tabArea

    -- ── Member presence strip ──────────────────────────────────────────────
    local memberStrip = CreateFrame("Frame", nil, frame)
    memberStrip:SetPoint("TOPLEFT",  tabStrip, "BOTTOMLEFT",  0, -1)
    memberStrip:SetPoint("TOPRIGHT", tabStrip, "BOTTOMRIGHT", 0, -1)
    memberStrip:SetHeight(MBR_H)
    S:Bg(memberStrip,
        S.COLOR.PANEL[1] * 0.85, S.COLOR.PANEL[2] * 0.85, S.COLOR.PANEL[3] * 0.85, 1)
    memberStrip:Hide()
    frame.memberStrip = memberStrip

    local mbrDiv = memberStrip:CreateTexture(nil, "ARTWORK")
    mbrDiv:SetPoint("BOTTOMLEFT",  memberStrip)
    mbrDiv:SetPoint("BOTTOMRIGHT", memberStrip)
    mbrDiv:SetHeight(1)
    mbrDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

    -- ── Message area ──────────────────────────────────────────────────────
    local msgPanel = CreateFrame("Frame", nil, frame)
    msgPanel:SetPoint("TOPLEFT",     tabStrip, "BOTTOMLEFT",  0, -1)
    msgPanel:SetPoint("BOTTOMRIGHT", frame,    "BOTTOMRIGHT", 0, INP_H)
    S:Bg(msgPanel, 0, 0, 0, 0.08)
    frame.msgPanel = msgPanel

    -- Re-anchor msgPanel whenever member strip is toggled
    function frame:UpdateLayout(memberStripShown)
        msgPanel:ClearAllPoints()
        if memberStripShown then
            msgPanel:SetPoint("TOPLEFT",     memberStrip, "BOTTOMLEFT",  0, -1)
            msgPanel:SetPoint("BOTTOMRIGHT", frame,       "BOTTOMRIGHT", 0, INP_H)
        else
            msgPanel:SetPoint("TOPLEFT",     tabStrip, "BOTTOMLEFT",  0, -1)
            msgPanel:SetPoint("BOTTOMRIGHT", frame,    "BOTTOMRIGHT", 0, INP_H)
        end
    end

    local msgSf = CreateFrame("ScrollFrame", nil, msgPanel, "UIPanelScrollFrameTemplate")
    msgSf:SetPoint("TOPLEFT",     msgPanel, "TOPLEFT",     4, -4)
    msgSf:SetPoint("BOTTOMRIGHT", msgPanel, "BOTTOMRIGHT", -20, 4)

    local msgContent = CreateFrame("Frame", nil, msgSf)
    msgContent:SetSize(w - 26, 10)
    msgSf:SetScrollChild(msgContent)

    frame.msgScrollFrame   = msgSf
    frame.msgScrollContent = msgContent

    local ph = msgPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        UI:RefreshTeamsGroupList()
        if selected then UI:ShowTeamView(selected) end
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
        frame.memberStrip:Hide()
        frame.placeholder:Show()
        frame:UpdateLayout(false)
        frame.deleteBtn:SetAlpha(0.35)
        frame.membersBtn:SetAlpha(0.35)
        frame.inviteBtn:SetAlpha(0.35)
    end

    local groups = GH.Groups:GetAll()
    local xOff   = 0

    for _, g in ipairs(groups) do
        local isActive = (selected == g.id)
        local tr, tg, tb = HexToRGB(g.color)

        -- Count online members
        local total, online = #(g.members or {}), 0
        for _, name in ipairs(g.members or {}) do
            local info = GH.GuildData.byName[name]
            if info and info.online then online = online + 1 end
        end

        local tabW = math.max(100, math.min(200, #g.name * 7 + 70))

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
        local nameFs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFs:SetPoint("LEFT",  tab, "LEFT",  22, 0)
        nameFs:SetPoint("RIGHT", tab, "RIGHT", -36, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        nameFs:SetText(g.name)
        if isActive then
            nameFs:SetTextColor(1, 1, 1)
        else
            nameFs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end

        -- Member count badge (online / total)
        local badgeF = CreateFrame("Frame", nil, tab)
        badgeF:SetSize(32, 14)
        badgeF:SetPoint("RIGHT", tab, "RIGHT", -4, 0)
        badgeF:Show()
        local badgeBg = badgeF:CreateTexture(nil, "BACKGROUND")
        badgeBg:SetAllPoints()
        badgeBg:SetColorTexture(0, 0, 0, isActive and 0.4 or 0.25)
        local badgeFs = badgeF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badgeFs:SetAllPoints()
        badgeFs:SetJustifyH("CENTER")
        if online > 0 then
            badgeFs:SetText("|cff22cc44" .. online .. "|r/" .. total)
        else
            badgeFs:SetText("|cff888899" .. total .. "|r")
        end

        local capturedId = g.id
        tab:SetScript("OnClick", function()
            selected = capturedId
            UI:RefreshTeamsGroupList()
            UI:ShowTeamView(capturedId)
        end)

        xOff = xOff + tabW
    end
end

-- ── Member presence strip ─────────────────────────────────────────────────

function UI:RefreshMemberStrip(groupId)
    local frame = UI.TeamsTab
    if not frame then return end
    local strip = frame.memberStrip

    for i = strip:GetNumChildren(), 1, -1 do
        select(i, strip:GetChildren()):Hide()
    end

    local g = GH.Groups:Get(groupId)
    if not g or #(g.members or {}) == 0 then
        strip:Hide()
        frame:UpdateLayout(false)
        return
    end

    -- Sort: online first, then alphabetical
    local sorted = {}
    for _, name in ipairs(g.members) do
        local info   = GH.GuildData.byName[name]
        local online = info and info.online
        sorted[#sorted + 1] = { name = name, info = info, online = online }
    end
    table.sort(sorted, function(a, b)
        if a.online ~= b.online then return (a.online and 1 or 0) > (b.online and 1 or 0) end
        return a.name < b.name
    end)

    strip:Show()
    frame:UpdateLayout(true)

    local xOff    = 10
    local maxX    = (strip:GetWidth() > 0 and strip:GetWidth() or 800) - 64  -- reserve for "+N more"
    local skipped = 0

    for idx, m in ipairs(sorted) do
        local pillW = math.max(64, #m.name * 7 + 30)

        if xOff + pillW > maxX then
            skipped = #sorted - idx + 1
            break
        end

        local online = m.online
        local info   = m.info
        local cr, cg, cb = 0.75, 0.75, 0.75
        if info then cr, cg, cb = GH.GuildData:GetClassColor(info.classFileName) end
        if not online then cr, cg, cb = cr * 0.55, cg * 0.55, cb * 0.55 end

        local pill = CreateFrame("Button", nil, strip)
        pill:SetPoint("LEFT", strip, "LEFT", xOff, 0)
        pill:SetWidth(pillW)
        pill:SetHeight(MBR_H - 14)
        pill:Show()

        local pillBg = pill:CreateTexture(nil, "BACKGROUND")
        pillBg:SetAllPoints()
        pillBg:SetColorTexture(1, 1, 1, online and 0.04 or 0)

        pill:SetScript("OnEnter", function()
            pillBg:SetColorTexture(1, 1, 1, 0.08)
            local gt = rawget(_G, "GameTooltip")
            if gt then
                gt:SetOwner(pill, "ANCHOR_TOP")
                local statusLine = online and "|cff22cc44Online|r" or "|cff888899Offline|r"
                if info and info.rank then
                    statusLine = statusLine .. " — " .. info.rank
                end
                gt:SetText(m.name, cr, cg, cb)
                gt:AddLine(statusLine, 1, 1, 1)
                gt:Show()
            end
        end)
        pill:SetScript("OnLeave", function()
            pillBg:SetColorTexture(1, 1, 1, online and 0.04 or 0)
            local gt = rawget(_G, "GameTooltip")
            if gt then gt:Hide() end
        end)

        -- Whisper on click if online
        if online then
            local capturedName = m.name
            pill:SetScript("OnClick", function()
                local fn = rawget(_G, "ChatFrame_OpenChat")
                if fn then fn("/w " .. capturedName .. " ") end
            end)
        end

        -- Online indicator dot
        local dotF = CreateFrame("Frame", nil, pill)
        dotF:SetSize(7, 7)
        dotF:SetPoint("LEFT", pill, "LEFT", 4, 0)
        dotF:Show()
        local dotT = dotF:CreateTexture(nil, "OVERLAY")
        dotT:SetAllPoints()
        if online then
            dotT:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 1)
        else
            dotT:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.6)
        end

        -- Name label
        local nameFs = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFs:SetPoint("LEFT",  pill, "LEFT",  14, 0)
        nameFs:SetPoint("RIGHT", pill, "RIGHT", -4, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        nameFs:SetText(m.name)
        nameFs:SetTextColor(cr, cg, cb)

        xOff = xOff + pillW + 4
    end

    -- "+N more" overflow indicator
    if skipped > 0 then
        local moreF = CreateFrame("Frame", nil, strip)
        moreF:SetPoint("LEFT", strip, "LEFT", xOff, 0)
        moreF:SetSize(56, MBR_H - 14)
        moreF:Show()
        local moreFs = moreF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        moreFs:SetAllPoints()
        moreFs:SetJustifyH("LEFT")
        moreFs:SetText("|cff888899+" .. skipped .. " more|r")
    end
end

-- Called by GroupManager when this player joins a team or an existing team's
-- roster changes. Refreshes the tab strip, and if this team is now selected
-- (or nothing was selected) also updates the member strip + chat area so the
-- player sees the new state without any manual tab-flipping.
function UI:OnTeamMembershipChanged(groupId)
    local frame = UI.TeamsTab
    if not frame then return end

    -- If the player had nothing selected, pre-select this team so that the
    -- OnShow handler will display it automatically when they next open the tab.
    if selected == nil then
        selected = groupId
    end

    UI:RefreshTeamsGroupList()

    if selected == groupId and frame:IsShown() then
        UI:ShowTeamView(groupId)
    end
end

-- ── Team view ─────────────────────────────────────────────────────────────

function UI:ShowTeamView(groupId)
    local frame = UI.TeamsTab
    if not frame then return end
    local g = GH.Groups:Get(groupId)
    if not g then return end

    EnsureTeamChannel(groupId)

    frame.placeholder:Hide()
    local canManage = GH:CanManageTeam(groupId)
    frame.deleteBtn:SetAlpha(canManage and 1 or 0.35)
    frame.membersBtn:SetAlpha(1)
    frame.inviteBtn:SetAlpha(1)

    UI:RefreshMemberStrip(groupId)

    lastMsgTs = 0
    UI:RefreshTeamChatMessages(groupId)
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
        if frame.msgScrollFrame then
            frame.msgScrollFrame:SetVerticalScroll(
                frame.msgScrollFrame:GetVerticalScrollRange())
        end
    end)
end

-- ── ChatManager callbacks ─────────────────────────────────────────────────
-- ChatTab.lua is loaded before TeamsTab.lua (per .toc), so this definition
-- is final. Both tabs' real-time update needs are handled here.

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
                local gapText = gapRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

            local timeFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timeFs:SetPoint("LEFT", row, "LEFT", 0, 0)
            timeFs:SetText("|cff555566[" .. GH:FormatTime(msg.ts) .. "]|r ")
            timeFs:SetTextColor(1, 1, 1)
            local timeW = timeFs:GetStringWidth() + 2

            local senderBtn = CreateFrame("Button", nil, row)
            senderBtn:SetPoint("LEFT", row, "LEFT", timeW, 0)
            senderBtn:SetHeight(14)
            local senderFs = senderBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
            local bodyFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    accent:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 1)

    local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", dlg, "TOP", 0, -14)
    title:SetText(g.name .. " — Members")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local roleNote = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

            local nm = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
                    if selected == groupId then
                        UI:RefreshMemberStrip(groupId)
                    end
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

        local hint = inviteBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
                        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    accent:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 1)

    local heading = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOP", dlg, "TOP", 0, -14)
    heading:SetText("Team Invite")
    heading:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local body = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    dlg:SetSize(320, 110)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    dlg:SetFrameStrata("DIALOG")
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText(existingName and "Rename Team" or "New Team Name")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local eb = S:EditBox(dlg, 280, 28, 60)
    eb:SetPoint("TOP", title, "BOTTOM", 0, -10)
    if existingName then eb:SetText(existingName) end
    eb:SetFocus()

    local okBtn = S:Button(dlg, "OK", 80, 26)
    okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 12)

    local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 12)

    local function Confirm()
        local name = eb:GetText():match("^%s*(.-)%s*$")
        if name ~= "" then callback(name) end
        dlg:Hide()
    end
    okBtn:SetScript("OnClick", Confirm)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    eb:SetScript("OnEnterPressed", Confirm)
end

function UI:ShowGroupNameDialog(existingName, callback)
    UI:ShowTeamNameDialog(existingName, callback)
end
