-- Cinematic: speech from behind you. With "Hide speech you can see as a
-- bubble", a say or yell whose bubble doesn't show on screen (its speaker is
-- behind you, or out of view) shows as a line of text beside the chat window
-- (or where it's moved to) instead of bringing up a faded chat window
-- (db.chatSpeechBehind):
-- "Name says: ..." in the chat's own colour, looking like the chat bubbles
-- do: in a bubble of its own, or just the text (outlined, if ticked) with the
-- Chat bubbles page's Text only, and at its text size. Newer lines push older
-- ones up; each fades out after a while, longer for longer lines.
local _, ns = ...

local MAX_LINES = 3
local GAP = 4 -- between lines
local PAD_X, PAD_Y = 18, 12 -- round the text, in a bubble
local TAIL_SPACE = 12 -- under a bubble, for its tail
local RISE_FROM = 80 -- how far below the screen a rising line starts
local FADE_IN, FADE_OUT = 0.2, 0.6 -- seconds
local SLIDE_RATE = 10 -- how fast a line slides up into its place (higher: quicker)
local BASE_TIME, PER_LETTER, MOST_TIME = 3, 0.06, 12 -- seconds a line stays up
local SAME_LINE = 1 -- seconds: the same line again (another chat window's copy) is skipped
local BOX_W, BOX_H = 360, 48 -- the Move box
local BESIDE_CHAT_X, BESIDE_CHAT_Y = 12, -30 -- the box's corner from the chat window's top corner

-- spot: the Move box's place (db.speechBehindLeft/Bottom; nil: beside the
-- chat window); the lines line up with its left edge, middle or right edge
-- (side) as it's on the left, middle or right of the screen.
local holder, spot
local side, spotBottom = "LEFT", 0
local ANCHOR = { LEFT = "BOTTOMLEFT", CENTER = "BOTTOM", RIGHT = "BOTTOMRIGHT" }
local lines = {} -- newest first: { frame, text, born, life, y }
local spare = {}
local recent = {} -- [event .. text] = when shown

local function Font()
	return _G.ChatBubbleFont or _G.GameFontHighlightLarge
end

-- How long a line stays up, by its length (Chat Cam's subtitles too).
function ns.SpeechLife(text)
	return math.min(MOST_TIME, BASE_TIME + #text * PER_LETTER)
end

-- The look the chat bubbles have now (the Style hub's Chat bubbles page,
-- Bubbles.lua): in a bubble or not, outline thickness (1-3, nil none), size,
-- and the look itself.
local function Styled()
	return ns.BubbleLook and ns.BubbleLook() or ns.DEFAULTS
end
local function Look()
	local look = Styled()
	local outline = tonumber(look.bubblesOutline) or 0
	return look.bubblesBack ~= "none", outline > 0 and outline or nil, tonumber(look.bubblesTextScale) or 1, look
end

-- How these lines tell they're from behind you (the Style hub's Chat bubbles
-- page too): rising up from below the screen, quieter than a bubble overhead
-- (smaller, fainter), and a bubble's tail on top, pointing up, if ticked.
local function Behind()
	local db = Styled()
	return db.speechBehindRise, tonumber(db.speechBehindScale) or 1, tonumber(db.speechBehindAlpha) or 1,
		db.speechBehindTailTop
end

-- A bubble like the game's (Bubbles.lua).
local function Bubble(parent)
	return ns.MakeGameBubble(parent)
end

-- The tail under the bubble pointing down, or on top turned to point up; along
-- the bubble by speechBehindTailPos (0 its left end, 0.5 the middle, 1 its
-- right end), and mirrored (curling the other way) if speechBehindTailFlip.
-- wide: the bubble's width.
local TAIL_INSET = 14 -- from the bubble's side, with the tail at its left or right end
local function TailAt(bubble, top, wide)
	local db = Styled()
	local along = math.max(0, math.min(1, tonumber(db.speechBehindTailPos) or 0.8))
	local tail = bubble.tail
	local half = (tail:GetWidth() or 0) / 2
	local x = TAIL_INSET + half + along * math.max(0, wide - 2 * (TAIL_INSET + half))
	tail:ClearAllPoints()
	if top then
		tail:SetPoint("BOTTOM", bubble, "TOPLEFT", x, -bubble.tailInto)
	else
		tail:SetPoint("TOP", bubble, "BOTTOMLEFT", x, bubble.tailInto)
	end
	-- (Turned and mirrored by swapping its texture's four corners, as they were
	-- before it was ever turned: an atlas's can be stored turned in its file.
	-- Upside down = each corner with the one across; mirrored = left with right.)
	if not tail.corners then
		local c = { tail:GetTexCoord() } -- upper left, lower left, upper right, lower right: x, y each
		if #c < 8 then return end
		tail.corners = { { c[1], c[2] }, { c[3], c[4] }, { c[5], c[6] }, { c[7], c[8] } }
	end
	local c = tail.corners
	local ul, ll, ur, lr = c[1], c[2], c[3], c[4]
	if top then ul, ll, ur, lr = lr, ur, ll, ul end
	if db.speechBehindTailFlip then ul, ll, ur, lr = ur, lr, ul, ll end
	tail:SetTexCoord(ul[1], ul[2], ll[1], ll[2], ur[1], ur[2], lr[1], lr[2])
end

local OUTLINE_FLAGS = { "OUTLINE", "THICKOUTLINE", "THICKOUTLINE" }

-- The Style hub's Chat bubbles page's Max width (speechBehindWidth) and Align
-- (speechBehindAlign: "LEFT", "CENTER", "RIGHT", or "auto": by which side
-- of the screen the Move box is on).
local function MaxWidth()
	return math.max(200, tonumber(Styled().speechBehindWidth) or 480)
end

local function Align()
	local align = Styled().speechBehindAlign
	return ANCHOR[align] and align or side
end

local function SetLook(line, words)
	local boxed, outline, scale, look = Look()
	scale = scale * select(2, Behind())
	local text, font = line.text, Font()
	local file, size = font:GetFont()
	if file and ns.BubbleFont then file = ns.BubbleFont(look, file, "") end
	local most = MaxWidth()
	line.frame:SetWidth(most)
	text:SetWidth(most)
	text:SetText(words)
	if ns.SetPlateNameFont and file then
		-- (A font family, so every alphabet's letters show; it sets the words again.)
		ns.SetPlateNameFont(text, font, file, size, scale, outline and OUTLINE_FLAGS[outline] or "")
	end
	if outline == 3 then
		text:SetShadowColor(0, 0, 0, 1)
		text:SetShadowOffset(2, -2)
	elseif outline then
		text:SetShadowColor(0, 0, 0, 0)
		text:SetShadowOffset(0, 0)
	else
		text:SetShadowColor(font:GetShadowColor())
		text:SetShadowOffset(font:GetShadowOffset())
	end
	-- (Only as wide as its words, so a bubble fits them; past Max width, into
	-- rows of about even length, not a long one and a word left over. The
	-- slack: words don't break exactly at the even width.)
	local wide = text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()
	if type(wide) == "number" and wide < most then
		text:SetWidth(math.ceil(wide) + 2)
	elseif type(wide) == "number" then
		local rows = math.ceil(wide / most)
		text:SetWidth(math.min(most, math.ceil(wide / rows) + 40))
	end
	-- (The game's bubble, or a back of our own: Dark, Custom.)
	local own = ns.BubbleBackColor and ns.BubbleBackColor(look)
	if boxed and own and not line.skin and ns.MakeBubbleSkin then
		line.skin = ns.MakeBubbleSkin(line.frame)
		line.skin:SetFrameLevel(line.frame:GetFrameLevel() + 1)
	end
	if boxed and not own and not line.bubble then
		line.bubble = Bubble(line.frame) or false
	end
	local back = boxed and (own and line.skin or not own and line.bubble) or nil
	line.boxed = back and true or false
	local tailTop = select(4, Behind())
	-- (The tail's room is under the bubble, or over it with the tail on top.)
	-- (Lined up with the Move box's side; a bubble's edge, not its words', on it.)
	local align = Align()
	local point = ANCHOR[align]
	local inset = align == "LEFT" and PAD_X or align == "RIGHT" and -PAD_X or 0
	text:SetJustifyH(align)
	text:ClearAllPoints()
	text:SetPoint(point, line.frame, point, line.boxed and inset or 0,
		line.boxed and PAD_Y + (tailTop and 0 or TAIL_SPACE) or 0)
	line.point = point
	for _, frame in ipairs({ line.bubble or false, line.skin or false }) do
		if frame then
			TailAt(frame, tailTop, text:GetWidth() + PAD_X * 2)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", text, "TOPLEFT", -PAD_X, PAD_Y)
			frame:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", PAD_X, -PAD_Y)
		end
	end
	if line.skin then ns.DressBubbleSkin(line.skin, look) end
	if line.bubble then
		line.bubble:SetAlpha(tonumber(look.bubblesAlpha) or 1)
		line.bubble.tail:SetShown(look.bubblesTail and true or false)
	end
	if line.skin then line.skin:SetShown(back == line.skin) end
	if line.bubble then line.bubble:SetShown(back == line.bubble) end
end

local function NewLine()
	local line = table.remove(spare)
	if line then
		return line
	end
	local frame = CreateFrame("Frame", nil, holder)
	frame:SetSize(MaxWidth(), 1)
	-- (Its words on a frame of their own, over the bubble's.)
	local words = CreateFrame("Frame", nil, frame)
	words:SetAllPoints(frame)
	words:SetFrameLevel(frame:GetFrameLevel() + 5)
	local text = words:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(Font())
	text:SetJustifyV("BOTTOM")
	text:SetWordWrap(true)
	return { frame = frame, text = text }
end

local function Drop(i)
	local line = table.remove(lines, i)
	line.frame:Hide()
	spare[#spare + 1] = line
end

-- A line whose speaker comes into view (the camera swings round to them) has
-- its own bubble on screen now: it fades out, so the words don't show twice.
-- So does one the talking head (the portrait box) is saying.
local BUBBLE_CHECK = 0.2 -- seconds between looks at the bubbles
local sinceBubbleCheck = 0

local function Plain(value)
	return type(value) == "string" and not (issecretvalue and issecretvalue(value))
end

local function Trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function TalkingHeadSays(text)
	local frame = _G.TalkingHeadFrame
	if not (frame and ns.Flag(frame:IsVisible())) then
		return false
	end
	local said
	if C_TalkingHead and C_TalkingHead.GetCurrentLineInfo then
		local ok, _, _, _, _, _, _, _, headText = pcall(C_TalkingHead.GetCurrentLineInfo)
		said = ok and headText
	end
	if not Plain(said) then
		local shown = frame.TextFrame and frame.TextFrame.Text
		said = shown and shown:GetText()
	end
	return Plain(said) and Plain(text) and Trim(said) == Trim(text)
end

local function OnUpdate(_, elapsed)
	local now = GetTime()
	local y = 0
	sinceBubbleCheck = sinceBubbleCheck + elapsed
	local lookForBubbles = sinceBubbleCheck >= BUBBLE_CHECK and ns.IsBubbleOnScreen
	if lookForBubbles then
		sinceBubbleCheck = 0
	end
	for i = #lines, 1, -1 do
		local line = lines[i]
		if lookForBubbles and not line.fading and line.said
				and (ns.IsBubbleOnScreen(line.said) or TalkingHeadSays(line.said)) then
			line.bubbled = true
		end
		if now >= line.born + line.life or i > MAX_LINES or line.bubbled then
			-- (Pushed out or done: fades out where it is.)
			line.fading = line.fading or now
			local alpha = 1 - (now - line.fading) / FADE_OUT
			if alpha <= 0 then
				Drop(i)
			else
				line.frame:SetAlpha(math.min(alpha * line.most, line.frame:GetAlpha()))
			end
		end
	end
	for _, line in ipairs(lines) do
		if not line.fading then
			line.frame:SetAlpha(math.min(1, (now - line.born) / FADE_IN) * line.most)
		end
		-- (Slides up into its place as newer lines come in under it: quick at
		-- first, settling into place.)
		line.y = math.abs(y - line.y) < 0.5 and y or line.y + (y - line.y) * math.min(1, elapsed * SLIDE_RATE)
		line.frame:ClearAllPoints()
		line.frame:SetPoint(line.point, spot, line.point, 0, line.y)
		y = y + line.text:GetStringHeight() + (line.boxed and PAD_Y * 2 + TAIL_SPACE or 0) + GAP
	end
	if #lines == 0 then
		holder:SetScript("OnUpdate", nil)
	end
end
local OnHolderUpdate = ns.Profiled("Speech behind", OnUpdate)

-- A frame's edges in the holder's units (nil if they can't be read).
local function Edges(frame)
	local left, right, top = frame:GetLeft(), frame:GetRight(), frame:GetTop()
	for _, value in ipairs({ left, right, top }) do
		if type(value) ~= "number" or (issecretvalue and issecretvalue(value)) then
			return nil
		end
	end
	local scale = frame:GetEffectiveScale() / holder:GetEffectiveScale()
	return left * scale, right * scale, top * scale
end

-- Where the Move box is: where it was put, else beside the main chat window
-- (on its right; on its left if chat is on the right of the screen), else
-- low in the middle of the screen.
local function PlaceSpot()
	local width = holder:GetWidth()
	local left, bottom = tonumber(ns.db.speechBehindLeft), tonumber(ns.db.speechBehindBottom)
	if not (left and bottom) then
		local chatLeft, chatRight, chatTop
		if _G.ChatFrame1 then
			chatLeft, chatRight, chatTop = Edges(_G.ChatFrame1)
		end
		if chatLeft then
			if (chatLeft + chatRight) / 2 > width / 2 then
				left = chatLeft - BESIDE_CHAT_X - BOX_W
			else
				left = chatRight + BESIDE_CHAT_X
			end
			bottom = chatTop + BESIDE_CHAT_Y
		else
			left, bottom = (width - BOX_W) / 2, 170
		end
	end
	local middle = left + BOX_W / 2
	side = middle < width / 3 and "LEFT" or middle > width * 2 / 3 and "RIGHT" or "CENTER"
	spotBottom = bottom
	spot:ClearAllPoints()
	spot:SetSize(BOX_W, 1)
	spot:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", left, bottom)
end

local function Holder()
	if not holder then
		holder = CreateFrame("Frame", nil, UIParent)
		holder:SetAllPoints(UIParent)
		holder:SetFrameStrata("LOW")
		holder:EnableMouse(false)
		if ns.AddOverlay then
			ns.AddOverlay(holder) -- (stays up with the UI hidden, like the bubbles)
		end
		spot = CreateFrame("Frame", nil, holder)
	end
	PlaceSpot()
	return holder
end

-- The Style hub's Chat bubbles page's Move button: a box standing in for the lines, dragged to
-- where they should show (saved as it's let go). A left click sets it there
-- and closes it, a line showing there to see; right-click puts it back.
local mover
function ns.MoveSpeechBehind()
	Holder()
	if not mover then
		mover = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
		mover:SetSize(BOX_W, BOX_H)
		mover:SetFrameStrata("FULLSCREEN_DIALOG")
		mover:SetClampedToScreen(true)
		mover:SetMovable(true)
		mover:RegisterForDrag("LeftButton")
		mover:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		mover:SetBackdropColor(0, 0, 0, 0.6)
		mover:SetBackdropBorderColor(1, 0.82, 0, 1)
		local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("CENTER")
		label:SetText(ns.L["Speech from behind you shows here.\nDrag it where you want it, left-click to set, right-click to reset."])
		local close = CreateFrame("Button", nil, mover, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 4, 4)
		local function Snap()
			mover:ClearAllPoints()
			mover:SetPoint("BOTTOMLEFT", spot, "BOTTOMLEFT", 0, 0)
		end
		mover:SetScript("OnDragStart", mover.StartMoving)
		mover:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local left, bottom = self:GetLeft(), self:GetBottom()
			if type(left) == "number" and type(bottom) == "number" then
				local scale = self:GetEffectiveScale() / holder:GetEffectiveScale()
				ns.db.speechBehindLeft = math.floor(left * scale + 0.5)
				ns.db.speechBehindBottom = math.floor(bottom * scale + 0.5)
			end
			PlaceSpot()
			Snap()
			self.draggedAt = GetTime() -- (the button-up ending a drag isn't a click)
		end)
		mover:SetScript("OnClick", function(self, button)
			if self.draggedAt and GetTime() - self.draggedAt < 0.2 then
				return
			elseif button == "RightButton" then
				ns.db.speechBehindLeft, ns.db.speechBehindBottom = nil, nil -- (beside the chat window)
				PlaceSpot()
				Snap()
			else
				self:Hide()
				ns.ShowSpeechBehind("CHAT_MSG_SAY", nil, ns.L["Speech from behind you shows here."])
			end
		end)
		mover.Snap = Snap
	end
	mover.Snap()
	mover:Show()
end

-- A player's name in their class colour (db.speechBehindClassColor), as the
-- chat window shows it; NPCs' and unknown ones as they are.
local function ClassColoured(name, guid)
	if not Styled().speechBehindClassColor or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid))
			or not guid:find("^Player%-") or not _G.GetPlayerInfoByGUID then
		return name
	end
	local ok, _, class = pcall(_G.GetPlayerInfoByGUID, guid)
	local colour = ok and type(class) == "string" and not (issecretvalue and issecretvalue(class))
		and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if colour and colour.colorStr then
		return "|c" .. colour.colorStr .. name .. "|r"
	end
	return name
end

-- event: CHAT_MSG_SAY, _YELL, _MONSTER_SAY or _MONSTER_YELL; guid: the
-- speaker's, if the chat message gave it.
-- The Style hub's Chat bubbles page's Test button: a line from you, as one
-- from behind you would show.
function ns.TestSpeechBehind()
	ns.ShowSpeechBehind("CHAT_MSG_SAY", UnitName("player"), ns.L["Speech from behind you shows here."],
		UnitGUID("player"))
end

function ns.ShowSpeechBehind(event, author, text, guid)
	local now = GetTime()
	local key = event .. text
	if recent[key] and now - recent[key] < SAME_LINE then
		return
	end
	recent[key] = now
	for seen, when in pairs(recent) do
		if now - when >= SAME_LINE then recent[seen] = nil end
	end
	if TalkingHeadSays(text) or (ns.ChatCamImmersive and ns.ChatCamImmersive()) then
		return -- (or shown as a subtitle: Chat Cam's Ultra immersive)
	end

	local chatType = event:gsub("^CHAT_MSG_", "")
	local words = text
	if Styled().speechBehindName and type(author) == "string" and author ~= ""
			and not (issecretvalue and issecretvalue(author)) then
		-- (A player's in brackets, as the chat window shows it, the brackets in
		-- the chat's colour; an NPC's without, as there too.)
		local name = ClassColoured(_G.Ambiguate and _G.Ambiguate(author, "none") or author, guid)
		if not chatType:find("^MONSTER_") then
			name = "[" .. name .. "]"
		end
		local prefix = _G["CHAT_" .. chatType .. "_GET"]
		local ok, said = false, nil
		if type(prefix) == "string" then
			ok, said = pcall(string.format, prefix, name)
		end
		words = (ok and said or (name .. ": ")) .. text
	end

	Holder()
	local line = NewLine()
	local rise, _, most = Behind()
	line.born, line.life, line.fading = now, ns.SpeechLife(text), nil
	line.most, line.said, line.bubbled = most, text, nil
	-- (Rising: it starts below the screen's bottom edge and slides up into place.)
	line.y = rise and -(spotBottom + RISE_FROM) or 0
	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
	local r, g, b = 1, 1, 1
	if info then r, g, b = info.r or 1, info.g or 1, info.b or 1 end
	SetLook(line, words)
	line.text:SetTextColor(r, g, b, 1)
	line.frame:SetAlpha(0)
	line.frame:ClearAllPoints()
	line.frame:SetPoint(line.point, spot, line.point, 0, line.y)
	line.frame:Show()
	table.insert(lines, 1, line)
	holder:SetScript("OnUpdate", OnHolderUpdate)
end
