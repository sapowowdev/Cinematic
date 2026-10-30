-- Personal mana: a mana bar of ours under the personal resource display's
-- power bar, for when mana isn't the power it shows (Elemental and
-- Enhancement Shaman, Shadow Priest, Balance Druid, druids in forms). The
-- game has a bar for it (AlternatePowerBar) but keeps it hidden.
-- Off to start with: the UI Manager's Personal Resources page turns it on
-- (prdMana, PersonalResources.lua), and can keep it to a few seconds after
-- you use mana (prdManaRecent); the Style hub's Personal Resource Display page
-- dresses it with the other two (PersonalStyle.lua).
-- It's a child of the display, so it moves with Edit Mode and comes and goes
-- with it. Its fade is the Standard Frames row Personal mana bar (prdmana,
-- its stand-in CinematicPersonalMana: Frames.lua), which calls
-- ns.FadePersonalMana each tick.
-- Retail only (Forever's display is your own nameplate). Mana can be secret
-- in fights: the bar takes it as it is, and its words are made by the game's
-- own functions, which take secrets.

local _, ns = ...

local display = _G.PersonalResourceDisplayFrame
if not (ns.isRetail and display) then return end
ns.PERSONAL_MANA = true -- (the mana rows on Personal Resources and its Style page: shown)

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local GAME_FILL = "Interface\\TargetingFrame\\UI-StatusBar" -- (when the game's mana bar has none to copy)
local MANA_BLUE = { 0, 0.55, 1 } -- (the game's mana color, where it has one: GameFill)
local GAP = 2 -- under the bar above it, in pixels

local bar -- made once the display has a power bar to go under
local shown = false -- whether it's in use: on, and mana isn't your power

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- Whether mana has a bar of its own now: ticked, and mana not the power the
-- display shows while you have some. (Secret: as it was.)
local function Wanted()
	if not (ns.db and ns.db.prdMana) then return false end
	local powerType = UnitPowerType("player")
	local maxMana = UnitPowerMax("player", MANA)
	if not (Readable(powerType) and Readable(maxMana)) then return shown end
	return powerType ~= MANA and maxMana > 0
end

-- The game's own look for mana, as its unit frames draw it: its mana atlas
-- (already blue: true) where it has one, else a plain fill (its hidden mana
-- bar's, white until the game colors it, which it never does while hidden)
-- and the game's mana color for it.
-- (An atlas that exists on this client.)
local function HasAtlas(name)
	return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo
		and C_Texture.GetAtlasInfo(name) ~= nil or false
end

-- Mana's atlas in the power bar's own art: its atlas with the power's name
-- (its last word: ...-Bar-Maelstrom) swapped for Mana, then the player
-- frame's mana bar.
local function ManaAtlas()
	local power = display.PowerBar
	local fill = power and power.GetStatusBarTexture and power:GetStatusBarTexture()
	local atlas = fill and fill.GetAtlas and fill:GetAtlas()
	if Readable(atlas) and type(atlas) == "string" and atlas ~= "" then
		local swapped = atlas:gsub("[^%-]+$", "Mana")
		if HasAtlas(swapped) then return swapped end
	end
	for _, name in ipairs({ "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Mana",
		"UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana" }) do
		if HasAtlas(name) then return name end
	end
end

local function GameFill()
	local manaAtlas = ManaAtlas()
	if manaAtlas then return manaAtlas, true end
	local getColor = _G.GetPowerBarColor
	local info = getColor and getColor("MANA") or _G.PowerBarColor and _G.PowerBarColor.MANA
	if type(info) == "table" and type(info.atlas) == "string" and info.atlas ~= "" then
		return info.atlas, true
	end
	if type(info) == "table" and info.r then
		MANA_BLUE[1], MANA_BLUE[2], MANA_BLUE[3] = info.r, info.g, info.b
	end
	local game = display.AlternatePowerBar
	local fill = game and game.GetStatusBarTexture and game:GetStatusBarTexture()
	local file = fill and fill:GetTexture()
	if Readable(file) and file ~= "" then return file, false end
	return GAME_FILL, false
end

-- Its words, as the power bar's: a percent left, the amount right or in the
-- middle, each shown while the power bar's is (the game's Status Text).
local WORDS = { LeftText = "percent", RightText = "amount", TextString = "amount" }

local function MakeWords()
	bar.words = {}
	local power = display.PowerBar
	for field in pairs(WORDS) do
		local theirs = power and power[field]
		if type(theirs) == "table" and theirs.GetFont then
			local words = bar:CreateFontString(nil, "OVERLAY")
			local object = theirs:GetFontObject()
			if object then
				words:SetFontObject(object)
			else
				local file, size, flags = theirs:GetFont()
				if file then words:SetFont(file, size, flags) else words:SetFontObject("TextStatusBarText") end
			end
			local ok, point, _, relPoint, x, y = pcall(theirs.GetPoint, theirs, 1)
			if ok and Readable(point) then
				words:SetPoint(point, bar, relPoint, x, y)
			else
				words:SetPoint(field == "LeftText" and "LEFT" or field == "RightText" and "RIGHT" or "CENTER", bar,
					field == "LeftText" and "LEFT" or field == "RightText" and "RIGHT" or "CENTER",
					field == "LeftText" and 2 or field == "RightText" and -2 or 0, 0)
			end
			words.theirs = theirs
			bar.words[field] = words
		end
	end
end

local function UpdateValue()
	if not (bar and shown) then return end
	local mana, maxMana = UnitPower("player", MANA), UnitPowerMax("player", MANA)
	bar:SetMinMaxValues(0, maxMana)
	bar:SetValue(mana)
	for field, words in pairs(bar.words) do
		local theirs = words.theirs
		local on = ns.Flag(theirs:IsShown())
		if on then
			local ok, text = pcall(function()
				if WORDS[field] == "percent" then
					local percentOf, curves = _G.UnitPowerPercent, _G.CurveConstants
					local percent = percentOf and curves and curves.ScaleTo100
						and percentOf("player", MANA, false, curves.ScaleTo100)
					if type(percent) ~= "number" and Readable(mana) and Readable(maxMana) and maxMana > 0 then
						percent = mana / maxMana * 100
					end
					return type(percent) == "number" and ("%d%%"):format(percent) or nil
				end
				local abbreviate = _G.AbbreviateNumbers
				return abbreviate and abbreviate(mana) or tostring(mana)
			end)
			on = ok and type(text) == "string" -- (type: a secret string can't be compared)
			if on then words:SetText(text) end
		end
		words:SetShown(on)
	end
end

-- Where it goes: under the power bar, or under your class resource while
-- that's up (a druid's combo points in Cat Form), as wide as the power bar.
local function Place()
	local power = display.PowerBar
	local pieces = display.ClassFrameContainer
	local above = power
	if pieces and ns.Flag(pieces:IsShown()) then
		local ok, bottom, powerBottom = pcall(function() return pieces:GetBottom(), power:GetBottom() end)
		if ok and Readable(bottom) and Readable(powerBottom) and bottom < powerBottom then above = pieces end
	end
	-- (Spaced for a border of ours: PersonalStyle.lua.)
	local gap = ns.PersonalBarGap and ns.PersonalBarGap() or GAP
	bar:ClearAllPoints()
	if above == power then
		bar:SetPoint("TOPLEFT", power, "BOTTOMLEFT", 0, -gap)
		bar:SetPoint("TOPRIGHT", power, "BOTTOMRIGHT", 0, -gap)
	else
		bar:SetPoint("TOP", above, "BOTTOM", 0, -gap)
		local ok, width = pcall(power.GetWidth, power)
		bar:SetWidth(ok and Readable(width) and width > 0 and width or 200)
	end
end

-- The game's cast bar, where Edit Mode put it just under the display: our
-- bar grows the display down into it, so while ours is in use it's moved down
-- to leave CAST_GAP. Put back while it's not, and for Edit Mode (which saves
-- where it is). A cast bar placed elsewhere, or on the player frame: left.
local CAST_GAP = 6 -- between our bar and the cast bar, in pixels
local castMoved -- { own = its points, ours = the points we gave it }, while moved

local function CastPoints(cast)
	local points = {}
	for i = 1, cast:GetNumPoints() do points[i] = { cast:GetPoint(i) } end
	return points
end

local function SamePoints(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		for j = 1, 5 do if a[i][j] ~= b[i][j] then return false end end
	end
	return true
end

local function SetCastPoints(cast, points)
	cast:ClearAllPoints()
	for _, p in ipairs(points) do cast:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
end

local function PlaceCastBar()
	local cast = _G.PlayerCastingBarFrame
	if not (cast and cast.GetNumPoints) then return end
	if castMoved then
		-- (Moved since by the game: its own spot is the new one.)
		local ok, now = pcall(CastPoints, cast)
		if ok and SamePoints(now, castMoved.ours) then SetCastPoints(cast, castMoved.own) end
		castMoved = nil
	end
	local editing = _G.EditModeManagerFrame and _G.EditModeManagerFrame.IsEditModeActive
		and _G.EditModeManagerFrame:IsEditModeActive()
	if not (shown and bar) or editing or cast.attachedToPlayerFrame then return end
	local ok, own, shift = pcall(function()
		local bs, cs = bar:GetEffectiveScale(), cast:GetEffectiveScale()
		local barTop, barBottom, castTop = bar:GetTop(), bar:GetBottom(), cast:GetTop()
		local barLeft, barRight = bar:GetLeft(), bar:GetRight()
		local castLeft, castRight = cast:GetLeft(), cast:GetRight()
		if not (barTop and castTop and barLeft and castLeft) then return end
		-- (Under our bar's top, side by side with it, and closer than the gap,
		-- under any border line of ours.)
		local reach
		if ns.PersonalBarGap then reach = select(2, ns.PersonalBarGap()) end
		local want = (barBottom - CAST_GAP - (reach or 0)) * bs
		if castTop * cs > barTop * bs or castTop * cs <= want then return end
		if castRight * cs < barLeft * bs or castLeft * cs > barRight * bs then return end
		return CastPoints(cast), (castTop * cs - want) / cs
	end)
	if not (ok and own and shift) then return end
	local ours = {}
	for i, p in ipairs(own) do ours[i] = { p[1], p[2], p[3], p[4], p[5] - shift } end
	SetCastPoints(cast, ours)
	castMoved = { own = own, ours = CastPoints(cast) }
end

local EventRegistry = _G.EventRegistry
if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("EditMode.Enter", PlaceCastBar, "CinematicPersonalMana")
	EventRegistry:RegisterCallback("EditMode.Exit", function() C_Timer.After(0, PlaceCastBar) end,
		"CinematicPersonalManaExit")
end

local function Make()
	local power = display.PowerBar
	if bar or not (power and power.GetHeight) then return bar end
	bar = CreateFrame("StatusBar", "CinematicPersonalManaBar", display)
	bar:SetFrameLevel(power:GetFrameLevel())
	local ok, height = pcall(power.GetHeight, power)
	bar:SetHeight(ns.PersonalOwnHeight and ns.PersonalOwnHeight(power) or ok and Readable(height) and height or 8)
	local fill = GameFill()
	bar:SetStatusBarTexture(fill)
	bar:Hide()
	MakeWords()
	-- (Your class resource coming and going: under it or not.)
	local pieces = display.ClassFrameContainer
	if pieces and pieces.HookScript then
		pieces:HookScript("OnShow", function() if shown then Place() C_Timer.After(0, PlaceCastBar) end end)
		pieces:HookScript("OnHide", function() if shown then Place() C_Timer.After(0, PlaceCastBar) end end)
	end
	return bar
end

-- Its color, after the Style page has dressed it: Custom's, else mana's
-- blue over a plain fill (ours or the game's), or none over the game's mana
-- atlas (already blue).
function ns.ColorPersonalMana(look)
	if not bar then return end
	local fill = bar:GetStatusBarTexture()
	local ours = ns.StyleTexturePath(look and look.prdTexture) ~= nil
	local _, gameColored = GameFill()
	if look and look.prdManaColor == "custom" then
		if fill and not ours and gameColored then fill:SetDesaturated(true) end
		bar:SetStatusBarColor(look.prdManaR or 0, look.prdManaG or 0, look.prdManaB or 0)
	elseif ours or not gameColored then
		bar:SetStatusBarColor(MANA_BLUE[1], MANA_BLUE[2], MANA_BLUE[3])
	else
		if fill then fill:SetDesaturated(false) end
		bar:SetStatusBarColor(1, 1, 1)
	end
end

-- Its alpha: while either row is faded (Frames.lua's fade, each tick) it
-- takes its own row's; with both up it follows the display's. Times recent:
-- how far it's faded in after you used mana (prdManaRecent; 1 while that's off).
local held = false
local rowHealth, rowLevel = 1, 1 -- (the rows' alphas, as last given)
local recent = 1
local function Paint()
	if not bar then return end
	local level = rowLevel * recent
	if level < 1 or rowHealth < 1 then
		if not held then bar:SetIgnoreParentAlpha(true) end
		held = true
		bar:SetAlpha(level)
	elseif held then
		held = false
		bar:SetIgnoreParentAlpha(false)
		bar:SetAlpha(1)
	end
end

function ns.FadePersonalMana(health, level)
	rowHealth, rowLevel = health, level
	Paint()
end

-- Only for a while after you use mana (prdManaRecent: seconds; 0: always).
-- Used: your mana went down, or (mana secret, in fights) a cast that costs mana.
local RECENT_FADE = 0.3 -- seconds to fade in or out
local lastUsed = -math.huge
local lastMana -- (readable: the last seen, to tell a drop)

local function RecentNow()
	local seconds = ns.db and tonumber(ns.db.prdManaRecent) or 0
	return seconds <= 0 or GetTime() - lastUsed < seconds
end

-- (Runs while it's in use and fading, or kept to a while: off otherwise.)
local recentDriver = CreateFrame("Frame")
recentDriver:Hide()
recentDriver:SetScript("OnUpdate", function(self, elapsed)
	local target = RecentNow() and 1 or 0
	if recent ~= target then
		local step = elapsed / RECENT_FADE
		recent = target > recent and math.min(target, recent + step) or math.max(target, recent - step)
		Paint()
	elseif not shown or (ns.db and tonumber(ns.db.prdManaRecent) or 0) <= 0 then
		self:Hide()
	end
end)

local function Used()
	lastUsed = GetTime()
	if shown then recentDriver:Show() end
end

-- Shown or not (the Style page's settings changing, your spec or form
-- changing). dressing: the Style page's own call, which dresses it next;
-- else a bar just made is dressed here.
local function Update(dressing)
	local want = Wanted()
	local made = bar
	if want and not Make() then want = false end
	local was = shown
	shown = want
	if not bar then return end
	if want then
		-- (Coming up: faded in only if you've used mana lately.)
		if not was then recent = RecentNow() and 1 or 0 end
		recentDriver:Show()
		Paint()
		Place()
		if not made and not dressing and ns.RefreshPersonalStyle then ns.RefreshPersonalStyle() end
	end
	bar:SetShown(want)
	UpdateValue()
	C_Timer.After(0, PlaceCastBar) -- (once our bar's spot has settled)
end
ns.UpdatePersonalMana = Update

-- In use: shown under the display (Personal Resources: low mana and "until
-- full" are this row's then, not the power bar's).
function ns.PersonalManaShown()
	return shown
end

-- The bar itself, for the Style page to dress (nil until made).
function ns.PersonalManaBar()
	return bar
end

-- For /cine debug plates.
function ns.DescribePersonalMana()
	if not bar then
		return ("mana bar: not made (ticked %s, style page %s)"):format(tostring(ns.db.prdMana),
			tostring(ns.StyleOn("prdStyle")))
	end
	local powerType, maxMana = UnitPowerType("player"), UnitPowerMax("player", MANA)
	local words = {}
	for field, each in pairs(bar.words) do
		words[#words + 1] = field .. (ns.Flag(each:IsShown()) and " shown" or " hidden")
	end
	local okAlpha, alpha = pcall(bar.GetAlpha, bar)
	local gameFill, atlas = GameFill()
	local r, g, b = bar:GetStatusBarColor()
	-- (And the power bar's own fill, to match.)
	local powerFill = display.PowerBar and display.PowerBar:GetStatusBarTexture()
	local okArt, powerAtlas, powerFile = pcall(function() return powerFill:GetAtlas(), powerFill:GetTexture() end)
	local function Shown(value) return okArt and Readable(value) and tostring(value) or "?" end
	return ("mana bar: %s, fill %s (%s), color %.2f %.2f %.2f, power bar's fill %s / %s, alpha %s%s, "
		.. "power type %s, max mana %s, words: %s, cast bar %s, recent %.2f (%s s, used %s s ago)"):format(
		shown and "in use" or "not in use", tostring(gameFill), atlas and "atlas" or "tinted", r or 0, g or 0, b or 0,
		Shown(powerAtlas), Shown(powerFile),
		okAlpha and Readable(alpha) and ("%.2f"):format(alpha) or "secret",
		held and " (ours)" or "", Readable(powerType) and tostring(powerType) or "secret",
		Readable(maxMana) and tostring(maxMana) or "secret", #words > 0 and table.concat(words, ", ") or "none",
		castMoved and ("moved down %.1f"):format(castMoved.own[1][5] - castMoved.ours[1][5]) or "not moved",
		recent, tostring(ns.db.prdManaRecent), lastUsed > -math.huge and ("%.1f"):format(GetTime() - lastUsed) or "never")
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
watcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
watcher:RegisterUnitEvent("UNIT_MAXPOWER", "player")
watcher:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
-- (A cast that costs mana, for when mana itself is secret.)
local function CostsMana(spellID)
	local getCost = C_Spell and C_Spell.GetSpellPowerCost
	local ok, costs = pcall(getCost, spellID)
	if not (getCost and ok and type(costs) == "table") then return false end
	for _, info in ipairs(costs) do
		if Readable(info.type) and info.type == MANA and (not Readable(info.cost) or info.cost > 0) then
			return true
		end
	end
	return false
end
watcher:SetScript("OnEvent", function(_, event, _, arg2, arg3)
	if event == "UNIT_POWER_FREQUENT" then
		-- (A secret token can't be compared: maybe mana.)
		if not Readable(arg2) or arg2 == "MANA" then
			local mana = UnitPower("player", MANA)
			if Readable(mana) then
				if lastMana and mana < lastMana then Used() end
				lastMana = mana
			else
				lastMana = nil
			end
			UpdateValue()
		end
		return
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if lastMana == nil and CostsMana(arg3) then Used() end
		return
	end
	Update()
end)
