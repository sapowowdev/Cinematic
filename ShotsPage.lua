-- Cinematic: the My Shots page (Camera hub), for Shots.lua's shots: pick
-- one, give it a name and a camera, and set its sway and zoom; test it, share
-- it, or add one a friend shared. Triggers pick shots on the Cameras page.
local _, ns = ...

function ns.CreateMyShotsPanel(kit)
	local L = ns.L
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", L["My Shots"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title, L["A shot is one of the cameras that run while you stand still " ..
		"(cozy, vista, fish or AFK) with numbers of your own for how it sways and zooms. Make one here, then pick " ..
		"it as a trigger's camera on the Cameras page. A number you haven't changed follows the camera's own " ..
		"settings."])

	local selected -- (the shot shown)
	local function Shot()
		local list, set = ns.ShotList()
		if not (selected and set[selected]) then selected = list[1] end
		return selected
	end
	local Layout -- (below)
	local function Changed()
		ns.CameraRowsChanged()
		kit.Refresh()
		Layout()
	end
	local function Button(text, width, tip, onClick)
		local button = ns.PanelButton(content)
		button:SetSize(width, 22)
		button:SetText(text)
		button.searchSkip = true
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", onClick)
		return button
	end

	-- The shot shown, and what can be done with it.
	local pick = ns.ChoiceMenu(content, 190, function()
		local list = {}
		for _, id in ipairs((ns.ShotList())) do list[#list + 1] = { value = id, text = ns.ShotName(id) } end
		return list
	end, Shot, function(value)
		selected = value
		Changed()
	end)
	pick:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
	kit.Tooltip(pick, L["The shot to show and change."])
	kit.AddControl(pick)
	local newShot = Button(L["+ New shot"], 100, L["Make a shot, starting from the cozy camera's own numbers. " ..
		"Pick another camera for it below."], function()
		local id = ns.AddShot("cozy")
		if id then
			selected = id
			Changed()
		end
	end)
	newShot.Refresh = function(self) self:SetEnabled(#(ns.ShotList()) < ns.SHOT_MAX) end
	kit.AddControl(newShot)
	local test = Button(L["Test"], 60, L["Play this shot now (stand still). Press it again, or move, to stop."],
		function() if Shot() then ns.TestShot(Shot()) end end)
	local share = Button(L["Share"], 64, L["Text to send a friend: they add this shot with Import here or on " ..
		"their Cameras page."], function()
		if Shot() then ns.ShowCameraShare(ns.ExportShot(Shot()), (L["Share %s"]):format(ns.ShotName(Shot()))) end
	end)
	local import = Button(L["Import"], 64, L["Add a trigger or shot a friend shared (the text from their Share " ..
		"button)."], function()
		ns.ShowCameraImport(function(id, kind)
			if kind == "shot" then selected = id end
			Changed()
		end)
	end)
	local delete = Button(L["Delete"], 64, L["Delete this shot. Triggers that played it go back to its camera."],
		function()
			local id = Shot()
			if not id then return end
			if not StaticPopupDialogs.CINEMATIC_REMOVE_SHOT then
				StaticPopupDialogs.CINEMATIC_REMOVE_SHOT = {
					text = L["Delete the shot %s? Triggers that played it go back to its camera."],
					button1 = DELETE or L["Delete"], button2 = CANCEL or L["Cancel"],
					OnAccept = function(_, data) data() end,
					timeout = 0, whileDead = true, hideOnEscape = true,
				}
			end
			StaticPopup_Show("CINEMATIC_REMOVE_SHOT", (ns.ShotName(id):gsub("|", "")), nil, function()
				ns.RemoveShot(id)
				selected = nil
				Changed()
			end)
		end)
	newShot:SetPoint("LEFT", pick, "RIGHT", 10, 0)
	test:SetPoint("LEFT", newShot, "RIGHT", 6, 0)
	share:SetPoint("LEFT", test, "RIGHT", 6, 0)
	import:SetPoint("LEFT", share, "RIGHT", 6, 0)
	delete:SetPoint("LEFT", import, "RIGHT", 6, 0)

	local empty = kit.Label(content, "GameFontDisable", L["No shots yet. + New shot makes one, or Import adds " ..
		"one a friend shared."])
	empty:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 2, -18)

	-- The shot's name, camera and numbers.
	local body = CreateFrame("Frame", nil, content)
	body:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -14)
	body:SetSize(560, 10)
	local nameLabel = kit.Label(body, "GameFontNormalSmall", L["Name"])
	nameLabel:SetPoint("TOPLEFT", 2, -6)
	local nameBox = ns.SkinEditBox(CreateFrame("EditBox", nil, body, "InputBoxTemplate"))
	nameBox:SetSize(200, 20)
	nameBox:SetPoint("LEFT", nameLabel, "LEFT", 70, 0)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(40)
	nameBox.searchSkip = true
	nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	nameBox:SetScript("OnEditFocusLost", function(self)
		local id = Shot()
		if not id then return end
		local text = self:GetText():gsub("[%c|]", ""):match("^%s*(.-)%s*$")
		ns.GetDB().cameraRows[id .. ".name"] = text ~= "" and text or nil
		Changed()
	end)
	nameBox:SetScript("OnEscapePressed", function(self)
		self:SetText(Shot() and ns.ShotName(Shot()) or "")
		self:ClearFocus()
	end)
	nameBox.Refresh = function(self)
		if not self:HasFocus() then self:SetText(Shot() and ns.ShotName(Shot()) or "") end
	end
	kit.Tooltip(nameBox, L["The shot's name, as the Cameras page lists it."])
	kit.AddControl(nameBox)

	local baseLabel = kit.Label(body, "GameFontNormalSmall", L["Camera"])
	baseLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -22)
	local BASES = {}
	local base = ns.ChoiceMenu(body, 170, function()
		if #BASES == 0 then
			for _, value in ipairs(ns.SHOT_BASES) do BASES[#BASES + 1] = { value = value, text = ns.CAMERA_NAMES[value] } end
		end
		return BASES
	end, function() return Shot() and ns.ShotBaseOf(Shot()) end, function(value)
		if not Shot() then return end
		ns.GetDB().cameraRows[Shot() .. ".base"] = value
		Changed()
	end)
	base:SetPoint("LEFT", baseLabel, "LEFT", 66, 0)
	kit.Tooltip(base, L["The camera it moves like: cozy swings round to face you, vista and fish settle behind you " ..
		"(fish sways less), AFK turns right round you. Its other settings (Camera Settings page) go on as they are."])
	kit.AddControl(base)

	local sliders = {}
	for _, setting in ipairs(ns.SHOT_SETTINGS) do
		local slider = kit.Slider(body, {
			get = function() return Shot() and ns.ShotValue(Shot(), setting.key) or setting.min end,
			set = function(value) if Shot() then ns.SetShotValue(Shot(), setting.key, value) end end,
		}, setting.label, setting.min, setting.max, setting.step, setting.fmt)
		slider:SetWidth(260)
		kit.Tooltip(slider, setting.tip)
		slider.setting = setting
		sliders[#sliders + 1] = slider
	end

	local reset = ns.PanelButton(body)
	reset:SetSize(220, 22)
	reset:SetText(L["Use the camera's own numbers"])
	reset.searchSkip = true
	kit.Tooltip(reset, L["Clears this shot's numbers, so each follows its camera's own setting again."])
	reset:SetScript("OnClick", function()
		if Shot() then
			ns.ResetShot(Shot())
			Changed()
		end
	end)
	local usedBy = kit.Label(body, "GameFontHighlightSmall", "")
	usedBy:SetJustifyH("LEFT")
	usedBy:SetWidth(520)

	-- (A row's name, as the Cameras page shows it.)
	local function RowName(row)
		local trigger, copy = ns.CameraRowTrigger(row)
		local name = trigger and trigger.key or row
		if trigger and trigger.custom then
			name = ns.CustomTriggerLabel(trigger.key)
		else
			for _, event in ipairs(ns.EVENTS) do
				if trigger and event.key == trigger.key then name = event.label end
			end
		end
		return name .. (copy and " (" .. copy .. ")" or "")
	end

	-- Shows what fits the shot: the sliders its camera has, in order.
	function Layout()
		local id = Shot()
		local has = id ~= nil
		empty:SetShown(not has)
		body:SetShown(has)
		for _, button in ipairs({ test, share, delete }) do button:SetShown(has) end
		pick:SetShown(has)
		if not has then
			newShot:ClearAllPoints()
			newShot:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
			kit.FitContentHeight(content)
			return
		end
		newShot:ClearAllPoints()
		newShot:SetPoint("LEFT", pick, "RIGHT", 10, 0)
		local camera = ns.ShotBaseOf(id)
		local y = 92
		for _, slider in ipairs(sliders) do
			local setting = slider.setting
			local shown = (not setting.only or setting.only == camera) and setting.skip ~= camera
			slider:SetShown(shown)
			if shown then
				slider:ClearAllPoints()
				slider:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -y)
				y = y + 44
			end
		end
		reset:ClearAllPoints()
		reset:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(y - 14))
		local names = {}
		for _, row in ipairs(ns.ShotUsers(id)) do names[#names + 1] = RowName(row) end
		usedBy:SetText(#names > 0 and (L["Played by: %s"]):format(table.concat(names, ", "))
			or L["No trigger plays it yet: pick it as a camera on the Cameras page."])
		usedBy:ClearAllPoints()
		usedBy:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 2, -10)
		body:SetHeight(y + 40)
		kit.FitContentHeight(content)
	end

	canvas:SetScript("OnShow", kit.PageShown(function()
		-- (Opened by a camera menu's New shot...: that shot.)
		if ns.myShotsSelect then
			selected, ns.myShotsSelect = ns.myShotsSelect, nil
		end
		kit.Refresh()
		Layout()
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "My Shots")
end
