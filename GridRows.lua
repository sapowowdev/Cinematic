-- The frames tables' rows as dropdowns (Options.lua's ShowTable: Standard
-- Frames, Gamepad, Chat): an Always box, a dropdown of the fights and one
-- of the places (each ticked item shows the row: all joined by OR, as the
-- columns were), the roles and an Edit button. The ticks are the lists the
-- columns always were (combatShow, worldShow...), so saved settings and
-- profiles are as they were. Edit shows the row as a rule (db.frameRules,
-- ns.CompileRule) in the rule editor here: one still just the dropdowns'
-- words joined by OR goes back into them as it closes; one with more (AND,
-- NOT, other words) is the row's rule, shown in its place, its words in
-- their groups' colours.

local _, ns = ...
local L = ns.L

-- A tip on hover (the widget's own OnEnter and OnLeave).
local function Tip(widget, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(type(text) == "function" and text() or text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function Colored(color, text)
	return ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, text)
end

-- The pieces of a rule, a line of buttons each in the rule editor:
-- { name, colour, { { word, label }... } }. Made when asked,
-- once the language is known.
function ns.RulePieces()
	local location = { { "world", L["Open World"] }, { "city", L["Cities"] }, { "inn", L["Inns"] },
		{ "bg", L["BGs & Arenas"] } }
	if ns.isRetail then -- (apart where there are arenas)
		location[#location + 1] = { "battleground", L["Battlegrounds"] }
		location[#location + 1] = { "arena", L["Arenas"] }
	end
	for _, piece in ipairs({ { "instance", L["Instances"] }, { "dungeon", L["Dungeons"] }, { "raid", L["Raids"] } }) do
		location[#location + 1] = piece
	end
	-- (Spell range's bands, Frames.lua: * as the yards go by your class.)
	local ranges = {}
	for _, band in ipairs(ns.RANGE_BANDS) do
		ranges[#ranges + 1] = { band.field, band.label .. "*" }
	end
	-- (The classes this client has, by the game's names for them.)
	local classes = {}
	for id = 1, (GetNumClasses and GetNumClasses() or 0) do
		local name, file = GetClassInfo(id)
		if name and file and ns.RULE_WORDS[file:lower()] then
			classes[#classes + 1] = { file:lower(), name }
		end
	end
	return {
		{ L["Logic"], { 1, 1, 1 }, { { "and", "AND" }, { "or", "OR" }, { "not", "NOT" }, { "(", "(" }, { ")", ")" } } },
		{ L["Combat"], { 1, 0.45, 0.4 }, { { "combat", L["In combat"] }, { "calm", L["Calm Timer"] },
			{ "nocombat", L["Out of combat"] }, { "camera", L["In a camera mode"] },
			{ "entering", L["Entering combat"] }, { "leaving", L["Leaving combat"] }, { "boss", L["Boss fight"] } } },
		{ L["Target"], { 1, 0.65, 0.25 }, { { "enemy", L["Enemy targeted"] }, { "friendly", L["Friend targeted"] },
			{ "target", L["Anything targeted"] }, { "targetself", L["You"] }, { "enemyplayer", L["Enemy Players"] },
			{ "hostilenpc", L["Hostile NPCs"] }, { "neutralplayer", L["Neutral Players"] },
			{ "neutralnpc", L["Neutral NPCs"] }, { "friendlyplayer", L["Friendly Players"] },
			{ "friendlynpc", L["Friendly NPCs"] }, { "noplate", L["Plate off screen"] }, { "near", L["Near (11 yards)"] }, { "near28", L["Near (28 yards)"] } } },
		{ L["Spell range"], { 0.45, 0.9, 0.9 }, ranges },
		{ L["Nearby"], { 1, 0.5, 0.8 }, { { "elite11", L["Elite near (11 yards)"] },
			{ "elite28", L["Elite near (28 yards)"] }, { "elite40", L["Elite near (40 yards)"] } } },
		{ L["Location"], { 0.45, 0.75, 1 }, location },
		{ L["You"], { 0.8, 0.6, 1 }, { { "mounted", L["Mounted"] }, { "flagged", L["PvP flagged"] },
			{ "group", L["Grouped"] }, { "cinemode", L["In CineMode"] } } },
		{ L["Role"], { 0.4, 0.85, 0.5 }, { { "tank", L["Tank"] }, { "healer", L["Healer"] }, { "damage", L["Damage"] } } },
		{ L["Class"], { 0.85, 0.75, 0.6 }, classes },
		-- (Last: the editor shows it only for the Tooltips row, tooltip:All.)
		{ L["Tooltip"], { 0.95, 0.95, 0.6 }, { { "tipenemy", L["Enemy"] }, { "tipfriendly", L["Friendly"] },
			{ "tipgather", L["Gatherable"] }, { "tipquest", L["Quest objective"] }, { "tipother", L["Anything else"] } },
			tooltipOnly = true },
	}
end

-- Each situation's colour (a field of the rules' facts: aliases share it).
local fieldColor
local function FieldColor(field)
	if not fieldColor then
		fieldColor = { always = { 1, 0.82, 0 }, never = { 1, 0.82, 0 } }
		for _, group in ipairs(ns.RulePieces()) do
			for _, piece in ipairs(group[3]) do
				local field = ns.RULE_WORDS[piece[1]]
				if field then fieldColor[field] = group[2] end
			end
		end
	end
	return fieldColor[field]
end
local LOGIC_COLOR, UNKNOWN_COLOR = { 0.7, 0.7, 0.7 }, { 1, 0.38, 0.38 }

-- A rule's text with each word in its group's colour (one the rules don't
-- know red), the logic grey, for showing.
function ns.ColoredRule(text)
	-- (A word, then what's up to the next: spaces, brackets and signs, a | doubled to show as one.)
	return (text:gsub("([%w_]*)([^%w_]*)", function(word, between)
		local lower = word:lower()
		local color = (lower == "and" or lower == "or" or lower == "not") and LOGIC_COLOR
			or FieldColor(ns.RULE_WORDS[lower]) or UNKNOWN_COLOR
		word = word ~= "" and Colored(color, word) or ""
		between = between:find("%S") and Colored(LOGIC_COLOR, (between:gsub("|", "||"))) or between
		return word .. between
	end))
end

-- A row's ticks as a rule: the ticked words joined by OR, always first
-- with Always on (the rest kept, for when it's off again); never with none.
function ns.GridRule(always, words)
	local text = table.concat(words, " or ")
	if always then return text ~= "" and "always or " .. text or "always" end
	return text ~= "" and text or "never"
end

-- A rule read back into a row: words joined by OR, each one of the grid's
-- (grid: field -> true; target is enemy and friendly both), brackets
-- allowed. Gives always, and the fields ticked (field -> true); or nil and why not.
function ns.ReadGridRule(text, grid)
	local always, ticked, n = false, {}, 0
	local i = 1
	while i <= #text do
		local c = text:sub(i, i)
		if c:find("[%s()]") then
			i = i + 1
		else
			local token = text:match("^[%w_]+", i) or text:match("^[&|!]+", i)
			if not token then return nil, (L["can't read \"%s\""]):format(c) end
			i = i + #token
			local lower = token:lower()
			if lower == "and" or lower == "not" or token:find("^[&!]") then
				return nil, L["the dropdowns only join with OR"]
			end
			-- (Words and ORs take turns, a word first and last.)
			n = n + 1
			local isOr = lower == "or" or lower:find("^|+$") ~= nil
			if (n % 2 == 1) == isOr then return nil, L["it isn't finished"] end
			if not isOr then
				local field = ns.RULE_WORDS[lower]
				if not field then
					return nil, (L["\"%s\" isn't a word it knows"]):format(token)
				elseif field == "always" then
					always = true
				elseif field == "target" and grid.enemy and grid.friendly then
					ticked.enemy, ticked.friendly = true, true
				elseif field ~= "never" then
					if not grid[field] then return nil, (L["\"%s\" isn't in the dropdowns"]):format(token) end
					ticked[field] = true
				end
			end
		end
	end
	if n == 0 then return false, ticked end -- (blank: nothing ticked, so never)
	if n % 2 == 0 then return nil, L["it isn't finished"] end
	-- (Brackets matched, or the rules can't read it either.)
	local _, err = ns.CompileRule(text)
	if err then return nil, err end
	return always, ticked
end

-- A button with a down arrow at its right (in both menu looks), small text
-- at the left: what a dropdown has ticked. The arrow greys while disabled.
function ns.GridMenuButton(parent, width)
	local button = ns.PanelButton(parent)
	button:SetSize(width, 20)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetWordWrap(false)
	button:SetFontString(text)
	button:SetNormalFontObject("GameFontHighlightSmall")
	button:SetDisabledFontObject("GameFontDisableSmall")
	text:ClearAllPoints()
	text:SetPoint("LEFT", 6, 0)
	text:SetPoint("RIGHT", -16, 0)
	text:SetJustifyH("LEFT")
	local arrow = button:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(14, 14)
	arrow:SetPoint("RIGHT", -2, -2)
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	button:HookScript("OnDisable", function() arrow:SetDesaturated(true) arrow:SetAlpha(0.4) end)
	button:HookScript("OnEnable", function() arrow:SetDesaturated(false) arrow:SetAlpha(1) end)
	return button
end

-- A menu of entries ({ text, isOn(), toggle(), enabled() or nil, tip or nil })
-- under owner, with All (or Clear, once all are ticked) at the top, unless
-- plain; kept open for ticking more. changed(): after any tick. Nil where
-- the client has no menus (MenuUtil): ns.GRID_MENUS says so.
ns.GRID_MENUS = MenuUtil and MenuUtil.CreateContextMenu and true or false
function ns.TickMenu(owner, entries, changed, plain)
	if not ns.GRID_MENUS then return end
	local keep = MenuResponse and MenuResponse.Refresh
	local function Usable(entry) return not entry[4] or entry[4]() end
	local function AllOn()
		for _, entry in ipairs(entries) do
			if Usable(entry) and not entry[2]() then return false end
		end
		return true
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		if not plain then
			local top = root:CreateButton(AllOn() and L["Clear"] or L["All"], function()
				local on = not AllOn()
				for _, entry in ipairs(entries) do
					if Usable(entry) and entry[2]() ~= on then entry[3]() end
				end
				changed()
				return keep
			end)
			-- (Its text again each time the menu refreshes, as ticks change it.)
			if top and top.AddInitializer then
				top:AddInitializer(function(button)
					local text = button.fontString or (button.GetFontString and button:GetFontString())
					if text then text:SetText(AllOn() and L["Clear"] or L["All"]) end
				end)
			end
			root:CreateDivider()
		end
		for _, entry in ipairs(entries) do
			local box = root:CreateCheckbox(entry[1], entry[2], function()
				entry[3]()
				changed()
				return keep
			end)
			if box and entry[4] and box.SetEnabled then box:SetEnabled(entry[4]()) end
			if box and entry[5] and box.SetTooltip then
				box:SetTooltip(function(tooltip) tooltip:AddLine(entry[5], 1, 1, 1, true) end)
			end
		end
	end)
end

-- The rule editor: one window, for one row at a time. target: { label, the
-- row's name; Text(), its rule now (the ticks' while it has none);
-- SetText(text), as it's typed; Close(text), as it closes (back into the
-- dropdowns if it reads, else kept as the row's rule); ResetToGrid(), drop
-- the rule for the ticks it had; grid, the words its dropdowns hold: nil for
-- a row without (a nameplate row, a unit frame part), whose rule just stays }.
-- Built the first time.
local editor, target
local EDIT_W = 560

local function BuildEditor()
	local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
	editor = CreateFrame("Frame", "CinematicRuleEditor", UIParent, BACKDROP)
	editor:SetWidth(EDIT_W)
	if editor.SetBackdrop then
		editor:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
	end
	ns.SkinWindow(editor)
	editor:SetPoint("CENTER")
	editor:SetFrameStrata("DIALOG")
	editor:SetToplevel(true)
	editor:SetClampedToScreen(true)
	editor:EnableMouse(true)
	editor:SetMovable(true)
	editor:RegisterForDrag("LeftButton")
	editor:SetScript("OnDragStart", editor.StartMoving)
	editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
	tinsert(UISpecialFrames, "CinematicRuleEditor") -- (Escape closes it)
	local close = ns.SkinClose(CreateFrame("Button", nil, editor, "UIPanelCloseButton"))
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() editor:Hide() end)
	local heading = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOP", 0, -10)
	heading:SetWidth(EDIT_W - 80)

	-- The rule, a few lines' room; a click anywhere on it types there.
	local well = CreateFrame("Frame", nil, editor, BACKDROP)
	well:SetPoint("TOPLEFT", 14, -34)
	well:SetSize(EDIT_W - 28, 64)
	if well.SetBackdrop then
		well:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		well:SetBackdropColor(0, 0, 0, 0.8)
	end
	ns.SkinWindow(well, true)
	local box = CreateFrame("EditBox", nil, well)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(EDIT_W - 40)
	box:SetPoint("TOPLEFT", 6, -6)
	box:SetMaxLetters(255)
	-- (It has the keys from the start: Escape here closes the editor, as Done does.)
	box:SetScript("OnEscapePressed", function() editor:Hide() end)
	well:SetScript("OnMouseDown", function() box:SetFocus() end)

	local reads = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	reads:SetPoint("TOPLEFT", well, "BOTTOMLEFT", 2, -6)
	reads:SetWidth(EDIT_W - 32)
	reads:SetJustifyH("LEFT")
	local now = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	now:SetPoint("TOPLEFT", reads, "BOTTOMLEFT", 0, -4)
	now:SetWidth(EDIT_W - 32)
	now:SetJustifyH("LEFT")

	local Refresh
	local function Changed()
		if target then target.SetText(box:GetText()) end
		Refresh()
	end
	box:SetScript("OnTextChanged", function(_, userInput)
		if userInput then Changed() end
	end)
	-- A piece in at the cursor, spaced from what's either side.
	local function Insert(word)
		local text, pos = box:GetText(), box:GetCursorPosition()
		local before, after = text:sub(1, pos), text:sub(pos + 1)
		local lead = (before == "" or before:find("[%s(]$") or word == ")") and "" or " "
		local trail = (word ~= "(" and after:find("^[%w_(]")) and " " or ""
		box:SetText(before .. lead .. word .. trail .. after)
		box:SetCursorPosition(#before + #lead + #word)
		box:SetFocus()
		Changed()
	end
	-- Undo: the piece before the cursor (a word, or a bracket or sign).
	local function Undo()
		local text, pos = box:GetText(), box:GetCursorPosition()
		local before, after = text:sub(1, pos):gsub("%s+$", ""), text:sub(pos + 1)
		local shorter = before:gsub("[%w_]+$", "")
		if shorter == before then shorter = before:sub(1, -2) end
		shorter = shorter:gsub("%s+$", "")
		box:SetText(shorter .. after)
		box:SetCursorPosition(#shorter)
		box:SetFocus()
		Changed()
	end

	-- The pieces, a line each in its colour; a green dot: true where you are now.
	local palette = CreateFrame("Frame", nil, editor)
	palette:SetPoint("TOPLEFT", now, "BOTTOMLEFT", -2, -12)
	palette:SetWidth(EDIT_W - 28)
	local LINE_X, DOT_ROOM = 70, 12
	local px, py = LINE_X, 0
	local wordButtons = {}
	local function Piece(text, onClick, color, dotted)
		local button = ns.PanelButton(palette)
		button:SetHeight(20)
		local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button:SetFontString(label)
		button:SetText(Colored(color, text))
		button:SetWidth(label:GetStringWidth() + 16 + (dotted and DOT_ROOM or 0))
		label:ClearAllPoints()
		label:SetPoint("CENTER", dotted and -DOT_ROOM / 2 or 0, 0)
		button:SetSkinEdge(color[1], color[2], color[3], 0.45)
		if dotted then
			button.dot = button:CreateTexture(nil, "OVERLAY")
			button.dot:SetSize(10, 10)
			button.dot:SetPoint("RIGHT", -5, 0)
			button.dot:SetTexture("Interface\\COMMON\\Indicator-Green")
			button.dot:Hide()
		end
		if px > LINE_X and px + button:GetWidth() > EDIT_W - 28 then
			px, py = LINE_X, py - 24
		end
		button:SetPoint("TOPLEFT", palette, "TOPLEFT", px, py)
		px = px + button:GetWidth() + 4
		button:SetScript("OnClick", onClick)
		return button
	end
	local GOLD = { 1, 0.82, 0 }
	-- (The Tooltip line's name and buttons, and the palette's height without it.)
	local tipLine, heightWithout = {}, nil
	for g, group in ipairs(ns.RulePieces()) do
		if group.tooltipOnly then heightWithout = -py + 22 end
		if g > 1 then px, py = LINE_X, py - 26 end
		local name = palette:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		if group.tooltipOnly then tipLine[#tipLine + 1] = name end
		name:SetText(group[1])
		name:SetTextColor(group[2][1], group[2][2], group[2][3])
		name:SetPoint("TOPLEFT", palette, "TOPLEFT", 0, py - 6)
		for _, piece in ipairs(group[3]) do
			local word = piece[1]
			local field = ns.RULE_WORDS[word]
			local button = Piece(piece[2], function() Insert(word) end, group[2], field ~= nil)
			if group.tooltipOnly then tipLine[#tipLine + 1] = button end
			if field and group.tooltipOnly then
				wordButtons[word] = button
				Tip(button, (L["Adds \"%s\": true for a tooltip of this kind (one can be more than one: a quest mob " ..
					"is an enemy too). Anything else: none of the others, and every tooltip of the UI."]):format(word))
			elseif field then
				wordButtons[word] = button
				local tip = (L["Adds \"%s\". A green dot: true where you are now."]):format(word)
				if field:find("^range") then
					-- (What it measures with here, as you look.)
					Tip(button, function() return ns.RangeBandInfo(field) end)
				elseif field == "near" or field == "near28" then
					Tip(button, tip .. "\n\n" .. L["Never counts in fights: the game won't say how far anyone is then. Spell range does."])
				else
					Tip(button, tip)
				end
			end
		end
		if g == 1 then
			-- (Undo and Clear at the end of the Logic line, a little apart.)
			px = px + 16
			Tip(Piece(L["Undo"], Undo, GOLD), L["Takes off the piece before the cursor."])
			Tip(Piece(L["Clear"], function()
				box:SetText("")
				box:SetFocus()
				Changed()
			end, GOLD), L["Empties the rule."])
		end
	end
	local heightWith = -py + 22
	heightWithout = heightWithout or heightWith
	-- Shows the Tooltip line or not, the editor's height to match.
	local function ShowTipLine(shown)
		for _, widget in ipairs(tipLine) do widget:SetShown(shown) end
		palette:SetHeight(shown and heightWith or heightWithout)
		editor:SetHeight(34 + 64 + 6 + 32 + 12 + palette:GetHeight() + 50)
	end
	palette:SetHeight(heightWith)

	-- Along the bottom: Reset to grid (when it can't go back by itself), Done.
	local done = ns.PanelButton(editor)
	done:SetSize(90, 22)
	done:SetPoint("BOTTOMRIGHT", -14, 12)
	done:SetText(L["Done"])
	done:SetScript("OnClick", function() editor:Hide() end)
	if done.SetMotionScriptsWhileDisabled then done:SetMotionScriptsWhileDisabled(true) end -- (its tip says why)
	Tip(done, function()
		if not done:IsEnabled() then
			return L["The rule isn't finished. Finish it, or close with X or Escape to put back the rule it had."]
		end
		return target and not target.grid and L["Closes the editor, keeping the rule."]
			or L["Closes the editor. A rule that's just the dropdowns' words joined by OR goes back into them; " ..
			"one that isn't stays the row's rule."]
	end)
	local resetGrid = ns.PanelButton(editor)
	resetGrid:SetSize(130, 22)
	resetGrid:SetPoint("BOTTOMLEFT", 14, 12)
	resetGrid:SetText(L["Reset to grid"])
	resetGrid:SetScript("OnClick", function()
		if target then target.ResetToGrid() end
		target = nil -- (nothing to put back as it closes)
		editor:Hide()
	end)
	Tip(resetGrid, L["Drops the rule: the row's dropdowns decide again, ticked as they were before."])
	editor:SetHeight(34 + 64 + 6 + 32 + 12 + palette:GetHeight() + 50)

	function Refresh()
		if not target then return end
		local text = box:GetText()
		local grid = target.grid
		local isAlways, why
		if grid then isAlways, why = ns.ReadGridRule(text, grid) end
		resetGrid:SetShown(grid ~= nil and isAlways == nil)
		-- (Only a rule that reads, or none, can be kept.)
		done:SetEnabled(not text:find("%S") or ns.CompileRule(text) ~= nil)
		reads:SetShown(grid ~= nil)
		reads:SetText(not grid and "" or isAlways ~= nil and "|cff60ff60" .. L["Goes back into the dropdowns as you close it."] .. "|r"
			or "|cffffd100" .. (L["Stays the row's rule (it can't go in the dropdowns: %s)."]):format(why) .. "|r")
		local facts = ns.db and ns.RuleFactsNow and ns.RuleFactsNow()
		for word, button in pairs(wordButtons) do
			button.dot:SetShown(facts and facts[ns.RULE_WORDS[word]] and true or false)
		end
		if not facts then
			now:SetText("")
			return
		end
		local test, err = ns.CompileRule(text)
		if not text:find("%S") then
			now:SetText(grid and "|cffffd100" .. L["Blank: never shown."] .. "|r"
				or "|cff999999" .. L["Empty: its ticks decide."] .. "|r")
		elseif not test then
			now:SetText("|cffff6060" .. (L["Not finished: %s. Closing now puts back the rule it had."]):format(err) .. "|r")
		else
			now:SetText(test(facts) and "|cff60ff60" .. L["Right now: shown"] .. "|r"
				or "|cffffd100" .. L["Right now: hidden"] .. "|r")
		end
	end
	local since = 0
	editor:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since > 0.5 then
			since = 0
			Refresh()
		end
	end)
	-- (Closed any way: Done, X, Escape or the settings going.)
	editor:SetScript("OnHide", function()
		box:ClearFocus()
		local closing = target
		target = nil
		if closing then closing.Close(box:GetText()) end
	end)
	editor.Open = function(newTarget)
		target = newTarget
		ShowTipLine(newTarget.key ~= nil and newTarget.key:find("^tooltip:") ~= nil)
		heading:SetText((L["Rule: %s"]):format(newTarget.label))
		local text = newTarget.Text()
		box:SetText(text)
		editor:Show()
		box:SetFocus()
		box:SetCursorPosition(#text)
		Refresh()
	end
end

-- Opens the editor for a row (see target above); another row's, open,
-- closes first (its rule kept or back in its dropdowns).
function ns.OpenRuleEditor(newTarget)
	if not editor then BuildEditor() end
	if editor:IsShown() then editor:Hide() end
	editor.Open(newTarget)
end
-- Closes it (the settings going).
function ns.CloseRuleEditor()
	if editor then editor:Hide() end
end

-- Whether key's a raid-style party frames' row, which follows the raid
-- frames' on purpose. (Frames.lua loads after this: looked up when asked.)
local function RaidStyleFollower(key)
	for _, partyKey in pairs(ns.RAID_STYLE_PARTY or {}) do
		if partyKey == key then return true end
	end
	return false
end

-- The rule word for each column's list (FRAME_COLUMNS' third field).
local LIST_WORD = { combatShow = "combat", enemyShow = "enemy", friendlyShow = "friendly", bgShow = "bg",
	worldShow = "world", cityShow = "city", groupShow = "group", instanceShow = "instance" }
-- The words a list row's dropdowns hold, for ns.ReadGridRule.
local GRID = { calm = true } -- (calm: the Combat dropdown's Calm Timer, calmShow)
for _, word in pairs(LIST_WORD) do GRID[word] = true end

-- The dropdowns, by number (a grid has some of them: ns.GRID_COMBAT...),
-- each in its colour (as the editor has them), and what its tip says.
local MENU_GROUPS = {
	{ heading = "Combat", color = { 1, 0.45, 0.4 }, help = "Shown while you're in a fight." },
	{ heading = "Target", color = { 1, 0.65, 0.25 }, help = "Shown while you have one of these targeted." },
	{ heading = "Location", color = { 0.45, 0.75, 1 },
		help = "Shown the whole time while you're in any of these (Grouped: in a party or raid)." },
}
ns.GRID_COMBAT, ns.GRID_TARGET, ns.GRID_LOCATION = 1, 2, 3
-- Which dropdown each list's in (the rest: Location).
local LIST_GROUP = { combatShow = 1, enemyShow = 2, friendlyShow = 2 }
local ROLE_COLOR = { 0.4, 0.85, 0.5 }
-- The targets' names in a menu (the rest are their columns').
local MENU_NAMES = { combatShow = "In combat", enemyShow = "Enemy targeted", friendlyShow = "Friend targeted" }

-- Across a row, from the label's end: Always, the dropdowns, the roles, Edit.
local ALWAYS_W, MENU_W, ROLES_W, RULE_W, GAP = 46, 96, 50, 40, 2
-- The dot at the end of a row's name (room kept for it in the label).
ns.GRID_DOT_ROOM = 18

-- The roles (a row's roles dropdown: unticked, kept hidden while you're
-- that role), their settings and icons (the nameplates' role texture).
local ROLES = { { "tankHide", "Tank", "0:19:22:41" }, { "healerHide", "Healer", "20:39:1:20" },
	{ "damageHide", "Damage", "20:39:22:41" } }
local function RoleIcon(role, size)
	return ("|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:%d:%d:0:0:64:64:%s|t"):format(size, size, role[3])
end

-- What a dropdown says: -, the one ticked, All or how many.
local function Summary(names, total, color)
	if #names == 0 then return "|cff808080-|r" end
	if #names == 1 then return Colored(color, names[1]) end
	if #names == total then return Colored(color, L["All"]) end
	return Colored(color, (L["%d of %d"]):format(#names, total))
end

-- Where a grid's columns go across a row, labelWidth in. layout: { groups,
-- the dropdowns it has ({ 1, 2, 3 } when nil); always = false: no Always
-- column; roles, edit: those columns }.
local function Columns(layout)
	local x, cols = 0, { menus = {} }
	if layout.always ~= false then
		cols.always = x
		x = x + ALWAYS_W + GAP
	end
	for _, g in ipairs(layout.groups or { 1, 2, 3 }) do
		cols.menus[g] = x
		x = x + MENU_W + GAP
	end
	cols.menusEnd = x
	if layout.roles and ns.GRID_MENUS then
		cols.roles = x
		x = x + ROLES_W + GAP
	end
	if layout.edit then
		cols.edit = x
		x = x + RULE_W
	end
	cols.width = x
	return cols
end
-- How wide a grid's columns are (the label's not counted).
function ns.GridWidth(layout) return Columns(layout).width end

-- The headings over a grid's columns: at top's top left, labelWidth in
-- (kit.FrameHeading's height, kit.headingHeight). Gives them, to show and hide.
function ns.GridHeadings(kit, parent, top, labelWidth, layout)
	local cols, made = Columns(layout), {}
	local function Heading(text, x, width, color)
		local heading = kit.FrameHeading(parent, text)
		heading:SetWidth(width)
		heading:SetPoint("TOPLEFT", top, "TOPLEFT", labelWidth + x, 0)
		if color then heading:SetTextColor(color[1], color[2], color[3]) end
		made[#made + 1] = heading
	end
	if cols.always then Heading(layout.alwaysHeading or L["Always"], cols.always, ALWAYS_W) end
	for g, group in ipairs(MENU_GROUPS) do
		if cols.menus[g] then Heading(L[group.heading], cols.menus[g], MENU_W, group.color) end
	end
	if cols.roles then Heading(L["Roles"], cols.roles, ROLES_W, ROLE_COLOR) end
	if cols.edit then Heading(L["Edit"], cols.edit, RULE_W) end
	return made
end

-- A text button the width of the dropdowns, for the row's rule in their place.
local function RuleButton(row, width)
	local button = ns.PanelButton(row)
	button:SetSize(width, 20)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetWordWrap(false)
	button:SetFontString(text)
	text:ClearAllPoints()
	text:SetPoint("LEFT", 6, 0)
	text:SetPoint("RIGHT", -6, 0)
	text:SetJustifyH("LEFT")
	return button
end

-- One row of a grid, in a frame the caller places with its label (drawn by
-- the caller, labelWidth wide, to the row's left). kit: the page helpers
-- (Options.lua's Tooltip, Refresh, controls, RecordKey...). spec:
--   always = { isOn(), set(value), tip } (nil: an empty cell);
--   menus = { [dropdown] = { { name, isOn(), toggle(), usable() or nil, tip }... } };
--   roles = { key(), tip, changed() } (nil: none);
--   rule = { key(), label(), grid (the dropdowns' words, for ns.ReadGridRule;
--     nil: a rule just stays), words(), apply(always, ticked), changed(key) } (nil: no Edit);
--   enabled() (nil: usable): whether its client has it and the like;
--   cells() (nil: "full"): "full", "always" (just Always) or "none" (a row reused);
--   changed(): after any change; band: its number (every other one lighter,
--     the band across the label too);
--   dot = true: a dot at the label's end, green while it'd show now (from its
--     rule, else liveRule(): its ticks as a rule, for a row whose ticks aren't
--     the rules' words, else its rule.grid words).
-- The row's Refresh and SetEnabled are the page's (it goes in kit.controls).
function ns.GridRow(kit, parent, labelWidth, layout, spec)
	local cols = Columns(layout)
	local Tooltip, Refresh = kit.Tooltip, kit.Refresh
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(cols.width, 24)
	local function Changed()
		if spec.changed then spec.changed() end
		Refresh()
	end
	local rule = spec.rule
	local function RuleKey() return rule and rule.key() end
	local function Rule()
		local key = RuleKey()
		local rules = key and ns.GetDB().frameRules
		local text = rules and rules[key]
		return type(text) == "string" and text:find("%S") and text or nil
	end
	local function SetRule(text)
		local db = ns.GetDB()
		db.frameRules = db.frameRules or {}
		db.frameRules[RuleKey()] = text
		if rule.changed then rule.changed(RuleKey()) end
	end
	local function AlwaysOn() return spec.always and spec.always.isOn() and true or false end

	-- (row:SetBand(n): its number again, for a row laid out afresh.)
	if spec.band then
		local band = row:CreateTexture(nil, "BACKGROUND", nil, -8)
		band:SetPoint("TOPLEFT", row, "TOPLEFT", -labelWidth, 1)
		band:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -1)
		function row:SetBand(n) band:SetColorTexture(1, 1, 1, n % 2 == 1 and 0.05 or 0.02) end
		row:SetBand(spec.band)
	end
	local live
	if spec.dot then
		live = row:CreateTexture(nil, "OVERLAY")
		live:SetSize(10, 10)
		live:SetPoint("RIGHT", row, "LEFT", -6, 0)
		local hover = CreateFrame("Frame", nil, row)
		hover:SetSize(16, 16)
		hover:SetPoint("CENTER", live, "CENTER")
		hover:EnableMouse(true)
		Tooltip(hover, L["Green: it'd show in CineMode right now. Grey: it'd be hidden. None: its rule isn't finished."])
	end

	local always
	if spec.always and cols.always then
		always = ns.SkinCheck(CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate"))
		always:SetSize(26, 26)
		always:SetPoint("LEFT", cols.always + (ALWAYS_W - 26) / 2, 0)
		always:SetScript("OnClick", function(self)
			spec.always.set(self:GetChecked() and true or false)
			Changed()
		end)
		Tooltip(always, spec.always.tip)
	end

	-- The dropdowns, each its items' ticks.
	local menus = {}
	for g, group in ipairs(MENU_GROUPS) do
		local entries = spec.menus and spec.menus[g]
		if cols.menus[g] and entries and #entries > 0 then
			local color, heading, help = group.color, L[group.heading], spec.help and spec.help[g] or L[group.help]
			local button = ns.GridMenuButton(row, MENU_W)
			button:SetPoint("LEFT", cols.menus[g], 0)
			button:SetSkinEdge(color[1], color[2], color[3], 0.45)
			button:SetScript("OnClick", function(self) ns.TickMenu(self, entries, Changed) end)
			button.Refresh = function(self)
				local on = {}
				for _, entry in ipairs(entries) do
					if entry[2]() then on[#on + 1] = entry[1] end
				end
				self:SetText(Summary(on, #entries, color))
				self.tip = #on > 0 and table.concat(on, ", ") or L["Nothing ticked"]
			end
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(heading, 1, 1, 1)
				GameTooltip:AddLine(self.tip, color[1], color[2], color[3], true)
				GameTooltip:AddLine(help, 0.8, 0.8, 0.8, true)
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			menus[#menus + 1] = button
		end
	end

	-- The roles it shows for (kept apart from the rule: they count either way).
	local roles
	if spec.roles and cols.roles then
		local Key = spec.roles.key
		roles = ns.GridMenuButton(row, ROLES_W)
		roles:SetPoint("LEFT", cols.roles, 0)
		roles:SetSkinEdge(ROLE_COLOR[1], ROLE_COLOR[2], ROLE_COLOR[3], 0.45)
		-- Ticked: it shows only while you're one of them; none ticked (-), for
		-- every role. Kept as the roles it's hidden for (tankHide...), so all
		-- ticked is none hidden too, and back to -. (All hidden, from before:
		-- None, in red, ticks as none.)
		local function Hidden(list) return ns.RoleHidden(ns.GetDB(), list, Key()) end
		local function HiddenCount()
			local count = 0
			for _, role in ipairs(ROLES) do
				if Hidden(role[1]) then count = count + 1 end
			end
			return count
		end
		local function Ticked(list)
			local hidden = HiddenCount()
			return hidden > 0 and hidden < #ROLES and not Hidden(list)
		end
		local entries = {}
		for _, role in ipairs(ROLES) do
			local list = role[1]
			entries[#entries + 1] = { RoleIcon(role, 14) .. " " .. L[role[2]], function() return Ticked(list) end, function()
				local db, key = ns.GetDB(), Key()
				local ticked, count = {}, 0
				for _, each in ipairs(ROLES) do
					local on = Ticked(each[1])
					if each[1] == list then on = not on end
					ticked[each[1]] = on
					if on then count = count + 1 end
				end
				for _, each in ipairs(ROLES) do
					local hide = count > 0 and count < #ROLES and not ticked[each[1]]
					db[each[1]] = db[each[1]] or {}
					-- (Back to nil when it's the row's default again.)
					if hide == ns.RoleHidden({}, each[1], key) then
						db[each[1]][key] = nil
					else
						db[each[1]][key] = hide
					end
				end
			end }
		end
		roles:SetScript("OnClick", function(self)
			ns.TickMenu(self, entries, function()
				if spec.roles.changed then spec.roles.changed() end
				Changed()
			end, true)
		end)
		roles.Refresh = function(self)
			local hidden = HiddenCount()
			if hidden == 0 then
				self:SetText("|cff808080-|r")
			elseif hidden == #ROLES then
				self:SetText("|cffff6060" .. L["None"] .. "|r")
			else
				local on = {}
				for _, role in ipairs(ROLES) do
					if not Hidden(role[1]) then on[#on + 1] = RoleIcon(role, 13) end
				end
				self:SetText(table.concat(on))
			end
		end
		Tooltip(roles, spec.roles.tip or L["Tick roles to show it only while you're one of them (your specialization's, " ..
			"or the one picked in the group finder), whatever its ticks or rule say. None ticked (-): every role."])
	end

	-- The rule: in text mode, shown where Always and the dropdowns were (a
	-- click opens the editor), its edge red while it doesn't read (the
	-- ticks decide then); Edit opens the editor, Grid puts it back.
	local ruleText, edit
	if rule and cols.edit then
		ruleText = RuleButton(row, cols.menusEnd - GAP)
		ruleText:SetPoint("LEFT", 0, 0)
		local function Target()
			local before = Rule()
			-- (No rule yet: its dropdowns' or ticks' words to start from; none ticked, blank.)
			local ticksRule = not rule.grid and spec.liveRule and spec.liveRule()
			local start = before or (rule.grid and (AlwaysOn() or #rule.words() > 0)
				and ns.GridRule(AlwaysOn(), rule.words())) or (rule.grid and "")
				or (ticksRule ~= "never" and ticksRule) or ""
			return { label = rule.label(), grid = rule.grid, key = RuleKey(),
				Text = function() return start end,
				SetText = function(typed) SetRule(typed) Refresh() end,
				Close = function(typed)
					-- (A rule that doesn't read never stays: back to the one it had, or its grid.)
					if typed:find("%S") and not ns.CompileRule(typed) then
						SetRule(before and ns.CompileRule(before) and before or nil)
						Changed()
						return
					end
					local isAlways, ticked
					if rule.grid then isAlways, ticked = ns.ReadGridRule(typed, rule.grid) end
					if isAlways ~= nil then
						-- (Unchanged and never a rule: nothing to write.)
						if before or typed ~= start then rule.apply(isAlways, ticked) end
						SetRule(nil)
					elseif not before and typed == start then
						SetRule(nil) -- (its ticks' words, untouched: the ticks keep deciding)
					else
						SetRule(typed:find("%S") and typed or nil)
					end
					Changed()
				end,
				ResetToGrid = function() SetRule(nil) Changed() end,
			}
		end
		ruleText:SetScript("OnClick", function() ns.OpenRuleEditor(Target()) end)
		ruleText:SetScript("OnEnter", function(self)
			local text = Rule() or ""
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Rule"], 1, 1, 1)
			GameTooltip:AddLine(ns.ColoredRule(text), 1, 1, 1, true)
			local _, err = ns.CompileRule(text)
			if err then
				GameTooltip:AddLine((rule.grid and L["Not finished: %s. The dropdowns decide until it is."]
					or L["Not finished: %s. Its ticks decide until it is."]):format(err), 1, 0.38, 0.38, true)
			end
			GameTooltip:AddLine(L["Click to open the editor."], 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		ruleText:SetScript("OnLeave", GameTooltip_Hide)

		edit = ns.PanelButton(row)
		edit:SetSize(RULE_W, 20)
		edit:SetPoint("LEFT", cols.edit, 0)
		edit:SetNormalFontObject("GameFontHighlightSmall")
		edit:SetDisabledFontObject("GameFontDisableSmall")
		if edit.SetMotionScriptsWhileDisabled then edit:SetMotionScriptsWhileDisabled(true) end -- (its tip says why)
		edit:SetScript("OnClick", function()
			local text = Rule()
			if not text then
				ns.OpenRuleEditor(Target())
			elseif rule.grid then
				Target().Close(text) -- (back into the dropdowns, as the editor would)
			else
				SetRule(nil) -- (its ticks again)
				Changed()
			end
		end)
		edit:SetScript("OnEnter", function(self)
			local text = Rule()
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if not text then
				GameTooltip:SetText(L["Edit as a rule"], 1, 1, 1)
				if rule.grid then
					GameTooltip:AddLine(ns.ColoredRule(ns.GridRule(AlwaysOn(), rule.words())), 1, 1, 1, true)
				elseif spec.liveRule then
					GameTooltip:AddLine(ns.ColoredRule(spec.liveRule()), 1, 1, 1, true)
				end
				GameTooltip:AddLine(L["Opens the rule editor, for AND, NOT and more places and situations " ..
					"than the dropdowns have."], 0.8, 0.8, 0.8, true)
			elseif rule.grid then
				local _, why = ns.ReadGridRule(text, rule.grid)
				GameTooltip:SetText(L["Back to the dropdowns"], 1, 1, 1)
				GameTooltip:AddLine(why and (L["Can't: %s. Open the rule to change it, or Reset to grid there."])
					:format(why) or L["Puts the rule's words back in the dropdowns."], 0.8, 0.8, 0.8, true)
			else
				GameTooltip:SetText(L["Back to the ticks"], 1, 1, 1)
				GameTooltip:AddLine(L["Drops the rule: its ticks, as they were, decide again."], 0.8, 0.8, 0.8, true)
			end
			GameTooltip:Show()
		end)
		edit:SetScript("OnLeave", GameTooltip_Hide)
	end

	-- The dot: what its rule (or its ticks, as one) gives where you are
	-- now, and whether its roles keep it hidden.
	local function Live()
		if not live then return end
		local facts = ns.db and ns.RuleFactsNow and ns.RuleFactsNow()
		local text = Rule() or (spec.liveRule and spec.liveRule())
			or (rule and rule.grid and ns.GridRule(AlwaysOn(), rule.words()))
		local test = facts and text and ns.CompileRule(text)
		if not test then
			live:Hide()
			return
		end
		local key = spec.roles and spec.roles.key()
		local roleList = facts.tank and "tankHide" or facts.healer and "healerHide" or facts.damage and "damageHide"
		local shows = test(facts) and not (key and roleList and ns.RoleHidden(ns.GetDB(), roleList, key))
		live:SetTexture(shows and "Interface\\COMMON\\Indicator-Green" or "Interface\\COMMON\\Indicator-Gray")
		live:Show()
	end
	row.Live = Live

	-- Shows the row as its settings are. (Refresh and SetEnabled both call
	-- this, never each other: a section's wrapper of Refresh may end in
	-- SetEnabled(false), so that would loop.)
	local function Paint()
		if not ns.GetDB() then return end
		local cells = spec.cells and spec.cells() or "full"
		local full = cells == "full"
		local enabled = row.enabled ~= false and (not spec.enabled or spec.enabled())
		local text = full and Rule()
		local on = AlwaysOn()
		if always then
			always:SetShown(cells ~= "none" and not text)
			always:SetChecked(on)
			always:SetEnabled(enabled)
		end
		for _, menu in ipairs(menus) do
			menu:SetShown(full and not text)
			menu:Refresh()
			menu:SetEnabled(enabled and not on)
			-- (Greyed, faded whole, edge and all: plainly out of play while Always is ticked.)
			menu:SetAlpha((enabled and not on) and 1 or 0.35)
		end
		if roles then
			roles:SetShown(full)
			roles:Refresh()
			roles:SetEnabled(enabled)
		end
		if ruleText then
			ruleText:SetShown(text and true or false)
			ruleText:SetEnabled(enabled)
			if text then
				ruleText:SetText(ns.ColoredRule(text))
				ruleText:SetSkinTint(not ns.CompileRule(text) and 1 or nil, 0.45, 0.45)
			end
			edit:SetShown(full)
			edit:SetText(text and L["Grid"] or L["Edit"])
			edit:SetEnabled(enabled and (not text or not rule.grid or ns.ReadGridRule(text, rule.grid) ~= nil))
		end
		if live then
			if full then Live() else live:Hide() end
		end
	end
	function row:Refresh() Paint() end
	function row:SetEnabled(enabled)
		self.enabled = enabled and true or false
		Paint()
	end
	kit.controls[#kit.controls + 1] = row
	return row
end

-- The rows' dots kept up while parent shows (every half second).
function ns.GridDots(parent, rows)
	local ticker = CreateFrame("Frame", nil, parent)
	local since = 0
	ticker:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < 0.5 then return end
		since = 0
		for _, row in ipairs(rows) do
			if row:IsVisible() then row.Live() end
		end
	end)
end

-- The spec parts for a row kept in the shared lists (the Standard Frames
-- page's columns: the frames tables', the supported addons', custom
-- frames', and the Show in rows that were Turn off in grids): Key() its key
-- (a function, for rows reused), columns (from the second: FRAME_COLUMNS),
-- columnTips (nil: the columns' own), setAlways. Gives menus, words, apply
-- for ns.GridRow. A tick here gives the rows that follow this one
-- (ns.ROW_FALLBACK: the pet frame the player frame's) its old tick of their
-- own first, so only this row changes. Combat holds three times, each a
-- tick of its own: In combat, Calm Timer (calmShow: after a fight, till it's
-- run out) and Out of combat (quietShow: the rest). opts (nil: none):
--   quiet, cam: Out of combat (quietShow) and In a camera mode (camShow) in Combat too;
--   anyFight: its In combat in any fight (not greyed while CineMode doesn't stay on in them);
--   omit: lists left out (list -> true: In combat, the targets, a place);
--   calmItem: in place of the Calm Timer, a menu entry of its own (cameras' wait).
function ns.ListRowParts(Key, columns, columnTips, setAlways, opts)
	opts = opts or {}
	local omit = opts.omit or {}
	local function KeepFollowers(list, isOn)
		local db, key = ns.GetDB(), Key()
		for follower, leader in pairs(ns.ROW_FALLBACK or {}) do
			if leader == key and db[list][follower] == nil and not RaidStyleFollower(follower) then
				db[list][follower] = isOn(follower) and true or false
			end
		end
	end
	local function Ticked(c) return columns[c][2](Key()) and true or false end
	local function SetTick(c, value)
		KeepFollowers(columns[c][3], columns[c][2])
		ns.GetDB()[columns[c][3]][Key()] = value
	end
	-- (The lists that aren't columns: Calm Timer, Out of combat, In a camera mode.)
	local EXTRA_ON = { calmShow = ns.IsCalmShowOn, quietShow = ns.IsQuietShowOn, camShow = ns.IsCamShowOn }
	local function ExtraOn(list) return EXTRA_ON[list](Key()) and true or false end
	local function SetExtra(list, value)
		KeepFollowers(list, EXTRA_ON[list])
		ns.GetDB()[list][Key()] = value
	end
	local combatColumn
	for c = 2, #columns do
		if columns[c][3] == "combatShow" and not omit.combatShow then combatColumn = c end
	end
	local stays = function() return ns.GetDB().stayInCombat and true or false end

	local menus = { {}, {}, {} }
	for c = 2, #columns do
		local column = columns[c]
		local list = column[3]
		if not omit[list] then
			local name = MENU_NAMES[list] and L[MENU_NAMES[list]] or column[1]
			local tip = columnTips and columnTips[c] or column[5]
			-- (In combat only counts while CineMode stays on in fights, for the UI's rows.)
			local needsStay = column[4] and not opts.anyFight
			if needsStay then
				tip = (tip and tip .. " " or "") .. L["(Only while Combat is unticked under Turn off in, " ..
					"on the main page: CineMode stays on in fights.)"]
			end
			local group = menus[LIST_GROUP[list] or 3]
			group[#group + 1] = { name, function() return Ticked(c) end, function() SetTick(c, not Ticked(c)) end,
				needsStay and stays or nil, tip }
			-- (Combat's Calm Timer: the time after a fight, till it's run out.)
			if c == combatColumn then
				if opts.calmItem then
					group[#group + 1] = opts.calmItem
				else
					group[#group + 1] = { L["Calm Timer"], function() return ExtraOn("calmShow") end,
						function() SetExtra("calmShow", not ExtraOn("calmShow")) end, nil,
						L["On after a fight, until the Calm Timer (CineMode page) has run out. With In combat too: " ..
						"the fight, then that."] }
				end
				if opts.quiet then
					group[#group + 1] = { L["Out of combat"], function() return ExtraOn("quietShow") end,
						function() SetExtra("quietShow", not ExtraOn("quietShow")) end, nil,
						L["On out of fights, once the Calm Timer after one has run out. With Calm Timer too: as soon " ..
						"as a fight ends."] }
				end
				if opts.cam then
					group[#group + 1] = { L["In a camera mode"], function() return ExtraOn("camShow") end,
						function() SetExtra("camShow", not ExtraOn("camShow")) end, nil,
						L["On while a camera mode runs (flights, AFK, cozy and the rest)."] }
				end
			end
		end
	end
	-- (A Combat dropdown with no In combat: Calm Timer's item, and the others.)
	if not combatColumn then
		local group = menus[1]
		if opts.calmItem then group[#group + 1] = opts.calmItem end
		if opts.quiet then
			group[#group + 1] = { L["Out of combat"], function() return ExtraOn("quietShow") end,
				function() SetExtra("quietShow", not ExtraOn("quietShow")) end, nil,
				L["On out of fights, once the Calm Timer after one has run out. With Calm Timer too: as soon " ..
				"as a fight ends."] }
		end
		if opts.cam then
			group[#group + 1] = { L["In a camera mode"], function() return ExtraOn("camShow") end,
				function() SetExtra("camShow", not ExtraOn("camShow")) end, nil,
				L["On while a camera mode runs (flights, AFK, cozy and the rest)."] }
		end
	end
	-- (A row's own items at the Combat dropdown's end: opts.combatItems, each
	-- { name, isOn(), toggle(), usable() or nil, tip }. Not words of the
	-- row's rule: the row reads them itself.)
	for _, item in ipairs(opts.combatItems or {}) do
		menus[1][#menus[1] + 1] = item
	end
	local function Words()
		local words = {}
		for c = 2, #columns do
			if not omit[columns[c][3]] and Ticked(c) then words[#words + 1] = LIST_WORD[columns[c][3]] end
			if c == combatColumn and not opts.calmItem and ExtraOn("calmShow") then words[#words + 1] = "calm" end
		end
		if opts.quiet and ExtraOn("quietShow") then words[#words + 1] = "nocombat" end
		if opts.cam and ExtraOn("camShow") then words[#words + 1] = "camera" end
		return words
	end
	local function Apply(isAlways, ticked)
		if setAlways then setAlways(isAlways) end
		for c = 2, #columns do
			if not omit[columns[c][3]] then SetTick(c, ticked[LIST_WORD[columns[c][3]]] and true or false) end
		end
		if combatColumn and not opts.calmItem then SetExtra("calmShow", ticked.calm and true or false) end
		if opts.quiet then SetExtra("quietShow", ticked.nocombat and true or false) end
		if opts.cam then SetExtra("camShow", ticked.camera and true or false) end
	end
	-- (The words this row's dropdowns hold, for reading a rule back into them.)
	local grid = {}
	for word in pairs(GRID) do grid[word] = true end
	if omit.combatShow or opts.calmItem then grid.calm = nil end
	for list in pairs(omit) do
		if LIST_WORD[list] then grid[LIST_WORD[list]] = nil end
	end
	grid.nocombat = opts.quiet or nil
	grid.camera = opts.cam or nil
	return { menus = menus, words = Words, apply = Apply, grid = grid, keepFollowers = KeepFollowers }
end

-- The Standard Frames table, a row per item, as dropdowns (ShowTable does
-- the rest: its kit is the page helpers it shares). Returns the last row's
-- label, to place what comes below.
function ns.GridTable(content, columnTop, rows, kit)
	local LABEL_WIDTH, ROW_HEIGHT, COLUMNS = kit.labelWidth, kit.rowHeight, kit.columns
	local Tooltip = kit.Tooltip
	local LAYOUT = { roles = kit.rolesMenu, edit = true }
	if not rows.noHeadings then
		ns.GridHeadings(kit, content, columnTop, LABEL_WIDTH, LAYOUT)
	end

	local made = {}
	local lastLabel = columnTop
	for r, item in ipairs(rows) do
		local y = -kit.headingHeight - 4 - (r - 1) * ROW_HEIGHT
		local rowLabel = kit.Label(content, "GameFontHighlight", item.label)
		rowLabel:SetPoint("TOPLEFT", columnTop, "TOPLEFT", 0, y - 5)
		rowLabel:SetWidth(LABEL_WIDTH - 4 - ns.GRID_DOT_ROOM)
		rowLabel:SetJustifyH("LEFT")
		rowLabel:SetWordWrap(false)
		kit.ShowBox(content, item, rowLabel) -- (its frame on at all: item.showKey)
		-- An asterisk, with a tip, on rows that have a page of their own.
		if item.morePage or item.tip then
			if item.morePage then rowLabel:SetText(item.label .. " |cffffd100*|r") end
			local hover = CreateFrame("Frame", nil, content)
			hover:SetAllPoints(rowLabel)
			hover:EnableMouse(true)
			Tooltip(hover, item.morePage and (L["More settings on the %s page. They can keep it up beyond what's " ..
				"ticked here (hovering, tracking, new auras, cooldowns recharging and the like)."]):format(L[item.morePage])
				or item.tip)
		end
		if ns.CINE_SHOW_SETTING[item.key] then
			kit.RecordKey(content, ns.CINE_SHOW_SETTING[item.key]) -- (for the page's Reset)
		end
		for c, column in ipairs(item.alwaysOnly and { COLUMNS[1] } or COLUMNS) do
			if c > 1 or not item.setAlways then
				kit.RecordKey(content, column[3])
				kit.RecordRow(content, column[3], item.key)
			end
		end
		if item.alwaysKey then kit.RecordKey(content, item.alwaysKey) end
		for _, key in ipairs(item.recordKeys or {}) do kit.RecordKey(content, key) end
		local opts = {}
		for k, v in pairs(rows.opts or {}) do opts[k] = v end
		for k, v in pairs(item.opts or {}) do opts[k] = v end
		if not item.alwaysOnly then
			for _, list in ipairs({ "calmShow", "quietShow", "camShow", "tankHide", "healerHide", "damageHide" }) do
				kit.RecordKey(content, list)
				kit.RecordRow(content, list, item.key)
			end
		end

		local function Key() return item.key end
		local alwaysOn = item.alwaysOn or ns.IsCineShowOn
		local parts
		local function SetAlways(value)
			local setting = ns.CINE_SHOW_SETTING[item.key]
			if item.setAlways then
				item.setAlways(value)
			elseif setting then
				ns.GetDB()[setting] = value
			else
				parts.keepFollowers("cineShow", ns.IsCineShowOn)
				ns.GetDB().cineShow[item.key] = value
			end
		end
		parts = ns.ListRowParts(Key, COLUMNS, rows.columnTips, SetAlways, opts)
		local spec = {
			band = r, dot = not item.alwaysOnly,
			always = { isOn = function() return alwaysOn(item.key) end, set = SetAlways,
				tip = item.alwaysTip or item.part
				and L["Show it whenever its frame shows. This overrides its Mouseover groups: untick it to " ..
				"hide it in CineMode except when hovered or brought up by the other columns."]
				or L["Show it all through CineMode, instead of hiding it. (The other columns then have nothing to add.)"] },
			changed = item.apply,
			enabled = item.showKey and function() return kit.RowShown(item) end or nil,
		}
		if not item.alwaysOnly then
			spec.menus = parts.menus
			spec.roles = { key = Key, tip = rows.rolesTip }
			spec.rule = { key = Key, label = function() return item.label end, grid = parts.grid,
				words = parts.words, apply = parts.apply }
		end
		local row = ns.GridRow(kit, content, LABEL_WIDTH, LAYOUT, spec)
		row.debugName = item.label -- (for the dev copy's page timing)
		row:SetPoint("TOPLEFT", columnTop, "TOPLEFT", LABEL_WIDTH, y)
		made[#made + 1] = row
		lastLabel = rowLabel
	end
	ns.GridDots(content, made)
	return lastLabel
end
