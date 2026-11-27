-- Notifiers/Recipe.lua: a recipe/pattern/plan/formula learned FROM AN ITEM. Blue or better by
-- default (settings.recipeMinQuality); Alchemy and Enchanting from green
-- (settings.recipeMinQualityBy, keyed by the recipe subclass: 6 Alchemy, 8 Enchanting).
-- Trainer recipes are not posted: the "You have learned ..." message only counts when a
-- Recipe-class item (classID 9) was used from the bags just before.
local _, ns = ...
local N = ns.NewNotifier("recipe")

N.WINDOW = 10
N.RECIPE_CLASS = 9

local function containerLink(bag, slot)
  if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag, slot) end
  if GetContainerItemLink then return GetContainerItemLink(bag, slot) end
end

local function isRecipe(link)
  if not link then return false end
  if GetItemInfoInstant then
    local _, _, _, _, _, classID = GetItemInfoInstant(link)
    if classID then return classID == N.RECIPE_CLASS end
  end
  local _, _, _, _, _, itemType = GetItemInfo(link)
  return itemType == "Recipe"
end

function N:OnUse(bag, slot)
  local link = containerLink(bag, slot)
  if isRecipe(link) then self.used = { link = link, at = GetTime() } end
end

function N:Patterns()
  if not self.patterns then
    self.patterns = {}
    for _, g in ipairs({ "ERR_LEARN_RECIPE_S", "ERR_LEARN_SPELL_S", "ERR_LEARN_ABILITY_S" }) do
      local fmt = _G[g]
      if type(fmt) == "string" then self.patterns[#self.patterns + 1] = ns.FormatToPattern(fmt) end
    end
  end
  return self.patterns
end

function N:OnSystem(msg)
  local u = self.used
  if not u or GetTime() - u.at > self.WINDOW then return end
  for _, p in ipairs(self:Patterns()) do
    local learned = (msg or ""):match(p)
    if learned then
      self.used = nil
      local name, _, quality = GetItemInfo(u.link)
      local st = ns.settings or ns.DEFAULTS
      local subclass = GetItemInfoInstant and select(7, GetItemInfoInstant(u.link))
      local minQ = (st.recipeMinQualityBy or {})[subclass or -1] or tonumber(st.recipeMinQuality) or 3
      if (quality or 0) < minQ then return end
      ns.Emit("recipe", { itemId = tonumber(u.link:match("item:(%d+)")), quality = quality,
        item = name or u.link:match("%[(.-)%]"), learned = (ns.StripCodes(learned):gsub("^%[(.*)%]$", "%1")) })
      return
    end
  end
end

function N:Init()
  if hooksecurefunc then
    if UseContainerItem then hooksecurefunc("UseContainerItem", function(bag, slot) N:OnUse(bag, slot) end) end
    if C_Container and C_Container.UseContainerItem then
      hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot) N:OnUse(bag, slot) end)
    end
  end
  ns.On("CHAT_MSG_SYSTEM", function(_, msg) N:OnSystem(msg) end)
end

function N:Test()
  return { itemId = 13518, quality = 2, item = "Recipe: Flask of Petrification", learned = "Flask of Petrification" }
end
