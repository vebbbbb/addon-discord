-- Notifiers/Level.lua: PLAYER_LEVEL_UP. Screenshot 0.5 s later so the level-up glow is visible.
local _, ns = ...
local N = ns.NewNotifier("level")

N.DELAY = 0.5

function N:Handle(newLevel)
  ns.Emit("level", { level = tonumber(newLevel), zone = GetRealZoneText and GetRealZoneText() or "" },
    { delay = self.DELAY, priority = true })
end

function N:Init()
  ns.On("PLAYER_LEVEL_UP", function(_, level) N:Handle(level) end)
end

function N:Test()
  ns.Emit("level", { level = math.min((UnitLevel("player") or 1) + 1, 60), zone = GetRealZoneText() },
    { delay = self.DELAY, priority = true, test = true })
end
