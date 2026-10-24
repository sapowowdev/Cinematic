-- Low-health edge themes (LowHealth.lua draws them), one for each class's
-- talent trees, and which the Auto choice picks. The art is white or grey
-- (Media/make_lowhealth.py), tinted here.
--
-- A theme:
--   name     shown in the menu
--   edge     the edge material (Textures/LowHealth/<edge>.tga), or nil for none
--   body     its colour (nil: its glow only)
--   glow     its glow's colour, added on top (nil: none); glowAlpha its strength
--   shadow   the dark edges' colour, at full Shadow tint
--   flash    a big hit's flash colour
--   pulse, bpm  the heartbeat's throb and speed, times the page's
--   sway     the art rocks slowly, sloshing (1 about a hand's width), or nil
--   drip     { tex = "Drip" or "Icicle", color, rate (times the page's), up (running
--            up from the bottom edge) }, or nil
--   effects  sprites from Effects.tga (CELLS below), each:
--     cell   its picture ("Splat": any of the four)
--     kind   how it moves:
--              splat   lands (growing past its size and back), slides a touch, fades
--              reveal  drawn on across, quickly (a cut, a crack), then fades
--              rise    floats up, swaying (embers, motes)
--              fall    falls (rain, shards, dust)
--              flutter drifts down, swaying and turning (feathers, leaves)
--              drift   billows in from the edge, growing (smoke)
--              ripple  a ring spreading out, fading
--              flicker flashes on and off (lightning)
--              twinkle fades in and out (stars, runes, eyes)
--              bubble  swells, wobbling (rising at speed), and bursts
--              pull    drawn in toward the middle, shrinking (souls)
--              sweep   along the edge it starts by (wind); best "across"
--     at     where it starts: "edge" (about where the edges reach, any side),
--            "top", "bottom", "across" (top or bottom) or "sides"
--     trail  this many in a row along the edge, one after another (paw
--            prints: step apart, every seconds)
--     color, add (drawn additively: light), size { min, max } (shares of the
--     screen's height), life { min, max } (seconds), speed (screen heights a
--     second, for rise and fall)
--     hit    { min, max } of them on a big hit; beat: the chance a heartbeat
--            brings one (at full); rate: a minute, at full
--     from   only once the edges are this far in (0-1)

local _, ns = ...

ns.LOW_HEALTH_CELLS = { -- (Effects.tga's cells, 8 across, in this order)
	"Splat1", "Splat2", "Splat3", "Splat4", "Slash", "Claw", "CrackBurst", "Ember",
	"Mote", "Feather", "Leaf", "Puff", "Shard", "Rain", "Bolt", "Ripple",
	"Rune1", "Rune2", "Rune3", "Eye", "Star", "Dust", "Bruise", "Spark",
	"Bubble", "Petal", "Wind", "Sand", "Paw", "WolfEyes", "Leaf2",
}

local BLOOD = { 0.85, 0.05, 0.06 }
local DARK_RED = { 0.35, 0, 0 }

local function Splats(color, hit, beat)
	return { cell = "Splat", kind = "splat", at = "edge", color = color, size = { 0.03, 0.06 },
		life = { 2.5, 5 }, hit = hit or { 2, 4 }, beat = beat or 0.3 }
end

local function BloodDrip(rate)
	return { tex = "Drip", color = BLOOD, rate = rate or 1 }
end

ns.LOW_HEALTH_THEMES = {
	-- The default, and warriors with no talents yet.
	{ key = "blood", name = "Blood", edge = "Soak", body = BLOOD, glow = { 0.5, 0.05, 0.05 }, glowAlpha = 0.5,
		shadow = DARK_RED, flash = { 1, 0, 0 }, drip = BloodDrip(), effects = { Splats(BLOOD) } },

	-- Warrior
	{ key = "wounds", name = "Battle wounds", edge = "Soak", body = BLOOD, glow = { 0.5, 0.05, 0.05 },
		glowAlpha = 0.5, shadow = DARK_RED, flash = { 1, 0, 0 }, drip = BloodDrip(1.3), effects = {
			{ cell = "Slash", kind = "reveal", at = "edge", color = { 0.7, 0.02, 0.03 }, size = { 0.18, 0.3 },
				life = { 3, 5 }, hit = { 1, 2 } },
			Splats(BLOOD, { 1, 3 }, 0.15),
		} },
	{ key = "rage", name = "Rage", edge = "Soak", body = { 1, 0.12, 0.05 }, glow = { 1, 0.35, 0.1 },
		glowAlpha = 0.8, shadow = { 0.45, 0.05, 0 }, flash = { 1, 0.3, 0 }, pulse = 1.6, bpm = 1.25,
		drip = BloodDrip(0.8), effects = {
			Splats({ 1, 0.12, 0.05 }, { 2, 5 }, 0.6),
			{ cell = "Ember", kind = "rise", at = "bottom", color = { 1, 0.4, 0.1 }, add = true,
				size = { 0.015, 0.03 }, life = { 1.5, 3 }, speed = 0.12, rate = 30 },
		} },
	{ key = "shield", name = "Battered shield", edge = "Crack", body = { 0.55, 0.57, 0.62 },
		glow = { 0.9, 0.15, 0.1 }, glowAlpha = 0.6, shadow = { 0.12, 0.12, 0.15 }, flash = { 1, 0.8, 0.5 },
		drip = BloodDrip(0.5), effects = {
			{ cell = "CrackBurst", kind = "reveal", at = "edge", color = { 0.15, 0.15, 0.17 },
				size = { 0.12, 0.2 }, life = { 3, 5 }, hit = { 1, 2 } },
			{ cell = "Spark", kind = "rise", at = "edge", color = { 1, 0.8, 0.4 }, add = true,
				size = { 0.03, 0.05 }, life = { 0.4, 0.8 }, speed = 0.4, hit = { 3, 6 } },
		} },

	-- Paladin
	{ key = "holylight", name = "Fading light", edge = "Glow", glow = { 1, 0.8, 0.35 }, glowAlpha = 0.7,
		shadow = { 0.25, 0.18, 0.05 }, flash = { 1, 0.9, 0.5 }, pulse = 0.7, effects = {
			{ cell = "Mote", kind = "rise", at = "edge", color = { 1, 0.85, 0.4 }, add = true,
				size = { 0.02, 0.04 }, life = { 2, 4 }, speed = 0.05, rate = 40, beat = 0.4 },
		} },
	{ key = "holyshield", name = "Holy shield", edge = "Crack", body = { 0.75, 0.62, 0.3 },
		glow = { 1, 0.9, 0.5 }, glowAlpha = 1, shadow = { 0.2, 0.15, 0.03 }, flash = { 1, 0.95, 0.6 },
		effects = {
			{ cell = "CrackBurst", kind = "reveal", at = "edge", color = { 1, 0.9, 0.5 }, add = true,
				size = { 0.12, 0.2 }, life = { 2, 4 }, hit = { 1, 2 } },
			{ cell = "Mote", kind = "rise", at = "edge", color = { 1, 0.9, 0.5 }, add = true,
				size = { 0.015, 0.03 }, life = { 1.5, 3 }, speed = 0.06, rate = 20 },
		} },
	{ key = "judgement", name = "Judgement", edge = "Flame", body = { 0.5, 0.35, 0.2 }, glow = { 1, 0.75, 0.25 },
		glowAlpha = 1, shadow = { 0.35, 0.15, 0 }, flash = { 1, 0.8, 0.3 }, effects = {
			{ cell = "Ember", kind = "rise", at = "bottom", color = { 1, 0.8, 0.3 }, add = true,
				size = { 0.015, 0.03 }, life = { 1.5, 3 }, speed = 0.15, rate = 40, hit = { 4, 8 } },
		} },

	-- Hunter
	{ key = "claws", name = "Claws", edge = "Soak", body = BLOOD, glow = { 0.5, 0.05, 0.05 }, glowAlpha = 0.4,
		shadow = DARK_RED, flash = { 1, 0, 0 }, bpm = 1.2, drip = BloodDrip(), effects = {
			{ cell = "Claw", kind = "reveal", at = "edge", color = { 0.6, 0.02, 0.03 }, size = { 0.2, 0.3 },
				life = { 3, 5 }, hit = { 1, 1 } },
			Splats(BLOOD, { 1, 2 }, 0.15),
		} },
	-- (Marksmanship: a lone wolf. Cold wind, prints circling, eyes in the dark.)
	{ key = "lonewolf", name = "Lone wolf", edge = "Wind", body = { 0.7, 0.76, 0.85 }, glow = { 0.6, 0.7, 0.85 },
		glowAlpha = 0.5, shadow = { 0.05, 0.07, 0.1 }, flash = { 0.85, 0.9, 1 }, effects = {
			{ cell = "Wind", kind = "sweep", at = "across", color = { 0.8, 0.86, 0.95 }, add = true,
				size = { 0.12, 0.2 }, life = { 1.2, 2 }, speed = 0.45, rate = 25, beat = 0.2 },
			{ cell = "Paw", kind = "splat", at = "across", color = { 0.12, 0.13, 0.16 }, size = { 0.025, 0.035 },
				life = { 3, 4 }, rate = 2, hit = { 1, 1 }, trail = 6, step = 0.06, every = 0.3 },
			{ cell = "WolfEyes", kind = "twinkle", at = "edge", color = { 1, 0.8, 0.3 }, add = true,
				size = { 0.05, 0.08 }, life = { 2.5, 4 }, rate = 5, from = 0.4 },
		} },
	{ key = "thorns", name = "Thorns", edge = "Vines", body = { 0.2, 0.3, 0.12 }, shadow = { 0.08, 0.12, 0.02 },
		flash = { 0.8, 0.1, 0 }, drip = { tex = "Drip", color = { 0.55, 0.12, 0.05 }, rate = 0.7 }, effects = {
			Splats({ 0.55, 0.12, 0.05 }, { 1, 3 }, 0.2),
			{ cell = "Leaf", kind = "flutter", at = "top", color = { 0.35, 0.45, 0.15 }, size = { 0.03, 0.05 },
				life = { 3, 5 }, speed = 0.08, hit = { 1, 2 } },
		} },

	-- Rogue
	{ key = "poison", name = "Poison", edge = "Vines", body = { 0.15, 0.4, 0.1 }, glow = { 0.4, 1, 0.2 },
		glowAlpha = 0.6, shadow = { 0.05, 0.18, 0.02 }, flash = { 0.5, 1, 0.2 }, pulse = 0.8, bpm = 0.8,
		drip = { tex = "Drip", color = { 0.35, 0.85, 0.15 }, rate = 1.2 }, effects = {
			Splats({ 0.35, 0.85, 0.15 }, { 2, 3 }, 0.3),
		} },
	{ key = "bruise", name = "Brawl", edge = "Soak", body = { 0.6, 0.05, 0.1 }, glow = { 0.4, 0.05, 0.1 },
		glowAlpha = 0.4, shadow = { 0.2, 0, 0.12 }, flash = { 0.8, 0.1, 0.4 }, drip = BloodDrip(0.6), effects = {
			{ cell = "Bruise", kind = "splat", at = "edge", color = { 0.3, 0.05, 0.3 }, size = { 0.08, 0.14 },
				life = { 4, 6 }, hit = { 1, 2 } },
			Splats(BLOOD, { 1, 2 }, 0.1),
		} },
	{ key = "shadow", name = "Shadow", edge = "Smoke", body = { 0.12, 0.1, 0.14 }, shadow = { 0, 0, 0 },
		flash = { 0.3, 0.2, 0.4 }, pulse = 0.7, effects = {
			{ cell = "Puff", kind = "drift", at = "edge", color = { 0.05, 0.04, 0.07 }, size = { 0.12, 0.22 },
				life = { 3, 5 }, rate = 30, hit = { 2, 3 } },
		} },

	-- Priest
	{ key = "ward", name = "Failing ward", edge = "Crack", body = { 0.7, 0.8, 0.9 }, glow = { 0.9, 0.95, 1 },
		glowAlpha = 0.9, shadow = { 0.1, 0.12, 0.18 }, flash = { 0.9, 0.95, 1 }, effects = {
			{ cell = "CrackBurst", kind = "reveal", at = "edge", color = { 0.9, 0.95, 1 }, add = true,
				size = { 0.12, 0.2 }, life = { 2, 4 }, hit = { 1, 2 } },
			{ cell = "Shard", kind = "fall", at = "top", color = { 0.8, 0.9, 1 }, size = { 0.02, 0.04 },
				life = { 1, 2 }, speed = 0.5, hit = { 2, 4 } },
		} },
	{ key = "feathers", name = "Feathers", edge = "Glow", glow = { 1, 0.97, 0.88 }, glowAlpha = 0.6,
		shadow = { 0.2, 0.2, 0.22 }, flash = { 1, 1, 0.9 }, pulse = 0.6, effects = {
			{ cell = "Feather", kind = "flutter", at = "top", color = { 1, 1, 0.95 }, size = { 0.04, 0.06 },
				life = { 4, 6 }, speed = 0.05, rate = 10, hit = { 1, 2 } },
		} },
	{ key = "void", name = "Void", edge = "Vines", body = { 0.15, 0.05, 0.22 }, glow = { 0.55, 0.2, 0.9 },
		glowAlpha = 0.7, shadow = { 0.1, 0, 0.18 }, flash = { 0.6, 0.2, 1 }, pulse = 1.2, effects = {
			{ cell = "Puff", kind = "drift", at = "edge", color = { 0.15, 0.03, 0.22 }, size = { 0.1, 0.2 },
				life = { 3, 5 }, rate = 15 },
			{ cell = "Eye", kind = "twinkle", at = "edge", color = { 0.75, 0.4, 1 }, add = true,
				size = { 0.04, 0.07 }, life = { 2, 3 }, rate = 6, from = 0.6 },
		} },

	-- Shaman
	{ key = "storm", name = "Storm", edge = "Smoke", body = { 0.18, 0.2, 0.26 }, shadow = { 0.04, 0.05, 0.1 },
		flash = { 0.7, 0.8, 1 }, effects = {
			{ cell = "Bolt", kind = "flicker", at = "top", color = { 0.7, 0.8, 1 }, add = true,
				size = { 0.2, 0.3 }, life = { 0.3, 0.5 }, hit = { 1, 1 }, rate = 4 },
			{ cell = "Rain", kind = "fall", at = "top", color = { 0.6, 0.65, 0.75 }, size = { 0.05, 0.08 },
				life = { 0.6, 1 }, speed = 1.2, rate = 120 },
		} },
	-- (Enhancement: Windfury. Gales tearing round the edges, a crack of lightning on hits.)
	{ key = "gale", name = "Windfury", edge = "Wind", body = { 0.75, 0.85, 0.95 }, glow = { 0.45, 0.7, 1 },
		glowAlpha = 0.8, shadow = { 0.03, 0.06, 0.12 }, flash = { 0.6, 0.8, 1 }, bpm = 1.1, effects = {
			{ cell = "Wind", kind = "sweep", at = "across", color = { 0.7, 0.85, 1 }, add = true,
				size = { 0.14, 0.24 }, life = { 0.8, 1.4 }, speed = 0.9, rate = 50, hit = { 3, 5 }, beat = 0.4 },
			{ cell = "Dust", kind = "sweep", at = "across", color = { 0.6, 0.65, 0.7 }, size = { 0.06, 0.1 },
				life = { 1, 1.6 }, speed = 0.7, rate = 15 },
			{ cell = "Bolt", kind = "flicker", at = "top", color = { 0.65, 0.8, 1 }, add = true,
				size = { 0.12, 0.2 }, life = { 0.25, 0.4 }, hit = { 1, 1 } },
		} },
	{ key = "water", name = "Tides", edge = "Soak", body = { 0.15, 0.35, 0.6 }, glow = { 0.5, 0.8, 1 },
		glowAlpha = 0.8, shadow = { 0, 0.06, 0.15 }, flash = { 0.5, 0.8, 1 }, pulse = 0.8, bpm = 0.8,
		drip = { tex = "Drip", color = { 0.4, 0.65, 0.95 }, rate = 1.3 }, effects = {
			{ cell = "Ripple", kind = "ripple", at = "edge", color = { 0.6, 0.85, 1 }, add = true,
				size = { 0.08, 0.14 }, life = { 1.5, 2.5 }, rate = 20, hit = { 2, 3 }, beat = 0.3 },
		} },

	-- Mage
	{ key = "arcane", name = "Arcane", edge = "Runes", body = { 0.2, 0.1, 0.3 }, glow = { 0.75, 0.45, 1 },
		glowAlpha = 1, shadow = { 0.12, 0.03, 0.2 }, flash = { 0.8, 0.5, 1 }, effects = {
			{ cell = "Star", kind = "twinkle", at = "edge", color = { 0.85, 0.65, 1 }, add = true,
				size = { 0.03, 0.06 }, life = { 0.8, 1.5 }, rate = 40, hit = { 3, 5 } },
			{ cell = "Rune1", kind = "twinkle", at = "edge", color = { 0.75, 0.45, 1 }, add = true,
				size = { 0.04, 0.06 }, life = { 1.5, 2.5 }, rate = 8 },
		} },
	{ key = "fire", name = "Fire", edge = "Flame", body = { 0.45, 0.38, 0.34 }, glow = { 1, 0.5, 0.1 },
		glowAlpha = 1, shadow = { 0.3, 0.08, 0 }, flash = { 1, 0.5, 0.1 }, effects = {
			{ cell = "Ember", kind = "rise", at = "bottom", color = { 1, 0.55, 0.15 }, add = true,
				size = { 0.015, 0.03 }, life = { 1.5, 3 }, speed = 0.15, rate = 50, hit = { 4, 8 } },
		} },
	{ key = "frost", name = "Frost", edge = "Frost", body = { 0.8, 0.9, 1 }, glow = { 0.6, 0.85, 1 },
		glowAlpha = 0.6, shadow = { 0.05, 0.1, 0.2 }, flash = { 0.7, 0.9, 1 }, bpm = 0.7,
		drip = { tex = "Icicle", color = { 0.8, 0.92, 1 }, rate = 0.8 }, effects = {
			{ cell = "CrackBurst", kind = "reveal", at = "edge", color = { 0.85, 0.95, 1 }, size = { 0.12, 0.18 },
				life = { 3, 5 }, hit = { 1, 2 } },
			{ cell = "Shard", kind = "fall", at = "top", color = { 0.85, 0.95, 1 }, size = { 0.02, 0.035 },
				life = { 1, 2 }, speed = 0.45, hit = { 2, 4 } },
		} },

	-- Warlock
	{ key = "decay", name = "Decay", edge = "Vines", body = { 0.22, 0.2, 0.12 }, glow = { 0.5, 0.7, 0.2 },
		glowAlpha = 0.4, shadow = { 0.1, 0.08, 0.05 }, flash = { 0.6, 0.7, 0.2 }, pulse = 0.8, bpm = 0.75,
		drip = { tex = "Drip", color = { 0.25, 0.3, 0.1 }, rate = 1 }, effects = {
			{ cell = "Puff", kind = "drift", at = "edge", color = { 0.25, 0.3, 0.1 }, size = { 0.1, 0.18 },
				life = { 3, 5 }, rate = 12 },
			Splats({ 0.3, 0.32, 0.1 }, { 1, 2 }, 0.2),
		} },
	{ key = "fel", name = "Fel runes", edge = "Runes", body = { 0.06, 0.15, 0.04 }, glow = { 0.45, 1, 0.2 },
		glowAlpha = 1, shadow = { 0.03, 0.12, 0 }, flash = { 0.5, 1, 0.2 }, effects = {
			{ cell = "Mote", kind = "rise", at = "edge", color = { 0.45, 1, 0.2 }, add = true,
				size = { 0.015, 0.03 }, life = { 1.5, 3 }, speed = 0.06, rate = 30 },
			{ cell = "Eye", kind = "twinkle", at = "edge", color = { 0.5, 1, 0.25 }, add = true,
				size = { 0.04, 0.07 }, life = { 2, 3 }, rate = 4, from = 0.7 },
		} },
	{ key = "felfire", name = "Fel fire", edge = "Flame", body = { 0.3, 0.38, 0.28 }, glow = { 0.4, 1, 0.15 },
		glowAlpha = 1, shadow = { 0.05, 0.15, 0 }, flash = { 0.5, 1, 0.2 }, effects = {
			{ cell = "Ember", kind = "rise", at = "bottom", color = { 0.45, 1, 0.2 }, add = true,
				size = { 0.015, 0.03 }, life = { 1.5, 3 }, speed = 0.15, rate = 50, hit = { 4, 8 } },
			{ cell = "Dust", kind = "rise", at = "bottom", color = { 0.25, 0.25, 0.2 }, size = { 0.06, 0.1 },
				life = { 2, 3 }, speed = 0.06, rate = 8 },
		} },

	-- Druid
	-- (Balance: sun and moon. Sunlight streaming in from the left, a crescent
	-- moon's cold light on the right, stars between and sunfire motes rising.)
	{ key = "eclipse", name = "Sun and moon", edge = "SunMoon", body = { 1, 0.78, 0.35 },
		glow = { 0.7, 0.8, 1 }, glowAlpha = 0.9, shadow = { 0.08, 0.06, 0.14 }, flash = { 1, 0.9, 0.7 },
		pulse = 0.7, effects = {
			{ cell = "Star", kind = "twinkle", at = "sides", color = { 0.8, 0.85, 1 }, add = true,
				size = { 0.02, 0.045 }, life = { 1, 2 }, rate = 40, hit = { 2, 4 } },
			{ cell = "Mote", kind = "rise", at = "bottom", color = { 1, 0.75, 0.3 }, add = true,
				size = { 0.015, 0.03 }, life = { 2, 3.5 }, speed = 0.06, rate = 25 },
		} },
	-- (Restoration: leaves. A thick border of leaves, more of them drifting down.)
	{ key = "leaves", name = "Falling leaves", edge = "Leaves", body = { 0.32, 0.55, 0.2 },
		shadow = { 0.05, 0.12, 0.03 }, flash = { 0.7, 1, 0.5 }, pulse = 0.7, sway = 0.4, effects = {
			{ cell = "Leaf", kind = "flutter", at = "top", color = { 0.4, 0.65, 0.22 }, size = { 0.03, 0.05 },
				life = { 4, 6 }, speed = 0.06, rate = 18, hit = { 2, 3 } },
			{ cell = "Leaf2", kind = "flutter", at = "top", color = { 0.55, 0.6, 0.2 }, size = { 0.035, 0.055 },
				life = { 4, 6 }, speed = 0.05, rate = 12, hit = { 1, 2 } },
			{ cell = "Leaf2", kind = "flutter", at = "top", color = { 0.7, 0.45, 0.15 }, size = { 0.03, 0.05 },
				life = { 4, 6 }, speed = 0.07, rate = 6, from = 0.6 }, -- (turning brown as you weaken)
		} },

	-- Retail's later classes, and specs Classic doesn't have.
	-- Death Knight
	{ key = "bloodrune", name = "Blood drawn", edge = "Soak", body = { 0.55, 0.02, 0.05 }, glow = { 0.6, 0.05, 0.08 },
		glowAlpha = 0.5, shadow = { 0.25, 0, 0.02 }, flash = { 0.9, 0.05, 0.1 }, pulse = 1.3, bpm = 0.8,
		drip = { tex = "Drip", color = { 0.6, 0.03, 0.06 }, rate = 1.2, up = true }, effects = {
			{ cell = "Rune2", kind = "twinkle", at = "edge", color = { 0.9, 0.1, 0.12 }, add = true,
				size = { 0.04, 0.06 }, life = { 1.5, 2.5 }, hit = { 1, 2 }, rate = 6 },
			{ cell = "Mote", kind = "pull", at = "edge", color = { 0.8, 0.05, 0.08 }, add = true,
				size = { 0.02, 0.035 }, life = { 1.5, 2.5 }, rate = 20 },
		} },
	{ key = "runefrost", name = "Frost runes", edge = "Frost", body = { 0.75, 0.85, 1 }, glow = { 0.45, 0.75, 1 },
		glowAlpha = 0.7, shadow = { 0.04, 0.08, 0.18 }, flash = { 0.6, 0.85, 1 }, bpm = 0.75, effects = {
			{ cell = "Rune1", kind = "twinkle", at = "edge", color = { 0.5, 0.8, 1 }, add = true,
				size = { 0.04, 0.06 }, life = { 1.5, 2.5 }, rate = 10, hit = { 1, 2 } },
			{ cell = "Puff", kind = "drift", at = "edge", color = { 0.7, 0.8, 0.9 }, size = { 0.1, 0.18 },
				life = { 3, 5 }, rate = 12 },
			{ cell = "Shard", kind = "fall", at = "top", color = { 0.85, 0.95, 1 }, size = { 0.02, 0.035 },
				life = { 1, 2 }, speed = 0.45, hit = { 2, 3 } },
		} },
	{ key = "plague", name = "Plague", edge = "Vines", body = { 0.12, 0.16, 0.08 }, glow = { 0.45, 0.9, 0.2 },
		glowAlpha = 0.6, shadow = { 0.04, 0.1, 0.02 }, flash = { 0.5, 1, 0.2 }, pulse = 0.8, effects = {
			{ cell = "Bubble", kind = "bubble", at = "edge", color = { 0.5, 0.9, 0.25 }, size = { 0.03, 0.06 },
				life = { 1.5, 3 }, rate = 25, beat = 0.4 },
			{ cell = "Puff", kind = "drift", at = "edge", color = { 0.25, 0.4, 0.1 }, size = { 0.1, 0.18 },
				life = { 3, 5 }, rate = 10 },
			Splats({ 0.3, 0.5, 0.12 }, { 1, 2 }, 0.1),
		} },
	-- Monk
	{ key = "stagger", name = "Stagger", edge = "Soak", body = { 0.75, 0.45, 0.1 }, glow = { 1, 0.75, 0.3 },
		glowAlpha = 0.6, shadow = { 0.2, 0.1, 0 }, flash = { 1, 0.7, 0.2 }, sway = 1, bpm = 0.8, effects = {
			{ cell = "Bubble", kind = "bubble", at = "bottom", color = { 1, 0.85, 0.45 }, size = { 0.015, 0.03 },
				life = { 1.5, 2.5 }, speed = 0.05, rate = 40 },
			{ cell = "Bruise", kind = "splat", at = "edge", color = { 0.35, 0.15, 0.05 }, size = { 0.08, 0.14 },
				life = { 4, 6 }, hit = { 1, 2 } },
		} },
	{ key = "mist", name = "Jade mist", edge = "Smoke", body = { 0.5, 0.85, 0.7 }, shadow = { 0.03, 0.12, 0.08 },
		flash = { 0.6, 1, 0.8 }, pulse = 0.6, effects = {
			{ cell = "Puff", kind = "drift", at = "edge", color = { 0.55, 0.9, 0.75 }, size = { 0.12, 0.2 },
				life = { 3, 5 }, rate = 15 },
			{ cell = "Petal", kind = "flutter", at = "top", color = { 1, 0.75, 0.85 }, size = { 0.02, 0.035 },
				life = { 4, 6 }, speed = 0.05, rate = 14, hit = { 2, 3 } },
			{ cell = "Mote", kind = "rise", at = "bottom", color = { 0.5, 1, 0.75 }, add = true,
				size = { 0.015, 0.03 }, life = { 2, 3 }, speed = 0.05, rate = 15 },
		} },
	{ key = "chi", name = "Chi", edge = "Wind", body = { 0.45, 0.8, 0.65 }, glow = { 0.4, 1, 0.75 },
		glowAlpha = 0.8, shadow = { 0.02, 0.1, 0.07 }, flash = { 0.5, 1, 0.8 }, bpm = 1.15, effects = {
			{ cell = "Wind", kind = "sweep", at = "across", color = { 0.5, 1, 0.8 }, add = true,
				size = { 0.12, 0.2 }, life = { 0.8, 1.3 }, speed = 0.9, rate = 30, beat = 0.3 },
			{ cell = "Ripple", kind = "ripple", at = "edge", color = { 0.5, 1, 0.8 }, add = true,
				size = { 0.08, 0.14 }, life = { 0.8, 1.2 }, hit = { 1, 2 } },
		} },
	-- Demon Hunter
	{ key = "demon", name = "Demon within", edge = "Flame", body = { 0.2, 0.25, 0.18 }, glow = { 0.45, 1, 0.2 },
		glowAlpha = 1, shadow = { 0.03, 0.12, 0 }, flash = { 0.5, 1, 0.2 }, bpm = 1.2, effects = {
			{ cell = "Eye", kind = "twinkle", at = "edge", color = { 0.5, 1, 0.25 }, add = true,
				size = { 0.05, 0.08 }, life = { 2, 3 }, rate = 6, from = 0.5 },
			Splats({ 0.15, 0.3, 0.08 }, { 2, 3 }, 0.15),
			{ cell = "Ember", kind = "rise", at = "bottom", color = { 0.45, 1, 0.2 }, add = true,
				size = { 0.015, 0.03 }, life = { 1.5, 3 }, speed = 0.15, rate = 30 },
		} },
	{ key = "souls", name = "Soul fragments", edge = "Crack", body = { 0.18, 0.12, 0.22 }, glow = { 0.45, 1, 0.25 },
		glowAlpha = 0.7, shadow = { 0.06, 0.03, 0.1 }, flash = { 0.5, 1, 0.3 }, pulse = 0.8, effects = {
			{ cell = "Mote", kind = "pull", at = "edge", color = { 0.65, 0.4, 1 }, add = true,
				size = { 0.025, 0.045 }, life = { 1.5, 2.5 }, rate = 30, hit = { 2, 4 } },
			{ cell = "Spark", kind = "rise", at = "edge", color = { 0.5, 1, 0.3 }, add = true,
				size = { 0.03, 0.05 }, life = { 0.4, 0.8 }, speed = 0.4, hit = { 3, 5 } },
		} },
	{ key = "devour", name = "Void hunger", edge = "Smoke", body = { 0.14, 0.06, 0.2 }, shadow = { 0.06, 0, 0.12 },
		flash = { 0.6, 0.3, 1 }, pulse = 1.1, effects = {
			{ cell = "Star", kind = "twinkle", at = "edge", color = { 0.7, 0.5, 1 }, add = true,
				size = { 0.02, 0.04 }, life = { 1, 2 }, rate = 30 },
			{ cell = "Mote", kind = "pull", at = "edge", color = { 0.6, 0.35, 1 }, add = true,
				size = { 0.02, 0.04 }, life = { 1.2, 2 }, rate = 35, hit = { 3, 5 } },
			{ cell = "Puff", kind = "drift", at = "edge", color = { 0.1, 0.03, 0.16 }, size = { 0.12, 0.2 },
				life = { 3, 5 }, rate = 12 },
		} },
	-- Evoker
	{ key = "dragonfire", name = "Dragonfire", edge = "Scales", body = { 0.45, 0.1, 0.06 }, glow = { 1, 0.5, 0.12 },
		glowAlpha = 0.8, shadow = { 0.3, 0.06, 0 }, flash = { 1, 0.5, 0.1 }, effects = {
			{ cell = "Ember", kind = "sweep", at = "across", color = { 1, 0.55, 0.15 }, add = true,
				size = { 0.015, 0.03 }, life = { 1.5, 2.5 }, speed = 0.3, rate = 45, hit = { 5, 8 } },
		} },
	{ key = "dream", name = "Emerald dream", edge = "Glow", glow = { 0.45, 1, 0.5 }, glowAlpha = 0.6,
		shadow = { 0.04, 0.14, 0.05 }, flash = { 0.7, 1, 0.6 }, pulse = 0.6, bpm = 0.75, effects = {
			{ cell = "Leaf", kind = "flutter", at = "top", color = { 0.4, 0.9, 0.45 }, add = true,
				size = { 0.03, 0.045 }, life = { 4, 6 }, speed = 0.04, rate = 12 },
			{ cell = "Petal", kind = "flutter", at = "top", color = { 1, 0.9, 0.5 }, add = true,
				size = { 0.02, 0.035 }, life = { 4, 6 }, speed = 0.04, rate = 10, hit = { 2, 3 } },
		} },
	{ key = "sands", name = "Sands of time", edge = "Wind", body = { 0.85, 0.68, 0.38 }, glow = { 1, 0.8, 0.4 },
		glowAlpha = 0.6, shadow = { 0.18, 0.12, 0.03 }, flash = { 1, 0.85, 0.5 }, effects = {
			{ cell = "Sand", kind = "fall", at = "top", color = { 0.95, 0.78, 0.45 }, size = { 0.06, 0.1 },
				life = { 1, 1.6 }, speed = 0.4, rate = 40 },
			{ cell = "Ripple", kind = "ripple", at = "edge", color = { 1, 0.8, 0.4 }, add = true,
				size = { 0.08, 0.12 }, life = { 1, 1.5 }, beat = 0.5, hit = { 1, 2 } }, -- (a clock's tick)
		} },
	-- Specs retail has that Classic doesn't.
	{ key = "bear", name = "Bear hide", edge = "Fur", body = { 0.38, 0.26, 0.16 }, shadow = { 0.12, 0.07, 0.03 },
		flash = { 0.9, 0.3, 0.2 }, pulse = 1.3, bpm = 0.75, drip = BloodDrip(0.6), effects = {
			{ cell = "Claw", kind = "reveal", at = "edge", color = { 0.5, 0.02, 0.03 }, size = { 0.2, 0.3 },
				life = { 3, 5 }, hit = { 1, 1 } },
			{ cell = "CrackBurst", kind = "reveal", at = "edge", color = { 0.25, 0.17, 0.1 }, size = { 0.1, 0.16 },
				life = { 3, 5 }, beat = 0.15 },
		} },
	{ key = "outlaw", name = "Powder and sea", edge = "Smoke", body = { 0.35, 0.4, 0.45 },
		shadow = { 0.05, 0.08, 0.12 }, flash = { 1, 0.75, 0.4 }, drip = { tex = "Drip", color = { 0.45, 0.6, 0.75 },
		rate = 0.8 }, effects = {
			{ cell = "Puff", kind = "drift", at = "edge", color = { 0.55, 0.55, 0.55 }, size = { 0.08, 0.14 },
				life = { 2, 3 }, hit = { 1, 2 } }, -- (pistol smoke)
			{ cell = "Spark", kind = "rise", at = "edge", color = { 1, 0.75, 0.35 }, add = true,
				size = { 0.03, 0.05 }, life = { 0.3, 0.6 }, speed = 0.3, hit = { 2, 3 } },
			Splats(BLOOD, { 1, 2 }, 0.1),
		} },
}

ns.LOW_HEALTH_THEME = {} -- (by key)
for _, theme in ipairs(ns.LOW_HEALTH_THEMES) do
	ns.LOW_HEALTH_THEME[theme.key] = theme
end

-- Auto: by class, then the talent tree with the most points (in the game's
-- order of trees). No points yet (under level 10): the class's own, first.
ns.LOW_HEALTH_CLASS_THEMES = {
	WARRIOR = { "wounds", "rage", "shield", none = "blood" },
	PALADIN = { "holylight", "holyshield", "judgement" },
	HUNTER = { "claws", "lonewolf", "thorns" },
	ROGUE = { "poison", "bruise", "shadow" },
	PRIEST = { "ward", "feathers", "void" },
	SHAMAN = { "storm", "gale", "water" },
	MAGE = { "arcane", "fire", "frost" },
	WARLOCK = { "decay", "fel", "felfire" },
	DRUID = { "eclipse", "claws", "leaves" },
	-- (Later classes, on clients that have them.)
	DEATHKNIGHT = { "bloodrune", "runefrost", "plague" },
	MONK = { "stagger", "mist", "chi" },
	DEMONHUNTER = { "demon", "souls", "devour" },
	EVOKER = { "dragonfire", "dream", "sands" },
}
-- Clients with specs, where they differ from the trees: druids have four
-- (Guardian third), and rogues' second is Outlaw (once Combat).
ns.LOW_HEALTH_SPEC_THEMES = {
	DRUID = { "eclipse", "claws", "bear", "leaves" },
	ROGUE = { "poison", "outlaw", "shadow" },
}

-- The page's theme menu: a submenu for each class (its token, for its
-- colour, and name), each spec in it with its theme. (Retail: marks specs
-- and classes only retail has.)
ns.LOW_HEALTH_MENU = {
	{ "WARRIOR", "Warrior", { { "Arms", "wounds" }, { "Fury", "rage" }, { "Protection", "shield" },
		{ "No talents yet", "blood" } } },
	{ "PALADIN", "Paladin", { { "Holy", "holylight" }, { "Protection", "holyshield" },
		{ "Retribution", "judgement" } } },
	{ "HUNTER", "Hunter", { { "Beast Mastery", "claws" }, { "Marksmanship", "lonewolf" },
		{ "Survival", "thorns" } } },
	{ "ROGUE", "Rogue", { { "Assassination", "poison" }, { "Combat", "bruise" }, { "Outlaw", "outlaw", retail = true },
		{ "Subtlety", "shadow" } } },
	{ "PRIEST", "Priest", { { "Discipline", "ward" }, { "Holy", "feathers" }, { "Shadow", "void" } } },
	{ "SHAMAN", "Shaman", { { "Elemental", "storm" }, { "Enhancement", "gale" }, { "Restoration", "water" } } },
	{ "MAGE", "Mage", { { "Arcane", "arcane" }, { "Fire", "fire" }, { "Frost", "frost" } } },
	{ "WARLOCK", "Warlock", { { "Affliction", "decay" }, { "Demonology", "fel" }, { "Destruction", "felfire" } } },
	{ "DRUID", "Druid", { { "Balance", "eclipse" }, { "Feral", "claws" }, { "Guardian", "bear", retail = true },
		{ "Restoration", "leaves" } } },
	{ "DEATHKNIGHT", "Death Knight", retail = true, { { "Blood", "bloodrune" }, { "Frost", "runefrost" },
		{ "Unholy", "plague" } } },
	{ "MONK", "Monk", retail = true, { { "Brewmaster", "stagger" }, { "Mistweaver", "mist" },
		{ "Windwalker", "chi" } } },
	{ "DEMONHUNTER", "Demon Hunter", retail = true, { { "Havoc", "demon" }, { "Vengeance", "souls" },
		{ "Devourer", "devour" } } },
	{ "EVOKER", "Evoker", retail = true, { { "Devastation", "dragonfire" }, { "Preservation", "dream" },
		{ "Augmentation", "sands" } } },
}

-- Who each is for (from the menu: "Arms Warrior", or more than one).
for _, class in ipairs(ns.LOW_HEALTH_MENU) do
	for _, spec in ipairs(class[3]) do
		local theme = ns.LOW_HEALTH_THEME[spec[2]]
		local who = spec[1] .. " " .. class[2]
		theme.who = theme.who and theme.who .. ", " .. who or who
	end
end
