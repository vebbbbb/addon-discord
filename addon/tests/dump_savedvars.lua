-- dump_savedvars.lua: emits a SavedVariables file (WoW style) after a `/navtok test <type>` for
-- every type. Used by the Go savedvars test to check the real addon output parses.
local dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
dofile(dir .. "/harness.lua")
local ns = H.Boot()
for _, t in ipairs(ns.notifierOrder) do SlashCmdList["NAVTOK"]("test " .. t) end
W.Advance(20)

local function quote(s)
  return '"' .. s:gsub('[\\"\n\r]', { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r" }) .. '"'
end

local function ser(v, indent)
  local t = type(v)
  if t == "string" then return quote(v) end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t ~= "table" then return "nil" end
  local out = { "{\n" }
  local n = #v
  for i = 1, n do out[#out + 1] = indent .. "\t" .. ser(v[i], indent .. "\t") .. ", -- [" .. i .. "]\n" end
  local keys = {}
  for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local ks = type(k) == "string" and quote(k) or tostring(k)
    out[#out + 1] = indent .. "\t[" .. ks .. "] = " .. ser(v[k], indent .. "\t") .. ",\n"
  end
  out[#out + 1] = indent .. "}"
  return table.concat(out)
end

io.write("\nNavtokDiscordDB = " .. ser(NavtokDiscordDB, "") .. "\n")
