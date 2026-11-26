-- Notifiers/Loot.lua: epic (or better) items looted by the player, and EVERYTHING the player
-- WINS ON A NEED ROLL (any item, any quality; settings.needMinQuality can raise the bar).
-- CHAT_MSG_LOOT is matched against patterns built from LOOT_ITEM_SELF(_MULTIPLE); items that are
-- not cached yet are resolved via GET_ITEM_INFO_RECEIVED (link colour as last resort).
-- Need: RollOnLoot(rollID, 1) is hooked (plus "You have selected Need for: X" as a fallback);
-- "You won: X" for such an item posts it with roll = "need" (and the roll value when the
-- "Need Roll - 87 for X by You" message was seen). Its "You receive loot" line is not posted again.
local _, ns = ...
local N = ns.NewNotifier("loot")

N.pending = {}      -- itemID -> { link, count, since }
N.RESOLVE_TIMEOUT = 5
N.needs = {}        -- itemID -> GetTime() when the player chose Need
N.rollValues = {}   -- itemID -> the player's need roll
N.wonByNeed = {}    -- itemID -> GetTime() of a posted need win (suppresses the receive message)
N.NEED_TTL = 600

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

-- Roll patterns are not anchored at the start: Forever's chat shows them as "[Loot]: You won: X".
local function pattern(global)
  local fmt = _G[global]
  if type(fmt) == "string" then return (ns.FormatToPattern(fmt):gsub("^%^", "")) end
end

-- "Veb" and "Veb Ragnvaldjord" (Forever shows surnames in roll messages) are the same player.
local function isMe(who)
  if type(who) ~= "string" then return false end
  local me = ns.playerName or ""
  return who == me or who:sub(1, #me + 1) == me .. " " or who:sub(1, #me + 1) == me .. "-"
    or who == (YOU or "You") or who == "you"
end

function N:RollPatterns()
  if self.rollPats then return self.rollPats end
  local p = { won = {}, needSelf = {}, rolled = {} }
  -- "You won: X" (and the newer "You won: X (Need - 87)" variants with the roll included)
  for _, g in ipairs({ "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "LOOT_ROLL_YOU_WON" }) do
    local pat = pattern(g)
    if pat then p.won[#p.won + 1] = { pattern = pat, need = g:find("NEED") ~= nil } end
  end
  p.needSelf[#p.needSelf + 1] = pattern("LOOT_ROLL_NEED_SELF")
  p.rolled[#p.rolled + 1] = pattern("LOOT_ROLL_ROLLED_NEED")
  self.rollPats = p
  return p
end

function N:MarkNeed(link)
  local id = link and itemIdOf(link)
  if id then self.needs[id] = GetTime() end
end

-- Handles roll related loot messages; returns true when the message was one of them.
function N:HandleRoll(msg)
  local p = self:RollPatterns()
  for _, pat in ipairs(p.needSelf) do
    local link = msg:match(pat)
    if link then self:MarkNeed(link) return true end
  end
  for _, pat in ipairs(p.rolled) do
    -- "Need Roll - %d for %s by %s"
    local roll, link, who = msg:match(pat)
    if roll and link then
      local id = itemIdOf(link)
      if id and isMe(who) then
        self.rollValues[id] = tonumber(roll)
      end
      return true
    end
  end
  for _, w in ipairs(p.won) do
    local link, roll = msg:match(w.pattern)
    if link then
      if w.need then self:MarkNeed(link) end
      local id = itemIdOf(link)
      if roll and id then self.rollValues[id] = tonumber(roll) end
      self:Won(link)
      return true
    end
  end
  return false
end

local function needMinQuality()
  return tonumber((ns.settings or ns.DEFAULTS).needMinQuality) or 0
end

function N:Won(link)
  local id = itemIdOf(link)
  local at = id and self.needs[id]
  if not at or GetTime() - at > self.NEED_TTL then return end -- not won by need
  self.needs[id] = nil
  local name, _, quality = GetItemInfo(link)
  if quality == nil then
    local color = link:match("|c%x%x(%x%x%x%x%x%x)")
    quality = color and ({ ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4,
      ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7 })[color:lower()]
  end
  if (quality or 0) < needMinQuality() then return end
  self.wonByNeed[id] = GetTime()
  ns.Emit("loot", {
    itemId = id, quality = quality or 1, count = 1,
    item = name or link:match("%[(.-)%]") or ("item " .. id),
    roll = "need", rollValue = self.rollValues[id],
  })
  self.rollValues[id] = nil
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
  if self.wonByNeed[itemId] and GetTime() - self.wonByNeed[itemId] < 120 then
    self.wonByNeed[itemId] = nil
    return -- already posted as a need win
  end
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
    msg = msg or ""
    if N:HandleRoll(msg) then return end
    local link, count = N:Parse(msg)
    if link then N:Handle(link, count) end
  end)
  if hooksecurefunc and RollOnLoot then
    hooksecurefunc("RollOnLoot", function(rollID, rollType)
      if rollType == 1 and GetLootRollItemLink then
        local ok, link = pcall(GetLootRollItemLink, rollID)
        if ok then N:MarkNeed(link) end
      end
    end)
  end
  ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemId, success) N:OnItemInfo(itemId, success) end)
end

function N:Test()
  return { itemId = 19019, quality = 5, count = 1, item = "Thunderfury, Blessed Blade of the Windseeker" }
end
