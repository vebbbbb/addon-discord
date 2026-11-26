local function enterBG(w, instanceID)
  w.bg.instance = { true, "pvp" }
  w.bg.status = { { status = "active", map = "Warsong Gulch", instanceID = instanceID } }
  w.bg.scores = {
    { name = "Enemy", kb = 9, hk = 9, deaths = 9, honor = 9, faction = 0 },
    { name = "Testchar", kb = 7, hk = 31, deaths = 2, honor = 412, faction = 1 },
  }
  w.bg.runtime = 1234567
end

H.test("bg: win posted once, after ~1 s, with own score row", function()
  local ns = H.Boot({ setup = function(w) enterBG(w, 17) end })
  W.Fire("UPDATE_BATTLEFIELD_SCORE")
  H.eq(#H.EventsOfType(ns, "bg"), 0, "no winner yet")
  W.bg.winner = 1 -- Alliance
  W.Fire("UPDATE_BATTLEFIELD_STATUS")
  W.Fire("UPDATE_BATTLEFIELD_SCORE")
  H.eq(W.bg.requested, 1, "score data requested once")
  H.eq(#H.EventsOfType(ns, "bg"), 0, "waits for scoreboard")
  W.Advance(1.05)
  local ev = H.EventsOfType(ns, "bg")
  H.eq(#ev, 1)
  for _, k in ipairs({ '"result":"win"', '"bg":"Warsong Gulch"', '"kb":7', '"hk":31', '"deaths":2', '"honor":412',
    '"duration":1234' }) do H.contains(ev[1].raw, k) end
  for _ = 1, 5 do W.Fire("UPDATE_BATTLEFIELD_SCORE"); W.Advance(1.1) end
  H.eq(#H.EventsOfType(ns, "bg"), 1, "once per instance")
  W.Advance(2)
  H.ok(#W.screenshots >= 1)
end)

H.test("bg: loss for the other faction; realm-suffixed names match", function()
  local ns = H.Boot({ setup = function(w)
    enterBG(w, 18)
    w.bg.scores[2].name = "Testchar-Otherrealm"
  end })
  W.bg.winner = 0 -- Horde
  W.Fire("UPDATE_BATTLEFIELD_SCORE")
  W.Advance(1.1)
  local raw = H.EventsOfType(ns, "bg")[1].raw
  H.contains(raw, '"result":"loss"')
  H.contains(raw, '"kb":7')
end)

H.test("bg: /reload on the scoreboard does not post again", function()
  local ns = H.Boot({ setup = function(w) enterBG(w, 19) end })
  W.bg.winner = 1
  W.Fire("UPDATE_BATTLEFIELD_SCORE")
  W.Advance(1.1)
  H.eq(#H.EventsOfType(ns, "bg"), 1)
  local db = NavtokDiscordDB
  local ns2 = H.Boot({ db = db, setup = function(w) enterBG(w, 19); w.bg.winner = 1 end })
  W.Fire("UPDATE_BATTLEFIELD_SCORE")
  W.Advance(1.1)
  H.eq(#H.EventsOfType(ns2, "bg"), 1, "still one")
end)

H.test("bg: instanceID 0 -> start-time key, next instance posts again", function()
  local ns = H.Boot({ setup = function(w) enterBG(w, 0) end })
  W.bg.winner = 1
  W.Fire("UPDATE_BATTLEFIELD_SCORE"); W.Advance(1.1)
  -- reload 20 s later (runtime grew by the same amount => same start bucket)
  W.bg.runtime = W.bg.runtime + 20000
  W.Fire("UPDATE_BATTLEFIELD_SCORE"); W.Advance(1.1)
  H.eq(#H.EventsOfType(ns, "bg"), 1)
  -- a new game started 30 min later
  W.Advance(1800)
  W.bg.runtime = 600000
  W.Fire("UPDATE_BATTLEFIELD_SCORE"); W.Advance(1.1)
  H.eq(#H.EventsOfType(ns, "bg"), 2)
end)

H.test("bg: winner outside a battleground is ignored", function()
  local ns = H.Boot()
  W.bg.winner = 1
  W.Fire("UPDATE_BATTLEFIELD_SCORE"); W.Advance(1.1)
  H.eq(#H.EventsOfType(ns, "bg"), 0)
end)
