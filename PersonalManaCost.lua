-- Mana cost: while you cast a spell that costs mana, the mana it will take
-- shows as a pale stretch at the end of your mana, from the fill's right
-- edge leftwards: what's left after the cast is the fill to its left.
-- On your mana under your character (the personal resource display's power
-- bar while mana is your power, else our own mana bar under it while that's
-- in use: PersonalMana.lua), and on your player frame's (its mana bar, else
-- the game's mana bar under it). Each off to start with: the UI Manager's
-- Personal Resources page turns them on (manaCostDisplay, manaCostPortrait).
-- The game's own cost on the player frame (retail's) is faded while ours
-- is on there.
-- Mana and its max can be secret in fights: the stretch is a status bar of
-- its own, drawn reversed from the fill's right edge and given them as they
-- are, clipped to the bar (a cost over what you have runs out at its left).

local _, ns = ...

local DEFAULTS = ns.DEFAULTS
DEFAULTS.manaCostDisplay = false    -- a cast's mana cost on your mana under your character
DEFAULTS.manaCostPortrait = false   -- ...and on your player frame's

local display = _G.PersonalResourceDisplayFrame
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local SHADE = { 1, 1, 1, 0.5 } -- the stretch: white over the fill, half seen
local KEYS = { display = "manaCostDisplay", portrait = "manaCostPortrait" }

local overlays = setmetatable({}, { __mode = "k" }) -- bar -> its overlay
local gameCost = setmetatable({}, { __mode = "k" }) -- the game's own cost pieces -> true, while faded for ours
local casting -- the cast going on, while it costs mana (its guid, or true)
local cost -- ...its mana cost

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- The bars your mana is on now, by where: display (under your character)
-- and portrait (your player frame). Either can be nil. (Power type
-- secret: maybe mana.)
local function ManaBars()
	local powerType = UnitPowerType("player")
	local isMana = not Readable(powerType) or powerType == MANA
	local under
	if display then
		if ns.PersonalManaShown and ns.PersonalManaShown() then
			under = ns.PersonalManaBar()
		elseif isMana then
			under = display.PowerBar
		end
	end
	local portrait
	local frame = _G.PlayerFrame
	if frame then
		if isMana then
			portrait = frame.manabar or frame.ManaBar or _G.PlayerFrameManaBar
		else
			local alternate = _G.AlternatePowerBar or _G.PlayerFrameAlternateManaBar
			if alternate and ns.Flag(alternate:IsShown()) then portrait = alternate end
		end
	end
	return { display = under, portrait = portrait }
end
ns.PlayerManaBars = ManaBars

-- A spell's mana cost (nil: none, or it can't be read). The game's list
-- has an entry per power it costs; some only with an aura you have.
local function ManaCost(spellID)
	local getCost = C_Spell and C_Spell.GetSpellPowerCost or _G.GetSpellPowerCost
	if not (getCost and spellID) then return end
	local ok, found = pcall(function()
		for _, each in ipairs(getCost(spellID) or {}) do
			local aura = each.requiredAuraID
			if each.type == MANA and (not aura or aura == 0 or each.hasRequiredAura) then
				return each.cost
			end
		end
	end)
	if ok and found ~= nil and (not Readable(found) or found > 0) then return found end
end

local function Overlay(bar)
	local overlay = overlays[bar]
	if overlay then return overlay end
	-- (A clipping frame the bar's size, and in it the stretch: as wide as the
	-- bar, its right edge on the fill's.)
	overlay = CreateFrame("Frame", nil, bar)
	overlay:SetAllPoints()
	overlay:SetClipsChildren(true)
	overlay:SetFrameLevel(bar:GetFrameLevel() + 1)
	local stretch = CreateFrame("StatusBar", nil, overlay)
	stretch:SetReverseFill(true)
	stretch:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	stretch:SetStatusBarColor(SHADE[1], SHADE[2], SHADE[3], SHADE[4])
	overlay.stretch = stretch
	overlay:Hide()
	overlays[bar] = overlay
	return overlay
end

-- The game's own cost on a bar (retail's player frame): its pieces.
local function GameCost(bar)
	local frame = _G.PlayerFrame
	local pieces = {}
	for _, piece in ipairs({ bar.ManaCostPredictionBar or false,
		frame and bar == (frame.manabar or frame.ManaBar) and frame.myManaCostPredictionBar or false }) do
		if type(piece) == "table" and piece.SetAlpha then pieces[#pieces + 1] = piece end
	end
	return pieces
end

-- The stretch on one bar, for the cast going on (false: it can't be).
local function Draw(bar)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not fill then return false end
	local overlay = Overlay(bar)
	local stretch = overlay.stretch
	local ok = pcall(function()
		stretch:SetWidth(bar:GetWidth())
		stretch:ClearAllPoints()
		stretch:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
		stretch:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
		stretch:SetMinMaxValues(0, UnitPowerMax("player", MANA))
		stretch:SetValue(cost)
	end)
	overlay:SetShown(ok)
	return ok
end

-- Drawn again: the cast starting or ending, your mana or its bars changing,
-- the page's settings.
local function Update()
	local db = ns.GetDB()
	local bars = ManaBars()
	local drawn, mute = {}, {}
	for where, key in pairs(KEYS) do
		local bar = bars[where]
		if bar and db and db[key] then
			if casting and Draw(bar) then drawn[bar] = true end
			for _, piece in ipairs(GameCost(bar)) do mute[piece] = true end
		end
	end
	for bar, overlay in pairs(overlays) do
		if not drawn[bar] then overlay:Hide() end
	end
	-- (The game's own faded where ours is on, back elsewhere.)
	for piece in pairs(mute) do
		gameCost[piece] = true
		piece:SetAlpha(0)
	end
	for piece in pairs(gameCost) do
		if not mute[piece] then
			gameCost[piece] = nil
			piece:SetAlpha(1)
		end
	end
	-- (And the mana after the cast, by the same cast: PersonalManaText.lua.)
	if ns.UpdateManaAfter then ns.UpdateManaAfter(casting and cost or nil, bars) end
end
ns.UpdateManaCost = Update

local function Start(castGUID, spellID)
	cost = ManaCost(spellID)
	casting = type(cost) == "number" and (castGUID or true) or nil
	if not casting then cost = nil end
	Update()
end

-- (Only for the cast that's on: some spells go off on their own mid-cast.
-- A cast whose guid can't be read: taken as it.)
local function Stop(castGUID)
	if not casting then return end
	if Readable(castGUID) and Readable(casting) and castGUID ~= casting then return end
	casting, cost = nil, nil
	Update()
end

-- For /cine debug plates: which bar each is on.
function ns.DescribeManaBar(bar)
	if bar == nil then return "none" end
	if display and bar == display.PowerBar then return "the power bar" end
	if ns.PersonalManaBar and bar == ns.PersonalManaBar() then return "our mana bar" end
	local ok, name = pcall(bar.GetName, bar)
	return ok and Readable(name) and name or "the player frame's"
end

function ns.DescribeManaCost()
	local db = ns.GetDB() or {}
	local bars = ManaBars()
	return ("mana cost: resource bar %s (%s), player frame %s (%s), casting %s, cost %s"):format(
		db.manaCostDisplay and "on" or "off", ns.DescribeManaBar(bars.display),
		db.manaCostPortrait and "on" or "off", ns.DescribeManaBar(bars.portrait),
		casting and "a spell" or "nothing", Readable(cost) and tostring(cost) or cost and "secret" or "none")
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
watcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
watcher:RegisterUnitEvent("UNIT_MAXPOWER", "player")
watcher:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
watcher:SetScript("OnEvent", function(_, event, _, arg2, spellID)
	if event == "UNIT_SPELLCAST_START" then
		Start(arg2, spellID)
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		-- (A second cast failing, queued while one is on: that one goes on.)
		-- (Parentheses: Classic Era returns nothing at all when not casting.)
		if type((UnitCastingInfo("player"))) == "nil" then Stop(arg2) end
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		Stop(arg2)
	elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_DISPLAYPOWER" then
		-- (A frame on: our mana bar comes or goes on these too, PersonalMana.lua.)
		C_Timer.After(0, Update)
	elseif casting then
		-- (Your mana changing: drawn again. arg2: the power's token; a secret
		-- one maybe mana.)
		if event ~= "UNIT_POWER_FREQUENT" or not Readable(arg2) or arg2 == "MANA" then Update() end
	end
end)
