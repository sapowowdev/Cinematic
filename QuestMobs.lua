-- Cinematic: which units count for a quest objective you haven't finished
-- (a mob to kill, an NPC to talk to). For the Vision page's Quest Vision: their
-- plates kept up (see Effects), a quest icon on them (see PlateParts) and on the target frame.
-- Read from the unit's tooltip lines without showing the tooltip
-- (C_TooltipInfo.GetUnit): a quest objective line ("5/7 Thistle Boar slain")
-- not yet done. Where the lines can't be read, C_QuestLog.UnitIsRelatedToActiveQuest
-- (which can't tell a finished objective). Unreadable (secret) counts as no.
local _, ns = ...

-- Answers by GUID: true/false and when they were read. A yes holds until the
-- quest log changes; a no is read again after a while (a unit's tooltip lines
-- can be missing for a moment after its plate appears).
local answers = {} -- [guid] = { quest = bool, at = time }
local RECHECK_NO = 2
-- The game drops a unit's quest line a moment after the quest log changes
-- (an NPC you've just questioned): answers read within SETTLE seconds of a
-- change are read once more after it.
local SETTLE = 2
local settleAt = 0
local passiveAnswers = {} -- [guid] = bool (see IsPassiveQuestMob)

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

-- Whether an objective line's text says it's done: "7/7" or "100%".
local function TextDone(text)
	if type(text) ~= "string" or not Known(text) then
		return nil
	end
	local have, need = text:match("(%d+)%s*/%s*(%d+)")
	if have then
		return tonumber(have) >= tonumber(need)
	end
	local percent = text:match("(%d+)%%")
	if percent then
		return tonumber(percent) >= 100
	end
	return nil
end

-- A friendly NPC whose only open objective is a progress bar ("Rout the
-- Lightbloom Frenzy", 85%) gets no mark: the bar moves for the enemies you
-- kill around it, and there's nothing to do with the NPC itself. Bar
-- objectives are told by their text, as the quest log has them (rebuilt as
-- it changes); a line that's just a percentage is one too.
local barTexts -- [normalized text] = true, or nil until needed

local function Normalize(text)
	text = text:lower():gsub("%d+%s*/%s*%d+", ""):gsub("%d+%s*%%", ""):gsub("[%(%)%-:]", "")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function BarTexts()
	if barTexts then
		return barTexts
	end
	barTexts = {}
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then
		return barTexts
	end
	pcall(function()
		for i = 1, log.GetNumQuestLogEntries() do
			local info = log.GetInfo(i)
			local questID = info and not info.isHeader and info.questID
			for _, objective in ipairs(type(questID) == "number" and log.GetQuestObjectives(questID) or {}) do
				local text = objective.text
				if objective.type == "progressbar" and type(text) == "string" and Known(text) then
					barTexts[Normalize(text)] = true
				end
			end
		end
	end)
	return barTexts
end

local function IsBarLine(text)
	if type(text) ~= "string" or not Known(text) then
		return false
	end
	if text:find("%d+%s*/%s*%d+") then
		return false -- (counted: not a bar)
	end
	local key = Normalize(text)
	return key == "" or BarTexts()[key] == true
end

local function IsFriendly(unit)
	local ok, can = pcall(UnitCanAttack, "player", unit)
	return ok and Known(can) and not can
end

-- true / false from the tooltip lines, or nil when they can't say.
local function FromTooltip(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return nil
	end
	local objective = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
	local friendly = IsFriendly(unit)
	local ok, found = pcall(function()
		local data = C_TooltipInfo.GetUnit(unit)
		local lines = data and data.lines
		if type(lines) ~= "table" then
			return nil
		end
		for _, line in ipairs(lines) do
			local text = line.leftText
			if objective and line.type == objective then
				local done = line.completed
				if done == nil then
					done = TextDone(text)
				end
				if not done and not (friendly and IsBarLine(text)) then
					return true
				end
			elseif type(text) == "string" and Known(text) and text:find("^%s*%-%s*%d+%s*/%s*%d+") then
				-- (Clients without line kinds: " - 5/7 Thistle Boar slain".)
				if not TextDone(text) then
					return true
				end
			end
		end
		return false
	end)
	if ok then
		return found
	end
	return nil
end

local function Read(unit)
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if not ok or not Known(isPlayer) or isPlayer then
		return false
	end
	local found = FromTooltip(unit)
	if found ~= nil then
		return found
	end
	local related = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
	if related then
		local okRelated, yes = pcall(related, unit)
		return okRelated and Known(yes) and yes and true or false
	end
	return false
end

-- Whether a unit counts for a quest objective you haven't finished.
function ns.IsQuestMob(unit)
	if not unit then
		return false
	end
	-- (Asked every time, not kept: a mob killed with others in the fight
	-- doesn't always change the quest log, and its yes would keep its plate up.)
	local okDead, dead = pcall(UnitIsDead, unit)
	if okDead and Known(dead) and dead then
		return false
	end
	local ok, guid = pcall(UnitGUID, unit)
	if not (ok and type(guid) == "string" and Known(guid)) then
		return Read(unit)
	end
	local now = GetTime()
	local answer = answers[guid]
	if answer and (answer.at >= settleAt or now < settleAt) and (answer.quest or now - answer.at < RECHECK_NO) then
		return answer.quest
	end
	answer = answer or {}
	answer.quest, answer.at = Read(unit), now
	answers[guid] = answer
	return answer.quest
end

-- The quest log changed (progress made, a quest taken or handed in): every
-- answer is read again.
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function()
	wipe(answers)
	wipe(passiveAnswers)
	settleAt = GetTime() + SETTLE
	barTexts = nil
end)

-- The golden exclamation mark shown for them (plates' Quest Icon row, the
-- target frame's, below, and Quest Glow's): the map's sharp quest mark, or the
-- old gossip one with Forever's Character Models on Standard Definition (its
-- proxy setting is true then) or where a client lacks that atlas. Marks follow
-- the setting as it changes.
ns.QUEST_MOB_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"
local MODELS_SETTING = "PROXY_CHARACTER_MODELS_TOGGLE"
local marks = setmetatable({}, { __mode = "k" })

local function StandardModels()
	local ok, value = pcall(function()
		return Settings.GetSetting(MODELS_SETTING):GetValue()
	end)
	return ok and value == true
end

local function HasAtlas(name)
	return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- A quest mob you can't do anything with yourself (friendly, and the game
-- gives it just the plain pointer: one you eavesdrop on or protect) gets the
-- quest log's "in progress" mark (gold, three dots) instead: part of a quest
-- you're on, nothing to click. The atlas as retail's quest log picks it, else
-- by name; where there's none, the ! greyed.
local PROGRESS_ATLASES = { "Quest-In-Progress-Icon-yellow", "QuestInProgress", "Quest-InProgress" }
local progressAtlas -- false: none

function ns.QuestProgressAtlas()
	if progressAtlas ~= nil then
		return progressAtlas or nil
	end
	progressAtlas = false
	local util = _G.QuestUtil
	if util and util.GetQuestIconActive then
		local ok, atlas = pcall(util.GetQuestIconActive, false)
		if ok and HasAtlas(atlas) then
			progressAtlas = atlas
			return atlas
		end
	end
	for _, name in ipairs(PROGRESS_ATLASES) do
		if HasAtlas(name) then
			progressAtlas = name
			break
		end
	end
	return progressAtlas or nil
end

local function PaintMark(texture)
	local passive = marks[texture] == "passive"
	texture:SetDesaturated(false)
	texture:SetVertexColor(1, 1, 1)
	local atlas = passive and not StandardModels() and ns.QuestProgressAtlas()
	if atlas and pcall(texture.SetAtlas, texture, atlas) then
		return
	end
	if StandardModels() or not (texture.SetAtlas and HasAtlas("QuestNormal")
		and pcall(texture.SetAtlas, texture, "QuestNormal")) then
		texture:SetTexture(ns.QUEST_MOB_TEXTURE)
		texture:SetTexCoord(0, 1, 0, 1) -- undo the atlas's, if it had one
	end
	if passive then
		texture:SetDesaturated(true)
		texture:SetVertexColor(0.8, 0.8, 0.8)
	end
end

-- The plain pointer, as a texture reads it back (file numbers, made once) or
-- by name (retail's crosshair atlases: "Crosshair_Point_64").
local cursorProbe = CreateFrame("Frame"):CreateTexture()
local pointerFiles

local function IsPointer(cursor)
	if type(cursor) == "string" then
		return cursor:lower():find("point", 1, true) ~= nil
	end
	if type(cursor) ~= "number" then
		return false
	end
	if not pointerFiles then
		pointerFiles = {}
		for _, path in ipairs({ "Interface\\Cursor\\Point", "Interface\\Cursor\\Crosshair\\Point" }) do
			cursorProbe:SetTexture(nil)
			pcall(cursorProbe.SetTexture, cursorProbe, path)
			local file = cursorProbe:GetTexture()
			if type(file) == "number" and Known(file) then
				pointerFiles[file] = true
			end
		end
	end
	return pointerFiles[cursor] or false
end

-- The cursor the game would show over the unit (file or atlas), or nil.
function ns.UnitCursor(unit)
	if not SetUnitCursorTexture then
		return nil
	end
	cursorProbe:SetTexture(nil)
	if not pcall(SetUnitCursorTexture, cursorProbe, unit, nil, true) then
		return nil
	end
	local file = cursorProbe:GetTexture()
	if file ~= nil and Known(file) then
		return file
	end
	local atlas = cursorProbe.GetAtlas and cursorProbe:GetAtlas()
	if atlas ~= nil and Known(atlas) then
		return atlas
	end
	return nil
end

-- Whether a quest mob is one you can't do anything with (see above). By GUID
-- until the quest log changes (passiveAnswers, at the top). Where the game
-- won't say: no (the !).
function ns.IsPassiveQuestMob(unit)
	if not (unit and IsFriendly(unit)) then
		return false
	end
	local ok, guid = pcall(UnitGUID, unit)
	guid = ok and type(guid) == "string" and Known(guid) and guid or nil
	if guid and passiveAnswers[guid] ~= nil then
		return passiveAnswers[guid]
	end
	local passive = IsPointer(ns.UnitCursor(unit))
	if guid then
		passiveAnswers[guid] = passive
	end
	return passive
end

local watching
-- passive: the "in progress" mark (see above), else the !. Painted again only
-- when that changes.
function ns.SetQuestMark(texture, passive)
	local kind = passive and "passive" or "normal"
	if marks[texture] == kind then
		return
	end
	marks[texture] = kind
	PaintMark(texture)
	if not watching and Settings and Settings.SetOnValueChangedCallback then
		watching = true
		pcall(Settings.SetOnValueChangedCallback, MODELS_SETTING, function()
			for mark in pairs(marks) do
				PaintMark(mark)
			end
		end)
	end
end

-- The target frame's quest icon (targetQuestIcon, Vision page's Quest Vision): the
-- same mark left of the target frame's health bar while your target is a
-- quest mob. Part of the frame, so it fades with it. Looked at again as the
-- target or the quest log changes, and now and then (progress can land a
-- moment after the event).
local targetIcon
local function TargetIcon()
	local frame = _G.TargetFrame
	if targetIcon or not (frame and frame.CreateTexture) then
		return targetIcon
	end
	local bar = frame.healthbar or frame.HealthBar or frame
	targetIcon = CreateFrame("Frame", nil, frame)
	targetIcon:SetSize(24, 24)
	if bar == frame then
		targetIcon:SetPoint("RIGHT", frame, "LEFT", 4, 0)
	else
		targetIcon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
	end
	targetIcon:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	local texture = targetIcon:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints()
	ns.SetQuestMark(texture)
	targetIcon.texture = texture
	return targetIcon
end

function ns.RefreshTargetQuestIcon()
	local db = ns.db
	local on = db and ns.QuestVisionSetting("targetQuestIcon")
	local ok, exists = pcall(UnitExists, "target")
	local show = on and ok and Known(exists) and exists and ns.IsQuestMob("target")
	if show then
		local icon = TargetIcon()
		if icon then
			ns.SetQuestMark(icon.texture, ns.IsPassiveQuestMob("target"))
			icon:Show()
		end
	elseif targetIcon then
		targetIcon:Hide()
	end
end

-- Whether Quest Vision is showing anything now (the minimap button's glow):
-- the target frame's icon, an object's glow, or a quest mob's plate.
function ns.QuestVisionActive()
	if not ns.Setting("questVision") then
		return false
	end
	if (targetIcon and ns.Flag(targetIcon:IsShown())) or (ns.QuestGlowShown and ns.QuestGlowShown()) then
		return true
	end
	if not (ns.QuestMobsShow() and C_NamePlate and C_NamePlate.GetNamePlates) then
		return false
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and ns.IsQuestMob(unit) then
			return true
		end
	end
	return false
end

local TARGET_EVERY = 0.5
local targetWatcher = CreateFrame("Frame")
targetWatcher.at = 0
targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
targetWatcher:SetScript("OnEvent", ns.RefreshTargetQuestIcon)
targetWatcher:SetScript("OnUpdate", function(self)
	local now = GetTime()
	if now >= self.at then
		self.at = now + TARGET_EVERY
		if (ns.db and ns.db.targetQuestIcon) or (targetIcon and targetIcon:IsShown()) then
			ns.RefreshTargetQuestIcon()
		end
	end
end)

-- For /cine debug plates: what the target's quest lines say.
function ns.DescribeQuestMob(unit)
	return ("quest mob=%s (tooltip=%s)"):format(tostring(ns.IsQuestMob(unit)), tostring(FromTooltip(unit)))
end
