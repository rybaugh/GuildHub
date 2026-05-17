-- GuildHub - MacroTool
-- Macro tool for guild management: kick, promote, and demote actions with
-- saved per-tab rules, a live queue built by scanning the roster, batched
-- WoW macro generation (255-char limit), an ignore list, and hotkey binding.

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

-- ── Layout ───────────────────────────────────────────────────────────────────

local TOOL_W    = 1200
local TOOL_H    = 610
local TITLE_H   = 36
local LEFT_W    = 380
local MID_W     = 390
local RIGHT_W   = 400   -- TOOL_W - LEFT_W - MID_W - 30 padding
local QROW_H    = 22
local MACRO_CAP = 250   -- WoW macro character cap (255 minus safety margin)
local WOW_MACRO = "GH_Tool"

local TAB = { KICK = 1, PROMOTE = 2, DEMOTE = 3 }
local TAB_CMD   = { "/gkick", "/gpromote", "/gdemote" }
local TAB_LABEL = { "Kick",   "Promote",   "Demote"   }
local TAB_COL   = {           -- text colour for action label in queue
    { 1.0, 0.35, 0.35 },     -- kick  = red
    { 0.30, 1.0, 0.45 },     -- promote = green
    { 0.90, 0.75, 0.20 },    -- demote = gold
}

-- ── DB helpers ────────────────────────────────────────────────────────────────

local function GetMT()
    local sv = rawget(_G, "GuildHubDB")
    if not sv or not sv.settings then return nil end
    local s = sv.settings
    if not s.macroTool then
        s.macroTool = {
            kickRules    = {},
            promoteRules = {},
            demoteRules  = {},
            ignored      = {},
            hotKey       = "CTRL-SHIFT-K",
            disableLogSpam = false,
        }
    end
    local mt = s.macroTool
    mt.kickRules    = mt.kickRules    or {}
    mt.promoteRules = mt.promoteRules or {}
    mt.demoteRules  = mt.demoteRules  or {}
    mt.ignored      = mt.ignored      or {}
    mt.lastSeenMap  = mt.lastSeenMap  or {}
    return mt
end

local function TabRuleStore(tab)
    local mt = GetMT()
    if not mt then return {} end
    if tab == TAB.KICK    then return mt.kickRules    end
    if tab == TAB.PROMOTE then return mt.promoteRules end
    return mt.demoteRules
end

local function RuleCount(tab)
    local n = 0; for _ in pairs(TabRuleStore(tab)) do n = n + 1 end; return n
end

local function SaveRule(tab, rule, oldName)
    local mt = GetMT(); if not mt then return end
    local store = TabRuleStore(tab)
    if oldName and oldName ~= rule.name then store[oldName] = nil end
    store[rule.name] = rule
end

local function DeleteRule(tab, name)
    local mt = GetMT(); if not mt then return end
    TabRuleStore(tab)[name] = nil
end

local function IsIgnored(name)
    local mt = GetMT(); return mt and mt.ignored[name] ~= nil
end

local function SetIgnored(name, v)
    local mt = GetMT(); if mt then mt.ignored[name] = v and time() or nil end
end

local function IgnoredCount()
    local mt = GetMT(); if not mt then return 0 end
    local n = 0; for _ in pairs(mt.ignored) do n = n + 1 end; return n
end

-- ── Permissions ───────────────────────────────────────────────────────────────

local function PermKick()
    return CanGuildRemove  and CanGuildRemove()  or false
end
local function PermPromote()
    return CanGuildPromote and CanGuildPromote() or false
end
local function PermDemote()
    return CanGuildDemote  and CanGuildDemote()  or false
end

local function PermForTab(tab)
    if tab == TAB.KICK    then return PermKick()    end
    if tab == TAB.PROMOTE then return PermPromote() end
    return PermDemote()
end

-- ── Roster & queue ────────────────────────────────────────────────────────────

local function MyRankIndex()
    local _, _, r = GetGuildInfo("player"); return r or 0
end

local function GuildMemberList()
    local mt    = GetMT()
    local lsMap = mt and mt.lastSeenMap or {}
    local now   = time()
    local out, total = {}, GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, total do
        local name, _, rankIndex, level, _, _, _, _, online =
            GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^%-]+)") or name
            if online then lsMap[short] = now end
            out[#out + 1] = {
                name      = short,
                rankIndex = rankIndex or 0,
                level     = level     or 0,
                online    = online    or false,
                lastSeen  = lsMap[short],
            }
        end
    end
    return out
end

local function MemberMatchesRule(m, rule)
    if rule.ranks and not rule.ranks[m.rankIndex + 1] then return false end
    if rule.useInactivity and not rule.kickActive then
        if m.online then return false end
        if m.lastSeen then
            local daysSince = (time() - m.lastSeen) / 86400
            if daysSince < (rule.inactivityDays or 30) then return false end
        end
        -- No lastSeen recorded yet: member unseen since tracking began; treat as inactive
    end
    return true
end

local function BuildQueue(tab)
    local store   = TabRuleStore(tab)
    local members = GuildMemberList()
    local myName  = UnitName("player") or ""
    local myRank  = MyRankIndex()

    local enabled = {}
    for _, r in pairs(store) do
        if r.enabled then enabled[#enabled + 1] = r end
    end
    table.sort(enabled, function(a, b) return (a.idx or 0) < (b.idx or 0) end)

    local seen, queue = {}, {}
    for _, rule in ipairs(enabled) do
        for _, m in ipairs(members) do
            if not seen[m.name] and m.name ~= myName then
                local rankOk = (tab == TAB.PROMOTE) or (m.rankIndex > myRank)
                if rankOk and not IsIgnored(m.name) and MemberMatchesRule(m, rule) then
                    seen[m.name] = true
                    queue[#queue + 1] = { name = m.name }
                end
            end
        end
    end
    table.sort(queue, function(a, b) return a.name < b.name end)
    return queue
end

-- ── Batching & macro writing ──────────────────────────────────────────────────

local function SplitBatches(entries, tab)
    local cmd = TAB_CMD[tab]
    local batches, batch, len = {}, {}, 0
    for _, e in ipairs(entries) do
        local line = cmd .. " " .. e.name .. "\n"
        if len + #line > MACRO_CAP and #batch > 0 then
            batches[#batches + 1] = batch; batch, len = {}, 0
        end
        batch[#batch + 1] = e.name; len = len + #line
    end
    if #batch > 0 then batches[#batches + 1] = batch end
    return batches
end

local function WriteMacro(names, tab)
    local cmd, text = TAB_CMD[tab], ""
    for _, n in ipairs(names) do text = text .. cmd .. " " .. n .. "\n" end
    if text == "" then return "" end
    local idx = GetMacroIndexByName(WOW_MACRO)
    if idx and idx > 0 then
        EditMacro(idx, WOW_MACRO, nil, text)
    else
        CreateMacro(WOW_MACRO, "INV_Misc_Note_01", text, nil)
    end
    local hotKey = (GetMT() or {}).hotKey or ""
    if hotKey ~= "" then
        local mi = GetMacroIndexByName(WOW_MACRO)
        if mi and mi > 0 then
            SetBindingMacro(hotKey, mi)
            SaveBindings(GetCurrentBindingSet())
        end
    end
    return text
end

local function ClearMacro()
    local mt  = GetMT() or {}
    local placeholder = '/run print("|cff7289daGH Tool|r ready.")'
    local idx = GetMacroIndexByName(WOW_MACRO)
    if idx and idx > 0 then EditMacro(idx, WOW_MACRO, nil, placeholder) end
    if mt.hotKey and mt.hotKey ~= "" then
        SetBinding(mt.hotKey, nil)
        SaveBindings(GetCurrentBindingSet())
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ── Popup: Hotkey Editor ─────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildHotkeyEditor(parent, onChange)
    local pop = CreateFrame("Frame", nil, parent)
    pop:SetSize(400, 170)
    pop:SetPoint("CENTER")
    pop:SetFrameStrata("TOOLTIP")
    pop:EnableMouse(true)
    S:Bg(pop, 0.05, 0.05, 0.10, 0.98)
    S:Border(pop)
    pop:Hide()

    local title = S:FS(pop, "OVERLAY", "normal")
    title:SetPoint("TOP", pop, "TOP", 0, -14)
    title:SetText("Edit Hot Key")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local disp = S:FS(pop, "OVERLAY", "normal")
    disp:SetPoint("TOP", title, "BOTTOM", 0, -10)
    disp:SetWidth(260); disp:SetJustifyH("CENTER")
    disp:SetTextColor(0.2, 0.88, 1.0)
    pop.disp = disp

    local function CurrKey() return disp:GetText() or "" end
    local function SetKey(k)  disp:SetText(k or "") end

    local function MakeModBtn(lbl, x)
        local b = S:Button(pop, lbl, 72, 22)
        b:SetPoint("BOTTOM", pop, "BOTTOM", x, 46); return b
    end
    MakeModBtn("Shift",  -120):SetScript("OnClick", function()
        local k = CurrKey()
        if not k:find("SHIFT") then SetKey("SHIFT-" .. k) end
    end)
    MakeModBtn("Ctrl",  -40):SetScript("OnClick", function()
        local k = CurrKey()
        if not k:find("CTRL") then
            if k:find("SHIFT%-") then
                SetKey(k:gsub("SHIFT%-", "SHIFT-CTRL-"))
            else SetKey("CTRL-" .. k) end
        end
    end)
    MakeModBtn("Alt", 40):SetScript("OnClick", function()
        local k = CurrKey()
        if not k:find("ALT") then SetKey(k .. "ALT-") end
    end)

    local keyLabel = S:FS(pop, "OVERLAY")
    keyLabel:SetPoint("BOTTOM", pop, "BOTTOM", 130, 68)
    keyLabel:SetText("Final Key:")
    keyLabel:SetTextColor(0.2, 0.88, 1.0)

    local keyEB = S:EditBox(pop, 44, 22, 1)
    keyEB:SetPoint("LEFT", keyLabel, "RIGHT", 6, 0)
    keyEB:SetScript("OnTextChanged", function(self)
        local ch = string.upper(self:GetText() or "")
        if ch == "" then return end
        local base = CurrKey():match("^(.*%-)[^%-]*$") or ""
        SetKey(base .. ch)
        self:SetText("")
    end)

    local clearBtn   = S:DangerButton(pop, "Clear",   60, 22)
    local cancelBtn  = S:DangerButton(pop, "Cancel",  72, 22)
    local confirmBtn = S:Button(pop,       "Confirm", 80, 22)
    clearBtn:SetPoint("BOTTOMLEFT",  pop, "BOTTOMLEFT",  14, 14)
    cancelBtn:SetPoint("LEFT",  clearBtn, "RIGHT", 6, 0)
    confirmBtn:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -14, 14)

    clearBtn:SetScript("OnClick",  function() SetKey("") end)
    cancelBtn:SetScript("OnClick", function() pop:Hide() end)
    confirmBtn:SetScript("OnClick", function()
        local k = CurrKey()
        if k == "" or k:sub(-1) == "-" then
            print("|cff7289daGuildHub:|r Please finish building the hot key."); return
        end
        local mt = GetMT()
        if mt then mt.hotKey = k end
        pop:Hide()
        if onChange then onChange(k) end
    end)

    function pop:Open()
        SetKey((GetMT() or {}).hotKey or "")
        keyEB:SetText("")
        pop:Show()
    end
    return pop
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ── Popup: Ignore List ────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildIgnoreListPopup(parent, onRefresh)
    local pop = CreateFrame("Frame", nil, parent)
    pop:SetSize(370, 400)
    pop:SetPoint("CENTER")
    pop:SetFrameStrata("TOOLTIP")
    pop:EnableMouse(true)
    S:Bg(pop, 0.05, 0.05, 0.10, 0.98)
    S:Border(pop)
    pop:Hide()

    local title = S:FS(pop, "OVERLAY", "normal")
    title:SetPoint("TOP", pop, "TOP", 0, -14)
    title:SetText("Ignored Players")
    title:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local closeBtn = CreateFrame("Button", nil, pop, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", pop, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() pop:Hide() end)

    local note = S:FS(pop, "OVERLAY")
    note:SetPoint("TOP", title, "BOTTOM", 0, -4)
    note:SetText("Right-click a queued player to add them here.")
    note:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    local sf = CreateFrame("ScrollFrame", nil, pop, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     pop, "TOPLEFT",     12, -52)
    sf:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -28, 46)
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(320, 10)
    sf:SetScrollChild(sc)

    local pool = {}
    local function Repopulate()
        for _, r in ipairs(pool) do r:Hide() end
        local mt = GetMT() or {}
        local names = {}
        for n in pairs(mt.ignored) do names[#names + 1] = n end
        table.sort(names)
        for i, name in ipairs(names) do
            local row = pool[i]
            if not row then
                row = CreateFrame("Frame", nil, sc)
                row:SetHeight(22)
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(); row.bg = bg
                local fs = S:FS(row, "OVERLAY")
                fs:SetPoint("LEFT", row, "LEFT", 8, 0)
                fs:SetWidth(220); fs:SetJustifyH("LEFT"); row.fs = fs
                local rb = S:DangerButton(row, "Remove", 66, 16)
                rb:SetPoint("RIGHT", row, "RIGHT", -4, 0); row.rb = rb
                pool[i] = row
            end
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(i-1)*22)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(i-1)*22)
            row.bg:SetColorTexture(
                i%2==0 and S.COLOR.PANEL[1] or 0,
                i%2==0 and S.COLOR.PANEL[2] or 0,
                i%2==0 and S.COLOR.PANEL[3] or 0,
                i%2==0 and 0.3 or 0)
            row.fs:SetText(name)
            local cap = name
            row.rb:SetScript("OnClick", function()
                SetIgnored(cap, false); Repopulate()
                if onRefresh then onRefresh() end
            end)
            row:Show()
        end
        sc:SetHeight(math.max(#names * 22, 10))
    end

    local clearAll = S:DangerButton(pop, "Clear All", 100, 22)
    clearAll:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 14, 12)
    clearAll:SetScript("OnClick", function()
        local mt = GetMT()
        if mt then mt.ignored = {} end
        Repopulate()
        if onRefresh then onRefresh() end
    end)

    function pop:Open() Repopulate(); pop:Show() end
    return pop
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ── Popup: Rule Editor ────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildRuleEditor(parent, onSave)
    local pop = CreateFrame("Frame", nil, parent)
    pop:SetSize(430, 390)
    pop:SetPoint("CENTER")
    pop:SetFrameStrata("TOOLTIP")
    pop:EnableMouse(true)
    S:Bg(pop, 0.05, 0.05, 0.10, 0.98)
    S:Border(pop)
    pop:Hide()
    pop._tab = TAB.KICK

    local titleFS = S:FS(pop, "OVERLAY", "normal")
    titleFS:SetPoint("TOP", pop, "TOP", 0, -14)
    titleFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    pop.titleFS = titleFS

    local closeBtn = CreateFrame("Button", nil, pop, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", pop, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() pop:Hide() end)

    -- Name
    local nameLbl = S:FS(pop, "OVERLAY")
    nameLbl:SetPoint("TOPLEFT", pop, "TOPLEFT", 14, -42)
    nameLbl:SetText("Rule Name:")
    nameLbl:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local nameEB = S:EditBox(pop, 240, 22, 64)
    nameEB:SetPoint("LEFT", nameLbl, "RIGHT", 8, 0)
    pop.nameEB = nameEB

    -- Rank section
    local rankHdr = S:FS(pop, "OVERLAY")
    rankHdr:SetPoint("TOPLEFT", nameLbl, "BOTTOMLEFT", 0, -14)
    rankHdr:SetText("Apply to Ranks:")
    rankHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local allRanksBtn = CreateFrame("CheckButton", nil, pop, "UICheckButtonTemplate")
    allRanksBtn:SetSize(18, 18)
    allRanksBtn:SetPoint("LEFT", rankHdr, "RIGHT", 12, 0)
    local allRanksLbl = S:FS(pop, "OVERLAY")
    allRanksLbl:SetPoint("LEFT", allRanksBtn, "RIGHT", 2, 0)
    allRanksLbl:SetText("All Ranks")
    allRanksLbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])

    pop.rankChks = {}

    local function RebuildRankChks()
        for _, c in ipairs(pop.rankChks) do c.btn:Hide(); c.lbl:Hide() end
        pop.rankChks = {}
        local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        local cols = 3
        for i = 1, numRanks do
            -- GuildControlGetRankName(1) = GM (rankIndex 0),
            -- GuildControlGetRankName(N) = lowest. We display descending (GM first).
            local rankName = (GuildControlGetRankName and
                GuildControlGetRankName(i)) or ("Rank " .. i)
            local btn = CreateFrame("CheckButton", nil, pop, "UICheckButtonTemplate")
            btn:SetSize(16, 16)
            local lbl = S:FS(pop, "OVERLAY")
            lbl:SetText(rankName)
            lbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
            lbl:SetWidth(100)
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            if col == 0 then
                btn:SetPoint("TOPLEFT", rankHdr, "BOTTOMLEFT", 0, -10 - row * 22)
            else
                btn:SetPoint("LEFT", pop.rankChks[i - 1].btn, "RIGHT", 108, 0)
            end
            lbl:SetPoint("LEFT", btn, "RIGHT", 2, 0)
            -- rankIndex for this display position: GM=0, displayed first
            pop.rankChks[i] = { btn = btn, lbl = lbl, rankIndex = i - 1 }
        end
        -- Reposition inactivity section below rank checkboxes
        local rows = math.max(1, math.ceil((numRanks) / cols))
        local baseY = -10 - 14 - rows * 22 - 14  -- from rankHdr bottom
        pop.inactSection:ClearAllPoints()
        pop.inactSection:SetPoint("TOPLEFT", rankHdr, "BOTTOMLEFT", 0, baseY)
    end

    allRanksBtn:SetScript("OnClick", function(self)
        local v = self:GetChecked()
        for _, c in ipairs(pop.rankChks) do
            c.btn:SetChecked(v); c.btn:SetEnabled(not v)
        end
    end)

    -- Inactivity section (anchor updated dynamically)
    local inactSection = CreateFrame("Frame", nil, pop)
    inactSection:SetSize(380, 22)
    inactSection:SetPoint("TOPLEFT", rankHdr, "BOTTOMLEFT", 0, -90)
    pop.inactSection = inactSection

    local inactChk = CreateFrame("CheckButton", nil, pop, "UICheckButtonTemplate")
    inactChk:SetSize(18, 18)
    inactChk:SetPoint("LEFT", inactSection, "LEFT", 0, 0)
    local inactLbl = S:FS(pop, "OVERLAY")
    inactLbl:SetPoint("LEFT", inactChk, "RIGHT", 4, 0)
    inactLbl:SetText("Inactive for at least")
    inactLbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    local inactEB = S:EditBox(pop, 38, 20, 5)
    inactEB:SetPoint("LEFT", inactLbl, "RIGHT", 6, 0)
    inactEB:SetText("30")
    local inactDays = S:FS(pop, "OVERLAY")
    inactDays:SetPoint("LEFT", inactEB, "RIGHT", 6, 0)
    inactDays:SetText("days")
    inactDays:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    pop.inactChk = inactChk; pop.inactEB = inactEB

    -- Kick-even-if-active (kick tab only)
    local kickActChk = CreateFrame("CheckButton", nil, pop, "UICheckButtonTemplate")
    kickActChk:SetSize(18, 18)
    kickActChk:SetPoint("TOPLEFT", inactSection, "BOTTOMLEFT", 0, -8)
    local kickActLbl = S:FS(pop, "OVERLAY")
    kickActLbl:SetPoint("LEFT", kickActChk, "RIGHT", 4, 0)
    kickActLbl:SetText("Include online / recently active players")
    kickActLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    pop.kickActChk = kickActChk; pop.kickActLbl = kickActLbl

    -- Buttons
    local saveBtn   = S:Button(pop,      "Save Rule",  110, 24)
    local cancelBtn = S:DangerButton(pop, "Cancel",     90, 24)
    saveBtn:SetPoint("BOTTOMLEFT",  pop, "BOTTOMLEFT",  14, 14)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function() pop:Hide() end)

    saveBtn:SetScript("OnClick", function()
        local name = nameEB:GetText():match("^%s*(.-)%s*$")
        if name == "" then
            print("|cff7289daGuildHub:|r Rule must have a name."); return
        end
        local ranks = {}
        if allRanksBtn:GetChecked() then
            local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
            for i = 1, n do ranks[i] = true end
        else
            for _, c in ipairs(pop.rankChks) do
                ranks[c.rankIndex + 1] = c.btn:GetChecked() or false
            end
        end
        local rule = {
            name          = name,
            enabled       = true,
            ranks         = ranks,
            useInactivity = inactChk:GetChecked(),
            inactivityDays = tonumber(inactEB:GetText()) or 30,
            kickActive    = kickActChk:GetChecked(),
            idx           = (pop._existing and pop._existing.idx) or time(),
        }
        if onSave then onSave(pop._tab, rule, pop._origName) end
        pop:Hide()
    end)

    function pop:Open(tab, existing)
        pop._tab      = tab
        pop._existing = existing
        pop._origName = existing and existing.name or nil
        RebuildRankChks()
        titleFS:SetText(existing and "Edit Rule" or "Add Rule  [" .. TAB_LABEL[tab] .. "]")
        nameEB:SetText(existing and existing.name or "")
        allRanksBtn:SetChecked(false)
        for _, c in ipairs(pop.rankChks) do
            local v = existing and existing.ranks and existing.ranks[c.rankIndex + 1]
            c.btn:SetChecked(v or false); c.btn:SetEnabled(true)
        end
        inactChk:SetChecked(existing and existing.useInactivity or false)
        inactEB:SetText(tostring(existing and existing.inactivityDays or 30))
        kickActChk:SetChecked(existing and existing.kickActive or false)
        local isKick = (tab == TAB.KICK)
        kickActChk:SetShown(isKick); kickActLbl:SetShown(isKick)
        pop:Show()
    end
    return pop
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ── Context menu (right-click on rule rows) ───────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildContextMenu(parent)
    local menu = CreateFrame("Frame", nil, parent)
    menu:SetSize(130, 70)
    menu:SetFrameStrata("TOOLTIP")
    menu:EnableMouse(true)
    S:Bg(menu, 0.04, 0.04, 0.08, 0.97)
    S:Border(menu)
    menu:Hide()
    menu:SetScript("OnHide", function() menu._rule = nil; menu._tab = nil end)

    local function MenuItem(lbl, y, cb)
        local btn = CreateFrame("Button", nil, menu)
        btn:SetSize(118, 20)
        btn:SetPoint("TOP", menu, "TOP", 0, y)
        local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); btn.bg = bg
        bg:SetColorTexture(0,0,0,0)
        local fs = S:FS(btn, "OVERLAY")
        fs:SetAllPoints(); fs:SetText(lbl)
        fs:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
        btn:SetScript("OnEnter", function() bg:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.5) end)
        btn:SetScript("OnLeave", function() bg:SetColorTexture(0,0,0,0) end)
        btn:SetScript("OnClick", function() menu:Hide(); cb() end)
        return btn
    end

    menu.editBtn   = MenuItem("Edit",             -10, function() if menu.onEdit   then menu.onEdit()   end end)
    menu.toggleBtn = MenuItem("Disable",          -32, function() if menu.onToggle then menu.onToggle() end end)
    menu.deleteBtn = MenuItem("Delete",           -54, function() if menu.onDelete then menu.onDelete() end end)

    function menu:Open(x, y, rule, tab, callbacks)
        menu._rule = rule; menu._tab = tab
        menu.onEdit   = callbacks.edit
        menu.onToggle = callbacks.toggle
        menu.onDelete = callbacks.delete
        menu.toggleBtn:SetText(rule.enabled and "Disable" or "Enable")
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        menu:Show()
    end
    return menu
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ── Main frame builder ────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildMacroToolFrame()
    local t = CreateFrame("Frame", "GuildHubMacroDialog", UIParent)
    t:SetSize(TOOL_W, TOOL_H)
    t:SetPoint("CENTER")
    t:SetFrameStrata("DIALOG")
    t:SetMovable(true)
    t:SetClampedToScreen(true)
    t:EnableMouse(true)
    t:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    t:SetScript("OnMouseUp",   function(self) self:StopMovingOrSizing() end)
    S:GradientBg(t, "VERTICAL",
        S.COLOR.BG[1] + 0.01, S.COLOR.BG[2] + 0.008, S.COLOR.BG[3] + 0.018, 0.97,
        S.COLOR.BG[1],        S.COLOR.BG[2],          S.COLOR.BG[3],          0.97)
    S:Border(t)
    tinsert(UISpecialFrames, "GuildHubMacroDialog")

    t._tab       = TAB.KICK
    t._queue     = {}
    t._batches   = nil
    t._batchIdx  = 1
    t._queuePool = {}
    t._macroPool = {}

    -- ── Title bar ─────────────────────────────────────────────────────────────

    local titleBar = CreateFrame("Frame", nil, t)
    titleBar:SetPoint("TOPLEFT",  t, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", t, "TOPRIGHT")
    titleBar:SetHeight(TITLE_H)
    S:GradientBg(titleBar, "VERTICAL",
        S.COLOR.TITLE_TOP[1], S.COLOR.TITLE_TOP[2], S.COLOR.TITLE_TOP[3], 1,
        S.COLOR.TITLE_BOT[1], S.COLOR.TITLE_BOT[2], S.COLOR.TITLE_BOT[3], 1)

    -- Gold top accent stripe
    local macroAccent = t:CreateTexture(nil, "OVERLAY")
    macroAccent:SetPoint("TOPLEFT",  t, "TOPLEFT",  0, 0)
    macroAccent:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
    macroAccent:SetHeight(2)
    local _maOk = pcall(function()
        macroAccent:SetGradient("HORIZONTAL",
            CreateColor(S.COLOR.GOLD[1]*0.5, S.COLOR.GOLD[2]*0.5, S.COLOR.GOLD[3]*0.3, 0.6),
            CreateColor(S.COLOR.GOLD[1],     S.COLOR.GOLD[2],     S.COLOR.GOLD[3],     0.9))
    end)
    if not _maOk then
        macroAccent:SetColorTexture(S.COLOR.GOLD[1], S.COLOR.GOLD[2], S.COLOR.GOLD[3], 0.7)
    end

    -- Bottom separator under title bar
    local macroDivSep = titleBar:CreateTexture(nil, "ARTWORK")
    macroDivSep:SetPoint("BOTTOMLEFT",  titleBar, "BOTTOMLEFT")
    macroDivSep:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT")
    macroDivSep:SetHeight(1)
    macroDivSep:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.4)

    local titleFS = S:FS(titleBar, "OVERLAY", "large")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
    titleFS:SetText("Macro Tool")
    titleFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 2, 0)
    closeBtn:SetScript("OnClick", function() t:Hide() end)

    -- ── Column separators ─────────────────────────────────────────────────────

    local function VSep(x)
        local sep = t:CreateTexture(nil, "ARTWORK")
        sep:SetSize(1, TOOL_H - TITLE_H - 2)
        sep:SetPoint("TOPLEFT", t, "TOPLEFT", x, -TITLE_H - 1)
        sep:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.6)
    end
    VSep(LEFT_W)
    VSep(LEFT_W + MID_W)

    -- ═══════════════════════════════════════════════════════════════════════
    -- LEFT PANEL  (x=0 .. LEFT_W-1)  — Permissions + Rules
    -- ═══════════════════════════════════════════════════════════════════════

    local lx, ly = 10, -TITLE_H - 10

    -- Permissions header
    local permHdr = S:FS(t, "OVERLAY", "normal")
    permHdr:SetPoint("TOPLEFT", t, "TOPLEFT", lx + 90, ly)
    permHdr:SetText("Permissions")
    permHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local function PermLabel(text, y)
        local fs = S:FS(t, "OVERLAY")
        fs:SetPoint("TOPLEFT", t, "TOPLEFT", lx + 85, y)
        fs:SetText(text)
        return fs
    end
    t.permKickFS   = PermLabel("-Kick-",    ly - 18)
    t.permPromoFS  = PermLabel("-Promote-", ly - 36)
    t.permDemoteFS = PermLabel("-Demote-",  ly - 54)

    -- "Rules" section label
    local rulesHdr = S:FS(t, "OVERLAY", "normal")
    rulesHdr:SetPoint("TOPLEFT", t, "TOPLEFT", lx, ly - 78)
    rulesHdr:SetText("Rules")
    rulesHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    -- Tab buttons
    t.tabBtns = {}
    local tabY = ly - 100
    local tabW = 82
    local tabNames = { "Kick", "Promote", "Demote" }
    for i, name in ipairs(tabNames) do
        local btn = CreateFrame("Button", nil, t)
        btn:SetSize(tabW, 36)
        btn:SetPoint("TOPLEFT", t, "TOPLEFT", lx + (i-1)*(tabW+4), tabY)

        local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); btn.bg = bg
        bg:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.7)

        local count = S:FS(btn, "OVERLAY")
        count:SetPoint("TOP", btn, "TOP", 0, -4)
        count:SetText("0")
        count:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        btn.countFS = count

        local label = S:FS(btn, "OVERLAY")
        label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 4)
        label:SetText(name)
        btn.labelFS = label

        btn:SetScript("OnEnter", function(self)
            if t._tab ~= i then
                self.bg:SetColorTexture(S.COLOR.PANEL_HOVER[1], S.COLOR.PANEL_HOVER[2], S.COLOR.PANEL_HOVER[3], 0.9)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if t._tab ~= i then
                self.bg:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.7)
            end
        end)
        local tabIdx = i
        btn:SetScript("OnClick", function()
            t._tab     = tabIdx
            t._batches = nil
            t._batchIdx = 1
            t:Refresh()
        end)
        t.tabBtns[i] = btn
    end

    -- Rules scroll frame
    local rulesSF = CreateFrame("ScrollFrame", nil, t, "UIPanelScrollFrameTemplate")
    rulesSF:SetPoint("TOPLEFT",     t, "TOPLEFT",  lx,           tabY - 44)
    rulesSF:SetPoint("BOTTOMRIGHT", t, "BOTTOMLEFT", LEFT_W - 20, 52)
    local rulesSC = CreateFrame("Frame", nil, rulesSF)
    rulesSC:SetSize(LEFT_W - 42, 10)
    rulesSF:SetScrollChild(rulesSC)
    t.rulesContent = rulesSC
    t._rulePool    = {}

    -- Enable All checkbox
    local enableAllChk = CreateFrame("CheckButton", nil, t, "UICheckButtonTemplate")
    enableAllChk:SetSize(18, 18)
    enableAllChk:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", lx, 32)
    local enableAllLbl = S:FS(t, "OVERLAY")
    enableAllLbl:SetPoint("LEFT", enableAllChk, "RIGHT", 4, 0)
    enableAllLbl:SetText("Enable All")
    enableAllLbl:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    t.enableAllChk = enableAllChk

    -- Add Custom Rule button
    local addRuleBtn = S:Button(t, "Add Custom Rule", 155, 24)
    addRuleBtn:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", lx + 110, 30)
    t.addRuleBtn = addRuleBtn

    -- Sync button (bottom left)
    local syncBtn = S:Button(t, "Sync", 50, 26)
    syncBtn:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", lx, 6)
    syncBtn:SetScript("OnClick", function()
        print("|cff7289daGuildHub:|r Rule sync is a pending feature.")
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    -- MIDDLE PANEL  (x=LEFT_W .. LEFT_W+MID_W-1)  — Queued Actions
    -- ═══════════════════════════════════════════════════════════════════════

    local mx = LEFT_W + 10

    local queuedHdr = S:FS(t, "OVERLAY", "normal")
    queuedHdr:SetPoint("TOPLEFT", t, "TOPLEFT", mx, ly + 4)
    queuedHdr:SetText("Queued Actions")
    queuedHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local exportBtn = S:Button(t, "Export", 76, 24)
    exportBtn:SetPoint("TOPRIGHT", t, "TOPLEFT", LEFT_W + MID_W - 10, ly)
    exportBtn:SetScript("OnClick", function()
        local q = t._queue or {}
        if #q == 0 then
            print("|cff7289daGuildHub:|r No queued names to export."); return
        end
        local lines = {}
        for _, e in ipairs(q) do lines[#lines + 1] = e.name end
        if UI.ShowExportDialog then
            UI:ShowExportDialog(table.concat(lines, "\n"))
        else
            print(table.concat(lines, ", "))
        end
    end)

    local qNameHdr = S:FS(t, "OVERLAY")
    qNameHdr:SetPoint("TOPLEFT", t, "TOPLEFT", mx, ly - 20)
    qNameHdr:SetText("Name:")
    qNameHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local qActHdr = S:FS(t, "OVERLAY")
    qActHdr:SetPoint("LEFT", qNameHdr, "RIGHT", 140, 0)
    qActHdr:SetText("Action:")
    qActHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local queueSF = CreateFrame("ScrollFrame", nil, t, "UIPanelScrollFrameTemplate")
    queueSF:SetPoint("TOPLEFT",     t, "TOPLEFT",  mx,              ly - 38)
    queueSF:SetPoint("BOTTOMRIGHT", t, "TOPLEFT",  LEFT_W + MID_W - 20, 52)
    local queueSC = CreateFrame("Frame", nil, queueSF)
    queueSC:SetSize(MID_W - 40, 10)
    queueSF:SetScrollChild(queueSC)
    t.queueContent = queueSC

    -- Build Macro button (below queue)
    local buildBtn = S:Button(t, "Build Macro", 190, 26)
    buildBtn:SetPoint("BOTTOM", t, "TOPLEFT", LEFT_W + MID_W/2, 30)
    t.buildBtn = buildBtn

    -- "Players same rank or higher will not be shown" note
    local rankNote = S:FS(t, "OVERLAY")
    rankNote:SetPoint("BOTTOM", t, "TOPLEFT", LEFT_W + MID_W/2, 10)
    rankNote:SetText("Players the same rank or higher will not be shown.")
    rankNote:SetTextColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3])
    rankNote:SetWidth(MID_W - 20)
    rankNote:SetJustifyH("CENTER")

    -- Queue status
    local queueStatus = S:FS(t, "OVERLAY")
    queueStatus:SetPoint("BOTTOM", buildBtn, "TOP", 0, 4)
    queueStatus:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    t.queueStatus = queueStatus

    -- ═══════════════════════════════════════════════════════════════════════
    -- RIGHT PANEL  (x=LEFT_W+MID_W .. TOOL_W-1)  — Current Actions / Macro
    -- ═══════════════════════════════════════════════════════════════════════

    local rx = LEFT_W + MID_W + 10

    local curActHdr = S:FS(t, "OVERLAY", "normal")
    curActHdr:SetPoint("TOPLEFT", t, "TOPLEFT", rx, ly + 4)
    curActHdr:SetText("Current Actions")
    curActHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local mNameHdr = S:FS(t, "OVERLAY")
    mNameHdr:SetPoint("TOPLEFT", t, "TOPLEFT", rx, ly - 20)
    mNameHdr:SetText("Name:")
    mNameHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local mMacroHdr = S:FS(t, "OVERLAY")
    mMacroHdr:SetPoint("LEFT", mNameHdr, "RIGHT", 130, 0)
    mMacroHdr:SetText("Macro:")
    mMacroHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    -- Warning shown below column headers for promote/demote tabs only
    local limitNote = S:FS(t, "OVERLAY")
    limitNote:SetPoint("TOPLEFT", t, "TOPLEFT", rx, ly - 40)
    limitNote:SetText("Due to limitations with macros a player\ncan only move 1 rank at a time.")
    limitNote:SetTextColor(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3])
    limitNote:SetJustifyH("CENTER"); limitNote:SetWidth(RIGHT_W - 20)
    limitNote:SetSpacing(2)
    limitNote:Hide()
    t.limitNote = limitNote

    -- Current macro member scroll list (top shifted down to clear the warning note)
    local macroSF = CreateFrame("ScrollFrame", nil, t, "UIPanelScrollFrameTemplate")
    macroSF:SetPoint("TOPLEFT",     t, "TOPLEFT",  rx,             ly - 74)
    macroSF:SetPoint("BOTTOMRIGHT", t, "TOPRIGHT",  -16,           ly - 38 - 220)
    local macroSC = CreateFrame("Frame", nil, macroSF)
    macroSC:SetSize(RIGHT_W - 36, 10)
    macroSF:SetScrollChild(macroSC)
    t.macroContent = macroSC

    -- "Macro is currently empty" / build-status button
    local macroStatusBtn = S:Button(t, "Macro is currently empty", RIGHT_W - 30, 50)
    macroStatusBtn:SetPoint("TOPLEFT", t, "TOPLEFT", rx, ly - 38 - 230)
    macroStatusBtn:SetAlpha(0.5)
    macroStatusBtn:Disable()
    t.macroStatusBtn = macroStatusBtn

    -- Clear selection button
    local clearSelBtn = S:DangerButton(t, "Clear Selection", RIGHT_W - 30, 26)
    clearSelBtn:SetPoint("TOPLEFT", macroStatusBtn, "BOTTOMLEFT", 0, -8)
    clearSelBtn:SetScript("OnClick", function()
        t._batches  = nil
        t._batchIdx = 1
        ClearMacro()
        for _, row in ipairs(t._macroPool) do row:Hide() end
        t.macroContent:SetHeight(10)
        macroStatusBtn.label:SetText("Macro is currently empty")
        macroStatusBtn:Disable()
        macroStatusBtn:SetAlpha(0.5)
        t.buildBtn.label:SetText("Build Macro")
        t.buildBtn:Enable(); t.buildBtn:SetAlpha(1)
        t:Refresh()
    end)

    -- Stats
    local function StatRow(lbl, y)
        local lblFS = S:FS(t, "OVERLAY")
        lblFS:SetPoint("TOPLEFT", t, "TOPRIGHT", -(RIGHT_W - 10), y)
        lblFS:SetText(lbl)
        lblFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        local valFS = S:FS(t, "OVERLAY")
        valFS:SetPoint("LEFT", lblFS, "RIGHT", 4, 0)
        valFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
        return valFS
    end
    local statsY = -(TOOL_H - 200)
    t.totalQueuedVal = StatRow("Total Queued:",    statsY)
    t.ignoredVal     = StatRow("Actions Ignored:", statsY - 18)

    local viewIgnoreBtn = S:Button(t, "View Ignore List", 150, 24)
    viewIgnoreBtn:SetPoint("TOPLEFT", t, "TOPRIGHT", -(RIGHT_W - 10), statsY - 46)
    t.viewIgnoreBtn = viewIgnoreBtn

    -- Hotkey display
    t.hotKeyFS = S:FS(t, "OVERLAY")
    t.hotKeyFS:SetPoint("TOPLEFT", t, "TOPRIGHT", -(RIGHT_W - 10), statsY - 82)
    t.hotKeyFS:SetTextColor(0.2, 0.88, 1.0)

    local editHKBtn = S:Button(t, "Edit Hot Key", 120, 22)
    editHKBtn:SetPoint("TOPLEFT", t, "TOPRIGHT", -(RIGHT_W - 10), statsY - 106)
    t.editHKBtn = editHKBtn

    -- Restore defaults
    local restoreBtn = S:DangerButton(t, "Restore Defaults", 140, 24)
    restoreBtn:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -14, 6)
    restoreBtn:SetScript("OnClick", function()
        local mt = GetMT(); if not mt then return end
        mt.kickRules    = {}
        mt.promoteRules = {}
        mt.demoteRules  = {}
        mt._batches     = nil
        t._batches      = nil
        t._batchIdx     = 1
        ClearMacro()
        t:Refresh()
        print("|cff7289daGuildHub:|r Macro Tool rules reset.")
    end)

    -- Disable log spam checkbox
    local logSpamChk = CreateFrame("CheckButton", nil, t, "UICheckButtonTemplate")
    logSpamChk:SetSize(16, 16)
    logSpamChk:SetPoint("BOTTOMRIGHT", restoreBtn, "BOTTOMLEFT", -20, 3)
    local logSpamLbl = S:FS(t, "OVERLAY")
    logSpamLbl:SetPoint("RIGHT", logSpamChk, "LEFT", -2, 0)
    logSpamLbl:SetText("Disable chat log spam while using the Macro Tool")
    logSpamLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    logSpamChk:SetScript("OnClick", function(self)
        local mt = GetMT(); if mt then mt.disableLogSpam = self:GetChecked() end
    end)
    t.logSpamChk = logSpamChk

    -- ── Build popups ──────────────────────────────────────────────────────────

    local ctxMenu    = BuildContextMenu(t)
    local ruleEditor = BuildRuleEditor(t, function(tab, rule, oldName)
        SaveRule(tab, rule, oldName)
        t:Refresh()
    end)
    local ignorePop  = BuildIgnoreListPopup(t, function() t:Refresh() end)
    local hotKeyPop  = BuildHotkeyEditor(t, function(k)
        t.hotKeyFS:SetText("Hot Key: " .. k)
    end)

    viewIgnoreBtn:SetScript("OnClick", function() ignorePop:Open() end)
    editHKBtn:SetScript("OnClick",     function() hotKeyPop:Open() end)
    addRuleBtn:SetScript("OnClick",    function()
        if PermForTab(t._tab) then
            ruleEditor:Open(t._tab, nil)
        else
            print("|cff7289daGuildHub:|r You do not have permission for " ..
                TAB_LABEL[t._tab] .. " actions.")
        end
    end)

    -- Enable-all checkbox wires into rule store
    enableAllChk:SetScript("OnClick", function(self)
        local v = self:GetChecked()
        for _, rule in pairs(TabRuleStore(t._tab)) do
            rule.enabled = v
        end
        t:Refresh()
    end)

    -- Build Macro button logic
    buildBtn:SetScript("OnClick", function()
        local q = t._queue or {}
        if #q == 0 then return end
        if not t._batches or #t._batches == 0 then
            t._batches  = SplitBatches(q, t._tab)
            t._batchIdx = 1
        end
        local batch = t._batches[t._batchIdx]
        if not batch then return end

        WriteMacro(batch, t._tab)
        t._batchIdx = t._batchIdx + 1

        -- Update the current-actions macro list
        local sc = t.macroContent
        for _, row in ipairs(t._macroPool) do row:Hide() end
        local cmd = TAB_CMD[t._tab]
        for i, name in ipairs(batch) do
            local row = t._macroPool[i]
            if not row then
                row = CreateFrame("Frame", nil, sc)
                row:SetHeight(QROW_H)
                local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); row.bg = bg
                local nfs = S:FS(row, "OVERLAY")
                nfs:SetPoint("LEFT", row, "LEFT", 6, 0); nfs:SetWidth(130); nfs:SetJustifyH("LEFT"); row.nfs = nfs
                local mfs = S:FS(row, "OVERLAY")
                mfs:SetPoint("LEFT", nfs, "RIGHT", 6, 0); mfs:SetWidth(130); mfs:SetJustifyH("LEFT"); row.mfs = mfs
                mfs:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
                t._macroPool[i] = row
            end
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(i-1)*QROW_H)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(i-1)*QROW_H)
            row.bg:SetColorTexture(
                i%2==0 and S.COLOR.PANEL[1] or 0,
                i%2==0 and S.COLOR.PANEL[2] or 0,
                i%2==0 and S.COLOR.PANEL[3] or 0,
                i%2==0 and 0.3 or 0)
            row.nfs:SetText(name)
            row.mfs:SetText(cmd .. " " .. name)
            row:Show()
        end
        sc:SetHeight(math.max(#batch * QROW_H, 10))

        -- Update status button
        macroStatusBtn:Enable()
        macroStatusBtn:SetAlpha(1)
        local total = t._batches and #t._batches or 1
        if t._batchIdx <= (t._batches and #t._batches or 0) then
            macroStatusBtn.label:SetText(
                "Batch " .. (t._batchIdx - 1) .. "/" .. total ..
                " written — press hotkey, then click for next batch")
            buildBtn.label:SetText("Next Batch (" .. t._batchIdx .. "/" .. total .. ")")
        else
            macroStatusBtn.label:SetText("All batches done! (" .. total .. " total)")
            buildBtn.label:SetText("Done")
            buildBtn:Disable()
            buildBtn:SetAlpha(0.5)
        end

        -- Log
        local mt = GetMT() or {}
        if not mt.disableLogSpam then
            local total2 = t._batches and #t._batches or 1
            print("|cff7289daGuildHub:|r Macro '" .. WOW_MACRO .. "' written (" ..
                #batch .. " player" .. (#batch==1 and "" or "s") ..
                ", batch " .. (t._batchIdx-1) .. "/" .. total2 .. ").")
        end
    end)

    -- ── GUILD_ROSTER_UPDATE auto-refresh ──────────────────────────────────────

    local evFrame = CreateFrame("Frame")
    evFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
    evFrame:SetScript("OnEvent", function()
        if t:IsShown() then
            t._batches  = nil  -- recompute batches after roster change
            t._batchIdx = 1
            t:Refresh()
        end
    end)

    -- ── Refresh function ──────────────────────────────────────────────────────

    local function RefreshRulesList()
        local sc = t.rulesContent
        for _, row in ipairs(t._rulePool) do row:Hide() end

        local store = TabRuleStore(t._tab)
        local ruleList = {}
        for _, r in pairs(store) do ruleList[#ruleList + 1] = r end
        table.sort(ruleList, function(a, b) return (a.idx or 0) < (b.idx or 0) end)

        for i, rule in ipairs(ruleList) do
            local row = t._rulePool[i]
            if not row then
                row = CreateFrame("Frame", nil, sc)
                row:SetHeight(26)
                row:EnableMouse(true)
                local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); row.bg = bg
                local chk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                chk:SetSize(16, 16); chk:SetPoint("LEFT", row, "LEFT", 4, 0); row.chk = chk
                local fs = S:FS(row, "OVERLAY")
                fs:SetPoint("LEFT", chk, "RIGHT", 4, 0); fs:SetWidth(220); fs:SetJustifyH("LEFT"); row.fs = fs
                row:SetScript("OnMouseUp", function(self, btn)
                    if not self._rule then return end
                    if btn == "LeftButton" then
                        ruleEditor:Open(t._tab, self._rule)
                    elseif btn == "RightButton" then
                        local cx, cy = GetCursorPosition()
                        local s = UIParent:GetEffectiveScale()
                        ctxMenu:Open(cx/s, cy/s, self._rule, t._tab, {
                            edit = function()
                                ruleEditor:Open(t._tab, self._rule)
                            end,
                            toggle = function()
                                self._rule.enabled = not self._rule.enabled
                                t:Refresh()
                            end,
                            delete = function()
                                DeleteRule(t._tab, self._rule.name)
                                t:Refresh()
                            end,
                        })
                    end
                end)
                t._rulePool[i] = row
            end
            row._rule = rule
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(i-1)*26)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(i-1)*26)
            row.bg:SetColorTexture(
                i%2==0 and S.COLOR.PANEL[1] or 0,
                i%2==0 and S.COLOR.PANEL[2] or 0,
                i%2==0 and S.COLOR.PANEL[3] or 0,
                i%2==0 and 0.3 or 0)
            row.chk:SetChecked(rule.enabled)
            row.chk:SetScript("OnClick", function(self)
                rule.enabled = self:GetChecked(); t:Refresh()
            end)
            row.fs:SetText(rule.name)
            row.fs:SetTextColor(rule.enabled
                and S.COLOR.TEXT[1]  or S.COLOR.TEXT_DIM[1],
                rule.enabled
                and S.COLOR.TEXT[2]  or S.COLOR.TEXT_DIM[2],
                rule.enabled
                and S.COLOR.TEXT[3]  or S.COLOR.TEXT_DIM[3])
            row:Show()
        end
        sc:SetHeight(math.max(#ruleList * 26, 10))

        -- Update tab active state
        for i, btn in ipairs(t.tabBtns) do
            if i == t._tab then
                btn.bg:SetColorTexture(S.COLOR.NAV_ACTIVE[1], S.COLOR.NAV_ACTIVE[2], S.COLOR.NAV_ACTIVE[3], 1)
                btn.labelFS:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
            else
                btn.bg:SetColorTexture(S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.7)
                btn.labelFS:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
            end
            btn.countFS:SetText(RuleCount(i))
        end

        -- Enable-all checkbox state
        local allEnabled = true
        local anyRule    = false
        for _, r in pairs(store) do
            anyRule = true
            if not r.enabled then allEnabled = false; break end
        end
        enableAllChk:SetChecked(anyRule and allEnabled)
    end

    function t:Refresh()
        t.limitNote:SetShown(t._tab ~= TAB.KICK)

        -- Permissions
        local kOk, pOk, dOk = PermKick(), PermPromote(), PermDemote()
        local function PermColor(ok)
            return ok and 0.2 or 1, ok and 0.88 or 0.3, ok and 0.3 or 0.3
        end
        t.permKickFS:SetTextColor(PermColor(kOk))
        t.permPromoFS:SetTextColor(PermColor(pOk))
        t.permDemoteFS:SetTextColor(PermColor(dOk))

        -- Rebuild queue
        local tab = t._tab
        t._queue = BuildQueue(tab)

        -- Queue list
        local sc = t.queueContent
        for _, row in ipairs(t._queuePool) do row:Hide() end
        local q = t._queue
        for i, e in ipairs(q) do
            local row = t._queuePool[i]
            if not row then
                row = CreateFrame("Frame", nil, sc)
                row:SetHeight(QROW_H)
                row:EnableMouse(true)
                local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); row.bg = bg
                local nfs = S:FS(row, "OVERLAY")
                nfs:SetPoint("LEFT", row, "LEFT", 6, 0); nfs:SetWidth(190); nfs:SetJustifyH("LEFT"); row.nfs = nfs
                local afs = S:FS(row, "OVERLAY")
                afs:SetPoint("LEFT", nfs, "RIGHT", 8, 0); afs:SetWidth(90); afs:SetJustifyH("LEFT"); row.afs = afs
                row:SetScript("OnMouseUp", function(frame, btn)
                    if btn == "RightButton" and frame._name then
                        SetIgnored(frame._name, true)
                        t:Refresh()
                    end
                end)
                t._queuePool[i] = row
            end
            row._name = e.name
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(i-1)*QROW_H)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(i-1)*QROW_H)
            row.bg:SetColorTexture(
                i%2==0 and S.COLOR.PANEL[1] or 0,
                i%2==0 and S.COLOR.PANEL[2] or 0,
                i%2==0 and S.COLOR.PANEL[3] or 0,
                i%2==0 and 0.3 or 0)
            row.nfs:SetText(e.name)
            local col = TAB_COL[tab]
            row.afs:SetText(TAB_LABEL[tab])
            row.afs:SetTextColor(col[1], col[2], col[3])
            row:Show()
        end
        sc:SetHeight(math.max(#q * QROW_H, 10))

        -- Build/status button
        if #q == 0 then
            t.buildBtn.label:SetText("No Names to Add")
            t.buildBtn:Disable(); t.buildBtn:SetAlpha(0.5)
            t.queueStatus:SetText("No players match the active rules.")
        elseif not t._batches then
            t.buildBtn.label:SetText("Build Macro")
            t.buildBtn:Enable(); t.buildBtn:SetAlpha(1)
            t.queueStatus:SetText(#q .. " player" .. (#q==1 and "" or "s") .. " queued")
        end

        -- Stats
        t.totalQueuedVal:SetText(tostring(#q))
        t.ignoredVal:SetText(tostring(IgnoredCount()))

        -- Hotkey
        local mt = GetMT() or {}
        t.hotKeyFS:SetText("Hot Key: " .. (mt.hotKey or "None"))
        t.logSpamChk:SetChecked(mt.disableLogSpam or false)

        RefreshRulesList()
    end

    return t
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ── Public entry point ────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────

function UI:ShowMacroDialog()
    if not GH:IsOfficer() then
        print("|cff7289daGuildHub:|r Only officers can use the Macro Tool.")
        return
    end

    local t = rawget(_G, "GuildHubMacroDialog")
    if not t then
        t = BuildMacroToolFrame()
    end
    t:Show()
    t:Refresh()
end
