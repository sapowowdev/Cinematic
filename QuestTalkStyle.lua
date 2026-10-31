-- Quest Vision's Quest talk tab: quest talk itself (its switch, questTalk:
-- off, the game's own gossip and quest windows) and how it looks (QuestTalk.lua
-- draws it): the panels behind the NPC's words, your replies and the quest's card
-- (parchment, the game's chat bubble, dark or none), their opacity, and the
-- words' font, size and outline. A preview at the top: a bubble and its
-- replies, dressed by quest talk's own code. Then its controls (the "Show
-- the game's window" link, the number keys). Where it sits (and where the
-- game's windows do, with it off): the Vision tab (Options.lua).

local _, ns = ...
local L = ns.L

-- The look's settings a preset sets (the rest as the defaults).
local PRESET_KEYS = { "questTalkStyle", "questTalkAlpha", "questTalkFont", "questTalkTextSize", "questTalkOutline",
	"questTalkCardSame" }

function ns.CreateQuestTalkStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Dialogue"])
	ns.QuestTabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["NPC dialogue, and how it looks: the panels behind the NPC's words, your replies and the quest's card, " ..
		"and the words themselves. Where it sits: the Vision tab. Changes show at once, " ..
		"here and on a conversation going on."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		if ns.RefreshQuestTalkStyle then ns.RefreshQuestTalkStyle() end
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "questTalkStyled", L["Enable Page"],
		L["On: the dialogue looks as this page says. Off: parchment, in the game's fonts (the preview shows " ..
		"that too). Each setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "questTalk")

	preview = ns.MakeQuestTalkPreview(content, 480)
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)

	rows.PresetMenu({
		{ L["Cinematic's"], L["Parchment, as the dialogue has always looked (the defaults)."], {} },
		{ L["Bubble"], L["The game's own chat bubble."], { questTalkStyle = "bubble" } },
		{ L["Dark"], L["Light words on dark, see-through panels, in Arial Narrow."],
			{ questTalkStyle = "dark", questTalkAlpha = 0.8, questTalkFont = "arial" } },
		{ L["Subtitles"], L["No panels: outlined words, like a film's subtitles."],
			{ questTalkStyle = "none", questTalkOutline = 1, questTalkTextSize = 1.1 } },
	}, PRESET_KEYS)

	stack:Header(content, L["Panels"])
	rows.Choices(L["Panels:"], "questTalkStyle", {
		{ "parchment", L["Parchment"], L["Like the quest window's page."] },
		{ "bubble", L["Chat bubble"], L["The game's own chat bubble."] },
		{ "dark", L["Dark"] },
		{ "none", L["None"], L["Just the words, over the world: an outline helps them read."] },
	})
	rows.Slider("questTalkAlpha", L["Opacity"], 20, 100, 5, "%d%%", 100, L["How see-through the panels are."],
		function(db) return db.questTalk and db.questTalkStyle ~= "none" end)
	rows.Check("questTalkCardSame", L["Quest card on the bubble's background"],
		L["The quest card and the list of replies have the bubble's look instead of their own dark one, " ..
		"their words in colors that suit it."])
	rows.Check("questTalkPortrait", L["The NPC's portrait"],
		L["Their portrait, round, on the bubble's top left corner, as on the game's quest window. Not " ..
		"for a quest from an item, with nobody to show."])

	stack:Header(content, L["Size"])
	rows.Slider("questTalkScale", L["Scale"], 70, 150, 5, "%d%%", 100,
		L["The size of the bubble and the list as a whole (their words grow with them)."])
	rows.Slider("questTalkLines", L["Bubble height"], 3, 15, 1, L["%d lines"], 1,
		L["How many lines of their words the bubble holds. It's always this tall, however little is on the " ..
		"page; more words go on the next page."])

	-- Where the quest card and the list sit (where the bubble does: the Quest
	-- Vision page's Where they go).
	stack:Header(content, L["Layout"])
	local SIDE_TIP = L["Where the quest card (the objective, rewards and buttons, or the list of replies) " ..
		"goes beside the bubble. Below: as wide as the bubble, which moves up to make room for it. Side: " ..
		"with Opposite clicked, on the bubble's outer side (away from the middle of the screen), else on " ..
		"the right. Right or Left: always that side. Beside it, it's as tall as the bubble."] .. " " ..
		L["Separate: the card stays where you drag it (or at the list's height), wherever the bubble goes."]
	-- (Default leaves the card where it is: under the bubble or the list's own spot.)
	local function SideOn(db) return db.questTalk and db.questTalkPlace ~= "fixed" end
	local side = kit.Dropdown(content, "questTalkCardSide", {
		{ value = "below", text = L["Below"] },
		{ value = "side", text = L["Side"] },
		{ value = "right", text = L["Right"] },
		{ value = "left", text = L["Left"] },
		{ value = "separate", text = L["Separate"] },
	}, 160, Changed)
	if side then
		local sideName = stack:Add(kit.Label(content, "GameFontHighlight", L["Quest card beside the bubble"]), "label")
		side:SetPoint("LEFT", sideName, "RIGHT", 10, 0)
		kit.GreyUnless(side, SideOn)
		kit.Tooltip(side, SIDE_TIP)
	else
		rows.Choices(L["Quest card beside the bubble"], "questTalkCardSide", {
			{ "below", L["Below"], SIDE_TIP }, { "side", L["Side"], SIDE_TIP },
			{ "right", L["Right"], SIDE_TIP }, { "left", L["Left"], SIDE_TIP },
			{ "separate", L["Separate"], SIDE_TIP },
		}, SideOn)
	end
	local listLine = stack:Add(kit.BoxLine(content), "label")
	local listY = listLine:Box(L["List height on the screen"], "questTalkListY", 20, 80, 1, "%d", 100,
		L["How far up the screen the list of replies starts: its top edge, from the bottom of the screen. " ..
		"Changing this also forgets where you dragged the list to."], function()
			ns.GetDB().questTalkSpot = nil -- (the box decides again)
			Changed()
		end, nil, "%")
	kit.GreyUnless(listY, rows.On)

	stack:Header(content, L["Words"])
	rows.Font("questTalkFont", L["The game's: each part in its own (the quest window's for the words). Russian, " ..
		"Korean or Chinese text keeps the game's, so its letters show."])
	rows.Slider("questTalkTextSize", L["Text size"], 70, 150, 5, "%d%%", 100,
		L["How big the words are, next to their usual size."])
	local OUTLINES = { [0] = L["None"], L["Thin"], L["Thick"] }
	rows.Outline("questTalkOutline", L["Outline"], 2, OUTLINES,
		L["A black border round the letters: for light words with no panel behind them."])

	-- Using it.
	stack:Header(content, L["Controls"])
	local function Control(key, label, tip)
		stack:Add(kit.Check(content, key, label, tip, function(value)
			ns.GetDB()[key] = value
			if ns.RefreshQuestTalk then ns.RefreshQuestTalk() end
			Changed()
		end), "check")
	end
	Control("questTalkGameButton", L["\"Show the game's window\" link"],
		L["A small link at the bottom of the quest card that brings back the game's own quest window for the " ..
		"rest of that conversation (for a long quest text, or to read it the usual way)."])
	Control("questTalkKeys", L["Number keys and Space"],
		L["1 to 9 and 0 pick from the list, as numbered. Space shows the next paragraph, and on the last " ..
		"one does the card's first button (Accept, Continue, Complete Quest). Only keys that do something " ..
		"there are held back from your action bars, and none in a fight."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Quest Talk Style", L["Dialogue"])
end
