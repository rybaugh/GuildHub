-- GuildHub - MainWindow
-- Root frame: title bar, sidebar navigation, and tab content area.

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local TABS = { "Members", "Activity", "Chat", "Teams", "Events", "LFM", "Recruit" }


function UI:Initialize()
    S:ApplyFontSize(GH.DB:GetSetting("fontSize") or 10)
    self:CreateMainWindow()
end

-- Size bounds for the resizable window.
local WIN_MIN_W, WIN_MIN_H = 840,  520
local WIN_MAX_W, WIN_MAX_H = 1800, 1100

function UI:CreateMainWindow()
    local win = CreateFrame("Frame", "GuildHubMainWindow", UIParent)

    -- Restore the user's saved dimensions (falls back to the style defaults).
    local savedW = GH.DB:GetSetting("windowW") or S.WINDOW_W
    local savedH = GH.DB:GetSetting("windowH") or S.WINDOW_H
    win:SetSize(
        math.max(WIN_MIN_W, math.min(WIN_MAX_W, savedW)),
        math.max(WIN_MIN_H, math.min(WIN_MAX_H, savedH)))

    win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:SetResizable(true)
    win:SetResizeBounds(WIN_MIN_W, WIN_MIN_H, WIN_MAX_W, WIN_MAX_H)
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
            -- Roster profile dialogs
            "GuildHubSetJoinDateDialog", "GuildHubSetBirthdayDialog",
            "GuildHubBanDialog", "GuildHubAddAltDialog",
            "GuildHubMacroDialog", "GuildHubExportDialog",
            "GuildHubBanListWindow", "GuildHubAddBanDialog", "GuildHubEditBanDialog",
            -- Mouseover window is in UISpecialFrames; must be closed here or it
            -- blocks the WoW game menu (CloseSpecialWindows returns non-nil).
            "GuildHubMouseoverWindow",
        }
        for _, name in ipairs(orphans) do
            local f = rawget(_G, name)
            if f and f:IsShown() then f:Hide() end
        end
        if UI._contextMenu and UI._contextMenu:IsShown() then
            UI._contextMenu:Hide()
        end
    end)

    -- Main background: subtle top-to-bottom depth gradient
    S:GradientBg(win, "VERTICAL",
        S.COLOR.BG[1] + 0.008, S.COLOR.BG[2] + 0.006, S.COLOR.BG[3] + 0.018, 0.98,
        S.COLOR.BG[1],         S.COLOR.BG[2],         S.COLOR.BG[3],          0.98)

    -- Outer border: anchor-based so it stretches with the window when resized.
    local function EdgeLine(p1, p2, isHoriz)
        local t = win:CreateTexture(nil, "BORDER")
        t:SetPoint(p1, win, p1)
        t:SetPoint(p2, win, p2)
        if isHoriz then t:SetHeight(1) else t:SetWidth(1) end
        t:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.55)
    end
    EdgeLine("TOPLEFT",    "TOPRIGHT",    true)   -- top
    EdgeLine("BOTTOMLEFT", "BOTTOMRIGHT", true)   -- bottom
    EdgeLine("TOPLEFT",    "BOTTOMLEFT",  false)  -- left
    EdgeLine("TOPRIGHT",   "BOTTOMRIGHT", false)  -- right

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, win)
    titleBar:SetPoint("TOPLEFT",  win, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(S.TITLEBAR_H)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function() win:StartMoving() end)
    titleBar:SetScript("OnMouseUp",   function() win:StopMovingOrSizing() end)

    -- Title bar gradient: very dark at the top, slightly lighter at the bottom
    S:GradientBg(titleBar, "VERTICAL",
        S.COLOR.TITLE_TOP[1], S.COLOR.TITLE_TOP[2], S.COLOR.TITLE_TOP[3], 1,
        S.COLOR.TITLE_BOT[1], S.COLOR.TITLE_BOT[2], S.COLOR.TITLE_BOT[3], 1)

    -- Bottom separator under title bar
    local titleBarSep = titleBar:CreateTexture(nil, "ARTWORK")
    titleBarSep:SetPoint("BOTTOMLEFT",  titleBar, "BOTTOMLEFT")
    titleBarSep:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT")
    titleBarSep:SetHeight(1)
    titleBarSep:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.45)

    -- 3-px gold accent stripe at very top of the window
    local titleAccent = win:CreateTexture(nil, "OVERLAY")
    titleAccent:SetPoint("TOPLEFT",  win, "TOPLEFT",  0, 0)
    titleAccent:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    titleAccent:SetHeight(3)
    local _taOk = pcall(function()
        titleAccent:SetGradient("HORIZONTAL",
            CreateColor(S.COLOR.GOLD[1] * 0.6, S.COLOR.GOLD[2] * 0.6, S.COLOR.GOLD[3] * 0.4, 0.7),
            CreateColor(S.COLOR.GOLD[1],        S.COLOR.GOLD[2],        S.COLOR.GOLD[3],        1.0))
    end)
    if not _taOk then
        titleAccent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.85)
    end

    local titleText = S:FS(titleBar, "OVERLAY", "large")
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

    local function RefreshTitle()
        local guildName = GH:GetGuildName()
        titleText:SetText("|cff7289daGuildHub|r  |cff555566—|r  " .. guildName)
    end
    win.RefreshTitle = RefreshTitle

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, win)
    sidebar:SetPoint("TOPLEFT",    win, "TOPLEFT",    0, -S.TITLEBAR_H)
    sidebar:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(S.SIDEBAR_W)

    -- Sidebar: subtle top-to-bottom gradient gives the nav panel visual depth
    S:GradientBg(sidebar, "VERTICAL",
        S.COLOR.SIDEBAR[1] + 0.008, S.COLOR.SIDEBAR[2] + 0.006, S.COLOR.SIDEBAR[3] + 0.016, 1,
        S.COLOR.SIDEBAR[1],         S.COLOR.SIDEBAR[2],         S.COLOR.SIDEBAR[3],          1)

    -- Sidebar divider: anchor top→bottom so it grows with the window height.
    local sideDiv = win:CreateTexture(nil, "ARTWORK")
    sideDiv:SetWidth(1)
    sideDiv:SetPoint("TOPLEFT",    win, "TOPLEFT",    S.SIDEBAR_W, -S.TITLEBAR_H)
    sideDiv:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", S.SIDEBAR_W, 0)
    sideDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.6)

    -- Banner strip (news ticker: MOTD, upcoming events, recent LFM posts)
    local bannerBar = CreateFrame("Frame", nil, win)
    bannerBar:SetPoint("TOPLEFT",  win, "TOPLEFT",  S.SIDEBAR_W + 1, -S.TITLEBAR_H)
    bannerBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -S.TITLEBAR_H)
    bannerBar:SetHeight(S.BANNER_H)

    -- Banner bar: gradient for a bit of depth
    S:GradientBg(bannerBar, "VERTICAL",
        0.036, 0.034, 0.068, 1,
        0.026, 0.024, 0.052, 1)

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

    local bannerFS = S:FS(bannerInner, "OVERLAY")
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

    -- ── Invite controls embedded in title bar (privilege-gated) ──────────────
    -- Visible only when the player has the guild rank permission to invite.
    -- Layout (right → left): settings gear | [Invite btn] [input box] | title text

    local function PlayerCanInvite()
        if C_GuildInfo and C_GuildInfo.CanInvite then
            local ok, res = pcall(C_GuildInfo.CanInvite)
            if ok then return res == true end
        end
        return GH:IsOfficer()
    end

    -- Invite button — anchored left of the settings gear
    local inviteBtn = S:Button(titleBar, "Invite", 58, 22)
    inviteBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -10, 0)

    -- Edit box — anchored left of the invite button
    local inviteEB = CreateFrame("EditBox", "GuildHubInviteEditBox", titleBar)
    inviteEB:SetSize(168, 22)
    inviteEB:SetPoint("RIGHT", inviteBtn, "LEFT", -4, 0)
    inviteEB:SetFontObject(S.FontSmall)
    inviteEB:SetAutoFocus(false)
    inviteEB:SetMaxLetters(64)
    inviteEB:SetTextInsets(6, 6, 0, 0)
    local inviteEBbg = inviteEB:CreateTexture(nil, "BACKGROUND")
    inviteEBbg:SetAllPoints()
    inviteEBbg:SetColorTexture(S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)
    local inviteEBborder = inviteEB:CreateTexture(nil, "BORDER")
    inviteEBborder:SetAllPoints()
    inviteEBborder:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
    inviteEBbg:SetPoint("TOPLEFT",     1, -1)
    inviteEBbg:SetPoint("BOTTOMRIGHT", -1, 1)

    local inviteHint = S:FS(inviteEB, "OVERLAY")
    inviteHint:SetPoint("LEFT", inviteEB, "LEFT", 6, 0)
    inviteHint:SetText("Invite player…")
    inviteHint:SetTextColor(0.35, 0.35, 0.45)
    inviteEB:SetScript("OnEditFocusGained", function() inviteHint:Hide() end)
    inviteEB:SetScript("OnEditFocusLost", function()
        if inviteEB:GetText() == "" then inviteHint:Show() end
    end)

    local function DoInvite()
        local name = inviteEB:GetText():match("^%s*(.-)%s*$")
        if name == "" then return end
        if C_GuildInfo and C_GuildInfo.Invite then C_GuildInfo.Invite(name) end
        inviteEB:SetText("")
        inviteHint:Show()
        inviteEB:ClearFocus()
    end
    inviteEB:SetScript("OnEnterPressed", DoInvite)
    inviteEB:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        inviteHint:Show()
    end)
    inviteBtn:SetScript("OnClick", DoInvite)

    -- "Invite sent!" flash — sits left of the input, fades after 4 s
    local inviteStatusFS = S:FS(titleBar, "OVERLAY")
    inviteStatusFS:SetPoint("RIGHT", inviteEB, "LEFT", -8, 0)
    inviteStatusFS:SetWidth(110)
    inviteStatusFS:SetJustifyH("RIGHT")
    inviteStatusFS:SetTextColor(S.COLOR.GREEN[1], S.COLOR.GREEN[2], S.COLOR.GREEN[3])
    inviteStatusFS:Hide()
    win.inviteStatusFS = inviteStatusFS

    local inviteEventFrame = CreateFrame("Frame")
    pcall(function() inviteEventFrame:RegisterEvent("GUILD_INVITE_ACCEPT") end)
    inviteEventFrame:SetScript("OnEvent", function()
        inviteStatusFS:SetText("Invite sent!")
        inviteStatusFS:Show()
        C_Timer.After(4, function() inviteStatusFS:Hide() end)
    end)

    -- Show/hide the whole group based on current guild rank
    local function RefreshInviteVisibility()
        local show = GH:IsInGuild() and PlayerCanInvite()
        inviteEB:SetShown(show)
        inviteBtn:SetShown(show)
        if show then inviteHint:SetShown(inviteEB:GetText() == "") end
    end
    win.RefreshInviteVisibility = RefreshInviteVisibility
    RefreshInviteVisibility()

    -- Content area (banner is the only bar below the title)
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT",     win, "TOPLEFT",     S.SIDEBAR_W + 1,
        -(S.TITLEBAR_H + S.BANNER_H))
    content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
    win.contentArea = content

    -- Nav buttons
    local navBtns  = {}
    -- Use the live window size so tabs are sized correctly for the restored dimensions.
    local contentW = win:GetWidth()  - S.SIDEBAR_W - 1
    local contentH = win:GetHeight() - S.TITLEBAR_H

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
            nb.accentBar:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0)
            nb.label:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        end
        local nb = navBtns[tabName]
        if nb then
            nb.activeBg:SetAlpha(1)
            nb.accentBar:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 1)
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

        -- Hide Activity tab nav button when roster profiles feature is off
        if tabName == "Activity" and GH.DB:GetSetting("rosterProfilesEnabled") == false then
            nb:Hide()
        end
        -- Recruit tab is officer-only
        if tabName == "Recruit" and not GH:IsOfficer() then
            nb:Hide()
        end

        -- Active state: horizontal gradient from nav-active to transparent (right edge)
        local activeBg = nb:CreateTexture(nil, "BACKGROUND")
        activeBg:SetAllPoints()
        local _abOk = pcall(function()
            activeBg:SetGradient("HORIZONTAL",
                CreateColor(S.COLOR.NAV_ACTIVE[1], S.COLOR.NAV_ACTIVE[2], S.COLOR.NAV_ACTIVE[3], 0.85),
                CreateColor(S.COLOR.NAV_ACTIVE[1] * 0.4, S.COLOR.NAV_ACTIVE[2] * 0.4, S.COLOR.NAV_ACTIVE[3] * 0.4, 0))
        end)
        if not _abOk then
            activeBg:SetColorTexture(S.COLOR.NAV_ACTIVE[1], S.COLOR.NAV_ACTIVE[2], S.COLOR.NAV_ACTIVE[3], 0.75)
        end
        activeBg:SetAlpha(0)
        nb.activeBg = activeBg

        -- Hover state: very faint tint
        local hoverBg = nb:CreateTexture(nil, "BACKGROUND", nil, -1)
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(1, 1, 1, 0)
        nb.hoverBg = hoverBg

        -- Left accent bar — 3px wide, full button height
        local accentBar = nb:CreateTexture(nil, "ARTWORK")
        accentBar:SetSize(3, 40)
        accentBar:SetPoint("LEFT", nb, "LEFT", 0, 0)
        accentBar:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0)
        nb.accentBar = accentBar

        local label = S:FS(nb, "OVERLAY", "normal")
        label:SetPoint("LEFT", nb, "LEFT", 18, 0)
        label:SetText(tabName)
        label:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        nb.label = label

        nb:SetScript("OnEnter", function(self)
            if win.activeTab ~= tabName then
                self.hoverBg:SetColorTexture(1, 1, 1, 0.05)
                self.label:SetTextColor(
                    S.COLOR.TEXT[1] * 0.85, S.COLOR.TEXT[2] * 0.85, S.COLOR.TEXT[3] * 0.85)
            end
        end)
        nb:SetScript("OnLeave", function(self)
            self.hoverBg:SetColorTexture(1, 1, 1, 0)
            if win.activeTab ~= tabName then
                self.label:SetTextColor(
                    S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
            end
        end)
        nb:SetScript("OnClick", function()
            SelectTab(tabName)
            if tabName == "Members"  then GH.GuildData:Refresh() end
            if tabName == "Activity" then UI:RefreshActivityTab() end
            if tabName == "LFM"      then GH.Recruit:BroadcastAll(); UI:RefreshLFMList() end
            if tabName == "Recruit"  then
                GH.GuildRecruit:RequestApplicants()
                UI:RefreshApplicantsList()
            end
        end)

        navBtns[tabName] = nb
    end

    -- ── Sidebar: Guild News ─────────────────────────────────────────────────
    -- Bottom of last nav button from sidebar top: (N-1)*44 + 12 + 40
    local NEWS_BASE    = (#TABS - 1) * 44 + 12 + 40   -- = 316
    local NEWS_ITEM_H  = 38
    local NEWS_MAX_ROWS = 8

    local newsDiv = sidebar:CreateTexture(nil, "ARTWORK")
    newsDiv:SetHeight(1)
    newsDiv:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  10, -(NEWS_BASE + 9))
    newsDiv:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -10, -(NEWS_BASE + 9))
    newsDiv:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.4)

    local newsHdrFS = S:FS(sidebar, "OVERLAY")
    newsHdrFS:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -(NEWS_BASE + 18))
    newsHdrFS:SetText("|TInterface/Icons/Achievement_GuildPerk_EverybodysFriend:12:12|t  Guild News")
    newsHdrFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local newsEmptyFS = S:FS(sidebar, "OVERLAY")
    newsEmptyFS:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -(NEWS_BASE + 37))
    newsEmptyFS:SetText("No recent news")
    newsEmptyFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    newsEmptyFS:Hide()
    win.newsEmptyFS = newsEmptyFS

    -- Clipping container keeps news rows inside the sidebar regardless of count.
    local newsClip = CreateFrame("Frame", nil, sidebar)
    newsClip:SetPoint("TOPLEFT",     sidebar, "TOPLEFT",     0, -(NEWS_BASE + 37))
    newsClip:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 28)   -- leave room for online badge
    newsClip:SetClipsChildren(true)

    local newsRows = {}
    for rowI = 1, NEWS_MAX_ROWS do
        local yBase = -((rowI - 1) * NEWS_ITEM_H)

        local row = CreateFrame("Button", nil, newsClip)
        row:SetPoint("TOPLEFT",  newsClip, "TOPLEFT",  0, yBase)
        row:SetPoint("TOPRIGHT", newsClip, "TOPRIGHT", 0, yBase)
        row:SetHeight(NEWS_ITEM_H)

        local rowHover = row:CreateTexture(nil, "BACKGROUND")
        rowHover:SetAllPoints()
        rowHover:SetColorTexture(1, 1, 1, 0)
        row.hoverBg = rowHover
        row:SetScript("OnEnter", function(f)
            f.hoverBg:SetColorTexture(1, 1, 1, 0.04)
            if f._rawLink then
                GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, f._rawLink)
                GameTooltip:Show()
            elseif f._tooltipName or f._tooltipDesc then
                GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
                if f._tooltipName then
                    GameTooltip:AddLine(f._tooltipName, 1, 1, 1)
                end
                if f._tooltipDesc then
                    GameTooltip:AddLine(f._tooltipDesc, 0.85, 0.85, 0.85, true)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(f)
            f.hoverBg:SetColorTexture(1, 1, 1, 0)
            GameTooltip:Hide()
        end)

        local rowIcon = row:CreateTexture(nil, "ARTWORK")
        rowIcon:SetSize(12, 12)
        rowIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -5)
        rowIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.iconTex = rowIcon

        local rowNameFS = S:FS(row, "OVERLAY")
        rowNameFS:SetPoint("TOPLEFT",  row, "TOPLEFT",  22, -3)
        rowNameFS:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)
        rowNameFS:SetJustifyH("LEFT")
        row.nameFS = rowNameFS

        local rowDescFS = S:FS(row, "OVERLAY")
        rowDescFS:SetPoint("TOPLEFT",  row, "TOPLEFT",  6, -18)
        rowDescFS:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -18)
        rowDescFS:SetJustifyH("LEFT")
        rowDescFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        row.descFS = rowDescFS

        row:Hide()
        newsRows[rowI] = row
    end
    win.newsRows   = newsRows

    local newsEventFrame = CreateFrame("Frame")
    newsEventFrame:RegisterEvent("GUILD_NEWS_UPDATE")
    newsEventFrame:RegisterEvent("CHAT_MSG_GUILD_ACHIEVEMENT")
    newsEventFrame:SetScript("OnEvent", function(_, evt, arg1, arg2)
        if evt == "CHAT_MSG_GUILD_ACHIEVEMENT" then
            -- arg1 = full message text  arg2 = sender (should be regular string for this event)
            local shortName = arg2 and Ambiguate(arg2, "short") or "?"
            -- Pull the achievement name and raw hyperlink out of the message
            local achLink    = arg1 and arg1:match("%[(.-)%]") or "Achievement"
            local rawLink    = arg1 and arg1:match("(|Hachievement:[^|]+|h%[[^%]]*%]|h)")
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
            local entry = {
                name    = nameStr,
                desc    = "|cffffcc00" .. achLink .. "|r",
                iconTex = achIcon or "Interface/Icons/Achievement_General",
                rawLink = rawLink,
            }
            GH.DB:AddNewsEntry(entry)
        end
        UI:RefreshGuildNews()
    end)
    win.newsEventFrame = newsEventFrame

    -- Online count badge at sidebar bottom
    local onlineBadgeBtn = CreateFrame("Button", nil, sidebar)
    onlineBadgeBtn:SetSize(120, 16)
    onlineBadgeBtn:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 12, 10)
    local onlineBadge = S:FS(onlineBadgeBtn, "OVERLAY")
    onlineBadge:SetAllPoints()
    onlineBadge:SetJustifyH("LEFT")
    onlineBadge:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    onlineBadgeBtn:SetScript("OnClick", function()
        local cur = GH.DB:GetSetting("showOfflineMembers")
        if cur == nil then cur = true end
        GH.DB:SetSetting("showOfflineMembers", not cur)
        UI:RefreshMembersTab()
    end)
    onlineBadgeBtn:SetScript("OnEnter", function() SetCursor("Interface\\Cursor\\Point") end)
    onlineBadgeBtn:SetScript("OnLeave", function() ResetCursor() end)
    win.onlineBadge = onlineBadge

    -- Create tab content frames
    UI:CreateMembersTab(content, contentW, contentH)
    UI:CreateActivityTab(content, contentW, contentH)
    UI:CreateChatTab(content, contentW, contentH)
    UI:CreateTeamsTab(content, contentW, contentH)
    UI:CreateEventsTab(content, contentW, contentH)
    UI:CreateLFMTab(content, contentW, contentH)
    UI:CreateGuildRecruitTab(content, contentW)

    -- Create settings page (lazy: built on first access)
    win.settingsPage = nil

    -- Default to Members tab
    SelectTab("Members")

    win.navBtns = navBtns

    -- ── Resize grip ───────────────────────────────────────────────────────────
    -- Bottom-right drag handle.  Saves the new dimensions so they're restored
    -- next session.  The grip sits above the border in DIALOG strata so it
    -- never gets covered by tab content.
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameStrata("DIALOG")
    grip:SetFrameLevel(win:GetFrameLevel() + 10)

    local gripTex = grip:CreateTexture(nil, "ARTWORK")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    gripTex:SetAlpha(0.60)

    local gripHover = grip:CreateTexture(nil, "HIGHLIGHT")
    gripHover:SetAllPoints()
    gripHover:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Over")
    gripHover:SetAlpha(0.90)

    grip:SetScript("OnEnter", function() gripTex:SetAlpha(1.0) end)
    grip:SetScript("OnLeave", function() gripTex:SetAlpha(0.60) end)
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp",   function()
        win:StopMovingOrSizing()
        local w = math.floor(win:GetWidth()  + 0.5)
        local h = math.floor(win:GetHeight() + 0.5)
        GH.DB:SetSetting("windowW", w)
        GH.DB:SetSetting("windowH", h)
    end)

    self.window = win

    -- Roster refresh callback
    self.OnRosterRefresh = function()
        RefreshTitle()
        win.RefreshInviteVisibility()
        -- Recruit tab visibility follows officer status
        if win.navBtns and win.navBtns["Recruit"] then
            local isOff = GH:IsOfficer()
            win.navBtns["Recruit"]:SetShown(isOff)
            if not isOff and win.activeTab == "Recruit" then
                SelectTab("Members")
            end
        end
        local on, total = GH.GuildData:GetOnlineCount()
        onlineBadge:SetText("Online: |cff22cc44" .. on .. "|r / " .. total)
        if win:IsShown() then
            RefreshBannerTicker()
            UI:RefreshGuildNews()
        end
        if win.activeTab == "Members" and win:IsShown() then
            UI:RefreshMembersTab()
        end
        if win.activeTab == "Chat" and win:IsShown() then
            UI:RefreshCurrentChatMembersPanel()
        end
        if win.activeTab == "Teams" and win:IsShown() then
            if UI.TeamsTab and UI.TeamsTab.rosterPanel and UI.TeamsTab.rosterPanel:IsShown() then
                local g = UI.TeamsTab.rosterPanel._groupId
                if g then UI:RefreshTeamRoster(g) end
            end
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

    local titleFs = S:FS(header, "OVERLAY", "large")
    titleFs:SetPoint("CENTER", header, "CENTER")
    titleFs:SetText("Settings")
    titleFs:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local backBtn = S:Button(header, "← Back", 80, 26)
    backBtn:SetPoint("LEFT", header, "LEFT", 12, 0)
    backBtn:SetScript("OnClick", function() UI:ToggleSettings() end)

    -- Scrollable area below the fixed header
    local sf = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     page, "TOPLEFT",     0, -44)
    sf:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 0)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetPoint("TOPLEFT", sf, "TOPLEFT")
    sf:SetScrollChild(sc)
    -- Match scroll child width to the visible area; update if the window resizes.
    local function SyncScWidth() sc:SetWidth(math.max(sf:GetWidth(), 1)) end
    sf:SetScript("OnSizeChanged", SyncScWidth)
    C_Timer.After(0, SyncScWidth)

    -- ── Settings rows ─────────────────────────────────────────────────────
    local ROW_H = 46
    local rowY  = -12

    -- Helper: alternating stripe row frame with a left-aligned label
    local function MakeRow(labelText, yOff)
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  24, yOff)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -24, yOff)
        row:SetHeight(ROW_H)

        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        local band = math.floor((-yOff - 12) / ROW_H)
        if band % 2 == 0 then
            stripe:SetColorTexture(S.COLOR.PANEL_ALT[1], S.COLOR.PANEL_ALT[2], S.COLOR.PANEL_ALT[3], 0.55)
        else
            stripe:SetColorTexture(0, 0, 0, 0)
        end

        local lbl = S:FS(row, "OVERLAY", "normal")
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
        local tlbl = S:FS(btn, "OVERLAY")
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

    -- 0 — Window Size
    local row0 = MakeRow("Window Size", rowY)
    rowY = rowY - ROW_H
    do
        local sizeFS = S:FS(row0, "OVERLAY", "normal")
        sizeFS:SetPoint("LEFT", row0, "LEFT", 230, 0)
        sizeFS:SetWidth(100)
        sizeFS:SetJustifyH("LEFT")
        sizeFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

        local function RefreshSizeLabel()
            local w = self.window
            if w then
                local cw = math.floor(w:GetWidth()  + 0.5)
                local ch = math.floor(w:GetHeight() + 0.5)
                sizeFS:SetText(cw .. " × " .. ch)
            end
        end
        RefreshSizeLabel()

        local resetBtn = S:Button(row0, "Reset to Default", 130, 26)
        resetBtn:SetPoint("LEFT", row0, "LEFT", 336, 0)
        resetBtn:SetScript("OnClick", function()
            local w = self.window
            if w then
                w:SetSize(S.WINDOW_W, S.WINDOW_H)
                GH.DB:SetSetting("windowW", S.WINDOW_W)
                GH.DB:SetSetting("windowH", S.WINDOW_H)
                RefreshSizeLabel()
            end
        end)

        local hint = S:FS(row0, "OVERLAY")
        hint:SetPoint("LEFT", row0, "LEFT", 476, 0)
        hint:SetText("Drag the ⇲ grip at the bottom-right corner to resize")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- Font Size
    local rowFont = MakeRow("Font Size", rowY)
    rowY = rowY - ROW_H
    do
        local MIN_SIZE, MAX_SIZE = 9, 15

        local sizeDisplay = S:FS(rowFont, "OVERLAY", "normal")
        sizeDisplay:SetPoint("LEFT", rowFont, "LEFT", 230, 0)
        sizeDisplay:SetWidth(26)
        sizeDisplay:SetJustifyH("CENTER")
        sizeDisplay:SetTextColor(
            S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

        local function GetSize() return GH.DB:GetSetting("fontSize") or 10 end
        local function RefreshDisplay() sizeDisplay:SetText(tostring(GetSize())) end
        RefreshDisplay()

        local minusBtn = S:Button(rowFont, "−", 26, 26)
        minusBtn:SetPoint("LEFT", rowFont, "LEFT", 260, 0)
        minusBtn:SetScript("OnClick", function()
            local newSize = math.max(MIN_SIZE, GetSize() - 1)
            GH.DB:SetSetting("fontSize", newSize)
            S:ApplyFontSize(newSize)
            RefreshDisplay()
        end)

        local plusBtn = S:Button(rowFont, "+", 26, 26)
        plusBtn:SetPoint("LEFT", minusBtn, "RIGHT", 4, 0)
        plusBtn:SetScript("OnClick", function()
            local newSize = math.min(MAX_SIZE, GetSize() + 1)
            GH.DB:SetSetting("fontSize", newSize)
            S:ApplyFontSize(newSize)
            RefreshDisplay()
        end)

        local hint = S:FS(rowFont, "OVERLAY")
        hint:SetPoint("LEFT", rowFont, "LEFT", 410, 0)
        hint:SetText("Text size throughout GuildHub, 9–15 (applies immediately)")
        hint:SetTextColor(
            S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
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

        local hint = S:FS(row1, "OVERLAY")
        hint:SetPoint("LEFT", row1, "LEFT", 410, 0)
        hint:SetText("Sets the format for all timestamps in GuildHub")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- 2 — Hide Default WoW Guild Window
    local row2 = MakeRow("Hide Default Guild Window", rowY)
    rowY = rowY - ROW_H
    do
        local btn = MakeToggle(row2, "hideDefaultGuildFrame", true)
        local origClick = btn:GetScript("OnClick")
        btn:SetScript("OnClick", function()
            origClick()
            if GH.DB:GetSetting("hideDefaultGuildFrame") ~= false then
                GH.ApplyGuildKeybindOverride()
            else
                GH.ReleaseGuildKeybindOverride()
            end
        end)
    end
    do
        local hint = S:FS(row2, "OVERLAY")
        hint:SetPoint("LEFT", row2, "LEFT", 410, 0)
        hint:SetText("Replace WoW's guild window with GuildHub")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- 3 — Show Offline Members
    local row3 = MakeRow("Show Offline Members", rowY)
    rowY = rowY - ROW_H
    MakeToggle(row3, "showOfflineMembers", true)
    do
        local hint = S:FS(row3, "OVERLAY")
        hint:SetPoint("LEFT", row3, "LEFT", 410, 0)
        hint:SetText("Display offline members in the roster list")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- Helper: integer spinner for a DB setting.
    -- Pass locked=true to grey out and disable controls (GM-only settings).
    local function MakeSpinner(row, settingKey, defaultVal, minVal, maxVal, hintText, locked)
        local display = S:FS(row, "OVERLAY", "normal")
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

        local hint = S:FS(row, "OVERLAY")
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
        local hint = S:FS(row6, "OVERLAY")
        hint:SetPoint("LEFT", row6, "LEFT", 410, 0)
        hint:SetText("Print debug output to chat (also: /gh debug on|off)")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- ── Section divider: Cross-Guild Federation ───────────────────────────────
    rowY = rowY - 8
    local fedDivLine = sc:CreateTexture(nil, "ARTWORK")
    fedDivLine:SetHeight(1)
    fedDivLine:SetPoint("TOPLEFT",  sc, "TOPLEFT",  24, rowY)
    fedDivLine:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -24, rowY)
    fedDivLine:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
    rowY = rowY - 16

    local fedHdrFS = S:FS(sc, "OVERLAY", "normal")
    fedHdrFS:SetPoint("TOPLEFT", sc, "TOPLEFT", 24, rowY)
    fedHdrFS:SetText("Cross-Guild Federation")
    fedHdrFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    rowY = rowY - ROW_H + 4

    local fedOfficer = GH:IsOfficer()

    -- Helper: styled edit box matching the window's dark palette.
    local function MakeFedEditBox(row, initialText, enabled)
        local eb = CreateFrame("EditBox", nil, row)
        eb:SetSize(160, 24)
        eb:SetPoint("LEFT", row, "LEFT", 230, 0)
        eb:SetFontObject(S.FontNormal)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(64)
        eb:SetTextInsets(6, 6, 0, 0)
        eb:SetText(initialText or "")
        eb:SetEnabled(enabled)
        eb:SetAlpha(enabled and 1 or 0.4)
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetAllPoints()
        ebBg:SetColorTexture(0.03, 0.03, 0.08, 0.95)
        -- Hairline border using four 1-px textures.
        local function EdgeLine(pt, w, h)
            local t = eb:CreateTexture(nil, "BORDER")
            t:SetSize(w, h)
            t:SetPoint(pt)
            t:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.6)
        end
        EdgeLine("TOPLEFT",    160, 1)
        EdgeLine("BOTTOMLEFT", 160, 1)
        EdgeLine("TOPLEFT",    1, 24)
        EdgeLine("TOPRIGHT",   1, 24)
        eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
        eb:SetScript("OnEnterPressed",  function() eb:ClearFocus() end)
        return eb
    end

    -- F1 — Federation channel name
    local fRow1 = MakeRow("Federation Channel", rowY)
    rowY = rowY - ROW_H
    local chanEB = MakeFedEditBox(fRow1, GH.BNetChat:GetFederationChannelName(), fedOfficer)
    do
        local hint = S:FS(fRow1, "OVERLAY")
        hint:SetPoint("LEFT", fRow1, "LEFT", 410, 0)
        hint:SetText("Shared channel for relay to non-BNet confederation members")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- F2 — Federation channel password
    local fRow2 = MakeRow("Channel Password", rowY)
    rowY = rowY - ROW_H
    local pwEB = MakeFedEditBox(fRow2, GH.DB:GetSetting("federationPassword") or "", fedOfficer)
    do
        local hint = S:FS(fRow2, "OVERLAY")
        hint:SetPoint("LEFT", fRow2, "LEFT", 410, 0)
        hint:SetText("Leave blank for an open channel")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- F3 — Apply button + live peer / channel status
    local fRow3 = MakeRow("", rowY)
    rowY = rowY - ROW_H

    local applyBtn = S:Button(fRow3, "Apply", 80, 26)
    applyBtn:SetPoint("LEFT", fRow3, "LEFT", 230, 0)
    if not fedOfficer then
        applyBtn:SetAlpha(0.35)
        applyBtn:Disable()
    end

    local fedStatusFS = S:FS(fRow3, "OVERLAY")
    fedStatusFS:SetPoint("LEFT", applyBtn, "RIGHT", 10, 0)
    fedStatusFS:SetWidth(270)
    fedStatusFS:SetJustifyH("LEFT")
    fedStatusFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    local function RefreshFedStatus(flashMsg)
        if flashMsg then
            fedStatusFS:SetText("|cff22cc44" .. flashMsg .. "|r")
            return
        end
        local peers = GH.BNetChat:GetPeerCount()
        local chan  = GH.BNetChat:GetFederationChannelName()
        if peers > 0 then
            local s = peers == 1 and "peer" or "peers"
            fedStatusFS:SetText(peers .. " GuildHub " .. s .. " discovered"
                .. (chan ~= "" and "  ·  chan: " .. chan or ""))
        elseif chan ~= "" then
            fedStatusFS:SetText("Channel: |cffffffff" .. chan .. "|r  (no peers yet)")
        else
            fedStatusFS:SetText("No peers found — scan runs 20 s after login")
        end
    end
    RefreshFedStatus()

    if fedOfficer then
        applyBtn:SetScript("OnClick", function()
            local name = chanEB:GetText():match("^%s*(.-)%s*$") or ""
            local pwd  = pwEB:GetText():match("^%s*(.-)%s*$") or ""
            GH.BNetChat:SetFederationChannel(name, pwd)
            chanEB:SetText(name)
            pwEB:SetText(pwd)
            RefreshFedStatus(name ~= "" and "Applied." or "Cleared.")
            C_Timer.After(2, RefreshFedStatus)
        end)
    end

    -- ── Section divider: Roster Profiles ─────────────────────────────────────
    rowY = rowY - 8
    local rosterDivLine = sc:CreateTexture(nil, "ARTWORK")
    rosterDivLine:SetHeight(1)
    rosterDivLine:SetPoint("TOPLEFT",  sc, "TOPLEFT",  24, rowY)
    rosterDivLine:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -24, rowY)
    rosterDivLine:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
    rowY = rowY - 16

    local rosterHdrFS = S:FS(sc, "OVERLAY", "normal")
    rosterHdrFS:SetPoint("TOPLEFT", sc, "TOPLEFT", 24, rowY)
    rosterHdrFS:SetText("Roster Profiles")
    rosterHdrFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    rowY = rowY - ROW_H + 4

    -- Helper: dynamic sub-rows that show/hide based on master toggle
    local rosterSubRows = {}

    -- R1 — Master toggle
    local rRow1 = MakeRow("Enable Roster Profiles", rowY)
    rowY = rowY - ROW_H
    local masterToggle = MakeToggle(rRow1, "rosterProfilesEnabled", true)
    do
        local hint = S:FS(rRow1, "OVERLAY")
        hint:SetPoint("LEFT", rRow1, "LEFT", 410, 0)
        hint:SetText("Join dates, alt groups, activity log, ban list, export & macro tools")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- R2 — Show mouseover window
    local rRow2 = MakeRow("  Mouseover Window", rowY)
    rowY = rowY - ROW_H
    MakeToggle(rRow2, "rosterShowMouseover", true)
    do
        local hint = S:FS(rRow2, "OVERLAY")
        hint:SetPoint("LEFT", rRow2, "LEFT", 410, 0)
        hint:SetText("Show extended player details when hovering the guild roster")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end
    rosterSubRows[#rosterSubRows + 1] = rRow2

    -- R3 — Show birthday info
    local rRow3 = MakeRow("  Show Birthday Info", rowY)
    rowY = rowY - ROW_H
    MakeToggle(rRow3, "rosterShowBirthdays", true)
    do
        local hint = S:FS(rRow3, "OVERLAY")
        hint:SetPoint("LEFT", rRow3, "LEFT", 410, 0)
        hint:SetText("Display birthday field in profile panel and mouseover window")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end
    rosterSubRows[#rosterSubRows + 1] = rRow3

    -- R4 — Sync data
    local rRow4 = MakeRow("  Sync with Guild", rowY)
    rowY = rowY - ROW_H
    MakeToggle(rRow4, "rosterSyncEnabled", true)
    do
        local hint = S:FS(rRow4, "OVERLAY")
        hint:SetPoint("LEFT", rRow4, "LEFT", 410, 0)
        hint:SetText("Share profile data with other online GuildHub users")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end
    rosterSubRows[#rosterSubRows + 1] = rRow4

    -- R5 — Sync min rank (officer only)
    local rRow5 = MakeRow("  Min Rank to Push Syncs", rowY)
    rowY = rowY - ROW_H
    MakeSpinner(rRow5, "rosterSyncMinRank", 4, 0, 9,
        "Rank index ≤ this can broadcast profile edits to others",
        not GH:IsOfficer())
    rosterSubRows[#rosterSubRows + 1] = rRow5

    -- R6 — Auto tag join date
    local rRow6 = MakeRow("  Auto-Tag Join Date", rowY)
    rowY = rowY - ROW_H
    MakeToggle(rRow6, "rosterAutoJoinDate", false)
    do
        local hint = S:FS(rRow6, "OVERLAY")
        hint:SetPoint("LEFT", rRow6, "LEFT", 410, 0)
        hint:SetText("Append join date to a note field when a new member is detected")
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end
    rosterSubRows[#rosterSubRows + 1] = rRow6

    -- R7 — Join date note destination (only officer relevant)
    if GH:IsOfficer() then
        local rRow7 = MakeRow("  Join Date Target", rowY)
        rowY = rowY - ROW_H
        do
            local function GetTarget() return GH.DB:GetSetting("rosterJoinDateTarget") or "custom" end
            local TARGETS = { { k = "custom", l = "Custom Note" }, { k = "public", l = "Public Note" },
                               { k = "officer", l = "Officer Note" } }
            local tBtns = {}
            local tx = 230
            for _, td in ipairs(TARGETS) do
                local tb = S:Button(rRow7, td.l, 90, 22)
                tb:SetPoint("LEFT", rRow7, "LEFT", tx, 0)
                tx = tx + 96
                local captK = td.k
                tb:SetScript("OnClick", function()
                    GH.DB:SetSetting("rosterJoinDateTarget", captK)
                    for _, b in ipairs(tBtns) do
                        local isSel = GH.DB:GetSetting("rosterJoinDateTarget") == b._key
                        b.bg:SetColorTexture(
                            isSel and S.COLOR.ACCENT[1] or S.COLOR.PANEL[1],
                            isSel and S.COLOR.ACCENT[2] or S.COLOR.PANEL[2],
                            isSel and S.COLOR.ACCENT[3] or S.COLOR.PANEL[3], 0.9)
                    end
                end)
                tb._key = captK
                tBtns[#tBtns + 1] = tb
            end
            -- Initial state
            for _, b in ipairs(tBtns) do
                local isSel = GetTarget() == b._key
                b.bg:SetColorTexture(
                    isSel and S.COLOR.ACCENT[1] or S.COLOR.PANEL[1],
                    isSel and S.COLOR.ACCENT[2] or S.COLOR.PANEL[2],
                    isSel and S.COLOR.ACCENT[3] or S.COLOR.PANEL[3], 0.9)
            end
        end
        rosterSubRows[#rosterSubRows + 1] = rRow7
    end

    -- Show/hide sub-rows based on master toggle
    local function UpdateRosterSubRows()
        local enabled = GH.DB:GetSetting("rosterProfilesEnabled") ~= false
        for _, row in ipairs(rosterSubRows) do
            if enabled then row:Show() else row:Hide() end
        end
        -- Also update sidebar Activity nav button
        if win.navBtns and win.navBtns["Activity"] then
            win.navBtns["Activity"]:SetShown(enabled)
        end
    end
    UpdateRosterSubRows()

    local origMasterClick = masterToggle:GetScript("OnClick")
    masterToggle:SetScript("OnClick", function(self)
        origMasterClick(self)
        UpdateRosterSubRows()
    end)

    -- ── Shared helpers for new sections ──────────────────────────────────────
    local function AddDivider(label)
        rowY = rowY - 10
        local div = sc:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT",  sc, "TOPLEFT",  24, rowY)
        div:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -24, rowY)
        div:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
        rowY = rowY - 18
        local hdr = S:FS(sc, "OVERLAY", "normal")
        hdr:SetPoint("TOPLEFT", sc, "TOPLEFT", 24, rowY)
        hdr:SetText(label)
        hdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        rowY = rowY - ROW_H + 4
    end

    local function MakeHint(row, text)
        local hint = S:FS(row, "OVERLAY")
        hint:SetPoint("LEFT", row, "LEFT", 410, 0)
        hint:SetText(text)
        hint:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- Inline edit-box bound to a string DB setting
    local function MakeTextSetting(row, settingKey, defaultText, maxLen, w)
        local eb = CreateFrame("EditBox", nil, row)
        eb:SetSize(w or 130, 24)
        eb:SetPoint("LEFT", row, "LEFT", 230, 0)
        eb:SetFontObject(S.FontSmall)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(maxLen or 32)
        eb:SetTextInsets(6, 6, 0, 0)
        eb:SetText(GH.DB:GetSetting(settingKey) or defaultText or "")
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetAllPoints()
        ebBg:SetColorTexture(S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)
        local ebBd = eb:CreateTexture(nil, "BORDER")
        ebBd:SetAllPoints()
        ebBd:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
        ebBg:SetPoint("TOPLEFT",     1, -1)
        ebBg:SetPoint("BOTTOMRIGHT", -1, 1)
        eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", function()
            GH.DB:SetSetting(settingKey, eb:GetText():match("^%s*(.-)%s*$"))
        end)
        eb:SetScript("OnEnterPressed", function()
            GH.DB:SetSetting(settingKey, eb:GetText():match("^%s*(.-)%s*$"))
            eb:ClearFocus()
        end)
        return eb
    end

    -- ── Section: General ─────────────────────────────────────────────────────
    AddDivider("General")

    local gRow1 = MakeRow("Show at Login", rowY)
    rowY = rowY - ROW_H
    MakeToggle(gRow1, "showAtLogon", false)
    MakeHint(gRow1, "Open GuildHub automatically when you log in")

    local gRow2 = MakeRow("  Only if Log Has Changes", rowY)
    rowY = rowY - ROW_H
    MakeToggle(gRow2, "onlyShowIfLogChanges", false)
    MakeHint(gRow2, "Only auto-open when new activity was detected since last session")

    -- ── Section: Sync ────────────────────────────────────────────────────────
    AddDivider("Sync")

    local sRow1 = MakeRow("Auto-Trigger Delay", rowY)
    rowY = rowY - ROW_H
    MakeSpinner(sRow1, "syncAutoTriggerDelay", 60, 10, 300,
        "Seconds after login before requesting a full data sync from peers")

    local sRow2 = MakeRow("Restrict Incoming Only", rowY)
    rowY = rowY - ROW_H
    MakeToggle(sRow2, "syncRestrictIncoming", true)
    MakeHint(sRow2, "Apply rank restriction only to incoming data; always receive from anyone")

    local sRow3 = MakeRow("Ban List Sync Min Rank", rowY)
    rowY = rowY - ROW_H
    MakeSpinner(sRow3, "syncBanListMinRank", 4, 0, 9,
        "Rank index ≤ this can push ban list updates to peers")

    local sRow4 = MakeRow("Sync Custom Notes", rowY)
    rowY = rowY - ROW_H
    MakeToggle(sRow4, "syncCustomNotes", true)
    MakeHint(sRow4, "Include custom notes in the data shared with other GuildHub users")

    local sRow5 = MakeRow("Show Sync Messages", rowY)
    rowY = rowY - ROW_H
    MakeToggle(sRow5, "displaySyncMessages", false)
    MakeHint(sRow5, "Print a chat message whenever profile data is received from a peer")

    -- ── Section: Officer ─────────────────────────────────────────────────────
    AddDivider("Officer")

    local oRow1 = MakeRow("Auto Join Date", rowY)
    rowY = rowY - ROW_H
    MakeToggle(oRow1, "rosterAutoJoinDate", false)
    MakeHint(oRow1, "Automatically tag join date in a note when a new member is detected")

    local oRow2 = MakeRow("  Join Tag Text", rowY)
    rowY = rowY - ROW_H
    MakeTextSetting(oRow2, "joinTagText", "Joined:", 24, 130)
    MakeHint(oRow2, "Prefix inserted before the date — e.g. \"Joined:\" → \"Joined: May 15 '26\"")

    local oRow3 = MakeRow("  Rejoin Tag Text", rowY)
    rowY = rowY - ROW_H
    MakeTextSetting(oRow3, "rejoinTagText", "Rejoined:", 24, 130)
    MakeHint(oRow3, "Used instead of the join tag when a former member returns")

    local oRow4 = MakeRow("  Note Destination", rowY)
    rowY = rowY - ROW_H
    do
        local TARGETS = {
            { k = "custom",  l = "Custom Note"  },
            { k = "public",  l = "Public Note"  },
            { k = "officer", l = "Officer Note" },
        }
        local tBtns = {}
        local tx = 230
        local function GetTarget() return GH.DB:GetSetting("rosterJoinDateTarget") or "custom" end
        for _, td in ipairs(TARGETS) do
            local tb = S:Button(oRow4, td.l, 90, 22)
            tb:SetPoint("LEFT", oRow4, "LEFT", tx, 0)
            tx = tx + 96
            local captK = td.k
            tb:SetScript("OnClick", function()
                GH.DB:SetSetting("rosterJoinDateTarget", captK)
                for _, b in ipairs(tBtns) do
                    local sel = GH.DB:GetSetting("rosterJoinDateTarget") == b._key
                    b.bg:SetColorTexture(
                        sel and S.COLOR.ACCENT[1] or S.COLOR.PANEL[1],
                        sel and S.COLOR.ACCENT[2] or S.COLOR.PANEL[2],
                        sel and S.COLOR.ACCENT[3] or S.COLOR.PANEL[3], 0.9)
                end
            end)
            tb._key = captK
            tBtns[#tBtns + 1] = tb
        end
        for _, b in ipairs(tBtns) do
            local sel = GetTarget() == b._key
            b.bg:SetColorTexture(
                sel and S.COLOR.ACCENT[1] or S.COLOR.PANEL[1],
                sel and S.COLOR.ACCENT[2] or S.COLOR.PANEL[2],
                sel and S.COLOR.ACCENT[3] or S.COLOR.PANEL[3], 0.9)
        end
    end

    local oRow5 = MakeRow("Add Events to Calendar", rowY)
    rowY = rowY - ROW_H
    MakeToggle(oRow5, "addEventsToCalendar", false)
    MakeHint(oRow5, "Automatically queue birthdays and anniversaries to the in-game calendar")

    -- ── Section: Scan ────────────────────────────────────────────────────────
    AddDivider("Scan")

    local scRow1 = MakeRow("Scan Interval", rowY)
    rowY = rowY - ROW_H
    MakeSpinner(scRow1, "scanIntervalSecs", 30, 10, 300,
        "Seconds between automatic roster scans (0 = only on GUILD_ROSTER_UPDATE)")

    local scRow2 = MakeRow("Inactive Return (days)", rowY)
    rowY = rowY - ROW_H
    MakeSpinner(scRow2, "inactiveReturnDays", 14, 1, 90,
        "Report a player as 'returned' after being offline this many days")

    local scRow3 = MakeRow("Announce Events Ahead", rowY)
    rowY = rowY - ROW_H
    MakeSpinner(scRow3, "announceEventsDays", 14, 1, 60,
        "Days in advance to announce upcoming anniversaries and birthdays")

    local scRow4 = MakeRow("Announce Anniversaries", rowY)
    rowY = rowY - ROW_H
    MakeToggle(scRow4, "announceAnniversaries", true)
    MakeHint(scRow4, "Post a guild chat message when a member's join anniversary is upcoming")

    local scRow5 = MakeRow("Announce Birthdays", rowY)
    rowY = rowY - ROW_H
    MakeToggle(scRow5, "announceBirthdays", true)
    MakeHint(scRow5, "Post a guild chat message when a member's birthday is upcoming")

    local scRow6 = MakeRow("  Mains Only", rowY)
    rowY = rowY - ROW_H
    MakeToggle(scRow6, "onlyMainForBdayAnn", false)
    MakeHint(scRow6, "Only announce anniversaries and birthdays for characters marked as Main")

    local scRow7 = MakeRow("Announce at Login", rowY)
    rowY = rowY - ROW_H
    MakeToggle(scRow7, "announceLoginBirthday", true)
    MakeHint(scRow7, "Greet a guild member in chat when they log in on their birthday")

    local scRow8 = MakeRow("Report Level-Ups", rowY)
    rowY = rowY - ROW_H
    MakeToggle(scRow8, "reportLevelUps", true)
    MakeHint(scRow8, "Log level-up events in the Activity tab")

    local scRow9 = MakeRow("  Min Level to Report", rowY)
    rowY = rowY - ROW_H
    MakeSpinner(scRow9, "levelReportMin", 10, 1, 80,
        "Ignore level-ups below this level (reduces noise for low-level alts)")

    sc:SetHeight(math.abs(rowY) + 20)

    win.settingsPage = page
    page:Hide()
end

-- ── Guild News refresh ────────────────────────────────────────────────────

function UI:RefreshGuildNews()
    local win = self.window
    if not win or not win.newsRows then return end
    local rows    = win.newsRows
    local emptyFS = win.newsEmptyFS

    for _, row in ipairs(rows) do
        row:Hide()
        row._rawLink = nil; row._tooltipName = nil; row._tooltipDesc = nil
    end

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
                    -- Build raw hyperlink for the tooltip
                    local rawLink
                    if isAchiev and id1 and id1 > 0 then
                        local ok4, link = pcall(GetAchievementLink, id1)
                        if ok4 then rawLink = link end
                    elseif not isAchiev then
                        local fn = rawget(_G, "GetGuildNewsItemLink")
                        if fn then
                            local ok4, link = pcall(fn, i)
                            if ok4 then rawLink = link end
                        end
                    end
                    row._rawLink     = rawLink
                    row._tooltipName = shortName
                    row._tooltipDesc = desc
                    shown[desc] = true
                    row:Show()
                    -- Persist to DB buffer so this survives reloads
                    GH.DB:AddNewsEntry({
                        name    = nameStr,
                        desc    = desc,
                        iconTex = iconTex,
                        rawLink = rawLink,
                    })
                end
            end
        end
    end

    -- ── Source 2: persistent buffer (achievements + saved WoW API news) ────────
    for _, entry in ipairs(win.newsBuffer or {}) do
        if rowIdx >= #rows then break end
        if not shown[entry.desc] then
            rowIdx = rowIdx + 1
            local row = rows[rowIdx]
            row.nameFS:SetText(entry.name or "")
            row.descFS:SetText(entry.desc or "")
            row.iconTex:SetTexture(entry.iconTex or "Interface/Icons/Achievement_General")
            row._rawLink     = entry.rawLink
            row._tooltipName = entry.name
            row._tooltipDesc = entry.desc
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
