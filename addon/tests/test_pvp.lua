local function hk(victim) W.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", victim .. " dies, honorable kill Rank: Sergeant (Estimated Honor Points: 40)") end

H.test("death: every 50th lifetime death (statistic 60) and 50th death to players (1501)", function()
  local ns = H.Boot({ setup = function(w) w.stats[60] = "48"; w.stats[1501] = "49" end })
  W.Fire("PLAYER_DEAD")                   -- statistic not updated yet: this is death 49
  H.ok(not H.EventsOfType(ns, "death")[1].raw:find("deathNo"))
  W.Advance(30)
  W.stats[60] = "49"                      -- statistic lagging one behind: still 50
  W.target = { name = "Gankster", hostile = true, player = true }
  W.Fire("PLAYER_DEAD")                   -- killed by a player: 50th total AND 50th pvp death
  local raw = H.EventsOfType(ns, "death")[2].raw
  H.contains(raw, '"deathNo":50')
  H.contains(raw, '"pvpDeathNo":50')
  W.Advance(30)
  W.stats[60] = "51"                      -- statistic already updated: 51, no milestone
  W.target = nil
  W.Fire("PLAYER_DEAD")
  H.ok(not H.EventsOfType(ns, "death")[3].raw:find("DeathNo"))
end)

H.test("pvp: rank up posts (first scan only seeds); HK milestones", function()
  local ns = H.Boot({ setup = function(w) w.pvpRank = 7; w.stats[588] = "95" end })
  W.Fire("PLAYER_PVP_RANK_CHANGED")
  H.eq(#H.EventsOfType(ns, "pvp"), 0)
  W.pvpRank = 8
  W.Fire("PLAYER_PVP_RANK_CHANGED")
  local ev = H.EventsOfType(ns, "pvp")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"sub":"rank"')
  W.stats[588] = "101"
  W.Fire("PLAYER_PVP_KILLS_CHANGED")
  ev = H.EventsOfType(ns, "pvp")
  H.eq(#ev, 2)
  H.contains(ev[2].raw, '"count":100')
end)

H.test("pvp: world fight summary counts different victims, group posts once, min 3", function()
  local ns = H.Boot({ setup = function(w) w.party = { "Zed" } end })
  hk("Gank1"); W.AddonMsg("Zed", "H\tGank1") -- same victim credited to both: counted once
  hk("Gank2"); W.AddonMsg("Zed", "H\tGank2")
  W.Advance(35)
  hk("Gank3")
  W.Advance(301)
  local ev = H.EventsOfType(ns, "pvp")
  local summary
  for _, e in ipairs(ev) do if e.raw:find('"sub":"worldpvp"') then summary = e end end
  H.ok(summary, "summary posted")
  H.contains(summary.raw, '"count":3')
  H.contains(summary.raw, '"group":"Testchar, Zed"')
  H.ok(summary.raw:find('"shotSeq"'), "uses a kept kill screenshot")
  H.contains(summary.raw, '"victims":"Gank1, Gank2, Gank3"')
end)

H.test("pvp: Abe took part (alphabetically first) -> we do not post; 2 kills is not enough", function()
  local ns = H.Boot({ setup = function(w) w.party = { "Abe" } end })
  W.AddonMsg("Abe", "H\tA"); hk("A"); hk("B"); hk("C")
  W.Advance(301)
  local n = 0
  for _, e in ipairs(H.EventsOfType(ns, "pvp")) do if e.raw:find('"sub":"worldpvp"') then n = n + 1 end end
  H.eq(n, 0)
  local ns2 = H.Boot()
  hk("A"); hk("B")
  W.Advance(301)
  for _, e in ipairs(H.EventsOfType(ns2, "pvp")) do H.ok(not e.raw:find('"sub":"worldpvp"'), "below minimum") end
end)

H.test("pvp: battleground honorable kills are ignored", function()
  local ns = H.Boot({ setup = function(w) w.bg.instance = { true, "pvp" } end })
  hk("A"); hk("B"); hk("C")
  W.Advance(301)
  H.eq(#H.EventsOfType(ns, "pvp"), 0)
end)

H.test("pvp: HK milestones also post inside a battleground (only the world PvP summary skips them)", function()
  local ns = H.Boot({ setup = function(w) w.stats[588] = "998"; w.bg.instance = { true, "pvp" } end })
  W.stats[588] = "1000"
  hk("Enemy")
  W.Advance(1.5)
  local ev = H.EventsOfType(ns, "pvp")
  H.eq(#ev, 1)
  H.contains(ev[1].raw, '"sub":"hk"')
  H.contains(ev[1].raw, '"count":1000')
  W.Advance(301)
  H.eq(#H.EventsOfType(ns, "pvp"), 1, "no world PvP summary from a battleground")
end)
