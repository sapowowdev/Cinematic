-- Cinematic: the Wheels pages, a hub with an icon for each wheel. A wheel's
-- page says what it does, shows its ring as it is now (point at an icon for
-- its name) and has its keybind, and, but for the master wheel's, an "On the
-- master wheel" tick. The master wheel's page lists the wheels on it, in
-- their order round the ring.
local _, ns = ...
local L = ns.L

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- (a round mask every client has)
local RADIUS = 78     -- the preview's: from the middle to each icon's centre; more for many icons
local ICON_SIZE = 34
local ICON_GAP = 12   -- at least this between icons round the ring
local DEAD_ZONE = 44  -- the middle circle's radius
local ROW = 28        -- the master wheel's list: each wheel's row

-- The text that's the wheels' (the same as the Keybinds page's, so it's
-- translated once).
local TIPS = {
	master = "Hold to bring up a wheel of the wheels below (camera, menu, marker...): point at one and " ..
		"let go to open it, then click what you want on it. Tap it instead and the wheel stays up for you " ..
		"to click one. The camera wheel can't open in a fight.",
	camera = "Hold to bring up a wheel of the cameras below, an icon for each: point at one and let go " ..
		"to start it. Tap it instead and the wheel stays up for you to click one. Picking the camera " ..
		"that's running stops it.",
	menu = "Hold to bring up a wheel of the game's menu buttons (character, spellbook, quest log...), " ..
		"the ones on your menu bar: point at one and let go to open its window, even with the UI hidden. " ..
		"Tap it instead and the wheel stays up for you to click one.",
	marker = "Hold to bring up a wheel of the raid target markers (skull, cross, square...) for your " ..
		"target, or with none, whatever the cursor is on: point at one and let go to put it on them, or at None to take theirs off. Tap it instead " ..
		"and the wheel stays up for you to click one.",
	world = "Hold to bring up a wheel of the ground markers (the colored lights you drop on the floor): " ..
		"point at one and let go, and it drops under the cursor. Picking one that's down moves it; Clear " ..
		"all takes them all up. Tap it instead and the wheel stays up for you to click one. Only in a group.",
	vision = "Hold to bring up a wheel of the visions (Heal, Quest, Duel...), ringed while they're on: " ..
		"point at one and let go to turn it on or off, in a fight too. Tap it instead and the wheel stays " ..
		"up for you to click one.",
}

-- A secure wheel's slots now, for its preview.
local function SlotsOf(key)
	local wheel = ns.markerWheels and ns.markerWheels[key]
	local list = {}
	for _, entry in ipairs(wheel and wheel.GetSlots() or {}) do
		list[#list + 1] = { label = L[entry.label], icon = entry.icon, trim = entry.trim, color = entry.color }
	end
	return list
end

-- Each built-in wheel's page, in the hub's order: key (as the master wheel
-- saves it), its page's name (English), its key binding, and Entries(), its
-- slots now (each: label, and icon with trim and color, or Paint(icon, under)).
local WHEELS = {
	{ key = "master", label = "Master wheel", action = "CLICK CinematicMasterWheelButton:LeftButton",
		Entries = function() return SlotsOf("master") end },
	{ key = "camera", label = "Camera wheel", action = "CINEMATIC_CAMWHEEL",
		Entries = function()
			local list = {}
			for _, camera in ipairs(ns.CAMERA_WHEEL_LIST or {}) do
				list[#list + 1] = { label = L[camera.label], icon = camera.icon, trim = true }
			end
			return list
		end },
	{ key = "menu", label = "Menu wheel", action = "CLICK CinematicMenuWheelButton:LeftButton",
		Entries = function() return ns.MenuWheelPreview and ns.MenuWheelPreview() or {} end },
	{ key = "marker", label = "Marker wheel", action = "CLICK CinematicMarkerWheelButton:LeftButton",
		Entries = function() return SlotsOf("marker") end },
	{ key = "world", label = "Ground marker wheel", action = "CLICK CinematicWorldMarkerWheelButton:LeftButton",
		Entries = function() return SlotsOf("world") end },
	{ key = "vision", label = "Vision wheel", action = "CLICK CinematicVisionWheelButton:LeftButton",
		Entries = function() return SlotsOf("vision") end },
}

local function IsOnMaster(key)
	for _, item in ipairs(ns.MasterWheelOrder()) do
		if item.choice.key == key then
			return item.on
		end
	end
	return false
end

local function SetOnMaster(key, on)
	local list = ns.MasterWheelOrder()
	for _, item in ipairs(list) do
		if item.choice.key == key then
			item.on = on
		end
	end
	ns.SetMasterWheelOrder(list)
end

-- (Round, like the wheel's own.)
local function Round(frame, texture)
	if frame.CreateMaskTexture then
		local mask = frame:CreateMaskTexture()
		mask:SetAllPoints(texture)
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
		texture:AddMaskTexture(mask)
		return mask
	end
end

-- A wheel drawn on the page as it looks in the game: icons round a dark
-- disc, the one the cursor's on named in the middle. preview:SetEntries(list)
-- puts its icons on it; title: the middle's text with none pointed at.
local function Preview(parent, title)
	local frame = CreateFrame("Frame", nil, parent)
	local disc = frame:CreateTexture(nil, "BACKGROUND")
	disc:SetPoint("CENTER")
	disc:SetColorTexture(0, 0, 0, 0.55)
	Round(frame, disc)
	local hub = frame:CreateTexture(nil, "BORDER")
	hub:SetPoint("CENTER")
	hub:SetSize(DEAD_ZONE * 2, DEAD_ZONE * 2)
	hub:SetColorTexture(0.45, 0.36, 0.12, 0.6)
	Round(frame, hub)
	local centerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	centerText:SetPoint("CENTER")
	centerText:SetWidth(DEAD_ZONE * 2 - 8)
	centerText.searchSkip = true
	local icons = {}

	local function ShowTitle()
		centerText:SetText(title)
		centerText:SetTextColor(1, 0.82, 0)
	end

	local function MakeIcon()
		local button = CreateFrame("Frame", nil, frame)
		button:SetSize(ICON_SIZE, ICON_SIZE)
		button:EnableMouse(true)
		local under = button:CreateTexture(nil, "ARTWORK", nil, -1) -- (the menu wheel's character slot)
		under:SetAllPoints()
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		button.icon, button.under = icon, under
		if button.CreateMaskTexture then
			button.mask = button:CreateMaskTexture()
			button.mask:SetAllPoints(icon)
			button.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
		end
		button:SetScript("OnEnter", function(self)
			local entry = self.entry
			centerText:SetText(entry.label)
			local color = entry.color or { 1, 0.82, 0.3 }
			centerText:SetTextColor(color[1], color[2], color[3])
		end)
		button:SetScript("OnLeave", ShowTitle)
		return button
	end

	function frame:SetEntries(list)
		local count = #list
		local radius = math.max(RADIUS, count * (ICON_SIZE + ICON_GAP) / (2 * math.pi))
		local outer = radius + ICON_SIZE * 0.9
		frame:SetSize(outer * 2, outer * 2)
		disc:SetSize(outer * 2, outer * 2)
		for i = 1, math.max(count, #icons) do
			local entry, button = list[i], icons[i]
			if entry and not button then
				button = MakeIcon()
				icons[i] = button
			end
			if entry then
				button.entry = entry
				local angle = math.rad(90 - (i - 1) * 360 / count)
				button:ClearAllPoints()
				button:SetPoint("CENTER", frame, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
				button.under:Hide()
				if entry.Paint then
					entry.Paint(button.icon, button.under)
				else
					button.icon:SetTexture(entry.icon)
					if entry.trim then
						button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
					else
						button.icon:SetTexCoord(0, 1, 0, 1)
					end
				end
				-- (A spell's square icon cut to a circle, as on the wheel.)
				local masked = entry.trim and true or false
				if button.mask and masked ~= (button.masked or false) then
					if masked then
						button.icon:AddMaskTexture(button.mask)
					else
						button.icon:RemoveMaskTexture(button.mask)
					end
					button.masked = masked
				end
				button:Show()
			elseif button then
				button:Hide()
			end
		end
		if count == 0 then
			centerText:SetText(L["No wheels on it"])
			centerText:SetTextColor(0.6, 0.6, 0.6)
		else
			ShowTitle()
		end
	end

	ShowTitle()
	return frame
end

-- The keybind row: a label and two slots, as on the Keybinds page.
local function KeyRow(kit, content, anchor, action)
	local label = kit.Label(content, "GameFontHighlight", L["Key"])
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
	label:SetWidth(60)
	local first = kit.CreateKeybindButton(content, action, 1)
	first:SetPoint("LEFT", label, "RIGHT", 10, 0)
	local second = kit.CreateKeybindButton(content, action, 2)
	second:SetPoint("LEFT", first, "RIGHT", 8, 0)
	return label
end

-- A page's title and what the wheel does, under it.
local function Top(kit, content, info)
	local title = kit.Label(content, "GameFontNormalLarge", L[info.label])
	title:SetPoint("TOPLEFT", 16, -16)
	local text = kit.Label(content, "GameFontHighlight", L[TIPS[info.key]])
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetWidth(560)
	text:SetSpacing(2)
	return text
end

local function Finish(kit, canvas, content, info, RefreshPage)
	canvas:RegisterEvent("UPDATE_BINDINGS")
	canvas:SetScript("OnEvent", kit.RefreshKeybinds)
	canvas:SetScript("OnShow", kit.PageShown(function()
		RefreshPage()
		kit.RefreshKeybinds()
	end, content))
	canvas:SetScript("OnHide", kit.StopListening)
	canvas:Hide()
	kit.RegisterSubpage(canvas, info.label)
end

local refreshMaster -- the master wheel's page, laid out again (once made)

-- A built-in wheel's page.
local function WheelPage(kit, info)
	local canvas, content = kit.CreateScrollPage(true)
	local text = Top(kit, content, info)
	local keyLabel = KeyRow(kit, content, text, info.action)
	local onMaster = kit.Check(content, nil, L["On the master wheel"],
		L["Its icon is on the master wheel, which opens it. Untick to leave it off: its own key still " ..
		"brings it up. The master wheel is the same for all your characters."],
		function(value)
			SetOnMaster(info.key, value)
			if refreshMaster then refreshMaster() end
		end)
	onMaster:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", -2, -12)
	onMaster.Refresh = function(self) self:SetChecked(IsOnMaster(info.key)) end
	local preview = Preview(content, L[info.label])
	preview:SetPoint("TOPLEFT", onMaster, "BOTTOMLEFT", 2, -16)
	Finish(kit, canvas, content, info, function()
		preview:SetEntries(info.Entries())
	end)
end

-- The master wheel's page: a row for each wheel it can have, ticked while
-- it's on it, with arrows to move it round the ring, then its preview.
local function MasterPage(kit, info)
	local canvas, content = kit.CreateScrollPage(true)
	local text = Top(kit, content, info)
	local keyLabel = KeyRow(kit, content, text, info.action)
	local header = kit.Header(content, L["Wheels on it"], keyLabel, -24)
	local rows = {} -- by key
	local preview = Preview(content, L[info.label])
	local usual -- the Usual order button

	local function Move(key, by)
		local list = ns.MasterWheelOrder()
		for i, item in ipairs(list) do
			if item.choice.key == key and list[i + by] then
				list[i], list[i + by] = list[i + by], list[i]
				break
			end
		end
		ns.SetMasterWheelOrder(list)
		refreshMaster()
	end

	local function Arrow(parent, dir)
		local button = CreateFrame("Button", nil, parent)
		button:SetSize(22, 22)
		local base = "Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. dir
		button:SetNormalTexture(base .. "-Up")
		button:SetPushedTexture(base .. "-Down")
		button:SetDisabledTexture(base .. "-Disabled")
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		return button
	end

	local function Row(choice)
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(320, ROW)
		local check = kit.Check(row, nil, L[choice.label], nil, function(value)
			SetOnMaster(choice.key, value)
			refreshMaster()
		end)
		check:SetPoint("LEFT", 26, 0)
		check.Refresh = function(self) self:SetChecked(IsOnMaster(choice.key)) end
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(20, 20)
		icon:SetPoint("LEFT", 0, 0)
		icon:SetTexture(choice.icon)
		if choice.trim then
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		end
		row.up, row.down = Arrow(row, "Up"), Arrow(row, "Down")
		row.down:SetPoint("RIGHT", 0, 0)
		row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
		kit.Tooltip(row.up, L["Earlier round the wheel (the first is at the top)."])
		kit.Tooltip(row.down, L["Later round the wheel."])
		row.up:SetScript("OnClick", function() Move(choice.key, -1) end)
		row.down:SetScript("OnClick", function() Move(choice.key, 1) end)
		row.check = check
		return row
	end
	for _, choice in ipairs(ns.MASTER_WHEEL_CHOICES or {}) do
		rows[choice.key] = Row(choice)
	end

	usual = ns.PanelButton(content)
	usual:SetSize(140, 22)
	usual:SetText(L["Usual order"])
	kit.Tooltip(usual, L["Every wheel back on the master wheel, in their usual order."])
	usual:SetScript("OnClick", function()
		ns.SetMasterWheelOrder(nil)
		refreshMaster()
	end)

	refreshMaster = function()
		local list = ns.MasterWheelOrder()
		local last = header
		for i, item in ipairs(list) do
			local row = rows[item.choice.key]
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8 - (i - 1) * ROW)
			row.check:Refresh()
			row.up:SetEnabled(i > 1)
			row.down:SetEnabled(i < #list)
			last = row
		end
		usual:ClearAllPoints()
		usual:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
		preview:ClearAllPoints()
		preview:SetPoint("TOPLEFT", usual, "BOTTOMLEFT", 0, -20)
		preview:SetEntries(info.Entries())
		kit.Refresh() -- (the other pages' "On the master wheel" ticks)
	end
	-- (The wheel's rebuilt after a fight if changed in one; its preview
	-- shows the settings meanwhile.)
	local entries = info.Entries
	info.Entries = function()
		if InCombatLockdown() then
			local list = {}
			for _, item in ipairs(ns.MasterWheelOrder()) do
				if item.on then
					list[#list + 1] = { label = L[item.choice.label], icon = item.choice.icon,
						trim = item.choice.trim, color = item.choice.color }
				end
			end
			return list
		end
		return entries()
	end
	Finish(kit, canvas, content, info, refreshMaster)
end

-- (Options.lua, once the language is known, with the helpers it shares.)
function ns.CreateWheelsPanels(kit)
	for _, info in ipairs(WHEELS) do
		if info.key == "master" then
			MasterPage(kit, info)
		elseif info.key ~= "world" or ns.hasWorldMarkerWheel then
			WheelPage(kit, info)
		end
	end
end
