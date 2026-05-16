-- GuildHub - MouseoverWindow
-- Enhanced floating window that appears when hovering over names in the
-- default WoW guild roster (CommunitiesFrame / GuildRosterContainer).
-- Shows join date, rank history, custom note, alts, birthday, and M+ score.
-- Click to lock the window; ESC or click-away to release.

local GH  = GuildHub
local S   = GH.Styles
local UI  = GH.UI

local WIN_W  = 280
local WIN_H  = 320  -- dynamically sized

local _win       = nil
local _locked    = false
local _lockName  = nil

-- ── Create the window ─────────────────────────────────────────────────────────

local function BuildWindow()
    local win = CreateFrame("Frame", "GuildHubMouseoverWindow", UIParent)
    win:SetSize(WIN_W, WIN_H)
    win:SetFrameStrata("TOOLTIP")
    win:SetFrameLevel(100)
    win:SetClampedToScreen(true)
    win:Hide()

    -- Background + border
    S:Bg(win, 0.04, 0.04, 0.08, 0.97)
    S:Border(win, S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.9)

    -- Accent bar at top
    local accent = win:CreateTexture(nil, "ARTWORK")
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT",  win, "TOPLEFT")
    accent:SetPoint("TOPRIGHT", win, "TOPRIGHT")
    accent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.80)

    -- Name header
    local nameFS = S:FS(win, "OVERLAY", "large")
    nameFS:SetPoint("TOPLEFT",  win, "TOPLEFT",  12, -12)
    nameFS:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -12)
    nameFS:SetJustifyH("LEFT")
    win.nameFS = nameFS

    -- Lock indicator
    local lockHint = S:FS(win, "OVERLAY")
    lockHint:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -8)
    lockHint:SetText("📌")
    lockHint:SetAlpha(0)
    win.lockHint = lockHint

    -- Divider below name
    local div = win:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  win, "TOPLEFT",  8, -34)
    div:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -34)
    div:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

    -- Scrollable content area
    local sf = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     win, "TOPLEFT",     6, -40)
    sf:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -22, 6)

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(WIN_W - 30)
    content:SetHeight(10)
    sf:SetScrollChild(content)
    win.content  = content
    win.scrollFrame = sf

    -- ESC closes/unlocks
    tinsert(UISpecialFrames, "GuildHubMouseoverWindow")

    win:SetScript("OnMouseDown", function()
        if _locked and _lockName then
            _locked   = false
            _lockName = nil
            win.lockHint:SetAlpha(0)
            win:Hide()
        else
            _locked   = true
            _lockName = win._currentName
            win.lockHint:SetAlpha(1)
        end
    end)

    _win = win
    return win
end

-- ── Populate ──────────────────────────────────────────────────────────────────

local function ClearContent(win)
    local content = win.content
    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end
    -- FontStrings aren't children; just hide the frame and recreate
end

local function AddLine(content, text, r, g, b, yRef)
    local fs = S:FS(content, "OVERLAY")
    fs:SetPoint("TOPLEFT",  content, "TOPLEFT",  6, yRef)
    fs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, yRef)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text)
    fs:SetTextColor(r or S.COLOR.TEXT[1], g or S.COLOR.TEXT[2], b or S.COLOR.TEXT[3])
    return fs
end

local function PopulateWindow(win, name)
    if not name then win:Hide(); return end
    if GH.DB:GetSetting("rosterProfilesEnabled") == false then return end
    if GH.DB:GetSetting("rosterShowMouseover") == false then return end

    local member  = GH.GuildData:FindMember(name)
    local profile = GH.Profiles:GetProfile(name)
    local cr, cg, cb = 1, 1, 1
    if member then cr, cg, cb = GH.GuildData:GetClassColor(member.classFileName) end

    win.nameFS:SetText(name)
    win.nameFS:SetTextColor(cr, cg, cb)
    win._currentName = name

    local content = win.content
    -- Hide all existing fontstrings by recreating content frame children pool
    for i = content:GetNumChildren(), 1, -1 do
        local child = select(i, content:GetChildren())
        child:Hide()
    end

    local y = 0

    local function Row(label, value, vr, vg, vb)
        if not value or value == "" then return end
        local fs = S:FS(content, "OVERLAY")
        fs:SetPoint("TOPLEFT",  content, "TOPLEFT",  4, y - 2)
        fs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, y - 2)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        local labelColor = string.format("|cff%02x%02x%02x%s:|r ",
            math.floor(S.COLOR.TEXT_GOLD[1]*255),
            math.floor(S.COLOR.TEXT_GOLD[2]*255),
            math.floor(S.COLOR.TEXT_GOLD[3]*255), label)
        fs:SetText(labelColor .. value)
        if vr then fs:SetTextColor(vr, vg or 1, vb or 1) end
        y = y - (fs:GetStringHeight() + 4)
    end

    local function Sep()
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT",  content, "TOPLEFT",  4, y - 3)
        line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, y - 3)
        line:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.4)
        y = y - 8
    end

    -- Rank + level
    if member then
        Row("Rank", member.rank)
        local lvlClass = ""
        if member.level and member.level > 0 then lvlClass = member.level end
        if member.class and member.class ~= "" then
            lvlClass = lvlClass .. (lvlClass ~= "" and "  " or "") .. member.class
        end
        Row("Level", tostring(lvlClass))
        if member.zone and member.zone ~= "" then
            Row("Zone", member.zone, 0.5, 0.85, 0.5)
        end
    end

    -- Status
    if member then
        if not member.online then
            Row("Status", "Offline", S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3])
        elseif member.status == 1 then
            Row("Status", "Away", S.COLOR.AFK[1], S.COLOR.AFK[2], S.COLOR.AFK[3])
        elseif member.status == 2 then
            Row("Status", "Busy", S.COLOR.DND[1], S.COLOR.DND[2], S.COLOR.DND[3])
        end
    end

    Sep()

    -- Join date
    if profile.joinDate then
        local verified = profile.joinDateVerified and "" or " (est.)"
        Row("Joined", GH.Profiles.FormatDate(profile.joinDate) .. verified)
    end

    -- Last promotion
    local hist = profile.rankHistory or {}
    if #hist > 1 then
        local last = hist[#hist]
        Row("Promoted", last.rankName .. " (" .. GH.Profiles.FormatDate(last.ts) .. ")")
    end

    -- Birthday
    if GH.DB:GetSetting("rosterShowBirthdays") ~= false and profile.birthday then
        local b = profile.birthday
        local months = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
        Row("Birthday", (months[b.month] or "?") .. " " .. b.day)
    end

    Sep()

    -- Alt group
    local group = GH.Profiles:GetAltGroup(name)
    if group then
        local main = group.main or "?"
        if main ~= name then
            Row("Main", "|cfff2c617" .. main .. "|r")
        else
            Row("Main", "|cfff2c617" .. main .. " (you)|r")
        end
        local altsStr = ""
        for _, alt in ipairs(group.alts or {}) do
            if alt ~= main and alt ~= name then
                altsStr = altsStr ~= "" and (altsStr .. ", " .. alt) or alt
            end
        end
        if altsStr ~= "" then Row("Alts", altsStr) end
    end

    -- M+ score
    local score = GH.DB:GetMemberScore(name)
    if score and score > 0 then
        local sr, sg, sb
        if score >= 3000 then sr,sg,sb = 1.0,0.5,0.0
        elseif score >= 2000 then sr,sg,sb = 0.6,0.2,0.9
        elseif score >= 1500 then sr,sg,sb = 0.0,0.5,1.0
        elseif score >= 750  then sr,sg,sb = 0.1,0.9,0.1
        else sr,sg,sb = 0.8,0.8,0.8 end
        Row("M+ Score", tostring(score), sr, sg, sb)
    end

    Sep()

    -- Custom note
    if profile.customNote and profile.customNote ~= "" then
        Row("Note", "\"" .. profile.customNote .. "\"",
            S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    end

    -- Ban indicator
    if profile.isBanned then
        local fs = S:FS(content, "OVERLAY", "normal")
        fs:SetPoint("TOPLEFT",  content, "TOPLEFT",  4, y - 4)
        fs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, y - 4)
        fs:SetText("|cffcc2222⚠ BANNED|r")
        fs:SetJustifyH("CENTER")
        y = y - 18
    end

    content:SetHeight(math.abs(y) + 10)

    -- Resize window to fit content
    local newH = math.min(math.abs(y) + 55, 400)
    win:SetHeight(newH)
end

-- ── Hook the default guild roster ────────────────────────────────────────────

local _hooked = false

local function HookRosterButtons()
    if _hooked then return end
    if GH.DB:GetSetting("rosterShowMouseover") == false then return end
    if GH.DB:GetSetting("rosterProfilesEnabled") == false then return end

    -- The default guild roster in Retail 12.x lives inside CommunitiesFrame
    local container = rawget(_G, "CommunitiesFrame")
    if not container then return end

    -- WoW populates GuildRosterContainerScrollFrameButton1..N
    -- We hook dynamically up to 100 buttons, re-hook on GUILD_ROSTER_UPDATE
    local found = 0
    for i = 1, 100 do
        local btn = rawget(_G, "GuildRosterContainerScrollFrameButton" .. i)
        if not btn then break end

        hooksecurefunc(btn, "SetMemberID", function(self, memberID)
            self:SetScript("OnEnter", function(self)
                if _locked then return end
                if not _win then BuildWindow() end
                local info = C_GuildInfo and C_GuildInfo.GetMemberInfo and
                             C_GuildInfo.GetMemberInfo(memberID)
                local memberName = info and info.name
                if not memberName then
                    -- Fallback: try reading the name fontstring
                    if self.Name then memberName = self.Name:GetText() end
                end
                if not memberName or memberName == "" then return end
                memberName = memberName:match("^([^%-]+)")

                PopulateWindow(_win, memberName)
                _win:ClearAllPoints()
                _win:SetPoint("TOPLEFT", self, "TOPRIGHT", 4, 0)
                _win:Show()
            end)
            self:SetScript("OnLeave", function()
                if not _locked then _win:Hide() end
            end)
        end)
        found = found + 1
    end

    if found > 0 then _hooked = true end
end

-- Try hooking after GUILD_ROSTER_UPDATE (guild frame may not be open at login)
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function()
    C_Timer.After(0.5, HookRosterButtons)
end)

-- ── Public API ────────────────────────────────────────────────────────────────

function UI:InitMouseoverWindow()
    if not _win then BuildWindow() end
end

-- Called by MembersTab when hovering over an in-GuildHub row (optional bonus)
function UI:ShowMouseover(memberData, anchor)
    if GH.DB:GetSetting("rosterProfilesEnabled") == false then return end
    if GH.DB:GetSetting("rosterShowMouseover") == false then return end
    if _locked then return end

    if not _win then BuildWindow() end
    PopulateWindow(_win, memberData.name)
    _win:ClearAllPoints()
    if anchor then
        _win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    else
        _win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    _win:Show()
end

function UI:HideMouseover()
    if _win and not _locked then _win:Hide() end
end
