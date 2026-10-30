-- Shoulder Cam (shoulderCam): the camera sits over your right shoulder, you
-- on the left of the screen. It's the game's test_cameraOverShoulder offset,
-- which it eases over to on its own. The game ignores that while Keep
-- Character Centered (Accessibility) is on, so that's turned off meanwhile.
-- It's one of Blizzard's experimental camera settings: writing it brings up
-- their warning. Accept saves nothing; it's the write that brings it up. So
-- while it's on, the settings stay as they are over logout (the game keeps
-- them), and are only written when they differ: Accept once, not each login.
-- Your own settings (db.shoulderCamYours) come back as it's turned off.
-- Disable (ResetTestCvars) turns it off here too.
-- (Not ns.ApplyCVarSet: that puts them back on logout and writes them again
-- on login, the warning each time.)
-- (A plain switch for now: when it's used is still to be worked out.)
local _, ns = ...
local L = ns.L

local CVARS = {
	test_cameraOverShoulder = "1", -- yards to your right
	CameraKeepCharacterCentered = "0",
}

local function Same(a, b)
	return a == b or (tonumber(a) ~= nil and tonumber(a) == tonumber(b))
end

function ns.ApplyShoulderCam()
	if not ns.db then
		return
	end
	local yours = ns.db.shoulderCamYours
	if ns.db.shoulderCam then
		yours = yours or {}
		ns.db.shoulderCamYours = yours
		for cvar, value in pairs(CVARS) do
			local now = GetCVar(cvar)
			if now ~= nil and not Same(now, value) then
				if yours[cvar] == nil then
					yours[cvar] = now
				end
				ns.Log("cvar", ("Shoulder Cam: %s %s -> %s"):format(cvar, now, value))
				SetCVar(cvar, value)
			end
		end
	elseif yours then
		for cvar, value in pairs(yours) do
			if not Same(GetCVar(cvar), value) then
				ns.Log("cvar", ("Shoulder Cam: %s back to %s"):format(cvar, value))
				SetCVar(cvar, value)
			end
		end
		ns.db.shoulderCamYours = nil
	end
end

-- For /cine debug shoulder.
function ns.GetShoulderCamDebug()
	return {
		setting = ns.db and ns.db.shoulderCam, applied = ns.db and ns.db.shoulderCamYours ~= nil,
		shoulder = GetCVar("test_cameraOverShoulder"), centered = GetCVar("CameraKeepCharacterCentered"),
	}
end

-- The warning's Disable: the game has put the experimental settings back
-- itself, so the switch goes off and the rest of yours come back.
if ResetTestCvars then
	hooksecurefunc("ResetTestCvars", function()
		if ns.db and ns.db.shoulderCam then
			ns.db.shoulderCam = false
			if ns.db.shoulderCamYours then
				ns.db.shoulderCamYours.test_cameraOverShoulder = nil
			end
			ns.ApplyShoulderCam()
			ns.Print(L["Shoulder Cam turned off: the game's experimental camera warning was disabled."])
			if ns.RefreshOptions then ns.RefreshOptions() end
		end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", ns.ApplyShoulderCam)

function ns.CreateShoulderCamPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Shoulder Cam"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["The camera sits over your right shoulder, with you on the left of the screen."])
	kit.PageSwitch(content, "shoulderCam", L["Enable page"],
		L["On: the camera moves over your right shoulder. This uses one of Blizzard's experimental " ..
		"camera settings: the game shows its experimental camera warning (Accept keeps it working). " ..
		"The game's Keep Character Centered option (Accessibility) stops it, so that's turned off " ..
		"meanwhile. Off: your own settings come back."], intro, ns.ApplyShoulderCam)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Shoulder Cam")
end
