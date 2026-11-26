-- Notifiers/Rare.lua: kills of rare / rare elite NPCs.
-- Forever gives addons no combat log, so kills are detected two ways:
--  1. a rare unit the player can see (target, mouseover, nameplate) turns dead while it is not
--     tapped by someone else (UnitIsTapDenied == false: we or our group get credit);
--  2. "X dies, you gain N experience." (CHAT_MSG_COMBAT_XP_GAIN) for a rare seen in the last 2 min.
-- Each rare (by GUID) is posted once.
local _, ns = ...
local N = ns.NewNotifier("rare")

N.SEEN_TTL = 120
N.seen = {}      -- guid -> { name, classification, level, npcId, at }
N.posted = {}    -- guid -> true

local function classes()
  return (ns.settings or ns.DEFAULTS).rareClassifications or { rare = true, rareelite = true }
end

-- Creature-0-<server>-<instance>-<zone>-<npcId>-<spawn>  ->  npcId
local function npcIdOf(guid)
  if type(guid) ~= "string" then return nil end
  local parts = {}
  for p in guid:gmatch("[^-]+") do parts[#parts + 1] = p end
  if parts[1] == "Creature" or parts[1] == "Vehicle" then return tonumber(parts[6]) end
end

function N:Remember(unit)
  if not UnitExists or not UnitExists(unit) or UnitIsPlayer(unit) then return end
  local c = UnitClassification and UnitClassification(unit)
  if not c or not classes()[c] then return end
  local guid = UnitGUID and UnitGUID(unit)
  if not guid then return end
  local s = self.seen[guid] or {}
  s.name, s.classification, s.level, s.npcId, s.at = UnitName(unit), c, UnitLevel(unit), npcIdOf(guid), GetTime()
  self.seen[guid] = s
  return guid, s
end

function N:Post(guid, s)
  if self.posted[guid] then return end
  self.posted[guid] = true
  ns.Emit("rare", {
    npc = s.name, npcId = s.npcId, classification = s.classification,
    mobLevel = (s.level and s.level > 0) and s.level or nil,
    zone = GetRealZoneText and GetRealZoneText() or "",
    subzone = GetSubZoneText and GetSubZoneText() or "",
  })
end

function N:Check(unit)
  local guid, s = self:Remember(unit)
  if not guid then return end
  if UnitIsDead(unit) and not (UnitIsTapDenied and UnitIsTapDenied(unit)) then
    self:Post(guid, s)
  end
end

function N:Prune()
  local now = GetTime()
  for guid, s in pairs(self.seen) do
    if now - s.at > self.SEEN_TTL then self.seen[guid] = nil end
  end
end

function N:XPPatterns()
  if self.patterns then return self.patterns end
  self.patterns = {}
  for _, g in ipairs({ "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP",
    "COMBATLOG_XPGAIN_FIRSTPERSON_RAID", "COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP",
    "COMBATLOG_XPGAIN_EXHAUSTION1_RAID", "COMBATLOG_XPGAIN_EXHAUSTION2", "COMBATLOG_XPGAIN_EXHAUSTION2_GROUP" }) do
    local fmt = _G[g]
    if type(fmt) == "string" then
      -- these strings continue after the first sentence (bonus/penalty text): match the prefix
      local p = ns.FormatToPattern(fmt):gsub("%$$", "")
      self.patterns[#self.patterns + 1] = p
    end
  end
  return self.patterns
end

function N:OnXP(msg)
  for _, p in ipairs(self:XPPatterns()) do
    local name = msg:match(p)
    if name then
      self:Prune()
      local best, bestGuid
      for guid, s in pairs(self.seen) do
        if s.name == name and not self.posted[guid] and (not best or s.at > best.at) then
          best, bestGuid = s, guid
        end
      end
      if best then self:Post(bestGuid, best) end
      return
    end
  end
end

function N:Init()
  ns.On("PLAYER_TARGET_CHANGED", function() N:Check("target") end)
  ns.On("UPDATE_MOUSEOVER_UNIT", function() N:Check("mouseover") end)
  local function onUnit(_, unit)
    if unit == "target" or unit == "mouseover" or (type(unit) == "string" and unit:find("^nameplate")) then
      N:Check(unit)
    end
  end
  ns.On("UNIT_HEALTH", onUnit)
  ns.On("UNIT_HEALTH_FREQUENT", onUnit)
  ns.On("UNIT_FLAGS", onUnit)
  ns.On("NAME_PLATE_UNIT_ADDED", onUnit)
  ns.On("NAME_PLATE_UNIT_REMOVED", onUnit)
  ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(_, msg) N:OnXP(msg or "") end)
end

function N:Test()
  return { npc = "Mor'Ladim", npcId = 522, classification = "rareelite", mobLevel = 35,
    zone = "Duskwood", subzone = "Tranquil Gardens Cemetery" }
end
