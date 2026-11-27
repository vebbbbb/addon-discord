-- Notifiers/Unlock.lua: one-time character unlocks.
--   riding   - a riding skill reaches 75 (normal mount) or 150 (epic mount). Read from the skill
--              list (SKILL_LINES_CHANGED), so it works for the classic per-race skills ("Horse
--              Riding", "Ram Riding", "Mechanostrider Piloting", "Undead Horsemanship", ...) and a
--              plain "Riding" skill. The first scan after login only seeds the cache.
--   dualspec - the number of talent groups goes from 1 to 2 (GetNumTalentGroups), with a
--              system-message fallback. Posted once per character.
local _, ns = ...
local N = ns.NewNotifier("unlock")

N.RIDING_NAMES = { "Riding", "Horsemanship", "Piloting" }
N.TIERS = { { rank = 150, sub = "epicriding" }, { rank = 75, sub = "riding" } }

function N.IsRiding(name)
  if type(name) ~= "string" then return false end
  for _, n in ipairs(N.RIDING_NAMES) do
    if name:find(n, 1, true) then return true end
  end
  return false
end

function N:ScanRiding()
  if not (GetNumSkillLines and GetSkillLineInfo) then return end
  local cache = ns.char.riding
  local seeding = not ns.char.ridingSeeded
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
    if name and not isHeader and N.IsRiding(name) and rank then
      local old = cache[name] or 0
      cache[name] = rank
      if not seeding and rank > old then
        for _, t in ipairs(N.TIERS) do
          if rank >= t.rank and old < t.rank then
            ns.Emit("unlock", { sub = t.sub, skill = name, rank = rank }, { kind = "riding", priority = true })
            break
          end
        end
      end
    end
  end
  ns.char.ridingSeeded = true
end

local function talentGroups()
  if GetNumTalentGroups then
    local ok, n = pcall(GetNumTalentGroups)
    if ok then return tonumber(n) end
  end
end

function N:CheckDualSpec(fromMessage)
  if ns.char.dualspec then return end
  local n = talentGroups()
  if (n and n >= 2) or fromMessage then
    ns.char.dualspec = true
    if self.seededDual or fromMessage then
      ns.Emit("unlock", { sub = "dualspec" }, { kind = "dualspec", priority = true })
    end
  end
  self.seededDual = true
end

local DUAL_TEXT = { "Dual Talent Specialization", "Dual Specialization", "Dual Spec" }
function N:OnSystem(msg)
  if ns.char.dualspec or type(msg) ~= "string" then return end
  for _, t in ipairs(DUAL_TEXT) do
    if msg:find(t, 1, true) and (msg:find("learn", 1, true) or msg:find("unlock", 1, true) or msg:find("purchase", 1, true)) then
      self:CheckDualSpec(true)
      return
    end
  end
end

function N:Init()
  ns.char.riding = ns.char.riding or {}
  self:ScanRiding()
  self:CheckDualSpec() -- seeds: a character that already has dual spec is never posted
  ns.On("SKILL_LINES_CHANGED", function() N:ScanRiding() end)
  for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB" }) do
    ns.On(e, function() N:CheckDualSpec() end)
  end
  ns.On("CHAT_MSG_SYSTEM", function(_, msg) N:OnSystem(msg) end)
end

function N:Test()
  return { sub = "epicriding", skill = "Horse Riding", rank = 150 }
end
