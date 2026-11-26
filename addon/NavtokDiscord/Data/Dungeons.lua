-- Data/Dungeons.lua: final bosses that trigger a "dungeon" post on ENCOUNTER_END (success == 1).
--
-- !! ALL ENCOUNTER IDS ARE UNVERIFIED FOR WOW FOREVER !!  (see VERIFY.md item 4)
-- Dungeon encounter ids are left nil on purpose: we do not know the ids the Forever client
-- uses and refuse to guess. Matching falls back to the (English) encounter name until the ids
-- are collected with `/navtok probe` (the probe logs every ENCOUNTER_END with its id).
-- Raid ids below are the classic-era DungeonEncounter ids as known from 1.13+ clients; they
-- are believed correct but still need a Forever check.
--
-- Fields: id (encounterID or nil), boss (encounterName as the client reports it),
--         instance (display name), kind ("dungeon" or "raid"), verified (false until checked).
local _, ns = ...
ns.Data = ns.Data or {}

local list = {
  -- Dungeons (final boss per wing/instance)
  { id = nil, boss = "Bazzalan",                    instance = "Ragefire Chasm",               kind = "dungeon" },
  { id = nil, boss = "Mutanus the Devourer",        instance = "Wailing Caverns",              kind = "dungeon" },
  { id = nil, boss = "Edwin VanCleef",              instance = "The Deadmines",                kind = "dungeon" },
  { id = nil, boss = "Archmage Arugal",             instance = "Shadowfang Keep",              kind = "dungeon" },
  { id = nil, boss = "Aku'mai",                     instance = "Blackfathom Deeps",            kind = "dungeon" },
  { id = nil, boss = "Bazil Thredd",                instance = "The Stockade",                 kind = "dungeon" },
  { id = nil, boss = "Mekgineer Thermaplugg",       instance = "Gnomeregan",                   kind = "dungeon" },
  { id = nil, boss = "Charlga Razorflank",          instance = "Razorfen Kraul",               kind = "dungeon" },
  { id = nil, boss = "Bloodmage Thalnos",           instance = "Scarlet Monastery: Graveyard", kind = "dungeon" },
  { id = nil, boss = "Arcanist Doan",               instance = "Scarlet Monastery: Library",   kind = "dungeon" },
  { id = nil, boss = "Herod",                       instance = "Scarlet Monastery: Armory",    kind = "dungeon" },
  { id = nil, boss = "High Inquisitor Whitemane",   instance = "Scarlet Monastery: Cathedral", kind = "dungeon" },
  { id = nil, boss = "Amnennar the Coldbringer",    instance = "Razorfen Downs",               kind = "dungeon" },
  { id = nil, boss = "Archaedas",                   instance = "Uldaman",                      kind = "dungeon" },
  { id = nil, boss = "Chief Ukorz Sandscalp",       instance = "Zul'Farrak",                   kind = "dungeon" },
  { id = nil, boss = "Princess Theradras",          instance = "Maraudon",                     kind = "dungeon" },
  { id = nil, boss = "Shade of Eranikus",           instance = "Sunken Temple",                kind = "dungeon" },
  { id = nil, boss = "Emperor Dagran Thaurissan",   instance = "Blackrock Depths",             kind = "dungeon" },
  { id = nil, boss = "Overlord Wyrmthalak",         instance = "Lower Blackrock Spire",        kind = "dungeon" },
  { id = nil, boss = "General Drakkisath",          instance = "Upper Blackrock Spire",        kind = "dungeon" },
  { id = nil, boss = "Alzzin the Wildshaper",       instance = "Dire Maul: East",              kind = "dungeon" },
  { id = nil, boss = "Prince Tortheldrin",          instance = "Dire Maul: West",              kind = "dungeon" },
  { id = nil, boss = "King Gordok",                 instance = "Dire Maul: North",             kind = "dungeon" },
  { id = nil, boss = "Darkmaster Gandling",         instance = "Scholomance",                  kind = "dungeon" },
  { id = nil, boss = "Balnazzar",                   instance = "Stratholme: Live",             kind = "dungeon" },
  { id = nil, boss = "Baron Rivendare",             instance = "Stratholme: Undead",           kind = "dungeon" },
  -- Raids (final boss)
  { id = 672,  boss = "Ragnaros",                   instance = "Molten Core",                  kind = "raid" },
  { id = 1084, boss = "Onyxia",                     instance = "Onyxia's Lair",                kind = "raid" },
  { id = 617,  boss = "Nefarian",                   instance = "Blackwing Lair",               kind = "raid" },
  { id = 793,  boss = "Hakkar",                     instance = "Zul'Gurub",                    kind = "raid" },
  { id = 723,  boss = "Ossirian the Unscarred",     instance = "Ruins of Ahn'Qiraj",           kind = "raid" },
  { id = 717,  boss = "C'Thun",                     instance = "Temple of Ahn'Qiraj",          kind = "raid" },
  { id = 1114, boss = "Kel'Thuzad",                 instance = "Naxxramas",                    kind = "raid" },
}

local byId, byName = {}, {}
for _, e in ipairs(list) do
  e.verified = false
  if e.id then byId[e.id] = e end
  byName[e.boss:lower()] = e
end

ns.Data.Dungeons = { list = list, byId = byId, byName = byName }

-- Returns the table entry for a finished encounter, or nil if it is not a final boss.
function ns.Data.FindFinalBoss(encounterID, encounterName)
  if encounterID and byId[encounterID] then return byId[encounterID] end
  if type(encounterName) == "string" then return byName[encounterName:lower()] end
  return nil
end
