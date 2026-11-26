-- Data/Classes.lua: class file token -> numeric class id (same numbers as the game's classID).
-- The barcode carries the number; the companion maps it to a class colour.
local _, ns = ...
ns.Data = ns.Data or {}

ns.Data.ClassIds = {
  WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
  DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11,
}
