-- Low-health edge themes (LowHealth.lua draws them), one for each class's
-- talent trees, and which the Auto choice picks. The art is white or grey
-- (Media/make_lowhealth.py), tinted here. Mostly the soft edges, their
-- colours, the heartbeat and the flash; a few have sparks.
--
-- A theme:
--   name     shown in the menu
--   edge     the edge material (Textures/LowHealth/<edge>.tga), or nil for none
--   body     its colour (nil: its glow only)
--   glow     its glow's colour, added on top (nil: none); glowAlpha its strength
--   shadow   the dark edges' colour, at full Shadow tint
--   flash    a big hit's flash colour (and the colour grade's tinge)
--   pulse, bpm  the heartbeat's throb and speed, times the page's
--   sway     the art rocks slowly, sloshing (1 about a hand's width), or nil
--   look     the theme's own defaults for the Style page's settings ({ lowHealthDark = 0.6, ... }):
--            a setting the player hasn't changed takes the theme's; one they have stays theirs
--   sparks   the few sprites left (LowHealth.lua draws them), each:
--     tex    its texture: "Bolt" (lightning), "Star", "Mote" or "Gas"
--     kind   "flicker" (on and off, fading: lightning), "twinkle" (fading in
--            and out), "rise" (floating up, swaying) or "drift" (billowing in,
--            growing)
--     flat   drawn as it is, not as light (gas over art: it shouldn't glow)
--   (Every theme also gets a haze of gas: Haze, below.)
--     at     where it starts: "top", "bottom", "sides", or nil for any edge
--     color, size { min, max } (shares of the screen's height), life { min,
--     max } (seconds), speed (rise: screen heights a second), rate (a minute,
--     at full), hit { min, max } (on a big hit)

local _, ns = ...

local BLOOD = { 0.85, 0.05, 0.06 }
local DARK_RED = { 0.35, 0, 0 }

ns.LOW_HEALTH_THEMES = {
	-- The default, and warriors with no talents yet.
	{ key = "blood", name = "Blood", edge = "Soak", body = BLOOD, glow = { 0.5, 0.05, 0.05 }, glowAlpha = 0.5,
		shadow = DARK_RED, flash = { 1, 0, 0 } },

	-- Warrior
	{ key = "wounds", name = "Battle wounds", edge = "Soak", body = BLOOD, glow = { 0.5, 0.05, 0.05 },
		glowAlpha = 0.5, shadow = DARK_RED, flash = { 1, 0, 0 } },
	{ key = "rage", name = "Rage", edge = "Soak", body = { 1, 0.12, 0.05 }, glow = { 1, 0.35, 0.1 },
		glowAlpha = 0.8, shadow = { 0.45, 0.05, 0 }, flash = { 1, 0.3, 0 }, pulse = 1.6, bpm = 1.25 },
	{ key = "shield", name = "Battered shield", edge = "Smoke", body = { 0.3, 0.31, 0.34 },
		shadow = { 0.1, 0.1, 0.12 }, flash = { 1, 0.8, 0.5 } },

	-- Paladin
	{ key = "holylight", name = "Fading light", edge = "Glow", glow = { 1, 0.8, 0.35 }, glowAlpha = 0.7,
		shadow = { 0.25, 0.18, 0.05 }, flash = { 1, 0.9, 0.5 }, pulse = 0.7, sparks = {
			{ tex = "Mote", kind = "rise", color = { 1, 0.85, 0.4 }, size = { 0.02, 0.04 },
				life = { 2, 4 }, speed = 0.05, rate = 40, hit = { 2, 3 } },
		} },
	{ key = "holyshield", name = "Holy shield", edge = "Glow", glow = { 1, 0.88, 0.5 }, glowAlpha = 0.55,
		shadow = { 0.2, 0.15, 0.03 }, flash = { 1, 0.95, 0.6 }, sparks = {
			{ tex = "Mote", kind = "rise", color = { 1, 0.9, 0.5 }, size = { 0.015, 0.03 },
				life = { 1.5, 3 }, speed = 0.05, rate = 25, hit = { 3, 5 } },
		} },
	{ key = "judgement", name = "Judgement", edge = "Glow", glow = { 1, 0.72, 0.25 },
		glowAlpha = 0.6, shadow = { 0.35, 0.15, 0 }, flash = { 1, 0.8, 0.3 }, sparks = {
			{ tex = "Mote", kind = "rise", at = "bottom", color = { 1, 0.8, 0.3 }, size = { 0.015, 0.03 },
				life = { 1.5, 3 }, speed = 0.1, rate = 35, hit = { 4, 6 } },
		} },

	-- Hunter
	{ key = "claws", name = "Claws", edge = "Soak", body = BLOOD, glow = { 0.5, 0.05, 0.05 }, glowAlpha = 0.4,
		shadow = DARK_RED, flash = { 1, 0, 0 }, bpm = 1.2 },
	{ key = "lonewolf", name = "Lone wolf", edge = "Smoke", body = { 0.45, 0.5, 0.58 },
		shadow = { 0.05, 0.07, 0.1 }, flash = { 0.85, 0.9, 1 } },
	{ key = "thorns", name = "Thorns", edge = "Soak", body = { 0.35, 0.12, 0.05 }, shadow = { 0.1, 0.1, 0.02 },
		flash = { 0.8, 0.1, 0 } },

	-- Rogue
	{ key = "poison", name = "Poison", edge = "Soak", body = { 0.15, 0.4, 0.1 }, glow = { 0.4, 1, 0.2 },
		glowAlpha = 0.4, shadow = { 0.05, 0.18, 0.02 }, flash = { 0.5, 1, 0.2 }, pulse = 0.8, bpm = 0.8, sparks = {
			{ tex = "Gas", kind = "drift", flat = true, color = { 0.35, 0.7, 0.15 }, size = { 0.35, 0.6 },
				life = { 3, 5 }, rate = 45, hit = { 3, 4 } },
		} },
	{ key = "bruise", name = "Brawl", edge = "Soak", body = { 0.6, 0.05, 0.1 }, glow = { 0.4, 0.05, 0.1 },
		glowAlpha = 0.4, shadow = { 0.2, 0, 0.12 }, flash = { 0.8, 0.1, 0.4 } },
	{ key = "shadow", name = "Shadow", edge = "Smoke", body = { 0.12, 0.1, 0.14 }, shadow = { 0, 0, 0 },
		flash = { 0.3, 0.2, 0.4 }, pulse = 0.7 },

	-- Priest
	{ key = "ward", name = "Failing ward", edge = "Glow", glow = { 0.8, 0.9, 1 },
		glowAlpha = 0.55, shadow = { 0.1, 0.12, 0.18 }, flash = { 0.9, 0.95, 1 }, sparks = {
			{ tex = "Mote", kind = "rise", color = { 0.85, 0.92, 1 }, size = { 0.015, 0.03 },
				life = { 1.5, 3 }, speed = 0.05, rate = 25, hit = { 2, 4 } },
		} },
	{ key = "feathers", name = "Feathers", edge = "Glow", glow = { 1, 0.97, 0.88 }, glowAlpha = 0.6,
		shadow = { 0.2, 0.2, 0.22 }, flash = { 1, 1, 0.9 }, pulse = 0.6, sparks = {
			{ tex = "Mote", kind = "rise", color = { 1, 0.97, 0.88 }, size = { 0.015, 0.035 },
				life = { 2, 4 }, speed = 0.04, rate = 30, hit = { 2, 3 } },
		} },
	{ key = "void", name = "Void", edge = "Smoke", body = { 0.16, 0.06, 0.24 },
		shadow = { 0.1, 0, 0.18 }, flash = { 0.6, 0.2, 1 }, pulse = 1.2 },

	-- Shaman
	{ key = "storm", name = "Storm", edge = "Smoke", body = { 0.18, 0.2, 0.26 }, shadow = { 0.04, 0.05, 0.1 },
		flash = { 0.7, 0.8, 1 }, sparks = {
			{ tex = "Bolt", kind = "flicker", at = "top", color = { 0.7, 0.8, 1 }, size = { 0.2, 0.3 }, life = { 0.3, 0.5 },
				rate = 4, hit = { 1, 1 } },
		} },
	{ key = "gale", name = "Windfury", edge = "Smoke", body = { 0.42, 0.5, 0.62 },
		shadow = { 0.03, 0.06, 0.12 }, flash = { 0.6, 0.8, 1 }, bpm = 1.1,
		sparks = {
			{ tex = "Bolt", kind = "flicker", at = "top", color = { 0.65, 0.8, 1 }, size = { 0.12, 0.2 }, life = { 0.3, 0.5 },
				hit = { 1, 1 } },
		} },
	{ key = "water", name = "Tides", edge = "Soak", body = { 0.15, 0.35, 0.6 }, glow = { 0.5, 0.8, 1 },
		glowAlpha = 0.8, shadow = { 0, 0.06, 0.15 }, flash = { 0.5, 0.8, 1 }, pulse = 0.8, bpm = 0.8, sparks = {
			{ tex = "Mote", kind = "rise", at = "bottom", color = { 0.5, 0.8, 1 }, size = { 0.015, 0.03 },
				life = { 2, 3 }, speed = 0.06, rate = 30, hit = { 3, 5 } },
		} },

	-- Mage
	{ key = "arcane", name = "Arcane", edge = "Glow", glow = { 0.7, 0.45, 1 },
		glowAlpha = 0.55, shadow = { 0.12, 0.03, 0.2 }, flash = { 0.8, 0.5, 1 }, sparks = {
			{ tex = "Star", kind = "twinkle", color = { 0.85, 0.65, 1 }, size = { 0.03, 0.06 }, life = { 0.8, 1.5 },
				rate = 40, hit = { 3, 5 } },
		} },
	{ key = "fire", name = "Fire", edge = "Glow", glow = { 1, 0.45, 0.08 },
		glowAlpha = 0.6, shadow = { 0.3, 0.08, 0 }, flash = { 1, 0.5, 0.1 }, sparks = {
			{ tex = "Mote", kind = "rise", at = "bottom", color = { 1, 0.55, 0.15 }, size = { 0.015, 0.035 },
				life = { 1.5, 3 }, speed = 0.12, rate = 70, hit = { 5, 8 } },
			{ tex = "Mote", kind = "rise", color = { 1, 0.75, 0.3 }, size = { 0.01, 0.02 },
				life = { 1.5, 2.5 }, speed = 0.06, rate = 30 },
		} },
	{ key = "frost", name = "Frost", edge = "Smoke", body = { 0.72, 0.82, 0.92 },
		shadow = { 0.05, 0.1, 0.2 }, flash = { 0.7, 0.9, 1 }, bpm = 0.7, sparks = {
			{ tex = "Mote", kind = "rise", color = { 0.8, 0.92, 1 }, size = { 0.012, 0.028 },
				life = { 2, 3.5 }, speed = 0.03, rate = 30, hit = { 2, 4 } },
		} },

	-- Warlock
	{ key = "decay", name = "Decay", edge = "Smoke", body = { 0.22, 0.22, 0.1 },
		shadow = { 0.1, 0.08, 0.05 }, flash = { 0.6, 0.7, 0.2 }, pulse = 0.8, bpm = 0.75 },
	{ key = "fel", name = "Fel runes", edge = "Glow", glow = { 0.45, 1, 0.2 },
		glowAlpha = 0.5, shadow = { 0.03, 0.12, 0 }, flash = { 0.5, 1, 0.2 }, sparks = {
			{ tex = "Mote", kind = "rise", color = { 0.45, 1, 0.2 }, size = { 0.015, 0.03 },
				life = { 1.5, 3 }, speed = 0.05, rate = 30, hit = { 2, 4 } },
		} },
	-- (Destruction: a shadow glow, fire motes rising through it.)
	{ key = "felfire", name = "Shadowflame", edge = "Glow", glow = { 0.55, 0.2, 0.85 },
		glowAlpha = 0.55, shadow = { 0.12, 0.02, 0.18 }, flash = { 1, 0.45, 0.15 }, sparks = {
			{ tex = "Mote", kind = "rise", at = "bottom", color = { 1, 0.5, 0.12 }, size = { 0.015, 0.035 },
				life = { 1.5, 3 }, speed = 0.12, rate = 40, hit = { 3, 5 } },
			{ tex = "Mote", kind = "rise", color = { 1, 0.65, 0.2 }, size = { 0.01, 0.025 },
				life = { 2, 3.5 }, speed = 0.05, rate = 30, hit = { 2, 4 } },
		} },

	-- Druid
	{ key = "eclipse", name = "Sun and moon", edge = "Glow", glow = { 0.78, 0.75, 1 }, glowAlpha = 0.55,
		shadow = { 0.08, 0.06, 0.14 }, flash = { 1, 0.85, 0.5 }, pulse = 0.7, sparks = {
			{ tex = "Star", kind = "twinkle", at = "sides", color = { 0.8, 0.85, 1 }, size = { 0.02, 0.045 },
				life = { 1, 2 }, rate = 40, hit = { 2, 4 } },
			{ tex = "Mote", kind = "rise", at = "bottom", color = { 1, 0.75, 0.3 }, size = { 0.015, 0.03 },
				life = { 2, 3.5 }, speed = 0.06, rate = 25 },
		} },
	{ key = "leaves", name = "Falling leaves", edge = "Glow", glow = { 0.5, 0.8, 0.3 }, glowAlpha = 0.4,
		shadow = { 0.05, 0.12, 0.03 }, flash = { 0.7, 1, 0.5 }, pulse = 0.7 },

	-- Retail's later classes, and specs Classic doesn't have.
	-- Death Knight
	{ key = "bloodrune", name = "Blood drawn", edge = "Soak", body = { 0.55, 0.02, 0.05 }, glow = { 0.6, 0.05, 0.08 },
		glowAlpha = 0.5, shadow = { 0.25, 0, 0.02 }, flash = { 0.9, 0.05, 0.1 }, pulse = 1.3, bpm = 0.8 },
	{ key = "runefrost", name = "Frost runes", edge = "Glow", glow = { 0.45, 0.75, 1 },
		glowAlpha = 0.5, shadow = { 0.04, 0.08, 0.18 }, flash = { 0.6, 0.85, 1 }, bpm = 0.75 },
	{ key = "plague", name = "Plague", edge = "Smoke", body = { 0.18, 0.26, 0.1 },
		shadow = { 0.04, 0.1, 0.02 }, flash = { 0.5, 1, 0.2 }, pulse = 0.8 },
	-- Monk
	{ key = "stagger", name = "Stagger", edge = "Soak", body = { 0.75, 0.45, 0.1 }, glow = { 1, 0.75, 0.3 },
		glowAlpha = 0.6, shadow = { 0.2, 0.1, 0 }, flash = { 1, 0.7, 0.2 }, sway = 1, bpm = 0.8 },
	{ key = "mist", name = "Jade mist", edge = "Smoke", body = { 0.5, 0.85, 0.7 }, shadow = { 0.03, 0.12, 0.08 },
		flash = { 0.6, 1, 0.8 }, pulse = 0.6 },
	{ key = "chi", name = "Chi", edge = "Glow", glow = { 0.4, 1, 0.75 },
		glowAlpha = 0.45, shadow = { 0.02, 0.1, 0.07 }, flash = { 0.5, 1, 0.8 }, bpm = 1.15 },
	-- Demon Hunter
	{ key = "demon", name = "Demon within", edge = "Glow", glow = { 0.45, 1, 0.2 },
		glowAlpha = 0.5, shadow = { 0.03, 0.12, 0 }, flash = { 0.5, 1, 0.2 }, bpm = 1.2 },
	{ key = "souls", name = "Soul fragments", edge = "Smoke", body = { 0.18, 0.12, 0.22 },
		shadow = { 0.06, 0.03, 0.1 }, flash = { 0.5, 1, 0.3 }, pulse = 0.8 },
	{ key = "devour", name = "Void hunger", edge = "Smoke", body = { 0.14, 0.06, 0.2 }, shadow = { 0.06, 0, 0.12 },
		flash = { 0.6, 0.3, 1 }, pulse = 1.1, sparks = {
			{ tex = "Star", kind = "twinkle", color = { 0.7, 0.5, 1 }, size = { 0.02, 0.04 }, life = { 1, 2 }, rate = 30 },
		} },
	-- Evoker
	{ key = "dragonfire", name = "Dragonfire", edge = "Glow", glow = { 1, 0.32, 0.08 },
		glowAlpha = 0.6, shadow = { 0.3, 0.04, 0 }, flash = { 1, 0.5, 0.1 } },
	{ key = "dream", name = "Emerald dream", edge = "Glow", glow = { 0.45, 1, 0.5 }, glowAlpha = 0.6,
		shadow = { 0.04, 0.14, 0.05 }, flash = { 0.7, 1, 0.6 }, pulse = 0.6, bpm = 0.75 },
	{ key = "sands", name = "Sands of time", edge = "Glow", glow = { 1, 0.8, 0.4 },
		glowAlpha = 0.45, shadow = { 0.18, 0.12, 0.03 }, flash = { 1, 0.85, 0.5 } },
	-- Specs retail has that Classic doesn't.
	{ key = "bear", name = "Bear hide", edge = "Fur", body = { 0.38, 0.26, 0.16 }, shadow = { 0.12, 0.07, 0.03 },
		flash = { 0.9, 0.3, 0.2 }, pulse = 1.3, bpm = 0.75 },
	{ key = "outlaw", name = "Powder and sea", edge = "Smoke", body = { 0.35, 0.4, 0.45 },
		shadow = { 0.05, 0.08, 0.12 }, flash = { 1, 0.75, 0.4 } },
}

-- Every theme gets a haze: soft gas drifting over its edges, like its glow but
-- uneven and moving, so the edges feel alive. In the art's colour, drawn
-- flat; with no art colour (glow themes), the glow's, as light. A theme with
-- gas of its own (Poison) keeps that.
local HAZE_LIGHT = 0.5

local function Haze(theme)
	for _, info in ipairs(theme.sparks or {}) do
		if info.kind == "drift" then return end
	end
	local color, add = theme.body, false
	if not color and theme.glow then
		-- (as light it adds up where puffs overlap: dimmer, so it stays soft)
		local glow = theme.glow
		color, add = { glow[1] * HAZE_LIGHT, glow[2] * HAZE_LIGHT, glow[3] * HAZE_LIGHT }, true
	end
	if not color then return end
	theme.sparks = theme.sparks or {}
	table.insert(theme.sparks, { tex = "Gas", kind = "drift", haze = true, flat = not add, color = color,
		size = { 0.35, 0.6 }, life = { 3, 5 }, rate = 45, hit = { 3, 4 } })
end

-- Each theme's own defaults for the Style page (the look field above), as set
-- with the dev copy's DEV SET DEFAULT.
local LOOKS = {
	wounds = { lowHealthBloodReach = 0, lowHealthGameAlpha = 0.75 },
	rage = { lowHealthBloodAlpha = 0.1, lowHealthBloodReach = 0.2, lowHealthGameAlpha = 0.7 },
	holylight = { lowHealthGameReach = 0.4, lowHealthGameAlpha = 0.15 },
	judgement = { lowHealthGameReach = 0.1 },
	claws = { lowHealthBloodReach = 0.2, lowHealthGamePattern = 6225366, lowHealthGameAlpha = 0.9 },
	lonewolf = { lowHealthBloodAlpha = 0.65, lowHealthGameAlpha = 0.65 },
	thorns = { lowHealthBloodReach = 0.25 },
	poison = { lowHealthBloodReach = 0.05, lowHealthGameReach = 0.85, lowHealthGameAlpha = 0.81 },
	bruise = { lowHealthBloodAlpha = 0.65, lowHealthBloodReach = 0.05 },
	shadow = { lowHealthGameReach = 1 },
	ward = { lowHealthBloodAlpha = 0.79, lowHealthGameReach = 0.2, lowHealthGameAlpha = 0.31 },
	feathers = { lowHealthGameReach = 0.35 },
	void = { lowHealthBloodAlpha = 0.91, lowHealthBloodReach = 0.9, lowHealthGameReach = 0.9,
		lowHealthGameAlpha = 0.95 },
	storm = { lowHealthBloodAlpha = 1, lowHealthGameReach = 0.05, lowHealthGameMask = 1802909,
		lowHealthGameColors = "theme", lowHealthGameAlpha = 0.25 },
	gale = { lowHealthBloodAlpha = 0.85, lowHealthBloodReach = 0.4, lowHealthGameMask = 6225363,
		lowHealthGameAlpha = 1, lowHealthSparks = false },
	water = { lowHealthBloodAlpha = 0.35, lowHealthBloodReach = 0, lowHealthGameAlpha = 0.85 },
	arcane = { lowHealthBloodReach = 0.4 },
	fire = { lowHealthGameReach = 0.05 },
	frost = { lowHealthBloodAlpha = 0.23 },
	decay = { lowHealthBloodReach = 0 },
	felfire = { lowHealthBloodAlpha = 0.76, lowHealthBloodReach = 0.45, lowHealthGameReach = 0,
		lowHealthGameAlpha = 0.81 },
	eclipse = { lowHealthBloodAlpha = 0.61, lowHealthGameColors = "own", lowHealthGameAlpha = 0.71 },
	leaves = { lowHealthBloodAlpha = 0.12, lowHealthGameReach = 0.8, lowHealthGameAlpha = 0.91 },
	bloodrune = { lowHealthBloodAlpha = 0.21, lowHealthBloodReach = 0.05, lowHealthGamePattern = 4876486,
		lowHealthGameColors = "theme" },
	runefrost = { lowHealthGameReach = 0.1 },
	plague = { lowHealthBloodReach = 0.75, lowHealthGameReach = 0.2 },
	stagger = { lowHealthBloodAlpha = 0.29, lowHealthGameAlpha = 0.69 },
	mist = { lowHealthBloodAlpha = 0.48, lowHealthGameAlpha = 0.38 },
	bear = { lowHealthBloodAlpha = 0.23, lowHealthBloodReach = 0.3 },
	outlaw = { lowHealthBloodAlpha = 0.94, lowHealthGameAlpha = 0.31 },
}

ns.LOW_HEALTH_THEME = {} -- (by key)
for _, theme in ipairs(ns.LOW_HEALTH_THEMES) do
	theme.look = theme.look or LOOKS[theme.key]
	Haze(theme)
	ns.LOW_HEALTH_THEME[theme.key] = theme
end

-- Blizzard art: the game's full-screen effects (by file number), a layer of
-- their own over our art (or alone), cut to an edge by a mask and closing in
-- with it. Each pattern players can pick, with how it's drawn unless the
-- page says otherwise:
--   mask   the mask cutting it to an edge (nil: it's an edge already)
--   own    in its own colors (else greyed and tinted in the theme's)
--   tiles  times across the screen; paint  drawn over (else added on, as light)
-- Retail has them all; Classic only the first few (the rest are left out of
-- the page there, and a theme's pick it hasn't falls back to the red edge).
local SOFT, ROUND, RAGGED, FROSTY, WISPY, WAVY = 1802909, 2202396, 6225363, 2199927, 1305138, 5857689
ns.LOW_HEALTH_BLIZZ_EDGE = 131140 -- (the game's own low-health edge: Classic has it)
ns.LOW_HEALTH_BLIZZ_PATTERNS = {
	{ 131140, "Red soft edge", own = true },
	{ 985799, "Grey fog", mask = WISPY },
	{ 1273707, "White crackling veins", mask = WISPY },
	{ 1305137, "Olive blotchy cells", mask = WISPY, own = true },
	{ 4383351, "Rays in from the edges" },
	{ 2395778, "Amber flame wisps", mask = SOFT, own = true },
	{ 4876486, "Lava cracks", mask = SOFT, own = true },
	{ 2140999, "Embers and ash flakes", own = true },
	{ 4237662, "Gold marble with sparkles", mask = ROUND, own = true },
	{ 5201310, "Orange wavy lines with specks", mask = SOFT, own = true },
	{ 5636771, "Pale gold wavy stripes", mask = SOFT, own = true },
	{ 2396780, "Gold water ripples", mask = SOFT, own = true },
	{ 3522953, "Blue lightning veins", mask = SOFT, own = true },
	{ 5332774, "Teal with white waves", mask = WAVY, own = true },
	{ 4417751, "Teal wavy lines", mask = SOFT, own = true },
	{ 2735672, "Mint green water ripples", mask = SOFT, own = true },
	{ 2202483, "Pale blue blurry blobs", mask = FROSTY, own = true },
	{ 2199926, "Grey ripples", mask = SOFT },
	{ 6214876, "Thin lilac waves on dark", mask = SOFT },
	{ 4237661, "Thin white curves", mask = ROUND },
	{ 6225095, "White petals in clumps", mask = SOFT, tiles = 2 },
	{ 6907568, "Grey clouds, cyan and lilac tints", mask = ROUND },
	{ 4541185, "Grey wavy wisps", mask = SOFT },
	{ 6996935, "Grey flowing smoke", mask = SOFT },
	{ 3509149, "Grey sideways streaks", mask = SOFT },
	{ 5680179, "Green with yellow glows", mask = SOFT, own = true },
	{ 5198840, "Green speckles", mask = SOFT, own = true },
	{ 6225364, "Dark green moss", mask = RAGGED, own = true },
	{ 6225366, "Thorny green vines", mask = RAGGED, own = true, paint = true },
	{ 4630641, "Brown dirt", mask = RAGGED, own = true, paint = true },
	{ 4741753, "Purple and blue swirl", mask = SOFT, own = true },
	{ 5857669, "Purple swirl with stars", mask = SOFT, own = true },
	{ 5857660, "Dark purple swirl", mask = SOFT, own = true },
	{ 4741750, "Dark blue night sky, faint stars", mask = ROUND, own = true },
}
-- The masks players can pick (Theme's pick and None are the page's).
ns.LOW_HEALTH_BLIZZ_MASKS = {
	{ SOFT, "Soft frame" }, { ROUND, "Soft rounded frame" }, { WAVY, "Soft frame, wavy bottom" },
	{ RAGGED, "Ragged frame" }, { FROSTY, "Frosty ragged frame" }, { WISPY, "Wispy frame" },
}
ns.LOW_HEALTH_BLIZZ_PATTERN = {} -- (by file number)
for _, pattern in ipairs(ns.LOW_HEALTH_BLIZZ_PATTERNS) do
	ns.LOW_HEALTH_BLIZZ_PATTERN[pattern[1]] = pattern
end
-- Each theme's pick: a pattern, or { pattern, own = false } to tint one that
-- is in its own colors otherwise. (Game art themes: none, their art is it.)
local THEIRS = {
	blood = 131140, wounds = 131140, claws = 131140, bloodrune = 131140,
	bruise = { 131140, own = false },
	rage = 2395778, dragonfire = 2395778,
	shield = 985799,
	holylight = 4237662, holyshield = 4383351, judgement = 5201310,
	lonewolf = 4541185, thorns = 6225366,
	poison = 5680179, shadow = 6996935,
	ward = 4237661, feathers = 6225095, void = 4741753,
	storm = 3522953, gale = 6214876, water = 5332774,
	arcane = 5857669, fire = 4876486, frost = 2202483,
	decay = 1305137, fel = 1273707, felfire = 2140999,
	eclipse = 4741750, leaves = 6225364,
	runefrost = 4237661, plague = 5198840,
	stagger = 2396780, mist = 6907568, chi = 4417751,
	demon = 1273707, souls = 3509149, devour = 5857660,
	dream = 2735672, sands = 5636771,
	bear = 4630641, outlaw = 2199926,
}
for key, pick in pairs(THEIRS) do
	ns.LOW_HEALTH_THEME[key].theirs = type(pick) == "table" and pick or { pick }
end

-- Game art (the menu's Game art section, not Auto's): the game's own
-- low-health edge in place of ours, greyed and tinted by body and glow, with
-- a wave of it creeping in on each beat. One for each colour. Not in the
-- gallery: the art is the game's. No haze, so it's the game's look.
local function Game(key, name, body, glow, shadow, flash)
	return { key = key, name = name, game = true, body = body, glow = glow, glowAlpha = 0.6, shadow = shadow,
		flash = flash }
end
ns.LOW_HEALTH_GAME_THEMES = {
	Game("game_low", "Low health", BLOOD, { 0.6, 0.05, 0.05 }, DARK_RED, { 1, 0, 0 }),
	Game("game_fire", "Fire", { 1, 0.4, 0.08 }, { 1, 0.5, 0.1 }, { 0.3, 0.08, 0 }, { 1, 0.5, 0.1 }),
	Game("game_gold", "Gold", { 1, 0.8, 0.35 }, { 1, 0.85, 0.45 }, { 0.25, 0.18, 0.05 }, { 1, 0.9, 0.5 }),
	Game("game_light", "Light", { 1, 0.95, 0.8 }, { 1, 1, 0.9 }, { 0.2, 0.2, 0.22 }, { 1, 1, 0.9 }),
	Game("game_nature", "Nature", { 0.4, 0.8, 0.3 }, { 0.55, 0.9, 0.4 }, { 0.05, 0.12, 0.03 }, { 0.6, 1, 0.4 }),
	Game("game_fel", "Fel", { 0.35, 0.9, 0.15 }, { 0.45, 1, 0.2 }, { 0.05, 0.15, 0.02 }, { 0.5, 1, 0.2 }),
	Game("game_jade", "Jade", { 0.3, 0.9, 0.65 }, { 0.45, 1, 0.75 }, { 0.03, 0.12, 0.08 }, { 0.5, 1, 0.8 }),
	Game("game_frost", "Frost", { 0.45, 0.75, 1 }, { 0.6, 0.85, 1 }, { 0, 0.06, 0.15 }, { 0.6, 0.85, 1 }),
	Game("game_storm", "Storm", { 0.3, 0.5, 1 }, { 0.5, 0.7, 1 }, { 0.03, 0.06, 0.12 }, { 0.6, 0.8, 1 }),
	Game("game_arcane", "Arcane", { 0.7, 0.45, 1 }, { 0.8, 0.6, 1 }, { 0.12, 0.03, 0.2 }, { 0.8, 0.5, 1 }),
	Game("game_shadow", "Shadow", { 0.5, 0.2, 0.8 }, { 0.6, 0.3, 1 }, { 0.1, 0, 0.18 }, { 0.6, 0.2, 1 }),
}
for _, theme in ipairs(ns.LOW_HEALTH_GAME_THEMES) do
	ns.LOW_HEALTH_THEME[theme.key] = theme
end

-- Auto, Game art: as Auto below, each spec a colour.
ns.LOW_HEALTH_GAME_CLASS_THEMES = {
	WARRIOR = { "game_low", "game_fire", "game_light", none = "game_low" },
	PALADIN = { "game_light", "game_gold", "game_gold" },
	HUNTER = { "game_nature", "game_gold", "game_fire" },
	ROGUE = { "game_fel", "game_low", "game_shadow" },
	PRIEST = { "game_light", "game_gold", "game_shadow" },
	SHAMAN = { "game_storm", "game_storm", "game_frost" },
	MAGE = { "game_arcane", "game_fire", "game_frost" },
	WARLOCK = { "game_shadow", "game_fel", "game_fire" },
	DRUID = { "game_arcane", "game_low", "game_nature" },
	DEATHKNIGHT = { "game_low", "game_frost", "game_nature" },
	MONK = { "game_gold", "game_jade", "game_jade" },
	DEMONHUNTER = { "game_fel", "game_shadow", "game_shadow" },
	EVOKER = { "game_fire", "game_nature", "game_gold" },
}
ns.LOW_HEALTH_GAME_SPEC_THEMES = {
	DRUID = { "game_arcane", "game_low", "game_fire", "game_nature" },
	ROGUE = { "game_fel", "game_low", "game_shadow" },
}

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
