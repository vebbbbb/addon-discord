local function link(id, name, color) return "|cff" .. (color or "0070dd") .. "|Hitem:" .. id .. "::::::::60:::::|h[" .. name .. "]|h|r" end

H.test("equip: BoE equipped after the bind confirmation posts (blue+), other gear swaps do not", function()
  local ns = H.Boot()
  local helm = link(3000, "Blue Helm")
  local green = link(3001, "Green Belt", "1eff00")
  W.items[3000] = { name = "Blue Helm", quality = 3 }
  W.items[3001] = { name = "Green Belt", quality = 2 }
  W.equipped[1] = link(9, "Old Helm")
  W.Fire("PLAYER_EQUIPMENT_CHANGED", 1, true) -- normal swap: no confirmation
  H.eq(#H.EventsOfType(ns, "equip"), 0)
  W.cursor = helm
  W.Fire("EQUIP_BIND_CONFIRM", 1)
  W.equipped[1] = helm
  W.Fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
  local ev = H.EventsOfType(ns, "equip")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"item":"Blue Helm"')
  H.contains(ev[1].raw, '"slot":1')
  W.cursor = nil
  W.Fire("AUTOEQUIP_BIND_CONFIRM", 6)
  W.equipped[6] = green
  W.Fire("PLAYER_EQUIPMENT_CHANGED", 6, true)
  H.eq(#H.EventsOfType(ns, "equip"), 1, "green below the default minimum")
end)

H.test("recipe: learned from a recipe item posts; trainer recipes do not", function()
  local ns = H.Boot()
  local r = link(4000, "Recipe: Elixir of Giants", "1eff00")
  W.items[4000] = { name = "Recipe: Elixir of Giants", quality = 2, classID = 9 }
  W.bags[0] = { [3] = r, [4] = link(4001, "Linen Cloth", "ffffff") }
  W.items[4001] = { name = "Linen Cloth", quality = 1, classID = 7 }
  -- trainer: no item used
  W.Fire("CHAT_MSG_SYSTEM", "You have learned how to create a new item: Minor Healing Potion.")
  H.eq(#H.EventsOfType(ns, "recipe"), 0)
  -- using a non-recipe item does not count
  UseContainerItem(0, 4)
  W.Fire("CHAT_MSG_SYSTEM", "You have learned how to create a new item: Something.")
  H.eq(#H.EventsOfType(ns, "recipe"), 0)
  UseContainerItem(0, 3)
  W.Fire("CHAT_MSG_SYSTEM", "You have learned how to create a new item: |cffffffff|Hitem:9206|h[Elixir of Giants]|h|r.")
  local ev = H.EventsOfType(ns, "recipe")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"item":"Recipe: Elixir of Giants"')
  H.contains(ev[1].raw, '"learned":"Elixir of Giants"')
  H.contains(ev[1].raw, '"quality":2')
end)

H.test("death: killed by a player is marked pvp", function()
  local ns = H.Boot()
  W.target = { name = "Gankster", hostile = true, player = true }
  W.Fire("PLAYER_DEAD")
  H.contains(H.EventsOfType(ns, "death")[1].raw, '"pvp":1')
  W.Advance(30)
  W.target = { name = "Hogger", hostile = true }
  W.Fire("PLAYER_DEAD")
  H.ok(not H.EventsOfType(ns, "death")[2].raw:find('"pvp"'), "mob kill is not pvp")
end)
