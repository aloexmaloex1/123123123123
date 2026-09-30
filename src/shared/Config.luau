-- Shared tuning for Relic RNG: Museum Heist.
-- Every balance number lives here so it can be changed without touching game logic.
-- Feature-specific tuning lives in ReplicatedStorage.RelicRNG.FeatureConfig.
local Config = {}

-- Tier order matters: index 1 is the most common, the last is the rarest.
-- Chance is a percent at luck 1 and all chances add up to 100. Income is coins per minute on display.
Config.Rarities = {
	{ Name = "Common", Chance = 45, Income = 1, Color = Color3.fromRGB(170, 170, 170) },
	{ Name = "Uncommon", Chance = 25, Income = 2, Color = Color3.fromRGB(85, 200, 95) },
	{ Name = "Rare", Chance = 14, Income = 5, Color = Color3.fromRGB(70, 140, 255) },
	{ Name = "Epic", Chance = 8, Income = 12, Color = Color3.fromRGB(165, 85, 240) },
	{ Name = "Legendary", Chance = 4.5, Income = 30, Color = Color3.fromRGB(255, 150, 40) },
	{ Name = "Mythic", Chance = 2, Income = 75, Color = Color3.fromRGB(235, 50, 60) },
	{ Name = "Ancient", Chance = 0.9, Income = 180, Color = Color3.fromRGB(240, 200, 60) },
	{ Name = "World Wonder", Chance = 0.35, Income = 450, Color = Color3.fromRGB(255, 225, 140) },
	{ Name = "Celestial", Chance = 0.2, Income = 1000, Color = Color3.fromRGB(190, 235, 255) },
	{ Name = "Forgotten", Chance = 0.05, Income = 3000, Color = Color3.fromRGB(215, 30, 60) },
}

-- Luck multiplies the chance of every tier from LuckMinTier up, then chances are renormalised.
Config.LuckMinTier = 3

-- Pity: after Every rolls without a MinTier-or-better relic, the next roll is upgraded.
Config.Pity = {
	{ Every = 25, MinTier = 3 },
	{ Every = 75, MinTier = 4 },
	{ Every = 200, MinTier = 5 },
	{ Every = 750, MinTier = 6 },
}

Config.Economy = {
	StartingTickets = 5,
	StarterRelic = "rusty_coin",
	TicketCost = 10,
	FreeTicketInterval = 60, -- seconds online per free Dig Ticket
	FreeTicketCap = 10, -- free tickets stop accruing at this many
	OfflineCapSeconds = 4 * 60 * 60,
	RollCooldown = 1.2,
	DisplaySlots = 8, -- base pedestals; upgrades and passes add more
	MaxDisplaySlots = 16, -- pedestals physically present in each plot
	AnnounceMinTier = 6, -- Mythic and rarer get a server-wide announcement
	AutosaveInterval = 60,
}

-- Curator Level: XP needed to go from `level` to `level + 1`.
function Config.XPForLevel(level)
	return math.floor(40 * level ^ 1.35)
end

function Config.RollXP(tier, ticketCost)
	return (4 + tier * 3) * ticketCost
end

-- Dig sites, in unlock order. Center/Radius define where rolling at that site is allowed.
Config.DigSiteOrder = { "DustyDunes", "SunkenVault", "FrozenReliquary", "MeteorCrater", "HauntedBazaar", "CelestialRuins" }
Config.DigSites = {
	DustyDunes = { Name = "Dusty Dunes", Level = 1, TicketCost = 1, Luck = 1, Center = Vector3.new(0, 0, -140), Radius = 60, Color = Color3.fromRGB(222, 196, 140), Blurb = "Beginner desert excavation. Coins, pottery and desert royalty." },
	SunkenVault = { Name = "Sunken Vault", Level = 6, TicketCost = 2, Luck = 1.3, Center = Vector3.new(-220, 0, -140), Radius = 55, Color = Color3.fromRGB(60, 150, 190), Blurb = "Flooded ruins full of naval relics and drowned kings." },
	FrozenReliquary = { Name = "Frozen Reliquary", Level = 16, TicketCost = 3, Luck = 1.7, Center = Vector3.new(220, 0, -140), Radius = 55, Color = Color3.fromRGB(180, 225, 245), Blurb = "An ice cave of preserved crowns, bones and sealed weapons." },
	MeteorCrater = { Name = "Meteor Crater", Level = 31, TicketCost = 5, Luck = 2.3, Center = Vector3.new(-440, 0, -140), Radius = 55, Color = Color3.fromRGB(120, 70, 200), Blurb = "A glowing impact zone of star fragments and alien metal." },
	HauntedBazaar = { Name = "Haunted Bazaar", Level = 41, TicketCost = 7, Luck = 3, Center = Vector3.new(440, 0, -140), Radius = 55, Color = Color3.fromRGB(150, 60, 160), Blurb = "An abandoned black market of cursed dolls and tricksters." },
	CelestialRuins = { Name = "Celestial Ruins", Level = 51, TicketCost = 10, Luck = 4, Center = Vector3.new(0, 0, -360), Radius = 55, Color = Color3.fromRGB(255, 235, 170), Blurb = "The endgame. Divine fragments and god-tier relics." },
}

-- Shape picks the placeholder model built on the pedestal (see MuseumService).
local R = function(id, name, tier, shape, color)
	return { Id = id, Name = name, Tier = tier, Shape = shape, Color = color }
end
local rgb = Color3.fromRGB
Config.RelicsBySite = {
	DustyDunes = {
		R("rusty_coin", "Rusty Coin", 1, "Coin", rgb(150, 85, 45)),
		R("cracked_clay_pot", "Cracked Clay Pot", 1, "Pot", rgb(180, 95, 60)),
		R("old_belt_buckle", "Old Belt Buckle", 1, "Block", rgb(120, 110, 95)),
		R("broken_sundial", "Broken Sundial", 1, "Coin", rgb(160, 155, 140)),
		R("faded_map_scrap", "Faded Map Scrap", 1, "Slab", rgb(215, 195, 150)),
		R("stone_arrowhead", "Stone Arrowhead", 1, "Wedge", rgb(110, 105, 100)),
		R("bronze_ring", "Bronze Ring", 2, "Ring", rgb(190, 130, 70)),
		R("painted_shard", "Painted Pottery Shard", 2, "Wedge", rgb(70, 140, 150)),
		R("copper_amulet", "Copper Amulet", 2, "Ball", rgb(200, 110, 70)),
		R("royal_sandals", "Royal Sandals", 2, "Slab", rgb(160, 120, 70)),
		R("golden_scarab", "Golden Scarab", 3, "Ball", rgb(230, 180, 50)),
		R("silver_chalice", "Silver Chalice", 3, "Pot", rgb(200, 205, 215)),
		R("bronze_bell", "Bronze Bell", 3, "Pot", rgb(175, 120, 60)),
		R("royal_playing_card", "Royal Playing Card", 3, "Slab", rgb(235, 235, 240)),
		R("whispering_mask", "Whispering Mask", 4, "Mask"),
		R("emerald_serpent_idol", "Emerald Serpent Idol", 4, "Idol", rgb(40, 170, 90)),
		R("clockwork_heart", "Clockwork Heart", 4, "Ball", rgb(190, 150, 80)),
		R("pharaoh_mask", "Mask of the Forgotten Pharaoh", 5, "Mask", rgb(235, 185, 50)),
		R("astronomer_orb", "Astronomer's Golden Orb", 5, "Ball", rgb(245, 200, 70)),
		R("eye_of_colossus", "Eye of the Colossus", 6, "Ball"),
		R("dragonbone_crown", "Dragonbone Crown", 6, "Crown", rgb(235, 225, 200)),
		R("sun_crown", "Sun Crown", 7, "Crown"),
		R("tower_of_babel", "Miniature Tower of Babel", 8, "Tower"),
		R("halo_first_dawn", "Halo of the First Dawn", 9, "Ring"),
		R("the_first_coin", "The First Coin", 10, "Coin", rgb(15, 10, 12)),
	},
	SunkenVault = {
		R("barnacled_coin", "Barnacled Coin", 1, "Coin", rgb(110, 130, 110)),
		R("sailors_bottle", "Sailor's Bottle", 1, "Pot", rgb(70, 120, 90)),
		R("tarnished_spyglass", "Tarnished Spyglass", 2, "Block", rgb(150, 120, 70)),
		R("pearl_button", "Pearl Button", 2, "Coin", rgb(235, 230, 220)),
		R("drowned_compass", "Drowned Captain's Compass", 3, "Coin", rgb(180, 150, 90)),
		R("ships_bell", "Ship's Bell", 3, "Pot", rgb(190, 150, 70)),
		R("coral_crown", "Coral Crown", 4, "Crown", rgb(240, 110, 100)),
		R("drowned_king_crown", "Crown of the Drowned King", 5, "Crown", rgb(90, 170, 170)),
		R("pearl_abyss", "Pearl of the Abyss", 6, "Ball", rgb(60, 40, 120)),
		R("leviathan_tooth", "Leviathan Tooth", 7, "Wedge", rgb(235, 235, 215)),
		R("ark_ancient_kings", "Ark of Ancient Kings", 8, "Block", rgb(200, 160, 60)),
		R("heart_deep_sea", "Heart of the Deep Sea", 9, "Ball", rgb(40, 160, 255)),
		R("drowned_choir", "The Drowned Choir", 10, "Idol", rgb(10, 30, 40)),
	},
	FrozenReliquary = {
		R("frostbitten_arrow", "Frostbitten Arrow", 1, "Wedge", rgb(170, 190, 200)),
		R("ancient_ice_shard", "Ancient Ice Shard", 1, "Wedge", rgb(190, 230, 250)),
		R("bone_comb", "Carved Bone Comb", 2, "Slab", rgb(230, 220, 195)),
		R("frost_beads", "Frost Bead Necklace", 2, "Ring", rgb(160, 210, 240)),
		R("viking_compass", "Viking Compass", 3, "Coin", rgb(150, 120, 80)),
		R("frozen_horn", "Frozen War Horn", 3, "Pot", rgb(210, 200, 180)),
		R("sealed_frost_blade", "Sealed Frost Blade", 4, "Slab", rgb(150, 220, 255)),
		R("blade_first_ranger", "Blade of the First Ranger", 5, "Slab", rgb(200, 210, 220)),
		R("frozen_crown", "Frozen Crown", 6, "Crown", rgb(170, 230, 255)),
		R("mammoth_idol", "Mammoth Idol", 7, "Idol", rgb(150, 110, 80)),
		R("glacier_throne", "Glacier Throne", 8, "Tower", rgb(200, 240, 255)),
		R("aurora_heart", "Aurora Heart", 9, "Ball", rgb(120, 255, 200)),
		R("the_last_winter", "The Last Winter", 10, "Ring", rgb(240, 250, 255)),
	},
	MeteorCrater = {
		R("scorched_pebble", "Scorched Pebble", 1, "Ball", rgb(60, 50, 45)),
		R("alien_rivet", "Alien Rivet", 1, "Block", rgb(120, 130, 140)),
		R("glowing_debris", "Glowing Debris", 2, "Wedge", rgb(120, 255, 140)),
		R("stardust_vial", "Stardust Vial", 2, "Pot", rgb(200, 180, 255)),
		R("meteor_shard", "Meteor Shard", 3, "Wedge", rgb(170, 90, 60)),
		R("alien_metal", "Alien Metal Plate", 3, "Slab", rgb(140, 200, 210)),
		R("star_fragment", "Star Fragment", 4, "Ball", rgb(255, 240, 150)),
		R("comet_core", "Comet Core", 5, "Ball", rgb(120, 200, 255)),
		R("celestial_compass", "Celestial Compass", 6, "Coin", rgb(220, 200, 255)),
		R("void_prism", "Void Prism", 7, "Wedge", rgb(80, 20, 140)),
		R("golden_observatory", "Golden Observatory", 8, "Tower", rgb(240, 200, 80)),
		R("fragment_of_moon", "Fragment of the Moon", 9, "Ball", rgb(230, 230, 240)),
		R("relic_should_not_exist", "The Relic That Should Not Exist", 10, "Mask", rgb(5, 5, 5)),
	},
	HauntedBazaar = {
		R("carnival_ticket", "Carnival Ticket", 1, "Slab", rgb(220, 60, 70)),
		R("moth_eaten_glove", "Moth-Eaten Glove", 1, "Block", rgb(90, 80, 90)),
		R("porcelain_doll", "Smiling Porcelain Doll", 2, "Idol", rgb(240, 225, 220)),
		R("tarot_card", "Cursed Tarot Card", 2, "Slab", rgb(120, 60, 140)),
		R("haunted_marionette", "Haunted Marionette", 3, "Idol", rgb(150, 90, 60)),
		R("skull_candle", "Skull Candle", 3, "Pot", rgb(230, 225, 200)),
		R("jester_mask", "Jester's Grin Mask", 4, "Mask", rgb(200, 40, 120)),
		R("lantern_lost_souls", "Lantern of Lost Souls", 5, "Pot", rgb(120, 255, 200)),
		R("haunted_mirror", "Haunted Vanity Mirror", 6, "Slab", rgb(180, 200, 220)),
		R("puppeteer_crown", "Puppeteer's Crown", 7, "Crown", rgb(100, 30, 60)),
		R("phantom_carousel", "Phantom Carousel", 8, "Tower", rgb(170, 120, 220)),
		R("moonlit_music_box", "Moonlit Music Box", 9, "Block", rgb(190, 170, 255)),
		R("mirror_that_watches", "The Mirror That Watches", 10, "Slab", rgb(20, 10, 25)),
	},
	CelestialRuins = {
		R("divine_marble", "Divine Marble Fragment", 1, "Wedge", rgb(245, 240, 230)),
		R("angel_quill", "Angel Feather Quill", 1, "Slab", rgb(250, 250, 255)),
		R("star_map", "Star Map", 2, "Slab", rgb(40, 50, 110)),
		R("moon_chalice", "Moon Chalice", 2, "Pot", rgb(210, 220, 240)),
		R("halo_fragment", "Halo Fragment", 3, "Ring", rgb(255, 230, 150)),
		R("sun_disc", "Sun Disc", 3, "Coin", rgb(255, 200, 60)),
		R("phoenix_feather", "Phoenix Feather in Glass", 4, "Pot", rgb(255, 120, 40)),
		R("seraph_lyre", "Seraph's Lyre", 5, "Slab", rgb(255, 225, 120)),
		R("divine_fragment", "Divine Fragment", 6, "Wedge", rgb(255, 250, 220)),
		R("garden_of_eden", "Floating Garden of Eden", 7, "Ball", rgb(90, 200, 90)),
		R("starforged_throne", "Starforged Throne", 8, "Tower", rgb(200, 220, 255)),
		R("crown_sky_serpent", "Crown of the Sky Serpent", 9, "Crown", rgb(140, 230, 255)),
		R("the_nameless_crown", "The Nameless Crown", 10, "Crown", rgb(15, 15, 20)),
	},
}

-- Collection sets. Owning every relic in a set (on display or not) activates its bonus.
-- Bonus kinds: Income / Luck (multiplier add, 0.1 = +10%), OfflineHours, HeistSeconds.
Config.Sets = {
	{ Id = "dusty_beginnings", Name = "Dusty Beginnings", Relics = { "rusty_coin", "cracked_clay_pot", "old_belt_buckle", "broken_sundial", "faded_map_scrap", "stone_arrowhead" }, Bonus = { Income = 0.05 }, Reward = { Tickets = 10 } },
	{ Id = "desert_kings", Name = "Desert Kings", Relics = { "golden_scarab", "royal_sandals", "sun_crown", "pharaoh_mask" }, Bonus = { Income = 0.10 }, Reward = { Tickets = 50 } },
	{ Id = "ocean_depths", Name = "Ocean Depths", Relics = { "drowned_compass", "coral_crown", "pearl_abyss", "leviathan_tooth" }, Bonus = { Luck = 0.05 }, Reward = { Tickets = 75 } },
	{ Id = "frost_hoard", Name = "Frost Hoard", Relics = { "bone_comb", "viking_compass", "sealed_frost_blade", "frozen_crown" }, Bonus = { OfflineHours = 1 }, Reward = { Tickets = 100 } },
	{ Id = "cosmic_debris", Name = "Cosmic Debris", Relics = { "meteor_shard", "star_fragment", "comet_core", "celestial_compass" }, Bonus = { Luck = 0.10 }, Reward = { Tickets = 150 } },
	{ Id = "cursed_carnival", Name = "Cursed Carnival", Relics = { "haunted_marionette", "porcelain_doll", "carnival_ticket", "mirror_that_watches" }, Bonus = { HeistSeconds = 30 }, Reward = { Tickets = 250 } },
	{ Id = "celestial_court", Name = "Celestial Court", Relics = { "halo_fragment", "star_map", "moon_chalice", "crown_sky_serpent" }, Bonus = { Income = 0.25 }, Reward = { Tickets = 500 } },
}

Config.Relics = {}
Config.RelicsById = {}
Config.SiteRelicsByTier = {}
for _, siteId in ipairs(Config.DigSiteOrder) do
	local byTier = {}
	for tier in ipairs(Config.Rarities) do
		byTier[tier] = {}
	end
	for _, relic in ipairs(Config.RelicsBySite[siteId]) do
		relic.Site = siteId
		table.insert(Config.Relics, relic)
		Config.RelicsById[relic.Id] = relic
		table.insert(byTier[relic.Tier], relic.Id)
	end
	Config.SiteRelicsByTier[siteId] = byTier
end
-- Back-compat: the starter site's pool.
Config.RelicsByTier = Config.SiteRelicsByTier.DustyDunes

function Config.GetIncome(relicId)
	local relic = Config.RelicsById[relicId]
	return relic and Config.Rarities[relic.Tier].Income or 0
end

-- Tier chances (percent, summing to 100) at a given total luck.
function Config.GetTierChances(luck)
	luck = luck or 1
	local weights, total = {}, 0
	for tier, rarity in ipairs(Config.Rarities) do
		local w = rarity.Chance * (tier >= Config.LuckMinTier and luck or 1)
		weights[tier] = w
		total += w
	end
	for tier, w in ipairs(weights) do
		weights[tier] = w / total * 100
	end
	return weights
end

-- Percent chance of rolling this exact relic at its own site with the given luck.
function Config.GetRelicChance(relicId, luck)
	local relic = Config.RelicsById[relicId]
	local chances = Config.GetTierChances(luck)
	return chances[relic.Tier] / #Config.SiteRelicsByTier[relic.Site][relic.Tier]
end

-- Which dig site (if any) a world position is inside.
function Config.SiteAt(position)
	for _, siteId in ipairs(Config.DigSiteOrder) do
		local site = Config.DigSites[siteId]
		local offset = position - site.Center
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= site.Radius then
			return siteId
		end
	end
	return nil
end

function Config.FormatNumber(n)
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""):gsub("^%-,", "-"))
end

-- 1.2K / 3.4M style for tight spaces.
function Config.Abbreviate(n)
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while math.abs(n) >= 1000 and i < #units do
		n /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(math.floor(n))
	end
	return (string.format(n < 10 and "%.2f" or n < 100 and "%.1f" or "%.0f", n):gsub("%.?0+$", "")) .. units[i]
end

return Config
