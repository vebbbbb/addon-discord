local function run(cmd) SlashCmdList["NAVTOK"](cmd) end

H.test("commands: status, position, chat, debug, mode", function()
  local ns = H.Boot()
  H.eq(SLASH_NAVTOK1, "/navtok")
  run("")
  H.ok(#W.chat > 0)
  run("position bl")
  H.eq(ns.settings.position, "BOTTOMLEFT")
  run("position nowhere")
  H.eq(ns.settings.position, "BOTTOMLEFT")
  run("chat off"); H.eq(ns.settings.hideChat, false)
  run("chat on"); H.eq(ns.settings.hideChat, true)
  run("debug"); H.eq(ns.settings.debug, true)
  run("mode band"); H.eq(ns.settings.mode, "band")
  run("mode screenshot"); H.eq(ns.settings.mode, "screenshot")
end)

H.test("commands: test <type> works for every notifier and marks test", function()
  local ns = H.Boot()
  for _, t in ipairs(ns.notifierOrder) do run("test " .. t) end
  local ev = H.Events(ns)
  H.eq(#ev, #ns.notifierOrder)
  local seen = {}
  for _, e in ipairs(ev) do
    H.ok(e.test, e.type .. " is test")
    seen[e.type] = true
  end
  for _, t in ipairs(ns.notifierOrder) do H.ok(seen[t], "test " .. t) end
  -- every test event must encode into a barcode
  for _, line in ipairs(ns.char.events) do H.ok(#line > 0) end
  W.Advance(2.2 * #ns.notifierOrder + 2)
  H.eq(#W.screenshots, #ns.notifierOrder, "every test event screenshotted")
end)
