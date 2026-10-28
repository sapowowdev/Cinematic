-- Cinematic: the Test button on a camera's section of the Camera Settings
-- page runs that camera for TEST_TIME seconds where you stand, to see its
-- settings at work, and turns into Stop meanwhile (Options.lua). Moving
-- ends a test, as it ends the camera.
--
-- ns.CAMERA_TESTS[section key] = { start, running, stop, tip }: start()
-- returns true if the camera started (else it says why), running() whether
-- it's still going, stop() ends it. A test that stops on its own (you moved,
-- its camera ended) frees the button. tip: the button's tooltip (English:
-- translated as the page is built), if not the usual one.
--   The standing-still cameras: as their key bindings start them
--     (Cinematic_StartCam), the Hearthstone's cast pretended for the whole test.
--   The death camera: its key binding's own 30-second test (you lie down).
--   The quest camera: a conversation with nobody (ns.QuestCamTest).
--   Chat Cam: a made-up conversation (ChatCam.lua, the dev copy).
--   The flight, RP walk and auto-run cameras: pretended (below).
-- While one runs, ns.cameraTesting lets the cameras start with the game's
-- Settings window open (they wait for menus otherwise).
local _, ns = ...

local TEST_TIME = 30 -- seconds
local CHECK_EVERY = 0.2

ns.CAMERA_TESTS = ns.CAMERA_TESTS or {}
local tests = ns.CAMERA_TESTS
local current -- { key, test, untilAt }

-- (On a refusal, the key binding is pressed again, not quietly: it says why.)
local STANDING = {
	["AFK Cam"] = { "idle", "afk" }, ["Cozy Cam"] = { "cozy", "cozy" }, ["Vista Cam"] = { "vista", "vista" },
	["Fish Cam"] = { "fish", "fish" }, ["Tele Cam"] = { "tele", "tele" },
}
for key, cam in pairs(STANDING) do
	local camera, manual = cam[1], cam[2]
	tests[key] = {
		start = function()
			Cinematic_StartCam(camera, true, "Test button")
			if ns.manualCam ~= manual then
				Cinematic_StartCam(camera, false, "Test button")
				return false
			end
			if camera == "tele" then
				ns.PretendDepartCast(TEST_TIME) -- (its spin and zoom run to the cast's end)
			end
			return true
		end,
		running = function() return ns.manualCam == manual end,
		stop = function()
			if ns.manualCam == manual then
				Cinematic_StartCam(camera, true) -- (pressed again: it stops)
			end
		end,
	}
end

local function DeathTesting()
	return GetTime() < (ns.deathTestUntil or 0)
end
tests["Death Cam"] = {
	start = function()
		Cinematic_StartCam("death", true)
		if not DeathTesting() then
			Cinematic_StartCam("death")
			return false
		end
		return true
	end,
	running = DeathTesting,
	stop = function()
		if DeathTesting() then
			Cinematic_StartCam("death", true)
		end
	end,
	tip = "Your character lies down as if dead and the death camera runs for 30 seconds. " ..
		"Moving, or clicking Stop, ends it.",
}

tests["Quest Cam"] = {
	start = function()
		if ns.QuestCamTest(true) then
			return true
		end
		ns.Print(ns.L["The quest camera can't start now: it's off (Cameras page), you're " ..
			"moving or in a fight, or it's turned off where you are."])
		return false
	end,
	running = function() return ns.QuestCamTesting() end,
	stop = function() ns.QuestCamTest(false) end,
	tip = "Runs the quest camera for 30 seconds as if you were talking to a quest giver in " ..
		"front of you. Moving, or clicking Stop, ends it.",
}

-- The flight, RP walk and auto-run cameras: pretended (ns.testTravel), as
-- if you'd taken off, or were auto-walking or auto-running, standing where
-- you are (ns.OnTaxi, ns.IsRPWalking and ns.IsAutoRunning go by it). No route
-- is known, so a pretend flight never knows when it'll land; ending the test
-- lands it. Moving by hand ends it, as it ends those cameras.
local TRAVEL = {
	["Flight Cam"] = { mode = "flight", setting = "eventFlightCamera",
		tip = "Pretends you've taken off on a flight path: the flight camera runs for 30 seconds " ..
			"where you stand (with no route known, it never knows when you'll land), then lands. " ..
			"Moving, or clicking Stop, ends it." },
	["RP Walk Cam"] = { mode = "walk", setting = "walkCamera",
		tip = "Pretends you're auto-walking: the RP walk camera runs for 30 seconds where you " ..
			"stand. Moving, or clicking Stop, ends it." },
	["Auto-run Cam"] = { mode = "run", setting = "runCamera",
		tip = "Pretends you're auto-running: the auto-run camera runs for 30 seconds where you " ..
			"stand. Moving, or clicking Stop, ends it." },
}
for key, travel in pairs(TRAVEL) do
	tests[key] = {
		start = function()
			local db = ns.db
			if not db.enabled or db[travel.setting] == "none" or ns.playerMoving
				or UnitOnTaxi("player") or InCombatLockdown() then
				ns.Print(ns.L["This camera can't be tested now: Cinematic or the camera is off (Camera " ..
					"Triggers page), or you're moving, flying or in a fight."])
				return false
			end
			ns.testTravel = travel.mode
			return true
		end,
		running = function() return ns.testTravel == travel.mode and not ns.playerMoving end,
		stop = function()
			if ns.testTravel == travel.mode then
				ns.testTravel = nil
			end
		end,
		tip = travel.tip,
	}
end

local ticker = CreateFrame("Frame")
local wait = 0
local function Tick(_, elapsed)
	wait = wait - elapsed
	if wait > 0 then
		return
	end
	wait = CHECK_EVERY
	if current and (not current.test.running() or GetTime() >= current.untilAt) then
		local test = current.test
		current = nil
		test.stop() -- (ended on its own: anything it left, cleared)
	end
	ns.cameraTesting = current ~= nil
	if not current then
		ticker:SetScript("OnUpdate", nil)
	end
end

function ns.CameraTestStop()
	if current then
		local test = current.test
		current = nil
		ns.cameraTesting = false
		test.stop()
	end
end

-- Starts the test for a section (its English key); true if it started.
function ns.CameraTestStart(key)
	local test = tests[key]
	if not test then
		return false
	end
	ns.CameraTestStop()
	-- (Set first: the camera's checks run as it starts, with the Settings window open.)
	ns.cameraTesting = true
	if not test.start() then
		ns.cameraTesting = false
		return false
	end
	current = { key = key, test = test, untilAt = GetTime() + TEST_TIME }
	wait = CHECK_EVERY
	ticker:SetScript("OnUpdate", Tick)
	return true
end

-- Seconds left on the section's test, or nil if it isn't running.
function ns.CameraTestLeft(key)
	if current and current.key == key then
		return math.max(0, current.untilAt - GetTime())
	end
	return nil
end
