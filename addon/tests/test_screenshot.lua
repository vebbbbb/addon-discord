local function boot() return H.Boot() end

H.test("screenshot: barcode drawn one frame before Screenshot(), chat hidden, both restored", function()
  local ns = boot()
  ns.Emit("loot", { itemId = 1, quality = 4, count = 1, item = "X" })
  W.Frame() -- draws barcode
  H.eq(#W.screenshots, 0, "not in the same frame")
  H.ok(_G.NavtokDiscordBarcode:IsShown(), "barcode drawn")
  H.eq(ChatFrame1:GetAlpha(), 0, "chat hidden")
  W.Frame() -- screenshot
  H.eq(#W.screenshots, 1)
  H.ok(W.screenshots[1].barcodeShown, "barcode visible during Screenshot()")
  H.eq(W.screenshots[1].chatAlpha, 0, "chat hidden during Screenshot()")
  W.Frame() -- hide
  H.ok(not _G.NavtokDiscordBarcode:IsShown(), "barcode hidden on the next frame")
  H.eq(ChatFrame1:GetAlpha(), 1, "chat restored")
  H.eq(H.Events(ns)[1].shot, time(), "shot time recorded in SavedVariables")
end)

H.test("screenshot: chat stays visible when hideChat is off", function()
  local ns = boot()
  ns.settings.hideChat = false
  ns.Emit("loot", { itemId = 1 })
  W.Frame(); W.Frame()
  H.eq(W.screenshots[1].chatAlpha, 1)
end)

H.test("screenshot: rate limit 1 per 2 s, queue keeps order", function()
  local ns = boot()
  for i = 1, 3 do ns.Emit("skill", { skill = "S" .. i, rank = 75 }) end
  W.Advance(0.5)
  H.eq(#W.screenshots, 1)
  W.Advance(1.0)
  H.eq(#W.screenshots, 1, "still rate limited at 1.5 s")
  W.Advance(0.6)
  H.eq(#W.screenshots, 2)
  W.Advance(2.1)
  H.eq(#W.screenshots, 3)
  local gaps = { W.screenshots[2].at - W.screenshots[1].at, W.screenshots[3].at - W.screenshots[2].at }
  for _, g in ipairs(gaps) do H.ok(g >= 2 - 1e-6, "gap >= 2s: " .. g) end
end)

H.test("screenshot: delay honoured, other ready items go first", function()
  local ns = boot()
  ns.Emit("level", { level = 21 }, { delay = 0.5, priority = true })
  W.Advance(0.3)
  H.eq(#W.screenshots, 0, "level waits 0.5 s")
  W.Advance(0.4)
  H.eq(#W.screenshots, 1)
end)

H.test("screenshot: full queue drops non-priority, never priority events", function()
  local ns = boot()
  local S = ns.Screenshot
  for i = 1, S.MAX_QUEUE + 10 do ns.Emit("skill", { skill = "S" .. i, rank = 75 }) end
  ns.Emit("bg", { bg = "WSG", result = "win" }, { priority = true })
  ns.Emit("level", { level = 30 }, { priority = true })
  ns.Emit("dungeon", { encounter = "X" }, { priority = true })
  H.ok(S.QueueLength() <= S.MAX_QUEUE + 3)
  local pri = 0
  for _, item in ipairs(S.queue) do if item.priority then pri = pri + 1 end end
  H.eq(pri, 3, "all priority events kept")
  H.ok(S.dropped > 0)
  -- a queue full of priority events still accepts more priority events
  S.queue = {}
  for i = 1, S.MAX_QUEUE + 5 do S.Enqueue({ type = "bg", id = tostring(i) }, 0, true) end
  H.eq(S.QueueLength(), S.MAX_QUEUE + 5)
end)

H.test("screenshot: band mode (plan B) holds barcode, no Screenshot()", function()
  local ns = boot()
  ns.settings.mode = "band"
  ns.Emit("loot", { itemId = 1 })
  W.Frame()
  H.ok(_G.NavtokDiscordBarcode:IsShown())
  W.Advance(0.4)
  H.ok(_G.NavtokDiscordBarcode:IsShown(), "still visible at 0.4 s")
  W.Advance(0.3)
  H.ok(not _G.NavtokDiscordBarcode:IsShown(), "hidden after hold")
  H.eq(#W.screenshots, 0)
end)

H.test("screenshot: Screenshot() error does not break the queue", function()
  local ns = boot()
  W.screenshotError = "blocked"
  ns.Emit("loot", { itemId = 1 })
  ns.Emit("loot", { itemId = 2 })
  W.Advance(3)
  H.ok(not _G.NavtokDiscordBarcode:IsShown())
  H.eq(ns.Screenshot.QueueLength(), 0)
  H.eq(ChatFrame1:GetAlpha(), 1)
end)

H.test("screenshot: chat addon windows are hidden too (ScrollingMessageFrame, *chat* names, hideFrames)", function()
  local ns = boot()
  local smf = CreateFrame("ScrollingMessageFrame", nil, UIParent)       -- unnamed message frame
  local addon = CreateFrame("Frame", "ChattynatorMessageFrame1", UIParent) -- name contains "chat"
  local custom = CreateFrame("Frame", "MyWhisperBox", UIParent)          -- configured by name
  local other = CreateFrame("Frame", "PlayerFrameThing", UIParent)
  ns.settings.hideFrames = { "MyWhisperBox" }
  local seen = {}
  local orig = Screenshot
  Screenshot = function()
    seen = { smf = smf:GetAlpha(), addon = addon:GetAlpha(), custom = custom:GetAlpha(), other = other:GetAlpha() }
    orig()
  end
  ns.Emit("loot", { itemId = 1 })
  W.Frame(); W.Frame(); W.Frame()
  Screenshot = orig
  H.eq(seen.smf, 0, "message frame hidden")
  H.eq(seen.addon, 0, "chat addon frame hidden")
  H.eq(seen.custom, 0, "hideFrames entry hidden")
  H.eq(seen.other, 1, "unrelated frame untouched")
  H.eq(addon:GetAlpha(), 1, "restored afterwards")
end)
