-- What the Style hub's pages made in their own files share (LetterboxStyle.lua,
-- QuestItemStyle.lua): rows of choices, color swatches, sliders and a row of
-- presets, each greyed out unless the page's switch (or its own test) says,
-- and each change shown at once (changed()).

local ADDON_NAME, ns = ...

-- The previews' backdrop: a lake at dusk, 2:1 (Media/make_letterbox_scene.py).
local SCENE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\LetterboxScene"

-- The previews show it, or a plain dark ground (the tickbox above each: one
-- setting for them all).
ns.DEFAULTS.styleScene = true
local scenes = setmetatable({}, { __mode = "k" }) -- (frame -> { focus, shade })

-- The scene behind frame (made once, then cut again: call it as frame's size
-- changes), cut to frame's shape from its middle, never stretched: a wide
-- strip shows the band at focus (0 top, 1 bottom: the hills and the lake,
-- 0.55, by default). shade: darker, for text over it (1: as it is).
function ns.StyleScene(frame, focus, shade)
	scenes[frame] = { focus, shade }
	local scene = frame.styleScene
	if not scene then
		scene = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		scene:SetAllPoints()
		frame.styleScene = scene
	end
	if ns.db and ns.db.styleScene == false then
		scene:SetColorTexture(0.11, 0.14, 0.18, 0.95)
		scene:SetVertexColor(1, 1, 1, 1)
		scene:SetTexCoord(0, 1, 0, 1)
		return scene
	end
	scene:SetTexture(SCENE)
	shade = shade or 1
	scene:SetVertexColor(shade, shade, shade, 1)
	local width, height = frame:GetWidth(), frame:GetHeight()
	local aspect = (width and height and height > 0) and width / height or 2
	if aspect >= 2 then
		local part = 2 / aspect
		local top = math.min(math.max((focus or 0.55) - part / 2, 0), 1 - part)
		scene:SetTexCoord(0, 1, top, top + part)
	else
		local cut = (1 - aspect / 2) / 2
		scene:SetTexCoord(cut, 1 - cut, 0, 1)
	end
	return scene
end

-- A toggle button's look: its text gold while it's on, grey while it's off
-- (its normal font: the mouse over it still lights it, as any button).
function ns.StyleToggle(button, on)
	button:SetNormalFontObject(on and "GameFontNormal" or "GameFontDisable")
end

-- A Visions hub page's link to its Style hub page: a small Style button right
-- of the page's title, past its "?" (PageIntro). page: the Style page's name,
-- as ns.OpenOptions takes it. Tooltip: the page's (Options.lua's).
function ns.StyleLink(content, title, page, tip, Tooltip)
	local button = ns.PanelButton(content)
	button:SetSize(70, 20)
	button:SetText(ns.L["Style"])
	button:SetPoint("LEFT", title, "RIGHT", 44, 0)
	Tooltip(button, tip)
	button:SetScript("OnClick", function() ns.OpenOptions(page) end)
	return button
end

-- The Scene button above a preview: the scene behind every preview, or a
-- plain ground (one setting for them all). Tooltip, AddControl: the page's
-- (Options.lua's, as the kit has them). Works with the page's switch off too.
-- Place it as the page places controls.
function ns.StyleSceneButton(content, Tooltip, AddControl)
	local button = ns.PanelButton(content)
	button:SetSize(110, 22)
	button:SetText(ns.L["Scene"])
	Tooltip(button, ns.L["A lake at dusk behind the previews on the Style pages, to see the look over the " ..
		"world. Off: a plain dark ground."])
	local function Apply()
		ns.StyleToggle(button, ns.GetDB().styleScene ~= false)
		for frame, how in pairs(scenes) do ns.StyleScene(frame, how[1], how[2]) end
	end
	button:SetScript("OnClick", function()
		local db = ns.GetDB()
		db.styleScene = db.styleScene == false
		Apply()
	end)
	-- (and as its page shows: the pages are made before the settings may be loaded)
	button.Refresh = Apply
	button.pageSwitch = false
	AddControl(button)
	return button
end

-- The rows for a page: kit (Options.lua's ns.lowHealthKit), its content and
-- stack, changed() after each change, and its switch's key.
function ns.StyleRows(kit, content, stack, changed, switchKey)
	local rows = {}
	local function On(db) return db[switchKey] end
	rows.On = On

	-- A row of choices for key, after its name: { value, text, tip } each.
	-- Gives the last, to put a color swatch after.
	function rows.Choices(label, key, list, test)
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetWidth(150)
		local last
		for _, info in ipairs(list) do
			local choice = kit.Choice(content, key, info[1], info[2], info[3])
			choice:HookScript("OnClick", changed)
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
	-- a pick puts key on Custom (key nil: a color of its own, no choices).
	function rows.Swatch(after, key, keys, tip, test)
		local swatch = CreateFrame("Button", nil, content)
		swatch:SetSize(18, 18)
		swatch:SetPoint("LEFT", after.Text or after.text or after, "RIGHT", 10, 0)
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
				if key then db[key] = "custom" end
				changed()
				kit.Refresh()
			end)
		end)
		kit.GreyUnless(swatch, test or On)
		kit.AddControl(swatch)
		return swatch
	end

	-- A color on a row of its own: its name, then its swatch.
	function rows.Color(label, keys, tip, test)
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 22) -- (room for the swatch, rows of them one under another)
		return rows.Swatch(name, nil, keys, tip, test)
	end

	function rows.Slider(key, label, minV, maxV, step, fmt, scale, tip, test)
		local slider = stack:Add(kit.Slider(content, key, label, minV, maxV, step, fmt, scale, changed), "slider")
		if tip then kit.Tooltip(slider, tip) end
		kit.GreyUnless(slider, test or On)
		return slider
	end

	function rows.Check(key, label, tip, test)
		local check = stack:Add(kit.Check(content, key, label, tip, function(value)
			ns.GetDB()[key] = value
			changed()
			kit.Refresh()
		end), "check")
		kit.GreyUnless(check, test or On)
		return check
	end

	-- A row of preset buttons, width wide: { name, tip, settings } each; a
	-- pick turns the page on and sets keys as its settings say, the rest as
	-- their defaults.
	function rows.Presets(presets, keys, width)
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(width, 24)
		stack:Add(row, "label")
		local last
		for _, preset in ipairs(presets) do
			local button = ns.PanelButton(row)
			button:SetText(preset[1])
			button:SetSize(math.max(110, button:GetFontString():GetStringWidth() + 24), 22)
			if last then
				button:SetPoint("LEFT", last, "RIGHT", 8, 0)
			else
				button:SetPoint("LEFT", row, "LEFT", 0, 0)
			end
			kit.Tooltip(button, preset[2])
			button:SetScript("OnClick", function()
				local db = ns.GetDB()
				db[switchKey] = true
				for _, key in ipairs(keys) do
					local value = preset[3][key]
					if value == nil then value = ns.DEFAULTS[key] end
					db[key] = value
				end
				changed()
				kit.Refresh()
			end)
			button.Refresh = function() end
			kit.GreyUnless(button, On)
			kit.AddControl(button)
			last = button
		end
		return row
	end

	return rows
end
