-- GuildHub - ChatManager
-- Guild chat is captured via CLUB_MESSAGE_ADDED (Communities API).
-- History is backfilled from WoW's club cache via C_Club.GetMessagesInRange.

local GH = GuildHub
local Chat = GH.Chat

local MSG_TYPE_CHAT        = "CM"
local MSG_TYPE_CREATE      = "CC"
local MSG_TYPE_LINK        = "CLK"
local MSG_TYPE_LINK_DELETE = "CLKD"
local MSG_TYPE_LINK_LABEL  = "CLKN"
local MSG_TYPE_LINK_TARGET = "CLKT"
local SEPARATOR            = "\30"

local GUILD_ID   = "__GUILD__"
local OFFICER_ID = "__OFFICER__"
local XGUILD_ID  = "__XGUILD__"

Chat.GUILD_ID   = GUILD_ID
Chat.OFFICER_ID = OFFICER_ID
Chat.XGUILD_ID  = XGUILD_ID

Chat.guildMsgs              = {}
Chat.officerMsgs            = {}
Chat.communityMsgs          = {}
Chat._linkedClubs           = {}   -- [tostring(clubId)] = {streamId, label, id}
Chat._lastSentCommunityMsgs = {}   -- [tostring(clubId)] = {sender, text}
Chat.unread                 = {}

local MAX_RING            = 2000
local MAX_COMMUNITY_RING  = 2000
local CLUB_TYPE_GUILD     = (Enum and Enum.ClubType and Enum.ClubType.Guild) or 3

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function AppendRing(buf, entry, max)
    buf[#buf + 1] = entry
    local limit = max or MAX_RING
    if #buf > limit then table.remove(buf, 1) end
end

local function HasAnyLinks()
    for _ in pairs(GH.DB:GetCommunityLinks()) do return true end
    return false
end

local function NotifyGuildMsg(entry)
    local channelId = entry.isOfficer and OFFICER_ID or GUILD_ID
    local buf       = entry.isOfficer and Chat.officerMsgs or Chat.guildMsgs
    AppendRing(buf, entry)
    Chat.unread[channelId] = (Chat.unread[channelId] or 0) + 1
    if GH.UI and GH.UI.UpdateChatBadge then GH.UI:UpdateChatBadge() end
    if GH.UI and GH.UI.OnChatMessage   then GH.UI:OnChatMessage(channelId) end
    -- Guild messages also appear in the cross-guild view when any links are configured.
    if not entry.isOfficer and HasAnyLinks() then
        Chat.unread[XGUILD_ID] = (Chat.unread[XGUILD_ID] or 0) + 1
        if GH.UI and GH.UI.OnChatMessage then GH.UI:OnChatMessage(XGUILD_ID) end
    end
end

-- ── Initialization ────────────────────────────────────────────────────────

function Chat:Initialize()
    GH:Debug("Chat", "Initialize()")

    -- Load previously cached messages from SavedVariables immediately.
    Chat:_LoadSavedGuildHistory()
    Chat:_LoadSavedCommunityHistory()

    -- Custom group-channel addon messages.
    local af = CreateFrame("Frame")
    af:RegisterEvent("CHAT_MSG_ADDON")
    af:SetScript("OnEvent", function(_, _, prefix, message, _, sender)
        if prefix == GH.ADDON_PREFIX then Chat:OnAddonMessage(message, sender) end
    end)
    Chat._addonEventFrame = af

    -- WIM-style deferred guild/officer chat capture.
    -- CHAT_MSG_GUILD/OFFICER arg11 is the lineID — never a secret value even in WoW 12.x.
    -- If InChatMessagingLockdown() is true the lineID is queued; the OnUpdate frame drains
    -- the queue once the lockdown clears and calls GetChatLineText/GetChatLineSenderName.
    Chat._pendingLines = {}

    local processFrame = CreateFrame("Frame")
    processFrame:Hide()
    processFrame:SetScript("OnUpdate", function()
        if #Chat._pendingLines == 0 then processFrame:Hide(); return end
        local C_ChatInfo = rawget(_G, "C_ChatInfo")
        if not C_ChatInfo then processFrame:Hide(); return end
        if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
        local queue = Chat._pendingLines
        Chat._pendingLines = {}
        processFrame:Hide()
        for _, item in ipairs(queue) do
            Chat:_ProcessChatLine(item.lineID, item.isOfficer)
        end
    end)
    Chat._lineProcessFrame = processFrame

    -- Real-time guild/officer chat via CHAT_MSG_GUILD/OFFICER + GetChatLineText.
    -- CLUB_MESSAGE_ADDED provides an immediate fallback via the C_Club API (no chat lockdown),
    -- which fixes message delivery during dungeons where InChatMessagingLockdown() persists.
    -- CLUB_MESSAGE_HISTORY_RECEIVED triggers history backfill from the C_Club cache.
    local gf = CreateFrame("Frame")
    gf:RegisterEvent("CHAT_MSG_GUILD")
    gf:RegisterEvent("CHAT_MSG_OFFICER")
    gf:RegisterEvent("CLUB_MESSAGE_ADDED")
    gf:RegisterEvent("CLUB_MESSAGE_HISTORY_RECEIVED")
    gf:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
            local isOfficer = (event == "CHAT_MSG_OFFICER")
            local lineID = select(11, ...)
            if not lineID then return end
            local C_ChatInfo = rawget(_G, "C_ChatInfo")
            local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
                and C_ChatInfo.InChatMessagingLockdown()
            if locked then
                Chat._pendingLines[#Chat._pendingLines + 1] = { lineID = lineID, isOfficer = isOfficer }
                Chat._lineProcessFrame:Show()
            else
                Chat:_ProcessChatLine(lineID, isOfficer)
            end
        elseif event == "CLUB_MESSAGE_ADDED" then
            local clubId, streamId, messageId = ...
            Chat:_OnClubMessageAdded(clubId, streamId, messageId)
        elseif event == "CLUB_MESSAGE_HISTORY_RECEIVED" then
            local clubId, streamId = ...
            -- If club discovery hasn't run yet, do it now — C_Club is clearly ready.
            if not Chat.guildClubId then
                Chat:FindGuildClub()
            end
            if clubId == Chat.guildClubId and streamId == Chat.guildStreamId then
                Chat:_LoadFromClubCache(clubId, streamId)
            else
                local li = Chat._linkedClubs[tostring(clubId)]
                if li and streamId == li.streamId then
                    Chat:_LoadCommunityHistory(clubId, streamId, li)
                end
            end
        end
    end)
    Chat._guildEventFrame = gf

    -- Discover the guild's club + stream once login data is ready.
    -- 2 s is enough for PLAYER_LOGIN to fire; shorter reduces the window where
    -- CLUB_MESSAGE_HISTORY_RECEIVED can arrive before the club ID is known.
    C_Timer.After(2, function() Chat:FindGuildClub() end)
    -- Community discovery runs slightly later so the guild club is already known.
    C_Timer.After(4, function() Chat:FindLinkedCommunities() end)
end

-- ── Real-time chat line processing ───────────────────────────────────────

function Chat:_ProcessChatLine(lineID, isOfficer)
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if not C_ChatInfo then return end
    local text   = C_ChatInfo.GetChatLineText        and C_ChatInfo.GetChatLineText(lineID)       or ""
    local sender = C_ChatInfo.GetChatLineSenderName  and C_ChatInfo.GetChatLineSenderName(lineID) or "?"
    if text == "" then return end
    if Ambiguate then sender = Ambiguate(sender, "none") end
    -- Skip if already captured immediately via CLUB_MESSAGE_ADDED (e.g. during dungeon).
    local ringBuf = isOfficer and Chat.officerMsgs or Chat.guildMsgs
    for i = math.max(1, #ringBuf - 30), #ringBuf do
        local m = ringBuf[i]
        if m and m.sender == sender and m.text == text then return end
    end
    local ts    = GH:GetTimestamp()
    local entry = { sender = sender, text = text, ts = ts }
    GH:Debug("Chat", "_ProcessChatLine: %s: %s (isOfficer=%s)", sender, text, tostring(isOfficer))
    if isOfficer then
        entry.isOfficer = true
        local prev = Chat._lastSentOfficerMsg
        if prev and prev.sender == sender and prev.text == text then
            Chat._lastSentOfficerMsg = nil
            return
        end
        NotifyGuildMsg(entry)
    else
        local prev = Chat._lastSentGuildMsg
        if prev and prev.sender == sender and prev.text == text then
            Chat._lastSentGuildMsg = nil
            return
        end
        GH.DB:AddGuildMessage(entry)
        NotifyGuildMsg(entry)
    end
end

-- Immediate real-time capture via CLUB_MESSAGE_ADDED — bypasses InChatMessagingLockdown.
-- This is the primary path when in dungeons where the lockdown persists through combat.
-- _ProcessChatLine deduplicates against the ring buffer so both paths can coexist safely.
function Chat:_OnClubMessageAdded(clubId, streamId, messageId)
    -- ── Guild / officer stream ────────────────────────────────────────────
    if Chat.guildClubId and clubId == Chat.guildClubId then
        local isOfficer = Chat.officerStreamId and streamId == Chat.officerStreamId
        if streamId ~= Chat.guildStreamId and not isOfficer then return end

        local C_Club = rawget(_G, "C_Club")
        if not (C_Club and C_Club.GetMessage) then return end
        local msg = SafeCall(C_Club.GetMessage, clubId, streamId, messageId)
        if not msg then return end

        local body   = msg.content and msg.content.body
        local sender = msg.author  and msg.author.name
        if not body or body == "" or not sender then return end

        local ts = messageId and math.floor(messageId.epoch / 1000000) or GH:GetTimestamp()

        local buf = isOfficer and Chat.officerMsgs or Chat.guildMsgs
        for i = math.max(1, #buf - 30), #buf do
            local m = buf[i]
            if m and m.sender == sender and m.text == body then return end
        end

        if isOfficer then
            local prev = Chat._lastSentOfficerMsg
            if prev and prev.sender == sender and prev.text == body then
                Chat._lastSentOfficerMsg = nil; return
            end
        else
            local prev = Chat._lastSentGuildMsg
            if prev and prev.sender == sender and prev.text == body then
                Chat._lastSentGuildMsg = nil; return
            end
        end

        local entry = { sender = sender, text = body, ts = ts }
        if isOfficer then entry.isOfficer = true end
        GH:Debug("Chat", "_OnClubMessageAdded: %s: %s (isOfficer=%s)", sender, body, tostring(isOfficer or false))
        if not isOfficer then GH.DB:AddGuildMessage(entry) end
        NotifyGuildMsg(entry)
        return
    end

    -- ── Linked community stream ───────────────────────────────────────────
    local li = Chat._linkedClubs[tostring(clubId)]
    if li and streamId == li.streamId then
        Chat:_OnCommunityMessageAdded(clubId, streamId, messageId, li)
    end
end

function Chat:_OnCommunityMessageAdded(clubId, streamId, messageId, li)
    local C_Club = rawget(_G, "C_Club")
    if not (C_Club and C_Club.GetMessage) then return end
    local msg = SafeCall(C_Club.GetMessage, clubId, streamId, messageId)
    if not msg then return end

    local body   = msg.content and msg.content.body
    local sender = msg.author  and msg.author.name
    if not body or body == "" or not sender then return end

    local ts  = messageId and math.floor(messageId.epoch / 1000000) or GH:GetTimestamp()
    local mid = messageId and tostring(messageId.epoch) or nil
    local cid = tostring(clubId)

    -- Dedup against recent community ring.
    for i = math.max(1, #Chat.communityMsgs - 30), #Chat.communityMsgs do
        local m = Chat.communityMsgs[i]
        if m and m.communityId == cid and m.sender == sender and m.text == body then return end
    end

    -- Echo guard for own sent messages.
    local prevSent = Chat._lastSentCommunityMsgs[cid]
    if prevSent and prevSent.sender == sender and prevSent.text == body then
        Chat._lastSentCommunityMsgs[cid] = nil
        return
    end

    local entry = {
        sender      = sender,
        text        = body,
        ts          = ts,
        mid         = mid,
        communityId = cid,
        sourceLabel = li.label,
    }
    GH:Debug("Chat", "_OnCommunityMessageAdded: [%s] %s: %s", li.label, sender, body)
    AppendRing(Chat.communityMsgs, entry, MAX_COMMUNITY_RING)
    GH.DB:AddCommunityMessage(entry)
    Chat.unread[XGUILD_ID] = (Chat.unread[XGUILD_ID] or 0) + 1
    if GH.UI and GH.UI.UpdateChatBadge then GH.UI:UpdateChatBadge() end
    if GH.UI and GH.UI.OnChatMessage   then GH.UI:OnChatMessage(XGUILD_ID) end
end

-- ── Club discovery ────────────────────────────────────────────────────────

function Chat:FindGuildClub()
    if Chat.guildClubId and Chat.guildStreamId then return end
    local C_Club = rawget(_G, "C_Club")
    if not (C_Club and C_Club.GetSubscribedClubs) then return end

    local clubs = SafeCall(C_Club.GetSubscribedClubs) or {}
    for _, club in ipairs(clubs) do
        if club.clubType == CLUB_TYPE_GUILD then
            Chat.guildClubId = club.clubId
            GH:Debug("Chat", "FindGuildClub: clubId=%s", tostring(club.clubId))

            local streams = SafeCall(C_Club.GetStreams, club.clubId) or {}
            for _, s in ipairs(streams) do
                if s.streamType == 0 then
                    Chat.guildStreamId = s.streamId
                end
            end
            if not Chat.guildStreamId and streams[1] then
                Chat.guildStreamId = streams[1].streamId
            end
            -- Officer stream is the first stream that isn't the general stream.
            Chat.officerStreamId = nil
            for _, s in ipairs(streams) do
                if s.streamId ~= Chat.guildStreamId then
                    Chat.officerStreamId = s.streamId
                    break
                end
            end

            GH:Debug("Chat", "FindGuildClub: streamId=%s officerStreamId=%s",
                tostring(Chat.guildStreamId), tostring(Chat.officerStreamId))

            if Chat.guildStreamId then
                Chat:_LoadFromClubCache(Chat.guildClubId, Chat.guildStreamId)
                Chat:_RequestMoreGuildHistory()
            end
            return
        end
    end

    -- Retry up to 6 times at 5 s intervals if guild data isn't ready yet.
    Chat._guildClubDiscoveryAttempts = (Chat._guildClubDiscoveryAttempts or 0) + 1
    if Chat._guildClubDiscoveryAttempts < 6 then
        C_Timer.After(5, function() Chat:FindGuildClub() end)
    end
end

-- ── History backfill ──────────────────────────────────────────────────────

function Chat:_RequestMoreGuildHistory()
    local C_Club = rawget(_G, "C_Club")
    if not (C_Club and C_Club.RequestMoreMessagesBefore
            and Chat.guildClubId and Chat.guildStreamId) then return end
    local now = GetTime()
    if Chat._lastGuildHistoryRequestTs and now - Chat._lastGuildHistoryRequestTs < 30 then
        return
    end
    Chat._lastGuildHistoryRequestTs = now
    SafeCall(C_Club.RequestMoreMessagesBefore, Chat.guildClubId, Chat.guildStreamId, nil, 50)
end

function Chat:_LoadFromClubCache(clubId, streamId)
    local C_Club = rawget(_G, "C_Club")
    if not (C_Club and C_Club.GetMessageRangeInCache and C_Club.GetMessagesInRange) then return end

    local minId, maxId = SafeCall(C_Club.GetMessageRangeInCache, clubId, streamId)
    if not minId or not maxId then
        if C_Club.RequestMoreMessagesBefore then
            SafeCall(C_Club.RequestMoreMessagesBefore, clubId, streamId, nil, 50)
        end
        return
    end

    local messages = SafeCall(C_Club.GetMessagesInRange, clubId, streamId, minId, maxId)
    if not messages then return end

    -- Build a dedup set from what's already in the ring buffer.
    local seen = {}
    for _, m in ipairs(Chat.guildMsgs) do
        seen[(m.sender or "") .. "\1" .. (m.text or "") .. "\1" .. tostring(m.ts)] = true
    end

    local newEntries = {}
    for _, msg in ipairs(messages) do
        local body   = msg.content and msg.content.body
        local sender = msg.author  and msg.author.name
        if body and body ~= "" and sender then
            local ts  = msg.messageId and math.floor(msg.messageId.epoch / 1000000) or 0
            local key = sender .. "\1" .. body .. "\1" .. tostring(ts)
            if not seen[key] then
                seen[key] = true
                newEntries[#newEntries + 1] = { sender = sender, text = body, ts = ts }
            end
        end
    end

    if #newEntries == 0 then return end

    table.sort(newEntries, function(a, b) return a.ts < b.ts end)
    for _, e in ipairs(newEntries) do
        AppendRing(Chat.guildMsgs, e)
        GH.DB:AddGuildMessage(e)
    end

    GH:Debug("Chat", "_LoadFromClubCache: added %d msgs", #newEntries)
    if GH.UI and GH.UI.OnChatMessage then GH.UI:OnChatMessage(GUILD_ID) end
end

function Chat:_LoadSavedGuildHistory()
    Chat.guildMsgs = {}
    for _, msg in ipairs(GH.DB:GetGuildMessages()) do
        AppendRing(Chat.guildMsgs, msg)
    end
    GH:Debug("Chat", "_LoadSavedGuildHistory: ring=%d", #Chat.guildMsgs)
end

function Chat:_LoadSavedCommunityHistory()
    Chat.communityMsgs = {}
    for _, msg in ipairs(GH.DB:GetCommunityMessages()) do
        AppendRing(Chat.communityMsgs, msg, MAX_COMMUNITY_RING)
    end
    GH:Debug("Chat", "_LoadSavedCommunityHistory: ring=%d", #Chat.communityMsgs)
end

-- ── Community discovery & history ─────────────────────────────────────────

function Chat:FindLinkedCommunities()
    Chat._linkedClubs = {}
    local links = GH.DB:GetCommunityLinks()
    if not HasAnyLinks() then return end

    local C_Club = rawget(_G, "C_Club")
    if not (C_Club and C_Club.GetSubscribedClubs) then return end

    local clubs = SafeCall(C_Club.GetSubscribedClubs) or {}
    local clubMap = {}
    for _, club in ipairs(clubs) do
        clubMap[tostring(club.clubId)] = club
    end

    for id, link in pairs(links) do
        if link.enabled ~= false and clubMap[tostring(link.clubId)] then
            Chat._linkedClubs[tostring(link.clubId)] = {
                streamId = link.streamId,
                label    = link.label or "Community",
                id       = id,
            }
            local li = Chat._linkedClubs[tostring(link.clubId)]
            Chat:_LoadCommunityHistory(link.clubId, link.streamId, li)
            if C_Club.RequestMoreMessagesBefore then
                C_Timer.After(0.5, function()
                    SafeCall(C_Club.RequestMoreMessagesBefore, link.clubId, link.streamId, nil, 50)
                end)
            end
        end
    end

    GH:Debug("Chat", "FindLinkedCommunities: %d linked", (function()
        local n = 0; for _ in pairs(Chat._linkedClubs) do n = n + 1 end; return n
    end)())
    if GH.UI and GH.UI.OnChannelListChanged then GH.UI:OnChannelListChanged() end
end

function Chat:_LoadCommunityHistory(clubId, streamId, li)
    local C_Club = rawget(_G, "C_Club")
    if not (C_Club and C_Club.GetMessageRangeInCache and C_Club.GetMessagesInRange) then return end

    local minId, maxId = SafeCall(C_Club.GetMessageRangeInCache, clubId, streamId)
    if not minId or not maxId then return end

    local messages = SafeCall(C_Club.GetMessagesInRange, clubId, streamId, minId, maxId)
    if not messages then return end

    local cid  = tostring(clubId)
    local seen = {}
    for _, m in ipairs(Chat.communityMsgs) do
        if m.communityId == cid then
            seen[(m.sender or "") .. "\1" .. (m.text or "") .. "\1" .. tostring(m.ts)] = true
        end
    end

    local newEntries = {}
    for _, msg in ipairs(messages) do
        local body   = msg.content and msg.content.body
        local sender = msg.author  and msg.author.name
        if body and body ~= "" and sender then
            local ts  = msg.messageId and math.floor(msg.messageId.epoch / 1000000) or 0
            local mid = msg.messageId and tostring(msg.messageId.epoch) or nil
            local key = sender .. "\1" .. body .. "\1" .. tostring(ts)
            if not seen[key] then
                seen[key] = true
                newEntries[#newEntries + 1] = {
                    sender      = sender,
                    text        = body,
                    ts          = ts,
                    mid         = mid,
                    communityId = cid,
                    sourceLabel = li.label,
                }
            end
        end
    end

    if #newEntries == 0 then return end

    table.sort(newEntries, function(a, b) return a.ts < b.ts end)
    for _, e in ipairs(newEntries) do
        AppendRing(Chat.communityMsgs, e, MAX_COMMUNITY_RING)
        GH.DB:AddCommunityMessage(e)
    end
    -- Keep communityMsgs sorted after bulk insert.
    table.sort(Chat.communityMsgs, function(a, b) return a.ts < b.ts end)

    GH:Debug("Chat", "_LoadCommunityHistory [%s]: added %d msgs", li.label, #newEntries)
    if GH.UI and GH.UI.OnChatMessage then GH.UI:OnChatMessage(XGUILD_ID) end
end

function Chat:LoadXGuildHistory()
    Chat:_LoadSavedCommunityHistory()
    for cid, li in pairs(Chat._linkedClubs) do
        Chat:_LoadCommunityHistory(cid, li.streamId, li)
    end
    if GH.UI and GH.UI.OnChatMessage then GH.UI:OnChatMessage(XGUILD_ID) end
end

-- ── History ───────────────────────────────────────────────────────────────

-- Called when the Guild Chat tab is opened or when history needs refreshing.
function Chat:LoadGuildHistory()
    Chat:_LoadSavedGuildHistory()
    if GH.UI and GH.UI.OnChatMessage then GH.UI:OnChatMessage(GUILD_ID) end
    if Chat.guildClubId and Chat.guildStreamId then
        Chat:_LoadFromClubCache(Chat.guildClubId, Chat.guildStreamId)
        Chat:_RequestMoreGuildHistory()
    else
        Chat:FindGuildClub()
    end
end

-- ── Officer history ───────────────────────────────────────────────────────

function Chat:LoadOfficerHistory()
    if not (Chat.guildClubId and Chat.officerStreamId) then return end
    local C_Club = rawget(_G, "C_Club")
    if not (C_Club and C_Club.GetMessageRangeInCache and C_Club.GetMessagesInRange) then return end

    local minId, maxId = SafeCall(C_Club.GetMessageRangeInCache, Chat.guildClubId, Chat.officerStreamId)
    if not minId or not maxId then return end

    local messages = SafeCall(C_Club.GetMessagesInRange, Chat.guildClubId, Chat.officerStreamId, minId, maxId)
    if not messages then return end

    local seen = {}
    for _, m in ipairs(Chat.officerMsgs) do
        seen[(m.sender or "") .. "\1" .. (m.text or "") .. "\1" .. tostring(m.ts)] = true
    end

    local newEntries = {}
    for _, msg in ipairs(messages) do
        local body   = msg.content and msg.content.body
        local sender = msg.author  and msg.author.name
        if body and body ~= "" and sender then
            local ts  = msg.messageId and math.floor(msg.messageId.epoch / 1000000) or 0
            local key = sender .. "\1" .. body .. "\1" .. tostring(ts)
            if not seen[key] then
                seen[key] = true
                newEntries[#newEntries + 1] = { sender = sender, text = body, ts = ts, isOfficer = true }
            end
        end
    end

    if #newEntries == 0 then return end

    table.sort(newEntries, function(a, b) return a.ts < b.ts end)
    for _, e in ipairs(newEntries) do AppendRing(Chat.officerMsgs, e) end

    GH:Debug("Chat", "LoadOfficerHistory: added %d msgs", #newEntries)
    if GH.UI and GH.UI.OnChatMessage then GH.UI:OnChatMessage(OFFICER_ID) end
end

-- ── Channel management ─────────────────────────────────────────────────────

function Chat:GetChannels()
    local out = {}
    out[#out + 1] = { id = GUILD_ID, name = "Guild Chat", isGuild = true }
    if GH:IsOfficer() then
        out[#out + 1] = { id = OFFICER_ID, name = "Officer", isOfficer = true }
    end
    if HasAnyLinks() then
        out[#out + 1] = {
            id       = XGUILD_ID,
            name     = GH.DB:GetCrossGuildLabel(),
            isXGuild = true,
        }
    end
    local custom = {}
    for id, ch in pairs(GH.DB:GetChats()) do
        custom[#custom + 1] = { id = id, name = ch.name, members = ch.members }
    end
    table.sort(custom, function(a, b) return a.name < b.name end)
    for _, ch in ipairs(custom) do out[#out + 1] = ch end
    return out
end

function Chat:GetChannel(id)
    return GH.DB:GetChat(id)
end

function Chat:CreateChannel(name, members)
    local id = GH.DB:NewId()
    local ch = { name = name, members = members or {}, messages = {} }
    GH.DB:SaveChat(id, ch)
    self:_BroadcastChannelInfo(id, ch)
    return id
end

function Chat:DeleteChannel(id)
    GH.DB:DeleteChat(id)
end

function Chat:AddMember(channelId, memberName)
    local ch = GH.DB:GetChat(channelId)
    if not ch then return end
    for _, n in ipairs(ch.members) do
        if n == memberName then return end
    end
    ch.members[#ch.members + 1] = memberName
    GH.DB:SaveChat(channelId, ch)
    self:_BroadcastChannelInfo(channelId, ch)
end

function Chat:RemoveMember(channelId, memberName)
    local ch = GH.DB:GetChat(channelId)
    if not ch then return end
    for i, n in ipairs(ch.members) do
        if n == memberName then table.remove(ch.members, i); break end
    end
    GH.DB:SaveChat(channelId, ch)
end

function Chat:SendMessage(channelId, text)
    if text == "" then return end

    if channelId == XGUILD_ID then
        -- Try to send to the configured community stream (C_Club.SendMessage is safe
        -- here because we're called from an OnEnterPressed / OnClick hardware event).
        local sendTarget = GH.DB:GetCrossGuildSendTarget()
        if sendTarget then
            local li = Chat._linkedClubs[tostring(sendTarget)]
            if li then
                local C_Club = rawget(_G, "C_Club")
                if C_Club and C_Club.SendMessage then
                    local ok = pcall(C_Club.SendMessage, sendTarget, li.streamId, text)
                    if ok then
                        -- Optimistic local display; echo suppressed by _lastSentCommunityMsgs.
                        local cid = tostring(sendTarget)
                        Chat._lastSentCommunityMsgs[cid] = { sender = GH:GetPlayerName(), text = text }
                        local entry = {
                            sender      = GH:GetPlayerName(),
                            text        = text,
                            ts          = GH:GetTimestamp(),
                            communityId = cid,
                            sourceLabel = li.label,
                        }
                        AppendRing(Chat.communityMsgs, entry, MAX_COMMUNITY_RING)
                        GH.DB:AddCommunityMessage(entry)
                        if GH.UI and GH.UI.OnChatMessage then GH.UI:OnChatMessage(XGUILD_ID) end
                        return
                    end
                end
            end
        end
        -- Fallback: send to own guild chat and let it surface in the merged view.
        channelId = GUILD_ID
    end

    if channelId == GUILD_ID then
        local msg = { sender = GH:GetPlayerName(), text = text, ts = GH:GetTimestamp() }
        GH.DB:AddGuildMessage(msg)
        Chat._lastSentGuildMsg = msg
        NotifyGuildMsg(msg)
        local fn = rawget(_G, "SendChatMessage")
        if fn then fn(text, "GUILD") end
        return
    end

    if channelId == OFFICER_ID then
        local msg = { sender = GH:GetPlayerName(), text = text,
                      ts = GH:GetTimestamp(), isOfficer = true }
        Chat._lastSentOfficerMsg = msg
        NotifyGuildMsg(msg)
        local fn = rawget(_G, "SendChatMessage")
        if fn then fn(text, "OFFICER") end
        return
    end

    local ch = GH.DB:GetChat(channelId)
    if not ch then return end

    local sender  = GH:GetPlayerName()
    local ts      = GH:GetTimestamp()
    local msg     = { sender = sender, text = text, ts = ts }
    GH.DB:AddChatMessage(channelId, msg)

    local payload = table.concat(
        { MSG_TYPE_CHAT, channelId, sender, tostring(ts), text }, SEPARATOR)
    if #payload <= 250 then
        local C_ChatInfo = rawget(_G, "C_ChatInfo")
        if C_ChatInfo then
            C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
        end
    end

    if GH.UI and GH.UI.OnChatMessage then GH.UI:OnChatMessage(channelId, msg) end
end

function Chat:GetMessages(channelId)
    if channelId == GUILD_ID   then return Chat.guildMsgs   end
    if channelId == OFFICER_ID then return Chat.officerMsgs end
    if channelId == XGUILD_ID  then
        -- Linear merge of two independently-sorted arrays: O(n).
        local gm, cm = Chat.guildMsgs, Chat.communityMsgs
        local result = {}
        local gi, ci = 1, 1
        while gi <= #gm or ci <= #cm do
            if gi <= #gm and (ci > #cm or gm[gi].ts <= cm[ci].ts) then
                result[#result + 1] = gm[gi]; gi = gi + 1
            else
                result[#result + 1] = cm[ci]; ci = ci + 1
            end
        end
        return result
    end
    local ch = GH.DB:GetChat(channelId)
    return ch and ch.messages or {}
end

function Chat:IsMember(channelId, playerName)
    if channelId == GUILD_ID or channelId == OFFICER_ID or channelId == XGUILD_ID then return true end
    -- Officers can see all custom channels (team chats and group channels).
    if playerName == GH:GetPlayerName() and GH:IsOfficer() then return true end
    local ch = GH.DB:GetChat(channelId)
    if not ch then return false end
    for _, n in ipairs(ch.members) do
        if n == playerName then return true end
    end
    return false
end

function Chat:MarkRead(channelId)
    Chat.unread[channelId] = 0
    if GH.UI and GH.UI.UpdateChatBadge then GH.UI:UpdateChatBadge() end
end

function Chat:GetUnreadCount(channelId)
    return Chat.unread[channelId] or 0
end

function Chat:GetTotalUnread()
    local total = 0
    for _, v in pairs(Chat.unread) do total = total + v end
    return total
end

-- ── Addon messages (custom group channels) ────────────────────────────────

function Chat:OnAddonMessage(payload, _)
    local parts = {}
    for p in (payload .. SEPARATOR):gmatch("([^" .. SEPARATOR .. "]*)" .. SEPARATOR) do
        parts[#parts + 1] = p
    end
    if #parts < 1 then return end

    local msgType = parts[1]

    if msgType == MSG_TYPE_CHAT and #parts >= 5 then
        local channelId = parts[2]
        local msgSender = parts[3]
        local ts        = tonumber(parts[4]) or GH:GetTimestamp()
        local text      = parts[5]

        if not self:IsMember(channelId, GH:GetPlayerName()) then return end
        if msgSender == GH:GetPlayerName() then return end

        local msg = { sender = msgSender, text = text, ts = ts }
        GH.DB:AddChatMessage(channelId, msg)
        if GH.UI and GH.UI.OnChatMessage then GH.UI:OnChatMessage(channelId, msg) end

    elseif msgType == MSG_TYPE_CREATE and #parts >= 3 then
        local channelId   = parts[2]
        local channelName = parts[3]
        local membersStr  = parts[4] or ""
        local members = {}
        for m in (membersStr .. ","):gmatch("([^,]*),") do
            if m ~= "" then members[#members + 1] = m end
        end
        local myName = GH:GetPlayerName()
        for _, n in ipairs(members) do
            if n == myName and not GH.DB:GetChat(channelId) then
                GH.DB:SaveChat(channelId,
                    { name = channelName, members = members, messages = {} })
                if GH.UI and GH.UI.OnChannelListChanged then
                    GH.UI:OnChannelListChanged()
                end
                break
            end
        end

    elseif msgType == MSG_TYPE_LINK and #parts >= 4 then
        local id       = parts[2]
        local clubId   = parts[3]
        local streamId = parts[4]
        local label    = parts[5] or "Community"
        GH.DB:SaveCommunityLink(id, { clubId = clubId, streamId = streamId, label = label, enabled = true })
        Chat:FindLinkedCommunities()

    elseif msgType == MSG_TYPE_LINK_DELETE and #parts >= 2 then
        local id   = parts[2]
        local link = GH.DB:GetCommunityLinks()[id]
        if link then Chat._linkedClubs[tostring(link.clubId)] = nil end
        GH.DB:DeleteCommunityLink(id)
        if GH.UI and GH.UI.OnChannelListChanged then GH.UI:OnChannelListChanged() end

    elseif msgType == MSG_TYPE_LINK_LABEL and #parts >= 2 then
        GH.DB:SetCrossGuildLabel(parts[2])
        if GH.UI and GH.UI.OnChannelListChanged then GH.UI:OnChannelListChanged() end

    elseif msgType == MSG_TYPE_LINK_TARGET and #parts >= 2 then
        local target = parts[2]
        GH.DB:SetCrossGuildSendTarget(target ~= "" and target or nil)
    end
end

function Chat:BroadcastAllChannels()
    for id, ch in pairs(GH.DB:GetChats()) do
        self:_BroadcastChannelInfo(id, ch)
    end
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if not C_ChatInfo then return end
    -- Broadcast community links so newly-online guildmates get the current config.
    for id, link in pairs(GH.DB:GetCommunityLinks()) do
        if link.enabled ~= false then
            local payload = table.concat(
                { MSG_TYPE_LINK, id, tostring(link.clubId), tostring(link.streamId), link.label or "" },
                SEPARATOR)
            if #payload <= 250 then
                C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
            end
        end
    end
    local sendTarget = GH.DB:GetCrossGuildSendTarget()
    if sendTarget then
        local payload = table.concat({ MSG_TYPE_LINK_TARGET, tostring(sendTarget) }, SEPARATOR)
        if #payload <= 250 then C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD") end
    end
end

function Chat:_BroadcastChannelInfo(id, ch)
    local memberStr = table.concat(ch.members, ",")
    local payload   = table.concat({ MSG_TYPE_CREATE, id, ch.name, memberStr }, SEPARATOR)
    if #payload <= 250 then
        local C_ChatInfo = rawget(_G, "C_ChatInfo")
        if C_ChatInfo then
            C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
        end
    end
end

-- ── Community link management (officer API) ───────────────────────────────

function Chat:AddCommunityLink(clubId, streamId, label)
    local id   = GH.DB:NewId()
    local data = { clubId = clubId, streamId = streamId, label = label or "Community", enabled = true }
    GH.DB:SaveCommunityLink(id, data)
    Chat._linkedClubs[tostring(clubId)] = { streamId = streamId, label = data.label, id = id }
    Chat:_LoadCommunityHistory(clubId, streamId, Chat._linkedClubs[tostring(clubId)])
    local C_Club = rawget(_G, "C_Club")
    if C_Club and C_Club.RequestMoreMessagesBefore then
        SafeCall(C_Club.RequestMoreMessagesBefore, clubId, streamId, nil, 50)
    end
    local payload = table.concat(
        { MSG_TYPE_LINK, id, tostring(clubId), tostring(streamId), data.label }, SEPARATOR)
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if C_ChatInfo and #payload <= 250 then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
    if GH.UI and GH.UI.OnChannelListChanged then GH.UI:OnChannelListChanged() end
end

function Chat:RemoveCommunityLink(id)
    local link = GH.DB:GetCommunityLinks()[id]
    if not link then return end
    Chat._linkedClubs[tostring(link.clubId)] = nil
    GH.DB:DeleteCommunityLink(id)
    local payload = table.concat({ MSG_TYPE_LINK_DELETE, id }, SEPARATOR)
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if C_ChatInfo and #payload <= 250 then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
    if GH.UI and GH.UI.OnChannelListChanged then GH.UI:OnChannelListChanged() end
end

function Chat:SetCrossGuildLabel(label)
    GH.DB:SetCrossGuildLabel(label)
    local payload = table.concat({ MSG_TYPE_LINK_LABEL, label or "" }, SEPARATOR)
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if C_ChatInfo and #payload <= 250 then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
    if GH.UI and GH.UI.OnChannelListChanged then GH.UI:OnChannelListChanged() end
end

function Chat:SetCrossGuildSendTarget(clubId)
    GH.DB:SetCrossGuildSendTarget(clubId)
    local payload = table.concat({ MSG_TYPE_LINK_TARGET, clubId and tostring(clubId) or "" }, SEPARATOR)
    local C_ChatInfo = rawget(_G, "C_ChatInfo")
    if C_ChatInfo and #payload <= 250 then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
end

-- Returns subscribed non-guild clubs not already linked, for the picker UI.
function Chat:GetAvailableCommunities()
    local C_Club = rawget(_G, "C_Club")
    if not (C_Club and C_Club.GetSubscribedClubs) then return {} end
    local clubs = SafeCall(C_Club.GetSubscribedClubs) or {}
    local linked = GH.DB:GetCommunityLinks()
    local linkedIds = {}
    for _, link in pairs(linked) do linkedIds[tostring(link.clubId)] = true end
    local result = {}
    for _, club in ipairs(clubs) do
        if club.clubType ~= CLUB_TYPE_GUILD and not linkedIds[tostring(club.clubId)] then
            local streams = SafeCall(C_Club.GetStreams, club.clubId) or {}
            if streams[1] then
                result[#result + 1] = {
                    clubId   = club.clubId,
                    streamId = streams[1].streamId,
                    name     = club.name or tostring(club.clubId),
                }
            end
        end
    end
    return result
end
