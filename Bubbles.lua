-- Cinematic: chat bubbles. Where the game shows them (say and yell, party; by
-- place, as the page's grid says), and how they look (the Style hub's Chat
-- bubbles page: their back, font, outline and text size).
local _, ns = ...

-- Where the bubbles show is the game's own two settings, written as you
-- enter each place: chatBubbles (say, yell, NPC speech) and chatBubblesParty.
-- Your own values are put back when the page's switch goes off.
local CVARS = { Say = "chatBubbles", Party = "chatBubblesParty" }

-- Whether that kind of bubble is off here and now: its Show in row
-- (bubble:<kind>, the page's grid) off.
local BUBBLE_ROWS = { Say = "bubble:Say", Party = "bubble:Party" }
local function OffHere(db, kind)
	return not ns.RowOnNow(BUBBLE_ROWS[kind], db["bubbles" .. kind .. "Always"], true)
end

local function ApplyCVars(db)
	local where = ns.EffectPlace()
	for kind, cvar in pairs(CVARS) do
		if GetCVar(cvar) ~= nil then
			ns.SaveCVar(cvar)
			local want = OffHere(db, kind) and "0" or "1"
			if GetCVar(cvar) ~= want then
				ns.LogDetail("cvar", ("%s -> %s (chat bubbles, %s)"):format(cvar, want, where))
				SetCVar(cvar, want)
			end
		end
	end
end

local function RestoreCVars()
	for _, cvar in pairs(CVARS) do
		ns.RestoreCVar(cvar)
	end
end

-- The look: the Style hub's Chat bubbles page (bubblesStyle: on; off, these
-- defaults, whatever the page's set to). It works with the UI Manager's Chat
-- bubbles page off too. Speech from behind you (Speech.lua) has it as well.
local DEFAULTS = ns.DEFAULTS
DEFAULTS.bubblesStyle = true
DEFAULTS.bubblesBack = "game"   -- behind the words: "game" (the game's bubble), "dark", "custom" (bubblesBackR/G/B), "none"
DEFAULTS.bubblesBackR, DEFAULTS.bubblesBackG, DEFAULTS.bubblesBackB = 0.2, 0.12, 0.3
DEFAULTS.bubblesAlpha = 1       -- ...its opacity
DEFAULTS.bubblesEdge = "general" -- ...Dark and Custom's edge: "none", "thin", "thick", "custom" (general: General's)
DEFAULTS.bubblesTail = true     -- ...the tail pointing at who's talking
DEFAULTS.bubblesFont = "general" -- the words' font (ns.QUEST_ITEM_FONTS' names; general: the Style hub's General page)
DEFAULTS.bubblesOutline = -1    -- ...outline: 0 none, 1 thin, 2 thick, 3 thick with a drop shadow (-1: General's)
-- (and bubblesTextScale, their size: Core.lua)

local function Look()
	return ns.StyleLook("bubblesStyle")
end
ns.BubbleLook = Look

-- The back's color, if it's one of ours (Dark, Custom).
local DARK = { 0.04, 0.05, 0.06 }
function ns.BubbleBackColor(look)
	if look.bubblesBack == "custom" then
		return look.bubblesBackR, look.bubblesBackG, look.bubblesBackB
	elseif look.bubblesBack == "dark" then
		return unpack(DARK)
	end
end

-- The words' font file and flags, from the font's own (file, flags): the
-- look's file unless the client's language needs the game's (Cyrillic,
-- Korean, Chinese: boxes in the others).
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
function ns.BubbleFont(look, file, flags)
	if ROMAN then
		file = ns.StyleFontFile(look.bubblesFont) or file
	end
	local outline = tonumber(look.bubblesOutline) or 0
	return file, ns.OutlinedFlags and ns.OutlinedFlags(flags, math.min(outline, 2)) or flags
end

-- A back of our own, for Dark and Custom: a flat color, a thin line round
-- it, and a tail like the game's in the same color (skin.tail: placed by
-- whoever makes it).
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SIDES = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
	{ "TOPRIGHT", "BOTTOMRIGHT" } }
function ns.MakeBubbleSkin(parent)
	local skin = CreateFrame("Frame", nil, parent)
	skin.back = skin:CreateTexture(nil, "BACKGROUND")
	skin.back:SetAllPoints()
	skin.back:SetTexture(WHITE)
	skin.edges = {}
	for i, side in ipairs(SIDES) do
		local edge = skin:CreateTexture(nil, "BORDER")
		edge:SetTexture(WHITE)
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		if i <= 2 then edge:SetHeight(1) else edge:SetWidth(1) end
		skin.edges[i] = edge
	end
	local tail = skin:CreateTexture(nil, "BORDER")
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("ChatBubble-Tail") then
		tail:SetAtlas("ChatBubble-Tail", true)
		skin.tailInto = 5 -- (how far it overlaps the edge)
	else
		tail:SetTexture("Interface\\Tooltips\\ChatBubble-Tail")
		tail:SetSize(16, 16)
		skin.tailInto = 3
	end
	tail:SetDesaturated(true)
	skin.tail = tail
	skin.border = ns.MakeStyleEdges(skin, "BORDER")
	return skin
end

-- A skin dressed as look says (shown only for Dark and Custom).
function ns.DressBubbleSkin(skin, look)
	local r, g, b = ns.BubbleBackColor(look)
	skin:SetShown(r ~= nil)
	if not r then return end
	local alpha = tonumber(look.bubblesAlpha) or 1
	skin.back:SetVertexColor(r, g, b, alpha)
	for _, edge in ipairs(skin.edges) do edge:Hide() end -- (the old 1-pixel lines: ours now, any thickness)
	-- (Thin and Thick: a soft grey, as the bubble's always had; Custom: its own.)
	local kind, size, er, eg, eb = ns.StyleBorder(look, "bubblesEdge", { 0.65, 0.65, 0.65 })
	skin.border:SetShown(kind == "line")
	if kind == "line" then
		ns.DressStyleEdges(skin.border, size, er, eg, eb, look.bubblesEdge == "custom" and alpha or 0.7 * alpha, false)
	end
	skin.tail:SetVertexColor(r, g, b, alpha)
	skin.tail:SetShown(look.bubblesTail and true or false)
end

-- On the game's bubbles: their background, border and tail (every texture
-- in them) at the look's opacity, or faded out for a back of our own (drawn
-- behind instead) or none; their words' font, outline and size. Bubbles are
-- reused, so each is looked at again as it shows. Bubbles the game keeps
-- from addons (in instances, on retail) are left as they are.
local faded = setmetatable({}, { __mode = "k" }) -- texture -> true, while faded
local scaled = setmetatable({}, { __mode = "k" }) -- font string -> true, while scaled
-- font string -> its own font, flags and shadow, while restyled
local restyled = setmetatable({}, { __mode = "k" })
local skins = setmetatable({}, { __mode = "k" }) -- bubble -> our skin behind it
local ours = setmetatable({}, { __mode = "k" }) -- (our skins: left as they are)

local SHADOW_X, SHADOW_Y = 2, -2

local function IsTail(region, inside)
	if region == inside.Tail then return true end
	local atlas = region.GetAtlas and region:GetAtlas()
	if type(atlas) == "string" and atlas:find("Tail") then return true end
	local file = region:GetTexture()
	return type(file) == "string" and file:find("Tail") ~= nil
end

local function SetAlphaOf(region, alpha)
	if alpha ~= 1 then
		faded[region] = true
		if region:GetAlpha() ~= alpha then region:SetAlpha(alpha) end
	elseif faded[region] then
		faded[region] = nil
		region:SetAlpha(1)
	end
end

-- look nil: its own font back.
local function StyleText(region, look)
	local own = restyled[region]
	if not look or (look.bubblesFont == "game" and (tonumber(look.bubblesOutline) or 0) == 0) then
		if own then
			region:SetFont(own.file, own.height, own.flags)
			region:SetShadowColor(unpack(own.color))
			region:SetShadowOffset(own.x, own.y)
			restyled[region] = nil
		end
		return
	end
	if not own then
		local file, height, flags = region:GetFont()
		if not file then return end
		local x, y = region:GetShadowOffset()
		own = { file = file, height = height, flags = flags or "", x = x, y = y, color = { region:GetShadowColor() } }
		restyled[region] = own
	end
	local file, flags = ns.BubbleFont(look, own.file, own.flags)
	local nowFile, nowHeight, nowFlags = region:GetFont()
	-- (The game can set the font again as it reuses a bubble.)
	if nowFile ~= file or nowHeight ~= own.height or (nowFlags or "") ~= flags then
		region:SetFont(file, own.height, flags)
	end
	if look.bubblesOutline == 3 then
		region:SetShadowColor(0, 0, 0, 1)
		region:SetShadowOffset(SHADOW_X, SHADOW_Y)
	else
		region:SetShadowColor(unpack(own.color))
		region:SetShadowOffset(own.x, own.y)
	end
end

local function Style(inside, look, ...)
	local game = look and look.bubblesBack == "game"
	local alpha = game and tonumber(look.bubblesAlpha) or 1
	local scale = look and tonumber(look.bubblesTextScale) or 1
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		local kind = region:GetObjectType()
		if kind == "Texture" then
			if not look then
				SetAlphaOf(region, 1)
			elseif not game or (not look.bubblesTail and IsTail(region, inside)) then
				SetAlphaOf(region, 0)
			else
				SetAlphaOf(region, alpha)
			end
		elseif kind == "FontString" then
			StyleText(region, look)
			if region.SetTextScale and (scale ~= 1 or scaled[region]) then
				region:SetTextScale(scale)
				scaled[region] = scale ~= 1 or nil
			end
		end
	end
end

local function StyleFrame(frame, inside, look)
	Style(inside, look, frame:GetRegions())
	for i = 1, select("#", frame:GetChildren()) do
		local child = select(i, frame:GetChildren())
		if not ours[child] and not (child.IsForbidden and child:IsForbidden()) then
			StyleFrame(child, inside, look)
		end
	end
end

-- Our back behind a bubble's inside (Dark, Custom), its tail where the
-- game's is (faded out, it still says where).
local SKIN_INSET = 4
local function Skin(bubble, inside, look)
	local skin = skins[bubble]
	if not skin then
		if not (look and ns.BubbleBackColor(look)) then return end
		skin = ns.MakeBubbleSkin(bubble)
		ours[skin] = true
		skins[bubble] = skin
		skin:SetPoint("TOPLEFT", inside, "TOPLEFT", SKIN_INSET, -SKIN_INSET)
		skin:SetPoint("BOTTOMRIGHT", inside, "BOTTOMRIGHT", -SKIN_INSET, SKIN_INSET)
	end
	if not look then
		skin:Hide()
		return
	end
	skin:SetFrameLevel(math.max(0, inside:GetFrameLevel() - 1))
	ns.DressBubbleSkin(skin, look)
	local gameTail = inside.Tail
	if not gameTail then
		for i = 1, select("#", inside:GetRegions()) do
			local region = select(i, inside:GetRegions())
			if region:GetObjectType() == "Texture" and IsTail(region, inside) then gameTail = region end
		end
	end
	skin.tail:ClearAllPoints()
	if gameTail then
		skin.tail:SetAllPoints(gameTail)
	else
		skin.tail:Hide()
	end
end

local function StyleBubbles()
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
		return
	end
	local look = ns.StyleOn("bubblesStyle") and ns.StyleLook("bubblesStyle") or nil
	if not look and not next(faded) and not next(scaled) and not next(restyled) and not next(skins) then
		return
	end
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) then
			local inside = bubble:GetChildren()
			if inside and not (inside.IsForbidden and inside:IsForbidden()) then
				StyleFrame(bubble, inside, look)
				Skin(bubble, inside, look)
			end
		end
	end
end
ns.RefreshBubbleStyle = StyleBubbles -- (the Style pages, as their settings change)

-- A bubble like the game's: its nine-slice where the client has one, else
-- the older bubble textures. (Speech from behind you, the Style page's preview.)
function ns.MakeGameBubble(parent)
	local bubble
	if _G.NineSliceUtil and _G.NineSliceUtil.ApplyLayoutByName then
		bubble = CreateFrame("Frame", nil, parent, "NineSlicePanelTemplate")
		if not pcall(_G.NineSliceUtil.ApplyLayoutByName, bubble, "ChatBubble") then
			bubble:Hide()
			bubble = nil
		end
	end
	if not bubble and BackdropTemplateMixin then
		bubble = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		bubble:SetBackdrop({
			bgFile = "Interface\\Tooltips\\ChatBubble-Background",
			edgeFile = "Interface\\Tooltips\\ChatBubble-Backdrop",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 16, right = 16, top = 16, bottom = 16 },
		})
	end
	if bubble then
		bubble:SetFrameLevel(parent:GetFrameLevel() + 1)
		-- Its tail (placed by TailAt).
		local tail = bubble:CreateTexture(nil, "OVERLAY")
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("ChatBubble-Tail") then
			tail:SetAtlas("ChatBubble-Tail", true)
			bubble.tailInto = 5 -- (how far it overlaps the bubble's edge)
		else
			tail:SetTexture("Interface\\Tooltips\\ChatBubble-Tail")
			tail:SetSize(16, 16)
			bubble.tailInto = 3
		end
		bubble.tail = tail
	end
	return bubble
end

-- Whether any bubble is still styled from before (the game hides bubbles and
-- reuses them: those only come back as they show again).
local function Styled()
	return next(faded) or next(scaled) or next(restyled) or next(skins)
end

-- Kept off the top of the screen: the game pins a bubble to the screen's top
-- edge, under the letterbox bar. Its inside (the frame holding its background,
-- tail and text) is moved down until its top is below the bar, or 10% from
-- the top while the bars are off. The game places the bubble itself each
-- frame, so this is looked at each frame while it shows. Bubbles the game
-- keeps from addons (in instances, on retail) are left as they are.
local TOP_MARGIN = 0.1
local lifted = setmetatable({}, { __mode = "k" }) -- inside frame -> { points, by }

local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- The line, in screen pixels from the bottom, a bubble's top stays under.
local function TopLine()
	local height = UIParent:GetHeight()
	local bar = 0
	local letterbox = ns.letterbox
	if letterbox and ns.Flag(letterbox:IsShown()) and letterbox:GetAlpha() > 0 then
		bar = letterbox.top:GetHeight()
	end
	if bar < 1 then
		bar = height * TOP_MARGIN
	end
	return (height - bar) * UIParent:GetEffectiveScale()
end

local function Place(inside, state, by)
	state.moving = true
	inside:ClearAllPoints()
	for _, point in ipairs(state.points) do
		inside:SetPoint(point[1], point[2], point[3], point[4], point[5] - by)
	end
	state.moving = false
	state.by = by
end

-- Retail's inside hangs off its text (String), which the game places itself
-- each frame: the text is moved down instead, the inside with it. (Moving the
-- inside left the words up under the bar, the box below them.) The game's
-- own place is told from ours by it not being where we last put it.
local function LiftText(inside, text, state)
	local on = ns.db and ns.db.handleBubbles
	local point, relative, relativePoint, x, y = text:GetPoint(1)
	if not (point and Readable(x) and Readable(y)) or text:GetNumPoints() ~= 1 then
		return
	end
	local ours = state.textX == x and state.textY == y
	if not ours then
		state.baseY, state.by = y, 0 -- (the game's place this frame)
	end
	local by = 0
	if on then
		local top, scale = inside:GetTop(), inside:GetEffectiveScale()
		if not (Readable(top) and Readable(scale)) or scale <= 0 then
			return
		end
		local over = (top + state.by) - TopLine() / scale
		by = over > 0 and over or 0
	end
	if math.abs(by - state.by) > 0.5 or (by == 0 and state.by ~= 0) then
		text:ClearAllPoints()
		text:SetPoint(point, relative, relativePoint, x, state.baseY - by)
		state.by, state.textX, state.textY = by, x, state.baseY - by
	end
end

local function Lift(inside)
	local text = inside.String
	if text and text.GetPoint and select(2, inside:GetPoint(1)) == text then
		local state = lifted[inside]
		if not state then
			state = { by = 0 }
			lifted[inside] = state
		end
		LiftText(inside, text, state)
		return
	end
	local state = lifted[inside]
	if not state then
		state = { by = 0 }
		lifted[inside] = state
		-- (Something else placing it: that's where it goes from now.)
		hooksecurefunc(inside, "SetPoint", function()
			if not state.moving then
				state.points, state.by = nil, 0
			end
		end)
	end
	local on = ns.db and ns.db.handleBubbles
	if not on then
		if state.by ~= 0 and state.points then Place(inside, state, 0) end
		return
	end
	local top, scale = inside:GetTop(), inside:GetEffectiveScale()
	if not (Readable(top) and Readable(scale)) or scale <= 0 then
		return
	end
	if not state.points then
		if inside:GetNumPoints() == 0 then return end
		state.points = {}
		for i = 1, inside:GetNumPoints() do
			state.points[i] = { inside:GetPoint(i) }
		end
	end
	local over = (top + state.by) - TopLine() / scale
	local by = over > 0 and over or 0
	if math.abs(by - state.by) > 0.5 or (by == 0 and state.by ~= 0) then
		Place(inside, state, by)
	end
end

local hooked = setmetatable({}, { __mode = "k" }) -- bubble -> true
local function HookBubbles()
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
		return
	end
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		if not hooked[bubble] and not (bubble.IsForbidden and bubble:IsForbidden()) then
			local inside = bubble:GetChildren()
			if inside and not (inside.IsForbidden and inside:IsForbidden()) then
				hooked[bubble] = true
				bubble:HookScript("OnUpdate", function() Lift(inside) end)
			end
		end
	end
end

-- Whether a bubble saying exactly this text is showing on screen (so its chat
-- line needn't show the chat window). Bubbles the game keeps from addons can't
-- be read, so those count as not showing.
local function SaysText(frame, text)
	for i = 1, select("#", frame:GetRegions()) do
		local region = select(i, frame:GetRegions())
		if region:GetObjectType() == "FontString" then
			local shown = region:GetText()
			if type(shown) == "string" and not (issecretvalue and issecretvalue(shown)) and shown == text then
				return true
			end
		end
	end
	for i = 1, select("#", frame:GetChildren()) do
		local child = select(i, frame:GetChildren())
		if not (child.IsForbidden and child:IsForbidden()) and SaysText(child, text) then
			return true
		end
	end
	return false
end
ns.BubbleSays = SaysText -- (/cine debug speakers)

function ns.IsBubbleOnScreen(text)
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
		return false
	end
	local width, height = WorldFrame:GetWidth(), WorldFrame:GetHeight()
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) and ns.Flag(bubble:IsVisible())
			and SaysText(bubble, text) then
			-- (Its centre in the world frame's own units, inside the screen.)
			local x, y = bubble:GetCenter()
			local scale = bubble:GetEffectiveScale() / WorldFrame:GetEffectiveScale()
			if type(x) == "number" and not (issecretvalue and issecretvalue(x)) then
				x, y = x * scale, y * scale
				if x >= 0 and x <= width and y >= 0 and y <= height then
					return true
				end
			end
		end
	end
	return false
end

-- How many bubbles the game keeps from addons (in instances, on retail): their
-- text can't be read, but one turning up just after a line is most likely its.
function ns.UnreadableBubbles()
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
		return 0
	end
	return #C_ChatBubbles.GetAllChatBubbles(true) - #C_ChatBubbles.GetAllChatBubbles(false)
end

-- A bubble appears a frame or so after its chat message: the bubbles are
-- looked at for a short while after each one.
local BUBBLE_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY",
}
local WATCH_FOR = 0.5
local watchLeft = 0

local watcher = CreateFrame("Frame")
local function OnUpdate(self, elapsed)
	StyleBubbles()
	if ns.db and ns.db.handleBubbles then HookBubbles() end
	watchLeft = watchLeft - elapsed
	if watchLeft <= 0 then
		self:SetScript("OnUpdate", nil)
	end
end

-- And once a second while the page is on: the Calm Timer running out, a
-- camera mode starting, a rule's other words.
local ticker = CreateFrame("Frame")
local sinceCheck = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck < 1 then return end
	sinceCheck = 0
	if ns.db and ns.db.handleBubbles then ApplyCVars(ns.db) end
end)

local wasOn = false
-- The settings changing (on the page, a profile, a reset) or a new place.
function ns.ApplyBubbles()
	local db = ns.db
	if not db then return end
	if db.handleBubbles then
		ApplyCVars(db)
	elseif wasOn then
		RestoreCVars()
	end
	wasOn = db.handleBubbles and true or false
	StyleBubbles()
	if db.handleBubbles then HookBubbles() end
end

watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- (The grid's rows can follow fights, your target and your group, too.)
local SITUATION_EVENTS = { PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true, PLAYER_TARGET_CHANGED = true,
	GROUP_ROSTER_UPDATE = true }
for event in pairs(SITUATION_EVENTS) do watcher:RegisterEvent(event) end
for _, event in ipairs(BUBBLE_EVENTS) do
	pcall(watcher.RegisterEvent, watcher, event) -- (not every client has every event)
end
watcher:SetScript("OnEvent", ns.Profiled("chat bubbles event", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or SITUATION_EVENTS[event] then
		ns.ApplyBubbles()
	-- (Also while the Style page is on, or any bubble is still styled from
	-- before.) (And while the page is on at all, to keep new bubbles off the top.)
	elseif ns.db and (ns.db.handleBubbles or ns.StyleOn("bubblesStyle") or Styled()) then
		watchLeft = WATCH_FOR
		self:SetScript("OnUpdate", OnUpdate)
	end
end))

-- The Style hub's Chat bubbles page's preview: a say and a yell in bubbles
-- dressed as the look says, over the Style pages' scene.
local PREVIEW_PAD_X, PREVIEW_PAD_Y = 14, 10
local function PreviewBubble(holder)
	local frame = CreateFrame("Frame", nil, holder)
	frame.game = ns.MakeGameBubble(frame)
	frame.skin = ns.MakeBubbleSkin(frame)
	for _, back in ipairs({ frame.game or false, frame.skin }) do
		if back then
			back:SetAllPoints()
			back:SetFrameLevel(frame:GetFrameLevel() + 1)
			back.tail:ClearAllPoints()
			back.tail:SetPoint("TOP", back, "BOTTOM", -20, back.tailInto)
		end
	end
	local words = CreateFrame("Frame", nil, frame)
	words:SetAllPoints()
	words:SetFrameLevel(frame:GetFrameLevel() + 5)
	frame.text = words:CreateFontString(nil, "OVERLAY")
	frame.text:SetPoint("TOPLEFT", PREVIEW_PAD_X, -PREVIEW_PAD_Y)
	frame.text:SetJustifyH("LEFT")
	frame.text:SetWordWrap(true)
	return frame
end

local function DressPreviewBubble(frame, look, words, color, most)
	local font = _G.ChatBubbleFont or _G.GameFontHighlightLarge
	local file, height, flags = font:GetFont()
	local text = frame.text
	if file and height then
		local outline = tonumber(look.bubblesOutline) or 0
		file, flags = ns.BubbleFont(look, file, flags)
		text:SetFont(file, height * (tonumber(look.bubblesTextScale) or 1), flags)
		if outline == 3 then
			text:SetShadowColor(0, 0, 0, 1)
			text:SetShadowOffset(SHADOW_X, SHADOW_Y)
		else
			text:SetShadowColor(font:GetShadowColor())
			text:SetShadowOffset(font:GetShadowOffset())
		end
	end
	text:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
	text:SetWidth(most)
	text:SetText(words)
	local wide = text:GetStringWidth()
	if type(wide) == "number" and wide < most then text:SetWidth(math.ceil(wide) + 2) end
	frame:SetSize(text:GetWidth() + PREVIEW_PAD_X * 2, text:GetStringHeight() + PREVIEW_PAD_Y * 2)
	local own = ns.BubbleBackColor(look)
	local boxed = look.bubblesBack ~= "none"
	ns.DressBubbleSkin(frame.skin, look)
	frame.skin:SetShown(boxed and own ~= nil)
	if frame.game then
		frame.game:SetShown(boxed and not own)
		frame.game:SetAlpha(tonumber(look.bubblesAlpha) or 1)
		frame.game.tail:SetShown(look.bubblesTail and true or false)
	end
end

function ns.MakeBubblePreview(parent, width)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 190)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("TOPLEFT", 6, -5)
	caption:SetText(ns.L["Preview"])
	caption.searchSkip = true
	local say, yell = PreviewBubble(holder), PreviewBubble(holder)
	say:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 40, 80)
	yell:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -40, 40)
	function holder:Refresh()
		ns.StyleScene(self, 0.5, 0.85)
		local look = Look()
		local info = _G.ChatTypeInfo or {}
		DressPreviewBubble(say, look, ns.L["Has anyone seen my turnip? It was right here a moment ago."],
			info.SAY or { r = 1, g = 1, b = 1 }, 220)
		DressPreviewBubble(yell, look, ns.L["For the Alliance!"], info.YELL or { r = 1, g = 0.25, b = 0.25 }, 220)
	end
	holder:SetScript("OnShow", holder.Refresh)
	return holder
end
