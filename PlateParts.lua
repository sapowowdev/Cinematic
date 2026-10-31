-- Cinematic: the Nameplates page's Plate parts grid. In CineMode each part of
-- the game's nameplates (health bar, name, cast bar, auras...) shows as its
-- row says, fading like the plates themselves. Outside CineMode, or with the
-- page's master switch off, the parts are left to the game.
local ADDON_NAME, ns = ...

-- Each part's frame on a plate's unit frame: the first of these it has, or
-- (all) every one of them, for parts drawn by several textures. The
-- containers (health and cast bars with their borders) go first. WoW
-- Forever's level is the PlayerLevelDiffFrame box (its LevelFrame stays hidden);
-- Classic Era has both too but shows LevelFrame, so each is faded.
-- A dotted field is one on a frame on the unit frame.
local PART_FRAMES = {
	Health = { "HealthBarsContainer", "healthBar" },
	Name = { "name" },
	CastBar = { "CastBarsContainer", "castBar", "CastBar" },
	-- (Clients whose plates keep buffs and debuffs in one frame, BuffFrame,
	-- mostly show your debuffs there: it goes with Debuffs.)
	Buffs = { "AurasFrame.BuffListFrame" },
	Debuffs = { "AurasFrame.DebuffListFrame", "AurasFrame.CrowdControlListFrame", all = true,
		fallback = { "BuffFrame" } },
	-- (On the plates that are up. Over the rest, the Names grid's Raid marker
	-- row keeps one of Effects' own.)
	RaidMarker = { "RaidTargetFrame" },
	Classification = { "ClassificationFrame", "classificationIndicator", all = true },
	Level = { "PlayerLevelDiffFrame", "LevelFrame", "levelText", all = true },
	Threat = { "aggroHighlight", "aggroHighlightBase", "aggroHighlightAdditive", "aggroFlash", all = true },
	-- (Forever's is the health bar's gold border, on your target.)
	Highlight = { "selectionHighlight", "healthBar.selectedBorder", all = true },
	Widgets = { "WidgetContainer" },
}

-- How far each part shows, 0 to 1, faded at the UI's fade speeds.
local levels = {}

-- A plate held up only for its name (see ns.SetPlateBody): how much of its
-- alpha the rest of it gets ([plate] = 0 to 1, nil for all of it), and the
-- name ([plate] = 0 to 1, nil for none of its own). And one held up for a
-- quest mark alone (Quest Vision's ! only): the mark's ([plate] = 0 to 1).
local bodyShare, nameShare, markShare = {}, {}, {}

local function Usable(frame)
	return type(frame) == "table" and frame.SetAlpha and not (frame.IsForbidden and frame:IsForbidden())
end

local function Field(unitFrame, field)
	local value = unitFrame
	for name in field:gmatch("[^.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[name]
	end
	return value
end

-- Calls fn(frame, ...) for each of a part's frames on a unit frame (or its
-- fallback's, when it has none of them).
local function EachPartFrame(unitFrame, part, fn, ...)
	local fields = PART_FRAMES[part]
	local found = false
	for _, field in ipairs(fields) do
		local frame = Field(unitFrame, field)
		if Usable(frame) then
			found = true
			fn(frame, ...)
			if not fields.all then
				return
			end
		end
	end
	if not found and fields.fallback then
		for _, field in ipairs(fields.fallback) do
			local frame = Field(unitFrame, field)
			if Usable(frame) then
				fn(frame, ...)
				return
			end
		end
	end
end

-- The game sets some of these parts' alpha itself (the cast bar fades out
-- after a cast), so while a part is faded its alpha is put back to ours every
-- frame, as with the plates. [part frame] = alpha.
local held = {}
local keeper = CreateFrame("Frame")
keeper:Hide()
keeper:SetScript("OnUpdate", ns.Profiled("Plate parts keeper", function(self)
	for frame, wanted in pairs(held) do
		-- (A secret alpha can't be compared: set ours again.)
		local alpha = frame:GetAlpha()
		if (issecretvalue and issecretvalue(alpha)) or alpha ~= wanted then
			frame:SetAlpha(wanted)
		end
	end
	if not next(held) then
		self:Hide()
	end
end))

-- WoW Forever's personal resource bars are a plate too: theirs are left alone.
local function PersonalPlate()
	return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
end

-- The game's own alpha for a part, from before it was first held: some aren't
-- at full (Classic Era's target highlight, a faint white over the bar, went
-- solid white when let go at 1). [part frame] = alpha.
local own = {}

local function Fade(frame, alpha)
	if alpha < 1 then
		if not held[frame] then
			local base = frame:GetAlpha()
			own[frame] = type(base) == "number" and not (issecretvalue and issecretvalue(base)) and base or 1
		end
		held[frame] = alpha * own[frame]
		frame:SetAlpha(held[frame])
	elseif held[frame] then
		held[frame] = nil -- (let go: back to the game's own, then the game's again)
		frame:SetAlpha(own[frame] or 1)
		own[frame] = nil
	end
end

-- A plate showing its name alone has it centred over where the health bar
-- was (retail's sits at the bar's left end): its own justification is put
-- back once the rest of the plate shows. [name text] = the game's justification.
local centred = {}

local function CentreName(unitFrame, on)
	local name = unitFrame.name
	if not (Usable(name) and name.SetJustifyH and name.GetJustifyH) then
		return
	end
	if on then
		if not centred[name] then
			centred[name] = name:GetJustifyH() or "LEFT"
		end
		if name:GetJustifyH() ~= "CENTER" then
			name:SetJustifyH("CENTER")
		end
	elseif centred[name] then
		name:SetJustifyH(centred[name])
		centred[name] = nil
	end
end

-- Names on plates showing just the name are drawn by a text of our own (with
-- the Nameplates page's tick), the game's name faded to nothing behind it:
-- the game keeps setting its own name's colour, font and place (and on WoW
-- Forever won't even say where it is), ours it leaves alone. Ours sits on the
-- game's name, moved up or down as the Name Style page says, coloured as the
-- game colours names over heads: red hostile, yellow neutral, green friendly,
-- friendly players blue, white or in the class colours their plates give
-- them (plateNameFriends). WoW Forever's colours and names can be secret: they
-- go straight from the game to our text. [unit frame] = our text.
local texts = {}
-- [unit frame] = a copy of our text in its last band's look, fading out
-- while the text fades in at the new one (see swaps).
local ghosts = {}

-- Marked plates' colors (the Target Indicator page's Also color column: see
-- TintTarget, below), [unit frame] = how far it's in (level, the rows'),
-- and each part's color ({ r, g, b }, nil for the game's: name, bar, border).
local tints = {}

-- A color blended into a part's (name, bar or border), as far as it's in.
local function Blend(r, g, b, tint, part)
	local level, colour = tint.level, tint[part]
	return r + (colour[1] - r) * level, g + (colour[2] - g) * level, b + (colour[3] - b) * level
end

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Ask(fn, ...)
	local ok, value = pcall(fn, ...)
	return ok and Known(value) and value and true or false
end

-- A name style setting (the Name Style page's, see Core's DEFAULTS).
local function Style(key)
	local value = ns.db and ns.db[key]
	if value == nil then
		return ns.DEFAULTS[key]
	end
	return value
end

-- Whether a unit's name takes a colour of ours: true for the game's colour
-- for it over heads, a friendly player's colour of our own ("blue",
-- "white"), or false for the plate's own (class colours).
local function TintUnit(unit)
	local okGuid, guid = pcall(UnitGUID, unit)
	if okGuid and Known(guid) and type(guid) == "string" and guid:find("^Player%-")
		and not Ask(UnitCanAttack, "player", unit) then
		local friends = Style("plateNameFriends")
		return friends ~= "class" and friends
	end
	return true
end

-- Friendly players' colours of our own. Blue as the game's names over their
-- heads (read off a screenshot: the game's colour for them on plates is a
-- far darker pure blue); green, its own, while they're PvP flagged, as
-- there too.
local FRIEND_COLOURS = { blue = { 0.4, 0.4, 1 }, white = { 1, 1, 1 } }
ns.PLATE_FRIEND_COLOURS = FRIEND_COLOURS -- (the Name Style page's preview)

local function PaintName(text, unit, own)
	local colour = FRIEND_COLOURS[own or ""]
	if colour and not (own == "blue" and Ask(UnitIsPVP, unit)) then
		text:SetTextColor(colour[1], colour[2], colour[3])
	elseif UnitSelectionColor then
		pcall(function() text:SetTextColor(UnitSelectionColor(unit)) end)
	else
		local reaction = Ask(UnitReaction, unit, "player") and UnitReaction(unit, "player")
		local color = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
		if color then
			text:SetTextColor(color.r, color.g, color.b)
		end
	end
end

local OUTLINES = { [0] = "", "OUTLINE", "THICKOUTLINE" }

-- (Flag by flag: a font's own can come back spaced, "MONOCHROME, OUTLINE",
-- and SetFont won't take a blank one between commas.)
local function Outlined(flags, outline)
	local kept = {}
	for flag in tostring(flags or ""):gmatch("[^,%s]+") do
		if flag ~= "OUTLINE" and flag ~= "THICKOUTLINE" then kept[#kept + 1] = flag end
	end
	if OUTLINES[outline] and OUTLINES[outline] ~= "" then
		kept[#kept + 1] = OUTLINES[outline]
	end
	return table.concat(kept, ",")
end
ns.OutlinedFlags = Outlined -- (the Name Style page's preview)

-- A font file holds one alphabet: a name set in the plate's file shows
-- Cyrillic (or Korean, Chinese) letters as boxes. So names get a font family
-- of our own, like the game's plate font: its font for each alphabet, at our
-- size and outline. (From the game's font object where it can say which font
-- each alphabet has; else the game's usual ones.) Kept by size and flags.
-- nil on clients without font families.
local ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
local ALPHABET_FILES = { russian = "Fonts\\FRIZQT___CYR.TTF", korean = "Fonts\\2002.TTF",
	simplifiedchinese = "Fonts\\ARKai_T.ttf", traditionalchinese = "Fonts\\blei00d.TTF" }
local families, familyCount = {}, 0

-- object: the game's font object for the name (its other alphabets' fonts);
-- file, size: its roman font as it is; scale: times that size.
local function NameFamily(object, file, size, scale, flags)
	if not CreateFontFamily or not (file and size) then
		return nil
	end
	local key = tostring(object) .. "|" .. file .. "|" .. ("%.1f"):format(size * scale) .. "|" .. (flags or "")
	local family = families[key]
	if family == nil then
		local members = {}
		for _, alphabet in ipairs(ALPHABETS) do
			local memberFile, memberSize = file, size
			if alphabet ~= "roman" then
				memberFile = ALPHABET_FILES[alphabet]
				local ok, member = pcall(function() return object:GetFontObjectForAlphabet(alphabet) end)
				local memberFont, height = nil, nil
				if ok and member then
					memberFont, height = member:GetFont()
				end
				if memberFont then
					memberFile, memberSize = memberFont, height or size
				end
			end
			members[#members + 1] = { alphabet = alphabet, file = memberFile, height = memberSize * scale,
				flags = flags or "" }
		end
		familyCount = familyCount + 1
		local ok, made = pcall(CreateFontFamily, "CinematicPlateName" .. familyCount, members)
		family = ok and made or false
		families[key] = family
	end
	return family or nil
end
ns.PlateNameFamily = NameFamily

-- Sets a text's font, every alphabet's letters drawn (a family where the
-- client has them), its words set again so they take it.
local function SetNameFont(text, object, file, size, scale, flags)
	local family = NameFamily(object, file, size, scale, flags)
	if family then
		text:SetFontObject(family)
	else
		pcall(text.SetFont, text, file, size * scale, flags)
	end
	pcall(function() text:SetText(text:GetText()) end)
end
ns.SetPlateNameFont = SetNameFont

-- Further off, smaller and lower: the game's names over heads are drawn in
-- the world, so they shrink with their distance from the camera (and take
-- over from the plate's at the edge of nameplate range). WoW Forever's
-- plates don't scale, so ours are sized and placed by that distance, as
-- near as it can be told: the camera's from you (exact), plus the unit's
-- from you in bands, the game only saying whether it's within about 11
-- yards (trade range) and 28 (follow range). Size and height follow
-- perspective (one over the distance) through the Name Style page's two
-- points, close and far, and on past them. A unit has to stay in a new band
-- a moment first, and its name then swaps: a copy in the old look fading out
-- as the new fades in, both sliding to the new height (a size can't change
-- smoothly, a place can: see ghosts and SwapShares);
-- zooming changes them in small steps. Bands aren't
-- looked at in fights (the game may not allow it). Not on retail, whose
-- plates scale with distance themselves. [plate] = band, 1 to 3 (nil: 2).
local FAR_USED = not ns.isRetail
local FAR_CHECK, FAR_HOLD, FAR_SWAP = 0.25, 0.5, 0.6 -- seconds
local BAND_YARDS = { 4, 16, 35 } -- a unit's rough distance from you, by band
local CLOSE_YARDS, FAR_YARDS = 10, 50 -- from the camera: the page's two points
local SIZE_STEP = 0.05 -- size changes in steps (text sized smoothly wobbles)
local bandOf, farChecked = {}, {}
local farSince = {} -- [plate] = when it was first seen in another band
local swaps = {} -- [plate] = { started = time, to = band }
local zoom = 0 -- the camera's distance from you, this frame

-- Out of sight, gone: the game's names over heads hide behind walls, a
-- plate shows through them. The game dims a plate whose unit is out of
-- sight (nameplateOccludedAlphaMult, the plate's own alpha: WoW Forever
-- does this much), so a name shown alone fades out while its plate is
-- dimmed, and back as its unit comes into sight. Full plates are left
-- dimmed as the game has them. [plate] = how far it shows (nil: all).
local sight = {}
local SIGHT_FADE = 0.4 -- seconds

-- A unit's band: 1 within about 11 yards, 2 within 28, 3 beyond; nil when
-- the game won't say.
local function Band(unit)
	if not unit or InCombatLockdown() then
		return nil
	end
	local ok, near = pcall(CheckInteractDistance, unit, 4)
	if not ok or not Known(near) or near == nil then
		return nil
	end
	if not near then
		return 3
	end
	local okClose, close = pcall(CheckInteractDistance, unit, 2)
	return (okClose and Known(close) and close) and 1 or 2
end

-- A name's size (times the plate's) and height for its band, at the
-- camera's distance now (see bandOf); retail's, as the page says.
local function Look(band)
	if not FAR_USED then
		return Style("plateNameSize"), Style("plateNameY")
	end
	local yards = math.max(1, zoom + BAND_YARDS[band or 2])
	local t = (1 / yards - 1 / FAR_YARDS) / (1 / CLOSE_YARDS - 1 / FAR_YARDS)
	local size = Style("plateNameFarSize") + t * (Style("plateNameCloseSize") - Style("plateNameFarSize"))
	local y = Style("plateNameFarY") + t * (Style("plateNameCloseY") - Style("plateNameFarY"))
	size = math.min(3, math.max(0.2, size))
	return math.floor(size / SIZE_STEP + 0.5) * SIZE_STEP, math.floor(math.min(80, math.max(-80, y)) + 0.5)
end

-- How far a plate's name is through swapping to its new look: 0 to 1 (1:
-- none under way).
local function SwapFade(plate)
	local swap = swaps[plate]
	if not swap then
		return 1
	end
	return math.min(1, (GetTime() - swap.started) / FAR_SWAP)
end

-- How much shows of the new look (in) and the old (out) that far through:
-- the old fading out over the first half, the new in over the second, with
-- only a sliver of overlap (two sizes over each other read as a double image).
local SWAP_OVERLAP = 0.1
local function SwapShares(t)
	local half = (1 + SWAP_OVERLAP) / 2
	local out = math.max(0, 1 - t / half)
	local into = math.min(1, math.max(0, (t - (1 - half)) / half))
	return into, out
end

local function UnitOf(plate)
	return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

-- Draws our text over the game's name: its look when that changed (dirty),
-- then its words and colour, which the game may change at any time.
local function DrawName(text, name, unit)
	if text.dirty then
		text.dirty = nil
		local object = name.GetFontObject and name:GetFontObject()
		local file, size, flags = name:GetFont()
		if not file then
			object = _G.SystemFont_NamePlate or _G.GameFontNormal
			file, size, flags = object:GetFont()
		end
		SetNameFont(text, object, file, size, text.size, Outlined(flags, Style("plateNameOutline")))
		if Style("plateNameShadow") then
			text:SetShadowOffset(Style("plateNameShadowX"), Style("plateNameShadowY"))
			text:SetShadowColor(0, 0, 0, Style("plateNameShadowAlpha"))
		else
			text:SetShadowOffset(0, 0)
		end
		-- (Further off, lower: a plate's name sits a fixed height over the unit's
		-- head, and the game's names over heads come down closer to it with distance.)
		text:ClearAllPoints()
		text:SetPoint("BOTTOM", name, "BOTTOM", 0, text.y)
	end
	-- (The game's own words: a secret name shows all the same.)
	local ok, words = pcall(name.GetText, name)
	if not ok then
		ok, words = pcall(UnitName, unit)
	end
	if ok then
		pcall(text.SetText, text, words)
	end
	-- (Colour only: on WoW Forever a FontString's colour carries its alpha, and
	-- the game's name is faded out under ours, so its alpha is 0, tested.)
	local alpha = text:GetAlpha()
	local tint = Style("plateNameColour") and TintUnit(unit)
	if tint then
		PaintName(text, unit, tint ~= true and tint or nil)
	else
		-- (A player's class colour from their class, not the game's name, which
		-- it can turn white.)
		local okClass, _, class = pcall(UnitClass, unit)
		local colour = okClass and Known(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if colour then
			text:SetTextColor(colour.r, colour.g, colour.b)
		else
			pcall(function()
				local r, g, b = name:GetTextColor()
				text:SetTextColor(r, g, b)
			end)
		end
	end
	-- (Kept, for your target's color going in and out over it: see TintTarget.
	-- A colour read back secret, as the game's can be when it redraws its name
	-- on mouseover, keeps the last one: blending nothing in showed the plain
	-- name for a frame, a flash.)
	local okColour, r, g, b = pcall(text.GetTextColor, text)
	if okColour and type(r) == "number" and Known(r) and Known(g) and Known(b) then
		text.baseR, text.baseG, text.baseB = r, g, b
	end
	local targetTint = tints[text:GetParent()]
	if targetTint and targetTint.name and text.baseR then
		text:SetTextColor(Blend(text.baseR, text.baseG, text.baseB, targetTint, "name"))
	end
	text:SetAlpha(alpha)
	-- Retail's plates grow as their units come nearer: undone, for one size.
	if ns.isRetail and text.SetScale then
		local scale = 1
		local parent = text:GetParent()
		if Style("plateNameFixedSize") and parent and parent.GetEffectiveScale then
			local plateScale, uiScale = parent:GetEffectiveScale(), UIParent:GetEffectiveScale()
			if Known(plateScale) and Known(uiScale) and plateScale > 0 then
				scale = uiScale / plateScale
			end
		end
		text:SetScale(scale)
	end
end

-- A text's size and height as its band and the camera have them now
-- (dirty when they changed).
local function UpdateLook(text, band)
	local size, y = Look(band)
	if text.size ~= size or text.y ~= y then
		text.size, text.y, text.dirty = size, y, true
	end
end

-- Shows or hides our text for a plate, at alpha (nil: hidden), and while
-- its band swaps, its copy in the old look fading out under it.
local function OwnName(plate, alpha)
	local unitFrame = plate.UnitFrame
	local text, ghost = texts[unitFrame], ghosts[unitFrame]
	local name = unitFrame.name
	local unit = UnitOf(plate)
	if not (alpha and alpha > 0 and unit and Usable(name)) then
		if text then
			text:Hide()
		end
		if ghost then
			ghost:Hide()
		end
		return
	end
	if not text then
		text = unitFrame:CreateFontString(nil, "OVERLAY")
		text.dirty = true
		texts[unitFrame] = text
	end
	local share = SwapFade(plate)
	local into, out = SwapShares(share)
	text.band = bandOf[plate] or 2
	UpdateLook(text, text.band)
	DrawName(text, name, unit)
	text:SetAlpha(alpha * into)
	text:Show()
	local swap = swaps[plate]
	if swap and share < 1 then
		if not ghost then
			ghost = unitFrame:CreateFontString(nil, "OVERLAY")
			ghost.dirty = true
			ghosts[unitFrame] = ghost
		end
		ghost.band = swap.from
		UpdateLook(ghost, ghost.band)
		DrawName(ghost, name, unit)
		ghost:SetAlpha(alpha * out)
		ghost:Show()
		-- (Both slide from the old height to the new together, so they sit on
		-- one line and only the size blends: a place moves smoothly, a size
		-- doesn't.)
		local y = ghost.y + (text.y - ghost.y) * share
		for _, each in ipairs({ text, ghost }) do
			each:ClearAllPoints()
			each:SetPoint("BOTTOM", name, "BOTTOM", 0, y)
		end
		text.slid = true
	else
		if ghost then
			ghost:Hide()
		end
		if text.slid then
			text.slid = nil
			text:ClearAllPoints()
			text:SetPoint("BOTTOM", name, "BOTTOM", 0, text.y)
		end
	end
end

-- Our text for a plate while it shows (the guild line goes under it).
function ns.PlateNameText(plate)
	local text = plate and plate.UnitFrame and texts[plate.UnitFrame]
	return text and text:IsShown() and text or nil
end

local RefreshQuestIcon -- (below: its quest mark goes by the name shown alone)

local function ApplyPlate(plate, personal)
	local unitFrame = plate and plate.UnitFrame
	if not Usable(unitFrame) or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	local body = bodyShare[plate] or 1
	local kept = nameShare[plate]
	-- A plate filling in round a name kept up (your target clicked) or
	-- emptying back to it: the name crossfades, so its look never jumps.
	-- Its name-only look fades out over the first half of the rest coming in,
	-- the plate's own look fades in over the second half (and back).
	local crossfading = kept ~= nil and body < 1
	local nameOnly = crossfading and body < 0.5
	local nameFade = crossfading and (nameOnly and 1 - 2 * body or 2 * body - 1) or 1
	local nameAlpha = nameOnly and kept * nameFade * (sight[plate] or 1) or 0
	-- (Our own text in its place, with the Nameplates page's tick: see texts.)
	local ours = nameOnly and plate ~= personal and Style("plateNameStyle")
	CentreName(unitFrame, nameOnly and not ours)
	OwnName(plate, ours and nameAlpha * Style("plateNameAlpha") or nil)
	for _, part in ipairs(ns.PLATE_PARTS) do
		local level = plate ~= personal and levels[part] or 1
		if part == "Name" then
			if ours then
				level = 0
			elseif nameOnly then
				level = nameAlpha
			elseif crossfading then
				level = math.max(level, kept) * nameFade
			else
				level = math.max(level * body, kept or 0)
			end
		else
			level = level * body
		end
		EachPartFrame(unitFrame, part, Fade, level)
	end
	-- (And the guild line under a name shown alone: PlateGuild.lua. It sits
	-- under our text, so it fades in with its new look.)
	ns.SetPlateGuild(plate, plate ~= personal and nameAlpha * (ours and (SwapShares(SwapFade(plate))) or 1) or 0)
	if nameOnly or crossfading then
		RefreshQuestIcon(plate)
	end
	if next(held) then
		keeper:Show()
	end
end

local function ApplyAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local personal = PersonalPlate()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		ApplyPlate(plate, personal)
	end
end
ApplyAll = ns.Profiled("Plate parts", ApplyAll)

-- After a name style change (the Name Style page): our texts drawn anew.
function ns.RefreshPlateNameStyle()
	for _, text in pairs(texts) do
		text.dirty = true
	end
	for _, ghost in pairs(ghosts) do
		ghost.dirty = true
	end
	ApplyAll()
end

-- Whether any part is faded (or still held from being faded).
local function AnyFaded()
	for _, part in ipairs(ns.PLATE_PARTS) do
		if (levels[part] or 1) < 1 then
			return true
		end
	end
	return next(held) ~= nil or next(bodyShare) ~= nil
end

-- The class icon rows (ns.PLATE_CLASS_PARTS): our own icon left of a player's
-- health bar, where Duel Vision's badge goes (and giving way to it), friendly
-- and enemy players apart. Hidden unless ticked: in CineMode as its row says,
-- outside it only with Always ticked.
local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local plateClass = {} -- [plate] = { part = row, class = file name }, or false for no icon
local icons = {} -- [plate] = icon frame

-- What icon a plate's unit has, if any: players' only. (Players that can't be
-- attacked count as friendly.)
local function ReadClass(plate)
	local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	if not unit or not Ask(UnitIsPlayer, unit) then
		return false
	end
	local ok, _, class = pcall(UnitClass, unit)
	if not (ok and Known(class) and type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) then
		return false
	end
	return { part = Ask(UnitCanAttack, "player", unit) and "ClassEnemy" or "ClassFriendly", class = class }
end

local function ClassIcon(plate)
	local icon = icons[plate]
	local unitFrame = plate.UnitFrame
	if icon or not Usable(unitFrame) then
		return icon
	end
	local bar = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame
	icon = CreateFrame("Frame", nil, unitFrame)
	icon:SetSize(22, 22)
	icon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
	icon:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	icon.texture = icon:CreateTexture(nil, "OVERLAY")
	icon.texture:SetAllPoints()
	icon.texture:SetTexture(CLASS_TEXTURE)
	icons[plate] = icon
	return icon
end

-- Shows or hides a plate's class icon as its row and its unit say.
local function RefreshClass(plate)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	if plateClass[plate] == nil then
		plateClass[plate] = ReadClass(plate)
	end
	local info = plateClass[plate]
	local level = info and plate ~= PersonalPlate() and not ns.DuelBadgeShown(plate)
		and (levels[info.part] or 0) * (bodyShare[plate] or 1) or 0
	local icon = icons[plate]
	if level <= 0 then
		if icon then
			icon:Hide()
		end
		return
	end
	icon = ClassIcon(plate)
	if icon then
		icon.texture:SetTexCoord(unpack(CLASS_ICON_TCOORDS[info.class]))
		icon:SetAlpha(level)
		icon:Show()
	end
end

-- The role icon rows (ns.PLATE_ROLE_PARTS): the game's role icon left of a
-- group member's health bar (the level box is on the right), further out
-- while the class icon or Duel Vision's badge is there. A row per role,
-- shown like the class icons. Only players with a role set have one.
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLES = {
	TANK = { part = "RoleTank", coords = { 0, 19 / 64, 22 / 64, 41 / 64 } },
	HEALER = { part = "RoleHealer", coords = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 } },
	DAMAGER = { part = "RoleDamager", coords = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } },
}
local plateRole = {} -- [plate] = an entry of ROLES, or false for no icon
local roleIcons = {} -- [plate] = icon frame

-- A plate's unit's role in your group, if it's a player with one.
local function ReadRole(plate)
	local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	if not unit or not UnitGroupRolesAssigned or not Ask(UnitIsPlayer, unit) then
		return false
	end
	local ok, role = pcall(UnitGroupRolesAssigned, unit)
	return ok and Known(role) and ROLES[role] or false
end

local function RoleIcon(plate)
	local icon = roleIcons[plate]
	local unitFrame = plate.UnitFrame
	if icon or not Usable(unitFrame) then
		return icon
	end
	local bar = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame
	icon = CreateFrame("Frame", nil, unitFrame)
	icon:SetSize(18, 18)
	icon.bar = bar
	icon:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	icon.texture = icon:CreateTexture(nil, "OVERLAY")
	icon.texture:SetAllPoints()
	icon.texture:SetTexture(ROLE_TEXTURE)
	roleIcons[plate] = icon
	return icon
end

-- Shows or hides a plate's role icon as its row and its unit say.
local function RefreshRoleIcon(plate)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	if plateRole[plate] == nil then
		plateRole[plate] = ReadRole(plate)
	end
	local role = plateRole[plate]
	local level = role and plate ~= PersonalPlate() and (levels[role.part] or 0) * (bodyShare[plate] or 1) or 0
	local icon = roleIcons[plate]
	if level <= 0 then
		if icon then
			icon:Hide()
		end
		return
	end
	icon = RoleIcon(plate)
	if icon then
		local classIcon = icons[plate]
		local beside = ns.DuelBadgeShown(plate) or (classIcon and classIcon:IsShown())
		icon:ClearAllPoints()
		icon:SetPoint("RIGHT", icon.bar, "LEFT", beside and -28 or -3, 0)
		icon.texture:SetTexCoord(unpack(role.coords))
		icon:SetAlpha(level)
		icon:Show()
	end
end

-- The Quest Icon row: a golden exclamation mark left of the health bar of a
-- unit for a quest objective you haven't finished (ns.IsQuestMob), where
-- players' class icons go (quest mobs aren't players). Shown like the class
-- icons, its one box (Always) ticked on the Vision page's Quest Vision, whose
-- Enable and page switch it follows. On a plate showing just its name (Quest
-- Vision's Name), it's left of the name instead, fading with it. Quest
-- Vision's ! only shows it whatever the row says, and alone (no plate or
-- name to go by) on the middle of where the plate is.
local questIcons = {} -- [plate] = icon frame

local function QuestIcon(plate)
	local icon = questIcons[plate]
	local unitFrame = plate.UnitFrame
	if icon or not Usable(unitFrame) then
		return icon
	end
	local bar = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame
	icon = CreateFrame("Frame", nil, unitFrame)
	icon:SetSize(20, 20)
	icon.bar = bar
	icon:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	icon.texture = icon:CreateTexture(nil, "OVERLAY")
	icon.texture:SetAllPoints()
	ns.SetQuestMark(icon.texture)
	questIcons[plate] = icon
	return icon
end

-- A number a frame's method gives, if the game will say.
local function Measure(frame, method)
	local ok, a, b = pcall(frame[method], frame)
	if ok and type(a) == "number" and Known(a) and (b == nil or (type(b) == "number" and Known(b))) then
		return a, b
	end
end

-- Where a quest mark goes, its middle from the health bar's middle. Left of
-- the bar; left of the name shown alone (ours, else the game's: its middle
-- less half its words' width); alone, the bar's middle. Moving between them
-- as the plate does: with a kept name, from the name's spot to the bar's as
-- the rest of the plate (body) fills in; with a mark alone, from the middle
-- as the plate or name (shown, of mark) fades in. Each move takes the first
-- QUEST_MOVE of the fade (half: of 1.5 seconds, 0.75), eased, the
-- plate still fading in round it after. nil when the game won't say where
-- the bar or the name is.
local QUEST_MOVE = 0.5

local function QuestMove(share)
	local t = math.min(1, math.max(0, share / QUEST_MOVE))
	return t * t * (3 - 2 * t)
end

-- The game's icons that can sit left of the health bar (a rare or elite's
-- dragon, the raid marker): the quest mark goes left of any showing there.
local SIDE_ICONS = { "ClassificationFrame", "classificationIndicator", "RaidTargetFrame" }

-- The quest mark's middle from the bar's middle, left of the bar and of any
-- side icon showing in its way (x, the start, is left of the bar alone).
-- Where the game won't say where things are (retail's plates: sizes, but no
-- spots): a side icon showing is taken to sit left of the bar where it's
-- anchored (its RIGHT to the bar's LEFT, offset as its anchor says, if the
-- game will say), the classification's dragon there even if it won't. Less
-- SIDE_ICON_TRIM: the clear edges round the dragon and the thin ! (tested on
-- retail: none left a wide gap, 16 overlapped).
local SIDE_ICON_TRIM = 9

local function PastSideIconsBySize(icon, unitFrame, x)
	local barWidth = Measure(icon.bar, "GetWidth")
	if not barWidth then
		return x
	end
	for i, field in ipairs(SIDE_ICONS) do
		local frame = unitFrame[field]
		if Usable(frame) and Ask(frame.IsVisible, frame) and (Measure(frame, "GetAlpha") or 0) > 0 then
			local width = Measure(frame, "GetWidth")
			local ok, point, _, relative, offset = pcall(frame.GetPoint, frame, 1)
			local known = ok and Known(point) and Known(relative) and Known(offset)
			local left = known and type(point) == "string" and point:find("RIGHT")
				and type(relative) == "string" and relative:find("LEFT")
			if width and (left or (not known and i <= 2)) then
				offset = (left and type(offset) == "number") and offset or 0
				x = math.min(x, -(barWidth / 2 - offset + width + 2 + icon:GetWidth() / 2 - SIDE_ICON_TRIM))
			end
		end
	end
	return x
end

local function PastSideIcons(icon, unitFrame, x)
	local bar = icon.bar
	local barX = Measure(bar, "GetCenter")
	local barScale, scale = Measure(bar, "GetEffectiveScale"), Measure(icon, "GetEffectiveScale")
	if not (barX and barScale and scale) then
		return PastSideIconsBySize(icon, unitFrame, x)
	end
	barX = barX * barScale
	local reach = barX + (x - icon:GetWidth() / 2) * scale -- (the mark's left, on screen)
	for _, field in ipairs(SIDE_ICONS) do
		local frame = unitFrame[field]
		if Usable(frame) and Ask(frame.IsVisible, frame) and (Measure(frame, "GetAlpha") or 0) > 0 then
			local left, right = Measure(frame, "GetLeft"), Measure(frame, "GetRight")
			local own = Measure(frame, "GetEffectiveScale")
			if left and right and own then
				left, right = left * own, right * own
				-- (In the mark's way: from its left to the bar's middle.)
				if right > reach and left < barX then
					x = math.min(x, (left - barX) / scale - 2 - icon:GetWidth() / 2)
				end
			end
		end
	end
	return x
end

local function QuestIconSpot(icon, plate, body, kept, shown, mark)
	local half = icon:GetWidth() / 2
	local width = Measure(icon.bar, "GetWidth")
	if not width then
		return nil
	end
	local x, y = PastSideIcons(icon, plate.UnitFrame, -(width / 2 + 3 + half)), 0
	if kept and body < 1 then
		local barX, barY = Measure(icon.bar, "GetCenter")
		local unitFrame = plate.UnitFrame
		local text = texts[unitFrame]
		local left, nameY
		if text and text:IsShown() then
			left = Measure(text, "GetLeft")
			nameY = select(2, Measure(text, "GetCenter"))
		elseif Usable(unitFrame.name) then
			local nameX, centreY = Measure(unitFrame.name, "GetCenter")
			local words = Measure(unitFrame.name, "GetStringWidth")
			left, nameY = nameX and words and nameX - words / 2, centreY
		end
		if not (barX and left and nameY) then
			return nil
		end
		local nameX = left - 2 - half - barX
		local t = QuestMove(body)
		x, y = nameX + (x - nameX) * t, (nameY - barY) * (1 - t)
	end
	if mark > 0 then
		local t = QuestMove(shown / mark)
		x, y = x * t, y * t
	end
	return x, y
end

-- Puts a quest mark in its spot. (Where the game won't say where things
-- are: anchored to them, so it jumps between them.)
local function PlaceQuestIcon(icon, plate, body, kept, shown, mark)
	local x, y = QuestIconSpot(icon, plate, body, kept, shown, mark)
	local anchor
	if x then
		x, y, anchor = math.floor(x + 0.5), math.floor(y + 0.5), icon.bar
	else
		local text = kept and body < 0.5 and texts[plate.UnitFrame]
		anchor = (text and text:IsShown()) and text or icon.bar
		x, y = mark > shown and "alone" or "left", 0
	end
	if icon.anchor == anchor and icon.x == x and icon.y == y then
		return
	end
	icon.anchor, icon.x, icon.y = anchor, x, y
	icon:ClearAllPoints()
	if x == "alone" then
		icon:SetPoint("CENTER", icon.bar, "CENTER")
	elseif x == "left" then
		icon:SetPoint("RIGHT", anchor, "LEFT", anchor == icon.bar and -3 or -2, 0)
	else
		icon:SetPoint("CENTER", anchor, "CENTER", x, y)
	end
end

-- Whether the game's own icon shows over the unit: soft targeting's (speech
-- bubbles over someone to talk to, a gear...), on the plate's SoftTargetFrame
-- or, for the soft interact pick with its icon setting on, drawn in the world.
-- Our mark steps aside for it. Unreadable counts as no. (The frame stays
-- shown on every plate: it's its Icon the game shows or hides.)
-- (Retail's speech bubbles over a campaign NPC with something to say for a
-- quest can't be read, from the plate or the cursor (tested): both show.)
local function GameIconShows(plate, unit)
	local frame = plate.UnitFrame and plate.UnitFrame.SoftTargetFrame
	if type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden()) then
		frame = type(frame.Icon) == "table" and frame.Icon or frame
	end
	if type(frame) == "table" and frame.IsVisible and not (frame.IsForbidden and frame:IsForbidden()) then
		local okShown, shown = pcall(frame.IsVisible, frame)
		local okAlpha, alpha = pcall(frame.GetEffectiveAlpha, frame)
		if okShown and Known(shown) and shown and okAlpha and type(alpha) == "number" and Known(alpha)
			and alpha > 0.05 then
			return true
		end
	end
	if not (UnitIsUnit and Ask(UnitIsUnit, unit, "softinteract")) or GetCVar("SoftTargetIconInteract") ~= "1" then
		return false
	end
	local mode = tonumber(GetCVar("SoftTargetInteract")) or 0
	local pad = ns.IsGamePadOn and ns.IsGamePadOn() or false
	return mode == 3 or (mode == 1 and pad) or (mode == 2 and not pad)
end

-- For /cine debug questmob: what GameIconShows sees on the unit's plate.
function ns.DescribeGameIcon(unit)
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not (ok and plate) then
		return "game icon: no plate"
	end
	local function State(frame)
		if type(frame) ~= "table" or (frame.IsForbidden and frame:IsForbidden()) then
			return tostring(frame and "forbidden" or nil)
		end
		local okS, shown = pcall(frame.IsShown, frame)
		local okV, visible = pcall(frame.IsVisible, frame)
		local okA, alpha = pcall(frame.GetEffectiveAlpha, frame)
		local okT, atlas = pcall(function() return frame.GetAtlas and frame:GetAtlas() end)
		local okF, file = pcall(function() return frame.GetTexture and frame:GetTexture() end)
		local function V(good, value)
			return good and Known(value) and tostring(value) or (good and "secret" or "err")
		end
		return ("shown=%s visible=%s alpha=%s atlas=%s file=%s"):format(V(okS, shown), V(okV, visible),
			V(okA, alpha), V(okT, atlas), V(okF, file))
	end
	local frame = plate.UnitFrame and plate.UnitFrame.SoftTargetFrame
	local icon = type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden()) and frame.Icon
	local icons = questIcons[plate]
	return ("game icon: shows=%s | SoftTargetFrame %s | its Icon %s | softinteract=%s softfriend=%s"
		.. " | SoftTargetInteract=%s SoftTargetIconInteract=%s SoftTargetIconFriend=%s | our mark shown=%s alpha=%s"):format(
		tostring(GameIconShows(plate, unit)), State(frame), State(icon),
		tostring(Ask(UnitIsUnit, unit, "softinteract")), tostring(Ask(UnitIsUnit, unit, "softfriend")),
		tostring(GetCVar("SoftTargetInteract")), tostring(GetCVar("SoftTargetIconInteract")),
		tostring(GetCVar("SoftTargetIconFriend")), tostring(icons and icons:IsShown()),
		tostring(icons and icons:GetAlpha()))
end

function RefreshQuestIcon(plate)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	-- (Showing just its name: as far as the name shows. See ApplyPlate.)
	local body, kept = bodyShare[plate] or 1, nameShare[plate]
	local nameOnly = kept ~= nil and body < 0.5
	local share = nameOnly and kept * (1 - 2 * body) * (sight[plate] or 1) or body
	local mark = markShare[plate] or 0
	local level = math.max(levels.QuestIcon or 0, ns.QuestMarkLevel and ns.QuestMarkLevel() or 0)
		* math.max(share, mark)
	local icon = questIcons[plate]
	local unit
	if level > 0 and plate ~= PersonalPlate() then
		unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if not (unit and ns.IsQuestMob(unit)) or GameIconShows(plate, unit) then
			level = 0
		end
	end
	if level <= 0 then
		if icon then
			icon:Hide()
		end
		return
	end
	icon = QuestIcon(plate)
	if icon then
		-- (One you can't do anything with: the "in progress" mark. See QuestMobs.)
		ns.SetQuestMark(icon.texture, unit and ns.IsPassiveQuestMob(unit))
		PlaceQuestIcon(icon, plate, body, kept, share, mark)
		icon:SetAlpha(level)
		icon:Show()
	end
end

-- The Target Arrow row: a mark on your target's plate, for when no target
-- frame shows what you've targeted (Pure Cinema), and on your focus's and
-- the one under the mouse. Shown like the class icons, but not faded with
-- the plate: one faded right out, or showing just its name, still has it. It
-- hides with the plate. Its look is the Style hub's Target Indicator page's,
-- a row for each kind: an arrow, chevron or diamond over the plate (clear of
-- the name), a glow behind its health bar, brackets, carets or corners round
-- it, or a line under it; colored, sized, raised and moving as that page says.
-- (Media/make_target_arrow.py and make_target_marks.py)
local ARROW_ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\"
local ARROW_OVER = { arrow = "TargetArrow", chevron = "TargetChevron", diamond = "TargetDiamond" }
local ARROW_SIDES = { brackets = "TargetBracket", carets = "TargetCaret" }
-- The corners' texture coordinates: top left as drawn, the others mirrored.
local CORNERS = {
	{ "TOPLEFT", -1, 1, 0, 1, 0, 1 }, { "TOPRIGHT", 1, 1, 1, 0, 0, 1 },
	{ "BOTTOMLEFT", -1, -1, 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, -1, 1, 0, 1, 0 },
}
local GOLD = { 1, 0.82, 0 }
local arrows = {} -- [plate] = arrow frame

-- A mark setting for a row (the Style hub's Nameplates page, see Core's
-- DEFAULTS): your target's are targetArrow<key>, the others' <id>Mark<key>,
-- but for Also color's, <id>Color<part> for every row.
-- Aggro on you (and its other rows) goes by your target's height, its look
-- too while its own style is "same", and its color while its color is.
-- A setting a row hasn't got: the same row's without its number, then
-- without its Distance, then its kind's (targetEnemyPast402,
-- targetEnemyPast40, targetEnemy, target: Core's MarkRowBase).
local AGGRO_COLOR_KEYS = { Color = true, R = true, G = true, B = true }
local function MarkParent(kind)
	local base, reaction, copy, distance = ns.MarkRowBase(kind)
	if copy then
		return base .. (reaction or "") .. (distance or "")
	end
	if distance then
		return base .. (reaction or "")
	end
	return reaction and base or nil
end
local function OwnSetting(key, kind)
	local value
	-- (Its Also color ticks: <id>ColorName, ColorBar and ColorBorder.)
	if key == "ColorName" or key == "ColorBar" or key == "ColorBorder" then
		value = Style(kind .. key)
	elseif kind == "target" then
		value = Style("targetArrow" .. key)
	else
		value = Style(kind .. "Mark" .. key)
	end
	if value == nil then
		local parent = MarkParent(kind)
		if parent then return OwnSetting(key, parent) end
	end
	return value
end
local function ArrowSetting(key, kind)
	kind = kind or "target"
	local base = ns.MarkRowBase(kind)
	if base == "aggro" and (key == "Y" or key == "BareY"
		or AGGRO_COLOR_KEYS[key] and OwnSetting("Color", kind) == "same") then
		kind, base = "target", "target"
	end
	local value = OwnSetting(key, kind)
	if base == "aggro" and key == "Style" and value == "same" then
		return Style("targetArrowStyle")
	end
	-- (The unit under the mouse: just the marks over its plate. Round it or
	-- under it, they hang in the air where its plate is hidden.)
	if base == "mouseover" and key == "Style" and not (ARROW_OVER[value] or value == "none") then
		return ns.DEFAULTS.mouseoverMarkStyle
	end
	return value
end
ns.TargetMarkSetting = ArrowSetting
ns.TargetMarkOwn = OwnSetting -- (as set, "same" and all: for copying a row)

-- Whose Also color a row's plate takes: its own, or an aggro row's while
-- it's your target's (AlsoSame), your target's ticks in your target's color.
local function TintKind(kind)
	if ns.MarkRowBase(kind) == "aggro" and OwnSetting("AlsoSame", kind) then
		return "target"
	end
	return kind
end
ns.TargetMarkTintKind = TintKind

-- A row's plate color (PlateColor): "-" none, the next fitting row's
-- (PlateLook); "game" the game's, whatever the rows below say; "same" its
-- mark's; "gold", "reaction", "class" or "custom" (PlateR, G, B).
local function PlateHow(kind)
	return ArrowSetting("PlateColor", kind) or "-"
end
local PLATE_PASS = { ["-"] = true, game = true }
-- Whether a row's plate color ticks a part (ColorName, ColorBar, ColorBorder)
-- and colors it: not on "-" or the game's (the page hides the ticks then).
local function AlsoOn(key, kind)
	return ArrowSetting(key, kind) and not PLATE_PASS[PlateHow(kind)] or false
end
ns.TargetMarkAlso = AlsoOn
ns.TargetPlateHow = PlateHow

-- Red, yellow or green by how a unit sees you (hostile: no unit, the preview).
local function ReactionColour(unit)
	local ok, reaction = pcall(UnitReaction, unit or "", "player")
	reaction = ok and Known(reaction) and type(reaction) == "number" and reaction or 2
	if reaction >= 5 then
		return 0, 1, 0
	elseif reaction == 4 then
		return 1, 1, 0
	end
	return 1, 0.1, 0.1
end

-- A colour for a unit (nil: the preview's, a hostile NPC) by how (gold,
-- reaction, class or custom: r, g, b).
local function ColourBy(how, unit, r, g, b)
	if how == "custom" then
		return r, g, b
	elseif how == "class" and unit then
		-- (By GUID: Forever's UnitIsPlayer can say no for a player.)
		local okGuid, guid = pcall(UnitGUID, unit)
		local ok, _, class = pcall(UnitClass, unit)
		local colour = okGuid and Known(guid) and type(guid) == "string" and guid:find("^Player%-")
			and ok and Known(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if colour then
			return colour.r, colour.g, colour.b
		end
	end
	if how == "reaction" or how == "class" then
		return ReactionColour(unit)
	end
	return unpack(GOLD)
end
-- The arrow's colour for a unit, by its kind's row (nil: your target's).
local function ArrowColour(unit, kind)
	return ColourBy(ArrowSetting("Color", kind), unit, ArrowSetting("R", kind), ArrowSetting("G", kind),
		ArrowSetting("B", kind))
end
-- The colour a row's plate color gives a unit's parts (its mark's on "same").
local function PlateColour(unit, kind)
	local how = PlateHow(kind)
	if how == "same" then
		return ArrowColour(unit, kind)
	end
	return ColourBy(how, unit, ArrowSetting("PlateR", kind) or 1, ArrowSetting("PlateG", kind) or 1,
		ArrowSetting("PlateB", kind) or 1)
end
ns.TargetPlateColour = PlateColour

-- Moving (the Target Indicator page's Moving ticks): the arrow, chevron and
-- diamond bob, the brackets, carets and corners close in, the glow and line
-- pulse, out and back every BOB_TIME seconds. Worked out each frame: an
-- animation group's BOUNCE looping jumped a few pixels for a frame as it
-- turned, at the top of each bob (seen frame by frame in a capture).
local BOB_TIME = 1.2

-- Whether a region shows, as far as the game will say: nil when it won't.
local function Seen(region)
	if not (region and region.IsVisible) then
		return nil
	end
	local ok, shown = pcall(region.IsVisible, region)
	if not ok or not Known(shown) then
		return nil
	end
	return shown and true or false
end

-- Whether the plate draws its health bar or name at all: the game hides
-- them itself on some plates (the alpha stays 1). Can't tell: it does.
local function PlateDrawn(plate)
	local unitFrame = plate.UnitFrame
	if not Usable(unitFrame) then
		return true
	end
	local text = texts[unitFrame]
	if text and text:IsShown() then
		return true
	end
	local bar = Seen(unitFrame.HealthBarsContainer or unitFrame.healthBar)
	local name = Seen(unitFrame.name)
	if bar == nil and name == nil then
		return true
	end
	return bar or name or false
end

-- A frame's alpha with all it's in (effective), 0 to 1: 1 when the game won't say.
local function Opacity(frame)
	local ok, alpha = pcall(frame.GetEffectiveAlpha, frame)
	return ok and type(alpha) == "number" and Known(alpha) and alpha or 1
end

-- How much of a plate shows, 0 to 1: its alpha (its unit frame's with all
-- it's in: the game fades that one too, a unit out of sight, and we never
-- do) times the most of its health bar or name (shown alone or not); none
-- while the game draws neither. Unknown alpha (secret): all of it.
local function PlateShowing(plate)
	if not PlateDrawn(plate) then
		return 0
	end
	local alpha = Opacity(Usable(plate.UnitFrame) and plate.UnitFrame or plate)
	local body = bodyShare[plate] or 1
	local shown = math.max((levels.Health or 1) * body, (levels.Name or 1) * body,
		(nameShare[plate] or 0) * (sight[plate] or 1))
	return alpha * shown
end

-- An arrow's pieces where they go, out (t) from 0 (at rest) to 1. The marks
-- over the plate sit over its name, raised by the Height setting; with
-- nothing of the plate showing, on the plate itself, centred on its health
-- bar (no name to clear: hung up there, they'd point at empty air), raised
-- by the no-plate Height. Between: moved as the quest mark is (QuestMove),
-- in the first part of the plate's fade, eased; and never faster than
-- MARK_MOVE seconds the whole way (the game showing or hiding a plate's bar
-- and name at once would jump it).
local MARK_MOVE = 0.4
local function PlaceArrow(arrow, t)
	local size = arrow.size
	local overY = arrow.overY
	if arrow.plate then
		local showing = QuestMove(PlateShowing(arrow.plate))
		local now = GetTime()
		local was = arrow.showing
		if was and arrow.placedAt then
			local step = (now - arrow.placedAt) / MARK_MOVE
			showing = math.max(was - step, math.min(was + step, showing))
		end
		arrow.showing, arrow.placedAt = showing, now
		if showing < 1 then
			local ok, high = pcall(arrow.GetHeight, arrow)
			high = ok and type(high) == "number" and Known(high) and high or 9
			local bare = -high / 2 - arrow.over:GetHeight() / 2 + arrow.bareRaise
			overY = bare + (overY - bare) * showing
		end
	end
	arrow.over:SetPoint("BOTTOM", arrow, "TOP", 0, overY + 4 * size * t)
	arrow.left:SetPoint("RIGHT", arrow, "LEFT", -3 + 3 * size * t, 0)
	arrow.right:SetPoint("LEFT", arrow, "RIGHT", 3 - 3 * size * t, 0)
	local out = 6 * size - 3 * size * t
	for i, corner in ipairs(arrow.corners) do
		local spec = CORNERS[i]
		corner:SetPoint(spec[1], arrow, spec[1], spec[2] * out, spec[3] * out)
	end
	arrow.glow:SetAlpha(1 - 0.45 * t)
	arrow.under:SetAlpha(1 - 0.45 * t)
end

-- Each frame while it shows: moving, and (on a plate) down onto it as the
-- plate's name and bar fade out.
local function ArrowMoves(arrow)
	PlaceArrow(arrow, arrow.bob and (1 - math.cos(GetTime() * 2 * math.pi / BOB_TIME)) / 2 or 0)
end

-- Makes a target arrow on a frame, over bar (a plate's health bar, or the
-- page's preview's): its pieces for every style, styled by StyleArrow.
local function MakeArrow(parent, bar)
	local arrow = CreateFrame("Frame", nil, parent)
	arrow:SetAllPoints(bar)
	arrow:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	arrow.over = arrow:CreateTexture(nil, "OVERLAY")
	-- (The glow behind the bar, on a frame of its own below it.)
	arrow.glowFrame = CreateFrame("Frame", nil, arrow)
	arrow.glowFrame:SetAllPoints()
	arrow.glowFrame:SetFrameLevel(math.max(0, arrow:GetFrameLevel() - 6))
	arrow.glow = arrow.glowFrame:CreateTexture(nil, "BACKGROUND")
	arrow.glow:SetTexture(ARROW_ART .. "TargetGlow")
	arrow.left = arrow:CreateTexture(nil, "OVERLAY")
	arrow.right = arrow:CreateTexture(nil, "OVERLAY")
	arrow.corners = {}
	for i, spec in ipairs(CORNERS) do
		local corner = arrow:CreateTexture(nil, "OVERLAY")
		corner:SetTexture(ARROW_ART .. "TargetCorner")
		corner:SetTexCoord(spec[4], spec[5], spec[6], spec[7])
		arrow.corners[i] = corner
	end
	arrow.under = arrow:CreateTexture(nil, "OVERLAY")
	arrow.under:SetTexture(ARROW_ART .. "TargetUnderline")
	return arrow
end

-- Gives an arrow its look for a unit, as the Target Indicator page's row for
-- its kind says (nil: your target's).
local function StyleArrow(arrow, unit, kind)
	local style, size = ArrowSetting("Style", kind), ArrowSetting("Size", kind)
	local r, g, b = ArrowColour(unit, kind)
	local over = ARROW_OVER[style]
	arrow.over:SetShown(over ~= nil)
	if over then
		arrow.over:SetTexture(ARROW_ART .. over)
		arrow.over:SetSize((style == "diamond" and 16 or 20) * size, (style == "diamond" and 16 or 20) * size)
	end
	arrow.glow:SetShown(style == "glow")
	arrow.glow:ClearAllPoints()
	arrow.glow:SetPoint("TOPLEFT", arrow, "TOPLEFT", -24 * size, 14 * size)
	arrow.glow:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 24 * size, -14 * size)
	local sides = ARROW_SIDES[style]
	arrow.left:SetShown(sides ~= nil)
	arrow.right:SetShown(sides ~= nil)
	if sides then
		for _, side in ipairs({ arrow.left, arrow.right }) do
			side:SetTexture(ARROW_ART .. sides)
			if style == "carets" then
				side:SetSize(12 * size, 12 * size)
			else
				side:SetSize(11 * size, 24 * size)
			end
		end
		arrow.left:SetTexCoord(0, 1, 0, 1)
		arrow.right:SetTexCoord(1, 0, 0, 1)
	end
	for _, corner in ipairs(arrow.corners) do
		corner:SetShown(style == "corners")
		corner:SetSize(10 * size, 10 * size)
	end
	arrow.under:SetShown(style == "underline")
	arrow.under:ClearAllPoints()
	arrow.under:SetPoint("TOPLEFT", arrow, "BOTTOMLEFT", 6, -3)
	arrow.under:SetPoint("TOPRIGHT", arrow, "BOTTOMRIGHT", -6, -3)
	arrow.under:SetHeight(6 * size)
	for _, piece in ipairs({ arrow.over, arrow.glow, arrow.left, arrow.right, arrow.under, unpack(arrow.corners) }) do
		piece:SetVertexColor(r, g, b)
	end
	-- (Placed at rest, then moving each frame while it shows, if it moves.)
	arrow.raise, arrow.bareRaise = ArrowSetting("Y"), ArrowSetting("BareY")
	arrow.size, arrow.overY = size, 18 + arrow.raise
	for _, piece in ipairs({ arrow.over, arrow.left, arrow.right, unpack(arrow.corners) }) do
		piece:ClearAllPoints()
	end
	PlaceArrow(arrow, 0)
	arrow.bob = ArrowSetting("Bob", kind)
	arrow:SetScript("OnUpdate", (arrow.bob or arrow.plate) and ArrowMoves or nil)
	arrow.styled = kind or "target"
end

-- For the Target Indicator page's preview.
function ns.MakeTargetArrow(parent, bar)
	return MakeArrow(parent, bar)
end
ns.StyleTargetArrow = StyleArrow
ns.TargetArrowColour = ArrowColour

local function TargetArrow(plate)
	local arrow = arrows[plate]
	local unitFrame = plate.UnitFrame
	if arrow or not Usable(unitFrame) then
		return arrow
	end
	arrow = MakeArrow(unitFrame, unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame)
	arrow:SetIgnoreParentAlpha(true)
	arrow.plate = plate
	arrows[plate] = arrow
	return arrow
end

-- Mark colors (the Target Indicator page's Also color column): a marked
-- plate's name, health bar and border each in the color of the first row
-- that fits it and colors that part, blended in as far as the row shows. The
-- game paints these again whenever it likes, so they're painted every frame
-- while a plate is tinted, then given back the colors they had. (Our own
-- name text: DrawName keeps its color.)
-- TintTarget(plate, level, unit, kinds): kinds = { name, bar, border }, each
-- the row (kind) whose color it takes, or nil for the game's; level 0 or no
-- kinds lets the plate go, if it's tinted.
local TintTarget
do
	local BORDER_FIELDS = { "selectionHighlight", "healthBar.selectedBorder" }
	-- [region] = { r, g, b, getter, setter, unit frame, part }: the color it had first
	local saved = {}

	-- A region's color, if the game will say: r, g, b and its alpha (or nil).
	local function ReadColour(region, getter)
		local ok, r, g, b, a = pcall(region[getter], region)
		if ok and type(r) == "number" and Known(r) and Known(g) and Known(b) then
			return r, g, b, type(a) == "number" and Known(a) and a or nil
		end
	end

	-- (Alpha kept: on WoW Forever a text's or texture's color carries it.)
	local function SetColour(region, setter, r, g, b, a)
		if a then
			pcall(region[setter], region, r, g, b, a)
		else
			pcall(region[setter], region, r, g, b)
		end
	end

	-- The game paints a part's color again whenever it likes, and once a
	-- frame wasn't enough: its color flickered through on frames it painted
	-- after us. So each part's setter is hooked, once: whatever color the game
	-- sets is kept as the one to give back, and ours goes straight back over
	-- it. (painting: our own calls, which the hook lets be.)
	local painting = false
	local hooked = {}
	local Paint

	local function Hook(region, setter)
		if hooked[region] then
			return
		end
		hooked[region] = true
		hooksecurefunc(region, setter, function(self, r, g, b)
			local first = saved[self]
			if painting or not first or not tints[first[6]] then
				return
			end
			if type(r) == "number" and Known(r) and Known(g) and Known(b) then
				first[1], first[2], first[3] = r, g, b
			end
			Paint(self, first[4], first[5], first[6], first[7])
		end)
		-- (Retail's name went white for a frame or two as the mouse came onto
		-- your target, logged, with no SetTextColor: a new font or vertex color
		-- resets a text's. Ours goes back over those too, as they happen.)
		if region:GetObjectType() == "FontString" then
			for _, other in ipairs({ "SetVertexColor", "SetFontObject", "SetFont" }) do
				if region[other] then
					hooksecurefunc(region, other, function(self)
						local first = saved[self]
						if not painting and first and tints[first[6]] then
							Paint(self, first[4], first[5], first[6], first[7])
						end
					end)
				end
			end
		end
	end

	function Paint(region, getter, setter, unitFrame, part)
		if not (region[getter] and region[setter]) then
			return
		end
		local r, g, b, a = ReadColour(region, getter)
		local first = saved[region]
		if not r then
			-- (Read back secret, as retail's name is after the game paints it on
			-- mouseover: ours goes over it all the same, at its last alpha known;
			-- leaving it showed the game's white name till it painted again.)
			if not first then
				return
			end
			a = first[8]
		elseif not first then
			first = { r, g, b, getter, setter, unitFrame, part, a }
			saved[region] = first
			Hook(region, setter)
		elseif a then
			first[8] = a
		end
		local tint = tints[unitFrame]
		if not (tint and tint[part]) then
			return
		end
		local br, bg, bb = Blend(first[1], first[2], first[3], tint, part)
		painting = true
		SetColour(region, setter, br, bg, bb, a)
		painting = false
	end

	-- A frame's textures, from its GetRegions (no table: this runs each frame).
	local function PaintRegions(unitFrame, child, ...)
		if not child then
			return
		end
		if child:GetObjectType() == "Texture" then
			Paint(child, "GetVertexColor", "SetVertexColor", unitFrame, "border")
		end
		return PaintRegions(unitFrame, ...)
	end

	-- The border's textures (Forever's is a frame of them round the bar).
	local function PaintBorder(unitFrame)
		for _, field in ipairs(BORDER_FIELDS) do
			local region = Field(unitFrame, field)
			if Usable(region) and region.GetObjectType then
				if region:GetObjectType() == "Texture" then
					Paint(region, "GetVertexColor", "SetVertexColor", unitFrame, "border")
				elseif region.GetRegions then
					PaintRegions(unitFrame, region:GetRegions())
				end
			end
		end
	end

	local painter = CreateFrame("Frame")
	painter:Hide()
	painter:SetScript("OnUpdate", ns.Profiled("Target colors", function()
		for unitFrame, tint in pairs(tints) do
			if Usable(unitFrame) then
				if tint.name then
					if Usable(unitFrame.name) then
						Paint(unitFrame.name, "GetTextColor", "SetTextColor", unitFrame, "name")
					end
					local text = texts[unitFrame]
					if text and text.baseR then
						local alpha = text:GetAlpha()
						text:SetTextColor(Blend(text.baseR, text.baseG, text.baseB, tint, "name"))
						text:SetAlpha(alpha)
					end
				end
				if tint.bar and Usable(unitFrame.healthBar) then
					Paint(unitFrame.healthBar, "GetStatusBarColor", "SetStatusBarColor", unitFrame, "bar")
				end
				if tint.border then
					PaintBorder(unitFrame)
				end
			end
		end
	end))

	-- A plate's colors given back as they were.
	local function Untint(unitFrame)
		painting = true
		for region, first in pairs(saved) do
			if first[6] == unitFrame then
				local _, _, _, a = ReadColour(region, first[4])
				SetColour(region, first[5], first[1], first[2], first[3], a)
				saved[region] = nil
			end
		end
		painting = false
		local text = texts[unitFrame]
		if text and text.baseR then
			local alpha = text:GetAlpha()
			text:SetTextColor(text.baseR, text.baseG, text.baseB)
			text:SetAlpha(alpha)
		end
		tints[unitFrame] = nil
		if not next(tints) then
			painter:Hide()
		end
	end

	local TINT_PARTS = { "name", "bar", "border" }
	function TintTarget(plate, level, unit, kinds)
		local unitFrame = plate.UnitFrame
		if not Usable(unitFrame) then
			return
		end
		if not (kinds and level > 0) then
			kinds = {}
		end
		local tint = tints[unitFrame]
		if not (kinds.name or kinds.bar or kinds.border) then
			if tint then
				Untint(unitFrame)
			end
			return
		end
		-- (A part going back to the game's: the old colors back first.)
		if tint then
			for _, part in ipairs(TINT_PARTS) do
				if tint[part] and not kinds[part] then
					Untint(unitFrame)
					tint = nil
					break
				end
			end
		end
		tint = tint or {}
		tints[unitFrame] = tint
		tint.level = level
		for _, part in ipairs(TINT_PARTS) do
			local kind = kinds[part]
			tint[part] = kind and { PlateColour(unit, kind) } or nil
		end
		painter:Show()
	end
end

-- Whether a unit is after you: you have its aggro, or it's fighting you and
-- has you targeted (no threat list: a player, say).
local function OnYou(unit)
	local ok, status = pcall(UnitThreatSituation, "player", unit)
	if ok and Known(status) and type(status) == "number" then
		return status >= 2
	end
	return Ask(UnitCanAttack, "player", unit) and Ask(UnitAffectingCombat, unit)
		and Ask(UnitIsUnit, unit .. "target", "player")
end

-- The aggro rows, on any enemy plate in a fight, by their letters (Core's
-- MARK_AGGRO_FLAGS): who it's after, y you (aggro: Aggro on you) or o someone
-- friendly that isn't you (a group member, a pet or another player: its
-- target), and that one's role, t tank, h healer or d DPS (a player with
-- none set: DPS; a pet just with all three ticked).
local function AggroFits(flags, unit)
	if not (unit and Ask(UnitCanAttack, "player", unit)) then
		return false
	end
	local victim = OnYou(unit) and "player" or nil
	if not victim and flags:find("o", 1, true) and Ask(UnitAffectingCombat, unit) then
		local target = unit .. "target"
		if Ask(UnitExists, target) and Ask(UnitIsFriend, "player", target) and not Ask(UnitIsUnit, target, "player") then
			victim = target
		end
	end
	if not victim or not flags:find(victim == "player" and "y" or "o", 1, true) then
		return false
	end
	if flags:find("t", 1, true) and flags:find("h", 1, true) and flags:find("d", 1, true) then
		return true
	end
	local role
	if victim == "player" then
		role = ns.PlayerRole()
	elseif Ask(UnitIsPlayer, victim) then
		local ok, assigned = pcall(UnitGroupRolesAssigned, victim)
		role = ok and Known(assigned) and assigned or nil
	else
		return false -- (a pet)
	end
	return flags:find(role == "TANK" and "t" or role == "HEALER" and "h" or "d", 1, true) ~= nil
end
local AGGRO_ROWS = ns.MARK_AGGRO_FLAGS

-- Whether a plate is a unit's (pcall: a token a client lacks).
local function PlateOf(token, plate)
	local ok, found = pcall(C_NamePlate.GetNamePlateForUnit, token)
	return ok and found ~= nil and found == plate
end

-- The Style hub's Nameplates page's rows in the order a plate tries them:
-- the markOrder setting, each row once (Core's MarkRowValid), Default's added
-- rows after the rest. Default's own, always last, isn't in it.
local markOrderText, markOrder
local function MarkOrder()
	local text = Style("markOrder")
	if text ~= markOrderText or not markOrder then
		markOrderText, markOrder = text, {}
		local seen, last = {}, {}
		for kind in tostring(text or ""):gmatch("[^,]+") do
			if ns.MarkRowValid(kind) and not seen[kind] then
				seen[kind] = true
				if ns.MarkRowBase(kind) == "others" then
					last[#last + 1] = kind
				else
					markOrder[#markOrder + 1] = kind
				end
			end
		end
		for _, kind in ipairs(last) do markOrder[#markOrder + 1] = kind end
	end
	return markOrder
end
ns.TargetMarkOrder = MarkOrder

-- Whether each row fits now, as the page's When grid says (see Core's
-- MARK_WHEN_WORDS): kind -> false while it doesn't, worked out by UpdateWhen
-- (twice a second, and as settings change), facts asked only for a row set
-- to more than Always.
local WHEN_ROLES = { "tankHide", "healerHide", "damageHide" }
local whenNow = {}
-- (A row's When setting: as its other settings, its kind's while it hasn't one.)
local function WhenStyle(kind, suffix)
	local value = Style(kind .. "When" .. suffix)
	if value == nil then
		local parent = MarkParent(kind)
		if parent then return WhenStyle(parent, suffix) end
	end
	return value
end
local function WhenSet(kind)
	local key, db = kind .. "When", ns.db
	if not WhenStyle(kind, "") or (db.frameRules and db.frameRules[key]) then
		return true
	end
	for _, list in ipairs(WHEN_ROLES) do
		if ns.RoleHidden(db, list, key) then return true end
	end
	return false
end
local function WhenFits(kind, facts)
	local key = kind .. "When"
	local list = facts.tank and "tankHide" or facts.healer and "healerHide" or facts.damage and "damageHide"
	if list and ns.RoleHidden(ns.db, list, key) then
		return false
	end
	local rule = ns.RuleShows(key, facts)
	if rule ~= nil then
		return rule
	end
	if WhenStyle(kind, "") then
		return true
	end
	for _, word in ipairs(ns.MARK_WHEN_WORDS) do
		if WhenStyle(kind, word[2]) and facts[ns.RULE_WORDS[word[1]]] then return true end
	end
	return false
end
-- (Gives whether any row's changed.)
local function UpdateWhen()
	if not ns.db then
		return false
	end
	local facts, changed
	local function Look(kind)
		local fits = true
		if WhenSet(kind) then
			facts = facts or (ns.RuleFactsNow and ns.RuleFactsNow())
			fits = not facts or WhenFits(kind, facts)
		end
		if (whenNow[kind] ~= false) ~= fits then changed = true end
		whenNow[kind] = fits
	end
	for _, kind in ipairs(MarkOrder()) do Look(kind) end
	Look("others")
	return changed
end
ns.TargetMarkFits = function(kind) return whenNow[kind] ~= false end

-- Whether Default's row changes every other plate from the game's
-- look: shown, with a mark, an Also color or an opacity.
local function OthersOn(kind)
	kind = kind or "others"
	return ArrowSetting("Show", kind) and (ArrowSetting("Style", kind) ~= "none"
		or AlsoOn("ColorName", kind) or AlsoOn("ColorBar", kind)
		or (ArrowSetting("Alpha", kind) or 1) < 1
		or ns.isRetail and (math.abs((ArrowSetting("PlateWidth", kind) or 1) - 1) > 0.001
			or math.abs((ArrowSetting("PlateHeight", kind) or 1) - 1) > 0.001)) and true or false
end

-- How a unit stands with you, for the rows added for one reaction: "Enemy",
-- "Neutral" or "Friendly"; nil when the game won't say.
local function UnitStanding(unit)
	local ok, reaction = pcall(UnitReaction, unit or "", "player")
	if not (ok and Known(reaction) and type(reaction) == "number") then
		return nil
	end
	return reaction >= 5 and "Friendly" or reaction == 4 and "Neutral" or "Enemy"
end

-- The Style hub's Nameplates page's row a plate goes by now: the first, in
-- their order, that's on, its When saying now, and the plate its: your
-- target's, focus's or mouseover's; any enemy's after you or the rest (the
-- aggro rows); a living NPC's by rank (Normal NPC, Elite NPC) or any (NPC);
-- a player's or minion's as the Nameplates page sorts them (Effects'
-- PlateKind); any unit's (Any unit); and for a row with a Who or a
-- Distance, only those units. The rows below it aren't asked. None
-- fitting: Default's while it's changed from the game's (a mark, an Also
-- color or an opacity); else nil, the game's look.
local mouseoverPlate -- (the plate with the mouseover mark: see mouseoverWatch)
local RANK_LETTERS = { normal = "n", elite = "e" }
local PLATE_KIND_ROWS = { Enemies = { "p", "Enemy" }, Friends = { "p", "Friendly" },
	EnemyMinions = { "m", "Enemy" }, FriendlyMinions = { "m", "Friendly" } }
-- (From the row at start on, for the rows below one: returns the row and
-- its place in the order, none for Default's own.)
local function FittingRow(plate, unit, start)
	local standing, asked, plateKind, kindAsked, rank, rankAsked
	local order = MarkOrder()
	for i = start or 1, #order do
		local kind = order[i]
		local base, reaction, _, distance = ns.MarkRowBase(kind)
		if whenNow[kind] ~= false and ArrowSetting("Show", kind) then
			local fits
			if AGGRO_ROWS[base] then
				fits = AggroFits(AGGRO_ROWS[base], unit)
			elseif base == "others" then
				fits = OthersOn(kind)
			elseif base == "all" then
				fits = unit ~= nil
			elseif ns.MARK_UNIT_FLAGS[base] then
				-- (Living NPCs by rank, players and minions as the Nameplates
				-- page sorts them: friend or foe as it has them, just now.)
				local flags = ns.MARK_UNIT_FLAGS[base]
				fits = false
				if flags:find("[ne]") then
					if not rankAsked then
						rank, rankAsked = ns.NPCRank and ns.NPCRank(unit), true
					end
					fits = rank ~= nil and flags:find(RANK_LETTERS[rank] or "-", 1, true) ~= nil
				end
				if not fits and flags:find("[pm]") then
					if not kindAsked then
						plateKind, kindAsked = unit and ns.PlateKindOf and ns.PlateKindOf(unit), true
					end
					local sort = PLATE_KIND_ROWS[plateKind or ""]
					fits = sort ~= nil and flags:find(sort[1], 1, true) ~= nil
						and (not reaction or reaction:find(sort[2], 1, true) ~= nil)
					if fits then reaction = nil end
				end
			else
				fits = PlateOf(base, plate)
			end
			if fits and reaction then
				if not asked then
					standing, asked = UnitStanding(unit), true
				end
				fits = standing ~= nil and reaction:find(standing, 1, true) ~= nil
			end
			if fits and distance then
				fits = unit ~= nil and ns.UnitInBand and ns.UnitInBand(unit, distance) == true
			end
			if fits then return kind, i end
		end
	end
	if whenNow.others ~= false and OthersOn() then
		return "others"
	end
end

-- A plate's look from the row it goes by (all of it, that row's): the row
-- its mark is (nil for none), each part's (name, bar, border: as TintKind
-- has it, while its plate color ticks it: kinds), whether it's the mouseover
-- row's, its opacity (below 100%) and its size (not 100%). Its plate color
-- "-": the parts as the next row that fits says, and so on down (Default's
-- own last); the game's: none.
local partKinds = {}
local PART_KEYS = { name = "ColorName", bar = "ColorBar", border = "ColorBorder" }
-- (The page's own Width and Height, every plate's: 1, 1 for none.)
local function MasterSize()
	return Style("plateStyleWidth") or 1, Style("plateStyleHeight") or 1
end
local function MasterSizeOn()
	local width, height = MasterSize()
	return ns.isRetail and (math.abs(width - 1) > 0.001 or math.abs(height - 1) > 0.001)
end
local function PlateLook(plate, unit)
	wipe(partKinds)
	local kind, at = FittingRow(plate, unit)
	local masterWidth, masterHeight = MasterSize()
	if not kind then
		return nil, partKinds, false, nil, MasterSizeOn() and { width = masterWidth, height = masterHeight } or nil
	end
	local mark = ArrowSetting("Style", kind) ~= "none" and kind or nil
	local alpha = ArrowSetting("Alpha", kind) or 1
	local width = (ArrowSetting("PlateWidth", kind) or 1) * masterWidth
	local height = (ArrowSetting("PlateHeight", kind) or 1) * masterHeight
	local colorRow = kind
	while colorRow do
		local tintKind = TintKind(colorRow)
		local how = PlateHow(tintKind)
		if how ~= "-" then
			if how ~= "game" then
				for part, key in pairs(PART_KEYS) do
					if ArrowSetting(key, tintKind) then
						partKinds[part] = tintKind
					end
				end
			end
			break
		end
		if not at then break end
		colorRow, at = FittingRow(plate, unit, at + 1)
	end
	return mark, partKinds, ns.MarkRowBase(kind) == "mouseover", alpha < 1 and alpha or nil,
		(math.abs(width - 1) > 0.001 or math.abs(height - 1) > 0.001) and { width = width, height = height } or nil
end

-- Each plate's opacity from its rows (below 1 only), for Effects' plate
-- alpha: CineMode's fade times this. Eased in and out with the Target
-- Indicator row (level); a change has Effects set the plate's alpha again.
local opacities = {}
function ns.PlateStyleOpacity(plate)
	return plate and opacities[plate] or 1
end
-- (Whether a row that fits plates by what they are, not one unit's (your
-- target's, focus's, mouseover's), is on: a new plate is looked at for it.)
local UNIT_ROWS = { target = true, focus = true, mouseover = true }
local function TypeRowsOn()
	for _, kind in ipairs(MarkOrder()) do
		local base = ns.MarkRowBase(kind)
		if base == "others" and OthersOn(kind) or not UNIT_ROWS[base] and base ~= "others"
			and ArrowSetting("Show", kind) then
			return true
		end
	end
	return false
end
-- (Whether an aggro row is on the grid and shown: plates looked at as
-- enemies change who they're after.)
local function AggroRowsOn()
	for _, kind in ipairs(MarkOrder()) do
		if AGGRO_ROWS[ns.MarkRowBase(kind)] and ArrowSetting("Show", kind) and whenNow[kind] ~= false then
			return true
		end
	end
	return false
end
-- (Whether a row with a Distance is: plates looked at again as units come
-- and go.)
local function DistanceRowsOn()
	for _, kind in ipairs(MarkOrder()) do
		if select(4, ns.MarkRowBase(kind)) and ArrowSetting("Show", kind) and whenNow[kind] ~= false then
			return true
		end
	end
	return false
end
-- Each plate's size from its rows (retail: Forever's plates don't size):
-- its own width and height times the row's Width and Height. Retail's
-- plates won't say where their parts are, but Blizzard's layout is known
-- (NamePlateUnitFrameMixin:UpdateAnchors): the cast bar container's held
-- in from the unit frame's bottom corners by the plate's inset, the health
-- bar container sits on it as wide, its height set, and the name, debuffs,
-- raid mark, level and border hang off that. So the width's the cast bar
-- container's inset (more in, narrower; less, wider, about its middle),
-- the height the health bar container's (growing up off the cast bar, the
-- name and debuffs riding on top), and everything follows. Its own put
-- back after: the inset from the widths (they can be read), the height.
-- [health bar container] = { inset, width, height, cast bar container,
-- unit frame, plate } while ours is on; nows.width/height[plate] = ours on
-- it now (nil: its own).
local ownSizes, nows = {}, { width = {}, height = {} }
local function Number(ok, value)
	return ok and type(value) == "number" and Known(value) and value or nil
end
-- (reanchoring: while we lay it out, our UpdateAnchors hook leaves it be.)
local reanchoring, reanchorHooked = false, {}
-- (Why a plate isn't sized, for /cine debug marks: [plate] = reason.)
local sizeSkipped = {}
local function SetInset(cast, unitFrame, inset)
	pcall(cast.ClearAllPoints, cast)
	pcall(cast.SetPoint, cast, "BOTTOMLEFT", unitFrame, "BOTTOMLEFT", inset, 0)
	pcall(cast.SetPoint, cast, "BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", -inset, 0)
end
local function ReanchorSized(bar, own, width, height)
	reanchoring = true
	SetInset(own.cast, own.frame, own.inset + own.width * (1 - width) / 2)
	pcall(bar.SetHeight, bar, own.height * height)
	reanchoring = false
end
local function RestoreSize(bar, own)
	reanchoring = true
	SetInset(own.cast, own.frame, own.inset)
	pcall(bar.SetHeight, bar, own.height)
	reanchoring = false
end
-- (Its own: the widths and height now, the inset from them; nil and why
-- while it's not laid out yet or isn't retail's layout.)
local function SizeOwn(plate, unitFrame, bar)
	local cast = unitFrame.CastBarsContainer
	if not Usable(cast) then
		return nil, "no cast bar container"
	end
	local frameWidth = Number(pcall(unitFrame.GetWidth, unitFrame))
	local castWidth = Number(pcall(cast.GetWidth, cast))
	local ownWidth, ownHeight = Number(pcall(bar.GetWidth, bar)), Number(pcall(bar.GetHeight, bar))
	if not (frameWidth and castWidth and ownWidth and ownHeight and ownWidth > 0 and ownHeight > 0) then
		return nil, "no size yet"
	end
	if math.abs(castWidth - ownWidth) > 0.5 then
		return nil, ("health bar %s wide, cast bar %s: not the layout we know"):format(ownWidth, castWidth)
	end
	return { inset = (frameWidth - castWidth) / 2, width = ownWidth, height = ownHeight, cast = cast,
		frame = unitFrame, plate = plate }
end
-- (The quest mark's spot goes by the bar's width, not its edge: put in it
-- again as the bar changes, each step of the way. The class and role icons
-- hang off the bar's left edge and go with it.)
local function FollowSize(plate)
	local icon = questIcons[plate]
	if icon and icon:IsShown() then
		RefreshQuestIcon(plate)
	end
end
local function ApplySize(plate)
	local unitFrame = plate and plate.UnitFrame
	local bar = unitFrame and unitFrame.HealthBarsContainer
	if not (Usable(unitFrame) and Usable(bar)) then
		return
	end
	local width, height = nows.width[plate] or 1, nows.height[plate] or 1
	local own = ownSizes[bar]
	if math.abs(width - 1) < 0.001 and math.abs(height - 1) < 0.001 then
		nows.width[plate], nows.height[plate], sizeSkipped[plate] = nil, nil, nil
		if own then
			ownSizes[bar] = nil
			RestoreSize(bar, own)
			FollowSize(plate)
		end
		return
	end
	if not own then
		-- (Not laid out yet, or no way to: left as it is, tried again on the
		-- next look.)
		local why
		own, why = SizeOwn(plate, unitFrame, bar)
		sizeSkipped[plate] = why
		if not own then
			return
		end
		ownSizes[bar] = own
	end
	ReanchorSized(bar, own, width, height)
	FollowSize(plate)
	-- (The game laying the plate out again (its options changed): its own
	-- taken again from what it just set, then ours on it.)
	if not reanchorHooked[unitFrame] and unitFrame.UpdateAnchors then
		reanchorHooked[unitFrame] = true
		pcall(hooksecurefunc, unitFrame, "UpdateAnchors", function(self)
			local container = self.HealthBarsContainer
			local mine = container and ownSizes[container]
			if mine and not reanchoring then
				local fresh = SizeOwn(mine.plate, self, container)
				if fresh then
					ownSizes[container] = fresh
					mine = fresh
				end
				ReanchorSized(container, mine, nows.width[mine.plate] or 1, nows.height[mine.plate] or 1)
			end
		end)
	end
end
local function ApplyOpacity(plate, opacity)
	if opacity and opacity >= 0.999 then
		opacity = nil
	end
	if opacities[plate] ~= opacity then
		opacities[plate] = opacity
		if ns.RefreshPlateAlpha then ns.RefreshPlateAlpha(plate) end
	end
end

-- A plate's opacity and size don't jump to a new row's: they move toward
-- it, a whole 100% in the page's Change time (plateStyleFadeTime), turning
-- back from wherever they are if it changes again (the elite rules, a
-- camera turned from the elite and back). A plate just come starts at its
-- own (settled: [plate] = true once it has).
local goals = { opacity = {}, width = {}, height = {} }
local settled = {}
local easer = CreateFrame("Frame")
easer:Hide()
easer:SetScript("OnUpdate", function(self, elapsed)
	local time = Style("plateStyleFadeTime") or 1.5
	local step = time > 0 and elapsed / time or 1
	for plate, goal in pairs(goals.opacity) do
		local now = opacities[plate] or 1
		local value = now < goal and math.min(goal, now + step) or math.max(goal, now - step)
		ApplyOpacity(plate, value)
		if value == goal then goals.opacity[plate] = nil end
	end
	for what, list in pairs(nows) do
		for plate, goal in pairs(goals[what]) do
			local now = list[plate] or 1
			local value = now < goal and math.min(goal, now + step) or math.max(goal, now - step)
			list[plate] = value
			ApplySize(plate)
			if value == goal then goals[what][plate] = nil end
		end
	end
	if not (next(goals.opacity) or next(goals.width) or next(goals.height)) then
		self:Hide()
	end
end)
-- (What, its value now and the goal, 1 for none; jump: there at once.)
local function MoveTo(what, plate, now, goal, jump)
	if jump or math.abs(now - goal) < 0.001 then
		goals[what][plate] = nil
		if what == "opacity" then
			ApplyOpacity(plate, goal)
		else
			nows[what][plate] = goal
			ApplySize(plate)
		end
		return
	end
	goals[what][plate] = goal
	easer:Show()
end
local function SetPlateSize(plate, size, level, jump)
	if not ns.isRetail then
		return
	end
	for what, list in pairs(nows) do
		local goal = size and size[what]
		MoveTo(what, plate, list[plate] or 1, goal and level > 0 and 1 - level * (1 - goal) or 1, jump)
	end
end
local function SetPlateOpacity(plate, opacity, level, jump)
	MoveTo("opacity", plate, opacities[plate] or 1, opacity and level > 0 and 1 - level * (1 - opacity) or 1, jump)
end
-- (A plate gone: its own size back, nothing left moving.)
local function ForgetPlateLook(plate)
	goals.opacity[plate], goals.width[plate], goals.height[plate], settled[plate] = nil, nil, nil, nil
	nows.width[plate], nows.height[plate] = nil, nil
	ApplySize(plate)
	opacities[plate] = nil
end

-- The mouse leaving a unit has no event: while a plate has the mouseover
-- mark, looked at now and then to see it's still the mouse's.
local MOUSEOVER_CHECK = 0.1
local mouseoverWatch = CreateFrame("Frame")
mouseoverWatch:Hide()

-- Shows or hides a plate's mark and colors as the rows that fit it say.
local function RefreshTargetArrow(plate)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	-- (None while the Style hub's Nameplates page is switched off.)
	local level = plate ~= PersonalPlate() and Style("handlePlateStyle") and levels.TargetArrow or 0
	local kind, kinds, hovered, opacity, size
	if level > 0 then
		kind, kinds, hovered, opacity, size = PlateLook(plate, unit)
	end
	local jump = not settled[plate]
	settled[plate] = true
	SetPlateOpacity(plate, opacity, level, jump)
	SetPlateSize(plate, size, level, jump)
	if hovered then
		mouseoverPlate = plate
		mouseoverWatch:Show()
	elseif mouseoverPlate == plate then
		mouseoverPlate = nil
	end
	local arrow = arrows[plate]
	-- (Its own colors, each part in its row's, as their Also colors say.)
	TintTarget(plate, level, unit, kinds)
	if not kind then
		level = 0
	end
	if level <= 0 then
		if arrow then
			arrow:Hide()
			arrow.styled = false -- (styled again for its next unit)
		end
		return
	end
	arrow = TargetArrow(plate)
	if arrow then
		if arrow.styled ~= kind then
			StyleArrow(arrow, unit, kind)
		end
		-- (At its own opacity: Opacity, the mark's; Alpha is the plate's.)
		arrow:SetAlpha(level * (ArrowSetting("Opacity", kind) or 1))
		arrow:Show()
	end
end

-- /cine debug marks: each plate's mark now, and why it sits where it does
-- (the Height setting, how much of the plate shows and from what, where the
-- mark over the plate ended up).
function ns.ReportTargetMarks()
	local function Num(value)
		if type(value) ~= "number" then return tostring(value) end
		return Known(value) and ("%.2f"):format(value) or "secret"
	end
	ns.Print(("marks: client %s, combat %s, page %s, Target Indicator row %s, Height %s (no plate %s), target %s"):format(
		ns.isRetail and "retail" or "forever", tostring(InCombatLockdown()),
		Style("handlePlateStyle") and "on" or "off", Num(levels.TargetArrow),
		tostring(Style("targetArrowY")), tostring(Style("targetArrowBareY")), tostring(UnitExists("target"))))
	-- (The game's Show Offscreen Nameplates: the elite rules see only plates.)
	local on, off = ns.OFFSCREEN_PLATE_CVARS, ns.NO_OFFSCREEN_PLATE_CVARS
	ns.Print(("  offscreen plates: game setting %s, held by CineMode %s, page tick %s, yours saved %s"):format(
		tostring(GetCVar("nameplateShowOffscreen")),
		on and on.active and "on" or off and off.active and "off" or "no", tostring(Style("plateShowOffscreen")),
		tostring(ns.db.savedCVars and ns.db.savedCVars.nameplateShowOffscreen)))
	-- (Each row's When now, top to bottom.)
	local when = {}
	for _, kind in ipairs(MarkOrder()) do
		when[#when + 1] = kind .. (whenNow[kind] == false and " no" or " yes")
	end
	ns.Print("  order and fits now: " .. table.concat(when, ", ") .. ", others "
		.. (whenNow.others == false and "no" or "yes") .. (OthersOn() and " (changed)" or " (the game's)"))
	local any = false
	for plate, arrow in pairs(arrows) do
		if arrow:IsShown() then
			any = true
			local okAlpha, alpha = pcall(plate.GetAlpha, plate)
			local okHigh, high = pcall(arrow.GetHeight, arrow)
			-- (Where it ended up can't be asked on retail: its plate is restricted.)
			local okPoint, _, _, _, x, y = pcall(arrow.over.GetPoint, arrow.over, 1)
			if not okPoint then
				x, y = "restricted", ""
			end
			local okTop, top = pcall(arrow.over.GetTop, arrow.over)
			local okBarTop, barTop = pcall(arrow.GetTop, arrow)
			-- (Any frame it's in that cuts off what's drawn outside it: a mark
			-- moved below the plate went missing.)
			local clips, frame = {}, arrow
			while frame do
				local okClip, clip = pcall(frame.DoesClipChildren, frame)
				if okClip and clip then
					local okName, name = pcall(frame.GetDebugName, frame)
					clips[#clips + 1] = okName and tostring(name) or "?"
				end
				frame = frame:GetParent()
			end
			ns.Print("    clipped by: " .. (#clips > 0 and table.concat(clips, ", ") or "nothing"))
			local unitFrame = plate.UnitFrame
			local bar = unitFrame and (unitFrame.HealthBarsContainer or unitFrame.healthBar)
			local function Alpha(frame)
				if not frame then return "none" end
				local okOwn, own = pcall(frame.GetAlpha, frame)
				return Num(okOwn and own or nil) .. "/" .. Num(Opacity(frame))
			end
			ns.Print(("    game draws: bar %s, name %s; eased showing %s; alpha own/effective: plate %s, " ..
				"unit frame %s, bar %s, name %s"):format(
				tostring(unitFrame and Seen(bar)), tostring(unitFrame and Seen(unitFrame.name)), Num(arrow.showing),
				Alpha(plate), Alpha(unitFrame), Alpha(bar), Alpha(unitFrame and unitFrame.name)))
			ns.Print(("  %s (%s): style %s, overY %s, showing %s = alpha %s x max(health %s, name %s) x body %s; " ..
				"name alone %s, sight %s; bar height %s; mark at %s, %s; mark top %s over bar top %s"):format(
				tostring(arrow.styled), tostring(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)),
				tostring(ArrowSetting("Style", arrow.styled)),
				Num(arrow.overY), Num(PlateShowing(plate)), okAlpha and Num(alpha) or "error",
				Num(levels.Health), Num(levels.Name), Num(bodyShare[plate] or 1), Num(nameShare[plate]),
				Num(sight[plate]), okHigh and Num(high) or "error",
				Num(x), Num(y), okTop and Num(top) or "error", okBarTop and Num(barTop) or "error"))
		end
	end
	if not any then
		ns.Print("  no mark showing: target, focus or hover a unit first")
	end
	-- (Each plate's size: the row it goes by and its Width and Height, the
	-- health bar container's size now and its own, the cast bar container's
	-- width and its inset now (own: the game's), or why it's not sized.)
	ns.Print(("  page Width %s Height %s (every plate's)"):format(Num(Style("plateStyleWidth")),
		Num(Style("plateStyleHeight"))))
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unitFrame = plate.UnitFrame
		local unit = plate.namePlateUnitToken or (unitFrame and unitFrame.unit)
		local row = (levels.TargetArrow or 0) > 0 and unit and FittingRow(plate, unit)
		local bar = unitFrame and unitFrame.HealthBarsContainer
		local cast = unitFrame and unitFrame.CastBarsContainer
		local own = bar and ownSizes[bar]
		local width, height = Number(pcall(bar and bar.GetWidth or error, bar)), Number(pcall(bar and bar.GetHeight or error, bar))
		local frameWidth = Number(pcall(unitFrame and unitFrame.GetWidth or error, unitFrame))
		local castWidth = Number(pcall(cast and cast.GetWidth or error, cast))
		ns.Print(("  size %s: row %s, its Width %s Height %s; bar %sx%s, own %s, cast bar %s inset %s (own %s), ours %s/%s%s%s"):format(
			tostring(unit), tostring(row), row and Num(ArrowSetting("PlateWidth", row)) or "-",
			row and Num(ArrowSetting("PlateHeight", row)) or "-", Num(width), Num(height),
			own and (Num(own.width) .. "x" .. Num(own.height)) or "-", Num(castWidth),
			frameWidth and castWidth and Num((frameWidth - castWidth) / 2) or "-", own and Num(own.inset) or "-",
			Num(nows.width[plate]), Num(nows.height[plate]),
			sizeSkipped[plate] and ", not sized: " .. sizeSkipped[plate] or "",
			ns.isRetail and "" or " (Forever: not sized)"))
	end
end

-- Every plate's mark looked at again (a new target, focus or mouseover).
local function RefreshMarks()
	if (levels.TargetArrow or 0) > 0 or next(arrows) or next(tints) or next(opacities) or next(ownSizes) then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			RefreshTargetArrow(plate)
		end
	end
end

-- The When grid's rows looked at twice a second, the marks again as one
-- starts or stops fitting (a fight starting, a zone changing...).
local WHEN_CHECK = 0.5
local whenAt = 0
CreateFrame("Frame"):SetScript("OnUpdate", function()
	local now = GetTime()
	if now < whenAt then
		return
	end
	whenAt = now + WHEN_CHECK
	-- (The aggro rows too: an enemy joining a fight has no event of its own;
	-- and the rows with a Distance: none for moving either.)
	if (levels.TargetArrow or 0) > 0 and (UpdateWhen() or AggroRowsOn() or DistanceRowsOn()) then
		RefreshMarks()
	end
end)

local mouseoverAt = 0
mouseoverWatch:SetScript("OnUpdate", function(self)
	local now = GetTime()
	if now < mouseoverAt then
		return
	end
	mouseoverAt = now + MOUSEOVER_CHECK
	if not mouseoverPlate then
		self:Hide()
	elseif not PlateOf("mouseover", mouseoverPlate) then
		RefreshTargetArrow(mouseoverPlate)
	end
end)

-- After a change on the Target Indicator page: the arrows styled anew.
function ns.RefreshTargetArrows()
	UpdateWhen()
	for _, arrow in pairs(arrows) do
		arrow.styled = false
	end
	RefreshMarks()
end

-- A plate's icons (the role icon goes by where the class icon is).
function ns.RefreshClassIcon(plate)
	RefreshClass(plate)
	RefreshRoleIcon(plate)
	RefreshQuestIcon(plate)
	RefreshTargetArrow(plate)
end

local function RefreshClassIcons()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			ns.RefreshClassIcon(plate)
		end
	end
end

local function AnyClassIcons()
	for _, part in ipairs(ns.PLATE_ICON_PARTS) do
		if (levels[part] or 0) > 0 then
			return true
		end
	end
	return false
end

-- A plate given a new unit takes the parts' alphas (or lets go of its last
-- unit's), and its class and role icons. One whose player changes sides (a
-- duel starting) swaps icon rows; roles are read again when the group changes.
local SELF_UNITS = { player = true, target = true, focus = true, mouseover = true }
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
watcher:RegisterEvent("UNIT_FACTION")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
watcher:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
watcher:RegisterEvent("UNIT_TARGET")
-- (Not every client has these.)
pcall(watcher.RegisterEvent, watcher, "PLAYER_ROLES_ASSIGNED")
pcall(watcher.RegisterEvent, watcher, "PLAYER_FOCUS_CHANGED")
watcher:SetScript("OnEvent", function(_, event, unit)
	if not (ns.db and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return
	end
	if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
		wipe(plateRole)
		if (levels.TargetArrow or 0) > 0 and AggroRowsOn() then
			RefreshMarks() -- (Aggro on non-tank: who's the tank)
		end
		if AnyClassIcons() or next(roleIcons) then
			RefreshClassIcons()
		end
		return
	end
	-- (The marks move to the new target's, focus's or mouseover's plate.)
	if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
		RefreshMarks()
		return
	end
	-- (Your target coming after you, or leaving off: its mark to aggro's and back.)
	-- (Who an enemy's after changing: the aggro rows' plates looked at again,
	-- an enemy's own when it picks a new target, every plate when threat moves.)
	if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_TARGET" then
		if (levels.TargetArrow or 0) > 0 and AggroRowsOn() and type(unit) == "string" then
			if unit:find("^nameplate") then
				RefreshTargetArrow(C_NamePlate.GetNamePlateForUnit(unit))
			elseif SELF_UNITS[unit] then
				RefreshMarks()
			end
			-- (A group member's own: not every plate for each, dozens a second
			-- in a raid. Aggro goes by the enemy's target, its plate's event,
			-- and the When check's twice a second catches the rest.)
		end
		return
	end
	if event == "UNIT_FACTION" and not (type(unit) == "string" and unit:find("^nameplate")) then
		return
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end
	if event == "NAME_PLATE_UNIT_REMOVED" then
		plateClass[plate], plateRole[plate] = nil, nil
		bodyShare[plate], nameShare[plate], markShare[plate] = nil, nil, nil
		bandOf[plate], farChecked[plate], farSince[plate], swaps[plate] = nil, nil, nil, nil
		sight[plate] = nil
		if Usable(plate.UnitFrame) then
			CentreName(plate.UnitFrame, false)
			OwnName(plate, nil)
		end
		if icons[plate] then
			icons[plate]:Hide()
		end
		if roleIcons[plate] then
			roleIcons[plate]:Hide()
		end
		if questIcons[plate] then
			questIcons[plate]:Hide()
		end
		if arrows[plate] then
			arrows[plate]:Hide()
			arrows[plate].styled = false
		end
		TintTarget(plate, 0)
		ForgetPlateLook(plate)
		return
	end
	plateClass[plate], plateRole[plate] = nil, nil
	if AnyClassIcons() or icons[plate] or roleIcons[plate] or questIcons[plate] or arrows[plate]
		or opacities[plate] or nows.width[plate] or nows.height[plate]
		or ((levels.TargetArrow or 0) > 0 and (OthersOn() or TypeRowsOn() or MasterSizeOn())) then
		ns.RefreshClassIcon(plate)
	end
	-- (Looked at or not, a plate's settled now: from here on it moves.)
	settled[plate] = true
	if event == "NAME_PLATE_UNIT_ADDED" and AnyFaded() then
		ApplyPlate(plate, PersonalPlate())
	end
end)

-- From Effects, with each plate's alpha: how much of it the plate's parts
-- other than the name get (body, 0 to 1) and the name at least (name), for a
-- plate held up for its name alone (Names rows: see Effects' nameLevel).
function ns.SetPlateBody(plate, body, name, mark)
	if not plate then
		return
	end
	body = body < 1 and body or nil
	name = name > 0 and name or nil
	mark = mark and mark > 0 and mark or nil
	if bodyShare[plate] == body and nameShare[plate] == name and markShare[plate] == mark then
		return
	end
	bodyShare[plate], nameShare[plate], markShare[plate] = body, name, mark
	-- (A name first kept up: its band straight away, no swap.)
	if FAR_USED and name and not farChecked[plate] then
		farChecked[plate] = true
		bandOf[plate] = Band(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
	end
	if name then
		ns.WatchFarNames()
	end
	ApplyPlate(plate, PersonalPlate())
	if AnyClassIcons() or icons[plate] or roleIcons[plate] or questIcons[plate] or mark
		or (ns.QuestMarkLevel and ns.QuestMarkLevel() > 0) then
		ns.RefreshClassIcon(plate)
	end
end

-- Each frame while names show alone: names out of sight faded, swaps
-- under way faded, names sized anew as the camera zooms (Forever), and every
-- FAR_CHECK our texts' words and colours looked at again (a unit changing
-- sides, a name read late) and, on Forever, each name-only plate's band.
-- Only plates showing nothing but the name (a target's filling in has its
-- own crossfade).
local farWatch = CreateFrame("Frame")
farWatch:Hide()
local farCheckAt = 0
farWatch:SetScript("OnUpdate", ns.Profiled("Plate names", function(self, elapsed)
	local now = GetTime()
	local personal
	-- (The camera moved in or out: see Look.)
	local nowZoom = FAR_USED and GetCameraZoom and GetCameraZoom() or 0
	if type(nowZoom) == "number" and Known(nowZoom) and nowZoom ~= zoom then
		zoom = nowZoom
		for unitFrame, text in pairs(texts) do
			if text:IsShown() and Usable(unitFrame.name) and unitFrame.unit then
				UpdateLook(text, text.band)
				if text.dirty then
					DrawName(text, unitFrame.name, unitFrame.unit)
				end
			end
		end
	end
	-- (In sight or not: see sight. Plates showing just a name.)
	for plate in pairs(nameShare) do
		local level = sight[plate] or 1
		local okAlpha, alpha = pcall(plate.GetAlpha, plate)
		local target = ((bodyShare[plate] or 1) < 0.5 and okAlpha and Known(alpha) and alpha < 0.99) and 0 or 1
		if level ~= target then
			level = ns.Approach(level, target, elapsed, SIGHT_FADE)
			sight[plate] = level < 1 and level or nil
			personal = personal or PersonalPlate()
			ApplyPlate(plate, personal)
		end
	end
	for plate, swap in pairs(swaps) do
		personal = personal or PersonalPlate()
		if now - swap.started >= FAR_SWAP then
			swaps[plate] = nil
		end
		ApplyPlate(plate, personal)
	end
	if now >= farCheckAt then
		farCheckAt = now + FAR_CHECK
		for unitFrame, text in pairs(texts) do
			if text:IsShown() and Usable(unitFrame.name) and unitFrame.unit then
				DrawName(text, unitFrame.name, unitFrame.unit)
			end
		end
		for plate in pairs(FAR_USED and nameShare or {}) do
			if (bodyShare[plate] or 1) <= 0 and not swaps[plate] then
				local band = Band(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
				if band == nil or band == (bandOf[plate] or 2) then
					farSince[plate] = nil
				elseif not farSince[plate] then
					farSince[plate] = now
				elseif now - farSince[plate] >= FAR_HOLD then
					farSince[plate] = nil
					-- (The text takes the new look at once, fading in over a copy in the old.)
					swaps[plate] = { started = now, from = bandOf[plate] or 2, to = band }
					bandOf[plate] = band
				end
			end
		end
	end
	if not (next(nameShare) or next(swaps)) then
		self:Hide()
	end
end))

function ns.WatchFarNames()
	farWatch:Show()
end

-- /cine debug names: every 0.1 s, each player's plate's name state, logged
-- when it changes, to see why a name blinks on and off.
local namesTicker
local namesLast = {}
-- (And every frame, your target's name colors, logged as they change: a
-- flash of the wrong color lasts a frame or so, under the ticker's 0.1 s.)
local namesColours = CreateFrame("Frame")
namesColours:Hide()
namesColours:SetScript("OnUpdate", function()
	local function Colour(region)
		if not region then return "none" end
		local ok, r, g, b, a = pcall(region.GetTextColor, region)
		if not ok then return "error" end
		if not (Known(r) and Known(g) and Known(b)) then return "secret" end
		local okAlpha, alpha = pcall(region.GetAlpha, region)
		-- (Retail's vertex color tints a text on top of its own: white there too?)
		local okVertex, vr, vg, vb = pcall(region.GetVertexColor, region)
		local vertex = okVertex and type(vr) == "number" and (Known(vr) and Known(vg) and Known(vb)
			and ("%.2f/%.2f/%.2f"):format(vr, vg, vb) or "secret") or "none"
		return ("%.2f/%.2f/%.2f a%s vertex %s alpha %s shown %s"):format(r, g, b,
			Known(a) and ("%.2f"):format(a or -1) or "secret", vertex,
			okAlpha and Known(alpha) and ("%.2f"):format(alpha) or "secret", tostring(Seen(region)))
	end
	-- (Every other text showing on the plate, with its words: a second name
	-- the game shows on mouseover would be the white one.)
	local function Others(unitFrame)
		local found = {}
		local function Scan(frame, depth)
			for _, region in ipairs({ frame:GetRegions() }) do
				if region ~= unitFrame.name and region ~= texts[unitFrame] and region:GetObjectType() == "FontString"
					and Seen(region) ~= false then
					local okText, words = pcall(region.GetText, region)
					words = okText and Known(words) and words or "?"
					if words ~= "" and words ~= "?" then
						local okName, name = pcall(region.GetDebugName, region)
						found[#found + 1] = ("%s '%s' %s"):format(okName and tostring(name) or "?", words, Colour(region))
					end
				end
			end
			if depth < 3 then
				for _, child in ipairs({ frame:GetChildren() }) do
					if not (child.IsForbidden and child:IsForbidden()) and Seen(child) ~= false then
						Scan(child, depth + 1)
					end
				end
			end
		end
		pcall(Scan, unitFrame, 0)
		return #found > 0 and table.concat(found, "; ") or "none"
	end
	local plate = C_NamePlate.GetNamePlateForUnit("target")
	local unitFrame = plate and plate.UnitFrame
	local line = "no target plate"
	if unitFrame then
		local tint = tints[unitFrame]
		local okOver, over = pcall(UnitIsUnit, "mouseover", "target")
		line = ("target colours: game's %s | ours %s | other texts %s | tint %s | mouseover %s"):format(
			Colour(Usable(unitFrame.name) and unitFrame.name or nil), Colour(texts[unitFrame]), Others(unitFrame),
			tint and (("level %.2f name %s"):format(tint.level or -1,
				tint.name and ("%.2f/%.2f/%.2f"):format(tint.name[1], tint.name[2], tint.name[3]) or "game's")) or "none",
			okOver and Known(over) and (over and "on target" or (UnitExists("mouseover") and "other" or "none")) or "?")
	end
	if namesLast.colours ~= line then
		namesLast.colours = line
		ns.Log("names", line)
	end
end)
function ns.ToggleNamesDebug()
	if namesTicker then
		namesTicker:Cancel()
		namesTicker = nil
		namesColours:Hide()
		wipe(namesLast)
		return false
	end
	namesColours:Show()
	namesTicker = C_Timer.NewTicker(0.1, function()
		-- (A target with no plate at all says so.)
		local targetLine = UnitExists("target") and not C_NamePlate.GetNamePlateForUnit("target")
			and ("target: no plate (row %s)"):format(tostring(ns.TargetNameRow("target"))) or nil
		if targetLine and namesLast.target ~= targetLine then
			ns.Log("names", targetLine)
		end
		namesLast.target = targetLine
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unit = UnitOf(plate)
			local okGuid, guid = pcall(UnitGUID, unit)
			local okTarget, isTarget = pcall(UnitIsUnit, unit, "target")
			if unit and ((okGuid and Known(guid) and type(guid) == "string" and guid:find("^Player%-"))
				or (okTarget and Known(isTarget) and isTarget)) then
				local okName, who = pcall(UnitName, unit)
				local okAlpha, alpha = pcall(plate.GetAlpha, plate)
				local text = texts[plate.UnitFrame]
				local line = ("%s: %s | name=%s body=%s plateAlpha=%s sight=%s band=%s swap=%s text=%s"):format(
					okName and Known(who) and tostring(who) or unit, ns.DescribePlateNameKept(unit, plate),
					tostring(nameShare[plate]), tostring(bodyShare[plate]),
					okAlpha and Known(alpha) and ("%.2f"):format(alpha) or "?", tostring(sight[plate]),
					tostring(bandOf[plate]), tostring(swaps[plate] and swaps[plate].to),
					text and (text:IsShown() and ("%.2f"):format(text:GetAlpha()) or "hidden") or "none")
				if namesLast[unit] ~= line then
					namesLast[unit] = line
					ns.Log("names", line)
				end
			end
		end
	end)
	return true
end

local QUEST_ICONS_EVERY = 0.5
local questIconsAt = 0

-- Each tick, from ns.UpdatePlates: active while the Nameplates page steers
-- plates (CineMode, its master switch on).
function ns.UpdatePlateParts(active, elapsed)
	local changed = false
	for _, part in ipairs(ns.PLATE_PARTS) do
		local target = (not active or ns.PlateRowWanted("Part" .. part)) and 1 or 0
		local level = levels[part]
		if level == nil then
			levels[part] = target -- logging in: no fade
			changed = changed or target < 1
		elseif level ~= target then
			levels[part] = ns.Approach(level, target, elapsed, target > level and ns.FadeInTime() or ns.FadeOutTime())
			changed = true
		end
	end
	if changed then
		ApplyAll()
	end
	-- The class and role icons: shown nowhere with the page's master switch off.
	local iconsChanged = false
	for _, part in ipairs(ns.PLATE_ICON_PARTS) do
		local wanted
		if not ns.db.handlePlates or (part == "QuestIcon" and not ns.Setting("questVision")) then
			wanted = false
		elseif active then
			wanted = ns.PlateRowWanted("Part" .. part)
		else
			wanted = ns.db["plateAlwaysPart" .. part]
		end
		local target = wanted and 1 or 0
		local level = levels[part]
		if level == nil then
			levels[part] = target
			iconsChanged = iconsChanged or target > 0
		elseif level ~= target then
			levels[part] = ns.Approach(level, target, elapsed, target > level and ns.FadeInTime() or ns.FadeOutTime())
			iconsChanged = true
		end
	end
	if iconsChanged then
		RefreshClassIcons()
	elseif ((levels.QuestIcon or 0) > 0 or ns.QuestMarkLevel() > 0 or next(markShare)) and GetTime() >= questIconsAt then
		-- (Quest progress comes and goes without the row changing: looked at again now and then.)
		questIconsAt = GetTime() + QUEST_ICONS_EVERY
		for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
			RefreshQuestIcon(plate)
		end
	end
end

-- For /cine debug plates: which of each part's frames the plate has, then
-- every frame and text on it, for finding parts a client names otherwise.
-- One frame or texture for the debug listing: its type, whether it's shown,
-- a text's words and a texture's colour. (Not everything can say:
-- animations, say. Anything that errors is listed bare.)
local function Entry(name, value)
	local okType, kind = pcall(function() return value:GetObjectType() end)
	local okShown, shown = pcall(function() return value:IsShown() end)
	local okText, text = pcall(function() return kind == "FontString" and value:GetText() or nil end)
	if okText and issecretvalue and issecretvalue(text) then
		text = "(secret)"
	end
	local okColor, color = pcall(function()
		if kind ~= "Texture" then
			return nil
		end
		local r, g, b = value:GetVertexColor()
		if not (Known(r) and Known(g) and Known(b)) then
			return "secret"
		end
		return ("%.2f/%.2f/%.2f"):format(r, g, b)
	end)
	return name .. ":" .. (okType and tostring(kind) or "?")
		.. ((okShown and not ns.Flag(shown)) and "(hidden)" or "")
		.. ((okText and text) and (' "' .. text .. '"') or "")
		.. ((okColor and color) and (" " .. color) or "")
end

-- Every frame and texture on a frame: by its field, then its textures and
-- texts that have none (numbered).
local function ListFields(frame)
	local children, named = {}, {}
	for field, value in pairs(frame) do
		-- (Some tables can't even be looked into: a locked one on a group member's plate.)
		if type(field) == "string" and type(value) == "table" and Known(value)
			and select(2, pcall(function() return value.GetObjectType ~= nil end)) == true then
			named[value] = true
			children[#children + 1] = Entry(field, value)
		end
	end
	table.sort(children)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	for i, region in ipairs(ok and regions or {}) do
		if not named[region] then
			children[#children + 1] = Entry("#" .. i, region)
		end
	end
	return table.concat(children, ", ")
end

-- For /cine debug plates: the plate's name colour (text, then vertex), the
-- game's colour for its unit, and why ours is on it or not.
local function Rgb(r, g, b)
	if not (Known(r) and Known(g) and Known(b)) then
		return "secret"
	end
	return ("%.2f/%.2f/%.2f"):format(r or -1, g or -1, b or -1)
end

function ns.DescribePlateName(unitFrame)
	local name = unitFrame and unitFrame.name
	if not Usable(name) then
		return "no name text"
	end
	local plate = unitFrame:GetParent()
	local unit = unitFrame.unit
	local text = texts[unitFrame]
	local ok, colours = pcall(function()
		return "game's text " .. Rgb(name:GetTextColor())
			.. (text and (", ours " .. Rgb(text:GetTextColor())) or "")
	end)
	local okGame, game = pcall(function()
		return UnitSelectionColor and Rgb(UnitSelectionColor(unit)) or "no UnitSelectionColor"
	end)
	return ("%s, game %s, ours=%s band=%s size=%s height=%s unit=%s tint unit=%s body=%s name=%s"):format(
		ok and colours or ("error " .. tostring(colours)), okGame and game or ("error " .. tostring(game)),
		tostring(text ~= nil and text:IsShown()), tostring(bandOf[plate] or 2), tostring(text and text.size),
		tostring(text and text.y), tostring(unit),
		tostring(unit and TintUnit(unit)), tostring(bodyShare[plate]), tostring(nameShare[plate]))
end

function ns.DescribePlateParts(unitFrame)
	local found = {}
	for _, part in ipairs(ns.PLATE_PARTS) do
		local names = {}
		EachPartFrame(unitFrame, part, function(frame)
			-- (With its alpha now, and @ ours while held.)
			-- (A secret alpha or name formats to a secret string, which concat refuses.)
			local ok, alpha = pcall(frame.GetAlpha, frame)
			local wanted = held[frame]
			local okName, name = pcall(frame.GetDebugName, frame)
			names[#names + 1] = (okName and Known(name) and tostring(name):match("[^.]*%.?[^.]+$") or "?") .. " "
				.. (ok and (Known(alpha) and ("%.2f"):format(alpha) or "secret") or "?")
				.. (wanted and ("@" .. ("%.2f"):format(wanted)) or "")
		end)
		found[#found + 1] = part .. "=" .. (#names > 0 and table.concat(names, "+") or "NONE")
	end
	-- The role the game gives the plate's unit, and whether our role icon shows.
	local unit = unitFrame.unit
	local okRole, role = pcall(function() return unit and UnitGroupRolesAssigned(unit) end)
	if okRole and issecretvalue and issecretvalue(role) then
		role = "(secret)"
	end
	local roleIcon = roleIcons[unitFrame:GetParent()]
	found[#found + 1] = "Role=" .. (okRole and tostring(role) or "?") .. " icon="
		.. (roleIcon and (roleIcon:IsShown() and "shown" or "hidden") or "none")
	if unit and ns.DescribeQuestMob then
		local questIcon = questIcons[unitFrame:GetParent()]
		found[#found + 1] = ns.DescribeQuestMob(unit) .. " icon="
			.. (questIcon and (questIcon:IsShown() and "shown" or "hidden") or "none")
	end
	-- What the quest mark goes left of: each side icon (visible, alpha, left
	-- and right on screen), then anything else drawn left of the bar's middle.
	local function Spot(frame)
		local okVisible, visible = pcall(frame.IsVisible, frame)
		local alpha = Measure(frame, "GetAlpha")
		local left, right = Measure(frame, "GetLeft"), Measure(frame, "GetRight")
		local scale = Measure(frame, "GetEffectiveScale")
		local width = Measure(frame, "GetWidth")
		local okPoint, point, _, relative, offset = pcall(frame.GetPoint, frame, 1)
		local anchor = "?"
		if okPoint and Known(point) and Known(relative) and Known(offset) then
			anchor = ("%s>%s %s"):format(tostring(point), tostring(relative), tostring(offset))
		end
		return ("%s a=%s %s-%s w=%s at %s"):format(okVisible and (Known(visible) and tostring(visible) or "secret") or "?",
			alpha and ("%.2f"):format(alpha) or "?", left and scale and ("%.0f"):format(left * scale) or "?",
			right and scale and ("%.0f"):format(right * scale) or "?", width and ("%.0f"):format(width) or "?", anchor)
	end
	local sides = {}
	local barFrame = unitFrame.HealthBarsContainer or unitFrame.healthBar
	local barX = Usable(barFrame) and Measure(barFrame, "GetCenter")
	local barScale = Usable(barFrame) and Measure(barFrame, "GetEffectiveScale")
	sides[#sides + 1] = "bar middle " .. (barX and barScale and ("%.0f"):format(barX * barScale) or "?")
	local seen = {}
	for _, field in ipairs(SIDE_ICONS) do
		local frame = unitFrame[field]
		if not Known(frame) then
			frame = nil
		end
		seen[frame or field] = true
		sides[#sides + 1] = field .. " " .. (Usable(frame) and Spot(frame) or "none")
	end
	if barX and barScale then
		for _, owner in ipairs({ unitFrame, unitFrame.HealthBarsContainer }) do
			if type(owner) == "table" and owner.GetObjectType then
				for field, value in pairs(owner) do
					-- (Some fields hold secret values, which can't be a table's key.)
					if type(field) == "string" and type(value) == "table" and Known(value) and not seen[value]
						and Usable(value) and value.GetLeft then
						seen[value] = true
						local left, scale = Measure(value, "GetLeft"), Measure(value, "GetEffectiveScale")
						local okVisible, visible = pcall(value.IsVisible, value)
						if left and scale and left * scale < barX * barScale - 20
							and okVisible and Known(visible) and visible then
							sides[#sides + 1] = field .. " " .. Spot(value)
						end
					end
				end
			end
		end
	end
	local questIcon = questIcons[unitFrame:GetParent()]
	if questIcon then
		sides[#sides + 1] = "quest mark at " .. tostring(questIcon.x) .. " " .. Spot(questIcon)
	end
	found[#found + 1] = "left of bar: " .. table.concat(sides, "; ")
	-- The health bar's container, the bar, and any frame on the bar (its border).
	local healthFields = {}
	local container, bar = unitFrame.HealthBarsContainer, unitFrame.healthBar
	if type(container) == "table" and container.GetObjectType then
		healthFields[#healthFields + 1] = "container: " .. ListFields(container)
	end
	if type(bar) == "table" and bar.GetObjectType then
		healthFields[#healthFields + 1] = "healthBar: " .. ListFields(bar)
		for field, value in pairs(bar) do
			if type(field) == "string" and type(value) == "table"
				and select(2, pcall(function() return value.GetRegions ~= nil end)) == true then
				healthFields[#healthFields + 1] = "healthBar." .. field .. ": " .. ListFields(value)
			end
		end
	end
	-- And the auras' frame, whose lists are the Buffs and Debuffs parts.
	local auras = unitFrame.AurasFrame
	if type(auras) == "table" and auras.GetObjectType then
		healthFields[#healthFields + 1] = "AurasFrame: " .. ListFields(auras)
	end
	healthFields = #healthFields > 0 and table.concat(healthFields, " | ") or "NONE"
	return table.concat(found, ", "), ListFields(unitFrame), healthFields
end

-- /cine debug range: what the game says about how far a unit is, for sizing
-- names on name-only plates like the game's names over heads (which shrink
-- with distance). Your target, the unit under the mouse, then the plates
-- showing just a name: each check's answer (true, false, nil, secret, error).
local function Answer(ok, value)
	if not ok then
		return "error"
	elseif issecretvalue and issecretvalue(value) then
		return "secret"
	end
	return tostring(value)
end

function ns.PrintRangeDebug()
	local function Describe(unit)
		local parts = {}
		for i = 1, 4 do
			parts[#parts + 1] = "interact" .. i .. "=" .. Answer(pcall(CheckInteractDistance, unit, i))
		end
		parts[#parts + 1] = "distance=" .. Answer(pcall(function()
			local squared, checked = UnitDistanceSquared(unit)
			return checked and squared and ("%.0f"):format(math.sqrt(squared)) or nil
		end))
		local isItem = C_Item and C_Item.IsItemInRange or IsItemInRange
		parts[#parts + 1] = "bandage=" .. Answer(pcall(isItem, 1251, unit))
		local isSpell = C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
		parts[#parts + 1] = "autoattack=" .. Answer(pcall(isSpell, 6603, unit))
		return table.concat(parts, " ")
	end
	ns.Print(("client: %s; in combat: %s; target's plate: %s"):format(ns.isRetail and "retail" or "Forever",
		tostring(InCombatLockdown() and true or false),
		C_NamePlate and C_NamePlate.GetNamePlateForUnit("target") and "on screen" or "none"))
	for _, unit in ipairs({ "target", "mouseover" }) do
		if UnitExists(unit) then
			ns.Print(unit .. " " .. tostring(UnitName(unit)) .. ": " .. Describe(unit))
		end
	end
	for plate in pairs(nameShare) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and (bodyShare[plate] or 1) < 1 then
			local okName, name = pcall(UnitName, unit)
			ns.Print(unit .. " " .. Answer(okName, name) .. ": " .. Describe(unit))
		end
	end
end

-- /cine debug platedebuffs: whether the game keeps auras secret now, and
-- your debuffs on your target as each read answers (name, spell ID and
-- whether the game's plate shows it; secret or error). In fights on retail
-- an addon can't read them at all (tested 2026-10-28), so which debuffs a
-- plate shows is the game's alone.
function ns.PrintPlateDebuffsDebug()
	local secrets, secret = _G.C_Secrets, "no such check"
	if secrets and secrets.ShouldAurasBeSecret then
		secret = Answer(pcall(secrets.ShouldAurasBeSecret))
	end
	ns.Print(("client: %s; in combat: %s; auras secret: %s"):format(ns.isRetail and "retail" or "Forever",
		tostring(InCombatLockdown() and true or false), secret))
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
		ns.Print("C_UnitAuras.GetAuraDataByIndex: missing on this client")
		return
	elseif not UnitExists("target") then
		ns.Print("no target: target an enemy with your debuffs on it")
		return
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL|PLAYER")
		if not ok then
			ns.Print(("debuff %d: error %s"):format(i, tostring(aura)))
			return
		elseif type(aura) ~= "table" then
			if i == 1 then
				ns.Print("none of your debuffs on it")
			end
			return
		end
		ns.Print(("debuff %d: %s (%s), shows on game plate: %s"):format(i, Answer(true, aura.name),
			Answer(true, aura.spellId), Answer(true, aura.nameplateShowPersonal)))
	end
end
