-- Notifiers/Reputation.lua: posts every standing increase to Friendly/Honored/Revered/Exalted.
-- standingID is cached per faction in the character DB; the first sighting of a faction only
-- seeds the cache. Factions under collapsed headers are simply not visited (no false posts).
local _, ns = ...
local N = ns.NewNotifier("reputation")

N.MIN_POST_STANDING = 5 -- 5 Friendly, 6 Honored, 7 Revered, 8 Exalted

function N:Scan()
  local cache = ns.char.rep
  local n = GetNumFactions and GetNumFactions() or 0
  for i = 1, n do
    local name, _, standingID, _, _, _, _, _, isHeader, _, hasRep, _, _, factionID = GetFactionInfo(i)
    if name and standingID and (not isHeader or hasRep) then
      local key = factionID and tostring(factionID) or name
      local old = cache[key]
      cache[key] = standingID
      if old and standingID > old and standingID >= self.MIN_POST_STANDING then
        ns.Emit("reputation", { faction = name, standing = standingID })
      end
    end
  end
end

function N:Init()
  self:Scan() -- seeds the cache; only later increases (while online) are posted
  ns.On("UPDATE_FACTION", function() N:Scan() end)
end

function N:Test()
  return { faction = "Stormwind", standing = 8 }
end
