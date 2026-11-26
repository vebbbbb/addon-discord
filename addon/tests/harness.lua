-- harness.lua: loads the addon into the stub world and provides tiny assert helpers.
local H = {}
_G.H = H

H.dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
H.addonDir = H.dir .. "/../NavtokDiscord"

dofile(H.dir .. "/wowstubs.lua")

function H.TocFiles()
  local files = {}
  for line in io.lines(H.addonDir .. "/NavtokDiscord.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^##") then
      files[#files + 1] = (line:gsub("\\", "/"))
    end
  end
  return files
end

-- Fresh world + fresh addon instance. opts.db pre-seeds NavtokDiscordDB (simulates SavedVariables).
function H.Boot(opts)
  opts = opts or {}
  W.Reset()
  if opts.setup then opts.setup(W) end
  NavtokDiscordDB = opts.db
  local ns = {}
  for _, f in ipairs(H.TocFiles()) do
    local chunk, err = loadfile(H.addonDir .. "/" .. f)
    if not chunk then error(err) end
    chunk("NavtokDiscord", ns)
  end
  W.Fire("ADDON_LOADED", "NavtokDiscord")
  W.Fire("PLAYER_LOGIN")
  W.Fire("PLAYER_ENTERING_WORLD", true, false)
  W.Advance(5) -- past the login grace period
  H.ns = ns
  return ns
end

-- Decodes the JSON lines of the ring buffer just enough for assertions (type/id/test fields).
function H.Events(ns)
  local out = {}
  for _, line in ipairs(ns.char.events) do
    out[#out + 1] = {
      raw = line,
      type = line:match('"type":"(.-)"'),
      id = line:match('"id":"(.-)"'),
      test = line:match('"test":(%a+)') == "true",
      shot = tonumber(line:match('"shot":(%d+)')),
    }
  end
  return out
end

function H.EventsOfType(ns, t)
  local out = {}
  for _, e in ipairs(H.Events(ns)) do if e.type == t then out[#out + 1] = e end end
  return out
end

-------------------------------------------------------------------------------
H.tests = {}
H.failures = 0
H.count = 0

function H.test(name, fn) H.tests[#H.tests + 1] = { name = name, fn = fn } end

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function H.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "values differ") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
  end
end

function H.ok(v, msg)
  if not v then error(msg or "expected truthy value", 2) end
end

function H.contains(s, needle, msg)
  if type(s) ~= "string" or not s:find(needle, 1, true) then
    error((msg or "missing substring") .. ": " .. fmt(needle) .. " not in " .. fmt(s), 2)
  end
end

function H.run(filter)
  for _, t in ipairs(H.tests) do
    if not filter or t.name:find(filter, 1, true) then
      H.count = H.count + 1
      local ok, err = xpcall(t.fn, debug.traceback)
      if ok then
        io.write("ok   ", t.name, "\n")
      else
        H.failures = H.failures + 1
        io.write("FAIL ", t.name, "\n     ", tostring(err):gsub("\n", "\n     "), "\n")
      end
    end
  end
  io.write(string.format("\n%d tests, %d failures\n", H.count, H.failures))
  return H.failures == 0
end

return H
