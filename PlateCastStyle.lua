-- The Style hub's Cast bars page: how the cast bars look, on nameplates,
-- yours (and your pet's), your target's and focus's, and the bosses' and
-- arena enemies'. The game's own bars are restyled where they are (each
-- change put back on as the game sets its own again, on each cast): their
-- fill and its colors by what's cast (a cast, a channel, one that can't be
-- interrupted, one that was), a dark ground behind, a border, the spell's
-- icon, shield and spark, and the spell's name in a font of your own, with
-- the seconds left at the end. A Default tab, and a tab for each kind of bar
-- that follows Default until its "Use default settings" is unticked (as the
-- Unit frames page's tabs do): then it has its own copy of each setting
-- (<key>_<BAR>). The bars past the nameplates' keep the game's look until
-- their tab's "Restyle these bars" is ticked (plateCastOn_<BAR>), and keep
-- the game's size (yours is sized in Edit Mode). Whether the nameplates'
-- show (in CineMode): the Nameplates page's Plate Parts grid. A preview at
-- the top, drawn by the same code as the real ones.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.plateCastStyle = true
DEFAULTS.plateCastWidth = 1        -- times the game's, about its middle
DEFAULTS.plateCastHeight = 1       -- times the game's, its top kept
DEFAULTS.plateCastFill = "general" -- the fill: "game" (its own, and its colors) or a texture (general: General's)
DEFAULTS.plateCastR, DEFAULTS.plateCastG, DEFAULTS.plateCastB = 1, 0.7, 0                       -- a cast
DEFAULTS.plateCastChannelR, DEFAULTS.plateCastChannelG, DEFAULTS.plateCastChannelB = 0.25, 0.75, 0.35 -- a channel
DEFAULTS.plateCastLockedR, DEFAULTS.plateCastLockedG, DEFAULTS.plateCastLockedB = 0.6, 0.6, 0.65  -- can't be interrupted
DEFAULTS.plateCastStopR, DEFAULTS.plateCastStopG, DEFAULTS.plateCastStopB = 0.85, 0.15, 0.1     -- interrupted
DEFAULTS.plateCastBack = 0.6        -- the dark ground behind our fill, 0 to 1
DEFAULTS.plateCastBorder = "general" -- "game", "none", "thin", "thick", "custom" (general: General's)
DEFAULTS.plateCastSpark = true
DEFAULTS.plateCastIcon = true
DEFAULTS.plateCastIconSize = 1      -- the icon under the bar, times the game's
DEFAULTS.plateCastShield = true     -- the game's shield on casts that can't be interrupted
DEFAULTS.plateCastImportant = true  -- the game's mark on important casts
DEFAULTS.plateCastTarget = true     -- the game's who it's cast at (its mark and name)
DEFAULTS.plateCastText = true       -- the spell's name
DEFAULTS.plateCastFont = "general" -- QUEST_ITEM_FONTS (QuestItemButton.lua; general: General's)
DEFAULTS.plateCastTextSize = 1      -- times the game's size
DEFAULTS.plateCastOutline = "general" -- "game", "none", "thin" or "thick" (general: General's)
DEFAULTS.plateCastTimer = false     -- the seconds left at the bar's right end

-- The look's settings a preset sets (the rest as the defaults; the colors are kept).
local PRESET_KEYS = { "plateCastWidth", "plateCastHeight", "plateCastFill", "plateCastBack", "plateCastBorder", "plateCastSpark", "plateCastIcon", "plateCastIconSize",
	"plateCastShield", "plateCastImportant", "plateCastTarget", "plateCastText", "plateCastFont", "plateCastTextSize", "plateCastOutline", "plateCastTimer" }

local FILLS = {
	flat = "Interface\\Buttons\\WHITE8X8",
	smooth = "Interface\\TargetingFrame\\UI-StatusBar",
	raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
-- (Any other of the Style pages' textures that's a file: ns.StyleTexturePath.
-- An atlas isn't: the game's fill shows for it.)
setmetatable(FILLS, { __index = function(_, value)
	if not ns.StyleTexturePath then return end
	local path, atlas = ns.StyleTexturePath(value)
	if path and not atlas then return path end
end })
local OUTLINE_LEVEL = { none = 0, thin = 1, thick = 2 }
-- The game's art on the bar our border and ground stand in for (not every
-- client has each), and the parts with a tickbox of their own.
local BORDER_ART = { "Border", "TextBorder" }

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Usable(region)
	return type(region) == "table" and region.SetAlpha and not (region.IsForbidden and region:IsForbidden())
end

-- [bar] = what's ours on it: its ground, border, overlay and timer, the
-- game's alphas for what's hidden, its fill and color as the game last set
-- them, the font it had, and what was last put on.
local states = setmetatable({}, { __mode = "k" })
local busy = false -- (while we set the bar: not the game setting its own)

local function State(bar)
	local state = states[bar]
	if not state then
		state = { hidden = {} }
		states[bar] = state
	end
	return state
end

-- A part of the game's shown (its own alpha back) or hidden (alpha 0).
local function ShowPart(state, region, shown)
	if not Usable(region) then
		return
	end
	local hidden = state.hidden
	if not shown then
		if hidden[region] == nil then
			local alpha = region:GetAlpha()
			hidden[region] = type(alpha) == "number" and Known(alpha) and alpha or 1
		end
		region:SetAlpha(0)
	elseif hidden[region] ~= nil then
		region:SetAlpha(hidden[region])
		hidden[region] = nil
	end
end

-- What the bar shows now: "cast", "channel", "locked" (can't be
-- interrupted) or "stop" (interrupted), and the can't-be-interrupted answer
-- when the game keeps it secret (then "cast" or "channel", the overlay
-- showing by it).
local function UnitLocked(bar)
	local unit = bar.unit
	if type(unit) ~= "string" then
		return nil
	end
	local ok, name, _, _, _, _, _, _, locked = pcall(UnitCastingInfo, unit)
	if ok and type(name) ~= "nil" then
		return locked
	end
	local okChannel, channel, _, _, _, _, _, channelLocked = pcall(UnitChannelInfo, unit)
	if okChannel and type(channel) ~= "nil" then
		return channelLocked
	end
	return nil
end

local function CastKind(bar)
	local kind = bar.barType
	if not (type(kind) == "string" and Known(kind)) then
		kind = nil
	elseif kind == "interrupted" then
		return "stop"
	elseif kind == "uninterruptable" or kind == "uninterruptible" then
		return "locked"
	end
	local base = (ns.Flag(bar.channeling) or ns.Flag(bar.reverseChanneling) or kind == "channel") and "channel"
		or "cast"
	local locked = bar.notInterruptible
	if locked == nil then
		locked = UnitLocked(bar)
	end
	if not Known(locked) then
		return base, locked
	end
	return locked and "locked" or base
end

local COLOR_KEYS = {
	cast = { "plateCastR", "plateCastG", "plateCastB" },
	channel = { "plateCastChannelR", "plateCastChannelG", "plateCastChannelB" },
	locked = { "plateCastLockedR", "plateCastLockedG", "plateCastLockedB" },
	stop = { "plateCastStopR", "plateCastStopG", "plateCastStopB" },
}
local function Rgb(look, kind)
	local keys = COLOR_KEYS[kind]
	return look[keys[1]], look[keys[2]], look[keys[3]]
end

-- Each kind of bar (its id, as the settings name it, and its tab's name).
local BARS = {
	{ "PLATE", "Nameplates" },
	{ "PLAYER", "You" },
	{ "TARGET", "Target & focus" },
	{ "BOSS", "Boss & arena" },
}
-- The settings each has a copy of (Default's are the plain keys), starting
-- as Default's; the shared ones (General's) shared under each's name too.
local BAR_KEYS = { "plateCastBorderSize", "plateCastBorderR", "plateCastBorderG", "plateCastBorderB" }
for _, key in ipairs(PRESET_KEYS) do BAR_KEYS[#BAR_KEYS + 1] = key end
for _, keys in pairs(COLOR_KEYS) do
	for _, key in ipairs(keys) do BAR_KEYS[#BAR_KEYS + 1] = key end
end
local OWN_KEY = {}
for _, key in ipairs(BAR_KEYS) do OWN_KEY[key] = true end
for _, info in ipairs(BARS) do
	local id = info[1]
	DEFAULTS["plateCastOwn_" .. id] = false
	if id ~= "PLATE" then DEFAULTS["plateCastOn_" .. id] = false end
	for _, key in ipairs(BAR_KEYS) do
		DEFAULTS[key .. "_" .. id] = DEFAULTS[key]
		local entry = ns.SHARED_STYLE[key]
		if entry then
			ns.SHARED_STYLE[key .. "_" .. id] = entry.follows
				and { kind = entry.kind, follows = entry.follows .. "_" .. id } or entry
		end
	end
end

-- Whether a kind of bar is restyled: the page on, and for any but the
-- nameplates', its tab's Restyle these bars ticked. (db: the settings to
-- ask, for the options' tests.)
local function Active(id, db)
	db = db or ns.db
	return ns.StyleOn("plateCastStyle", db) and (id == "PLATE" or (db and db["plateCastOn_" .. id])) and true
		or false
end

-- A kind of bar's look (id nil: the Default tab's): its own settings while
-- its "Use default settings" is unticked, else Default's; each through the
-- Style pages' look (General's, and the game's with the page or General off).
local views = {}
local function View(id)
	local view = views[id or "DEFAULT"]
	if not view then
		view = setmetatable({}, { __index = function(_, key)
			local look = ns.StyleLook("plateCastStyle")
			local db = ns.db
			if id and OWN_KEY[key] and db and ns.StyleOn("plateCastStyle") and db["plateCastOwn_" .. id] then
				return look[key .. "_" .. id]
			end
			return look[key]
		end })
		views[id or "DEFAULT"] = view
	end
	return view
end

-- The look a kind of bar gets now: the game's while it isn't restyled.
local function Look(id)
	if id and not Active(id) then
		return ns.StyleLook("plateCastStyle", true)
	end
	return View(id)
end

function ns.PlateCastLook()
	return Look("PLATE")
end

-- A part of the game's bar: by its key, or (the classic clients' older
-- bars) by its name, <bar's name><part>.
local function Part(bar, field)
	local part = bar[field]
	if part == nil and bar.GetName then
		local name = bar:GetName()
		part = type(name) == "string" and _G[name .. field] or nil
	end
	return part
end

-- Our pieces on a bar, made the first time it needs them.
local function Ground(bar, state)
	if not state.ground then
		state.ground = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
		state.ground:SetAllPoints()
		state.ground:SetColorTexture(0, 0, 0, 1)
	end
	return state.ground
end

-- A frame of 1-wide lines just outside around (r, g, b, a).
local LINES = {
	{ "TOPLEFT", -1, 1, "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1, "BOTTOMRIGHT", 1, -1 },
	{ "TOPLEFT", -1, 1, "BOTTOMLEFT", -1, -1 }, { "TOPRIGHT", 1, 1, "BOTTOMRIGHT", 1, -1 },
}
local function Lines(around, r, g, b, a)
	local frame = CreateFrame("Frame", nil, around)
	frame:SetAllPoints()
	frame:SetFrameLevel(around:GetFrameLevel() + 2)
	for i, line in ipairs(LINES) do
		local texture = frame:CreateTexture(nil, "OVERLAY")
		texture:SetColorTexture(r, g, b, a)
		texture:SetPoint(line[1], around, line[1], line[2], line[3])
		texture:SetPoint(line[4], around, line[4], line[5], line[6])
		if i <= 2 then texture:SetHeight(1) else texture:SetWidth(1) end
	end
	return frame
end

local function Edge(bar, state)
	if not state.edge then
		state.edge = ns.MakeStyleEdges(bar)
	end
	return state.edge
end

-- The fill again in the can't-be-interrupted color, over the game's, showing
-- by an answer the game keeps secret (SetAlphaFromBoolean takes those).
local function Overlay(bar, state, fill)
	if not state.overlay then
		state.overlay = bar:CreateTexture(nil, "ARTWORK", nil, 7)
	end
	local overlay = state.overlay
	overlay:ClearAllPoints()
	overlay:SetAllPoints(fill)
	return overlay
end

local function Timer(bar, state)
	if not state.timer then
		local timer = bar:CreateFontString(nil, "OVERLAY")
		local text = Part(bar, "Text")
		-- (the game's font, not ours if the name has it already)
		local own = state.fonts and state.fonts.text
		local object = own and own.object or (Usable(text) and text.GetFontObject and text:GetFontObject())
		timer:SetFontObject(object or "GameFontHighlightSmall")
		timer:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
		timer:SetJustifyH("RIGHT")
		state.timer = timer
	end
	return state.timer
end

-- The spell name's (and the timer's) font: the game's, or ours over it (a
-- family, so every alphabet's letters show: ns.SetPlateNameFont).
local function FontFile(look)
	for _, font in ipairs(ns.QUEST_ITEM_FONTS or {}) do
		if font[1] == look.plateCastFont then
			return font[3]
		end
	end
end

-- (Its size: the page's Text size, the timer's times the bar's height too,
-- as it's on the bar.)
local function SetFont(state, text, look, which)
	local scale = (look.plateCastTextSize or 1) * (which == "timer" and look.plateCastHeight or 1)
	local wanted = look.plateCastFont ~= "game" or look.plateCastOutline ~= "game"
		or math.abs(scale - 1) > 0.001
	local fonts = state.fonts or {}
	state.fonts = fonts
	local own = fonts[which]
	if not wanted then
		if own and own.ours then
			if own.object then
				text:SetFontObject(own.object)
			elseif own.file then
				pcall(text.SetFont, text, own.file, own.size, own.flags)
			end
			pcall(function() text:SetText(text:GetText()) end)
			own.ours, own.key = false, nil
		end
		return
	end
	if not own then
		local file, size, flags = text:GetFont()
		own = { object = text:GetFontObject(), file = file, size = size, flags = flags }
		fonts[which] = own
	end
	if not (own.file and own.size) then
		return
	end
	local flags = own.flags or ""
	if look.plateCastOutline ~= "game" then
		flags = ns.OutlinedFlags(flags, OUTLINE_LEVEL[look.plateCastOutline] or 1)
	end
	local file = FontFile(look) or own.file
	local key = file .. "|" .. flags .. "|" .. scale
	if own.key ~= key then
		ns.SetPlateNameFont(text, own.object, file, own.size, scale, flags)
		own.ours, own.key = true, key
	end
end

-- The fill's color by what's cast, and the overlay for a secret answer.
local function Paint(bar, state, look)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not fill then
		return
	end
	local kind, secret = CastKind(bar)
	state.kind = kind
	busy = true
	pcall(bar.SetStatusBarColor, bar, Rgb(look, kind))
	busy = false
	local overlay = state.overlay
	if secret ~= nil or overlay then
		overlay = Overlay(bar, state, fill)
		overlay:SetTexture(FILLS[look.plateCastFill])
		overlay:SetVertexColor(Rgb(look, "locked"))
		if secret ~= nil and overlay.SetAlphaFromBoolean then
			if not pcall(overlay.SetAlphaFromBoolean, overlay, secret, 1, 0) then
				overlay:SetAlpha(0)
			end
		else
			overlay:SetAlpha(0)
		end
	end
end

-- The seconds left, when the game will say (its numbers can be secret in
-- fights): hidden otherwise.
local function UpdateTimer(bar, state)
	local timer = state.timer
	if not timer then
		return
	end
	local value, most = bar.value, bar.maxValue
	if not (type(value) == "number" and type(most) == "number" and Known(value) and Known(most)) then
		local ok, v = pcall(bar.GetValue, bar)
		local okRange, _, m = pcall(bar.GetMinMaxValues, bar)
		value, most = ok and v, okRange and m
	end
	if type(value) == "number" and type(most) == "number" and Known(value) and Known(most) and most > 0 then
		local left = (ns.Flag(bar.channeling) and value) or (most - value)
		if left >= 0 and state.kind ~= "stop" then
			timer:SetFormattedText("%.1f", left)
			timer:Show()
			return
		end
	end
	-- (Retail's are secret in fights, the bar's and its fill's too: the
	-- cast's own duration then, secret, which the text can still take.)
	local unit = bar.unit
	if type(unit) == "string" and state.kind ~= "stop" then
		local ok = pcall(function()
			local duration = _G.UnitCastingDuration and _G.UnitCastingDuration(unit)
			if not duration and _G.UnitChannelDuration then
				duration = _G.UnitChannelDuration(unit)
			end
			timer:SetFormattedText("%.1f", duration:GetRemainingDuration())
		end)
		if ok then
			timer:Show()
			return
		end
	end
	timer:Hide()
end

-- The bar's size: its width and height times the page's, about its middle
-- (its top kept: the spell's name under it moves down with it). Retail
-- won't say where a plate's parts are, but the bar's anchors can be read:
-- each put back with its left or right side moved in or out and its bottom
-- down, and a side it isn't held by sized instead. Its own (as the game last
-- set it) kept, and put back at 100%. Not sized while its anchors can't be
-- read (state.sizeWhy says why, for /cine debug plates).
local function Number(ok, value)
	return ok and type(value) == "number" and Known(value) and value or nil
end

local function ReadPoints(bar)
	local count = Number(pcall(bar.GetNumPoints, bar))
	if not count then
		return nil, "its anchors are secret"
	end
	local points = {}
	for i = 1, count do
		local ok, point, relative, relativePoint, x, y = pcall(bar.GetPoint, bar, i)
		if not (ok and Known(point) and Known(relative) and Known(relativePoint) and Known(x) and Known(y)) then
			return nil, "its anchors are secret"
		end
		points[i] = { point, relative, relativePoint, x or 0, y or 0 }
	end
	return points
end

local function SamePoints(a, b)
	if not (a and b) or #a ~= #b then
		return false
	end
	for i, p in ipairs(a) do
		local q = b[i]
		if p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3] or math.abs(p[4] - q[4]) > 0.01
			or math.abs(p[5] - q[5]) > 0.01 then
			return false
		end
	end
	return true
end

local function SetPoints(bar, points)
	pcall(bar.ClearAllPoints, bar)
	for _, p in ipairs(points) do
		pcall(bar.SetPoint, bar, p[1], p[2], p[3], p[4], p[5])
	end
end

-- Whether a size read back (now) is the game's own again rather than ours:
-- the game snaps sizes to whole pixels, so ours reads back a little off
-- (taking that for the game's own grew the bar on every cast, without end).
local function Reset(now, ours)
	return not ours or math.abs(now - ours) > math.max(1, ours * 0.05)
end

-- Retail's: the bar's own anchors and size are secret. The game holds it
-- at a height of its own on its container's bottom, the health bar on top
-- (a taller container only pushed the health bar up; scaling it moved it
-- off, its anchors' offsets scaled too: both tested). So its height's set,
-- growing up from its bottom, and its container grows by the same, the
-- health bar and name riding up on it. Its own height is read off its
-- ground, which fills it (the bar's own is secret); ours reads back there
-- too, so that's the game's own again only when clearly not ours. Its
-- width there is the health bar's: the Nameplate Style page's. All put
-- back at 100%.
local function OwnHeight(bar)
	local ground = bar.Background
	if Usable(ground) and ground.GetHeight then
		local height = Number(pcall(ground.GetHeight, ground))
		if height and height > 0 then
			return height
		end
	end
end

local function Room(bar, state, grow)
	local container = bar:GetParent()
	if not (Usable(container) and container.SetHeight) then
		return
	end
	local now = Number(pcall(container.GetHeight, container))
	if now and Reset(now, state.containerHeight) then
		state.containerOwn = now
	end
	local own = state.containerOwn
	if not grow then
		if state.containerHeight and own then
			pcall(container.SetHeight, container, own)
		end
		state.containerHeight = nil
		return
	end
	if own and own > 0 then
		state.containerHeight = own + grow
		pcall(container.SetHeight, container, state.containerHeight)
	end
end

local function HeightOnly(bar, state, height)
	local now = OwnHeight(bar)
	if now and Reset(now, state.barHeight) then
		state.ownHeight = now
	end
	local own = state.ownHeight
	if math.abs(height - 1) < 0.001 then
		if state.barHeight and own then
			pcall(bar.SetHeight, bar, own)
			Room(bar, state, nil)
		end
		state.barHeight, state.sizeWhy = nil, nil
		return
	end
	if not own then
		state.sizeWhy = "its anchors and height are secret"
		return
	end
	state.barHeight = own * height
	pcall(bar.SetHeight, bar, state.barHeight)
	-- (The bar sits on the icon's row, so a taller icon lifts it too, tested.)
	Room(bar, state, state.barHeight - own + (state.iconGain or 0))
	state.sizeWhy = nil
end

local function SizeBar(bar, state, look)
	local width, height = look.plateCastWidth or 1, look.plateCastHeight or 1
	local wanted = math.abs(width - 1) > 0.001 or math.abs(height - 1) > 0.001
	local points, why = ReadPoints(bar)
	if not points and not state.sized then
		HeightOnly(bar, state, height)
		return
	end
	-- (The game's own again whenever what's on it isn't what we put on.)
	if points and not SamePoints(points, state.sizedPoints) then
		state.own = state.own or {}
		state.own.points = points
	end
	local own = state.own
	if own then
		local nowWidth = Number(pcall(bar.GetWidth, bar))
		local nowHeight = Number(pcall(bar.GetHeight, bar))
		if nowWidth and Reset(nowWidth, state.sizedWidth) then
			own.width = nowWidth
		end
		if nowHeight and Reset(nowHeight, state.sizedHeight) then
			own.height = nowHeight
		end
	end
	if not wanted then
		if state.sized and own and own.points then
			SetPoints(bar, own.points)
			if own.width and own.height then
				pcall(bar.SetSize, bar, own.width, own.height)
			end
		end
		state.sized, state.sizedPoints, state.sizedWidth, state.sizedHeight, state.sizeWhy = false, nil, nil, nil, nil
		return
	end
	if not (own and own.points and own.width and own.height and own.width > 0 and own.height > 0) then
		state.sizeWhy = why or "no size yet"
		return
	end
	local sides = {}
	for _, p in ipairs(own.points) do
		for _, side in ipairs({ "LEFT", "RIGHT", "TOP", "BOTTOM" }) do
			if p[1]:find(side) then sides[side] = true end
		end
	end
	local dx = own.width * (1 - width) / 2
	local grow = own.height * (height - 1)
	local mine = {}
	for i, p in ipairs(own.points) do
		local x, y = p[4], p[5]
		if p[1]:find("LEFT") then
			x = x + dx
		elseif p[1]:find("RIGHT") then
			x = x - dx
		end
		if p[1]:find("BOTTOM") then
			y = y - grow
		end
		mine[i] = { p[1], p[2], p[3], x, y }
	end
	SetPoints(bar, mine)
	state.sizedWidth, state.sizedHeight = nil, nil
	if not (sides.LEFT and sides.RIGHT) then
		state.sizedWidth = own.width * width
		pcall(bar.SetWidth, bar, state.sizedWidth)
	end
	if not (sides.TOP and sides.BOTTOM) then
		state.sizedHeight = own.height * height
		pcall(bar.SetHeight, bar, state.sizedHeight)
	end
	state.sized, state.sizedPoints, state.sizeWhy = true, mine, nil
end

-- The spell's icon at the page's size (its place the game's, its
-- size taken from its anchor). Its own size is the game's again whenever it
-- clearly isn't ours (read-backs snap to pixels).
local function SizeIcon(bar, state, height)
	local icon = Part(bar, "Icon")
	if not (Usable(icon) and icon.SetSize) then
		return
	end
	local width = Number(pcall(icon.GetWidth, icon))
	local tall = Number(pcall(icon.GetHeight, icon))
	if width and tall and width > 0 and tall > 0 then
		local ours = state.iconSize
		if not ours or Reset(width, ours[1]) or Reset(tall, ours[2]) then
			state.iconOwn = { width, tall }
		end
	end
	local own = state.iconOwn
	if math.abs(height - 1) < 0.001 then
		if state.iconSize and own then
			pcall(icon.SetSize, icon, own[1], own[2])
		end
		state.iconSize, state.iconGain = nil, nil
		return
	end
	if own then
		state.iconSize = { own[1] * height, own[2] * height }
		state.iconGain = own[2] * (height - 1)
		pcall(icon.SetSize, icon, state.iconSize[1], state.iconSize[2])
	end
end

-- (sized: the bar's own size too, the nameplates' alone; the rest keep the
-- game's, yours set in Edit Mode.)
local UNSIZED = { plateCastWidth = 1, plateCastHeight = 1 }
local function Size(bar, state, look, sized)
	SizeIcon(bar, state, look.plateCastIconSize or 1)
	if sized then
		SizeBar(bar, state, look)
	elseif state.sized or state.barHeight then
		SizeBar(bar, state, UNSIZED) -- (a preview's sample, its tab changed: its own size back)
	end
end

-- Puts the look on a bar (the game's where a setting says the game's). The
-- preview's bars too (sample: no game fill to put back). sized: a
-- nameplate's (or a sample of one), sized by the page.
local function Apply(bar, look, sample, sized)
	local state = State(bar)
	local ours = FILLS[look.plateCastFill]
	if ours then
		busy = true
		pcall(bar.SetStatusBarTexture, bar, ours)
		busy = false
		Paint(bar, state, look)
		state.filled = true
	elseif state.filled then
		state.filled = false
		if not sample and state.ownFill then
			busy = true
			pcall(bar.SetStatusBarTexture, bar, state.ownFill)
			if state.ownColor then
				pcall(bar.SetStatusBarColor, bar, unpack(state.ownColor))
			end
			busy = false
		end
		if state.overlay then state.overlay:SetAlpha(0) end
	end
	local ground = (ours and look.plateCastBack > 0) and Ground(bar, state) or state.ground
	if ground then
		ground:SetAlpha(look.plateCastBack)
		ground:SetShown(ours ~= nil and look.plateCastBack > 0)
	end
	ShowPart(state, Part(bar, "Background"), not ours)
	local border, size, br, bg, bb = ns.StyleBorder(look, "plateCastBorder")
	-- (The box the spell's name sits in goes with the name.)
	for _, field in ipairs(BORDER_ART) do
		ShowPart(state, Part(bar, field), border == "game" and (field ~= "TextBorder" or look.plateCastText))
	end
	if border == "line" then
		local edge = Edge(bar, state)
		ns.DressStyleEdges(edge, size, br, bg, bb, 1, true)
		edge:Show()
	elseif state.edge then
		state.edge:Hide()
	end
	ShowPart(state, Part(bar, "Spark"), look.plateCastSpark)
	ShowPart(state, Part(bar, "Icon"), look.plateCastIcon)
	ShowPart(state, Part(bar, "BorderShield"), look.plateCastShield)
	ShowPart(state, bar.ImportantCastIndicator, look.plateCastImportant)
	ShowPart(state, bar.CastTargetIndicator, look.plateCastTarget)
	ShowPart(state, bar.CastTargetNameText, look.plateCastTarget)
	local text = Part(bar, "Text")
	ShowPart(state, text, look.plateCastText)
	if Usable(text) and text.GetFont then
		SetFont(state, text, look, "text")
	end
	if look.plateCastTimer then
		local timer = Timer(bar, state)
		SetFont(state, timer, look, "timer")
		UpdateTimer(bar, state)
	elseif state.timer then
		state.timer:Hide()
	end
	Size(bar, state, look, sized)
	state.on = true
end
ns.StylePlateCastBar = Apply

-- The real bars: each hooked once, so whatever the game sets on it as a
-- cast starts, changes or ends, the look goes back on. A bar no longer
-- restyled gets the game's look back once, then is left be.
local hooked = setmetatable({}, { __mode = "k" })
local barIds = setmetatable({}, { __mode = "k" }) -- [bar] = its kind's id

local function Restyle(bar)
	local id = barIds[bar] or "PLATE"
	local state = states[bar]
	local active = Active(id)
	if not active and not (state and state.on) then
		return
	end
	Apply(bar, Look(id), nil, id == "PLATE")
	if not active then
		states[bar].on = false
	end
end

local onEvent = ns.Profiled("Plate cast bar style", Restyle)
local onUpdate = ns.Profiled("Plate cast bar style update", function(bar)
	local state = states[bar]
	if not (state and state.on) then
		return
	end
	local look = Look(barIds[bar] or "PLATE")
	-- (What's cast can change mid-cast: an interrupt, a shield coming up.)
	if state.filled then
		local kind = CastKind(bar)
		if kind ~= state.kind then
			Paint(bar, state, look)
		end
	end
	if look.plateCastTimer then
		UpdateTimer(bar, state)
	end
end)

local function Hook(bar, id)
	if hooked[bar] then
		return
	end
	hooked[bar] = true
	barIds[bar] = id
	bar:HookScript("OnEvent", onEvent)
	bar:HookScript("OnShow", onEvent)
	bar:HookScript("OnUpdate", onUpdate)
	-- (The game's own fill and color kept, for turning ours off again.)
	pcall(hooksecurefunc, bar, "SetStatusBarTexture", function(self, texture)
		if busy then
			return
		end
		local state = State(self)
		local fill = self:GetStatusBarTexture()
		local atlas = fill and fill.GetAtlas and fill:GetAtlas()
		state.ownFill = (Known(atlas) and atlas) or (Known(texture) and texture) or state.ownFill
		if state.on then
			Restyle(self)
		end
	end)
	pcall(hooksecurefunc, bar, "SetStatusBarColor", function(self, r, g, b, a)
		if busy then
			return
		end
		local state = State(self)
		if Known(r) and Known(g) and Known(b) and Known(a) then
			state.ownColor = { r, g, b, a or 1 }
		end
		if state.on and state.filled then
			Paint(self, state, Look(barIds[self] or "PLATE"))
		end
	end)
end

-- A plate's cast bar (WoW Forever's in CastBarsContainer), or nil.
local function BarOf(unitFrame)
	if not Usable(unitFrame) then
		return nil
	end
	local container = unitFrame.CastBarsContainer
	local bar = unitFrame.castBar or (type(container) == "table" and container.castBar) or unitFrame.CastBar
	return Usable(bar) and bar.SetStatusBarTexture and bar or nil
end

local function PersonalPlate()
	return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
end

local function StylePlate(plate)
	if not plate or plate == PersonalPlate() then
		return
	end
	local bar = BarOf(plate.UnitFrame)
	if not bar then
		return
	end
	if Active("PLATE") then
		Hook(bar, "PLATE")
	end
	if hooked[bar] then
		Restyle(bar)
	end
end

-- The game's other cast bars, by kind: yours (retail's, Classic's, the
-- pet's for vehicles and mind control, WoW Forever's gamepad one), the
-- target's and focus's (spellbar on every client; by its name too), and the
-- bosses' and arena enemies' (retail's arena frames, the classic clients'
-- by name). Untested: the arena ones.
local GAME_BARS = {
	PLAYER = function(add)
		for _, name in ipairs({ "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame", "CastingBarFrame",
			"PetCastingBarFrame", "GamepadPlayerCastingBarFrame" }) do
			add(_G[name])
		end
	end,
	TARGET = function(add)
		for _, name in ipairs({ "TargetFrame", "FocusFrame" }) do
			add(_G[name] and _G[name].spellbar)
			add(_G[name .. "SpellBar"])
		end
	end,
	BOSS = function(add)
		for i = 1, 8 do
			local boss = _G["Boss" .. i .. "TargetFrame"]
			add(boss and boss.spellbar)
			add(_G["Boss" .. i .. "TargetFrameSpellBar"])
			add(_G["ArenaEnemyFrame" .. i .. "CastingBar"])
			add(_G["ArenaEnemyMatchFrame" .. i .. "CastingBar"])
		end
		local arena = _G.CompactArenaFrame
		if type(arena) == "table" and type(arena.memberUnitFrames) == "table" then
			for _, member in ipairs(arena.memberUnitFrames) do
				add(type(member) == "table" and member.CastingBarFrame)
			end
		end
	end,
}

-- One kind's bars: hooked once it's restyled, each dressed again.
local function StyleGame(id)
	local seen = {}
	pcall(GAME_BARS[id], function(bar)
		if not (Usable(bar) and bar.SetStatusBarTexture and bar.HookScript) or seen[bar] then
			return
		end
		seen[bar] = true
		if Active(id) then
			Hook(bar, id)
		end
		if hooked[bar] then
			Restyle(bar)
		end
	end)
end

-- Every bar again (a change on the page).
function ns.RefreshPlateCastStyle()
	if not ns.db then
		return
	end
	for id in pairs(GAME_BARS) do
		StyleGame(id)
	end
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		StylePlate(plate)
	end
end

-- (The bosses' and arena's frames come as they're needed: looked for again
-- then.)
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_ENTERING_WORLD", "ADDON_LOADED",
	"INSTANCE_ENCOUNTER_ENGAGE_UNIT", "ARENA_OPPONENT_UPDATE" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event, unit)
	if not ns.db then
		return
	end
	if event == "NAME_PLATE_UNIT_ADDED" then
		if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
			StylePlate(C_NamePlate.GetNamePlateForUnit(unit))
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		for id in pairs(GAME_BARS) do
			StyleGame(id)
		end
	elseif event == "ADDON_LOADED" then
		if unit == "Blizzard_ArenaUI" or unit == "Blizzard_CompactRaidFrames" then
			StyleGame("BOSS")
		end
	else
		StyleGame("BOSS")
	end
end)

-- The bar's size and anchors now, its container's size, ours on it, or why not.
local function SizeReport(bar, state)
	local function Num(value)
		return value and ("%.1f"):format(value) or "?"
	end
	local function Pair(size)
		return size and size[1] and size[2] and ("%sx%s"):format(Num(size[1]), Num(size[2])) or "?"
	end
	local points, why = ReadPoints(bar)
	local anchors = {}
	for _, p in ipairs(points or {}) do
		local okName, name = pcall(function() return p[2] and p[2]:GetDebugName() end)
		anchors[#anchors + 1] = ("%s>%s %s %s,%s"):format(p[1],
			okName and Known(name) and tostring(name):match("[^.]*$") or "?", p[3], Num(p[4]), Num(p[5]))
	end
	local container = bar:GetParent()
	local own = state and state.own
	return ("bar %sx%s, anchors %s; container %sx%s (own height %s, ours %s); bar height by its ground %s (own %s, ours %s); icon %s (own %s); own %sx%s; ours %s%s"):format(
		Num(Number(pcall(bar.GetWidth, bar))), Num(Number(pcall(bar.GetHeight, bar))),
		points and (#anchors > 0 and table.concat(anchors, " + ") or "none") or why,
		Num(container and Number(pcall(container.GetWidth, container))),
		Num(container and Number(pcall(container.GetHeight, container))),
		Num(state and state.containerOwn), Num(state and state.containerHeight),
		Num(OwnHeight(bar)), Num(state and state.ownHeight), Num(state and state.barHeight),
		Pair(bar.Icon and Usable(bar.Icon) and { Number(pcall(bar.Icon.GetWidth, bar.Icon)),
			Number(pcall(bar.Icon.GetHeight, bar.Icon)) }), Pair(state and state.iconOwn),
		Num(own and own.width), Num(own and own.height),
		tostring(state and state.sized or false), state and state.sizeWhy and (" (" .. state.sizeWhy .. ")") or "")
end

-- For /cine debug plates: where the target plate's cast bar is, its fields,
-- what it's casting as we read it, and what's ours on it.
function ns.DescribePlateCastBar(unitFrame)
	local bar = BarOf(unitFrame)
	if not bar then
		local container = unitFrame and unitFrame.CastBarsContainer
		return "none found (castBar " .. tostring(unitFrame and unitFrame.castBar ~= nil) .. ", container "
			.. tostring(container ~= nil) .. ")"
	end
	local function Say(value)
		if not Known(value) then
			return "secret"
		end
		return type(value) == "number" and ("%.2f"):format(value) or tostring(value)
	end
	local fields = {}
	for field, value in pairs(bar) do
		if type(field) == "string" and type(value) == "table"
			and select(2, pcall(function() return value.GetObjectType ~= nil end)) == true then
			local okType, kind = pcall(value.GetObjectType, value)
			local okShown, shown = pcall(value.IsShown, value)
			local okAlpha, alpha = pcall(value.GetAlpha, value)
			fields[#fields + 1] = ("%s:%s%s a=%s"):format(field, okType and tostring(kind) or "?",
				(okShown and Known(shown) and not shown) and "(hidden)" or "", okAlpha and Say(alpha) or "?")
		end
	end
	table.sort(fields)
	local fill = bar:GetStatusBarTexture()
	local okAtlas, atlas = pcall(function() return fill and fill:GetAtlas() end)
	local okTexture, texture = pcall(function() return fill and fill:GetTexture() end)
	local kind, secret = CastKind(bar)
	local state = states[bar]
	return ("%s; barType=%s casting=%s channeling=%s notInterruptible=%s unit=%s value=%s/%s; we read %s%s; "
		.. "fill atlas=%s texture=%s; page %s, hooked %s, styled %s, game fill %s; size: %s; fields: %s"):format(
		bar == unitFrame.castBar and "castBar" or (bar == unitFrame.CastBar and "CastBar" or "CastBarsContainer.castBar"),
		Say(bar.barType), Say(bar.casting), Say(bar.channeling), Say(bar.notInterruptible), Say(bar.unit),
		Say(bar.value), Say(bar.maxValue), kind, secret ~= nil and " (can't-interrupt secret)" or "",
		okAtlas and Say(atlas) or "?", okTexture and Say(texture) or "?",
		tostring(Active("PLATE")), tostring(hooked[bar] == true), tostring(state and state.on),
		tostring(state and state.ownFill), SizeReport(bar, state), table.concat(fields, ", "))
end

-- The page.
-- (Each: its label, icon and spell, the spell's name in the game's own words.)
local SAMPLES = {
	{ "Casting", "Interface\\Icons\\Spell_Fire_FlameBolt", 133, "Fireball" },
	{ "Channeling", "Interface\\Icons\\Spell_Shadow_SiphonMana", 689, "Drain Life", channel = true },
	{ "Can't be interrupted", "Interface\\Icons\\Spell_Shadow_ShadowBolt", 686, "Shadow Bolt", locked = true },
}
local function SpellName(id, fallback)
	local ok, name = pcall(function()
		return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (GetSpellInfo and GetSpellInfo(id))
	end)
	return ok and type(name) == "string" and name or fallback
end
local SAMPLE_TIME = 2.5 -- seconds a sample cast takes, over and over
local SAMPLE_W = 140 -- a sample plate's width (the game's are about 258 wide)
-- The game's own fills, retail's atlases (the classic smooth one where
-- there's none).
local GAME_ATLAS = { cast = "UI-CastingBar-Full-Standard", channel = "UI-CastingBar-Full-Channel",
	locked = "UI-CastingBar-Full-Uninterruptable" }
local GAME_COLORS = { cast = { 1, 0.7, 0 }, channel = { 0, 1, 0 }, locked = { 0.7, 0.7, 0.7 } }

-- A stand-in for the game's bar: a status bar with its parts by the same names.
local function MakeSample(parent, info)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(SAMPLE_W, 7)
	bar:SetMinMaxValues(0, 1)
	local background = bar:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.5)
	bar.Background = background
	bar.Border = Lines(bar, 0.75, 0.75, 0.75, 0.8)
	local icon = bar:CreateTexture(nil, "OVERLAY")
	-- (Laid out as the game's: retail's icon and spell name under the bar,
	-- at its left; elsewhere the icon at the bar's left, the name on it.)
	icon:SetSize(13, 13)
	if ns.isRetail then
		icon:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
	else
		icon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
	end
	-- (The spell's own icon, the game's current art. Not filtered smooth: SetTexture with a
	-- filter mode crashed the game on retail as the page was made.)
	local art = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(info[3]) or info[2]
	icon:SetTexture(art)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	bar.Icon = icon
	local shield = bar:CreateTexture(nil, "OVERLAY", nil, 1)
	shield:SetSize(20, 24)
	shield:SetPoint("CENTER", icon, "CENTER", 0, -1)
	if not (shield.SetAtlas and pcall(shield.SetAtlas, shield, "nameplates-InterruptShield")) then
		shield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
	end
	shield:SetShown(info.locked == true)
	bar.BorderShield = shield
	local spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	spark:SetBlendMode("ADD")
	spark:SetSize(12, 16)
	bar.Spark = spark
	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	if ns.isRetail then
		text:SetPoint("LEFT", icon, "RIGHT", 2, 0)
	else
		text:SetPoint("CENTER", bar, "CENTER", 0, 0)
	end
	text:SetText(SpellName(info[3], info[4]))
	bar.Text = text
	bar.channeling = info.channel or nil
	bar.casting = not info.channel or nil
	bar.notInterruptible = info.locked or false
	bar.barType = info.locked and "uninterruptable" or (info.channel and "channel" or "standard")
	return bar
end

local TAB_NAMES = {}
for _, info in ipairs(BARS) do TAB_NAMES[info[1]] = info[2] end

function ns.CreatePlateCastStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Cast bars"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the cast bars look: on nameplates, yours, your target's and focus's, and the bosses' and arena " ..
		"enemies'. The Default tab's settings are every bar's until its own tab has Use default settings " ..
		"unticked. All but the nameplates' keep the game's look until their tab's Restyle these bars is " ..
		"ticked. Whether the nameplates' show in CineMode: the Nameplates page's Plate Parts grid. Changes " ..
		"show at once, here and on bars casting now."])

	-- The tab being edited (nil: Default), and each setting as the field it
	-- edits: the bar's own copy while it has one, else Default's (shown greyed).
	local editing
	local function UsesDefault(db) return editing and not db["plateCastOwn_" .. editing] end
	local function Restyled(db) return not editing or Active(editing, db) end
	local fields = {}
	local function Field(key)
		if not fields[key] then
			fields[key] = {
				get = function()
					local db = ns.GetDB()
					if not db then return nil end
					return db[(editing and db["plateCastOwn_" .. editing]) and key .. "_" .. editing or key]
				end,
				set = function(value)
					ns.GetDB()[editing and key .. "_" .. editing or key] = value
				end,
			}
		end
		return fields[key]
	end

	local preview -- (below: drawn again as each setting changes)
	local tabs, ownCheck, restyleCheck, sizes
	local function Changed()
		ns.RefreshPlateCastStyle()
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "plateCastStyle", L["Enable page"],
		L["On: the cast bars look as this page says. Off: the game's own (the preview shows that too). Each " ..
		"setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "plateCastStyle", Field)
	local function Editable(db) return rows.On(db) and Restyled(db) and not UsesDefault(db) end

	local function Pick(id)
		editing = id
		kit.Refresh()
		Changed()
	end

	-- The preview: a cast, a channel and one that can't be interrupted, filling
	-- again and again, over the Style pages' scene.
	local PREVIEW_W, PREVIEW_H = 480, 150
	preview = CreateFrame("Frame", nil, content)
	preview:SetSize(PREVIEW_W, PREVIEW_H)
	stack:Add(preview, "label")
	ns.StyleScene(preview, 0.6, 0.8) -- (StylePages.lua)
	local caption = kit.Label(preview, "GameFontDisableSmall", L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	local samples = {}
	-- Three small plates side by side, as the game lays one out: the health
	-- bar with the unit's name in it (here what the sample shows), the cast
	-- bar under it.
	local GAP = 14
	local left = (PREVIEW_W - 3 * SAMPLE_W - 2 * GAP) / 2
	for i, info in ipairs(SAMPLES) do
		local health = CreateFrame("StatusBar", nil, preview)
		health:SetSize(SAMPLE_W, 13)
		health:SetPoint("TOPLEFT", preview, "TOPLEFT", left + (i - 1) * (SAMPLE_W + GAP), -42)
		health:SetStatusBarTexture(FILLS.flat)
		health:SetStatusBarColor(0.8, 0.1, 0.1)
		health:SetMinMaxValues(0, 1)
		health:SetValue(0.85 - (i - 1) * 0.2)
		local ground = health:CreateTexture(nil, "BACKGROUND")
		ground:SetAllPoints()
		ground:SetColorTexture(0, 0, 0, 0.6)
		Lines(health, 0, 0, 0, 1)
		local name = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("LEFT", 3, 0)
		name:SetPoint("RIGHT", -3, 0)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		name:SetText(L[info[1]])
		name.searchSkip = true
		local bar = MakeSample(preview, info)
		bar:SetPoint("TOP", health, "BOTTOM", 0, -2)
		bar.offset = (i - 1) * 0.3
		samples[i] = bar
	end
	-- (The tab being edited's look: the game's for a kind not restyled.)
	function preview:Refresh()
		local look = Look(editing)
		for i, bar in ipairs(samples) do
			-- (The game's look for a sample: its classic fill and colors.)
			if not FILLS[look.plateCastFill] then
				local info = SAMPLES[i]
				local kind = info.locked and "locked" or (info.channel and "channel" or "cast")
				local atlas = ns.isRetail and C_Texture and C_Texture.GetAtlasInfo
					and C_Texture.GetAtlasInfo(GAME_ATLAS[kind]) and GAME_ATLAS[kind]
				if atlas and bar.SetStatusBarTexture then
					bar:SetStatusBarTexture(atlas)
					bar:SetStatusBarColor(1, 1, 1)
				else
					bar:SetStatusBarTexture(FILLS.smooth)
					bar:SetStatusBarColor(unpack(GAME_COLORS[kind]))
				end
			end
			Apply(bar, look, true, not editing or editing == "PLATE")
		end
	end
	local started = GetTime()
	preview:SetScript("OnUpdate", function()
		local look = Look(editing)
		for _, bar in ipairs(samples) do
			local done = ((GetTime() - started) / SAMPLE_TIME + bar.offset) % 1
			local value = bar.channeling and (1 - done) or done
			bar:SetValue(value)
			bar.value, bar.maxValue = value * SAMPLE_TIME, SAMPLE_TIME
			local width = bar:GetWidth()
			bar.Spark:SetPoint("CENTER", bar, "LEFT", width * value, 0)
			if look.plateCastTimer and states[bar] then
				UpdateTimer(bar, states[bar])
			end
		end
	end)
	kit.AddControl(preview)

	-- (Default's: the presets set the Default tab's settings.)
	rows.PresetMenu({
		{ L["Like the game's"], L["The game's own cast bars (the defaults)."], {} },
		{ L["Flat"], L["A flat fill in your colors on a dark ground, a thin black edge, Arial Narrow, the " ..
			"seconds left."], { plateCastHeight = 1.5, plateCastFill = "flat", plateCastBorder = "thin",
			plateCastFont = "arial",
			plateCastOutline = "thin", plateCastTimer = true } },
		{ L["Smooth"], L["The classic smooth fill in your colors, no border."],
			{ plateCastFill = "smooth", plateCastBorder = "none", plateCastBack = 0.5 } },
		{ L["Cinematic"], L["A quiet flat bar: no icon, spark or border, a soft ground, small outlined text."],
			{ plateCastFill = "flat", plateCastBorder = "none", plateCastBack = 0.35, plateCastIcon = false,
			plateCastSpark = false, plateCastTextSize = 0.9, plateCastOutline = "thin" } },
	}, PRESET_KEYS)

	-- The tabs, in Heal Vision's folder look (ns.FolderTabs): Default, then
	-- each kind of bar, the settings on the panel under them. On a kind's,
	-- Use default settings, and (all but the nameplates') Restyle these bars
	-- beside it; on Default's, a note in their place.
	local TAB_H = ns.FOLDER_TAB_HEIGHT
	local ids, list = { false }, {}
	for _, info in ipairs(BARS) do ids[#ids + 1] = info[1] end
	for i, id in ipairs(ids) do
		list[i] = { id and L[TAB_NAMES[id]] or L["Default"],
			id and L["These cast bars' settings: Default's until you untick Use default settings."]
			or L["The settings every kind of cast bar has while its tab uses the default settings."] }
	end
	-- (Room for the tabs; the panel's top left under it.)
	local tabsRoom = CreateFrame("Frame", nil, content)
	tabsRoom:SetSize(PREVIEW_W, TAB_H + 4)
	stack:Add(tabsRoom, "label")
	local panel, ShowTab, base
	panel, tabs, ShowTab, base = ns.FolderTabs(content, list, function(i) Pick(ids[i] or nil) end)
	panel:SetPoint("TOPLEFT", tabsRoom, "BOTTOMLEFT", -10, 0)
	-- (Tabs sit 8 right of base: the first one 2 left of tabsRoom, as before.)
	base:SetPoint("TOPLEFT", tabsRoom, "BOTTOMLEFT", -10, 0)
	local defaultNote
	local function TabsLook()
		local db = ns.GetDB()
		for i, tab in ipairs(tabs) do
			local id = ids[i] or nil
			local own = id and db and db["plateCastOwn_" .. id]
			tab:SetText((id and L[TAB_NAMES[id]] or L["Default"]) .. (own and " |cffffd100*|r" or ""))
			tab:SetWidth(math.max(56, math.ceil(tab.label:GetStringWidth()) + 16))
			if id == editing then ShowTab(i) end
		end
		ownCheck:SetShown(editing ~= nil)
		restyleCheck:SetShown(editing ~= nil and editing ~= "PLATE")
		defaultNote:SetShown(editing == nil)
		-- (The bar's size: the nameplates' alone.)
		sizes:SetShown(not editing or editing == "PLATE")
	end
	-- (Every setting the page has, Default's and each kind's, for its Reset.)
	for _, key in ipairs(BAR_KEYS) do kit.RecordKey(content, key) end
	for _, info in ipairs(BARS) do
		local id = info[1]
		kit.RecordKey(content, "plateCastOwn_" .. id)
		if id ~= "PLATE" then kit.RecordKey(content, "plateCastOn_" .. id) end
		for _, key in ipairs(BAR_KEYS) do kit.RecordKey(content, key .. "_" .. id) end
	end
	ownCheck = kit.Check(content, false, L["Use default settings"],
		L["Ticked: these cast bars look as the Default tab says. Unticked: as the settings below say (they " ..
		"start as Default's, and are kept while it's ticked)."], function(value)
			local db = ns.GetDB()
			-- (A first untick: the kind starts from Default's settings.)
			if not value and not db["plateCastStarted_" .. editing] then
				for _, key in ipairs(BAR_KEYS) do db[key .. "_" .. editing] = db[key] end
				db["plateCastStarted_" .. editing] = true
			end
			db["plateCastOwn_" .. editing] = not value
			Changed()
			kit.Refresh()
		end)
	ownCheck.Refresh = function(self)
		local db = ns.GetDB()
		self:SetChecked(editing and db and not db["plateCastOwn_" .. editing] or false)
		TabsLook()
	end
	ownCheck.pageSwitch = false
	stack:Add(ownCheck, "check")
	kit.GreyUnless(ownCheck, function(db) return rows.On(db) and Restyled(db) end)
	kit.AddControl(ownCheck)
	restyleCheck = kit.Check(content, false, L["Restyle these bars"],
		L["Ticked: these cast bars take this page's look (the Default tab's, or this tab's own). Unticked: " ..
		"they keep the game's own. Their size stays the game's (yours is sized in Edit Mode)."], function(value)
			ns.GetDB()["plateCastOn_" .. editing] = value
			Changed()
			kit.Refresh()
		end)
	restyleCheck.Refresh = function(self)
		local db = ns.GetDB()
		self:SetChecked(editing and editing ~= "PLATE" and db and db["plateCastOn_" .. editing] or false)
	end
	restyleCheck.pageSwitch = false
	restyleCheck:SetPoint("LEFT", ownCheck.Text or ownCheck.text or ownCheck, "RIGHT", 24, 0)
	kit.GreyUnless(restyleCheck, rows.On)
	kit.AddControl(restyleCheck)
	defaultNote = kit.Label(content, "GameFontHighlightSmall",
		L["Every kind of cast bar looks as this tab says until its own tab has Use default settings unticked."])
	defaultNote:SetPoint("LEFT", ownCheck, "LEFT", 4, 0)
	defaultNote.searchSkip = true

	-- (Sizes and the like as small boxes on a line, colors on one line, each
	-- part's check with its size beside it.)
	stack:Header(content, L["Bar"])
	sizes = rows.Boxes()
	-- (Retail's plates won't say where the bar is: its width there goes with
	-- the health bar's, the Nameplate Style page's Width.)
	if not ns.isRetail then
		sizes:Box(L["W"], Field("plateCastWidth"), 50, 150, 5, "%d", 100,
			L["Its width, next to the game's, about its middle (nameplates only)."], Editable, "%")
	end
	sizes:Box(L["H"], Field("plateCastHeight"), 50, 300, 10, "%d", 100,
		L["Its height, next to the game's (nameplates only). The health bar and name ride up on it."],
		Editable, "%")
	local function Filled(db)
		local fill = rows.Get("plateCastFill")
		if ns.IsGeneralStyle(fill) then fill = ns.GeneralStyleValue("plateCastFill") end
		return Editable(db) and FILLS[fill] ~= nil
	end
	rows.Boxes():Box(L["Dark ground"], Field("plateCastBack"), 0, 100, 5, "%d", 100,
		L["How dark it is behind the fill (with a fill of your own; the game's keeps its own)."], Filled, "%")
	rows.Texture(L["Fill:"], "plateCastFill", L["The game's: its own fill, in its own colors. Below the " ..
		"game's own few: any other addon shares (through LibSharedMedia)."], Editable, { 1, 0.7, 0 })
	local lastColor = rows.Colors(L["Colors:"], {
		{ L["Casting"], COLOR_KEYS.cast, L["Pick the color of a cast."] },
		{ L["Channeling"], COLOR_KEYS.channel, L["Pick the color of a channel."] },
		{ L["Can't be interrupted"], COLOR_KEYS.locked,
			L["Pick the color of a cast or channel that can't be interrupted."] },
		{ L["Interrupted"], COLOR_KEYS.stop,
			L["Pick the color of a cast that was interrupted (when the game says: not in every fight)."] },
	}, Filled)
	rows.Border(L["Border:"], "plateCastBorder", { game = true }, L["The cast bar's border: the game's, or " ..
		"one of ours (Custom: its thickness and color under it)."], Editable)
	rows.Check("plateCastSpark", L["The spark at the fill's end"], nil, Editable)

	stack:Header(content, L["Icon"])
	local icon = rows.Check("plateCastIcon", L["The spell's icon"], nil, Editable)
	rows.Boxes(icon):Box(L["Size"], Field("plateCastIconSize"), 50, 300, 10, "%d", 100,
		L["The icon's size, next to the game's. On nameplates, the health bar and name ride up on it."],
		Editable, "%")
	rows.Check("plateCastShield", L["The shield on casts that can't be interrupted"],
		L["The game's shield over the icon while the cast can't be interrupted."], Editable)
	-- (Seen on retail's plates and game 11509's alike.)
	rows.Check("plateCastImportant", L["The mark on important casts"],
		L["The game's mark on casts it counts as important, ones worth interrupting or getting out of."],
		Editable)
	rows.Check("plateCastTarget", L["Who it's cast at"],
		L["The game's mark and name for who the spell is cast at."], Editable)

	stack:Header(content, L["Text"])
	local text = rows.Check("plateCastText", L["The spell's name"], nil, Editable)
	rows.Boxes(text):Box(L["Size"], Field("plateCastTextSize"), 50, 300, 10, "%d", 100,
		L["Its size, next to the game's."], Editable, "%")
	rows.Font("plateCastFont", nil, Editable)
	rows.Choices(L["Outline:"], "plateCastOutline", {
		{ "general", L["General"], L["As the Style hub's General page says."] },
		{ "game", L["The game's"] },
		{ "none", L["None"] },
		{ "thin", L["Thin"] },
		{ "thick", L["Thick"] },
	}, Editable)
	local timer = rows.Check("plateCastTimer", L["Seconds left at its right end"],
		L["The seconds left on the cast, at the bar's right end (in the same font). Hidden while the game " ..
		"keeps them secret, in some fights."], Editable)
	-- (The panel's bottom under the last row, its right past the widest, the
	-- colors' row: its length goes with the language.)
	panel:SetPoint("BOTTOM", timer, "BOTTOM", 0, -12)
	panel:SetPoint("RIGHT", lastColor, "RIGHT", 14, 0)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Cast Bar Style", L["Cast bars"])
end

-- One sample cast bar, for the General page's nameplate preview: dressed as
-- the page says (:Refresh), and filling again and again.
function ns.MakePlateCastSample(parent)
	local info = SAMPLES[1]
	local bar = MakeSample(parent, info)
	function bar:Refresh()
		local look = ns.PlateCastLook()
		if not FILLS[look.plateCastFill] then
			local atlas = ns.isRetail and C_Texture and C_Texture.GetAtlasInfo
				and C_Texture.GetAtlasInfo(GAME_ATLAS.cast) and GAME_ATLAS.cast
			if atlas and self.SetStatusBarTexture then
				self:SetStatusBarTexture(atlas)
				self:SetStatusBarColor(1, 1, 1)
			else
				self:SetStatusBarTexture(FILLS.smooth)
				self:SetStatusBarColor(unpack(GAME_COLORS.cast))
			end
		end
		Apply(self, look, true, true)
	end
	local started = GetTime()
	bar:HookScript("OnUpdate", function(self)
		local value = ((GetTime() - started) / SAMPLE_TIME) % 1
		self:SetValue(value)
		self.value, self.maxValue = value * SAMPLE_TIME, SAMPLE_TIME
		self.Spark:SetPoint("CENTER", self, "LEFT", self:GetWidth() * value, 0)
		if ns.PlateCastLook().plateCastTimer and states[self] then UpdateTimer(self, states[self]) end
	end)
	return bar
end
