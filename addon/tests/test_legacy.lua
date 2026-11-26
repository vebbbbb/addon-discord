H.test("legacy: ACHIEVEMENT_EARNED for a legacy challenge posts with group; others ignored", function()
  local ns = H.Boot()
  W.achievements[62382] = "Explorer"
  W.Fire("ACHIEVEMENT_EARNED", 62382, false)
  W.Fire("ACHIEVEMENT_EARNED", 999999, false) -- not a legacy challenge
  W.Fire("ACHIEVEMENT_EARNED", 64015, false)  -- same challenge, second data variant -> deduped
  local ev = H.EventsOfType(ns, "legacy")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"achievementId":62382')
  H.contains(ev[1].raw, '"text":"Explorer"')
  H.contains(ev[1].raw, '"group":"Adventure"')
end)

H.test("legacy: localized name from GetAchievementInfo, zone steps follow legacyZones", function()
  local ns = H.Boot()
  W.achievements[62012] = "Alchimiste compagnon"
  W.Fire("ACHIEVEMENT_EARNED", 62012)
  H.contains(H.EventsOfType(ns, "legacy")[1].raw, '"text":"Alchimiste compagnon"')
  ns.settings.legacyZones = false
  W.Fire("ACHIEVEMENT_EARNED", 776) -- Explore Elwynn Forest
  H.eq(#H.EventsOfType(ns, "legacy"), 1)
  ns.settings.legacyZones = true
  W.Advance(11)
  W.Fire("ACHIEVEMENT_EARNED", 776)
  H.eq(#H.EventsOfType(ns, "legacy"), 2)
end)

H.test("legacy: generated table has every category", function()
  local ns = H.Boot()
  local groups = {}
  for _, e in pairs(ns.Data.Legacy) do groups[e.group:match("^[^:]+")] = true end
  for _, g in ipairs({ "Classes", "Tradeskills", "Dungeons", "Raids", "Player vs. Player", "Adventure" }) do
    H.ok(groups[g], g)
  end
end)

H.test("legacy: system-message fallback only when ACHIEVEMENT_EARNED does not exist", function()
  local ns = H.Boot()
  W.Fire("CHAT_MSG_SYSTEM", "Legacy challenge complete: Explorer")
  H.eq(#H.EventsOfType(ns, "legacy"), 0, "achievement path active")
  local ns2 = H.Boot({ setup = function(w) w.unknownEvents.ACHIEVEMENT_EARNED = true end })
  W.Fire("CHAT_MSG_SYSTEM", "Legacy challenge complete: |cffffd000Explorer|r")
  W.Fire("CHAT_MSG_SYSTEM", "You are now AFK.")
  local ev = H.EventsOfType(ns2, "legacy")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"text":"Legacy challenge complete: Explorer"')
end)
