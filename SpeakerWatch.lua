-- /cine debug speakers: where a speaking NPC shows on screen, to see whether a
-- camera could turn toward them as they talk. The game gives no NPC's place in
-- the world, only where their chat bubble and nameplate are drawn. Each say or
-- yell is followed for FOLLOW seconds: its bubble (found by its text) and the
-- speaker's plate (by GUID, else name), as a share of the screen from its
-- middle (x: -1 left edge, +1 right; y: -1 bottom, +1 top), with the angle off
-- the middle that makes, from the camera's field of view. Turn the camera
-- while they talk to see it follow. All of it goes in the log (/reload to
-- save it); the first reading of each line is printed too.
local _, ns = ...

local EVENTS = { "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY" }
local FOLLOW = 6     -- seconds each line is followed
local STEP = 0.5     -- seconds between readings
local FIRST_WAIT = 0.5 -- seconds a bubble or plate gets to show before "none" is logged

local watcher = CreateFrame("Frame")
local followed = {} -- { label, text, guid, name, born, nextAt, printed }
local on = false

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function Text(value)
	if Secret(value) then
		return "secret"
	end
	return tostring(value)
end

-- The camera's horizontal field of view in degrees (cameraFov where the client
-- has it; 90 is the game's usual).
local function FieldOfView()
	local ok, fov = pcall(GetCVar, "cameraFov")
	fov = ok and tonumber(fov)
	return fov or 90, fov and "" or " (guessed)"
end

-- A frame's centre as a share of the screen from its middle, and the angle off
-- the middle; nil and why if it can't be read.
local function Where(frame)
	-- (Retail won't measure nameplates: "Can't measure restricted regions".)
	local ok, x, y = pcall(frame.GetCenter, frame)
	if not ok then
		return nil, "can't be measured"
	end
	if type(x) ~= "number" or type(y) ~= "number" or Secret(x) or Secret(y) then
		return nil, "centre " .. Text(x)
	end
	local okScale, scale = pcall(frame.GetEffectiveScale, frame)
	if not okScale or type(scale) ~= "number" or Secret(scale) then
		return nil, "scale " .. (okScale and Text(scale) or "can't be read")
	end
	scale = scale / WorldFrame:GetEffectiveScale()
	local width, height = WorldFrame:GetWidth(), WorldFrame:GetHeight()
	local sx = (x * scale - width / 2) / (width / 2)
	local sy = (y * scale - height / 2) / (height / 2)
	local fov = FieldOfView()
	local angle = math.deg(math.atan(sx * math.tan(math.rad(fov) / 2)))
	local off = (sx < -1 or sx > 1 or sy < -1 or sy > 1) and " off screen" or ""
	return ("x %+.2f y %+.2f, %+.0f deg%s"):format(sx, sy, angle, off)
end

local function Bubbles(text)
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
		return "bubbles: no API"
	end
	local all = C_ChatBubbles.GetAllChatBubbles(true)
	local readable = C_ChatBubbles.GetAllChatBubbles(false)
	local found = {}
	for _, bubble in ipairs(readable) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) and ns.Flag(bubble:IsVisible())
			and ns.BubbleSays and ns.BubbleSays(bubble, text) then
			local where, why = Where(bubble)
			found[#found + 1] = where or why
		end
	end
	local counts = ("%d shown, %d readable"):format(#all, #readable)
	if #found == 0 then
		return "bubble: none (" .. counts .. ")", false
	end
	return "bubble: " .. table.concat(found, "; ") .. " (" .. counts .. ")", true
end

-- A plate's place: the plate itself, else the first of its parts that can be
-- measured (named, so the log says which).
local PLATE_PARTS = { "UnitFrame", "healthBar", "HealthBarsContainer", "name" }
local function PlateWhere(plate)
	local where, why = Where(plate)
	if where then
		return where
	end
	local tried = { "plate " .. why }
	local unitFrame = plate.UnitFrame
	for _, key in ipairs(PLATE_PARTS) do
		local part = key == "UnitFrame" and unitFrame or (unitFrame and unitFrame[key])
		if type(part) == "table" and part.GetCenter then
			local partWhere, partWhy = Where(part)
			if partWhere then
				return partWhere .. " (from " .. key .. ")"
			end
			tried[#tried + 1] = key .. " " .. partWhy
		end
	end
	return table.concat(tried, ", ")
end

local function Plates(guid, name)
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return "plate: no API"
	end
	local plates = C_NamePlate.GetNamePlates() or {}
	local byName
	for _, plate in ipairs(plates) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then
			local okGuid, plateGuid = pcall(UnitGUID, unit)
			if okGuid and type(guid) == "string" and not Secret(guid) and not Secret(plateGuid)
				and plateGuid == guid then
				local where = PlateWhere(plate)
				return "plate (guid " .. unit .. "): " .. where, true
			end
			local okName, plateName = pcall(UnitName, unit)
			if not byName and okName and type(name) == "string" and not Secret(name) and not Secret(plateName)
				and plateName == name then
				byName = { plate = plate, unit = unit }
			end
		end
	end
	if byName then
		local where = PlateWhere(byName.plate)
		return "plate (name " .. byName.unit .. "): " .. where, true
	end
	local ok, friendly = pcall(GetCVar, "nameplateShowFriendlyNPCs")
	return ("plate: none (%d plates, friendly NPC plates %s)"):format(#plates, ok and Text(friendly) or "?"), false
end

local function OnUpdate()
	local now = GetTime()
	for i = #followed, 1, -1 do
		local line = followed[i]
		if now - line.born > FOLLOW then
			table.remove(followed, i)
		elseif now >= line.nextAt then
			line.nextAt = now + STEP
			local bubble, hasBubble = Bubbles(line.text)
			local plate, hasPlate = Plates(line.guid, line.name)
			local first = not line.printed and (hasBubble or hasPlate or now - line.born >= FIRST_WAIT)
			-- (Before FIRST_WAIT nothing's logged until something shows: the bubble comes a frame or so late.)
			if first or line.printed then
				local report = ("%s +%.1fs: %s; %s"):format(line.label, now - line.born, bubble, plate)
				ns.Log("speakers", report)
				if first then
					line.printed = true
					ns.Print(report)
				end
			end
		end
	end
	if #followed == 0 then
		watcher:SetScript("OnUpdate", nil)
	end
end

watcher:SetScript("OnEvent", function(_, event, text, name, ...)
	if event == "TALKINGHEAD_REQUESTED" then
		-- (A talking head: the portrait box with the line. It gives no unit, so
		-- there's only its name and text to log.)
		local ok, _, _, _, _, lineNumber, numLines, headName, headText = pcall(C_TalkingHead.GetCurrentLineInfo)
		ns.Log("speakers", ("talking head %s (line %s of %s): %s"):format(Text(ok and headName), Text(ok and lineNumber),
			Text(ok and numLines), Text(ok and headText)))
		ns.Print("speakers: talking head " .. Text(ok and headName))
		return
	end
	local guid = select(10, ...)
	if Secret(text) or type(text) ~= "string" then
		ns.Log("speakers", event .. ": text " .. Text(text))
		return
	end
	local now = GetTime()
	local label = ("%s %s (guid %s)"):format(event:gsub("^CHAT_MSG_", ""), Text(name),
		type(guid) == "string" and not Secret(guid) and guid:match("^(%a+)") or Text(guid))
	followed[#followed + 1] = { label = label, text = text, guid = guid, name = name,
		born = now, nextAt = now }
	ns.Log("speakers", label .. ": " .. text)
	watcher:SetScript("OnUpdate", OnUpdate)
end)

-- Returns whether it's on now.
function ns.ToggleSpeakerWatch()
	on = not on
	for _, event in ipairs(EVENTS) do
		if on then
			watcher:RegisterEvent(event)
		else
			watcher:UnregisterEvent(event)
		end
	end
	if C_TalkingHead and C_TalkingHead.GetCurrentLineInfo then
		pcall(on and watcher.RegisterEvent or watcher.UnregisterEvent, watcher, "TALKINGHEAD_REQUESTED")
	end
	if on then
		local fov, guessed = FieldOfView()
		ns.Log("speakers", ("watching; field of view %s%s, screen %.0f x %.0f"):format(fov, guessed,
			WorldFrame:GetWidth(), WorldFrame:GetHeight()))
	else
		followed = {}
		watcher:SetScript("OnUpdate", nil)
	end
	return on
end
