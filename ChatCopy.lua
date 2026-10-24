-- Cinematic: copying chat. A small icon in the bottom right of each chat
-- window (while the mouse is over it) opens that window's lines as text, to
-- select and copy with Ctrl+C. Addons can't put text on the clipboard, so a
-- box to copy from is as close as it gets (chatCopyButton, Quality of life).
local ADDON_NAME, ns = ...
local L = ns.L

local BUTTON_SIZE = 16
local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Quill" -- (Media/make_quill.py)
local CHECK_INTERVAL = 0.1
local buttons = {} -- [chat frame] = its copy button
local window
local rawView -- /cine debug chatcopy: the window shows each line's codes as text

function ns.ToggleChatCopyRaw()
	rawView = not rawView
	return rawView
end

local function Readable(text)
	return type(text) == "string" and not (issecretvalue and issecretvalue(text))
end

local function Number(value)
	return type(value) == "number" and value or nil
end

local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

-- Retail's named colours (|cnIQ4: an item quality, |cnNAME_COLOR: a global
-- colour) as plain colour codes, which a text box shows.
local function NamedColour(name)
	local quality = tonumber(name:match("^IQ(%d+)$") or "")
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or _G[name]
	if type(color) == "table" and Number(color.r) and Number(color.g) and Number(color.b) then
		return Hex(color.r, color.g, color.b)
	end
	return ""
end

-- A chat line without its links, icons and protected Battle.net names
-- (which can't be copied); links keep their shown text.
local function Strip(text)
	text = text:gsub("|T.-|t", "")
		:gsub("|A.-|a", "")
		:gsub("|K.-|k", "?")
		:gsub("|H.-|h(.-)|h", "%1")
		:gsub("|cn([^:]*):", NamedColour)
	return text
end

-- The line in its chat colour, keeping coloured bits (class-coloured names,
-- links) inside it; their |r goes back to the line's colour, as it does in
-- chat. Colours stack in text and too many stop showing, so only one is open
-- at a time: each coloured bit closes the line's colour first.
local function Coloured(text, r, g, b)
	local colour = Hex(r, g, b)
	text = text:gsub("|c(%x%x%x%x%x%x%x%x)", "\001%1")
		:gsub("|r", "|r" .. colour)
		:gsub("\001(%x%x%x%x%x%x%x%x)", "|r|c%1")
	return colour .. text .. "|r"
end

-- Types the chat settings show as one: your side of a whisper, leaders' lines.
local SAME_TYPE = {
	WHISPER_INFORM = "WHISPER", BN_WHISPER_INFORM = "BN_WHISPER",
	PARTY_LEADER = "PARTY", RAID_LEADER = "RAID", INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
}
local OTHER = "OTHER" -- lines without a chat type (addons' prints)

-- A chat line's type ("SAY", "CHANNEL6"...): chat adds a line with its
-- ChatTypeInfo id and event after the colour. A channel line read as just
-- CHANNEL takes its number from the "[6. Trade]" at its start.
local function LineType(idToType, id, event, plain)
	local chatType = idToType[Number(id) or false]
	if not chatType and Readable(event) then
		chatType = event:match("^CHAT_MSG_(.+)")
	end
	chatType = chatType or OTHER
	if chatType == "CHANNEL" then
		local number = plain:match("%[(%d+)%. ")
		chatType = number and "CHANNEL" .. number or chatType
	end
	return SAME_TYPE[chatType] or chatType
end

-- A type's name for the dropdown: a channel's own name ("6. Trade - City"),
-- the chat settings' name, or the type spelled out.
local function TypeName(chatType)
	if chatType == OTHER then
		return L["Other"]
	end
	local number = chatType:match("^CHANNEL(%d+)$")
	if number then
		local _, name = GetChannelName(tonumber(number))
		return number .. ". " .. (Readable(name) and name ~= "" and name or CHANNEL or "Channel")
	end
	local name = _G["CHAT_MSG_" .. chatType]
	if Readable(name) and name ~= "" then
		return name
	end
	return (chatType:lower():gsub("_", " "):gsub("^%l", string.upper))
end

-- Each line as { plain, coloured, type }.
local function ChatLines(chatFrame)
	local idToType = {}
	for chatType, info in pairs(ChatTypeInfo or {}) do
		if type(info) == "table" and Number(info.id) then
			idToType[info.id] = chatType
		end
	end
	local lines = {}
	for i = 1, chatFrame:GetNumMessages() do
		local text, r, g, b, id, _, _, event = chatFrame:GetMessageInfo(i)
		if Readable(text) then
			local raw = text
			text = Strip(text)
			local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			r, g, b = Number(r), Number(g), Number(b)
			local line = {
				plain = plain,
				coloured = r and g and b and Coloured(text, r, g, b) or plain,
				type = LineType(idToType, id, event, plain),
			}
			if rawView then
				-- (|| shows a code as text rather than using it)
				line.raw = ("%s  {id %s, event %s, colour %s}"):format(raw:gsub("|", "||"),
					tostring(id), Readable(event) and event or "?",
					r and g and b and Hex(r, g, b):sub(3) or "none")
			end
			lines[#lines + 1] = line
		end
	end
	return lines
end

-- The dropdown's choices: All, then each type in the lines (with how many),
-- by name.
local function TypeChoices(lines)
	local counts, choices = {}, {}
	for _, line in ipairs(lines) do
		if not counts[line.type] then
			choices[#choices + 1] = { value = line.type, name = TypeName(line.type) }
		end
		counts[line.type] = (counts[line.type] or 0) + 1
	end
	table.sort(choices, function(a, b) return a.name < b.name end)
	for _, choice in ipairs(choices) do
		choice.text = ("%s (%d)"):format(choice.name, counts[choice.value])
	end
	table.insert(choices, 1, { text = ("%s (%d)"):format(L["All"], #lines) })
	return choices
end

-- The lines of the type picked (nil: all), as one text.
local function Shown(lines, chatType, colours)
	local shown = {}
	for _, line in ipairs(lines) do
		if not chatType or line.type == chatType then
			shown[#shown + 1] = line.raw or colours and line.coloured or line.plain
		end
	end
	return table.concat(shown, "\n")
end

-- Fills the box from the lines, the type picked and the Colours tick,
-- scrolled to the newest.
local function Refresh()
	window.text = Shown(window.lines or {}, window.chatType, ns.Setting("chatCopyColours"))
	window.box:SetText(window.text)
	C_Timer.After(0, function()
		window.scroll:SetVerticalScroll(window.scroll:GetVerticalScrollRange())
	end)
end

local function CreateWindow()
	window = CreateFrame("Frame", "CinematicChatCopyWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetSize(620, 400)
	window:SetPoint("CENTER", 0, 40)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	tinsert(UISpecialFrames, "CinematicChatCopyWindow") -- Escape closes it

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	window.title = title

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	hint:SetPoint("RIGHT", window, "RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText(L["Drag over the lines you want (or Select all), then press Ctrl+C to copy them."])

	local holder = CreateFrame("Frame", nil, window, BackdropTemplateMixin and "BackdropTemplate")
	holder:SetPoint("TOPLEFT", 14, -56)
	holder:SetPoint("BOTTOMRIGHT", -14, 44)
	holder:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	holder:SetBackdropColor(0, 0, 0, 0.6)
	local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(550)
	box:SetScript("OnEscapePressed", function() window:Hide() end)
	-- Read-only: any typing puts the text back.
	box:SetScript("OnTextChanged", function(self, user)
		if user then
			self:SetText(window.text)
		end
	end)
	scroll:SetScrollChild(box)
	scroll:SetScript("OnSizeChanged", function(_, width) box:SetWidth(width) end)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	window.box, window.scroll = box, scroll

	local selectAll = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	selectAll:SetSize(110, 22)
	selectAll:SetPoint("BOTTOMRIGHT", -16, 14)
	selectAll:SetText(L["Select all"])
	selectAll:SetScript("OnClick", function()
		box:SetFocus()
		box:HighlightText()
	end)

	-- Colours: copying keeps the colour codes, so untick it for plain text.
	local colours = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
	colours:SetSize(24, 24)
	colours:SetPoint("RIGHT", selectAll, "LEFT", -76, 0)
	local coloursLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	coloursLabel:SetPoint("LEFT", colours, "RIGHT", 2, 0)
	coloursLabel:SetText(L["Colours"])
	colours:SetScript("OnClick", function(self)
		ns.db.chatCopyColours = self:GetChecked() and true or false
		Refresh()
	end)
	colours:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L["Colours"])
		GameTooltip:AddLine(L["Shows the lines in their chat colours. Copied text keeps the colour codes, so untick this to copy plain text."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	colours:SetScript("OnLeave", GameTooltip_Hide)
	window.colours = colours

	-- Show: only the lines of one type, from the types in the window now
	-- (none on clients without the modern dropdown).
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, window, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		local label = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("BOTTOMLEFT", 18, 19)
		label:SetText(L["Show:"])
		dropdown:SetWidth(240)
		dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
		dropdown:SetupMenu(function(_, rootDescription)
			for _, choice in ipairs(TypeChoices(window.lines or {})) do
				rootDescription:CreateRadio(choice.text,
					function() return window.chatType == choice.value end,
					function()
						window.chatType = choice.value
						Refresh()
					end)
			end
		end)
		window.dropdown = dropdown
	end
end

-- Opens a chat window's lines, scrolled to the newest, all selected.
local function ShowCopy(chatFrame)
	if not window then CreateWindow() end
	local name = chatFrame.name
	if not Readable(name) and FCF_GetChatWindowInfo and chatFrame.GetID then
		name = FCF_GetChatWindowInfo(chatFrame:GetID())
	end
	window.title:SetText(Readable(name) and name ~= "" and L["Copy chat: %s"]:format(name) or L["Copy chat"])
	window.lines = ChatLines(chatFrame)
	window.chatType = nil -- each opening starts on All
	if window.dropdown then window.dropdown:GenerateMenu() end
	window.colours:SetChecked(ns.Setting("chatCopyColours") and true or false)
	window:Show()
	Refresh()
	window.box:SetFocus()
	window.box:HighlightText()
end

local function CreateButton(chatFrame)
	local button = CreateFrame("Button", nil, chatFrame)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameLevel(chatFrame:GetFrameLevel() + 10)
	button:SetNormalTexture(ICON)
	button:SetPushedTexture(ICON)
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
	button:SetScript("OnClick", function() ShowCopy(chatFrame) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L["Copy chat"])
		GameTooltip:AddLine(L["Opens this chat window's lines to copy."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	buttons[chatFrame] = button
	return button
end

-- Bottom right, left of the scroll-to-bottom arrow while that's up.
local function PlaceButton(button, chatFrame)
	local arrow = chatFrame.ScrollToBottomButton
	local anchor = arrow and ns.Flag(arrow:IsShown()) and arrow or nil
	if button.anchor == anchor and button.placed then
		return
	end
	button.anchor, button.placed = anchor, true
	button:ClearAllPoints()
	if anchor then
		button:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
	else
		button:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -2, 2)
	end
end

-- Each chat window's button shows while the mouse is over the window (new
-- whisper windows get one when they first open).
local function Update(enabled)
	for _, frameName in ipairs(CHAT_FRAMES or {}) do
		local chatFrame = _G[frameName]
		if chatFrame and chatFrame.GetMessageInfo then
			local button = buttons[chatFrame]
			local show = enabled and ns.Flag(chatFrame:IsVisible())
				and (ns.Flag(chatFrame:IsMouseOver()) or button and ns.Flag(button:IsMouseOver()))
			if show then
				button = button or CreateButton(chatFrame)
				PlaceButton(button, chatFrame)
			end
			if button and button:IsShown() ~= (show and true or false) then
				button:SetShown(show)
			end
		end
	end
end

local watcher = CreateFrame("Frame")
local sinceCheck = 0
watcher:SetScript("OnUpdate", ns.Profiled("Chat copy button", function(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck < CHECK_INTERVAL then
		return
	end
	sinceCheck = 0
	Update(ns.Setting("chatCopyButton"))
end))
