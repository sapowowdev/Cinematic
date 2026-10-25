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
local _, ns = ...
local L = ns.L

local NEAR_YARDS = 300
local CHECK_EVERY = 2 -- seconds (you move: the nearest quest changes)
local SIZE = 52
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

local button = CreateFrame("Button", "CinematicQuestItemButton", UIParent, "SecureActionButtonTemplate")
button:SetSize(SIZE, SIZE)
button:SetFrameStrata("MEDIUM")
button:Hide()
button:SetAttribute("type", "item")

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
-- The extra action button's frame round it, where the client has that art;
-- else an action button's border.
local style = button:CreateTexture(nil, "OVERLAY")
style:SetPoint("CENTER")
style:SetSize(256, 128)
if style:SetTexture("Interface\\ExtraButton\\Default") == false or not style:GetTexture() then
	style:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	style:SetSize(SIZE * 1.7, SIZE * 1.7)
end
local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
cooldown:SetAllPoints(icon)
local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
count:SetPoint("BOTTOMRIGHT", -3, 3)
local hotkey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
hotkey:SetPoint("TOPRIGHT", -3, -3)
button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

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
	if ok and Known(start) and Known(duration) and enable ~= 0 and enable ~= false
		and type(start) == "number" and start > 0 then
		cooldown:SetCooldown(start, duration)
	else
		cooldown:Clear()
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
