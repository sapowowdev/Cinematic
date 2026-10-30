-- The Style hub's General page: a switch for every Style page at once (off:
-- each shows the game's look), the settings the pages share (bar texture,
-- font, outline: StylePages.lua's ns.StyleLook), a preview of several pages'
-- parts in turn, and which pages follow it or have a setting of their own.

local _, ns = ...
local L = ns.L

-- The pages that share settings, as the list shows them: name, the page to
-- open (ns.OpenOptions), its shared settings.
local PAGES = {
	{ "Unit frames", "Unit Style", { "ufTexture", "ufFont", "ufOutline", "ufBorder" } },
	{ "Raid frames", "Raid Style", { "rfTexture", "rfFont", "rfOutline", "rfBorder" } },
	{ "Personal Resource Display", "Personal Style", { "prdTexture", "prdBorder" } },
	{ "Tooltips", "Tooltip Style", { "tooltipBarTexture", "tooltipFont", "tooltipOutline", "tooltipEdge" } },
	{ "Cast bars", "Cast Bar Style", { "plateCastFill", "plateCastFont", "plateCastOutline", "plateCastBorder" } },
	{ "Chat bubbles", "Bubble Style", { "bubblesFont", "bubblesOutline", "bubblesEdge" } },
	{ "Dialogue", "Quest Talk Style", { "questTalkFont", "questTalkOutline" } },
	{ "Quest item button", "Quest Item Style", { "questItemFont", "questItemOutline", "questItemFrame" } },
	{ "Roll Vision", "Roll Style", { "rollBarTexture", "rollFont", "rollOutline" } },
	{ "Combat Vision", "Combat Style", { "combatFont", "combatOutline" } },
}
local KIND_NAMES = { texture = "Texture", font = "Font", outline = "Outline", border = "Border" }

-- Every page's look again (General's settings changing).
local function RefreshAll()
	for _, refresh in ipairs({ ns.RefreshPersonalStyle, ns.RefreshTooltipStyle, ns.RefreshBubbleStyle,
		ns.RefreshQuestTalkStyle, ns.RefreshQuestItemStyle, ns.RefreshRollStyle, ns.RefreshPlateCastStyle,
		ns.RefreshUnitStyle, ns.RefreshRaidStyle }) do
		if refresh then pcall(refresh) end
	end
end
ns.RefreshAllStyles = RefreshAll

-- A nameplate, for the preview: an enemy's name in General's font and
-- outline, its health bar in General's texture and border (the game's
-- nameplate fill and its dark ground with General at the game's), and a
-- cast bar under it as the Cast bars page dresses it.
local PLATE_FILL, PLATE_GROUND = "UI-HUD-CoolDownManager-Bar", "UI-HUD-CoolDownManager-Bar-BG"
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

function ns.MakeGeneralPlatePreview(parent, width)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 200)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("TOPLEFT", 6, -5)
	caption:SetText(L["Preview"])
	caption.searchSkip = true
	local plate = CreateFrame("Frame", nil, holder)
	plate:SetSize(140, 40)
	plate:SetScale(1.6)
	plate:SetPoint("CENTER", holder, "CENTER", 0, 10)
	local health = CreateFrame("StatusBar", nil, plate)
	health:SetSize(140, 10)
	health:SetPoint("TOP", plate, "TOP", 0, -14)
	health:SetMinMaxValues(0, 1)
	health:SetValue(0.7)
	local ground = health:CreateTexture(nil, "BACKGROUND")
	ground:SetPoint("TOPLEFT", -2, 2)
	ground:SetPoint("BOTTOMRIGHT", 2, -2)
	local back = health:CreateTexture(nil, "BACKGROUND", nil, -1)
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.6)
	local border = ns.MakeStyleEdges(health)
	local name = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("BOTTOM", health, "TOP", 0, 3)
	name:SetText(L["Gnoll Brute"])
	name.searchSkip = true
	local own = { name:GetFont() }
	local cast = ns.MakePlateCastSample and ns.MakePlateCastSample(plate)
	if cast then cast:SetPoint("TOP", health, "BOTTOM", 0, -3) end
	function holder:Refresh()
		ns.StyleScene(self, 0.55, 0.85)
		local db = ns.db
		local on = db and db.styleGeneral
		local general = on and db or ns.DEFAULTS
		-- (Its fill: General's texture, or the game's nameplate fill.)
		if not ns.SetBarTexture(health, on and general.styleTexture or "game") then
			local game = HasAtlas(PLATE_FILL) and PLATE_FILL or "Interface\\TargetingFrame\\UI-StatusBar"
			health:SetStatusBarTexture(game)
			health:GetStatusBarTexture():SetDesaturated(false)
		end
		health:SetStatusBarColor(0.85, 0.12, 0.1)
		-- (Its border: General's, or the game's ground with its outline.)
		local kind, size, r, g, b = ns.StyleBorder(general, "styleBorder")
		local game = kind == "game"
		ground:SetShown(game)
		if game then
			if HasAtlas(PLATE_GROUND) then ground:SetAtlas(PLATE_GROUND) else ground:SetColorTexture(0, 0, 0, 0.7) end
		end
		back:SetShown(not game)
		border:SetShown(kind == "line")
		if kind == "line" then ns.DressStyleEdges(border, size, r, g, b, 1, true) end
		-- (Its name: General's font and outline.)
		local file, height, flags = own[1], own[2], own[3]
		if file and height then
			local font, outline = general.styleFont, tonumber(general.styleOutline) or -1
			if ROMAN then
				file = ns.StyleFontFile(font) or file
			end
			if outline >= 0 and ns.OutlinedFlags then flags = ns.OutlinedFlags(flags, outline) end
			name:SetFont(file, height, flags or "")
			name:SetText(L["Gnoll Brute"])
		end
		name:SetTextColor(1, 0.25, 0.2)
		if cast then cast:Refresh() end
	end
	holder:SetScript("OnShow", holder.Refresh)
	return holder
end

-- The preview: one big screen showing the pages' own previews in turn, in
-- this order, a new one every few seconds fading in over the last; arrows
-- step back and forth (and start the wait again). Each is held to one size
-- (what's past it clipped).
local CELLS = {
	{ "Unit frames", "MakeUnitStylePreview" },
	{ "Raid frames", "MakeRaidStylePreview" },
	{ "Nameplate", "MakeGeneralPlatePreview" },
	{ "Personal Resource Display", "MakePersonalPreview" },
	{ "Tooltips", "MakeTooltipPreview" },
	{ "Chat bubbles", "MakeBubblePreview" },
	{ "Dialogue", "MakeQuestTalkPreview" },
	{ "Roll Vision", "MakeRollPreview" },
	{ "Quest item button", "MakeQuestItemPreview" },
	{ "Combat Vision", "MakeCombatPreview", sized = true }, -- (sized: given the screen's height)
}
local ROTATE_SECONDS, FADE_SECONDS = 6, 0.6
local NAME_H = 24 -- (the page's name over the screen; the screen as high as every Style preview's)

local function MakePreview(parent, width)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, NAME_H + ns.StylePreviewHeight())
	local name = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("TOPLEFT", 0, -5)
	name.searchSkip = true
	local count = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	count:SetPoint("LEFT", name, "RIGHT", 6, 0)
	count.searchSkip = true
	local cells = {}
	for _, info in ipairs(CELLS) do
		local make = ns[info[2]]
		if make then
			local cell = make(holder, width, info.sized and ns.StylePreviewHeight() or nil)
			cell:SetScript("OnShow", nil) -- (drawn by holder:Refresh)
			cell:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -NAME_H)
			cell:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -NAME_H) -- (as wide as the page makes it)
			if cell.SetClipsChildren then cell:SetClipsChildren(true) end
			-- (Held to the screen's size after each drawing, its own too: Roll
			-- Vision's sizes itself to its cards as they tick.)
			local own = cell.Refresh
			function cell:Refresh(...)
				if own then own(self, ...) end
				local height = ns.StylePreviewHeight()
				if math.abs(self:GetHeight() - height) > 0.5 then
					self:SetHeight(height)
				end
				ns.RecutStyleScene(self) -- (its shape: the screen's width may have changed too)
			end
			cell:Hide()
			cells[#cells + 1] = { frame = cell, name = L[info[1]] }
		end
	end
	local current, waited, fading = 1, 0, nil -- (fading: the one going, under the one coming in)
	local function ShowOnly(index)
		for i, other in ipairs(cells) do
			other.frame:SetShown(i == index or (fading and i == fading.index))
		end
	end
	function holder:Refresh()
		local cell = cells[current]
		if not cell then return end
		ShowOnly(current)
		name:SetText(cell.name)
		count:SetText(("%d / %d"):format(current, #cells))
		cell.frame:Refresh()
	end
	local function EndFade()
		if not fading then return end
		cells[fading.index].frame:Hide()
		fading = nil
		local cell = cells[current]
		if cell then cell.frame:SetAlpha(1) end
	end
	local function Step(by)
		if #cells < 2 then return end
		EndFade()
		local was = current
		current = (current - 1 + by) % #cells + 1
		waited = 0
		-- (The new one over the old, from clear.)
		local base = holder:GetFrameLevel()
		cells[was].frame:SetFrameLevel(base + 1)
		cells[current].frame:SetFrameLevel(base + 10)
		cells[current].frame:SetAlpha(0)
		fading = { index = was, time = 0 }
		holder:Refresh()
	end
	-- (The arrows, in the screen's top right as the other previews' buttons,
	-- over the pages fading in.)
	for _, side in ipairs({ { 30, "Prev", -1 }, { 6, "Next", 1 } }) do
		local arrow = CreateFrame("Button", nil, holder)
		arrow:SetSize(24, 24)
		arrow:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -side[1], -NAME_H - 4)
		arrow:SetFrameLevel(holder:GetFrameLevel() + 30)
		local art = "Interface\\Buttons\\UI-SpellbookIcon-" .. side[2] .. "Page-"
		arrow:SetNormalTexture(art .. "Up")
		arrow:SetPushedTexture(art .. "Down")
		arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		arrow:SetScript("OnClick", function() Step(side[3]) end)
		if side[3] < 0 then holder.prevArrow = arrow end
	end
	holder:SetScript("OnShow", function(self) EndFade(); waited = 0; self:Refresh() end)
	holder:SetScript("OnUpdate", function(_, elapsed)
		if fading then
			fading.time = fading.time + elapsed
			local cell = cells[current]
			if fading.time >= FADE_SECONDS then
				EndFade()
			elseif cell then
				cell.frame:SetAlpha(fading.time / FADE_SECONDS)
			end
		end
		waited = waited + elapsed
		if waited >= ROTATE_SECONDS then Step(1) end
	end)
	return holder
end

-- The pages list: each page, whether it follows General, and a button to
-- put it back on General.
local function PageStatus(keys)
	local db = ns.GetDB()
	local own = {}
	for _, key in ipairs(keys) do
		if db and not ns.IsGeneralStyle(db[key]) then
			local entry = ns.SHARED_STYLE[key]
			own[#own + 1] = L[KIND_NAMES[entry and entry.kind] or "Texture"]
		end
	end
	return own
end


function ns.CreateGeneralStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["General"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["Every Style page at once: a switch for them all, and the settings they share. Each page's shared " ..
		"settings start on General and follow it; change one on its page and it's that page's own."])

	local preview -- (below: drawn again as each setting changes)
	local pageRows = {}
	local function Changed()
		RefreshAll()
		if preview then preview:Refresh() end
		for _, row in ipairs(pageRows) do row:Refresh() end
	end

	local switch = kit.PageSwitch(content, "styleGeneral", L["Enable Style"],
		L["On: every Style page looks as it says. Off: none of them do; everything shows the game's look. " ..
		"Each page keeps its settings for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "styleGeneral")

	preview = MakePreview(content, 480)
	preview.headHeight = NAME_H -- (its name over the screen: StylePages.lua)
	stack:Add(preview, "label")
	local pop = ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	-- (left of the arrows, not over them)
	pop:ClearAllPoints()
	pop:SetPoint("RIGHT", preview.prevArrow, "LEFT", -6, 0)
	kit.AddControl(preview)

	rows.PresetMenu({
		{ L["Like the game's"], L["Each page as its own defaults have it (the game's look)."], {} },
		{ L["Clean"], L["Flat bars and Arial Narrow, thinly outlined."],
			{ styleTexture = "flat", styleFont = "arial", styleOutline = 1 } },
		{ L["Cinematic"], L["Soft bars and Friz Quadrata, thinly outlined."],
			{ styleTexture = "soft", styleFont = "friz", styleOutline = 1 } },
		{ L["Glass"], L["Glass bars, the game's fonts."], { styleTexture = "glass" } },
	}, { "styleTexture", "styleFont", "styleOutline", "styleBorder", "styleBorderSize", "styleBorderR", "styleBorderG",
		"styleBorderB" })

	stack:Header(content, L["Shared look"])
	rows.Texture(L["Bar texture:"], "styleTexture", L["Every page's bars that follow General. The game's: " ..
		"each page's own. Below the game's own few: any other addon shares (through LibSharedMedia)."], nil,
		{ 0.25, 0.75, 0.3 })
	rows.Font("styleFont", L["Every page's words that follow General. The game's: each page's own. Russian, " ..
		"Korean or Chinese text keeps the game's, so its letters show."])
	rows.Outline("styleOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"] },
		L["A black border round the letters, on every page that follows General. The game's: as each " ..
		"page's default has it."], nil, L["The game's"])
	rows.Border(L["Border:"], "styleBorder", { game = true }, L["The border round every page's " ..
		"bars, panels and buttons that follow General. The game's: as each page's default has it. Custom: " ..
		"its thickness and color under it."])

	-- The game's own nameplate Style (retail's Options > Nameplates), shown
	-- for what it is: greyed, as we leave it alone. Only where the client
	-- has it.
	local okStyle, gameStyle = pcall(GetCVar, "nameplateStyle")
	if okStyle and gameStyle ~= nil then
		local STYLES = { [0] = "Modern", "Thin Bars", "Blocky Bars", "Clean Health", "Blocky Cast", "Legacy Red" }
		local styleName = stack:Add(kit.Label(content, "GameFontHighlight", L["Game's nameplate Style:"]), "label")
		styleName:SetSize(150, 30)
		styleName:SetJustifyV("MIDDLE")
		local box = ns.PanelButton(content)
		box:SetSize(200, 22)
		box:SetPoint("LEFT", styleName, "RIGHT", 4, 0)
		box:Disable()
		kit.Tooltip(box, L["The game's own setting (Options, Nameplates, Style): the size and color of its plates' " ..
			"bars, all in the same texture. Shown here for what it is; Cinematic doesn't change it."])
		box:SetMotionScriptsWhileDisabled(true) -- (its tooltip still shows)
		box.Refresh = function(self)
			local ok, value = pcall(GetCVar, "nameplateStyle")
			local name = ok and STYLES[tonumber(value) or -1]
			self:SetText(name and L[name] or tostring(value))
		end
		box.pageSwitch = false
		kit.AddControl(box)
	end

	stack:Header(content, L["Pages"])
	stack:Help(content, L["Which pages follow General. A page with a setting of its own shows which; Use " ..
		"General puts them all back on General. The page's name opens it."])
	for _, page in ipairs(PAGES) do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(480, 22)
		stack:Add(row, "label")
		local open = CreateFrame("Button", nil, row)
		open:SetSize(160, 22)
		open:SetPoint("LEFT")
		local name = open:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("LEFT")
		name:SetText(L[page[1]])
		open:SetScript("OnClick", function() ns.OpenOptions(page[2]) end)
		open:SetScript("OnEnter", function() name:SetTextColor(1, 0.82, 0) end)
		open:SetScript("OnLeave", function() name:SetTextColor(1, 1, 1) end)
		local status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		status:SetPoint("LEFT", open, "RIGHT", 4, 0)
		status.searchSkip = true
		local back = ns.PanelButton(row)
		back:SetSize(100, 20)
		back:SetPoint("LEFT", status, "RIGHT", 10, 0)
		back:SetText(L["Use General"])
		kit.Tooltip(back, L["This page's shared settings back on General."])
		back:SetScript("OnClick", function()
			local db = ns.GetDB()
			for _, key in ipairs(page[3]) do db[key] = ns.DEFAULTS[key] end
			Changed()
			kit.Refresh()
		end)
		function row:Refresh()
			local own = PageStatus(page[3])
			if #own == 0 then
				status:SetText(L["Follows General"])
				status:SetTextColor(0.6, 0.6, 0.6)
				back:Hide()
			else
				status:SetText(L["Its own:"] .. " " .. table.concat(own, ", "))
				status:SetTextColor(1, 0.82, 0)
				back:Show()
			end
		end
		pageRows[#pageRows + 1] = row
	end

	local shown = kit.PageShown(kit.Refresh, content)
	canvas:SetScript("OnShow", function()
		for _, row in ipairs(pageRows) do row:Refresh() end
		shown()
	end)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Style General", L["General"])
end
