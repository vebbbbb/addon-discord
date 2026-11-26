-- Screenshot.lua: queue + rate limit + the "barcode, wait a frame, Screenshot(), hide" sequence.
--
-- Sequence per event (plan A, mode "screenshot"):
--   frame N   : hide chat (alpha 0), draw barcode
--   frame N+1 : Screenshot()
--   frame N+1+holdFrames : hide barcode, restore chat
-- Plan B (mode "band"): no Screenshot(); barcode stays visible bandHoldSeconds so the companion
-- can read it from the live window.
local _, ns = ...

local S = {}
ns.Screenshot = S

S.MAX_QUEUE = 25
S.queue = {}
S.state = "idle"     -- idle | drawn | shot | band
S.lastShot = nil     -- GetTime() of the last capture
S.shots = 0
S.dropped = 0

local chatSaved = {}

local CHAT_EXTRA = {
  "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
  "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton",
}

-- Chat addons (Chattynator, ElvUI, Glass, ...) draw their own windows. Besides the standard
-- ChatFrameN frames we hide every ScrollingMessageFrame and every frame whose name contains
-- "chat", plus names listed in settings.hideFrames. The frame scan is cached for a minute.
local scanned, scannedAt = {}, -1000

local function scanChatLike()
  if not EnumerateFrames then return {} end
  if GetTime() - scannedAt < 60 then return scanned end
  scanned, scannedAt = {}, GetTime()
  local f = EnumerateFrames()
  local guard = 0
  while f and guard < 50000 do
    guard = guard + 1
    local ok, otype = pcall(f.GetObjectType, f)
    local name = f.GetName and f:GetName()
    local chatName = type(name) == "string" and name:lower():find("chat", 1, true)
    if (ok and otype == "ScrollingMessageFrame") or chatName then
      if name ~= "NavtokDiscordBarcode" then scanned[#scanned + 1] = f end
    end
    f = EnumerateFrames(f)
  end
  return scanned
end

local function chatFrames()
  local list = {}
  for _, f in ipairs(scanChatLike()) do list[#list + 1] = f end
  for _, name in ipairs((ns.settings or ns.DEFAULTS).hideFrames or {}) do
    if _G[name] then list[#list + 1] = _G[name] end
  end
  local n = NUM_CHAT_WINDOWS or 10
  for i = 1, n do
    for _, suffix in ipairs({ "", "Tab", "EditBox", "ButtonFrame" }) do
      local f = _G["ChatFrame" .. i .. suffix]
      if f then list[#list + 1] = f end
    end
  end
  for _, name in ipairs(CHAT_EXTRA) do
    if _G[name] then list[#list + 1] = _G[name] end
  end
  return list
end

-- SetAlpha is not a protected call, so this also works in combat (VERIFY.md item 9).
function S.HideChat()
  for _, f in ipairs(chatFrames()) do
    if f.GetAlpha and f.SetAlpha and chatSaved[f] == nil then
      chatSaved[f] = f:GetAlpha()
      f:SetAlpha(0)
    end
  end
end

function S.RestoreChat()
  for f, a in pairs(chatSaved) do
    f:SetAlpha(a)
  end
  chatSaved = {}
end

local function settings() return ns.settings or ns.DEFAULTS end

function S.Enqueue(ev, delay, priority)
  if #S.queue >= S.MAX_QUEUE and not priority then
    -- queue full: drop the oldest non-priority entry; priority events are never dropped
    local dropped = false
    for i, item in ipairs(S.queue) do
      if not item.priority then
        table.remove(S.queue, i)
        dropped = true
        break
      end
    end
    if not dropped then
      S.dropped = S.dropped + 1
      ns.Debug("screenshot queue full, dropping " .. ev.type)
      return false
    end
    S.dropped = S.dropped + 1
  end
  S.queue[#S.queue + 1] = { ev = ev, notBefore = GetTime() + (delay or 0), priority = priority and true or false }
  return true
end

function S.QueueLength() return #S.queue end

local current, frameCount, holdUntil

local function finish()
  ns.Barcode.Hide()
  S.RestoreChat()
  S.state = "idle"
  current = nil
end

local function startCapture(item)
  current = item
  local ev = item.ev
  local ok, err = pcall(function()
    if settings().hideChat then S.HideChat() end
    ns.Barcode.Show(ns.Barcode.GridForEvent(ev))
  end)
  if not ok then
    ns.Debug("barcode failed: " .. tostring(err))
    finish()
    return
  end
  S.lastShot = GetTime()
  frameCount = 0
  if settings().mode == "band" then
    S.state = "band"
    holdUntil = GetTime() + (tonumber(settings().bandHoldSeconds) or 0.6)
    ns.MarkShot(ev, time())
  else
    S.state = "drawn"
  end
end

local function pickReady(now)
  for i, item in ipairs(S.queue) do
    if now >= item.notBefore then
      table.remove(S.queue, i)
      return item
    end
  end
end

function S.OnUpdate()
  local now = GetTime()
  if S.state == "drawn" then
    -- one frame later the barcode has been rendered: take the screenshot
    local ok, err = pcall(Screenshot)
    if not ok then ns.Debug("Screenshot() failed: " .. tostring(err)) end
    S.shots = S.shots + 1
    if current then ns.MarkShot(current.ev, time()) end
    S.state = "shot"
    frameCount = 0
    return
  elseif S.state == "shot" then
    frameCount = frameCount + 1
    if frameCount >= (tonumber(settings().holdFrames) or 1) then finish() end
    return
  elseif S.state == "band" then
    if now >= holdUntil then finish() end
    return
  end
  if #S.queue == 0 then return end
  local minInterval = tonumber(settings().minInterval) or 2
  if S.lastShot and now - S.lastShot < minInterval then return end
  local item = pickReady(now)
  if item then startCapture(item) end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function() S.OnUpdate() end)
S.driver = driver
