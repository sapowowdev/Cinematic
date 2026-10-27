-- Wind Guide (a demo, maybe a Vision later): wind blowing across the screen
-- toward your waypoint. Streaks of wind (or light, embers, snow... in your
-- class and spec's style, WindGuideStyles.lua) blow in from the edge
-- nearest it (a few from anywhere) and drift there, swaying, in gusts; when
-- it's off the screen they sweep out the side to turn to. The waypoint: retail's
-- navigation marker where the client has one (exactly where it is on
-- screen), else your map pin or the quest you're tracking, by where it lies
-- from you on the map and the way you face (so it's off while you swing the
-- camera round without turning). Its own overlay, like Vitals Vision's.
-- Sprites: Media/make_wind_guide.py. Its page is at the bottom.

local ADDON_NAME, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.windGuide = false           -- at all (its page's switch)
DEFAULTS.windGuideOnlyCine = false   -- ...only while CineMode is on
DEFAULTS.windGuideNotInFights = true -- ...and not in fights
DEFAULTS.windGuideStyle = "auto"     -- a style's key (WindGuideStyles.lua), or by class and spec
DEFAULTS.windGuideAmount = 6         -- how many start a second (more in gusts)
DEFAULTS.windGuideStrength = 0.6     -- their opacity
DEFAULTS.windGuideSize = 1           -- their size, times the style's own
DEFAULTS.windGuideSpeed = 1          -- how fast they go to the waypoint, times the style's own
DEFAULTS.windGuideGusts = true       -- coming and going in gusts, not steadily
DEFAULTS.windGuideNear = 15          -- yards from the waypoint they stop at (without the game's marker)

-- The game's waypoint marker (retail's): the wind stops when it does.
local HAS_MARKER = C_Navigation and C_Navigation.GetFrame and C_Navigation.GetTargetState and true or false
local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\WindGuide\\"
local MAX_SPRITES = 64
local EDGE_TRIES = 6     -- places round the edge tried for each sprite: more, the nearer it keeps to the target
local STRAGGLERS = 0.15  -- the share that come from anywhere round it instead
local MAX_LIFE = 12      -- seconds a sprite can last, whatever happens
local TURN_AWAY = math.cos(math.rad(50)) -- a sprite gives up once the waypoint has swung this far from where it set off toward...
local LEAVE_TIME = 0.4   -- ...and fades out over this many seconds, carrying on the way it was going
local EDGE_DEPTH = 0.6   -- how far past the edge (its sizes) a sprite starts
local NEAR_SIZE = 1.5    -- a sprite's size as it comes in, close to you (times its own)...
local FAR_SIZE = 0.5     -- ...and by a waypoint on the screen, far off
local LOOK_EVERY = 0.2   -- seconds between looks for the waypoint (and where it lies)
local FADE_TIME = 0.6    -- seconds the wind takes to fade in or out as a whole
local GUST_TIME = 7      -- seconds from one gust to the next
local HORIZON = 0.55     -- how high up the screen a waypoint ahead sits (the map's guess)
local TEST_TIME = 30     -- seconds the test blows for
local TEST_ANGLE = math.rad(-60) -- ...where it is as it starts (60 degrees to your right)

-- (The styles: WindGuideStyles.lua.)

local db, frame, driver
local sprites = {}
local shown = 0      -- the whole wind's opacity as it fades in and out (0-1)
local nextLook = 0
local test           -- the test: { ends, bearing (a pretend waypoint's, when there's no real one) }
-- Where the waypoint was last found: bearing (radians, the way GetPlayerFacing
-- counts) and distance (yards, or nil), from the map.
local bearing, distance

local function Between(range)
	return range[1] + math.random() * (range[2] - range[1])
end

-- The way you face, or nil when the client keeps it secret.
local function Facing()
	local ok, facing = pcall(GetPlayerFacing)
	if not ok or type(facing) ~= "number" or (issecretvalue and issecretvalue(facing)) then return end
	return facing
end

local function Number(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value)) and value or nil
end

-- The waypoint on a map: your map pin when you're following it (or have no
-- quest tracked), else the quest you're tracking. Gives its map and x, y.
local function Waypoint(mapID)
	local pin = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
	local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	local followingPin = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint
		and C_SuperTrack.IsSuperTrackingUserWaypoint()
	if pin and (followingPin or not questID or questID == 0) then
		return pin.uiMapID, pin.position:GetXY()
	end
	if not questID or questID == 0 then return end
	if not C_QuestLog then return end
	-- (The next stop on the way, for a quest in another zone.)
	if C_QuestLog.GetNextWaypoint then
		local wayMap, x, y = C_QuestLog.GetNextWaypoint(questID)
		if wayMap and x then return wayMap, x, y end
	end
	if C_QuestLog.GetQuestsOnMap then
		for _, quest in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
			if quest.questID == questID and quest.x then return mapID, quest.x, quest.y end
		end
	end
end

-- Where the waypoint lies from you: its bearing and distance (nil: not
-- known), from the map you're on. Map x runs east and y south.
local function LookOnMap()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return end
	local here = C_Map.GetPlayerMapPosition(mapID, "player")
	if not here then return end
	local px, py = here:GetXY()
	px, py = Number(px), Number(py)
	if not px then return end
	local wayMap, wx, wy = Waypoint(mapID)
	if not wayMap then return end
	if wayMap ~= mapID then -- (onto your map, through the world's)
		if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos) then return end
		local continent, world = C_Map.GetWorldPosFromMapPos(wayMap, CreateVector2D(wx, wy))
		if not continent then return end
		local _, onMine = C_Map.GetMapPosFromWorldPos(continent, world, mapID)
		if not onMine then return end
		wx, wy = onMine:GetXY()
	end
	local width, height = 1, 1
	if C_Map.GetMapWorldSize then
		width, height = C_Map.GetMapWorldSize(mapID)
	end
	local known = width and width > 0 and height and height > 0
	if not known then width, height = 1, 1 end
	local east, south = (wx - px) * width, (wy - py) * height
	-- (Facing counts from north, round to the west.)
	return math.atan2(-east, -south), known and math.sqrt(east * east + south * south) or nil
end

local function Look()
	if test and test.bearing then
		bearing, distance = test.bearing, nil
		return
	end
	local ok, found, yards = pcall(LookOnMap)
	if ok then bearing, distance = found, yards else bearing, distance = nil, nil end
end

-- Retail's navigation marker, where the client has one: where on the screen
-- (frame's coordinates), whether that's pinned to the screen's edge (behind
-- or off to a side), and how far.
local function Navigation()
	if (test and test.bearing) or not (C_Navigation and C_Navigation.GetFrame) then return end
	local nav = C_Navigation.GetFrame()
	if not nav then return end
	local x, y = nav:GetCenter()
	x, y = Number(x), Number(y)
	if not x then return end
	local scale = nav:GetEffectiveScale() / frame:GetEffectiveScale()
	local clamped = C_Navigation.WasClampedToScreen and C_Navigation.WasClampedToScreen()
	return x * scale, y * scale, clamped, Number(C_Navigation.GetDistance and C_Navigation.GetDistance())
end

-- Whether the game's waypoint marker is off (no waypoint, or you're there:
-- it goes by the marker's own state, as the game's marker does).
local function MarkerOff()
	local state = Number(C_Navigation.GetTargetState())
	local states = Enum and Enum.NavigationState
	return state == nil or (states and (state == states.Invalid or state == states.Disabled)) or false
end

-- Where the wind blows to (frame's coordinates, may be off the screen),
-- whether that's the waypoint on screen, and its distance; nil: nowhere.
-- With the game's marker, it stops when the marker does (the test: not).
local function Target(width, height)
	if HAS_MARKER and not test and MarkerOff() then return end
	local nx, ny, clamped, navYards = Navigation()
	if nx and not clamped then return nx, ny, true, navYards end
	local facing = Facing()
	local turn -- (the waypoint's angle from the way you face: positive to the left)
	if bearing and facing then
		turn = (bearing - facing + math.pi) % (2 * math.pi) - math.pi
	end
	if not turn then
		if not nx then return end
		-- (Pinned to the edge: blow on past it, from the middle.)
		local dx, dy = nx - width / 2, ny - height / 2
		return width / 2 + dx * 1.6, height / 2 + dy * 1.6, false, navYards
	end
	local yards = navYards or distance
	local half = math.rad((tonumber(GetCVar("cameraFov")) or 90) / 2)
	if math.abs(turn) < half * 0.95 then
		return width / 2 - math.tan(turn) / math.tan(half) * width / 2, height * HORIZON, true, yards
	end
	-- Off the screen: off the side to turn to (behind: further off, lower).
	local behind = math.abs(turn) > math.pi / 2
	local x = turn > 0 and -width * (behind and 0.6 or 0.3) or width * (behind and 1.6 or 1.3)
	return x, height * (behind and 0.35 or 0.5), false, yards
end

local function Create()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("BACKGROUND")
	frame:SetFrameLevel(0) -- (under the letterbox, like Vitals Vision)
	frame:EnableMouse(false)
	ns.AddOverlay(frame)
	for i = 1, MAX_SPRITES do
		local tex = frame:CreateTexture(nil, "BORDER")
		tex:Hide()
		sprites[i] = { tex = tex }
	end
	frame:Hide()
	-- (Its own frame, not under UIParent, so it runs with the UI hidden too.)
	driver = CreateFrame("Frame")
	driver:Hide()
end

local function Clear()
	for _, sprite in ipairs(sprites) do
		sprite.born = nil
		sprite.tex:Hide()
	end
end

-- A point just past the screen's edge (margin out), anywhere round it, and
-- the way into the screen from there.
local function EdgePoint(width, height, margin)
	local u = math.random() * 2 * (width + height)
	if u < width then return u, -margin, 0, 1 end -- (bottom)
	u = u - width
	if u < height then return width + margin, u, -1, 0 end -- (right)
	u = u - height
	if u < width then return u, height + margin, 0, -1 end -- (top)
	return -margin, u - width, 1, 0 -- (left)
end

-- A free sprite, or nil when they're all in use.
local function Free()
	for _, sprite in ipairs(sprites) do
		if not sprite.born then return sprite end
	end
end

-- Sets a sprite's picture and look up (its part's or an arrival's).
local function Dress(sprite, texName, color, add)
	local tex = sprite.tex
	tex:SetTexture(ART .. texName)
	sprite.color = color
	tex:SetVertexColor(color[1], color[2], color[3], 0)
	tex:SetBlendMode(add and "ADD" or "BLEND")
	if tex.SetRotation then tex:SetRotation(0) end
	tex:Show()
end

local function PickPart(style)
	local total = 0
	for _, part in ipairs(style.parts) do total = total + (part.weight or 1) end
	local roll = math.random() * total
	for _, part in ipairs(style.parts) do
		roll = roll - (part.weight or 1)
		if roll <= 0 then return part end
	end
	return style.parts[1]
end

-- A new sprite, blowing in from past the screen's edge toward the target.
-- A waypoint on the screen: mostly from the part of the edge nearest it (of
-- a few places tried, the nearest), now and then a straggler from anywhere.
-- One off the screen: from anywhere it would blow across the screen (toward
-- one off the right: the left edge, and the top and bottom all along), so
-- the wind sweeps over toward the side to turn to.
local function Spawn(style, width, height, tx, ty, onScreen)
	local sprite = Free()
	if not sprite then return end
	local part = PickPart(style)
	-- (Spread: most small, a few big, the higher it is.)
	local size = part.size[1] + math.random() ^ (part.spread or 1) * (part.size[2] - part.size[1])
	size = size * height * db.windGuideSize
	local straggler = not onScreen or math.random() < STRAGGLERS
	local into = onScreen and 0.25 or 0.05 -- (how squarely it has to blow onto the screen)
	local bestX, bestY, best
	for _ = 1, EDGE_TRIES do
		local x, y, inX, inY = EdgePoint(width, height, size * EDGE_DEPTH)
		local dx, dy = tx - x, ty - y
		local length = math.max(1, math.sqrt(dx * dx + dy * dy))
		if (dx * inX + dy * inY) / length > into and (not best or (not straggler and length < best)) then
			bestX, bestY, best = x, y, length
		end
	end
	if not best then return end
	sprite.x, sprite.y = bestX, bestY
	sprite.from = best -- (how far it has to go, for its depth)
	sprite.entered = false
	sprite.part, sprite.kind = part, part.motion or "blow"
	sprite.born = GetTime()
	sprite.size = size
	sprite.speed = part.speed * height * db.windGuideSpeed * (0.8 + math.random() * 0.4)
	-- (A waypoint on the screen: some fade out short of it.)
	sprite.life = sprite.from / sprite.speed * (0.65 + math.random() * 0.45)
	sprite.phase = math.random() * 2 * math.pi
	sprite.spin = part.spin and Between(part.spin) * (math.random() < 0.5 and -1 or 1) or nil
	sprite.angle = math.random() * 2 * math.pi
	sprite.flick, sprite.jitter, sprite.bright = 0, 0, 1
	-- (The way it set off: if you turn and the waypoint swings well away from
	-- that, it fades out rather than wheel round after it.)
	sprite.aimX, sprite.aimY = (tx - bestX) / best, (ty - bestY) / best
	sprite.headX, sprite.headY = sprite.aimX, sprite.aimY
	sprite.leaving = nil
	Dress(sprite, part.tex[math.random(#part.tex)], part.colors[math.random(#part.colors)], part.add)
end

-- The style's mark where the waypoint is on the screen (it follows it there).
local function Arrive(info, now)
	local sprite = Free()
	if not sprite then return end
	sprite.part, sprite.kind = info, "arrive"
	sprite.born, sprite.life = now, info.every * 1.6
	Dress(sprite, info.tex, info.color, info.add)
end

-- An arrival's size (times its own) and opacity, by how far through its life.
local function ArrivalLook(kind, age)
	if kind == "ripple" then return 0.5 + 1.1 * age, 1 - age end
	if kind == "pop" then -- (swells, then bursts: bigger and gone)
		if age < 0.85 then return 0.6 + 0.5 * age / 0.85, math.min(1, age * 6) end
		return 1.1 + (age - 0.85) / 0.15 * 0.5, (1 - age) / 0.15
	end
	return 1, math.sin(math.pi * age) -- (glow)
end

-- Moves each sprite on toward the target, weaving. Each comes in big, close
-- to you, and shrinks into the distance toward a waypoint on the screen,
-- fading out near the end of its way; toward one off the screen it blows
-- on out that side. Its part's motion on top (drifting up or down,
-- twinkling, crackling, pulled in); an arrival stays on the waypoint. Turn
-- so the waypoint swings well away from where one set off toward, and it
-- fades out on its way instead of wheeling round after it.
local function Move(now, elapsed, tx, ty, onScreen, width, height, strength)
	for _, sprite in ipairs(sprites) do
		if sprite.born then
			local part, kind, tex = sprite.part, sprite.kind, sprite.tex
			local age = (now - sprite.born) / sprite.life
			local color = sprite.color
			if kind == "arrive" then
				if age >= 1 or not onScreen then
					sprite.born = nil
					tex:Hide()
				else
					local scale, alpha = ArrivalLook(part.kind, age)
					tex:SetVertexColor(color[1], color[2], color[3], alpha * (part.alpha or 0.9) * strength)
					tex:SetSize(part.size * height * scale, part.size * height * scale)
					tex:ClearAllPoints()
					tex:SetPoint("CENTER", frame, "BOTTOMLEFT", tx, ty)
				end
			else
				local dx, dy = tx - sprite.x, ty - sprite.y
				local length = math.sqrt(dx * dx + dy * dy)
				local margin = sprite.size * EDGE_DEPTH
				local inside = sprite.x > -margin and sprite.x < width + margin
					and sprite.y > -margin and sprite.y < height + margin
				if inside then sprite.entered = true end
				if (onScreen and (age >= 1 or length < height * 0.03)) or (sprite.entered and not inside)
					or now - sprite.born > MAX_LIFE or (sprite.leaving and now - sprite.leaving >= LEAVE_TIME) then
					sprite.born = nil
					tex:Hide()
				else
					local closer = math.max(0, 1 - length / sprite.from) -- (how far along its way)
					local speed = sprite.speed
					if kind == "pull" then speed = speed * (1 + 2 * closer) end
					dx, dy = dx / math.max(length, 1), dy / math.max(length, 1)
					if not sprite.leaving and dx * sprite.aimX + dy * sprite.aimY < TURN_AWAY then
						sprite.leaving = now
					end
					if sprite.leaving then
						dx, dy = sprite.headX, sprite.headY
					else
						sprite.headX, sprite.headY = dx, dy
					end
					local weave = math.sin(sprite.phase + (now - sprite.born) * part.sway[2] * 2 * math.pi)
						* part.sway[1]
					local vx, vy = (dx - dy * weave) * speed, (dy + dx * weave) * speed
					if part.drift then vy = vy + part.drift * height end
					sprite.x, sprite.y = sprite.x + vx * elapsed, sprite.y + vy * elapsed
					local alpha = math.min(1, (now - sprite.born) / 0.25) * part.alpha * strength
					local depth = 1
					if onScreen then
						alpha = alpha * math.min(1, (1 - age) * 3.5) * math.min(1, length / (height * 0.08))
						depth = NEAR_SIZE + (FAR_SIZE - NEAR_SIZE) * closer
					end
					if kind == "pull" then depth = depth * (1 - 0.7 * closer) end
					if sprite.leaving then alpha = alpha * (1 - (now - sprite.leaving) / LEAVE_TIME) end
					if part.twinkle then
						alpha = alpha * (0.6 + 0.4 * math.sin(sprite.phase * 3 + now * part.twinkle * 2 * math.pi))
					end
					if kind == "crackle" then
						-- (A new jagged shape, angle and brightness every few hundredths of a second.)
						if now >= sprite.flick then
							sprite.flick = now + 0.03 + math.random() * 0.05
							tex:SetTexture(ART .. part.tex[math.random(#part.tex)])
							sprite.jitter = (math.random() - 0.5) * 0.8
							sprite.bright = 0.45 + math.random() * 0.55
						end
						alpha = alpha * sprite.bright
					end
					tex:SetVertexColor(color[1], color[2], color[3], alpha)
					tex:SetSize(sprite.size * depth, sprite.size * depth)
					tex:ClearAllPoints()
					tex:SetPoint("CENTER", frame, "BOTTOMLEFT", sprite.x, sprite.y)
					if tex.SetRotation and not part.still then
						if sprite.spin then
							sprite.angle = sprite.angle + sprite.spin * elapsed
							tex:SetRotation(sprite.angle)
						else
							tex:SetRotation(math.atan2(vy, vx) + sprite.jitter) -- (its head leads)
						end
					end
				end
			end
		end
	end
end

-- The style blowing now: the page's, or Auto's (Vitals Vision's theme for
-- your class and spec), else plain wind.
local function StyleKey()
	local key = (ns.GetDB() or DEFAULTS).windGuideStyle -- (the page asks before the settings load)
	if key == "auto" and ns.LowHealthAutoTheme then key = ns.LowHealthAutoTheme() end
	return ns.WIND_GUIDE_STYLES[key] and key or "streaks"
end
local function CurrentStyle()
	local style = ns.WIND_GUIDE_STYLES[StyleKey()]
	if style.byClass then -- (motes or wisps in your class and spec's colours)
		return ns.WindGuideByClass(style.byClass, ns.LowHealthAutoTheme and ns.LowHealthAutoTheme() or "")
	end
	return style
end

local spawnDebt = 0 -- (sprites owed: the rate times the time, a fraction at a time)
local nextArrival = 0

-- Whether the wind should blow now (the test: whatever the page says).
local function Wanted(now)
	if test then
		if now >= test.ends then
			test = nil
			ns.Print(L["Wind Guide test done."])
		else
			return true
		end
	end
	if not db.windGuide or (db.windGuideOnlyCine and not ns.lastCinematic) then return false end
	if db.windGuideNotInFights and (InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))) then
		return false
	end
	return not (ns.Flag(ns.OnTaxi()) or ns.Flag(UnitIsDeadOrGhost("player")))
end

local function Update(_, elapsed)
	local now = GetTime()
	local wanted = Wanted(now)
	if wanted and now >= nextLook then
		nextLook = now + LOOK_EVERY
		Look()
	end
	local width, height = frame:GetWidth(), frame:GetHeight()
	local tx, ty, onScreen, yards
	if wanted then
		tx, ty, onScreen, yards = Target(width, height)
		-- (Close enough: there.)
		if tx and yards and not test and not HAS_MARKER and yards < db.windGuideNear then tx = nil end
	end
	local target = tx ~= nil
	shown = math.max(0, math.min(1, shown + (target and elapsed or -elapsed) / FADE_TIME))
	if shown <= 0 and not target then
		Clear()
		frame:Hide()
		-- (Kept running while the page is on: it watches for when to blow.)
		if not (test or db.windGuide) then driver:Hide() end
		return
	end
	frame:Show()
	if not target then -- (fading out: they finish their way where they were going)
		tx, ty, onScreen = frame.lastX or width / 2, frame.lastY or height, frame.lastOnScreen
	end
	frame.lastX, frame.lastY, frame.lastOnScreen = tx, ty, onScreen
	local style = CurrentStyle()
	if target then
		local rate = db.windGuideAmount
		if db.windGuideGusts then
			local swell = 0.5 + 0.5 * math.sin(now / (style.gust or GUST_TIME) * 2 * math.pi)
			rate = rate * ((style.calm or 0.15) + 1.5 * swell * swell)
		end
		if style.arrive and onScreen and now >= nextArrival then
			nextArrival = now + style.arrive.every
			Arrive(style.arrive, now)
		end
		spawnDebt = spawnDebt + rate * elapsed
		while spawnDebt >= 1 do
			spawnDebt = spawnDebt - 1
			Spawn(style, width, height, tx, ty, onScreen)
		end
	else
		spawnDebt = 0
	end
	local strength = db.windGuideStrength * shown
	if style.pulse then -- (a heartbeat: a throb, then a rest)
		local beat = math.max(0, math.sin(now * style.pulse / 60 * 2 * math.pi))
		strength = strength * (0.55 + 0.45 * beat ^ 4)
	end
	Move(now, elapsed, tx, ty, onScreen, width, height, strength)
end

-- Starts it running when it may have something to show (it stops itself).
local function Wake()
	if not driver then return end
	if test or db.windGuide then driver:Show() end
end
ns.RefreshWindGuide = Wake

-- The test, for TEST_TIME seconds: to your waypoint if you have one (however
-- near, and whatever the page says), else to a pretend one off to your right,
-- where it is as it starts (turn to it and the wind follows).
function ns.TestWindGuide()
	local ok, found = pcall(LookOnMap)
	if (ok and found) or Navigation() then
		test = { ends = GetTime() + TEST_TIME }
		ns.Print(L["Wind Guide test: blowing toward your waypoint."])
	else
		local facing = Facing()
		if not facing then
			ns.Print(L["Wind Guide can't tell which way you face here."])
			return
		end
		test = { bearing = facing + TEST_ANGLE, ends = GetTime() + TEST_TIME }
		ns.Print(L["Wind Guide test: no waypoint, so a pretend one off to your right."])
	end
	nextLook = 0
	Wake()
end

function ns.StopWindGuideTest()
	test = nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		db = ns.GetDB()
		Create()
		driver:SetScript("OnUpdate", Update)
		for _, other in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
			"SUPER_TRACKING_CHANGED", "USER_WAYPOINT_UPDATED", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
			pcall(events.RegisterEvent, events, other)
		end
	end
	nextLook = 0
	Wake()
end)

-- The Wind Guide page (in the Visions hub, marked a work in progress): its
-- switch, the style and a test, when it blows, and how it looks. Options.lua
-- calls it with the page helpers it shares.
function ns.CreateWindGuidePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Wind Guide"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["A breeze that shows you the way: wind blows across the screen toward your waypoint (your map " ..
		"pin, or the quest you're tracking), in gusts. When it's off the screen, the wind sweeps off the " ..
		"side to turn to. It goes by the way you face, so it's off while you swing the camera round on its " ..
		"own (on retail it follows the game's waypoint marker exactly). A demo for now."])
	local function Changed()
		ns.RefreshWindGuide()
	end
	local switch = kit.PageSwitch(content, "windGuide", L["Enable page"],
		L["On: everything below works as ticked. Off: none of it does, and each keeps its tick for " ..
		"when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local function Tick(key, label, tip)
		return stack:Add(kit.Check(content, key, label, tip, function(value)
			ns.GetDB()[key] = value
			Changed()
			kit.Refresh()
		end), "check")
	end
	local function Slide(key, label, minV, maxV, step, fmt, scale, tip)
		local slider = stack:Add(kit.Slider(content, key, label, minV, maxV, step, fmt, scale, Changed), "slider")
		if tip then kit.Tooltip(slider, tip) end
		return slider
	end
	local function Button(parent, text, width, tip, onClick)
		local button = ns.PanelButton(parent)
		button:SetSize(width, 22)
		button:SetText(text)
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", onClick)
		return button
	end
	local TEST_TIP = L["Blows toward your waypoint for 30 seconds (or, with none, a pretend one off to your " ..
		"right: turn toward it and the wind follows). It works with the page off too. Close the settings " ..
		"to see it."]

	-- The style: Auto (and what it picks for you), the plain ones, or any
	-- class and spec's (like Vitals Vision's theme picker). A test beside it.
	local function StyleName(key)
		local style = ns.WIND_GUIDE_STYLES[key]
		return style and L[style.name] or key
	end
	local function AutoText()
		return L["Auto"] .. ": " .. StyleName(StyleKey())
	end
	local function Choices() -- (flat: the button that steps through them)
		local list, seen = { { value = "auto", text = AutoText() } }, {}
		for _, key in ipairs(ns.WIND_GUIDE_PLAIN) do
			list[#list + 1] = { value = key, text = StyleName(key) }
			seen[key] = true
		end
		for _, info in ipairs(ns.LOW_HEALTH_THEMES or {}) do
			if ns.WIND_GUIDE_STYLES[info.key] and not seen[info.key] then
				list[#list + 1] = { value = info.key, text = StyleName(info.key) }
			end
		end
		return list
	end
	local styleRow = CreateFrame("Frame", nil, content)
	styleRow:SetSize(560, 26)
	stack:Add(styleRow, "label", 2)
	local styleLabel = kit.Label(styleRow, "GameFontHighlight", L["Style:"])
	styleLabel:SetPoint("LEFT")
	local STYLE_TIP = L["What blows: Auto picks your class and spec's (the same as Vitals Vision's theme), " ..
		"or pick any, or plain wind or motes of light."]
	local picker = kit.Dropdown and kit.Dropdown(styleRow, "windGuideStyle", Choices, 260, Changed)
	if picker then
		kit.Tooltip(picker, STYLE_TIP)
		-- Auto and the plain ones, then a submenu for each class (in its
		-- colour), each spec in it with its style. (Replaces the flat list
		-- the helper made.)
		local RETAIL = " |cff999999(" .. L["retail"] .. ")|r"
		local function Pick(key)
			ns.GetDB().windGuideStyle = key
			Changed()
			kit.Refresh()
		end
		local function Picked(key)
			local d = ns.GetDB()
			return d ~= nil and d.windGuideStyle == key
		end
		local function ClassName(class)
			local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class[1]] or L[class[2]]
			local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class[1]]
			if color then
				name = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name)
			end
			return name .. (class.retail and RETAIL or "")
		end
		picker:SetupMenu(function(_, root)
			root:CreateRadio(AutoText(), function() return Picked("auto") end, function() Pick("auto") end)
			for _, key in ipairs(ns.WIND_GUIDE_PLAIN) do
				root:CreateRadio(StyleName(key), function() return Picked(key) end, function() Pick(key) end)
			end
			root:CreateDivider()
			for _, class in ipairs(ns.LOW_HEALTH_MENU or {}) do
				local menu = root:CreateButton(ClassName(class))
				for _, spec in ipairs(class[3]) do
					local key = spec[2]
					menu:CreateRadio(L[spec[1]] .. ": " .. StyleName(key) .. (spec.retail and RETAIL or ""),
						function() return Picked(key) end, function() Pick(key) end)
				end
			end
		end)
	else
		-- (No dropdowns on this client: a button that steps through them.)
		picker = Button(styleRow, "", 220, STYLE_TIP, function(self)
			local list = Choices()
			local d = ns.GetDB()
			local following = list[1].value
			for i, choice in ipairs(list) do
				if choice.value == d.windGuideStyle then
					following = list[i % #list + 1].value
					break
				end
			end
			d.windGuideStyle = following
			Changed()
			self:Refresh()
		end)
		picker.Refresh = function(self)
			local key = ns.GetDB().windGuideStyle
			self:SetText(key == "auto" and AutoText() or StyleName(key))
		end
		kit.AddControl(picker)
	end
	picker:SetPoint("LEFT", styleLabel, "RIGHT", 8, 0)
	-- (Not page controls: they work with the page off.)
	local testButton = Button(styleRow, L["Test"], 80, TEST_TIP, ns.TestWindGuide)
	testButton:SetPoint("LEFT", picker, "RIGHT", 10, 0)
	local stopButton = Button(styleRow, L["Stop"], 80, nil, ns.StopWindGuideTest)
	stopButton:SetPoint("LEFT", testButton, "RIGHT", 8, 0)
	stack:Continue(styleRow, "label")

	stack:Header(content, L["When it blows"])
	Tick("windGuideOnlyCine", L["Only in CineMode"], L["Ticked, only while the UI is faded."])
	Tick("windGuideNotInFights", L["Not in fights"], L["Ticked, the wind drops while you're in a fight."])
	-- (With the game's waypoint marker the wind stops when it does: no slider.)
	if not HAS_MARKER then
		Slide("windGuideNear", L["Stops within"], 0, 100, 5, L["%d yards"], 1,
			L["How close to the waypoint the wind stops (you're there)."])
	end

	stack:Header(content, L["Look"])
	Slide("windGuideAmount", L["Amount"], 1, 20, 1, L["%d a second"], 1,
		L["How many streaks (or leaves, or motes) start each second."])
	Tick("windGuideGusts", L["In gusts"],
		L["Ticked, the wind comes and goes in gusts every few seconds. Unticked, it blows steadily."])
	Slide("windGuideStrength", L["Opacity"], 10, 100, 5, "%d%%", 100)
	Slide("windGuideSize", L["Size"], 50, 200, 10, "%d%%", 100)
	Slide("windGuideSpeed", L["Speed"], 25, 300, 5, "%d%%", 100,
		L["How fast they travel to the waypoint, next to the style's own speed."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Wind Guide")
end
