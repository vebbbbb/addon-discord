-- Notifiers/Dungeon.lua: dungeon and raid clears.
--  * A boss on the final-boss list (Data/Dungeons.lua) dies -> post right away.
--  * Any other boss kill takes a "candidate" screenshot (flag C): the companion keeps it but does
--    not post it.
--  * Leaving the instance ALIVE after killing bosses but not the final one -> an in-game popup asks
--    whether the dungeon is complete. Yes posts a summary with the last boss screenshot (shotSeq).
--  * Leaving dead or as a ghost (wipe, corpse run) never asks: the run stays open and continues when
--    you run back in. `/navtok done` asks for a run that was left that way.
-- The run lives in SavedVariables (survives /reload and relog).
local _, ns = ...
local N = ns.NewNotifier("dungeon")

N.DELAY = 0.5
N.POPUP = "NAVTOK_DUNGEON_DONE"

local function where()
  if not GetInstanceInfo then return nil end
  local name, itype, _, _, _, _, _, mapId = GetInstanceInfo()
  if itype == "party" or itype == "raid" then
    return { map = tostring(mapId or name), instance = name, kind = itype == "raid" and "raid" or "dungeon" }
  end
end

local function deadOrGhost()
  return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") or false
end

function N:Run() return ns.char and ns.char.run end

-- Posts the summary of a run whose completion the player confirmed.
N.SUMMARY_TTL = 1800 -- a group member's summary covers our run of the same instance this long

local function summaryKey(run) return "S:" .. tostring(run.map) end

function N:PostSummary(run)
  if not run or run.posted then return end
  run.posted = true
  if ns.Group.IsDone(summaryKey(run), N.SUMMARY_TTL) then return end -- someone in the group posted it
  ns.Group.Done(summaryKey(run)) -- the others' popups close / are never shown
  ns.Emit("dungeon", {
    encounter = run.lastBoss, instance = run.instance, bosses = run.bosses,
    duration = math.max(0, (run.lastAt or time()) - run.start), shotSeq = run.lastSeq,
    group = ns.Group.MembersText(),
  }, { priority = true })
end

-- Asks "was <instance> complete?" for a run left without its final boss.
function N:Ask(run)
  if not run or run.done or run.posted or (run.bosses or 0) == 0 or not run.lastSeq then return end
  if not ns.IsEnabled("dungeon") then return end
  if ns.Group.IsDone(summaryKey(run), N.SUMMARY_TTL) then return end -- a group member already posted
  if not (StaticPopupDialogs and StaticPopup_Show) then
    ns.Print(run.instance .. ": " .. run.bosses .. " bosses. Type /navtok done to post it.")
    N.pending = run
    return
  end
  StaticPopupDialogs[N.POPUP] = StaticPopupDialogs[N.POPUP] or {
    text = "NAVTOK: Did you complete %s?\nPost it to Discord?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data) N:PostSummary(data); N.pending = nil end,
    OnCancel = function() N.pending = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  N.pending = run
  StaticPopup_Show(N.POPUP, run.instance, nil, run)
end

-- `/navtok done`: ask (again) for the last run that was left without a final boss.
function N:Done()
  local run = N.pending or self:Run()
  if run and run.away and not where() then
    ns.char.run = nil
  end
  if run and not run.done and not run.posted and (run.bosses or 0) > 0 then
    self:Ask(run)
  else
    ns.Print("no unfinished dungeon run to post")
  end
end

function N:Zone()
  local here = where()
  local run = self:Run()
  if run and here and here.map == run.map then
    run.away = nil -- back inside (runback after a death, or /reload)
    return
  end
  if run and not here then
    if deadOrGhost() or run.away then
      run.away = true -- died and released: wait for the runback, never ask
      return
    end
    ns.char.run = nil
    self:Ask(run) -- left alive
    return
  end
  if run and here then
    ns.char.run = nil -- a different instance: the old run is dropped silently
  end
  if here then
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
    local data = {
      encounterId = id, encounter = encounterName or entry.boss, instance = entry.instance,
      bosses = run and run.bosses or nil, duration = run and (time() - run.start) or nil,
    }
    -- one post per group: the group's NAVTOK addons agree who posts
    ns.Group.Share("K:" .. tostring(id or encounterName), function()
      data.group = ns.Group.MembersText()
      ns.Emit("dungeon", data, { delay = self.DELAY, priority = true })
    end)
  elseif run and not run.done then
    local ev = ns.Emit("dungeon", { encounterId = id, encounter = encounterName, instance = run.instance },
      { delay = self.DELAY, priority = true, candidate = true })
    if ev then
      run.lastSeq, run.lastBoss = ev.seq, encounterName
    end
  end
end

function N:Init()
  -- a group member posted the summary of the instance we are in / just left: close our popup
  ns.Group.On("D", function(_, key)
    if N.pending and summaryKey(N.pending) == key then
      N.pending.posted = true
      if StaticPopup_Hide then StaticPopup_Hide(N.POPUP) end
    end
  end)
  ns.On("ENCOUNTER_END", function(_, ...) N:Handle(...) end)
  ns.On("PLAYER_ENTERING_WORLD", function() N:Zone() end)
  ns.On("ZONE_CHANGED_NEW_AREA", function() N:Zone() end)
  self:Zone()
end

function N:Test()
  return { encounterId = 2747, encounter = "Edwin VanCleef", instance = "Deadmines", bosses = 8, duration = 2040 }
end
