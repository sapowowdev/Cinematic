-- The Style hub's Roll Vision page: how the window of the group's loot rolls
-- looks (RollWindow.lua draws it): its cards, their text, the bar for the
-- time left, each player's pick and number, and the winner's row. A preview
-- at the top, two cards drawn by the window's own code (ns.MakeRollPreview);
-- Show a test roll brings up the real window too, with made-up drops. Turning
-- it on: the Visions hub's Roll Vision page.

local _, ns = ...
local L = ns.L

-- The look's settings a preset sets (the rest as the defaults; the custom
-- colors are kept, for a pick of Custom later).
local PRESET_KEYS = { "rollPanel", "rollAlpha", "rollDensity", "rollFont", "rollTextSize", "rollOutline",
	"rollBarTexture", "rollBarColor", "rollBarHeight", "rollPicks", "rollNumbers", "rollWinner", "rollWinnerColor" }

function ns.CreateRollStylePanel(kit)
	if not ns.hasRollWindow then -- (no loot history on this client: no window to style)
		return
	end
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Roll Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the window of the group's loot rolls looks: its cards, the bar for the time left, and each " ..
		"player's pick and number. Turning it on: the Visions hub's Roll Vision page. Changes show at once, " ..
		"here and on the window."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		if ns.RefreshRollStyle then ns.RefreshRollStyle() end
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "rollStyle", L["Enable page"],
		L["On: the window looks as this page says. Off: as Roll Vision has always looked. Each setting " ..
		"keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "rollStyle")

	-- The real window, with made-up drops (the Roll Vision page's test).
	local test = ns.PanelButton(content)
	test:SetSize(150, 22)
	test:SetText(L["Show a test roll"])
	stack:Add(test, "label")
	kit.Tooltip(test, L["Brings up the window with three made-up drops, your group picking and rolling on " ..
		"them over a few seconds. Change things here while it's up to see them."])
	test:SetScript("OnClick", function() ns.TestRollWindow() end)
	test.Refresh = function(self) self:SetEnabled(ns.GetDB().rollWindow and true or false) end
	test.pageSwitch = false -- (works with the page off too: to see the look it goes back to)
	kit.AddControl(test)

	-- (under the test button: a won drop and one being picked on)
	preview = ns.MakeRollPreview(content, 480)
	-- (Scene beside it: StylePages.lua)
	ns.StyleSceneButton(content, kit.Tooltip, kit.AddControl):SetPoint("LEFT", test, "RIGHT", 8, 0)
	stack:Add(preview, "label")
	kit.AddControl(preview)

	rows.Presets({
		{ L["Cinematic's"], L["As Roll Vision has always looked (the defaults)."], {} },
		{ L["Compact"], L["Tighter rows and smaller text, for raids."],
			{ rollDensity = "compact", rollTextSize = 0.9, rollFont = "arial", rollOutline = 1 } },
		{ L["Bare"], L["No panels behind the cards: outlined text over the world, the winner just crowned."],
			{ rollPanel = "none", rollOutline = 1, rollWinner = "crown", rollPicks = "words" } },
		{ L["Gilded"], L["Flat cards, gold timers and the winner's row in gold."],
			{ rollPanel = "flat", rollBarColor = "gold", rollBarTexture = "smooth" } },
	}, PRESET_KEYS, 480)

	stack:Header(content, L["Cards"])
	rows.Choices(L["Cards on:"], "rollPanel", {
		{ "rounded", L["The game's frame"], L["A dark panel in the rounded edge of the game's roll frames, in the item's quality color."] },
		{ "flat", L["Flat"], L["A dark panel with a thin line round it, in the item's quality color."] },
		{ "none", L["Nothing"], L["Just the text, over the world."] },
	})
	rows.Slider("rollAlpha", L["Opacity"], 20, 100, 5, "%d%%", 100, L["How see-through the cards are."],
		function(db) return db.rollStyle and db.rollPanel ~= "none" end)
	rows.Choices(L["Rows:"], "rollDensity", {
		{ "roomy", L["Roomy"] },
		{ "compact", L["Compact"] },
	})

	stack:Header(content, L["Text"])
	local font = kit.Dropdown(content, "rollFont", function()
		local list = {}
		for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do list[#list + 1] = { value = info[1], text = info[2] } end
		return list
	end, 200, Changed)
	if font then
		local fontName = stack:Add(kit.Label(content, "GameFontHighlight", L["Font:"]), "label")
		fontName:SetWidth(150)
		font:SetPoint("LEFT", fontName, "RIGHT", 4, 0)
		kit.GreyUnless(font, rows.On)
		kit.Tooltip(font, L["Names in Russian, Korean or Chinese keep the game's font, so their letters show."])
	end
	rows.Slider("rollTextSize", L["Size"], 70, 140, 5, "%d%%", 100, L["How big the text is, next to its usual size."])
	local OUTLINES = { [0] = L["None"], L["Thin"], L["Thick"] }
	rows.Slider("rollOutline", L["Outline"], 0, 2, 1, function(value) return OUTLINES[value] or "" end, 1,
		L["A black border round the letters: easier to read with no panel behind them."])

	stack:Header(content, L["Time left"])
	rows.Choices(L["Bar texture:"], "rollBarTexture", {
		{ "flat", L["Flat"] },
		{ "smooth", L["Smooth"], L["The game's status bar texture."] },
	})
	rows.Swatch(rows.Choices(L["Bar color:"], "rollBarColor", {
		{ "quality", L["The item's quality"] },
		{ "gold", L["Gold"] },
		{ "custom", L["Custom"] },
	}), "rollBarColor", { "rollBarR", "rollBarG", "rollBarB" }, L["Pick the bar's color."])
	rows.Slider("rollBarHeight", L["Bar height"], 2, 10, 1, "%d", 1, L["How tall the bar for the time left is."])

	stack:Header(content, L["Picks"])
	local function Words(db) return db.rollStyle and db.rollPicks == "words" end
	rows.Choices(L["Shown as:"], "rollPicks", {
		{ "icons", L["Icons"], L["The game's dice and coin before each name."] },
		{ "words", L["Words"], L["Need, Greed or Transmog after each name, in their colors."] },
	})
	rows.Color(L["Need"], { "rollNeedR", "rollNeedG", "rollNeedB" }, L["Pick Need's color."], Words)
	rows.Color(L["Greed"], { "rollGreedR", "rollGreedG", "rollGreedB" }, L["Pick Greed's color."], Words)
	rows.Color(L["Transmog"], { "rollTransmogR", "rollTransmogG", "rollTransmogB" },
		L["Pick Transmog's color."], Words)
	rows.Check("rollNumbers", L["Their numbers, once the rolls are shown"],
		L["Each player's number at the end of their row once the game reveals the rolls. Unticked: just " ..
		"who won."])

	stack:Header(content, L["Winner"])
	local function Marked(db) return db.rollStyle and db.rollWinner ~= "plain" end
	rows.Choices(L["Winner's row:"], "rollWinner", {
		{ "lit", L["Lit"], L["A glow along the row, a crown and the number in its color."] },
		{ "crown", L["A crown"], L["A crown and the number in its color."] },
		{ "plain", L["Just at the top"] },
	})
	rows.Swatch(rows.Choices(L["Winner color:"], "rollWinnerColor", {
		{ "gold", L["Gold"] },
		{ "custom", L["Custom"] },
	}, Marked), "rollWinnerColor", { "rollWinnerR", "rollWinnerG", "rollWinnerB" }, L["Pick the winner's color."],
		Marked)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Roll Style", L["Roll Vision"])
end
