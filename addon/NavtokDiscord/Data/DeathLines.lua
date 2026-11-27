-- Data/DeathLines.lua: flavour lines added to death posts for the session death count. EDIT FREELY.
--
-- Placeholders: {name} = character, {n} = deaths this session, {zone} = zone name.
-- exact = only at that exact count (3rd, 5th, 7th death);
-- from  = every death from that count until the next tier (10-14, 15-19, 20-24, 25+).
--
-- KEEP THIS FILE PLAIN DATA (one table, strings only, no code): NAVTOK.exe reads it too and
-- turns the chosen line into text. Add, change or remove lines freely; keys must stay numbers
-- written as strings. A new release ships the changes to everyone ("Check for updates").
NavtokDeathLines = {
  exact = {
    ["3"] = {
      "{name} died for the 3rd time this session. Warming up?",
      "Three down. {name}'s spirit healer knows the way by now.",
      "{name} has died 3 times this session. Third time's the charm… apparently not.",
      "{name} is collecting spirit healer loyalty points. (3)",
      "Death #3 for {name}. The spirit healer knows you by name now.",
    },
    ["5"] = {
      "{name} died for the 5th time this session, are you okay?",
      "5 deaths this session. {name}, maybe check your gear durability?",
      "{name} is on death #5 this session. The repair bill sends its regards.",
      "{name}: 5 deaths. The repair bill is looking crazy.",
      "5 deaths. {name}, blink twice if you need help.",
      "{name} died again in {zone}. Maybe try a different zone. Or game.",
    },
    ["7"] = {
      "7 deaths this session. {name} has entered a committed relationship with the graveyard.",
      "{name} died for the 7th time this session. The spirit healer is starting to wave hello.",
      "{name} died for the 7th time this session. Are you okay lil bro?",
      "The spirit healer just asked {name} if everything's alright at home. (7)",
      "7 deaths. Someone check on {name}.",
    },
  },
  from = {
    ["10"] = {
      "💀 {n} deaths this session! {name}, it might be time for a break.",
      "{name} reached {n} deaths this session. Achievement unlocked: Professional Corpse Runner.",
      "Double digits! {name} has died {n} times this session.",
      "{name} died for the {n}th time this session. Are you okay lil bro? Genuinely asking.",
      "{n} deaths. {name}, this is a cry for help.",
      "{name} is speedrunning the graveyard. ({n})",
      "{name} died again. That's {n}. The graveyard has a loyalty card with your name on it.",
      "{n} deaths. {name}, have you tried not dying?",
      "Death #{n}. {name}'s corpse has its own hearthstone at this point.",
    },
    ["15"] = {
      "{n} deaths this session. {name}, the ghost form looks good on you.",
      "{name} died for the {n}th time this session. Should we call someone?",
      "{n} deaths. Put the fries in the bag bro.",
      "{name} has died {n} times. Their killers are farming them.",
      "{n} deaths. {name}, the spirit healer is charging rent now.",
      "{name} died for the {n}th time. Ghost form is basically your main spec.",
      "{n}. {name}, I'm not saying uninstall, but I'm not not saying it.",
    },
    ["20"] = {
      "{n} deaths. Log off bro.",
      "{name} died for the {n}th time. Log off. Touch grass.",
      "{n} deaths. {name}, the game is asking you to stop.",
      "{name}: {n} deaths this session. Please hydrate. And maybe log off.",
      "{n} deaths. Bro. Bro. Log off.",
      "{name}: {n} deaths. Your keyboard is filing a complaint.",
      "{n} deaths. Even the murlocs feel bad for you, {name}.",
      "{n} deaths. Valen is waiting for you.",
    },
    ["25"] = {
      "{name} has died {n} times this session. At this point it's a lifestyle.",
      "Death #{n} this session for {name}. The graveyard is naming a bench after you.",
      "{n} deaths. {name} is no longer playing WoW. WoW is playing {name}.",
      "{name} has died {n} times. We're not even mad. We're impressed.",
      "{n}. LOG OFF. BRO.",
      "{name}: {n}. Go to bed.",
      "{n} deaths. Someone take {name}'s keyboard away.",
      "{name} has died {n} times. This is now a documentary.",
      "Death #{n}. {name} has been reported for griefing the graveyard.",
    },
  },
}
