-- Notifiers/Dungeon.lua: ENCOUNTER_END success on a dungeon's (or raid's) final boss.
local _, ns = ...
local N = ns.NewNotifier("dungeon")

N.DELAY = 0.5

function N:Handle(encounterID, encounterName, difficultyID, groupSize, success)
  if tonumber(success) ~= 1 and success ~= true then return end
  local entry = ns.Data.FindFinalBoss(tonumber(encounterID), encounterName)
  if not entry then return end
  ns.Emit("dungeon", {
    encounterId = tonumber(encounterID),
    encounter = encounterName or entry.boss,
    instance = entry.instance,
  }, { delay = self.DELAY, priority = true })
end

function N:Init()
  ns.On("ENCOUNTER_END", function(_, ...) N:Handle(...) end)
end

function N:Test()
  return { encounterId = 0, encounter = "Edwin VanCleef", instance = "The Deadmines" }
end
