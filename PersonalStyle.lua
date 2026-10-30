-- The Style hub's Personal resources page: how the game's personal resource
-- display (the bars under your character) looks. Its health and power bars'
-- texture, border and background, the health bar's color, each bar's
-- height, and your class resource's size. When the bars come up: the UI
-- Manager's Personal Resources page and the Standard Frames grid
-- (PersonalResources.lua, Frames.lua).
-- Its parts are found by their fields (they differ a little between
-- clients); /cine debug plates lists them.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.prdStyle = true             -- the page's switch (off: these defaults, whatever it's set to)
DEFAULTS.prdTexture = "general"      -- the bars' fill: "game" or a texture (ns.StyleTexturePath; general: General's)
DEFAULTS.prdBorder = "general"       -- their border: "game", "none", "thin", "thick", "custom" (general: General's)
DEFAULTS.prdBorderSize = 1           -- ...the line's thickness, in pixels
DEFAULTS.prdBorderR, DEFAULTS.prdBorderG, DEFAULTS.prdBorderB = 0, 0, 0 -- ...its color
DEFAULTS.prdBack = 0.5               -- ...the dark behind them, with a border of ours (thin, none)
DEFAULTS.prdHealthColor = "game"     -- the health bar: "game", "class" or "custom" (prdHealthR/G/B)
DEFAULTS.prdHealthR, DEFAULTS.prdHealthG, DEFAULTS.prdHealthB = 0.2, 0.8, 0.4
DEFAULTS.prdHealthHeight = 1         -- the health bar's height, times the game's
DEFAULTS.prdPowerHeight = 1          -- the power bar's, times the game's
DEFAULTS.prdPiecesScale = 1          -- your class resource (combo points, holy power, runes...), times its size
DEFAULTS.prdMana = false             -- a mana bar of ours under them, when mana isn't your power (PersonalMana.lua)
DEFAULTS.prdManaColor = "game"       -- ...its color: "game" or "custom" (prdManaR/G/B)
DEFAULTS.prdManaR, DEFAULTS.prdManaG, DEFAULTS.prdManaB = 0, 0.55, 1
DEFAULTS.prdManaHeight = 1           -- ...its height, times the power bar's

local function Look()
	return ns.StyleLook("prdStyle")
end

-- The class's color (yours).
local function ClassColor()
	local _, class = UnitClass("player")
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then return color.r, color.g, color.b end
	return 0.2, 0.8, 0.4
end

local function HealthColor(look)
	if look.prdHealthColor == "class" then
		return ClassColor()
	elseif look.prdHealthColor == "custom" then
		return look.prdHealthR, look.prdHealthG, look.prdHealthB
	end
end

-- The parts: the health bar (in its holder), the power bar, the class
-- resource. Any can be missing.
local function Parts()
	local root = _G.PersonalResourceDisplayFrame
	if not root or (root.IsForbidden and root:IsForbidden()) then return end
	local holder = root.HealthBarsContainer
	local health = holder and holder.healthBar or root.healthbar or root.healthBar
	return root, holder or health, health, root.PowerBar, root.ClassFrameContainer
end

-- The game's own look, as first seen (put back with the look's as the
-- game's): each bar's fill texture and height, its border and background
-- pieces' alpha. Sizes are read once (a size read back is pixel-snapped).
local own = setmetatable({}, { __mode = "k" })
local function OwnOf(frame)
	local saved = own[frame]
	if not saved then
		saved = { height = frame:GetHeight() }
		if frame.GetStatusBarTexture then
			local fill = frame:GetStatusBarTexture()
			saved.file = fill and fill:GetTexture()
			saved.atlas = fill and fill.GetAtlas and fill:GetAtlas()
		end
		own[frame] = saved
	end
	return saved
end
-- (The mana bar's height to start from: the power bar's own.)
function ns.PersonalOwnHeight(frame)
	local height = OwnOf(frame).height
	return type(height) == "number" and height > 0 and height or nil
end

-- A frame's border and background pieces: its fields named so, and its own
-- textures drawn in such art (retail's bars have no field for theirs: one
-- unnamed UI-HUD-CoolDownManager-Bar-BG behind each, its outline in it;
-- /cine debug prdtextures).
local function Trim(frame)
	local pieces = {}
	if type(frame) ~= "table" then return pieces end
	local fill = frame.GetStatusBarTexture and frame:GetStatusBarTexture()
	local found = {}
	-- (Copies of another bar's, on our mana bar: CopyTrim.)
	for _, piece in ipairs(rawget(frame, "cineTrim") or {}) do
		pieces[#pieces + 1] = piece
		found[piece] = true
	end
	for key, value in pairs(frame) do
		if type(key) == "string" and type(value) == "table" and value.SetAlpha and value ~= frame then
			local lower = key:lower()
			if lower:find("border") or lower:find("background") or lower == "bg" then
				pieces[#pieces + 1] = value
				found[value] = true
			end
		end
	end
	if frame.GetRegions then
		for _, region in ipairs({ frame:GetRegions() }) do
			if region ~= fill and not found[region] and region:GetObjectType() == "Texture" then
				local ok, atlas = pcall(function() return region.GetAtlas and region:GetAtlas() end)
				if ok and type(atlas) == "string" and not (issecretvalue and issecretvalue(atlas)) then
					local lower = atlas:lower()
					if lower:find("%-bg$") or lower:find("border") or lower:find("background") then
						pieces[#pieces + 1] = region
					end
				end
			end
		end
	end
	return pieces
end

-- The game's border and background art from one bar onto another (the
-- power bar's onto our mana bar, which has none of its own): each texture
-- piece again, in its art, layer and place. Once.
local function CopyTrim(from, to)
	if not (from and to) or to.cineTrim then return end
	to.cineTrim = {}
	for _, piece in ipairs(Trim(from)) do
		if piece.GetObjectType and piece:GetObjectType() == "Texture" then
			local ok, atlas, file, layer, sublevel = pcall(function()
				local layerNow, sublevelNow = piece:GetDrawLayer()
				return piece.GetAtlas and piece:GetAtlas(), piece:GetTexture(), layerNow, sublevelNow
			end)
			local readable = ok and not (issecretvalue and (issecretvalue(atlas) or issecretvalue(file)))
			if readable and (atlas or file) then
				local copy = to:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
				if type(atlas) == "string" and atlas ~= "" then copy:SetAtlas(atlas) else copy:SetTexture(file) end
				pcall(function() copy:SetVertexColor(piece:GetVertexColor()) end)
				-- (Its points, on ours; placed by any other frame or unreadable: our size.)
				local placed = pcall(function()
					for i = 1, piece:GetNumPoints() do
						local point, relativeTo, relPoint, x, y = piece:GetPoint(i)
						if relativeTo ~= from then error("placed by another frame") end
						copy:SetPoint(point, to, relPoint, x, y)
					end
				end)
				if not placed or copy:GetNumPoints() == 0 then
					copy:ClearAllPoints()
					copy:SetAllPoints()
				end
				to.cineTrim[#to.cineTrim + 1] = copy
			end
		end
	end
end

-- Our border and background, for any border but the game's: a dark ground
-- and a line round the bar (ns.StyleBorder: its thickness and color).
local function MakeSkin(bar)
	local skin = CreateFrame("Frame", nil, bar)
	skin:SetAllPoints()
	skin:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	skin.back = skin:CreateTexture(nil, "BACKGROUND", nil, -8)
	skin.back:SetAllPoints()
	skin.back:SetColorTexture(0, 0, 0, 1)
	skin.border = ns.MakeStyleEdges(skin)
	return skin
end
ns.MakePersonalSkin = MakeSkin

local function DressSkin(skin, look)
	local kind, size, r, g, b = ns.StyleBorder(look, "prdBorder")
	skin:SetShown(kind ~= "game")
	skin.back:SetAlpha(tonumber(look.prdBack) or 0.5)
	skin.border:SetShown(kind == "line")
	if kind == "line" then ns.DressStyleEdges(skin.border, size, r, g, b, 1, true) end
end

local faded = setmetatable({}, { __mode = "k" }) -- piece -> true, while faded out
local skins = setmetatable({}, { __mode = "k" })
local textured = setmetatable({}, { __mode = "k" }) -- bar -> true, while in a fill of ours
local sized = setmetatable({}, { __mode = "k" }) -- holder -> true, while at a height of ours
local dressing = false -- (our own setters: not the game's, for the hooks)

-- One bar (and its holder: the frame whose height it takes, and whose
-- pieces are its border) as look says; look nil: as the game had it.
local function DressBar(bar, holder, look, heightKey, color)
	if not bar then return end
	holder = holder or bar
	local saved = OwnOf(holder)
	local fillSaved = OwnOf(bar)
	dressing = true
	-- Its fill.
	-- (The game's: left alone unless we'd changed it, the power bar's being
	-- set again by the game as your power changes.)
	if look and ns.SetBarTexture(bar, look.prdTexture) then
		textured[bar] = true
	elseif textured[bar] then
		textured[bar] = nil
		local fill = fillSaved.atlas or fillSaved.file
		if fill then bar:SetStatusBarTexture(fill) end
		local now = bar:GetStatusBarTexture()
		if now and now.SetDesaturated then now:SetDesaturated(false) end
	end
	if color then
		bar:SetStatusBarColor(color[1], color[2], color[3])
	end
	-- Its height.
	-- (Left alone at the game's height unless we'd changed it: Edit Mode's
	-- own changes stay.)
	local scale = look and tonumber(look[heightKey]) or 1
	if type(saved.height) == "number" and saved.height > 0 and (scale ~= 1 or sized[holder]) then
		holder:SetHeight(saved.height * scale)
		sized[holder] = scale ~= 1 or nil
	end
	-- Its border and background: the game's, or ours.
	local ours = look and look.prdBorder ~= "game"
	for _, piece in ipairs(Trim(holder)) do
		if ours then
			faded[piece] = true
			piece:SetAlpha(0)
		elseif faded[piece] then
			faded[piece] = nil
			piece:SetAlpha(1)
		end
	end
	if holder ~= bar then
		for _, piece in ipairs(Trim(bar)) do
			if ours then
				faded[piece] = true
				piece:SetAlpha(0)
			elseif faded[piece] then
				faded[piece] = nil
				piece:SetAlpha(1)
			end
		end
	end
	local skin = skins[bar]
	if not skin and ours then
		skin = MakeSkin(bar)
		skins[bar] = skin
	end
	if skin then
		if look then DressSkin(skin, look) else skin:Hide() end
	end
	dressing = false
end

local healthHooked, powerHooked = false, false
local Apply

-- Every part again (the page's settings changing, the bars set up again).
function Apply()
	local root, holder, health, power, pieces = Parts()
	if not root then return end
	-- (The mana bar: shown or not as the page says now, made if it's wanted.)
	if ns.UpdatePersonalMana then ns.UpdatePersonalMana(true) end
	-- (Its cost and the mana after it, on the bars as they are now: PersonalManaCost.lua.)
	if ns.UpdateManaCost then ns.UpdateManaCost() end
	local look = ns.StyleOn("prdStyle") and Look() or nil
	if not look and not next(own) then return end
	local r, g, b
	if look then r, g, b = HealthColor(look) end
	DressBar(health, holder, look, "prdHealthHeight", r and { r, g, b } or nil)
	DressBar(power, nil, look, "prdPowerHeight")
	local mana = ns.PersonalManaBar and ns.PersonalManaBar()
	if mana then
		CopyTrim(power, mana)
		DressBar(mana, nil, look, "prdManaHeight")
		ns.ColorPersonalMana(look)
	end
	local pieceScale = look and tonumber(look.prdPiecesScale) or 1
	if pieces and pieces.SetScale and (pieceScale ~= 1 or sized[pieces]) then
		pieces:SetScale(pieceScale)
		sized[pieces] = pieceScale ~= 1 or nil
	end
	-- The game sets the health bar's color, and the power bar's fill as your
	-- power changes (a druid's form): ours again after it.
	if health and not healthHooked and health.SetStatusBarColor then
		healthHooked = true
		hooksecurefunc(health, "SetStatusBarColor", function(self)
			local now = ns.StyleOn("prdStyle") and Look()
			if dressing or not now then return end
			local cr, cg, cb = HealthColor(now)
			if cr then
				dressing = true
				self:SetStatusBarColor(cr, cg, cb)
				dressing = false
			end
		end)
	end
	if power and not powerHooked and power.SetStatusBarTexture then
		powerHooked = true
		hooksecurefunc(power, "SetStatusBarTexture", function(self)
			local now = ns.StyleOn("prdStyle") and Look()
			if dressing or not (now and ns.StyleTexturePath(now.prdTexture)) then return end
			dressing = true
			ns.SetBarTexture(self, now.prdTexture)
			dressing = false
		end)
	end
end
ns.RefreshPersonalStyle = Apply

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
loader:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
loader:SetScript("OnEvent", function() Apply() end)

-- The page's preview: your health and power bars and class resource,
-- dressed as the look says (drawn here: the game's are hidden out of fights).
local PREVIEW_PIECES = { ROGUE = 5, PALADIN = 5, WARLOCK = 5, DEATHKNIGHT = 6, MONK = 5, EVOKER = 5, DRUID = 5,
	MAGE = 4 }
local PREVIEW_POWER = { 0, 0.55, 1 } -- (mana's blue)

function ns.MakePersonalPreview(parent, width)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 150)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("TOPLEFT", 6, -5)
	caption:SetText(L["Preview"])
	caption.searchSkip = true
	local function Bar(value)
		local bar = CreateFrame("StatusBar", nil, holder)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(value)
		bar:SetWidth(200)
		bar.game = bar:CreateTexture(nil, "BACKGROUND")
		bar.game:SetPoint("TOPLEFT", -2, 2)
		bar.game:SetPoint("BOTTOMRIGHT", 2, -2)
		bar.game:SetColorTexture(0.1, 0.1, 0.1, 0.8)
		bar.skin = MakeSkin(bar)
		return bar
	end
	local health, power, mana = Bar(0.72), Bar(0.55), Bar(0.8)
	health:SetPoint("TOP", holder, "TOP", 0, -54)
	power:SetPoint("TOP", health, "BOTTOM", 0, -3)
	mana:SetPoint("TOP", power, "BOTTOM", 0, -3)
	local pieces = CreateFrame("Frame", nil, holder)
	pieces:SetSize(200, 18)
	pieces.dots = {}
	local _, class = UnitClass("player")
	local count = PREVIEW_PIECES[class or ""] or 5
	for i = 1, count do
		local dot = pieces:CreateTexture(nil, "ARTWORK")
		dot:SetSize(14, 14)
		dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
		dot:SetPoint("CENTER", pieces, "CENTER", (i - (count + 1) / 2) * 18, 0)
		pieces.dots[i] = dot
	end
	-- The game's fills, from the real bars if they're there.
	local function GameFill(bar)
		local saved = bar and own[bar]
		if saved then return saved.atlas, saved.file end
		local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
		if fill then return fill.GetAtlas and fill:GetAtlas(), fill:GetTexture() end
	end
	function holder:Refresh()
		ns.StyleScene(self, 0.62, 0.85)
		local look = Look()
		local _, _, realHealth, realPower = Parts()
		-- (The mana bar while it's ticked: a third bar, under the power bar, in
		-- the power bar's game fill.)
		local withMana = ns.PERSONAL_MANA and look.prdMana and true or false
		mana:SetShown(withMana)
		pieces:SetPoint("TOP", withMana and mana or power, "BOTTOM", 0, -6)
		for _, info in ipairs({ { health, realHealth, "prdHealthHeight", 10 }, { power, realPower, "prdPowerHeight", 8 },
			{ mana, realPower, "prdManaHeight", 8 } }) do
			local bar = info[1]
			if not ns.SetBarTexture(bar, look.prdTexture) then
				local atlas, file = GameFill(info[2])
				bar:SetStatusBarTexture(atlas or file or "Interface\\TargetingFrame\\UI-StatusBar")
				bar:GetStatusBarTexture():SetDesaturated(false)
			end
			bar:SetHeight(info[4] * (tonumber(look[info[3]]) or 1))
			bar.game:SetShown(look.prdBorder == "game")
			DressSkin(bar.skin, look)
		end
		local r, g, b = HealthColor(look)
		health:SetStatusBarColor(r or 0, g or 0.8, b or 0)
		-- (The power bar a Maelstrom-like purple beside the mana bar, else mana's blue.)
		if withMana then
			power:SetStatusBarColor(0.6, 0.3, 1)
		else
			power:SetStatusBarColor(unpack(PREVIEW_POWER))
		end
		if look.prdManaColor == "custom" then
			mana:GetStatusBarTexture():SetDesaturated(true)
			mana:SetStatusBarColor(look.prdManaR or 0, look.prdManaG or 0, look.prdManaB or 0)
		else
			mana:SetStatusBarColor(unpack(PREVIEW_POWER))
		end
		local scale = tonumber(look.prdPiecesScale) or 1
		local cr, cg, cb = ClassColor()
		for i, dot in ipairs(pieces.dots) do
			dot:SetSize(14 * scale, 14 * scale)
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", pieces, "CENTER", (i - (#pieces.dots + 1) / 2) * 18 * scale, 0)
			if i <= 3 then dot:SetVertexColor(cr, cg, cb) else dot:SetVertexColor(0.35, 0.35, 0.35) end
		end
	end
	holder:SetScript("OnShow", holder.Refresh)
	return holder
end

-- The page itself.
local PRESET_KEYS = { "prdTexture", "prdBorder", "prdBorderSize", "prdBorderR", "prdBorderG", "prdBorderB", "prdBack",
	"prdHealthColor", "prdHealthHeight", "prdPowerHeight", "prdPiecesScale", "prdManaHeight" }

function ns.CreatePersonalStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Personal resources"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the personal resource display under your character looks: its health and power bars, and " ..
		"your class resource. When the bars come up: the UI Manager's Personal Resources page."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		Apply() -- (the mana bar too)
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "prdStyle", L["Enable page"],
		L["On: the bars look as this page says. Off: the game's own (the preview shows that too). Each " ..
		"setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "prdStyle")

	preview = ns.MakePersonalPreview(content, 480)
	stack:Add(preview, "label")
	kit.AddControl(preview)

	rows.PresetMenu({
		{ L["Like the game's"], L["The game's bars, as it draws them (the defaults)."], {} },
		{ L["Flat"], L["Flat bars, health in your class color, with a thin black edge."],
			{ prdTexture = "flat", prdBorder = "thin", prdBack = 0.6, prdHealthColor = "class", prdPowerHeight = 0.8,
				prdManaHeight = 0.8 } },
		{ L["Slim"], L["Thin, borderless bars that barely show over the world."],
			{ prdTexture = "flat", prdBorder = "none", prdBack = 0.35, prdHealthColor = "class", prdHealthHeight = 0.5,
				prdPowerHeight = 0.4, prdManaHeight = 0.4, prdPiecesScale = 0.8 } },
		{ L["Cinematic"], L["Soft, thin bars with a fine edge, health in your class color."],
			{ prdTexture = "smooth", prdBorder = "thin", prdBack = 0.4, prdHealthColor = "class",
				prdHealthHeight = 0.7, prdPowerHeight = 0.6, prdManaHeight = 0.6 } },
	}, PRESET_KEYS)

	-- The bars' look: their fill, their border (the game's, a line of ours
	-- or none: its thickness and color), the dark behind ours.
	stack:Header(content, L["Bars"])
	rows.Texture(L["Texture:"], "prdTexture", L["The bars' fill. Below the game's own few: any other addon " ..
		"shares (through LibSharedMedia)."], nil, { 0.25, 0.75, 0.3 })
	rows.Border(L["Border:"], "prdBorder", { game = true }, L["The bars' border: the game's, or one of ours " ..
		"(Custom: its thickness and color under it)."])
	local function Ours(db) return rows.On(db) and Look().prdBorder ~= "game" end
	rows.Slider("prdBack", L["Background"], 0, 100, 5, "%d%%", 100,
		L["How dark it is behind the bars, with a border of ours."], Ours)

	-- Each bar's size, next to the game's.
	stack:Header(content, L["Sizes"])
	local sizes = rows.Boxes()
	sizes:Box(L["Health"], "prdHealthHeight", 0, 100, 5, "%d", 100, L["The health bar's height, next to the game's."],
		nil, "%")
	sizes:Box(L["Power"], "prdPowerHeight", 0, 100, 5, "%d", 100, L["The power bar's height, next to the game's."],
		nil, "%")
	sizes:Box(L["Class resource"], "prdPiecesScale", 0, 100, 5, "%d", 100,
		L["How big your class resource is (combo points, holy power, runes and the like), next to the game's."], nil, "%")
	local function ManaOn(db) return rows.On(db) and Look().prdMana end
	if ns.PERSONAL_MANA then
		sizes:Box(L["Mana"], "prdManaHeight", 0, 100, 5, "%d", 100,
			L["The mana bar's height, next to the power bar's."], ManaOn, "%")
	end

	stack:Header(content, L["Health"])
	local last = rows.Choices(L["Color:"], "prdHealthColor", {
		{ "game", L["The game's"] },
		{ "class", L["Class"], L["Your class's color."] },
		{ "custom", L["Custom"], L["A color of your own (the swatch)."] },
	})
	rows.Swatch(last, "prdHealthColor", { "prdHealthR", "prdHealthG", "prdHealthB" },
		L["The health bar's color, for Custom."])

	-- Mana under the power bar, when it isn't your power (PersonalMana.lua).
	if ns.PERSONAL_MANA then
		stack:Header(content, L["Mana bar"])
		rows.Check("prdMana", L["Show your mana when it isn't your power"],
			L["The game shows only your main power under your character: Maelstrom, Insanity, Astral Power, " ..
			"rage or energy in a form. Ticked, your mana gets a bar of its own under it. When it comes up is the " ..
			"Personal mana bar row on the Standard Frames page."])
		local manaLast = rows.Choices(L["Color:"], "prdManaColor", {
			{ "game", L["The game's"] },
			{ "custom", L["Custom"], L["A color of your own (the swatch)."] },
		}, ManaOn)
		rows.Swatch(manaLast, "prdManaColor", { "prdManaR", "prdManaG", "prdManaB" },
			L["The mana bar's color, for Custom."], ManaOn)
	end

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Personal Style", L["Personal resources"])
end
