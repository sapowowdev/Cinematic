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

local function Rows() return ns.GetDB().cameraRows end
local function Source(id)
	local kind, what = tostring(Rows()[id .. ".source"] or ""):match("^(%a+):(.*)$")
	return kind or "emote", what or ""
end
local function SetSource(id, kind, what)
	Rows()[id .. ".source"] = kind .. ":" .. what
end
local function UntilKind(id)
	local text = Rows()[id .. ".until"]
	if type(text) == "string" and text:find("^time:") then return "time" end
	return type(text) == "string" and text or "move"
end
local function Seconds(id)
	return tonumber(tostring(Rows()[id .. ".until"] or ""):match("^time:(%d+)")) or 5
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

local function UntilChoices(id)
	local kind = Source(id)
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

-- The drawer's Starts and Ends lines for trigger id, and a Share button
-- on its Name line. kit: At(line, control, x), Changed(), Tooltip, AddControl,
-- x (where the lines' controls start).
function ns.BuildCustomTriggerLines(drawer, id, kit)
	local At, Tooltip, AddControl, x = kit.At, kit.Tooltip, kit.AddControl, kit.x
	MakeChoices()
	local function Saved()
		ns.CustomTriggersChanged()
		kit.Changed()
	end

	-- Starts: the kind, then what (typed, or picked from its list).
	local kind = At("Starts", Menu(drawer, 130, ns.CUSTOM_TRIGGER_KINDS, function() return (Source(id)) end,
		function(value)
			local start = KIND_START[value] or KIND_START.emote
			SetSource(id, value, value == "place" and CurrentPlace() or start[1])
			Rows()[id .. ".until"] = start[2] ~= "move" and start[2] or nil
			Saved()
		end), x)
	Tooltip(kind, L["What starts this trigger's camera: an emote you do, a spell you cast, a buff on you, a place " ..
		"you're in, a moment (leveling up...), something you are (mounted...), or a key you press."])
	AddControl(kind)

	local function Typed() local k = Source(id) return HINTS[k] ~= nil end
	local box = At("Starts", ns.SkinEditBox(CreateFrame("EditBox", nil, drawer, "InputBoxTemplate")), x + 146)
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
		local k = Source(id)
		if k == "emote" then text = ns.EmoteToken(text) end
		SetSource(id, k, text)
		hint:SetShown(text == "")
		Saved()
	end
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusLost", SaveBox)
	box:SetScript("OnEditFocusGained", function() hint:Hide() end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(select(2, Source(id)))
		self:ClearFocus()
	end)
	box.Refresh = function(self)
		if self:HasFocus() then return end
		local k, what = Source(id)
		self:SetText(what)
		hint:SetText(L[HINTS[k] or ""])
		hint:SetShown(what == "")
	end
	ShownWhile(box, Typed)
	Tooltip(box, L["Emotes: the command, with or without its slash. Spells and buffs: the name in your game " ..
		"language, or a spell ID (works in any language). Places: the zone or subzone name as the game shows it."])
	AddControl(box)

	local function Fixed()
		local k = Source(id)
		return k == "moment" and ns.CUSTOM_TRIGGER_MOMENTS or k == "state" and ns.CUSTOM_TRIGGER_STATES
			or k == "key" and ns.CUSTOM_TRIGGER_KEYS or nil
	end
	local pick = At("Starts", Menu(drawer, 200, function() return Fixed() or {} end,
		function() return (select(2, Source(id))) end,
		function(value)
			SetSource(id, (Source(id)), value)
			Saved()
		end), x + 140)
	ShownWhile(pick, Fixed)
	Tooltip(pick, L["Which one. Key bindings are set in the game's Key Bindings, under Cinematic."])
	AddControl(pick)

	local here = At("Starts", ns.PanelButton(drawer), x + 344)
	here:SetSize(60, 22)
	here:SetText(L["Here"])
	here.searchSkip = true
	here:SetScript("OnClick", function()
		SetSource(id, "place", CurrentPlace())
		Saved()
	end)
	ShownWhile(here, function() return Source(id) == "place" end)
	Tooltip(here, L["Fill in the subzone you're in now (or the zone, where there's no subzone)."])
	AddControl(here)

	-- Ends: until when, how long, and its place in the priority list.
	local untilMenu = At("Ends", Menu(drawer, 150, function() return UntilChoices(id) end,
		function() return UntilKind(id) end,
		function(value)
			Rows()[id .. ".until"] = value == "time" and ("time:" .. Seconds(id)) or (value ~= "move" and value or nil)
			Saved()
		end), x)
	Tooltip(untilMenu, L["When its camera stops. Moving always stops it too, as it does every camera that runs " ..
		"while you stand still."])
	AddControl(untilMenu)

	local seconds = At("Ends", Menu(drawer, 80, SECOND_CHOICES, function() return Seconds(id) end,
		function(value)
			Rows()[id .. ".until"] = "time:" .. value
			Saved()
		end), x + 160)
	ShownWhile(seconds, function() return UntilKind(id) == "time" end)
	Tooltip(seconds, L["How long its camera runs."])
	AddControl(seconds)

	local after = At("Ends", Menu(drawer, 210, AFTER_CHOICES,
		function()
			local value = Rows()[id .. ".after"]
			return value == nil and "emote" or value
		end,
		function(value)
			Rows()[id .. ".after"] = value ~= "emote" and value or nil
			Saved()
		end), x + 250)
	Tooltip(after, L["Where it comes when other triggers are on at the same time: the first one on in this " ..
		"order plays. Going AFK while doing an emote is the AFK camera, say."])
	AddControl(after)

	-- (Share, on the Name line.)
	local share = At("Name", ns.PanelButton(drawer), kit.shareX)
	share:SetSize(70, 22)
	share:SetText(L["Share"])
	share.searchSkip = true
	share:SetScript("OnClick", function()
		ns.ShowCameraShare(ns.ExportCameraTrigger(id), (L["Share %s"]):format(ns.CustomTriggerLabel(id)))
	end)
	Tooltip(share, L["Text to send a friend: they add this trigger (and the shot it plays) with Import on their " ..
		"Cameras page. Where it may start (its When) stays with you."])
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
	w.mode, w.text, w.info, w.onAdded = "import", nil, nil, onAdded
	w.title:SetText(L["Import a trigger or shot"])
	w.hint:SetText(L["Paste the text a friend sent (Ctrl+V). What it holds shows below before you add it."])
	w.review:SetText("")
	w.action:SetText(L["Add it"])
	w.action:SetEnabled(false)
	w:Show()
	w.box:SetText("")
	w.box:SetFocus()
end
