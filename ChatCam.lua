-- Chat Cam (a prototype, in the dev copy only: CinematicDev.toc): as NPCs
-- talk, the camera zooms in (as the quest cam does), swings toward whoever's
-- talking, drifts slowly to and fro while they go on, and swings again only
-- when someone else speaks. Once it's over, it turns back and zooms back out.
--
-- The game gives no NPC's place in the world (and retail won't measure
-- nameplates), only where its chat bubble is drawn. A bubble's offset from
-- the screen's middle, through the camera's field of view, is an angle off
-- the view; the swing leaves them chatCamFrame degrees off it, on their side (see
-- the gain, below), at most MAX_TURN from where the camera started, no more
-- than TURN_BUDGET in a few seconds, and no faster than chatCamSwingSpeed
-- (every move held to its top speed: see TopSpeed). If one swing leaves them
-- well off, one more follows. A speaker it's on who walks off the framing
-- while talking is kept up with by a steady turn (see TRACK_CATCH).
-- It's measured while the camera's still or only drifting (mid-swing, the
-- bubble's place is already out of date); a swing alongside the zoom in goes
-- SIDE_TURN at most, and how far it moved them isn't learnt from. More
-- lines from the one the
-- camera's on don't move it: the drift keeps the shot alive. A speaker with
-- no bubble on screen is looked round for (chatCamSearch: see SEARCH_SPEED),
-- or leaves the camera on whoever it was on.
--
-- The turns are sent as the quest cam sends its own (see
-- SPEED_MIN_SETTING), along eased curves; a drift leg going a new speaker's
-- way turns into the swing, one going the other way eases out first. The
-- amount turned is counted, as the camera's angle can't be read, and undone
-- by as much (/cine chatcam flip swaps the two directions, should the
-- tested way ever turn out wrong elsewhere). The zoom is the quest cam's
-- own (ns.QuestCamZoomTo), at Chat Cam's own distance and speeds (its
-- section on the Camera Settings page, chatCam*), as is the drift's width.
--
-- The conversation ends after chatCamQuiet seconds with no line, or a fight:
-- the camera turns back and zooms back out. Moving (walking, even mid-turn
-- or on the way back), moving or zooming the camera yourself, or another
-- camera taking over (the quest cam, a camera mode) hands it over at once:
-- a turn under way stops quickly, nothing's undone, and no line starts it
-- again while you're moving (a camera moving as you do felt awkward).
-- /cine chatcam to switch it on or off. What it does is printed to chat
-- (and so the log), prefixed "chat cam"; /cine chatcam log saves
-- every frame of the next conversations too.
local _, ns = ...

local EVENTS = { "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY" }
-- The camera turns round you, not on the spot, so a speaker near you moves
-- across the screen much less than the camera turns (tested: about a third
-- of a degree per degree, standing beside Liadrin and Zul'jarra). The swing
-- divides by that (the gain), learnt afresh from each swing's result.
local GAIN_START = 0.35 -- degrees the speaker moves on screen per degree turned, until a swing's measured
local GAIN_MIN, GAIN_MAX = 0.15, 1
local CORRECT = 6      -- degrees still off past the framing (chatCamFrame) after a swing: one more swing
local MAX_TURN = 30    -- degrees from where the camera started, at most (45 swung the view
                       -- right off Liadrin and Zul'jarra, standing side by side)
local MAX_SWING = 30   -- degrees one swing goes, at most (the test's first layout swung 84 and 98:
                       -- the view whipped right round)
local MIN_TURN = 2     -- degrees: a smaller swing isn't worth a move
-- Keeping up: the one it's on walking off the framing (chatCamFrame) while
-- talking. Swinging after them once they were 10 degrees past it, then
-- resting 3 seconds, left them running off while it looked elsewhere. Now
-- one turn their way, its speed set at each look (AIM_EVERY) to make up how
-- far they're past the framing in TRACK_CATCH seconds (no faster than
-- chatCamSwingSpeed, speeding up and slowing down no harder than
-- MAX_ACCEL), easing to a stop once they're back in it or their bubble's gone.
local TRACK_START = 2  -- degrees past the framing before it starts after them
local TRACK_CATCH = 1  -- seconds the turn's speed makes up the gap in (walking on, they stay about their speed times this past it)
local TRACK_MAX = 90   -- degrees from where the camera started it follows them to, at most
-- Where a swing leaves them (short of the framing by less than CORRECT, as
-- the gain's a guess) is the framing for keeping up, till the next swing:
-- counting from chatCamFrame, every swing ended in a dead stop, then a
-- moment still, then a turn from rest after someone standing still.
-- The turn's speed then eases toward each look's (TRACK_EASE, speeding up
-- harder no quicker than TRACK_JERK), rather than straight at MAX_ACCEL: the
-- looks jump about, and each one jolted it.
local TRACK_EASE = 0.6 -- seconds the speed takes to close most of the gap to the speed wanted
local TRACK_JERK = 15  -- degrees/sec per second, per second: how fast its speeding up can change
local TRACK_STILL = 0.2 -- degrees/sec: slower than this with none wanted, it's stopped
local HITCH = 0.05     -- seconds: a frame longer than this while turning is logged (a hitch on screen whatever we do)
-- Swings share a budget: TURN_BUDGET degrees in any TURN_WINDOW seconds, a
-- swing past it cut to what's left (or held, under MIN_TURN). Two speakers
-- too far apart to frame together got a full 30-degree swing each way at
-- every line, one every 5 to 8 seconds, and it felt jumpy. 30 made two
-- speakers 21 degrees apart (Arator, Decimus, Lothraxion) wait 3 to 5
-- seconds at every other line, and turning felt late: 45 lets two such
-- swings through, a third still waits.
local TURN_BUDGET = 45
local TURN_WINDOW = 10
-- Up close, the game moves a bubble's box off its speaker's head (its middle
-- once read x -0.38 for Zul'jarra standing at -0.05, and each swing went 45
-- degrees for two speakers 8 apart). Its tail says where they are (tested,
-- /cine chatcam debug's log of Liadrin and Zul'jarra and three screenshots):
-- it's only ever in one of two places. At the box's bottom middle (8 units
-- off), right over their head (within 26 units of where Liadrin stood),
-- whether the box touches the screen's top or not. Or pinned to one end of
-- a box moved beside their head (theirs reaching the screen's top: 16 to 72
-- units below it), the end toward them, and they stand past it, by how much
-- isn't fixed: the box goes either side of them (at the same turn, once to
-- their right, once to their left, the two tails 160 apart with her
-- between). Zul'jarra stood 85, 92, 120 and 125 past it (a video matched to
-- the log, and screenshots). Only one bubble ever showed at a time.
local TAIL_MIDDLE = 40     -- units (WorldFrame's: the screen's 768 high) off the box's middle: over their head
local PINNED_BEYOND = 100  -- ...and about how far past a pinned tail they stand
-- A tail over their head, the only bubble showing, well off the middle
-- (past chatCamFrame), is aimed by. Otherwise, once two have talked, each
-- speaker has a spot by their order, left to right, spread evenly from this
-- far left of where the camera started to this far right (two: either end;
-- three: the ends and the middle): in view or not (Liadrin and Zul'jarra a
-- few degrees either side of the middle both read in view, and the camera
-- never turned between them). A pinned tail's guess, or a bubble with no
-- tail to read, places them well enough for that order; placed by their
-- first good bubble if there's been one (placed again from guesses, the
-- order once flipped and a line got no swing).
local SIDE_TURN = 12
local TOP_EDGE = 0.85  -- with no tail to read: a bubble's middle this high (-1 to 1) is on the top edge
local LOG_MAX = 20000  -- frames kept by /cine chatcam log (a few minutes)
local SWING_MIN_TIME = 1.5 -- seconds: the shortest swing
-- Swings and the turn back go as the fly-by's turns do (Camera.lua): one
-- smooth swell from rest to rest, speeding up no harder than MAX_ACCEL. (With
-- a flat top speed reached in about a second, a swing sped up some 24
-- degrees/sec per second, and every one hitched as it started.)
local SWING_EASE = 0.5 -- share of a swing spent speeding up (and again slowing down): one swell
local BACK_EASE = 0.5  -- ...of the turn back
local MAX_ACCEL = 9    -- degrees/sec per second at most (the fly-by's: the sways' most)
-- /cine chatcam steady (a comparison, for the spike): swings and the turn
-- back go at chatCamSwingSpeed from start to finish, the speed setting left at
-- yours, instead of easing up and down. (A video of the eased swing showed
-- the camera overshooting its speed for half a second as it reached full
-- speed, though the setting rose smoothly.)
local function Ease(ease)
	return ns.db.chatCamSteady and 0 or ease
end
local BACK_MIN_TIME = 3 -- seconds the turn back takes, at least
local DRIFT_TIME = 7   -- seconds a leg of the drift across its whole width takes (as the quest cam's)
local DRIFT_EASE = 0.3
local DRIFT_GAP = 0.35 -- seconds between legs
local STOP_TIME = 0.8  -- seconds a move under way takes to ease to a stop for a new swing
-- Every move is sent as the quest cam and fly-bys send theirs (QuestCam.lua's
-- MoveTo): one MoveView*Start for the whole move, at the share of your turn
-- speed setting that makes your setting its top speed, then only the setting
-- stepped along the curve (from SPEED_MIN_SETTING up toward yours and back),
-- yours put back SPEED_RESTORE_DELAY after it stops. (Re-sending the move at
-- each new speed instead, your setting untouched, as the camera modes' sways
-- do: these slow swings sent shares of 0.001 to 0.04 of a setting of 180,
-- and a video showed their speed climbing in visible stairs, as the game
-- handles slow speeds coarsely; see the quest cam's own note on it.) A drift
-- leg going a new swing's way turns into it with one re-send, at the new
-- share. (Once, stepping the setting, every swing straight after a drift leg
-- jumped about a degree as it started; with the drift at 0, its default,
-- that can't happen.)
-- A move from rest starts creeping as the lowest setting goes in (at
-- PRIME_SHARE, too slow to see), the move itself sent over it once primed.
-- (Two videos, matched frame by frame to the debug log: every swing's first
-- frame jumped 2-3 pixels its way, about a frame at full speed, then the
-- camera all but stopped for 0.2 seconds before following the curve, which
-- read as a lurch at each start. A move already under way takes the new
-- share without a jump: the drift carry does it.)
local SPEED_MIN_SETTING = 1 -- the lowest speed setting sent (lower, the game uses its full speed)
local SPEED_CHANGE = 0.02   -- setting changes smaller than this share aren't sent
local SPEED_PRIME_TIME = 0.2 -- seconds the lowest setting is in before the move starts
local PRIME_SHARE = 0.001   -- the creep's share of the setting (even at your 180: 0.18 deg/sec)
local SPEED_RESTORE_DELAY = 0.3 -- seconds after a move stops before your setting comes back
local TALKED_WINDOW = 30 -- seconds after a gossip or quest window closes its NPC's lines still start it at once
local BUBBLE_WAIT = 2  -- seconds after a line its bubble is waited for before saying there's none
-- A speaker with no bubble on screen by then (behind you, say): with
-- chatCamSearch on, the camera wraps round, a full turn at most, toward the
-- side their bubble's drawn off screen if it is, or where they were placed
-- before, until their bubble shows (then the usual swing frames them). Once
-- per speaker a conversation: found nowhere (a yell from afar, say), it's
-- back where it started, and their later lines don't search again.
local SEARCH_SPEED = 30 -- degrees a second the look round goes at most (45 felt like a whip)
local SEARCH_ACCEL = 30 -- ...speeding up and slowing down no harder than this (degrees/sec per second)
local AIM_EVERY = 0.25 -- seconds between looks for a new speaker's bubble
local LET_GO_TIME = 0.3 -- seconds a move under way takes to stop as you move off (quick: it's yours)
local ZOOM_MARGIN = 0.5 -- yards: already about this close, so no zoom in
local ZOOM_EDGE = 0.7   -- the zoom in eases to a stop once the speaker's bubble middle is this near an edge (-1 to 1)
local ZOOM_STOP_TIME = 0.8 -- ...over this many seconds
local ZOOM_YOURS = 1.5  -- yards from where it zoomed to: you've zoomed yourself, so no zoom back out
local CVAR = "cameraYawMoveSpeed"
local WHO = "chatcam" -- (its hold on your turn speed: ns.HoldSpeed, Core.lua)

local FOLLOW_CVARS = { values = { cameraSmoothStyle = "0" } } -- (camera follow would pull the view back)

-- amount: degrees turned, counted (positive: toward the right of the screen).
-- kind: "swing", "drift", "track" or "back". stopping: easing to a stop early.
-- want: a track's speed wanted (degrees/sec; it has no end of its own).
-- sent: the speed sent (degrees/sec), right: which way. share: the move's
-- share of your speed setting, setting: the speed setting sent, speed: the
-- curve's speed now, primedUntil: when the move starts.
local turn = { amount = 0, moving = false, stoppedAt = 0, primedUntil = 0 }
-- The conversation going on: { startedAt, lastLineAt, nextAimAt, turnedAt, on (who
-- the camera's on), center (the drift's middle), driftOut, zoom (your
-- distance), zoomedTo, base (where turns are counted from: 0, or where a
-- look round found someone), search, searched, speaker = { name, text, at, missing } }
local convo
local leaving -- once it's over: { zoom, zoomedTo, startedAt } until the turn back starts
local zoomingOut -- the distance the zoom back out is heading for

local watcher = CreateFrame("Frame")

-- The Cameras page's rows (each "chat" or "none"): "NPCs you talk
-- to" (chatCamera) and "NPCs chatting nearby" (chatNearbyCamera, once you've
-- stood still chatNearbyDelay seconds: see Ambient).
ns.DEFAULTS.chatCamera = "chat"
ns.DEFAULTS.chatNearbyCamera = "chat"
ns.DEFAULTS.chatNearbyDelay = 10
-- Its section on the Camera Settings page.
ns.DEFAULTS.chatCamDistance = 4      -- yards it zooms in to (if you're further out)
ns.DEFAULTS.chatCamZoomSpeed = 0.5   -- yards a second the zoom in goes
ns.DEFAULTS.chatCamZoomOutSpeed = 0.5 -- ...and the zoom back out (0: stays in)
ns.DEFAULTS.chatCamZoomMaxTime = 8   -- seconds either zoom takes at most (from far out: quicker than its speed)
ns.DEFAULTS.chatCamSwingSpeed = 15   -- degrees a second a swing goes at most
ns.DEFAULTS.chatCamFrame = 6         -- degrees off the middle a speaker's left at, on their side
ns.DEFAULTS.chatCamDrift = 0         -- degrees it drifts to and fro on a speaker (0: holds still)
ns.DEFAULTS.chatCamQuiet = 20       -- seconds with no one talking before it's over
ns.DEFAULTS.chatCamSearch = true    -- a speaker off screen: the camera looks round for them (see SEARCH_SPEED)
-- A row on the Cameras page's grid (Turn off in, Calm Timer) and a box in
-- the Minimap page's "Hide in camera modes", as key "chatcam" (the Chat page's
-- own settings start with "chat"). Added here, so after Core.lua made the
-- other cameras' defaults: its own follow (no camera in battlegrounds and
-- arenas, waits out the Calm Timer as the quest camera does, minimap left up).
table.insert(ns.CAMERA_OFF_CAMS, { "chatcam", ns.L["Chat"] })
for _, where in ipairs(ns.CAMERA_OFF_WHERE) do
	ns.DEFAULTS["chatcamOffIn" .. where] = where == "BGs"
end
ns.DEFAULTS.chatcamCalmWait = true
ns.DEFAULTS.chatcamHideMinimap = false
local function On()
	return ns.db.enabled and (ns.db.chatCamera == "chat" or ns.db.chatNearbyCamera == "chat")
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- Tested (the Liadrin scene): MoveViewLeft brings what's on the right of the
-- screen toward the middle.
local function Command(right)
	if ns.db.chatCamSwap then
		right = not right
	end
	return right and "MoveViewLeft" or "MoveViewRight"
end

-- /cine chatcam log: every frame while it's at work, saved
-- (ns.db.chatCamLog) for reading after a /reload, with camera commands
-- that weren't ours (others) and what we did (notes) since the last frame.
local frameLog = { sending = false }
local function Note(text)
	if frameLog.lines then
		frameLog.notes = frameLog.notes or {}
		if #frameLog.notes < 8 then
			frameLog.notes[#frameLog.notes + 1] = text
		end
	end
end

-- The debug log (/cine chatcam debug to switch it off): as much as can be
-- read about every bubble, the nameplates and the camera through each
-- conversation, saved (ns.db.chatCamDebug) for reading after a /reload, so
-- one run answers as much as it can (setting up a scene to test takes a
-- while). Whether bubbles are pushed to the screen's edges, where their
-- tails are, whether two showing at once push each other apart, whether the
-- frame GetAllChatBubbles gives sits where the drawn bubble does. Started
-- afresh at the first line after each login or /reload; each line's GetTime,
-- with the clock time once a second, to match a video.
local DEBUG_MAX = 40000
local DEBUG_EVERY = 0.25 -- seconds between readings of the bubbles and camera
local DEBUG_PLATES_EVERY = 1 -- ...and of the nameplates
local DEBUG_FULL_EVERY = 2 -- seconds between full dumps of a bubble still showing
local debugLog = { started = false, ids = setmetatable({}, { __mode = "k" }), nextId = 0, fullAt = {},
	nextAt = 0, platesAt = 0 }
local function DebugAdd(text)
	local lines = ns.db and ns.db.chatCamDebug
	if debugLog.started and lines and #lines < DEBUG_MAX then
		lines[#lines + 1] = ("%.2f %s"):format(GetTime(), text)
	end
end

-- What it does, to the log (a chat tab named Cinematic shows it live:
-- Diagnostics.lua), with the seconds since the conversation started: the
-- frame log's own time, which also notes it. toChat: printed too (the
-- /cine chatcam commands' answers).
local function Say(text, toChat)
	if convo then
		text = ("[%.1fs] %s"):format(GetTime() - convo.startedAt, text)
	end
	Note(text)
	DebugAdd("SAY " .. text)
	if toChat then
		ns.Print("Chat Cam: " .. text)
	else
		ns.Log("chatcam", text)
	end
end

local function Send(name, amount)
	frameLog.sending = true
	ns.CameraCall("chatcam", name, amount)
	frameLog.sending = false
	Note(amount and ("%s(%.4f)"):format(name, amount) or name)
end

local function StopMove()
	if not turn.moving then
		return
	end
	if turn.sent or turn.creeping then
		if turn.sent and turn.sent > 1 then
			-- (Cut off at speed: a jolt on screen.)
			Say(("%s stopped dead at %.1f deg/sec"):format(turn.kind or "move", turn.sent))
		end
		Send(Command(turn.right) .. "Stop")
	end
	turn.moving, turn.sent, turn.creeping, turn.stopping, turn.stoppedAt = false, nil, nil, nil, GetTime()
	-- (Your setting back a moment later, so the end of the move can't run at
	-- full speed; not if a new move has started.
	-- Held till then: see the camera lock.)
	turn.restoring = (turn.restoring or 0) + 1
	C_Timer.After(SPEED_RESTORE_DELAY, function()
		turn.restoring = turn.restoring - 1
		if not turn.moving then
			ns.ReleaseSpeed(WHO, CVAR)
		end
	end)
end

local function SendSetting(setting)
	ns.SetHeldSpeed(WHO, CVAR, setting)
	turn.setting = setting
end

-- The speed now (degrees/sec): the move goes out once, at its share; after
-- that only your speed setting changes, when it's changed enough (see
-- SPEED_MIN_SETTING).
local function Push(speed)
	local setting = math.max(SPEED_MIN_SETTING, speed / turn.share)
	if not turn.sent then
		Send(Command(turn.right) .. "Start", turn.share)
	elseif math.abs(setting - turn.setting) > turn.setting * SPEED_CHANGE then
		SendSetting(setting)
	end
	turn.sent = turn.setting * turn.share
end

-- A move from rest: the lowest setting in and the creep started its way
-- (see PRIME_SHARE), the move sent over it SPEED_PRIME_TIME later (Push).
local function Prime()
	SendSetting(SPEED_MIN_SETTING)
	Send(Command(turn.right) .. "Start", PRIME_SHARE)
	turn.creeping = true
	turn.primedUntil = GetTime() + SPEED_PRIME_TIME
end

-- A move's top speed (degrees/sec) and its most speeding up or slowing
-- down (degrees/sec per second), by kind.
local function TopSpeed(kind)
	if kind == "search" then
		return SEARCH_SPEED, SEARCH_ACCEL
	end
	return ns.db.chatCamSwingSpeed, MAX_ACCEL
end

-- Turns to `target` degrees (counted) over T seconds. from: the speed it's
-- turning at already, the same way (a drift turned into a swing): the move
-- carries on from it rather than stopping and starting again.
local function MoveTo(target, T, ease, kind, from)
	local distance = math.abs(target - turn.amount)
	if not from then
		StopMove()
	end
	if distance < 0.5 then
		turn.amount = target
		StopMove()
		return
	end
	-- (The top speed that covers the distance: speeding up from `from` over the
	-- first ease * T seconds, then on, then slowing to rest over the last.)
	local carrying = from ~= nil
	from = from or 0
	local function Cruise()
		local R = ease * T
		return math.max(from, (distance - from * R / 2) / (T - R)), R
	end
	-- The safeguard, whatever asked for the move: no faster than its top
	-- speed, speeding up and slowing down no harder than its most (stretched
	-- till it fits).
	local top, accel = TopSpeed(kind)
	top = math.max(top, from) -- (already going faster: it can't be helped)
	local asked, cruise, R = T, Cruise()
	for _ = 1, 100 do
		if cruise <= top * 1.001 and (R <= 0 or cruise * math.pi / (2 * R) <= accel * 1.001) then
			break
		end
		T = T * 1.05
		cruise, R = Cruise()
	end
	if T > asked * 1.01 then
		Say(("%s held to %.0f deg/sec: %.1fs, not %.1fs"):format(kind, top, T, asked))
	end
	turn.target, turn.t, turn.T, turn.ease, turn.kind = target, 0, T, ease, kind
	turn.right = target > turn.amount
	turn.from, turn.speed, turn.cruise = from, from, cruise
	-- The share of your speed setting it's sent at: your setting is then its top speed.
	turn.share = turn.cruise / ns.HoldSpeed(WHO, CVAR)
	if carrying and turn.sent then
		-- (Carrying on from a move under way: sent again at the new share, the
		-- setting moved so the speed holds.)
		SendSetting(math.max(SPEED_MIN_SETTING, from / turn.share))
		Send(Command(turn.right) .. "Start", turn.share)
		turn.sent, turn.primedUntil = turn.setting * turn.share, 0
	else
		-- (The setting at its lowest a moment before the move starts, creeping.)
		Prime()
	end
	turn.stopping = nil
	turn.moving = true
	ns.ApplyCVarSet(FOLLOW_CVARS, true)
end

-- Starts keeping up with the one it's on (see TRACK_CATCH), from rest: sent
-- at the share that makes your setting chatCamSwingSpeed, its speed then
-- set by turn.want.
local function StartTrack(right, want)
	StopMove()
	turn.kind, turn.right, turn.want, turn.speed, turn.t, turn.accel = "track", right, want, 0, 0, 0
	turn.share = ns.db.chatCamSwingSpeed / ns.HoldSpeed(WHO, CVAR)
	Prime()
	turn.stopping = nil
	turn.moving = true
	ns.ApplyCVarSet(FOLLOW_CVARS, true)
end

-- A swing or turn back of `distance` degrees: as quick as chatCamSwingSpeed allows.
local function SwingTime(distance, ease, least)
	local T = math.max(least, distance / (ns.db.chatCamSwingSpeed * (1 - ease)))
	if ease > 0 then
		-- (A half-cosine ramp of R seconds up to v peaks at v * pi / (2R) degrees/sec
		-- per second; v = distance / (T * (1 - ease)), R = ease * T.)
		T = math.max(T, math.sqrt(math.pi * distance / (2 * ease * (1 - ease) * MAX_ACCEL)))
	end
	return T
end

-- A move under way slows to a stop from the speed it's at, over STOP_TIME
-- (or T seconds; cut dead, it jolts). Not started yet: just dropped. With
-- no T, no harder than STOP_HARDER times the move's most (a swing at 15
-- degrees/sec stopped over 0.8 seconds slowed by 29 a second, three times a
-- swing's own; at its own most, it ran on 20 degrees the wrong way first).
local STOP_HARDER = 2
local function EaseToStop(T)
	if not T and turn.moving then
		local _, accel = TopSpeed(turn.kind)
		T = math.max(STOP_TIME, (turn.speed or turn.sent or 0) * math.pi / (2 * accel * STOP_HARDER))
	end
	if not turn.moving or (turn.stopping and turn.stopping.T <= (T or STOP_TIME)) then
		return
	end
	if not turn.sent then
		StopMove()
		return
	end
	turn.stopping = { from = turn.speed or turn.sent, t = 0, T = T or STOP_TIME }
end

-- The speed at t along the move: up from `from` (half a cosine), on at the
-- top, down to rest (half a cosine).
local function MoveSpeed(t)
	local T, R = turn.T, turn.ease * turn.T
	if R <= 0 then
		return turn.cruise
	elseif t < R then
		return turn.from + (turn.cruise - turn.from) * (1 - math.cos(math.pi * t / R)) / 2
	elseif t > T - R then
		return turn.cruise * (1 - math.cos(math.pi * (T - t) / R)) / 2
	end
	return turn.cruise
end

local function StepMove(elapsed)
	if not turn.moving or GetTime() < turn.primedUntil then
		return
	end
	turn.t = turn.t + elapsed
	local speed, over
	if turn.stopping then
		local stopping = turn.stopping
		stopping.t = stopping.t + elapsed
		over = stopping.t >= stopping.T
		speed = over and 0 or stopping.from * (1 + math.cos(math.pi * stopping.t / stopping.T)) / 2
	elseif turn.kind == "track" then
		-- (Eased toward the speed wanted, no harder than MAX_ACCEL, its speeding
		-- up changing no quicker than TRACK_JERK; all but still with none wanted: over.)
		if convo and (turn.right and 1 or -1) * (turn.amount - convo.base) >= TRACK_MAX then
			turn.want = 0 -- (the safeguard, whatever's steering it: see TRACK_MAX)
		end
		local want = turn.want or 0
		local accel = turn.accel or 0
		local aim = math.max(-MAX_ACCEL, math.min(MAX_ACCEL, (want - (turn.speed or 0)) / TRACK_EASE))
		local jerk = TRACK_JERK * elapsed
		accel = accel + math.max(-jerk, math.min(jerk, aim - accel))
		speed = math.max(0, (turn.speed or 0) + accel * elapsed)
		turn.accel = speed > 0 and accel or 0
		over = want <= 0 and speed < TRACK_STILL
	else
		over = turn.t >= turn.T
		speed = over and 0 or MoveSpeed(turn.t)
	end
	turn.speed = speed
	if over then
		if not turn.stopping and turn.kind ~= "track" then
			turn.amount = turn.target -- (counted as it went: this tidies the last hundredth)
		end
		StopMove() -- (stopped early, or a track: where it's got to)
		return
	end
	Push(speed)
	if turn.sent then
		turn.amount = turn.amount + (turn.right and turn.sent or -turn.sent) * elapsed
	end
end

local function Turned()
	return turn.amount ~= 0 or turn.moving
end

-- Let go where it is: nothing undone (you moved, or moved the camera, or
-- another camera took over). quick: a move under way stops over LET_GO_TIME
-- rather than dead.
local function HandOver(why, quick, hold)
	if Turned() or (convo and convo.zoomedTo) or leaving or ns.QuestCamZooming() then
		Say(("let go at %+.1f deg (%s)"):format(turn.amount, why))
	end
	if quick then
		EaseToStop(LET_GO_TIME)
	else
		StopMove()
	end
	-- hold: let go as you moved off or turned the camera (not zoomed it). The
	-- zoom back out to your distance is then held till you've walked off, as
	-- the quest cam's own (ns.QuestCamHoldZoomOut), not dropped. (Your speed
	-- setting eases back rather than at once: the game's last bit of zoom
	-- still to go showed as a hop in.)
	local was = convo or leaving
	local back = zoomingOut and ns.QuestCamZooming() and zoomingOut
	if not back and was and was.zoom and was.zoomedTo and GetCameraZoom
		and not ns.PlayerZoomedSince(was.startedAt)
		and (ns.QuestCamZooming() or math.abs(GetCameraZoom() - was.zoomedTo) < ZOOM_YOURS) then
		back = was.zoom
	end
	hold = hold and back and ns.db.chatCamZoomOutSpeed > 0 and ns.QuestCamHoldZoomOut
	if (convo and convo.zoomedTo) or (leaving and leaving.zoomedTo) or (zoomingOut and ns.QuestCamZooming()) then
		ns.QuestCamStopZoom(hold)
	end
	if hold then
		Say(("zoom back out to %.1f yards held till you walk off"):format(back))
		ns.QuestCamHoldZoomOut(back, ns.db.chatCamZoomOutSpeed)
	end
	zoomingOut = nil
	turn.amount, convo, leaving = 0, nil, nil
	ns.ApplyCVarSet(FOLLOW_CVARS, false)
end

-- The conversation's over: the drift eases to a stop, then the camera turns
-- back and zooms back out (unless you zoomed yourself).
local function End(why)
	Say("conversation over (" .. why .. ")" .. (Turned() and (", turning back from %+.1f deg"):format(turn.amount) or ""))
	leaving = { zoom = convo.zoom, zoomedTo = convo.zoomedTo, startedAt = convo.startedAt }
	convo = nil
	EaseToStop()
end

local function Leave(now)
	if turn.moving or now - turn.stoppedAt < DRIFT_GAP then
		return
	end
	if not leaving.turnedBack then
		leaving.turnedBack = true
		turn.amount = (turn.amount + 180) % 360 - 180 -- (looked round for someone: the shorter way back)
		if turn.amount ~= 0 then
			MoveTo(0, SwingTime(math.abs(turn.amount), Ease(BACK_EASE), BACK_MIN_TIME), Ease(BACK_EASE), "back")
			return
		end
	end
	-- (The zoom back out once the turn back's done, not alongside it: the
	-- zoom's small steps every tenth of a second showed as jitter in the turn.)
	local zoom, zoomedTo = leaving.zoom, leaving.zoomedTo
	if zoom and zoomedTo and GetCameraZoom and ns.db.chatCamZoomOutSpeed > 0
		and not ns.PlayerZoomedSince(leaving.startedAt)
		and (ns.QuestCamZooming() or math.abs(GetCameraZoom() - zoomedTo) < ZOOM_YOURS) then
		Say(("zooming back out to %.1f yards"):format(zoom))
		zoomingOut = zoom
		ns.QuestCamZoomTo(zoom, math.min(ns.db.chatCamZoomMaxTime,
			math.abs(zoom - GetCameraZoom()) / ns.db.chatCamZoomOutSpeed))
	end
	leaving = nil
end

-- The angle (degrees, positive right) off the view's middle of a bubble on
-- screen saying `text`, its x and y (-1 to 1), and how many other bubbles
-- are showing; nil if there's none.
-- The Test button (CameraTests.lua): a made-up conversation between two
-- speakers either side of you, a few lines each, with pretend bubbles that
-- move across the screen as the camera turns (by FAKE_GAIN, as measured with
-- Liadrin and Zul'jarra). Real bubbles are passed over meanwhile.
-- (About as far apart as Liadrin and Zul'jarra stood, zoomed in: wider, each
-- swing whipped the view round.)
local FAKE_SPEAKERS = { { "Speaker on your left", -12 }, { "Speaker on your right", 10 } }
local FAKE_LINES = { { 0, 1 }, { 4, 1 }, { 7, 2 }, { 12, 1 }, { 16, 2 }, { 19, 2 } } -- { seconds in, speaker }
local FAKE_GAIN = 0.45
local FAKE_BUBBLE = 10 -- seconds a pretend bubble shows (as long as a swing, so its result's measured)
local fake -- { amountAt (turn.amount as it began), shown = { [text] = { angle, untilAt } } }

-- Something's middle on screen, in WorldFrame units; nil if it can't be read.
local function Place(object)
	local ok, x, y = pcall(object.GetCenter, object)
	if not ok or type(x) ~= "number" or type(y) ~= "number" or Secret(x) or Secret(y) then
		return nil
	end
	local okScale, scale = pcall(object.GetEffectiveScale, object)
	if not okScale or type(scale) ~= "number" or Secret(scale) then
		return nil
	end
	scale = scale / WorldFrame:GetEffectiveScale()
	return x * scale, y * scale
end

local function BubbleAngle(text)
	if fake then
		local bubble = fake.shown[text]
		if not bubble or GetTime() >= bubble.untilAt then
			return nil
		end
		local now, others = GetTime(), 0
		for shownText, shown in pairs(fake.shown) do
			if shownText ~= text and now < shown.untilAt then
				others = others + 1
			end
		end
		local angle = bubble.angle - FAKE_GAIN * (turn.amount - fake.amountAt)
		return angle, math.tan(math.rad(angle)), 0, others, "tail" -- (x on screen, at a 90-degree field of view)
	end
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles and ns.BubbleSays) then
		return nil
	end
	local width, height = WorldFrame:GetWidth(), WorldFrame:GetHeight()
	local angle, sx, sy, how
	local shown = 0
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) and ns.Flag(bubble:IsVisible()) then
			shown = shown + 1
			if not angle and ns.BubbleSays(bubble, text) then
				local x, y = Place(bubble)
				if x and x >= 0 and x <= width and y >= 0 and y <= height then
					-- (Where the tail says they are, if there's one to read: see TAIL_MIDDLE.)
					how = "box"
					local okInner, inner = pcall(bubble.GetChildren, bubble)
					local tail = okInner and type(inner) == "table" and inner.Tail
					local okShown, tailShown = false, nil
					if tail then
						okShown, tailShown = pcall(tail.IsShown, tail)
					end
					local tailX = okShown and ns.Flag(tailShown) and Place(tail)
					if tailX then
						local offset = tailX - x
						if math.abs(offset) <= TAIL_MIDDLE then
							x, how = tailX, "tail"
						else
							x = tailX + (offset > 0 and PINNED_BEYOND or -PINNED_BEYOND)
							how = offset > 0 and "pinned right" or "pinned left"
						end
					end
					local bx = (x - width / 2) / (width / 2)
					local okFov, fov = pcall(GetCVar, "cameraFov")
					fov = okFov and tonumber(fov) or 90
					angle, sx, sy = math.deg(math.atan(bx * math.tan(math.rad(fov) / 2))), bx,
						(y - height / 2) / (height / 2)
				end
			end
		end
	end
	if angle then
		return angle, sx, sy, shown - 1, how
	end
	return nil
end

-- Which side of the screen (1 right, -1 left) a bubble saying `text` is
-- drawn off it, or nil (none, or it can't be read).
local function BubbleSide(text)
	if fake or not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles and ns.BubbleSays) then
		return nil
	end
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) and ns.BubbleSays(bubble, text) then
			local x = Place(bubble)
			if x and x < 0 then
				return -1
			elseif x and x > WorldFrame:GetWidth() then
				return 1
			end
		end
	end
	return nil
end

-- How a bubble reads, for the log: good (its tail over their head, and
-- alone) or why not.
local function BubbleReading(sy, others, how)
	if how == "pinned left" or how == "pinned right" then
		return false, ("box moved aside, tail %s: about %d past it"):format(how, PINNED_BEYOND)
	elseif how == "box" and sy >= TOP_EDGE then
		return false, "no tail, on the top edge"
	elseif others > 0 then
		return false, ("%d other bubble%s showing"):format(others, others == 1 and "" or "s")
	end
	return true, how == "tail" and "tail over their head, alone" or "no tail, over their head, alone"
end

-- The debug log's readings (see DEBUG_MAX). Everything's read through pcall
-- and checked for secret values: a part that can't be read says why.
local function Readable(...)
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if value == nil or Secret(value) then
			return false
		end
	end
	return true
end
local function Show(value, form)
	if Secret(value) then
		return "secret"
	elseif form and type(value) == "number" then
		return form:format(value)
	end
	return tostring(value)
end

-- Where something's drawn, in WorldFrame units (the screen: 0,0 bottom left):
-- its middle, size, and how far each edge is from the screen's (top, bottom,
-- left, right), "-" past it.
local function Rect(object)
	local ok, left, bottom, width, height = pcall(object.GetRect, object)
	if not ok then
		return "can't measure"
	elseif left == nil then
		return "no place"
	elseif not Readable(left, bottom, width, height) then
		return "secret place"
	end
	local okScale, scale = pcall(object.GetEffectiveScale, object)
	scale = (okScale and Readable(scale) and scale or 1) / WorldFrame:GetEffectiveScale()
	left, bottom, width, height = left * scale, bottom * scale, width * scale, height * scale
	local screenW, screenH = WorldFrame:GetWidth(), WorldFrame:GetHeight()
	return ("mid %.0f,%.0f size %.0fx%.0f gaps T%.0f B%.0f L%.0f R%.0f"):format(left + width / 2,
		bottom + height / 2, width, height, screenH - bottom - height, bottom, left, screenW - left - width)
end

-- Its key in its parent (Tail, String...), else its debug name.
local function Key(object)
	local okParent, parent = pcall(object.GetParent, object)
	if okParent and type(parent) == "table" then
		for key, value in pairs(parent) do
			if value == object and type(key) == "string" then
				return key
			end
		end
	end
	local okName, name = pcall(object.GetDebugName, object)
	return okName and type(name) == "string" and not Secret(name) and name or "-"
end

local function Anchors(object)
	local okCount, count = pcall(object.GetNumPoints, object)
	if not okCount or not Readable(count) then
		return "?"
	end
	local out = {}
	for i = 1, count do
		local ok, point, relativeTo, relativePoint, x, y = pcall(object.GetPoint, object, i)
		if ok then
			out[#out + 1] = ("%s>%s.%s %s,%s"):format(Show(point), relativeTo and Key(relativeTo) or "nil",
				Show(relativePoint), Show(x, "%.1f"), Show(y, "%.1f"))
		else
			out[#out + 1] = "can't read"
		end
	end
	return table.concat(out, " ")
end

-- One frame, texture or text: kind, key, shown, place, alpha, anchors, and a
-- texture's atlas, file and corners (a tail flipped or slid would show
-- there), or a text's words.
local function Describe(object, depth)
	local okKind, kind = pcall(object.GetObjectType, object)
	kind = okKind and Show(kind) or "?"
	local okShown, shown = pcall(object.IsShown, object)
	local okAlpha, alpha = pcall(object.GetAlpha, object)
	local extra = ""
	if kind == "Texture" then
		local okAtlas, atlas = pcall(object.GetAtlas, object)
		local okFile, file = pcall(object.GetTexture, object)
		local okCoord, ulx, uly, llx, lly, urx, ury, lrx, lry = pcall(object.GetTexCoord, object)
		extra = (" atlas %s file %s coords %s"):format(okAtlas and Show(atlas) or "?", okFile and Show(file) or "?",
			okCoord and Readable(ulx, uly, llx, lly, urx, ury, lrx, lry)
				and ("%.2f,%.2f %.2f,%.2f %.2f,%.2f %.2f,%.2f"):format(ulx, uly, llx, lly, urx, ury, lrx, lry) or "?")
	elseif kind == "FontString" then
		local okText, text = pcall(object.GetText, object)
		extra = " text " .. (okText and (Secret(text) and "secret" or ("%q"):format(tostring(text):sub(1, 40))) or "?")
	end
	return ("%s%s %s %s %s a%s at[%s]%s"):format(("  "):rep(depth), kind, Key(object),
		okShown and (Secret(shown) and "shown?" or (shown and "shown" or "hidden")) or "?", Rect(object),
		okAlpha and Show(alpha, "%.2f") or "?", Anchors(object), extra)
end

local function DumpTree(frame, depth, out)
	out[#out + 1] = Describe(frame, depth)
	if depth >= 5 then
		return
	end
	local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
	for _, region in ipairs(okRegions and regions or {}) do
		out[#out + 1] = Describe(region, depth + 1)
	end
	local okChildren, children = pcall(function() return { frame:GetChildren() } end)
	for _, child in ipairs(okChildren and children or {}) do
		if not (child.IsForbidden and child:IsForbidden()) then
			DumpTree(child, depth + 1, out)
		end
	end
end

-- The first part under `frame` that `match` picks (depth first).
local function FindPart(frame, match, depth)
	depth = depth or 0
	local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
	for _, region in ipairs(okRegions and regions or {}) do
		if match(region) then
			return region
		end
	end
	if depth < 5 then
		local okChildren, children = pcall(function() return { frame:GetChildren() } end)
		for _, child in ipairs(okChildren and children or {}) do
			if not (child.IsForbidden and child:IsForbidden()) then
				if match(child) then
					return child
				end
				local found = FindPart(child, match, depth + 1)
				if found then
					return found
				end
			end
		end
	end
end
local function IsTail(object)
	if Key(object):lower():find("tail") then
		return true
	end
	local okAtlas, atlas = pcall(object.GetAtlas, object)
	if okAtlas and type(atlas) == "string" and not Secret(atlas) and atlas:lower():find("tail") then
		return true
	end
	local okFile, file = pcall(object.GetTexture, object)
	return okFile and type(file) == "string" and not Secret(file) and file:lower():find("tail") ~= nil
end
local function IsText(object)
	local ok, kind = pcall(object.GetObjectType, object)
	return ok and kind == "FontString"
end

-- Every bubble showing: a short line each reading (the bubble frame, its
-- first child, the tail, the text's place), the whole tree when first seen
-- and every DEBUG_FULL_EVERY seconds after.
local function DebugBubbles(now)
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
		DebugAdd("bubbles: no API")
		return
	end
	local all = C_ChatBubbles.GetAllChatBubbles(true)
	local readable = C_ChatBubbles.GetAllChatBubbles(false)
	DebugAdd(("bubbles: %d in all, %d readable"):format(#all, #readable))
	for _, bubble in ipairs(readable) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) then
			local id = debugLog.ids[bubble]
			if not id then
				debugLog.nextId = debugLog.nextId + 1
				id = debugLog.nextId
				debugLog.ids[bubble] = id
			end
			local okVisible, visible = pcall(bubble.IsVisible, bubble)
			local text = FindPart(bubble, IsText)
			local words = "?"
			if text then
				local okText, said = pcall(text.GetText, text)
				words = okText and (Secret(said) and "secret" or ("%q"):format(tostring(said):sub(1, 30))) or "?"
			end
			local okChildren, children = pcall(function() return { bubble:GetChildren() } end)
			local inner = okChildren and children[1]
			local tail = FindPart(bubble, IsTail)
			local okTailShown, tailShown = false, nil
			if tail then
				okTailShown, tailShown = pcall(tail.IsShown, tail)
			end
			DebugAdd(("bubble #%d %s %s | frame %s | inner %s | tail %s%s | text %s"):format(id,
				okVisible and (Secret(visible) and "visible?" or (visible and "visible" or "not visible")) or "?",
				words, Rect(bubble), inner and Rect(inner) or "none", tail and Rect(tail) or "none",
				tail and (okTailShown and (Secret(tailShown) and " shown?" or (tailShown and " shown" or " hidden")) or " ?")
					or "", text and Rect(text) or "none"))
			if okVisible and ns.Flag(visible) and now - (debugLog.fullAt[id] or -math.huge) >= DEBUG_FULL_EVERY then
				debugLog.fullAt[id] = now
				local out = {}
				DumpTree(bubble, 1, out)
				DebugAdd(("bubble #%d tree (%d parts):"):format(id, #out))
				for _, line in ipairs(out) do
					DebugAdd(line)
				end
			end
		end
	end
end

-- The nameplates (by unit: name, whether it's the one talking, 28 yards,
-- its place in the world and on screen), your target's, and yours.
local function DebugUnit(unit, speaker)
	local okName, name = pcall(UnitName, unit)
	local okGuid, guid = pcall(UnitGUID, unit)
	local okRange, near = pcall(CheckInteractDistance, unit, 4)
	local okPos, y, x = pcall(UnitPosition, unit)
	name = okName and name
	return ("%s %s%s guid %s 28y %s world %s"):format(unit, Show(name),
		speaker and Readable(name) and name == speaker and " (TALKING)" or "",
		okGuid and Show(guid) or "?", okRange and Show(near) or "can't",
		okPos and (Readable(x, y) and ("%.1f,%.1f"):format(x, y) or Show(x) .. "," .. Show(y)) or "can't")
end
local function DebugPlates()
	local speaker = convo and convo.speaker and convo.speaker.name
	local okFacing, facing = pcall(GetPlayerFacing)
	DebugAdd(("clock %s | %s facing %s"):format(date("%H:%M:%S"), DebugUnit("player"),
		okFacing and Show(facing, "%.3f") or "can't"))
	if UnitExists("target") then
		DebugAdd("target: " .. DebugUnit("target", speaker))
	end
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local okPlates, plates = pcall(C_NamePlate.GetNamePlates)
	plates = okPlates and plates or {}
	local okFriendly, friendly = pcall(GetCVar, "nameplateShowFriendlyNPCs")
	DebugAdd(("plates: %d (friendly NPC plates %s)"):format(#plates, okFriendly and Show(friendly) or "?"))
	for _, plate in ipairs(plates) do
		if not (plate.IsForbidden and plate:IsForbidden()) then
			local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			DebugAdd(("plate %s | %s"):format(unit and DebugUnit(unit, speaker) or "no unit", Rect(plate)))
		end
	end
end

-- Each frame while it's at work: the bubbles and camera every DEBUG_EVERY,
-- the plates every DEBUG_PLATES_EVERY.
local function DebugTick(now)
	if not debugLog.started or ns.db.chatCamDebugOff then
		return
	end
	if now >= debugLog.nextAt then
		debugLog.nextAt = now + DEBUG_EVERY
		DebugAdd(("camera: zoom %s turned %+.2f%s %s sent %s quest-cam zooming %s"):format(
			GetCameraZoom and Show(GetCameraZoom(), "%.2f") or "?", turn.amount, turn.moving and " moving" or "",
			turn.kind or "-", turn.sent and ("%.2f"):format(turn.sent) or "-",
			tostring(ns.QuestCamZooming and ns.QuestCamZooming() or false)))
		DebugBubbles(now)
	end
	if now >= debugLog.platesAt then
		debugLog.platesAt = now + DEBUG_PLATES_EVERY
		DebugPlates()
	end
end

-- A line heard (whether Chat Cam takes it or not, and why not): starts the
-- log, once after each login or /reload.
local function DebugLine(event, text, name, guid, ignored)
	if ns.db.chatCamDebugOff then
		return
	end
	if not debugLog.started then
		debugLog.started = true
		ns.db.chatCamDebug = {}
		local cvars = {}
		for _, cvar in ipairs({ "cameraFov", "chatBubbles", "chatBubblesParty", "nameplateShowFriendlyNPCs",
			"test_cameraOverShoulder", "CameraKeepCharacterCentered", "cameraYawMoveSpeed", "cameraZoomSpeed",
			"uiScale", "useUiScale" }) do
			local ok, value = pcall(GetCVar, cvar)
			cvars[#cvars + 1] = cvar .. "=" .. (ok and Show(value) or "?")
		end
		local okMap, map = pcall(C_Map.GetBestMapForUnit, "player")
		DebugAdd(("START %s (GetTime %.2f) %s | screen %.0fx%.0f, WorldFrame scale %.3f, UIParent scale %.3f | %s | %s / %s map %s"):format(
			date("%Y-%m-%d %H:%M:%S"), GetTime(), ns.isRetail and "retail" or "classic", WorldFrame:GetWidth(),
			WorldFrame:GetHeight(), WorldFrame:GetEffectiveScale(), UIParent:GetEffectiveScale(), table.concat(cvars, " "),
			Show(GetRealZoneText()), Show(GetSubZoneText()), okMap and Show(map) or "?"))
	end
	DebugAdd(("LINE %s %s guid %s%s: %s"):format((tostring(event):gsub("^CHAT_MSG_", "")), Show(name), Show(guid),
		ignored and (" (not taken: " .. ignored .. ")") or "", Secret(text) and "secret" or tostring(text)))
	debugLog.nextAt, debugLog.platesAt = 0, 0 -- (a reading straight away)
end

-- Another camera has the view, or it's switched off: hands over.
local function TakenOver()
	if ns.IsSuspended() or not On() then
		return "off"
	elseif ns.QuestCamBusy and ns.QuestCamBusy() then
		return "quest cam"
	elseif ns.CameraHolder("chatcam") and ns.CameraHolder("chatcam") ~= "you" then
		return "the " .. ns.CameraHolder("chatcam") .. " camera has the view"
	elseif not fake and ns.IsCameraOffHere("chatcam") then
		return "turned off here (Cameras page)"
	elseif ns.CameraMode() then
		return "camera mode " .. tostring(ns.CameraMode())
	end
	return nil
end

-- How high (-1 to 1) the speaker's bubble middle goes before the zoom in
-- stops: ZOOM_EDGE, brought down by the letterbox's top bar while it shows
-- (the bubble's kept under the bar: see Bubbles.lua).
local function ZoomTop()
	local letterbox = ns.letterbox
	local height = UIParent:GetHeight()
	if not (letterbox and ns.Flag(letterbox:IsShown()) and letterbox:GetAlpha() > 0 and height > 0) then
		return ZOOM_EDGE
	end
	return ZOOM_EDGE - 2 * letterbox.top:GetHeight() / height
end

-- The first bubble seen in the conversation: in to the quest cam's distance
-- (not if you're zooming yourself, or already close). Talking again on the
-- zoom back out: in again from wherever it's got to, not on out to your
-- distance mid-conversation.
local function ZoomIn(now, sx, sy)
	convo.zoomChecked = true
	local db = ns.db
	if not (GetCameraZoom and ns.QuestCamZoomTo) then
		return
	end
	if ns.PlayerZoomedSince(now - (ns.PLAYER_ZOOM_WAIT or 1)) then
		Say("you're zooming: no zoom in")
	elseif (sy >= ZoomTop() or math.abs(sx) >= ZOOM_EDGE) and not ns.QuestCamZooming() then
		Say(("bubble near the edge already (x %+.2f y %+.2f): no zoom in"):format(sx, sy))
	elseif GetCameraZoom() > db.chatCamDistance + ZOOM_MARGIN or ns.QuestCamZooming() then
		convo.zoom = convo.zoom or (ns.PlayerZoom and ns.PlayerZoom()) or GetCameraZoom()
		convo.zoomedTo, convo.zoomingIn = db.chatCamDistance, true
		Say(("zooming in to %.1f yards"):format(db.chatCamDistance))
		ns.QuestCamZoomTo(db.chatCamDistance, math.min(db.chatCamZoomMaxTime,
			math.abs(GetCameraZoom() - db.chatCamDistance) / db.chatCamZoomSpeed))
	end
end

-- Looks round for a speaker with no bubble on screen (see SEARCH_SPEED): a
-- full turn their way at most, eased in and out.
local function StartSearch(now, speaker)
	convo.searched = convo.searched or {}
	convo.searched[speaker.name] = true
	local way, why = BubbleSide(speaker.text), "their bubble's off that side"
	local placed = convo.placed and convo.placed[speaker.name]
	if not way and placed then
		way = placed.at - convo.gain * (turn.amount - convo.base) >= 0 and 1 or -1
		why = "where they were before"
	end
	if not way then
		way, why = math.random() < 0.5 and 1 or -1, "no telling which way"
	end
	local R = SEARCH_SPEED * math.pi / (2 * SEARCH_ACCEL) -- (seconds speeding up: see SwingTime)
	local T = 360 / SEARCH_SPEED + R
	convo.search = { from = turn.amount, way = way }
	convo.turnedAt = convo.turnedAt or now
	Say(("%s: no bubble on screen, looking round to the %s for them (%s)"):format(
		speaker.name, way > 0 and "right" or "left", why))
	Note("search for " .. speaker.name)
	MoveTo(turn.amount + 360 * way, T, R / T, "search")
end

-- A new speaker: swing toward their bubble once it shows.
-- drifting: a move's under way (a drift leg, a swing, the turn back). Going
-- the new swing's way, it turns into it; the other way, it eases to a stop
-- first (Aim again after).
local function Aim(now, drifting)
	local speaker = convo.speaker
	local search = convo.search
	if search then
		if BubbleAngle(speaker.text) then
			-- (Eased to a stop, then the usual swing frames them.)
			convo.search, convo.rebase = nil, true
			Say(("found %s's bubble %+.0f deg round: stopping"):format(speaker.name, turn.amount - search.from))
			EaseToStop()
		elseif not turn.moving then
			convo.search, speaker.missing = nil, true
			turn.amount = turn.amount - 360 * search.way -- (a full turn: back where it started)
			Say(("%s: no bubble anywhere round, staying on %s"):format(speaker.name, convo.on or "where it is"))
		end
		return
	end
	if convo.rebase then
		-- (Turned round to find someone: where the camera's got to is the new
		-- start, for the spots and how far it turns from there.)
		convo.rebase, convo.base, convo.placed = nil, turn.amount, nil
	end
	local zooming = ns.QuestCamZooming and ns.QuestCamZooming()
	local angle, sx, sy, others, how = BubbleAngle(speaker.text)
	if not angle then
		if speaker.waiting and not speaker.missing then
			-- (Done talking before the budget let it swing: no looking round.)
			speaker.missing = true
			Say(("%s's bubble gone before the swing, staying where it is"):format(speaker.name))
		elseif not speaker.missing and now - speaker.at > BUBBLE_WAIT then
			if ns.db.chatCamSearch and not (convo.searched and convo.searched[speaker.name]) then
				if drifting then
					EaseToStop() -- (a stop first, then the look round)
				else
					StartSearch(now, speaker)
				end
				return
			end
			speaker.missing = true
			Say(("%s: no bubble on screen, staying on %s%s"):format(speaker.name, convo.on or "where it is",
				convo.zoomChecked and "" or " (no zoom in)"))
		end
		return
	end
	-- Zoomed in only once a bubble's on screen: after walking off, say, the
	-- speaker may be behind you or out of sight, and a close-up shows nothing.
	if not convo.zoomChecked then
		ZoomIn(now, sx, sy)
		zooming = ns.QuestCamZooming and ns.QuestCamZooming()
	end
	local good, reading = BubbleReading(sy, others, how)
	-- (Where they'd be on screen with the camera where it started, to compare
	-- with the others who've talked: as first placed, or first placed by a
	-- good bubble.)
	convo.placed = convo.placed or {}
	local placed = convo.placed[speaker.name]
	if not placed or (good and not placed.good) then
		convo.placed[speaker.name] = { at = angle + convo.gain * (turn.amount - convo.base), good = good }
	end
	-- Each speaker's spot by their order, left to right, spread evenly from
	-- SIDE_TURN left to SIDE_TURN right (once two have talked).
	local frame = ns.db.chatCamFrame
	local spotAt, spot
	local names = {}
	for name in pairs(convo.placed) do
		names[#names + 1] = name
	end
	if #names > 1 then
		local placedAt = convo.placed
		table.sort(names, function(a, b)
			return placedAt[a].at < placedAt[b].at or (placedAt[a].at == placedAt[b].at and a < b)
		end)
		for i, name in ipairs(names) do
			if name == speaker.name then
				spotAt = convo.base - SIDE_TURN + 2 * SIDE_TURN * (i - 1) / (#names - 1)
				spot = ("spot %d of %d from the left"):format(i, #names)
			end
		end
	end
	local off = math.abs(angle) <= frame and 0 or (angle - (angle > 0 and frame or -frame))
	local wanted
	if good and off ~= 0 then
		-- (A good bubble well off the middle: to chatCamFrame degrees off it on
		-- their side, through the gain.)
		wanted, spot = turn.amount + off / convo.gain, nil
	elseif spotAt then
		-- (Otherwise their spot. Even in view: two speakers a few degrees apart
		-- both read in view, and the camera never turned between them.)
		wanted = spotAt
	elseif good or off == 0 then
		wanted = turn.amount -- (the only one so far, and in view)
	else
		wanted = convo.base + (off > 0 and SIDE_TURN or -SIDE_TURN) -- (the only one so far: SIDE_TURN their way)
	end
	local target = math.max(turn.amount - MAX_SWING, math.min(turn.amount + MAX_SWING, wanted))
	-- (Mid zoom in, the gain's the close-up one, not yet true: SIDE_TURN at most.)
	local most = zooming and SIDE_TURN or MAX_TURN
	target = math.max(convo.base - most, math.min(convo.base + most, target))
	local step = target - turn.amount
	-- (The budget: what's been swung in the last TURN_WINDOW seconds.)
	local swings, spent = convo.swings or {}, 0
	for i = #swings, 1, -1 do
		if now - swings[i].at >= TURN_WINDOW then
			table.remove(swings, i)
		else
			spent = spent + swings[i].amount
		end
	end
	convo.swings = swings
	local budget
	local left = math.max(0, TURN_BUDGET - spent)
	if math.abs(step) > left then
		if off ~= 0 and left < math.min(math.abs(step), SIDE_TURN) then
			-- (Well off the framing, and little budget left: waits for it, rather
			-- than a crawl of small swings, or none (one left a speaker on the
			-- screen's edge, x -0.96).)
			if not speaker.waiting then
				speaker.waiting = true
				Say(("%s: %+.1f deg off the middle, waiting to swing (%.0f deg swung in the last %ds)"):format(
					speaker.name, angle, spent, TURN_WINDOW))
			end
			return
		end
		budget = (", cut from %+.1f: %.0f deg swung in the last %ds"):format(step, spent, TURN_WINDOW)
		step = left * (step > 0 and 1 or -1)
		target = turn.amount + step
	end
	local carry = drifting and turn.sent and math.abs(step) >= MIN_TURN and (step > 0) == turn.right
	if drifting and not carry then
		EaseToStop() -- (the other way, or not worth a swing: a stop first, then a fresh look)
		return
	end
	speaker.aimed = true
	convo.on = speaker.name
	convo.center, convo.driftOut = target, nil
	if math.abs(step) < MIN_TURN then
		Say(("on %s: %+.1f deg off the middle (bubble x %+.2f y %+.2f, %s)%s, %s"):format(
			speaker.name, angle, sx, sy, reading, spot and (", " .. spot) or "",
			budget and ("held (%.0f deg swung in the last %ds)"):format(spent, TURN_WINDOW) or "already in view"))
		return
	end
	swings[#swings + 1] = { at = now, amount = math.abs(step) }
	local T = SwingTime(math.abs(step), Ease(SWING_EASE), SWING_MIN_TIME)
	Say(("swinging to %s%s: %+.1f deg off the middle (bubble x %+.2f y %+.2f, %s), gain %.2f, %+.1f to %+.1f over %.1fs%s"):format(
		speaker.correcting and "(again) " or "", speaker.name, angle, sx, sy, reading,
		convo.gain, step, target, T,
		(target ~= wanted and " (as far as it goes)" or "") .. (spot and (", " .. spot) or "") .. (budget or "")))
	Note("swing to " .. speaker.name)
	convo.slack = nil -- (set again by where this swing leaves them: see TRACK_EASE)
	convo.turnedAt = convo.turnedAt or now
	if carry then
		Note(turn.kind .. " turned into the swing")
	end
	MoveTo(target, T, Ease(SWING_EASE), "swing", carry and (turn.speed or turn.sent) or nil)
	-- (Looked at again once it's done: how far it really moved them.)
	convo.check = { speaker = speaker, angle = angle, step = step, good = good, zooming = zooming }
end

-- Settled on someone: a slow drift to and fro about them (the quest cam's
-- width), each leg's time by its distance.
local function Drift()
	local width = ns.db.chatCamDrift or 0
	if width < 1 or not convo.center then
		return
	end
	if convo.driftOut == nil then
		convo.driftOut = math.random() < 0.5
	else
		convo.driftOut = not convo.driftOut
	end
	local target = convo.center + (convo.driftOut and width / 2 or -width / 2)
	MoveTo(target, math.max(1, DRIFT_TIME * math.abs(target - turn.amount) / width), DRIFT_EASE, "drift")
end

local hitchSaidAt = 0
local function OnUpdate(_, elapsed)
	StepMove(elapsed)
	local now = GetTime()
	if elapsed > HITCH and turn.sent and now >= hitchSaidAt then
		-- (A slow frame mid-turn: the game's own stutter, not the curve's. Once a second at most.)
		hitchSaidAt = now + 1
		Say(("slow frame mid-%s: %.0f ms at %.1f deg/sec (%.0f fps)"):format(turn.kind or "move", elapsed * 1000,
			turn.sent, GetFramerate()))
	end
	if convo then
		local takenOver = TakenOver()
		-- (Your mouse already held on the camera as it started counts too: turning
		-- as the quest cam let go, its swing went against yours.)
		if convo.turnedAt and (ns.GetLastCameraInput() > convo.turnedAt or ns.IsMouseOnCamera()) then
			local zoomed = ns.lastCameraInputWhat == "zoom"
			HandOver(zoomed and "you zoomed"
				or ("you moved the camera: %s"):format(tostring(ns.lastCameraInputWhat)), nil, not zoomed)
			-- (Your turn speed now, not SPEED_RESTORE_DELAY later: your drag ran
			-- at the swing's crawl meanwhile, and the camera seemed taken away.)
			ns.ReleaseSpeed(WHO, CVAR)
		elseif takenOver then
			if Turned() or convo.zoomedTo then
				HandOver(takenOver)
			end
			-- (Otherwise the conversation's kept: the quest cam turning back at its
			-- start, say, and the lines carry on once it's done.)
		elseif UnitAffectingCombat("player") then
			End("fight")
		elseif ns.playerMoving then
			HandOver("you moved", true, true)
		elseif now - convo.lastLineAt >= ns.db.chatCamQuiet then
			End(("no one's talked for %d seconds"):format(ns.db.chatCamQuiet))
		else
			-- (The zoom in waits for the speaker's bubble on screen: see Aim.)
			if not convo.zoomChecked then
				convo.turnedAt = convo.turnedAt or now
			end
			local zooming = ns.QuestCamZooming and ns.QuestCamZooming()
			-- (Zooming in, their head rises up the screen and out to the side: the
			-- zoom eases to a stop before their bubble's pushed off the edge.)
			if zooming and convo.zoomingIn and convo.speaker and now >= (convo.edgeAt or 0) then
				convo.edgeAt = now + AIM_EVERY / 2
				local _, sx, sy = BubbleAngle(convo.speaker.text)
				if sx and (sy >= ZoomTop() or math.abs(sx) >= ZOOM_EDGE) then
					convo.zoomingIn = nil
					local goal = ns.QuestCamEaseZoomStop and ns.QuestCamEaseZoomStop(ZOOM_STOP_TIME)
					if goal then
						convo.zoomedTo = goal
						Say(("%s's bubble near the edge (x %+.2f y %+.2f): zoom stopping at %.1f yards"):format(
							convo.speaker.name, sx, sy, goal))
					end
				end
			end
			local check = convo.check
			if check and not turn.moving then
				convo.check = nil
				local speaker = check.speaker
				local after, _, afterY, afterOthers, afterHow = BubbleAngle(speaker.text)
				local afterGood, afterReading
				if after then
					afterGood, afterReading = BubbleReading(afterY, afterOthers, afterHow)
				end
				if not after then
					Say(("after the swing, %s's bubble is gone"):format(speaker.name))
				elseif check.zooming or zooming then
					-- (The zoom moved them too: no telling the turn's share.)
					Say(("after the swing, %s is %+.1f deg off the middle: zoomed meanwhile, not measured"):format(
						speaker.name, after))
				elseif not (check.good and afterGood) then
					-- (A box moved aside, or a bubble not alone, measures nothing: see TAIL_MIDDLE.)
					Say(("after the swing, %s is %+.1f deg off the middle (%s): not measured"):format(
						speaker.name, after, check.good and afterReading or "not a good bubble before"))
				else
					-- How far they moved on screen per degree turned (the gain).
					local moved = check.angle - after
					local gain = moved / check.step
					if gain > 0 then
						convo.gain = math.max(GAIN_MIN, math.min(GAIN_MAX, gain))
					end
					Say(("after the swing, %s is %+.1f deg off the middle (was %+.1f): moved %.2f deg per deg turned%s"):format(
						speaker.name, after, check.angle, gain,
						gain <= 0 and " - WRONG WAY? /cine chatcam flip" or ""))
					-- Still well off: one more go (not for a speaker someone else has since taken over from).
					if gain > 0 and not speaker.correcting and speaker == convo.speaker
						and math.abs(after) > ns.db.chatCamFrame + CORRECT and math.abs(turn.amount - convo.base) < MAX_TURN then
						speaker.correcting, speaker.aimed, convo.on = true, false, nil
					end
				end
				-- (Left short of the framing, and no more swings for it: that's where
				-- keeping up counts from. See TRACK_EASE.)
				local past = after and math.abs(after) - ns.db.chatCamFrame
				if past and past > 0 and speaker == convo.speaker and speaker.aimed then
					convo.slack = { name = speaker.name, right = after > 0, by = math.min(past, CORRECT) }
					Say(("%s left %.1f deg past the framing: keeping up counts from there"):format(speaker.name, past))
				end
			end
			local speaker = convo.speaker
			-- Keeping up: the one it's on walking off the framing while talking
			-- (Decimus went from -1.6 to -43.8 with the camera all but still): see
			-- TRACK_CATCH. Only a good bubble (see TAIL_MIDDLE) counts, and not
			-- mid-swing or mid-zoom.
			local tracking = turn.moving and turn.kind == "track" and not turn.stopping
			if tracking and turn.want > 0 and not (speaker and speaker.name == convo.on) then
				-- (Someone else talking now: the look below no longer steers it, and
				-- left going it ran on at full speed, 338 degrees round in 22 seconds.)
				Say(("%s isn't the one talking now: stopping at %+.1f deg"):format(convo.on or "?", turn.amount))
				turn.want = 0
			end
			if speaker and speaker.name == convo.on and not convo.check and not convo.search
				and now >= (convo.trackAt or 0)
				and (tracking or (turn.moving and turn.kind == "drift" and not turn.stopping)
					or (not turn.moving and now - turn.stoppedAt >= DRIFT_GAP)) then
				convo.trackAt = now + AIM_EVERY
				local angle, _, sy, others, how = BubbleAngle(speaker.text)
				local good = angle and not zooming and BubbleReading(sy, others, how)
				local frame = ns.db.chatCamFrame
				local slack = convo.slack
				if slack and slack.name == speaker.name and good and (angle > 0) == slack.right then
					frame = frame + slack.by
				end
				local off = (not good or math.abs(angle) <= frame) and 0 or (angle - (angle > 0 and frame or -frame))
				-- (No further than TRACK_MAX from where it started.)
				local room = TRACK_MAX - (off > 0 and 1 or -1) * (turn.amount - convo.base)
				if tracking then
					-- (Their way only: past the framing the other side, it stops first.)
					local want = (off > 0) == turn.right and room > 0
						and math.min(ns.db.chatCamSwingSpeed, math.abs(off) / convo.gain / TRACK_CATCH) or 0
					if want == 0 and turn.want > 0 then
						Say(("%s: %s at %+.1f deg"):format(speaker.name,
							not good and "no good bubble, stopping" or room <= 0 and "as far as it goes, stopping"
							or "caught up, stopping", turn.amount))
					end
					turn.want = want
					convo.center, convo.driftOut = turn.amount, nil
					if want > 0 and now >= (convo.trackSaidAt or 0) then
						-- (Once a second: how the look steers it, to match a jolt on screen.)
						convo.trackSaidAt = now + 1
						Say(("keeping up with %s: %s, past the framing %+.1f (framing %.1f), want %.1f deg/sec, going %.1f (speeding up %+.1f), at %+.1f deg"):format(
							speaker.name, angle and ("%+.1f deg off"):format(angle) or "no bubble", off, frame,
							want, turn.speed or 0, turn.accel or 0, turn.amount))
					end
				elseif math.abs(off) > TRACK_START and room > 0 then
					if turn.moving then
						EaseToStop() -- (a drift leg: a stop first, then after them)
					else
						local want = math.min(ns.db.chatCamSwingSpeed, math.abs(off) / convo.gain / TRACK_CATCH)
						Say(("%s walked to %+.1f deg off the middle (framing %.1f): keeping up (%.1f deg/sec)"):format(
							speaker.name, angle, frame, want))
						convo.turnedAt = convo.turnedAt or now
						StartTrack(off > 0, want)
					end
				end
			end
			-- (Swings go alongside the zoom in, as the quest cam's turn to the side
			-- does: waiting for it, a line 8 seconds into the zoom got its swing as
			-- it ended. Earlier, the two together moved in jolts: watch for it.)
			if speaker and not speaker.aimed and not speaker.missing and speaker.name ~= convo.on then
				-- (Someone new: mid move (a drift leg, a swing to the last speaker, the
				-- turn back), it's turned into the new swing, or eased out first if it's
				-- going the other way; not waited out. Otherwise a moment after the last
				-- move stopped.)
				local drifting = turn.moving and not turn.stopping
				if (drifting or (not turn.moving and now - turn.stoppedAt >= DRIFT_GAP))
					and now >= convo.nextAimAt then
					convo.nextAimAt = now + AIM_EVERY
					Aim(now, drifting)
				end
			elseif convo.on and not turn.moving and now - turn.stoppedAt >= DRIFT_GAP then
				Drift()
			end
		end
	elseif ns.playerMoving and (leaving or (turn.moving and not turn.stopping) or (zoomingOut and ns.QuestCamZooming())) then
		HandOver("you moved", true, true) -- (turning back or zooming back out: stops there too)
	elseif leaving then
		Leave(now)
	end
	DebugTick(now)
	local lines = frameLog.lines
	if lines and #lines < LOG_MAX then
		lines[#lines + 1] = ("%.3f +%.3f %s %+.2f%s sent %s cvar %s zoom %.2f%s%s%s"):format(
			now - frameLog.startedAt, elapsed, turn.kind or "-", turn.amount, turn.moving and "*" or "",
			turn.sent and ("%.2f"):format(turn.sent) or "-", tostring(GetCVar(CVAR)),
			GetCameraZoom and GetCameraZoom() or -1, ns.QuestCamZooming and ns.QuestCamZooming() and "*" or "",
			frameLog.others and (" OTHERS: " .. table.concat(frameLog.others, " ")) or "",
			frameLog.notes and (" | " .. table.concat(frameLog.notes, " ")) or "")
		frameLog.others, frameLog.notes = nil, nil
	end
	if not convo and not leaving and not turn.moving then
		-- (Back where it started, or let go: camera follow back, nothing to watch.)
		frameLog.lines = nil
		turn.amount = 0
		ns.ApplyCVarSet(FOLLOW_CVARS, false)
		watcher:SetScript("OnUpdate", nil)
	end
end

-- Targeting the last speaker (which turns your character's head to them).
-- Addons can't target, or clear a target: TargetUnit and ClearTarget are
-- protected, only a key press or click may. So a secure button whose
-- /targetexact names them, pressed by its key (Key Bindings page, the dev copy
-- only: CLICK CinematicChatTargetButton:LeftButton, no Bindings.xml entry).
-- The name's set as each real line comes, out of fights (a secure button
-- can't change in one).
local targetButton = CreateFrame("Button", "CinematicChatTargetButton", UIParent, "SecureActionButtonTemplate")
targetButton:SetAttribute("type", "macro")
targetButton:SetAttribute("macrotext", "")
targetButton:RegisterEvent("PLAYER_LOGIN")
targetButton:SetScript("OnEvent", function(self)
	-- (On key down or up as the game's action buttons are, not both: it'd go twice.)
	self:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
end)
local function SetTargetName(name)
	if name ~= "?" and not InCombatLockdown() then
		targetButton:SetAttribute("macrotext", "/targetexact " .. name)
	end
end

-- A line spoken: the conversation starts, or goes on.
local function Heard(text, name)
	local now = GetTime()
	if not convo then
		convo = { nextAimAt = 0, startedAt = now, gain = GAIN_START, base = 0 }
		if frameLog.on or fake then -- (a Test button run is always logged)
			ns.db.chatCamLog = {}
			frameLog.lines, frameLog.startedAt = ns.db.chatCamLog, now
		end
		-- (Talking again before it turned back or zoomed back out: carries on from
		-- here, and still goes back out to your own distance after.)
		if leaving then
			convo.zoom, convo.zoomedTo, convo.zoomChecked = leaving.zoom, leaving.zoomedTo, leaving.zoomedTo ~= nil
			leaving = nil
		elseif zoomingOut and ns.QuestCamZooming() then
			convo.zoom, zoomingOut = zoomingOut, nil
		end
		-- (Still turning back from the last one: the swing to this speaker takes
		-- it over, or it eases out if they're the other way: see Aim.)
		Say(("%s started talking%s (camera at %.1f yards, max %s)"):format(name, fake and " (test)" or "",
			GetCameraZoom and GetCameraZoom() or -1, tostring(GetCVar("cameraDistanceMaxZoomFactor"))))
	elseif name == convo.on then
		Say(("%s again: staying on them"):format(name))
	end
	if convo.search and convo.speaker.name ~= name then
		-- (Someone else talking mid look round: it eases to a stop, and they're
		-- looked for from there.)
		Say(("%s talking: stopped looking for %s"):format(name, convo.speaker.name))
		convo.search, convo.rebase = nil, true
		EaseToStop()
	end
	convo.lastLineAt = now
	convo.speaker = { name = name, text = text, at = now }
	watcher:SetScript("OnUpdate", OnUpdate)
end

-- Lines from an NPC you're talking to (its gossip or quest window open, or
-- closed under TALKED_WINDOW ago), your target or a party NPC start it at
-- once (the "NPCs you talk to" row); ones from NPCs just chatting nearby (a
-- city's citizens) only once you've stood still chatNearbyDelay seconds (the
-- "NPCs chatting nearby" row). Any line in a conversation already going (or
-- turning back) carries it on. (Its own clock, not the Stand still row's:
-- the AFK camera resets that one.)
local stillSince -- when you last stopped moving (nil: moving)
local talking = false -- a gossip or quest window open
local talkedAt = 0 -- ...when the last one closed
local TALK_OPEN = { GOSSIP_SHOW = true, QUEST_GREETING = true, QUEST_DETAIL = true, QUEST_PROGRESS = true,
	QUEST_COMPLETE = true }
local TALK_CLOSED = { GOSSIP_CLOSED = true, QUEST_FINISHED = true }

local function Plain(value)
	return type(value) == "string" and not Secret(value) and value or nil
end

-- Why a line isn't taken by its row, or nil.
local function Ambient(event, name, now)
	if convo or leaving or (zoomingOut and ns.QuestCamZooming()) then
		return nil
	elseif event == "CHAT_MSG_MONSTER_PARTY" or talking or now - talkedAt < TALKED_WINDOW
		or (name ~= "?" and Plain(UnitName("target")) == name) then
		return ns.db.chatCamera ~= "chat" and "NPCs you talk to: no camera" or nil
	elseif ns.db.chatNearbyCamera ~= "chat" then
		return "NPCs chatting nearby: no camera"
	end
	stillSince = stillSince or now
	local wait = ns.db.chatNearbyDelay or 0
	if now - stillSince < wait then
		return ("NPC chatting nearby: stood still %d of %d sec"):format(now - stillSince, wait)
	end
end

-- Why a line isn't taken, or nil.
local function NotTaken(text, event, name)
	if type(text) ~= "string" or Secret(text) then
		return "text can't be read"
	elseif not On() then
		return "Chat Cam off"
	elseif ns.IsSuspended() then
		return "suspended"
	elseif ns.playerMoving then
		return "you're moving"
	elseif fake then
		return "Test running"
	-- (Turned off here, or the Calm Timer still running after a fight: Cameras page.)
	elseif not convo and ns.IsCameraOffHere("chatcam") then
		return "turned off here"
	elseif not convo and not ns.CombatWaitOver("chatcam", GetTime()) then
		return "Calm Timer"
	end
	return Ambient(event, name, GetTime())
end

watcher:SetScript("OnEvent", function(_, event, text, name, ...)
	if event == "PLAYER_STARTED_MOVING" then
		stillSince = nil
		return
	elseif event == "PLAYER_STOPPED_MOVING" or event == "PLAYER_ENTERING_WORLD" then
		stillSince = GetTime() -- (a loading screen counts as moving: a new place)
		return
	elseif TALK_OPEN[event] then
		talking = true
		return
	elseif TALK_CLOSED[event] then
		talking, talkedAt = false, GetTime()
		return
	end
	name = Plain(name) or "?"
	SetTargetName(name) -- (any line, the camera on or not: the key targets whoever spoke last)
	local why = NotTaken(text, event, name)
	DebugLine(event, text, name, (select(10, ...)), why)
	if not why then
		Heard(text, name)
	end
end)

ns.CAMERA_TESTS = ns.CAMERA_TESTS or {}
ns.CAMERA_TESTS["Chat Cam"] = {
	start = function()
		if not On() or ns.playerMoving or ns.IsSuspended() then
			ns.Print(ns.L["Chat Cam can't start now: it's off (Cameras page), or you're moving."])
			return false
		end
		if convo or leaving or turn.moving then
			HandOver("test")
		end
		local run = { amountAt = turn.amount, shown = {} }
		fake = run
		for i, line in ipairs(FAKE_LINES) do
			local speaker = FAKE_SPEAKERS[line[2]]
			local text = ("(test line %d)"):format(i)
			local function Speak()
				if fake == run then
					run.shown[text] = { angle = speaker[2], untilAt = GetTime() + FAKE_BUBBLE }
					Heard(text, speaker[1])
				end
			end
			if line[1] == 0 then
				Speak()
			else
				C_Timer.After(line[1], Speak)
			end
		end
		return true
	end,
	running = function() return fake ~= nil and convo ~= nil end,
	stop = function()
		fake = nil
		if convo then
			End("test over")
		end
	end,
	tip = "Runs Chat Cam for 30 seconds with a made-up conversation between two speakers either " ..
		"side of you. Moving, or clicking Stop, ends it.",
}

for _, event in ipairs(EVENTS) do
	watcher:RegisterEvent(event)
end
for _, event in ipairs({ "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_ENTERING_WORLD",
	"GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
	"QUEST_FINISHED" }) do
	watcher:RegisterEvent(event)
end

-- For the frame log: camera commands that weren't ours (the quest cam's zoom
-- steering, the addon's other cameras, your own input).
for _, name in ipairs({ "MoveViewLeftStart", "MoveViewLeftStop", "MoveViewRightStart", "MoveViewRightStop",
	"MoveViewUpStart", "MoveViewUpStop", "MoveViewDownStart", "MoveViewDownStop", "CameraZoomIn", "CameraZoomOut",
	"SetView", "ResetView" }) do
	if _G[name] then
		hooksecurefunc(name, function()
			if frameLog.lines and not frameLog.sending then
				frameLog.others = frameLog.others or {}
				if #frameLog.others < 8 then
					frameLog.others[#frameLog.others + 1] = name
				end
			end
		end)
	end
end

-- The camera lock (Core.lua): the Chat Cam holds the view while it's turned
-- or zoomed (in a conversation, or turning back after), and until your speed
-- setting's back; your camera input lets it go at once.
ns.RegisterCamera("chatcam", function()
	return turn.moving or (turn.restoring or 0) > 0 or (convo ~= nil and (Turned() or convo.zoomedTo ~= nil))
		or leaving ~= nil or zoomingOut ~= nil
		or (ns.QuestCamZoomBy and ns.QuestCamZoomBy() == "chatcam" and ns.QuestCamZoomHeld())
end, function()
	HandOver("you moved the camera", nil, ns.lastCameraInputWhat ~= "zoom")
	ns.ReleaseSpeed(WHO, CVAR) -- (your speed now: see OnUpdate's hand over)
end)

-- Whether a conversation has the camera now (the Minimap page hides the
-- minimap by it: ns.activeCam, Camera.lua).
function ns.ChatCamActive()
	return convo ~= nil
end

-- Who's talking in the conversation now (for the camera mode log), or nil.
function ns.ChatCamSpeaker()
	return convo and convo.speaker and convo.speaker.name
end

-- /cine chatcam [flip|log|steady|debug|mark <note>].
function ns.ChatCamCommand(arg)
	local note = arg:match("^mark%s*(.*)$")
	if note then
		-- (A note in the debug log, typed mid-run: "liadrin's on the left", say.)
		if debugLog.started then
			DebugAdd("MARK " .. note)
			ns.Print("Chat Cam: noted in the debug log at " .. date("%H:%M:%S"))
		else
			ns.Print("Chat Cam: the debug log starts with the first line someone says")
		end
		return
	elseif arg == "debug" then
		ns.db.chatCamDebugOff = not ns.db.chatCamDebugOff or nil
		Say("debug log of bubbles, plates and the camera: " .. (ns.db.chatCamDebugOff and "off" or "on")
			.. " (/reload afterwards to save it)", true)
		return
	elseif arg == "flip" then
		ns.db.chatCamSwap = not ns.db.chatCamSwap
		Say("turn directions " .. (ns.db.chatCamSwap and "swapped" or "as tested"), true)
		return
	elseif arg == "steady" then
		ns.db.chatCamSteady = not ns.db.chatCamSteady
		Say("swings " .. (ns.db.chatCamSteady and "at a steady speed (no easing; a comparison)" or "eased"), true)
		return
	elseif arg == "log" then
		frameLog.on = not frameLog.on
		Say("log every frame of the next conversations: " .. (frameLog.on and "on" or "off")
			.. " (/reload afterwards to save it)", true)
		return
	end
	-- (Both its Cameras page rows together, NPCs you talk to and chatting nearby.)
	local value = On() and "none" or "chat"
	ns.db.chatCamera, ns.db.chatNearbyCamera = value, value
	Say("(prototype) " .. (On() and "on" or "off") .. (ns.db.enabled and "" or " (Cinematic is off)")
		.. ". If it turns away from whoever's talking: /cine chatcam flip", true)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	if ns.db then
		-- (From before it was Chat Cam: the untested first guess's swap is
		-- dropped, the tested way being the default now.)
		if ns.db.dialogueCam then
			ns.db.chatCamera = "chat"
		end
		ns.db.chatCamSwap = ns.db.chatCamSwap or ns.db.dialogueCamSwap
		ns.db.dialogueCam, ns.db.dialogueCamFlip, ns.db.dialogueCamSwap, ns.db.dialogueCamLog = nil, nil, nil, nil
	end
end)
