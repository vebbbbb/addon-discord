H.test("death: zone, subzone, hostile target as killer", function()
  local ns = H.Boot()
  W.target = { name = "Hogger", hostile = true }
  W.Fire("PLAYER_DEAD")
  local ev = H.EventsOfType(ns, "death")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"killer":"Hogger"')
  H.contains(ev[1].raw, '"zone":"Elwynn Forest"')
  H.contains(ev[1].raw, '"subzone":"Goldshire"')
end)

H.test("death: last hostile target remembered; no killer when unknown", function()
  local ns = H.Boot()
  W.target = { name = "Defias Thug", hostile = true }
  W.Fire("PLAYER_TARGET_CHANGED")
  W.target = nil
  W.Fire("PLAYER_DEAD")
  H.contains(H.EventsOfType(ns, "death")[1].raw, '"killer":"Defias Thug"')
  W.Advance(30) -- a second death later on
  W.Fire("PLAYER_DEAD")
  local raw = H.EventsOfType(ns, "death")[2].raw
  H.ok(not raw:find('"killer"'), "no killer field")
end)

H.test("death: ignored right after login", function()
  W.Reset()
  local ns = H.Boot()
  ns.loginTime = GetTime()
  W.Fire("PLAYER_DEAD")
  H.eq(#H.EventsOfType(ns, "death"), 0)
end)

H.test("death: PLAYER_DEAD fired twice for one death posts once; a later death posts again", function()
  local ns = H.Boot()
  W.Fire("PLAYER_DEAD")
  W.Advance(0.2)
  W.Fire("PLAYER_DEAD")
  H.eq(#H.EventsOfType(ns, "death"), 1)
  W.Advance(60)
  W.Fire("PLAYER_DEAD")
  H.eq(#H.EventsOfType(ns, "death"), 2)
end)

local function die(times)
  for _ = 1, times do
    W.Fire("PLAYER_DEAD")
    W.Advance(15)
  end
end

local function lines(ns)
  local out = {}
  for i, e in ipairs(H.EventsOfType(ns, "death")) do out[i] = e.raw:match('"line":"(.-)"') or "-" end
  return out
end

H.test("session deaths: lines at 3, 5, 7 and every death from 10", function()
  local ns = H.Boot()
  die(12)
  local l = lines(ns)
  local with = {}
  for i, v in ipairs(l) do if v ~= "-" then with[#with + 1] = i end end
  H.eq(table.concat(with, ","), "3,5,7,10,11,12")
  H.ok(l[3]:match("^3:%d+$") and l[5]:match("^5:") and l[7]:match("^7:") and l[10]:match("^10:"), table.concat(l, " "))
  H.contains(H.EventsOfType(ns, "death")[12].raw, '"session":12')
end)

H.test("session deaths: no line during a boss fight, but the death counts", function()
  local ns = H.Boot()
  die(2)
  W.Fire("ENCOUNTER_START", 672, "Ragnaros", 9, 40)
  die(1) -- 3rd death, wipe on Ragnaros
  W.Fire("ENCOUNTER_END", 672, "Ragnaros", 9, 40, 0)
  die(2) -- 4th, 5th
  local l = lines(ns)
  H.eq(l[3], "-")
  H.ok(l[5] ~= "-")
  H.contains(H.EventsOfType(ns, "death")[5].raw, '"session":5')
end)

H.test("session deaths: /reload or a quick relog keep the count; 30+ min offline resets", function()
  local ns = H.Boot()
  die(4)
  local ns2 = H.Boot({ db = NavtokDiscordDB }) -- relog right away
  die(1)
  H.contains(H.EventsOfType(ns2, "death")[5].raw, '"session":5')
  NavtokDiscordDB.chars["Testchar-Testrealm"].lastSeen = time() - 4000 -- offline 30+ min (the fake clock restarts on boot)
  local ns3 = H.Boot({ db = NavtokDiscordDB })
  die(1)
  local ev = H.EventsOfType(ns3, "death")
  H.contains(ev[#ev].raw, '"session":1')
end)

H.test("session deaths: lines do not repeat within a pool and never twice in a row", function()
  local ns = H.Boot()
  local N = ns.notifiers.death
  local pool = select(2, N.PoolFor(10))
  local seen, prev = {}, nil
  for i = 1, #pool do
    local id = N:PickLine(10)
    H.ok(not seen[id], "repeat within the pool: " .. id)
    seen[id] = true
    prev = id
  end
  for _ = 1, 50 do
    local id = N:PickLine(12)
    H.ok(id ~= prev, "same line twice in a row")
    prev = id
  end
  H.eq(select(1, N.PoolFor(14)), "10")
  H.eq(select(1, N.PoolFor(19)), "15")
  H.eq(select(1, N.PoolFor(99)), "25")
  H.eq(N.PoolFor(4), nil)
end)
