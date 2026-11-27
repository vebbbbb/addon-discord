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

function N:Handle()
  if ns.loginTime and GetTime() - ns.loginTime < self.LOGIN_GRACE then return end
  if self.lastDeath and GetTime() - self.lastDeath < self.REPEAT_GRACE then return end
  self.lastDeath = GetTime()
  local killer, byPlayer = self:Killer()
  local total = nextCount("deathTotal", N.STAT_TOTAL_DEATHS)
  local pvpTotal = byPlayer and nextCount("pvpDeathTotal", N.STAT_PVP_DEATHS) or nil
  ns.Emit("death", {
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
