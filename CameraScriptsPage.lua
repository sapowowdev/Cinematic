-- Cinematic: the Camera Scripts page (dev copy), where camera scripts are
-- written (CameraScripts.lua runs them), and the preview window beside it.
--
-- The page: a script picked at the top (the built-in examples, then yours:
-- New, Copy, Delete, a name, Share and Import), what starts it (the Cameras
-- page rows set to it, and Use for to set a trigger's own row), Run now and
-- Stop. Then its steps, a row each (Together and Repeat with theirs indented
-- under them): a click picks one and opens its settings under it; the
-- buttons below add a step after the one picked (inside it, for Together and
-- Repeat). Then the stop rules, and When it ends, another list of steps.
-- The built-in ones show their steps but don't change: Copy one first.
--
-- The preview window plays the script on a drawing (from above, and from
-- the side), no camera moving, with a bar of its steps in time. It sits
-- beside the settings (docked) or anywhere you drag it (Pop out), and stays
-- up when they close.
local _, ns = ...
local L = ns.L

local LEFT, WIDTH = 16, 568
local ROW_H, INDENT = 22, 16
local EDITOR_H = 52
local SHARE_PREFIX, SHARE_FORMAT = "CINES", 1
local COLORS = {
	move = { 0.4, 0.62, 1 }, wait = { 0.6, 0.62, 0.68 }, flow = { 0.68, 0.52, 0.95 }, misc = { 0.92, 0.62, 0.3 },
}
local KIND_COLOR = { rotate = "move", tilt = "move", zoom = "move", zoomRand = "move", lineup = "move",
	wait = "wait", together = "flow", ["repeat"] = "flow", emote = "misc", putback = "misc" }
local KIND_NAMES = { rotate = "Rotate", tilt = "Tilt", zoom = "Zoom", zoomRand = "Zoom at random",
	lineup = "Line up", wait = "Wait", together = "Together", ["repeat"] = "Repeat", emote = "Emote",
	putback = "Put back" }
local FIELD_NAMES = { deg = "Degrees", secs = "Seconds", way = "Way", ease = "Ease", to = "Yards", min = "Nearest",
	max = "Furthest", token = "Emote", times = "Times" }
local CHOICE_NAMES = { left = "Left", right = "Right", random = "Either way", smooth = "Smooth", gentle = "Gentle",
	steady = "Steady" }
local RULE_NAMES = { camera = "You move the camera", fight = "A fight starts", walk = "You walk", zoom = "You zoom",
	ends = "Its trigger ends" }
local ACTION_NAMES = { stop = "Stop, leave it there", putback = "Run When it ends", pause = "Pause, then carry on",
	restart = "Start again", ignore = "Carry on" }
local HINTS = {
	rotate = "Turns the view, as your Turn view left and right keys do. One turn at a time.",
	tilt = "Positive tilts the view down, negative up. It waits for a turn to finish: the game won't do both at once.",
	zoom = "Zooms to this many yards from you.",
	zoomRand = "Zooms somewhere between the two, picked each time it runs.",
	lineup = "Turns back to straight behind you, however far round it is.",
	wait = "Holds still. A short wait also gives the game a moment between moves.",
	together = "Runs the steps inside it at once; it's done when the longest is. Pick it and add steps to put them inside.",
	["repeat"] = "Runs the steps inside it again. 0 times: until the camera ends (the preview shows three).",
	emote = "Your character does this emote (a word, like wave or cheer).",
	putback = "Undoes every turn, tilt and zoom this script made.",
}
local function Translate(map)
	for key, text in pairs(map) do map[key] = L[text] end
end
ns.OnLanguage(function()
	for _, map in ipairs({ KIND_NAMES, FIELD_NAMES, CHOICE_NAMES, RULE_NAMES, ACTION_NAMES, HINTS }) do Translate(map) end
end)

local function Num(n)
	return (("%.1f"):format(n):gsub("%.0$", ""))
end

-- A step's line on the page.
local function StepText(step)
	local k = step.k
	if k == "rotate" then
		local way = step.way == "random" and L["either way"] or step.way == "left" and L["left"] or L["right"]
		return L["Rotate %s° %s over %s s"]:format(Num(step.deg), way, Num(step.secs))
	elseif k == "tilt" then
		if step.deg == 0 then return L["Tilt 0° (no tilt)"] end
		return (step.deg > 0 and L["Tilt %s° down over %s s"] or L["Tilt %s° up over %s s"]):format(Num(math.abs(step.deg)),
			Num(step.secs))
	elseif k == "zoom" then
		return L["Zoom to %s yd over %s s"]:format(Num(step.to), Num(step.secs))
	elseif k == "zoomRand" then
		return L["Zoom somewhere from %s to %s yd over %s s"]:format(Num(step.min), Num(step.max), Num(step.secs))
	elseif k == "lineup" then
		return L["Line up behind you over %s s"]:format(Num(step.secs))
	elseif k == "wait" then
		return L["Wait %s s"]:format(Num(step.secs))
	elseif k == "emote" then
		return L["Do /%s"]:format(step.token)
	elseif k == "putback" then
		return L["Put everything back over %s s"]:format(Num(step.secs))
	elseif k == "together" then
		return #step.steps == 0 and L["Together (empty: pick it and add steps)"] or L["Together: these at once"]
	elseif k == "repeat" then
		local text = step.times == 0 and L["Repeat until it ends"] or L["Repeat %s times"]:format(Num(step.times))
		return #step.steps == 0 and text .. " " .. L["(empty: pick it and add steps)"] or text
	end
	return k
end

local function CountSteps(list)
	local n = 0
	for _, step in ipairs(list) do
		n = n + 1 + (step.steps and CountSteps(step.steps) or 0)
	end
	return n
end

-- Where a step is: its list and place (searched through both lists).
local function FindStep(list, step)
	for i, each in ipairs(list) do
		if each == step then return list, i end
		if each.steps then
			local found, at = FindStep(each.steps, step)
			if found then return found, at end
		end
	end
end

local page = {} -- the page's state and widgets
local preview -- the preview window, once made

-- A choice: a dropdown (or, on a client without the modern one, a button
-- that steps through them). choices() and value() are asked each time.
local function Choice(parent, width, choices, value, set, nameOf)
	local ok, pick = ns.MenuDropdown(parent)
	if ok and pick and pick.SetupMenu then
		pick:SetWidth(width)
		pick:SetupMenu(function(_, root)
			for _, choice in ipairs(choices()) do
				root:CreateRadio(nameOf(choice), function() return value() == choice end, function() set(choice) end)
			end
		end)
		pick.Refresh = function(self) self:GenerateMenu() end
	else
		pick = ns.PanelButton(parent)
		pick:SetSize(width, 22)
		pick:SetScript("OnClick", function()
			local list, now = choices(), value()
			for i, choice in ipairs(list) do
				if choice == now then
					set(list[i % #list + 1])
					return
				end
			end
			if list[1] then set(list[1]) end
		end)
		pick.Refresh = function(self) self:SetText(nameOf(value()) or "") end
	end
	pick.searchSkip = true
	return pick
end

local function Button(parent, text, width)
	local button = ns.PanelButton(parent)
	button:SetSize(width, 22)
	button:SetText(text)
	return button
end

local function Box(parent, width)
	local box = ns.SkinEditBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return box
end

local function IconButton(parent, art, tip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(16, 16)
	button:SetNormalTexture(art)
	button:SetHighlightTexture(art)
	button:GetHighlightTexture():SetAlpha(0.4)
	if tip then
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	return button
end

-- ---------------------------------------------------------------------------
-- The preview window
-- ---------------------------------------------------------------------------

local VIEW, SIDE = 200, 84
local RINGS, SEGMENTS = { 3, 6, 9, 12 }, 32
local YARD = (VIEW / 2 - 8) / 13 -- pixels a yard, from above
local SIDE_YARD = 9
local START_HEIGHT = 25 -- degrees: the camera's height above you the drawing starts at

local function NewLine(parent, r, g, b, a, thick)
	if not parent.CreateLine then return nil end
	local line = parent:CreateLine(nil, "ARTWORK")
	line:SetThickness(thick or 1)
	line:SetColorTexture(r, g, b, a)
	return line
end
local function SetLine(line, parent, x1, y1, x2, y2)
	if not line then return end
	line:SetStartPoint("CENTER", parent, x1, y1)
	line:SetEndPoint("CENTER", parent, x2, y2)
end
local function Dot(parent, size, r, g, b)
	local dot = parent:CreateTexture(nil, "OVERLAY")
	dot:SetSize(size, size)
	dot:SetColorTexture(r, g, b, 1)
	return dot
end

local function Store()
	local db = ns.GetDB()
	if type(db.cameraScripts) ~= "table" then db.cameraScripts = {} end
	return db.cameraScripts
end

-- The settings window the page is in (to dock beside).
local function SettingsWindow()
	local frame = page.canvas
	while frame and frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
	return frame
end

local function PlacePreview()
	local w = preview
	local saved = Store().preview
	w:ClearAllPoints()
	if type(saved) == "table" and saved.x and saved.y then
		w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
		w.dock:SetText(L["Dock"])
	else
		local settings = SettingsWindow()
		if settings and settings:IsShown() then
			w:SetPoint("TOPLEFT", settings, "TOPRIGHT", 4, 0)
		else
			w:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
		end
		w.dock:SetText(L["Pop out"])
	end
end

-- Draws the camera where the plan has it at t.
local function DrawPreview()
	local w = preview
	if not w.plan then return end
	local yaw, pitch, zoom, active = ns.SampleCameraPlan(w.plan, w.t, w.start)
	local height = math.max(-10, math.min(85, START_HEIGHT - pitch))
	local flat = math.min(13, zoom * math.cos(math.rad(height)))
	-- From above: you in the middle facing up; the view turned left puts the
	-- camera round to your right.
	local cx, cy = math.sin(math.rad(yaw)) * flat * YARD, -math.cos(math.rad(yaw)) * flat * YARD
	w.camDot:ClearAllPoints()
	w.camDot:SetPoint("CENTER", w.view, "CENTER", cx, cy)
	SetLine(w.sight, w.view, cx, cy, 0, 0)
	local toward = math.atan2(-cy, -cx)
	for i, side in ipairs({ -0.45, 0.45 }) do
		SetLine(w.cone[i], w.view, cx, cy, cx + math.cos(toward + side) * 46, cy + math.sin(toward + side) * 46)
	end
	-- From the side: you standing on the ground, the camera up on its arc.
	local hx, hy = -SIDE / 2 + 14, -40
	local sx = hx + math.cos(math.rad(height)) * math.min(zoom, 9) * SIDE_YARD * 0.7
	local sy = hy + math.sin(math.rad(height)) * math.min(zoom, 9) * SIDE_YARD
	w.sideDot:ClearAllPoints()
	w.sideDot:SetPoint("CENTER", w.side, "CENTER", math.min(sx, SIDE / 2 - 6), math.max(-90, math.min(90, sy)))
	SetLine(w.sideSight, w.side, math.min(sx, SIDE / 2 - 6), math.max(-90, math.min(90, sy)), hx, hy)
	w.readout:SetText(L["Turn %d°   Tilt %d°   Zoom %s yd   %s / %s s"]:format(math.floor(yaw + 0.5),
		math.floor(pitch + 0.5), Num(zoom), Num(w.t), Num(w.plan.total)))
	w.head:ClearAllPoints()
	w.head:SetPoint("LEFT", w.bar, "LEFT", (w.bar:GetWidth() - 2) * math.min(1, w.t / w.plan.total), 0)
	w.status:SetText(w.message or "")
	if page.active ~= active then
		page.active = active
		if page.Paint then page.Paint() end
	end
end

-- Lays the script out again (after a change) and draws its steps' bar.
function ns.RefreshCameraScriptPreview()
	local w = preview
	if not w or not w:IsShown() or not page.script then return end
	w.title:SetText(L["Preview: %s"]:format(page.script.name))
	w.start = { yaw = 0, pitch = 0, zoom = math.max(2, GetCameraZoom and GetCameraZoom() or 8) }
	w.plan = ns.PlanCameraScript(page.script, w.start)
	w.t = math.min(w.t or 0, w.plan.total)
	for _, seg in ipairs(w.segments) do seg:Hide() end
	local width = w.bar:GetWidth()
	for i, span in ipairs(w.plan.spans) do
		local seg = w.segments[i]
		if not seg then
			seg = w.bar:CreateTexture(nil, "ARTWORK")
			w.segments[i] = seg
		end
		local c = COLORS[KIND_COLOR[span.step.k]] or COLORS.wait
		seg:SetColorTexture(c[1], c[2], c[3], i % 2 == 0 and 0.75 or 0.95)
		seg:ClearAllPoints()
		seg:SetPoint("TOPLEFT", w.bar, "TOPLEFT", width * span.t0 / w.plan.total, -1)
		seg:SetSize(math.max(1, width * (span.t1 - span.t0) / w.plan.total), w.bar:GetHeight() - 2)
		seg:Show()
	end
	DrawPreview()
end

local function SimRule()
	local w = preview
	local rules = page.script.rules
	local action = rules.camera
	if not w.playing and w.t == 0 then
		w.message = L["Press Play first."]
	elseif action == "stop" then
		w.playing = false
		w.message = L["You moved the camera: it stops, and the camera's yours where it is."]
	elseif action == "putback" then
		w.t = math.max(w.t, w.plan.endStart)
		w.message = L["You moved the camera: on to When it ends."]
	elseif action == "pause" then
		w.pausedLeft = rules.cameraSecs
		w.message = L["You moved the camera: it waits %s s, then carries on."]:format(Num(rules.cameraSecs))
	else
		w.t = 0
		w.message = L["You moved the camera: it starts again."]
	end
	w.play:SetText(w.playing and L["Pause"] or L["Play"])
	DrawPreview()
end

local function MakePreview()
	local w = CreateFrame("Frame", "CinematicScriptPreview", UIParent, "BackdropTemplate")
	preview = w
	w:SetSize(318, 372)
	w:SetFrameStrata("DIALOG")
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	if w.SetBackdrop then
		w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	end
	ns.SkinWindow(w)
	tinsert(UISpecialFrames, "CinematicScriptPreview")
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", function(self)
		local saved = Store().preview
		if type(saved) == "table" and saved.x then self:StartMoving() end
	end)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Store().preview = { x = self:GetLeft(), y = self:GetTop() }
	end)

	w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	w.title:SetPoint("TOPLEFT", 12, -10)
	w.title:SetPoint("RIGHT", -92, 0)
	w.title:SetJustifyH("LEFT")
	w.title:SetWordWrap(false)
	local close = ns.SkinClose(CreateFrame("Button", nil, w, "UIPanelCloseButton"))
	close:SetPoint("TOPRIGHT", 0, 0)
	w.dock = Button(w, L["Pop out"], 70)
	w.dock:SetPoint("TOPRIGHT", -28, -6)
	w.dock:SetScript("OnClick", function()
		local store = Store()
		if type(store.preview) == "table" and store.preview.x then
			store.preview = nil
		else
			store.preview = { x = w:GetLeft() + 30, y = w:GetTop() - 30 }
		end
		PlacePreview()
	end)
	ns.lowHealthKit.Tooltip(w.dock, L["Pop out: drag the window anywhere (by its edge). Dock: back beside the settings."])

	local view = CreateFrame("Frame", nil, w)
	view:SetSize(VIEW, VIEW)
	view:SetPoint("TOPLEFT", 12, -34)
	local viewBg = view:CreateTexture(nil, "BACKGROUND")
	viewBg:SetAllPoints()
	viewBg:SetColorTexture(0, 0, 0, 0.45)
	w.view = view
	for _, yards in ipairs(RINGS) do
		local r = yards * YARD
		for i = 1, SEGMENTS do
			local a1, a2 = (i - 1) / SEGMENTS * 2 * math.pi, i / SEGMENTS * 2 * math.pi
			SetLine(NewLine(view, 0.5, 0.5, 0.55, 0.35), view, math.cos(a1) * r, math.sin(a1) * r, math.cos(a2) * r,
				math.sin(a2) * r)
		end
		local label = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		label:SetPoint("BOTTOM", view, "CENTER", 0, r + 1)
		label:SetText(L["%d yd"]:format(yards))
	end
	local you = Dot(view, 7, 1, 1, 1)
	you:SetPoint("CENTER")
	SetLine(NewLine(view, 1, 1, 1, 0.9, 2), view, 0, 0, 0, 14) -- (facing up)
	w.sight = NewLine(view, 1, 0.82, 0, 0.8, 1)
	w.cone = { NewLine(view, 1, 0.82, 0, 0.35), NewLine(view, 1, 0.82, 0, 0.35) }
	w.camDot = Dot(view, 9, 1, 0.82, 0)

	local side = CreateFrame("Frame", nil, w)
	side:SetSize(SIDE, VIEW)
	side:SetPoint("TOPLEFT", view, "TOPRIGHT", 8, 0)
	local sideBg = side:CreateTexture(nil, "BACKGROUND")
	sideBg:SetAllPoints()
	sideBg:SetColorTexture(0, 0, 0, 0.45)
	w.side = side
	SetLine(NewLine(side, 0.5, 0.5, 0.55, 0.6, 2), side, -SIDE / 2 + 2, -62, SIDE / 2 - 2, -62)
	local body = side:CreateTexture(nil, "ARTWORK")
	body:SetColorTexture(1, 1, 1, 0.9)
	body:SetSize(6, 22)
	body:SetPoint("BOTTOM", side, "CENTER", -SIDE / 2 + 14, -62)
	w.sideSight = NewLine(side, 1, 0.82, 0, 0.8)
	w.sideDot = Dot(side, 8, 1, 0.82, 0)
	local sideLabel = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sideLabel:SetPoint("BOTTOM", 0, 6)
	sideLabel:SetText(L["side"])

	w.readout = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	w.readout:SetPoint("TOPLEFT", view, "BOTTOMLEFT", 0, -8)
	w.bar = CreateFrame("Frame", nil, w)
	w.bar:SetSize(VIEW + 8 + SIDE, 12)
	w.bar:SetPoint("TOPLEFT", w.readout, "BOTTOMLEFT", 0, -6)
	local barBg = w.bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(0, 0, 0, 0.5)
	w.head = w.bar:CreateTexture(nil, "OVERLAY")
	w.head:SetColorTexture(1, 1, 1, 1)
	w.head:SetSize(2, 14)
	w.segments = {}

	w.play = Button(w, L["Play"], 70)
	w.play:SetPoint("TOPLEFT", w.bar, "BOTTOMLEFT", 0, -8)
	w.play:SetScript("OnClick", function()
		if not w.plan then return end
		if w.playing then
			w.playing = false
		else
			if w.t >= w.plan.total then w.t = 0 end
			w.playing, w.message, w.pausedLeft = true, nil, nil
		end
		w.play:SetText(w.playing and L["Pause"] or L["Play"])
		DrawPreview()
	end)
	local moveCam = Button(w, L["You move the camera"], 140)
	moveCam:SetPoint("LEFT", w.play, "RIGHT", 4, 0)
	moveCam:SetScript("OnClick", SimRule)
	ns.lowHealthKit.Tooltip(moveCam, L["What the script does when you move the camera yourself (its first stop rule)."])
	local runNow = Button(w, L["Run in game"], 84)
	runNow:SetPoint("LEFT", moveCam, "RIGHT", 4, 0)
	runNow:SetScript("OnClick", function() page.RunNow() end)
	ns.lowHealthKit.Tooltip(runNow, L["Moves the real camera through this script now (Stop on the page, or /cine script stop, ends it)."])

	w.status = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	w.status:SetPoint("TOPLEFT", w.play, "BOTTOMLEFT", 0, -8)
	w.status:SetWidth(294)
	w.status:SetJustifyH("LEFT")

	w:SetScript("OnUpdate", function(_, elapsed)
		if not w.playing or not w.plan then return end
		if w.pausedLeft then
			w.pausedLeft = w.pausedLeft - elapsed
			if w.pausedLeft <= 0 then
				w.pausedLeft, w.message = nil, L["Carried on where it left off."]
			end
		else
			w.t = math.min(w.plan.total, w.t + elapsed)
		end
		if w.t >= w.plan.total then
			w.playing = false
			w.play:SetText(L["Play"])
		end
		DrawPreview()
	end)
	w:SetScript("OnHide", function()
		w.playing = false
		page.active = nil
		if page.Paint then page.Paint() end
	end)
	w:Hide()
end

function ns.ShowCameraScriptPreview()
	if not preview then MakePreview() end
	preview:Show()
	PlacePreview()
	preview.t, preview.playing, preview.message = 0, false, nil
	preview.play:SetText(L["Play"])
	ns.RefreshCameraScriptPreview()
end

-- ---------------------------------------------------------------------------
-- The share window
-- ---------------------------------------------------------------------------

local share
local function ShareWindow()
	if share then return share end
	share = CreateFrame("Frame", "CinematicScriptShare", UIParent, "BackdropTemplate")
	share:SetSize(460, 260)
	share:SetPoint("CENTER")
	share:SetFrameStrata("DIALOG")
	share:EnableMouse(true)
	if share.SetBackdrop then
		share:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	end
	ns.SkinWindow(share)
	tinsert(UISpecialFrames, "CinematicScriptShare")
	share.title = share:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	share.title:SetPoint("TOPLEFT", 14, -12)
	local close = ns.SkinClose(CreateFrame("Button", nil, share, "UIPanelCloseButton"))
	close:SetPoint("TOPRIGHT", 0, 0)
	share.hint = share:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	share.hint:SetPoint("TOPLEFT", 14, -32)
	share.hint:SetWidth(430)
	share.hint:SetJustifyH("LEFT")
	local scroll = ns.SkinScroll(CreateFrame("ScrollFrame", nil, share, "UIPanelScrollFrameTemplate"))
	scroll:SetPoint("TOPLEFT", 14, -64)
	scroll:SetPoint("BOTTOMRIGHT", -34, 44)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(400)
	scroll:SetScrollChild(box)
	box:SetScript("OnEscapePressed", function() share:Hide() end)
	share.box = box
	share.status = share:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	share.status:SetPoint("BOTTOMLEFT", 14, 18)
	share.status:SetWidth(300)
	share.status:SetJustifyH("LEFT")
	share.accept = Button(share, L["Add script"], 110)
	share.accept:SetPoint("BOTTOMRIGHT", -14, 12)
	local WHY = { empty = "", newer = "This script is from a newer Cinematic: update it to add this one.",
		other = "That isn't a camera script (they start CINES1:).", broken = "That isn't a whole script: copy it again, all of it." }
	box:SetScript("OnTextChanged", function(self, userInput)
		if share.mode == "export" then
			if userInput then
				self:SetText(share.text)
				self:HighlightText()
			end
			return
		end
		local data, why = ns.UnpackShared(SHARE_PREFIX, SHARE_FORMAT, self:GetText())
		share.data = data and ns.CleanCameraScript(data, "import")
		share.accept:SetEnabled(share.data ~= nil)
		share.status:SetText(share.data and L["%s: %d steps. Add script adds it to yours."]:format(share.data.name,
			CountSteps(share.data.steps) + CountSteps(share.data.ending)) or L[WHY[why] or ""])
	end)
	share.accept:SetScript("OnClick", function()
		if not share.data then return end
		local script = ns.AddCameraScript(share.data, share.data.name)
		if not script then
			ns.Print(L["You have 30 camera scripts already: delete one to add another."])
			return
		end
		share:Hide()
		page.Pick(script.id)
	end)
	return share
end

local function ShowShare(export)
	local window = ShareWindow()
	window.mode = export and "export" or "import"
	if export then
		local script = page.script
		window.text = ns.PackShared(SHARE_PREFIX, SHARE_FORMAT, { name = script.name, steps = script.steps,
			ending = script.ending, rules = script.rules })
		window.title:SetText(L["Share %s"]:format(script.name))
		window.hint:SetText(L["Press Ctrl+C to copy this, then paste it wherever your friends will see it. They " ..
			"add it with Import on their Camera Scripts page."])
		window.accept:Hide()
		window.status:SetText("")
	else
		window.text = ""
		window.title:SetText(L["Import a camera script"])
		window.hint:SetText(L["Paste in a script someone shared (Ctrl+V), then Add script. It's added as a new " ..
			"script of yours."])
		window.accept:Show()
		window.accept:SetEnabled(false)
	end
	window:Show()
	window.box:SetText(window.text)
	window.box:SetFocus()
	if export then window.box:HighlightText() end
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

-- A step row (pooled): its line, colour strip, and up, down and delete.
local function StepRow(content)
	local row = CreateFrame("Button", nil, content)
	row:SetSize(WIDTH, ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.strip = row:CreateTexture(nil, "ARTWORK")
	row.strip:SetSize(3, ROW_H - 4)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.text:SetPoint("RIGHT", -64, 0)
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.06)
	row.del = IconButton(row, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", L["Remove this step"])
	row.del:SetPoint("RIGHT", -4, 0)
	row.down = IconButton(row, "Interface\\Buttons\\Arrow-Down-Up", L["Move down"])
	row.down:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
	row.up = IconButton(row, "Interface\\Buttons\\Arrow-Up-Up", L["Move up"])
	row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
	row:SetScript("OnClick", function(self)
		page.selected = page.selected ~= self.step and self.step or nil
		page.Layout()
	end)
	row.up:SetScript("OnClick", function(self) page.MoveStep(self:GetParent().step, -1) end)
	row.down:SetScript("OnClick", function(self) page.MoveStep(self:GetParent().step, 1) end)
	row.del:SetScript("OnClick", function(self) page.DeleteStep(self:GetParent().step) end)
	return row
end

-- The settings of the step picked, under its row: up to four fields and a hint.
local function MakeEditor(content)
	local editor = CreateFrame("Frame", nil, content)
	editor:SetSize(WIDTH, EDITOR_H)
	local bg = editor:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 0.82, 0, 0.06)
	editor.slots = {}
	for i = 1, 4 do
		local slot = {}
		slot.label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		slot.label:SetPoint("TOPLEFT", 28 + (i - 1) * 136, -8)
		slot.box = Box(editor, 54)
		slot.box:SetPoint("LEFT", slot.label, "RIGHT", 8, 0)
		local function Commit(box)
			local step, field = editor.step, slot.field
			if not step or not field then return end
			step[field[1]] = ns.CleanCameraScriptField(field, box:GetText())
			box:SetText(field[2] == "num" and Num(step[field[1]]) or step[field[1]])
			page.Changed()
		end
		slot.box:SetScript("OnEnterPressed", function(self) Commit(self) self:ClearFocus() end)
		slot.box:SetScript("OnEditFocusLost", Commit)
		slot.pick = Choice(editor, 84, function() return slot.field and slot.field[3] or {} end,
			function() return editor.step and slot.field and editor.step[slot.field[1]] end,
			function(choice)
				editor.step[slot.field[1]] = choice
				slot.pick:Refresh()
				page.Changed()
			end, function(choice) return CHOICE_NAMES[choice] or choice end)
		slot.pick:SetPoint("LEFT", slot.label, "RIGHT", 8, 0)
		editor.slots[i] = slot
	end
	editor.hint = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	editor.hint:SetPoint("BOTTOMLEFT", 28, 7)
	editor.hint:SetWidth(WIDTH - 40)
	editor.hint:SetJustifyH("LEFT")
	editor.hint:SetWordWrap(false)

	function editor:Edit(step, locked)
		self.step = step
		local fields = ns.CAMERA_SCRIPT_KINDS[step.k].fields
		for i, slot in ipairs(self.slots) do
			local field = not locked and fields[i]
			slot.field = field or nil
			slot.label:SetShown(field and true or false)
			slot.box:SetShown(field and field[2] ~= "pick" or false)
			slot.pick:SetShown(field and field[2] == "pick" or false)
			if field then
				slot.label:SetText(FIELD_NAMES[field[1]] or field[1])
				if field[2] == "pick" then
					slot.pick:Refresh()
				else
					slot.box:SetText(field[2] == "num" and Num(step[field[1]]) or step[field[1]])
					slot.box:SetCursorPosition(0)
				end
			end
		end
		self.hint:SetText(locked and L["A built-in example: Copy it to change it."] or HINTS[step.k] or "")
	end
	return editor
end

function ns.CreateCameraScriptsPanel(kit)
	local canvas, content = kit.CreateScrollPage(true)
	page.canvas, page.content = canvas, content
	local title = kit.Label(content, "GameFontNormalLarge", L["Camera Scripts"])
	title:SetPoint("TOPLEFT", LEFT, -16)
	kit.PageIntro(content, title, L["Cameras made of small steps: rotate, tilt, zoom, wait, and Together and " ..
		"Repeat for steps at once or again. Stop rules say what happens when you move the camera, walk, zoom, a " ..
		"fight starts or its trigger ends. A script is a camera: set a Cameras page row to it (or Use for, " ..
		"below), or Run now. The built-in ones are the steps our own cameras take, with your settings: copy one " ..
		"to make it yours. Dev copy only for now."])

	-- The script, and New, Copy, Delete.
	page.pick = Choice(content, 220, function()
		local ids = {}
		for _, script in ipairs(ns.CameraScripts()) do ids[#ids + 1] = script.id end
		return ids
	end, function() return page.id end, function(id) page.Pick(id) end, function(id)
		local script = ns.FindCameraScript(id)
		return script and (script.builtin and L["%s (built-in)"]:format(script.name) or script.name) or ""
	end)
	page.pick:SetPoint("TOPLEFT", LEFT, -46)
	local new = Button(content, L["New"], 70)
	new:SetPoint("LEFT", page.pick, "RIGHT", 10, 0)
	new:SetScript("OnClick", function()
		local script = ns.AddCameraScript(nil, L["My camera %d"]:format(#(Store().list or {}) + 1))
		if script then page.Pick(script.id) else ns.Print(L["You have 30 camera scripts already: delete one to add another."]) end
	end)
	kit.Tooltip(new, L["A new script of yours, with a few steps to start from."])
	local copy = Button(content, L["Copy"], 70)
	copy:SetPoint("LEFT", new, "RIGHT", 4, 0)
	copy:SetScript("OnClick", function()
		local script = ns.AddCameraScript(page.script)
		if script then page.Pick(script.id) else ns.Print(L["You have 30 camera scripts already: delete one to add another."]) end
	end)
	kit.Tooltip(copy, L["A copy of this script, yours to change."])
	page.delete = Button(content, L["Delete"], 70)
	page.delete:SetPoint("LEFT", copy, "RIGHT", 4, 0)
	page.delete:SetScript("OnClick", function()
		if page.confirmDelete == page.id then
			ns.DeleteCameraScript(page.id)
			page.confirmDelete = nil
			page.Pick("orbit")
		else
			page.confirmDelete = page.id
			page.delete:SetText(L["Sure?"])
		end
	end)
	kit.Tooltip(page.delete, L["Deletes this script (click twice). Rows set to it go back to no camera."])

	-- Its name, Share and Import.
	local nameLabel = kit.Label(content, "GameFontNormal", L["Name"])
	nameLabel:SetPoint("TOPLEFT", LEFT, -82)
	page.name = Box(content, 200)
	page.name:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
	page.name:SetMaxLetters(40)
	page.name:SetScript("OnEditFocusLost", function(self)
		local mine = page.script and ns.MyCameraScript(page.script.id)
		local text = self:GetText():gsub("|", ""):match("^%s*(.-)%s*$")
		if mine and text ~= "" then
			mine.name = text
			ns.CameraScriptChanged()
			page.pick:Refresh()
			ns.RefreshCameraScriptPreview()
		end
		self:SetText(page.script and page.script.name or "")
	end)
	page.nameText = kit.Label(content, "GameFontHighlight", "")
	page.nameText:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
	local shareButton = Button(content, L["Share"], 80)
	shareButton:SetPoint("TOPLEFT", LEFT + 300, -78)
	shareButton:SetScript("OnClick", function() ShowShare(true) end)
	kit.Tooltip(shareButton, L["A string of this script to give to friends."])
	local import = Button(content, L["Import"], 80)
	import:SetPoint("LEFT", shareButton, "RIGHT", 4, 0)
	import:SetScript("OnClick", function() ShowShare(false) end)
	kit.Tooltip(import, L["Add a script someone shared with you."])

	-- What starts it, Use for, Run now, Stop, Preview.
	page.starts = kit.Label(content, "GameFontHighlightSmall", "")
	page.starts:SetPoint("TOPLEFT", LEFT, -112)
	page.starts:SetWidth(WIDTH)
	local ok, useFor = ns.MenuDropdown(content)
	if ok and useFor and useFor.SetupMenu then
		useFor:SetWidth(170)
		useFor:SetupMenu(function(_, root)
			root:CreateTitle(L["Start it on"])
			for _, trigger in ipairs(ns.CAMERA_TRIGGERS) do
				if ns.TriggerTakesScripts(trigger) and page.script then
					local key = trigger.key
					root:CreateCheckbox(ns.CameraTriggerName(key), function()
						return ns.CameraRowValue(key, "camera") == "script:" .. page.script.id
					end, function()
						local on = ns.CameraRowValue(key, "camera") ~= "script:" .. page.script.id
						ns.UseCameraScriptFor(key, page.script.id, on)
						page.Layout()
					end)
				end
			end
		end)
		if useFor.SetDefaultText then useFor:SetDefaultText(L["Use for..."]) end
		useFor:SetPoint("TOPLEFT", LEFT, -136)
		kit.Tooltip(useFor, L["Sets a trigger's own row on the Cameras page to this script (its copies there are " ..
			"set on that page)."])
		page.useFor = useFor
	end
	local runNow = Button(content, L["Run now"], 80)
	runNow:SetPoint("TOPLEFT", LEFT + 190, -136)
	function page.RunNow()
		local played, why = ns.PlayCameraScript(page.script)
		if not played then ns.Print(why) end
	end
	runNow:SetScript("OnClick", page.RunNow)
	kit.Tooltip(runNow, L["Moves the real camera through this script now. Its stop rules count, as for a trigger."])
	local stop = Button(content, L["Stop"], 70)
	stop:SetPoint("LEFT", runNow, "RIGHT", 4, 0)
	stop:SetScript("OnClick", function() ns.StopCameraScript() end)
	local previewButton = Button(content, L["Preview"], 80)
	previewButton:SetPoint("LEFT", stop, "RIGHT", 4, 0)
	previewButton:SetScript("OnClick", function()
		if preview and preview:IsShown() then preview:Hide() else ns.ShowCameraScriptPreview() end
	end)
	kit.Tooltip(previewButton, L["Plays the script on a drawing, in a window of its own: no camera moves."])

	-- The lists and rules, laid out by Layout.
	page.rows, page.used = {}, 0
	page.editor = MakeEditor(content)
	page.headers = {}
	for _, key in ipairs({ "steps", "rules", "ending" }) do
		page.headers[key] = kit.Label(content, "GameFontNormal", key == "steps" and L["Steps"] or key == "rules"
			and L["Stop rules"] or L["When it ends"])
	end
	page.addBars = {}
	for _, list in ipairs({ "steps", "ending" }) do
		local bar = CreateFrame("Frame", nil, content)
		bar:SetSize(WIDTH, 50)
		for i, kind in ipairs(ns.CAMERA_SCRIPT_ADDABLE) do
			local add = Button(bar, "+ " .. KIND_NAMES[kind], 110)
			add:SetPoint("TOPLEFT", ((i - 1) % 5) * 114, -math.floor((i - 1) / 5) * 26)
			add:SetScript("OnClick", function() page.AddStep(kind, list) end)
		end
		page.addBars[list] = bar
	end
	page.ruleRows = {}
	for i, rule in ipairs(ns.CAMERA_SCRIPT_RULES) do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(WIDTH, 26)
		row.label = kit.Label(row, "GameFontHighlightSmall", RULE_NAMES[rule.key])
		row.label:SetPoint("LEFT", 8, 0)
		row.label:SetWidth(170)
		row.pick = Choice(row, 180, function() return rule.actions end,
			function() return page.script and page.script.rules[rule.key] end,
			function(action)
				page.script.rules[rule.key] = action
				page.Changed()
			end, function(action) return ACTION_NAMES[action] end)
		row.pick:SetPoint("LEFT", 186, 0)
		row.fixed = kit.Label(row, "GameFontHighlightSmall", "")
		row.fixed:SetPoint("LEFT", 192, 0)
		row.secsLabel = kit.Label(row, "GameFontHighlightSmall", L["for"])
		row.secsLabel:SetPoint("LEFT", row.pick, "RIGHT", 10, 0)
		row.secs = Box(row, 40)
		row.secs:SetPoint("LEFT", row.secsLabel, "RIGHT", 8, 0)
		row.secsUnit = kit.Label(row, "GameFontHighlightSmall", L["s"])
		row.secsUnit:SetPoint("LEFT", row.secs, "RIGHT", 4, 0)
		local function Commit(box)
			local secs = tonumber(box:GetText())
			if secs and page.script then
				page.script.rules[rule.key .. "Secs"] = math.max(1, math.min(60, secs))
				page.Changed()
			end
			box:SetText(page.script and Num(page.script.rules[rule.key .. "Secs"]) or "")
		end
		row.secs:SetScript("OnEditFocusLost", Commit)
		row.rule = rule
		page.ruleRows[i] = row
	end

	-- Picks a script (by id) for the page.
	function page.Pick(id)
		local script = ns.MyCameraScript(id) or ns.FindCameraScript(id) or ns.FindCameraScript("orbit")
		page.id, page.script, page.selected = script.id, script, nil
		page.locked = script.builtin and true or false
		page.confirmDelete = nil
		page.delete:SetText(L["Delete"])
		page.Layout()
		ns.RefreshCameraScriptPreview()
	end

	-- After a change: the page and the preview follow.
	function page.Changed()
		page.Layout()
		ns.RefreshCameraScriptPreview()
	end

	function page.AddStep(kind, listKey)
		local script = page.script
		if page.locked or not script then return end
		if CountSteps(script.steps) + CountSteps(script.ending) >= 80 then
			ns.Print(L["A script holds 80 steps at most."])
			return
		end
		local step = ns.NewCameraScriptStep(kind)
		local sel = page.selected
		local list, at
		if sel then list, at = FindStep(script[listKey], sel) end
		if sel and list and sel.steps then
			table.insert(sel.steps, step)
		elseif list then
			table.insert(list, at + 1, step)
		else
			table.insert(script[listKey], step)
		end
		page.selected = step
		page.Changed()
	end

	function page.MoveStep(step, by)
		local script = page.script
		local list, at = FindStep(script.steps, step)
		if not list then list, at = FindStep(script.ending, step) end
		if not list or not list[at + by] then return end
		list[at], list[at + by] = list[at + by], list[at]
		page.Changed()
	end

	function page.DeleteStep(step)
		local script = page.script
		local list, at = FindStep(script.steps, step)
		if not list then list, at = FindStep(script.ending, step) end
		if not list then return end
		table.remove(list, at)
		if page.selected == step then page.selected = nil end
		page.Changed()
	end

	-- Colours the rows: picked, and the step the preview's playing.
	function page.Paint()
		for i = 1, page.used do
			local row = page.rows[i]
			if row.step == page.active then
				row.bg:SetColorTexture(1, 0.82, 0, 0.16)
			elseif row.step == page.selected then
				row.bg:SetColorTexture(1, 0.82, 0, 0.1)
			else
				row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.0)
			end
		end
	end

	-- Everything below the top rows, placed down the page.
	local function PlaceRows(list, depth, y)
		for _, step in ipairs(list) do
			page.used = page.used + 1
			local row = page.rows[page.used]
			if not row then
				row = StepRow(content)
				page.rows[page.used] = row
			end
			row.step = step
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", LEFT, y)
			local c = COLORS[KIND_COLOR[step.k]] or COLORS.wait
			row.strip:ClearAllPoints()
			row.strip:SetPoint("LEFT", 4 + depth * INDENT, 0)
			row.strip:SetColorTexture(c[1], c[2], c[3], 1)
			row.text:ClearAllPoints()
			row.text:SetPoint("LEFT", 14 + depth * INDENT, 0)
			row.text:SetPoint("RIGHT", -64, 0)
			row.text:SetText(("|cff%02x%02x%02x%s|r  %s"):format(math.floor(c[1] * 255), math.floor(c[2] * 255),
				math.floor(c[3] * 255),
				KIND_NAMES[step.k] or step.k, StepText(step)))
			row.up:SetShown(not page.locked)
			row.down:SetShown(not page.locked)
			row.del:SetShown(not page.locked)
			row:Show()
			y = y - ROW_H
			if step == page.selected then
				page.editor:ClearAllPoints()
				page.editor:SetPoint("TOPLEFT", LEFT, y)
				page.editor:Edit(step, page.locked)
				page.editor:Show()
				page.editorShown = true
				y = y - EDITOR_H - 2
			end
			if step.steps then y = PlaceRows(step.steps, depth + 1, y) end
		end
		return y
	end

	function page.Layout()
		local script = page.script
		if not script then return end
		page.pick:Refresh()
		page.name:SetShown(not page.locked)
		page.nameText:SetShown(page.locked)
		page.nameText:SetText(script.name)
		if not page.name:HasFocus() then page.name:SetText(script.name) end
		page.delete:SetShown(not page.locked)
		local keys = ns.CameraScriptTriggers(script.id)
		local names = {}
		for _, key in ipairs(keys) do names[#names + 1] = ns.CameraTriggerName(key) end
		page.starts:SetText(#names > 0 and L["Starts when: %s"]:format(table.concat(names, ", "))
			or L["Starts when: no trigger yet. Pick one with Use for, or set a row on the Cameras page to it."])
		if page.useFor then page.useFor:GenerateMenu() end

		page.used, page.editorShown = 0, false
		local y = -172
		page.headers.steps:SetPoint("TOPLEFT", LEFT, y)
		y = PlaceRows(script.steps, 0, y - 20)
		local bar = page.addBars.steps
		bar:SetShown(not page.locked)
		if not page.locked then
			bar:SetPoint("TOPLEFT", LEFT, y - 6)
			y = y - 6 - 52
		end
		page.headers.rules:SetPoint("TOPLEFT", LEFT, y - 14)
		y = y - 34
		for _, row in ipairs(page.ruleRows) do
			local key = row.rule.key
			row:SetPoint("TOPLEFT", LEFT, y)
			row.pick:SetShown(not page.locked)
			row.fixed:SetShown(page.locked)
			row.fixed:SetText(ACTION_NAMES[script.rules[key]] or "")
			if not page.locked then row.pick:Refresh() end
			local pause = script.rules[key] == "pause"
			row.secsLabel:SetShown(pause)
			row.secs:SetShown(pause and not page.locked)
			row.secsUnit:SetShown(pause)
			if pause and not row.secs:HasFocus() then row.secs:SetText(Num(script.rules[key .. "Secs"])) end
			y = y - 26
		end
		page.headers.ending:SetPoint("TOPLEFT", LEFT, y - 14)
		y = y - 34
		y = PlaceRows(script.ending, 0, y)
		bar = page.addBars.ending
		bar:SetShown(not page.locked)
		if not page.locked then
			bar:SetPoint("TOPLEFT", LEFT, y - 6)
			y = y - 6 - 52
		end
		for i = page.used + 1, #page.rows do page.rows[i]:Hide() end
		if not page.editorShown then page.editor:Hide() end
		page.Paint()
		content:SetHeight(-y + 30)
	end

	canvas:SetScript("OnShow", kit.PageShown(function()
		if not page.script then page.Pick("orbit") else page.Pick(page.id) end
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Camera Scripts")
end
