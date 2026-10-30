-- Combat Vision: a cue for a few seconds as you go into a fight and come out
-- of it: a word on the screen or in a letterbox bar (a title card, a
-- subtitle or a chapter line), a pulse round the screen's edges, an icon and
-- sounds (CombatSoundRules.lua). Its pages: the Visions hub's Combat Vision
-- (when it shows) and the Style hub's (how it looks, with a preview drawn by
-- the same code).

local _, ns = ...
local L = ns.L
local DEFAULTS = ns.DEFAULTS

DEFAULTS.combatVision = false
DEFAULTS.combatOnEnter = true          -- as a fight starts (its Show in row's Combat dropdown)
DEFAULTS.combatOnLeave = true          -- ...and as it ends
DEFAULTS.combatMinFight = 3            -- no leaving cue after a fight shorter than this (seconds)
DEFAULTS.combatAlways = true           -- its Show in row's Always (the rest: ROW_KEY's ticks and rule)
DEFAULTS.combatPlace = "top"           -- "screen", "top" or "bottom" (a letterbox bar)
DEFAULTS.combatBarScale = 0.62         -- in a bar: the text's height, a share of the bar's
DEFAULTS.combatAlign = "center"        -- in a bar: "left", "center" or "right"
DEFAULTS.combatStyle = "title"         -- "title", "subtitle" or "chapter" (no words: "none" in Setup)
DEFAULTS.combatTextIn = "Combat"       -- the words ("": none, just the icon, pulse, bar; these
DEFAULTS.combatTextOut = "Respite"     -- two shown in the game's language: ShownWords)
DEFAULTS.combatFont = "general"        -- QUEST_ITEM_FONTS (QuestItemButton.lua; general: General's)
DEFAULTS.combatSize = 34               -- the text's height on the screen
DEFAULTS.combatOutlineR, DEFAULTS.combatOutlineG, DEFAULTS.combatOutlineB = 0, 0, 0 -- (black: the game's own)
DEFAULTS.combatOutline = -1            -- 0 none, 1 thin, 2 thick (-1: General's, thin at the game's)
DEFAULTS.combatInR, DEFAULTS.combatInG, DEFAULTS.combatInB = 0.89, 0.13, 0.22 -- #E32038
DEFAULTS.combatOutR, DEFAULTS.combatOutG, DEFAULTS.combatOutB = 0.49, 0.67, 0.73
-- The pulse's colors, going in and coming out.
DEFAULTS.combatPulseInR, DEFAULTS.combatPulseInG, DEFAULTS.combatPulseInB = 0.89, 0.79, 0.34
DEFAULTS.combatPulseOutR, DEFAULTS.combatPulseOutG, DEFAULTS.combatPulseOutB = 0.49, 0.67, 0.73
DEFAULTS.combatHoldIn = 1              -- seconds the text stays, between its fades
DEFAULTS.combatHoldOut = 1
DEFAULTS.combatPulseIn = 0.03          -- the screen's edges flash, this strong (0: no)
DEFAULTS.combatPulseOut = 0.01
DEFAULTS.combatIconShowIn = false      -- an icon before the word going in
DEFAULTS.combatIconShowOut = false     -- ...and coming out
DEFAULTS.combatIconIn = "Interface\\Icons\\Ability_DualWield" -- (a file or file ID: IconBrowser.lua)
DEFAULTS.combatIconOut = 132320
DEFAULTS.combatAnim = "fade"           -- "fade"; "reveal": the words open from their middle (or side);
                                       -- "track": their letters close up (tracking in)
DEFAULTS.combatBarFallback = false     -- in a bar with no letterbox up: the lower third (else a bar of our own)
-- Boss fights: the going in cue as a title card, the boss's name for its
-- words, once a run for each boss: as it's pulled, or before that as you
-- first target it or come near it (its Show in row: BOSS_KEY).
DEFAULTS.combatBossPull = true         -- as a boss fight starts (ENCOUNTER_START)
DEFAULTS.combatBossTarget = false      -- as you first target a boss, before the pull
DEFAULTS.combatBossNear = false        -- as you first come within about 28 yards of one
DEFAULTS.combatBossAlways = true       -- its Show in row's Always
DEFAULTS.combatBossHold = 2.5          -- seconds it stays, between its fades
DEFAULTS.combatBossSub = true          -- the dungeon and difficulty under the name
DEFAULTS.combatBossCount = true        -- "Boss 2 of 3" over it, where the Journal knows (on the pull)
-- Its look, apart from the cue's (the Style page's Boss card tab: BOSS_FIELDS):
-- a gold name over a line in the lower third, the dungeon under it.
DEFAULTS.combatBossPlace = "third"
DEFAULTS.combatBossBarScale = 0.62
DEFAULTS.combatBossAlign = "center"
DEFAULTS.combatBossStyle = "chapter"
DEFAULTS.combatBossFont = "general"
DEFAULTS.combatBossSize = 44
DEFAULTS.combatBossOutline = -1
DEFAULTS.combatBossOutlineR, DEFAULTS.combatBossOutlineG, DEFAULTS.combatBossOutlineB = 0, 0, 0
DEFAULTS.combatBossR, DEFAULTS.combatBossG, DEFAULTS.combatBossB = 0.85, 0.71, 0.35 -- #D9B45A
DEFAULTS.combatBossPulse = 0
DEFAULTS.combatBossPulseR, DEFAULTS.combatBossPulseG, DEFAULTS.combatBossPulseB = 0.85, 0.71, 0.35
DEFAULTS.combatBossIconShow = false
DEFAULTS.combatBossIcon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
DEFAULTS.combatBossAnim = "track"
DEFAULTS.combatBossBarFallback = true

-- Its Show in row (GridRows.lua: the places, roles and a rule, which can
-- name cinemode), read as a fight begins.
local ROW_KEY = "vision:combat"
local BOSS_KEY = "vision:boss"

-- The cue's look settings -> a boss card's own (going in's, for the side settings).
local BOSS_FIELDS = {
	combatPlace = "combatBossPlace", combatBarScale = "combatBossBarScale", combatAlign = "combatBossAlign",
	combatStyle = "combatBossStyle", combatFont = "combatBossFont", combatSize = "combatBossSize",
	combatOutline = "combatBossOutline", combatOutlineR = "combatBossOutlineR",
	combatOutlineG = "combatBossOutlineG", combatOutlineB = "combatBossOutlineB",
	combatInR = "combatBossR", combatInG = "combatBossG", combatInB = "combatBossB",
	combatPulseIn = "combatBossPulse", combatPulseInR = "combatBossPulseR", combatPulseInG = "combatBossPulseG",
	combatPulseInB = "combatBossPulseB", combatIconShowIn = "combatBossIconShow", combatIconIn = "combatBossIcon",
	combatHoldIn = "combatBossHold", combatAnim = "combatBossAnim", combatBarFallback = "combatBossBarFallback",
}
-- A look (ns.StyleLook's) read as a boss card's: its own settings for the cue's.
local function BossLook(look)
	return setmetatable({}, { __index = function(_, key) return look[BOSS_FIELDS[key] or key] end })
end

local FADE_IN, FADE_OUT = 0.35, 0.5
local REVEAL = 1.1                 -- Reveal: seconds the words take to open
local REVEAL_OUT = 0.9             -- ...and to fade out, slower
local LATE_FROM, LATE_FOR = 0.6, 0.6 -- ...a boss card's other lines coming in after the name
local TRACK = 1.4                  -- Tracking in: seconds the letters take to close up
local TRACK_FROM = 0.32            -- ...from this much apart (of the text's height)
local PULSE_PEAK, PULSE_GONE = 0.12, 0.9
local CUT_OUT = 0.25               -- a cue cut short (the fight's other edge came first) fades this fast
local OUTLINES = { [0] = "", "OUTLINE", "THICKOUTLINE" }

-- A gradient on texture, from alpha 0 at one end to 1 at the other ("VERTICAL":
-- opaque at the top if high; "HORIZONTAL": opaque at the left if high).
local function Gradient(texture, orientation, high, r, g, b)
	local from, to = high and 0 or 1, high and 1 or 0
	if orientation == "HORIZONTAL" then from, to = to, from end
	texture:SetColorTexture(1, 1, 1, 1)
	if texture.SetGradient and CreateColor then
		texture:SetGradient(orientation, CreateColor(r, g, b, from), CreateColor(r, g, b, to))
	elseif texture.SetGradientAlpha then
		texture:SetGradientAlpha(orientation, r, g, b, from, r, g, b, to)
	else
		texture:SetColorTexture(r, g, b, 0.4)
	end
end

-- The chapter line's color: flat, or fading out to the right (the lower third).
local function LineColor(line, r, g, b, fade)
	if fade then
		Gradient(line, "HORIZONTAL", true, r, g, b)
	elseif line.SetGradient and CreateColor then
		line:SetColorTexture(1, 1, 1, 1)
		line:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.8), CreateColor(r, g, b, 0.8))
	elseif line.SetGradientAlpha then
		line:SetColorTexture(1, 1, 1, 1)
		line:SetGradientAlpha("HORIZONTAL", r, g, b, 0.8, r, g, b, 0.8)
	else
		line:SetColorTexture(r, g, b, 0.8)
	end
end

-- A cue's parts on frame (the real one over the screen, or the preview's):
-- letterbox bars of its own, a pulse round the edges, and over them the
-- text, its line and the icon.
local function MakeCue(frame)
	local bars = CreateFrame("Frame", nil, frame)
	bars:SetAllPoints()
	ns.MakeLetterboxBars(bars)
	local pulse = CreateFrame("Frame", nil, frame)
	pulse:SetAllPoints()
	pulse:SetFrameLevel(bars:GetFrameLevel() + 1)
	pulse.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = pulse:CreateTexture(nil, "ARTWORK")
		if side == "TOP" or side == "BOTTOM" then
			edge:SetPoint(side .. "LEFT")
			edge:SetPoint(side .. "RIGHT")
		else
			edge:SetPoint("TOP" .. side)
			edge:SetPoint("BOTTOM" .. side)
		end
		pulse.edges[side] = edge
	end
	local over = CreateFrame("Frame", nil, frame)
	over:SetAllPoints()
	over:SetFrameLevel(pulse:GetFrameLevel() + 1)
	-- The words in a window that opens from their middle or side (Reveal).
	local clip = CreateFrame("Frame", nil, over)
	if clip.SetClipsChildren then clip:SetClipsChildren(true) end
	local text = clip:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.8)
	-- An outline in a color: the text again behind it, nudged each way (the
	-- game's own outline is always black).
	text.rim = {}
	for i = 1, 8 do
		text.rim[i] = clip:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		text.rim[i]:SetDrawLayer("OVERLAY", -1)
	end
	local line = over:CreateTexture(nil, "OVERLAY")
	local icon = over:CreateTexture(nil, "OVERLAY")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- A boss card's lines: the dungeon under the name, the boss's number over it.
	local sub = over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	local meta = over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	for _, each in ipairs({ sub, meta }) do
		each:SetShadowOffset(1, -1)
		each:SetShadowColor(0, 0, 0, 0.8)
	end
	frame.cue = { bars = bars, pulse = pulse, over = over, clip = clip, text = text, line = line, icon = icon,
		sub = sub, meta = meta }
	bars:Hide()
	pulse:Hide()
	over:Hide()
	return frame.cue
end

local function FontFile(look)
	return ns.StyleFontFile(look.combatFont) or (GameFontNormalHuge:GetFont())
end

-- The words at key (combatTextIn, combatTextOut) as shown: the defaults in
-- the game's language.
local function ShownWords(look, key)
	local word = look[key] or DEFAULTS[key]
	return word == DEFAULTS[key] and L[word] or word
end

-- Tracking in: the words' letters each a text of their own, each where it
-- sits in the whole words (cue.letterAt) plus spacing for each character
-- before it (cue.letterIndex), about cue.text's origin. At no spacing they
-- sit just as the whole words do, so the swap back to them can't be seen.
local function LayLetters(cue, spacing)
	local total = cue.wordsWidth + spacing * (cue.charCount - 1)
	local origin = cue.trackOrigin
	local x = origin == "LEFT" and 0 or origin == "RIGHT" and -total or -total / 2
	for i = 1, cue.letterCount do
		cue.letters[i]:SetPoint("LEFT", cue.text, origin, x + cue.letterAt[i] + spacing * (cue.letterIndex[i] - 1), 0)
	end
end

-- Sets up cue for a going in (enter) or coming out, on a screen width x
-- height; scale: that next to the real screen (the preview's smaller).
-- boss: a boss card's { name, sub, meta } (the name can be secret: shown,
-- never read).
local function Setup(cue, look, enter, width, height, scale, boss)
	local r, g, b, pr, pg, pb
	if enter then
		r, g, b = look.combatInR, look.combatInG, look.combatInB
		pr, pg, pb = look.combatPulseInR, look.combatPulseInG, look.combatPulseInB
	else
		r, g, b = look.combatOutR, look.combatOutG, look.combatOutB
		pr, pg, pb = look.combatPulseOutR, look.combatPulseOutG, look.combatPulseOutB
	end
	local word = boss and boss.name or ShownWords(look, enter and "combatTextIn" or "combatTextOut")
	local secret = issecretvalue ~= nil and issecretvalue(word)
	local style, place = look.combatStyle, look.combatPlace
	if not secret and word == "" then style = "none" end
	-- (In a bar with no letterbox up, if it says so: the lower third.)
	if (place == "top" or place == "bottom") and look.combatBarFallback
		and not (ns.db.letterbox and (scale ~= 1 or ns.lastCinematic)
		and ns.LetterboxHeight(ns.LetterboxLook(), width, height) >= 1) then
		place = "third"
	end
	local size = look.combatSize * scale
	if style == "subtitle" then
		size = math.max(size * 0.5, 11 * scale)
		if not secret then word = "- " .. word .. " -" end
	elseif style == "chapter" then
		size = size * 0.65
	end
	local text, line, icon = cue.text, cue.line, cue.icon
	text:ClearAllPoints()
	line:ClearAllPoints()
	icon:ClearAllPoints()
	cue.barSide, cue.lineWidth, cue.third = nil, nil, place == "third"
	local x, y, point, relative = 0, 0, "CENTER", "CENTER"
	if place == "top" or place == "bottom" then
		-- With the letterbox up (in CineMode; the preview as if it were): in
		-- its bar. Else in a bar of our own, as tall as the letterbox's. The
		-- text scales with the bar (combatBarScale).
		local barLook = ns.LetterboxLook()
		local full = ns.LetterboxHeight(barLook, width, height)
		local active = ns.db.letterbox and (scale ~= 1 or ns.lastCinematic) and full >= 1
		local want = full >= 1 and full or size * 1.5
		size = math.max(want * look.combatBarScale, 6 * scale)
		cue.ownBar = not (active and scale == 1)
		local side = place == "top" and "TOP" or "BOTTOM"
		local align = look.combatAlign == "left" and "LEFT" or look.combatAlign == "right" and "RIGHT" or ""
		point, relative = align ~= "" and align or "CENTER", side .. align
		x = (align == "LEFT" and 1 or align == "RIGHT" and -1 or 0) * math.max(16 * scale, want * 0.6)
		y = (side == "TOP" and -1 or 1) * want / 2
		cue.barSide, cue.barShare = side, want / height
		if style == "chapter" then
			line:SetPoint("CENTER", cue.over, side, 0, (side == "TOP" and -1 or 1) * (want - 1))
		end
	elseif place == "third" then
		-- The lower third: low on the left, the line under it fading out.
		point, relative, x, y = "BOTTOMLEFT", "BOTTOMLEFT", width * 0.07, height * 0.22
		if style == "chapter" then line:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6 * scale) end
	elseif style == "title" then
		y = height * 0.12
	elseif style == "subtitle" then
		point, relative, y = "BOTTOM", "BOTTOM", height * 0.16
	elseif style == "chapter" then
		y = height * 0.14
		line:SetPoint("TOP", text, "BOTTOM", 0, -6 * scale)
	end
	text:SetPoint(point, cue.over, relative, x, y)
	text:SetText(word)
	local outline = OUTLINES[look.combatOutline] or ""
	local or_, og, ob = look.combatOutlineR or 0, look.combatOutlineG or 0, look.combatOutlineB or 0
	local rimmed = outline ~= "" and or_ + og + ob > 0
	local fontSize = math.floor(size + 0.5)
	ns.SetPlateNameFont(text, GameFontNormalHuge, FontFile(look), fontSize, 1, rimmed and "" or outline)
	text:SetTextColor(r, g, b, 1)
	text:SetVertexColor(r, g, b, 1) -- (one and the same on Forever)
	text:SetShown(style ~= "none")
	local nudge = (outline == "THICKOUTLINE" and 2 or 1) * math.max(scale, 0.5)
	for i, rim in ipairs(text.rim) do
		rim:SetShown(rimmed and style ~= "none")
		if rimmed then
			local angle = (i - 1) * math.pi / 4
			rim:ClearAllPoints()
			rim:SetPoint("CENTER", text, "CENTER", math.cos(angle) * nudge, math.sin(angle) * nudge)
			rim:SetText(word)
			ns.SetPlateNameFont(rim, GameFontNormalHuge, FontFile(look), fontSize, 1, "")
			rim:SetTextColor(or_, og, ob, 1)
			rim:SetVertexColor(or_, og, ob, 1)
			rim:SetShadowOffset(0, 0)
		end
	end
	if style == "chapter" then
		LineColor(line, r, g, b, cue.third)
		line:SetHeight(math.max(1, scale))
		-- (A secret name's width is secret too: then a fixed share of the screen.)
		local textWidth = text:GetStringWidth()
		if issecretvalue and issecretvalue(textWidth) then textWidth = width * 0.2 end
		cue.lineWidth = cue.barSide and width * 0.6 or cue.third and width * 0.26
			or math.max(textWidth * 1.6, width * 0.3)
	end
	line:SetShown(style == "chapter")
	-- A boss card's lines: in a bar, the dungeon beside the name (before it
	-- when on the right); on the screen, the dungeon under it (under its line)
	-- and the boss's number over it.
	local sub, meta = cue.sub, cue.meta
	sub:ClearAllPoints()
	meta:ClearAllPoints()
	local subText = boss and style ~= "none" and boss.sub or ""
	local metaText = boss and style ~= "none" and not cue.barSide and boss.meta or ""
	local subR, subG, subB = (r + 1) / 2, (g + 1) / 2, (b + 1) / 2
	local plain = outline ~= "" and "OUTLINE" or ""
	local before = cue.barSide and look.combatAlign == "right"
	if subText ~= "" then
		local subSize = cue.barSide and size * 0.7 or math.max(size * 0.42, 10 * scale)
		ns.SetPlateNameFont(sub, GameFontNormalHuge, FontFile(look), math.floor(subSize + 0.5), 1, plain)
		sub:SetText(subText)
		sub:SetTextColor(subR, subG, subB, 1)
		sub:SetVertexColor(subR, subG, subB, 1)
		local under = style == "chapter" and line or text
		if before then
			cue.subAt = { "RIGHT", text, "LEFT", -size * 0.8, 0 }
		elseif cue.barSide then
			cue.subAt = { "LEFT", text, "RIGHT", size * 0.8, 0 }
		elseif cue.third then
			cue.subAt = { "TOPLEFT", under, "BOTTOMLEFT", 0, -size * 0.25 }
		else
			cue.subAt = { "TOP", under, "BOTTOM", 0, -size * 0.25 }
		end
		sub:SetPoint(unpack(cue.subAt))
	end
	sub:SetShown(subText ~= "")
	if metaText ~= "" then
		local metaSize = math.max(size * 0.3, 8 * scale)
		ns.SetPlateNameFont(meta, GameFontNormalHuge, FontFile(look), math.floor(metaSize + 0.5), 1, plain)
		meta:SetText(metaText)
		meta:SetTextColor(0.8, 0.78, 0.72, 1)
		meta:SetVertexColor(0.8, 0.78, 0.72, 1)
		cue.metaAt = cue.third and { "BOTTOMLEFT", text, "TOPLEFT", 0, size * 0.2 }
			or { "BOTTOM", text, "TOP", 0, size * 0.2 }
		meta:SetPoint(unpack(cue.metaAt))
	end
	meta:SetShown(metaText ~= "")
	-- Reveal: the words' window opens from where they're anchored (Draw), a
	-- boss card's other lines rising in after them.
	local clip = cue.clip
	clip:ClearAllPoints()
	local origin = point:find("LEFT") and "LEFT" or point:find("RIGHT") and "RIGHT" or "CENTER"
	local pad = size * 0.5
	clip:SetPoint(origin, text, origin, origin == "LEFT" and -pad or origin == "RIGHT" and pad or 0, 0)
	clip:SetHeight(size * 2.5)
	-- (Tracking in needs the words' letters: a secret name opens as Reveal.)
	local anim = look.combatAnim
	if anim == "track" and (secret or style == "none") then anim = "reveal" end
	cue.reveal, cue.track = anim == "reveal", anim == "track"
	cue.clipWidth = width
	clip:SetWidth(cue.reveal and 1 or width)
	cue.late, cue.rise = (cue.reveal or cue.track) and (subText ~= "" or metaText ~= ""), size * 0.15
	-- Tracking in: a text for each letter, the same font and color, laid out
	-- apart (Draw closes them up, then the words show whole again).
	cue.letters = cue.letters or {}
	local count = 0
	if cue.track then
		-- (Each letter's place: the words up to and with it, less the letter
		-- itself, measured in the words' own font, so pairs keep their kerning.)
		local flags = rimmed and "" or outline
		local measure = cue.measure
		if not measure then
			measure = cue.over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
			measure:Hide()
			cue.measure = measure
		end
		local function Width(part)
			measure:SetText(part)
			ns.SetPlateNameFont(measure, GameFontNormalHuge, FontFile(look), fontSize, 1, flags)
			return measure:GetStringWidth()
		end
		cue.letterAt, cue.letterIndex = cue.letterAt or {}, cue.letterIndex or {}
		cue.trackOrigin, cue.trackFrom = origin, size * TRACK_FROM
		cue.wordsWidth = Width(word)
		local before, index = "", 0
		for char in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			index = index + 1
			if char ~= " " then
				count = count + 1
				local letter = cue.letters[count]
				if not letter then
					letter = cue.over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
					letter:SetShadowOffset(1, -1)
					letter:SetShadowColor(0, 0, 0, 0.8)
					cue.letters[count] = letter
				end
				letter:ClearAllPoints()
				letter:SetText(char)
				ns.SetPlateNameFont(letter, GameFontNormalHuge, FontFile(look), fontSize, 1, flags)
				letter:SetTextColor(r, g, b, 1)
				letter:SetVertexColor(r, g, b, 1)
				letter:Show()
				cue.letterAt[count] = Width(before .. char) - Width(char)
				cue.letterIndex[count] = index
			end
			before = before .. char
		end
		cue.letterCount, cue.charCount = count, index
		if count > 0 then LayLetters(cue, cue.trackFrom) end
	end
	for i = count + 1, #cue.letters do cue.letters[i]:Hide() end
	cue.tracking = cue.track and count > 0
	text:SetAlpha(cue.tracking and 0 or 1)
	for _, rim in ipairs(text.rim) do rim:SetAlpha(cue.tracking and 0 or 1) end
	sub:SetAlpha(1)
	meta:SetAlpha(1)
	local showIcon = look[enter and "combatIconShowIn" or "combatIconShowOut"] and true or false
	icon:SetShown(showIcon)
	if showIcon then
		icon:SetTexture(enter and look.combatIconIn or look.combatIconOut)
		icon:SetSize(size * 1.1, size * 1.1)
		if style == "none" then
			icon:SetPoint(point, cue.over, relative, x, y)
		else
			icon:SetPoint("RIGHT", before and subText ~= "" and sub or text, "LEFT", -size * 0.35, 0)
		end
	end
	for side, edge in pairs(cue.pulse.edges) do
		local thick = (side == "TOP" or side == "BOTTOM") and height * 0.2 or width * 0.12
		if side == "TOP" or side == "BOTTOM" then edge:SetHeight(thick) else edge:SetWidth(thick) end
		Gradient(edge, (side == "TOP" or side == "BOTTOM") and "VERTICAL" or "HORIZONTAL",
			side == "TOP" or side == "LEFT", pr, pg, pb)
	end
	cue.look, cue.enter, cue.width, cue.height, cue.scale = look, enter, width, height, scale
	cue.barLook = cue.barSide and setmetatable({ letterboxSizeBy = "height", letterboxSize = cue.barShare,
		letterboxMotion = "slide" }, { __index = ns.LetterboxLook() })
end

-- How far cue is faded in age seconds in (0 to 1, before easing), and its
-- length.
local function Shown(cue, age)
	local look = cue.look
	local hold = cue.enter and look.combatHoldIn or look.combatHoldOut -- (a boss card's: BossLook's)
	local fadeOut = (cue.reveal or cue.track) and REVEAL_OUT or FADE_OUT
	local a
	if age < FADE_IN then
		a = age / FADE_IN
	elseif age > FADE_IN + hold then
		a = 1 - (age - FADE_IN - hold) / fadeOut
	else
		a = 1
	end
	return math.max(a, 0), FADE_IN + hold + fadeOut
end

-- Draws cue age seconds in. Gives false once it's over (and hidden). Cut
-- short (cue.cutAt, cue.cutFrom: when, and how shown then), it fades out
-- from there in CUT_OUT.
local function Draw(cue, age)
	local look = cue.look
	local a, length = Shown(cue, age)
	local cut = 1
	if cue.cutAt then
		cut = 1 - (age - cue.cutAt) / CUT_OUT
		a = math.min(a, cue.cutFrom * cut)
	end
	if age >= length or cut <= 0 then
		cue.bars:Hide()
		cue.pulse:Hide()
		cue.over:Hide()
		return false
	end
	a = a * a * (3 - 2 * a)
	cue.over:Show()
	cue.over:SetAlpha(a)
	-- (Reveal: the window opening, eased out; the line drawing out with it.)
	local open = a
	if cue.reveal then
		open = 1 - (1 - math.min(age / REVEAL, 1)) ^ 4
		cue.clip:SetWidth(math.max(cue.clipWidth * open, 1))
	elseif cue.track then
		-- (Tracking in: the letters closing up, eased out; once together, the
		-- words whole, with their kerning and outline.)
		local t = math.min(age / TRACK, 1)
		open = 1 - (1 - t) ^ 3
		if cue.tracking then
			if t < 1 then
				LayLetters(cue, cue.trackFrom * (1 - open))
			else
				cue.tracking = false
				for i = 1, cue.letterCount do cue.letters[i]:Hide() end
				cue.text:SetAlpha(1)
				for _, rim in ipairs(cue.text.rim) do rim:SetAlpha(1) end
			end
		end
	end
	if cue.lineWidth then cue.line:SetWidth(math.max(cue.lineWidth * open, 0.01)) end
	if cue.late then
		local t = math.max(0, math.min((age - LATE_FROM) / LATE_FOR, 1))
		t = t * t * (3 - 2 * t)
		for _, each in ipairs({ { cue.sub, cue.subAt }, { cue.meta, cue.metaAt } }) do
			local at = each[2]
			if at and each[1]:IsShown() then
				each[1]:SetAlpha(t)
				each[1]:SetPoint(at[1], at[2], at[3], at[4], at[5] - cue.rise * (1 - t))
			end
		end
	end
	local pulse = 0
	local strength = cue.enter and look.combatPulseIn or look.combatPulseOut
	if strength > 0 then
		pulse = age < PULSE_PEAK and age / PULSE_PEAK or math.max(0, 1 - (age - PULSE_PEAK) / (PULSE_GONE - PULSE_PEAK))
	end
	pulse = pulse * cut
	cue.pulse:SetShown(pulse > 0)
	cue.pulse:SetAlpha(pulse * strength)
	cue.bars:SetShown(cue.barSide ~= nil and cue.ownBar)
	if cue.barSide and cue.ownBar then
		local bars = cue.bars
		ns.DrawLetterbox(bars, cue.barLook, cue.width, cue.height, a, cue.scale)
		local other = cue.barSide == "TOP" and "bottom" or "top"
		bars[other]:Hide()
		bars[other .. "Feather"]:Hide()
		bars[other .. "Line"]:Hide()
		bars[cue.barSide == "TOP" and "top" or "bottom"]:Show()
	end
	return true
end

-- Plays cue on frame: its OnUpdate runs it to the end. look: ns.db. after:
-- called once it's done (not if another cue on frame cuts it short).
local function Play(frame, look, enter, width, height, scale, boss, after)
	local cue = frame.cue or MakeCue(frame)
	Setup(cue, look, enter, width, height, scale, boss)
	local age = 0
	cue.cutAt = nil
	-- Cut short: a quick fade out from as shown as it is now.
	cue.cut = function()
		if cue.cutAt then return end
		cue.cutAt, cue.cutFrom = age, (Shown(cue, age))
	end
	Draw(cue, 0)
	frame:SetScript("OnUpdate", function(self, elapsed)
		age = age + elapsed
		if not Draw(cue, age) then
			self:SetScript("OnUpdate", nil)
			if after then after() end
		end
	end)
end

-- The real cue, over the whole screen (kept when the UI is hidden: an overlay).
local screen
-- cine: CineMode as the fight began, for the sound rules (nil: as it is now).
-- boss: a boss card (Setup's), going in. after: Play's.
function ns.PlayCombatVision(enter, cine, boss, after)
	if not screen then
		screen = CreateFrame("Frame", "CinematicCombatVision", UIParent)
		screen:SetAllPoints(UIParent)
		screen:SetFrameStrata("LOW")
		screen:EnableMouse(false)
		ns.AddOverlay(screen)
	end
	local look = ns.StyleLook("combatVision")
	Play(screen, boss and BossLook(look) or look, enter, UIParent:GetWidth(), UIParent:GetHeight(), 1, boss, after)
	if boss and boss.quiet then return end -- (a card before the pull: no fight's sound yet)
	if cine == nil then cine = ns.lastCinematic and true or false end
	ns.PlayCombatCueSound(enter and "enter" or "leave", cine) -- (CombatSoundRules.lua)
end

-- The real cue cut short if it's a going in (enter) or coming out one still
-- playing: the fight ended (or began again) before it was done.
local function CutCombatVision(enter)
	local cue = screen and screen.cue
	if cue and cue.cut and cue.enter == enter and screen:GetScript("OnUpdate") then
		cue.cut()
	end
end

-- Whether the cue plays as a fight starts (edge "enter") or ends ("leave"):
-- its Show in row, read with the rules' entering or leaving true and
-- cinemode as the fight began. With no rule, its Combat dropdown's ticks
-- (combatOnEnter, combatOnLeave) say which; a rule says it all itself.
local fightStart, cineAtStart = 0, false
local function Allowed(db, edge)
	if not db.combatVision then
		return false
	end
	ns.combatEdge, ns.combatEdgeCine = edge, cineAtStart
	local ok, shows = pcall(ns.RowOnNow, ROW_KEY, db.combatAlways, true)
	ns.combatEdge = nil
	if not (ok and shows) then
		return false
	end
	local rule = type(db.frameRules) == "table" and db.frameRules[ROW_KEY]
	if type(rule) == "string" and rule:find("%S") and ns.CompileRule(rule) then
		return true
	end
	return db[edge == "enter" and "combatOnEnter" or "combatOnLeave"] and true or false
end

-- Boss cards. A boss is told by the pull (ENCOUNTER_START: its name, plain)
-- or, before it, as an enemy elite in a dungeon or raid at a skull's level,
-- or on retail two or more levels over yours (the trash at yours, tested:
-- names and GUIDs there are secret even out of a fight, so no Journal match).
-- Each encounter's card shows once a run (a wipe doesn't bring it back). One
-- shown before a pull (target, near) holds the next until a boss dies, as
-- which boss it was can't be told; that boss's pull then has the usual cue.
local PULL_GAP = 2      -- seconds the pull and the fight's start can be apart
local PRE_HOLD = 300    -- a card before a pull holds the next this long at most (no kill: not a boss)
local NEAR_EVERY = 0.5  -- seconds between looks at the plates for one near
local OUTSIDE_RESET = 600 -- back in after this long outside: a new run
local bossRun = { shown = {}, cardAt = -math.huge, preAt = -math.huge }

local function Plain(fn, ...)
	local ok, value = pcall(fn, ...)
	if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

local function InsideInstance()
	local _, kind = GetInstanceInfo()
	return kind == "party" or kind == "raid"
end

-- Why a card showed or not, while /cine debug boss watch runs (it sets ns.BossCardLog).
local function BossLog(text)
	if ns.BossCardLog then ns.BossCardLog(text) end
end

-- The line under the name: the dungeon and its difficulty ("" for none).
local function InstanceLine(look)
	if not look.combatBossSub then return "" end
	local name, kind, _, difficulty = GetInstanceInfo()
	if kind == "none" or type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or name == "" then
		return ""
	end
	if type(difficulty) == "string" and not (issecretvalue and issecretvalue(difficulty)) and difficulty ~= "" then
		return name .. " · " .. difficulty
	end
	return name
end

-- "Boss 2 of 3" for an encounter, from the Journal where it knows ("" else).
local function BossNumber(encounterID, look)
	if not (look.combatBossCount and EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex) then return "" end
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local ok, journal = pcall(EJ_GetInstanceForMap, mapID or 0)
	if not ok or not journal or journal == 0 then return "" end
	-- (The Journal's own choice put back after, in case its window is open.)
	local before = EJ_GetCurrentInstance and EJ_GetCurrentInstance()
	if EJ_SelectInstance then pcall(EJ_SelectInstance, journal) end
	local count, index = 0, nil
	while count < 40 do
		local okInfo, name, _, _, _, _, _, dungeonEncounter = pcall(EJ_GetEncounterInfoByIndex, count + 1, journal)
		if not okInfo or not name then break end
		count = count + 1
		if dungeonEncounter == encounterID then index = count end
	end
	if before and before ~= 0 and before ~= journal and EJ_SelectInstance then pcall(EJ_SelectInstance, before) end
	if index and index == count and count > 1 then return L["Final boss"] end
	return index and L["Boss %d of %d"]:format(index, count) or ""
end

-- A made-up boss card for the preview and the Test button (in an instance:
-- its own line under the name).
local function SampleBoss(look)
	local sub = InstanceLine(look)
	if sub == "" and look.combatBossSub then sub = L["The Deadmines"] .. " · " .. L["Normal"] end
	return { name = L["Edwin VanCleef"], sub = sub, meta = look.combatBossCount and L["Boss %d of %d"]:format(5, 5) or "" }
end

-- Whether unit looks like a boss before its pull (plain answers only), and why.
local function LooksLikeBoss(unit)
	if not InsideInstance() then return false, "not in a dungeon or raid" end
	local rank = ns.EnemyNPCRank(unit)
	if rank ~= "elite" then return false, "rank " .. (Plain(tostring, rank) or "secret") end
	local level = Plain(UnitLevel, unit)
	if level == -1 or Plain(UnitClassification, unit) == "worldboss" then return true, "skull level or world boss" end
	local mine = UnitLevel("player")
	if ns.isRetail and type(level) == "number" and type(mine) == "number" and level >= mine + 2 then
		return true, ("level %d, yours %d"):format(level, mine)
	end
	return false, ("elite at level %s, yours %s: not a skull%s"):format(tostring(level), tostring(mine),
		ns.isRetail and " or 2 over" or "")
end

-- Whether a boss card may show now, by tick (combatBossPull...) and its Show in row, and why not.
local function BossAllowed(db, tick)
	if not db.combatVision then return false, "Combat Vision off" end
	if not db[tick] then return false, tick .. " off" end
	ns.combatEdge, ns.combatEdgeCine = "enter", ns.lastCinematic and true or false
	local ok, shows = pcall(ns.RowOnNow, BOSS_KEY, db.combatBossAlways, true)
	ns.combatEdge = nil
	if not ok then return false, "Show in row errored" end
	if not shows then return false, "its Show in row says not now" end
	return true
end

-- A card before the pull, for unit (target, a plate): once until a boss dies.
local function CardBeforePull(unit, tick)
	local db = ns.db
	if not db then return end
	local who = (Plain(UnitName, unit) or "a secret name") .. " (" .. tick .. ")"
	local why
	if InCombatLockdown() then
		why = "in combat"
	elseif bossRun.encounterOn then
		why = "an encounter is on"
	elseif GetTime() - bossRun.preAt < PRE_HOLD then
		why = ("held %.0fs more: a card already showed before a pull, no boss killed since"):format(
			PRE_HOLD - (GetTime() - bossRun.preAt))
	end
	local looks, how
	if not why then
		looks, how = LooksLikeBoss(unit)
		if not looks then why = "not boss-like: " .. how end
	end
	if not why then
		local allowed, no = BossAllowed(db, tick)
		if not allowed then why = no end
	end
	if why then
		BossLog(("no card for %s: %s"):format(who, why))
		return
	end
	BossLog(("card before the pull for %s: %s"):format(who, how))
	bossRun.preAt = GetTime()
	local look = ns.StyleLook("combatVision")
	ns.PlayCombatVision(true, nil, { name = (UnitName(unit)), sub = InstanceLine(look), meta = "", quiet = true })
end

-- Near: the plates looked at twice a second, only out of a fight in an instance.
local nearLook = CreateFrame("Frame")
nearLook:Hide()
local nearWait = 0
nearLook:SetScript("OnUpdate", function(_, elapsed)
	nearWait = nearWait - elapsed
	if nearWait > 0 then return end
	nearWait = NEAR_EVERY
	local db = ns.db
	if not (db and db.combatVision and db.combatBossNear) or InCombatLockdown() or bossRun.encounterOn
		or GetTime() - bossRun.preAt < PRE_HOLD then
		return
	end
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and Plain(CheckInteractDistance, unit, 4) == true and LooksLikeBoss(unit) then
			CardBeforePull(unit, "combatBossNear")
			return
		end
	end
end)

-- A new run: another instance, or back in after long outside.
local function EnteredWorld()
	local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local inside = InsideInstance()
	nearLook:SetShown(inside)
	if not inside then
		bossRun.leftAt = bossRun.leftAt or GetTime()
		return
	end
	if instanceID ~= bossRun.instance or GetTime() - (bossRun.leftAt or GetTime()) > OUTSIDE_RESET then
		bossRun.shown, bossRun.preAt, bossRun.encounterOn = {}, -math.huge, nil
		BossLog(("new run in instance %s: every boss's card can show again"):format(tostring(instanceID)))
	end
	bossRun.instance, bossRun.leftAt = instanceID, nil
end

-- The pull: its card in place of the going in cue, the first time this run.
local function EncounterStart(db, encounterID, name)
	bossRun.encounterOn = true
	local key = (issecretvalue and issecretvalue(encounterID)) and "?" or encounterID
	local who = ("%s (encounter %s)"):format(Plain(tostring, name) or "a secret name", tostring(key))
	if bossRun.shown[key] then
		BossLog(("no card at the pull of %s: its card showed already this run"):format(who))
		return
	end
	bossRun.shown[key] = true
	-- (Its card already showed before the pull: the usual cue.)
	if GetTime() - bossRun.preAt < PRE_HOLD then
		BossLog(("no card at the pull of %s: a card showed before it (%.0fs ago), so the usual cue"):format(who,
			GetTime() - bossRun.preAt))
		return
	end
	local allowed, no = BossAllowed(db, "combatBossPull")
	if not allowed then
		BossLog(("no card at the pull of %s: %s"):format(who, no))
		return
	end
	local look = ns.StyleLook("combatVision")
	local card = { name = name ~= nil and name or "", sub = InstanceLine(look), meta = key ~= "?" and BossNumber(encounterID, look) or "",
		at = GetTime() }
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		-- (Already fighting, a pull from range: over the cue playing.)
		BossLog(("card at the pull of %s, already in combat: plays now (%s)"):format(who, card.meta))
		bossRun.cardAt = GetTime()
		ns.PlayCombatVision(true, ns.lastCinematic and true or false, card)
	else
		BossLog(("card at the pull of %s: waits for combat to start (%s)"):format(who, card.meta))
		bossRun.pending = card
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
for _, event in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END" }) do
	pcall(watcher.RegisterEvent, watcher, event) -- (each client that has them)
end
watcher:SetScript("OnEvent", function(_, event, ...)
	local db = ns.db
	if not db then
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		CutCombatVision(false) -- (a respite still showing; a going in cue below plays over it anyway)
		fightStart, cineAtStart = GetTime(), ns.lastCinematic and true or false
		local card = bossRun.pending
		bossRun.pending = nil
		if card then
			BossLog(("combat started %.2fs after the pull: %s"):format(GetTime() - card.at,
				GetTime() - card.at < PULL_GAP and "its card plays" or "too late for its card, the usual cue"))
		end
		if card and GetTime() - card.at < PULL_GAP then
			bossRun.cardAt = GetTime()
			ns.PlayCombatVision(true, cineAtStart, card)
		elseif GetTime() - bossRun.cardAt >= PULL_GAP and Allowed(db, "enter") then
			ns.PlayCombatVision(true, cineAtStart)
		elseif GetTime() - bossRun.cardAt < PULL_GAP then
			BossLog("combat started: no going in cue, a boss card just played")
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		CutCombatVision(true) -- (the going in cue or a boss card still showing)
		if GetTime() - fightStart >= db.combatMinFight and Allowed(db, "leave") then
			ns.PlayCombatVision(false, cineAtStart)
		end
	elseif event == "ENCOUNTER_START" then
		EncounterStart(db, ...)
	elseif event == "ENCOUNTER_END" then
		local _, _, _, _, success = ...
		bossRun.encounterOn = nil
		if Plain(tostring, success) == "1" then bossRun.preAt = -math.huge end -- (a boss down: the next may show before its pull)
		BossLog(("encounter ended, success %s: %s"):format(Plain(tostring, success) or "secret",
			Plain(tostring, success) == "1" and "the next boss's card may show before its pull" or "a card before a pull stays held"))
	elseif event == "PLAYER_TARGET_CHANGED" then
		if db.combatBossTarget and UnitExists("target") then CardBeforePull("target", "combatBossTarget") end
	else
		EnteredWorld()
	end
end)

-- Both pages' tabs: the cue (Combat) and the Boss card, the one picked kept
-- for both. onPick(tab) after a pick. Gives Part(tab, build, group): what
-- build puts on content shows only on that tab (each tab's part of a group
-- starts at the same place, so neither leaves a gap), and Finish() once the
-- page is built. Folder tabs as Heal Vision's (Options.lua): the picked one
-- taller, lit, a gold top, in the panel's colour with no line between, so
-- they look one piece; the rest dark behind. The panel holds the rest of the
-- page, its top edge either side of the picked tab.
local tabNow = "combat"
local TAB_W, TAB_H, TAB_GAP, PANEL_PAD = 100, 24, 4, 10
local PANEL_BG, TAB_BG = { 0.12, 0.12, 0.13, 0.9 }, { 0.04, 0.04, 0.05, 0.9 }
local EDGE, DIM_EDGE = { 0.42, 0.42, 0.42, 1 }, { 0.22, 0.22, 0.22, 1 }
local function PageTabs(kit, content, stack, onPick)
	local row = CreateFrame("Frame", nil, content)
	row:SetSize(480, TAB_H + 4)
	stack:Add(row, "label")
	local panel = CreateFrame("Frame", nil, content)
	panel:SetFrameLevel(content:GetFrameLevel()) -- (under the settings on it)
	panel:SetPoint("TOPLEFT", row, "BOTTOMLEFT", -PANEL_PAD, 0)
	panel:SetSize(480, 100) -- (as the page lays out: Layout)
	local function Line(parent, color)
		local line = parent:CreateTexture(nil, "BORDER")
		line:SetColorTexture(unpack(color))
		return line
	end
	local panelBg = panel:CreateTexture(nil, "BACKGROUND")
	panelBg:SetAllPoints()
	panelBg:SetColorTexture(unpack(PANEL_BG))
	local leftEdge, rightEdge, bottomEdge = Line(panel, EDGE), Line(panel, EDGE), Line(panel, EDGE)
	leftEdge:SetPoint("TOPLEFT")
	leftEdge:SetPoint("BOTTOMLEFT")
	leftEdge:SetWidth(1)
	rightEdge:SetPoint("TOPRIGHT")
	rightEdge:SetPoint("BOTTOMRIGHT")
	rightEdge:SetWidth(1)
	bottomEdge:SetPoint("BOTTOMLEFT")
	bottomEdge:SetPoint("BOTTOMRIGHT")
	bottomEdge:SetHeight(1)
	local topLeft, topRight = Line(panel, EDGE), Line(panel, EDGE)
	topLeft:SetHeight(1)
	topRight:SetHeight(1)
	local function PaintTab(tab, on)
		tab:SetHeight(on and TAB_H + 4 or TAB_H)
		tab.bg:SetColorTexture(unpack(on and PANEL_BG or TAB_BG))
		for _, side in ipairs({ tab.left, tab.right, tab.top }) do
			side:SetColorTexture(unpack(on and EDGE or DIM_EDGE))
		end
		if on then tab.top:SetColorTexture(1, 0.82, 0, 1) end
		tab.top:SetHeight(on and 2 or 1)
		local r, g, b = 1, 0.82, 0
		if on then r, g, b = 1, 1, 1 end
		tab.label:SetTextColor(r, g, b)
		tab.label:SetVertexColor(r, g, b) -- (one on Forever)
		if on then
			topLeft:ClearAllPoints()
			topLeft:SetPoint("TOPLEFT", panel, "TOPLEFT")
			topLeft:SetPoint("TOPRIGHT", tab, "BOTTOMLEFT", 1, 0)
			topRight:ClearAllPoints()
			topRight:SetPoint("TOPLEFT", tab, "BOTTOMRIGHT", -1, 0)
			topRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
		end
	end
	local TABS = {
		{ "combat", L["Combat"], L["The cue going into a fight and coming out of it."] },
		{ "boss", L["Boss card"], L["A boss's name as a title card, as its fight starts or before it."] },
	}
	for i, info in ipairs(TABS) do
		local tab = CreateFrame("Button", nil, content)
		tab:SetSize(TAB_W, TAB_H)
		tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		tab.label:SetPoint("CENTER", 0, 1)
		tab:SetFontString(tab.label)
		tab:SetText(info[2])
		tab.bg = tab:CreateTexture(nil, "BACKGROUND")
		tab.bg:SetAllPoints()
		tab.left, tab.right, tab.top = Line(tab, EDGE), Line(tab, EDGE), Line(tab, EDGE)
		tab.left:SetPoint("TOPLEFT")
		tab.left:SetPoint("BOTTOMLEFT")
		tab.left:SetWidth(1)
		tab.right:SetPoint("TOPRIGHT")
		tab.right:SetPoint("BOTTOMRIGHT")
		tab.right:SetWidth(1)
		tab.top:SetPoint("TOPLEFT")
		tab.top:SetPoint("TOPRIGHT")
		local hover = tab:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.06)
		-- (Bottoms on the panel's top, whatever their height.)
		tab:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 8 + (i - 1) * (TAB_W + TAB_GAP), 0)
		kit.Tooltip(tab, info[3])
		tab:SetScript("OnClick", function()
			tabNow = info[1]
			if onPick then onPick(tabNow) end
			kit.PageShown(kit.Refresh, content)()
		end)
		tab.Refresh = function(self) PaintTab(self, tabNow == info[1]) end
		tab.pageSwitch = false
		kit.AddControl(tab)
	end
	-- (A little room inside the panel's top.)
	local inside = CreateFrame("Frame", nil, content)
	inside:SetSize(1, 2)
	stack:Add(inside, "label")
	-- The panel down past the lowest thing shown under it and across the page.
	local function Layout()
		local top, left, right = panel:GetTop(), panel:GetLeft(), content:GetRight()
		if not (top and left and right) then return end
		local lowest = top
		local function Consider(object)
			if object ~= panel and object:IsShown() then
				local bottom = object:GetBottom()
				if bottom and bottom < lowest then lowest = bottom end
			end
		end
		for _, object in ipairs({ content:GetChildren() }) do Consider(object) end
		for _, object in ipairs({ content:GetRegions() }) do Consider(object) end
		panel:SetSize(math.max(right - left - 2, 100), top - lowest + PANEL_PAD + 2)
	end
	local owner, hiddenByTab = {}, {}
	local function Each(fn)
		for _, object in ipairs({ content:GetChildren() }) do fn(object) end
		for _, object in ipairs({ content:GetRegions() }) do fn(object) end
	end
	local parts = {}
	local starts = {}
	function parts.Part(tab, build, group)
		-- (Each tab's part of a group from where the group's first began.)
		group = group or 1
		local start = starts[group]
		if start then stack:Continue(start[1], start[2]) else starts[group] = { stack.last, stack.kind } end
		local before = {}
		Each(function(object) before[object] = true end)
		build()
		Each(function(object) if not before[object] then owner[object] = tab end end)
	end
	-- Shows the tab picked's parts and hides the rest: run last as the page
	-- refreshes, after any control's own showing and hiding.
	function parts.Finish()
		local apply = CreateFrame("Frame", nil, content)
		apply:SetSize(1, 1)
		apply:Hide()
		apply.pageSwitch = false
		apply.Refresh = function()
			Each(function(object)
				local tab = owner[object]
				if tab == tabNow then
					if hiddenByTab[object] then
						hiddenByTab[object] = nil
						object:Show()
					end
				elseif tab and object:IsShown() then
					hiddenByTab[object] = true
					object:Hide()
				end
			end)
			-- (Again next frame, once anchors have settled.)
			Layout()
			C_Timer.After(0, Layout)
		end
		kit.AddControl(apply)
	end
	return parts
end

-- The Visions hub's page: turning it on, and when it shows.
function ns.CreateCombatVisionPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Combat Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["A cue for a few seconds as you go into a fight and come out of it: a word on the screen or in a " ..
		"letterbox bar, a pulse round the screen's edges, an icon and a sound. How it looks: the Style hub's " ..
		"Combat Vision page."])
	ns.StyleLink(content, title, "Combat Style", L["Opens the Style hub's Combat Vision page: how the cue " ..
		"looks."], kit.Tooltip)
	local function Changed() end
	local switch = kit.PageSwitch(content, "combatVision", L["Enable page"],
		L["On: the cue shows as this page says. Off: never. Each setting keeps its value for when you turn " ..
		"this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "combatVision")
	local parts = PageTabs(kit, content, stack)
	local function Edge(key, name, tip)
		return { name, function() return ns.GetDB()[key] and true or false end,
			function() local db = ns.GetDB() db[key] = not db[key] end, nil, tip }
	end

	parts.Part("combat", function()
		stack:Header(content, L["When"])
		rows.Slider("combatMinFight", L["Not after fights under"], 0, 10, 1, "%d s", 1,
			L["No cue coming out of a fight shorter than this, so a stray hit doesn't bring it up. 0: after " ..
			"every fight."])

		-- Where and which: a Show in row as the Visual Effects page's, read as a
		-- fight starts and ends; its Combat dropdown is just those two (the
		-- usual fights and targets left out).
		local header = stack:Header(content, L["Show in"])
		local lastRow = ns.ShowTable(content, header, {
			underHeader = true,
			opts = { anyFight = true, omit = { combatShow = true, enemyShow = true, friendlyShow = true },
				combatItems = {
					Edge("combatOnEnter", L["Entering combat"], L["The cue as a fight starts."]),
					Edge("combatOnLeave", L["Leaving combat"], L["The cue as a fight ends."]),
				} },
			{ key = ROW_KEY, label = L["Combat Vision"], alwaysKey = "combatAlways",
				alwaysOn = function() return ns.GetDB().combatAlways end,
				setAlways = function(value) ns.GetDB().combatAlways = value end,
				alwaysTip = L["Shows wherever you are. (The other columns then have nothing to add.)"],
				recordKeys = { "combatOnEnter", "combatOnLeave" } },
		}, L["Combat Vision"])
		stack:Continue(lastRow, "label")

		ns.CombatSoundRulesSection(kit, content, stack) -- (CombatSoundRules.lua)
	end)

	-- Boss cards: a Show in row of its own, its Combat dropdown when the
	-- card shows (the places and roles where).
	parts.Part("boss", function()
		local bossHeader = stack:Header(content, L["Show in"])
		local bossRow = ns.ShowTable(content, bossHeader, {
			underHeader = true,
			opts = { anyFight = true, omit = { combatShow = true, enemyShow = true, friendlyShow = true },
				combatItems = {
					Edge("combatBossPull", L["Boss pulled"], L["The boss's name as its fight starts, in place of the " ..
						"cue's words. Once a run for each boss."]),
					Edge("combatBossTarget", L["Boss targeted"], L["The boss's name as you first target it, before " ..
						"the fight. A dungeon or raid boss is told by its level: a skull, or on retail two over yours."]),
					Edge("combatBossNear", L["Boss nearby"], L["The boss's name as you first come within about 28 " ..
						"yards of it, before the fight. A dungeon or raid boss is told by its level: a skull, or on " ..
						"retail two over yours."]),
				} },
			{ key = BOSS_KEY, label = L["Boss card"], alwaysKey = "combatBossAlways",
				alwaysOn = function() return ns.GetDB().combatBossAlways end,
				setAlways = function(value) ns.GetDB().combatBossAlways = value end,
				alwaysTip = L["Shows wherever you are. (The other columns then have nothing to add.)"],
				recordKeys = { "combatBossPull", "combatBossTarget", "combatBossNear" } },
		}, L["Boss card"])
		stack:Continue(bossRow, "label")
	end)
	parts.Finish()

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Combat Vision")
end

-- The look's settings a preset sets (the rest as the defaults; the colors
-- and words too).
local PRESET_KEYS = { "combatPlace", "combatBarScale", "combatAlign", "combatStyle", "combatFont", "combatSize",
	"combatAnim", "combatBarFallback",
	"combatOutline", "combatOutlineR", "combatOutlineG", "combatOutlineB",
	"combatHoldIn", "combatHoldOut", "combatPulseIn", "combatPulseOut", "combatIconShowIn", "combatIconShowOut",
	"combatTextIn", "combatTextOut", "combatInR", "combatInG", "combatInB", "combatOutR", "combatOutG", "combatOutB",
	"combatPulseInR", "combatPulseInG", "combatPulseInB", "combatPulseOutR", "combatPulseOutG", "combatPulseOutB" }

-- A row with an edit box for words (key: "" for none; the defaults shown
-- and kept as such in any language).
local function WordsRow(kit, content, stack, key, label, tip, test)
	local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
	name:SetSize(150, 22)
	local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	if ns.SkinEditBox then ns.SkinEditBox(box) end
	box:SetSize(100, 22) -- (narrow: the row also takes the color, icon, pulse and how long it stays)
	box:SetAutoFocus(false)
	box:SetMaxLetters(40)
	box:SetPoint("LEFT", name, "LEFT", 160, 0) -- (in line with the rows' choices)
	kit.Tooltip(box, tip)
	local function Save(self)
		local words = (self:GetText() or ""):match("^%s*(.-)%s*$")
		ns.GetDB()[key] = words == L[DEFAULTS[key]] and DEFAULTS[key] or words
		self:ClearFocus()
		if content.combatChanged then content.combatChanged() end
	end
	box:SetScript("OnEnterPressed", Save)
	box:SetScript("OnEditFocusLost", Save)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(ShownWords(ns.GetDB(), key))
		self:ClearFocus()
	end)
	box.Refresh = function(self)
		if not self:HasFocus() then self:SetText(ShownWords(ns.GetDB(), key)) end
	end
	kit.GreyUnless(box, test)
	kit.AddControl(box)
	return box
end

-- The preview: the screen's shape (or a height given), the scene behind,
-- the cue played on it: going in then coming out, or kind() "boss": the
-- Boss card (this page's, and the General page's screen).
function ns.MakeCombatPreview(parent, width, fixedH, kind)
	local preview = CreateFrame("Frame", nil, parent)
	preview:SetSize(width, fixedH or 270)
	if preview.SetClipsChildren then preview:SetClipsChildren(true) end
	local stage = CreateFrame("Frame", nil, preview)
	stage:SetAllPoints()
	stage:SetFrameLevel(preview:GetFrameLevel() + 2)
	local caption = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetText(L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	function preview:Refresh()
		if not self:IsVisible() then
			return -- (the kit refreshes every page's controls)
		end
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		local previewH = fixedH or math.floor(width * screenH / math.max(screenW, 1) + 0.5)
		self:SetHeight(previewH)
		ns.StyleScene(self)
		local look = ns.StyleLook("combatVision")
		local scale = previewH / math.max(screenH, 1)
		local wide = self:GetWidth() -- (the page's width: StylePopout)
		if kind and kind() == "boss" then
			Play(stage, BossLook(look), true, wide, previewH, scale, SampleBoss(look))
		else
			-- (Going in, then coming out.)
			Play(stage, look, true, wide, previewH, scale, nil, function()
				Play(stage, ns.StyleLook("combatVision"), false, wide, previewH, scale)
			end)
		end
	end
	return preview
end

-- The Style hub's page: how the cue looks, a preview at the top.
function ns.CreateCombatStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Combat Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the cue going into a fight and coming out of it looks. When it shows: the Visions hub's " ..
		"Combat Vision page. Changes play at once in the preview."])

	local preview, lastKind = nil, tabNow == "boss" and "boss" or "in"
	local function Replay(kind)
		if kind ~= nil then lastKind = kind end
		if preview then preview:Refresh() end
	end
	local function Changed() Replay() end
	content.combatChanged = Changed

	local switch = kit.PageSwitch(content, "combatVision", L["Enable page"],
		L["On: the cue shows as the Visions hub's Combat Vision page says, looking as this page says. Off: " ..
		"never. Each setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	-- The look's rows edit the cue's settings, or on the Boss card tab the
	-- card's own (BOSS_FIELDS).
	local fields = {}
	local function Field(key)
		if not BOSS_FIELDS[key] then return key end
		fields[key] = fields[key] or {
			get = function()
				local db = ns.GetDB()
				return db and db[tabNow == "boss" and BOSS_FIELDS[key] or key]
			end,
			set = function(value) ns.GetDB()[tabNow == "boss" and BOSS_FIELDS[key] or key] = value end,
		}
		return fields[key]
	end
	for key, bossKey in pairs(BOSS_FIELDS) do
		kit.RecordKey(content, key)
		kit.RecordKey(content, bossKey)
	end
	local rows = ns.StyleRows(kit, content, stack, Changed, "combatVision", Field)
	local Get = rows.Get

	-- The preview: the screen's shape, the scene behind, the cue played on it.
	preview = ns.MakeCombatPreview(content, 480, nil, function() return lastKind end)
	preview.pageSwitch = false
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)

	-- The tabs under the preview: what follows is the cue's or the Boss card's.
	local parts = PageTabs(kit, content, stack, function(tab) Replay(tab == "boss" and "boss" or "in") end)

	-- Test: the preview's cue again, and on your screen (going in, then coming
	-- out; or the Boss card).
	ns.StylePreviewTest(preview, kit, L["Plays the cue in the preview and on your screen, as it will look: " ..
		"going in, then coming out (on the Boss card tab, the card)."], function()
			preview:Refresh()
			if lastKind == "boss" then
				ns.PlayCombatVision(true, nil, SampleBoss(ns.StyleLook("combatVision")))
			else
				ns.PlayCombatVision(true, nil, nil, function() ns.PlayCombatVision(false) end)
			end
		end)

	parts.Part("combat", function()
		rows.PresetMenu({
			{ L["Film"], L["A serif title in the middle of the screen, the edges pulsing."],
				{ combatPlace = "screen", combatFont = "morpheus" } },
			{ L["Reel"], L["The word in the bottom letterbox bar, no pulse."],
				{ combatPlace = "bottom", combatPulseIn = 0, combatPulseOut = 0 } },
			{ L["Minimal"], L["A small subtitle low on the screen, nothing else."],
				{ combatPlace = "screen", combatStyle = "subtitle", combatFont = "friz", combatPulseIn = 0,
				combatPulseOut = 0, combatInR = 0.94, combatInG = 0.58, combatInB = 0.58, combatOutR = 0.83, combatOutG = 0.82,
				combatOutB = 0.78 } },
			{ L["Arcade"], L["Big, bold, an icon and a strong pulse."],
				{ combatPlace = "screen", combatFont = "skurri", combatSize = 46, combatOutline = 2,
				combatPulseIn = 0.9, combatPulseOut = 0.9, combatIconShowIn = true,
				combatIconShowOut = true, combatInR = 0.94, combatInG = 0.62, combatInB = 0.15,
				combatOutR = 0.59, combatOutG = 0.77, combatOutB = 0.35, combatPulseInR = 0.94, combatPulseInG = 0.62,
				combatPulseInB = 0.15, combatPulseOutR = 0.59, combatPulseOutG = 0.77, combatPulseOutB = 0.35 } },
			{ L["Quiet"], L["A chapter line in the top bar, on the right, a faint pulse."],
				{ combatPlace = "top", combatAlign = "right", combatStyle = "chapter", combatBarScale = 0.45,
				combatHoldIn = 2, combatHoldOut = 2 } },
		}, PRESET_KEYS)
	end, "presets")
	-- (The Boss card's own, its settings named as they're kept.)
	local bossKeys = {}
	for _, key in ipairs(PRESET_KEYS) do
		if BOSS_FIELDS[key] then bossKeys[#bossKeys + 1] = BOSS_FIELDS[key] end
	end
	parts.Part("boss", function()
		rows.PresetMenu({
			{ L["Lower third"], L["The name over a gold line low on the left, the dungeon under it, its letters " ..
				"closing up."], {} },
			{ L["Film"], L["The name over a gold line in the middle of the screen, the dungeon under it."],
				{ combatBossPlace = "screen", combatBossFont = "morpheus" } },
			{ L["Reel"], L["The name in the bottom letterbox bar, the dungeon beside it."],
				{ combatBossPlace = "bottom", combatBossStyle = "title" } },
			{ L["Epic"], L["A big bold name in the middle, a red pulse round the edges."],
				{ combatBossStyle = "title", combatBossFont = "skurri", combatBossSize = 58, combatBossOutline = 2,
				combatBossR = 0.94, combatBossG = 0.3, combatBossB = 0.2, combatBossPulse = 0.5,
				combatBossPulseR = 0.89, combatBossPulseG = 0.13, combatBossPulseB = 0.22, combatBossHold = 3 } },
			{ L["Quiet"], L["A chapter line in the top bar, on the right."],
				{ combatBossPlace = "top", combatBossAlign = "right", combatBossBarScale = 0.45 } },
		}, bossKeys)
	end, "presets")

	stack:Header(content, L["Where"])
	local function InBar(db)
		local place = Get("combatPlace")
		return db.combatVision and (place == "top" or place == "bottom")
	end
	-- (Dropdowns: one choice to read at a glance.)
	local function List(choices)
		return function()
			local list = {}
			for i, choice in ipairs(choices) do list[i] = { value = choice[1], text = choice[2], tip = choice[3] } end
			return list
		end
	end
	rows.Dropdown(L["Place:"], "combatPlace", List({
		{ "screen", L["On the screen"] },
		{ "top", L["Top letterbox bar"] },
		{ "bottom", L["Bottom letterbox bar"] },
		{ "third", L["Lower third"], L["Low on the left of the screen, as a film names someone, its line fading " ..
			"out to the right."] },
	}), L["Where the text shows: in the middle of the screen, in a letterbox bar or in the lower third."])
	rows.Dropdown(L["In the bar:"], "combatAlign", List({
		{ "left", L["Left"] },
		{ "center", L["Center"] },
		{ "right", L["Right"] },
	}), L["Where in the letterbox bar the text sits."], InBar)
	rows.Slider("combatBarScale", L["Letterbox scale"], 20, 100, 1, "%d%%", 100,
		L["The text's height next to the bar's: it grows and shrinks with your letterbox. (With no letterbox " ..
		"up, a bar as tall as your letterbox's comes in for the cue.)"], InBar)
	rows.Check("combatBarFallback", L["Lower third with no letterbox"],
		L["Ticked: while no letterbox is up, the text shows in the lower third. Unticked: a bar of its own " ..
		"comes in for it."], InBar)

	local On = rows.On

	stack:Header(content, L["Text"])
	local Words = On
	rows.Dropdown(L["Style:"], "combatStyle", List({
		{ "title", L["Title card"], L["A big word in the middle of the screen."] },
		{ "subtitle", L["Subtitle"], L["A small line low on the screen, where a film's subtitles go."] },
		{ "chapter", L["Chapter line"], L["The word over a line that draws out, as a new scene starts."] },
	}), L["How the text is set: a title card, a subtitle or a chapter line."])
	rows.Dropdown(L["Animation:"], "combatAnim", List({
		{ "fade", L["Fade"], L["The text fades in and out."] },
		{ "reveal", L["Reveal"], L["The text opens out from its middle (or from its side, in the lower third or " ..
			"at a bar's side), its line drawing out with it; a boss card's other lines rise in after the name."] },
		{ "track", L["Tracking in"], L["The letters start spread apart and close up, as a film's title comes in; " ..
			"a boss card's other lines rise in after the name. A boss's name that the game keeps secret (a card " ..
			"before the fight, on retail) opens as Reveal instead."] },
	}), L["How the text comes in."])
	local font = rows.Font("combatFont", L["Words in Russian, Korean or Chinese keep the game's font, so " ..
		"their letters show."], Words)
	-- (In line with the dropdowns above it: its name as wide as theirs.)
	local _, fontName
	if font then _, fontName = font:GetPoint(1) end
	if fontName and fontName.SetWidth then
		fontName:SetWidth(150)
		font:ClearAllPoints()
		font:SetPoint("LEFT", fontName, "RIGHT", 4, 0)
	end
	-- Size: a number box.
	local boxes = rows.Boxes()
	boxes:Box(L["Size"], Field("combatSize"), 14, 64, 1, "%d", 1,
		L["How tall the text is on the screen. (In a letterbox bar: Letterbox scale.)"],
		function(db) return Words(db) and not InBar(db) end)
	-- The outline: a dropdown (General first, named for what it gives), its
	-- color's swatch after it.
	local outline = rows.Outline("combatOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"] },
		L["A border round the letters."], Words)
	local outlineColor = rows.Swatch(outline or boxes, nil, { "combatOutlineR", "combatOutlineG", "combatOutlineB" },
		L["Pick the outline's color."], function(db)
			local value = Get("combatOutline")
			if value == -1 then value = ns.GeneralStyleValue("combatOutline") end
			return Words(db) and (value or 0) > 0
		end)
	-- (After the dropdown, not the words inside it.)
	if outline then
		outlineColor:ClearAllPoints()
		outlineColor:SetPoint("LEFT", outline, "RIGHT", 10, 0)
	end

	-- Going in and coming out: a row each, its words, color, icon (a tick
	-- for it at all, then a button opening every icon the game has:
	-- IconBrowser.lua) and pulse.
	local browser = ns.IconBrowser(canvas, function(key, icon)
		ns.GetDB()[key] = icon
		Changed()
		kit.Refresh()
	end)
	-- (A row's number boxes closer to what's before them, so a whole row fits.)
	local function Tight(line, after)
		line:SetPoint("LEFT", after.Text or after.text or after, "RIGHT", 12, 0)
		return line
	end
	-- A tick for the icon at all (showKey), then the icon's button.
	local function IconButton(after, showKey, iconKey, tip)
		local check = kit.Check(content, showKey, "", tip, function(value)
			ns.GetDB()[showKey] = value
			Changed()
			kit.Refresh()
		end)
		check:SetPoint("LEFT", after, "RIGHT", 10, 0)
		kit.GreyUnless(check, function(db) return db.combatVision end)
		local button = CreateFrame("Button", nil, content)
		button:SetSize(22, 22)
		button:SetPoint("LEFT", check, "RIGHT", 2, 0)
		local border = button:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.45, 0.38, 0.2, 1)
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", -2, 2)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local hl = button:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(icon)
		hl:SetColorTexture(1, 1, 1, 0.2)
		kit.Tooltip(button, L["The icon. Click to pick it from all the game's. Right-click: back to the usual one."])
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(self, mouse)
			local db = ns.GetDB()
			if mouse == "RightButton" then
				db[iconKey] = DEFAULTS[iconKey]
				Changed()
				kit.Refresh()
				return
			end
			browser:Open(self, iconKey, db[iconKey])
		end)
		button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		button:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		button.Refresh = function() icon:SetTexture(ns.GetDB()[iconKey] or DEFAULTS[iconKey]) end
		kit.GreyUnless(button, function(db) return db.combatVision and db[showKey] end)
		kit.AddControl(button)
		return button
	end
	local SIDES = {
		{ L["Going in:"], "In",
			L["The words going into a fight. Empty: none, just the rest of the cue."], L["Pick the text's color going in."],
			L["An icon before the word going in: crossed swords, unless you pick another."],
			L["The edges of the screen flash for a moment as a fight starts, this strongly. 0: no pulse."],
			L["Pick the pulse's color going in."],
			L["How long the cue going in stays between fading in and out."] },
		{ L["Coming out:"], "Out",
			L["The words coming out of it. Empty: none, just the rest of the cue."], L["Pick the text's color coming out."],
			L["An icon before the word coming out, unless you pick another."],
			L["The edges of the screen flash for a moment as a fight ends, this strongly. 0: no pulse."],
			L["Pick the pulse's color coming out."],
			L["How long the cue coming out stays between fading in and out."] },
	}
	parts.Part("combat", function()
		stack:Header(content, L["Going in and coming out"])
		for _, side in ipairs(SIDES) do
			local which = side[2]
			local box = WordsRow(kit, content, stack, "combatText" .. which, side[1], side[3], Words)
			local swatch = rows.Swatch(box, nil, { "combat" .. which .. "R", "combat" .. which .. "G",
				"combat" .. which .. "B" }, side[4])
			local icon = IconButton(swatch, "combatIconShow" .. which, "combatIcon" .. which, side[5])
			local pulse = Tight(rows.Boxes(icon), icon)
			pulse:Box(L["Pulse"], "combatPulse" .. which, 0, 100, 1, "%d", 100, side[6], On, "%")
			local pulseColor = rows.Swatch(pulse, nil, { "combatPulse" .. which .. "R", "combatPulse" .. which .. "G",
				"combatPulse" .. which .. "B" }, side[7], function(db) return On(db) and db["combatPulse" .. which] > 0 end)
			Tight(rows.Boxes(pulseColor), pulseColor):Box(L["Stays"], "combatHold" .. which, 0, 4, 0.1, "%.1f", 1, side[8], On, "s")
		end
	end, "sides")

	-- The Boss card's: the name's color, icon, pulse and how long it stays
	-- (no words: the boss's name), then its lines (when: the Visions hub's page).
	parts.Part("boss", function()
		stack:Header(content, L["Card"])
		local name = stack:Add(kit.Label(content, "GameFontHighlight", L["Name:"]), "label")
		name:SetSize(150, 22)
		local gap = CreateFrame("Frame", nil, content) -- (its swatch just after its name)
		gap:SetSize(1, 22)
		gap:SetPoint("LEFT", name, "LEFT", 150, 0)
		local swatch = rows.Swatch(gap, nil, { "combatBossR", "combatBossG", "combatBossB" },
			L["Pick the boss's name's color."])
		local icon = IconButton(swatch, "combatBossIconShow", "combatBossIcon",
			L["An icon before the boss's name: a skull, unless you pick another."])
		local pulse = Tight(rows.Boxes(icon), icon)
		pulse:Box(L["Pulse"], "combatBossPulse", 0, 100, 1, "%d", 100,
			L["The edges of the screen flash for a moment as the card shows, this strongly. 0: no pulse."], On, "%")
		local pulseColor = rows.Swatch(pulse, nil, { "combatBossPulseR", "combatBossPulseG", "combatBossPulseB" },
			L["Pick the pulse's color."], function(db) return On(db) and db.combatBossPulse > 0 end)
		Tight(rows.Boxes(pulseColor), pulseColor):Box(L["Stays"], "combatBossHold", 0.5, 8, 0.1, "%.1f", 1,
			L["How long a boss's card stays between fading in and out: longer than the usual cue, to read its lines."],
			On, "s")
		rows.Check("combatBossSub", L["Dungeon line"],
			L["The dungeon or raid and its difficulty under the boss's name (beside it in a letterbox bar)."])
		if EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex then
			rows.Check("combatBossCount", L["Boss number"],
				L["\"Boss 2 of 3\" over the name, from the Adventure Guide, as the fight starts (not in a letterbox bar)."])
		end
	end, "sides")
	parts.Finish()

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content)) -- (its refresh plays the preview)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Combat Style", L["Combat Vision"])
end
