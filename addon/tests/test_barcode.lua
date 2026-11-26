dofile(H.dir .. "/fixture_common.lua")

H.test("barcode: crc16-ccitt-false check value", function()
  local ns = H.Boot()
  local bytes = {}
  for i = 1, 9 do bytes[i] = ("123456789"):byte(i) end
  H.eq(ns.Barcode.CRC16(bytes), 0x29B1)
end)

H.test("barcode: frame layout", function()
  local ns = H.Boot()
  local f = ns.Barcode.BuildFrame("hi")
  H.eq(#f, 8)
  H.eq(f[1], 0x4E); H.eq(f[2], 0x56); H.eq(f[3], 1); H.eq(f[4], 2)
  H.eq(f[5], ("h"):byte()); H.eq(f[6], ("i"):byte())
end)

H.test("barcode: finder and clock tracks", function()
  local ns = H.Boot()
  local B = ns.Barcode
  local g = B.BuildGrid(B.BuildFrame("x"))
  local R, C = B.ROWS, B.COLS
  for r = 0, R - 1 do H.eq(g[r * C + 1], 1, "left column solid") end
  for c = 0, C - 1 do H.eq(g[(R - 1) * C + c + 1], 1, "bottom row solid") end
  for c = 0, C - 1 do H.eq(g[c + 1], (c % 2 == 0) and 1 or 0, "top clock") end
  for r = 0, R - 1 do H.eq(g[r * C + C], ((R - 1 - r) % 2 == 0) and 1 or 0, "right clock") end
  H.ok((R - 2) * (C - 2) >= (B.MAX_PAYLOAD + 6) * 8, "capacity fits max frame")
end)

H.test("barcode: payload fields and truncation to 96 bytes (utf-8 safe)", function()
  local ns = H.Boot()
  local B = ns.Barcode
  local p = B.EncodePayload({ type = "skill", ts = 5, seq = 1, char = "A", classId = 1, level = 2,
    data = { skill = "Mining", rank = 75 } })
  H.eq(p, "S\31\31" .. "5\0311\031A\0311\0312\031Mining\03175")
  local long = string.rep("é", 80)
  local p2 = B.EncodePayload({ type = "death", test = true, ts = 1764160000, seq = 12345, char = "Ünïcödé", classId = 4,
    level = 60, data = { zone = long, subzone = long, killer = long } })
  H.ok(#p2 <= 96, "fits: " .. #p2)
  H.ok(p2:sub(2, 3) == "\31T", "test flag")
  -- valid utf-8: no dangling lead bytes at the end of any field
  for field in (p2 .. "\31"):gmatch("(.-)\31") do
    local last = field:byte(#field)
    H.ok(not last or last < 0xC0, "no cut lead byte")
  end
end)

H.test("barcode: utf8 truncate", function()
  local ns = H.Boot()
  local T = ns.Barcode.Utf8Truncate
  H.eq(T("abc", 5), "abc")
  H.eq(T("aé", 2), "a")
  H.eq(T("aé", 3), "aé")
  H.eq(T("a€b", 3), "a")
  H.eq(T("abc", 0), "")
end)

H.test("barcode: fixture matches the current encoder (regenerate with gen_fixture.lua)", function()
  local ns = H.Boot()
  local f = assert(io.open(H.dir .. "/fixtures/barcode_v1.txt", "rb"))
  local onDisk = f:read("*a")
  f:close()
  H.eq(onDisk, FixtureText(ns), "fixture out of date")
end)

H.test("barcode: pixel-perfect drawing uses physical height", function()
  local ns = H.Boot()
  W.screenSize = { 2560, 1440 }
  ns.Barcode.Show(ns.Barcode.GridForEvent(FIXTURE_EVENT))
  local f = _G.NavtokDiscordBarcode
  H.ok(math.abs(f.scale - 768 / 1440) < 1e-9, "scale = 768/physH")
  H.eq(f.w, (77 + 4) * 8)
  H.eq(f.h, (13 + 4) * 8)
  H.eq(f.points[1][1], "TOPRIGHT")
  H.eq(f.parent, nil, "no parent: survives Alt+Z")
  ns.Barcode.Hide()
  H.ok(not f:IsShown())
end)
