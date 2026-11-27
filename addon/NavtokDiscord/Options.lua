-- Options.lua: per-player settings. `/navtok settings` opens a small window; the same changes are
-- possible with `/navtok on|off <type>` and `/navtok set <name> <value>`.
local _, ns = ...

local O = {}
ns.Options = O

-- post types that can be switched off, in display order (deaths are always on)
O.KINDS = {
  { "loot", "Epic loot" }, { "need", "Need roll wins" }, { "equip", "BoE equipped" },
  { "recipe", "Recipes learned" }, { "level", "Level up" }, { "skill", "Profession milestones" },
  { "reputation", "Reputation" }, { "dungeon", "Dungeon / raid clears" }, { "bg", "Battlegrounds" },
  { "rare", "Rare kills" }, { "legacy", "Legacy challenges" },
  { "quest", "Quest rewards" }, { "riding", "Riding skill" }, { "dualspec", "Dual spec" },
}
O.QUALITY = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
O.QUALITY_SETTINGS = {
  loot = "lootMinQuality", need = "needMinQuality", boe = "equipMinQuality", recipe = "recipeMinQuality",
}

local function s() return ns.settings end

function O.SetEnabled(kind, on)
  for _, k in ipairs(O.KINDS) do
    if k[1] == kind then
      s().enabled = s().enabled or {}
      s().enabled[kind] = on and true or false
      return true
    end
  end
  return false
end

local function parseQuality(v)
  local n = tonumber(v)
  if n then return (n >= 0 and n <= 5) and n or nil end
  v = (v or ""):lower()
  for i = 0, 5 do
    if O.QUALITY[i]:lower() == v or (v == "green" and i == 2) or (v == "blue" and i == 3)
      or (v == "purple" and i == 4) or (v == "orange" and i == 5) or (v == "white" and i == 1)
      or (v == "grey" and i == 0) or (v == "gray" and i == 0) or (v == "all" and i == 0) then
      return i
    end
  end
end

-- `/navtok set <name> <value>`; returns a message
function O.Set(name, value)
  name = (name or ""):lower()
  if O.QUALITY_SETTINGS[name] then
    local q = parseQuality(value)
    if not q then return "quality: poor|common|uncommon|rare|epic|legendary (or 0-5)" end
    s()[O.QUALITY_SETTINGS[name]] = q
    return name .. " minimum quality: " .. O.QUALITY[q]
  elseif name == "skills" then
    local list = {}
    for n in (value or ""):gmatch("%d+") do list[#list + 1] = tonumber(n) end
    if #list == 0 then return "usage: /navtok set skills 75,150,225,300" end
    table.sort(list)
    s().skillMilestones = list
    return "profession milestones: " .. table.concat(list, ", ")
  elseif name == "levels" then
    local n = tonumber(value)
    if not n or n < 1 then return "usage: /navtok set levels <N> (post every N levels)" end
    s().levelEvery = math.floor(n)
    return "level ups: every " .. s().levelEvery .. " levels (and level " .. (s().maxLevel or 60) .. ")"
  end
  return "settings: loot|need|boe|recipe <quality>, skills <list>, levels <N>"
end

function O.Summary()
  local on, off = {}, {}
  for _, k in ipairs(O.KINDS) do
    if ns.IsEnabled(k[1]) then on[#on + 1] = k[1] else off[#off + 1] = k[1] end
  end
  local st = s()
  return {
    "posting: " .. table.concat(on, ", ") .. ", death (always)",
    "off: " .. (#off > 0 and table.concat(off, ", ") or "none"),
    ("min quality - loot %s, need %s, boe %s, recipe %s"):format(O.QUALITY[st.lootMinQuality] or "?",
      O.QUALITY[st.needMinQuality] or "?", O.QUALITY[st.equipMinQuality] or "?", O.QUALITY[st.recipeMinQuality] or "?"),
    "professions at " .. table.concat(st.skillMilestones or {}, ", ") .. "; levels every " .. (st.levelEvery or 1),
  }
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local frame

local function label(parent, text, x, y, size)
  local fs = parent:CreateFontString(nil, "OVERLAY", size or "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function build()
  local f = CreateFrame("Frame", "NavtokDiscordOptions", UIParent)
  f:SetSize(380, 510)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
  label(f, "NAVTOK settings", 16, -14, "GameFontNormalLarge")
  label(f, "Deaths are always posted.", 16, -36, "GameFontHighlightSmall")

  f.checks = {}
  for i, k in ipairs(O.KINDS) do
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    cb:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + col * 180, -56 - row * 26)
    local text = cb.text or cb.Text
    if type(text) ~= "table" or not text.SetText then text = label(cb, "", 28, -6, "GameFontHighlight") end
    text:SetText(k[2])
    cb:SetScript("OnClick", function(self) O.SetEnabled(k[1], self:GetChecked()) end)
    f.checks[k[1]] = cb
  end

  local y = -56 - math.ceil(#O.KINDS / 2) * 26 - 12
  f.quality = {}
  for _, q in ipairs({ { "loot", "Loot minimum" }, { "need", "Need win minimum" }, { "boe", "BoE minimum" },
    { "recipe", "Recipe minimum" } }) do
    label(f, q[2], 16, y - 4, "GameFontHighlight")
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(120, 22)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 200, y)
    b:SetScript("OnClick", function(self)
      local key = O.QUALITY_SETTINGS[q[1]]
      s()[key] = ((s()[key] or 0) + 1) % 6
      self:SetText(O.QUALITY[s()[key]])
    end)
    f.quality[q[1]] = b
    y = y - 26
  end

  label(f, "Professions post at", 16, y - 8, "GameFontHighlight")
  local skills = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  skills:SetSize(150, 20)
  skills:SetPoint("TOPLEFT", f, "TOPLEFT", 200, y - 4)
  skills:SetAutoFocus(false)
  skills:SetScript("OnEnterPressed", function(self) O.Set("skills", self:GetText()) self:ClearFocus() end)
  f.skills = skills
  y = y - 30
  label(f, "Post every N levels", 16, y - 8, "GameFontHighlight")
  local levels = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  levels:SetSize(50, 20)
  levels:SetPoint("TOPLEFT", f, "TOPLEFT", 200, y - 4)
  levels:SetAutoFocus(false)
  levels:SetScript("OnEnterPressed", function(self) O.Set("levels", self:GetText()) self:ClearFocus() end)
  f.levels = levels
  label(f, "Press Enter to save a text field.", 16, y - 34, "GameFontHighlightSmall")

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetSize(90, 24)
  close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
  close:SetText(CLOSE or "Close")
  close:SetScript("OnClick", function() f:Hide() end)
  if UISpecialFrames then table.insert(UISpecialFrames, "NavtokDiscordOptions") end -- Escape closes it
  f:Hide()
  return f
end

function O.Refresh()
  if not frame then return end
  for kind, cb in pairs(frame.checks) do cb:SetChecked(ns.IsEnabled(kind)) end
  for kind, b in pairs(frame.quality) do b:SetText(O.QUALITY[s()[O.QUALITY_SETTINGS[kind]]] or "?") end
  frame.skills:SetText(table.concat(s().skillMilestones or {}, ","))
  frame.levels:SetText(tostring(s().levelEvery or 1))
end

function O.Open()
  if not frame then frame = build() end
  O.Refresh()
  frame:Show()
end
