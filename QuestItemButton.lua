-- Cinematic: the quest item button (Vision page's Quest Vision,
-- questItemButton). The item the nearest tracked quest gives you to use
-- (the small square beside it in the quest tracker), on a big button where
-- your extra ability button goes: at the extra abilities frame's place (Edit
-- Mode's spot), or beside it while the game has an extra action or zone
-- ability in it. Ours, not the game's: an addon can't put an item on that one.
-- Shows within NEAR_YARDS of the quest's area, until its objectives are done
-- (once used: the objectives the item moved). A secure button: it can only
-- show, hide, change item or move out of combat, so in a fight it stays as it
-- was (its cooldown and count still follow). Key binding: CLICK
-- CinematicQuestItemButton:LeftButton. Not one of the frames CineMode fades:
-- that row (the extra action button's) is in the Action bars mouseover group,
-- so the mouse on it brought the bars up. It shows while it's needed.
local ADDON_NAME, ns = ...
local L = ns.L

local NEAR_YARDS = 300
local CHECK_EVERY = 2 -- seconds (you move: the nearest quest changes)
local BINDING = "CLICK CinematicQuestItemButton:LeftButton"
local GAP = 10 -- beside the game's extra button: this far to its right

_G["BINDING_NAME_" .. BINDING] = "Cinematic: " .. L["Use the quest item"]
ns.OnLanguage(function()
	_G["BINDING_NAME_" .. BINDING] = "Cinematic: " .. L["Use the quest item"]
end)

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Shown(name)
	local frame = _G[name]
	return frame and frame.IsShown and ns.Flag(frame:IsShown()) or false
end

-- Its look: the Style hub's Quest item button page (questItemStyle: on; off,
-- these defaults, whatever the page's set to).
local DEFAULTS = ns.DEFAULTS
DEFAULTS.questItemStyle = true
DEFAULTS.questItemSize = 52            -- its width and height
DEFAULTS.questItemShape = "square"     -- or "round"
DEFAULTS.questItemFrame = "general"    -- round it: "game" (the extra action button's art), "none", "thin", "thick", "custom"
DEFAULTS.questItemZoom = false         -- the icon zoomed in, to cut its own border
DEFAULTS.questItemGlow = "none"        -- while it's ready: "none", "soft" or "edge"
DEFAULTS.questItemGlowColor = "gold"   -- ...gold or "custom" (questItemGlowR/G/B)
DEFAULTS.questItemGlowR, DEFAULTS.questItemGlowG, DEFAULTS.questItemGlowB = 0.5, 0.83, 1
DEFAULTS.questItemCooldown = "sweep"   -- "sweep" (the game's) or "fill" (a dark fill, draining)
DEFAULTS.questItemNumbers = true       -- the seconds left in the middle while it cools down
DEFAULTS.questItemKey = true           -- its key binding in the corner
DEFAULTS.questItemFont = "general"     -- its numbers' font (QUEST_ITEM_FONTS; general: General's)
DEFAULTS.questItemOutline = -1         -- ...outline: 0 none, 1 thin, 2 thick (-1: General's)

function ns.QuestItemLook()
	return ns.StyleLook("questItemStyle")
end

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- (a round mask every client has)
local SOFT_GLOW = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\SoftGlow" -- (Media/make_soft_glow.py)
local SQUARE = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 1, 0.82, 0 }
-- The fonts its numbers can take (game: the action buttons' own).
ns.QUEST_ITEM_FONTS = {
	{ "game", "The game's" },
	{ "friz", "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
	{ "arial", "Arial Narrow", "Fonts\\ARIALN.TTF" },
	{ "morpheus", "Morpheus", "Fonts\\MORPHEUS.TTF" },
	{ "skurri", "Skurri", "Fonts\\SKURRI.TTF" },
}
local FONT_FILES = {}
for _, font in ipairs(ns.QUEST_ITEM_FONTS) do FONT_FILES[font[1]] = font[3] end
ns.OnLanguage(function() ns.QUEST_ITEM_FONTS[1][2] = L["The game's"] end)

-- Fonts other addons share through LibSharedMedia (none of theirs bundled)
-- come after these, as "lsm:<its name>".
local function SharedMedia()
	local stub = _G.LibStub
	return stub and stub("LibSharedMedia-3.0", true)
end

-- Whether a font file has small letters: a font with only capitals (some
-- shared ones) draws every small letter as the same box. So: a-z all one
-- width while A-Z aren't (a fixed-width font has both even), it's capitals
-- only. Cached per file. (Widths kept for /cine debug fonts; refusals
-- counted there too.)
local LOWER, UPPER = "abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local readable, measured, tries, probe = {}, {}, {}, nil
local function Widths(letters)
	local widths, even = {}, true
	for letter in letters:gmatch(".") do
		probe:SetText(letter)
		widths[#widths + 1] = probe:GetStringWidth()
		if math.abs(widths[#widths] - widths[1]) > 0.5 then even = false end
	end
	return widths, even
end
local function Readable(path)
	if readable[path] ~= nil then return readable[path] end
	if not probe then
		-- (Shown, see-through: the game may not load a font for hidden text.)
		local holder = CreateFrame("Frame", nil, UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint("BOTTOMLEFT")
		holder:SetAlpha(0)
		probe = holder:CreateFontString(nil, "ARTWORK")
		probe:SetPoint("BOTTOMLEFT")
	end
	local ok, set = pcall(probe.SetFont, probe, path, 20, "")
	if not ok or set == false then
		-- (Refused: not loaded yet, or not there. Kept, uncached, so it's
		-- measured again when next asked; a missing file just shows the
		-- game's font.)
		tries[path] = (tries[path] or 0) + 1
		measured[path] = ("refused %d times, kept"):format(tries[path])
		return true
	end
	local lower, lowerEven = Widths(LOWER)
	local upper, upperEven = Widths(UPPER)
	probe:SetText("")
	readable[path] = not (lowerEven and not upperEven)
	measured[path] = ("a i m %.1f %.1f %.1f, A I M %.1f %.1f %.1f"):format(lower[1], lower[9], lower[13],
		upper[1], upper[9], upper[13])
	return readable[path]
end

-- A shared font's file, whether or not it's readable (nil: no longer there).
local function SharedFile(value)
	local name = type(value) == "string" and value:match("^lsm:(.+)")
	local media = name and SharedMedia()
	if media then
		local ok, path = pcall(media.Fetch, media, "font", name, true)
		if ok and path then return path end
	end
end

-- A font value's file (nil: the game's, or a shared one no longer there or
-- with no small letters).
function ns.StyleFontFile(value)
	if FONT_FILES[value] then return FONT_FILES[value] end
	local path = SharedFile(value)
	if path and Readable(path) then return path end
end

-- /cine debug fonts: every font shared through LibSharedMedia, its file, and
-- whether it has small letters (left out of the lists if not).
function ns.ReportStyleFonts()
	local media = SharedMedia()
	if not (media and media.List) then
		ns.Print("Fonts: no LibSharedMedia addon loaded, so only our five.")
		return
	end
	local ok, names = pcall(media.List, media, "font")
	names = ok and names or {}
	-- (All measured again, then again when listed, once the files the game
	-- hadn't loaded have had time to.)
	wipe(readable)
	wipe(tries)
	for _, name in ipairs(names) do
		local path = SharedFile("lsm:" .. name)
		if path then Readable(path) end
	end
	ns.Print("Fonts: measuring, the list in 4 seconds...")
	C_Timer.After(4, function()
		local left = 0
		for _, name in ipairs(names) do
			local path = SharedFile("lsm:" .. name)
			local good = path and Readable(path)
			if not good then left = left + 1 end
			ns.Print(("  %s%s|r %s - %s (%s)"):format(good and "|cff80ff80" or "|cffff6060", name,
				good and "kept" or "LEFT OUT", tostring(path), path and measured[path] or "no file"))
		end
		ns.Print(("Fonts: %d shared, %d left out (no small letters: a-z all one width, A-Z not). Refused: the " ..
			"game wouldn't set it on our measuring text (asked once now, again 4 seconds later)."):format(#names, left))
	end)
end

-- A font value's name, as the lists show it.
function ns.StyleFontName(value)
	for _, info in ipairs(ns.QUEST_ITEM_FONTS) do
		if info[1] == value then return info[2] end
	end
	return type(value) == "string" and value:match("^lsm:(.+)") or tostring(value)
end

-- The list, for a dropdown: { value, text } each, ours first, then the
-- shared ones (sorted; any with a file of ours left out).
function ns.StyleFontChoices()
	local list, known = {}, {}
	for _, info in ipairs(ns.QUEST_ITEM_FONTS) do
		list[#list + 1] = { value = info[1], text = info[2] }
		if info[3] then known[info[3]:lower()] = true end
	end
	local media = SharedMedia()
	if media and media.List then
		local ok, names = pcall(media.List, media, "font")
		local shared = {}
		for _, name in ipairs(ok and names or {}) do
			local path = ns.StyleFontFile("lsm:" .. name) -- (nil for one with no small letters: left out)
			if path and not known[path:lower()] then shared[#shared + 1] = { value = "lsm:" .. name, text = name } end
		end
		table.sort(shared, function(a, b) return a.text:lower() < b.text:lower() end)
		for _, choice in ipairs(shared) do list[#list + 1] = choice end
	end
	return list
end
-- (A cooldown this short is the global cooldown: no fill, seconds or dimmed glow for it.)
local GCD = 1.5

-- The button's parts on frame (the real button, or a preview's stand-in):
-- icon, the game's frame art (style), a black edge or disc behind (back), the
-- ready glow, a dark fill for the cooldown, the cooldown sweep, and the count,
-- key and seconds over them. round: textures masked round when its shape is
-- (the button's highlight and pushed ones too). Drawn by ns.StyleQuestItem.
function ns.MakeQuestItemParts(frame, round)
	local parts = { frame = frame, round = round or {} }
	parts.glow = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
	parts.glow:SetPoint("CENTER")
	parts.back = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
	parts.back:SetPoint("CENTER")
	parts.icon = frame:CreateTexture(nil, "ARTWORK")
	parts.icon:SetAllPoints()
	parts.fill = frame:CreateTexture(nil, "ARTWORK", nil, 1)
	parts.fill:SetPoint("TOPLEFT")
	parts.fill:SetPoint("TOPRIGHT")
	parts.fill:SetColorTexture(0, 0, 0, 0.7)
	parts.fill:Hide()
	-- The extra action button's frame round it, where the client has that art;
	-- else an action button's border.
	parts.style = frame:CreateTexture(nil, "OVERLAY")
	parts.style:SetPoint("CENTER")
	if parts.style:SetTexture("Interface\\ExtraButton\\Default") == false or not parts.style:GetTexture() then
		parts.style:SetTexture("Interface\\Buttons\\UI-Quickslot2")
		parts.styleSize = { 1.7, 1.7 }
	else
		parts.styleSize = { 256 / 52, 128 / 52 }
	end
	parts.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	parts.cooldown:SetAllPoints(parts.icon)
	if parts.cooldown.SetHideCountdownNumbers then parts.cooldown:SetHideCountdownNumbers(true) end
	-- (The text above the sweep.)
	parts.top = CreateFrame("Frame", nil, frame)
	parts.top:SetAllPoints()
	parts.top:SetFrameLevel(parts.cooldown:GetFrameLevel() + 1)
	parts.count = parts.top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	parts.count:SetPoint("BOTTOMRIGHT", -3, 3)
	parts.hotkey = parts.top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	parts.hotkey:SetPoint("TOPRIGHT", -3, -3)
	parts.seconds = parts.top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	parts.seconds:SetPoint("CENTER")
	parts.fonts = {}
	for _, text in ipairs({ parts.count, parts.hotkey, parts.seconds }) do
		parts.fonts[text] = { text:GetFont() }
	end
	table.insert(parts.round, parts.icon)
	table.insert(parts.round, parts.fill)
	table.insert(parts.round, parts.back)
	return parts
end

-- Its parts' look, as look says (ns.QuestItemLook), at size (the frame's
-- own size is the caller's: the real button's can't change in a fight).
function ns.StyleQuestItem(parts, look, size)
	parts.look, parts.size = look, size
	local round = look.questItemShape == "round"
	if parts.frame.CreateMaskTexture and parts.masked ~= round then
		parts.masked = round
		if not parts.mask then
			parts.mask = parts.frame:CreateMaskTexture()
			parts.mask:SetAllPoints()
			parts.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
		end
		for _, texture in ipairs(parts.round) do
			if round then texture:AddMaskTexture(parts.mask) else texture:RemoveMaskTexture(parts.mask) end
		end
	end
	local cooldown = parts.cooldown
	if cooldown.SetSwipeTexture then
		cooldown:SetSwipeTexture(round and CIRCLE or SQUARE)
		cooldown:SetSwipeColor(0, 0, 0, 0.8)
	end
	if cooldown.SetUseCircularEdge then cooldown:SetUseCircularEdge(round) end

	local frame, edge, er, eg, eb = ns.StyleBorder(look, "questItemFrame")
	parts.style:SetShown(frame == "game")
	parts.style:SetSize(size * parts.styleSize[1], size * parts.styleSize[2])
	-- (A line of ours: a plate behind it, edge pixels bigger all round; a disc
	-- behind a round icon.)
	parts.back:SetShown(frame == "line")
	parts.back:SetSize(size + 2 * edge, size + 2 * edge)
	parts.back:SetColorTexture(er or 0, eg or 0, eb or 0, 1)
	local zoom = look.questItemZoom and 0.08 or 0
	parts.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

	-- The ready glow: soft, a halo added on; an edge, a ring of color.
	local r, g, b = unpack(GOLD)
	if look.questItemGlowColor == "custom" then
		r, g, b = look.questItemGlowR, look.questItemGlowG, look.questItemGlowB
	end
	local glow = parts.glow
	if look.questItemGlow == "soft" then
		glow:SetTexture(SOFT_GLOW)
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(r, g, b, 1)
		glow:SetSize(size * 1.7, size * 1.7)
		if parts.glowMasked then glow:RemoveMaskTexture(parts.glowMask) parts.glowMasked = false end
	else
		glow:SetColorTexture(r, g, b, 1)
		glow:SetBlendMode("BLEND")
		local pad = frame == "game" and 8 or frame == "line" and edge + 2 or 2
		glow:SetSize(size + 2 * pad, size + 2 * pad)
		-- (Round: a disc, masked with one of its own the size of the glow.)
		if parts.frame.CreateMaskTexture and round ~= (parts.glowMasked or false) then
			if not parts.glowMask then
				parts.glowMask = parts.frame:CreateMaskTexture()
				parts.glowMask:SetAllPoints(glow)
				parts.glowMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
			end
			if round then glow:AddMaskTexture(parts.glowMask) else glow:RemoveMaskTexture(parts.glowMask) end
			parts.glowMasked = round
		end
	end

	-- The numbers: the font's file, sized to the button, outlined.
	local SCALE = { [parts.count] = 14 / 52, [parts.hotkey] = 12 / 52, [parts.seconds] = 0.36 }
	for text, base in pairs(parts.fonts) do
		local file = ns.StyleFontFile(look.questItemFont) or base[1]
		if file then
			text:SetFont(file, math.max(6, math.floor(size * SCALE[text] + 0.5)),
				ns.OutlinedFlags(base[3], look.questItemOutline))
		end
	end
	parts.hotkey:SetShown(look.questItemKey)
	ns.QuestItemCooldown(parts, parts.start, parts.duration)
end

-- Ticks a cooling button's fill and seconds; once it's done, it's ready.
local function Tick(top)
	local parts = top.parts
	local left = parts.start and parts.start + parts.duration - GetTime() or 0
	if left <= 0 then
		top:SetScript("OnUpdate", nil)
		ns.QuestItemCooldown(parts, nil, nil)
		return
	end
	local look = parts.look
	if look.questItemCooldown == "fill" then
		parts.fill:SetHeight(math.max(0.01, parts.size * left / parts.duration))
	end
	if look.questItemNumbers then
		parts.seconds:SetText(left >= 60 and ("%dm"):format(math.ceil(left / 60)) or math.ceil(left))
	end
end

-- Its cooldown: start, duration (nil: none; false: the game won't say).
function ns.QuestItemCooldown(parts, start, duration)
	parts.start, parts.duration = start or nil, duration
	local look = parts.look or ns.QuestItemLook()
	local cooling = start and duration and duration > GCD and start + duration > GetTime()
	local cooldown = parts.cooldown
	if start and duration and start > 0 and look.questItemCooldown ~= "fill" then
		cooldown:SetCooldown(start, duration)
	else
		cooldown:Clear()
	end
	parts.fill:SetShown(cooling and look.questItemCooldown == "fill" or false)
	parts.seconds:SetShown(cooling and look.questItemNumbers or false)
	-- (Ready: no cooldown the game told us of.)
	parts.glow:SetShown(look.questItemGlow ~= "none" and start ~= false and not cooling)
	parts.top.parts = parts
	if cooling then
		parts.top:SetScript("OnUpdate", Tick)
		Tick(parts.top)
	else
		parts.top:SetScript("OnUpdate", nil)
	end
end

local button = CreateFrame("Button", "CinematicQuestItemButton", UIParent, "SecureActionButtonTemplate")
button:SetSize(DEFAULTS.questItemSize, DEFAULTS.questItemSize)
button:SetFrameStrata("MEDIUM")
button:Hide()
button:SetAttribute("type", "item")
button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
local parts = ns.MakeQuestItemParts(button, { button:GetHighlightTexture(), button:GetPushedTexture() })
local icon, count, hotkey = parts.icon, parts.count, parts.hotkey

-- Its look, again (out of fights: its size can't change in one).
local styled -- (the look's been put on since it last changed)
local function Style()
	if styled or InCombatLockdown() then
		return
	end
	styled = true
	local look = ns.QuestItemLook()
	button:SetSize(look.questItemSize, look.questItemSize)
	ns.StyleQuestItem(parts, look, look.questItemSize)
end
function ns.RefreshQuestItemStyle()
	styled = false
	Style()
end

local current -- { itemID, link, index (quest log), questID }

local function OnLogin()
	-- Click on key down or up, as the game's action buttons do (not both:
	-- that would use it twice).
	button:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
end

button:SetScript("OnEnter", function(self)
	if not current then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if GameTooltip.SetQuestLogSpecialItem then
		pcall(GameTooltip.SetQuestLogSpecialItem, GameTooltip, current.index)
	else
		pcall(GameTooltip.SetHyperlink, GameTooltip, current.link)
	end
	GameTooltip:Show()
end)
button:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

local function Objectives(questID)
	local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
	return ok and type(objectives) == "table" and objectives or {}
end

local function Finished(objective)
	return objective and Known(objective.finished) and objective.finished or false
end

-- The objectives the item is for: the ones that moved after you used it
-- ("The Arcantina": the key's Teleport to the Arcantina, not Speak with
-- Arator after it), kept per character until the quest leaves the log.
-- ns.chardb.questItemObjectives[questID] = { [objective index] = true }.
local USED_WAIT = 60 -- seconds after the cast for its objective to move
local used -- { questID, at, before = { [index] = numFulfilled } }, or nil

local function ItemObjectives()
	local chardb = ns.chardb
	if not chardb then
		return {}
	end
	chardb.questItemObjectives = chardb.questItemObjectives or {}
	return chardb.questItemObjectives
end

local function Counts(questID)
	local counts = {}
	for index, objective in ipairs(Objectives(questID)) do
		local have = objective.numFulfilled
		counts[index] = (type(have) == "number" and Known(have) and have or 0) + (Finished(objective) and 0.5 or 0)
	end
	return counts
end

-- You cast a spell: if it's a quest item's, note that quest's counts.
local function ItemCast(spellID)
	if not (type(spellID) == "number" and Known(spellID)) then
		return
	end
	local GetItemSpell = C_Item and C_Item.GetItemSpell or _G.GetItemSpell
	for _, quest in ipairs(ns.QuestLogItems()) do
		local ok, _, itemSpell = pcall(GetItemSpell or error, quest.itemID)
		if ok and itemSpell == spellID then
			used = { questID = quest.questID, at = GetTime(), before = Counts(quest.questID) }
			return
		end
	end
end

-- The quest log changed: which of that quest's objectives moved since.
local function CheckUsed()
	if not used then
		return
	end
	if GetTime() - used.at > USED_WAIT then
		used = nil
		return
	end
	local moved
	for index, have in pairs(Counts(used.questID)) do
		if have > (used.before[index] or 0) then
			moved = moved or {}
			moved[index] = true
		end
	end
	if moved then
		ItemObjectives()[used.questID] = moved
		used = nil
	end
end

-- Forget quests no longer in the log.
local function ForgetGone()
	local saved = ItemObjectives()
	if not next(saved) or not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then
		return
	end
	for questID in pairs(saved) do
		local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
		if ok and index == nil then
			saved[questID] = nil
		end
	end
end

-- Whether the item's no longer needed (whatever the tracker does with it):
-- the objectives it moved are done, else every objective of the quest is
-- (10/10), the quest log maybe not yet calling it complete.
local function Done(questID)
	local objectives = Objectives(questID)
	if #objectives == 0 then
		return false
	end
	local mine = ItemObjectives()[questID]
	for index, objective in ipairs(objectives) do
		if (not mine or mine[index]) and not Finished(objective) then
			return false
		end
	end
	return true
end

-- Whether the quest is tracked (in the quest tracker). Retail's watch type on
-- clients that have it, else the older IsQuestWatched (by quest log index).
local function Tracked(quest)
	local log = C_QuestLog
	if log and log.GetQuestWatchType then
		local ok, watchType = pcall(log.GetQuestWatchType, quest.questID)
		return ok and watchType ~= nil
	end
	if IsQuestWatched then
		local ok, watched = pcall(IsQuestWatched, quest.index)
		return ok and ns.Flag(watched) or false
	end
	return true
end

-- The tracked quest with an item to use nearest you, within NEAR_YARDS of its
-- area (where the game won't say how far: one anyway, if nothing nearer). nil
-- if none. say: a function told each quest's distance (/cine debug questitem).
local function Nearest(say)
	local log = C_QuestLog
	local best, bestDistance
	for _, quest in ipairs(ns.QuestLogItems(say)) do
		local tracked = Tracked(quest)
		if say and not tracked then
			say(("  quest %s: not tracked"):format(quest.questID))
		end
		if tracked and not (quest.complete or Done(quest.questID)) then
			local distance = math.huge
			local ok, distanceSq, onContinent = pcall(log.GetDistanceSqToQuest or error, quest.questID)
			if ok and type(distanceSq) == "number" and Known(distanceSq) then
				distance = (onContinent and distanceSq <= NEAR_YARDS * NEAR_YARDS) and distanceSq or nil
			end
			if say then
				say(("  quest %s: %s"):format(quest.questID, ok and type(distanceSq) == "number" and Known(distanceSq)
					and ("%.0f yards, on this continent %s"):format(math.sqrt(distanceSq), tostring(onContinent))
					or "distance unknown"))
			end
			if distance and (not bestDistance or distance < bestDistance) then
				best, bestDistance = quest, distance
			end
		end
	end
	return best
end

-- The extra abilities frame (Edit Mode's spot), and whether the game has
-- something in it (an extra action, a zone ability).
local function ExtraSpot()
	local container = _G.ExtraAbilityContainer or _G.ExtraActionBarFrame
	local busy = Shown("ExtraActionBarFrame") or Shown("ZoneAbilityFrame")
	return container, busy
end

local placedAt -- (the spot it was put at: "free" or "busy", and where)
local function Place()
	local container, busy = ExtraSpot()
	local spot = (container and tostring(container) or "none") .. (busy and "busy" or "free")
	if placedAt == spot then
		return
	end
	placedAt = spot
	button:ClearAllPoints()
	if not container then
		button:SetPoint("CENTER", UIParent, "BOTTOM", 0, 250)
	elseif busy then
		button:SetPoint("LEFT", container, "RIGHT", GAP, 0)
	else
		button:SetPoint("CENTER", container, "CENTER")
	end
end

-- What can change in a fight: cooldown, count, key.
local function Paint()
	if not current then
		return
	end
	local GetCooldown = C_Container and C_Container.GetItemCooldown or _G.GetItemCooldown
	local ok, start, duration, enable = pcall(GetCooldown, current.itemID)
	if not (ok and Known(start) and Known(duration)) then
		ns.QuestItemCooldown(parts, false)
	elseif enable ~= 0 and enable ~= false and type(start) == "number" and start > 0 then
		ns.QuestItemCooldown(parts, start, duration)
	else
		ns.QuestItemCooldown(parts, nil, nil)
	end
	local GetCount = C_Item and C_Item.GetItemCount or _G.GetItemCount
	local okCount, have = pcall(GetCount, current.itemID, nil, true)
	count:SetText(okCount and type(have) == "number" and Known(have) and have > 1 and have or "")
	local key = GetBindingKey(BINDING)
	hotkey:SetText(key and GetBindingText and GetBindingText(key, true) or key or "")
end

function ns.RefreshQuestItemButton()
	if InCombatLockdown() then
		Paint()
		return
	end
	local quest = ns.QuestVisionSetting("questItemButton") and Nearest()
	if not quest then
		current = nil
		button:SetAttribute("item", nil)
		button:Hide()
		return
	end
	if not (current and current.itemID == quest.itemID) then
		button:SetAttribute("item", "item:" .. quest.itemID)
		icon:SetTexture(quest.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(quest.itemID)))
	end
	current = quest
	Style()
	Place()
	Paint()
	button:Show()
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED",
	"QUEST_REMOVED", "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "ZONE_CHANGED",
	"ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "UPDATE_EXTRA_ACTIONBAR", "UPDATE_BINDINGS",
	"SPELLS_CHANGED", "QUEST_WATCH_LIST_CHANGED" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_SPELLCAST_SENT", "player")
watcher:SetScript("OnEvent", function(_, event, _, _, _, spellID)
	if event == "UNIT_SPELLCAST_SENT" then
		-- (unit, target name, castGUID, spellID): sent, before the count moves
		ItemCast(spellID)
		return
	end
	if event == "PLAYER_LOGIN" then
		OnLogin()
	elseif event == "QUEST_LOG_UPDATE" then
		CheckUsed()
	elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" or event == "PLAYER_ENTERING_WORLD" then
		ForgetGone()
	end
	ns.RefreshQuestItemButton()
end)
watcher.at = 0
watcher:SetScript("OnUpdate", function(self)
	local now = GetTime()
	if now >= self.at then
		self.at = now + CHECK_EVERY
		if ns.db and (ns.db.questItemButton or button:IsShown()) then
			ns.RefreshQuestItemButton()
		end
	end
end)
-- The zone ability can come and go with no event of its own we hear.
for _, name in ipairs({ "ExtraActionBarFrame", "ZoneAbilityFrame" }) do
	local frame = _G[name]
	if frame and frame.HookScript then
		frame:HookScript("OnShow", function() ns.RefreshQuestItemButton() end)
		frame:HookScript("OnHide", function() ns.RefreshQuestItemButton() end)
	end
end

-- For /cine debug questitem: the quest and item the button would show.
function ns.DescribeQuestItemButton()
	local quest = Nearest(function(text) ns.Print("quest item: " .. text) end)
	local container, busy = ExtraSpot()
	return ("button: %s, nearest quest with an item: %s (item %s), extra frame: %s (%s)"):format(
		button:IsShown() and "shown" or "hidden", tostring(quest and quest.questID), tostring(quest and quest.itemID),
		container and (container:GetName() or "?") or "none", busy and "in use: ours beside it" or "free")
end
