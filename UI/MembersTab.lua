-- GuildHub - Members Tab
-- Roster list with filter, sort, and member context actions.

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local CreateFrame        = _G.CreateFrame
local ChatFrame_OpenChat = rawget(_G, "ChatFrame_OpenChat")
local GameTooltip        = rawget(_G, "GameTooltip")

-- Column layout
local COLS = {
    { label = "Name",     x = 22,  w = 128 },
    { label = "Rank",     x = 155, w = 75  },
    { label = "Lvl",      x = 235, w = 40  },
    { label = "M+",       x = 280, w = 60  },
    { label = "Zone",     x = 345, w = 110 },
    { label = "Team",     x = 460, w = 70  },
    { label = "Note",     x = 535, w = 110 },
    { label = "Personal", x = 650, w = 108 },
}

local ROW_POOL    = {}
local activeRows  = {}
local currentFilter = ""

-- Column sort state
UI._memberSortCol = nil
UI._memberSortDir = "asc"

-- Currently selected member name (left-click to select, same click to deselect)
UI._selectedMemberName = nil

local SORT_MAP = {
    ["Name"]     = function(m) return m.name:lower() end,
    ["Rank"]     = function(m) return m.rankIndex or 999 end,
    ["Lvl"]      = function(m) return m.level or 0 end,
    ["M+"]       = function(m) return GH.DB:GetMemberScore(m.name) or 0 end,
    ["Zone"]     = function(m) return (m.zone or ""):lower() end,
    ["Team"]     = function(m)
        local team = GH.GuildData:GetMemberTeam(m.name)
        return team and team.name:lower() or "~"
    end,
    ["Note"]     = function(m) return (m.note or ""):lower() end,
    ["Personal"] = function(m)
        local note = GH.GuildData:GetPersonalNote(m.name) or ""
        return note:lower()
    end,
}

function UI:CreateMembersTab(parent, w)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.MembersTab = frame

    -- ── ROSTER PANEL ──────────────────────────────────────────────────────
    local rp = CreateFrame("Frame", nil, frame)
    rp:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, 0)
    rp:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.rosterPanel = rp

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, rp)
    toolbar:SetPoint("TOPLEFT",  rp, "TOPLEFT",  10, -6)
    toolbar:SetPoint("TOPRIGHT", rp, "TOPRIGHT", -10, -6)
    toolbar:SetHeight(30)

    local searchBox = S:EditBox(toolbar, 220, 26, 100)
    searchBox:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    local hint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    hint:SetTextColor(0.4, 0.4, 0.5)
    hint:SetText("Search…")
    searchBox:SetScript("OnEditFocusGained", function() hint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function()
        if searchBox:GetText() == "" then hint:Show() end
    end)
    searchBox:SetScript("OnTextChanged", function(eb)
        currentFilter = eb:GetText()
        UI:RefreshMembersTab()
    end)
    frame.searchBox = searchBox

    local refreshBtn = S:Button(toolbar, "Refresh", 80, 26)
    refreshBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    refreshBtn:SetScript("OnClick", function()
        GH.GuildData:Refresh()
        GH.GuildData:RequestScoresFromGuild()
    end)

    local countLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    countLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame.countLabel = countLabel

    -- Column headers
    local headerRow = CreateFrame("Frame", nil, rp)
    headerRow:SetPoint("TOPLEFT",  rp, "TOPLEFT",  10, -42)
    headerRow:SetPoint("TOPRIGHT", rp, "TOPRIGHT", -36, -42)
    headerRow:SetHeight(20)

    local headerBg = headerRow:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 1)

    frame.headerButtons = {}
    for i, col in ipairs(COLS) do
        local btn = CreateFrame("Button", nil, headerRow)
        btn:SetPoint("LEFT", headerRow, "LEFT", col.x, 0)
        btn:SetSize(col.w, 20)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", btn, "LEFT", 0, 0)
        lbl:SetWidth(col.w - 12)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(col.label)
        lbl:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        btn.label = lbl

        local indicator = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        indicator:SetPoint("LEFT", lbl, "RIGHT", 2, 0)
        indicator:SetWidth(12)
        indicator:SetHeight(14)
        indicator:SetJustifyH("CENTER")
        indicator:SetJustifyV("MIDDLE")
        indicator:SetText("")
        indicator:SetTextColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3])
        btn.indicator = indicator

        btn:SetScript("OnClick", function()
            if UI._memberSortCol == col.label then
                UI._memberSortDir = (UI._memberSortDir == "asc") and "desc" or "asc"
            else
                UI._memberSortCol = col.label
                UI._memberSortDir = "asc"
            end
            for _, b in ipairs(frame.headerButtons) do
                if b.indicator then
                    if UI._memberSortCol == b.colLabel then
                        b.indicator:SetText(UI._memberSortDir == "asc" and "^" or "v")
                    else
                        b.indicator:SetText("")
                    end
                end
            end
            UI:RefreshMembersTab()
        end)

        btn.colLabel = col.label
        frame.headerButtons[i] = btn
    end

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, rp, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     rp, "TOPLEFT",     10, -64)
    sf:SetPoint("BOTTOMRIGHT", rp, "BOTTOMRIGHT", -36, 10)

    local scrollBg = sf:CreateTexture(nil, "BACKGROUND", nil, -2)
    scrollBg:SetAllPoints()
    scrollBg:SetColorTexture(0, 0, 0, 0.2)

    local contentW = w - 10 - 36
    local scrollContent = CreateFrame("Frame", nil, sf)
    scrollContent:SetSize(contentW, 10)
    sf:SetScrollChild(scrollContent)
    frame.scrollContent = scrollContent

    UI:RefreshMembersTab()
end

-- ── Tooltip helpers ───────────────────────────────────────────────────────

local function GetMemberRealm(m)
    if m.fullName and m.fullName:find("-", 1, true) then
        return m.fullName:match("-(.+)$")
    end
    if UnitFullName then
        local _, r = UnitFullName("player")
        if r and r ~= "" then return r end
    end
    return ""
end

local function GetRaiderIOProfile(m)
    local rio = rawget(_G, "RaiderIO")
    if not (rio and type(rio.GetProfile) == "function") then return nil end
    local realm = GetMemberRealm(m)
    if not realm or realm == "" then return nil end
    local ok, profile = pcall(rio.GetProfile, m.name, realm)
    if ok and type(profile) == "table" then return profile end
    return nil
end

-- ── Row pool ─────────────────────────────────────────────────────────────

local function GetOrCreateRow(index, parent)
    local row = ROW_POOL[index]
    if row then return row end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(S.ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    row.rowBg = rowBg

    -- 3px class colour bar
    local classBar = row:CreateTexture(nil, "ARTWORK")
    classBar:SetSize(3, S.ROW_H - 6)
    classBar:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.classBar = classBar

    -- 8px status dot
    local dot = row:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.dot = dot

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", COLS[1].x, 0)
    nameText:SetWidth(COLS[1].w)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankText:SetPoint("LEFT", row, "LEFT", COLS[2].x, 0)
    rankText:SetWidth(COLS[2].w)
    rankText:SetJustifyH("LEFT")
    rankText:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    row.rankText = rankText

    local levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetPoint("LEFT", row, "LEFT", COLS[3].x, 0)
    levelText:SetWidth(COLS[3].w)
    levelText:SetJustifyH("LEFT")
    levelText:SetTextColor(0.8, 0.72, 0.5)
    row.levelText = levelText

    local scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scoreText:SetPoint("LEFT", row, "LEFT", COLS[4].x, 0)
    scoreText:SetWidth(COLS[4].w)
    scoreText:SetJustifyH("LEFT")
    row.scoreText = scoreText

    local zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneText:SetPoint("LEFT", row, "LEFT", COLS[5].x, 0)
    zoneText:SetWidth(COLS[5].w)
    zoneText:SetJustifyH("LEFT")
    row.zoneText = zoneText

    local teamBtn = CreateFrame("Button", nil, row)
    teamBtn:SetPoint("LEFT", row, "LEFT", COLS[6].x, 0)
    teamBtn:SetSize(COLS[6].w, S.ROW_H - 4)
    teamBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local teamText = teamBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    teamText:SetAllPoints()
    teamText:SetJustifyH("LEFT")
    row.teamBtn  = teamBtn
    row.teamText = teamText

    local noteText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteText:SetPoint("LEFT", row, "LEFT", COLS[7].x, 0)
    noteText:SetWidth(COLS[7].w)
    noteText:SetJustifyH("LEFT")
    noteText:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    row.noteText = noteText

    local personalBtn = CreateFrame("Button", nil, row)
    personalBtn:SetPoint("LEFT", row, "LEFT", COLS[8].x, 0)
    personalBtn:SetSize(COLS[8].w, S.ROW_H - 4)
    personalBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local personalText = personalBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    personalText:SetPoint("LEFT", personalBtn, "LEFT", 0, 0)
    personalText:SetWidth(COLS[8].w)
    personalText:SetJustifyH("LEFT")
    personalText:SetTextColor(0.65, 0.75, 0.9)
    row.personalBtn  = personalBtn
    row.personalText = personalText

    row:SetScript("OnEnter", function(self)
        self.rowBg:SetColorTexture(
            S.COLOR.PANEL_HOVER[1], S.COLOR.PANEL_HOVER[2], S.COLOR.PANEL_HOVER[3], 1)
        if not self.memberData then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        local m = self.memberData
        local cr, cg, cb = GH.GuildData:GetClassColor(m.classFileName)

        -- Name with realm in class colour
        GameTooltip:SetText(m.fullName or m.name, cr, cg, cb)

        -- Rank
        if m.rank and m.rank ~= "" then
            GameTooltip:AddLine(m.rank,
                S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        end

        -- Level + Class combined
        local levelParts = {}
        if m.level and m.level > 0 then levelParts[#levelParts + 1] = "Level " .. m.level end
        if m.class  and m.class  ~= "" then levelParts[#levelParts + 1] = m.class end
        if #levelParts > 0 then
            GameTooltip:AddLine(table.concat(levelParts, " "), cr * 0.85, cg * 0.85, cb * 0.85)
        end

        -- Status (only if not simply online)
        if not m.online then
            GameTooltip:AddLine("Offline",
                S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3])
        elseif m.status == 1 then
            GameTooltip:AddLine("Away", S.COLOR.AFK[1], S.COLOR.AFK[2], S.COLOR.AFK[3])
        elseif m.status == 2 then
            GameTooltip:AddLine("Busy", S.COLOR.DND[1], S.COLOR.DND[2], S.COLOR.DND[3])
        end

        -- Zone
        if m.zone and m.zone ~= "" then
            GameTooltip:AddLine(m.zone, 0.60, 0.80, 0.60)
        end

        -- Guild note as a [badge] in gold (mirrors the default guild window style)
        if m.note and m.note ~= "" then
            GameTooltip:AddLine("[" .. m.note .. "]",
                S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        end

        -- M+ score
        local score = GH.DB:GetMemberScore(m.name)
        local profile = GetRaiderIOProfile(m)
        local hasMPlusData = (score and score > 0) or profile

        if hasMPlusData then
            GameTooltip:AddLine(" ", 0, 0, 0)
        end

        if score and score > 0 then
            local sr, sg, sb
            if     score >= 3000 then sr, sg, sb = 1.0, 0.5, 0.0
            elseif score >= 2000 then sr, sg, sb = 0.6, 0.2, 0.9
            elseif score >= 1500 then sr, sg, sb = 0.0, 0.5, 1.0
            elseif score >= 750  then sr, sg, sb = 0.1, 0.9, 0.1
            else                      sr, sg, sb = 0.8, 0.8, 0.8
            end
            GameTooltip:AddDoubleLine(
                "Raider.IO M+ Score", tostring(score),
                0.70, 0.70, 0.70, sr, sg, sb)
        end

        if profile then
            local mkp = profile.mythicKeystoneProfile
            if mkp then
                local cur = mkp.mplusCurrent
                if cur then
                    -- Best timed run
                    local runs = cur.runs
                    if runs and type(runs) == "table" and #runs > 0 then
                        local best = runs[1]
                        for _, run in ipairs(runs) do
                            if (run.level or 0) > (best.level or 0) then best = run end
                        end
                        local dShort = best.dungeon and
                            (best.dungeon.shortName or best.dungeon.name) or ""
                        local kLevel = best.level or 0
                        if dShort ~= "" and kLevel > 0 then
                            local upgrades = (best.upgrades or 0) > 0
                                and (" +" .. best.upgrades) or ""
                            GameTooltip:AddDoubleLine(
                                "Best Run",
                                dShort .. " +" .. kLevel .. upgrades,
                                0.70, 0.70, 0.70, 0.90, 0.90, 0.90)
                        end
                    end
                    -- Timed run count
                    if type(cur.numKeysCompleted) == "number" and cur.numKeysCompleted > 0 then
                        GameTooltip:AddDoubleLine(
                            "Timed Runs", tostring(cur.numKeysCompleted),
                            0.70, 0.70, 0.70, 0.90, 0.90, 0.90)
                    end
                end
            end

            -- Raid progress
            local raidTbl = profile.raid
            if raidTbl and type(raidTbl) == "table" then
                local summary = type(raidTbl.summary) == "string" and raidTbl.summary
                if not summary then
                    local latestTier, latestData = 0, nil
                    for _, raidData in pairs(raidTbl) do
                        if type(raidData) == "table" and (raidData.tier or 0) > latestTier then
                            latestTier, latestData = raidData.tier, raidData
                        end
                    end
                    if latestData and type(latestData.summary) == "string" then
                        summary = latestData.summary
                    end
                end
                if summary and summary ~= "" then
                    GameTooltip:AddLine("Raid: " .. summary, 0.80, 0.70, 0.55)
                end
            end
        end

        -- Personal note
        local personal = GH.GuildData:GetPersonalNote(m.name)
        if personal and personal ~= "" then
            GameTooltip:AddLine(" ", 0, 0, 0)
            GameTooltip:AddLine("Note: " .. personal, 0.65, 0.75, 0.90)
        end

        GameTooltip:AddLine(" ", 0, 0, 0)
        GameTooltip:AddLine(
            "|cffaaaaaa[Left]|r Select  |cffaaaaaa[Shift+Left]|r Invite  " ..
            "|cffaaaaaa[Shift+Right]|r Whisper",
            0.6, 0.6, 0.6)
        GameTooltip:AddLine("|cffaaaaaa[Right]|r Actions menu", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        -- Restore the base background stored during RefreshMembersTab
        if self.baseR then
            self.rowBg:SetColorTexture(self.baseR, self.baseG, self.baseB, self.baseA)
        else
            self.rowBg:SetColorTexture(0, 0, 0, 0)
        end
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, btn)
        -- Any click on a row dismisses an open context menu first.
        if UI._contextMenu and UI._contextMenu:IsShown() then
            UI._contextMenu:Hide()
        end
        local m = self.memberData
        if not m then return end
        if btn == "LeftButton" then
            if IsShiftKeyDown() then
                local fn = rawget(_G, "InviteUnit")
                if fn then fn(m.fullName)
                elseif C_PartyInfo and C_PartyInfo.InviteUnit then
                    C_PartyInfo.InviteUnit(m.fullName)
                end
            else
                UI._selectedMemberName = (UI._selectedMemberName == m.name) and nil or m.name
                UI:RefreshMembersTab()
            end
        elseif btn == "RightButton" then
            if IsShiftKeyDown() then
                ChatFrame_OpenChat("/w " .. m.name .. " ")
            else
                UI:ShowMemberContextMenu(m)
            end
        end
    end)

    ROW_POOL[index] = row
    return row
end

-- ── Roster refresh ────────────────────────────────────────────────────────

function UI:RefreshMembersTab()
    local frame = self.MembersTab
    if not frame then return end

    local members = GH.GuildData:GetMembers(currentFilter)

    -- Honour "show offline" setting
    if GH.DB:GetSetting("showOfflineMembers") == false then
        local filtered = {}
        for _, m in ipairs(members) do
            if m.online then filtered[#filtered + 1] = m end
        end
        members = filtered
    end

    -- Copy so we don't mutate GuildData's cached table
    local sorted = {}
    for i, m in ipairs(members) do sorted[i] = m end
    members = sorted

    -- Apply column sort
    local sortCol = UI._memberSortCol
    if sortCol then
        local sortFn = SORT_MAP[sortCol]
        if sortFn then
            local dir = UI._memberSortDir or "asc"
            table.sort(members, function(a, b)
                local av, bv = sortFn(a), sortFn(b)
                if av == bv then
                    return a.name < b.name
                end
                if dir == "asc" then
                    return av < bv
                else
                    return av > bv
                end
            end)
        end
    else
        table.sort(members, function(a, b)
            if a.online ~= b.online then return a.online end
            return a.name < b.name
        end)
    end

    local content = frame.scrollContent

    for _, r in ipairs(activeRows) do r:Hide() end
    activeRows = {}

    local totalH = 0
    for i, member in ipairs(members) do
        local row = GetOrCreateRow(i, content)
        row:SetParent(content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * S.ROW_H)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT",  0, -(i - 1) * S.ROW_H)
        row:SetHeight(S.ROW_H)
        row:Show()

        local isSelected = (member.name == UI._selectedMemberName)
        if isSelected then
            row.rowBg:SetColorTexture(
                S.COLOR.ACCENT[1] * 0.22, S.COLOR.ACCENT[2] * 0.22, S.COLOR.ACCENT[3] * 0.45, 1)
            row.baseR, row.baseG, row.baseB, row.baseA =
                S.COLOR.ACCENT[1] * 0.22, S.COLOR.ACCENT[2] * 0.22, S.COLOR.ACCENT[3] * 0.45, 1
        elseif i % 2 == 0 then
            row.rowBg:SetColorTexture(
                S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.45)
            row.baseR, row.baseG, row.baseB, row.baseA =
                S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.45
        else
            row.rowBg:SetColorTexture(0, 0, 0, 0)
            row.baseR, row.baseG, row.baseB, row.baseA = 0, 0, 0, 0
        end

        local cr, cg, cb = GH.GuildData:GetClassColor(member.classFileName)
        row.classBar:SetColorTexture(cr, cg, cb, 1)

        if member.online then
            if member.status == 1 then
                row.dot:SetColorTexture(S.COLOR.AFK[1],    S.COLOR.AFK[2],    S.COLOR.AFK[3],    1)
            elseif member.status == 2 then
                row.dot:SetColorTexture(S.COLOR.DND[1],    S.COLOR.DND[2],    S.COLOR.DND[3],    1)
            else
                row.dot:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 1)
            end
        else
            row.dot:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 1)
        end

        if member.online then
            row.nameText:SetTextColor(cr, cg, cb)
        else
            row.nameText:SetTextColor(cr * 0.5, cg * 0.5, cb * 0.5)
        end
        row.nameText:SetText(member.name)

        row.rankText:SetText(member.rank or "")
        row.levelText:SetText(tostring(member.level or ""))

        -- M+ Score
        local score = GH.DB:GetMemberScore(member.name)
        if score and score > 0 then
            local sr, sg, sb
            if     score >= 3000 then sr,sg,sb = 1.0, 0.5, 0.0
            elseif score >= 2000 then sr,sg,sb = 0.6, 0.2, 0.9
            elseif score >= 1500 then sr,sg,sb = 0.0, 0.5, 1.0
            elseif score >= 750  then sr,sg,sb = 0.1, 0.9, 0.1
            else                      sr,sg,sb = 0.8, 0.8, 0.8
            end
            row.scoreText:SetText(tostring(score))
            row.scoreText:SetTextColor(sr, sg, sb)
        else
            row.scoreText:SetText("|cff444455—|r")
            row.scoreText:SetTextColor(1, 1, 1)
        end

        -- Zone
        if member.zone and member.zone ~= "" then
            if member.online then
                row.zoneText:SetTextColor(0.50, 0.75, 0.50)
            else
                row.zoneText:SetTextColor(
                    S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
            end
            row.zoneText:SetText(member.zone)
        else
            row.zoneText:SetText("")
        end

        -- Team
        local team = GH.GuildData:GetMemberTeam(member.name)
        if team then
            row.teamText:SetText(team.name)
            row.teamText:SetTextColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3])
        else
            row.teamText:SetText("|cff333344—|r")
            row.teamText:SetTextColor(1, 1, 1)
        end

        do
            local capturedMember = member
            row.teamBtn:SetScript("OnClick", function(_, btn)
                if btn == "RightButton" then
                    UI:ShowMemberContextMenu(capturedMember)
                elseif GH:CanManageTeams() then
                    UI:ShowTeamAssignDialog(capturedMember.name)
                end
            end)
            if GH:CanManageTeams() then
                row.teamBtn:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(row.teamBtn, "ANCHOR_TOP")
                    GameTooltip:SetText("Click to assign team", 1, 1, 1)
                    GameTooltip:Show()
                end)
                row.teamBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            else
                row.teamBtn:SetScript("OnEnter", nil)
                row.teamBtn:SetScript("OnLeave", nil)
            end
        end

        row.noteText:SetText(member.note or "")

        local personal     = GH.GuildData:GetPersonalNote(member.name)
        local capturedName = member.name
        if personal and personal ~= "" then
            row.personalText:SetText(personal)
        else
            row.personalText:SetText("|cff333355✎ Add note|r")
        end
        do
            local capturedMember = member
            row.personalBtn:SetScript("OnClick", function(_, btn)
                if btn == "RightButton" then
                    UI:ShowMemberContextMenu(capturedMember)
                else
                    UI:ShowPersonalNoteDialog(capturedName)
                end
            end)
        end
        row.personalBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row.personalBtn, "ANCHOR_TOP")
            GameTooltip:SetText("Your private note about " .. capturedName, 0.65, 0.75, 0.9)
            GameTooltip:AddLine("Left-click to edit  ·  Right-click for actions", 0.5, 0.5, 0.6)
            GameTooltip:Show()
        end)
        row.personalBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.memberData = member
        activeRows[#activeRows + 1] = row
        totalH = totalH + S.ROW_H
    end

    content:SetHeight(math.max(totalH, 10))

    if frame.countLabel then
        local on, total = GH.GuildData:GetOnlineCount()
        local showing   = #members
        frame.countLabel:SetText(
            "|cff22cc44" .. on .. " online|r  ·  " .. showing .. " / " .. total .. " members"
        )
    end
end

-- ── Dialogs ───────────────────────────────────────────────────────────────

function UI:ShowPersonalNoteDialog(targetName)
    local current = GH.GuildData:GetPersonalNote(targetName) or ""

    local dlg = rawget(_G, "GuildHubPersonalNoteDialog")
    if not dlg then
        dlg = CreateFrame("Frame", "GuildHubPersonalNoteDialog", UIParent)
        dlg:SetSize(380, 130)
        dlg:SetFrameStrata("DIALOG")
        S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)
    end
    dlg:SetPoint("CENTER")
    dlg:Show()

    for i = dlg:GetNumChildren(), 1, -1 do
        select(i, dlg:GetChildren()):Hide()
    end

    local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText("Private note about |cffffd700" .. targetName .. "|r")
    title:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    title:Show()

    local subLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subLabel:SetPoint("TOP", title, "BOTTOM", 0, -2)
    subLabel:SetText("Only visible to you — never shared")
    subLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    subLabel:Show()

    local eb = S:EditBox(dlg, 340, 26, 200)
    eb:SetPoint("TOP", subLabel, "BOTTOM", 0, -8)
    eb:SetText(current)
    eb:SetFocus()
    eb:Show()

    local okBtn = S:Button(dlg, "Save", 80, 26)
    okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 10)
    okBtn:Show()

    local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 10)
    cancelBtn:Show()

    local function Save()
        local note = eb:GetText():match("^%s*(.-)%s*$")
        GH.GuildData:SetPersonalNote(targetName, note)
        dlg:Hide()
        UI:RefreshMembersTab()
    end

    okBtn:SetScript("OnClick", Save)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    eb:SetScript("OnEnterPressed", function() Save() end)
end

function UI:ShowTeamAssignDialog(memberName)
    local groups = GH.Groups:GetAll()

    local dlg = CreateFrame("Frame", "GuildHubTeamAssignDialog", UIParent)
    dlg:SetSize(220, math.min(#groups * 36 + 70, 320))
    dlg:SetPoint("CENTER")
    dlg:SetFrameStrata("DIALOG")
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText("Assign " .. memberName .. " to:")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    if #groups == 0 then
        local none = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        none:SetPoint("CENTER", dlg, "CENTER", 0, 0)
        none:SetText("No team presets found.\nCreate one in the Teams tab.")
        none:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    else
        for i, g in ipairs(groups) do
            local btn = S:Button(dlg, g.name, 180, 28)
            btn:SetPoint("TOP", dlg, "TOP", 0, -(i * 34) - 16)
            local capturedId = g.id
            btn:SetScript("OnClick", function()
                GH.Groups:AddMember(capturedId, memberName)
                dlg:Hide()
                UI:RefreshMembersTab()
            end)
        end
    end

    local currentTeam = GH.GuildData:GetMemberTeam(memberName)
    if currentTeam then
        local removeBtn = S:DangerButton(dlg, "Remove from " .. currentTeam.name, 180, 26)
        removeBtn:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 36)
        removeBtn:SetScript("OnClick", function()
            GH.Groups:RemoveMember(currentTeam.id, memberName)
            dlg:Hide()
            UI:RefreshMembersTab()
        end)
    end

    local closeBtn = S:Button(dlg, "Cancel", 80, 26)
    closeBtn:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 8)
    closeBtn:SetScript("OnClick", function() dlg:Hide() end)
end

-- ── Member context menu ───────────────────────────────────────────────────

function UI:ShowMemberContextMenu(member)
    -- Dismiss any existing menu.
    if UI._contextMenu and UI._contextMenu:IsShown() then
        UI._contextMenu:Hide()
    end

    -- Build item list for this member.
    local items = {}
    local function item(label, fn, danger)
        items[#items + 1] = { label = label, fn = fn, danger = danger }
    end
    local function sep()
        items[#items + 1] = { separator = true }
    end

    item("Whisper", function()
        ChatFrame_OpenChat("/w " .. member.name .. " ")
    end)
    item("Invite to Group", function()
        local fn = rawget(_G, "InviteUnit")
        if fn then fn(member.fullName)
        elseif C_PartyInfo and C_PartyInfo.InviteUnit then
            C_PartyInfo.InviteUnit(member.fullName)
        end
    end)
    item("Edit Personal Note", function()
        UI:ShowPersonalNoteDialog(member.name)
    end)

    if GH:CanManageTeams() then
        sep()
        item("Assign Team", function()
            UI:ShowTeamAssignDialog(member.name)
        end)
    end

    if GH:IsOfficer() then
        sep()
        item("Promote", function()
            local fn = rawget(_G, "GuildPromote")
            if fn then fn(member.name)
            elseif C_GuildInfo and C_GuildInfo.Promote then C_GuildInfo.Promote(member.name)
            end
        end)
        item("Demote", function()
            local fn = rawget(_G, "GuildDemote")
            if fn then fn(member.name)
            elseif C_GuildInfo and C_GuildInfo.Demote then C_GuildInfo.Demote(member.name)
            end
        end)
        item("Kick from Guild", function()
            local fn = rawget(_G, "GuildUninvite")
            if fn then fn(member.name)
            elseif C_GuildInfo and C_GuildInfo.KickMember then C_GuildInfo.KickMember(member.name)
            end
        end, true)
    end

    -- Measure height.
    local ITEM_H = 26
    local SEP_H  = 7
    local MENU_W = 196
    local totalH = 28  -- title bar
    for _, it in ipairs(items) do
        totalH = totalH + (it.separator and SEP_H or ITEM_H)
    end
    totalH = totalH + 6  -- bottom padding

    local menu = CreateFrame("Frame", "GuildHubContextMenu", UIParent)
    menu:SetSize(MENU_W, totalH)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    S:Bg(menu, 0.06, 0.06, 0.10, 0.98)

    -- 1px accent top bar
    local topBar = menu:CreateTexture(nil, "ARTWORK")
    topBar:SetHeight(1)
    topBar:SetPoint("TOPLEFT", menu, "TOPLEFT")
    topBar:SetPoint("TOPRIGHT", menu, "TOPRIGHT")
    topBar:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 1)

    -- Member name title
    local cr, cg, cb = GH.GuildData:GetClassColor(member.classFileName)
    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -7)
    title:SetTextColor(cr, cg, cb)
    title:SetText(member.name)

    -- Items
    local yOff = -26
    for _, it in ipairs(items) do
        if it.separator then
            local line = menu:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT",  menu, "TOPLEFT",  8, yOff - 3)
            line:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -8, yOff - 3)
            line:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)
            yOff = yOff - SEP_H
        else
            local btn = CreateFrame("Button", nil, menu)
            btn:SetPoint("TOPLEFT",  menu, "TOPLEFT",  0, yOff)
            btn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, yOff)
            btn:SetHeight(ITEM_H)

            local hbg = btn:CreateTexture(nil, "BACKGROUND")
            hbg:SetAllPoints()
            hbg:SetColorTexture(0, 0, 0, 0)

            local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", btn, "LEFT", 12, 0)
            if it.danger then
                lbl:SetTextColor(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3])
            else
                lbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
            end
            lbl:SetText(it.label)

            local capturedFn    = it.fn
            local capturedDanger = it.danger
            btn:SetScript("OnClick", function()
                menu:Hide()
                capturedFn()
            end)
            btn:SetScript("OnEnter", function()
                if capturedDanger then
                    hbg:SetColorTexture(S.COLOR.RED[1] * 0.35, 0.04, 0.04, 1)
                else
                    hbg:SetColorTexture(
                        S.COLOR.PANEL_HOVER[1], S.COLOR.PANEL_HOVER[2], S.COLOR.PANEL_HOVER[3], 1)
                end
            end)
            btn:SetScript("OnLeave", function()
                hbg:SetColorTexture(0, 0, 0, 0)
            end)

            yOff = yOff - ITEM_H
        end
    end

    -- Position at the cursor.
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)

    menu:Show()
    UI._contextMenu = menu
end
