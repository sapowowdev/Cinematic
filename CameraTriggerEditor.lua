-- Cinematic: the Cameras page's editor for triggers of your own
-- (CustomTriggers.lua): the Starts and Ends lines in such a row's drawer,
-- and the window that shares a trigger or a shot (Shots.lua) as text, or
-- adds one someone shared.
local _, ns = ...
local L = ns.L

-- A dropdown of { value, text } choices (or a function giving them), or on a
-- client without the modern dropdown a button that steps through them.
local function Menu(parent, width, choices, get, set)
	local function List() return type(choices) == "function" and choices() or choices end
	local ok, menu = ns.MenuDropdown(parent)
	if ok and menu and menu.SetupMenu then
		menu:SetWidth(width)
		menu:SetupMenu(function(_, root)
			for _, choice in ipairs(List()) do
				root:CreateRadio(choice.text, function() return ns.GetDB() ~= nil and get() == choice.value end,
					function() set(choice.value) end)
			end
		end)
		menu.Refresh = function(self) self:GenerateMenu() end
	else
		menu = ns.PanelButton(parent)
		menu:SetSize(width, 22)
		menu:SetScript("OnClick", function()
			local list, now = List(), get()
			for i, choice in ipairs(list) do
				if choice.value == now then
					set(list[i % #list + 1].value)
					return
				end
			end
			if list[1] then set(list[1].value) end
		end)
		menu.Refresh = function(self)
			local now = get()
			for _, choice in ipairs(List()) do
				if choice.value == now then
					self:SetText(choice.text)
					return
				end
			end
			self:SetText("")
		end
	end
	menu.searchSkip = true
	return menu
end
ns.ChoiceMenu = Menu
-- (Shown only while test() holds; refreshed as before.)
local function ShownWhile(control, test)
	local refresh = control.Refresh
	control.Refresh = function(self)
		local shown = test() and true or false
		self:SetShown(shown)
		if shown and refresh then refresh(self) end
	end
	return control
end

-- A trigger's camera choices in the menus' order: its cameras (camera scripts
-- among them, CameraScripts.lua), your shots where it has the cozy camera,
-- then No camera.
function ns.CameraChoiceValues(cameras)
	local list, none = {}, nil
	for _, value in ipairs(cameras) do
		if value == "none" or value == false then none = value else list[#list + 1] = value end
	end
	for _, value in ipairs(cameras) do
		if value == "cozy" then
			for _, shot in ipairs((ns.ShotList())) do list[#list + 1] = "shot:" .. shot end
		end
	end
	if none ~= nil then list[#list + 1] = none end
	return list
end
-- A camera menu's New shot... entry: a new shot of the cozy camera, picked
-- with set(value), and My Shots opened on it to set its numbers.
function ns.NewShotFor(set)
	local id = ns.AddShot("cozy")
	if not id then
		ns.Print((L["You have %d shots already: delete one to make another."]):format(ns.SHOT_MAX))
		return
	end
	set("shot:" .. id)
	ns.myShotsSelect = id
	ns.OpenOptions("My Shots")
end
ns.CUSTOM_CAMERA_TIP = "The camera it plays: one that runs where you stand, a camera script, or a shot of yours " ..
	"(New shot... makes one and opens My Shots). The flight, RP walk, auto-run, quest and chat cameras aren't " ..
	"here: they need you flying, walking or talking to an NPC, and have triggers of their own."

-- Where the lines read and write a trigger's settings (source, until, after,
-- name, camera, music, cine): a saved trigger's row (RowStore), or the New
-- trigger panel's draft, kept until Save (a plain table's).
local function RowStore(id)
	return {
		get = function(field) return ns.GetDB().cameraRows[id .. "." .. field] end,
		set = function(field, value) ns.GetDB().cameraRows[id .. "." .. field] = value end,
	}
end
local function TableStore(data)
	return { get = function(field) return data[field] end, set = function(field, value) data[field] = value end }
end
local function Source(store)
	local kind, what = tostring(store.get("source") or ""):match("^(%a+):(.*)$")
	return kind or "emote", what or ""
end
local function SetSource(store, kind, what)
	store.set("source", kind .. ":" .. what)
end
local function UntilKind(store)
	local text = store.get("until")
	if type(text) == "string" and text:find("^time:") then return "time" end
	return type(text) == "string" and text or "move"
end
local function Seconds(store)
	return tonumber(tostring(store.get("until") or ""):match("^time:(%d+)")) or 5
end
local function CurrentPlace()
	local name = GetSubZoneText and GetSubZoneText()
	if type(name) ~= "string" or name == "" then name = GetZoneText and GetZoneText() end
	return type(name) == "string" and name or ""
end

-- Each kind's first what and until, and the untils it can have.
local KIND_START = { emote = { "cheer", "move" }, spell = { "", "ends" }, aura = { "", "ends" },
	place = { "", "ends" }, moment = { "levelup", "time:5" }, state = { "mounted", "ends" }, key = { "1", "key" } }
local UNTILS = { emote = { "move", "time" }, spell = { "ends", "move", "time" }, aura = { "ends", "move", "time" },
	place = { "ends", "move", "time" }, moment = { "time", "move" }, state = { "ends", "move", "time" },
	key = { "key", "move", "time" } }
local SECONDS = { 3, 5, 8, 10, 15, 20, 30, 60 }
-- The priority list's places (Triggers.lua's built-in sources).
local AFTER = { { "", "First, before everything" }, { "depart", "After Hearthstones and teleports" },
	{ "logout", "After logging out" }, { "afk", "After going AFK" }, { "byFire", "After sitting by a campfire" },
	{ "emote", "After emotes and seats" }, { "weapon", "After a drawn weapon" },
	{ "campfire", "After a campfire buff" }, { "still", "Last, after standing still" } }
-- (A typed what's hint, greyed in its empty box.)
local HINTS = { emote = "cheer, /lol...", spell = "Fishing, or a spell ID", aura = "A buff's name or spell ID",
	place = "A zone or subzone" }

local function UntilChoices(store)
	local kind = Source(store)
	local ENDS = { spell = L["The cast ends"], aura = L["The buff fades"], place = L["You leave"],
		state = L["It stops"] }
	local TEXT = { move = L["You move"], ends = ENDS[kind] or L["It ends"], time = L["A set time"],
		key = L["You press its key again"] }
	local list = {}
	for _, value in ipairs(UNTILS[kind] or UNTILS.emote) do list[#list + 1] = { value = value, text = TEXT[value] } end
	return list
end
-- (Made as the page is, once the language is known.)
local SECOND_CHOICES, AFTER_CHOICES
local function MakeChoices()
	if SECOND_CHOICES then return end
	SECOND_CHOICES, AFTER_CHOICES = {}, {}
	for _, n in ipairs(SECONDS) do SECOND_CHOICES[#SECOND_CHOICES + 1] = { value = n, text = (L["%d sec"]):format(n) } end
	for _, each in ipairs(AFTER) do AFTER_CHOICES[#AFTER_CHOICES + 1] = { value = each[1], text = L[each[2]] } end
end

-- The Starts and Ends lines on parent for a store. kit: At(line, control, x),
-- Tooltip, AddControl (each control, refreshed with the page or panel),
-- x (where the lines' controls start), Saved() (after each change).
local function BuildLines(parent, store, kit)
	local At, Tooltip, AddControl, x, Saved = kit.At, kit.Tooltip, kit.AddControl, kit.x, kit.Saved
	MakeChoices()

	-- Starts: the kind, then what (typed, or picked from its list).
	local kind = At("Starts", Menu(parent, 130, ns.CUSTOM_TRIGGER_KINDS, function() return (Source(store)) end,
		function(value)
			local start = KIND_START[value] or KIND_START.emote
			SetSource(store, value, value == "place" and CurrentPlace() or start[1])
			store.set("until", start[2] ~= "move" and start[2] or nil)
			Saved()
		end), x)
	Tooltip(kind, L["What starts this trigger's camera: an emote you do, a spell you cast, a buff on you, a place " ..
		"you're in, a moment (leveling up...), something you are (mounted...), or a key you press."])
	AddControl(kind)

	local function Typed() local k = Source(store) return HINTS[k] ~= nil end
	local box = At("Starts", ns.SkinEditBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate")), x + 146)
	box:SetSize(190, 20)
	box:SetAutoFocus(false)
	box:SetMaxLetters(80)
	box.searchSkip = true
	local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 2, 0)
	hint:SetPoint("RIGHT", -2, 0)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(false)
	local function SaveBox(self)
		local text = self:GetText():gsub("[%c|]", ""):match("^%s*(.-)%s*$")
		local k = Source(store)
		if k == "emote" then text = ns.EmoteToken(text) end
		SetSource(store, k, text)
		hint:SetShown(text == "")
		Saved()
	end
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusLost", SaveBox)
	box:SetScript("OnEditFocusGained", function() hint:Hide() end)
	-- (Typing counts at once, for the panel's Save: the box is read as it changes.)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput and kit.typing then kit.typing(self:GetText()) end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(select(2, Source(store)))
		self:ClearFocus()
	end)
	box.Refresh = function(self)
		if self:HasFocus() then return end
		local k, what = Source(store)
		self:SetText(what)
		hint:SetText(L[HINTS[k] or ""])
		hint:SetShown(what == "")
	end
	ShownWhile(box, Typed)
	Tooltip(box, L["Emotes: the command, with or without its slash. Spells and buffs: the name in your game " ..
		"language, or a spell ID (works in any language). Places: the zone or subzone name as the game shows it."])
	AddControl(box)

	local function Fixed()
		local k = Source(store)
		return k == "moment" and ns.CUSTOM_TRIGGER_MOMENTS or k == "state" and ns.CUSTOM_TRIGGER_STATES
			or k == "key" and ns.CUSTOM_TRIGGER_KEYS or nil
	end
	local pick = At("Starts", Menu(parent, 200, function() return Fixed() or {} end,
		function() return (select(2, Source(store))) end,
		function(value)
			SetSource(store, (Source(store)), value)
			Saved()
		end), x + 140)
	ShownWhile(pick, Fixed)
	Tooltip(pick, L["Which one. Key bindings are set in the game's Key Bindings, under Cinematic."])
	AddControl(pick)

	local here = At("Starts", ns.PanelButton(parent), x + 344)
	here:SetSize(60, 22)
	here:SetText(L["Here"])
	here.searchSkip = true
	here:SetScript("OnClick", function()
		SetSource(store, "place", CurrentPlace())
		Saved()
	end)
	ShownWhile(here, function() return Source(store) == "place" end)
	Tooltip(here, L["Fill in the subzone you're in now (or the zone, where there's no subzone)."])
	AddControl(here)

	-- Ends: until when, how long, and its place in the priority list.
	local untilMenu = At("Ends", Menu(parent, 150, function() return UntilChoices(store) end,
		function() return UntilKind(store) end,
		function(value)
			store.set("until", value == "time" and ("time:" .. Seconds(store)) or (value ~= "move" and value or nil))
			Saved()
		end), x)
	Tooltip(untilMenu, L["When its camera stops. Moving always stops it too, as it does every camera that runs " ..
		"while you stand still."])
	AddControl(untilMenu)

	local seconds = At("Ends", Menu(parent, 80, SECOND_CHOICES, function() return Seconds(store) end,
		function(value)
			store.set("until", "time:" .. value)
			Saved()
		end), x + 160)
	ShownWhile(seconds, function() return UntilKind(store) == "time" end)
	Tooltip(seconds, L["How long its camera runs."])
	AddControl(seconds)

	local after = At("Ends", Menu(parent, 210, AFTER_CHOICES,
		function()
			local value = store.get("after")
			return value == nil and "emote" or value
		end,
		function(value)
			store.set("after", value ~= "emote" and value or nil)
			Saved()
		end), x + 250)
	Tooltip(after, L["Where it comes when other triggers are on at the same time: the first one on in this " ..
		"order plays. Going AFK while doing an emote is the AFK camera, say."])
	AddControl(after)
end

-- A saved trigger's drawer: its Starts and Ends lines, and a Share button
-- on its Name line. kit: At, Changed(), Tooltip, AddControl, x, shareX.
function ns.BuildCustomTriggerLines(drawer, id, kit)
	BuildLines(drawer, RowStore(id), { At = kit.At, Tooltip = kit.Tooltip, AddControl = kit.AddControl, x = kit.x,
		Saved = function()
			ns.CustomTriggersChanged()
			kit.Changed()
		end })
	local share = kit.At("Name", ns.PanelButton(drawer), kit.shareX)
	share:SetSize(70, 22)
	share:SetText(L["Share"])
	share.searchSkip = true
	share:SetScript("OnClick", function()
		ns.ShowCameraShare(ns.ExportCameraTrigger(id), (L["Share %s"]):format(ns.CustomTriggerLabel(id)))
	end)
	kit.Tooltip(share, L["Text to send a friend: they add this trigger (and the shot it plays) with Import on their " ..
		"Cameras page. Where it may start (its When) stays with you."])
end

-- The New trigger panel, above the Cameras page's rows: a trigger made in
-- it isn't one until Save, which adds it to the rows (where it sorts as the
-- rest do). Cancel drops it. kit: width, Tooltip, onSaved(id), onShown(shown).
-- Gives the panel; panel:Open() starts a fresh draft.
function ns.BuildTriggerDraft(parent, kit)
	local LINE_H, LABEL_W = 34, 62
	local LINES = { "Name", "Camera", "Starts", "Ends", "Buttons" }
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(kit.width, LINE_H * #LINES + 30)
	panel:Hide()
	local back = panel:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.35)
	local edge = panel:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(2)
	edge:SetColorTexture(0.73, 0.89, 0.54, 0.8)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetText(L["New trigger"])

	local data, store = {}, nil
	local own = {} -- (its controls, refreshed together)
	local function RefreshAll() for _, control in ipairs(own) do control:Refresh() end end
	local function At(line, control, x)
		local index = 1
		for i, each in ipairs(LINES) do if each == line then index = i end end
		control:SetPoint("LEFT", panel, "TOPLEFT", x, -(26 + (index - 0.5) * LINE_H))
		return control
	end
	for _, line in ipairs({ "Name", "Camera", "Starts", "Ends" }) do
		local label = At(line, panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), 10)
		label:SetText(({ Name = L["Name"], Camera = L["Camera"], Starts = L["Starts"], Ends = L["Ends"] })[line])
	end

	-- (What it's missing to be saved: a typed kind with nothing typed.)
	local typed -- (the box's text as typed, before it's left)
	local function Ready()
		local k, what = Source(store)
		if HINTS[k] then what = typed or what end
		return not HINTS[k] or (what and what:find("%S")) ~= nil
	end
	local save -- (below)

	local name = At("Name", ns.SkinEditBox(CreateFrame("EditBox", nil, panel, "InputBoxTemplate")), LABEL_W + 16)
	name:SetSize(220, 20)
	name:SetAutoFocus(false)
	name:SetMaxLetters(40)
	local nameHint = name:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	nameHint:SetPoint("LEFT", 2, 0)
	nameHint:SetPoint("RIGHT", -2, 0)
	nameHint:SetJustifyH("LEFT")
	nameHint:SetWordWrap(false)
	name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	name:SetScript("OnEditFocusGained", function() nameHint:Hide() end)
	name:SetScript("OnEditFocusLost", function(self)
		local text = self:GetText():gsub("[%c|]", ""):match("^%s*(.-)%s*$")
		data.name = text ~= "" and text or nil
		nameHint:SetShown(not data.name)
	end)
	name.Refresh = function(self)
		if not self:HasFocus() then self:SetText(data.name or "") end
		nameHint:SetText(ns.DescribeTriggerSource(data.source))
		nameHint:SetShown(not data.name and not self:HasFocus())
	end
	kit.Tooltip(name, L["A name of your own for it, shown on the rows. Empty: what starts it."])
	own[#own + 1] = name

	-- (Its camera: the standing-still ones, or a shot.)
	local camera = At("Camera", Menu(panel, 150, function()
		local list = {}
		for _, value in ipairs(ns.CameraChoiceValues(ns.CUSTOM_TRIGGER_CAMERAS)) do
			list[#list + 1] = { value = value, text = ns.CameraName(value) or tostring(value) }
		end
		if #(ns.ShotList()) < ns.SHOT_MAX then list[#list + 1] = { value = "newshot", text = L["New shot..."] } end
		return list
	end, function() return data.camera end, function(value)
		if value == "newshot" then
			ns.NewShotFor(function(shot) data.camera = shot end)
		else
			data.camera = value
		end
		RefreshAll()
	end), LABEL_W + 4)
	kit.Tooltip(camera, L[ns.CUSTOM_CAMERA_TIP])
	own[#own + 1] = camera
	local function Tick(label, field, x, tip, usable)
		local check = ns.SkinCheck(CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate"))
		check:SetSize(26, 26)
		local text = check.Text or check.text or check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", check, "RIGHT", 2, 0)
		text:SetFontObject("GameFontHighlight")
		text:SetText(label)
		check:SetScript("OnClick", function(self) data[field] = self:GetChecked() and true or nil end)
		check.Refresh = function(self)
			self:SetChecked(data[field] and true or false)
			local on = not usable or usable()
			self:SetEnabled(on)
			self:SetAlpha(on and 1 or 0.4)
		end
		kit.Tooltip(check, tip)
		own[#own + 1] = At("Camera", check, x)
	end
	Tick(L["Music"], "music", LABEL_W + 170, L["Music starts as its camera starts (Audio page)."])
	Tick("CineMode", "cine", LABEL_W + 260, L["With \"Start in CineMode\" off (Cinematic's main page), its camera " ..
		"starting brings CineMode on, and it ends with the camera."], function() return not ns.GetDB().fadeUI end)

	BuildLines(panel, TableStore(data), {
		At = At, Tooltip = kit.Tooltip, x = LABEL_W + 4,
		AddControl = function(control) own[#own + 1] = control end,
		Saved = function()
			typed = nil
			RefreshAll()
		end,
		typing = function(text)
			typed = text
			if save then save:Refresh() end
		end,
	})

	save = At("Buttons", ns.PanelButton(panel), LABEL_W + 4)
	save:SetSize(100, 22)
	save:SetText(L["Save"])
	save.Refresh = function(self) self:SetEnabled(Ready()) end
	kit.Tooltip(save, L["Add it to the rows below, with its When set to anywhere but battlegrounds and arenas, " ..
		"out of fights (open its row to change that)."])
	own[#own + 1] = save
	local cancel = At("Buttons", ns.PanelButton(panel), LABEL_W + 112)
	cancel:SetSize(100, 22)
	cancel:SetText(CANCEL or L["Cancel"])

	function panel:Close()
		self:Hide()
		kit.onShown(false)
	end
	cancel:SetScript("OnClick", function() panel:Close() end)
	save:SetScript("OnClick", function()
		-- (The boxes as they are, even mid-typing.)
		for _, box in ipairs({ name }) do if box:HasFocus() then box:ClearFocus() end end
		for _, control in ipairs(own) do
			if control.HasFocus and control:HasFocus() then control:ClearFocus() end
		end
		if not Ready() then return end
		local id = ns.AddCustomTrigger(data.source, data["until"] or "move", data.camera, data.name)
		if not id then
			ns.Print((L["You have %d triggers of your own already: delete one to make another."]):format(
				ns.CUSTOM_TRIGGER_MAX))
			return
		end
		local rows = ns.GetDB().cameraRows
		rows[id .. ".after"] = data.after
		rows[id .. ".music"] = data.music
		rows[id .. ".cine"] = data.cine
		ns.CustomTriggersChanged()
		panel:Close()
		kit.onSaved(id)
	end)

	-- A name to start with: My Trigger, or My Trigger (1), (2)... where one of
	-- yours has it. (You can still give two the same name.)
	local function NextName()
		local rows, taken = ns.GetDB().cameraRows, {}
		for id in tostring(rows.custom or ""):gmatch("[^,]+") do
			local own = rows[id .. ".name"]
			if type(own) == "string" then taken[own] = true end
		end
		local base = L["My Trigger"]
		if not taken[base] then return base end
		local n = 1
		while taken[("%s (%d)"):format(base, n)] do n = n + 1 end
		return ("%s (%d)"):format(base, n)
	end

	function panel:Open()
		wipe(data)
		data.source, data.camera, data.name = "emote:cheer", "cozy", NextName()
		store, typed = TableStore(data), nil
		self:Show()
		kit.onShown(true)
		RefreshAll()
	end
	store = TableStore(data)
	return panel
end

-- Deleting a built-in trigger (CameraRows' deleted list), once you've said
-- yes: its rows go, and it starts no camera, until Add back.
function ns.ConfirmDeleteBuiltInTrigger(key, name, done)
	if not StaticPopupDialogs.CINEMATIC_DELETE_BUILTIN_TRIGGER then
		StaticPopupDialogs.CINEMATIC_DELETE_BUILTIN_TRIGGER = {
			text = L["Delete the trigger %s? It starts no camera until you bring it back with Add back, above the " ..
				"rows (its settings are kept)."],
			button1 = DELETE or L["Delete"], button2 = CANCEL or L["Cancel"],
			OnAccept = function(_, data) data() end,
			timeout = 0, whileDead = true, hideOnEscape = true,
		}
	end
	StaticPopup_Show("CINEMATIC_DELETE_BUILTIN_TRIGGER", (tostring(name):gsub("|", "")), nil, function()
		ns.SetTriggerDeleted(key, true)
		done()
	end)
end

-- The Add back menu: the built-in triggers you've deleted, one to bring
-- back (or all of them). Shown only while there are any. label(key): a
-- trigger's name; onChanged() after one comes back.
function ns.BuildAddBackMenu(parent, label, onChanged)
	local function Back(key)
		if key == "all" then
			for _, each in ipairs(ns.DeletedTriggers()) do ns.SetTriggerDeleted(each, false) end
		else
			ns.SetTriggerDeleted(key, false)
		end
		onChanged()
	end
	local ok, menu = ns.MenuDropdown(parent)
	if ok and menu and menu.SetupMenu then
		menu:SetWidth(120)
		if menu.SetDefaultText then menu:SetDefaultText(L["Add back"]) end
		menu:SetupMenu(function(_, root)
			for _, key in ipairs(ns.DeletedTriggers()) do
				root:CreateButton(label(key), function() Back(key) end)
			end
			if #ns.DeletedTriggers() > 1 then root:CreateButton(L["All of them"], function() Back("all") end) end
		end)
		menu.Refresh = function(self)
			self:SetShown(#ns.DeletedTriggers() > 0)
			self:GenerateMenu()
		end
	else
		-- (No modern dropdown: one button brings them all back.)
		menu = ns.PanelButton(parent)
		menu:SetSize(120, 22)
		menu:SetText(L["Add back all"])
		menu:SetScript("OnClick", function() Back("all") end)
		menu.Refresh = function(self) self:SetShown(#ns.DeletedTriggers() > 0) end
	end
	menu.searchSkip = true
	return menu
end

-- Deleting a trigger of your own, once you've said yes.
function ns.ConfirmRemoveCustomTrigger(id, done)
	if not StaticPopupDialogs.CINEMATIC_REMOVE_CAMERA_TRIGGER then
		StaticPopupDialogs.CINEMATIC_REMOVE_CAMERA_TRIGGER = {
			text = L["Delete the trigger %s and its settings?"],
			button1 = DELETE or L["Delete"], button2 = CANCEL or L["Cancel"],
			OnAccept = function(_, data) data() end,
			timeout = 0, whileDead = true, hideOnEscape = true,
		}
	end
	local name = tostring(ns.CustomTriggerLabel(id)):gsub("|", "")
	StaticPopup_Show("CINEMATIC_REMOVE_CAMERA_TRIGGER", name, nil, function()
		ns.RemoveCustomTrigger(id)
		done()
	end)
end

-- The share window: a trigger's or shot's text to copy, or a box to paste
-- one into, with what it holds shown before it's added.
local window
local WHY = {
	newer = "This is from a newer Cinematic: update it to add this one.",
	other = "That isn't a camera trigger or shot: profiles go on the Profiles page, wheels on Your wheels.",
	broken = "That isn't all of it: copy it again, every letter.",
	full = "No room for it: delete a trigger or shot first.",
}
local function Window()
	if window then return window end
	window = CreateFrame("Frame", "CinematicCameraShareWindow", UIParent,
		BackdropTemplateMixin and "BackdropTemplate" or nil)
	window:SetSize(480, 300)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	if window.SetBackdrop then
		window:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 } })
	end
	if ns.SkinWindow then ns.SkinWindow(window) end
	tinsert(UISpecialFrames, "CinematicCameraShareWindow")
	window:Hide()

	window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	window.title:SetPoint("TOPLEFT", 18, -16)
	window.title:SetPoint("RIGHT", -18, 0)
	window.title:SetJustifyH("LEFT")
	window.hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.hint:SetPoint("TOPLEFT", window.title, "BOTTOMLEFT", 0, -6)
	window.hint:SetPoint("RIGHT", -18, 0)
	window.hint:SetJustifyH("LEFT")

	local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
	if ns.SkinScroll then ns.SkinScroll(scroll) end
	scroll:SetPoint("TOPLEFT", 18, -70)
	scroll:SetPoint("RIGHT", -40, 0)
	scroll:SetHeight(80)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(420)
	scroll:SetScrollChild(box)
	box:SetScript("OnEscapePressed", function() window:Hide() end)
	window.box = box

	window.review = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.review:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -10)
	window.review:SetPoint("RIGHT", -18, 0)
	window.review:SetJustifyH("LEFT")
	window.review:SetSpacing(3)

	local close = ns.PanelButton(window)
	close:SetSize(90, 22)
	close:SetPoint("BOTTOMRIGHT", -16, 14)
	close:SetText(CLOSE or L["Close"])
	close:SetScript("OnClick", function() window:Hide() end)
	local action = ns.PanelButton(window)
	action:SetSize(110, 22)
	action:SetPoint("RIGHT", close, "LEFT", -8, 0)
	window.action = action

	box:SetScript("OnTextChanged", function(self, userInput)
		if window.mode == "export" then
			if userInput then
				self:SetText(window.text)
				self:HighlightText()
			end
			return
		end
		-- (Another page's thing to import: its reader, ns.ShowShareImport.)
		local reader = window.reader
		if reader then
			local info, why = reader.read(self:GetText())
			window.info = info
			action:SetEnabled(info ~= nil)
			window.review:SetText(info and reader.describe(info) or why or "")
			return
		end
		local info, why = ns.ReadCameraShare(self:GetText())
		window.info = info
		action:SetEnabled(info ~= nil)
		if not info then
			window.review:SetText(why and WHY[why] and L[WHY[why]] or "")
			return
		end
		local function Safe(text) return (tostring(text or ""):gsub("|", "||")) end
		local lines = {}
		if info.kind == "shot" then
			lines[1] = ("|cffffd100%s|r %s"):format(L["Shot:"], Safe(info.name or ""))
			lines[2] = (L["Camera: %s"]):format(ns.CAMERA_NAMES[info.base] or info.base)
		else
			lines[1] = ("|cffffd100%s|r %s"):format(L["Trigger:"], Safe(info.name or ns.DescribeTriggerSource(info.source)))
			lines[2] = (L["Starts: %s"]):format(Safe(ns.DescribeTriggerSource(info.source)))
			lines[3] = (L["Camera: %s"]):format(info.shot and (L["%s (a shot of its own, added too)"]):format(
				Safe(info.shot.name or ns.CAMERA_NAMES[info.shot.base])) or ns.CAMERA_NAMES[info.camera] or info.camera)
		end
		window.review:SetText(table.concat(lines, "\n"))
	end)
	action:SetScript("OnClick", function()
		if window.mode == "export" then
			box:SetFocus()
			box:HighlightText()
			return
		end
		if not window.info then return end
		if window.reader then
			local done, why = window.reader.add(window.info)
			if done then window:Hide() else window.review:SetText(why or "") end
			return
		end
		local id, why = ns.AddCameraShare(window.info)
		if not id then
			window.review:SetText(L[WHY[why or "full"]])
			return
		end
		window:Hide()
		if window.onAdded then window.onAdded(id, window.info.kind) end
	end)
	return window
end

function ns.ShowCameraShare(text, title)
	local w = Window()
	w.mode, w.text, w.info = "export", text, nil
	w.title:SetText(title)
	w.hint:SetText(L["Press Ctrl+C to copy this, then paste it wherever your friend will see it."])
	w.review:SetText("")
	w.action:SetText(L["Select all"])
	w.action:SetEnabled(true)
	w:Show()
	w.box:SetText(text)
	w.box:SetFocus()
	w.box:HighlightText()
end

-- onAdded(id, kind): what was added ("trigger" or "shot").
function ns.ShowCameraImport(onAdded)
	local w = Window()
	w.mode, w.text, w.info, w.onAdded, w.reader = "import", nil, nil, onAdded, nil
	w.title:SetText(L["Import a trigger or shot"])
	w.hint:SetText(L["Paste the text a friend sent (Ctrl+V). What it holds shows below before you add it."])
	w.review:SetText("")
	w.action:SetText(L["Add it"])
	w.action:SetEnabled(false)
	w:Show()
	w.box:SetText("")
	w.box:SetFocus()
end

-- The same window for another page's shared thing. reader: read(text) ->
-- info or nil and why (text); describe(info) -> what it holds (text);
-- add(info) -> true, or nil and why.
function ns.ShowShareImport(title, reader)
	local w = Window()
	w.mode, w.text, w.info, w.onAdded, w.reader = "import", nil, nil, nil, reader
	w.title:SetText(title)
	w.hint:SetText(L["Paste the text a friend sent (Ctrl+V). What it holds shows below before you add it."])
	w.review:SetText("")
	w.action:SetText(L["Add it"])
	w.action:SetEnabled(false)
	w:Show()
	w.box:SetText("")
	w.box:SetFocus()
end
