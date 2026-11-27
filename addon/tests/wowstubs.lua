-- wowstubs.lua: minimal WoW API emulation for offline tests (luajit).
-- Everything lives in the global `W` (the fake world) so tests can drive it.
local W = {}
_G.W = W

local function noop() end

function W.Reset()
  W.now = 1000.0                  -- GetTime()
  W.epoch = 1764160000            -- time() at GetTime() == 1000
  W.frames = {}
  W.timers = {}
  W.chat = {}
  W.screenshots = {}              -- { at, time, barcodeShown, chatAlpha }
  W.player = { name = "Testchar", realm = "Testrealm", class = "Warrior", classFile = "WARRIOR", classId = 1,
    level = 20, faction = "Alliance" }
  W.zone, W.subzone = "Elwynn Forest", "Goldshire"
  W.target = nil                  -- { name, hostile, guid, classification, level, dead, tapDenied }
  W.units = {}                    -- other unit tokens (mouseover, nameplate1...) -> same shape
  W.achievements = {}             -- id -> localized name
  W.achievementCategory = {}      -- id -> category id
  W.categories = {}               -- category id -> { title, parent }
  W.instance = nil                -- { name, type ("party"/"raid"), mapId }
  W.popups = {}                   -- StaticPopup_Show calls: { which, arg1, data }
  W.quest = nil                   -- { id, title, rewards = {links}, choices = {links}, spell, tagID, tagName }
  W.skills = {}                   -- list of { name, rank, header }
  W.talentGroups = 1
  StaticPopupDialogs = {}
  W.items = {}                    -- link or id -> { name, quality } ; missing = uncached
  W.factions = {}                 -- list of { name, standingID, isHeader, hasRep, factionID }
  W.bg = { winner = nil, status = {}, scores = {}, runtime = 0, instance = { false, "none" } }
  W.screenSize = { 1920, 1080 }
  W.unknownEvents = { NOT_A_REAL_EVENT = true, LEGACY_POINTS_UPDATED = true, LEGACY_CHALLENGE_COMPLETED = true,
    CHALLENGE_COMPLETED = true, CRITERIA_EARNED = true }
  W.screenshotError = nil

  NavtokDiscordDB = nil
  SlashCmdList = {}
  SLASH_NAVTOK1 = nil

  -- chat frames
  NUM_CHAT_WINDOWS = 3
  for i = 1, 3 do
    _G["ChatFrame" .. i] = W.NewFrame("Frame", "ChatFrame" .. i)
    _G["ChatFrame" .. i .. "Tab"] = W.NewFrame("Frame", "ChatFrame" .. i .. "Tab")
    _G["ChatFrame" .. i .. "EditBox"] = W.NewFrame("Frame", "ChatFrame" .. i .. "EditBox")
  end
  GeneralDockManager = W.NewFrame("Frame", "GeneralDockManager")
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) W.chat[#W.chat + 1] = msg end }
  UIParent = W.NewFrame("Frame", "UIParent")
  WorldFrame = W.NewFrame("Frame", "WorldFrame")
end

-------------------------------------------------------------------------------
-- Frames and textures
-------------------------------------------------------------------------------
local FrameMT = {}
-- unknown widget methods (UI templates: SetText, SetChecked, EnableMouse, ...) are no-ops
FrameMT.__index = function(_, k)
  local v = rawget(FrameMT, k)
  if v ~= nil then return v end
  -- only method-like names (SetText, EnableMouse...); fields such as parent/text stay nil
  if type(k) == "string" and k:match("^[A-Z][a-z]+[A-Z]") then return function() end end
end

function W.NewFrame(ftype, name, parent)
  local f = setmetatable({ ftype = ftype, name = name, parent = parent, shown = true, alpha = 1, scale = 1,
    scripts = {}, events = {}, points = {}, textures = {} }, FrameMT)
  W.frames[#W.frames + 1] = f
  if name then _G[name] = f end
  return f
end

function FrameMT:SetScript(k, fn) self.scripts[k] = fn end
function FrameMT:GetScript(k) return self.scripts[k] end
function FrameMT:RegisterEvent(e)
  if W.unknownEvents[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
  self.events[e] = true
end
function FrameMT:UnregisterEvent(e) self.events[e] = nil end
function FrameMT:Show() self.shown = true end
function FrameMT:Hide() self.shown = false end
function FrameMT:IsShown() return self.shown end
function FrameMT:SetAlpha(a) self.alpha = a end
function FrameMT:GetAlpha() return self.alpha end
function FrameMT:SetScale(s) self.scale = s end
function FrameMT:GetScale() return self.scale end
function FrameMT:GetEffectiveScale() return self.scale end
function FrameMT:SetSize(w, h) self.w, self.h = w, h end
function FrameMT:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FrameMT:ClearAllPoints() self.points = {} end
function FrameMT:SetAllPoints() end
function FrameMT:SetFrameStrata(s) self.strata = s end
function FrameMT:SetFrameLevel(l) self.level = l end
function FrameMT:SetClampedToScreen() end
function FrameMT:CreateFontString()
  local fs = W.NewFrame("FontString")
  fs.SetText = function(self, t) self.text = t end
  return fs
end
function FrameMT:CreateTexture()
  local t = W.NewFrame("Texture")
  t.SetColorTexture = function(tex, r, g, b, a) tex.color = { r, g, b, a } end
  self.textures[#self.textures + 1] = t
  return t
end

function CreateFrame(ftype, name, parent) return W.NewFrame(ftype, name, parent) end
function FrameMT:GetName() return self.name end
function FrameMT:GetObjectType() return self.ftype end
function EnumerateFrames(after)
  local idx = 0
  if after then
    for i, f in ipairs(W.frames) do if f == after then idx = i break end end
  end
  for i = idx + 1, #W.frames do
    if W.frames[i].ftype ~= "Texture" then return W.frames[i] end
  end
end

-------------------------------------------------------------------------------
-- Clock, timers, events
-------------------------------------------------------------------------------
function GetTime() return W.now end
function time() return W.epoch + math.floor(W.now - 1000) end
function date(fmt, t) return os.date(fmt, t or time()) end

C_Timer = {
  After = function(delay, fn) W.timers[#W.timers + 1] = { at = W.now + delay, fn = fn } end,
}

-- Runs one rendered frame: timers that are due, then every OnUpdate script.
function W.Frame(dt)
  dt = dt or (1 / 60)
  W.now = W.now + dt
  local due = {}
  for i = #W.timers, 1, -1 do
    if W.now >= W.timers[i].at then
      due[#due + 1] = table.remove(W.timers, i)
    end
  end
  for i = #due, 1, -1 do due[i].fn() end
  for _, f in ipairs(W.frames) do
    local s = f.scripts.OnUpdate
    if s then s(f, dt) end
  end
end

function W.Advance(seconds)
  local frames = math.max(1, math.floor(seconds * 60 + 0.5))
  for _ = 1, frames do W.Frame(1 / 60) end
end

function W.Fire(event, ...)
  for _, f in ipairs(W.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-------------------------------------------------------------------------------
-- Game API
-------------------------------------------------------------------------------
local function U(unit)
  if unit == "target" then return W.target end
  return W.units[unit]
end
function UnitName(unit)
  if unit == "player" then return W.player.name, nil end
  local u = U(unit)
  return u and u.name
end
function UnitExists(unit) return unit == "player" or U(unit) ~= nil end
function UnitCanAttack(_, unit) local u = U(unit) return u and u.hostile or false end
function UnitIsPlayer(unit) local u = U(unit) return unit == "player" or (u and u.player) or false end
function UnitGUID(unit) local u = U(unit) return u and u.guid end
function UnitClassification(unit) local u = U(unit) return u and (u.classification or "normal") end
function UnitIsDead(unit) local u = U(unit) return u and u.dead or false end
function UnitIsTapDenied(unit) local u = U(unit) return u and u.tapDenied or false end
function GetAchievementInfo(id)
  local n = W.achievements[id]
  if not n then return nil end
  return id, n, 0, true
end
function UnitClass() return W.player.class, W.player.classFile, W.player.classId end
function UnitLevel(unit)
  if unit == nil or unit == "player" then return W.player.level end
  local u = U(unit)
  return u and u.level or 0
end
function UnitFactionGroup() return W.player.faction, W.player.faction end
function GetRealmName() return W.player.realm end
function GetRealZoneText() return W.zone end
function GetZoneText() return W.zone end
function GetSubZoneText() return W.subzone end
function GetBuildInfo() return "1.60.1", "99999", "Nov 1 2026", 16001 end
function GetPhysicalScreenSize() return W.screenSize[1], W.screenSize[2] end
function GetScreenWidth() return 1024 end
function GetScreenHeight() return 768 end
function GetCVar() return nil end
function IsInInstance()
  if W.instance then return true, W.instance.type end
  return W.bg.instance[1], W.bg.instance[2]
end
function GetInstanceInfo()
  local i = W.instance
  if not i then return GetRealZoneText(), "none", 0, "", 0, 0, false, 0 end
  return i.name, i.type, 1, "Normal", 5, 0, false, i.mapId
end
function UnitIsDeadOrGhost(unit) return unit == "player" and W.player.dead or false end
function StaticPopup_Show(which, a1, a2, data)
  local d = { which = which, arg1 = a1, data = data }
  W.popups[#W.popups + 1] = d
  return d
end
-- clicks a button of the last popup: "accept" or "cancel"
function W.ClickPopup(button)
  local d = W.popups[#W.popups]
  local def = StaticPopupDialogs[d.which]
  if button == "accept" then def.OnAccept(d, d.data) else def.OnCancel(d, d.data) end
end
function GetQuestID() return W.quest and W.quest.id end
function GetTitleText() return W.quest and W.quest.title end
function GetNumQuestRewards() return W.quest and #(W.quest.rewards or {}) or 0 end
function GetNumQuestChoices() return W.quest and #(W.quest.choices or {}) or 0 end
function GetQuestItemLink(kind, i)
  local q = W.quest
  if not q then return nil end
  return (kind == "reward" and q.rewards or q.choices or {})[i]
end
function GetRewardSpell() if W.quest and W.quest.spell then return "Interface\\Icons\\x", W.quest.spell end end
function GetQuestTagInfo() if W.quest then return W.quest.tagID, W.quest.tagName end end
function GetQuestReward(choice) if W.hooks.GetQuestReward then W.hooks.GetQuestReward(choice) end end
function GetNumSkillLines() return #W.skills end
function GetSkillLineInfo(i) local s = W.skills[i] return s.name, s.header or false, true, s.rank end
function GetNumTalentGroups() return W.talentGroups end
function GetAchievementCategory(id) return W.achievementCategory[id] or -1 end
function GetCategoryInfo(cat) local c = W.categories[cat] if c then return c.title, c.parent end end

function Screenshot()
  if W.screenshotError then error(W.screenshotError) end
  local bc = _G.NavtokDiscordBarcode
  W.screenshots[#W.screenshots + 1] = {
    at = W.now, time = time(), barcodeShown = bc and bc:IsShown() or false,
    chatAlpha = ChatFrame1:GetAlpha(),
  }
end

function GetItemInfo(link)
  local id = tonumber(tostring(link):match("item:(%d+)")) or tonumber(link)
  local it = W.items[id]
  if not it then return nil end
  return it.name, link, it.quality, 60, 60, "Armor", "Plate", 1, it.equipLoc or "INVTYPE_CHEST"
end
function IsEquippableItem(link)
  local id = tonumber(tostring(link):match("item:(%d+)")) or tonumber(link)
  local it = W.items[id]
  if not it then return nil end
  return (it.equipLoc or "INVTYPE_CHEST") ~= ""
end
W.hooks = {}
function hooksecurefunc(a, b, c)
  if type(a) == "table" then W.hooks["C_Container." .. b] = c else W.hooks[a] = b end
end
W.bags = {}          -- [bag][slot] = link
W.equipped = {}      -- [slot] = link
W.cursor = nil       -- link on the cursor
function UseContainerItem(bag, slot) if W.hooks.UseContainerItem then W.hooks.UseContainerItem(bag, slot) end end
function GetContainerItemLink(bag, slot) return W.bags[bag] and W.bags[bag][slot] end
function GetInventoryItemLink(_, slot) return W.equipped[slot] end
function GetCursorInfo() if W.cursor then return "item", tonumber(W.cursor:match("item:(%d+)")), W.cursor end end
function GetItemInfoInstant(link)
  local id = tonumber(tostring(link):match("item:(%d+)")) or tonumber(link)
  local it = W.items[id]
  return id, nil, nil, it and it.equipLoc or "INVTYPE_CHEST", nil, it and it.classID or 4, it and it.subclassID or 1
end
W.rollItems = {}
function RollOnLoot(rollID, rollType) if W.hooks.RollOnLoot then W.hooks.RollOnLoot(rollID, rollType) end end
function GetLootRollItemLink(rollID) return W.rollItems[rollID] end

function GetNumFactions() return #W.factions end
function GetFactionInfo(i)
  local f = W.factions[i]
  if not f then return nil end
  return f.name, "", f.standingID, 0, 0, 0, false, false, f.isHeader or false, false, f.hasRep or false,
    false, false, f.factionID
end

MAX_BATTLEFIELD_QUEUES = 3
function GetBattlefieldStatus(i)
  local s = W.bg.status[i]
  if not s then return "none", nil, 0 end
  return s.status, s.map, s.instanceID
end
function GetBattlefieldWinner() return W.bg.winner end
function GetNumBattlefieldScores() return #W.bg.scores end
function GetBattlefieldScore(i)
  local s = W.bg.scores[i]
  return s.name, s.kb, s.hk, s.deaths, s.honor, s.faction
end
function GetBattlefieldInstanceRunTime() return W.bg.runtime end
function RequestBattlefieldScoreData() W.bg.requested = (W.bg.requested or 0) + 1 end

-- GlobalStrings
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
SKILL_RANK_UP = "Your skill in %s has increased to %d."
LOOT_ROLL_YOU_WON = "You won: %s"
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
ITEM_CLASSES_ALLOWED = "Classes: %s"
ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
ERR_LEARN_SPELL_S = "You have learned a new spell: %s."
LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
YOU = "You"
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
COMBATLOG_XPGAIN_FIRSTPERSON_GROUP = "%s dies, you gain %d experience. (+%d group bonus)"
COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
for i, l in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }) do
  _G["FACTION_STANDING_LABEL" .. i] = l
end

-- WoW globals the addon may touch
unpack = unpack or table.unpack
noop()

return W
