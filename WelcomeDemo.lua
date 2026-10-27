-- A demo of a simpler welcome window: one page with three levels (Subtle,
-- Balanced, Full), closed with the X to keep the one picked, and Customize
-- for pages that change one part of it (their questions only, for now).
-- Only /cine debug welcomedemo opens it; the real one is still Welcome.lua.
-- Picking a level really switches to its profile, as there. Everything's
-- drawn flat (its own buttons, X and descriptions, no Blizzard templates or
-- tooltip), so the old and new styles don't mix.
-- (English only while it's a demo. To scrap it: delete this file, its line in
-- both .toc files and the welcomedemo lines in Slash.lua.)

local ADDON_NAME, ns = ...

local WIDTH, PAD, GAP = 560, 22, 14
local CARD_W = (WIDTH - 2 * PAD - 2 * GAP) / 3
local MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\RoundIcon" -- soft rounded corners

-- Colours: the window, an edge, a lit edge (hovered), gold (picked, the main
-- button) and text greys.
local BG = { 0.07, 0.07, 0.08 }
local RAISED = { 0.11, 0.11, 0.12 }
local EDGE = { 0.24, 0.24, 0.26 }
local LIT = { 0.55, 0.55, 0.58 }
local GOLD = { 1, 0.82, 0 }
local BUTTON, BUTTON_LIT = { 0.5, 0.38, 0.05 }, { 0.62, 0.48, 0.08 }
local WHITE, SOFT, DIM = { 1, 1, 1 }, { 0.78, 0.78, 0.78 }, { 0.5, 0.5, 0.52 }

-- The three levels (ns.WELCOME_LEVELS), and each slot's question and
-- choices (ns.SLOT_CHOICES, ns.SlotChoices): ProfileChoices.lua.
local LEVELS = ns.WELCOME_LEVELS

-- The Customize pages: a slot's (its question and choices), or just a question.
local OWN_PROFILE = "My setup" -- (the profile of your own a change on a built-in starts)
ns.OWN_PROFILE = OWN_PROFILE
local SECTIONS = {}
-- (A slot with no choices on this client isn't listed: Layout on retail.)
for _, slot in ipairs({ "frames", "bars", "layout", "camera", "vfx", "visions", "misc" }) do
	if slot == "visions" then
		tinsert(SECTIONS, { label = "Visions", page = "Vision", question = "Which Visions do you want?" })
	elseif ns.SlotChoices(slot) then
		tinsert(SECTIONS, setmetatable({ slot = slot }, { __index = ns.SLOT_CHOICES[slot] }))
	end
end

local window, pages, status, about
local cards = {} -- profile name -> its card
local levelOf = {} -- profile name -> its level

-- (Forever keeps a FontString's text and vertex colour as one: set both.)
local function Color(s, c)
	s:SetTextColor(c[1], c[2], c[3])
	s:SetVertexColor(c[1], c[2], c[3])
end

local function Flat(frame, bg, edge)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	frame:SetBackdropColor(unpack(bg or RAISED))
	frame:SetBackdropBorderColor(unpack(edge or EDGE))
end

local function Text(parent, font, text, color, width)
	local s = parent:CreateFontString(nil, "OVERLAY", font)
	s:SetJustifyH("LEFT")
	s:SetJustifyV("TOP")
	if width then s:SetWidth(width) end
	s:SetText(text)
	Color(s, color or WHITE)
	return s
end

local function Rounded(parent, texture)
	if not parent.CreateMaskTexture then return end
	local mask = parent:CreateMaskTexture()
	mask:SetAllPoints(texture)
	mask:SetTexture(MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
	texture:AddMaskTexture(mask)
end

-- A flat button: "main" gold, "box" outlined (the other buttons beside it),
-- otherwise just text that lights up.
local function FlatButton(parent, text, style, onClick)
	local main = style == "main" or style == "box"
	local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
	local s = Text(b, main and "GameFontHighlight" or "GameFontHighlightSmall", text,
		style == "main" and WHITE or style == "box" and SOFT or DIM)
	s:SetPoint("CENTER")
	b.text = s
	if style == "main" then
		b:SetSize(120, 30)
		Flat(b, BUTTON, BUTTON)
		b:SetScript("OnEnter", function() b:SetBackdropColor(unpack(BUTTON_LIT)) end)
		b:SetScript("OnLeave", function() b:SetBackdropColor(unpack(BUTTON)) end)
	elseif style == "box" then
		b:SetSize(120, 30)
		Flat(b, RAISED, EDGE)
		b:SetScript("OnEnter", function()
			b:SetBackdropBorderColor(unpack(LIT))
			Color(s, WHITE)
		end)
		b:SetScript("OnLeave", function()
			b:SetBackdropBorderColor(unpack(EDGE))
			Color(s, SOFT)
		end)
	else
		b:SetSize(s:GetStringWidth() + 6, 20)
		b:SetScript("OnEnter", function() Color(s, WHITE) end)
		b:SetScript("OnLeave", function() Color(s, DIM) end)
	end
	b:SetScript("OnClick", onClick)
	function b:SetLabel(label)
		s:SetText(label)
		if not main then b:SetWidth(s:GetStringWidth() + 6) end
	end
	return b
end

-- (The Profiles demo page draws with these too: ProfilesDemo.lua.)
ns.DemoUI = { Flat = Flat, Text = Text, Color = Color, Rounded = Rounded, FlatButton = FlatButton,
	BG = BG, RAISED = RAISED, EDGE = EDGE, LIT = LIT, GOLD = GOLD, WHITE = WHITE, SOFT = SOFT, DIM = DIM }

-- The close X, two thin lines.
local function CloseX(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(28, 28)
	local lines = {}
	if b.CreateLine then
		for i, ends in ipairs({ { 9, 9, 19, 19 }, { 9, 19, 19, 9 } }) do
			local line = b:CreateLine(nil, "OVERLAY")
			line:SetThickness(2)
			line:SetStartPoint("BOTTOMLEFT", b, ends[1], ends[2])
			line:SetEndPoint("BOTTOMLEFT", b, ends[3], ends[4])
			line:SetColorTexture(unpack(DIM))
			lines[i] = line
		end
	else
		local s = Text(b, "GameFontHighlightLarge", "x", DIM)
		s:SetPoint("CENTER")
		b:SetScript("OnEnter", function() Color(s, WHITE) end)
		b:SetScript("OnLeave", function() Color(s, DIM) end)
	end
	if lines[1] then
		b:SetScript("OnEnter", function() for _, l in ipairs(lines) do l:SetColorTexture(unpack(WHITE)) end end)
		b:SetScript("OnLeave", function() for _, l in ipairs(lines) do l:SetColorTexture(unpack(DIM)) end end)
	end
	b:SetScript("OnClick", function() parent:Hide() end)
	return b
end

-- What the description box says: the hovered level's, else the picked one's.
local function Describe(level)
	if level then
		about:SetText("|cffffd100" .. level.label .. "|r   " .. level.tip)
	else
		about:SetText("Pick a level to try it now. You can change it any time, here or on the Profiles page.")
	end
end

local function Active()
	return ns.ProfileChosen() and ns.db.enabled and ns.ActiveProfile()
end

-- Gold edge on the level being tried, and the lines saying so.
local function UpdatePicked()
	local active = Active()
	for name, card in pairs(cards) do
		card.active = name == active
		card:SetBackdropBorderColor(unpack(card.active and GOLD or EDGE))
	end
	if active then
		status:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t Trying |cffffd100"
			.. (levelOf[active] and levelOf[active].label or ns.ProfileLabel(active)) .. "|r. Close this window to keep it.")
	elseif not ns.db.enabled then
		status:SetText("Cinematic is off. Pick a level, or Turn on, to start it again.")
	else
		status:SetText("")
	end
	Describe(levelOf[active])
end

local function Pick(name, level)
	if not ns.db.enabled then ns.SetEnabled(true) end
	ns.SetProfile(name)
	if ns.RestartTimers then ns.RestartTimers() end
	ns.PreviewProfile(name)
	-- (Full: Vitals Vision's screen edges for a moment, too.)
	if level and level.flash == "vitals" and ns.FlashVitals then ns.FlashVitals(2) end
	UpdatePicked()
end

-- A level's card: its profile's icon, the level's name and a short line.
local function Card(parent, profile, level)
	local card = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
	card:SetSize(CARD_W, 124)
	Flat(card)
	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetSize(44, 44)
	icon:SetPoint("TOP", 0, -16)
	icon:SetTexture(profile.icon)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	Rounded(card, icon)
	local title = Text(card, "GameFontHighlightLarge", level.label)
	title:SetPoint("TOP", icon, "BOTTOM", 0, -8)
	local sub = Text(card, "GameFontHighlightSmall", level.line, SOFT, CARD_W - 20)
	sub:SetJustifyH("CENTER")
	sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
	card:SetScript("OnEnter", function(self)
		if not self.active then self:SetBackdropBorderColor(unpack(LIT)) end
		Describe(level)
	end)
	card:SetScript("OnLeave", function(self)
		if not self.active then self:SetBackdropBorderColor(unpack(EDGE)) end
		Describe(levelOf[Active()])
	end)
	card:SetScript("OnClick", function() Pick(profile.name, level) end)
	return card
end

-- Page 1: the three levels.
local function BuildLevels(page)
	local title = Text(page, "GameFontNormalHuge", "Welcome to Cinematic", GOLD)
	title:SetPoint("TOPLEFT")
	local sub = Text(page, "GameFontHighlight", "Immerse yourself in the world. How much do you want?", SOFT)
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	local byName = {}
	for _, profile in ipairs(ns.BUILTIN_PROFILES) do byName[profile.name] = profile end
	for i, level in ipairs(LEVELS) do
		local profile = byName[level.profile or ns.DEFAULT_PROFILE]
		if profile then
			local card = Card(page, profile, level)
			card:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", (i - 1) * (CARD_W + GAP), -18)
			cards[profile.name], levelOf[profile.name] = card, level
		end
	end

	-- The description box under the cards.
	local box = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate")
	box:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18 - 124 - 12)
	box:SetSize(WIDTH - 2 * PAD, 56)
	Flat(box, BG)
	about = Text(box, "GameFontHighlightSmall", "", SOFT, WIDTH - 2 * PAD - 24)
	about:SetPoint("TOPLEFT", 12, -10)
	about:SetSpacing(2)

	status = Text(page, "GameFontHighlightSmall", "", SOFT)
	status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
	page.height = 380
end

-- Page 2: Customize, a list of parts on the left and the one shown on the right.
local function BuildCustomize(page)
	local title = Text(page, "GameFontNormalHuge", "Customize", GOLD)
	title:SetPoint("TOPLEFT")
	local sub = Text(page, "GameFontHighlight", "Change one part of your level. Each change shows straight away.", SOFT)
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	local NAV_W, PANEL_H = 140, 300
	local rows, question, soon, saved, panel
	local options = {} -- the choices shown, as rows
	local panelW = WIDTH - 2 * PAD - NAV_W - GAP
	local shown -- (the section shown)

	-- Gold edge on the choice the live settings match (none: your own mix),
	-- and which profile a change goes in.
	local function UpdateChoices()
		local any
		for _, option in ipairs(options) do
			-- (the first that matches: two parts can set a slot the same way)
			option.active = not any and option:IsShown() and ns.SlotPartMatches(shown.slot, option.choice.part)
			any = any or option.active
			option:SetBackdropBorderColor(unpack(option.active and GOLD or EDGE))
		end
		local active = ns.ActiveProfile()
		if not shown.slot then
			saved:SetText("")
		elseif ns.IsBuiltinProfile(active) then
			saved:SetText("A change here starts a profile of your own, " .. OWN_PROFILE .. ".")
		else
			saved:SetText("Changes go in your profile |cffffd100" .. active .. "|r."
				.. (any and "" or " This part is a mix of its own."))
		end
	end

	-- A choice's row: an icon, its name and a line, gold when it's the live one.
	local function Option(i)
		local option = CreateFrame("Button", nil, panel, BackdropTemplateMixin and "BackdropTemplate")
		option:SetSize(panelW - 28, 40)
		Flat(option, BG)
		option.icon = option:CreateTexture(nil, "ARTWORK")
		option.icon:SetSize(28, 28)
		option.icon:SetPoint("LEFT", 8, 0)
		option.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		Rounded(option, option.icon)
		option.name = Text(option, "GameFontHighlight", "")
		option.name:SetPoint("TOPLEFT", 10, -6)
		option.line = Text(option, "GameFontHighlightSmall", "", SOFT, panelW - 28 - 60)
		option.line:SetPoint("TOPLEFT", option.name, "BOTTOMLEFT", 0, -3)
		option.line:SetWordWrap(false)
		option:SetScript("OnEnter", function(self)
			if not self.active then self:SetBackdropBorderColor(unpack(LIT)) end
		end)
		option:SetScript("OnLeave", function(self)
			if not self.active then self:SetBackdropBorderColor(unpack(EDGE)) end
		end)
		option:SetScript("OnClick", function(self)
			if self.active then return end -- (already so: no profile of your own for nothing)
			if not ns.db.enabled then ns.SetEnabled(true) end
			ns.ApplyPart(shown.slot, self.choice.part, OWN_PROFILE)
			UpdateChoices()
		end)
		options[i] = option
		return option
	end

	local function Show(i)
		for j, row in ipairs(rows) do
			row.on = i == j
			row:SetBackdropColor(unpack(row.on and RAISED or BG))
			Color(row.text, row.on and WHITE or SOFT)
		end
		shown = SECTIONS[i]
		question:SetText(shown.question)
		local choices = shown.slot and ns.SlotChoices(shown.slot) or {}
		soon:SetShown(#choices == 0)
		-- (rows closer together when there are more than five, to fit the panel)
		local step = math.min(44, math.floor((PANEL_H - 56) / math.max(1, #choices)))
		for j, choice in ipairs(choices) do
			local option = options[j] or Option(j)
			option:SetHeight(step - 4)
			option:SetPoint("TOPLEFT", question, "BOTTOMLEFT", 0, -12 - (j - 1) * step)
			option.choice = choice
			-- (an icon when the choice has one, the text beside it)
			option.icon:SetTexture(choice.icon)
			option.icon:SetShown(choice.icon ~= nil)
			option.name:SetPoint("TOPLEFT", choice.icon and 46 or 10, -6)
			option.name:SetText(choice.label)
			option.line:SetWidth(panelW - 28 - (choice.icon and 56 or 20))
			option.line:SetText(choice.line)
			option:Show()
		end
		for j = #choices + 1, #options do options[j]:Hide() end
		UpdateChoices()
	end
	page.Refresh = function() if shown then Show(shown.index) end end
	page.settingsPage = function() return shown and shown.page end
	rows = {}
	for i, section in ipairs(SECTIONS) do
		section.index = i
		local row = CreateFrame("Button", nil, page, BackdropTemplateMixin and "BackdropTemplate")
		row:SetSize(NAV_W, 26)
		row:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18 - (i - 1) * 28)
		Flat(row, BG, BG)
		row.text = Text(row, "GameFontHighlight", section.label, SOFT)
		row.text:SetPoint("LEFT", 10, 0)
		row:SetScript("OnEnter", function() if not row.on then Color(row.text, WHITE) end end)
		row:SetScript("OnLeave", function() if not row.on then Color(row.text, SOFT) end end)
		row:SetScript("OnClick", function() Show(i) end)
		rows[i] = row
	end

	panel = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate")
	panel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", NAV_W + GAP, -18)
	panel:SetSize(panelW, PANEL_H)
	Flat(panel)
	question = Text(panel, "GameFontHighlightLarge", "", WHITE, panelW - 28)
	question:SetPoint("TOPLEFT", 14, -14)
	soon = Text(panel, "GameFontHighlightSmall", "Its choices come next.", DIM)
	soon:SetPoint("TOPLEFT", question, "BOTTOMLEFT", 0, -8)
	saved = Text(panel, "GameFontHighlightSmall", "", DIM, panelW - 28)
	saved:SetPoint("BOTTOMLEFT", 14, 12)
	Show(1)
	page.height = 476
end

local primary, customize, settings, off, back

local function ShowPage(n)
	for i, page in ipairs(pages) do page:SetShown(i == n) end
	customize:SetShown(n == 1)
	if n == 1 then UpdatePicked() elseif pages[n].Refresh then pages[n].Refresh() end
	off:SetShown(n == 1)
	off:SetLabel(ns.db.enabled and "Turn off" or "Turn on")
	settings:ClearAllPoints()
	settings:SetPoint("RIGHT", n == 1 and customize or primary, "LEFT", -8, 0)
	back:SetShown(n > 1)
	window.page = n
	window:SetHeight(pages[n].height)
end

local function OnHide()
	if not ns.db.enabled then -- (closed after Turn off)
		ns.Print("turned off. /cine brings the welcome window back to pick a profile.")
	elseif not ns.ProfileChosen() then
		ns.Print("off until you pick a profile. This window comes back next login, or now with /cine welcome.")
	end
end

local function CreateWindow()
	window = CreateFrame("Frame", "CinematicWelcomeDemo", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetWidth(WIDTH)
	window:SetPoint("CENTER", 0, 60)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetScript("OnHide", OnHide)
	Flat(window, { BG[1], BG[2], BG[3], 0.97 })
	tinsert(UISpecialFrames, "CinematicWelcomeDemo") -- Escape closes it, as the X does

	-- The X keeps the level picked (and with none, Cinematic stays off).
	CloseX(window):SetPoint("TOPRIGHT", -8, -8)

	pages = {}
	for i, build in ipairs({ BuildLevels, BuildCustomize }) do
		local page = CreateFrame("Frame", nil, window)
		page:SetPoint("TOPLEFT", PAD, -PAD)
		page:SetPoint("BOTTOMRIGHT", -PAD, PAD)
		build(page)
		pages[i] = page
	end

	-- Footer: a quiet link on the left; on the right Done (keeps what's
	-- picked, as the X does), Customize (on the first page) and Settings: the
	-- options at the page for what's shown (the Profiles page, or the part's).
	primary = FlatButton(window, "Done", "main", function() window:Hide() end)
	primary:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	customize = FlatButton(window, "Customize", "box", function() ShowPage(2) end)
	customize:SetPoint("RIGHT", primary, "LEFT", -8, 0)
	settings = FlatButton(window, "Settings", "box", function()
		local page = window.page == 2 and pages[2].settingsPage() or "Profiles"
		window:Hide()
		ns.OpenOptions(page)
	end)
	-- Turn off (or on again): Cinematic, not the window, which stays open to
	-- pick a level.
	off = FlatButton(window, "Turn off", nil, function()
		local on = not ns.db.enabled
		ns.SetEnabled(on)
		off:SetLabel(on and "Turn off" or "Turn on")
		UpdatePicked()
	end)
	off:SetPoint("BOTTOMLEFT", PAD - 3, PAD + 5)
	back = FlatButton(window, "< Back", nil, function() ShowPage(1) end)
	back:SetPoint("BOTTOMLEFT", PAD - 3, PAD + 5)
end

function ns.ShowWelcomeDemo()
	if not window then CreateWindow() end
	window:Show()
	ShowPage(1)
end
