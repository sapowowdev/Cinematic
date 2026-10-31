-- Roll Vision's Style tab: how the window of the group's loot rolls
-- looks (RollWindow.lua draws it): its cards, their text, the bar for the
-- time left, each player's pick and number, and the winner's row. A preview
-- at the top, two cards drawn by the window's own code (ns.MakeRollPreview);
-- Show a test roll brings up the real window too, with made-up drops. Turning
-- it on: the Vision tab (Options.lua). Both in the Visions hub under one icon.

local _, ns = ...
local L = ns.L

-- The look's settings a preset sets (the rest as the defaults; the custom
-- colors are kept, for a pick of Custom later).
local PRESET_KEYS = { "rollPanel", "rollAlpha", "rollDensity", "rollFont", "rollTextSize", "rollOutline",
	"rollBarTexture", "rollBarColor", "rollBarHeight", "rollPicks", "rollNumbers", "rollWinner", "rollWinnerColor" }

-- The two pages' tabs (picked: 1 Vision, 2 Style).
function ns.RollTabs(content, title, picked)
	ns.VisionTabs(content, title, "Roll Vision", "Roll Style", picked,
		L["Turning it on, and which rolls it shows."], L["How the roll window looks."])
end

function ns.CreateRollStylePanel(kit)
	if not ns.hasRollWindow then -- (no loot history on this client: no window to style)
		return
	end
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Roll Vision"])
	ns.RollTabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["How the window of the group's loot rolls looks: its cards, the bar for the time left, and each " ..
		"player's pick and number. Turning it on: the Vision tab. Changes show at once, " ..
		"here and on the window."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		if ns.RefreshRollStyle then ns.RefreshRollStyle() end
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "rollStyle", L["Enable Page"],
		L["On: the window looks as this page says. Off: as Roll Vision has always looked. Each setting " ..
		"keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "rollStyle")

	-- (a won drop and one being picked on)
	preview = ns.MakeRollPreview(content, 480)
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)

	-- The real window, with made-up drops (the Roll Vision page's test). (Works
	-- with the page off too: to see the look it goes back to.)
	local test = ns.StylePreviewTest(preview, kit, L["Brings up the window with three made-up drops, your " ..
		"group picking and rolling on them over a few seconds. Change things here while it's up to see them."],
		function() ns.TestRollWindow() end)
	test.Refresh = function(self) self:SetEnabled(ns.GetDB().rollWindow and true or false) end

	rows.PresetMenu({
		{ L["Cinematic's"], L["As Roll Vision has always looked (the defaults)."], {} },
		{ L["Compact"], L["Tighter rows and smaller text, for raids."],
			{ rollDensity = "compact", rollTextSize = 0.9, rollFont = "arial", rollOutline = 1 } },
		{ L["Bare"], L["No panels behind the cards: outlined text over the world, the winner just crowned."],
			{ rollPanel = "none", rollOutline = 1, rollWinner = "crown", rollPicks = "words" } },
		{ L["Gilded"], L["Flat cards, gold timers and the winner's row in gold."],
			{ rollPanel = "flat", rollBarColor = "gold", rollBarTexture = "smooth" } },
	}, PRESET_KEYS)

	stack:Header(content, L["Cards"])
	rows.Choices(L["Cards on:"], "rollPanel", {
		{ "rounded", L["The game's frame"], L["A dark panel in the rounded edge of the game's roll frames, in the item's quality color."] },
		{ "flat", L["Flat"], L["A dark panel with a thin line round it, in the item's quality color."] },
		{ "none", L["Nothing"], L["Just the text, over the world."] },
	})
	rows.Slider("rollAlpha", L["Opacity"], 20, 100, 5, "%d%%", 100, L["How see-through the cards are."],
		function(db) return rows.On(db) and db.rollPanel ~= "none" end)
	rows.Choices(L["Rows:"], "rollDensity", {
		{ "roomy", L["Roomy"] },
		{ "compact", L["Compact"] },
	})

	stack:Header(content, L["Text"])
	rows.Font("rollFont", L["Names in Russian, Korean or Chinese keep the game's font, so their letters show."])
	rows.Slider("rollTextSize", L["Size"], 70, 140, 5, "%d%%", 100, L["How big the text is, next to its usual size."])
	local OUTLINES = { [0] = L["None"], L["Thin"], L["Thick"] }
	rows.Outline("rollOutline", L["Outline"], 2, OUTLINES,
		L["A black border round the letters: easier to read with no panel behind them."])

	stack:Header(content, L["Time left"])
	rows.Texture(L["Bar texture:"], "rollBarTexture", L["The bar's fill. Below the game's own few: any other " ..
		"addon shares (through LibSharedMedia)."], nil, { 1, 0.82, 0 }, L["Flat"])
	rows.Swatch(rows.Choices(L["Bar color:"], "rollBarColor", {
		{ "quality", L["The item's quality"] },
		{ "gold", L["Gold"] },
		{ "custom", L["Custom"] },
	}), "rollBarColor", { "rollBarR", "rollBarG", "rollBarB" }, L["Pick the bar's color."])
	rows.Slider("rollBarHeight", L["Bar height"], 2, 10, 1, "%d", 1, L["How tall the bar for the time left is."])

	stack:Header(content, L["Picks"])
	local function Words(db) return rows.On(db) and db.rollPicks == "words" end
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
	local function Marked(db) return rows.On(db) and db.rollWinner ~= "plain" end
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
