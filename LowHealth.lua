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
DEFAULTS.lowHealthGrade = false    -- the whole picture drained toward a cold grey, tinged by the theme
DEFAULTS.lowHealthGradeAmount = 0.5 -- ...how far, at full
DEFAULTS.lowHealthBlood = true     -- the theme's art
DEFAULTS.lowHealthBloodAlpha = 0.9
DEFAULTS.lowHealthBloodReach = 0.7 -- how far in the art comes at full (0-1)
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

local frame, edges, body, glow, grade, driver
local ripple -- (game art only)
local gameArt -- the game's art shown, not ours
local gameArtTest -- (/cine debug gameart's, over any theme)
local sparks = {} -- (made once, reused)
local reachNow = 0 -- (the shadow's reach as last shown: sparks start about there)
local artScale = ART_OUT -- (the art's size now)
local theme, shownTheme -- (the theme wanted, and the one the textures are set up for)
local autoTheme, autoGameTheme -- (Auto's picks, ours and Game art's, until your talents change)
local level, flash, beat = 0, 0, 0 -- shown (0-1), the hit flash (0-1), heartbeat phase
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

local function WantedTheme()
	local key = db.lowHealthTheme
	if key == "autogame" then
		key = ns.LowHealthAutoGameTheme()
	elseif key == "auto" or not ns.LOW_HEALTH_THEME[key] then
		key = ns.LowHealthAutoTheme()
	end
	return ns.LOW_HEALTH_THEME[key] or ns.LOW_HEALTH_THEMES[1]
end

local function Create()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("BACKGROUND")
	frame:SetFrameLevel(0) -- (under the letterbox, like the tint and death screen)
	frame:EnableMouse(false)
	ns.AddOverlay(frame)
	body = frame:CreateTexture(nil, "BORDER")
	body:SetPoint("CENTER")
	glow = frame:CreateTexture(nil, "BORDER", nil, 1)
	glow:SetPoint("CENTER")
	glow:SetBlendMode("ADD")
	ripple = frame:CreateTexture(nil, "BORDER", nil, 1)
	ripple:SetPoint("CENTER")
	ripple:SetBlendMode("ADD")
	ripple:Hide()
	edges = ns.CreateVignette(frame)
	-- (The shadow under everything: over the art, it hid it.)
	for _, piece in pairs(edges) do
		piece:SetDrawLayer("BACKGROUND", -8)
	end
	grade = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	grade:SetAllPoints(frame)
	grade:SetTexture("Interface\\Buttons\\WHITE8X8")
	grade:SetBlendMode("MOD")
	grade:Hide()
	for i = 1, MAX_SPARKS do
		local tex = frame:CreateTexture(nil, "BORDER", nil, 2)
		tex:Hide()
		sparks[i] = { tex = tex }
	end
	frame:Hide()
	-- (Its own frame, not under UIParent, so it runs with the UI hidden too.)
	driver = CreateFrame("Frame")
	driver:Hide()
end

local function ClearSparks()
	for _, spark in ipairs(sparks) do
		spark.born = nil
		spark.tex:Hide()
	end
end

-- Sets the textures up for a theme (its art and glow).
local function UseTheme(wanted)
	shownTheme = wanted
	ClearSparks()
	body:SetPoint("CENTER") -- (a sloshing theme's rocking, undone)
	glow:SetPoint("CENTER")
	if wanted.edge and wanted.body then
		body:SetTexture(ART .. wanted.edge)
	end
	if wanted.edge and wanted.glow then
		glow:SetTexture(ART .. wanted.edge .. "Glow")
		glow:SetBlendMode("ADD")
	end
	body:SetDesaturated(false)
	body:SetBlendMode("BLEND")
	glow:SetDesaturated(false)
	ripple:Hide()
	-- (A Game art theme's, or the debug test's over any.)
	gameArt = gameArtTest or wanted.game or false
	if gameArt then
		for _, tex in ipairs({ body, glow, ripple }) do
			tex:SetTexture(GAME_EDGE)
			tex:SetDesaturated(true) -- (it's red: grey, then the theme's colour)
		end
		-- (Light on black, as the game draws it: as paint, its black middle
		-- covered the screen.)
		body:SetBlendMode("ADD")
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

local function Spark(info)
	for _, spark in ipairs(sparks) do
		if not spark.born then
			spark.info = info
			spark.born, spark.life, spark.size = GetTime(), Between(info.life), Between(info.size)
			-- (Gas stays over the edges, where it blends in: alone further in, it
			-- looked pasted on.)
			local gas = info.kind == "drift"
			spark.x, spark.y = Place(info.at, gas and reachNow * GAS_REACH or reachNow, gas)
			spark.phase = math.random() * 2 * math.pi
			spark.tex:SetTexture(ART .. info.tex)
			spark.tex:SetBlendMode(info.flat and "BLEND" or "ADD")
			-- (mirrored now and then)
			if math.random() < 0.5 then spark.tex:SetTexCoord(0, 1, 0, 1) else spark.tex:SetTexCoord(1, 0, 0, 1) end
			return
		end
	end
end

-- The sparks now. flicker: on and off, fading out; twinkle: fading in and
-- out; rise: floating up, swaying, fading in and out; drift: billowing in
-- a little toward the middle, growing, fading in slowly and out.
local function AnimateSparks(now, width, height, alpha)
	for _, spark in ipairs(sparks) do
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
				spark.tex:SetPoint("CENTER", frame, "TOPLEFT", x * width, -y * height)
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

-- k: how far in (0 none, 1 full; a little more on a beat or a flash); heart:
-- the heartbeat now (0-1).
local function Apply(k, fade, heart, secret)
	local c = math.min(1, k)
	c = c * c * (3 - 2 * c)
	local over = math.max(0, k - 1)
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local size = EDGE_START + (db.lowHealthReach - EDGE_START) * c + over * 0.1
	local alpha = math.min(1, db.lowHealthDark * c + flash * 0.35) * fade
	-- The shadow: the theme's colour (as far as Shadow tint says), toward its
	-- flash colour in a flash.
	local shadow, flashColor = shownTheme.shadow, shownTheme.flash
	for i = 1, 3 do
		local v = shadow[i] * db.lowHealthRed
		shadowColor[i] = v + (flashColor[i] - v) * flash * FLASH_TINT
	end
	ns.SetVignette(edges, size, alpha, shadowColor[1], shadowColor[2], shadowColor[3])
	-- The grade: by how far in the edges are, not their throb (the world
	-- shouldn't pulse). Not with secret health: the game's alpha may not fade
	-- a multiplying layer, so it would stay at full.
	local graded = db.lowHealthGrade and level > 0 and not secret
	if graded then
		local g = level * level * (3 - 2 * level) * db.lowHealthGradeAmount * fade
		local tint = shownTheme.flash
		local r, gr, b
		for i = 1, 3 do
			local target = GRADE_GREY[i] + (tint[i] - GRADE_GREY[i]) * GRADE_TINT
			local v = 1 + (target - 1) * g
			if i == 1 then r = v elseif i == 2 then gr = v else b = v end
		end
		grade:SetVertexColor(r, gr, b)
	end
	grade:SetShown(graded)
	if db.lowHealthBlood and c > 0 then
		local deep = ART_SHALLOWEST + (ART_DEEPEST - ART_SHALLOWEST) * db.lowHealthBloodReach
		artScale = math.max(1, ART_OUT + (deep - ART_OUT) * c - over * 0.05)
		local artAlpha = db.lowHealthBloodAlpha * math.min(1, c * 3) * fade
		-- Sloshing (liquid themes): the art rocks slowly side to side and up and down.
		local sway = shownTheme.sway
		-- (a little bigger while it rocks, so its edges never come on screen)
		local pad = sway and 4 * SWAY * sway or 0
		if sway then
			local now = GetTime()
			local sx = math.sin(now * 1.3) * sway * SWAY * height
			local sy = math.sin(now * 0.9 + 1) * sway * SWAY * 0.6 * height
			body:SetPoint("CENTER", sx, sy)
			glow:SetPoint("CENTER", sx, sy)
		end
		-- (Game art: the theme's art colour or its glow's, for both.)
		local edged = shownTheme.edge or gameArt
		local color = shownTheme.body or gameArt and shownTheme.glow
		if color and edged then
			body:SetSize(width * (artScale + pad), height * (artScale + pad))
			body:SetVertexColor(color[1], color[2], color[3], artAlpha)
			body:Show()
		else
			body:Hide()
		end
		color = shownTheme.glow or gameArt and shownTheme.body
		if color and edged then
			glow:SetSize(width * (artScale + pad), height * (artScale + pad))
			-- (brighter on a beat and in a flash)
			local a = artAlpha * (shownTheme.glowAlpha or 1) * (0.8 + 0.3 * heart + 0.4 * flash)
			glow:SetVertexColor(color[1], color[2], color[3], math.min(1, a))
			glow:Show()
		else
			glow:Hide()
		end
		if gameArt and color then
			-- A wave creeping in from past the edges on each beat (each second
			-- with no heartbeat), brightest halfway.
			local p = db.lowHealthPulse and beat or GetTime() % 1
			local scale = artScale + pad + RIPPLE_SPAN * (1 - p)
			ripple:SetSize(width * scale, height * scale)
			ripple:SetVertexColor(color[1], color[2], color[3], artAlpha * RIPPLE_ALPHA * math.sin(math.pi * p))
			ripple:Show()
		end
		AnimateSparks(GetTime(), width, height, db.lowHealthBloodAlpha * math.min(1, c * 2) * fade)
	else
		body:Hide()
		glow:Hide()
		ripple:Hide()
		ClearSparks()
	end
	return size
end

-- What's wanted now: the share of health to go by (nil: secret), and whether
-- the edges are wanted at all.
local function Wanted(now)
	if test then
		local t = now - test.start
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
	theme = WantedTheme()
	if theme ~= shownTheme then UseTheme(theme) end
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
	local sparking = db.lowHealthBlood and level > 0.05 and shownTheme.sparks
	if bigHit or lostAdding >= db.lowHealthFlashAdded then
		lostAdding = 0
		if db.lowHealthFlash then flash = 1 end
		if sparking then
			for _, info in ipairs(sparking) do
				for _ = 1, info.hit and math.random(info.hit[1], info.hit[2]) or 0 do Spark(info) end
			end
		end
	end
	if sparking then
		for _, info in ipairs(sparking) do
			if info.rate and math.random() < info.rate / 60 * elapsed * level then Spark(info) end
		end
	end
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
	local k, heart = level, 0
	if db.lowHealthPulse and level > 0 then
		local bpm = (db.lowHealthBpmSlow + (db.lowHealthBpmFast - db.lowHealthBpmSlow) * level)
			* (shownTheme.bpm or 1)
		beat = (beat + elapsed * bpm / 60) % 1
		heart = Heartbeat(beat)
		k = level * (1 + db.lowHealthPulseAmount * (shownTheme.pulse or 1) * heart)
	end
	-- (A flash with the edges out still shows a little at the edges.)
	k = math.max(k, flash * 0.35)
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
		reachNow = Apply(k, fade, heart, secret)
	else
		ClearSparks()
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
	ClearSparks()
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
	ns.Print(("Vitals: on %s, edges %s, art %s, combat %s, test %s"):format(Show(db.lowHealth),
		Show(db.lowHealthEdges), Show(db.lowHealthBlood), Show(ns.Flag(UnitAffectingCombat("player"))),
		Show(test ~= nil)))
	ns.Print(("  health %s / %s, share %s, curve %s, level %.2f, art size %.2f screens"):format(Show(health),
		Show(max), Show(HealthShare()), Show(SecretCurve() and true), level, artScale))
	ns.Print(("  theme %s (edge %s), frame shown %s, alpha %s, driver %s"):format(Show(shownTheme and shownTheme.key),
		Show(shownTheme and shownTheme.edge), Show(frame:IsShown()), Show(frame:GetAlpha()), Show(driver:IsShown())))
	ns.Print("  game art: " .. Show(gameArt))
	for name, tex in pairs({ art = body, glow = glow, wave = ripple }) do
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
	UseTheme(WantedTheme())
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
-- paint.
local EDGE_SCOUT = {
	{ 131140, "lowhealth" }, { 131141, "outofcontrol" }, { 965906, "penandinkoverlay" },
	{ 965907, "penandinkoverlay_512" }, { 985799, "outlinemagicscroll" }, { 1273707, "dh_demonvisionscroll" },
	{ 1305137, "dh_demonvisionfire" }, { 1305138, "dh_demonvisionfiremask" }, { 1610628, "vignette_t" },
	{ 1802909, "8fx_mask_fullscreen_01" }, { 1803988, "mask_fullscreen_01" },
	{ 1807126, "mask_fullscreen_01_scroll" }, { 2140999, "fullscreeneffect_blend_2140999" },
	{ 2144748, "mask_fullscreen_02" }, { 2199089, "fullscreeneffect_2199089" },
	{ 2199924, "fullscreeneffect_blend_2199924" }, { 2199926, "fullscreeneffect_blend_2199926" },
	{ 2199927, "fullscreeneffect_blend_2199927" }, { 2202396, "mask_fullscreen_03" },
	{ 2202483, "fullscreeneffect_blend_2202483" }, { 2202649, "fullscreeneffect_blend_2202649" },
	{ 2395778, "fullscreeneffect_2395778" }, { 2396780, "fullscreeneffect_blend_2396780" },
	{ 2510375, "mask_fullscreen_01_scroll_a" }, { 2530675, "mask_fullscreen_01_scroll_a2" },
	{ 2735672, "fullscreeneffect_2735672" }, { 3509149, "9fx_soul_camera_vignette_3509149" },
	{ 3509152, "9fx_soul_camera_vignette_3509152" }, { 3522951, "fullscreeneffect_blend_3522951" },
	{ 3522953, "fullscreeneffect_3522953" }, { 3522955, "fullscreeneffect_blend_3522955" },
	{ 3728762, "9fx_soul_camera_vignette_3728762" }, { 3728763, "9fx_soul_camera_vignette_3728763" },
	{ 3728764, "9fx_soul_camera_vignette_3728764" }, { 3728765, "9fx_soul_camera_vignette_3728765" },
	{ 3728766, "9fx_soul_camera_vignette_3728766" }, { 4237661, "fullscreeneffect_blend_4237661" },
	{ 4237662, "fullscreeneffect_4237662" }, { 4325579, "fullscreeneffect_blend_4325579" },
	{ 4383351, "fullscreeneffect_blend_4383351" }, { 4417751, "fullscreeneffect_blend_4417751" },
	{ 4541185, "fullscreeneffect_4541185" }, { 4541187, "fullscreeneffect_blend_4541187" },
	{ 4541189, "fullscreeneffect_blend_4541189" }, { 4630641, "fullscreeneffect_blend_4630641" },
	{ 4741748, "fullscreeneffect_4741748" }, { 4741750, "fullscreeneffect_blend_4741750" },
	{ 4741753, "fullscreeneffect_blend_4741753" }, { 4876486, "fullscreeneffect_4876486" },
	{ 5198840, "fullscreeneffect_blend_5198840" }, { 5201310, "fullscreeneffect_blend_5201310" },
	{ 5332772, "fullscreeneffect_blend_5332772" }, { 5332774, "fullscreeneffect_blend_5332774" },
	{ 5371262, "fullscreeneffect_blend_5371262" },
	{ 5556140, "7fx_soulengine_soulwrap_camera_vignette_5556140" },
	{ 5636771, "fullscreeneffect_blend_5636771" }, { 5636772, "fullscreeneffect_5636772" },
	{ 5680179, "fullscreeneffect_5680179" }, { 5726057, "fullscreeneffect_5726057" },
	{ 5737247, "fullscreeneffect_blend_5737247" }, { 5737249, "fullscreeneffect_5737249" },
	{ 5737251, "fullscreeneffect_blend_5737251" }, { 5857660, "fullscreeneffect_blend_5857660" },
	{ 5857669, "fullscreeneffect_5857669" }, { 5857689, "fullscreeneffect_blend_5857689" },
	{ 6214875, "fullscreeneffect_blend_6214875" }, { 6214876, "fullscreeneffect_blend_6214876" },
	{ 6214877, "fullscreeneffect_blend_6214877" }, { 6225363, "fullscreeneffect_blend_6225363" },
	{ 6225364, "fullscreeneffect_6225364" }, { 6225365, "fullscreeneffect_blend_6225365" },
	{ 6225366, "fullscreeneffect_blend_6225366" }, { 6907568, "fullscreeneffect_blend_6907568" },
	{ 6907571, "fullscreeneffect_blend_6907571" }, { 6996935, "fullscreeneffect_blend_6996935" },
	{ 6996936, "fullscreeneffect_6996936" }, { 7339122, "fullscreeneffect_blend_7339122" },
	{ 7352941, "fullscreeneffect_blend_7352941" }, { 7713391, "fullscreeneffect_blend_7713391" },
	{ 7713861, "fullscreeneffect_blend_7713861" },
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
	scout.tex:SetTexture(entry[1])
	scout.tex:SetBlendMode(scoutBlend and "BLEND" or "ADD")
	scout:Show()
	local id = scout.tex.GetTextureFileID and scout.tex:GetTextureFileID()
	ns.Print(("game edge %d of %d: %s (%d), %s%s"):format(scoutAt, #EDGE_SCOUT, entry[2], entry[1],
		scoutBlend and "as paint" or "as light", (id or 0) > 0 and "" or ", not loaded"))
	ns.Print("  next: /cine debug gameedge; also back, a number, blend (light or paint), off")
end

function ns.SetVitalsSecretAlpha(frame)
	local curve = SecretCurve()
	if curve then
		pcall(function() frame:SetAlpha(UnitHealthPercent("player", true, curve)) end)
	end
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
	local function Slide(key, label, minV, maxV, step, fmt, scale, tip, enabledBy)
		local slider = stack:Add(kit.Slider(content, key, label, minV, maxV, step, fmt, scale, Changed), "slider")
		if tip then kit.Tooltip(slider, tip) end
		if enabledBy then kit.GreyUnless(slider, enabledBy) end
		return slider
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
	local function Art(d) return d.lowHealthEdges and d.lowHealthBlood end
	local function Beating(d) return d.lowHealthEdges and d.lowHealthPulse end
	local TEST_TIP = L["Your health falls as the Test section below says (all the way in, at first), stays " ..
		"there a moment, then goes back to yours, in the theme picked. It works with the page off too. " ..
		"Close the settings to see it all."]

	-- The theme: Auto (and what it picks for you), or any of them, by class
	-- and spec. A quick test beside it.
	local function ThemeName(key)
		local info = ns.LOW_HEALTH_THEME[key]
		return info and L[info.name] or key
	end
	local function AutoText()
		return L["Auto"] .. ": " .. ThemeName(ns.LowHealthAutoTheme())
	end
	local function AutoGameText() -- (Game art's Auto, by class and spec too)
		return L["Game art"] .. ", " .. L["Auto"] .. ": " .. ThemeName(ns.LowHealthAutoGameTheme())
	end
	local function Choices() -- (flat: the button that steps through them)
		local list = { { value = "auto", text = AutoText() }, { value = "autogame", text = AutoGameText() } }
		for _, info in ipairs(ns.LOW_HEALTH_THEMES) do
			list[#list + 1] = { value = info.key, text = L[info.name] }
		end
		for _, info in ipairs(ns.LOW_HEALTH_GAME_THEMES) do
			list[#list + 1] = { value = info.key, text = L["Game art"] .. ": " .. ThemeName(info.key) }
		end
		return list
	end
	local themeRow = CreateFrame("Frame", nil, content)
	themeRow:SetSize(560, 26)
	stack:Add(themeRow, "label", 2)
	local themeLabel = kit.Label(themeRow, "GameFontHighlight", L["Theme:"])
	themeLabel:SetPoint("LEFT")
	local THEME_TIP = L["The look: Auto picks your class and spec's (by the talent tree you've put most " ..
		"into, on clients without specs), or pick any. Each class has a theme for each spec."]
	local dropdown = kit.Dropdown and kit.Dropdown(themeRow, "lowHealthTheme", Choices, 260, Changed)
	local themePicker = dropdown
	if dropdown then
		dropdown:SetPoint("LEFT", themeLabel, "RIGHT", 8, 0)
		kit.Tooltip(dropdown, THEME_TIP)
		-- By class: Auto, then a submenu for each class (in its colour), each
		-- spec in it with its theme. (Replaces the flat list the helper made.)
		local RETAIL = " |cff999999(" .. L["retail"] .. ")|r"
		local function Pick(key)
			ns.GetDB().lowHealthTheme = key
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
		dropdown:SetupMenu(function(_, root)
			root:CreateRadio(AutoText(), function() return Picked("auto") end, function() Pick("auto") end)
			root:CreateDivider()
			for _, class in ipairs(ns.LOW_HEALTH_MENU) do
				local menu = root:CreateButton(ClassName(class))
				for _, spec in ipairs(class[3]) do
					local key = spec[2]
					menu:CreateRadio(L[spec[1]] .. ": " .. ThemeName(key) .. (spec.retail and RETAIL or ""),
						function() return Picked(key) end, function() Pick(key) end)
				end
			end
			-- The game's own edge (LowHealthThemes.lua's Game art): Auto by
			-- class and spec, then each colour.
			root:CreateDivider()
			local gameMenu = root:CreateButton(L["Game art"])
			gameMenu:CreateRadio(AutoGameText(), function() return Picked("autogame") end,
				function() Pick("autogame") end)
			gameMenu:CreateDivider()
			for _, info in ipairs(ns.LOW_HEALTH_GAME_THEMES) do
				local key = info.key
				gameMenu:CreateRadio(ThemeName(key), function() return Picked(key) end, function() Pick(key) end)
			end
		end)
	else
		-- (No dropdowns on this client: a button that steps through them.)
		themePicker = Button(themeRow, "", 220, THEME_TIP, function(self)
			local list = Choices()
			local key = ns.GetDB().lowHealthTheme
			for i, choice in ipairs(list) do
				if choice.value == key then
					ns.GetDB().lowHealthTheme = list[i % #list + 1].value
					break
				end
			end
			Changed()
			self:Refresh()
		end)
		themePicker:SetPoint("LEFT", themeLabel, "RIGHT", 8, 0)
		themePicker.Refresh = function(self)
			local key = ns.GetDB().lowHealthTheme
			self:SetText(key == "auto" and AutoText() or key == "autogame" and AutoGameText() or ThemeName(key))
		end
		kit.AddControl(themePicker)
	end
	-- (Not a page control: it works with the page off.)
	local quickTest = Button(themeRow, L["Test"], 80, TEST_TIP, ns.TestLowHealth)
	quickTest:SetPoint("LEFT", themePicker, "RIGHT", 10, 0)
	stack:Continue(themeRow, "label")
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
	Slide("lowHealthStart", L["Starts below"], 10, 100, 5, "%d%%", 100,
		L["Your health the edges start creeping in below."])
	Slide("lowHealthFull", L["All the way in at"], 0, 90, 5, "%d%%", 100,
		L["Your health the edges are all the way in at (under Starts below)."])
	Slide("lowHealthCalm", L["Strength out of combat"], 0, 100, 5, "%d%%", 100,
		L["How strong the edges are out of a fight (eating and drinking back up, say), next to in one. Some " ..
		"clients keep your health secret in fights; there the edges only fade in and out with it."], Edges)

	stack:Header(content, L["How fast"])
	Slide("lowHealthFollow", L["Close in over"], 0, 1, 0.05, "%.2fs", 1,
		L["Seconds the edges take to close all the way in when your health drops. Keep it short: it's the " ..
		"warning."], Edges)
	Slide("lowHealthLiftSpeed", L["Lift speed"], 5, 200, 5, L["%d%% a second"], 100,
		L["The fastest the edges lift when you're healed, as a share of all the way each second (40%: a " ..
		"full heal takes at least 2.5 seconds). They speed up to it and slow as they settle."], Edges)

	stack:Header(content, L["Shadow"])
	Slide("lowHealthReach", L["Reach"], 10, 50, 1, "%d%%", 100,
		L["How much of the screen the dark edges cover at full."], Edges)
	Slide("lowHealthDark", L["Darkness"], 0, 100, 5, "%d%%", 100, L["How dark the edges are at full."], Edges)
	Slide("lowHealthRed", L["Shadow tint"], 0, 100, 5, "%d%%", 100,
		L["0%: black, like the death screen. 100%: the theme's own color (deep red for blood)."], Edges)
	Tick("lowHealthGrade", L["Color grade"], L["The whole picture drains toward a cold grey, tinged with the " ..
		"theme's color, as the edges close in. The world only: your UI stays as it is. Off in fights where " ..
		"the game keeps your health secret."], Edges)
	Slide("lowHealthGradeAmount", L["Grade strength"], 10, 100, 5, "%d%%", 100,
		L["How far the picture drains at full."], function(d) return Edges(d) and d.lowHealthGrade end)

	stack:Header(content, L["Theme art"])
	Tick("lowHealthBlood", L["Show the theme's art"], L["The theme's art soaking in from the edges as they " ..
		"close in (blood, smoke, a glow...). Unticked: just the shadow."], Edges)
	Slide("lowHealthBloodAlpha", L["Opacity"], 0, 100, 5, "%d%%", 100, nil, Art)
	Slide("lowHealthBloodReach", L["Reach"], 0, 100, 5, "%d%%", 100,
		L["How far in the art comes at full: 0% just the screen's edges, 100% all of it."], Art)

	stack:Header(content, L["Heartbeat"])
	Tick("lowHealthPulse", L["Heartbeat"], L["The edges throb with a heartbeat, quicker as you weaken."], Edges)
	Slide("lowHealthPulseAmount", L["Throb"], 0, 60, 5, "%d%%", 100,
		L["How much further in each beat pushes the edges (some themes throb more or less)."], Beating)
	Slide("lowHealthBpmSlow", L["Beats a minute as they start"], 30, 120, 5, "%d", 1, nil, Beating)
	Slide("lowHealthBpmFast", L["Beats a minute at full"], 60, 200, 5, "%d", 1, nil, Beating)

	stack:Header(content, L["Big hits"])
	Tick("lowHealthFlash", L["Flash on big hits"],
		L["The edges flash in the theme's color when a hit takes a lot at once."], Edges)
	Slide("lowHealthFlashHit", L["A big hit takes"], 2, 40, 1, "%d%%", 100,
		L["The share of your health a hit has to take at once to count as big."], Edges)
	Slide("lowHealthFlashAdded", L["Or hits adding up to"], 5, 60, 1, "%d%%", 100,
		L["Smaller hits count as a big one too once they've taken this much of your health together " ..
			"(since the last one; again each fight)."], Edges)
	-- (Dev copy: try a camera shake, before hits get one.)
	if ns.isDev then
		local shakeRow = CreateFrame("Frame", nil, content)
		shakeRow:SetSize(300, 26)
		stack:Add(shakeRow, "label", 2)
		Button(shakeRow, "Test camera shake", 160, "A small shake, as a big hit might give. Close the " ..
			"settings first or watch the world behind them.", function()
				C_Timer.After(0.3, ns.ShakeCamera)
			end):SetPoint("LEFT")
	end

	-- The test: its own settings, and Test and Stop. (Not page controls:
	-- they work with the page off.)
	stack:Header(content, L["Test"])
	stack:Add(kit.Label(content, "GameFontHighlightSmall",
		L["Try a theme whatever your health: it falls from one share to another over some seconds."]), "label")
	Slide("lowHealthTestFrom", L["From"], 0, 100, 5, "%d%%", 100)
	Slide("lowHealthTestTo", L["To"], 0, 100, 5, "%d%%", 100)
	Slide("lowHealthTestTime", L["Over"], 1, 30, 1, L["%ds"], 1)
	stack:Add(kit.Check(content, "lowHealthTestHits", L["In hits"],
		L["Ticked, your health falls in hits (each a big hit, with its flash); unticked, smoothly."]),
		"check")
	local row = CreateFrame("Frame", nil, content)
	row:SetSize(300, 26)
	stack:Add(row, "label", 2)
	local testButton = Button(row, L["Test"], 80, TEST_TIP, ns.TestLowHealth)
	testButton:SetPoint("LEFT")
	local stopButton = Button(row, L["Stop"], 80, nil, ns.StopLowHealthTest)
	stopButton:SetPoint("LEFT", testButton, "RIGHT", 8, 0)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Vitals Vision")
end
