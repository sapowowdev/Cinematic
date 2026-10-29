-- The Style hub's Letterbox page: how the letterbox bars look and come in
-- (Effects.lua draws them, by ns.LetterboxLook). Their height by a share of
-- the screen or by a film's frame, color, opacity, a feathered inner edge, a
-- line along it, and sliding or fading in, over the UI's fade or a time of
-- their own. A preview at the top, drawn by the same code as the real bars.
-- When they show at all: the Visual Effects page's Show in grid.

local ADDON_NAME, ns = ...
local L = ns.L

-- The preview's backdrop: a lake at dusk, 2:1 (Media/make_letterbox_scene.py).
local SCENE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\LetterboxScene"

-- The look's settings a preset sets (the rest as the defaults; the custom
-- colors are kept, for a pick of Custom later).
local PRESET_KEYS = { "letterboxSizeBy", "letterboxSize", "letterboxAspect", "letterboxColor", "letterboxAlpha",
	"letterboxEdge", "letterboxFeather", "letterboxLine", "letterboxMotion", "letterboxTime" }

function ns.CreateLetterboxStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Letterbox"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the bars at the top and bottom of the screen look and come in. When they show: the Visual " ..
		"Effects page's Show in grid. Changes show at once, here and on the bars."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		ns.RefreshLetterbox()
		if preview then preview:Refresh() end
	end
	local function On(db) return db.letterboxStyle end

	local switch = kit.PageSwitch(content, "letterboxStyle", L["Enable page"],
		L["On: the bars look as this page says. Off: Cinematic's own, thin black bars sliding in with the " ..
		"UI's fade (the preview shows that too). Each setting keeps its value for when you turn this back on."],
		intro, Changed)
	local stack = kit.Stack(switch, "check")

	-- The preview: a little screen with a lake at dusk, the bars over it as
	-- the real ones are drawn, the screen's own shape. Bars in / Bars out
	-- brings them in and out as at a fight's end and start.
	local PREVIEW_W = 480
	preview = CreateFrame("Frame", nil, content)
	preview:SetSize(PREVIEW_W, 270)
	if preview.SetClipsChildren then preview:SetClipsChildren(true) end
	local scene = preview:CreateTexture(nil, "BACKGROUND")
	scene:SetAllPoints()
	scene:SetTexture(SCENE)
	local caption = kit.Label(preview, "GameFontDisableSmall", L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	local bars = CreateFrame("Frame", nil, preview)
	bars:SetAllPoints()
	bars:SetFrameLevel(preview:GetFrameLevel() + 2)
	ns.MakeLetterboxBars(bars)
	-- (caption above the bars)
	local over = CreateFrame("Frame", nil, preview)
	over:SetAllPoints()
	over:SetFrameLevel(bars:GetFrameLevel() + 1)
	caption:SetParent(over)

	local progress, target = 1, 1
	local function Draw()
		-- (The screen's shape, which can change with the resolution.)
		local width, height = UIParent:GetWidth(), UIParent:GetHeight()
		local previewH = math.floor(PREVIEW_W * height / math.max(width, 1) + 0.5)
		preview:SetHeight(previewH)
		-- (The scene is 2:1: cut to the screen's shape, from its middle.)
		local cut = math.max(0, 1 - PREVIEW_W / math.max(previewH, 1) / 2) / 2
		scene:SetTexCoord(cut, 1 - cut, 0, 1)
		local t = progress * progress * (3 - 2 * progress)
		ns.DrawLetterbox(bars, ns.LetterboxLook(), PREVIEW_W, previewH, t, previewH / math.max(height, 1))
		bars:SetShown(progress > 0)
	end
	function preview:Refresh()
		Draw()
	end
	preview:SetScript("OnUpdate", function(_, elapsed)
		if progress ~= target then
			progress = ns.Approach(progress, target, elapsed, ns.LetterboxTime(ns.LetterboxLook(), target > progress))
			Draw()
		end
	end)
	kit.AddControl(preview)

	local inOut = ns.PanelButton(content)
	inOut:SetSize(110, 22)
	-- (above the preview)
	stack:Add(inOut, "label")
	stack:Add(preview, "label")
	local function InOutText() inOut:SetText(target == 1 and L["Bars out"] or L["Bars in"]) end
	InOutText()
	kit.Tooltip(inOut, L["Brings the bars in or out, as at a fight's end and start."])
	inOut:SetScript("OnClick", function()
		target = 1 - target
		InOutText()
	end)
	inOut.Refresh = function() end
	kit.AddControl(inOut)

	-- Presets: a few looks to start from.
	local PRESETS = {
		{ L["Cinematic's"], L["Thin black bars that slide in with the UI's fade (the defaults)."], {} },
		{ L["Film"], L["A 2.39:1 frame, as at the cinema."],
			{ letterboxSizeBy = "aspect", letterboxAspect = 2.39, letterboxTime = 1 } },
		{ L["Soft"], L["Feathered edges that melt into the scene, fading in."],
			{ letterboxSize = 0.09, letterboxEdge = "soft", letterboxFeather = 40, letterboxAlpha = 0.9,
			letterboxMotion = "fade", letterboxTime = 1.2 } },
		{ L["Gilded"], L["Thin bars with a thin gold line along their edge."],
			{ letterboxSize = 0.06, letterboxLine = "gold" } },
	}
	local presetRow = CreateFrame("Frame", nil, content)
	presetRow:SetSize(PREVIEW_W, 24)
	stack:Add(presetRow, "label")
	local lastButton
	for _, preset in ipairs(PRESETS) do
		local button = ns.PanelButton(presetRow)
		button:SetText(preset[1])
		button:SetSize(math.max(110, button:GetFontString():GetStringWidth() + 24), 22)
		if lastButton then
			button:SetPoint("LEFT", lastButton, "RIGHT", 8, 0)
		else
			button:SetPoint("LEFT", presetRow, "LEFT", 0, 0)
		end
		kit.Tooltip(button, preset[2])
		button:SetScript("OnClick", function()
			local db = ns.GetDB()
			db.letterboxStyle = true
			for _, key in ipairs(PRESET_KEYS) do
				local value = preset[3][key]
				if value == nil then value = ns.DEFAULTS[key] end
				db[key] = value
			end
			Changed()
			kit.Refresh()
		end)
		button.Refresh = function() end
		kit.GreyUnless(button, On)
		kit.AddControl(button)
		lastButton = button
	end

	-- A row of choices for key, after its name: { value, text, tip } each.
	-- Gives the last, to put a color swatch after.
	local function Choices(label, key, list, test)
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetWidth(150)
		local last
		for _, info in ipairs(list) do
			local choice = kit.Choice(content, key, info[1], info[2], info[3])
			choice:HookScript("OnClick", Changed)
			if last then
				choice:SetPoint("LEFT", last.Text or last.text, "RIGHT", 16, 0)
			else
				choice:SetPoint("LEFT", name, "RIGHT", 4, 0)
			end
			kit.GreyUnless(choice, test or On)
			last = choice
		end
		return last
	end

	-- A color's swatch after a row of choices: its R, G and B settings (keys);
	-- a pick puts key on Custom.
	local function Swatch(after, key, keys, tip)
		local swatch = CreateFrame("Button", nil, content)
		swatch:SetSize(18, 18)
		swatch:SetPoint("LEFT", after.Text or after.text, "RIGHT", 10, 0)
		local border = swatch:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.6, 0.6, 0.6, 1)
		local color = swatch:CreateTexture(nil, "ARTWORK")
		color:SetPoint("TOPLEFT", 2, -2)
		color:SetPoint("BOTTOMRIGHT", -2, 2)
		kit.Tooltip(swatch, tip)
		swatch:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		swatch:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		swatch.Refresh = function()
			local db = ns.GetDB()
			color:SetColorTexture(db[keys[1]], db[keys[2]], db[keys[3]], 1)
		end
		swatch:SetScript("OnClick", function()
			local db = ns.GetDB()
			kit.OpenColorPicker(db[keys[1]], db[keys[2]], db[keys[3]], function(r, g, b)
				db[keys[1]], db[keys[2]], db[keys[3]] = r, g, b
				db[key] = "custom"
				Changed()
				kit.Refresh()
			end)
		end)
		kit.GreyUnless(swatch, On)
		kit.AddControl(swatch)
		return swatch
	end

	local function StyleSlider(key, label, minV, maxV, step, fmt, scale, tip, test)
		local slider = stack:Add(kit.Slider(content, key, label, minV, maxV, step, fmt, scale, Changed), "slider")
		if tip then kit.Tooltip(slider, tip) end
		kit.GreyUnless(slider, test or On)
		return slider
	end

	stack:Header(content, L["Size"])
	Choices(L["Set by:"], "letterboxSizeBy", {
		{ "height", L["Height"], L["Each bar a share of the screen's height."] },
		{ "aspect", L["A film's frame"], L["The bars as tall as it takes for what's left between them to have a " ..
			"film's shape, whatever your screen."] },
	})
	StyleSlider("letterboxSize", L["Bar height"], 0, 25, 1, "%d%%", 100,
		L["How tall each bar is, as a share of the screen's height."],
		function(db) return db.letterboxStyle and db.letterboxSizeBy ~= "aspect" end)
	Choices(L["Frame:"], "letterboxAspect", {
		{ 2.39, L["2.39:1 (cinema)"] },
		{ 2, L["2:1"] },
		{ 1.85, L["1.85:1"] },
	}, function(db) return db.letterboxStyle and db.letterboxSizeBy == "aspect" end)

	stack:Header(content, L["Look"])
	Swatch(Choices(L["Color:"], "letterboxColor", {
		{ "black", L["Black"] },
		{ "custom", L["Custom"] },
	}), "letterboxColor", { "letterboxR", "letterboxG", "letterboxB" }, L["Pick the bars' color."])
	StyleSlider("letterboxAlpha", L["Opacity"], 10, 100, 5, "%d%%", 100,
		L["How see-through the bars are."])
	Choices(L["Inner edge:"], "letterboxEdge", {
		{ "hard", L["Hard"] },
		{ "soft", L["Soft (feathered)"], L["The bars fade into the scene past their edge."] },
	})
	StyleSlider("letterboxFeather", L["Feather"], 5, 80, 5, "%d", 1,
		L["How far past the bars' edge they fade into the scene."],
		function(db) return db.letterboxStyle and db.letterboxEdge == "soft" end)
	Swatch(Choices(L["Line along the edge:"], "letterboxLine", {
		{ "none", L["None"] },
		{ "gold", L["Gold"] },
		{ "custom", L["Custom"] },
	}), "letterboxLine", { "letterboxLineR", "letterboxLineG", "letterboxLineB" }, L["Pick the line's color."])

	stack:Header(content, L["Coming in and going"])
	Choices(L["How:"], "letterboxMotion", {
		{ "slide", L["Slide in"], L["The bars grow in from the screen's edges."] },
		{ "fade", L["Fade in"], L["The bars fade in at their full height."] },
	})
	StyleSlider("letterboxTime", L["How long"], 0, 30, 1, function(value)
		return value == 0 and L["With the UI"] or ("%.1f s"):format(value / 10)
	end, 10, L["How long the bars take to come in or go. 0: as long as the UI's own fades (the main page's " ..
		"Fade in and Fade out times)."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Letterbox Style", L["Letterbox"])
end
