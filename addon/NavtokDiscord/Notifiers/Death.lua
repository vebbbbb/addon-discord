-- Notifiers/Death.lua: PLAYER_DEAD with zone/subzone and a best-effort killer.
-- Forever has no combat log for addons; the killer is the hostile target at time of death, or
-- the last hostile unit that was targeted while in combat (VERIFY.md: death recap API).
local _, ns = ...
local N = ns.NewNotifier("death")

N.LOGIN_GRACE = 3
N.REPEAT_GRACE = 10 -- Forever fires PLAYER_DEAD twice for one death (seen in the wild)
N.MILESTONE = 50    -- every 50th death gets a "Death #50!" line
N.STAT_TOTAL_DEATHS = 60  -- Statistics: "Total deaths" (Forever's achievement data)
N.STAT_PVP_DEATHS = 1501  -- Statistics: "Total deaths from other players"

local function stat(id)
  if not GetStatistic then return nil end
  local ok, v = pcall(GetStatistic, id)
  return ok and tonumber(v) or nil -- "--" when 0
end

-- Reads the lifetime counters at login, so the first death afterwards is numbered correctly
-- whether or not the statistic already includes it when PLAYER_DEAD fires.
function N:SeedCounters()
  local c = ns.char
  c.deathTotal = stat(N.STAT_TOTAL_DEATHS) or c.deathTotal or 0
  c.pvpDeathTotal = stat(N.STAT_PVP_DEATHS) or c.pvpDeathTotal or 0
end

-- Next value of a lifetime counter: the statistic, but at least the previous value + 1.
local function nextCount(field, statId)
  local c = ns.char
  local n = math.max(stat(statId) or 0, (c[field] or 0) + 1)
  c[field] = n
  return n
end

-- name, isPlayer of a hostile unit
local function hostileName(unit)
  if UnitExists and UnitExists(unit) and UnitCanAttack and UnitCanAttack("player", unit) then
    return UnitName(unit), (UnitIsPlayer and UnitIsPlayer(unit)) and true or false
  end
end

function N:Killer()
  if C_DeathRecap and C_DeathRecap.GetRecapEvents then
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if ok and type(events) == "table" and events[1] and events[1].sourceName then
      return events[1].sourceName
    end
  end
  local name, isPlayer = hostileName("target")
  if name then return name, isPlayer end
  return self.lastHostile, self.lastHostilePlayer
end

local function inPvPInstance()
  if not IsInInstance then return false end
  local _, itype = IsInInstance()
  return itype == "pvp" or itype == "arena"
end

-------------------------------------------------------------------------------
-- Session deaths + flavour lines (Data/DeathLines.lua)
-------------------------------------------------------------------------------
N.SESSION_GAP = 1800   -- offline longer than this before a login = new session
N.HEARTBEAT = 60       -- how often "last seen" is saved while online

local function newSession() return { deaths = 0, decks = {} } end

function N:Session()
  ns.char.session = ns.char.session or newSession()
  return ns.char.session
end

-- PLAYER_ENTERING_WORLD: a real login after more than SESSION_GAP offline starts a new session;
-- /reload, a disconnect or a quick relog keep the count.
function N:OnEnteringWorld(isInitialLogin, isReloadingUi)
  if isInitialLogin and not isReloadingUi then
    local last = ns.char.lastSeen or 0
    if time() - last > N.SESSION_GAP then ns.char.session = newSession() end
  end
  ns.char.lastSeen = time()
end

function N:Heartbeat()
  if ns.char then ns.char.lastSeen = time() end
  ns.After(N.HEARTBEAT, function() N:Heartbeat() end)
end

-- Pool for a session death count: exact 3/5/7, then the highest "from" tier <= n.
function N.PoolFor(n)
  local lines = NavtokDeathLines
  if type(lines) ~= "table" then return nil end
  local exact = lines.exact and lines.exact[tostring(n)]
  if exact then return tostring(n), exact end
  local bestKey, best
  for k, pool in pairs(lines.from or {}) do
    local from = tonumber(k)
    if from and n >= from and (not bestKey or from > tonumber(bestKey)) then bestKey, best = k, pool end
  end
  return bestKey, best
end

local function shuffled(count)
  local t = {}
  for i = 1, count do t[i] = i end
  for i = count, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- Picks the next line of a pool: each pool is a shuffled deck stepped through, so lines do not
-- repeat within a session, and never the same line twice in a row. Returns "key:index".
function N:PickLine(n)
  local key, pool = N.PoolFor(n)
  if not key or type(pool) ~= "table" or #pool == 0 then return nil end
  local s = self:Session()
  local deck = s.decks[key]
  if not deck or deck.size ~= #pool then
    deck = { order = shuffled(#pool), pos = 0, size = #pool }
    s.decks[key] = deck
  end
  for _ = 1, 2 do
    if deck.pos >= #deck.order then
      deck.order, deck.pos = shuffled(#pool), 0
    end
    deck.pos = deck.pos + 1
    local id = key .. ":" .. deck.order[deck.pos]
    if id ~= s.lastLine or #pool == 1 then
      s.lastLine = id
      return id
    end
  end
end

function N:Handle()
  if ns.loginTime and GetTime() - ns.loginTime < self.LOGIN_GRACE then return end
  if self.lastDeath and GetTime() - self.lastDeath < self.REPEAT_GRACE then return end
  self.lastDeath = GetTime()
  local killer, byPlayer = self:Killer()
  local total = nextCount("deathTotal", N.STAT_TOTAL_DEATHS)
  local pvpTotal = byPlayer and nextCount("pvpDeathTotal", N.STAT_PVP_DEATHS) or nil
  local session = self:Session()
  session.deaths = session.deaths + 1
  local n = session.deaths
  local line
  -- 3, 5, 7 exactly, then every death from 10; never during a boss fight (raid wipes)
  if not self.inEncounter and (n == 3 or n == 5 or n == 7 or n >= 10) then line = self:PickLine(n) end
  ns.Emit("death", {
    session = n,
    line = line,
    deathNo = (total % N.MILESTONE == 0) and total or nil,
    pvpDeathNo = (pvpTotal and pvpTotal % N.MILESTONE == 0) and pvpTotal or nil,
    zone = GetRealZoneText and GetRealZoneText() or "",
    subzone = GetSubZoneText and GetSubZoneText() or "",
    killer = killer,
    pvp = (byPlayer or inPvPInstance()) and 1 or nil,
  })
  self.lastHostile, self.lastHostilePlayer = nil, nil
end

function N:Init()
  self:SeedCounters()
  self:Session()
  ns.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi) N:OnEnteringWorld(isInitialLogin, isReloadingUi) end)
  ns.On("PLAYER_LOGOUT", function() ns.char.lastSeen = time() end)
  ns.On("ENCOUNTER_START", function() N.inEncounter = true end)
  ns.On("ENCOUNTER_END", function() N.inEncounter = false end)
  -- first heartbeat only after PLAYER_ENTERING_WORLD has compared the previous "last seen"
  ns.After(N.HEARTBEAT, function() N:Heartbeat() end)
  ns.On("PLAYER_DEAD", function() N:Handle() end)
  ns.On("PLAYER_TARGET_CHANGED", function()
    local name, isPlayer = hostileName("target")
    if name then N.lastHostile, N.lastHostilePlayer = name, isPlayer end
  end)
  ns.On("PLAYER_REGEN_ENABLED", function() N.lastHostile, N.lastHostilePlayer = nil, nil end)
end

function N:Test()
  return { zone = "Stranglethorn Vale", subzone = "Booty Bay", killer = "Bloodsail Swashbuckler" }
end
