-- The menu look (main page's Menu look, ns.MenuSkin): Cinematic's settings
-- pages and windows in HD, flat (dark, a thin edge), or SD, the game's own
-- buttons and windows. Each thing made by these has both looks and shows the
-- one now; ns.ApplyMenuSkin() puts them all in the look again when it
-- changes (the setting, or Forever's Character Models under Auto: checked as
-- a page or window opens). Buttons, windows, checkboxes, sliders, dropdowns
-- and text boxes; HD's accent (a tick, a slider's filled part) is gold.

local _, ns = ...

local skinned = setmetatable({}, { __mode = "k" }) -- (thing -> its function putting it in a look)
local applied -- (the look they're in)
local preview -- (the Grid Demo's switch: a look to try, not saved)

-- The look things are in now (or will be, made now). Worked out once, not
-- for each thing made; ns.ApplyMenuSkin looks again.
function ns.CurrentMenuSkin()
	applied = applied or preview or ns.MenuSkin()
	return applied
end

-- Puts thing in skin. A look that goes wrong (a client without some method)
-- mustn't stop a page being made: the first error's reported, once.
local reported
local function Apply(thing, apply, skin)
	local ok, err = pcall(apply, thing, skin)
	if not ok and not reported then
		reported = true
		geterrorhandler()(err)
	end
end

-- Every skinned thing in the look, when it's changed (force: all the same).
function ns.ApplyMenuSkin(force)
	local skin = preview or ns.MenuSkin()
	if skin == applied and not force then return end
	applied = skin
	for thing, apply in pairs(skinned) do Apply(thing, apply, skin) end
end

-- A look to try everywhere till it's cleared (nil): not saved.
function ns.PreviewMenuSkin(skin)
	preview = skin
	ns.ApplyMenuSkin()
end

local function Register(thing, apply)
	skinned[thing] = apply
	Apply(thing, apply, ns.CurrentMenuSkin())
end

-- Whether a control's usable (some clients' sliders can't say: then it is).
local function Enabled(control)
	return not control.IsEnabled or control:IsEnabled()
end

-- A flat edge and background on frame, under everything it has: the edge a
-- pixel out all round. Gives edge, bg.
--
-- The edge is one screen pixel, whatever the scale: a fixed 1 is less than
-- a pixel in the settings (their scale is under 1), and rounds away on some
-- rows. Worked out from frame's own scale each time it shows (once its
-- parents, the settings window among them, are set), only moved if it's changed.
-- Off the pixel grid: snapped, a sliver this thin can round to nothing on
-- some rows; off it, it always draws.
local function NoSnap(texture)
	if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
	if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end
local function SnapEdge(frame, edge, left)
	NoSnap(edge)
	local function Snap()
		local scale = frame:GetEffectiveScale()
		local px = 1
		if PixelUtil and PixelUtil.GetPixelToUIUnitFactor and scale and scale > 0 then
			px = PixelUtil.GetPixelToUIUnitFactor() / scale
		end
		if edge.px ~= px then
			edge.px = px
			edge:ClearAllPoints()
			edge:SetPoint("TOPLEFT", -(left or 0) - px, px)
			edge:SetPoint("BOTTOMRIGHT", px, -px)
		end
	end
	Snap()
	frame:HookScript("OnShow", Snap)
end
local function Flat(frame, r, g, b, a, edgeAlpha)
	local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	SnapEdge(frame, edge)
	edge:SetColorTexture(0.5, 0.5, 0.5, edgeAlpha)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetAllPoints()
	bg:SetColorTexture(r, g, b, a)
	NoSnap(bg)
	return edge, bg
end

local ACCENT = { 1, 0.82, 0 }

-- frame's textures (made by its template: call before adding ours), but keep's.
local function TexturesOf(frame, keep)
	local art = {}
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not (keep and keep[region]) then art[#art + 1] = region end
	end
	return art
end
local function ShowArt(art, shown)
	for _, piece in ipairs(art) do piece:SetAlpha(shown and 1 or 0) end
end
-- Calls fn after the control's greyed or brought back.
local function OnEnabledChange(control, fn)
	for _, method in ipairs({ "SetEnabled", "Enable", "Disable" }) do
		if control[method] then hooksecurefunc(control, method, fn) end
	end
end

-- The game's art on a button: three pieces on some clients, one texture on
-- others, and its pushed, disabled and highlight ones.
local function ButtonArt(button)
	local art = {}
	for _, piece in ipairs({ button.Left or false, button.Middle or false, button.Right or false,
		button:GetNormalTexture() or false, button:GetPushedTexture() or false,
		button:GetDisabledTexture() or false, button:GetHighlightTexture() or false }) do
		if piece and not art[piece] then
			art[piece] = true
			art[#art + 1] = piece
		end
	end
	return art
end

-- A UIPanelButtonTemplate button in both looks. HD: dark, a thin edge, a
-- lighter hover, dimmed while disabled. SD: as the game draws it. Its own:
-- button:SetSkinEdge(r, g, b, a), the HD edge's colour (a group's, say);
-- button:SetSkinTint(r, g, b), a colour on both looks (nil: none), as for
-- one that's on or wrong.
function ns.SkinButton(button)
	local art = ButtonArt(button)
	local edge, bg = Flat(button, 0.06, 0.06, 0.08, 0.9, 0.5)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.08)
	local edgeColor, tint = { 0.5, 0.5, 0.5, 0.5 }, nil
	local function Paint(self, skin)
		local hd = skin == "HD"
		edge:SetShown(hd)
		bg:SetShown(hd)
		hover:SetShown(hd)
		bg:SetAlpha(Enabled(self) and 1 or 0.5)
		if tint then
			edge:SetColorTexture(tint[1], tint[2], tint[3], 0.8)
		else
			edge:SetColorTexture(edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4])
		end
		-- (Alpha, not Hide: the game's button shows its own art again as it's pressed.)
		for _, piece in ipairs(art) do
			piece:SetAlpha(hd and 0 or 1)
			if piece.SetVertexColor then
				piece:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1)
			end
		end
	end
	function button:SetSkinEdge(r, g, b, a)
		edgeColor = { r, g, b, a or 0.5 }
		Paint(self, ns.CurrentMenuSkin())
	end
	function button:SetSkinTint(r, g, b)
		tint = r and { r, g, b } or nil
		Paint(self, ns.CurrentMenuSkin())
	end
	-- (Hooked: the game's button has its own, for its art.)
	button:HookScript("OnDisable", function() bg:SetAlpha(0.5) end)
	button:HookScript("OnEnable", function() bg:SetAlpha(1) end)
	Register(button, Paint)
	return button
end

-- A new UIPanelButtonTemplate button on parent, in both looks.
function ns.PanelButton(parent)
	return ns.SkinButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
end

-- A UIPanelCloseButton in both looks. HD: a small flat square with an X,
-- in the middle of the game's room for it.
function ns.SkinClose(button)
	local art = ButtonArt(button)
	local square = CreateFrame("Frame", nil, button)
	square:SetSize(18, 18)
	square:SetPoint("CENTER")
	square:SetFrameLevel(button:GetFrameLevel())
	local edge, bg = Flat(square, 0.06, 0.06, 0.08, 0.9, 0.5)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(square)
	hover:SetColorTexture(1, 1, 1, 0.12)
	local x = square:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	x:SetPoint("CENTER", 0, 0)
	x:SetText("X")
	Register(button, function(_, skin)
		local hd = skin == "HD"
		square:SetShown(hd)
		hover:SetShown(hd)
		edge:SetShown(hd)
		bg:SetShown(hd)
		for _, piece in ipairs(art) do piece:SetAlpha(hd and 0 or 1) end
	end)
	return button
end

-- A window (or, inset, a box inside one) made with BackdropTemplate, in
-- both looks: SD the backdrop it has (set it, and its colours, first), HD
-- flat, dark with a thin edge. Checks the look as it opens.
function ns.SkinWindow(frame, inset)
	local info = frame.backdropInfo
	local bgColor = info and { frame:GetBackdropColor() }
	local borderColor = info and { frame:GetBackdropBorderColor() }
	local edge, bg
	if inset then
		edge, bg = Flat(frame, 0, 0, 0, 0.8, 0.5)
	else
		edge, bg = Flat(frame, 0.04, 0.04, 0.05, 0.95, 0.6)
	end
	Register(frame, function(self, skin)
		local hd = skin == "HD" or not info
		edge:SetShown(hd)
		bg:SetShown(hd)
		if not (info and self.SetBackdrop) then return end
		if hd then
			self:SetBackdrop(nil)
		elseif not self.backdropInfo then
			self:SetBackdrop(info)
			if bgColor[1] then self:SetBackdropColor(unpack(bgColor)) end
			if borderColor[1] then self:SetBackdropBorderColor(unpack(borderColor)) end
		end
	end)
	if not inset then frame:HookScript("OnShow", function() ns.ApplyMenuSkin() end) end
	return frame
end

-- A UICheckButtonTemplate checkbox in both looks. HD: a small flat square
-- in the middle of the game's room for it, a gold square in it while ticked,
-- dimmed while greyed. Its label stays as it is. round: a radio button's,
-- a circle with a gold dot.
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local function Paint(texture, round, r, g, b, a)
	if round then
		texture:SetTexture(ROUND)
		texture:SetVertexColor(r, g, b, a)
	else
		texture:SetColorTexture(r, g, b, a)
	end
end
function ns.SkinCheck(check, round)
	local art = TexturesOf(check)
	local box = CreateFrame("Frame", nil, check)
	box:SetSize(14, 14)
	box:SetPoint("CENTER")
	box:SetFrameLevel(check:GetFrameLevel())
	local edge, bg = Flat(box, 0.06, 0.06, 0.08, 0.9, 0.6)
	if round then
		Paint(edge, true, 0.5, 0.5, 0.5, 0.6)
		Paint(bg, true, 0.06, 0.06, 0.08, 0.9)
	end
	local tick = box:CreateTexture(nil, "ARTWORK")
	tick:SetSize(8, 8)
	tick:SetPoint("CENTER")
	Paint(tick, round, ACCENT[1], ACCENT[2], ACCENT[3], 1)
	local hover = check:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(box)
	Paint(hover, round, 1, 1, 1, 0.12)
	local hd = false
	local function Show()
		tick:SetShown(hd and check:GetChecked() and true or false)
		box:SetAlpha(Enabled(check) and 1 or 0.45)
	end
	hooksecurefunc(check, "SetChecked", Show)
	-- (PostClick, not OnClick: the checkbox makers set OnClick after this,
	-- which would take a hook on it away, leaving the tick as it was.)
	check:HookScript("PostClick", Show)
	OnEnabledChange(check, Show)
	Register(check, function(_, skin)
		hd = skin == "HD"
		box:SetShown(hd)
		hover:SetShown(hd)
		ShowArt(art, not hd)
		Show()
	end)
	return check
end

-- A slider (OptionsSliderTemplate, or the plain one where there's none) in
-- both looks. HD: a thin flat track, gold up to the thumb, and a light
-- flat thumb; dimmed while greyed. The thumb's still the game's, unseen, so
-- dragging is as it was.
function ns.SkinSlider(slider)
	local thumb = slider:GetThumbTexture()
	local art = TexturesOf(slider)
	for _, child in ipairs({ slider:GetChildren() }) do
		for _, piece in ipairs(TexturesOf(child)) do art[#art + 1] = piece end
	end
	local track = CreateFrame("Frame", nil, slider)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetFrameLevel(slider:GetFrameLevel())
	Flat(track, 0.06, 0.06, 0.08, 0.9, 0.6)
	local fill, knob
	if thumb then
		fill = track:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("LEFT", track, "LEFT")
		fill:SetPoint("RIGHT", thumb, "CENTER")
		fill:SetHeight(4)
		fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.75)
		knob = slider:CreateTexture(nil, "OVERLAY")
		knob:SetSize(8, 14)
		knob:SetPoint("CENTER", thumb, "CENTER")
		knob:SetColorTexture(0.85, 0.85, 0.85, 1)
	end
	local function Dim()
		local alpha = Enabled(slider) and 1 or 0.45
		track:SetAlpha(alpha)
		if knob then knob:SetAlpha(alpha) end
	end
	OnEnabledChange(slider, Dim)
	Register(slider, function(_, skin)
		local hd = skin == "HD"
		track:SetShown(hd)
		if knob then knob:SetShown(hd) end
		ShowArt(art, not hd)
		Dim()
	end)
	return slider
end

-- A WowStyle1DropdownTemplate dropdown in both looks. HD: flat, dark, a thin
-- edge, a lighter hover; its arrow and text stay.
function ns.SkinDropdown(dropdown)
	local art = TexturesOf(dropdown, dropdown.Arrow and { [dropdown.Arrow] = true })
	local edge, bg = Flat(dropdown, 0.06, 0.06, 0.08, 0.9, 0.5)
	local hover = dropdown:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.08)
	Register(dropdown, function(_, skin)
		local hd = skin == "HD"
		edge:SetShown(hd)
		bg:SetShown(hd)
		hover:SetShown(hd)
		ShowArt(art, not hd)
	end)
	return dropdown
end

-- A new dropdown on parent in both looks, given as pcall(CreateFrame, ...)
-- gives it: ok and the dropdown (ok false where the client has no
-- DropdownButton or the template).
function ns.MenuDropdown(parent)
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then ns.SkinDropdown(dropdown) end
	return ok, dropdown
end

-- An InputBoxTemplate text box in both looks. HD: a flat dark well with a
-- thin edge where the game's art was (it starts 5 left of the box, where
-- the text begins).
function ns.SkinEditBox(box)
	local art = {}
	for _, piece in ipairs({ box.Left or false, box.Middle or false, box.Right or false }) do
		if piece then art[#art + 1] = piece end
	end
	if #art == 0 then art = TexturesOf(box) end
	local edge = box:CreateTexture(nil, "BACKGROUND", nil, -8)
	SnapEdge(box, edge, 5)
	edge:SetColorTexture(0.5, 0.5, 0.5, 0.5)
	local bg = box:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetPoint("TOPLEFT", -5, 0)
	bg:SetPoint("BOTTOMRIGHT")
	bg:SetColorTexture(0, 0, 0, 0.8)
	NoSnap(bg)
	Register(box, function(_, skin)
		local hd = skin == "HD"
		edge:SetShown(hd)
		bg:SetShown(hd)
		ShowArt(art, not hd)
	end)
	return box
end

-- A UIPanelScrollFrameTemplate scroll frame's bar in both looks. HD: a thin
-- flat track and a light flat thumb; its up and down buttons still there to
-- click, unseen. Where the bar isn't as expected, it's left as it is.
function ns.SkinScroll(scroll)
	local name = scroll:GetName()
	local bar = scroll.ScrollBar or (name and _G[name .. "ScrollBar"])
	local thumb = bar and bar.GetThumbTexture and bar:GetThumbTexture()
	if not thumb then return scroll end
	local art = TexturesOf(bar)
	for _, child in ipairs({ bar:GetChildren() }) do
		if child.GetNormalTexture then
			for _, piece in ipairs(ButtonArt(child)) do art[#art + 1] = piece end
		else
			for _, piece in ipairs(TexturesOf(child)) do art[#art + 1] = piece end
		end
	end
	local track = CreateFrame("Frame", nil, bar)
	track:SetPoint("TOP", 0, 14)
	track:SetPoint("BOTTOM", 0, -14)
	track:SetWidth(6)
	track:SetFrameLevel(bar:GetFrameLevel())
	Flat(track, 0.06, 0.06, 0.08, 0.6, 0.35)
	local knob = bar:CreateTexture(nil, "OVERLAY")
	knob:SetWidth(6)
	knob:SetPoint("TOP", thumb, "TOP", 0, -2)
	knob:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 2)
	knob:SetColorTexture(0.7, 0.7, 0.7, 0.9)
	Register(bar, function(_, skin)
		local hd = skin == "HD"
		track:SetShown(hd)
		knob:SetShown(hd)
		ShowArt(art, not hd)
	end)
	return scroll
end

-- Each of these on a control the page goes on to use: one that goes wrong
-- leaves the control in the game's look (the first error reported, once),
-- never stops the page being made.
for _, name in ipairs({ "SkinButton", "SkinClose", "SkinWindow", "SkinCheck", "SkinSlider", "SkinDropdown",
	"SkinEditBox", "SkinScroll" }) do
	local skin = ns[name]
	ns[name] = function(control, ...)
		local ok, err = pcall(skin, control, ...)
		if not ok and not reported then
			reported = true
			geterrorhandler()(err)
		end
		-- (What's asked of a skinned button, there even when it didn't take.)
		if name == "SkinButton" and control then
			control.SetSkinEdge = control.SetSkinEdge or function() end
			control.SetSkinTint = control.SetSkinTint or function() end
		end
		return control
	end
end
