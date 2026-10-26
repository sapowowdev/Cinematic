-- Cinematic: wheels of the player's own. Each works like the marker wheels
-- (MarkerWheel.lua's MakeWheel), and each of its slots runs a command: a
-- slash command, or several, a line each (anything a macro can do). So a raid
-- leader can have /rw, /readycheck and a pull timer under one key, in a
-- fight too, as the commands run through secure buttons like a macro's.
--
-- They're kept for the account (db.customWheels), and made from a pool of
-- MAX wheels made as the addon loads, each with its own key in Bindings.xml
-- (named after the wheel using it). A wheel's slots only change out of a
-- fight: one edited in a fight changes as it ends.
local _, ns = ...
local L = ns.L

local MAX = 8 -- wheels (Bindings.xml has a key for each)
ns.CUSTOM_WHEEL_MAX = MAX
ns.CUSTOM_WHEEL_SLOTS = 12 -- slots on one wheel
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
ns.CUSTOM_WHEEL_DEFAULT_ICON = DEFAULT_ICON
local COLOR = { 1, 0.82, 0.3 }

local pool = {} -- the secure wheels, by pool number

-- The saved wheels: a list of { pool, name, icon, slots }, each slot
-- { label, icon, command }.
local function Saved()
	local db = ns.db
	return db and type(db.customWheels) == "table" and db.customWheels or {}
end
ns.CustomWheels = Saved

local function ByPool(n)
	for _, wheel in ipairs(Saved()) do
		if wheel.pool == n then
			return wheel
		end
	end
end

-- A slot's name: its label, or with none, its command's first line.
function ns.CustomSlotLabel(slot)
	if type(slot.label) == "string" and slot.label:match("%S") then
		return slot.label
	end
	local first = (slot.command or ""):match("^%s*([^\n]-)%s*\n") or (slot.command or ""):match("^%s*(.-)%s*$")
	return first ~= "" and first or L["(nothing yet)"]
end

-- The wheel's key binding (the game's name for it).
function ns.CustomWheelAction(data)
	return "CLICK CinematicCustomWheel" .. data.pool .. "Button:LeftButton"
end

local function SlotsFor(data)
	local slots = {}
	for _, slot in ipairs(data.slots or {}) do
		slots[#slots + 1] = { icon = slot.icon or DEFAULT_ICON, trim = true, color = COLOR,
			label = ns.CustomSlotLabel(slot), attributes = { type = "macro", macrotext = slot.command or "" } }
	end
	return slots
end

for n = 1, MAX do
	pool[n] = ns.MakeWheel({
		name = "CinematicCustomWheel" .. n,
		title = "Your wheel",
		binding = "Your wheel",
		slots = {},
		linger = 0.4, -- (up a moment after a pick, showing which it was)
		lingerPicks = true,
		Title = function()
			local data = ByPool(n)
			return data and data.name or ""
		end,
		BindingName = function()
			local data = ByPool(n)
			if data then
				return L["%s (hold)"]:format(data.name)
			end
			return L["Your wheel %d (not made yet)"]:format(n)
		end,
	})
end
ns.LinkSecureWheels()

-- Lays a wheel out again from what's saved (none saved: empty), now or, in a
-- fight, as it ends.
local pending = {}
local pendingFrame = CreateFrame("Frame")
local function Apply(n)
	local data = ByPool(n)
	pool[n].RefreshBindingName()
	if pool[n].SetSlots(data and SlotsFor(data) or {}) then
		pending[n] = nil
	else
		pending[n] = true
		pendingFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
end
pendingFrame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		for n in pairs(pending) do
			Apply(n)
		end
		return
	end
	-- (PLAYER_LOGIN: the settings are loaded.)
	for n = 1, MAX do
		Apply(n)
	end
	ns.RebuildMasterWheel()
end)
pendingFrame:RegisterEvent("PLAYER_LOGIN")

-- After a wheel's been changed on the Wheels page: it, its key's name and
-- the master wheel.
function ns.ApplyCustomWheel(data)
	Apply(data.pool)
	ns.RebuildMasterWheel()
end

-- The master wheel's choices for these (MarkerWheel.lua): off it until ticked.
function ns.CustomWheelChoices()
	local list = {}
	for _, data in ipairs(Saved()) do
		list[#list + 1] = { key = "custom" .. data.pool, icon = data.icon or DEFAULT_ICON, trim = true,
			color = COLOR, label = data.name, opens = pool[data.pool], offByDefault = true, custom = true }
	end
	return list
end

-- For the previews: a wheel's slots as it shows them.
function ns.CustomWheelEntries(data)
	local list = {}
	for _, slot in ipairs(SlotsFor(data)) do
		list[#list + 1] = { label = slot.label, icon = slot.icon, trim = true, color = COLOR }
	end
	return list
end

-- What a new wheel can start from: key, button and tip (its button's on the
-- Your wheels page, in English), and Make(), its name and slots.
ns.CUSTOM_WHEEL_TEMPLATES = {
	{ key = "blank", button = "New wheel", tip = "A wheel with nothing on it yet, for you to fill.",
		Make = function() return L["My wheel"], {} end },
}

-- A name no other wheel has: name, or name 2, name 3...
local function FreeName(name)
	local taken = {}
	for _, data in ipairs(Saved()) do
		taken[data.name] = true
	end
	local try, i = name, 1
	while taken[try] do
		i = i + 1
		try = name .. " " .. i
	end
	return try
end

-- A new wheel from a template (one of CUSTOM_WHEEL_TEMPLATES, or any table
-- whose Make() gives a name, slots and optionally an icon): it, or nil with
-- all MAX made.
function ns.NewCustomWheel(template)
	local db = ns.db
	if not db then
		return nil
	end
	local used = {}
	for _, data in ipairs(Saved()) do
		used[data.pool] = true
	end
	for n = 1, MAX do
		if not used[n] then
			local name, slots, icon = template.Make()
			local data = { pool = n, name = FreeName(name),
				icon = icon or slots[1] and slots[1].icon or DEFAULT_ICON, slots = slots }
			db.customWheels = type(db.customWheels) == "table" and db.customWheels or {}
			db.customWheels[#db.customWheels + 1] = data
			ns.ForgetMasterWheel("custom" .. n) -- (nothing left of a wheel that had its place)
			ns.ApplyCustomWheel(data)
			return data
		end
	end
	return nil
end

-- Deletes a wheel, and takes its keys off (out of a fight: keys can't change in one).
function ns.DeleteCustomWheel(data)
	local list = Saved()
	for i = #list, 1, -1 do
		if list[i] == data then
			table.remove(list, i)
		end
	end
	ns.ForgetMasterWheel("custom" .. data.pool)
	if not InCombatLockdown() then
		local keys = { GetBindingKey(ns.CustomWheelAction(data)) }
		for _, key in ipairs(keys) do
			SetBinding(key)
		end
		if #keys > 0 then
			SaveBindings(GetCurrentBindingSet())
		end
	end
	ns.ApplyCustomWheel(data)
end

-- A wheel someone shared (Share.lua's ns.ReadSharedWheel): added as a new
-- one of yours, or nil with all MAX made.
function ns.AddSharedWheel(info)
	local slots = {}
	for _, slot in ipairs(info.slots) do
		slots[#slots + 1] = { label = slot.label, icon = slot.icon or DEFAULT_ICON, command = slot.command }
	end
	return ns.NewCustomWheel({ Make = function() return info.name, slots, info.icon end })
end

-- An icon from what's typed: a spell or item (its name, ID or link), an
-- icon's file name (INV_Misc_Bag_07) or path, or a file ID. nil if none.
local probe = UIParent:CreateTexture()
probe:Hide()
local function Exists(file)
	return file and probe:SetTexture(file) ~= false and file or nil
end
local function SpellIcon(spell)
	local GetTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
	local ok, icon = pcall(GetTexture, spell)
	return ok and icon or nil
end
local function ItemIcon(item)
	local ok, icon = pcall(GetItemIcon, item)
	if ok and icon then
		return icon
	end
	local found, _, _, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, item)
	return found and texture or nil
end
function ns.FindIcon(text)
	text = (text or ""):match("^%s*(.-)%s*$")
	if text == "" then
		return nil
	end
	local itemID, spellID = text:match("|Hitem:(%d+)"), text:match("|Hspell:(%d+)")
	if itemID then
		return ItemIcon(tonumber(itemID))
	elseif spellID then
		return SpellIcon(tonumber(spellID))
	end
	local number = tonumber(text)
	if number then
		return SpellIcon(number) or ItemIcon(number) or Exists(number)
	end
	return SpellIcon(text) or ItemIcon(text)
		or Exists(text:find("[\\/]") and text or "Interface\\Icons\\" .. text)
end
