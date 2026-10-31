-- Cinematic: camera scripts (dev copy for now). A camera written as a list of
-- small steps: rotate, tilt, zoom (to a distance, or somewhere at random),
-- wait, line up behind you, do an emote, put everything back; Together runs
-- its steps side by side, Repeat runs them again (or until the camera ends).
-- Stop rules say what happens when you move the camera, a fight starts, you
-- walk, you zoom, or its trigger ends; When it ends is a list of steps of its
-- own (usually Put back). CameraScriptsPage.lua is the page that writes them.
--
-- A script is a camera like the built-in ones: a Cameras page row set to it
-- starts it (a standing-still trigger, one of your own, a Hearthstone or
-- teleport cast, or a flight), or Run now on its page, or /cine script play.
-- The built-in ones are examples: the steps our own cameras take (fly-by,
-- quest cam, Chat Cam, standing-still zoom), with your settings, to copy.
--
-- The moves go out as the quest cam's do (QuestCam.lua says why at length):
-- one held turn, tilt or zoom per move, its speed setting stepped along an
-- eased curve, sent at the share of your speed setting that makes it the
-- move's top speed; a creep start under the lowest setting (no jump on the
-- first frame); a turn and a tilt never at once, with a short gap between
-- moves; the zoom steered toward its eased path. Camera follow is off while
-- one runs. One camera at a time (ns.ClaimCamera): it holds the view from
-- start to end, and your camera input stops its moves at once.
--
-- Saved in db.cameraScripts (all profiles share it): list (your scripts),
-- nextId, preview (the preview window's place). A row's camera value for a
-- script is "script:<id>".
local _, ns = ...
local L = ns.L

local WHO = "script"
local MOVE_MIN_TIME = 1     -- seconds: the shortest turn, tilt or zoom
local MIN_SETTING = 1       -- the lowest speed setting sent (lower, the game uses its full speed)
local MIN_SPEED = 1         -- degrees a second: the slowest a move goes (its end creeps in at this)
local CHANGE = 0.02         -- speed setting changes smaller than this share aren't sent
local PRIME_TIME = 0.2      -- seconds the lowest setting goes in before a move starts...
local PRIME_SHARE = 0.001   -- ...creeping meanwhile at this share of it (see FLYBY.PRIME_SHARE)
local RESTORE_DELAY = 0.3   -- seconds after a move stops before your speed setting comes back
local STEP_GAP = 0.6        -- seconds between a turn or tilt stopping and the next starting
local MAX_STEPS = 80        -- steps in a script, all lists and depths together
local MAX_DEPTH = 4         -- Together and Repeat inside each other
local MAX_SCRIPTS = 30
local EASES = { smooth = 0.5, gentle = 0.35, steady = 0.15 } -- share of a move spent speeding up (and slowing down)
local FOLLOW_CVARS = { values = { cameraSmoothStyle = "0" } } -- camera follow off meanwhile
ns.CAMERA_SCRIPT_EASES = { "smooth", "gentle", "steady" }

-- ---------------------------------------------------------------------------
-- The steps
-- ---------------------------------------------------------------------------

-- Each kind: its fields { key, kind ("num" min max, or "pick" choices), default }.
-- group: holds steps of its own.
ns.CAMERA_SCRIPT_KINDS = {
	rotate = { fields = { { "deg", "num", 1, 3600, 45 }, { "secs", "num", 0.5, 600, 4 },
		{ "way", "pick", { "left", "right", "random" }, "left" }, { "ease", "pick", ns.CAMERA_SCRIPT_EASES, "smooth" } } },
	tilt = { fields = { { "deg", "num", -80, 80, 10 }, { "secs", "num", 0.5, 600, 3 } } },
	zoom = { fields = { { "to", "num", 0.5, 50, 5 }, { "secs", "num", 0.5, 600, 3 } } },
	zoomRand = { fields = { { "min", "num", 0.5, 50, 3 }, { "max", "num", 0.5, 50, 8 }, { "secs", "num", 0.5, 600, 6 } } },
	lineup = { fields = { { "secs", "num", 0.5, 600, 3 } } },
	wait = { fields = { { "secs", "num", 0, 3600, 2 } } },
	emote = { fields = { { "token", "text", "wave" } } },
	putback = { fields = { { "secs", "num", 0.5, 600, 3 } } },
	together = { group = true, fields = {} },
	["repeat"] = { group = true, fields = { { "times", "num", 0, 100, 2 } } },
}
ns.CAMERA_SCRIPT_ADDABLE = { "rotate", "tilt", "zoom", "zoomRand", "lineup", "wait", "together", "repeat", "emote",
	"putback" }
local KINDS = ns.CAMERA_SCRIPT_KINDS

-- The stop rules: each event's actions (the first is its default).
ns.CAMERA_SCRIPT_RULES = {
	{ key = "camera", actions = { "stop", "putback", "pause", "restart" } },
	{ key = "fight", actions = { "putback", "stop" } },
	{ key = "walk", actions = { "putback", "stop", "pause", "restart", "ignore" } },
	{ key = "zoom", actions = { "ignore", "stop", "putback", "pause" } },
	{ key = "ends", actions = { "putback", "stop" } },
}
local RULE_ACTIONS = {}
for _, rule in ipairs(ns.CAMERA_SCRIPT_RULES) do
	RULE_ACTIONS[rule.key] = {}
	for _, action in ipairs(rule.actions) do RULE_ACTIONS[rule.key][action] = true end
end

-- A step with its kind's defaults.
function ns.NewCameraScriptStep(kind)
	local def = KINDS[kind]
	if not def then return nil end
	local step = { k = kind }
	for _, field in ipairs(def.fields) do
		step[field[1]] = field[#field]
	end
	if def.group then step.steps = {} end
	return step
end

-- A field's value made safe: a number in its range, a choice it has, a short
-- word for an emote.
local function CleanField(field, value)
	local kind = field[2]
	if kind == "num" then
		value = tonumber(value)
		if not value or value ~= value then return field[5] end
		return math.max(field[3], math.min(field[4], value))
	elseif kind == "pick" then
		for _, choice in ipairs(field[3]) do
			if value == choice then return value end
		end
		return field[4]
	end
	value = type(value) == "string" and value:lower():match("^%s*(%a+)%s*$")
	return value and #value <= 24 and value or field[3]
end
ns.CleanCameraScriptField = CleanField

-- A list of steps made safe (from a share string, or saved by an older
-- version): unknown kinds dropped, fields in range, depth and count capped.
local function CleanSteps(list, depth, budget)
	local out = {}
	if type(list) ~= "table" then return out end
	for _, step in ipairs(list) do
		local def = type(step) == "table" and KINDS[step.k]
		if def and budget.left > 0 and not (def.group and depth >= MAX_DEPTH) then
			budget.left = budget.left - 1
			local clean = { k = step.k }
			for _, field in ipairs(def.fields) do
				clean[field[1]] = CleanField(field, step[field[1]])
			end
			if def.group then clean.steps = CleanSteps(step.steps, depth + 1, budget) end
			out[#out + 1] = clean
		end
	end
	return out
end

local function CleanName(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|", ""):gsub("%c", " "):match("^%s*(.-)%s*$")
	if #text > 40 then text = text:sub(1, 40):gsub("[\192-\255][\128-\191]*$", "") end
	return text ~= "" and text or nil
end

-- A whole script made safe; its id kept if given.
function ns.CleanCameraScript(script, id)
	if type(script) ~= "table" then return nil end
	local budget = { left = MAX_STEPS }
	local rules = {}
	local given = type(script.rules) == "table" and script.rules or {}
	for _, rule in ipairs(ns.CAMERA_SCRIPT_RULES) do
		local action = given[rule.key]
		rules[rule.key] = RULE_ACTIONS[rule.key][action] and action or rule.actions[1]
		local secs = tonumber(given[rule.key .. "Secs"])
		rules[rule.key .. "Secs"] = secs and math.max(1, math.min(60, secs)) or 5
	end
	return {
		id = id or script.id,
		name = CleanName(script.name) or L["My camera"],
		steps = CleanSteps(script.steps, 1, budget),
		ending = CleanSteps(script.ending, 1, budget),
		rules = rules,
	}
end

-- ---------------------------------------------------------------------------
-- The scripts: the built-in examples and yours
-- ---------------------------------------------------------------------------

local function S(kind, fields)
	local step = ns.NewCameraScriptStep(kind)
	for k, v in pairs(fields or {}) do step[k] = v end
	return step
end

-- The built-in ones, from your settings now (each a function: they follow them).
local function Db(key, fallback)
	local value = ns.db and tonumber(ns.db[key])
	return value or fallback
end
local BUILT_IN = {
	{ id = "flyby", name = "Fly-by", make = function()
		return {
			steps = { S("wait", { secs = 1 }), S("lineup", { secs = 1.5 }),
				S("rotate", { deg = Db("flyByAngle", 160), secs = Db("flyByTurnTime", 8), way = "random" }),
				S("wait", { secs = Db("flyByHold", 5) }), S("lineup", { secs = Db("flyByBackTime", 6) }) },
			ending = {},
			rules = { camera = "stop", fight = "stop", walk = "stop", zoom = "ignore", ends = "stop" },
		}
	end },
	{ id = "quest", name = "Quest cam", make = function()
		local drift = Db("questCamDrift", 4)
		return {
			steps = { S("wait", { secs = Db("questCamDelay", 3) }),
				S("together", { steps = { S("zoom", { to = Db("questCamDistance", 4), secs = Db("questCamZoomMaxTime", 8) }),
					S("lineup", { secs = Db("questCamTime", 3) }) } }),
				S("rotate", { deg = math.max(1, Db("questCamAngle", 30)), secs = Db("questCamTurnTime", 4), way = "random",
					ease = "gentle" }),
				S("tilt", { deg = Db("questCamLower", 0), secs = 4 }),
				S("repeat", { times = 0, steps = { S("rotate", { deg = math.max(1, drift), secs = 7, ease = "steady" }),
					S("rotate", { deg = math.max(1, drift), secs = 7, way = "right", ease = "steady" }) } }) },
			ending = { S("putback", { secs = 4 }) },
			rules = { camera = "stop", fight = "putback", walk = "putback", zoom = "stop", ends = "putback" },
		}
	end },
	{ id = "chat", name = "Chat Cam", make = function()
		return {
			steps = { S("together", { steps = { S("zoom", { to = Db("chatCamDistance", 4), secs = 4 }),
				S("rotate", { deg = 20, secs = 3, way = "random" }) } }),
				S("repeat", { times = 0, steps = { S("rotate", { deg = 3, secs = 5, ease = "steady" }),
					S("rotate", { deg = 3, secs = 5, way = "right", ease = "steady" }) } }) },
			ending = { S("putback", { secs = 4 }) },
			rules = { camera = "stop", fight = "putback", walk = "stop", zoom = "stop", ends = "putback" },
		}
	end },
	{ id = "still", name = "Standing still zoom", make = function()
		local far = Db("idleZoomDistance", 6)
		return {
			steps = { S("zoom", { to = far, secs = Db("idleZoomTime", 20) }),
				S("repeat", { times = 0, steps = { S("wait", { secs = Db("idleZoomPause", 10) }),
					S("zoomRand", { min = Db("idleZoomIn", 2), max = far, secs = Db("idleZoomTime", 20) }) } }) },
			ending = { S("putback", { secs = 2 }) },
			rules = { camera = "stop", fight = "putback", walk = "putback", zoom = "stop", ends = "putback" },
		}
	end },
	{ id = "orbit", name = "Slow orbit", make = function()
		return {
			steps = { S("wait", { secs = 1 }),
				S("together", { steps = { S("rotate", { deg = 360, secs = 40, ease = "steady" }),
					S("zoom", { to = 6, secs = 12 }) } }),
				S("wait", { secs = 2 }) },
			ending = { S("putback", { secs = 3 }) },
			rules = { camera = "pause", cameraSecs = 5, fight = "putback", walk = "putback", zoom = "ignore",
				ends = "putback" },
		}
	end },
}
ns.OnLanguage(function()
	for _, each in ipairs(BUILT_IN) do each.name = L[each.name] end
end)

local function Store()
	local db = ns.db or (ns.GetDB and ns.GetDB())
	if not db then return nil end
	if type(db.cameraScripts) ~= "table" then db.cameraScripts = {} end
	local store = db.cameraScripts
	if type(store.list) ~= "table" then store.list = {} end
	store.nextId = tonumber(store.nextId) or 1
	return store
end

-- Every script: the built-in ones (builtin = true) then yours, in order.
function ns.CameraScripts()
	local list = {}
	for _, each in ipairs(BUILT_IN) do
		local script = ns.CleanCameraScript(each.make(), each.id)
		script.name, script.builtin = each.name, true
		list[#list + 1] = script
	end
	local store = Store()
	for _, script in ipairs(store and store.list or {}) do
		if type(script) == "table" and script.id then list[#list + 1] = script end
	end
	return list
end

function ns.FindCameraScript(id)
	for _, script in ipairs(ns.CameraScripts()) do
		if script.id == id then return script end
	end
end

-- Yours (the table saved), or nil for a built-in one.
local function Mine(id)
	local store = Store()
	for i, script in ipairs(store and store.list or {}) do
		if script.id == id then return script, i end
	end
end
ns.MyCameraScript = Mine

-- A new script of yours: a copy of from (any script), or a few steps to start
-- with. Gives it, or nil with all MAX_SCRIPTS made.
function ns.AddCameraScript(from, name)
	local store = Store()
	if not store or #store.list >= MAX_SCRIPTS then return nil end
	local id = "u" .. store.nextId
	store.nextId = store.nextId + 1
	local script = ns.CleanCameraScript(from or {
		steps = { S("wait", { secs = 1 }), S("rotate", { deg = 90, secs = 8 }), S("wait", { secs = 2 }) },
		ending = { S("putback", { secs = 3 }) },
	}, id)
	script.name = CleanName(name) or (from and L["%s (copy)"]:format(from.name):sub(1, 40)) or L["My camera"]
	store.list[#store.list + 1] = script
	ns.SyncScriptCameras()
	return script
end

-- Deletes one of yours; rows of this profile set to it go back to no camera.
function ns.DeleteCameraScript(id)
	local _, at = Mine(id)
	if not at then return end
	table.remove(Store().list, at)
	local value = "script:" .. id
	for _, row in ipairs(ns.CameraRowOrder()) do
		if ns.CameraRowValue(row, "camera") == value then
			ns.SetCameraRowValue(row, "camera", ns.CameraRowTrigger(row).off)
		end
	end
	ns.CameraRowsChanged()
	ns.SyncScriptCameras()
end

-- A script's settings changed (its name, or a step): the Cameras page's
-- names follow.
function ns.CameraScriptChanged()
	ns.SyncScriptCameras()
end

-- ---------------------------------------------------------------------------
-- Scripts as cameras on the Cameras page
-- ---------------------------------------------------------------------------

function ns.IsScriptCamera(value)
	return type(value) == "string" and value:sub(1, 7) == "script:"
end
local IsScript = ns.IsScriptCamera

-- The triggers whose rows may pick a script: those with a standing-still
-- camera (theirs or your own triggers'), a Hearthstone or teleport's, or a
-- flight's.
local TAKES = { afk = true, tele = true, flight = true }
local function TakesScripts(list)
	for _, value in ipairs(list) do
		if TAKES[value] then return true end
	end
	return false
end
function ns.TriggerTakesScripts(trigger)
	return type(trigger.cameras) == "table" and TakesScripts(trigger.cameras)
end

-- Puts every script in those triggers' camera lists (before "none") and
-- its name in ns.CAMERA_NAMES. (The lists are shared between triggers: each
-- done once.)
function ns.SyncScriptCameras()
	if not ns.CAMERA_TRIGGERS or not ns.CAMERA_NAMES then return end
	for value in pairs(ns.CAMERA_NAMES) do
		if IsScript(value) then ns.CAMERA_NAMES[value] = nil end
	end
	local values = {}
	for _, script in ipairs(ns.CameraScripts()) do
		local value = "script:" .. script.id
		values[#values + 1] = value
		ns.CAMERA_NAMES[value] = L["Script: %s"]:format(script.name)
	end
	local done = {}
	for _, trigger in ipairs(ns.CAMERA_TRIGGERS) do
		local list = trigger.cameras
		if type(list) == "table" and not done[list] and TakesScripts(list) then
			done[list] = true
			for i = #list, 1, -1 do
				if IsScript(list[i]) then table.remove(list, i) end
			end
			local at = #list + 1
			for i, value in ipairs(list) do
				if value == "none" then at = i break end
			end
			for i, value in ipairs(values) do table.insert(list, at + i - 1, value) end
		end
	end
end
-- (A trigger added later, one of your own say: its list too.)
if ns.RegisterCameraTrigger then
	hooksecurefunc(ns, "RegisterCameraTrigger", function() ns.SyncScriptCameras() end)
end

-- A trigger's name, as the Cameras page shows it.
function ns.CameraTriggerName(key)
	local trigger = ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER[key]
	if not trigger then return tostring(key) end
	if trigger.custom and ns.CustomTriggerLabel then return ns.CustomTriggerLabel(key) end
	for _, event in ipairs(ns.EVENTS or {}) do
		if event.key == key then return event.label end
	end
	return key
end

-- The Cameras page rows set to a script: their trigger keys, each once.
function ns.CameraScriptTriggers(id)
	local value, keys, seen = "script:" .. id, {}, {}
	for _, row in ipairs(ns.CameraRowOrder()) do
		local trigger = ns.CameraRowTrigger(row)
		if trigger and not seen[trigger.key] and ns.CameraRowValue(row, "camera") == value then
			seen[trigger.key] = true
			keys[#keys + 1] = trigger.key
		end
	end
	return keys
end

-- Sets a trigger's own row to a script (or, on = false, back to no camera
-- if it was this one).
function ns.UseCameraScriptFor(key, id, on)
	local trigger = ns.CAMERA_TRIGGER[key]
	if not trigger then return end
	local value = "script:" .. id
	if on then
		ns.SetCameraRowValue(key, "camera", value)
		ns.SetCameraRowOn(key, true)
	elseif ns.CameraRowValue(key, "camera") == value then
		ns.SetCameraRowValue(key, "camera", trigger.off)
	end
	ns.CameraRowsChanged()
	if ns.RefreshCameraRows then ns.RefreshCameraRows() end
end

-- ---------------------------------------------------------------------------
-- The plan: a script laid out in time, for the preview (no camera moves)
-- ---------------------------------------------------------------------------

local function Wrap(angle)
	return (angle + 180) % 360 - 180
end

-- Share (0-1) of a move covered at t along T seconds, with ease*T ramps at
-- either end (as QuestCam.lua's EaseProgress).
local function EaseProgress(t, T, ease)
	if t <= 0 then return 0 end
	if t >= T then return 1 end
	local R = ease * T
	if R <= 0 then return t / T end
	local function ramp(u) return u / 2 - R / (2 * math.pi) * math.sin(math.pi * u / R) end
	local covered
	if t < R then
		covered = ramp(t)
	elseif t <= T - R then
		covered = R / 2 + (t - R)
	else
		covered = (T - R) - ramp(T - t)
	end
	return covered / (T - R)
end
ns.CameraScriptEase = EaseProgress

-- { moves = { axis, from, to, t0, t1, ease, top }, spans = { step, t0, t1 },
-- endStart, total }. Repeat-until-it-ends goes three times. start: { yaw,
-- pitch, zoom } as it begins.
local PREVIEW_REPEATS = 3
function ns.PlanCameraScript(script, start)
	local moves, spans = {}, {}
	local seed = 7
	local function Random()
		seed = (seed * 9301 + 49297) % 233280
		return seed / 233280
	end
	local state = { yaw = start.yaw, pitch = start.pitch, zoom = start.zoom }
	local busyUntil = { yaw = 0, pitch = 0 } -- (a turn and a tilt one at a time)
	local One
	local function Run(list, t, top)
		for _, step in ipairs(list) do t = One(step, t, top or step) end
		return t
	end
	local function Move(axis, to, t, secs, ease, top)
		if axis == "yaw" or axis == "pitch" then
			local other = axis == "yaw" and "pitch" or "yaw"
			if busyUntil[other] > t then t = busyUntil[other] + STEP_GAP end
		end
		secs = math.max(MOVE_MIN_TIME, secs or 0)
		moves[#moves + 1] = { axis = axis, from = state[axis], to = to, t0 = t, t1 = t + secs, ease = ease, top = top }
		state[axis] = to
		if busyUntil[axis] then busyUntil[axis] = t + secs end
		return t + secs
	end
	local function Hold(t, secs, top)
		moves[#moves + 1] = { axis = "none", t0 = t, t1 = t + secs, top = top }
		return t + secs
	end
	function One(step, t, top)
		local from, ending = t, t
		local k = step.k
		if k == "rotate" then
			local way = step.way == "random" and (Random() < 0.5 and "left" or "right") or step.way
			ending = Move("yaw", state.yaw + (way == "left" and step.deg or -step.deg), t, step.secs, EASES[step.ease], top)
		elseif k == "tilt" then
			ending = step.deg ~= 0 and Move("pitch", state.pitch + step.deg, t, step.secs, 0.5, top) or t
		elseif k == "zoom" then
			ending = Move("zoom", step.to, t, step.secs, EASES.gentle, top)
		elseif k == "zoomRand" then
			local low, high = math.min(step.min, step.max), math.max(step.min, step.max)
			ending = Move("zoom", low + Random() * (high - low), t, step.secs, EASES.gentle, top)
		elseif k == "lineup" then
			ending = Move("yaw", state.yaw - Wrap(state.yaw), t, step.secs, 0.5, top)
		elseif k == "putback" then
			local turned = Move("yaw", state.yaw - Wrap(state.yaw), t, step.secs, 0.5, top)
			Move("zoom", start.zoom, t, step.secs, EASES.gentle, top)
			ending = math.max(turned, Move("pitch", start.pitch, turned, step.secs, 0.5, top))
		elseif k == "wait" then
			ending = Hold(t, step.secs, top)
		elseif k == "emote" then
			ending = Hold(t, 0.5, top)
		elseif k == "together" then
			for _, child in ipairs(step.steps) do ending = math.max(ending, One(child, t, top)) end
		elseif k == "repeat" then
			for _ = 1, step.times > 0 and step.times or PREVIEW_REPEATS do
				local before = t
				t = Run(step.steps, t, top)
				if t == before then break end
			end
			ending = t
		end
		if top == step then spans[#spans + 1] = { step = step, t0 = from, t1 = ending } end
		return ending
	end
	local endStart = Run(script.steps, 0)
	local total = Run(script.ending, endStart)
	return { moves = moves, spans = spans, endStart = endStart, total = math.max(total, 1) }
end

-- Where the plan has the camera at t: yaw, pitch, zoom, and the top-level
-- step under way (nil between them).
function ns.SampleCameraPlan(plan, t, start)
	local yaw, pitch, zoom, active = start.yaw, start.pitch, start.zoom, nil
	for _, move in ipairs(plan.moves) do
		if move.t0 <= t then
			if t < move.t1 then active = move.top end
			if move.axis ~= "none" then
				local value = move.from + (move.to - move.from) * EaseProgress(t - move.t0, move.t1 - move.t0, move.ease or 0.5)
				if move.axis == "yaw" then yaw = value elseif move.axis == "pitch" then pitch = value else zoom = value end
			end
		end
	end
	return yaw, pitch, zoom, active
end

-- ---------------------------------------------------------------------------
-- The runner: moving the real camera
-- ---------------------------------------------------------------------------

local function EaseShape(t, T, ease)
	local R = ease * T
	if R <= 0 then
		return 1
	elseif t < R then
		return (1 - math.cos(math.pi * t / R)) / 2
	elseif t > T - R then
		return (1 - math.cos(math.pi * (T - t) / R)) / 2
	end
	return 1
end

local run -- the script running: see Start
local restoring = 0 -- speed settings still to come back (a moment after each move)

local function Send(name, amount)
	return ns.CameraCall(WHO, name, amount)
end

-- The turn and the tilt. amount: degrees counted from where the script
-- started (yaw: the view turned left; pitch: down).
local movers = {
	yaw = { name = "yaw", amount = 0, cvar = "cameraYawMoveSpeed", who = "script:yaw",
		grow = "MoveViewLeft", shrink = "MoveViewRight" },
	pitch = { name = "pitch", amount = 0, cvar = "cameraPitchMoveSpeed", who = "script:pitch",
		grow = "MoveViewDown", shrink = "MoveViewUp" },
}
movers.yaw.other, movers.pitch.other = movers.pitch, movers.yaw
local lastStop = -math.huge -- when a turn or tilt last stopped

local function Command(m)
	return m.growing and m.grow or m.shrink
end

local function StopMove(m)
	m.pending = false
	if not m.moving then return end
	if m.sent or m.creeping then Send(Command(m) .. "Stop") end
	m.moving, m.sent, m.creeping = false, nil, nil
	lastStop = GetTime()
	restoring = restoring + 1
	C_Timer.After(RESTORE_DELAY, function()
		restoring = restoring - 1
		if not m.moving then ns.ReleaseSpeed(m.who, m.cvar) end
	end)
end

-- Moves to target degrees over T seconds (it sets off once it can: see Begin).
local function MoveTo(m, target, T, ease)
	StopMove(m)
	m.suspended = nil
	m.target, m.t, m.T, m.ease = target, 0, math.max(MOVE_MIN_TIME, T or 0), ease or EASES.smooth
	m.pending = math.abs(target - m.amount) >= 0.5
end

-- Sets a pending move off: not with the other axis moving, nor within
-- STEP_GAP of a move stopping, nor without the view.
local function Begin(m)
	local now = GetTime()
	if m.other.moving or now - lastStop < STEP_GAP or not ns.ClaimCamera(WHO) then return end
	local yours = ns.HoldSpeed(m.who, m.cvar)
	m.cruise = math.abs(m.target - m.amount) / (m.T * (1 - m.ease))
	m.share = m.cruise / yours
	ns.SetHeldSpeed(m.who, m.cvar, MIN_SETTING)
	m.primedUntil = now + PRIME_TIME
	m.growing = m.target > m.amount
	m.pending = false
	if Send(Command(m) .. "Start", PRIME_SHARE) then
		m.creeping, m.moving, m.sent, m.t = true, true, nil, 0
	else
		m.pending = true
		ns.ReleaseSpeed(m.who, m.cvar)
	end
end

local function StepMove(m, elapsed)
	if m.pending then
		Begin(m)
		return
	end
	if not m.moving or GetTime() < m.primedUntil then return end
	m.t = m.t + elapsed
	if (m.target > m.amount) ~= m.growing or math.abs(m.target - m.amount) < 0.05 or m.t > m.T + 3 then
		StopMove(m)
		return
	end
	local speed = math.max(MIN_SPEED, m.cruise * EaseShape(math.min(m.t, m.T), m.T, m.ease))
	local setting = math.max(MIN_SETTING, speed / m.share)
	if not m.sent then
		Send(Command(m) .. "Start", m.share)
		m.sent = MIN_SETTING
	elseif math.abs(setting - m.sent) > m.sent * CHANGE then
		ns.SetHeldSpeed(m.who, m.cvar, setting)
		m.sent = setting
	end
	speed = m.sent * m.share
	m.amount = m.amount + (m.growing and speed or -speed) * elapsed
end

local function MoverDone(m)
	return not (m.pending or m.moving or m.suspended)
end

-- The zoom: steered along its eased path (as the quest cam's: the game
-- doesn't go exactly the distance asked, so commands toward where the path
-- will be shortly, from where the camera is; the zoom speed setting just
-- above the path's speed meanwhile, then eased back to yours).
local ZOOM_CVAR, ZOOM_WHO = "cameraZoomSpeed", "script:zoom"
local ZOOM_DONE, ZOOM_STILL, ZOOM_SETTLED, ZOOM_GIVE_UP = 0.05, 0.002, 0.4, 4
local ZOOM_SEND_EVERY, ZOOM_LEAD, ZOOM_GAIN = 0.1, 0.25, 0.6
local ZOOM_HEADROOM, ZOOM_EXTRA, ZOOM_MIN_SPEED, ZOOM_SETTLE_SPEED = 1.3, 0.3, 0.3, 0.5
local ZOOM_RELEASE_TIME = 1.5
local zoomer = { moving = false }

local function Zoom()
	return GetCameraZoom and GetCameraZoom() or 0
end

local function StopZoom()
	zoomer.pending = false
	if not zoomer.moving then return end
	zoomer.moving = false
	local yours = ns.SpeedHeld(ZOOM_CVAR, ZOOM_WHO) and ns.YourSpeed(ZOOM_CVAR)
	if yours and zoomer.sent and yours > zoomer.sent then
		zoomer.release = { from = zoomer.sent, to = yours, t = 0 }
	else
		zoomer.sent = nil
		ns.ReleaseSpeed(ZOOM_WHO, ZOOM_CVAR)
	end
end

local function ZoomTo(distance, T)
	StopZoom()
	zoomer.suspended = nil
	local now = Zoom()
	if math.abs(distance - now) < ZOOM_DONE then return end
	zoomer.goal, zoomer.T = distance, math.max(MOVE_MIN_TIME, T or 0)
	zoomer.pending = true
end

local function BeginZoom()
	if not ns.ClaimCamera(WHO) then return end
	local now = Zoom()
	zoomer.release = nil
	ns.HoldSpeed(ZOOM_WHO, ZOOM_CVAR)
	zoomer.from, zoomer.t = now, 0
	zoomer.cruise = math.abs(zoomer.goal - now) / (zoomer.T * (1 - EASES.gentle))
	zoomer.last, zoomer.sentAt, zoomer.stillSince, zoomer.sent, zoomer.asked = now, 0, nil, nil, 0
	zoomer.pending, zoomer.moving = false, true
end

local function StepZoom(elapsed)
	if zoomer.pending then BeginZoom() end
	if not zoomer.moving then
		local release = zoomer.release
		if release then
			release.t = release.t + elapsed
			local f = release.t / ZOOM_RELEASE_TIME
			if f >= 1 or not ns.SpeedHeld(ZOOM_CVAR, ZOOM_WHO) then
				zoomer.release, zoomer.sent = nil, nil
				ns.ReleaseSpeed(ZOOM_WHO, ZOOM_CVAR)
			else
				ns.SetHeldSpeed(ZOOM_WHO, ZOOM_CVAR, release.from * (release.to / release.from) ^ (f * f))
			end
		end
		return
	end
	local now, zoom = GetTime(), Zoom()
	zoomer.t = zoomer.t + elapsed
	local t, T = zoomer.t, zoomer.T
	local still = math.abs(zoom - zoomer.last) < ZOOM_STILL
	zoomer.last = zoom
	if t >= T and math.abs(zoomer.goal - zoom) < ZOOM_DONE and still then
		zoomer.stillSince = zoomer.stillSince or now
		if now - zoomer.stillSince >= ZOOM_SETTLED then
			StopZoom()
			return
		end
	else
		zoomer.stillSince = nil
	end
	if t >= T + ZOOM_GIVE_UP then
		StopZoom()
		return
	end
	local speed = ZOOM_SETTLE_SPEED
	if t < T then
		speed = math.max(ZOOM_MIN_SPEED, zoomer.cruise * EaseShape(t, T, EASES.gentle) * ZOOM_HEADROOM + ZOOM_EXTRA)
	end
	if not zoomer.sent or math.abs(speed - zoomer.sent) > zoomer.sent * CHANGE then
		ns.SetHeldSpeed(ZOOM_WHO, ZOOM_CVAR, speed)
		zoomer.sent = speed
	end
	-- (Never asking past the path from where the commands sent already have
	-- it heading: they add up in the game.)
	if now - zoomer.sentAt >= ZOOM_SEND_EVERY then
		local point = zoomer.from + (zoomer.goal - zoomer.from) * EaseProgress(math.min(T, t + ZOOM_LEAD), T, EASES.gentle)
		local miss = point - zoom
		local ahead = point - (zoomer.from + zoomer.asked)
		local ask = (ahead > 0) == (miss > 0) and math.min(math.abs(miss) * ZOOM_GAIN, math.abs(ahead)) or 0
		if math.abs(miss) > ZOOM_DONE and ask > 0 then
			zoomer.sentAt = now
			Send(miss < 0 and "CameraZoomIn" or "CameraZoomOut", ask)
			zoomer.asked = zoomer.asked + (miss < 0 and -ask or ask)
		end
	end
end

local function ZoomDone()
	return not (zoomer.pending or zoomer.moving or zoomer.suspended)
end

-- Every move stopped where it is (nothing kept to carry on with).
local function StopAll()
	StopMove(movers.yaw)
	StopMove(movers.pitch)
	movers.yaw.suspended, movers.pitch.suspended = nil, nil
	StopZoom()
	zoomer.suspended = nil
end

-- Paused: each move stopped, what's left of it kept to carry on with.
local function Suspend()
	for _, m in pairs(movers) do
		if m.pending or m.moving then
			m.suspended = { target = m.target, T = math.max(MOVE_MIN_TIME, (m.T or 0) - (m.t or 0)) }
			StopMove(m)
		end
	end
	if zoomer.pending or zoomer.moving then
		zoomer.suspended = { goal = zoomer.goal, T = math.max(MOVE_MIN_TIME, zoomer.T - (zoomer.t or 0)) }
		StopZoom()
	end
end

local function Resume()
	for _, m in pairs(movers) do
		local left = m.suspended
		if left then MoveTo(m, left.target, left.T, m.ease) end
	end
	local left = zoomer.suspended
	if left then ZoomTo(left.goal, left.T) end
end

-- The steps, run in a coroutine: each yields a frame at a time until done.
local Yield = coroutine.yield
local function WaitSeconds(secs)
	local untilT = run.t + secs
	while run.t < untilT do Yield() end
end
local function WaitMover(m)
	while not MoverDone(m) do Yield() end
end
local function WaitZoom()
	while not ZoomDone() do Yield() end
end

local DoStep
local function DoSteps(list)
	for _, step in ipairs(list) do DoStep(step) end
end

local STEP = {}
function STEP.rotate(step)
	local way = step.way == "random" and (math.random() < 0.5 and "left" or "right") or step.way
	local m = movers.yaw
	MoveTo(m, m.amount + (way == "left" and step.deg or -step.deg), step.secs, EASES[step.ease])
	WaitMover(m)
end
function STEP.tilt(step)
	if step.deg == 0 then return end
	local m = movers.pitch
	MoveTo(m, m.amount + step.deg, step.secs, EASES.smooth)
	WaitMover(m)
end
function STEP.zoom(step)
	ZoomTo(step.to, step.secs)
	WaitZoom()
end
function STEP.zoomRand(step)
	local low, high = math.min(step.min, step.max), math.max(step.min, step.max)
	ZoomTo(low + math.random() * (high - low), step.secs)
	WaitZoom()
end
function STEP.lineup(step)
	local m = movers.yaw
	MoveTo(m, m.amount - Wrap(m.amount), step.secs, EASES.smooth)
	WaitMover(m)
end
function STEP.wait(step)
	WaitSeconds(step.secs)
end
function STEP.emote(step)
	local token = step.token:upper()
	if DoEmote then
		pcall(DoEmote, token, "none")
	elseif C_ChatInfo and C_ChatInfo.PerformEmote then
		pcall(C_ChatInfo.PerformEmote, token, "none")
	end
	WaitSeconds(0.5)
end
-- Everything this script turned, tilted and zoomed undone: the turn and the
-- zoom together, then the tilt (the game won't turn and tilt at once).
function STEP.putback(step)
	local yaw, pitch = movers.yaw, movers.pitch
	MoveTo(yaw, yaw.amount - Wrap(yaw.amount), step.secs, EASES.smooth)
	ZoomTo(run.startZoom, step.secs)
	WaitMover(yaw)
	MoveTo(pitch, 0, step.secs, EASES.smooth)
	WaitMover(pitch)
	WaitZoom()
end
function STEP.together(step)
	local kids = {}
	for _, child in ipairs(step.steps) do
		kids[#kids + 1] = coroutine.create(function() DoStep(child) end)
	end
	while true do
		local alive = false
		for _, kid in ipairs(kids) do
			if coroutine.status(kid) ~= "dead" then
				local ok, err = coroutine.resume(kid)
				if not ok then error(err, 0) end
				if coroutine.status(kid) ~= "dead" then alive = true end
			end
		end
		if not alive then return end
		Yield()
	end
end
STEP["repeat"] = function(step)
	local count = 0
	while step.times == 0 or count < step.times do
		count = count + 1
		local before = run.t
		DoSteps(step.steps)
		if run.t == before then Yield() end -- (nothing in it took any time: never spin within a frame)
	end
end

function DoStep(step)
	local action = STEP[step.k]
	if action then
		run.step = step
		action(step)
	end
end

-- Starts a script (trigger: the trigger key it's running for; nil, played
-- from its page or /cine script play).
local function Start(script, trigger, camera)
	if run then StopAll() end
	script = ns.CleanCameraScript(script, script.id) -- (a copy: editing it on its page meanwhile can't trip it up)
	run = {
		script = script, trigger = trigger, camera = camera, t = 0, phase = "steps",
		startZoom = Zoom(), startedAt = GetTime(), inputSeen = ns.GetLastCameraInput and ns.GetLastCameraInput() or 0,
		triggerOn = trigger ~= nil,
	}
	movers.yaw.amount, movers.pitch.amount = 0, 0
	run.co = coroutine.create(function() DoSteps(script.steps) end)
	ns.ApplyCVarSet(FOLLOW_CVARS, true)
	ns.Log("state", ("camera script %s started (%s)"):format(script.name, trigger or "played"))
end

local stoppedFor -- trigger..camera a script was stopped for: not again until that trigger's over

local function Finish(why)
	if not run then return end
	StopAll()
	ns.ApplyCVarSet(FOLLOW_CVARS, false)
	ns.Log("state", ("camera script %s ended (%s)"):format(run.script.name, why or "done"))
	if run.trigger and run.triggerOn then stoppedFor = run.trigger .. run.camera end
	run = nil
end

local function BeginEnding(why)
	StopAll()
	if #run.script.ending == 0 then
		Finish(why)
		return
	end
	run.phase, run.pausedUntil, run.why = "ending", nil, why
	run.co = coroutine.create(function() DoSteps(run.script.ending) end)
end

-- What a stop rule says to do.
local function Act(event)
	local rules = run.script.rules
	local action = rules[event]
	if action == "ignore" then return false end
	if run.phase == "ending" or action == "stop" then
		Finish(event)
	elseif action == "putback" then
		BeginEnding(event)
	elseif action == "pause" then
		if not run.pausedUntil then Suspend() end
		run.pausedUntil = GetTime() + rules[event .. "Secs"]
		run.pausedBy = event
	elseif action == "restart" then
		StopAll()
		run.pausedUntil, run.phase = nil, "steps"
		run.co = coroutine.create(function() DoSteps(run.script.steps) end)
	end
	return true
end

-- The trigger running a script camera now, and that camera: a standing-still
-- trigger's (or your own's, or a cast's), else a flight's.
local function TriggerNow()
	if not ns.db or not ns.db.enabled or not ns.ActiveEvent then return nil end
	local key, camera = ns.ActiveEvent()
	if IsScript(camera) then return key, camera end
	if ns.OnTaxi() and ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER.Flight then
		camera = ns.TriggerSetting("Flight", "camera")
		if IsScript(camera) then return "Flight", camera end
	end
end

local function InFight()
	return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
end

local function Update(elapsed)
	local now = GetTime()
	if not ns.db.enabled then
		Finish("Cinematic off")
		return
	end
	-- Your camera input since the last look: the zoom or the rest.
	local input = ns.GetLastCameraInput and ns.GetLastCameraInput() or 0
	local zoomed, moved = false, false
	if input > run.inputSeen then
		run.inputSeen = input
		if ns.lastPlayerZoomAt == input then zoomed = true else moved = true end
	end
	if run.tookAt then
		moved, run.tookAt = true, nil
	end
	if run.pausedUntil then
		-- Paused: more input keeps it paused; then it carries on.
		if (run.pausedBy == "camera" and (moved or zoomed)) or (run.pausedBy == "zoom" and zoomed)
			or (run.pausedBy == "walk" and ns.playerMoving) then
			run.pausedUntil = now + run.script.rules[run.pausedBy .. "Secs"]
		end
		if InFight() then Act("fight") return end
		if run.trigger and not run.triggerOn then Act("ends") return end
		if now < run.pausedUntil then return end
		run.pausedUntil = nil
		Resume()
	end
	if moved and Act("camera") then return end
	if InFight() and Act("fight") then return end
	if ns.playerMoving and (not ns.MovingManually or ns.MovingManually()) and Act("walk") then return end
	if zoomed then
		if not Act("zoom") then StopZoom() end -- (yours wins: its zoom gives up)
		if not run or run.pausedUntil then return end
	end
	if run.phase == "steps" and run.trigger and not run.triggerOn then
		Act("ends")
		if not run then return end
	end
	if run.pausedUntil then return end
	StepMove(movers.yaw, elapsed)
	StepMove(movers.pitch, elapsed)
	StepZoom(elapsed)
	run.t = run.t + elapsed
	if coroutine.status(run.co) ~= "dead" then
		local ok, err = coroutine.resume(run.co)
		if not ok then
			ns.Print(L["camera script %s stopped: %s"]:format(run.script.name, tostring(err)))
			Finish("error")
			return
		end
	end
	if coroutine.status(run.co) == "dead" then
		if run.phase == "ending" then
			Finish(run.why)
		elseif not run.trigger then
			BeginEnding("done")
		end
		-- (Run for a trigger: it holds where it got to until the trigger's over.)
	end
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(_, elapsed)
	if not ns.db then return end
	local key, camera = TriggerNow()
	if run and run.trigger then
		run.triggerOn = key == run.trigger and camera == run.camera
	end
	if not key then
		stoppedFor = nil
	elseif not run and stoppedFor ~= key .. camera and not InFight() then
		local script = ns.FindCameraScript(camera:sub(8))
		if script then Start(script, key, camera) end
	end
	if run then
		Update(elapsed)
	elseif zoomer.release then
		StepZoom(elapsed) -- (the zoom speed easing back after it ended)
	end
end)
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_LOGOUT")
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		ns.SyncScriptCameras()
	else
		Finish("logging out")
	end
end)

if ns.RegisterCamera then
	ns.RegisterCamera(WHO, function()
		return run ~= nil or restoring > 0 or zoomer.moving or zoomer.release ~= nil
	end, function()
		-- You took the camera: every move stops now (the rules decide next frame).
		if run then
			run.tookAt = GetTime()
			if run.pausedUntil then return end
			Suspend()
			if run.script.rules.camera ~= "pause" then StopAll() end
		end
	end)
end

-- Plays a script now, from its page or a command. False and why if it can't.
function ns.PlayCameraScript(script)
	if not ns.db.enabled then return false, L["Cinematic is off (/cine turns it on)"] end
	if InFight() then return false, L["not in combat"] end
	stoppedFor = nil
	Start(script, nil, nil)
	return true
end

function ns.StopCameraScript()
	if run then Finish("stopped") return true end
	return false
end

-- The one running: its script, phase ("steps" or "ending"), the step under
-- way, seconds in, paused (seconds left), and the trigger.
function ns.CameraScriptState()
	if not run then return nil end
	return {
		script = run.script, phase = run.phase, step = run.step, t = run.t, trigger = run.trigger,
		paused = run.pausedUntil and math.max(0, run.pausedUntil - GetTime()) or nil,
		yaw = movers.yaw.amount, pitch = movers.pitch.amount,
	}
end

-- /cine script: what's running and why (or why not), and the commands.
function ns.CameraScriptCommand(arg)
	local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
	if cmd == "play" then
		local want = rest:lower()
		for _, script in ipairs(ns.CameraScripts()) do
			if script.name:lower() == want or script.id == want then
				local ok, why = ns.PlayCameraScript(script)
				ns.Print(ok and L["playing camera script %s"]:format(script.name) or why)
				return
			end
		end
		ns.Print(L["no camera script called %s"]:format(rest))
	elseif cmd == "stop" then
		ns.Print(ns.StopCameraScript() and L["camera script stopped"] or L["no camera script is running"])
	elseif cmd == "list" then
		for _, script in ipairs(ns.CameraScripts()) do
			local keys = ns.CameraScriptTriggers(script.id)
			ns.Print(("%s [%s]%s: %s"):format(script.name, script.id, script.builtin and " (built-in)" or "",
				#keys > 0 and table.concat(keys, ", ") or "no trigger"))
		end
	else
		local key, camera = TriggerNow()
		local active, activeCam
		if ns.ActiveEvent then active, activeCam = ns.ActiveEvent() end
		ns.Print(("camera scripts: trigger now %s (%s); event %s (%s); flight %s; combat %s; view held by %s"):format(
			tostring(key), tostring(camera), tostring(active), tostring(activeCam), tostring(ns.OnTaxi()),
			tostring(InFight()), tostring(ns.CameraHolder and ns.CameraHolder(WHO) or "?")))
		if run then
			local step = run.step
			ns.Print(("running %s for %s: %s, step %s, %.1f s in%s; counted turn %.1f, tilt %.1f; zoom %.1f (started %.1f)%s"):format(
				run.script.name, tostring(run.trigger or "a play"), run.phase, step and step.k or "-", run.t,
				run.pausedUntil and (", paused %.1f s (%s)"):format(run.pausedUntil - GetTime(), run.pausedBy) or "",
				movers.yaw.amount, movers.pitch.amount, Zoom(), run.startZoom,
				run.trigger and (run.triggerOn and ", trigger on" or ", trigger over") or ""))
			ns.Print(("moves: turn %s, tilt %s, zoom %s; speeds %s / %s / %s"):format(
				movers.yaw.moving and "moving" or movers.yaw.pending and "waiting" or "-",
				movers.pitch.moving and "moving" or movers.pitch.pending and "waiting" or "-",
				zoomer.moving and "moving" or zoomer.pending and "waiting" or "-",
				tostring(GetCVar("cameraYawMoveSpeed")), tostring(GetCVar("cameraPitchMoveSpeed")),
				tostring(GetCVar("cameraZoomSpeed"))))
		else
			ns.Print(("not running%s"):format(stoppedFor and (" (stopped for %s until it's over)"):format(stoppedFor) or ""))
		end
		ns.Print("/cine script list | play <name> | stop")
	end
end
