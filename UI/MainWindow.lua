-- GuildHub - MainWindow
-- Root frame: title bar, sidebar navigation, and tab content area.

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local TABS = { "Members", "Chat", "Teams", "Events", "LFM" }


function UI:Initialize()
    self:CreateMainWindow()
end

function UI:CreateMainWindow()
    local win = CreateFrame("Frame", "GuildHubMainWindow", UIParent)
    win:SetSize(S.WINDOW_W, S.WINDOW_H)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()

    tinsert(UISpecialFrames, "GuildHubMainWindow")

    win:SetScript("OnHide", function()
        local orphans = {
            "GHLFMSignupPopup", "GHLFMApplicantsPanel", "GHLFMLeaderboardPanel",
            "GuildHubEventCreateDialog", "GuildHubTeamMembersDialog",
            "GuildHubTeamInvitePopup", "GuildHubTeamNameDialog",
            "GuildHubCopyDialog", "GuildHubChatMembersDialog",
            "GuildHubNameDialog", "GuildHubPersonalNoteDialog",
            "GuildHubTeamAssignDialog", "GuildHubContextMenu",
        }
        for _, name in ipairs(orphans) do
            local f = rawget(_G, name)
            if f and f:IsShown() then f:Hide() end
        end
        if UI._contextMenu and UI._contextMenu:IsShown() then
            UI._contextMenu:Hide()
        end
    end)

    -- Main background
    local mainBg = win:CreateTexture(nil, "BACKGROUND")
    mainBg:SetAllPoints()
    mainBg:SetColorTexture(S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 1.0)

    -- Thin outer border
    local function MakeBorder(point, w, h)
        local t = win:CreateTexture(nil, "BORDER")
        t:SetSize(w, h)
        t:SetPoint(point)
        t:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.7)
    end
    MakeBorder("TOPLEFT",    S.WINDOW_W, 1)
    MakeBorder("BOTTOMLEFT", S.WINDOW_W, 1)
    MakeBorder("TOPLEFT",    1, S.WINDOW_H)
    MakeBorder("TOPRIGHT",   1, S.WINDOW_H)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, win)
    titleBar:SetPoint("TOPLEFT",  win, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(S.TITLEBAR_H)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function() win:StartMoving() end)
    titleBar:SetScript("OnMouseUp",   function() win:StopMovingOrSizing() end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.03, 0.03, 0.07, 1)

    local titleAccent = win:CreateTexture(nil, "ARTWORK")
    titleAccent:SetPoint("TOPLEFT",  win, "TOPLEFT",  0, 0)
    titleAccent:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    titleAccent:SetHeight(2)
    titleAccent:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 1)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
    titleText:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    win.titleText = titleText

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 2, 0)
    closeBtn:SetSize(28, 28)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- Settings gear button (left of close button)
    local settingsBtn = CreateFrame("Button", nil, titleBar)
    settingsBtn:SetSize(26, 26)
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", 0, 0)

    local gearIcon = settingsBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetAllPoints()
    gearIcon:SetTexture("Interface/Icons/INV_Misc_Gear_01")
    gearIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    gearIcon:SetVertexColor(0.7, 0.7, 0.8)

    local gearHover = settingsBtn:CreateTexture(nil, "HIGHLIGHT")
    gearHover:SetAllPoints()
    gearHover:SetTexture("Interface/Icons/INV_Misc_Gear_01")
    gearHover:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    gearHover:SetVertexColor(1, 1, 1)
    gearHover:SetAlpha(0)

    settingsBtn:SetScript("OnEnter", function()
        gearIcon:SetVertexColor(1, 1, 1)
        if GameTooltip then
            GameTooltip:SetOwner(settingsBtn, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Settings", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    settingsBtn:SetScript("OnLeave", function()
        gearIcon:SetVertexColor(0.7, 0.7, 0.8)
        if GameTooltip then GameTooltip:Hide() end
    end)
    settingsBtn:SetScript("OnClick", function()
        UI:ToggleSettings()
    end)

    -- Guild name + online count in title
    local function RefreshTitle()
        local guildName = GH:GetGuildName()
        local on, total = GH.GuildData:GetOnlineCount()
        titleText:SetText("|cff7289daGuildHub|r  |cff555566—|r  " .. guildName
            .. "  |cff444455[|r|cff22cc44" .. on .. "|r|cff444455/|r" .. total .. "|cff444455]|r")
    end
    win.RefreshTitle = RefreshTitle

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, win)
    sidebar:SetPoint("TOPLEFT",    win, "TOPLEFT",    0, -S.TITLEBAR_H)
    sidebar:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(S.SIDEBAR_W)

    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(S.COLOR.SIDEBAR[1], S.COLOR.SIDEBAR[2], S.COLOR.SIDEBAR[3], 1)

    -- Sidebar divider
    local sideDiv = win:CreateTexture(nil, "ARTWORK")
    sideDiv:SetSize(1, S.WINDOW_H - S.TITLEBAR_H)
    sideDiv:SetPoint("TOPLEFT", win, "TOPLEFT", S.SIDEBAR_W, -S.TITLEBAR_H)
    sideDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.6)

    -- Banner strip (news ticker: MOTD, upcoming events, recent LFM posts)
    local bannerBar = CreateFrame("Frame", nil, win)
    bannerBar:SetPoint("TOPLEFT",  win, "TOPLEFT",  S.SIDEBAR_W + 1, -S.TITLEBAR_H)
    bannerBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -S.TITLEBAR_H)
    bannerBar:SetHeight(S.BANNER_H)

    local bannerBg = bannerBar:CreateTexture(nil, "BACKGROUND")
    bannerBg:SetAllPoints()
    bannerBg:SetColorTexture(0.03, 0.03, 0.06, 1)

    local bannerDiv = bannerBar:CreateTexture(nil, "ARTWORK")
    bannerDiv:SetPoint("BOTTOMLEFT",  bannerBar, "BOTTOMLEFT")
    bannerDiv:SetPoint("BOTTOMRIGHT", bannerBar, "BOTTOMRIGHT")
    bannerDiv:SetHeight(1)
    bannerDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

    -- Static prefix dot (colored texture; ◆ is not in WoW's built-in font)
    local bannerPrefix = bannerBar:CreateTexture(nil, "OVERLAY")
    bannerPrefix:SetSize(6, 6)
    bannerPrefix:SetPoint("LEFT", bannerBar, "LEFT", 11, 0)
    bannerPrefix:SetColorTexture(0.44, 0.54, 0.85, 1)

    -- Clipping region (right of the prefix icon)
    local bannerClipper = CreateFrame("Frame", nil, bannerBar)
    bannerClipper:SetPoint("TOPLEFT",     bannerBar, "TOPLEFT",     22, 0)
    bannerClipper:SetPoint("BOTTOMRIGHT", bannerBar, "BOTTOMRIGHT", -6, 1)
    bannerClipper:SetClipsChildren(true)

    -- Inner frame that scrolls within the clipper
    local bannerInner = CreateFrame("Frame", nil, bannerClipper)
    bannerInner:SetHeight(S.BANNER_H)
    bannerInner:SetWidth(4000)
    bannerInner:SetPoint("LEFT", bannerClipper, "LEFT", 0, 0)

    local bannerFS = bannerInner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bannerFS:SetPoint("LEFT", bannerInner, "LEFT", 0, 0)
    bannerFS:SetJustifyH("LEFT")
    bannerFS:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

    -- Scroll state
    local bannerScrollX = 0
    local bannerClipW   = 0
    local bannerTextW   = 0
    local BANNER_SPEED  = 60  -- px/sec

    local function BuildBannerText()
        local items = {}
        local motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
        if motd ~= "" then
            items[#items + 1] = "|cffF2CF00MOTD:|r " .. motd
        end
        local now = GH:GetTimestamp()
        for _, ev in ipairs(GH.Events:GetAll()) do
            if ev.date and ev.date >= now and ev.date <= now + 6 * 3600 then
                local mins = math.floor((ev.date - now) / 60)
                local when = mins < 60
                    and (mins .. "m")
                    or  (math.floor(mins / 60) .. "h" .. (mins % 60 > 0 and (mins % 60 .. "m") or ""))
                items[#items + 1] = "|cff6ca3f7Event:|r " .. ev.title .. " (in " .. when .. ")"
            end
        end
        local cutoff = now - 6 * 3600
        for _, post in ipairs(GH.Recruit:GetAll()) do
            if (post.ts or 0) >= cutoff then
                local open = GH.Recruit:TotalOpen(post)
                if open > 0 then
                    local label = post.title or post.body or (post.activityType .. " LFM")
                    items[#items + 1] = "|cff20cc55LFM:|r " .. label
                        .. " — " .. (post.author or "?")
                        .. " (" .. open .. " slot" .. (open ~= 1 and "s" or "") .. " open)"
                end
            end
        end
        if #items == 0 then return nil end
        return table.concat(items, "   |cff333366—|r   ")
    end

    local bannerLastText = nil

    local function RefreshBannerTicker()
        local text = BuildBannerText() or ""
        if text == bannerLastText then return end
        bannerLastText = text
        bannerFS:SetText(text)
        bannerTextW   = 0  -- reset scroll; OnUpdate recalculates width after layout
        bannerScrollX = 0
    end

    bannerBar:SetScript("OnUpdate", function(_, elapsed)
        if bannerTextW == 0 then
            bannerClipW = bannerClipper:GetWidth()
            bannerTextW = bannerFS:GetStringWidth()
            if bannerTextW == 0 or bannerClipW == 0 then return end
            bannerScrollX = bannerClipW + 8
        end
        bannerScrollX = bannerScrollX - BANNER_SPEED * elapsed
        if bannerScrollX < -(bannerTextW + 8) then
            bannerScrollX = bannerClipW + 8
        end
        bannerInner:ClearAllPoints()
        bannerInner:SetPoint("LEFT", bannerClipper, "LEFT", bannerScrollX, 0)
    end)

    win.RefreshBannerTicker = RefreshBannerTicker
    win.bannerBar = bannerBar

    -- Content area (pushed down by banner height)
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT",     win, "TOPLEFT",     S.SIDEBAR_W + 1, -(S.TITLEBAR_H + S.BANNER_H))
    content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
    win.contentArea = content

    -- Nav buttons
    local navBtns  = {}
    local contentW = S.WINDOW_W - S.SIDEBAR_W - 1
    local contentH = S.WINDOW_H - S.TITLEBAR_H

    local function HideAllTabContent()
        for _, t in ipairs(TABS) do
            if UI[t .. "Tab"] then UI[t .. "Tab"]:Hide() end
        end
        if win.settingsPage then win.settingsPage:Hide() end
    end

    local function SelectTab(tabName)
        win.activeTab = tabName
        HideAllTabContent()
        for _, nb in pairs(navBtns) do
            nb.activeBg:SetAlpha(0)
            nb.label:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end
        local nb = navBtns[tabName]
        if nb then
            nb.activeBg:SetAlpha(1)
            nb.label:SetTextColor(1, 1, 1)
        end
        if UI[tabName .. "Tab"] then
            UI[tabName .. "Tab"]:Show()
        end
    end
    win.SelectTab = SelectTab

    for i, tabName in ipairs(TABS) do
        local nb = CreateFrame("Button", nil, sidebar)
        nb:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  0, -(i - 1) * 44 - 12)
        nb:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, -(i - 1) * 44 - 12)
        nb:SetHeight(40)

        local activeBg = nb:CreateTexture(nil, "BACKGROUND")
        activeBg:SetAllPoints()
        activeBg:SetColorTexture(S.COLOR.NAV_ACTIVE[1], S.COLOR.NAV_ACTIVE[2], S.COLOR.NAV_ACTIVE[3], 1)
        activeBg:SetAlpha(0)
        nb.activeBg = activeBg

        local hoverBg = nb:CreateTexture(nil, "BACKGROUND", nil, -1)
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(1, 1, 1, 0)
        nb.hoverBg = hoverBg

        local accentBar = nb:CreateTexture(nil, "ARTWORK")
        accentBar:SetSize(3, 28)
        accentBar:SetPoint("LEFT", nb, "LEFT", 0, 0)
        accentBar:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0)
        nb.accentBar = accentBar

        local label = nb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", nb, "LEFT", 16, 0)
        label:SetText(tabName)
        label:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        nb.label = label

        nb:SetScript("OnEnter", function(self)
            if win.activeTab ~= tabName then
                self.hoverBg:SetColorTexture(1, 1, 1, 0.04)
            end
        end)
        nb:SetScript("OnLeave", function(self)
            self.hoverBg:SetColorTexture(1, 1, 1, 0)
        end)
        nb:SetScript("OnClick", function()
            SelectTab(tabName)
            if tabName == "Members" then GH.GuildData:Refresh() end
        end)

        navBtns[tabName] = nb
    end

    -- ── Sidebar: Guild News ─────────────────────────────────────────────────
    -- Bottom of last nav button from sidebar top: (N-1)*44 + 12 + 40
    local NEWS_BASE    = (#TABS - 1) * 44 + 12 + 40   -- = 228
    local NEWS_ITEM_H  = 38
    local NEWS_MAX_ROWS = 6

    local newsDiv = sidebar:CreateTexture(nil, "ARTWORK")
    newsDiv:SetHeight(1)
    newsDiv:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  10, -(NEWS_BASE + 9))
    newsDiv:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -10, -(NEWS_BASE + 9))
    newsDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.4)

    local newsHdrFS = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    newsHdrFS:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -(NEWS_BASE + 18))
    newsHdrFS:SetText("|TInterface/Icons/Achievement_GuildPerk_EverybodysFriend:12:12|t  Guild News")
    newsHdrFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local newsEmptyFS = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    newsEmptyFS:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -(NEWS_BASE + 37))
    newsEmptyFS:SetText("No recent news")
    newsEmptyFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    newsEmptyFS:Hide()
    win.newsEmptyFS = newsEmptyFS

    local newsRows = {}
    for rowI = 1, NEWS_MAX_ROWS do
        local yBase = -(NEWS_BASE + 37 + (rowI - 1) * NEWS_ITEM_H)

        local row = CreateFrame("Button", nil, sidebar)
        row:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  0, yBase)
        row:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, yBase)
        row:SetHeight(NEWS_ITEM_H)

        local rowHover = row:CreateTexture(nil, "BACKGROUND")
        rowHover:SetAllPoints()
        rowHover:SetColorTexture(1, 1, 1, 0)
        row.hoverBg = rowHover
        row:SetScript("OnEnter", function(f) f.hoverBg:SetColorTexture(1, 1, 1, 0.04) end)
        row:SetScript("OnLeave", function(f) f.hoverBg:SetColorTexture(1, 1, 1, 0) end)

        local rowIcon = row:CreateTexture(nil, "ARTWORK")
        rowIcon:SetSize(12, 12)
        rowIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -5)
        rowIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.iconTex = rowIcon

        local rowNameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rowNameFS:SetPoint("TOPLEFT",  row, "TOPLEFT",  22, -3)
        rowNameFS:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)
        rowNameFS:SetJustifyH("LEFT")
        row.nameFS = rowNameFS

        local rowDescFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rowDescFS:SetPoint("TOPLEFT",  row, "TOPLEFT",  6, -18)
        rowDescFS:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -18)
        rowDescFS:SetJustifyH("LEFT")
        rowDescFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        row.descFS = rowDescFS

        row:Hide()
        newsRows[rowI] = row
    end
    win.newsRows   = newsRows
    win.newsBuffer = {}  -- {name, desc, iconTex} entries, newest first

    local newsEventFrame = CreateFrame("Frame")
    newsEventFrame:RegisterEvent("GUILD_NEWS_UPDATE")
    newsEventFrame:RegisterEvent("CHAT_MSG_GUILD_ACHIEVEMENT")
    newsEventFrame:SetScript("OnEvent", function(_, evt, arg1, arg2)
        if evt == "CHAT_MSG_GUILD_ACHIEVEMENT" then
            -- arg1 = full message text  arg2 = sender (should be regular string for this event)
            local shortName = arg2 and Ambiguate(arg2, "short") or "?"
            -- Pull the achievement name out of the first [bracketed] segment in the hyperlink
            local achLink = arg1 and arg1:match("%[(.-)%]") or "Achievement"
            local achIcon
            local achId = arg1 and arg1:match("|Hachievement:(%d+):")
            if achId then
                local ok3, _, _, _, _, _, _, _, _, _, ic = pcall(GetAchievementInfo, tonumber(achId))
                if ok3 then achIcon = ic end
            end
            local nameStr = shortName
            local member  = GH.GuildData and GH.GuildData:FindMember(shortName)
            if member and member.classFileName then
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFileName]
                if cc then
                    nameStr = string.format("|cff%02x%02x%02x%s|r",
                        math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255),
                        shortName)
                end
            end
            table.insert(win.newsBuffer, 1, {
                name    = nameStr,
                desc    = "|cffffcc00" .. achLink .. "|r",
                iconTex = achIcon or "Interface/Icons/Achievement_General",
            })
            while #win.newsBuffer > 20 do table.remove(win.newsBuffer) end
        end
        UI:RefreshGuildNews()
    end)
    win.newsEventFrame = newsEventFrame

    -- Online count badge at sidebar bottom
    local onlineBadge = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    onlineBadge:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 12, 10)
    onlineBadge:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    win.onlineBadge = onlineBadge

    -- Create tab content frames
    UI:CreateMembersTab(content, contentW, contentH)
    UI:CreateChatTab(content, contentW, contentH)
    UI:CreateTeamsTab(content, contentW, contentH)
    UI:CreateEventsTab(content, contentW, contentH)
    UI:CreateLFMTab(content, contentW, contentH)

    -- Create settings page (lazy: built on first access)
    win.settingsPage = nil

    -- Default to Members tab
    SelectTab("Members")

    win.navBtns = navBtns
    self.window = win

    -- Roster refresh callback
    self.OnRosterRefresh = function()
        RefreshTitle()
        local on, total = GH.GuildData:GetOnlineCount()
        onlineBadge:SetText("Online: |cff22cc44" .. on .. "|r / " .. total)
        if win:IsShown() then
            RefreshBannerTicker()
            UI:RefreshGuildNews()
        end
        if win.activeTab == "Members" and win:IsShown() then
            UI:RefreshMembersTab()
        end
    end
end

-- ── Settings page ─────────────────────────────────────────────────────────

function UI:ToggleSettings()
    local win = self.window
    if not win then return end

    if win.settingsPage and win.settingsPage:IsShown() then
        win.settingsPage:Hide()
        -- Restore active tab
        local t = win.activeTab
        if t and UI[t .. "Tab"] then UI[t .. "Tab"]:Show() end
        return
    end

    -- Build settings page on first open
    if not win.settingsPage then
        UI:BuildSettingsPage(win.contentArea)
    end

    -- Hide all tab content and show settings
    for _, t in ipairs(TABS) do
        if UI[t .. "Tab"] then UI[t .. "Tab"]:Hide() end
    end
    win.settingsPage:Show()
end

function UI:BuildSettingsPage(parent)
    local win  = self.window
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    -- Background
    local bg = page:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 1)

    -- Header bar
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT",  page, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    header:SetHeight(44)
    S:Bg(header, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    local titleFs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFs:SetPoint("CENTER", header, "CENTER")
    titleFs:SetText("Settings")
    titleFs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local backBtn = S:Button(header, "← Back", 80, 26)
    backBtn:SetPoint("LEFT", header, "LEFT", 12, 0)
    backBtn:SetScript("OnClick", function() UI:ToggleSettings() end)

    -- ── Settings rows ─────────────────────────────────────────────────────
    local ROW_H = 46
    local rowY  = -56

    -- Helper: alternating stripe row frame with a left-aligned label
    local function MakeRow(labelText, yOff)
        local row = CreateFrame("Frame", nil, page)
        row:SetPoint("TOPLEFT",  page, "TOPLEFT",  24, yOff)
        row:SetPoint("TOPRIGHT", page, "TOPRIGHT", -24, yOff)
        row:SetHeight(ROW_H)

        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        local band = math.floor((-yOff - 56) / ROW_H)
        if band % 2 == 0 then
            stripe:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.55)
        else
            stripe:SetColorTexture(0, 0, 0, 0)
        end

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", 12, 0)
        lbl:SetWidth(210)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(labelText)
        lbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        return row
    end

    -- Helper: ON/OFF toggle button bound to a DB setting
    local function MakeToggle(parent, settingKey, defaultVal)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(62, 26)
        btn:SetPoint("LEFT", parent, "LEFT", 230, 0)

        local tbg = btn:CreateTexture(nil, "BACKGROUND")
        tbg:SetAllPoints()
        btn.tbg = tbg
        local tlbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tlbl:SetAllPoints()
        btn.tlbl = tlbl

        local function Refresh()
            local val = GH.DB:GetSetting(settingKey)
            if val == nil then val = defaultVal end
            if val then
                btn.tbg:SetColorTexture(
                    S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 0.75)
                btn.tlbl:SetText("ON")
            else
                btn.tbg:SetColorTexture(
                    S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.5)
                btn.tlbl:SetText("OFF")
            end
        end
        Refresh()

        btn:SetScript("OnClick", function()
            local cur = GH.DB:GetSetting(settingKey)
            if cur == nil then cur = defaultVal end
            GH.DB:SetSetting(settingKey, not cur)
            Refresh()
        end)
        btn:SetScript("OnEnter", function()
            btn.tbg:SetColorTexture(0.5, 0.5, 0.65, 0.6)
        end)
        btn:SetScript("OnLeave", Refresh)
        return btn
    end

    -- 1 — Time Format
    local row1 = MakeRow("Time Format", rowY)
    rowY = rowY - ROW_H

    do
        local function GetFmt() return GH.DB:GetSetting("timeFormat") or "24h" end
        local btn12 = S:Button(row1, "12-hour", 78, 26)
        btn12:SetPoint("LEFT", row1, "LEFT", 230, 0)
        local btn24 = S:Button(row1, "24-hour", 78, 26)
        btn24:SetPoint("LEFT", btn12, "RIGHT", 6, 0)

        local function RefreshFmt()
            local fmt = GetFmt()
            local aR, aG, aB = S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3]
            local dR, dG, dB = S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3]
            btn12.bg:SetColorTexture(fmt == "12h" and aR or dR,
                                     fmt == "12h" and aG or dG,
                                     fmt == "12h" and aB or dB, 0.9)
            btn24.bg:SetColorTexture(fmt == "24h" and aR or dR,
                                     fmt == "24h" and aG or dG,
                                     fmt == "24h" and aB or dB, 0.9)
        end
        RefreshFmt()
        btn12:SetScript("OnClick", function()
            GH.DB:SetSetting("timeFormat", "12h"); RefreshFmt()
        end)
        btn24:SetScript("OnClick", function()
            GH.DB:SetSetting("timeFormat", "24h"); RefreshFmt()
        end)

        local hint = row1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("LEFT", row1, "LEFT", 410, 0)
        hint:SetText("Sets the format for all timestamps in GuildHub")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- 2 — Hide Default WoW Guild Window
    local row2 = MakeRow("Hide Default Guild Window", rowY)
    rowY = rowY - ROW_H
    MakeToggle(row2, "hideDefaultGuildFrame", true)
    do
        local hint = row2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("LEFT", row2, "LEFT", 410, 0)
        hint:SetText("Replace WoW's guild window with GuildHub (restart to apply)")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- 3 — Show Offline Members
    local row3 = MakeRow("Show Offline Members", rowY)
    rowY = rowY - ROW_H
    MakeToggle(row3, "showOfflineMembers", true)
    do
        local hint = row3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("LEFT", row3, "LEFT", 410, 0)
        hint:SetText("Display offline members in the roster list")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- Helper: integer spinner for a DB setting.
    -- Pass locked=true to grey out and disable controls (GM-only settings).
    local function MakeSpinner(row, settingKey, defaultVal, minVal, maxVal, hintText, locked)
        local display = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        display:SetPoint("LEFT", row, "LEFT", 230, 0)
        display:SetWidth(26)
        display:SetJustifyH("CENTER")
        if locked then
            display:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        else
            display:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        end

        local function GetVal() return GH.DB:GetSetting(settingKey) or defaultVal end
        local function RefreshVal() display:SetText(tostring(GetVal())) end
        RefreshVal()

        local minusBtn = S:Button(row, "−", 26, 26)
        minusBtn:SetPoint("LEFT", row, "LEFT", 260, 0)
        if locked then
            minusBtn:SetAlpha(0.35)
            minusBtn:Disable()
        else
            minusBtn:SetScript("OnClick", function()
                GH.DB:SetSetting(settingKey, math.max(minVal, GetVal() - 1))
                RefreshVal()
            end)
        end

        local plusBtn = S:Button(row, "+", 26, 26)
        plusBtn:SetPoint("LEFT", minusBtn, "RIGHT", 4, 0)
        if locked then
            plusBtn:SetAlpha(0.35)
            plusBtn:Disable()
        else
            plusBtn:SetScript("OnClick", function()
                GH.DB:SetSetting(settingKey, math.min(maxVal, GetVal() + 1))
                RefreshVal()
            end)
        end

        local hint = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("LEFT", row, "LEFT", 410, 0)
        hint:SetText(hintText)
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- 4 — Team Rank Threshold (GM only)
    local row4 = MakeRow("Team Rank Threshold", rowY)
    rowY = rowY - ROW_H
    local officerDefault = GH.DB:GetSetting("officerRankThreshold") or 1
    MakeSpinner(row4, "teamRankThreshold", officerDefault, 0, 9,
        "Rank index ≤ this can create/manage teams (default " .. officerDefault .. ")",
        not GH:IsGuildMaster())

    -- 5 — Officer Rank Threshold (GM only)
    local row5 = MakeRow("Officer Rank Threshold", rowY)
    rowY = rowY - ROW_H
    MakeSpinner(row5, "officerRankThreshold", 1, 0, 9,
        "Rank index ≤ this grants all officer features (default 1)",
        not GH:IsGuildMaster())

    -- 6 — Debug Mode
    local row6 = MakeRow("Debug Mode", rowY)
    rowY = rowY - ROW_H
    do
        local btn = MakeToggle(row6, "debugMode", false)
        -- Sync GH._debugMode whenever the toggle is clicked.
        local origClick = btn:GetScript("OnClick")
        btn:SetScript("OnClick", function()
            origClick()
            GH._debugMode = GH.DB:GetSetting("debugMode") == true
        end)
        local hint = row6:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("LEFT", row6, "LEFT", 410, 0)
        hint:SetText("Print debug output to chat (also: /gh debug on|off)")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    win.settingsPage = page
    page:Hide()
end

-- ── Guild News refresh ────────────────────────────────────────────────────

function UI:RefreshGuildNews()
    local win = self.window
    if not win or not win.newsRows then return end
    local rows    = win.newsRows
    local emptyFS = win.newsEmptyFS

    for _, row in ipairs(rows) do row:Hide() end

    local rowIdx = 0
    local shown  = {}  -- desc strings already displayed, used to deduplicate

    -- ── Source 1: WoW guild news API (items, may be empty until GuildFrame loads) ──
    local ok, numNews = pcall(GetNumGuildNews)
    if ok and numNews and numNews > 0 then
        for i = 1, numNews do
            if rowIdx >= #rows then break end
            local ok2, newsType, playerName, _, _, _, _, _, id1 = pcall(GetGuildNewsItem, i)
            if not ok2 or not newsType then break end

            local isAchiev = newsType == 6
            local isItem   = newsType == 3 or newsType == 4 or newsType == 5

            if isAchiev or isItem then
                local shortName = playerName and playerName:match("^([^%-]+)") or (playerName or "?")
                local nameStr   = shortName
                local member    = GH.GuildData and GH.GuildData:FindMember(shortName)
                if member and member.classFileName then
                    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFileName]
                    if cc then
                        nameStr = string.format("|cff%02x%02x%02x%s|r",
                            math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255),
                            shortName)
                    end
                end

                local desc, iconTex
                if isAchiev then
                    local achName, achIcon
                    if id1 and id1 > 0 then
                        local ok3, _, n, _, _, _, _, _, _, _, ic = pcall(GetAchievementInfo, id1)
                        if ok3 then achName, achIcon = n, ic end
                    end
                    iconTex = achIcon or "Interface/Icons/Achievement_General"
                    desc    = "|cffffcc00" .. (achName or "Achievement") .. "|r"
                else
                    local actionWord = newsType == 3 and "looted" or newsType == 4 and "crafted" or "purchased"
                    local displayLink, tex
                    local ok3, lnk = pcall(GetGuildNewsItemLink, i)
                    if ok3 and lnk then
                        displayLink = lnk
                        local iid = tonumber(lnk:match("item:(%d+)"))
                        if iid then
                            local info = C_Item.GetItemInfo(iid)
                            if info then tex = info.itemIcon end
                        end
                    elseif id1 then
                        local info = C_Item.GetItemInfo(id1)
                        if info then displayLink, tex = info.itemName, info.itemIcon end
                    end
                    iconTex = tex or "Interface/Icons/INV_Misc_Bag_07"
                    desc    = actionWord .. " " .. (displayLink or "?")
                end

                if not shown[desc] then
                    rowIdx = rowIdx + 1
                    local row = rows[rowIdx]
                    row.nameFS:SetText(nameStr)
                    row.descFS:SetText(desc)
                    row.iconTex:SetTexture(iconTex)
                    shown[desc] = true
                    row:Show()
                end
            end
        end
    end

    -- ── Source 2: in-memory buffer from CHAT_MSG_GUILD_ACHIEVEMENT ────────────
    for _, entry in ipairs(win.newsBuffer or {}) do
        if rowIdx >= #rows then break end
        if not shown[entry.desc] then
            rowIdx = rowIdx + 1
            local row = rows[rowIdx]
            row.nameFS:SetText(entry.name or "")
            row.descFS:SetText(entry.desc or "")
            row.iconTex:SetTexture(entry.iconTex or "Interface/Icons/Achievement_General")
            shown[entry.desc] = true
            row:Show()
        end
    end

    if rowIdx == 0 then
        if emptyFS then emptyFS:Show() end
    else
        if emptyFS then emptyFS:Hide() end
    end
end

-- ── Public API ────────────────────────────────────────────────────────────

function UI:Show()
    if not self.window then return end
    GH.GuildData:Refresh()
    self.window.RefreshTitle()
    self.window.RefreshBannerTicker()
    self:RefreshGuildNews()
    self.window:Show()
    if not self.window.activeTab then
        self.window.SelectTab("Members")
    end
end

function UI:Hide()
    if self.window then self.window:Hide() end
end

function UI:Toggle()
    if self.window and self.window:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function UI:UpdateChatBadge()
    if not self.window then return end
    local nb = self.window.navBtns and self.window.navBtns["Chat"]
    if not nb then return end
    local total = GH.Chat:GetTotalUnread()
    if total > 0 then
        nb.label:SetText("Chat |cffff4444(" .. (total > 99 and "99+" or tostring(total)) .. ")|r")
    else
        nb.label:SetText("Chat")
    end
end

-- OnLFMUpdated is defined in RecruitTab.lua and dispatched by RecruitManager.
