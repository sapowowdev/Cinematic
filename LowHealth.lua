-- Vitals Vision, low-health edges: as your health drops, dark edges creep in round the
-- screen, like the death screen's vignette, with a theme's art soaking in
-- past them (blood, frost, fire, smoke...: Media/make_lowhealth.py), its
-- effects moving over it (drips running down, drops splashing on, embers
-- rising...), a heartbeat that quickens as you weaken and a flash on big
-- hits. So you can tell how you're doing without the portrait. Themes are in
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
DEFAULTS.lowHealthBlood = true     -- the theme's art (and its drips and effects)
DEFAULTS.lowHealthBloodAlpha = 0.9
DEFAULTS.lowHealthBloodReach = 0.7 -- how far in the art comes at full (0-1)
DEFAULTS.lowHealthDrips = true     -- drips running down from the art at the top
DEFAULTS.lowHealthDripRate = 12    -- ...a minute, at full (fewer as it starts)
DEFAULTS.lowHealthDrops = true     -- the theme's effects (drops, embers, cracks...)
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
local NO_TOP = {} -- (a material with no top edge known: drips start at the screen's top)
local DRIP_SPAN = { 4 / 32, 28 / 32 } -- (where in the texture drips can start: not the corners)
local MAX_DRIPS, MAX_EFFECTS = 8, 24
-- A drip runs down (its tip leading) over its run time to its length, keeps
-- creeping a little, then fades. Sizes in shares of the screen's height.
local DRIP_RUN = { 0.8, 2.2 }      -- seconds
local DRIP_LIFE = { 4, 7 }         -- seconds in all
local DRIP_LENGTH = { 0.03, 0.12 }
local DRIP_WIDTH = { 0.008, 0.014 }
local DRIP_CREEP = 0.25            -- longer by this share over the rest of its life
local DRIP_HIDE = 0.008            -- starts this far up into the art
-- Effects (LowHealthThemes.lua says how each kind moves).
local POP = 0.12                   -- seconds a splat takes to land, a reveal to draw on
local SPLAT_SLIDE = 0.012          -- how far a splat slides over its life
local FADE_IN, FADE_END = 0.3, 1.2 -- seconds effects fade in (those that do) and out over
local SWAY = 0.012                 -- how far a sloshing theme's art rocks (share of the height, times its sway)
local EFFECTS_COLUMNS, EFFECTS_ROWS = 8, 4
-- (Cells drawn mirrored now and then, for variety: the ones it doesn't show.)
local FLIPPABLE = { Splat = true, Slash = true, Claw = true, CrackBurst = true, Puff = true, Dust = true,
	Bruise = true, Shard = true, Bolt = true, Leaf = true, Feather = true }

local frame, edges, body, glow, driver
local drips, effects = {}, {} -- (sprite pools: made once, reused)
local artScale = ART_OUT -- (the art's size now: drips follow its edge)
local theme, shownTheme -- (the theme wanted, and the one the textures are set up for)
local autoTheme -- (Auto's pick, until your talents change)
local cellIndex = {} -- cell name -> its place in Effects.tga
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

local function Between(range)
	return range[1] + (range[2] - range[1]) * math.random()
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

local function AutoTheme()
	local _, class = UnitClass("player")
	local list = ns.LOW_HEALTH_CLASS_THEMES[class]
	if not list then return "blood" end
	local tree
	if GetSpecialization then
		local ok, spec = pcall(GetSpecialization)
		if ok and type(spec) == "number" and spec > 0 then
			list = ns.LOW_HEALTH_SPEC_THEMES[class] or list
			tree = spec
		end
	else
		tree = TreeWithMostPoints()
	end
	return tree and list[tree] or list.none or list[1]
end

function ns.LowHealthAutoTheme()
	autoTheme = autoTheme or AutoTheme()
	return autoTheme
end

local function WantedTheme()
	local key = db.lowHealthTheme
	if key == "auto" or not ns.LOW_HEALTH_THEME[key] then
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
	-- (Drips under the art, so where they leave it doesn't show; effects on top.)
	for i = 1, MAX_DRIPS do
		local tex = frame:CreateTexture(nil, "BACKGROUND")
		tex:Hide()
		drips[i] = { tex = tex }
	end
	body = frame:CreateTexture(nil, "BORDER")
	body:SetPoint("CENTER")
	glow = frame:CreateTexture(nil, "BORDER", nil, 1)
	glow:SetPoint("CENTER")
	glow:SetBlendMode("ADD")
	for i = 1, MAX_EFFECTS do
		local tex = frame:CreateTexture(nil, "BORDER", nil, 2)
		tex:SetTexture(ART .. "Effects")
		tex:Hide()
		effects[i] = { tex = tex }
	end
	edges = ns.CreateVignette(frame)
	-- (The shadow under everything: over the art, it hid it.)
	for _, piece in pairs(edges) do
		piece:SetDrawLayer("BACKGROUND", -8)
	end
	frame:Hide()
	for i, name in ipairs(ns.LOW_HEALTH_CELLS) do
		cellIndex[name] = i
	end
	-- (Its own frame, not under UIParent, so it runs with the UI hidden too.)
	driver = CreateFrame("Frame")
	driver:Hide()
end

local function ClearSprites()
	for _, drip in ipairs(drips) do
		drip.born = nil
		drip.tex:Hide()
	end
	for _, fx in ipairs(effects) do
		fx.born = nil
		fx.tex:Hide()
	end
end

-- Sets the textures up for a theme (its art, glow and drips).
local function UseTheme(wanted)
	shownTheme = wanted
	ClearSprites()
	body:SetPoint("CENTER") -- (a sloshing theme's rocking, undone)
	glow:SetPoint("CENTER")
	if wanted.edge and wanted.body then
		body:SetTexture(ART .. wanted.edge)
	end
	if wanted.edge and wanted.glow then
		glow:SetTexture(ART .. wanted.edge .. "Glow")
		glow:SetBlendMode("ADD")
	end
	if wanted.drip then
		for _, drip in ipairs(drips) do
			drip.tex:SetTexture(ART .. wanted.drip.tex)
		end
	end
end

-- A heartbeat: a strong beat and a softer one just after (0-1).
local function Heartbeat(phase)
	local p = phase % 1
	local first = math.exp(-((p - 0.05) / 0.05) ^ 2)
	local second = 0.6 * math.exp(-((p - 0.28) / 0.06) ^ 2)
	return math.max(first, second)
end

-- How far down from the screen's top the art's edge is at x (0-1 across the
-- screen), in shares of the screen's height (below 0: off the top). up: how
-- far up from the bottom, instead.
local function ArtTopAt(x, up)
	local tops = (up and ns.LOW_HEALTH_BOTTOMS or ns.LOW_HEALTH_TOPS)[shownTheme.edge] or NO_TOP
	local u = 0.5 + (x - 0.5) / artScale -- (across the texture)
	local at = math.max(0, math.min(32, u * 32))
	local i = math.floor(at)
	local a, b = tops[i + 1] or 0, tops[math.min(33, i + 2)] or 0
	local top = a + (b - a) * (at - i)
	return artScale * top - (artScale - 1) / 2
end

local function StartDrip()
	for _, drip in ipairs(drips) do
		if not drip.born then
			-- (across the screen, where that's in the texture's middle span)
			local lo = math.max(0.02, 0.5 + (DRIP_SPAN[1] - 0.5) * artScale)
			local hi = math.min(0.98, 0.5 + (DRIP_SPAN[2] - 0.5) * artScale)
			drip.x = lo + (hi - lo) * math.random()
			drip.born, drip.run, drip.life = GetTime(), Between(DRIP_RUN), Between(DRIP_LIFE)
			drip.length, drip.width = Between(DRIP_LENGTH), Between(DRIP_WIDTH)
			local color = shownTheme.drip.color
			drip.r, drip.g, drip.b = color[1], color[2], color[3]
			drip.up = shownTheme.drip.up
			return
		end
	end
end

-- Where an effect starts (shares of the screen across and down), about
-- where the shadow reaches now, and the side (1 top, 2 bottom, 3 left, 4 right).
local function Place(at, reach)
	local along, inset = 0.1 + 0.8 * math.random(), reach * (0.4 + 0.7 * math.random())
	local side = at == "top" and 1 or at == "bottom" and 2 or at == "sides" and math.random(3, 4)
		or at == "across" and math.random(2) or math.random(4)
	if side == 1 then return along, inset, side end
	if side == 2 then return along, 1 - inset, side end
	-- (Left and right: the reach is a share of the width there, and screens are wide.)
	if side == 3 then return inset * 0.6, along, side end
	return 1 - inset * 0.6, along, side
end

-- delay: seconds before it shows (a trail's later steps); x, y, side: where
-- (else picked).
local function StartEffect(info, reach, delay, x, y, side)
	for _, fx in ipairs(effects) do
		if not fx.born then
			fx.info = info
			if x then
				fx.x, fx.y, fx.side = x, y, side
			else
				fx.x, fx.y, fx.side = Place(info.at, reach)
			end
			fx.born, fx.life, fx.size = GetTime() + (delay or 0), Between(info.life), Between(info.size)
			fx.phase = math.random() * 2 * math.pi
			fx.dir = math.random() < 0.5 and -1 or 1 -- (a sweep's way along the edge)
			-- Its cell (a splat: any of the four), mirrored now and then.
			local i = cellIndex[info.cell] or cellIndex[info.cell .. math.random(4)] or 1
			local column, row = (i - 1) % EFFECTS_COLUMNS, math.floor((i - 1) / EFFECTS_COLUMNS)
			local left, right = column / EFFECTS_COLUMNS, (column + 1) / EFFECTS_COLUMNS
			local top, bottom = row / EFFECTS_ROWS, (row + 1) / EFFECTS_ROWS
			if FLIPPABLE[info.cell] and math.random() < 0.5 then left, right = right, left end
			if FLIPPABLE[info.cell] and info.kind ~= "fall" and math.random() < 0.5 then
				top, bottom = bottom, top
			end
			-- (A sweep's picture faces the way it goes: the wind's head leads.)
			if info.kind == "sweep" and (fx.dir < 0) == (left < right) then left, right = right, left end
			fx.left, fx.right, fx.top, fx.bottom = left, right, top, bottom
			fx.tex:SetTexCoord(left, right, top, bottom)
			fx.tex:SetBlendMode(info.add and "ADD" or "BLEND")
			return fx
		end
	end
end

-- A trail (paw prints walking along an edge): info.trail steps, each a
-- little further on and later, alternating either side of the way.
local function StartTrail(info, reach)
	local x, y, side = Place(info.at, reach)
	local dir = math.random() < 0.5 and -1 or 1
	local step = info.step or 0.05
	for i = 0, info.trail - 1 do
		local offset = (i % 2 == 0 and -1 or 1) * step * 0.3
		local fx
		if side <= 2 then
			fx = StartEffect(info, reach, i * (info.every or 0.35), x + dir * i * step * 0.6, y + offset, side)
		else
			fx = StartEffect(info, reach, i * (info.every or 0.35), x + offset * 0.6, y + dir * i * step, side)
		end
		if not fx then return end
	end
end

-- A sprite's alpha at age t of its life: fading out over the end.
local function FadeOut(t, life)
	return math.max(0, math.min(1, (life - t) / FADE_END))
end

local function AnimateDrips(now, width, height, alpha)
	for _, drip in ipairs(drips) do
		if drip.born then
			local t = now - drip.born
			if t >= drip.life then
				drip.born = nil
				drip.tex:Hide()
			else
				local run = math.min(1, t / drip.run)
				run = 1 - (1 - run) ^ 3 -- (fast off the edge, slowing as it goes)
				local creep = math.max(0, t - drip.run) / (drip.life - drip.run) * DRIP_CREEP
				local length = drip.length * (run + creep) * height
				local top = (ArtTopAt(drip.x, drip.up) - DRIP_HIDE) * height
				local shown = math.min(1, run + creep) -- (the sprite's bottom part: its tip first)
				drip.tex:ClearAllPoints()
				if drip.up then
					-- (from the bottom edge, upside down: its tip leading up)
					drip.tex:SetPoint("BOTTOM", frame, "BOTTOMLEFT", drip.x * width, top)
					drip.tex:SetTexCoord(0, 1, 1, 1 - shown)
				else
					drip.tex:SetPoint("TOP", frame, "TOPLEFT", drip.x * width, -top)
					drip.tex:SetTexCoord(0, 1, 1 - shown, 1)
				end
				drip.tex:SetSize(drip.width * height, math.max(1, length + DRIP_HIDE * height))
				drip.tex:SetVertexColor(drip.r, drip.g, drip.b, alpha * FadeOut(t, drip.life))
				drip.tex:Show()
			end
		end
	end
end

-- One effect at age t: where it is (shares of the screen), its size (shares
-- of the height) and width (times that), its alpha, and how much of it is
-- drawn on (reveal: 0-1 across).
local function EffectNow(fx, t)
	local info, x, y, size, wide, alpha, drawn = fx.info, fx.x, fx.y, fx.size, 1, FadeOut(t, fx.life), 1
	local kind = info.kind
	if kind == "splat" then
		-- (lands growing to 120%, settling back to its size)
		size = size * (t < POP and 0.4 + 0.8 * t / POP or 1 + 0.2 * math.max(0, 1 - (t - POP) / 0.1))
		y = y + t / fx.life * SPLAT_SLIDE
	elseif kind == "reveal" then
		drawn = math.min(1, t / POP)
	elseif kind == "rise" then
		y = y - (info.speed or 0.1) * t
		x = x + math.sin(fx.phase + t * 2) * 0.008
		alpha = alpha * math.min(1, t / FADE_IN)
	elseif kind == "fall" then
		y = y + (info.speed or 0.3) * t
	elseif kind == "flutter" then
		y = y + (info.speed or 0.06) * t
		x = x + math.sin(fx.phase + t * 1.5) * 0.025
		wide = 0.3 + 0.7 * math.abs(math.cos(fx.phase + t * 2)) -- (turning as it falls)
		alpha = alpha * math.min(1, t / FADE_IN)
	elseif kind == "drift" then
		local share = t / fx.life
		x, y = x + (0.5 - x) * 0.15 * share, y + (0.5 - y) * 0.15 * share
		size = size * (1 + 0.8 * share)
		alpha = alpha * math.min(1, t / (FADE_IN * 2))
	elseif kind == "ripple" then
		size = size * (0.3 + 1.2 * t / fx.life)
		alpha = 1 - t / fx.life
	elseif kind == "flicker" then
		alpha = (math.sin(t * 55 + fx.phase) > -0.4 and 1 or 0.15) * (1 - t / fx.life)
	elseif kind == "twinkle" then
		alpha = math.sin(math.pi * t / fx.life)
	elseif kind == "bubble" then
		-- (swells, wobbling, and bursts: gone in its last tenth)
		local share = t / fx.life
		size = size * (0.5 + 0.6 * share) * (1 + 0.05 * math.sin(t * 9 + fx.phase))
		alpha = share < 0.9 and math.min(1, t / FADE_IN) or (1 - share) * 10
		y = y - (info.speed or 0) * t
	elseif kind == "pull" then
		-- (drawn in toward the middle, faster as it goes, shrinking)
		local share = (t / fx.life) ^ 1.6
		x, y = x + (0.5 - x) * 0.6 * share, y + (0.5 - y) * 0.6 * share
		size = size * (1 - 0.6 * share)
		alpha = math.min(1, t / FADE_IN) * (1 - share)
	elseif kind == "sweep" then
		-- (along the edge it started by: across on the top and bottom, up or down the sides)
		local moved = (info.speed or 0.4) * t * fx.dir
		if fx.side == 3 or fx.side == 4 then y = y + moved else x = x + moved * 0.6 end
		alpha = math.min(1, t / FADE_IN) * FadeOut(t, fx.life)
	end
	return x, y, size, wide, alpha, drawn
end

local function AnimateEffects(now, width, height, alpha)
	for _, fx in ipairs(effects) do
		if fx.born then
			local t = now - fx.born
			if t < 0 then
				fx.tex:Hide() -- (a trail's step not reached yet)
			elseif t >= fx.life then
				fx.born = nil
				fx.tex:Hide()
			else
				local x, y, size, wide, a, drawn = EffectNow(fx, t)
				local px = size * height
				local tex = fx.tex
				tex:ClearAllPoints()
				if drawn < 1 then
					-- (drawn on from its left: the left part of its cell)
					tex:SetPoint("LEFT", frame, "TOPLEFT", x * width - px / 2, -y * height)
					tex:SetSize(math.max(1, px * drawn), px)
					tex:SetTexCoord(fx.left, fx.left + (fx.right - fx.left) * drawn, fx.top, fx.bottom)
				else
					tex:SetPoint("CENTER", frame, "TOPLEFT", x * width, -y * height)
					tex:SetSize(math.max(1, px * wide), px)
					tex:SetTexCoord(fx.left, fx.right, fx.top, fx.bottom)
				end
				local color = fx.info.color
				tex:SetVertexColor(color[1], color[2], color[3], alpha * a)
				tex:Show()
			end
		end
	end
end

-- k: how far in (0 none, 1 full; a little more on a beat or a flash); heart:
-- the heartbeat now (0-1). Returns the shadow's reach (share of the screen).
local function Apply(k, fade, heart)
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
		local color = shownTheme.body
		if color and shownTheme.edge then
			body:SetSize(width * (artScale + pad), height * (artScale + pad))
			body:SetVertexColor(color[1], color[2], color[3], artAlpha)
			body:Show()
		else
			body:Hide()
		end
		color = shownTheme.glow
		if color and shownTheme.edge then
			glow:SetSize(width * (artScale + pad), height * (artScale + pad))
			-- (brighter on a beat and in a flash)
			local a = artAlpha * (shownTheme.glowAlpha or 1) * (0.8 + 0.3 * heart + 0.4 * flash)
			glow:SetVertexColor(color[1], color[2], color[3], math.min(1, a))
			glow:Show()
		else
			glow:Hide()
		end
		local now = GetTime()
		local spriteAlpha = db.lowHealthBloodAlpha * math.min(1, c * 2) * fade
		AnimateDrips(now, width, height, spriteAlpha)
		AnimateEffects(now, width, height, spriteAlpha)
	else
		body:Hide()
		glow:Hide()
		ClearSprites()
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

local reachNow = 0 -- (the shadow's reach as last shown: effects start about there)
local belowStart = false -- health known to be under Starts below (not when secret)

-- The theme's effects that a hit, a heartbeat or time brings on.
local function SpawnEffects(why, elapsed)
	if not (db.lowHealthBlood and db.lowHealthDrops and level > 0.05) then return end
	for _, info in ipairs(shownTheme.effects) do
		if level >= (info.from or 0) then
			local count = 0
			if why == "hit" and info.hit then
				count = math.random(info.hit[1], info.hit[2])
			elseif why == "beat" and info.beat and math.random() < info.beat * level then
				count = 1
			elseif why == "time" and info.rate and math.random() < info.rate / 60 * elapsed * level then
				count = 1
			end
			for _ = 1, count do
				if info.trail then StartTrail(info, reachNow) else StartEffect(info, reachNow) end
			end
		end
	end
end

local function Update(_, elapsed)
	local now = GetTime()
	theme = WantedTheme()
	if theme ~= shownTheme then UseTheme(theme) end
	local share, on, testing, dead = Wanted(now)
	testShare = testing and share or nil
	-- A big hit, or smaller ones adding up to Hits adding up to: a flash (only
	-- by what was shown: a heal doesn't), and the theme's effects for it.
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
	if bigHit or lostAdding >= db.lowHealthFlashAdded then
		lostAdding = 0
		if db.lowHealthFlash then flash = 1 end
		SpawnEffects("hit")
	end
	SpawnEffects("time", elapsed)
	local drip = shownTheme.drip
	if drip and db.lowHealthBlood and db.lowHealthDrips and level > 0.05
		and math.random() < db.lowHealthDripRate * (drip.rate or 1) / 60 * elapsed * level then
		StartDrip()
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
		local was = beat
		beat = (beat + elapsed * bpm / 60) % 1
		if beat < was then SpawnEffects("beat") end
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
		reachNow = Apply(k, fade, heart)
	else
		ClearSprites()
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
-- soaks in with its flashes and effects, held for seconds, then back to yours.
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
	ClearSprites()
	if frame then frame:Hide() end
	Wake()
end

function ns.StopLowHealthTest()
	test = nil
	Wake()
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
		autoTheme = nil -- (picked again)
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
	for name, tex in pairs({ art = body, glow = glow }) do
		local _, _, _, a = tex:GetVertexColor()
		local width, height = tex:GetSize()
		ns.Print(("  %s: shown %s, texture %s, size %s x %s, alpha %s"):format(name, Show(tex:IsShown()),
			Show(tex:GetTexture()), Show(width), Show(height), Show(a)))
	end
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
		"theme's art soaking in from them (blood, frost, fire, wind...) and its effects moving over it, a " ..
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
	local function Choices() -- (flat: the button that steps through them)
		local list = { { value = "auto", text = AutoText() } }
		for _, info in ipairs(ns.LOW_HEALTH_THEMES) do
			list[#list + 1] = { value = info.key, text = L[info.name] }
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
			self:SetText(key == "auto" and AutoText() or ThemeName(key))
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
		L["The screen's edges close in as your health drops, with your theme's art and effects (all the " ..
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

	stack:Header(content, L["Theme art"])
	Tick("lowHealthBlood", L["Show the theme's art"], L["The theme's art soaking in from the edges as they " ..
		"close in (blood, frost, fire...), with its drips and effects. Unticked: just the shadow."], Edges)
	Slide("lowHealthBloodAlpha", L["Opacity"], 0, 100, 5, "%d%%", 100, nil, Art)
	Slide("lowHealthBloodReach", L["Reach"], 0, 100, 5, "%d%%", 100,
		L["How far in the art comes at full: 0% just the screen's edges, 100% all of it."], Art)
	Tick("lowHealthDrips", L["Drips"], L["Drips (or icicles) running down from the art, in themes that " ..
		"have them."], Art)
	Slide("lowHealthDripRate", L["Drips a minute"], 2, 60, 1, "%d", 1,
		L["How many at full (fewer as the edges come in; some themes have more or fewer)."],
		function(d) return Art(d) and d.lowHealthDrips end)
	Tick("lowHealthDrops", L["Effects"], L["The theme's effects: drops splashing on, cuts, cracks, embers, " ..
		"smoke, wind, leaves... (with big hits, heartbeats or over time)."], Art)

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
		L["The share of your health a hit has to take at once to count as big (and bring on its effects)."], Edges)
	Slide("lowHealthFlashAdded", L["Or hits adding up to"], 5, 60, 1, "%d%%", 100,
		L["Smaller hits count as a big one too once they've taken this much of your health together " ..
			"(since the last one; again each fight)."], Edges)

	-- The test: its own settings, and Test and Stop. (Not page controls:
	-- they work with the page off.)
	stack:Header(content, L["Test"])
	stack:Add(kit.Label(content, "GameFontHighlightSmall",
		L["Try a theme whatever your health: it falls from one share to another over some seconds."]), "label")
	Slide("lowHealthTestFrom", L["From"], 0, 100, 5, "%d%%", 100)
	Slide("lowHealthTestTo", L["To"], 0, 100, 5, "%d%%", 100)
	Slide("lowHealthTestTime", L["Over"], 1, 30, 1, L["%ds"], 1)
	stack:Add(kit.Check(content, "lowHealthTestHits", L["In hits"],
		L["Ticked, your health falls in hits (each a big hit, with its flash and effects); unticked, smoothly."]),
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
