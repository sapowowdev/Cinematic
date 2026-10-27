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
local passiveAnswers = {} -- [guid] = { passive = bool, at = time } (see IsPassiveQuestMob)
local spent = {} -- [guid] = questID: NPCs you've used that quest's item on (see below)
local spentNames = {} -- [name] = until (time): the same, by name, for SPENT_NAME_TIME seconds
local SPENT_NAME_TIME = 60
local lastSpent -- (for /cine debug questmob: the last one, { guid, name })

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function NameOf(unit)
	local ok, name = pcall(UnitName, unit)
	return ok and type(name) == "string" and Known(name) and name or nil
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

-- Classic gives units no quest lines (and UnitIsRelatedToActiveQuest says no):
-- there, the kill objectives in the log not yet done ("Young Nightsaber slain:
-- 3/7"), by the mob's name. Items that drop from mobs can't be told this way.
local killNames -- [name] = true, or nil until needed

local function KillName(text)
	if type(text) ~= "string" or not Known(text) then
		return nil
	end
	local name = text:match("^(.-):%s*%d+%s*/%s*%d+")
	if not name then
		return nil
	end
	-- (" slain", from the game's own "%s slain: %d/%d".)
	local suffix = type(QUEST_MONSTERS_KILLED) == "string" and QUEST_MONSTERS_KILLED:match("^%%s(.-):")
	if suffix and suffix ~= "" and name:sub(-#suffix) == suffix then
		name = name:sub(1, -#suffix - 1)
	end
	return name ~= "" and name or nil
end

local function KillNames()
	if killNames then
		return killNames
	end
	killNames = {}
	pcall(function()
		local log = C_QuestLog
		if log and log.GetInfo and log.GetQuestObjectives then
			for i = 1, log.GetNumQuestLogEntries() do
				local info = log.GetInfo(i)
				local questID = info and not info.isHeader and info.questID
				for _, objective in ipairs(type(questID) == "number" and log.GetQuestObjectives(questID) or {}) do
					local name = objective.type == "monster" and not objective.finished and KillName(objective.text)
					if name then
						killNames[name] = true
					end
				end
			end
		elseif GetQuestLogTitle and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
			for i = 1, GetNumQuestLogEntries() do
				local _, _, _, isHeader = GetQuestLogTitle(i)
				for j = 1, not isHeader and GetNumQuestLeaderBoards(i) or 0 do
					local text, kind, finished = GetQuestLogLeaderBoard(j, i)
					local name = kind == "monster" and not finished and KillName(text)
					if name then
						killNames[name] = true
					end
				end
			end
		end
	end)
	return killNames
end

-- Whether the unit is an enemy named by a kill objective not yet done (see above).
local function FromKillLog(unit)
	if ns.isRetail or IsFriendly(unit) then
		return false
	end
	local name = NameOf(unit)
	return name and KillNames()[name] == true or false
end

local function Read(unit)
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if not ok or not Known(isPlayer) or isPlayer then
		return false
	end
	local found = FromTooltip(unit)
	if found then
		return true
	end
	local related = found == nil and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
	if related then
		local okRelated, yes = pcall(related, unit)
		if okRelated and Known(yes) and yes then
			return true
		end
	end
	return FromKillLog(unit)
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
	if spent[guid] then
		local okOn, on = pcall(C_QuestLog.IsOnQuest, spent[guid])
		if okOn and on then
			return false
		end
		spent[guid] = nil
	end
	-- (By name for a while too: the game can swap an NPC you've used the item
	-- on for a fresh copy of it, with a new GUID.)
	if next(spentNames) then
		local name = NameOf(unit)
		local untilTime = name and spentNames[name]
		if untilTime and GetTime() < untilTime then
			return false
		elseif untilTime then
			spentNames[name] = nil
		end
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

-- NPCs you use a quest's item on ("Renewal for the Weary": 1/10 Sunwell
-- Channeler renewed) keep the objective line on their tooltip after, so they'd
-- keep the !. An NPC counts as done (spent, at the top) once a cast aimed at
-- it is followed, within SPENT_WAIT seconds, by progress on a quest with an
-- item to use: the quest whose item has that spell, else (an item can cast
-- some other spell) any of them, if the NPC was a quest mob. Until the quest
-- leaves the log. Its name too, for SPENT_NAME_TIME seconds. /cine debug questitem prints each step.
local SPENT_WAIT = 15
local CAST_UNITS = { "target", "softinteract", "softfriend", "mouseover", "focus" }
local itemQuests -- { [spellID] = questID, all = { questID, ... } }, or nil until needed
local aimed -- UNIT_SPELLCAST_SENT's: { id = castGUID, guid, mob = quest mob, have = { [questID] = count } }
local pending = {} -- { guid, name, quest, have, at }

local function Report(text)
	if ns.questItemDebug then
		ns.Print("quest item: " .. text)
	end
end

-- The quests in your log with an item to use (the square beside them in the
-- quest tracker): { questID, index (quest log), link, itemID, icon,
-- showComplete, complete } each. Also for QuestItemButton. say: a function
-- told what each quest gives back (/cine debug questitem).
function ns.QuestLogItems(say)
	local found = {}
	local log = C_QuestLog
	local SpecialItem = _G.GetQuestLogSpecialItemInfo or (log and log.GetQuestLogSpecialItemInfo)
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and SpecialItem) then
		if say then
			say(("can't read quest items: quest log %s, item reader %s"):format(tostring(log and log.GetInfo ~= nil),
				tostring(SpecialItem ~= nil)))
		end
		return found
	end
	local okCount, entries = pcall(log.GetNumQuestLogEntries)
	for index = 1, okCount and type(entries) == "number" and entries or 0 do
		local ok, problem = pcall(function()
			local info = log.GetInfo(index)
			local questID = info and not info.isHeader and info.questID
			if type(questID) ~= "number" then
				return
			end
			local link, icon, _, showComplete = SpecialItem(index)
			if link == nil then
				return
			end
			local readable = type(link) == "string" and Known(link)
			local itemID = readable and tonumber(link:match("item:(%d+)"))
			local complete = log.IsComplete and log.IsComplete(questID) or false
			if say then
				say(("quest %s (%s): item %s%s"):format(questID, tostring(info.title),
					readable and link or ("unreadable (" .. type(link) .. ")"), complete and ", complete" or ""))
			end
			if itemID then
				found[#found + 1] = { questID = questID, index = index, link = link, itemID = itemID, icon = icon,
					showComplete = showComplete, complete = complete }
			end
		end)
		if not ok and say then
			say(("quest log entry %d: error %s"):format(index, tostring(problem)))
		end
	end
	return found
end

local function ItemQuests()
	if itemQuests then
		return itemQuests
	end
	itemQuests = { all = {} }
	local GetItemSpell = C_Item and C_Item.GetItemSpell or _G.GetItemSpell
	for _, quest in ipairs(ns.QuestLogItems()) do
		local all = itemQuests.all
		all[#all + 1] = quest.questID
		local ok, _, spellID = pcall(GetItemSpell or error, quest.itemID)
		if ok and type(spellID) == "number" and Known(spellID) then
			itemQuests[spellID] = quest.questID
		end
	end
	return itemQuests
end

-- How many of the quest's objectives' steps are done, all told.
local function Fulfilled(questID)
	local total = 0
	pcall(function()
		for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
			if type(objective.numFulfilled) == "number" and Known(objective.numFulfilled) then
				total = total + objective.numFulfilled
			end
		end
	end)
	return total
end

-- The unit a cast is aimed at: of the ones SENT named (any, with no name: an
-- item used on your soft target can come with none), a quest mob first.
local function AimedAt(name)
	local first
	for _, unit in ipairs(CAST_UNITS) do
		local okName, unitName = pcall(UnitName, unit)
		local ok, guid = pcall(UnitGUID, unit)
		if ok and type(guid) == "string" and Known(guid)
			and (name == nil or (okName and Known(unitName) and unitName == name)) then
			if ns.IsQuestMob(unit) then
				return guid, true, unit
			end
			first = first or unit
		end
	end
	return first and UnitGUID(first), false, first
end

local function CheckPending()
	local now = GetTime()
	for i = #pending, 1, -1 do
		local cast = pending[i]
		if now - cast.at > SPENT_WAIT then
			Report(("no progress on quest %s in %d sec: the ! stays"):format(tostring(cast.quest), SPENT_WAIT))
			table.remove(pending, i)
		elseif Fulfilled(cast.quest) > cast.have then
			spent[cast.guid] = cast.quest
			if cast.name then
				spentNames[cast.name] = now + SPENT_NAME_TIME
			end
			lastSpent = { guid = cast.guid, name = cast.name }
			Report(("progress on quest %s: %s is done (%s)"):format(tostring(cast.quest), tostring(cast.name),
				tostring(cast.guid)))
			table.remove(pending, i)
		end
	end
end

local castWatcher = CreateFrame("Frame")
castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castWatcher:SetScript("OnEvent", function(_, event, _, a, b, c)
	if event == "UNIT_SPELLCAST_SENT" then
		-- (unit, target name, castGUID, spellID)
		local name = type(a) == "string" and Known(a) and a ~= "" and a or nil
		local guid, mob, unit = AimedAt(name)
		-- (Each item quest's count now, before the cast: the game can move it
		-- before SUCCEEDED reaches us.)
		aimed = guid and { id = b, guid = guid, name = unit and NameOf(unit), mob = mob, have = {} }
		for _, questID in ipairs(guid and ItemQuests().all or {}) do
			aimed.have[questID] = Fulfilled(questID)
		end
		Report(("cast %s sent at %s: %s (%s)"):format(tostring(c), tostring(name or "no name"),
			tostring(unit or "no unit found"), mob and "a quest mob" or "not a quest mob"))
		return
	end
	-- (unit, castGUID, spellID)
	if not (aimed and Known(a) and a == aimed.id) then
		return
	end
	local quests = ItemQuests()
	local quest = type(b) == "number" and Known(b) and quests[b]
	local list = quest and { quest } or (aimed.mob and quests.all) or {}
	Report(("cast %s done: %s"):format(tostring(b), quest and ("the item spell of quest " .. quest)
		or (#list > 0 and ("not an item spell; watching %d quests with items"):format(#list))
		or "not an item spell, not at a quest mob: ignored"))
	for _, questID in ipairs(list) do
		pending[#pending + 1] = { guid = aimed.guid, name = aimed.name, quest = questID, have = aimed.have[questID] or Fulfilled(questID),
			at = GetTime() }
	end
	aimed = nil
	CheckPending()
end)

-- The quest log changed (progress made, a quest taken or handed in): every
-- answer is read again.
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function()
	if #pending > 0 then
		CheckPending()
	end
	itemQuests = nil
	wipe(answers)
	wipe(passiveAnswers)
	settleAt = GetTime() + SETTLE
	barTexts = nil
	killNames = nil
end)

-- The golden exclamation mark shown for them (plates' Quest Icon row, the
-- target frame's, below, and Quest Glow's): the map's sharp quest mark, or the
-- old gossip one with Forever's Character Models on Standard Definition (its
-- proxy setting is true then) or where a client lacks that atlas. Marks follow
-- the setting as it changes.
ns.QUEST_MOB_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"
local MODELS_SETTING = "PROXY_CHARACTER_MODELS_TOGGLE" -- (to follow it as it changes)
local marks = setmetatable({}, { __mode = "k" })

local function StandardModels()
	return ns.StandardModels() == true
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
-- until the quest log changes (passiveAnswers, at the top); a yes is read
-- again after a while: an enemy that turns friendly when beaten (to be
-- questioned) shows the plain pointer for a moment before you can talk to it.
-- Where the game won't say: no (the !).
function ns.IsPassiveQuestMob(unit)
	if not (unit and IsFriendly(unit)) then
		return false
	end
	local ok, guid = pcall(UnitGUID, unit)
	guid = ok and type(guid) == "string" and Known(guid) and guid or nil
	local now = GetTime()
	local answer = guid and passiveAnswers[guid]
	if answer and not (answer.passive and now - answer.at >= RECHECK_NO) then
		return answer.passive
	end
	local passive = IsPointer(ns.UnitCursor(unit))
	if guid then
		passiveAnswers[guid] = { passive = passive, at = now }
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

-- For /cine debug questmob: what the tooltip says, and the kill objectives in the log (Classic).
function ns.DescribeQuestKills(unit)
	local names = {}
	for name in pairs(KillNames()) do
		names[#names + 1] = name
	end
	table.sort(names)
	return ("tooltip says=%s, kill log match=%s, kill objectives: %s"):format(tostring(FromTooltip(unit)),
		tostring(FromKillLog(unit)), #names > 0 and table.concat(names, ", ") or "none")
end

-- For /cine debug questmob: the unit's GUID and whether it counts as done.
function ns.DescribeQuestSpent(unit)
	local ok, guid = pcall(UnitGUID, unit)
	guid = ok and type(guid) == "string" and Known(guid) and guid or nil
	local name = NameOf(unit)
	local untilTime = name and spentNames[name]
	return ("guid=%s, item used on it=%s, by name for %s, last done: %s (%s)"):format(tostring(guid),
		tostring(guid and spent[guid] ~= nil), untilTime and ("%.0f more sec"):format(math.max(0, untilTime - GetTime()))
		or "no", tostring(lastSpent and lastSpent.name), tostring(lastSpent and lastSpent.guid))
end
