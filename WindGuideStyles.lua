-- Wind Guide's styles (WindGuide.lua): what blows toward your waypoint. One
-- for each of Vitals Vision's themes (LowHealthThemes.lua), by its key, so
-- Auto picks your class and spec's the same way, plus plain wind and motes
-- of light. Kept subtle and soft: wind, light, shadow, snow, embers,
-- lightning, coloured wisps; no pictures of things.
-- Each style:
--   name    what the page calls it (English: translated there)
--   parts   what blows in, each picked by its weight:
--     tex     its sprites (Textures/WindGuide, Media/make_wind_guide.py), one picked
--     size    { min, max } shares of the screen's height (as it comes in);
--             spread: most near the min, a few big, the higher it is (1: even)
--     speed   screen heights a second
--     sway    { how far it weaves (share of its speed), weaves a second }
--     spin    { min, max } radians a second (either way); still: never turned;
--             else it faces the way it blows (its head leads)
--     drift   screen heights a second up (down if less than 0) as it blows
--     twinkle shimmers this many times a second
--     colors  picked from; alpha, add (drawn additively: light)
--     motion  how it goes (else it blows straight in):
--               crackle  jumps to a new shape, angle and brightness many times a
--                        second (lightning)
--               pull     speeds up and shrinks away as it nears the waypoint (souls)
--     weight  how often, next to the others (1)
--   gust    seconds from one gust to the next (7); calm: how much blows
--           between gusts, next to the most (0.15)
--   pulse   beats a minute: everything throbs with a heartbeat
--   arrive  where the waypoint is on the screen, now and then: { tex, kind
--           ("ripple" spreads and fades, "glow" swells in and out, "pop" swells
--           and bursts), every (seconds), size, color, add, alpha }

local _, ns = ...

-- The wind: gusts of a few strands, with single streaks among them.
local function Wind(colors, speed, alpha, weight)
	return { tex = { "Gust1", "Gust2", "Streak" }, size = { 0.13, 0.22 }, speed = speed or 0.5,
		sway = { 0.12, 1.2 }, colors = colors, alpha = alpha or 0.5, add = true, weight = weight }
end
-- Coloured wisps: thin curling streaks.
local function Wisps(colors, speed, alpha, weight)
	return { tex = { "Wisp", "Wisp", "Streak" }, size = { 0.1, 0.18 }, speed = speed or 0.5,
		sway = { 0.15, 1.5 }, colors = colors, alpha = alpha or 0.45, add = true, weight = weight }
end
-- Light: soft glows of all sizes, shimmering, drifting up a little.
local function Light(colors, weight)
	return { tex = { "Glow" }, size = { 0.025, 0.08 }, spread = 2, speed = 0.14, sway = { 0.3, 0.5 },
		drift = 0.02, twinkle = 0.5, still = true, colors = colors, alpha = 0.8, add = true, weight = weight }
end
-- Shadow: soft dark smears.
local function Shadow(colors, speed, weight)
	return { tex = { "Shade1", "Shade2" }, size = { 0.12, 0.2 }, speed = speed or 0.3, sway = { 0.12, 0.8 },
		colors = colors, alpha = 0.55, weight = weight }
end
local function Motes(colors, speed, motion, weight)
	return { tex = { "Mote" }, size = { 0.015, 0.04 }, spread = 2, speed = speed or 0.2, sway = { 0.35, 1.2 },
		still = true, colors = colors, alpha = 0.9, add = true, motion = motion, weight = weight }
end
local function Embers(colors, rise, weight)
	return { tex = { "Ember" }, size = { 0.025, 0.05 }, spread = 1.5, speed = 0.3, sway = { 0.4, 1.8 },
		drift = rise or 0.12, still = true, colors = colors, alpha = 0.95, add = true, weight = weight }
end
-- Stars of all sizes, most small, twinkling.
local function Stars(colors, biggest, weight)
	return { tex = { "Star" }, size = { 0.012, biggest or 0.06 }, spread = 2.5, speed = 0.2, sway = { 0.4, 0.6 },
		twinkle = 0.8, still = true, colors = colors, alpha = 0.9, add = true, weight = weight }
end
-- Snow: soft flakes of all sizes, falling a little as they blow.
local function Snow(weight)
	return { tex = { "Snow" }, size = { 0.006, 0.02 }, spread = 2, speed = 0.2, sway = { 0.5, 0.5 },
		drift = -0.05, still = true, colors = { { 1, 1, 1 }, { 0.9, 0.95, 1 } }, alpha = 0.85, weight = weight }
end
local function Glow(color, every, size)
	return { tex = "Glow", kind = "glow", every = every or 2, size = size or 0.1, color = color, add = true }
end

local PALE = { { 0.9, 0.95, 1 }, { 0.8, 0.88, 0.95 } }
local GOLD = { { 1, 0.85, 0.45 }, { 1, 0.93, 0.7 } }
local HOLY = { { 1, 0.95, 0.8 }, { 1, 1, 0.92 } }
local FEL = { { 0.45, 1, 0.25 }, { 0.6, 1, 0.35 } }

-- Valhalla: simple white wisps on a cold wind, now and then a gold spark
-- from the hall's fires.
local VALHALLA = { name = "Valhalla", parts = { Wisps({ { 1, 1, 1 }, { 0.92, 0.95, 1 } }, 0.55, 0.5, 6),
	Embers({ { 1, 0.75, 0.3 }, { 1, 0.85, 0.45 } }, 0.06) } }
local PALADIN = { name = "Motes of light", parts = { Motes(GOLD) } }
-- Priests' light: soft glows and faint light wisps.
local function HolyLight(colors, glow)
	return { name = "Light", parts = { Light(colors, 3), Wisps(colors, 0.3, 0.25) }, arrive = Glow(glow, 2.5, 0.12) }
end

ns.WIND_GUIDE_STYLES = {
	-- (Plain: the page's first choices after Auto.)
	streaks = { name = "Wind", parts = { Wind(PALE) } },
	motes = { name = "Motes of light", parts = { Motes({ { 1, 0.85, 0.5 }, { 1, 0.95, 0.75 } }) } },

	-- Warrior: all Valhalla.
	blood = VALHALLA, wounds = VALHALLA, rage = VALHALLA, shield = VALHALLA,

	-- Paladin: just motes of light, golden.
	holylight = PALADIN, holyshield = PALADIN, judgement = PALADIN,

	-- Hunter: simple wisps (Beast Mastery shares Feral's key).
	claws = { name = "Wisps", parts = { Wisps({ { 0.95, 0.9, 0.75 }, { 0.85, 0.92, 0.8 } }) } },
	lonewolf = { name = "Wisps", parts = { Wisps(PALE, 0.6) } },
	thorns = { name = "Wisps", parts = { Wisps({ { 0.85, 0.95, 0.8 }, { 0.9, 0.95, 0.9 } }) } },

	-- Rogue
	poison = { name = "Venom wisps", parts = { Wisps({ { 0.35, 0.75, 0.25 }, { 0.3, 0.6, 0.2 } }, 0.4, 0.4) } },
	bruise = { name = "Wind", parts = { Wind(PALE, 0.7) } },
	outlaw = { name = "Sea breeze", parts = { Wind({ { 0.75, 0.92, 0.95 }, { 0.9, 0.97, 1 } }, 0.6) } },
	shadow = { name = "Shadow", parts = { Shadow({ { 0.08, 0.05, 0.12 } }, 0.35, 3), Wisps({ { 0.4, 0.3, 0.55 } }, 0.4, 0.3) } },

	-- Priest
	ward = HolyLight(HOLY, { 1, 0.95, 0.8 }),
	feathers = HolyLight(HOLY, { 1, 0.95, 0.8 }),
	void = { name = "Void", parts = { Shadow({ { 0.15, 0.05, 0.25 } }, 0.3, 3),
		Motes({ { 0.6, 0.35, 0.9 }, { 0.45, 0.25, 0.75 } }, 0.22, "pull", 2) },
		arrive = Glow({ 0.45, 0.2, 0.7 }, 2.5) },

	-- Shaman
	storm = { name = "Lightning", gust = 4, parts = {
		{ tex = { "Arc1", "Arc2", "Arc3", "Arc4", "Arc5", "Arc6" }, size = { 0.04, 0.08 }, spread = 1.5,
			speed = 0.5, sway = { 0.2, 2 }, colors = { { 0.75, 0.85, 1 }, { 0.9, 0.95, 1 } }, alpha = 1, add = true,
			motion = "crackle" } } },
	gale = { name = "Wind", gust = 4, calm = 0.1, parts = { Wind({ { 0.8, 0.9, 1 }, { 0.9, 0.95, 1 } }, 0.75, 0.55) } },
	water = { name = "Rain", parts = { { tex = { "Rain" }, size = { 0.05, 0.08 }, speed = 0.45, sway = { 0.1, 1 },
		colors = { { 0.55, 0.8, 1 } }, alpha = 0.8, add = true } },
		arrive = { tex = "Ripple", kind = "ripple", every = 1.5, size = 0.08, color = { 0.5, 0.8, 1 }, add = true } },

	-- Mage
	arcane = { name = "Arcane stars", parts = { Stars({ { 1, 0.55, 1 }, { 0.75, 0.6, 1 }, { 0.9, 0.85, 1 } }) } },
	fire = { name = "Embers", parts = { Embers({ { 1, 0.5, 0.15 }, { 1, 0.7, 0.25 } }, 0.15) } },
	frost = { name = "Snow", parts = { Snow(4), Wind({ { 0.8, 0.92, 1 } }, 0.35, 0.25) } },

	-- Warlock
	-- (Affliction: creeping shadow, a few sickly souls drawn in through it.)
	agony = { name = "Creeping shadow", parts = { Shadow({ { 0.1, 0.06, 0.12 }, { 0.08, 0.1, 0.06 } }, 0.25, 4),
		Motes({ { 0.55, 0.85, 0.3 }, { 0.45, 0.7, 0.25 } }, 0.22, "pull") } },
	fel = { name = "Fel wisps", parts = { Wisps(FEL, 0.55, 0.45) } },
	-- (Destruction: fire and shadow, embers with shadow smouldering among them.)
	felfire = { name = "Shadowflame", parts = { Embers({ { 1, 0.45, 0.12 }, { 1, 0.62, 0.2 }, { 0.9, 0.3, 0.1 } }, 0.15, 3),
		Shadow({ { 0.08, 0.06, 0.1 } }, 0.3) } },

	-- Druid
	eclipse = { name = "Starlight", parts = { Stars({ { 1, 0.85, 0.45 }, { 1, 0.92, 0.7 } }, 0.04, 2),
		Stars({ { 0.6, 0.75, 1 }, { 0.8, 0.88, 1 } }, 0.035) } },
	bear = { name = "Earth wisps", gust = 10, parts = { Wisps({ { 0.75, 0.6, 0.4 }, { 0.55, 0.65, 0.35 } }, 0.3, 0.4) } },
	leaves = { name = "Green wisps", parts = { Wisps({ { 0.45, 0.85, 0.35 }, { 0.6, 0.95, 0.45 } }, 0.4, 0.45) } },

	-- Death Knight
	bloodrune = { name = "Blood mist", pulse = 60, parts = { Wisps({ { 0.75, 0.08, 0.08 } }, 0.35, 0.6) } },
	runefrost = { name = "Blizzard", gust = 4, parts = { Snow(3), Wind({ { 0.75, 0.9, 1 } }, 0.65, 0.4) } },
	decay = { name = "Plague wisps", gust = 10, parts = { Wisps({ { 0.5, 0.75, 0.2 }, { 0.4, 0.6, 0.15 } }, 0.3, 0.4) } },

	-- Monk
	stagger = { name = "Bubbles", parts = { { tex = { "Bubble" }, size = { 0.012, 0.05 }, spread = 2, speed = 0.18,
		sway = { 0.5, 1.2 }, still = true, colors = { { 1, 0.85, 0.5 }, { 0.95, 0.75, 0.4 } }, alpha = 0.85,
		add = true } },
		arrive = { tex = "Bubble", kind = "pop", every = 1.2, size = 0.05, color = { 1, 0.85, 0.5 }, add = true } },
	mist = { name = "Jade wisps", gust = 9, parts = { Wisps({ { 0.4, 0.9, 0.7 }, { 0.55, 1, 0.8 } }, 0.3, 0.35) } },
	chi = { name = "Chi", parts = { Wisps({ { 0.45, 1, 0.8 } }, 0.6, 0.5) } },

	-- Demon Hunter
	demon = { name = "Fel wisps", gust = 4, parts = { Wisps(FEL, 0.7, 0.5, 2), Embers(FEL, 0.08) } },
	souls = { name = "Souls", parts = { Motes({ { 0.7, 0.45, 1 }, { 0.55, 0.35, 0.95 } }, 0.25, "pull") } },
	devour = { name = "Void hunger", parts = { Motes({ { 0.45, 0.2, 0.7 }, { 0.3, 0.15, 0.55 } }, 0.25, "pull") },
		arrive = Glow({ 0.35, 0.1, 0.55 }, 2) },

	-- Evoker
	dragonfire = { name = "Dragonfire", parts = { Embers({ { 1, 0.55, 0.15 }, { 1, 0.4, 0.1 } }, 0.1) } },
	dream = { name = "Emerald dream", parts = { Wisps({ { 0.5, 1, 0.55 }, { 0.75, 1, 0.6 } }, 0.35, 0.4, 2),
		Motes({ { 0.7, 1, 0.6 } }, 0.18) } },
	sands = { name = "Sands of time", parts = { Wisps({ { 1, 0.8, 0.45 }, { 0.9, 0.7, 0.35 } }, 0.4, 0.4, 2),
		{ tex = { "Mote" }, size = { 0.01, 0.025 }, spread = 2, speed = 0.25, sway = { 0.3, 1 }, twinkle = 1.2,
			still = true, colors = { { 1, 0.9, 0.55 } }, alpha = 0.9, add = true } } },
}

-- Just motes, or just wisps, in your class and spec's colours (Auto's pick):
-- byClass, built when used (ns.WindGuideByClass).
ns.WIND_GUIDE_STYLES.classMotes = { name = "Motes (class and spec)", byClass = "motes" }
ns.WIND_GUIDE_STYLES.classWisps = { name = "Wisps (class and spec)", byClass = "wisps" }

-- Each class and spec's colour (by Vitals Vision's theme key), bright enough
-- to show drawn as light; a lighter shade of each is mixed in.
ns.WIND_GUIDE_COLORS = {
	blood = { { 1, 0.3, 0.25 } }, wounds = { { 1, 0.85, 0.6 } }, rage = { { 1, 0.4, 0.2 } },
	shield = { { 0.85, 0.9, 1 } },
	holylight = { { 1, 0.88, 0.5 } }, holyshield = { { 1, 0.8, 0.4 } }, judgement = { { 1, 0.7, 0.3 } },
	claws = { { 1, 0.85, 0.55 } }, lonewolf = { { 0.8, 0.88, 1 } }, thorns = { { 0.6, 0.9, 0.4 } },
	poison = { { 0.45, 1, 0.3 } }, bruise = { { 1, 0.55, 0.3 } }, outlaw = { { 0.5, 0.9, 1 } },
	shadow = { { 0.6, 0.45, 0.85 } },
	ward = { { 1, 0.95, 0.75 } }, feathers = { { 1, 1, 0.9 } }, void = { { 0.65, 0.3, 1 } },
	storm = { { 0.6, 0.75, 1 } }, gale = { { 0.6, 0.85, 1 } }, water = { { 0.4, 0.8, 1 } },
	arcane = { { 0.95, 0.5, 1 } }, fire = { { 1, 0.5, 0.15 } }, frost = { { 0.65, 0.9, 1 } },
	agony = { { 0.6, 0.45, 0.85 } }, fel = { { 0.45, 1, 0.25 } }, felfire = { { 1, 0.45, 0.15 } },
	eclipse = { { 1, 0.85, 0.45 }, { 0.6, 0.75, 1 } }, leaves = { { 0.45, 0.9, 0.35 } },
	bear = { { 0.85, 0.65, 0.4 } },
	bloodrune = { { 1, 0.15, 0.15 } }, runefrost = { { 0.55, 0.85, 1 } }, decay = { { 0.55, 0.95, 0.25 } },
	stagger = { { 1, 0.8, 0.4 } }, mist = { { 0.45, 1, 0.8 } }, chi = { { 0.45, 1, 0.8 } },
	demon = { { 0.45, 1, 0.25 } }, souls = { { 0.7, 0.45, 1 } }, devour = { { 0.6, 0.3, 0.95 } },
	dragonfire = { { 1, 0.5, 0.15 } }, dream = { { 0.55, 1, 0.6 } }, sands = { { 1, 0.8, 0.45 } },
}

local byClass = {} -- (built: [kind][theme key])
-- The motes ("motes") or wisps ("wisps") style for a class and spec's theme key.
function ns.WindGuideByClass(kind, theme)
	byClass[kind] = byClass[kind] or {}
	if not byClass[kind][theme] then
		local colors = {}
		for _, c in ipairs(ns.WIND_GUIDE_COLORS[theme] or { { 0.9, 0.95, 1 } }) do
			colors[#colors + 1] = c
			colors[#colors + 1] = { c[1] + (1 - c[1]) * 0.35, c[2] + (1 - c[2]) * 0.35, c[3] + (1 - c[3]) * 0.35 }
		end
		byClass[kind][theme] = { parts = { kind == "motes" and Motes(colors) or Wisps(colors) } }
	end
	return byClass[kind][theme]
end

-- (The plain ones, as the page lists them, before the classes.)
ns.WIND_GUIDE_PLAIN = { "streaks", "motes", "classMotes", "classWisps" }
