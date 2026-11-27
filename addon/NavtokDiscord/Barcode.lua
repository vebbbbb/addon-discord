-- Barcode.lua: encodes an event into the NAVTOK v1 barcode and draws it pixel-perfect.
-- The format is specified in docs/barcode.md; companion/internal/barcode is the decoder.
-- Any change here must regenerate addon/tests/fixtures/barcode_v1.txt (luajit tests/gen_fixture.lua).
local _, ns = ...

local B = {}
ns.Barcode = B

B.VERSION = 1
B.ROWS = 13
B.COLS = 77
B.QUIET = 2              -- quiet zone (white) in modules on each side
B.MAX_PAYLOAD = 96
B.SEP = "\31"            -- ASCII unit separator between payload fields

B.TYPE_CODES = {
  loot = "L", skill = "S", level = "V", reputation = "R",
  death = "D", dungeon = "K", bg = "B", legacy = "G", rare = "E", equip = "Q", recipe = "P", quest = "U", unlock = "M",
}

-- Type specific payload fields, in order. Shared with the companion (internal/event/payload.go).
B.FIELDS = {
  loot       = { "itemId", "quality", "count", "item", "roll", "rollValue" },
  skill      = { "skill", "rank" },
  level      = { "zone" },
  reputation = { "faction", "standing" },
  death      = { "zone", "subzone", "killer", "pvp" },
  dungeon    = { "encounterId", "encounter", "instance", "bosses", "duration", "shotSeq" },
  bg         = { "bg", "result", "duration", "kb", "hk", "deaths", "honor" },
  legacy     = { "achievementId", "text", "group" },
  rare       = { "npcId", "classification", "mobLevel", "npc", "zone", "subzone" },
  equip      = { "itemId", "quality", "slot", "item" },
  recipe     = { "itemId", "quality", "item", "learned" },
  quest      = { "sub", "questId", "itemId", "quality", "stage", "item", "extra", "quest" },
  unlock     = { "sub", "rank", "skill" },
}

-- Free-text fields that may be shortened (first entry is shortened first) to fit MAX_PAYLOAD.
B.TRIM_ORDER = {
  loot = { "item" }, skill = { "skill" }, level = { "zone" }, reputation = { "faction" },
  death = { "subzone", "killer", "zone" }, dungeon = { "instance", "encounter" },
  bg = { "bg" }, legacy = { "group", "text" }, rare = { "subzone", "zone", "npc" },
  equip = { "item" }, recipe = { "learned", "item" }, quest = { "quest", "extra", "item" },
  unlock = { "skill" },
}

local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

-------------------------------------------------------------------------------
-- Pure encoding (no WoW API) - covered by tests/test_barcode.lua and the Go fixture test
-------------------------------------------------------------------------------

-- CRC16-CCITT (CCITT-FALSE): poly 0x1021, init 0xFFFF, no reflection, no final xor.
function B.CRC16(bytes, n)
  local crc = 0xFFFF
  for i = 1, n or #bytes do
    crc = bxor(crc, lshift(bytes[i], 8))
    for _ = 1, 8 do
      if band(crc, 0x8000) ~= 0 then
        crc = band(bxor(lshift(crc, 1), 0x1021), 0xFFFF)
      else
        crc = band(lshift(crc, 1), 0xFFFF)
      end
    end
  end
  return crc
end

-- Cuts s to at most n bytes without splitting a UTF-8 sequence.
function B.Utf8Truncate(s, n)
  if #s <= n then return s end
  if n <= 0 then return "" end
  local cut = s:sub(1, n)
  local i = #cut
  while i > 0 do
    local b = cut:byte(i)
    if b < 0x80 then break end
    if b >= 0xC0 then
      local need = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or 2
      if #cut - i + 1 < need then cut = cut:sub(1, i - 1) end
      break
    end
    i = i - 1
  end
  return cut
end

local function clean(v)
  if v == nil then return "" end
  if type(v) == "boolean" then return v and "1" or "0" end
  local s = ns.StripCodes and ns.StripCodes(tostring(v)) or tostring(v)
  return (s:gsub("[%z\1-\31]", " "))
end

-- Builds the payload string for an event (see docs/barcode.md "Payload v1").
function B.EncodePayload(ev)
  local code = B.TYPE_CODES[ev.type]
  if not code then error("unknown event type " .. tostring(ev.type)) end
  local header = {
    code, (ev.test and "T" or "") .. (ev.candidate and "C" or ""), tostring(ev.ts or 0), tostring(ev.seq or 0),
    clean(ev.char), tostring(ev.classId or 0), tostring(ev.level or 0),
  }
  local names = B.FIELDS[ev.type]
  local values = {}
  local data = ev.data or {}
  for i, name in ipairs(names) do values[i] = clean(data[name]) end

  local function build()
    local all = {}
    for i = 1, #header do all[#all + 1] = header[i] end
    for i = 1, #values do all[#all + 1] = values[i] end
    return table.concat(all, B.SEP)
  end

  local s = build()
  if #s <= B.MAX_PAYLOAD then return s end
  local index = {}
  for i, name in ipairs(names) do index[name] = i end
  for _, name in ipairs(B.TRIM_ORDER[ev.type] or {}) do
    local over = #s - B.MAX_PAYLOAD
    local i = index[name]
    values[i] = B.Utf8Truncate(values[i], #values[i] - over)
    s = build()
    if #s <= B.MAX_PAYLOAD then return s end
  end
  header[5] = B.Utf8Truncate(header[5], #header[5] - (#s - B.MAX_PAYLOAD))
  s = build()
  return B.Utf8Truncate(s, B.MAX_PAYLOAD)
end

-- Frame: "N" "V" version length payload... crcHi crcLo  -> array of bytes
function B.BuildFrame(payload)
  if #payload > B.MAX_PAYLOAD then error("payload too long") end
  local bytes = { 0x4E, 0x56, B.VERSION, #payload }
  for i = 1, #payload do bytes[#bytes + 1] = payload:byte(i) end
  local crc = B.CRC16(bytes)
  bytes[#bytes + 1] = rshift(crc, 8)
  bytes[#bytes + 1] = band(crc, 0xFF)
  return bytes
end

-- Returns grid (flat array, index r*COLS + c + 1, value 1 = black) for the frame bytes.
function B.BuildGrid(frame)
  local R, C = B.ROWS, B.COLS
  local grid = {}
  -- finder (left column + bottom row solid) and clocks (top row, right column)
  for r = 0, R - 1 do
    for c = 0, C - 1 do
      local v = 0
      if c == 0 or r == R - 1 then
        v = 1
      elseif r == 0 then
        v = (c % 2 == 0) and 1 or 0
      elseif c == C - 1 then
        v = ((R - 1 - r) % 2 == 0) and 1 or 0
      end
      grid[r * C + c + 1] = v
    end
  end
  -- data bits, row-major, MSB first; padded with 0xEC 0x11 ... then zero bits
  local capacityBits = (R - 2) * (C - 2)
  local capacityBytes = math.floor(capacityBits / 8)
  local stream = {}
  for i = 1, #frame do stream[i] = frame[i] end
  local pad = { 0xEC, 0x11 }
  local p = 1
  while #stream < capacityBytes do
    stream[#stream + 1] = pad[p]
    p = 3 - p
  end
  local bitIndex = 0
  for r = 1, R - 2 do
    for c = 1, C - 2 do
      local byteI = math.floor(bitIndex / 8) + 1
      local v = 0
      local byte = stream[byteI]
      if byte then
        v = band(rshift(byte, 7 - (bitIndex % 8)), 1)
      end
      grid[r * C + c + 1] = v
      bitIndex = bitIndex + 1
    end
  end
  return grid
end

function B.GridForEvent(ev)
  return B.BuildGrid(B.BuildFrame(B.EncodePayload(ev)))
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
-- Physical screen height in pixels (pixel-perfect sizing; see VERIFY.md item 8).
function B.PhysicalHeight()
  if GetPhysicalScreenSize then
    local _, h = GetPhysicalScreenSize()
    if h and h > 0 then return h, "GetPhysicalScreenSize" end
  end
  if GetCVar then
    for _, cvar in ipairs({ "gxFullscreenResolution", "gxWindowedResolution", "gxResolution" }) do
      local v = GetCVar(cvar)
      local h = v and tonumber(v:match("%d+x(%d+)"))
      if h and h > 0 then return h, cvar end
    end
  end
  return 1080, "fallback"
end

local frame, bg, modules

local function ensureFrame()
  if frame then return end
  -- No parent: stays visible when the UI is hidden with Alt+Z and ignores the UI scale.
  frame = CreateFrame("Frame", "NavtokDiscordBarcode", nil)
  frame:SetFrameStrata("TOOLTIP")
  if frame.SetFrameLevel then frame:SetFrameLevel(9000) end
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(1, 1, 1, 1)
  bg:SetAllPoints(frame)
  modules = {}
  frame:Hide()
end

local function pixelSnap(tex)
  if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
  if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
end

-- Draws the grid in the configured corner. Sizes are in physical pixels: with no parent the
-- frame's effective scale is its own scale, and scale = 768 / physicalHeight makes 1 unit = 1 px.
function B.Show(grid)
  ensureFrame()
  local s = ns.settings or ns.DEFAULTS
  local px = math.max(2, math.floor(tonumber(s.blockSize) or 8))
  local physH = B.PhysicalHeight()
  frame:SetScale(768 / physH)
  local R, C, Q = B.ROWS, B.COLS, B.QUIET
  frame:SetSize((C + 2 * Q) * px, (R + 2 * Q) * px)
  frame:ClearAllPoints()
  local corner = s.position or "TOPRIGHT"
  frame:SetPoint(corner, WorldFrame or UIParent, corner, 0, 0)
  pixelSnap(bg)
  for r = 0, R - 1 do
    for c = 0, C - 1 do
      local i = r * C + c + 1
      local tex = modules[i]
      if grid[i] == 1 then
        if not tex then
          tex = frame:CreateTexture(nil, "ARTWORK")
          tex:SetColorTexture(0, 0, 0, 1)
          pixelSnap(tex)
          modules[i] = tex
        end
        tex:ClearAllPoints()
        tex:SetSize(px, px)
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", (Q + c) * px, -(Q + r) * px)
        tex:Show()
      elseif tex then
        tex:Hide()
      end
    end
  end
  frame:Show()
  B.shown = true
end

function B.Hide()
  if frame then frame:Hide() end
  B.shown = false
end

function B.IsShown()
  return frame ~= nil and frame:IsShown()
end
