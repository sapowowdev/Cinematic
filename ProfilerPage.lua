-- The Profiler page (Community hub, off to start with): what the addon costs.
-- On top, a graph of the game's own figure for this addon (its share of each
-- frame's time, sampled once a second, the last five minutes, kept over a reload),
-- each bar colored by what was going on then, with averages for each. Below,
-- a recording with Profiler.lua's timers (/cine debug cpu): it starts once the
-- settings close, and its sections show here as bars, biggest first. Copy
-- report gives it all as English text, for players to send us.
local ADDON_NAME, ns = ...
local L = ns.L

ns.DEFAULTS.profilerPage = false -- its page's switch: off, nothing's sampled or saved

local function PageOn()
	return ns.db and ns.db.profilerPage
end

local HISTORY = 300 -- samples kept, one a second
local GRAPH_HEIGHT = 110
local CHILD_ROWS = 4 -- parts listed under each recorded section
local DEEP_CHILD_ROWS = 12 -- ...in a detailed (deep) one

-- What was going on at a sample, most telling first. (English names: the
-- saved digest and the report keep them; the page shows them translated.)
local STATE_NORMAL, STATE_CINE, STATE_FIGHT, STATE_SETTINGS = 1, 2, 3, 4
local STATES = {
	[STATE_NORMAL] = { "normal UI", 0.5, 0.6, 0.75 },
	[STATE_CINE] = { "CineMode", 0.65, 0.45, 0.9 },
	[STATE_FIGHT] = { "in a fight", 0.85, 0.3, 0.25 },
	[STATE_SETTINGS] = { "settings open", 0.8, 0.7, 0.4 },
}

-- The samples: parallel rings (no table a sample), head the newest.
local addonMs, appMs, allMs, sampleState, sampleCam, sampleAt = {}, {}, {}, {}, {}, {}
local head, count = 0, 0

local function SettingsOpen()
	local panel = SettingsPanel or InterfaceOptionsFrame
	if not panel then
		return false
	end
	local ok, shown = pcall(panel.IsShown, panel)
	return ok and type(shown) == "boolean" and shown -- (secret on Forever: say closed)
end

local function CurrentState()
	if SettingsOpen() then
		return STATE_SETTINGS
	elseif InCombatLockdown() then
		return STATE_FIGHT
	elseif ns.lastCinematic then
		return STATE_CINE
	end
	return STATE_NORMAL
end

local onSample -- (the page's redraw while it's shown)

local function Push(addon, app, all, state, cam, at)
	head = head % HISTORY + 1
	count = math.min(count + 1, HISTORY)
	addonMs[head], appMs[head], allMs[head] = addon, app, all
	sampleState[head], sampleCam[head], sampleAt[head] = state, cam, at
end

-- The i-th newest sample's ring slot (1 = the newest).
local function Slot(i)
	return (head - i) % HISTORY + 1
end

local function Share(addon, app)
	return app and app > 0 and addon * 100 / app or 0
end

-- A sample that makes sense: the addon took no more than the whole frame.
-- (Just after a reload or a loading screen the game's averages can be out of
-- step: the addon's still counting the load, the frame's started over.)
local function Sensible(addon, app)
	return type(addon) == "number" and type(app) == "number" and app > 0 and addon <= app
end

-- Kept over a reload or logout: the samples (oldest first) and the last
-- recording in CinematicDB.profiler, with a digest to read in the file (the
-- averages for each state and each minute).
local restored
local function Restore()
	restored = true
	local saved = CinematicDB and CinematicDB.profiler
	if type(saved) ~= "table" then
		return
	end
	local samples = saved.samples
	if type(samples) == "table" and type(samples.addon) == "table" then
		for i = 1, #samples.addon do
			if Sensible(samples.addon[i], samples.app[i]) then
				Push(samples.addon[i], samples.app[i], samples.all[i] or 0, samples.state[i] or STATE_NORMAL,
					samples.cam[i] ~= "none" and samples.cam[i] or nil, samples.at[i] or 0)
			end
		end
	end
	if type(saved.last) == "table" and not ns.lastProfile then
		ns.lastProfile = saved.last
	end
end

local function Digest()
	local lines = {}
	local function Add(text, ...)
		lines[#lines + 1] = text:format(...)
	end
	local addon, app, all = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
	local seconds = { 0, 0, 0, 0 }
	local minute, minuteAddon, minuteApp, minuteStates
	local minutes = {}
	local function EndMinute()
		if minute then
			minutes[#minutes + 1] = ("%s: %.1f%% (%s)"):format(date("%H:%M", minute * 60),
				Share(minuteAddon, minuteApp), table.concat(minuteStates, "/"))
		end
	end
	for i = count, 1, -1 do
		local slot = Slot(i)
		local state = sampleState[slot]
		addon[state], app[state] = addon[state] + addonMs[slot], app[state] + appMs[slot]
		all[state], seconds[state] = all[state] + allMs[slot], seconds[state] + 1
		local at = math.floor((sampleAt[slot] or 0) / 60)
		if at ~= minute then
			EndMinute()
			minute, minuteAddon, minuteApp, minuteStates = at, 0, 0, {}
		end
		minuteAddon, minuteApp = minuteAddon + addonMs[slot], minuteApp + appMs[slot]
		local name, listed = STATES[state][1], false
		for _, each in ipairs(minuteStates) do
			listed = listed or each == name
		end
		if not listed then
			minuteStates[#minuteStates + 1] = name
		end
	end
	EndMinute()
	local totalAddon, totalApp, totalAll = 0, 0, 0
	for state = 1, #STATES do
		totalAddon, totalApp, totalAll = totalAddon + addon[state], totalApp + app[state], totalAll + all[state]
	end
	Add("saved %s, %d samples (one a second): Cinematic %.1f%% of the frame (%.3f ms), all addons %.1f%%",
		date("%Y-%m-%d %H:%M:%S"), count, Share(totalAddon, totalApp), count > 0 and totalAddon / count or 0,
		Share(totalAll, totalApp))
	for state = 1, #STATES do
		if seconds[state] > 0 then
			Add("%s: %.1f%% (%.3f ms a frame, %.1f fps), %d s", STATES[state][1], Share(addon[state], app[state]),
				addon[state] / seconds[state], app[state] > 0 and seconds[state] * 1000 / app[state] or 0,
				seconds[state])
		end
	end
	for _, line in ipairs(minutes) do
		lines[#lines + 1] = "minute " .. line
	end
	return lines
end

-- Every loaded addon by the game's own figures (retail's profiler), in ms a
-- frame: now (its recent average), on average since login, and its worst
-- frame. Read only while the page shows or for a report: nothing's sampled.
local function AddonMetric(name, metric)
	local profiler = C_AddOnProfiler
	local id = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[metric]
	if not (profiler and profiler.GetAddOnMetric and id) then
		return nil
	end
	local ok, value = pcall(profiler.GetAddOnMetric, name, id)
	if ok and type(value) == "number" and not (issecretvalue and issecretvalue(value)) then
		return value
	end
	return nil
end

local addonList = {} -- { name, now, average, peak } each, reused
local function ReadAddons()
	local GetNum = C_AddOns and C_AddOns.GetNumAddOns or _G.GetNumAddOns
	local GetInfo = C_AddOns and C_AddOns.GetAddOnInfo or _G.GetAddOnInfo
	local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
	local found = 0
	if GetNum and GetInfo and IsLoaded then
		for i = 1, GetNum() do
			local name = GetInfo(i)
			local now = name and IsLoaded(i) and AddonMetric(name, "RecentAverageTime")
			if now then
				found = found + 1
				local entry = addonList[found] or {}
				addonList[found] = entry
				entry.name, entry.now = name, now
				entry.average = AddonMetric(name, "SessionAverageTime") or 0
				entry.peak = AddonMetric(name, "PeakTime") or 0
			end
		end
	end
	for i = found + 1, #addonList do
		addonList[i] = nil
	end
	return addonList
end

-- How the list is sorted: by one of the figures, biggest first, or by name.
local ADDON_ORDER = {}
for _, key in ipairs({ "now", "average", "peak" }) do
	ADDON_ORDER[key] = function(a, b)
		if a[key] ~= b[key] then
			return a[key] > b[key]
		end
		return a.name < b.name
	end
end
ADDON_ORDER.name = function(a, b)
	return a.name:lower() < b.name:lower()
end

local function SortedAddons(by)
	local list = ReadAddons()
	table.sort(list, ADDON_ORDER[by] or ADDON_ORDER.average)
	return list
end

local function AddonLines()
	local lines = {}
	for _, addon in ipairs(SortedAddons("average")) do
		lines[#lines + 1] = ("%s: now %.3f, average %.3f, worst %.2f"):format(addon.name, addon.now, addon.average,
			addon.peak)
	end
	return lines
end

-- Everything as text to send us (Copy report): what it ran on, the graph's
-- digest, every addon's figures and the last recording, in English for us to read.
local function ShareText()
	local version, build = GetBuildInfo()
	local lines = {
		("Cinematic %s profiler report, %s"):format(ns.Version(), date("%Y-%m-%d %H:%M")),
		("client: %s, game %s (%s), %s"):format(tostring(ns.CLIENT), tostring(version), tostring(build),
			tostring(GetLocale())),
		"",
		"[the graph: the game's figure, one sample a second]",
	}
	if count > 0 then
		for _, line in ipairs(Digest()) do
			lines[#lines + 1] = line
		end
	else
		lines[#lines + 1] = "no samples"
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "[every loaded addon, the game's figures in ms a frame, biggest average first]"
	local addons = AddonLines()
	for _, line in ipairs(#addons > 0 and addons or { "not on this client" }) do
		lines[#lines + 1] = line
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "[the last recording]"
	local last = ns.lastProfile
	for _, line in ipairs(last and last.lines or { "none" }) do
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

local function Save()
	if not (CinematicDB and PageOn()) then
		return -- (off: what was saved last stays)
	end
	if not restored then
		Restore() -- (a reload within a second of logging in: keep what was there)
	end
	local samples = { addon = {}, app = {}, all = {}, state = {}, cam = {}, at = {} }
	for i = count, 1, -1 do
		local slot = Slot(i)
		local n = #samples.addon + 1
		samples.addon[n], samples.app[n], samples.all[n] = addonMs[slot], appMs[slot], allMs[slot]
		samples.state[n], samples.cam[n] = sampleState[slot], tostring(sampleCam[slot] or "none")
		samples.at[n] = sampleAt[slot]
	end
	CinematicDB.profiler = { samples = samples, digest = Digest(), addons = AddonLines(), last = ns.lastProfile,
		states = { STATES[1][1], STATES[2][1], STATES[3][1], STATES[4][1] } }
end

local saver = CreateFrame("Frame")
saver:RegisterEvent("PLAYER_LOGOUT")
saver:SetScript("OnEvent", Save)

local function Sample()
	if not restored then
		Restore()
	end
	if not PageOn() then
		return
	end
	local metric = ns.ProfileGameMetric
	local addon = metric and metric("addon", "RecentAverageTime")
	local app = metric and metric("app", "RecentAverageTime")
	if not Sensible(addon, app) then
		return
	end
	Push(addon, app, metric("overall", "RecentAverageTime") or 0, CurrentState(), ns.activeCam, time())
	if onSample then
		onSample()
	end
end

C_Timer.NewTicker(1, Sample)

-- A countdown at the top of the screen while a profile runs (from the page or
-- /cine debug cpu), then a while saying it's done. Our own frame: it stays up
-- through CineMode.
local DONE_SHOWN = 20 -- seconds the "done" line stays
local timer = CreateFrame("Frame", nil, UIParent)
timer:SetSize(380, 50)
timer:SetPoint("TOP", 0, -110)
timer:SetFrameStrata("HIGH")
timer:Hide()
local timerBack = timer:CreateTexture(nil, "BACKGROUND")
timerBack:SetAllPoints()
timerBack:SetColorTexture(0, 0, 0, 0.6)
local timerText = timer:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
timerText:SetPoint("TOP", 0, -6)
local timerNote = timer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
timerNote:SetPoint("TOP", timerText, "BOTTOM", 0, -3)
local doneAt, shownSecond
timer:SetScript("OnUpdate", function(self)
	local left, deep = ns.ProfileTimeLeft()
	if left then
		doneAt = nil
		local second = math.ceil(left)
		if second ~= shownSecond then -- (new text once a second, not every frame)
			shownSecond = second
			timerText:SetText((deep and L["Detailed CPU recording  %d:%02d"] or L["Recording CPU  %d:%02d"]):format(
				math.floor(second / 60), second % 60))
			timerNote:SetText(L["Play as usual. Stop on the Profiler page ends it."])
		end
		return
	end
	local now = GetTime()
	if not doneAt then
		doneAt, shownSecond = now, nil
		timerText:SetText("|cff40ff40" .. L["CPU recording done"] .. "|r")
		timerNote:SetText(L["Open the Profiler page to see it, or Copy report there to share it."])
	elseif now - doneAt > DONE_SHOWN then
		self:Hide()
	end
end)
function ns.ShowProfileTimer()
	doneAt, shownSecond = nil, nil
	timer:Show()
end

-- A recording: the page's Record button, with its options (how long,
-- detailed, start now). Without Start now it waits for the settings to close.
ns.DEFAULTS.profilerSeconds = 120   -- how long a recording runs
ns.DEFAULTS.profilerDetailed = false -- every ns function timed too (deep)
ns.DEFAULTS.profilerNow = false     -- start right away, with the settings open (to measure them)
local armedSeconds, armedDeep
local armer = CreateFrame("Frame")
armer:Hide()
local function StartRecording(seconds, deep)
	if ns.StartProfile(seconds, true, deep) then
		ns.Print((deep and L["Detailed CPU recording for %d seconds: play as usual."]
			or L["CPU recording for %d seconds: play as usual."]):format(seconds))
	end
end
armer:SetScript("OnUpdate", function(self)
	if SettingsOpen() then
		return
	end
	self:Hide()
	local seconds, deep = armedSeconds, armedDeep
	armedSeconds, armedDeep = nil, nil
	StartRecording(seconds, deep)
end)

-- Clear all data: the graph's samples, the last recording and what's saved.
-- (The game's own figures for each addon are its own: they start again only
-- when it does.)
local function ClearData()
	for _, list in ipairs({ addonMs, appMs, allMs, sampleState, sampleCam, sampleAt }) do
		wipe(list)
	end
	head, count = 0, 0
	ns.lastProfile = nil
	if CinematicDB then
		CinematicDB.profiler = nil
	end
end

local ROW_HEIGHT = 18
local SORT_ARROW = " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-2|t"

function ns.CreateProfilerPanel(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", L["Profiler"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How much of your computer's time Cinematic takes. The graph is the game's own figure for this addon: " ..
		"its share of each frame's time, sampled every second (the last five minutes, kept over a reload), each " ..
		"bar colored by what was going on. A recording times the addon's busy parts: it starts when you close " ..
		"the settings, and its results show here. If Cinematic seems slow for you, record a while of your usual " ..
		"play (a fight too), then Copy report and send it to us: it helps us find what to speed up."])

	local function Text(parent, font, anchor, x, y)
		local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -6)
		fs:SetJustifyH("LEFT")
		return fs
	end
	local function Button(text, width, tip, onClick)
		local button = ns.PanelButton(content)
		button:SetSize(width, 22)
		button:SetText(text)
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", onClick)
		return button
	end

	-- A table: a header row of column names (click one to sort by it, the one
	-- in use gold with an arrow), then rows, every other one shaded. columns:
	-- { key, label, width } each, the first the name (as wide as is left,
	-- with a bar behind it of the sorted figure); cell(row, key) gives a
	-- cell's text. onSort(key) when a header's clicked.
	local function Table(anchor, columns, onSort, onEnter)
		local tableFrame = CreateFrame("Frame", nil, content)
		tableFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
		tableFrame:SetPoint("RIGHT", content, "RIGHT", -16, 0)
		tableFrame:SetHeight(ROW_HEIGHT)
		tableFrame.headers, tableFrame.rows = {}, {}
		local right = 0
		for i = #columns, 1, -1 do
			local column = columns[i]
			local header = CreateFrame("Button", nil, tableFrame)
			header:SetHeight(ROW_HEIGHT)
			header.text = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
			header.text:SetAllPoints()
			if i == 1 then
				header:SetPoint("TOPLEFT")
				header:SetPoint("RIGHT", tableFrame, "RIGHT", -right, 0)
				header.text:SetJustifyH("LEFT")
			else
				header:SetPoint("TOPRIGHT", tableFrame, "TOPRIGHT", -right, 0)
				header:SetWidth(column[3])
				header.text:SetJustifyH("RIGHT")
				right = right + column[3]
			end
			header.key, header.label = column[1], column[2]
			header:SetScript("OnClick", function() onSort(column[1]) end)
			header:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
			header:SetScript("OnLeave", function(self) self.text:SetTextColor(self.color[1], self.color[2],
				self.color[3]) end)
			header.color = { 1, 0.82, 0 }
			tableFrame.headers[i] = header
		end
		local line = tableFrame:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(1, 0.82, 0, 0.35)
		line:SetHeight(1)
		line:SetPoint("TOPLEFT", 0, -ROW_HEIGHT)
		line:SetPoint("TOPRIGHT", 0, -ROW_HEIGHT)
		function tableFrame:ShowSort(key)
			for _, header in ipairs(self.headers) do
				local on = header.key == key
				header.color = on and { 1, 0.82, 0 } or { 0.75, 0.75, 0.75 }
				header.text:SetText(on and header.label .. SORT_ARROW or header.label)
				header.text:SetTextColor(header.color[1], header.color[2], header.color[3])
			end
		end
		function tableFrame:Row(i)
			local row = self.rows[i]
			if row then
				return row
			end
			row = CreateFrame("Frame", nil, self)
			row:SetHeight(ROW_HEIGHT)
			row:SetPoint("TOPLEFT", 0, -i * ROW_HEIGHT - 2)
			row:SetPoint("RIGHT")
			local shade = row:CreateTexture(nil, "BACKGROUND")
			shade:SetAllPoints()
			shade:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
			row.bar = row:CreateTexture(nil, "BORDER")
			row.bar:SetPoint("LEFT", 2, 0)
			row.bar:SetHeight(ROW_HEIGHT - 4)
			row.bar:SetColorTexture(1, 1, 1, 1)
			row.cells = {}
			local cellRight = 0
			for c = #columns, 1, -1 do
				local cell = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
				cell:SetHeight(ROW_HEIGHT)
				cell:SetWordWrap(false)
				if c == 1 then
					cell:SetPoint("LEFT", 6, 0)
					cell:SetPoint("RIGHT", row, "RIGHT", -cellRight - 8, 0)
					cell:SetJustifyH("LEFT")
				else
					cell:SetPoint("RIGHT", row, "RIGHT", -cellRight, 0)
					cell:SetWidth(columns[c][3])
					cell:SetJustifyH("RIGHT")
					cellRight = cellRight + columns[c][3]
				end
				row.cells[c] = cell
			end
			row.nameWidth = function()
				return (row:GetWidth() or 0) - cellRight
			end
			if onEnter then
				row:EnableMouse(true)
				row:SetScript("OnEnter", onEnter)
				row:SetScript("OnLeave", GameTooltip_Hide)
			end
			self.rows[i] = row
			return row
		end
		-- Shows n rows (fill(row, i) sets each) and hides the rest.
		function tableFrame:Fill(n, fill)
			for i = 1, n do
				local row = self:Row(i)
				fill(row, i)
				row:Show()
			end
			for i = n + 1, #self.rows do
				self.rows[i]:Hide()
			end
			self:SetHeight((n + 1) * ROW_HEIGHT + 4)
		end
		-- A row's bar: share (0 to 1) of the name column, in a color.
		function tableFrame.Bar(row, share, r, g, b, a)
			local width = row.nameWidth()
			if width <= 0 then width = 200 end
			row.bar:SetWidth(math.max(width * math.min(share, 1), 1))
			row.bar:SetVertexColor(r, g, b, a or 0.35)
		end
		return tableFrame
	end

	-- The switch, and Clear all data beside it.
	local Refresh -- (below)
	local switch = kit.PageSwitch(content, "profilerPage", L["Enable page"],
		L["On: the graph samples the game's figure every second and keeps it over a reload, and you can " ..
		"record. Off (to start with): nothing is sampled or saved, and it costs nothing."], intro,
		function() Refresh() end)
	StaticPopupDialogs.CINEMATIC_PROFILER_CLEAR = {
		text = L["Clear the Profiler's graph and its last recording, here and in what's saved? (The game's own " ..
			"figures for each addon start again only when the game does.)"],
		button1 = L["Clear"], button2 = CANCEL or L["Cancel"],
		OnAccept = function()
			ClearData()
			Refresh()
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	local clear = Button(L["Clear all data"], 130, L["Clears the graph's samples and the last recording, " ..
		"here and in what's saved."], function() StaticPopup_Show("CINEMATIC_PROFILER_CLEAR") end)
	clear:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -14)

	-- The graph, and its figures under it in tiles.
	local graphHeader = kit.Header(content, L["The game's figure, the last five minutes"], switch, -16)
	local graph = CreateFrame("Frame", nil, content)
	graph:SetPoint("TOPLEFT", graphHeader, "BOTTOMLEFT", 0, -8)
	graph:SetPoint("RIGHT", content, "RIGHT", -60, 0)
	graph:SetHeight(GRAPH_HEIGHT)
	local back = graph:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.35)
	local bars = {}
	for i = 1, HISTORY do
		local bar = graph:CreateTexture(nil, "ARTWORK")
		bar:SetColorTexture(1, 1, 1, 1)
		bar:Hide()
		bars[i] = bar
	end
	local averageLine = graph:CreateTexture(nil, "OVERLAY")
	averageLine:SetColorTexture(1, 0.82, 0, 0.8)
	averageLine:SetHeight(1)
	local topLabel = graph:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	topLabel:SetPoint("TOPLEFT", graph, "TOPRIGHT", 4, 0)
	local averageLabel = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	local zeroLabel = graph:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	zeroLabel:SetPoint("BOTTOMLEFT", graph, "BOTTOMRIGHT", 4, 0)
	zeroLabel:SetText("0%")
	local empty = graph:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER")

	local legend = Text(content, "GameFontHighlightSmall", graph, 0, -6)
	local legendParts = {}
	for i = 1, #STATES do
		local state = STATES[i]
		-- (a square of its color: the font has no square character)
		legendParts[i] = ("|TInterface\\Buttons\\WHITE8X8:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t %s"):format(
			state[2] * 255, state[3] * 255, state[4] * 255, L[state[1]])
	end
	legend:SetText(table.concat(legendParts, "    ") .. "    |cffffd100--|r " .. L["average"])

	-- Tiles: a big figure with its name under it, in a row.
	-- (beside: the tile before it in its row; else under below, the row's first)
	local function Tile(label, beside, below, tip, width)
		local tile = CreateFrame("Frame", nil, content)
		tile:SetSize(width or 150, 44)
		if beside then
			tile:SetPoint("LEFT", beside, "RIGHT", 8, 0)
		else
			tile:SetPoint("TOPLEFT", below or legend, "BOTTOMLEFT", 0, -10)
		end
		if tip then
			tile:EnableMouse(true)
			kit.Tooltip(tile, tip)
		end
		local shade = tile:CreateTexture(nil, "BACKGROUND")
		shade:SetAllPoints()
		shade:SetColorTexture(1, 1, 1, 0.05)
		tile.value = tile:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
		tile.value:SetPoint("TOPLEFT", 8, -5)
		tile.label = tile:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		tile.label:SetPoint("BOTTOMLEFT", 8, 5)
		tile.label:SetText(label)
		return tile
	end
	local nowTile = Tile(L["Now"])
	local averageTile = Tile(L["Average"], nowTile)
	local peakTile = Tile(L["Peak"], averageTile)
	local allTile = Tile(L["All addons"], peakTile)
	local tiles = { nowTile, averageTile, peakTile, allTile }
	local stateText = Text(content, "GameFontHighlightSmall", nowTile, 0, -10)
	stateText:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	stateText:SetJustifyV("TOP")

	local scaleMax = 5
	local function DrawGraph()
		if count == 0 then
			empty:SetText(ns.ProfileGameMetric and ns.ProfileGameMetric("addon", "RecentAverageTime") == nil
				and L["The game's profiler isn't on this client: use a recording below."]
				or (PageOn() and L["No samples yet (one a second)."] or L["Off: turn on Enable page to sample."]))
			empty:Show()
		else
			empty:Hide()
		end
		local width = graph:GetWidth()
		if not width or width <= 0 then
			return
		end
		local barWidth = width / HISTORY
		-- Totals over the window, for each state too.
		local peak, sumAddon, sumApp, sumAll = 0, 0, 0, 0
		local byAddon, byApp, bySeconds = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
		for i = 1, count do
			local slot = Slot(i)
			local share = Share(addonMs[slot], appMs[slot])
			if share > peak then peak = share end
			sumAddon, sumApp, sumAll = sumAddon + addonMs[slot], sumApp + appMs[slot], sumAll + allMs[slot]
			local state = sampleState[slot]
			byAddon[state] = byAddon[state] + addonMs[slot]
			byApp[state] = byApp[state] + appMs[slot]
			bySeconds[state] = bySeconds[state] + 1
		end
		scaleMax = math.max(5, math.ceil(peak / 5) * 5)
		topLabel:SetText(scaleMax .. "%")
		-- (Newest on the right.)
		for i = 1, HISTORY do
			local bar = bars[i]
			if i > count then
				bar:Hide()
			else
				local slot = Slot(i)
				local share = Share(addonMs[slot], appMs[slot])
				local state = STATES[sampleState[slot]]
				bar:ClearAllPoints()
				bar:SetPoint("BOTTOMLEFT", graph, "BOTTOMLEFT", width - i * barWidth, 0)
				bar:SetSize(math.max(barWidth - (barWidth > 2 and 0.5 or 0), 0.5),
					math.max(GRAPH_HEIGHT * math.min(share, scaleMax) / scaleMax, 0.5))
				bar:SetVertexColor(state[2], state[3], state[4], 0.9)
				bar:Show()
			end
		end
		local average = Share(sumAddon, sumApp)
		if count > 0 then
			averageLine:ClearAllPoints()
			averageLine:SetPoint("BOTTOMLEFT", graph, "BOTTOMLEFT", 0, GRAPH_HEIGHT * average / scaleMax)
			averageLine:SetPoint("BOTTOMRIGHT", graph, "BOTTOMRIGHT", 0, GRAPH_HEIGHT * average / scaleMax)
			averageLine:Show()
			averageLabel:ClearAllPoints()
			averageLabel:SetPoint("LEFT", graph, "BOTTOMRIGHT", 4, GRAPH_HEIGHT * average / scaleMax)
			averageLabel:SetText(("%.1f%%"):format(average))
			averageLabel:Show()
		else
			averageLine:Hide()
			averageLabel:Hide()
		end
		if count == 0 then
			for _, tile in ipairs(tiles) do
				tile.value:SetText("-")
			end
			stateText:SetText("")
			return
		end
		local newest = Slot(1)
		nowTile.value:SetText(("|cffffd100%.1f%%|r  %.2f ms"):format(Share(addonMs[newest], appMs[newest]),
			addonMs[newest]))
		averageTile.value:SetText(("%.1f%%  %.2f ms"):format(average, sumAddon / count))
		peakTile.value:SetText(("%.1f%%"):format(peak))
		allTile.value:SetText(("%.1f%%"):format(Share(sumAll, sumApp)))
		local parts = {}
		for state = 1, #STATES do
			if bySeconds[state] > 0 then
				parts[#parts + 1] = L["%s |cffffd100%.1f%%|r (%.3f ms a frame, %d s)"]:format(L[STATES[state][1]],
					Share(byAddon[state], byApp[state]), byAddon[state] / bySeconds[state], bySeconds[state])
			end
		end
		stateText:SetText(table.concat(parts, "     "))
	end

	-- Mouse over the graph: that second's figures.
	local hovered
	local function ShowHovered()
		local left, width = graph:GetLeft(), graph:GetWidth()
		if not (left and width and width > 0) then
			return
		end
		local x = GetCursorPosition() / graph:GetEffectiveScale() - left
		local i = math.floor((width - x) / (width / HISTORY)) + 1
		if i < 1 or i > count then
			GameTooltip:Hide()
			hovered = nil
			return
		end
		if i == hovered and GameTooltip:IsOwned(graph) then
			return
		end
		hovered = i
		local slot = Slot(i)
		GameTooltip:SetOwner(graph, "ANCHOR_CURSOR")
		GameTooltip:SetText(L["%s, %d s ago"]:format(date("%H:%M:%S", sampleAt[slot]), time() - sampleAt[slot]),
			1, 0.82, 0)
		GameTooltip:AddLine(L["Cinematic %.1f%% of the frame: %.3f ms of %.2f ms (%.0f fps)"]:format(
			Share(addonMs[slot], appMs[slot]), addonMs[slot], appMs[slot],
			appMs[slot] > 0 and 1000 / appMs[slot] or 0), 1, 1, 1)
		GameTooltip:AddLine(L["All addons %.1f%% (%.3f ms)"]:format(Share(allMs[slot], appMs[slot]), allMs[slot]),
			0.8, 0.8, 0.8)
		local state = STATES[sampleState[slot]]
		GameTooltip:AddLine(L["%s, camera %s"]:format(L[state[1]], tostring(sampleCam[slot] or L["none"])),
			state[2], state[3], state[4])
		GameTooltip:Show()
	end
	graph:EnableMouse(true)
	graph:SetScript("OnEnter", function(self)
		hovered = nil
		self:SetScript("OnUpdate", ShowHovered)
	end)
	graph:SetScript("OnLeave", function(self)
		self:SetScript("OnUpdate", nil)
		GameTooltip:Hide()
	end)

	-- Every addon, the game's figures: a table sorted by a header, the first
	-- few unless Show all.
	local ADDON_ROWS = 12
	local addonSort, addonAll = "average", false
	local DrawAddons -- (below)
	local addonHeader = kit.Header(content, L["All addons (the game's figures, ms a frame)"], stateText, -24)
	local addonTable = Table(addonHeader, {
		{ "name", L["Addon"] }, { "now", L["Now"], 80 }, { "average", L["Average"], 80 },
		{ "peak", L["Worst"], 80 }, { "share", L["Share now"], 90 },
	}, function(key)
		addonSort = key == "share" and "now" or key
		DrawAddons()
	end)
	local addonEmpty = Text(content, "GameFontDisable", addonTable, 6, -2)
	addonEmpty:SetText(L["The game's profiler isn't on this client."])
	local showAll = Button(L["Show all"], 110, nil, function()
		addonAll = not addonAll
		DrawAddons()
		kit.FitContentHeight(content)
	end)
	showAll:SetPoint("TOPLEFT", addonTable, "BOTTOMLEFT", 0, -6)
	-- Which addons the table shows: a menu of every loaded one to tick (none
	-- ticked: all). Kept until a reload.
	local addonFilter, filtered = {}, {}
	local function FilterCount()
		local ticked = 0
		for _ in pairs(addonFilter) do ticked = ticked + 1 end
		return ticked
	end
	local filterMenu
	local function FilterText()
		local ticked = FilterCount()
		return ticked == 0 and L["All addons"] or L["%d addons"]:format(ticked)
	end
	local okMenu, menu = ns.MenuDropdown(content)
	if okMenu and menu and menu.SetupMenu then
		filterMenu = menu
		filterMenu:SetWidth(170)
		filterMenu:SetPoint("RIGHT", content, "RIGHT", -16, 0)
		filterMenu:SetPoint("BOTTOM", addonHeader, "BOTTOM", 0, -4)
		kit.Tooltip(filterMenu, L["Which addons the table shows: tick the ones to compare, or All addons for " ..
			"every one."])
		filterMenu:SetupMenu(function(_, root)
			root:CreateButton(L["All addons"], function()
				wipe(addonFilter)
				DrawAddons()
			end)
			root:CreateDivider()
			local names = {}
			for _, addon in ipairs(ReadAddons()) do
				names[#names + 1] = addon.name
			end
			table.sort(names, function(a, b) return a:lower() < b:lower() end)
			for _, name in ipairs(names) do
				root:CreateCheckbox(name, function() return addonFilter[name] == true end, function()
					addonFilter[name] = not addonFilter[name] or nil
					DrawAddons()
				end)
			end
		end)
	end
	function DrawAddons()
		addonTable:ShowSort(addonSort)
		local list = SortedAddons(addonSort)
		if next(addonFilter) then
			wipe(filtered)
			for _, addon in ipairs(list) do
				if addonFilter[addon.name] then
					filtered[#filtered + 1] = addon
				end
			end
			list = filtered
		end
		if filterMenu then
			if filterMenu.OverrideText then
				filterMenu:OverrideText(FilterText())
			elseif filterMenu.SetDefaultText then
				filterMenu:SetDefaultText(FilterText())
			end
		end
		local app = ns.ProfileGameMetric and ns.ProfileGameMetric("app", "RecentAverageTime") or 0
		local figure = addonSort == "name" and "average" or addonSort
		local biggest = 0.0001
		for _, addon in ipairs(list) do
			biggest = math.max(biggest, addon[figure])
		end
		addonTable:Fill(addonAll and #list or math.min(#list, ADDON_ROWS), function(row, i)
			local addon = list[i]
			local ours = addon.name == ADDON_NAME
			row.cells[1]:SetText(addon.name)
			row.cells[1]:SetTextColor(ours and 1 or 1, ours and 0.82 or 1, ours and 0 or 1)
			row.cells[2]:SetText(("%.3f"):format(addon.now))
			row.cells[3]:SetText(("%.3f"):format(addon.average))
			row.cells[4]:SetText(("%.2f"):format(addon.peak))
			row.cells[5]:SetText(("%.1f%%"):format(Share(addon.now, app)))
			if ours then
				addonTable.Bar(row, addon[figure] / biggest, 1, 0.82, 0)
			else
				addonTable.Bar(row, addon[figure] / biggest, 0.45, 0.6, 0.85)
			end
		end)
		addonEmpty:SetShown(#list == 0)
		showAll:SetShown(#list > ADDON_ROWS)
		showAll:SetText(addonAll and L["Show fewer"] or L["Show all"])
	end

	-- The recording: one Record button (Stop while one runs or waits), its
	-- options beside it, then the results as a table.
	local recordHeader = kit.Header(content, L["Recording (the addon's own timers)"], showAll, -24)
	local LENGTHS = { { value = 30, text = L["30 seconds"] }, { value = 60, text = L["1 minute"] },
		{ value = 120, text = L["2 minutes"] }, { value = 300, text = L["5 minutes"] } }
	local function LengthText(seconds)
		for _, length in ipairs(LENGTHS) do
			if length.value == seconds then return length.text end
		end
		return ("%d s"):format(seconds)
	end
	local status
	local record = Button(L["Record"], 110, nil, function()
		if ns.IsProfiling() or armedSeconds then
			armedSeconds, armedDeep = nil, nil
			armer:Hide()
			ns.StopProfile()
		elseif PageOn() then
			local db = ns.GetDB()
			local seconds, deep = db.profilerSeconds or 120, db.profilerDetailed and true or false
			if db.profilerNow then
				StartRecording(seconds, deep)
			else
				armedSeconds, armedDeep = seconds, deep
				armer:Show()
			end
		end
		Refresh()
	end)
	record:SetPoint("TOPLEFT", recordHeader, "BOTTOMLEFT", 0, -10)
	kit.Tooltip(record, L["Times the addon's busy parts as you play, for as long as is picked beside it. It starts " ..
		"when you close the settings (or right away, with Start now), and the results show here. Click it again " ..
		"to stop."])
	local length = kit.Dropdown and kit.Dropdown(content, "profilerSeconds", LENGTHS, 120, function() Refresh() end)
	if not length then
		-- (No dropdowns on this client: a button that steps through them.)
		length = Button("", 120, nil, function(self)
			local db = ns.GetDB()
			local following = LENGTHS[1].value
			for i, choice in ipairs(LENGTHS) do
				if choice.value == db.profilerSeconds then
					following = LENGTHS[i % #LENGTHS + 1].value
					break
				end
			end
			db.profilerSeconds = following
			self:Refresh()
		end)
		length.Refresh = function(self) self:SetText(LengthText(ns.GetDB().profilerSeconds)) end
		kit.AddControl(length)
	end
	kit.Tooltip(length, L["How long a recording runs."])
	length:SetPoint("LEFT", record, "RIGHT", 10, 0)
	local detailed = kit.Check(content, "profilerDetailed", L["Detailed"], L["Nearly every one of the addon's " ..
		"functions timed too, not just its busy parts, each listed under the part that called it: it shows " ..
		"what inside a busy part costs. The timing itself takes time, so everything reads higher than it is."])
	detailed:SetPoint("LEFT", length, "RIGHT", 12, 0)
	local startNow = kit.Check(content, "profilerNow", L["Start now"], L["Start right away, with the settings " ..
		"open, instead of when you close them: to measure the settings pages themselves. Click through the ones " ..
		"to check while it runs."])
	startNow:SetPoint("LEFT", detailed.Text or detailed, "RIGHT", 16, 0)
	local copy = Button(L["Copy report"], 120, L["Everything here as text, to copy and send us (on Discord, " ..
		"or in a bug report): your game version, the graph's figures, every addon's and the last recording. " ..
		"It's in English, for us to read."], function()
			ns.ShowText(L["Profiler: press Ctrl+C to copy"], ShareText())
		end)
	copy:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	copy:SetPoint("TOP", record, "TOP")
	status = Text(content, "GameFontHighlight", record, 0, -12)
	status:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	-- The recording's figures in tiles, like the graph's.
	local RECORD_TILE = 138
	local measuredTile = Tile(L["Cinematic, timed"], nil, status, L["What the addon's timers measured: ms a " ..
		"frame, and its share of the frame."], RECORD_TILE)
	local gameTile = Tile(L["The game's figure"], measuredTile, nil, L["What the game measured for Cinematic " ..
		"meanwhile, the timers' parts and all the rest."], RECORD_TILE)
	local garbageTile = Tile(L["Garbage"], gameTile, nil, L["Memory made and thrown away, a second: the game " ..
		"spends time clearing it up."], RECORD_TILE)
	local slowTile = Tile(L["Slow frames"], garbageTile, nil, L["Frames where the addon took over 5 ms, and " ..
		"their share of all frames."], RECORD_TILE)
	local worstTile = Tile(L["Worst frame"], slowTile, nil, L["The most the addon took in one frame."], RECORD_TILE)
	local recordTiles = { measuredTile, gameTile, garbageTile, slowTile, worstTile }
	-- Each row of tiles shares the page's width (16 in from each side, 8
	-- between), however wide the settings window is.
	local function FitTiles(row)
		local width = (content:GetWidth() or 0) - 32 - 8 * (#row - 1)
		if width > 0 then
			for _, tile in ipairs(row) do
				tile:SetWidth(width / #row)
			end
		end
	end
	content:HookScript("OnSizeChanged", function()
		FitTiles(tiles)
		FitTiles(recordTiles)
	end)
	FitTiles(tiles)
	FitTiles(recordTiles)
	-- (Whose code the parts are: only Cinematic's own can be timed. Other
	-- addons show only as a whole, in All addons above.)
	local partsNote = Text(content, "GameFontDisableSmall", measuredTile, 0, -12)
	partsNote:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	partsNote:SetText(L["Every part below is Cinematic's own code: an addon can only time its own. For other " ..
		"addons, see All addons above."])

	-- The recorded parts: a table sorted by a header (parts called by a
	-- section stay under it). (Their names are the code's own, in English.)
	local partSort = "ms"
	local DrawRecording -- (below)
	local function RowTip(row)
		local data = row.data
		if not data then return end
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(data.name, 1, 0.82, 0)
		GameTooltip:AddLine(L["%.4f ms a frame, %.2f calls a frame"]:format(data.ms, data.calls), 1, 1, 1)
		GameTooltip:AddLine(L["average %.4f ms a call, worst %.2f ms"]:format(data.average, data.worst), 1, 1, 1)
		GameTooltip:AddLine(L["%.1f KB of garbage a second"]:format(data.kb), 1, 1, 1)
		if row.child then
			GameTooltip:AddLine(L["(Called by the part above: its time is part of that one's.)"], 0.7, 0.7, 0.7, true)
		end
		GameTooltip:Show()
	end
	local partTable = Table(partsNote, {
		{ "name", L["Part"] }, { "ms", L["ms a frame"], 80 }, { "share", L["Share"], 60 },
		{ "calls", L["Calls a frame"], 90 }, { "worst", L["Worst ms"], 70 }, { "kb", L["Garbage KB/s"], 90 },
	}, function(key)
		partSort = key == "share" and "ms" or key
		DrawRecording()
	end, RowTip)
	local PART_ORDER = {}
	for _, key in ipairs({ "ms", "calls", "worst", "kb" }) do
		PART_ORDER[key] = function(a, b)
			if a[key] ~= b[key] then return a[key] > b[key] end
			return a.name < b.name
		end
	end
	PART_ORDER.name = function(a, b) return a.name:lower() < b.name:lower() end
	local partRows = {} -- { data, child } each, reused
	function DrawRecording()
		partTable:ShowSort(partSort)
		local last = ns.lastProfile
		local left = ns.ProfileTimeLeft()
		if left then
			status:SetText(L["Recording: %d:%02d left."]:format(math.floor(math.ceil(left) / 60),
				math.ceil(left) % 60))
		elseif armedSeconds then
			status:SetText((armedDeep and L["Starts when you close the settings: %d seconds, detailed."]
				or L["Starts when you close the settings: %d seconds."]):format(armedSeconds))
		elseif last then
			status:SetText((last.deep and L["Last recording: %s, %s, detailed"] or L["Last recording: %s, %s"]):format(
				date("%H:%M", last.finished), LengthText(math.floor(last.seconds + 0.5))))
		elseif PageOn() then
			status:SetText(L["No recording yet."])
		else
			status:SetText(L["Turn on Enable page to record."])
		end
		local used = 0
		for _, tile in ipairs(recordTiles) do
			tile:SetShown(last ~= nil)
		end
		partsNote:SetShown(last ~= nil)
		if last then
			local frames = math.max(last.fps * last.seconds, 1)
			measuredTile.value:SetText(("|cffffd100%.2f ms|r  %.1f%%"):format(last.total,
				last.total * 100 / last.frameMs))
			gameTile.value:SetText(last.game and ("%.2f ms  %.1f%%"):format(last.game.addon,
				Share(last.game.addon, last.game.app)) or "-")
			garbageTile.value:SetText(("%.0f KB/s"):format(last.kb))
			slowTile.value:SetText(("%d  %.1f%%"):format(last.spikes[5], last.spikes[5] * 100 / frames))
			worstTile.value:SetText(("%.1f ms"):format(last.worst))
			local sections = {}
			for i, section in ipairs(last.sections) do sections[i] = section end
			table.sort(sections, PART_ORDER[partSort] or PART_ORDER.ms)
			local limit = last.deep and DEEP_CHILD_ROWS or CHILD_ROWS
			for _, section in ipairs(sections) do
				used = used + 1
				partRows[used] = partRows[used] or {}
				partRows[used].data, partRows[used].child = section, false
				-- (A detailed recording times a part twice when it's both one of
				-- the timed parts and a function on ns: "UpdateFrames" and
				-- "ns.UpdateFrames", the same time. Only the first shows.)
				local named = { [section.name] = true }
				for _, child in ipairs(section.children) do
					named[child.name] = true
				end
				local shown = 0
				for _, child in ipairs(section.children) do
					local own = child.name:match("^ns%.(.+)")
					if not (own and named[own]) then
						shown = shown + 1
						if shown > limit then break end
						used = used + 1
						partRows[used] = partRows[used] or {}
						partRows[used].data, partRows[used].child = child, true
					end
				end
			end
		end
		local biggest = math.max(last and last.sections[1] and last.sections[1].ms or 0, 0.0001)
		for _, section in ipairs(last and last.sections or {}) do
			biggest = math.max(biggest, section.ms)
		end
		local total = last and last.total or 0
		partTable:SetShown(used > 0)
		partTable:Fill(used, function(row, i)
			local data, child = partRows[i].data, partRows[i].child
			row.data, row.child = data, child
			row.cells[1]:SetText(child and "    > " .. data.name or data.name)
			row.cells[1]:SetTextColor(child and 0.7 or 1, child and 0.7 or 1, child and 0.7 or 1)
			row.cells[2]:SetText(("%.3f"):format(data.ms))
			row.cells[3]:SetText(child and "" or ("%.0f%%"):format(total > 0 and data.ms * 100 / total or 0))
			row.cells[4]:SetText(("%.2f"):format(data.calls))
			row.cells[5]:SetText(("%.2f"):format(data.worst))
			row.cells[6]:SetText(("%.1f"):format(data.kb))
			if child then
				partTable.Bar(row, data.ms / biggest, 0.45, 0.6, 0.85, 0.25)
			elseif data.kb > 5 then
				partTable.Bar(row, data.ms / biggest, 1, 0.5, 0.15) -- (orange: a lot of garbage)
			else
				partTable.Bar(row, data.ms / biggest, 1, 0.82, 0)
			end
		end)
		if used == 0 then partTable:Hide() end
	end

	function Refresh()
		DrawGraph()
		DrawAddons()
		DrawRecording()
		local on = PageOn() and true or false
		local busy = ns.IsProfiling() or armedSeconds ~= nil
		record:SetText(busy and L["Stop"] or L["Record"])
		record:SetEnabled(on or busy)
	end
	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:HookScript("OnShow", function() onSample = DrawGraph end)
	canvas:SetScript("OnHide", function() onSample = nil end)
	-- (The addons' figures, and whether a recording's running, read again
	-- every second while the page shows: reading them costs nothing while
	-- it's closed.)
	local shownAt, wasBusy = 0, false
	canvas:SetScript("OnUpdate", function()
		local now = GetTime()
		if now - shownAt >= 1 then
			shownAt = now
			DrawAddons()
			local busy = ns.IsProfiling() or armedSeconds ~= nil
			if busy ~= wasBusy then
				wasBusy = busy
				Refresh()
			elseif busy then
				DrawRecording() -- (the time left)
			end
		end
	end)
	-- (The graph's width is only known once laid out.)
	graph:SetScript("OnSizeChanged", DrawGraph)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Profiler")
end
