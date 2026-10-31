-- Quest Vision's Quest Item Button tab: how the big button for the nearest
-- quest's item looks (QuestItemButton.lua draws it, by ns.QuestItemLook):
-- size, shape, its frame, the icon zoomed in, a glow while it's ready, its
-- cooldown as the game's sweep or a draining fill with the seconds left, and
-- its numbers' font. A preview at the top: the button ready, and cooling down,
-- drawn by the same code as the real one. Turning it on: the Vision tab
-- (Options.lua).

local _, ns = ...
local L = ns.L

-- The look's settings a preset sets (the rest as the defaults; the custom
-- glow color is kept, for a pick of Custom later).
local PRESET_KEYS = { "questItemSize", "questItemShape", "questItemFrame", "questItemZoom", "questItemGlow",
	"questItemGlowColor", "questItemCooldown", "questItemNumbers", "questItemKey", "questItemFont",
	"questItemOutline" }
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_Bag_07"
local SAMPLE_COOLDOWN = 8 -- seconds the cooling sample counts down, over and over

-- The preview: the button ready, and cooling down (again and again), over
-- the Style pages' scene, with your item's icon if a quest has one (this
-- page's, and the General page's screen).
function ns.MakeQuestItemPreview(parent, width)
	local preview = CreateFrame("Frame", nil, parent)
	preview:SetSize(width, 170)
	ns.StyleScene(preview, 0.6) -- (StylePages.lua)
	local caption = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetText(L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	local samples, names = {}, {}
	for i, label in ipairs({ L["Ready"], L["Cooling down"] }) do
		local frame = CreateFrame("Frame", nil, preview)
		frame.parts = ns.MakeQuestItemParts(frame)
		frame.parts.count:SetText("3")
		local name = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetText(label)
		name.searchSkip = true
		samples[i], names[i] = frame, name
	end
	-- (A third of the way in from each side, however wide the page makes it.)
	local function Place(_, w)
		for i, frame in ipairs(samples) do
			local x = w * (i == 1 and 0.32 or 0.68)
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", preview, "LEFT", x, 8)
			names[i]:ClearAllPoints()
			names[i]:SetPoint("BOTTOM", preview, "BOTTOMLEFT", x, 10)
		end
	end
	Place(nil, width)
	preview:HookScript("OnSizeChanged", Place)
	local cooling = samples[2]
	local function Icon()
		local items = ns.QuestLogItems and ns.QuestLogItems() or {}
		local first = items[1]
		return first and (first.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(first.itemID)))
			or SAMPLE_ICON
	end
	function preview:Refresh()
		local look = ns.QuestItemLook()
		local key = GetBindingKey("CLICK CinematicQuestItemButton:LeftButton")
		local keyText = key and GetBindingText and GetBindingText(key, true) or key or "E"
		local icon = Icon()
		for _, frame in ipairs(samples) do
			frame:SetSize(look.questItemSize, look.questItemSize)
			frame.parts.icon:SetTexture(icon)
			frame.parts.hotkey:SetText(keyText)
			ns.StyleQuestItem(frame.parts, look, look.questItemSize)
		end
		if not cooling.parts.start then
			ns.QuestItemCooldown(cooling.parts, GetTime(), SAMPLE_COOLDOWN)
		end
	end
	-- (The cooling one starts again a moment after it's done.)
	local readyAt
	preview:SetScript("OnUpdate", function()
		if cooling.parts.start then
			readyAt = nil
		elseif not readyAt then
			readyAt = GetTime()
		elseif GetTime() - readyAt > 1.5 then
			ns.QuestItemCooldown(cooling.parts, GetTime(), SAMPLE_COOLDOWN)
		end
	end)
	return preview
end

function ns.CreateQuestItemStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Quest Item Button"])
	ns.QuestTabs(content, title, 3)
	local intro = kit.PageIntro(content, title,
		L["How the big button for the nearest quest's item looks. Turning it on: the Vision tab. " ..
		"Where it sits: the extra ability button's place in Edit Mode. Changes show at once (its size " ..
		"after a fight, if you're in one)."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		ns.RefreshQuestItemStyle()
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "questItemStyle", L["Enable Page"],
		L["On: the button looks as this page says. Off: like the game's extra ability button (the preview " ..
		"shows that too). Each setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "questItemStyle")

	preview = ns.MakeQuestItemPreview(content, 480)
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)

	-- Presets: a few looks to start from.
	rows.PresetMenu({
		{ L["Like the game's"], L["Framed like the game's extra ability button (the defaults)."], {} },
		{ L["Flat"], L["A thin black edge, the icon zoomed in to cut its border, an edge glow when ready, " ..
			"Arial Narrow."], { questItemFrame = "thin", questItemZoom = true, questItemFont = "arial",
			questItemGlow = "edge" } },
		{ L["Round"], L["A round button with a soft glow when ready."],
			{ questItemShape = "round", questItemFrame = "thin", questItemZoom = true, questItemGlow = "soft" } },
		{ L["Cinematic"], L["Smaller, no frame, a quiet edge glow and a dark cooldown fill, no key."],
			{ questItemSize = 42, questItemFrame = "none", questItemZoom = true, questItemGlow = "edge",
			questItemCooldown = "fill", questItemKey = false } },
	}, PRESET_KEYS)

	stack:Header(content, L["Button"])
	rows.Slider("questItemSize", L["Size"], 32, 80, 2, "%d", 1, L["The button's width and height."])
	rows.Choices(L["Shape:"], "questItemShape", {
		{ "square", L["Square"] },
		{ "round", L["Round"] },
	})
	rows.Border(L["Frame:"], "questItemFrame", { game = true }, L["Round the button: the game's (the extra " ..
		"ability button's frame), or one of ours (Custom: its thickness and color under it)."])
	rows.Check("questItemZoom", L["Zoom the icon in to cut its own border"],
		L["Icons have a dark border of their own: zoomed in a little, it's cut off."])

	stack:Header(content, L["When it's ready"])
	local function Glowing(db) return rows.On(db) and db.questItemGlow ~= "none" end
	rows.Choices(L["Glow:"], "questItemGlow", {
		{ "none", L["None"] },
		{ "soft", L["Soft"], L["A soft halo round it."] },
		{ "edge", L["An edge"], L["A ring of color round it."] },
	})
	rows.Swatch(rows.Choices(L["Color:"], "questItemGlowColor", {
		{ "gold", L["Gold"] },
		{ "custom", L["Custom"] },
	}, Glowing), "questItemGlowColor", { "questItemGlowR", "questItemGlowG", "questItemGlowB" },
		L["Pick the glow's color."])
	stack:Note(content, L["Ready: it's up (you're near the quest's area) and not cooling down."], 460)

	stack:Header(content, L["Cooldown"])
	rows.Choices(L["Shown as:"], "questItemCooldown", {
		{ "sweep", L["The game's sweep"] },
		{ "fill", L["Dark fill, draining"], L["A dark fill over the icon, going down as the cooldown runs out."] },
	})
	rows.Check("questItemNumbers", L["Seconds left in the middle"],
		L["The seconds left in the middle of the button while it cools down."])

	stack:Header(content, L["Text"])
	rows.Check("questItemKey", L["Its key binding in the corner"],
		L["The key you've bound to it (Key Bindings, Cinematic: Use the quest item), in its top corner."])
	rows.Font("questItemFont", nil)
	local OUTLINES = { [0] = L["None"], L["Thin"], L["Thick"] }
	rows.Outline("questItemOutline", L["Outline"], 2, OUTLINES,
		L["A black border round its numbers."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Quest Item Style", L["Quest Item Button"])
end
