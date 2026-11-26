-- Notifiers/Loot.lua: epic (or better) items looted by the player.
-- CHAT_MSG_LOOT is matched against patterns built from LOOT_ITEM_SELF(_MULTIPLE); items that are
-- not cached yet are resolved via GET_ITEM_INFO_RECEIVED (link colour as last resort).
local _, ns = ...
local N = ns.NewNotifier("loot")

N.pending = {}      -- itemID -> { link, count, since }
N.RESOLVE_TIMEOUT = 5

-- link colour -> quality, used only when GetItemInfo never answers
local COLOR_QUALITY = {
  ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
  ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}

function N:BuildPatterns()
  self.patterns = {}
  if LOOT_ITEM_SELF_MULTIPLE then
    self.patterns[#self.patterns + 1] = { pattern = ns.FormatToPattern(LOOT_ITEM_SELF_MULTIPLE), multiple = true }
  end
  if LOOT_ITEM_SELF then
    self.patterns[#self.patterns + 1] = { pattern = ns.FormatToPattern(LOOT_ITEM_SELF), multiple = false }
  end
end

-- Returns link, count for a loot message about the player, or nil.
function N:Parse(msg)
  if not self.patterns then self:BuildPatterns() end
  for _, p in ipairs(self.patterns) do
    local link, count = msg:match(p.pattern)
    if link then
      return link, p.multiple and tonumber(count) or 1
    end
  end
end

local function itemIdOf(link)
  return tonumber(link:match("item:(%d+)"))
end

local function minQuality()
  return tonumber((ns.settings or ns.DEFAULTS).lootMinQuality) or 4
end

function N:Post(link, count, quality, name)
  local itemId = itemIdOf(link)
  name = name or link:match("%[(.-)%]") or ("item " .. tostring(itemId))
  ns.Emit("loot", { itemId = itemId, quality = quality, count = count, item = name })
end

function N:Handle(link, count)
  local itemId = itemIdOf(link)
  if not itemId then return end
  local name, _, quality = GetItemInfo(link)
  if quality == nil then
    self.pending[itemId] = { link = link, count = count, since = GetTime() }
    ns.After(self.RESOLVE_TIMEOUT, function() self:Timeout(itemId) end)
    return
  end
  if quality >= minQuality() then self:Post(link, count, quality, name) end
end

function N:OnItemInfo(itemId, success)
  local p = self.pending[itemId]
  if not p then return end
  local name, _, quality = GetItemInfo(p.link)
  if quality == nil and success ~= false then return end -- still not there, wait for timeout
  self.pending[itemId] = nil
  if quality and quality >= minQuality() then self:Post(p.link, p.count, quality, name) end
  if quality == nil then self:Fallback(itemId, p) end
end

function N:Fallback(itemId, p)
  local color = p.link:match("|c%x%x(%x%x%x%x%x%x)")
  local quality = color and COLOR_QUALITY[color:lower()]
  if quality and quality >= minQuality() then self:Post(p.link, p.count, quality) end
end

function N:Timeout(itemId)
  local p = self.pending[itemId]
  if not p then return end
  self.pending[itemId] = nil
  local name, _, quality = GetItemInfo(p.link)
  if quality then
    if quality >= minQuality() then self:Post(p.link, p.count, quality, name) end
  else
    self:Fallback(itemId, p)
  end
end

function N:Init()
  self:BuildPatterns()
  ns.On("CHAT_MSG_LOOT", function(_, msg)
    local link, count = N:Parse(msg or "")
    if link then N:Handle(link, count) end
  end)
  ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemId, success) N:OnItemInfo(itemId, success) end)
end

function N:Test()
  return { itemId = 19019, quality = 5, count = 1, item = "Thunderfury, Blessed Blade of the Windseeker" }
end
