-- Cinematic: triggers of your own. Each starts one of the standing-still
-- cameras (cozy, vista, fish, AFK) when something happens: an emote, a spell
-- cast, a buff, a place, a moment (levelling up...), a state (mounted...) or
-- one of five key bindings. They're Cameras page rows like the built-in
-- triggers (CameraRows.lua: camera, music, CineMode, When, copies), and take
-- their place in the priority list (Triggers.lua) after a built-in source.
--
-- Saved in db.cameraRows with the rows (so profiles, Save/Reset and share
-- strings carry them): "custom" their ids (MineA, MineB...: letters only, as
-- a row id is a trigger key and a copy number), and per id:
--   source  "<kind>:<what>": emote:cheer, spell:7620 or spell:fishing,
--           aura:<id or name>, place:<zone or subzone name>,
--           moment:levelup|achievement|quest|boss|alive,
--           state:mounted|swimming|flying|indoors|outdoors|resting|stealthed|night,
--           key:1-5
--   until   move (nil), ends (as its state or cast ends), time:<sec>, key
--           (pressed again)
--   after   the built-in source it comes after (nil: "emote"; "": first)
--
-- Each is on for an episode: it starts as its thing happens (a state: as it
-- becomes true) and lasts until its until, or until you move (moving ends
-- every standing-still camera). A state still true after its episode ended
-- doesn't start another until it's been false.
local _, ns = ...
local L = ns.L

ns.CUSTOM_TRIGGER_MAX = 20
-- What can start one, in the editor's order (CameraTriggerEditor.lua), with
-- the choices of the kinds that have a fixed list.
ns.CUSTOM_TRIGGER_KINDS = {
	{ value = "emote", text = L["Emote"] }, { value = "spell", text = L["Spell cast"] },
	{ value = "aura", text = L["Buff on you"] }, { value = "place", text = L["Place"] },
	{ value = "moment", text = L["Moment"] }, { value = "state", text = L["State"] },
	{ value = "key", text = L["Key binding"] },
}
ns.CUSTOM_TRIGGER_MOMENTS = {
	{ value = "levelup", text = L["You level up"] }, { value = "achievement", text = L["You earn an achievement"] },
	{ value = "quest", text = L["You turn in a quest"] }, { value = "boss", text = L["Your group kills a boss"] },
	{ value = "alive", text = L["You come back to life"] },
}
ns.CUSTOM_TRIGGER_STATES = {
	{ value = "mounted", text = L["Mounted"] }, { value = "swimming", text = L["Swimming"] },
	{ value = "flying", text = L["Flying"] }, { value = "indoors", text = L["Indoors"] },
	{ value = "outdoors", text = L["Outdoors"] }, { value = "resting", text = L["Resting (an inn or a city)"] },
	{ value = "stealthed", text = L["Stealthed"] }, { value = "night", text = L["Night (game time)"] },
}
ns.CUSTOM_TRIGGER_KEYS = {}
for n = 1, 5 do
	ns.CUSTOM_TRIGGER_KEYS[n] = { value = tostring(n), text = (L["Custom camera trigger %d"]):format(n) }
end
ns.OnLanguage(function()
	for _, list in ipairs({ ns.CUSTOM_TRIGGER_KINDS, ns.CUSTOM_TRIGGER_MOMENTS, ns.CUSTOM_TRIGGER_STATES }) do
		ns.TranslateFields(list, "text")
	end
	for n, each in ipairs(ns.CUSTOM_TRIGGER_KEYS) do each.text = (L["Custom camera trigger %d"]):format(n) end
end)
local function ChoiceText(list, value)
	for _, each in ipairs(list) do
		if each.value == value then return each.text end
	end
end
local CAMERAS = { "cozy", "vista", "fish", "afk", "none" }
local DEFAULT_SECS = 5 -- a moment's (or an instant cast's) camera, when its until doesn't say
local TICK = 0.1 -- seconds between looks at the states
local SLOW_LOOK = 1 -- seconds between looks at buffs and places with no event

-- Moments: their game events (a boss only when the fight was won).
local MOMENT_EVENTS = {
	levelup = { "PLAYER_LEVEL_UP" }, achievement = { "ACHIEVEMENT_EARNED" }, quest = { "QUEST_TURNED_IN" },
	boss = { "ENCOUNTER_END" }, alive = { "PLAYER_UNGHOST", "PLAYER_ALIVE" },
}
local SPELL_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }
local PLACE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }
local CAST_START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
local CAST_END = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_FAILED = true }

-- States: read on the tick, by the game's function's name (a client may lack one).
local STATE_API = { mounted = "IsMounted", swimming = "IsSwimming", flying = "IsFlying", indoors = "IsIndoors",
	outdoors = "IsOutdoors", resting = "IsResting", stealthed = "IsStealthed" }
local function StateNow(what)
	if what == "night" then
		local hour = GetGameTime and GetGameTime()
		return type(hour) == "number" and (hour >= 21 or hour < 6)
	end
	local fn = _G[STATE_API[what] or ""]
	if not fn then return false end
	local ok, value = pcall(fn)
	return ok and ns.Flag(value) or false
end

-- A buff on you by spell ID or name (lower case). On retail your own buffs
-- can't be read in fights: false then (the camera waits out a fight anyway).
local function ScanAuras(what, id)
	if id and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		return C_UnitAuras.GetPlayerAuraBySpellID(id) ~= nil
	end
	for i = 1, 40 do
		local name, spellID
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
			if not aura then return false end
			name, spellID = aura.name, aura.spellId
		else
			local _
			name, _, _, _, _, _, _, _, _, spellID = UnitBuff("player", i)
			if not name then return false end
		end
		if (id and spellID == id) or (not id and type(name) == "string" and name:lower() == what) then
			return true
		end
	end
	return false
end
-- You're in a zone or subzone of that name (lower case).
local PLACE_TEXT = { "GetSubZoneText", "GetZoneText", "GetMinimapZoneText", "GetRealZoneText" }
local function ScanPlace(what)
	for _, fnName in ipairs(PLACE_TEXT) do
		local fn = _G[fnName]
		local name = fn and fn()
		if type(name) == "string" and name ~= "" and name:lower() == what then return true end
	end
	return false
end
-- A cast is the trigger's: by ID, or by its name in your game language.
local function ScanSpell(spellID, wantID, wantName)
	if wantID then return spellID == wantID end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
		or (GetSpellInfo and GetSpellInfo(spellID))
	return type(name) == "string" and name:lower() == wantName
end
local function Safe(ok, value) return ok and value or false end

local function Rows()
	local db = ns.db
	return db and type(db.cameraRows) == "table" and db.cameraRows or nil
end

-- An emote as its token, lower case: "/lol" or "lol" -> "laugh", by the
-- game's own emote commands (any language, any alias); else as typed.
local emoteTokens -- ("/lol" -> "laugh", built on first use)
function ns.EmoteToken(text)
	text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if not emoteTokens then
		emoteTokens = {}
		for i = 1, 1000 do
			local token = _G["EMOTE" .. i .. "_TOKEN"]
			if type(token) == "string" then
				emoteTokens["/" .. token:lower()] = token:lower()
				for j = 1, 10 do
					local cmd = _G["EMOTE" .. i .. "_CMD" .. j]
					if type(cmd) == "string" then emoteTokens[cmd:lower()] = token:lower() end
				end
			end
		end
	end
	local slashed = text:find("^/") and text or "/" .. text
	return emoteTokens[slashed] or text:gsub("^/", "")
end

-- What each trigger is doing: id -> { source, kind, what, spellID,
-- untilText, untilKind, secs, on, since, cond, done, casting, dirty, lookedAt }.
local live = {}
local liveOrder = {} -- (their ids in order)
local syncedText = false

-- Reads a trigger's source and until (again only when their text changes).
local function Parse(id, state)
	local rows = Rows()
	if not rows then return end
	local source = tostring(rows[id .. ".source"] or "")
	local untilText = tostring(rows[id .. ".until"] or "move")
	if state.source == source and state.untilText == untilText then return end
	state.source, state.untilText = source, untilText
	local kind, what = source:match("^(%a+):(.*)$")
	state.kind, state.what = kind, what and what:lower() or ""
	if kind == "emote" then state.what = ns.EmoteToken(state.what) end
	state.spellID = (kind == "spell" or kind == "aura") and tonumber(state.what) or nil
	local secs = tonumber(untilText:match("^time:(%d+%.?%d*)$"))
	state.untilKind = secs and "time" or untilText
	state.secs = secs or DEFAULT_SECS
	state.on, state.cond, state.done, state.dirty = false, nil, false, true
end

local function Start(state)
	state.on, state.since, state.done = true, GetTime(), false
end
local function Stop(state)
	state.on, state.done = false, true
end

-- The game events the triggers need now, registered only while one does.
local watcher = CreateFrame("Frame")
local function Watch()
	watcher:UnregisterAllEvents()
	local need = {}
	for _, id in ipairs(liveOrder) do
		local state = live[id]
		if state.kind == "spell" then
			for _, event in ipairs(SPELL_EVENTS) do need[event] = true end
		elseif state.kind == "aura" then
			need.UNIT_AURA = true
		elseif state.kind == "place" then
			for _, event in ipairs(PLACE_EVENTS) do need[event] = true end
		elseif state.kind == "moment" then
			for _, event in ipairs(MOMENT_EVENTS[state.what] or {}) do need[event] = true end
		end
	end
	for event in pairs(need) do
		if event:find("^UNIT_") then
			pcall(watcher.RegisterUnitEvent, watcher, event, "player")
		else
			pcall(watcher.RegisterEvent, watcher, event)
		end
	end
end

local function MomentMatches(state, event, ...)
	for _, each in ipairs(MOMENT_EVENTS[state.what] or {}) do
		if each == event then
			if event == "ENCOUNTER_END" then return select(5, ...) == 1 end -- (won)
			if event == "PLAYER_ALIVE" then return not ns.Flag(UnitIsDeadOrGhost("player")) end
			return true
		end
	end
	return false
end

watcher:SetScript("OnEvent", function(_, event, ...)
	local isCast = CAST_START[event] or CAST_END[event] or event == "UNIT_SPELLCAST_SUCCEEDED"
	for _, id in ipairs(liveOrder) do
		local state = live[id]
		if state.kind == "spell" and isCast then
			if Safe(pcall(ScanSpell, (select(3, ...)), state.spellID, state.what)) then
				if CAST_START[event] then
					state.casting = true
					Start(state)
				elseif CAST_END[event] then
					state.casting = false
					if state.on and state.untilKind == "ends" then Stop(state) end
				elseif not state.casting and not state.on then
					Start(state) -- (an instant cast: "ends" times out, as a moment)
				end
			end
		elseif state.kind == "moment" and MomentMatches(state, event, ...) then
			Start(state)
		elseif state.kind == "aura" or state.kind == "place" then
			state.dirty = true
		end
	end
end)

-- A state source's condition now (nil for the ones an event starts). Buffs
-- and places are looked at again on their events, or every SLOW_LOOK.
local function Condition(state, now)
	local kind = state.kind
	if kind == "state" then
		return StateNow(state.what)
	elseif kind == "aura" or kind == "place" then
		if state.dirty or not state.lookedAt or now - state.lookedAt >= SLOW_LOOK then
			state.dirty, state.lookedAt = false, now
			if kind == "aura" then
				state.found = Safe(pcall(ScanAuras, state.what, state.spellID))
			else
				state.found = Safe(pcall(ScanPlace, state.what))
			end
		end
		return state.found
	end
end

-- Whether an episode on now has run its time: a set time, or "ends" for
-- what has no end of its own (a moment, an instant cast).
local function TimedOut(state, now)
	local timed = state.untilKind == "time"
		or (state.untilKind == "ends" and (state.kind == "moment" or (state.kind == "spell" and not state.casting)))
	return timed and now - state.since >= state.secs
end

local lastEmoteAt -- (the last emote's time already looked at)
local function Tick()
	local now = GetTime()
	local emote = ns.lastEmote
	local newEmote = emote and emote.at ~= lastEmoteAt and type(emote.token) == "string" and emote.token:lower()
	lastEmoteAt = emote and emote.at
	local moving = ns.playerMoving and not (ns.OnTaxi and ns.OnTaxi())
	for _, id in ipairs(liveOrder) do
		local state = live[id]
		Parse(id, state)
		local cond = Condition(state, now)
		if cond ~= nil then
			if cond and not state.cond and not state.done then Start(state) end
			if not cond then
				if state.on and state.untilKind == "ends" then state.on = false end
				state.done = false
			end
			state.cond = cond
		end
		if newEmote and state.kind == "emote" then
			-- (Another emote ends it, as the built-in emotes' cameras end.)
			if newEmote == state.what then
				Start(state)
			elseif state.on then
				Stop(state)
			end
		end
		if state.on and (moving or TimedOut(state, now)) then Stop(state) end
	end
end
if ns.Profiled then Tick = ns.Profiled("CustomTriggers", Tick) end

local ticker = CreateFrame("Frame")
local sinceTick = 0
ticker:Hide()
ticker:SetScript("OnUpdate", function(_, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick >= TICK then
		sinceTick = 0
		Tick()
	end
end)

-- Where a trigger sits in the priority list: just after the built-in source
-- it names, in the order the triggers are listed.
local BUILT_IN_ORDER = {}
for _, source in ipairs(ns.TRIGGER_SOURCES) do BUILT_IN_ORDER[source.id] = source.order end
local function OrderOf(id, index)
	local after = Rows()[id .. ".after"]
	local base = after == "" and 0 or BUILT_IN_ORDER[after or "emote"] or BUILT_IN_ORDER.emote
	return base + 1 + math.min(index, 98) / 100
end

-- Brings the registered triggers in line with the profile's list when it
-- changes (one added or taken off, a profile loaded).
function ns.SyncCustomTriggers()
	local rows = Rows()
	if not rows then return end
	local text = tostring(rows.custom or "")
	if text == syncedText then return end
	syncedText = text
	local ids, seen = {}, {}
	for id in text:gmatch("[^,]+") do
		-- (Never over a built-in trigger.)
		local taken = ns.CAMERA_TRIGGER[id] and not ns.CAMERA_TRIGGER[id].custom
		if id:find("^%a+$") and not taken and not seen[id] and #ids < ns.CUSTOM_TRIGGER_MAX then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	for _, id in ipairs(liveOrder) do
		if not seen[id] then
			ns.UnregisterCameraTrigger(id)
			ns.UnregisterTriggerSource("custom:" .. id)
			live[id] = nil
		end
	end
	wipe(liveOrder)
	for i, id in ipairs(ids) do
		local state = live[id] or {}
		live[id], liveOrder[i] = state, id
		if not ns.CAMERA_TRIGGER[id] then
			ns.RegisterCameraTrigger({ key = id, custom = true, cameras = CAMERAS, off = "none", music = true,
				cine = true })
		end
		Parse(id, state)
		ns.RegisterTriggerSource({ id = "custom:" .. id, order = OrderOf(id, i), custom = id,
			Key = function() return state.on and id or nil end })
	end
	Watch()
	ticker:SetShown(#liveOrder > 0)
end
-- (A trigger's source or place in the list changed: worked out afresh.)
function ns.CustomTriggersChanged()
	syncedText = false
	ns.SyncCustomTriggers()
end

-- What starts a trigger, in words: "/cheer", "Cast Fishing", "Mounted"...
function ns.DescribeTriggerSource(source)
	local kind, what = tostring(source or ""):match("^(%a+):(.*)$")
	what = what or ""
	if kind == "emote" then
		return "/" .. ns.EmoteToken(what)
	elseif kind == "spell" then
		local id = tonumber(what)
		local name = id and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
			or (GetSpellInfo and GetSpellInfo(id)))
		return (L["Cast %s"]):format(type(name) == "string" and name or what)
	elseif kind == "aura" then
		return (L["Buff: %s"]):format(what)
	elseif kind == "place" then
		return (L["In %s"]):format(what)
	elseif kind == "moment" then
		return ChoiceText(ns.CUSTOM_TRIGGER_MOMENTS, what) or what
	elseif kind == "state" then
		return ChoiceText(ns.CUSTOM_TRIGGER_STATES, what) or what
	elseif kind == "key" then
		return (L["Custom camera trigger %d"]):format(tonumber(what) or 1)
	end
	return tostring(source or "?")
end

-- A trigger's name for the page and logs: your own, else what starts it.
function ns.CustomTriggerLabel(id)
	local rows = Rows()
	local name = rows and rows[id .. ".name"]
	if type(name) == "string" and name:find("%S") then return name end
	return ns.DescribeTriggerSource(rows and rows[id .. ".source"])
end

-- Whether a custom spell trigger is on with its cast going: the cast isn't
-- busy casting then (as fishing isn't), so its camera can run.
function ns.CustomCastCounts()
	for _, id in ipairs(liveOrder) do
		local state = live[id]
		if state.kind == "spell" and state.on and state.casting and ns.TriggerHasCamera(id) then return true end
	end
	return false
end

-- The key bindings (Cinematic custom trigger 1-5): start the triggers set
-- to that key, or stop them if they're on.
function Cinematic_CustomTrigger(n)
	local what = tostring(n)
	for _, id in ipairs(liveOrder) do
		local state = live[id]
		if state.kind == "key" and state.what == what then
			if state.on then Stop(state) else Start(state) end
		end
	end
end

-- For the camera mode log: what set a custom trigger off.
function ns.CustomTriggerDetail(key)
	local state = live[key]
	if not state then return nil end
	return ("custom %s (%s, until %s), %.0f sec in"):format(ns.CustomTriggerLabel(key), tostring(state.source),
		tostring(state.untilText), state.since and GetTime() - state.since or 0)
end

-- A new trigger: its id (nil with all taken). Starts with the camera given
-- (cozy), no music, anywhere but battlegrounds and arenas, out of fights.
function ns.AddCustomTrigger(source, untilText, camera, name)
	local db = ns.GetDB()
	local rows = db.cameraRows
	local taken, count = {}, 0
	for id in tostring(rows.custom or ""):gmatch("[^,]+") do
		taken[id] = true
		count = count + 1
	end
	if count >= ns.CUSTOM_TRIGGER_MAX then return nil end
	local id
	for n = 0, 701 do
		local letters = n < 26 and string.char(65 + n) or string.char(64 + math.floor(n / 26), 65 + n % 26)
		if not taken["Mine" .. letters] and not ns.CAMERA_TRIGGER["Mine" .. letters] then
			id = "Mine" .. letters
			break
		end
	end
	if not id then return nil end
	rows[id .. ".source"] = source
	rows[id .. ".until"] = untilText ~= "move" and untilText or nil
	rows[id .. ".camera"] = camera or "cozy"
	rows[id .. ".name"] = name
	local key = ns.CameraRowKey(id)
	for _, list in ipairs({ "worldShow", "cityShow", "instanceShow", "groupShow", "bgShow", "combatShow" }) do
		if type(db[list]) ~= "table" then db[list] = {} end
		db[list][key] = list ~= "bgShow" and list ~= "combatShow"
	end
	rows.custom = (rows.custom and rows.custom ~= "" and rows.custom .. "," or "") .. id
	ns.SyncCustomTriggers()
	return id
end

-- Takes a trigger off, with its copies and all their settings.
function ns.RemoveCustomTrigger(id)
	local db = ns.GetDB()
	local rows = db.cameraRows
	if ns.CAMERA_TRIGGER[id] then
		for _, each in ipairs(ns.TriggerRowIds(id)) do
			if each ~= id then ns.RemoveCameraRow(each) end
		end
	end
	for _, field in ipairs({ "camera", "music", "cine", "name", "always", "calm", "off", "source", "until", "after" }) do
		rows[id .. "." .. field] = nil
	end
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if type(db[list]) == "table" then db[list][ns.CameraRowKey(id)] = nil end
	end
	local list = {}
	for each in tostring(rows.custom or ""):gmatch("[^,]+") do
		if each ~= id then list[#list + 1] = each end
	end
	rows.custom = #list > 0 and table.concat(list, ",") or nil
	-- (Out of a row order of your own, if there is one.)
	if rows.order then
		local order = {}
		for _, each in ipairs(ns.CameraRowOrder()) do
			if each ~= id then order[#order + 1] = each end
		end
		ns.SetCameraRowOrder(order)
	else
		ns.SyncCustomTriggers()
	end
end

-- For /cine debug triggers: each one, what starts it, whether it's on and
-- why, its place in the priority list and the row it goes by.
function ns.DescribeCustomTriggers()
	local lines = {}
	local rows = Rows() or {}
	for _, id in ipairs(liveOrder) do
		local state = live[id]
		local order = "-"
		for _, each in ipairs(ns.TRIGGER_SOURCES) do
			if each.custom == id then order = ("%.2f"):format(each.order) end
		end
		lines[#lines + 1] = ("%s \"%s\": %s until %s, after %s (order %s) - %s%s%s, cond %s, row %s -> %s"):format(id,
			ns.CustomTriggerLabel(id), tostring(state.source), tostring(state.untilText),
			tostring(rows[id .. ".after"] or "emote"), order, state.on and "ON" or "off",
			state.done and ", done" or "", state.casting and ", casting" or "", tostring(state.cond),
			tostring(ns.TriggerRowNow(id)), tostring(ns.TriggerSetting(id, "camera")))
	end
	return lines
end

-- (Once the profile's there, and every second after: a profile loaded or
-- reset with nothing else asking for the rows.)
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	ns.SyncCustomTriggers()
	if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, ns.SyncCustomTriggers) end
end)
