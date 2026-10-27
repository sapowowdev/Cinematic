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
-- client's options, and every module used by a built-in. Exits 1 on any
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
	local problems, _, absent, nowhere = ns.CheckModules(client, ns.ALL_BUILTIN_PROFILES)
	for _, line in ipairs(problems) do print("problem\t" .. line) end
	for key, entries in pairs(absent) do
		for _, entry in ipairs(entries) do print("absent\t" .. key .. "\t" .. entry) end
	end
	for key, settings in pairs(nowhere) do
		for _, setting in ipairs(settings) do print("nowhere\t" .. key .. "\t" .. setting) end
	end
	for _, module in ipairs(ns.PROFILE_MODULES) do
		if not module.client or module.client == client then print("module\t" .. module.key) end
	end
	for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
		if not profile.client or profile.client == client then
			for _, entry in ipairs(ns.ResolveModules(profile, client, ns.ALL_BUILTIN_BY_NAME)) do
				print("used\t" .. entry.key)
			end
		end
	end
	return
end

local problems, seen = {}, {}
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
	if not used[key] then Problem(("module %s: no built-in profile uses it"):format(key)) end
end

table.sort(problems)
for _, line in ipairs(problems) do print(line) end
print(("profile modules: %d problems"):format(#problems))
os.exit(#problems == 0 and 0 or 1)
