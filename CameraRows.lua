-- Cinematic: the Cameras page's rows. Each row is a trigger (an emote, a
-- campfire, going AFK, a flight, dying...) and the camera it starts, with its
-- music and CineMode switches, and When it may start (as the Standard Frames
-- page's rows: Always, the places, a rule, the roles; and its own Calm Timer
-- wait). A trigger's own row keeps the settings it always had (eventAFKCamera,
-- walkCamera, deathOrbit...); copies of it (AFK2...) are rows of their own,
-- in db.cameraRows. When a trigger happens, its rows are tried in their order
-- and the first whose When fits picks the camera: none fitting, no camera.
--
-- db.cameraRows (a profile table, flat): "order" the rows in their order
-- (comma separated; nil: each trigger's own row alone), and "<id>.<field>":
-- camera, music, cine (a copy's; nil: its trigger's own row's), name (one of
-- your own), off (true: unticked, passed over), always and calm (the When's Always and the Calm Timer wait; nil
-- on a trigger's own row: its camera's, below). A row's place ticks and rule
-- are under "trig:<id>" in the shared lists (cityShow..., frameRules,
-- tankHide...).
--
-- Triggers of your own (CustomTriggers.lua: custom = true) keep all of theirs
-- in it too, their own row's included: "custom" their ids, and
-- "<id>.source", "<id>.until", "<id>.after" what starts and ends them.
--
-- Before the page was one, each camera had its When (the Camera Modes page's
-- "cam:<cam>" rows, camAlways<cam>, <cam>CalmWait). A trigger's own row
-- follows its camera's until it's given a When of its own, so nothing
-- changes for settings and profiles from before.
local _, ns = ...
local L = ns.L

ns.CAMERA_ROW_COPIES = 5 -- (a trigger's own row and four copies: <key>2 to <key>5)

-- The triggers in the order the page lists them: the order they win in when
-- two are on (Camera.lua's CurrentEvent), then the ones with cameras of
-- their own. Each: key, its settings (camera, music, cine: nil for none),
-- its cameras (value, name), the value that's no camera.
local EVENT_CAMERAS = { "cozy", "vista", "fish", "afk", "none" }
local function Event(key, cameras)
	local music = ns.DEFAULTS["event" .. key .. "Music"] ~= nil and "event" .. key .. "Music" or nil
	return { key = key, camera = "event" .. key .. "Camera", music = music, cine = "event" .. key .. "Cine",
		cameras = cameras or EVENT_CAMERAS, off = "none" }
end
local TRIGGERS, TRIGGER = {}, {}
ns.CAMERA_TRIGGERS, ns.CAMERA_TRIGGER = TRIGGERS, TRIGGER
local orderCache, triggerRows -- (below: worked out again when a trigger's added)

-- Adds a trigger's rows to the page (key: letters only, as a row id is the
-- key and a copy number), at the end of the list. Again with the same key:
-- its fields replaced, in its place.
function ns.RegisterCameraTrigger(trigger)
	local old = TRIGGER[trigger.key]
	if old then
		for i, each in ipairs(TRIGGERS) do
			if each == old then TRIGGERS[i] = trigger end
		end
	else
		TRIGGERS[#TRIGGERS + 1] = trigger
	end
	TRIGGER[trigger.key] = trigger
	if orderCache then
		orderCache.text, orderCache.list = false, nil
		wipe(triggerRows)
	end
	if ns.CameraRowsChanged then ns.CameraRowsChanged() end
end
-- Takes a trigger's rows off the page (its settings stay). Its rows' ids
-- still name it (RETIRED), for a page's controls made for them before.
local RETIRED = {}
function ns.UnregisterCameraTrigger(key)
	local old = TRIGGER[key]
	if not old then return end
	RETIRED[key] = old
	for i = #TRIGGERS, 1, -1 do
		if TRIGGERS[i] == old then table.remove(TRIGGERS, i) end
	end
	TRIGGER[key] = nil
	orderCache.text, orderCache.list = false, nil
	wipe(triggerRows)
	ns.CameraRowsChanged()
end

-- (A WoW Forever event has no row on retail.)
local FOREVER_ONLY = {}
for _, event in ipairs(ns.EVENTS) do
	if event.forever then FOREVER_ONLY[event.key] = true end
end
for _, trigger in ipairs({
	Event("Hearth", { "tele", "none" }), Event("Teleport", { "tele", "none" }), Event("Logout"), Event("AFK"),
	Event("Sit"), Event("SitButton"), Event("Sleep"), Event("Dance"), Event("Kneel"), Event("Stare"),
	Event("Chair"), Event("Weapon"), Event("Campfire"), Event("Fishing"), Event("Still"),
	Event("Flight", { "flight", "none" }), Event("Quest", { "quest", "none" }),
	Event("QuestGossip", { "quest", "none" }),
	{ key = "Walk", camera = "walkCamera", music = "musicCamWalk", cine = "walkCine", cameras = { "walk", "none" },
		off = "none" },
	{ key = "Run", camera = "runCamera", music = "musicCamRun", cine = "runCine", cameras = { "run", "none" },
		off = "none" },
	{ key = "Death", camera = "deathOrbit", music = "deathSong", cine = "deathCine", cameras = { true, false },
		off = false },
}) do
	-- (A flight's music is the flight camera's own switch.)
	if trigger.key == "Flight" then trigger.music = "musicCamFlight" end
	if not (FOREVER_ONLY[trigger.key] and ns.isRetail) then ns.RegisterCameraTrigger(trigger) end
end
-- (The chat camera: ChatCam.lua; no music or CineMode switch yet.)
if ns.ChatCamCommand then
	ns.RegisterCameraTrigger({ key = "Chat", camera = "chatCamera", cameras = { "chat", "none" }, off = "none" })
	ns.RegisterCameraTrigger({ key = "ChatNearby", camera = "chatNearbyCamera", cameras = { "chat", "none" },
		off = "none" })
	-- Capital cities' citizens never stop chatting: that row's Cities unticked
	-- to start with (its other ticks follow the chat camera's).
	ns.LIST_DEFAULTS.cityShow["trig:ChatNearby"] = false
end

-- Each camera's name, and its row on the old Camera Modes page (ns.CAMERA_OFF_CAMS).
-- (death: the death camera as a trigger of your own plays it; the Die row's is true.)
ns.CAMERA_NAMES = { cozy = L["Cozy camera"], vista = L["Vista camera"], fish = L["Fish camera"], death = L["Death camera"],
	afk = L["AFK camera"], tele = L["Tele camera"], flight = L["Flight camera"], quest = L["Quest camera"],
	walk = L["RP walk camera"], run = L["Auto-run camera"], [true] = L["Death camera"], chat = L["Chat camera"],
	none = L["No camera"], [false] = L["No camera"] }
ns.OnLanguage(function()
	for value, name in pairs(ns.CAMERA_NAMES) do ns.CAMERA_NAMES[value] = L[name] end
end)
local CAM_OF = { cozy = "cozy", vista = "vista", fish = "fish", afk = "idle", tele = "tele", flight = "flight",
	quest = "quest", walk = "walk", run = "run", [true] = "death", chat = "chatcam", death = "death" }
-- A camera value's mode (as ns.CAMERA_OFF_CAMS names it), or nil for none.
-- (A shot: its camera's, Shots.lua.)
local function CamOf(value)
	if ns.ShotBase then value = ns.ShotBase(value) end
	return CAM_OF[value]
end
function ns.CameraValueMode(value) return CamOf(value) end

-- A row's trigger and its number (nil: the trigger's own row).
function ns.CameraRowTrigger(id)
	local key, copy = tostring(id):match("^(%a+)(%d?)$")
	return key and (TRIGGER[key] or RETIRED[key]), tonumber(copy)
end

local function Rows()
	local db = ns.db or ns.GetDB()
	local rows = db and db.cameraRows
	return type(rows) == "table" and rows or {}
end

-- Built-in triggers you've deleted ("deleted": their keys, comma separated):
-- no rows, no camera; their settings stay for Add back (or a Reset).
local deletedCache = { text = false, set = {} }
local function DeletedSet()
	local text = Rows().deleted
	if deletedCache.text ~= text then
		local set = {}
		for key in tostring(text or ""):gmatch("[^,]+") do set[key] = true end
		deletedCache.text, deletedCache.set = text, set
	end
	return deletedCache.set
end
function ns.TriggerDeleted(key) return DeletedSet()[key] == true end
-- The deleted ones, in the page's order.
function ns.DeletedTriggers()
	local list, set = {}, DeletedSet()
	for _, trigger in ipairs(TRIGGERS) do
		if set[trigger.key] then list[#list + 1] = trigger.key end
	end
	return list
end
function ns.SetTriggerDeleted(key, deleted)
	local trigger = TRIGGER[key]
	if not trigger or trigger.custom then return end
	local set, list = DeletedSet(), {}
	for _, each in ipairs(TRIGGERS) do
		local on = set[each.key]
		if each.key == key then on = deleted end
		if on then list[#list + 1] = each.key end
	end
	ns.GetDB().cameraRows.deleted = #list > 0 and table.concat(list, ",") or nil
	ns.CameraRowsChanged()
end

-- Every row in order: each trigger's own and its copies, the triggers as
-- TRIGGERS has them (a copy before its own row comes first for it), less
-- the deleted ones.
-- Worked out again only when the order changes. (Triggers of your own
-- brought up to date first: a profile loaded has its own.)
orderCache = { text = false }
function ns.CameraRowOrder()
	if ns.SyncCustomTriggers then ns.SyncCustomTriggers() end
	local text = Rows().order
	local deleted = DeletedSet()
	if orderCache.text == text and orderCache.deleted == deleted and orderCache.list then return orderCache.list end
	local byTrigger, seen = {}, {}
	for id in tostring(text or ""):gmatch("[^,]+") do
		local trigger, copy = ns.CameraRowTrigger(id)
		if trigger and not seen[id] and (not copy or (copy >= 2 and copy <= ns.CAMERA_ROW_COPIES)) then
			seen[id] = true
			byTrigger[trigger.key] = byTrigger[trigger.key] or {}
			table.insert(byTrigger[trigger.key], id)
		end
	end
	local list = {}
	for _, trigger in ipairs(TRIGGERS) do
		if not deleted[trigger.key] then
			local own = byTrigger[trigger.key] or {}
			if not seen[trigger.key] then table.insert(own, 1, trigger.key) end
			for _, id in ipairs(own) do list[#list + 1] = id end
		end
	end
	orderCache.text, orderCache.deleted, orderCache.list = text, deleted, list
	return list
end
-- A trigger's rows, in order.
triggerRows = {}
function ns.TriggerRowIds(key)
	local list = ns.CameraRowOrder()
	local cached = triggerRows[key]
	if cached and cached.from == list then return cached end
	cached = { from = list }
	for _, id in ipairs(list) do
		local trigger = ns.CameraRowTrigger(id)
		if trigger and trigger.key == key then cached[#cached + 1] = id end
	end
	triggerRows[key] = cached
	return cached
end

-- A row's setting (camera, music, cine): a copy's own, else its trigger's
-- own row's. False for a setting the trigger hasn't (no music for it).
function ns.CameraRowValue(id, field)
	local trigger, copy = ns.CameraRowTrigger(id)
	if not trigger then return nil end
	local db = ns.db or ns.GetDB()
	if copy then
		local value = Rows()[id .. "." .. field]
		if value ~= nil then return value end
	end
	if trigger.custom then
		local value = Rows()[trigger.key .. "." .. field]
		if value == nil then return field == "camera" and trigger.off or false end
		return value
	end
	local key = trigger[field]
	if not key then return field == "camera" and trigger.off or false end
	local value = db[key]
	if field == "camera" and (trigger.key == "Hearth" or trigger.key == "Teleport") and value ~= "none" then
		return "tele" -- (its only camera; early test versions saved "cozy")
	end
	return value
end
function ns.SetCameraRowValue(id, field, value)
	local trigger, copy = ns.CameraRowTrigger(id)
	if not trigger then return end
	local db = ns.GetDB()
	if copy or trigger.custom then
		db.cameraRows[id .. "." .. field] = value
	elseif trigger[field] then
		db[trigger[field]] = value
	end
end

-- Whether a row's ticked on (its tick at the start of the row): off, its
-- trigger passes it over, as if its When didn't fit.
function ns.CameraRowOn(id) return not Rows()[id .. ".off"] end
function ns.SetCameraRowOn(id, on)
	ns.GetDB().cameraRows[id .. ".off"] = not on or nil
	ns.CameraRowsChanged()
end

-- The camera row (Camera Modes' cam:<cam>) a trigger's own row follows, by
-- its camera now; nil for a copy, or with no camera.
local function Leader(id)
	local trigger, copy = ns.CameraRowTrigger(id)
	if copy or not trigger or trigger.custom then return nil end
	return CamOf(ns.CameraRowValue(id, "camera"))
end

-- The lists a row's When is in, and its key in them.
ns.CAMERA_ROW_LISTS = { "combatShow", "calmShow", "quietShow", "camShow", "enemyShow", "friendlyShow", "bgShow",
	"worldShow", "cityShow", "groupShow", "instanceShow", "frameRules", "tankHide", "healerHide", "damageHide" }
local ROW_KEY = setmetatable({}, { __index = function(keys, id)
	local key = "trig:" .. id
	keys[id] = key
	return key
end })
function ns.CameraRowKey(id) return ROW_KEY[id] end

-- Whether a trigger's own row has a When of its own yet (else its camera's
-- counts, rule, roles and all, as before the page was one). A tick it starts
-- with (ns.LIST_DEFAULTS) counts.
local function OwnWhen(id)
	local db, key = ns.db or ns.GetDB(), ROW_KEY[id]
	if Rows()[id .. ".always"] ~= nil or Rows()[id .. ".calm"] ~= nil then return true end
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if type(db[list]) == "table" and db[list][key] ~= nil then return true end
		if ns.LIST_DEFAULTS[list] and ns.LIST_DEFAULTS[list][key] ~= nil then return true end
	end
	return false
end

-- Keeps a trigger's own row's unset ticks following its camera's (the
-- lists' ns.ROW_FALLBACK), for the page and for the rows' When.
function ns.CameraRowFollow(id)
	local leader = Leader(id)
	if ns.ROW_FALLBACK then ns.ROW_FALLBACK[ROW_KEY[id]] = leader and ("cam:" .. leader) or nil end
	return leader
end

-- A row's Always and Calm Timer wait: its own, else (a trigger's own row)
-- its camera's.
function ns.CameraRowAlways(id)
	local own = Rows()[id .. ".always"]
	if own ~= nil then return own end
	local leader = Leader(id)
	return leader and ns.GetDB()["camAlways" .. leader] and true or false
end
function ns.CameraRowCalm(id)
	local own = Rows()[id .. ".calm"]
	if own ~= nil then return own end
	local leader = Leader(id)
	return leader and not ns.CALM_WAIT_NEVER[leader] and ns.GetDB()[leader .. "CalmWait"] and true or false
end

-- Whether a row's When fits now. A flight's places are where it took off: a
-- capital city or the open world (its rule aside).
local function Fits(key, always, flight)
	if flight and ns.OnTaxi() and not ns.RuleTest(key) then
		if always then return true end
		return ns.IsPlaceShowOn(ns.db.takeoffInCity and "cityShow" or "worldShow", key)
	end
	return ns.RowOnNow(key, always, true)
end
-- In a fight a row fits only with In combat ticked (or Always, or by its
-- rule); the death camera's aside: you die in one.
local function FightFits(key, always)
	if always or ns.RuleTest(key) ~= nil or not ns.Flag(UnitAffectingCombat("player")) then return true end
	return ns.IsCombatShowOn(key) and true or false
end
local function RowFits(id)
	local trigger = ns.CameraRowTrigger(id)
	local leader = ns.CameraRowFollow(id)
	if trigger.key ~= "Death" then
		local key, always = ROW_KEY[id], ns.CameraRowAlways(id)
		if leader and not OwnWhen(id) then key, always = "cam:" .. leader, ns.db["camAlways" .. leader] and true or false end
		if not FightFits(key, always) then return false end
	end
	local flight = trigger.key == "Flight"
	if leader and not OwnWhen(id) then
		return Fits("cam:" .. leader, ns.db["camAlways" .. leader] and true or false, flight)
	end
	return Fits(ROW_KEY[id], ns.CameraRowAlways(id), flight)
end

-- The row a trigger goes by now: the first of its rows whose When fits, or
-- nil (no camera). Worked out once a frame for each trigger.
local nowCache = { at = -1 }
function ns.TriggerRowNow(key)
	if not ns.db or not TRIGGER[key] or DeletedSet()[key] then return nil end
	local now = GetTime()
	if nowCache.at ~= now then
		wipe(nowCache)
		nowCache.at = now
	end
	local id = nowCache[key]
	if id == nil then
		id = false
		for _, each in ipairs(ns.TriggerRowIds(key)) do
			if ns.CameraRowOn(each) and RowFits(each) then
				id = each
				break
			end
		end
		nowCache[key] = id
	end
	return id or nil
end
-- (Settings changed: worked out afresh.)
function ns.CameraRowsChanged()
	wipe(nowCache)
	nowCache.at = -1
end

-- A trigger's setting now (camera, music, cine), from the row it goes by:
-- with none fitting, no camera, and off.
function ns.TriggerSetting(key, field)
	local id = ns.TriggerRowNow(key)
	if not id then
		return field == "camera" and TRIGGER[key] and TRIGGER[key].off or false
	end
	return ns.CameraRowValue(id, field)
end
-- Whether a trigger's camera now is one (and not none).
function ns.TriggerHasCamera(key)
	local camera = ns.TriggerSetting(key, "camera")
	return camera ~= nil and camera ~= false and camera ~= "none"
end

-- Whether any of a trigger's rows, here or anywhere, has a camera (or a
-- setting, field, ticked): for greying a camera's settings out.
function ns.TriggerAnyRow(key, field)
	local trigger = TRIGGER[key]
	if not trigger or not ns.GetDB() then return false end
	for _, id in ipairs(ns.TriggerRowIds(key)) do
		local value = ns.CameraRowOn(id) and ns.CameraRowValue(id, field or "camera")
		if field and value then return true end
		if not field and ns.CameraRowOn(id) and value ~= trigger.off then return true end
	end
	return false
end

-- The trigger a camera mode is running for: its own (flights, auto-walk...),
-- or the event that picked it (the AFK, cozy, vista, fish and tele cameras).
local MODE_TRIGGER = { flight = "Flight", taxi = "Flight", walk = "Walk", run = "Run", death = "Death",
	chatcam = "Chat" }
function ns.CameraModeTrigger(mode)
	if mode == "quest" then return ns.QuestCamEvent and ns.QuestCamEvent() or "Quest" end
	if MODE_TRIGGER[mode] then return MODE_TRIGGER[mode] end
	local key = ns.ActiveEvent and ns.ActiveEvent()
	if key and TRIGGER[key] then return key end
	return mode == "idle" and "Still" or nil
end

-- The cameras with a trigger of their own: off here unless the row their
-- trigger goes by now is set to them. (The chat camera: either of its rows.)
local OWN_TRIGGER = { flight = { "Flight" }, walk = { "Walk" }, run = { "Run" }, death = { "Death" },
	chatcam = { "Chat", "ChatNearby" } }
function ns.CameraRowsOff(cam)
	local keys = OWN_TRIGGER[cam]
	if cam == "quest" then keys = { ns.QuestCamEvent and ns.QuestCamEvent() or "Quest" } end
	-- (A trigger of your own running it: CustomTriggers.lua.)
	if cam == "death" and ns.CustomDeathOn and ns.CustomDeathOn() then return false end
	if not keys then return false end -- (the event cameras: their rows decide as an event picks one)
	for _, key in ipairs(keys) do
		if TRIGGER[key] and CamOf(ns.TriggerSetting(key, "camera")) == cam then return false end
	end
	return true
end

-- A camera's Calm Timer wait now: the row its trigger goes by.
function ns.CameraWaitsForCalm(mode)
	local key = ns.CameraModeTrigger(mode)
	local id = key and ns.TriggerRowNow(key)
	return id and ns.CameraRowCalm(id) or false
end

-- A copy of a row: the next free number of its trigger, nil with all taken.
function ns.FreeCameraRow(key)
	local on = {}
	for _, id in ipairs(ns.CameraRowOrder()) do on[id] = true end
	for copy = 2, ns.CAMERA_ROW_COPIES do
		if not on[key .. copy] then return key .. copy end
	end
end

-- Puts the rows in this order (a list of ids).
function ns.SetCameraRowOrder(list)
	ns.GetDB().cameraRows.order = table.concat(list, ",")
	ns.CameraRowsChanged()
end

-- A copy of row id, just below it: its camera, music, CineMode, name and
-- When written out (its trigger's own row's, its camera's where it follows
-- it). Gives the copy's id, or nil.
function ns.CopyCameraRow(id)
	local trigger = ns.CameraRowTrigger(id)
	local new = trigger and ns.FreeCameraRow(trigger.key)
	if not new then return nil end
	local db, rows = ns.GetDB(), ns.GetDB().cameraRows
	for _, field in ipairs({ "camera", "music", "cine" }) do
		rows[new .. "." .. field] = ns.CameraRowValue(id, field)
	end
	local own = rows[id .. ".name"]
	rows[new .. ".name"] = type(own) == "string" and own:find("%S") and (L["%s (copy)"]):format(own):sub(1, 40) or nil
	ns.CameraRowFollow(id)
	local from = (Leader(id) and not OwnWhen(id)) and ("cam:" .. Leader(id)) or ROW_KEY[id]
	if from == ROW_KEY[id] then
		rows[new .. ".always"] = ns.CameraRowAlways(id)
	else
		rows[new .. ".always"] = db["camAlways" .. Leader(id)] and true or false
	end
	rows[new .. ".calm"] = ns.CameraRowCalm(id)
	rows[new .. ".off"] = rows[id .. ".off"]
	local IS_ON = { combatShow = ns.IsCombatShowOn, calmShow = ns.IsCalmShowOn, quietShow = ns.IsQuietShowOn,
		camShow = ns.IsCamShowOn, enemyShow = ns.IsEnemyShowOn, friendlyShow = ns.IsFriendlyShowOn }
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if type(db[list]) ~= "table" then db[list] = {} end
		if IS_ON[list] then
			db[list][ROW_KEY[new]] = IS_ON[list](from) and true or false
		elseif list:find("Show$") then
			db[list][ROW_KEY[new]] = ns.IsPlaceShowOn(list, from) and true or false
		else
			db[list][ROW_KEY[new]] = db[list][from]
		end
	end
	local order = ns.CameraRowOrder()
	local list, at = {}, nil
	for i, each in ipairs(order) do
		list[i] = each
		if each == id then at = i + 1 end
	end
	table.insert(list, at or #list + 1, new)
	ns.SetCameraRowOrder(list)
	return new
end

-- Takes a copy off (a trigger's own row stays: its camera goes to none).
function ns.RemoveCameraRow(id)
	local _, copy = ns.CameraRowTrigger(id)
	if not copy then return end
	local db, rows = ns.GetDB(), ns.GetDB().cameraRows
	for _, field in ipairs({ "camera", "music", "cine", "name", "always", "calm", "off" }) do
		rows[id .. "." .. field] = nil
	end
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if type(db[list]) == "table" then db[list][ROW_KEY[id]] = nil end
	end
	local list = {}
	for _, each in ipairs(ns.CameraRowOrder()) do
		if each ~= id then list[#list + 1] = each end
	end
	ns.SetCameraRowOrder(list)
end

-- Moves a row up (by -1) or down among its trigger's rows.
function ns.MoveCameraRow(id, by)
	local trigger = ns.CameraRowTrigger(id)
	local list = {}
	for i, each in ipairs(ns.CameraRowOrder()) do list[i] = each end
	for i, each in ipairs(list) do
		local other = list[i + by]
		if each == id and other and ns.CameraRowTrigger(other) == trigger then
			list[i], list[i + by] = other, each
			break
		end
	end
	ns.SetCameraRowOrder(list)
end

-- For /cine debug: each trigger's rows, and the one it goes by now.
function ns.DescribeCameraRows()
	local lines = {}
	for _, trigger in ipairs(TRIGGERS) do
		local ids = ns.TriggerRowIds(trigger.key)
		local now = ns.TriggerRowNow(trigger.key)
		lines[#lines + 1] = ("%s: %s -> %s (%s)"):format(trigger.key, table.concat(ids, ","), tostring(now),
			tostring(ns.TriggerSetting(trigger.key, "camera")))
	end
	return lines
end
