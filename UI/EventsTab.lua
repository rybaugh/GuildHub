-- GuildHub - Events Tab

local GH = GuildHub
local S  = GH.Styles
local UI = GH.UI

local CreateFrame = _G.CreateFrame

local selectedEventId = nil

local function CanDeleteEvent(ev)
    if not ev then return false end
    local playerName = GH:GetPlayerName()
    if ev.author == playerName then return true end
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex and rankIndex <= 3 then return true end
    return false
end

function UI:CreateEventsTab(parent, w)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    UI.EventsTab = frame

    -- Left: event list
    local listPanel = CreateFrame("Frame", nil, frame)
    listPanel:SetPoint("TOPLEFT",    frame, "TOPLEFT",    10, -10)
    listPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    listPanel:SetWidth(220)
    S:GradientBg(listPanel, "VERTICAL",
        S.COLOR.PANEL_HDR_T[1], S.COLOR.PANEL_HDR_T[2], S.COLOR.PANEL_HDR_T[3], 1,
        S.COLOR.PANEL[1],       S.COLOR.PANEL[2],       S.COLOR.PANEL[3],       1)

    S:Header(listPanel, "  UPCOMING EVENTS"):SetPoint("TOPLEFT", listPanel, "TOPLEFT", 6, -8)

    local newEventBtn = S:Button(listPanel, "+ Schedule Event", 200, 26)
    newEventBtn:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 10, -26)
    newEventBtn:SetScript("OnClick", function()
        UI:ShowEventCreateDialog()
    end)

    local sf = CreateFrame("ScrollFrame", nil, listPanel)
    sf:SetPoint("TOPLEFT",     listPanel, "TOPLEFT",     4,  -58)
    sf:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -4, 4)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max,
            self:GetVerticalScroll() - delta * 40)))
    end)
    local listContent = CreateFrame("Frame", nil, sf)
    listContent:SetHeight(10)
    sf:SetScrollChild(listContent)

    local function SyncEventListWidth()
        local sfW = sf:GetWidth()
        if sfW > 0 then listContent:SetWidth(sfW) end
    end
    sf:SetScript("OnSizeChanged", SyncEventListWidth)
    C_Timer.After(0, SyncEventListWidth)

    frame.eventListContent = listContent

    -- Right: event detail
    local detailPanel = CreateFrame("Frame", nil, frame)
    detailPanel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     238, -10)
    detailPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    S:Bg(detailPanel, S.COLOR.PANEL[1], S.COLOR.PANEL[2], S.COLOR.PANEL[3], 0.3)
    frame.detailPanel = detailPanel

    local detailTitle = S:FS(detailPanel, "OVERLAY", "large")
    detailTitle:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 12, -14)
    detailTitle:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])
    detailTitle:SetWidth(w - 360)
    frame.detailTitle = detailTitle

    local detailDate = S:FS(detailPanel, "OVERLAY", "normal")
    detailDate:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -6)
    detailDate:SetTextColor(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3])
    frame.detailDate = detailDate

    local detailType = S:FS(detailPanel, "OVERLAY")
    detailType:SetPoint("TOPLEFT", detailDate, "BOTTOMLEFT", 0, -4)
    detailType:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame.detailType = detailType

    local detailAuthor = S:FS(detailPanel, "OVERLAY")
    detailAuthor:SetPoint("TOPLEFT", detailType, "BOTTOMLEFT", 0, -4)
    detailAuthor:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame.detailAuthor = detailAuthor

    local divLine = S:HLine(detailPanel, w - 260)
    divLine:SetPoint("TOPLEFT", detailAuthor, "BOTTOMLEFT", 0, -8)

    local detailDesc = S:FS(detailPanel, "OVERLAY")
    detailDesc:SetPoint("TOPLEFT",  detailPanel, "TOPLEFT",  12, -110)
    detailDesc:SetPoint("TOPRIGHT", detailPanel, "TOPRIGHT", -12, -110)
    detailDesc:SetJustifyH("LEFT")
    detailDesc:SetJustifyV("TOP")
    detailDesc:SetHeight(120)
    detailDesc:SetTextColor(S.COLOR.TEXT[1], S.COLOR.TEXT[2], S.COLOR.TEXT[3])
    detailDesc:SetWordWrap(true)
    frame.detailDesc = detailDesc

    -- RSVP buttons
    local rsvpLabel = S:FS(detailPanel, "OVERLAY")
    rsvpLabel:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 12, -240)
    rsvpLabel:SetText("RSVP:")
    rsvpLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame.rsvpLabel = rsvpLabel

    local yesBtn   = S:Button(detailPanel, "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:0|t Yes",   80, 26)
    local maybeBtn = S:Button(detailPanel, "|TInterface\\RAIDFRAME\\ReadyCheck-Waiting:0|t Maybe",  80, 26)
    local noBtn    = S:DangerButton(detailPanel, "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:0|t No", 80, 26)

    yesBtn:SetPoint("LEFT",   rsvpLabel, "RIGHT",   10, 0)
    maybeBtn:SetPoint("LEFT", yesBtn,    "RIGHT",    6, 0)
    noBtn:SetPoint("LEFT",    maybeBtn,  "RIGHT",    6, 0)

    yesBtn:SetScript("OnClick",   function() if selectedEventId then GH.Events:RSVP(selectedEventId, "yes")   UI:RefreshEventsTab() end end)
    maybeBtn:SetScript("OnClick", function() if selectedEventId then GH.Events:RSVP(selectedEventId, "maybe") UI:RefreshEventsTab() end end)
    noBtn:SetScript("OnClick",    function() if selectedEventId then GH.Events:RSVP(selectedEventId, "no")    UI:RefreshEventsTab() end end)

    frame.yesBtn   = yesBtn
    frame.maybeBtn = maybeBtn
    frame.noBtn    = noBtn

    -- Attendee list
    local attendeesLabel = S:FS(detailPanel, "OVERLAY")
    attendeesLabel:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 12, -300)
    attendeesLabel:SetText("Attendees:")
    attendeesLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    frame.attendeesLabel = attendeesLabel

    local attendeesList = S:FS(detailPanel, "OVERLAY")
    attendeesList:SetPoint("TOPLEFT", attendeesLabel, "BOTTOMLEFT", 0, -6)
    attendeesList:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", -12, 46)
    attendeesList:SetJustifyH("LEFT")
    attendeesList:SetJustifyV("TOP")
    attendeesList:SetWordWrap(true)
    frame.attendeesList = attendeesList

    -- Delete button (author only)
    local deleteBtn = S:DangerButton(detailPanel, "Delete Event", 110, 26)
    deleteBtn:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", -10, 10)
    deleteBtn:SetScript("OnClick", function()
        if not selectedEventId then return end
        local ev = GH.DB:GetEvents()[selectedEventId]
        if not CanDeleteEvent(ev) then return end
        GH.Events:Delete(selectedEventId)
        selectedEventId = nil
        UI:RefreshEventsTab()
    end)
    frame.deleteBtn = deleteBtn

    -- Placeholder
    local placeholder = S:FS(detailPanel, "OVERLAY", "normal")
    placeholder:SetAllPoints(detailPanel)
    placeholder:SetText("Select an event\nor schedule a new one.")
    placeholder:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    placeholder:SetJustifyH("CENTER")
    frame.evPlaceholder = placeholder

    -- Hide all detail UI until an event is selected
    for _, f in ipairs({ detailTitle, detailDate, detailType, detailAuthor,
                         detailDesc, rsvpLabel, yesBtn, maybeBtn, noBtn,
                         deleteBtn, divLine }) do
        f:Hide()
    end

    UI:RefreshEventsTab()
end

function UI:RefreshEventsTab()
    local frame = UI.EventsTab
    if not frame then return end
    if UI.window and UI.window:IsShown() then
        UI.window.RefreshBannerTicker()
    end

    local content = frame.eventListContent
    for i = content:GetNumChildren(), 1, -1 do
        local child = select(i, content:GetChildren())
        child:Hide()
    end

    local events = GH.Events:GetAll()
    local now    = GH:GetTimestamp()

    for i, ev in ipairs(events) do
        local btn = CreateFrame("Button", nil, content)
        btn:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * 54)
        btn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * 54)
        btn:SetHeight(52)
        btn:Show()

        local isPast     = (ev.date or 0) < now
        local isSelected = (ev.id == selectedEventId)

        S:Bg(btn,
            isSelected and S.COLOR.NAV_ACTIVE[1] or S.COLOR.PANEL[1],
            isSelected and S.COLOR.NAV_ACTIVE[2] or S.COLOR.PANEL[2],
            isSelected and S.COLOR.NAV_ACTIVE[3] or S.COLOR.PANEL[3],
            isSelected and 1 or (i % 2 == 0 and 0.5 or 0)
        )

        local typeColor = { 0.6, 0.8, 1.0 }  -- default blue
        if     ev.evType == "Raid"        then typeColor = { 0.9, 0.3, 0.3 }
        elseif ev.evType == "PvP"         then typeColor = { 0.9, 0.5, 0.1 }
        elseif ev.evType == "Competition" then typeColor = { 0.8, 0.7, 0.1 }
        elseif ev.evType == "Social"      then typeColor = { 0.3, 0.9, 0.5 }
        end

        local typeBar = btn:CreateTexture(nil, "ARTWORK")
        typeBar:SetSize(3, 44)
        typeBar:SetPoint("LEFT", btn, "LEFT", 0, 0)
        typeBar:SetColorTexture(typeColor[1], typeColor[2], typeColor[3], isPast and 0.3 or 1)

        local titleLabel = S:FS(btn, "OVERLAY", "normal")
        titleLabel:SetPoint("TOPLEFT", btn, "TOPLEFT", 10, -8)
        titleLabel:SetWidth(ev.repeatType and 160 or 185)
        titleLabel:SetJustifyH("LEFT")
        titleLabel:SetWordWrap(false)
        titleLabel:SetText(ev.title)
        titleLabel:SetTextColor(isPast and 0.45 or 1, isPast and 0.45 or 1, isPast and 0.45 or 1)

        -- Repeat badge (top-right of the row)
        if ev.repeatType then
            local repeatBadge = S:FS(btn, "OVERLAY")
            repeatBadge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -8)
            local badgeText = ev.repeatType == "weekly"   and "Weekly"
                           or ev.repeatType == "biweekly" and "Bi-Wkly"
                           or "Monthly"
            repeatBadge:SetText("|cff7289da" .. badgeText .. "|r")
        end

        local dateLabel = S:FS(btn, "OVERLAY")
        dateLabel:SetPoint("TOPLEFT", btn, "TOPLEFT", 10, -24)
        dateLabel:SetText(GH.Events:FormatDate(ev.date))
        dateLabel:SetTextColor(
            isPast and S.COLOR.TEXT_DIM[1] or S.COLOR.ACCENT[1],
            isPast and S.COLOR.TEXT_DIM[2] or S.COLOR.ACCENT[2],
            isPast and S.COLOR.TEXT_DIM[3] or S.COLOR.ACCENT[3]
        )

        local myRsvp = GH.Events:GetRSVP(ev.id)
        if myRsvp then
            local rsvpLabel = S:FS(btn, "OVERLAY")
            rsvpLabel:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 4)
            local rsvpColors = { yes = {0.2,0.9,0.3}, maybe = {0.9,0.7,0.1}, no = {0.9,0.3,0.3} }
            local rc = rsvpColors[myRsvp] or {0.5,0.5,0.5}
            local rsvpText = (myRsvp == "yes" and "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:0|t")
                or (myRsvp == "no" and "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:0|t")
                or "|TInterface\\RAIDFRAME\\ReadyCheck-Waiting:0|t"
            rsvpLabel:SetText(rsvpText)
            rsvpLabel:SetTextColor(rc[1], rc[2], rc[3])
        end

        local capturedId = ev.id
        btn:SetScript("OnClick", function()
            selectedEventId = capturedId
            UI:RefreshEventsTab()
            UI:ShowEventDetail(capturedId)
        end)
    end

    content:SetHeight(math.max(#events * 54, 10))

    if selectedEventId then
        UI:ShowEventDetail(selectedEventId)
    else
        UI:_HideEventDetail()
    end
end

local DETAIL_FIELDS = { "detailTitle","detailDate","detailType","detailAuthor",
                        "detailDesc","rsvpLabel","yesBtn","maybeBtn","noBtn",
                        "deleteBtn","attendeesLabel","attendeesList" }

function UI:_HideEventDetail()
    local frame = UI.EventsTab
    if not frame then return end
    frame.evPlaceholder:Show()
    for _, k in ipairs(DETAIL_FIELDS) do
        if frame[k] then frame[k]:Hide() end
    end
end

function UI:ShowEventDetail(eventId)
    local frame = UI.EventsTab
    if not frame then return end

    -- Raw DB record (for authorship / delete permission check).
    local rawEv = GH.DB:GetEvents()[eventId]
    if not rawEv then return end

    -- Computed record (has the rolled-forward date for repeating events).
    local ev
    for _, e in ipairs(GH.Events:GetAll()) do
        if e.id == eventId then ev = e; break end
    end
    if not ev then return end

    frame.evPlaceholder:Hide()
    for _, k in ipairs(DETAIL_FIELDS) do
        if frame[k] then frame[k]:Show() end
    end

    if CanDeleteEvent(rawEv) then
        frame.deleteBtn:Show()
    else
        frame.deleteBtn:Hide()
    end

    frame.detailTitle:SetText(ev.title)
    frame.detailDate:SetText(GH.Events:FormatDate(ev.date))

    local repeatLabel = ev.repeatType == "weekly"   and "  |cff7289da(Weekly)|r"
                     or ev.repeatType == "biweekly" and "  |cff7289da(Bi-Weekly)|r"
                     or ev.repeatType == "monthly"  and "  |cff7289da(Monthly)|r"
                     or ""
    frame.detailType:SetText("Type: " .. (ev.evType or "Other") .. repeatLabel)

    local teamSuffix = ""
    if ev.hostTeamId then
        local tg = GH.Groups:Get(ev.hostTeamId)
        if tg then
            teamSuffix = "  |cff7289da[" .. tg.name
                .. (ev.teamOnly and " — team only" or "") .. "]|r"
        end
    end
    frame.detailAuthor:SetText("Organised by: " .. (ev.author or "Unknown") .. teamSuffix)
    frame.detailDesc:SetText(ev.desc ~= "" and ev.desc or "|cff555566No description.|r")

    -- Populate attendee list
    local rsvps = ev.rsvps or {}
    local yesList, maybeList, noList = {}, {}, {}
    for name, status in pairs(rsvps) do
        if status == "yes" then table.insert(yesList, name)
        elseif status == "maybe" then table.insert(maybeList, name)
        elseif status == "no" then table.insert(noList, name) end
    end
    table.sort(yesList)
    table.sort(maybeList)
    table.sort(noList)

    local lines = {}
    if #yesList > 0 then
        table.insert(lines, "|cff20e530Yes:|r " .. table.concat(yesList, ", "))
    end
    if #maybeList > 0 then
        table.insert(lines, "|cffe7b10aMaybe:|r " .. table.concat(maybeList, ", "))
    end
    if #noList > 0 then
        table.insert(lines, "|cffe03030No:|r " .. table.concat(noList, ", "))
    end

    if #lines > 0 then
        frame.attendeesList:SetText(table.concat(lines, "\n"))
        frame.attendeesLabel:Show()
        frame.attendeesList:Show()
    else
        frame.attendeesLabel:Hide()
        frame.attendeesList:Hide()
    end

    -- Highlight the player's current RSVP
    local myRsvp = GH.Events:GetRSVP(eventId)
    local function dim(btn) btn.bg:SetColorTexture(
        S.COLOR.ACCENT[1]*0.5, S.COLOR.ACCENT[2]*0.5, S.COLOR.ACCENT[3]*0.5, 0.85) end
    local function bright(btn) btn.bg:SetColorTexture(
        S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.85) end
    dim(frame.yesBtn); dim(frame.maybeBtn)
    frame.noBtn.bg:SetColorTexture(S.COLOR.RED[1]*0.5, S.COLOR.RED[2]*0.5, S.COLOR.RED[3]*0.5, 0.85)
    if myRsvp == "yes"   then bright(frame.yesBtn)
    elseif myRsvp == "maybe" then bright(frame.maybeBtn)
    elseif myRsvp == "no" then
        frame.noBtn.bg:SetColorTexture(S.COLOR.RED[1], S.COLOR.RED[2], S.COLOR.RED[3], 0.85)
    end
end

-- Modal dialog to create a new event
function UI:ShowEventCreateDialog()
    local dlg = rawget(_G, "GuildHubEventCreateDialog")
    if dlg then
        dlg.titleBox:SetText("")
        dlg.descBox:SetText("")
        dlg:ResetPickers()
        dlg:Show()
        dlg.titleBox:SetFocus()
        return
    end

    dlg = CreateFrame("Frame", "GuildHubEventCreateDialog", UIParent)
    dlg:SetSize(420, 476)
    dlg:SetPoint("CENTER")
    dlg:SetFrameStrata("DIALOG")
    dlg:SetClampedToScreen(true)
    dlg:EnableMouse(true)
    dlg:SetToplevel(true)
    S:Bg(dlg, S.COLOR.BG[1], S.COLOR.BG[2], S.COLOR.BG[3], 0.98)
    S:Border(dlg)

    local titleHdr = S:FS(dlg, "OVERLAY", "large")
    titleHdr:SetPoint("TOP", dlg, "TOP", 0, -14)
    titleHdr:SetText("Schedule New Event")
    titleHdr:SetTextColor(S.COLOR.TEXT_GOLD[1], S.COLOR.TEXT_GOLD[2], S.COLOR.TEXT_GOLD[3])

    local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() dlg:Hide() end)

    local headerLine = S:HLine(dlg, 380)
    headerLine:SetPoint("TOP",  titleHdr, "BOTTOM", 0, -10)
    headerLine:SetPoint("LEFT", dlg, "LEFT", 20, 0)

    local function Label(text, anchor, offY)
        local l = S:FS(dlg, "OVERLAY")
        l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offY or -8)
        l:SetText(text)
        l:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
        return l
    end

    local titleLbl = Label("Event Title:", headerLine, -14)
    local titleBox = S:EditBox(dlg, 380, 28, 80)
    titleBox:SetPoint("TOPLEFT", titleLbl, "BOTTOMLEFT", 0, -6)

    -- ── Scroll-wheel date/time pickers ────────────────────────────────────────

    local MONTH_NAMES    = {"Jan","Feb","Mar","Apr","May","Jun",
                             "Jul","Aug","Sep","Oct","Nov","Dec"}
    local DAYS_PER_MONTH = {31,28,31,30,31,30,31,31,30,31,30,31}

    local function BuildDays(mIdx, yr)
        local max = DAYS_PER_MONTH[mIdx] or 31
        if mIdx == 2 and yr and
           ((yr % 4 == 0 and yr % 100 ~= 0) or yr % 400 == 0) then
            max = 29
        end
        local t = {}
        for i = 1, max do t[i] = tostring(i) end
        return t
    end
    local function BuildYears()
        local y = tonumber(date("%Y")) or 2025
        return { tostring(y), tostring(y + 1), tostring(y + 2) }
    end
    local function BuildHours()
        local t = {}
        for i = 0, 23 do t[i + 1] = string.format("%02d", i) end
        return t
    end
    local function BuildMinutes()
        local t = {}
        for i = 0, 55, 5 do t[#t + 1] = string.format("%02d", i) end
        return t
    end

    -- Compact scroll-wheel picker (90 px tall).
    -- Frame layout (screen Y, 0 = top, 90 = bottom, center = 45):
    --   1–17   up-arrow button  (TOP-1, h=16)
    --   23 px  prev centre      (WoW CENTER+22 → screen 45-22=23)
    --   39 px  curr centre      (WoW CENTER+6  → screen 45-6 =39)  ← highlight
    --   55 px  next centre      (WoW CENTER-10 → screen 45+10=55)
    --   58–74  down-arrow       (BOTTOM+16, h=16 → 90-16=74 btm, 74-16=58 top)
    --   76–88  column label     (BOTTOM+2, h=12)
    -- Highlight strip: top=28, bottom=50 (22 px centred at 39 = curr row).
    local function MakeScrollPicker(pickerW, initVals, initIdx, colLabel)
        local values = initVals
        local idx    = initIdx or 1
        local count  = #values

        local f = CreateFrame("Frame", nil, dlg)
        f:SetSize(pickerW, 90)

        local bdrTex = f:CreateTexture(nil, "BORDER")
        bdrTex:SetAllPoints()
        bdrTex:SetColorTexture(
            S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.7)
        local bgTex = f:CreateTexture(nil, "BACKGROUND")
        bgTex:SetPoint("TOPLEFT",     f, "TOPLEFT",     1, -1)
        bgTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  1)
        bgTex:SetColorTexture(
            S.COLOR.INPUT_BG[1], S.COLOR.INPUT_BG[2], S.COLOR.INPUT_BG[3], 1)

        -- Highlight: anchored to TOP edge so the strip sits exactly on the
        -- current-value row (28–50 px from frame top = centred at 39 px).
        local hlTex = f:CreateTexture(nil, "ARTWORK")
        hlTex:SetPoint("TOPLEFT",     f, "TOP",  1, -28)
        hlTex:SetPoint("BOTTOMRIGHT", f, "TOP", -1, -50)
        hlTex:SetColorTexture(
            S.COLOR.NAV_ACTIVE[1], S.COLOR.NAV_ACTIVE[2], S.COLOR.NAV_ACTIVE[3], 0.55)

        -- Helper: draws a chevron button (^ or v) using two rotated line textures.
        -- No font or external texture dependency — works in any WoW locale/font.
        local function MakeChevronBtn(anchorPoint, anchorRef, anchorRefPoint, offX, offY, isUp)
            local btn = CreateFrame("Button", nil, f)
            btn:SetPoint(anchorPoint, anchorRef, anchorRefPoint, offX, offY)
            btn:SetPoint(anchorPoint == "TOPLEFT" and "TOPRIGHT" or "BOTTOMRIGHT",
                         f, anchorPoint == "TOPLEFT" and "TOPRIGHT" or "BOTTOMRIGHT",
                         -1, offY)
            btn:SetHeight(18)

            -- Subtle tinted background (very low alpha so text below stays readable)
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(S.COLOR.ACCENT[1]*0.08, S.COLOR.ACCENT[2]*0.08,
                               S.COLOR.ACCENT[3]*0.08, 1)

            -- 1-px separator at the inward edge
            local sep = btn:CreateTexture(nil, "ARTWORK", nil, -1)
            sep:SetHeight(1)
            if isUp then
                sep:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT")
                sep:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")
            else
                sep:SetPoint("TOPLEFT",  btn, "TOPLEFT")
                sep:SetPoint("TOPRIGHT", btn, "TOPRIGHT")
            end
            sep:SetColorTexture(S.COLOR.BORDER[1], S.COLOR.BORDER[2], S.COLOR.BORDER[3], 0.5)

            -- Left arm of chevron
            local armL = btn:CreateTexture(nil, "OVERLAY")
            armL:SetSize(9, 2)
            armL:SetPoint("CENTER", btn, "CENTER", -4, isUp and 1 or -1)
            armL:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.9)
            armL:SetRotation(math.rad(isUp and 40 or -40))

            -- Right arm of chevron
            local armR = btn:CreateTexture(nil, "OVERLAY")
            armR:SetSize(9, 2)
            armR:SetPoint("CENTER", btn, "CENTER", 4, isUp and 1 or -1)
            armR:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.9)
            armR:SetRotation(math.rad(isUp and -40 or 40))

            btn:SetScript("OnEnter", function()
                bg:SetColorTexture(S.COLOR.ACCENT[1]*0.22, S.COLOR.ACCENT[2]*0.22,
                                   S.COLOR.ACCENT[3]*0.22, 1)
                armL:SetColorTexture(1, 1, 1, 1)
                armR:SetColorTexture(1, 1, 1, 1)
            end)
            btn:SetScript("OnLeave", function()
                bg:SetColorTexture(S.COLOR.ACCENT[1]*0.08, S.COLOR.ACCENT[2]*0.08,
                                   S.COLOR.ACCENT[3]*0.08, 1)
                armL:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.9)
                armR:SetColorTexture(S.COLOR.ACCENT[1], S.COLOR.ACCENT[2], S.COLOR.ACCENT[3], 0.9)
            end)
            return btn
        end

        local upBtn   = MakeChevronBtn("TOPLEFT",     f, "TOPLEFT",     1, -1, true)
        local downBtn = MakeChevronBtn("BOTTOMLEFT",  f, "BOTTOMLEFT",  1,  1, false)

        -- Previous value (dimmed, screen y≈22)
        local prevFs = S:FS(f, "OVERLAY")
        prevFs:SetPoint("CENTER", f, "CENTER", 0, 22)
        prevFs:SetWidth(pickerW - 6); prevFs:SetJustifyH("CENTER")
        prevFs:SetTextColor(0.35, 0.35, 0.50)

        -- Current value (bright, screen y≈39 — aligned with the highlight strip)
        local currFs = S:FS(f, "OVERLAY", "normal")
        currFs:SetPoint("CENTER", f, "CENTER", 0, 6)
        currFs:SetWidth(pickerW - 6); currFs:SetJustifyH("CENTER")
        currFs:SetTextColor(1, 1, 1)

        -- Next value (dimmed, screen y≈56)
        local nextFs = S:FS(f, "OVERLAY")
        nextFs:SetPoint("CENTER", f, "CENTER", 0, -10)
        nextFs:SetWidth(pickerW - 6); nextFs:SetJustifyH("CENTER")
        nextFs:SetTextColor(0.35, 0.35, 0.50)

        -- Column label lives inside downBtn so it renders above the button's own bg.
        local colLbl = S:FS(downBtn, "OVERLAY")
        colLbl:SetAllPoints()
        colLbl:SetJustifyH("CENTER")
        colLbl:SetJustifyV("MIDDLE")
        colLbl:SetText(colLabel)
        colLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

        local function Refresh()
            local pIdx = idx > 1     and (idx - 1) or count
            local nIdx = idx < count and (idx + 1) or 1
            prevFs:SetText(tostring(values[pIdx]))
            currFs:SetText(tostring(values[idx]))
            nextFs:SetText(tostring(values[nIdx]))
        end
        Refresh()

        local function ScrollUp()
            idx = idx > 1 and (idx - 1) or count
            Refresh()
            if f.onChange then f.onChange(idx, values[idx]) end
        end
        local function ScrollDown()
            idx = idx < count and (idx + 1) or 1
            Refresh()
            if f.onChange then f.onChange(idx, values[idx]) end
        end

        upBtn:SetScript("OnClick",   ScrollUp)
        downBtn:SetScript("OnClick", ScrollDown)
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", function(_, delta)
            if delta > 0 then ScrollUp() else ScrollDown() end
        end)

        f.GetIndex  = function() return idx end
        f.GetValue  = function() return values[idx] end
        f.SetIndex  = function(i)
            idx = math.max(1, math.min(i, count)); Refresh()
        end
        f.SetValues = function(newVals, keepIdx)
            values = newVals; count = #newVals
            if not keepIdx then idx = math.min(idx, count) end
            Refresh()
        end
        return f
    end

    -- Default: tomorrow at 20:00
    local tomorrow    = time() + 86400
    local defMonth    = tonumber(date("%m", tomorrow)) or 1
    local defDay      = tonumber(date("%d", tomorrow)) or 1
    local defYearStr  = date("%Y", tomorrow)
    local defYearNum  = tonumber(defYearStr) or 2025
    local initYears   = BuildYears()
    local initYearIdx = 1
    for i, y in ipairs(initYears) do
        if y == defYearStr then initYearIdx = i; break end
    end

    local monthPicker = MakeScrollPicker(76, MONTH_NAMES,               defMonth,    "Month")
    local dayPicker   = MakeScrollPicker(52, BuildDays(defMonth, defYearNum), defDay, "Day")
    local yearPicker  = MakeScrollPicker(68, initYears,                 initYearIdx, "Year")
    local hourPicker  = MakeScrollPicker(52, BuildHours(),              21,          "Hour")
    local minPicker   = MakeScrollPicker(52, BuildMinutes(),            1,           "Min")

    local dtLbl = Label("Date & Time:", titleBox, -10)
    monthPicker:SetPoint("TOPLEFT", dtLbl,       "BOTTOMLEFT",  0, -6)
    dayPicker:SetPoint(  "TOPLEFT", monthPicker, "TOPRIGHT",    6,  0)
    yearPicker:SetPoint( "TOPLEFT", dayPicker,   "TOPRIGHT",    6,  0)
    hourPicker:SetPoint( "TOPLEFT", yearPicker,  "TOPRIGHT",   18,  0)
    minPicker:SetPoint(  "TOPLEFT", hourPicker,  "TOPRIGHT",    6,  0)

    -- ":" between hour and minute
    local colonLbl = S:FS(dlg, "OVERLAY", "normal")
    colonLbl:SetPoint("RIGHT", minPicker, "LEFT", -1, 0)
    colonLbl:SetText(":")
    colonLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    -- Rebuild day list when month or year changes (Feb=28/29, Apr=30, etc.)
    monthPicker.onChange = function()
        dayPicker.SetValues(
            BuildDays(monthPicker.GetIndex(), tonumber(yearPicker.GetValue())), true)
    end
    yearPicker.onChange = function()
        dayPicker.SetValues(
            BuildDays(monthPicker.GetIndex(), tonumber(yearPicker.GetValue())), true)
    end

    -- Type
    local typeLbl  = Label("Type:", monthPicker, -8)
    local typeOpts = {}
    for _, t in ipairs(GH.Events.EVENT_TYPES) do
        typeOpts[#typeOpts + 1] = { label = t, value = t }
    end
    local typeDd = S:Dropdown(dlg, typeOpts, 174, 26)
    typeDd:SetPoint("TOPLEFT", typeLbl, "BOTTOMLEFT", 0, -4)

    -- Repeat
    local REPEAT_OPTS = {
        { label = "No Repeat", value = nil        },
        { label = "Weekly",    value = "weekly"   },
        { label = "Bi-Weekly", value = "biweekly" },
        { label = "Monthly",   value = "monthly"  },
    }
    local repeatLabel = S:FS(dlg, "OVERLAY")
    repeatLabel:SetPoint("LEFT", typeDd, "RIGHT", 10, 0)
    repeatLabel:SetText("Repeat:")
    repeatLabel:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])
    local repeatDd = S:Dropdown(dlg, REPEAT_OPTS, 110, 26)
    repeatDd:SetPoint("LEFT", repeatLabel, "RIGHT", 4, 0)

    -- ── Host Team / Team-Only row ─────────────────────────────────────────────
    -- Build the team list at dialog creation time from whatever teams exist now.
    local function BuildTeamOpts()
        local opts = { { label = "All Guild", id = nil } }
        for _, t in ipairs(GH.Groups:GetAll()) do
            opts[#opts + 1] = { label = t.name, id = t.id }
        end
        return opts
    end
    local teamOpts = BuildTeamOpts()

    local hostLbl = S:FS(dlg, "OVERLAY")
    hostLbl:SetPoint("TOPLEFT", typeDd, "BOTTOMLEFT", 0, -8)
    hostLbl:SetText("Host Team:")
    hostLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    dlg.teamIdx = 1
    local teamBtn = S:Button(dlg, teamOpts[1].label, 174, 26)
    teamBtn:SetPoint("TOPLEFT", hostLbl, "BOTTOMLEFT", 0, -4)
    teamBtn:SetScript("OnClick", function()
        dlg.teamIdx = (dlg.teamIdx % #teamOpts) + 1
        teamBtn.label:SetText(teamOpts[dlg.teamIdx].label)
    end)

    -- "Team Only" ON/OFF toggle (shown inline to the right of the team button)
    local teamOnlyLbl = S:FS(dlg, "OVERLAY")
    teamOnlyLbl:SetPoint("LEFT", teamBtn, "RIGHT", 10, 0)
    teamOnlyLbl:SetText("Team Only:")
    teamOnlyLbl:SetTextColor(S.COLOR.TEXT_DIM[1], S.COLOR.TEXT_DIM[2], S.COLOR.TEXT_DIM[3])

    dlg.teamOnly = false
    local teamOnlyBtn = CreateFrame("Button", nil, dlg)
    teamOnlyBtn:SetSize(56, 26)
    teamOnlyBtn:SetPoint("LEFT", teamOnlyLbl, "RIGHT", 4, 0)
    local tObg = teamOnlyBtn:CreateTexture(nil, "BACKGROUND")
    tObg:SetAllPoints()
    tObg:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.5)
    local tOlbl = S:FS(teamOnlyBtn, "OVERLAY")
    tOlbl:SetAllPoints(); tOlbl:SetJustifyH("CENTER")
    tOlbl:SetText("OFF")
    teamOnlyBtn:SetScript("OnClick", function()
        dlg.teamOnly = not dlg.teamOnly
        if dlg.teamOnly then
            tObg:SetColorTexture(S.COLOR.ONLINE[1], S.COLOR.ONLINE[2], S.COLOR.ONLINE[3], 0.75)
            tOlbl:SetText("ON")
        else
            tObg:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.5)
            tOlbl:SetText("OFF")
        end
    end)

    -- Description (anchors to teamBtn so the host-team row is between type and desc)
    local descLbl = Label("Description (optional):", teamBtn, -8)
    local descBox = S:EditBox(dlg, 380, 60, 255)
    descBox:SetPoint("TOPLEFT", descLbl, "BOTTOMLEFT", 0, -4)
    descBox:SetHeight(60)

    local okBtn = S:Button(dlg, "Create", 100, 30)
    okBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 20, 16)
    okBtn:SetScript("OnClick", function()
        local evTitle = titleBox:GetText():match("^%s*(.-)%s*$")
        local evDesc  = descBox:GetText():match("^%s*(.-)%s*$")
        if evTitle == "" then return end
        local ts = time({
            year  = tonumber(yearPicker.GetValue())  or 2025,
            month = monthPicker.GetIndex(),
            day   = tonumber(dayPicker.GetValue())   or 1,
            hour  = tonumber(hourPicker.GetValue())  or 20,
            min   = tonumber(minPicker.GetValue())   or 0,
            sec   = 0,
        })
        local selTeam = teamOpts[dlg.teamIdx]
        GH.Events:Create(evTitle, evDesc, ts,
            typeDd.GetValue(),
            repeatDd.GetValue(),
            selTeam.id,
            selTeam.id and dlg.teamOnly or false)
        dlg:Hide()
        UI:RefreshEventsTab()
    end)

    local cancelBtn = S:DangerButton(dlg, "Cancel", 100, 30)
    cancelBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -20, 16)
    cancelBtn:SetScript("OnClick", function() dlg:Hide() end)

    dlg.ResetPickers = function()
        local tom    = time() + 86400
        local dm     = tonumber(date("%m", tom)) or 1
        local dd     = tonumber(date("%d", tom)) or 1
        local dyStr  = date("%Y", tom)
        local dyNum  = tonumber(dyStr) or 2025
        local newYrs = BuildYears()
        local yIdx   = 1
        for i, y in ipairs(newYrs) do if y == dyStr then yIdx = i; break end end
        monthPicker.SetIndex(dm)
        yearPicker.SetValues(newYrs, false); yearPicker.SetIndex(yIdx)
        dayPicker.SetValues(BuildDays(dm, dyNum), false)
        dayPicker.SetIndex(math.min(dd, #BuildDays(dm, dyNum)))
        hourPicker.SetIndex(21); minPicker.SetIndex(1)
        repeatDd.Reset()
        typeDd.Reset()
        -- Refresh team list in case teams were added/removed since last open
        teamOpts = BuildTeamOpts()
        dlg.teamIdx = 1; teamBtn.label:SetText(teamOpts[1].label)
        dlg.teamOnly = false
        tObg:SetColorTexture(S.COLOR.OFFLINE[1], S.COLOR.OFFLINE[2], S.COLOR.OFFLINE[3], 0.5)
        tOlbl:SetText("OFF")
    end

    dlg.titleBox  = titleBox
    dlg.descBox   = descBox
    dlg.typeDd   = typeDd
    dlg.repeatDd = repeatDd
    dlg.teamBtn   = teamBtn

    titleBox:SetFocus()
end
