-- Notifiers/Equip.lua: a Bind-on-Equip item is equipped (blue or better by default,
-- settings.equipMinQuality). Equipping a BoE item makes WoW ask "will bind to you"
-- (EQUIP_BIND_CONFIRM / AUTOEQUIP_BIND_CONFIRM); the next PLAYER_EQUIPMENT_CHANGED shortly after
-- is that item.
local _, ns = ...
local N = ns.NewNotifier("equip")

N.WINDOW = 15

local function itemIdOf(link) return link and tonumber(link:match("item:(%d+)")) end

function N:OnBindConfirm()
  local link
  if GetCursorInfo then
    local kind, _, cursorLink = GetCursorInfo()
    if kind == "item" then link = cursorLink end
  end
  self.pending = { at = GetTime(), id = itemIdOf(link) }
end

function N:OnEquipmentChanged(slot)
  local p = self.pending
  if not p or GetTime() - p.at > self.WINDOW then return end
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
  local id = itemIdOf(link)
  if not id or (p.id and p.id ~= id) then return end
  self.pending = nil
  local name, _, quality = GetItemInfo(link)
  if (quality or 0) < (tonumber((ns.settings or ns.DEFAULTS).equipMinQuality) or 3) then return end
  ns.Emit("equip", { itemId = id, quality = quality, slot = slot,
    item = name or link:match("%[(.-)%]") or ("item " .. id) }, { delay = 0.3 })
end

function N:Init()
  for _, e in ipairs({ "EQUIP_BIND_CONFIRM", "AUTOEQUIP_BIND_CONFIRM", "EQUIP_BIND_TRADEABLE_CONFIRM" }) do
    ns.On(e, function() N:OnBindConfirm() end)
  end
  ns.On("PLAYER_EQUIPMENT_CHANGED", function(_, slot) N:OnEquipmentChanged(tonumber(slot)) end)
end

function N:Test()
  return { itemId = 12640, quality = 4, slot = 1, item = "Lionheart Helm" }
end
