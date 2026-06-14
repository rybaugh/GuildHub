-- GuildHub - Members Tab
-- Roster list with filter, sort, and member context actions.

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local CreateFrame        = _G.CreateFrame
local ChatFrame_OpenChat = rawget(_G, "ChatFrame_OpenChat")
local GameTooltip        = rawget(_G, "GameTooltip")
local GetNumGuildMembers = rawget(_G, "GetNumGuildMembers")

-- Column layout
local COLS = {
    { label = "Name",     x = 22,  w = 128 },
    { label = "Rank",     x = 155, w = 75  },
    { label = "Lvl",      x = 235, w = 40  },
    { label = "M+",       x = 280, w = 60  },
    { label = "Zone",     x = 345, w = 90  },
    { label = "Offline",  x = 440, w = 55  },
    { label = "Team",     x = 500, w = 65  },
    { label = "Note",     x = 570, w = 100 },
    { label = "Personal", x = 675, w = 145 },
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
    ["M+"]       = function(m) return GH.DB:GetMemberScore(m.fullName) or 0 end,
    ["Zone"]     = function(m) return (m.zone or ""):lower() end,
    ["Offline"]  = function(m)
        if m.online then return -1 end
        return m.daysOffline or 0
    end,
    ["Team"]     = function(m)
        local teams = GH.GuildData:GetMemberTeams(m.fullName)
        return #teams > 0 and teams[1].name:lower() or "~"
    end,
    ["Note"]     = function(m) return (m.note or ""):lower() end,
    ["Personal"] = function(m)
        local note = GH.GuildData:GetPersonalNote(m.fullName) or ""
        return note:lower()
    end,
}

function UI:CreateMembersTab(parent)
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

    -- Create profile panel (slides in from right when a member row is clicked)
    UI:CreateProfilePanel(frame)

    local searchBox = S:EditBox(toolbar, 180, 26, 100)
    searchBox:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    local hint = S:FS(searchBox, "OVERLAY")
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

    local refreshBtn = S:Button(toolbar, "Refresh", 70, 26)
    refreshBtn:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    refreshBtn:SetScript("OnClick", function()
        GH.GuildData:Refresh()
        GH.GuildData:RequestScoresFromGuild()
    end)

    -- Export, Macro, and Ban List buttons (only shown when Roster Profiles is enabled)
    local exportBtn = S:Button(toolbar, "Export", 65, 26)
    exportBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 6, 0)
    exportBtn:SetScript("OnClick", function() UI:ShowExportDialog() end)
    frame.exportBtn = exportBtn

    local macroBtn = S:Button(toolbar, "Macro Tool", 85, 26)
    macroBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)
    macroBtn:SetScript("OnClick", function() UI:ShowMacroDialog() end)
    frame.macroBtn = macroBtn

    local banListBtn = S:DangerButton(toolbar, "Ban List", 72, 26)
    banListBtn:SetPoint("LEFT", macroBtn, "RIGHT", 4, 0)
    banListBtn:SetScript("OnClick", function() UI:ShowBanListDialog() end)
    frame.banListBtn = banListBtn

    local countLabel = S:FS(toolbar, "OVERLAY")
    countLabel:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    countLabel:SetJustifyH("RIGHT")
    frame.countLabel = countLabel

    local function UpdateProfileButtons()
        local enabled = GH.DB:GetSetting("rosterProfilesEnabled") ~= false
        local officer = GH:IsOfficer()
        exportBtn:SetShown(enabled)
        macroBtn:SetShown(enabled and officer)
        banListBtn:SetShown(enabled and officer)
    end
    UpdateProfileButtons()

    -- Column headers
    local headerRow = CreateFrame("Frame", nil, rp)
    headerRow:SetPoint("TOPLEFT",  rp, "TOPLEFT",  10, -42)
    headerRow:SetPoint("TOPRIGHT", rp, "TOPRIGHT", -36, -42)
    headerRow:SetHeight(20)
    headerRow:SetClipsChildren(true)  -- prevent column labels bleeding into the profile panel

    -- Header row: gradient from panel-header top to slightly darker base
    S:GradientBg(headerRow, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL_HDR_B[1], S.COLOR.PANEL_HDR_B[2], S.COLOR.PANEL_HDR_B[3], 1)

    -- Subtle gold rule beneath the header
    local headerRule = headerRow:CreateTexture(nil, "ARTWORK")
    headerRule:SetPoint("BOTTOMLEFT",  headerRow, "BOTTOMLEFT")
    headerRule:SetPoint("BOTTOMRIGHT", headerRow, "BOTTOMRIGHT")
    headerRule:SetHeight(1)
    headerRule:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.18)

    frame.headerButtons = {}
    for i, col in ipairs(COLS) do
        local btn = CreateFrame("Button", nil, headerRow)
        btn:SetPoint("LEFT", headerRow, "LEFT", col.x, 0)
        btn:SetSize(col.w, 20)

        local lbl = S:FS(btn, "OVERLAY")
        lbl:SetPoint("LEFT", btn, "LEFT", 0, 0)
        lbl:SetWidth(col.w - 12)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(col.label)
        lbl:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        btn.label = lbl

        local indicator = S:FS(btn, "OVERLAY", "normal")
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

    local scrollContent = CreateFrame("Frame", nil, sf)
    scrollContent:SetHeight(10)
    sf:SetScrollChild(scrollContent)
    frame.scrollContent = scrollContent

    -- Keep the scroll content exactly as wide as the visible scroll area.
    -- This ensures row backgrounds (anchored TOPLEFT→TOPRIGHT to scrollContent)
    -- always fill the full window width, even after a live resize.
    local function SyncScrollWidth()
        local sfW = sf:GetWidth()
        if sfW > 0 then scrollContent:SetWidth(sfW) end
    end
    sf:SetScript("OnSizeChanged", SyncScrollWidth)
    -- Defer one frame so WoW has committed the scroll frame's initial layout.
    C_Timer.After(0, SyncScrollWidth)

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

    -- 4px class colour bar — slightly thicker for bolder visual identity
    local classBar = row:CreateTexture(nil, "ARTWORK")
    classBar:SetSize(4, S.ROW_H - 4)
    classBar:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.classBar = classBar

    -- Subtle inner glow alongside the class bar (adds warmth)
    local classGlow = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    classGlow:SetSize(18, S.ROW_H)
    classGlow:SetPoint("LEFT", row, "LEFT", 0, 0)
    classGlow:SetColorTexture(0, 0, 0, 0)
    row.classGlow = classGlow

    -- 10px status dot (larger, more legible)
    local dot = row:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.dot = dot

    local nameText = S:FS(row, "OVERLAY", "normal")
    nameText:SetPoint("LEFT", row, "LEFT", COLS[1].x, 0)
    nameText:SetWidth(COLS[1].w)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local rankText = S:FS(row, "OVERLAY")
    rankText:SetPoint("LEFT", row, "LEFT", COLS[2].x, 0)
    rankText:SetWidth(COLS[2].w)
    rankText:SetJustifyH("LEFT")
    rankText:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    row.rankText = rankText

    local levelText = S:FS(row, "OVERLAY")
    levelText:SetPoint("LEFT", row, "LEFT", COLS[3].x, 0)
    levelText:SetWidth(COLS[3].w)
    levelText:SetJustifyH("LEFT")
    levelText:SetTextColor(0.8, 0.72, 0.5)
    row.levelText = levelText

    local scoreText = S:FS(row, "OVERLAY")
    scoreText:SetPoint("LEFT", row, "LEFT", COLS[4].x, 0)
    scoreText:SetWidth(COLS[4].w)
    scoreText:SetJustifyH("LEFT")
    row.scoreText = scoreText

    local zoneText = S:FS(row, "OVERLAY")
    zoneText:SetPoint("LEFT", row, "LEFT", COLS[5].x, 0)
    zoneText:SetWidth(COLS[5].w)
    zoneText:SetJustifyH("LEFT")
    row.zoneText = zoneText

    local offlineText = S:FS(row, "OVERLAY")
    offlineText:SetPoint("LEFT", row, "LEFT", COLS[6].x, 0)
    offlineText:SetWidth(COLS[6].w)
    offlineText:SetJustifyH("LEFT")
    row.offlineText = offlineText

    local teamBtn = CreateFrame("Button", nil, row)
    teamBtn:SetPoint("LEFT", row, "LEFT", COLS[7].x, 0)
    teamBtn:SetSize(COLS[7].w, S.ROW_H - 4)
    teamBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local teamText = S:FS(teamBtn, "OVERLAY")
    teamText:SetAllPoints()
    teamText:SetJustifyH("LEFT")
    row.teamBtn  = teamBtn
    row.teamText = teamText

    local noteText = S:FS(row, "OVERLAY")
    noteText:SetPoint("LEFT", row, "LEFT", COLS[8].x, 0)
    noteText:SetSize(COLS[8].w, S.ROW_H)
    noteText:SetJustifyH("LEFT")
    noteText:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    row.noteText = noteText

    local personalBtn = CreateFrame("Button", nil, row)
    personalBtn:SetPoint("TOPLEFT",    row, "TOPLEFT",    COLS[9].x,  2)
    personalBtn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", COLS[9].x, -2)
    personalBtn:SetWidth(COLS[9].w)
    personalBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local personalText = S:FS(personalBtn, "OVERLAY")
    personalText:SetPoint("TOPLEFT", personalBtn, "TOPLEFT", 0, -2)
    personalText:SetWidth(COLS[9].w)
    personalText:SetWordWrap(true)
    personalText:SetJustifyH("LEFT")
    personalText:SetJustifyV("TOP")
    personalText:SetTextColor(0.65, 0.75, 0.9)
    row.personalBtn  = personalBtn
    row.personalText = personalText

    row:SetScript("OnEnter", function(self)
        -- Tint hover with a very subtle wash of the member's class color
        local hm = self.memberData
        if hm then
            local hr, hg, hb = GH.GuildData:GetClassColor(hm.classFileName)
            self.rowBg:SetColorTexture(
                S.COLOR.PANEL_HOVER[1] + hr * 0.06,
                S.COLOR.PANEL_HOVER[2] + hg * 0.04,
                S.COLOR.PANEL_HOVER[3] + hb * 0.06, 1)
        else
            self.rowBg:SetColorTexture(
                S.COLOR.PANEL_HOVER[1], S.COLOR.PANEL_HOVER[2], S.COLOR.PANEL_HOVER[3], 1)
        end
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
            local offlineLabel = "Offline"
            if m.daysOffline then
                offlineLabel = offlineLabel .. "  ·  "
                    .. (m.daysOffline == 0 and "< 1 day"
                        or m.daysOffline == 1 and "1 day"
                        or m.daysOffline .. " days")
            end
            GameTooltip:AddLine(offlineLabel,
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
                local wasSelected = (UI._selectedMemberName == m.fullName)
                UI._selectedMemberName = wasSelected and nil or m.fullName
                UI:RefreshMembersTab()
                if wasSelected then
                    if UI.ProfilePanel then UI.ProfilePanel:Hide() end
                    if UI.MembersTab and UI.MembersTab.rosterPanel then
                        UI.MembersTab.rosterPanel:SetPoint(
                            "BOTTOMRIGHT", UI.MembersTab, "BOTTOMRIGHT", 0, 0)
                    end
                else
                    UI:ShowProfilePanel(m)
                end
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

    local yOffset = 0
    local totalH  = 0
    for i, member in ipairs(members) do
        local row = GetOrCreateRow(i, content)
        row:SetParent(content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOffset)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOffset)
        row:Show()

        local isSelected = (member.fullName == UI._selectedMemberName)
        if isSelected then
            -- Selected row: deep sapphire tint
            local sr, sg, sb = S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3]
            row.rowBg:SetColorTexture(sr * 0.24, sg * 0.24, sb * 0.50, 1)
            row.baseR, row.baseG, row.baseB, row.baseA = sr * 0.24, sg * 0.24, sb * 0.50, 1
        elseif i % 2 == 0 then
            -- Even rows: slightly elevated panel color for stripe effect
            row.rowBg:SetColorTexture(
                S.COLOR.PANEL_ALT[1], S.COLOR.PANEL_ALT[2], S.COLOR.PANEL_ALT[3], 0.55)
            row.baseR, row.baseG, row.baseB, row.baseA =
                S.COLOR.PANEL_ALT[1], S.COLOR.PANEL_ALT[2], S.COLOR.PANEL_ALT[3], 0.55
        else
            row.rowBg:SetColorTexture(0, 0, 0, 0)
            row.baseR, row.baseG, row.baseB, row.baseA = 0, 0, 0, 0
        end

        local cr, cg, cb = GH.GuildData:GetClassColor(member.classFileName)

        -- Class bar: full opacity for online members, dimmed for offline
        local barAlpha = member.online and 0.90 or 0.35
        row.classBar:SetColorTexture(cr, cg, cb, barAlpha)

        -- Class glow: very subtle inner highlight beside the bar
        if member.online and row.classGlow then
            row.classGlow:SetColorTexture(cr, cg, cb, 0.06)
        elseif row.classGlow then
            row.classGlow:SetColorTexture(0, 0, 0, 0)
        end

        -- Status dot
        if member.online then
            if member.status == 1 then
                row.dot:SetColorTexture(S.COLOR.AFK[1],    S.COLOR.AFK[2],    S.COLOR.AFK[3],    1)
            elseif member.status == 2 then
                row.dot:SetColorTexture(S.COLOR.DND[1],    S.COLOR.DND[2],    S.COLOR.DND[3],    1)
            else
                row.dot:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 1)
            end
        else
            row.dot:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.5)
        end

        if member.online then
            row.nameText:SetTextColor(cr, cg, cb)
        else
            -- Offline: more aggressively dimmed so the online members stand out
            row.nameText:SetTextColor(cr * 0.42, cg * 0.42, cb * 0.42)
        end
        row.nameText:SetText(member.name)

        row.rankText:SetText(member.rank or "")
        row.levelText:SetText(tostring(member.level or ""))

        -- M+ Score
        local score = GH.DB:GetMemberScore(member.fullName)
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

        -- Offline days
        if not member.online and member.daysOffline ~= nil then
            local d = member.daysOffline
            row.offlineText:SetText(d == 0 and "< 1d" or d .. "d")
            row.offlineText:SetTextColor(
                S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        else
            row.offlineText:SetText("")
        end

        -- Team (supports multiple teams)
        local teams = GH.GuildData:GetMemberTeams(member.fullName)
        if #teams > 0 then
            local label = teams[1].name
            if #teams > 1 then label = label .. " |cff888899+" .. (#teams - 1) .. "|r" end
            row.teamText:SetText(label)
            row.teamText:SetTextColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3])
        else
            row.teamText:SetText("|cff333344—|r")
            row.teamText:SetTextColor(1, 1, 1)
        end

        do
            local capturedMember = member
            local capturedTeams  = teams
            row.teamBtn:SetScript("OnClick", function(_, btn)
                if btn == "RightButton" then
                    UI:ShowMemberContextMenu(capturedMember)
                elseif GH:CanManageTeams() then
                    UI:ShowTeamAssignDialog(capturedMember.fullName)
                end
            end)
            row.teamBtn:SetScript("OnEnter", function()
                if #capturedTeams > 0 or GH:CanManageTeams() then
                    GameTooltip:SetOwner(row.teamBtn, "ANCHOR_TOP")
                    if #capturedTeams > 1 then
                        local names = {}
                        for _, t in ipairs(capturedTeams) do names[#names + 1] = t.name end
                        GameTooltip:SetText(table.concat(names, ", "), 1, 1, 1)
                        if GH:CanManageTeams() then
                            GameTooltip:AddLine("Click to manage teams", 0.5, 0.5, 0.6)
                        end
                    elseif GH:CanManageTeams() then
                        GameTooltip:SetText("Click to manage teams", 1, 1, 1)
                    end
                    GameTooltip:Show()
                end
            end)
            row.teamBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        -- Ban badge overlay (only when Roster Profiles enabled)
        if not row.banBadge then
            local badge = S:FS(row, "OVERLAY")
            badge:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            badge:SetTextColor(0.85, 0.2, 0.2)
            row.banBadge = badge
        end
        if GH.DB:GetSetting("rosterProfilesEnabled") ~= false and
           GH.Profiles:IsBanned(member.fullName) then
            row.banBadge:SetText("|cffcc2222⛔|r")
        else
            row.banBadge:SetText("")
        end

        row.noteText:SetText(member.note or "")

        local personal     = GH.GuildData:GetPersonalNote(member.fullName)
        local capturedName = member.fullName
        if personal and personal ~= "" then
            row.personalText:ClearAllPoints()
            row.personalText:SetPoint("TOPLEFT", row.personalBtn, "TOPLEFT", 0, -2)
            row.personalText:SetJustifyV("TOP")
            row.personalText:SetText(personal)
        else
            row.personalText:ClearAllPoints()
            row.personalText:SetPoint("LEFT", row.personalBtn, "LEFT", 0, 0)
            row.personalText:SetJustifyV("MIDDLE")
            row.personalText:SetHeight(S.ROW_H)
            row.personalText:SetText("|cff333344—|r")
        end

        local strH = row.personalText:GetStringHeight()
        local rowH = math.max(S.ROW_H, strH + 10)
        row:SetHeight(rowH)
        row.classBar:SetHeight(rowH - 4)
        if row.classGlow then row.classGlow:SetHeight(rowH) end
        yOffset = yOffset + rowH
        totalH  = totalH + rowH

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
    end

    content:SetHeight(math.max(totalH, 10))

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

        local title = S:FS(dlg, "OVERLAY", "normal")
        title:SetPoint("TOP", dlg, "TOP", 0, -12)
        title:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        dlg._title = title

        local subLabel = S:FS(dlg, "OVERLAY")
        subLabel:SetPoint("TOP", title, "BOTTOM", 0, -2)
        subLabel:SetText("Only visible to you — never shared")
        subLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

        local eb = S:EditBox(dlg, 340, 26, 200)
        eb:SetPoint("TOP", subLabel, "BOTTOM", 0, -8)
        dlg._eb = eb

        local okBtn = S:Button(dlg, "Save", 80, 26)
        okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 30, 10)
        dlg._okBtn = okBtn

        local cancelBtn = S:DangerButton(dlg, "Cancel", 80, 26)
        cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 10)
        cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
    end

    dlg._title:SetText("Private note about |cffffd700" .. targetName .. "|r")
    dlg._eb:SetText(current)
    dlg._eb:SetFocus()

    local function Save()
        local note = dlg._eb:GetText():match("^%s*(.-)%s*$")
        GH.GuildData:SetPersonalNote(targetName, note)
        dlg:Hide()
        UI:RefreshMembersTab()
        local pp = UI.ProfilePanel
        if pp and pp:IsShown() and pp.currentName == targetName and pp.personalNoteFS then
            pp.personalNoteFS:SetText(note ~= "" and note or "|cff888888No personal note|r")
        end
    end

    dlg._okBtn:SetScript("OnClick", Save)
    dlg._eb:SetScript("OnEnterPressed", function() Save() end)

    dlg:SetPoint("CENTER")
    dlg:Show()
end

function UI:ShowTeamAssignDialog(memberName)
    local groups       = GH.Groups:GetAll()
    local currentTeams = GH.GuildData:GetMemberTeams(memberName)
    local isOnTeam     = {}
    for _, t in ipairs(currentTeams) do isOnTeam[t.id] = true end

    local HEADER_H = 34
    local BTN_H    = 30
    local BTN_GAP  = 4
    local FOOTER_H = 8 + BTN_H + 8
    local teamsH   = math.max(1, #groups) * (BTN_H + BTN_GAP)
    local dlgH     = math.min(HEADER_H + teamsH + FOOTER_H, 420)

    local dlg = CreateFrame("Frame", nil, UIParent)
    dlg:SetSize(240, dlgH)
    dlg:SetPoint("CENTER")
    dlg:SetFrameStrata("DIALOG")
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.97)

    local accent = dlg:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("TOPRIGHT"); accent:SetHeight(2)
    accent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.80)

    local title = S:FS(dlg, "OVERLAY", "normal")
    title:SetPoint("TOP", dlg, "TOP", 0, -12)
    title:SetText("Manage Teams — " .. (memberName:match("^([^%-]+)") or memberName))
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     dlg, "TOPLEFT",     8,  -HEADER_H)
    sf:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -22, FOOTER_H)
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(196)
    sf:SetScrollChild(sc)

    if #groups == 0 then
        sc:SetHeight(50)
        local none = S:FS(sc, "OVERLAY")
        none:SetPoint("TOP", sc, "TOP", 0, -8)
        none:SetText("No team presets found.\nCreate one in the Teams tab.")
        none:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        none:SetJustifyH("CENTER")
    else
        for i, g in ipairs(groups) do
            local isOn       = isOnTeam[g.id]
            local label      = isOn and ("Remove from " .. g.name) or ("Add to " .. g.name)
            local btn        = isOn and S:DangerButton(sc, label, 196, BTN_H)
                                     or S:Button(sc, label, 196, BTN_H)
            btn:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(i - 1) * (BTN_H + BTN_GAP))
            btn:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(i - 1) * (BTN_H + BTN_GAP))
            local capturedId = g.id
            btn:SetScript("OnClick", function()
                if isOn then
                    GH.Groups:RemoveMember(capturedId, memberName)
                    local grp = GH.Groups:Get(capturedId)
                    if grp and grp.channelId then
                        GH.Chat:RemoveMember(grp.channelId, memberName)
                    end
                else
                    GH.Groups:AddMember(capturedId, memberName)
                end
                dlg:Hide()
                UI:RefreshMembersTab()
            end)
        end
        sc:SetHeight(#groups * (BTN_H + BTN_GAP))
    end

    local closeBtn = S:Button(dlg, "Close", 90, BTN_H)
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
        ChatFrame_OpenChat("/w " .. member.fullName .. " ")
    end)
    item("Invite to Group", function()
        local fn = rawget(_G, "InviteUnit")
        if fn then fn(member.fullName)
        elseif C_PartyInfo and C_PartyInfo.InviteUnit then
            C_PartyInfo.InviteUnit(member.fullName)
        end
    end)
    item("Edit Personal Note", function()
        UI:ShowPersonalNoteDialog(member.fullName)
    end)
    if GH:CanEditPublicNote() then
        item("Edit Guild Note", function()
            UI:ShowGuildNoteDialog(member)
        end)
    end

    -- Roster profile actions
    if GH.DB:GetSetting("rosterProfilesEnabled") ~= false then
        sep()
        if GH:IsOfficer() then
            item("Set as Main", function()
                GH.Profiles:SetMain(member.fullName)
            end)
            item("Add Alt…", function()
                UI:ShowAddAltDialog(member.fullName, member)
            end)
            if GH.Profiles:IsBanned(member.fullName) then
                item("Remove Ban", function()
                    GH.Profiles:UnbanPlayer(member.fullName)
                end)
            else
                item("Ban Player", function()
                    UI:ShowBanDialog(member.fullName, member)
                end, true)
            end
        end
    end

    if GH:CanManageTeams() then
        sep()
        item("Manage Teams", function()
            UI:ShowTeamAssignDialog(member.fullName)
        end)
    end

    local canPromote = GH:CanPromote()
    local canDemote  = GH:CanDemote()
    local canRemove  = GH:CanRemoveMember()
    if canPromote or canDemote or canRemove then
        sep()
        if canPromote then
            item("Promote", function()
                if C_GuildInfo and C_GuildInfo.Promote then C_GuildInfo.Promote(member.name) end
            end)
        end
        if canDemote then
            item("Demote", function()
                if C_GuildInfo and C_GuildInfo.Demote then C_GuildInfo.Demote(member.name) end
            end)
        end
        if canRemove then
            item("Kick from Guild", function()
                local fn = rawget(_G, "GuildUninvite")
                if fn then fn(member.name)
                elseif C_GuildInfo and C_GuildInfo.KickMember then C_GuildInfo.KickMember(member.name)
                end
            end, true)
        end
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
    local title = S:FS(menu, "OVERLAY", "normal")
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

            local lbl = S:FS(btn, "OVERLAY")
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
