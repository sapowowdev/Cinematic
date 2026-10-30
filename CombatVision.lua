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
DEFAULTS.combatHold = 0.5              -- seconds the text stays, between its fades
DEFAULTS.combatPulseIn = 0.03          -- the screen's edges flash, this strong (0: no)
DEFAULTS.combatPulseOut = 0.01
DEFAULTS.combatIconShowIn = false      -- an icon before the word going in
DEFAULTS.combatIconShowOut = false     -- ...and coming out
DEFAULTS.combatIconIn = "Interface\\Icons\\Ability_DualWield" -- (a file or file ID: IconBrowser.lua)
DEFAULTS.combatIconOut = 132320

-- Its Show in row (GridRows.lua: the places, roles and a rule, which can
-- name cinemode), read as a fight begins.
local ROW_KEY = "vision:combat"

local FADE_IN, FADE_OUT = 0.35, 0.5
local PULSE_PEAK, PULSE_GONE = 0.12, 0.9
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
	local text = over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.8)
	-- An outline in a color: the text again behind it, nudged each way (the
	-- game's own outline is always black).
	text.rim = {}
	for i = 1, 8 do
		text.rim[i] = over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		text.rim[i]:SetDrawLayer("OVERLAY", -1)
	end
	local line = over:CreateTexture(nil, "OVERLAY")
	local icon = over:CreateTexture(nil, "OVERLAY")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.cue = { bars = bars, pulse = pulse, over = over, text = text, line = line, icon = icon }
	bars:Hide()
	pulse:Hide()
	over:Hide()
	return frame.cue
end

local function FontFile(look)
	for _, font in ipairs(ns.QUEST_ITEM_FONTS or {}) do
		if font[1] == look.combatFont and font[3] then
			return font[3]
		end
	end
	return (GameFontNormalHuge:GetFont())
end

-- The words at key (combatTextIn, combatTextOut) as shown: the defaults in
-- the game's language.
local function ShownWords(look, key)
	local word = look[key] or DEFAULTS[key]
	return word == DEFAULTS[key] and L[word] or word
end

-- Sets up cue for a going in (enter) or coming out, on a screen width x
-- height; scale: that next to the real screen (the preview's smaller).
local function Setup(cue, look, enter, width, height, scale)
	local r, g, b, pr, pg, pb
	if enter then
		r, g, b = look.combatInR, look.combatInG, look.combatInB
		pr, pg, pb = look.combatPulseInR, look.combatPulseInG, look.combatPulseInB
	else
		r, g, b = look.combatOutR, look.combatOutG, look.combatOutB
		pr, pg, pb = look.combatPulseOutR, look.combatPulseOutG, look.combatPulseOutB
	end
	local word = ShownWords(look, enter and "combatTextIn" or "combatTextOut")
	local style, place = look.combatStyle, look.combatPlace
	if word == "" then style = "none" end
	local size = look.combatSize * scale
	if style == "subtitle" then
		size, word = math.max(size * 0.5, 11 * scale), "- " .. word .. " -"
	elseif style == "chapter" then
		size = size * 0.65
	end
	local text, line, icon = cue.text, cue.line, cue.icon
	text:ClearAllPoints()
	line:ClearAllPoints()
	icon:ClearAllPoints()
	cue.barSide, cue.lineWidth = nil, nil
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
		line:SetColorTexture(r, g, b, 0.8)
		line:SetHeight(math.max(1, scale))
		cue.lineWidth = cue.barSide and width * 0.6 or math.max(text:GetStringWidth() * 1.6, width * 0.3)
	end
	line:SetShown(style == "chapter")
	local showIcon = look[enter and "combatIconShowIn" or "combatIconShowOut"] and true or false
	icon:SetShown(showIcon)
	if showIcon then
		icon:SetTexture(enter and look.combatIconIn or look.combatIconOut)
		icon:SetSize(size * 1.1, size * 1.1)
		if style == "none" then
			icon:SetPoint(point, cue.over, relative, x, y)
		else
			icon:SetPoint("RIGHT", text, "LEFT", -size * 0.35, 0)
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

-- Draws cue age seconds in. Gives false once it's over (and hidden).
local function Draw(cue, age)
	local look = cue.look
	local hold = look.combatHold
	if age >= FADE_IN + hold + FADE_OUT then
		cue.bars:Hide()
		cue.pulse:Hide()
		cue.over:Hide()
		return false
	end
	local a
	if age < FADE_IN then
		a = age / FADE_IN
	elseif age > FADE_IN + hold then
		a = 1 - (age - FADE_IN - hold) / FADE_OUT
	else
		a = 1
	end
	a = a * a * (3 - 2 * a)
	cue.over:Show()
	cue.over:SetAlpha(a)
	if cue.lineWidth then cue.line:SetWidth(math.max(cue.lineWidth * a, 0.01)) end
	local pulse = 0
	local strength = cue.enter and look.combatPulseIn or look.combatPulseOut
	if strength > 0 then
		pulse = age < PULSE_PEAK and age / PULSE_PEAK or math.max(0, 1 - (age - PULSE_PEAK) / (PULSE_GONE - PULSE_PEAK))
	end
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

-- Plays cue on frame: its OnUpdate runs it to the end. look: ns.db.
local function Play(frame, look, enter, width, height, scale)
	local cue = frame.cue or MakeCue(frame)
	Setup(cue, look, enter, width, height, scale)
	local age = 0
	Draw(cue, 0)
	frame:SetScript("OnUpdate", function(self, elapsed)
		age = age + elapsed
		if not Draw(cue, age) then self:SetScript("OnUpdate", nil) end
	end)
end

-- The real cue, over the whole screen (kept when the UI is hidden: an overlay).
local screen
-- cine: CineMode as the fight began, for the sound rules (nil: as it is now).
function ns.PlayCombatVision(enter, cine)
	if not screen then
		screen = CreateFrame("Frame", "CinematicCombatVision", UIParent)
		screen:SetAllPoints(UIParent)
		screen:SetFrameStrata("LOW")
		screen:EnableMouse(false)
		ns.AddOverlay(screen)
	end
	Play(screen, ns.StyleLook("combatVision"), enter, UIParent:GetWidth(), UIParent:GetHeight(), 1)
	if cine == nil then cine = ns.lastCinematic and true or false end
	ns.PlayCombatCueSound(enter and "enter" or "leave", cine) -- (CombatSoundRules.lua)
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

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
	local db = ns.db
	if not db then
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		fightStart, cineAtStart = GetTime(), ns.lastCinematic and true or false
		if Allowed(db, "enter") then ns.PlayCombatVision(true, cineAtStart) end
	elseif GetTime() - fightStart >= db.combatMinFight and Allowed(db, "leave") then
		ns.PlayCombatVision(false, cineAtStart)
	end
end)

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

	stack:Header(content, L["When"])
	rows.Slider("combatMinFight", L["Not after fights under"], 0, 10, 1, "%d s", 1,
		L["No cue coming out of a fight shorter than this, so a stray hit doesn't bring it up. 0: after " ..
		"every fight."])

	-- Where and which: a Show in row as the Visual Effects page's, read as a
	-- fight starts and ends; its Combat dropdown is just those two (the
	-- usual fights and targets left out).
	local header = stack:Header(content, L["Show in"])
	local function Edge(key, name, tip)
		return { name, function() return ns.GetDB()[key] and true or false end,
			function() local db = ns.GetDB() db[key] = not db[key] end, nil, tip }
	end
	local lastRow = ns.ShowTable(content, header, {
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

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Combat Vision")
end

-- The look's settings a preset sets (the rest as the defaults; the colors
-- and words too).
local PRESET_KEYS = { "combatPlace", "combatBarScale", "combatAlign", "combatStyle", "combatFont", "combatSize",
	"combatOutline", "combatOutlineR", "combatOutlineG", "combatOutlineB",
	"combatHold", "combatPulseIn", "combatPulseOut", "combatIconShowIn", "combatIconShowOut", "combatTextIn",
	"combatTextOut", "combatInR", "combatInG", "combatInB", "combatOutR", "combatOutG", "combatOutB",
	"combatPulseInR", "combatPulseInG", "combatPulseInB", "combatPulseOutR", "combatPulseOutG", "combatPulseOutB" }

-- A row with an edit box for words (key: "" for none; the defaults shown
-- and kept as such in any language).
local function WordsRow(kit, content, stack, key, label, tip, test)
	local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
	name:SetSize(150, 22)
	local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	if ns.SkinEditBox then ns.SkinEditBox(box) end
	box:SetSize(150, 22)
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

-- The Style hub's page: how the cue looks, a preview at the top.
function ns.CreateCombatStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Combat Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the cue going into a fight and coming out of it looks. When it shows: the Visions hub's " ..
		"Combat Vision page. Changes play at once in the preview."])

	local preview, lastEnter = nil, true
	local function Replay(enter)
		if enter ~= nil then lastEnter = enter end
		if preview then preview:Refresh() end
	end
	local function Changed() Replay() end
	content.combatChanged = Changed

	local switch = kit.PageSwitch(content, "combatVision", L["Enable page"],
		L["On: the cue shows as the Visions hub's Combat Vision page says, looking as this page says. Off: " ..
		"never. Each setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "combatVision")

	-- The preview: the screen's shape, the scene behind, the cue played on it.
	local PREVIEW_W = 480
	local buttons = CreateFrame("Frame", nil, content)
	buttons:SetSize(PREVIEW_W, 24)
	stack:Add(buttons, "label")
	local last
	for _, enter in ipairs({ true, false }) do
		local button = ns.PanelButton(buttons)
		button:SetSize(110, 22)
		button:SetText(enter and L["Going in"] or L["Coming out"])
		if last then button:SetPoint("LEFT", last, "RIGHT", 8, 0) else button:SetPoint("LEFT") end
		kit.Tooltip(button, L["Plays the cue in the preview."])
		button:SetScript("OnClick", function() Replay(enter) end)
		button.Refresh = function() end
		button.pageSwitch = false
		kit.AddControl(button)
		last = button
	end
	-- (Scene beside them: StylePages.lua)
	ns.StyleSceneButton(content, kit.Tooltip, kit.AddControl):SetPoint("LEFT", last, "RIGHT", 8, 0)

	preview = CreateFrame("Frame", nil, content)
	preview:SetSize(PREVIEW_W, 270)
	if preview.SetClipsChildren then preview:SetClipsChildren(true) end
	local stage = CreateFrame("Frame", nil, preview)
	stage:SetAllPoints()
	stage:SetFrameLevel(preview:GetFrameLevel() + 2)
	local caption = kit.Label(preview, "GameFontDisableSmall", L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	function preview:Refresh()
		if not self:IsVisible() then
			return -- (the kit refreshes every page's controls)
		end
		local width, height = UIParent:GetWidth(), UIParent:GetHeight()
		local previewH = math.floor(PREVIEW_W * height / math.max(width, 1) + 0.5)
		self:SetHeight(previewH)
		ns.StyleScene(self)
		Play(stage, ns.StyleLook("combatVision"), lastEnter, PREVIEW_W, previewH, previewH / math.max(height, 1))
	end
	preview.pageSwitch = false
	stack:Add(preview, "label")
	kit.AddControl(preview)

	local tests = CreateFrame("Frame", nil, content)
	tests:SetSize(PREVIEW_W, 24)
	stack:Add(tests, "label")
	for i, enter in ipairs({ true, false }) do
		local test = ns.PanelButton(tests)
		test:SetSize(150, 22)
		test:SetPoint("LEFT", (i - 1) * 158, 0)
		test:SetText(enter and L["Test: into a fight"] or L["Test: out of it"])
		kit.Tooltip(test, L["Plays the cue on the screen as it will look."])
		test:SetScript("OnClick", function() ns.PlayCombatVision(enter) end)
		test.Refresh = function() end
		test.pageSwitch = false
		kit.AddControl(test)
	end

	rows.Presets({
		{ L["Film"], L["A serif title in the middle of the screen, the edges pulsing."],
			{ combatPlace = "screen", combatFont = "morpheus" } },
		{ L["Reel"], L["The word in the bottom letterbox bar, no pulse."],
			{ combatPlace = "bottom", combatPulseIn = 0, combatPulseOut = 0 } },
		{ L["Minimal"], L["A small subtitle low on the screen, nothing else."],
			{ combatPlace = "screen", combatStyle = "subtitle", combatFont = "friz", combatHold = 1, combatPulseIn = 0,
			combatPulseOut = 0, combatInR = 0.94, combatInG = 0.58, combatInB = 0.58, combatOutR = 0.83, combatOutG = 0.82,
			combatOutB = 0.78 } },
		{ L["Arcade"], L["Big, bold, an icon and a strong pulse."],
			{ combatPlace = "screen", combatFont = "skurri", combatSize = 46, combatOutline = 2, combatHold = 1,
			combatPulseIn = 0.9, combatPulseOut = 0.9, combatIconShowIn = true,
			combatIconShowOut = true, combatInR = 0.94, combatInG = 0.62, combatInB = 0.15,
			combatOutR = 0.59, combatOutG = 0.77, combatOutB = 0.35, combatPulseInR = 0.94, combatPulseInG = 0.62,
			combatPulseInB = 0.15, combatPulseOutR = 0.59, combatPulseOutG = 0.77, combatPulseOutB = 0.35 } },
		{ L["Quiet"], L["A chapter line in the top bar, on the right, a faint pulse."],
			{ combatPlace = "top", combatAlign = "right", combatStyle = "chapter", combatBarScale = 0.45,
			combatHold = 2 } },
	}, PRESET_KEYS, PREVIEW_W)

	stack:Header(content, L["Where"])
	local function InBar(db) return db.combatVision and db.combatPlace ~= "screen" end
	rows.Choices(L["Place:"], "combatPlace", {
		{ "screen", L["On the screen"] },
		{ "top", L["Top letterbox bar"] },
		{ "bottom", L["Bottom letterbox bar"] },
	})
	rows.Choices(L["In the bar:"], "combatAlign", {
		{ "left", L["Left"] },
		{ "center", L["Center"] },
		{ "right", L["Right"] },
	}, InBar)
	rows.Slider("combatBarScale", L["Letterbox scale"], 20, 100, 1, "%d%%", 100,
		L["The text's height next to the bar's: it grows and shrinks with your letterbox. (With no letterbox " ..
		"up, a bar as tall as your letterbox's comes in for the cue.)"], InBar)

	local On = rows.On

	stack:Header(content, L["Text"])
	local Words = On
	rows.Choices(L["Style:"], "combatStyle", {
		{ "title", L["Title card"], L["A big word in the middle of the screen."] },
		{ "subtitle", L["Subtitle"], L["A small line low on the screen, where a film's subtitles go."] },
		{ "chapter", L["Chapter line"], L["The word over a line that draws out, as a new scene starts."] },
	})
	rows.Font("combatFont", L["Words in Russian, Korean or Chinese keep the game's font, so their letters show."],
		Words)
	-- Size, outline (and its color) and how long it stays: number boxes on
	-- one row.
	local boxes = rows.Boxes()
	boxes:Box(L["Size"], "combatSize", 14, 64, 1, "%d", 1,
		L["How tall the text is on the screen. (In a letterbox bar: Letterbox scale.)"],
		function(db) return Words(db) and db.combatPlace == "screen" end)
	local OUTLINE_NAMES = { [0] = L["None"], L["Thin"], L["Thick"] }
	local function OutlineName(value)
		if value == -1 then
			return L["General"] .. " (" .. (OUTLINE_NAMES[ns.GeneralStyleValue("combatOutline")] or "") .. ")"
		end
		return OUTLINE_NAMES[value] or ""
	end
	-- (Its box as wide as its longest name.)
	local measure = content:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
	local widest = 0
	for value = -1, 2 do
		measure:SetText(value == -1 and L["General"] .. " (" .. L["Thick"] .. ")" or OutlineName(value))
		widest = math.max(widest, measure:GetStringWidth())
	end
	measure:Hide()
	local outlineBox = boxes:Box(L["Outline"], "combatOutline", -1, 2, 1, OutlineName, 1,
		L["A border round the letters."], Words, nil, math.ceil(widest) + 14)
	outlineBox:SetMaxLetters(30) -- (its name in full: the boxes take 6)
	local outlineColor = rows.Swatch(boxes, nil, { "combatOutlineR", "combatOutlineG", "combatOutlineB" },
		L["Pick the outline's color."], function(db)
			local outline = db.combatOutline == -1 and ns.GeneralStyleValue("combatOutline") or db.combatOutline
			return Words(db) and (outline or 0) > 0
		end)
	rows.Boxes(outlineColor):Box(L["Stays for"], "combatHold", 0, 4, 0.1, "%.1f", 1,
		L["How long the cue stays between fading in and out."], On, "s")

	-- Going in and coming out: a row each, its words, color, icon (a tick
	-- for it at all, then a button opening every icon the game has:
	-- IconBrowser.lua) and pulse.
	stack:Header(content, L["Going in and coming out"])
	local browser = ns.IconBrowser(canvas, function(key, icon)
		ns.GetDB()[key] = icon
		Changed()
		kit.Refresh()
	end)
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
			L["Pick the pulse's color going in."] },
		{ L["Coming out:"], "Out",
			L["The words coming out of it. Empty: none, just the rest of the cue."], L["Pick the text's color coming out."],
			L["An icon before the word coming out, unless you pick another."],
			L["The edges of the screen flash for a moment as a fight ends, this strongly. 0: no pulse."],
			L["Pick the pulse's color coming out."] },
	}
	for _, side in ipairs(SIDES) do
		local which = side[2]
		local box = WordsRow(kit, content, stack, "combatText" .. which, side[1], side[3], Words)
		local swatch = rows.Swatch(box, nil, { "combat" .. which .. "R", "combat" .. which .. "G",
			"combat" .. which .. "B" }, side[4])
		local icon = IconButton(swatch, "combatIconShow" .. which, "combatIcon" .. which, side[5])
		local pulse = rows.Boxes(icon)
		pulse:Box(L["Pulse"], "combatPulse" .. which, 0, 100, 1, "%d", 100, side[6], On, "%")
		rows.Swatch(pulse, nil, { "combatPulse" .. which .. "R", "combatPulse" .. which .. "G",
			"combatPulse" .. which .. "B" }, side[7], function(db) return On(db) and db["combatPulse" .. which] > 0 end)
	end

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content)) -- (its refresh plays the preview)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Combat Style", L["Combat Vision"])
end
