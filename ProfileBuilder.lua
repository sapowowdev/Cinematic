-- The dev build's Profile Builder page: every built-in profile (both
-- clients', and dev-only and hidden ones) with the profile it starts from
-- and its modules (ProfileModules.lua). Modules... ticks one in or out to
-- try it on this client (kept in db.devModules until cleared, and only
-- taking effect when the profile is picked or reset); Lua gives the
-- profile's modules line for Profiles.lua. Capture writes the live settings
-- of one page or section as a module for ProfileModules.lua, and Compare
-- lists the settings two profiles differ on, by page and section. Output
-- goes in the box at the bottom, to copy. Options.lua calls
-- ns.CreateProfileBuilder with the page helpers it shares (dev build only).

local _, ns = ...

local NAME_W, FROM_W, MODULES_W, ROW_H = 130, 80, 400, 22

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
	local parts = {}
	for _, k in ipairs(keys) do
		local key
		if type(k) == "string" and k:match("^[%a_][%w_]*$") then
			key = k
		elseif type(k) == "string" then
			key = ("[%q]"):format(k)
		else
			key = "[" .. tostring(k) .. "]"
		end
		parts[#parts + 1] = key .. " = " .. Lua(value[k])
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
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

-- The client a profile is shown for: its own, or this one.
local function ClientOf(profile)
	return profile.client or ns.CLIENT
end

-- A profile's own module list as the builder has it: the changed one, or
-- the code's (each entry as it's written, { forever =, retail = } too).
local function OwnModules(profile)
	local changed = ns.db.devModules and ns.db.devModules[profile.name]
	return changed or profile.modules or {}, changed ~= nil
end

-- Its modules, resolved on its client, with the changes.
local function Resolved(profile)
	local own = OwnModules(profile)
	return ns.ResolveModules(profile, ClientOf(profile), ns.ALL_BUILTIN_BY_NAME, own)
end

-- The modules cell: its own white, the ones it starts from grey, and green
-- with a * when the builder's changed its list.
local function ModulesText(profile)
	local _, changed = OwnModules(profile)
	local parts = {}
	for _, entry in ipairs(Resolved(profile)) do
		local text = entry.key
		if entry.missing then
			text = "|cffff4040" .. text .. "?|r"
		elseif entry.from ~= profile.name then
			text = "|cff808080" .. text .. "|r"
		elseif changed then
			text = "|cff40ff40" .. text .. "|r"
		end
		parts[#parts + 1] = text
	end
	return table.concat(parts, ", ") .. (changed and " |cff40ff40*|r" or "")
end

-- An entry as Lua: a key, or { forever = key, retail = key }.
local function EntryLua(entry)
	return type(entry) == "table" and Lua(entry) or ("%q"):format(entry)
end

-- The profile's modules line, changes and all, for Profiles.lua.
local function ModulesLua(profile)
	local fields = {}
	for _, entry in ipairs((OwnModules(profile))) do fields[#fields + 1] = EntryLua(entry) end
	return ("-- %s\n\t\t%smodules = { %s },"):format(profile.name,
		profile.from and ("from = %q,\n\t\t"):format(profile.from) or "", table.concat(fields, ", "))
end

-- Keeps a profile's changed list (none: when it's back to the code's).
local function Keep(profile, own)
	local same = #own == #(profile.modules or {})
	for i, entry in ipairs(own) do
		same = same and EntryLua(entry) == EntryLua(profile.modules[i])
	end
	ns.db.devModules = ns.db.devModules or {}
	ns.db.devModules[profile.name] = not same and own or nil
	if not next(ns.db.devModules) then ns.db.devModules = nil end
end

-- Ticks a module in or out of a profile's own list (this client's: an
-- entry for the other client's stays). Out of one it starts from: "-key".
local function Toggle(profile, key)
	local own = {}
	for _, entry in ipairs((OwnModules(profile))) do own[#own + 1] = entry end
	local client = ClientOf(profile)
	for i, entry in ipairs(own) do
		local each = type(entry) == "table" and entry[client] or entry
		if each == key or each == "-" .. key then
			if type(entry) == "table" then
				local copy = {}
				for k, v in pairs(entry) do copy[k] = v end
				copy[client] = nil
				own[i] = next(copy) and copy or nil
			else
				own[i] = nil
			end
			local packed = {}
			for j = 1, #own + 1 do
				if own[j] ~= nil then packed[#packed + 1] = own[j] end
			end
			own = packed
			-- (Taking out a "-key" puts the inherited one back; taking out
			-- one of its own is done. Either way, the list's set.)
			Keep(profile, own)
			return
		end
	end
	-- Not in its own list: in it now, or out if it's one it starts from.
	local inherited = false
	for _, entry in ipairs(Resolved(profile)) do
		if entry.key == key and entry.from ~= profile.name then inherited = true end
	end
	own[#own + 1] = inherited and "-" .. key or key
	Keep(profile, own)
end

-- The live settings in one page or section (address, or a page's name)
-- that differ from the defaults, as a module: each setting, and each list's
-- rows there.
local function CaptureLua(where)
	local scope = { where }
	local db, lines = ns.db, {}
	local function Here(key, row)
		for _, address in ipairs(ns.SettingAddresses(key, row) or {}) do
			if ns.InScope(scope, address) then return true end
		end
		return false
	end
	local keys = {}
	for key in pairs(ns.DEFAULTS) do
		if ns.IsProfileKey(key) and not ns.IS_PROFILE_TABLE[key] and Here(key) and db[key] ~= ns.DEFAULTS[key] then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do lines[#lines + 1] = ("\t\t\tset(%q, %s)"):format(key, Lua(db[key])) end
	local lists = {}
	for _, key in ipairs(ns.PROFILE_TABLES) do lists[#lists + 1] = key end
	table.sort(lists)
	for _, key in ipairs(lists) do
		if type(db[key]) == "table" then
			local rows = {}
			for row, value in pairs(db[key]) do
				if Here(key, row) then rows[row] = value end
			end
			if next(rows) then lines[#lines + 1] = ("\t\t\tset(%q, %s)"):format(key, Lua(rows)) end
		end
	end
	return ("-- %s captured %s from %s (%d settings): paste into ProfileModules.lua's list, and name it.\n"
		.. "\t{ key = \"new-module\", name = \"New module\", scope = { %q },\n\t\ttip = \"What it does.\",\n"
		.. "\t\tapply = function(set)\n%s\n\t\tend },"):format(where, date("%Y-%m-%d %H:%M"),
		ns.ProfileLabel(ns.ActiveProfile()), #lines, where, table.concat(lines, "\n"))
end

-- The settings two profiles differ on, by page and section (a list row by
-- row; a row one hasn't got: "default").
local function CompareText(a, b)
	local A, B = ns.ProfileSettings(a), ns.ProfileSettings(b)
	local byAddress = {}
	local function Add(key, row, text)
		local address = ns.SettingAddress(key, row) or "on no page"
		byAddress[address] = byAddress[address] or {}
		table.insert(byAddress[address], text)
	end
	local function Shown(value)
		if value == nil then return "default" end
		return type(value) == "table" and Lua(value) or tostring(value)
	end
	for key in pairs(ns.DEFAULTS) do
		if ns.IsProfileKey(key) and A[key] ~= B[key] and not ns.IS_PROFILE_TABLE[key] then
			Add(key, nil, ("%s: %s -> %s"):format(key, Shown(A[key]), Shown(B[key])))
		end
	end
	for _, key in ipairs(ns.PROFILE_TABLES) do
		local listA, listB = A[key] or {}, B[key] or {}
		local rows = {}
		for row in pairs(listA) do rows[row] = true end
		for row in pairs(listB) do rows[row] = true end
		for row in pairs(rows) do
			local va, vb = listA[row], listB[row]
			local differ
			if type(va) == "table" or type(vb) == "table" then differ = Lua(va) ~= Lua(vb) else differ = va ~= vb end
			if differ then
				Add(key, row, ("%s.%s: %s -> %s"):format(key, tostring(row), Shown(va), Shown(vb)))
			end
		end
	end
	local addresses = {}
	for address in pairs(byAddress) do addresses[#addresses + 1] = address end
	table.sort(addresses)
	local out = { ("%s -> %s"):format(ns.ProfileLabel(a), ns.ProfileLabel(b)) }
	for _, address in ipairs(addresses) do
		local list = byAddress[address]
		table.sort(list)
		out[#out + 1] = ("\n%s (%d):"):format(address, #list)
		for _, line in ipairs(list) do out[#out + 1] = "  " .. line end
	end
	if #addresses == 0 then out[#out + 1] = "\nthe same settings" end
	return table.concat(out, "\n")
end

function ns.CreateProfileBuilder(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "|cffff4040DEV ONLY|r Profile Builder")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.Label(content, "GameFontHighlight", "Each built-in profile, the one it starts from, and its " ..
		"modules (grey: from the one it starts from). Modules... ticks one in or out on this client (green*: " ..
		"changed; it takes effect when you pick or reset that profile, and your live settings stay as they are). " ..
		"Lua puts the profile's modules line in the box below, for Profiles.lua. /cine debug modules checks them.")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	intro:SetWidth(640)
	intro:SetJustifyH("LEFT")

	local function Button(parent, text, width, tip, onClick)
		local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		button:SetSize(width, ROW_H)
		button:SetText(text)
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", onClick)
		return button
	end

	local output -- (the box at the bottom)
	local Refresh
	local rows = {}
	local anchor = intro
	for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(NAME_W + FROM_W + MODULES_W + 120, ROW_H)
		row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, anchor == intro and -14 or -4)
		anchor = row
		local tags = {}
		if profile.client then tags[#tags + 1] = profile.client == "forever" and "F" or "R" end
		if profile.dev then tags[#tags + 1] = "dev" end
		if profile.hidden then tags[#tags + 1] = "hidden" end
		local name = kit.Label(row, "GameFontHighlightSmall", (profile.label or profile.name)
			.. (#tags > 0 and " |cff808080(" .. table.concat(tags, ",") .. ")|r" or ""))
		name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
		name:SetWidth(NAME_W - 6)
		name:SetWordWrap(false)
		local from = kit.Label(row, "GameFontDisableSmall", profile.from and ns.ProfileLabel(profile.from) or "defaults")
		from:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_W, -4)
		from:SetWidth(FROM_W - 6)
		from:SetWordWrap(false)
		row.modules = kit.Label(row, "GameFontHighlightSmall")
		row.modules:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_W + FROM_W, -4)
		row.modules:SetWidth(MODULES_W - 6)
		row.modules:SetJustifyH("LEFT")
		row.profile = profile
		local edit = Button(row, "Modules...", 76, "Tick a module in or out of this profile, on this client.", function(self)
			local entries = {}
			local _, changed = OwnModules(profile)
			if changed then
				entries[#entries + 1] = { "Undo (as in the code)", function()
					ns.db.devModules[profile.name] = nil
					if not next(ns.db.devModules) then ns.db.devModules = nil end
					ns.ForgetProfileBases()
					Refresh()
				end }
			end
			local inIt = {}
			for _, entry in ipairs(Resolved(profile)) do inIt[entry.key] = entry.from end
			for _, module in ipairs(ns.PROFILE_MODULES) do
				if not module.client or module.client == ClientOf(profile) then
					local mark = inIt[module.key] and "|cff40ff40[x]|r " or "[  ] "
					local note = inIt[module.key] and inIt[module.key] ~= profile.name
						and " |cff808080(from " .. ns.ProfileLabel(inIt[module.key]) .. ")|r" or ""
					entries[#entries + 1] = { mark .. module.name .. note, function()
						Toggle(profile, module.key)
						ns.ForgetProfileBases()
						ns.Print(("Profile Builder: %s %s %s (when you pick or reset it)"):format(profile.name,
							inIt[module.key] and "without" or "with", module.key))
						Refresh()
					end }
				end
			end
			Menu(self, entries)
		end)
		edit:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_W + FROM_W + MODULES_W, 0)
		local lua = Button(row, "Lua", 40, "This profile's modules line, with your changes, in the box below.", function()
			output:SetText(ModulesLua(profile))
			output:HighlightText()
			output:SetFocus()
		end)
		lua:SetPoint("LEFT", edit, "RIGHT", 4, 0)
		rows[#rows + 1] = row
	end

	-- Clear changes, Capture, Compare.
	local clear = Button(content, "Clear changes", 120, "Every profile's modules back to the code's.", function()
		ns.db.devModules = nil
		ns.ForgetProfileBases()
		Refresh()
	end)
	clear:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
	local capture = Button(content, "Capture...", 110, "The live settings of one page, or one section of it, that " ..
		"differ from the defaults, as a module to paste into ProfileModules.lua.", function(self)
		local entries = {}
		local sections = ns.PageSections()
		local pages = {}
		for page in pairs(sections) do pages[#pages + 1] = page end
		table.sort(pages)
		local function Show(where)
			return function()
				output:SetText(CaptureLua(where))
				output:HighlightText()
				output:SetFocus()
			end
		end
		for _, page in ipairs(pages) do
			local sub = { { "The whole page", Show(page) } }
			for _, address in ipairs(sections[page]) do
				local section = address:match("/(.*)$")
				sub[#sub + 1] = { section == "top" and "Top of the page" or section, Show(address) }
			end
			entries[#entries + 1] = { page, sub }
		end
		Menu(self, entries)
	end)
	capture:SetPoint("LEFT", clear, "RIGHT", 8, 0)

	-- Compare: the two profiles picked (the active one and the first built-in to start).
	local picked = {}
	local function PickButton(index)
		local button
		button = Button(content, "", 130, "Pick a profile to compare.", function(self)
			local entries = {}
			for _, name in ipairs(ns.ProfileNames()) do
				entries[#entries + 1] = { ns.ProfileLabel(name), function()
					picked[index] = name
					button:SetText(ns.ProfileLabel(name))
				end }
			end
			Menu(self, entries)
		end)
		return button
	end
	local first, second = PickButton(1), PickButton(2)
	first:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -10)
	second:SetPoint("LEFT", first, "RIGHT", 8, 0)
	local compare = Button(content, "Compare", 100, "The settings these two profiles differ on, by page and " ..
		"section (each as it would be live: its own values with your changes).", function()
		output:SetText(CompareText(picked[1], picked[2]))
		output:SetCursorPosition(0)
	end)
	compare:SetPoint("LEFT", second, "RIGHT", 8, 0)

	-- The box: text to copy (Ctrl+A, Ctrl+C).
	local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
	box:SetSize(640, 220)
	box:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -12)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		box:SetBackdropColor(0, 0, 0, 0.8)
	end
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	output = CreateFrame("EditBox", nil, scroll)
	output:SetMultiLine(true)
	output:SetAutoFocus(false)
	output:SetFontObject(ChatFontNormal)
	output:SetWidth(600)
	output:SetScript("OnEscapePressed", output.ClearFocus)
	scroll:SetScrollChild(output)

	-- (Each row as tall as its modules' lines, the next below it.)
	function Refresh()
		local above
		for _, row in ipairs(rows) do
			row.modules:SetText(ModulesText(row.profile))
			row:SetHeight(math.max(ROW_H, (row.modules:GetStringHeight() or 0) + 8))
			row:ClearAllPoints()
			if above then
				row:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -4)
			else
				row:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
			end
			above = row
		end
		picked[1] = picked[1] or ns.ActiveProfile()
		picked[2] = picked[2] or ns.BUILTIN_PROFILES[1].name
		first:SetText(ns.ProfileLabel(picked[1]))
		second:SetText(ns.ProfileLabel(picked[2]))
	end

	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Profile Builder", "Profile Builder")
end
