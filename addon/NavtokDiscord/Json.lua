-- Json.lua: tiny, dependency-free JSON encoder (Lua 5.1).
-- Objects get sorted keys so output is deterministic (the companion and the tests rely on it).
local _, ns = ...

local Json = {}
ns.Json = Json

local escapes = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escapeString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k <= 0 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true, n
end

local encodeValue

local function encodeTable(t, depth)
  if depth > 16 then error("json: nesting too deep") end
  local arr, n = isArray(t)
  local out = {}
  if arr and n > 0 then
    for i = 1, n do out[i] = encodeValue(t[i], depth + 1) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for i, k in ipairs(keys) do
    local v = t[k]
    if v == nil then v = t[tonumber(k)] end
    out[i] = escapeString(k) .. ":" .. encodeValue(v, depth + 1)
  end
  return "{" .. table.concat(out, ",") .. "}"
end

encodeValue = function(v, depth)
  local tv = type(v)
  if tv == "string" then
    return escapeString(v)
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v % 1 == 0 and v > -1e15 and v < 1e15 then
      return string.format("%d", v)
    end
    return string.format("%.14g", v)
  elseif tv == "boolean" then
    return v and "true" or "false"
  elseif tv == "table" then
    return encodeTable(v, depth)
  end
  return "null"
end

function Json.Encode(v)
  return encodeValue(v, 0)
end
