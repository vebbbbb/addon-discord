-- Data/Attunements.lua: quests/items that attune a character to a raid. EDIT FREELY.
-- A quest turn-in matches an entry when its quest ID is in questIds, its title is in titles, or one
-- of its reward items is in items (by ID; the English name is the fallback when the ID is nil).
-- verified = false: IDs/names not yet confirmed in WoW Forever - collect them with
-- `/navtok probe quest` (VERIFY.md) and flip to true.
--
-- Fields: key, raid (shown in "<name> is attuned to <raid>!"), questIds, titles, items, verified.
local _, ns = ...
ns.Data = ns.Data or {}

ns.Data.Attunements = {
  {
    key = "onyxia",
    raid = "Onyxia's Lair",
    -- Drakefire Amulet is the reward of the last quest of both chains:
    -- Alliance "Drakefire Amulet", Horde "Blood of the Black Dragon Champion"
    questIds = { 6502, 6602 },
    titles = { "Drakefire Amulet", "Blood of the Black Dragon Champion" },
    items = { { id = 16309, name = "Drakefire Amulet" } },
    verified = false,
  },
  {
    key = "moltencore",
    raid = "Molten Core",
    questIds = { 7848 },
    titles = { "Attunement to the Core" },
    items = {},
    verified = false,
  },
}
