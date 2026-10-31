-- The profile modules' checks (ProfileModules.lua) on both clients, outside
-- the game. From the repo root:
--
--   lua5.1 Tools/offline/check.lua
--
-- Loads the addon on each client and build (load.lua: each in a Lua of its
-- own, so one's settings don't carry into the next) and runs
-- ns.CheckModules: each module writing only inside its scope, no two of a
-- profile's modules setting the same thing, every built-in's modules there.
-- Also: the files loading without errors, every scope entry on at least one
-- client's options, and every module used by a built-in or a slot's choice.
-- Notes (two choices of a slot that come out the same) are listed but pass. Exits 1 on any
-- problem.

local RUNS = {
	{ "forever", "Cinematic.toc" }, { "retail", "Cinematic.toc" },
	{ "forever", "CinematicDev.toc" }, { "retail", "CinematicDev.toc" },
}

-- One run (lua5.1 check.lua <client> <toc>): its lines, tab-separated.
if arg[1] then
	local client, toc = arg[1], arg[2]
	local ns, wow = dofile("Tools/offline/load.lua")(client, toc)
	for _, warning in ipairs(wow.warnings) do
		-- (The minimap button compares the stand-in's numbers: not the addon's.)
		if not warning:find("^PLAYER_LOGIN: MinimapButton") then print("problem\t" .. warning) end
	end
	local problems, _, absent, nowhere, notes = ns.CheckModules(client, ns.ALL_BUILTIN_PROFILES)
	for _, line in ipairs(problems) do print("problem\t" .. line) end
	for _, line in ipairs(notes) do print("note\t" .. line) end
	for key, entries in pairs(absent) do
		for _, entry in ipairs(entries) do print("absent\t" .. key .. "\t" .. entry) end
	end
	for key, settings in pairs(nowhere) do
		for _, setting in ipairs(settings) do print("nowhere\t" .. key .. "\t" .. setting) end
	end
	for _, key in ipairs(ns.ModuleKeys()) do
		local module = ns.GetModule(key)
		if not module.client or module.client == client then print("module\t" .. key) end
	end
	for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
		if not profile.client or profile.client == client then
			for _, entry in ipairs(ns.ResolveModules(profile, client, ns.ALL_BUILTIN_BY_NAME)) do
				print("used\t" .. entry.key)
			end
		end
	end
	-- (Or by a slot's choice: the welcome window's Customize pages.)
	for slot, info in pairs(ns.SLOT_CHOICES) do
		for _, choice in ipairs(info.choices) do
			for _, entry in ipairs(ns.ChoiceModules(slot, choice.part, client) or {}) do
				print("used\t" .. entry.key)
			end
		end
	end
	-- The Cameras page's triggers, in the order they always had (a WoW Forever
	-- one left out on retail, the chat camera's only where it's loaded).
	local expected = { "Hearth", "Teleport", "Logout", "AFK", "Sit", "SitButton", "Sleep", "Dance", "Kneel", "Stare",
		"Chair", "Weapon", "Campfire", "Fishing", "Still", "Flight", "Quest", "QuestGossip", "Walk", "Run", "Death" }
	if client == "retail" then table.remove(expected, 6) end
	if ns.ChatCamCommand then
		expected[#expected + 1] = "Chat"
		expected[#expected + 1] = "ChatNearby"
	end
	local keys = {}
	for i, trigger in ipairs(ns.CAMERA_TRIGGERS) do
		keys[i] = trigger.key
		if ns.CAMERA_TRIGGER[trigger.key] ~= trigger then print("problem\tCamera trigger " .. trigger.key .. " not indexed") end
	end
	if table.concat(keys, ",") ~= table.concat(expected, ",") then
		print("problem\tCamera triggers are " .. table.concat(keys, ",") .. ", not " .. table.concat(expected, ","))
	end
	-- The trigger sources (Triggers.lua) pick as the fixed order before them
	-- did, for every mix of what's on and which triggers have a camera.
	local function OldPick(state, cameraOf)
		local order = { state.departing, state.logout and "Logout", state.afk and "AFK", state.byFire and "Campfire",
			state.emote, state.weapon and "Weapon", state.campfire and "Campfire", state.still and "Still" }
		for i = 1, 8 do
			local camera = order[i] and cameraOf(order[i])
			if camera then return order[i], camera end
		end
	end
	local EMOTES = { false, "Sit", "Fishing", "Hearth" }
	local CAMERA_SETS = {
		{ Hearth = "tele", Teleport = "tele", Logout = "cozy", AFK = "afk", Campfire = "cozy", Sit = "vista",
			Fishing = "fish", Weapon = "cozy", Still = "afk" },
		{ Logout = "cozy", Campfire = "cozy", Fishing = "fish", Still = "afk" },
		{ AFK = "afk", Sit = "vista", Weapon = "cozy" },
		{ Teleport = "tele", Campfire = "cozy" },
		{},
	}
	local mismatches = 0
	for _, cameras in ipairs(CAMERA_SETS) do
		local function CameraOf(key) return cameras[key] end
		for bits = 0, 63 do
			for _, departing in ipairs({ false, "Hearth", "Teleport" }) do
				for _, emote in ipairs(EMOTES) do
					local function Bit(n) return math.floor(bits / 2 ^ n) % 2 == 1 end
					local state = { departing = departing, logout = Bit(0), afk = Bit(1), byFire = Bit(2), emote = emote,
						weapon = Bit(3), campfire = Bit(4), still = Bit(5) }
					local newKey, newCamera = ns.PickTrigger(state, CameraOf)
					local oldKey, oldCamera = OldPick(state, CameraOf)
					if newKey ~= oldKey or newCamera ~= oldCamera then mismatches = mismatches + 1 end
				end
			end
		end
	end
	if mismatches > 0 then
		print(("problem\tTrigger sources pick differently from the old order in %d cases"):format(mismatches))
	end
	-- Triggers of your own (CustomTriggers.lua): one added is a row with its
	-- camera, sits after the emotes in the priority list (or first), starts
	-- from its key, and taken off leaves nothing behind.
	local function Problem(text) print("problem\tCustom triggers: " .. text) end
	local function SourceOf(id)
		for _, source in ipairs(ns.TRIGGER_SOURCES) do
			if source.custom == id then return source end
		end
	end
	local before = #ns.CAMERA_TRIGGERS
	local id = ns.AddCustomTrigger("key:1", "key", "vista", "Photo mode")
	local rows = ns.GetDB().cameraRows
	if id ~= "MineA" then Problem("the first one's id is " .. tostring(id)) end
	if id then
		if not ns.CAMERA_TRIGGER[id] or #ns.CAMERA_TRIGGERS ~= before + 1 then Problem("not on the Cameras page") end
		local listed = false
		for _, each in ipairs(ns.CameraRowOrder()) do listed = listed or each == id end
		if not listed then Problem("its row isn't in the row order") end
		if ns.CameraRowValue(id, "camera") ~= "vista" then Problem("its camera is " .. tostring(ns.CameraRowValue(id, "camera"))) end
		ns.SetCameraRowValue(id, "music", true)
		if rows[id .. ".music"] ~= true or ns.CameraRowValue(id, "music") ~= true then Problem("music not kept") end
		local source = SourceOf(id)
		if not source or not (source.order > 500 and source.order < 600) then
			Problem("not between the emotes and the weapon: " .. tostring(source and source.order))
		end
		if source and source.Key({}) ~= nil then Problem("on before its key") end
		Cinematic_CustomTrigger(1)
		if source and source.Key({}) ~= id then Problem("its key didn't start it") end
		Cinematic_CustomTrigger(1)
		if source and source.Key({}) ~= nil then Problem("its key didn't stop it") end
		rows[id .. ".after"] = ""
		ns.CustomTriggersChanged()
		source = SourceOf(id)
		if not source or source.order >= 100 then Problem("after \"\" isn't first: " .. tostring(source and source.order)) end
		local copy = ns.CopyCameraRow(id)
		if copy ~= id .. "2" then Problem("its copy is " .. tostring(copy)) end
		ns.RemoveCustomTrigger(id)
		ns.SyncCustomTriggers()
		if ns.CAMERA_TRIGGER[id] or #ns.CAMERA_TRIGGERS ~= before or SourceOf(id) then Problem("still there taken off") end
		for key in pairs(rows) do
			if tostring(key):find("^" .. id) then Problem("left behind: " .. key) end
		end
		if rows.custom ~= nil then Problem("its list is " .. tostring(rows.custom)) end
		for _, each in ipairs(ns.CameraRowOrder()) do
			if each:find("^" .. id) then Problem("its row's still in the order: " .. each) end
		end
	end
	-- A built-in trigger deleted (CameraRows' deleted list): its rows go, it
	-- starts no camera, and Add back brings it back as it was.
	local afkCamera = ns.CameraRowValue("AFK", "camera")
	ns.SetTriggerDeleted("AFK", true)
	for _, each in ipairs(ns.CameraRowOrder()) do
		if each:find("^AFK%d?$") then Problem("a deleted trigger's row is still listed: " .. each) end
	end
	if ns.TriggerRowNow("AFK") ~= nil or ns.TriggerSetting("AFK", "camera") ~= "none" then
		Problem("a deleted trigger still picks a camera")
	end
	if ns.DeletedTriggers()[1] ~= "AFK" then Problem("Add back doesn't list it") end
	ns.SetTriggerDeleted("AFK", false)
	local back = false
	for _, each in ipairs(ns.CameraRowOrder()) do back = back or each == "AFK" end
	if not back or ns.CameraRowValue("AFK", "camera") ~= afkCamera or ns.GetDB().cameraRows.deleted ~= nil then
		Problem("Add back didn't bring it back as it was")
	end
	-- My Shots (Shots.lua): a shot follows its camera's numbers until given its
	-- own, a row set to one goes by its camera's mode, a trigger shared with
	-- its shot comes back whole, a tampered string is clamped or refused, and
	-- deleting a shot sends its rows back to its camera.
	local function ShotProblem(text) print("problem\tMy Shots: " .. text) end
	local shot = ns.AddShot("vista", "Wide")
	local trigger = shot and ns.AddCustomTrigger("emote:wave", "move", "shot:" .. shot, "Wave")
	if not (shot and trigger) then
		ShotProblem("couldn't make a shot and a trigger for it")
	else
		if ns.ShotValue(shot, "OrbitBackArc") ~= ns.GetDB().vistaOrbitBackArc then ShotProblem("doesn't follow its camera") end
		ns.SetShotValue(shot, "OrbitBackArc", 70)
		if ns.ShotValue(shot, "OrbitBackArc") ~= 70 then ShotProblem("its own number isn't kept") end
		if ns.CameraValueMode("shot:" .. shot) ~= "vista" then ShotProblem("its row doesn't go by the vista camera") end
		if ns.ShotSetting("vistaOrbitBackArc") ~= ns.GetDB().vistaOrbitBackArc then
			ShotProblem("its number applies while it isn't running")
		end
		local info = ns.ReadCameraShare(ns.ExportCameraTrigger(trigger))
		if not (info and info.source == "emote:wave" and info.shot and info.shot.settings.OrbitBackArc == 70) then
			ShotProblem("a shared trigger doesn't come back whole")
		end
		local tampered = ns.ReadCameraShare(ns.PackCameraShare({ kind = "shot", base = "afk", name = "x|cffff0000",
			settings = { OrbitStep = 9999, Bogus = 1 } }))
		if not (tampered and tampered.settings.OrbitStep == 180 and tampered.settings.Bogus == nil
			and not tampered.name:find("|")) then
			ShotProblem("a tampered shot isn't clamped and cleaned")
		end
		local _, why = ns.ReadCameraShare("CINECAM9:abc")
		if why ~= "newer" then ShotProblem("a newer string reads as " .. tostring(why)) end
		_, why = ns.ReadCameraShare("CINECAM1:{x=s1;}:000000")
		if why ~= "broken" then ShotProblem("a wrong checksum reads as " .. tostring(why)) end
		ns.RemoveShot(shot)
		if ns.CameraRowValue(trigger, "camera") ~= "vista" then ShotProblem("a deleted shot's row isn't back on its camera") end
		ns.RemoveCustomTrigger(trigger)
		local leftover = {}
		for key in pairs(ns.GetDB().cameraRows) do
			if key ~= "order" then leftover[#leftover + 1] = tostring(key) end -- (the earlier copy's row order)
		end
		if #leftover > 0 then ShotProblem("left behind: " .. table.concat(leftover, ", ")) end
	end
	-- Vitals Vision: a page's Reset (its settings back to the profile's) leaves
	-- each theme's own look on them, not the plain defaults.
	local db, base = ns.GetDB(), ns.ProfileBase()
	for _, theme in ipairs(ns.LOW_HEALTH_THEMES) do
		db.lowHealthTheme = theme.key
		ns.ResyncVitalsLook()
		for key in pairs(theme.look or {}) do db[key] = base[key] end
		ns.ResyncVitalsLook()
		for key, value in pairs(theme.look or {}) do
			if db[key] ~= value then
				print(("problem\tVitals theme %s: %s after a Reset is %s, not its %s"):format(theme.key, key,
					tostring(db[key]), tostring(value)))
			end
		end
	end
	return
end

local problems, seen, notes = {}, {}, {}
local function Problem(text)
	if not seen[text] then
		seen[text] = true
		problems[#problems + 1] = text
	end
end
local looked, absent, nowhere, used = {}, {}, {}, {}
for _, run in ipairs(RUNS) do
	local where = run[1] .. " (" .. run[2] .. ")"
	local pipe = io.popen(("lua5.1 Tools/offline/check.lua %s %s 2>&1"):format(run[1], run[2]))
	for line in pipe:lines() do
		local kind, a, b = line:match("^(%a+)\t([^\t]*)\t?(.*)$")
		if kind == "problem" then
			Problem(where .. ": " .. a)
		elseif kind == "note" then
			if not seen["note " .. a] then
				seen["note " .. a] = true
				notes[#notes + 1] = a
			end
		elseif kind == "absent" then
			absent[a .. "\t" .. b] = (absent[a .. "\t" .. b] or 0) + 1
		elseif kind == "nowhere" then
			nowhere[a .. "\t" .. b] = (nowhere[a .. "\t" .. b] or 0) + 1
		elseif kind == "module" then
			looked[a] = (looked[a] or 0) + 1
		elseif kind == "used" then
			used[a] = true
		else
			Problem(where .. ": " .. line)
		end
	end
	pipe:close()
end
-- (A scope entry missing on every run its module was on: on neither client.)
for pair, count in pairs(absent) do
	local key, entry = pair:match("^(.-)\t(.*)$")
	if count >= looked[key] then
		Problem(("module %s: its scope's %s isn't on either client's options"):format(key, entry))
	end
end
-- (A setting a module writes on no page on every run: on neither client.)
for pair, count in pairs(nowhere) do
	local key, setting = pair:match("^(.-)\t(.*)$")
	if count >= looked[key] then
		Problem(("module %s: %s isn't on either client's options"):format(key, setting))
	end
end
for key in pairs(looked) do
	if not used[key] then Problem(("module %s: no built-in profile or part uses it"):format(key)) end
end

table.sort(problems)
table.sort(notes)
for _, line in ipairs(problems) do print(line) end
for _, line in ipairs(notes) do print("note: " .. line) end
print(("profile modules: %d problems, %d notes"):format(#problems, #notes))
os.exit(#problems == 0 and 0 or 1)
