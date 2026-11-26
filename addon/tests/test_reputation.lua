local function factions()
  return {
    { name = "Alliance", isHeader = true, hasRep = false },
    { name = "Stormwind", standingID = 4, factionID = 72 },
    { name = "Darnassus", standingID = 5, factionID = 69 },
    { name = "Bloodsail", standingID = 2, factionID = 87 },
  }
end

H.test("reputation: first scan seeds silently, increases post, decreases don't", function()
  local ns = H.Boot({ setup = function(w) w.factions = factions() end })
  H.eq(#H.EventsOfType(ns, "reputation"), 0, "seed is silent")
  W.factions[2].standingID = 5  -- Neutral -> Friendly
  W.Fire("UPDATE_FACTION")
  local ev = H.EventsOfType(ns, "reputation")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"faction":"Stormwind"')
  H.contains(ev[1].raw, '"standing":5')
  W.Fire("UPDATE_FACTION") -- no change
  H.eq(#H.EventsOfType(ns, "reputation"), 1)
  W.factions[3].standingID = 4 -- decrease
  W.Fire("UPDATE_FACTION")
  H.eq(#H.EventsOfType(ns, "reputation"), 1)
  W.factions[4].standingID = 3 -- increase but below Friendly
  W.Fire("UPDATE_FACTION")
  H.eq(#H.EventsOfType(ns, "reputation"), 1)
end)

H.test("reputation: every tier Friendly..Exalted", function()
  local ns = H.Boot({ setup = function(w) w.factions = factions() end })
  for s = 5, 8 do
    W.factions[2].standingID = s
    W.Fire("UPDATE_FACTION")
  end
  H.eq(#H.EventsOfType(ns, "reputation"), 4)
end)

H.test("reputation: cache persists across reload; collapsed headers are not changes", function()
  local ns = H.Boot({ setup = function(w) w.factions = factions() end })
  local db = NavtokDiscordDB
  local ns2 = H.Boot({ db = db, setup = function(w)
    w.factions = factions()
    w.factions[2].standingID = 6 -- changed while we were reloading: Honored (cached 4)
  end })
  H.eq(#H.EventsOfType(ns2, "reputation"), 1, "increase vs cached standing posts on login scan")
  -- collapse: factions disappear from the list
  W.factions = { { name = "Alliance", isHeader = true } }
  W.Fire("UPDATE_FACTION")
  W.factions = factions(); W.factions[2].standingID = 6
  W.Fire("UPDATE_FACTION")
  H.eq(#H.EventsOfType(ns2, "reputation"), 1, "expand again: nothing new")
end)
