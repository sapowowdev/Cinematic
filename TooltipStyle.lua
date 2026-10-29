-- The Style hub's Tooltips page: how the game's tooltips look. Their
-- background (the game's, dark or a color of your own) and its opacity, their
-- edge (the game's, a thin black line, a line in the unit's or item's color,
-- or none), their words' font, size and outline, players' and NPCs' names
-- in class or reaction colors, and the health bar under unit tooltips: where
-- it goes, its texture and height. Which lines show and when: the UI
-- Manager's Tooltips page (TooltipParts.lua).

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.tooltipStyle = true          -- the page's switch (off: these defaults, whatever it's set to)
DEFAULTS.tooltipBack = "game"         -- the background: "game", "dark" or "custom" (tooltipBackR/G/B)
DEFAULTS.tooltipBackR, DEFAULTS.tooltipBackG, DEFAULTS.tooltipBackB = 0.1, 0.08, 0.16
DEFAULTS.tooltipAlpha = 1             -- ...its opacity
DEFAULTS.tooltipEdge = "game"         -- the edge: "game", "thin" (black), "colored" (the unit's or item's) or "none"
DEFAULTS.tooltipFont = "game"         -- the words' font (ns.QUEST_ITEM_FONTS' names)
DEFAULTS.tooltipTextSize = 1          -- ...times their usual size
DEFAULTS.tooltipOutline = 0           -- ...outline: 0 none, 1 thin, 2 thick
DEFAULTS.tooltipNames = "game"        -- names: "game" or "class" (players' class, NPCs' reaction colors)
DEFAULTS.tooltipBar = "under"         -- the health bar: "under" (the game's place), "top" (over the tooltip) or "none"
DEFAULTS.tooltipBarTexture = "game"   -- ...its texture: "game", "flat" or "smooth"
DEFAULTS.tooltipBarHeight = 8         -- ...its height

local function Look()
	return ns.db and ns.db.tooltipStyle and ns.db or DEFAULTS
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local DARK = { 0.03, 0.03, 0.04 }
local BAR_TEXTURES = { flat = WHITE, smooth = "Interface\\TargetingFrame\\UI-StatusBar" }

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- The back's color, if it's one of ours (Dark, Custom).
local function BackColor(look)
	if look.tooltipBack == "custom" then
		return look.tooltipBackR, look.tooltipBackG, look.tooltipBackB
	elseif look.tooltipBack == "dark" then
		return unpack(DARK)
	end
end

-- A unit's color: a player's class, else its reaction to you (nil: unknown,
-- or secret in a fight).
local function UnitColor(unit)
	if not Readable(unit) then return end
	local ok, r, g, b = pcall(function()
		if UnitIsPlayer(unit) then
			local _, class = UnitClass(unit)
			local color = Readable(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
			if color then return color.r, color.g, color.b end
		end
		local reaction = UnitReaction(unit, "player")
		local color = Readable(reaction) and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
		if color then return color.r, color.g, color.b end
	end)
	if ok and Readable(r) then return r, g, b end
end

-- An item's quality color (nil: unknown).
local function ItemColor(link)
	if not (Readable(link) and type(link) == "string") then return end
	local ok, r, g, b = pcall(function()
		local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
			or select(3, GetItemInfo(link))
		if not Readable(quality) then return end
		if C_Item and C_Item.GetItemQualityColor then
			return C_Item.GetItemQualityColor(quality)
		end
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if color then return color.r, color.g, color.b end
	end)
	if ok and Readable(r) then return r, g, b end
end

-- Our back and edge, behind a tooltip's words: a flat color (Dark, Custom)
-- and a line round it (Thin black, In its color). On the game's nine-slice,
-- so the Tooltips page hiding that (its border part) hides ours too.
local SIDES = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
	{ "TOPRIGHT", "BOTTOMRIGHT" } }
local function MakeSkin(parent, inside)
	local skin = CreateFrame("Frame", nil, parent)
	skin:SetPoint("TOPLEFT", inside, "TOPLEFT", 1, -1)
	skin:SetPoint("BOTTOMRIGHT", inside, "BOTTOMRIGHT", -1, 1)
	skin.back = skin:CreateTexture(nil, "BACKGROUND", nil, -7)
	skin.back:SetAllPoints()
	skin.back:SetTexture(WHITE)
	skin.edges = {}
	for i, side in ipairs(SIDES) do
		local edge = skin:CreateTexture(nil, "BORDER")
		edge:SetTexture(WHITE)
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		if i <= 2 then edge:SetHeight(1) else edge:SetWidth(1) end
		skin.edges[i] = edge
	end
	return skin
end

-- color: the unit's or item's (r, g, b), for In its color.
local function DressSkin(skin, look, r, g, b)
	local alpha = tonumber(look.tooltipAlpha) or 1
	local br, bg, bb = BackColor(look)
	skin.back:SetShown(br ~= nil)
	if br then skin.back:SetVertexColor(br, bg, bb, alpha) end
	local edge = look.tooltipEdge
	local er, eg, eb = 0, 0, 0
	if edge == "colored" then er, eg, eb = r or 0.6, g or 0.6, b or 0.6 end
	for _, line in ipairs(skin.edges) do
		line:SetShown(edge == "thin" or edge == "colored")
		line:SetVertexColor(er, eg, eb, 1)
	end
	skin:SetShown(br ~= nil or edge == "thin" or edge == "colored")
end

-- The game's nine-slice: its fill (Center) at the look's opacity, or faded
-- out for a back of ours; its edge pieces faded out unless the edge is the
-- game's. Put back as it was with look nil.
local touched = setmetatable({}, { __mode = "k" }) -- texture -> true, while faded
local function SetAlphaOf(region, alpha)
	if alpha ~= 1 then
		touched[region] = true
		region:SetAlpha(alpha)
	elseif touched[region] then
		touched[region] = nil
		region:SetAlpha(1)
	end
end

local function DressSlice(slice, look)
	local ours = look and BackColor(look)
	local fill = not look and 1 or ours and 0 or tonumber(look.tooltipAlpha) or 1
	local edge = not look and 1 or look.tooltipEdge == "game" and 1 or 0
	for _, region in ipairs({ slice:GetRegions() }) do
		if region:GetObjectType() == "Texture" then
			SetAlphaOf(region, region == slice.Center and fill or edge)
		end
	end
end

-- The words: the tooltips' font objects (every tooltip's lines use them),
-- each with the look's font, size and outline; their own put back with
-- the look's font and size as the game's.
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
local FONT_OBJECTS = { "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }
local ownFonts = {}
local function DressFonts(look)
	local plain = not look or (look.tooltipFont == "game" and (tonumber(look.tooltipTextSize) or 1) == 1
		and (tonumber(look.tooltipOutline) or 0) == 0)
	for _, name in ipairs(FONT_OBJECTS) do
		local font = _G[name]
		if font and font.GetFont then
			local own = ownFonts[name]
			if plain then
				if own then
					font:SetFont(own[1], own[2], own[3])
					ownFonts[name] = nil
				end
			else
				if not own then
					local file, height, flags = font:GetFont()
					if file and height then
						own = { file, height, flags or "" }
						ownFonts[name] = own
					end
				end
				if own then
					local file = own[1]
					if ROMAN then
						for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do
							if info[1] == look.tooltipFont and info[3] then file = info[3] end
						end
					end
					font:SetFont(file, own[2] * (tonumber(look.tooltipTextSize) or 1),
						ns.OutlinedFlags and ns.OutlinedFlags(own[3], tonumber(look.tooltipOutline) or 0) or own[3])
				end
			end
		end
	end
end

-- The health bar: its place, texture and height (the game's, as first seen,
-- put back with the look's as the game's).
local barOwn
local function DressBar(bar, tooltip, look)
	if not bar or (not look and not barOwn) then return end
	if not barOwn then
		local texture = bar:GetStatusBarTexture()
		barOwn = { height = bar:GetHeight(), points = {},
			file = texture and texture:GetTexture(), atlas = texture and texture.GetAtlas and texture:GetAtlas() }
		for i = 1, tonumber(bar:GetNumPoints()) or 0 do barOwn.points[i] = { bar:GetPoint(i) } end
	end
	local where = look and look.tooltipBar or "under"
	local height = look and tonumber(look.tooltipBarHeight) or barOwn.height
	bar:ClearAllPoints()
	if where == "top" then
		bar:SetPoint("BOTTOMLEFT", tooltip, "TOPLEFT", 2, 2)
		bar:SetPoint("BOTTOMRIGHT", tooltip, "TOPRIGHT", -2, 2)
	else
		for _, point in ipairs(barOwn.points) do bar:SetPoint(unpack(point)) end
	end
	if Readable(height) then bar:SetHeight(height) end
	bar:SetAlpha(where == "none" and 0 or 1)
	local texture = look and BAR_TEXTURES[look.tooltipBarTexture]
	if texture then
		bar:SetStatusBarTexture(texture)
	elseif barOwn.atlas and bar.SetStatusBarTexture then
		local own = bar:GetStatusBarTexture()
		if own and own.SetAtlas then own:SetAtlas(barOwn.atlas) end
	elseif barOwn.file then
		bar:SetStatusBarTexture(barOwn.file)
	end
end

-- One tooltip dressed as the look says (look nil: as the game has it).
-- r, g, b: its unit's or item's color, for In its color.
local skins = setmetatable({}, { __mode = "k" })
local function Dress(tooltip, look, r, g, b)
	local slice = tooltip.NineSlice
	if not slice then return end
	DressSlice(slice, look)
	local skin = skins[tooltip]
	if not skin and look then
		skin = MakeSkin(slice, tooltip)
		skins[tooltip] = skin
	end
	if skin then
		if look then DressSkin(skin, look, r, g, b) else skin:Hide() end
	end
end

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }

-- A tooltip's unit or item color, as it is now.
local function ColorOf(tooltip)
	local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
	if ok and unit then
		local r, g, b = UnitColor(unit)
		if r then return r, g, b end
	end
	if tooltip.GetItem then
		local itemOk, _, link = pcall(tooltip.GetItem, tooltip)
		if itemOk then return ItemColor(link) end
	end
end

-- The name line of a unit's tooltip in its class or reaction color.
local function ColorName(tooltip)
	local look = Look()
	if not (ns.db and look.tooltipNames == "class") then return end
	local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
	if not (ok and unit) then return end
	local r, g, b = UnitColor(unit)
	local line = _G[tooltip:GetName() .. "TextLeft1"]
	if r and line then
		line:SetTextColor(r, g, b)
		if line.SetVertexColor then line:SetVertexColor(r, g, b) end
	end
end

local function Apply(tooltip)
	local active = ns.db and ns.db.tooltipStyle
	if not active and not next(skins) and not next(touched) then return end
	Dress(tooltip, active and ns.db or nil, ColorOf(tooltip))
end

-- Every tooltip again, and the fonts and bar (the page's settings changing).
function ns.RefreshTooltipStyle()
	local look = ns.db and ns.db.tooltipStyle and ns.db or nil
	DressFonts(look)
	if GameTooltip then DressBar(_G.GameTooltipStatusBar or GameTooltip.StatusBar, GameTooltip, look) end
	for _, name in ipairs(TOOLTIPS) do
		local tooltip = _G[name]
		if tooltip and tooltip.NineSlice then Apply(tooltip) end
	end
end

local hooked = false
local function Hook()
	if hooked then return end
	hooked = true
	for _, name in ipairs(TOOLTIPS) do
		local tooltip = _G[name]
		if tooltip and tooltip.HookScript then
			tooltip:HookScript("OnShow", Apply)
		end
	end
	-- (The game sets a tooltip's colors again as it fills it.)
	for _, name in ipairs({ "SharedTooltip_SetBackdropStyle", "GameTooltip_SetBackdropStyle" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function(tooltip) if tooltip then Apply(tooltip) end end)
		end
	end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes or "ALL", function(tooltip)
			Apply(tooltip)
			ColorName(tooltip)
		end)
	elseif GameTooltip then
		hooksecurefunc(GameTooltip, "SetUnit", function(tooltip)
			Apply(tooltip)
			ColorName(tooltip)
		end)
	end
	ns.RefreshTooltipStyle()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() Hook() end)

-- The page's preview: an enemy's tooltip with its health bar, and an epic
-- item's, dressed by the same code (and in the same font objects).
local PREVIEW_TIPS = {
	{ kind = "unit", color = { 1, 0.13, 0.13 }, health = 0.64, lines = {
		{ "Gnarlpine Ambusher", "header" }, { "Level 6 Humanoid", "text", { 1, 1, 1 } },
		{ "Gnarlpine", "text", { 1, 1, 1 } } } },
	{ kind = "item", color = { 0.64, 0.21, 0.93 }, lines = {
		{ "Staff of the Wandering Moon", "header" }, { "Item Level 40", "text", { 1, 0.82, 0 } },
		{ "Two-Hand", "text", { 1, 1, 1 } }, { "+12 Intellect", "text", { 1, 1, 1 } },
		{ "Equip: Restores 4 mana per 5 sec.", "text", { 0.12, 1, 0 } } } },
}

local function PreviewTip(holder, info)
	local tip = CreateFrame("Frame", nil, holder)
	tip:SetSize(220, 60)
	if _G.NineSliceUtil and _G.NineSliceUtil.ApplyLayoutByName then
		tip.NineSlice = CreateFrame("Frame", nil, tip, "NineSlicePanelTemplate")
		tip.NineSlice:SetAllPoints()
		if not pcall(_G.NineSliceUtil.ApplyLayoutByName, tip.NineSlice, "TooltipDefaultLayout") then
			tip.NineSlice:Hide()
			tip.NineSlice = nil
		end
	end
	if tip.NineSlice then
		local color = _G.TOOLTIP_DEFAULT_BACKGROUND_COLOR
		if color and tip.NineSlice.SetCenterColor then tip.NineSlice:SetCenterColor(color.r, color.g, color.b, 1) end
	end
	-- (Its words on a frame of their own, over the nine-slice and our skin:
	-- a child frame draws over its parent's own text.)
	local words = CreateFrame("Frame", nil, tip)
	words:SetAllPoints()
	tip.words = words -- (its level: set as it's drawn, the page moving it up after it's made)
	tip.lines = {}
	for i, line in ipairs(info.lines) do
		local text = words:CreateFontString(nil, "OVERLAY", line[2] == "header" and "GameTooltipHeaderText" or "GameTooltipText")
		text:SetText(L[line[1]])
		text:SetJustifyH("LEFT")
		if i == 1 then
			text:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, -10)
		else
			text:SetPoint("TOPLEFT", tip.lines[i - 1], "BOTTOMLEFT", 0, -2)
		end
		local c = line[3] or info.color
		text:SetTextColor(c[1], c[2], c[3])
		tip.lines[i] = text
	end
	if info.health then
		local bar = CreateFrame("StatusBar", nil, tip)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(info.health)
		bar:SetStatusBarColor(0, 0.83, 0)
		tip.bar = bar
	end
	return tip
end

function ns.MakeTooltipPreview(parent, width)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 200)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("TOPLEFT", 6, -5)
	caption:SetText(L["Preview"])
	caption.searchSkip = true
	local unit, item = PreviewTip(holder, PREVIEW_TIPS[1]), PreviewTip(holder, PREVIEW_TIPS[2])
	unit:SetPoint("TOPLEFT", holder, "TOPLEFT", 20, -40)
	item:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -20, -26)
	local function Fit(tip)
		local wide, high = 0, 16
		for _, text in ipairs(tip.lines) do
			local w, h = text:GetStringWidth(), text:GetStringHeight()
			if type(w) == "number" and w > wide then wide = w end
			high = high + (type(h) == "number" and h or 12) + 2
		end
		tip:SetSize(math.max(140, wide + 22), high)
	end
	function holder:Refresh()
		ns.StyleScene(self, 0.5, 0.85)
		local look = Look()
		for _, tip in ipairs({ unit, item }) do
			local info = tip == unit and PREVIEW_TIPS[1] or PREVIEW_TIPS[2]
			-- (Fonts set again, so the text takes the font objects' new look.)
			for i, text in ipairs(tip.lines) do
				text:SetFontObject(info.lines[i][2] == "header" and "GameTooltipHeaderText" or "GameTooltipText")
				text:SetText(L[info.lines[i][1]])
				local c = info.lines[i][3] or info.color
				text:SetTextColor(c[1], c[2], c[3])
			end
			local name = tip.lines[1]
			if tip == unit and look.tooltipNames ~= "class" then
				name:SetTextColor(1, 1, 1)
			else
				name:SetTextColor(unpack(info.color))
			end
			Fit(tip)
			Dress(tip, look, unpack(info.color))
			tip.words:SetFrameLevel((tip.NineSlice or tip):GetFrameLevel() + 5)
		end
		local bar = unit.bar
		bar:ClearAllPoints()
		if look.tooltipBar == "top" then
			bar:SetPoint("BOTTOMLEFT", unit, "TOPLEFT", 2, 2)
			bar:SetPoint("BOTTOMRIGHT", unit, "TOPRIGHT", -2, 2)
		else
			bar:SetPoint("TOPLEFT", unit, "BOTTOMLEFT", 2, -1)
			bar:SetPoint("TOPRIGHT", unit, "BOTTOMRIGHT", -2, -1)
		end
		bar:SetHeight(tonumber(look.tooltipBarHeight) or 8)
		bar:SetShown(look.tooltipBar ~= "none")
		bar:SetStatusBarTexture(BAR_TEXTURES[look.tooltipBarTexture] or BAR_TEXTURES.smooth)
		bar:SetStatusBarColor(0, 0.83, 0)
	end
	holder:SetScript("OnShow", holder.Refresh)
	return holder
end

-- The page itself.
local PRESET_KEYS = { "tooltipBack", "tooltipAlpha", "tooltipEdge", "tooltipFont", "tooltipTextSize", "tooltipOutline",
	"tooltipNames", "tooltipBar", "tooltipBarTexture", "tooltipBarHeight" }

function ns.CreateTooltipStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Tooltips"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the game's tooltips look: their background, edge and words, names in their colors and the " ..
		"health bar. Which lines show and when: the UI Manager's Tooltips page."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		ns.RefreshTooltipStyle()
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "tooltipStyle", L["Enable page"],
		L["On: tooltips look as this page says. Off: the game's own (the preview shows that too). Each " ..
		"setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "tooltipStyle")

	stack:Add(ns.StyleSceneButton(content, kit.Tooltip, kit.AddControl), "label")
	preview = ns.MakeTooltipPreview(content, 480)
	stack:Add(preview, "label")
	kit.AddControl(preview)

	rows.Presets({
		{ L["Like the game's"], L["The game's tooltips, as it draws them (the defaults)."], {} },
		{ L["Flat"], L["Dark and flat with a thin edge, names in class and reaction colors, in Arial Narrow."],
			{ tooltipBack = "dark", tooltipAlpha = 0.88, tooltipEdge = "thin", tooltipFont = "arial",
				tooltipNames = "class", tooltipBarTexture = "flat", tooltipBarHeight = 5 } },
		{ L["Colored edges"], L["The edge in a unit's class or reaction color, or an item's quality."],
			{ tooltipBack = "dark", tooltipAlpha = 0.88, tooltipEdge = "colored", tooltipFont = "arial",
				tooltipNames = "class", tooltipBarTexture = "flat" } },
		{ L["Cinematic"], L["See-through and borderless, the health bar thin along the top."],
			{ tooltipBack = "dark", tooltipAlpha = 0.65, tooltipEdge = "none", tooltipOutline = 1,
				tooltipNames = "class", tooltipBar = "top", tooltipBarTexture = "smooth", tooltipBarHeight = 3 } },
	}, PRESET_KEYS, 480)

	-- Each section: its choices first, then its sliders.
	stack:Header(content, L["Panel"])
	local last = rows.Choices(L["Background:"], "tooltipBack", {
		{ "game", L["The game's"] },
		{ "dark", L["Dark"] },
		{ "custom", L["Custom"], L["A color of your own (the swatch)."] },
	})
	rows.Swatch(last, "tooltipBack", { "tooltipBackR", "tooltipBackG", "tooltipBackB" },
		L["The background's color, for Custom."])
	rows.Choices(L["Edge:"], "tooltipEdge", {
		{ "game", L["The game's"] },
		{ "thin", L["Thin black"] },
		{ "colored", L["In its color"], L["A unit's class or reaction color, an item's quality."] },
		{ "none", L["None"] },
	})
	rows.Slider("tooltipAlpha", L["Opacity"], 20, 100, 5, "%d%%", 100, L["How see-through the background is."])

	stack:Header(content, L["Words"])
	rows.Font("tooltipFont", L["The words' font. Russian, Korean or Chinese text keeps the game's, so its letters show."])
	rows.Choices(L["Name color:"], "tooltipNames", {
		{ "game", L["The game's"] },
		{ "class", L["Class or reaction"], L["Players' names in their class color, NPCs' in their reaction to " ..
			"you (red, yellow or green)."] },
	})
	rows.Slider("tooltipTextSize", L["Text size"], 80, 140, 5, "%d%%", 100,
		L["How big the words are, next to their usual size."])
	local OUTLINES = { [0] = L["None"], L["Thin"], L["Thick"] }
	rows.Slider("tooltipOutline", L["Outline"], 0, 2, 1, function(value) return OUTLINES[value] or "" end, 1,
		L["A black border round the letters, for see-through backgrounds."])

	stack:Header(content, L["Health bar"])
	rows.Choices(L["Position:"], "tooltipBar", {
		{ "under", L["Under it"], L["Under the tooltip, where the game puts it."] },
		{ "top", L["Along the top"] },
		{ "none", L["None"] },
	})
	local function BarOn(db) return db.tooltipStyle and db.tooltipBar ~= "none" end
	rows.Choices(L["Texture:"], "tooltipBarTexture", {
		{ "game", L["The game's"] },
		{ "flat", L["Flat"] },
		{ "smooth", L["Smooth"] },
	}, BarOn)
	rows.Slider("tooltipBarHeight", L["Height"], 2, 12, 1, "%d", nil, L["The health bar's height."], BarOn)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Tooltip Style", L["Tooltips"])
end
