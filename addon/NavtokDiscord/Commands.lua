-- Commands.lua: /navtok slash commands.
local _, ns = ...

local C = {}
ns.Commands = C

local CORNERS = {
  tl = "TOPLEFT", tr = "TOPRIGHT", bl = "BOTTOMLEFT", br = "BOTTOMRIGHT",
  topleft = "TOPLEFT", topright = "TOPRIGHT", bottomleft = "BOTTOMLEFT", bottomright = "BOTTOMRIGHT",
}

-- events that must never be dropped and their screenshot delay (also used for tests)
local TEST_OPTS = {
  level = { delay = 0.5, priority = true },
  dungeon = { delay = 0.5, priority = true },
  bg = { delay = 1, priority = true },
}

local function onoff(v) return v and "|cff00ff00on|r" or "|cffff0000off|r" end

function C.Status()
  local s = ns.settings
  ns.Print(("v%s - mode %s, corner %s, hide chat %s, debug %s"):format(
    ns.VERSION, s.mode, s.position, onoff(s.hideChat), onoff(s.debug)))
  local events = ns.char and #ns.char.events or 0
  ns.Print(("%d events logged for %s, queue %d, screenshots this session %d, probe %s"):format(
    events, ns.charKey or "?", ns.Screenshot.QueueLength(), ns.Screenshot.shots, onoff(ns.Probe.enabled)))
  if ns.lastEvent then
    ns.Print(("last event: %s at %s"):format(ns.lastEvent.type, date and date("%H:%M:%S", ns.lastEvent.ts) or ns.lastEvent.ts))
  end
  for _, line in ipairs(ns.Options.Summary()) do ns.Print(line) end
  ns.Print("commands: settings | on|off <type> | set <name> <value> | test <type> | position <tl|tr|bl|br> | chat on|off | done | debug | probe")
end

function C.Test(etype)
  local n = ns.notifiers[etype or ""]
  if not n then
    ns.Print("test types: " .. table.concat(ns.notifierOrder, ", "))
    return
  end
  local data = n.Test and n:Test()
  if data then
    local o = TEST_OPTS[etype] or {}
    ns.Emit(etype, data, { delay = o.delay, priority = o.priority, test = true })
  end
  ns.Print("test " .. etype .. " event queued")
end

local function boolArg(arg, current)
  if arg == "on" then return true elseif arg == "off" then return false end
  return not current
end

function C.Handle(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  local s = ns.settings
  if cmd == "" or cmd == "status" then
    C.Status()
  elseif cmd == "test" then
    C.Test(rest)
  elseif cmd == "position" or cmd == "pos" then
    local corner = CORNERS[rest]
    if not corner then ns.Print("usage: /navtok position tl|tr|bl|br") return end
    s.position = corner
    ns.Print("barcode corner: " .. corner)
  elseif cmd == "chat" then
    s.hideChat = boolArg(rest, s.hideChat)
    ns.Print("hide chat before screenshots: " .. onoff(s.hideChat))
  elseif cmd == "mode" then
    if rest ~= "screenshot" and rest ~= "band" then ns.Print("usage: /navtok mode screenshot|band") return end
    s.mode = rest
    ns.Print("mode: " .. rest .. (rest == "band" and " (set plan_b_band_capture=true in the companion config)" or ""))
  elseif cmd == "settings" or cmd == "options" or cmd == "config" then
    ns.Options.Open()
  elseif cmd == "on" or cmd == "off" then
    if rest == "death" then ns.Print("deaths are always posted") return end
    if not ns.Options.SetEnabled(rest, cmd == "on") then
      local names = {}
      for _, k in ipairs(ns.Options.KINDS) do names[#names + 1] = k[1] end
      ns.Print("usage: /navtok " .. cmd .. " <" .. table.concat(names, "|") .. ">")
      return
    end
    ns.Print(rest .. " posts " .. (cmd == "on" and "|cff00ff00on|r" or "|cffff0000off|r"))
  elseif cmd == "set" then
    local name, value = rest:match("^(%S+)%s*(.-)$")
    ns.Print(ns.Options.Set(name, value))
  elseif cmd == "done" then
    ns.notifiers.dungeon:Done()
  elseif cmd == "debug" then
    s.debug = boolArg(rest, s.debug)
    ns.Print("debug: " .. onoff(s.debug))
  elseif cmd == "probe" then
    if rest == "shot" then
      ns.Probe.ShotTest()
    elseif rest == "clear" then
      ns.db.probe = {}
      ns.Print("probe buffer cleared")
    else
      ns.Probe.SetEnabled(boolArg(rest, ns.Probe.enabled))
    end
  else
    ns.Print("unknown command '" .. cmd .. "'")
    C.Status()
  end
end

SLASH_NAVTOK1 = "/navtok"
SlashCmdList = SlashCmdList or {}
SlashCmdList["NAVTOK"] = C.Handle
