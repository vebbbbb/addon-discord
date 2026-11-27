-- Notifiers/PvP.lua: world PvP, without per-kill spam. Nothing here posts from battlegrounds.
--   rank      PvP rank went up ("reached Knight-Lieutenant (Rank 7)"). The first scan only seeds.
--   hk        lifetime honorable kills crossed a milestone (100, 250, 500, 1000, 2500 ...).
--             Statistic 588 "Total Honorable Kills", else GetPVPLifetimeStats().
--   worldpvp  a world PvP fight summary: after QUIET seconds without an honorable kill, ONE post
--             for the whole group with the number of DIFFERENT victims (in a group every member gets
--             the same HKs, so 3 kills in a 5-man group are 3, not 15), at least MIN_KILLS.
--             Group members share their kills (Group "H" messages); the alphabetically first group
--             member that took part posts. The picture is a kept "candidate" screenshot of a kill.
local _, ns = ...
local N = ns.NewNotifier("pvp")

N.QUIET = 300
N.MIN_KILLS = 3
N.SHOT_EVERY = 30 -- seconds between kept kill screenshots
N.HK_MILESTONES = { 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000 }
N.STAT_TOTAL_HK = 588

local function inBattleground()
  if not IsInInstance then return false end
  local _, itype = IsInInstance()
  return itype == "pvp" or itype == "arena"
end

-------------------------------------------------------------------------------
-- rank
-------------------------------------------------------------------------------
function N:CheckRank()
  if not UnitPVPRank then return end
  local rank = UnitPVPRank("player")
  if not rank then return end
  local c = ns.char
  local old = c.pvpRank
  c.pvpRank = rank
  if old and rank > old then
    local name = GetPVPRankInfo and GetPVPRankInfo(rank, "player") or ("Rank " .. rank)
    local number = GetPVPRankInfo and select(2, GetPVPRankInfo(rank, "player")) or rank
    ns.Emit("pvp", { sub = "rank", rank = number, extra = name }, { kind = "pvp", priority = true })
  end
end

-------------------------------------------------------------------------------
-- lifetime honorable kills
-------------------------------------------------------------------------------
function N:LifetimeHK()
  if GetStatistic then
    local ok, v = pcall(GetStatistic, N.STAT_TOTAL_HK)
    if ok and tonumber(v) then return tonumber(v) end
  end
  if GetPVPLifetimeStats then
    local hk = GetPVPLifetimeStats()
    return tonumber(hk)
  end
end

function N:CheckHK()
  local hk = self:LifetimeHK()
  if not hk then return end
  local c = ns.char
  local old = c.lifetimeHK
  c.lifetimeHK = hk
  if not old or hk <= old then return end
  local reached
  for _, m in ipairs(N.HK_MILESTONES) do
    if hk >= m and old < m then reached = m end
  end
  if reached then
    ns.Emit("pvp", { sub = "hk", count = reached }, { kind = "pvp", priority = true })
  end
end

-------------------------------------------------------------------------------
-- world PvP fights
-------------------------------------------------------------------------------
function N:Fight()
  if not self.fight then
    self.fight = { victims = {}, members = {}, start = time(), zone = GetRealZoneText and GetRealZoneText() or "" }
  end
  return self.fight
end

function N:AddKill(victim, member)
  local f = self:Fight()
  f.victims[victim] = true
  f.members[member] = true
  f.last = GetTime()
  f.lastTs = time()
  self.timerToken = (self.timerToken or 0) + 1
  local token = self.timerToken
  ns.After(N.QUIET, function() if token == N.timerToken then N:EndFight() end end)
end

function N:OwnKill(victim)
  local me = ns.playerName
  self:AddKill(victim, me)
  ns.Group.Send("H", victim)
  local f = self.fight
  if not f.lastShot or GetTime() - f.lastShot >= N.SHOT_EVERY then
    f.lastShot = GetTime()
    local ev = ns.Emit("pvp", { sub = "kill", extra = victim }, { kind = "pvp", candidate = true })
    if ev then f.shotSeq = ev.seq end
  end
end

function N:EndFight()
  local f = self.fight
  self.fight = nil
  if not f then return end
  local count = 0
  for _ in pairs(f.victims) do count = count + 1 end
  if count < N.MIN_KILLS or not f.members[ns.playerName] then return end
  -- the alphabetically first member that took part posts; we only post if that is us
  local first
  for name in pairs(f.members) do if not first or name < first then first = name end end
  if first ~= ns.playerName then return end
  local names, victims = {}, {}
  for name in pairs(f.members) do names[#names + 1] = name end
  table.sort(names)
  for v in pairs(f.victims) do victims[#victims + 1] = v end
  table.sort(victims)
  ns.Emit("pvp", {
    sub = "worldpvp", count = count, duration = math.max(0, (f.lastTs or time()) - f.start), zone = f.zone,
    group = table.concat(names, ", "), shotSeq = f.shotSeq, victims = table.concat(victims, ", "),
  }, { kind = "pvp" })
end

function N:HonorPattern()
  if not self.hkPat then
    local fmt = COMBATLOG_HONORGAIN or "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
    self.hkPat = (ns.FormatToPattern(fmt):gsub("^%^", ""):gsub("%$$", ""))
  end
  return self.hkPat
end

function N:OnHonor(msg)
  if inBattleground() then return end
  local victim = (msg or ""):match(self:HonorPattern())
  if victim then self:OwnKill(victim) end
end

function N:Init()
  self:CheckRank()
  self:CheckHK()
  ns.On("PLAYER_PVP_RANK_CHANGED", function() N:CheckRank() end)
  ns.On("PLAYER_PVP_KILLS_CHANGED", function() N:CheckHK() end)
  ns.On("PLAYER_ENTERING_WORLD", function() N:CheckRank() end)
  ns.On("CHAT_MSG_COMBAT_HONOR_GAIN", function(_, msg)
    N:OnHonor(msg)
    ns.After(1, function() N:CheckHK() end)
  end)
  ns.Group.On("H", function(sender, victim)
    if not inBattleground() and victim ~= "" then N:AddKill(victim, sender) end
  end)
end

function N:Test()
  return { sub = "worldpvp", count = 9, duration = 720, zone = "Hillsbrad Foothills", group = "Kjell, Rune, Veb" }
end
