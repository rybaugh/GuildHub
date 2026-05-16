-- GuildHub - Main
-- Entry point: ADDON_LOADED hook, slash commands, minimap button.

local GH = GuildHub

local CreateFrame     = _G.CreateFrame
local UIParent        = _G.UIParent
local Minimap         = _G.Minimap
local SlashCmdList    = _G.SlashCmdList
local GameTooltip     = _G.GameTooltip

-- ── Guild frame replacement ───────────────────────────────────────────────
-- Intercepts the default guild window and shows GuildHub instead.
-- Uses two paths: the OPEN_GUILD_FRAME event (covers most 12.x UI entry points)
-- and a hooksecurefunc on ToggleGuildFrame (covers the G keybind / social button).
-- The hook calls GH.UI:Toggle() so G key properly opens AND closes GuildHub.

-- In WoW 12.x the guild window is CommunitiesFrame; GuildFrame is legacy.
-- Defer by one tick so the hide runs after WoW finishes showing the frame.
local function HideDefaultGuildFrames()
    for _, name in ipairs({ "GuildFrame", "CommunitiesFrame" }) do
        local f = rawget(_G, name)
        if f and f:IsShown() then f:Hide() end
    end
end

-- Invisible button used as the TOGGLEGUILDTAB keybind redirect target.
-- SetOverrideBindingClick routes the bound key (default G) here so
-- CommunitiesFrame is never opened, eliminating the flash and layout drift.
local _ghKeyBtn

local function GetOrCreateKeyButton()
    if _ghKeyBtn then return _ghKeyBtn end
    _ghKeyBtn = CreateFrame("Button", "GuildHubKeyBindButton", UIParent)
    _ghKeyBtn:SetSize(1, 1)
    _ghKeyBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    _ghKeyBtn:SetAlpha(0)
    _ghKeyBtn:EnableMouse(false)
    _ghKeyBtn:SetScript("OnClick", function() GH.UI:Toggle() end)
    return _ghKeyBtn
end

function GH.ApplyGuildKeybindOverride()
    local btn = GetOrCreateKeyButton()
    local key1, key2 = GetBindingKey("TOGGLEGUILDTAB")
    if key1 then SetOverrideBindingClick(btn, true, key1, "GuildHubKeyBindButton") end
    if key2 then SetOverrideBindingClick(btn, true, key2, "GuildHubKeyBindButton") end
end

function GH.ReleaseGuildKeybindOverride()
    if _ghKeyBtn then ClearOverrideBindings(_ghKeyBtn) end
end

local function SetupGuildFrameReplacement()
    -- Path 1: event fired by Communities button / other non-keybind entry points.
    -- Defer the hide by one tick so WoW finishes showing the frame before we hide it.
    local evFrame = CreateFrame("Frame")
    pcall(function() evFrame:RegisterEvent("OPEN_GUILD_FRAME") end)
    evFrame:RegisterEvent("UPDATE_BINDINGS")
    evFrame:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_BINDINGS" then
            if GH.DB:GetSetting("hideDefaultGuildFrame") ~= false then
                GH.ApplyGuildKeybindOverride()
            end
            return
        end
        if GH.DB:GetSetting("hideDefaultGuildFrame") ~= false then
            C_Timer.After(0, HideDefaultGuildFrames)
        end
        GH.UI:Show()
    end)

    -- Path 2: steal TOGGLEGUILDTAB keybind so CommunitiesFrame is never opened
    if GH.DB:GetSetting("hideDefaultGuildFrame") ~= false then
        GH.ApplyGuildKeybindOverride()
    end

    -- Path 3: ToggleGuildFrame hook as fallback for code-driven calls
    if rawget(_G, "ToggleGuildFrame") then
        hooksecurefunc("ToggleGuildFrame", function()
            if GH.DB:GetSetting("hideDefaultGuildFrame") ~= false then
                HideDefaultGuildFrames()
            end
            GH.UI:Toggle()
        end)
    end
end

-- ── Initialisation ────────────────────────────────────────────────────────

-- Activates the per-guild DB namespace and reloads chat history.
-- Must be idempotent — may be called from PLAYER_LOGIN and GUILD_ROSTER_UPDATE.
local _guildActivated = false
local function ActivateGuildNamespace()
    if _guildActivated then return end
    local currentGuild = GH:GetGuildName()
    if not currentGuild or currentGuild == "No Guild" or currentGuild == "" then return end

    GH.DB:SetActiveGuild(currentGuild)

    -- Reload the guild chat ring from the now-active DB namespace.
    -- The initial load in Chat:Initialize() ran before the guild was known.
    GH.Chat:_LoadSavedGuildHistory()

    -- If FindGuildClub or CLUB_MESSAGE_HISTORY_RECEIVED ran before PLAYER_LOGIN fired,
    -- _LoadFromClubCache already populated Chat.guildMsgs but AddGuildMessage silently
    -- returned false (no active guild). Re-run it now so those messages are persisted.
    if GH.Chat.guildClubId and GH.Chat.guildStreamId then
        GH.Chat:_LoadFromClubCache(GH.Chat.guildClubId, GH.Chat.guildStreamId)
    end

    _guildActivated = true
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == GH.ADDON_NAME then
        GH:Initialize()
        -- Restore persistent debug mode immediately after DB is ready.
        if GH.DB:GetSetting("debugMode") then
            GH._debugMode = true
            print("|cff7289daGuildHub:|r Debug mode is |cff55ff55ON|r (saved in settings).")
        end
        initFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if GH:IsInGuild() then
            local fn = rawget(_G, "GuildRoster")
            if fn then
                fn()
            elseif C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            end
            -- Activate now; if guild name isn't ready yet GUILD_ROSTER_UPDATE will retry.
            ActivateGuildNamespace()
        end
        SetupGuildFrameReplacement()
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Fallback: GetGuildInfo("player") may not be reliable at PLAYER_LOGIN time.
        ActivateGuildNamespace()
        if _guildActivated then
            initFrame:UnregisterEvent("GUILD_ROSTER_UPDATE")
        end
    end
end)

-- ── Minimap button ────────────────────────────────────────────────────────

local function GetMinimapAngle()
    return GH.DB:GetSetting("minimapAngle") or math.rad(225)
end

local function PositionMinimapButton(btn, angle)
    local radius = 74
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius,
        math.sin(angle) * radius)
end

local function CreateMinimapButton()
    local btn = CreateFrame("Button", "GuildHubMinimapButton", UIParent)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(200)
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface/Icons/Achievement_Guild_PerkHappyHour")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Circular mask / highlight ring
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints()
    ring:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    ring:SetAlpha(0.8)

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText("|cff7289daGuildHub|r", 1, 1, 1)
        GameTooltip:AddLine("Click to open / close", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to reposition",    0.6, 0.6, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function() GH.UI:Toggle() end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local s  = Minimap:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            cx, cy = cx / s, cy / s
            PositionMinimapButton(self, math.atan2(cy - my, cx - mx))
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        local mx, my = Minimap:GetCenter()
        local s  = Minimap:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        cx, cy = cx / s, cy / s
        local angle = math.atan2(cy - my, cx - mx)
        GH.DB:SetSetting("minimapAngle", angle)
        PositionMinimapButton(self, angle)
    end)

    PositionMinimapButton(btn, GetMinimapAngle())
    btn:Show()
    return btn
end

-- Delay minimap button creation until UI is ready
C_Timer.After(0, function()
    if not rawget(_G, "GuildHubMinimapButton") then
        CreateMinimapButton()
    end
end)

-- ── Slash commands ────────────────────────────────────────────────────────

local function HandleSlash(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "" or msg == "open" then
        GH.UI:Show()
    elseif msg == "close" then
        GH.UI:Hide()
    elseif msg == "members" then
        GH.UI:Show()
        if GH.UI.window then GH.UI.window.SelectTab("Members") end
    elseif msg == "chat" then
        GH.UI:Show()
        if GH.UI.window then GH.UI.window.SelectTab("Chat") end
    elseif msg == "teams" then
        GH.UI:Show()
        if GH.UI.window then GH.UI.window.SelectTab("Teams") end
    elseif msg == "events" then
        GH.UI:Show()
        if GH.UI.window then GH.UI.window.SelectTab("Events") end
    elseif msg == "lfm" or msg == "recruit" then
        GH.UI:Show()
        if GH.UI.window then GH.UI.window.SelectTab("LFM") end
    elseif msg == "activity" or msg == "log" then
        GH.UI:Show()
        if GH.UI.window then GH.UI.window.SelectTab("Activity") end
    elseif msg == "settings" then
        GH.UI:Show()
        if GH.UI.ToggleSettings then GH.UI:ToggleSettings() end
    elseif msg == "reset" then
        rawset(_G, "GuildHubDB", nil)
        GH.DB._activeGuild = nil
        GH.DB:Initialize()
        local currentGuild = GH:GetGuildName()
        if currentGuild and currentGuild ~= "No Guild" and currentGuild ~= "" then
            GH.DB:SetActiveGuild(currentGuild)
        end
        print("|cff7289daGuildHub:|r Database reset.")
    elseif msg == "debug" or msg == "debug on" then
        GH._debugMode = true
        GH.DB:SetSetting("debugMode", true)
        print("|cff7289daGuildHub:|r Debug mode |cff55ff55ON|r — live logs printing to chat.")
    elseif msg == "debug off" then
        GH._debugMode = false
        GH.DB:SetSetting("debugMode", false)
        print("|cff7289daGuildHub:|r Debug mode |cffff5555OFF|r.")
    elseif msg == "debugdump" then
        GH:DumpDebugLog()
    elseif msg == "logdump" then
        GH:DumpPersistentLog()
    elseif msg == "logclear" then
        GH:ClearPersistentLog()
    else
        print("|cff7289daGuildHub|r commands:")
        print("  /gh               — open window")
        print("  /gh members       — jump to Members tab")
        print("  /gh activity      — jump to Activity log tab  (also: /gh log)")
        print("  /gh chat          — jump to Chat tab")
        print("  /gh teams         — jump to Teams tab")
        print("  /gh events        — jump to Events tab")
        print("  /gh lfm           — jump to LFM tab (also: /gh recruit)")
        print("  /gh settings      — open settings")
        print("  /gh reset         — reset all saved data")
        print("  /gh debug [on|off] — toggle live debug logging")
        print("  /gh debugdump     — dump full debug log to chat")
        print("  /roster           — shortcut to open Members tab")
    end
end

rawset(_G, "SLASH_GUILDHUB1", "/gh")
rawset(_G, "SLASH_GUILDHUB2", "/guildhub")
SlashCmdList["GUILDHUB"] = HandleSlash

-- /roster opens GuildHub Members tab directly
rawset(_G, "SLASH_GUILDHUB_ROSTER1", "/roster")
SlashCmdList["GUILDHUB_ROSTER"] = function()
    GH.UI:Show()
    if GH.UI.window then GH.UI.window.SelectTab("Members") end
end
