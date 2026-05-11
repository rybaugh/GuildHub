-- GuildHub - Debug logger
-- In-memory ring (lost on reload):   /gh debug on|off   /gh debugdump
-- Persistent session log (survives reloads + character switches, written to GuildHubDB):
--   /gh logdump   — print to chat
--   /gh logclear  — wipe the log
-- The full log is also readable as plain text in:
--   WTF\Account\<ACCOUNT>\SavedVariables\GuildHub.lua  (key: sessionLog)

local GH = GuildHub

local MAX_LOG  = 400
GH._debugLog   = GH._debugLog  or {}
GH._debugMode  = GH._debugMode or false

-- ── In-memory ring ────────────────────────────────────────────────────────

function GH:Debug(cat, fmt, ...)
    local msg
    if select("#", ...) > 0 then
        local ok, result = pcall(string.format, fmt, ...)
        msg = ok and result or (tostring(fmt) .. " [fmt-err]")
    else
        msg = tostring(fmt or "")
    end
    local entry = string.format("[%.2f][%s] %s", GetTime(), cat, msg)
    GH._debugLog[#GH._debugLog + 1] = entry
    if #GH._debugLog > MAX_LOG then table.remove(GH._debugLog, 1) end
    if GH._debugMode then
        print("|cff778899GH-DBG:|r " .. entry)
    end
end

function GH:DumpDebugLog()
    if #GH._debugLog == 0 then
        print("|cff7289daGuildHub:|r Debug log is empty.")
        return
    end
    print("|cff7289daGuildHub Debug Log|r — " .. #GH._debugLog .. " entries:")
    for _, line in ipairs(GH._debugLog) do
        print("|cff778899" .. line .. "|r")
    end
end

-- ── Persistent session log (survives reloads / character switches) ────────
-- Writes to GuildHubDB.sessionLog so data survives reloads.
-- Limit: 2 000 entries to keep SavedVariables file readable.

local MAX_PLOG = 2000

function GH:PLog(fmt, ...)
    local db = rawget(_G, "GuildHubDB")
    if not db then return end
    db.sessionLog = db.sessionLog or {}
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = "(fmt-error: " .. tostring(fmt) .. ")" end
    local entry = string.format("[%.2f] %s", GetTime(), msg)
    db.sessionLog[#db.sessionLog + 1] = entry
    if #db.sessionLog > MAX_PLOG then table.remove(db.sessionLog, 1) end
    if GH._debugMode then
        print("|cff99aacc GH-PLOG:|r " .. entry)
    end
end

function GH:DumpPersistentLog()
    local db = rawget(_G, "GuildHubDB")
    local log = db and db.sessionLog or {}
    if #log == 0 then
        print("|cff7289daGuildHub:|r Persistent log is empty.")
        return
    end
    print("|cff7289daGuildHub Persistent Log|r — " .. #log .. " entries "
          .. "(also in WTF/.../SavedVariables/GuildHub.lua → sessionLog):")
    for _, line in ipairs(log) do
        print("|cff99aacc" .. line .. "|r")
    end
end

function GH:ClearPersistentLog()
    local db = rawget(_G, "GuildHubDB")
    if db then db.sessionLog = {} end
    print("|cff7289daGuildHub:|r Persistent log cleared.")
end

-- ── Helper: safely describe any value for logging ─────────────────────────
-- Works even on WoW secret strings (which error on normal string ops).
function GH:SafeDesc(val)
    if val == nil  then return "nil" end
    local t = type(val)
    if t ~= "string" then return t end
    -- secret strings report as "Unknown" via tostring in WoW 12.x
    local ts = tostring(val)
    if ts == "Unknown" or ts == "" then return "SECRET_STRING" end
    -- try to get a short preview
    local previewOk, preview = pcall(string.sub, val, 1, 40)
    if previewOk and preview then
        return string.format('"%s"(len=%d)', preview, #val)
    end
    return "OPAQUE_STRING"
end
