-- Cinematic: the Tooltips page's parts grid (with the page switched on, in
-- and out of CineMode). Each part shows on first hover or not
-- (tooltipShow<part>First), and once the tooltip's been up tooltipFullAfter
-- seconds or not (...Later): the background and border, the health bar
-- under unit tooltips, and lines of unit tooltips (players, NPCs and mobs):
-- guild and titles, level, spec and class, creature type, faction and PvP,
-- reputation faction, threat, quest lines; and the quest lines of objects
-- in the world.
-- A line is taken out by moving the lines under it up one (text and colour,
-- both sides) and clearing the last, then letting the tooltip size itself
-- again. Unreadable (secret) lines are kept, and a tooltip whose lines can't
-- all be read is left as it is.
local _, ns = ...

-- Hovered long enough (tooltipFullAfter): the After column's parts, until
-- the tooltip hides or moves on to another unit.
local revealed = false
-- Whether this tooltip's lines were cut (to fill in again for the After column).
local linesCut = false

-- Whether a part (ns.TOOLTIP_PARTS) is taken out now: unticked in the
-- column for now (On first hover, or After once revealed). With
-- tooltipFullAfter off, none is.
local function Cut(part)
	local db = ns.db
	if not (db and db.enabled and db.handleTooltips) or (db.tooltipFullAfter or 0) <= 0 then
		return false
	end
	return not db["tooltipShow" .. part .. (revealed and "Later" or "First")]
end

-- Fade in/out's seconds (tooltipFadeTime; nil: no fading).
local function FadeTime()
	local time = ns.db and ns.db.enabled and ns.db.tooltipFadeTime
	return time and time > 0 and time or nil
end

local function Left(i)
	return _G["GameTooltipTextLeft" .. i]
end
local function Right(i)
	return _G["GameTooltipTextRight" .. i]
end

-- Whether a and b are the same string (secret: no).
local function Same(a, b)
	local ok, same = pcall(function() return a ~= nil and a == b end)
	return ok and same
end

-- The titles of the quests in your log.
local function QuestTitles()
	local titles = {}
	pcall(function()
		if C_QuestLog and C_QuestLog.GetInfo then
			for i = 1, C_QuestLog.GetNumQuestLogEntries() do
				local info = C_QuestLog.GetInfo(i)
				if info and not info.isHeader and info.title then
					titles[info.title] = true
				end
			end
		elseif GetQuestLogTitle then
			for i = 1, GetNumQuestLogEntries() do
				local title, _, _, isHeader = GetQuestLogTitle(i)
				if title and not isHeader then
					titles[title] = true
				end
			end
		end
	end)
	return titles
end

-- The texts of the tooltip's lines whose kind the client gives, -> part:
-- quest lines (titles, objectives, party members on the quest) and threat.
local function TypedTexts(tooltip)
	local texts = {}
	local kinds = Enum and Enum.TooltipDataLineType
	if not (kinds and tooltip.GetTooltipData) then
		return texts
	end
	local KEYS = {
		[kinds.QuestObjective or false] = "Quest", [kinds.QuestTitle or false] = "Quest",
		[kinds.QuestPlayer or false] = "Quest", [kinds.UnitThreat or false] = "Threat",
	}
	KEYS[false] = nil
	pcall(function()
		local data = tooltip:GetTooltipData()
		for _, line in ipairs(data and data.lines or {}) do
			if line.leftText and KEYS[line.type] then
				texts[line.leftText] = KEYS[line.type]
			end
		end
	end)
	return texts
end

-- The threat line ("100% Threat"), from the game's own wording.
-- Reputation factions' names (an NPC's "Hara'ti" line), every one the game
-- knows, read once: by ID, so ones under collapsed headers count too.
local MAX_FACTION_ID = 5000
local repFactions
local function RepFactions()
	if not repFactions then
		repFactions = {}
		pcall(function()
			for id = 1, MAX_FACTION_ID do
				local name
				if C_Reputation and C_Reputation.GetFactionDataByID then
					local data = C_Reputation.GetFactionDataByID(id)
					name = data and data.name
				elseif GetFactionInfoByID then
					name = GetFactionInfoByID(id)
				end
				if type(name) == "string" and name ~= "" then
					repFactions[name] = true
				end
			end
		end)
	end
	return repFactions
end

local threatPattern
local function ThreatPattern()
	if not threatPattern then
		local format = type(THREAT_TOOLTIP) == "string" and THREAT_TOOLTIP or "%d%% Threat"
		-- (Magic characters escaped bar %, so %% stays a literal %; %d is any number.)
		local pattern = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%d", "%%d+")
		threatPattern = "^" .. pattern .. "$"
	end
	return threatPattern
end

-- The lines taken out: line number -> true. An object in the world (object
-- set) has just its quest lines taken out, by their own row (ObjQuest).
local function LinesToCut(tooltip, count, unit, object)
	local cut = {}
	local level = LEVEL or "Level"
	local creatureType, className, isPlayer, guildName
	if unit then
		local okPlayer, player = pcall(function()
			return ns.Flag(UnitIsPlayer(unit)) or tostring(UnitGUID(unit)):find("^Player%-") ~= nil
		end)
		isPlayer = okPlayer and player
		local ok, kind = pcall(UnitCreatureType, unit)
		creatureType = ok and kind or nil
		local okClass, class = pcall(UnitClass, unit)
		className = okClass and type(class) == "string" and class or nil
		local okGuild, guild = pcall(GetGuildInfo, unit)
		guildName = okGuild and type(guild) == "string" and guild ~= ""
			and not (issecretvalue and issecretvalue(guild)) and guild or nil
	end
	local questTitles, typed = QuestTitles(), TypedTexts(tooltip)
	local inQuest = false
	for i = 2, count do
		local text = Left(i) and Left(i):GetText()
		local ok, key = pcall(function()
			if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
				return nil
			end
			if typed[text] == "Threat" or text:find(ThreatPattern()) then
				inQuest = false
				return "Threat"
			elseif typed[text] or questTitles[text] then
				inQuest = true
				return "Quest"
			elseif inQuest and text:find("^%s") then
				return "Quest" -- (an objective under its quest)
			end
			inQuest = false
			if text:find("^<.*>$") then
				return "Guild"
			elseif guildName and text:find(guildName, 1, true) then
				return "Guild" -- (a player's guild with no brackets, as on retail: "Top Opp")
			elseif text:find(level, 1, true) then
				return "Level"
			elseif className and isPlayer and text:find(className, 1, true) then
				return "Spec" -- (a player's "Fury Warrior")
			elseif Same(text, creatureType) then
				return "Type"
			elseif text == FACTION_HORDE or text == FACTION_ALLIANCE or text == PVP then
				return "Faction"
			elseif RepFactions()[text] then
				return "Rep"
			elseif i == 2 and unit and not isPlayer then
				return "Guild" -- (an NPC's title with no brackets: "Ranger-General of Silvermoon")
			end
		end)
		if object then
			key = key == "Quest" and "ObjQuest" or nil
		end
		if ok and key and Cut(key) then
			cut[i] = true
		end
	end
	return cut
end

-- One line's text and colour, both sides (nil: unreadable).
local function Snapshot(i)
	local ok, line = pcall(function()
		local left, right = Left(i), Right(i)
		local line = { left = left:GetText(), lr = { left:GetTextColor() } }
		if right and ns.Flag(right:IsShown()) then
			line.right, line.rr = right:GetText(), { right:GetTextColor() }
		end
		return line
	end)
	return ok and line or nil
end

-- The icons beside lines (a quest objective's bullet, or its tick once done):
-- textures of their own, held to their line, so they move with it, or hide
-- with it taken out. One whose line can't be read (restricted) hides.
local function MoveIcons(cut, count, newIndex)
	for k = 1, 30 do
		local icon = _G["GameTooltipTexture" .. k]
		if not icon then
			break
		end
		if ns.Flag(icon:IsShown()) then
			local ok, point, line, relative, x, y = pcall(function()
				local point, relativeTo, relative, x, y = icon:GetPoint(1)
				for i = 2, count do
					if relativeTo == Left(i) then
						return point, i, relative, x, y
					end
				end
			end)
			local new = ok and line and not cut[line] and newIndex[line]
			if new then
				if new ~= line then
					icon:ClearAllPoints()
					icon:SetPoint(point, Left(new), relative, x, y)
				end
			else
				icon:Hide()
			end
		end
	end
end

local function CutLines(tooltip, object)
	local okCount, count = pcall(tooltip.NumLines, tooltip)
	if not okCount or type(count) ~= "number" or count < 2 then
		return
	end
	local unit
	pcall(function()
		local _, u = tooltip:GetUnit()
		unit = u
	end)
	local cut = LinesToCut(tooltip, count, unit, object)
	if not next(cut) then
		return
	end
	local kept, newIndex = {}, {}
	for i = 2, count do
		if not cut[i] then
			local line = Snapshot(i)
			if not line then
				return -- (unreadable: leave the tooltip as it is)
			end
			kept[#kept + 1] = line
			newIndex[i] = #kept + 1
		end
	end
	pcall(function()
		for n = 2, count do
			local line, left, right = kept[n - 1], Left(n), Right(n)
			if line then
				left:SetText(line.left)
				left:SetTextColor(line.lr[1], line.lr[2], line.lr[3])
				left:Show()
				if right then
					if line.right then
						right:SetText(line.right)
						right:SetTextColor(line.rr[1], line.rr[2], line.rr[3])
						right:Show()
					else
						right:SetText(nil)
						right:Hide()
					end
				end
			else
				left:SetText(nil)
				left:Hide()
				if right then
					right:SetText(nil)
					right:Hide()
				end
			end
		end
	end)
	pcall(MoveIcons, cut, count, newIndex)
	linesCut = true
	if ns.Flag(tooltip:IsShown()) then
		pcall(tooltip.Show, tooltip) -- (sizes itself to the lines again)
	end
end

local LINE_PARTS = { "Guild", "Level", "Spec", "Type", "Faction", "Rep", "Threat", "Quest" }
local function AnyLineCut()
	for _, part in ipairs(LINE_PARTS) do
		if Cut(part) then
			return true
		end
	end
	return false
end

-- The background and border: see-through while taken out (put back once, after).
local borderHidden = false
local function UpdateBorder(tooltip)
	local slice = tooltip.NineSlice
	if not slice then
		return
	end
	if Cut("Border") then
		slice:SetAlpha(0)
		borderHidden = true
	elseif borderHidden then
		slice:SetAlpha(1)
		borderHidden = false
	end
end

-- The health bars (both names, where they're two bars), and the ones hidden: bar -> true.
local bars, hiddenBars = {}, {}

-- A bar hides as it shows, and as the tooltip moves on to another unit
-- (it stays shown then, so shows no more).
local function HideBar(bar)
	if Cut("Health") and ns.Flag(bar:IsShown()) then
		hiddenBars[bar] = true
		bar:Hide()
	end
end

-- Shown in full: the border and bars back, and the lines filled in again
-- (refilling: our own refill, not a new tooltip): the game fills the
-- tooltip again where it can, or else a unit's is set again.
local refilling = false
-- The tooltip's unit, if any (nil: none, or unreadable).
local function TooltipUnit(tooltip)
	local ok, unit = pcall(function()
		local _, unit = tooltip:GetUnit()
		return unit
	end)
	return ok and unit or nil
end

-- An object in the world (a quest's rune, chest or herb): no unit, and
-- owned by UIParent or the world.
local function IsWorldObject(tooltip)
	local ok, isObject = pcall(function()
		local owner = tooltip:GetOwner()
		return TooltipUnit(tooltip) == nil and (owner == nil or owner == UIParent or owner == WorldFrame)
	end)
	return ok and isObject
end

-- Fade in/out (tooltipFadeTime seconds, Tooltips page, with its switch off
-- too): tooltips fade in as they show, cross-fade into the After column's
-- look, and fade out before Effects.lua hides one for the mouse being still
-- too long. The game hides others at once (or fades a world one out
-- itself), so those can't. A fade stops once something else takes the
-- tooltip's alpha the other way (the game's own fade out of a world
-- tooltip, as one fades in).
local fader = CreateFrame("Frame")
fader:Hide()
local fade -- { from, to, start, length, set (the alpha last set), done, kind ("in", "reveal", "out") }

local function Alpha(tooltip)
	local ok, alpha = pcall(tooltip.GetAlpha, tooltip)
	return ok and type(alpha) == "number" and not (issecretvalue and issecretvalue(alpha)) and alpha or nil
end

local function StopFade(restore)
	if fade and restore then
		GameTooltip:SetAlpha(1)
	end
	fade = nil
	fader:Hide()
end

fader:SetScript("OnUpdate", function()
	local alpha = Alpha(GameTooltip)
	local against = alpha and fade and (fade.to > fade.from and alpha < fade.set - 0.02
		or fade.to < fade.from and alpha > fade.set + 0.02)
	if not fade or not ns.Flag(GameTooltip:IsShown()) or against then
		StopFade()
		return
	end
	local t = fade.length > 0 and math.min(1, (GetTime() - fade.start) / fade.length) or 1
	fade.set = fade.from + (fade.to - fade.from) * t
	GameTooltip:SetAlpha(fade.set)
	if t >= 1 then
		local done = fade.done
		StopFade()
		if done then done() end
	end
end)

-- The fade in is the tooltip coming up at all, not each new thing in it: the
-- game hides and shows it again for every new thing hovered, so a show within
-- KEEP_UP seconds of a hide carries on from the alpha it had then (sweeping
-- the mouse across buttons doesn't flicker it).
local KEEP_UP = 0.3
local hiddenAt, hiddenAlpha = 0, 0

local function StartFade(kind, from, to, length, done)
	fade = { kind = kind, from = from, to = to, start = GetTime(), length = length, set = from, done = done }
	GameTooltip:SetAlpha(from)
	fader:Show()
end

-- Hovered long enough: the After column's parts. Lines taken out on first
-- hover are filled in again (the game fills the tooltip again where it
-- can, or else a unit's is set again; refilling: our own refill, not a new
-- tooltip), and its fill takes out the After column's; with none taken out
-- yet, they're taken out from what's there.
local function ShowLater(tooltip)
	revealed = true
	UpdateBorder(tooltip)
	if not Cut("Health") then
		for bar in pairs(hiddenBars) do
			bar:Show()
		end
		hiddenBars = {}
	end
	for _, bar in ipairs(bars) do
		HideBar(bar)
	end
	local unit = TooltipUnit(tooltip)
	if linesCut then
		linesCut = false
		refilling = true
		if tooltip.RefreshData then
			pcall(tooltip.RefreshData, tooltip)
		elseif unit then
			pcall(tooltip.SetUnit, tooltip, unit)
		end
		refilling = false
	elseif unit then
		CutLines(tooltip)
	elseif IsWorldObject(tooltip) then
		CutLines(tooltip, true)
	end
end

-- With Fade in/out, the whole tooltip fades out, takes on the After look
-- while it can't be seen (the lines move and the box resizes then), and
-- fades back in: half the fade time each way.
local function Reveal(tooltip)
	if revealed or not ns.Flag(tooltip:IsShown()) or (fade and (fade.kind == "reveal" or fade.kind == "out")) then
		return -- (already on its way, or fading out to hide)
	end
	local time = FadeTime()
	if not time then
		ShowLater(tooltip)
		return
	end
	StartFade("reveal", Alpha(tooltip) or 1, 0, time / 2, function()
		if ns.Flag(tooltip:IsShown()) then
			ShowLater(tooltip)
			StartFade("in", 0, 1, time / 2)
		end
	end)
end

-- The countdown to showing in full, from each new tooltip or unit.
local fullTimer
local function StartCountdown(tooltip)
	if fullTimer then
		fullTimer:Cancel()
		fullTimer = nil
	end
	local after = ns.db and ns.db.tooltipFullAfter or 0
	if after > 0 then
		fullTimer = C_Timer.NewTimer(after, function()
			fullTimer = nil
			Reveal(tooltip)
		end)
	end
end

-- A new unit in the tooltip (its name changed) starts again, taken out.
local shownName
local function OnUnitTooltip(tooltip)
	if tooltip ~= GameTooltip then
		return
	end
	local name = Left(1) and Left(1):GetText()
	if not refilling and not Same(name, shownName) then
		shownName = name
		if fade and fade.kind == "reveal" then
			StopFade(true) -- (a new unit: its own first look)
		end
		if revealed then
			revealed = false
			UpdateBorder(tooltip)
		end
		StartCountdown(tooltip)
	end
	for _, bar in ipairs(bars) do
		HideBar(bar)
	end
	if AnyLineCut() then
		CutLines(tooltip)
	end
end

-- An object in the world (a quest's rune, chest or herb): its quest lines.
-- World tooltips have no unit and are owned by UIParent or the world.
local function OnObjectTooltip(tooltip)
	if tooltip == GameTooltip and Cut("ObjQuest") and IsWorldObject(tooltip) then
		CutLines(tooltip, true)
	end
end

-- Fades the tooltip out and then runs done (Effects.lua's hide). False with
-- fading off: the caller hides it now.
function ns.TooltipFadeOut(done)
	local time = FadeTime()
	if not time then
		return false
	end
	if not (fade and fade.kind == "out") then
		StartFade("out", Alpha(GameTooltip) or 1, 0, time, done)
	end
	return true
end

-- A fade out that's no longer wanted (the mouse moved): the tooltip back.
function ns.TooltipFadeCancel()
	if fade and fade.kind == "out" then
		StopFade(true)
	end
end

-- /cine debug tooltipparts: the next tooltip's shown parts, bar its lines'
-- text (name, kind, size, where), printed a moment after it shows.
local listParts = false
function ns.TooltipPartsDebug()
	listParts = true
	ns.Print("Mouse over something: its tooltip's parts print in a moment.")
end

-- Each piece read on its own, so one restricted call doesn't lose the rest.
local function Describe(part)
	local function Try(f)
		local ok, text = pcall(f)
		return ok and text or "?"
	end
	return ("%s (%s) %s at %s, %s"):format(
		Try(function() return part:GetDebugName() end),
		Try(function() return part:GetObjectType() end),
		Try(function() return ("%.0fx%.0f"):format(part:GetSize()) end),
		Try(function()
			local point, relativeTo, _, x, y = part:GetPoint(1)
			return ("%s of %s %.0f,%.0f"):format(point, relativeTo and relativeTo:GetDebugName() or "-", x, y)
		end),
		Try(function() return part.GetAtlas and part:GetAtlas() or part.GetTexture and part:GetTexture() end))
end

local function ListParts(tooltip)
	local function Walk(frame, depth)
		for _, region in ipairs({ frame:GetRegions() }) do
			if ns.Flag(region:IsShown()) and region:GetObjectType() ~= "FontString" then
				ns.Print(("%s%s"):format(("  "):rep(depth), Describe(region)))
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			if ns.Flag(child:IsShown()) then
				ns.Print(("%s%s"):format(("  "):rep(depth), Describe(child)))
				if depth < 2 then
					Walk(child, depth + 1)
				end
			end
		end
	end
	pcall(Walk, tooltip, 0)
end

function ns.HookTooltipParts()
	-- Unit lines (and objects'): after every fill (refreshes too) where the
	-- client says so, else as the tooltip's set or shows.
	local processor = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum
		and Enum.TooltipDataType
	if processor then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
		TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes or "ALL", function(tooltip, data)
			if not (data and data.type == Enum.TooltipDataType.Unit) then
				OnObjectTooltip(tooltip)
			end
		end)
	else
		hooksecurefunc(GameTooltip, "SetUnit", OnUnitTooltip)
	end
	GameTooltip:HookScript("OnShow", function(tooltip)
		if refilling then
			return
		end
		-- (A unit's lines are cut before it shows: linesCut stays as it is.)
		revealed = false
		UpdateBorder(tooltip)
		StartCountdown(tooltip)
		if FadeTime() and tooltip == GameTooltip then
			local from = GetTime() - hiddenAt <= KEEP_UP and hiddenAlpha or 0
			StartFade("in", from, 1, FadeTime() * (1 - from))
		elseif fade then
			StopFade(true)
		end
		if not processor then
			OnObjectTooltip(tooltip)
		end
		if listParts then
			listParts = false
			C_Timer.After(0.3, function() ListParts(tooltip) end)
		end
	end)
	GameTooltip:HookScript("OnHide", function()
		if fullTimer then
			fullTimer:Cancel()
			fullTimer = nil
		end
		revealed, linesCut, shownName = false, false, nil
		hiddenBars = {}
		hiddenAt, hiddenAlpha = GetTime(), Alpha(GameTooltip) or (fade and fade.set) or 1
		StopFade(true)
	end)
	-- The health bar hides each time it shows.
	for _, bar in ipairs({ GameTooltipStatusBar or false, GameTooltip.StatusBar or false }) do
		if bar and bar ~= bars[1] then
			bars[#bars + 1] = bar
			bar:HookScript("OnShow", HideBar)
		end
	end
end
