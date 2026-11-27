-- Data/QuestRewards.lua: quest reward rules that are just lists. EDIT FREELY.
local _, ns = ...
ns.Data = ns.Data or {}

-- Tier 0.5 upgrade quests (by exact in-game title) -> stage 1..4. Stage 4 = "Tier 0.5 complete!".
-- Titles must match the quest title exactly (VERIFY.md: confirm them in Forever; per-class IDs
-- can be added to questIds as they are collected with `/navtok probe quest`).
ns.Data.Tier05 = {
  titles = {
    ["An Earnest Proposition"] = 1,
    ["Just Compensation"] = 2,
    ["Anthion's Parting Words"] = 3,
    ["Saving the Best for Last"] = 4,
  },
  questIds = {
    -- [questID] = stage,   e.g. [8905] = 1,
  },
}

-- Always-post quest rewards (lowest priority rule). Match by item ID; when id is nil the English
-- item name is used instead. verified = false until the ID is confirmed in Forever.
ns.Data.QuestRewardAllowlist = {
  { id = 11122, name = "Carrot on a Stick", verified = false },
  { id = nil,   name = "Cleansed Vilebranch Icon", verified = false },
  { id = nil,   name = "Cleansed Vilebranch Medallion", verified = false },
  { id = nil,   name = "Rune of the Guard Captain", verified = false },
}
