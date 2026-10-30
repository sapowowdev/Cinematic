-- The Letterbox and Tint pages (their Show in rows), and Letterbox's Style
-- tab: how the letterbox bars look and come in (Effects.lua draws them, by ns.LetterboxLook). Their height by a share of
-- the screen or by a film's frame, color, opacity, a feathered inner edge, a
-- line along it, and sliding or fading in, over the UI's fade or a time of
-- their own. A preview at the top, drawn by the same code as the real bars.
-- When they show at all: the Letterbox tab (ns.CreateEffectPanel). Both in the
-- Atmosphere hub under one icon.

local _, ns = ...
local L = ns.L

-- The look's settings a preset sets (the rest as the defaults; the custom
-- colors are kept, for a pick of Custom later).
local PRESET_KEYS = { "letterboxSizeBy", "letterboxSize", "letterboxAspect", "letterboxColor", "letterboxAlpha",
	"letterboxEdge", "letterboxFeather", "letterboxLine", "letterboxMotion", "letterboxTime" }

-- The Atmosphere hub's effects with a page of their own: a Show in row on
-- the first tab, the look on the Style tab (English: L at the call, once the
-- language is set). page: the first tab's page, style: the Style tab's.
local EFFECT_PAGES = {
	letterbox = { name = "Letterbox", page = "Letterbox", style = "Letterbox Style",
		tip = "Where and when the bars show.", styleTip = "How the letterbox bars look and come in.",
		intro = "Black bars at the top and bottom of the screen in CineMode, like a film's. Where and when they " ..
			"show: the row below (nothing ticked: off). Their size and look: the Style tab. The Visual Effects " ..
			"page's Enable page turns them off too." },
	tint = { name = "Tint", page = "Tint", style = "Tint Style",
		tip = "Where and when the tint shows.",
		styleTip = "The color grading: a preset, the time of day and each zone's mood.",
		intro = "The color grading over the game world in CineMode. Where and when it shows: the row below " ..
			"(nothing ticked: off). Its preset, the time of day and the zones' tints: the Style tab. The Visual " ..
			"Effects page's Enable page turns it off too. The UI isn't tinted." },
}

-- Under the Tint tab's row: how strong it is, its drift, and the zone
-- borders' timing, each slider on one line with its name (stack: inline).
EFFECT_PAGES.tint.More = function(kit, content, stack)
	stack:Header(content, L["How strong"])
	local strength = stack:Add(kit.Slider(content, "tintStrength", L["Strength"], 5, 100, 5, "%d%%", 100,
		ns.RefreshTint), "slider")
	kit.Tooltip(strength, L["How strongly the tint colors the world, for every preset."])
	local timeStrength = stack:Add(kit.Slider(content, "timeTintStrength", L["Time of day strength"], 0, 100, 5,
		"%d%%", 100, ns.RefreshTint), "slider")
	kit.Tooltip(timeStrength, L["How strongly the time-of-day color applies, in Time of day and " ..
		"Zone + time of day. Lower it for softer nights; 0 leaves just the zone mood."])
	local drift = stack:Add(kit.Check(content, "tintDrift", L["Subtle drift"],
		L["The tint's strength slowly wanders up and down over a few minutes, so a still scene " ..
		"feels a little more alive. Paused while the Style tab is open."]), "check")
	drift:HookScript("OnClick", function()
		kit.Refresh() -- (grey out / enable the amount slider)
		ns.RefreshTint()
	end)
	local driftAmount = stack:Add(kit.Slider(content, "tintDriftAmount", L["Drift amount"], 2, 15, 1, "+/-%d%%", 100,
		ns.RefreshTint), "slider")
	kit.Tooltip(driftAmount, L["How far the strength wanders either way, as a share of the strength."])
	kit.GreyUnless(driftAmount, function(db) return db.tintDrift end)

	-- Crossing a zone border: how the old zone's tint gives way to the new one.
	stack:Header(content, L["At zone borders"])
	local zoneFade = stack:Add(kit.Slider(content, "zoneFadeTime", L["Fade time"], 0.5, 10, 0.5, L["%.1f sec"]),
		"slider")
	kit.Tooltip(zoneFade, L["With a Zone tint preset, crossing into a zone with a different mood " ..
		"fades the old mood out over this long, pauses, then fades the new one in over " ..
		"this long."])
	local gapFlying = stack:Add(kit.Slider(content, "zoneGapFlying", L["Pause between tints when flying"], 0, 20, 1,
		L["%d sec"]), "slider")
	kit.Tooltip(gapFlying, L["Untinted time between the two zones' moods while you're in the air, " ..
		"where you see the old zone's ground for longer (snow under an ember tint looks red)."])
	local gapGround = stack:Add(kit.Slider(content, "zoneGapTime", L["Pause between tints on the ground"], 0, 10, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(gapGround, L["The same pause when you cross a border on foot or riding."])
end

-- An effect's two tabs (picked: 1 its Show in, 2 Style). title: the page's,
-- put under them.
function ns.EffectTabs(content, title, effect, picked)
	local info = EFFECT_PAGES[effect]
	local panel = ns.PageTabs(content, {
		{ L[info.name], info.page, L[info.tip] },
		{ L["Style"], info.style, L[info.styleTip] },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
end

-- An effect's first tab: its Show in row (effect:<effect>, as the Visual
-- Effects page's rows: off everywhere switches it off).
function ns.CreateEffectPanel(kit, effect)
	local info = EFFECT_PAGES[effect]
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L[info.name])
	ns.EffectTabs(content, title, effect, 1)
	local intro = kit.PageIntro(content, title, L[info.intro])
	local stack = kit.Stack(intro, "label")
	local header = stack:Header(content, L["Show in"])
	local key, alwaysKey = "effect:" .. effect, effect .. "Always"
	local lastRow = ns.ShowTable(content, header, {
		opts = { quiet = true, cam = true, anyFight = true }, underHeader = true,
		{ key = key, label = L[info.name], alwaysKey = alwaysKey,
			alwaysOn = function() return ns.GetDB()[alwaysKey] end,
			setAlways = function(value) ns.GetDB()[alwaysKey] = value end,
			alwaysTip = L["Shows all through CineMode. (The other columns then have nothing to add.)"],
			apply = function()
				local switch = ns.EFFECT_SWITCHES and ns.EFFECT_SWITCHES[effect]
				if switch then ns.GetDB()[switch] = ns.RowOnAnywhere(key, ns.GetDB()[alwaysKey]) end
				ns.letterboxDirty = true
				if ns.RefreshTint then ns.RefreshTint() end
			end },
	}, L[info.name])
	stack:Continue(lastRow, "label")
	if info.More then
		info.More(kit, content, kit.Stack(lastRow, "label", true))
	end
	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, info.page)
end

function ns.CreateLetterboxStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Letterbox"])
	ns.EffectTabs(content, title, "letterbox", 2)
	local intro = kit.PageIntro(content, title,
		L["How the bars at the top and bottom of the screen look and come in. When they show: the Letterbox " ..
		"tab. Changes show at once, here and on the bars."])

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
