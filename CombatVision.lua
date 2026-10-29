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
DEFAULTS.combatPlace = "screen"        -- "screen", "top" or "bottom" (a letterbox bar)
DEFAULTS.combatWiden = true            -- in a bar: the bar grows to fit the text
DEFAULTS.combatAlign = "center"        -- in a bar: "left", "center" or "right"
DEFAULTS.combatStyle = "title"         -- "title", "subtitle", "chapter" or "none"
DEFAULTS.combatTextIn = ""             -- the words ("": Combat, Respite)
DEFAULTS.combatTextOut = ""
DEFAULTS.combatFont = "morpheus"       -- QUEST_ITEM_FONTS (QuestItemButton.lua)
DEFAULTS.combatSize = 34               -- the text's height on the screen
DEFAULTS.combatOutline = 1             -- 0 none, 1 thin, 2 thick
DEFAULTS.combatInR, DEFAULTS.combatInG, DEFAULTS.combatInB = 0.89, 0.29, 0.29
DEFAULTS.combatOutR, DEFAULTS.combatOutG, DEFAULTS.combatOutB = 0.62, 0.88, 0.8
DEFAULTS.combatHold = 1.5              -- seconds the text stays, between its fades
DEFAULTS.combatPulse = true            -- the screen's edges flash in the text's color
DEFAULTS.combatPulseStrength = 0.1
DEFAULTS.combatIcon = false            -- an icon before the word
DEFAULTS.combatIconIn = "Interface\\Icons\\Ability_DualWield" -- (a file or file ID: IconBrowser.lua)
DEFAULTS.combatIconOut = "Interface\\Icons\\Ability_Warrior_DefensiveStance"

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

-- Sets up cue for a going in (enter) or coming out, on a screen width x
-- height; scale: that next to the real screen (the preview's smaller).
local function Setup(cue, look, enter, width, height, scale)
	local r, g, b
	if enter then
		r, g, b = look.combatInR, look.combatInG, look.combatInB
	else
		r, g, b = look.combatOutR, look.combatOutG, look.combatOutB
	end
	local word = enter and look.combatTextIn or look.combatTextOut
	if not word or word == "" then word = enter and L["Combat"] or L["Respite"] end
	local style, place = look.combatStyle, look.combatPlace
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
		-- In a bar of our own: as tall as the text needs (Widen), or as the
		-- letterbox's own bars are now, the text sized to fit it.
		local real = 0
		if ns.letterbox and ns.letterbox:IsShown() and scale == 1 then real = ns.letterbox.top:GetHeight() end
		local want = look.combatWiden and math.max(real, size * 1.8) or (real > size * 0.8 and real or size * 1.5)
		size = math.min(size, want * 0.62)
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
	ns.SetPlateNameFont(text, GameFontNormalHuge, FontFile(look), math.floor(size + 0.5), 1,
		OUTLINES[look.combatOutline] or "")
	text:SetTextColor(r, g, b, 1)
	text:SetVertexColor(r, g, b, 1) -- (one and the same on Forever)
	text:SetShown(style ~= "none")
	if style == "chapter" then
		line:SetColorTexture(r, g, b, 0.8)
		line:SetHeight(math.max(1, scale))
		cue.lineWidth = cue.barSide and width * 0.6 or math.max(text:GetStringWidth() * 1.6, width * 0.3)
	end
	line:SetShown(style == "chapter")
	icon:SetShown(look.combatIcon and true or false)
	if look.combatIcon then
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
			side == "TOP" or side == "LEFT", r, g, b)
	end
	cue.look, cue.width, cue.height, cue.scale = look, width, height, scale
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
	if look.combatPulse then
		pulse = age < PULSE_PEAK and age / PULSE_PEAK or math.max(0, 1 - (age - PULSE_PEAK) / (PULSE_GONE - PULSE_PEAK))
	end
	cue.pulse:SetShown(pulse > 0)
	cue.pulse:SetAlpha(pulse * look.combatPulseStrength)
	cue.bars:SetShown(cue.barSide ~= nil)
	if cue.barSide then
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
	Play(screen, ns.db, enter, UIParent:GetWidth(), UIParent:GetHeight(), 1)
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
	local function Changed() end
	local switch = kit.PageSwitch(content, "combatVision", L["Enable page"],
		L["On: the cue shows as this page says. Off: never. Each setting keeps its value for when you turn " ..
		"this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "combatVision")

	local tests = CreateFrame("Frame", nil, content)
	tests:SetSize(320, 24)
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

	stack:Header(content, L["When"])
	rows.Slider("combatMinFight", L["Not after fights under"], 0, 10, 1, "%d s", 1,
		L["No cue coming out of a fight shorter than this, so a stray hit doesn't bring it up. 0: after " ..
		"every fight."])

	-- Where and which: a Show in row as the Visual Effects page's, read as a
	-- fight starts and ends; its Combat dropdown is just those two (the
	-- usual fights and targets left out).
	stack:Header(content, L["Show in"])
	local note = stack:Add(kit.Label(content, "GameFontHighlightSmall",
		L["When and where the cue shows. Combat: entering combat, leaving it, or both. Always: everywhere. " ..
		"Location: the places. Role: only as those roles. Edit: a rule, with Entering combat and Leaving " ..
		"combat under Combat, and In CineMode under You for only the fights that begin in CineMode."]), "label")
	note:SetWidth(460)
	note:SetJustifyH("LEFT")
	local function Edge(key, name, tip)
		return { name, function() return ns.GetDB()[key] and true or false end,
			function() local db = ns.GetDB() db[key] = not db[key] end, nil, tip }
	end
	local lastRow = ns.ShowTable(content, note, {
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
local PRESET_KEYS = { "combatPlace", "combatWiden", "combatAlign", "combatStyle", "combatFont", "combatSize",
	"combatOutline", "combatHold", "combatPulse", "combatPulseStrength", "combatIcon", "combatTextIn",
	"combatTextOut", "combatInR", "combatInG", "combatInB", "combatOutR", "combatOutG", "combatOutB" }

-- A row with an edit box for words (key: "" for the usual ones).
local function WordsRow(kit, content, stack, key, label, tip, test)
	local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
	name:SetSize(150, 22)
	local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	if ns.SkinEditBox then ns.SkinEditBox(box) end
	box:SetSize(200, 22)
	box:SetAutoFocus(false)
	box:SetMaxLetters(40)
	box:SetPoint("LEFT", name, "RIGHT", 8, 0)
	kit.Tooltip(box, tip)
	local function Save(self)
		ns.GetDB()[key] = (self:GetText() or ""):match("^%s*(.-)%s*$")
		self:ClearFocus()
		if content.combatChanged then content.combatChanged() end
	end
	box:SetScript("OnEnterPressed", Save)
	box:SetScript("OnEditFocusLost", Save)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.GetDB()[key] or "")
		self:ClearFocus()
	end)
	box.Refresh = function(self)
		if not self:HasFocus() then self:SetText(ns.GetDB()[key] or "") end
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
		Play(stage, ns.GetDB(), lastEnter, PREVIEW_W, previewH, previewH / math.max(height, 1))
	end
	preview.pageSwitch = false
	stack:Add(preview, "label")
	kit.AddControl(preview)

	rows.Presets({
		{ L["Film"], L["A serif title in the middle of the screen, the edges pulsing (the defaults)."], {} },
		{ L["Reel"], L["The word in the bottom bar, the bar growing in to hold it."],
			{ combatPlace = "bottom", combatSize = 26, combatPulse = false } },
		{ L["Minimal"], L["A small subtitle low on the screen, nothing else."],
			{ combatStyle = "subtitle", combatFont = "friz", combatHold = 1, combatPulse = false,
			combatInR = 0.94, combatInG = 0.58, combatInB = 0.58, combatOutR = 0.83, combatOutG = 0.82, combatOutB = 0.78 } },
		{ L["Arcade"], L["Big, bold, an icon and a strong pulse."],
			{ combatFont = "skurri", combatSize = 46, combatOutline = 2, combatHold = 1, combatPulseStrength = 0.9,
			combatIcon = true, combatInR = 0.94, combatInG = 0.62, combatInB = 0.15,
			combatOutR = 0.59, combatOutG = 0.77, combatOutB = 0.35 } },
		{ L["Quiet"], L["A chapter line in the top bar, on the right, a faint pulse."],
			{ combatPlace = "top", combatWiden = false, combatAlign = "right", combatStyle = "chapter",
			combatSize = 26, combatHold = 2 } },
	}, PRESET_KEYS, PREVIEW_W)

	stack:Header(content, L["Where"])
	local function InBar(db) return db.combatVision and db.combatPlace ~= "screen" end
	rows.Choices(L["Place:"], "combatPlace", {
		{ "screen", L["On the screen"] },
		{ "top", L["Top letterbox bar"] },
		{ "bottom", L["Bottom letterbox bar"] },
	})
	rows.Check("combatWiden", L["Widen the bar to fit"],
		L["The bar grows as the cue comes in, tall enough for the text, then goes back. Unticked: the text " ..
		"is sized to fit the bar as it is. With no bars up, a bar comes in for the cue either way."], InBar)
	rows.Choices(L["In the bar:"], "combatAlign", {
		{ "left", L["Left"] },
		{ "center", L["Center"] },
		{ "right", L["Right"] },
	}, InBar)

	stack:Header(content, L["Text"])
	local function Words(db) return db.combatVision and db.combatStyle ~= "none" end
	rows.Choices(L["Style:"], "combatStyle", {
		{ "title", L["Title card"], L["A big word in the middle of the screen."] },
		{ "subtitle", L["Subtitle"], L["A small line low on the screen, where a film's subtitles go."] },
		{ "chapter", L["Chapter line"], L["The word over a line that draws out, as a new scene starts."] },
		{ "none", L["No text"] },
	})
	WordsRow(kit, content, stack, "combatTextIn", L["Going in:"],
		L["The words going into a fight. Empty: Combat."], Words)
	WordsRow(kit, content, stack, "combatTextOut", L["Coming out:"],
		L["The words coming out of it. Empty: Respite."], Words)
	local font = kit.Dropdown(content, "combatFont", function()
		local list = {}
		for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do list[#list + 1] = { value = info[1], text = info[2] } end
		return list
	end, 200, Changed)
	if font then
		local fontName = stack:Add(kit.Label(content, "GameFontHighlight", L["Font:"]), "label")
		font:SetPoint("LEFT", fontName, "RIGHT", 10, 0)
		kit.GreyUnless(font, Words)
		kit.Tooltip(font, L["Words in Russian, Korean or Chinese keep the game's font, so their letters show."])
	end
	rows.Slider("combatSize", L["Size"], 14, 64, 2, "%d", 1, L["How tall the text is."], Words)
	local OUTLINE_NAMES = { [0] = L["None"], L["Thin"], L["Thick"] }
	rows.Slider("combatOutline", L["Outline"], 0, 2, 1, function(value) return OUTLINE_NAMES[value] or "" end, 1,
		L["A black border round the letters."], Words)
	rows.Color(L["Going in"], { "combatInR", "combatInG", "combatInB" }, L["Pick the color going in."])
	rows.Color(L["Coming out"], { "combatOutR", "combatOutG", "combatOutB" }, L["Pick the color coming out."])
	rows.Slider("combatHold", L["Stays for"], 5, 40, 5, function(value) return ("%.1f s"):format(value / 10) end,
		10, L["How long the cue stays between fading in and out."])

	stack:Header(content, L["Screen"])
	rows.Check("combatPulse", L["Pulse the screen's edges"],
		L["The edges of the screen flash in the cue's color for a moment."])
	rows.Slider("combatPulseStrength", L["Pulse strength"], 10, 100, 5, "%d%%", 100, nil,
		function(db) return db.combatVision and db.combatPulse end)
	rows.Check("combatIcon", L["An icon"],
		L["An icon before the word: crossed swords going in and a shield coming out, unless you pick others."])
	-- Its icons: a button each showing the one now, a click opening every
	-- icon the game has (IconBrowser.lua).
	local function Icons(db) return db.combatVision and db.combatIcon end
	local browser = ns.IconBrowser(canvas, function(key, icon)
		ns.GetDB()[key] = icon
		Changed()
		kit.Refresh()
	end)
	for _, which in ipairs({ { "combatIconIn", L["Going in"] }, { "combatIconOut", L["Coming out"] } }) do
		local name = stack:Add(kit.Label(content, "GameFontHighlight", which[2]), "label")
		name:SetSize(150, 30)
		local button = CreateFrame("Button", nil, content)
		button:SetSize(28, 28)
		button:SetPoint("LEFT", name, "RIGHT", 4, 0)
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
		kit.Tooltip(button, L["Click to pick the icon from all the game's. Right-click: back to the usual one."])
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(self, mouse)
			local db = ns.GetDB()
			if mouse == "RightButton" then
				db[which[1]] = DEFAULTS[which[1]]
				Changed()
				kit.Refresh()
				return
			end
			browser:Open(self, which[1], db[which[1]])
		end)
		button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		button:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		button.Refresh = function() icon:SetTexture(ns.GetDB()[which[1]] or DEFAULTS[which[1]]) end
		kit.GreyUnless(button, Icons)
		kit.AddControl(button)
	end

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content)) -- (its refresh plays the preview)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Combat Style", L["Combat Vision"])
end
