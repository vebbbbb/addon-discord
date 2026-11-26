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
