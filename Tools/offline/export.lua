-- The profile modules as JSON, for looking at them outside the game (the
-- mock-ups of the profile pages are made from it). From the repo root:
--
--   lua5.1 Tools/offline/export.lua > profiles.json
--
-- For each client (the dev build's files, so the hidden and dev-only
-- profiles are there too): its options pages and their sections (how many
-- settings each), the modules with what each writes and where, and the
-- built-in profiles with their modules (where each came from) and settings.

local function Json(value, indent)
	indent = indent or ""
	local kind = type(value)
	if kind == "nil" then return "null" end
	if kind == "boolean" or kind == "number" then return tostring(value) end
	if kind == "string" then
		return '"' .. value:gsub('[%c"\\]', function(c)
			local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
			return named[c] or ("\\u%04x"):format(c:byte())
		end) .. '"'
	end
	local inner = indent .. "  "
	if #value > 0 or next(value) == nil then
		local parts = {}
		for _, each in ipairs(value) do parts[#parts + 1] = inner .. Json(each, inner) end
		if #parts == 0 then return "[]" end
		return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
	end
	local keys = {}
	for k in pairs(value) do keys[#keys + 1] = tostring(k) end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local v = value[k]
		if v == nil then v = value[tonumber(k)] end
		parts[#parts + 1] = inner .. Json(k) .. ": " .. Json(v, inner)
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

-- One client (lua5.1 export.lua <client>): its part, as JSON.
local function Shown(value)
	if type(value) ~= "table" then return value end
	return "(" .. #value .. " groups)" -- (the mouseover groups)
end

local function Client(client)
	local ns = dofile("Tools/offline/load.lua")(client, "CinematicDev.toc")
	local out = { pages = {}, modules = {}, profiles = {} }
	-- Pages in the order the settings list them.
	local counts = {}
	local function Count(addresses)
		for _, address in ipairs(addresses or {}) do counts[address] = (counts[address] or 0) + 1 end
	end
	for _, settings in pairs(ns.PageSettings()) do
		for key in pairs(settings.keys) do
			if not settings.rows[key] then Count(ns.SettingAddresses(key)) end
		end
		for key, rows in pairs(settings.rows) do
			for row in pairs(rows) do Count(ns.SettingAddresses(key, row)) end
		end
	end
	local sections = ns.PageSections()
	local pageNames = {}
	for page in pairs(sections) do pageNames[#pageNames + 1] = page end
	table.sort(pageNames)
	for _, page in ipairs(pageNames) do
		local list = {}
		for _, address in ipairs(sections[page]) do
			list[#list + 1] = { address = address, name = address:match("/(.*)$"), settings = counts[address] or 0 }
		end
		out.pages[#out.pages + 1] = { name = page, sections = list }
	end
	for _, module in ipairs(ns.PROFILE_MODULES) do
		if not module.client or module.client == client then
			local writes = {}
			ns.ApplyModules({ { module = module } }, {}, client, function(key, row, value)
				writes[#writes + 1] = { setting = key, row = row ~= nil and tostring(row) or nil, value = Shown(value),
					address = ns.SettingAddress(key, row) }
			end)
			table.sort(writes, function(a, b)
				return (a.address or "") .. a.setting .. (a.row or "") < (b.address or "") .. b.setting .. (b.row or "")
			end)
			out.modules[#out.modules + 1] = { key = module.key, name = module.name, tip = module.tip,
				scope = module.scope, client = module.client, group = module.group, writes = writes }
		end
	end
	for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
		if not profile.client or profile.client == client then
			local resolved = ns.ResolveModules(profile, client, ns.ALL_BUILTIN_BY_NAME)
			local modules = {}
			for _, entry in ipairs(resolved) do modules[#modules + 1] = { key = entry.key, from = entry.from } end
			-- Who writes what (address -> module -> count).
			local by = {}
			ns.ApplyModules(resolved, {}, client, function(key, row, _, module)
				local address = ns.SettingAddress(key, row) or "?"
				by[address] = by[address] or {}
				by[address][module.key] = (by[address][module.key] or 0) + 1
			end)
			local picks, pickedBy = ns.ProfilePicks(profile, client, ns.ALL_BUILTIN_BY_NAME)
			local slots = {}
			for _, slot in ipairs(ns.PROFILE_SLOTS) do
				local info = ns.SLOT_CHOICES[slot.key]
				slots[slot.key] = { part = picks[slot.key] or info.default, by = pickedBy[slot.key] or "default" }
			end
			out.profiles[#out.profiles + 1] = { name = profile.name, label = profile.label or profile.name,
				tip = profile.tip, from = profile.from, hidden = profile.hidden, dev = profile.dev,
				listed = ns.IsBuiltinProfile(profile.name), icon = profile.icon, preview = profile.preview,
				modules = modules, writes = by, picks = slots }
		end
	end
	-- The slots and their choices, and the welcome window's levels.
	out.slots = {}
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		local info = ns.SLOT_CHOICES[slot.key]
		local choices = {}
		for _, choice in ipairs(info.choices) do
			if not choice.client or choice.client == client then
				local keys = {}
				for _, entry in ipairs(ns.ChoiceModules(slot.key, choice.part, client)) do keys[#keys + 1] = entry.key end
				choices[#choices + 1] = { part = choice.part, label = choice.label, line = choice.line,
					hidden = choice.hidden, modules = keys,
					changes = #ns.ModuleEffect(ns.ChoiceModules(slot.key, choice.part, client), client) }
			end
		end
		out.slots[#out.slots + 1] = { key = slot.key, label = info.label, question = info.question, page = info.page,
			default = info.default, choices = choices }
	end
	out.levels = {}
	for _, level in ipairs(ns.WELCOME_LEVELS) do
		out.levels[#out.levels + 1] = { label = level.label, line = level.line, tip = level.tip,
			profile = level.profile or ns.BUILTIN_PROFILES[1].name }
	end
	local _, _, _, _, notes = ns.CheckModules(client, ns.ALL_BUILTIN_PROFILES)
	out.notes = notes
	return out
end

if arg[1] then
	print(Json(Client(arg[1])))
	return
end
local parts = {}
for _, client in ipairs({ "forever", "retail" }) do
	local pipe = io.popen("lua5.1 Tools/offline/export.lua " .. client)
	parts[#parts + 1] = '  "' .. client .. '": ' .. pipe:read("*a"):gsub("%s+$", ""):gsub("\n", "\n  ")
	pipe:close()
end
print("{\n" .. table.concat(parts, ",\n") .. "\n}")
