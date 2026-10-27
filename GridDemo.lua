-- The dev build's Grid Demo page: some frames-grid rows done the new way, to
-- see how it looks before the real pages change. Always, then a dropdown per
-- group (each ticked item shows the row: they're all joined by OR), the
-- roles (AND NOT the unticked ones, as the real grid's roles: none ticked,
-- hidden whatever your role), a dot for whether it shows right now, and an Edit button that
-- swaps the dropdowns for the row's rule as text, edited in a window of its
-- own. A rule still in that shape goes back into the dropdowns; one that
-- isn't keeps the text (red), with the editor's Reset to grid to drop it
-- for the ticks the row had (closing the editor on one that reads puts it
-- back in the grid). One line a row: the rule's in the Edit
-- button's tip. A Look switch by the title shows it all flat (HD) or in
-- the game's own buttons and windows (SD), to compare. Not wired in: it keeps its own state and nothing fades by it. Options.lua calls ns.CreateGridDemo (dev build only).

local _, ns = ...

-- The groups, each a dropdown (and a line in the editor, its colour), and
-- the words their items write. Only words that add to where it shows: one
-- like Out of combat, joined by OR, would show it nearly everywhere.
-- Battlegrounds and arenas apart where there are arenas (retail: not Forever).
local SPLIT_PVP = ns.isRetail
local LOCATIONS = { { "world", "Open World" }, { "city", "City" }, { "inn", "Inn" } }
if SPLIT_PVP then
	tinsert(LOCATIONS, { "battleground", "Battlegrounds" })
	tinsert(LOCATIONS, { "arena", "Arenas" })
else
	tinsert(LOCATIONS, { "bg", "BGs & Arenas" })
end
tinsert(LOCATIONS, { "dungeon", "Dungeon" })
tinsert(LOCATIONS, { "raid", "Raid" })
tinsert(LOCATIONS, { "group", "Grouped" })
local GROUPS = {
	{ heading = "Combat", color = { 1, 0.45, 0.4 }, options = { { "combat", "In combat" },
		{ "calm", "Calm Timer" } } },
	{ heading = "Target", color = { 1, 0.65, 0.25 }, options = { { "enemy", "Enemy" }, { "friendly", "Friendly" },
		{ "target", "Any target" } } },
	{ heading = "Location", color = { 0.45, 0.75, 1 }, options = LOCATIONS },
}
local GRID_WORDS = { always = true, never = true }
for _, group in ipairs(GROUPS) do
	for _, option in ipairs(group.options) do GRID_WORDS[option[1]] = true end
end
-- The rules' other names for grid words, and the words that tick more than
-- one item: instance, and bg where arenas are apart. (The rules' arena is
-- BGs and arenas both; where they're apart, the demo's is arenas only.)
local ALIASES = { fighting = "combat", ["true"] = "always", ["false"] = "never", bgs = "bg", pvp = "bg",
	arena = not SPLIT_PVP and "bg" or nil, grouped = "group" }
local EXPANDS = { instance = { "dungeon", "raid" }, bg = SPLIT_PVP and { "battleground", "arena" } or nil }
local ROLES = { "Tank", "Healer", "Damage" }
local ROLE_COLOR = { 0.4, 0.85, 0.5 }
-- Each role's icon as text (the nameplates' role texture, pixels of its 64x64).
local ROLE_PIXELS = { Tank = { 0, 19, 22, 41 }, Healer = { 20, 39, 1, 20 }, Damage = { 20, 39, 22, 41 } }
local function RoleIcon(role, size)
	local p = ROLE_PIXELS[role]
	return ("|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:%d:%d:0:0:64:64:%d:%d:%d:%d|t")
		:format(size, size, p[1], p[2], p[3], p[4])
end

-- Text in a colour (r, g, b from 0 to 1).
local function Colored(color, text)
	return ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, text)
end

-- Words only the editor has, to keep the grid simple (a rule with one stays
-- text): the fights that narrow it down, the camera modes, and you (in a
-- party, mounted and the like). A line of buttons each.
local EDITOR_ONLY = {
	{ heading = "Fights", color = { 1, 0.45, 0.4 }, options = { { "nocombat", "Out of combat" },
		{ "pvpcombat", "PvP combat" } } },
	{ heading = "Camera", color = { 0.5, 0.9, 0.9 }, options = { { "anycam", "Any camera" }, { "flightcam", "Flight" },
		{ "idlecam", "Idle/AFK" }, { "cozycam", "Cozy" }, { "telecam", "Tele" }, { "walkcam", "Walk" },
		{ "runcam", "Run" }, { "vistacam", "Vista" }, { "fishcam", "Fish" }, { "deathcam", "Death" },
		{ "questcam", "Quest" } } },
	{ heading = "You", color = { 0.8, 0.6, 1 }, options = { { "party", "In party" },
		{ "raidgroup", "In raid group" }, { "resting", "Resting" }, { "flying", "Flying" }, { "swimming", "Swimming" },
		{ "dead", "Dead" }, { "lowhealth", "Low health" }, { "notfull", "Not full" }, { "casting", "Casting" },
		{ "gamepad", "Gamepad" }, { "flagged", "PvP flagged" }, { "mounted", "Mounted" } } },
}
local EDITOR_WORDS = {}
for _, group in ipairs(EDITOR_ONLY) do
	for _, option in ipairs(group.options) do EDITOR_WORDS[option[1]] = true end
end

-- The camera mode running now: the death, quest and tele cameras as well as
-- the ones ns.CameraMode knows.
local function CamNow()
	if ns.IsDeathCinematic and ns.IsDeathCinematic() then return "death" end
	if ns.QuestCamActive and ns.QuestCamActive() then return "quest" end
	if ns.IsTele and ns.IsTele() then return "tele" end
	return ns.CameraMode and ns.CameraMode()
end
-- When the last fight ended, for calm (the Calm Timer after it). Cut short
-- like everyone's when calmEndsAtFull ends the timer early.
local lastCombatAt = -math.huge
ns.OnCalmEnd(function(cut) lastCombatAt = math.min(lastCombatAt, cut) end)
local combatWatch = CreateFrame("Frame")
combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatch:SetScript("OnEvent", function() lastCombatAt = GetTime() end)

-- The demo's own words (the rules don't know them yet), each true or false
-- where you are now, given the rules' facts. Low health and Not full aren't
-- here: the demo can't tell.
local DEMO_FACTS = {
	nocombat = function(f) return not f.combat end,
	-- (Just the time after a fight: tick In combat as well for the fight too.)
	calm = function(f) return not f.combat and GetTime() - lastCombatAt < (ns.db.calmTime or 0) end,
	-- (The rules' bg is battlegrounds and arenas both: apart here, where there are arenas.)
	battleground = SPLIT_PVP and function(f) return f.bg and select(2, IsInInstance()) ~= "arena" end or nil,
	arena = SPLIT_PVP and function(f) return f.bg and select(2, IsInInstance()) == "arena" end or nil,
	pvpcombat = function(f) return f.combat and (f.bg or f.flagged) end,
	anycam = function() return CamNow() ~= nil end,
	party = function() return ns.Flag(IsInGroup()) and not ns.Flag(IsInRaid()) end,
	raidgroup = function() return ns.Flag(IsInRaid()) end,
	resting = function() return ns.Flag(IsResting()) end,
	flying = function() return IsFlying and ns.Flag(IsFlying()) end,
	swimming = function() return _G.IsSwimming and ns.Flag(_G.IsSwimming()) end,
	dead = function() return ns.Flag(UnitIsDeadOrGhost("player")) end,
	casting = function()
		local ok, casting = pcall(function()
			return UnitCastingInfo("player") ~= nil or (UnitChannelInfo and UnitChannelInfo("player") ~= nil)
		end)
		return ok and ns.Flag(casting)
	end,
	gamepad = function() return ns.IsGamePadOn and ns.IsGamePadOn() end,
}
for _, mode in ipairs({ "flight", "idle", "cozy", "tele", "walk", "run", "vista", "fish", "death", "quest" }) do
	DEMO_FACTS[mode .. "cam"] = function() return CamNow() == mode end
end
-- Whether a word's true now (nil: the demo can't tell).
local function WordTrue(word, facts)
	local fact = DEMO_FACTS[word]
	if fact then return fact(facts) and true or false end
	local field = ns.RULE_WORDS and ns.RULE_WORDS[word]
	if field then return facts[field] and true or false end
end
-- What a rule gives where you are now: true or false; or nil, why not and
-- whether that's a word the demo can't tell (the rest: it doesn't read).
local function RuleNow(text, facts)
	if not ns.CompileRule then return nil, "" end
	-- (The demo's own words as always or never, as they are now, for the rules to read.)
	local unknown
	local readable = text:gsub("[%w_]+", function(w)
		w = w:lower()
		local fact = DEMO_FACTS[w]
		if fact then return fact(facts) and "always" or "never" end
		if EDITOR_WORDS[w] and not (ns.RULE_WORDS and ns.RULE_WORDS[w]) then unknown = unknown or w end
	end)
	if unknown then return nil, ("the demo can't tell \"%s\""):format(unknown), true end
	local test, err = ns.CompileRule(readable)
	if not test then return nil, err end
	return test(facts) and true or false
end
-- The facts for where you are now; nil before the settings load.
local function FactsNow()
	return ns.db and ns.RuleFactsNow and ns.RuleFactsNow()
end

local LABEL_W, ALWAYS_W, MENU_W, ROLES_W, RULE_W, GAP = 120, 40, 112, 50, 44, 2
local ROW_H = 24

-- A button for the rows and the editor (ns.PanelButton: both looks, as the
-- main page's Menu look says), small text: left with an arrow at the right
-- for a menu's, else centred. The arrow greys while disabled.
local function FlatButton(parent, width, arrow)
	local button = ns.PanelButton(parent)
	button:SetSize(width, 20)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetWordWrap(false)
	button:SetFontString(text)
	button:SetNormalFontObject("GameFontHighlightSmall")
	button:SetDisabledFontObject("GameFontDisableSmall")
	text:ClearAllPoints()
	if arrow then
		text:SetPoint("LEFT", 6, 0)
		text:SetPoint("RIGHT", -16, 0)
		text:SetJustifyH("LEFT")
		button.arrow = button:CreateTexture(nil, "OVERLAY")
		button.arrow:SetSize(14, 14)
		button.arrow:SetPoint("RIGHT", -2, -2)
		button.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
		button:HookScript("OnDisable", function(self)
			self.arrow:SetDesaturated(true)
			self.arrow:SetAlpha(0.4)
		end)
		button:HookScript("OnEnable", function(self)
			self.arrow:SetDesaturated(false)
			self.arrow:SetAlpha(1)
		end)
	else
		text:SetPoint("LEFT", 4, 0)
		text:SetPoint("RIGHT", -4, 0)
		text:SetJustifyH("CENTER")
	end
	return button
end

-- The role words (aliases too) and the roles they stand for.
local ROLE_WORDS = { tank = "Tank", healer = "Healer", heal = "Healer", damage = "Damage", dps = "Damage" }

-- Each word's colour: its group's, as in the dropdowns and the editor
-- (aliases too); always and never gold, the logic words grey.
local WORD_COLOR = { always = { 1, 0.82, 0 }, never = { 1, 0.82, 0 } }
for _, list in ipairs({ GROUPS, EDITOR_ONLY }) do
	for _, group in ipairs(list) do
		for _, option in ipairs(group.options) do WORD_COLOR[option[1]] = group.color end
	end
end
for word in pairs(ROLE_WORDS) do WORD_COLOR[word] = ROLE_COLOR end
for alias, word in pairs(ALIASES) do WORD_COLOR[alias] = WORD_COLOR[word] end
for word, into in pairs(EXPANDS) do WORD_COLOR[word] = WORD_COLOR[into[1]] end
local LOGIC_COLOR, UNKNOWN_COLOR = { 0.7, 0.7, 0.7 }, { 1, 0.38, 0.38 }
-- A rule's text with each word in its colour (one it doesn't know red), for
-- showing: the row in text mode and the tips.
local function ColoredRule(text)
	-- (A word, then what's up to the next: spaces, brackets and signs, grey
	-- like the logic words, a | doubled to show as one.)
	return (text:gsub("([%w_]*)([^%w_]*)", function(word, between)
		local lower = word:lower()
		local color = (lower == "and" or lower == "or" or lower == "not") and LOGIC_COLOR
			or WORD_COLOR[lower] or UNKNOWN_COLOR
		word = word ~= "" and Colored(color, word) or ""
		between = between:find("%S") and Colored(LOGIC_COLOR, (between:gsub("|", "||"))) or between
		return word .. between
	end))
end

-- The ticks as a rule: "always", or each group's words joined by OR (a
-- group of two or more in brackets), "never" with nothing ticked. Then,
-- unless every role's ticked, AND NOT the unticked ones (hidden while
-- you're that role, as the real grid has it: no role, it still shows):
-- "(combat or city) and not damage".
local function GridRule(state)
	local body
	if state.always then
		body = "always"
	else
		local parts = {}
		for _, group in ipairs(GROUPS) do
			local words = {}
			-- (A word ticking more than one item, in place of them all ticked: bg.)
			local joined = {}
			for word, into in pairs(EXPANDS) do
				local all = word ~= "instance" -- (dungeon or raid stays as it is)
				for _, each in ipairs(into) do all = all and state.ticked[each] end
				if all then for _, each in ipairs(into) do joined[each] = word end end
			end
			for _, option in ipairs(group.options) do
				local word = option[1]
				if state.ticked[word] then
					local as = joined[word] or word
					if as == word or as ~= words[#words] then words[#words + 1] = as end
				end
			end
			if #words == 1 then
				parts[#parts + 1] = words[1]
			elseif #words > 1 then
				parts[#parts + 1] = "(" .. table.concat(words, " or ") .. ")"
			end
		end
		body = #parts > 0 and table.concat(parts, " or ") or "never"
	end
	local hides = {}
	for _, role in ipairs(ROLES) do
		if not state.roles[role] then hides[#hides + 1] = role:lower() end
	end
	if #hides == 0 or body == "never" then return body end
	if body:find(" or ") then body = "(" .. body .. ")" end
	return body .. " and not " .. (#hides == 1 and hides[1] or "(" .. table.concat(hides, " or ") .. ")")
end

-- The words of tokens[first..last], when they're words joined by OR
-- (brackets anywhere, matched); or nil and why not.
local function OrList(tokens, first, last)
	local words, depth, n = {}, 0, 0
	for i = first, last do
		local token = tokens[i]
		if token == "(" then
			depth = depth + 1
		elseif token == ")" then
			depth = depth - 1
			if depth < 0 then return nil, "a ) has no (" end
		elseif token == "and" then
			return nil, "an AND inside brackets"
		elseif token == "not" then
			return nil, "NOT only fits as AND NOT the roles"
		else
			-- (Words and ORs take turns, a word first and last.)
			n = n + 1
			if (n % 2 == 1) == (token == "or") then return nil, "it isn't finished" end
			if token ~= "or" then words[#words + 1] = token end
		end
	end
	if depth ~= 0 then return nil, "a ( has no )" end
	if n % 2 == 0 then return nil, n == 0 and "it's empty" or "it isn't finished" end
	return words
end

-- Whether tokens[first..last] has an OR outside brackets (beside an AND,
-- it'd bind the wrong way: "combat or city and tank").
local function LooseOr(tokens, first, last)
	local depth = 0
	for i = first, last do
		local token = tokens[i]
		depth = depth + (token == "(" and 1 or token == ")" and -1 or 0)
		if depth == 0 and token == "or" then return true end
	end
	return false
end

-- A rule read back into the row: grid words joined by OR (brackets
-- allowed), and at most one AND, followed by NOT and roles joined by OR.
-- Gives always, ticked, roles (nil without a roles part); or nil and why not.
local function ReadGrid(text)
	local tokens = {}
	local i = 1
	while i <= #text do
		local c = text:sub(i, i)
		if c:find("%s") then
			i = i + 1
		elseif c == "(" or c == ")" then
			tokens[#tokens + 1] = c
			i = i + 1
		elseif c == "!" then
			tokens[#tokens + 1] = "not"
			i = i + 1
		elseif c == "&" or c == "|" then
			local run = text:match("^[&|]+", i)
			tokens[#tokens + 1] = c == "&" and "and" or "or"
			i = i + #run
		else
			local word = text:match("^[%w_]+", i)
			if not word then return nil, ("can't read \"%s\""):format(c) end
			i = i + #word
			word = word:lower()
			word = ALIASES[word] or word
			if word ~= "and" and word ~= "or" and word ~= "not" and not GRID_WORDS[word] and not ROLE_WORDS[word]
				and not EXPANDS[word] then
				return nil, (EDITOR_WORDS[word] and "\"%s\" is only in the editor" or "\"%s\" isn't in the grid"):format(word)
			end
			tokens[#tokens + 1] = word
		end
	end
	-- The ANDs outside brackets: none, or one beside the roles.
	local ands, depth = {}, 0
	for n, token in ipairs(tokens) do
		depth = depth + (token == "(" and 1 or token == ")" and -1 or 0)
		if depth < 0 then return nil, "a ) has no (" end
		if depth == 0 and token == "and" then ands[#ands + 1] = n end
	end
	if #ands > 1 then return nil, "only one AND fits the grid (for the roles)" end
	local body, hideWords, err
	if #ands == 0 then
		body, err = OrList(tokens, 1, #tokens)
		if not body then return nil, err end
	else
		local at = ands[1]
		-- (The roles after AND NOT: "and not (tank or damage)".)
		local negated = tokens[at + 1] == "not"
		local rolesFrom = negated and at + 2 or at + 1
		if LooseOr(tokens, 1, at - 1) or LooseOr(tokens, rolesFrom, #tokens) then
			return nil, "what's beside AND needs brackets round it"
		end
		local right
		body, err = OrList(tokens, 1, at - 1)
		if not body then return nil, err end
		right, err = OrList(tokens, rolesFrom, #tokens)
		if not right then return nil, err end
		for _, word in ipairs(right) do
			if not ROLE_WORDS[word] then return nil, "only roles fit after the AND, as AND NOT the roles" end
		end
		if not negated then
			return nil, "the grid's roles are AND NOT the ones it's hidden for, like (...) and not damage"
		end
		hideWords = right
	end
	local always, ticked, roles = false, {}, {}
	for _, word in ipairs(body) do
		if ROLE_WORDS[word] then return nil, "roles go after AND NOT, like (...) and not damage" end
		if word == "always" then
			always = true
		elseif EXPANDS[word] then
			for _, each in ipairs(EXPANDS[word]) do ticked[each] = true end
		elseif word ~= "never" then
			ticked[word] = true
		end
	end
	-- (No roles part: nil, it shows whatever your role.)
	if not hideWords then return always, ticked, nil end
	for _, role in ipairs(ROLES) do roles[role] = true end
	for _, word in ipairs(hideWords) do roles[ROLE_WORDS[word]] = nil end
	return always, ticked, roles
end

function ns.CreateGridDemo(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local Label, Tooltip = kit.Label, kit.Tooltip

	local title = Label(content, "GameFontNormalLarge", "Grid Demo")
	title:SetPoint("TOPLEFT", 16, -16)
	-- The look, by the title: HD or SD tried everywhere (ns.PreviewMenuSkin)
	-- while this page shows, the one on lit (white), the other grey.
	local lookLabel = Label(content, "GameFontNormalSmall", "Look")
	lookLabel:SetPoint("LEFT", title, "RIGHT", 24, 0)
	local looks = {}
	local function ShowLooks()
		for name, button in pairs(looks) do
			button:SetText(name == ns.CurrentMenuSkin() and name or "|cff808080" .. name .. "|r")
		end
	end
	for i, look in ipairs({ { "HD", "The new look: flat, dark buttons with a thin edge in their group's colour." },
		{ "SD", "The old look: the game's own buttons and windows." } }) do
		local button = FlatButton(content, 36)
		button:SetPoint("LEFT", lookLabel, "RIGHT", 6 + (i - 1) * 40, 0)
		button:SetScript("OnClick", function()
			ns.PreviewMenuSkin(look[1])
			ShowLooks()
		end)
		Tooltip(button, look[2] .. " Tried on every page and window till you leave this one, then back to " ..
			"the main page's Menu look.")
		looks[look[1]] = button
	end
	local intro = Label(content, "GameFontHighlightSmall",
		"Some rows done the new way (not wired in: nothing fades by it). Each dropdown's ticks show the row, " ..
		"all joined by OR, then AND NOT the roles you untick. The dot by a name: green, it'd show right now; " ..
		"grey, hidden. Edit shows the row as text: one still in that shape goes back into the dropdowns when " ..
		"you close it; one with other NOTs, other ANDs or editor-only words stays text until you Reset to grid.")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetWidth(580)

	-- The headings, over their columns.
	local top = CreateFrame("Frame", nil, content)
	top:SetSize(1, 1)
	top:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -30) -- (room for the headings above it)
	-- (A group's heading in its colour, as in the editor.)
	local function Heading(text, x, width, color)
		local heading = Label(content, "GameFontNormalSmall", text)
		if color then heading:SetTextColor(color[1], color[2], color[3]) end
		heading:SetWidth(width)
		heading:SetJustifyH("CENTER")
		heading:SetPoint("BOTTOMLEFT", top, "TOPLEFT", x, 2)
	end
	local x = LABEL_W
	Heading("Always", x, ALWAYS_W)
	x = x + ALWAYS_W + GAP
	for _, group in ipairs(GROUPS) do
		Heading(group.heading, x, MENU_W, group.color)
		x = x + MENU_W + GAP
	end
	local rolesX = x
	Heading("Roles", rolesX, ROLES_W, ROLE_COLOR)
	local ruleX = rolesX + ROLES_W + GAP
	Heading("Edit", ruleX, RULE_W)

	-- A row: its own ticks (kept while it's text, for Reset to grid), rule
	-- (nil in grid mode) and editor; one editor open at a time.
	local editors, updates, lives = {}, {}, {}
	local function Row(index, label, state)
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(ruleX + RULE_W, ROW_H)
		row:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -2 - (index - 1) * (ROW_H + 2))
		local band = row:CreateTexture(nil, "BACKGROUND")
		band:SetAllPoints()
		band:SetColorTexture(1, 1, 1, index % 2 == 1 and 0.05 or 0.02)
		local name = Label(row, "GameFontHighlight", label)
		name:SetPoint("LEFT", 6, 0)
		name:SetWidth(LABEL_W - 26)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		-- Whether its rule (or its ticks') shows it right now: a dot at the
		-- name's end, green or grey, none when the demo can't tell.
		local live = row:CreateTexture(nil, "OVERLAY")
		live:SetSize(10, 10)
		live:SetPoint("LEFT", LABEL_W - 16, 0)
		local hover = CreateFrame("Frame", nil, row)
		hover:SetPoint("TOPLEFT")
		hover:SetSize(LABEL_W, ROW_H)
		hover:EnableMouse(true)
		Tooltip(hover, "The dot: green, it'd show right now in CineMode; grey, it'd be hidden. None: the " ..
			"rule doesn't read yet, or has a word the demo can't tell.")
		lives[#lives + 1] = function(facts)
			local shows = facts and RuleNow(state.text or GridRule(state), facts)
			live:SetShown(shows ~= nil)
			live:SetTexture(shows and "Interface\\COMMON\\Indicator-Green" or "Interface\\COMMON\\Indicator-Gray")
		end

		local Update
		local always = ns.SkinCheck(CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate"))
		always:SetSize(22, 22)
		always:SetPoint("LEFT", LABEL_W + (ALWAYS_W - 22) / 2, 0)
		always:SetScript("OnClick", function(self)
			state.always = self:GetChecked() and true or false
			Update()
		end)
		Tooltip(always, "Shown the whole time in CineMode: the dropdowns don't matter then.")

		-- A menu of { text, checked, toggle } with one line at the top: All, or
		-- Clear once all are ticked. Kept open for ticking more (no menus on this
		-- client: a click ticks all or none).
		local function Menu(owner, entries, setAll)
			local function AllOn()
				for _, entry in ipairs(entries) do
					if not entry[2]() then return false end
				end
				return true
			end
			if not (MenuUtil and MenuUtil.CreateContextMenu) then
				setAll(not AllOn())
				Update()
				return
			end
			local keep = MenuResponse and MenuResponse.Refresh
			MenuUtil.CreateContextMenu(owner, function(_, root)
				local top = root:CreateButton(AllOn() and "Clear" or "All", function()
					setAll(not AllOn())
					Update()
					return keep
				end)
				-- (Its text again each time the menu refreshes, as ticks change it.)
				if top and top.AddInitializer then
					top:AddInitializer(function(button)
						local text = button.fontString or (button.GetFontString and button:GetFontString())
						if text then text:SetText(AllOn() and "Clear" or "All") end
					end)
				end
				root:CreateDivider()
				for _, entry in ipairs(entries) do
					root:CreateCheckbox(entry[1], entry[2], function() entry[3]() Update() return keep end)
				end
			end)
		end
		-- What a menu button says: All, None, the one ticked or how many.
		local function Summary(on, total, only)
			if on == total then return "All" end
			if on == 0 then return "|cff808080-|r" end -- (nothing ticked: the group plays no part)
			if on == 1 then return only end
			return ("%d of %d"):format(on, total)
		end

		local menus = {}
		x = LABEL_W + ALWAYS_W + GAP
		for _, group in ipairs(GROUPS) do
			local button = FlatButton(row, MENU_W, true)
			button:SetSkinEdge(group.color[1], group.color[2], group.color[3], 0.45)
			button:SetPoint("LEFT", x, 0)
			x = x + MENU_W + GAP
			local entries = {}
			for _, option in ipairs(group.options) do
				local word = option[1]
				entries[#entries + 1] = { option[2], function() return state.ticked[word] == true end,
					function() state.ticked[word] = not state.ticked[word] or nil end }
			end
			button:SetScript("OnClick", function(self)
				Menu(self, entries, function(on)
					for _, option in ipairs(group.options) do state.ticked[option[1]] = on or nil end
				end)
			end)
			button.Refresh = function(self)
				local on, only, names = 0, nil, {}
				for _, option in ipairs(group.options) do
					if state.ticked[option[1]] then
						on, only = on + 1, option[2]
						names[#names + 1] = option[2]
					end
				end
				-- (Plain while Always greys it, so it greys like the rest.)
				local summary = Summary(on, #group.options, only)
				self:SetText((on == 0 or state.always) and summary or Colored(group.color, summary))
				self:SetEnabled(not state.always)
				self.tip = #names > 0 and table.concat(names, ", ") or "Not used: nothing ticked"
			end
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(group.heading, 1, 1, 1)
				GameTooltip:AddLine(self.tip, 1, 0.82, 0, true)
				GameTooltip:AddLine("Shown while any of these is true. All (or Clear) is at the top of the menu.",
					0.8, 0.8, 0.8, true)
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			menus[#menus + 1] = button
		end

		local roles = FlatButton(row, ROLES_W, true)
		roles:SetSkinEdge(ROLE_COLOR[1], ROLE_COLOR[2], ROLE_COLOR[3], 0.45)
		roles:SetPoint("LEFT", rolesX, 0)
		local roleEntries = {}
		for _, role in ipairs(ROLES) do
			roleEntries[#roleEntries + 1] = { RoleIcon(role, 14) .. " " .. role, function() return state.roles[role] == true end,
				function() state.roles[role] = not state.roles[role] or nil end }
		end
		roles:SetScript("OnClick", function(self)
			Menu(self, roleEntries, function(on)
				for _, role in ipairs(ROLES) do state.roles[role] = on or nil end
			end)
		end)
		Tooltip(roles, "The roles it shows for: an unticked one keeps it hidden while you're that role, like " ..
			"\"(combat or city) and not damage\". None: hidden whatever your role (with no role at all, " ..
			"it still shows).")

		-- The editor: a window of its own for the row's rule as text, with a
		-- button for each piece (put in at the cursor; a green dot: true where
		-- you are now), what it gives right now and whether it reads back into
		-- the grid. Made the first time it opens; Update refreshes it.
		local editor
		local function BackToGrid()
			local isAlways, ticked, roles = ReadGrid(state.text or "")
			if isAlways == nil then return end
			-- (No roles part: it shows for them all.)
			if not roles then
				roles = {}
				for _, role in ipairs(ROLES) do roles[role] = true end
			end
			state.always, state.ticked, state.roles, state.text = isAlways, ticked, roles, nil
			if editor then editor:Hide() end
			Update()
		end
		local function ResetToGrid()
			state.text = nil
			if editor then editor:Hide() end
			Update()
		end

		local function MakeEditor()
			local EDIT_W = 560
			-- (As the addon's other windows: SD a dark dialog with a tooltip
			-- border, HD flat like the rows. ns.SkinWindow.)
			local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
			local frame = CreateFrame("Frame", "CinematicGridDemoEditor" .. index, UIParent, BACKDROP)
			frame:SetWidth(EDIT_W)
			if frame.SetBackdrop then
				frame:SetBackdrop({
					bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
					edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
					tile = true, tileSize = 16, edgeSize = 16,
					insets = { left = 4, right = 4, top = 4, bottom = 4 },
				})
			end
			ns.SkinWindow(frame)
			local close = ns.SkinClose(CreateFrame("Button", nil, frame, "UIPanelCloseButton"))
			close:SetPoint("TOPRIGHT", -2, -2)
			close:SetScript("OnClick", function() frame:Hide() end)
			frame:SetPoint("CENTER")
			frame:SetFrameStrata("DIALOG")
			frame:SetToplevel(true)
			frame:SetClampedToScreen(true)
			frame:EnableMouse(true)
			frame:SetMovable(true)
			frame:RegisterForDrag("LeftButton")
			frame:SetScript("OnDragStart", frame.StartMoving)
			frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
			tinsert(UISpecialFrames, "CinematicGridDemoEditor" .. index) -- (Escape closes it)
			local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			heading:SetPoint("TOP", 0, -10)
			heading:SetText("Rule: " .. label)

			-- The rule, a few lines' room; a click anywhere on it types there.
			local well = CreateFrame("Frame", nil, frame, BACKDROP)
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
			box:SetScript("OnEscapePressed", box.ClearFocus)
			box:SetScript("OnTextChanged", function(self, userInput)
				if userInput then
					state.text = self:GetText()
					Update()
				end
			end)
			well:SetScript("OnMouseDown", function() box:SetFocus() end)
			frame.box = box

			local reads = Label(frame, "GameFontNormalSmall", "")
			reads:SetPoint("TOPLEFT", well, "BOTTOMLEFT", 2, -6)
			reads:SetWidth(EDIT_W - 32)
			local now = Label(frame, "GameFontNormalSmall", "")
			now:SetPoint("TOPLEFT", reads, "BOTTOMLEFT", 0, -4)
			now:SetWidth(EDIT_W - 32)

			-- The pieces: put in at the cursor, spaced from what's either side.
			local function Insert(word)
				local text, pos = box:GetText(), box:GetCursorPosition()
				local before, after = text:sub(1, pos), text:sub(pos + 1)
				local lead = (before == "" or before:find("[%s(]$") or word == ")") and "" or " "
				local trail = (word ~= "(" and after:find("^[%w_(]")) and " " or ""
				box:SetText(before .. lead .. word .. trail .. after)
				box:SetCursorPosition(#before + #lead + #word)
				box:SetFocus()
				state.text = box:GetText()
				Update()
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
				state.text = box:GetText()
				Update()
			end

			local palette = CreateFrame("Frame", nil, frame)
			palette:SetPoint("TOPLEFT", now, "BOTTOMLEFT", -2, -12)
			palette:SetWidth(EDIT_W - 28)
			local LINE_X, DOT_ROOM = 70, 12
			local px, py = LINE_X, 0
			local wordButtons = {}
			-- (Flat too, in its group's colour: the text, and the edge dimmer.)
			local function Piece(text, onClick, color, dotted)
				local button = FlatButton(palette, 10)
				button:SetText(Colored(color, text))
				button:SetWidth(button:GetFontString():GetStringWidth() + 16 + (dotted and DOT_ROOM or 0))
				button:SetSkinEdge(color[1], color[2], color[3], 0.45)
				if dotted then
					button.dot = button:CreateTexture(nil, "OVERLAY")
					button.dot:SetSize(10, 10)
					button.dot:SetPoint("RIGHT", -5, 0)
					button.dot:SetTexture("Interface\\COMMON\\Indicator-Green")
					button.dot:Hide()
					button:GetFontString():SetPoint("RIGHT", -4 - DOT_ROOM, 0)
				end
				if px > LINE_X and px + button:GetWidth() > EDIT_W - 28 then
					px, py = LINE_X, py - 24
				end
				button:SetPoint("TOPLEFT", palette, "TOPLEFT", px, py)
				px = px + button:GetWidth() + 4
				button:SetScript("OnClick", onClick)
				return button
			end
			local function Line(name, color)
				if px > LINE_X then px, py = LINE_X, py - 26 end
				local heading = Label(palette, "GameFontNormalSmall", name)
				heading:SetTextColor(color[1], color[2], color[3])
				heading:SetPoint("TOPLEFT", palette, "TOPLEFT", 0, py - 6)
			end
			local WHITE, GOLD = { 1, 1, 1 }, { 1, 0.82, 0 }
			Line("Logic", WHITE)
			for _, piece in ipairs({ { "and", "AND" }, { "or", "OR" }, { "not", "NOT" }, { "(", "(" }, { ")", ")" } }) do
				Piece(piece[2], function() Insert(piece[1]) end, WHITE)
			end
			px = px + 16
			Tooltip(Piece("Undo", Undo, GOLD), "Takes off the piece before the cursor.")
			Tooltip(Piece("Clear", function()
				box:SetText("")
				box:SetFocus()
				state.text = ""
				Update()
			end, GOLD), "Empties the rule.")
			for _, group in ipairs(GROUPS) do
				Line(group.heading, group.color)
				for _, option in ipairs(group.options) do
					local word = option[1]
					local button = Piece(option[2], function() Insert(word) end, group.color, true)
					wordButtons[word] = button
					Tooltip(button, ("Adds \"%s\". A green dot: true where you are now."):format(word))
				end
			end
			-- (The roles, after AND NOT: "(...) and not (tank or damage)".)
			Line("Role", ROLE_COLOR)
			for _, role in ipairs(ROLES) do
				local word = role:lower()
				local button = Piece(RoleIcon(role, 12) .. " " .. role, function() Insert(word) end, ROLE_COLOR, true)
				wordButtons[word] = button
				Tooltip(button, ("Adds \"%s\", for after AND NOT. A green dot: you're that role now."):format(word))
			end
			-- (Then the editor's own words, under a note, set apart.)
			px, py = LINE_X, py - 30
			local apart = Label(palette, "GameFontDisableSmall", "Editor only: a rule with these stays text")
			apart:SetPoint("TOPLEFT", palette, "TOPLEFT", 0, py)
			px, py = LINE_X + 1, py + 8 -- (the next line steps down under it)
			for _, group in ipairs(EDITOR_ONLY) do
				Line(group.heading, group.color)
				for _, option in ipairs(group.options) do
					local word = option[1]
					local button = Piece(option[2], function() Insert(word) end, group.color, true)
					wordButtons[word] = button
					Tooltip(button, ("Adds \"%s\" (editor only). A green dot: true where you are now."):format(word))
				end
			end
			palette:SetHeight(-py + 22)

			-- Along the bottom: back to the grid (or reset to it), Reset and Done.
			local done = FlatButton(frame, 80)
			done:SetHeight(22)
			done:SetPoint("BOTTOMRIGHT", -14, 12)
			done:SetText("Done")
			done:SetScript("OnClick", function() frame:Hide() end)
			Tooltip(done, "Closes the editor. A rule that reads back goes into the dropdowns; one that can't stays text.")
			-- Reset: the text back to what the row's ticks give, still editing.
			local resetText = FlatButton(frame, 80)
			resetText:SetHeight(22)
			resetText:SetPoint("RIGHT", done, "LEFT", -6, 0)
			resetText:SetText("Reset")
			resetText:SetScript("OnClick", function()
				local text = GridRule(state)
				box:SetText(text)
				box:SetFocus()
				box:SetCursorPosition(#text)
				state.text = text
				Update()
			end)
			resetText:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText("Reset", 1, 1, 1)
				GameTooltip:AddLine("Puts the rule back to what the row's ticks give:", 0.8, 0.8, 0.8, true)
				GameTooltip:AddLine(ColoredRule(GridRule(state)), 1, 1, 1, true)
				GameTooltip:Show()
			end)
			resetText:SetScript("OnLeave", GameTooltip_Hide)
			local back = FlatButton(frame, 110)
			back:SetHeight(22)
			back:SetPoint("BOTTOMLEFT", 14, 12)
			back:SetText("Back to grid")
			back:SetScript("OnClick", BackToGrid)
			Tooltip(back, "Its words go back into the dropdowns.")
			local resetGrid = FlatButton(frame, 110)
			resetGrid:SetHeight(22)
			resetGrid:SetPoint("BOTTOMLEFT", 14, 12)
			resetGrid:SetText("Reset to grid")
			resetGrid:SetScript("OnClick", ResetToGrid)
			Tooltip(resetGrid, "Drops the text: the row goes back to the ticks it had before you edited it.")
			frame:SetHeight(34 + 64 + 6 + 32 + 12 + palette:GetHeight() + 50)

			function frame.Refresh()
				local text = state.text or ""
				if not box:HasFocus() then box:SetText(text) end
				local isAlways, why = ReadGrid(text)
				back:SetShown(isAlways ~= nil)
				resetGrid:SetShown(isAlways == nil)
				reads:SetText(isAlways ~= nil and "|cff60ff60Reads back into the grid.|r"
					or "|cffff6060Can't go back to the grid: " .. why .. ". Reset to grid drops it.|r")
				local facts = FactsNow()
				for word, button in pairs(wordButtons) do
					button.dot:SetShown(facts and WordTrue(word, facts) and true or false)
				end
				if not facts then
					now:SetText("")
					return
				end
				local shows, err, unknown = RuleNow(text, facts)
				if not text:find("%S") then
					now:SetText("|cff999999Empty.|r")
				elseif unknown then
					now:SetText("|cff999999Right now: " .. err .. ".|r")
				elseif shows == nil then
					now:SetText("|cffff6060Not finished: " .. err .. ".|r")
				else
					now:SetText(shows and "|cff60ff60Right now: shown|r" or "|cffffd100Right now: hidden|r")
				end
			end
			local since = 0
			frame:SetScript("OnUpdate", function(_, elapsed)
				since = since + elapsed
				if since > 0.5 then since = 0 frame.Refresh() end
			end)
			-- (Closed any way, Done, X, Escape or the page going: a rule that
			-- reads back goes into the dropdowns.)
			frame:SetScript("OnHide", function()
				box:ClearFocus()
				if state.text and ReadGrid(state.text) ~= nil then BackToGrid() end
			end)
			return frame
		end
		local function OpenEditor()
			editor = editor or MakeEditor()
			for _, other in pairs(editors) do
				if other ~= editor then other:Hide() end -- (its own, hidden, would go back to the grid)
			end
			editors[index] = editor
			editor:Show()
			editor.box:SetText(state.text or "")
			editor.box:SetFocus()
			editor.box:SetCursorPosition(#(state.text or ""))
			Update()
		end

		-- Text mode: the rule, where Always and the dropdowns were; a click opens the editor.
		-- (Its words in their groups' colours; the edge red while it can't go back to the grid: the tip says why.)
		local ruleText = FlatButton(row, ALWAYS_W + #GROUPS * (MENU_W + GAP) + ROLES_W) -- (the roles' room too)
		ruleText:SetPoint("LEFT", LABEL_W, 0)
		ruleText:GetFontString():SetJustifyH("LEFT")
		ruleText:SetScript("OnClick", OpenEditor)
		ruleText:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Rule", 1, 1, 1)
			GameTooltip:AddLine(ColoredRule(state.text or ""), 1, 1, 1, true)
			local isAlways, why = ReadGrid(state.text or "")
			if isAlways == nil then
				GameTooltip:AddLine("Can't go back to the grid: " .. why .. ".", 1, 0.38, 0.38, true)
			end
			GameTooltip:AddLine("Click to open the editor.", 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		ruleText:SetScript("OnLeave", GameTooltip_Hide)

		local rule = FlatButton(row, RULE_W)
		rule:SetPoint("LEFT", ruleX, 0)
		if rule.SetMotionScriptsWhileDisabled then rule:SetMotionScriptsWhileDisabled(true) end -- (its tip says why)
		rule:SetScript("OnClick", function()
			if state.text then
				BackToGrid()
			else
				state.text = GridRule(state)
				OpenEditor()
			end
		end)
		rule:SetScript("OnEnter", function(self)
			-- (Just the rule; in text mode, why it can't go back, if it can't.)
			local isAlways, why = ReadGrid(state.text or "")
			if not state.text then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(ColoredRule(GridRule(state)), 1, 1, 1, 1, true)
				GameTooltip:Show()
			elseif isAlways == nil then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText("Can't go back to the grid: " .. why .. ".", 1, 0.38, 0.38, 1, true)
				GameTooltip:Show()
			end
		end)
		rule:SetScript("OnLeave", GameTooltip_Hide)

		function Update()
			local text = state.text
			always:SetShown(not text)
			roles:SetShown(not text)
			always:SetChecked(state.always)
			for _, button in ipairs(menus) do
				button:SetShown(not text)
				button:Refresh()
			end
			ruleText:SetShown(text ~= nil)
			local on = {}
			for _, role in ipairs(ROLES) do
				if state.roles[role] then on[#on + 1] = RoleIcon(role, 13) end
			end
			roles:SetText(#on == 0 and "|cffff6060None|r" or #on == #ROLES and Colored(ROLE_COLOR, "All") or table.concat(on))
			local canGoBack = not text or ReadGrid(text) ~= nil
			ruleText:SetText(text and ColoredRule(text) or "")
			ruleText:SetSkinTint(not canGoBack and 1 or nil, 0.45, 0.45)
			rule:SetText(text and "Grid" or "Edit")
			rule:SetEnabled(canGoBack)
			if editor and editor:IsShown() then editor.Refresh() end
			lives[index](FactsNow())
		end
		Update()
		updates[#updates + 1] = Update
	end

	-- Rows as the frames pages might have them (Buffs, Quest tracker and
	-- Party frames rules that can't be a grid): name, ticks, roles (all
	-- without), Always, rule.
	local ROWS = {
		{ "Minimap", { combat = true, city = true, inn = true, raid = true } },
		{ "Player frame", { combat = true, calm = true, enemy = true, friendly = true } },
		{ "Target frame", { target = true } },
		{ "Action bars", { combat = true, dungeon = true, raid = true }, { Tank = true, Healer = true } },
		{ "Chat", {}, nil, true },
		{ "Buffs", { combat = true }, nil, nil, "(combat or raid) and not mounted" },
		{ "Quest tracker", { world = true }, nil, nil, "world and nocombat" },
		{ "Party frames", { group = true }, nil, nil, "group and healer" },
		{ "Raid frames", { raid = true, bg = true } },
		{ "Cast bar", { combat = true } },
		{ "Micro menu", {} },
		{ "Bags", {} },
	}
	for i, each in ipairs(ROWS) do
		local roles = each[3]
		if not roles then
			roles = {}
			for _, role in ipairs(ROLES) do roles[role] = true end
		end
		-- (bg ticks both, where they're apart.)
		local ticked = each[2]
		for word, into in pairs(EXPANDS) do
			if ticked[word] then
				ticked[word] = nil
				for _, item in ipairs(into) do ticked[item] = true end
			end
		end
		Row(i, each[1], { always = each[4] or false, ticked = ticked, roles = roles, text = each[5] })
	end

	canvas:SetScript("OnShow", kit.PageShown(function()
		-- (Opens in the main page's Menu look; the switch here is to compare.)
		ns.PreviewMenuSkin(nil)
		ShowLooks()
		for _, update in ipairs(updates) do update() end
	end, content))
	-- (The rows' dots kept up while the page shows.)
	local ticker = CreateFrame("Frame", nil, canvas)
	local since = 0
	ticker:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < 0.5 then return end
		since = 0
		local facts = FactsNow()
		for _, live in ipairs(lives) do live(facts) end
	end)
	-- (The editors go with the page.)
	canvas:HookScript("OnHide", function()
		ns.PreviewMenuSkin(nil) -- (a look tried here ends with the page)
		for _, editor in pairs(editors) do editor:Hide() end
	end)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Grid Demo", "Grid Demo")
end
