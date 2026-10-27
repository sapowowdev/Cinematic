-- The dev build's Profiles demo page: the Profiles page done the modular way,
-- to see how it looks before the real one changes. A profile is where you
-- start from; under it, each part (a profile slot, ProfileSlots.lua) has its
-- choices (ns.SLOT_CHOICES, ProfileChoices.lua), the live one lit, and picking
-- another changes just that part (ns.ApplyPart: on a built-in, first a
-- profile of your own). Wired in: it really switches. Drawn flat, as the
-- welcome demo is. Options.lua calls ns.CreateProfilesDemo (dev build only).
-- (To scrap it: delete this file, its line in CinematicDev.toc and its call
-- in Options.lua.)

local _, ns = ...

local WIDTH = 600
local LABEL_W = 130
local CARD_W, CARD_H, PER_ROW = 92, 74, 6

function ns.CreateProfilesDemo(kit)
	local ui = ns.DemoUI
	local Flat, Text, Color, Rounded = ui.Flat, ui.Text, ui.Color, ui.Rounded
	local canvas, content = kit.CreateScrollPage(true)

	local title = kit.Label(content, "GameFontNormalLarge", "|cffff4040DEV ONLY|r Profiles (new)")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = Text(content, "GameFontHighlight", "Your setup is made of parts. Pick a profile to start " ..
		"from, then change any part on its own: the rest stays as it is. Changing a part of a built-in " ..
		"profile starts one of your own, " .. ns.OWN_PROFILE .. ", so the built-in stays as it was.", ui.SOFT, WIDTH)
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

	local Refresh -- (below)

	-- Profiles: a card each, the active one gold.
	local profilesHead = Text(content, "GameFontNormalLarge", "Start from", ui.GOLD)
	profilesHead:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -18)
	local grid = CreateFrame("Frame", nil, content)
	grid:SetPoint("TOPLEFT", profilesHead, "BOTTOMLEFT", 0, -10)
	grid:SetSize(WIDTH, CARD_H)
	local cards = {}
	local function Card(i)
		if cards[i] then return cards[i] end
		local card = CreateFrame("Button", nil, grid, BackdropTemplateMixin and "BackdropTemplate")
		card:SetSize(CARD_W, CARD_H)
		Flat(card)
		card.icon = card:CreateTexture(nil, "ARTWORK")
		card.icon:SetSize(34, 34)
		card.icon:SetPoint("TOP", 0, -10)
		card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		Rounded(card, card.icon)
		card.label = Text(card, "GameFontHighlightSmall", "", ui.SOFT, CARD_W - 8)
		card.label:SetJustifyH("CENTER")
		card.label:SetWordWrap(false)
		card.label:SetPoint("TOP", card.icon, "BOTTOM", 0, -6)
		card:SetScript("OnEnter", function(self)
			if not self.active then self:SetBackdropBorderColor(unpack(ui.LIT)) end
		end)
		card:SetScript("OnLeave", function(self)
			if not self.active then self:SetBackdropBorderColor(unpack(ui.EDGE)) end
		end)
		card:SetScript("OnClick", function(self)
			if self.active then return end
			if not ns.db.enabled then ns.SetEnabled(true) end
			ns.SetProfile(self.name)
			ns.PreviewProfile(self.name)
			Refresh()
		end)
		cards[i] = card
		return card
	end

	local using = Text(content, "GameFontHighlight", "", ui.WHITE, WIDTH)
	using:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -12)
	local note = Text(content, "GameFontHighlightSmall", "", ui.DIM, WIDTH)
	note:SetPoint("TOPLEFT", using, "BOTTOMLEFT", 0, -4)

	-- Parts: a row each, its choices as chips (laid out on each refresh: the
	-- Edit Mode layouts come and go), the live one gold, and a line under them
	-- saying what the hovered (or live) one does.
	-- Managing profiles, as on the Profiles page (its popups, Share.lua's
	-- windows): buttons that light up on hover, dimmed when they can't be
	-- used on this profile (a built-in can't be renamed, only reset), and a
	-- line under them saying what the hovered one does.
	local manage = CreateFrame("Frame", nil, content)
	manage:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)
	manage:SetSize(WIDTH, 24 * 2 + 8 + 8 + 14)
	local manageLine = Text(manage, "GameFontHighlightSmall", "", ui.DIM, WIDTH)
	manageLine:SetPoint("BOTTOMLEFT")
	local actions = {}
	local function Action(text, tip, onClick)
		local b = CreateFrame("Button", nil, manage, BackdropTemplateMixin and "BackdropTemplate")
		Flat(b)
		b.text = Text(b, "GameFontHighlightSmall", text, ui.SOFT)
		b.text:SetPoint("CENTER")
		b:SetSize(b.text:GetStringWidth() + 28, 24)
		b.on = true
		b:SetScript("OnEnter", function(self)
			if self.on then
				self:SetBackdropBorderColor(unpack(ui.LIT))
				Color(self.text, ui.WHITE)
			end
			manageLine:SetText(tip)
		end)
		b:SetScript("OnLeave", function(self)
			if self.on then
				self:SetBackdropBorderColor(unpack(ui.EDGE))
				Color(self.text, ui.SOFT)
			end
			manageLine:SetText("")
		end)
		b:SetScript("OnClick", function(self) if self.on then onClick() end end)
		function b:SetOn(on)
			self.on = on
			Color(self.text, on and ui.SOFT or { 0.35, 0.35, 0.37 })
			self:SetBackdropBorderColor(unpack(ui.EDGE))
		end
		actions[#actions + 1] = b
		return b
	end
	local function Active() return ns.ActiveProfile() end
	local new = Action("New", "A profile of your own, starting from your current settings.", function()
		StaticPopup_Show("CINEMATIC_PROFILE_NEW")
	end)
	local rename = Action("Rename", "Rename this profile (your own ones only).", function()
		StaticPopup_Show("CINEMATIC_PROFILE_RENAME", nil, nil, Active())
	end)
	local describe = Action("Description", "Say what this profile is for (your own ones only).", function()
		StaticPopup_Show("CINEMATIC_PROFILE_NOTE", nil, nil, Active())
	end)
	local delete = Action("Delete", "Delete this profile (your own ones only).", function()
		StaticPopup_Show("CINEMATIC_PROFILE_DELETE", Active(), nil, Active())
	end)
	local reset = Action("Reset", "Put this built-in profile back to its own settings.", function()
		StaticPopup_Show("CINEMATIC_PROFILE_RESET", ns.ProfileLabel(Active()))
	end)
	local export = Action("Share", "This profile as a line of text to give friends (your own ones only).", function()
		ns.ShowExport()
	end)
	local import = Action("Import", "Add a profile someone shared with you, from their text.", function()
		ns.ShowImport()
	end)
	-- (A toggle: gold while this character has a profile of its own.)
	local perChar = Action("Just this character", "On: this character keeps its own profile, whatever " ..
		"your other characters use. Off: it uses the same one as the rest.", function()
		ns.SetCharacterProfile(not ns.IsCharacterProfile())
		Refresh()
	end)
	new:SetPoint("TOPLEFT")
	for i, b in ipairs({ rename, describe, delete, reset }) do
		b:SetPoint("LEFT", i == 1 and new or actions[i], "RIGHT", 6, 0)
	end
	export:SetPoint("TOPLEFT", new, "BOTTOMLEFT", 0, -8)
	import:SetPoint("LEFT", export, "RIGHT", 6, 0)
	perChar:SetPoint("LEFT", import, "RIGHT", 18, 0)
	local function UpdateActions()
		local active = ns.ProfileChosen() and Active()
		local own = active and not ns.IsBuiltinProfile(active)
		rename:SetOn(own)
		describe:SetOn(own)
		delete:SetOn(own)
		reset:SetOn(active and not own)
		export:SetOn(own)
		local mine = ns.IsCharacterProfile()
		perChar:SetBackdropBorderColor(unpack(mine and ui.GOLD or ui.EDGE))
		Color(perChar.text, mine and ui.WHITE or ui.SOFT)
	end
	perChar:HookScript("OnLeave", UpdateActions)

	local partsHead = Text(content, "GameFontNormalLarge", "Your parts", ui.GOLD)
	partsHead:SetPoint("TOPLEFT", manage, "BOTTOMLEFT", 0, -20)
	local CHIPS_W = WIDTH - LABEL_W - 12
	local rows = {}

	-- The Layout row: every Edit Mode layout the profile can put you on (as
	-- the Profiles page's dropdown lists them, ns.LayoutChoices), not parts.
	local function LayoutChoices()
		local list = {}
		for _, choice in ipairs(ns.LayoutChoices and ns.LayoutChoices() or {}) do
			local line = choice.value == "" and "Cinematic leaves your Edit Mode layout as it is."
				or choice.value == ns.LAYOUT_PRESET and "The game's own layout, Modern or Classic."
				or ("Puts you on the Edit Mode layout " .. choice.text .. ".")
			list[#list + 1] = { value = choice.value, label = choice.text, line = line }
		end
		return list
	end
	local function IsLive(row, choice)
		if row.slot == "layout" then return (ns.db.editModeLayout or "") == choice.value end
		return ns.SlotPartMatches(row.slot, choice.part)
	end
	local function Pick(row, choice)
		if not ns.db.enabled then ns.SetEnabled(true) end
		if row.slot == "layout" then
			ns.EnsureOwnProfile(ns.OWN_PROFILE)
			ns.db.editModeLayout = choice.value
			ns.SaveProfile()
			ns.SwitchProfileLayout()
		else
			ns.ApplyPart(row.slot, choice.part, ns.OWN_PROFILE)
		end
	end

	local function Chip(row, i)
		if row.chips[i] then return row.chips[i] end
		local chip = CreateFrame("Button", nil, row, BackdropTemplateMixin and "BackdropTemplate")
		Flat(chip)
		chip.text = Text(chip, "GameFontHighlightSmall", "", ui.SOFT)
		chip.text:SetPoint("CENTER")
		chip:SetScript("OnEnter", function(self)
			if not self.active then
				self:SetBackdropBorderColor(unpack(ui.LIT))
				Color(self.text, ui.WHITE)
			end
			row.line:SetText(self.choice.line)
		end)
		chip:SetScript("OnLeave", function(self)
			if not self.active then
				self:SetBackdropBorderColor(unpack(ui.EDGE))
				Color(self.text, ui.SOFT)
			end
			row.line:SetText(row.liveLine)
		end)
		chip:SetScript("OnClick", function(self)
			if self.active then return end
			Pick(row, self.choice)
			Refresh()
		end)
		row.chips[i] = chip
		return chip
	end

	local last = partsHead
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		local info = ns.SLOT_CHOICES[slot.key]
		local isLayout = slot.key == "layout" and ns.LayoutChoices and C_EditMode and C_EditMode.GetLayouts
		if info and (isLayout or ns.SlotChoices(slot.key)) then
			local row = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate")
			row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, last == partsHead and -10 or -8)
			row:SetSize(WIDTH, 64)
			Flat(row, ui.BG)
			local name = Text(row, "GameFontHighlight", isLayout and "Edit Mode layout" or info.label, ui.WHITE,
				LABEL_W - 16)
			name:SetPoint("TOPLEFT", 12, -12)
			-- (its options page, for everything the choices don't cover)
			local link = CreateFrame("Button", nil, row)
			local linkText = Text(link, "GameFontHighlightSmall", "Settings  >", ui.DIM)
			linkText:SetPoint("LEFT")
			link:SetSize(linkText:GetStringWidth() + 4, 16)
			link:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
			link:SetScript("OnEnter", function() Color(linkText, ui.WHITE) end)
			link:SetScript("OnLeave", function() Color(linkText, ui.DIM) end)
			link:SetScript("OnClick", function() ns.OpenOptions(info.page) end)
			row.chips, row.slot = {}, slot.key
			row.line = Text(row, "GameFontHighlightSmall", "", ui.SOFT, CHIPS_W)
			row.Choices = isLayout and LayoutChoices or function() return ns.SlotChoices(slot.key) or {} end
			rows[#rows + 1] = row
			last = row
		end
	end

	function Refresh()
		-- The profile cards, wrapped in rows.
		local active = ns.ActiveProfile()
		local names = ns.ProfileNames()
		for i, name in ipairs(names) do
			local card = Card(i)
			card.name = name
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", ((i - 1) % PER_ROW) * (CARD_W + 8), -math.floor((i - 1) / PER_ROW) * (CARD_H + 8))
			card.icon:SetTexture(ns.ProfileIcon(name))
			card.label:SetText(ns.ProfileLabel(name))
			card.active = ns.ProfileChosen() and name == active
			card:SetBackdropBorderColor(unpack(card.active and ui.GOLD or ui.EDGE))
			Color(card.label, card.active and ui.WHITE or ui.SOFT)
			card:Show()
		end
		for i = #names + 1, #cards do cards[i]:Hide() end
		grid:SetHeight(math.ceil(#names / PER_ROW) * (CARD_H + 8) - 8)

		if ns.ProfileChosen() then
			using:SetText("Using |cffffd100" .. ns.ProfileLabel(active) .. "|r"
				.. (ns.IsBuiltinProfile(active) and "  (built-in)" or "  (your own)"))
		else
			using:SetText("No profile picked yet: Cinematic is off until you pick one.")
		end
		note:SetText(ns.IsBuiltinProfile(active) and "" or (ns.ProfileNote(active) or ""))
		UpdateActions()

		-- Each part's chips, wrapped, and its live choice: the first that the
		-- live settings match.
		for _, row in ipairs(rows) do
			local choices, found = row.Choices(), nil
			local x, y = 0, 0
			for i, choice in ipairs(choices) do
				local chip = Chip(row, i)
				chip.choice = choice
				chip.text:SetText(choice.label)
				local w = chip.text:GetStringWidth() + 24
				if x > 0 and x + w > CHIPS_W then x, y = 0, y + 30 end
				chip:SetSize(w, 24)
				chip:ClearAllPoints()
				chip:SetPoint("TOPLEFT", LABEL_W + x, -10 - y)
				x = x + w + 6
				chip.active = not found and IsLive(row, choice)
				if chip.active then found = chip end
				chip:SetBackdropBorderColor(unpack(chip.active and ui.GOLD or ui.EDGE))
				Color(chip.text, chip.active and ui.WHITE or ui.SOFT)
				chip:Show()
			end
			for i = #choices + 1, #row.chips do row.chips[i]:Hide() end
			row.line:ClearAllPoints()
			row.line:SetPoint("TOPLEFT", LABEL_W, -10 - y - 24 - 8)
			row:SetHeight(math.max(64, 10 + y + 24 + 8 + 14 + 12))
			row.liveLine = found and found.choice.line
				or "|cff808080A mix of its own: changed on its settings page.|r"
			row.line:SetText(row.liveLine)
		end
	end

	-- (A demo: an error here goes to chat, so the page doesn't just stay half drawn.)
	local function SafeRefresh()
		local ok, err = pcall(Refresh)
		if not ok then ns.Print("Profiles demo: " .. tostring(err)) end
	end
	-- Drawn once each time the page comes on screen. (Not from OnShow: Settings
	-- puts a page that was never hidden straight into its shown window, so
	-- the first time there's no OnShow. A child's OnUpdate runs only while
	-- it's on screen.)
	local Shown = kit.PageShown(SafeRefresh, content)
	local pending = true
	local watcher = CreateFrame("Frame", nil, canvas)
	-- (Also when the profiles change from elsewhere: a popup's New, Rename or
	-- Delete, an import, Edit Mode picking a layout.)
	local function State()
		local n = 0
		for _ in pairs(ns.db.profiles) do n = n + 1 end
		return ns.ActiveProfile() .. "|" .. n .. "|" .. tostring(ns.db.editModeLayout)
			.. "|" .. tostring(ns.IsCharacterProfile())
	end
	local seen
	watcher:SetScript("OnUpdate", function()
		local state = ns.db and State()
		if pending or state ~= seen then
			pending, seen = false, state
			Shown()
		end
	end)
	canvas:HookScript("OnHide", function() pending = true end)
	kit.RegisterSubpage(canvas, "Profiles Demo", "Profiles Demo")
end
