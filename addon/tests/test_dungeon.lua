H.test("dungeon: unknown id falls back to the boss name; trash boss does not post", function()
  local ns = H.Boot()
  W.Fire("ENCOUNTER_END", 9999, "Edwin VanCleef", 1, 5, 1)
  W.Fire("ENCOUNTER_END", 9998, "Rhahk'Zor", 1, 5, 1)
  local ev = H.EventsOfType(ns, "dungeon")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"instance":"Deadmines"')
  H.contains(ev[1].raw, '"encounterId":9999')
end)

H.test("dungeon: wipe (success 0) does not post; raid final boss by id", function()
  local ns = H.Boot()
  W.Fire("ENCOUNTER_END", 672, "Ragnaros", 9, 40, 0)
  H.eq(#H.EventsOfType(ns, "dungeon"), 0)
  W.Fire("ENCOUNTER_END", 672, "Some Localized Name", 9, 40, 1)
  local ev = H.EventsOfType(ns, "dungeon")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"instance":"Molten Core"')
  H.ok(ns.Screenshot.queue[1].priority)
end)

H.test("dungeon: generated Forever ids (game data) post; non-final bosses do not", function()
  local ns = H.Boot()
  W.Fire("ENCOUNTER_END", 2741, "Rhahk'Zor", 0, 5, 1)          -- Deadmines first boss
  W.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 0, 5, 1)     -- Deadmines final
  W.Fire("ENCOUNTER_END", 448, "Herod", 0, 5, 1)               -- SM Armory wing
  W.Fire("ENCOUNTER_END", 3303, "Shade of the Archmage", 0, 5, 1) -- new Forever dungeon
  local ev = H.EventsOfType(ns, "dungeon")
  H.eq(#ev, 3)
  H.contains(ev[2].raw, '"instance":"Scarlet Monastery: Armory"')
  H.contains(ev[3].raw, '"instance":"City of Dalaran"')
  H.ok(ns.Data.Dungeons.byId[1084] and ns.Data.Dungeons.byId[672], "raid ids")
  local verified = 0
  for _, e in ipairs(ns.Data.Dungeons.list) do if e.verified then verified = verified + 1 end end
  H.ok(verified >= 40, "known finals marked verified")
end)
