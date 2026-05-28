-- GuildHub - CommunityData
-- Wraps C_Club and C_ClubFinder APIs. UI never calls WoW APIs directly.

local GH = GuildHub
local CD = GH.Communities

-- Presence values that count as "online" in WoW 12.x
local ONLINE_PRESENCES = {}
if Enum and Enum.ClubMemberPresence then
    ONLINE_PRESENCES[Enum.ClubMemberPresence.Online]       = true
    ONLINE_PRESENCES[Enum.ClubMemberPresence.OnlineMobile] = true
    ONLINE_PRESENCES[Enum.ClubMemberPresence.Away]         = true
    ONLINE_PRESENCES[Enum.ClubMemberPresence.Busy]         = true
end

function CD:IsOnline(presence)
    return ONLINE_PRESENCES[presence] == true
end

-- Returns all subscribed non-guild communities.
function CD:GetAll()
    if not (C_Club and C_Club.GetSubscribedClubs) then return {} end
    local clubs = C_Club.GetSubscribedClubs() or {}
    local out = {}
    for _, club in ipairs(clubs) do
        if club.clubType ~= (Enum and Enum.ClubType and Enum.ClubType.Guild) then
            out[#out + 1] = club
        end
    end
    return out
end

-- Returns members of a community, sorted online-first then alphabetically.
function CD:GetMembers(clubId)
    if not (C_Club and C_Club.GetClubMembers) then return {} end
    local ok, members = pcall(C_Club.GetClubMembers, clubId)
    if not ok or not members then return {} end
    table.sort(members, function(a, b)
        local aOn = CD:IsOnline(a.presence)
        local bOn = CD:IsOnline(b.presence)
        if aOn ~= bOn then return aOn end
        return (a.name or "") < (b.name or "")
    end)
    return members
end

-- Returns the first (General) stream for a community, or nil if none.
function CD:GetStream(clubId)
    if not (C_Club and C_Club.GetStreams) then return nil end
    local ok, streams = pcall(C_Club.GetStreams, clubId)
    if not ok or not streams or #streams == 0 then return nil end
    return streams[1]
end

-- Returns up to 50 most-recent messages. Returns empty table on failure.
function CD:GetMessages(clubId, streamId)
    if not (C_Club and C_Club.GetMessageHistory) then return {} end
    local ok, result = pcall(C_Club.GetMessageHistory, clubId, streamId, nil, 50)
    if not ok or type(result) ~= "table" then return {} end
    return result.messages or {}
end

-- Requests 25 messages older than oldestMessageId. Results arrive via
-- CLUB_MESSAGE_HISTORY_RECEIVED -> UI:OnCommunityHistoryReceived.
function CD:RequestOlderMessages(clubId, streamId, oldestMessageId)
    if not (C_Club and C_Club.RequestMoreMessagesBefore) then return end
    pcall(C_Club.RequestMoreMessagesBefore, clubId, streamId, oldestMessageId, 25)
end

-- Sends a message to the active community stream.
function CD:SendMessage(clubId, streamId, text)
    if not (C_Club and C_Club.SendMessage) then return end
    if not text or text:match("^%s*$") then return end
    pcall(C_Club.SendMessage, clubId, streamId, text)
end

-- Marks all messages in the stream as read.
function CD:MarkRead(clubId, streamId)
    if not (C_Club and C_Club.AdvanceStreamViewMarker) then return end
    pcall(C_Club.AdvanceStreamViewMarker, clubId, streamId)
end

-- Initiates a community search. Results arrive via CLUB_FINDER_CLUBS_LOADED.
function CD:SearchFinder(searchTerm)
    if GuildHub._debugMode then
        if not C_ClubFinder then
            DEFAULT_CHAT_FRAME:AddMessage("|cff7289daGuildHub:|r C_ClubFinder is nil")
        else
            local fns = {}
            for k in pairs(C_ClubFinder) do fns[#fns+1] = k end
            table.sort(fns)
            DEFAULT_CHAT_FRAME:AddMessage("|cff7289daGuildHub:|r C_ClubFinder keys: " .. table.concat(fns, ", "))
        end
    end

    if not C_ClubFinder then return end

    -- Lazy-register the search-result events; they may not be available at ADDON_LOADED time.
    if CD.eventFrame then
        for _, ev in ipairs({ "CLUB_FINDER_CLUBS_LOADED", "CLUB_FINDER_RECRUIT_LIST_LOADED",
                               "CLUB_FINDER_CLUBS_LOADED_RESULT" }) do
            pcall(CD.eventFrame.RegisterEvent, CD.eventFrame, ev)
        end
    end

    -- Try SearchClubs (old API), fall back to RequestClubsList (new API).
    if C_ClubFinder.SearchClubs then
        local ok, err = pcall(C_ClubFinder.SearchClubs, searchTerm, Enum.ClubType.BattleNet,
                              nil, 0, nil, 0, 0, 0, 0, 0, 0)
        if GuildHub._debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff7289daGuildHub:|r SearchClubs ok=" ..
                tostring(ok) .. " err=" .. tostring(err))
        end
    elseif C_ClubFinder.RequestClubsList then
        local ok, err = pcall(C_ClubFinder.RequestClubsList, searchTerm,
                              Enum.ClubType.BattleNet, nil, 0, nil, 0, 0, 0, 0, 0, 0)
        if GuildHub._debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff7289daGuildHub:|r RequestClubsList ok=" ..
                tostring(ok) .. " err=" .. tostring(err))
        end
    else
        if GuildHub._debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff7289daGuildHub:|r No search function found in C_ClubFinder")
        end
    end
end

-- Caches finder results after CLUB_FINDER_CLUBS_LOADED fires.
-- Returns cached array of ClubFinderCandidateClubData.
function CD:CacheFinderResults()
    if not (C_ClubFinder and C_ClubFinder.GetRecruitingClubs) then
        CD._finderResults = {}
        return {}
    end
    -- Try no-arg form first (returns all search results regardless of type),
    -- then fall back to the offset/count form if that returns nothing.
    local ok, results = pcall(C_ClubFinder.GetRecruitingClubs)
    if not ok or type(results) ~= "table" or #results == 0 then
        ok, results = pcall(C_ClubFinder.GetRecruitingClubs, 0, 50)
    end
    if GuildHub._debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7289daGuildHub:|r GetRecruitingClubs ok=" ..
            tostring(ok) .. " type=" .. type(results) ..
            " count=" .. (type(results) == "table" and #results or "n/a"))
    end
    CD._finderResults = (ok and type(results) == "table") and results or {}
    return CD._finderResults
end

-- Submits an application to a club found via the finder.
function CD:ApplyToClub(clubFinderGUID, comment)
    if not (C_ClubFinder and C_ClubFinder.ApplyToClub) then return end
    pcall(C_ClubFinder.ApplyToClub, clubFinderGUID, comment or "")
end

-- Creates a new BattleNet community.
function CD:CreateCommunity(name, shortName, description)
    if not (C_Club and C_Club.CreateClub) then return end
    pcall(C_Club.CreateClub, name, shortName or "", description or "",
          0, Enum.ClubType.BattleNet)
end

local function TryRegister(frame, event)
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444GuildHub:|r Unknown event skipped: " .. event)
    end
end

function CD:Initialize()
    if not (C_Club and C_Club.GetSubscribedClubs) then return end   -- guard: Classic / API not present
    local frame = CreateFrame("Frame")
    TryRegister(frame, "CLUB_ADDED")
    TryRegister(frame, "CLUB_REMOVED")
    TryRegister(frame, "CLUB_UPDATED")
    TryRegister(frame, "CLUB_MEMBER_ADDED")
    TryRegister(frame, "CLUB_MEMBER_REMOVED")
    TryRegister(frame, "CLUB_MEMBER_UPDATED")
    TryRegister(frame, "CLUB_MESSAGE_ADDED")
    TryRegister(frame, "CLUB_MESSAGE_HISTORY_RECEIVED")
    TryRegister(frame, "CLUB_FINDER_RECRUIT_LIST_LOADED")
    TryRegister(frame, "CLUB_FINDER_CLUBS_LOADED")   -- retail alias; TryRegister skips if unknown
    frame:SetScript("OnEvent", function(_, event, ...)
        CD:OnEvent(event, ...)
    end)
    CD.eventFrame = frame
end

function CD:OnEvent(event, ...)
    if event == "CLUB_ADDED" or event == "CLUB_REMOVED" or event == "CLUB_UPDATED" then
        if GH.UI and GH.UI.OnCommunitiesChanged then
            GH.UI:OnCommunitiesChanged(event)
        end
    elseif event == "CLUB_MEMBER_ADDED"
        or event == "CLUB_MEMBER_REMOVED"  or event == "CLUB_MEMBER_UPDATED" then
        if GH.UI and GH.UI.OnCommunityRosterUpdate then
            GH.UI:OnCommunityRosterUpdate(...)
        end
    elseif event == "CLUB_MESSAGE_ADDED" then
        if GH.UI and GH.UI.OnCommunityMessageAdded then
            GH.UI:OnCommunityMessageAdded(...)
        end
    elseif event == "CLUB_MESSAGE_HISTORY_RECEIVED" then
        if GH.UI and GH.UI.OnCommunityHistoryReceived then
            GH.UI:OnCommunityHistoryReceived(...)
        end
    elseif event == "CLUB_FINDER_RECRUIT_LIST_LOADED" or event == "CLUB_FINDER_CLUBS_LOADED" then
        CD:CacheFinderResults()
        if GH.UI and GH.UI.OnClubFinderLoaded then
            GH.UI:OnClubFinderLoaded()
        end
    end
end
