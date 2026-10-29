-- What the Style hub's pages made in their own files share (LetterboxStyle.lua,
-- QuestItemStyle.lua): rows of choices, color swatches, sliders and a row of
-- presets, each greyed out unless the page's switch (or its own test) says,
-- and each change shown at once (changed()).

local _, ns = ...

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
	-- a pick puts key on Custom.
	function rows.Swatch(after, key, keys, tip)
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
				changed()
				kit.Refresh()
			end)
		end)
		kit.GreyUnless(swatch, On)
		kit.AddControl(swatch)
		return swatch
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
