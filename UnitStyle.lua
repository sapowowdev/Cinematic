-- The Style hub's Unit frames page: how the game's player, target, focus,
-- pet, target of target and party frames (unless the game draws the party
-- as raid frames) look: their bars' texture, border and
-- background, the health bar's and name's colors, the name's font, outline
-- and size, and the portrait (the game's, or a player's class icon). A
-- Default tab, and a tab for each frame that follows Default until its "Use
-- default settings" is unticked (as Heal Vision's role tabs do): then the
-- frame has its own copy of each setting (<key>_<FRAME>). Which parts show:
-- the UI Manager's Unit Frames page (Frames.lua).

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.ufStyle = true

-- Whether the game draws the party as raid frames (retail's Edit Mode
-- setting, the classic clients' useCompactPartyFrames): then the Party tab
-- has nothing to dress (the Raid frames page's, those).
function ns.RaidStyleParty()
	local manager = _G.EditModeManagerFrame
	if manager and manager.UseRaidStylePartyFrames then
		local ok, raid = pcall(manager.UseRaidStylePartyFrames, manager)
		if ok and type(raid) == "boolean" then return raid end
	end
	local ok, raid = pcall(GetCVarBool, "useCompactPartyFrames")
	return ok and raid == true
end

-- The party's own frames (when they aren't raid-style): the classic
-- clients' by name, retail's in PartyFrame (the raid-style ones apart).
local function PartyFrames()
	local list = {}
	if ns.RaidStyleParty() then return list end
	for i = 1, 4 do
		local frame = _G["PartyMemberFrame" .. i]
		if frame then list[#list + 1] = frame end
	end
	local holder = _G.PartyFrame
	if holder and not (holder.IsForbidden and holder:IsForbidden()) then
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= _G.CompactPartyFrame then list[#list + 1] = child end
		end
	end
	return list
end

-- Each frame (its id, as the settings name it) and the game's frames it
-- covers (their names, or a function giving the frames themselves).
local FRAMES = {
	{ "PLAYER", "Player", { "PlayerFrame" } },
	{ "TARGET", "Target", { "TargetFrame" } },
	{ "FOCUS", "Focus", { "FocusFrame" } },
	{ "PET", "Pet", { "PetFrame" } },
	{ "TOT", "Target of target", { "TargetFrameToT", "FocusFrameToT" } },
	{ "PARTY", "Party", PartyFrames },
}

-- The game's frames an entry covers, now.
local function GameFrames(info)
	if type(info[3]) == "function" then return info[3]() end
	local list = {}
	for _, name in ipairs(info[3]) do
		if _G[name] then list[#list + 1] = _G[name] end
	end
	return list
end

-- The settings, Default's (and each frame's own, <key>_<FRAME>, starting as
-- Default's). Texture, border, font and outline start on the General page.
local KEYS = {
	ufTexture = "general",       -- the bars' fill (ns.StyleTexturePath)
	ufBorder = "general",        -- their border: "game", "none", "thin", "thick", "custom" (ns.StyleBorder)
	ufBorderSize = 1, ufBorderR = 0, ufBorderG = 0, ufBorderB = 0,
	ufBack = 0.5,                -- the dark behind them, with a border of ours
	ufHealthColor = "game",      -- the health bar: "game", "class" (class or reaction) or "custom"
	ufHealthR = 0.2, ufHealthG = 0.8, ufHealthB = 0.4,
	ufNameColor = "game",        -- the name: "game", "class" (class or reaction) or "white"
	ufFont = "general",          -- the name's font (ns.QUEST_ITEM_FONTS' names)
	ufOutline = -1,              -- ...outline: 0 none, 1 thin, 2 thick (-1: General's)
	ufNameSize = 1,              -- ...times its usual size
	ufPortrait = "game",         -- "game" (their face) or "class" (a player's class icon)
}
local SHARED = { ufTexture = { "texture", "game" }, ufFont = { "font", "game" }, ufOutline = { "outline", 0 },
	ufBorder = { "border", "game" } }

local function Share(key, suffix)
	local entry = SHARED[key]
	if not entry then return end
	local shared = ns.SHARED_STYLE
	shared[key .. suffix] = { kind = entry[1], own = entry[2] }
	if entry[1] == "border" then
		shared[key .. "Size" .. suffix] = { kind = "borderSize", follows = key .. suffix }
		for _, channel in ipairs({ "R", "G", "B" }) do
			shared[key .. channel .. suffix] = { kind = "border" .. channel, follows = key .. suffix }
		end
	end
end

for key, value in pairs(KEYS) do DEFAULTS[key] = value end
for key in pairs(SHARED) do Share(key, "") end
for _, frame in ipairs(FRAMES) do
	local id = frame[1]
	DEFAULTS["ufOwn_" .. id] = false
	for key, value in pairs(KEYS) do DEFAULTS[key .. "_" .. id] = value end
	for key in pairs(SHARED) do Share(key, "_" .. id) end
end
-- (A border's own size and color, per frame: the shared list's border entry
-- reads <key>Size, <key>R... under the frame's suffix.)
for _, frame in ipairs(FRAMES) do
	for _, part in ipairs({ "Size", "R", "G", "B" }) do
		ns.SHARED_STYLE["ufBorder_" .. frame[1] .. part] = ns.SHARED_STYLE["ufBorder" .. part .. "_" .. frame[1]]
		DEFAULTS["ufBorder_" .. frame[1] .. part] = DEFAULTS["ufBorder" .. part .. "_" .. frame[1]]
	end
end

-- A frame's look: its own settings while its "Use default settings" is
-- unticked, else Default's; each through the Style pages' look (General's,
-- and the game's with the page or General off).
local views = {}
local function View(id)
	local view = views[id]
	if not view then
		view = setmetatable({}, { __index = function(_, key)
			local look = ns.StyleLook("ufStyle")
			local db = ns.db
			if db and ns.StyleOn("ufStyle") and db["ufOwn_" .. id] then
				-- (ufBorderSize_PLAYER and the like: the border's parts by its key.)
				local own = key:match("^ufBorder(%u%l*)$")
				if own and own ~= "" then return look["ufBorder_" .. id .. own] end
				return look[key .. "_" .. id]
			end
			return look[key]
		end })
		views[id] = view
	end
	return view
end
ns.UnitStyleView = View

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
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

local function HealthColor(view, unit)
	if view.ufHealthColor == "class" then
		return UnitColor(unit)
	elseif view.ufHealthColor == "custom" then
		return view.ufHealthR, view.ufHealthG, view.ufHealthB
	end
end

-- What we've changed, to put back: bar -> its own fill and color; skins.
local own = setmetatable({}, { __mode = "k" })
local skins = setmetatable({}, { __mode = "k" })
local dressing = false -- (our own setters: not the game's, for the hooks)

local function OwnOf(object)
	local saved = own[object]
	if not saved then
		saved = {}
		if object.GetStatusBarTexture then
			local fill = object:GetStatusBarTexture()
			saved.atlas = fill and fill.GetAtlas and fill:GetAtlas()
			saved.file = fill and fill:GetTexture()
			local ok, r, g, b = pcall(object.GetStatusBarColor, object)
			if ok and Readable(r) then saved.color = { r, g, b } end
		elseif object.GetFontObject then
			saved.object = object:GetFontObject()
			local r, g, b = object:GetTextColor()
			if Readable(r) then saved.color = { r, g, b } end
		end
		own[object] = saved
	end
	return saved
end

-- Our border and background behind a bar (for any border but the game's).
local function Skin(bar)
	local skin = skins[bar]
	if not skin then
		skin = CreateFrame("Frame", nil, bar)
		skin:SetAllPoints()
		skin:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
		skin.back = skin:CreateTexture(nil, "BACKGROUND", nil, -8)
		skin.back:SetAllPoints()
		skin.back:SetColorTexture(0, 0, 0, 1)
		skin.border = ns.MakeStyleEdges(skin)
		skins[bar] = skin
	end
	return skin
end

local function DressSkin(skin, view)
	local kind, size, r, g, b = ns.StyleBorder(view, "ufBorder")
	skin:SetShown(kind ~= "game")
	skin.back:SetAlpha(tonumber(view.ufBack) or 0.5)
	skin.border:SetShown(kind == "line")
	if kind == "line" then ns.DressStyleEdges(skin.border, size, r, g, b, 1, true) end
end

-- A bar's fill as view says (view nil: the game's); color: its color, or
-- nil for the game's.
local function DressBar(bar, view, r, g, b)
	if not (bar and bar.SetStatusBarTexture) or (bar.IsForbidden and bar:IsForbidden()) then return end
	local saved = OwnOf(bar)
	dressing = true
	if view and ns.SetBarTexture(bar, view.ufTexture) then
		saved.ours = true
	elseif saved.ours then
		saved.ours = nil
		local fill = saved.atlas or saved.file
		if fill then bar:SetStatusBarTexture(fill) end
		local now = bar:GetStatusBarTexture()
		if now and now.SetDesaturated then now:SetDesaturated(false) end
	end
	if r then
		local fill = bar:GetStatusBarTexture()
		if fill and fill.SetDesaturated then fill:SetDesaturated(true) end -- (a colored fill of the game's tints clean)
		bar:SetStatusBarColor(r, g, b)
		saved.colored = true
	elseif saved.colored then
		saved.colored = nil
		if saved.color then bar:SetStatusBarColor(unpack(saved.color)) end
		if not saved.ours then
			local fill = bar:GetStatusBarTexture()
			if fill and fill.SetDesaturated then fill:SetDesaturated(false) end
		end
	end
	if view and view.ufBorder ~= "game" or skins[bar] then
		local skin = Skin(bar)
		if view then DressSkin(skin, view) else skin:Hide() end
	end
	dressing = false
end

-- The name as view says: its color, font, outline and size.
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
local function DressName(text, view, unit)
	if not (text and text.SetTextColor) or (text.IsForbidden and text:IsForbidden()) then return end
	local saved = OwnOf(text)
	local color = view and view.ufNameColor
	local r, g, b
	if color == "class" then
		r, g, b = UnitColor(unit)
	elseif color == "white" then
		r, g, b = 1, 1, 1
	end
	if r then
		text:SetTextColor(r, g, b)
		saved.colored = true
	elseif saved.colored and saved.color then
		text:SetTextColor(unpack(saved.color))
		saved.colored = nil
	end
	local font = view and view.ufFont or "game"
	local outline = view and tonumber(view.ufOutline) or 0
	local size = view and tonumber(view.ufNameSize) or 1
	if font == "game" and outline <= 0 and size == 1 then
		if saved.fonted and saved.object then
			text:SetFontObject(saved.object)
			pcall(function() text:SetText(text:GetText()) end)
			saved.fonted = nil
		end
		return
	end
	local object = saved.object
	if not object then return end
	local file, height, flags = object:GetFont()
	if not (file and height) then return end
	if ROMAN then
		for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do
			if info[1] == font and info[3] then file = info[3] end
		end
	end
	if outline >= 0 and ns.OutlinedFlags then flags = ns.OutlinedFlags(flags, outline) end
	if ns.SetPlateNameFont then
		ns.SetPlateNameFont(text, object, file, height, size, flags or "")
	else
		pcall(text.SetFont, text, file, height * size, flags or "")
	end
	saved.fonted = true
end

-- The portrait: a player's class icon, or their face (the game's).
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local function DressPortrait(portrait, view, unit)
	if not (portrait and portrait.SetTexture) or (portrait.IsForbidden and portrait:IsForbidden()) then return end
	local want = view and view.ufPortrait == "class"
	local class
	if want and Readable(unit) then
		local ok, isPlayer = pcall(UnitIsPlayer, unit)
		if ok and Readable(isPlayer) and isPlayer then
			local _, file = UnitClass(unit)
			class = Readable(file) and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[file] and file
		end
	end
	local saved = OwnOf(portrait)
	if class then
		portrait:SetTexture(CLASS_ICONS)
		portrait:SetTexCoord(unpack(_G.CLASS_ICON_TCOORDS[class]))
		saved.iconed = true
	elseif saved.iconed then
		saved.iconed = nil
		portrait:SetTexCoord(0, 1, 0, 1)
		if Readable(unit) and SetPortraitTexture then pcall(SetPortraitTexture, portrait, unit) end
	end
end

-- The parts of one of the game's frames.
local function Parts(frame)
	return frame.healthbar or frame.HealthBar, frame.manabar or frame.ManaBar, frame.name or frame.Name,
		frame.portrait or frame.Portrait
end

local hooked = setmetatable({}, { __mode = "k" })
local Dress

-- One frame (id) as the page says, every game frame it covers.
local function DressFrame(info)
	local active = ns.StyleOn("ufStyle")
	local view = active and View(info[1]) or nil
	for _, frame in ipairs(GameFrames(info)) do
		if not (frame.IsForbidden and frame:IsForbidden()) then
			local unit = frame.unit
			local health, power, text, portrait = Parts(frame)
			local r, g, b
			if view then r, g, b = HealthColor(view, unit) end
			DressBar(health, view, r, g, b)
			DressBar(power, view)
			DressName(text, view, unit)
			DressPortrait(portrait, view, unit)
			-- (The game sets these again as the unit changes: ours after it.)
			if not hooked[frame] then
				hooked[frame] = true
				for _, bar in ipairs({ health or false, power or false }) do
					if bar and bar.SetStatusBarTexture then
						hooksecurefunc(bar, "SetStatusBarTexture", function() if not dressing then Dress(info) end end)
					end
				end
				if health and health.SetStatusBarColor then
					hooksecurefunc(health, "SetStatusBarColor", function() if not dressing then Dress(info) end end)
				end
			end
		end
	end
end

function Dress(info)
	if dressing then return end
	DressFrame(info)
end

-- Every frame again (the page's settings changing, a new target...).
function ns.RefreshUnitStyle()
	if not ns.db then return end
	for _, info in ipairs(FRAMES) do DressFrame(info) end
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET",
	"UNIT_DISPLAYPOWER", "UNIT_FACTION", "GROUP_ROSTER_UPDATE", "EDIT_MODE_LAYOUTS_UPDATED", "CVAR_UPDATE" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event, name)
	-- (Of the game's settings, only the classic clients' raid-style party one.)
	if event == "CVAR_UPDATE" and name ~= "useCompactPartyFrames" then return end
	ns.RefreshUnitStyle()
end)
if hooksecurefunc and type(_G.UnitFramePortrait_Update) == "function" then
	hooksecurefunc("UnitFramePortrait_Update", function(frame)
		for _, info in ipairs(FRAMES) do
			for _, each in ipairs(GameFrames(info)) do
				if each == frame then
					local _, _, _, portrait = Parts(frame)
					DressPortrait(portrait, ns.StyleOn("ufStyle") and View(info[1]) or nil, frame.unit)
				end
			end
		end
	end)
end

-- The preview: the five frames as small mock-ups, each dressed by its own
-- look (a frame clicked opens its tab: onPick(id)).
local SAMPLES = {
	PLAYER = { name = "Vedeth", x = 14, y = -30, w = 150, class = "WARRIOR", health = 0.86, power = { 1, 0, 0 }, amount = 0.4 },
	TARGET = { name = "Turnip Punching Bag", x = 270, y = -30, w = 150, reaction = 2, health = 0.62,
		power = { 1, 1, 0 }, amount = 1, flip = true },
	FOCUS = { name = "Maketh", x = 300, y = -112, w = 110, class = "MAGE", health = 0.95, power = { 0, 0.55, 1 },
		amount = 0.7, flip = true },
	PET = { name = "Wolf", x = 30, y = -118, w = 80, reaction = 5, health = 1, power = { 1, 1, 0 }, amount = 0.5,
		small = true },
	PARTY = { name = "Lumen", x = 150, y = -146, w = 90, class = "PALADIN", health = 0.7, power = { 0, 0.55, 1 },
		amount = 0.8, small = true },
	TOT = { name = "Vedeth", x = 400, y = -64, w = 70, class = "WARRIOR", health = 0.86, power = { 1, 0, 0 },
		amount = 0.4, small = true },
}
local GAME_FILL = "Interface\\TargetingFrame\\UI-StatusBar"

local function SampleColor(sample)
	if sample.class then
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[sample.class]
		if color then return color.r, color.g, color.b end
	end
	local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[sample.reaction or 4]
	if color then return color.r, color.g, color.b end
	return 1, 0.2, 0.2
end

function ns.MakeUnitStylePreview(parent, width, onPick)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 190)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("TOPLEFT", 6, -5)
	caption:SetText(L["Preview"])
	caption.searchSkip = true
	local samples = {}
	for _, info in ipairs(FRAMES) do
		local id, sample = info[1], SAMPLES[info[1]]
		local unit = CreateFrame("Button", nil, holder)
		local size = sample.small and 22 or 34
		unit:SetSize(sample.w + size + 6, size + 6)
		unit:SetPoint("TOPLEFT", holder, "TOPLEFT", sample.x, sample.y)
		unit.portrait = unit:CreateTexture(nil, "ARTWORK")
		unit.portrait:SetSize(size, size)
		unit.portrait:SetPoint(sample.flip and "RIGHT" or "LEFT", unit, sample.flip and "RIGHT" or "LEFT", 0, 0)
		unit.name = unit:CreateFontString(nil, "OVERLAY", sample.small and "GameFontNormalSmall" or "GameFontNormal")
		unit.health = CreateFrame("StatusBar", nil, unit)
		unit.health:SetSize(sample.w, sample.small and 6 or 10)
		unit.power = CreateFrame("StatusBar", nil, unit)
		unit.power:SetSize(sample.w, sample.small and 3 or 5)
		local side = sample.flip and "RIGHT" or "LEFT"
		unit.health:SetPoint("TOP" .. side, unit.portrait, "TOP" .. (sample.flip and "LEFT" or "RIGHT"),
			sample.flip and -4 or 4, -(sample.small and 9 or 13))
		unit.power:SetPoint("TOP", unit.health, "BOTTOM", 0, -2)
		unit.name:SetPoint("BOTTOM" .. side, unit.health, "TOP" .. side, 0, 2)
		for _, bar in ipairs({ unit.health, unit.power }) do
			bar:SetMinMaxValues(0, 1)
			local ground = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
			ground:SetAllPoints()
			ground:SetColorTexture(0, 0, 0, 0.5)
			bar.game = ground
		end
		unit.health:SetValue(sample.health)
		unit.power:SetValue(sample.amount)
		unit.mark = unit:CreateTexture(nil, "OVERLAY")
		unit.mark:SetPoint("TOPLEFT", -3, 3)
		unit.mark:SetPoint("BOTTOMRIGHT", 3, -3)
		unit.mark:SetColorTexture(1, 0.82, 0, 0.12)
		unit:SetScript("OnClick", function() if onPick then onPick(id) end end)
		unit.id, unit.sample = id, sample
		samples[#samples + 1] = unit
	end
	function holder:Refresh(editing)
		ns.StyleScene(self, 0.55, 0.85)
		for _, unit in ipairs(samples) do
			local view, sample = View(unit.id), unit.sample
			unit.mark:SetShown(editing == unit.id)
			-- (The bars: the look's fill, else the game's look.)
			for i, bar in ipairs({ unit.health, unit.power }) do
				if not ns.SetBarTexture(bar, view.ufTexture) then
					bar:SetStatusBarTexture(GAME_FILL)
					bar:GetStatusBarTexture():SetDesaturated(false)
				end
				if i == 1 then
					local r, g, b
					if view.ufHealthColor == "class" then
						r, g, b = SampleColor(sample)
					elseif view.ufHealthColor == "custom" then
						r, g, b = view.ufHealthR, view.ufHealthG, view.ufHealthB
					end
					bar:SetStatusBarColor(r or 0, g or 0.8, b or 0)
				else
					bar:SetStatusBarColor(unpack(sample.power))
				end
				local kind = ns.StyleBorder(view, "ufBorder")
				bar.game:SetShown(kind == "game")
				DressSkin(Skin(bar), view)
			end
			-- (The name.)
			local object = sample.small and _G.GameFontNormalSmall or _G.GameFontNormal
			unit.name:SetFontObject(object)
			local file, height, flags = object:GetFont()
			local font, outline = view.ufFont, tonumber(view.ufOutline) or 0
			if ROMAN then
				for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do
					if info[1] == font and info[3] then file = info[3] end
				end
			end
			if outline >= 0 and ns.OutlinedFlags then flags = ns.OutlinedFlags(flags, outline) end
			if file and height then unit.name:SetFont(file, height * (tonumber(view.ufNameSize) or 1), flags or "") end
			unit.name:SetText(L[sample.name])
			local nr, ng, nb = 1, 0.82, 0
			if view.ufNameColor == "class" then
				nr, ng, nb = SampleColor(sample)
			elseif view.ufNameColor == "white" then
				nr, ng, nb = 1, 1, 1
			end
			unit.name:SetTextColor(nr, ng, nb)
			-- (The portrait: a class icon for a player with Class icon picked.)
			local coords = view.ufPortrait == "class" and sample.class and _G.CLASS_ICON_TCOORDS
				and _G.CLASS_ICON_TCOORDS[sample.class]
			if coords then
				unit.portrait:SetTexture(CLASS_ICONS)
				unit.portrait:SetTexCoord(unpack(coords))
			else
				unit.portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
				unit.portrait:SetTexCoord(0, 1, 0, 1)
			end
		end
	end
	return holder
end

-- The page itself.
local PRESET_KEYS = { "ufTexture", "ufBorder", "ufBorderSize", "ufBorderR", "ufBorderG", "ufBorderB", "ufBack",
	"ufHealthColor", "ufNameColor", "ufFont", "ufOutline", "ufNameSize", "ufPortrait" }
local TAB_NAMES = {}
for _, info in ipairs(FRAMES) do TAB_NAMES[info[1]] = info[2] end

function ns.CreateUnitStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Unit frames"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How your player, target, focus, pet, target of target and party frames look. The Default tab's " ..
		"settings are every frame's until its own tab has Use default settings unticked. Which parts show: " ..
		"the UI Manager's Unit Frames page."])

	-- The tab being edited (nil: Default), and each setting as the field it edits:
	-- the frame's own copy while it has one, else Default's (shown greyed).
	local editing
	local function UsesDefault(db) return editing and not db["ufOwn_" .. editing] end
	local function FieldOf(key)
		return {
			get = function()
				local db = ns.GetDB()
				if not db then return nil end
				local own = editing and db["ufOwn_" .. editing]
				local border = key:match("^ufBorder(%u%l*)$")
				if own and border and border ~= "" then return db["ufBorder_" .. editing .. border] end
				return db[own and key .. "_" .. editing or key]
			end,
			set = function(value)
				local db = ns.GetDB()
				local border = key:match("^ufBorder(%u%l*)$")
				if editing and border and border ~= "" then
					db["ufBorder_" .. editing .. border] = value
				else
					db[editing and key .. "_" .. editing or key] = value
				end
			end,
		}
	end
	local fields = {}
	local function Field(key)
		fields[key] = fields[key] or FieldOf(key)
		return fields[key]
	end

	local preview -- (below: drawn again as each setting changes)
	local tabs, ownCheck, partyNote = {}, nil, nil
	local function Changed()
		ns.RefreshUnitStyle()
		if preview then preview:Refresh(editing) end
	end

	local switch = kit.PageSwitch(content, "ufStyle", L["Enable page"],
		L["On: the unit frames look as this page says. Off: the game's own (the preview shows that too). " ..
		"Each setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "ufStyle", Field)
	local function Editable(db) return rows.On(db) and not UsesDefault(db) end

	local function Pick(id)
		editing = id
		kit.Refresh()
		Changed()
	end

	stack:Add(ns.StyleSceneButton(content, kit.Tooltip, kit.AddControl), "label")
	preview = ns.MakeUnitStylePreview(content, 480, Pick)
	stack:Add(preview, "label")
	kit.AddControl(preview)
	local refreshPreview = preview.Refresh
	preview.Refresh = function(self) refreshPreview(self, editing) end

	rows.Presets({
		{ L["Like the game's"], L["The game's frames, as it draws them (the defaults)."], {} },
		{ L["Flat"], L["Flat bars with a thin black edge, health and names in class and reaction colors, " ..
			"Arial Narrow."], { ufTexture = "flat", ufBorder = "thin", ufBack = 0.65, ufHealthColor = "class",
			ufNameColor = "class", ufFont = "arial", ufOutline = 1 } },
		{ L["Slim"], L["Borderless flat bars in class colors, small white names."],
			{ ufTexture = "flat", ufBorder = "none", ufBack = 0.4, ufHealthColor = "class", ufNameColor = "white",
				ufNameSize = 0.9, ufOutline = 1 } },
		{ L["Cinematic"], L["Soft bars with a fine edge, class icons for players."],
			{ ufTexture = "soft", ufBorder = "thin", ufBack = 0.45, ufHealthColor = "class", ufPortrait = "class",
				ufOutline = 1 } },
	}, PRESET_KEYS, 480)

	-- The tabs: Default, then each frame; on a frame's, Use default settings.
	local tabsRow = CreateFrame("Frame", nil, content)
	tabsRow:SetSize(480, 22)
	stack:Add(tabsRow, "label")
	local function TabsLook()
		local db = ns.GetDB()
		for _, tab in ipairs(tabs) do
			if tab.id == editing then tab:LockHighlight() else tab:UnlockHighlight() end
			local own = tab.id and db and db["ufOwn_" .. tab.id]
			tab:SetText((tab.id and L[TAB_NAMES[tab.id]] or L["Default"]) .. (own and " |cffffd100*|r" or ""))
		end
		ownCheck:SetShown(editing ~= nil)
		partyNote:SetShown(editing == "PARTY" and ns.RaidStyleParty())
	end
	local list = { false }
	for _, info in ipairs(FRAMES) do list[#list + 1] = info[1] end
	for i, id in ipairs(list) do
		local tab = ns.PanelButton(tabsRow)
		tab.id = id or nil
		tab:SetText(id and L[TAB_NAMES[id]] or L["Default"])
		tab:SetSize(math.max(64, tab:GetFontString():GetStringWidth() + 20), 22)
		if i == 1 then tab:SetPoint("LEFT", tabsRow, "LEFT", 0, 0) else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 4, 0) end
		kit.Tooltip(tab, id and L["This frame's settings: Default's until you untick Use default settings."]
			or L["The settings every frame has while its tab uses the default settings."])
		tab:SetScript("OnClick", function() Pick(tab.id) end)
		tabs[i] = tab
	end
	-- (Every setting the page has, Default's and each frame's, for its Reset.)
	for key in pairs(KEYS) do kit.RecordKey(content, key) end
	for _, info in ipairs(FRAMES) do
		kit.RecordKey(content, "ufOwn_" .. info[1])
		for key in pairs(KEYS) do kit.RecordKey(content, key .. "_" .. info[1]) end
		for _, part in ipairs({ "Size", "R", "G", "B" }) do kit.RecordKey(content, "ufBorder_" .. info[1] .. part) end
	end
	ownCheck = kit.Check(content, false, L["Use default settings"],
		L["Ticked: this frame looks as the Default tab says. Unticked: as the settings below say (they start " ..
		"as Default's, and are kept while it's ticked)."], function(value)
			local db = ns.GetDB()
			-- (A first untick: the frame starts from Default's settings.)
			if not value and not db["ufStarted_" .. editing] then
				for key in pairs(KEYS) do db[key .. "_" .. editing] = db[key] end
				for _, part in ipairs({ "Size", "R", "G", "B" }) do
					db["ufBorder_" .. editing .. part] = db["ufBorder" .. part]
				end
				db["ufStarted_" .. editing] = true
			end
			db["ufOwn_" .. editing] = not value
			Changed()
			kit.Refresh()
		end)
	ownCheck.Refresh = function(self)
		local db = ns.GetDB()
		self:SetChecked(editing and db and not db["ufOwn_" .. editing] or false)
		TabsLook()
	end
	ownCheck.pageSwitch = false
	stack:Add(ownCheck, "check")
	-- (Party, while the game draws it as raid frames: nothing here to dress.)
	partyNote = kit.Label(content, "GameFontHighlightSmall", L["Your party uses raid-style frames (Edit Mode's " ..
		"party frames setting): they follow the Raid frames page, not this tab."])
	partyNote:SetPoint("LEFT", ownCheck.Text or ownCheck.text or ownCheck, "RIGHT", 16, 0)
	partyNote:SetWidth(300)
	partyNote:SetJustifyH("LEFT")
	partyNote:SetTextColor(1, 0.82, 0)
	kit.GreyUnless(ownCheck, rows.On)
	kit.AddControl(ownCheck)

	stack:Header(content, L["Bars"])
	rows.Texture(L["Texture:"], "ufTexture", L["The bars' fill. Below the game's own few: any other addon " ..
		"shares (through LibSharedMedia)."], Editable, { 0.25, 0.75, 0.3 })
	rows.Border(L["Border:"], "ufBorder", { game = true }, L["Round each bar: the game's frame alone, or a " ..
		"border of ours (Custom: its thickness and color under it)."], Editable)
	rows.Slider("ufBack", L["Background"], 0, 100, 5, "%d%%", 100,
		L["How dark it is behind the bars, with a border of ours."], Editable)

	stack:Header(content, L["Colors"])
	local last = rows.Choices(L["Health:"], "ufHealthColor", {
		{ "game", L["The game's"] },
		{ "class", L["Class or reaction"], L["Players in their class color, everyone else red, yellow or " ..
			"green by how they see you."] },
		{ "custom", L["Custom"], L["A color of your own (the swatch)."] },
	}, Editable)
	rows.Swatch(last, "ufHealthColor", { "ufHealthR", "ufHealthG", "ufHealthB" }, L["The health bar's color, for Custom."],
		Editable)
	rows.Choices(L["Name:"], "ufNameColor", {
		{ "game", L["The game's"] },
		{ "class", L["Class or reaction"] },
		{ "white", L["White"] },
	}, Editable)

	stack:Header(content, L["Name"])
	rows.Font("ufFont", L["The name's font. Russian, Korean or Chinese names keep the game's, so their " ..
		"letters show."], Editable)
	rows.Outline("ufOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"] }, nil, Editable)
	rows.Slider("ufNameSize", L["Size"], 50, 150, 5, "%d%%", 100, L["The name's size, next to the game's."], Editable)

	stack:Header(content, L["Portrait"])
	rows.Choices(L["Portrait:"], "ufPortrait", {
		{ "game", L["The game's"], L["Their face."] },
		{ "class", L["Class icon"], L["A player's class icon in place of their face (NPCs keep theirs)."] },
	}, Editable)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Unit Style", L["Unit frames"])
end
