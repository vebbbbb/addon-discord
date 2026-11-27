-- Group.lua: lets the NAVTOK addons of a group agree on who posts, so a boss/rare/battleground/
-- world-PvP fight shared by 5 guild members gives ONE Discord post, not five.
--
-- Hidden addon messages (prefix "NAVTOK", PARTY/RAID/BATTLEGROUND channel):
--   C <key>         "I saw <key> and would post it" - a claim. After CLAIM_WINDOW seconds every
--                   claimant picks the alphabetically first claimant name; only that one posts.
--   D <key>         "<key> was posted" - e.g. a dungeon summary answered with Yes.
--   H <victim>      world PvP: I got an honorable kill on <victim>.
-- Outside a group everything posts immediately. Deaths and personal events never go through here.
local _, ns = ...

local G = {}
ns.Group = G

G.PREFIX = "NAVTOK"
G.CLAIM_WINDOW = 1.5
G.pending = {}   -- key -> { fn, claimants = {name=true} }
G.early = {}     -- key -> { name -> GetTime() } claims heard before we saw the event ourselves
G.done = {}      -- key -> GetTime() keys someone already posted
G.DONE_TTL = 600 -- a posted key blocks repeats this long (a second clear later still posts)

function G.IsDone(key, ttl)
  local at = G.done[key]
  return at ~= nil and GetTime() - at < (ttl or G.DONE_TTL)
end
G.listeners = {} -- message kind -> list of fn(sender, payload)

local function short(name)
  if not name then return nil end
  if Ambiguate then
    local ok, n = pcall(Ambiguate, name, "none")
    if ok and n then name = n end
  end
  return (name:gsub("%-.*$", ""))
end

local function me() return short(ns.playerName or UnitName("player")) end

function G.InGroup()
  if IsInGroup then return IsInGroup() and true or false end
  return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 1
end

local function channel()
  if IsInInstance then
    local _, itype = IsInInstance()
    if itype == "pvp" or itype == "arena" then return "BATTLEGROUND" end
  end
  if IsInRaid and IsInRaid() then return "RAID" end
  return "PARTY"
end

function G.Send(kind, payload)
  if not G.InGroup() then return end
  local msg = kind .. "\t" .. (payload or "")
  local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if not send then return end
  local ch = channel()
  local ok = pcall(send, G.PREFIX, msg, ch)
  if not ok and ch == "BATTLEGROUND" then pcall(send, G.PREFIX, msg, "INSTANCE_CHAT") end
end

-- Names of the group (party members, or "raid of N" for big groups), the player first.
function G.Members()
  local names = { me() }
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  if n > 5 then return names, n end
  for i = 1, 4 do
    local nm = UnitExists and UnitExists("party" .. i) and UnitName("party" .. i)
    if nm then names[#names + 1] = short(nm) end
  end
  return names, n
end

-- Own party only ("Veb, Kjell") - used in battlegrounds, where the raid is the whole team.
function G.PartyText()
  local names = { me() }
  for i = 1, 4 do
    local nm = UnitExists and UnitExists("party" .. i) and UnitName("party" .. i)
    if nm then names[#names + 1] = short(nm) end
  end
  if #names < 2 then return nil end
  return table.concat(names, ", ")
end

-- "Veb, Kjell, Rune" (party) or "raid of 20"
function G.MembersText()
  if not G.InGroup() then return nil end
  local names, n = G.Members()
  if n > 5 then return "raid of " .. n end
  return table.concat(names, ", ")
end

-- Runs fn() on exactly one of the group's NAVTOK addons that saw `key` (alphabetically first
-- name). Solo: right away.
function G.Share(key, fn)
  if G.IsDone(key) then return end
  if not G.InGroup() then
    fn()
    return
  end
  if G.pending[key] then return end
  local p = { fn = fn, claimants = { [me()] = true } }
  for name, at in pairs(G.early[key] or {}) do
    if GetTime() - at <= G.CLAIM_WINDOW * 2 then p.claimants[name] = true end
  end
  G.early[key] = nil
  G.pending[key] = p
  G.Send("C", key)
  ns.After(G.CLAIM_WINDOW, function() G.Resolve(key) end)
end

function G.Resolve(key)
  local p = G.pending[key]
  G.pending[key] = nil
  if not p or G.IsDone(key) then return end
  local first
  for name in pairs(p.claimants) do
    if not first or name < first then first = name end
  end
  if first == me() then
    G.done[key] = GetTime()
    p.fn()
  end
end

-- Tells the group that `key` was posted (they skip it from now on).
function G.Done(key)
  G.done[key] = GetTime()
  G.Send("D", key)
end

function G.On(kind, fn)
  G.listeners[kind] = G.listeners[kind] or {}
  table.insert(G.listeners[kind], fn)
end

function G.OnMessage(prefix, msg, _, sender)
  if prefix ~= G.PREFIX or type(msg) ~= "string" then return end
  sender = short(sender)
  if not sender or sender == me() then return end
  local kind, payload = msg:match("^(%a)\t(.*)$")
  if not kind then return end
  if kind == "C" then
    local p = G.pending[payload]
    if p then
      p.claimants[sender] = true
    else
      G.early[payload] = G.early[payload] or {}
      G.early[payload][sender] = GetTime()
    end
  elseif kind == "D" then
    G.done[payload] = GetTime()
    G.pending[payload] = nil
  end
  for _, fn in ipairs(G.listeners[kind] or {}) do pcall(fn, sender, payload) end
end

function G.Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, G.PREFIX)
  elseif RegisterAddonMessagePrefix then
    pcall(RegisterAddonMessagePrefix, G.PREFIX)
  end
  ns.On("CHAT_MSG_ADDON", function(_, ...) G.OnMessage(...) end)
end

ns.On("PLAYER_LOGIN", function() G.Init() end)
