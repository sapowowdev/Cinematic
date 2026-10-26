-- Cinematic: the Wheels pages, a hub with an icon for each wheel. A wheel's
-- page says what it does, shows its ring as it is now (point at an icon for
-- its name) and has its keybind, and, but for the master wheel's, an "On the
-- master wheel" tick. The master wheel's page lists the wheels on it, in
-- their order round the ring. Your wheels makes and edits wheels of the
-- player's own (CustomWheels.lua).
local _, ns = ...
local L = ns.L

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- (a round mask every client has)
local RADIUS = 78     -- the preview's: from the middle to each icon's centre; more for many icons
local ICON_SIZE = 34
local ICON_GAP = 12   -- at least this between icons round the ring
local DEAD_ZONE = 44  -- the middle circle's radius
local ROW = 28        -- the master wheel's list: each wheel's row
local SLOT_ROW = 46   -- Your wheels: each icon's row
local TILE = 36       -- Your wheels: each wheel's icon in the row of them
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

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
	yours = "Wheels of your own, up to 8: each icon on one runs a command when you pick it, such as " ..
		"/rw Pull in 10 or /readycheck (anything a macro can do, a line each), in a fight too. Give a " ..
		"wheel its own key here, or put it on the master wheel. They're the same for all your characters.",
}

-- (The skinned look where Skin.lua has it, else the game's own.)
local function PanelButton(parent)
	if ns.PanelButton then
		return ns.PanelButton(parent)
	end
	return CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
end
local function InputBox(parent)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	return ns.SkinEditBox and ns.SkinEditBox(box) or box
end

-- A secure wheel's slots now, for its preview.
local function SlotsOf(key)
	local wheel = ns.markerWheels and ns.markerWheels[key]
	local list = {}
	for _, entry in ipairs(wheel and wheel.GetSlots() or {}) do
		list[#list + 1] = { label = L[entry.label], icon = entry.icon, trim = entry.trim, color = entry.color }
	end
	return list
end

-- Each wheel's page, in the hub's order: key (as the master wheel saves
-- it), its page's name (English), its key binding, and Entries(), its slots
-- now (each: label, and icon with trim and color, or Paint(icon, under)).
local WHEELS = {
	{ key = "master", label = "Master wheel", action = "CLICK CinematicMasterWheelButton:LeftButton",
		Entries = function() return SlotsOf("master") end },
	{ key = "yours", label = "Your wheels" },
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
-- puts its icons on it; title: the middle's text with none pointed at
-- (preview:SetTitle changes it).
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
	local empty = true

	local function ShowTitle()
		if empty then
			centerText:SetText(L["Nothing on it yet"])
			centerText:SetTextColor(0.6, 0.6, 0.6)
		else
			centerText:SetText(title)
			centerText:SetTextColor(1, 0.82, 0)
		end
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

	function frame:SetTitle(text)
		title = text
		ShowTitle()
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
		empty = count == 0
		ShowTitle()
	end

	ShowTitle()
	return frame
end

-- The keybind row: a label and two slots, as on the Keybinds page. (Their
-- .action can change: Your wheels' are the wheel being edited's.)
local function KeyRow(kit, parent, anchor, action, yOffset)
	local label = kit.Label(parent, "GameFontHighlight", L["Key"])
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -16)
	label:SetWidth(60)
	local first = kit.CreateKeybindButton(parent, action, 1)
	first:SetPoint("LEFT", label, "RIGHT", 10, 0)
	local second = kit.CreateKeybindButton(parent, action, 2)
	second:SetPoint("LEFT", first, "RIGHT", 8, 0)
	return label, first, second
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

local function Finish(kit, canvas, content, info, RefreshPage, OnHide)
	canvas:RegisterEvent("UPDATE_BINDINGS")
	canvas:SetScript("OnEvent", kit.RefreshKeybinds)
	canvas:SetScript("OnShow", kit.PageShown(function()
		RefreshPage()
		kit.RefreshKeybinds()
	end, content))
	canvas:SetScript("OnHide", function()
		kit.StopListening()
		if OnHide then OnHide() end
	end)
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

-- Up and down arrows (the chat frame's).
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

-- The master wheel's page: a row for each wheel it can have (yours too),
-- ticked while it's on it, with arrows to move it round the ring, then its
-- preview.
local function MasterPage(kit, info)
	local canvas, content = kit.CreateScrollPage(true)
	local text = Top(kit, content, info)
	local keyLabel = KeyRow(kit, content, text, info.action)
	local header = kit.Header(content, L["Wheels on it"], keyLabel, -24)
	local rows = {} -- by key (made as each wheel first shows up)
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

	local function Row(key)
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(320, ROW)
		local check = kit.Check(row, nil, "", nil, function(value)
			SetOnMaster(key, value)
			refreshMaster()
		end)
		check:SetPoint("LEFT", 26, 0)
		check.Refresh = function(self) self:SetChecked(IsOnMaster(key)) end
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", 0, 0)
		row.up, row.down = Arrow(row, "Up"), Arrow(row, "Down")
		row.down:SetPoint("RIGHT", 0, 0)
		row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
		kit.Tooltip(row.up, L["Earlier round the wheel (the first is at the top)."])
		kit.Tooltip(row.down, L["Later round the wheel."])
		row.up:SetScript("OnClick", function() Move(key, -1) end)
		row.down:SetScript("OnClick", function() Move(key, 1) end)
		row.check, row.label = check, check.Text or check.text
		return row
	end

	usual = PanelButton(content)
	usual:SetSize(140, 22)
	usual:SetText(L["Usual order"])
	kit.Tooltip(usual, L["Every wheel back on the master wheel, in their usual order (your own wheels " ..
		"off it)."])
	usual:SetScript("OnClick", function()
		ns.SetMasterWheelOrder(nil)
		refreshMaster()
	end)

	refreshMaster = function()
		local list = ns.MasterWheelOrder()
		local last, listed = header, {}
		for i, item in ipairs(list) do
			local choice = item.choice
			local row = rows[choice.key] or Row(choice.key)
			rows[choice.key] = row
			listed[choice.key] = true
			-- (A wheel of your own may have a new name or icon.)
			row.label:SetText(L[choice.label])
			row.icon:SetTexture(choice.icon)
			if choice.trim then
				row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			else
				row.icon:SetTexCoord(0, 1, 0, 1)
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8 - (i - 1) * ROW)
			row.check:Refresh()
			row.up:SetEnabled(i > 1)
			row.down:SetEnabled(i < #list)
			row:Show()
			last = row
		end
		-- (A wheel of yours that's been deleted.)
		for key, row in pairs(rows) do
			if not listed[key] then
				row:Hide()
			end
		end
		usual:ClearAllPoints()
		usual:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
		preview:ClearAllPoints()
		preview:SetPoint("TOPLEFT", usual, "BOTTOMLEFT", 0, -20)
		preview:SetEntries(info.Entries())
		kit.Refresh() -- (the other pages' "On the master wheel" ticks)
	end
	-- (The wheel's laid out again after a fight if changed in one; its
	-- preview shows the settings meanwhile.)
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

-- A command's box: a few lines' room in a dark well, a click anywhere on it
-- typing there.
local function CommandBox(parent, width)
	local well = CreateFrame("Frame", nil, parent, BACKDROP)
	well:SetSize(width, 38)
	if well.SetBackdrop then
		well:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		well:SetBackdropColor(0, 0, 0, 0.8)
	end
	if ns.SkinWindow then
		ns.SkinWindow(well, true)
	end
	if well.SetClipsChildren then
		well:SetClipsChildren(true) -- (a long command runs on out of sight)
	end
	local box = CreateFrame("EditBox", nil, well)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(width - 12)
	box:SetPoint("TOPLEFT", 6, -5)
	box:SetMaxLetters(1023)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	well:EnableMouse(true)
	well:SetScript("OnMouseDown", function() box:SetFocus() end)
	well.box = box
	return well
end

-- A square icon button: gold edge when it's the one picked.
local function IconTile(parent, size)
	local tile = CreateFrame("Button", nil, parent)
	tile:SetSize(size, size)
	tile.border = tile:CreateTexture(nil, "BACKGROUND")
	tile.border:SetAllPoints()
	tile.border:SetColorTexture(0.45, 0.38, 0.2, 1)
	local bg = tile:CreateTexture(nil, "BORDER")
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.06, 0.05, 0.04, 0.95)
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetPoint("TOPLEFT", 2, -2)
	tile.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local hl = tile:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(tile.icon)
	hl:SetColorTexture(1, 1, 1, 0.15)
	function tile:SetPicked(picked)
		self.border:SetColorTexture(picked and 1 or 0.45, picked and 0.82 or 0.38, picked and 0 or 0.2, 1)
	end
	return tile
end

-- Your wheels: buttons to make a new one (blank or from a template), a row
-- of the ones you've made, and the one picked from it: its name, icon, key
-- and master wheel tick, then a row for each icon on it (its icon, name and
-- command, a Test button, arrows to move it and a delete), and its preview.
-- Changes are saved as you type, and put on the wheel as you leave a box.
local function YourWheelsPage(kit, info)
	local canvas, content = kit.CreateScrollPage(true)
	local text = Top(kit, content, info)
	local MAX, MAX_SLOTS = ns.CUSTOM_WHEEL_MAX, ns.CUSTOM_WHEEL_SLOTS
	local DEFAULT_ICON = ns.CUSTOM_WHEEL_DEFAULT_ICON
	local CoverWith -- (the Test buttons': below)
	local selected -- the wheel being edited
	local dirty    -- changed since it was last put on the wheel
	local RefreshPage

	-- Puts what's changed on the wheel (and its key's name and the master wheel).
	local function Apply()
		if selected and dirty then
			dirty = false
			ns.ApplyCustomWheel(selected)
		end
	end
	local function Select(data)
		Apply()
		selected = data
		RefreshPage()
	end

	-- A button for each template.
	local newButtons, previous = {}, nil
	for _, template in ipairs(ns.CUSTOM_WHEEL_TEMPLATES or {}) do
		local button = PanelButton(content)
		button:SetSize(template.key == "blank" and 120 or 180, 22)
		button:SetText(L[template.button])
		kit.Tooltip(button, L[template.tip])
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
		else
			button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
		end
		button:SetScript("OnClick", function()
			Apply()
			local data = ns.NewCustomWheel(template)
			if data then
				Select(data)
			else
				ns.Print(L["You have %d wheels already: delete one to make another."]:format(MAX))
			end
		end)
		newButtons[#newButtons + 1] = button
		previous = button
	end
	local firstNew = newButtons[1]

	-- The row of your wheels.
	local tiles = {}
	local empty = kit.Label(content, "GameFontDisable", L["You haven't made a wheel yet."])
	empty:SetPoint("TOPLEFT", firstNew, "BOTTOMLEFT", 0, -16)
	local function Tile(i)
		local tile = IconTile(content, TILE)
		tile:SetPoint("TOPLEFT", firstNew, "BOTTOMLEFT", (i - 1) * (TILE + 6), -12)
		tile:SetScript("OnClick", function(self) Select(self.data) end)
		tile:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(self.data.name, 1, 0.82, 0)
			GameTooltip:Show()
		end)
		tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return tile
	end

	-- The wheel picked.
	local editor = CreateFrame("Frame", nil, content)
	editor:SetPoint("TOPLEFT", firstNew, "BOTTOMLEFT", 0, -12 - TILE - 18)
	editor:SetSize(580, 10)

	local picker = kit.IconPicker(canvas, function(key, file)
		if not selected then return end
		if key == 0 then
			selected.icon = file
		elseif selected.slots[key] then
			selected.slots[key].icon = file
		end
		dirty = true
		Apply()
		RefreshPage()
	end)

	local wheelIcon = IconTile(editor, TILE)
	wheelIcon:SetPoint("TOPLEFT", 0, 0)
	kit.Tooltip(wheelIcon, L["The wheel's icon, as it shows on the master wheel. Click to pick another."])
	wheelIcon:SetScript("OnClick", function(self)
		picker:Open(self, 0, selected and selected.icon)
	end)
	local nameLabel = kit.Label(editor, "GameFontHighlight", L["Name"])
	nameLabel:SetPoint("LEFT", wheelIcon, "RIGHT", 12, 0)
	local nameBox = InputBox(editor)
	nameBox:SetSize(200, 22)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(40)
	nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
	kit.Tooltip(nameBox, L["Shown in the wheel's middle, on the master wheel and in the game's key bindings."])
	nameBox:SetScript("OnTextChanged", function(self, userInput)
		local name = self:GetText():match("^%s*(.-)%s*$")
		if userInput and selected and name ~= "" then
			selected.name = name
			dirty = true
		end
	end)
	nameBox:SetScript("OnEnterPressed", nameBox.ClearFocus)
	nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)
	nameBox:SetScript("OnEditFocusLost", function(self)
		Apply()
		if selected then self:SetText(selected.name) end
		RefreshPage()
	end)

	StaticPopupDialogs.CINEMATIC_WHEEL_DELETE = {
		text = L["Delete the wheel %s?"],
		button1 = YES, button2 = NO,
		OnAccept = function(_, data)
			ns.DeleteCustomWheel(data)
			if selected == data then
				selected, dirty = nil, false
			end
			RefreshPage()
			if refreshMaster then refreshMaster() end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	local delete = PanelButton(editor)
	delete:SetSize(120, 22)
	delete:SetText(L["Delete wheel"])
	delete:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -20, -7)
	kit.Tooltip(delete, L["Deletes this wheel, and takes its keys off."])
	delete:SetScript("OnClick", function()
		if selected then
			StaticPopup_Show("CINEMATIC_WHEEL_DELETE", selected.name, nil, selected)
		end
	end)

	local keyLabel, firstKey, secondKey = KeyRow(kit, editor, wheelIcon, "CLICK CinematicCustomWheel1Button:LeftButton",
		-14)
	local onMaster = kit.Check(editor, nil, L["On the master wheel"],
		L["Its icon is on the master wheel, which opens it. Untick to leave it off: its own key still " ..
		"brings it up. The master wheel is the same for all your characters."],
		function(value)
			if not selected then return end
			SetOnMaster("custom" .. selected.pool, value)
			if refreshMaster then refreshMaster() end
		end)
	onMaster:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", -2, -12)
	onMaster.Refresh = function(self)
		self:SetChecked(selected and IsOnMaster("custom" .. selected.pool) or false)
	end

	local header = kit.Header(editor, L["Icons on it"], onMaster, -18)
	header:SetPoint("TOPLEFT", onMaster, "BOTTOMLEFT", 2, -18)
	-- (Column names over the rows.)
	local COLUMNS = { { L["Icon"], 0 }, { L["Name"], 42 }, { L["Command"], 172 } }
	for _, column in ipairs(COLUMNS) do
		local label = kit.Label(editor, "GameFontNormalSmall", column[1])
		label:SetPoint("TOPLEFT", header, "BOTTOMLEFT", column[2], -8)
	end

	-- The Test buttons' secure side: one button of the game's secure kind (a
	-- macro's, like the wheel's), laid over the Test button the cursor's on,
	-- out of a fight. It isn't in the settings window, as a secure button in
	-- it would make the window's frames protected, and they couldn't move or
	-- hide in a fight. It goes as the cursor leaves it (a secure snippet,
	-- so in a fight too).
	local tester = CreateFrame("Button", "CinematicWheelTestButton", UIParent,
		"SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate")
	tester:SetFrameStrata("FULLSCREEN_DIALOG")
	tester:RegisterForClicks("AnyUp")
	tester:SetAttribute("useOnKeyDown", false)
	tester:SetAttribute("type", "macro")
	tester:SetAttribute("_onleave", "self:Hide()")
	tester:Hide()
	tester:HookScript("OnEnter", function(self)
		if self.owner then
			self.owner:LockHighlight()
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Runs its command now, as picking it on the wheel would."], 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	tester:HookScript("OnHide", function(self)
		if self.owner then self.owner:UnlockHighlight() end
		GameTooltip:Hide()
	end)
	function CoverWith(button, slot)
		if InCombatLockdown() then return end
		local scale = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local left, bottom = button:GetLeft(), button:GetBottom()
		if not left then return end
		tester.owner = button
		tester:SetAttribute("macrotext", slot.command or "")
		tester:ClearAllPoints()
		tester:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
		tester:SetSize(button:GetWidth() * scale, button:GetHeight() * scale)
		tester:Show()
	end

	-- Each icon's row (made as needed; i: its place on the wheel).
	local slotRows = {}
	local function MoveSlot(i, by)
		local slots = selected.slots
		if slots[i] and slots[i + by] then
			slots[i], slots[i + by] = slots[i + by], slots[i]
			dirty = true
			Apply()
			RefreshPage()
		end
	end
	local function SlotRow(i)
		local row = CreateFrame("Frame", nil, editor)
		row:SetSize(580, SLOT_ROW)
		row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -26 - (i - 1) * SLOT_ROW)
		local icon = IconTile(row, 32)
		icon:SetPoint("TOPLEFT", 0, 0)
		kit.Tooltip(icon, L["Click to pick its icon."])
		icon:SetScript("OnClick", function(self)
			local slot = selected and selected.slots[i]
			if slot then picker:Open(self, i, slot.icon) end
		end)
		local label = InputBox(row)
		label:SetSize(120, 22)
		label:SetAutoFocus(false)
		label:SetMaxLetters(40)
		label:SetPoint("TOPLEFT", 48, -5)
		kit.Tooltip(label, L["Its name in the wheel's middle as you point at it. Empty: its command's first line."])
		label:SetScript("OnTextChanged", function(self, userInput)
			local slot = selected and selected.slots[i]
			if userInput and slot then
				slot.label = self:GetText()
				dirty = true
			end
		end)
		label:SetScript("OnEnterPressed", label.ClearFocus)
		label:SetScript("OnEscapePressed", label.ClearFocus)
		label:SetScript("OnEditFocusLost", function()
			Apply()
			RefreshPage()
		end)
		local command = CommandBox(row, 250)
		command:SetPoint("TOPLEFT", 172, 0)
		kit.Tooltip(command, L["What picking it does: a slash command, such as /rw Pull in 10, or several, a " ..
			"line each (anything a macro can do). The game cuts a line at 255 letters."])
		command.box:SetScript("OnTextChanged", function(self, userInput)
			local slot = selected and selected.slots[i]
			if userInput and slot then
				slot.command = self:GetText()
				dirty = true
			end
		end)
		command.box:SetScript("OnEditFocusLost", function()
			Apply()
			RefreshPage()
		end)
		-- Test: runs its command now, as a pick would (through the secure
		-- tester laid over it, below).
		local test = PanelButton(row)
		test:SetSize(52, 22)
		test:SetPoint("TOPLEFT", 430, -5)
		test:SetText(L["Test"])
		test:SetScript("OnEnter", function(self)
			local slot = selected and selected.slots[i]
			if slot then CoverWith(self, slot) end
		end)
		row.up, row.down = Arrow(row, "Up"), Arrow(row, "Down")
		row.up:SetPoint("TOPLEFT", 488, -5)
		row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
		row.up:SetScript("OnClick", function() MoveSlot(i, -1) end)
		row.down:SetScript("OnClick", function() MoveSlot(i, 1) end)
		kit.Tooltip(row.up, L["Earlier round the wheel (the first is at the top)."])
		kit.Tooltip(row.down, L["Later round the wheel."])
		local remove = CreateFrame("Button", nil, row)
		remove:SetSize(20, 20)
		remove:SetPoint("LEFT", row.down, "RIGHT", 6, 0)
		remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
		remove:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		kit.Tooltip(remove, L["Takes this icon off the wheel."])
		remove:SetScript("OnClick", function()
			if selected and selected.slots[i] then
				table.remove(selected.slots, i)
				dirty = true
				Apply()
				RefreshPage()
			end
		end)
		row.icon, row.label, row.command, row.test = icon, label, command, test
		row.test:SetEnabled(not InCombatLockdown())
		return row
	end

	local add = PanelButton(editor)
	add:SetSize(120, 22)
	add:SetText(L["Add an icon"])
	kit.Tooltip(add, L["Adds an icon to the wheel, for a command of its own (up to 12)."])
	add:SetScript("OnClick", function()
		if selected and #selected.slots < MAX_SLOTS then
			selected.slots[#selected.slots + 1] = { label = "", icon = DEFAULT_ICON, command = "" }
			dirty = true
			Apply()
			RefreshPage()
		end
	end)

	local preview = Preview(content, "")

	RefreshPage = function()
		local list = ns.CustomWheels()
		local found = false
		for _, data in ipairs(list) do
			found = found or data == selected
		end
		if not found then
			selected, dirty = list[1], false
		end
		for i = 1, math.max(#list, #tiles) do
			local data, tile = list[i], tiles[i]
			if data and not tile then
				tile = Tile(i)
				tiles[i] = tile
			end
			if data then
				tile.data = data
				tile.icon:SetTexture(data.icon or DEFAULT_ICON)
				tile:SetPicked(data == selected)
				tile:Show()
			elseif tile then
				tile:Hide()
			end
		end
		for _, button in ipairs(newButtons) do
			button:SetEnabled(#list < MAX)
		end
		empty:SetShown(#list == 0)
		editor:SetShown(selected ~= nil)
		preview:SetShown(selected ~= nil)
		if selected then
			wheelIcon.icon:SetTexture(selected.icon or DEFAULT_ICON)
			if not nameBox:HasFocus() then
				nameBox:SetText(selected.name)
			end
			local action = ns.CustomWheelAction(selected)
			firstKey.action, secondKey.action = action, action
			kit.RefreshKeybinds()
			onMaster:Refresh()
			local slots = selected.slots
			for i = 1, math.max(#slots, #slotRows) do
				local slot, row = slots[i], slotRows[i]
				if slot and not row then
					row = SlotRow(i)
					slotRows[i] = row
				end
				if slot then
					row.icon.icon:SetTexture(slot.icon or DEFAULT_ICON)
					if not row.label:HasFocus() then
						row.label:SetText(slot.label or "")
					end
					if not row.command.box:HasFocus() then
						row.command.box:SetText(slot.command or "")
					end
					row.test:SetEnabled(not InCombatLockdown())
					row.up:SetEnabled(i > 1)
					row.down:SetEnabled(i < #slots)
					row:Show()
				elseif row then
					row:Hide()
				end
			end
			add:ClearAllPoints()
			add:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -26 - #slots * SLOT_ROW - 4)
			add:SetEnabled(#slots < MAX_SLOTS)
			-- (The editor's height: down to the Add button, for the page's scroll.)
			editor:SetHeight(TILE + 120 + #slots * SLOT_ROW + 30)
			preview:ClearAllPoints()
			preview:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -20)
			preview:SetTitle(selected.name)
			preview:SetEntries(ns.CustomWheelEntries(selected))
		end
		if kit.FitContentHeight then kit.FitContentHeight(content) end
	end
	Finish(kit, canvas, content, info, RefreshPage, function()
		picker:Hide()
		if not InCombatLockdown() then tester:Hide() end
		Apply()
	end)
end

-- (Options.lua, once the language is known, with the helpers it shares.)
function ns.CreateWheelsPanels(kit)
	for _, info in ipairs(WHEELS) do
		if info.key == "master" then
			MasterPage(kit, info)
		elseif info.key == "yours" then
			YourWheelsPage(kit, info)
		elseif info.key ~= "world" or ns.hasWorldMarkerWheel then
			WheelPage(kit, info)
		end
	end
end
