-- Notifiers/Battleground.lua: one post per battleground instance when the winner is known.
-- Screenshot ~1 s after the winner is known so the final scoreboard is on screen.
-- Instance key = map name + instanceID (or a start-time bucket when the id is 0/nil); posted keys
-- are persisted, so a /reload on the scoreboard does not post again.
local _, ns = ...
local N = ns.NewNotifier("bg")

N.SCORE_DELAY = 1
N.BUCKET = 30
N.MAX_POSTED = 50

local function activeBattlefield()
  local max = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or MAX_BATTLEFIELD_QUEUES or 3
  for i = 1, max do
    local status, mapName, instanceID = GetBattlefieldStatus(i)
    if status == "active" then return mapName, tonumber(instanceID) end
  end
end

local function inBattleground()
  if not IsInInstance then return false end
  local inInstance, itype = IsInInstance()
  return inInstance and itype == "pvp"
end

function N:InstanceKeys()
  local mapName, instanceID = activeBattlefield()
  mapName = mapName or (GetRealZoneText and GetRealZoneText()) or "?"
  if instanceID and instanceID > 0 then
    return { mapName .. "#" .. instanceID }, mapName
  end
  local runMs = GetBattlefieldInstanceRunTime and GetBattlefieldInstanceRunTime() or 0
  local start = time() - math.floor((runMs or 0) / 1000)
  local b = math.floor(start / self.BUCKET) * self.BUCKET
  -- neighbours too, so jitter across a bucket border still counts as the same instance
  return { mapName .. "@" .. b, mapName .. "@" .. (b - self.BUCKET), mapName .. "@" .. (b + self.BUCKET) }, mapName
end

function N:IsPosted(keys)
  local posted = ns.char.bg.posted
  for _, k in ipairs(keys) do
    for _, p in ipairs(posted) do
      if p == k then return true end
    end
  end
  return false
end

function N:MarkPosted(key)
  local posted = ns.char.bg.posted
  posted[#posted + 1] = key
  while #posted > self.MAX_POSTED do table.remove(posted, 1) end
end

function N:OwnRow()
  local n = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
  local me = ns.playerName or UnitName("player")
  for i = 1, n do
    local name, kb, hk, deaths, honor = GetBattlefieldScore(i)
    if name and (name == me or name:sub(1, #me + 1) == me .. "-") then
      return { kb = kb, hk = hk, deaths = deaths, honor = honor }
    end
  end
  return {}
end

function N:Result(winner)
  local faction = UnitFactionGroup("player")
  if winner == 0 then return faction == "Horde" and "win" or "loss" end
  if winner == 1 then return faction == "Alliance" and "win" or "loss" end
  return "draw"
end

function N:Check()
  if self.waiting or not inBattleground() then return end
  local winner = GetBattlefieldWinner and GetBattlefieldWinner()
  if winner == nil then return end
  local keys, mapName = self:InstanceKeys()
  if self:IsPosted(keys) then return end
  self:MarkPosted(keys[1])
  self.waiting = true
  if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
  local runMs = GetBattlefieldInstanceRunTime and GetBattlefieldInstanceRunTime() or 0
  ns.After(self.SCORE_DELAY, function()
    self.waiting = false
    local row = self:OwnRow()
    ns.Emit("bg", {
      bg = mapName,
      result = self:Result(winner),
      duration = math.floor((runMs or 0) / 1000),
      kb = row.kb, hk = row.hk, deaths = row.deaths, honor = row.honor,
    }, { priority = true })
  end)
end

function N:Init()
  ns.On("UPDATE_BATTLEFIELD_STATUS", function() N:Check() end)
  ns.On("UPDATE_BATTLEFIELD_SCORE", function() N:Check() end)
end

function N:Test()
  return { bg = "Warsong Gulch", result = "win", duration = 1234, kb = 7, hk = 31, deaths = 2, honor = 412 }
end
