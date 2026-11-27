-- Notifiers/Skill.lua: profession/weapon skill milestones (75/150/225/300 by default).
local _, ns = ...
local N = ns.NewNotifier("skill")

N.seen = {}

function N:Parse(msg)
  if not self.pattern then self.pattern = ns.FormatToPattern(SKILL_RANK_UP or "Your skill in %s has increased to %d.") end
  local skill, rank = msg:match(self.pattern)
  if skill then return skill, tonumber(rank) end
end

local function isMilestone(rank)
  for _, m in ipairs((ns.settings or ns.DEFAULTS).skillMilestones or {}) do
    if rank == m then return true end
  end
  return false
end

function N:Handle(msg)
  local skill, rank = self:Parse(msg or "")
  if not skill or not isMilestone(rank) then return end
  if ns.notifiers.unlock and ns.notifiers.unlock.IsRiding(skill) then return end -- posted as riding
  local key = skill .. ":" .. rank
  if self.seen[key] then return end
  self.seen[key] = true
  ns.Emit("skill", { skill = skill, rank = rank })
end

function N:Init()
  ns.On("CHAT_MSG_SKILL", function(_, msg) N:Handle(msg) end)
end

function N:Test()
  return { skill = "Mining", rank = 300 }
end
