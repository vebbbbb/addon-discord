-- Probe.lua: `/navtok probe` - logs every event of interest plus API return values to chat and
-- NavtokDiscordDB.probe, so the VERIFY.md checklist can be answered from real Forever data.
local _, ns = ...

local P = {}
ns.Probe = P
P.enabled = false

-- Events the probe listens to (registered with pcall: unknown events are reported, not fatal).
P.EVENTS = {
  "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
  "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED", "SCREENSHOT_STARTED",
  "CHAT_MSG_LOOT", "GET_ITEM_INFO_RECEIVED", "CHAT_MSG_SKILL", "PLAYER_LEVEL_UP",
  "UPDATE_FACTION", "CHAT_MSG_COMBAT_FACTION_CHANGE", "PLAYER_DEAD",
  "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "PLAYER_TARGET_CHANGED",
  "UPDATE_BATTLEFIELD_STATUS", "UPDATE_BATTLEFIELD_SCORE",
  "CHAT_MSG_SYSTEM", "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE",
  "CHAT_MSG_BG_SYSTEM_HORDE", "RAID_BOSS_EMOTE",
  "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED",
  -- speculative: candidates for Forever's legacy point challenges (VERIFY.md item 7)
  "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE", "CRITERIA_EARNED", "QUEST_TURNED_IN",
  "LEGACY_POINTS_UPDATED", "LEGACY_CHALLENGE_COMPLETED", "CHALLENGE_COMPLETED",
  "CHAT_MSG_COMBAT_XP_GAIN", "NAME_PLATE_UNIT_ADDED",
}

local function stamp()
  return date and date("%H:%M:%S") or tostring(time())
end

local function fmtArgs(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    out[#out + 1] = tostring(v)
  end
  return table.concat(out, ", ")
end

function P.Log(line)
  line = stamp() .. string.format(" [%.3f] ", GetTime()) .. line
  local buf = ns.db and ns.db.probe
  if buf then
    buf[#buf + 1] = line
    while #buf > ns.MAX_PROBE do table.remove(buf, 1) end
  end
  ns.Print("|cffffcc00probe|r " .. line:gsub("|", "||"))
end

local function safe(fn, ...)
  if type(fn) ~= "function" then return "n/a (missing)" end
  local r = { pcall(fn, ...) }
  if not r[1] then return "error: " .. tostring(r[2]) end
  return fmtArgs(unpack(r, 2))
end

-- Extra API state logged after specific events.
local AFTER = {
  PLAYER_ENTERING_WORLD = function()
    P.Log("IsInInstance -> " .. safe(IsInInstance))
    P.Log("zone -> " .. safe(GetRealZoneText) .. " / " .. safe(GetSubZoneText))
  end,
  UPDATE_BATTLEFIELD_STATUS = function()
    P.Log("GetBattlefieldWinner -> " .. safe(GetBattlefieldWinner))
    for i = 1, (MAX_BATTLEFIELD_QUEUES or 3) do
      P.Log("GetBattlefieldStatus(" .. i .. ") -> " .. safe(GetBattlefieldStatus, i))
    end
    P.Log("GetBattlefieldInstanceRunTime -> " .. safe(GetBattlefieldInstanceRunTime))
  end,
  UPDATE_BATTLEFIELD_SCORE = function()
    P.Log("GetBattlefieldWinner -> " .. safe(GetBattlefieldWinner) ..
      " | UnitFactionGroup -> " .. safe(UnitFactionGroup, "player"))
    local n = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
    P.Log("GetNumBattlefieldScores -> " .. tostring(n))
    for i = 1, n do
      local name = GetBattlefieldScore(i)
      if name and ns.playerName and name:find(ns.playerName, 1, true) == 1 then
        P.Log("own score row " .. i .. " -> " .. safe(GetBattlefieldScore, i))
      end
    end
  end,
  UPDATE_FACTION = function()
    local n = GetNumFactions and GetNumFactions() or 0
    P.Log("GetNumFactions -> " .. n)
    for i = 1, n do
      P.Log("GetFactionInfo(" .. i .. ") -> " .. safe(GetFactionInfo, i))
    end
  end,
  ACHIEVEMENT_EARNED = function()
    P.Log("GetAchievementInfo -> " .. type(GetAchievementInfo))
  end,
  PLAYER_TARGET_CHANGED = function()
    if UnitExists and UnitExists("target") then
      P.Log("target " .. safe(UnitName, "target") .. " class=" .. safe(UnitClassification, "target") ..
        " guid=" .. safe(UnitGUID, "target") .. " tapDenied=" .. safe(UnitIsTapDenied, "target"))
    end
  end,
  PLAYER_DEAD = function()
    P.Log("target -> " .. safe(UnitName, "target") .. " canAttack=" .. safe(UnitCanAttack, "player", "target"))
    P.Log("C_DeathRecap -> " .. tostring(C_DeathRecap ~= nil))
  end,
}

local throttled = { UPDATE_FACTION = 0, UPDATE_BATTLEFIELD_SCORE = 0, UPDATE_BATTLEFIELD_STATUS = 0 }

function P.OnEvent(event, ...)
  P.Log(event .. "(" .. fmtArgs(...) .. ")")
  local after = AFTER[event]
  if after then
    if throttled[event] then
      local now = GetTime()
      if now - throttled[event] < 5 then return end
      throttled[event] = now
    end
    pcall(after)
  end
end

-- Environment dump: one-time API presence / values for VERIFY.md.
function P.Environment()
  P.Log("GetBuildInfo -> " .. safe(GetBuildInfo))
  P.Log("GetPhysicalScreenSize -> " .. safe(GetPhysicalScreenSize))
  P.Log("GetScreenWidth/Height -> " .. safe(GetScreenWidth) .. " / " .. safe(GetScreenHeight))
  if UIParent then
    P.Log("UIParent:GetEffectiveScale -> " .. safe(UIParent.GetEffectiveScale, UIParent) ..
      " GetScale -> " .. safe(UIParent.GetScale, UIParent))
  end
  local h, src = ns.Barcode.PhysicalHeight()
  P.Log("barcode physical height used -> " .. h .. " (" .. src .. ")")
  for _, cvar in ipairs({ "uiScale", "useUiScale", "gxWindowedResolution", "gxFullscreenResolution",
    "screenshotFormat", "screenshotQuality" }) do
    P.Log("GetCVar(" .. cvar .. ") -> " .. safe(GetCVar, cvar))
  end
  for _, api in ipairs({ "Screenshot", "C_Timer", "GetPhysicalScreenSize", "C_DeathRecap",
    "GetBattlefieldWinner", "GetBattlefieldScore", "GetBattlefieldInstanceRunTime",
    "RequestBattlefieldScoreData", "GetFactionInfo", "C_Reputation", "GetItemInfo", "C_Item",
    "GetAchievementInfo", "UnitClassification", "UnitGUID", "UnitIsTapDenied", "C_NamePlate" }) do
    P.Log("API " .. api .. " -> " .. type(_G[api]))
  end
  local unknown = {}
  for e in pairs(ns.unknownEvents) do unknown[#unknown + 1] = e end
  table.sort(unknown)
  P.Log("unknown events -> " .. (#unknown > 0 and table.concat(unknown, ", ") or "none"))
end

local registered = false
function P.SetEnabled(on, quiet)
  if on and not registered then
    registered = true
    for _, e in ipairs(P.EVENTS) do ns.On(e, function() end) end
  end
  P.enabled = on and true or false
  if ns.db then ns.db.probeEnabled = P.enabled end
  if on then
    if not quiet then ns.Print("probe ON - output goes to chat and NavtokDiscordDB.probe") end
    P.Environment()
  elseif not quiet then
    ns.Print("probe OFF")
  end
end

-- `/navtok probe shot`: tests VERIFY item 1/3 - Screenshot() from a timer, no key press.
function P.ShotTest()
  P.Log("shot test: calling Screenshot() from a timer in 1s (no hardware event)")
  ns.After(1, function()
    P.Log("shot test: Screenshot() now, time()=" .. time())
    local ok, err = pcall(Screenshot)
    P.Log("shot test: returned ok=" .. tostring(ok) .. (err and (" err=" .. tostring(err)) or ""))
  end)
end
