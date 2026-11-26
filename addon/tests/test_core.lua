H.test("core: ring buffer keeps last 300 events per character", function()
  local ns = H.Boot()
  for i = 1, 310 do ns.Emit("skill", { skill = "S", rank = i }) end
  local ev = H.Events(ns)
  H.eq(#ev, 300)
  H.contains(ev[1].raw, '"rank":11')
  H.contains(ev[300].raw, '"rank":310')
end)

H.test("core: event ids are unique and seq survives reload", function()
  local ns = H.Boot()
  local a = ns.Emit("skill", { skill = "A", rank = 75 })
  local b = ns.Emit("skill", { skill = "B", rank = 75 })
  H.ok(a.id ~= b.id)
  local db = NavtokDiscordDB
  local ns2 = H.Boot({ db = db })
  local c = ns2.Emit("skill", { skill = "C", rank = 75 })
  H.eq(c.seq, b.seq + 1, "seq continues after /reload")
end)

H.test("core: event json contract", function()
  local ns = H.Boot()
  ns.Emit("loot", { itemId = 19019, quality = 5, count = 1, item = "TF" })
  local raw = H.Events(ns)[1].raw
  for _, k in ipairs({ '"type":"loot"', '"char":"Testchar"', '"realm":"Testrealm"', '"class":"WARRIOR"',
    '"classId":1', '"level":20', '"test":false', '"data":{"count":1,"item":"TF","itemId":19019,"quality":5}' }) do
    H.contains(raw, k)
  end
  H.ok(raw:match('"id":"%d+%.%d+"'), "id format ts.seq")
  local db = NavtokDiscordDB
  H.ok(db.chars["Testchar-Testrealm"], "per character key Name-Realm")
end)

H.test("core: settings defaults and persistence", function()
  local ns = H.Boot()
  H.eq(ns.settings.position, "TOPRIGHT")
  H.eq(ns.settings.hideChat, true)
  ns.settings.position = "BOTTOMLEFT"
  local ns2 = H.Boot({ db = NavtokDiscordDB })
  H.eq(ns2.settings.position, "BOTTOMLEFT")
end)

H.test("core: FormatToPattern", function()
  local ns = H.Boot()
  local p = ns.FormatToPattern("You receive loot: %sx%d.")
  H.eq(p, "^You receive loot: (.+)x(%d+)%.$")
  local a, b = ("You receive loot: [X]x3."):match(p)
  H.eq(a, "[X]"); H.eq(b, "3")
  H.eq(ns.FormatToPattern("%1$s got %2$d"), "^(.+) got (%d+)$")
end)

H.test("core: a failing handler does not break other handlers", function()
  local ns = H.Boot()
  local hit = false
  ns.On("TEST_EVENT", function() error("boom") end)
  ns.On("TEST_EVENT", function() hit = true end)
  W.Fire("TEST_EVENT")
  H.ok(hit)
end)
