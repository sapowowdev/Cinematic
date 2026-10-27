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
-- extras: the player can put icons of their own on it (MarkerWheel.lua).
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
	{ key = "marker", label = "Marker wheel", action = "CLICK CinematicMarkerWheelButton:LeftButton", extras = true,
		Entries = function() return SlotsOf("marker") end },
	{ key = "world", label = "Ground marker wheel", action = "CLICK CinematicWorldMarkerWheelButton:LeftButton",
		extras = true, Entries = function() return SlotsOf("world") end },
	{ key = "vision", label = "Vision wheel", action = "CLICK CinematicVisionWheelButton:LeftButton", extras = true,
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

-- The Test buttons' secure side: one button of the game's secure kind (a
-- macro's, like the wheels'), laid over the Test button the cursor's on, out
-- of a fight. It isn't in the settings window, as a secure button in it
-- would make the window's frames protected, and they couldn't move or hide
-- in a fight. It goes as the cursor leaves it (a secure snippet, so in a
-- fight too). Made with the first page that has Test buttons.
local tester
local function CoverWith(button, command)
	if not tester then
		tester = CreateFrame("Button", "CinematicWheelTestButton", UIParent,
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
	end
	if InCombatLockdown() then return end
	local scale = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, bottom = button:GetLeft(), button:GetBottom()
	if not left then return end
	tester.owner = button
	tester:SetAttribute("macrotext", command or "")
	tester:ClearAllPoints()
	tester:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
	tester:SetSize(button:GetWidth() * scale, button:GetHeight() * scale)
	tester:Show()
end
local function HideTester()
	if tester and not InCombatLockdown() then tester:Hide() end
end

-- The icon picker: every icon the game has, and a box to find one by name
-- (IconBrowser.lua). onPick(key, file).
local function SearchPicker(_, canvas, onPick)
	return ns.IconBrowser(canvas, onPick)
end

-- The rows of a wheel's icons, each its icon, name and command, a Test
-- button, arrows to move it and a delete, then Add an icon. Under anchor
-- (column names first). hooks: Slots() (the list, live: made if need be),
-- Max() (how many it can have), Edited() (typed in: saved, not on the wheel
-- yet), Commit() (put on the wheel, and the page laid out again). The page's
-- picker calls editor:SetIcon(i, file) for slot i.
local function SlotEditor(kit, parent, anchor, picker, hooks)
	local editor = { rows = {} }
	local COLUMNS = { { L["Icon"], 0 }, { L["Name"], 48 }, { L["Command"], 172 } }
	for _, column in ipairs(COLUMNS) do
		local label = kit.Label(parent, "GameFontNormalSmall", column[1])
		label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", column[2], -8)
	end

	local function Slot(i)
		return hooks.Slots()[i]
	end
	local function Move(i, by)
		local slots = hooks.Slots()
		if slots[i] and slots[i + by] then
			slots[i], slots[i + by] = slots[i + by], slots[i]
			hooks.Commit()
		end
	end

	local function Row(i)
		local row = CreateFrame("Frame", nil, parent)
		row:SetSize(580, SLOT_ROW)
		row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -26 - (i - 1) * SLOT_ROW)
		local icon = IconTile(row, 32)
		icon:SetPoint("TOPLEFT", 0, 0)
		kit.Tooltip(icon, L["Click to pick its icon."])
		icon:SetScript("OnClick", function(self)
			local slot = Slot(i)
			if slot then picker:Open(self, i, slot.icon) end
		end)
		local label = InputBox(row)
		label:SetSize(120, 22)
		label:SetAutoFocus(false)
		label:SetMaxLetters(40)
		label:SetPoint("TOPLEFT", 48, -5)
		kit.Tooltip(label, L["Its name in the wheel's middle as you point at it. Empty: its command's first line."])
		label:SetScript("OnTextChanged", function(self, userInput)
			local slot = Slot(i)
			if userInput and slot then
				slot.label = self:GetText()
				hooks.Edited()
			end
		end)
		label:SetScript("OnEnterPressed", label.ClearFocus)
		label:SetScript("OnEscapePressed", label.ClearFocus)
		label:SetScript("OnEditFocusLost", hooks.Commit)
		local command = CommandBox(row, 250)
		command:SetPoint("TOPLEFT", 172, 0)
		kit.Tooltip(command, L["What picking it does: a slash command, such as /rw Pull in 10, or several, a " ..
			"line each (anything a macro can do). The game cuts a line at 255 letters."])
		command.box:SetScript("OnTextChanged", function(self, userInput)
			local slot = Slot(i)
			if userInput and slot then
				slot.command = self:GetText()
				hooks.Edited()
			end
		end)
		command.box:SetScript("OnEditFocusLost", hooks.Commit)
		-- Test: runs its command now, as a pick would (through the tester above).
		local test = PanelButton(row)
		test:SetSize(52, 22)
		test:SetPoint("TOPLEFT", 430, -5)
		test:SetText(L["Test"])
		test:HookScript("OnEnter", function(self)
			local slot = Slot(i)
			if slot then CoverWith(self, slot.command) end
		end)
		row.up, row.down = Arrow(row, "Up"), Arrow(row, "Down")
		row.up:SetPoint("TOPLEFT", 488, -5)
		row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
		row.up:SetScript("OnClick", function() Move(i, -1) end)
		row.down:SetScript("OnClick", function() Move(i, 1) end)
		kit.Tooltip(row.up, L["Earlier round the wheel (the first is at the top)."])
		kit.Tooltip(row.down, L["Later round the wheel."])
		local remove = CreateFrame("Button", nil, row)
		remove:SetSize(20, 20)
		remove:SetPoint("LEFT", row.down, "RIGHT", 6, 0)
		remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
		remove:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		kit.Tooltip(remove, L["Takes this icon off the wheel."])
		remove:SetScript("OnClick", function()
			local slots = hooks.Slots()
			if slots[i] then
				table.remove(slots, i)
				hooks.Commit()
			end
		end)
		row.icon, row.label, row.command, row.test = icon, label, command, test
		return row
	end

	local add = PanelButton(parent)
	add:SetSize(120, 22)
	add:SetText(L["Add an icon"])
	kit.Tooltip(add, L["Adds an icon to the wheel, for a command of its own."])
	add:SetScript("OnClick", function()
		local slots = hooks.Slots()
		if #slots < hooks.Max() then
			slots[#slots + 1] = { label = "", icon = ns.CUSTOM_WHEEL_DEFAULT_ICON, command = "" }
			hooks.Commit()
		end
	end)
	editor.add = add

	function editor:SetIcon(i, file)
		local slot = Slot(i)
		if slot then
			slot.icon = file
			hooks.Commit()
		end
	end

	-- Lays the rows out for the list as it is now.
	function editor:Refresh()
		local slots = hooks.Slots()
		local rows = self.rows
		for i = 1, math.max(#slots, #rows) do
			local slot, row = slots[i], rows[i]
			if slot and not row then
				row = Row(i)
				rows[i] = row
			end
			if slot then
				row.icon.icon:SetTexture(slot.icon or ns.CUSTOM_WHEEL_DEFAULT_ICON)
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
		add:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -26 - #slots * SLOT_ROW - 4)
		add:SetEnabled(#slots < hooks.Max())
		return #slots
	end
	return editor
end

-- The window for sharing a wheel: Export shows its text to copy; Import
-- takes one pasted, shows its name and every command on it to read, and
-- Add wheel makes it one of yours (onAdded(wheel) after).
local share
local function ShareWindow()
	if share then return share end
	share = CreateFrame("Frame", "CinematicWheelShareWindow", UIParent, BACKDROP)
	share:SetSize(500, 440)
	share:SetPoint("CENTER")
	share:SetFrameStrata("FULLSCREEN_DIALOG")
	share:SetToplevel(true)
	share:EnableMouse(true)
	share:SetMovable(true)
	share:RegisterForDrag("LeftButton")
	share:SetScript("OnDragStart", share.StartMoving)
	share:SetScript("OnDragStop", share.StopMovingOrSizing)
	if share.SetBackdrop then
		share:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
	end
	if ns.SkinWindow then ns.SkinWindow(share) end
	tinsert(UISpecialFrames, "CinematicWheelShareWindow") -- (Escape closes it)
	share:Hide()

	share.title = share:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	share.title:SetPoint("TOPLEFT", 16, -14)
	local close = CreateFrame("Button", nil, share, "UIPanelCloseButton")
	if ns.SkinClose then ns.SkinClose(close) end
	close:SetPoint("TOPRIGHT", -2, -2)
	share.hint = share:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	share.hint:SetPoint("TOPLEFT", share.title, "BOTTOMLEFT", 0, -8)
	share.hint:SetWidth(468)
	share.hint:SetJustifyH("LEFT")

	-- A dark well with a scroll bar, for the text or the review.
	local function Well(height)
		local holder = CreateFrame("Frame", nil, share, BACKDROP)
		holder:SetPoint("LEFT", 14, 0)
		holder:SetPoint("RIGHT", -14, 0)
		holder:SetHeight(height)
		if holder.SetBackdrop then
			holder:SetBackdrop({
				bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			holder:SetBackdropColor(0, 0, 0, 0.6)
		end
		if ns.SkinWindow then ns.SkinWindow(holder, true) end
		local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
		if ns.SkinScroll then ns.SkinScroll(scroll) end
		scroll:SetPoint("TOPLEFT", 8, -6)
		scroll:SetPoint("BOTTOMRIGHT", -28, 6)
		holder.scroll = scroll
		return holder
	end

	local textWell = Well(90)
	textWell:SetPoint("TOP", share, "TOP", 0, -76)
	local box = CreateFrame("EditBox", nil, textWell.scroll)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(430)
	textWell.scroll:SetScrollChild(box)
	box:SetScript("OnEscapePressed", function() share:Hide() end)
	share.box = box

	local reviewWell = Well(200)
	reviewWell:SetPoint("TOP", textWell, "BOTTOM", 0, -10)
	local reviewHolder = CreateFrame("Frame", nil, reviewWell.scroll)
	reviewHolder:SetSize(430, 10)
	reviewWell.scroll:SetScrollChild(reviewHolder)
	local review = reviewHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	review:SetPoint("TOPLEFT")
	review:SetWidth(430)
	review:SetJustifyH("LEFT")
	review:SetSpacing(3)
	share.reviewWell = reviewWell

	local accept = PanelButton(share)
	accept:SetSize(120, 22)
	accept:SetPoint("BOTTOMRIGHT", -16, 14)
	accept:SetText(L["Add wheel"])
	local selectAll = PanelButton(share)
	selectAll:SetSize(120, 22)
	selectAll:SetPoint("BOTTOMRIGHT", -16, 14)
	selectAll:SetText(L["Select all"])
	selectAll:SetScript("OnClick", function()
		box:SetFocus()
		box:HighlightText()
	end)
	share.accept, share.selectAll = accept, selectAll

	-- What's pasted, read: shown for review, or why it can't be added.
	local WHY = {
		empty = "",
		newer = "This wheel is from a newer Cinematic: update it to add this one.",
		profile = "That's a profile, not a wheel: import it on the Profiles page.",
		broken = "That isn't a whole wheel: copy it again, all of it.",
	}
	local function Safe(text)
		return (tostring(text or ""):gsub("|", "||"))
	end
	local function UpdateImport()
		local info, why = ns.ReadSharedWheel(box:GetText())
		share.info = info
		accept:SetEnabled(info ~= nil)
		if not info then
			review:SetText(why and WHY[why] and L[WHY[why]] or "")
		else
			local lines = {
				"|cffff6659" .. L["Read every command before you add it: each runs as if you'd typed it, " ..
					"and /run ones can do anything an addon can."] .. "|r",
				"",
				"|cffffd100" .. Safe(info.name) .. "|r" .. (info.from and (" (" .. L["from %s"]:format(Safe(info.from)) .. ")") or ""),
			}
			if #info.slots == 0 then
				lines[#lines + 1] = L["Nothing on it yet"]
			end
			for i, slot in ipairs(info.slots) do
				local name = slot.label ~= "" and slot.label or L["(no name)"]
				lines[#lines + 1] = ("|cffffd100%d. %s|r"):format(i, Safe(name))
				for line in ((slot.command ~= "" and slot.command or L["(no command)"]) .. "\n"):gmatch("(.-)\n") do
					lines[#lines + 1] = "    " .. Safe(line)
				end
			end
			review:SetText(table.concat(lines, "\n"))
		end
		reviewHolder:SetHeight(review:GetStringHeight() + 4)
	end
	box:SetScript("OnTextChanged", function(self, userInput)
		if share.mode == "export" then
			-- (Read-only: any typing puts the text back.)
			if userInput then
				self:SetText(share.text)
				self:HighlightText()
			end
		else
			UpdateImport()
		end
	end)
	accept:SetScript("OnClick", function()
		if not share.info then return end
		local data = ns.AddSharedWheel(share.info)
		if not data then
			ns.Print(L["You have %d wheels already: delete one to make another."]:format(ns.CUSTOM_WHEEL_MAX))
			return
		end
		share:Hide()
		if share.onAdded then share.onAdded(data) end
	end)
	return share
end

local function ShowExport(data)
	local window = ShareWindow()
	window.mode = "export"
	window.text = ns.ExportWheel(data)
	window.title:SetText(L["Share %s"]:format(data.name))
	window.hint:SetText(L["Press Ctrl+C to copy this, then paste it wherever your friends will see it. They add " ..
		"it with Import a wheel on their Your wheels page."])
	window.reviewWell:Hide()
	window.accept:Hide()
	window.selectAll:Show()
	window:Show()
	window.box:SetText(window.text)
	window.box:SetFocus()
	window.box:HighlightText()
end

local function ShowImport(onAdded)
	local window = ShareWindow()
	window.mode = "import"
	window.onAdded = onAdded
	window.title:SetText(L["Import a wheel"])
	window.hint:SetText(L["Paste in a wheel someone shared (Ctrl+V), read what's on it below, and Add wheel. " ..
		"It's added as a new wheel of yours."])
	window.reviewWell:Show()
	window.accept:Show()
	window.selectAll:Hide()
	window:Show()
	window.box:SetText("")
	window.box:SetFocus()
end

-- A built-in wheel's page; on the marker, ground marker and vision wheels'
-- (info.extras), a section for icons of the player's own on it too.
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
	local RefreshPage, editor, picker
	local dirty

	if info.extras then
		local header = kit.Header(content, L["Your icons on it"], onMaster, -18)
		header:SetPoint("TOPLEFT", onMaster, "BOTTOMLEFT", 2, -18)
		local note = kit.Label(content, "GameFontHighlightSmall", "")
		note:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
		note:SetWidth(560)
		local function Commit()
			dirty = false
			ns.ApplyWheelExtras(info.key)
			RefreshPage()
		end
		picker = SearchPicker(kit, canvas, function(key, file)
			editor:SetIcon(key, file)
		end)
		editor = SlotEditor(kit, content, note, picker, {
			Slots = function() return ns.WheelExtras(info.key, true) end,
			Max = function() return ns.WheelExtrasRoom(info.key) end,
			Edited = function() dirty = true end,
			Commit = Commit,
		})
		RefreshPage = function()
			note:SetText(L["Icons of your own, after the wheel's own: each runs a command, as on your own " ..
				"wheels. Room for %d. The same for all your characters."]:format(ns.WheelExtrasRoom(info.key)))
			editor:Refresh()
			preview:ClearAllPoints()
			preview:SetPoint("TOPLEFT", editor.add, "BOTTOMLEFT", 0, -20)
			preview:SetEntries(info.Entries())
			if kit.FitContentHeight then kit.FitContentHeight(content) end
		end
	else
		preview:SetPoint("TOPLEFT", onMaster, "BOTTOMLEFT", 2, -16)
		RefreshPage = function()
			preview:SetEntries(info.Entries())
		end
	end
	Finish(kit, canvas, content, info, RefreshPage, function()
		if picker then picker:Hide() end
		HideTester()
		if dirty then
			dirty = false
			ns.ApplyWheelExtras(info.key)
		end
	end)
end

-- Your wheels: New wheel and Import a wheel, a row of the ones you've made,
-- and the one picked from it: its name, icon, key, master wheel tick, Share
-- and Delete, then a row for each icon on it, and its preview. Changes are
-- saved as you type, and put on the wheel as you leave a box.
local function YourWheelsPage(kit, info)
	local canvas, content = kit.CreateScrollPage(true)
	local text = Top(kit, content, info)
	local MAX, MAX_SLOTS = ns.CUSTOM_WHEEL_MAX, ns.CUSTOM_WHEEL_SLOTS
	local DEFAULT_ICON = ns.CUSTOM_WHEEL_DEFAULT_ICON
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

	-- A button for each template, then Import a wheel.
	local newButtons, previous = {}, nil
	local function TopButton(label, tip, width, onClick)
		local button = PanelButton(content)
		button:SetSize(width, 22)
		button:SetText(label)
		kit.Tooltip(button, tip)
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
		else
			button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
		end
		button:SetScript("OnClick", onClick)
		newButtons[#newButtons + 1] = button
		previous = button
		return button
	end
	for _, template in ipairs(ns.CUSTOM_WHEEL_TEMPLATES or {}) do
		TopButton(L[template.button], L[template.tip], 120, function()
			Apply()
			local data = ns.NewCustomWheel(template)
			if data then
				Select(data)
			else
				ns.Print(L["You have %d wheels already: delete one to make another."]:format(MAX))
			end
		end)
	end
	TopButton(L["Import a wheel"], L["Add a wheel someone shared with you: paste in its text, and read " ..
		"what's on it before you add it."], 140, function()
		Apply()
		ShowImport(Select)
	end)
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
	local editorFrame = CreateFrame("Frame", nil, content)
	editorFrame:SetPoint("TOPLEFT", firstNew, "BOTTOMLEFT", 0, -12 - TILE - 18)
	editorFrame:SetSize(580, 10)

	local slotEditor
	local picker = SearchPicker(kit, canvas, function(key, file)
		if not selected then return end
		if key == 0 then
			selected.icon = file
			dirty = true
			Apply()
			RefreshPage()
		else
			slotEditor:SetIcon(key, file)
		end
	end)

	local wheelIcon = IconTile(editorFrame, TILE)
	wheelIcon:SetPoint("TOPLEFT", 0, 0)
	kit.Tooltip(wheelIcon, L["The wheel's icon, as it shows on the master wheel. Click to pick another."])
	wheelIcon:SetScript("OnClick", function(self)
		picker:Open(self, 0, selected and selected.icon)
	end)
	local nameLabel = kit.Label(editorFrame, "GameFontHighlight", L["Name"])
	nameLabel:SetPoint("LEFT", wheelIcon, "RIGHT", 12, 0)
	local nameBox = InputBox(editorFrame)
	nameBox:SetSize(180, 22)
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
	local delete = PanelButton(editorFrame)
	delete:SetSize(100, 22)
	delete:SetText(L["Delete wheel"])
	delete:SetPoint("TOPRIGHT", editorFrame, "TOPRIGHT", -20, -7)
	kit.Tooltip(delete, L["Deletes this wheel, and takes its keys off."])
	delete:SetScript("OnClick", function()
		if selected then
			StaticPopup_Show("CINEMATIC_WHEEL_DELETE", selected.name, nil, selected)
		end
	end)
	local shareButton = PanelButton(editorFrame)
	shareButton:SetSize(100, 22)
	shareButton:SetText(L["Share wheel"])
	shareButton:SetPoint("RIGHT", delete, "LEFT", -8, 0)
	kit.Tooltip(shareButton, L["A line of text to copy and paste to friends, who add it with Import a wheel."])
	shareButton:SetScript("OnClick", function()
		Apply()
		if selected then ShowExport(selected) end
	end)

	local keyLabel, firstKey, secondKey = KeyRow(kit, editorFrame, wheelIcon,
		"CLICK CinematicCustomWheel1Button:LeftButton", -14)
	local onMaster = kit.Check(editorFrame, nil, L["On the master wheel"],
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

	local header = kit.Header(editorFrame, L["Icons on it"], onMaster, -18)
	header:SetPoint("TOPLEFT", onMaster, "BOTTOMLEFT", 2, -18)
	slotEditor = SlotEditor(kit, editorFrame, header, picker, {
		Slots = function() return selected and selected.slots or {} end,
		Max = function() return MAX_SLOTS end,
		Edited = function() dirty = true end,
		Commit = function()
			dirty = true
			Apply()
			RefreshPage()
		end,
	})

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
		editorFrame:SetShown(selected ~= nil)
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
			local count = slotEditor:Refresh()
			-- (The editor's height: down to Add an icon, for the page's scroll.)
			editorFrame:SetHeight(TILE + 120 + count * SLOT_ROW + 30)
			preview:ClearAllPoints()
			preview:SetPoint("TOPLEFT", slotEditor.add, "BOTTOMLEFT", 0, -20)
			preview:SetTitle(selected.name)
			preview:SetEntries(ns.CustomWheelEntries(selected))
		end
		if kit.FitContentHeight then kit.FitContentHeight(content) end
	end
	Finish(kit, canvas, content, info, RefreshPage, function()
		picker:Hide()
		HideTester()
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
