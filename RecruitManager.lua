-- GuildHub - LFM Manager (Looking for More)
-- Guild members post groups when they need more players.
-- Supports Dungeons, Raids, Battlegrounds, and Arena.
-- Rewards guild members with Guild Points for participating.

local GH      = GuildHub
local Recruit = GH.Recruit

local SEP          = "\30"
local MSG_POST     = "LP"
local MSG_SIGNUP   = "LS"
local MSG_DEL      = "LD"    -- post deleted / group full
local MSG_PTS_UPD  = "LPU"   -- single-player points total (name, newTotal)
local MSG_PTS_SYN  = "LPA"   -- batch points sync (name:pts,name:pts,...)

local POINTS_SIGNUP     = 5
local POINTS_GOT_SIGNUP = 2

-- ──────────────────────────────────────────────────────────
-- Constants (exposed for UI access)
-- ──────────────────────────────────────────────────────────

Recruit.ACTIVITY_TYPES    = { "Dungeon", "Raid", "Battleground", "Arena" }
Recruit.POINTS_SIGNUP     = POINTS_SIGNUP
Recruit.POINTS_GOT_SIGNUP = POINTS_GOT_SIGNUP
Recruit.EXPIRE_SECS       = 30 * 60   -- posts expire after 30 minutes

Recruit.ACTIVITY_COLORS = {
    Dungeon      = { 0.42, 0.65, 1.00 },
    Raid         = { 1.00, 0.55, 0.15 },
    Battleground = { 0.90, 0.25, 0.25 },
    Arena        = { 0.72, 0.30, 0.95 },
}

-- Per-role display colours used in the listings
Recruit.ROLE_COLORS = {
    Tank             = { 0.20, 0.55, 1.00 },
    Healer           = { 0.20, 0.80, 0.35 },
    DPS              = { 0.90, 0.28, 0.28 },
    ["Melee DPS"]    = { 0.88, 0.42, 0.12 },
    ["Ranged DPS"]   = { 0.72, 0.38, 0.90 },
    Any              = { 0.55, 0.55, 0.65 },
}

-- One-letter abbreviations for the compact slot display
Recruit.ROLE_ABBR = {
    Tank           = "T",
    Healer         = "H",
    DPS            = "D",
    ["Melee DPS"]  = "M",
    ["Ranged DPS"] = "R",
    Any            = "?",
}

-- Fixed composition for Dungeons (always 1T 1H 3D)
Recruit.DUNGEON_NEEDS = {
    { role = "Tank",   count = 1 },
    { role = "Healer", count = 1 },
    { role = "DPS",    count = 3 },
}

-- ──────────────────────────────────────────────────────────
-- Initialization
-- ──────────────────────────────────────────────────────────

function Recruit:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, event, prefix, message)
        if event == "CHAT_MSG_ADDON" and prefix == GH.ADDON_PREFIX then
            Recruit:OnAddonMessage(message)
        end
    end)
    Recruit.eventFrame = frame

    -- Broadcast known points shortly after login so peers sync without needing GD|SA.
    C_Timer.After(10, function() Recruit:BroadcastAllPoints() end)
end

-- ──────────────────────────────────────────────────────────
-- Needs encoding / decoding
-- Compact wire format:  "Tank:1,Healer:1,DPS:3"
-- ──────────────────────────────────────────────────────────

local function EncodeNeeds(needs)
    local parts = {}
    for _, n in ipairs(needs) do
        parts[#parts + 1] = (n.role or "Any") .. ":" .. tostring(n.count or 0)
    end
    return table.concat(parts, ",")
end

local function DecodeNeeds(str)
    local needs = {}
    if not str or str == "" then return needs end
    for entry in (str .. ","):gmatch("([^,]+),") do
        local role, cnt = entry:match("^(.+):(%d+)$")
        if role and cnt then
            needs[#needs + 1] = { role = role, count = tonumber(cnt) or 0 }
        end
    end
    return needs
end

-- ──────────────────────────────────────────────────────────
-- Data normalisation (handles old posts that used the flat slot model)
-- ──────────────────────────────────────────────────────────

local function NormalizePost(id, raw)
    local actType = raw.activityType or "Dungeon"
    local out = {
        id           = id,
        activityType = actType,
        instanceName = raw.instanceName or nil,
        difficulty   = raw.difficulty   or nil,
        title        = raw.title or (actType .. " LFM"),
        body         = raw.body  or "",
        author       = raw.author or "?",
        ts           = raw.ts    or 0,
        needs        = {},
        signups      = raw.signups or {},
    }

    -- Needs: detect old [{role, (no count)}] vs new [{role, count}] format
    if raw.needs and #raw.needs > 0 then
        if raw.needs[1].count then
            out.needs = raw.needs
        else
            -- Old format: one entry per slot, group by role
            local order, counts = {}, {}
            for _, n in ipairs(raw.needs) do
                local r = n.role or "Any"
                if not counts[r] then counts[r] = 0; order[#order+1] = r end
                counts[r] = counts[r] + 1
            end
            for _, r in ipairs(order) do
                out.needs[#out.needs+1] = { role = r, count = counts[r] }
            end
        end
    elseif out.activityType == "Dungeon" then
        out.needs = { {role="Tank",count=1}, {role="Healer",count=1}, {role="DPS",count=3} }
    else
        local slots = raw.slotsNeeded or 1
        out.needs = { { role = "Any", count = slots } }
    end

    -- Signups: migrate old filled = {[slotIndex] = {name, ts}} → signups [{name, role, ts}]
    if #out.signups == 0 and raw.filled then
        for _, entry in pairs(raw.filled) do
            if type(entry) == "table" and entry.name then
                out.signups[#out.signups+1] = { name = entry.name, role = "Any", ts = entry.ts or 0 }
            end
        end
    end

    return out
end

-- ──────────────────────────────────────────────────────────
-- Data access
-- ──────────────────────────────────────────────────────────

function Recruit:GetAll()
    local out  = {}
    local now  = GH:GetTimestamp() or time()
    for id, raw in pairs(GH.DB:GetRecruitPosts()) do
        if now - (raw.ts or 0) <= self.EXPIRE_SECS then
            out[#out + 1] = NormalizePost(id, raw)
        end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

-- Delete posts older than EXPIRE_SECS and broadcast deletions for own posts.
function Recruit:CleanupExpired()
    if not GH:IsInGuild() then return end
    local now = GH:GetTimestamp() or time()
    local me  = GH:GetPlayerName()
    for id, raw in pairs(GH.DB:GetRecruitPosts()) do
        if now - (raw.ts or 0) > self.EXPIRE_SECS then
            if (raw.author or "") == me then
                local payload = table.concat({ MSG_DEL, id }, SEP)
                if #payload <= 250 then
                    pcall(C_ChatInfo.SendAddonMessage, GH.ADDON_PREFIX, payload, "GUILD")
                end
            end
            GH.DB:DeleteRecruitPost(id)
        end
    end
end

-- Total slots across all roles
function Recruit:TotalSlots(post)
    local n = 0
    for _, need in ipairs(post.needs or {}) do n = n + (need.count or 0) end
    return n
end

-- Number of signups for a specific role
function Recruit:FilledForRole(post, role)
    local n = 0
    for _, s in ipairs(post.signups or {}) do
        if s.role == role then n = n + 1 end
    end
    return n
end

-- Open slots remaining for a specific role
function Recruit:OpenSlotsForRole(post, role)
    local needed = 0
    for _, need in ipairs(post.needs or {}) do
        if need.role == role then needed = need.count or 0; break end
    end
    return math.max(0, needed - self:FilledForRole(post, role))
end

-- Total open slots across all roles
function Recruit:TotalOpen(post)
    local n = 0
    for _, need in ipairs(post.needs or {}) do
        n = n + self:OpenSlotsForRole(post, need.role)
    end
    return n
end

-- List of roles that still have at least one open slot
function Recruit:GetOpenRoles(post)
    local roles = {}
    for _, need in ipairs(post.needs or {}) do
        if self:OpenSlotsForRole(post, need.role) > 0 then
            roles[#roles + 1] = need.role
        end
    end
    return roles
end

-- True if the current player has signed up for this post
function Recruit:HasSignedUp(post)
    local me = GH:GetPlayerName()
    for _, s in ipairs(post.signups or {}) do
        if s.name == me then return true end
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- Guild chat + Group Finder helpers
-- ──────────────────────────────────────────────────────────

-- Build the compact role string used in both guild chat and LFG descriptions.
-- e.g.  "1 Tank · 1 Healer · 3 DPS"
local function RoleString(needs)
    local parts = {}
    for _, need in ipairs(needs or {}) do
        if (need.count or 0) > 0 then
            parts[#parts + 1] = tostring(need.count) .. " " .. (need.role or "Any")
        end
    end
    return table.concat(parts, " · ")
end

-- Post an announcement to guild chat.
local function AnnounceToGuildChat(data)
    if not GH:IsInGuild() then return end
    local sendFn = rawget(_G, "SendChatMessage")
    if not sendFn then return end

    local tag      = "[LFM]"
    local instTag  = data.instanceName and ("[" .. data.instanceName .. "]")
                     or ("[" .. (data.activityType or "LFM") .. "]")
    local roleStr  = RoleString(data.needs)
    local msg      = tag .. " " .. instTag .. " " .. roleStr
    if data.body and data.body ~= "" then
        msg = msg .. " — " .. data.body
    end

    pcall(sendFn, msg, "GUILD")
end

-- Open the Premade Groups frame so the player can create a listing manually.
-- We intentionally avoid manipulating internal child frames (CategorySelection,
-- EntryCreation) because doing so bypasses Blizzard's state machine and corrupts
-- the frame layout.  The print message guides the player from here.
local function CreateGroupFinderListing(data)
    local at = data.activityType
    if at ~= "Dungeon" and at ~= "Raid" then return end

    local pvef = rawget(_G, "PVEFrame")
    if pvef then
        ShowUIPanel(pvef)
        local showFn = rawget(_G, "PVEFrame_ShowFrame")
        if showFn then pcall(showFn, "GroupFinderFrame") end
    end

    print("|cff7289daGuildHub LFM:|r Premade Groups opened — select your "
        .. at:lower() .. " and click |cffF2CF00Start a Group|r to publish.")
end

-- ──────────────────────────────────────────────────────────
-- Actions
-- ──────────────────────────────────────────────────────────

-- Track which post (if any) created the current Group Finder listing.
Recruit._activeLFGPostId = nil

-- Post a new LFM group.
-- needs: array of { role, count }  (auto-filled for Dungeon if omitted)
-- sendGuildChat: true (default) → announce to guild chat; false → silent
-- difficulty: e.g. "Mythic+", "Heroic", "Mythic" — optional
function Recruit:Post(activityType, description, needs, instanceName, sendGuildChat, difficulty)
    needs = (needs and #needs > 0) and needs or {}
    if sendGuildChat == nil then sendGuildChat = true end
    if not difficulty then
        difficulty = (activityType == "Dungeon") and "Mythic+" or
                     (activityType == "Raid")    and "Mythic"  or nil
    end

    local id   = GH.DB:NewId()
    local name = GH:GetPlayerName()
    local data = {
        activityType = activityType,
        instanceName = instanceName or nil,
        difficulty   = difficulty   or nil,
        title        = instanceName or (activityType .. " LFM"),
        body         = description or "",
        needs        = needs,
        signups      = {},
        author       = name,
        ts           = GH:GetTimestamp(),
        filled       = {},  -- kept for legacy compat
    }
    GH.DB:SaveRecruitPost(id, data)
    self:_BroadcastPost(id, data)

    -- Announce to guild chat (only if the checkbox was ticked)
    if sendGuildChat then AnnounceToGuildChat(data) end

    -- List in the in-game Group Finder (Dungeon / Raid only).
    -- Must run synchronously to stay within the button-click hardware event.
    if activityType == "Dungeon" or activityType == "Raid" then
        CreateGroupFinderListing(data)
        self._activeLFGPostId = id
    end

    return id
end

function Recruit:Delete(id)
    GH.DB:DeleteRecruitPost(id)
    -- Remove the Group Finder listing if we created it for this post
    if self._activeLFGPostId == id then
        local removeFn = rawget(C_LFGList, "RemoveListing")
        if removeFn then pcall(removeFn) end
        self._activeLFGPostId = nil
    end
    if GH.UI and GH.UI.OnLFMUpdated then GH.UI:OnLFMUpdated() end
end

-- Called after every signup; delists the post when all slots are filled.
-- Only the author broadcasts the deletion so peers who missed earlier signups clean up.
function Recruit:_AutoDelistIfFull(postId, raw)
    local post = NormalizePost(postId, raw)
    if self:TotalOpen(post) > 0 then return end
    self:Delete(postId)
    if post.author == GH:GetPlayerName() then
        local payload = table.concat({ MSG_DEL, postId }, SEP)
        if #payload <= 250 then
            C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
        end
        local label = post.instanceName or post.activityType or "group"
        print("|cff7289daGuildHub LFM:|r Your " .. label .. " group is full — listing removed.")
    end
end

-- Sign up the current player for `role` in post `postId`.
function Recruit:Signup(postId, role)
    local posts = GH.DB:GetRecruitPosts()
    local raw   = posts[postId]
    if not raw then return false end

    local post = NormalizePost(postId, raw)
    local me   = GH:GetPlayerName()

    if post.author == me          then return false end
    if self:HasSignedUp(post)     then return false end
    if self:OpenSlotsForRole(post, role) <= 0 then return false end

    local entry = { name = me, role = role, ts = GH:GetTimestamp() }

    -- Persist to DB (merge back)
    raw.signups = raw.signups or {}
    raw.signups[#raw.signups + 1] = entry
    GH.DB:SaveRecruitPost(postId, raw)

    GH.DB:AddLFMPoints(me, POINTS_SIGNUP)
    self:_BroadcastSignup(postId, me, role, entry.ts, GH.DB:GetLFMPoints(me))

    if GH.UI and GH.UI.OnLFMUpdated then GH.UI:OnLFMUpdated() end
    self:_AutoDelistIfFull(postId, raw)
    return true
end

-- Re-broadcast all stored posts (login sync)
function Recruit:BroadcastAll()
    if not GH:IsInGuild() then return end
    local i = 0
    for id, raw in pairs(GH.DB:GetRecruitPosts()) do
        i = i + 1
        C_Timer.After(i * 0.3, function()
            self:_BroadcastPost(id, raw)
        end)
    end
    -- Piggyback points sync onto the existing login sync broadcast.
    C_Timer.After((i + 1) * 0.3, function() self:BroadcastAllPoints() end)
end

-- Broadcast every known player's point total so peers can merge (MAX).
-- Chunks into ≤250-byte messages automatically.
function Recruit:BroadcastAllPoints()
    if not GH:IsInGuild() then return end
    local all = GH.DB:GetAllLFMPoints()
    local entries = {}
    for name, pts in pairs(all) do
        if (pts or 0) > 0 then
            entries[#entries + 1] = name .. ":" .. tostring(pts)
        end
    end
    if #entries == 0 then return end

    local prefix = MSG_PTS_SYN .. SEP
    local chunk, cLen = {}, #prefix
    for _, entry in ipairs(entries) do
        local cost = #entry + (#chunk > 0 and 1 or 0)  -- +1 for comma after first
        if cLen + cost > 250 then
            C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, prefix .. table.concat(chunk, ","), "GUILD")
            chunk, cLen = {}, #prefix
            cost = #entry
        end
        chunk[#chunk + 1] = entry
        cLen = cLen + cost
    end
    if #chunk > 0 then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, prefix .. table.concat(chunk, ","), "GUILD")
    end
end

-- ──────────────────────────────────────────────────────────
-- Networking
-- ──────────────────────────────────────────────────────────

function Recruit:_BroadcastPost(id, data)
    local needsStr = EncodeNeeds(data.needs or {})
    local payload  = table.concat({
        MSG_POST,
        id,
        data.author        or "",
        tostring(data.ts   or 0),
        data.activityType  or "Dungeon",
        data.body          or "",
        needsStr,
        data.instanceName  or "",
        data.difficulty    or "",
    }, SEP)
    if #payload <= 250 then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
end

function Recruit:_BroadcastSignup(postId, playerName, role, ts, newPts)
    local payload = table.concat({
        MSG_SIGNUP, postId, playerName, role, tostring(ts or 0), tostring(newPts or 0)
    }, SEP)
    if #payload <= 250 then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
end

function Recruit:_BroadcastPoints(name, pts)
    local payload = table.concat({ MSG_PTS_UPD, name, tostring(pts or 0) }, SEP)
    if #payload <= 250 then
        C_ChatInfo.SendAddonMessage(GH.ADDON_PREFIX, payload, "GUILD")
    end
end

function Recruit:OnAddonMessage(payload)
    local parts = {}
    for p in (payload .. SEP):gmatch("([^" .. SEP .. "]*)" .. SEP) do
        parts[#parts + 1] = p
    end
    if #parts < 1 then return end
    local msgType = parts[1]

    if msgType == MSG_POST and #parts >= 6 then
        local id           = parts[2]
        local author       = parts[3]
        local ts           = tonumber(parts[4]) or 0
        local actType      = parts[5]
        local body         = parts[6]
        local needs        = DecodeNeeds(parts[7] or "")
        local instanceName = (parts[8] and parts[8] ~= "") and parts[8] or nil
        local difficulty   = (parts[9] and parts[9] ~= "") and parts[9] or nil
        if #needs == 0 then
            needs = actType == "Dungeon"
                and { {role="Tank",count=1}, {role="Healer",count=1}, {role="DPS",count=3} }
                or  { {role="Any", count=1} }
        end
        if not GH.DB:GetRecruitPosts()[id] then
            GH.DB:SaveRecruitPost(id, {
                activityType = actType,
                instanceName = instanceName,
                difficulty   = difficulty,
                title        = instanceName or (actType .. " LFM"),
                body         = body,
                needs        = needs,
                signups      = {},
                author       = author,
                ts           = ts,
                filled       = {},
            })
            if GH.UI and GH.UI.OnLFMUpdated then GH.UI:OnLFMUpdated() end
        end

    elseif msgType == MSG_SIGNUP and #parts >= 4 then
        local postId    = parts[2]
        local signer    = parts[3]
        local role      = parts[4]
        local sigTs     = tonumber(parts[5]) or 0
        local signerPts = tonumber(parts[6])

        -- Merge the signer's authoritative point total embedded in the message.
        if signerPts and signerPts > 0 then
            GH.DB:MergeLFMPoints(signer, signerPts)
        end

        local raw = GH.DB:GetRecruitPosts()[postId]
        if raw then
            local post = NormalizePost(postId, raw)
            if not self:HasSignedUp(post) or post.author ~= signer then
                raw.signups = raw.signups or {}
                -- Only add if not already present
                local already = false
                for _, s in ipairs(raw.signups) do
                    if s.name == signer then already = true; break end
                end
                if not already then
                    raw.signups[#raw.signups + 1] = { name = signer, role = role, ts = sigTs }
                    GH.DB:SaveRecruitPost(postId, raw)
                    if raw.author == GH:GetPlayerName() then
                        GH.DB:AddLFMPoints(GH:GetPlayerName(), POINTS_GOT_SIGNUP)
                        -- Push updated author total to all peers immediately.
                        self:_BroadcastPoints(GH:GetPlayerName(),
                            GH.DB:GetLFMPoints(GH:GetPlayerName()))
                    end
                    if GH.UI and GH.UI.OnLFMUpdated then GH.UI:OnLFMUpdated() end
                    self:_AutoDelistIfFull(postId, raw)
                end
            end
        end

    elseif msgType == MSG_PTS_UPD and #parts >= 3 then
        local name = parts[2]
        local pts  = tonumber(parts[3]) or 0
        if name ~= "" and pts > 0 then
            GH.DB:MergeLFMPoints(name, pts)
            if GH.UI and GH.UI.OnLFMUpdated then GH.UI:OnLFMUpdated() end
        end

    elseif msgType == MSG_PTS_SYN and #parts >= 2 then
        local changed = false
        for entry in (parts[2] .. ","):gmatch("([^,]+),") do
            local name, pts = entry:match("^(.+):(%d+)$")
            pts = tonumber(pts)
            if name and pts and pts > 0 then
                GH.DB:MergeLFMPoints(name, pts)
                changed = true
            end
        end
        if changed and GH.UI and GH.UI.OnLFMUpdated then GH.UI:OnLFMUpdated() end

    elseif msgType == MSG_DEL and #parts >= 2 then
        local postId = parts[2]
        if GH.DB:GetRecruitPosts()[postId] then
            self:Delete(postId)
        end
    end
end
