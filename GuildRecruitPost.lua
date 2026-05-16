-- GuildHub - Guild Recruitment Manager
-- Lets officers post the guild to the in-game Guild/Club Finder and manage applicants.

local GH           = GuildHub
local GuildRecruit = GH.GuildRecruit

GuildRecruit.FOCUS_TYPES = { "Raids", "Mythic+", "PvP", "Casual", "Roleplay", "Social" }
GuildRecruit.ROLE_TYPES  = { "Tank", "Healer", "DPS", "Caster", "Melee", "Ranged" }
GuildRecruit.LANGUAGES   = { "English", "German", "French", "Spanish", "Russian", "Korean", "Chinese" }

-- ──────────────────────────────────────────────────────────
-- WoW API helpers
-- ──────────────────────────────────────────────────────────

-- Returns the current player's guild club ID, or nil.
local function GetGuildClubId()
    if not rawget(_G, "C_Club") or not C_Club.GetSubscribedClubs then return nil end
    local ok, clubs = pcall(C_Club.GetSubscribedClubs)
    if not ok or not clubs then return nil end
    local guildType = rawget(_G, "Enum") and Enum.ClubType and Enum.ClubType.Guild or 2
    for _, club in ipairs(clubs) do
        if club.clubType == guildType then
            return club.clubId
        end
    end
    return nil
end

-- True when C_ClubFinder is available (WoW 10+).
function GuildRecruit:HasClubFinderAPI()
    return rawget(_G, "C_ClubFinder") ~= nil
        and C_ClubFinder.SetClubRecruitmentSettings ~= nil
end

-- ──────────────────────────────────────────────────────────
-- Initialization
-- ──────────────────────────────────────────────────────────

function GuildRecruit:Initialize()
    local f = CreateFrame("Frame")
    -- Listen for Club Finder events if the API is present.
    pcall(function()
        f:RegisterEvent("CLUB_FINDER_RECRUITMENT_SETTINGS_CHANGED")
        f:RegisterEvent("CLUB_FINDER_APPLICANT_LIST_UPDATED")
    end)
    f:SetScript("OnEvent", function(_, event)
        if GH.UI and GH.UI.OnGuildRecruitUpdated then
            GH.UI:OnGuildRecruitUpdated()
        end
    end)
    self._eventFrame = f
end

-- ──────────────────────────────────────────────────────────
-- Settings CRUD
-- ──────────────────────────────────────────────────────────

function GuildRecruit:GetSettings()
    return GH.DB:GetGuildRecruitSettings()
end

function GuildRecruit:SaveSettings(data)
    data.updatedAt = GH:GetTimestamp()
    data.updatedBy = GH:GetPlayerName()
    GH.DB:SaveGuildRecruitSettings(data)
end

-- ──────────────────────────────────────────────────────────
-- Post to in-game Guild/Club Finder
-- Uses C_ClubFinder when available; otherwise prints a hint.
-- ──────────────────────────────────────────────────────────

function GuildRecruit:PostToFinder(settings)
    if not settings.listed then
        self:_SetFinderListed(false, "")
        return
    end
    self:_SetFinderListed(true, settings.message or "")
end

function GuildRecruit:_SetFinderListed(active, message)
    if not self:HasClubFinderAPI() then return end
    local clubId = GetGuildClubId()
    if not clubId then return end
    pcall(function()
        -- C_ClubFinder.SetClubRecruitmentSettings signature may vary by patch;
        -- wrap in pcall so a wrong signature doesn't break anything.
        C_ClubFinder.SetClubRecruitmentSettings(clubId, {
            recruitmentMessage = active and (message or "") or "",
            active             = active,
        })
    end)
end

-- ──────────────────────────────────────────────────────────
-- Applicants
-- ──────────────────────────────────────────────────────────

-- Request a fresh list from the server (async; fires CLUB_FINDER_APPLICANT_LIST_UPDATED).
function GuildRecruit:RequestApplicants()
    if not self:HasClubFinderAPI() then return end
    local clubId = GetGuildClubId()
    if not clubId then return end
    pcall(function()
        if C_ClubFinder.RequestApplicantList then
            C_ClubFinder.RequestApplicantList(clubId)
        end
    end)
end

-- Returns a table of applicant records {id, name, level, class, role, comment, ts}.
function GuildRecruit:GetApplicants()
    local out = {}
    if not self:HasClubFinderAPI() then return out end
    local clubId = GetGuildClubId()
    if not clubId then return out end
    pcall(function()
        local raw
        if C_ClubFinder.GetApplicants then
            raw = C_ClubFinder.GetApplicants(clubId)
        elseif C_ClubFinder.GetApplicantList then
            raw = C_ClubFinder.GetApplicantList(clubId)
        end
        if not raw then return end
        for _, app in ipairs(raw) do
            out[#out + 1] = {
                id      = app.applicantId or app.id or tostring(#out + 1),
                name    = app.name or app.playerName or "?",
                level   = app.level or 0,
                class   = (app.classFileName or app.class or ""):upper(),
                role    = app.role or "",
                comment = app.comment or app.message or "",
                ts      = app.applicationDate or app.ts or 0,
            }
        end
    end)
    return out
end

function GuildRecruit:AcceptApplicant(applicantId)
    if not self:HasClubFinderAPI() then return false end
    local clubId = GetGuildClubId()
    if not clubId then return false end
    local ok = pcall(function()
        C_ClubFinder.ApplicantResponse(clubId, applicantId, true)
    end)
    return ok
end

function GuildRecruit:DeclineApplicant(applicantId)
    if not self:HasClubFinderAPI() then return false end
    local clubId = GetGuildClubId()
    if not clubId then return false end
    local ok = pcall(function()
        C_ClubFinder.ApplicantResponse(clubId, applicantId, false)
    end)
    return ok
end

-- ──────────────────────────────────────────────────────────
-- Fallback: open WoW's native guild/club finder window
-- ──────────────────────────────────────────────────────────

function GuildRecruit:OpenNativeWindow()
    pcall(function()
        -- Try Club Finder frame (modern WoW)
        local cf = rawget(_G, "ClubFinderFrame") or rawget(_G, "GuildFinderFrame")
        if cf then ShowUIPanel(cf); return end
        -- Last resort: toggle the guild frame on the recruitment tab
        if rawget(_G, "ToggleGuildFrame") then ToggleGuildFrame(5) end
    end)
end
