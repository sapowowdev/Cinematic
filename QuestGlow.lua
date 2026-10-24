-- Cinematic: Quest Vision's glow on quest objects (questObjectGlow, Vision
-- page): the thing on the ground you pick up or use for a quest objective
-- glows gold, with the quest mark over it. The game's soft targeting picks
-- one object to interact with at a time (the "softinteract" unit, the
-- nearest in front of you) and, with the settings below, gives it a
-- nameplate: the glow goes on that plate. So it's one object at a time, the
-- one your interact key would use.
-- A quest object: the game shows its quest cursor over it, or says it's
-- related to a quest you're on, or its name is in an objective you haven't
-- finished. Unreadable (secret) counts as no.
local _, ns = ...

local SOFT = "softinteract"
local CHECK_EVERY = 0.15

-- The game settings held while it's on (the player's own come back after):
-- soft targeting of things to interact with, keyboard and mouse too, out to
-- 20 yards in front of you (out of reach too), with a plate and icon for
-- objects (the game gives objects no plate without their icon). The icons
-- it brings are hidden bar the ones you'd see anyway (see UpdateIcon).
-- (Secure: nameplate settings wait for the end of a fight.) Not playerWins:
-- the game changes some of these itself (the object icon as you log in,
-- soft targeting with gamepad mode), which would have let go of them and
-- lost your own values. Held instead: written again (KeepHeld) and put back
-- as they were when you untick it.
local CVARS = { secure = true, values = {
	SoftTargetInteract = "3", SoftTargetInteractRange = "20", SoftTargetInteractArc = "1",
	SoftTargetInteractOnlyInRange = "0", SoftTargetNameplateInteract = "1",
	SoftTargetIconGameObject = "1", nameplateGameObjectMaxDistance = "60",
} }

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Ask(fn, ...)
	if not fn then
		return false
	end
	local ok, value = pcall(fn, ...)
	return ok and Known(value) and value and true or false
end

-- The game's quest cursors (Interface\Cursor, and retail's newer ones in its
-- Crosshair folder), by file number as a texture reads them back: made once,
-- from their names.
local QUEST_CURSORS = { "Quest", "QuestRepeatable", "QuestTurnIn", "QuestInteract", "CampaignQuest",
	"CampaignQuestTurnIn", "LegendaryQuest", "LegendaryQuestTurnIn", "Important", "ImportantTurnIn", "Recurring",
	"RecurringTurnIn", "Wrapper", "WrapperTurnIn" }
local CURSOR_FOLDERS = { "Interface\\Cursor\\", "Interface\\Cursor\\Crosshair\\" }
local probe = CreateFrame("Frame"):CreateTexture()
local questCursorFiles

local function QuestCursorFiles()
	if not questCursorFiles then
		questCursorFiles = {}
		for _, folder in ipairs(CURSOR_FOLDERS) do
			for _, name in ipairs(QUEST_CURSORS) do
				probe:SetTexture(nil)
				pcall(probe.SetTexture, probe, folder .. name)
				local file = probe:GetTexture()
				if type(file) == "number" and Known(file) then
					questCursorFiles[file] = true
				end
			end
		end
	end
	return questCursorFiles
end

-- The cursor the game would show over the unit: its file (number or path)
-- or atlas, or nil.
local function CursorOf(unit)
	if not SetUnitCursorTexture then
		return nil
	end
	probe:SetTexture(nil)
	if not pcall(SetUnitCursorTexture, probe, unit, nil, true) then
		return nil
	end
	local file = probe:GetTexture()
	local atlas = probe.GetAtlas and probe:GetAtlas()
	if file ~= nil and Known(file) then
		return file
	end
	if atlas ~= nil and Known(atlas) then
		return atlas
	end
	return nil
end

local function QuestCursor(cursor)
	if type(cursor) == "number" then
		return QuestCursorFiles()[cursor] or false
	end
	if type(cursor) == "string" then
		local name = cursor:lower()
		return (name:find("quest", 1, true) or name:find("important", 1, true) or name:find("recurring", 1, true)
			or name:find("wrapper", 1, true)) and not name:find("unable", 1, true) and true or false
	end
	return false
end

-- The objectives you haven't finished, in lower case (made as needed, again
-- when the quest log changes).
local objectives

local function Objectives()
	if objectives then
		return objectives
	end
	objectives = {}
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetQuestIDForLogIndex and log.GetQuestObjectives) then
		return objectives
	end
	pcall(function()
		for index = 1, log.GetNumQuestLogEntries() or 0 do
			local questID = log.GetQuestIDForLogIndex(index)
			for _, objective in ipairs(type(questID) == "number" and log.GetQuestObjectives(questID) or {}) do
				local text = objective.text
				if not objective.finished and type(text) == "string" and Known(text) then
					objectives[#objectives + 1] = text:lower()
				end
			end
		end
	end)
	return objectives
end

-- Whether a quest you're on needs something picked up or used here: an
-- objective you haven't finished that's an object to use or an item to
-- collect, for a quest on the map you're in (any map where the game won't
-- say, or says no quest at all is here: quests without map data), and not
-- more than NEAR_YARDS from its area where the game says how far (a delve
-- quest's "complete the delve" is an object objective too). Soft targeting is
-- only held while one does: it picks every corpse and trainer you walk past
-- too, the game outlining each. Made as needed, again when the quest log or
-- zone changes and every RECHECK_EVERY seconds (as you move). The quest (for
-- the debug line) or nil.
local NEEDS_GLOW = { object = true, item = true }
local NEAR_YARDS, RECHECK_EVERY = 300, 5
local needed -- false: none
local neededAt = 0

local function Near(questID)
	local log = C_QuestLog
	if not log.GetDistanceSqToQuest then
		return true
	end
	local ok, distanceSq = pcall(log.GetDistanceSqToQuest, questID)
	return not (ok and type(distanceSq) == "number" and Known(distanceSq) and distanceSq > NEAR_YARDS * NEAR_YARDS)
end

-- Delve quests (retail's Delver's Call: "... delve completed" is an object
-- objective): by the quest's tag, or (where the game won't tag it) the word
-- in the objective's text.
local function DelveQuest(questID, objective)
	local log, tags = C_QuestLog, Enum and Enum.QuestTag
	if log.GetQuestTagInfo and tags and tags.Delve then
		local ok, info = pcall(log.GetQuestTagInfo, questID)
		if ok and type(info) == "table" and Known(info.tagID) and info.tagID == tags.Delve then
			return true
		end
	end
	local text = objective.text
	return type(text) == "string" and Known(text) and text:lower():find("delve", 1, true) ~= nil
end

local function NeededFor()
	if needed ~= nil and GetTime() - neededAt < RECHECK_EVERY then
		return needed or nil
	end
	needed = false
	neededAt = GetTime()
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetQuestIDForLogIndex and log.GetQuestObjectives) then
		return nil
	end
	local elsewhere, anyHere
	pcall(function()
		for index = 1, log.GetNumQuestLogEntries() or 0 do
			local questID = log.GetQuestIDForLogIndex(index)
			if type(questID) == "number" and questID > 0 then
				local here = true
				if log.IsOnMap then
					local ok, onMap = pcall(log.IsOnMap, questID)
					here = not (ok and Known(onMap) and onMap == false)
				end
				anyHere = anyHere or here
				for _, objective in ipairs(log.GetQuestObjectives(questID) or {}) do
					if not objective.finished and NEEDS_GLOW[objective.type] and not DelveQuest(questID, objective) then
						if here and not Near(questID) then
							break
						elseif here then
							needed = questID
						else
							elsewhere = elsewhere or questID
						end
						break
					end
				end
			end
		end
	end)
	if not needed and not anyHere and elsewhere then
		needed = elsewhere
	end
	return needed or nil
end

local function NamedInObjective(unit)
	local ok, name = pcall(UnitName, unit)
	if not (ok and type(name) == "string" and Known(name) and #name > 2) then
		return false
	end
	name = name:lower()
	-- Or its last word, the thing it is ("Lightbloom-Infected Bitterbloom" for
	-- "Bitterblooms burned"), when that's long enough not to match by chance.
	local last = name:match("([%a']+)$")
	if last and #last < 5 then
		last = nil
	end
	for _, text in ipairs(Objectives()) do
		if text:find(name, 1, true) or (last and text:find(last, 1, true)) then
			return true
		end
	end
	return false
end

-- Whether the game's tooltip for it has a quest line (retail lists the
-- objective it counts for under the object's name).
local function QuestInTooltip(unit)
	local info, lineTypes = C_TooltipInfo, Enum and Enum.TooltipDataLineType
	if not (info and info.GetUnit and lineTypes) then
		return false
	end
	local ok, data = pcall(info.GetUnit, unit)
	if not (ok and type(data) == "table" and type(data.lines) == "table") then
		return false
	end
	for _, line in ipairs(data.lines) do
		local kind = line.type
		if Known(kind) and kind ~= nil and (kind == lineTypes.QuestObjective or kind == lineTypes.QuestTitle
			or kind == lineTypes.QuestPlayer) then
			return true
		end
	end
	return false
end

-- Why an object counts (for the debug line), or nil.
local function QuestReason(unit)
	local cursor = CursorOf(unit)
	if QuestCursor(cursor) then
		return "cursor"
	end
	local log = C_QuestLog
	if Ask(log and log.UnitIsRelatedToActiveQuest, unit) then
		return "related"
	end
	if NamedInObjective(unit) then
		return "objective"
	end
	if QuestInTooltip(unit) then
		return "tooltip"
	end
	return nil
end

-- Answers by GUID until the quest log changes.
local answers = {}

local function IsQuestObject(unit)
	local ok, guid = pcall(UnitGUID, unit)
	if not (ok and type(guid) == "string" and Known(guid)) then
		return QuestReason(unit) ~= nil
	end
	if answers[guid] == nil then
		answers[guid] = QuestReason(unit) ~= nil
	end
	return answers[guid]
end

-- An object, not a creature: the game says so, or (older clients) it doesn't
-- "exist" as a unit.
local function IsObject(unit)
	if UnitIsGameObject then
		return Ask(UnitIsGameObject, unit)
	end
	return not Ask(UnitExists, unit)
end

-- The glow: a soft gold light round the object (below its plate) and the
-- quest mark over it, drawn whatever the plate's own fade (CineMode fades it).
-- The light only for LIGHT_TIME seconds per object, then it fades out over
-- LIGHT_FADE (it hides a small object), the mark staying.
local LIGHT_TIME, LIGHT_FADE = 2.5, 1
local glow = CreateFrame("Frame")
glow:Hide()
glow:SetSize(110, 110)
glow:SetIgnoreParentAlpha(true)
do
	local lightFrame = CreateFrame("Frame", nil, glow)
	lightFrame:SetAllPoints()
	glow.light = lightFrame
	local light = lightFrame:CreateTexture(nil, "BACKGROUND")
	light:SetAllPoints()
	light:SetTexture("Interface\\Cooldown\\star4")
	light:SetBlendMode("ADD")
	light:SetVertexColor(1, 0.82, 0.2)
	local mark = glow:CreateTexture(nil, "OVERLAY")
	mark:SetSize(24, 24)
	mark:SetPoint("BOTTOM", glow, "TOP", 0, -30)
	ns.SetQuestMark(mark)
	glow.mark = mark
	local pulse = light:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")
	glow.pulse = pulse
end
glow:SetScript("OnUpdate", function(self)
	local left = LIGHT_TIME + LIGHT_FADE - (GetTime() - (self.litAt or 0))
	local alpha = math.max(0, math.min(1, left / LIGHT_FADE))
	if self.light:GetAlpha() ~= alpha then
		self.light:SetAlpha(alpha)
	end
end)

-- guid: the object's, so the light comes back only for another one (kept
-- after the glow goes: back on the same object, no light again).
local function GlowOn(plate, guid)
	if glow.guid ~= guid or (not guid and glow.plate ~= plate) then
		glow.guid = guid
		glow.litAt = GetTime()
	end
	if glow.plate ~= plate then
		glow.plate = plate
		glow:SetParent(plate)
		glow:SetIgnoreParentAlpha(true)
		glow:SetFrameLevel((plate.GetFrameLevel and plate:GetFrameLevel() or 0) + 10)
		glow:ClearAllPoints()
		glow:SetPoint("CENTER", plate, "CENTER", 0, -40)
		-- Retail gives objects' plates their name, where the mark would sit:
		-- the mark goes just above it (the name itself hidden: see UpdateIcon).
		local mark, name = glow.mark, plate.UnitFrame and plate.UnitFrame.name
		mark:ClearAllPoints()
		if not (ns.isRetail and type(name) == "table" and pcall(mark.SetPoint, mark, "BOTTOM", name, "TOP", 0, 2)) then
			mark:ClearAllPoints()
			mark:SetPoint("BOTTOM", glow, "TOP", 0, -30)
		end
	end
	if not glow:IsShown() then
		glow:Show()
		glow.pulse:Play()
	end
end

local function GlowOff()
	if glow:IsShown() then
		glow.pulse:Stop()
		glow:Hide()
	end
	glow.plate = nil
	glow:SetParent(nil)
end

-- Whether an object glows now (Quest Vision's part of the minimap button's glow).
function ns.QuestGlowShown()
	return glow:IsShown() and true or false
end

local function Wanted()
	return ns.db and ns.QuestVisionSetting("questObjectGlow") and NeededFor() and true or false
end

-- The object soft targeting picked and its plate, if it has one: plate, or nil.
local function SoftPlate()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return nil
	end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, SOFT)
	return ok and plate or nil
end

-- Soft targeting switches between objects as you walk and turn, so the glow
-- stays on the object it lit up (lock) for at least LOCK_TIME seconds, and
-- after that until you've moved LOCK_YARDS from where it lit up (by time
-- alone where the game won't say where you are). It lets go sooner when that
-- object loses its plate (looted, out of range) or stops counting for a quest.
local LOCK_TIME, LOCK_YARDS = 2, 5
local lock -- { guid, at, x, y }

local function Position()
	if not UnitPosition then
		return nil
	end
	local ok, y, x = pcall(UnitPosition, "player")
	if ok and type(x) == "number" and type(y) == "number" and Known(x) and Known(y) then
		return x, y
	end
	return nil
end

local function GUIDOf(unit)
	local ok, guid = pcall(UnitGUID, unit)
	return ok and type(guid) == "string" and Known(guid) and guid or nil
end

-- The plate the locked object has now, and its unit, if any.
local function LockedPlate()
	local guid = lock.guid
	if GUIDOf(SOFT) == guid then
		return SoftPlate(), SOFT
	end
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken
		if unit and GUIDOf(unit) == guid then
			return plate, unit
		end
	end
	return nil
end

local function LockReleased()
	if GetTime() - lock.at < LOCK_TIME then
		return false
	end
	local x, y = Position()
	if not (x and lock.x) then
		return true
	end
	local dx, dy = x - lock.x, y - lock.y
	return dx * dx + dy * dy >= LOCK_YARDS * LOCK_YARDS
end

local function Usable(plate)
	return plate and not (plate.IsForbidden and plate:IsForbidden())
end

-- Your own value for a game setting (put back once the glow lets go).
local function Own(cvar)
	local saved = ns.db.savedCVars[cvar]
	if saved ~= nil then
		return saved
	end
	return GetCVar(cvar)
end

-- The soft targeting held above gives a plate to whatever it picks, a dead
-- mob you can loot included: that plate stays up until you loot it. While
-- the settings are ours, a dead unit's plate is hidden (Effects asks here),
-- and so is a living one's that only got its plate from us (an NPC you face,
-- with your own plates for its kind off): the glow only needs objects'.
function ns.SoftPlateHidden(unit)
	if not (CVARS.active and unit and Ask(UnitIsUnit, unit, SOFT)) then
		return false
	end
	if Ask(UnitIsDead, unit) then
		return true
	end
	return Own("SoftTargetNameplateInteract") ~= "1" and not IsObject(unit)
		and not (ns.PlateShownAnyway and ns.PlateShownAnyway(unit))
end

-- The soft plate hidden last tick: refreshed as one turns up or goes, so
-- Effects hides it (or gives it back) at once.
local hiddenSoftPlate

local function UpdateHiddenSoftPlate()
	local plate = SoftPlate()
	local unit = plate and plate.namePlateUnitToken
	if not (unit and ns.SoftPlateHidden(unit)) then
		plate = nil
	end
	if plate == hiddenSoftPlate then
		return
	end
	local old = hiddenSoftPlate
	hiddenSoftPlate = plate
	for _, changed in ipairs({ old or false, plate or false }) do
		if changed and ns.RefreshPlate and not (changed.IsForbidden and changed:IsForbidden()) then
			ns.RefreshPlate(changed, changed.namePlateUnitToken)
		end
	end
end

-- The game's icon over what soft targeting picked, or your target when it's
-- something to interact with (the plate's SoftTargetFrame: a gear, a herb, a
-- hearthstone, a gamepad button...), on any plate.
-- While the settings are ours it shows only where your own settings would
-- have shown it: soft targeting on for the way you're playing (keyboard and
-- mouse, or gamepad) and the icon on for that kind of thing. Elsewhere it's
-- hidden (quest objects have our mark). [icon frame] = true while hidden by us.
-- Likewise the name retail gives an object's plate: hidden unless your own
-- settings give objects plates (kept in hiddenIcons too).
local hiddenIcons = {}

local function OwnIconShows(object)
	local mode = tonumber(Own("SoftTargetInteract")) or 0
	local pad = ns.IsGamePadOn and ns.IsGamePadOn() or false
	local covered = mode == 3 or (mode == 1 and pad) or (mode == 2 and not pad)
	return covered and Own(object and "SoftTargetIconGameObject" or "SoftTargetIconInteract") == "1"
end

local function IconOf(plate)
	local frame = plate and plate.UnitFrame and plate.UnitFrame.SoftTargetFrame
	if type(frame) == "table" and frame.SetAlpha and not (frame.IsForbidden and frame:IsForbidden()) then
		return frame
	end
	return nil
end

-- A plate's unit (some clients only give it on the unit frame).
local function UnitOf(plate)
	return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

-- The game sets an icon's alpha back as it updates it (a dead mob's skinning
-- icon flashed when hidden only each check): the hidden ones every frame.
local iconKeeper = CreateFrame("Frame")
iconKeeper:Hide()
iconKeeper:SetScript("OnUpdate", function(self)
	if not next(hiddenIcons) then
		self:Hide()
		return
	end
	for frame in pairs(hiddenIcons) do
		frame:SetAlpha(0)
	end
end)

local hideNow = {}
local function UpdateIcon()
	wipe(hideNow)
	if CVARS.active then
		-- (Your own settings decide objects and creatures apart: each asked once.)
		local shows = {}
		local ownPlates = Own("SoftTargetNameplateInteract") == "1"
		for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
			local frame = IconOf(plate)
			local unit = UnitOf(plate)
			local object = unit and IsObject(unit)
			if frame and unit then
				if shows[object] == nil then
					shows[object] = OwnIconShows(object)
				end
				if not shows[object] then
					hideNow[frame] = true
				end
			end
			local name = object and not ownPlates and plate.UnitFrame and plate.UnitFrame.name
			if type(name) == "table" and name.SetAlpha and not (name.IsForbidden and name:IsForbidden()) then
				hideNow[name] = true
			end
		end
	end
	for frame in pairs(hiddenIcons) do
		if not hideNow[frame] then
			hiddenIcons[frame] = nil
			frame:SetAlpha(1)
		end
	end
	for frame in pairs(hideNow) do
		hiddenIcons[frame] = true
		frame:SetAlpha(0)
	end
	iconKeeper:SetShown(next(hiddenIcons) ~= nil)
end

-- The held settings written again where the game changed them (once a
-- second; nameplate ones out of fights).
local KEEP_EVERY = 1
local keepAt = 0
local function KeepHeld()
	local now = GetTime()
	if not CVARS.active or now < keepAt then
		return
	end
	keepAt = now + KEEP_EVERY
	for cvar, value in pairs(CVARS.values) do
		local current = GetCVar(cvar)
		if current ~= nil and current ~= value and tonumber(current) ~= tonumber(value)
			and not (cvar:find("^nameplate") and InCombatLockdown()) then
			SetCVar(cvar, value)
		end
	end
end

-- "Your own" interact settings saved as exactly ours (lost to an earlier
-- build, or saved again after one): the game's defaults go back instead, or
-- unticking would leave soft targeting and its icons on.
local HEAL = { "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
	"SoftTargetNameplateInteract", "SoftTargetIconGameObject" }
local healed = false

local function HealSaved()
	if healed or not CVARS.active then
		return
	end
	healed = true
	local saved = ns.db.savedCVars
	local Default = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
	if not Default then
		return
	end
	for _, cvar in ipairs(HEAL) do
		if saved[cvar] == nil or tonumber(saved[cvar]) ~= tonumber(CVARS.values[cvar]) then
			return
		end
	end
	for _, cvar in ipairs(HEAL) do
		local ok, value = pcall(Default, cvar)
		if ok and value ~= nil then
			ns.Log("cvar", ("%s: saved value was the glow's, the game's default (%s) goes back"):format(cvar,
				tostring(value)))
			saved[cvar] = value
		end
	end
end

local function Update()
	local on = Wanted()
	-- Retail draws the icon over a creature-like interact pick (a hand over the
	-- shears on a table) in the world, with no plate to hide it on: held as
	-- your own settings would show it (followed as gamepad mode changes).
	if ns.isRetail then
		CVARS.values.SoftTargetIconInteract = OwnIconShows(false) and "1" or "0"
	end
	ns.ApplyCVarSet(CVARS, on)
	HealSaved()
	KeepHeld()
	UpdateHiddenSoftPlate()
	UpdateIcon()
	if not on then
		lock = nil
		GlowOff()
		return
	end
	if lock then
		local plate, unit = LockedPlate()
		if Usable(plate) and IsQuestObject(unit) and not LockReleased() then
			GlowOn(plate, lock.guid)
			return
		end
		lock = nil
	end
	local plate = SoftPlate()
	if Usable(plate) and IsObject(SOFT) and IsQuestObject(SOFT) then
		local guid = GUIDOf(SOFT)
		GlowOn(plate, guid)
		if guid then
			local x, y = Position()
			lock = { guid = guid, at = GetTime(), x = x, y = y }
		end
	else
		GlowOff()
	end
end
ns.UpdateQuestGlow = Update

local ticker = CreateFrame("Frame")
ticker.at = 0
ticker:SetScript("OnUpdate", function(self)
	local now = GetTime()
	if now < self.at then
		return
	end
	self.at = now + CHECK_EVERY
	if Wanted() or CVARS.active or glow:IsShown() or next(hiddenIcons) then
		Update()
	end
end)

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD", "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED",
	"ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_SOFT_INTERACT_CHANGED" or event == "NAME_PLATE_UNIT_ADDED" then
		-- At once: the game has just shown the icon on the new plate (its own
		-- handler runs first), and soft targeting can hop between several
		-- corpses a second, each hop a flash if left to the next frame.
		if Wanted() or CVARS.active then
			Update()
		end
		ticker.at = 0 -- (and looked at again on the next frame)
		return
	end
	wipe(answers)
	objectives = nil
	needed = nil
end)

-- /cine debug iconwatch: for 30 seconds, logs each plate's game icon as it
-- changes (shown, alpha, hidden by us), checked every frame, with the plate
-- events, to see when an icon we hide still shows.
local function Text(fn, ...)
	local ok, value = pcall(fn, ...)
	if not ok then
		return "err"
	end
	if not Known(value) then
		return "secret"
	end
	return type(value) == "number" and ("%.2f"):format(value) or tostring(value)
end

local iconWatch
function ns.StartIconWatch()
	if iconWatch then
		iconWatch:Hide()
	end
	local watch = iconWatch or CreateFrame("Frame")
	iconWatch = watch
	watch.untilAt = GetTime() + 30
	watch.last = {}
	watch.lastSoft = nil
	local function Log(text)
		ns.Log("iconwatch", ("%.3f %s"):format(GetTime(), text))
	end
	watch:UnregisterAllEvents()
	for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_SOFT_INTERACT_CHANGED",
		"CVAR_UPDATE" }) do
		pcall(watch.RegisterEvent, watch, event)
	end
	watch:SetScript("OnEvent", function(_, event, arg1, arg2)
		if event == "CVAR_UPDATE" then
			Log(("CVAR_UPDATE %s = %s"):format(tostring(arg1), tostring(arg2)))
			return
		end
		local x, y = Position()
		Log(("%s %s %s (%s) facing=%s at=%s"):format(event, tostring(arg1), tostring(arg2), Text(UnitName, SOFT),
			GetPlayerFacing and Text(GetPlayerFacing) or "?",
			x and ("%.1f,%.1f"):format(x, y) or "?"))
	end)
	watch:SetScript("OnUpdate", function(self)
		if GetTime() > self.untilAt then
			self:Hide()
			self:UnregisterAllEvents()
			Log("done")
			ns.Print("icon watch: done (/reload to write the log)")
			return
		end
		-- What soft targeting has picked (plate or not) and the settings it goes by.
		local okPlate, softPlate = pcall(C_NamePlate.GetNamePlateForUnit, SOFT)
		local soft = ("soft target: %s dead=%s plate=%s glow=%s | SoftTargetInteract=%s"
			.. " SoftTargetNameplateInteract=%s SoftTargetIconInteract=%s"):format(Text(UnitName, SOFT),
			Text(UnitIsDead, SOFT), okPlate and softPlate and tostring(UnitOf(softPlate)) or "no",
			tostring(glow:IsShown()), tostring(GetCVar("SoftTargetInteract")),
			tostring(GetCVar("SoftTargetNameplateInteract")), tostring(GetCVar("SoftTargetIconInteract")))
		if self.lastSoft ~= soft then
			self.lastSoft = soft
			Log(soft)
		end
		local seen = {}
		for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
			local frame = IconOf(plate)
			local unit = UnitOf(plate)
			if frame then
				seen[frame] = true
				local icon = frame.Icon
				local state = ("%s %s dead=%s soft=%s object=%s | frame shown=%s alpha=%s effective=%s ignoreParent=%s"
					.. " ours=%s | icon shown=%s alpha=%s | plate alpha=%s"):format(tostring(unit),
					unit and Text(UnitName, unit) or "-", unit and Text(UnitIsDead, unit) or "-",
					unit and Text(UnitIsUnit, unit, SOFT) or "-", unit and tostring(IsObject(unit)) or "-",
					Text(frame.IsShown, frame), Text(frame.GetAlpha, frame), Text(frame.GetEffectiveAlpha, frame),
					frame.IsIgnoringParentAlpha and Text(frame.IsIgnoringParentAlpha, frame) or "?",
					tostring(hiddenIcons[frame] or false),
					icon and Text(icon.IsShown, icon) or "-", icon and Text(icon.GetAlpha, icon) or "-",
					plate.UnitFrame and Text(plate.UnitFrame.GetAlpha, plate.UnitFrame) or "-")
				if self.last[frame] ~= state then
					self.last[frame] = state
					Log(tostring(frame):sub(-6) .. " " .. state)
				end
			end
		end
		for frame in pairs(self.last) do
			if not seen[frame] then
				self.last[frame] = nil
				Log(tostring(frame):sub(-6) .. " gone")
			end
		end
	end)
	watch:Show()
	Log("start")
	ns.Print("icon watch: logging nameplate icons for 30 seconds (face a dead mob you can skin)")
end

-- /cine debug questmob: the unit under your mouse, to tell quest mobs you can
-- interact with (talk to) from ones you can't (a quest item used on them):
-- the cursor the game would give it, the quest checks, its tooltip's quest
-- lines and the item each of those quests gives you to use.
function ns.PrintQuestMobDebug()
	local unit = "mouseover"
	local okName, name = pcall(UnitName, unit)
	if not (okName and name ~= nil) then
		ns.Print("questmob: nothing under your mouse (hover a unit, then type the command)")
		return
	end
	local cursor = CursorOf(unit)
	local log = C_QuestLog
	ns.Print(("questmob: %s, cursor=%s (quest cursor: %s), related=%s, object=%s, dead=%s, can attack=%s"):format(
		Known(name) and tostring(name) or "(secret)", tostring(cursor), tostring(QuestCursor(cursor)),
		tostring(Ask(log and log.UnitIsRelatedToActiveQuest, unit)), tostring(IsObject(unit)),
		Text(UnitIsDead, unit), Text(UnitCanAttack, "player", unit)))
	ns.Print(("  quest mob=%s, can't interact (in progress mark)=%s, in progress atlas=%s"):format(
		tostring(ns.IsQuestMob(unit)), tostring(ns.IsPassiveQuestMob(unit)), tostring(ns.QuestProgressAtlas())))
	local info, lineTypes = C_TooltipInfo, Enum and Enum.TooltipDataLineType
	local ok, data = pcall(info and info.GetUnit or error, unit)
	if not (ok and type(data) == "table" and type(data.lines) == "table" and lineTypes) then
		ns.Print("  tooltip: unreadable")
		return
	end
	-- Quest titles in the log, to find each tooltip quest's log index and item.
	local byTitle = {}
	for index = 1, log.GetNumQuestLogEntries and log.GetNumQuestLogEntries() or 0 do
		local okInfo, quest = pcall(log.GetInfo, index)
		if okInfo and type(quest) == "table" and not quest.isHeader and type(quest.title) == "string" then
			byTitle[quest.title] = { index = index, questID = quest.questID }
		end
	end
	for _, line in ipairs(data.lines) do
		local kind, text = line.type, line.leftText
		if Known(kind) and (kind == lineTypes.QuestTitle or kind == lineTypes.QuestObjective
			or kind == lineTypes.QuestPlayer) then
			local readable = Known(text) and type(text) == "string"
			local extra = ""
			local quest = readable and byTitle[text]
			if quest then
				local item, texture
				local SpecialItem = _G.GetQuestLogSpecialItemInfo
				if SpecialItem then
					local okItem, link, icon = pcall(SpecialItem, quest.index)
					item, texture = okItem and link, okItem and icon
				end
				extra = (" | quest %s, its item: %s%s"):format(tostring(quest.questID), tostring(item or "none"),
					texture and (" (icon " .. tostring(texture) .. ")") or "")
			end
			ns.Print(("  tooltip line type %s: %s%s"):format(tostring(kind), readable and text or "(secret)", extra))
		end
	end
end

-- /cine debug questglow: what soft targeting has picked and why it glows or not.
function ns.PrintQuestGlowDebug()
	local cvars = {}
	for _, name in ipairs({ "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetNameplateInteract",
		"SoftTargetIconGameObject" }) do
		cvars[#cvars + 1] = name .. "=" .. tostring(GetCVar(name))
	end
	ns.Print(("quest object glow: %s, settings held: %s (%s)"):format(Wanted() and "on" or "off",
		tostring(CVARS.active or false), table.concat(cvars, ", ")))
	local questID = NeededFor()
	local title = questID and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	ns.Print(questID and ("needed for: %s (%s), an object or item objective on this map"):format(
		tostring(title), questID) or "not needed: no object or item objective left for a quest on this map")
	if questID then
		local okDistance, distanceSq, onContinent = pcall(C_QuestLog.GetDistanceSqToQuest or error, questID)
		ns.Print(("  distance to its area: %s (on this continent: %s)"):format(
			okDistance and type(distanceSq) == "number" and ("%.0f yards"):format(math.sqrt(distanceSq)) or "unknown",
			tostring(okDistance and onContinent)))
		local okTag, tag = pcall(C_QuestLog.GetQuestTagInfo or error, questID)
		ns.Print(("  tag: %s"):format(okTag and type(tag) == "table" and ("%s (%s)"):format(tostring(tag.tagName),
			tostring(tag.tagID)) or "none"))
		for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
			ns.Print(("  objective: %s, type %s, finished %s"):format(tostring(objective.text), tostring(objective.type),
				tostring(objective.finished)))
		end
	end
	local x = Position()
	ns.Print(lock and ("locked for %.1fs (your position %s)"):format(GetTime() - lock.at,
		x and (lock.x and "known" or "unknown at lock") or "unknown: by time alone") or "not locked")
	local okTarget, targetPlate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	local targetIcon = okTarget and IconOf(targetPlate)
	ns.Print(("your target's plate: %s (unit %s), its icon: %s"):format(okTarget and targetPlate and "yes" or "no",
		tostring(targetPlate and UnitOf(targetPlate)),
		not targetIcon and "none" or hiddenIcons[targetIcon] and "hidden by us" or "left alone"))
	ns.Print(("your own: SoftTargetInteract=%s, SoftTargetIconInteract=%s, SoftTargetIconGameObject=%s, " ..
		"gamepad mode=%s: creature icons %s, object icons %s"):format(tostring(Own("SoftTargetInteract")),
		tostring(Own("SoftTargetIconInteract")), tostring(Own("SoftTargetIconGameObject")),
		tostring(ns.IsGamePadOn and ns.IsGamePadOn() or false), OwnIconShows(false) and "shown" or "hidden",
		OwnIconShows(true) and "shown" or "hidden"))
	local okName, name = pcall(UnitName, SOFT)
	if not (okName and name ~= nil) then
		ns.Print("nothing soft targeted")
		return
	end
	local cursor = CursorOf(SOFT)
	local plate = SoftPlate()
	local okAlpha, alpha = pcall(function() return ("%.2f"):format(plate.UnitFrame:GetAlpha()) end)
	local icon = plate and plate.UnitFrame and plate.UnitFrame.SoftTargetFrame
	ns.Print(("soft target: %s, object=%s, plate=%s, cursor=%s, reason=%s, glowing=%s"):format(
		Known(name) and tostring(name) or "(secret)", tostring(IsObject(SOFT)),
		plate and ("yes, alpha " .. (okAlpha and alpha or "?")) or "no",
		tostring(cursor), tostring(QuestReason(SOFT)), tostring(glow:IsShown())))
	local known = 0
	for _ in pairs(QuestCursorFiles()) do
		known = known + 1
	end
	ns.Print(("  each check: cursor=%s (%d quest cursors known), related=%s, objective=%s, tooltip=%s"):format(
		tostring(QuestCursor(cursor)), known, tostring(Ask(C_QuestLog.UnitIsRelatedToActiveQuest, SOFT)),
		tostring(NamedInObjective(SOFT)), tostring(QuestInTooltip(SOFT))))
	-- The mark: where it is against the plate and its name, and what it shows.
	local mark = glow.mark
	local nameText = plate and plate.UnitFrame and plate.UnitFrame.name
	local function Rect(region)
		local ok, left, bottom, width, height = pcall(region.GetRect, region)
		return ok and Known(left) and left and ("%.0f,%.0f %.0fx%.0f"):format(left, bottom, width, height) or "?"
	end
	ns.Print(("mark: visible=%s alpha=%s atlas=%s texture=%s at %s | glow at %s level %s | plate at %s level %s"
		.. " | name at %s"):format(Text(mark.IsVisible, mark), Text(mark.GetEffectiveAlpha, mark),
		tostring(mark.GetAtlas and mark:GetAtlas()), tostring(mark:GetTexture()), Rect(mark), Rect(glow),
		Text(glow.GetFrameLevel, glow), plate and Rect(plate) or "-",
		plate and Text(plate.GetFrameLevel, plate) or "-", type(nameText) == "table" and nameText.GetRect and Rect(nameText) or "-"))
	ns.Print(("game's icon: %s, your own settings would show it: %s"):format(
		type(icon) ~= "table" and "none" or hiddenIcons[icon] and "hidden by us" or "left alone",
		tostring(OwnIconShows(IsObject(SOFT)))))
end
