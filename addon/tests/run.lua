-- run.lua: offline test runner.  Usage: luajit addon/tests/run.lua [filter]
local dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
dofile(dir .. "/harness.lua")

local files = {
  "test_json.lua", "test_barcode.lua", "test_screenshot.lua", "test_core.lua",
  "test_loot.lua", "test_skill.lua", "test_level.lua", "test_reputation.lua",
  "test_death.lua", "test_dungeon.lua", "test_bg.lua", "test_legacy.lua",
  "test_commands.lua", "test_probe.lua",
}
for _, f in ipairs(files) do dofile(dir .. "/" .. f) end

local ok = H.run(arg[1])
os.exit(ok and 0 or 1)
