-- Core.lua: namespace, SavedVariables, event dispatch, event creation + ring buffer.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = "1.1.0"
ns.MAX_EVENTS = 300
ns.MAX_PROBE = 1000

ns.Data = ns.Data or {}
ns.notifiers = {}
ns.notifierOrder = {}
ns.unknownEvents = {}

local DEFAULTS = {
  position = "TOPRIGHT",   -- TOPLEFT | TOPRIGHT | BOTTOMLEFT | BOTTOMRIGHT
  hideChat = true,         -- hide chat frames for the screenshot frame
  hideFrames = {},         -- extra frame names to hide for screenshots (e.g. a chat addon's window)
  debug = false,
  blockSize = 8,           -- barcode module size in PHYSICAL pixels
  mode = "screenshot",     -- "screenshot" (plan A) | "band" (plan B: no Screenshot(), barcode held visible)
  bandHoldSeconds = 0.6,   -- plan B: how long the barcode stays visible
  holdFrames = 1,          -- frames to keep the barcode after Screenshot() before hiding it
  minInterval = 2,         -- seconds between two screenshot events (rate limit)
  -- post types players can switch off (/navtok settings). Deaths are always posted.
  enabled = { loot = true, need = true, skill = true, level = true, reputation = true, dungeon = true,
    bg = true, rare = true, legacy = true, equip = true, recipe = true, quest = true, riding = true,
    dualspec = true, pvp = true },
  levelEvery = 1,          -- post every N levels (the max level is always posted)
  maxLevel = 60,
  equipMinQuality = 3,     -- BoE items equipped: 3 = blue (rare) or better
  recipeMinQuality = 3,    -- recipes learned from an item: 3 = blue or better ...
  recipeMinQualityBy = { [6] = 2, [8] = 2 }, -- ... except Alchemy (6) and Enchanting (8): green
  lootMinQuality = 4,      -- 4 = epic
  needMinQuality = 0,      -- items won on a Need roll: 0 = everything (2 = green or better)
  skillMilestones = { 75, 150, 225, 300 },
  legacyZones = true,      -- also post single-zone "Explore <zone>" legacy steps
  legacyPatterns = { "[Ll]egacy.-[Cc]omplete", "[Cc]omplete.-[Ll]egacy" }, -- fallback only
  rareClassifications = { rare = true, rareelite = true },
}
ns.DEFAULTS = DEFAULTS

-------------------------------------------------------------------------------
-- Output helpers
-------------------------------------------------------------------------------
function ns.Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff5865f2NAVTOK|r " .. tostring(msg))
  end
end

function ns.Debug(msg)
  if ns.settings and ns.settings.debug then ns.Print("|cff999999" .. tostring(msg) .. "|r") end
end

-------------------------------------------------------------------------------
-- Timers (C_Timer when present, OnUpdate fallback otherwise)
-------------------------------------------------------------------------------
local timerFrame = CreateFrame("Frame")
local pendingTimers = {}
timerFrame:SetScript("OnUpdate", function()
  if #pendingTimers == 0 then return end
  local now = GetTime()
  local due = {}
  for i = #pendingTimers, 1, -1 do
    local t = pendingTimers[i]
    if now >= t.at then
      table.remove(pendingTimers, i)
      due[#due + 1] = t
    end
  end
  for i = #due, 1, -1 do
    local ok, err = pcall(due[i].fn)
    if not ok then ns.Debug("timer error: " .. tostring(err)) end
  end
end)

function ns.After(delay, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, fn)
  else
    pendingTimers[#pendingTimers + 1] = { at = GetTime() + delay, fn = fn }
  end
end

-------------------------------------------------------------------------------
-- Event dispatch: several modules may listen to the same event.
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame
local handlers = {}

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then
      ns.unknownEvents[event] = true
      ns.Debug("event not available in this client: " .. event)
    end
  end
  table.insert(handlers[event], fn)
end

function ns.Dispatch(event, ...)
  if ns.Probe and ns.Probe.enabled then ns.Probe.OnEvent(event, ...) end
  local list = handlers[event]
  if not list then return end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, event, ...)
    if not ok then ns.Debug("error in " .. event .. ": " .. tostring(err)) end
  end
end

eventFrame:SetScript("OnEvent", function(_, event, ...) ns.Dispatch(event, ...) end)

-------------------------------------------------------------------------------
-- Notifier registry
-------------------------------------------------------------------------------
-- A notifier is a table with optional :Init() (called at PLAYER_LOGIN) and :Test() (returns
-- fake event data for `/navtok test <type>`, or nil to emit itself).
function ns.NewNotifier(etype)
  local n = { type = etype }
  ns.notifiers[etype] = n
  ns.notifierOrder[#ns.notifierOrder + 1] = etype
  return n
end

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------
function ns.CopyDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then
        local c = {}
        for k2, v2 in pairs(v) do c[k2] = v2 end
        dst[k] = c
      else
        dst[k] = v
      end
    end
  end
  return dst
end

-- Removes WoW escape sequences (colours, links, textures) to get plain text.
function ns.StripCodes(s)
  if type(s) ~= "string" then return s end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
  return s
end

-- Converts a GlobalStrings format ("You receive loot: %sx%d.") into an anchored Lua pattern.
function ns.FormatToPattern(fmt)
  local s = fmt
  s = s:gsub("%%%d+%$s", "\1S"):gsub("%%%d+%$d", "\1D")
  s = s:gsub("%%s", "\1S"):gsub("%%d", "\1D")
  s = s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  s = s:gsub("\1S", "(.+)"):gsub("\1D", "(%%d+)")
  return "^" .. s .. "$"
end

-------------------------------------------------------------------------------
-- SavedVariables
-------------------------------------------------------------------------------
local function InitDB()
  NavtokDiscordDB = NavtokDiscordDB or {}
  local db = NavtokDiscordDB
  db.version = 1
  db.addonVersion = ns.VERSION
  db.settings = ns.CopyDefaults(db.settings or {}, DEFAULTS)
  db.chars = db.chars or {}
  db.probe = db.probe or {}
  ns.db = db
  ns.settings = db.settings
end

local function InitChar()
  local name = UnitName("player")
  local realm = GetRealmName and GetRealmName() or ""
  local _, classFile, classId = UnitClass("player")
  ns.playerName = name
  ns.realm = realm
  ns.classFile = classFile
  ns.classId = classId or (ns.Data.ClassIds and ns.Data.ClassIds[classFile or ""]) or 0
  local key = (name or "?") .. "-" .. (realm or "?")
  ns.charKey = key
  local c = ns.db.chars[key] or {}
  c.name, c.realm, c.class, c.classId = name, realm, classFile, ns.classId
  c.events = c.events or {}
  c.seq = c.seq or 0
  c.rep = c.rep or {}
  c.bg = c.bg or { posted = {} }
  c.bg.posted = c.bg.posted or {}
  ns.db.chars[key] = c
  ns.char = c
end

-------------------------------------------------------------------------------
-- Events -> ring buffer + screenshot queue
-------------------------------------------------------------------------------
-- Appends the JSON line for ev to the per-character ring buffer (last MAX_EVENTS events).
function ns.Log(ev)
  local events = ns.char.events
  events[#events + 1] = ns.Json.Encode(ev)
  while #events > ns.MAX_EVENTS do table.remove(events, 1) end
end

local function publicCopy(ev)
  local c = {}
  for k, v in pairs(ev) do
    if type(k) == "string" and k:sub(1, 1) ~= "_" then c[k] = v end
  end
  return c
end
ns.PublicEvent = publicCopy

-- Creates an event, logs it to SavedVariables and queues its screenshot.
-- opts: delay (seconds before the screenshot), priority (never dropped), test (boolean),
--       candidate (screenshot is kept by the companion but not posted; see Notifiers/Dungeon.lua)
-- Is a post type switched on? kind is the settings name (loot/need/skill/...); deaths always are.
function ns.IsEnabled(kind)
  if kind == "death" then return true end
  local en = ns.settings and ns.settings.enabled
  return not en or en[kind] ~= false
end

-- opts.kind: settings name when it differs from the event type (need wins are "loot" events).
function ns.Emit(etype, data, opts)
  opts = opts or {}
  if not ns.char then return nil end
  if not opts.test and not ns.IsEnabled(opts.kind or etype) then return nil end
  ns.char.seq = (ns.char.seq or 0) + 1
  local ts = time()
  local ev = {
    id = ts .. "." .. ns.char.seq,
    type = etype,
    ts = ts,
    seq = ns.char.seq,
    test = opts.test and true or false,
    candidate = opts.candidate or nil,
    char = ns.playerName,
    realm = ns.realm,
    class = ns.classFile,
    classId = ns.classId,
    level = (data and tonumber(data.level)) or UnitLevel("player"),
    data = data or {},
  }
  if ev.data.level then ev.data.level = nil end
  ns.Log(publicCopy(ev))
  ns.lastEvent = ev
  ns.Debug(("event %s %s"):format(etype, ev.id))
  ns.Screenshot.Enqueue(ev, opts.delay or 0, opts.priority)
  return ev
end

-- Called by Screenshot when the picture was taken: records the shot time for late matching.
function ns.MarkShot(ev, shotTs)
  ev.shot = shotTs
  local events = ns.char.events
  local line = ns.Json.Encode(publicCopy(ev))
  local needle = '"id":"' .. ev.id .. '"'
  for i = #events, 1, -1 do
    if events[i]:find(needle, 1, true) then
      events[i] = line
      return
    end
  end
end

-------------------------------------------------------------------------------
-- Bootstrap
-------------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(_, name)
  if name == ADDON then InitDB() end
end)

ns.On("PLAYER_LOGIN", function()
  if not ns.db then InitDB() end
  InitChar()
  ns.loginTime = GetTime()
  for _, etype in ipairs(ns.notifierOrder) do
    local n = ns.notifiers[etype]
    if n.Init then
      local ok, err = pcall(n.Init, n)
      if not ok then ns.Debug("init " .. etype .. " failed: " .. tostring(err)) end
    end
  end
  if ns.Probe and ns.db.probeEnabled then ns.Probe.SetEnabled(true, true) end
end)
