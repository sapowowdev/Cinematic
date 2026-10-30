-- Chat Cam's Ultra immersive subtitles (chatCamImmersive, ChatCam.lua): while
-- a conversation has the camera, every say and yell shows as a subtitle in
-- the letterbox's bottom bar (twice its height then: Effects.lua), the
-- speaker's name over their words (the chat bubbles still show). Each
-- line stays up as long as speech from behind you would (ns.SpeechLife); a
-- new one takes its place.
local _, ns = ...

local FADE_IN, FADE_OUT = 0.25, 0.4 -- seconds
local WIDTH = 0.6  -- share of the screen's width the words wrap at
local NAME_GAP = 2 -- between the name and the words
local LOW_EDGE = 12 -- the words kept at least this far up off the screen's bottom

local holder
local slots = {} -- two, taking turns: { frame, name, text, born, life, fading }
local current = 0

local function Plain(value)
	return type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value or nil
end

local function Slot(i)
	if slots[i] then
		return slots[i]
	end
	local frame = CreateFrame("Frame", nil, holder)
	frame:SetSize(1, 1)
	frame:SetAlpha(0)
	local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("BOTTOM", frame, "TOP", 0, NAME_GAP)
	name:SetShadowColor(0, 0, 0, 1)
	name:SetShadowOffset(1, -1)
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	text:SetPoint("TOP", frame, "TOP")
	text:SetJustifyH("CENTER")
	text:SetWordWrap(true)
	text:SetShadowColor(0, 0, 0, 1)
	text:SetShadowOffset(1, -1)
	slots[i] = { frame = frame, name = name, text = text }
	return slots[i]
end

-- The words' middle in the bottom bar (or low on the screen, the bar thin).
local function Place(slot)
	local bar = 0
	local letterbox = ns.letterbox
	if letterbox and ns.Flag(letterbox:IsShown()) then
		bar = letterbox.bottom:GetHeight() or 0
	end
	local height = slot.text:GetStringHeight()
	local y = math.max(bar / 2 + height / 2, height + LOW_EDGE)
	slot.frame:ClearAllPoints()
	slot.frame:SetPoint("TOP", holder, "BOTTOM", 0, y)
end

local function OnUpdate()
	local now = GetTime()
	local on = ns.ChatCamImmersive and ns.ChatCamImmersive()
	local showing = false
	for i, slot in pairs(slots) do
		if slot.born then
			if not on or i ~= current or now >= slot.born + slot.life then
				slot.fading = slot.fading or now
			end
			local alpha
			if slot.fading then
				alpha = math.min(slot.frame:GetAlpha(), 1 - (now - slot.fading) / FADE_OUT)
			else
				alpha = math.min(1, (now - slot.born) / FADE_IN)
			end
			if alpha <= 0 then
				slot.born = nil
				slot.frame:SetAlpha(0)
				slot.frame:Hide()
			else
				slot.frame:SetAlpha(alpha)
				Place(slot)
				showing = true
			end
		end
	end
	if not on and not showing then
		holder:SetScript("OnUpdate", nil)
	end
end
local OnHolderUpdate = ns.Profiled("Chat Cam subtitles", OnUpdate)

-- A line said (event: CHAT_MSG_SAY, _YELL, _MONSTER_SAY...), as a subtitle.
function ns.ShowSubtitle(event, author, words)
	words = Plain(words)
	if not words then
		return
	end
	if not holder then
		holder = CreateFrame("Frame", nil, UIParent)
		holder:SetAllPoints(UIParent)
		holder:SetFrameStrata("MEDIUM")
		holder:EnableMouse(false)
		if ns.AddOverlay then
			ns.AddOverlay(holder) -- (stays up with the UI hidden, like the letterbox)
		end
	end
	current = current % 2 + 1
	local slot = Slot(current)
	local width = UIParent:GetWidth() * WIDTH
	slot.frame:SetWidth(width)
	slot.text:SetWidth(width)
	slot.text:SetText(words)
	slot.frame:SetHeight(math.max(1, slot.text:GetStringHeight()))
	author = Plain(author)
	slot.name:SetText(author and author ~= "?" and (_G.Ambiguate and _G.Ambiguate(author, "none") or author) or "")
	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[(event or ""):gsub("^CHAT_MSG_", "")]
	slot.name:SetTextColor(info and info.r or 1, info and info.g or 0.82, info and info.b or 0)
	slot.born, slot.life, slot.fading = GetTime(), ns.SpeechLife and ns.SpeechLife(words) or 5, nil
	slot.frame:SetAlpha(0)
	slot.frame:Show()
	Place(slot)
	holder:SetScript("OnUpdate", OnHolderUpdate)
end

-- Players' say and yell in the conversation too (NPCs' come from ChatCam.lua,
-- as it takes each line).
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("CHAT_MSG_SAY")
watcher:RegisterEvent("CHAT_MSG_YELL")
watcher:SetScript("OnEvent", function(_, event, text, author)
	if ns.ChatCamImmersive and ns.ChatCamImmersive() then
		ns.ShowSubtitle(event, author, text)
	end
end)
