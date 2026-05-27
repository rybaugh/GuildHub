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
    if not (C_ClubFinder and C_ClubFinder.SearchClubs) then return end
    -- Parameters: searchTerm, clubType, locale, ageRating, language,
    --   minLevel, maxLevel, minMemberCount, maxMemberCount, playstyle, characteristics
    pcall(C_ClubFinder.SearchClubs, searchTerm, Enum.ClubType.BattleNet,
          GetLocale(), 0, "", 0, 0, 0, 0, 0, 0)
end

-- Caches finder results after CLUB_FINDER_CLUBS_LOADED fires.
-- Returns cached array of ClubFinderCandidateClubData.
function CD:CacheFinderResults()
    if not (C_ClubFinder and C_ClubFinder.GetRecruitingClubs) then
        CD._finderResults = {}
        return {}
    end
    local ok, results = pcall(C_ClubFinder.GetRecruitingClubs, 0, 50)
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

function CD:Initialize()
    if not C_Club then return end   -- guard: Classic / API not present
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CLUB_ADDED")
    frame:RegisterEvent("CLUB_REMOVED")
    frame:RegisterEvent("CLUB_UPDATED")
    frame:RegisterEvent("CLUB_ROSTER_UPDATE")
    frame:RegisterEvent("CLUB_MEMBER_ADDED")
    frame:RegisterEvent("CLUB_MEMBER_REMOVED")
    frame:RegisterEvent("CLUB_MEMBER_UPDATED")
    frame:RegisterEvent("CLUB_MESSAGE_ADDED")
    frame:RegisterEvent("CLUB_MESSAGE_HISTORY_RECEIVED")
    frame:RegisterEvent("CLUB_FINDER_CLUBS_LOADED")
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
    elseif event == "CLUB_ROSTER_UPDATE"   or event == "CLUB_MEMBER_ADDED"
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
    elseif event == "CLUB_FINDER_CLUBS_LOADED" then
        CD:CacheFinderResults()
        if GH.UI and GH.UI.OnClubFinderLoaded then
            GH.UI:OnClubFinderLoaded()
        end
    end
end
