-- Vitals Vision, low-health edges: as your health drops, dark edges creep in round the
-- screen, like the death screen's vignette, with a theme's art soaking in
-- past them (blood, smoke, a glow: Media/make_lowhealth.py), the world's
-- colour draining if ticked, a heartbeat that quickens as you weaken and a
-- flash on big hits. So you can tell how you're doing without the portrait. Themes are in
-- LowHealthThemes.lua: one for each class's talent trees, picked by Auto.
-- Its own overlay, under the UI like the death screen's; the death screen
-- takes over as you die. This is Vitals Vision: its page is at the bottom.

local ADDON_NAME, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.lowHealth = false         -- Vitals Vision at all (its page's switch)
DEFAULTS.lowHealthEdges = true     -- the screen's edges closing in (the health bars are below)
DEFAULTS.lowHealthOnlyCine = false -- ...only while CineMode is on
DEFAULTS.lowHealthTheme = "auto"   -- a theme's key (LowHealthThemes.lua), or by class and talents
DEFAULTS.lowHealthStart = 0.75     -- health (0-1) they start creeping in below
DEFAULTS.lowHealthFull = 0.15      -- ...and are all the way in at
DEFAULTS.lowHealthReach = 0.3      -- share of the screen each edge's shadow covers at full
DEFAULTS.lowHealthDark = 0.85      -- the shadow's darkness at full
DEFAULTS.lowHealthRed = 0.6        -- 0 black (like the death screen) to 1 the theme's colour
DEFAULTS.lowHealthBloodAlpha = 0.9
DEFAULTS.lowHealthBloodReach = 0.7 -- how far in our art comes at full (0-1)
-- Blizzard art: the game's screen effects, a layer of their own over ours
-- (LowHealthThemes.lua's patterns). "auto": the theme's pick, and the pattern's
-- own mask and colors.
DEFAULTS.lowHealthGamePattern = "auto" -- or a pattern's file number
DEFAULTS.lowHealthGameMask = "auto"    -- or "none", or a mask's file number
DEFAULTS.lowHealthGameColors = "auto"  -- or "theme" (greyed, tinted) or "own"
DEFAULTS.lowHealthGameAlpha = 0.6
DEFAULTS.lowHealthGameReach = 0.7  -- how far in Blizzard art comes at full (0-1)
-- Our effects (with the shadow, heartbeat, grade and flash below).
DEFAULTS.lowHealthSparks = true    -- the theme's sparks and haze
DEFAULTS.lowHealthRipple = true    -- a wave of the game's art creeping in on each beat
DEFAULTS.lowHealthStrength = 0.5   -- the look's strength: half as set, scaled down to none or up to double
DEFAULTS.lowHealthStyle = true     -- the Style hub's page: its look as set there (off: the defaults')
DEFAULTS.lowHealthPulse = true     -- a heartbeat: the edges throb
DEFAULTS.lowHealthPulseAmount = 0.25
DEFAULTS.lowHealthBpmSlow = 60     -- beats a minute as they start creeping in...
DEFAULTS.lowHealthBpmFast = 140    -- ...and at full
DEFAULTS.lowHealthFollow = 0.1     -- seconds to close all the way in after a drop (quick: it's a warning)
DEFAULTS.lowHealthLiftSpeed = 0.4  -- the most it lifts a second after healing (share of all the way);
                                   -- it eases up to that speed and slows as it settles
DEFAULTS.lowHealthFlash = true     -- a flash at the edges on a big hit
DEFAULTS.lowHealthFlashHit = 0.08  -- share of your health lost at once that counts
DEFAULTS.lowHealthFlashAdded = 0.2 -- ...or lost in smaller hits adding up (since the last, in a fight)
DEFAULTS.lowHealthCalm = 0.6       -- strength out of combat (eating up, say)
-- Health bars: faded out in CineMode, they fade in between Starts below
-- (hidden above) and All the way in at (fully up below), Frames.lua.
DEFAULTS.lowHealthPortrait = false -- your player frame (portrait)
DEFAULTS.lowHealthPrd = false      -- ...and the personal resource display
-- The page's test: health falling from one share to another over some seconds.
DEFAULTS.lowHealthTestFrom = 1
DEFAULTS.lowHealthTestTo = 0.1
DEFAULTS.lowHealthTestTime = 8
DEFAULTS.lowHealthTestHits = true  -- falls in hits (flashing) rather than smoothly

local db
local EDGE_START = 0.05      -- share of the screen the shadow covers as it starts in
-- (The art is the outer tenth or so of its texture, so a little over a
-- screen already puts it past the edges: much more and it only shows at full.)
local ART_OUT = 1.35         -- the art's size (screens) as it starts: about all past the edges
local ART_DEEPEST = 1        -- ...and at full with Reach 100% (no smaller: it must cover the screen)
local ART_SHALLOWEST = 1.2   -- ...and at full with Reach 0%
local FLASH_TIME = 0.6       -- seconds a hit's flash takes to fade
local FLASH_TINT = 0.6       -- how far a flash turns the shadow to the theme's flash colour
local DEATH_FADE = 0.5       -- seconds to clear as you die (the death screen takes over)
local LIFT_EASE = 0.8        -- how quickly the lift speeds up and slows down (a second, each second)
local TEST_HOLD = 2          -- seconds the test stays at its last share before handing back
local TEST_HIT_EVERY = 0.7   -- seconds between the test's hits
local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\LowHealth\\"
-- Game art (the Game art themes, LowHealthThemes.lua, or over any theme with
-- /cine debug gameart): the game's own low-health edge in place of our art,
-- greyed and tinted by the theme, and a wave of it creeping in on each beat.
local GAME_EDGE = "Interface\\FullScreenTextures\\LowHealth"
local RIPPLE_SPAN = 0.25           -- how far past the art each wave starts (screens)
local RIPPLE_ALPHA = 0.7
local WHITE = { 1, 1, 1 }           -- (Blizzard art in its own colors: untinted)
local SWAY = 0.012                 -- how far a sloshing theme's art rocks (share of the height, times its sway)
-- Sparks (a theme's sparks, LowHealthThemes.lua): the few sprites left, each
-- its own texture: lightning flickering in by the top edge, stars twinkling,
-- motes rising, gas billowing in.
local MAX_SPARKS = 24
local FADE_IN, FADE_END = 0.3, 1.2 -- seconds those that fade fade in and out over
local GAS_REACH = 0.2              -- gas starts this share of the shadow's reach in (by the edge)...
local GAS_DRIFT = 0.03             -- ...and billows this share of the way to the middle

-- The colour grade: a layer over the whole screen that multiplies what's
-- under it (the world, not the UI above), so it can't grey colours out, only
-- darken and tint them: toward this grey, tinged GRADE_TINT of the way to the
-- theme's flash colour. White is no change, so it fades by its colour.
local GRADE_GREY = { 0.6, 0.63, 0.68 }
local GRADE_TINT = 0.3

local frame, driver -- (the screen's overlay, and what runs it)
-- What draws the edges: the screen's, and the Style page's preview's, each
-- (NewDrawer) { frame, its textures: body, glow, ripple (game art only),
-- theirs and theirsWave (Blizzard art's layer and its wave), edges (the
-- shadow), grade, sparks; shown (the theme they're set up for), pick
-- (Blizzard art's: { pattern, mask, tiles, own, paint }, or nil), gameArt (the
-- game's art in place of ours), reach (the shadow's as last shown: sparks
-- start about there), artScale (the art's size now), level, flash, beat }.
local screen
-- (/cine debug gameart's, over any theme: true; or the dev page's tester's
-- layers: { pattern = file number, mask = one or nil, center = the middle's
-- hole's size or nil, tiles = across the art, paint = drawn as paint }. The
-- screen's only.)
local gameArtTest
local theme -- (the theme wanted)
local autoTheme, autoGameTheme -- (Auto's picks, ours and Game art's, until your talents change)
local level, flash = 0, 0 -- the screen's: shown (0-1), the hit flash (0-1)
local liftSpeed = 0 -- (lifting now: a share of all the way a second)
local lastHealth -- (share, for spotting big hits)
local test -- the page's test running: { from, to, time, start, hits }
local secretCurve -- (health that's secret: its alpha from the game, by this curve)
-- (Health secret, so Update can't see hits: the hit event's, since the last
-- frame. Lost: a share of your health.)
local woundLost, woundHit = 0, false
local lostAdding = 0 -- (lost since the last flash, for Hits adding up to; again each fight)
local testShare -- (the test's health now, for the health bars)
local shadowColor = { 0, 0, 0 }

-- The look's settings (the Style hub's Vitals Vision page): its own while
-- that page is on, else the defaults.
local function Look()
	return ns.StyleLook and ns.StyleLook("lowHealthStyle") or db
end

-- The look for a theme. A theme's own defaults (its look, LowHealthThemes.lua)
-- are the page's settings while it's shown (SyncThemeLook), so the page shows
-- what's used; with the page off, they're over the defaults here. (One proxy
-- for each theme and look, made once.)
-- Strength (lowHealthStrength, 0-1) scales these: at half, each as set; down
-- to none at 0, up to double at full, up to its most ({ most, share it
-- scales by }: reach only partly, so it never shrinks to nothing).
local SCALED = {
	lowHealthDark = { 1, 1 }, lowHealthPulseAmount = { 0.6, 1 }, lowHealthBloodAlpha = { 1, 1 },
	lowHealthGameAlpha = { 1, 1 }, lowHealthReach = { 0.5, 0.5 },
}
-- (Settings a theme never sets, the player's alone: none now; the color grade,
-- once one, follows Strength.)
local NOT_THEMES = {}
local themed = {}
local function ThemeLook(base, wanted)
	wanted = wanted or false
	local byBase = themed[wanted] or {}
	themed[wanted] = byBase
	local proxy = byBase[base]
	if not proxy then
		proxy = setmetatable({}, { __index = function(_, key)
			local value = base[key]
			local own = wanted and wanted.look and not NOT_THEMES[key] and wanted.look[key]
			if own ~= nil and not (ns.StyleOn and ns.StyleOn("lowHealthStyle")) then value = own end
			local scaled = SCALED[key]
			if scaled and type(value) == "number" then
				local strength = base.lowHealthStrength or 0.5
				value = math.min(scaled[1], value * (1 + (strength * 2 - 1) * scaled[2]))
			end
			return value
		end })
		byBase[base] = proxy
	end
	return proxy
end

-- A theme's own defaults onto the page's settings as it's shown, so the
-- page's controls show what's used: each still at its default (or as the
-- last theme set it) takes the theme's; one the player changed stays theirs.
-- (lowHealthFromTheme: the theme last put on, and what it set.)
local function SyncThemeLook(wanted, again)
	if not (db and wanted) then return end
	local from = db.lowHealthFromTheme
	if not from then
		from = {}
		db.lowHealthFromTheme = from
	end
	if from.theme == wanted.key and not again then return end
	for key, value in pairs(from.values or {}) do
		if db[key] == value then db[key] = DEFAULTS[key] end -- (untouched: back)
	end
	local values = {}
	for key, value in pairs(wanted.look or {}) do
		if not NOT_THEMES[key] and db[key] == DEFAULTS[key] then
			db[key] = value
			values[key] = value
		end
	end
	from.theme, from.values = wanted.key, values
end

-- The dev copy's DEV SET DEFAULT: a theme's own defaults
-- (CinematicDB.vitalsThemeEdits[key].look), over its look as written, to be
-- written into LowHealthThemes.lua. (The old theme editor's other edits stay
-- saved but do nothing: nothing on the page shows them.)
local themeLookAsWritten = {} -- (by key: the look as LowHealthThemes.lua has it, or false)
local function ThemeEdited(key)
	local theme = ns.LOW_HEALTH_THEME[key]
	if not theme then return end
	if themeLookAsWritten[key] == nil then themeLookAsWritten[key] = theme.look or false end
	local edits = CinematicDB and CinematicDB.vitalsThemeEdits and CinematicDB.vitalsThemeEdits[key]
	local look = edits and edits.look
	if look == nil then look = themeLookAsWritten[key] end
	theme.look = look or nil
	if screen then screen.shown = nil end
end
ns.VitalsThemeEdited = ThemeEdited

-- Whether this client has a file: SetTexture says false for one it hasn't
-- (drawn, it'd be the game's bright green). Many of the game's screen effects
-- are retail's only. (A texture of its own, hidden: asking on one shown would
-- flash the green.)
local FileLoads
do
	local probe
	function FileLoads(file)
		if not probe then
			local holder = CreateFrame("Frame", nil, UIParent)
			holder:Hide()
			probe = holder:CreateTexture()
		end
		return probe:SetTexture(file) ~= false
	end
end

local function Approach(current, target, elapsed, duration)
	local step = duration > 0 and elapsed / duration or 1
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- Your health as a share (0-1); nil if the game won't say (secret).
local function HealthShare()
	local health, max = UnitHealth("player"), UnitHealthMax("player")
	if Secret(health) or Secret(max) or type(health) ~= "number" or type(max) ~= "number" then
		return nil
	end
	return max > 0 and health / max or 1
end

-- How far in the edges want to be (0-1) at a health share.
local function LevelAt(share)
	local start, full = db.lowHealthStart, math.min(db.lowHealthFull, db.lowHealthStart - 0.01)
	return math.max(0, math.min(1, (start - share) / (start - full)))
end

-- Secret health (in combat on some clients): the game sets the overlay's
-- alpha from your health through this curve, and the edges stay at full
-- reach (no creep: only the fade). nil where there's no curve API.
local function SecretCurve()
	if secretCurve ~= nil then return secretCurve end
	secretCurve = false
	if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType and UnitHealthPercent) then
		return false
	end
	local ok, curve = pcall(C_CurveUtil.CreateCurve)
	if ok and curve then
		curve:SetType(Enum.LuaCurveType.Linear)
		local start, full = db.lowHealthStart, math.min(db.lowHealthFull, db.lowHealthStart - 0.01)
		curve:AddPoint(0, 1)
		curve:AddPoint(full, 1)
		curve:AddPoint(start, 0)
		curve:AddPoint(1, 0)
		secretCurve = curve
	end
	return secretCurve
end

-- Auto: your class's theme for the talent tree with the most points (the
-- spec, on clients with specs). No points yet: the class's own.
local function TreeWithMostPoints()
	if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
	local best, bestPoints = nil, 0
	for i = 1, GetNumTalentTabs() or 0 do
		-- (Classic: name, icon, points...; later clients: id, name, description, icon, points...)
		local ok, a, _, c, _, e = pcall(GetTalentTabInfo, i)
		local points = ok and (type(a) == "number" and e or c)
		if type(points) == "number" and points > bestPoints then
			best, bestPoints = i, points
		end
	end
	return best
end

-- (byClass, bySpec: our themes' lists, or Game art's.)
local function AutoTheme(byClass, bySpec, fallback)
	local _, class = UnitClass("player")
	local list = byClass[class]
	if not list then return fallback end
	local tree
	if GetSpecialization then
		local ok, spec = pcall(GetSpecialization)
		if ok and type(spec) == "number" and spec > 0 then
			list = bySpec[class] or list
			tree = spec
		end
	else
		tree = TreeWithMostPoints()
	end
	return tree and list[tree] or list.none or list[1]
end

function ns.LowHealthAutoTheme()
	autoTheme = autoTheme or AutoTheme(ns.LOW_HEALTH_CLASS_THEMES, ns.LOW_HEALTH_SPEC_THEMES, "blood")
	return autoTheme
end

-- Auto, Game art: the game's edge in your class and spec's colour.
function ns.LowHealthAutoGameTheme()
	autoGameTheme = autoGameTheme
		or AutoTheme(ns.LOW_HEALTH_GAME_CLASS_THEMES, ns.LOW_HEALTH_GAME_SPEC_THEMES, "game_low")
	return autoGameTheme
end

local function WantedTheme(look)
	local key = (look or Look()).lowHealthTheme
	if key == "autogame" then
		key = ns.LowHealthAutoGameTheme()
	elseif key == "auto" or not ns.LOW_HEALTH_THEME[key] then
		key = ns.LowHealthAutoTheme()
	end
	return ns.LOW_HEALTH_THEME[key] or ns.LOW_HEALTH_THEMES[1]
end

-- A drawer's textures, in parent (the screen's overlay, or the preview).
local function NewDrawer(parent)
	local d = { frame = parent, sparks = {}, reach = 0, artScale = ART_OUT, level = 0, flash = 0, beat = 0 }
	d.body = parent:CreateTexture(nil, "BORDER")
	d.body:SetPoint("CENTER")
	d.glow = parent:CreateTexture(nil, "BORDER", nil, 1)
	d.glow:SetPoint("CENTER")
	d.glow:SetBlendMode("ADD")
	d.ripple = parent:CreateTexture(nil, "BORDER", nil, 1)
	d.ripple:SetPoint("CENTER")
	d.ripple:SetBlendMode("ADD")
	d.ripple:Hide()
	-- (Blizzard art over ours, under the sparks.)
	d.theirs = parent:CreateTexture(nil, "BORDER", nil, 1)
	d.theirs:SetPoint("CENTER")
	d.theirs:Hide()
	d.theirsWave = parent:CreateTexture(nil, "BORDER", nil, 1)
	d.theirsWave:SetPoint("CENTER")
	d.theirsWave:Hide()
	d.edges = ns.CreateVignette(parent)
	-- (The shadow under everything: over the art, it hid it.)
	for _, piece in pairs(d.edges) do
		piece:SetDrawLayer("BACKGROUND", -8)
	end
	d.grade = parent:CreateTexture(nil, "BACKGROUND", nil, -7)
	d.grade:SetAllPoints(parent)
	d.grade:SetTexture("Interface\\Buttons\\WHITE8X8")
	d.grade:SetBlendMode("MOD")
	d.grade:Hide()
	for i = 1, MAX_SPARKS do
		local tex = parent:CreateTexture(nil, "BORDER", nil, 2)
		tex:Hide()
		d.sparks[i] = { tex = tex }
	end
	return d
end

local function Create()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("BACKGROUND")
	frame:SetFrameLevel(0) -- (under the letterbox, like the tint and death screen)
	frame:EnableMouse(false)
	ns.AddOverlay(frame)
	screen = NewDrawer(frame)
	screen.isScreen = true
	frame:Hide()
	-- (Its own frame, not under UIParent, so it runs with the UI hidden too.)
	driver = CreateFrame("Frame")
	driver:Hide()
end

local function ClearSparks(d)
	for _, spark in ipairs(d.sparks) do
		spark.born = nil
		spark.tex:Hide()
	end
end

-- The tester's layers: a mask on a texture (which: "edgeMask" or
-- "centerMask"), or off (file nil). CLAMP: past a mask's own edges, its edge
-- (shown) carries on, so a small centre mask hides only the middle.
local CENTER_MASK = 4541187 -- (the game's soft rounded frame: clear in the middle)
local function Masked(tex, which, file)
	local mask = tex[which]
	if file and not mask then
		local owner = tex:GetParent()
		if not owner.CreateMaskTexture then return end
		mask = owner:CreateMaskTexture()
		tex[which] = mask
	end
	if not mask then return end
	if file then
		mask:SetTexture(file, "CLAMP", "CLAMP")
		if which == "edgeMask" then mask:SetAllPoints(tex) else mask:SetPoint("CENTER", tex) end
		if not tex[which .. "On"] then tex:AddMaskTexture(mask) end
	elseif tex[which .. "On"] then
		tex:RemoveMaskTexture(mask)
	end
	tex[which .. "On"] = file and true or nil
end

-- (Each frame, as the art's size changes: the centre hole's, by its share.)
local function SizeMasks(tex, w, h)
	local layers = type(gameArtTest) == "table" and gameArtTest
	if layers and layers.center and tex.centerMaskOn then
		tex.centerMask:SetSize(w * layers.center, h * layers.center)
	end
end

-- What Blizzard art shows for a theme: the look's pattern, mask and colors,
-- or the theme's pick and the pattern's own. A file this client hasn't: the
-- game's red edge, tinted (Classic has few); a mask it hasn't: the wispy frame
-- if it has that, else the red edge again. No pick (a Game art theme): the red edge.
local function TheirsPick(wanted, look)
	local pick = wanted.theirs
	local file = look.lowHealthGamePattern
	if file == "auto" then file = pick and pick[1] or ns.LOW_HEALTH_BLIZZ_EDGE end
	if type(file) ~= "number" then file = ns.LOW_HEALTH_BLIZZ_EDGE end
	if not pick then pick = { file, own = false } end
	local pattern = ns.LOW_HEALTH_BLIZZ_PATTERN[file] or { file }
	local mask = look.lowHealthGameMask
	if mask == "auto" then mask = pattern.mask elseif mask == "none" then mask = nil end
	local own = pattern.own
	if look.lowHealthGamePattern == "auto" and pick and pick.own ~= nil then own = pick.own end
	if look.lowHealthGameColors ~= "auto" then own = look.lowHealthGameColors == "own" end
	local edge = { ns.LOW_HEALTH_BLIZZ_EDGE, nil, 1, false, false }
	if not FileLoads(file) then return edge end
	if mask and not FileLoads(mask) then
		mask = FileLoads(1305138) and 1305138 or nil -- (the wispy frame)
		if not mask then return edge end
	end
	return { file, mask, pattern.tiles or 1, own and true or false, pattern.paint and true or false }
end

-- Sets a drawer's textures up for a theme (its art and glow, and Blizzard
-- art's layer as the look says).
local function UseTheme(d, wanted, look)
	d.shown = wanted
	ClearSparks(d)
	local body, glow, ripple, theirs, theirsWave = d.body, d.glow, d.ripple, d.theirs, d.theirsWave
	body:SetPoint("CENTER") -- (a sloshing theme's rocking, undone)
	glow:SetPoint("CENTER")
	theirs:SetPoint("CENTER")
	-- (Only art there's a file for: an edge with no art or glow of its own (Glow
	-- has no art, Fur no glow) shows none, not the game's green.)
	d.hasBody = wanted.edge and wanted.body and FileLoads(ART .. wanted.edge) or false
	d.hasGlow = wanted.edge and wanted.glow and FileLoads(ART .. wanted.edge .. "Glow") or false
	if d.hasBody then
		body:SetTexture(ART .. wanted.edge)
	end
	if d.hasGlow then
		glow:SetTexture(ART .. wanted.edge .. "Glow")
		glow:SetBlendMode("ADD")
	end
	body:SetDesaturated(false)
	body:SetBlendMode("BLEND")
	glow:SetDesaturated(false)
	ripple:Hide()
	-- (A Game art theme's, or the debug test's over any, on the screen.)
	local tested = d.isScreen and gameArtTest
	d.gameArt = tested or wanted.game or false
	local layers = d.gameArt and type(tested) == "table" and tested
	for _, tex in ipairs({ body, glow, ripple }) do
		tex:SetTexCoord(0, 1, 0, 1)
		Masked(tex, "edgeMask", layers and layers.mask)
		Masked(tex, "centerMask", layers and layers.center and CENTER_MASK)
	end
	if d.gameArt then
		-- (The tester's pattern tiles: square, so as many down as fit.)
		local across = layers and layers.tiles or 1
		local down = across * UIParent:GetHeight() / UIParent:GetWidth()
		for _, tex in ipairs({ body, glow, ripple }) do
			if layers then
				tex:SetTexture(layers.pattern, "REPEAT", "REPEAT")
				tex:SetTexCoord(0, across, 0, down)
			else
				tex:SetTexture(GAME_EDGE)
			end
			-- (it's red: grey, then the theme's colour; the tester's Own
			-- colors: the file as it is)
			tex:SetDesaturated(not (layers and layers.own))
		end
		-- (Light on black, as the game draws it: as paint, its black middle
		-- covered the screen.)
		body:SetBlendMode(layers and layers.paint and "BLEND" or "ADD")
	end
	-- Blizzard art's layer (not while the dev page's tester shows its own).
	d.pick = not tested and TheirsPick(wanted, look) or nil
	if d.pick then
		local file, mask, tiles, own, paint = unpack(d.pick, 1, 5)
		local down = tiles * UIParent:GetHeight() / UIParent:GetWidth()
		for _, tex in ipairs({ theirs, theirsWave }) do
			tex:SetTexture(file, "REPEAT", "REPEAT")
			tex:SetTexCoord(0, tiles, 0, file == ns.LOW_HEALTH_BLIZZ_EDGE and 1 or down)
			tex:SetDesaturated(not own)
			Masked(tex, "edgeMask", mask)
			Masked(tex, "centerMask", nil)
		end
		theirs:SetBlendMode(paint and "BLEND" or "ADD")
		theirsWave:SetBlendMode("ADD")
	else
		theirs:Hide()
		theirsWave:Hide()
	end
end

-- A heartbeat: a strong beat and a softer one just after (0-1).
local function Between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

-- Where a spark starts (shares of the screen across and down), about where
-- the shadow reaches now: by the top or bottom edge, the sides, or any.
-- spread: anywhere along the edge, corners too (else not the last tenths).
local function Place(at, reach, spread)
	local along = spread and math.random() or 0.1 + 0.8 * math.random()
	local inset = reach * (0.4 + 0.7 * math.random())
	local side = at == "top" and 1 or at == "bottom" and 2 or at == "sides" and math.random(3, 4)
		or math.random(4)
	if side == 1 then return along, inset end
	if side == 2 then return along, 1 - inset end
	-- (Left and right: the reach is a share of the width there, and screens are wide.)
	if side == 3 then return inset * 0.6, along end
	return 1 - inset * 0.6, along
end

local function Spark(d, info)
	for _, spark in ipairs(d.sparks) do
		if not spark.born then
			spark.info = info
			spark.born, spark.life, spark.size = GetTime(), Between(info.life), Between(info.size)
			-- (Gas stays over the edges, where it blends in: alone further in, it
			-- looked pasted on.)
			local gas = info.kind == "drift"
			spark.x, spark.y = Place(info.at, gas and d.reach * GAS_REACH or d.reach, gas)
			spark.phase = math.random() * 2 * math.pi
			spark.tex:SetTexture(ART .. info.tex)
			spark.tex:SetBlendMode(info.flat and "BLEND" or "ADD")
			-- (mirrored now and then)
			if math.random() < 0.5 then spark.tex:SetTexCoord(0, 1, 0, 1) else spark.tex:SetTexCoord(1, 0, 0, 1) end
			return
		end
	end
end

-- A drawer's sparks: a big hit's (the theme's for a hit), and those that
-- come now and then (more the further in).
local function Sparking(d, look, elapsed, hit)
	local list = look.lowHealthSparks and d.level > 0.05 and d.shown and d.shown.sparks
	if not list then return end
	for _, info in ipairs(list) do
		if hit then
			for _ = 1, info.hit and math.random(info.hit[1], info.hit[2]) or 0 do Spark(d, info) end
		end
		if info.rate and math.random() < info.rate / 60 * elapsed * d.level then Spark(d, info) end
	end
end

-- The sparks now. flicker: on and off, fading out; twinkle: fading in and
-- out; rise: floating up, swaying, fading in and out; drift: billowing in
-- a little toward the middle, growing, fading in slowly and out.
local function AnimateSparks(d, now, width, height, alpha)
	for _, spark in ipairs(d.sparks) do
		if spark.born then
			local t, info = now - spark.born, spark.info
			if t >= spark.life then
				spark.born = nil
				spark.tex:Hide()
			else
				local a
				local x, y, size = spark.x, spark.y, spark.size
				if info.kind == "flicker" then
					a = (math.sin(t * 55 + spark.phase) > -0.4 and 1 or 0.15) * (1 - t / spark.life)
				elseif info.kind == "twinkle" then
					a = math.sin(math.pi * t / spark.life)
				elseif info.kind == "drift" then
					local share = t / spark.life
					x, y = x + (0.5 - x) * GAS_DRIFT * share, y + (0.5 - y) * GAS_DRIFT * share
					size = size * (1 + 0.5 * share)
					a = math.min(1, t / (FADE_IN * 2), (spark.life - t) / FADE_END)
				else
					y = y - (info.speed or 0.1) * t
					x = x + math.sin(spark.phase + t * 2) * 0.008
					a = math.min(1, t / FADE_IN, (spark.life - t) / FADE_END)
				end
				local px = size * height
				spark.tex:ClearAllPoints()
				spark.tex:SetPoint("CENTER", d.frame, "TOPLEFT", x * width, -y * height)
				spark.tex:SetSize(px, px)
				local color = info.color
				spark.tex:SetVertexColor(color[1], color[2], color[3], alpha * a)
				spark.tex:Show()
			end
		end
	end
end

local function Heartbeat(phase)
	local p = phase % 1
	local first = math.exp(-((p - 0.05) / 0.05) ^ 2)
	local second = 0.6 * math.exp(-((p - 0.28) / 0.06) ^ 2)
	return math.max(first, second)
end

-- A drawer's heartbeat, elapsed seconds on (its beat moves on): how far in
-- with the beat's push (k), and the heartbeat now (0-1).
local function Beat(d, look, elapsed)
	local k, heart = d.level, 0
	if look.lowHealthPulse and d.level > 0 then
		local bpm = (look.lowHealthBpmSlow + (look.lowHealthBpmFast - look.lowHealthBpmSlow) * d.level)
			* (d.shown.bpm or 1)
		d.beat = (d.beat + elapsed * bpm / 60) % 1
		heart = Heartbeat(d.beat)
		k = d.level * (1 + look.lowHealthPulseAmount * (d.shown.pulse or 1) * heart)
	end
	-- (A flash with the edges out still shows a little at the edges.)
	return math.max(k, d.flash * 0.35), heart
end

-- Draws a drawer as the look says. k: how far in (0 none, 1 full; a little
-- more on a beat or a flash); heart: the heartbeat now (0-1). Gives the
-- shadow's reach.
local function Apply(d, look, k, fade, heart, secret)
	local shown, flash, level, beat = d.shown, d.flash, d.level, d.beat
	local body, glow, ripple, theirs, theirsWave = d.body, d.glow, d.ripple, d.theirs, d.theirsWave
	local gameArt = d.gameArt
	local c = math.min(1, k)
	c = c * c * (3 - 2 * c)
	local over = math.max(0, k - 1)
	local width, height = d.frame:GetWidth(), d.frame:GetHeight()
	local size = EDGE_START + (look.lowHealthReach - EDGE_START) * c + over * 0.1
	local alpha = math.min(1, look.lowHealthDark * c + flash * 0.35) * fade
	-- The shadow: the theme's colour (as far as Shadow tint says), toward its
	-- flash colour in a flash.
	local shadow, flashColor = shown.shadow, shown.flash
	for i = 1, 3 do
		local v = shadow[i] * look.lowHealthRed
		shadowColor[i] = v + (flashColor[i] - v) * flash * FLASH_TINT
	end
	ns.SetVignette(d.edges, size, alpha, shadowColor[1], shadowColor[2], shadowColor[3], width, height)
	-- The grade: by how far in the edges are, not their throb (the world
	-- shouldn't pulse). Not with secret health: the game's alpha may not fade
	-- a multiplying layer, so it would stay at full.
	-- (As strong as Strength: none at 0, all the way at full.)
	local strength = look.lowHealthStrength or 0.5
	local graded = strength > 0 and level > 0 and not secret
	if graded then
		local g = level * level * (3 - 2 * level) * strength * fade
		local tint = shown.flash
		local r, gr, b
		for i = 1, 3 do
			local target = GRADE_GREY[i] + (tint[i] - GRADE_GREY[i]) * GRADE_TINT
			local v = 1 + (target - 1) * g
			if i == 1 then r = v elseif i == 2 then gr = v else b = v end
		end
		d.grade:SetVertexColor(r, gr, b)
	end
	d.grade:SetShown(graded)
	-- The art: ours, Blizzard's, or both, closing in together.
	-- (Each while its opacity's above none.)
	local ours, blizz = look.lowHealthBloodAlpha > 0, look.lowHealthGameAlpha > 0 and d.pick
	local artScale = d.artScale
	local sway = shown.sway
	-- (a little bigger while it rocks, so its edges never come on screen)
	local pad = sway and 4 * SWAY * sway or 0
	if (ours or blizz) and c > 0 then
		-- (Each art's size: from past the edges in to as far as its reach says.)
		local function Scale(reach)
			local deep = ART_SHALLOWEST + (ART_DEEPEST - ART_SHALLOWEST) * reach
			return math.max(1, ART_OUT + (deep - ART_OUT) * c - over * 0.05)
		end
		artScale = Scale(look.lowHealthBloodReach)
		d.artScale = artScale
		local theirsScale = Scale(look.lowHealthGameReach)
		-- Sloshing (liquid themes): the art rocks slowly side to side and up and down.
		if sway then
			local now = GetTime()
			local sx = math.sin(now * 1.3) * sway * SWAY * height
			local sy = math.sin(now * 0.9 + 1) * sway * SWAY * 0.6 * height
			body:SetPoint("CENTER", sx, sy)
			glow:SetPoint("CENTER", sx, sy)
			theirs:SetPoint("CENTER", sx, sy)
		end
		local waveAt = look.lowHealthPulse and beat or GetTime() % 1 -- (each beat's wave, or each second's)
		-- Blizzard art: in its own colors or the theme's, brighter on a beat
		-- and in a flash; and its wave creeping in from past the edges.
		if blizz then
			-- (The theme's color: a bright one, as it's added on as light: the glow's,
			-- else the flash's; a smoke theme's art color is near black.)
			local color = d.pick[4] and WHITE or shown.glow or shown.flash or shown.body or WHITE
			local a = look.lowHealthGameAlpha * math.min(1, c * 3) * fade * (0.85 + 0.25 * heart + 0.3 * flash)
			theirs:SetSize(width * (theirsScale + pad), height * (theirsScale + pad))
			theirs:SetVertexColor(color[1], color[2], color[3], math.min(1, a))
			theirs:Show()
			if look.lowHealthRipple then
				local scale = theirsScale + pad + RIPPLE_SPAN * (1 - waveAt)
				theirsWave:SetSize(width * scale, height * scale)
				theirsWave:SetVertexColor(color[1], color[2], color[3],
					math.min(1, a) * RIPPLE_ALPHA * math.sin(math.pi * waveAt))
				theirsWave:Show()
			else
				theirsWave:Hide()
			end
		else
			theirs:Hide()
			theirsWave:Hide()
		end
	else
		theirs:Hide()
		theirsWave:Hide()
	end
	if look.lowHealthSparks and c > 0 then
		AnimateSparks(d, GetTime(), width, height, look.lowHealthBloodAlpha * math.min(1, c * 2) * fade)
	else
		ClearSparks(d)
	end
	if ours and c > 0 then
		local artAlpha = look.lowHealthBloodAlpha * math.min(1, c * 3) * fade
		-- (Game art: the theme's art colour or its glow's, for both.)
		local edged = shown.edge or gameArt
		local color = shown.body or gameArt and shown.glow
		local own = gameArt and d.isScreen and type(gameArtTest) == "table" and gameArtTest.own and WHITE
		color = color and own or color
		if color and edged and (gameArt or d.hasBody) then
			body:SetSize(width * (artScale + pad), height * (artScale + pad))
			SizeMasks(body, width * (artScale + pad), height * (artScale + pad))
			body:SetVertexColor(color[1], color[2], color[3], artAlpha)
			body:Show()
		else
			body:Hide()
		end
		color = shown.glow or gameArt and shown.body
		color = color and own or color
		if color and edged and (gameArt or d.hasGlow) then
			glow:SetSize(width * (artScale + pad), height * (artScale + pad))
			SizeMasks(glow, width * (artScale + pad), height * (artScale + pad))
			-- (brighter on a beat and in a flash)
			local a = artAlpha * (shown.glowAlpha or 1) * (0.8 + 0.3 * heart + 0.4 * flash)
			glow:SetVertexColor(color[1], color[2], color[3], math.min(1, a))
			glow:Show()
		else
			glow:Hide()
		end
		if gameArt and color and look.lowHealthRipple then
			-- A wave creeping in from past the edges on each beat (each second
			-- with no heartbeat), brightest halfway.
			local p = look.lowHealthPulse and beat or GetTime() % 1
			local scale = artScale + pad + RIPPLE_SPAN * (1 - p)
			ripple:SetSize(width * scale, height * scale)
			SizeMasks(ripple, width * scale, height * scale)
			ripple:SetVertexColor(color[1], color[2], color[3], artAlpha * RIPPLE_ALPHA * math.sin(math.pi * p))
			ripple:Show()
		else
			ripple:Hide()
		end
	else
		body:Hide()
		glow:Hide()
		ripple:Hide()
	end
	d.reach = size
	return size
end

-- What's wanted now: the share of health to go by (nil: secret), and whether
-- the edges are wanted at all.
local function Wanted(now)
	if test then
		local t = now - test.start
		if t > test.time + (test.hold or TEST_HOLD) and test.loop then
			-- (Looping, the Style page's: from the top again, till it's pressed again.)
			test.start, t = now, 0
		end
		if t > test.time + (test.hold or TEST_HOLD) then
			local quiet = test.quiet
			test = nil
			if not quiet then ns.Print(L["Vitals Vision test done."]) end
		else
			local progress = math.min(1, t / math.max(0.1, test.time))
			if test.hits then -- (in steps, each a hit)
				local steps = math.max(1, math.floor(test.time / TEST_HIT_EVERY))
				progress = math.min(1, math.ceil(progress * steps - 0.001) / steps)
			end
			return test.from + (test.to - test.from) * progress, db.lowHealthEdges, true
		end
	end
	if not db.lowHealth or not db.lowHealthEdges or (db.lowHealthOnlyCine and not ns.lastCinematic) then
		return 1, false
	end
	if ns.Flag(UnitIsDeadOrGhost("player")) then
		return 1, false, false, true
	end
	return HealthShare(), true
end

local belowStart = false -- health known to be under Starts below (not when secret)

local function Update(_, elapsed)
	local now = GetTime()
	local look = Look()
	theme = WantedTheme(look)
	look = ThemeLook(look, theme)
	if theme ~= screen.shown then
		SyncThemeLook(theme)
		UseTheme(screen, theme, look)
	end
	local share, on, testing, dead = Wanted(now)
	testShare = testing and share or nil
	-- A big hit, or smaller ones adding up to Hits adding up to: a flash (only
	-- by what was shown: a heal doesn't).
	-- (Secret health, in fights on retail: by the hit event's amounts, plain.)
	local lostNow, bigHit = 0, false
	if on and share and lastHealth then
		lostNow = math.max(0, lastHealth - share)
		bigHit = lostNow >= db.lowHealthFlashHit
	elseif on and share == nil then
		lostNow, bigHit = woundLost, woundHit
	end
	woundLost, woundHit = 0, false
	lostAdding = on and lostAdding + lostNow or 0
	local hit = bigHit or lostAdding >= db.lowHealthFlashAdded
	if hit then
		lostAdding = 0
		if look.lowHealthFlash then flash = 1 end
	end
	screen.level = level
	Sparking(screen, look, elapsed, hit)
	lastHealth = share
	belowStart = on and share ~= nil and share < db.lowHealthStart
	flash = Approach(flash, 0, elapsed, FLASH_TIME)
	local secret = on and share == nil
	local target = on and (share and LevelAt(share) or 1) or 0
	if on and not testing and not secret and not ns.Flag(UnitAffectingCombat("player")) then
		target = target * db.lowHealthCalm
	end
	if dead or target >= level then
		-- Closing in (or dying): straight there, quickly.
		level = Approach(level, target, elapsed, dead and DEATH_FADE or db.lowHealthFollow)
		liftSpeed = 0
	else
		-- Lifting: speeding up to at most Lift speed, slowing to settle, so a
		-- big heal eases the edges back rather than snapping them out.
		local gap = level - target
		local wanted = math.min(db.lowHealthLiftSpeed, math.sqrt(2 * LIFT_EASE * gap))
		liftSpeed = math.min(wanted, liftSpeed + LIFT_EASE * elapsed)
		level = math.max(target, level - liftSpeed * elapsed)
		if level - target < 0.001 then level = target end
	end
	screen.level, screen.flash = level, flash
	local k, heart = Beat(screen, look, elapsed)
	local fade = 1
	if secret then
		local curve = SecretCurve()
		if curve then
			-- (The game's own number, secret: straight into SetAlpha.)
			pcall(function() frame:SetAlpha(UnitHealthPercent("player", true, curve)) end)
		else
			fade = 0
		end
	else
		frame:SetAlpha(1)
	end
	local shown = (k > 0 or flash > 0) and fade > 0
	frame:SetShown(shown)
	if shown then
		Apply(screen, look, k, fade, heart, secret)
	else
		ClearSparks(screen)
	end
	-- Settled with nothing showing (and not secret: that's left running, as
	-- the game's alpha follows your health with no events to go by here).
	if not shown and not secret and not test and level == 0 and flash == 0 then
		driver:Hide()
	end
end

-- Something changed (health, combat, a setting): run until settled.
local function Wake()
	if driver then driver:Show() end
end
ns.RefreshLowHealth = function()
	secretCurve = nil -- (its points follow the start and full settings)
	if screen then screen.shown = nil end -- (set up again: the look may have changed)
	Wake()
end

-- The page's test: health from one share to another over seconds (then a
-- moment there, then back to yours), in the theme picked. Shows with the
-- edges off too.
function ns.TestLowHealth()
	db = db or ns.GetDB()
	test = { from = db.lowHealthTestFrom, to = db.lowHealthTestTo, time = db.lowHealthTestTime,
		start = GetTime(), hits = db.lowHealthTestHits }
	lastHealth = test.from
	Wake()
end

-- The Style page's test on the screen: the page's test over and over, till
-- this is called again. Says whether it's on now.
function ns.LoopLowHealthTest()
	if test and test.loop then
		test = nil
		Wake()
		return false
	end
	ns.TestLowHealth()
	test.loop = true
	return true
end
function ns.LowHealthTestLooping()
	return test ~= nil and test.loop == true
end

-- A quick look (the welcome window's Cinema level): the page's test, shorter,
-- with nothing said in chat. Health falls in hits to low, so the theme's art
-- soaks in with its flashes, held for seconds, then back to yours.
local GLIMPSE_FROM, GLIMPSE_TO, GLIMPSE_TIME = 0.7, 0.1, 1.4
function ns.FlashVitals(seconds)
	db = db or ns.GetDB()
	test = { from = GLIMPSE_FROM, to = GLIMPSE_TO, time = GLIMPSE_TIME, start = GetTime(), hits = true,
		hold = seconds or 2, quiet = true }
	lastHealth = test.from
	Wake()
end

-- That look cut short (another level picked): gone at once, not eased out,
-- then back to your own health.
function ns.StopVitalsFlash()
	if not (test and test.quiet) then return end
	test, testShare, lastHealth = nil, nil, nil
	level, flash, liftSpeed = 0, 0, 0
	ClearSparks(screen)
	if frame then frame:Hide() end
	Wake()
end

function ns.StopLowHealthTest()
	test = nil
	Wake()
end

-- A small camera shake, as a big hit might give (the dev copy's page has a
-- button to try it; hits don't shake yet). Each step turns the view for
-- SHAKE_STEP seconds at its share of SHAKE_SPEED degrees a second, yaw and
-- pitch; each list adds up to 0, and what frame timing leaves over is
-- turned back at the end, so the view ends where it started. A camera of
-- ours like any other: it waits its turn, and your input stops it.
local SHAKE_STEP = 0.04
local SHAKE_SPEED = { yaw = 40, pitch = 25 }
local SHAKE_YAW = { 1, -1.8, 1.5, -1.1, 0.4 }
local SHAKE_PITCH = { -0.6, 1.1, -0.9, 0.6, -0.2 }
local SHAKE_AXES = {
	yaw = { "MoveViewRightStart", "MoveViewRightStop", "MoveViewLeftStart", "MoveViewLeftStop",
		"cameraYawMoveSpeed", 180 },
	pitch = { "MoveViewUpStart", "MoveViewUpStop", "MoveViewDownStart", "MoveViewDownStop",
		"cameraPitchMoveSpeed", 90 },
}
local shake -- { start, at = { yaw, pitch }: degrees turned so far, going = { yaw, pitch }: speed now }
local shaker = CreateFrame("Frame")
shaker:Hide()

local function ShakeStop(axis)
	local names = SHAKE_AXES[axis]
	ns.CameraCall("shake", names[2])
	ns.CameraCall("shake", names[4])
	shake.going[axis] = 0
end

-- Turn one axis at `speed` degrees a second (signed; 0 stops). False if the
-- view isn't ours.
local function ShakeTurn(axis, speed)
	if speed == shake.going[axis] then return true end
	ShakeStop(axis)
	if speed == 0 then return true end
	local names = SHAKE_AXES[axis]
	local setting = tonumber(GetCVar(names[5])) or names[6]
	local ok = ns.CameraCall("shake", speed > 0 and names[1] or names[3], math.abs(speed) / setting)
	shake.going[axis] = ok and speed or 0
	return ok
end

local function EndShake()
	if not shake then return end
	ShakeStop("yaw")
	ShakeStop("pitch")
	shake = nil
	shaker:Hide()
end

shaker:SetScript("OnUpdate", function(_, elapsed)
	-- (What the last frame's speeds turned.)
	for axis, speed in pairs(shake.going) do
		shake.at[axis] = shake.at[axis] + speed * elapsed
	end
	local step = math.floor((GetTime() - shake.start) / SHAKE_STEP) + 1
	if step <= #SHAKE_YAW then
		if not (ShakeTurn("yaw", SHAKE_YAW[step] * SHAKE_SPEED.yaw)
			and ShakeTurn("pitch", SHAKE_PITCH[step] * SHAKE_SPEED.pitch)) then
			EndShake()
		end
		return
	end
	-- Turning back what's left over, until it's under a frame's worth.
	local done = true
	for axis, at in pairs(shake.at) do
		local speed = SHAKE_SPEED[axis] * 0.5
		if math.abs(at) > speed * math.max(elapsed, 0.01) then
			done = false
			ShakeTurn(axis, at > 0 and -speed or speed)
		else
			ShakeTurn(axis, 0)
		end
	end
	if done or GetTime() - shake.start > 1 then EndShake() end
end)

function ns.ShakeCamera()
	if shake then return end
	shake = { start = GetTime(), at = { yaw = 0, pitch = 0 }, going = { yaw = 0, pitch = 0 } }
	shaker:Show()
end

if ns.RegisterCamera then
	ns.RegisterCamera("shake", function() return shake ~= nil end, EndShake)
end

-- (Events a client may not have: registering those would error.)
local TALENT_EVENTS = { "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LEVEL_UP" }
local isTalentEvent = {}
for _, event in ipairs(TALENT_EVENTS) do isTalentEvent[event] = true end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, _, action, _, amount)
	if event == "UNIT_COMBAT" then
		-- A hit while your health is secret (retail fights): the amount still
		-- comes plain, so it's counted by that. (Plain health: Update's.)
		if action ~= "WOUND" or Secret(amount) or type(amount) ~= "number" or HealthShare() then return end
		local max = UnitHealthMax("player")
		if Secret(max) or type(max) ~= "number" or max <= 0 then return end
		woundLost = woundLost + amount / max
		woundHit = woundHit or amount / max >= db.lowHealthFlashHit
	elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		lostAdding = 0 -- (Hits adding up to: again each fight)
	elseif event == "PLAYER_LOGIN" then
		db = ns.GetDB()
		-- (The dev copy: the theme editor's edits, over the themes.)
		if ns.isDev and CinematicDB and CinematicDB.vitalsThemeEdits then
			for key in pairs(CinematicDB.vitalsThemeEdits) do ThemeEdited(key) end
		end
		Create()
		driver:SetScript("OnUpdate", Update)
		events:RegisterUnitEvent("UNIT_HEALTH", "player")
		events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
		events:RegisterUnitEvent("UNIT_COMBAT", "player")
		for _, other in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
			"PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }) do
			events:RegisterEvent(other)
		end
		for _, other in ipairs(TALENT_EVENTS) do
			pcall(events.RegisterEvent, events, other)
		end
	elseif isTalentEvent[event] then
		autoTheme, autoGameTheme = nil, nil -- (picked again)
	end
	Wake()
end)

-- Is it showing now? (The minimap button's Vision Helper.) Only once your
-- health is under Starts below: secret health can't tell, so it stays dark.
function ns.VitalsVisionActive()
	return db ~= nil and db.lowHealth and db.lowHealthEdges and belowStart and level > 0
end

-- Your health bar faded out in CineMode (Frames.lua asks, each tick): which
-- is "portrait" or "prd". How far up (0-1) by your health: none above Starts
-- below, fading in to fully up at All the way in at. nil: not ticked (or
-- dead). "secret": the game won't say, so ns.SetVitalsSecretAlpha sets it.
-- plate: Forever's personal resource bars (your own nameplate), which can't
-- take a secret alpha: fully up then.
function ns.VitalsFrameAlpha(which, plate)
	if not (db and db[which == "prd" and "lowHealthPrd" or "lowHealthPortrait"]) then return nil end
	local share = testShare
	if not share then
		if not db.lowHealth or ns.Flag(UnitIsDeadOrGhost("player")) then return nil end
		share = HealthShare()
	end
	if share then return LevelAt(share) end
	if plate or not SecretCurve() then return 1 end
	return "secret"
end

-- /cine debug vitals: what the edges and the theme's art are doing now (run
-- it in a fight: health can be secret there).
function ns.ReportVitals()
	if not frame then ns.Print("Vitals Vision: not set up yet") return end
	local function Show(value)
		if Secret(value) then return "secret" end
		if type(value) == "number" then return ("%.2f"):format(value) end
		return tostring(value)
	end
	local health, max = UnitHealth("player"), UnitHealthMax("player")
	ns.Print(("Vitals: on %s, edges %s, art opacity %s, combat %s, test %s"):format(Show(db.lowHealth),
		Show(db.lowHealthEdges), Show(db.lowHealthBloodAlpha), Show(ns.Flag(UnitAffectingCombat("player"))),
		Show(test ~= nil)))
	ns.Print(("  health %s / %s, share %s, curve %s, level %.2f, art size %.2f screens"):format(Show(health),
		Show(max), Show(HealthShare()), Show(SecretCurve() and true), level, screen.artScale))
	ns.Print(("  theme %s (edge %s), frame shown %s, alpha %s, driver %s"):format(Show(screen.shown and screen.shown.key),
		Show(screen.shown and screen.shown.edge), Show(frame:IsShown()), Show(frame:GetAlpha()), Show(driver:IsShown())))
	ns.Print("  game art: " .. Show(screen.gameArt) .. ", Blizzard art: " .. Show(screen.pick and screen.pick[1]))
	for name, tex in pairs({ art = screen.body, glow = screen.glow, wave = screen.ripple, blizzard = screen.theirs }) do
		local r, g, b, a = tex:GetVertexColor()
		local width, height = tex:GetSize()
		ns.Print(("  %s: shown %s, texture %s, size %s x %s, color %s %s %s, alpha %s, %s, greyed %s"):format(name,
			Show(tex:IsShown()), Show(tex:GetTexture()), Show(width), Show(height), Show(r), Show(g), Show(b), Show(a),
			Show(tex:GetBlendMode()), Show(tex.IsDesaturated and tex:IsDesaturated())))
	end
end

-- /cine debug gameart [off]: the game's edge (GAME_EDGE) in place of the
-- theme's art, in its colours, then the page's test. A test to compare by
-- eye; until /reload or off.
function ns.LowHealthGameArt(arg)
	if not frame then ns.Print("Vitals Vision: not set up yet") return end
	gameArtTest = arg ~= "off" or nil
	UseTheme(screen, WantedTheme(), ThemeLook(Look(), WantedTheme()))
	if gameArtTest then
		ns.Print("Vitals Vision: the game's low-health edge in the theme's colours. Testing (off: /cine debug gameart off)")
		ns.TestLowHealth()
	else
		ns.Print("Vitals Vision: the theme's own art again")
	end
	Wake()
end

-- /cine debug gameedge [number|back|blend|off]: steps through the game's
-- full-screen textures (screen effects, by file number: their names don't
-- say what they look like), one at a time over the whole screen, to pick
-- edges for Game art. As light (most are light on black) or, with blend, as
-- paint. Each: its file number, what it looks like, its kind (the tester's
-- menu's groups), the file's name.
local EDGE_SCOUT = {
	{ 131140, "Red soft edge (the game's low health)", "Edges", "lowhealth" },
	{ 131141, "Blue soft edge (loss of control)", "Edges", "outofcontrol" },
	{ 965906, "Burnt parchment edges", "Edges", "penandinkoverlay" },
	{ 965907, "Burnt parchment edges (smaller)", "Edges", "penandinkoverlay_512" },
	{ 985799, "Grey fog", "Smoke and clouds", "outlinemagicscroll" },
	{ 1273707, "White crackling veins (Demon Hunter)", "Lightning", "dh_demonvisionscroll" },
	{ 1305137, "Olive blotchy cells (Demon Hunter)", "Nature and fel", "dh_demonvisionfire" },
	{ 1305138, "Wispy frame, curls at the bottom", "Edge masks", "dh_demonvisionfiremask" },
	{ 1610628, "Dark fade from the top", "Other", "vignette_t" },
	{ 1802909, "Soft frame, thick at the bottom", "Edge masks", "8fx_mask_fullscreen_01" },
	{ 1803988, "Soft frame, thick at the bottom (2)", "Edge masks", "mask_fullscreen_01" },
	{ 1807126, "White below a wavy line", "Other", "mask_fullscreen_01_scroll" },
	{ 2140999, "Embers and ash flakes", "Fire", "fullscreeneffect_blend_2140999" },
	{ 2144748, "Frame open at the top", "Edge masks", "mask_fullscreen_02" },
	{ 2176482, "Dark from one side (BfA menu)", "Edges", "ui_battleforazeroth_vignette01" },
	{ 2199089, "Green water ripples", "Nature and fel", "fullscreeneffect_2199089" },
	{ 2199924, "Grey-blue water ripples", "Water and ice", "fullscreeneffect_blend_2199924" },
	{ 2199926, "Grey ripples", "Water and ice", "fullscreeneffect_blend_2199926" },
	{ 2199927, "Frosty ragged frame", "Edge masks", "fullscreeneffect_blend_2199927" },
	{ 2202396, "Soft rounded frame", "Edge masks", "mask_fullscreen_03" },
	{ 2202483, "Pale blue blurry blobs", "Water and ice", "fullscreeneffect_blend_2202483" },
	{ 2202649, "Bright cyan blobs", "Water and ice", "fullscreeneffect_blend_2202649" },
	{ 2395778, "Amber flame wisps", "Fire", "fullscreeneffect_2395778" },
	{ 2396780, "Gold water ripples", "Water and ice", "fullscreeneffect_blend_2396780" },
	{ 2510375, "White below a wavy line (2)", "Other", "mask_fullscreen_01_scroll_a" },
	{ 2530675, "White below a wavy line (3)", "Other", "mask_fullscreen_01_scroll_a2" },
	{ 2735672, "Mint green water ripples", "Water and ice", "fullscreeneffect_2735672" },
	{ 3185817, "Faint red swirl round an oval (N'Zoth)", "Edges", "8fx_nzothmental_sanity_cameraattach_3185817" },
	{ 3186659, "Red cracked eye, left of the middle (N'Zoth)", "Other", "8fx_nzothmental_sanityheavy_cameraattach_3186659" },
	{ 3509149, "Grey sideways streaks", "Soul (Shadowlands)", "9fx_soul_camera_vignette_3509149" },
	{ 3509152, "Ghostly face", "Soul (Shadowlands)", "9fx_soul_camera_vignette_3509152" },
	{ 3522951, "Blue lightning veins on blue", "Lightning", "fullscreeneffect_blend_3522951" },
	{ 3522953, "Blue lightning veins", "Lightning", "fullscreeneffect_3522953" },
	{ 3522955, "Blue frame open at the top", "Edge masks", "fullscreeneffect_blend_3522955" },
	{ 3535775, "Black round an oval (barrel hole)", "Edges", "8fx_freehold_barrelhole_camera_3535775" },
	{ 3604146, "White from the right, streaky", "Other", "fx_fxtestscreeneffectsk_aura_3604146" },
	{ 3728762, "Grey sideways streaks (2)", "Soul (Shadowlands)", "9fx_soul_camera_vignette_3728762" },
	{ 3728763, "Small blue wisps in the middle", "Soul (Shadowlands)", "9fx_soul_camera_vignette_3728763" },
	{ 3728764, "Grey water ripples", "Water and ice", "9fx_soul_camera_vignette_3728764" },
	{ 3728765, "Upright bright band, streaks to the right", "Soul (Shadowlands)", "9fx_soul_camera_vignette_3728765" },
	{ 3728766, "Ghostly face (2)", "Soul (Shadowlands)", "9fx_soul_camera_vignette_3728766" },
	{ 3749296, "White sideways band", "Other", "fx_fxtestscreeneffectsk_aura_3749296" },
	{ 3846655, "Dark top corners (Shadowlands menu)", "Edges", "ui_shadowlands_vignette01" },
	{ 4237661, "Thin white curves (knotwork-like)", "Lines and shapes", "fullscreeneffect_blend_4237661" },
	{ 4237662, "Gold marble with sparkles", "Holy and gold", "fullscreeneffect_4237662" },
	{ 4325579, "Faint curves (knotwork-like)", "Lines and shapes", "fullscreeneffect_blend_4325579" },
	{ 4383351, "Rays in from the edges", "Edge masks", "fullscreeneffect_blend_4383351" },
	{ 4417751, "Teal wavy lines", "Water and ice", "fullscreeneffect_blend_4417751" },
	{ 4541185, "Grey wavy wisps", "Smoke and clouds", "fullscreeneffect_4541185" },
	{ 4541187, "Soft rounded frame (wide)", "Edge masks", "fullscreeneffect_blend_4541187" },
	{ 4541189, "Grey wavy folds", "Smoke and clouds", "fullscreeneffect_blend_4541189" },
	{ 4630641, "Brown dirt", "Other", "fullscreeneffect_blend_4630641" },
	{ 4741748, "Grey and white blotches", "Smoke and clouds", "fullscreeneffect_4741748" },
	{ 4741750, "Dark blue night sky, faint stars", "Space", "fullscreeneffect_blend_4741750" },
	{ 4741753, "Purple and blue swirl", "Space", "fullscreeneffect_blend_4741753" },
	{ 4876486, "Lava cracks", "Fire", "fullscreeneffect_4876486" },
	{ 5198840, "Green speckles", "Nature and fel", "fullscreeneffect_blend_5198840" },
	{ 5201310, "Orange wavy lines with specks", "Holy and gold", "fullscreeneffect_blend_5201310" },
	{ 5332772, "Starry nebula", "Space", "fullscreeneffect_blend_5332772" },
	{ 5332774, "Teal with white waves", "Water and ice", "fullscreeneffect_blend_5332774" },
	{ 5371262, "Dark grey soft folds", "Other", "fullscreeneffect_blend_5371262" },
	{ 5373358, "Small leaves in rows", "Other", "fx_fxtestscreeneffectsk_aura_5373358" },
	{ 5556140, "Dark grey veil, darker at the bottom", "Other", "7fx_soulengine_soulwrap_camera_vignette_5556140" },
	{ 5636771, "Pale gold wavy stripes", "Holy and gold", "fullscreeneffect_blend_5636771" },
	{ 5636772, "Pale gold wavy stripes (2)", "Holy and gold", "fullscreeneffect_5636772" },
	{ 5680179, "Green with yellow glows", "Nature and fel", "fullscreeneffect_5680179" },
	{ 5726057, "Cobwebs", "Lines and shapes", "fullscreeneffect_5726057" },
	{ 5737247, "White clouds with dark specks", "Smoke and clouds", "fullscreeneffect_blend_5737247" },
	{ 5737249, "Grey with dark dashes", "Other", "fullscreeneffect_5737249" },
	{ 5737251, "Pale pink with dark dashes", "Other", "fullscreeneffect_blend_5737251" },
	{ 5857660, "Dark purple swirl", "Space", "fullscreeneffect_blend_5857660" },
	{ 5857669, "Purple swirl with stars", "Space", "fullscreeneffect_5857669" },
	{ 5857689, "Soft frame, wavy bottom", "Edge masks", "fullscreeneffect_blend_5857689" },
	{ 5948583, "Round darkening (War Within menu)", "Edges", "ui_mainmenu_warwithin_vignette" },
	{ 6214875, "Dark grey wavy streaks", "Water and ice", "fullscreeneffect_blend_6214875" },
	{ 6214876, "Thin lilac waves on dark", "Water and ice", "fullscreeneffect_blend_6214876" },
	{ 6214877, "Streaky frame", "Edge masks", "fullscreeneffect_blend_6214877" },
	{ 6225095, "White petals in clumps", "Other", "fx_fxtestscreeneffectbrennan_aura_6225095" },
	{ 6225363, "Ragged frame", "Edge masks", "fullscreeneffect_blend_6225363" },
	{ 6225364, "Dark green moss", "Nature and fel", "fullscreeneffect_6225364" },
	{ 6225365, "White clouds", "Smoke and clouds", "fullscreeneffect_blend_6225365" },
	{ 6225366, "Thorny green vines", "Nature and fel", "fullscreeneffect_blend_6225366" },
	{ 6385681, "Lime glow from the bottom", "Other", "fx_fxtestscreeneffectsk_aura_6385681" },
	{ 6907568, "Grey clouds, cyan and lilac tints", "Smoke and clouds", "fullscreeneffect_blend_6907568" },
	{ 6907571, "Pale yellow clouds", "Holy and gold", "fullscreeneffect_blend_6907571" },
	{ 6996935, "Grey flowing smoke", "Smoke and clouds", "fullscreeneffect_blend_6996935" },
	{ 6996936, "Blue swirl with stars", "Space", "fullscreeneffect_6996936" },
	{ 7262880, "White fade from the top", "Other", "cameravignette_7262880" },
	{ 7339122, "Blue water ripples, orange patches", "Water and ice", "fullscreeneffect_blend_7339122" },
	{ 7352941, "Soft frame (3)", "Edge masks", "fullscreeneffect_blend_7352941" },
	{ 7550812, "Round darkening, blue and purple (Midnight menu)", "Edges", "ui_mainmenu_midnight_vignette" },
	{ 7713391, "Small upright rectangle (a UI mask)", "Other", "fullscreeneffect_blend_7713391" },
	{ 7713861, "Big centered rectangle (a UI mask)", "Other", "fullscreeneffect_blend_7713861" },
}
local scout, scoutAt, scoutBlend = nil, 0, false
function ns.ScoutGameEdges(arg)
	if arg == "off" then
		if scout then scout:Hide() end
		ns.Print("game edges: off")
		return
	end
	if not scout then
		scout = CreateFrame("Frame", nil, UIParent)
		scout:SetAllPoints(UIParent)
		scout:SetFrameStrata("BACKGROUND")
		scout:EnableMouse(false)
		scout.tex = scout:CreateTexture(nil, "ARTWORK")
		scout.tex:SetAllPoints()
	end
	local number = tonumber(arg)
	if arg == "blend" then
		scoutBlend = not scoutBlend
	elseif arg == "back" then
		scoutAt = scoutAt - 1
	elseif number then
		scoutAt = number
	else
		scoutAt = scoutAt + 1
	end
	scoutAt = (scoutAt - 1) % #EDGE_SCOUT + 1
	local entry = EDGE_SCOUT[scoutAt]
	local loaded = FileLoads(entry[1])
	scout.tex:SetTexture(loaded and entry[1] or nil)
	scout.tex:SetBlendMode(scoutBlend and "BLEND" or "ADD")
	scout:Show()
	ns.Print(("game edge %d of %d: %s (%d), %s%s"):format(scoutAt, #EDGE_SCOUT, entry[2], entry[1],
		scoutBlend and "as paint" or "as light", loaded and "" or ", not on this client"))
	ns.Print("  next: /cine debug gameedge; also back, a number, blend (light or paint), off")
end

-- Edge masks among them (white, the edge in their alpha), for the tester's
-- layers: soft frames, ragged ones, open on one side, a starburst.
local EDGE_MASKS = {
	{ 1802909, "Soft frame, thick at the bottom" }, { 1803988, "Soft frame, thick at the bottom (2)" },
	{ 7352941, "Soft frame (3)" },
	{ 2202396, "Soft rounded frame" }, { 4541187, "Soft rounded frame (wide)" },
	{ 1305138, "Wispy frame, curls at the bottom" }, { 2199927, "Frosty ragged frame" }, { 6225363, "Ragged frame" },
	{ 5857689, "Soft frame, wavy bottom" }, { 6214877, "Streaky frame" }, { 2144748, "Frame open at the top" },
	{ 3522955, "Blue frame open at the top" }, { 4383351, "Rays in from the edges" },
}

-- /cine debug texreel [masks] [shots] [seconds] [from] | pause | off: plays
-- the list above as a slideshow to record, each over the whole screen, first
-- on black then on grey (what's dark or see-through in it shows), with its
-- number, file, name and the name it has here, and the time left. masks:
-- only the edge masks; shots: a screenshot of each half. Seconds each
-- (default 6, 4 with shots), from: the list number to start at.
local reel
function ns.TextureReel(arg)
	arg = arg or ""
	if arg == "off" then
		if reel then reel:Hide() end
		ns.Print("texture reel: off")
		return
	end
	if arg == "pause" then
		if reel and reel:IsShown() then
			reel.paused = not reel.paused
			ns.Print("texture reel: " .. (reel.paused and "paused" or "playing"))
		end
		return
	end
	if not reel then
		reel = CreateFrame("Frame", nil, UIParent)
		reel:SetAllPoints(UIParent)
		reel:SetFrameStrata("FULLSCREEN_DIALOG")
		reel:EnableMouse(false)
		reel.back = reel:CreateTexture(nil, "BACKGROUND")
		reel.back:SetAllPoints()
		reel.tex = reel:CreateTexture(nil, "ARTWORK")
		reel.tex:SetAllPoints()
		local box = reel:CreateTexture(nil, "OVERLAY")
		box:SetColorTexture(0, 0, 0, 0.75)
		box:SetPoint("TOPLEFT", 0, 0)
		box:SetPoint("TOPRIGHT", 0, 0)
		box:SetHeight(96)
		reel.lines = {}
		for i, font in ipairs({ "GameFontNormalHuge", "GameFontHighlightLarge", "GameFontHighlightLarge" }) do
			local line = reel:CreateFontString(nil, "OVERLAY")
			line:SetFontObject(font)
			line:SetPoint("TOP", 0, -10 - (i - 1) * 28)
			reel.lines[i] = line
		end
		local barBack = reel:CreateTexture(nil, "OVERLAY")
		barBack:SetColorTexture(0.2, 0.2, 0.2, 0.9)
		barBack:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
		barBack:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
		barBack:SetHeight(4)
		reel.bar = reel:CreateTexture(nil, "OVERLAY", nil, 1)
		reel.bar:SetColorTexture(1, 0.82, 0, 1)
		reel.bar:SetPoint("TOPLEFT", barBack, "TOPLEFT")
		reel.bar:SetHeight(4)
		reel.barBack = barBack
		reel:SetScript("OnUpdate", function(self, elapsed)
			if self.paused then return end
			self.left = self.left - elapsed
			local each = self.each
			while self.left <= 0 do
				self.at = self.at + 1
				if self.at > #self.list then
					self:Hide()
					ns.Print("texture reel: done")
					return
				end
				self.left = self.left + each
				self.shown = nil
			end
			local entry = self.list[self.at]
			local onGrey = self.left <= each / 2
			if self.shown ~= entry or self.onGrey ~= onGrey then
				self.shown, self.onGrey, self.snapped = entry, onGrey, false
				local loaded = FileLoads(entry[1])
				self.tex:SetTexture(loaded and entry[1] or nil)
				self.tex:SetBlendMode("BLEND")
				local g = onGrey and 0.5 or 0
				self.back:SetColorTexture(g, g, g, 1)
				local index = self.numbers[self.at]
				self.lines[1]:SetText(("%d of %d   |   file %d   |   %s%s"):format(index, self.total, entry[1],
					entry[4] or "", loaded and "" or "   |cffff6060NOT ON THIS CLIENT|r"))
				self.lines[2]:SetText(("Named here: \"%s\"   (%s)"):format(entry[2], entry[3] or "edge mask"))
			end
			local remaining = (#self.list - self.at) * each + self.left
			self.lines[3]:SetText(("%s   |   next in %.1fs   |   %d:%02d left"):format(onGrey and "on grey" or
				"on black", self.left, math.floor(remaining / 60), math.floor(remaining % 60)))
			self.bar:SetWidth(math.max(1, self.barBack:GetWidth() * (1 - remaining / (#self.list * each))))
			-- (shots: one a little into each half, once the text has drawn)
			local into = (onGrey and each / 2 or each) - self.left
			if self.shots and not self.snapped and into >= math.min(1, each / 4) then
				self.snapped = true
				Screenshot()
			end
		end)
		reel:SetScript("OnHide", function()
			if ActionStatus then ActionStatus:SetAlpha(1) end
		end)
	end
	local words = {}
	for word in arg:gmatch("%S+") do words[#words + 1] = word end
	local masksOnly, shots = false, false
	while words[1] == "masks" or words[1] == "shots" do
		if table.remove(words, 1) == "masks" then masksOnly = true else shots = true end
	end
	local each = math.max(tonumber(words[1]) or (shots and 4 or 6), 1)
	local from = math.max(math.floor(tonumber(words[2]) or 1), 1)
	-- The masks by their number in the big list, so one id names each.
	-- (Only the files this client has: the rest would be bright green.)
	local list, numbers, missing = {}, {}, 0
	for i, entry in ipairs(EDGE_SCOUT) do
		local isMask = false
		for _, mask in ipairs(EDGE_MASKS) do
			if mask[1] == entry[1] then isMask = true end
		end
		if (not masksOnly or isMask) and i >= from then
			if FileLoads(entry[1]) then
				list[#list + 1] = entry
				numbers[#list] = i
			else
				missing = missing + 1
			end
		end
	end
	if missing > 0 then ns.Print(("texture reel: %d left out, not on this client"):format(missing)) end
	if #list == 0 then
		ns.Print("texture reel: nothing from " .. from)
		return
	end
	reel.list, reel.numbers, reel.total, reel.each = list, numbers, #EDGE_SCOUT, each
	reel.at, reel.left, reel.shown, reel.paused, reel.shots = 1, each, nil, false, shots
	reel:Show()
	-- (the game's "Screen captured" would land in the next shot)
	if shots and ActionStatus then ActionStatus:SetAlpha(0) end
	local total = #list * each
	ns.Print(("texture reel: %d textures, %ds each (half on black, half on grey), %d:%02d in all%s")
		:format(#list, each, math.floor(total / 60), total % 60,
			shots and (", a screenshot of each half (%d)"):format(#list * 2) or ""))
	ns.Print("  /cine debug texreel pause, or off")
end

function ns.SetVitalsSecretAlpha(frame)
	local curve = SecretCurve()
	if curve then
		pcall(function() frame:SetAlpha(UnitHealthPercent("player", true, curve)) end)
	end
end

-- The Style hub's Vitals Vision page: the theme, our art and Blizzard's, the
-- shadow and the effects, a preview at the top with the edges closing in.
-- When it shows: the Visions hub's Vitals Vision page.
function ns.CreateVitalsStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Vitals Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the low-health edges look: the theme, our art and Blizzard's, the shadow and the effects. When " ..
		"they show: the Visions hub's Vitals Vision page. Changes show at once in the preview."])
	local preview
	local function Changed()
		ns.RefreshLowHealth()
		if preview and preview.drawer then preview.drawer.shown = nil end
	end
	local switch = kit.PageSwitch(content, "lowHealthStyle", L["Enable page"],
		L["On: the edges look as this page says. Off: as they start out (each setting keeps its value for " ..
		"when you turn this back on)."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "lowHealthStyle")
	local On = rows.On
	local function Button(parent, text, width, tip, onClick)
		local button = ns.PanelButton(parent)
		button:SetSize(width, 22)
		button:SetText(text)
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", onClick)
		button.Refresh = function() end
		button.pageSwitch = false -- (works with the page off)
		kit.AddControl(button)
		return button
	end

	-- The preview: the screen's shape, the scene behind, the edges drawn on
	-- it as on the screen, at the health its buttons set (or the test's).
	local PREVIEW_W = 480
	local sim = { health = 0.2, last = 0.2, adding = 0, lift = 0 }
	local buttons = CreateFrame("Frame", nil, content)
	buttons:SetSize(PREVIEW_W, 24)
	stack:Add(buttons, "label")
	local last
	for _, info in ipairs({
		{ L["Low health"], L["Your health at 20% in the preview."], function() sim.test, sim.health = nil, 0.2 end },
		{ L["Big hit"], L["A hit taking 15% of your health in the preview."],
			function() sim.test, sim.health = nil, math.max(0, sim.health - 0.15) end },
		{ L["Heal"], L["Full health in the preview: the edges lift."], function() sim.test, sim.health = nil, 1 end },
		{ L["Test"], L["The test in the preview: from full health to 10% in hits, then back."],
			function() sim.test = GetTime() end },
	}) do
		local button = Button(buttons, info[1], 90, info[2], info[3])
		if last then button:SetPoint("LEFT", last, "RIGHT", 6, 0) else button:SetPoint("LEFT") end
		last = button
	end
	-- (Scene beside them: StylePages.lua)
	ns.StyleSceneButton(content, kit.Tooltip, kit.AddControl):SetPoint("LEFT", last, "RIGHT", 6, 0)

	preview = CreateFrame("Frame", nil, content)
	preview:SetSize(PREVIEW_W, 270)
	if preview.SetClipsChildren then preview:SetClipsChildren(true) end
	local stage = CreateFrame("Frame", nil, preview)
	stage:SetAllPoints()
	stage:SetFrameLevel(preview:GetFrameLevel() + 2)
	local caption = kit.Label(preview, "GameFontDisableSmall", L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	local healthText = kit.Label(preview, "GameFontHighlightSmall", "")
	healthText:SetPoint("TOPRIGHT", -6, -5)
	healthText.searchSkip = true
	preview.drawer = NewDrawer(stage)
	function preview:Refresh()
		if not self:IsVisible() then return end -- (the kit refreshes every page's controls)
		local width, height = UIParent:GetWidth(), UIParent:GetHeight()
		self:SetHeight(math.floor(PREVIEW_W * height / math.max(width, 1) + 0.5))
		ns.StyleScene(self)
		self.drawer.shown = nil
	end
	-- As Update does for the screen, at the preview's health.
	preview:SetScript("OnUpdate", function(self, elapsed)
		if not db then return end
		local d, look = self.drawer, Look()
		local wanted = WantedTheme(look)
		look = ThemeLook(look, wanted)
		if wanted ~= d.shown then
			SyncThemeLook(wanted)
			UseTheme(d, wanted, look)
		end
		local share = sim.health
		if sim.test then
			local t = GetTime() - sim.test
			if t > 10 then
				sim.test = nil
			else
				local steps = math.floor(8 / TEST_HIT_EVERY)
				share = 1 - 0.9 * math.min(1, math.ceil(math.min(1, t / 8) * steps - 0.001) / steps)
			end
		end
		local lost = math.max(0, sim.last - share)
		sim.last = share
		sim.adding = sim.adding + lost
		local hit = lost >= db.lowHealthFlashHit or sim.adding >= db.lowHealthFlashAdded
		if hit then
			sim.adding = 0
			if look.lowHealthFlash then d.flash = 1 end
		end
		Sparking(d, look, elapsed, hit)
		d.flash = Approach(d.flash, 0, elapsed, FLASH_TIME)
		local target = LevelAt(share)
		if target >= d.level then
			d.level = Approach(d.level, target, elapsed, db.lowHealthFollow)
			sim.lift = 0
		else
			local wantedSpeed = math.min(db.lowHealthLiftSpeed, math.sqrt(2 * LIFT_EASE * (d.level - target)))
			sim.lift = math.min(wantedSpeed, sim.lift + LIFT_EASE * elapsed)
			d.level = math.max(target, d.level - sim.lift * elapsed)
		end
		local k, heart = Beat(d, look, elapsed)
		Apply(d, look, k, 1, heart, false)
		healthText:SetText(("%s %d%%"):format(L["Health"], math.floor(share * 100 + 0.5)))
	end)
	preview.pageSwitch = false
	stack:Add(preview, "label")
	kit.AddControl(preview)

	local tests = CreateFrame("Frame", nil, content)
	tests:SetSize(PREVIEW_W, 24)
	stack:Add(tests, "label")
	-- (On: the test over and over on the screen, till it's pressed again.)
	local loop = Button(tests, "", 200, L["Your health falls as the Vitals Vision page's Test says, on the " ..
		"screen, again and again till you press this again. Close the settings to see it all."], function()
			ns.LoopLowHealthTest()
			kit.Refresh()
		end)
	loop:SetPoint("LEFT")
	loop.Refresh = function(self)
		local on = ns.LowHealthTestLooping()
		self:SetText(L["Test on the screen"] .. ": " .. (on and L["On"] or L["Off"]))
		ns.StyleToggle(self, on)
	end
	loop:Refresh()


	-- A row picking from a list: its name, then a dropdown, or (no dropdowns
	-- on this client) a button stepping through it.
	local function Pick(key, labelText, Choices, tip, test)
		local name = stack:Add(kit.Label(content, "GameFontHighlight", labelText), "label")
		name:SetSize(150, 30)
		name:SetJustifyV("MIDDLE")
		local picker = kit.Dropdown and kit.Dropdown(content, key, Choices, 280, Changed)
		if not picker then
			picker = ns.PanelButton(content)
			picker:SetSize(280, 22)
			picker:SetScript("OnClick", function(self)
				local list, value = Choices(), ns.GetDB()[key]
				for i, choice in ipairs(list) do
					if choice.value == value then
						ns.GetDB()[key] = list[i % #list + 1].value
						break
					end
				end
				Changed()
				self:Refresh()
			end)
			picker.Refresh = function(self)
				local value = ns.GetDB()[key]
				for _, choice in ipairs(Choices()) do
					if choice.value == value then self:SetText(choice.text) end
				end
			end
			kit.AddControl(picker)
		end
		picker:SetPoint("LEFT", name, "LEFT", 160, 0)
		kit.Tooltip(picker, tip)
		kit.GreyUnless(picker, test or On)
		return picker, name
	end

	-- The theme: Auto (and what it picks for you), or any of them, by class
	-- and spec. (Game art's themes: no longer offered, Blizzard art being a
	-- layer of its own; one already picked still works.)
	local function ThemeName(key)
		local info = ns.LOW_HEALTH_THEME[key]
		return info and L[info.name] or key
	end
	local function AutoText()
		return L["Auto"] .. ": " .. ThemeName(ns.LowHealthAutoTheme())
	end
	local function Choices() -- (flat: the button that steps through them)
		local list = { { value = "auto", text = AutoText() } }
		for _, info in ipairs(ns.LOW_HEALTH_THEMES) do
			list[#list + 1] = { value = info.key, text = L[info.name] }
		end
		return list
	end
	local themePicker, themeName = Pick("lowHealthTheme", L["Theme:"], Choices,
		L["The look: Auto picks your class and spec's (by the talent tree you've put most into, on clients " ..
		"without specs), or pick any. Each class has a theme for each spec."])
	-- (Just after its name, not in line with the rows' choices below.)
	themePicker:ClearAllPoints()
	themePicker:SetPoint("LEFT", themeName, "LEFT", themeName:GetStringWidth() + 10, 0)
	if themePicker.SetupMenu then
		-- By class: Auto, then a submenu for each class (in its colour), each
		-- spec in it with its theme. (Replaces the flat list the helper made.)
		local RETAIL = " |cff999999(" .. L["retail"] .. ")|r"
		local function PickTheme(key)
			ns.GetDB().lowHealthTheme = key
			SyncThemeLook(WantedTheme()) -- (its defaults on the page before it shows)
			Changed()
			kit.Refresh()
		end
		local function Picked(key)
			local d = ns.GetDB()
			return d ~= nil and d.lowHealthTheme == key
		end
		local function ClassName(class)
			local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class[1]] or L[class[2]]
			local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class[1]]
			if color then
				name = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name)
			end
			return name .. (class.retail and RETAIL or "")
		end
		themePicker:SetupMenu(function(_, root)
			root:CreateRadio(AutoText(), function() return Picked("auto") end, function() PickTheme("auto") end)
			root:CreateDivider()
			for _, class in ipairs(ns.LOW_HEALTH_MENU) do
				local menu = root:CreateButton(ClassName(class))
				for _, spec in ipairs(class[3]) do
					local key = spec[2]
					menu:CreateRadio(L[spec[1]] .. ": " .. ThemeName(key) .. (spec.retail and RETAIL or ""),
						function() return Picked(key) end, function() PickTheme(key) end)
				end
			end
		end)
	end

	-- Strength, on the theme's line. (After the dropdown's edge: its own text
	-- is inside it, where the boxes would go after.)
	local themeEnd = CreateFrame("Frame", nil, content)
	themeEnd:SetSize(1, 22)
	themeEnd:SetPoint("LEFT", themePicker, "RIGHT", -10, 0)
	rows.Boxes(themeEnd):Box(L["Strength"], "lowHealthStrength", 0, 100, 5, "%d", 100, L["How strong it all is: " ..
		"at 50% as the settings below say (and the theme's own); less, lighter, down to nothing at 0%; more, up " ..
		"to double. It scales the darkness, the shadow's reach, the throb and both arts' opacity. The color " ..
		"grade (the world draining toward grey, tinged with the theme's color) is as strong as this says."], nil,
		"%")

	-- The art, in two layers: ours, and Blizzard's (the game's own screen
	-- effects) over it, each on its own or both.
	local Ours, Theirs = On, On
	-- (Each shows while its opacity's above 0.) What's each art's own, then
	-- what's both's: how far in they come, the shadow, the heartbeat.
	-- Each art's opacity: a slider (the settings' own), its tick beside it.
	local function Opacity(key, tip, test)
		local slider = stack:Add(kit.Slider(content, key, L["Opacity"], 0, 100, 1, "%d%%", 100, Changed), "slider")
		kit.Tooltip(slider, tip)
		kit.GreyUnless(slider, test)
		return slider
	end
	local function TickBeside(slider, key, label, tip, test)
		local check = kit.Check(content, key, label, tip, function(value)
			ns.GetDB()[key] = value
			Changed()
			kit.Refresh()
		end)
		check:SetPoint("LEFT", slider, "RIGHT", 30, 0)
		kit.GreyUnless(check, test or On)
		return check
	end
	stack:Header(content, L["Our art"])
	TickBeside(Opacity("lowHealthBloodAlpha", L["The theme's art soaking in from the edges as they close in " ..
		"(blood, smoke, a glow...)."], Ours), "lowHealthSparks", L["Sparks"], L["The theme's sparks (motes, " ..
		"stars, lightning) and the haze drifting over the edges."], Ours)
	kit.GreyUnless(stack:Add(kit.Slider(content, "lowHealthBloodReach", L["Reach"], 0, 100, 5, "%d%%", 100,
		Changed), "slider"), Ours)

	stack:Header(content, L["Blizzard art"])
	TickBeside(Opacity("lowHealthGameAlpha", L["The game's own screen effects (fire, frost, lightning, " ..
		"ripples...) cut to an edge, closing in with ours, over it. Each theme has one picked to go with it. " ..
		"Classic has only a few of them."], Theirs), "lowHealthRipple", L["Ripple wave"], L["A wave of the " ..
		"game's art creeping in from past the edges on each heartbeat (each second without one). With Blizzard " ..
		"art, or a Game art theme."])
	kit.GreyUnless(stack:Add(kit.Slider(content, "lowHealthGameReach", L["Reach"], 0, 100, 5, "%d%%", 100,
		Changed), "slider"), Theirs)
	local function PatternName(file)
		local pattern = ns.LOW_HEALTH_BLIZZ_PATTERN[file]
		return pattern and L[pattern[2]] or tostring(file)
	end
	Pick("lowHealthGamePattern", L["Pattern:"], function()
		local pick = db and WantedTheme().theirs -- (the menu's first made before settings load)
		local list = { { value = "auto", text = L["Theme's pick"] .. ": " .. PatternName(pick and pick[1] or ns.LOW_HEALTH_BLIZZ_EDGE) } }
		for _, pattern in ipairs(ns.LOW_HEALTH_BLIZZ_PATTERNS) do
			if FileLoads(pattern[1]) then
				list[#list + 1] = { value = pattern[1], text = L[pattern[2]], texture = pattern[1],
					tint = pattern.own and WHITE or nil }
			end
		end
		return list
	end, L["The game's effect shown. Theme's pick: the one picked to go with your theme (it changes with it)."],
		Theirs)
	Pick("lowHealthGameMask", L["Edge:"], function()
		local list = { { value = "auto", text = L["The pattern's own"] }, { value = "none", text = L["None"] } }
		for _, mask in ipairs(ns.LOW_HEALTH_BLIZZ_MASKS) do
			if FileLoads(mask[1]) then list[#list + 1] = { value = mask[1], text = L[mask[2]] } end
		end
		return list
	end, L["What cuts the pattern to an edge, so it stays round the screen's sides. None: the pattern over " ..
		"all of the screen (an edge already, like the red one, needs none)."], Theirs)
	Pick("lowHealthGameColors", L["Colors:"], function()
		return { { value = "auto", text = L["The pattern's own choice"] },
			{ value = "theme", text = L["The theme's color"] }, { value = "own", text = L["Its own colors"] } }
	end, L["The theme's color: the effect turned grey and tinted to match your theme. Its own colors: as " ..
		"the game draws it."], Theirs)

	stack:Header(content, L["Both"])
	local shadowBoxes = rows.Boxes()
	shadowBoxes:Box(L["Shadow reach"], "lowHealthReach", 10, 50, 1, "%d", 100,
		L["How much of the screen the dark edges cover at full."], nil, "%")
	shadowBoxes:Box(L["Darkness"], "lowHealthDark", 0, 100, 5, "%d", 100, L["How dark the edges are at full."], nil, "%")
	shadowBoxes:Box(L["Shadow tint"], "lowHealthRed", 0, 100, 5, "%d", 100,
		L["0%: black, like the death screen. 100%: the theme's own color (deep red for blood)."], nil, "%")

	local function Beating(d) return On(d) and d.lowHealthPulse end
	local pulse = rows.Check("lowHealthPulse", L["Heartbeat"],
		L["The edges throb with a heartbeat, quicker as you weaken."])
	rows.Boxes(pulse):Box(L["Throb"], "lowHealthPulseAmount", 0, 60, 5, "%d", 100,
		L["How much further in each beat pushes the edges (some themes throb more or less)."], Beating, "%")
	local bpm = rows.Boxes()
	bpm:Box(L["Beats a minute as they start"], "lowHealthBpmSlow", 30, 120, 5, "%d", 1, nil, Beating)
	bpm:Box(L["At full"], "lowHealthBpmFast", 60, 200, 5, "%d", 1, L["Beats a minute at full"], Beating)
	rows.Check("lowHealthFlash", L["Flash on big hits"],
		L["The edges flash in the theme's color when a hit takes a lot at once. (What counts as big: the " ..
		"Vitals Vision page.)"])

	-- (Dev copy: DEV SET DEFAULT. This page's settings, as they show now, become
	-- the picked theme's own defaults (CinematicDB.vitalsThemeEdits, to be
	-- written into LowHealthThemes.lua), and the page goes back to its
	-- defaults, so it follows the theme. Not with Auto: a theme must be picked.)
	if ns.isDev then
		local LOOK_KEYS = { "lowHealthReach", "lowHealthDark", "lowHealthRed", "lowHealthBloodAlpha", "lowHealthBloodReach", "lowHealthGameReach",
			"lowHealthGamePattern", "lowHealthGameMask", "lowHealthGameColors", "lowHealthGameAlpha", "lowHealthSparks",
			"lowHealthRipple", "lowHealthPulse", "lowHealthPulseAmount", "lowHealthBpmSlow", "lowHealthBpmFast",
			"lowHealthFlash" }
		local function Picked()
			local d = ns.GetDB()
			local key = d and d.lowHealthTheme
			return key ~= "auto" and key ~= "autogame" and ns.LOW_HEALTH_THEME[key] and key or nil
		end
		local devRow = CreateFrame("Frame", nil, content)
		devRow:SetSize(PREVIEW_W, 30)
		stack:Add(devRow, "label")
		local devSet = ns.PanelButton(devRow)
		devSet:SetSize(140, 22)
		devSet:SetText("DEV SET DEFAULT")
		devSet:SetPoint("LEFT")
		kit.Tooltip(devSet, "Dev copy: this page's settings, as they show now, become the picked theme's own " ..
			"defaults, and the page goes back to its defaults so it follows the theme. Then ask Claude to write " ..
			"them into LowHealthThemes.lua. Pick a theme first: not with Auto.")
		devSet:SetScript("OnClick", function()
			local key = Picked()
			if not key then return end
			local d, theme, look, count = ns.GetDB(), ns.LOW_HEALTH_THEME[key], {}, 0
			for _, setting in ipairs(LOOK_KEYS) do
				local value = d[setting]
				if value == DEFAULTS[setting] and theme.look and theme.look[setting] ~= nil then
					value = theme.look[setting]
				end
				if value ~= DEFAULTS[setting] then
					look[setting] = value
					count = count + 1
				end
				d[setting] = DEFAULTS[setting]
			end
			CinematicDB.vitalsThemeEdits = CinematicDB.vitalsThemeEdits or {}
			local edits = CinematicDB.vitalsThemeEdits[key] or {}
			edits.look = count > 0 and look or false
			CinematicDB.vitalsThemeEdits[key] = edits
			ThemeEdited(key)
			db.lowHealthFromTheme = nil -- (the page's at its defaults: the theme's onto it)
			SyncThemeLook(theme, true)
			Changed()
			kit.Refresh()
			ns.Print(("Vitals Vision: %s's defaults set, %d settings away from the usual."):format(theme.name, count))
		end)
		devSet.Refresh = function(self) self:SetEnabled(Picked() ~= nil) end
		devSet.pageSwitch = false
		kit.AddControl(devSet)
	end

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Vitals Style", L["Vitals Vision"])
end

-- The Vitals Vision page (in the Visions hub): its switch, the theme and a
-- quick test, then when it shows, how fast, its look, the heartbeat and hits,
-- and the test's settings. Options.lua calls it with the page helpers it shares.
function ns.CreateVitalsVisionPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Vitals Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["Your health at a glance, without the portrait: as it drops, the screen's edges close in, with your " ..
		"theme's art soaking in from them (blood, smoke, a glow in its color), a " ..
		"heartbeat that quickens as you weaken and a flash on big hits. Auto picks a theme for your class " ..
		"and spec. The death screen takes over if you die."])
	ns.StyleLink(content, title, "Vitals Style", L["Opens the Style hub's Vitals Vision page: its theme, our " ..
		"art and Blizzard's, the shadow and the heartbeat."], kit.Tooltip)
	local function Changed()
		ns.RefreshLowHealth()
	end
	local switch = kit.PageSwitch(content, "lowHealth", L["Enable page"],
		L["On: everything below works as ticked. Off: none of it does, and each keeps its tick for " ..
		"when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local function Tick(key, label, tip, enabledBy)
		local check = stack:Add(kit.Check(content, key, label, tip, function(value)
			ns.GetDB()[key] = value
			Changed()
			kit.Refresh()
		end), "check")
		if enabledBy then kit.GreyUnless(check, enabledBy) end
		return check
	end
	-- Number boxes on a line of their own: { key, label, min, max, step, fmt,
	-- scale, tip, enabledBy } each (fmt as a slider's: "%d%%", the unit after the box).
	local function Boxes(...)
		local line = stack:Add(kit.BoxLine(content), "label")
		for _, box in ipairs({ ... }) do
			local key, label, minV, maxV, step, fmt, scale, tip, enabledBy = unpack(box)
			local made = line:Box(label, key, minV, maxV, step, fmt, scale, tip, Changed)
			if enabledBy then kit.GreyUnless(made, enabledBy) end
		end
		return line
	end
	local function Button(parent, text, width, tip, onClick)
		local button = ns.PanelButton(parent)
		button:SetSize(width, 22)
		button:SetText(text)
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", onClick)
		return button
	end
	local function Edges(d) return d.lowHealthEdges end
	local TEST_TIP = L["Your health falls, stays there a moment, then goes back to yours, in the theme picked. " ..
		"It works with the page off too. Close the settings to see it all."]

	-- A quick test (not a page control: it works with the page off). The look:
	-- the Style hub's Vitals Vision page (the Style button by the title).
	local quickRow = CreateFrame("Frame", nil, content)
	quickRow:SetSize(300, 26)
	stack:Add(quickRow, "label", 2)
	Button(quickRow, L["Test"], 80, TEST_TIP, ns.TestLowHealth):SetPoint("LEFT")
	stack:Continue(quickRow, "label")
	Tick("lowHealthOnlyCine", L["Only in CineMode"], L["Ticked, only while the UI is faded."], Edges)

	-- What shows your health: the screen's edges, and health bars kept faded
	-- in CineMode, fading in as your health drops.
	stack:Header(content, L["What shows"])
	Tick("lowHealthEdges", L["Screen edges"],
		L["The screen's edges close in as your health drops, with your theme's art (all the " ..
		"sections below)."])
	local BARS_TIP = "\n\n" .. L["In CineMode, a health bar faded out comes back as your health drops: hidden " ..
		"above Starts below, fading in to fully up at All the way in at."]
	Tick("lowHealthPortrait", L["Player frame"],
		L["Your player frame (portrait and health bar) fades in as your health drops."] .. BARS_TIP)
	-- (Only on clients with a personal resource display.)
	if _G.CinematicPersonalPower then
		Tick("lowHealthPrd", L["Personal resource display"],
			L["Your personal resource display (the health bar under your character) fades in as your health drops."]
			.. BARS_TIP)
	end

	stack:Header(content, L["When it shows"])
	Boxes({ "lowHealthStart", L["Starts below"], 10, 100, 5, "%d%%", 100,
			L["Your health the edges start creeping in below."] },
		{ "lowHealthFull", L["All the way in at"], 0, 90, 5, "%d%%", 100,
			L["Your health the edges are all the way in at (under Starts below)."] })
	Boxes({ "lowHealthCalm", L["Strength out of combat"], 0, 100, 5, "%d%%", 100,
		L["How strong the edges are out of a fight (eating and drinking back up, say), next to in one. Some " ..
		"clients keep your health secret in fights; there the edges only fade in and out with it."], Edges })

	stack:Header(content, L["How fast"])
	Boxes({ "lowHealthFollow", L["Close in over"], 0, 1, 0.05, "%.2fs", 1,
			L["Seconds the edges take to close all the way in when your health drops. Keep it short: it's the " ..
			"warning."], Edges },
		{ "lowHealthLiftSpeed", L["Lift speed"], 5, 200, 5, L["%d%% a second"], 100,
			L["The fastest the edges lift when you're healed, as a share of all the way each second (40%: a " ..
			"full heal takes at least 2.5 seconds). They speed up to it and slow as they settle."], Edges })

	stack:Header(content, L["Big hits"])
	Boxes({ "lowHealthFlashHit", L["A big hit takes"], 2, 40, 1, "%d%%", 100,
			L["The share of your health a hit has to take at once to count as big."], Edges },
		{ "lowHealthFlashAdded", L["Or hits adding up to"], 5, 60, 1, "%d%%", 100,
			L["Smaller hits count as a big one too once they've taken this much of your health together " ..
			"(since the last one; again each fight)."], Edges })

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Vitals Vision")
end
