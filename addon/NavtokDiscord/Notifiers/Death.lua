-- Notifiers/Death.lua: PLAYER_DEAD with zone/subzone and a best-effort killer.
-- Forever has no combat log for addons; the killer is the hostile target at time of death, or
-- the last hostile unit that was targeted while in combat (VERIFY.md: death recap API).
local _, ns = ...
local N = ns.NewNotifier("death")

N.LOGIN_GRACE = 3
N.REPEAT_GRACE = 10 -- Forever fires PLAYER_DEAD twice for one death (seen in the wild)

local function hostileName(unit)
  if UnitExists and UnitExists(unit) and UnitCanAttack and UnitCanAttack("player", unit) then
    return UnitName(unit)
  end
end

function N:Killer()
  if C_DeathRecap and C_DeathRecap.GetRecapEvents then
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if ok and type(events) == "table" and events[1] and events[1].sourceName then
      return events[1].sourceName
    end
  end
  return hostileName("target") or self.lastHostile
end

function N:Handle()
  if ns.loginTime and GetTime() - ns.loginTime < self.LOGIN_GRACE then return end
  if self.lastDeath and GetTime() - self.lastDeath < self.REPEAT_GRACE then return end
  self.lastDeath = GetTime()
  ns.Emit("death", {
    zone = GetRealZoneText and GetRealZoneText() or "",
    subzone = GetSubZoneText and GetSubZoneText() or "",
    killer = self:Killer(),
  })
  self.lastHostile = nil
end

function N:Init()
  ns.On("PLAYER_DEAD", function() N:Handle() end)
  ns.On("PLAYER_TARGET_CHANGED", function()
    local name = hostileName("target")
    if name then N.lastHostile = name end
  end)
  ns.On("PLAYER_REGEN_ENABLED", function() N.lastHostile = nil end)
end

function N:Test()
  return { zone = "Stranglethorn Vale", subzone = "Booty Bay", killer = "Bloodsail Swashbuckler" }
end
