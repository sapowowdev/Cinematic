-- Quest cam: talking to a quest giver, the camera eases in close, swings
-- round behind you, comes round to one side and down toward eye level,
-- looking past you at them at an angle (a dialogue shot). Optionally it also
-- moves over your right shoulder. It all goes back as the window closes.
--
-- Interacting turns you to face the NPC, so "behind you" is looking at them.
-- The swing borrows camera follow (ns.CenterCamera), which is reliable for
-- the small offsets left by that turn. The shoulder is the game's
-- test_cameraOverShoulder offset, which it eases over to on its own; the
-- game ignores it while Keep Character Centered (Accessibility) is on, so
-- it's only used with that off (or questCamUncenter turning it off meanwhile).
-- It's one of Blizzard's experimental camera settings (setting it brings up
-- their warning), so it's off unless you turn it on (questCamOverShoulder).
--
-- Once the swing's over, the turn to the side (questCamAngle) runs alongside
-- the rest of the zoom, then the tilt down (questCamLower) follows, after a
-- short pause (the game won't turn and tilt at once). Going back, the zoom
-- out and the turn back go together, then the tilt up. In between, once all
-- that's settled, the turn drifts slowly to and fro (questCamDrift). There's no reading
-- the camera's angle, so both are counted, and undone by as much.
-- Both ease in and out, like the death camera's tilt: one move command is
-- held while its speed setting is stepped along the curve (re-sending the
-- move at each new speed restarts it, which snapped, worse with the zoom's
-- per-frame steps alongside); your setting then comes back. Camera follow is
-- off meanwhile, so it can't pull the view back.
-- Every move gives a small jolt as it starts, bigger the faster it starts
-- (/cine starttest: a steady 10 degrees/sec start jolted plainly, 1 degree/sec
-- just a hair). The speed setting can't go much below 1 (lower, the game
-- uses its full speed), so the move is sent at a share of it instead: the
-- share that makes your own setting the move's top speed. The setting then
-- runs from 1 (a start of a fraction of a degree per second) up toward
-- yours and back, never past it.
-- The zoom works the same way: one CameraZoomIn (or Out) for the whole
-- distance, with the game's zoom speed setting stepped along the curve. (The
-- addon's other zooms nudge the camera every frame; alongside a turn those
-- nudges showed as small snaps.)
-- Moving off (walking away from the quest giver) ends it: everything goes
-- back, and it doesn't start again until the next conversation.
-- The zoom back out waits until you're ZOOM_OUT_DISTANCE yards from where you
-- started talking (quest givers often stand together: talk to another and
-- that's the new spot, the zoom back out still to come), or you take a
-- flight; at once if no other quest giver's mark is on the minimap within
-- GIVER_NEAR yards (where the minimap can be swept). Leaving the conversation
-- (Escape, Goodbye) ends it at once too, not after CLOSE_GRACE. Then it goes at its
-- own speed (questCamZoomOutSpeed), but takes ZOOM_HURRY at most. Either
-- zoom takes questCamZoomMaxTime at most: from far out, quicker than its speed.
-- It isn't queued behind the turn back (walking, the RP walk and auto-run
-- cameras' own swing behind you held the queue up, and it never came), and
-- turning the camera yourself as you go doesn't stop it: only zooming
-- yourself does.
-- Moving the camera yourself while talking hands it over: nothing is undone.
-- It waits questCamDelay seconds after the window opens before starting, so
-- a quest picked up and gone at once gets no camera at all. Each new window
-- after (the next quest's text, the reward) adds WINDOW_EXTRA to the wait.
local _, ns = ...

local CLOSE_GRACE = 3 -- seconds held after the window closes (going from gossip to a quest closes one window before opening the next)
local WINDOW_EXTRA = 1 -- seconds each window after the first adds to the wait before starting (questCamDelay)
-- The swing behind you: the takeoff swing's gentle speeds (a quicker one
-- showed as a snap), then a moment for it to settle before camera follow is
-- handed back (switched off while still easing the view, it jolts).
local SWING_YAW = 45    -- degrees per second, at most (no pitch: the tilt has that)
local SWING_RAMP = 1.5  -- seconds for it to build up speed from a crawl
local SWING_SETTLE = 1  -- seconds held on past questCamTime
local QUICK_SWING = 1.5 -- seconds the swing takes, at most, with no zoom in to run alongside (close already:
                        -- the turn to the side waited the zoom's full time with nothing else moving)
local ZOOM_MARGIN = 0.5 -- yards: already about this close, so no zoom
local ZOOM_YOURS = 1.5  -- yards from where it zoomed to: you've zoomed yourself, so it stays
local BACK_SHARE = 4 / 3 -- the turn back takes this share of the turn's time (0.5 was rushed, 1 a bit quick)...
local BACK_MIN = 4      -- ...but at least this many seconds
local BACK_EASE = 0.5   -- ...one long, smooth swell, like the tilt
local MOVE_MIN_TIME = 1.5 -- seconds: the shortest turn or tilt
local MOVE_EASE = 0.35   -- share of a move spent speeding up (and again slowing down)
local MOVE_MIN_SPEED = 1 -- degrees per second: the slowest step sent (lower, the game uses its full speed)
local MOVE_MIN_SETTING = 1 -- the lowest speed setting sent (the start's speed is this times the move's share)
local MOVE_CHANGE = 0.02 -- speed changes smaller than this share aren't sent
local MOVE_PRIME_TIME = 0.2 -- seconds the starting speed is set before the move starts
-- ...creeping meanwhile at this share of it, too slow to see; the move is sent
-- over the creep. (From rest, the Chat Cam's swings jumped 2-3 pixels in their
-- first frame, about a frame at full speed, then all but stopped for the
-- prime's 0.2 seconds: a lurch at each start. With the creep, tested, gone.)
local PRIME_SHARE = 0.001
local SPEED_RESTORE_DELAY = 0.3 -- seconds after stopping before your speed setting comes back
local ZOOM_CVAR = "cameraZoomSpeed"
local WHO = "quest" -- (its holds on your speed settings: ns.HoldSpeed, Core.lua)
local ZOOM_MIN_SPEED = 0.3 -- yards per second: the slowest step sent
local ZOOM_DONE = 0.05     -- yards: arrived
local ZOOM_GIVE_UP = 4     -- extra seconds to settle before a zoom that can't get there stops
local ZOOM_HURRY = 3       -- seconds the zoom back out takes once you've walked off (at most; 1.5 was jarring)
local ZOOM_HURRY_RAMP = 1.5 -- seconds it takes to speed up to that (all at once, it lurched)
local ZOOM_OUT_DISTANCE = 10 -- yards from where you started talking before it zooms back out
local ZOOM_OUT_WALK_TIME = 1.5 -- ...or, where the game won't say where you are, seconds of walking
local GIVER_NEAR = 28 -- ...unless no quest giver's mark is on the minimap within this many yards: at once
local LEAVE_WINDOW = 2 -- seconds: a window closing this long after no step on (accept, pick a quest...) is you leaving
local FOLLOW_GAP = 0.5 -- seconds between the swing handing camera follow back and the turn starting
local STEP_GAP = 0.6   -- seconds between one move stopping and the next starting (on neighbouring frames, it
                       -- snapped; and clear of the speed setting coming back, SPEED_RESTORE_DELAY after)
local TILT_TIME = 4    -- seconds the tilt down takes (squeezed into what was left of the zoom, it was rushed)
local TILT_EASE = 0.5  -- ...one long, smooth swell: speeding up over its first half
local TILT_BACK_TIME = 4 -- ...and back up (2 was rushed)
local DRIFT_TIME = 7   -- seconds each leg of the drift takes, once settled (questCamDrift)
local DRIFT_EASE = 0.3 -- ...ramps at either end (all easing, it crawled so long it seemed to stop at each
                       -- side; much shorter, it turned round with a jump)
local DRIFT_GAP = 0.35 -- ...seconds between legs (STEP_GAP's pause showed)
local INPUT_GRACE = 1 -- seconds: camera input this soon is the click that opened the window
local CLICK_WINDOW = 2 -- seconds: a click on the world this soon before the window opened is what opened it
local LOG_MAX = 4000  -- frames kept by /cine debug questlog

local SHOULDER_CVARS = { values = { test_cameraOverShoulder = "1" } }
local CENTERED_CVARS = { values = { CameraKeepCharacterCentered = "0" } }
local FOLLOW_CVARS = { values = { cameraSmoothStyle = "0" } }

local cam = { active = false, steps = {} }

-- The two moves. amount: degrees from where the swing left the camera
-- (yaw: round to your right, or left; pitch: down).
-- grow/shrink: the commands that move amount up and down.
-- (Kept apart from ns.yawAxis and ns.pitchAxis: the orbit stops those every
-- frame while it's idle, which cut the turn off over and over, a lurching spin.)
local movers = {
	yaw = { amount = 0, cvar = "cameraYawMoveSpeed", default = 180,
		grow = "MoveViewLeft", shrink = "MoveViewRight" },
	pitch = { amount = 0, cvar = "cameraPitchMoveSpeed", default = 90,
		grow = "MoveViewDown", shrink = "MoveViewUp" },
}

-- Quests on offer or to hand in at this gossip NPC.
local function GossipHasQuests()
	local info = C_GossipInfo
	if info and info.GetNumAvailableQuests and info.GetNumActiveQuests then
		return (info.GetNumAvailableQuests() or 0) + (info.GetNumActiveQuests() or 0) > 0
	end
	if GetNumGossipAvailableQuests and GetNumGossipActiveQuests then
		return (GetNumGossipAvailableQuests() or 0) + (GetNumGossipActiveQuests() or 0) > 0
	end
	return false
end

-- A gossip window with a "(Quest)" option (its QuestLabelPrepend flag): a quest
-- step talked through, with no quest to pick up or hand in (the "Talk about a
-- quest" event).
local function GossipHasQuestOptions()
	local info, flags = C_GossipInfo, Enum and Enum.GossipOptionRecFlags
	if not (info and info.GetOptions and flags and flags.QuestLabelPrepend) then
		return false
	end
	for _, option in ipairs(info.GetOptions() or {}) do
		if type(option.flags) == "number" and bit.band(option.flags, flags.QuestLabelPrepend) ~= 0 then
			return true
		end
	end
	return false
end

local function ShoulderAllowed()
	return ns.db.questCamUncenter or GetCVar("CameraKeepCharacterCentered") ~= "1"
end

-- Speed (0-1) at t along a move of T seconds: half-cosine ramps of ease*T at
-- either end (as Camera.lua's EaseShape).
local function EaseShape(t, T, ease)
	local R = ease * T
	if R <= 0 then
		return 1
	elseif t < R then
		return (1 - math.cos(math.pi * t / R)) / 2
	elseif t > T - R then
		return (1 - math.cos(math.pi * (T - t) / R)) / 2
	end
	return 1
end

-- Our camera commands: marked, so the log can tell others' apart.
-- /cine debug questlog: our own commands and speed setting changes, noted by
-- name for the next log line.
local function Note(text)
	if cam.log then
		cam.notes = cam.notes or {}
		if #cam.notes < 8 then
			cam.notes[#cam.notes + 1] = text
		end
	end
end

local function Send(name, amount)
	cam.sending = true
	-- (The zoom's the Chat Cam's while it borrows it: see ns.QuestCamZoomTo.)
	ns.CameraCall(name:find("Zoom") and cam.zoomBy or "quest", name, amount)
	cam.sending = false
	if not name:find("Zoom") then
		Note(amount and ("%s(%.3f)"):format(name, amount) or name)
	end
end

-- A speed setting put back (noted for the log).
local function RestoreSpeed(cvar)
	if ns.SpeedHeld(cvar, WHO) then
		Note(cvar .. " back")
		ns.ReleaseSpeed(WHO, cvar)
	end
end

-- The command a mover sends: its grow or shrink one, the yaw's flipped for
-- your left.
local function Command(m)
	local grow = m.growing
	if m == movers.yaw and m.left then
		grow = not grow
	end
	return grow and m.grow or m.shrink
end

-- The drift's wanted: set, and not held still for Quest talk's bubble over
-- the NPC's head (following their plate, it jiggled as the camera drifted).
local function DriftWanted()
	return (ns.db.questCamDrift or 0) >= 1 and not (ns.QuestTalkHoldsCamera and ns.QuestTalkHoldsCamera())
end

-- Settled and drifting to and fro (or about to).
local function Drifting()
	return cam.active and not cam.handedOver and DriftWanted()
end

local function StopMove(m)
	if not m.moving then
		return
	end
	if m.sent or m.creeping then
		Send(Command(m) .. "Stop")
	end
	m.moving, m.sent, m.creeping, m.stoppedAt = false, nil, nil, GetTime()
	-- (Put back a moment later, so the end of the move can't run at full speed.
	-- Not between the drift's legs: your setting coming back just as the
	-- camera came to rest jumped it. Held till then: see the camera lock.)
	cam.restoring = (cam.restoring or 0) + 1
	C_Timer.After(SPEED_RESTORE_DELAY, function()
		cam.restoring = cam.restoring - 1
		if not m.moving and not (m == movers.yaw and Drifting()) then
			RestoreSpeed(m.cvar)
		end
	end)
end

-- Moves to `target` degrees, over T seconds.
-- ease: the share spent speeding up (and slowing down), MOVE_EASE if nil.
-- tail: { extra, speed, R }: instead of slowing to a stop at target, it slows
-- only to `speed` (degrees per second) and carries on `extra` degrees further
-- the same way, easing to a stop over R seconds at the end (the side turn
-- flowing into the drift's first leg).
local function MoveTo(m, target, T, ease, tail)
	StopMove(m)
	local final = target
	if tail then
		final = target + (target >= m.amount and tail.extra or -tail.extra)
	end
	m.from, m.target, m.t, m.T = m.amount, final, 0, math.max(MOVE_MIN_TIME, T)
	m.tail = tail and { speed = tail.speed, R = tail.R } or nil
	if math.abs(final - m.amount) < 0.5 then
		m.amount = final
		return
	end
	-- The share of the speed setting the move is sent at: your setting is
	-- then its top speed.
	local yours = ns.HoldSpeed(WHO, m.cvar)
	m.ease = ease or MOVE_EASE
	m.cruise = math.abs(target - m.amount) / (m.T * (1 - m.ease))
	m.limit = m.T + 1 + (tail and (math.abs(final - target) / tail.speed + tail.R) or 0)
	m.share = math.max(m.cruise, m.tail and m.tail.speed or 0) / yours
	-- The setting goes to its lowest a moment before the move starts, the
	-- creep started its way (see PRIME_SHARE).
	ns.SetHeldSpeed(WHO, m.cvar, MOVE_MIN_SETTING)
	m.primedUntil = GetTime() + MOVE_PRIME_TIME
	m.growing = final > m.amount
	m.lastGrowing = m.growing
	Send(Command(m) .. "Start", PRIME_SHARE)
	m.creeping = true
	m.moving = true
end

-- A move with a tail: its speed at this point. Up to its cruise, down only
-- to the tail's speed by T, on at that, and once the distance left is what
-- easing to a stop over the tail's R covers, eased to a stop.
local function TailSpeed(m)
	local t, T, R, tail = m.t, m.T, m.ease * m.T, m.tail
	if tail.stopAt then
		local u = (t - tail.stopAt) / tail.R
		return u >= 1 and 0 or tail.from * (1 + math.cos(math.pi * u)) / 2
	end
	local speed
	if t < T - R then
		speed = m.cruise * EaseShape(t, T, m.ease)
	elseif t < T then
		speed = tail.speed + (m.cruise - tail.speed) * EaseShape(t, T, m.ease)
	else
		speed = tail.speed
	end
	if t >= R and math.abs(m.target - m.amount) <= speed * tail.R / 2 then
		tail.stopAt, tail.from = t, speed
	end
	return speed
end

-- Leaving: a move under way slows to a stop from where it is, rather than
-- halting dead (the drift cut off mid-swing showed once the hold after the
-- window closed was long enough to watch it). False: just stop it (barely
-- moving yet). (Even the drift heading back behind you stops first: sent
-- with room to carry straight on into the turn back, its speed setting ran
-- over too few steps and it jumped, most as it turned round.)
local function EaseToStop(m)
	if not m.moving or GetTime() < m.primedUntil or not m.sent then
		return false
	end
	local sign = m.growing and 1 or -1
	if m.tail then
		-- Already easing to a stop, or slowed now over the tail's own R.
		if not m.tail.stopAt then
			local speed = TailSpeed(m)
			m.tail.stopAt, m.tail.from = m.t, speed
			m.target = m.amount + sign * speed * m.tail.R / 2
		end
		return true
	end
	local R = m.ease * m.T
	if m.t >= m.T - R then
		return true -- already slowing down at its end
	elseif m.t <= R then
		return false
	end
	-- Mid-way at full speed: the curve cut short so its slowing down starts now.
	local T = m.t / (1 - m.ease)
	m.T, m.limit = T, T + 1
	m.target = m.amount + sign * m.cruise * m.ease * T / 2
	return true
end

local function StepMove(m, elapsed)
	if not m.moving or GetTime() < m.primedUntil then
		return
	end
	m.t = m.t + elapsed
	-- Done when its curve has eased right down, not when it's counted as far
	-- as asked: the speed sent lags a little behind the curve as it slows (see
	-- MOVE_CHANGE), so it got there early and stopped still moving, a small jump.
	local speed = m.tail and TailSpeed(m) or m.cruise * EaseShape(m.t, m.T, m.ease)
	if m.t >= m.limit or (m.tail and m.tail.stopAt and speed == 0) or (not m.tail and m.t >= m.T) then
		m.amount = m.target
		StopMove(m)
		return
	end
	-- The speed setting for this point on the curve (the move's speed is the
	-- setting times its share).
	local setting = math.max(MOVE_MIN_SETTING, speed / m.share)
	if not m.sent then
		-- The move goes out once, at the primed setting; after that only the
		-- setting changes.
		Note(("%s %s share %.4f"):format(m.cvar, tostring(GetCVar(m.cvar)), m.share))
		Send(Command(m) .. "Start", m.share)
		m.sent = MOVE_MIN_SETTING
	elseif math.abs(setting - m.sent) > m.sent * MOVE_CHANGE then
		ns.SetHeldSpeed(WHO, m.cvar, setting)
		m.sent = setting
	end
	-- How far it's come, at the speed actually sent.
	speed = m.sent * m.share
	m.amount = m.amount + (m.growing and speed or -speed) * elapsed
end

-- The zoom. The game doesn't move the camera exactly the distance asked of
-- CameraZoomIn/Out (it can go several times further), and there's no reading
-- where it's heading, only where the camera is: one command for the whole
-- distance went far past the goal. So it's steered along the eased path: at
-- most every ZOOM_SEND_EVERY seconds, a command toward where the path will be
-- ZOOM_LEAD seconds on, from where the camera really is. The game's zoom
-- speed setting is held just above the path's speed meanwhile, so the camera
-- glides between commands instead of hopping to each one (at your own speed,
-- the addon's other zooms' small per-frame steps showed as snaps). Your
-- setting comes back once the camera has held still at the goal.
local ZOOM_SEND_EVERY = 0.1  -- seconds between commands, at least
local ZOOM_LEAD = 0.25       -- seconds ahead on the path each command aims for
local ZOOM_GAIN = 0.6        -- share of the way to that point each command asks for
local ZOOM_HEADROOM = 1.3    -- the speed setting, as a share of the path's speed...
local ZOOM_SPEED_EXTRA = 0.3 -- ...plus this many yards per second
local ZOOM_SETTLE_SPEED = 0.5 -- yards per second once the path's done
local ZOOM_SETTLED = 0.4     -- seconds held still at the goal before it counts as done
local ZOOM_STILL = 0.002     -- yards per frame: less is holding still
local LEAVE_ZOOM_STOP = 0.6  -- seconds a zoom back out takes to ease to a stop as you talk to someone again
local zoomer = { moving = false }

local function Zooming()
	return zoomer.moving
end

-- Done: the speed setting rises back to yours over ZOOM_RELEASE_TIME (all at
-- once, any last bit of the game's own zoom left to go happened in a frame:
-- a hop). restoreNow: at once (you're zooming yourself).
local ZOOM_RELEASE_TIME = 1.5
local function StopZoom(restoreNow)
	if restoreNow then
		zoomer.moving, zoomer.sent, zoomer.release = false, nil, nil
		RestoreSpeed(ZOOM_CVAR)
		return
	end
	if not zoomer.moving then
		return
	end
	zoomer.moving = false
	local yours = ns.SpeedHeld(ZOOM_CVAR, WHO) and ns.YourSpeed(ZOOM_CVAR)
	if yours and zoomer.sent and yours > zoomer.sent then
		zoomer.release = { from = zoomer.sent, to = yours, t = 0 }
		Note("zoom speed easing back")
	else
		zoomer.sent = nil
		RestoreSpeed(ZOOM_CVAR)
	end
end

local function StepZoomRelease(elapsed)
	local release = zoomer.release
	if not release then
		return
	end
	-- Held at the crawl while a turn or tilt is under way or still to come:
	-- one starting as the setting eased back snapped, and waiting for it to
	-- finish first left a long gap between the turn and the tilt.
	if cam.active and (#cam.steps > 0 or movers.yaw.moving or movers.pitch.moving or Drifting()) then
		return
	end
	release.t = release.t + elapsed
	local f = release.t / ZOOM_RELEASE_TIME
	-- (Yours already put back by something else, the camera watch say: stop,
	-- or the next step would leave it at a crawl with nothing to restore.)
	if f >= 1 or not ns.SpeedHeld(ZOOM_CVAR, WHO) then
		zoomer.release, zoomer.sent = nil, nil
		RestoreSpeed(ZOOM_CVAR)
		return
	end
	-- (Geometric, so it creeps up from the crawl rather than leaping.)
	ns.SetHeldSpeed(WHO, ZOOM_CVAR, release.from * (release.to / release.from) ^ (f * f))
end

local function SetZoomSpeed(speed)
	if not zoomer.sent or math.abs(speed - zoomer.sent) > zoomer.sent * MOVE_CHANGE then
		ns.SetHeldSpeed(WHO, ZOOM_CVAR, speed)
		zoomer.sent = speed
	end
end

-- Share (0-1) of a move covered at t along T seconds, for EaseShape's speed
-- curve (as Camera.lua's EaseProgress).
local function EaseProgress(t, T, ease)
	if t <= 0 then return 0 end
	if t >= T then return 1 end
	local R = ease * T
	if R <= 0 then return t / T end
	local total = T - R
	local function ramp(u) return u / 2 - R / (2 * math.pi) * math.sin(math.pi * u / R) end
	local covered
	if t < R then
		covered = ramp(t)
	elseif t <= T - R then
		covered = R / 2 + (t - R)
	else
		covered = total - ramp(T - t)
	end
	return covered / total
end

-- Where the path has the camera at t.
local function ZoomPath(t)
	if zoomer.easeOut then
		local u = math.min(1, t / zoomer.T)
		return zoomer.from + (zoomer.goal - zoomer.from) * (1 - (1 - u) * (1 - u))
	end
	return zoomer.from + (zoomer.goal - zoomer.from) * EaseProgress(t, zoomer.T, MOVE_EASE)
end

-- Zooms to `distance` yards over T seconds.
local function ZoomTo(distance, T)
	local now = GetCameraZoom()
	zoomer.moving = false
	if math.abs(distance - now) < ZOOM_DONE then
		return
	end
	zoomer.release, cam.zoomBy = nil, nil
	ns.HoldSpeed(WHO, ZOOM_CVAR)
	Note(("zoom to %.2f"):format(distance))
	zoomer.from, zoomer.goal, zoomer.t, zoomer.T = now, distance, 0, math.max(MOVE_MIN_TIME, T)
	zoomer.cruise = math.abs(distance - now) / (zoomer.T * (1 - MOVE_EASE))
	zoomer.last, zoomer.sentAt, zoomer.stillSince, zoomer.sent = now, 0, nil, nil
	zoomer.rate, zoomer.rateGoal, zoomer.leaving, zoomer.easeOut = 1, 1, false, nil
	zoomer.moving, zoomer.startedAt = true, GetTime()
end

-- Hurries the zoom along so what's left of it takes about T seconds. It runs
-- along the same path, just faster (the speed rising over ZOOM_HURRY_RAMP),
-- so it doesn't stop and start again.
local function HurryZoom(T)
	if zoomer.moving and zoomer.t < zoomer.T then
		zoomer.rateGoal = math.max(zoomer.rateGoal, (zoomer.T - zoomer.t) / T)
	end
end

-- Eases the zoom to a stop over T seconds, from where the camera is at the
-- speed it's going (its path swapped for one that only slows down). Where
-- it'll stop, or nil if it isn't zooming.
local function EaseZoomStop(T)
	if not zoomer.moving then
		return nil
	elseif zoomer.easeOut then
		return zoomer.goal
	end
	local t = zoomer.t
	local speed = t < zoomer.T and zoomer.cruise * EaseShape(t, zoomer.T, MOVE_EASE) * zoomer.rate or 0
	local zoom = GetCameraZoom()
	local sign = zoomer.goal > zoomer.from and 1 or -1
	zoomer.from, zoomer.goal, zoomer.t, zoomer.T = zoom, zoom + sign * speed * T / 2, 0, T
	zoomer.cruise, zoomer.easeOut, zoomer.rate, zoomer.rateGoal = speed, true, 1, 1
	return zoomer.goal
end

local function StepZoom(elapsed)
	if not zoomer.moving then
		return
	end
	local now, zoom = GetTime(), GetCameraZoom()
	if zoomer.rate < zoomer.rateGoal then
		zoomer.rate = math.min(zoomer.rateGoal, zoomer.rate + zoomer.rateGoal * elapsed / ZOOM_HURRY_RAMP)
	end
	-- (Hurried, the path's time runs faster; once it's over, settling is in real time.)
	local rate = zoomer.t < zoomer.T and zoomer.rate or 1
	zoomer.t = zoomer.t + elapsed * rate
	local t, T = zoomer.t, zoomer.T
	local still = math.abs(zoom - zoomer.last) < ZOOM_STILL
	zoomer.last = zoom
	-- Done once the path's over and it's held still at the goal (or given up on).
	if t >= T and math.abs(zoomer.goal - zoom) < ZOOM_DONE and still then
		zoomer.stillSince = zoomer.stillSince or now
		if now - zoomer.stillSince >= ZOOM_SETTLED then
			StopZoom()
			ns.RestoreZoomLimit() -- (inside it now)
			return
		end
	else
		zoomer.stillSince = nil
	end
	if t >= T + ZOOM_GIVE_UP then
		StopZoom()
		ns.RestoreZoomLimit()
		return
	end
	-- The speed setting: just above the path's speed, then a crawl.
	local speed = ZOOM_SETTLE_SPEED
	if t < T then
		local pathSpeed = zoomer.easeOut and zoomer.cruise * (1 - t / T) or zoomer.cruise * EaseShape(t, T, MOVE_EASE) * rate
		speed = math.max(ZOOM_MIN_SPEED, pathSpeed * ZOOM_HEADROOM + ZOOM_SPEED_EXTRA)
	end
	SetZoomSpeed(speed)
	-- Steer toward where the path will be shortly.
	if now - zoomer.sentAt >= ZOOM_SEND_EVERY then
		local miss = ZoomPath(math.min(T, t + ZOOM_LEAD * rate)) - zoom -- (positive: further out)
		if math.abs(miss) > ZOOM_DONE then
			zoomer.sentAt = now
			Send(miss < 0 and "CameraZoomIn" or "CameraZoomOut", math.abs(miss) * ZOOM_GAIN)
		end
	end
end

-- Seconds the turn back behind you takes, leaving.
local function TurnBackTime()
	return math.max(BACK_MIN, ns.db.questCamTurnTime * BACK_SHARE)
end

-- Runs the queued steps in order (cam.steps: { kind, target, T, waitZoom, ease, tail }),
-- once the swing behind you has handed camera follow back. "yaw" and "pitch"
-- moves run one at a time; a "zoom" starts and the next step follows at once
-- (the tilt and the zoom go together). waitZoom: not while the zoom's moving.
local function StepSequence(now)
	while true do
		local drift = cam.active and not cam.handedOver and #cam.steps == 0 and DriftWanted()
		if movers.yaw.moving or movers.pitch.moving
			or now - math.max(movers.yaw.stoppedAt or 0, movers.pitch.stoppedAt or 0) < (drift and DRIFT_GAP or STEP_GAP) then
			return
		end
		local step = cam.steps[1]
		if drift then
			-- Settled: a slow drift to and fro about the turn's angle, so the
			-- shot isn't stock-still. (Each leg's own gentle start and stop
			-- turn it round at either end.) Each leg's time goes by its
			-- distance, so a first one from the middle doesn't crawl. (The
			-- side turn usually runs on into that first leg itself.)
			-- The first leg carries on the way the camera last turned.
			local half = ns.db.questCamDrift / 2
			if cam.driftOut == nil then
				cam.driftOut = movers.yaw.lastGrowing ~= false
			else
				cam.driftOut = not cam.driftOut
			end
			local target = math.max(0, ns.db.questCamAngle) + (cam.driftOut and half or -half)
			local T = DRIFT_TIME * math.abs(target - movers.yaw.amount) / ns.db.questCamDrift
			step = { "yaw", target, T, false, DRIFT_EASE }
			cam.drifting = true -- (ns.QuestCamMoving: the drift doesn't count)
			cam.steps[1] = step
		end
		if not step then
			if not cam.active and movers.yaw.amount == 0 and movers.pitch.amount == 0 then
				ns.ApplyCVarSet(FOLLOW_CVARS, false) -- all back: your camera follow returns
			end
			return
		end
		if ns.RECENTER_CVARS.active then
			cam.followBackAt = nil
			return
		end
		cam.followBackAt = cam.followBackAt or now
		if now < (cam.stepsAt or 0) or now - cam.followBackAt < FOLLOW_GAP or (step[4] and Zooming()) then
			return
		end
		table.remove(cam.steps, 1)
		if step[1] == "zoom" then
			ZoomTo(step[2], step[3])
		else
			ns.ApplyCVarSet(FOLLOW_CVARS, true)
			if step[6] then
				-- (The turn carries on into the drift's first leg: the next
				-- leg heads back.)
				cam.driftOut = step[2] >= movers.yaw.amount
			end
			MoveTo(movers[step[1]], step[2], step[3], step[5], step[6])
		end
	end
end

-- You moved the camera yourself: it's yours, nothing to put back. (Except
-- the zoom back out to your distance, once it's over, unless you zoomed.)
local function HandOver(what)
	ns.Log("questcam", ("handed over to you (%s): turn, tilt and zoom stopped"):format(tostring(what)))
	for _, m in pairs(movers) do
		StopMove(m)
		-- (Your speed now, not SPEED_RESTORE_DELAY later: your first drag ran
		-- at the turn's slowed speed, and the camera seemed to fight you.)
		RestoreSpeed(m.cvar)
		m.amount = 0
	end
	if not (zoomer.leaving and zoomer.moving and ns.lastCameraInputWhat ~= "zoom") then
		StopZoom(true) -- (your own zooming goes at your speed)
		ns.RestoreZoomLimit()
	end
	cam.steps, cam.handedOver = {}, true
	ns.ApplyCVarSet(FOLLOW_CVARS, false)
end

-- /cine debug questlog: every frame of each quest cam, saved (ns.db.questCamLog)
-- for reading after a /reload.
local function Log(now)
	local log = cam.log
	if not log or #log >= LOG_MAX then
		return
	end
	local yaw, pitch = movers.yaw, movers.pitch
	log[#log + 1] = ("%.3f yaw %.1f%s sent %s pitch %.1f%s zoom %.2f%s %s follow %s recenter %s steps %d%s"):format(
		now - cam.startedAt, yaw.amount, yaw.moving and "*" or "", yaw.sent and ("%.1f"):format(yaw.sent) or "-",
		pitch.amount, pitch.moving and "*" or "", GetCameraZoom and GetCameraZoom() or -1,
		Zooming() and "*" or "", zoomer.moving and ("speed %.2f path %.2f"):format(zoomer.sent or 0, ZoomPath(math.min(zoomer.t, zoomer.T))) or "-",
		tostring(GetCVar("cameraSmoothStyle")),
		tostring(ns.RECENTER_CVARS.active or false), #cam.steps,
		cam.others and (" OTHERS: " .. table.concat(cam.others, " ")) or "")
		.. (cam.notes and (" | " .. table.concat(cam.notes, " ")) or "")
	cam.others, cam.notes = nil, nil
end

-- Where you are, in yards; nil where the game won't say (some instances).
local function PlayerPosition()
	local ok, y, x = pcall(UnitPosition, "player")
	if ok and type(y) == "number" and type(x) == "number"
		and not (issecretvalue and (issecretvalue(y) or issecretvalue(x))) then
		return x, y
	end
end

-- Which way the camera comes round (yaw.left), for Start: picked as the
-- conversation opens, so Quest talk's bubble can open on the other half of
-- the screen from the quest giver straight away (ns.QuestCamSide).
local function PickSide()
	local side = ns.db.questCamSide
	if side == "click" and cam.clickSide then
		return cam.clickSide == "right"
	elseif side == "random" or side == "click" then
		return math.random() < 0.5
	end
	return side == "left"
end

local function Start()
	local db = ns.db
	cam.active, cam.closingAt, cam.handedOver = true, nil, false
	cam.startedAt = GetTime()
	ns.Log("questcam", ("started (%s)"):format(cam.test and "test" or tostring(cam.npcName or cam.event)))
	cam.log = nil
	if db.debugQuestCam or ns.Verbose() then
		db.questCamLog = {}
		cam.log = db.questCamLog
	end
	cam.talkX, cam.talkY = PlayerPosition()
	-- Your own distance (the AFK camera's slow zoom, if it was going, lets go
	-- where it is: this zoom takes over). Still to go back out to from the
	-- last quest giver: that one.
	local back = zoomer.pending and zoomer.pending.to or (zoomer.leaving and zoomer.moving and zoomer.goal) or nil
	zoomer.pending = nil
	cam.zoom, cam.zoomedTo = back or (ns.PlayerZoom and ns.PlayerZoom()), nil
	ns.TakeOverZoom()
	local swing = math.min(db.questCamTime, QUICK_SWING)
	-- (Not while your own zoom's still going: you've just picked a distance.)
	if ns.PlayerZoomedSince(cam.startedAt - ns.PLAYER_ZOOM_WAIT) then
		Note("you're zooming: no zoom in")
		ns.RestoreZoomLimit()
	elseif cam.zoom and GetCameraZoom and GetCameraZoom() > db.questCamDistance + ZOOM_MARGIN then
		cam.zoomedTo = db.questCamDistance
		ZoomTo(db.questCamDistance, math.min(db.questCamZoomMaxTime or math.huge,
			(GetCameraZoom() - db.questCamDistance) / db.questCamZoomSpeed))
		swing = db.questCamTime
	else
		ns.RestoreZoomLimit() -- (close already: inside it)
		if back then
			-- (Still ours: it goes back out after this one too.)
			if zoomer.leaving then
				StopZoom()
			end
			cam.zoomedTo = GetCameraZoom()
		end
	end
	if swing < db.questCamTime then
		-- No zoom in: a turn or tilt still going back from the last quest giver
		-- slows to a stop now, rather than holding up this one's turn.
		for _, m in pairs(movers) do
			if not EaseToStop(m) then
				StopMove(m)
			end
		end
	end
	-- (Held on a little past its time so it settles fully behind you.)
	ns.CenterCamera(swing + SWING_SETTLE, SWING_YAW, 0, math.min(SWING_RAMP, swing))
	-- Then round to the side as the zoom carries on, and down after that.
	-- (A move still undoing a past conversation's carries on from where it is.)
	-- Which side: there's no knowing where the quest giver stands (only your
	-- own and your group's positions are given), nor what's around you, so
	-- with questCamSide "random" it's picked afresh each time. With "click",
	-- it turns toward the side of the screen you clicked them on. (That's
	-- yaw.left on a click on the right: the other way, it turned away.)
	-- (Unless still turning back from the last one: it carries on that way.)
	-- (Picked as the conversation opened, see PickSide.)
	if movers.yaw.amount == 0 then
		if cam.left == nil then
			cam.left = PickSide()
		end
		movers.yaw.left = cam.left
		Note("side " .. (movers.yaw.left and "left" or "right") .. (cam.clickSide and " (clicked)" or ""))
	end
	cam.steps, cam.stepsAt = {}, cam.startedAt + swing + SWING_SETTLE
	cam.driftOut, movers.yaw.lastGrowing, cam.drifting = nil, nil, nil
	local turnTime = db.questCamAngle > 0 and db.questCamTurnTime or 0
	if db.questCamAngle > 0 then
		-- With nothing after it but the drift, the turn flows straight into it
		-- (stopping and starting again showed as a pause).
		local tail
		if DriftWanted() and db.questCamLower <= 0 then
			tail = { extra = db.questCamDrift / 2, R = DRIFT_EASE * DRIFT_TIME,
				speed = db.questCamDrift / (DRIFT_TIME * (1 - DRIFT_EASE)) }
		end
		table.insert(cam.steps, { "yaw", db.questCamAngle, turnTime, nil, nil, tail })
	end
	if db.questCamLower > 0 then
		table.insert(cam.steps, { "pitch", db.questCamLower, TILT_TIME, false, TILT_EASE })
	end
	if db.questCamOverShoulder and db.questCamShoulder > 0 and ShoulderAllowed() then
		SHOULDER_CVARS.values.test_cameraOverShoulder = ("%.2f"):format(db.questCamShoulder)
		if db.questCamUncenter then
			ns.ApplyCVarSet(CENTERED_CVARS, true)
		end
		ns.ApplyCVarSet(SHOULDER_CVARS, true)
	end
end

local function Stop()
	cam.active, cam.closingAt = false, nil
	ns.ApplyCVarSet(SHOULDER_CVARS, false)
	ns.ApplyCVarSet(CENTERED_CVARS, false)
	-- The zoom out and the turn back behind you together, then the tilt up.
	cam.steps, cam.stepsAt = {}, 0
	zoomer.leaving = false
	if not cam.handedOver then
		for _, m in pairs(movers) do
			-- (Cut short if still on the way in: undone from where it got to.)
			if not EaseToStop(m) then
				StopMove(m)
			end
		end
	end
	-- Back out to your distance, unless you zoomed yourself while talking.
	-- (Still on its way in counts as ours.) At speed 0 it stays where it is.
	if cam.zoomedTo and cam.zoom and GetCameraZoom and ns.db.questCamZoomOutSpeed > 0
		and not ns.PlayerZoomedSince(cam.startedAt)
		and (zoomer.moving or math.abs(GetCameraZoom() - cam.zoomedTo) < ZOOM_YOURS) then
		-- (Held until you've walked off: see OnUpdate. Out at once (now) with no
		-- other quest giver near to talk to next (the one you left doesn't
		-- count), and from a test (the Test button).)
		local alone = ns.QuestGiverNear and ns.QuestGiverNear(GIVER_NEAR, cam.leftNpc) == false
		zoomer.pending = { to = cam.zoom, x = cam.talkX, y = cam.talkY, since = GetTime(), walked = 0,
			now = cam.test or alone }
		if alone then Note("no quest giver near: zoom out now") end
		Note("zoom out held")
	end
	if not cam.handedOver then
		local turnBack = TurnBackTime()
		if movers.yaw.amount ~= 0 then
			table.insert(cam.steps, { "yaw", 0, turnBack, nil, BACK_EASE })
		end
		if movers.pitch.amount ~= 0 then
			table.insert(cam.steps, { "pitch", 0, TILT_BACK_TIME, false, TILT_EASE })
		end
	end
	cam.zoom, cam.zoomedTo = nil, nil
end

-- The conversation's event (Cameras page): its camera here isn't "none".
-- cam.event is "Quest" (a quest giver) or "QuestGossip" (only "(Quest)"
-- options so far).
local function Wanted()
	local db = ns.db
	return db and db.enabled and ns.TriggerHasCamera(cam.event or "Quest")
		and not InCombatLockdown()
		and not cam.movie and not ns.OnTaxi() and not ns.IsCameraOffHere("quest")
		and ns.CombatWaitOver("quest", GetTime())
end

-- The last click on the world (not on a window): when, and which half of the
-- screen it was on.
local lastClick = { at = -math.huge }
local clickWatcher = CreateFrame("Frame")
clickWatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
clickWatcher:SetScript("OnEvent", function()
	local focus
	if GetMouseFoci then
		focus = GetMouseFoci()[1]
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	if focus ~= nil and focus ~= WorldFrame then
		return
	end
	local x = GetCursorPosition() / UIParent:GetEffectiveScale()
	lastClick.at = GetTime()
	lastClick.side = x > UIParent:GetWidth() / 2 and "right" or "left"
	lastClick.x = x / UIParent:GetWidth()
end)

-- How far across the screen (a share of its width) the click that opened the
-- conversation was, or nil if it wasn't a click (Quest talk's Opposite Clicked).
function ns.ClickedX()
	return GetTime() - lastClick.at <= CLICK_WINDOW and lastClick.x or nil
end

local OPENS = {
	QUEST_GREETING = true, QUEST_DETAIL = true, QUEST_PROGRESS = true, QUEST_COMPLETE = true,
	GOSSIP_SHOW = true,
}

-- A step on in the conversation (picking a quest or option, accepting, handing
-- in): its window closes for the next. A window closing with none of these
-- just before is you leaving (Escape, Goodbye): the camera goes back at once.
local steppedAt = -math.huge
local function Stepped() steppedAt = GetTime() end
for _, name in ipairs({ "AcceptQuest", "CompleteQuest", "GetQuestReward", "SelectAvailableQuest",
	"SelectActiveQuest", "SelectGossipAvailableQuest", "SelectGossipActiveQuest", "SelectGossipOption" }) do
	if _G[name] then hooksecurefunc(name, Stepped) end
end
for _, name in ipairs({ "SelectAvailableQuest", "SelectActiveQuest", "SelectOption", "SelectOptionByIndex" }) do
	if C_GossipInfo and C_GossipInfo[name] then hooksecurefunc(C_GossipInfo, name, Stepped) end
end

-- The name of who you're talking to (nil if the game won't say).
local function NpcName()
	local name = UnitName("npc")
	if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
end

-- A movie or cinematic (a quest giver's "play the movie" option): the moves
-- went on counting while it played, and the game's camera didn't follow the
-- count, so undoing them after left it looking straight down. So everything
-- stops where it is, and no more for this conversation. Once it's over, if
-- the quest cam had moved the camera, it's set back behind you, level, and
-- back to your distance.
local MOVIE_VIEW = 5 -- saved view slot used for Blizzard's default view (as /cine behind)
local MOVIE_ZOOM_WAIT = 1.5 -- seconds for SetView's blend to settle before the zoom goes back
local function OnMovie(started)
	if not started then
		cam.movie = false
		local restore = cam.movieRestore
		cam.movieRestore = nil
		if restore and ResetView and SetView then
			ns.CallCameraFunction("ResetView", MOVIE_VIEW)
			ns.CallCameraFunction("SetView", MOVIE_VIEW)
			C_Timer.After(MOVIE_ZOOM_WAIT, function()
				local diff = restore.zoom and GetCameraZoom and restore.zoom - GetCameraZoom()
				if diff and math.abs(diff) > 0.1 then
					ns.CallCameraFunction(diff > 0 and "CameraZoomOut" or "CameraZoomIn", math.abs(diff))
				end
			end)
		end
		return
	end
	if cam.movie then
		return
	end
	cam.movie = true
	local moved = movers.yaw.amount ~= 0 or movers.pitch.amount ~= 0 or movers.yaw.moving or movers.pitch.moving
		or zoomer.moving or zoomer.pending ~= nil or cam.zoomedTo ~= nil
	if moved then
		local zoom = zoomer.pending and zoomer.pending.to or (zoomer.leaving and zoomer.goal) or cam.zoom
		cam.movieRestore = { zoom = zoom or (ns.PlayerZoom and ns.PlayerZoom()) }
	end
	for _, m in pairs(movers) do
		StopMove(m)
		m.amount = 0
	end
	StopZoom(true)
	ns.RestoreZoomLimit()
	zoomer.pending, zoomer.leaving = nil, false
	cam.active, cam.steps, cam.zoom, cam.zoomedTo = false, {}, nil, nil
	if cam.since then
		cam.cancelled = true
	end
	ns.ApplyCVarSet(FOLLOW_CVARS, false)
	ns.ApplyCVarSet(SHOULDER_CVARS, false)
	ns.ApplyCVarSet(CENTERED_CVARS, false)
	Note("movie: stopped")
end

local MOVIE_EVENTS = { PLAY_MOVIE = true, CINEMATIC_START = true, STOP_MOVIE = false, CINEMATIC_STOP = false }

-- Talking to a quest giver: cam.since is when it started (nil: not talking),
-- cam.closingAt when its window closed (it ends after CLOSE_GRACE, unless
-- another opens meanwhile, going from gossip to the quest text).
local function OnEvent(_, event)
	if MOVIE_EVENTS[event] ~= nil then
		OnMovie(MOVIE_EVENTS[event])
	elseif OPENS[event] then
		-- Which event: a quest window or quests on offer, a quest giver's;
		-- only "(Quest)" options, talking about a quest's; else none (an
		-- innkeeper or the like), unless every NPC counts as a quest giver.
		local which = "Quest"
		if event == "GOSSIP_SHOW" and not GossipHasQuests() then
			which = (GossipHasQuestOptions() and "QuestGossip")
				or (ns.db and ns.db.questCamAllGossip and "Quest") or nil
		end
		if not which and not cam.since then
			return
		end
		if not cam.since and not (ns.Flag(UnitExists("npc")) and not ns.Flag(UnitIsPlayer("npc"))) then
			return -- shared by a player, or from an item: nobody to talk to
		end
		if not cam.since and ns.db and ns.db.questCamNotMounted and IsMounted and ns.Flag(IsMounted()) then
			return -- on a mount, and you'd rather it didn't
		end
		-- The wait before starting (questCamDelay), from the first window. Each
		-- window after adds WINDOW_EXTRA (and leaves at least that): clicking
		-- through several quests' text, it doesn't start mid-way, but a few
		-- clicks to get to one doesn't hold it off for long. (Windows opening
		-- on the same frame count as one.)
		-- (Talking about a quest first, a quest giver's window after: it's
		-- theirs from then on.)
		if not cam.since or which == "Quest" then
			cam.event = which or cam.event
		end
		local delay = ns.db and ns.db[cam.event == "QuestGossip" and "questCamGossipDelay" or "questCamDelay"] or 0
		local now = GetTime()
		if not cam.since then
			cam.since, cam.cancelled, cam.test = now, nil, false -- a new conversation
			cam.npcName, cam.leftNpc = NpcName(), nil
			-- Opened by clicking them (not an interact key): the side they were on.
			cam.clickSide = cam.since - lastClick.at <= CLICK_WINDOW and lastClick.side or nil
			cam.left = PickSide()
			cam.startAt = now + delay
			-- Still zooming back out from the last one (or the Chat Cam's): it
			-- eases to a stop, the rest held again till you walk off from here.
			if zoomer.leaving and zoomer.moving then
				local x, y = PlayerPosition()
				zoomer.pending = { to = zoomer.goal, x = x, y = y, since = now, walked = 0,
					speed = zoomer.leavingSpeed }
				EaseZoomStop(LEAVE_ZOOM_STOP)
				zoomer.leaving = false
				Note("talking again: zoom out stopped, held")
			end
		elseif not cam.active and now > (cam.windowAt or 0) then
			local extra = math.min(WINDOW_EXTRA, delay)
			cam.startAt = math.max((cam.startAt or now) + extra, now + extra)
		end
		cam.windowAt = now
		cam.closingAt = nil
	elseif event == "PLAYER_LOGOUT" then
		-- No time to glide: everything goes straight back (the zoom isn't saved).
		for _, m in pairs(movers) do
			StopMove(m)
			ns.ReleaseSpeed(WHO, m.cvar)
		end
		StopZoom(true)
		ns.ApplyCVarSet(FOLLOW_CVARS, false)
		ns.ApplyCVarSet(SHOULDER_CVARS, false)
		ns.ApplyCVarSet(CENTERED_CVARS, false)
	elseif event == "PLAYER_REGEN_DISABLED" then
		if cam.since then
			cam.closingAt = 0 -- a fight: ends now
		end
		zoomer.pending = nil
		-- (And the zoom stops where it is, your zoom speed back, so it's yours
		-- for the fight: the zoom back out is slow.)
		if zoomer.moving or zoomer.release then
			Note("fight: zoom stopped")
			StopZoom(true)
			ns.RestoreZoomLimit()
		end
	elseif cam.since and GetTime() - steppedAt > LEAVE_WINDOW then
		Note("left the conversation")
		cam.closingAt = 0 -- you left (Escape, Goodbye): ends now
		cam.leftNpc = cam.npcName
	elseif cam.since then
		cam.closingAt = cam.closingAt or GetTime()
	end
end

-- The live log (/cine debug tab, the Cinematic chat tab): when it thinks
-- you're moving the camera and when you've stopped, and what of the quest
-- cam's still going each time that changes, down to nothing left.
local WatchLog
do
	local INPUT_QUIET = 0.5 -- seconds without camera input: you've stopped (Core.lua's PLAYER_HOLD)
	local inputSeen, yours, partsWas = -math.huge, false, ""

	-- What keeps it holding the view (as its camera lock busy, below), by name.
	local function Parts()
		local parts = {}
		if cam.active then parts[#parts + 1] = cam.handedOver and "on (handed over)" or "on" end
		if ns.QuestCamPending() then parts[#parts + 1] = "about to start" end
		if #cam.steps > 0 then parts[#parts + 1] = "steps to go" end
		if movers.yaw.moving then parts[#parts + 1] = cam.drifting and "drifting" or "turning" end
		if movers.pitch.moving then parts[#parts + 1] = "tilting" end
		if zoomer.moving then
			parts[#parts + 1] = (cam.zoomBy and cam.zoomBy .. "'s " or "") .. ("zoom to %.1f"):format(zoomer.goal)
		end
		if zoomer.release then parts[#parts + 1] = "zoom speed easing back" end
		if zoomer.pending then
			parts[#parts + 1] = ("zoom out to %.1f held till you walk off"):format(zoomer.pending.to)
		end
		if (cam.restoring or 0) > 0 then parts[#parts + 1] = "speed settings going back" end
		if GetTime() - (zoomer.wantsAt or -math.huge) < 0.5 then parts[#parts + 1] = "waiting for the view to zoom out" end
		return table.concat(parts, ", ")
	end

	function WatchLog(now)
		local mouse = ns.IsMouseOnCamera and ns.IsMouseOnCamera() or false
		local last = ns.GetLastCameraInput()
		local parts = Parts()
		-- (Only around a quest cam: not every drag all day.)
		local around = parts ~= "" or partsWas ~= ""
		if last > inputSeen or mouse then
			if not yours and around then
				ns.Log("questcam", ("you're moving the camera: %s%s; quest cam: %s"):format(
					mouse and "mouse held" or tostring(ns.lastCameraInputWhat),
					IsMouselooking and IsMouselooking() and " (mouselook)" or "", parts ~= "" and parts or "done"))
			end
			yours = yours or around
			inputSeen = math.max(last, inputSeen)
			if mouse then inputSeen = now end
		elseif yours and now - inputSeen >= INPUT_QUIET then
			yours = false
			ns.Log("questcam", ("you've stopped moving the camera; quest cam: %s"):format(parts ~= "" and parts or "done"))
		end
		if parts ~= partsWas then
			ns.Log("questcam", parts ~= "" and ("still going: " .. parts)
				or ("all done at %.1f yards, the view's free (holder now: %s)"):format(GetCameraZoom(),
					tostring(ns.CameraHolder("quest") or "nobody")))
			partsWas = parts
		end
	end
end

local function OnUpdate(_, elapsed)
	if ns.IsSuspended() then
		return -- stopped after an error (Diagnostics.lua)
	end
	local now = GetTime()
	-- (The moves carry on after the window closes, going back.)
	StepMove(movers.yaw, elapsed)
	StepMove(movers.pitch, elapsed)
	StepZoom(elapsed)
	StepZoomRelease(elapsed)
	local busy = cam.active or #cam.steps > 0 or movers.yaw.moving or movers.pitch.moving or zoomer.moving
	if not cam.handedOver and cam.startedAt and busy
		and ns.GetLastCameraInput() > cam.startedAt + INPUT_GRACE then
		HandOver(ns.lastCameraInputWhat)
	end
	-- Zoomed yourself while it zooms (in, or back out): it stops, and the
	-- wheel goes at your speed (also while the speed's still easing back).
	if (zoomer.moving or zoomer.release) and ns.PlayerZoomedSince(zoomer.startedAt) then
		Note("you zoomed: zoom stopped")
		StopZoom(true)
		ns.RestoreZoomLimit()
	end
	-- The zoom back out, held: it goes once you've walked off from where you
	-- started talking (not just a few steps to the next quest giver). Zoomed
	-- yourself meanwhile: it's yours, it stays. Took a flight: it goes at once
	-- (a flight doesn't count as moving, so it was held the whole way, and
	-- the flight camera's zoom waited on it).
	local pending = zoomer.pending
	local onTaxi = pending and ns.OnTaxi()
	if pending and ns.PlayerZoomedSince(pending.since) then
		Note("you zoomed: no zoom out")
		zoomer.pending = nil
	elseif pending and (ns.playerMoving or onTaxi or pending.now) then
		local x, y = PlayerPosition()
		local far
		if onTaxi or pending.now then
			far = true
		elseif x and pending.x then
			far = (x - pending.x) ^ 2 + (y - pending.y) ^ 2 >= ZOOM_OUT_DISTANCE ^ 2
		else
			pending.walked = pending.walked + elapsed
			far = pending.walked >= ZOOM_OUT_WALK_TIME
		end
		-- (Once the view's ours: another camera holding it lets go for this, see
		-- the camera lock below.)
		if far and not ns.ClaimCamera("quest") then
			zoomer.wantsAt = now
		elseif far then
			zoomer.pending = nil
			ZoomTo(pending.to, math.min(ns.db.questCamZoomMaxTime or math.huge,
				math.abs(pending.to - GetCameraZoom()) / (pending.speed or ns.db.questCamZoomOutSpeed)))
			zoomer.leaving, zoomer.leavingSpeed = true, pending.speed
			HurryZoom(ZOOM_HURRY)
		end
	end
	StepSequence(now)
	if busy or Zooming() or zoomer.release then
		Log(now)
	end
	WatchLog(now)
	if not cam.since then
		return
	end
	if cam.closingAt and now - cam.closingAt >= CLOSE_GRACE then
		cam.since, cam.closingAt = nil, nil
		if cam.active then
			ns.Log("questcam", "window closed: going back")
			Stop()
		end
	elseif cam.active and not Wanted() then
		ns.Log("questcam", "turned off mid-conversation: going back")
		Stop() -- turned off (or set to no camera) mid-conversation
		cam.since = nil
	elseif cam.active and ns.playerMoving then
		ns.Log("questcam", "you walked off: going back")
		Stop() -- walked off: back to normal, and no more until the next conversation
		cam.cancelled = true
	elseif not cam.active and not cam.closingAt and not cam.cancelled and not ns.playerMoving
		and now >= cam.startAt and Wanted() and ns.ClaimCamera("quest") then
		Start() -- (after the wait: a quest picked up and gone sooner gets no camera)
	end
end

local frame = CreateFrame("Frame")
for event in pairs(OPENS) do
	frame:RegisterEvent(event)
end
for _, event in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED", "PLAYER_REGEN_DISABLED", "PLAYER_LOGOUT" }) do
	frame:RegisterEvent(event)
end
for event in pairs(MOVIE_EVENTS) do
	pcall(frame.RegisterEvent, frame, event) -- (not every client has every event)
end
frame:SetScript("OnEvent", OnEvent)

-- For the log: camera commands that aren't ours (the addon's other cameras,
-- the zoom, your own input), noted by name until the next log line.
for _, name in ipairs({ "MoveViewLeftStart", "MoveViewLeftStop", "MoveViewRightStart", "MoveViewRightStop",
	"MoveViewUpStart", "MoveViewUpStop", "MoveViewDownStart", "MoveViewDownStop", "CameraZoomIn", "CameraZoomOut",
	"SetView", "ResetView" }) do
	if _G[name] then
		hooksecurefunc(name, function()
			if cam.log and not cam.sending then
				cam.others = cam.others or {}
				if #cam.others < 8 then
					cam.others[#cam.others + 1] = name
				end
			end
		end)
	end
end
frame:SetScript("OnUpdate", ns.Profiled("Quest cam", OnUpdate))

-- Whether the quest cam is zooming back out to your distance (the RP walk
-- and auto-run cameras' own zoom waits for it, rather than starting from close in).
function ns.QuestCamZoomingBack()
	return (zoomer.leaving and zoomer.moving) or zoomer.pending ~= nil
end

-- Whether the quest cam is running now.
function ns.QuestCamActive()
	return cam.active and true or false
end

-- Running with the quest giver's window still open: a click on them for the
-- next quest isn't moving the camera (ns.IsMouseOnCamera waits on it). Once
-- the window's closed, a held button is yours at once.
function ns.QuestCamWindowOpen()
	return cam.active and not cam.closingAt
end

-- The trigger (Cameras page) it's running for ("Quest" or "QuestGossip"): its
-- Music and CineMode columns.
function ns.QuestCamEvent()
	return cam.event or "Quest"
end

-- The Test button (CameraTests.lua): a conversation with nobody, as if a
-- quest giver's window had opened and the wait were over, until it's
-- stopped (then everything goes back, the zoom straight away). False if the
-- quest camera can't start now.
function ns.QuestCamTest(on)
	if on then
		if not cam.since then
			cam.event = "Quest"
		end
		if not Wanted() or ns.playerMoving then
			return false
		end
		local now = GetTime()
		cam.since, cam.cancelled, cam.clickSide, cam.test = now, nil, nil, true
		cam.left, cam.npcName, cam.leftNpc = PickSide(), nil, nil
		cam.startAt, cam.windowAt, cam.closingAt = now, now, nil
		return true
	end
	if cam.test and cam.since then
		cam.closingAt = GetTime() - CLOSE_GRACE -- (over next frame)
	end
end
-- (Walked off, it's over: the conversation's only kept for the window that never closes.)
function ns.QuestCamTesting()
	return cam.test and cam.since ~= nil and not cam.cancelled
end

-- Whether the quest cam is moving the camera now: the swing behind you, the
-- zoom in, the turn and the tilt (not the drift after, nor once you've taken
-- the camera). Quest talk's bubble over the NPC's head waits on it.
function ns.QuestCamMoving()
	if not cam.active or cam.handedOver then
		return false
	end
	return GetTime() < (cam.stepsAt or 0) or zoomer.moving or #cam.steps > 0 or movers.pitch.moving
		or (movers.yaw.moving and not cam.drifting)
end

-- Which half of the screen the quest giver ends up on ("left" or "right"),
-- while the quest cam is running or about to for this conversation; nil
-- otherwise. (The camera coming round to your left frames them on the left:
-- with "Where you clicked them", a click on the right turns it toward the
-- right, so they end up on the left.) Quest talk's Opposite Clicked goes on
-- the other half when you didn't click them.
function ns.QuestCamSide()
	local left
	if cam.active or (ns.QuestCamPending and ns.QuestCamPending()) then
		-- (Still turning back from the last one: it carries on that way.)
		if cam.active or movers.yaw.amount ~= 0 then
			left = movers.yaw.left
		else
			left = cam.left
		end
	end
	if left == nil then
		return nil
	end
	return left and "left" or "right"
end

-- The camera lock (Core.lua): the quest cam holds the view from its start
-- (and while about to) until its turns, tilt and zoom are done and your
-- settings back; a zoom back out that's due takes it from whoever has it.
-- Your camera input past INPUT_GRACE (sooner, it's the click that opened the
-- window) hands it over at once.
ns.RegisterCamera("quest", function()
	return cam.active or #cam.steps > 0 or movers.yaw.moving or movers.pitch.moving
		or ((zoomer.moving or zoomer.release ~= nil) and cam.zoomBy == nil) or (cam.restoring or 0) > 0
		or GetTime() - (zoomer.wantsAt or -math.huge) < 0.5 or ns.QuestCamPending()
end, function(what)
	if not cam.handedOver and GetTime() > (cam.startedAt or 0) + INPUT_GRACE then
		Note("you took the camera")
		HandOver(what)
	end
end)

-- Whether it's waiting to start (questCamDelay), and will unless the talk
-- ends first or you move off.
function ns.QuestCamPending()
	return cam.since ~= nil and not cam.active and not cam.closingAt and not cam.cancelled
		and not ns.playerMoving and Wanted() and true or false
end

-- Running, or still turning or tilting back (the Chat Cam waits for it).
function ns.QuestCamBusy()
	return cam.active or #cam.steps > 0 or movers.yaw.moving or movers.pitch.moving
end

-- The Chat Cam (ChatCam.lua, the dev copy) borrows the eased zoom:
-- it's stepped here (OnUpdate) whoever started it, and stops if you zoom.
function ns.QuestCamZoomTo(distance, T)
	ns.TakeOverZoom()
	ZoomTo(distance, T)
	cam.zoomBy = "chatcam"
end
-- Whose zoom is going ("chatcam" while it's borrowed; nil: the quest cam's),
-- and whether it's still going or easing your speed setting back.
function ns.QuestCamZoomBy()
	return cam.zoomBy
end
function ns.QuestCamZoomHeld()
	return zoomer.moving or zoomer.release ~= nil
end
function ns.QuestCamZooming()
	return zoomer.moving
end
function ns.QuestCamEaseZoomStop(T)
	return EaseZoomStop(T)
end
function ns.QuestCamStopZoom(ease)
	StopZoom(not ease)
	ns.RestoreZoomLimit()
end
-- The Chat Cam let go as you moved: its zoom back out to `distance`, held
-- till you've walked off from here (at `speed` yards a second), as this one's.
function ns.QuestCamHoldZoomOut(distance, speed)
	local x, y = PlayerPosition()
	zoomer.pending = { to = distance, x = x, y = y, since = GetTime(), walked = 0, speed = speed }
end

-- For /cine debug: whether the quest cam is on now, its moves and the shoulder state.
function ns.GetQuestCamDebug()
	return {
		active = cam.active, talking = cam.since ~= nil, zoom = cam.zoom, zoomedTo = cam.zoomedTo,
		turned = movers.yaw.amount, lowered = movers.pitch.amount, handedOver = cam.handedOver,
		shoulder = GetCVar("test_cameraOverShoulder"), centered = GetCVar("CameraKeepCharacterCentered"),
		shoulderOn = SHOULDER_CVARS.active or false,
	}
end

-- /cine starttest <kind>: one slow turn (about 30 degrees left) on its own,
-- to find what snaps as the quest cam's moves start. Stand still; nothing
-- else moves the camera meanwhile. Your turn speed setting comes back after.
--   setting: the quest cam's way (the low speed set first, then the move,
--            then the setting eased up and down)
--   share:   your setting left alone; the move sent at a share of it and
--            re-sent as the speed changes (each send restarts the turn)
--   steady:  your setting left alone; one move at a steady 10 degrees/sec
--   nomove:  only the setting changed to the low speed, no move at all
--   gentle:  the quest cam's way now: sent at a share of the setting, the
--            setting eased from 1 up toward yours and back (a far gentler start)
--   tilt:    the same, tilting down (about 20 degrees) instead
do
	local YAW = "cameraYawMoveSpeed"
	local TEST_TIME, TEST_PEAK, TEST_WAIT = 4, 12, 1 -- seconds, degrees per second at most, seconds first
	local KINDS = { setting = true, share = true, steady = true, nomove = true, gentle = true, tilt = true }
	local PITCH = "cameraPitchMoveSpeed"
	local TEST = "test:quest" -- (not a camera: the watch leaves its holds alone)
	local test
	local runner = CreateFrame("Frame")

	local function Finish()
		if test.kind == "tilt" then
			ns.CallCameraFunction("MoveViewDownStop")
		elseif test.kind ~= "nomove" then
			ns.CallCameraFunction("MoveViewLeftStop")
		end
		runner:SetScript("OnUpdate", nil)
		C_Timer.After(SPEED_RESTORE_DELAY, function()
			ns.ReleaseSpeed(TEST, YAW)
			ns.ReleaseSpeed(TEST, PITCH)
		end)
		ns.Print("start test (" .. test.kind .. "): done")
		test = nil
	end

	local function OnTestUpdate(_, elapsed)
		test.t = test.t + elapsed
		local t = test.t - TEST_WAIT
		if t < 0 then
			return
		end
		local yours = ns.YourSpeed(YAW)
		local speed = math.max(MOVE_MIN_SPEED, TEST_PEAK * EaseShape(t, TEST_TIME, MOVE_EASE))
		local now = GetTime()
		if test.kind == "setting" then
			if not test.primedAt then
				ns.SetHeldSpeed(TEST, YAW, MOVE_MIN_SPEED)
				test.primedAt = now
			elseif not test.sent then
				if now - test.primedAt >= MOVE_PRIME_TIME then
					ns.CallCameraFunction("MoveViewLeftStart", 1)
					test.sent = MOVE_MIN_SPEED
				end
			elseif math.abs(speed - test.sent) > test.sent * MOVE_CHANGE then
				ns.SetHeldSpeed(TEST, YAW, speed)
				test.sent = speed
			end
		elseif test.kind == "share" then
			if not test.sent or (math.abs(speed - test.sent) > test.sent * 0.03 and now - test.sentAt >= 0.1) then
				ns.CallCameraFunction("MoveViewLeftStart", speed / yours)
				test.sent, test.sentAt = speed, now
			end
		elseif test.kind == "steady" then
			if not test.sent then
				ns.CallCameraFunction("MoveViewLeftStart", 10 / yours)
				test.sent = 10
			end
		elseif test.kind == "gentle" or test.kind == "tilt" then
			local cvar = test.kind == "tilt" and PITCH or YAW
			local peak = test.kind == "tilt" and TEST_PEAK * 2 / 3 or TEST_PEAK
			local share = peak / ns.YourSpeed(cvar)
			local setting = math.max(MOVE_MIN_SETTING, peak * EaseShape(t, TEST_TIME, MOVE_EASE) / share)
			if not test.primedAt then
				ns.SetHeldSpeed(TEST, cvar, MOVE_MIN_SETTING)
				test.primedAt = now
			elseif not test.sent then
				if now - test.primedAt >= MOVE_PRIME_TIME then
					ns.CallCameraFunction(test.kind == "tilt" and "MoveViewDownStart" or "MoveViewLeftStart", share)
					test.sent = MOVE_MIN_SETTING
				end
			elseif math.abs(setting - test.sent) > test.sent * MOVE_CHANGE then
				ns.SetHeldSpeed(TEST, cvar, setting)
				test.sent = setting
			end
		elseif not test.sent then -- nomove
			ns.SetHeldSpeed(TEST, YAW, MOVE_MIN_SPEED)
			test.sent = MOVE_MIN_SPEED
		end
		if t >= TEST_TIME then
			Finish()
		end
	end

	-- Returns false and why if it can't start.
	function ns.QuestCamStartTest(kind)
		if not KINDS[kind] then
			return false, "pick one: gentle, tilt, setting, share, steady or nomove"
		end
		if test then
			return false, "one's already running"
		end
		if cam.active or movers.yaw.moving or movers.pitch.moving then
			return false, "not while the quest cam is moving"
		end
		if kind == "setting" or kind == "nomove" or kind == "gentle" then
			ns.HoldSpeed(TEST, YAW)
		elseif kind == "tilt" then
			ns.HoldSpeed(TEST, PITCH)
		end
		test = { kind = kind, t = 0 }
		runner:SetScript("OnUpdate", OnTestUpdate)
		return true
	end
end
