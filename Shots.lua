-- Cinematic: My Shots. A shot is one of the standing-still cameras (cozy,
-- vista, fish, AFK) with numbers of your own for its sway and zoom: the same
-- moves, set your way. Any trigger that can pick those cameras can pick a
-- shot (the camera value "shot:<id>"); while one runs, Camera.lua's
-- OrbitSetting and ZoomSetting read its numbers (ns.ShotSetting) in place of
-- its camera's, and everything else goes by its camera.
--
-- Saved in db.cameraRows with the Cameras page's rows (so profiles,
-- Save/Reset and share strings carry them): "shots" their ids (ShotA,
-- ShotB...), and per id: name, base (its camera), and a number for each of
-- SHOT_SETTINGS it sets ("<id>.OrbitBackArc"...; nil: its camera's own).
--
-- Also the share strings for a trigger or a shot (CINECAM1:...).
local _, ns = ...
local L = ns.L

ns.SHOT_MAX = 10
ns.SHOT_BASES = { "cozy", "vista", "fish", "afk" }
-- (Each camera's settings' prefix: the AFK camera's are the standing-still ones.)
local PREFIX = { cozy = "cozy", vista = "vista", fish = "fish", afk = "idle" }
-- What a shot can set: the setting after its camera's prefix, its slider.
-- only/not: the cameras it's for (the AFK camera turns round you in steps;
-- the others sway either side of where they settle).
ns.SHOT_SETTINGS = {
	{ key = "OrbitBackArc", label = L["Sway either side"], min = 0, max = 90, step = 1, fmt = "%d°", skip = "afk",
		tip = L["How far the camera may sway either side of where it settles."] },
	{ key = "OrbitStep", label = L["Turn each move"], min = 5, max = 180, step = 5, fmt = "%d°", only = "afk",
		tip = L["How far round you the camera turns with each move."] },
	{ key = "OrbitPitchUp", label = L["Tilt up to"], min = 0, max = 30, step = 1, fmt = "%d°",
		tip = L["How far the camera may tilt up as it moves."] },
	{ key = "OrbitPitchDown", label = L["Tilt down to"], min = 0, max = 30, step = 1, fmt = "%d°",
		tip = L["How far the camera may tilt down as it moves."] },
	{ key = "OrbitMoveTime", label = L["Each move takes"], min = 2, max = 40, step = 1, fmt = L["%d sec"],
		tip = L["How long each move takes, start to stop. Longer is slower and smoother."] },
	{ key = "OrbitPause", label = L["Pause between moves"], min = 0, max = 30, step = 1, fmt = L["%d sec"],
		tip = L["How long the camera holds still between moves."] },
	{ key = "OrbitDriftSpeed", label = L["Drift speed"], min = 0, max = 3, step = 0.1, fmt = "%.1f",
		tip = L["The slow drift the camera keeps up between moves. 0: none."] },
	{ key = "ZoomDistance", label = L["Zoom out up to"], min = 0, max = 15, step = 0.5, fmt = L["%.1f yards"],
		tip = L["How far the camera may pull back from its distance."] },
	{ key = "ZoomIn", label = L["Zoom in up to"], min = 0, max = 10, step = 0.5, fmt = L["%.1f yards"],
		tip = L["How far the camera may come in from its distance."] },
	{ key = "ZoomTime", label = L["Each zoom takes"], min = 2, max = 40, step = 1, fmt = L["%d sec"],
		tip = L["How long each zoom in or out takes."] },
}
ns.OnLanguage(function() ns.TranslateFields(ns.SHOT_SETTINGS, "label", "tip", "fmt") end)
local SETTING = {}
for _, setting in ipairs(ns.SHOT_SETTINGS) do SETTING[setting.key] = setting end

local function Rows()
	local db = ns.db
	return db and type(db.cameraRows) == "table" and db.cameraRows or nil
end

-- The shots in order (worked out again only when the list changes).
local listCache = { text = false, list = {}, set = {} }
function ns.ShotList()
	local rows = Rows()
	local text = rows and tostring(rows.shots or "") or ""
	if listCache.text == text then return listCache.list, listCache.set end
	local list, set = {}, {}
	for id in text:gmatch("[^,]+") do
		if id:find("^Shot%a+$") and not set[id] and #list < ns.SHOT_MAX then
			set[id] = true
			list[#list + 1] = id
		end
	end
	listCache.text, listCache.list, listCache.set = text, list, set
	return list, set
end

-- A shot's id from a camera value ("shot:ShotA"), or nil.
function ns.ShotOf(value)
	if type(value) ~= "string" or not value:find("^shot:") then return nil end
	return value:sub(6)
end
function ns.ShotBaseOf(id)
	local rows = Rows()
	local base = rows and rows[id .. ".base"]
	return PREFIX[base] and base or "cozy"
end
-- A camera value as the camera it runs: a shot's camera, else itself.
function ns.ShotBase(value)
	local id = ns.ShotOf(value)
	if not id then return value end
	return ns.ShotBaseOf(id)
end
function ns.ShotName(id)
	local rows = Rows()
	local name = rows and rows[id .. ".name"]
	if type(name) == "string" and name:find("%S") then return name end
	-- (Unnamed: its camera's name, and the number it was given if that was taken: see AddShot.)
	local num = rows and tonumber(rows[id .. ".num"])
	return (L["%s shot"]):format(ns.CAMERA_NAMES[ns.ShotBaseOf(id)] or "") .. (num and (" (" .. num .. ")") or "")
end
-- Any camera value's name: a shot's, else the camera's.
function ns.CameraName(value)
	local id = ns.ShotOf(value)
	if id then return ns.ShotName(id) end
	return ns.CAMERA_NAMES[value]
end

-- A shot's number for a setting: its own, else its camera's.
function ns.ShotValue(id, key)
	local rows = Rows()
	local own = rows and rows[id .. "." .. key]
	if type(own) == "number" then return own end
	local db = ns.db or ns.GetDB()
	return db[PREFIX[ns.ShotBaseOf(id)] .. key]
end
function ns.SetShotValue(id, key, value)
	if not SETTING[key] then return end
	ns.GetDB().cameraRows[id .. "." .. key] = value
end

-- The shot running now: the one the active event's row picked, or the one
-- My Shots' Test button started. Worked out once a frame.
local activeCache = { at = -1 }
local function ActiveShot()
	local now = GetTime()
	if activeCache.at == now then return activeCache.id end
	activeCache.at = now
	local id
	local key = ns.ActiveEvent and ns.ActiveEvent()
	if key == "Manual" then
		id = ns.testShot
	elseif key then
		id = ns.ShotOf(ns.TriggerSetting(key, "camera"))
	end
	local _, set = ns.ShotList()
	activeCache.id = id and set[id] and id or nil
	return activeCache.id
end
ns.ActiveShot = ActiveShot

-- A camera setting as the camera reads it (OrbitSetting, ZoomSetting): the
-- running shot's number where it sets one for its own camera, else yours.
function ns.ShotSetting(fullKey)
	local db = ns.db
	if #(ns.ShotList()) > 0 then
		local id = ActiveShot()
		local prefix = id and PREFIX[ns.ShotBaseOf(id)]
		if prefix and fullKey:find(prefix, 1, true) == 1 then
			local own = Rows()[id .. "." .. fullKey:sub(#prefix + 1)]
			if type(own) == "number" then return own end
		end
	end
	return db[fullKey]
end

-- A new shot of a camera: its id (nil with all taken). Starts with its
-- camera's numbers (none of its own yet).
function ns.AddShot(base, name)
	local rows = ns.GetDB().cameraRows
	local list, set = ns.ShotList()
	if #list >= ns.SHOT_MAX then return nil end
	local id
	for n = 0, 25 do
		if not set["Shot" .. string.char(65 + n)] then
			id = "Shot" .. string.char(65 + n)
			break
		end
	end
	if not id then return nil end
	-- A name another shot already shows gets the first free number after it,
	-- "Cozy camera shot (1)", so a new one stands out (the same name is
	-- still allowed if you type it). Unnamed, the number's kept apart from
	-- the name, which goes on following its camera.
	local taken = {}
	for _, other in ipairs(list) do taken[ns.ShotName(other)] = true end
	rows[id .. ".base"] = PREFIX[base] and base or "cozy"
	rows[id .. ".name"], rows[id .. ".num"] = name, nil
	local shown = ns.ShotName(id)
	if taken[shown] then
		local n = 1
		while taken[shown .. " (" .. n .. ")"] do n = n + 1 end
		if name then rows[id .. ".name"] = name .. " (" .. n .. ")" else rows[id .. ".num"] = n end
	end
	rows.shots = (rows.shots and rows.shots ~= "" and rows.shots .. "," or "") .. id
	return id
end

-- The rows set to a shot: { id, ... } (a trigger's own rows and copies).
function ns.ShotUsers(id)
	local users, value = {}, "shot:" .. id
	for _, row in ipairs(ns.CameraRowOrder()) do
		if ns.CameraRowValue(row, "camera") == value then users[#users + 1] = row end
	end
	return users
end

-- Takes a shot off: rows set to it go to its camera.
function ns.RemoveShot(id)
	local rows = ns.GetDB().cameraRows
	local base = ns.ShotBaseOf(id)
	for _, row in ipairs(ns.ShotUsers(id)) do ns.SetCameraRowValue(row, "camera", base) end
	rows[id .. ".name"], rows[id .. ".base"], rows[id .. ".num"] = nil, nil, nil
	for _, setting in ipairs(ns.SHOT_SETTINGS) do rows[id .. "." .. setting.key] = nil end
	local list = {}
	for _, each in ipairs((ns.ShotList())) do
		if each ~= id then list[#list + 1] = each end
	end
	rows.shots = #list > 0 and table.concat(list, ",") or nil
	if ns.testShot == id then ns.testShot = nil end
	ns.CameraRowsChanged()
end

-- Clears a shot's own numbers: its camera's again.
function ns.ResetShot(id)
	local rows = ns.GetDB().cameraRows
	for _, setting in ipairs(ns.SHOT_SETTINGS) do rows[id .. "." .. setting.key] = nil end
end

-- My Shots' Test button: the shot's camera started as its key would, with
-- the shot's numbers. Again (or moving) stops it.
function ns.TestShot(id)
	local base = ns.ShotBaseOf(id)
	ns.testShot = id
	Cinematic_StartCam(base == "afk" and "idle" or base, false, "My Shots")
end

-- Share strings: a trigger (and the shot it plays, if it plays one) or a
-- shot, as "CINECAM1:", its table written out, ":" and a checksum. When it
-- starts comes along; where (its When ticks) doesn't: it lands with a new
-- trigger's (anywhere but battlegrounds and arenas, out of fights).
local SHARE_PREFIX, SHARE_FORMAT = "CINECAM", 1
local MAX_TEXT, MAX_DEPTH = 4000, 3

-- The table written out: {key=value;...}, strings s.., numbers n.., true and
-- false b1/b0, tables in braces; anything but letters, digits and . - _ as
-- %XX, so spaces and the like don't break it in chat or a paste.
local function Escape(text)
	return (tostring(text):gsub("[^%w%.%-_]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function Write(data, out, depth)
	out[#out + 1] = "{"
	for key, value in pairs(data) do
		local kind = type(value)
		if type(key) == "string" and (kind == "string" or kind == "number" or kind == "boolean"
			or (kind == "table" and depth < MAX_DEPTH)) then
			out[#out + 1] = Escape(key) .. "="
			if kind == "string" then
				out[#out + 1] = "s" .. Escape(value)
			elseif kind == "number" then
				out[#out + 1] = "n" .. Escape(value)
			elseif kind == "boolean" then
				out[#out + 1] = value and "b1" or "b0"
			else
				Write(value, out, depth + 1)
			end
			out[#out + 1] = ";"
		end
	end
	out[#out + 1] = "}"
end
local function Unescape(text)
	return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end
-- Reads Write's text from pos: the table and where it ended, or nil.
local function Read(text, pos, depth)
	if text:sub(pos, pos) ~= "{" or depth > MAX_DEPTH then return nil end
	local data = {}
	pos = pos + 1
	while text:sub(pos, pos) ~= "}" do
		local key, after = text:match("^([%w%.%-_%%]+)=()", pos)
		if not key then return nil end
		key, pos = Unescape(key), after
		local kind = text:sub(pos, pos)
		local value
		if kind == "{" then
			value, pos = Read(text, pos, depth + 1)
			if not value then return nil end
		else
			local raw, nextPos = text:match("^.([%w%.%-_%%]*)()", pos)
			if not raw then return nil end
			raw, pos = Unescape(raw), nextPos
			if kind == "s" then
				value = raw
			elseif kind == "n" then
				value = tonumber(raw)
			elseif kind == "b" then
				value = raw == "1"
			end
			if value == nil then return nil end
		end
		if text:sub(pos, pos) ~= ";" then return nil end
		data[key], pos = value, pos + 1
	end
	return data, pos + 1
end
-- (A simple sum, enough to tell a string cut short or mistyped.)
local function Checksum(text)
	local sum = 0
	for i = 1, #text do sum = (sum * 31 + text:byte(i)) % 16777216 end
	return ("%06X"):format(sum)
end
local function Pack(data)
	local out = {}
	Write(data, out, 1)
	local body = table.concat(out)
	return SHARE_PREFIX .. SHARE_FORMAT .. ":" .. body .. ":" .. Checksum(body)
end
-- The table in a pasted string, or nil and why ("empty", "newer", "other" or "broken").
local function Unpack(text)
	text = tostring(text or ""):gsub("%s", "")
	if text == "" then return nil, "empty" end
	if #text > MAX_TEXT then return nil, "broken" end
	local format = tonumber(text:match("^" .. SHARE_PREFIX .. "(%d+):"))
	if not format then return nil, "other" end
	if format > SHARE_FORMAT then return nil, "newer" end
	local body, sum = text:match("^" .. SHARE_PREFIX .. "%d+:(.*):(%x+)$")
	if not body then return nil, "broken" end
	if Checksum(body) ~= sum:upper() then return nil, "broken" end
	local data, after = Read(body, 1, 1)
	if not data or after ~= #body + 1 then return nil, "broken" end
	return data
end
ns.PackCameraShare, ns.UnpackCameraShare = Pack, Unpack -- (for the offline checks)
-- Text from a shared string: no colors or escapes, at most max bytes (cut at
-- a whole letter), nil if nothing's left.
local function Clean(text, max)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", ""):gsub("%c", " "):match("^%s*(.-)%s*$")
	if #text > max then text = text:sub(1, max):gsub("[\192-\255][\128-\191]*$", "") end
	return text ~= "" and text or nil
end
local MAX_NAME, MAX_SOURCE = 40, 120
local UNTIL_OK = { move = true, ends = true, key = true }
local AFTER_OK = { [""] = true, depart = true, logout = true, afk = true, byFire = true, emote = true,
	weapon = true, campfire = true, still = true }
local CAMERA_OK = { cozy = true, vista = true, fish = true, afk = true, none = true }

local function ShotData(id)
	local settings = {}
	local rows = Rows()
	for _, setting in ipairs(ns.SHOT_SETTINGS) do
		local own = rows[id .. "." .. setting.key]
		if type(own) == "number" then settings[setting.key] = own end
	end
	return { name = ns.ShotName(id), base = ns.ShotBaseOf(id), settings = settings }
end

function ns.ExportCameraTrigger(id)
	local rows = Rows()
	local camera = ns.CameraRowValue(id, "camera")
	local shot = ns.ShotOf(camera)
	return Pack({
		kind = "trigger", name = rows[id .. ".name"], source = rows[id .. ".source"], ["until"] = rows[id .. ".until"],
		after = rows[id .. ".after"], camera = shot and "shot" or camera,
		music = ns.CameraRowValue(id, "music") and true or nil, cine = ns.CameraRowValue(id, "cine") and true or nil,
		shot = shot and ShotData(shot) or nil,
	})
end
function ns.ExportShot(id)
	local data = ShotData(id)
	data.kind = "shot"
	return Pack(data)
end

-- A shared shot's parts, checked: { name, base, settings } or nil.
local function CleanShot(shot)
	if type(shot) ~= "table" or not PREFIX[shot.base] then return nil end
	local settings = {}
	for key, value in pairs(type(shot.settings) == "table" and shot.settings or {}) do
		local setting = SETTING[key]
		if setting and type(value) == "number" and value == value then
			settings[key] = math.max(setting.min, math.min(setting.max, value))
		end
	end
	return { name = Clean(shot.name, MAX_NAME), base = shot.base, settings = settings }
end

-- What a pasted string holds, checked: { kind = "trigger" | "shot", ... },
-- or nil and why ("empty", "newer", "other" or "broken").
function ns.ReadCameraShare(text)
	local data, why = Unpack(text)
	if not data then return nil, why end
	if data.kind == "shot" then
		local shot = CleanShot(data)
		if not shot then return nil, "broken" end
		shot.kind = "shot"
		return shot
	elseif data.kind == "trigger" then
		local source = Clean(data.source, MAX_SOURCE)
		if not source or not source:find("^%a+:.") then return nil, "broken" end
		local untilText = data["until"]
		if not (UNTIL_OK[untilText] or (type(untilText) == "string" and untilText:find("^time:%d+$"))) then
			untilText = nil
		end
		local shot = data.camera == "shot" and CleanShot(data.shot) or nil
		return {
			kind = "trigger", name = Clean(data.name, MAX_NAME), source = source, ["until"] = untilText,
			after = AFTER_OK[data.after] and data.after or nil,
			camera = shot and "shot" or (CAMERA_OK[data.camera] and data.camera or "cozy"),
			music = data.music == true, cine = data.cine == true, shot = shot,
		}
	end
	return nil, "other"
end

local function AddSharedShot(shot)
	local id = ns.AddShot(shot.base, shot.name)
	if not id then return nil end
	for key, value in pairs(shot.settings) do ns.SetShotValue(id, key, value) end
	return id
end

-- Adds what ReadCameraShare read: the new trigger's or shot's id, or nil
-- and why ("full").
function ns.AddCameraShare(info)
	if info.kind == "shot" then
		local id = AddSharedShot(info)
		return id, not id and "full" or nil
	end
	local camera = info.camera
	if info.shot then
		local shot = AddSharedShot(info.shot)
		camera = shot and ("shot:" .. shot) or info.shot.base
	end
	local id = ns.AddCustomTrigger(info.source, info["until"] or "move", camera, info.name)
	if not id then return nil, "full" end
	local rows = ns.GetDB().cameraRows
	rows[id .. ".after"] = info.after
	rows[id .. ".music"] = info.music or nil
	rows[id .. ".cine"] = info.cine or nil
	ns.CustomTriggersChanged()
	return id
end
