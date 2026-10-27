-- The dev build's Module Editor page: the built-in profiles, the slots'
-- choices and the modules (ProfileChoices.lua, ProfileModules.lua), changed
-- in the game. Changes are kept in db.devEdits (ns.DevEdits) until cleared,
-- and a profile takes them when it's picked or reset; Export gives the Lua
-- to paste back into those two files. Three parts:
--   Profiles: each built-in's choice per slot (click one for another) and
--     modules of its own.
--   Choices: each slot's choices and their modules (Modules... ticks one in
--     or out), and Try to put one on your live settings.
--   Modules: one at a time: what it changes and where, its name and scope;
--     Try it on, take your live settings into it, or make a new one from a
--     page or a section of one.
-- Options.lua calls ns.CreateModuleEditor with the page helpers it shares
-- (dev build only).

local _, ns = ...

local NAME_W, SLOT_W, ROW_H, WIDTH = 120, 84, 22, 700
local OWN_PROFILE = "My setup" -- (Try on a built-in: a profile of your own first)

-- A value as Lua source (keys sorted, so the same settings give the same text).
local function Lua(value)
	if type(value) == "string" then return ("%q"):format(value) end
	if type(value) ~= "table" then return tostring(value) end
	local keys = {}
	for k in pairs(value) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) == "number" end
		return a < b
	end)
	local parts, n = {}, 0
	for _, k in ipairs(keys) do
		local key
		n = n + 1
		if type(k) == "number" and k == n then
			key = nil -- (a list: in order, no keys)
		elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
			key = k
		elseif type(k) == "string" then
			key = ("[%q]"):format(k)
		else
			key = "[" .. tostring(k) .. "]"
		end
		parts[#parts + 1] = (key and key .. " = " or "") .. Lua(value[k])
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = Copy(v) end
	return copy
end

-- A menu of { text, fn } (or { text, entries } for a submenu) under a
-- button. No menus on this client: each click takes the next one (a
-- submenu's entries in turn).
local function Menu(owner, entries)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			local function Add(parent, list)
				for _, entry in ipairs(list) do
					if type(entry[2]) == "table" then
						Add(parent:CreateButton(entry[1]), entry[2])
					else
						parent:CreateButton(entry[1], entry[2])
					end
				end
			end
			Add(root, entries)
		end)
		return
	end
	local flat = {}
	local function Flatten(list)
		for _, entry in ipairs(list) do
			if type(entry[2]) == "table" then Flatten(entry[2]) else flat[#flat + 1] = entry end
		end
	end
	Flatten(entries)
	if #flat > 0 then
		owner.menuIndex = (owner.menuIndex or 0) % #flat + 1
		flat[owner.menuIndex][2]()
	end
end

-- The changes (made when first wanted), and after one: profiles and slots
-- worked out again, and none kept when there are none.
local function Edits()
	local edits = ns.db.devEdits or {}
	ns.db.devEdits = edits
	edits.modules, edits.choices, edits.profiles = edits.modules or {}, edits.choices or {}, edits.profiles or {}
	return edits
end
local function Changed()
	local edits = ns.db.devEdits
	if edits then
		for slot, list in pairs(edits.choices or {}) do
			if not next(list) then edits.choices[slot] = nil end
		end
		if not (next(edits.modules or {}) or next(edits.choices or {}) or next(edits.profiles or {})) then
			ns.db.devEdits = nil
		end
	end
	ns.ForgetProfileBases()
	ns.ForgetSlotSettings()
end

local function ModuleName(key)
	local module = ns.GetModule(key)
	return module and module.name or key
end

local function ClientOf(profile) return profile.client or ns.CLIENT end

local function EditOf(name)
	local edits = ns.DevEdits()
	return edits and edits.profiles and edits.profiles[name]
end

-- A profile's own picks and modules as the Editor has them (a copy to change).
local function OwnCopy(profile)
	local own = EditOf(profile.name) or profile
	return { picks = Copy(own.picks or {}), modules = Copy(own.modules or {}) }
end

-- A module's changes as data settings (what a data module holds): its lists by row.
local function AsSettings(module)
	local settings = {}
	for _, change in ipairs(ns.ModuleEffect({ { module = module } }, ns.CLIENT)) do
		local key, row, value = change[1], change[2], change[3]
		if row == nil then
			settings[key] = Copy(value)
		else
			settings[key] = settings[key] or {}
			settings[key][row] = Copy(value)
		end
	end
	return settings
end

-- The Editor's copy of a module to change (a new data module from the
-- code's the first time).
local function EditModule(key)
	local edits = Edits()
	if not edits.modules[key] then
		local module = ns.GetModule(key)
		edits.modules[key] = { name = module.name, tip = module.tip, scope = Copy(module.scope),
			client = module.client, group = module.group, settings = AsSettings(module) }
	end
	return edits.modules[key]
end

-- The settings with nothing on them: the defaults, the old grids' gone over.
local function Baseline()
	local values = {}
	for k, v in pairs(ns.DEFAULTS) do values[k] = v end
	return ns.ApplyModules({}, values, ns.CLIENT)
end

-- The live settings in a scope that differ from the defaults, as data settings.
local function Capture(scope)
	local base, db, settings = Baseline(), ns.db, {}
	local function Here(key, row)
		for _, address in ipairs(ns.SettingAddresses(key, row) or {}) do
			if ns.InScope(scope, address) then return true end
		end
		return false
	end
	local S = ns.SerialValue
	for key in pairs(ns.DEFAULTS) do
		if ns.IsProfileKey(key) and not ns.IS_PROFILE_TABLE[key] and Here(key) and S(db[key]) ~= S(base[key]) then
			settings[key] = Copy(db[key])
		end
	end
	for _, key in ipairs(ns.PROFILE_TABLES) do
		local live, from = db[key], base[key]
		if key == "hoverGroups" then
			if Here(key) and live ~= nil and S(live) ~= S(from) then settings[key] = Copy(live) end
		elseif type(live) == "table" then
			for row, value in pairs(live) do
				if Here(key, row) and S(value) ~= S(type(from) == "table" and from[row] or nil) then
					settings[key] = settings[key] or {}
					settings[key][row] = Copy(value)
				end
			end
		end
	end
	return settings
end

-- How many settings (lists' rows each) data settings hold.
local function Count(settings)
	local n = 0
	for key, value in pairs(settings) do
		if type(value) == "table" and key ~= "hoverGroups" then
			for _ in pairs(value) do n = n + 1 end
		else
			n = n + 1
		end
	end
	return n
end

-- A data module as Lua, for ProfileModules.lua's list.
local function ModuleLua(key, module)
	local lines = { ("\t{ key = %q, name = %q,"):format(key, module.name or key) }
	if module.client then lines[#lines + 1] = ("\t\tclient = %q,"):format(module.client) end
	if module.group then lines[#lines + 1] = ("\t\tgroup = %q,"):format(module.group) end
	lines[#lines + 1] = "\t\tscope = " .. Lua(module.scope or {}) .. ","
	lines[#lines + 1] = ("\t\ttip = %q,"):format(module.tip or "")
	lines[#lines + 1] = "\t\tsettings = {"
	local keys = {}
	for k in pairs(module.settings or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		lines[#lines + 1] = ("\t\t\t%s = %s,"):format(k:match("^[%a_][%w_]*$") and k or ("[%q]"):format(k),
			Lua(module.settings[k]))
	end
	lines[#lines + 1] = "\t\t} },"
	return table.concat(lines, "\n")
end

-- A profile's picks and modules lines, for ProfileChoices.lua.
local function ProfileLua(profile)
	local own = EditOf(profile.name) or profile
	local lines = { "-- " .. profile.name }
	if profile.from then lines[#lines + 1] = ("\t\tfrom = %q,"):format(profile.from) end
	lines[#lines + 1] = "\t\tpicks = " .. Lua(own.picks or {}) .. ","
	if own.modules and #own.modules > 0 then lines[#lines + 1] = "\t\tmodules = " .. Lua(own.modules) .. "," end
	return table.concat(lines, "\n")
end

-- Every change as Lua, by the file it goes in.
local function ExportLua()
	local edits = ns.DevEdits()
	if not edits then return "No changes: everything is as the code has it." end
	local out = {}
	local keys = {}
	for key in pairs(edits.modules or {}) do keys[#keys + 1] = key end
	table.sort(keys)
	if #keys > 0 then
		out[#out + 1] = "-- ProfileModules.lua, ns.PROFILE_MODULES: these modules, in place of the ones with the same key (or new):"
		for _, key in ipairs(keys) do out[#out + 1] = ModuleLua(key, edits.modules[key]) end
	end
	local slots = {}
	for slot in pairs(edits.choices or {}) do slots[#slots + 1] = slot end
	table.sort(slots)
	if #slots > 0 then
		out[#out + 1] = "\n-- ProfileChoices.lua, ns.SLOT_CHOICES: these choices' modules:"
		for _, slot in ipairs(slots) do
			for part, choice in pairs(edits.choices[slot]) do
				out[#out + 1] = ("-- %s.%s\n\t\t\tmodules = %s },"):format(slot, part, Lua(choice.modules or {}))
			end
		end
	end
	local names = {}
	for name in pairs(edits.profiles or {}) do names[#names + 1] = name end
	table.sort(names)
	if #names > 0 then
		out[#out + 1] = "\n-- ProfileChoices.lua, ns.BUILTIN_PROFILES: these profiles' picks and modules:"
		for _, name in ipairs(names) do
			local profile = ns.ALL_BUILTIN_BY_NAME[name]
			if profile then out[#out + 1] = ProfileLua(profile) end
		end
	end
	return table.concat(out, "\n")
end

function ns.CreateModuleEditor(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "|cffff4040DEV ONLY|r Module Editor")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.Label(content, "GameFontHighlight", "The built-in profiles, the choices each slot offers " ..
		"and the modules they're made of (ProfileChoices.lua, ProfileModules.lua). Changes here are kept " ..
		"(green) until you clear them, and a profile takes them when you pick or reset it. Export gives the " ..
		"Lua to paste back into the files.")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	intro:SetWidth(WIDTH)
	intro:SetJustifyH("LEFT")

	local output, status, Refresh
	local function Button(parent, text, width, tip, onClick)
		local button = ns.PanelButton and ns.PanelButton(parent) or CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		button:SetSize(width, ROW_H)
		button:SetText(text)
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", onClick)
		return button
	end
	local function Show(text)
		output:SetText(text)
		output:HighlightText()
		output:SetFocus()
	end
	local function Header(text, anchor, y)
		local label = kit.Label(content, "GameFontNormalLarge", text)
		label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -18)
		return label
	end

	-- Top: the changes kept, and what to do with them.
	local export = Button(content, "Export changes", 130, "Every change as Lua, by the file it goes in, in the " ..
		"box at the bottom.", function() Show(ExportLua()) end)
	export:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
	local clear = Button(content, "Clear changes", 120, "Everything back to the code's (profiles you're on " ..
		"take it when picked or reset).", function()
		ns.db.devEdits = nil
		Changed()
		Refresh()
	end)
	clear:SetPoint("LEFT", export, "RIGHT", 8, 0)
	local check = Button(content, "Run checks", 110, "/cine debug modules: modules writing outside their " ..
		"scope, two of a profile's setting the same thing, choices that come out the same...", function()
		local problems, _, _, _, notes = ns.CheckModules(ns.CLIENT, ns.ALL_BUILTIN_PROFILES)
		local lines = { ("%d problems, %d notes"):format(#problems, #notes) }
		for _, line in ipairs(problems) do lines[#lines + 1] = line end
		for _, line in ipairs(notes) do lines[#lines + 1] = "note: " .. line end
		output:SetText(table.concat(lines, "\n"))
	end)
	check:SetPoint("LEFT", clear, "RIGHT", 8, 0)
	status = kit.Label(content, "GameFontHighlightSmall", "")
	status:SetPoint("LEFT", check, "RIGHT", 12, 0)

	-- 1. Profiles: a row each, a cell per slot.
	local profilesHead = Header("Profiles", export, -20)
	local profilesNote = kit.Label(content, "GameFontHighlightSmall", "Each built-in's choice per slot: white its " ..
		"own, grey the one it's from (or the slot's default), green changed here. Click one for another.")
	profilesNote:SetPoint("TOPLEFT", profilesHead, "BOTTOMLEFT", 0, -6)
	local slotHeads = CreateFrame("Frame", nil, content)
	slotHeads:SetSize(WIDTH, 16)
	slotHeads:SetPoint("TOPLEFT", profilesNote, "BOTTOMLEFT", 0, -10)
	for i, slot in ipairs(ns.PROFILE_SLOTS) do
		local label = kit.Label(slotHeads, "GameFontNormalSmall", ns.SLOT_CHOICES[slot.key] and
			ns.SLOT_CHOICES[slot.key].label or slot.name)
		label:SetPoint("LEFT", slotHeads, "LEFT", NAME_W + (i - 1) * SLOT_W + 3, 0)
		label:SetWidth(SLOT_W - 4)
		label:SetWordWrap(false)
	end
	local profileRows, anchor = {}, slotHeads
	for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(WIDTH, ROW_H)
		row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
		anchor = row
		row.profile = profile
		local tags = {}
		if profile.client then tags[#tags + 1] = profile.client == "forever" and "F" or "R" end
		if profile.hidden then tags[#tags + 1] = "hidden" end
		local name = kit.Label(row, "GameFontHighlightSmall", (profile.label or profile.name)
			.. (#tags > 0 and " |cff808080(" .. table.concat(tags, ",") .. ")|r" or ""))
		name:SetPoint("LEFT")
		name:SetWidth(NAME_W - 4)
		name:SetWordWrap(false)
		row.cells = {}
		for i, slot in ipairs(ns.PROFILE_SLOTS) do
			local cell = CreateFrame("Button", nil, row)
			cell:SetSize(SLOT_W - 4, ROW_H - 2)
			cell:SetPoint("LEFT", row, "LEFT", NAME_W + (i - 1) * SLOT_W, 0)
			local back = cell:CreateTexture(nil, "BACKGROUND")
			back:SetAllPoints()
			back:SetColorTexture(1, 1, 1, 0.06)
			cell:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			cell.text = kit.Label(cell, "GameFontHighlightSmall")
			cell.text:SetPoint("LEFT", 3, 0)
			cell.text:SetPoint("RIGHT", -3, 0)
			cell.text:SetWordWrap(false)
			cell:SetScript("OnClick", function(self)
				local client = ClientOf(profile)
				local entries = {}
				local function Pick(part)
					local own = OwnCopy(profile)
					local pick = own.picks[slot.key]
					if type(pick) == "table" then
						pick = Copy(pick)
						pick[client] = part
						if not next(pick) then pick = nil end
					else
						pick = part
					end
					own.picks[slot.key] = pick
					Edits().profiles[profile.name] = own
					Changed()
					ns.Print(("Module Editor: %s %s: %s (when you pick or reset it)"):format(profile.name, slot.key,
						part or "not its own"))
					Refresh()
				end
				local info = ns.SLOT_CHOICES[slot.key]
				for _, choice in ipairs(info and info.choices or {}) do
					if not choice.client or choice.client == client then
						entries[#entries + 1] = { choice.label .. " |cff808080(" .. choice.part
							.. (choice.hidden and ", hidden" or "") .. ")|r", function() Pick(choice.part) end }
					end
				end
				entries[#entries + 1] = { profile.from and ("As " .. ns.ProfileLabel(profile.from) .. " has it")
					or ("The default (" .. tostring(info and info.default) .. ")"), function() Pick(nil) end }
				Menu(self, entries)
			end)
			row.cells[i] = cell
		end
		local extra = Button(row, "+", 24, "Modules of its own on top of its choices (or one of the " ..
			"choices' taken out).", function(self)
			local own, client = OwnCopy(profile), ClientOf(profile)
			local resolved = ns.ResolveModules(profile, client, ns.ALL_BUILTIN_BY_NAME, EditOf)
			local inIt, entries = {}, {}
			for _, entry in ipairs(resolved) do inIt[entry.key] = entry end
			for _, key in ipairs(ns.ModuleKeys()) do
				local module = ns.GetModule(key)
				if not module.client or module.client == client then
					local entry = inIt[key]
					local note = entry and entry.slot and " |cff808080(" .. entry.slot .. ")|r" or ""
					entries[#entries + 1] = { (entry and "|cff40ff40[x]|r " or "[  ] ") .. module.name .. note, function()
						local list, found = own.modules, false
						for i = #list, 1, -1 do
							if list[i] == key or list[i] == "-" .. key then
								table.remove(list, i)
								found = true
							end
						end
						if not found then list[#list + 1] = entry and "-" .. key or key end
						Edits().profiles[profile.name] = own
						Changed()
						Refresh()
					end }
				end
			end
			Menu(self, entries)
		end)
		extra:SetPoint("LEFT", row, "LEFT", NAME_W + #ns.PROFILE_SLOTS * SLOT_W, 0)
		local lua = Button(row, "Lua", 40, "Its picks and modules lines, with your changes, in the box below.",
			function() Show(ProfileLua(profile)) end)
		lua:SetPoint("LEFT", extra, "RIGHT", 2, 0)
		local undo = Button(row, "Undo", 46, "Its picks and modules back to the code's.", function()
			Edits().profiles[profile.name] = nil
			Changed()
			Refresh()
		end)
		undo:SetPoint("LEFT", lua, "RIGHT", 2, 0)
		row.undo = undo
		profileRows[#profileRows + 1] = row
	end

	-- 2. Choices: each slot's, a row each.
	local choicesHead = Header("Choices", anchor, -22)
	local choicesNote = kit.Label(content, "GameFontHighlightSmall", "Each slot's choices and their modules. " ..
		"Modules... ticks one in or out; Try puts the choice on your live settings (on a built-in, in a " ..
		"profile of your own, " .. OWN_PROFILE .. ").")
	choicesNote:SetPoint("TOPLEFT", choicesHead, "BOTTOMLEFT", 0, -6)
	choicesNote:SetWidth(WIDTH)
	choicesNote:SetJustifyH("LEFT")
	local choiceRows = {}
	anchor = choicesNote
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		local info = ns.SLOT_CHOICES[slot.key]
		if info then
			local slotLabel = kit.Label(content, "GameFontNormal", info.label .. " |cff808080(" .. slot.key .. ": "
				.. (info.question or "") .. ")|r")
			slotLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
			anchor = slotLabel
			for _, choice in ipairs(info.choices) do
				local row = CreateFrame("Frame", nil, content)
				row:SetSize(WIDTH, ROW_H)
				row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
				anchor = row
				row.slot, row.part = slot.key, choice.part
				local tags = { choice.part }
				if choice.hidden then tags[#tags + 1] = "hidden" end
				if choice.client then tags[#tags + 1] = choice.client .. " only" end
				local name = kit.Label(row, "GameFontHighlightSmall", choice.label .. " |cff808080("
					.. table.concat(tags, ", ") .. ")|r")
				name:SetPoint("TOPLEFT", 12, -4)
				name:SetWidth(200)
				name:SetWordWrap(false)
				row.modules = kit.Label(row, "GameFontHighlightSmall")
				row.modules:SetPoint("TOPLEFT", 216, -4)
				row.modules:SetWidth(WIDTH - 216 - 150)
				row.modules:SetJustifyH("LEFT")
				local edit = Button(row, "Modules...", 76, "Tick a module in or out of this choice.", function(self)
					local entries = {}
					local current = ns.GetChoice(slot.key, choice.part).modules or {}
					for _, key in ipairs(ns.ModuleKeys()) do
						local on = false
						for _, entry in ipairs(current) do
							if entry == key or (type(entry) == "table" and (entry.forever == key or entry.retail == key)) then
								on = true
							end
						end
						entries[#entries + 1] = { (on and "|cff40ff40[x]|r " or "[  ] ") .. ModuleName(key), function()
							local list = Copy(current)
							local removed = false
							for i = #list, 1, -1 do
								local entry = list[i]
								if entry == key or (type(entry) == "table" and (entry.forever == key or entry.retail == key)) then
									table.remove(list, i)
									removed = true
								end
							end
							if not removed then list[#list + 1] = key end
							local edits = Edits()
							edits.choices[slot.key] = edits.choices[slot.key] or {}
							edits.choices[slot.key][choice.part] = { modules = list }
							Changed()
							Refresh()
						end }
					end
					if ns.DevEdits() and ns.DevEdits().choices and ns.DevEdits().choices[slot.key]
						and ns.DevEdits().choices[slot.key][choice.part] then
						table.insert(entries, 1, { "Undo (as in the code)", function()
							Edits().choices[slot.key][choice.part] = nil
							Changed()
							Refresh()
						end })
					end
					Menu(self, entries)
				end)
				edit:SetPoint("TOPRIGHT", row, "TOPRIGHT", -46, 0)
				local try = Button(row, "Try", 42, "This choice on your live settings, just its slot's settings.",
					function()
						if not ns.db.enabled then ns.SetEnabled(true) end
						ns.ApplyChoice(slot.key, choice.part, OWN_PROFILE)
						Refresh()
					end)
				try:SetPoint("LEFT", edit, "RIGHT", 2, 0)
				choiceRows[#choiceRows + 1] = row
			end
		end
	end

	-- 3. Modules: one at a time.
	local modulesHead = Header("Modules", anchor, -22)
	local picked
	local pick = Button(content, "", 260, "Pick a module to look at or change.", function(self)
		local entries = {}
		for _, key in ipairs(ns.ModuleKeys()) do
			local module = ns.GetModule(key)
			entries[#entries + 1] = { (module.edited and "|cff40ff40" or "") .. module.name .. " |cff808080(" .. key
				.. ")|r", function()
				picked = key
				Refresh()
			end }
		end
		Menu(self, entries)
	end)
	pick:SetPoint("TOPLEFT", modulesHead, "BOTTOMLEFT", 0, -8)
	-- New from a page or section: the live settings there, as a new module.
	local function PageMenu(onPick)
		local entries, sections, pages = {}, ns.PageSections(), {}
		for page in pairs(sections) do pages[#pages + 1] = page end
		table.sort(pages)
		for _, page in ipairs(pages) do
			local sub = { { "The whole page", function() onPick(page) end } }
			for _, address in ipairs(sections[page]) do
				local section = address:match("/(.*)$")
				sub[#sub + 1] = { section == "top" and "Top of the page" or section, function() onPick(address) end }
			end
			entries[#entries + 1] = { page, sub }
		end
		return entries
	end
	local new = Button(content, "New from...", 110, "A new module from your live settings on a page, or a " ..
		"section of one (the ones that differ from the defaults).", function(self)
		Menu(self, PageMenu(function(where)
			local base = where:gsub("/top$", ""):gsub("[^%w]+", "-"):lower():gsub("^%-+", ""):gsub("%-+$", "")
			local key, n = base, 1
			while ns.GetModule(key) do
				n = n + 1
				key = base .. "-" .. n
			end
			Edits().modules[key] = { name = where:gsub("/top$", ""):gsub("/", ": "), scope = { where },
				tip = "", settings = Capture({ where }) }
			Changed()
			picked = key
			ns.Print(("Module Editor: new module %s from %s (%d settings)"):format(key, where,
				Count(Edits().modules[key].settings)))
			Refresh()
		end))
	end)
	new:SetPoint("LEFT", pick, "RIGHT", 8, 0)

	-- Its name and description: typed in, kept on Enter or leaving the box.
	local function Field(label, width, anchorTo, onSave)
		local text = kit.Label(content, "GameFontHighlightSmall", label)
		text:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -10)
		local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
		if ns.SkinEditBox then ns.SkinEditBox(box) end
		box:SetSize(width, 20)
		box:SetAutoFocus(false)
		box:SetPoint("LEFT", text, "LEFT", 70, 0)
		local function Save(self)
			if picked and self:GetText() ~= (self.shown or "") then
				onSave(self:GetText())
				Changed()
				Refresh()
			end
		end
		box:SetScript("OnEnterPressed", function(self)
			Save(self)
			self:ClearFocus()
		end)
		box:SetScript("OnEditFocusLost", Save)
		box:SetScript("OnEscapePressed", function(self)
			self:SetText(self.shown or "")
			self:ClearFocus()
		end)
		return text, box
	end
	local nameLabel, nameBox = Field("Name", 260, pick, function(text) EditModule(picked).name = text end)
	local tipLabel, tipBox = Field("What it does", WIDTH - 80, nameLabel, function(text) EditModule(picked).tip = text end)
	local scopeText = kit.Label(content, "GameFontHighlightSmall", "")
	scopeText:SetPoint("TOPLEFT", tipLabel, "BOTTOMLEFT", 0, -12)
	scopeText:SetWidth(WIDTH - 90)
	scopeText:SetJustifyH("LEFT")
	local scopeButton = Button(content, "Scope...", 80, "Tick a page or section in or out of where this module " ..
		"may change settings (Take live settings takes the ones there).", function(self)
		Menu(self, PageMenu(function(where)
			local module = EditModule(picked)
			local scope, found = module.scope, false
			for i = #scope, 1, -1 do
				if scope[i] == where then
					table.remove(scope, i)
					found = true
				end
			end
			if not found then scope[#scope + 1] = where end
			Changed()
			Refresh()
		end))
	end)
	scopeButton:SetPoint("TOPLEFT", scopeText, "TOPRIGHT", 6, 4)
	local actions = CreateFrame("Frame", nil, content)
	actions:SetSize(WIDTH, ROW_H)
	actions:SetPoint("TOPLEFT", scopeText, "BOTTOMLEFT", 0, -12)
	local tryOn = Button(actions, "Try it on", 90, "What this module changes, on your live settings (on a " ..
		"built-in, in a profile of your own, " .. OWN_PROFILE .. ").", function()
		if not ns.db.enabled then ns.SetEnabled(true) end
		ns.ApplyModulesLive({ picked }, OWN_PROFILE)
		Refresh()
	end)
	tryOn:SetPoint("LEFT")
	local take = Button(actions, "Take live settings", 140, "This module becomes your live settings in its " ..
		"scope: set things up on those pages first, then take them.", function()
		local module = EditModule(picked)
		module.settings = Capture(module.scope)
		Changed()
		ns.Print(("Module Editor: %s took %d live settings"):format(picked, Count(module.settings)))
		Refresh()
	end)
	take:SetPoint("LEFT", tryOn, "RIGHT", 6, 0)
	local revert = Button(actions, "Undo", 70, "This module back to the code's (a new one: gone).", function()
		Edits().modules[picked] = nil
		Changed()
		if not ns.GetModule(picked) then picked = nil end
		Refresh()
	end)
	revert:SetPoint("LEFT", take, "RIGHT", 6, 0)
	local moduleLua = Button(actions, "Lua", 50, "This module as data, for ProfileModules.lua.", function()
		Show(ModuleLua(picked, ns.DevEdits() and ns.DevEdits().modules[picked] or
			{ name = ns.GetModule(picked).name, tip = ns.GetModule(picked).tip, scope = ns.GetModule(picked).scope,
				client = ns.GetModule(picked).client, group = ns.GetModule(picked).group,
				settings = AsSettings(ns.GetModule(picked)) }))
	end)
	moduleLua:SetPoint("LEFT", revert, "RIGHT", 6, 0)
	local usedBy = kit.Label(content, "GameFontHighlightSmall", "")
	usedBy:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -10)
	usedBy:SetWidth(WIDTH)
	usedBy:SetJustifyH("LEFT")
	local changes = kit.Label(content, "GameFontHighlightSmall", "")
	changes:SetPoint("TOPLEFT", usedBy, "BOTTOMLEFT", 0, -8)
	changes:SetWidth(WIDTH)
	changes:SetJustifyH("LEFT")

	-- The box: text to copy (Ctrl+A, Ctrl+C).
	local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
	box:SetSize(WIDTH, 240)
	box:SetPoint("TOPLEFT", changes, "BOTTOMLEFT", 0, -14)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		box:SetBackdropColor(0, 0, 0, 0.8)
	end
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	if ns.SkinScroll then ns.SkinScroll(scroll) end
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	output = CreateFrame("EditBox", nil, scroll)
	output:SetMultiLine(true)
	output:SetAutoFocus(false)
	output:SetFontObject(ChatFontNormal)
	output:SetWidth(WIDTH - 40)
	output:SetScript("OnEscapePressed", output.ClearFocus)
	scroll:SetScrollChild(output)

	function Refresh()
		local edits = ns.DevEdits()
		local counts = { 0, 0, 0 }
		for _ in pairs(edits and edits.modules or {}) do counts[1] = counts[1] + 1 end
		for _, list in pairs(edits and edits.choices or {}) do
			for _ in pairs(list) do counts[2] = counts[2] + 1 end
		end
		for _ in pairs(edits and edits.profiles or {}) do counts[3] = counts[3] + 1 end
		status:SetText(("Changed: %d modules, %d choices, %d profiles"):format(counts[1], counts[2], counts[3]))
		-- Profiles' cells.
		for _, row in ipairs(profileRows) do
			local profile, client = row.profile, ClientOf(row.profile)
			local picks, by = ns.ProfilePicks(profile, client, ns.ALL_BUILTIN_BY_NAME, EditOf)
			local edited = EditOf(profile.name)
			for i, slot in ipairs(ns.PROFILE_SLOTS) do
				local info = ns.SLOT_CHOICES[slot.key]
				local part = picks[slot.key] or (info and info.default)
				local choice = part and ns.GetChoice(slot.key, part)
				local text = choice and choice.label or ("|cffff4040" .. tostring(part) .. "?|r")
				if not picks[slot.key] then
					text = "|cff606060" .. text .. "|r"
				elseif by[slot.key] ~= profile.name then
					text = "|cff909090" .. text .. "|r"
				elseif edited then
					text = "|cff40ff40" .. text .. "|r"
				end
				row.cells[i].text:SetText(text)
			end
			row.undo:SetShown(edited ~= nil)
		end
		-- Choices' modules.
		for _, row in ipairs(choiceRows) do
			local choice = ns.GetChoice(row.slot, row.part)
			local names = {}
			for _, entry in ipairs(choice.modules or {}) do
				if type(entry) == "table" then
					local parts = {}
					for client, key in pairs(entry) do parts[#parts + 1] = client .. ": " .. ModuleName(key) end
					table.sort(parts)
					names[#names + 1] = table.concat(parts, ", ")
				else
					names[#names + 1] = ModuleName(entry)
				end
			end
			local text = #names > 0 and table.concat(names, ", ") or "|cff808080nothing: the defaults|r"
			row.modules:SetText(choice.edited and "|cff40ff40" .. text .. "|r" or text)
			row:SetHeight(math.max(ROW_H, (row.modules:GetStringHeight() or 0) + 8))
		end
		-- The module picked.
		local module = picked and ns.GetModule(picked)
		for _, widget in ipairs({ nameLabel, nameBox, tipLabel, tipBox, scopeText, scopeButton, actions, usedBy }) do
			widget:SetShown(module ~= nil)
		end
		if not module then
			pick:SetText("Pick a module...")
			changes:SetText("Pick a module to see what it changes, or make one with New from...")
			return
		end
		pick:SetText((module.edited and "|cff40ff40" or "") .. module.name .. " |cff808080(" .. picked .. ")|r")
		nameBox.shown, tipBox.shown = module.name, module.tip or ""
		if not nameBox:HasFocus() then nameBox:SetText(module.name) end
		if not tipBox:HasFocus() then tipBox:SetText(module.tip or "") end
		local scope = {}
		for _, entry in ipairs(module.scope or {}) do
			scope[#scope + 1] = entry:find("/") and entry:gsub("/top$", " (top)"):gsub("/", " > ") or entry .. " (all of it)"
		end
		scopeText:SetText("Scope: " .. (#scope > 0 and table.concat(scope, ", ") or "|cffff4040none|r")
			.. (module.client and " |cff808080(" .. module.client .. " only)|r" or ""))
		revert:SetText(ns.PROFILE_MODULE_BY_KEY[picked] and "Undo" or "Delete")
		revert:SetEnabled(module.edited == true)
		-- Who uses it.
		local users = {}
		for slot, info in pairs(ns.SLOT_CHOICES) do
			for _, choice in ipairs(info.choices) do
				for _, entry in ipairs(ns.ChoiceModules(slot, choice.part, ns.CLIENT) or {}) do
					if entry.key == picked then users[#users + 1] = slot .. "." .. choice.part end
				end
			end
		end
		table.sort(users)
		usedBy:SetText("In choices: " .. (#users > 0 and table.concat(users, ", ") or "none"))
		-- What it changes, by where.
		local lines = {}
		for _, change in ipairs(ns.ModuleEffect({ { module = module } }, ns.CLIENT)) do
			local address = ns.SettingAddress(change[1], change[2])
			local inside = false
			for _, each in ipairs(ns.SettingAddresses(change[1], change[2]) or {}) do
				inside = inside or ns.InScope(module.scope or {}, each)
			end
			local value = type(change[3]) == "table" and "(" .. Count(change[3]) .. " entries)" or tostring(change[3])
			lines[#lines + 1] = ("%s%s|r  %s%s = %s"):format(inside and "|cffffd100" or "|cffff4040",
				address and address:gsub("/top$", " (top)"):gsub("/", " > ") or "on no page",
				change[1], change[2] ~= nil and "." .. tostring(change[2]) or "", value)
		end
		table.sort(lines)
		changes:SetText(("Changes %d settings (red: outside its scope):\n"):format(#lines) .. table.concat(lines, "\n"))
	end

	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Module Editor", "Module Editor")
end
