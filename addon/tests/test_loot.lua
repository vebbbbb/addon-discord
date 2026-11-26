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
