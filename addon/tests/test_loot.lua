local EPIC = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
local RARE = "|cff0070dd|Hitem:1234::::::::60:::::|h[Blue Thing]|h|r"

H.test("loot: epic item posts, rare does not", function()
  local ns = H.Boot()
  W.items[19019] = { name = "Thunderfury", quality = 5 }
  W.items[1234] = { name = "Blue Thing", quality = 3 }
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. RARE .. ".")
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. EPIC .. ".")
  local ev = H.EventsOfType(ns, "loot")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"itemId":19019')
  H.contains(ev[1].raw, '"quality":5')
  H.contains(ev[1].raw, '"count":1')
end)

H.test("loot: multiple count", function()
  local ns = H.Boot()
  W.items[19019] = { name = "Thunderfury", quality = 4 }
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. EPIC .. "x3.")
  local ev = H.EventsOfType(ns, "loot")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"count":3')
end)

H.test("loot: other players' loot ignored", function()
  local ns = H.Boot()
  W.items[19019] = { name = "Thunderfury", quality = 5 }
  W.Fire("CHAT_MSG_LOOT", "Bob receives loot: " .. EPIC .. ".")
  H.eq(#H.EventsOfType(ns, "loot"), 0)
end)

H.test("loot: uncached item resolved via GET_ITEM_INFO_RECEIVED", function()
  local ns = H.Boot()
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. EPIC .. ".")
  H.eq(#H.EventsOfType(ns, "loot"), 0, "waits for item info")
  W.items[19019] = { name = "Thunderfury", quality = 5 }
  W.Fire("GET_ITEM_INFO_RECEIVED", 19019, true)
  H.eq(#H.EventsOfType(ns, "loot"), 1)
  W.Advance(6) -- timeout must not post a second time
  H.eq(#H.EventsOfType(ns, "loot"), 1)
end)

H.test("loot: never cached -> link colour fallback after timeout", function()
  local ns = H.Boot()
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. EPIC .. ".")
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. RARE .. ".")
  W.Advance(6)
  local ev = H.EventsOfType(ns, "loot")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"quality":4')
  H.contains(ev[1].raw, '"item":"Thunderfury"')
end)

H.test("loot: quality threshold is configurable", function()
  local ns = H.Boot()
  ns.settings.lootMinQuality = 3
  W.items[1234] = { name = "Blue Thing", quality = 3 }
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. RARE .. ".")
  H.eq(#H.EventsOfType(ns, "loot"), 1)
end)

local function link(id, name, color)
  return "|cff" .. (color or "1eff00") .. "|Hitem:" .. id .. "::::::::60:::::|h[" .. name .. "]|h|r"
end

H.test("loot: anything won on Need posts once, with the roll; greed wins follow the normal rule", function()
  local ns = H.Boot()
  local boots = link(2000, "Green Boots")
  local recipe = link(2001, "Recipe: Thing", "ffffff")
  local epic = link(2002, "Epic Sword", "a335ee")
  local greed = link(2003, "Blue Ring", "0070dd")
  W.items[2000] = { name = "Green Boots", quality = 2 }
  W.items[2001] = { name = "Recipe: Thing", quality = 1, equipLoc = "" }
  W.items[2002] = { name = "Epic Sword", quality = 4, equipLoc = "INVTYPE_WEAPON" }
  W.items[2003] = { name = "Blue Ring", quality = 3, equipLoc = "INVTYPE_FINGER" }
  -- need via the roll button (hook) and via the chat message
  W.rollItems[1] = boots
  RollOnLoot(1, 1)
  W.Fire("CHAT_MSG_LOOT", "You have selected Need for: " .. recipe)
  W.Fire("CHAT_MSG_LOOT", "You have selected Need for: " .. epic)
  W.rollItems[4] = greed
  RollOnLoot(4, 2) -- greed
  W.Fire("CHAT_MSG_LOOT", "Need Roll - 87 for " .. boots .. " by Testchar")
  W.Fire("CHAT_MSG_LOOT", "Need Roll - 12 for " .. boots .. " by Someoneelse")
  W.Fire("CHAT_MSG_LOOT", "You won: " .. boots)
  W.Fire("CHAT_MSG_LOOT", "You won: " .. recipe)
  W.Fire("CHAT_MSG_LOOT", "You won: " .. epic)
  W.Fire("CHAT_MSG_LOOT", "You won: " .. greed)
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. epic .. ".") -- must not post a 2nd time
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. greed .. ".") -- blue, not need: no post
  local ev = H.EventsOfType(ns, "loot")
  H.eq(#ev, 3)
  H.contains(ev[1].raw, '"roll":"need"')
  H.contains(ev[1].raw, '"rollValue":87')
  H.contains(ev[1].raw, '"item":"Green Boots"')
  H.contains(ev[2].raw, '"item":"Recipe: Thing"')
  H.contains(ev[3].raw, '"item":"Epic Sword"')
  -- a later normal epic loot of the same item id posts normally again
  W.Advance(130)
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. epic .. ".")
  H.eq(#H.EventsOfType(ns, "loot"), 4)
end)

H.test("loot: someone else winning the item you needed is not posted", function()
  local ns = H.Boot()
  local boots = link(2000, "Green Boots")
  W.items[2000] = { name = "Green Boots", quality = 2 }
  W.Fire("CHAT_MSG_LOOT", "You have selected Need for: " .. boots)
  W.Fire("CHAT_MSG_LOOT", "Bob won: " .. boots)
  H.eq(#H.EventsOfType(ns, "loot"), 0)
end)

H.test("loot: need win with Forever chat format ([Loot]: prefix, full name with surname)", function()
  local ns = H.Boot()
  local legs = "|cff0070dd|Hitem:2100::::::::60:::::|h[Leggings of Frenzied Magic]|h|r"
  W.items[2100] = { name = "Leggings of Frenzied Magic", quality = 3, equipLoc = "INVTYPE_LEGS" }
  W.Fire("CHAT_MSG_LOOT", "[Loot]: Jopindo Moonblade has selected Greed for: " .. legs)
  W.Fire("CHAT_MSG_LOOT", "[Loot]: You have selected Need for: " .. legs)
  W.Fire("CHAT_MSG_LOOT", "[Loot]: Need Roll - 84 for " .. legs .. " by Testchar Ragnvaldjord")
  W.Fire("CHAT_MSG_LOOT", "[Loot]: You won: " .. legs)
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. legs .. ".")
  local ev = H.EventsOfType(ns, "loot")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"roll":"need"')
  H.contains(ev[1].raw, '"rollValue":84')
  H.contains(ev[1].raw, '"item":"Leggings of Frenzied Magic"')
end)

H.test("loot: need win from the loot history (no chat lines at all)", function()
  local ns = H.Boot()
  local ruby = "|cff1eff00|Hitem:7910::::::::60:::::|h[Star Ruby]|h|r"
  W.items[7910] = { name = "Star Ruby", quality = 2 }
  local players = { { "Arve Benito", "WARRIOR", 2, 12 }, { "Testchar", "WARRIOR", 1, 55 } }
  C_LootHistory = {
    GetNumItems = function() return 1 end,
    GetItem = function() return 77, ruby, 2, true, 2 end,
    GetPlayerInfo = function(_, p) local x = players[p] return x[1], x[2], x[3], x[4], p == 2 end,
  }
  W.Fire("LOOT_HISTORY_ROLL_COMPLETE")
  W.Advance(0.3)
  W.Fire("LOOT_HISTORY_FULL_UPDATE")
  W.Advance(0.3)
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. ruby)
  C_LootHistory = nil
  local ev = H.EventsOfType(ns, "loot")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"roll":"need"')
  H.contains(ev[1].raw, '"rollValue":55')
end)

H.test("loot: greed win in the loot history does not post; roll lines on CHAT_MSG_SYSTEM work", function()
  local ns = H.Boot()
  local ruby = "|cff1eff00|Hitem:7910::::::::60:::::|h[Star Ruby]|h|r"
  W.items[7910] = { name = "Star Ruby", quality = 2 }
  C_LootHistory = {
    GetNumItems = function() return 1 end,
    GetItem = function() return 78, ruby, 1, true, 1 end,
    GetPlayerInfo = function() return "Testchar", "WARRIOR", 2, 90, true end,
  }
  W.Fire("LOOT_HISTORY_ROLL_COMPLETE")
  W.Advance(0.3)
  C_LootHistory = nil
  H.eq(#H.EventsOfType(ns, "loot"), 0)
  W.Fire("CHAT_MSG_SYSTEM", "|HlootHistory:9|h[Loot]|h: You have selected Need for: " .. ruby)
  W.Fire("CHAT_MSG_SYSTEM", "|HlootHistory:9|h[Loot]|h: You won: " .. ruby)
  H.eq(#H.EventsOfType(ns, "loot"), 1)
  SlashCmdList["NAVTOK"]("probe loot")
  W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. ruby)
  H.contains(NavtokDiscordDB.probe[#NavtokDiscordDB.probe], "CHAT_MSG_LOOT: You receive loot: ||cff1eff00")
end)

H.test("loot: need win from the modern loot history (winner isSelf, state Need)", function()
  local ns = H.Boot()
  local rune = "|cff1eff00|Hitem:12662::::::::60:::::|h[Demonic Rune]|h|r"
  W.items[12662] = { name = "Demonic Rune", quality = 2 }
  local drops = {
    { lootListID = 1, itemHyperlink = rune, winner = { playerName = "Arve Benito", roll = 66, state = 0, isSelf = false } },
    { lootListID = 2, itemHyperlink = rune, winner = { playerName = "Testchar", roll = 91, state = 0, isSelf = true } },
    { lootListID = 3, itemHyperlink = rune, winner = { playerName = "Testchar", roll = 80, state = 3, isSelf = true } }, -- greed
  }
  C_LootHistory = { GetSortedDropsForEncounter = function() return drops end }
  W.Fire("LOOT_HISTORY_UPDATE_DROP", 99, 2)
  W.Advance(0.3)
  W.Fire("LOOT_HISTORY_UPDATE_ENCOUNTER", 99)
  W.Advance(0.3)
  C_LootHistory = nil
  local ev = H.EventsOfType(ns, "loot")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"rollValue":91')
  H.contains(ev[1].raw, '"item":"Demonic Rune"')
end)

H.test("core: after an update the new version announces itself once", function()
  local ns = H.Boot({ db = { loadedVersion = "0.0.1" } })
  H.contains(table.concat(W.chat, "\n"), "updated to v" .. ns.VERSION)
  local n = #W.chat
  H.Boot({ db = NavtokDiscordDB })
  H.ok(not table.concat(W.chat, "\n"):find("updated to"), "not again")
end)
