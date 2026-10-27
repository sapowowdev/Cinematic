-- Cinematic: picking an icon from all the game's, like the macro window's
-- icon list: a scrolling grid of every icon the game has (as the macro
-- window lists them), the one picked now framed in gold, and a box to find
-- one by name (a spell or item, or an icon's file name: ns.FindIcon in
-- CustomWheels.lua). Used for the Wheels pages' icons and your profiles'.
--
-- browser = ns.IconBrowser(canvas, onPick); browser:Open(owner, key,
-- current) shows it under owner (above when that runs off the page), and a
-- click on an icon calls onPick(key, icon). Like the Mouseover groups page's
-- grid (Options.lua's IconPicker): on the page's canvas, so the scroll frame
-- doesn't clip it, and a click anywhere else puts it away.
local _, ns = ...
local L = ns.L

local COLUMNS, ROWS = 10, 7
local CELL, GAP, EDGE = 36, 4, 10
local HEADER = 44 -- (the one picked now and the find box, above the grid)
local SCROLL_W = 16

-- Every icon, as the macro window lists them: file IDs, or names (made
-- into paths). Read once, the first time a browser opens.
local icons
local function AllIcons()
	if icons then
		return icons
	end
	local list = {}
	-- (Retail and WoW Forever: the macro window's own list.)
	if IconDataProviderMixin and CreateAndInitFromMixin then
		local ok, provider = pcall(CreateAndInitFromMixin, IconDataProviderMixin,
			IconDataProviderExtraType and IconDataProviderExtraType.None)
		if ok and provider and provider.GetNumIcons then
			for i = 1, provider:GetNumIcons() do
				list[#list + 1] = provider:GetIconByIndex(i)
			end
			if provider.Release then
				pcall(provider.Release, provider)
			end
		end
	end
	-- (Older clients: the lists the macro window used to read.)
	if #list == 0 then
		for _, Get in ipairs({ GetLooseMacroIcons, GetMacroIcons, GetLooseMacroItemIcons, GetMacroItemIcons }) do
			if Get then
				pcall(Get, list)
			end
		end
	end
	icons = {}
	local seen = {}
	for _, icon in ipairs(list) do
		if type(icon) == "string" and not icon:find("[\\/]") then
			icon = "Interface\\Icons\\" .. icon
		end
		if icon and not seen[icon] then
			seen[icon] = true
			icons[#icons + 1] = icon
		end
	end
	-- (None at all: the Mouseover groups page's.)
	if #icons == 0 then
		for _, icon in ipairs(ns.HOVER_GROUP_ICONS) do
			icons[#icons + 1] = icon
		end
	end
	return icons
end

-- Icons with a name the game tells us, for the find box: { lowered name,
-- icon } for the spells in your spellbook, the items you carry and wear,
-- and every mount. (The macro window's list is mostly file IDs, which have
-- no name in game; those match only by an icon's file name where it has one.)
local function NamedIcons()
	local named = {}
	local function Add(name, icon)
		if type(name) == "string" and name ~= "" and icon then
			named[#named + 1] = { name:lower(), icon, name }
		end
	end
	local function FromLink(link, icon)
		Add(type(link) == "string" and link:match("%[(.-)%]"), icon)
	end
	pcall(function() -- (your spellbook)
		if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
			local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
			for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
				local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
				if info then
					for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
						local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
						if item then Add(item.name, item.iconID) end
					end
				end
			end
		elseif GetNumSpellTabs then
			local book = BOOKTYPE_SPELL or "spell"
			for tab = 1, GetNumSpellTabs() do
				local _, _, offset, count = GetSpellTabInfo(tab)
				for i = offset + 1, offset + count do
					Add(GetSpellBookItemName(i, book), GetSpellBookItemTexture(i, book))
				end
			end
		end
	end)
	pcall(function() -- (your bags)
		local Container = C_Container or {}
		local Slots = Container.GetContainerNumSlots or GetContainerNumSlots
		for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
			for slot = 1, Slots(bag) or 0 do
				if Container.GetContainerItemInfo then
					local info = Container.GetContainerItemInfo(bag, slot)
					if info then FromLink(info.hyperlink, info.iconFileID) end
				else
					local icon, _, _, _, _, _, link = GetContainerItemInfo(bag, slot)
					FromLink(link, icon)
				end
			end
		end
	end)
	pcall(function() -- (what you wear)
		for slot = 1, 19 do
			FromLink(GetInventoryItemLink("player", slot), GetInventoryItemTexture("player", slot))
		end
	end)
	pcall(function() -- (every mount, had or not)
		if C_MountJournal and C_MountJournal.GetMountIDs then
			for _, id in ipairs(C_MountJournal.GetMountIDs()) do
				local name, _, icon = C_MountJournal.GetMountInfoByID(id)
				Add(name, icon)
			end
		end
	end)
	return named
end

-- An icon as a table key: file IDs as they are, paths lowered.
local function Key(icon)
	return type(icon) == "string" and icon:lower() or icon
end

-- Every spell in the game, read a little each frame (out of combat) from
-- the first time a browser opens, so most icons get a name: the first
-- spell's that uses it. The game can't name an icon's file from its ID.
local SCAN_MS = 3 -- (per frame)
local SCAN_BATCH = 200
local SCAN_GAP = 100000 -- (this many IDs on without a spell: the end)
local spellNames = {} -- icon key -> the first spell's name
local spellList = {} -- { lowered name, icon, name }, in spell ID order
local scanDone
local scanner = CreateFrame("Frame")
local function StartSpellScan()
	if scanDone or scanner:GetScript("OnUpdate") then
		return
	end
	local GetTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
	local GetName = C_Spell and C_Spell.GetSpellName or function(id) return (GetSpellInfo(id)) end
	local nextID, lastHit = 1, 0
	local function Step()
		local stop = debugprofilestop() + SCAN_MS
		repeat
			for id = nextID, nextID + SCAN_BATCH - 1 do
				local icon = GetTexture(id)
				if icon then
					lastHit = id
					local key = Key(icon)
					if not spellNames[key] then
						local name = GetName(id)
						if type(name) == "string" and name ~= "" then
							spellNames[key] = name
							spellList[#spellList + 1] = { name:lower(), icon, name }
						end
					end
				end
			end
			nextID = nextID + SCAN_BATCH
			if nextID - lastHit > SCAN_GAP then
				return true
			end
		until debugprofilestop() > stop
	end
	scanner:SetScript("OnUpdate", function(self)
		if InCombatLockdown() then
			return
		end
		local ok, finished = pcall(Step)
		if finished or not ok then
			scanDone = true
			self:SetScript("OnUpdate", nil)
		end
	end)
end

-- The same icon, whether it's a file ID or its path (case aside).
local function Same(a, b)
	if a == nil or b == nil then
		return false
	end
	if type(a) == "string" and type(b) == "string" then
		return a:lower() == b:lower()
	end
	return a == b
end

local function SkinnedBox(parent)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	return ns.SkinEditBox and ns.SkinEditBox(box) or box
end

function ns.IconBrowser(canvas, onPick)
	local width = EDGE * 2 + COLUMNS * CELL + (COLUMNS - 1) * GAP + SCROLL_W + 6
	local height = EDGE * 2 + HEADER + ROWS * CELL + (ROWS - 1) * GAP
	local browser = CreateFrame("Frame", nil, canvas, BackdropTemplateMixin and "BackdropTemplate" or nil)
	browser:SetSize(width, height)
	browser:SetFrameStrata("DIALOG")
	browser:EnableMouse(true)
	if browser.SetBackdrop then
		browser:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		browser:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
	end
	if ns.SkinWindow then
		ns.SkinWindow(browser, true)
	end
	browser:Hide()
	local top = 0 -- the first row shown
	local shown -- the icons in the grid: all of them, or those the find box matches
	local named -- (NamedIcons(), read each time it opens: bags and spells change)
	local nameOf -- (icon -> the first name found for it, for the mouseover)

	-- The one picked now, top left.
	local current = browser:CreateTexture(nil, "ARTWORK")
	current:SetSize(32, 32)
	current:SetPoint("TOPLEFT", EDGE, -EDGE)
	current:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local currentEdge = browser:CreateTexture(nil, "BORDER")
	currentEdge:SetPoint("TOPLEFT", current, -2, 2)
	currentEdge:SetPoint("BOTTOMRIGHT", current, 2, -2)
	currentEdge:SetColorTexture(1, 0.82, 0, 1)
	local currentText = browser:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	currentText:SetPoint("LEFT", current, "RIGHT", 8, 0)
	currentText:SetText(L["Picked now"])

	-- Find one by name, top right.
	local box = SkinnedBox(browser)
	box:SetSize(170, 20)
	box:SetAutoFocus(false)
	box:SetPoint("TOPRIGHT", -EDGE - 4, -EDGE - 6)
	local findLabel = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	findLabel:SetPoint("RIGHT", box, "LEFT", -10, 0)
	findLabel:SetText(L["Or find one:"])
	local result = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	result:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
	result:SetTextColor(1, 0.4, 0.35)
	box:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["Type part of a name to see the icons it matches: any spell, the items you " ..
			"carry and wear, mounts, or an icon's file name such as INV_Misc_Bag_07. Enter picks the first."],
			1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local function Pick(icon)
		browser:Hide()
		if browser.key ~= nil then
			onPick(browser.key, icon)
		end
	end
	-- (An exact find first: a spell or item by its whole name or ID, which
	-- needn't be yours; then the named icons and file names holding the text.)
	local function Matches(typed)
		typed = typed:match("^%s*(.-)%s*$")
		if typed == "" then
			return AllIcons()
		end
		local text = typed:lower()
		local list, seen = {}, {}
		local function Add(icon)
			if icon and not seen[Key(icon)] then
				seen[Key(icon)] = true
				list[#list + 1] = icon
			end
		end
		local exact = ns.FindIcon and ns.FindIcon(typed)
		if type(exact) == "number" then
			Add(exact)
			if nameOf and not tonumber(typed) then
				nameOf[exact] = nameOf[exact] or typed
			end
		end
		for _, entries in ipairs({ named or {}, spellList }) do
			for _, entry in ipairs(entries) do
				if entry[1]:find(text, 1, true) then
					Add(entry[2])
				end
			end
		end
		browser.partial = not scanDone -- (more may come: looked again when the scan ends)
		for _, icon in ipairs(AllIcons()) do
			if type(icon) == "string" and icon:lower():match("[^\\/]*$"):find(text, 1, true) then
				Add(icon)
			end
		end
		return list
	end
	-- (Enter: the first match, or failing any, a file name or path typed whole.)
	box:SetScript("OnEnterPressed", function(self)
		if not self:GetText():find("%S") then
			return
		end
		local icon = shown[1] or ns.FindIcon and ns.FindIcon(self:GetText())
		if icon then
			Pick(icon)
		end
	end)
	box:SetScript("OnEscapePressed", function() browser:Hide() end)

	-- The grid: ROWS of COLUMNS buttons, showing the rows from top on.
	local cells = {}
	for row = 0, ROWS - 1 do
		for column = 0, COLUMNS - 1 do
			local cell = CreateFrame("Button", nil, browser)
			cell:SetSize(CELL, CELL)
			cell:SetPoint("TOPLEFT", EDGE + column * (CELL + GAP), -EDGE - HEADER - row * (CELL + GAP))
			cell.border = cell:CreateTexture(nil, "BACKGROUND")
			cell.border:SetAllPoints()
			cell.icon = cell:CreateTexture(nil, "ARTWORK")
			cell.icon:SetPoint("TOPLEFT", 2, -2)
			cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
			cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			local hl = cell:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(cell.icon)
			hl:SetColorTexture(1, 1, 1, 0.2)
			cell:SetScript("OnClick", function(self)
				if self.file then Pick(self.file) end
			end)
			-- (Its name on the mouseover: one of yours, a spell's that uses it,
			-- else its file name; none for an icon no spell uses, or before the
			-- scan reaches it.)
			cell:SetScript("OnEnter", function(self)
				local file = self.file
				local name = file and (nameOf and nameOf[Key(file)] or spellNames[Key(file)])
					or type(file) == "string" and file:match("[^\\/]*$")
				if name then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(name, 1, 1, 1)
					GameTooltip:Show()
				end
			end)
			cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
			cells[#cells + 1] = cell
		end
	end

	local function RowCount()
		return math.ceil(#shown / COLUMNS)
	end
	local function MaxTop()
		return math.max(0, RowCount() - ROWS)
	end

	local slider = CreateFrame("Slider", nil, browser)
	slider:SetOrientation("VERTICAL")
	slider:SetWidth(SCROLL_W)
	slider:SetPoint("TOPRIGHT", -EDGE, -EDGE - HEADER)
	slider:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.5)
	slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	slider:SetValueStep(1)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

	local function Draw()
		for i, cell in ipairs(cells) do
			local file = shown[top * COLUMNS + i]
			cell.file = file
			if file then
				cell.icon:SetTexture(file)
				if Same(file, browser.current) then
					cell.border:SetColorTexture(1, 0.82, 0, 1)
				else
					cell.border:SetColorTexture(0.25, 0.22, 0.15, 1)
				end
				cell:Show()
			else
				cell:Hide()
			end
		end
	end
	local function ScrollTo(row)
		top = math.max(0, math.min(MaxTop(), math.floor(row + 0.5)))
		if math.floor(slider:GetValue() + 0.5) ~= top then
			slider:SetValue(top)
		end
		Draw()
	end
	slider:SetScript("OnValueChanged", function(_, value) ScrollTo(value) end)
	browser:EnableMouseWheel(true)
	browser:SetScript("OnMouseWheel", function(_, delta)
		ScrollTo(top - delta * (IsShiftKeyDown() and ROWS or 2))
	end)

	-- The grid narrows to what the find box matches as you type.
	local function Show(list)
		shown = list
		slider:SetMinMaxValues(0, MaxTop())
		ScrollTo(0)
	end
	box:SetScript("OnTextChanged", function(self, typed)
		if not typed then
			return -- (set by us on opening)
		end
		Show(Matches(self:GetText()))
		result:SetText(#shown == 0 and L["None found"] or "")
	end)

	-- Closes on a click anywhere else.
	browser:SetScript("OnUpdate", function(self)
		if self.partial and scanDone then
			self.partial = nil
			local row = top
			Show(Matches(box:GetText()))
			ScrollTo(row)
			result:SetText(#shown == 0 and L["None found"] or "")
		end
		if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver())
			and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
			self:Hide()
		end
	end)

	-- (Clicking the same one again closes it.)
	function browser:Open(owner, key, picked)
		if self:IsShown() and self.key == key then
			self:Hide()
			return
		end
		self.owner, self.key, self.current = owner, key, picked
		current:SetTexture(picked or "Interface\\Icons\\INV_Misc_QuestionMark")
		self.partial = nil
		named, nameOf = NamedIcons(), {}
		for _, entry in ipairs(named) do
			nameOf[Key(entry[2])] = nameOf[Key(entry[2])] or entry[3]
		end
		StartSpellScan()
		box:SetText("")
		result:SetText("")
		shown = AllIcons()
		slider:SetMinMaxValues(0, MaxTop())
		-- (Scrolled to the one picked now, when it's in the list.)
		local row = 0
		for i, icon in ipairs(AllIcons()) do
			if Same(icon, picked) then
				row = math.floor((i - 1) / COLUMNS) - math.floor(ROWS / 2)
				break
			end
		end
		ScrollTo(row)
		-- (Below it, or above when that runs off the page; leftwards near the right edge.)
		local scale = owner:GetEffectiveScale() / self:GetEffectiveScale()
		local left, bottom = (owner:GetLeft() or 0) * scale, (owner:GetBottom() or 0) * scale
		local rightward = left + self:GetWidth() <= (canvas:GetRight() or math.huge)
		local downward = bottom - self:GetHeight() - 2 >= (canvas:GetBottom() or 0)
		local upward = (owner:GetTop() or 0) * scale + self:GetHeight() + 2 <= (canvas:GetTop() or math.huge)
		self:ClearAllPoints()
		if downward or upward then
			self:SetPoint((downward and "TOP" or "BOTTOM") .. (rightward and "LEFT" or "RIGHT"), owner,
				(downward and "BOTTOM" or "TOP") .. (rightward and "LEFT" or "RIGHT"), 0, downward and -2 or 2)
		else
			self:SetPoint("CENTER", canvas, "CENTER") -- (room neither way: the middle of the page)
		end
		self:Show()
	end
	return browser
end
