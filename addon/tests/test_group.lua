local function enter(name, itype, mapId)
  W.instance = name and { name = name, type = itype or "party", mapId = mapId } or nil
  W.Fire("PLAYER_ENTERING_WORLD", false, false)
end

H.test("group: final boss - the alphabetically first claimant posts, with the group names", function()
  -- we are "Testchar"; Kjell (before us) also runs NAVTOK -> Kjell posts, we do not
  local ns = H.Boot({ setup = function(w) w.party = { "Kjell", "Zed" } end })
  enter("Deadmines", "party", 36)
  W.AddonMsg("Kjell", "C\tK:2747") -- Kjell's claim arrives first
  W.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 0, 5, 1)
  H.eq(W.sent[#W.sent][2], "C\tK:2747", "we claim too")
  W.Advance(2)
  H.eq(#H.EventsOfType(ns, "dungeon"), 0, "Kjell posts it")
  H.ok(ns.char.run == nil or ns.char.run.done, "our run counts as done (no popup later)")

  -- now only Zed (after us) claims -> we post
  local ns2 = H.Boot({ setup = function(w) w.party = { "Kjell", "Zed" } end })
  enter("Deadmines", "party", 36)
  W.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 0, 5, 1)
  W.AddonMsg("Zed", "C\tK:2747")
  W.Advance(2)
  local ev = H.EventsOfType(ns2, "dungeon")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"group":"Testchar, Kjell, Zed"')
end)

H.test("group: solo posts immediately, without a group field", function()
  local ns = H.Boot()
  W.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 0, 5, 1)
  local ev = H.EventsOfType(ns, "dungeon")
  H.eq(#ev, 1)
  H.ok(not ev[1].raw:find('"group"'))
end)

H.test("group: a member's dungeon summary closes our popup and stops ours", function()
  local ns = H.Boot({ setup = function(w) w.party = { "Kjell" } end })
  enter("Blackmaw Hold", "party", 2974)
  W.Fire("ENCOUNTER_END", 3315, "Withermaw", 0, 5, 1)
  W.Advance(2)
  enter(nil)
  H.eq(#W.popups, 1)
  W.AddonMsg("Kjell", "D\tS:2974") -- Kjell answered Yes first
  H.eq(W.hiddenPopups[1], "NAVTOK_DUNGEON_DONE")
  -- even if we click Yes afterwards, nothing is posted twice
  W.ClickPopup("accept")
  local posts = 0
  for _, e in ipairs(H.Events(ns)) do if e.type == "dungeon" and not e.raw:find('"candidate"') then posts = posts + 1 end end
  H.eq(posts, 0)
end)

H.test("group: our Yes posts the summary and tells the group", function()
  local ns = H.Boot({ setup = function(w) w.party = { "Kjell" } end })
  enter("Blackmaw Hold", "party", 2974)
  W.Fire("ENCOUNTER_END", 3315, "Withermaw", 0, 5, 1)
  W.Advance(2)
  enter(nil)
  W.ClickPopup("accept")
  H.eq(W.sent[#W.sent][2], "D\tS:2974")
  local ev = H.EventsOfType(ns, "dungeon")
  H.contains(ev[#ev].raw, '"group":"Testchar, Kjell"')
end)

H.test("group: rare killed together posts once; deaths are never shared", function()
  local ns = H.Boot({ setup = function(w) w.party = { "Abe" } end })
  W.AddonMsg("Abe", "C\tE:Creature-0-1-0-1-522-1")
  W.target = { name = "Mor'Ladim", guid = "Creature-0-1-0-1-522-1", classification = "rareelite", hostile = true, dead = true }
  W.Fire("PLAYER_TARGET_CHANGED")
  W.Advance(2)
  H.eq(#H.EventsOfType(ns, "rare"), 0, "Abe posts it")
  W.Fire("PLAYER_DEAD")
  H.eq(#H.EventsOfType(ns, "death"), 1, "own death always posts")
end)

H.test("group: the same final boss again 15 minutes later posts again", function()
  local ns = H.Boot({ setup = function(w) w.party = { "Zed" } end })
  W.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 0, 5, 1)
  W.Advance(2)
  W.Advance(900)
  W.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 0, 5, 1)
  W.Advance(2)
  H.eq(#H.EventsOfType(ns, "dungeon"), 2)
end)
