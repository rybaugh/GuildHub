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
-- GetClubMembers returns member IDs in WoW 12.x; GetMemberInfo resolves each to a table.
function CD:GetMembers(clubId)
    if not (C_Club and C_Club.GetClubMembers) then return {} end
    local ok, memberIds = pcall(C_Club.GetClubMembers, clubId)
    if not ok or not memberIds then return {} end
    local members = {}
    for _, memberId in ipairs(memberIds) do
        if C_Club.GetMemberInfo then
            local ok2, info = pcall(C_Club.GetMemberInfo, clubId, memberId)
            if ok2 and info then members[#members + 1] = info end
        end
    end
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

-- Initiates a community search.
-- WoW 12.x API: RequestClubsList(guildListRequested, searchString, specIDs)
--   false = community list, {} = no spec filter
-- specIDs: optional array of spec IDs for role filtering (pass {} for any role).
function CD:SearchFinder(searchTerm, specIDs)
    if not (C_ClubFinder and C_ClubFinder.RequestClubsList) then return end
    -- Lazy-register search-result events (not available at ADDON_LOADED time).
    if CD.eventFrame then
        for _, ev in ipairs({ "CLUB_FINDER_RECRUIT_LIST_LOADED", "CLUB_FINDER_CLUBS_LOADED" }) do
            pcall(CD.eventFrame.RegisterEvent, CD.eventFrame, ev)
        end
    end
    local ok, err = pcall(C_ClubFinder.RequestClubsList, false, searchTerm, specIDs or {})
    if GuildHub._debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7289daGuildHub:|r RequestClubsList ok=" ..
            tostring(ok) .. " err=" .. tostring(err))
    end
end

-- Retrieves community search results after the search event fires.
-- WoW 12.x API: ReturnMatchingCommunityList() → array of community data tables.
function CD:CacheFinderResults()
    if not (C_ClubFinder and C_ClubFinder.ReturnMatchingCommunityList) then
        CD._finderResults = {}
        return {}
    end
    local ok, results = pcall(C_ClubFinder.ReturnMatchingCommunityList)
    if GuildHub._debugMode then
        local sample = (ok and type(results) == "table" and #results > 0)
                       and results[1] or nil
        local sampleKeys = ""
        if sample then
            local ks = {}
            for k in pairs(sample) do ks[#ks+1] = k .. "=" .. tostring(sample[k]) end
            sampleKeys = " sample={" .. table.concat(ks, ",") .. "}"
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff7289daGuildHub:|r ReturnMatchingCommunityList ok=" ..
            tostring(ok) .. " count=" .. (type(results) == "table" and #results or "n/a") ..
            sampleKeys)
    end
    CD._finderResults = (ok and type(results) == "table") and results or {}
    return CD._finderResults
end

-- Submits an application to a club found via the finder.
-- WoW 12.x API: RequestMembershipToClub(clubFinderGUID, comment)
function CD:ApplyToClub(clubFinderGUID, comment)
    if not C_ClubFinder then return end
    local fn = C_ClubFinder.RequestMembershipToClub or C_ClubFinder.ApplyToClub
    if not fn then return end
    pcall(fn, clubFinderGUID, comment or "")
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
