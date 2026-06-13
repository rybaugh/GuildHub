-- GuildHub - EventManager
-- Guild events stored in SavedVariables + broadcast via guild addon messages.

local GH     = GuildHub
local Events = GH.Events

local EVENT_TYPES = { "Raid", "Dungeon", "PvP", "Social", "Competition", "Other" }
Events.EVENT_TYPES = EVENT_TYPES

-- Addon message prefix for events.
-- Format: EV|<id>|<author>|<ts_created>|<event_date>|<evType>|<title>|<desc_truncated>
local EV_PREFIX = "EV|"
local EV_SEP    = "\31"  -- ASCII unit separator — safe in addon messages

function Events:Initialize()
    -- Purge events older than 30 days on load
    local cutoff = GH:GetTimestamp() - (30 * 86400)
    for id, ev in pairs(GH.DB:GetEvents()) do
        if ev.date and ev.date < cutoff then
            GH.DB:DeleteEvent(id)
        end
    end

    -- Listen for event broadcasts from other GuildHub users
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, prefix, message)
        if prefix == GH.ADDON_PREFIX then
            Events:OnAddonMessage(message)
        end
    end)
    Events.eventFrame = frame
end

-- ── CRUD ──────────────────────────────────────────────────────────────────

-- Advance a timestamp by one repeat period.
local function NextOccurrence(ts, repeatType)
    if repeatType == "weekly"   then return ts + 7  * 86400 end
    if repeatType == "biweekly" then return ts + 14 * 86400 end
    if repeatType == "monthly"  then
        local dt = date("*t", ts)
        if type(dt) == "table" then
            local mo = (tonumber(dt.month) or 1) + 1
            local yr =  tonumber(dt.year)  or 2025
            if mo > 12 then mo = 1; yr = yr + 1 end
            return time({ year = yr, month = mo,
                          day  = tonumber(dt.day)  or 1,
                          hour = tonumber(dt.hour) or 0,
                          min  = tonumber(dt.min)  or 0, sec = 0 })
        end
        return ts + 30 * 86400
    end
    return ts
end

function Events:GetAll()
    local now = GH:GetTimestamp()
    local out = {}
    for id, ev in pairs(GH.DB:GetEvents()) do
        local displayDate = ev.date or 0
        local repeatType  = ev.repeatType

        -- For repeating events roll the date forward to the next occurrence.
        if repeatType then
            local safety = 0
            while displayDate < now and safety < 500 do
                displayDate = NextOccurrence(displayDate, repeatType)
                safety = safety + 1
            end
        end

        -- If teamOnly, skip events the current player isn't a member of.
        local visible = true
        if ev.teamOnly and ev.hostTeamId then
            local myTeam = GH.GuildData:GetMemberTeam(GH:GetFullPlayerName())
            if not (myTeam and myTeam.id == ev.hostTeamId) then
                visible = false
            end
        end

        if visible then
            out[#out + 1] = {
                id         = id,
                title      = ev.title,
                desc       = ev.desc or "",
                date       = displayDate,
                evType     = ev.evType or "Other",
                author     = ev.author,
                rsvps      = ev.rsvps or {},
                repeatType = repeatType,
                hostTeamId = ev.hostTeamId,
                teamOnly   = ev.teamOnly,
            }
        end
    end
    table.sort(out, function(a, b) return (a.date or 0) < (b.date or 0) end)
    return out
end

function Events:GetUpcoming()
    local now = GH:GetTimestamp()
    local out = {}
    for _, ev in ipairs(self:GetAll()) do
        if (ev.date or 0) >= now then out[#out + 1] = ev end
    end
    return out
end

-- Add a GuildHub event to the native WoW calendar (player events).
local function AddEventToCalendar(title, desc, timestamp)
    if not C_Calendar or not C_Calendar.CreatePlayerEvent then return end
    if C_Calendar.CanAddEvent and not C_Calendar.CanAddEvent() then return end
    pcall(function()
        local t = date("*t", timestamp)
        if type(t) ~= "table" then return end
        C_Calendar.CreatePlayerEvent()
        C_Calendar.EventSetTitle(title)
        C_Calendar.EventSetDescription(desc or "")
        C_Calendar.EventSetDate(
            tonumber(t.month) or 1,
            tonumber(t.day)   or 1,
            tonumber(t.year)  or 2025)
        C_Calendar.EventSetTime(
            tonumber(t.hour) or 0,
            tonumber(t.min)  or 0)
        C_Calendar.AddEvent()
    end)
    -- Silently ignore failures; calendar may be unavailable.
end

-- Create a new event (Unix timestamp for date) and broadcast it to the guild.
-- repeatType : nil | "weekly" | "biweekly" | "monthly"
-- hostTeamId : nil | team id string  — which team is hosting
-- teamOnly   : boolean — when true, only team members see the event
function Events:Create(title, desc, date, evType, repeatType, hostTeamId, teamOnly)
    local id = GH.DB:NewId()
    local ev = {
        title      = title,
        desc       = desc or "",
        date       = date,
        evType     = evType or "Other",
        author     = GH:GetPlayerName(),
        rsvps      = {},
        repeatType = repeatType or nil,
        hostTeamId = hostTeamId or nil,
        teamOnly   = (hostTeamId and teamOnly) and true or nil,
    }
    GH.DB:SaveEvent(id, ev)
    self:_Broadcast(id, ev)
    AddEventToCalendar(title, desc, date)
    return id
end

function Events:Delete(id)
    GH.DB:DeleteEvent(id)
end

-- RSVP: status = "yes" | "no" | "maybe"
function Events:RSVP(id, status)
    local ev = GH.DB:GetEvents()[id]
    if not ev then return end
    ev.rsvps = ev.rsvps or {}
    ev.rsvps[GH:GetPlayerName()] = status
    GH.DB:SaveEvent(id, ev)
end

function Events:GetRSVP(id, playerName)
    local ev = GH.DB:GetEvents()[id]
    if not ev or not ev.rsvps then return nil end
    return ev.rsvps[playerName or GH:GetPlayerName()]
end

-- ── Network ───────────────────────────────────────────────────────────────

-- Broadcast a single event to all online guild GuildHub users.
-- Description is truncated to 80 chars to stay within the 250-byte limit.
function Events:_Broadcast(id, ev)
    if not GH:IsInGuild() then return end
    local desc = (ev.desc or ""):sub(1, 80)
    local payload = EV_PREFIX .. table.concat({
        id,
        ev.author or GH:GetPlayerName(),
        tostring(GH:GetTimestamp()),
        tostring(ev.date or 0),
        ev.evType or "Other",
        (ev.title or ""):sub(1, 60),
        desc,
        ev.repeatType  or "",
        ev.hostTeamId  or "",
        ev.teamOnly    and "1" or "",
    }, EV_SEP)
    if #payload <= 250 then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
end

-- Re-broadcast all upcoming local events (used during login sync).
-- Messages are spaced 0.3 s apart to avoid channel flooding.
function Events:BroadcastAll()
    if not GH:IsInGuild() then return end
    local now = GH:GetTimestamp()
    local i   = 0
    for id, ev in pairs(GH.DB:GetEvents()) do
        if (ev.date or 0) >= now then
            i = i + 1
            local capturedId = id
            local capturedEv = ev
            C_Timer.After(i * 0.3, function()
                Events:_Broadcast(capturedId, capturedEv)
            end)
        end
    end
end

-- Handle an incoming event broadcast from another client.
function Events:OnAddonMessage(payload)
    if payload:sub(1, #EV_PREFIX) ~= EV_PREFIX then return end
    local rest  = payload:sub(#EV_PREFIX + 1)
    local parts = {}
    for p in (rest .. EV_SEP):gmatch("([^" .. EV_SEP .. "]*)" .. EV_SEP) do
        parts[#parts + 1] = p
    end
    if #parts < 6 then return end

    local id         = parts[1]
    local author     = parts[2]
    local date       = tonumber(parts[4]) or 0
    local evType     = parts[5]
    local title      = parts[6]
    local desc       = parts[7] or ""
    local repeatType = (parts[8] and parts[8] ~= "") and parts[8] or nil
    local hostTeamId = (parts[9] and parts[9] ~= "") and parts[9] or nil
    local teamOnly   = (parts[10] == "1") and true or nil

    -- Skip past events and ones we already have
    local now = GH:GetTimestamp()
    if date < now then return end
    if GH.DB:GetEvents()[id] then return end

    GH.DB:SaveEvent(id, {
        title      = title,
        desc       = desc,
        date       = date,
        evType     = evType,
        author     = author,
        rsvps      = {},
        repeatType = repeatType,
        hostTeamId = hostTeamId,
        teamOnly   = teamOnly,
    })

    if GH.UI and GH.UI.window and GH.UI.window:IsShown()
    and GH.UI.window.activeTab == "Events" then
        GH.UI:RefreshEventsTab()
    end
end

-- ── Date helpers ──────────────────────────────────────────────────────────

function Events:FormatDate(ts)
    if not ts then return "Unknown" end
    return date("%a %b %d, %Y  %I:%M %p", ts)
end

function Events:ParseDate(str)
    local m, d, y, H, M = str:match("(%d+)/(%d+)/(%d+)%s+(%d+):(%d+)")
    if not m then return nil end
    return time({
        year  = tonumber(y) or 2025, month = tonumber(m) or 1,
        day   = tonumber(d) or 1,
        hour  = tonumber(H) or 0,   min   = tonumber(M) or 0, sec = 0,
    })
end
