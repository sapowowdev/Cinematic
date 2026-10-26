-- Chat Cam (a prototype, in the dev copy only: CinematicDev.toc): as NPCs
-- talk, the camera zooms in (as the quest cam does), swings toward whoever's
-- talking, drifts slowly to and fro while they go on, and swings again only
-- when someone else speaks. Once it's over, it turns back and zooms back out.
--
-- The game gives no NPC's place in the world (and retail won't measure
-- nameplates), only where its chat bubble is drawn. A bubble's offset from
-- the screen's middle, through the camera's field of view, is an angle off
-- the view; the swing leaves them chatCamFrame degrees off it, on their side (see
-- the gain, below), at most MAX_TURN from where the camera started, and no
-- faster than chatCamSwingSpeed. If one swing leaves them well off, one more follows.
-- It's measured while the camera's still or only drifting (mid-swing, the
-- bubble's place is already out of date), and not while zooming in. More
-- lines from the one the
-- camera's on don't move it: the drift keeps the shot alive. A speaker with
-- no bubble on screen leaves the camera on whoever it was on.
--
-- The turns are sent as the camera modes' sways send theirs (see
-- RESTART_INTERVAL), along eased curves; a drift leg going a new speaker's
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
local MAX_TURN = 45    -- degrees from where the camera started, at most
local MAX_SWING = 45   -- degrees one swing goes, at most (the test's first layout swung 84 and 98:
                       -- the view whipped right round)
local MIN_TURN = 2     -- degrees: a smaller swing isn't worth a move
-- Up close, the game draws NPCs' bubbles squeezed toward the top middle of
-- the screen, not over their heads (tested: Liadrin a third of the screen
-- left, Zul'jarra as far right, their bubbles at x -0.09 and +0.04), so both
-- read as "already in view" and the camera never turned. Their order still
-- holds, though. So once a second speaker's been placed, a swing goes at
-- least this far from where the camera started, toward the side of the one
-- talking (left or right of the other).
local SIDE_TURN = 20
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
-- Every move is sent as the camera modes' sways send theirs (Camera.lua's
-- MoveAxis): MoveView*Start at a share of your turn speed setting, re-sent as
-- the speed changes (at most every RESTART_INTERVAL, and not for changes
-- under RESTART_CHANGE), your setting never touched. (Holding one move and
-- stepping the speed setting instead, as the quest cam and fly-bys do, every
-- swing straight after a drift leg jumped about a degree as it started:
-- tested with videos, and with the drift at 0 there was barely any. Drift
-- and swings sent alike, a drift going the swing's way turns into it.)
local RESTART_INTERVAL = 0.05 -- seconds between speed changes, at least (as the sways')
local RESTART_CHANGE = 0.02   -- speed changes smaller than this share aren't sent
local RESTART_BIG = 0.3       -- ...and ones over this share go at once
-- The speed sent is smoothed on top of its curve (as the sways' drift is,
-- Camera.lua's DRIFT_SMOOTH), so the re-sent steps never change it sharply. A
-- move then runs on past its time until the smoothing has settled: smoothing
-- only delays the turn, so it still covers the whole distance.
local SMOOTH_TIME = 0.3 -- seconds
local SETTLED = 0.05    -- degrees/sec: slower than this past its time, a move's done
local BUBBLE_WAIT = 2  -- seconds after a line its bubble is waited for before saying there's none
local AIM_EVERY = 0.25 -- seconds between looks for a new speaker's bubble
local LET_GO_TIME = 0.3 -- seconds a move under way takes to stop as you move off (quick: it's yours)
local ZOOM_MARGIN = 0.5 -- yards: already about this close, so no zoom in
local ZOOM_YOURS = 1.5  -- yards from where it zoomed to: you've zoomed yourself, so no zoom back out
local CVAR, DEFAULT_SPEED = "cameraYawMoveSpeed", 180

local FOLLOW_CVARS = { values = { cameraSmoothStyle = "0" } } -- (camera follow would pull the view back)

-- amount: degrees turned, counted (positive: toward the right of the screen).
-- kind: "swing", "drift" or "back". stopping: easing to a stop early.
-- sent: the speed sent (degrees/sec), right: which way.
local turn = { amount = 0, moving = false, stoppedAt = 0 }
-- The conversation going on: { startedAt, lastLineAt, nextAimAt, turnedAt, on (who
-- the camera's on), center (the drift's middle), driftOut, zoom (your
-- distance), zoomedTo, speaker = { name, text, at, missing } }
local convo
local leaving -- once it's over: { zoom, zoomedTo, startedAt } until the turn back starts
local zoomingOut -- the distance the zoom back out is heading for

local watcher = CreateFrame("Frame")

-- The Camera Triggers page's "NPCs talking" row (chatCamera: "chat" or "none").
ns.DEFAULTS.chatCamera = "chat"
-- Its section on the Camera Settings page.
ns.DEFAULTS.chatCamDistance = 4      -- yards it zooms in to (if you're further out)
ns.DEFAULTS.chatCamZoomSpeed = 0.5   -- yards a second the zoom in goes
ns.DEFAULTS.chatCamZoomOutSpeed = 0.5 -- ...and the zoom back out (0: stays in)
ns.DEFAULTS.chatCamZoomMaxTime = 8   -- seconds either zoom takes at most (from far out: quicker than its speed)
ns.DEFAULTS.chatCamHideWorld = true  -- names, nameplates and the target circle hidden meanwhile (Effects.lua)
ns.DEFAULTS.chatCamSwingSpeed = 15   -- degrees a second a swing goes at most
ns.DEFAULTS.chatCamFrame = 6         -- degrees off the middle a speaker's left at, on their side
ns.DEFAULTS.chatCamDrift = 0         -- degrees it drifts to and fro on a speaker (0: holds still)
ns.DEFAULTS.chatCamQuiet = 10        -- seconds with no one talking before it's over
-- A row on the Camera Modes page's grid (Turn off in, Calm Timer) and a box in
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
	return ns.db.enabled and ns.db.chatCamera == "chat"
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

-- What it does, to chat (and so the log), with the seconds since the
-- conversation started: the frame log's own time, which also notes it.
local function Say(text)
	if convo then
		text = ("[%.1fs] %s"):format(GetTime() - convo.startedAt, text)
	end
	Note(text)
	ns.Print("Chat Cam: " .. text)
end

local function Send(name, amount)
	frameLog.sending = true
	ns.CallCameraFunction(name, amount)
	frameLog.sending = false
	Note(amount and ("%s(%.4f)"):format(name, amount) or name)
end

local function StopMove()
	if not turn.moving then
		return
	end
	if turn.sent then
		Send(Command(turn.right) .. "Stop")
	end
	turn.moving, turn.sent, turn.stopping, turn.stoppedAt = false, nil, nil, GetTime()
end

-- The speed now (degrees/sec), sent as a share of your setting when it's
-- changed enough (see RESTART_INTERVAL).
local function Push(speed)
	local now = GetTime()
	local sent = turn.sent
	if speed <= 0.01 then
		return
	end
	if sent then
		local change = math.abs(speed - sent)
		if change <= sent * RESTART_CHANGE
			or (now - turn.sentAt < RESTART_INTERVAL and change <= sent * RESTART_BIG) then
			return
		end
	end
	local yours = tonumber(GetCVar(CVAR)) or DEFAULT_SPEED
	Send(Command(turn.right) .. "Start", speed / yours)
	turn.sent, turn.sentAt = speed, now
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
	turn.target, turn.t, turn.T, turn.ease, turn.kind = target, 0, T, ease, kind
	turn.right = target > turn.amount
	turn.from = from or 0
	turn.smooth = from or 0
	-- (The top speed that covers the distance: speeding up from `from` over the
	-- first ease * T seconds, then on, then slowing to rest over the last.)
	local R = ease * T
	turn.cruise = math.max(turn.from, (distance - turn.from * R / 2) / (T - R))
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
-- (or T seconds; cut dead, it jolts). Not started yet: just dropped.
local function EaseToStop(T)
	if not turn.moving or (turn.stopping and turn.stopping.T <= (T or STOP_TIME)) then
		return
	end
	if not turn.sent then
		StopMove()
		return
	end
	turn.stopping = { from = turn.smooth or turn.sent, t = 0, T = T or STOP_TIME }
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
	if not turn.moving then
		return
	end
	turn.t = turn.t + elapsed
	local speed, over
	if turn.stopping then
		local stopping = turn.stopping
		stopping.t = stopping.t + elapsed
		over = stopping.t >= stopping.T
		speed = over and 0 or stopping.from * (1 + math.cos(math.pi * stopping.t / stopping.T)) / 2
	else
		over = turn.t >= turn.T
		speed = over and 0 or MoveSpeed(turn.t)
	end
	turn.smooth = (turn.smooth or 0) + (speed - (turn.smooth or 0)) * math.min(1, elapsed / SMOOTH_TIME)
	if over and turn.smooth < SETTLED then
		if not turn.stopping then
			turn.amount = turn.target -- (counted as it went: this tidies the last hundredth)
		end
		StopMove() -- (stopped early: where it's got to)
		return
	end
	Push(turn.smooth)
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
local function HandOver(why, quick)
	if Turned() or (convo and convo.zoomedTo) or leaving or ns.QuestCamZooming() then
		Say(("let go at %+.1f deg (%s)"):format(turn.amount, why))
	end
	if quick then
		EaseToStop(LET_GO_TIME)
	else
		StopMove()
	end
	if (convo and convo.zoomedTo) or (leaving and leaving.zoomedTo) or (zoomingOut and ns.QuestCamZooming()) then
		ns.QuestCamStopZoom()
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
-- screen saying `text`, and its x (-1 to 1); nil if there's none.
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

local function BubbleAngle(text)
	if fake then
		local bubble = fake.shown[text]
		if not bubble or GetTime() >= bubble.untilAt then
			return nil
		end
		local angle = bubble.angle - FAKE_GAIN * (turn.amount - fake.amountAt)
		return angle, math.tan(math.rad(angle)) -- (x on screen, at a 90-degree field of view)
	end
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles and ns.BubbleSays) then
		return nil
	end
	local width, height = WorldFrame:GetWidth(), WorldFrame:GetHeight()
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) and ns.Flag(bubble:IsVisible())
			and ns.BubbleSays(bubble, text) then
			local ok, x, y = pcall(bubble.GetCenter, bubble)
			if ok and type(x) == "number" and type(y) == "number" and not Secret(x) and not Secret(y) then
				local scale = bubble:GetEffectiveScale() / WorldFrame:GetEffectiveScale()
				local sx = (x * scale - width / 2) / (width / 2)
				local sy = (y * scale - height / 2) / (height / 2)
				if sx >= -1 and sx <= 1 and sy >= -1 and sy <= 1 then
					local okFov, fov = pcall(GetCVar, "cameraFov")
					fov = okFov and tonumber(fov) or 90
					return math.deg(math.atan(sx * math.tan(math.rad(fov) / 2))), sx
				end
			end
		end
	end
	return nil
end

-- Another camera has the view, or it's switched off: hands over.
local function TakenOver()
	if ns.IsSuspended() or not On() then
		return "off"
	elseif ns.QuestCamBusy and ns.QuestCamBusy() then
		return "quest cam"
	elseif not fake and ns.IsCameraOffHere("chatcam") then
		return "turned off here (Camera Modes page)"
	elseif ns.CameraMode() then
		return "camera mode " .. tostring(ns.CameraMode())
	end
	return nil
end

-- The first look at the conversation: in to the quest cam's distance (not if
-- you're zooming yourself, or already close).
local function ZoomIn(now)
	convo.zoomChecked = true
	local db = ns.db
	if not (GetCameraZoom and ns.QuestCamZoomTo) then
		return
	end
	if ns.PlayerZoomedSince(now - (ns.PLAYER_ZOOM_WAIT or 1)) then
		Say("you're zooming: no zoom in")
	elseif GetCameraZoom() > db.chatCamDistance + ZOOM_MARGIN then
		convo.zoom = convo.zoom or (ns.PlayerZoom and ns.PlayerZoom()) or GetCameraZoom()
		convo.zoomedTo = db.chatCamDistance
		Say(("zooming in to %.1f yards"):format(db.chatCamDistance))
		ns.QuestCamZoomTo(db.chatCamDistance, math.min(db.chatCamZoomMaxTime,
			(GetCameraZoom() - db.chatCamDistance) / db.chatCamZoomSpeed))
	end
end

-- A new speaker: swing toward their bubble once it shows.
-- drifting: a move's under way (a drift leg, a swing, the turn back). Going
-- the new swing's way, it turns into it; the other way, it eases to a stop
-- first (Aim again after).
local function Aim(now, drifting)
	local speaker = convo.speaker
	local angle, sx = BubbleAngle(speaker.text)
	if not angle then
		if not speaker.missing and now - speaker.at > BUBBLE_WAIT then
			speaker.missing = true
			Say(("%s: no bubble on screen, staying on %s"):format(speaker.name, convo.on or "where it is"))
		end
		return
	end
	-- (To chatCamFrame degrees off the middle on their side, through the gain.)
	local frame = ns.db.chatCamFrame
	local off = math.abs(angle) <= frame and 0 or (angle - (angle > 0 and frame or -frame))
	local wanted = turn.amount + off / convo.gain
	-- (Where they'd be on screen with the camera where it started, to compare
	-- with the others who've talked.)
	local here = angle + convo.gain * turn.amount
	convo.placed = convo.placed or {}
	convo.placed[speaker.name] = here
	local other
	for name, place in pairs(convo.placed) do
		if name ~= speaker.name then
			other = place
		end
	end
	local sided
	if other and here ~= other then
		local side = here < other and -1 or 1
		if wanted * side < SIDE_TURN then
			wanted, sided = side * SIDE_TURN, side < 0 and "left" or "right"
		end
	end
	local target = math.max(turn.amount - MAX_SWING, math.min(turn.amount + MAX_SWING, wanted))
	target = math.max(-MAX_TURN, math.min(MAX_TURN, target))
	local step = target - turn.amount
	local carry = drifting and turn.sent and math.abs(step) >= MIN_TURN and (step > 0) == turn.right
	if drifting and not carry then
		EaseToStop() -- (the other way, or not worth a swing: a stop first, then a fresh look)
		return
	end
	speaker.aimed = true
	convo.on = speaker.name
	convo.center, convo.driftOut = target, nil
	if math.abs(step) < MIN_TURN then
		Say(("on %s: %+.1f deg off the middle (bubble x %+.2f), already in view"):format(speaker.name, angle, sx))
		return
	end
	local T = SwingTime(math.abs(step), Ease(SWING_EASE), SWING_MIN_TIME)
	Say(("swinging to %s%s: %+.1f deg off the middle (bubble x %+.2f), gain %.2f, %+.1f to %+.1f over %.1fs%s"):format(
		speaker.correcting and "(again) " or "", speaker.name, angle, sx, convo.gain, step, target, T,
		(target ~= wanted and " (as far as it goes)" or "") .. (sided and (", to their side (%s of the other)"):format(sided) or "")))
	Note("swing to " .. speaker.name)
	convo.turnedAt = convo.turnedAt or now
	if carry then
		Note(turn.kind .. " turned into the swing")
	end
	MoveTo(target, T, Ease(SWING_EASE), "swing", carry and (turn.smooth or turn.sent) or nil)
	-- (Looked at again once it's done: how far it really moved them.)
	convo.check = { speaker = speaker, angle = angle, step = step }
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

local function OnUpdate(_, elapsed)
	StepMove(elapsed)
	local now = GetTime()
	if convo then
		local takenOver = TakenOver()
		if convo.turnedAt and ns.GetLastCameraInput() > convo.turnedAt then
			HandOver(ns.lastCameraInputWhat == "zoom" and "you zoomed" or "you moved the camera")
		elseif takenOver then
			if Turned() or convo.zoomedTo then
				HandOver(takenOver)
			end
			-- (Otherwise the conversation's kept: the quest cam turning back at its
			-- start, say, and the lines carry on once it's done.)
		elseif UnitAffectingCombat("player") then
			End("fight")
		elseif ns.playerMoving then
			HandOver("you moved", true)
		elseif now - convo.lastLineAt >= ns.db.chatCamQuiet then
			End(("no one's talked for %d seconds"):format(ns.db.chatCamQuiet))
		else
			if not convo.zoomChecked then
				convo.turnedAt = convo.turnedAt or now
				ZoomIn(now)
			end
			local zooming = ns.QuestCamZooming and ns.QuestCamZooming()
			local check = convo.check
			if check and not turn.moving then
				convo.check = nil
				local speaker = check.speaker
				local after = BubbleAngle(speaker.text)
				if not after then
					Say(("after the swing, %s's bubble is gone"):format(speaker.name))
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
						and math.abs(after) > ns.db.chatCamFrame + CORRECT and math.abs(turn.amount) < MAX_TURN then
						speaker.correcting, speaker.aimed, convo.on = true, false, nil
					end
				end
			end
			local speaker = convo.speaker
			if zooming then
				-- (The swing waits for the zoom in: a turn alongside it can't be
				-- measured, and the two together moved in jolts.)
			elseif speaker and not speaker.aimed and not speaker.missing and speaker.name ~= convo.on then
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
		HandOver("you moved", true) -- (turning back or zooming back out: stops there too)
	elseif leaving then
		Leave(now)
	end
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
		convo = { nextAimAt = 0, startedAt = now, gain = GAIN_START }
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
		Say(("%s started talking%s"):format(name, fake and " (test)" or ""))
	elseif name == convo.on then
		Say(("%s again: staying on them"):format(name))
	end
	convo.lastLineAt = now
	convo.speaker = { name = name, text = text, at = now }
	watcher:SetScript("OnUpdate", OnUpdate)
end

watcher:SetScript("OnEvent", function(_, _, text, name)
	name = type(name) == "string" and not Secret(name) and name or "?"
	SetTargetName(name) -- (any line, the camera on or not: the key targets whoever spoke last)
	if type(text) ~= "string" or Secret(text) or not On() or ns.IsSuspended() or ns.playerMoving or fake then
		return
	end
	-- (Turned off here, or the Calm Timer still running after a fight: Camera Modes page.)
	if not convo and (ns.IsCameraOffHere("chatcam") or not ns.CombatWaitOver("chatcam", GetTime())) then
		return
	end
	Heard(text, name)
end)

ns.CAMERA_TESTS = ns.CAMERA_TESTS or {}
ns.CAMERA_TESTS["Chat Cam"] = {
	start = function()
		if not On() or ns.playerMoving or ns.IsSuspended() then
			ns.Print(ns.L["Chat Cam can't start now: it's off (Camera Triggers page), or you're moving."])
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

-- Whether a conversation has the camera now (the Minimap page hides the
-- minimap by it: ns.activeCam, Camera.lua).
function ns.ChatCamActive()
	return convo ~= nil
end

-- Whether names, nameplates and the target circle are hidden now
-- (chatCamHideWorld; Effects.lua): through the conversation and its turn back.
function ns.ChatCamHidesWorld()
	return ns.db.chatCamHideWorld and (convo ~= nil or leaving ~= nil) or false
end

-- /cine chatcam [flip|log|steady].
function ns.ChatCamCommand(arg)
	if arg == "flip" then
		ns.db.chatCamSwap = not ns.db.chatCamSwap
		Say("turn directions " .. (ns.db.chatCamSwap and "swapped" or "as tested"))
		return
	elseif arg == "steady" then
		ns.db.chatCamSteady = not ns.db.chatCamSteady
		Say("swings " .. (ns.db.chatCamSteady and "at a steady speed (no easing; a comparison)" or "eased"))
		return
	elseif arg == "log" then
		frameLog.on = not frameLog.on
		Say("log every frame of the next conversations: " .. (frameLog.on and "on" or "off")
			.. " (/reload afterwards to save it)")
		return
	end
	-- (The same switch as the "NPCs talking" row on the Camera Triggers page.)
	ns.db.chatCamera = ns.db.chatCamera == "chat" and "none" or "chat"
	Say("(prototype) " .. (On() and "on" or "off") .. (ns.db.enabled and "" or " (Cinematic is off)")
		.. ". If it turns away from whoever's talking: /cine chatcam flip")
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
