-- The welcome window: the first time Cinematic runs, it asks the player to
-- pick a level (Subtle, Balanced, Cinema: each a built-in profile), so they
-- start from a setup they chose. Until they pick one, Cinematic does nothing
-- and this comes back at each login (Decide later), unless they turn
-- Cinematic off from it. Picking one switches to its profile at once, behind
-- the window, so they can try each in turn; the X, Escape or Done keep it.
-- Customize has pages that change one part of it. /cine welcome and the
-- minimap button (with no profile picked) bring it back. Everything's drawn
-- flat (its own buttons, X and descriptions, no Blizzard templates or
-- tooltip), so the old and new styles don't mix.

local ADDON_NAME, ns = ...
local L = ns.L

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
-- (the profile of your own a change on a built-in starts: in your language here)
local OWN_PROFILE = "My setup"
ns.OWN_PROFILE = OWN_PROFILE
local SECTIONS = {}
local VISIONS = { label = "Visions", page = "Vision", question = "Which Visions do you want?",
	visions = true }
-- What each Vision does, in a line (the vision wheel's list: MarkerWheel.lua).
local VISION_LINES = {
	heal = "Party and raid frames show only who needs healing",
	quest = "Quest mobs keep their nameplates, with a quest mark",
	duel = "Watch duels near you: the duelists' health shows",
	roll = "Group loot rolls in a window: who picked what",
	vitals = "The screen's edges close in as your health drops",
}
-- (A slot with no choices on this client isn't listed: Layout on retail.)
for _, slot in ipairs({ "frames", "bars", "layout", "camera", "vfx", "visions", "chat", "sound" }) do
	if slot == "visions" then
		tinsert(SECTIONS, VISIONS)
	elseif ns.SlotChoices(slot) then
		tinsert(SECTIONS, setmetatable({ slot = slot }, { __index = ns.SLOT_CHOICES[slot] }))
	end
end
ns.OnLanguage(function()
	OWN_PROFILE = L[OWN_PROFILE]
	ns.TranslateFields({ VISIONS }, "label", "question")
	for key, line in pairs(VISION_LINES) do VISION_LINES[key] = L[line] end
end)

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
		about:SetText(L["Pick a level to try it now. You can change it any time, here or on the Profiles page."])
	end
end

local function Active()
	return ns.ProfileChosen() and ns.db.enabled and ns.ActiveProfile()
end

local primary, finish, settings, off, back

-- Gold edge on the level being tried, the lines saying so, and the way out:
-- Decide later (none picked yet) or Done.
local function UpdatePicked()
	local active = Active()
	for name, card in pairs(cards) do
		card.active = name == active
		card:SetBackdropBorderColor(unpack(card.active and GOLD or EDGE))
	end
	if active then
		local name = levelOf[active] and levelOf[active].label or ns.ProfileLabel(active)
		status:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t "
			.. L["Trying %s. Close this window to keep it."]:format("|cffffd100" .. name .. "|r"))
	elseif not ns.db.enabled then
		status:SetText(L["Cinematic is off. Pick a level, or Turn on, to start it again."])
	else
		status:SetText(L["Nothing runs until you pick one."])
	end
	finish:SetLabel(ns.ProfileChosen() and L["Done"] or L["Decide later"])
	Describe(levelOf[active])
end

local function Pick(name, level)
	if not ns.db.enabled then ns.SetEnabled(true) end
	ns.SetProfile(name)
	if ns.RestartTimers then ns.RestartTimers() end
	ns.PreviewProfile(name)
	-- (Cinema: Vitals Vision's screen edges for a moment, too. Another level
	-- ends that look at once.)
	if ns.StopVitalsFlash then ns.StopVitalsFlash() end
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
	local title = Text(page, "GameFontNormalHuge", L["Welcome to Cinematic"], GOLD)
	title:SetPoint("TOPLEFT")
	local sub = Text(page, "GameFontHighlight", L["Immerse yourself in the world. How much do you want?"], SOFT)
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
	-- (As tall as the longest description, in this language, so none runs
	-- out of it; the window grows to match.)
	local tallest = 0
	for _, level in ipairs(LEVELS) do
		Describe(level)
		tallest = math.max(tallest, about:GetStringHeight())
	end
	Describe(nil)
	tallest = math.max(tallest, about:GetStringHeight())
	local boxH = math.max(56, math.ceil(tallest) + 20)
	box:SetHeight(boxH)

	status = Text(page, "GameFontHighlightSmall", "", SOFT)
	status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
	page.height = 380 + boxH - 56
end

-- Page 2: Customize, a list of parts on the left and the one shown on the right.
local function BuildCustomize(page)
	local title = Text(page, "GameFontNormalHuge", L["Customize"], GOLD)
	title:SetPoint("TOPLEFT")
	local sub = Text(page, "GameFontHighlight", L["Change one part of your level. Each change shows straight away."],
		SOFT)
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	local NAV_W, PANEL_H = 140, 300
	local rows, question, soon, saved, panel
	local options = {} -- the choices shown, as rows
	local panelW = WIDTH - 2 * PAD - NAV_W - GAP
	local shown -- (the section shown)

	-- Gold edge on the choice the live settings match (none: your own mix),
	-- or on each Vision that's on, and which profile a change goes in.
	local function UpdateChoices()
		local any = shown.visions
		for _, option in ipairs(options) do
			local vision = option.choice and option.choice.vision
			if vision then
				option.active = option:IsShown() and ns.VisionOn(vision)
			else
				-- (the first that matches: two parts can set a slot the same way)
				option.active = not any and option:IsShown() and ns.SlotPartMatches(shown.slot, option.choice.part)
				any = any or option.active
			end
			option:SetBackdropBorderColor(unpack(option.active and GOLD or EDGE))
		end
		local active = ns.ActiveProfile()
		if not shown.slot and not shown.visions then
			saved:SetText("")
		elseif ns.IsBuiltinProfile(active) then
			saved:SetText(L["A change here starts a profile of your own, %s."]:format(OWN_PROFILE))
		else
			saved:SetText((any and L["Changes go in your profile %s."]
				or L["Changes go in your profile %s. This part is a mix of its own."])
				:format("|cffffd100" .. active .. "|r"))
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
		-- (a layout Cinematic makes for you: a gold tag beside its name)
		option.tag = Text(option, "GameFontHighlightSmall", L["Cinematic makes it for you"], GOLD)
		option.tag:SetPoint("LEFT", option.name, "RIGHT", 8, 0)
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
			local vision = self.choice.vision
			if vision then
				-- (A Vision: on or off, any number of them, in a profile of your own.)
				ns.EnsureOwnProfile(OWN_PROFILE)
				ns.ToggleVision(vision, true)
				ns.SaveProfile()
				UpdateChoices()
				return
			end
			if self.active then return end -- (already so: no profile of your own for nothing)
			if not ns.db.enabled then ns.SetEnabled(true) end
			ns.ApplyPart(shown.slot, self.choice.part, OWN_PROFILE)
			UpdateChoices()
			if page.OnShow then page.OnShow() end -- (a profile's picked now: Done, not Decide later)
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
		if shown.visions then
			-- (each a row that's ticked on or off, its icon as the vision wheel has it)
			choices = {}
			for _, vision in ipairs(ns.VISION_LIST or {}) do
				choices[#choices + 1] = { vision = vision, label = L[vision.label], icon = vision.icon,
					line = VISION_LINES[vision.key] }
			end
		end
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
			option.tag:SetShown(choice.made == true)
			option.line:SetWidth(panelW - 28 - (choice.icon and 56 or 20))
			option.line:SetText(choice.line)
			option:Show()
		end
		for j = #choices + 1, #options do options[j]:Hide() end
		UpdateChoices()
		if page.OnShow then page.OnShow() end
	end
	page.Refresh = function() if shown then Show(shown.index) end end
	-- (Next: the part after this one, false on the last.)
	page.Next = function()
		if shown.index >= #SECTIONS then return false end
		Show(shown.index + 1)
		return true
	end
	page.IsLast = function() return shown.index >= #SECTIONS end
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
	soon = Text(panel, "GameFontHighlightSmall", L["Its choices come next."], DIM)
	soon:SetPoint("TOPLEFT", question, "BOTTOMLEFT", 0, -8)
	saved = Text(panel, "GameFontHighlightSmall", "", DIM, panelW - 28)
	saved:SetPoint("BOTTOMLEFT", 14, 12)
	Show(1)
	page.height = 476
end

local function ShowPage(n)
	for i, page in ipairs(pages) do page:SetShown(i == n) end
	if n == 1 then
		primary:SetLabel(L["Next"])
		finish:Show()
		UpdatePicked()
	elseif pages[n].Refresh then
		pages[n].Refresh()
	end
	off:SetShown(n == 1)
	off:SetLabel(ns.db.enabled and L["Turn off"] or L["Turn on"])
	back:SetShown(n > 1)
	window.page = n
	window:SetHeight(pages[n].height)
end

-- Closed (the X, Escape, Done or Decide later): what's on now, in chat.
-- (Not on the way to the settings: those say it.)
local toSettings
local function OnHide()
	if toSettings then
		toSettings = false
	elseif not ns.db.enabled then -- (closed after Turn off)
		ns.Print(L["turned off. /cine brings this window back to pick a profile."])
	elseif not ns.ProfileChosen() then
		ns.Print(L["off until you pick a profile. This window comes back next login, or now with /cine welcome."])
	else
		ns.Print(L["profile: %s. Change it any time on the Profiles settings page, or with /cine profile."]
			:format(ns.ProfileLabel(ns.ActiveProfile())))
	end
end

local function CreateWindow()
	window = CreateFrame("Frame", "CinematicWelcome", UIParent, BackdropTemplateMixin and "BackdropTemplate")
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
	tinsert(UISpecialFrames, "CinematicWelcome") -- Escape closes it, as the X does

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
	-- On Customize the main button steps through the parts: Next, then Done
	-- (or Decide later) on the last.
	pages[2].OnShow = function()
		local out = ns.ProfileChosen() and L["Done"] or L["Decide later"]
		local last = pages[2].IsLast()
		primary:SetLabel(last and out or L["Next"])
		-- (the quiet way out too, but not twice on the last)
		finish:SetLabel(out)
		finish:SetShown(not last)
	end

	-- Footer: a quiet link on the left (Turn off, or Back); on the right
	-- Next, the way on: from the levels to Customize, then through its parts,
	-- Done on the last. Beside it Settings (the options at the page for
	-- what's shown: the Profiles page, or the part's) and, quietly, Done (or
	-- Decide later): out at any point, keeping what's picked, as the X does.
	primary = FlatButton(window, L["Next"], "main", function()
		if window.page == 1 then
			ShowPage(2)
		elseif not pages[2].Next() then
			window:Hide()
		end
	end)
	primary:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	finish = FlatButton(window, L["Done"], nil, function() window:Hide() end)
	settings = FlatButton(window, L["Settings"], "box", function()
		local page = window.page == 2 and pages[2].settingsPage() or "Profiles"
		toSettings = true
		window:Hide()
		ns.OpenOptions(page)
	end)
	settings:SetPoint("RIGHT", primary, "LEFT", -8, 0)
	finish:SetPoint("RIGHT", settings, "LEFT", -12, 0)
	-- Turn off (or on again): Cinematic, not the window, which stays open to
	-- pick a level.
	off = FlatButton(window, L["Turn off"], nil, function()
		local on = not ns.db.enabled
		ns.SetEnabled(on)
		off:SetLabel(on and L["Turn off"] or L["Turn on"])
		UpdatePicked()
	end)
	off:SetPoint("BOTTOMLEFT", PAD - 3, PAD + 5)
	back = FlatButton(window, L["< Back"], nil, function() ShowPage(1) end)
	back:SetPoint("BOTTOMLEFT", PAD - 3, PAD + 5)
end

function ns.ShowWelcome()
	if not window then CreateWindow() end
	window:Show()
	ShowPage(1)
end

-- At login (and /reload), until a profile's been picked.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, _, isLogin, isReload)
	if (isLogin or isReload) and ns.db and not ns.db.profileChosen and ns.db.enabled then
		C_Timer.After(1, ns.ShowWelcome)
	end
end)
