-- Notifiers/Legacy.lua: Forever "legacy point challenges" completion. STUB.
-- The API is unknown (VERIFY.md item 7). Until it is known, any system message that matches one of
-- settings.legacyPatterns is posted. Use `/navtok probe` while completing a challenge to see which
-- events/messages fire, then replace this generic hook with the real event.
local _, ns = ...
local N = ns.NewNotifier("legacy")

N.SOURCES = { "CHAT_MSG_SYSTEM", "RAID_BOSS_EMOTE" }
N.recent = {}

function N:Matches(msg)
  local text = ns.StripCodes(msg or "")
  for _, p in ipairs((ns.settings or ns.DEFAULTS).legacyPatterns or {}) do
    if text:find(p) then return text end
  end
end

function N:Handle(msg)
  local text = self:Matches(msg)
  if not text then return end
  local now = GetTime()
  if self.recent[text] and now - self.recent[text] < 10 then return end
  self.recent[text] = now
  ns.Emit("legacy", { text = text })
end

function N:Init()
  for _, e in ipairs(self.SOURCES) do
    ns.On(e, function(_, msg) N:Handle(msg) end)
  end
end

function N:Test()
  return { text = "Legacy challenge complete: Explorer of Azeroth" }
end
