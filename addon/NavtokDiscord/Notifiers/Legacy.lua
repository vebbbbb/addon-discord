-- Notifiers/Legacy.lua: WoW Forever legacy challenge completions.
-- Forever's game data defines the legacy challenges as achievements (Classes, Tradeskills,
-- Dungeons, Raids, Player vs. Player, Adventure). They are listed in Data/Legacy.lua (generated
-- from the client database) and detected with ACHIEVEMENT_EARNED. If that event is not available,
-- a system-message pattern fallback (settings.legacyPatterns) is used instead (VERIFY.md item 7).
local _, ns = ...
local N = ns.NewNotifier("legacy")

N.FALLBACK_SOURCES = { "CHAT_MSG_SYSTEM" }
N.recent = {}

local function settings() return ns.settings or ns.DEFAULTS end

function N:Post(data)
  local key = data.achievementId and ("a" .. data.achievementId) or data.text
  local now = GetTime()
  if self.recent[key] and now - self.recent[key] < 10 then return end
  self.recent[key] = now
  ns.Emit("legacy", data)
end

-- For achievements added after Data/Legacy.lua was generated: is it in a legacy category?
function N:Dynamic(id)
  if not (GetAchievementCategory and GetCategoryInfo and ns.Data.LegacyRoots) then return nil end
  local ok, cat = pcall(GetAchievementCategory, id)
  local sub
  for _ = 1, 5 do
    if not ok or not cat or cat == -1 then return nil end
    local title, parent = GetCategoryInfo(cat)
    sub = sub or title
    if ns.Data.LegacyRoots[cat] then
      local root = title or ns.Data.LegacyRoots[cat]
      return { group = (sub and sub ~= root) and (root .. ": " .. sub) or root }
    end
    cat = parent
  end
end

function N:OnAchievement(achievementID)
  local id = tonumber(achievementID)
  local entry = id and ns.Data.Legacy and ns.Data.Legacy[id] or (id and self:Dynamic(id))
  if not entry then return end
  if entry.zone and not settings().legacyZones then return end
  local name = entry.name or ("Challenge " .. id)
  if GetAchievementInfo then
    local ok, _, localized = pcall(GetAchievementInfo, id)
    if ok and type(localized) == "string" and localized ~= "" then name = localized end
  end
  if name:find("^Hidden") then return end
  -- the same challenge exists twice in the data (two flag variants): dedupe by name too
  local now = GetTime()
  if self.recent["n" .. name] and now - self.recent["n" .. name] < 10 then return end
  self.recent["n" .. name] = now
  self:Post({ achievementId = id, text = name, group = entry.group })
end

function N:OnSystemMessage(msg)
  if self.achievementEvent then return end -- the precise path is active
  local text = ns.StripCodes(msg or "")
  for _, p in ipairs(settings().legacyPatterns or {}) do
    if text:find(p) then
      self:Post({ text = text })
      return
    end
  end
end

function N:Init()
  ns.On("ACHIEVEMENT_EARNED", function(_, id) N:OnAchievement(id) end)
  self.achievementEvent = not ns.unknownEvents["ACHIEVEMENT_EARNED"]
  for _, e in ipairs(self.FALLBACK_SOURCES) do
    ns.On(e, function(_, msg) N:OnSystemMessage(msg) end)
  end
end

function N:Test()
  return { achievementId = 62382, text = "Explorer", group = "Adventure" }
end
