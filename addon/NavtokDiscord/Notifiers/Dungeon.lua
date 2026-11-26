-- Notifiers/Dungeon.lua: dungeon and raid clears. One simple rule:
--  * a KNOWN final boss dies (Data/Dungeons.lua, ids from the game data) -> post right away;
--  * otherwise, when you LEAVE an instance where at least one boss died, post one summary
--    ("Blackmaw Hold: 5 bosses defeated") that uses the screenshot of the last boss kill.
-- Every boss kill in such a run takes a "candidate" screenshot (flag C): the companion keeps it
-- without posting; the summary names it with shotSeq. This covers new Forever dungeons/raids and
-- skipped optional bosses without a list. The run is kept in SavedVariables (survives /reload).
local _, ns = ...
local N = ns.NewNotifier("dungeon")

N.DELAY = 0.5

local function where()
  if not GetInstanceInfo then return nil end
  local name, itype, _, _, _, _, _, mapId = GetInstanceInfo()
  if itype == "party" or itype == "raid" then
    return { map = tostring(mapId or name), instance = name, kind = itype == "raid" and "raid" or "dungeon" }
  end
end

function N:Run() return ns.char and ns.char.run end

-- Posts the summary of a finished run (only if no known final boss was posted for it).
function N:Finish()
  local run = self:Run()
  ns.char.run = nil
  if not run or run.done or (run.bosses or 0) == 0 or not run.lastSeq then return end
  ns.Emit("dungeon", {
    encounter = run.lastBoss, instance = run.instance, bosses = run.bosses,
    duration = math.max(0, (run.lastAt or time()) - run.start), shotSeq = run.lastSeq,
  }, { priority = true })
end

function N:Zone()
  local here = where()
  local run = self:Run()
  if run and (not here or here.map ~= run.map) then
    self:Finish()
    run = nil
  end
  if here and not run then
    ns.char.run = { map = here.map, instance = here.instance, kind = here.kind, start = time(), bosses = 0 }
  end
end

function N:Handle(encounterID, encounterName, difficultyID, groupSize, success)
  if tonumber(success) ~= 1 and success ~= true then return end
  self:Zone()
  local run = self:Run()
  local id = tonumber(encounterID)
  local entry = ns.Data.FindFinalBoss(id, encounterName)
  if run then
    run.bosses = run.bosses + 1
    run.lastAt = time()
  end
  if entry then
    if run then run.done = true end
    ns.Emit("dungeon", {
      encounterId = id, encounter = encounterName or entry.boss, instance = entry.instance,
      bosses = run and run.bosses or nil, duration = run and (time() - run.start) or nil,
    }, { delay = self.DELAY, priority = true })
  elseif run and not run.done then
    local ev = ns.Emit("dungeon", { encounterId = id, encounter = encounterName, instance = run.instance },
      { delay = self.DELAY, priority = true, candidate = true })
    if ev then
      run.lastSeq, run.lastBoss = ev.seq, encounterName
    end
  end
end

function N:Init()
  ns.On("ENCOUNTER_END", function(_, ...) N:Handle(...) end)
  ns.On("PLAYER_ENTERING_WORLD", function() N:Zone() end)
  ns.On("ZONE_CHANGED_NEW_AREA", function() N:Zone() end)
  self:Zone()
end

function N:Test()
  return { encounterId = 2747, encounter = "Edwin VanCleef", instance = "Deadmines", bosses = 8, duration = 2040 }
end
