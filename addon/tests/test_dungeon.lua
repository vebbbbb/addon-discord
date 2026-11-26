local function enter(name, itype, mapId)
  W.instance = name and { name = name, type = itype or "party", mapId = mapId } or nil
  W.Fire("PLAYER_ENTERING_WORLD", false, false)
end

H.test("dungeon: known final boss posts right away; no summary on leaving", function()
  local ns = H.Boot()
  enter("Deadmines", "party", 36)
  W.Fire("ENCOUNTER_END", 2741, "Rhahk'Zor", 0, 5, 1)
  W.Advance(60)
  W.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 0, 5, 1)
  local ev = H.EventsOfType(ns, "dungeon")
  H.eq(#ev, 2, "candidate for Rhahk'Zor + final")
  H.contains(ev[1].raw, '"candidate":true')
  H.contains(ev[2].raw, '"instance":"Deadmines"')
  H.contains(ev[2].raw, '"bosses":2')
  H.ok(not ev[2].raw:find('"candidate"'), "final is a normal post")
  enter(nil)
  H.eq(#H.EventsOfType(ns, "dungeon"), 2, "no summary after a known final")
end)

local function kills(ids)
  for _, k in ipairs(ids) do W.Fire("ENCOUNTER_END", k[1], k[2], 0, 5, 1); W.Advance(60) end
end

H.test("dungeon: leave alive without final -> popup; Yes posts summary with last boss shot", function()
  local ns = H.Boot()
  enter("Blackmaw Hold", "party", 2974)
  kills({ { 3315, "Withermaw" }, { 3316, "Impaan the Imprisoner" } })
  W.Fire("ENCOUNTER_END", 3327, "Elder Shaman Bloodmane", 0, 5, 0) -- wipe on a boss: ignored
  local cands = H.EventsOfType(ns, "dungeon")
  H.eq(#cands, 2, "a candidate screenshot per boss kill")
  H.contains(cands[1].raw, '"candidate":true')
  local lastSeq = cands[2].raw:match('"seq":(%d+)')
  H.eq(#W.popups, 0)
  enter(nil) -- hearth out, alive
  H.eq(#W.popups, 1, "asked once")
  H.eq(W.popups[1].arg1, "Blackmaw Hold")
  H.eq(#H.EventsOfType(ns, "dungeon"), 2, "nothing posted before the answer")
  W.ClickPopup("accept")
  local ev = H.EventsOfType(ns, "dungeon")
  H.eq(#ev, 3)
  local s = ev[3].raw
  H.ok(not s:find('"candidate"'))
  for _, k in ipairs({ '"shotSeq":' .. lastSeq, '"bosses":2', '"instance":"Blackmaw Hold"',
    '"encounter":"Impaan the Imprisoner"' }) do H.contains(s, k) end
  enter(nil)
  H.eq(#W.popups, 1, "not asked again")
end)

H.test("dungeon: answering No posts nothing", function()
  local ns = H.Boot()
  enter("Alcaz Prison", "party", 2994)
  kills({ { 3403, "Overseer Wrex" } })
  enter(nil)
  W.ClickPopup("cancel")
  H.eq(#H.EventsOfType(ns, "dungeon"), 1, "only the candidate")
end)

H.test("dungeon: dying and running back never asks; leaving alive later does", function()
  local ns = H.Boot()
  enter("The Drowned City", "party", 2970)
  kills({ { 3474, "Zul'Alai" } })
  W.player.dead = true -- wipe, release: ghost at the graveyard outside
  enter(nil)
  W.Fire("ZONE_CHANGED_NEW_AREA")
  H.eq(#W.popups, 0, "no popup for a death")
  enter("The Drowned City", "party", 2970) -- runback: resurrected inside
  W.player.dead = false
  H.ok(ns.char.run and ns.char.run.bosses == 1, "same run continues")
  kills({ { 3475, "Var'Taka" } })
  enter(nil)
  H.eq(#W.popups, 1)
  W.ClickPopup("accept")
  H.contains(H.EventsOfType(ns, "dungeon")[3].raw, '"bosses":2')
end)

H.test("dungeon: spirit healer outside never asks; /navtok done asks on demand", function()
  local ns = H.Boot()
  enter("Krol'dok Stronghold", "party", 3039)
  kills({ { 3450, "Slavecrusher Grox" } })
  W.player.dead = true
  enter(nil)
  W.player.dead = false -- resurrected at the spirit healer, walks away
  W.Fire("ZONE_CHANGED_NEW_AREA")
  H.eq(#W.popups, 0)
  SlashCmdList["NAVTOK"]("done")
  H.eq(#W.popups, 1)
  W.ClickPopup("accept")
  H.eq(#H.EventsOfType(ns, "dungeon"), 2)
end)

H.test("dungeon: final boss killed -> no popup; run survives /reload", function()
  local ns = H.Boot()
  enter("Deadmines", "party", 36)
  kills({ { 2741, "Rhahk'Zor" } })
  local ns2 = H.Boot({ db = NavtokDiscordDB, setup = function(w) w.instance = { name = "Deadmines", type = "party", mapId = 36 } end })
  H.ok(ns2.char.run and ns2.char.run.bosses == 1, "run kept across /reload")
  kills({ { 2747, "Edwin VanCleef" } })
  enter(nil)
  H.eq(#W.popups, 0)
  local ev = H.EventsOfType(ns2, "dungeon")
  H.contains(ev[#ev].raw, '"bosses":2')
end)

H.test("dungeon: raid left without final asks too; no kills -> no popup", function()
  H.Boot()
  enter("Alcaz Prison", "party", 2994)
  enter(nil)
  H.eq(#W.popups, 0)
  enter("Nightmare Grove", "raid", 2832)
  W.Fire("ENCOUNTER_END", 9001, "Some New Raid Boss", 0, 20, 1)
  enter(nil) -- back in the open world
  H.eq(#W.popups, 1)
end)

H.test("dungeon: unknown id but known final name still posts (fallback)", function()
  local ns = H.Boot()
  W.Fire("ENCOUNTER_END", 99999, "Edwin VanCleef", 1, 5, 1)
  local ev = H.EventsOfType(ns, "dungeon")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"instance":"Deadmines"')
end)
