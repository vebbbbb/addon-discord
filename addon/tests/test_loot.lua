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
