-- The Style hub's Letterbox page: how the letterbox bars look and come in
-- (Effects.lua draws them, by ns.LetterboxLook). Their height by a share of
-- the screen or by a film's frame, color, opacity, a feathered inner edge, a
-- line along it, and sliding or fading in, over the UI's fade or a time of
-- their own. A preview at the top, drawn by the same code as the real bars.
-- When they show at all: the Visual Effects page's Show in grid.

local _, ns = ...
local L = ns.L

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

	local switch = kit.PageSwitch(content, "letterboxStyle", L["Enable page"],
		L["On: the bars look as this page says. Off: Cinematic's own, thin black bars sliding in with the " ..
		"UI's fade (the preview shows that too). Each setting keeps its value for when you turn this back on."],
		intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "letterboxStyle")

	-- The preview: a little screen with a lake at dusk, the bars over it as
	-- the real ones are drawn, the screen's own shape. Its Test takes them out
	-- and back in.
	local PREVIEW_W = 480
	preview = CreateFrame("Frame", nil, content)
	preview:SetSize(PREVIEW_W, 270)
	if preview.SetClipsChildren then preview:SetClipsChildren(true) end
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
	local comeBack -- (the test's: back in once out)
	local function Draw()
		-- (The screen's shape, which can change with the resolution.)
		local width, height = UIParent:GetWidth(), UIParent:GetHeight()
		local previewH = math.floor(PREVIEW_W * height / math.max(width, 1) + 0.5)
		preview:SetHeight(previewH)
		ns.StyleScene(preview) -- (cut to the screen's shape: StylePages.lua)
		local t = progress * progress * (3 - 2 * progress)
		ns.DrawLetterbox(bars, ns.LetterboxLook(), preview:GetWidth(), previewH, t, previewH / math.max(height, 1))
		bars:SetShown(progress > 0)
	end
	function preview:Refresh()
		Draw()
	end
	preview:SetScript("OnUpdate", function(_, elapsed)
		if progress ~= target then
			progress = ns.Approach(progress, target, elapsed, ns.LetterboxTime(ns.LetterboxLook(), target > progress))
			Draw()
		elseif comeBack and progress == 0 then
			comeBack, target = nil, 1
		end
	end)
	kit.AddControl(preview)

	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	-- Test: the bars out, then back in once they're gone, as at a fight's start and end.
	ns.StylePreviewTest(over, kit, L["Takes the bars out and brings them back in, as at a fight's start and end."],
		function()
			target, comeBack = 0, true
		end)

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
	rows.PresetMenu(PRESETS, PRESET_KEYS)

	stack:Header(content, L["Size"])
	rows.Choices(L["Set by:"], "letterboxSizeBy", {
		{ "height", L["Height"], L["Each bar a share of the screen's height."] },
		{ "aspect", L["A film's frame"], L["The bars as tall as it takes for what's left between them to have a " ..
			"film's shape, whatever your screen."] },
	})
	rows.Slider("letterboxSize", L["Bar height"], 0, 25, 1, "%d%%", 100,
		L["How tall each bar is, as a share of the screen's height."],
		function(db) return db.letterboxStyle and db.letterboxSizeBy ~= "aspect" end)
	rows.Choices(L["Frame:"], "letterboxAspect", {
		{ 2.39, L["2.39:1 (cinema)"] },
		{ 2, L["2:1"] },
		{ 1.85, L["1.85:1"] },
	}, function(db) return db.letterboxStyle and db.letterboxSizeBy == "aspect" end)

	stack:Header(content, L["Look"])
	rows.Swatch(rows.Choices(L["Color:"], "letterboxColor", {
		{ "black", L["Black"] },
		{ "custom", L["Custom"] },
	}), "letterboxColor", { "letterboxR", "letterboxG", "letterboxB" }, L["Pick the bars' color."])
	rows.Slider("letterboxAlpha", L["Opacity"], 10, 100, 5, "%d%%", 100,
		L["How see-through the bars are."])
	rows.Choices(L["Inner edge:"], "letterboxEdge", {
		{ "hard", L["Hard"] },
		{ "soft", L["Soft (feathered)"], L["The bars fade into the scene past their edge."] },
	})
	rows.Slider("letterboxFeather", L["Feather"], 5, 80, 5, "%d", 1,
		L["How far past the bars' edge they fade into the scene."],
		function(db) return db.letterboxStyle and db.letterboxEdge == "soft" end)
	rows.Swatch(rows.Choices(L["Line along the edge:"], "letterboxLine", {
		{ "none", L["None"] },
		{ "gold", L["Gold"] },
		{ "custom", L["Custom"] },
	}), "letterboxLine", { "letterboxLineR", "letterboxLineG", "letterboxLineB" }, L["Pick the line's color."])

	stack:Header(content, L["Coming in and going"])
	rows.Choices(L["How:"], "letterboxMotion", {
		{ "slide", L["Slide in"], L["The bars grow in from the screen's edges."] },
		{ "fade", L["Fade in"], L["The bars fade in at their full height."] },
	})
	rows.Slider("letterboxTime", L["How long"], 0, 30, 1, function(value)
		return value == 0 and L["With the UI"] or ("%.1f s"):format(value / 10)
	end, 10, L["How long the bars take to come in or go. 0: as long as the UI's own fades (the main page's " ..
		"Fade in and Fade out times)."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Letterbox Style", L["Letterbox"])
end
