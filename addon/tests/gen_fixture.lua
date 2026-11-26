-- gen_fixture.lua: regenerates fixtures/barcode_v1.txt.  Usage: luajit addon/tests/gen_fixture.lua
local dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
dofile(dir .. "/harness.lua")
dofile(dir .. "/fixture_common.lua")
local ns = H.Boot()
local path = dir .. "/fixtures/barcode_v1.txt"
local f = assert(io.open(path, "wb"))
f:write(FixtureText(ns))
f:close()
print("wrote " .. path)
