-- Combat Vision's sounds: rules, each for entering or leaving combat, with a
-- condition in the rules' words (boss, raid, cinemode...; none: any fight)
-- and a list of sounds. As a fight starts or ends, the first rule that fits
-- plays one of its sounds at random (not the one it played last), at its own
-- volume times the cue volume. The sounds: CombatSounds.lua.
--
-- Volume: the game can't play one sound quieter than another, so a cue plays
-- on the Ambience channel with that channel's volume set for it, then put
-- back (the setting combatHeldAmbience keeps it meanwhile, so a crash or logout mid-cue
-- still gets it back). With ambient sound off, a cue plays as a sound effect
-- at the game's own volume.

local _, ns = ...
local L = ns.L

-- The rules, saved as text so profiles and shared strings carry them: rules
-- apart by ";", each "<in|out>#<condition>#<id>@<volume %>,...".
ns.DEFAULTS.combatSounds = "in#boss#233484@60,316724@60,316723@60;in##700@100;out##698@100"
ns.DEFAULTS.combatCueVolume = 0.8

local SOUND = {} -- id -> its entry in ns.COMBAT_SOUNDS
for _, entry in ipairs(ns.COMBAT_SOUNDS or {}) do SOUND[entry[1]] = entry end
ns.COMBAT_SOUND = SOUND

-- Text -> { { edge = "in"|"out", rule = text, sounds = { { id, volume 0-1 }... } }... }
function ns.ParseCombatSounds(text)
	local rules = {}
	for chunk in (text or ""):gmatch("[^;]+") do
		local edge, rule, list = chunk:match("^(%a+)#([^#]*)#(.*)$")
		if edge == "in" or edge == "out" then
			local sounds = {}
			for id, volume in list:gmatch("(%d+)@(%d+)") do
				sounds[#sounds + 1] = { tonumber(id), math.min(100, tonumber(volume)) / 100 }
			end
			rules[#rules + 1] = { edge = edge, rule = rule, sounds = sounds }
		end
	end
	return rules
end

function ns.FormatCombatSounds(rules)
	local parts = {}
	for _, rule in ipairs(rules) do
		local sounds = {}
		for _, sound in ipairs(rule.sounds) do
			sounds[#sounds + 1] = sound[1] .. "@" .. math.floor(sound[2] * 100 + 0.5)
		end
		local condition = (rule.rule or ""):gsub("[#;]", "")
		parts[#parts + 1] = rule.edge .. "#" .. condition .. "#" .. table.concat(sounds, ",")
	end
	return table.concat(parts, ";")
end

-- Sounds cut or volumes jumped at once click (the wave jumps to nothing), so
-- both fade: a sound stopped fades out over FADE_MS, the Ambience volume
-- eases back over RAMP seconds.
local FADE_MS, CUT_MS, RAMP, RAMP_STEPS = 300, 120, 0.3, 6

-- The Ambience volume, held for a cue and put back after it (eased back;
-- at once as you log out). A new cue stops the easing (rampToken).
local restoreAt, rampToken = 0, 0
local function Restore(atOnce)
	local held = ns.db and ns.db.combatHeldAmbience
	if not held then
		return
	end
	rampToken = rampToken + 1
	local from, to = tonumber(GetCVar("Sound_AmbienceVolume")), tonumber(held)
	if atOnce or not (from and to) then
		pcall(SetCVar, "Sound_AmbienceVolume", held)
		ns.db.combatHeldAmbience = nil
		return
	end
	local token = rampToken
	for step = 1, RAMP_STEPS do
		C_Timer.After(RAMP * step / RAMP_STEPS, function()
			if token ~= rampToken then return end -- (another cue took it)
			if step == RAMP_STEPS then
				pcall(SetCVar, "Sound_AmbienceVolume", held)
				ns.db.combatHeldAmbience = nil
			else
				pcall(SetCVar, "Sound_AmbienceVolume", ("%.3f"):format(from + (to - from) * step / RAMP_STEPS))
			end
		end)
	end
end
local function RestoreWhenDone()
	if GetTime() >= restoreAt - 0.05 then Restore() end
end

-- Plays sound id at volume (0-1, times the cue volume and your sound
-- effects' volume). The one playing before fades out quickly: one cue sound
-- at a time. And each fades out as its length is up (CombatSounds.lua):
-- some of the game's sounds loop, and would go on for ever.
local playing -- (its handle)
local function Stop(fadeMs)
	if playing then
		pcall(StopSound, playing, fadeMs)
		playing = nil
	end
end
local function Start(id, channel, seconds)
	Stop(CUT_MS)
	local ok, willPlay, handle = pcall(PlaySound, id, channel)
	if ok and willPlay and handle then
		playing = handle
		C_Timer.After(math.max(0, seconds - 0.15), function()
			if playing == handle then Stop(FADE_MS) end
		end)
	end
end
function ns.PlayCombatSound(id, volume)
	local entry = SOUND[id]
	local seconds = entry and entry[4] or 3
	local db = ns.db
	if GetCVar("Sound_EnableAmbience") ~= "1" then
		Start(id, "SFX", seconds)
		return
	end
	local effects = tonumber(GetCVar("Sound_SFXVolume")) or 1
	local level = math.max(0, math.min(1, (db.combatCueVolume or 1) * (volume or 1) * effects))
	if not db.combatHeldAmbience then db.combatHeldAmbience = GetCVar("Sound_AmbienceVolume") end
	rampToken = rampToken + 1 -- (an easing back still going: stopped, this cue's level instead)
	pcall(SetCVar, "Sound_AmbienceVolume", ("%.2f"):format(level))
	Start(id, "Ambience", seconds)
	-- (Eased back once this one has faded out: the one before stopped.)
	local done = seconds - 0.15 + FADE_MS / 1000 + 0.05
	restoreAt = GetTime() + done
	C_Timer.After(done + 0.05, RestoreWhenDone)
end

-- The first rule for edge ("enter" or "leave") that fits now (its condition
-- read with the rules' entering or leaving true, and cinemode as cine says).
local lastPlayed = {} -- rule's place -> the id it played last
local function Pick(edge, cine)
	local rules = ns.ParseCombatSounds(ns.db.combatSounds)
	local side = edge == "enter" and "in" or "out"
	ns.combatEdge, ns.combatEdgeCine = edge, cine
	local ok, facts = pcall(ns.RuleFactsNow)
	ns.combatEdge = nil
	for place, rule in ipairs(rules) do
		if rule.edge == side then
			local fits = not rule.rule:find("%S")
			if not fits and ok then
				local test = ns.CompileRule(rule.rule)
				fits = test and test(facts) and true or false
			end
			if fits then
				local sounds = rule.sounds
				if #sounds == 0 then return nil end -- (a rule with none: silence)
				local i = math.random(#sounds)
				if #sounds > 1 and sounds[i][1] == lastPlayed[place] then i = i % #sounds + 1 end
				lastPlayed[place] = sounds[i][1]
				return sounds[i]
			end
		end
	end
end

-- The sound for a fight starting or ending, a moment later (so a boss's
-- frames are up to tell it's a boss fight).
function ns.PlayCombatCueSound(edge, cine)
	C_Timer.After(0.25, function()
		local sound = Pick(edge, cine)
		if sound then ns.PlayCombatSound(sound[1], sound[2]) end
	end)
end

-- A cue's Ambience volume left held by a crash or reload mid-cue: back now;
-- and given back as you log out.
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_ENTERING_WORLD")
guard:RegisterEvent("PLAYER_LOGOUT")
guard:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then self:UnregisterEvent(event) end
	if ns.db then Restore(true) end
end)

-- The page's part: the cue volume, the rules (each its condition, its
-- sounds with their volume, a play and remove button) and a window to pick
-- sounds from. kit, content, stack: the Visions page's.
local RULE_W, ROW_H = 520, 24
local picker -- (below)

local function SmallButton(parent, text, width)
	local button = ns.PanelButton(parent)
	button:SetSize(width or 22, 20)
	button:SetText(text)
	return button
end

local function SoundName(id)
	local entry = SOUND[id]
	return entry and L[entry[2]] or tostring(id)
end

-- A slider for 10-100%: plain, so it works on every client.
local function VolumeSlider(parent, onChange, onRelease)
	local slider = CreateFrame("Slider", nil, parent)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(110, 14)
	slider:SetMinMaxValues(10, 100)
	slider:SetValueStep(5)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(0.3, 0.3, 0.3, 0.9)
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	slider:EnableMouseWheel(false)
	slider:SetScript("OnValueChanged", function(_, value) onChange(value) end)
	slider:SetScript("OnMouseUp", onRelease)
	return slider
end

function ns.CombatSoundRulesSection(kit, content, stack)
	stack:Header(content, L["Sounds"])
	local note = stack:Add(kit.Label(content, "GameFontHighlightSmall",
		L["Rules for the sounds, read top to bottom as a fight starts or ends: the first that fits plays one " ..
		"of its sounds at random. A rule's condition uses the rules' words (Boss fight, Raids, In CineMode...); " ..
		"none: any fight. Each sound's slider sets it next to the others, the cue volume sets them all. They " ..
		"play on the Ambience channel, its volume set for them and put back after."]), "label")
	note:SetWidth(RULE_W)
	note:SetJustifyH("LEFT")
	local cueVolume = stack:Add(kit.Slider(content, "combatCueVolume", L["Cue volume"], 0, 100, 5, "%d%%", 100),
		"slider")
	kit.Tooltip(cueVolume, L["How loud the sounds are, next to your sound effects' volume."])

	local box = CreateFrame("Frame", nil, content)
	box:SetSize(RULE_W, 40)
	stack:Add(box, "label")

	-- (Read again only when the saved text changed elsewhere, a profile or
	-- reset: the editor and picker hold on to the rules they're changing.)
	local rules, loaded
	local function Load()
		local text = (ns.GetDB() or ns.DEFAULTS).combatSounds -- (the page is first made before the settings load)
		if text ~= loaded then
			rules, loaded = ns.ParseCombatSounds(text), text
		end
	end
	local Rebuild
	local function Save()
		loaded = ns.FormatCombatSounds(rules)
		ns.GetDB().combatSounds = loaded
		Rebuild()
	end

	local heads, rows = {}, {}
	local function Head(i)
		local head = heads[i]
		if head then return head end
		head = CreateFrame("Frame", nil, box)
		head:SetSize(RULE_W, ROW_H)
		local band = head:CreateTexture(nil, "BACKGROUND")
		band:SetAllPoints()
		band:SetColorTexture(1, 1, 1, 0.05)
		head.number = kit.Label(head, "GameFontDisable", "")
		head.number:SetPoint("LEFT", 6, 0)
		head.edge = SmallButton(head, "", 130)
		head.edge:SetPoint("LEFT", 26, 0)
		head.rule = SmallButton(head, "", 250)
		head.rule:SetPoint("LEFT", head.edge, "RIGHT", 6, 0)
		head.rule:GetFontString():SetWordWrap(false)
		head.up = SmallButton(head, "^")
		head.up:SetPoint("LEFT", head.rule, "RIGHT", 6, 0)
		head.remove = SmallButton(head, "x")
		head.remove:SetPoint("LEFT", head.up, "RIGHT", 4, 0)
		kit.Tooltip(head.edge, L["As a fight starts or as it ends. Click to switch."])
		kit.Tooltip(head.rule, L["When this rule fits. Click to write it in the rule editor; empty: any fight."])
		kit.Tooltip(head.up, L["Move this rule up: it's read before the ones below it."])
		kit.Tooltip(head.remove, L["Remove this rule and its sounds."])
		head.add = SmallButton(box, L["Add a sound"], 110)
		kit.Tooltip(head.add, L["Pick sounds for this rule from the game's."])
		heads[i] = head
		return head
	end
	local function Row(n)
		local row = rows[n]
		if row then return row end
		row = CreateFrame("Frame", nil, box)
		row:SetSize(RULE_W - 26, 22)
		row.name = kit.Label(row, "GameFontHighlightSmall", "")
		row.name:SetPoint("LEFT", 0, 0)
		row.name:SetWidth(230)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.percent = kit.Label(row, "GameFontHighlightSmall", "")
		row.slider = VolumeSlider(row, function(value)
			row.percent:SetText(("%d%%"):format(value))
			if row.sound then row.sound[2] = value / 100 end
		end, function()
			if row.sound then
				Save()
				ns.PlayCombatSound(row.sound[1], row.sound[2])
			end
		end)
		row.slider:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
		row.percent:SetPoint("LEFT", row.slider, "RIGHT", 6, 0)
		row.percent:SetWidth(36)
		row.play = SmallButton(row, ">")
		row.play:SetPoint("LEFT", row.percent, "RIGHT", 4, 0)
		row.remove = SmallButton(row, "x")
		row.remove:SetPoint("LEFT", row.play, "RIGHT", 4, 0)
		kit.Tooltip(row.slider, L["This sound's volume, next to the others."])
		kit.Tooltip(row.play, L["Play it, at its volume."])
		kit.Tooltip(row.remove, L["Take it off this rule."])
		row.play:SetScript("OnClick", function() if row.sound then ns.PlayCombatSound(row.sound[1], row.sound[2]) end end)
		rows[n] = row
		return row
	end

	local addRule = SmallButton(box, L["Add a rule"], 120)
	local defaults = SmallButton(box, L["Back to the defaults"], 160)
	defaults:SetPoint("LEFT", addRule, "RIGHT", 8, 0)
	kit.Tooltip(addRule, L["A new rule above the last one, for the fights you pick."])
	kit.Tooltip(defaults, L["The rules as they come: horns for a boss fight, a sword drawn for the rest, and " ..
		"sheathed after."])
	addRule:SetScript("OnClick", function()
		table.insert(rules, math.max(1, #rules), { edge = "in", rule = "boss", sounds = {} })
		Save()
	end)
	defaults:SetScript("OnClick", function()
		ns.GetDB().combatSounds = ns.DEFAULTS.combatSounds
		Load()
		Rebuild()
	end)

	function Rebuild()
		for _, head in ipairs(heads) do head:Hide() head.add:Hide() end
		for _, row in ipairs(rows) do row:Hide() row.sound = nil end
		local y, n = 0, 0
		for i, rule in ipairs(rules) do
			local head = Head(i)
			head:ClearAllPoints()
			head:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
			head:Show()
			y = y + ROW_H + 2
			head.number:SetText(i .. ".")
			head.edge:SetText(rule.edge == "in" and "|cffe24b4a" .. L["Entering combat"] .. "|r"
				or "|cff5dcaa5" .. L["Leaving combat"] .. "|r")
			head.rule:SetText(rule.rule:find("%S") and ns.ColoredRule(rule.rule) or L["Any fight"])
			head.up:SetEnabled(i > 1)
			head.edge:SetScript("OnClick", function()
				rule.edge = rule.edge == "in" and "out" or "in"
				Save()
			end)
			head.up:SetScript("OnClick", function()
				rules[i], rules[i - 1] = rules[i - 1], rules[i]
				Save()
			end)
			head.remove:SetScript("OnClick", function()
				table.remove(rules, i)
				Save()
			end)
			head.rule:SetScript("OnClick", function()
				ns.OpenRuleEditor({
					label = (L["Sound rule %d"]):format(i),
					Text = function() return rule.rule end,
					SetText = function() end,
					Close = function(text)
						rule.rule = (text or ""):gsub("[#;]", ""):match("^%s*(.-)%s*$")
						Save()
					end,
					ResetToGrid = function()
						rule.rule = ""
						Save()
					end,
				})
			end)
			for _, sound in ipairs(rule.sounds) do
				n = n + 1
				local row = Row(n)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", box, "TOPLEFT", 26, -y)
				row:Show()
				y = y + 22
				row.sound = nil -- (no saving while it's set)
				local entry = SOUND[sound[1]]
				row.name:SetText(SoundName(sound[1]) .. (entry and ("  |cff808080%.1f s|r"):format(entry[4]) or ""))
				row.slider:SetValue(math.floor(sound[2] * 100 + 0.5))
				row.percent:SetText(("%d%%"):format(math.floor(sound[2] * 100 + 0.5)))
				row.sound = sound
				row.remove:SetScript("OnClick", function()
					for k, other in ipairs(rule.sounds) do
						if other == sound then table.remove(rule.sounds, k) break end
					end
					Save()
				end)
			end
			if #rule.sounds == 0 then
				local row = Row(n + 1)
				n = n + 1
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", box, "TOPLEFT", 26, -y)
				row:Show()
				row.name:SetText("|cff808080" .. L["No sounds: silent"] .. "|r")
				row.slider:Hide()
				row.percent:SetText("")
				row.play:Hide()
				row.remove:Hide()
				y = y + 22
			end
			head.add:ClearAllPoints()
			head.add:SetPoint("TOPLEFT", box, "TOPLEFT", 26, -y)
			head.add:Show()
			head.add:SetScript("OnClick", function() picker.Open(rule, Save) end)
			y = y + 28
		end
		for _, row in ipairs(rows) do
			local on = row.sound ~= nil
			if on then row.slider:Show() row.play:Show() row.remove:Show() end
		end
		addRule:ClearAllPoints()
		addRule:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y - 4)
		box:SetHeight(y + 30)
		if kit.FitContentHeight then kit.FitContentHeight(content) end
	end

	-- (Rebuilt each time the page shows: a profile or reset may have changed them.)
	box.Refresh = function(self)
		if self:IsVisible() then Load() Rebuild() end
	end
	box.pageSwitch = false
	kit.AddControl(box)
	Load()
	Rebuild()
end

-- The window to pick sounds from: the groups down the left (the rule's side
-- first), their sounds on the right, a search over them all. picker.Open(rule,
-- save): ticks add to rule's sounds or take off them.
local PICK_ROWS, PICK_ROW_H = 15, 22
picker = {}
function picker.Open(rule, save)
	local frame = picker.frame
	if not frame then
		frame = CreateFrame("Frame", "CinematicCombatSoundPicker", UIParent,
			BackdropTemplateMixin and "BackdropTemplate" or nil)
		frame:SetSize(600, 430)
		if frame.SetBackdrop then
			frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
				insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		end
		if ns.SkinWindow then ns.SkinWindow(frame) end
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("DIALOG")
		frame:SetToplevel(true)
		frame:SetClampedToScreen(true)
		frame:EnableMouse(true)
		frame:SetMovable(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
		tinsert(UISpecialFrames, "CinematicCombatSoundPicker")
		frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.title:SetPoint("TOPLEFT", 14, -12)
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
		local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
		if ns.SkinEditBox then ns.SkinEditBox(search) end
		search:SetSize(200, 20)
		search:SetAutoFocus(false)
		search:SetPoint("TOPRIGHT", -36, -8)
		frame.search = search
		local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("RIGHT", search, "LEFT", -10, 0)
		hint:SetText(L["Search"])
		frame.groups = {}
		for g = 1, #ns.COMBAT_SOUND_GROUPS do
			local button = CreateFrame("Button", nil, frame)
			button:SetSize(160, 20)
			button:SetPoint("TOPLEFT", 12, -36 - (g - 1) * 22)
			button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			button.text:SetPoint("LEFT", 6, 0)
			button.bg = button:CreateTexture(nil, "BACKGROUND")
			button.bg:SetAllPoints()
			local hl = button:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.08)
			frame.groups[g] = button
		end
		frame.rows = {}
		for r = 1, PICK_ROWS do
			local row = CreateFrame("Frame", nil, frame)
			row:SetSize(404, PICK_ROW_H)
			row:SetPoint("TOPLEFT", 184, -36 - (r - 1) * (PICK_ROW_H + 3))
			local band = row:CreateTexture(nil, "BACKGROUND")
			band:SetAllPoints()
			band:SetColorTexture(1, 1, 1, r % 2 == 1 and 0.04 or 0.01)
			row.play = SmallButton(row, ">")
			row.play:SetPoint("LEFT", 2, 0)
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.name:SetPoint("LEFT", row.play, "RIGHT", 6, 0)
			row.name:SetWidth(300)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			row.length = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			row.length:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
			row.pick = SmallButton(row, "+")
			row.pick:SetPoint("RIGHT", -2, 0)
			frame.rows[r] = row
		end
		frame.page = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		frame.page:SetPoint("BOTTOMRIGHT", -14, 12)
		frame:EnableMouseWheel(true)
		frame:SetScript("OnMouseWheel", function(self, delta)
			self.offset = math.max(0, math.min(self.offset - delta * 5, math.max(0, #self.list - PICK_ROWS)))
			self.Draw()
		end)
		search:SetScript("OnTextChanged", function() frame.offset = 0 frame.Draw() end)
		search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		picker.frame = frame
	end

	local order = {}
	local side = rule.edge
	for _, group in ipairs(ns.COMBAT_SOUND_GROUPS) do
		if group[2] == side then order[#order + 1] = group[1] end
	end
	for _, group in ipairs(ns.COMBAT_SOUND_GROUPS) do
		if group[2] ~= side then order[#order + 1] = group[1] end
	end
	frame.group, frame.offset = order[1], 0
	frame.search:SetText("")
	frame.title:SetText(rule.edge == "in" and L["Sounds for entering combat"] or L["Sounds for leaving combat"])

	local function Has(id)
		for k, sound in ipairs(rule.sounds) do
			if sound[1] == id then return k end
		end
	end
	function frame.Draw()
		local query = (frame.search:GetText() or ""):lower()
		local list = {}
		for _, entry in ipairs(ns.COMBAT_SOUNDS) do
			if query ~= "" then
				if L[entry[2]]:lower():find(query, 1, true) or tostring(entry[1]):find(query, 1, true) then
					list[#list + 1] = entry
				end
			elseif entry[3] == frame.group then
				list[#list + 1] = entry
			end
		end
		frame.list = list
		for g, button in ipairs(frame.groups) do
			local name = order[g]
			button.text:SetText(L[name])
			local on = query == "" and name == frame.group
			button.bg:SetColorTexture(1, 0.82, 0, on and 0.18 or 0)
			button.text:SetTextColor(on and 1 or 0.85, on and 0.82 or 0.85, on and 0 or 0.85)
			button:SetScript("OnClick", function()
				frame.group, frame.offset = name, 0
				frame.search:SetText("")
				frame.Draw()
			end)
		end
		for r, row in ipairs(frame.rows) do
			local entry = list[frame.offset + r]
			row:SetShown(entry ~= nil)
			if entry then
				row.name:SetText(L[entry[2]])
				row.length:SetText(("%.1f s"):format(entry[4]))
				local has = Has(entry[1])
				row.pick:SetText(has and "|cffffd100v|r" or "+")
				row.play:SetScript("OnClick", function() ns.PlayCombatSound(entry[1], entry[5]) end)
				row.pick:SetScript("OnClick", function()
					local k = Has(entry[1])
					if k then
						table.remove(rule.sounds, k)
					else
						rule.sounds[#rule.sounds + 1] = { entry[1], entry[5] }
					end
					save()
					frame.Draw()
				end)
			end
		end
		local pages = math.max(1, math.ceil(#list / PICK_ROWS))
		frame.page:SetText(("%d sounds  %d / %d  (%s)"):format(#list, math.floor(frame.offset / PICK_ROWS) + 1,
			pages, L["mouse wheel to scroll"]))
	end
	frame:Show()
	frame.Draw()
end
