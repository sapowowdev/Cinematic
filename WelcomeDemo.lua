-- A demo of a simpler welcome window, in three steps: what Cinematic does,
-- pick a style (three big cards, the rest under More styles), and three
-- things to remember. Only /cine debug welcomedemo opens it; the real one is
-- still Welcome.lua. Picking a style here really switches to it, as there.
-- (English only while it's a demo. To scrap it: delete this file, its line in
-- both .toc files and the welcomedemo lines in Slash.lua.)

local _, ns = ...

local WIDTH, PAD, GAP = 540, 20, 16
local CARD_W = (WIDTH - 2 * PAD - 2 * GAP) / 3
local GOLD = { 1, 0.82, 0 }
local EDGE = { 0.3, 0.3, 0.32 }

-- The three styles given a card (by name; Full is this client's default),
-- and the short line each shows (its full description is the tooltip).
local FEATURED = { "Lite", "VFX Only" }
local SHORT = {
	["Lite"] = "The fading, fewer cameras",
	["VFX Only"] = "Just the tint, UI stays",
}

local window, pages, step, primary, dots, status
local cards = {} -- profile name -> its card or chip

local function Flat(frame, alpha)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	frame:SetBackdropColor(0.08, 0.08, 0.09, alpha or 1)
	frame:SetBackdropBorderColor(unpack(EDGE))
end

local function Text(parent, font, text, width)
	local s = parent:CreateFontString(nil, "OVERLAY", font)
	s:SetJustifyH("LEFT")
	if width then s:SetWidth(width) end
	s:SetText(text)
	return s
end

-- A tile with an icon, a name and a short line under it.
local function Tile(parent, icon, name, line)
	local tile = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
	tile:SetSize(CARD_W, 118)
	Flat(tile)
	local tex = tile:CreateTexture(nil, "ARTWORK")
	tex:SetSize(40, 40)
	tex:SetPoint("TOP", 0, -16)
	tex:SetTexture(icon)
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local title = Text(tile, "GameFontHighlight", name)
	title:SetPoint("TOP", tex, "BOTTOM", 0, -8)
	local sub = Text(tile, "GameFontDisableSmall", line, CARD_W - 16)
	sub:SetJustifyH("CENTER")
	sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
	return tile
end

local function Tooltip(frame, profile)
	frame:SetScript("OnEnter", function(self)
		if not self.active then self:SetBackdropBorderColor(0.6, 0.6, 0.62) end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(profile.label or profile.name, 1, 1, 1)
		GameTooltip:AddLine(profile.tip, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function(self)
		if not self.active then self:SetBackdropBorderColor(unpack(EDGE)) end
		GameTooltip:Hide()
	end)
end

-- Gold edge on the style being tried, and the line saying so.
local function UpdatePicked()
	local active = ns.ProfileChosen() and ns.db.enabled and ns.ActiveProfile()
	for name, card in pairs(cards) do
		card.active = name == active
		card:SetBackdropBorderColor(unpack(card.active and GOLD or EDGE))
	end
	if active then
		status:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t Trying |cffffd100" .. ns.ProfileLabel(active)
			.. "|r. Click another to compare.")
	else
		status:SetText("Click one to try it now. You can switch any time.")
	end
end

local function Pick(name)
	if not ns.db.enabled then ns.SetEnabled(true) end
	ns.SetProfile(name)
	if ns.RestartTimers then ns.RestartTimers() end
	ns.PreviewProfile(name)
	UpdatePicked()
end

local function Close()
	window:Hide()
	if not ns.ProfileChosen() then
		ns.Print("off until you pick a profile. This window comes back next login, or now with /cine welcome.")
	end
end

local ShowStep

-- Step 1: what it does.
local function BuildIntro(page)
	local title = Text(page, "GameFontNormalHuge", "Welcome to Cinematic")
	title:SetPoint("TOPLEFT")
	local sub = Text(page, "GameFontHighlight", "Immerse yourself in the world.")
	sub:SetTextColor(0.75, 0.75, 0.75)
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	local tiles = {
		{ "Interface\\Icons\\Spell_Nature_Invisibilty", "Calm UI", "Fades when you're not fighting" },
		{ "Interface\\Icons\\Spell_Shadow_Charm", "Movie look", "Letterbox bars and a colour tint" },
		{ "Interface\\Icons\\INV_Misc_Spyglass_03", "Living camera", "Flights, campfires, going AFK" },
	}
	for i, t in ipairs(tiles) do
		local tile = Tile(page, t[1], t[2], t[3])
		tile:EnableMouse(false)
		tile:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", (i - 1) * (CARD_W + GAP), -18)
	end
	local note = Text(page, "GameFontHighlightSmall", "Fights, casting and opening windows bring everything back.")
	note:SetTextColor(0.75, 0.75, 0.75)
	note:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18 - 118 - 14)
	page.height = 200 + 118
end

-- Step 2: pick a style.
local function BuildStyles(page)
	local title = Text(page, "GameFontNormalHuge", "How much do you want?")
	title:SetPoint("TOPLEFT")
	status = Text(page, "GameFontHighlight", "", WIDTH - 2 * PAD)
	status:SetTextColor(0.75, 0.75, 0.75)
	status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	-- Full (this client's default), Light, Just the look.
	local featured = { ns.BUILTIN_PROFILES[1].name, FEATURED[1], FEATURED[2] }
	local labels = { "Full", "Light", "Just the look" }
	local isFeatured, byName = {}, {}
	for _, profile in ipairs(ns.BUILTIN_PROFILES) do byName[profile.name] = profile end
	for i, name in ipairs(featured) do
		local profile = byName[name]
		if profile then
			isFeatured[name] = true
			local line = SHORT[name] or "Everything on"
			local card = Tile(page, profile.icon, labels[i], line)
			card:SetPoint("TOPLEFT", status, "BOTTOMLEFT", (i - 1) * (CARD_W + GAP), -18)
			card:SetScript("OnClick", function() Pick(name) end)
			Tooltip(card, profile)
			cards[name] = card
		end
	end

	-- More styles: the rest, as small chips, three to a row.
	local more = CreateFrame("Button", nil, page)
	more:SetSize(120, 18)
	more:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -18 - 118 - 12)
	local moreText = Text(more, "GameFontNormalSmall", "More styles  +")
	moreText:SetPoint("LEFT")
	local list = CreateFrame("Frame", nil, page)
	list:SetPoint("TOPLEFT", more, "BOTTOMLEFT", 0, -8)
	list:SetSize(WIDTH - 2 * PAD, 1)
	list:Hide()
	local chipW, n = (WIDTH - 2 * PAD - 2 * 10) / 3, 0
	for _, profile in ipairs(ns.BUILTIN_PROFILES) do
		if not isFeatured[profile.name] then
			local chip = CreateFrame("Button", nil, list, BackdropTemplateMixin and "BackdropTemplate")
			chip:SetSize(chipW, 28)
			chip:SetPoint("TOPLEFT", (n % 3) * (chipW + 10), -math.floor(n / 3) * 36)
			Flat(chip)
			local icon = chip:CreateTexture(nil, "ARTWORK")
			icon:SetSize(20, 20)
			icon:SetPoint("LEFT", 4, 0)
			icon:SetTexture(profile.icon)
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			local label = Text(chip, "GameFontHighlightSmall", profile.label or profile.name)
			label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
			local name = profile.name
			chip:SetScript("OnClick", function() Pick(name) end)
			Tooltip(chip, profile)
			cards[name] = chip
			n = n + 1
		end
	end
	local listHeight = math.ceil(n / 3) * 36
	local base = 200 + 118 + 26
	page.height = base
	more:SetScript("OnClick", function()
		list:SetShown(not list:IsShown())
		moreText:SetText(list:IsShown() and "More styles  -" or "More styles  +")
		page.height = base + (list:IsShown() and listHeight + 8 or 0)
		ShowStep(2)
	end)
end

-- Step 3: three things to remember.
local function BuildTips(page)
	local title = Text(page, "GameFontNormalHuge", "You're set")
	title:SetPoint("TOPLEFT")
	local rows = {
		{ "Interface\\Icons\\INV_Misc_Note_01", "|cffffd100/cine|r turns Cinematic on and off" },
		{ "Interface\\CURSOR\\Point", "Point at a faded bar to show it" },
		{ "Interface\\Icons\\INV_Misc_Gear_01", "Right-click the minimap button for settings" },
	}
	local last = title
	for i, r in ipairs(rows) do
		local icon = page:CreateTexture(nil, "ARTWORK")
		icon:SetSize(28, 28)
		icon:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -18 or -12)
		icon:SetTexture(r[1])
		if i ~= 2 then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
		local line = Text(page, "GameFontHighlight", r[2])
		line:SetPoint("LEFT", icon, "RIGHT", 12, 0)
		last = icon
	end
	page.height = 250
end

-- The footer's main button, per step.
local STEPS = {
	{ label = "Choose a style  >", go = function() ShowStep(2) end },
	{ label = "Next  >", go = function()
		if ns.ProfileChosen() and ns.db.enabled then
			ShowStep(3)
		else
			status:SetText("|cffff6060Pick a style first.|r")
		end
	end },
	{ label = "Start playing", go = function() Close() end },
}

function ShowStep(n)
	step = n
	for i, page in ipairs(pages) do page:SetShown(i == n) end
	for i, dot in ipairs(dots) do
		if i == n then dot:SetColorTexture(1, 1, 1) else dot:SetColorTexture(0.35, 0.35, 0.37) end
	end
	primary:SetText(STEPS[n].label)
	window.back:SetShown(n > 1)
	window.later:SetShown(n == 1)
	if n == 2 then UpdatePicked() end
	window:SetHeight(pages[n].height)
end

local function Link(parent, text, onClick)
	local b = CreateFrame("Button", nil, parent)
	local s = Text(b, "GameFontDisableSmall", text)
	s:SetPoint("LEFT")
	b:SetSize(s:GetStringWidth() + 4, 18)
	b:SetScript("OnEnter", function() s:SetTextColor(1, 1, 1) end)
	b:SetScript("OnLeave", function() s:SetTextColor(0.5, 0.5, 0.5) end)
	b:SetScript("OnClick", onClick)
	return b
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
	Flat(window, 0.96)
	tinsert(UISpecialFrames, "CinematicWelcomeDemo")

	pages = {}
	for i, build in ipairs({ BuildIntro, BuildStyles, BuildTips }) do
		local page = CreateFrame("Frame", nil, window)
		page:SetPoint("TOPLEFT", PAD, -PAD)
		page:SetPoint("BOTTOMRIGHT", -PAD, PAD)
		build(page)
		pages[i] = page
	end

	-- Footer: quiet links on the left, step dots, the main button on the right.
	primary = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	primary:SetSize(150, 26)
	primary:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	primary:SetScript("OnClick", function() STEPS[step].go() end)
	window.later = Link(window, "Not now", Close)
	window.later:SetPoint("BOTTOMLEFT", PAD, PAD + 4)
	window.back = Link(window, "< Back", function() ShowStep(step - 1) end)
	window.back:SetPoint("BOTTOMLEFT", PAD, PAD + 4)
	local off = Link(window, "Turn off", function()
		ns.SetEnabled(false)
		window:Hide()
		ns.Print("turned off. /cine brings the welcome window back to pick a profile.")
	end)
	off:SetPoint("LEFT", window.later, "RIGHT", 14, 0)
	dots = {}
	for i = 1, 3 do
		local dot = window:CreateTexture(nil, "ARTWORK")
		dot:SetSize(6, 6)
		dot:SetPoint("BOTTOM", window, "BOTTOM", (i - 2) * 14, PAD + 10)
		dots[i] = dot
	end
end

function ns.ShowWelcomeDemo()
	if not window then CreateWindow() end
	window:Show()
	ShowStep(1)
end
