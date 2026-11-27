-- Notifiers/Quest.lua: notable quest turn-ins. One post per quest, the highest-priority rule wins:
--   1 attunement  quest/item listed in Data/Attunements.lua      "<name> is attuned to <raid>!"
--   2 tier05      title (or ID) in Data/QuestRewards.lua Tier05  "upgraded <pieces> to Tier 0.5 (n/4)"
--   3 class       GetRewardSpell() or a class-restricted reward item (tooltip "Classes: ...")
--   4 epic        any reward item of quality >= 4
--   5 dungeon     reward quality >= 3 and the quest tag is Dungeon/Raid (GetQuestTagInfo)
--   6 allowlist   reward item in Data/QuestRewards.lua QuestRewardAllowlist
-- Everything is read on QUEST_COMPLETE (the quest is still in the log); the chosen reward comes from
-- hooksecurefunc("GetQuestReward"); the post is sent after QUEST_TURNED_IN, confirmed by the
-- "You receive item: X" message (LOOT_ITEM_PUSHED_SELF), or right away when no item is expected.
-- `/navtok probe quest` prints every QUEST_COMPLETE in detail (IDs for the data files).
local _, ns = ...
local N = ns.NewNotifier("quest")

N.CONFIRM_TIMEOUT = 5     -- seconds to wait for the reward item message after the turn-in
N.TURNIN_WINDOW = 30      -- QUEST_TURNED_IN must follow QUEST_COMPLETE within this time

local function itemIdOf(link) return link and tonumber(link:match("item:(%d+)")) end
local function nameOf(link) return link and link:match("%[(.-)%]") end

-------------------------------------------------------------------------------
-- Reading the quest frame
-------------------------------------------------------------------------------
local function itemInfo(link)
  local name, _, quality = GetItemInfo(link)
  if quality == nil then
    local c = link:match("|c%x%x(%x%x%x%x%x%x)")
    quality = c and ({ ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4,
      ["ff8000"] = 5 })[c:lower()]
  end
  return { link = link, id = itemIdOf(link), name = name or nameOf(link), quality = quality or 1 }
end

local function readItems(kind, count)
  local out = {}
  for i = 1, count or 0 do
    local link = GetQuestItemLink and GetQuestItemLink(kind, i)
    if link then out[i] = itemInfo(link) end
  end
  return out
end

-- tagID, tagName (classic returns two values, newer clients a table)
local function questTag(questID)
  if not (GetQuestTagInfo and questID) then return nil, nil end
  local ok, a, b = pcall(GetQuestTagInfo, questID)
  if not ok then return nil, nil end
  if type(a) == "table" then return a.tagID, a.tagName end
  return a, b
end

local DUNGEON_TAGS = { [81] = true, [62] = true, [88] = true, [89] = true }
local function isDungeonTag(id, name)
  if id and DUNGEON_TAGS[id] then return true end
  if type(name) ~= "string" then return false end
  local n = name:lower()
  return n == (DUNGEON or "Dungeon"):lower() or n == (RAID or "Raid"):lower() or n:find("dungeon", 1, true) ~= nil
    or n:find("raid", 1, true) ~= nil
end

-- Tooltip lines of an item (replaced in tests).
function N.TooltipLines(link)
  if not N.tip then
    N.tip = CreateFrame("GameTooltip", "NavtokScanTooltip", nil, "GameTooltipTemplate")
  end
  local tip = N.tip
  tip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  tip:ClearLines()
  tip:SetHyperlink(link)
  local lines = {}
  for i = 1, (tip:NumLines() or 0) do
    local fs = _G["NavtokScanTooltipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t then lines[#lines + 1] = t end
  end
  tip:Hide()
  return lines
end

-- Returns the "Classes: Warrior" text if the item is class-restricted.
function N.ClassRestriction(link)
  local fmt = ITEM_CLASSES_ALLOWED or "Classes: %s"
  local pat = ns.FormatToPattern(fmt)
  local ok, lines = pcall(N.TooltipLines, link)
  if not ok or type(lines) ~= "table" then return nil end
  for _, l in ipairs(lines) do
    local classes = ns.StripCodes(l):match(pat)
    if classes then return classes end
  end
end

function N:Snapshot()
  local questID = GetQuestID and GetQuestID()
  local tagID, tagName = questTag(questID)
  local spellName
  if GetRewardSpell then
    local ok, a, b = pcall(GetRewardSpell)
    if ok then spellName = (type(b) == "string" and b) or (type(a) == "string" and not a:find("^Interface") and a) or nil end
  end
  local snap = {
    questID = questID, title = GetTitleText and GetTitleText() or "?",
    rewards = readItems("reward", GetNumQuestRewards and GetNumQuestRewards() or 0),
    choices = readItems("choice", GetNumQuestChoices and GetNumQuestChoices() or 0),
    spell = spellName, tagID = tagID, tagName = tagName, at = GetTime(),
  }
  self.snap = snap
  if ns.db and ns.db.probeQuest then self:ProbePrint(snap) end
  return snap
end

function N:ProbePrint(snap)
  local log = ns.Probe and ns.Probe.Log or ns.Print
  log(("quest %s \"%s\" tag=%s/%s spell=%s"):format(tostring(snap.questID), snap.title, tostring(snap.tagID),
    tostring(snap.tagName), tostring(snap.spell)))
  for _, kind in ipairs({ "rewards", "choices" }) do
    for i, it in pairs(snap[kind]) do
      log(("  %s %d: id=%s q=%s %s class=%s"):format(kind, i, tostring(it.id), tostring(it.quality),
        tostring(it.name), tostring(N.ClassRestriction(it.link))))
    end
  end
end

-------------------------------------------------------------------------------
-- Classification
-------------------------------------------------------------------------------
local function itemMatches(it, entry)
  if entry.id then return it.id == entry.id end
  return it.name ~= nil and entry.name ~= nil and it.name:lower() == entry.name:lower()
end

-- The items the player actually gets: all fixed rewards plus the chosen one (or all choices when
-- the choice is unknown).
function N:Received(snap)
  local items = {}
  for _, it in pairs(snap.rewards) do items[#items + 1] = it end
  if snap.chosen then
    items[#items + 1] = snap.chosen
  else
    for _, it in pairs(snap.choices) do items[#items + 1] = it end
  end
  return items
end

local function best(items, minQ)
  local b
  for _, it in ipairs(items) do
    if it.quality >= (minQ or 0) and (not b or it.quality > b.quality) then b = it end
  end
  return b
end

-- Returns sub-type and event data, or nil when the quest is not post-worthy.
function N:Classify(snap)
  local items = self:Received(snap)
  local base = { questId = snap.questID, quest = snap.title }
  local function with(t)
    for k, v in pairs(base) do if t[k] == nil then t[k] = v end end
    return t
  end
  -- 1 attunement
  for _, att in ipairs(ns.Data.Attunements or {}) do
    local hit = false
    for _, id in ipairs(att.questIds or {}) do if snap.questID == id then hit = true end end
    for _, t in ipairs(att.titles or {}) do if snap.title == t then hit = true end end
    for _, it in ipairs(items) do
      for _, e in ipairs(att.items or {}) do if itemMatches(it, e) then hit = true end end
    end
    if hit then
      local it = items[1]
      return "attunement", with({ extra = att.raid, item = it and it.name, itemId = it and it.id, quality = it and it.quality })
    end
  end
  -- 2 tier 0.5
  local t05 = ns.Data.Tier05 or {}
  local stage = (t05.questIds or {})[snap.questID or -1] or (t05.titles or {})[snap.title]
  if stage then
    local names = {}
    for _, it in ipairs(items) do names[#names + 1] = it.name end
    local it = best(items, 0)
    return "tier05", with({ stage = stage, extra = table.concat(names, ", "), item = it and it.name,
      itemId = it and it.id, quality = it and it.quality })
  end
  -- 3 class quest
  if snap.spell then
    return "class", with({ extra = snap.spell })
  end
  for _, it in ipairs(items) do
    if N.ClassRestriction(it.link) then
      return "class", with({ item = it.name, itemId = it.id, quality = it.quality })
    end
  end
  -- 4 epic
  local epic = best(items, 4)
  if epic then return "epic", with({ item = epic.name, itemId = epic.id, quality = epic.quality }) end
  -- 5 dungeon / raid quest with a blue+ reward
  local blue = best(items, 3)
  if blue and isDungeonTag(snap.tagID, snap.tagName) then
    return "dungeon", with({ item = blue.name, itemId = blue.id, quality = blue.quality, extra = snap.tagName })
  end
  -- 6 allowlist
  for _, it in ipairs(items) do
    for _, e in ipairs(ns.Data.QuestRewardAllowlist or {}) do
      if itemMatches(it, e) then
        return "allowlist", with({ item = it.name, itemId = it.id, quality = it.quality })
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Turn-in flow
-------------------------------------------------------------------------------
function N:Post(snap)
  if snap.posted then return end
  snap.posted = true
  if self.snap == snap then self.snap = nil end
  local sub, data = self:Classify(snap)
  if not sub then return end
  data.sub = sub
  ns.Emit("quest", data, { delay = 0.3, priority = sub == "attunement" or sub == "tier05" })
end

function N:OnTurnedIn(questID)
  local snap = self.snap
  if not snap or GetTime() - snap.at > self.TURNIN_WINDOW then return end
  if questID and snap.questID and tonumber(questID) ~= snap.questID then return end
  snap.turnedIn = true
  if #self:Received(snap) == 0 then
    self:Post(snap) -- nothing to wait for (spell / attunement without item)
    return
  end
  ns.After(self.CONFIRM_TIMEOUT, function()
    if not snap.posted then self:Post(snap) end -- the item message never came: post anyway
  end)
end

function N:PushedPatterns()
  if not self.pushed then
    self.pushed = {}
    for _, g in ipairs({ "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF" }) do
      local fmt = _G[g]
      if type(fmt) == "string" then self.pushed[#self.pushed + 1] = (ns.FormatToPattern(fmt):gsub("^%^", "")) end
    end
  end
  return self.pushed
end

function N:OnLoot(msg)
  local snap = self.snap
  if not snap or not snap.turnedIn or snap.posted then return end
  for _, p in ipairs(self:PushedPatterns()) do
    local link = msg:match(p)
    if link then
      local id = itemIdOf(link)
      for _, it in ipairs(self:Received(snap)) do
        if it.id == id then
          if not snap.chosen then
            for _, c in pairs(snap.choices) do if c.id == id then snap.chosen = c end end
          end
          self:Post(snap)
          return
        end
      end
    end
  end
end

function N:Init()
  ns.On("QUEST_COMPLETE", function() N:Snapshot() end)
  ns.On("QUEST_TURNED_IN", function(_, questID) N:OnTurnedIn(questID) end)
  ns.On("CHAT_MSG_LOOT", function(_, msg) N:OnLoot(msg or "") end)
  if hooksecurefunc and GetQuestReward then
    hooksecurefunc("GetQuestReward", function(choice)
      local snap = N.snap
      if snap and choice and snap.choices[choice] then snap.chosen = snap.choices[choice] end
      if snap and ns.unknownEvents["QUEST_TURNED_IN"] then N:OnTurnedIn(nil) end
    end)
  end
end

function N:Test()
  return { sub = "attunement", questId = 6502, quest = "Drakefire Amulet", item = "Drakefire Amulet",
    itemId = 16309, quality = 4, extra = "Onyxia's Lair" }
end
