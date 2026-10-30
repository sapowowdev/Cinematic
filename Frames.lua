-- Cinematic: the frames that fade. The built-in fade list, fading and
-- nesting, the minimap shrink, scanning for frames created later, the Issue
-- Reporter, hover, and the Advanced Frames page's lists.
local ADDON_NAME, ns = ...
local L = ns.L

-- Frames to fade, grouped so hovering one member reveals the whole group.
-- Names differ between Classic Era, progression Classic and Retail; missing
-- ones are skipped.
local FRAME_GROUPS = {
	bars = {
		"MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
		"MultiBar5", "MultiBar6", "MultiBar7", "StanceBarFrame", "StanceBar",
		"PetActionBarFrame", "PetActionBar", "PossessBarFrame", "PossessActionBar",
		"MicroButtonAndBagsBar", "MicroMenuContainer", "BagsBar",
		"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
		"StatusTrackingBarManager", "ExtraActionBarFrame", "ZoneAbilityFrame",
		-- The leave vehicle / stop flight button: in the main bar, unless an
		-- action bar addon moves it out (EllesmereUI does).
		"MainMenuBarVehicleLeaveButton",
	},
	sidebars = { "MultiBarLeft", "MultiBarRight" },
	player = { "PlayerFrame", "PetFrame", "TotemFrame" },
	-- The personal resource bars (health, power and class resources under
	-- your character). Retail's is a frame placed in Edit Mode, which the
	-- game only shows or hides, never its alpha; Forever's is your own
	-- nameplate, so a stand-in fades for it (see below).
	prd = { "PersonalResourceDisplayFrame", "CinematicPersonalResource" },
	prdpower = { "CinematicPersonalPower" },
	-- Our mana bar under them (PersonalMana.lua), by its own stand-in.
	prdmana = { "CinematicPersonalMana" },
	totems = {
		"MultiCastActionBarFrame", "MultiCastSummonSpellButton", "MultiCastRecallSpellButton",
		"MultiCastFlyoutFrame", "MultiCastSlotButton1", "MultiCastSlotButton2",
		"MultiCastSlotButton3", "MultiCastSlotButton4",
		"MultiCastActionPage1", "MultiCastActionPage2", "MultiCastActionPage3",
	},
	target = { "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT" },
	-- The party frames when they aren't raid-style (portraits down the left,
	-- their pets' with them): Classic's by name; retail's are found in
	-- PartyFrame (see ScanPartyFrames).
	party = {
		"PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
		"PartyMemberBackground",
	},
	-- In a group, the tab at the left edge and the panel it opens. (The raid
	-- frames themselves, raidplayers and raidpets, are found by ScanRaidFrames.)
	raidmanager = { "CompactRaidFrameManager" },
	-- In battlegrounds, the flag carriers' frames (the arena enemy frames, reused).
	flags = { "ArenaEnemyFramesContainer" },
	-- (With the queue eyes for the dungeon finder and battlegrounds, which can
	-- sit outside the minimap: named differently by client.)
	minimap = {
		"MinimapCluster", "Minimap", "CinematicMinimapButton",
		"LFGMinimapFrame", "MiniMapLFGFrame", "QueueStatusMinimapButton", "MiniMapBattlefieldFrame",
	},
	buffs = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" },
	quests = { "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" },
	-- Classic's quest timer box: its own group, so it can stay up without the tracker.
	questtimer = { "QuestTimerFrame" },
	-- The boxes the game puts under the minimap for a scenario's or quest's
	-- step ("Stay a while", a capture bar...): made as they come, inside this.
	belowminimap = { "UIWidgetBelowMinimapContainerFrame" },
	-- Their kin at the top of the screen: a zone event's timer bar and
	-- text ("Incoming Aqir monstrosity in:"), a scenario's progress.
	topcenter = { "UIWidgetTopCenterContainerFrame" },
	misc = { "DurabilityFrame" },
	swing = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" },
	-- Your cast bars: retail's, Classic's, the pet's (vehicles, mind control)
	-- and Forever's in gamepad mode. (Target and focus cast bars sit inside
	-- their unit frames and fade with them.)
	castbar = {
		"PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame", "CastingBarFrame", "PetCastingBarFrame",
		"GamepadPlayerCastingBarFrame",
	},
	meters = { "DamageMeter" },
	-- The encounter bar: the extra power bar some bosses, quests and vehicles
	-- bring up. Retail's PlayerPowerBarAlt sits inside EncounterBar, which
	-- Edit Mode places (one of them, so it isn't faded twice).
	encounter = { _G.EncounterBar and "EncounterBar" or "PlayerPowerBarAlt" },
	-- Voice chat's notices of who's talking (above the chat): the game makes
	-- them inside this frame.
	voice = { "VoiceActivityManager" },
	-- The Cooldown Manager (retail and Forever). Made when its addon loads,
	-- so a later scan picks it up.
	cooldowns = {
		"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer",
	},
	-- Retail's quest waypoint: the marker in the world, with its distance,
	-- that shows where a tracked quest or map pin is.
	waypoint = { "SuperTrackedFrame" },
	-- WoW Forever's gamepad mode: its action bars, the button hints top left
	-- and the aiming dot in the middle of the screen.
	gamepadbars = { "GamepadMainActionBarFrame" },
	gamepadlegend = { "GamepadPersistentInputLegend" },
	gamepadreticle = { "GamepadReticle" },
	-- Action bar art from addons (Bartender4's art bar); the game's own is
	-- found by FindBarArt.
	barart = {},
	-- The bar behind the zone's name above the minimap: found by FindMinimapHeader.
	minimapheader = {},
	-- What's on it: the zone's name and the tracking button (no names: found
	-- by FindMinimapHeader), the calendar and the clock.
	minimapzone = {},
	minimaptracking = {},
	minimapcalendar = { "GameTimeFrame" },
	minimapclock = { "TimeManagerClockButton" },
	-- WoW Forever's day and night dial by the minimap (MinimapCluster.DielFrame:
	-- found by FindMinimapHeader).
	minimapdial = {},
	chat = {
		"GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
		"QuickJoinToastButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
		"FriendsMicroButton",
	},
}

-- Forever's personal resource bars are your own nameplate, which comes and
-- goes as the game likes: this stand-in fades with the row instead, and the
-- plate takes its alpha (ns.SetPersonalPlateAlpha, Effects). (Clients with
-- no personal resource display have no setting for it.)
-- Their resource bars (mana, rage, energy and the like, with class resources
-- such as combo points) have a row of their own, faded through a stand-in
-- too: while either row fades, those bars stop taking the health bar's fade
-- (their parent's) and take this one (see personalPower.Apply). (One table:
-- this file is near Lua's 200 locals.)
local personalPower = { level = 1, health = 1, mana = 1, held = {}, pass = 0 }
if not ns.isRetail and GetCVar("nameplateShowSelf") ~= nil then
	personalPower.healthStandIn = CreateFrame("Frame", "CinematicPersonalResource", UIParent)
end
if personalPower.healthStandIn or _G.PersonalResourceDisplayFrame then
	personalPower.standIn = CreateFrame("Frame", "CinematicPersonalPower", UIParent)
end
-- (Retail's mana bar of ours, when mana isn't your power, PersonalMana.lua:
-- a row of its own too.)
if ns.isRetail and _G.PersonalResourceDisplayFrame then
	CreateFrame("Frame", "CinematicPersonalMana", UIParent)
end

-- The queue eye (dungeon finder, battlegrounds): Forever pins it to the
-- minimap, retail puts it beside the micro menu, so it goes with either.
table.insert(FRAME_GROUPS[ns.isRetail and "bars" or "minimap"], "QueueStatusButton")

local function AddName(list, name)
	for _, existing in ipairs(list) do
		if existing == name then
			return
		end
	end
	list[#list + 1] = name
end

-- Top-level frames whose names contain any of these are faded too. This picks
-- up client features (and addons) whose exact frame names vary, like the
-- built-in damage meter and swing timer.
local AUTO_PATTERNS = { DamageMeter = "meters", SwingTimer = "swing" }
ns.SCAN_INTERVAL = 5

-- Other addons' frames: ns.ADDON_FRAMES (AddonSupport.lua), filled by Support/.

local function AddOnLoaded(name)
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	return isLoaded and isLoaded(name) and true or false
end

-- Installed, loaded or not (missing ones error or say "MISSING").
function ns.AddOnInstalled(name)
	local getInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
	if not getInfo then
		return false
	end
	local ok, _, _, _, _, reason = pcall(getInfo, name)
	return ok and reason ~= "MISSING"
end
ns.AddOnLoaded = AddOnLoaded

function ns.IsAddonFramesOn(key)
	return ns.db.addonFrames[key] ~= false
end

-- Groups whose frames set their own alpha (see AddFrame).
-- (The party frames dim members out of range.)
local OWN_ALPHA = {
	chat = true, waypoint = true, cooldowns = true, raidplayers = true, raidpets = true, party = true,
}
-- Parts of the raid frames with rows of their own (role icons, names, group
-- titles, buffs, debuffs and the threat highlight). They sit inside the frames
-- they're part of but fade apart from them (not nested), and they don't take
-- the mouse: hovering the raid frames brings them up (their Mouseover group).
local PART_GROUPS = {
	raidroles = true, raidnames = true, raidpetnames = true, raidtitles = true, raidbuffs = true, raiddebuffs = true,
	raidthreat = true, raidtarget = true, raidready = true, partyroles = true, partynames = true, partystatus = true,
}
-- Parts that go only while a row's frames are up (part -> row): the "Party"
-- title sits in no faded frame (the party members fade one by one), so its
-- Always tick would leave it alone on screen.
local followsRow = {}

ns.managed = {}       -- { frame, name, group, alpha, baseAlpha }
local seen = {}
-- A managed frame inside another managed frame already fades with its
-- parent; fading it too would multiply the two and make it lag (half way
-- through a fade-in it would show at 25%, not 50%). Nested frames still track
-- their own fade state (the minimap needs it to know when to shrink) but are
-- drawn at full alpha.
-- The minimap's map image breaks if the minimap sits at alpha 0 while full
-- size, so it's only ever at 0 while shrunk. When nested it follows its
-- parent's fade but runs its own fade MINIMAP_ALPHA_BOOST times faster: nearly
-- opaque straight away (no lag), yet never jumping from 0 to 1 at full size.
local MINIMAP_ALPHA_BOOST = 20

local function VisualAlpha(entry)
	if entry.shrunk then
		return 0
	end
	if not entry.nested then
		return entry.alpha
	end
	if entry.shrinkWhenFaded then
		return math.min(1, entry.alpha * MINIMAP_ALPHA_BOOST)
	end
	return 1
end

-- How far a frame's alpha can read back from what was set (it's stored with
-- less precision) before it counts as the frame setting its own.
local ALPHA_SLACK = 0.005

-- For frames that set their own alpha (see AddFrame): one now at something
-- other than what was last applied set it itself, so take that as its new
-- base alpha and fade relative to it. Checked before every change too, or
-- an alpha it set since would be written over unseen and its new base lost
-- (EllesmereUI's bars start at 0 and come up a moment after login).
-- An alpha set from a secret value reads back secret (EllesmereUI's
-- show-when-health-missing): it can't be compared, so ours just goes back.
-- /cine debug alpha: report frames setting their own alpha (at most twice a
-- second each), to track down one flashing up.
local alphaReportedAt = {}
local function ReportOwnAlpha(entry, alpha, how)
	if not ns.alphaWatch then
		return
	end
	local now = GetTime()
	if (alphaReportedAt[entry.frame] or 0) > now - 0.5 then
		return
	end
	alphaReportedAt[entry.frame] = now
	local shown = (issecretvalue and issecretvalue(alpha)) and "secret" or ("%.2f"):format(alpha)
	ns.Print(("%s [%s] set its alpha to %s (ours %.2f, %s)"):format(entry.name or entry.frame:GetDebugName(),
		entry.group, shown, entry.applied or -1, how))
end

-- (Second result: the alpha it set reads back secret.)
local function TakeOwnAlpha(entry)
	local alpha = entry.frame:GetAlpha()
	if issecretvalue and issecretvalue(alpha) then
		ReportOwnAlpha(entry, alpha, "seen")
		return true, true
	elseif math.abs(alpha - entry.applied) > ALPHA_SLACK then
		ReportOwnAlpha(entry, alpha, "seen")
		entry.baseAlpha = alpha
		return true
	end
	return false
end

-- Parts of a raid frame that ignore its alpha (the outline round your
-- target's frame, which stays bright when out of range dims the rest): found
-- once per frame, a few levels down (a group's frame holds its members').
local LOOSE_PART_GROUPS = { raidplayers = true, raidpets = true }
local function LooseParts(frame, depth, found)
	found = found or {}
	for _, region in ipairs({ frame:GetRegions() }) do
		local ignoring = region.IsIgnoringParentAlpha and region:IsIgnoringParentAlpha()
		-- (A secret answer counts as no.)
		if not (issecretvalue and issecretvalue(ignoring)) and ignoring then
			found[#found + 1] = region
		end
	end
	if depth > 0 then
		for _, child in ipairs({ frame:GetChildren() }) do
			if not (child.IsForbidden and child:IsForbidden()) then
				LooseParts(child, depth - 1, found)
			end
		end
	end
	return found
end

-- Those parts follow the fade too, back to their own alpha once it's over.
-- (Not ones with a row of their own, like the threat highlight: they fade as
-- that, and may have been found before they got it.)
local function FadeLooseParts(entry, alpha)
	entry.looseParts = entry.looseParts or LooseParts(entry.frame, 2)
	for _, part in ipairs(entry.looseParts) do
		if seen[part] then
			part.cinematicAlpha = nil
		elseif alpha < 1 then
			if not part.cinematicAlpha then
				local own = part:GetAlpha()
				part.cinematicAlpha = (issecretvalue and issecretvalue(own)) and 1 or own
			end
			part:SetAlpha(alpha * part.cinematicAlpha)
		elseif part.cinematicAlpha then
			part:SetAlpha(part.cinematicAlpha)
			part.cinematicAlpha = nil
		end
	end
end

local function ApplyAlpha(entry)
	local secret
	if entry.ownAlpha then
		secret = select(2, TakeOwnAlpha(entry))
	end
	local visual = VisualAlpha(entry)
	-- The raid frames dim members out of range with an alpha that reads back
	-- secret on retail: it can't be faded relative to, but while they're
	-- fully up it's left as it is (written over, every member looked in range).
	if not (secret and visual == 1 and LOOSE_PART_GROUPS[entry.group]) then
		entry.applied = visual * (entry.baseAlpha or 1)
		-- (The cast bar while it shows Fishing is kept hidden: hideFishingCastBar, Camera.)
		if entry.frame.cinematicFishingHidden then
			entry.applied = 0
		end
		entry.settingAlpha = true
		entry.frame:SetAlpha(entry.applied)
		entry.settingAlpha = false
		if ns.profiling then
			ns.ProfileCount("SetAlpha on faded frames")
		end
	end
	if LOOSE_PART_GROUPS[entry.group] then
		FadeLooseParts(entry, visual)
	end
end

-- A faded frame's alpha put back if something (Blizzard code, say) changed it.
local function ReapplyIfChanged(entry)
	local alpha = entry.frame:GetAlpha()
	if (issecretvalue and issecretvalue(alpha)) or math.abs(alpha - (entry.applied or -1)) > ALPHA_SLACK then
		ApplyAlpha(entry)
	end
end
ReapplyIfChanged = ns.Profiled("ReapplyIfChanged", ReapplyIfChanged)

-- A part of a frame (a chat window's background, its button column) faded
-- relative to its own alpha, which Blizzard may fade too, and put back to it
-- once alpha is 1 again.
function ns.FadeRelative(part, alpha)
	if alpha < 1 then
		local own = part:GetAlpha()
		if issecretvalue and issecretvalue(own) then
			own = nil
		end
		if not part.cinematicOwnAlpha or (own and math.abs(own - part.cinematicSetAlpha) > ALPHA_SLACK) then
			-- (First time, or Blizzard set its own since.)
			part.cinematicOwnAlpha = own or 1
		end
		part.cinematicSetAlpha = alpha * part.cinematicOwnAlpha
		if not own or math.abs(own - part.cinematicSetAlpha) > ALPHA_SLACK then
			part:SetAlpha(part.cinematicSetAlpha)
		end
	elseif part.cinematicOwnAlpha then
		part:SetAlpha(part.cinematicOwnAlpha)
		part.cinematicOwnAlpha, part.cinematicSetAlpha = nil, nil
	end
end

local function SyncOwnAlpha(entry)
	if TakeOwnAlpha(entry) then
		ApplyAlpha(entry)
	end
end

-- The cast bars set themselves to full alpha as each cast starts, so while
-- faded they'd flash up until the next tick put ours back. Their own events
-- (and showing) are followed by ours straight away instead. Script hooks,
-- not method hooks (see AddFrame); one for a frame no longer faded does
-- nothing. Once fully shown they're left alone, so their own fade-out as a
-- cast ends still plays.
-- (One local for all of it: the file is near Lua's 200 locals.)
-- entries: frame -> its entry while managed (false once not); fades: frame -> its fade animations.
local castBars = { entries = {}, fades = {}, none = {} }
-- A fade animation can't be stopped as it starts (see onFadeAnim): one left
-- over would carry on once the bar shows again, and a cast started soon after
-- another was stopped flashed up. So they're stopped after the bar's own
-- events, as it shows and as it updates.
function castBars.StopFades(frame)
	for _, group in ipairs(castBars.fades[frame] or castBars.none) do
		if ns.Flag(group:IsPlaying()) then
			group:Stop()
		end
	end
end
-- A bar finishing while faded doesn't hide itself: it hides at the end of its
-- fade-out, which the game skips for a bar at alpha 0 (as at every login and
-- /reload, where it "finishes" the cast you aren't making). It then showed,
-- full, once the UI came back. So a faded bar with nothing being cast is
-- hidden, as that fade would have. (Not in Edit Mode, which shows the bar.)
function castBars.HideIfIdle(frame)
	if frame.casting or frame.channeling or frame.reverseChanneling or frame.isInEditMode
		or not ns.Flag(frame:IsShown()) then
		return
	end
	frame:Hide()
end
function ns.ReapplyCastBar(frame)
	local entry = castBars.entries[frame]
	if entry and entry.alpha < 1 then
		castBars.StopFades(frame)
		ApplyAlpha(entry)
		castBars.HideIfIdle(frame)
	end
end
-- (Camera's Fishing cast bar hiding calls it too, after setting the bar's alpha itself.)
castBars.onScript = ns.Profiled("Cast bar fade hook", ns.ReapplyCastBar)
-- And after each of their updates while shown, before they're drawn: a bar
-- can be shown and set to full alpha by something other than its own events
-- (it flashed up as some casts started until the next tick).
castBars.onUpdate = ns.Profiled("Cast bar update hook", function(frame)
	local entry = castBars.entries[frame]
	if entry and entry.alpha < 1 then
		castBars.StopFades(frame)
		ReapplyIfChanged(entry)
		castBars.HideIfIdle(frame)
	end
end)

-- Their fade-out as a cast ends, or is interrupted (held a moment first), is
-- an alpha animation, which shows them whatever alpha they're set to: an
-- interrupted cast stayed up. While faded the bar is hidden instead, as at the
-- animation's end, and the animation stopped once its start is over (see
-- StopFades). (Not in Edit Mode, which shows the bar.)
castBars.onFadeAnim = ns.Profiled("Cast bar fade animation", function(group)
	local frame = group:GetParent()
	local entry = castBars.entries[frame]
	if not entry or entry.alpha >= 1 then
		return
	end
	local editMode = _G.EditModeManagerFrame
	if editMode and editMode.IsEditModeActive and ns.Flag(editMode:IsEditModeActive()) then
		return
	end
	frame:Hide()
end)

-- Whether an animation group fades the bar itself (not its spark, glow and the like).
function castBars.FadesFrame(group, frame)
	for _, anim in ipairs({ group:GetAnimations() }) do
		if anim:GetObjectType() == "Alpha" and (anim:GetTarget() or group:GetParent()) == frame then
			return true
		end
	end
	return false
end

function castBars.Hook(entry)
	local frame = entry.frame
	if castBars.entries[frame] == nil and frame.HookScript then
		frame:HookScript("OnEvent", castBars.onScript)
		frame:HookScript("OnShow", castBars.onScript)
		frame:HookScript("OnUpdate", castBars.onUpdate)
		if frame.GetAnimationGroups then
			for _, group in ipairs({ frame:GetAnimationGroups() }) do
				local ok, fades = pcall(castBars.FadesFrame, group, frame)
				if ok and fades then
					group:HookScript("OnPlay", castBars.onFadeAnim)
					castBars.fades[frame] = castBars.fades[frame] or {}
					table.insert(castBars.fades[frame], group)
				end
			end
		end
	end
	castBars.entries[frame] = entry
end

-- Some addons set their own frames' alpha all the time (EllesmereUI: target
-- changes, combat, mouseover), and a frame caught at that alpha even for a
-- moment flashes up. So their frames (only those: never the game's, whose own
-- calls a hook would get in the way of) have SetAlpha followed straight away by
-- ours, taking what it set as the new base. A hook can't be taken off: one
-- for a frame no longer faded does nothing.
local alphaHooked = {} -- frame -> its entry while managed (false once not)

local OnOwnSetAlpha = ns.Profiled("Own SetAlpha hook", function(frame, alpha)
	local entry = alphaHooked[frame]
	if not entry or entry.settingAlpha then
		return
	end
	if (issecretvalue and issecretvalue(alpha)) or math.abs(alpha - (entry.applied or -1)) > ALPHA_SLACK then
		ReportOwnAlpha(entry, alpha, "hooked")
	end
	if not (issecretvalue and issecretvalue(alpha)) then
		entry.baseAlpha = alpha
	end
	entry.applied = alpha -- (so ApplyAlpha doesn't take it again)
	ApplyAlpha(entry)
end)

local function HookOwnAlpha(entry)
	if alphaHooked[entry.frame] == nil then
		hooksecurefunc(entry.frame, "SetAlpha", OnOwnSetAlpha)
	end
	alphaHooked[entry.frame] = entry
end

-- What supported addons' setups (Support/) ask for, filled only once the
-- addon has loaded. Frames that set their own alpha (by name, or the frame
-- itself for unnamed ones), those of them hooked as well, and game frames an
-- addon hides for good (fading them in again would bring them back).
local ownAlphaNames, ownAlphaFrames = {}, {}
local hookedNames, hookedFrames = {}, {}
local leftAlone = {}
-- Advanced Frames groups hooked (hookAlpha), from their rows.
local HOOKED_GROUPS = {}
for _, known in ipairs(ns.ADDON_FRAMES) do
	if known.hookAlpha then
		HOOKED_GROUPS["addon:" .. known.key] = true
	end
end

-- The options pages' master switches (handle<...>, all on to start with).
-- The Standard Frames page's: off, the frames in its groups aren't faded
-- (let go, their own alpha back). It covers every built-in group but the
-- chat and gamepad ones, whose own pages' switches do the same for them. The
-- Advanced Frames page's covers other addons' and added frames. The other
-- pages' (Minimap, Quest tracker...) only turn that page's extras on or off
-- (see ns.PageOn): their frames still fade as their Standard Frames rows say.
local GROUP_SWITCH = {
	minimap = "handleMinimap", minimapheader = "handleMinimap", minimaptracking = "handleMinimap",
	minimapcalendar = "handleMinimap", minimapzone = "handleMinimap", minimapclock = "handleMinimap",
	minimapdial = "handleMinimap", quests = "handleQuests", questtimer = "handleQuests", waypoint = "handleQuests",
	buffs = "handleBuffs", cooldowns = "handleCooldowns", chat = "handleChat", swing = "handleSwing",
	gamepadbars = "handleGamepad", gamepadlegend = "handleGamepad", gamepadreticle = "handleGamepad",
}
local OWN_PAGE_GROUPS = { chat = true, gamepadbars = true, gamepadlegend = true, gamepadreticle = true }
ns.HANDLE_SWITCHES = {
	"handleFrames", "handleAddonFrames", "handleGamepad", "handleMinimap", "handleQuests", "handleBuffs",
	"handleCooldowns", "handleChat", "handleSwing",
}
local function GroupHandled(group)
	local db = ns.db
	if group:find("^addon:") or group:find("^extra:") then
		return db.handleAddonFrames and true or false
	end
	if not OWN_PAGE_GROUPS[group] and not db.handleFrames then
		return false
	end
	if not OWN_PAGE_GROUPS[group] then
		return true
	end
	return db[GROUP_SWITCH[group]] and true or false
end
ns.GroupHandled = GroupHandled

-- Whether a page's switch is on, for its extras (Keep open, reveals, peeks...).
function ns.PageOn(switch)
	return ns.db[switch] ~= false
end

local function AddFrame(frame, group)
	if not frame or seen[frame] or not frame.SetAlpha or frame == ns.letterbox then
		return false
	end
	if frame.IsForbidden and frame:IsForbidden() then
		return false
	end
	local name = frame:GetName()
	if name and (ns.db.ignoredFrames[name] or leftAlone[name]) then
		return false
	end
	-- (Its page's master switch off: left alone.)
	if not GroupHandled(group) then
		return false
	end
	seen[frame] = true
	local entry = {
		frame = frame, name = name, group = group, alpha = 1,
		shrinkWhenFaded = frame == Minimap,
	}
	ns.managed[#ns.managed + 1] = entry
	-- (Cast bars too, so their row alone decides: see castBars. And what's on
	-- the minimap's header (minimapzone, minimapclock...), so it can go while
	-- the map stays.)
	if (group == "questtimer" or group == "castbar" or group:find("^minimap.")) and frame.SetIgnoreParentAlpha then
		frame:SetIgnoreParentAlpha(true)
	end
	if group == "castbar" then
		castBars.Hook(entry)
	end
	-- Classic clients' raid frames sit inside the Raid Frame Manager: they
	-- don't fade with it (their own rows fade them).
	local raidFrames = _G.CompactRaidFrameContainer
	if group == "raidmanager" and raidFrames and raidFrames.SetIgnoreParentAlpha
		and raidFrames:GetParent() == frame then
		raidFrames:SetIgnoreParentAlpha(true)
	end
	-- Classic clients' pet frame sits inside the player frame: it fades on its
	-- own, so an unhappy pet can stay up while the portrait goes.
	if name == "PetFrame" and frame.SetIgnoreParentAlpha and frame:GetParent() == _G.PlayerFrame then
		frame:SetIgnoreParentAlpha(true)
	end

	-- Chat frames manage their own alpha (the input bar sits faint until you
	-- press Enter), and so do the waypoint (it dims as you look past it), the
	-- Cooldown Manager (its opacity setting) and other addons' frames (their
	-- own fades). Track the alpha last asked for, fade relative to it, and
	-- return to it rather than to fully opaque. Watched each frame rather than
	-- by hooking SetAlpha: hooking a game frame's methods breaks the game's
	-- own calls to them ("attempt to call a nil value"). Some addons' own
	-- frames are hooked as well (see HookOwnAlpha).
	local hooked = (name and hookedNames[name]) or hookedFrames[frame] or HOOKED_GROUPS[group]
	if hooked or OWN_ALPHA[group] or group:find("^addon:") or (name and ownAlphaNames[name])
		or ownAlphaFrames[frame] then
		local alpha = frame:GetAlpha()
		entry.baseAlpha = (issecretvalue and issecretvalue(alpha)) and 1 or alpha
		entry.applied = entry.baseAlpha
		entry.ownAlpha = true
		if hooked then
			HookOwnAlpha(entry)
		end
	end
	return true
end

-- Frames that fade on their own even though they sit inside another faded
-- frame, so they can be shown separately (target of target during combat).
-- The quest timer can sit inside the quest tracker: it ignores the tracker's
-- fade (see AddFrame) so it can stay up while the tracker is faded.
-- The cast bars too (retail's can be locked to the player frame).
local NEVER_NESTED = { TargetFrameToT = true, FocusFrameToT = true, QuestTimerFrame = true }
for _, name in ipairs(FRAME_GROUPS.castbar) do
	NEVER_NESTED[name] = true
end
-- The chat buttons too (Classic clients put them inside the chat window):
-- a window peeking for a message doesn't bring them up, their row
-- ("Chat tabs and buttons", Mouseover groups) does.
for _, name in ipairs(FRAME_GROUPS.chat) do
	if name ~= "GeneralDockManager" then
		NEVER_NESTED[name] = true
	end
end

local function RecomputeNesting()
	for _, entry in ipairs(ns.managed) do
		local nested = false
		local frame = entry.frame
		local parent = frame:GetParent()
		while parent and parent ~= UIParent and not NEVER_NESTED[entry.name] and not PART_GROUPS[entry.group] do
			-- (A parent's fade doesn't reach through a frame ignoring it.)
			local ignoring = frame.IsIgnoringParentAlpha and frame:IsIgnoringParentAlpha()
			if not (issecretvalue and issecretvalue(ignoring)) and ignoring then
				break
			end
			if seen[parent] then
				nested = true
				break
			end
			frame, parent = parent, parent:GetParent()
		end
		if nested ~= (entry.nested or false) then
			entry.nested = nested
			ApplyAlpha(entry)
		end
	end
end

-- The minimap's size can't change in combat if an addon put a secure button
-- on it (that makes it protected): the shrink waits for the fight to end.
function ns.ScaleBlocked(frame)
	return InCombatLockdown() and ns.Flag(frame:IsProtected())
end

-- Shrunk, the minimap still collapses into its anchor corner, where its
-- player arrow (which ignores alpha) shows as a single pixel. So while shrunk
-- it's also moved off the right edge of the screen, and its own anchors are
-- put back when it grows. (The offset is in its shrunk scale: 20000 is a few
-- hundred pixels.) A map clamped to the screen (WoW Forever's is) gets pulled
-- back into the top-right corner, so that's switched off while it's out there.
do -- (a block: this file is at Lua's 200-local cap)
local PARK_OFFSET = 20000

-- (Not x == PARK_OFFSET: the client can hand the offset back rounded, like
-- 19999.998. And not just any big offset: EllesmereUI anchors the shrunk map
-- far out too, see ParkShrunk.)
local function IsParkPoint(point, relativeTo, relativePoint, x)
	return point == "TOPLEFT" and relativeTo == UIParent and relativePoint == "TOPRIGHT" and type(x) == "number"
		and not (issecretvalue and issecretvalue(x)) and math.abs(x - PARK_OFFSET) < 1
end

-- EllesmereUI puts the map back on its saved spot divided by the map's own
-- scale, so the shrunk map lands right where it was (CENTER 130666 for 1306).
-- An offset past the screen's size that's on it once scaled is one of those:
-- taken back to what it is at full size, so the map grows back in place.
local function FullSizeOffsets(frame, entry, x, y)
	local ratio = frame:GetScale() / (entry.savedScale or 1)
	if ratio >= 1 or type(x) ~= "number" or type(y) ~= "number"
		or (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then
		return x, y
	end
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if (math.abs(x) > width or math.abs(y) > height)
		and math.abs(x * ratio) <= width and math.abs(y * ratio) <= height then
		return x * ratio, y * ratio
	end
	return x, y
end

function ns.ParkShrunk(entry)
	local frame = entry.frame
	local points = {}
	for i = 1, frame:GetNumPoints() do
		local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, i)
		if not ok or type(point) ~= "string" then
			return -- (can't read them back: leave it where it is)
		end
		if IsParkPoint(point, relativeTo, relativePoint, x) then
			points = nil -- (already parked: keep the anchors saved before)
			break
		end
		x, y = FullSizeOffsets(frame, entry, x, y)
		points[i] = { point, relativeTo, relativePoint, x, y }
	end
	entry.savedPoints = points or entry.savedPoints
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", PARK_OFFSET, 0)
	if frame.IsClampedToScreen and ns.Flag(frame:IsClampedToScreen()) then
		entry.savedClamped = true
		frame:SetClampedToScreen(false)
	end
end

-- Something laid it out again while shrunk (it's back on its own anchors).
function ns.IsParked(entry)
	local ok, point, relativeTo, relativePoint, x = pcall(entry.frame.GetPoint, entry.frame, 1)
	return ok and IsParkPoint(point, relativeTo, relativePoint, x)
end

-- Shrunk and moved off, but back on the screen: laid out again on its own
-- anchors (EllesmereUI does), or clamped to the screen again.
function ns.ParkUndone(entry)
	local frame = entry.frame
	return entry.savedPoints and (not ns.IsParked(entry)
		or (frame.IsClampedToScreen and ns.Flag(frame:IsClampedToScreen())))
end

function ns.UnparkShrunk(entry)
	local points = entry.savedPoints
	entry.savedPoints = nil
	if entry.savedClamped then
		entry.savedClamped = nil
		entry.frame:SetClampedToScreen(true)
	end
	if not points or not ns.IsParked(entry) then
		return
	end
	local frame = entry.frame
	frame:ClearAllPoints()
	for _, p in ipairs(points) do
		frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
	end
end

-- Kept full size while faded (a Reveal tick, Minimap page: NodeSweep.lua
-- sweeps it), the minimap is moved off the screen the same way, unshrunk:
-- its quest areas (the blue shapes) ignore its alpha, and on WoW Forever
-- nothing else hides them (tested). The sweep still reads it out there
-- (tested). Its rect is saved first, so hover still works over the empty spot.
function ns.ParkFullSize(entry)
	if not entry.parkedFullSize then
		entry.savedRect = { entry.frame:GetRect() }
		entry.savedEffectiveScale = entry.frame:GetEffectiveScale()
		entry.parkedFullSize = true
	elseif not ns.ParkUndone(entry) then
		return
	end
	-- (Again if laid out again or clamped again meanwhile.)
	ns.ParkShrunk(entry)
end

function ns.UnparkFullSize(entry)
	entry.parkedFullSize = nil
	ns.UnparkShrunk(entry)
end
end

local function RemoveFrame(frame)
	for i, entry in ipairs(ns.managed) do
		if entry.frame == frame then
			if alphaHooked[frame] then
				alphaHooked[frame] = false
			end
			if castBars.entries[frame] then
				castBars.entries[frame] = false
			end
			frame:SetAlpha(frame.cinematicFishingHidden and 0 or entry.baseAlpha or 1)
			if entry.looseParts then FadeLooseParts(entry, 1) end
			if entry.shrunk and ns.ScaleBlocked(frame) then
				local scale = entry.savedScale or 1
				local waiter = CreateFrame("Frame")
				waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
				waiter:SetScript("OnEvent", function(self)
					self:UnregisterAllEvents()
					frame:SetScale(scale)
					ns.UnparkShrunk(entry)
				end)
			elseif entry.shrunk then
				frame:SetScale(entry.savedScale or 1)
				ns.UnparkShrunk(entry)
			elseif entry.parkedFullSize and not ns.ScaleBlocked(frame) then
				ns.UnparkFullSize(entry)
			end
			table.remove(ns.managed, i)
			entry.removed = true -- (for script hooks still holding it: see HookPartyScripts)
			seen[frame] = nil
			RecomputeNesting()
			return true
		end
	end
	return false
end

-- The built-in group a frame name belongs to by pattern, if any.
local function AutoPatternGroup(name)
	for pattern, group in pairs(AUTO_PATTERNS) do
		if name:find(pattern) then
			return group
		end
	end
end

-- Windows (settings, spellbook, popups) are never faded as extras: fading
-- one you're using leaves it invisible but still taking your clicks and keys.
-- Escape-closable and panel windows, ones the reveal lists know, and anything
-- drawn in the dialog strata or above.
local WINDOW_STRATA = { DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

local function IsWindow(frame, name)
	if ns.WINDOWS[name] or (UIPanelWindows and UIPanelWindows[name]) then
		return true
	end
	for _, special in ipairs(UISpecialFrames or {}) do
		if special == name then
			return true
		end
	end
	return WINDOW_STRATA[frame:GetFrameStrata()] or false
end

local function ScanTopLevelFrames()
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not seen[frame] and not (frame.IsForbidden and frame:IsForbidden()) then
			local name = frame:GetName()
			if name then
				local group = AutoPatternGroup(name)
				if group then
					AddFrame(frame, group)
				elseif ns.db.extraFrames[name] and not IsWindow(frame, name) then
					AddFrame(frame, "extra:" .. name)
				end
			end
		end
	end
	for name in pairs(ns.db.extraFrames) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetFrameStrata and not (frame.IsForbidden and frame:IsForbidden())
			and not IsWindow(frame, name) then
			AddFrame(frame, "extra:" .. name)
		end
	end
end

local function ScanAddonFrames()
	for _, known in ipairs(ns.ADDON_FRAMES) do
		if known.loaded and ns.IsAddonFramesOn(known.key) then
			local group = "addon:" .. known.key
			for _, name in ipairs(known.names or {}) do
				AddFrame(_G[name], group)
			end
			if known.match or known.patterns then
				for _, frame in ipairs({ UIParent:GetChildren() }) do
					if not seen[frame] and not (frame.IsForbidden and frame:IsForbidden()) then
						local name = frame:GetName()
						if name then
							for _, pattern in ipairs(known.patterns or {}) do
								if name:find(pattern) then
									AddFrame(frame, group)
									break
								end
							end
						elseif known.match and known.match(frame) then
							AddFrame(frame, group)
						end
					end
				end
			end
		end
	end
end

-- Blizzard's PTR/beta Issue Reporter is built from unnamed frames, so it
-- can't be added by name. Find it through its global table, or failing that
-- by an unnamed top-level frame showing the text "Issue Reporter".
-- Forbidden frames error on almost any method call, so check this first.
local function IsForbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end

local function IsFrame(value)
	return type(value) == "table" and type(value.GetObjectType) == "function"
		and type(value.SetAlpha) == "function"
end

local function TopLevelAncestor(frame)
	while frame do
		local parent = frame:GetParent()
		if parent == UIParent then
			return frame
		elseif parent == nil then
			return nil
		end
		frame = parent
	end
end

-- The Issue Reporter's text is never in a frame this big. Unpacking a frame
-- with thousands of regions (EllesmereUI's unlock-mode tools) overflows the
-- Lua stack in the game's GetRegions: a client crash pcall can't catch.
local MAX_PARTS = 100
local COUNT_METHOD = { GetRegions = "GetNumRegions", GetChildren = "GetNumChildren" }

-- A frame's regions or children as a list, or nil when it's off limits:
-- a frame that isn't forbidden itself can still hold forbidden parts, and
-- then GetRegions/GetChildren error. Frames with too many parts are skipped.
local function ReadParts(frame, method)
	local countMethod = frame[COUNT_METHOD[method]]
	if type(countMethod) ~= "function" then
		return nil
	end
	local ok, count = pcall(countMethod, frame)
	if not ok or type(count) ~= "number" or count > MAX_PARTS then
		return nil
	end
	local parts = { pcall(frame[method], frame) }
	if not table.remove(parts, 1) then
		return nil
	end
	return parts
end

-- Hidden frames are skipped: a hidden reporter gets found by a later scan once
-- it shows, and addons build pages off-screen in hidden frames (EllesmereUI's
-- search index), which crash the client when read mid-build.
local function HasIssueReporterText(frame, depth)
	if IsForbidden(frame) or not ns.Flag(frame:IsShown()) then
		return false
	end
	for _, region in ipairs(ReadParts(frame, "GetRegions") or {}) do
		if not IsForbidden(region) and region.GetText then
			local text = region:GetText()
			if type(text) == "string" and not (issecretvalue and issecretvalue(text))
				and text:find("Issue") and text:find("Reporter") then
				return true
			end
		end
	end
	if depth > 0 then
		for _, child in ipairs(ReadParts(frame, "GetChildren") or {}) do
			if HasIssueReporterText(child, depth - 1) then
				return true
			end
		end
	end
	return false
end

local function FindIssueReporter()
	local reporter = _G.PTR_IssueReporter
	if type(reporter) == "table" then
		if IsFrame(reporter) then
			AddFrame(TopLevelAncestor(reporter), "issueReporter")
		end
		for _, value in pairs(reporter) do
			if IsFrame(value) and not IsForbidden(value) then
				AddFrame(TopLevelAncestor(value), "issueReporter")
			end
		end
	end
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not seen[frame] and not IsForbidden(frame) and not frame:GetName()
			and HasIssueReporterText(frame, 2) then
			AddFrame(frame, "issueReporter")
		end
	end
end

-- Action bar 1's art (the Standard Frames page's Action bar art row): the
-- end caps and the bar the buttons sit on, by name on older clients and by
-- parentKey on newer ones. The pieces are textures (which the fade's frame
-- code can't take), so a frame of ours over the bar stands in for them in
-- the fade, and its alpha is copied onto them. They ignore the bar's own
-- alpha, so they can stay up while its buttons fade, or the other way round.
local BAR_ART_NAMES = {
	"MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarArtFrameBackground",
	"MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
}
local BAR_ART_KEYS = {
	MainMenuBarArtFrame = { "LeftEndCap", "RightEndCap" },
	MainMenuBar = { "EndCaps", "BorderArt" },
	MainActionBar = { "EndCaps", "BorderArt" },
}
local barArt, barArtSeen = {}, {}
local artStandIn

local function AddBarArt(region)
	if type(region) ~= "table" or barArtSeen[region] or type(region.SetAlpha) ~= "function"
		or IsForbidden(region) then
		return
	end
	-- (A bar an addon took over is left alone, its art with it.)
	local bar = TopLevelAncestor(region)
	if bar and bar:GetName() and leftAlone[bar:GetName()] then
		return
	end
	barArtSeen[region] = true
	barArt[#barArt + 1] = { region = region, bar = bar and bar:GetName() }
	if region.SetIgnoreParentAlpha then
		region:SetIgnoreParentAlpha(true)
	end
	if not artStandIn then
		artStandIn = CreateFrame("Frame", nil, UIParent)
		artStandIn:SetAllPoints(bar or region)
		hooksecurefunc(artStandIn, "SetAlpha", function(_, alpha)
			for _, art in ipairs(barArt) do
				art.region:SetAlpha(alpha)
			end
		end)
	end
	region:SetAlpha(artStandIn:GetAlpha())
end

local function FindBarArt()
	for _, name in ipairs(BAR_ART_NAMES) do
		AddBarArt(_G[name])
	end
	for barName, keys in pairs(BAR_ART_KEYS) do
		local bar = _G[barName]
		if type(bar) == "table" then
			for _, key in ipairs(keys) do
				AddBarArt(bar[key])
			end
		end
	end
	if artStandIn then
		AddFrame(artStandIn, "barart")
	end
end

-- The minimap's header art (the Standard Frames page's Minimap header row):
-- the bar behind the zone's name above the minimap. WoW Forever's is the zone
-- button's StateTexture (and AddTexture, its hover glow); retail's BorderTop
-- and older clients' MinimapBorderTop are unverified. Textures, so a frame of
-- ours over the bar stands in for them in the fade, as for the action bar
-- art. They ignore the minimap's own fade, so the zone's name can float
-- without its bar, or the bar stay up while the map goes.
do
	local headerArt, headerSeen = {}, {}
	local headerStandIn

	local function AddHeaderArt(region, over)
		if type(region) ~= "table" or headerSeen[region] or type(region.SetAlpha) ~= "function"
			or IsForbidden(region) then
			return
		end
		headerSeen[region] = true
		headerArt[#headerArt + 1] = region
		if region.SetIgnoreParentAlpha then
			region:SetIgnoreParentAlpha(true)
		end
		if not headerStandIn then
			headerStandIn = CreateFrame("Frame", nil, UIParent)
			headerStandIn:SetAllPoints(over or region)
			hooksecurefunc(headerStandIn, "SetAlpha", function(_, alpha)
				for _, art in ipairs(headerArt) do
					art:SetAlpha(alpha)
				end
			end)
		end
		region:SetAlpha(headerStandIn:GetAlpha())
	end

	function ns.FindMinimapHeader()
		local cluster = type(_G.MinimapCluster) == "table" and _G.MinimapCluster or nil
		-- An addon that hides the cluster for good (EllesmereUI's minimap
		-- keeps it at alpha 0): its parts are left in it, or ignoring its
		-- alpha would bring them back.
		if leftAlone.MinimapCluster then
			cluster = nil
		end
		local bar = (cluster and cluster.ZoneTextButton) or (not leftAlone.MinimapCluster and _G.MinimapZoneTextButton)
		if type(bar) == "table" then
			AddHeaderArt(bar.StateTexture, bar)
			AddHeaderArt(bar.AddTexture, bar)
		end
		AddHeaderArt(cluster and cluster.BorderTop)
		AddHeaderArt(_G.MinimapBorderTop)
		-- The dark square behind the tracking button (Forever: atlas
		-- UI-HUD-Minimap-Button), and any like it behind the calendar.
		local tracking = cluster and cluster.Tracking
		if type(tracking) == "table" then
			AddHeaderArt(tracking.Background)
			AddFrame(tracking, "minimaptracking")
		end
		-- The zone's name: its button, whose bar art ignores its fade (above).
		AddFrame(bar, "minimapzone")
		AddFrame(cluster and cluster.DielFrame, "minimapdial")
		local calendar = _G.GameTimeFrame
		if type(calendar) == "table" and calendar.GetRegions and not IsForbidden(calendar)
			and not leftAlone.GameTimeFrame then
			for _, region in ipairs({ calendar:GetRegions() }) do
				local atlas = region.GetAtlas and region:GetAtlas()
				if type(atlas) == "string" and atlas:lower() == "ui-hud-minimap-button" then
					AddHeaderArt(region)
				end
			end
			AddHeaderArt(calendar.Background)
		end
		if headerStandIn then
			AddFrame(headerStandIn, "minimapheader")
		end
	end
end

-- Saved extras that are really built-in frames (added before /cine add
-- checked for that) would show in the extras list, where Stop would break the
-- built-in fade. Drop them.
function ns.PruneBuiltInExtras()
	for _, names in pairs(FRAME_GROUPS) do
		for _, name in ipairs(names) do
			ns.db.extraFrames[name] = nil
		end
	end
end

local function SyncAllOwnAlpha()
	for _, entry in ipairs(ns.managed) do
		if entry.ownAlpha then
			SyncOwnAlpha(entry)
		elseif ns.alphaWatch and entry.applied then
			-- (/cine debug alpha: the rest are only reported, to find a frame
			-- that should count as setting its own.)
			local alpha = entry.frame:GetAlpha()
			if (issecretvalue and issecretvalue(alpha)) or math.abs(alpha - entry.applied) > ALPHA_SLACK then
				ReportOwnAlpha(entry, alpha, "not followed")
			end
		end
	end
end

-- Every frame, not just on the update tick, when a supported addon asks
-- (ns.syncEveryFrame): a frame it sets the alpha of would otherwise show at
-- it for several frames until the next tick at a high frame rate. Otherwise
-- the tick does (see UpdateFrames).
ns.SyncOwnAlphas = SyncAllOwnAlpha

-- Supported addons' own searches for their frames (Support/), run with each scan.
local scanners = {}

-- Safe to call repeatedly: frames already managed are skipped, and frames
-- created after login get picked up on a later call.
function ns.BuildManagedList()
	for group, names in pairs(FRAME_GROUPS) do
		for _, name in ipairs(names) do
			AddFrame(_G[name], group)
		end
	end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		-- The input box sits on UIParent, not in its chat frame, so it's
		-- faded on its own (it sets its own alpha too: see AddFrame).
		AddFrame(_G["ChatFrame" .. i], "chat")
		AddFrame(_G["ChatFrame" .. i .. "EditBox"], "chat")
	end
	for _, scan in ipairs(scanners) do
		scan()
	end
	ScanTopLevelFrames()
	ScanAddonFrames()
	FindIssueReporter()
	FindBarArt()
	ns.FindMinimapHeader()
	RecomputeNesting()
end

-- Switching a supported addon off puts its frames back at once;
-- switching it on fades them from the next scan.
function ns.SetAddonFramesOn(key, on)
	ns.db.addonFrames[key] = on
	if on then
		ns.BuildManagedList()
		return
	end
	local group = "addon:" .. key
	for i = #ns.managed, 1, -1 do
		local entry = ns.managed[i]
		if entry.group == group then
			RemoveFrame(entry.frame)
		end
	end
end

-- The minimap's player arrow and icons ignore alpha, and hiding the minimap
-- leaves its map image blank once it's shown again. So once fully faded it's
-- shrunk to almost nothing instead (icons shrink with it), and its size is put
-- back as soon as it starts to fade in. Its on-screen rect is saved first so
-- hover still works over the empty spot.
local SHRUNK_SCALE = 0.01
ns.SHRUNK_SCALE = SHRUNK_SCALE
-- Once shrunk, stay shrunk (at alpha 0) for a minimum time, so fading out and
-- hovering straight back doesn't shrink and unshrink in quick succession.
local MIN_SHRUNK_TIME = 0.5

local function ShrinkEntry(entry)
	local frame = entry.frame
	entry.savedScale = frame:GetScale()
	-- (Shrunk again while still parked: it only had its size put back, so its
	-- saved place and rect still stand.)
	local parked = entry.savedPoints and ns.IsParked(entry)
	if not parked then
		entry.savedRect = { frame:GetRect() }
		entry.savedEffectiveScale = frame:GetEffectiveScale()
	end
	-- (/cine debug nodes park: kept full size off the screen instead, to see
	-- whether the game keeps adding tracking dots to it there.)
	frame:SetScale(ns.parkMinimapFullSize and frame == Minimap and entry.savedScale or SHRUNK_SCALE)
	if not parked then
		ns.ParkShrunk(entry)
	end
	entry.parkedFullSize = nil -- (parked full size before: now shrunk there)
	entry.shrunk = true
	entry.shrunkAt = GetTime()
end

-- Run once the minimap has its size back (see ns.OnMinimapRestored): an addon
-- laying it out while shrunk can leave its parts out of place.
local restoredHandlers = {}

-- Indoors (buildings, caves, Ironforge) the game stops updating the minimap's
-- indoor map while it's hidden (shrunk, or at any alpha below full), so after
-- walking around it comes back blank, black or half drawn. Outdoors it keeps
-- up. A zoom step and back on the next frame makes it draw the map again with
-- no visible flicker, but only once it's fully shown: so each time it grows
-- back indoors, that's done at the end of its fade-in. (Or the minimap can
-- stay up indoors: minimapIndoors, Minimap page.)
local minimapNeedsRedraw = false

local function RedrawMinimapWhenShown()
	if not minimapNeedsRedraw or not ns.Flag(Minimap:IsVisible()) or Minimap:GetEffectiveAlpha() < 0.99 then
		return
	end
	minimapNeedsRedraw = false
	local zoom = Minimap:GetZoom()
	local other = zoom > 0 and zoom - 1 or zoom + 1
	if other > Minimap:GetZoomLevels() - 1 then
		return
	end
	Minimap:SetZoom(other)
	C_Timer.After(0, function()
		if Minimap:GetZoom() == other then -- (unless you zoomed meanwhile)
			Minimap:SetZoom(zoom)
		end
	end)
end

local function UnshrinkEntry(entry)
	entry.frame:SetScale(entry.savedScale or 1)
	ns.UnparkShrunk(entry)
	entry.shrunk = false
	if entry.frame == Minimap and Minimap.GetZoomLevels and IsIndoors and ns.Flag(IsIndoors()) then
		minimapNeedsRedraw = true
	end
	for _, handler in ipairs(restoredHandlers) do
		pcall(handler)
	end
end

-- Every faded frame all the way out (for a layout change to wait for).
function ns.AllFaded()
	for _, entry in ipairs(ns.managed) do
		if (entry.alpha or 1) > 0 then return false end
	end
	return true
end

-- For the log: the frames not faded right out, with their alpha. (Not the
-- ones hidden anyway: a secret answer counts as shown.)
function ns.NotFadedList()
	local function Unseen(frame)
		local ok, unseen = pcall(function() return frame:IsVisible() == false end)
		return ok and unseen
	end
	local list = {}
	for _, entry in ipairs(ns.managed) do
		local alpha = entry.alpha or 1
		if alpha > 0 and not (entry.frame and Unseen(entry.frame)) then
			list[#list + 1] = ("%s %.2f"):format(entry.name or entry.group or "?", alpha)
		end
	end
	return #list > 0 and table.concat(list, ", ") or "none"
end

-- Every shrunk frame back at full size in its place (still faded), for a
-- moment: an Edit Mode layout switch then lays out the frames themselves,
-- not their parked, shrunk copies (whose old size and place would come back
-- when shown: an XP bar keeping its old width). The faded ones shrink again
-- a second later, from where the layout put them.
function ns.UnshrinkForLayout()
	ns.noShrinkUntil = GetTime() + 1
	for _, entry in ipairs(ns.managed) do
		if entry.shrunk and not ns.ScaleBlocked(entry.frame) then UnshrinkEntry(entry) end
	end
end

function ns.SetEntryAlpha(entry, alpha)
	entry.alpha = alpha
	if entry.shrinkWhenFaded then
		if alpha > 0 then
			-- (Blocked in combat: it stays shrunk, and grows back once the fight ends.)
			if entry.shrunk and GetTime() - entry.shrunkAt >= MIN_SHRUNK_TIME and not ns.ScaleBlocked(entry.frame) then
				UnshrinkEntry(entry)
			elseif entry.parkedFullSize and not ns.ScaleBlocked(entry.frame) then
				ns.UnparkFullSize(entry)
			end
		elseif ns.ScaleBlocked(entry.frame) or (entry.frame == Minimap and ns.KeepMinimapFullSize()) then
			-- Can't shrink in combat: it sits at alpha 0 full size until the
			-- fight ends (tried again each tick), and is redrawn once shown.
			-- (Nor while "Only while a herb or vein is on it" sweeps it: kept
			-- full size in its place, its icons hidden, NodeSweep.lua.)
			if entry.shrunk and not ns.ScaleBlocked(entry.frame) then
				UnshrinkEntry(entry)
			end
			if not entry.shrunk and entry.frame == Minimap and Minimap.GetZoomLevels and IsIndoors
				and ns.Flag(IsIndoors()) then
				minimapNeedsRedraw = true
			end
			-- (Kept full size for the sweep: in its place, where the game adds
			-- new dots to it; off the screen only while a quest's area (its
			-- blue outline shows through alpha 0) is on it, tested. Not for
			-- /cine debug nodes stay, which tests it in its place.)
			if not entry.shrunk and entry.frame == Minimap and not ns.ScaleBlocked(entry.frame) then
				if ns.MinimapAreaShown() and not ns.minimapStayFullSize then
					ns.ParkFullSize(entry)
				elseif entry.parkedFullSize then
					ns.UnparkFullSize(entry)
				end
			end
		elseif not entry.shrunk then
			-- Shrink in the same step it reaches 0, so it's never at alpha 0
			-- while full size. (Not just after a layout switch: see above.)
			if GetTime() >= (ns.noShrinkUntil or 0) then ShrinkEntry(entry) end
		elseif not (ns.parkMinimapFullSize and entry.frame == Minimap)
			and math.abs(entry.frame:GetScale() - SHRUNK_SCALE) > SHRUNK_SCALE / 2 then
			-- Something put its size back (EllesmereUI does when it lays the
			-- minimap out again): take that as its size and shrink it again.
			ShrinkEntry(entry)
		elseif ns.ParkUndone(entry) then
			-- Laid out again at its shrunk size, or clamped again: back off the screen.
			ns.ParkShrunk(entry)
		end
	end
	if entry.frame == Minimap then
		-- (Its arrow and icons ignore alpha: hidden whenever it's faded. Shrunk,
		-- the arrow is still a pixel wherever the map is: an addon that lays the
		-- map out again can keep it on the screen. And in combat it's faded full size.)
		ns.SetMinimapIconsHidden(alpha <= 0)
		-- (Its blue quest areas too, whenever it's faded full size.)
		ns.SetMinimapBlobsHidden(alpha <= 0 and not entry.shrunk)
	end
	ApplyAlpha(entry)
end
ns.SetEntryAlpha = ns.Profiled("SetEntryAlpha", ns.SetEntryAlpha)

local function IsCursorInSavedRect(entry)
	local left, bottom, width, height = unpack(entry.savedRect)
	if not left then
		return false
	end
	local x, y = GetCursorPosition()
	x, y = x / entry.savedEffectiveScale, y / entry.savedEffectiveScale
	return x >= left and x <= left + width and y >= bottom and y <= bottom + height
end

-- The UI element the mouse is actually over (nil over the 3D world). Asked
-- for every faded frame each tick, so worked out once a frame (GetMouseFoci
-- makes a table each call).
local MouseFocus
do
	local focusAt, focus = -1, nil
	function MouseFocus()
		local now = GetTime()
		if focusAt ~= now then
			focusAt = now
			if GetMouseFoci then
				focus = GetMouseFoci()[1]
			elseif GetMouseFocus then
				focus = GetMouseFocus()
			else
				focus = nil
			end
			if focus == WorldFrame then
				focus = nil
			end
		end
		return focus
	end
end

local function IsInside(frame, ancestor)
	while frame do
		if frame == ancestor then
			return true
		end
		if IsForbidden(frame) then
			return false
		end
		frame = frame:GetParent()
	end
	return false
end

-- An action bar's empty slots: the game hides a button with nothing on it, so
-- the mouse there is on the 3D world. Over one's rect counts as over the bar.
-- (Retail's bars list their buttons; Classic's go by name.)
function ns.IsOverEmptySlot(frame)
	local buttons, name = frame.actionButtons, frame:GetName()
	local x, y = GetCursorPosition()
	for i = 1, buttons and #buttons or 12 do
		local button = buttons and buttons[i]
			or _G[(name == "MainMenuBar" and "ActionButton" or (name or "") .. "Button") .. i]
		if button and not IsForbidden(button) and not ns.Flag(button:IsShown()) then
			local left, bottom, width, height = button:GetRect()
			local scale = button:GetEffectiveScale()
			if left and scale and scale > 0 and x / scale >= left and x / scale <= left + width
				and y / scale >= bottom and y / scale <= bottom + height then
				return true
			end
		end
	end
	return false
end

-- Buff icons are small, so they count as hovered from a little way off, and
-- across the gaps between them: the cursor within buffHoverPadX/Y (UI units)
-- of any shown icon. Icons are the mouse-enabled frames up to a few levels down
-- (BuffButtonN on Classic, the aura frames in each AuraContainer on retail).
local BUFF_HOVER_DEPTH = 3

local IsNearIcon
do
	local function IsIconNear(child, depth, padX, padY)
		-- (Any of these can come back secret on Forever: ns.Flag reads that as false.)
		if not IsForbidden(child) and ns.Flag(child:IsVisible()) then
			if ns.Flag(child:IsMouseEnabled()) and ns.Flag(child:IsMouseOver(padY, -padY, -padX, padX)) then
				return true
			end
			if depth > 1 and IsNearIcon(depth - 1, padX, padY, child:GetChildren()) then
				return true
			end
		end
		return false
	end

	function IsNearIcon(depth, padX, padY, ...)
		for i = 1, select("#", ...) do
			-- Forever locks some aura icons after a fight without marking them
			-- forbidden ("Attempt to access forbidden object" on IsVisible), so
			-- an icon that errors just doesn't count.
			local ok, near = pcall(IsIconNear, select(i, ...), depth, padX, padY)
			if ok and near then
				return true
			end
		end
		return false
	end
end

ns.CHAT_SCROLL_PARTS = { "ScrollBar", "ScrollToBottomButton", "buttonFrame", "Background" }
-- A chat window's background: Blizzard's own list (the window's name plus
-- each), its button column's strip included.
ns.CHAT_BACKGROUND_TEXTURES = CHAT_FRAME_TEXTURES or { "Background", "TopLeftTexture", "BottomLeftTexture",
	"TopRightTexture", "BottomRightTexture", "LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
ns.CHAT_BUTTON_COLUMNS = {}
for i = 1, (NUM_CHAT_WINDOWS or 10) do
	ns.CHAT_BUTTON_COLUMNS[i] = "ChatFrame" .. i .. "ButtonFrame"
end
function ns.IsEntryHovered(entry)
	if PART_GROUPS[entry.group] then
		return false
	end
	if entry.shrunk or entry.parkedFullSize then
		-- (Its spot is a bare rect test: a window dragged over it, like
		-- Settings, has the mouse instead.)
		local focus = MouseFocus()
		if focus then
			for name in pairs(ns.WINDOWS) do
				local window = _G[name]
				if window and IsInside(focus, window) then
					return false
				end
			end
		end
		return IsCursorInSavedRect(entry)
	end
	if entry.group == "buffs" then
		return ns.Flag(entry.frame:IsVisible()) and IsNearIcon(BUFF_HOVER_DEPTH,
			ns.db.buffHoverPadX or 20, ns.db.buffHoverPadY or 20, entry.frame:GetChildren())
	end
	-- Retail's quest tracker only takes the mouse on its headers and quest
	-- names, so the objective lines under them count by their rect: the mouse
	-- over any shown section (Campaign, Quests...), which is as tall as its
	-- quests, unlike the tracker itself. (NineSlice is the background, the
	-- whole tracker.) A frame of something else on top has the mouse instead.
	if entry.group == "quests" and ns.isRetail and entry.frame == _G.ObjectiveTrackerFrame then
		local tracker, focus = entry.frame, MouseFocus()
		if not ns.Flag(tracker:IsVisible()) or (focus and not IsInside(focus, tracker)) then
			return false
		end
		for i = 1, select("#", tracker:GetChildren()) do
			local child = select(i, tracker:GetChildren())
			if child ~= tracker.NineSlice and not IsForbidden(child) and ns.Flag(child:IsVisible())
				and ns.Flag(child:IsMouseOver(4, -4, -4, 4)) then
				return true
			end
		end
		return false
	end
	-- (The mouse over the 3D world, as it mostly is in CineMode: none of the
	-- rest can be hovered, so no need to ask each frame. Except an action
	-- bar's empty slots: see ns.IsOverEmptySlot.)
	if entry.group ~= "chat" and not MouseFocus() then
		return (entry.group == "bars" or entry.group == "sidebars") and ns.Flag(entry.frame:IsVisible())
			and ns.IsOverEmptySlot(entry.frame)
	end
	-- A chat window's scroll bar and jump-to-bottom button sit outside its
	-- rect (Classic's button column too), and so does the dark background
	-- around them: hovering any of them counts.
	if entry.group == "chat" and ns.Flag(entry.frame:IsVisible()) then
		local name = entry.frame:GetName()
		for _, key in ipairs(ns.CHAT_SCROLL_PARTS) do
			local part = entry.frame[key] or (name and _G[name .. key])
			if part and part.IsMouseOver and ns.Flag(part:IsVisible()) and ns.Flag(part:IsMouseOver()) then
				return true
			end
		end
	end
	if not (ns.Flag(entry.frame:IsVisible()) and ns.Flag(entry.frame:IsMouseOver())) then
		return false
	end
	-- Container frames (the action bar holders, status bar managers, the
	-- quest tracker) can cover far more of the screen than their buttons, so
	-- the mouse resting in an empty corner would reveal them. Only count it
	-- when the mouse is on something that belongs to the frame. Chat windows
	-- don't always take the mouse, so they keep the plain rect test.
	if entry.group == "chat" then
		return true
	end
	local focus = MouseFocus()
	-- Classic clients' raid frames sit inside the Raid Frame Manager: the
	-- mouse on them isn't on the manager.
	local raidFrames = _G.CompactRaidFrameContainer
	if entry.group == "raidmanager" and raidFrames and IsInside(focus, raidFrames) then
		return false
	end
	return IsInside(focus, entry.frame)
end
ns.IsEntryHovered = ns.Profiled("IsEntryHovered", ns.IsEntryHovered)

-- Frames the player can choose to show while fighting when staying cinematic
-- in combat (db.combatShow[key], missing = the default here).
ns.COMBAT_SHOW = {
	{ key = "player", label = L["Player frame"], default = true, frames = { "PlayerFrame" } },
	-- Follows the player frame's ticks until set (see ROW_FALLBACK).
	{ key = "petframe", label = L["Pet frame"], default = true, frames = { "PetFrame" } },
	{ key = "prd", label = L["Personal health bar"], default = true,
		frames = { "PersonalResourceDisplayFrame", "CinematicPersonalResource" } },
	-- Follows the health bar's ticks until set (see ROW_FALLBACK).
	{ key = "prdpower", label = L["Personal resource bar"], default = true, frames = { "CinematicPersonalPower" },
		tip = L["Mana, rage, energy, focus or runic power under your character, and class resources " ..
			"such as combo points."] },
	-- Follows the resource bar's ticks until set (see ROW_FALLBACK).
	{ key = "prdmana", label = L["Personal mana bar"], default = true, frames = { "CinematicPersonalMana" },
		tip = L["Your mana under your character when it isn't your power (Elemental Shaman, Shadow Priest...): " ..
			"once it's on, on the Personal Resources page."] },
	{ key = "target", label = L["Target"], default = true, frames = { "TargetFrame" } },
	{ key = "tot", label = L["Target of target"], default = true, frames = { "TargetFrameToT" } },
	{ key = "focus", label = L["Focus"], default = true, frames = { "FocusFrame" } },
	-- Follows the focus's ticks until set (see ROW_FALLBACK), as it did inside
	-- the focus frame. (noHoverRow: hovering it is hovering the target's group.)
	-- On WoW Forever, a box before its name turns the frame off altogether,
	-- CineMode or not (showKey; retail shows it as the game says).
	{ key = "focustot", label = L["Focus target of target"], default = true, frames = { "FocusFrameToT" },
		noHoverRow = true, showKey = not ns.isRetail and "unitPartsFocusToT" or nil,
		showTip = L["Unticked: the small frame by the focus frame, showing who your focus is targeting, doesn't " ..
			"show at all, CineMode or not. Which of its parts show is on the Unit Frames page."],
		showChanged = function() if ns.ApplyUnitFrameParts then ns.ApplyUnitFrameParts() end end },
	-- The game's circle on the ground under your target: not a frame but a
	-- setting (Effects.lua, ns.RowOnNow). Always ticked to start with
	-- (CINE_SHOW_DEFAULT), as before it had a row.
	{ key = "targetcircle", label = L["Target circle"], default = false, noHoverRow = true,
		tip = L["The selection circle on the ground under your target. Hidden, your own setting is put " ..
			"back when the UI returns."] },
	-- The Standard Frames page's Party frames section (page = "party"); the
	-- raid-style ones are the Raid frames section's.
	{ key = "party", label = L["Party frames"], default = true, page = "party", groups = { "party" } },
	-- Their parts, Always ticked to start with (CINE_SHOW_DEFAULT), as the raid frames' are,
	-- and nothing else (so the greyed columns show no ticks).
	{ key = "partyroles", label = L["Role icons"], default = false, page = "party", groups = { "partyroles" }, part = true },
	{ key = "partynames", label = L["Names"], default = false, page = "party", groups = { "partynames" }, part = true },
	{ key = "partystatus", label = L["Status icons"], default = false, page = "party", groups = { "partystatus" }, part = true,
		tip = L["The icon on a member's portrait for a summon on its way, or a member phased, in another " ..
			"instance or too far away."] },
	-- The raid frames (raid-style party frames too), members and pets apart,
	-- and the Raid Frame Manager (the tab at the left edge): the Standard
	-- Frames page's Raid frames section (page = "raid").
	{ key = "raidplayers", label = L["Players"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidplayers" } },
	{ key = "raidpets", label = L["Pets"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidpets" } },
	-- Parts of them, Always ticked to start with (CINE_SHOW_DEFAULT): untick
	-- one to hide it in CineMode (names and role icons while you heal, say).
	-- (part: Always means whenever its frame shows, over its Mouseover groups.)
	{ key = "raidroles", label = L["Role icons"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidroles" }, part = true },
	-- The glow round a member with threat. (tip: the row name's tooltip.)
	{ key = "raidthreat", label = L["Threat highlight"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidthreat" }, part = true,
		tip = L["The glow round a member with threat (aggro). To hide it all the time, CineMode or not, " ..
			"turn off the game's own Display Aggro Highlight raid frame option."] },
	-- The white outline round your target's frame.
	{ key = "raidtarget", label = L["Target highlight"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidtarget" }, part = true,
		tip = L["The white outline round your target's raid frame."] },
	-- The ready check's tick, cross or question mark. (It ignores its frame's
	-- alpha, staying bright on dimmed frames: faded here, it goes with them.)
	{ key = "raidready", label = L["Ready check"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidready" }, part = true,
		tip = L["The ready check's tick, cross or question mark on each member's raid frame."] },
	{ key = "raidnames", label = L["Player names"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidnames" }, part = true },
	{ key = "raidpetnames", label = L["Pet names"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidpetnames" }, part = true },
	{ key = "raidtitles", label = L["Group titles"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidtitles" }, part = true },
	{ key = "raidbuffs", label = L["Buffs"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidbuffs" }, part = true },
	{ key = "raiddebuffs", label = L["Debuffs"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raiddebuffs" }, part = true },
	{ key = "raidmanager", label = L["Raid Frame Manager"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", frames = { "CompactRaidFrameManager" } },
	-- The battlegrounds' flag carriers, in the Interface section.
	-- Always shown to start with (CINE_SHOW_DEFAULT), as before it had a row.
	{ key = "flags", label = L["Flag carriers"], default = false, addon = "Blizzard_Deprecated_ArenaUI",
		page = "interface", frames = { "ArenaEnemyFramesContainer" } },
	-- morePage: the options page with more settings for it, which can keep it up besides.
	{ key = "minimap", label = L["Minimap"], default = true, groups = { "minimap" }, morePage = "Minimap" },
	-- The bar behind the zone's name (not the name): follows the minimap's
	-- ticks until set (see ROW_FALLBACK).
	{ key = "minimapheader", label = L["Minimap header"], default = true, groups = { "minimapheader" },
		tip = L["The bar behind the zone's name above the minimap (the name has a row of its own). " ..
			"Untick it to leave the name floating on its own. Hovering the minimap brings it up with the map: " ..
			"to keep it hidden then too, take Minimap header out of the Minimap group on the Mouseover groups page."] },
	-- The buttons on the header: follow the minimap's ticks until set, too.
	{ key = "minimaptracking", label = L["Tracking button"], default = true, groups = { "minimaptracking" },
		tip = L["The tracking button on the minimap header. Untick it to hide it in CineMode even while the minimap is up. " ..
			"Hovering the minimap brings it up with the map."] },
	{ key = "minimapcalendar", label = L["Calendar"], default = true, groups = { "minimapcalendar" },
		tip = L["The calendar button on the minimap header. Untick it to hide it in CineMode even while the minimap is up. " ..
			"Hovering the minimap brings it up with the map."] },
	{ key = "minimapzone", label = L["Zone name"], default = true, groups = { "minimapzone" },
		tip = L["The zone's name on the minimap header. Untick it to hide it in CineMode even while the minimap is up. " ..
			"Hovering the minimap brings it up with the map."] },
	{ key = "minimapclock", label = L["Clock"], default = true, groups = { "minimapclock" },
		tip = L["The clock on the minimap header. Untick it to hide it in CineMode even while the minimap is up. " ..
			"Hovering the minimap brings it up with the map."] },
	{ key = "minimapdial", label = L["Day/night dial"], default = true, groups = { "minimapdial" }, retail = false,
		tip = L["The day and night dial by the minimap. Untick it to hide it in CineMode even while the minimap is up. " ..
			"Hovering the minimap brings it up with the map."] },
	-- (groups too: an addon's unnamed tracker parts, found by its scanner.)
	{ key = "quests", label = L["Quest tracker"], default = false, frames = FRAME_GROUPS.quests, groups = { "quests" },
		morePage = "Quest tracker" },
	-- Retail's quest waypoint: its Always tick is the Minimap page's "Always
	-- show the quest waypoint" (CINE_SHOW_SETTING).
	{ key = "waypoint", label = L["Quest waypoint"], default = false, retail = true, groups = { "waypoint" },
		morePage = "Minimap" },
	-- Always ticked to start with (CINE_SHOW_DEFAULT); its other columns follow
	-- the quest tracker's until set (see ROW_FALLBACK).
	{ key = "belowminimap", label = L["Objective boxes (below the minimap)"], default = false,
		frames = FRAME_GROUPS.belowminimap,
		tip = L["The boxes the game puts under the minimap for a scenario's or quest's current step, " ..
			"such as a capture bar. Always shown to start with."] },
	-- Follows the quest tracker's ticks until set too.
	{ key = "topcenter", label = L["Event boxes (top of the screen)"], default = false,
		frames = FRAME_GROUPS.topcenter,
		tip = L["The bars and boxes the game puts at the top of the screen for a zone event or scenario, " ..
			"such as a timer to the next event. Until you change its ticks it does what the quest tracker's row does."] },
	{ key = "buffs", label = L["Buffs and debuffs"], default = true, morePage = "Buffs/debuffs",
		frames = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" } },
	{ key = "swing", label = L["Swing timer"], default = true, retail = false,
		tip = L["The Swing timer page can fade out the bars of weapons you aren't using, and the off-hand's."],
		frames ={ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" } },
	-- Always ticked to start with (CINE_SHOW_DEFAULT), as before it had a row,
	-- and nothing else: untick it and tick In combat to hide your cast bar
	-- in CineMode but for fights.
	{ key = "castbar", label = L["Cast bar"], default = false, frames = FRAME_GROUPS.castbar },
	-- The game's own damage meter (made when first opened).
	{ key = "meters", label = L["Damage meter (the game's)"], default = false, frames = FRAME_GROUPS.meters },
	-- The Cooldown Manager's two spell bars and its tracked buffs and bars, a
	-- row each. The others follow Essential's ticks until set (see
	-- ROW_FALLBACK), as they were one row before.
	{ key = "cooldowns", label = L["Essential Cooldowns"], default = false, addon = "Blizzard_CooldownViewer",
		frames = { "EssentialCooldownViewer" }, morePage = "Cooldown Manager" },
	{ key = "cooldownsutility", label = L["Utility Cooldowns"], default = false, addon = "Blizzard_CooldownViewer",
		frames = { "UtilityCooldownViewer" }, morePage = "Cooldown Manager" },
	{ key = "cooldownsbuffs", label = L["Tracked Buffs"], default = false, addon = "Blizzard_CooldownViewer",
		frames = { "BuffIconCooldownViewer" }, morePage = "Cooldown Manager" },
	{ key = "cooldownsbars", label = L["Tracked Bars"], default = false, addon = "Blizzard_CooldownViewer",
		frames = { "BuffBarCooldownViewer" }, morePage = "Cooldown Manager" },
	-- Always ticked to start with (CINE_SHOW_DEFAULT): a boss's or quest's bar to watch.
	{ key = "encounter", label = L["Encounter bar"], default = false, frames = FRAME_GROUPS.encounter,
		tip = L["The extra bar some bosses, quests and vehicles bring up, such as a boss's own power."] },
	-- Numbered as retail's Edit Mode numbers them; Classic doesn't number its
	-- bars, so there each also says where it sits.
	{ key = "mainbar", label = L["Action bar 1"], default = true,
		frames = { "MainMenuBar", "MainActionBar", "MainMenuBarVehicleLeaveButton" } },
	-- The game's art round action bar 1 (end caps, the bar behind the buttons),
	-- left up or faded apart from its buttons, which an action bar addon may
	-- have taken away. Follows Action bar 1's ticks until set (see ROW_FALLBACK).
	-- noHoverRow: hovering it is hovering action bar 1.
	{ key = "art", label = L["Action bar art"], default = true, groups = { "barart" }, noHoverRow = true },
	{ key = "bottomleft", label = ns.isRetail and L["Action bar 2"] or L["Action bar 2 (bottom left)"], default = true,
		frames = { "MultiBarBottomLeft" } },
	{ key = "bottomright", label = ns.isRetail and L["Action bar 3"] or L["Action bar 3 (bottom right)"], default = true,
		frames = { "MultiBarBottomRight" } },
	{ key = "right1", label = ns.isRetail and L["Action bar 4"] or L["Action bar 4 (right)"], default = false,
		frames = { "MultiBarRight" } },
	{ key = "right2", label = ns.isRetail and L["Action bar 5"] or L["Action bar 5 (right 2)"], default = false,
		frames = { "MultiBarLeft" } },
	-- Retail only (the frames don't exist on Classic, so the rows are skipped).
	-- groupOnly: the mouse on one brings it up only through a mouseover group
	-- that's on (they sit mid-screen, where the mouse often rests).
	{ key = "bar6", label = L["Action bar 6"], default = false, groupOnly = true, frames = { "MultiBar5" } },
	{ key = "bar7", label = L["Action bar 7"], default = false, groupOnly = true, frames = { "MultiBar6" } },
	{ key = "bar8", label = L["Action bar 8"], default = false, groupOnly = true, frames = { "MultiBar7" } },
	{ key = "pet", label = L["Pet bar"], default = true, frames = { "PetActionBarFrame", "PetActionBar" } },
	{ key = "stance", label = L["Stance bar"], default = true, frames = { "StanceBarFrame", "StanceBar" } },
	{ key = "totems", label = L["Totem bar"], default = true, frames = {
		"MultiCastActionBarFrame", "MultiCastSummonSpellButton", "MultiCastRecallSpellButton",
		"MultiCastFlyoutFrame", "MultiCastSlotButton1", "MultiCastSlotButton2",
		"MultiCastSlotButton3", "MultiCastSlotButton4",
		"MultiCastActionPage1", "MultiCastActionPage2", "MultiCastActionPage3", "TotemFrame",
	} },
	-- Classic clients' micro menu and bags are one frame (MicroButtonAndBagsBar),
	-- so the Bags row is retail's only. Follows the micro menu's ticks until
	-- set (see ROW_FALLBACK).
	{ key = "micro", label = _G.BagsBar and L["Micro menu"] or L["Micro menu and bags"], default = true,
		frames = { "MicroButtonAndBagsBar", "MicroMenuContainer" } },
	{ key = "bags", label = L["Bags"], default = true, frames = { "BagsBar" } },
	-- Always ticked to start with (CINE_SHOW_DEFAULT), as before it had a row.
	{ key = "voice", label = L["Voice chat speakers"], default = false, frames = FRAME_GROUPS.voice,
		tip = L["The names and portraits above the chat of who's talking in voice chat. Untick Always to hide them in CineMode."] },
	-- (In gamepad mode the Gamepad page's row has them instead: notGamepad.)
	{ key = "xp", label = L["Experience and reputation bars"], default = true, notGamepad = true, frames = {
		"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
		"StatusTrackingBarManager",
	} },
	-- Always ticked to start with (CINE_SHOW_DEFAULT): it's what a quest or fight asks you to press.
	{ key = "extra", label = L["Extra action and zone ability"], default = false, retail = true,
		frames = { "ExtraActionBarFrame", "ZoneAbilityFrame" } },
	-- WoW Forever's gamepad mode, on the Gamepad page (page = "gamepad") rather
	-- than the Standard Frames page.
	{ key = "gamepadbars", label = L["Gamepad action bars"], default = true, retail = false, page = "gamepad",
		frames = FRAME_GROUPS.gamepadbars },
	{ key = "gamepadlegend", label = L["Button hints (top left)"], default = false, retail = false, page = "gamepad",
		frames = FRAME_GROUPS.gamepadlegend },
	{ key = "gamepadreticle", label = L["Reticle (center dot)"], default = true, retail = false, page = "gamepad",
		frames = FRAME_GROUPS.gamepadreticle },
	-- The game's experience bars again, used only in gamepad mode (gamepadOnly).
	{ key = "gamepadxp", label = L["Experience and reputation bars"], default = false, retail = false,
		page = "gamepad", gamepadOnly = true, frames = {
		"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
		"StatusTrackingBarManager",
	} },
}
-- The Standard Frames page's sections (page) for the rows not given one
-- above. (Kept in the order above within each.)
local ROW_SECTIONS = {
	player = "units", petframe = "units", prd = "units", prdpower = "units", prdmana = "units", target = "units", tot = "units", focus = "units", focustot = "units",
	targetcircle = "units",
	buffs = "combat", swing = "combat", castbar = "combat", meters = "combat", cooldowns = "combat",
	cooldownsutility = "combat", cooldownsbuffs = "combat", cooldownsbars = "combat", encounter = "combat",
	mainbar = "bars", art = "bars", bottomleft = "bars", bottomright = "bars",
	pet = "bars", stance = "bars", totems = "bars", extra = "bars",
	right1 = "bars", right2 = "bars", bar6 = "bars", bar7 = "bars", bar8 = "bars",
	minimap = "minimap", minimapheader = "minimap", minimaptracking = "minimap", minimapcalendar = "minimap",
	minimapzone = "minimap", minimapclock = "minimap", minimapdial = "minimap",
	quests = "interface", waypoint = "interface", belowminimap = "interface", topcenter = "interface", micro = "interface", bags = "interface", xp = "interface",
	voice = "interface",
}
for _, item in ipairs(ns.COMBAT_SHOW) do
	item.page = item.page or ROW_SECTIONS[item.key]
end

-- The raid-style party frames' own rows: the raid frames' rows again, for the
-- Standard Frames page's Party frames (raid-style) section (page = "rsparty").
-- They only count with its "Same as raid frames" unticked (raidStylePartySame):
-- ticked, the raid frames' rows decide for those frames too (see
-- UpdateFrames), and these follow theirs until set (ROW_FALLBACK). Not the
-- target highlight or the Raid Frame Manager: one for both.
ns.RAID_STYLE_PARTY = {
	raidplayers = "rspartyplayers", raidpets = "rspartypets", raidroles = "rspartyroles", raidthreat = "rspartythreat",
	raidnames = "rspartynames", raidpetnames = "rspartypetnames", raidtitles = "rspartytitles",
	raidbuffs = "rspartybuffs", raiddebuffs = "rspartydebuffs",
}
do
	-- (hoverLabel: their names on the Mouseover page, where the raid frames'
	-- rows go by the same ones. auraFrames: only where auras fade as frames,
	-- not WoW Forever's game setting, which is the raid frames' too.)
	local HOVER_LABELS = {
		rspartyplayers = L["Raid-style party players"], rspartypets = L["Raid-style party pets"],
		rspartyroles = L["Raid-style party role icons"], rspartythreat = L["Raid-style party threat highlight"],
		rspartynames = L["Raid-style party player names"], rspartypetnames = L["Raid-style party pet names"],
		rspartytitles = L["Raid-style party title"], rspartybuffs = L["Raid-style party buffs"],
		rspartydebuffs = L["Raid-style party debuffs"],
	}
	local copies = {}
	for _, item in ipairs(ns.COMBAT_SHOW) do
		local key = ns.RAID_STYLE_PARTY[item.key]
		if key then
			local copy = {}
			for field, value in pairs(item) do copy[field] = value end
			copy.key, copy.page, copy.groups, copy.hoverLabel = key, "rsparty", { key }, HOVER_LABELS[key]
			if key == "rspartytitles" then copy.label = L["Party title"] end
			copy.auraFrames = (key == "rspartybuffs" or key == "rspartydebuffs") or nil
			copies[#copies + 1] = copy
		end
	end
	for _, copy in ipairs(copies) do
		ns.COMBAT_SHOW[#ns.COMBAT_SHOW + 1] = copy
	end
end

-- Then the Other addons, by group (their frames may have no names).
for _, known in ipairs(ns.ADDON_FRAMES) do
	ns.COMBAT_SHOW[#ns.COMBAT_SHOW + 1] = {
		key = "addon:" .. known.key, label = known.short or known.label, default = true, addon = known.addon,
		groups = { "addon:" .. known.key },
	}
end

-- Mouseover groups (Mouseover page): frames in the same group come up
-- together when the mouse is on any of them, and with the events ticked for
-- the group. A frame can be in several groups; one in none comes up alone.
-- Groups are lists of rows: the Standard Frames rows above (with the
-- supported addons; not the Gamepad page's copy of the XP bars), a few
-- frames that have no row there, and the Advanced Frames additions
-- ("extra:<name>"). These only decide what reveals together: the fade groups
-- (FRAME_GROUPS) still drive everything else.
local HOVER_EXTRA_ROWS = {
	{ key = "totemtimers", label = L["Totem timers (by the portrait)"], frames = { "TotemFrame" } },
	{ key = "durability", label = L["Durability figure"], frames = { "DurabilityFrame" } },
	{ key = "chat", label = L["Chat tabs and buttons"], frames = FRAME_GROUPS.chat },
	{ key = "questtimer", label = L["Quest timer"], frames = { "QuestTimerFrame" } },
	{ key = "waypoint", label = L["Quest waypoint"], frames = { "SuperTrackedFrame" } },
}
ns.HOVER_ROWS = {}
ns.HOVER_GROUP_ONLY = {} -- row key -> true: rows marked groupOnly (above)
local HOVER_ROW_BY_NAME = {} -- frame name -> row key (the first row listing it)
for _, list in ipairs({ HOVER_EXTRA_ROWS, ns.COMBAT_SHOW }) do
	for _, item in ipairs(list) do
		if item.key ~= "gamepadxp" and not item.noHoverRow then
			ns.HOVER_ROWS[#ns.HOVER_ROWS + 1] = item
			ns.HOVER_GROUP_ONLY[item.key] = item.groupOnly
			for _, name in ipairs(item.frames or {}) do
				HOVER_ROW_BY_NAME[name] = HOVER_ROW_BY_NAME[name] or item.key
			end
		end
	end
end
-- Frames no row lists by name go with their fade group's row (the possess
-- bar with action bar 1, the minimap's clock with the minimap...); an
-- addon's or added frame's row is its fade group ("addon:<key>", "extra:<name>").
local HOVER_ROW_BY_GROUP = {
	bars = "mainbar", sidebars = "right1", player = "player", prd = "prd", prdpower = "prdpower", prdmana = "prdmana", totems = "totems", target = "target",
	party = "party",
	raidplayers = "raidplayers", raidpets = "raidpets", raidmanager = "raidmanager", flags = "flags",
	raidroles = "raidroles", raidnames = "raidnames", raidpetnames = "raidpetnames", raidtitles = "raidtitles",
	partyroles = "partyroles", partynames = "partynames", partystatus = "partystatus",
	raidbuffs = "raidbuffs", raiddebuffs = "raiddebuffs", raidthreat = "raidthreat", raidtarget = "raidtarget",
	raidready = "raidready",
	minimap = "minimap", buffs = "buffs", quests = "quests", questtimer = "questtimer", misc = "durability",
	swing = "swing", castbar = "castbar", meters = "meters", cooldowns = "cooldowns", waypoint = "waypoint",
	gamepadbars = "gamepadbars", gamepadlegend = "gamepadlegend", gamepadreticle = "gamepadreticle",
	chat = "chat", barart = "mainbar", voice = "voice", encounter = "encounter",
}
function ns.HoverRowFor(entry)
	return (entry.name and HOVER_ROW_BY_NAME[entry.name]) or HOVER_ROW_BY_GROUP[entry.group] or entry.group
end

-- The events that can bring a group up besides the mouse ("Also bring this
-- group up for"). Each still needs its own setting on: the Chat page's peek,
-- buff peeks on the Buffs/debuffs page, the Minimap and Quest tracker pages'
-- options, the gamepad's press reveal.
ns.HOVER_TRIGGERS = {
	{ key = "chat", label = L["Chat message"], tip = L["A chat window peeking for a new message (Chat page)."] },
	{ key = "whisper", label = L["Unread whisper"],
		tip = L["A whisper tab waiting to be read, while that keeps chat up (Chat page)."] },
	{ key = "typing", label = L["Typing"], tip = L["Typing in chat."] },
	{ key = "aura", label = L["New buff or debuff"], tip = L["A buff or debuff peek (Buffs/debuffs page)."] },
	{ key = "ping", label = L["Minimap ping"], tip = L["A group member pinging the minimap (Minimap page)."] },
	{ key = "tracking", label = L["Tracking"],
		tip = L["While the minimap stays up for herb, mineral or other tracking (Minimap page)."] },
	{ key = "quest", label = L["Quest progress"], tip = L["Accepting a quest or progress on one (Quest tracker page)."] },
	{ key = "gamepad", label = L["Gamepad input"], gamepad = true, tip = L["Pressing a gamepad button (Gamepad page)."] },
	{ key = "roster", label = L["Group joins or leaves"],
		tip = L["Someone joining or leaving your party or raid, or you joining or leaving one."] },
	{ key = "cooldown", label = L["Cooldown recharging"], tip = L["While a spell in the Cooldown Manager (or " ..
		"Enhanced Cooldown Manager's cooldown bars) is still recharging, until they're all ready. Not " ..
		"the global cooldown (Cooldown Manager page)."] },
}

-- What it's like before you change anything: today's groups that do
-- something (more than one frame, or brought up by more than the mouse).
-- (preset: which default group it is, kept in the player's copy; icon: its
-- picture on the Mouseover groups page, one of HOVER_GROUP_ICONS for groups
-- you make.)
ns.HOVER_GROUPS_DEFAULT = {
	{ preset = "bars", icon = "Interface\\Icons\\INV_Sword_04", name = L["Action bars"],
		members = { "mainbar", "bottomleft", "bottomright", "pet", "stance", "totems", "micro", "bags", "xp" } },
	{ preset = "side", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance", name = L["Side bars"],
		members = { "right1", "right2" } },
	-- (Off: with it off, the mouse on bars 6-8 brings up nothing: groupOnly.)
	{ preset = "bars68", icon = "Interface\\Icons\\Ability_DualWield", name = L["Action bars 6-8"],
		members = { "bar6", "bar7", "bar8" }, off = true },
	{ preset = "player", icon = "Interface\\Icons\\INV_Misc_Head_Human_01", name = L["Player"],
		members = { "player", "petframe", "totemtimers", "castbar" } },
	{ preset = "prd", icon = "Interface\\Icons\\Spell_Nature_Rejuvenation", name = L["Personal resource bars"],
		members = { "prd", "prdpower", "prdmana" } },
	{ preset = "target", icon = "Interface\\Icons\\Ability_Hunter_SniperShot", name = L["Target and focus"],
		members = { "target", "tot", "focus" } },
	-- (Raid-style party frames are the raid frames. The Raid Frame Manager
	-- has its own group, below: hovering them doesn't bring it up.)
	{ preset = "raid", icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", name = L["Raid frames"],
		members = { "raidplayers", "raidpets", "raidroles", "raidthreat", "raidtarget", "raidready", "raidnames", "raidpetnames",
		"raidtitles", "raidbuffs", "raiddebuffs" }, triggers = { roster = true } },
	-- (The raid-style ones' own rows too: they count once set apart from the raid frames.)
	{ preset = "party", icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02", name = L["Party frames"],
		members = { "party", "partyroles", "partynames", "partystatus", "rspartyplayers", "rspartypets", "rspartyroles",
		"rspartythreat", "rspartynames", "rspartypetnames", "rspartytitles", "rspartybuffs", "rspartydebuffs" },
		triggers = { roster = true } },
	{ preset = "raidmanager", icon = "Interface\\Icons\\Ability_Warrior_RallyingCry", name = L["Raid Frame Manager"],
		members = { "raidmanager" }, triggers = { roster = true }, when = "calm" },
	{ preset = "minimap", icon = "Interface\\Icons\\INV_Misc_Map_01", name = L["Minimap"],
		members = { "minimap", "minimapheader", "minimapzone", "minimaptracking", "minimapcalendar", "minimapclock",
			"minimapdial" },
		triggers = { ping = true, tracking = true } },
	{ preset = "buffs", icon = "Interface\\Icons\\Spell_Holy_WordFortitude", name = L["Buffs"],
		members = { "buffs" }, triggers = { aura = true } },
	{ preset = "quests", icon = "Interface\\Icons\\INV_Misc_Note_01", name = L["Quest tracker"],
		members = { "quests" }, triggers = { quest = true } },
	{ preset = "gamepad", icon = "Interface\\Icons\\INV_Gizmo_01", name = L["Gamepad action bars"],
		members = { "gamepadbars" }, triggers = { gamepad = true } },
	{ preset = "chat", icon = "Interface\\Icons\\INV_Scroll_03", name = L["Chat"],
		members = { "chat" }, triggers = { whisper = true, typing = true } },
	{ preset = "cooldowns", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", name = L["Cooldowns"],
		members = { "cooldowns", "cooldownsutility", "cooldownsbuffs", "cooldownsbars", "addon:fecm", "addon:fecmAuras" },
		triggers = { cooldown = true } },
}

-- The icons a group you make can have (the Mouseover groups page's picker).
ns.HOVER_GROUP_ICONS = {
	"Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_Gear_01",
	"Interface\\Icons\\INV_Misc_Bag_07", "Interface\\Icons\\INV_Misc_Coin_01",
	"Interface\\Icons\\INV_Misc_Key_03", "Interface\\Icons\\INV_Misc_Rune_01",
	"Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\INV_Misc_Book_11",
	"Interface\\Icons\\INV_Misc_Gift_01", "Interface\\Icons\\INV_Misc_Spyglass_03",
	"Interface\\Icons\\INV_Misc_Gem_Emerald_01", "Interface\\Icons\\INV_Potion_01",
	"Interface\\Icons\\INV_Ore_Copper_01", "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
	"Interface\\Icons\\INV_Weapon_Bow_07", "Interface\\Icons\\Spell_Holy_MindVision",
	"Interface\\Icons\\Spell_Holy_HolyBolt", "Interface\\Icons\\Spell_Holy_PowerWordShield",
	"Interface\\Icons\\Spell_Fire_FlameBolt", "Interface\\Icons\\Spell_Frost_FrostBolt02",
	"Interface\\Icons\\Spell_Shadow_ShadowBolt", "Interface\\Icons\\Spell_Nature_Lightning",
	"Interface\\Icons\\Spell_Nature_HealingTouch", "Interface\\Icons\\Spell_Nature_Regeneration",
	"Interface\\Icons\\Spell_Nature_Polymorph", "Interface\\Icons\\Spell_Arcane_Blink",
	"Interface\\Icons\\Ability_Warrior_BattleShout", "Interface\\Icons\\Ability_Rogue_Sprint",
	"Interface\\Icons\\Ability_Stealth", "Interface\\Icons\\Ability_Ambush",
	"Interface\\Icons\\Ability_Mount_RidingHorse", "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
	"Interface\\Icons\\Trade_Engineering", "Interface\\Icons\\Trade_Fishing",
	"Interface\\Icons\\Trade_Alchemy", "Interface\\Icons\\Trade_BlackSmithing",
	"Interface\\Icons\\Trade_Tailoring", "Interface\\Icons\\Trade_Herbalism",
	"Interface\\Icons\\Trade_Mining", "Interface\\Icons\\INV_BannerPVP_01",
	"Interface\\Icons\\Spell_Shadow_AntiShadow", "Interface\\Icons\\Spell_Holy_Renew",
	"Interface\\Icons\\Spell_Holy_FlashHeal", "Interface\\Icons\\Spell_Holy_GreaterHeal",
	"Interface\\Icons\\Spell_Holy_Resurrection", "Interface\\Icons\\Spell_Holy_SealOfMight",
	"Interface\\Icons\\Spell_Holy_DivineIntervention", "Interface\\Icons\\Spell_Holy_Heal",
	"Interface\\Icons\\Spell_Holy_WordFortitude", "Interface\\Icons\\Spell_Holy_MagicalSentry",
	"Interface\\Icons\\Spell_Holy_SealOfSacrifice", "Interface\\Icons\\Spell_Fire_Fireball02",
	"Interface\\Icons\\Spell_Fire_FireArmor", "Interface\\Icons\\Spell_Fire_SelfDestruct",
	"Interface\\Icons\\Spell_Fire_Fire", "Interface\\Icons\\Spell_Fire_SoulBurn",
	"Interface\\Icons\\Spell_Fire_Immolation", "Interface\\Icons\\Spell_Fire_Volcano",
	"Interface\\Icons\\Spell_Frost_FrostNova", "Interface\\Icons\\Spell_Frost_IceStorm",
	"Interface\\Icons\\Spell_Frost_FrostArmor02", "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
	"Interface\\Icons\\Spell_Frost_ChainsOfIce", "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
	"Interface\\Icons\\Spell_Shadow_DeathCoil", "Interface\\Icons\\Spell_Shadow_Teleport",
	"Interface\\Icons\\Spell_Shadow_Haunting", "Interface\\Icons\\Spell_Shadow_RaiseDead",
	"Interface\\Icons\\Spell_Shadow_SummonImp", "Interface\\Icons\\Spell_Shadow_Metamorphosis",
	"Interface\\Icons\\Spell_Shadow_Possession", "Interface\\Icons\\Spell_Shadow_Twilight",
	"Interface\\Icons\\Spell_Shadow_Charm", "Interface\\Icons\\Spell_Nature_StarFall",
	"Interface\\Icons\\Spell_Nature_Rejuvenation", "Interface\\Icons\\Spell_Nature_Thorns",
	"Interface\\Icons\\Spell_Nature_Cyclone", "Interface\\Icons\\Spell_Nature_Invisibilty",
	"Interface\\Icons\\Spell_Nature_TimeStop", "Interface\\Icons\\Spell_Nature_ResistNature",
	"Interface\\Icons\\Spell_Nature_WispSplode", "Interface\\Icons\\Spell_Nature_MoonKey",
	"Interface\\Icons\\Spell_Nature_Sleep", "Interface\\Icons\\Spell_Nature_SpiritWolf",
	"Interface\\Icons\\Spell_Nature_LightningShield", "Interface\\Icons\\Spell_Nature_Earthquake",
	"Interface\\Icons\\Spell_Arcane_PortalStormWind", "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar",
	"Interface\\Icons\\Spell_Arcane_StarFire", "Interface\\Icons\\Spell_Arcane_MindMastery",
	"Interface\\Icons\\Spell_Magic_PolymorphChicken", "Interface\\Icons\\Spell_Magic_LesserInvisibilty",
	"Interface\\Icons\\Ability_Hunter_SniperShot", "Interface\\Icons\\Ability_Hunter_EagleEye",
	"Interface\\Icons\\Ability_Hunter_Pet_Bear", "Interface\\Icons\\Ability_Hunter_Pet_Cat",
	"Interface\\Icons\\Ability_Hunter_Pet_Owl", "Interface\\Icons\\Ability_Hunter_Pet_Raptor",
	"Interface\\Icons\\Ability_Druid_CatForm", "Interface\\Icons\\Ability_Racial_BearForm",
	"Interface\\Icons\\Ability_Druid_TravelForm", "Interface\\Icons\\Ability_Druid_AquaticForm",
	"Interface\\Icons\\Ability_Warrior_DefensiveStance", "Interface\\Icons\\Ability_Warrior_Charge",
	"Interface\\Icons\\Ability_Warrior_Sunder", "Interface\\Icons\\Ability_Rogue_Eviscerate",
	"Interface\\Icons\\Ability_Rogue_FeignDeath", "Interface\\Icons\\Ability_Rogue_Disguise",
	"Interface\\Icons\\Ability_Mount_WhiteTiger", "Interface\\Icons\\Ability_Mount_JungleTiger",
	"Interface\\Icons\\Ability_Mount_Raptor", "Interface\\Icons\\Ability_Mount_Kodo_01",
	"Interface\\Icons\\Ability_Mount_MountainRam", "Interface\\Icons\\Ability_Mount_Undeadhorse",
	"Interface\\Icons\\Ability_Mount_NightmareHorse", "Interface\\Icons\\Ability_Parry",
	"Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\Ability_ThunderBolt",
	"Interface\\Icons\\Ability_Racial_Cannibalize", "Interface\\Icons\\Racial_Orc_BerserkerStrength",
	"Interface\\Icons\\Racial_Troll_Berserk", "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	"Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", "Interface\\Icons\\INV_Misc_Fish_02",
	"Interface\\Icons\\INV_Drink_05", "Interface\\Icons\\INV_Misc_Map_01",
	"Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\INV_Misc_Lantern_01",
	"Interface\\Icons\\INV_Misc_Orb_01", "Interface\\Icons\\INV_Misc_Shovel_01",
	"Interface\\Icons\\INV_Misc_Flower_02", "Interface\\Icons\\INV_Misc_Dice_01",
	"Interface\\Icons\\INV_Misc_Drum_01", "Interface\\Icons\\INV_Misc_Horn_01",
	"Interface\\Icons\\INV_Misc_Bell_01", "Interface\\Icons\\INV_Misc_MonsterClaw_04",
	"Interface\\Icons\\INV_Misc_PocketWatch_01", "Interface\\Icons\\INV_Ammo_Arrow_01",
	"Interface\\Icons\\INV_Sword_39", "Interface\\Icons\\INV_Axe_09",
	"Interface\\Icons\\INV_Mace_01", "Interface\\Icons\\INV_Staff_13",
	"Interface\\Icons\\INV_Wand_07", "Interface\\Icons\\INV_Shield_06",
	"Interface\\Icons\\INV_Helmet_03", "Interface\\Icons\\INV_Chest_Plate06",
	"Interface\\Icons\\INV_Jewelry_Ring_03", "Interface\\Icons\\INV_Crown_01",
	"Interface\\Icons\\INV_Hammer_16", "Interface\\Icons\\INV_Mushroom_11",
	"Interface\\Icons\\INV_Fabric_Linen_01", "Interface\\Icons\\INV_Misc_Gem_Ruby_01",
	"Interface\\Icons\\INV_Enchant_EssenceMagicLarge", "Interface\\Icons\\INV_Torch_Lit",
	"Interface\\Icons\\INV_Scroll_03", "Interface\\Icons\\INV_Misc_Ribbon_01",
	"Interface\\Icons\\INV_Misc_Bomb_02", "Interface\\Icons\\INV_Gizmo_02",
	"Interface\\Icons\\INV_Box_01", "Interface\\Icons\\INV_Misc_Bag_10",
	"Interface\\Icons\\INV_Misc_Coin_02", "Interface\\Icons\\INV_BannerPVP_02",
	"Interface\\Icons\\Trade_BrewPoison", "Interface\\Icons\\Trade_Engraving",
	"Interface\\Icons\\Trade_LeatherWorking",
}

do
	-- The default group a group is (its preset; copies made before presets
	-- were kept are found by name), or nil for one you made.
	local byPreset, byName = {}, {}
	for _, group in ipairs(ns.HOVER_GROUPS_DEFAULT) do
		byPreset[group.preset], byName[group.name] = group, group
	end
	function ns.HoverGroupPreset(group)
		return (group.preset and byPreset[group.preset]) or (not group.preset and byName[group.name]) or nil
	end

	-- What a setting picking groups saves for one: a default group's preset
	-- (kept through renames), or the name of one you made.
	function ns.HoverGroupId(group)
		local preset = ns.HoverGroupPreset(group)
		return preset and preset.preset or group.name
	end

	-- A group's icon: a default group's own, or the one picked for it.
	function ns.HoverGroupIcon(group)
		local preset = ns.HoverGroupPreset(group)
		return preset and preset.icon or group.icon or ns.HOVER_GROUP_ICONS[1]
	end

	-- An icon no group has yet (for a new one), else the first.
	function ns.UnusedHoverGroupIcon()
		local used = {}
		for _, group in ipairs(ns.GetHoverGroups()) do used[ns.HoverGroupIcon(group)] = true end
		for i = 2, #ns.HOVER_GROUP_ICONS do
			if not used[ns.HOVER_GROUP_ICONS[i]] then return ns.HOVER_GROUP_ICONS[i] end
		end
		return ns.HOVER_GROUP_ICONS[1]
	end
end

-- The groups in use: the player's (db.hoverGroups), or the defaults until
-- they change them.
function ns.GetHoverGroups()
	return ns.db.hoverGroups or ns.HOVER_GROUPS_DEFAULT
end

-- A copy of the groups in use, to change (the Mouseover page's first edit).
function ns.CopyHoverGroups()
	local copy = {}
	for _, group in ipairs(ns.GetHoverGroups()) do
		local members, triggers = {}, {}
		for i, key in ipairs(group.members or {}) do members[i] = key end
		for key, on in pairs(group.triggers or {}) do triggers[key] = on end
		local preset = ns.HoverGroupPreset(group)
		copy[#copy + 1] = { name = group.name, members = members, triggers = triggers, when = group.when,
			off = group.off, preset = preset and preset.preset or nil, icon = not preset and group.icon or nil }
	end
	return copy
end

-- Whether an option belongs on this client, for the options pages to skip
-- the rest: retail = true or false limits it to retail or to Classic clients.
-- Otherwise an option about frames needs one of them to exist. (Frames made
-- later, like the swing timer, are marked by client instead, since the pages
-- are built as the addon loads.)
function ns.OptionAvailable(item)
	if item.retail ~= nil then
		return item.retail == ns.isRetail
	end
	-- (Frames from an addon that loads later don't exist yet.)
	if item.addon then
		return ns.AddOnInstalled(item.addon)
	end
	if item.frames then
		for _, name in ipairs(item.frames) do
			if _G[name] then
				return true
			end
		end
		return false
	end
	return true
end

-- When an enemy is targeted out of combat, a separate list applies
-- (db.targetShow); by default just the target and its target.
local TARGET_SHOW_DEFAULT = { target = true, tot = true }
-- Enemy targeted: also the action bars, buffs and the like.
local ENEMY_SHOW_DEFAULT = {
	player = true, prd = true, prdpower = true, prdmana = true, target = true, tot = true, focus = true, buffs = true,
	mainbar = true,
	bottomleft = true, bottomright = true, pet = true, stance = true, totems = true, micro = true, bags = true, xp = true,
	gamepadbars = true, gamepadreticle = true,
}
-- Other addons' frames too.
for _, known in ipairs(ns.ADDON_FRAMES) do
	ENEMY_SHOW_DEFAULT["addon:" .. known.key] = true
end

-- Gamepad mode on. On WoW Forever: its gamepad bars are showing (the game
-- shows and hides them; the fade only sets their alpha). GamePadEnable stays
-- on there with the gamepad UI off, so it can't tell. Retail has no gamepad
-- UI of its own: the setting it is.
function ns.IsGamePadOn()
	if not ns.isRetail then
		local bar = _G.GamepadMainActionBarFrame
		return bar ~= nil and ns.Flag(bar:IsShown())
	end
	return C_GamePad ~= nil and GetCVarBool("GamePadEnable")
end

-- Frames added on the Advanced Frames page ("extra:<name>") start out with
-- nothing ticked: faded the whole time in CineMode until their row says.
local function IsExtraKey(key)
	return key:find("^extra:") ~= nil
end

-- Rows that take another row's tick in a column until given their own: the
-- bar art follows action bar 1, the pet portrait yours, the focus's target of target the focus, the bags the micro menu
-- and the minimap header and its buttons the minimap, so profiles and lists
-- from before it was a row (the Cooldown Manager profile's: no action bars) still hold.
local ROW_FALLBACK = {
	art = "mainbar", petframe = "player", prdpower = "prd", prdmana = "prdpower", focustot = "focus", minimapheader = "minimap", minimaptracking = "minimap", minimapcalendar = "minimap",
	minimapzone = "minimap", minimapclock = "minimap", minimapdial = "minimap", bags = "micro",
	belowminimap = "quests", topcenter = "quests",
	cooldownsutility = "cooldowns", cooldownsbuffs = "cooldowns", cooldownsbars = "cooldowns",
	["addon:fecmAuras"] = "addon:fecm",
}
-- (And the raid-style party frames' rows the raid frames'.)
for raidKey, key in pairs(ns.RAID_STYLE_PARTY) do
	ROW_FALLBACK[key] = raidKey
end
-- (For the settings: ticking a row gives those that follow it ticks of their own first, GridRows.lua.)
ns.ROW_FALLBACK = ROW_FALLBACK

function ns.IsCombatShowOn(key)
	local on = ns.db.combatShow[key]
	if on == nil then
		if ROW_FALLBACK[key] then
			return ns.IsCombatShowOn(ROW_FALLBACK[key])
		end
		if IsExtraKey(key) then
			return false
		end
		if ns.LIST_DEFAULTS.combatShow[key] ~= nil then
			return ns.LIST_DEFAULTS.combatShow[key]
		end
		for _, item in ipairs(ns.COMBAT_SHOW) do
			if item.key == key then return item.default end
		end
	end
	return on
end

local function IsListOn(list, key, defaults)
	local on = ns.db[list][key]
	if on == nil then
		if ROW_FALLBACK[key] then
			return IsListOn(list, ROW_FALLBACK[key], defaults)
		end
		if IsExtraKey(key) then
			return false
		end
		local more = ns.LIST_DEFAULTS[list]
		return defaults[key] or (more and more[key]) or false
	end
	return on
end

-- Standard Frames page's Always column (cineShow): ticked, a row's frames stay shown all through CineMode.
-- Some rows' Always tick is an option elsewhere too (the same setting).
ns.CINE_SHOW_SETTING = { minimap = "alwaysShowMinimap", waypoint = "alwaysShowWaypoint" }
-- Rows ticked there until changed (no profile lists them, so none hides them).
local CINE_SHOW_DEFAULT = {
	flags = true, castbar = true, partyroles = true, partynames = true, partystatus = true,
	raidroles = true, raidnames = true, raidpetnames = true, raidtitles = true, raidbuffs = true,
	raiddebuffs = true, raidthreat = true, raidtarget = true, raidready = true, extra = true, voice = true,
	encounter = true, targetcircle = true, focustot = true, belowminimap = true,
}
function ns.IsCineShowOn(key)
	local setting = ns.CINE_SHOW_SETTING[key]
	if setting then
		return ns.db[setting] or false
	end
	local on = ns.db.cineShow[key]
	-- (A default of its own wins over the row it follows: the focus's target of target.)
	if on == nil and CINE_SHOW_DEFAULT[key] then
		return true
	end
	if on == nil and ROW_FALLBACK[key] then
		return ns.IsCineShowOn(ROW_FALLBACK[key])
	end
	if on == nil then
		return CINE_SHOW_DEFAULT[key] or false
	end
	return on
end
function ns.IsEnemyShowOn(key) return IsListOn("enemyShow", key, ENEMY_SHOW_DEFAULT) end
-- Whether a row's on for the Calm Timer after a fight, the cool-down (the
-- Combat dropdown's Calm Timer: a time of its own, beside In combat and Out of
-- combat): its own tick, else what it follows, else its default, else, for a
-- row ticked In combat, combatShowCalm (the page's one switch, before: those
-- rows stayed for it).
function ns.IsCalmShowOn(key)
	local on = ns.db.calmShow and ns.db.calmShow[key]
	if on == nil and ROW_FALLBACK[key] then
		return ns.IsCalmShowOn(ROW_FALLBACK[key])
	end
	if on == nil and ns.LIST_DEFAULTS.calmShow[key] ~= nil then
		return ns.LIST_DEFAULTS.calmShow[key]
	end
	if on == nil then
		return ns.db.combatShowCalm and ns.IsCombatShowOn(key) and true or false
	end
	return on
end
function ns.IsFriendlyShowOn(key) return IsListOn("friendlyShow", key, TARGET_SHOW_DEFAULT) end

-- The frames pages' place columns, after the others: ticked, a row's frames
-- stay shown all through CineMode there, in fights and out, as the Always
-- column does everywhere. Grouped isn't a place: a party or raid, anywhere.
-- Places as the Nameplates page has them (bar its PvP flagged column, which
-- goes with the open world here). Their defaults are below.
ns.PLACE_SHOW = {
	{ list = "bgShow", label = L["BGs & Arenas"], tip = L["Show all through CineMode in battlegrounds and arenas."] },
	{ list = "worldShow", label = L["Open World"],
		tip = L["Show all through CineMode out in the world, inns included (capital cities are Cities)."] },
	{ list = "cityShow", label = L["Cities"], tip = L["Show all through CineMode in capital cities."] },
	{ list = "groupShow", label = L["Grouped"],
		tip = L["Show all through CineMode while you're in a party or raid, wherever you are."] },
	{ list = "instanceShow", label = L["Instances"],
		tip = L["Show all through CineMode in dungeons, scenarios and raids."] },
}
local NO_DEFAULTS = {}
-- Ticked to start with: the raid and party frames in battlegrounds and
-- arenas, where you're always in a group, and in dungeons, scenarios and
-- raids (nothing else: what you'd want hidden out of fights elsewhere you'd
-- want hidden there too); and the party frames and raid frames' players
-- whenever you're grouped.
local PLACE_SHOW_DEFAULTS = {
	bgShow = { raidplayers = true, raidpets = true, party = true },
	groupShow = { raidplayers = true, party = true },
	instanceShow = { raidplayers = true, raidpets = true, party = true },
}
local function PlaceDefaults(list)
	return PLACE_SHOW_DEFAULTS[list] or NO_DEFAULTS
end
function ns.IsPlaceShowOn(list, key) return IsListOn(list, key, PlaceDefaults(list)) end
-- The Combat dropdown's Out of combat (quietShow: on out of fights, and with
-- the row's Calm Timer past it) and In a camera mode (camShow), for the grids
-- that offer them (Visual Effects, music, tooltips...).
function ns.IsQuietShowOn(key) return IsListOn("quietShow", key, NO_DEFAULTS) end
function ns.IsCamShowOn(key) return IsListOn("camShow", key, NO_DEFAULTS) end

-- The place columns that apply where you are now.
-- Tables UpdateFrames (and what it calls) fills afresh each tick, kept rather
-- than made anew: making them 33 times a second was a lot of garbage.
local tickTables = {
	hovered = {}, triggered = {}, pinged = {}, mouseRows = {}, mouseGroups = {}, events = {},
	combatShown = {}, placeLists = {}, auraOnly = {}, cooldownBarUp = {},
	partsHovered = {}, partsHeldUntil = {}, deathKept = {},
}

-- "group:<group>", a group's key in the shown lists, made once for each
-- group: built every tick for each faded frame's group, it was garbage.
local GROUP_KEY = setmetatable({}, { __index = function(keys, group)
	local key = "group:" .. group
	keys[group] = key
	return key
end })

local function PlaceListsHere()
	local place = ns.GetPlaceType()
	local lists = wipe(tickTables.placeLists)
	lists[1] = (place == "pvp" and "bgShow")
		or ((place == "dungeon" or place == "raid") and "instanceShow") or (place == "city" and "cityShow") or "worldShow"
	if ns.InGroup() then
		lists[2] = "groupShow"
	end
	return lists
end

-- Rules (a test): a boolean expression in place of a Standard Frames row's
-- ticks (db.frameRules: row -> text), like "combat and (world or bg) and not
-- dungeon". Words: the situations below; and, or, not (also &, |, !) and
-- brackets. ns.CompileRule(text) gives a test of a facts table, or nil and
-- what's wrong; compiled once per text. ns.RuleShows(key, facts) is the
-- row's rule's answer, or nil with no rule (or a broken one): the ticks decide then.
-- The situations a rule can name, each a field of the facts table (aliases too).
ns.RULE_WORDS = {
	always = "always", ["true"] = "always", never = "never", ["false"] = "never",
	combat = "combat", fighting = "combat", calm = "calm", nocombat = "nocombat", camera = "camera", cam = "camera",
	enemy = "enemy", friendly = "friendly", target = "target",
	-- (Your target by what it is, as Effects' TargetRow has it.)
	targetself = "targetself", enemyplayer = "enemyplayer", hostilenpc = "hostilenpc", neutralplayer = "neutralplayer",
	neutralnpc = "neutralnpc", friendlyplayer = "friendlyplayer", friendlynpc = "friendlynpc",
	noplate = "noplate", plateoff = "noplate", offscreen = "noplate", near = "near", close = "near", near28 = "near28",
	-- (Spell range bands: see RANGE_BANDS. spellrange, from before the bands,
	-- and near40, its name before that, read as the nearest band.)
	range5to10 = "range5to10", range20to25 = "range20to25", range30to35 = "range30to35", range40plus = "range40plus",
	spellrange = "range30to35", range = "range30to35", near40 = "range40plus",
	elite11 = "elite11", elite = "elite28", elite28 = "elite28", elite40 = "elite40",
	bg = "bg", bgs = "bg", pvp = "bg", battleground = "battleground", arena = "arena", arenas = "arena",
	world = "world", group = "group", grouped = "group", instance = "instance",
	dungeon = "dungeon", raid = "raid", city = "city", inn = "inn",
	flagged = "flagged", mounted = "mounted",
	-- (CineMode on: always so for the rows read in it, the frames'; Combat Vision's is read any time.)
	cinemode = "cinemode", cine = "cinemode",
	-- (A fight starting or ending: only Combat Vision's row is read then.)
	entering = "entering", enter = "entering", leaving = "leaving", leave = "leaving",
	boss = "boss",
	-- (The tooltip being decided on, by kind: only the Tooltips row's rule reads them.)
	tipenemy = "tipenemy", tipfriendly = "tipfriendly", tipgather = "tipgather", tipquest = "tipquest",
	tipother = "tipother",
	tank = "tank", healer = "healer", heal = "healer", damage = "damage", dps = "damage",
	-- (Your class: its file name, lower case. All of them, so a rule reads on every client.)
	warrior = "warrior", paladin = "paladin", hunter = "hunter", rogue = "rogue", priest = "priest",
	deathknight = "deathknight", dk = "deathknight", shaman = "shaman", mage = "mage", warlock = "warlock",
	monk = "monk", druid = "druid", demonhunter = "demonhunter", dh = "demonhunter", evoker = "evoker",
}
do
	local OPERATORS = { ["and"] = "and", ["&"] = "and", ["&&"] = "and", ["or"] = "or", ["|"] = "or", ["||"] = "or",
		["not"] = "not", ["!"] = "not" }
	local compiled = {}

	local function Tokens(text)
		local tokens = {}
		local i = 1
		while i <= #text do
			local c = text:sub(i, i)
			if c:find("%s") then
				i = i + 1
			elseif c == "(" or c == ")" then
				tokens[#tokens + 1] = c
				i = i + 1
			elseif c == "&" or c == "|" or c == "!" then
				local run = text:match("^[&|]+", i) or c
				tokens[#tokens + 1] = OPERATORS[run] or run
				i = i + #run
			else
				local word = text:match("^[%w_]+", i)
				if not word then
					return nil, ("can't read \"%s\""):format(c)
				end
				word = word:lower()
				tokens[#tokens + 1] = OPERATORS[word] or word
				i = i + #word
			end
		end
		return tokens
	end

	-- Recursive descent: or binds loosest, then and, then not.
	function ns.CompileRule(text)
		local cached = compiled[text]
		if cached then
			return cached[1], cached[2]
		end
		local tokens, err = Tokens(text)
		local pos = 1
		local Or
		local function Unary()
			local token = tokens[pos]
			if token == "not" then
				pos = pos + 1
				local inner = Unary()
				return inner and function(f) return not inner(f) end
			elseif token == "(" then
				pos = pos + 1
				local inner = Or()
				if not inner then return nil end
				if tokens[pos] ~= ")" then
					err = err or "a ( has no )"
					return nil
				end
				pos = pos + 1
				return inner
			elseif token == nil then
				err = err or "it ends too soon"
			elseif ns.RULE_WORDS[token] then
				local field = ns.RULE_WORDS[token]
				pos = pos + 1
				return function(f) return f[field] end
			else
				err = err or ("\"%s\" isn't a word it knows"):format(token)
			end
		end
		local function And()
			local left = Unary()
			while left and tokens[pos] == "and" do
				pos = pos + 1
				local a, b = left, Unary()
				left = b and function(f) return a(f) and b(f) end
			end
			return left
		end
		function Or()
			local left = And()
			while left and tokens[pos] == "or" do
				pos = pos + 1
				local a, b = left, And()
				left = b and function(f) return a(f) or b(f) end
			end
			return left
		end
		local test
		if tokens then
			test = Or()
			if test and tokens[pos] ~= nil then
				test, err = nil, ("\"%s\" is out of place"):format(tokens[pos])
			end
		end
		compiled[text] = { test, not test and err or nil }
		return test, not test and err or nil
	end

	-- The rows kept hidden in CineMode while you're the role you are (a grid
	-- row's roles button: tankHide, healerHide, damageHide), key -> true.
	local NO_ROWS = {}
	function ns.RoleHides(facts)
		return facts.tank and ns.db.tankHide or facts.healer and ns.db.healerHide
			or facts.damage and ns.db.damageHide or NO_ROWS
	end

	function ns.RuleShows(key, facts)
		local test = ns.RuleTest(key)
		if test then
			return test(facts) and true or false
		end
	end
	-- The row's rule, compiled, when it has one that reads.
	function ns.RuleTest(key)
		local text = ns.db.frameRules and ns.db.frameRules[key]
		if type(text) ~= "string" or not text:find("%S") then
			return nil
		end
		return (ns.CompileRule(text))
	end

	-- Whether a unit is within an interact distance (the rules' near: 2,
	-- about 11 yards; near28: 4, about 28). False when it can't say.
	-- Never asked in a fight: retail blocks it there and blames us, for
	-- nameplate units (dozens of times a second) and for "target" too, asked
	-- from the game's code or from a frame of our own alike (tested 2026-10-29).
	-- True or false; nil when nothing can say.
	local function InteractDistance(unit, index)
		if InCombatLockdown() then
			return nil
		end
		local ok, near = pcall(CheckInteractDistance, unit, index)
		if ok and near ~= nil and not (issecretvalue and issecretvalue(near)) then
			return near and true or false
		end
	end
	local function UnitWithin(unit, index)
		return InteractDistance(unit, index) or false
	end
	local function TargetWithin(index)
		return UnitWithin("target", index)
	end

	-- The 40-yard bands (elite40, In40, Past40): no interact distance goes
	-- past 28, so a 40-yard spell's range from your action bars (harmful for
	-- enemies, helpful for friends; plain in retail fights, tested with
	-- Lightning Bolt). Looked for again every few seconds (bars and talents
	-- change). False with no such spell.
	-- The rules' Spell range bands, the same words on every class: your
	-- target within reach of your shortest spell in the band (a range up to
	-- the next band's start counts in it: 28 yards goes in 20-25). A class
	-- with none in it falls back to the next band down, never up, so a band
	-- never counts further than it says; with none below either, false.
	-- Attack spells for enemies, helpful ones for friends, each on its own.
	local RANGE_YARDS, RANGE_LOOK_EVERY = 40, 3
	local RANGE_BANDS = {
		{ field = "range5to10", from = 0, label = "5-10" },
		{ field = "range20to25", from = 20, label = "20-25" },
		{ field = "range30to35", from = 30, label = "30-35" },
		{ field = "range40plus", from = 40, label = "40+" },
	}
	ns.RANGE_BANDS = RANGE_BANDS
	local rangeSpells, rangeLookAt = {}, -math.huge
	local RANGE_TESTS = {
		harmful = C_Spell and C_Spell.IsSpellHarmful or IsHarmfulSpell,
		helpful = C_Spell and C_Spell.IsSpellHelpful or IsHelpfulSpell,
	}
	-- (Each band's shortest spell: bandSpells[i].harmful = id, its yards
	-- in bandSpells[i].harmfulYards.)
	local bandSpells = {}
	for i = 1, #RANGE_BANDS do bandSpells[i] = {} end
	local function BandOf(yards)
		for i = #RANGE_BANDS, 1, -1 do
			if yards >= RANGE_BANDS[i].from then return i end
		end
	end
	local function FindRangeSpells()
		rangeSpells.harmful, rangeSpells.helpful = nil, nil
		for _, band in ipairs(bandSpells) do wipe(band) end
		local best = {}
		for slot = 1, 180 do
			local ok, kind, id = pcall(GetActionInfo, slot)
			if ok and kind == "spell" and type(id) == "number" and not (issecretvalue and issecretvalue(id)) then
				local maxRange, minRange
				if C_Spell and C_Spell.GetSpellInfo then
					local okInfo, info = pcall(C_Spell.GetSpellInfo, id)
					if okInfo and type(info) == "table" then
						maxRange, minRange = info.maxRange, info.minRange
					end
				elseif GetSpellInfo then
					minRange, maxRange = select(5, GetSpellInfo(id))
				end
				-- (Classic Era, game 11509, gives Auto Shot's the wrong way round,
				-- 35 as its least and 0 as its most (tested): the larger is the range.)
				if type(minRange) == "number" and not (issecretvalue and issecretvalue(minRange))
					and (type(maxRange) ~= "number" or (not (issecretvalue and issecretvalue(maxRange)) and minRange > maxRange)) then
					maxRange = minRange
				end
				if type(maxRange) == "number" and not (issecretvalue and issecretvalue(maxRange))
					and maxRange > 0 then
					for key, test in pairs(RANGE_TESTS) do
						local okTest, is = pcall(test, id)
						if okTest and is == true then
							-- (The nearest range at or past 40, so the word means about 40.)
							if maxRange >= RANGE_YARDS and (not best[key] or maxRange < best[key]) then
								rangeSpells[key], best[key] = id, maxRange
							end
							local band = bandSpells[BandOf(maxRange)]
							local had = band[key .. "Yards"]
							if not had or maxRange < had then
								band[key], band[key .. "Yards"] = id, maxRange
							end
						end
					end
				end
			end
		end
	end
	-- Whether a spell reaches a unit: true, false, or nil when it can't say.
	local function SpellReaches(id, unit)
		local inRange = C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
		if not id or not inRange then return nil end
		-- (Old clients want the name and answer 1 or 0.)
		local spell = C_Spell and C_Spell.IsSpellInRange and id or (GetSpellInfo and GetSpellInfo(id))
		local ok, answer = pcall(inRange, spell, unit)
		if ok and answer ~= nil and not (issecretvalue and issecretvalue(answer)) then
			return answer == true or answer == 1
		end
	end
	local function LookForRangeSpells()
		local now = GetTime()
		if now - rangeLookAt >= RANGE_LOOK_EVERY then
			rangeLookAt = now
			FindRangeSpells()
		end
	end
	local function UnitWithin40(unit, enemyOnly)
		LookForRangeSpells()
		local answer = SpellReaches(rangeSpells.harmful, unit)
		if answer == nil and not enemyOnly then
			answer = SpellReaches(rangeSpells.helpful, unit)
		end
		return answer or false
	end
	-- A band's spell of a kind (harmful or helpful), falling back down:
	-- its id, its yards and the band it's from; nil with none at or below.
	local function BandSpell(index, key)
		for i = index, 1, -1 do
			local band = bandSpells[i]
			if band[key] then return band[key], band[key .. "Yards"], i end
		end
	end
	local function TargetInBand(index)
		local answer = SpellReaches((BandSpell(index, "harmful")), "target")
		if answer == nil then
			answer = SpellReaches((BandSpell(index, "helpful")), "target")
		end
		return answer or false
	end
	-- What a band measures with on this character, for its button's tip.
	function ns.RangeBandInfo(field)
		LookForRangeSpells()
		local index
		for i, band in ipairs(RANGE_BANDS) do
			if band.field == field then index = i end
		end
		if not index then return "" end
		-- (Just the spell and its range: the attack one, then a helpful one.)
		local lines = {}
		for _, kind in ipairs({ "harmful", "helpful" }) do
			local id, yards = BandSpell(index, kind)
			if id then
				local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
					or GetSpellInfo and GetSpellInfo(id) or tostring(id)
				lines[#lines + 1] = (L["%s, %d yards"]):format(name, yards)
			end
		end
		return #lines > 0 and table.concat(lines, "\n") or L["No spell"]
	end
	-- /cine debug spellrange: what the finder sees on your bars.
	function ns.ReportSpellRange()
		local function Show(fn, ...)
			if not fn then return "no api" end
			local ok, value = pcall(fn, ...)
			if not ok then return "error" end
			if issecretvalue and issecretvalue(value) then return "secret" end
			return tostring(value)
		end
		ns.Print(("spellrange: game %s, in combat %s, target %s (%s)"):format(tostring((select(4, GetBuildInfo()))),
			tostring(InCombatLockdown()), Show(UnitName, "target"), ns.HasTarget() and "enemy " .. tostring(ns.IsEnemyUnit("target")) or "none"))
		local kinds, spells = {}, 0
		for slot = 1, 180 do
			local ok, kind, id = pcall(GetActionInfo, slot)
			if ok and kind then
				kinds[kind] = (kinds[kind] or 0) + 1
				if kind == "spell" and spells < 20 then
					spells = spells + 1
					local name, maxRange, minRange = "?", "?", "?"
					if C_Spell and C_Spell.GetSpellInfo then
						local okInfo, info = pcall(C_Spell.GetSpellInfo, id)
						if okInfo and type(info) == "table" then
							name, maxRange, minRange = tostring(info.name), tostring(info.maxRange), tostring(info.minRange)
						end
					end
					local inRange = C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
					ns.Print(("  slot %d: %s %s, range %s-%s, harmful %s, helpful %s, reaches target %s"):format(slot,
						tostring(id), name, minRange, maxRange, Show(RANGE_TESTS.harmful, id), Show(RANGE_TESTS.helpful, id),
						Show(inRange, id, "target")))
				end
			end
		end
		local list = {}
		for kind, count in pairs(kinds) do list[#list + 1] = kind .. " " .. count end
		ns.Print("  action kinds: " .. (#list > 0 and table.concat(list, ", ") or "none"))
		rangeLookAt = -math.huge
		LookForRangeSpells()
		for i, band in ipairs(RANGE_BANDS) do
			local harmful, harmfulYards, harmfulFrom = BandSpell(i, "harmful")
			local helpful, helpfulYards, helpfulFrom = BandSpell(i, "helpful")
			ns.Print(("  %s: harmful %s (%s yd, band %s), helpful %s (%s yd, band %s), target in it %s"):format(band.label,
				tostring(harmful), tostring(harmfulYards), tostring(harmfulFrom), tostring(helpful), tostring(helpfulYards),
				tostring(helpfulFrom), ns.HasTarget() and tostring(TargetInBand(i)) or "no target"))
		end
		ns.Print(("  40-yard (elite40, Distance rows): harmful %s, helpful %s"):format(
			tostring(rangeSpells.harmful), tostring(rangeSpells.helpful)))
	end
	-- Whether a unit's that far from you, for the Nameplates page's rows with
	-- a Distance (Core's MARK_DISTANCES): In11, In28 and In40 within about 11,
	-- 28 or 40 yards, Past28 and Past40 further. True or false; nil when
	-- nothing can say (40: no 40-yard spell on your bars that can). In a
	-- fight, as InteractDistance has it.
	local Within = InteractDistance
	local function Within40(unit)
		if Within(unit, 4) then
			return true
		end
		LookForRangeSpells()
		local answer = SpellReaches(rangeSpells.harmful, unit)
		if answer == nil then
			answer = SpellReaches(rangeSpells.helpful, unit)
		end
		return answer
	end
	function ns.UnitInBand(unit, band)
		local within
		if band == "In11" then
			within = Within(unit, 2)
		elseif band == "In28" or band == "Past28" then
			within = Within(unit, 4)
		else
			within = Within40(unit)
		end
		if within == nil then
			return nil
		end
		if band == "Past28" or band == "Past40" then
			return not within
		end
		return within
	end

	-- A unit's rank, for the rules' elite words and the Nameplates page's
	-- Normal NPC and Elite NPC rows: "elite" (elite, rare elite or world
	-- boss) or "normal" (the rest: normal, rare, minor) for a living NPC; nil
	-- for anything else (players and their pets, totems and guardians, the
	-- dead) or when the game won't say. (Plain in retail fights, tested.)
	local ELITE_RANKS = { elite = true, rareelite = true, worldboss = true }
	local function Plain(fn, ...)
		local ok, value = pcall(fn, ...)
		if ok and not (issecretvalue and issecretvalue(value)) then return value end
	end
	function ns.NPCRank(unit)
		if not unit or Plain(UnitIsDeadOrGhost, unit) ~= false
			or Plain(UnitIsPlayer, unit) ~= false or Plain(UnitPlayerControlled, unit) ~= false then
			return nil
		end
		-- (Forever: UnitIsPlayer can say no for players; their GUID still says
		-- Player. A hunter's or warlock's pet: Pet.)
		local guid = Plain(UnitGUID, unit)
		if type(guid) == "string" and (guid:find("^Player%-") or guid:find("^Pet%-")) then
			return nil
		end
		local rank = Plain(UnitClassification, unit)
		if type(rank) ~= "string" then
			return nil
		end
		return ELITE_RANKS[rank] and "elite" or "normal"
	end
	-- (The same for an NPC you can attack; nil for the rest.)
	function ns.EnemyNPCRank(unit)
		if not unit or Plain(UnitCanAttack, "player", unit) ~= true then
			return nil
		end
		return ns.NPCRank(unit)
	end

	-- elite11, elite28, elite40: a living elite enemy within about 11, 28 or
	-- 40 yards of you, measured as near, near28 and the 40-yard bands measure your
	-- target. Only units with a plate count (the game makes them for units in
	-- view, up to its plate distance). Looked at four times a second.
	local ELITE_EVERY = 0.25
	local eliteAt, elitesNear = -math.huge, {}
	local function ElitesNear()
		local now = GetTime()
		if now - eliteAt < ELITE_EVERY then
			return elitesNear
		end
		eliteAt = now
		elitesNear[11], elitesNear[28], elitesNear[40] = false, false, false
		local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
		for _, plate in ipairs(plates) do
			local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if ns.EnemyNPCRank(unit) == "elite" then
				-- (Each band takes in the ones inside it.)
				if not elitesNear[11] and UnitWithin(unit, 2) then
					elitesNear[11], elitesNear[28], elitesNear[40] = true, true, true
				elseif not elitesNear[28] and UnitWithin(unit, 4) then
					elitesNear[28], elitesNear[40] = true, true
				elseif not elitesNear[40] and UnitWithin40(unit, true) then
					elitesNear[40] = true
				end
				if elitesNear[11] then break end
			end
		end
		return elitesNear
	end

	-- The facts for where you are now (inCombat: as the In combat column has
	-- it). Worked out once a frame (the nameplates ask for each kind).
	local facts = {}
	local factsAt, factsCombat
	function ns.RuleFacts(inCombat)
		local now = GetTime()
		inCombat = inCombat and true or false
		-- (A fight starting or ending: only while Combat Vision reads its row
		-- then, ns.combatEdge "enter" or "leave"; CineMode as the fight began.)
		local edge = ns.combatEdge
		facts.entering, facts.leaving = edge == "enter", edge == "leave"
		if edge then
			facts.cinemode = ns.combatEdgeCine and true or false
		else
			facts.cinemode = ns.lastCinematic and true or false
		end
		-- (The tooltip's kinds, while Effects asks about one: ns.tooltipKinds.)
		local tip = ns.tooltipKinds
		facts.tipenemy, facts.tipfriendly = tip and tip.tipenemy or false, tip and tip.tipfriendly or false
		facts.tipgather, facts.tipquest = tip and tip.tipgather or false, tip and tip.tipquest or false
		facts.tipother = tip and tip.tipother or false
		if factsAt == now and factsCombat == inCombat then
			return facts
		end
		factsAt, factsCombat = now, inCombat
		local place = ns.GetPlaceType()
		local hasTarget = ns.HasTarget()
		local enemy = hasTarget and ns.IsEnemyUnit("target") and not ns.Flag(UnitIsDeadOrGhost("target"))
		facts.always, facts.never = true, false
		facts.combat = inCombat and true or false
		facts.camera = ns.activeCam ~= nil -- (a camera mode running: flights, AFK, cozy and the rest)
		facts.calm = ns.InCalm and ns.InCalm() or false -- (just after a fight, till the Calm Timer runs out)
		-- (Out of combat: no fight, and the Calm Timer after one run out.)
		facts.nocombat = not facts.combat and not facts.calm
		facts.target = hasTarget and true or false
		facts.enemy = enemy and true or false
		facts.friendly = (hasTarget and not enemy) and true or false
		-- Your target by what it is: yourself, else as Effects' TargetRow has it (Effects.lua: players and NPCs, enemy, neutral or friendly; the dead friendly).
		local targetSelf = hasTarget and ns.Flag(UnitIsUnit("target", "player")) and true or false
		local row = hasTarget and not targetSelf and ns.TargetNameRow and ns.TargetNameRow("target")
		facts.targetself = targetSelf
		facts.enemyplayer, facts.hostilenpc = row == "TargetEnemyPlayer", row == "TargetEnemyNPC"
		facts.neutralplayer, facts.neutralnpc = row == "TargetNeutralPlayer", row == "TargetNeutralNPC"
		facts.friendlyplayer, facts.friendlynpc = row == "TargetFriendlyPlayer", row == "TargetFriendlyNPC"
		-- (Your target with no nameplate: behind the camera, off the side or too
		-- far. The game only makes plates for units in view; a plate CineMode
		-- fades is still there. Nameplates turned off for its kind count too.
		-- Plates can't be measured (restricted), so one pinned at the top counts as shown.)
		facts.noplate = hasTarget and not targetSelf and C_NamePlate ~= nil
			and C_NamePlate.GetNamePlateForUnit("target") == nil or false
		-- (Your target up close, where its plate goes to the top: see TargetWithin.)
		facts.near = hasTarget and not targetSelf and TargetWithin(2) or false
		facts.near28 = hasTarget and not targetSelf and TargetWithin(4) or false
		LookForRangeSpells()
		for i, band in ipairs(RANGE_BANDS) do
			facts[band.field] = hasTarget and not targetSelf and TargetInBand(i) or false
		end
		local elites = ElitesNear()
		facts.elite11, facts.elite28, facts.elite40 = elites[11], elites[28], elites[40]
		facts.bg = place == "pvp"
		-- (Apart, for rules: battlegrounds, and arenas.)
		facts.arena = facts.bg and select(2, IsInInstance()) == "arena"
		facts.battleground = facts.bg and not facts.arena
		facts.dungeon, facts.raid = place == "dungeon", place == "raid"
		facts.instance = facts.dungeon or facts.raid
		facts.city, facts.inn = place == "city", place == "inn"
		-- (The open world: not capital cities, as the grids' Cities is apart.)
		facts.world = not facts.bg and not facts.instance and not facts.city
		facts.group = ns.InGroup() and true or false
		facts.flagged = ns.IsPvPFlagged() and true or false
		facts.mounted = ns.Flag(IsMounted()) and true or false
		-- (A boss fight: an encounter on, the game's boss frames up, or a boss targeted.)
		local rank, level
		if hasTarget and enemy then
			rank, level = UnitClassification("target"), UnitLevel("target")
			if issecretvalue and (issecretvalue(rank) or issecretvalue(level)) then rank, level = nil, nil end
		end
		local encounter = _G.IsEncounterInProgress
		facts.boss = (encounter and ns.Flag(encounter())) or ns.Flag(UnitExists("boss1"))
			or rank == "worldboss" or level == -1 or false
		local role = ns.PlayerRole()
		facts.tank, facts.healer, facts.damage = role == "TANK", role == "HEALER", role == "DAMAGER"
		-- (Your class: true for its word; the others never set, so nil.)
		local _, class = UnitClass("player")
		if class then facts[class:lower()] = true end
		return facts
	end
	-- The same, in a fight only while really in one (the nameplates and unit frame parts).
	function ns.RuleFactsNow()
		return ns.RuleFacts(InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")))
	end
end

-- Frame names to show right now: only while staying cinematic and fighting
-- (in combat, or with an enemy targeted). Also returns whether the player is
-- actually in combat, since the fast fade-in only applies then.
-- Anything targeted (friend or foe).
local function HasAnyTarget()
	return ns.HasTarget()
end

-- When the player was last in combat (for "only after combat").
local lastCombatAt = -math.huge
ns.OnCalmEnd(function(cut) lastCombatAt = math.min(lastCombatAt, cut) end)
-- Whether it's just after a fight, till the Calm Timer runs out (the rules' calm).
function ns.InCalm()
	local fighting = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	return not fighting and GetTime() - lastCombatAt < (ns.db.calmTime or 0)
end

-- Casting at an enemy out of combat (Standard Frames page, "Cast fade into
-- combat"): the cast counts as the fight
-- starting, so the In combat rows fade in over the cast and are up as it
-- lands. ns.HostileCastLeft(now): seconds left of such a cast; 0 just after one
-- (or an instant one, or a channel), while it flies to the enemy and the fight
-- takes over; nil: none. (On ns: Frames.lua is at its 200 locals.)
do
	local CAST_HOLD = 1.5 -- seconds the rows stay after the cast, for it to reach the enemy
	local CAST_UNITS = { "target", "focus", "mouseover" }
	local endsAt, holdUntil = 0, 0
	local castID, cancelled
	local sentName, sentID -- (UNIT_SPELLCAST_SENT's: who the cast is aimed at)

	local function Plain(value, kind)
		return type(value) == kind and not (issecretvalue and issecretvalue(value))
	end

	-- Whether the spell is harmful; nil when the client can't say.
	local function IsHarmful(spellID)
		if not Plain(spellID, "number") then return nil end
		if C_Spell and C_Spell.IsSpellHarmful then
			local ok, harmful = pcall(C_Spell.IsSpellHarmful, spellID)
			if ok and Plain(harmful, "boolean") then return harmful end
		end
		local IsHarmfulSpell = _G.IsHarmfulSpell
		if IsHarmfulSpell and GetSpellInfo then
			local name = GetSpellInfo(spellID)
			local ok, harmful = pcall(IsHarmfulSpell, name)
			if ok and not (issecretvalue and issecretvalue(harmful)) then return harmful and true or false end
		end
		return nil
	end

	-- Whether this cast is at a living enemy: the unit SENT named (target,
	-- focus or mouseover), or with no name (aimed at the ground) the target.
	local function AtEnemy(spellID, castGUID)
		local harmful = IsHarmful(spellID)
		if harmful == false then return false end
		local name = castGUID == sentID and sentName or nil
		for _, unit in ipairs(CAST_UNITS) do
			if (name or unit == "target") and ns.IsEnemyUnit(unit) and not ns.Flag(UnitIsDeadOrGhost(unit)) then
				if not name then return true end
				local short, full = UnitName(unit), _G.GetUnitName and _G.GetUnitName(unit, true)
				if (Plain(short, "string") and short == name) or (Plain(full, "string") and full == name) then
					return true
				end
			end
		end
		return false
	end

	local function Report(text)
		if ns.castDebug then ns.Print("hostile cast: " .. text) end
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
	watcher:SetScript("OnEvent", function(_, event, _, a, b)
		if not (ns.db and ns.db.fadeInOnHostileCast) then return end
		if event == "UNIT_SPELLCAST_SENT" then
			-- (unit, target name, castGUID, spellID)
			sentName = Plain(a, "string") and a ~= "" and a or nil
			sentID = b
			return
		end
		-- (unit, castGUID, spellID)
		local castGUID, spellID = a, b
		local now = GetTime()
		if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
			if event == "UNIT_SPELLCAST_START" then
				castID, cancelled, endsAt = nil, false, 0
				if not AtEnemy(spellID, castGUID) then return end
				castID = castGUID
			elseif castGUID ~= castID then
				return
			end
			local ok, _, _, _, startMS, endMS = pcall(UnitCastingInfo, "player")
			if ok and Plain(endMS, "number") and Plain(startMS, "number") then
				endsAt = endMS / 1000
				Report(("%s, %.1f sec, fading in over %.1f sec"):format(tostring(spellID),
					(endMS - startMS) / 1000, math.max(0, endsAt - now)))
			end
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
			if AtEnemy(spellID, castGUID) then
				castID, endsAt, holdUntil = nil, 0, now + CAST_HOLD
				Report(tostring(spellID) .. ", channelled")
			end
		elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
			if castGUID == castID then
				cancelled, endsAt, holdUntil = true, 0, 0
				Report("stopped short")
			end
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_STOP" then
			if castGUID == castID then
				if not cancelled then
					endsAt, holdUntil = 0, now + CAST_HOLD
				end
				if event == "UNIT_SPELLCAST_SUCCEEDED" then castID = nil end
			elseif event == "UNIT_SPELLCAST_SUCCEEDED" and AtEnemy(spellID, castGUID) then
				holdUntil = now + CAST_HOLD
				Report(tostring(spellID) .. ", instant")
			end
		end
	end)

	function ns.HostileCastLeft(now)
		if not ns.db.fadeInOnHostileCast then return nil end
		if endsAt > now then return endsAt - now end
		-- (A moment past its end before the events come in counts as just after.)
		if holdUntil > now or (endsAt > 0 and now < endsAt + 0.5) then return 0 end
		return nil
	end
end

-- Frame names to show right now, from the Standard Frames page's column that
-- applies: In combat (while staying cinematic, and with combatShowCalm on
-- until the Calm Timer has run out after the fight), Tar Enemy (out of combat
-- with a living enemy targeted) or Tar Friendly (anything else targeted:
-- friends, NPCs, dead enemies).
-- Rows with Always ticked are always in it: they don't fade in CineMode at all.
-- Rows with a Calm Timer option of their own on their page: their In combat
-- tick lasts until the Calm Timer runs out even with combatShowCalm off. And
-- each row's own Calm Timer tick (ns.IsCalmShowOn): its In combat tick lasts
-- till then, the target columns counting meanwhile.
local GetCombatShownFrames
do
	local CALM_ROW_SETTING = { quests = "questCombatCalm" }
	-- Whether a row is ticked in one of the place columns that apply here.
	-- (Kept out of GetCombatShownFrames: a closure made each tick was garbage.)
	local function KeptHere(placeLists, key)
		for _, list in ipairs(placeLists) do
			if IsListOn(list, key, PlaceDefaults(list)) then
				return true
			end
		end
		return false
	end
	-- (Casting at an enemy: the In combat rows and the target's column's.
	-- Not a closure for the same reason.)
	local targetIsOn
	local function CastIsOn(key)
		return ns.IsCombatShowOn(key) or (targetIsOn and targetIsOn(key))
	end
	function GetCombatShownFrames()
		local fighting = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
		local calm = not fighting and GetTime() - lastCombatAt < (ns.db.calmTime or 0)
		-- (The rules' combat as it always was; the ticks' just the fight, each
		-- row's Calm Timer tick keeping it after.)
		local inCombat = fighting or (calm and ns.db.combatShowCalm)
		local isOn
		if fighting then
			if ns.db.stayInCombat then
				isOn = ns.IsCombatShowOn
			end
		elseif HasAnyTarget() then
			if ns.IsEnemyUnit("target") and not ns.Flag(UnitIsDeadOrGhost("target")) then
				isOn = ns.IsEnemyShowOn
			else
				isOn = ns.IsFriendlyShowOn
			end
		end
		-- (Casting at an enemy: the In combat rows as well, see ns.HostileCastLeft.)
		if not fighting and ns.db.stayInCombat and ns.HostileCastLeft(GetTime()) then
			targetIsOn = isOn
			isOn = CastIsOn
		end
		-- (And the rows ticked for where you are.)
		local placeLists = PlaceListsHere()
		local shown = wipe(tickTables.combatShown)
		-- Rows for gamepad mode only, and the ones they stand in for then.
		local gamepad = ns.IsGamePadOn()
		local facts = ns.RuleFacts(inCombat)
		-- The rows kept hidden while you're the role you are (their roles buttons), ticks or rule.
		local roleHide = ns.RoleHides(facts)
		for _, item in ipairs(ns.COMBAT_SHOW) do
			local applies = not (gamepad and item.notGamepad) and not (item.gamepadOnly and not gamepad)
			local calmRow = calm and ns.db.stayInCombat and (ns.IsCalmShowOn(item.key)
				or ns.IsCombatShowOn(item.key) and ns.db[CALM_ROW_SETTING[item.key] or ""] and ns.PageOn("handleQuests"))
			-- (A row's rule, when it has one that reads, decides instead of its ticks.)
			local ticked = ns.RuleShows(item.key, facts)
			if ticked == nil then
				ticked = ns.IsCineShowOn(item.key) or KeptHere(placeLists, item.key) or (isOn and isOn(item.key))
					or calmRow
			end
			if roleHide[item.key] then ticked = false end
			-- (Your bars held back at a fight's start, Personal Resources page:
			-- up only where Always or a place keeps them.)
			if ticked and (fighting or isOn == CastIsOn) and ns.FightHold(item.key)
				and not (ns.IsCineShowOn(item.key) or KeptHere(placeLists, item.key)) then
				ticked = false
			end
			if applies and ticked then
				for _, name in ipairs(item.frames or NO_DEFAULTS) do
					shown[name] = true
				end
				for _, group in ipairs(item.groups or NO_DEFAULTS) do
					shown[GROUP_KEY[group]] = true
				end
			end
		end
		-- Added frames, by their rows on the Advanced Frames page.
		for name in pairs(ns.db.extraFrames) do
			local key = "extra:" .. name
			local ticked = ns.RuleShows(key, facts)
			if ticked == nil then
				ticked = KeptHere(placeLists, key) or (isOn and isOn(key))
					or (calm and ns.db.stayInCombat and ns.IsCalmShowOn(key))
			end
			ticked = ticked and not roleHide[key]
			if ticked then
				shown[GROUP_KEY[key]] = true
			end
		end
		return shown
	end

	-- Whether a grid row that isn't a frame (the Chat page's: a message type,
	-- a channel; Chat bubbles', tooltips', Visual Effects', music's, Camera
	-- Modes') is on now, as a Standard Frames row would show: its rule if it
	-- has one, else Always (always: its own setting, when it has one), a place
	-- that applies here, In a camera mode, In combat / Out of combat, or Tar
	-- Enemy / Tar Friendly; never while you're a role its roles button has
	-- unticked. anyFight: In combat counts in any fight (else only while
	-- CineMode stays on in them).
	function ns.RowOnNow(key, always, anyFight)
		local fighting = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
		local calm = not fighting and GetTime() - lastCombatAt < (ns.db.calmTime or 0)
		local inCombat = fighting or (calm and ns.db.combatShowCalm)
		local facts = ns.RuleFacts(inCombat)
		if ns.RoleHides(facts)[key] then
			return false
		end
		local ticked = ns.RuleShows(key, facts)
		if ticked ~= nil then
			return ticked
		end
		if always == nil then
			always = ns.IsCineShowOn(key)
		end
		if always or KeptHere(PlaceListsHere(), key) then
			return true
		end
		if ns.IsCamShowOn(key) and facts.camera then
			return true
		end
		-- (In combat counts while CineMode stays on in fights, for the rows of
		-- the UI; anyFight: any fight, for the rest.)
		local stays = anyFight or ns.db.stayInCombat
		-- (Three times, each its own tick: the fight, the Calm Timer after it,
		-- and the rest, Out of combat.)
		if fighting then
			return stays and ns.IsCombatShowOn(key) and true or false
		end
		if calm then
			if ns.IsCalmShowOn(key) then return true end
		elseif ns.IsQuietShowOn(key) then
			return true
		end
		if HasAnyTarget() then
			if ns.IsEnemyUnit("target") and not ns.Flag(UnitIsDeadOrGhost("target")) then
				return ns.IsEnemyShowOn(key) and true or false
			end
			return ns.IsFriendlyShowOn(key) and true or false
		end
		return false
	end
end
GetCombatShownFrames = ns.Profiled("GetCombatShownFrames", GetCombatShownFrames)

-- Power types that sit empty at rest (rage, runic power, Insanity, Maelstrom,
-- Astral Power, Fury, Pain) don't count: leftover rage draining after a fight
-- isn't recovering, so only health matters.
local EMPTY_AT_REST = { RAGE = true, RUNIC_POWER = true, INSANITY = true, MAELSTROM = true,
	LUNAR_POWER = true, FURY = true, PAIN = true }
ns.EMPTY_AT_REST = EMPTY_AT_REST -- (Personal Resources: drained after a fight)

local function IsSecretValue(value)
	return issecretvalue and issecretvalue(value) or false
end

-- Does the player's power count toward recovery? (Yes when unsure.)
local function PowerCounts()
	local _, powerToken = UnitPowerType("player")
	return IsSecretValue(powerToken) or not EMPTY_AT_REST[powerToken]
end

-- Is the player's health or power not at its resting level? Where the values
-- can be read, compare them directly. This client hides current health and
-- power as secret values (even out of combat), so otherwise fall back on the
-- change events: they keep firing every couple of seconds while health or
-- power regenerates (or rage drains) and stop once it's back at rest. The
-- window covers mana's 5-second pause in regeneration after a cast; with no
-- cast that recent, ticks come every 2 seconds, so a shorter wait will do and
-- the portrait starts fading soon after you're full.
local RECOVERY_WINDOW = 6
local TICK_WINDOW = 3
local CAST_PAUSE = 5
local lastVitalsChange = 0
local lastCastAt = -math.huge

-- Fall damage brings the portrait up like a fight does. Health changing while
-- falling or just after landing (the damage arrives a moment later) counts.
local FALL_LANDING_GRACE = 1
local lastFallingAt = -math.huge
local lastFallDamageAt = -math.huge

-- Coming back to life does too, until health and power are full (however
-- long that takes).
local resurrectRecovering = false
do
	local resurrectWatcher = CreateFrame("Frame")
	resurrectWatcher:RegisterEvent("PLAYER_ALIVE") -- (also as you release to a ghost)
	resurrectWatcher:RegisterEvent("PLAYER_UNGHOST")
	resurrectWatcher:SetScript("OnEvent", function()
		if not ns.Flag(UnitIsDeadOrGhost("player")) then
			resurrectRecovering = true
		end
	end)
end

-- Buff peek: a new or refreshed buff/debuff briefly shows the buffs group.
-- UNIT_AURA says what changed (added, updated, removed) without needing the
-- aura details, which may be secret. Removals and the full refresh at login or
-- zoning don't count. Clients that don't say what changed count every change.
local buffPeekUntil = 0
-- A debuff peek: just the debuffs, and a fight starting doesn't clear it
-- (the hit that puts a debuff on you is often the one that starts the fight).
-- (In ns, not locals: Frames.lua is at the 200-local cap.)
ns.debuffPeekUntil = 0
-- How many debuffs you had at the last aura change (nil: unknown), to spot a
-- new one in a fight, when what changed is secret: ns.debuffCount.
-- A debuff brought them up with debuffPeekUntilGone: held until you have no
-- debuffs left (bar ignored ones).
local debuffHeld = false

local COMBAT_END_AURA_GRACE = 1 -- seconds after a fight its aura changes don't bring the buffs up

-- In combat the update details are secret: lists can't be looked into and the
-- flag can't be tested. A secret list is still present (so something was
-- added or refreshed); a secret flag counts as "not a full refresh".
local function HasEntries(list)
	if issecretvalue and issecretvalue(list) then
		return true
	end
	local ok, hasAny = pcall(function() return list ~= nil and next(list) ~= nil end)
	return ok and hasAny
end

local function IsFullUpdate(flag)
	if issecretvalue and issecretvalue(flag) then
		return false
	end
	return flag == true
end

-- Flights don't peek at buffs: nothing gained on the way matters, and landing
-- adds Honorless Target. So no peek on a flight or just after landing, and
-- Honorless Target never counts.
-- Buffs that never bring the buffs up: the player's list (buffPeekIgnore), spell
-- IDs or names (names match your game language), parsed when it changes.
local ignoredIDs, ignoredNames, ignoredFrom = {}, {}, nil
local function IgnoreLists()
	local text = ns.db.buffPeekIgnore or ""
	if text ~= ignoredFrom then
		ignoredIDs, ignoredNames, ignoredFrom = {}, {}, text
		for entry in text:gmatch("[^,]+") do
			entry = entry:match("^%s*(.-)%s*$")
			local id = tonumber(entry)
			if id then
				ignoredIDs[id] = true
			elseif entry ~= "" then
				ignoredNames[entry:lower()] = true
			end
		end
	end
	return ignoredIDs, ignoredNames
end
local LANDING_QUIET = 5 -- seconds after landing with no buff peek
local landedQuietUntil = 0

-- Called by the flight code on landing.
function ns.OnLandedForBuffs()
	landedQuietUntil = GetTime() + LANDING_QUIET
end

-- One aura's data: on the ignore list? (False when unsure, e.g. secret values.)
local function IsIgnoredAura(aura)
	if type(aura) ~= "table" then
		return false
	end
	local id, name = aura.spellId, aura.name
	if issecretvalue and (issecretvalue(id) or issecretvalue(name)) then
		return false
	end
	local ids, names = IgnoreLists()
	return ids[id] or (type(name) == "string" and names[name:lower()]) or false
end

-- One aura's data: lasting longer than buffPeekLongMinutes, with
-- buffPeekIgnoreLong? (Its full time, not what's left. False when unsure, or
-- for ones with no time at all.)
function ns.IsLongAura(aura)
	if type(aura) ~= "table" or not ns.db.buffPeekIgnoreLong then
		return false
	end
	local duration = aura.duration
	if type(duration) ~= "number" or (issecretvalue and issecretvalue(duration)) then
		return false
	end
	return duration > (ns.db.buffPeekLongMinutes or 30) * 60
end

-- A buff you cast on yourself (buffPeekIgnoreSelf passes these over): its
-- caster is you or your pet. (False when unsure: no data, or a secret caster.)
local function IsSelfCast(aura)
	if type(aura) ~= "table" then
		return false
	end
	local source = aura.sourceUnit
	if source == nil or (issecretvalue and issecretvalue(source)) then
		return false
	end
	for _, unit in ipairs({ "player", "pet" }) do
		local ok, mine = pcall(UnitIsUnit, source, unit)
		if ok and mine == true then
			return true
		end
	end
	return false
end

-- Buffs and debuffs each bring the buffs up on their own switch (buffPeek,
-- debuffPeek), each with its own "Only after combat" (within the Calm Timer).
local function PeekAllowed(harmful)
	local prefix = harmful and "debuffPeek" or "buffPeek"
	if not ns.db[prefix] then
		return false
	end
	return not (ns.db[prefix .. "AfterCombat"] and GetTime() - lastCombatAt > ns.db.calmTime)
end

-- How long a peek of this kind holds the buffs up (buffPeekTime,
-- debuffPeekTime), or nil when its kind doesn't bring them up.
local function PeekHold(harmful)
	if PeekAllowed(harmful) then
		return ns.HoldTime(harmful and "debuffPeekTime" or "buffPeekTime")
	end
end

-- The longer of the two kinds' holds, for when it's unclear which kind it was.
local function EitherHold()
	local buff, debuff = PeekHold(false), PeekHold(true)
	if buff and debuff then
		return math.max(buff, debuff)
	end
	return buff or debuff
end

-- A debuff peek for this long (debuffPeekTime by default), and held until
-- your debuffs are gone with debuffPeekUntilGone.
function ns.StartDebuffPeek(hold)
	ns.debuffPeekUntil = math.max(ns.debuffPeekUntil, GetTime() + (hold or ns.HoldTime("debuffPeekTime")))
	if ns.db.debuffPeekUntilGone then
		debuffHeld = true
	end
end

-- One aura gained or refreshed: how long it brings the buffs up, or nil. Not
-- at all if it's on the ignore list, or a buff you cast on yourself with
-- buffPeekIgnoreSelf; otherwise as its kind allows. When unsure (no data,
-- secret values), either kind will do.
local function AuraHold(aura)
	if IsIgnoredAura(aura) or ns.IsLongAura(aura) then
		return nil
	end
	local harmful = type(aura) == "table" and aura.isHarmful
	if harmful == nil or (issecretvalue and issecretvalue(harmful)) then
		return EitherHold()
	end
	if not harmful and ns.db.buffPeekIgnoreSelf and IsSelfCast(aura) then
		return nil
	end
	local hold = PeekHold(harmful and true or false)
	-- (A debuff's is a peek of its own, at just the debuffs.)
	if hold and harmful then
		ns.StartDebuffPeek(hold)
		return nil
	end
	return hold
end

-- Any debuff on you that isn't on the ignore list? (Yes when unsure: secret
-- values. The fight clears the hold anyway.)
local function HasDebuff()
	for i = 1, 40 do
		local aura
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			-- (Errors rather than returning nil while auras are secret.)
			local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
			if not ok or (issecretvalue and issecretvalue(data)) then
				-- (Secret, as in a fight: whether the game's debuff frame shows any.)
				local icons = ns.DebuffIconCount()
				return icons == nil or icons > 0
			end
			aura = data
		elseif UnitDebuff then
			local values = { UnitDebuff("player", i) }
			aura = values[1] and { name = values[1], duration = values[5], spellId = values[10] }
		end
		if not aura then
			return false
		end
		if (issecretvalue and issecretvalue(aura.name)) or not (IsIgnoredAura(aura) or ns.IsLongAura(aura)) then
			return true
		end
	end
	return false
end

-- How many debuffs are on you, or nil when that can't be told. (The count
-- isn't secret in fights, even where the debuffs are.)
function ns.DebuffCount()
	if C_UnitAuras and C_UnitAuras.GetAuraSlots then
		local ok, count = pcall(function()
			-- (The first value is the continuation token, not a slot.)
			return select("#", C_UnitAuras.GetAuraSlots("player", "HARMFUL")) - 1
		end)
		return ok and count or nil
	elseif UnitDebuff then
		local count = 0
		while UnitDebuff("player", count + 1) do
			count = count + 1
		end
		return count
	end
end

-- Where that count can't be had (retail in a fight), the game's own debuff
-- frame is asked instead: the list of auras it draws (DebuffFrame.auraInfo),
-- else its shown icons that hold an aura (buttonInfo), or DebuffButton1... on
-- older clients. Nil when there's none of these.
function ns.DebuffIconCount()
	local count = 0
	local function Shown(frame)
		local ok, shown = pcall(function() return not IsForbidden(frame) and ns.Flag(frame:IsShown()) end)
		return ok and shown
	end
	local function Look(depth, ...)
		for i = 1, select("#", ...) do
			local child = select(i, ...)
			if Shown(child) then
				if child.buttonInfo then
					count = count + 1
				elseif depth > 1 then
					Look(depth - 1, child:GetChildren())
				end
			end
		end
	end
	local frame = _G.DebuffFrame
	local ok, listed = pcall(function() return type(frame.auraInfo) == "table" and #frame.auraInfo end)
	if ok and type(listed) == "number" then
		return listed
	elseif frame and frame.GetChildren then
		Look(3, frame:GetChildren())
		return count
	elseif _G.DebuffButton1 then
		for i = 1, 40 do
			local button = _G["DebuffButton" .. i]
			if not button then break end
			if Shown(button) then count = count + 1 end
		end
		return count
	end
end

-- Counts the debuff icons a frame from now (once the game has drawn the
-- change), noting the count; with peek, one more than before starts a
-- fight's debuff peek.
function ns.CheckDebuffIcons(peek)
	C_Timer.After(0, function()
		local icons = ns.DebuffIconCount()
		if peek and icons and ns.debuffIcons and icons > ns.debuffIcons then
			ns.StartDebuffPeek()
		end
		-- (The last one gone: the hold lets go. The game's frame has caught up
		-- by now, which it may not have at the aura change itself.)
		if icons == 0 then
			debuffHeld = false
		end
		if ns.auraDebug then
			ns.Print(("debuff icons %s -> %s%s"):format(tostring(ns.debuffIcons), tostring(icons),
				peek and "" or " (not peeking)"))
		end
		ns.debuffIcons = icons
	end)
end

-- The longest hold of any aura gained or refreshed, or nil. Updates (a stack
-- ticking up, say) only give instance IDs, so each is looked up. Either kind
-- when unsure.
local function AnyAuraHold(updateInfo)
	local ok, hold = pcall(function()
		local longest
		local function Consider(seconds)
			if seconds and (not longest or seconds > longest) then
				longest = seconds
			end
		end
		local added, updated = updateInfo.addedAuras, updateInfo.updatedAuraInstanceIDs
		if HasEntries(added) then
			if issecretvalue and issecretvalue(added) then
				return AuraHold(nil)
			end
			for _, aura in pairs(added) do
				Consider(AuraHold(aura))
			end
		end
		if HasEntries(updated) then
			if (issecretvalue and issecretvalue(updated))
				or not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
				return AuraHold(nil)
			end
			for _, instanceID in pairs(updated) do
				Consider(AuraHold(C_UnitAuras.GetAuraDataByAuraInstanceID("player", instanceID)))
			end
		end
		return longest
	end)
	if not ok then
		return EitherHold()
	end
	return hold
end

do
	local auraWatcher = CreateFrame("Frame")
	auraWatcher:RegisterUnitEvent("UNIT_AURA", "player")
	auraWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	auraWatcher:SetScript("OnEvent", ns.Profiled("UNIT_AURA (peeks)", function(_, event, isLogin, updateInfo)
		-- Logging in or a /reload with a debuff already on you (a zone's, say):
		-- with debuffPeekUntilGone the hold picks up where it was, since nothing
		-- will be gained to start it. (updateInfo here: PLAYER_ENTERING_WORLD's
		-- isReloadingUi.)
		if event == "PLAYER_ENTERING_WORLD" then
			if isLogin or updateInfo then
				C_Timer.After(0, function()
					if ns.db and ns.db.debuffPeekUntilGone and PeekAllowed(true) and HasDebuff() then
						debuffHeld = true
					end
				end)
			end
			return
		end
		-- (Removals count here: the last debuff going lets them fade.)
		if debuffHeld and not (ns.db and ns.db.debuffPeekUntilGone and HasDebuff()) then
			debuffHeld = false
		end
		if not (ns.db and (PeekAllowed(false) or PeekAllowed(true))) then
			return
		end
		local count = PeekAllowed(true) and ns.DebuffCount() or nil
		local gainedDebuff = count and ns.debuffCount and count > ns.debuffCount
		if ns.auraDebug then
			ns.Print(("aura change: in combat %s, debuffs %s -> %s, details %s"):format(
				tostring(InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))), tostring(ns.debuffCount),
				tostring(count), type(updateInfo) ~= "table" and "none"
					or (issecretvalue and issecretvalue(updateInfo.addedAuras)) and "secret" or "readable"))
		end
		ns.debuffCount = count
		-- In a fight buffs don't peek: they'd hold the buffs up past its end
		-- (leaving combat, they fade with the rest of the UI at the usual fade
		-- out time). Nor auras the fight's end itself changes, in the moment
		-- after it. A new debuff in a fight still does (the fight's own frames
		-- may not show the buffs, as in Pure Cinema): what it is is secret then,
		-- so one more debuff than before counts, ignore list and all (not with
		-- "Only after combat").
		local inFight = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
			or GetTime() - lastCombatAt < COMBAT_END_AURA_GRACE
		local fightPeeks = inFight and not ns.db.debuffPeekAfterCombat and not ns.OnTaxi()
		-- (No count, as on retail in a fight: the game's debuff icons, kept
		-- counted out of fights too, to compare with.)
		if PeekAllowed(true) then
			ns.CheckDebuffIcons(count == nil and fightPeeks)
		end
		if inFight then
			if gainedDebuff and fightPeeks then
				ns.StartDebuffPeek()
			end
			return
		end
		-- (wasOnTaxi: landed this instant, before the flight code has noticed.)
		if ns.OnTaxi() or ns.wasOnTaxi or GetTime() < landedQuietUntil then
			return
		end
		local hold
		if type(updateInfo) == "table" then
			hold = not IsFullUpdate(updateInfo.isFullUpdate) and AnyAuraHold(updateInfo)
		else
			hold = EitherHold()
		end
		if hold then
			-- (a short buff peek doesn't cut a longer debuff one short)
			buffPeekUntil = math.max(buffPeekUntil, GetTime() + hold)
		end
	end))
end

do
	local vitalsWatcher = CreateFrame("Frame")
	vitalsWatcher:RegisterUnitEvent("UNIT_HEALTH", "player")
	vitalsWatcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	vitalsWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	vitalsWatcher:SetScript("OnEvent", ns.Profiled("Health/power events", function(_, event)
		local now = GetTime()
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			lastCastAt = now
			return
		end
		if event == "UNIT_POWER_UPDATE" and not PowerCounts() then
			return
		end
		if event == "UNIT_HEALTH" and (ns.Flag(IsFalling()) or now - lastFallingAt <= FALL_LANDING_GRACE) then
			lastFallDamageAt = now
		end
		lastVitalsChange = now
	end))
end

local function IsPlayerRecovering()
	local health, maxHealth = UnitHealth("player"), UnitHealthMax("player")
	local countPower = PowerCounts()
	local power, maxPower = UnitPower("player"), UnitPowerMax("player")
	if IsSecretValue(health) or IsSecretValue(maxHealth)
		or (countPower and (IsSecretValue(power) or IsSecretValue(maxPower))) then
		local now = GetTime()
		local window = now - lastCastAt < CAST_PAUSE + TICK_WINDOW and RECOVERY_WINDOW or TICK_WINDOW
		return now - lastVitalsChange < window
	end
	if maxHealth > 0 and health < maxHealth then
		return true
	end
	return countPower and maxPower > 0 and power < maxPower
end

ns.IsPlayerRecovering = IsPlayerRecovering

-- Is your pet's health not back to full? (No pet, or a dead one: no.) Secret
-- health falls back on its health events, as for the player.
do
	local lastPetHealthChange = -math.huge
	local petWatcher = CreateFrame("Frame")
	petWatcher:RegisterUnitEvent("UNIT_HEALTH", "pet")
	petWatcher:SetScript("OnEvent", function() lastPetHealthChange = GetTime() end)
	function ns.IsPetRecovering()
		if not ns.Flag(UnitExists("pet")) or ns.Flag(UnitIsDeadOrGhost("pet")) then
			return false
		end
		local health, maxHealth = UnitHealth("pet"), UnitHealthMax("pet")
		if IsSecretValue(health) or IsSecretValue(maxHealth) then
			return GetTime() - lastPetHealthChange < TICK_WINDOW
		end
		return maxHealth > 0 and health < maxHealth
	end
end

-- For the log (Exit Calm Timer when Healthy): which of your health, power and
-- pet's health could be read, and which were secret (judged by their events).
function ns.VitalsReadout()
	local function Read(value, maxValue)
		return (IsSecretValue(value) or IsSecretValue(maxValue)) and "secret" or "readable"
	end
	local _, powerToken = UnitPowerType("player")
	local power = PowerCounts() and Read(UnitPower("player"), UnitPowerMax("player")) or "not counted"
	local pet = "none"
	if ns.Flag(UnitExists("pet")) then
		pet = ns.Flag(UnitIsDeadOrGhost("pet")) and "dead" or Read(UnitHealth("pet"), UnitHealthMax("pet"))
	end
	return ("health %s, power %s (%s), pet health %s"):format(Read(UnitHealth("player"), UnitHealthMax("player")),
		power, IsSecretValue(powerToken) and "secret" or tostring(powerToken), pet)
end
ns.GetSecondsSinceVitalsChange = function() return GetTime() - lastVitalsChange end

local hoverHeldUntil = {} -- [row key] = when the mouse's hold on it ends (Mouseover groups)

-- Accepting a quest, or progress on one's objectives, brings the quest
-- tracker up as a mouseover would: it fades in, then is gone the quest
-- tracker's mouseover time later (or the Calm Timer, if longer, with that
-- reveal's Calm setting ticked).
local questRevealUntil = 0
do
	local QUEST_REVEAL_EVENTS = { QUEST_ACCEPTED = "questRevealOnAccept", QUEST_WATCH_UPDATE = "questRevealOnProgress" }
	local QUEST_REVEAL_CALM = { questRevealOnAccept = "questAcceptCalm", questRevealOnProgress = "questProgressCalm",
		questRevealOnScenario = "questScenarioCalm" }
	local questWatcher = CreateFrame("Frame")
	for event in pairs(QUEST_REVEAL_EVENTS) do
		pcall(questWatcher.RegisterEvent, questWatcher, event)
	end
	-- "Show just that quest" (Quest tracker page): a reveal (a quest accepted
	-- or its objectives moving on) that brings the tracker up from hidden shows
	-- just that quest (more join while it's up); the rest of the tracker's
	-- quests, every header (the tracker's own and its sections') and its
	-- background stay faded. They keep their place, so there can be a gap
	-- above. Hovering the tracker or a fight bringing it up shows the lot for
	-- the rest of that reveal. (Retail-style tracker: sections with
	-- usedBlocks, keyed by quest ID.) Scenario progress focuses the scenario
	-- section the same way, key SCENARIO: its header, stage and objectives.
	local focus = { on = false, quests = {}, since = 0, othersAlpha = 1 }
	local SCENARIO = "scenario"
	local function IsScenarioSection(section)
		return section == _G.ScenarioObjectiveTracker or type(section.StageBlock) == "table"
	end
	local FOCUS_FIND_TIME = 0.5 -- none of its quests found in the tracker by then: show the lot
	local function TrackerSections(tracker)
		if type(tracker.modules) == "table" then
			return tracker.modules
		end
		return { tracker:GetChildren() }
	end
	-- Fades every quest not in focus.quests, the headers and the background
	-- to alpha; true if any focused quest has a block in the tracker. (Relative
	-- to their own alpha: the background's is Edit Mode's opacity.)
	local blockAlphas = {} -- [block] = the alpha it's faded to, for its bars and buttons
	local BAR_KINDS = { "usedProgressBars", "usedTimerBars" }
	-- The block a quest's item or group finder button belongs to: those sit
	-- at the block's right edge, anchored to it (or to the button before),
	-- but aren't its children. Nil for anything else.
	local function AnchorBlock(frame)
		for _ = 1, 4 do
			if not (frame.GetPoint and frame:GetNumPoints() > 0) then
				return nil
			end
			local ok, _, relativeTo = pcall(frame.GetPoint, frame, 1)
			if not ok or type(relativeTo) ~= "table" or IsForbidden(relativeTo) then
				return nil
			end
			if blockAlphas[relativeTo] then
				return relativeTo
			end
			local parent = relativeTo.GetParent and relativeTo:GetParent()
			if parent and blockAlphas[parent] then
				return parent
			end
			frame = relativeTo
		end
	end
	local function FadeEdgeButtons(holder)
		if type(holder) ~= "table" or not holder.GetChildren or IsForbidden(holder) then
			return
		end
		for _, child in ipairs({ holder:GetChildren() }) do
			if not blockAlphas[child] and child.SetAlpha and not IsForbidden(child) then
				local block = AnchorBlock(child)
				if block then
					ns.FadeRelative(child, blockAlphas[block])
				end
			end
		end
	end
	local function ApplyFocus(tracker, alpha, timers)
		local found = false
		wipe(blockAlphas)
		for _, section in ipairs(TrackerSections(tracker)) do
			if type(section) == "table" and type(section.usedBlocks) == "table" and not IsForbidden(section) then
				local sectionHas = false
				local scenarioSection = IsScenarioSection(section)
				local sectionAlpha = alpha
				if scenarioSection then
					-- (Its stage and other blocks aren't all in usedBlocks.)
					sectionHas = (focus.quests[SCENARIO] or timers and timers[SCENARIO]) and true or false
					sectionAlpha = sectionHas and 1 or alpha
					for _, child in ipairs({ section:GetChildren() }) do
						if child.SetAlpha and not IsForbidden(child) then
							ns.FadeRelative(child, sectionAlpha)
						end
					end
				end
				for _, blocks in pairs(section.usedBlocks) do
					if type(blocks) == "table" then
						for id, block in pairs(blocks) do
							if type(block) == "table" and block.SetAlpha and not IsForbidden(block) then
								local blockAlpha = alpha
								if scenarioSection then
									blockAlpha = sectionAlpha
								elseif focus.quests[id] or timers and timers[id] then
									sectionHas = true
									blockAlpha = 1
								end
								blockAlphas[block] = blockAlpha
								ns.FadeRelative(block, blockAlpha)
							end
						end
					end
				end
				-- A quest's progress and timer bars aren't its block's children
				-- (the section's): keyed by their objective line, whose parent is
				-- the block.
				for _, kind in ipairs(BAR_KINDS) do
					local bars = section[kind]
					if type(bars) == "table" then
						for line, bar in pairs(bars) do
							if type(bar) == "table" and bar.SetAlpha and not IsForbidden(bar) then
								local owner = type(line) == "table" and line.GetParent and not IsForbidden(line)
									and line:GetParent()
								ns.FadeRelative(bar, owner and blockAlphas[owner] or sectionAlpha)
							end
						end
					end
				end
				if not scenarioSection then
					FadeEdgeButtons(section)
					FadeEdgeButtons(section.ContentsFrame)
				end
				found = found or sectionHas
				local header = section.Header
				if type(header) == "table" and header.SetAlpha and not IsForbidden(header) then
					ns.FadeRelative(header, sectionAlpha)
				end
			end
		end
		FadeEdgeButtons(tracker) -- (in case the game parents them to the tracker)
		for _, part in ipairs({ tracker.Header, tracker.NineSlice }) do
			if type(part) == "table" and part.SetAlpha and not IsForbidden(part) then
				ns.FadeRelative(part, alpha)
			end
		end
		return found
	end
	local function Focus(questID)
		if not (ns.db and ns.db.questRevealOnlyThat and (type(questID) == "number" or questID == SCENARIO)) then
			focus.on = false
			return
		end
		local entry = focus.entry
		if focus.on and (questRevealUntil > GetTime() or (entry and entry.alpha > 0)) then
			focus.quests[questID] = true
		elseif entry and (entry.alpha == 0 or focus.timers) then -- (up for just a timer: still focus)
			focus.on, focus.since = true, GetTime()
			wipe(focus.quests)
			focus.quests[questID] = true
		else
			focus.on = false -- (up already for something else: all of it stays)
		end
	end
	-- A timer counting down in a retail-style tracker (Show the quest timer
	-- while one is running): the scenario's (a header timer like an assault's
	-- "Deploy Defenses 01:14", a dungeon's or Proving Grounds' clock, a timed
	-- objective's bar), keyed SCENARIO, or a quest's timer bar, keyed by its
	-- quest. Nil with none. Looked at twice a second.
	local timerKeys, timerCheckedAt, timerAny = {}, -math.huge, false
	local TIMER_CHECK = 0.5
	local function HeaderTimerUp(section)
		local widgets = C_UIWidgetManager
		local timerType = Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.ScenarioHeaderTimer
		if not (timerType and widgets) then
			return false
		end
		local container = type(section.StageBlock) == "table" and section.StageBlock.WidgetContainer
		if type(container) == "table" and type(container.widgetFrames) == "table" then
			for _, widget in pairs(container.widgetFrames) do
				if type(widget) == "table" and widget.widgetType == timerType and widget.IsShown
					and not IsForbidden(widget) and ns.Flag(widget:IsShown()) then
					return true
				end
			end
		end
		local step = C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo and C_ScenarioInfo.GetScenarioStepInfo()
		local setID = step and step.widgetSetID
		if type(setID) ~= "number" or IsSecretValue(setID) or setID == 0
			or not (widgets.GetAllWidgetsBySetID and widgets.GetScenarioHeaderTimerWidgetVisualizationInfo) then
			return false
		end
		for _, widget in ipairs(widgets.GetAllWidgetsBySetID(setID) or {}) do
			if widget.widgetType == timerType then
				local info = widgets.GetScenarioHeaderTimerWidgetVisualizationInfo(widget.widgetID)
				local shown = info and info.shownState
				if type(shown) == "number" and not IsSecretValue(shown) and shown ~= 0 then
					return true
				end
			end
		end
		return false
	end
	local function ClockUp()
		if not (GetWorldElapsedTimers and GetWorldElapsedTime) then
			return false
		end
		for _, id in ipairs({ GetWorldElapsedTimers() }) do
			local _, _, kind = GetWorldElapsedTime(id)
			if type(kind) == "number" and not IsSecretValue(kind) and kind ~= 0 then
				return true
			end
		end
		return false
	end
	local function TrackerTimers(tracker)
		local now = GetTime()
		if now - timerCheckedAt < TIMER_CHECK then
			return timerAny and timerKeys or nil
		end
		timerCheckedAt = now
		wipe(timerKeys)
		timerAny = false
		if not ns.isRetail or type(tracker) ~= "table" or IsForbidden(tracker) then
			return nil
		end
		for _, section in ipairs(TrackerSections(tracker)) do
			if type(section) == "table" and not IsForbidden(section) then
				local scenarioSection = IsScenarioSection(section)
				if scenarioSection and (HeaderTimerUp(section) or ClockUp()) then
					timerKeys[SCENARIO], timerAny = true, true
				end
				local bars = section.usedTimerBars
				if type(bars) == "table" and next(bars) then
					for line, bar in pairs(bars) do
						local owner = type(bar) == "table" and bar.IsShown and not IsForbidden(bar) and ns.Flag(bar:IsShown())
							and type(line) == "table" and line.GetParent and not IsForbidden(line) and line:GetParent()
						if owner and scenarioSection then
							timerKeys[SCENARIO], timerAny = true, true
						elseif owner and type(section.usedBlocks) == "table" then
							for _, blocks in pairs(section.usedBlocks) do
								if type(blocks) == "table" then
									for id, block in pairs(blocks) do
										if block == owner then
											timerKeys[id], timerAny = true, true
										end
									end
								end
							end
						end
					end
				end
			end
		end
		return timerAny and timerKeys or nil
	end
	function ns.TrackerTimerKeys()
		return TrackerTimers(_G.ObjectiveTrackerFrame)
	end
	function ns.HasTrackerTimer()
		return TrackerTimers(_G.ObjectiveTrackerFrame) ~= nil
	end
	-- Each tick, with the tracker's entry: showAll when something besides the
	-- reveal has it up (hovered, a fight, out of CineMode); timerOnly when
	-- nothing but a running timer has it up: just the timer's quest or the
	-- scenario shows (with any quest a reveal focuses).
	function ns.QuestFocusTick(entry, showAll, elapsed, timerOnly)
		local now = GetTime()
		focus.entry = entry
		local timers = timerOnly and TrackerTimers(entry.frame) or nil
		if timers and not focus.timers and not focus.on then
			wipe(focus.quests) -- (a reveal's quests gone: just the timer's)
		end
		focus.timers = timers
		if focus.on and (showAll or (questRevealUntil <= now and entry.alpha == 0)) then
			focus.on = false
		end
		local want = (focus.on or timers) and 0 or 1
		if want == 1 and focus.othersAlpha == 1 then
			return
		end
		-- (Hidden with the tracker: no fade to see.)
		focus.othersAlpha = entry.alpha == 0 and want
			or ns.Approach(focus.othersAlpha, want, elapsed, want > 0 and ns.FadeInTime() or ns.FadeOutTime())
		if not ApplyFocus(entry.frame, focus.othersAlpha, timers) and focus.on and now - focus.since > FOCUS_FIND_TIME then
			focus.on = false
		end
	end
	local function Reveal(setting, questID)
		if ns.db and ns.db[setting] then
			Focus(questID)
			local hold = ns.HoldTime("mouseoverHold") - ns.FadeOutTime()
			if ns.db[QUEST_REVEAL_CALM[setting]] then
				hold = math.max(hold, ns.db.calmTime or 0)
			end
			questRevealUntil = GetTime() + ns.FadeInTime() + math.max(0, hold)
		end
	end
	-- When a quest was last picked up, or a tracked one moved on (Keep open's
	-- "Only after progress", Minimap page). QUEST_WATCH_UPDATE gives a quest
	-- ID on retail and a quest log index on the older clients.
	ns.questActivityAt = 0
	local function IsTracked(quest)
		if ns.isRetail then
			local watchType = C_QuestLog and C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(quest)
			return watchType ~= nil
		end
		return not IsQuestWatched or ns.Flag(IsQuestWatched(quest))
	end
	-- QUEST_ACCEPTED's quest ID: its only argument on retail, the second
	-- (after a quest log index) on the older clients.
	local function AcceptedQuestID(first, second)
		if type(second) == "number" and second > 0 then
			return second
		end
		local inLog = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
		if type(first) == "number" and (ns.isRetail or (inLog and inLog(first))) then
			return first
		end
	end
	questWatcher:SetScript("OnEvent", function(_, event, quest, second)
		-- (Older clients give a quest log index: with "Show just that quest",
		-- the quest log scan below reveals instead, knowing the quest.)
		local scanReveals = event == "QUEST_WATCH_UPDATE" and not ns.isRetail and ns.db and ns.db.questRevealOnlyThat
			and C_QuestLog and C_QuestLog.GetQuestObjectives
		if not scanReveals then
			Reveal(QUEST_REVEAL_EVENTS[event], event == "QUEST_WATCH_UPDATE" and quest or AcceptedQuestID(quest, second))
		end
		if event == "QUEST_ACCEPTED" or type(quest) ~= "number" or IsTracked(quest) then
			ns.questActivityAt = GetTime()
		end
	end)

	-- QUEST_WATCH_UPDATE misses progress-bar objectives (a percentage going
	-- up) and some counted ones, so each quest's progress (its counts plus its
	-- bar's percent) is summed after a quest log update, and a quest whose sum
	-- went up reveals. A quest seen for the first time doesn't. Any client with
	-- retail's quest log API (retail and Forever).
	local questLog = C_QuestLog
	local function IsTrackedID(questID)
		if questLog.GetQuestWatchType then
			return questLog.GetQuestWatchType(questID) ~= nil
		end
		return true
	end
	if questLog and questLog.GetNumQuestLogEntries and questLog.GetInfo and questLog.GetQuestObjectives then
		local progress, seen, advancedQuests = {}, {}, {}
		local pending = false
		local function Progress(questID)
			local sum = 0
			local objectives = questLog.GetQuestObjectives(questID)
			if objectives then
				for i = 1, #objectives do
					local count = objectives[i].numFulfilled
					if type(count) == "number" and not IsSecretValue(count) then
						sum = sum + count
					end
				end
			end
			if GetQuestProgressBarPercent then
				local percent = GetQuestProgressBarPercent(questID)
				if type(percent) == "number" and not IsSecretValue(percent) then
					sum = sum + percent
				end
			end
			return sum
		end
		local function Scan()
			pending = false
			local advanced = wipe(advancedQuests)
			for questID in pairs(seen) do
				seen[questID] = nil
			end
			for i = 1, questLog.GetNumQuestLogEntries() do
				local info = questLog.GetInfo(i)
				local questID = info and not info.isHeader and info.questID
				if type(questID) == "number" and questID > 0 then
					local sum = Progress(questID)
					local before = progress[questID]
					if before and sum > before then
						advanced[#advanced + 1] = questID
						if IsTrackedID(questID) then
							ns.questActivityAt = GetTime()
						end
					end
					progress[questID] = sum
					seen[questID] = true
				end
			end
			for questID in pairs(progress) do
				if not seen[questID] then
					progress[questID] = nil
				end
			end
			for _, questID in ipairs(advanced) do
				Reveal("questRevealOnProgress", questID)
			end
		end
		local logWatcher = CreateFrame("Frame")
		logWatcher:RegisterEvent("QUEST_LOG_UPDATE")
		logWatcher:SetScript("OnEvent", function()
			if not pending then
				pending = true
				C_Timer.After(0.2, Scan)
			end
		end)
	end

	-- Scenarios (a raid boss's or dungeon's stages and objectives, as in the
	-- tracker's scenario block) aren't quests: their progress is the stage
	-- number plus each criterion's count plus the step's weighted percent,
	-- summed after a scenario update, and a sum gone up reveals the tracker
	-- (with "Show just that quest", just the scenario section). Entering a
	-- scenario doesn't.
	local scenario = C_ScenarioInfo
	if scenario and scenario.GetScenarioInfo and scenario.GetScenarioStepInfo and scenario.GetCriteriaInfo then
		local lastSum, lastName
		local scenarioPending = false
		local function Number(value)
			return type(value) == "number" and not IsSecretValue(value) and value or 0
		end
		local function ScanScenario()
			scenarioPending = false
			local info = scenario.GetScenarioInfo()
			local name = info and info.name
			if type(name) ~= "string" or IsSecretValue(name) or name == "" then
				lastSum, lastName = nil, nil
				return
			end
			local sum = Number(info.currentStage) * 1e6
			local step = scenario.GetScenarioStepInfo()
			if step then
				sum = sum + Number(step.weightedProgress)
				for i = 1, Number(step.numCriteria) do
					local criteria = scenario.GetCriteriaInfo(i)
					if criteria then
						sum = sum + Number(criteria.quantity)
					end
				end
			end
			if name == lastName and lastSum and sum > lastSum then
				Reveal("questRevealOnScenario", SCENARIO)
				ns.questActivityAt = GetTime()
			end
			lastSum, lastName = sum, name
		end
		local scenarioWatcher = CreateFrame("Frame")
		for _, event in ipairs({ "SCENARIO_UPDATE", "SCENARIO_CRITERIA_UPDATE", "CRITERIA_COMPLETE",
			"PLAYER_ENTERING_WORLD" }) do
			pcall(scenarioWatcher.RegisterEvent, scenarioWatcher, event)
		end
		scenarioWatcher:SetScript("OnEvent", function()
			if not scenarioPending then
				scenarioPending = true
				C_Timer.After(0.2, ScanScenario)
			end
		end)
	end
end

-- Gear damaged (yellow) or broken (red): the game shows the durability
-- figure then, and it stays up in CineMode while it does (durabilityShow).
-- Asked of each equipped slot when durability changes, not every tick. (A
-- secret status counts as fine.)
do
	local alert = false
	local function Check()
		alert = false
		if not GetInventoryAlertStatus then
			local frame = _G.DurabilityFrame
			alert = frame ~= nil and ns.Flag(frame:IsShown())
			return
		end
		for slot = 1, 19 do
			local status = GetInventoryAlertStatus(slot)
			if type(status) == "number" and status > 0 then
				alert = true
				return
			end
		end
	end
	local durabilityWatcher = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "UNIT_INVENTORY_CHANGED" }) do
		pcall(durabilityWatcher.RegisterEvent, durabilityWatcher, event)
	end
	durabilityWatcher:SetScript("OnEvent", function(_, event, unit)
		if event ~= "UNIT_INVENTORY_CHANGED" or unit == "player" then
			Check()
		end
	end)
	function ns.HasDurabilityAlert()
		return alert
	end
end

-- Hunter pet not happy (content or unhappy, not green): the pet frame stays up
-- in CineMode while it is (petUnhappyShow). Not retail, which has no happiness.
-- (A secret value counts as happy.) Forever has no GetPetHappiness: its pet
-- frame's happiness icon asks with GetHappinessStats, and updates itself.
do
	local unhappy = false
	local function Happiness()
		if GetPetHappiness then
			return GetPetHappiness()
		end
		local icon = _G.PetFrameHappiness
		if icon and icon.GetHappinessStats then
			local ok, happiness = pcall(icon.GetHappinessStats, icon)
			return ok and happiness or nil
		end
	end
	local function Check()
		local happiness = Happiness()
		unhappy = type(happiness) == "number" and happiness < 3
	end
	local icon = _G.PetFrameHappiness
	if icon and icon.UpdateHappiness then
		hooksecurefunc(icon, "UpdateHappiness", Check)
	end
	local petWatcher = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE" }) do
		pcall(petWatcher.RegisterEvent, petWatcher, event)
	end
	petWatcher:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_PET" and unit ~= "player" then
			return
		end
		Check()
	end)
	-- (Not while the pet is dead, or dismissed: nothing to feed.)
	function ns.IsPetUnhappy()
		return unhappy and ns.Flag(UnitExists("pet")) and not ns.Flag(UnitIsDead("pet"))
	end
end

-- A group member pinging the minimap brings it up the same way
-- (minimapRevealOnPing) for minimapPingTime seconds, even in a camera mode
-- that hides it. Your own pings too, but not the ones NodeSweep.lua makes on
-- ore and herbs (its own reveal shows those; theirs come back a moment later).
local pingRevealUntil = 0
do
	local NODE_PING_ECHO = 3 -- seconds after a node ping that a ping of yours is taken as its echo
	local function Reveal(how, mine)
		if not (ns.db and ns.db.minimapRevealOnPing) then
			if ns.pingDebug then ns.Print(how .. ": Pings is off") end
			return
		end
		if mine and GetTime() - (ns.nodePingAt or -math.huge) < NODE_PING_ECHO then
			if ns.pingDebug then ns.Print(how .. ": taken as an ore/herb ping, skipped") end
			return
		end
		pingRevealUntil = GetTime() + ns.FadeInTime() + ns.db.minimapPingTime
		if ns.pingDebug then
			ns.Print(("%s: minimap up for %.1f sec"):format(how, pingRevealUntil - GetTime()))
		end
	end
	local pingWatcher = CreateFrame("Frame")
	pcall(pingWatcher.RegisterEvent, pingWatcher, "MINIMAP_PING")
	pingWatcher:SetScript("OnEvent", function(_, _, unit)
		local ok, mine = pcall(UnitIsUnit, unit or "player", "player")
		Reveal("ping event (" .. tostring(unit) .. ")", ok and ns.Flag(mine))
	end)
	-- (Your own clicks, in case the event doesn't come for them: the click
	-- pings through Minimap:PingLocation. NodeSweep.lua's pings go through it
	-- too and are told apart the same way.)
	if Minimap and Minimap.PingLocation then
		hooksecurefunc(Minimap, "PingLocation", function()
			Reveal("your ping", true)
		end)
	end
	-- /cine debug ping: also what would bring the minimap up with it.
	function ns.ReportPingReveal()
		ns.pingDebug = not ns.pingDebug
		ns.Print("print minimap pings: " .. (ns.pingDebug and "on" or "off") .. " (until you /reload)")
		ns.Print(("Minimap page on: %s, Pings: %s, Show for: %s sec, Not on flight paths: %s"):format(
			tostring(ns.PageOn("handleMinimap")), tostring(ns.db.minimapRevealOnPing),
			tostring(ns.db.minimapPingTime), tostring(ns.db.minimapHideOnTaxi)))
		local any = false
		for _, group in ipairs(ns.GetHoverGroups()) do
			if group.triggers and group.triggers.ping then
				any = true
				ns.Print(("group %s (Minimap ping ticked)%s%s: %s"):format(tostring(group.name),
					group.off and ", turned off" or "", group.when and ", only " .. group.when or "",
					table.concat(group.members or {}, ", ")))
			end
		end
		if not any then
			ns.Print("no Mouseover group has Minimap ping ticked: pings bring nothing up")
		end
	end
end

-- Someone joining or leaving your group (or you joining or leaving one)
-- brings up the Mouseover groups with it ticked the same way: the raid
-- frames by default. Just the group's size changing, not every roster update.
local rosterRevealUntil = 0
do
	local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
	local rosterRevealWatcher = CreateFrame("Frame")
	rosterRevealWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	rosterRevealWatcher:SetScript("OnEvent", function()
		local size = GetNumGroupMembers()
		if (issecretvalue and issecretvalue(size)) or type(size) ~= "number" or size == groupSize or not ns.db then
			return
		end
		groupSize = size
		local hold = ns.HoldTime("mouseoverHold") - ns.FadeOutTime()
		rosterRevealUntil = GetTime() + ns.FadeInTime() + math.max(0, hold)
	end)
end

-- Gamepad mode: pressing a gamepad button brings its action bars up, as
-- hovering does with the mouse (gamepadPressReveal): they fade in, then are
-- gone the bars' mouseover time later. The pad's buttons are read each
-- frame (C_GamePad), which leaves the presses to the game; the button event,
-- where the client has one, counts too.
-- Which buttons count is the player's choice (the Gamepad page's list).
-- Besides that,
-- not while fishing (the fish camera on, a cast going, or looting), nor
-- buttons bound to moving, turning or the camera, nor the fishing button
-- while it casts: going by what the button does now (override bindings too).
-- (Not by watching whether you moved or turned after a press: in gamepad mode
-- you turn with the camera all the time, so presses on the move never counted.)
local NO_REVEAL = {
	MOVEFORWARD = true, MOVEBACKWARD = true, TURNLEFT = true, TURNRIGHT = true,
	STRAFELEFT = true, STRAFERIGHT = true, TOGGLEAUTORUN = true, SITORSTAND = true,
	CAMERAZOOMIN = true, CAMERAZOOMOUT = true,
}
-- The buttons a press can come from, for the Gamepad page's list (each
-- ticked or not: db.gamepadPressButtons[key], missing = the default here).
-- Off by default: the right stick (the camera), clicking a stick in (ping
-- and auto-run) and the menu buttons. (Jumping is seen as it happens, so the
-- jump button can stay ticked.) Face buttons go by where they sit: pads print different
-- letters there (a Nintendo-style pad's A is on the right, Xbox's B). The left stick's directions are left to
-- the moving check: they don't always walk you.
ns.GAMEPAD_BUTTONS = {
	{ key = "PAD1", label = L["Bottom face button"], default = true },
	{ key = "PAD2", label = L["Right face button"], default = true },
	{ key = "PAD3", label = L["Left face button"], default = true },
	{ key = "PAD4", label = L["Top face button"], default = true },
	{ key = "PADDUP", label = L["D-pad up"], default = true },
	{ key = "PADDDOWN", label = L["D-pad down"], default = true },
	{ key = "PADDLEFT", label = L["D-pad left"], default = true },
	{ key = "PADDRIGHT", label = L["D-pad right"], default = true },
	{ key = "PADLSHOULDER", label = L["Left bumper (LB)"], default = true },
	{ key = "PADRSHOULDER", label = L["Right bumper (RB)"], default = true },
	{ key = "PADLTRIGGER", label = L["Left trigger (LT)"], default = true },
	{ key = "PADRTRIGGER", label = L["Right trigger (RT)"], default = true },
	{ key = "PADLSTICKUP", label = L["Left stick up"], default = true },
	{ key = "PADLSTICKDOWN", label = L["Left stick down"], default = true },
	{ key = "PADLSTICKLEFT", label = L["Left stick left"], default = true },
	{ key = "PADLSTICKRIGHT", label = L["Left stick right"], default = true },
	{ key = "PADRSTICKUP", label = L["Right stick up"], default = false },
	{ key = "PADRSTICKDOWN", label = L["Right stick down"], default = false },
	{ key = "PADRSTICKLEFT", label = L["Right stick left"], default = false },
	{ key = "PADRSTICKRIGHT", label = L["Right stick right"], default = false },
	{ key = "PADLSTICK", label = L["Left stick click"], default = false },
	{ key = "PADRSTICK", label = L["Right stick click"], default = false },
	{ key = "PADFORWARD", label = L["Start / Menu"], default = false },
	{ key = "PADBACK", label = L["Back / View"], default = false },
}
-- The labels above were made before the language was known: translated again.
ns.OnLanguage(function()
	ns.TranslateFields(ns.COMBAT_SHOW, "label", "tip", "alwaysTip", "hoverLabel")
	ns.TranslateFields(ns.HOVER_ROWS, "label", "tip")
	ns.TranslateFields(ns.HOVER_TRIGGERS, "label", "tip")
	ns.TranslateFields(ns.HOVER_GROUPS_DEFAULT, "name")
	ns.TranslateFields(ns.PLACE_SHOW, "label", "tip")
	ns.TranslateFields(ns.GAMEPAD_BUTTONS, "label")
end)
local PAD_BUTTON_DEFAULT = {}
for _, item in ipairs(ns.GAMEPAD_BUTTONS) do
	PAD_BUTTON_DEFAULT[item.key] = item.default
end

-- The game's own name for a button, as your pad labels it ("" if none).
function ns.PadButtonText(button)
	local ok, text = pcall(GetBindingText, button)
	if ok and type(text) == "string" and text ~= button then
		return text
	end
	return ""
end

-- Whether presses of this button reveal the bars (buttons not listed do).
function ns.IsPadButtonOn(button)
	local on = ns.db.gamepadPressButtons[button]
	if on == nil then
		on = PAD_BUTTON_DEFAULT[button]
	end
	return on ~= false
end

local function RevealsBars(button)
	if not ns.IsPadButtonOn(button) then
		return false
	end
	local ok, action = pcall(GetBindingAction, button, true)
	if not ok or type(action) ~= "string" then
		return true
	end
	return not (NO_REVEAL[action] or action:find("^CLICK CinematicFishingCastButton"))
end
local padRevealUntil = 0
-- A press that starts a cast is seen just before the cast begins, so presses
-- wait CAST_WAIT seconds and don't count if you're fishing by then. Nor if
-- you're in the air by then: that press jumped, whichever button jumps on
-- your pad.
local CAST_WAIT = 0.25
local pendingPress -- { at, button } while a press waits
local function Fishing()
	return (ns.IsFishingNow and ns.IsFishingNow()) or (LootFrame and ns.Flag(LootFrame:IsShown())) or false
end
local function DebugPress(button, text)
	if ns.padDebug then
		ns.Print(("pad %s: %s"):format(tostring(button), text))
	end
end
local function OnPadButton(button, via)
	local ok, action = pcall(GetBindingAction, button, true)
	DebugPress(button, ("%s (the game calls it %s), bound to \"%s\""):format(via, ns.PadButtonText(button),
		ok and tostring(action) or "?"))
	-- Fishing (casting, catching, looting): presses are for that.
	if Fishing() then
		DebugPress(button, "not revealing (fishing)")
		return
	end
	if not RevealsBars(button) then
		DebugPress(button, ("not revealing (%s)"):format(not ns.IsPadButtonOn(button)
			and "unticked on the Gamepad page" or "what it's bound to"))
		return
	end
	if ns.db and ns.db.gamepadPressReveal and not pendingPress then
		pendingPress = { at = GetTime(), button = button }
	end
end
-- A waiting press: dropped if it started fishing, else the bars come up.
local function CheckPendingPress()
	local press = pendingPress
	if not press then
		return
	end
	if Fishing() then
		pendingPress = nil
		DebugPress(press.button, "not revealing (started fishing)")
	elseif ns.Flag(IsFalling()) then
		pendingPress = nil
		DebugPress(press.button, "not revealing (jumped)")
	elseif GetTime() - press.at >= CAST_WAIT then
		pendingPress = nil
		DebugPress(press.button, "reveals")
		-- (The bars' own times, Gamepad page: see GroupFadeTime.)
		local hold = ns.db.gamepadPressHold - ns.db.gamepadBarsFadeOut
		padRevealUntil = GetTime() + ns.db.gamepadBarsFadeIn + math.max(0, hold)
	end
end
local padWatcher = CreateFrame("Frame")
ns.padEventOK = pcall(padWatcher.RegisterEvent, padWatcher, "GAME_PAD_BUTTON_DOWN")
padWatcher:SetScript("OnEvent", function(_, _, button)
	OnPadButton(button, "event")
end)
-- Buttons held last frame (index -> true), to see new presses.
local padHeld = {}
local function ButtonName(index)
	local ok, name = pcall(C_GamePad.ButtonIndexToBinding, index)
	return ok and name or ("button" .. index)
end
-- Moving and auto-run in gamepad mode: the left stick walks you and clicking
-- it toggles auto-run, all handled by the gamepad UI itself (no bindings, so
-- none of the Move*/ToggleAutoRun functions Core.lua hooks are called). So
-- the stick's directions held count as movement keys (ns.PadMovementHeld),
-- up or down ends auto-run as forward and back do, and the click toggles it.
local PAD_MOVE = { PADLSTICKUP = true, PADLSTICKDOWN = true, PADLSTICKLEFT = true, PADLSTICKRIGHT = true }
local PAD_ENDS_AUTORUN = { PADLSTICKUP = true, PADLSTICKDOWN = true }
local padMoveHeld = false
function ns.PadMovementHeld()
	return padMoveHeld
end
padWatcher:SetScript("OnUpdate", ns.Profiled("Gamepad watch", function()
	CheckPendingPress()
	if not (ns.db and C_GamePad and C_GamePad.GetDeviceMappedState and ns.IsGamePadOn()) then
		padMoveHeld = false
		return
	end
	local ok, state = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID
		and C_GamePad.GetActiveDeviceID() or nil)
	if not ok or type(state) ~= "table" or type(state.buttons) ~= "table" then
		padMoveHeld = false
		return
	end
	local moving = false
	for index, down in ipairs(state.buttons) do
		local name = (down or padHeld[index]) and ButtonName(index)
		if down and PAD_MOVE[name] then
			moving = true
		end
		if down and not padHeld[index] then
			if name == "PADLSTICK" and ns.OnAutoRunToggle then
				ns.OnAutoRunToggle()
			elseif PAD_ENDS_AUTORUN[name] then
				ns.autoRunning = false
			end
			OnPadButton(name, "read")
		end
		padHeld[index] = down or nil
	end
	padMoveHeld = moving
end))

-- A quest timer running (Classic clients; retail has no quest timer box).
-- Clients without GetQuestTimers go by the box: the game only shows it while
-- a timer runs (the fade only changes its alpha).
local function HasQuestTimer()
	if ns.isRetail then
		return false
	end
	if GetQuestTimers then
		return select("#", GetQuestTimers()) > 0
	end
	local frame = _G.QuestTimerFrame
	return frame ~= nil and ns.Flag(frame:IsShown())
end

-- A quest tracked in the quest tracker (Keep open, Minimap page), or on
-- retail one focused for its waypoint.
function ns.HasTrackedQuest()
	local count = C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()
		or GetNumQuestWatches and GetNumQuestWatches()
	if type(count) == "number" and count > 0 then
		return true
	end
	local superTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	return type(superTracked) == "number" and superTracked > 0
end

-- A cooldown still recharging in the Cooldown Manager's spell bars (not its
-- buff bars) or Enhanced Cooldown Manager's cooldown bars, longer than the
-- global cooldown. Each icon's spell is asked about first; failing that, the
-- cooldown swipe on it. Looked at a few times a second. The game keeps some
-- of this secret (in fights, and on some clients whether the bars are shown):
-- a secret time counts as ready, a secret "shown" as shown.
local COOLDOWN_VIEWERS = { EssentialCooldownViewer = true, UtilityCooldownViewer = true }
local GCD = 1.6
local cooldownCheckedAt, cooldownRecharging = 0, {} -- (group -> true while one in it is)

local function Secret(...)
	if not issecretvalue then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

-- Hidden for sure (a secret answer isn't).
local function Hidden(frame)
	local ok, shown = pcall(frame.IsShown, frame)
	return ok and not Secret(shown) and not shown
end

-- The spell an icon shows, if it says.
local ItemSpell
do
local INFO_SPELL_FIELDS = { "overrideSpellID", "spellID" }
function ItemSpell(item)
	if item.GetSpellID then
		local ok, id = pcall(item.GetSpellID, item)
		if ok and not Secret(id) and type(id) == "number" and id > 0 then return id end
	end
	-- (Only type() and Secret() on values that may be secret: testing one errors.)
	local cooldownID = item.cooldownID
	if type(cooldownID) == "nil" and item.GetCooldownID then
		local ok, id = pcall(item.GetCooldownID, item)
		if ok then cooldownID = id end
	end
	if type(cooldownID) == "number" and not Secret(cooldownID)
		and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
		local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
		if ok and type(info) == "table" then
			for _, field in ipairs(INFO_SPELL_FIELDS) do
				local id = info[field]
				if type(id) == "number" and not Secret(id) and id > 0 then return id end
			end
		end
	end
end
end

-- An icon's Cooldown Manager info (spellID, overrideSpellID, charges...), if it says.
function ns.IconCooldownInfo(icon)
	if type(icon.GetCooldownInfo) == "function" then
		local ok, info = pcall(icon.GetCooldownInfo, icon)
		if ok and type(info) == "table" then return info end
	end
	local cooldownID = icon.cooldownID
	if type(cooldownID) == "number" and not Secret(cooldownID)
		and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
		local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
		if ok and type(info) == "table" then return info end
	end
end

-- The spell a spell turned into came from (Tempest: Lightning Bolt), else
-- itself, as the Cooldown Manager's icons say (their spellID under what they
-- show now). Not the game's FindBaseSpellByID: that says Lava Burst's is
-- Primal Strike. The page's settings are kept under it, so a spell keeps its
-- mode while it's turned into another.
do
	local baseOf = {} -- spell shown -> the icon's own spell
	ns.cooldownChargeSpells = {} -- spell ID -> true: the Cooldown Manager says it has charges
	-- (Each icon's info read once per spell it shows: a new table each time.)
	local noted = setmetatable({}, { __mode = "k" }) -- icon -> the spell it was read for
	function ns.ForgetCooldownNotes()
		wipe(noted)
		wipe(ns.cooldownChargeSpells)
	end
	function ns.NoteCooldownIcon(icon, id)
		if noted[icon] == id then return end
		noted[icon] = id
		ns.NoteCooldownBase(icon, id)
		ns.NoteCooldownCharges(icon, id)
	end
	function ns.NoteCooldownBase(icon, id)
		local info = ns.IconCooldownInfo(icon)
		local base = info and info.spellID
		if type(base) == "number" and not Secret(base) and base > 0 and base ~= id then
			baseOf[id] = base
		end
	end
	function ns.BaseSpell(id)
		return baseOf[id] or id
	end
end

-- A spell's cooldown: start and duration in seconds, or nil if the game won't say.
-- (Asked for every Cooldown Manager icon ten times a second, and the game
-- gives a new table each time: each answer is kept until the game says
-- cooldowns changed, or for a second at most; a fight starting or ending
-- too, as it changes what's secret.)
local SpellCooldown
do
local NOT_KNOWN = false
local keptStart, keptDuration, keptAt = {}, {}, {}
local function Forget()
	wipe(keptStart)
	wipe(keptDuration)
	wipe(keptAt)
end
local forgetter = CreateFrame("Frame")
for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE" }) do
	pcall(forgetter.RegisterEvent, forgetter, event)
end
forgetter:SetScript("OnEvent", Forget)
local function AskCooldown(id)
	local ok, start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local info
		ok, info = pcall(C_Spell.GetSpellCooldown, id)
		if ok and type(info) == "table" then
			start, duration = info.startTime, info.duration
		end
	elseif GetSpellCooldown then
		ok, start, duration = pcall(GetSpellCooldown, id)
	end
	if not ok or Secret(start, duration) or type(start) ~= "number" or type(duration) ~= "number" then
		return nil
	end
	return start, duration
end
function SpellCooldown(id)
	local now = GetTime()
	local at = keptAt[id]
	if at and now - at < 1 then
		local start = keptStart[id]
		if start == NOT_KNOWN then
			return nil
		end
		return start, keptDuration[id]
	end
	local start, duration = AskCooldown(id)
	keptAt[id], keptStart[id], keptDuration[id] = now, start or NOT_KNOWN, duration
	return start, duration
end
end

-- A cooldown swipe's start and duration, in seconds, or nil.
local function SwipeTimes(cooldown)
	if not cooldown.GetCooldownTimes then return nil end
	local ok, start, duration = pcall(cooldown.GetCooldownTimes, cooldown)
	if not ok or Secret(start, duration) or type(start) ~= "number" or type(duration) ~= "number" then
		return nil
	end
	return start / 1000, duration / 1000
end

-- Calls visit(frame, kind) for each icon ("item", one with a spell) and each
-- cooldown swipe ("swipe") under frame (all: hidden ones too).
-- (Looked through several times a second: each walk's list of children is
-- kept and reused, one for each walk running inside another, not made anew.)
local EachCooldownPart
do
local childLists, walking = {}, 0
local function FillChildren(list, ...)
	local count = select("#", ...)
	for i = 1, count do
		list[i] = (select(i, ...))
	end
	for i = count + 1, list.count or 0 do
		list[i] = nil
	end
	list.count = count
	return count
end
function EachCooldownPart(frame, depth, visit, all)
	walking = walking + 1
	local list = childLists[walking]
	if not list then
		list = {}
		childLists[walking] = list
	end
	for i = 1, FillChildren(list, frame:GetChildren()) do
		local child = list[i]
		if all or not Hidden(child) then
			local isCooldown = child.GetObjectType and child:GetObjectType() == "Cooldown"
			if isCooldown then
				visit(child, "swipe")
			elseif child.GetSpellID or child.GetCooldownID or type(child.cooldownID) ~= "nil" then
				visit(child, "item")
			end
			if not isCooldown and depth > 0 then
				EachCooldownPart(child, depth - 1, visit, all)
			end
		end
	end
	-- (A visit that errored leaves this a step high: the next walks just use
	-- lists further in.)
	walking = walking - 1
end
end

local function Recharging(start, duration, now)
	return duration > GCD and start + duration > now
end

-- The Cooldown Manager frames to look in.
local function EachCooldownFrame(visit)
	for _, entry in ipairs(ns.managed) do
		local frame = entry.frame
		if COOLDOWN_VIEWERS[entry.name] or (entry.group == "addon:fecm" and frame.kind == "cooldown") then
			visit(entry, frame)
		end
	end
end

-- Whether a cooldown in a bar is recharging: group "essential" (with
-- Enhanced Cooldown Manager's bars) or "utility".
local function AnyCooldownRecharging(now, group)
	if now - cooldownCheckedAt < 0.25 then
		return cooldownRecharging[group] or false
	end
	cooldownCheckedAt = now
	wipe(cooldownRecharging)
	EachCooldownFrame(function(entry, frame)
		local bar = ns.COOLDOWN_BAR_GROUPS[entry.name] or "essential"
		if cooldownRecharging[bar] or Hidden(frame) then return end
		local found = false
		EachCooldownPart(frame, 3, function(part, kind)
			if found then return end
			local start, duration
			if kind == "item" then
				local id = ItemSpell(part)
				if id then start, duration = SpellCooldown(id) end
			else
				start, duration = SwipeTimes(part)
			end
			if start and Recharging(start, duration, now) then found = true end
		end)
		cooldownRecharging[bar] = found or nil
	end)
	return cooldownRecharging[group] or false
end

-- The Cooldown Manager page's "Only when ready in combat" spells
-- (db.cooldownReadyOnly: spell ID -> true): out of fights, and in fights
-- while it's recharging, a spell's icon fades out, the rest of its bar as
-- usual (the icon's place stays: it leaves a gap). It comes back once it's
-- ready, or with Show Early (db.cooldownEarlyOn[spell ID]) a little before:
-- db.cooldownReadyEarly[spell ID] seconds, or by default READY_EARLY of its
-- cooldown. Recharging: its swipe
-- says so, when the game lets it be read; in fights WoW Forever keeps it
-- secret, so then it goes by when you last cast the spell and how long its
-- cooldown is. Not knowing (say, cast before a reload), it shows.
-- The page's "While recharging" spells (db.cooldownRechargeOnly) are the
-- other way round, in fights or not: shown while recharging, faded once
-- ready. Not knowing, those stay faded (most likely it's ready).
-- (Sec: quicker than the CineMode fades, it's a cue. Coming back eases in;
-- going, as it's cast, it's out of the way at once.)
local READY_FADE_IN, READY_FADE_OUT = 0.5, 0.25
ns.READY_EARLY = 0.15 -- (of its cooldown)
local lastCastOf = {} -- spell ID -> when you last cast it
local cooldownLength = {} -- spell ID -> its cooldown (sec), last read off its swipe
local iconSpell = setmetatable({}, { __mode = "k" }) -- icon -> its spell, last read (for when it's secret)
local readyTargets = {} -- icon -> 0 or 1, for the ticked spells' icons
local readyAlpha = {} -- icon -> its alpha, while not full
local readyCheckedAt = 0

do
	local castWatcher = CreateFrame("Frame")
	castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	castWatcher:SetScript("OnEvent", function(_, _, _, _, spellID)
		if not Secret(spellID) and type(spellID) == "number" then
			lastCastOf[spellID] = GetTime()
		end
	end)
end

-- The page's "When it procs" spells (db.cooldownProcOnly): shown only while
-- the game glows the spell (a proc up, like an instant Lightning Bolt), in
-- fights or not. The glow's events say which spell; failing that the game is
-- asked, then the icon's own glow frame. Not knowing: faded.
do
	local glowing = {} -- spell ID -> true while its glow is up
	local glowWatcher = CreateFrame("Frame")
	glowWatcher:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
	glowWatcher:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
	glowWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	glowWatcher:SetScript("OnEvent", function(_, event, spellID)
		if event == "PLAYER_ENTERING_WORLD" then
			wipe(glowing)
		elseif not Secret(spellID) and type(spellID) == "number" then
			glowing[spellID] = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or nil
		end
	end)

	local IsOverlayed = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed)
		or _G.IsSpellOverlayed
	-- (Its glow may come under what it's turned into or its base: Tempest's Lightning Bolt.)
	local function Glows(id)
		if glowing[id] then return true end
		if IsOverlayed then
			local ok, on = pcall(IsOverlayed, id)
			if ok and not Secret(on) and on then return true end
		end
		return false
	end
	function ns.SpellGlowing(id, icon)
		if Glows(id) then return true end
		local base = ns.BaseSpell(id)
		if base ~= id and Glows(base) then return true end
		local alert = icon and icon.SpellActivationAlert
		if type(alert) == "table" and alert.IsShown then
			local ok, shown = pcall(alert.IsShown, alert)
			if ok and not Secret(shown) and shown then return true end
		end
		return false
	end
end

function ns.CooldownLength(id)
	if cooldownLength[id] then
		return cooldownLength[id]
	end
	if GetSpellBaseCooldown then
		local ok, ms = pcall(GetSpellBaseCooldown, id)
		if ok and not Secret(ms) and type(ms) == "number" and ms > 0 then
			return ms / 1000
		end
	end
end

local CooldownLength = ns.CooldownLength

-- The page's groups (each bar of the Cooldown Manager) and what a spell in
-- one does when it hasn't been set on its own: the group's settings
-- (db.cooldownGroupDefaults[group]), else these.
ns.COOLDOWN_GROUP_MODES = { utility = "recharge" }
-- The bars whose spells with no cooldown go by Smart Set (ns.SmartCooldownMode)
-- until their group's mode is set.
ns.COOLDOWN_SMART_GROUPS = { essential = true, utility = true }
ns.COOLDOWN_BAR_GROUPS = { EssentialCooldownViewer = "essential", UtilityCooldownViewer = "utility" }
-- Its tracked buffs and bars: groups of their own, with modes of their own
-- (ns.CooldownBuffMode), and not counted for recharging.
ns.COOLDOWN_BUFF_GROUPS = { BuffIconCooldownViewer = "buffs", BuffBarCooldownViewer = "bars" }
-- (The Mouseover groups' cooldown bar rows, and whose Stay up while
-- recharging brings each up.)
ns.COOLDOWN_MEMBER_BAR = { cooldowns = "essential", ["addon:fecm"] = "essential", cooldownsutility = "utility" }
-- The bars with Close the gaps on until it's set (below: CenterCooldownIcons).
ns.COOLDOWN_GROUP_CENTER = { essential = true, utility = true }

-- Whether a bar's Close the gaps is on.
function ns.CooldownGroupCentered(group)
	local set = ns.db.cooldownGroupDefaults[group]
	if set and set.center ~= nil then return set.center end
	return ns.COOLDOWN_GROUP_CENTER[group] or false
end

-- A group's mode, and its Resources and Show Early seconds (nil: the default share).
function ns.CooldownGroupSettings(group)
	local set = ns.db.cooldownGroupDefaults[group] or NO_DEFAULTS
	return set.mode or ns.COOLDOWN_GROUP_MODES[group] or "always", set.power, set.early
end

-- A spell's mode ("always", "ready", "recharge", "proc"), whether it's its
-- own (else its group's), and for "ready" its Resources, Show Early on, and
-- seconds (nil: the default share). Set under what it's turned into (from
-- before settings went by the base) or its base.
function ns.CooldownSpellMode(id, group)
	local db = ns.db
	if not (db.cooldownReadyOnly[id] or db.cooldownRechargeOnly[id] or db.cooldownProcOnly[id]
		or db.cooldownAlwaysShow[id]) then
		id = ns.BaseSpell(id)
	end
	if db.cooldownReadyOnly[id] then
		return "ready", true, db.cooldownNeedsPower[id], db.cooldownEarlyOn[id], db.cooldownReadyEarly[id]
	elseif db.cooldownRechargeOnly[id] then
		return "recharge", true
	elseif db.cooldownProcOnly[id] then
		return "proc", true
	elseif db.cooldownAlwaysShow[id] then
		return "always", true
	end
	-- (Its group's mode not set: the Smart Set pick, if it has one and Smart Set's ticked.)
	local set = db.cooldownGroupDefaults[group or "other"]
	if db.cooldownSmartDefaults and not (set and set.mode) and ns.COOLDOWN_SMART_GROUPS[group] then
		local pick = ns.SmartCooldownMode(id)
		if pick == "power" then
			return "ready", false, true, true, set and set.early
		elseif pick == "proc" then
			return "proc", false
		end
	end
	local mode, power, early = ns.CooldownGroupSettings(group or "other")
	return mode, false, power, true, early
end

-- A tracked buff's or bar's mode ("always", "combat": in fights, "quiet":
-- out of fights, "hidden"), and whether it's its own (db.cooldownBuffMode,
-- by spell ID), else its group's. Each goes by whether you're in a fight
-- only: the game keeps your buffs secret in fights.
function ns.CooldownBuffMode(id, group)
	local own = ns.db.cooldownBuffMode[id] or ns.db.cooldownBuffMode[ns.BaseSpell(id)]
	if own then return own, true end
	return (ns.CooldownGroupSettings(group or "buffs")), false
end

-- Whether a tracked buff's or bar's icon shows in a mode.
function ns.CooldownBuffShows(mode, inCombat)
	if mode == "hidden" then return false end
	if mode == "combat" then return inCombat end
	if mode == "quiet" then return not inCombat end
	return true
end

-- How long before a spell's icon is ready it comes back (sec), or nil until its cooldown's known.
local function ReadyEarly(earlyOn, seconds, length)
	if not earlyOn then
		return 0 -- (Show Early unticked: back once it's ready)
	end
	return seconds or (length and length * ns.READY_EARLY)
end

-- How long until an icon's spell is ready (sec, 0 when it is), and its
-- cooldown; nil when it can't tell.
local IconTimeLeft
do
-- (The first swipe's times, found by one function made once.)
local swipeStart, swipeDuration
local function FirstSwipe(part, kind)
	if kind == "swipe" and not swipeStart then
		swipeStart, swipeDuration = SwipeTimes(part)
	end
end
function IconTimeLeft(icon, id, now)
	local start, duration = SpellCooldown(id)
	if not start then
		swipeStart, swipeDuration = nil, nil
		EachCooldownPart(icon, 1, FirstSwipe)
		start, duration = swipeStart, swipeDuration
	end
	if start then
		if not Recharging(start, duration, now) then
			return 0, CooldownLength(id)
		end
		cooldownLength[id] = duration
		return start + duration - now, duration
	end
	local cast, length = lastCastOf[id], CooldownLength(id)
	if cast and length then
		return math.max(0, cast + length - now), length
	end
	return nil
end
end

-- Whether you have the resources to cast a spell (mana, Maelstrom...): the
-- game's "usable" check first, else its costs against your power. True when
-- the game won't say.
function ns.SpellHasPower(id)
	local IsUsable = (C_Spell and C_Spell.IsSpellUsable) or _G.IsUsableSpell
	if IsUsable then
		local ok, usable, noPower = pcall(IsUsable, id)
		if ok and not Secret(usable, noPower) then
			return not noPower
		end
	end
	local GetCosts = (C_Spell and C_Spell.GetSpellPowerCost) or _G.GetSpellPowerCost
	if not GetCosts then return true end
	local ok, costs = pcall(GetCosts, id)
	if not ok or type(costs) ~= "table" then return true end
	for _, cost in ipairs(costs) do
		-- (type() only on what may be secret: testing one errors.)
		local need, kind = cost.minCost, cost.type
		if type(need) == "nil" then need = cost.cost end
		local have = type(kind) == "number" and not Secret(kind) and UnitPower("player", kind)
		if type(need) == "number" and type(have) == "number" and not Secret(need, have) and have < need then
			return false
		end
	end
	return true
end

-- The Cooldown Manager page's Smart Set: what a spell with no cooldown is
-- best as. "power" (When Ready with Resources) when it costs a resource you
-- build up, like Maelstrom; "proc" when it costs nothing or only one that's
-- always there (mana, rage, energy, focus: an instant Lightning Bolt). nil
-- for a spell with a cooldown or charges (even one that recharges), or when the game won't say.
-- It's also what those spells are by default (ns.CooldownSpellMode), until
-- you set their group's mode.
do
	local EVERYDAY_POWER = {}
	for _, name in ipairs({ "Mana", "Rage", "Energy", "Focus" }) do
		local number = Enum and Enum.PowerType and Enum.PowerType[name]
		if number then EVERYDAY_POWER[number] = true end
	end

	-- (Its pick, and whether the game said for sure: a secret answer isn't kept.)
	local function Pick(id)
		-- (The Cooldown Manager says it has charges: Lava Burst at full charges
		-- shows no recharge.)
		if ns.cooldownChargeSpells[id] then return nil, true end
		local ok, base = pcall(GetSpellBaseCooldown or error, id)
		if not ok or Secret(base) then return nil, false end
		if type(base) ~= "number" or base > 0 then return nil, true end
		if C_Spell and C_Spell.GetSpellCharges then
			local okCharges, charges = pcall(C_Spell.GetSpellCharges, id)
			if not okCharges or Secret(charges) then return nil, false end
			-- (A spell with charges has its cooldown there, not in its base
			-- cooldown: Lava Burst. One charge and no recharge is no cooldown:
			-- Elemental Blast says 1/1.)
			if type(charges) == "table" then
				local most, recharge = charges.maxCharges, charges.cooldownDuration
				if Secret(most, recharge) then return nil, false end
				if type(most) ~= "number" or most > 1 then return nil, true end
				if type(recharge) == "number" and recharge > 0 then return nil, true end
			end
		end
		local GetCosts = (C_Spell and C_Spell.GetSpellPowerCost) or _G.GetSpellPowerCost
		if not GetCosts then return nil, true end
		local okCosts, costs = pcall(GetCosts, id)
		if not okCosts or Secret(costs) then return nil, false end
		for _, cost in ipairs(type(costs) == "table" and costs or {}) do
			local kind, need = cost.type, cost.minCost
			if type(need) == "nil" then need = cost.cost end
			if Secret(kind, need) then return nil, false end
			if type(kind) == "number" and not EVERYDAY_POWER[kind] and type(need) == "number" and need > 0 then
				return "power", true
			end
		end
		return "proc", true
	end

	-- (Asked a few times a second for each icon: kept until your spells or talents change.)
	local picks = {} -- spell ID -> its pick, or false for none
	local watcher = CreateFrame("Frame")
	for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
		"PLAYER_SPECIALIZATION_CHANGED" }) do
		pcall(watcher.RegisterEvent, watcher, event)
	end
	watcher:SetScript("OnEvent", function()
		wipe(picks)
		ns.ForgetCooldownNotes()
	end)

	function ns.SmartCooldownMode(id)
		if picks[id] ~= nil then return picks[id] or nil end
		local pick, sure = Pick(id)
		if sure then picks[id] = pick or false end
		return pick
	end

	-- Notes an icon's spell has charges, if the Cooldown Manager says (its
	-- cooldown info's charges); its pick is made again.
	function ns.NoteCooldownCharges(icon, id)
		if ns.cooldownChargeSpells[id] then return end
		local info = ns.IconCooldownInfo(icon)
		local charges = info and info.charges
		if Secret(charges) or charges ~= true then return end
		ns.cooldownChargeSpells[id] = true
		ns.cooldownChargeSpells[ns.BaseSpell(id)] = true
		for _, field in ipairs({ "spellID", "overrideSpellID" }) do
			local other = info[field]
			if type(other) == "number" and not Secret(other) then ns.cooldownChargeSpells[other] = true end
		end
		wipe(picks)
	end

	-- Smart Set's reasons for a spell, for /cine debug cooldowns.
	function ns.ReportSmartPick(id)
		local function Show(value)
			if Secret(value) then return "secret" end
			return tostring(value)
		end
		local ok, base = pcall(GetSpellBaseCooldown or error, id)
		local charges = "none"
		if C_Spell and C_Spell.GetSpellCharges then
			local okCharges, info = pcall(C_Spell.GetSpellCharges, id)
			if okCharges and type(info) == "table" then
				charges = ("%s/%s recharge %s"):format(Show(info.currentCharges), Show(info.maxCharges),
					Show(info.cooldownDuration))
			end
		end
		print(("    smart set: %s (base cooldown %s, charges %s, manager says charges %s)"):format(
			tostring(Pick(id)), ok and Show(base) or "?", charges, tostring(ns.cooldownChargeSpells[id] or false)))
	end
end

-- Whether a When Ready spell's icon shows: in fights, once it's nearly ready
-- (or when it can't tell), and with Resources ticked once you can pay for it.
local function IconShows(icon, id, now, power, earlyOn, seconds)
	local left, length = IconTimeLeft(icon, id, now)
	if left ~= nil and left > (ReadyEarly(earlyOn, seconds, length) or 0) then
		return false
	end
	return not power or ns.SpellHasPower(id)
end

-- Calls visit(icon, spell, bar) for each icon in the Cooldown Manager's spell
-- bars and its tracked buffs and bars (bar: the viewer's name). all: hidden
-- ones too (a buff that isn't up), for its page: the viewer's own icons in
-- use when it says, else every icon in it.
local EachCooldownIcon
do
-- (One Item function made once, not one for each bar on every pass: the walk
-- under way's visit and bar, kept aside while another walk runs inside it.)
local visiting, visitingBar
local function Item(part, kind)
	if kind == "item" then
		local id = ItemSpell(part)
		if id then
			iconSpell[part] = id
		end
		id = id or iconSpell[part]
		if id then
			ns.NoteCooldownIcon(part, id)
			visiting(part, id, visitingBar)
		end
	end
end
function EachCooldownIcon(visit, all)
	local outerVisit, outerBar = visiting, visitingBar
	visiting = visit
	for _, entry in ipairs(ns.managed) do
		local name, frame = entry.name, entry.frame
		if COOLDOWN_VIEWERS[name] or ns.COOLDOWN_BUFF_GROUPS[name] then
			visitingBar = name
			local pool = all and frame.itemFramePool
			if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
				for part in pool:EnumerateActive() do Item(part, "item") end
			else
				EachCooldownPart(frame, 3, Item, all)
			end
		end
	end
	visiting, visitingBar = outerVisit, outerBar
end
end

-- The spells in the Cooldown Manager now, for its page, as its settings
-- group them: the Essential bar's, the Utility bar's, the tracked buffs',
-- then the tracked bars', each in the order you set there (the icon's place
-- in its bar). Each is { id = spell ID, group = "essential", "utility",
-- "buffs" or "bars" }. (A spell can be in two: a cooldown and its buff.)
do
	local BAR_ORDER = { EssentialCooldownViewer = 1, UtilityCooldownViewer = 2, BuffIconCooldownViewer = 3,
		BuffBarCooldownViewer = 4 }
	function ns.CooldownManagerSpells()
		local found, listed = {}, {}
		EachCooldownIcon(function(icon, id, bar)
			id = ns.BaseSpell(id) -- (its settings go under it: ns.CooldownSpellMode)
			local group = ns.COOLDOWN_BAR_GROUPS[bar] or ns.COOLDOWN_BUFF_GROUPS[bar]
			listed[group] = listed[group] or {}
			if not listed[group][id] then
				listed[group][id] = true
				local place = icon.layoutIndex
				if Secret(place) or type(place) ~= "number" then place = math.huge end
				found[#found + 1] = { id = id, group = group, bar = BAR_ORDER[bar] or 5, place = place, seen = #found }
			end
		end, true)
		table.sort(found, function(a, b)
			if a.bar ~= b.bar then return a.bar < b.bar end
			if a.place ~= b.place then return a.place < b.place end
			return a.seen < b.seen
		end)
		return found
	end
end

-- The Cooldown Manager page's Show keybinds (db.cooldownKeybinds): each
-- spell's key in the top right corner of its icon in the Essential and
-- Utility bars, as on an action button. The key is the first action bar
-- button's holding the spell (or a macro casting it) that has one bound,
-- the main bar first. The bars are read again when a binding, a button or
-- the stance changes; the icons are looked at twice a second while it's on.
do
	local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer" }
	-- Each bar's first action slot and its buttons' binding (the main bar's
	-- slot moves with a stance or form: below).
	local SLOT_BARS = {
		{ 1, "ACTIONBUTTON" }, { 61, "MULTIACTIONBAR1BUTTON" }, { 49, "MULTIACTIONBAR2BUTTON" },
		{ 25, "MULTIACTIONBAR3BUTTON" }, { 37, "MULTIACTIONBAR4BUTTON" }, { 145, "MULTIACTIONBAR5BUTTON" },
		{ 157, "MULTIACTIONBAR6BUTTON" }, { 169, "MULTIACTIONBAR7BUTTON" },
	}
	local keyOf = {} -- spell ID -> its key text
	local labels = setmetatable({}, { __mode = "k" }) -- icon -> its key's font string
	local dirty = true
	local watcher = CreateFrame("Frame")

	-- The plain number a call gives, or nil.
	local function Number(func, ...)
		if type(func) ~= "function" then return nil end
		local ok, value = pcall(func, ...)
		if ok and not Secret(value) and type(value) == "number" and value > 0 then return value end
	end

	local function Store(id, text)
		if id and not keyOf[id] then keyOf[id] = text end
	end

	local function Rebuild()
		dirty = false
		wipe(keyOf)
		local offset = Number(GetBonusBarOffset)
		for _, bar in ipairs(SLOT_BARS) do
			local first, command = bar[1], bar[2]
			if command == "ACTIONBUTTON" and offset then
				first = 72 + (offset - 1) * 12 + 1
			end
			for i = 1, 12 do
				local ok, kind, id = pcall(GetActionInfo, first + i - 1)
				local key = ok and not Secret(kind, id) and GetBindingKey(command .. i)
				if key and (kind == "spell" or kind == "macro") then
					if kind == "macro" then
						id = Number(GetMacroSpell, id) or id
					end
					if type(id) == "number" then
						local text = GetBindingText and GetBindingText(key, true) or key
						-- (The icon may show the spell's base or what it's
						-- turned into now.)
						Store(id, text)
						Store(Number(FindBaseSpellByID, id), text)
						Store(C_Spell and Number(C_Spell.GetOverrideSpell, id), text)
					end
				end
			end
		end
	end

	local function Label(icon)
		local text = labels[icon]
		if not text then
			local ok, holder = pcall(CreateFrame, "Frame", nil, icon)
			if not ok then return nil end
			holder:SetAllPoints()
			holder:SetFrameLevel(icon:GetFrameLevel() + 10)
			text = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
			text:SetPoint("TOPRIGHT", -2, -3)
			text:SetJustifyH("RIGHT")
			labels[icon] = text
		end
		return text
	end

	local function ShowIcon(icon)
		if IsForbidden(icon) then return end
		local id = ItemSpell(icon) or iconSpell[icon]
		local key = id and keyOf[id]
		if key then
			local text = Label(icon)
			if text then
				text:SetText(key)
				text:Show()
			end
		elseif labels[icon] then
			labels[icon]:Hide()
		end
	end

	local function Update()
		if not (ns.db.cooldownKeybinds and ns.PageOn("handleCooldowns")) then
			for _, text in pairs(labels) do text:Hide() end
			return
		end
		if dirty then Rebuild() end
		for _, name in ipairs(VIEWERS) do
			local viewer = _G[name]
			local pool = viewer and viewer.itemFramePool
			if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
				for icon in pool:EnumerateActive() do ShowIcon(icon) end
			elseif viewer then
				EachCooldownPart(viewer, 3, function(part, kind)
					if kind == "item" then ShowIcon(part) end
				end, true)
			end
		end
	end

	local since = 0
	watcher:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < 0.5 then return end
		since = 0
		Update()
	end)
	watcher:Hide()
	watcher:SetScript("OnEvent", function(_, event)
		dirty = true
		if event == "PLAYER_ENTERING_WORLD" then ns.ApplyCooldownKeybinds() end
	end)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED",
		"UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "UPDATE_MACROS", "SPELLS_CHANGED" }) do
		pcall(watcher.RegisterEvent, watcher, event)
	end

	-- Starts or stops it as the page says (its tick box).
	function ns.ApplyCooldownKeybinds()
		if not ns.db then return end
		dirty = true
		Update()
		watcher:SetShown(ns.db.cooldownKeybinds and true or false)
	end
end

-- /cine debug cdm: what the game says about each Cooldown Manager spell -
-- its cooldown (base, charges, now), what it costs and in which resource,
-- and whether you can pay - plain, secret or missing. Run in and out of fights.
do
	local function Show(ok, value)
		if not ok then return "error" end
		if Secret(value) then return "secret" end
		return tostring(value)
	end

	local POWER_NAMES = {}
	for name, number in pairs(Enum and Enum.PowerType or {}) do
		POWER_NAMES[number] = name
	end

	local function Costs(id)
		local GetCosts = (C_Spell and C_Spell.GetSpellPowerCost) or _G.GetSpellPowerCost
		if not GetCosts then return "no cost check here" end
		local ok, costs = pcall(GetCosts, id)
		if not ok then return "error" end
		if Secret(costs) then return "secret" end
		if type(costs) ~= "table" or #costs == 0 then return "none" end
		local parts = {}
		for _, cost in ipairs(costs) do
			local kind = cost.type
			local name = (not Secret(kind) and POWER_NAMES[kind]) or Show(true, cost.name)
			parts[#parts + 1] = ("%s (type %s) %s, min %s, %s%%%s"):format(name, Show(true, kind),
				Show(true, cost.cost), Show(true, cost.minCost), Show(true, cost.costPercent),
				type(cost.requiredAuraID) == "number" and not Secret(cost.requiredAuraID) and cost.requiredAuraID > 0
					and (", needs aura " .. Show(true, cost.requiredAuraID)) or "")
		end
		return table.concat(parts, " + ")
	end

	local function Charges(id)
		if not (C_Spell and C_Spell.GetSpellCharges) then return "no check" end
		local ok, info = pcall(C_Spell.GetSpellCharges, id)
		if not ok then return "error" end
		if Secret(info) then return "secret" end
		if type(info) ~= "table" then return "none" end
		return Show(true, info.currentCharges) .. "/" .. Show(true, info.maxCharges)
	end

	local function CooldownNow(id)
		if not (C_Spell and C_Spell.GetSpellCooldown) then return "no check" end
		local ok, info = pcall(C_Spell.GetSpellCooldown, id)
		if not ok then return "error" end
		if Secret(info) then return "secret" end
		if type(info) ~= "table" then return "none" end
		return ("start %s, %s s"):format(Show(true, info.startTime), Show(true, info.duration))
	end

	function ns.PrintCooldownManagerDebug()
		local power = { pcall(UnitPowerType, "player") }
		local secrets, secret = _G.C_Secrets, "no such check"
		ns.Print(("client: %s; in combat: %s; your power: %s (type %s)"):format(
			ns.isRetail and "retail" or "Forever", tostring(InCombatLockdown() and true or false),
			Show(power[1], power[3]), Show(power[1], power[2])))
		local spells = ns.CooldownManagerSpells()
		if #spells == 0 then
			ns.Print("no spells found in the Cooldown Manager (is it on, in Edit Mode or Options > Gameplay?)")
			return
		end
		local GetName = (C_Spell and C_Spell.GetSpellName) or _G.GetSpellInfo
		local IsUsable = (C_Spell and C_Spell.IsSpellUsable) or _G.IsUsableSpell
		for _, spell in ipairs(spells) do
			local id = spell.id
			local okName, name = pcall(GetName, id)
			local okBase, base = pcall(GetSpellBaseCooldown or error, id)
			if secrets and secrets.ShouldSpellCooldownBeSecret then
				secret = Show(pcall(secrets.ShouldSpellCooldownBeSecret, id))
			end
			ns.Print(("%s %s (%s): base cd %s ms, charges %s, now %s, cd secret: %s"):format(spell.group,
				Show(okName, name), id, Show(okBase, base), Charges(id), CooldownNow(id), secret))
			local usable = IsUsable and { pcall(IsUsable, id) } or { false }
			ns.Print(("  costs: %s; usable %s, short of power %s"):format(Costs(id),
				Show(usable[1], usable[2]), Show(usable[1], usable[3])))
		end
	end
end

-- Every icon faded here back to full (and back in its place).
local function ReleaseReadyIcons()
	wipe(readyTargets)
	for icon in pairs(readyAlpha) do
		if not IsForbidden(icon) then
			icon:SetAlpha(1)
		end
		readyAlpha[icon] = nil
	end
	ns.UncenterCooldownIcons()
end

-- A bar's Close the gaps (ns.CooldownGroupCentered; the Essential and
-- Utility bars): the icons it shows sit together in their
-- order, centered on the bar's rows (or columns), instead of faded ones
-- leaving gaps; the faded ones wait after the last shown. Each icon's place
-- in the game's own layout is caught as the game sets it (a hook on the
-- icon's SetPoint: comparing with where it was last put here missed some,
-- leaving the Essential bar's places from two different layouts), and the
-- icon goes straight back where it showed, on to its new goal next pass.
-- Not in Edit Mode. (The others slide; one coming back from faded is put
-- straight in its place.)
do
	local SLIDE_RATE = 12 -- (share of the distance left, a second)
	local slotOf = setmetatable({}, { __mode = "k" }) -- icon -> the game's place: { point, relativeTo, relativePoint, x, y }
	local putAt = setmetatable({}, { __mode = "k" }) -- icon -> { x, y }, where it was last put here
	local goal = setmetatable({}, { __mode = "k" }) -- icon -> { x, y }, where it's going
	local placeOf = setmetatable({}, { __mode = "k" }) -- icon -> its place in its bar (layoutIndex)
	local watched = setmetatable({}, { __mode = "k" }) -- icon -> true once its SetPoint is hooked
	local barIcons, lineCross, wanted, shownIn = {}, {}, {}, {}
	local putting = false -- (our own SetPoint: not the game's place)

	local function Movable(icon)
		return not IsForbidden(icon)
			and not (InCombatLockdown() and icon.IsProtected and ns.Flag(icon:IsProtected()))
	end

	-- Reads an icon's one point into its slot; false if it can't be read.
	local function ReadPoint(icon)
		local okCount, count = pcall(icon.GetNumPoints, icon)
		if not okCount or Secret(count) or count ~= 1 then return false end
		local ok, point, relativeTo, relativePoint, x, y = pcall(icon.GetPoint, icon, 1)
		if not ok or Secret(point, relativeTo, relativePoint, x, y) or type(x) ~= "number" or type(y) ~= "number" then
			return false
		end
		local slot = slotOf[icon] or {}
		slot[1], slot[2], slot[3], slot[4], slot[5] = point, relativeTo, relativePoint, x, y
		slotOf[icon] = slot
		return true
	end

	local function Put(icon, x, y)
		local slot = slotOf[icon]
		if not slot or not Movable(icon) then return end
		putting = true
		icon:SetPoint(slot[1], slot[2], slot[3], x, y)
		putting = false
		local at = putAt[icon] or {}
		at[1], at[2] = x, y
		putAt[icon] = at
	end

	-- The game placed an icon: that's its slot now; one that was put here
	-- goes straight back where it showed.
	local function GameSetPoint(icon)
		if putting or not ReadPoint(icon) then return end
		local at = putAt[icon]
		putAt[icon] = nil
		if at and goal[icon] then Put(icon, at[1], at[2]) end
	end

	-- The game's place for an icon, or nil. (Before its hook, read while it's
	-- not been put here.)
	local function ReadSlot(icon)
		if not watched[icon] then
			if not putAt[icon] then ReadPoint(icon) end
			if slotOf[icon] and type(icon.SetPoint) == "function" then
				watched[icon] = true
				hooksecurefunc(icon, "SetPoint", GameSetPoint)
			end
		end
		return slotOf[icon]
	end

	local function PutBack(icon)
		ReadSlot(icon)
		local slot = slotOf[icon]
		if slot and putAt[icon] and Movable(icon) then
			putting = true
			icon:SetPoint(slot[1], slot[2], slot[3], slot[4], slot[5])
			putting = false
		end
		putAt[icon], goal[icon] = nil, nil
	end

	local function SetGoal(icon, x, y)
		local at = goal[icon] or {}
		at[1], at[2] = x, y
		goal[icon] = at
	end

	local function ByPlace(a, b)
		local placeA, placeB = placeOf[a], placeOf[b]
		if placeA ~= placeB then return placeA < placeB end
		local slotA, slotB = slotOf[a], slotOf[b]
		if slotA[5] ~= slotB[5] then return slotA[5] > slotB[5] end
		return slotA[4] < slotB[4]
	end

	-- A bar's icons (each with its game place) to their goals.
	local function PlaceBar(icons)
		table.sort(icons, ByPlace)
		local first, second = slotOf[icons[1]], slotOf[icons[2]]
		local stepX, stepY = second[4] - first[4], second[5] - first[5]
		local across = math.abs(stepY) < 0.5 -- (side by side: rows; else columns)
		-- The game's lines (rows or columns), by where each sits across them.
		wipe(lineCross)
		local lineLength, count = 0, 0
		for _, icon in ipairs(icons) do
			local slot = slotOf[icon]
			local cross = across and slot[5] or slot[4]
			if #lineCross == 0 or math.abs(cross - lineCross[#lineCross]) > 0.5 then
				lineCross[#lineCross + 1] = cross
			end
			if #lineCross == 1 then lineLength = lineLength + 1 end
			shownIn[icon] = readyTargets[icon] ~= 0
			if shownIn[icon] then count = count + 1 end
		end
		local function Goal(icon, line, along)
			local cross = lineCross[line + 1] or lineCross[#lineCross]
			if across then
				SetGoal(icon, first[4] + along * stepX, cross)
			else
				SetGoal(icon, cross, first[5] + along * stepY)
			end
		end
		local lastLine = math.max(0, math.floor((count - 1) / lineLength))
		local inLast = count - lastLine * lineLength
		-- The faded ones stay inside the game's own grid: the game sizes the
		-- bar to its icons when it lays it out again (centered on its anchor),
		-- so ones queued past its edge widened it and pulled the shown ones
		-- off center. First the game's lines after the last shown, then the
		-- whole places either side of the shown in theirs; any left over
		-- share the first faded one's place (or, with none, go just after
		-- the shown: on one line that's still inside the bar's width).
		local below = count == 0 and 0 or math.max(0, #lineCross - 1 - lastLine) * lineLength
		local start = (lineLength - inLast) / 2
		local side = math.floor(start)
		local function FadedGoal(icon, k)
			if count == 0 then
				Goal(icon, math.floor(k / lineLength), k % lineLength)
			elseif k < below then
				Goal(icon, lastLine + 1 + math.floor(k / lineLength), k % lineLength)
			elseif k - below < side then
				Goal(icon, lastLine, start + inLast + (k - below))
			elseif k - below < 2 * side then
				Goal(icon, lastLine, start - 1 - (k - below - side))
			elseif below + 2 * side > 0 then
				FadedGoal(icon, 0)
			else
				Goal(icon, lastLine, start + inLast + (k - below - 2 * side))
			end
		end
		local shown, faded = 0, 0
		for _, icon in ipairs(icons) do
			wanted[icon] = true
			if shownIn[icon] then
				local line = math.floor(shown / lineLength)
				local inLine = math.min(lineLength, count - line * lineLength)
				Goal(icon, line, shown % lineLength + (lineLength - inLine) / 2)
				shown = shown + 1
			else
				FadedGoal(icon, faded)
				faded = faded + 1
			end
		end
		wipe(shownIn)
	end

	local function Collect(icon, _, bar)
		local group = ns.COOLDOWN_BAR_GROUPS[bar]
		if group and ns.CooldownGroupCentered(group) and ReadSlot(icon) then
			local place = icon.layoutIndex
			if Secret(place) or type(place) ~= "number" then place = math.huge end
			placeOf[icon] = place
			barIcons[bar] = barIcons[bar] or {}
			table.insert(barIcons[bar], icon)
		end
	end

	-- The game just laid a bar out again (maybe with new icons: it reuses
	-- them for other spells; their places were caught by GameSetPoint): new
	-- goals the same frame.
	local hooked, relaying = {}, false
	local function LaidOut()
		if relaying then return end
		relaying = true
		ns.CenterCooldownIcons()
		relaying = false
	end

	local function HookBars()
		for name in pairs(ns.COOLDOWN_BAR_GROUPS) do
			local viewer = _G[name]
			if not hooked[name] and type(viewer) == "table" and type(viewer.Layout) == "function" then
				hooked[name] = true
				hooksecurefunc(viewer, "Layout", LaidOut)
			end
		end
	end

	-- Each pass of the When Ready check: every centered bar's goals.
	function ns.CenterCooldownIcons()
		local on = false
		for _, group in pairs(ns.COOLDOWN_BAR_GROUPS) do
			on = on or ns.CooldownGroupCentered(group)
		end
		if not on and not next(putAt) then return end
		if on then HookBars() end
		wipe(wanted)
		local editMode = _G.EditModeManagerFrame
		if on and not (editMode and editMode.IsEditModeActive and ns.Flag(editMode:IsEditModeActive())) then
			for _, icons in pairs(barIcons) do wipe(icons) end
			EachCooldownIcon(Collect)
			for _, icons in pairs(barIcons) do
				if #icons > 1 then PlaceBar(icons) end
			end
		end
		for icon in pairs(putAt) do
			if not wanted[icon] then PutBack(icon) end
		end
		for icon in pairs(goal) do
			if not wanted[icon] then goal[icon] = nil end
		end
	end

	-- Each frame: the icons on their way.
	function ns.SlideCooldownIcons(elapsed)
		for icon, at in pairs(goal) do
			local was = putAt[icon]
			local slot = ReadSlot(icon)
			if was and not putAt[icon] then
				goal[icon] = nil -- (the game laid it out again: placed on the next pass)
			elseif slot then
				local x, y = slot[4], slot[5]
				if was then x, y = was[1], was[2] end
				local alpha = readyAlpha[icon]
				local faint = alpha and alpha < 0.2
				-- (One fading out waits where it is till it's nearly gone,
				-- rather than sliding across the others.)
				if (x ~= at[1] or y ~= at[2]) and (faint or readyTargets[icon] ~= 0) then
					local share = faint and 1 or math.min(1, elapsed * SLIDE_RATE)
					x, y = x + (at[1] - x) * share, y + (at[2] - y) * share
					if math.abs(at[1] - x) < 0.5 and math.abs(at[2] - y) < 0.5 then x, y = at[1], at[2] end
					Put(icon, x, y)
				end
			end
		end
	end

	function ns.UncenterCooldownIcons()
		for icon in pairs(putAt) do PutBack(icon) end
		wipe(goal)
	end

	-- /cine debug cooldowns: what Close the gaps sees in each bar.
	function ns.ReportCenteredIcons()
		local function Num(value)
			if Secret(value) then return "secret" end
			return type(value) == "number" and ("%.1f"):format(value) or tostring(value)
		end
		local editMode = _G.EditModeManagerFrame
		ns.Print(("close the gaps: edit mode %s, in combat %s"):format(
			tostring(editMode and editMode.IsEditModeActive and ns.Flag(editMode:IsEditModeActive()) or false),
			tostring(InCombatLockdown())))
		for bar, group in pairs(ns.COOLDOWN_BAR_GROUPS) do
			local viewer = _G[bar]
			local geometry = "?"
			if type(viewer) == "table" and viewer.GetCenter then
				local okC, cx, cy = pcall(viewer.GetCenter, viewer)
				local okW, width = pcall(viewer.GetWidth, viewer)
				local okS, scale = pcall(viewer.GetEffectiveScale, viewer)
				local okP, point, relativeTo, relativePoint, px, py = pcall(viewer.GetPoint, viewer, 1)
				local relName = okP and not Secret(relativeTo) and type(relativeTo) == "table" and relativeTo.GetName
					and relativeTo:GetName() or "?"
				geometry = ("center %s,%s width %s scale %s | %s on %s %s %s,%s | stride %s, horizontal %s"):format(
					okC and Num(cx) or "?", okC and Num(cy) or "?", okW and Num(width) or "?", okS and Num(scale) or "?",
					okP and tostring(point) or "?", tostring(relName), okP and tostring(relativePoint) or "?",
					okP and Num(px) or "?", okP and Num(py) or "?",
					Num(viewer.stride or viewer.iconLimit), tostring(viewer.isHorizontal))
			end
			print(("  %s (%s): on=%s, viewer %s, Layout hooked %s"):format(bar, group,
				tostring(ns.CooldownGroupCentered(group)), type(viewer),
				tostring(hooked[bar] or false)))
			print("    " .. geometry)
		end
		local count = 0
		EachCooldownIcon(function(icon, id, bar)
			local group = ns.COOLDOWN_BAR_GROUPS[bar]
			if not group then return end
			count = count + 1
			if count > 30 then return end
			local okCount, points = pcall(icon.GetNumPoints, icon)
			local ok, point, relativeTo, _, x, y = pcall(icon.GetPoint, icon, 1)
			local slot, at, to = slotOf[icon], putAt[icon], goal[icon]
			local relName = ok and not Secret(relativeTo) and type(relativeTo) == "table" and relativeTo.GetName
				and relativeTo:GetName() or "?"
			local okC, cx = pcall(icon.GetCenter, icon)
			print(("  %s spell=%s place=%s points=%s now %s %s,%s on %s screen x %s | slot %s | put %s | goal %s | target %s, movable %s")
				:format(group, tostring(id), Num(icon.layoutIndex), okCount and Num(points) or "?",
				ok and tostring(point) or "?", ok and Num(x) or "?", ok and Num(y) or "?", tostring(relName),
				okC and Num(cx) or "?",
				slot and (Num(slot[4]) .. "," .. Num(slot[5])) or "none",
				at and (Num(at[1]) .. "," .. Num(at[2])) or "none",
				to and (Num(to[1]) .. "," .. Num(to[2])) or "none",
				tostring(readyTargets[icon]), tostring(Movable(icon))))
		end)
		if count == 0 then print("  (no Essential or Utility icons found)") end
	end
end

-- The personal resource bars' power half (personalPower, above). The bars are
-- found inside the personal bars by the fields each client gives them: in
-- the Edit Mode frame (retail's, and Forever's where it has one), or on your
-- own nameplate's unit frame or the nameplate driver, which parents them to
-- that plate (not when it puts combo points on your target's plate: those
-- are left alone).
-- /cine debug plates lists what's found.
do
	local POWER_FIELDS = { "PowerBar", "AlternatePowerBar", "ClassFrameContainer", "powerBar", "classPowerBar" }
	local DRIVER_FIELDS = { "classNamePlatePowerBar", "classNamePlateAlternatePowerBar", "classNamePlateMechanicFrame" }
	local held = personalPower.held -- [bar] = the pass it was last faded on

	-- Where the personal bars are: the Edit Mode frame, and (Forever) your
	-- own nameplate. Either can be missing.
	local function Roots()
		local plate = personalPower.healthStandIn and C_NamePlate and C_NamePlate.GetNamePlateForUnit
			and C_NamePlate.GetNamePlateForUnit("player")
		return _G.PersonalResourceDisplayFrame, plate or nil
	end

	local function Open(root)
		return root and not (root.IsForbidden and root:IsForbidden()) and root or nil
	end

	local function Usable(frame)
		return type(frame) == "table" and frame.SetAlpha and frame.SetIgnoreParentAlpha and frame.GetParent
			and not (frame.IsForbidden and frame:IsForbidden())
	end

	-- Whether a frame sits inside the personal bars (a few parents up at most).
	local function Inside(frame, root)
		local parent = frame:GetParent()
		for _ = 1, 6 do
			if parent == root then
				return true
			elseif not parent then
				return false
			end
			parent = parent:GetParent()
		end
		return false
	end

	-- Calls fn(bar, root, ...) for each power bar found on owner's fields.
	local function EachOn(owner, fields, root, fn, ...)
		if type(owner) ~= "table" then
			return
		end
		for _, field in ipairs(fields) do
			local bar = owner[field]
			if Usable(bar) and Inside(bar, root) then
				fn(bar, root, ...)
			end
		end
	end

	-- Fields not in the lists above, found by name (power, mana, class
	-- resources), so a client naming them otherwise is still covered. Not the
	-- elite dragon (classification), nor anything holding the health bar.
	local function NamedLikePower(field)
		if type(field) ~= "string" or field:lower():find("classification") then
			return false
		end
		local lower = field:lower()
		return lower:find("power") or lower:find("mana") or lower:find("class") or lower:find("combo")
			or lower:find("rune") or lower:find("resource")
	end

	local function HoldsHealth(frame, root)
		local health = root.healthBar or (root.UnitFrame and root.UnitFrame.healthBar) or root.HealthBarsContainer
			or (root.UnitFrame and root.UnitFrame.HealthBarsContainer)
		if type(health) ~= "table" or not health.GetParent then
			return false
		end
		return health == frame or Inside(health, frame)
	end

	-- The bars found ([bar] = the root it's in), looked for again when the
	-- personal bars change (Forever's plate comes and goes) or every second
	-- (bars made later).
	local found, foundFrame, foundPlate, foundPass = {}, nil, nil, -math.huge
	local function Add(bar, root)
		if not found[bar] and not HoldsHealth(bar, root) then
			found[bar] = root
		end
	end
	local function AddNamed(owner, root)
		if type(owner) ~= "table" then
			return
		end
		for field, bar in pairs(owner) do
			if NamedLikePower(field) and Usable(bar) and Inside(bar, root) then
				Add(bar, root)
			end
		end
	end
	local function FindIn(root)
		if not root then
			return
		end
		EachOn(root, POWER_FIELDS, root, Add)
		EachOn(root.UnitFrame, POWER_FIELDS, root, Add)
		EachOn(_G.NamePlateDriverFrame, DRIVER_FIELDS, root, Add)
		AddNamed(root, root)
		AddNamed(root.UnitFrame, root)
		AddNamed(_G.NamePlateDriverFrame, root)
	end

	local function EachPowerBar(fn, ...)
		local frame, plate = Roots()
		frame, plate = Open(frame), Open(plate)
		if frame ~= foundFrame or plate ~= foundPlate or personalPower.pass - foundPass > 60 then
			wipe(found)
			foundFrame, foundPlate, foundPass = frame, plate, personalPower.pass
			FindIn(frame)
			FindIn(plate)
		end
		for bar, root in pairs(found) do
			if Usable(bar) and Inside(bar, root) then
				fn(bar, root, ...)
			end
		end
	end

	local function Hold(bar, _, alpha)
		if not held[bar] then
			bar:SetIgnoreParentAlpha(true)
		end
		held[bar] = personalPower.pass
		bar:SetAlpha(alpha)
	end

	local function LetGo(bar)
		held[bar] = nil
		bar:SetIgnoreParentAlpha(false)
		bar:SetAlpha(1)
	end

	-- Each tick, after the fade: while either row is faded the power bars
	-- take their own row's alpha; with both up they're the game's again.
	function personalPower.Apply()
		personalPower.pass = personalPower.pass + 1
		if personalPower.level < 1 or personalPower.health < 1 then
			EachPowerBar(Hold, personalPower.level)
		end
		-- (Bars not found this time, or all of them with both rows up.)
		for bar, pass in pairs(held) do
			if pass ~= personalPower.pass then
				LetGo(bar)
			end
		end
	end

	-- For /cine debug plates: the two rows' fades and the power bars found.
	function ns.DescribePersonalPower()
		if not personalPower.standIn then
			return "no personal resource bars on this client"
		end
		local names = {}
		-- (A secret alpha or name formats to a secret string, which concat refuses.)
		local function Plain(ok, value)
			return ok and not (issecretvalue and issecretvalue(value)) and value ~= nil
		end
		EachPowerBar(function(bar)
			local okName, name = pcall(bar.GetDebugName, bar)
			local okAlpha, alpha = pcall(bar.GetAlpha, bar)
			names[#names + 1] = (Plain(okName, name) and tostring(name):match("[^.]*%.?[^.]+$") or "?") .. " "
				.. (Plain(okAlpha, alpha) and ("%.2f"):format(alpha) or (okAlpha and "secret" or "?"))
				.. (held[bar] and " (ours)" or "")
		end)
		-- (And the nameplate driver's bars wherever they are, by their parents.)
		local driver = {}
		for field, bar in pairs(type(_G.NamePlateDriverFrame) == "table" and _G.NamePlateDriverFrame or {}) do
			if NamedLikePower(field) and type(bar) == "table" and bar.GetParent then
				local okParent, parent = pcall(function() return bar:GetParent():GetDebugName() end)
				driver[#driver + 1] = field .. " in " .. (Plain(okParent, parent) and tostring(parent) or "?")
			end
		end
		local frame, plate = Roots()
		return ("health row %.2f, resource row %.2f, mana row %.2f, frame %s, plate %s, bars: %s; driver: %s"):format(
			personalPower.health, personalPower.level, personalPower.mana, frame and (ns.Flag(frame:IsShown()) and "shown" or "hidden") or "none",
			plate and "up" or "none", #names > 0 and table.concat(names, ", ") or "NONE found",
			#driver > 0 and table.concat(driver, ", ") or "none")
	end
end

-- The master switches changing (on their pages, or with a profile): frames
-- no longer handled are let go, and switched back on they're picked up and
-- fade from now. Looked at each frame.
local switchesWere = {}
local function SyncSwitches()
	local changed, turnedOn = false, false
	for _, key in ipairs(ns.HANDLE_SWITCHES) do
		local on = ns.db[key] and true or false
		if switchesWere[key] ~= nil and switchesWere[key] ~= on then
			changed = true
			turnedOn = turnedOn or on
		end
		switchesWere[key] = on
	end
	if not changed then
		return
	end
	for i = #ns.managed, 1, -1 do
		local entry = ns.managed[i]
		if not GroupHandled(entry.group) then
			RemoveFrame(entry.frame)
		end
	end
	if not GroupHandled("cooldowns") or not ns.PageOn("handleCooldowns") then
		ReleaseReadyIcons() -- (the "Only when ready in combat" icons)
	end
	if not GroupHandled("prd") then
		ns.SetPersonalPlateAlpha(1) -- (Forever's: your own nameplate)
	end
	if turnedOn then
		ns.BuildManagedList()
	end
end
ns.SyncSwitches = SyncSwitches

local UpdateReadyOnly
do
-- (Each pass's icons looked at by one function made once, with the pass's
-- time and whether you're in a fight.)
local passNow, passInCombat
local function ReadyTarget(icon, id, bar)
	local buffGroup = ns.COOLDOWN_BUFF_GROUPS[bar]
	if buffGroup then
		if not ns.CooldownBuffShows(ns.CooldownBuffMode(id, buffGroup), passInCombat) then
			readyTargets[icon] = 0
		end
		return
	end
	local mode, _, power, earlyOn, seconds = ns.CooldownSpellMode(id, ns.COOLDOWN_BAR_GROUPS[bar])
	if mode == "ready" then
		readyTargets[icon] = (passInCombat and IconShows(icon, id, passNow, power, earlyOn, seconds)) and 1 or 0
	elseif mode == "recharge" then
		local left = IconTimeLeft(icon, id, passNow) -- (not knowing: faded)
		readyTargets[icon] = (left and left > 0) and 1 or 0
	elseif mode == "proc" then
		readyTargets[icon] = ns.SpellGlowing(id, icon) and 1 or 0
	end
end
function UpdateReadyOnly(elapsed, now)
	SyncSwitches()
	if not GroupHandled("cooldowns") or not ns.PageOn("handleCooldowns") then
		return
	end
	if now - readyCheckedAt >= 0.1 then
		readyCheckedAt = now
		wipe(readyTargets)
		local db = ns.db
		local any = next(db.cooldownReadyOnly) or next(db.cooldownRechargeOnly) or next(db.cooldownProcOnly)
			or next(db.cooldownBuffMode)
		for _, group in pairs(ns.COOLDOWN_BAR_GROUPS) do
			any = any or ns.CooldownGroupSettings(group) ~= "always"
		end
		for _, group in pairs(ns.COOLDOWN_BUFF_GROUPS) do
			any = any or ns.CooldownGroupSettings(group) ~= "always"
		end
		if any then
			passNow, passInCombat = now, InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
			EachCooldownIcon(ReadyTarget)
		end
		ns.CenterCooldownIcons()
	end
	ns.SlideCooldownIcons(elapsed)
	for icon, target in pairs(readyTargets) do
		if target < 1 and not readyAlpha[icon] then
			readyAlpha[icon] = 1
		end
	end
	-- (Re-applied while faded, in case the game sets it; back to full, and
	-- unticked or reused for another spell, it's left alone again.)
	for icon, alpha in pairs(readyAlpha) do
		local target = readyTargets[icon] or 1
		alpha = ns.Approach(alpha, target, elapsed, target > alpha and READY_FADE_IN or READY_FADE_OUT)
		if not IsForbidden(icon) then
			icon:SetAlpha(alpha)
		end
		readyAlpha[icon] = alpha < 1 and alpha or nil
	end
end
end
UpdateReadyOnly = ns.Profiled("UpdateReadyOnly", UpdateReadyOnly)

-- /cine debug cooldowns: what the Cooldown Manager check sees.
function ns.ReportCooldowns()
	local now = GetTime()
	local any = false
	local function Show(value)
		if Secret(value) then return "secret" end
		return type(value) == "number" and ("%.1f"):format(value) or tostring(value)
	end
	EachCooldownFrame(function(entry, frame)
		any = true
		local ok, shown = pcall(frame.IsShown, frame)
		ns.Print(("%s: shown=%s"):format(entry.name or entry.group, ok and Show(shown) or "?"))
		local count = 0
		EachCooldownPart(frame, 3, function(part, kind)
			count = count + 1
			if count > 20 then return end
			if kind == "item" then
				local id = ItemSpell(part)
				local start, duration
				if id then start, duration = SpellCooldown(id) end
				print(("  icon spell=%s cooldown %s"):format(tostring(id), start
					and ("%.1fs left of %.1fs"):format(math.max(0, start + duration - now), duration)
					or "unreadable"))
				local mode, own, power, earlyOn, seconds
				if id then
					ns.NoteCooldownIcon(part, id)
					local base = ns.BaseSpell(id)
					if base ~= id then print(("    turned into from %d (its settings go under it)"):format(base)) end
					ns.ReportSmartPick(base)
					mode, own, power, earlyOn, seconds = ns.CooldownSpellMode(id, ns.COOLDOWN_BAR_GROUPS[entry.name])
				end
				local from = own and "" or " (its group's)"
				if mode == "ready" then
					local left, length = IconTimeLeft(part, id, now)
					local early = ReadyEarly(earlyOn, seconds, length)
					local cast = lastCastOf[id]
					print(("    when ready%s: %s, back %s early (last cast %s, cooldown %s)"):format(from,
						left == nil and "can't tell, shown" or (left > 0 and ("%.0fs left"):format(left) or "ready"),
						early and ("%.0fs"):format(early) or "?",
						cast and ("%.0fs ago"):format(now - cast) or "not seen",
						length and ("%.0fs"):format(length) or "unknown"))
					if power then
						print(("    resources: %s"):format(ns.SpellHasPower(id) and "enough" or "not enough"))
					end
				elseif mode == "recharge" then
					local left = IconTimeLeft(part, id, now)
					print(("    while recharging%s: %s"):format(from, left == nil and "can't tell, faded"
						or (left > 0 and ("%.0fs left, shown"):format(left) or "ready, faded")))
				elseif mode == "proc" then
					print(("    when it procs%s: %s"):format(from,
						ns.SpellGlowing(id, part) and "glowing, shown" or "no glow, faded"))
				end
			else
				local start, duration = SwipeTimes(part)
				print(("  swipe %s"):format(start
					and ("%.1fs left of %.1fs"):format(math.max(0, start + duration - now), duration)
					or "unreadable"))
			end
		end)
		if count == 0 then print("  (no icons or swipes found)") end
	end)
	-- The tracked buffs and bars: each icon in use (a buff not up too) and its mode.
	local inCombat = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	for _, entry in ipairs(ns.managed) do
		local group = ns.COOLDOWN_BUFF_GROUPS[entry.name]
		if group then
			any = true
			local ok, shown = pcall(entry.frame.IsShown, entry.frame)
			ns.Print(("%s: shown=%s, in a fight=%s, %s's mode %s"):format(entry.name, ok and Show(shown) or "?",
				tostring(inCombat), group, (ns.CooldownGroupSettings(group))))
		end
	end
	local count = 0
	EachCooldownIcon(function(icon, id, bar)
		local group = ns.COOLDOWN_BUFF_GROUPS[bar]
		if not group then return end
		count = count + 1
		if count > 30 then return end
		local mode, own = ns.CooldownBuffMode(id, group)
		local okShown, shown = pcall(icon.IsShown, icon)
		print(("  %s spell=%s up=%s mode=%s%s -> %s, alpha %s"):format(group, tostring(id),
			okShown and Show(shown) or "?", mode, own and "" or " (its group's)",
			ns.CooldownBuffShows(mode, inCombat) and "shown" or "faded", Show(readyAlpha[icon] or 1)))
	end, true)
	if not any then
		ns.Print("no Cooldown Manager frames found among the faded frames")
	end
	ns.ReportCenteredIcons()
	cooldownCheckedAt = 0
	ns.Print(("recharging now: essential %s, utility %s"):format(tostring(AnyCooldownRecharging(now, "essential")),
		tostring(AnyCooldownRecharging(now, "utility"))))
end

-- /cine debug frame <text>: how the faded frames with <text> in their name,
-- or their fade group (for unnamed ones), stand (matched ignoring case: slash
-- commands come lowercased).
function ns.ReportFrames(text)
	local found = false
	for _, entry in ipairs(ns.managed) do
		local name = entry.name or entry.frame:GetDebugName()
		if name:lower():find(text, 1, true) or entry.group:lower():find(text, 1, true) then
			found = true
			local frame = entry.frame
			local function Number(value)
				if issecretvalue and issecretvalue(value) then
					return "secret"
				end
				return value and ("%.2f"):format(value) or "-"
			end
			local parent = frame:GetParent()
			ns.Print(("%s [%s] shown=%s visible=%s nested=%s"):format(name, entry.group,
				tostring(frame:IsShown()), tostring(frame:IsVisible()), tostring(entry.nested or false)))
			ns.Print(("  alpha now %s, fade %s, applied %s, base %s, own=%s hooked=%s scale %s"):format(
				Number(frame:GetAlpha()), Number(entry.alpha), Number(entry.applied), Number(entry.baseAlpha),
				tostring(entry.ownAlpha or false), tostring(alphaHooked[frame] == entry),
				Number(frame:GetScale())))
			ns.Print(("  parent %s (shown=%s, alpha %s, on screen %s)"):format(
				parent and (parent:GetName() or parent:GetDebugName()) or "none",
				tostring(parent and parent:IsShown()), Number(parent and parent:GetAlpha()),
				Number(frame.GetEffectiveAlpha and frame:GetEffectiveAlpha())))
		end
	end
	if not found then
		ns.Print("no faded frames with " .. text .. " in the name or group")
	end
end

-- /cine debug minimap: the settings that decide it, then the minimap itself:
-- shown, alpha, size, where it's anchored, and whether it's shrunk and moved
-- off the screen (with the anchors it gets back when it grows).
function ns.ReportMinimap()
	local db = ns.db
	local function Value(value)
		if issecretvalue and issecretvalue(value) then
			return "secret"
		end
		return type(value) == "number" and ("%.2f"):format(value) or tostring(value)
	end
	local function Point(p)
		local relativeTo = p[2]
		local ok, name = pcall(function()
			return relativeTo and (relativeTo:GetName() or relativeTo:GetDebugName()) or "screen"
		end)
		return ("%s to %s %s %s, %s"):format(tostring(p[1]), ok and tostring(name) or "?", tostring(p[3]),
			Value(p[4]), Value(p[5]))
	end
	ns.Print(("minimap settings: profile %s, Standard Frames switch %s, Minimap page switch %s, Always %s, " ..
		"In combat %s"):format(tostring(ns.ActiveProfile()), tostring(db.handleFrames), tostring(db.handleMinimap),
		tostring(ns.IsCineShowOn("minimap")), tostring(ns.IsCombatShowOn("minimap"))))
	ns.Print(("addon on %s, keep up indoors %s, always show (old setting) %s"):format(
		tostring(db.enabled), tostring(db.minimapIndoors), tostring(db.alwaysShowMinimap)))
	local frame = Minimap
	ns.Print(("Minimap shown=%s visible=%s alpha %s, on screen %s, scale %s, size %s x %s"):format(
		Value(frame:IsShown()), Value(frame:IsVisible()), Value(frame:GetAlpha()),
		Value(frame.GetEffectiveAlpha and frame:GetEffectiveAlpha()), Value(frame:GetScale()),
		Value(frame:GetWidth()), Value(frame:GetHeight())))
	local count = frame:GetNumPoints()
	ns.Print(("  %d anchor%s"):format(count, count == 1 and "" or "s"))
	for i = 1, count do
		local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, i)
		ns.Print("    " .. (ok and Point({ point, relativeTo, relativePoint, x, y }) or "can't read"))
	end
	local parent = frame:GetParent()
	ns.Print(("  parent %s (shown=%s, alpha %s)"):format(parent and (parent:GetName() or parent:GetDebugName()) or "none",
		Value(parent and parent:IsShown()), Value(parent and parent:GetAlpha())))
	-- The header above the map (zone name, its border, the buttons on it):
	-- every frame and texture on MinimapCluster, and the older clients' globals,
	-- each with its size, for finding which is which.
	local function Describe(name, region)
		local okType, kind = pcall(region.GetObjectType, region)
		local okShown, shown = pcall(region.IsShown, region)
		local okSize, width, height = pcall(function() return region:GetWidth(), region:GetHeight() end)
		local okText, text = pcall(function() return kind == "FontString" and region:GetText() or nil end)
		local okAtlas, atlas = pcall(function() return kind == "Texture" and region.GetAtlas and region:GetAtlas() or nil end)
		local okFile, file = pcall(function() return kind == "Texture" and region:GetTexture() or nil end)
		return name .. ":" .. (okType and tostring(kind) or "?") .. ((okShown and not ns.Flag(shown)) and "(hidden)" or "")
			.. (okSize and (" " .. Value(width) .. "x" .. Value(height)) or "")
			.. ((okText and type(text) == "string") and (' "' .. text .. '"') or "")
			.. ((okAtlas and type(atlas) == "string") and (" atlas " .. atlas) or "")
			.. ((okFile and file and not (okAtlas and atlas)) and (" file " .. tostring(file)) or "")
	end
	-- A frame's fields (frames and textures), then its regions that have none.
	local function Contents(container)
		local found, named, frames = {}, {}, {}
		for field, value in pairs(container) do
			if type(field) == "string" and type(value) == "table" and value.GetObjectType then
				named[value] = true
				found[#found + 1] = Describe(field, value)
				if value.GetRegions then
					frames[#frames + 1] = field
				end
			end
		end
		table.sort(found)
		table.sort(frames)
		local ok, regions = pcall(function() return { container:GetRegions() } end)
		for i, region in ipairs(ok and regions or {}) do
			if not named[region] then
				found[#found + 1] = Describe("#" .. i, region)
			end
		end
		return found, frames
	end
	local cluster = _G.MinimapCluster
	if cluster then
		local found, frames = Contents(cluster)
		ns.Print("MinimapCluster: " .. table.concat(found, ", "))
		-- And what's in each of its frames (bar the map's own pins and blips).
		for _, field in ipairs(frames) do
			local inside = Contents(cluster[field])
			if #inside > 0 and field ~= "MinimapContainer" then
				ns.Print("  ." .. field .. ": " .. table.concat(inside, ", "))
			end
		end
		local container = cluster.MinimapContainer
		if type(container) == "table" and container.GetRegions then
			local inside = {}
			local ok, regions = pcall(function() return { container:GetRegions() } end)
			for i, region in ipairs(ok and regions or {}) do
				inside[#inside + 1] = Describe("#" .. i, region)
			end
			ns.Print("  .MinimapContainer textures: " .. (#inside > 0 and table.concat(inside, ", ") or "none"))
		end
	end
	local globals = {}
	for _, name in ipairs({ "MinimapBorderTop", "MinimapZoneTextButton", "MinimapZoneText", "MinimapBorder",
		"MinimapToggleButton", "MiniMapWorldMapButton", "TimeManagerClockButton", "GameTimeFrame" }) do
		local region = _G[name]
		if type(region) == "table" and region.GetObjectType then
			local okParent, parentName = pcall(function()
				local p = region:GetParent()
				return p and (p:GetName() or p:GetDebugName()) or "none"
			end)
			globals[#globals + 1] = Describe(name, region) .. " in " .. (okParent and tostring(parentName) or "?")
		end
	end
	ns.Print("header globals: " .. (#globals > 0 and table.concat(globals, ", ") or "NONE"))
	-- And what the header's buttons are made of.
	for name, button in pairs({ GameTimeFrame = _G.GameTimeFrame, ["Tracking.Button"] = cluster and cluster.Tracking
		and cluster.Tracking.Button }) do
		if type(button) == "table" and button.GetRegions then
			ns.Print("  " .. name .. ": " .. table.concat(Contents(button), ", "))
		end
	end
	local entry
	for _, managed in ipairs(ns.managed) do
		if managed.frame == frame then
			entry = managed
		end
	end
	if not entry then
		ns.Print("  not faded by Cinematic now")
		return
	end
	ns.Print(("  faded: fade %s, applied %s, shrunk %s (shrunk scale %s), moved off the screen %s, hooked %s"):format(
		Value(entry.alpha), Value(entry.applied), tostring(entry.shrunk or false), Value(SHRUNK_SCALE),
		tostring(ns.IsParked(entry)), tostring(alphaHooked[frame] == entry)))
	ns.Print(("  size to grow back to %s"):format(Value(entry.savedScale)))
	ns.Print("  " .. ns.MinimapIconState())
	if entry.savedPoints then
		ns.Print(("  anchors to put back (%d):"):format(#entry.savedPoints))
		for _, p in ipairs(entry.savedPoints) do
			ns.Print("    " .. Point(p))
		end
	end
	-- Moved off the screen, nothing of the map's should show: list what's still
	-- on it (its parts, its parent when not UIParent - EllesmereUI's crop frame -
	-- and the frames on UIParent anchored to either), for a stray pixel.
	local uiScale = UIParent:GetEffectiveScale()
	local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
	-- A frame's or texture's rect in UIParent units, or nil.
	local function ScreenRect(region, scale)
		local ok, left, bottom, width, height = pcall(region.GetRect, region)
		if not ok or type(left) ~= "number" or Secret(left) or Secret(width) then
			return nil
		end
		local k = scale / uiScale
		return left * k, bottom * k, width * k, height * k
	end
	local function Rect(left, bottom, width, height)
		return left and ("%.1f,%.1f %.1fx%.1f"):format(left, bottom, width, height) or "none"
	end
	-- (Not Rect(parent and ScreenRect(...)): "and" keeps only the first value.)
	local parentRect = "none"
	if parent then
		parentRect = Rect(ScreenRect(parent, parent:GetEffectiveScale()))
	end
	ns.Print(("  rect %s (screen %.0fx%.0f), parent rect %s, clamped to the screen %s (put back when it grows %s)"):format(
		Rect(ScreenRect(frame, frame:GetEffectiveScale())), screenW, screenH, parentRect,
		Value(frame.IsClampedToScreen and frame:IsClampedToScreen()), tostring(entry.savedClamped or false)))
	if not entry.shrunk then
		return
	end
	local onScreen, checked = {}, {}
	local function Check(name, region, scale, alpha)
		local left, bottom, width, height = ScreenRect(region, scale)
		if left and left < screenW and left + width > 0 and bottom < screenH and bottom + height > 0 then
			onScreen[#onScreen + 1] = ("%s (%s) at %s, alpha %s"):format(name,
				tostring(select(2, pcall(region.GetObjectType, region))), Rect(left, bottom, width, height), Value(alpha))
		end
	end
	local function Walk(target, depth)
		if checked[target] or depth > 6 or IsForbidden(target) or not ns.Flag(target:IsVisible()) then
			return
		end
		checked[target] = true
		local name = target:GetName() or target:GetDebugName()
		local scale, alpha = target:GetEffectiveScale(), target:GetEffectiveAlpha()
		if not Secret(alpha) and alpha > 0 then
			Check(name, target, scale, alpha)
		end
		local ok, regions = pcall(function() return { target:GetRegions() } end)
		for i, region in ipairs(ok and regions or {}) do
			local okShown, shown = pcall(region.IsShown, region)
			local okAlpha, own = pcall(region.GetAlpha, region)
			if okShown and ns.Flag(shown) and okAlpha and not Secret(own) and not Secret(alpha) then
				local ignores = region.IsIgnoringParentAlpha and ns.Flag(region:IsIgnoringParentAlpha())
				local shownAlpha = ignores and own or own * alpha
				if shownAlpha > 0 then
					Check(name .. "#" .. i, region, scale, shownAlpha)
				end
			end
		end
		for _, child in ipairs({ target:GetChildren() }) do
			Walk(child, depth + 1)
		end
	end
	local roots = { [frame] = true }
	if parent and parent ~= UIParent then
		roots[parent] = true
	end
	Walk(frame, 1)
	if roots[parent] then
		Walk(parent, 1)
	end
	for _, child in ipairs({ UIParent:GetChildren() }) do
		if not IsForbidden(child) then
			for i = 1, child:GetNumPoints() do
				local ok, _, relativeTo = pcall(child.GetPoint, child, i)
				if ok and relativeTo and (roots[relativeTo] or checked[relativeTo]) then
					Walk(child, 1)
					break
				end
			end
		end
	end
	ns.Print(("  still on the screen while moved off (%d):"):format(#onScreen))
	for i, line in ipairs(onScreen) do
		if i <= 15 then ns.Print("    " .. line) else ns.Log("minimap", line) end
	end
	if #onScreen > 15 then ns.Print(("    ...and %d more in /cine log"):format(#onScreen - 15)) end
end

-- /cine debug frames: the shown top-level frames not faded, and every global
-- frame with GamePad in its name, to the log (and chat), for finding frames
-- a client feature adds (WoW Forever's gamepad mode).
function ns.ReportUnfadedFrames()
	local function Report(text)
		ns.Print(text)
		ns.Log("frames", text)
	end
	local cvar = C_CVar and C_CVar.GetCVar or GetCVar
	Report(("GamePadEnable=%s C_GamePad=%s"):format(tostring(cvar and cvar("GamePadEnable")),
		tostring(C_GamePad ~= nil)))
	local function Describe(frame)
		local measured, left, bottom, width, height = pcall(frame.GetRect, frame)
		if not measured then
			left, bottom, width, height = nil, nil, nil, nil
		end
		local parent = frame:GetParent()
		return ("%s %s %s strata=%s rect=%d,%d %dx%d parent=%s"):format(frame:GetName() or "(unnamed)",
			frame:GetDebugName(), frame:GetObjectType(), frame.GetFrameStrata and frame:GetFrameStrata() or "-",
			left or -1, bottom or -1,
			width or 0, height or 0, parent and (parent:GetName() or parent:GetDebugName()) or "none")
	end
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not IsForbidden(frame) and not seen[frame] and ns.Flag(frame:IsVisible()) and frame ~= ns.letterbox then
			Report("unfaded: " .. Describe(frame))
		end
	end
	-- Small things at the middle of the screen (gamepad mode's dot), a few
	-- levels down, with what they draw.
	local centerX, centerY = UIParent:GetCenter()
	local function Textures(frame)
		local list = {}
		for _, region in ipairs(ReadParts(frame, "GetRegions") or {}) do
			if not IsForbidden(region) and region.GetTexture and ns.Flag(region:IsVisible()) then
				list[#list + 1] = tostring(region.GetAtlas and region:GetAtlas() or region:GetTexture())
			end
		end
		return table.concat(list, ",")
	end
	local function AtCenter(frame, depth)
		if IsForbidden(frame) or not ns.Flag(frame:IsVisible()) then
			return
		end
		-- (Nameplates can't be measured: they error. They're reported below.)
		local measured, left, bottom, width, height = pcall(frame.GetRect, frame)
		if not measured then
			return
		end
		if left and width < 100 and height < 100 and left <= centerX and left + width >= centerX
			and bottom <= centerY and bottom + height >= centerY then
			Report(("center: %s alpha=%.2f textures=%s"):format(Describe(frame), frame:GetEffectiveAlpha(),
				Textures(frame)))
		end
		if depth > 0 then
			for _, child in ipairs(ReadParts(frame, "GetChildren") or {}) do
				AtCenter(child, depth - 1)
			end
		end
	end
	AtCenter(UIParent, 5)
	AtCenter(WorldFrame, 2)
	-- The soft targets' plates (gamepad mode's interact prompt sits on one),
	-- with what's shown inside them.
	local function Inside(frame, depth, indent)
		for _, child in ipairs(ReadParts(frame, "GetChildren") or {}) do
			if not IsForbidden(child) and ns.Flag(child:IsShown()) then
				Report(("%s%s %s textures=%s"):format(indent, child:GetDebugName(), child:GetObjectType(),
					Textures(child)))
				if depth > 0 then
					Inside(child, depth - 1, indent .. "  ")
				end
			end
		end
	end
	for _, unit in ipairs({ "softinteract", "softenemy", "softfriend", "target" }) do
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
			and C_NamePlate.GetNamePlateForUnit(unit)
		Report(("unit %s: exists=%s plate=%s"):format(unit, tostring(UnitExists(unit)),
			plate and (IsForbidden(plate) and "forbidden" or plate:GetDebugName()) or "none"))
		if plate and not IsForbidden(plate) then
			Inside(plate, 4, "  ")
		end
	end
	-- Settings that may draw it (C_Console lists every setting the game has).
	if C_Console and C_Console.GetAllCommands then
		local cvar = C_CVar and C_CVar.GetCVar or GetCVar
		for _, command in ipairs(C_Console.GetAllCommands()) do
			local name = command.command
			if type(name) == "string" then
				local lower = name:lower()
				if lower:find("reticle") or lower:find("crosshair") or lower:find("cursor")
					or lower:find("gamepad") or lower:find("softtarget") then
					Report(("cvar %s = %s"):format(name, tostring(cvar(name))))
				end
			end
		end
	end
	for name, value in pairs(_G) do
		if type(name) == "string" and name:lower():find("gamepad") and IsFrame(value)
			and value.GetRect and not IsForbidden(value) then
			Report(("gamepad global: %s shown=%s faded=%s"):format(Describe(value), tostring(value:IsVisible()),
				tostring(seen[value] or false)))
		end
	end
end

-- /cine debug questtimer: why the quest timer is or isn't kept up.
function ns.ReportQuestTimer()
	local frame = _G.QuestTimerFrame
	local timers = {}
	for i, seconds in ipairs(GetQuestTimers and { GetQuestTimers() } or {}) do
		timers[i] = tostring(seconds)
	end
	ns.Print(("quest timer: running=%s option=%s retail=%s timers=%s"):format(tostring(HasQuestTimer()),
		tostring(ns.db.questTimerShow), tostring(ns.isRetail),
		GetQuestTimers and table.concat(timers, ",") or "no API"))
	if ns.isRetail then
		-- (Retail: timers in the tracker, each the quest or scenario kept up.)
		local keys = {}
		for key in pairs(ns.TrackerTimerKeys() or {}) do
			keys[#keys + 1] = tostring(key)
		end
		local tracker = _G.ObjectiveTrackerFrame
		ns.Print(("tracker timers: %s page=%s combat=%s tracker alpha=%s scenario=%s"):format(
			#keys > 0 and table.concat(keys, ",") or "none", tostring(ns.PageOn("handleQuests")),
			tostring(ns.Flag(InCombatLockdown())), tracker and ("%.2f"):format(tracker:GetAlpha()) or "no tracker",
			tostring(_G.ScenarioObjectiveTracker and ns.Flag(_G.ScenarioObjectiveTracker:IsShown()))))
		return
	end
	if not frame then
		ns.Print("no QuestTimerFrame")
		return
	end
	local parents = {}
	local parent = frame:GetParent()
	while parent do
		parents[#parents + 1] = (parent:GetName() or "?") .. (seen[parent] and "(faded)" or "")
		parent = parent:GetParent()
	end
	ns.Print("parents: " .. table.concat(parents, " > "))
	for _, entry in ipairs(ns.managed) do
		if entry.frame == frame then
			ns.Print(("group=%s alpha=%.2f nested=%s shown=%s ignoreParentAlpha=%s"):format(entry.group,
				entry.alpha, tostring(entry.nested or false), tostring(frame:IsShown()),
				tostring(frame.IsIgnoringParentAlpha and frame:IsIgnoringParentAlpha())))
			return
		end
	end
	ns.Print("QuestTimerFrame isn't managed")
end

local DEATH_FADE_TIME = 0.5 -- seconds for the UI to go when you die (death camera)

-- How long a group takes to fade in or out: the shared fade times, but for
-- gamepad mode's action bars, which have their own (Gamepad page) so they
-- come and go quickly with button presses.
local function GroupFadeTime(group, fadeIn)
	if group == "gamepadbars" then
		return fadeIn and ns.db.gamepadBarsFadeIn or ns.db.gamepadBarsFadeOut
	end
	return fadeIn and ns.FadeInTime() or ns.FadeOutTime()
end
-- The portrait shown while health or power recovers (addons' can stand in
-- for the game's: see ns.AddPortraitFrame), and the personal resource
-- display: each with the setting that keeps it up.
local PORTRAIT_FRAMES = {
	PlayerFrame = "portraitWhenNotFull",
	PersonalResourceDisplayFrame = "prdWhenNotFull", CinematicPersonalResource = "prdWhenNotFull",
	CinematicPersonalPower = "prdWhenNotFull", CinematicPersonalMana = "prdWhenNotFull",
}

-- Swing timer page (Classic clients' own swing timer): a bar fades out once
-- its weapon hasn't been used for a while, and the off-hand's can go for
-- good. A bar counts as used while it runs down (after a real swing or
-- shot). Without a bar to read, melee counts while auto-attack is on and the
-- target is in melee range, ranged while Auto Shot or a wand repeats and the
-- target is in its range, and on single shots (Shoot Bow or Throw).
-- Each holds on past its last use for the bar to run down to 0 and the
-- swingHideAfter seconds after.
-- (In a do block: the file is near Lua's 200 locals.)
do
	local BAR_WEAPON = {
		SwingTimerMainHandFrame = "melee", SwingTimerOffHandFrame = "melee", SwingTimerRangedFrame = "ranged",
	}
	-- Auto Shot, Shoot (wands; and Shoot as later clients name every ranged weapon's), Throw,
	-- Shoot Bow, Shoot Gun, Shoot Crossbow.
	local RANGED_SHOTS = { [75] = true, [5019] = true, [3018] = true, [2764] = true, [2480] = true,
		[7918] = true, [7919] = true }
	local usedAt = { melee = -math.huge, ranged = -math.huge }
	local inUse = { melee = false, ranged = false }

	local function Number(value)
		if type(value) ~= "number" or (issecretvalue and issecretvalue(value)) then
			return nil
		end
		return value
	end

	-- Seconds the weapon's bar takes to run down.
	local function Speed(weapon)
		local speed
		if weapon == "ranged" then
			speed = UnitRangedDamage and Number((UnitRangedDamage("player")))
		else
			speed = UnitAttackSpeed and Number((UnitAttackSpeed("player")))
		end
		return math.min(speed or 2, 5)
	end

	-- (Switching off doesn't count as a use: a hunter's /startattack plus
	-- /cast !Auto Shot macro switches auto-attack on and straight off again.
	-- While a weapon's switched on and in reach, each check counts instead.)
	local function SetInUse(weapon, on)
		inUse[weapon] = on
	end

	-- Spells whose range says whether the target is in reach of each weapon:
	-- Auto Attack, then a hunter's melee strikes (in case the game won't range
	-- check Auto Attack); Auto Shot (too close counts as out of range), then Shoot.
	local RANGE_SPELLS = { melee = { 6603, 2973, 2974, 1495 }, ranged = { 75, 5019 } }

	-- Whether the target is in range of the weapon: true, false, or nil when
	-- the game can't say (no target, a secret answer), which counts as in range.
	local function InRange(weapon)
		if not UnitExists("target") then
			return nil
		end
		for _, spellID in ipairs(RANGE_SPELLS[weapon]) do
			local ok, inRange
			if C_Spell and C_Spell.IsSpellInRange then
				ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, "target")
			elseif IsSpellInRange and GetSpellInfo then
				local spellName = GetSpellInfo(spellID)
				if spellName then
					ok, inRange = pcall(IsSpellInRange, spellName, "target")
				end
			end
			if ok and not (issecretvalue and issecretvalue(inRange)) then
				if inRange == true or inRange == 1 then
					return true
				elseif inRange == false or inRange == 0 then
					return false
				end
			end
		end
		return nil
	end

	if not ns.isRetail then
		-- (No combat log for the swings themselves: registering for it gets the
		-- addon blocked on Forever.)
		local watcher = CreateFrame("Frame")
		watcher:RegisterEvent("PLAYER_ENTER_COMBAT") -- (auto-attack on)
		watcher:RegisterEvent("PLAYER_LEAVE_COMBAT")
		watcher:RegisterEvent("START_AUTOREPEAT_SPELL")
		watcher:RegisterEvent("STOP_AUTOREPEAT_SPELL")
		watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		watcher:SetScript("OnEvent", function(_, event, _, _, spellID)
			if event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" then
				SetInUse("melee", event == "PLAYER_ENTER_COMBAT")
			elseif event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL" then
				SetInUse("ranged", event == "START_AUTOREPEAT_SPELL")
			elseif Number(spellID) and RANGED_SHOTS[spellID] then
				usedAt.ranged = GetTime()
			end
		end)
		-- (Auto-attack already on after a /reload.)
		local ok, attacking = pcall(IsCurrentSpell, 6603)
		inUse.melee = ok and attacking == true
	end

	-- The game's own bar shows whether the weapon has really been used: it
	-- sits still (at 0.0) until a swing or shot, then runs down. Its status
	-- bar's value, or nil when there's none to read (a secret value, say).
	local statusBars = {}
	local function FindStatusBar(frame, depth)
		if frame:IsObjectType("StatusBar") then
			return frame
		end
		if depth > 0 then
			for _, child in ipairs({ frame:GetChildren() }) do
				local bar = FindStatusBar(child, depth - 1)
				if bar then
					return bar
				end
			end
		end
	end
	local function BarValue(name)
		local bar = statusBars[name]
		if bar == nil then
			local frame = _G[name]
			if not frame then
				return nil
			end
			local ok, found = pcall(FindStatusBar, frame, 2)
			bar = ok and found or false
			statusBars[name] = bar
		end
		if not bar then
			return nil
		end
		local ok, value = pcall(bar.GetValue, bar)
		return ok and Number(value) or nil
	end
	local lastValue, moves, lastDecision = {}, {}, {}

	-- /cine debug swing: each bar's showing or fading, as it changes, and why.
	local function DebugSwing(name, unused, why)
		if ns.swingDebug and lastDecision[name] ~= unused then
			ns.Print(("swing %s: %s (%s)"):format(name, unused and "fades" or "shows", why))
		end
		lastDecision[name] = unused
		return unused
	end

	function ns.ReportSwing()
		for name in pairs(BAR_WEAPON) do
			local frame = _G[name]
			local value = BarValue(name)
			local bar = statusBars[name]
			local minValue, maxValue
			if bar then
				local ok, a, b = pcall(bar.GetMinMaxValues, bar)
				minValue, maxValue = ok and Number(a), ok and Number(b)
			end
			local weapon = BAR_WEAPON[name]
			ns.Print(("%s: frame %s, status bar %s, value %s (%s-%s), %s switched on %s, in range %s, last used %s sec ago"):format(
				name, frame and "yes" or "no", bar and (bar:GetName() or "unnamed") or "none", tostring(value),
				tostring(minValue), tostring(maxValue), weapon, tostring(inUse[weapon]), tostring(InRange(weapon)),
				usedAt[weapon] > -math.huge and ("%.1f"):format(GetTime() - usedAt[weapon]) or "never"))
		end
	end

	-- Whether the swing timer frame is to be faded out (it fades at the usual speed).
	function ns.IsSwingBarUnused(name)
		local weapon = BAR_WEAPON[name]
		if not weapon then
			return false
		end
		if not ns.db.handleSwing then
			return false
		end
		if name == "SwingTimerOffHandFrame" and ns.db.swingHideOffHand then
			return true
		end
		if not ns.db.swingSmartShow then
			return false
		end
		-- The bar moving: a real swing or shot (switched on with nothing in
		-- reach, it stays still). It has to move on two checks running: auto-
		-- attack switching on can jump it once without a swing.
		local value = BarValue(name)
		if value then
			if lastValue[name] and value ~= lastValue[name] then
				moves[name] = (moves[name] or 0) + 1
				if moves[name] >= 2 then
					usedAt[weapon] = GetTime()
				end
			else
				moves[name] = 0
			end
			local previous = lastValue[name]
			lastValue[name] = value
			return DebugSwing(name, GetTime() - usedAt[weapon] > ns.db.swingHideAfter,
				("bar %s -> %s"):format(tostring(previous), tostring(value)))
		end
		-- No bar to read: switched on and the target in reach: in use (and it holds on from
		-- here once it isn't). Switched on out of reach doesn't count: a
		-- hunter's /startattack plus /cast !Auto Shot macro turns on both.
		local inRange = InRange(weapon)
		if inUse[weapon] and inRange ~= false then
			usedAt[weapon] = GetTime()
			return DebugSwing(name, false, "no bar to read; switched on, in range " .. tostring(inRange))
		end
		return DebugSwing(name, GetTime() - usedAt[weapon] > Speed(weapon) + ns.db.swingHideAfter,
			"no bar to read; switched on " .. tostring(inUse[weapon]) .. ", in range " .. tostring(inRange))
	end

	-- Ranged bar on top (swingRangedOnTop<CLASS>, for your class): the ranged bar
	-- takes the main hand's place, and the main hand and off-hand bars each move
	-- down one (main hand, off hand, ranged becomes ranged, main hand, off hand).
	-- Each bar takes the anchors of the place it moves to, and one anchored to
	-- another bar is anchored to whichever bar is in that place now. The game's
	-- own anchors are kept (and taken afresh whenever it moves a bar), so it
	-- can be undone. Without an off-hand bar: main hand and ranged trade places.
	local order = { swapped = false, game = {}, moving = false }

	local function ReadPoints(frame)
		local points = {}
		for i = 1, frame:GetNumPoints() do
			local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
			if not (Number(x) and Number(y)) then
				return nil -- (secret: leave it alone)
			end
			points[i] = { point, relativeTo, relativePoint, x, y }
		end
		return points
	end

	-- moved: bar -> the bar now in its place.
	local function SetPoints(frame, points, moved)
		order.moving = true
		frame:ClearAllPoints()
		for _, p in ipairs(points) do
			frame:SetPoint(p[1], moved and moved[p[2]] or p[2], p[3], p[4], p[5])
		end
		order.moving = false
	end

	local function Apply(swap)
		local main, ranged = _G.SwingTimerMainHandFrame, _G.SwingTimerRangedFrame
		local off = _G.SwingTimerOffHandFrame
		local bars = { main, ranged, off }
		if not (main and ranged) then
			return
		end
		for _, bar in ipairs(bars) do
			if InCombatLockdown() and bar:IsProtected() then return end
		end
		for _, bar in ipairs(bars) do
			order.game[bar] = order.game[bar] or ReadPoints(bar)
			if not (order.game[bar] and #order.game[bar] > 0) then
				return
			end
		end
		if not order.hooked then
			order.hooked = true
			-- The game moving a bar: its new anchors are the game's, and the order is done again.
			local function OnMoved(frame)
				if order.moving then return end
				order.game[frame] = nil
				order.swapped = nil -- (looked at next tick)
			end
			for _, bar in ipairs(bars) do hooksecurefunc(bar, "SetPoint", OnMoved) end
		end
		if swap then
			-- (where each bar goes: the place of the bar named)
			local place = off and { [ranged] = main, [main] = off, [off] = ranged } or { [ranged] = main, [main] = ranged }
			local moved = {}
			for bar, to in pairs(place) do moved[to] = bar end
			for bar, to in pairs(place) do SetPoints(bar, order.game[to], moved) end
		else
			for _, bar in ipairs(bars) do SetPoints(bar, order.game[bar]) end
		end
		order.swapped = swap
	end

	-- Each tick: the bars as the setting (and the page's master switch) say.
	function ns.UpdateSwingOrder()
		local swap = ns.db.handleSwing and ns.db["swingRangedOnTop" .. select(2, UnitClass("player"))]
			and true or false
		if order.swapped ~= swap then
			-- (Not swapped and the game's anchors not taken yet: nothing to put back.)
			if swap or next(order.game) then
				if not pcall(Apply, swap) then
					order.swapped = swap -- (an error: not tried again every tick)
				end
			else
				order.swapped = false
			end
		end
	end
end

-- Where the mouse was when the hover checks last ran (see below).
tickTables.hoverMouse = { at = -math.huge }

function ns.UpdateFrames(cinematic, elapsed)
	local now = GetTime()
	UpdateReadyOnly(elapsed, now)
	if not ns.isRetail then
		ns.UpdateSwingOrder()
	end
	local combatShown
	if cinematic then
		combatShown = GetCombatShownFrames()
	end
	local fighting = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	-- (Casting at an enemy: the rows it brings up fade in over what's left of
	-- the cast, at the Combat fade in time just after it.)
	local castLeft = cinematic and not fighting and ns.db.stayInCombat and ns.HostileCastLeft(now)
	if fighting then
		lastCombatAt = now
		buffPeekUntil = 0 -- (a buff peek from just before the fight doesn't outlast it)
	end
	if ns.Flag(IsFalling()) then
		lastFallingAt = now
	end
	if resurrectRecovering and not IsPlayerRecovering() then
		resurrectRecovering = false
	end
	-- (Only after a fight or fall damage, within the Calm Timer, or after
	-- resurrecting: not for a buff cast in town.)
	local portraitAllowed = now - math.max(lastCombatAt, lastFallDamageAt) < ns.db.calmTime
		or resurrectRecovering
	if ns.IsChatActive() then
		ns.chatTypingUntil = now + ns.HoldTime("chatPeekTime")
	end
	local typing = ns.chatTypingUntil > now
	-- (The Chat page's Typing row: where it's off, just the input box comes up.)
	local typingWindows = typing and ns.RowOnNow("chat:typing", ns.db.chatShowWhileTyping)
	-- (Then the input box only while it's open: held after, it was an empty bar.)
	local activeEditBox = not typingWindows and ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
	-- A whisper tab waiting to be read keeps the whole chat window up, tabs
	-- and all, so it can be clicked (Chat page).
	local whisperUnread = cinematic and ns.db.chatUntilWhisperRead and ns.HasUnreadWhisper()
	ns.HoldScrolledChat(now)
	-- A docked chat window peeking: the window comes up, with its background,
	-- tabs and buttons as the Chat page ticks them (and for Mouseover groups
	-- with "Chat message" ticked).
	local dockPeek = false
	for chatFrame, untilTime in pairs(ns.chatPeekUntil) do
		if untilTime > now and (chatFrame.isDocked or chatFrame == DEFAULT_CHAT_FRAME) then
			dockPeek = true
			break
		end
	end
	-- Chat stays put when it isn't faded at all, or in a place chosen under
	-- "Always show in" (Chat page).
	local place = ns.GetOptionPlace()
	local fadeChat = not (place and ns.db[ns.CHAT_IN[place]])
	local keepForGathering, keepForCreatures = ns.IsKeepingMinimapForTracking(now)
	-- (Quest tracker page, its switch on.)
	local questTimerUp = ns.PageOn("handleQuests") and ns.db.questTimerShow and HasQuestTimer()
	-- (Retail: a timer in the quest tracker keeps just that part up.)
	local trackerTimerUp = ns.isRetail and ns.PageOn("handleQuests") and ns.db.questTimerShow and ns.HasTrackerTimer()
	-- (Hide in camera modes: not while one is running, it goes with the rest.)
	local durabilityUp = ns.PageOn("handleQuests") and ns.db.durabilityShow and not (ns.db.durabilityHideInCam and ns.activeCam)
		and ns.HasDurabilityAlert()
	local petUnhappyUp = ns.db.petUnhappyShow and not (ns.db.petUnhappyHideInCam and ns.activeCam)
		and ns.IsPetUnhappy()
	local questReveal = questRevealUntil > now
	local padReveal = padRevealUntil > now
	local pingReveal = pingRevealUntil > now
	local rosterReveal = rosterRevealUntil > now
	-- Tracking doesn't hold the minimap open in the places ticked under
	-- "Except in" (cities and the like).
	local trackingPaused = ns.IsTrackingOffHere()
	-- Mouseover groups: the rows the mouse is on (each held a while after it
	-- leaves), and the events going on now, bring up every row in their groups.
	local hoverGroups = ns.GetHoverGroups()
	-- (A group set to work only in fights, or only out of them: left out
	-- otherwise, its frames still coming up on their own. offWhen: the "when"
	-- that's left out now. A group turned off (group.off) is always left out.)
	local offWhen = fighting and "calm" or "combat"
	local hovered, triggered, pinged = wipe(tickTables.hovered), wipe(tickTables.triggered), wipe(tickTables.pinged)
	-- The raid-style party frames set apart from the raid frames (Standard
	-- Frames page): their own rows (rspGroup) decide for them, not the raid frames'.
	local ownPartyRows = ns.db.raidStylePartySame == false
	if cinematic and ns.db.mouseover then
		local mouseRows = wipe(tickTables.mouseRows)
		-- (Asked of every faded frame, many times a second: with the mouse
		-- still, on the same thing, each frame's answer stands, asked again a
		-- few times a second in case a frame showed or moved under it.)
		local mouse = tickTables.hoverMouse
		local x, y = GetCursorPosition()
		local focus = MouseFocus()
		local still = x == mouse.x and y == mouse.y and focus == mouse.focus and now - mouse.at < 0.25
		if not still then
			mouse.x, mouse.y, mouse.focus, mouse.at = x, y, focus, now
		end
		for _, entry in ipairs(ns.managed) do
			entry.row = entry.row or ns.HoverRowFor(entry)
			local over = entry.hoverWas
			if not still or over == nil then
				over = ns.IsEntryHovered(entry) and true or false
				entry.hoverWas = over
			end
			if over then
				mouseRows[ownPartyRows and entry.rspGroup or entry.row] = true
			end
		end
		-- (A groupOnly row counts only while a group it's in is on.)
		for row in pairs(mouseRows) do
			if ns.HOVER_GROUP_ONLY[row] then
				local inGroup = false
				for _, group in ipairs(hoverGroups) do
					for _, key in ipairs(not group.off and group.when ~= offWhen and group.members or NO_DEFAULTS) do
						if key == row then inGroup = true end
					end
				end
				if not inGroup then mouseRows[row] = nil end
			end
		end
		-- Rows linger after the mouse leaves. The hold time counts the fade
		-- out, so a row is gone that long after the mouse leaves; a hold
		-- shorter than the fade just starts the fade straight away.
		local heldUntil = now + math.max(0, ns.HoldTime("mouseoverHold") - ns.FadeOutTime())
		-- (Under the mouse counts even with no hold: the camera modes' is 0.)
		for row in pairs(mouseRows) do
			hoverHeldUntil[row] = heldUntil
			hovered[row] = true
		end
		for row, untilTime in pairs(hoverHeldUntil) do
			if untilTime > now then
				hovered[row] = true
			end
		end
		-- (Only groups a hovered row is in directly: groups sharing a row don't chain.)
		local mouseGroups = wipe(tickTables.mouseGroups)
		for _, group in ipairs(hoverGroups) do
			for _, key in ipairs(not group.off and group.when ~= offWhen and group.members or NO_DEFAULTS) do
				if hovered[key] then
					mouseGroups[#mouseGroups + 1] = group
					break
				end
			end
		end
		for _, group in ipairs(mouseGroups) do
			for _, member in ipairs(group.members) do
				hovered[member] = true
			end
		end
	end
	-- Mouseover wins over the Unit Frames page: a unit frame up for the mouse
	-- (or with its Mouseover groups) fades in the parts that page hides. Out
	-- of CineMode, the frame under the mouse, held as long (the fade out counted).
	if ns.SetUnitPartsHovered then
		local partsHovered, partsHeldUntil = wipe(tickTables.partsHovered), tickTables.partsHeldUntil
		for _, entry in ipairs(ns.db.mouseover and ns.managed or NO_DEFAULTS) do
			local name = entry.name
			if name and ns.UNIT_PART_FRAME_NAMES[name] then
				if cinematic then
					entry.row = entry.row or ns.HoverRowFor(entry)
					partsHovered[name] = hovered[ownPartyRows and entry.rspGroup or entry.row]
				else
					if ns.IsEntryHovered(entry) then
						partsHeldUntil[name] = now + math.max(0, ns.HoldTime("mouseoverHold") - ns.FadeOutTime())
					end
					partsHovered[name] = (partsHeldUntil[name] or 0) > now
				end
			end
		end
		ns.SetUnitPartsHovered(partsHovered, elapsed)
	end
	local events = tickTables.events
	events.chat, events.whisper, events.typing = dockPeek, whisperUnread, typingWindows
	-- (The Minimap, Quest tracker, Buffs/debuffs and Cooldown Manager pages'
	-- extras: none while their page's switch is off.)
	local minimapPage = ns.PageOn("handleMinimap")
	local debuffPeekOn = ns.debuffPeekUntil > now or (debuffHeld and ns.db.debuffPeekUntilGone)
	events.aura = cinematic and ns.PageOn("handleBuffs") and (buffPeekUntil > now or debuffPeekOn)
	-- (A debuff peek alone brings up just the debuffs, not the buffs beside
	-- them: see auraOnly below.)
	local debuffsOnly = events.aura and buffPeekUntil <= now
	-- (/cine debug peeks: when a peek starts and stops, and why not.)
	if ns.auraDebug and (events.aura or false) ~= (ns.auraDebugWas or false) then
		ns.auraDebugWas = events.aura or false
		ns.Print(("buffs peek %s (CineMode %s, page on %s, peek %.1fs, fight peek %.1fs)"):format(
			events.aura and "on" or "off", tostring(cinematic), tostring(ns.PageOn("handleBuffs")),
			math.max(0, buffPeekUntil - now), math.max(0, ns.debuffPeekUntil - now)))
	end
	-- (Not on flight paths, Minimap page: no pings, reveals or tracking bring it up then.)
	local taxiHidesMinimap = minimapPage and ns.db.minimapHideOnTaxi and ns.Flag(ns.OnTaxi())
	events.ping = minimapPage and pingReveal and not taxiHidesMinimap
	-- (Keep open and Reveal, Minimap page: "Except in" is for gathering tracking only.)
	events.tracking = minimapPage and not taxiHidesMinimap and ((keepForGathering and not trackingPaused) or keepForCreatures
		or ns.IsMinimapRevealed(now))
	events.quest, events.gamepad, events.roster = ns.PageOn("handleQuests") and questReveal, padReveal, rosterReveal
	-- (Each bar's own Stay up while recharging: Essential's, with Enhanced
	-- Cooldown Manager's bars, and Utility's. A bar comes up only for its own
	-- cooldowns; anything else in the group, for either.)
	local calm = now - lastCombatAt < ns.db.calmTime
	local cooldownsOn = cinematic and ns.PageOn("handleCooldowns")
	local barUp = tickTables.cooldownBarUp
	barUp.essential = cooldownsOn and ns.db.cooldownWhileRecharging and (calm or not ns.db.cooldownAfterCombat)
		and AnyCooldownRecharging(now, "essential") or false
	barUp.utility = cooldownsOn and ns.db.cooldownUtilityWhileRecharging
		and (calm or not ns.db.cooldownUtilityAfterCombat) and AnyCooldownRecharging(now, "utility") or false
	events.cooldown = barUp.essential or barUp.utility
	-- (auraOnly: rows brought up by a buff or debuff peek and nothing else.)
	local auraOnly = wipe(tickTables.auraOnly)
	for _, group in ipairs(hoverGroups) do
		for key, on in pairs(not group.off and group.when ~= offWhen and group.triggers or NO_DEFAULTS) do
			if on and events[key] then
				for _, member in ipairs(group.members) do
					-- (A cooldown bar: only for its own bar's cooldowns.)
					local bar = key == "cooldown" and ns.COOLDOWN_MEMBER_BAR[member]
					if not bar or barUp[bar] then
						if not triggered[member] then auraOnly[member] = key == "aura" or nil end
						if key ~= "aura" then auraOnly[member] = nil end
						triggered[member] = true
						if key == "ping" then pinged[member] = true end
					end
				end
			end
		end
	end

	-- Dead, with the death camera watching: everything goes, quickly, whatever
	-- would normally keep it up (the release button is a popup: it stays).
	-- Hovering still shows it.
	local deathFade = cinematic and ns.IsDeathCinematic and ns.IsDeathCinematic()
	-- (But the rows of the groups picked on the Death Cam page: up throughout.)
	local deathKept = wipe(tickTables.deathKept)
	if deathFade and ns.db.deathKeepGroups then
		for _, group in ipairs(ns.GetHoverGroups()) do
			if ns.db.deathKeepGroups[ns.HoverGroupId(group)] then
				for _, key in ipairs(group.members or NO_DEFAULTS) do deathKept[key] = true end
			end
		end
	end
	-- Chat Cam's Ultra immersive: through a conversation the whole UI goes,
	-- CineMode or not, hovering and all (typing still shows the input box).
	local immersive = ns.ChatCamImmersive and ns.ChatCamImmersive() or false

	-- Hide in camera modes (Minimap page): the camera running now fades the
	-- minimap and its header, whatever would keep them up. Hovering still shows them.
	local camHidesMinimap = minimapPage and ns.activeCam and ns.db[ns.activeCam .. "HideMinimap"]
	-- Keep minimap open indoors (Minimap page): see RedrawMinimapWhenShown.
	local keepIndoors = minimapPage and (ns.db.minimapIndoors and IsIndoors and ns.Flag(IsIndoors())
		or ns.db.minimapKeepQuest and ns.HasTrackedQuest()
			-- (Only after progress: 0 is off.)
			and ((ns.db.minimapKeepQuestFor or 0) <= 0 or now - ns.questActivityAt < ns.db.minimapKeepQuestFor * 60)
		-- (Zones you picked: not on flight paths, where Not on flight paths is ticked.)
		or not taxiHidesMinimap and ns.IsMinimapKeptInZone())

	-- (Up unless their rows' frames are faded below: let go, they're up.)
	personalPower.health, personalPower.level, personalPower.mana = 1, 1, 1
	local chatButtonsAlpha
	for _, entry in ipairs(ns.managed) do
		if entry.ownAlpha then
			SyncOwnAlpha(entry)
		end
		local target = 1
		-- (Typing always shows the input box, to see what you type, and the
		-- chat windows too where the Chat page's Typing row is on.)
		local typingShown = entry.group == "chat" and (typingWindows or (activeEditBox and entry.frame == activeEditBox))
		local chatShowing = (ns.chatPeekUntil[entry.frame] or 0) > now
			-- (An unread whisper brings up the Mouseover groups with it ticked,
			-- chat by default.)
			or typingShown
			-- (A docked window peeking brings its tabs and buttons too where the
			-- Chat page ticks them.)
			or (dockPeek and (entry.name == "GeneralDockManager" and ns.db.chatPeekTabs
				or entry.group == "chat" and NEVER_NESTED[entry.name] and ns.db.chatPeekButtons))
		entry.row = entry.row or ns.HoverRowFor(entry)
		-- (Its own row's group is its row too: see ns.RAID_STYLE_PARTY.)
		local ownRow = ownPartyRows and entry.rspGroup
		local row = ownRow or entry.row
		-- (Kept up by a setting, or brought up by an event ticked for one of its Mouseover groups.)
		local tracking = ((ns.db.alwaysShowMinimap or keepIndoors) and entry.group == "minimap")
			or (ns.db.alwaysShowWaypoint and entry.group == "waypoint")
			or (questTimerUp and entry.group == "questtimer")
			or (trackerTimerUp and entry.group == "quests" and entry.frame == _G.ObjectiveTrackerFrame)
			or (durabilityUp and entry.group == "misc")
			or (petUnhappyUp and entry.name == "PetFrame")
			or (triggered[row] and not (debuffsOnly and auraOnly[row]
				and (entry.name == "BuffFrame" or entry.name == "TemporaryEnchantFrame")))
		local listShown = combatShown
			and (entry.name and combatShown[entry.name] or combatShown[GROUP_KEY[ownRow or entry.group]])
		local fightingShown = listShown
		-- (Your frames kept up while you recover, or on low mana: PersonalResources.lua.)
		if not fightingShown and cinematic and (PORTRAIT_FRAMES[entry.name] or entry.name == "PetFrame")
			and ns.KeepYourFrameUp(PORTRAIT_FRAMES[entry.name], entry, portraitAllowed, fighting) then
			fightingShown = true -- shown like a combat frame, at the normal fade speeds
		end
		if cinematic and not hovered[row] and not chatShowing and not tracking
			and not fightingShown and (fadeChat or entry.group ~= "chat") then
			target = 0
		end
		if deathFade and deathKept[row] then
			target = 1
		elseif deathFade and not hovered[row] and not typingShown then
			target = 0
		end
		if immersive and not typingShown then
			target = 0
		end
		-- (Vitals Vision's health bars: up as far as your health says, LowHealth.lua.)
		entry.vitalsSecret = nil
		if target == 0 and cinematic and not deathFade and not immersive and PORTRAIT_FRAMES[entry.name]
			and entry.name ~= "CinematicPersonalPower" and entry.name ~= "CinematicPersonalMana" then
			local which = PORTRAIT_FRAMES[entry.name] == "prdWhenNotFull" and "prd" or "portrait"
			local vitals = ns.VitalsFrameAlpha(which, entry.frame == personalPower.healthStandIn)
			if vitals == "secret" then
				entry.vitalsSecret = which
			elseif vitals then
				target = vitals
			end
		end
		-- (Swing timer page: in CineMode and out, hovering included.)
		if entry.group == "swing" and ns.IsSwingBarUnused(entry.name) then
			target = 0
		end
		local follows = followsRow[entry.frame]
		if follows and ownPartyRows and entry.rspGroup then
			follows = ns.RAID_STYLE_PARTY[follows] or follows
		end
		if follows and cinematic and not hovered[follows] and not triggered[follows]
			and not (combatShown and combatShown[GROUP_KEY[follows]]) then
			target = 0
		end
		-- (/cine debug pad: why the gamepad bars come up, as they start to.)
		if ns.padDebug and entry.group == "gamepadbars" then
			local up = target > 0 and cinematic
			if up and not entry.debugUp then
				ns.Print(("gamepad bars up: %s%s%s%s"):format(hovered[entry.row] and "hovered " or "",
					padReveal and "button press " or "", listShown and "fight/target column " or "",
					tracking and not padReveal and "kept up " or ""))
			end
			entry.debugUp = up
		end
		-- (The header too: its bar, zone name, clock and buttons are groups of their own.)
		if camHidesMinimap and GROUP_SWITCH[entry.group] == "handleMinimap"
			and not hovered[row] and not pinged[row] then
			target = 0
		end
		-- (Fading out for a profile's layout change, Layouts.lua; then a
		-- profile's preview: just its group up, ns.PreviewProfile.)
		if ns.layoutFadeUntil then
			target = 0
		elseif ns.previewRows and not immersive then
			target = ns.previewRows[row] and 1 or 0
		end
		if entry.frame == Minimap then
			RedrawMinimapWhenShown()
		end
		-- (Show just that quest, Quest tracker page.)
		if entry.frame == _G.ObjectiveTrackerFrame and entry.group == "quests" then
			local shownAnyway = not cinematic or hovered[row] or fightingShown or ns.previewRows
			ns.QuestFocusTick(entry, shownAnyway or not ns.db.questRevealOnlyThat, elapsed,
				trackerTimerUp and not shownAnyway and (not triggered[row] or (questReveal and ns.db.questRevealOnlyThat)))
		end
		if typingShown and entry.alpha < 1 then
			-- Pressing Enter shows the chat input (and its window) at once.
			ns.SetEntryAlpha(entry, 1)
		elseif target == 0 and entry.alpha == 0 and not entry.shrinkWhenFaded
			and not LOOSE_PART_GROUPS[entry.group] and entry.frame ~= artStandIn then
			-- Faded and staying so: put back only if something changed its alpha
			-- (frames setting their own were seen to above).
			if not entry.ownAlpha then
				ReapplyIfChanged(entry)
			end
		-- Keep re-applying 0 while hidden in case Blizzard code resets the alpha;
		-- once fully revealed, leave the frame alone.
		elseif entry.alpha ~= target or target == 0 or entry.shrunk then
			local duration
			if target > entry.alpha then
				if castLeft and listShown and not hovered[row] then
					-- (The time for a whole fade at the pace that ends with the cast.)
					duration = castLeft > 0 and castLeft / (1 - entry.alpha) or ns.db.combatFadeInTime
				else
					duration = GroupFadeTime(entry.group, true)
				end
			else
				duration = deathFade and DEATH_FADE_TIME or GroupFadeTime(entry.group, false)
			end
			ns.SetEntryAlpha(entry, ns.Approach(entry.alpha, target, elapsed, duration))
		end
		-- (Secret health: the game sets a faded-out health bar's alpha from it.)
		if entry.vitalsSecret and target == 0 and entry.alpha == 0 and not ns.layoutFadeUntil and not ns.previewRows then
			ns.SetVitalsSecretAlpha(entry.frame, entry.vitalsSecret)
		end
		if NEVER_NESTED[entry.name] and entry.group == "chat" then
			chatButtonsAlpha = math.max(chatButtonsAlpha or 0, entry.alpha)
		end
		-- A chat window up just for a message: its background only where the
		-- Chat page's "Background" is ticked. (Held while the window fades out,
		-- so it doesn't come back for the fade.)
		if entry.isChatWindow == nil then
			entry.isChatWindow = entry.group == "chat" and type(entry.name) == "string"
				and entry.name:match("^ChatFrame%d+$") ~= nil
		end
		if entry.isChatWindow then
			if target > 0 then
				local peekOnly = cinematic and (ns.chatPeekUntil[entry.frame] or 0) > now and fadeChat
					and not hovered[row] and not typingShown and not tracking and not fightingShown
				entry.backgroundAlpha = ns.Approach(entry.backgroundAlpha or 1,
					(peekOnly and not ns.db.chatPeekBackground) and 0 or 1, elapsed, GroupFadeTime(entry.group, false))
			end
			if (entry.backgroundAlpha or 1) < 1 or entry.backgroundFaded then
				entry.backgroundFaded = entry.backgroundAlpha < 1
				if not entry.backgroundTextures then
					entry.backgroundTextures = {}
					for _, key in ipairs(ns.CHAT_BACKGROUND_TEXTURES) do
						local texture = _G[entry.name .. key]
						if texture and texture.SetAlpha then
							entry.backgroundTextures[#entry.backgroundTextures + 1] = texture
						end
					end
				end
				for _, texture in ipairs(entry.backgroundTextures) do
					ns.FadeRelative(texture, entry.backgroundAlpha)
				end
			end
		end
		if entry.frame == personalPower.healthStandIn then
			ns.SetPersonalPlateAlpha(entry.alpha)
		end
		if entry.group == "prd" then
			personalPower.health = entry.alpha
		elseif entry.group == "prdpower" then
			personalPower.level = entry.alpha
		elseif entry.group == "prdmana" then
			personalPower.mana = entry.alpha
		end
	end
	if personalPower.standIn then
		personalPower.Apply()
	end
	if ns.FadePersonalMana then
		ns.FadePersonalMana(personalPower.health, personalPower.mana)
	end
	-- A chat window's button column (inside the window on Classic clients)
	-- draws a strip of the window's dark background: it comes and goes with
	-- the chat buttons, so a window peeking for a message has no empty strip.
	for _, name in ipairs(ns.CHAT_BUTTON_COLUMNS) do
		local column = _G[name]
		if column and not IsForbidden(column) then
			ns.FadeRelative(column, chatButtonsAlpha or 1)
		end
	end
end

-- Frames beyond the built-in list (and built-in ones kept up): added ones (including auto-matched) and
-- ones the player chose to stop fading (an added one stays in extraFrames
-- then too, so it fades again when let go). Sorted for stable display.
-- Lists saved names rather than managed frames, so frames that don't exist
-- yet (created later in the session) still show.
function ns.GetExtraFrames()
	local faded, ignored = {}, {}
	for name in pairs(ns.db.extraFrames) do
		if not ns.db.ignoredFrames[name] then
			faded[#faded + 1] = name
		end
	end
	for name in pairs(ns.db.ignoredFrames) do
		ignored[#ignored + 1] = name -- (built-in frames kept with /cine keep too)
	end
	table.sort(faded)
	table.sort(ignored)
	return faded, ignored
end

function ns.StopFading(name)
	ns.db.ignoredFrames[name] = true
	if _G[name] then RemoveFrame(_G[name]) end
end

-- Built-in, auto-matched and added frames come back on the next scan.
function ns.UnignoreFrame(name)
	ns.db.ignoredFrames[name] = nil
end

-- Drops a frame from the extras list altogether: an added one stops fading
-- (without being remembered as stopped), a stopped one is no longer ignored.
function ns.ForgetExtraFrame(name)
	if ns.db.extraFrames[name] and _G[name] then RemoveFrame(_G[name]) end
	ns.db.extraFrames[name] = nil
	ns.db.ignoredFrames[name] = nil
end

-- Frames that don't take the mouse (the Cooldown Manager's icons, many
-- addons' bars) are invisible to GetMouseFoci, so failing that, the smallest
-- named, shown top-level frame the cursor is over. Smallest, so a frame
-- covering the whole screen doesn't win over the one actually being pointed at.
-- accept(frame): only frames it says yes to (add mode: ones not picked yet).
local function GetTopLevelFrameUnderCursor(accept)
	local best, bestArea
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not IsForbidden(frame) and frame ~= ns.letterbox and frame:GetName()
			and ns.Flag(frame:IsVisible()) and ns.Flag(frame:IsMouseOver()) and (not accept or accept(frame)) then
			local width, height = frame:GetSize()
			local area = (width or 0) * (height or 0)
			if not (issecretvalue and issecretvalue(area)) and area > 0 and (not bestArea or area < bestArea) then
				best, bestArea = frame, area
			end
		end
	end
	return best
end

-- The top-level (direct child of UIParent) frame under the cursor, so adding
-- e.g. a damage meter's bar picks up the whole meter window. Also the
-- outermost named frame below it that accept(frame) takes (any named one
-- without accept): an addon's button on one of the game's frames, like a
-- copy button on the chat window.
local function GetTopLevelFrameUnderMouse(accept)
	local focus = MouseFocus()
	local inner
	while focus and focus ~= UIParent do
		local parent = focus:GetParent()
		if parent == UIParent or parent == nil then
			if focus:GetName() then
				return focus, inner
			end
			break
		end
		if focus:GetName() and (not accept or accept(focus)) then
			inner = focus
		end
		focus = parent
	end
	return GetTopLevelFrameUnderCursor(), inner
end

-- name: a frame's global name (/cine add <name>), for frames that are hard
-- to hover; nil to use the one under the mouse.
function ns.AddUnderMouse(name)
	local frame
	if name and name ~= "" then
		frame = _G[name]
		if not IsFrame(frame) then
			ns.Print(L["no frame called %s (frame names are case-sensitive; /fstack shows them)."]:format(name))
			return
		end
	else
		local inner
		frame, inner = GetTopLevelFrameUnderMouse(function(f) return not seen[f] end)
		-- On a frame faded already (the chat window), its own named part.
		if inner and frame and seen[frame] then
			frame = inner
		end
		name = frame and frame:GetName()
	end
	if not name then
		ns.Print(L["hover over a named UI element, then type /cine add and press Enter " ..
			"(or /cine add <FrameName>). Frames without a name can't be added: the Advanced Frames " ..
			"settings page lists the addons faded out of the box."])
		return
	end
	if IsWindow(frame, name) then
		ns.Print(L["%s is a window, so it isn't faded (it would stay there invisible). " ..
			"Move the mouse off it onto the frame you want, then try again."]:format(name))
		return
	end
	for _, entry in ipairs(ns.managed) do
		if entry.frame == frame and not entry.group:find("^extra:") then
			ns.Print(L["%s is already faded as part of the built-in \"%s\" group."]:format(name, entry.group))
			return
		end
	end
	ns.db.ignoredFrames[name] = nil
	ns.db.extraFrames[name] = true
	AddFrame(frame, "extra:" .. name)
	ns.Print(L["now fading %s"]:format(name))
end

function ns.RemoveUnderMouse()
	local frame = GetTopLevelFrameUnderMouse()
	local name = frame and frame:GetName()
	if not name then
		ns.Print(L["hover over a faded UI element, then type /cine keep and press Enter."])
		return
	end
	ns.StopFading(name)
	ns.Print(L["%s will always be shown (untick its CineMode box under Custom frames on the Advanced Frames " ..
		"options page to undo)."]:format(name))
end

-- Add mode (/cine add mode): hovering frames collects them, and the second
-- /cine add mode fades them all. Only frames /cine add would take and that
-- aren't faded yet: not the game's own, not this addon's, not windows.
-- (In a do block: the file is near Lua's 200 locals.)
do
	local ADD_MODE_CHECK = 0.1 -- seconds between looks under the cursor
	local addMode            -- the ticker while on
	local pending = {}       -- names picked, in order
	local overlays = {}      -- name: its gold box
	local skipped = {}       -- names not to pick again this time: dropped, or kept (and told so)

	-- Whether the game made the frame's global (an addon's CreateFrame taints
	-- it), and if not, the addon that did.
	local function GlobalSource(name)
		if type(issecurevariable) ~= "function" then
			return false
		end
		local ok, secure, source = pcall(issecurevariable, name)
		if not ok then
			return false
		end
		return secure == true, type(source) == "string" and source or nil
	end

	-- A gold box over a collected frame, so it's clear what was picked.
	-- Unnamed and not taking the mouse, so the cursor checks never find it.
	local function ShowOverlay(frame, name)
		local overlay = CreateFrame("Frame", nil, UIParent)
		overlay:SetFrameStrata("TOOLTIP")
		overlay:SetAllPoints(frame)
		local fill = overlay:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetColorTexture(1, 0.82, 0, 0.2)
		local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOPLEFT", 2, -2)
		label:SetText(name)
		overlays[name] = overlay
	end

	-- The Advanced Frames page's button and list (see Options.lua).
	local function AddModeChanged()
		if ns.OnAddModeChanged then
			ns.OnAddModeChanged()
		end
	end

	-- Whether add mode can pick the frame: not picked or faded already, not the
	-- game's own or this addon's, not a window.
	local function Pickable(frame)
		local name = frame:GetName()
		if not name or overlays[name] or skipped[name] or seen[frame] or ns.db.extraFrames[name]
			or leftAlone[name] then
			return false
		end
		local game, source = GlobalSource(name)
		return not (game or source == ADDON_NAME or IsWindow(frame, name))
	end

	local function CheckUnderMouse()
		local frame, inner = GetTopLevelFrameUnderMouse(Pickable)
		-- One already picked or faded can sit over one that isn't (an action bar
		-- addon's buttons over its art bar): the smallest one under the cursor
		-- that is, then. (Not under a window or the game's frames: what's behind
		-- the settings window isn't being pointed at.) On one of the game's
		-- frames, an addon's named frame on it (a copy button on the chat window).
		local name = frame and frame:GetName()
		if name and inner and GlobalSource(name) then
			frame = inner
		elseif name and (overlays[name] or seen[frame] or ns.db.extraFrames[name]) then
			frame = GetTopLevelFrameUnderCursor(Pickable)
		elseif not (frame and Pickable(frame)) then
			return
		end
		if not frame then
			return
		end
		name = frame:GetName()
		local _, source = GlobalSource(name)
		if ns.db.ignoredFrames[name] then
			skipped[name] = true
			ns.Print(L["%s skipped: you set it to always show (untick its CineMode box under Custom frames " ..
				"on the Advanced Frames page)."]:format(name))
			return
		end
		pending[#pending + 1] = name
		ShowOverlay(frame, name)
		ns.Print(L["found %s"]:format(name) .. (source and (" (" .. source .. ")") or ""))
		AddModeChanged()
	end

	-- The frames picked so far, in the order found.
	function ns.GetPickedFrames()
		return pending
	end

	-- Takes a picked frame back out (the list's Drop), and doesn't pick it again.
	function ns.DropPickedFrame(name)
		for i, picked in ipairs(pending) do
			if picked == name then
				table.remove(pending, i)
				break
			end
		end
		if overlays[name] then
			overlays[name]:Hide()
			overlays[name] = nil
		end
		skipped[name] = true
		AddModeChanged()
	end

	-- The Advanced Frames page's search: every named frame add mode could
	-- pick (other addons', not faded yet), wherever it is, so frames under a
	-- window covering the screen can still be found. { name, source (the addon
	-- that made it), lower (both, lowercased, to match against) }, by name.
	local function Addable(name, frame)
		return not IsForbidden(frame) and type(frame.IsObjectType) == "function" and frame:IsObjectType("Frame")
			and frame:GetName() == name and Pickable(frame)
	end
	function ns.FindAddableFrames()
		local found = {}
		for name, frame in pairs(_G) do
			-- (pcall: a mixin table can look like a frame and error on its methods.)
			if type(name) == "string" and IsFrame(frame) then
				local ok, yes = pcall(Addable, name, frame)
				if ok and yes then
					local _, source = GlobalSource(name)
					found[#found + 1] = { name = name, source = source, lower = (name .. " " .. (source or "")):lower() }
				end
			end
		end
		table.sort(found, function(a, b) return a.name < b.name end)
		return found
	end

	-- A gold box over the frame a search match points at (nil: none). Whether
	-- it's on screen to mark.
	local marker
	function ns.MarkFrame(name)
		if marker then marker:Hide() end
		local frame = name and _G[name]
		if not (IsFrame(frame) and not IsForbidden(frame) and ns.Flag(frame:IsVisible())) then
			return false
		end
		if not marker then
			marker = CreateFrame("Frame", nil, UIParent)
			marker:SetFrameStrata("TOOLTIP")
			local fill = marker:CreateTexture(nil, "BACKGROUND")
			fill:SetAllPoints()
			fill:SetColorTexture(1, 0.82, 0, 0.3)
		end
		marker:ClearAllPoints()
		marker:SetAllPoints(frame)
		marker:Show()
		return true
	end

	local function EndAddMode()
		addMode:Cancel()
		addMode = nil
		for _, overlay in pairs(overlays) do
			overlay:Hide()
		end
		local names = pending
		pending, overlays, skipped = {}, {}, {}
		return names
	end

	function ns.IsAddModeOn()
		return addMode ~= nil
	end

	function ns.ToggleAddMode()
		if not addMode then
			addMode = C_Timer.NewTicker(ADD_MODE_CHECK, CheckUnderMouse)
			ns.Print(L["add mode: hover over the frames to fade. Type /cine add mode again to fade them " ..
				"(or /cine add cancel to drop them). The game's own frames and ones already faded are left out."])
			AddModeChanged()
			return
		end
		local added = 0
		for _, name in ipairs(EndAddMode()) do
			local frame = _G[name]
			if IsFrame(frame) then
				ns.db.ignoredFrames[name] = nil
				ns.db.extraFrames[name] = true
				AddFrame(frame, "extra:" .. name)
				added = added + 1
			end
		end
		ns.Print(added == 0 and L["add mode off: nothing found to add."]
			or (added == 1 and L["add mode off: now fading %d frame."] or L["add mode off: now fading %d frames."])
				:format(added))
		AddModeChanged()
	end

	function ns.CancelAddMode()
		if not addMode then
			ns.Print(L["add mode isn't on (/cine add mode starts it)."])
			return
		end
		local count = #EndAddMode()
		ns.Print((count == 1 and L["add mode canceled: %d frame left as it was."]
			or L["add mode canceled: %d frames left as they were."]):format(count))
		AddModeChanged()
	end
end

function ns.ListExtras()
	local faded, ignored = ns.GetExtraFrames()
	for _, name in ipairs(faded) do ns.Print(L["fading %s"]:format(name)) end
	for _, name in ipairs(ignored) do ns.Print(L["ignoring %s"]:format(name)) end
	if #faded + #ignored == 0 then
		ns.Print(L["no extra frames."])
	end
end

-- For supported addons' setups (Support/), which run only once their addon
-- has loaded. A frame already faded is let go, to be picked up again by the
-- next scan the new way.
local function LetGo(name)
	local frame = _G[name]
	if frame and seen[frame] then
		RemoveFrame(frame)
	end
end

-- Its frames that stand in for the game's: they fade in that group and follow
-- the Standard Frames page's row (by key, see COMBAT_SHOW). own: they set
-- their own alpha; hook: follow it at once (the addon's own frames only).
function ns.FadeWithRow(rowKey, group, names, own, hook)
	local row
	for _, item in ipairs(ns.COMBAT_SHOW) do
		if item.key == rowKey then
			row = item
		end
	end
	for _, name in ipairs(names) do
		AddName(FRAME_GROUPS[group], name)
		if row and row.frames then
			AddName(row.frames, name)
		end
		ownAlphaNames[name] = own or nil
		hookedNames[name] = hook or nil
		LetGo(name)
	end
end

-- Game frames whose alpha the addon sets: followed (checked, never hooked).
function ns.FollowOwnAlpha(names)
	for _, name in ipairs(names) do
		ownAlphaNames[name] = true
		LetGo(name)
	end
end

-- Game frames the addon hides for good: never faded.
-- An addon took the bar over (and may keep it at alpha 0): its art goes back
-- to following the bar.
local function ReleaseBarArt(barName)
	for i = #barArt, 1, -1 do
		local art = barArt[i]
		if art.bar == barName then
			if art.region.SetIgnoreParentAlpha then
				art.region:SetIgnoreParentAlpha(false)
			end
			art.region:SetAlpha(1)
			table.remove(barArt, i)
		end
	end
end

function ns.LeaveAlone(names)
	for _, name in ipairs(names) do
		leftAlone[name] = true
		ReleaseBarArt(name)
		LetGo(name)
	end
end

-- A frame its own search found (see ns.AddScanner), unnamed ones too. own and
-- hook as for ns.FadeWithRow.
function ns.AddFoundFrame(frame, group, own, hook)
	ownAlphaFrames[frame] = own or nil
	hookedFrames[frame] = hook or nil
	return AddFrame(frame, group)
end

function ns.IsFaded(frame)
	return seen[frame] or false
end

-- fn runs with each scan for the frames to fade.
function ns.AddScanner(fn)
	table.insert(scanners, fn)
end

-- fn runs each time the minimap gets its size back after being faded.
function ns.OnMinimapRestored(fn)
	table.insert(restoredHandlers, fn)
end

-- Its player frame, shown like the game's while health or power recovers.
function ns.AddPortraitFrame(name)
	PORTRAIT_FRAMES[name] = "portraitWhenNotFull"
end

-- A raid frame's ready check icon: retail's readyCheckIcon texture, WoW
-- Forever's a frame named after the member's (<name>ReadyCheckIcon). That
-- frame's alpha is the game's, set (secret) as it dims members out of range,
-- so its texture inside (Icon) is what fades.
function ns.RaidReadyCheckIcon(frame)
	local name = frame.GetName and frame:GetName()
	local icon = frame.readyCheckIcon or frame.ReadyCheckIcon or (name and _G[name .. "ReadyCheckIcon"])
	return type(icon) == "table" and icon.Icon or icon
end

-- /cine debug readycheck: each raid frame's ready check icon, whether it's
-- faded as the Ready check row (and how far), and whether CineMode is on.
function ns.ReportRaidReadyCheck()
	ns.Print(("CineMode=%s, Ready check row Always=%s"):format(tostring(ns.lastCinematic),
		tostring(ns.IsCineShowOn("raidready"))))
	local count = 0
	for _, holderName in ipairs({ "CompactRaidFrameContainer", "CompactPartyFrame" }) do
		local holder = _G[holderName]
		local members = {}
		if holder and not IsForbidden(holder) then
			for _, child in ipairs({ holder:GetChildren() }) do
				if not IsForbidden(child) then
					local name = child:GetName()
					if name and name:find("^CompactRaidGroup%d+$") then
						for _, member in ipairs({ child:GetChildren() }) do
							members[#members + 1] = member
						end
					else
						members[#members + 1] = child
					end
				end
			end
		end
		for _, member in ipairs(members) do
			local icon = not IsForbidden(member) and ns.RaidReadyCheckIcon(member)
			if icon and ns.Flag(icon:IsVisible()) then
				count = count + 1
				local managed = "not faded"
				for _, entry in ipairs(ns.managed) do
					if entry.frame == icon then
						managed = ("group=%s fade=%.2f"):format(entry.group, entry.alpha)
						break
					end
				end
				local alpha = icon:GetAlpha()
				ns.Print(("  %s: %s, alpha=%s, %s"):format(icon:GetDebugName(), icon:GetObjectType(),
					(issecretvalue and issecretvalue(alpha)) and "secret" or ("%.2f"):format(alpha), managed))
			end
		end
	end
	if count == 0 then
		ns.Print("  no ready check icons shown (start one with /readycheck)")
	end
end

-- The raid frames (and raid-style party frames): each member's frame, or
-- each group's when groups are kept together, in raidplayers; pets in
-- raidpets; and their parts (PART_GROUPS) in theirs. The game makes and
-- reuses them as the group changes (one can go from a player to a pet), so
-- they're sorted afresh at each scan, and soon after the group changes.
do
	-- (While sorting the raid-style party frames: theirs get their own rows'
	-- groups as well (rspGroup), for when they're set apart from the raid frames.)
	local sortingParty = false
	local function SortRaidPart(part, group)
		if not part or IsForbidden(part) then
			return
		end
		if seen[part] then
			for _, entry in ipairs(ns.managed) do
				if entry.frame == part then
					if entry.group == group then
						entry.rspGroup = sortingParty and ns.RAID_STYLE_PARTY[group] or nil
						return
					end
					RemoveFrame(part) -- (sorted again below)
					break
				end
			end
		end
		if AddFrame(part, group) then
			ns.managed[#ns.managed].rspGroup = sortingParty and ns.RAID_STYLE_PARTY[group] or nil
		end
	end

	local function GroupTitle(group)
		local name = group:GetName()
		return group.title or (name and _G[name .. "Title"])
	end

	-- A member's or pet's frame (inGroup: inside a group's frame, which fades
	-- for it), and its parts.
	local function SortUnitFrame(frame, inGroup)
		local unit = frame.unit or frame.displayedUnit
		if Secret(unit) or type(unit) ~= "string" then
			return
		end
		local isPet = unit:find("pet") ~= nil
		if not inGroup then
			SortRaidPart(frame, isPet and "raidpets" or "raidplayers")
		end
		SortRaidPart(frame.roleIcon, "raidroles")
		-- (The game only shows and hides it, never sets its alpha.)
		SortRaidPart(frame.aggroHighlight, "raidthreat")
		-- (The white outline round your target's frame: shown and hidden too.)
		SortRaidPart(frame.selectionHighlight, "raidtarget")
		SortRaidPart(ns.RaidReadyCheckIcon(frame), "raidready")
		SortRaidPart(frame.name, isPet and "raidpetnames" or "raidnames")
		for _, aura in ipairs(frame.buffFrames or {}) do
			SortRaidPart(aura, "raidbuffs")
		end
		for _, list in ipairs({ frame.debuffFrames or {}, frame.dispelDebuffFrames or {} }) do
			for _, aura in ipairs(list) do
				SortRaidPart(aura, "raiddebuffs")
			end
		end
	end

	local function ScanRaidFrames()
		for _, holderName in ipairs({ "CompactRaidFrameContainer", "CompactPartyFrame" }) do
			local holder = _G[holderName]
			sortingParty = holderName == "CompactPartyFrame"
			if holder and not IsForbidden(holder) then
				if sortingParty then
					local title = GroupTitle(holder) -- ("Party")
					SortRaidPart(title, "raidtitles")
					if title then
						followsRow[title] = "raidplayers"
					end
				end
				for _, child in ipairs({ holder:GetChildren() }) do
					if not IsForbidden(child) then
						local name = child:GetName()
						if name and name:find("^CompactRaidGroup%d+$") then
							SortRaidPart(child, "raidplayers")
							SortRaidPart(GroupTitle(child), "raidtitles") -- ("Group 1")
							for _, member in ipairs({ child:GetChildren() }) do
								if not IsForbidden(member) then
									SortUnitFrame(member, true)
								end
							end
						else
							SortUnitFrame(child, false)
						end
					end
				end
			end
		end
		sortingParty = false
	end
	ns.AddScanner(ScanRaidFrames)

	-- WoW Forever's raid frames draw their auras as forbidden frames, out of
	-- reach (no buffFrames lists, nor the functions that fill them): there the
	-- Buffs and Debuffs rows switch the game's own settings instead. A stand-in
	-- fades as the row says, as the bar art's does, and each frame its alpha
	-- turns the setting off (under half) or back on. The player changing it in
	-- the game's options wins (playerWins), as for the addon's other settings.
	local AURA_CVAR_ROWS = { raidbuffs = "raidFramesDisplayBuffs", raiddebuffs = "raidFramesDisplayDebuffs" }
	local auraStandIns = {}
	local function AddAuraStandIns()
		if _G.CompactUnitFrame_UtilSetBuff then
			return -- (aura icons as frames: faded as parts)
		end
		for group, cvar in pairs(AURA_CVAR_ROWS) do
			if not auraStandIns[group] and GetCVar(cvar) ~= nil then
				local set = { values = { [cvar] = "0" }, playerWins = true }
				local standIn = CreateFrame("Frame", nil, UIParent)
				standIn:SetSize(1, 1)
				standIn:SetPoint("TOPLEFT")
				standIn:SetScript("OnUpdate", function(self)
					ns.ApplyCVarSet(set, self:GetAlpha() < 0.5)
				end)
				auraStandIns[group] = standIn
			end
			if auraStandIns[group] then
				AddFrame(auraStandIns[group], group)
			end
		end
	end
	ns.AddScanner(AddAuraStandIns)

	-- A party member's frame, with its role icon and name (retail's are
	-- parent keys, Classic's named after the frame).
	-- The party frames dim members out of range (and light them back up) with
	-- their own SetAlpha, so while faded one flashed up until the next tick
	-- put ours back. Their own scripts are followed by ours straight away
	-- instead, as for the cast bars. Script hooks, not method hooks (see
	-- AddFrame); one for a frame no longer faded does nothing.
	local partyEntries = {} -- frame -> its entry (entry.removed once let go)
	local onPartyScript = ns.Profiled("Party frame alpha hook", function(frame)
		local entry = partyEntries[frame]
		if entry and not entry.removed and entry.alpha < 1 then
			ReapplyIfChanged(entry)
		end
	end)
	local function HookPartyScripts(frame)
		if partyEntries[frame] == nil and frame.HookScript then
			frame:HookScript("OnEvent", onPartyScript)
			frame:HookScript("OnShow", onPartyScript)
			frame:HookScript("OnUpdate", onPartyScript)
		end
		partyEntries[frame] = ns.managed[#ns.managed]
	end

	local function SortPartyFrame(frame)
		if not frame or IsForbidden(frame) then
			return
		end
		if AddFrame(frame, "party") then
			HookPartyScripts(frame)
		end
		local name = frame:GetName()
		local overlay = frame.PartyMemberOverlay
		SortRaidPart((overlay and overlay.RoleIcon) or frame.RoleIcon or (name and _G[name .. "RoleIcon"]),
			"partyroles")
		SortRaidPart(frame.Name or (name and _G[name .. "Name"]), "partynames")
		-- The icon for a summon on its way, or a member phased or elsewhere,
		-- ignores its frame's alpha (it stays bright as the frame dims), so it
		-- fades on its own: as its row says, and only while the frames are up.
		local status = frame.NotPresentIcon or (name and _G[name .. "NotPresentIcon"])
		SortRaidPart(status, "partystatus")
		if status then
			followsRow[status] = "party"
		end
	end

	-- Retail's party frames (unnamed, from a pool) are in PartyFrame, and so
	-- are the raid-style ones (CompactPartyFrame): fading the holder would
	-- fade those too, so its members fade instead.
	local function ScanPartyFrames()
		for i = 1, 4 do
			SortPartyFrame(_G["PartyMemberFrame" .. i])
		end
		local holder = _G.PartyFrame
		if not holder or IsForbidden(holder) then
			return
		end
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= _G.CompactPartyFrame then
				SortPartyFrame(child)
			end
		end
	end
	ns.AddScanner(ScanPartyFrames)

	local rosterWatcher = CreateFrame("Frame")
	rosterWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	rosterWatcher:RegisterEvent("UNIT_PET") -- (a pet's frame comes and goes)
	rosterWatcher:SetScript("OnEvent", function()
		-- (After the game has set its frames up for the new group.)
		C_Timer.After(0.5, function()
			if ns.db then
				ScanRaidFrames()
				RecomputeNesting()
			end
		end)
	end)
end

-- Unit frame parts (Unit Frames page): pieces of the player, pet, target,
-- focus and target of target frames hidden, CineMode or not, for those who
-- only want the bars. A section per frame, a Standard Frames row per part
-- (FRAMES.Hidden). One texture (FrameTexture) draws the portrait ring, the name box and
-- the bars' borders, so the frame art goes as a whole. Retail's (and WoW
-- Forever's) frame fields, then the classic clients' (their globals: _G.,
-- or @ for one named after the frame, as TargetFrame and FocusFrame share them).
do
	local PLAYER = {
		Portrait = { "PlayerFrameContainer.PlayerPortrait", "_G.PlayerPortrait" },
		Level = { "PlayerFrameContent.PlayerFrameContentMain.LevelBackgroundCircle", "_G.PlayerLevelText" },
		Name = { "_G.PlayerName" },
		-- The health and power bars (the containers retail and WoW Forever
		-- hold them in; healthbar and manabar: the keys the game keeps them on,
		-- every client).
		Health = { "PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer", "healthbar" },
		Power = { "PlayerFrameContent.PlayerFrameContentMain.ManaBarArea", "manabar" },
		-- Their numbers (percent, value), on the bars: hidden with a bar too.
		-- (The class's second power bar's as well, druid mana and the like.)
		Numbers = { "healthbar.TextString", "healthbar.LeftText", "healthbar.RightText",
			"manabar.TextString", "manabar.LeftText", "manabar.RightText",
			"_G.AlternatePowerBar.TextString", "_G.AlternatePowerBar.LeftText", "_G.AlternatePowerBar.RightText" },
		-- (Each frame art the game swaps in: vehicle, class resource bar.)
		Art = { "PlayerFrameContainer.FrameTexture", "PlayerFrameContainer.AlternatePowerFrameTexture",
			"PlayerFrameContainer.VehicleFrameTexture", "PlayerFrameContainer.FrameFlash",
			"PlayerFrameContent.PlayerFrameContentMain.StatusTexture",
			"PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon",
			-- (The aggro glow, under the key the game keeps it on every client.)
			"threatIndicator",
			"_G.PlayerFrameTexture", "_G.PlayerFrameVehicleTexture", "_G.PlayerFrameFlash",
			"_G.PlayerStatusTexture", "_G.PlayerStatusGlow", "_G.PlayerAttackBackground",
			-- (Classic's dark backdrop behind the bars, a texture of its own.)
			"_G.PlayerFrameBackground" },
		-- The damage and healing numbers on the portrait (feedbackText: where
		-- the game keeps them on every client).
		CombatText = { "feedbackText", "PlayerFrameContent.PlayerFrameContentMain.HitIndicator.HitText",
			"_G.PlayerHitIndicator" },
		-- (The faction flag, or the honor-level badge in its place, and the
		-- flag's timer. PvpBackgroundIcon: the flag WoW Forever shows by the
		-- level while the flag's timer runs, from /fstack.)
		PvP = { "PlayerFrameContent.PlayerFrameContentContextual.PVPIcon",
			"PlayerFrameContent.PlayerFrameContentMain.PvpBackgroundIcon",
			"PlayerFrameContent.PlayerFrameContentContextual.PrestigePortrait",
			"PlayerFrameContent.PlayerFrameContentContextual.PrestigeBadge", "_G.PlayerPVPTimerText",
			"_G.PlayerPVPIcon", "_G.PlayerPrestigePortrait", "_G.PlayerPrestigeBadge" },
		-- (The rest Zzz, the group leader's crown, the role and combat icons
		-- and the raid group number.)
		Icons = { "PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop",
			"PlayerFrameContent.PlayerFrameContentContextual.LeaderIcon",
			"PlayerFrameContent.PlayerFrameContentContextual.GuideIcon",
			"PlayerFrameContent.PlayerFrameContentContextual.RoleIcon",
			"PlayerFrameContent.PlayerFrameContentContextual.AttackIcon",
			"PlayerFrameContent.PlayerFrameContentContextual.GroupIndicator",
			"_G.PlayerRestIcon", "_G.PlayerRestGlow", "_G.PlayerLeaderIcon", "_G.PlayerMasterIcon",
			"_G.PlayerGuideIcon", "_G.PlayerFrameRoleIcon", "_G.PlayerAttackIcon", "_G.PlayerAttackGlow",
			"_G.PlayerFrameGroupIndicator" },
	}
	-- (Fields on TargetFrame, and on FocusFrame, built the same way.)
	local TARGET = {}
	-- Buffs and debuffs: frames the game takes from a pool as it draws them
	-- (auraPools), or numbered globals (TargetFrameBuff1...) on older frames.
	-- (A function: the frames change as auras come and go. No locals of its
	-- own here: this file's main chunk is at Lua's cap of 200.)
	TARGET.Auras = function(frame)
		local list = {}
		local pools = frame.auraPools
		-- (WoW Forever: one frame holds them all, from GetAuraContainer.)
		local ok, container = pcall(function() return frame.GetAuraContainer and frame:GetAuraContainer() end)
		if ok and type(container) == "table" and container.SetAlpha then
			list[1] = container
		elseif pools and pools.EnumerateActive then
			for aura in pools:EnumerateActive() do
				list[#list + 1] = aura
			end
		else
			local name = frame.GetName and frame:GetName()
			for _, kind in ipairs({ "Buff", "Debuff" }) do
				for i = 1, 40 do
					local aura = name and _G[name .. kind .. i]
					if not aura then break end
					list[#list + 1] = aura
				end
			end
		end
		return list
	end
	for part, paths in pairs({
		Portrait = { "TargetFrameContainer.Portrait", "@Portrait" },
		Level = { "TargetFrameContent.TargetFrameContentMain.LevelBackgroundCircle",
			"TargetFrameContent.TargetFrameContentMain.LevelText",
			"TargetFrameContent.TargetFrameContentContextual.HighLevelTexture",
			"@TextureFrameLevelText", "@TextureFrameHighLevelTexture" },
		-- (The coloured strip behind it with it.)
		Name = { "TargetFrameContent.TargetFrameContentMain.Name",
			"TargetFrameContent.TargetFrameContentMain.ReputationColor",
			"@TextureFrameName", "@NameBackground" },
		Health = { "TargetFrameContent.TargetFrameContentMain.HealthBarsContainer", "healthbar" },
		Power = { "TargetFrameContent.TargetFrameContentMain.ManaBar", "manabar" },
		Numbers = { "healthbar.TextString", "healthbar.LeftText", "healthbar.RightText",
			"manabar.TextString", "manabar.LeftText", "manabar.RightText" },
		Art = { "TargetFrameContainer.FrameTexture", "TargetFrameContainer.Flash",
			"TargetFrameContainer.BossPortraitFrameTexture", "threatIndicator",
			"@TextureFrameTexture", "@Flash", "@Background" },
		-- (PvpBackgroundIcon: the flag WoW Forever shows by the level, tested.)
		PvP = { "TargetFrameContent.TargetFrameContentContextual.PvpIcon",
			"TargetFrameContent.TargetFrameContentContextual.PvpBackgroundIcon",
			"TargetFrameContent.TargetFrameContentContextual.PrestigePortrait",
			"TargetFrameContent.TargetFrameContentContextual.PrestigeBadge",
			"@TextureFramePVPIcon", "@TextureFramePrestigePortrait", "@TextureFramePrestigeBadge" },
		-- (The group leader's crown, the quest and pet battle icons, and the
		-- raid target marker: skull, moon... BossIcon: retail's quest "!" and
		-- rare star by the bars.)
		Icons = { "TargetFrameContent.TargetFrameContentContextual.LeaderIcon",
			"TargetFrameContent.TargetFrameContentContextual.RaidTargetIcon",
			"TargetFrameContent.TargetFrameContentContextual.GuideIcon",
			"TargetFrameContent.TargetFrameContentContextual.QuestIcon",
			"TargetFrameContent.TargetFrameContentContextual.BossIcon",
			"TargetFrameContent.TargetFrameContentContextual.PetBattleIcon",
			"@TextureFrameLeaderIcon", "@TextureFrameRaidTargetIcon", "@TextureFrameQuestIcon",
			"@TextureFramePetBattleIcon" },
	}) do
		TARGET[part] = paths
	end
	-- Your pet's frame: no level or PvP of its own, and for icons only the
	-- hunter pet's happiness face, where the client has one (not retail).
	local PET = {
		Portrait = { "portrait", "_G.PetPortrait" },
		Name = { "name", "_G.PetName" },
		Health = { "healthbar" },
		Power = { "manabar" },
		Numbers = { "healthbar.TextString", "healthbar.LeftText", "healthbar.RightText",
			"manabar.TextString", "manabar.LeftText", "manabar.RightText" },
		-- (The aggro glow and the attack pulse, the red ring in a fight: by
		-- their keys too, for clients that don't name them.)
		Art = { "_G.PetFrameTexture", "_G.PetFrameFlash", "_G.PetAttackModeTexture", "threatIndicator",
			"AttackModeTexture", "Flash", "FrameTexture" },
		CombatText = { "feedbackText", "_G.PetHitIndicator" },
		Icons = _G.PetFrameHappiness and { "_G.PetFrameHappiness" } or nil,
	}
	-- The target of target frames (the target's and the focus's): a portrait,
	-- a name, the bars and the frame art, and on older frames numbered debuffs
	-- (TargetFrameToTDebuff1...). (In ns, not a local: see the cap above.)
	ns.UNIT_PARTS_TOT = { Portrait = { "Portrait", "@Portrait" }, Name = { "Name", "@TextureFrameName" },
		Art = { "FrameTexture", "@TextureFrameTexture", "@Background" },
		Health = { "HealthBar", "healthbar" }, Power = { "ManaBar", "manabar" } }
	if _G.TargetFrameToTDebuff1 then
		ns.UNIT_PARTS_TOT.Auras = function(frame)
			local list, name = {}, frame.GetName and frame:GetName()
			for i = 1, 40 do
				local aura = name and _G[name .. "Debuff" .. i]
				if not aura then break end
				list[#list + 1] = aura
			end
			return list
		end
	end
	-- The threat percentage over the frame and its aggro glow (also frame art:
	-- hidden while either column says so). By the keys the game keeps them
	-- on, the same on the target and focus frames.
	TARGET.Threat = { "threatNumericIndicator", "threatIndicator" }
	-- The cast bar under the frame (spellbar on every client; by its name too).
	TARGET.CastBar = function(frame)
		local name = frame.GetName and frame:GetName()
		local bar = frame.spellbar or name and _G[name .. "SpellBar"]
		return type(bar) == "table" and bar.SetAlpha and { bar } or {}
	end
	ns.UNIT_PARTS_PLAYER, ns.UNIT_PARTS_PET, ns.UNIT_PARTS_TARGET = PLAYER, PET, TARGET
	-- Each frame: its parts, the unit it shows and its section (unitPart<section><part>).
	-- The focus and target of target ones: the setting that has them go by
	-- the target's section, and their own otherwise.
	local FRAMES = {
		{ "PlayerFrame", PLAYER, "player", "Player" },
		{ "TargetFrame", TARGET, "target", "Target" },
		{ "FocusFrame", TARGET, "focus", "Focus", "unitPartsFocusSame" },
		{ "TargetFrameToT", ns.UNIT_PARTS_TOT, "targettarget", "ToT", "unitPartsToTSame" },
		{ "FocusFrameToT", ns.UNIT_PARTS_TOT, "focustarget", "FocusToT", "unitPartsFocusToTSame" },
		{ "PetFrame", PET, "pet", "Pet" },
	}
	-- The setting for a frame's part.
	function FRAMES.Key(entry, part)
		local same = entry[5] and ns.db[entry[5]] ~= false
		return "unitPart" .. (same and "Target" or entry[4]) .. part
	end

	-- A field on a frame (_G. for a global of its own, @ for the global named
	-- after the frame: @Portrait on TargetFrame is TargetFramePortrait).
	local function Field(frame, path)
		if path:sub(1, 1) == "@" then
			local name = frame.GetName and frame:GetName()
			path = name and "_G." .. name .. path:sub(2) or ""
		end
		local value = frame
		for name in path:gmatch("[^.]+") do
			if name == "_G" and value == frame then
				value = _G
			elseif type(value) ~= "table" then
				return nil
			else
				value = value[name]
			end
		end
		if type(value) == "table" and value.SetAlpha then
			return value
		end
	end

	local function Ask(fn, ...)
		local ok, value = pcall(fn, ...)
		if not ok or (issecretvalue and issecretvalue(value)) then
			return nil
		end
		return value
	end

	-- [region] = the alpha to put back. While hidden, the game setting the
	-- alpha (the rest glow pulses) is undone.
	local hidden, hooked = {}, {}
	-- (For /cine debug unitframes: which regions are held hidden.)
	ns.unitPartsHidden = hidden
	local setting = false
	-- (Held at none, or as far as the mouse has faded its frame back in:
	-- FRAMES.show, below.)
	local function KeepHidden(region)
		if hidden[region] and not setting then
			setting = true
			region:SetAlpha(hidden[region] * (FRAMES.show[FRAMES.owner[region]] or 0))
			setting = false
		end
	end

	local function SetHidden(region, hide)
		if hide and not hidden[region] then
			-- (WoW Forever can keep a cast bar's alpha secret: full put back then.)
			local alpha = region:GetAlpha()
			hidden[region] = not (issecretvalue and issecretvalue(alpha)) and alpha or 1
			if not hooked[region] then
				hooked[region] = true
				hooksecurefunc(region, "SetAlpha", KeepHidden)
				-- (WoW Forever's frames also set it this way, which SetAlpha's hook misses.)
				if type(region.SetAlphaFromBoolean) == "function" then
					hooksecurefunc(region, "SetAlphaFromBoolean", KeepHidden)
				end
				-- (A texture's colour carries its alpha: the game colouring the
				-- target's name strip by its faction shows it again, tested.)
				if type(region.SetVertexColor) == "function" then
					hooksecurefunc(region, "SetVertexColor", KeepHidden)
				end
				-- (And a text's colour, for the hit numbers; and, textures and
				-- texts only, shown again, for the glows the game shows in a fight.)
				if type(region.SetTextColor) == "function" then
					hooksecurefunc(region, "SetTextColor", KeepHidden)
				end
				if not (region.IsObjectType and region:IsObjectType("Frame")) then
					hooksecurefunc(region, "Show", KeepHidden)
					hooksecurefunc(region, "SetShown", KeepHidden)
				end
			end
			KeepHidden(region)
		elseif not hide and hidden[region] then
			local alpha = hidden[region]
			hidden[region] = nil
			region:SetAlpha(alpha)
		end
	end

	-- Whether this client's frames have the parts (the Unit Frames page shows the grid then).
	function ns.HasUnitFrameParts()
		for _, path in ipairs(_G.PlayerFrame and PLAYER.Portrait or {}) do
			if Field(_G.PlayerFrame, path) then
				return true
			end
		end
		return false
	end

	-- (Settings unitPart<frame><part>, ticked = shown: see ns.UNIT_PART_FRAMES.)
	-- Each part a Standard Frames row (the setting: its Always), keyed by the
	-- setting: shown as that row is now (its rule, if it has one). One that
	-- isn't simply always shown has the frames applied again as things change
	-- (FRAMES.dynamic: the watcher below).
	function FRAMES.Hidden(key)
		if not key then
			return false
		end
		local db = ns.db
		if not (db[key] == false or ns.RuleTest(key) or (db.tankHide and db.tankHide[key])
			or (db.healerHide and db.healerHide[key]) or (db.damageHide and db.damageHide[key])) then
			return false -- (Always, no rule or roles: shown, without working out the rest)
		end
		FRAMES.dynamic = true
		return not ns.RowOnNow(key, db[key] ~= false, true)
	end
	-- A region in two parts (the target's aggro glow: frame art and threat)
	-- is hidden while either says so: gathered first in want, then set.
	FRAMES.want = {}
	-- Frames the mouse brings up (UpdateFrames, each tick): their hidden parts
	-- fade in with them at the fade in time, and out at the fade out time.
	-- (show[frame name]: 0 to 1, how far in; owner[region]: its frame's name.)
	FRAMES.show, FRAMES.owner = {}, {}
	ns.UNIT_PART_FRAME_NAMES = {}
	for _, entry in ipairs(FRAMES) do
		ns.UNIT_PART_FRAME_NAMES[entry[1]] = true
	end
	function ns.SetUnitPartsHovered(names, elapsed)
		local changed = false
		for name in pairs(ns.UNIT_PART_FRAME_NAMES) do
			local was = FRAMES.show[name] or 0
			local goal = names[name] and 1 or 0
			if was ~= goal then
				local time = goal > was and ns.FadeInTime() or ns.FadeOutTime()
				local step = time > 0 and (elapsed or 0) / time or 1
				FRAMES.show[name] = goal > was and math.min(goal, was + step) or math.max(goal, was - step)
				changed = true
			end
		end
		if changed then
			for region in pairs(hidden) do
				KeepHidden(region)
			end
		end
	end
	function ns.ApplyUnitFrameParts()
		if not ns.db then
			return
		end
		local want = FRAMES.want
		FRAMES.dynamic = false
		for _, entry in ipairs(FRAMES) do
			local frame = _G[entry[1]]
			if frame then
				for _, part in ipairs(ns.UNIT_PARTS) do
					local key = FRAMES.Key(entry, part)
					local hide = ns.db.handleUnitFrames ~= false and FRAMES.Hidden(key)
					local paths = entry[2][part]
					if type(paths) == "function" then
						for _, region in ipairs(paths(frame)) do
							want[region] = want[region] or hide
							FRAMES.owner[region] = FRAMES.owner[region] or entry[1]
						end
					else
						for _, path in ipairs(paths or {}) do
							local region = Field(frame, path)
							if region then
								want[region] = want[region] or hide
								FRAMES.owner[region] = FRAMES.owner[region] or entry[1]
							end
						end
					end
				end
			end
		end
		-- The focus's target of target as a whole (its Standard Frames row's box,
		-- WoW Forever only): held at no alpha, and not clickable either. (Its
		-- mouse only out of combat: the game guards it in one; set after the fight.)
		local tot = _G.FocusFrameToT
		if tot then
			local hide = not ns.isRetail and ns.db.handleFrames ~= false and ns.db.unitPartsFocusToT == false
			want[tot] = hide
			-- (Shown again at the alpha its Standard Frames row fades it to now,
			-- not the one it had when hidden.)
			for _, entry in ipairs(hidden[tot] and not hide and ns.managed or NO_DEFAULTS) do
				if entry.frame == tot and entry.applied then
					hidden[tot] = entry.applied
				end
			end
			-- (Left alone unless we turned it off: FRAMES.totMouseOff.)
			if hide ~= (FRAMES.totMouseOff or false) and not InCombatLockdown() then
				tot:EnableMouse(not hide)
				FRAMES.totMouseOff = hide
			end
		end
		for region, hide in pairs(want) do
			SetHidden(region, hide)
		end
		wipe(want)
	end

	-- (For /cine debug unitframes: what a part of the target and focus frames
	-- goes by right now, a line per region.)
	function ns.UnitPartDebug(part)
		-- (Applied first, any error said: a part decided hidden but not held.)
		local ok, err = pcall(ns.ApplyUnitFrameParts)
		wipe(FRAMES.want)
		local lines = { "apply: " .. (ok and "ok" or tostring(err)) }
		for _, entry in ipairs(FRAMES) do
			local frame = _G[entry[1]]
			local paths = frame and entry[2][part]
			if type(paths) == "function" then
				local key = FRAMES.Key(entry, part)
				for _, region in ipairs(paths(frame)) do
					lines[#lines + 1] = ("%s %s: %s = %s, rule %s, hide %s, held %s, alpha %s"):format(
						entry[1], part, tostring(key), tostring(key and ns.db[key]),
						tostring(key and ns.RuleTest(key) ~= nil), tostring(FRAMES.Hidden(key)),
						tostring(hidden[region]), tostring(Ask(region.GetAlpha, region)))
				end
			end
		end
		return lines
	end

	-- The game draws the target's and focus's auras again as they change,
	-- taking frames from its pool: those go by the grid too. (In a function
	-- of its own, for the cap of 200 locals.)
	(function()
	local function AurasDrawn(frame)
		if not ns.db then
			return
		end
		for _, entry in ipairs(FRAMES) do
			if _G[entry[1]] == frame and entry[2].Auras then
				local key = FRAMES.Key(entry, "Auras")
				local hide = FRAMES.Hidden(key)
				for _, region in ipairs(entry[2].Auras(frame)) do
					SetHidden(region, hide)
				end
			end
		end
	end
	for _, name in ipairs({ "TargetFrame", "FocusFrame" }) do
		local frame = _G[name]
		if frame and type(frame.UpdateAuras) == "function" then
			hooksecurefunc(frame, "UpdateAuras", AurasDrawn)
		end
	end
	if type(_G.TargetFrame_UpdateAuras) == "function" then
		hooksecurefunc("TargetFrame_UpdateAuras", AurasDrawn)
	end

	-- The game redrawing a frame's level or art (logging in, a level-up, a
	-- vehicle) can bring a hidden part back: hidden again straight after.
	local function Rehide()
		for region in pairs(hidden) do
			KeepHidden(region)
		end
	end
	for _, name in ipairs({ "PlayerFrame_UpdateLevel", "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt",
		"TargetFrame_CheckLevel" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, Rehide)
		end
	end
	for _, name in ipairs({ "TargetFrame", "FocusFrame" }) do
		local frame = _G[name]
		if frame and type(frame.CheckLevel) == "function" then
			hooksecurefunc(frame, "CheckLevel", Rehide)
		end
	end

	-- The target's and focus's cast bars while hidden (as for your own, see
	-- castBars): their fade-out as a cast ends is an alpha animation, which
	-- shows them whatever their alpha, so they're hidden as it starts, as at
	-- its end; one left over is stopped as they show again. And one finishing
	-- at alpha 0 skips that fade and stays up, empty, so it's hidden once idle.
	local fades = {}
	-- They're set to full alpha by more than SetAlpha, which ours undoes (as
	-- your own bar is: still showing, tested), so it's put back after each of
	-- their events and updates too.
	-- (event: nil as they show, when they may not have set what they cast yet.)
	local function BarEvent(bar, event)
		if not hidden[bar] then
			return
		end
		KeepHidden(bar)
		for _, group in ipairs(fades[bar]) do
			if ns.Flag(group:IsPlaying()) then
				group:Stop()
			end
		end
		if event and not (ns.Flag(bar.casting) or ns.Flag(bar.channeling) or ns.Flag(bar.reverseChanneling)
			or bar.isInEditMode) and ns.Flag(bar:IsShown()) then
			bar:Hide()
		end
	end
	local function BarFade(group)
		local bar = group:GetParent()
		if hidden[bar] and not bar.isInEditMode then
			bar:Hide()
		end
	end
	for _, name in ipairs({ "TargetFrame", "FocusFrame" }) do
		local bar = _G[name] and TARGET.CastBar(_G[name])[1]
		if bar and bar.HookScript then
			fades[bar] = {}
			bar:HookScript("OnEvent", BarEvent)
			bar:HookScript("OnShow", BarEvent)
			bar:HookScript("OnUpdate", ns.Profiled("Unit cast bar update hook", function(self)
				if hidden[self] then
					KeepHidden(self)
				end
			end))
			for _, group in ipairs(bar.GetAnimationGroups and { bar:GetAnimationGroups() } or {}) do
				local ok, fadesBar = pcall(castBars.FadesFrame, group, bar)
				if ok and fadesBar then
					group:HookScript("OnPlay", BarFade)
					table.insert(fades[bar], group)
				end
			end
		end
	end
	end)()

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_LOGIN")
	-- (Again once the world is up: the player frame's parts may not be there,
	-- or be drawn again, by then. And once after the game's own updates.)
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	watcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
	-- (A unit turning hostile, or a duel starting.)
	watcher:RegisterUnitEvent("UNIT_FACTION", "target", "focus")
	-- (The target or focus picking someone else: their target of target frames.)
	watcher:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
	-- (After a fight: the focus's target of target's mouse, if left waiting.)
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:SetScript("OnEvent", function(_, event)
		ns.ApplyUnitFrameParts()
		if event == "PLAYER_ENTERING_WORLD" then
			C_Timer.After(0, ns.ApplyUnitFrameParts)
		end
	end)
	-- Parts shown by more than Always (FRAMES.dynamic, as last applied):
	-- applied again when what their rows know changes (a fight, a place, a
	-- group...), checked 4 times a second.
	local lastFacts, since = {}, 0
	watcher:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < 0.25 or not ns.db then
			return
		end
		since = 0
		if not FRAMES.dynamic then
			return
		end
		local changed = false
		for field, value in pairs(ns.RuleFactsNow()) do
			if lastFacts[field] ~= value then
				lastFacts[field] = value
				changed = true
			end
		end
		if changed then
			ns.ApplyUnitFrameParts()
		end
	end)
end
