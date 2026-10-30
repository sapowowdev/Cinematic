-- The Profiler page (Community hub, off to start with): what the addon costs.
-- On top, a graph of the game's own figure for this addon (its share of each
-- frame's time, sampled once a second, the last five minutes, kept over a reload),
-- each bar colored by what was going on then, with averages for each. Below,
-- a recording with Profiler.lua's timers (/cine debug cpu): it starts once the
-- settings close, and its sections show here as bars, biggest first. Copy
-- report gives it all as English text, for players to send us.
local _, ns = ...
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
			Push(samples.addon[i], samples.app[i] or 0, samples.all[i] or 0, samples.state[i] or STATE_NORMAL,
				samples.cam[i] ~= "none" and samples.cam[i] or nil, samples.at[i] or 0)
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

-- Everything as text to send us (Copy report): what it ran on, the graph's
-- digest and the last recording, in English for us to read.
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
	CinematicDB.profiler = { samples = samples, digest = Digest(), last = ns.lastProfile,
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
	if not addon then
		return
	end
	Push(addon, metric("app", "RecentAverageTime") or 0, metric("overall", "RecentAverageTime") or 0,
		CurrentState(), ns.activeCam, time())
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

-- The recording waiting for the settings to close: its length, and whether
-- it's a detailed one (every ns function timed: deep).
local armedSeconds, armedDeep
local armer = CreateFrame("Frame")
armer:Hide()
armer:SetScript("OnUpdate", function(self)
	if SettingsOpen() then
		return
	end
	self:Hide()
	local seconds, deep = armedSeconds, armedDeep
	armedSeconds, armedDeep = nil, nil
	if ns.StartProfile(seconds, true, deep) then
		ns.Print((deep and L["Detailed CPU recording for %d seconds: play as usual."]
			or L["CPU recording for %d seconds: play as usual."]):format(seconds))
	end
end)

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

	-- The graph.
	local Refresh -- (below)
	local switch = kit.PageSwitch(content, "profilerPage", L["Enable page"],
		L["On: the graph samples the game's figure every second and keeps it over a reload, and you can " ..
		"record. Off (to start with): nothing is sampled or saved, and it costs nothing."], intro,
		function() Refresh() end)
	local graphHeader = kit.Header(content, L["The game's figure, the last five minutes"], switch, -14)
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
	legend:SetText(table.concat(legendParts, "   ") .. "   |cffffd100--|r " .. L["average"])
	local nowText = Text(content, "GameFontHighlight", legend, 0, -8)
	local stateText = Text(content, "GameFontHighlightSmall", nowText, 0, -6)
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
			nowText:SetText("")
			stateText:SetText("")
			return
		end
		local newest = Slot(1)
		nowText:SetText(L["Now: |cffffd100%.1f%%|r of the frame (%.3f ms of %.2f ms)   |   %d s: average %.1f%%, " ..
			"peak %.1f%%   |   all addons %.1f%%"]:format(Share(addonMs[newest], appMs[newest]), addonMs[newest],
			appMs[newest], count, average, peak, Share(sumAll, sumApp)))
		local parts = {}
		for state = 1, #STATES do
			if bySeconds[state] > 0 then
				parts[#parts + 1] = L["%s |cffffd100%.1f%%|r (%.3f ms a frame, %d s)"]:format(L[STATES[state][1]],
					Share(byAddon[state], byApp[state]), byAddon[state] / bySeconds[state], bySeconds[state])
			end
		end
		stateText:SetText(table.concat(parts, "   ·   "))
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

	-- The recording.
	local recordHeader = kit.Header(content, L["Recording (the addon's own timers)"], stateText, -22)
	local status
	local function ArmedText(seconds, deep)
		return (deep and L["Starts when you close the settings: %d seconds, detailed."]
			or L["Starts when you close the settings: %d seconds."]):format(seconds)
	end
	local function Arm(seconds, deep)
		if ns.IsProfiling() or not PageOn() then
			return
		end
		armedSeconds, armedDeep = seconds, deep
		armer:Show()
		status:SetText(ArmedText(seconds, deep))
	end
	local record30 = Button(L["Record 30 s"], 110, L["Times the addon's busy parts for 30 seconds, starting " ..
		"when you close the settings. Play as usual meanwhile; open this page again for the results."],
		function() Arm(30) end)
	record30:SetPoint("TOPLEFT", recordHeader, "BOTTOMLEFT", 0, -8)
	local record120 = Button(L["Record 2 min"], 110, L["The same for two minutes."], function() Arm(120) end)
	record120:SetPoint("LEFT", record30, "RIGHT", 8, 0)
	local recordDeep = Button(L["Record 2 min, detailed"], 160, L["Two minutes with nearly every one of the " ..
		"addon's functions timed too, not just its busy parts, each listed under the part that called it: it " ..
		"shows what inside a busy part costs. The timing itself takes time, so everything reads higher than it is."],
		function() Arm(120, true) end)
	recordDeep:SetPoint("LEFT", record120, "RIGHT", 8, 0)
	local stop = Button(L["Stop"], 70, L["Stops the recording now (or the one waiting for the settings to close)."],
		function()
			armedSeconds = nil
			armer:Hide()
			ns.StopProfile()
			Refresh()
		end)
	stop:SetPoint("LEFT", recordDeep, "RIGHT", 8, 0)
	local copy = Button(L["Copy report"], 110, L["Everything here as text, to copy and send us (on Discord, " ..
		"or in a bug report): your game version, the graph's figures and the last recording. It's in English, " ..
		"for us to read."], function()
			ns.ShowText(L["Profiler: press Ctrl+C to copy"], ShareText())
		end)
	copy:SetPoint("LEFT", stop, "RIGHT", 8, 0)
	status = Text(content, "GameFontHighlightSmall", record30, 0, -8)
	status:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	local summary = Text(content, "GameFontHighlight", status, 0, -8)
	summary:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	local columns = Text(content, "GameFontDisableSmall", summary, 0, -10)
	columns:SetText(L["part: ms a frame · share of measured · calls a frame · KB of garbage a second " ..
		"(mouse over for more)"])

	-- The recorded sections: a row each, bar against the biggest, parts under it.
	-- (Their names are the code's own, in English.)
	local rows = {}
	local function RowTip(row)
		local data = row.data
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
	local function Row(i)
		local row = rows[i]
		if row then
			return row
		end
		row = CreateFrame("Frame", nil, content)
		row:SetHeight(16)
		row:SetPoint("TOPLEFT", i == 1 and columns or rows[i - 1], "BOTTOMLEFT", 0, i == 1 and -6 or -2)
		row:SetPoint("RIGHT", content, "RIGHT", -16, 0)
		row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.label:SetPoint("LEFT")
		row.label:SetWidth(210)
		row.label:SetJustifyH("LEFT")
		row.label:SetWordWrap(false)
		row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.value:SetPoint("RIGHT")
		row.value:SetWidth(190)
		row.value:SetJustifyH("RIGHT")
		row.track = row:CreateTexture(nil, "BACKGROUND")
		row.track:SetPoint("LEFT", 216, 0)
		row.track:SetPoint("RIGHT", -196, 0)
		row.track:SetHeight(10)
		row.track:SetColorTexture(1, 1, 1, 0.06)
		row.bar = row:CreateTexture(nil, "ARTWORK")
		row.bar:SetPoint("LEFT", row.track, "LEFT")
		row.bar:SetHeight(10)
		row.bar:SetColorTexture(1, 1, 1, 1)
		row:EnableMouse(true)
		row:SetScript("OnEnter", RowTip)
		row:SetScript("OnLeave", GameTooltip_Hide)
		rows[i] = row
		return row
	end
	local function FillRow(i, data, child, biggest, total)
		local row = Row(i)
		row.data, row.child = data, child
		row.label:SetText(child and "      > " .. data.name or data.name)
		if child then
			row.label:SetTextColor(0.7, 0.7, 0.7)
			row.value:SetText(("%.3f · - · %.2f · %.1f"):format(data.ms, data.calls, data.kb))
			row.bar:SetVertexColor(0.45, 0.55, 0.7, 0.8)
		else
			row.label:SetTextColor(1, 1, 1)
			row.value:SetText(("%.3f · %.0f%% · %.2f · %.1f"):format(data.ms, total > 0 and data.ms * 100 / total or 0,
				data.calls, data.kb))
			-- (Gold, orange where it makes a lot of garbage.)
			if data.kb > 5 then
				row.bar:SetVertexColor(1, 0.5, 0.15, 0.9)
			else
				row.bar:SetVertexColor(1, 0.82, 0, 0.9)
			end
		end
		local trackWidth = row.track:GetWidth()
		if not trackWidth or trackWidth <= 0 then
			trackWidth = 200
		end
		row.bar:SetWidth(math.max(trackWidth * math.min(data.ms / biggest, 1), 1))
		row:Show()
	end
	local function DrawRecording()
		if ns.IsProfiling() then
			status:SetText(L["Recording now: close the settings and play; open this page again when it's done."])
		elseif armedSeconds then
			status:SetText(ArmedText(armedSeconds, armedDeep))
		elseif not ns.lastProfile then
			status:SetText(L["No recording yet."])
		end
		local last = ns.lastProfile
		local used = 0
		if last then
			if not (ns.IsProfiling() or armedSeconds) then
				status:SetText((last.deep and L["Last recording (detailed): %s, %.0f s (%.0f fps). At the start: %s"]
					or L["Last recording: %s, %.0f s (%.0f fps). At the start: %s"]):format(
					date("%H:%M:%S", last.finished), last.seconds, last.fps, last.startState))
			end
			local text = L["Measured |cffffd100%.3f ms a frame|r (%.2f%% of the %.2f ms frame), garbage %.0f KB a " ..
				"second; frames over 1 / 5 / 16 ms: %d / %d / %d, worst %.2f ms"]:format(last.total,
				last.total * 100 / last.frameMs, last.frameMs, last.kb, last.spikes[1], last.spikes[5], last.spikes[16],
				last.worst)
			if last.game then
				text = text .. "\n" .. L["The game's figure meanwhile: |cffffd100%.3f ms a frame (%.1f%%)|r, so " ..
					"%.3f ms the timers don't cover; all addons %.3f ms"]:format(last.game.addon,
					Share(last.game.addon, last.game.app), last.game.addon - last.total, last.game.overall)
			end
			summary:SetText(text)
			local biggest = math.max(last.sections[1] and last.sections[1].ms or 0, 0.0001)
			for _, section in ipairs(last.sections) do
				used = used + 1
				FillRow(used, section, false, biggest, last.total)
				for c, child in ipairs(section.children) do
					if c > (last.deep and DEEP_CHILD_ROWS or CHILD_ROWS) then break end
					used = used + 1
					FillRow(used, child, true, biggest, last.total)
				end
			end
		else
			summary:SetText("")
		end
		columns:SetShown(used > 0)
		for i = used + 1, #rows do
			rows[i]:Hide()
		end
	end

	function Refresh()
		DrawGraph()
		DrawRecording()
		local on = PageOn() and true or false
		record30:SetEnabled(on)
		record120:SetEnabled(on)
		recordDeep:SetEnabled(on)
		if not on and not ns.IsProfiling() and not armedSeconds then
			status:SetText(L["Turn on Enable page to record."])
		end
	end
	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:HookScript("OnShow", function() onSample = DrawGraph end)
	canvas:SetScript("OnHide", function() onSample = nil end)
	-- (The graph's width is only known once laid out.)
	graph:SetScript("OnSizeChanged", DrawGraph)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Profiler")
end
