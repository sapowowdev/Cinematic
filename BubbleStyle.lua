-- The Style hub's Chat bubbles page: how chat bubbles look (Bubbles.lua draws
-- them), and speech from behind you with them (Speech.lua): the back behind
-- the words (the game's bubble, dark, a color of your own or none), its
-- opacity, edge and tail, and the words' font, size and outline. A preview
-- at the top. Where bubbles show: the UI Manager's Chat bubbles page.

local _, ns = ...
local L = ns.L

-- The look's settings a preset sets (the rest as the defaults).
local PRESET_KEYS = { "bubblesBack", "bubblesAlpha", "bubblesEdge", "bubblesTail", "bubblesFont",
	"bubblesTextScale", "bubblesOutline" }

function ns.CreateBubbleStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Chat bubbles"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How chat bubbles look, and speech from behind you with them. Where bubbles show: the UI " ..
		"Manager's Chat bubbles page. Bubbles already showing change with the next thing said."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		if ns.RefreshBubbleStyle then ns.RefreshBubbleStyle() end
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "bubblesStyle", L["Enable page"],
		L["On: chat bubbles look as this page says. Off: the game's own bubbles (the preview shows that " ..
		"too). Each setting keeps its value for when you turn this back on. (Not in instances on retail: " ..
		"the game doesn't let addons change bubbles there.)"], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "bubblesStyle")

	stack:Add(ns.StyleSceneButton(content, kit.Tooltip, kit.AddControl), "label")
	preview = ns.MakeBubblePreview(content, 480)
	stack:Add(preview, "label")
	kit.AddControl(preview)

	rows.Presets({
		{ L["Like the game's"], L["The game's own bubbles (the defaults)."], {} },
		{ L["Dark"], L["Light words on a dark, see-through bubble with a thin edge, in Arial Narrow."],
			{ bubblesBack = "dark", bubblesAlpha = 0.8, bubblesFont = "arial" } },
		{ L["Text only"], L["No bubble: just the words, outlined, like a film's subtitles."],
			{ bubblesBack = "none", bubblesOutline = 2, bubblesTextScale = 1.1 } },
		{ L["Big words"], L["The game's bubbles, with bigger words."], { bubblesTextScale = 1.3 } },
	}, PRESET_KEYS, 480)

	local function Boxed(db) return db.bubblesStyle and db.bubblesBack ~= "none" end
	local function Own(db) return db.bubblesStyle and (db.bubblesBack == "dark" or db.bubblesBack == "custom") end

	stack:Header(content, L["Bubble"])
	local last = rows.Choices(L["Behind the words:"], "bubblesBack", {
		{ "game", L["The game's"], L["The game's own bubble."] },
		{ "dark", L["Dark"], L["A flat dark bubble."] },
		{ "custom", L["Custom"], L["A flat bubble in a color of your own (the swatch)."] },
		{ "none", L["None"], L["Just the words, over the world: an outline helps them read."] },
	})
	rows.Swatch(last, "bubblesBack", { "bubblesBackR", "bubblesBackG", "bubblesBackB" },
		L["The bubble's color, for Custom."])
	rows.Slider("bubblesAlpha", L["Opacity"], 20, 100, 5, "%d%%", 100, L["How see-through the bubble is."], Boxed)
	rows.Choices(L["Edge:"], "bubblesEdge", {
		{ "thin", L["Thin"], L["A thin line round the bubble."] },
		{ "none", L["None"] },
	}, Own)
	rows.Check("bubblesTail", L["The tail pointing at who's talking"],
		L["The little point under the bubble. Unticked, just the bubble."], Boxed)

	stack:Header(content, L["Words"])
	local font = kit.Dropdown(content, "bubblesFont", function()
		local list = {}
		for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do list[#list + 1] = { value = info[1], text = info[2] } end
		return list
	end, 200, Changed)
	if font then
		local fontName = stack:Add(kit.Label(content, "GameFontHighlight", L["Font:"]), "label")
		font:SetPoint("LEFT", fontName, "RIGHT", 10, 0) -- (just after the word: a lone dropdown, no column to line up with)
		kit.GreyUnless(font, rows.On)
		kit.Tooltip(font, L["The words' font. Russian, Korean or Chinese text keeps the game's, so its letters show."])
	end
	rows.Slider("bubblesTextScale", L["Text size"], 50, 200, 5, "%d%%", 100,
		L["How big the words are, next to their usual size."])
	local OUTLINES = { [0] = L["None"], L["Thin"], L["Thick"], L["Thick + shadow"] }
	rows.Slider("bubblesOutline", L["Outline"], 0, 3, 1, function(value) return OUTLINES[value] or "" end, 1,
		L["A black border round the letters, so they stand out against the world. Thick + shadow also drops " ..
		"a shadow below and to the right of them."])

	-- Speech from behind you's own look (Speech.lua): turned on, moved and
	-- shown with chat up on the UI Manager's Chat bubbles page; greyed out
	-- while it's off there.
	stack:Header(content, L["Speech from behind you"])
	stack:Help(content, L["Says and yells whose bubble isn't on your screen, shown low on the screen instead. " ..
		"Turn it on, and move it, on the UI Manager's Chat bubbles page."])
	local function Behind(db)
		return db.bubblesStyle and db.chatPeek and db.chatHideBubbled and db.chatSpeechBehind
	end
	local speechName = rows.Check("speechBehindName", L["Show who said it"],
		L["Speech from behind you starts with the speaker's name (\"Name says: ...\"). Unticked, just their words show."],
		Behind)
	-- (On the same line as Show who said it.)
	local speechClass = kit.Check(content, "speechBehindClassColor", L["In class color"],
		L["Players' names show in their class color, as in the chat window. NPCs' don't have one."], function(value)
			ns.GetDB().speechBehindClassColor = value
			Changed()
		end)
	speechClass:SetPoint("LEFT", speechName.Text or speechName.text, "RIGHT", 16, 0)
	kit.GreyUnless(speechClass, function(db) return Behind(db) and db.speechBehindName end)
	rows.Check("speechBehindRise", L["Rise up from below the screen"],
		L["Each line slides up from below the bottom of the screen, as if from behind the camera, " ..
		"instead of just fading in."], Behind)
	rows.Slider("speechBehindScale", L["Size"], 50, 100, 5, "%d%%", 100,
		L["How big speech from behind you is, next to a bubble overhead: smaller sounds further away."], Behind)
	rows.Slider("speechBehindAlpha", L["Opacity"], 30, 100, 5, "%d%%", 100,
		L["How solid speech from behind you is: fainter sounds muffled, out of view."], Behind)
	rows.Check("speechBehindTailTop", L["Tail on top"],
		L["The bubble's tail sits on top, pointing up, instead of under it pointing down. (In a bubble only: " ..
		"not with no bubble behind the words.)"], function(db) return Behind(db) and db.bubblesBack ~= "none" end)
	-- How wide a line gets before it wraps, and which way the lines line up.
	rows.Slider("speechBehindWidth", L["Max width"], 200, 1000, 20, "%d", nil,
		L["How wide a line of speech from behind you can get. A longer one wraps into rows of about the same length."],
		Behind)
	local align = kit.Dropdown(content, "speechBehindAlign", {
		{ value = "auto", text = L["By where it's moved to"] },
		{ value = "LEFT", text = L["Left"] },
		{ value = "CENTER", text = L["Center"] },
		{ value = "RIGHT", text = L["Right"] },
	}, 200, Changed)
	if align then
		local alignName = stack:Add(kit.Label(content, "GameFontHighlight", L["Align:"]), "label")
		align:SetPoint("LEFT", alignName, "RIGHT", 10, 0)
		kit.GreyUnless(align, Behind)
		kit.Tooltip(align, L["Which way the lines line up: their left edges, their middles or their right " ..
			"edges. By where it's moved to: by which side of the screen the Move box is on."])
	end

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Bubble Style", L["Chat bubbles"])
end
