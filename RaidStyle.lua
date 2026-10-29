-- The Style hub's Raid frames page: how the game's compact frames look, the
-- raid's, the party's when the game draws it raid-style, and retail's arena
-- frames: their health bar's texture, border and color, their background,
-- and their names' color, font, outline and size. A Default tab, and Raid,
-- Party and Arena tabs that follow it until "Use default settings" is
-- unticked (as the Unit frames page's do). Which parts show: the Standard
-- Frames page's party and raid rows (Frames.lua). The bars and names are
-- dressed by the Unit frames page's code (UnitStyle.lua), reading this
-- page's settings (rf...) as its own (uf...).

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.rfStyle = true

local GROUPS = { { "RAID", "Raid" }, { "PARTY", "Party" }, { "ARENA", "Arena" } }

local KEYS = {
	rfTexture = "general",       -- the health bar's fill (ns.StyleTexturePath)
	rfBorder = "general",        -- each frame's border: "game", "none", "thin", "thick", "custom" (ns.StyleBorder)
	rfBorderSize = 1, rfBorderR = 0, rfBorderG = 0, rfBorderB = 0,
	rfBack = 0.5,                -- the dark behind the bar, with a border of ours
	rfGround = 1,                -- the game's background behind each frame, its opacity
	rfHealthColor = "game",      -- the health bar: "game", "class" (class or reaction) or "custom"
	rfHealthR = 0.2, rfHealthG = 0.8, rfHealthB = 0.4,
	rfNameColor = "game",        -- the name: "game", "class" or "white"
	rfFont = "general",          -- the name's font (ns.QUEST_ITEM_FONTS' names)
	rfOutline = -1,              -- ...outline: 0 none, 1 thin, 2 thick (-1: General's)
	rfNameSize = 1,              -- ...times its usual size
}
local SHARED = { rfTexture = { "texture", "game" }, rfFont = { "font", "game" }, rfOutline = { "outline", 0 },
	rfBorder = { "border", "game" } }

local function Share(key, suffix)
	local entry = SHARED[key]
	if not entry then return end
	local shared = ns.SHARED_STYLE
	shared[key .. suffix] = { kind = entry[1], own = entry[2] }
	if entry[1] == "border" then
		for _, part in ipairs({ "Size", "R", "G", "B" }) do
			local follow = { kind = part == "Size" and "borderSize" or "border" .. part, follows = key .. suffix }
			shared[key .. part .. suffix] = follow
			shared[key .. suffix .. part] = follow
		end
	end
end

for key, value in pairs(KEYS) do DEFAULTS[key] = value end
for key in pairs(SHARED) do Share(key, "") end
for _, group in ipairs(GROUPS) do
	local id = group[1]
	DEFAULTS["rfOwn_" .. id] = false
	for key, value in pairs(KEYS) do DEFAULTS[key .. "_" .. id] = value end
	for key in pairs(SHARED) do Share(key, "_" .. id) end
	for _, part in ipairs({ "Size", "R", "G", "B" }) do
		DEFAULTS["rfBorder_" .. id .. part] = DEFAULTS["rfBorder" .. part .. "_" .. id]
	end
end

-- A group's look, read as the Unit frames page's keys (ufTexture -> rfTexture...):
-- its own settings while its "Use default settings" is unticked, else Default's.
local views = {}
local function View(id)
	local view = views[id]
	if not view then
		view = setmetatable({}, { __index = function(_, key)
			key = key:gsub("^uf", "rf")
			local look = ns.StyleLook("rfStyle")
			local db = ns.db
			if db and ns.StyleOn("rfStyle") and db["rfOwn_" .. id] then
				local part = key:match("^rfBorder(%u%l*)$")
				if part and part ~= "" then return look["rfBorder_" .. id .. part] end
				return look[key .. "_" .. id]
			end
			return look[key]
		end })
		views[id] = view
	end
	return view
end
ns.RaidStyleView = View

-- Which group a compact frame is in, by its name (nil: not one of these,
-- like a nameplate's on the classic clients).
local function GroupOf(frame)
	local ok, name = pcall(frame.GetName, frame)
	if not (ok and type(name) == "string") then return nil end
	if name:find("^CompactPartyFrame") then return "PARTY" end
	if name:find("^CompactArenaFrame") then return "ARENA" end
	if name:find("^CompactRaid") then return "RAID" end
end

-- Every compact frame up now.
local function Members()
	local list = {}
	local function Add(frame)
		if frame and not (frame.IsForbidden and frame:IsForbidden()) then list[#list + 1] = frame end
	end
	for i = 1, 5 do
		Add(_G["CompactPartyFrameMember" .. i])
		Add(_G["CompactPartyFramePet" .. i])
		Add(_G["CompactArenaFrameMember" .. i])
	end
	for i = 1, 40 do Add(_G["CompactRaidFrame" .. i]) end
	for group = 1, 8 do
		for member = 1, 5 do Add(_G["CompactRaidGroup" .. group .. "Member" .. member]) end
	end
	return list
end

local BORDERS = { "horizTopBorder", "horizBottomBorder", "vertLeftBorder", "vertRightBorder" }
local touched = setmetatable({}, { __mode = "k" }) -- texture -> true, while we've set its alpha
local function SetAlphaOf(texture, alpha)
	if not (texture and texture.SetAlpha) then return end
	if alpha ~= 1 then
		touched[texture] = true
		texture:SetAlpha(alpha)
	elseif touched[texture] then
		touched[texture] = nil
		texture:SetAlpha(1)
	end
end

local dressing = false
local skinned = setmetatable({}, { __mode = "k" }) -- health bar -> true, once it has our border's pieces
-- One compact frame as its group's look says.
local function Dress(frame)
	if dressing or not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	local id = GroupOf(frame)
	if not id then return end
	local active = ns.StyleOn("rfStyle")
	local view = active and View(id) or nil
	local unit = frame.displayedUnit or frame.unit
	dressing = true
	-- (Our border's pieces are made out of fights only: these frames are the
	-- game's secure buttons. Colors and textures can change any time.)
	local health = frame.healthBar
	if health and (not InCombatLockdown() or not view or view.ufBorder == "game" or skinned[health]) then
		local r, g, b
		if view and view.ufHealthColor == "class" then
			r, g, b = ns.UnitStyleColor(unit)
		elseif view and view.ufHealthColor == "custom" then
			r, g, b = view.ufHealthR, view.ufHealthG, view.ufHealthB
		end
		ns.UnitStyleDressBar(health, view, r, g, b)
		if view and view.ufBorder ~= "game" then skinned[health] = true end
	end
	ns.UnitStyleDressName(frame.name, view, unit)
	-- (The game's border round the frame faded out for ours; its background as
	-- the page says.)
	local ours = view and view.ufBorder ~= "game"
	for _, field in ipairs(BORDERS) do SetAlphaOf(frame[field], ours and 0 or 1) end
	SetAlphaOf(frame.background, view and tonumber(view.ufGround) or 1)
	dressing = false
end

function ns.RefreshRaidStyle()
	if not ns.db then return end
	for _, frame in ipairs(Members()) do Dress(frame) end
end

-- The game sets a frame up, recolors its health and writes its name as
-- members come and go: ours again after it.
for _, name in ipairs({ "DefaultCompactUnitFrameSetup", "DefaultCompactMiniFrameSetup", "CompactUnitFrame_UpdateAll",
	"CompactUnitFrame_UpdateHealthColor", "CompactUnitFrame_UpdateName" }) do
	if type(_G[name]) == "function" then hooksecurefunc(name, Dress) end
end
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
	watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent", function() ns.RefreshRaidStyle() end)

-- The preview: a party column and a raid grid, each tile dressed as its
-- group's look says (a tile clicked opens its tab: onPick(id)).
local CLASSES = { "WARRIOR", "PALADIN", "MAGE", "ROGUE", "HUNTER", "WARLOCK", "DRUID", "SHAMAN", "DEATHKNIGHT",
	"MONK" }
local NAMES = { "Vedeth", "Lumen", "Maketh", "Sly", "Ashka", "Dravin", "Oakhorn", "Tidra", "Grimm", "Pell" }
local HEALTH = { 0.9, 0.55, 1, 0.3, 0.8, 0.85, 1, 0.5, 0.75, 0.95 }
local GAME_FILL = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]

local function ClassColor(class)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then return color.r, color.g, color.b end
	return 0, 0.8, 0
end

function ns.MakeRaidStylePreview(parent, width, onPick)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 210)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("TOPLEFT", 6, -5)
	caption:SetText(L["Preview"])
	caption.searchSkip = true
	local tiles = {}
	local function Tile(id, i, x, y, w, h)
		local tile = CreateFrame("Button", nil, holder)
		tile:SetSize(w, h)
		tile:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
		tile.ground = tile:CreateTexture(nil, "BACKGROUND", nil, -8)
		tile.ground:SetAllPoints()
		tile.ground:SetColorTexture(0.1, 0.1, 0.1, 0.9)
		tile.health = CreateFrame("StatusBar", nil, tile)
		tile.health:SetPoint("TOPLEFT", 1, -1)
		tile.health:SetPoint("BOTTOMRIGHT", -1, 5)
		tile.health:SetMinMaxValues(0, 1)
		tile.health:SetValue(HEALTH[i])
		tile.power = CreateFrame("StatusBar", nil, tile)
		tile.power:SetPoint("TOPLEFT", tile.health, "BOTTOMLEFT", 0, -1)
		tile.power:SetPoint("BOTTOMRIGHT", -1, 1)
		tile.power:SetStatusBarTexture(GAME_FILL)
		tile.power:SetStatusBarColor(0, 0.45, 1)
		tile.power:SetMinMaxValues(0, 1)
		tile.power:SetValue(0.4 + i * 0.05)
		tile.edge = ns.MakeStyleEdges(tile)
		tile.name = tile.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tile.name:SetPoint("TOPLEFT", 4, -3)
		tile.mark = tile:CreateTexture(nil, "OVERLAY")
		tile.mark:SetAllPoints()
		tile.mark:SetColorTexture(1, 0.82, 0, 0.12)
		tile.id, tile.i = id, i
		tile:SetScript("OnClick", function() if onPick then onPick(id) end end)
		tiles[#tiles + 1] = tile
	end
	for i = 1, 5 do Tile("PARTY", i, 14, -24 - (i - 1) * 37, 96, 34) end
	for i = 1, 10 do Tile("RAID", i, 150 + ((i - 1) % 5) * 64, -24 - math.floor((i - 1) / 5) * 54, 62, 52) end
	function holder:Refresh(editing)
		ns.StyleScene(self, 0.55, 0.85)
		for _, tile in ipairs(tiles) do
			local view, class = View(tile.id), CLASSES[tile.i]
			tile.mark:SetShown(editing == tile.id)
			if not ns.SetBarTexture(tile.health, view.ufTexture) then
				tile.health:SetStatusBarTexture(GAME_FILL)
				tile.health:GetStatusBarTexture():SetDesaturated(false)
			end
			-- (The game's raid frames: health in class colors.)
			local r, g, b = ClassColor(class)
			if view.ufHealthColor == "custom" then r, g, b = view.ufHealthR, view.ufHealthG, view.ufHealthB end
			tile.health:SetStatusBarColor(r, g, b)
			local kind, size, er, eg, eb = ns.StyleBorder(view, "ufBorder")
			tile.edge:SetShown(kind == "line" or kind == "game")
			if kind == "line" then
				ns.DressStyleEdges(tile.edge, size, er, eg, eb, 1, false)
			elseif kind == "game" then
				ns.DressStyleEdges(tile.edge, 1, 0.3, 0.3, 0.3, 1, false)
			end
			tile.ground:SetAlpha(0.9 * (tonumber(view.ufGround) or 1))
			-- (The name.)
			local object = _G.GameFontHighlightSmall
			tile.name:SetFontObject(object)
			local file, height, flags = object:GetFont()
			local font, outline = view.ufFont, tonumber(view.ufOutline) or 0
			if ROMAN then
				for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do
					if info[1] == font and info[3] then file = info[3] end
				end
			end
			if outline >= 0 and ns.OutlinedFlags then flags = ns.OutlinedFlags(flags, outline) end
			if file and height then tile.name:SetFont(file, height * (tonumber(view.ufNameSize) or 1), flags or "") end
			tile.name:SetText(L[NAMES[tile.i]])
			if view.ufNameColor == "class" then
				tile.name:SetTextColor(ClassColor(class))
			else
				tile.name:SetTextColor(1, 1, 1)
			end
		end
	end
	return holder
end

-- The page itself.
local PRESET_KEYS = { "rfTexture", "rfBorder", "rfBorderSize", "rfBorderR", "rfBorderG", "rfBorderB", "rfBack",
	"rfGround", "rfHealthColor", "rfNameColor", "rfFont", "rfOutline", "rfNameSize" }
local TAB_NAMES = {}
for _, group in ipairs(GROUPS) do TAB_NAMES[group[1]] = group[2] end

function ns.CreateRaidStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Raid frames"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the raid frames look, the party's when the game draws them raid-style, and the arena's. The " ..
		"Default tab's settings are each group's until its own tab has Use default settings unticked. Which " ..
		"parts show: the Standard Frames page's party and raid rows."])

	local editing
	local function UsesDefault(db) return editing and not db["rfOwn_" .. editing] end
	local fields = {}
	local function Field(key)
		local field = fields[key]
		if not field then
			field = {
				get = function()
					local db = ns.GetDB()
					if not db then return nil end
					local own = editing and db["rfOwn_" .. editing]
					local part = key:match("^rfBorder(%u%l*)$")
					if own and part and part ~= "" then return db["rfBorder_" .. editing .. part] end
					return db[own and key .. "_" .. editing or key]
				end,
				set = function(value)
					local db = ns.GetDB()
					local part = key:match("^rfBorder(%u%l*)$")
					if editing and part and part ~= "" then
						db["rfBorder_" .. editing .. part] = value
					else
						db[editing and key .. "_" .. editing or key] = value
					end
				end,
			}
			fields[key] = field
		end
		return field
	end

	local preview
	local tabs, ownCheck, partyNote = {}, nil, nil
	local function Changed()
		ns.RefreshRaidStyle()
		if preview then preview:Refresh(editing) end
	end

	local switch = kit.PageSwitch(content, "rfStyle", L["Enable page"],
		L["On: the raid frames look as this page says. Off: the game's own (the preview shows that too). Each " ..
		"setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "rfStyle", Field)
	local function Editable(db) return rows.On(db) and not UsesDefault(db) end

	local function Pick(id)
		editing = id
		kit.Refresh()
		Changed()
	end

	stack:Add(ns.StyleSceneButton(content, kit.Tooltip, kit.AddControl), "label")
	preview = ns.MakeRaidStylePreview(content, 480, Pick)
	stack:Add(preview, "label")
	kit.AddControl(preview)
	local refreshPreview = preview.Refresh
	preview.Refresh = function(self) refreshPreview(self, editing) end

	rows.Presets({
		{ L["Like the game's"], L["The game's raid frames, as it draws them (the defaults)."], {} },
		{ L["Flat"], L["Flat bars with a thin black edge, class-colored names, Arial Narrow."],
			{ rfTexture = "flat", rfBorder = "thin", rfNameColor = "class", rfFont = "arial", rfOutline = 1 } },
		{ L["Minimal"], L["Borderless flat bars on a faint ground, small names."],
			{ rfTexture = "flat", rfBorder = "none", rfGround = 0.4, rfNameSize = 0.9, rfOutline = 1 } },
		{ L["Cinematic"], L["Soft bars with a fine edge, names outlined."],
			{ rfTexture = "soft", rfBorder = "thin", rfOutline = 1 } },
	}, PRESET_KEYS, 480)

	-- The tabs: Default, then each group; on a group's, Use default settings.
	local tabsRow = CreateFrame("Frame", nil, content)
	tabsRow:SetSize(480, 22)
	stack:Add(tabsRow, "label")
	local function TabsLook()
		local db = ns.GetDB()
		for _, tab in ipairs(tabs) do
			if tab.id == editing then tab:LockHighlight() else tab:UnlockHighlight() end
			local own = tab.id and db and db["rfOwn_" .. tab.id]
			tab:SetText((tab.id and L[TAB_NAMES[tab.id]] or L["Default"]) .. (own and " |cffffd100*|r" or ""))
		end
		ownCheck:SetShown(editing ~= nil)
		partyNote:SetShown(editing == "PARTY" and not (ns.RaidStyleParty and ns.RaidStyleParty()))
	end
	local list = { false }
	for _, group in ipairs(GROUPS) do list[#list + 1] = group[1] end
	for i, id in ipairs(list) do
		local tab = ns.PanelButton(tabsRow)
		tab.id = id or nil
		tab:SetText(id and L[TAB_NAMES[id]] or L["Default"])
		tab:SetSize(math.max(64, tab:GetFontString():GetStringWidth() + 20), 22)
		if i == 1 then tab:SetPoint("LEFT", tabsRow, "LEFT", 0, 0) else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 4, 0) end
		kit.Tooltip(tab, id and L["This group's settings: Default's until you untick Use default settings."]
			or L["The settings every group has while its tab uses the default settings."])
		tab:SetScript("OnClick", function() Pick(tab.id) end)
		tabs[i] = tab
	end
	-- (Every setting the page has, Default's and each group's, for its Reset.)
	for key in pairs(KEYS) do kit.RecordKey(content, key) end
	for _, group in ipairs(GROUPS) do
		kit.RecordKey(content, "rfOwn_" .. group[1])
		for key in pairs(KEYS) do kit.RecordKey(content, key .. "_" .. group[1]) end
		for _, part in ipairs({ "Size", "R", "G", "B" }) do kit.RecordKey(content, "rfBorder_" .. group[1] .. part) end
	end
	ownCheck = kit.Check(content, false, L["Use default settings"],
		L["Ticked: this group looks as the Default tab says. Unticked: as the settings below say (they start " ..
		"as Default's, and are kept while it's ticked)."], function(value)
			local db = ns.GetDB()
			if not value and not db["rfStarted_" .. editing] then
				for key in pairs(KEYS) do db[key .. "_" .. editing] = db[key] end
				for _, part in ipairs({ "Size", "R", "G", "B" }) do
					db["rfBorder_" .. editing .. part] = db["rfBorder" .. part]
				end
				db["rfStarted_" .. editing] = true
			end
			db["rfOwn_" .. editing] = not value
			Changed()
			kit.Refresh()
		end)
	ownCheck.Refresh = function(self)
		local db = ns.GetDB()
		self:SetChecked(editing and db and not db["rfOwn_" .. editing] or false)
		TabsLook()
	end
	ownCheck.pageSwitch = false
	stack:Add(ownCheck, "check")
	kit.GreyUnless(ownCheck, rows.On)
	kit.AddControl(ownCheck)
	-- (Party, while the game draws it as its own frames: the Unit frames page's.)
	partyNote = kit.Label(content, "GameFontHighlightSmall", L["Your party uses its own frames, not raid-style " ..
		"ones: they follow the Unit frames page's Party tab."])
	partyNote:SetPoint("LEFT", ownCheck.Text or ownCheck.text or ownCheck, "RIGHT", 16, 0)
	partyNote:SetWidth(300)
	partyNote:SetJustifyH("LEFT")
	partyNote:SetTextColor(1, 0.82, 0)

	stack:Header(content, L["Bars"])
	rows.Texture(L["Texture:"], "rfTexture", L["The health bar's fill. Below the game's own few: any other " ..
		"addon shares (through LibSharedMedia)."], Editable, { 0.25, 0.75, 0.3 })
	rows.Border(L["Border:"], "rfBorder", { game = true }, L["Round each frame: the game's, or a border of ours " ..
		"(Custom: its thickness and color under it)."], Editable)
	local grounds = rows.Boxes()
	grounds:Box(L["Background"], Field("rfGround"), 0, 100, 5, "%d", 100, L["How solid the game's dark " ..
		"background behind each frame is."], Editable, "%")
	grounds:Box(L["Behind the bar"], Field("rfBack"), 0, 100, 5, "%d", 100, L["How dark it is behind the " ..
		"health bar, with a border of ours."], function(db) return Editable(db) and rows.Get("rfBorder") ~= "game" end,
		"%")

	stack:Header(content, L["Colors"])
	local last = rows.Choices(L["Health:"], "rfHealthColor", {
		{ "game", L["The game's"], L["As the game's options say (class colors, or green)."] },
		{ "class", L["Class or reaction"] },
		{ "custom", L["Custom"], L["A color of your own (the swatch)."] },
	}, Editable)
	rows.Swatch(last, "rfHealthColor", { "rfHealthR", "rfHealthG", "rfHealthB" }, L["The health bar's color, for Custom."],
		Editable)
	rows.Choices(L["Name:"], "rfNameColor", {
		{ "game", L["The game's"] },
		{ "class", L["Class or reaction"] },
		{ "white", L["White"] },
	}, Editable)

	stack:Header(content, L["Name"])
	rows.Font("rfFont", L["The name's font. Russian, Korean or Chinese names keep the game's, so their " ..
		"letters show."], Editable)
	rows.Outline("rfOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"] }, nil, Editable)
	rows.Slider("rfNameSize", L["Size"], 50, 150, 5, "%d%%", 100, L["The name's size, next to the game's."], Editable)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Raid Style", L["Raid frames"])
end
