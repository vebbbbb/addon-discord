H.test("skill: posts at 75/150/225/300 only, once", function()
  local ns = H.Boot()
  for _, r in ipairs({ 74, 75, 76, 150, 151, 225, 300 }) do
    W.Fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to " .. r .. ".")
  end
  W.Fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 75.")
  local ev = H.EventsOfType(ns, "skill")
  H.eq(#ev, 4)
  H.contains(ev[1].raw, '"rank":75')
  H.contains(ev[1].raw, '"skill":"Mining"')
  H.contains(ev[4].raw, '"rank":300')
end)
