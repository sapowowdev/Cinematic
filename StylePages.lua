-- What the Style hub's pages made in their own files share (LetterboxStyle.lua,
-- QuestItemStyle.lua): rows of choices, color swatches, sliders and a row of
-- presets, each greyed out unless the page's switch (or its own test) says,
-- and each change shown at once (changed()).

local ADDON_NAME, ns = ...

-- The Style hub's General page: a switch for every Style page at once (off:
-- each shows the game's look), and settings the pages share. A page's
-- shared setting (ns.ShareStyle) starts on General ("general", or -1 for an
-- outline): it follows General's value until it's given one of its own.
-- General's own "game" (texture, font) and -1 (outline) leave each page at
-- its own default.
ns.DEFAULTS.styleGeneral = true
ns.DEFAULTS.styleTexture = "game"
ns.DEFAULTS.styleFont = "game"
ns.DEFAULTS.styleOutline = -1

ns.DEFAULTS.styleBorder = "game"     -- "game" (each page's own), "none", "thin", "thick" or "custom":
ns.DEFAULTS.styleBorderSize = 1      -- ...custom's thickness, in pixels
ns.DEFAULTS.styleBorderR, ns.DEFAULTS.styleBorderG, ns.DEFAULTS.styleBorderB = 0, 0, 0 -- ...and color

local GENERAL_KEYS = { texture = "styleTexture", font = "styleFont", outline = "styleOutline", border = "styleBorder",
	borderSize = "styleBorderSize", borderR = "styleBorderR", borderG = "styleBorderG", borderB = "styleBorderB" }
-- The pages' shared settings (each defaults to General in its own file):
-- [key] = { kind, own: its value with General at the game's (its default
-- before General), map: General's value as the page takes it }.
local CAST_OUTLINES = { [0] = "none", "thin", "thick" }
local shared = {
	prdTexture = { kind = "texture", own = "game" },
	tooltipBarTexture = { kind = "texture", own = "game" },
	rollBarTexture = { kind = "texture", own = "flat" },
	plateCastFill = { kind = "texture", own = "game" },
	bubblesFont = { kind = "font", own = "game" },
	tooltipFont = { kind = "font", own = "game" },
	questTalkFont = { kind = "font", own = "game" },
	rollFont = { kind = "font", own = "game" },
	questItemFont = { kind = "font", own = "game" },
	combatFont = { kind = "font", own = "game" },
	plateCastFont = { kind = "font", own = "game" },
	bubblesOutline = { kind = "outline", own = 0 },
	tooltipOutline = { kind = "outline", own = 0 },
	questTalkOutline = { kind = "outline", own = 0 },
	rollOutline = { kind = "outline", own = 0 },
	questItemOutline = { kind = "outline", own = 1 },
	combatOutline = { kind = "outline", own = 1 },
	plateCastOutline = { kind = "outline", own = "game", map = function(value) return CAST_OUTLINES[value] end },
}
-- Borders: each page's border (its own default "own"), and its Custom's
-- thickness and color (<key>Size, <key>R/G/B), which follow General's while
-- the border's on General.
for key, own in pairs({ prdBorder = "game", tooltipEdge = "game", bubblesEdge = "thin", plateCastBorder = "game",
	questItemFrame = "game" }) do
	shared[key] = { kind = "border", own = own }
	ns.DEFAULTS[key .. "Size"] = ns.DEFAULTS[key .. "Size"] or 1
	shared[key .. "Size"] = { kind = "borderSize", follows = key }
	for _, channel in ipairs({ "R", "G", "B" }) do
		ns.DEFAULTS[key .. channel] = ns.DEFAULTS[key .. channel] or 0
		shared[key .. channel] = { kind = "border" .. channel, follows = key }
	end
end
ns.SHARED_STYLE = shared -- (the General page's list of who follows it)

local function IsGeneral(value)
	return value == "general" or value == -1
end
ns.IsGeneralStyle = IsGeneral

-- What General gives a shared setting now (gameOnly: General off, or the
-- page: its own default).
local function FromGeneral(entry, gameOnly)
	local db = ns.db
	local value = not gameOnly and db and db.styleGeneral and db[GENERAL_KEYS[entry.kind]] or nil
	if value == nil or value == "game" or value == -1 then
		return entry.own
	end
	return entry.map and entry.map(value) or value
end

-- Whether a Style page (its switch's key) is on: General's and its own.
-- (db: the settings to ask, for the options' tests; else the saved ones.)
function ns.StyleOn(switchKey, db)
	db = db or ns.db
	return db and db.styleGeneral and (not switchKey or db[switchKey]) and true or false
end

-- A page's look, read as its code reads the settings: its own while it's
-- on, else its defaults; a shared setting on General as General says.
local looks = {}
function ns.StyleLook(switchKey)
	local pair = looks[switchKey]
	if not pair then
		local function Proxy(on)
			return setmetatable({}, { __index = function(_, key)
				local source = on and ns.db or ns.DEFAULTS
				local value = source and source[key]
				local entry = shared[key]
				if entry and entry.follows then
					-- (A border's thickness or color: General's while that border's on General.)
					local db = ns.db
					if on and db and db.styleGeneral and IsGeneral(source[entry.follows])
						and db.styleBorder == "custom" then
						return db[GENERAL_KEYS[entry.kind]]
					end
					return value
				end
				if entry and IsGeneral(value) then
					return FromGeneral(entry, not on)
				end
				return value
			end })
		end
		pair = { on = Proxy(true), off = Proxy(false) }
		looks[switchKey] = pair
	end
	return ns.StyleOn(switchKey) and pair.on or pair.off
end

-- A page's border as look says (key: its border setting): "game", "none",
-- "colored" (Tooltips: the unit's or item's color) or "line", then a line's
-- thickness and color. Thin and Thick: 1 and 2 pixels, in thinColor (black
-- if not given); Custom: the page's own (or General's) thickness and color.
function ns.StyleBorder(look, key, thinColor)
	local value = look[key]
	local color = thinColor or { 0, 0, 0 }
	if value == "thin" or value == "thick" then
		return "line", value == "thick" and 2 or 1, color[1], color[2], color[3]
	elseif value == "custom" then
		return "line", math.max(1, math.floor(tonumber(look[key .. "Size"]) or 1)),
			tonumber(look[key .. "R"]) or 0, tonumber(look[key .. "G"]) or 0, tonumber(look[key .. "B"]) or 0
	elseif value == "colored" then
		return "colored", 1
	end
	return value or "game", 0
end

-- Four lines round a frame (made once: ns.DressStyleEdges places them).
local EDGE_SIDES = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
	{ "TOPRIGHT", "BOTTOMRIGHT" } }
function ns.MakeStyleEdges(around, layer)
	local holder = CreateFrame("Frame", nil, around)
	holder:SetAllPoints()
	holder:SetFrameLevel(around:GetFrameLevel() + 2)
	holder.lines = {}
	for i = 1, 4 do
		local line = holder:CreateTexture(nil, layer or "OVERLAY")
		line:SetTexture("Interface\\Buttons\\WHITE8X8")
		holder.lines[i] = line
	end
	return holder
end

-- size pixels thick, in r, g, b (a: its alpha); outside: just outside the
-- frame (else just inside it).
function ns.DressStyleEdges(holder, size, r, g, b, a, outside)
	local key = ("%s:%s"):format(size, outside and 1 or 0)
	if holder.placed ~= key then
		holder.placed = key
		local out = outside and size or 0
		for i, side in ipairs(EDGE_SIDES) do
			local line = holder.lines[i]
			line:ClearAllPoints()
			if i <= 2 then
				local y = i == 1 and out or -out
				line:SetPoint(side[1], holder, side[1], -out, y)
				line:SetPoint(side[2], holder, side[2], out, y)
				line:SetHeight(size)
			else
				local x = i == 3 and -out or out
				line:SetPoint(side[1], holder, side[1], x, 0)
				line:SetPoint(side[2], holder, side[2], x, 0)
				line:SetWidth(size)
			end
		end
	end
	for _, line in ipairs(holder.lines) do line:SetVertexColor(r, g, b, a or 1) end
end

-- A shared setting's value as a page would show it now (for the options:
-- "General (Glass)").
function ns.GeneralStyleValue(key)
	local entry = shared[key]
	return entry and FromGeneral(entry, false)
end

-- The previews' backdrop: a lake at dusk, 2:1 (Media/make_letterbox_scene.py).
local SCENE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\LetterboxScene"

-- The previews show it, or a plain dark ground (the tickbox above each: one
-- setting for them all).
ns.DEFAULTS.styleScene = true
local scenes = setmetatable({}, { __mode = "k" }) -- (frame -> { focus, shade })

-- The scene behind frame (made once, then cut again: call it as frame's size
-- changes), cut to frame's shape from its middle, never stretched: a wide
-- strip shows the band at focus (0 top, 1 bottom: the hills and the lake,
-- 0.55, by default). shade: darker, for text over it (1: as it is).
-- (Cut again for a frame's new size, as it was set up: the General page's
-- previews, held to one size.)
function ns.RecutStyleScene(frame)
	local how = scenes[frame]
	if how then ns.StyleScene(frame, how[1], how[2]) end
end

function ns.StyleScene(frame, focus, shade)
	scenes[frame] = { focus, shade }
	local scene = frame.styleScene
	if not scene then
		scene = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		scene:SetAllPoints()
		frame.styleScene = scene
	end
	if ns.db and ns.db.styleScene == false then
		scene:SetColorTexture(0.11, 0.14, 0.18, 0.95)
		scene:SetVertexColor(1, 1, 1, 1)
		scene:SetTexCoord(0, 1, 0, 1)
		return scene
	end
	scene:SetTexture(SCENE)
	shade = shade or 1
	scene:SetVertexColor(shade, shade, shade, 1)
	local width, height = frame:GetWidth(), frame:GetHeight()
	local aspect = (width and height and height > 0) and width / height or 2
	if aspect >= 2 then
		local part = 2 / aspect
		local top = math.min(math.max((focus or 0.55) - part / 2, 0), 1 - part)
		scene:SetTexCoord(0, 1, top, top + part)
	else
		local cut = (1 - aspect / 2) / 2
		scene:SetTexCoord(cut, 1 - cut, 0, 1)
	end
	return scene
end

-- A toggle button's look: its text gold while it's on, grey while it's off
-- (its normal font: the mouse over it still lights it, as any button).
function ns.StyleToggle(button, on)
	button:SetNormalFontObject(on and "GameFontNormal" or "GameFontDisable")
end

-- A Visions hub page's link to its Style hub page: a small Style button right
-- of the page's title, past its "?" (PageIntro). page: the Style page's name,
-- as ns.OpenOptions takes it. Tooltip: the page's (Options.lua's).
function ns.StyleLink(content, title, page, tip, Tooltip)
	local button = ns.PanelButton(content)
	button:SetSize(70, 20)
	button:SetText(ns.L["Style"])
	button:SetPoint("LEFT", title, "RIGHT", 44, 0)
	Tooltip(button, tip)
	button:SetScript("OnClick", function() ns.OpenOptions(page) end)
	return button
end

-- The Scene button above a preview: the scene behind every preview, or a
-- plain ground (one setting for them all). Tooltip, AddControl: the page's
-- (Options.lua's, as the kit has them). Works with the page's switch off too.
-- Place it as the page places controls.
function ns.StyleSceneButton(content, Tooltip, AddControl)
	local button = ns.PanelButton(content)
	button:SetSize(110, 22)
	button:SetText(ns.L["Scene"])
	Tooltip(button, ns.L["A lake at dusk behind the previews on the Style pages, to see the look over the " ..
		"world. Off: a plain dark ground."])
	local function Apply()
		ns.StyleToggle(button, ns.GetDB().styleScene ~= false)
		for frame, how in pairs(scenes) do ns.StyleScene(frame, how[1], how[2]) end
	end
	button:SetScript("OnClick", function()
		local db = ns.GetDB()
		db.styleScene = db.styleScene == false
		Apply()
	end)
	-- (and as its page shows: the pages are made before the settings may be loaded)
	button.Refresh = Apply
	button.pageSwitch = false
	AddControl(button)
	return button
end

-- The bar textures the Style pages offer: the game's own files, its modern
-- frames' fills (atlases: only those this client has), our own
-- (Media/make_bar_textures.py), then any that other addons share through
-- LibSharedMedia (none of theirs bundled). Each setting holds a value:
-- "game" (the part's own, left alone), one of these by name, or
-- "lsm:<its name>". { value, name, file or atlas, atlas = true } each. The
-- game's modern fills come in their own colors (mana's blue, the cast bars'
-- gold): turned grey, so they take the bar's color as the rest do.
local OURS = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Bars\\"
local TEXTURES = {
	{ "flat", "Flat", "Interface\\Buttons\\WHITE8X8" },
	{ "smooth", "Smooth", "Interface\\TargetingFrame\\UI-StatusBar" },
	{ "raid", "Raid frame", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ "raidpower", "Raid frame power", "Interface\\RaidFrame\\Raid-Bar-Resource-Fill" },
	{ "oldtarget", "Old target frame", "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
	{ "skills", "Skill bar", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	{ "playerhealth", "Player frame health", "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health", atlas = true },
	{ "playermana", "Player frame mana", "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana", atlas = true },
	{ "targethealth", "Target frame health", "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health", atlas = true },
	-- (Retail's nameplates' fill, the same in every one of its Styles, and the Cooldown Manager's.)
	{ "platemodern", "Nameplate", "UI-HUD-CoolDownManager-Bar", atlas = true },
	{ "castbar", "Cast bar", "UI-CastingBar-Filling-Standard", atlas = true },
	{ "channelbar", "Channel bar", "UI-CastingBar-Filling-Channel", atlas = true },
	{ "glass", "Glass", OURS .. "Glass" },
	{ "soft", "Soft", OURS .. "Soft" },
	{ "striped", "Striped", OURS .. "Striped" },
	{ "minimal", "Minimal", OURS .. "Minimal" },
	{ "rounded", "Rounded", OURS .. "Rounded" },
}

-- Whether this client has a texture (an atlas: the game says; a file: assumed).
local function Has(info)
	if not info.atlas then return true end
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(info[3]) ~= nil or false
end

local function SharedMedia()
	local stub = _G.LibStub
	return stub and stub("LibSharedMedia-3.0", true)
end

-- A texture value's file or atlas, whether it's an atlas, and whether it's
-- to be turned grey (nil: the game's own, or one this client doesn't have,
-- or a shared one no longer there).
function ns.StyleTexturePath(value)
	if type(value) ~= "string" or value == "game" then return nil end
	for _, info in ipairs(TEXTURES) do
		if info[1] == value then
			if Has(info) then return info[3], info.atlas or false, info.atlas or false end
			return nil
		end
	end
	local name = value:match("^lsm:(.+)")
	local media = name and SharedMedia()
	if media then
		local ok, path = pcall(media.Fetch, media, "statusbar", name, true)
		if ok and path then return path, false, false end
	end
end

-- A status bar's fill as a value says (turned grey where it's to be);
-- false if the value has no texture (the game's own: left alone).
function ns.SetBarTexture(bar, value)
	local path, _, grey = ns.StyleTexturePath(value)
	if not path then return false end
	bar:SetStatusBarTexture(path)
	local fill = bar:GetStatusBarTexture()
	if fill and fill.SetDesaturated then fill:SetDesaturated(grey) end
	return true
end

-- A texture (a strip, say) showing a value's texture; false if none.
function ns.SetStyleTexture(texture, value)
	local path, atlas, grey = ns.StyleTexturePath(value)
	if not path then return false end
	if atlas then texture:SetAtlas(path) else texture:SetTexture(path) end
	texture:SetDesaturated(grey)
	return true
end

-- A texture value's name, as the lists show it.
local function TextureName(value)
	if value == nil or value == "game" then return ns.L["The game's"] end
	for _, info in ipairs(TEXTURES) do
		if info[1] == value then return ns.L[info[2]] end
	end
	return type(value) == "string" and value:match("^lsm:(.+)") or tostring(value)
end

-- The list, for a dropdown: { value, text, texture, atlas } each, the
-- game's first. game: the first entry's name for the part's own ("The game's").
-- key: a page's shared setting, for a General entry first (named for what
-- General gives it now).
function ns.StyleTextureChoices(game, key)
	local list = {}
	if key and ns.GeneralStyleValue(key) ~= nil then
		local value = ns.GeneralStyleValue(key)
		local path, atlas = ns.StyleTexturePath(value)
		list[1] = { value = "general", text = ns.L["General"] .. " (" .. (value == "game" and (game or
			ns.L["The game's"]) or TextureName(value)) .. ")", texture = path, atlas = atlas }
	end
	list[#list + 1] = { value = "game", text = game or ns.L["The game's"] }
	local known = {}
	for _, info in ipairs(TEXTURES) do
		if Has(info) then
			list[#list + 1] = { value = info[1], text = ns.L[info[2]], texture = info[3], atlas = info.atlas }
			known[info[3]] = true
		end
	end
	local media = SharedMedia()
	if media and media.List then
		local ok, names = pcall(media.List, media, "statusbar")
		local shared = {}
		for _, name in ipairs(ok and names or {}) do
			local path = ns.StyleTexturePath("lsm:" .. name)
			if path and not known[path] then shared[#shared + 1] = { value = "lsm:" .. name, text = name, texture = path } end
		end
		table.sort(shared, function(a, b) return a.text:lower() < b.text:lower() end)
		for _, choice in ipairs(shared) do list[#list + 1] = choice end
	end
	return list
end

-- /cine debug textures: a strip of every texture in the list (tinted green),
-- with its name, to see which this client really has (a file it doesn't
-- shows as a plain green block). Again, or a click, to close.
local sampler
function ns.ShowStyleTextures()
	if sampler and sampler:IsShown() then
		sampler:Hide()
		return
	end
	if not sampler then
		sampler = CreateFrame("Button", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
		sampler:SetFrameStrata("DIALOG")
		sampler:SetPoint("CENTER")
		if sampler.SetBackdrop then
			sampler:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
				edgeSize = 1 })
			sampler:SetBackdropColor(0, 0, 0, 0.9)
			sampler:SetBackdropBorderColor(1, 0.82, 0, 1)
		end
		sampler:SetScript("OnClick", sampler.Hide)
		sampler.rows = {}
	end
	local choices = ns.StyleTextureChoices()
	for _, row in ipairs(sampler.rows) do row.name:Hide(); row.strip:Hide() end
	local missing = {}
	for _, info in ipairs(TEXTURES) do
		if not Has(info) then missing[#missing + 1] = info[3] end
	end
	for i = 2, #choices do
		local row = sampler.rows[i]
		if not row then
			row = { name = sampler:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
				strip = sampler:CreateTexture(nil, "ARTWORK") }
			row.name:SetPoint("TOPLEFT", sampler, "TOPLEFT", 10, -10 - (i - 2) * 18)
			row.strip:SetSize(200, 12)
			row.strip:SetPoint("LEFT", sampler, "TOPLEFT", 190, -10 - (i - 2) * 18 - 6)
			sampler.rows[i] = row
		end
		local choice = choices[i]
		row.name:SetText(choice.text)
		if choice.atlas then row.strip:SetAtlas(choice.texture) else row.strip:SetTexture(choice.texture) end
		row.strip:SetDesaturated(choice.atlas and true or false)
		row.strip:SetVertexColor(0.3, 0.8, 0.35, 1)
		row.name:Show()
		row.strip:Show()
	end
	sampler:SetSize(410, 20 + (#choices - 1) * 18)
	sampler:Show()
	ns.Print(("Textures: %d in the list (%s); click the box or run this again to close."):format(#choices - 1,
		SharedMedia() and "with other addons' shared ones" or "no LibSharedMedia addon loaded"))
	if #missing > 0 then
		ns.Print("Atlases this client doesn't have (left out): " .. table.concat(missing, ", "))
	end
end

-- /cine debug platetextures: the textures your target's nameplate (or the
-- nearest one up) is drawn with: each bar's fill, and every other shown
-- texture's atlas or file, to find the game's nameplate Style looks (switch
-- the game's Style and run it again). which "prd": the personal resource
-- display's instead (/cine debug prdtextures), each texture's alpha too, to
-- find its border pieces.
function ns.ReportPlateTextures(which)
	local function Plain(value)
		return value ~= nil and not (issecretvalue and issecretvalue(value))
	end
	local function Asset(texture)
		local ok, atlas = pcall(function() return texture.GetAtlas and texture:GetAtlas() end)
		if ok and Plain(atlas) and atlas ~= "" then return "atlas " .. atlas end
		local fileOk, file = pcall(texture.GetTexture, texture)
		if fileOk and Plain(file) then return "file " .. tostring(file) end
		return "?"
	end
	local function Name(region)
		local ok, name = pcall(region.GetDebugName, region)
		name = ok and Plain(name) and name or "?"
		return (name:gsub("^NamePlate%d+%.", ""):gsub("^PersonalResourceDisplayFrame%.", ""))
	end
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
	plate = plate or plates[1]
	local style = {}
	for _, cvar in ipairs({ "nameplateStyle", "NamePlateStyle", "nameplateHealthBarStyle" }) do
		local ok, value = pcall(GetCVar, cvar)
		if ok and value ~= nil then style[#style + 1] = cvar .. "=" .. tostring(value) end
	end
	local root
	if which == "prd" then
		root = _G.PersonalResourceDisplayFrame
		local look = ns.StyleLook("prdStyle")
		ns.Print(("Personal resource textures: %s, %s, page %s, border %s (%s), texture %s"):format(
			ns.isRetail and "retail" or "classic", InCombatLockdown() and "in combat" or "out of combat",
			ns.StyleOn("prdStyle") and "on" or "off", tostring(look.prdBorder), tostring(ns.GetDB().prdBorder),
			tostring(look.prdTexture)))
		if not root then
			ns.Print("No personal resource display on this client.")
			return
		end
	else
		ns.Print(("Plate textures: %s, %s, %d plates up, target %s; %s"):format(ns.isRetail and "retail" or "classic",
			InCombatLockdown() and "in combat" or "out of combat", #plates, UnitExists("target") and "yes" or "no",
			#style > 0 and table.concat(style, " ") or "no style CVar found"))
		if not plate then
			ns.Print("No nameplate up: target an enemy (with its plate showing) and run it again.")
			return
		end
		root = plate.UnitFrame or plate
	end
	if root.IsForbidden and root:IsForbidden() then
		ns.Print("This plate is closed to addons (a friendly plate in an instance?): try an enemy's.")
		return
	end
	local lines, seen = 0, {}
	local function Line(text)
		lines = lines + 1
		if lines <= 40 then ns.Print("  " .. text) end
	end
	local function Walk(frame, depth)
		if depth > 5 or seen[frame] then return end
		seen[frame] = true
		local shownOk, shown = pcall(frame.IsShown, frame)
		if shownOk and Plain(shown) and not shown then return end
		if frame.GetStatusBarTexture then
			local fill = frame:GetStatusBarTexture()
			if fill then
				seen[fill] = true
				Line(("bar %s: fill %s"):format(Name(frame), Asset(fill)))
			end
		end
		for _, region in ipairs({ frame:GetRegions() }) do
			if not seen[region] and region:GetObjectType() == "Texture" then
				local ok, regionShown = pcall(region.IsShown, region)
				if ok and Plain(regionShown) and regionShown then
					local alphaOk, alpha = pcall(region.GetEffectiveAlpha or region.GetAlpha, region)
					local shownAlpha = alphaOk and Plain(alpha) and (" alpha %.2f"):format(alpha) or ""
					Line(("%s: %s%s"):format(Name(region), Asset(region), which == "prd" and shownAlpha or ""))
				end
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			if not (child.IsForbidden and child:IsForbidden()) then Walk(child, depth + 1) end
		end
	end
	pcall(Walk, root, 0)
	if lines > 40 then ns.Print(("  ...and %d more."):format(lines - 40)) end
end

-- The rows for a page: kit (Options.lua's ns.lowHealthKit), its content and
-- stack, changed() after each change, and its switch's key. fieldOf: for a
-- page with tabs (the Unit frames page), a setting's key -> the field its
-- controls edit now (Options.lua's KeyGet/KeyPut); the key itself if not.
function ns.StyleRows(kit, content, stack, changed, switchKey, fieldOf)
	local rows = {}
	local function On(db) return ns.StyleOn(switchKey, db) end
	rows.On = On
	local K = fieldOf or function(key) return key end
	local function Get(key) return ns.StyleKeyGet(K(key)) end
	local function Put(key, value) ns.StyleKeyPut(K(key), value) end
	rows.Get, rows.Put = Get, Put

	-- A row of choices for key, after its name: { value, text, tip } each.
	-- Gives the last, to put a color swatch after.
	function rows.Choices(label, key, list, test)
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetWidth(150)
		local last
		for _, info in ipairs(list) do
			local choice = kit.Choice(content, K(key), info[1], info[2], info[3])
			choice:HookScript("OnClick", changed)
			if last then
				choice:SetPoint("LEFT", last.Text or last.text, "RIGHT", 16, 0)
			else
				choice:SetPoint("LEFT", name, "RIGHT", 4, 0)
			end
			kit.GreyUnless(choice, test or On)
			last = choice
		end
		return last
	end

	-- A color's swatch after a row of choices: its R, G and B settings (keys);
	-- a pick puts key on Custom (key nil: a color of its own, no choices).
	function rows.Swatch(after, key, keys, tip, test)
		local swatch = CreateFrame("Button", nil, content)
		swatch:SetSize(18, 18)
		swatch:SetPoint("LEFT", after.Text or after.text or after, "RIGHT", 10, 0)
		local border = swatch:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.6, 0.6, 0.6, 1)
		local color = swatch:CreateTexture(nil, "ARTWORK")
		color:SetPoint("TOPLEFT", 2, -2)
		color:SetPoint("BOTTOMRIGHT", -2, 2)
		kit.Tooltip(swatch, tip)
		swatch:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		swatch:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		swatch.Refresh = function()
			color:SetColorTexture(Get(keys[1]) or 0, Get(keys[2]) or 0, Get(keys[3]) or 0, 1)
		end
		swatch:SetScript("OnClick", function()
			kit.OpenColorPicker(Get(keys[1]) or 0, Get(keys[2]) or 0, Get(keys[3]) or 0, function(r, g, b)
				Put(keys[1], r)
				Put(keys[2], g)
				Put(keys[3], b)
				if key then Put(key, "custom") end
				changed()
				kit.Refresh()
			end)
		end)
		kit.GreyUnless(swatch, test or On)
		kit.AddControl(swatch)
		return swatch
	end

	-- A color on a row of its own: its name, then its swatch.
	function rows.Color(label, keys, tip, test)
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 22) -- (room for the swatch, rows of them one under another)
		return rows.Swatch(name, nil, keys, tip, test)
	end

	-- A Font: row, its dropdown (ns.QUEST_ITEM_FONTS) just after the word; the
	-- row as tall as the dropdown, so the next row clears it.
	-- (A shared one: General first, named for the font it gives the page.)
	local function FontName(value)
		for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do
			if info[1] == value then return info[2] end
		end
		return tostring(value)
	end
	function rows.Font(key, tip, test)
		local font = kit.Dropdown(content, K(key), function()
			local list = {}
			local general = ns.GeneralStyleValue(key)
			if general ~= nil then
				list[1] = { value = "general", text = ns.L["General"] .. " (" .. FontName(general) .. ")" }
			end
			for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do list[#list + 1] = { value = info[1], text = info[2] } end
			return list
		end, 200, changed)
		if not font then return end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", ns.L["Font:"]), "label")
		name:SetHeight(30)
		name:SetJustifyV("MIDDLE")
		font:SetPoint("LEFT", name, "RIGHT", 10, 0)
		kit.GreyUnless(font, test or On)
		kit.Tooltip(font, tip)
		return font
	end

	-- A texture row: its name, then a dropdown of the textures with a strip of
	-- each, the one picked shown in the closed dropdown too. tint: the
	-- strips' color ({ r, g, b }).
	-- game: the first entry's name for the part's own ("The game's").
	function rows.Texture(label, key, tip, test, tint, game)
		local dropdown = kit.Dropdown(content, K(key), function()
			local list = ns.StyleTextureChoices(game, key)
			for _, choice in ipairs(list) do choice.tint = tint end
			return list
		end, 200, changed)
		if not dropdown then return end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 30)
		name:SetJustifyV("MIDDLE")
		dropdown:SetPoint("LEFT", name, "RIGHT", 4, 0)
		-- (The picked one's strip, just right of the dropdown: its name has the
		-- dropdown's whole width.)
		local strip = dropdown:CreateTexture(nil, "ARTWORK")
		strip:SetSize(80, 12)
		strip:SetPoint("LEFT", dropdown, "RIGHT", 8, 0)
		local refresh = dropdown.Refresh
		dropdown.Refresh = function(self)
			refresh(self)
			local value = ns.GetDB() and Get(key)
			if ns.IsGeneralStyle(value) then value = ns.GeneralStyleValue(key) end
			local shown = value ~= nil and ns.SetStyleTexture(strip, value) or false
			strip:SetShown(shown)
			if shown then
				local t = tint or { 0.3, 0.75, 0.35 }
				strip:SetVertexColor(t[1], t[2], t[3], 1)
			end
		end
		kit.GreyUnless(dropdown, test or On)
		if tip then kit.Tooltip(dropdown, tip) end
		return dropdown
	end

	-- A dropdown row: its name, then the dropdown (list: a function giving
	-- { value, text } each, read as it opens).
	local function DropdownRow(label, key, list, tip, test)
		local dropdown = kit.Dropdown(content, K(key), list, 200, changed)
		if not dropdown then return end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 30)
		name:SetJustifyV("MIDDLE")
		dropdown:SetPoint("LEFT", name, "RIGHT", 4, 0)
		kit.GreyUnless(dropdown, test or On)
		if tip then kit.Tooltip(dropdown, tip) end
		return dropdown
	end
	rows.Dropdown = DropdownRow

	-- An outline: names[0..maxV] ("None", "Thin"...); a shared one has General
	-- first (named for the outline it gives); own: an entry at -1 by that
	-- name (General's own "Each page's own").
	function rows.Outline(key, label, maxV, names, tip, test, own)
		return DropdownRow(label .. ":", key, function()
			local list = {}
			local general = ns.GeneralStyleValue(key)
			if general ~= nil then
				list[1] = { value = -1, text = ns.L["General"] .. " (" .. (names[general] or "") .. ")" }
			elseif own then
				list[1] = { value = -1, text = own }
			end
			for value = 0, maxV do list[#list + 1] = { value = value, text = names[value] or tostring(value) } end
			return list
		end, tip, test)
	end

	-- A border: its dropdown (General first where it's shared; opts.game: the
	-- game's own, by that name if a string; opts.colored: Tooltips' In its
	-- color), then Custom's thickness and color on a line under it.
	local BORDER_NAMES = { game = "The game's", none = "None", thin = "Thin", thick = "Thick", custom = "Custom",
		colored = "In its color" }
	function rows.Border(label, key, opts, tip, test)
		opts = opts or {}
		local function Name(value)
			if value == "game" and type(opts.game) == "string" then return opts.game end
			return ns.L[BORDER_NAMES[value] or "None"]
		end
		local dropdown = DropdownRow(label, key, function()
			local list = {}
			local general = ns.GeneralStyleValue(key)
			if general ~= nil then
				list[1] = { value = "general", text = ns.L["General"] .. " (" .. Name(general) .. ")" }
			end
			if opts.game then list[#list + 1] = { value = "game", text = Name("game") } end
			for _, value in ipairs({ "none", "thin", "thick" }) do list[#list + 1] = { value = value, text = Name(value) } end
			if opts.colored then list[#list + 1] = { value = "colored", text = Name("colored") } end
			list[#list + 1] = { value = "custom", text = Name("custom") }
			return list
		end, tip, test)
		-- (Custom's: greyed unless it's picked.)
		local function Custom(db) return (test or On)(db) and Get(key) == "custom" end
		local line = rows.Boxes()
		line:Box(ns.L["Thickness"], K(key .. "Size"), 1, 10, 1, "%d", 1, ns.L["How thick the border is, in pixels."],
			Custom, "px")
		local color = kit.Label(content, "GameFontHighlight", ns.L["Color"])
		color:SetPoint("LEFT", line, "RIGHT", 6, 0)
		rows.Swatch(color, key, { key .. "R", key .. "G", key .. "B" },
			ns.L["The border's color. Picking one turns it to Custom."], test)
		return dropdown
	end

	-- A number: a box with its name before it (the Style pages' sliders, as
	-- boxes, to save room). fmt: "%d%%" and the like (what's after the number
	-- shown after the box), or a function for the box's text.
	function rows.Slider(key, label, minV, maxV, step, fmt, scale, tip, test)
		local unit, shown, width
		if type(fmt) == "function" then
			shown, width = fmt, 70
		else
			local number, after = tostring(fmt):match("^(%%[%d%.]*[df])%s*(.*)$")
			shown = number or "%d"
			unit = after and after:gsub("%%%%", "%%") or nil
			if unit == "" then unit = nil end
		end
		local line = rows.Boxes()
		line:Box(label, K(key), minV, maxV, step, shown, scale, tip, test, unit, width)
		return line
	end

	-- A line of small number boxes (Options.lua's BoxLine), on a line of its
	-- own, or beside after (a check, say). Its :Box(label, key, min, max,
	-- step, fmt, scale, tip, test, unit) adds one, greyed as the rest.
	function rows.Boxes(after)
		local line = kit.BoxLine(content)
		if after then
			line:SetPoint("LEFT", after.Text or after.text or after, "RIGHT", 24, 0)
		else
			stack:Add(line, "label")
		end
		local add = line.Box
		function line.Box(_, label, key, minV, maxV, step, fmt, scale, tip, test, unit, width)
			local box, name = add(line, label, key, minV, maxV, step, fmt, scale, tip, changed, width, unit)
			kit.GreyUnless(box, test or On)
			local refresh = box.Refresh
			box.Refresh = function(self)
				refresh(self)
				local on = (test or On)(ns.GetDB()) and 1 or 0.5
				self:SetAlpha(on)
				name:SetAlpha(on)
			end
			return box
		end
		return line
	end

	-- Colors on one line: { name, keys, tip } each, its name then its swatch.
	function rows.Colors(label, list, test)
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 22)
		local last = name
		for i, info in ipairs(list) do
			local each = kit.Label(content, "GameFontHighlightSmall", info[1])
			each:SetPoint("LEFT", last, "RIGHT", i == 1 and 4 or 14, 0)
			each.searchLabel = info[1]
			last = rows.Swatch(each, nil, info[2], info[3], test)
		end
		return last
	end

	function rows.Check(key, label, tip, test)
		local check = stack:Add(kit.Check(content, K(key), label, tip, function(value)
			Put(key, value)
			changed()
			kit.Refresh()
		end), "check")
		kit.GreyUnless(check, test or On)
		return check
	end

	-- A row of preset buttons, width wide: { name, tip, settings } each; a
	-- pick turns the page on and sets keys as its settings say, the rest as
	-- their defaults.
	function rows.Presets(presets, keys, width)
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(width, 24)
		stack:Add(row, "label")
		local last
		for _, preset in ipairs(presets) do
			local button = ns.PanelButton(row)
			button:SetText(preset[1])
			button:SetSize(math.max(110, button:GetFontString():GetStringWidth() + 24), 22)
			if last then
				button:SetPoint("LEFT", last, "RIGHT", 8, 0)
			else
				button:SetPoint("LEFT", row, "LEFT", 0, 0)
			end
			kit.Tooltip(button, preset[2])
			button:SetScript("OnClick", function()
				local db = ns.GetDB()
				db[switchKey] = true
				for _, key in ipairs(keys) do
					local value = preset[3][key]
					if value == nil then value = ns.DEFAULTS[key] end
					db[key] = value
				end
				changed()
				kit.Refresh()
			end)
			button.Refresh = function() end
			kit.GreyUnless(button, On)
			kit.AddControl(button)
			last = button
		end
		return row
	end

	return rows
end
