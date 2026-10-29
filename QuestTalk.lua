-- Cinematic: quest talk (Quest Vision page, questTalk). Talking to an NPC,
-- what they say shows in a speech bubble over their head (their nameplate:
-- CineMode keeps those up), and what you can say back in a list near the
-- bottom of the screen, instead of the game's gossip and quest windows:
--
--   gossip and quest greetings: their words, then quests to turn in, quests
--     to pick up (campaign, daily, weekly, legendary, low level...), quests
--     still in progress, and every other option (vendor, trainer, inn, flight
--     master, skip conversation, queue...; locked ones say why), Goodbye last;
--   a quest offered: its text a paragraph at a time, the objective and the
--     rewards on a card, Accept and Decline;
--   coming back before it's done: what's still needed, Continue greyed out;
--   turning it in: the rewards, a choice to click if there is one, Complete.
--
-- The game's own windows stay open (other addons, the quest cam and the
-- camera modes still see a conversation going on), only parked off the
-- screen and invisible. "Show the game's window" brings them back for the
-- rest of the conversation. The game's popups (a cost to confirm, a code to
-- type, a party member's escort quest, a PvP quest) stay the game's own:
-- they come up in the middle of the screen as usual.
-- With no NPC to stand over (a quest from an item, a turn-in from the quest
-- tracker), the bubble sits above the middle of the screen.
--
-- Keys (questTalkKeys): 1-9 and 0 pick from the list, Space turns the page
-- and then does the card's first button. Only out of fights (the game
-- doesn't let addons hold keys back in one), and only keys that do
-- something here: the rest go through to the game as usual.
local _, ns = ...
local L = ns.L

local TEXT_WIDTH = 360     -- the bubble's words, at most (its own units)
local PAD_X, PAD_Y = 16, 12
local PANEL_WIDTH = 440 -- the card's own width (below the bubble, as wide as it)
local NO_NPC_Y = 0.66      -- the bubble's bottom with no NPC (share of the screen's height)
local PORTRAIT = 54        -- the NPC's portrait, across (questTalkPortrait)
local OPPOSITE_X = 0.7     -- Opposite Clicked, till it's dragged: the bubble's middle this share across the screen
local OVER_PLATE = 22      -- the tail's tip over the nameplate's top (clear of the interact arrow over it)
local ROW_HEIGHT = 20
local ART_RECHECK = 0.2   -- seconds: the game's quest art read again after a screen opens
local CLOSE_WAIT = 0.15    -- seconds: going from gossip to a quest closes one before the next opens
local QUEST_ICONS = {
	available = "Interface\\GossipFrame\\AvailableQuestIcon",
	daily = "Interface\\GossipFrame\\DailyQuestIcon",
	legendary = "Interface\\GossipFrame\\AvailableLegendaryQuestIcon",
	complete = "Interface\\GossipFrame\\ActiveQuestIcon",
	dailyComplete = "Interface\\GossipFrame\\DailyActiveQuestIcon",
	incomplete = "Interface\\GossipFrame\\IncompleteQuestIcon",
}
local GOLD = { 1, 0.82, 0 }
local GREY = { 0.6, 0.6, 0.6 }
-- The card's colors: on its own dark background, and on parchment
-- (questTalkCardSame). GOLD and GREY passed in stand for title and dim.
local INK = {
	dark = { text = { 1, 1, 1 }, title = GOLD, header = { 0.7, 0.67, 0.55 }, sub = { 0.8, 0.8, 0.8 },
		dim = GREY, red = { 1, 0.3, 0.3 } },
	parchment = { text = { 0, 0, 0 }, title = { 0, 0, 0 }, header = { 0.30, 0.18, 0 },
		sub = { 0.3, 0.22, 0.12 }, dim = { 0.45, 0.4, 0.33 }, red = { 0.62, 0.1, 0.06 } },
}
local ink = INK.dark
local function Ink(color)
	if color == GOLD then
		return ink.title
	elseif color == GREY then
		return ink.dim
	end
	return color
end
-- The looks: parchment, the game's chat bubble (as the Chat bubbles page's
-- bubbles look), dark, or none (just the words, over the world).
local LOOKS = {
	parchment = { bg = { 0.93, 0.86, 0.70, 0.97 }, edge = { 0.45, 0.33, 0.16, 1 }, text = { 0, 0, 0 },
		name = { 0.40, 0.27, 0.10 }, title = { 0, 0, 0 }, font = "QuestFont", art = true },
	bubble = { text = { 1, 1, 1 }, name = { 1, 0.82, 0 }, title = { 1, 0.82, 0 }, font = "ChatBubbleFont" },
	dark = { bg = { 0.03, 0.04, 0.05, 0.88 }, edge = { 0.42, 0.35, 0.19, 1 }, text = { 1, 1, 1 },
		name = { 1, 0.82, 0 }, title = { 1, 0.82, 0 }, font = "QuestFont" },
	none = { bg = { 0, 0, 0, 0 }, edge = { 0, 0, 0, 0 }, text = { 1, 1, 1 }, name = { 1, 0.82, 0 },
		title = { 1, 0.82, 0 }, font = "QuestFont", bare = true },
}

-- Its look: the Style hub's Quest talk page (questTalkStyled: on; off, these
-- defaults, whatever the page's set to). questTalkStyle (the look's name), questTalkPortrait,
-- questTalkCardSame, questTalkLines and questTalkScale are Core's, from before
-- the page (they were on the Quest Vision page).
local DEFAULTS = ns.DEFAULTS
DEFAULTS.questTalkStyled = true
DEFAULTS.questTalkAlpha = 1      -- the panels' opacity (their fill, edge and page)
DEFAULTS.questTalkFont = "game"  -- the words' font (ns.QUEST_ITEM_FONTS' names; game: each part's own)
DEFAULTS.questTalkTextSize = 1   -- ...times their usual size
DEFAULTS.questTalkOutline = 0    -- ...outline: 0 none, 1 thin, 2 thick
local function Styled(key)
	local db = ns.db
	if db and db.questTalkStyled then
		return db[key]
	end
	return DEFAULTS[key]
end
local function CurrentLook()
	return LOOKS[Styled("questTalkStyle")] or LOOKS.parchment
end

-- The words' font as the page says, after SetFontObject (and before
-- SetText): its own file unless the client's language needs the game's
-- (Cyrillic, Korean, Chinese: boxes in the others), sized and outlined.
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
local function Font(fs)
	local font, size, outline = Styled("questTalkFont"), Styled("questTalkTextSize"), Styled("questTalkOutline")
	if font == "game" and size == 1 and outline == 0 then
		return
	end
	local file, height, flags = fs:GetFont()
	if not (file and height) then
		return
	end
	if ROMAN then
		for _, info in ipairs(ns.QUEST_ITEM_FONTS or {}) do
			if info[1] == font and info[3] then file = info[3] end
		end
	end
	fs:SetFont(file, height * size, ns.OutlinedFlags and ns.OutlinedFlags(flags, outline) or flags)
end
-- (What the words' look is now, to tell when it's changed.)
local function FontKey()
	return ("%s:%s:%s"):format(Styled("questTalkFont"), Styled("questTalkTextSize"), Styled("questTalkOutline"))
end

local function Setting(key)
	return ns.QuestVisionSetting(key)
end

-- Where the bubble goes (questTalkPlace): "head" over the NPC's nameplate,
-- "fixed" where you put it, "opposite" across the screen from where you
-- clicked them.
local PLACE_MODES = { head = true, fixed = true, opposite = true }
local function PlaceMode()
	local mode = ns.db and ns.db.questTalkPlace
	return PLACE_MODES[mode] and mode or "opposite"
end

-- A game string, or ours where the client hasn't got it (Forever lacks some).
local function G(name, english)
	local text = _G[name]
	return type(text) == "string" and text ~= "" and text or L[english]
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local results = { pcall(fn, ...) }
	if not results[1] then
		return nil
	end
	return unpack(results, 2)
end

-- Money with its coin icons (retail moved it into C_CurrencyInfo).
-- Money as the game's quest window shows it: the numbers with coin icons.
local function CoinIcons(money)
	if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Coin-Gold")) then
		return nil
	end
	local gold, silver, copper = math.floor(money / 10000), math.floor(money / 100) % 100, money % 100
	local parts = {}
	if gold > 0 then parts[#parts + 1] = gold .. "|A:Coin-Gold:19:19|a" end
	if silver > 0 then parts[#parts + 1] = silver .. "|A:Coin-Silver:19:19|a" end
	if copper > 0 or #parts == 0 then parts[#parts + 1] = copper .. "|A:Coin-Copper:19:19|a" end
	return table.concat(parts, " ")
end

local function Coins(money)
	local fn = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or _G.GetCoinTextureString
	return fn and fn(money) or tostring(money)
end

local function Plain(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

-- What's on screen now: kind ("gossip", "greeting", "detail", "progress",
-- "complete"), its pages of words and the one shown, the reward picked.
local talk = { pages = {}, page = 1 }
-- The click that opened the last conversation: whose, where across the
-- screen, and when (for talks the game reopens itself: Open); window: the
-- game's own talk window's (ns.TalkWindowSide).
local lastClick = { at = -math.huge }
local SAME_NPC_TIME = 120 -- seconds
local gameWindow = false -- "Show the game's window" for this conversation
local bubble, panel
local closeTimer

---------------------------------------------------------------------------
-- The game's windows, parked off the screen while ours show.
---------------------------------------------------------------------------
local WINDOWS = { "GossipFrame", "QuestFrame" }
local parked = {}   -- frame -> its own points before parking ({ point, relative, relativePoint, x, y }...)
local parking = false

local function SavePoints(frame)
	local points = {}
	for i = 1, Plain(frame:GetNumPoints()) or 0 do
		local point, relative, relativePoint, x, y = frame:GetPoint(i)
		if Plain(point) and Plain(x) and Plain(y) then
			points[#points + 1] = { point, relative, relativePoint, x, y }
		end
	end
	return points
end

local function Park(frame)
	if not frame or InCombatLockdown() and frame:IsProtected() then
		return
	end
	if not parked[frame] then
		parked[frame] = { points = SavePoints(frame), clamped = frame:IsClampedToScreen() }
	end
	parking = true
	frame:SetClampedToScreen(false)
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -5000, 0)
	frame:SetAlpha(0)
	parking = false
end

local function Unpark(frame)
	local saved = parked[frame]
	if not saved or InCombatLockdown() and frame:IsProtected() then
		return
	end
	parked[frame] = nil
	parking = true
	frame:ClearAllPoints()
	if #saved.points == 0 then
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	end
	for _, p in ipairs(saved.points) do
		frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
	end
	frame:SetClampedToScreen(saved.clamped and true or false)
	frame:SetAlpha(1)
	parking = false
end

-- Anyone moving a parked window (the game lining its windows up, the Quality
-- of life page's centering): that's where it goes when it comes back, and
-- it's parked again.
local function Moved(frame)
	if parking or not parked[frame] then
		return
	end
	parked[frame].points = SavePoints(frame)
	Park(frame)
end

local function Shown()
	return talk.kind ~= nil
end

local function ParkWindows(on)
	for _, name in ipairs(WINDOWS) do
		local frame = _G[name]
		if frame then
			if on then Park(frame) else Unpark(frame) end
		end
	end
end

---------------------------------------------------------------------------
-- Words into pages.
---------------------------------------------------------------------------
-- How tall words are in the bubble's font at its width (a font string of
-- our own, off the screen: the bubble itself may be on a nameplate, which
-- can't be measured).
local measurer
local fullHeights = {}
local function Measure(words)
	if not measurer then
		local holder = CreateFrame("Frame", nil, UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -2000, 0)
		holder:SetAlpha(0)
		measurer = holder:CreateFontString(nil, "OVERLAY")
		measurer:SetPoint("TOPLEFT")
		measurer:SetJustifyH("LEFT")
		measurer:SetWordWrap(true)
	end
	local look = CurrentLook()
	measurer:SetFontObject(_G[look.font] or GameFontHighlight)
	Font(measurer)
	measurer:SetWidth(TEXT_WIDTH)
	measurer:SetText(words)
	return Plain(measurer:GetStringHeight()) or 0
end

-- The bubble's one height for its words: questTalkLines lines (kept per font
-- and count).
local function FullHeight()
	local look = CurrentLook()
	local lines = math.max(1, math.floor(tonumber(Styled("questTalkLines")) or 7))
	local key = look.font .. ":" .. FontKey() .. ":" .. lines
	if not fullHeights[key] then
		fullHeights[key] = Measure(("Wordy\n"):rep(lines - 1) .. "Wordy")
	end
	return fullHeights[key]
end

-- A paragraph's sentences, and a sentence's words: for one too tall for a page.
local SENTENCE = "[^%.!%?]*[%.!%?]+[\"'%)]*%s*"
local function Sentences(piece)
	local parts = {}
	for part in piece:gmatch(SENTENCE) do
		part = part:match("^%s*(.-)%s*$")
		if part ~= "" then parts[#parts + 1] = part end
	end
	local rest = (piece:gsub(SENTENCE, "")):match("^%s*(.-)%s*$")
	if rest ~= "" then parts[#parts + 1] = rest end
	return parts
end

local function Words(piece)
	local parts = {}
	for word in piece:gmatch("%S+") do parts[#parts + 1] = word end
	return parts
end

-- Puts a piece (a paragraph, level 1; a sentence, 2; a word, 3) on the pages:
-- on the last page after sep while that still fits the bubble's height (the
-- gaps between paragraphs count: it goes by height, not letters), else on a
-- new one. One too tall for a page of its own goes in its sentences (or
-- words), the first still on the last page if it fits there.
local function AddPiece(pages, piece, sep, full, level)
	local last = pages[#pages]
	if last then
		local joined = last .. sep .. piece
		if Measure(joined) <= full + 1 then
			pages[#pages] = joined
			return
		end
	end
	if level >= 3 or Measure(piece) <= full + 1 then
		pages[#pages + 1] = piece
		return
	end
	local parts = level == 1 and Sentences(piece) or Words(piece)
	if #parts < 2 then
		AddPiece(pages, piece, sep, full, level + 1)
		return
	end
	for i, part in ipairs(parts) do
		AddPiece(pages, part, i == 1 and sep or " ", full, level + 1)
	end
end

local function Pages(text)
	local pages = {}
	text = Plain(text)
	if type(text) ~= "string" then
		return pages
	end
	text = text:gsub("\r\n", "\n")
	local full = FullHeight()
	for paragraph in (text .. "\n\n"):gmatch("(.-)\n%s*\n") do
		paragraph = paragraph:match("^%s*(.-)%s*$")
		if paragraph ~= "" then
			AddPiece(pages, paragraph, "\n\n", full, 1)
		end
	end
	return pages
end

---------------------------------------------------------------------------
-- The bubble.
---------------------------------------------------------------------------
local function NpcPlate()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) or not ns.Flag(UnitExists("npc")) then
		return nil
	end
	local plate = Call(C_NamePlate.GetNamePlateForUnit, "npc")
	if plate then
		return plate
	end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if ns.Flag(UnitExists(unit)) and Plain(UnitIsUnit(unit, "npc")) == true then
			return Call(C_NamePlate.GetNamePlateForUnit, unit)
		end
	end
end

-- The tail: the chat bubble's own for that look, a parchment point otherwise.
local function SetTail(on)
	local chat = bubble.look == LOOKS.bubble and bubble.slice ~= nil
	bubble.tail:SetShown(on and chat)
	bubble.point:SetShown(on and not chat)
end

-- Kept on the screen: the bubble can't be measured once it's anchored to a
-- nameplate (retail: "can't measure restricted regions"), and clamping
-- doesn't hold it. The game keeps nameplates a share of the screen down from
-- its top (these settings), so while the bubble's over one that share is
-- made room for it and the letterbox's top bar; yours come back after.
-- (Retail's one; older clients' two. Each a share of the screen's height,
-- or where its default is over 1, a distance in the UI's units.)
local TOP_INSETS = { "nameplateTopInset", "nameplateOtherTopInset", "nameplateLargeTopInset" }
local EDGE = 8 -- UIParent's units, between the bubble and the bar or the screen's top
local insetSet = false

local function RoomAtTop(on)
	if InCombatLockdown() then
		return -- (plate settings can't change in a fight)
	end
	local screenH = UIParent:GetHeight()
	local share, room
	if on and screenH > 0 then
		local bar = 0
		local letterbox = ns.letterbox
		if letterbox and letterbox:IsShown() and (Plain(letterbox:GetAlpha()) or 0) > 0 then
			bar = Plain(letterbox.top:GetHeight()) or 0
		end
		local scale = bubble:GetScale()
		local tall = (bubble.tall + OVER_PLATE + bubble.tailRoom + (bubble.under or 0)) * scale
		-- (Plus the space asked for: questTalkTopGap, a share of the screen.)
		room = tall + bar + EDGE + screenH * (tonumber(ns.db.questTalkTopGap) or 0)
		share = math.min(0.6, room / screenH)
	end
	for _, cvar in ipairs(TOP_INSETS) do
		if GetCVar(cvar) ~= nil then
			if share then
				ns.SaveCVar(cvar)
				local saved = tonumber(ns.db.savedCVars[cvar]) or 0
				local default = C_CVar and C_CVar.GetCVarDefault and tonumber(C_CVar.GetCVarDefault(cvar))
				local want = default and default > 1 and math.min(room, screenH * 0.6) or share
				SetCVar(cvar, tostring(math.max(want, saved)))
				ns.LogDetail("cvar", ("%s -> %s (quest talk bubble, default %s)"):format(cvar,
					tostring(GetCVar(cvar)), tostring(default)))
			elseif insetSet then
				ns.RestoreCVar(cvar)
			end
		end
	end
	insetSet = share ~= nil
end

-- While the camera moves (questTalkCamMove), over the head: anchored to the
-- NPC's plate, the bubble slides with it, and on screen it goes by whole
-- pixels, so a slow move (the quest cam's zoom and turn) shows as a stutter,
-- and turning it yourself as a lurch (the plate runs a frame or two ahead of
-- the world, and stops dead before it). "follow" leaves it so; "fade" fades
-- it and the card out till the camera's still; "dim" fades them down to
-- MOVE_DIM; "wait" puts them where Fixed would meanwhile, faded over to the
-- NPC once it's still (and back off, if it moves again).
local MOVE_MODES = { follow = true, fade = true, dim = true, wait = true }
local function MoveMode()
	local mode = ns.db and ns.db.questTalkCamMove
	return MOVE_MODES[mode] and mode or "follow"
end

-- Whether the camera's moving: the quest cam's moves (not its drift), the
-- mouse on the camera, or your facing changing faster than TURN_RATE (turn
-- keys); still only once none has for MOVE_SETTLE. Kept up to date every
-- frame (see the follower, below).
local MOVE_SETTLE = 0.2
local TURN_RATE = math.rad(20) -- radians per second
local camMove = { alpha = 1, at = 0 }
local function CameraMoving()
	return GetTime() - camMove.at < MOVE_SETTLE
end

-- Opposite Clicked: which half of the screen to keep clear ("left" or
-- "right"): the half you clicked them on; with no click, where the quest cam
-- frames them while it's turning for this talk. nil: neither.
local function NpcSide()
	local x = talk.clickX
	if x then
		return x > 0.5 and "right" or "left"
	end
	return ns.QuestCamSide and ns.QuestCamSide()
end

-- Whether Opposite Clicked has someone to be opposite (else it's as Fixed).
local function Opposite()
	return PlaceMode() == "opposite" and (talk.clickX ~= nil or NpcSide() ~= nil)
end

-- Where you clicked the NPC this conversation started with (a share of the
-- screen's width), or nil. The game opening the same NPC's talk again, after
-- a quest's accepted or turned in, with no click of yours: that first click
-- still goes, for a while.
function ns.TalkClickX()
	local x = ns.ClickedX and ns.ClickedX() or nil
	local guid = Plain(UnitGUID("npc"))
	if x then
		lastClick.guid, lastClick.x, lastClick.at = guid, x, GetTime()
	elseif guid and guid == lastClick.guid and GetTime() - lastClick.at <= SAME_NPC_TIME then
		x = lastClick.x
	end
	return x
end

-- With quest talk off, Where they go places the game's own
-- gossip and quest windows (CenterPanels.lua): "fixed" or "opposite", or nil
-- to leave them be (Over the head: a whole window over an NPC would hide
-- them; or ours are on, the game's window only shown on request).
function ns.TalkWindowPlace()
	if not ns.db or Setting("questTalk") then
		return nil
	end
	local mode = PlaceMode()
	return mode ~= "head" and mode or nil
end

-- ...and with Opposite Clicked, the half of the screen to keep clear for a
-- window opening now ("left" or "right"; nil: neither). starting: a new
-- conversation (no talk window open yet): its click is read.
function ns.TalkWindowSide(starting)
	if starting then
		lastClick.window = ns.TalkClickX()
	end
	if ns.TalkWindowPlace() ~= "opposite" then
		return nil
	end
	local x = lastClick.window
	if x then
		return x > 0.5 and "right" or "left"
	end
	return ns.QuestCamSide and ns.QuestCamSide()
end

local function Place()
	bubble:ClearAllPoints()
	local mode = PlaceMode()
	local plate = mode == "head" and NpcPlate()
	-- (follow: the card goes beside it, over their head or Opposite Clicked.)
	bubble.free, bubble.side, bubble.follow = false, nil, true
	-- (onPlate: the plate it's over. waiting: kept off it while the camera
	-- moves, questTalkCamMove "wait".)
	bubble.onPlate = nil
	-- (Or about to: a quest giver's camera waits a moment before it starts.)
	bubble.waiting = plate and MoveMode() == "wait"
		and (CameraMoving() or ns.QuestCamPending and ns.QuestCamPending()) or nil
	if bubble.waiting then
		plate = nil
	end
	-- (bubble.under: room under it for the card, below it: no tail then.)
	local under = bubble.under or 0
	if plate and pcall(bubble.SetPoint, bubble, "BOTTOM", plate, "TOP", 0, OVER_PLATE + bubble.tailRoom + under) then
		bubble.onPlate = plate
		SetTail(under == 0)
		RoomAtTop(bubble:IsShown())
		return
	end
	bubble:ClearAllPoints()
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local scale = bubble:GetScale()
	-- Not over anyone: where it was last dragged (db.questTalkBubbleSpot: its
	-- bottom middle, as shares of the screen), else above the middle of the
	-- screen (Opposite Clicked: off to the right of it). It can be dragged
	-- (bubble.free).
	local spot = ns.db.questTalkBubbleSpot
	local x, bottom = mode == "opposite" and OPPOSITE_X or 0.5, NO_NPC_Y
	if type(spot) == "table" and type(spot.x) == "number" and type(spot.bottom) == "number" then
		x, bottom = spot.x, spot.bottom
	end
	-- Opposite Clicked: the other half of the screen from the NPC (NpcSide)
	-- is the clearer one. On their half, it opens at the mirror of its spot on
	-- the other half instead; the card follows it, on its outer side. (Near
	-- the middle, it stays where you put it.)
	local opposite = Opposite()
	local side = opposite and NpcSide()
	if side and (x > 0.5) == (side == "right") then
		x = 1 - x
	end
	bubble:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x * width / scale, bottom * height / scale)
	bubble.follow = opposite
	bubble.side = opposite and (x > 0.5 and "right" or "left") or nil
	bubble.free = true
	SetTail(false)
	RoomAtTop(false)
end

-- The quest window's own page: its background's art where the client's
-- window has one (an atlas or a file), else the classic page, cropped out of
-- the frame art it's drawn in. Nil if neither can be read.
local CLASSIC_PAGE = { file = "Interface\\QuestFrame\\QuestBG", coords = { 0, 0.586, 0.02, 0.655 } }
-- A texture's art, as the game set it: { atlas } or { file, coords }; nil
-- if it has none (or it can't be read).
local function ReadArt(texture)
	if not texture then
		return nil
	end
	if texture.GetAtlas then
		local atlas = Plain(texture:GetAtlas())
		if type(atlas) == "string" and atlas ~= "" then
			return { atlas = atlas }
		end
	end
	if texture.GetTexture then
		local file = Plain(texture:GetTexture())
		if file then
			-- (Its shape too, for fitting it without stretching: SetArtFitted.)
			local w, h = Plain(texture:GetWidth()), Plain(texture:GetHeight())
			return { file = file, coords = { texture:GetTexCoord() },
				aspect = w and h and h > 0 and w / h or nil }
		end
	end
end

-- The quest window's panel up now (its text, progress, rewards or greeting),
-- else its text's, which is always there.
local QUEST_PANELS = { "QuestFrameRewardPanel", "QuestFrameProgressPanel", "QuestFrameDetailPanel",
	"QuestFrameGreetingPanel" }
local function QuestPanel()
	for _, name in ipairs(QUEST_PANELS) do
		local panel = _G[name]
		-- (Visible, not just shown: the panels stay "shown" inside the window
		-- once it's closed, with the last quest's art.)
		if panel and ns.Flag(panel:IsVisible()) then
			return panel
		end
	end
	return _G.QuestFrameDetailPanel
end

local function PageArt()
	local panel = QuestPanel()
	return ReadArt(panel and panel.Bg) or CLASSIC_PAGE
end

-- The emblem the panel up now has over its page (a campaign's sky, say), or
-- nil: none on this quest.
local function SealArt()
	local panel = QuestPanel()
	local seal = panel and panel.SealMaterialBG
	return seal and ns.Flag(seal:IsVisible()) and ReadArt(seal) or nil
end

local SetArt -- (below)

-- An art's file, its region (left, right, top, bottom) and its shape (width
-- over height): an atlas's from the game, a file's as read.
local SEAL_ASPECT = 299 / 407 -- the quest window's page, for a file whose shape isn't known
local function ArtRegion(art)
	if art.atlas then
		local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(art.atlas)
		if not info or not (info.width and info.height and info.height > 0) then
			return nil
		end
		return info.file or info.filename, info.leftTexCoord, info.rightTexCoord, info.topTexCoord,
			info.bottomTexCoord, info.width / info.height
	end
	local c = art.coords
	if #c == 8 then
		return art.file, c[1], c[5], c[2], c[4], art.aspect or SEAL_ASPECT
	end
	return art.file, c[1], c[2], c[3], c[4], art.aspect or SEAL_ASPECT
end

-- Art on a texture w by h without stretching it: as much as fits that shape
-- (the rest cropped off). part: "top" or "bottom", that half of the art only
-- (the bubble and the card share the game's page between them, as one page),
-- lined up on its outer edge; nil, the whole art, from its middle.
local function SetArtFitted(texture, art, w, h, part)
	local file, l, r, t, b, aspect = ArtRegion(art)
	if not file or not (w > 0 and h > 0) then
		SetArt(texture, art)
		return
	end
	texture:SetTexture(file)
	if part then
		local mid = (t + b) / 2
		if part == "top" then b = mid else t = mid end
		aspect = aspect * 2
	end
	local shape = w / h
	if shape > aspect then
		local keep = (b - t) * aspect / shape
		if part == "top" then
			b = t + keep
		elseif part == "bottom" then
			t = b - keep
		else
			local mid = (t + b) / 2
			t, b = mid - keep / 2, mid + keep / 2
		end
	else
		local mid, half = (l + r) / 2, (r - l) * shape / aspect / 2
		l, r = mid - half, mid + half
	end
	texture:SetTexCoord(l, r, t, b)
end

function SetArt(texture, art)
	if art.atlas then
		texture:SetAtlas(art.atlas)
	else
		texture:SetTexture(art.file)
		texture:SetTexCoord(unpack(art.coords))
	end
end

-- Dresses a frame (the bubble; the card with questTalkCardSame) in a look:
-- the game's chat bubble (frame.slice, where the client has it), or a flat
-- fill and edge, with the quest window's page over it for parchment
-- (frame.page); look nil: the card's own dark one. Returns the page art used.
local CARD = { bg = { 0.03, 0.04, 0.03, 0.88 }, edge = { 0.42, 0.35, 0.19, 1 } }
local function Dress(frame, look)
	local chat = look == LOOKS.bubble and frame.slice ~= nil
	local alpha = Styled("questTalkAlpha") -- (the page's opacity)
	if frame.slice then
		frame.slice:SetShown(chat)
		frame.slice:SetAlpha(alpha)
	end
	if chat or look and look.bare then
		frame:SetBackdrop(nil)
	else
		-- (A flat fill for a look: the tooltip's own background darkens the
		-- color, and the bubble's point under it wouldn't match.)
		frame:SetBackdrop({
			bgFile = look and "Interface\\Buttons\\WHITE8X8" or "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		local own = look or CARD
		local bg, edge = own.bg or { 0, 0, 0, 0.85 }, own.edge or { 0.6, 0.6, 0.6, 1 }
		frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] * alpha)
		frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] * alpha)
	end
	local art = not chat and look and look.art and PageArt()
	if art then SetArt(frame.page, art) end
	frame.page:SetShown(art and true or false)
	frame.page:SetAlpha(alpha)
	frame.seal:SetAlpha(alpha)
	return art
end

-- What a frame's dressing goes by (its look, the page's opacity and font),
-- to dress it again only once one changes.
local function DressKey(look)
	return tostring(look) .. ":" .. Styled("questTalkAlpha") .. ":" .. FontKey()
end

-- What Dress needs on a frame: its chat bubble nine-slice and page texture.
local function Dressable(frame)
	if not frame.SetBackdrop then
		frame.SetBackdrop = function() end
		frame.SetBackdropColor = function() end
		frame.SetBackdropBorderColor = function() end
	end
	if _G.NineSliceUtil and _G.NineSliceUtil.ApplyLayoutByName then
		local slice = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
		if pcall(_G.NineSliceUtil.ApplyLayoutByName, slice, "ChatBubble") then
			slice:SetAllPoints()
			slice:SetFrameLevel(frame:GetFrameLevel())
			frame.slice = slice
		end
		slice:Hide()
	end
	local page = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	page:SetPoint("TOPLEFT", 3, -3)
	page:SetPoint("BOTTOMRIGHT", -3, 3)
	page:Hide()
	frame.page = page
	local seal = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
	seal:SetAllPoints(page)
	seal:Hide()
	frame.seal = seal
end

local function ApplyLook()
	local look = CurrentLook()
	if bubble.look == look and bubble.lookKey == DressKey(look) then
		return look
	end
	bubble.look, bubble.lookKey = look, DressKey(look)
	local art = Dress(bubble, look)
	if not (look == LOOKS.bubble and bubble.slice) then
		local bg, edge = look.bg or { 0, 0, 0, 0.85 }, look.edge or { 0.6, 0.6, 0.6, 1 }
		local alpha = Styled("questTalkAlpha")
		bubble.pointFill:SetColorTexture(bg[1], bg[2], bg[3], (look.bare and 0 or 1) * alpha)
		bubble.pointEdge:SetColorTexture(edge[1], edge[2], edge[3], edge[4] * alpha)
		-- (The point: it's turned, so any part of the page will do.)
		if art then SetArt(bubble.pointFill, art) end
	end
	local font = _G[look.font] or GameFontHighlight
	bubble.text:SetFontObject(font)
	-- (Each from its own font again, then the page's size and outline on it;
	-- the name's put back after, so its letters take the font.)
	bubble.name:SetFontObject("GameFontNormalSmall")
	bubble.title:SetFontObject("QuestTitleFont")
	bubble.count:SetFontObject("GameFontNormalSmall")
	for _, fs in ipairs({ bubble.text, bubble.name, bubble.title, bubble.count }) do Font(fs) end
	bubble.name:SetText(bubble.name:GetText() or "")
	bubble.text:SetTextColor(unpack(look.text))
	bubble.name:SetTextColor(unpack(look.name))
	bubble.title:SetTextColor(unpack(look.title))
	bubble.count:SetTextColor(look.name[1], look.name[2], look.name[3], 0.8)
	return look
end

-- One size always: as wide as the words can go, as tall as a full page
-- (FullHeight), whatever's on the page.
local function ShowPage()
	ApplyLook()
	local words = talk.pages[talk.page] or ""
	local text = bubble.text
	text:SetWidth(TEXT_WIDTH)
	text:SetText(words)
	local many = #talk.pages > 1
	bubble.count:SetText(many and ("%d / %d"):format(talk.page, #talk.pages) or "")
	bubble.more:SetShown(many and talk.page < #talk.pages)
	local wordsHigh = math.max(Measure(words), FullHeight())
	-- (Room for the page count always, so it's one height paged or not.)
	bubble.title:SetText(talk.title or "")
	local titleHigh = talk.title and (Plain(bubble.title:GetStringHeight()) or 16) + 3 or 0
	local height = wordsHigh + (Plain(bubble.name:GetStringHeight()) or 12) + titleHigh + 4 + 14
	-- (Whole units, so its pieces line up with each other as it moves.)
	bubble:SetSize(math.floor(TEXT_WIDTH + (bubble.indent or PAD_X) + PAD_X + 0.5),
		math.floor(height + PAD_Y * 2 + 0.5))
	bubble.tall = height + PAD_Y * 2
	-- (On parchment, the quest's emblem over the page, as the game's.)
	local seal = talk.seal and bubble.page:IsShown() and talk.seal
	-- (The top half of the game's page: the card below has the bottom.)
	local artW = math.floor(TEXT_WIDTH + (bubble.indent or PAD_X) + PAD_X + 0.5) - 6
	local artH = math.floor(height + PAD_Y * 2 + 0.5) - 6
	if talk.pageArt and bubble.page:IsShown() then
		SetArtFitted(bubble.page, talk.pageArt, artW, artH, "top")
	end
	if seal then
		SetArtFitted(bubble.seal, seal, artW, artH, "top")
	end
	bubble.seal:SetShown(seal and true or false)
	bubble:SetScale(tonumber(Styled("questTalkScale")) or 1)
	-- (No words, as some gossip has: just the list.)
	bubble:SetShown(words ~= "")
	Place()
end

local function Turn(by)
	local page = math.max(1, math.min(#talk.pages, talk.page + by))
	if page ~= talk.page then
		talk.page = page
		ShowPage()
		return true
	end
end

local function CreateBubble()
	bubble = CreateFrame("Button", "CinematicQuestTalkBubble", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	bubble:SetFrameStrata("HIGH")
	bubble:SetClampedToScreen(true)
	bubble:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bubble:SetScript("OnClick", function(_, button)
		if GetTime() - (bubble.droppedAt or 0) < 0.2 then
			return -- (the end of a drag, not a click)
		end
		Turn(button == "RightButton" and -1 or 1)
	end)
	-- Dragged (only while it isn't over anyone: over a nameplate it can't be
	-- measured, and follows them anyway).
	bubble:SetMovable(true)
	bubble:RegisterForDrag("LeftButton")
	bubble:SetScript("OnDragStart", function()
		if bubble.free then
			bubble.moving = true
			bubble:StartMoving()
		end
	end)
	bubble:SetScript("OnDragStop", function()
		if not bubble.moving then
			return
		end
		bubble.moving = false
		bubble.droppedAt = GetTime()
		bubble:StopMovingOrSizing()
		if bubble.SetUserPlaced then bubble:SetUserPlaced(false) end
		local ok, x, bottom = pcall(function() return bubble:GetCenter(), bubble:GetBottom() end)
		x, bottom = ok and Plain(x), ok and Plain(bottom)
		local width, height = UIParent:GetWidth(), UIParent:GetHeight()
		if x and bottom and width > 0 and height > 0 then
			local scale = bubble:GetScale()
			ns.db.questTalkBubbleSpot = { x = x * scale / width, bottom = bottom * scale / height }
		end
		Place()
	end)
	Dressable(bubble)
	local tail = bubble:CreateTexture(nil, "OVERLAY")
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("ChatBubble-Tail") then
		tail:SetAtlas("ChatBubble-Tail", true)
		tail:SetPoint("TOP", bubble, "BOTTOM", 0, 5)
	else
		tail:SetTexture("Interface\\Tooltips\\ChatBubble-Tail")
		tail:SetSize(16, 16)
		tail:SetPoint("TOP", bubble, "BOTTOM", 0, 3)
	end
	bubble.tail = tail
	bubble.tailRoom = 12
	-- Their portrait (questTalkPortrait), round, in a ring of the bubble's
	-- edge color, over its top left corner.
	local portrait = CreateFrame("Frame", nil, bubble)
	portrait:SetSize(PORTRAIT, PORTRAIT)
	portrait:SetPoint("CENTER", bubble, "TOPLEFT", 4, -4)
	portrait:SetFrameLevel(bubble:GetFrameLevel() + 6)
	local mask = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
	local ring = portrait:CreateTexture(nil, "BACKGROUND")
	ring:SetAllPoints()
	ring:SetTexture(mask)
	local face = portrait:CreateTexture(nil, "ARTWORK")
	face:SetPoint("TOPLEFT", 3, -3)
	face:SetPoint("BOTTOMRIGHT", -3, 3)
	if face.AddMaskTexture then
		local faceMask = portrait:CreateMaskTexture()
		faceMask:SetAllPoints(face)
		faceMask:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		face:AddMaskTexture(faceMask)
	end
	portrait.ring, portrait.face = ring, face
	portrait:Hide()
	bubble.portrait = portrait
	-- The parchment point: two turned squares (an edge, the fill a little
	-- smaller inside it), only their lower half shown, over the bubble's edge.
	local point = CreateFrame("Frame", nil, bubble)
	point:SetPoint("TOPLEFT", bubble, "BOTTOMLEFT", 0, 4)
	point:SetPoint("BOTTOMRIGHT", bubble, "BOTTOMRIGHT", 0, -14)
	point:SetFrameLevel(bubble:GetFrameLevel() + 2)
	if point.SetClipsChildren then point:SetClipsChildren(true) end
	local pointEdge = point:CreateTexture(nil, "ARTWORK", nil, 1)
	pointEdge:SetSize(20, 20)
	pointEdge:SetPoint("CENTER", point, "TOP", 0, -4)
	local pointFill = point:CreateTexture(nil, "ARTWORK", nil, 2)
	pointFill:SetSize(16, 16)
	pointFill:SetPoint("CENTER", point, "TOP", 0, -2)
	for _, texture in ipairs({ pointEdge, pointFill }) do
		if texture.SetRotation then texture:SetRotation(math.pi / 4) end
	end
	bubble.point, bubble.pointEdge, bubble.pointFill = point, pointEdge, pointFill
	local words = CreateFrame("Frame", nil, bubble)
	words:SetAllPoints()
	words:SetFrameLevel(bubble:GetFrameLevel() + 3)
	local name = words:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	name:SetPoint("TOPLEFT", PAD_X, -PAD_Y)
	name:SetJustifyH("LEFT")
	bubble.name = name
	-- The quest's name, under theirs, in the quest window's title font (a
	-- quest's text, its progress or its turn-in; empty on the talk list).
	local title = words:CreateFontString(nil, "OVERLAY", "QuestTitleFont")
	title:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	title:SetJustifyH("LEFT")
	title:SetWidth(TEXT_WIDTH)
	bubble.title = title
	local text = words:CreateFontString(nil, "OVERLAY", "QuestFont")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetWordWrap(true)
	bubble.text = text
	local count = words:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	count:SetPoint("BOTTOM", 0, PAD_Y - 4)
	bubble.count = count
	local more = words:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	more:SetPoint("BOTTOMRIGHT", -PAD_X + 4, PAD_Y - 4)
	more:SetText(">>")
	bubble.more = more
	bubble:Hide()
end

---------------------------------------------------------------------------
-- The list and the quest card (the panel).
---------------------------------------------------------------------------
local rows, rowCount = {}, 0       -- menu rows (buttons), reused
local icons, iconCount = {}, 0     -- reward/required item buttons, reused
local texts, textCount = {}, 0     -- lines of text, reused
local buttons = {}                 -- the card's buttons (two)
local keyed = {}                   -- [number key] = function, for the rows shown
local cursor                       -- how far down the panel the next thing goes
local panelWidth = PANEL_WIDTH     -- the card's width now
local Draggable                    -- (below)

-- On parchment, text as the game's quest and gossip windows have it: dark
-- ink with no shadow (a shadow under black text smudges it). After
-- SetFontObject, which brings the font's own shadow back.
local function Shade(fs)
	if ink == INK.parchment then
		fs:SetShadowOffset(0, 0)
	end
end

local function ResetPanel()
	for i = 1, rowCount do rows[i]:Hide() end
	for i = 1, iconCount do icons[i]:Hide() end
	for i = 1, textCount do texts[i]:Hide() end
	for _, button in ipairs(buttons) do button:Hide() end
	rowCount, iconCount, textCount = 0, 0, 0
	wipe(keyed)
	cursor = 12
end

local function AddText(words, font, color, gap)
	textCount = textCount + 1
	local fs = texts[textCount]
	if not fs then
		fs = panel:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		texts[textCount] = fs
	end
	fs:SetFontObject(font or "GameFontHighlight")
	Font(fs)
	Shade(fs)
	fs:SetWidth(panelWidth - 28)
	fs:SetText(words)
	fs:SetTextColor(unpack(Ink(color) or ink.text))
	cursor = cursor + (gap or 4)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", 14, -cursor)
	fs:Show()
	cursor = cursor + (Plain(fs:GetStringHeight()) or 12)
	return fs
end

-- Words and a value after them, as the game's "Experience:  15,900": the
-- words in the quest font, the value in its number font, white, 15 after.
local function AddPair(words, value, color, gap)
	local label = AddText(words, "QuestFont", color, gap)
	local wide = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
	label:SetWidth((Plain(wide) or 100) + 2)
	textCount = textCount + 1
	local fs = texts[textCount]
	if not fs then
		fs = panel:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("LEFT")
		texts[textCount] = fs
	end
	fs:SetFontObject("NumberFontNormalLarge")
	Font(fs)
	fs:SetWidth(0)
	fs:SetText(value)
	fs:SetTextColor(1, 1, 1)
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", label, "RIGHT", 15, 0)
	fs:Show()
	return label
end

local function RowTooltip(row)
	if row.tip then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(row.tip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end
end

-- A row of the list: icon, words, a tag on the right; click (or its number
-- key) does onClick. dim: greyed (low level, in progress); locked: can't be
-- picked at all.
local function AddRow(entry)
	rowCount = rowCount + 1
	local row = rows[rowCount]
	if not row then
		row = CreateFrame("Button", nil, panel)
		row:SetHeight(ROW_HEIGHT)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.key = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.key:SetPoint("LEFT", 4, 0)
		row.key:SetWidth(18)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", 24, 0)
		row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.tag:SetPoint("RIGHT", -6, 0)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.text:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self)
			if self.onClick then self.onClick() end
		end)
		row:SetScript("OnEnter", RowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		Draggable(row)
		rows[rowCount] = row
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 6, -cursor)
	row:SetPoint("RIGHT", panel, "RIGHT", -6, 0)
	-- (taller for bigger words: the Style hub's Quest talk page)
	local rowHeight = ROW_HEIGHT * math.max(1, Styled("questTalkTextSize"))
	row:SetHeight(rowHeight)
	cursor = cursor + rowHeight
	local key
	if entry.onClick and not entry.locked and #keyed < 10 then
		key = #keyed + 1
		keyed[key] = entry.onClick
	end
	-- (On parchment, the words in the game's gossip font, as its window has
	-- them; each time, as a row is reused across looks.)
	row.text:SetFontObject(ink == INK.parchment and "QuestFont" or "GameFontHighlight")
	row.key:SetFontObject(ink == INK.parchment and "QuestFont" or "GameFontDisableSmall")
	row.tag:SetFontObject("GameFontNormalSmall")
	Font(row.text)
	Font(row.key)
	Font(row.tag)
	Shade(row.text)
	Shade(row.key)
	Shade(row.tag)
	-- (Its number: the key that picks it, shown only while the keys do.)
	row.key:SetText(key and Setting("questTalkKeys") and tostring(key % 10) or "")
	row.key:SetTextColor(unpack(ink == INK.parchment and ink.dim or GREY))
	row.icon:SetTexture(entry.icon)
	row.icon:SetDesaturated(entry.dim or entry.locked or false)
	row.icon:SetShown(entry.icon ~= nil)
	row.text:SetText(entry.text or "")
	local color = Ink(entry.color) or ((entry.dim or entry.locked) and ink.dim) or ink.text
	row.text:SetTextColor(unpack(color))
	row.tag:SetText(entry.tag or "")
	row.tag:SetTextColor(unpack(Ink(entry.tagColor) or ink.dim))
	row.onClick = not entry.locked and entry.onClick or nil
	row.tip = entry.tip
	row:SetEnabled(row.onClick ~= nil)
	row:Show()
	return row
end

-- A heading: in the quest window's title font on a quest's card (Quest
-- Objectives, Rewards), small over the talk list's groups.
local function AddHeader(words)
	if talk.kind == "gossip" or talk.kind == "greeting" then
		AddText(words, "GameFontNormalSmall", ink.header, 6)
	else
		AddText(words, "QuestTitleFont", ink.title, 8)
	end
	cursor = cursor + 2
end

-- An item (or currency, spell...) with its icon, name and count; tooltip by
-- tip(GameTooltip). pick: clicking chooses it (a reward choice).
local function IconWidth() return (panelWidth - 36) / 2 end
-- The game's reward button art (QuestInfoRewardsFrameQuestInfoItem1, /cine
-- debug questart): its icon size, the name frame, the quality frame over the
-- icon and the highlight on a chosen one.
local ICON, BUTTON_HIGH, ROW_STEP = 39, 41, 44
local NAME_FRAME = "Interface\\QuestFrame\\UI-QuestItemNameFrame"
local ICON_FRAME = "Interface\\Common\\WhiteIconFrame"
local CHOSEN = "Interface\\QuestFrame\\UI-QuestItemHighlight"
local iconColumn = 0
local function AddIcon(entry)
	iconCount = iconCount + 1
	local b = icons[iconCount]
	if not b then
		-- As the game's reward buttons: a 39 icon with its quality frame over
		-- it, the name frame (128x64, for a 147 wide button) tucked 10 under
		-- the icon, the name 15 into it, and the warband mark at the name's
		-- top right.
		b = CreateFrame("Button", nil, panel)
		b.nameFrame = b:CreateTexture(nil, "BACKGROUND", nil, -1)
		b.nameFrame:SetTexture(NAME_FRAME)
		b.icon = b:CreateTexture(nil, "BACKGROUND")
		b.icon:SetSize(ICON, ICON)
		b.icon:SetPoint("TOPLEFT")
		b.nameFrame:SetPoint("LEFT", b.icon, "RIGHT", -10, 0)
		b.border = b:CreateTexture(nil, "OVERLAY", nil, 1)
		b.border:SetAllPoints(b.icon)
		b.border:SetTexture(ICON_FRAME)
		b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.count:SetPoint("BOTTOMRIGHT", b.icon, -1, 1)
		b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		b.name:SetJustifyH("LEFT")
		if b.name.SetMaxLines then b.name:SetMaxLines(2) end
		b.mark = b:CreateTexture(nil, "OVERLAY", nil, 2)
		b.mark:SetSize(16, 21)
		b.mark:SetPoint("TOPLEFT", b.name, "TOPRIGHT", 0, 3)
		b.chosen = b:CreateTexture(nil, "BACKGROUND", nil, -2)
		b.chosen:SetTexture(CHOSEN)
		b.chosen:SetBlendMode("ADD")
		b.chosen:SetPoint("TOPLEFT", b, "TOPLEFT", -8, 12)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b:SetScript("OnEnter", function(self)
			if self.tip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if pcall(self.tip, GameTooltip) then
					GameTooltip:Show()
				else
					GameTooltip:Hide()
				end
			end
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function(self)
			-- (As the game's reward buttons: ctrl-click to try it on,
			-- shift-click to link it in chat, the game's own modified clicks.)
			if self.link and IsModifiedClick() and HandleModifiedItemClick(self.link) then
				return
			end
			if self.pick then self.pick() end
		end)
		Draggable(b)
		icons[iconCount] = b
	end
	-- (Wider than the game's 147, the name frame and highlight stretch to suit.)
	local wide = IconWidth()
	b:SetSize(wide, BUTTON_HIGH)
	-- (The art's edge stretches with it, so the name's 15 in does too, or
	-- it sits on the frame's border.)
	local stretch = (wide - ICON + 10) / (147 - ICON + 10)
	b.nameFrame:SetSize(128 * stretch, 64)
	b.name:ClearAllPoints()
	b.name:SetPoint("LEFT", b.nameFrame, "LEFT", 15 * stretch, 0)
	b.name:SetWidth(wide - ICON + 10 - 15 * stretch - 16)
	b.chosen:SetSize(256 * wide / 147, 64)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", 14 + iconColumn * (wide + 8), -cursor - 4)
	if iconColumn == 1 then
		cursor = cursor + ROW_STEP
	end
	iconColumn = 1 - iconColumn
	if entry.atlas then
		b.icon:SetAtlas(entry.atlas)
	else
		b.icon:SetTexture(entry.icon or 134400) -- (the question mark)
		b.icon:SetTexCoord(0, 1, 0, 1)
	end
	-- (Its quality's color, as the game's; grey for reputation and the like.)
	local color = entry.quality and entry.quality >= 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality]
	if color then
		b.border:SetVertexColor(color.r, color.g, color.b, 1)
	else
		b.border:SetVertexColor(0.659, 0.659, 0.659, 1)
	end
	if entry.mark then
		b.mark:SetAtlas(entry.mark)
	end
	b.mark:SetShown(entry.mark ~= nil)
	local count = tonumber(entry.count)
	b.count:SetText(count and count > 1 and tostring(count) or "")
	b.name:SetText(entry.name or "")
	-- (Red: one you can't use, as on the game's window.)
	if entry.red then
		b.name:SetTextColor(1, 0.3, 0.3)
	else
		b.name:SetTextColor(1, 1, 1)
	end
	b.tip, b.pick, b.link = entry.tip, entry.pick, entry.link
	b.chosen:SetShown(entry.chosen and true or false)
	b:Show()
	return b
end

local function EndIcons()
	if iconColumn == 1 then
		cursor = cursor + ROW_STEP
		iconColumn = 0
	end
end

local function SetButtons(first, second)
	for i, spec in ipairs({ first, second }) do
		local b = buttons[i]
		if spec then
			b:SetText(spec.text)
			b:SetWidth(math.max(110, (Plain(b:GetTextWidth()) or 80) + 30))
			b.onClick = spec.onClick
			b:SetEnabled(not spec.off)
			-- (A number key too, after the rows', shown as theirs are.)
			local key
			if #keyed < 10 then
				key = #keyed + 1
				keyed[key] = function()
					if b:IsEnabled() and b.onClick then b.onClick() end
				end
			end
			b.key:SetText(key and Setting("questTalkKeys") and tostring(key % 10) or "")
			b:Show()
		end
	end
	cursor = cursor + 10
	-- (Side by side, centered, with room between for the second's key,
	-- which sits just outside its left edge.)
	buttons[1]:ClearAllPoints()
	if second then
		local gap = 16
		local left = -(buttons[1]:GetWidth() + gap + buttons[2]:GetWidth()) / 2
		buttons[1]:SetPoint("TOPLEFT", panel, "TOP", left, -cursor)
		buttons[2]:ClearAllPoints()
		buttons[2]:SetPoint("TOPLEFT", buttons[1], "TOPRIGHT", gap, 0)
	else
		buttons[1]:SetPoint("TOP", panel, "TOP", 0, -cursor)
	end
	cursor = cursor + 26
end

-- Where the list goes: while the bubble's over the NPC's head (Over the
-- NPC's head, and they have a plate), beside it, following them, its top
-- level with the bubble's (on the right; on the left where that runs off the
-- screen, when it can be measured), and not dragged; else just below the
-- middle of the screen, or where it was last dragged (db.questTalkSpot: its
-- top middle, as shares of the screen, so it still fits after a change of
-- resolution or UI scale). Off a head, the two are dragged each on its own.
local FOLLOW_GAP = 12 -- between the bubble and the list, beside it
local function ToUI()
	local scale, uiScale = Plain(panel:GetEffectiveScale()), Plain(UIParent:GetEffectiveScale())
	return scale and uiScale and uiScale > 0 and scale / uiScale or 1
end

local function PlacePanel()
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local spot = ns.db.questTalkSpot
	local toUI = ToUI()
	panel:ClearAllPoints()
	panel.following = bubble ~= nil and bubble.follow == true
	if panel.following and not bubble:IsShown() then
		-- (No words, so no bubble: the card where it would be.)
		panel:SetPoint("BOTTOM", bubble, "BOTTOM")
		return
	elseif panel.following and talk.cardBelow then
		panel:SetPoint("TOP", bubble, "BOTTOM", 0, -FOLLOW_GAP)
		return
	end
	-- questTalkCardSide: "left", "right", or "side": with Opposite Clicked the
	-- bubble's outer side (away from the middle, so the middle stays clear),
	-- else the right.
	local cardSide = ns.db.questTalkCardSide
	local left = cardSide == "left" or cardSide == "side" and bubble.side == "left"
	if panel.following and left then
		panel:SetPoint("TOPRIGHT", bubble, "TOPLEFT", -FOLLOW_GAP, 0)
		return
	elseif panel.following and (cardSide == "right" or bubble.side == "right") then
		panel:SetPoint("TOPLEFT", bubble, "TOPRIGHT", FOLLOW_GAP, 0)
		return
	elseif panel.following and pcall(panel.SetPoint, panel, "TOPLEFT", bubble, "TOPRIGHT", FOLLOW_GAP, 0) then
		local ok, right = pcall(panel.GetRight, panel)
		right = ok and Plain(right)
		if right and right * toUI > width then
			panel:ClearAllPoints()
			panel:SetPoint("TOPRIGHT", bubble, "TOPLEFT", -FOLLOW_GAP, 0)
		end
		return
	end
	panel.following = false
	if type(spot) == "table" and type(spot.x) == "number" and type(spot.top) == "number" then
		panel:SetPoint("TOP", UIParent, "BOTTOMLEFT", spot.x * width / toUI, spot.top * height / toUI)
	else
		-- (Its top edge up the screen, till it's dragged: db.questTalkListY, a share of its height.)
		panel:SetPoint("TOP", UIParent, "BOTTOM", 0, height * (tonumber(ns.db.questTalkListY) or 0.46) / toUI)
	end
end

local function Dropped()
	if not panel.moving then
		return
	end
	panel.moving = false
	panel:StopMovingOrSizing()
	if panel.SetUserPlaced then panel:SetUserPlaced(false) end -- (ours, not the game's layout cache)
	local x, top = Plain(panel:GetCenter()), Plain(panel:GetTop())
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if x and top and width > 0 and height > 0 then
		local toUI = ToUI()
		ns.db.questTalkSpot = { x = x * toUI / width, top = top * toUI / height }
	end
	PlacePanel()
end

-- Dragging the list (or anything on it) moves it, unless it's following the
-- bubble over the NPC's head.
function Draggable(frame)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function()
		if panel.following then
			return
		end
		panel.moving = true
		panel:StartMoving()
	end)
	frame:SetScript("OnDragStop", Dropped)
end

local function FinishPanel()
	cursor = cursor + 6
	panel.full:ClearAllPoints()
	panel.full:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
	local full = Setting("questTalkGameButton") and true or false
	panel.full:SetShown(full)
	local pager = panel.pager
	if talk.split then
		pager:SetText(talk.cardPage == 2 and "<< " .. L["Back"] or L["More rewards"] .. " >>")
		pager:SetWidth((Plain(pager:GetFontString():GetStringWidth()) or 80) + 4)
		pager:GetFontString():SetTextColor(unpack(ink.title))
	end
	pager:SetShown(talk.split and true or false)
	-- (Room at the bottom for the link and the pager, when either shows.)
	if full or talk.split then
		cursor = cursor + 16
	end
	-- Beside the bubble over their head, it matches it: as tall on its right
	-- (taller only for more than fits), and below it, as wide (Show).
	local high = cursor + 6
	local over = bubble.follow == true and bubble:IsShown()
	if over and not talk.cardBelow then
		high = math.max(high, bubble.tall)
	end
	panel:SetHeight(high)
	-- (A parchment card: the quest's emblem over its page, fitted to it.)
	local seal = talk.seal and panel.page:IsShown() and talk.seal
	if talk.pageArt and panel.page:IsShown() then
		SetArtFitted(panel.page, talk.pageArt, panelWidth - 6, high - 6, "bottom")
	end
	if seal then
		SetArtFitted(panel.seal, seal, panelWidth - 6, high - 6, "bottom")
	end
	panel.seal:SetShown(seal and true or false)
	panel:SetScale(tonumber(Styled("questTalkScale")) or 1)
	-- Below it: the bubble goes up by the card's height.
	local under = over and talk.cardBelow and high + FOLLOW_GAP or 0
	if under ~= (bubble.under or 0) then
		bubble.under = under
		Place()
	end
	PlacePanel()
	panel:Show()
end

---------------------------------------------------------------------------
-- Quests in a list (gossip and greeting).
---------------------------------------------------------------------------
local function QuestTags(info)
	local id = info.questID
	if id and C_CampaignInfo and Call(C_CampaignInfo.IsCampaignQuest, id) then
		return L["campaign"], { 1, 0.6, 0.2 }
	end
	if info.isImportant or id and C_QuestLog and Call(C_QuestLog.IsImportantQuest, id) then
		return L["important"], { 1, 0.6, 0.2 }
	end
	if info.isLegendary then
		return L["legendary"], { 1, 0.5, 0 }
	end
	if info.isMeta then
		return L["meta"], { 0.6, 0.8, 1 }
	end
	if info.frequency == 1 then
		return L["daily"], { 0.35, 0.66, 0.94 }
	end
	if info.frequency == 2 then
		return L["weekly"], { 0.35, 0.66, 0.94 }
	end
	if info.repeatable then
		return L["repeatable"], { 0.35, 0.66, 0.94 }
	end
	if info.isTrivial then
		return L["low level"], GREY
	end
end

local function AvailableEntry(info, onClick)
	local tag, tagColor = QuestTags(info)
	local repeating = info.frequency == 1 or info.frequency == 2 or info.repeatable
	local icon = info.isLegendary and QUEST_ICONS.legendary or repeating and QUEST_ICONS.daily
		or QUEST_ICONS.available
	return { text = info.title, icon = icon, tag = tag, tagColor = tagColor, dim = info.isTrivial,
		onClick = onClick }
end

local function ActiveEntry(info, onClick)
	local repeating = info.frequency == 1 or info.frequency == 2 or info.repeatable
	if info.isComplete then
		return { text = info.title, icon = repeating and QUEST_ICONS.dailyComplete or QUEST_ICONS.complete,
			tag = L["ready to turn in"], tagColor = GOLD, onClick = onClick }
	end
	return { text = info.title, icon = QUEST_ICONS.incomplete, tag = L["in progress"], dim = true,
		onClick = onClick }
end

-- The list: quests to turn in first, then new ones, then those still going.
local function QuestRows(available, active)
	local any = #available > 0 or #active > 0
	if any then AddHeader(L["Quests"]) end
	for _, entry in ipairs(active) do
		if entry.tagColor == GOLD then AddRow(entry) end
	end
	for _, entry in ipairs(available) do AddRow(entry) end
	for _, entry in ipairs(active) do
		if entry.tagColor ~= GOLD then AddRow(entry) end
	end
	return any
end

local function Goodbye(close)
	AddRow({ text = G("GOODBYE", "Goodbye"), color = GREY, onClick = close })
end

---------------------------------------------------------------------------
-- Rewards (a quest offered or turned in) and what's needed (progress).
---------------------------------------------------------------------------
local function QuestItem(kind, i, pick, chosen)
	local name, texture, count, quality, isUsable = GetQuestItemInfo(kind, i)
	AddIcon({ name = Plain(name), icon = Plain(texture), count = Plain(count), quality = Plain(quality),
		red = Plain(isUsable) == false, chosen = chosen, pick = pick, link = Plain(Call(GetQuestItemLink, kind, i)),
		tip = function(tip) tip:SetQuestItem(kind, i) end })
end

local function CurrencyInfo(kind, i)
	if C_QuestOffer then
		local fn = kind == "required" and C_QuestOffer.GetQuestRequiredCurrencyInfo
			or C_QuestOffer.GetQuestRewardCurrencyInfo
		local info = kind == "required" and Call(fn, i) or Call(fn, kind, i)
		if type(info) == "table" then
			return info.name, info.texture, info.totalRewardAmount or info.requiredAmount, info.quality
		end
	end
	return Call(_G.GetQuestCurrencyInfo, kind, i)
end

local function Currency(kind, i)
	local name, texture, count, quality = CurrencyInfo(kind, i)
	if not Plain(name) then
		return
	end
	AddIcon({ name = name, icon = texture, count = count, quality = quality,
		tip = function(tip) tip:SetQuestCurrency(kind, i) end })
end

-- The currencies a quest gives: retail's list for the quest, else counted
-- the older way. Each { name, icon, count, quality, tip }.
local function RewardCurrencies()
	local list = {}
	local questID = Call(GetQuestID)
	local infos = questID and C_QuestInfoSystem and Call(C_QuestInfoSystem.GetQuestRewardCurrencies, questID)
	if type(infos) == "table" and #infos > 0 then
		for _, info in ipairs(infos) do
			local count = info.totalRewardAmount or info.baseRewardAmount
			list[#list + 1] = { name = info.name, icon = info.texture, count = count, quality = info.quality,
				tip = function(tip) tip:SetCurrencyByID(info.currencyID, count) end }
		end
		return list
	end
	for i = 1, Call(_G.GetNumRewardCurrencies) or 0 do
		local name, texture, count, quality = CurrencyInfo("reward", i)
		if Plain(name) then
			list[#list + 1] = { name = name, icon = texture, count = count, quality = quality,
				tip = function(tip) tip:SetQuestCurrency("reward", i) end }
		end
	end
	return list
end

-- Reputation a quest offers (retail's renown factions), with the faction's
-- crest where there's one.
local function RewardReputations()
	local list = {}
	local reps = C_QuestOffer and Call(C_QuestOffer.GetQuestOfferMajorFactionReputationRewards)
	for _, rep in ipairs(type(reps) == "table" and reps or {}) do
		local id = rep.factionID
		local data = id and C_MajorFactions and Call(C_MajorFactions.GetMajorFactionData, id)
		data = type(data) == "table" and data or nil
		local name = data and data.name
		if not name and id and C_Reputation then
			local faction = Call(C_Reputation.GetFactionDataByID, id)
			name = type(faction) == "table" and faction.name
		end
		local atlas = data and data.textureKit and ("MajorFactions_Icons_%s512"):format(data.textureKit)
		if atlas and not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then
			atlas = nil
		end
		-- (Shared by your warband: the game's warband mark in the corner.)
		local mark = id and C_Reputation and Call(C_Reputation.IsAccountWideReputation, id) and "warbands-icon"
		if mark and not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(mark)) then
			mark = nil
		end
		if name then
			local amount = rep.rewardAmount or 0
			list[#list + 1] = { name = name, atlas = atlas, count = amount, mark = mark or nil,
				tip = function(tip)
					tip:SetText(name, 1, 1, 1)
					tip:AddLine(L["+%d reputation"]:format(amount), 0.6, 0.8, 1)
				end }
		end
	end
	return list
end

local function RewardSpells()
	local questID = Call(GetQuestID)
	local spells = questID and C_QuestInfoSystem and Call(C_QuestInfoSystem.GetQuestRewardSpells, questID)
	if type(spells) == "table" then
		for _, spellID in ipairs(spells) do
			local info = Call(C_QuestInfoSystem.GetQuestRewardSpellInfo, questID, spellID)
			if type(info) == "table" then
				AddIcon({ name = info.name, icon = info.texture,
					tip = function(tip) tip:SetSpellByID(spellID) end })
			end
		end
		return
	end
	local texture, name = Call(_G.GetRewardSpell)
	if Plain(name) then
		AddIcon({ name = name, icon = texture, tip = function(tip) tip:SetQuestRewardSpell() end })
	end
end

-- The rewards: a choice (pick: clicking one picks it, the turn-in), then the
-- rest. Nothing added for a quest with no rewards.
local function Rewards(pick)
	local choices = Call(GetNumQuestChoices) or 0
	local items = Call(GetNumQuestRewards) or 0
	local currencies = RewardCurrencies()
	local reputations = RewardReputations()
	local money = Call(GetRewardMoney) or 0
	local xp = Call(GetRewardXP) or 0
	local honor = Call(_G.GetRewardHonor) or 0
	local title = Plain(Call(_G.GetRewardTitle))
	local skillName, _, skillPoints = Call(_G.GetRewardSkillPoints)
	local artifactXP = Call(_G.GetRewardArtifactXP) or 0
	local spellCount = Call(_G.GetNumRewardSpells) or 0
	local spells = C_QuestInfoSystem and Call(C_QuestInfoSystem.GetQuestRewardSpells, Call(GetQuestID) or 0)
	if type(spells) == "table" then spellCount = #spells end
	local rest = items + #currencies + #reputations + spellCount + (money > 0 and 1 or 0) + (xp > 0 and 1 or 0)
		+ (honor > 0 and 1 or 0) + (title and 1 or 0) + (artifactXP > 0 and 1 or 0)
		+ ((Plain(skillPoints) or 0) > 0 and 1 or 0)
	-- (For /cine log: what the game said it gives, should one go missing.)
	ns.LogDetail("questtalk", ("rewards: %d choices, %d items, %d currencies, %d reputations, %d spells, money %d, xp %d")
		:format(choices, items, #currencies, #reputations, spellCount, money, xp))
	if choices + rest == 0 then
		return
	end
	-- A choice and more besides: what's "also received" can go on the card's
	-- second page, when it all doesn't fit (Show). page: which one's up.
	talk.canSplit = choices > 0 and rest > 0
	local page = talk.split and talk.cardPage or nil
	if page ~= 2 then
		AddHeader(G("REWARDS", "Rewards"))
	end
	if choices > 0 and page ~= 2 then
		if choices > 1 then
			AddText(pick and G("REWARD_CHOOSE", "Choose your reward:") or G("REWARD_CHOICES", "You will be able to choose one of these rewards:"),
				"QuestFont", ink.text)
		end
		for i = 1, choices do
			QuestItem("choice", i, pick and choices > 1 and function() pick(i) end, pick and talk.choice == i)
		end
		EndIcons()
	end
	if page == 1 or rest == 0 then
		return
	end
	-- As the game's window has them: "You will (also) receive:" with the money
	-- after it, Experience on a line of its own, then the rest's icons.
	local receive = choices > 0 and G("REWARD_ITEMS", "You will also receive:")
		or G("REWARD_ITEMS_ONLY", "You will receive:")
	local coins = money > 0 and CoinIcons(money)
	if coins then
		AddPair(receive, coins, ink.text, 6)
	else
		AddText(receive .. (money > 0 and "  " .. Coins(money) or ""), "QuestFont", ink.text, 6)
	end
	if xp > 0 then
		AddPair(G("EXPERIENCE_COLON", "Experience:"), BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp),
			ink.text, 4)
	end
	for i = 1, items do QuestItem("reward", i) end
	for _, entry in ipairs(currencies) do AddIcon(entry) end
	for _, entry in ipairs(reputations) do AddIcon(entry) end
	RewardSpells()
	EndIcons()
	local bits = {}
	if honor > 0 then bits[#bits + 1] = L["%s honor"]:format(honor) end
	if artifactXP > 0 then bits[#bits + 1] = L["%s artifact power"]:format(artifactXP) end
	if (Plain(skillPoints) or 0) > 0 and Plain(skillName) then
		bits[#bits + 1] = ("+%d %s"):format(skillPoints, skillName)
	end
	if #bits > 0 then
		AddText(table.concat(bits, "   "), "QuestFont", nil, 6)
	end
	if title then
		AddText(L["Title: %s"]:format(title), "GameFontNormal", GOLD, 4)
	end
end

---------------------------------------------------------------------------
-- Each kind of conversation.
---------------------------------------------------------------------------
local Show, TalkState -- (below)

local function SpeakerName()
	return Plain(UnitName("npc")) or Plain(UnitName("questnpc")) or ""
end

-- An option's words as the game's window has them: "(Play Movie)" and
-- "(Quest)" before them in blue where its flags say so (the game's own
-- strings). On the dark card, a lighter blue, to be read.
local function Flagged(option, flag)
	return flag and type(option.flags) == "number" and bit.band(option.flags, flag) ~= 0
end

local function OptionName(option, flags)
	local name = option.name or ""
	if Flagged(option, flags.PlayMovieLabelPrepend) then
		name = G("GOSSIP_MOVIE_OPTION_PREPEND", "|cff0000ff(Play Movie)|r %s"):format(name)
	end
	if Flagged(option, flags.QuestLabelPrepend) then
		name = G("GOSSIP_QUEST_OPTION_PREPEND", "|cff0000ff(Quest)|r %s"):format(name)
	end
	if ink == INK.dark then
		name = name:gsub("|cff0000ff", "|cff6fa8ff")
	end
	return name
end

local function GossipScreen()
	local G_ = C_GossipInfo
	talk.pages = Pages(Call(G_.GetText))
	local available, active = {}, {}
	for _, info in ipairs(Call(G_.GetAvailableQuests) or {}) do
		available[#available + 1] = AvailableEntry(info, function() G_.SelectAvailableQuest(info.questID) end)
	end
	for _, info in ipairs(Call(G_.GetActiveQuests) or {}) do
		active[#active + 1] = ActiveEntry(info, function() G_.SelectActiveQuest(info.questID) end)
	end
	local quests = QuestRows(available, active)
	local options = Call(G_.GetOptions) or {}
	table.sort(options, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
	if #options > 0 and quests then AddHeader(L["Talk"]) end
	local status = Enum and Enum.GossipOptionStatus or {}
	local flags = Enum and Enum.GossipOptionRecFlags or {}
	for i, option in ipairs(options) do
		local locked = option.status ~= nil and (option.status == status.Locked or option.status == status.Unavailable)
		local done = option.status ~= nil and option.status == status.AlreadyComplete
		AddRow({
			text = OptionName(option, flags), icon = option.overrideIconID or option.icon,
			locked = locked, dim = done,
			tag = locked and (option.failureDescription or L["locked"]) or done and L["done"] or nil,
			tagColor = locked and { 0.8, 0.4, 0.3 } or nil,
			tip = locked and option.failureDescription or nil,
			onClick = function()
				if option.gossipOptionID and G_.SelectOption then
					G_.SelectOption(option.gossipOptionID)
				elseif G_.SelectOptionByIndex then
					G_.SelectOptionByIndex(option.orderIndex or i)
				end
			end,
		})
	end
	Goodbye(function() Call(G_.CloseGossip) end)
end

local function GreetingScreen()
	talk.pages = Pages(Call(GetGreetingText))
	local available, active = {}, {}
	for i = 1, Call(GetNumAvailableQuests) or 0 do
		local isTrivial, frequency, isRepeatable, isLegendary, questID, isImportant = Call(GetAvailableQuestInfo, i)
		available[#available + 1] = AvailableEntry({ title = Call(GetAvailableTitle, i), isTrivial = isTrivial,
			frequency = frequency, repeatable = isRepeatable, isLegendary = isLegendary, questID = questID,
			isImportant = isImportant }, function() SelectAvailableQuest(i) end)
	end
	for i = 1, Call(GetNumActiveQuests) or 0 do
		local title, isComplete = Call(GetActiveTitle, i)
		active[#active + 1] = ActiveEntry({ title = title, isComplete = isComplete,
			questID = Call(_G.GetActiveQuestID, i) }, function() SelectActiveQuest(i) end)
	end
	QuestRows(available, active)
	Goodbye(CloseQuest)
end

local function Accept()
	if Call(_G.QuestFlagsPVP) and StaticPopup_Show then
		StaticPopup_Show("CONFIRM_ACCEPT_PVP_QUEST")
	elseif Call(_G.QuestGetAutoAccept) and _G.AcknowledgeAutoAcceptQuest then
		_G.AcknowledgeAutoAcceptQuest()
	else
		AcceptQuest()
	end
end

-- The quest's name: at the top of the bubble (talk.title), or on the card
-- when there are no words for a bubble.
local function QuestTitle()
	local title = Plain(Call(GetTitleText))
	-- (The game's own header has the quest's icon before its name: a
	-- campaign's, say. Taken from it when it's this quest's.)
	local header = talk.kind == "progress" and _G.QuestProgressTitleText or _G.QuestInfoTitleHeader
	local shown = header and Plain(header:GetText())
	if type(shown) == "string" and type(title) == "string" and title ~= "" and shown:find(title, 1, true) then
		title = shown
	end
	talk.title = title ~= "" and title or nil
	if #talk.pages == 0 then
		AddText(title or "", "QuestTitleFont", GOLD, 0)
	end
end

local function DetailScreen()
	talk.pages = Pages(Call(GetQuestText))
	QuestTitle()
	local objective = Plain(Call(GetObjectiveText))
	if objective and objective ~= "" then
		AddHeader(G("QUEST_OBJECTIVES", "Quest Objectives"))
		AddText(objective, "QuestFont")
	end
	Rewards()
	if Call(_G.QuestGetAutoAccept) then
		SetButtons({ text = G("OKAY", "Okay"), onClick = Accept })
	else
		SetButtons({ text = G("ACCEPT", "Accept"), onClick = Accept },
			{ text = G("DECLINE", "Decline"), onClick = DeclineQuest })
	end
end

local function ProgressScreen()
	talk.pages = Pages(Call(GetProgressText))
	QuestTitle()
	local items = Call(GetNumQuestItems) or 0
	local currencies = Call(_G.GetNumQuestCurrencies) or 0
	local money = Call(GetQuestMoneyToGet) or 0
	if items + currencies > 0 or money > 0 then
		AddHeader(G("TURN_IN_ITEMS", "Required items:"))
		for i = 1, items do QuestItem("required", i) end
		for i = 1, currencies do Currency("required", i) end
		EndIcons()
		if money > 0 then
			local short = money > (GetMoney and GetMoney() or 0)
			AddText(G("REQUIRED_MONEY", "Required Money:") .. " " .. Coins(money), "QuestFont",
				short and ink.red or nil, 6)
		end
	end
	local ready = Call(IsQuestCompletable) and true or false
	SetButtons({ text = G("CONTINUE", "Continue"), onClick = CompleteQuest, off = not ready },
		{ text = G("GOODBYE", "Goodbye"), onClick = CloseQuest })
end

local function CompleteScreen()
	talk.pages = Pages(Call(GetRewardText))
	QuestTitle()
	local choices = Call(GetNumQuestChoices) or 0
	Rewards(function(i)
		talk.choice = i
		Show(true)
	end)
	local function Complete()
		if choices > 1 and not talk.choice then
			UIErrorsFrame:AddMessage(G("ERR_QUEST_MUST_CHOOSE", "You must choose a reward."), 1, 0.1, 0.1)
			return
		end
		GetQuestReward(choices > 1 and talk.choice or (choices == 1 and 1 or 0))
	end
	SetButtons({ text = G("COMPLETE_QUEST", "Complete Quest"), onClick = Complete, off = choices > 1 and not talk.choice },
		{ text = G("CANCEL", "Cancel"), onClick = CloseQuest })
end

local SCREENS = {
	gossip = GossipScreen, greeting = GreetingScreen, detail = DetailScreen,
	progress = ProgressScreen, complete = CompleteScreen,
}

-- Following the NPC's plate as the camera drifts, the bubble and card move a
-- fraction of a pixel at a time: each texture snapping to the pixel grid on
-- its own made their pieces step out of line (a jiggle). Unsnapped, they glide
-- together. (Textures are made as the card fills, so it's done each time.)
local function Unsnap(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.SetSnapToPixelGrid then
			region:SetSnapToPixelGrid(false)
			region:SetTexelSnappingBias(0)
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		Unsnap(child)
	end
end

-- Builds what's on screen for talk.kind. keepPage: the same screen again (a
-- reward picked), staying on the page shown.
function Show(keepPage)
	if not bubble then
		CreateBubble()
	end
	local page = talk.page
	bubble.name:SetText(SpeakerName())
	local portrait = bubble.portrait
	local face = Styled("questTalkPortrait") and ns.Flag(UnitExists("npc"))
	if face then
		SetPortraitTexture(portrait.face, "npc")
		local edge = CurrentLook().edge or { 0.6, 0.6, 0.6, 1 }
		portrait.ring:SetVertexColor(edge[1], edge[2], edge[3], 1)
	end
	portrait:SetShown(face and true or false)
	-- (Its words start right of the portrait, under it in the corner.)
	bubble.indent = face and PORTRAIT / 2 + 6 or PAD_X
	bubble.name:SetPoint("TOPLEFT", bubble.indent, -PAD_Y)
	-- The card: below the bubble (questTalkCardSide) while that's over their
	-- head, as wide as it; and dressed as it (questTalkCardSame), its colors
	-- to suit.
	local mode = PlaceMode()
	talk.cardBelow = ns.db.questTalkCardSide == "below"
		and (mode == "head" and NpcPlate() ~= nil or Opposite())
	panelWidth = talk.cardBelow and TEXT_WIDTH + bubble.indent + PAD_X or PANEL_WIDTH
	panel:SetWidth(panelWidth)
	local look = CurrentLook()
	local cardLook = Styled("questTalkCardSame") and look or nil
	if panel.look ~= (cardLook or CARD) or panel.lookKey ~= DressKey(cardLook or CARD) then
		panel.look, panel.lookKey = cardLook or CARD, DressKey(cardLook or CARD)
		Dress(panel, cardLook)
	end
	ink = cardLook == LOOKS.parchment and INK.parchment or INK.dark
	-- (On parchment, the emblem the game's panel has over its page: this
	-- quest's, so it's read each time.)
	-- (The emblem the game's panel has over its page: this quest's, so it's
	-- read each time; put on the bubble and a parchment card once they're
	-- sized.)
	talk.seal = SealArt()
	-- (And the page itself: a quest's theme can change it too.)
	talk.pageArt = PageArt()
	if ns.LogDetailOn() then
		local function Name(art) return art and (art.atlas or tostring(art.file)) or "none" end
		local up = QuestPanel()
		ns.LogDetail("questtalk", ("art: %s, page %s, seal %s"):format(up and up:GetName() or "?",
			Name(talk.pageArt), Name(talk.seal)))
	end
	talk.split, talk.canSplit, talk.title = nil, nil, nil
	ResetPanel()
	iconColumn = 0
	SCREENS[talk.kind]()
	-- On the bubble's right it's as tall as the bubble: more than fits there,
	-- and the rewards' "also received" goes on a second page.
	local beside = not talk.cardBelow and (mode == "head" and NpcPlate() ~= nil or Opposite())
	local limit = beside and FullHeight() + 12 + 4 + 14 + PAD_Y * 2 + (talk.title and 22 or 0)
	if talk.canSplit and limit and cursor + 28 > limit then
		talk.split = true
		talk.cardPage = talk.cardPage or 1
		ResetPanel()
		iconColumn = 0
		SCREENS[talk.kind]()
	end
	talk.page = keepPage and math.min(page, math.max(1, #talk.pages)) or 1
	ShowPage()
	FinishPanel()
	Unsnap(bubble)
	Unsnap(panel)
	ParkWindows(true)
end

local function Hide(why)
	ns.LogDetail("questtalk", ("ours gone, the game's windows back (%s)"):format(why or "?"))
	if bubble then
		bubble:Hide()
		panel:Hide()
		RoomAtTop(false)
	end
	ParkWindows(false)
	talk.kind = nil
end

-- "Show the game's window": ours go, the game's come back, until the
-- conversation ends.
local function ShowGameWindow(why)
	gameWindow = true
	Hide(type(why) == "string" and why or "Show the game's window clicked")
end

-- The screen built again (pcall'd: a later look, not the open itself). Gone
-- wrong: logged, and the game's window, so the conversation can go on (it
-- was swallowed, and nothing was left to answer with).
local function Reshow(why)
	local ok, err = pcall(Show, true)
	if not ok then
		ns.Log("questtalk", ("%s: building the screen failed (%s): the game's window back"):format(why, tostring(err)))
		ShowGameWindow("failed " .. why)
	end
end

---------------------------------------------------------------------------
-- Keys.
---------------------------------------------------------------------------
local function OnKeyDown(self, key)
	if InCombatLockdown() then
		return
	end
	local handled = false
	if Setting("questTalkKeys") and not IsModifierKeyDown() then
		local number = tonumber(key)
		if number and keyed[number == 0 and 10 or number] then
			keyed[number == 0 and 10 or number]()
			handled = true
		elseif key == "SPACE" then
			if Turn(1) then
				handled = true
			elseif buttons[1]:IsShown() and buttons[1]:IsEnabled() then
				buttons[1].onClick()
				handled = true
			end
		end
	end
	self:SetPropagateKeyboardInput(not handled)
	-- (A key held back: let the next ones through again straight after, so
	-- Escape and the rest never wait on this.)
	if handled then
		C_Timer.After(0, function()
			if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
		end)
	end
end

local function CreatePanel()
	panel = CreateFrame("Frame", "CinematicQuestTalkPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	panel:SetFrameStrata("HIGH")
	panel:SetWidth(PANEL_WIDTH)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	Draggable(panel)
	Dressable(panel)
	for i = 1, 2 do
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetHeight(24)
		Draggable(b)
		b:SetScript("OnClick", function(self)
			if self.onClick then self.onClick() end
		end)
		b.key = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		b.key:SetPoint("RIGHT", b, "LEFT", -3, 0)
		b:Hide()
		buttons[i] = b
	end
	local full = CreateFrame("Button", nil, panel)
	full:SetSize(10, 14)
	local fullText = full:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	fullText:SetPoint("RIGHT")
	full:SetFontString(fullText)
	full:SetText(L["Show the game's window"])
	full:SetWidth((Plain(fullText:GetStringWidth()) or 120) + 4)
	full:SetScript("OnClick", ShowGameWindow)
	full:SetScript("OnEnter", function() fullText:SetFontObject("GameFontHighlightSmall") end)
	full:SetScript("OnLeave", function() fullText:SetFontObject("GameFontDisableSmall") end)
	panel.full = full
	-- The card's pages (talk.split): its rewards' "also received" on the second.
	local pager = CreateFrame("Button", nil, panel)
	pager:SetSize(10, 14)
	local pagerText = pager:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pagerText:SetPoint("LEFT")
	pager:SetFontString(pagerText)
	pager:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 8)
	pager:SetScript("OnClick", function()
		talk.cardPage = (talk.cardPage or 1) == 1 and 2 or 1
		Show(true)
	end)
	Draggable(pager)
	pager:Hide()
	panel.pager = pager
	panel:EnableKeyboard(not InCombatLockdown())
	if panel.SetPropagateKeyboardInput then
		panel:SetPropagateKeyboardInput(true)
		panel:SetScript("OnKeyDown", OnKeyDown)
	end
	panel:Hide()
end

---------------------------------------------------------------------------
-- Events.
---------------------------------------------------------------------------
local OPENS = {
	GOSSIP_SHOW = "gossip", QUEST_GREETING = "greeting", QUEST_DETAIL = "detail",
	QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete",
}
local CLOSES = { GOSSIP_CLOSED = true, QUEST_FINISHED = true }

-- Whether the game's gossip or quest window is still open.
local function TalkWindowOpen()
	for _, name in ipairs(WINDOWS) do
		local frame = _G[name]
		if frame and ns.Flag(frame:IsShown()) then
			return true
		end
	end
	return false
end

-- For the log: whether ours are up where you can answer with them, and why
-- not. (The card shown, not faded out.)
local function Answerable()
	if not (panel and ns.Flag(panel:IsShown())) then
		return false
	end
	local ok, alpha = pcall(panel.GetEffectiveAlpha, panel)
	alpha = ok and Plain(alpha)
	return type(alpha) ~= "number" or alpha > 0.05
end
local function Where(frame)
	local ok, x, y = pcall(frame.GetCenter, frame)
	x, y = ok and Plain(x), ok and Plain(y)
	if type(x) ~= "number" or type(y) ~= "number" then
		return "unmeasured"
	end
	return ("%.0f,%.0f"):format(x, y)
end
function TalkState()
	local open = {}
	for _, name in ipairs(WINDOWS) do
		local frame = _G[name]
		if frame and ns.Flag(frame:IsShown()) then
			open[#open + 1] = name .. (parked[frame] and " parked" or " in view")
		end
	end
	local function Frame(frame, extra)
		if not frame then return "none" end
		local ok, alpha = pcall(frame.GetEffectiveAlpha, frame)
		alpha = ok and Plain(alpha)
		return ("%s alpha %s at %s%s"):format(ns.Flag(frame:IsShown()) and "shown" or "hidden",
			type(alpha) == "number" and ("%.2f"):format(alpha) or "?", Where(frame), extra)
	end
	return ("windows %s; npc %s (had %s); place %s, cam move %s (moving %s, quest cam pending %s, fade %.2f);"
		.. " bubble %s; card %s; game window %s, close due %s, %s"):format(
		#open > 0 and table.concat(open, ", ") or "none",
		ns.Flag(UnitExists("npc")) and "here" or "gone", tostring(talk.hadNpc), PlaceMode(), MoveMode(),
		tostring(CameraMoving()), tostring(ns.QuestCamPending and ns.QuestCamPending()), camMove.alpha,
		Frame(bubble, bubble and (", on plate %s, waiting %s, free %s"):format(tostring(bubble.onPlate ~= nil),
			tostring(bubble.waiting), tostring(bubble.free)) or ""),
		Frame(panel, panel and (", following %s"):format(tostring(panel.following)) or ""),
		tostring(gameWindow), tostring(closeTimer ~= nil), InCombatLockdown() and "in a fight" or "no fight")
end

local function Open(kind)
	if not ns.db or not Setting("questTalk") or gameWindow then
		return
	end
	if closeTimer then
		closeTimer:Cancel()
		closeTimer = nil
	end
	if not panel then
		CreatePanel()
	end
	-- (A new conversation: where you clicked them, for Opposite Clicked.)
	if not talk.kind then
		talk.clickX = ns.TalkClickX()
	end
	talk.choice, talk.cardPage = nil, nil
	talk.kind = kind
	-- (Whether "npc" is there to go: some talks never have it, see Ending.)
	talk.hadNpc = ns.Flag(UnitExists("npc"))
	-- Anything going wrong: the game's window, so the conversation can go on.
	local ok, err = pcall(Show)
	if not ok then
		ns.Log("questtalk", ("%s: building the screen failed (%s): the game's window back"):format(kind, tostring(err)))
		ShowGameWindow("failed to open " .. kind)
		geterrorhandler()(err)
		return
	end
	if ns.LogDetailOn() then
		ns.LogDetail("questtalk", ("opened %s: %s"):format(kind, TalkState()))
	end
	-- Once more a moment later: the game can set a screen's theme (its page
	-- and emblem) after the window's up. (Only if it's still this screen.)
	local opened = talk.opened or 0
	talk.opened = opened + 1
	C_Timer.After(ART_RECHECK, function()
		if talk.kind == kind and talk.opened == opened + 1 and not gameWindow then
			Reshow("art recheck")
		end
	end)
end

-- The game's window closed: ours go too, unless another opens meanwhile
-- (gossip to a quest closes one before the next opens: wait a moment).
local function ScheduleClose()
	if closeTimer then closeTimer:Cancel() end
	closeTimer = C_Timer.NewTimer(CLOSE_WAIT, function()
		closeTimer = nil
		if not TalkWindowOpen() then
			gameWindow = false
			Hide("the game's window closed")
		elseif ns.LogDetailOn() then
			ns.LogDetail("questtalk", ("close called off, a window's still open: %s"):format(TalkState()))
		end
	end)
end

-- And in case no event says so (Escape closing them, say): while ours show,
-- the game's windows are looked at a few times a second.
-- Also the way out if you're locked out: the game's window open (parked off
-- the screen) with nothing of ours to answer with for LOCKOUT_WAIT while the
-- camera's still (LOCKOUT_MOVING if it never is), or parked with no talk of
-- ours at all: logged with all there is, and the game's window back.
local WATCH_EVERY = 0.2
local LOCKOUT_WAIT = 1.5
local LOCKOUT_MOVING = 10
local watcher = CreateFrame("Frame")
local watched, unseen, hiddenFor, stray = 0, 0, 0, 0
watcher:SetScript("OnUpdate", function(_, elapsed)
	watched = watched + elapsed
	if watched < WATCH_EVERY then
		return
	end
	local step = watched
	watched = 0
	if talk.kind and not closeTimer and not TalkWindowOpen() then
		ScheduleClose()
	end
	if talk.kind and not closeTimer and not gameWindow and TalkWindowOpen() and not Answerable() then
		unseen = CameraMoving() and 0 or unseen + step
		hiddenFor = hiddenFor + step
		if unseen >= LOCKOUT_WAIT or hiddenFor >= LOCKOUT_MOVING then
			ns.Log("questtalk", ("locked out: nothing to answer with for %.1fs (%.1fs of it still), the game's"
				.. " window back: %s"):format(hiddenFor, unseen, TalkState()))
			unseen, hiddenFor = 0, 0
			ShowGameWindow("locked out")
		end
	else
		unseen, hiddenFor = 0, 0
	end
	local parkedShown = false
	if not talk.kind then
		for _, name in ipairs(WINDOWS) do
			local frame = _G[name]
			if frame and parked[frame] and ns.Flag(frame:IsShown()) then
				parkedShown = true
			end
		end
	end
	stray = parkedShown and stray + step or 0
	if stray >= LOCKOUT_WAIT then
		stray = 0
		ns.Log("questtalk", ("locked out: the game's window parked with no talk of ours, back: %s"):format(TalkState()))
		ParkWindows(false)
	end
end)

-- While the camera moves (questTalkCamMove, see MoveMode), every frame: the
-- bubble and the card beside it faded out or down, back once it's still;
-- or, waiting, faded out, moved (off the plate, or back on), faded in.
local MOVE_DIM = 0.35
local FADE_OUT, FADE_IN = 0.15, 0.3 -- seconds, all the way
local follower = CreateFrame("Frame")
follower:SetScript("OnUpdate", function(_, elapsed)
	local now = GetTime()
	if (ns.QuestCamMoving and ns.QuestCamMoving()) or (ns.IsMouseOnCamera and ns.IsMouseOnCamera()) then
		camMove.at = now
	end
	local ok, facing = pcall(GetPlayerFacing)
	facing = ok and Plain(facing)
	if type(facing) == "number" and camMove.facing and elapsed > 0 then
		local delta = math.abs(facing - camMove.facing)
		if delta > math.pi then
			delta = 2 * math.pi - delta -- crossed north
		end
		if delta / elapsed > TURN_RATE then
			camMove.at = now
		end
	end
	camMove.facing = type(facing) == "number" and facing or nil
	if not (bubble and panel) then
		return
	end
	local up = Shown() and bubble:IsShown()
	local mode, moving = MoveMode(), CameraMoving()
	-- (Waiting: on the plate as it starts moving, or off it once it's still.)
	local pending = mode == "wait" and ns.QuestCamPending and ns.QuestCamPending()
	local move = up and mode == "wait"
		and (bubble.waiting and not moving and not pending or bubble.onPlate ~= nil and moving)
	local want = 1
	if move then
		want = 0
	elseif up and bubble.onPlate and moving and (mode == "fade" or mode == "dim") then
		want = mode == "fade" and 0 or MOVE_DIM
	end
	if want ~= camMove.want then
		camMove.want = want
		if up and ns.LogDetailOn() then
			ns.LogDetail("questtalk", ("fading to %.2f (%s): %s"):format(want,
				move and (bubble.waiting and "waiting over: to the plate" or "camera moving: off the plate")
				or want < 1 and "camera moving" or "still", TalkState()))
		end
	end
	if camMove.alpha ~= want then
		local step = elapsed / (want < camMove.alpha and FADE_OUT or FADE_IN)
		camMove.alpha = want < camMove.alpha and math.max(want, camMove.alpha - step)
			or math.min(want, camMove.alpha + step)
	end
	if move and camMove.alpha == 0 then
		Place()
		PlacePanel()
	end
	bubble:SetAlpha(camMove.alpha)
	panel:SetAlpha((panel.following or mode == "wait") and camMove.alpha or 1)
end)

-- A plate came or went while ours show. A quest accepted refreshes the
-- NPC's plate (its mark goes) as the talk ends, when "npc" is gone: ours
-- stay just where they are then, off the plate, not to the middle for the
-- moment till the close (the close hides them; the next screen, if one
-- opens, places them again). Hiding them meanwhile made them blink between
-- a quest turned in and the next one offered. A plate just swapped comes
-- back a moment later, so only still gone after that is it the middle.
-- ("npc" gone counts only if the talk began with it: some NPCs' never do,
-- and a plate coming or going nearby then hid ours mid-talk.) Held for an
-- end that doesn't come (the window still open a moment later, no close
-- on its way): ours back over them.
local REPLATE_WAIT = 0.1
local ENDING_WAIT = 0.3
local function Ending()
	return closeTimer ~= nil or not TalkWindowOpen()
		or talk.hadNpc and not ns.Flag(UnitExists("npc"))
end
local function HoldForEnd()
	if bubble.onPlate then
		-- (Where it is on the screen now, in its own units, as SetPoint takes them.)
		local ok, left, bottom = pcall(function() return bubble:GetLeft(), bubble:GetBottom() end)
		left, bottom = ok and Plain(left), ok and Plain(bottom)
		if type(left) == "number" and type(bottom) == "number" then
			bubble:ClearAllPoints()
			bubble:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
			bubble.onPlate = nil
		else
			-- (Can't be measured over a plate: hidden till the close, as before.)
			bubble:Hide()
			panel:Hide()
		end
	end
	ns.LogDetail("questtalk", ("held for the end (%s)"):format(panel:IsShown() and "in place" or "hidden"))
	local kind, opened = talk.kind, talk.opened
	C_Timer.After(ENDING_WAIT, function()
		if talk.kind == kind and talk.opened == opened and not gameWindow
			and not closeTimer and TalkWindowOpen() then
			if panel:IsShown() then
				Place()
				PlacePanel()
			else
				Reshow("no end came")
			end
			if ns.LogDetailOn() then
				ns.LogDetail("questtalk", ("no end came, ours back: %s"):format(TalkState()))
			end
		elseif ns.LogDetailOn() then
			ns.LogDetail("questtalk", ("end held: %s"):format(talk.kind ~= kind and "talk " .. tostring(talk.kind)
				or talk.opened ~= opened and "another screen" or gameWindow and "game window"
				or closeTimer and "closing" or "window shut"))
		end
	end)
end
local function Replace(event)
	if Ending() then
		if ns.LogDetailOn() then
			ns.LogDetail("questtalk", ("%s, talk ending (%s): %s"):format(event, closeTimer and "close due"
				or not TalkWindowOpen() and "window shut" or "npc gone", TalkState()))
		end
		HoldForEnd()
		return
	end
	if PlaceMode() == "head" and not NpcPlate() then
		C_Timer.After(REPLATE_WAIT, function()
			if not (Shown() and bubble) then
				return
			end
			if Ending() then
				ns.LogDetail("questtalk", ("%s, talk ending after the replate wait"):format(event))
				HoldForEnd()
				return
			end
			Place()
			PlacePanel()
			if ns.LogDetailOn() then
				ns.LogDetail("questtalk", ("%s, placed after the replate wait: %s"):format(event, TalkState()))
			end
		end)
		return
	end
	Place()
	PlacePanel() -- (the list beside it, or back on its own)
end

local events = CreateFrame("Frame")
for event in pairs(OPENS) do events:RegisterEvent(event) end
for event in pairs(CLOSES) do events:RegisterEvent(event) end
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event)
	if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
		-- (Their plate gone, or handed to someone else: over them again, or the middle.)
		if Shown() and bubble then
			Replace(event)
		end
	elseif OPENS[event] then
		-- (A frame later: the game's windows have shown and set themselves up.)
		-- Only while the game's window is really open (it may not open at all).
		C_Timer.After(0, function()
			if TalkWindowOpen() then
				Open(OPENS[event])
			else
				ns.LogDetail("questtalk", ("%s: no window open a frame later, not opened"):format(event))
			end
		end)
	elseif CLOSES[event] then
		ns.LogDetail("questtalk", event)
		ScheduleClose()
	elseif panel then
		-- Keys: none held back in a fight (the game doesn't let us choose then).
		panel:EnableKeyboard(event == "PLAYER_REGEN_ENABLED")
		-- (The plate settings, if a fight kept them from going back.)
		if event == "PLAYER_REGEN_ENABLED" and not Shown() then RoomAtTop(false) end
	end
end)

-- The game moving its windows while parked, and showing them again.
local function HookWindows()
	for _, name in ipairs(WINDOWS) do
		local frame = _G[name]
		if frame then
			hooksecurefunc(frame, "SetPoint", Moved)
			-- (Parked as it shows, so it doesn't flash up for a frame first.)
			frame:HookScript("OnShow", function(self)
				if ns.db and Setting("questTalk") and not gameWindow then Park(self) end
				ns.LogDetail("questtalk", ("%s shown%s"):format(name, parked[self] and ", parked" or ""))
			end)
			frame:HookScript("OnHide", function()
				ns.LogDetail("questtalk", name .. " hidden")
				if Shown() then ScheduleClose() end
			end)
		end
	end
	if type(_G.UpdateUIPanelPositions) == "function" then
		hooksecurefunc("UpdateUIPanelPositions", function()
			if Shown() then
				for _, name in ipairs(WINDOWS) do Moved(_G[name]) end
			end
		end)
	end
end
HookWindows()

-- Whether the quest camera holds still (no drift) for us: the bubble over
-- the NPC's head (following their plate, it jiggled as the camera drifted),
-- with questTalkStill.
function ns.QuestTalkHoldsCamera()
	return talk.kind ~= nil and PlaceMode() == "head" and Setting("questTalkStill") and true or false
end

-- Turned off on the page (or the page off): the game's windows back.
function ns.RefreshQuestTalk()
	if not Setting("questTalk") or not TalkWindowOpen() then
		-- (Off, or no conversation going on: nothing of ours left up.)
		if talk.kind then Hide("turned off, or no conversation") end
	elseif talk.kind then
		Show(true)
	end
end

-- The Style hub's Quest talk page changed: dressed again, if it's up.
function ns.RefreshQuestTalkStyle()
	if talk.kind then Show(true) end
end

---------------------------------------------------------------------------
-- The Style hub's Quest talk page's preview: an NPC's words in a bubble and
-- the list of replies under it, dressed as quest talk dresses its own (Dress,
-- Font): the bubble in the page's look, the list in it too or its own dark one
-- (questTalkCardSame). Gives the holder; :Refresh() dresses them again.

local PREVIEW_ROWS = {
	{ icon = QUEST_ICONS.available, text = "The Turnip Thief" },
	{ icon = QUEST_ICONS.complete, text = "Fence Mending" },
	{ text = "Goodbye" },
}

function ns.MakeQuestTalkPreview(parent, width)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 300)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("TOPLEFT", 6, -5)
	caption:SetText(L["Preview"])
	caption.searchSkip = true
	local inner = width - 100 -- (the bubble's and the list's width)
	local sample = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate")
	sample:SetWidth(inner)
	sample:SetPoint("TOP", holder, "TOP", 0, -26)
	Dressable(sample)
	local name = sample:CreateFontString(nil, "OVERLAY")
	name:SetPoint("TOPLEFT", PAD_X, -PAD_Y)
	local text = sample:CreateFontString(nil, "OVERLAY")
	text:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	text:SetWidth(inner - 2 * PAD_X)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(true)
	local list = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate")
	list:SetWidth(inner)
	list:SetPoint("TOP", sample, "BOTTOM", 0, -FOLLOW_GAP)
	Dressable(list)
	local lines = {}
	for i, entry in ipairs(PREVIEW_ROWS) do
		local line = { key = list:CreateFontString(nil, "OVERLAY"), icon = list:CreateTexture(nil, "ARTWORK"),
			text = list:CreateFontString(nil, "OVERLAY") }
		line.icon:SetSize(16, 16)
		line.icon:SetTexture(entry.icon)
		line.icon:SetShown(entry.icon ~= nil)
		line.words = entry.text
		lines[i] = line
	end
	function holder:Refresh()
		local look = CurrentLook()
		-- The bubble: their name, then their words, in the look's fonts.
		Dress(sample, look)
		name:SetFontObject("GameFontNormalSmall")
		text:SetFontObject(_G[look.font] or GameFontHighlight)
		Font(name)
		Font(text)
		name:SetTextColor(unpack(look.name))
		text:SetTextColor(unpack(look.text))
		name:SetText(L["Farmer Brennick"])
		text:SetText(L["Something has been taking the turnips at night, and nobody here is brave enough to " ..
			"keep watch. Would you?"])
		local high = (Plain(name:GetStringHeight()) or 12) + 4 + (Plain(text:GetStringHeight()) or 40) + PAD_Y * 2
		sample:SetHeight(high)
		local art = sample.page:IsShown() and PageArt()
		if art then SetArtFitted(sample.page, art, inner - 6, high - 6, "top") end
		-- The list: as its card is dressed (questTalkCardSame), its words to suit.
		local cardLook = Styled("questTalkCardSame") and look or nil
		Dress(list, cardLook)
		local colors = cardLook == LOOKS.parchment and INK.parchment or INK.dark
		local rowHeight = ROW_HEIGHT * math.max(1, Styled("questTalkTextSize"))
		local y = -12
		for i, line in ipairs(lines) do
			line.key:SetFontObject(colors == INK.parchment and "QuestFont" or "GameFontDisableSmall")
			line.text:SetFontObject(colors == INK.parchment and "QuestFont" or "GameFontHighlight")
			Font(line.key)
			Font(line.text)
			if colors == INK.parchment then
				line.key:SetShadowOffset(0, 0)
				line.text:SetShadowOffset(0, 0)
			end
			line.key:SetTextColor(unpack(colors.dim))
			line.text:SetTextColor(unpack(colors.text))
			line.key:SetText(Setting("questTalkKeys") and tostring(i) or "")
			line.text:SetText(L[line.words])
			line.key:ClearAllPoints()
			line.key:SetPoint("TOPLEFT", 10, y - (rowHeight - 12) / 2)
			line.icon:ClearAllPoints()
			line.icon:SetPoint("LEFT", list, "TOPLEFT", 30, y - rowHeight / 2)
			line.text:ClearAllPoints()
			line.text:SetPoint("LEFT", list, "TOPLEFT", 52, y - rowHeight / 2)
			y = y - rowHeight
		end
		local listHigh = -y + 12
		list:SetHeight(listHigh)
		art = list.page:IsShown() and PageArt()
		if art then SetArtFitted(list.page, art, inner - 6, listHigh - 6, "bottom") end
		local total = 26 + high + FOLLOW_GAP + listHigh + 14
		if holder:GetHeight() ~= total or not holder.styleScene then
			holder:SetHeight(total)
			if ns.StyleScene then ns.StyleScene(holder) end
		end
	end
	return holder
end
