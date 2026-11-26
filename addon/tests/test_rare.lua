local GUID = "Creature-0-4372-0-17-522-00002A3F1C"

local function rare(over)
  local u = { name = "Mor'Ladim", guid = GUID, classification = "rareelite", level = 35, hostile = true }
  for k, v in pairs(over or {}) do u[k] = v end
  return u
end

H.test("rare: target rare dies (our tag) -> one post with npc id and zone", function()
  local ns = H.Boot()
  W.target = rare()
  W.Fire("PLAYER_TARGET_CHANGED")
  H.eq(#H.EventsOfType(ns, "rare"), 0, "alive")
  W.target.dead = true
  W.Fire("UNIT_HEALTH", "target")
  W.Fire("UNIT_HEALTH", "target")
  W.Fire("PLAYER_TARGET_CHANGED")
  local ev = H.EventsOfType(ns, "rare")
  H.eq(#ev, 1)
  for _, k in ipairs({ '"npc":"Mor\'Ladim"', '"npcId":522', '"classification":"rareelite"', '"mobLevel":35',
    '"zone":"Elwynn Forest"' }) do H.contains(ev[1].raw, k) end
end)

H.test("rare: someone else's tag, normal mobs and players are ignored", function()
  local ns = H.Boot()
  W.target = rare({ dead = true, tapDenied = true })
  W.Fire("PLAYER_TARGET_CHANGED")
  W.target = rare({ guid = "Creature-0-1-0-1-99-1", classification = "normal", dead = true })
  W.Fire("PLAYER_TARGET_CHANGED")
  W.target = rare({ guid = "Player-1-0001", player = true, dead = true })
  W.Fire("PLAYER_TARGET_CHANGED")
  H.eq(#H.EventsOfType(ns, "rare"), 0)
end)

H.test("rare: nameplate / mouseover units count too", function()
  local ns = H.Boot()
  W.units.nameplate3 = rare({ dead = true })
  W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
  H.eq(#H.EventsOfType(ns, "rare"), 1)
end)

H.test("rare: XP message for a recently seen rare posts (killed without it targeted at death)", function()
  local ns = H.Boot()
  W.units.mouseover = rare()
  W.Fire("UPDATE_MOUSEOVER_UNIT")
  W.units.mouseover = nil
  W.Advance(30)
  W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Mor'Ladim dies, you gain 1450 experience. (+120 group bonus)")
  W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 50 experience.")
  H.eq(#H.EventsOfType(ns, "rare"), 1)
  W.Advance(200) -- too old
  W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Mor'Ladim dies, you gain 1450 experience.")
  H.eq(#H.EventsOfType(ns, "rare"), 1)
end)

H.test("rare: classifications are configurable (worldboss)", function()
  local ns = H.Boot()
  ns.settings.rareClassifications.worldboss = true
  W.target = rare({ guid = "Creature-0-1-0-1-6109-1", name = "Azuregos", classification = "worldboss", dead = true })
  W.Fire("PLAYER_TARGET_CHANGED")
  H.eq(#H.EventsOfType(ns, "rare"), 1)
end)
