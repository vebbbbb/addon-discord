local function link(id, name, color) return "|cff" .. (color or "0070dd") .. "|Hitem:" .. id .. "::::::::60:::::|h[" .. name .. "]|h|r" end

-- Complete a quest the way the game does: QUEST_COMPLETE -> GetQuestReward -> QUEST_TURNED_IN -> item message
local function turnIn(q, choice, received)
  W.quest = q
  W.Fire("QUEST_COMPLETE")
  GetQuestReward(choice)
  W.Fire("QUEST_TURNED_IN", q.id, 100, 0)
  W.quest = nil
  for _, l in ipairs(received or {}) do W.Fire("CHAT_MSG_LOOT", "You receive item: " .. l .. ".") end
end

local function boot(tooltips)
  local ns = H.Boot()
  ns.notifiers.quest.TooltipLines = function(l)
    return tooltips and tooltips[tonumber(l:match("item:(%d+)"))] or { "Some item" }
  end
  return ns
end

H.test("quest: attunement (Drakefire Amulet) wins over every other rule; posted after the item arrives", function()
  local ns = boot()
  local amulet = link(16309, "Drakefire Amulet", "a335ee")
  W.items[16309] = { name = "Drakefire Amulet", quality = 4 }
  W.quest = { id = 6502, title = "Drakefire Amulet", rewards = { amulet }, tagID = 1, tagName = "Elite" }
  W.Fire("QUEST_COMPLETE")
  GetQuestReward(nil)
  W.Fire("QUEST_TURNED_IN", 6502, 0, 0)
  H.eq(#H.EventsOfType(ns, "quest"), 0, "waits for the item message")
  W.Fire("CHAT_MSG_LOOT", "You receive item: " .. amulet .. ".")
  local ev = H.EventsOfType(ns, "quest")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"sub":"attunement"')
  H.contains(ev[1].raw, '"extra":"Onyxia\'s Lair"')
  W.Advance(10)
  H.eq(#H.EventsOfType(ns, "quest"), 1, "one post per quest")
end)

H.test("quest: Molten Core attunement has no item reward -> posts at turn-in", function()
  local ns = boot()
  turnIn({ id = 7848, title = "Attunement to the Core", rewards = {} })
  local ev = H.EventsOfType(ns, "quest")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"extra":"Molten Core"')
end)

H.test("quest: tier 0.5 stage from the title, with the upgraded pieces", function()
  local ns = boot()
  local a, b = link(5001, "Lightforge Bracers", "a335ee"), link(5002, "Lightforge Belt", "a335ee")
  W.items[5001] = { name = "Lightforge Bracers", quality = 4 }
  W.items[5002] = { name = "Lightforge Belt", quality = 4 }
  turnIn({ id = 8905, title = "An Earnest Proposition", rewards = { a, b } }, nil, { a, b })
  local ev = H.EventsOfType(ns, "quest")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"sub":"tier05"')
  H.contains(ev[1].raw, '"stage":1')
  H.contains(ev[1].raw, '"extra":"Lightforge Bracers, Lightforge Belt"')
end)

H.test("quest: class quest by reward spell or class-restricted item", function()
  local ns = boot({ [6001] = { "Verigan's Fist", "Classes: Paladin" } })
  turnIn({ id = 1, title = "The Tome of Divinity", rewards = {}, spell = "Redemption" })
  local fist = link(6001, "Verigan's Fist", "0070dd")
  W.items[6001] = { name = "Verigan's Fist", quality = 3 }
  turnIn({ id = 2, title = "The Test of Righteousness", rewards = { fist } }, nil, { fist })
  local ev = H.EventsOfType(ns, "quest")
  H.eq(#ev, 2)
  H.contains(ev[1].raw, '"sub":"class"')
  H.contains(ev[1].raw, '"extra":"Redemption"')
  H.contains(ev[2].raw, '"item":"Verigan\'s Fist"')
end)

H.test("quest: chosen epic reward; dungeon blue; plain quests do not post", function()
  local ns = boot()
  local epic, green = link(7001, "Epic Choice", "a335ee"), link(7002, "Green Choice", "1eff00")
  W.items[7001] = { name = "Epic Choice", quality = 4 }
  W.items[7002] = { name = "Green Choice", quality = 2 }
  turnIn({ id = 3, title = "Pick One", choices = { green, epic } }, 2, { epic })
  local blue = link(7003, "Dungeon Blue", "0070dd")
  W.items[7003] = { name = "Dungeon Blue", quality = 3 }
  turnIn({ id = 4, title = "Into the Depths", rewards = { blue }, tagID = 81, tagName = "Dungeon" }, nil, { blue })
  turnIn({ id = 5, title = "Outdoor Blue", rewards = { blue } }, nil, { blue })            -- blue, not dungeon
  turnIn({ id = 6, title = "Pick Green", choices = { green, epic } }, 1, { green })        -- chose the green
  local ev = H.EventsOfType(ns, "quest")
  H.eq(#ev, 2)
  H.contains(ev[1].raw, '"sub":"epic"')
  H.contains(ev[1].raw, '"item":"Epic Choice"')
  H.contains(ev[2].raw, '"sub":"dungeon"')
end)

H.test("quest: allowlist by ID and by name", function()
  local ns = boot()
  local carrot = link(11122, "Carrot on a Stick", "1eff00")
  W.items[11122] = { name = "Carrot on a Stick", quality = 2 }
  turnIn({ id = 7, title = "Ride the Carrot", rewards = { carrot } }, nil, { carrot })
  local rune = link(9999, "Rune of the Guard Captain", "1eff00")
  W.items[9999] = { name = "Rune of the Guard Captain", quality = 2 }
  turnIn({ id = 8, title = "Guard Duty", rewards = { rune } }, nil, { rune })
  local ev = H.EventsOfType(ns, "quest")
  H.eq(#ev, 2)
  H.contains(ev[1].raw, '"sub":"allowlist"')
  H.contains(ev[2].raw, '"item":"Rune of the Guard Captain"')
end)

H.test("quest: missing item message -> posted after the timeout; switch off works; probe prints", function()
  local ns = boot()
  local epic = link(7001, "Epic Choice", "a335ee")
  W.items[7001] = { name = "Epic Choice", quality = 4 }
  SlashCmdList["NAVTOK"]("probe quest")
  turnIn({ id = 9, title = "Silent", rewards = { epic } })
  H.contains(table.concat(NavtokDiscordDB.probe, "\n"), 'quest 9 "Silent"')
  H.eq(#H.EventsOfType(ns, "quest"), 0)
  W.Advance(6)
  H.eq(#H.EventsOfType(ns, "quest"), 1)
  SlashCmdList["NAVTOK"]("off quest")
  turnIn({ id = 10, title = "Off", rewards = { epic } }, nil, { epic })
  H.eq(#H.EventsOfType(ns, "quest"), 1)
end)
