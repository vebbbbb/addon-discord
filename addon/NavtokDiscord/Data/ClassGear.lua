-- Data/ClassGear.lua: what each class can equip (classic proficiencies, including ones a class still
-- has to train, e.g. Plate for warriors before level 40). EDIT FREELY.
-- Used by the quest "dungeon" rule: a blue reward the class can never equip is not posted
-- (a reward the character is merely too low level for still is).
-- Item classes/subclasses are the game's (GetItemInfoInstant): armor = 4, weapon = 2.
local _, ns = ...
ns.Data = ns.Data or {}

-- armor subclass: 0 misc (rings, necks, trinkets...), 1 cloth, 2 leather, 3 mail, 4 plate,
-- 6 shield, 7 libram, 8 idol, 9 totem
-- weapon subclass: 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace, 6 polearm, 7 1H sword,
-- 8 2H sword, 10 staff, 13 fist, 14 misc, 15 dagger, 16 thrown, 18 crossbow, 19 wand, 20 fishing pole
local function set(list) local t = {} for _, v in ipairs(list) do t[v] = true end return t end

ns.Data.ClassGear = {
  WARRIOR = { armor = set { 1, 2, 3, 4, 6 },    weapon = set { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 } },
  PALADIN = { armor = set { 1, 2, 3, 4, 6, 7 }, weapon = set { 0, 1, 4, 5, 6, 7, 8 } },
  HUNTER  = { armor = set { 1, 2, 3 },          weapon = set { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 } },
  ROGUE   = { armor = set { 1, 2 },             weapon = set { 2, 3, 4, 7, 13, 15, 16, 18 } },
  PRIEST  = { armor = set { 1 },                weapon = set { 4, 10, 15, 19 } },
  SHAMAN  = { armor = set { 1, 2, 3, 6, 9 },    weapon = set { 0, 1, 4, 5, 10, 13, 15 } },
  MAGE    = { armor = set { 1 },                weapon = set { 7, 10, 15, 19 } },
  WARLOCK = { armor = set { 1 },                weapon = set { 7, 10, 15, 19 } },
  DRUID   = { armor = set { 1, 2, 8 },          weapon = set { 4, 5, 10, 13, 15 } },
}

-- always usable: armor misc (0), cloaks, shirts, tabards; weapon misc (14), fishing poles (20)
ns.Data.ClassGearAlways = { armor = set { 0 }, weapon = set { 14, 20 },
  equipLoc = set { "INVTYPE_CLOAK", "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_FINGER", "INVTYPE_NECK",
    "INVTYPE_TRINKET" } }

-- Can classFile ever equip this item? Unknown classes/items count as usable.
function ns.Data.CanClassEquip(classFile, link)
  local gear = ns.Data.ClassGear[classFile or ""]
  if not gear or not link or not GetItemInfoInstant then return true end
  local _, _, _, equipLoc, _, classID, subclassID = GetItemInfoInstant(link)
  local always = ns.Data.ClassGearAlways
  if equipLoc and always.equipLoc[equipLoc] then return true end
  if classID == 4 then
    return always.armor[subclassID] or gear.armor[subclassID] or false
  elseif classID == 2 then
    return always.weapon[subclassID] or gear.weapon[subclassID] or false
  end
  return true -- not armor/weapon
end
