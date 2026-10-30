-- Profile modules: the settings under the choices and profiles in
-- ProfileChoices.lua. A module is a set of settings for the pages, or the
-- sections of pages, it names (its scope), and changes nothing outside
-- them: the CDM module is just the Cooldown Manager page and the Standard
-- Frames page's Combat and action bar sections, so the CDM choice is those
-- settings and nothing else.
--
-- A module is written one of two ways: apply = function(set) (set(key,
-- value) a setting, set(list, { row = value }) some rows of a list), or as
-- data, settings = { key = value, list = { row = value } }, which is what
-- the dev build's Module Editor (ModuleEditor.lua) makes and exports.
--
-- Where a setting is: its address, "Page/Section" by the English names the
-- options show (Options.lua records each setting's page and the header or
-- section band it's under; "Page/top" above the first). A scope entry is an
-- address, or a page's name for all of it. A list a page shows as a grid
-- (the Standard Frames columns) has an address per row: the CDM module can
-- have the In combat column's action bar rows without its unit frame rows.
--
-- Two modules of one profile never change the same setting or row, except
-- that a module of the same group replaces the one before (the Edit Mode
-- layouts). /cine debug modules checks all of this, and so does
-- Tools/offline/check.lua outside the game, on both clients.

local _, ns = ...

-- This client, as modules and profiles name it.
ns.CLIENT = ns.isRetail and "retail" or "forever"

-- Settings whose address isn't where Options.lua records them: on no page,
-- or on one that's somewhere else's.
local KEY_ADDRESSES = {
	editModeLayout = "Profiles/Edit Mode layout", -- (set by the Layout choices in Customize, on the Profiles page)
	cooldownManagerOn = "Cooldown Manager/top", -- (the game's own switch: no box of ours)
	prdOn = "Profiles/Edit Mode layout", -- (the game's own switch, with the layout centred on it)
	chatPeekChannelList = "Chat/Other",
	-- (with the rows as dropdowns, what rows without a Calm Timer of their own go by)
	combatShowCalm = "Standard Frames/top",
	-- (the effects' switches, set from their row of the Visual Effects grid)
	letterbox = "Effects/Show in", vignette = "Effects/Show in", weatherTint = "Effects/Show in",
}
-- Lists whose rows go with the same rows of the grids: a row's rule or the
-- roles it shows for is where that row is.
local ROW_RULE_LISTS = { frameRules = true, tankHide = true, healerHide = true, damageHide = true }

-- Switches cameras off: an event's camera to none, or (for the ones no
-- event starts) its row of the Cameras page's "Turn off in" grid.
local EVENT_CAMS = { flight = true, idle = true, cozy = true, tele = true, vista = true, fish = true,
	quest = true }
local function CamsOff(set, cams)
	local off = {}
	for _, cam in ipairs(cams) do off[cam] = true end
	for _, event in ipairs(ns.EVENTS or {}) do
		local cam = event.camera == "afk" and "idle" or event.camera
		if off[cam] then
			set("event" .. event.key .. "Camera", "none")
		end
	end
	for _, cam in ipairs(cams) do
		if not EVENT_CAMS[cam] then
			for _, where in ipairs(ns.CAMERA_OFF_WHERE) do
				if not (ns.CAMERA_OFF_NEVER[cam] or {})[where] then
					set(cam .. "OffIn" .. where, true)
				end
			end
		end
	end
end

-- Each event that can start music, starting it.
local MUSIC_EVENTS = { "AFK", "Still", "Chair", "Kneel", "Sleep", "Dance", "Weapon", "Campfire",
	"SitButton", "Fishing", "Hearth", "Teleport", "Logout", "Quest" }

-- A list's rows, all given value.
local function All(rows, value)
	local list = {}
	for _, row in ipairs(rows) do list[row] = value end
	return list
end

-- The Standard Frames columns' rows that are action bars (and the other
-- bars: the Cooldown Manager, micro menu, bags, XP bars, gamepad bars and
-- other addons' bars), as against the rest.
local BAR_ROWS = { cooldowns = true, cooldownsutility = true, cooldownsbuffs = true, cooldownsbars = true, micro = true, bags = true, xp = true, gamepadbars = true, gamepadxp = true,
	["addon:bt4Bars"] = true, ["addon:euiBars"] = true, ["addon:euiCooldowns"] = true,
	["addon:euiEssentials"] = true, ["addon:euiDataBars"] = true }
local function IsBarRow(item)
	return item.page == "bars" or BAR_ROWS[item.key] == true
end
-- Every row of the columns, the bars' (bars true) or the rest, given value.
local function EveryRow(bars, value)
	local list = {}
	for _, item in ipairs(ns.COMBAT_SHOW) do
		if IsBarRow(item) == bars then list[item.key] = value end
	end
	return list
end

-- The action bars as Pure Cinema and the CDM module hide them: action bars
-- 1 to 3 (and 4 to 8) with the art.
local MAIN_BARS = { "mainbar", "art", "bottomleft", "bottomright" }
local EXTRA_BARS = { "right1", "right2", "bar6", "bar7", "bar8" }
-- The micro menu, bags and XP bars (the Interface section's).
local MICRO_ROWS = { "micro", "bags", "xp" }

-- The mouseover groups as retail has them: the action bars group split into
-- action bars 1-3 (with the pet, stance, totem and extra action bars stacked
-- on them), the micro menu and bags, and the XP bars, each a group of its
-- own. (The other groups as they are.)
local function SplitBarGroups(set)
	local L = ns.L
	local function Copy(source)
		if type(source) ~= "table" then return source end
		local result = {}
		for k, v in pairs(source) do result[k] = Copy(v) end
		return result
	end
	local groups = {}
	for _, group in ipairs(ns.HOVER_GROUPS_DEFAULT) do
		if group.preset == "bars" then
			local bars = Copy(group)
			bars.name = L["Action bars 1-3"]
			bars.members = { "mainbar", "bottomleft", "bottomright", "pet", "stance", "totems" }
			groups[#groups + 1] = bars
			groups[#groups + 1] = { icon = "Interface\\Icons\\INV_Misc_Bag_07", name = L["Micro menu and bags"],
				members = { "micro", "bags" } }
			groups[#groups + 1] = { icon = "Interface\\Icons\\INV_Misc_Book_09", name = L["XP bars"],
				members = { "xp" } }
		else
			groups[#groups + 1] = Copy(group)
		end
	end
	set("hoverGroups", groups)
end

-- A layout module: Edit Mode switches to the layout called layout when the
-- profile's picked (Layouts.lua: one of Cinematic's own is made first if it
-- isn't there). No layout module: the player's own layout. ns.LAYOUT_PRESET:
-- the game's own, a preset (Layouts.lua: the one they're on, else Modern).
ns.LAYOUT_PRESET = "*preset"
local function Layout(key, name, layout, client, tip, also)
	return { key = key, name = name, client = client, group = "layout", editMode = layout,
		scope = { "Profiles/Edit Mode layout" }, tip = tip,
		apply = function(set)
			set("editModeLayout", layout)
			if also then also(set) end
		end }
end

-- Every module, in the order the Module Editor lists them. key: what
-- choices and profiles name it by. client: only on that one ("forever" or "retail";
-- skipped on the other). group: one of a group per profile (a later one
-- replaces the earlier). apply(set, client): set(key, value) writes a
-- setting, or a list's rows (just the ones given).
ns.PROFILE_MODULES = {
	-- Edit Mode layouts
	Layout("layout-preset", "Game's own layout", ns.LAYOUT_PRESET, "forever",
		"The game's own layout (Modern or Classic), which the fades and mouseover groups are made for, " ..
		"not one the player's moved things in."),
	Layout("layout-retail", "Retail Inspired layout", "Retail Inspired", "forever",
		"Action bars centred along the bottom, the micro menu and bags in the corner, the XP bars under them, " ..
		"as on retail."),
	Layout("layout-forever", "Forever-style layout", "CINE_RETAIL_FOREVER_LAYOUT", "retail",
		"Retail laid out like WoW Forever's default."),
	Layout("layout-pure", "Personal Resource Centered layout", "Personal Resource Centered", "retail",
		"The personal resource display in the middle, the Cooldown Manager above it. Turns the game's personal " ..
		"resource display on if it's off.",
		function(set) set("prdOn", true) end),

	-- What fades, and when
	{ key = "recovering", name = "Up while recovering", scope = { "Standard Frames/top", "Personal Resources" },
		tip = "In combat rows stay for the Calm Timer, and the player frame and personal resource display " ..
		"stay up until health and power are full.",
		apply = function(set)
			set("combatShowCalm", true)
			set("portraitWhenNotFull", true)
			set("prdWhenNotFull", true)
		end },
	{ key = "no-fading", name = "Nothing fades", scope = { "Cinematic/General" },
		tip = "The normal UI: nothing fades.",
		apply = function(set) set("fadeUI", false) end },
	{ key = "solo-only", name = "Solo in the world only", scope = { "Cinematic/General" },
		tip = "On only while you're out in the world on your own: off in dungeons, raids, PvP and groups.",
		apply = function(set)
			for _, where in ipairs({ "Dungeons", "Raids", "PvP", "Party", "RaidGroup" }) do
				set("offIn" .. where, true)
			end
		end },
	{ key = "minimap-off-in-fights", name = "No minimap in fights", scope = { "Standard Frames/Minimap" },
		tip = "No minimap in fights, nor its header, buttons, zone name and clock.",
		apply = function(set)
			set("combatShow", All({ "minimap", "minimapheader", "minimaptracking", "minimapcalendar", "minimapzone",
				"minimapclock" }, false))
		end },
	{ key = "fewer-group-plates", name = "Fewer group nameplates", scope = { "Nameplates/Friendly Nameplates" },
		tip = "Group members' pets, and the Grouped column for friendly players and minions, don't stay up.",
		apply = function(set)
			set("plateAlwaysGroupMinions", false)
			set("plateGroupFriends", false)
			set("plateGroupFriendlyMinions", false)
		end },

	-- Action bars
	{ key = "retail-groups", name = "Retail's mouseover groups", scope = { "Mouseover groups/top" },
		tip = "Action bars 1-3 (with the pet, stance and totem bars), the micro menu and bags, and the XP " ..
		"bars each come up on their own when you point at one.",
		apply = SplitBarGroups },
	{ key = "micro-off-in-fights", name = "No micro menu or XP bar in fights",
		scope = { "Standard Frames/Interface" },
		tip = "No micro menu, bags or XP bars in fights or with an enemy targeted.",
		apply = function(set)
			set("combatShow", All(MICRO_ROWS, false))
			set("enemyShow", All(MICRO_ROWS, false))
		end },
	{ key = "cdm", name = "Cooldown Manager in fights",
		scope = { "Cooldown Manager", "Standard Frames/Combat", "Standard Frames/Action bars" },
		tip = "The Cooldown Manager in place of action bars 1 to 8 in fights and with an enemy targeted (the " ..
		"pet, stance and totem bars still come up). After a fight it stays up until its cooldowns are ready, " ..
		"within the Calm Timer. Turns the game's Cooldown Manager on if it's off.",
		apply = function(set)
			set("cooldownManagerOn", true)
			set("cooldownWhileRecharging", true)
			set("cooldownUtilityWhileRecharging", true)
			for _, list in ipairs({ "combatShow", "enemyShow" }) do
				local rows = All(MAIN_BARS, false)
				for row in pairs(All(EXTRA_BARS, false)) do rows[row] = false end
				for _, row in ipairs({ "cooldowns", "pet", "stance", "totems" }) do rows[row] = true end
				set(list, rows)
			end
		end },

	{ key = "bars-always", name = "Action bars always up",
		scope = { "Standard Frames/Action bars" },
		tip = "Action bars 1 to 8, and the pet, stance, totem and extra action bars, shown all through CineMode.",
		apply = function(set)
			local rows = {}
			for _, item in ipairs(ns.COMBAT_SHOW) do
				if item.page == "bars" then rows[item.key] = true end
			end
			set("cineShow", rows)
		end },

	-- Pure Cinema's, page by page
	{ key = "pure-frames", name = "Pure: frames",
		scope = { "Standard Frames", "Personal Resources", "Advanced Frames/Supported addons", "Gamepad/top" },
		tip = "Fights bring up only your resource bar: no portrait, target, buffs, minimap or swing timer, " ..
		"nothing for an enemy or friend targeted, nothing in dungeons and raids, and the cast bar shows all " ..
		"through CineMode. The player frame and resource display don't stay up until full; no focus's target of target; " ..
		"raid frames without names, buffs, threat, target markers, ready checks or titles in CineMode.",
		apply = function(set)
			set("portraitWhenNotFull", false)
			set("prdWhenNotFull", false)
			set("unitPartsFocusToT", false)
			set("cineShow", { castbar = true, raidnames = false, raidbuffs = false, raidthreat = false,
				raidtarget = false, raidready = false, raidtitles = false })
			set("combatShow", { prdpower = true, player = false, petframe = false, target = false, tot = false,
				focus = false, castbar = false, prd = false, party = false, raidplayers = false, raidpets = false, minimap = false,
				buffs = false, swing = false })
			set("enemyShow", { target = false, tot = false, player = false, prd = false, prdpower = false,
				party = false, raidplayers = false, raidpets = false, focus = false, buffs = false })
			set("friendlyShow", { target = false, tot = false })
			-- (Nor in dungeons, scenarios and raids, where the Instances column
			-- starts with the party and raid frames ticked. The bars: pure-cdm's.)
			set("instanceShow", EveryRow(false, false))
		end },
	{ key = "pure-cdm", name = "Pure: Cooldown Manager only",
		scope = { "Cooldown Manager", "Standard Frames/Combat", "Standard Frames/Action bars",
			"Standard Frames/Interface", "Advanced Frames/Supported addons",
			"Gamepad/top" },
		tip = "No action bars, micro menu, bags or XP bar in fights, with an enemy targeted or in instances; " ..
		"the Cooldown Manager in fights, and up whenever a cooldown is recharging, out of fights too.",
		apply = function(set)
			set("cooldownManagerOn", true)
			set("cooldownWhileRecharging", true)
			set("cooldownAfterCombat", false)
			set("cooldownUtilityWhileRecharging", true)
			set("cooldownUtilityAfterCombat", false)
			local fights = All({ "mainbar", "art", "bottomleft", "bottomright", "pet", "stance", "totems", "micro",
				"bags", "xp" }, false)
			local combat = {}
			for row, value in pairs(fights) do combat[row] = value end
			combat.cooldowns = true
			set("combatShow", combat)
			set("enemyShow", fights)
			set("instanceShow", EveryRow(true, false))
		end },
	{ key = "pure-plates", name = "Pure: nameplates", scope = { "Nameplates", "Nameplate Style" },
		tip = "Enemies' nameplates (and their minions') in fights, not kept up otherwise; in PvP and " ..
		"battlegrounds, none; in instances, friendly players' and NPCs' hidden; no group members' or friendly " ..
		"targets'; an arrow over your target's plate all through CineMode " ..
		"(the marks themselves: ultra-plates).",
		apply = function(set)
			for _, key in ipairs({ "plateAlwaysGroupMembers", "plateAlwaysGroupMinions", "plateGroupFriends",
				"plateGroupFriendlyMinions", "plateAlwaysYourTarget", "plateCinematicEnemies", "plateInCitiesEnemies", "plateCombatPvPEnemies", "plateCombatPvPEnemyMinions", "plateCombatPvPFriends",
				"plateInBGsEnemies", "plateInBGsFriends", "plateInPvPEnemies", "plateAlwaysPartClassEnemy",
				"plateAlwaysPartRoleHealer", "plateAlwaysPartRoleTank" }) do
				set(key, false)
			end
			set("plateCombatEnemies", true)
			set("plateCombatEnemyMinions", true)
			-- (Your target's plate kept up unless it's friendly.)
			set("frameRules", { ["plate:YourTarget"] = "enemyplayer or hostilenpc or neutralplayer or neutralnpc" })
			-- An arrow over your target's plate all through CineMode, with no
			-- target frame to show what you've targeted.
			for _, prefix in ipairs({ "plateCinematic", "plateCombat", "plateInPvP", "plateInBGs", "plateInInstances" }) do
				set(prefix .. "PartTargetArrow", true)
			end
			set("plateInstanceFriends", "hide")
			set("plateInstanceFriendlyNPCs", "hide")
		end },
	{ key = "ultra-plates", name = "Ultra responsive nameplates", scope = { "Nameplate Style" },
		tip = "In fights the plates say what matters at a glance: the further a unit, the fainter its plate " ..
		"(past 40, 28 and within 11 yards), normal NPCs faint and narrower while an elite's within 40 yards, an enemy after " ..
		"someone else tinted orange, and marks on your target and the unit under the mouse. No aggro mark, and " ..
		"plates change quicker.",
		apply = function(set)
			set("markOrder", "target,mouseover,focus,allPast40,allPast28,allIn11,npc,aggroother,aggro")
			set("markNames", { allPast40 = "Fade 40", allPast28 = "Fade 28", allIn11 = "Fade 11",
				npc = "Fade non elite", aggroother = "Aggro not on you" })
			set("plateStyleFadeTime", 0.6)
			-- Your target's arrow and the mouseover's mark in fights too, a little lower.
			set("targetWhenCombat", true)
			set("targetArrowY", -10)
			set("mouseoverWhen", false)
			set("mouseoverWhenCombat", true)
			-- Aggro on you: no mark.
			set("aggroMarkStyle", "none")
			-- Every unit by distance, in fights: no mark, just fainter.
			for id, alpha in pairs({ allPast40 = 0.5, allPast28 = 0.8, allIn11 = 0.95 }) do
				set(id .. "MarkShow", true)
				set(id .. "MarkStyle", "none")
				set(id .. "MarkAlpha", alpha)
				set(id .. "When", false)
				for _, word in ipairs({ "Combat", "Enemy", "Friendly" }) do set(id .. "When" .. word, true) end
			end
			set("allPast40MarkColor", "custom")
			-- Normal NPCs faint while an elite's within 40 yards, in fights.
			set("npcMarkAlpha", 0.5)
			set("npcMarkPlateWidth", 0.7) -- and their bars narrower
			set("npcWhen", false)
			set("npcWhenCombat", true)
			set("frameRules", { npcWhen = "combat and elite40" })
			-- An enemy after someone else: its health bar orange, no mark.
			set("aggrootherMarkStyle", "none")
			set("aggrootherMarkBob", false)
			set("aggrootherMarkColor", "reaction")
			set("aggrootherMarkG", 1)
			set("aggrootherMarkB", 1)
			set("aggrootherColorBar", true)
			set("aggrootherMarkPlateColor", "custom")
			set("aggrootherMarkPlateG", 0.54)
			set("aggrootherMarkPlateB", 0)
		end },
	{ key = "minimal-target", name = "Minimal target frame",
		scope = { "Unit Frames/Target", "Standard Frames/Unit frames", "Quest Vision/top" },
		tip = "The target frame stays through CineMode with nothing in it until a fight, then just its health, " ..
		"buffs and debuffs and cast bar: the nameplates show the rest. No quest icon on it.",
		apply = function(set)
			for _, part in ipairs({ "Art", "Auras", "CastBar", "Health", "Icons", "Level", "Name", "Numbers",
				"Portrait", "Power", "PvP", "Threat" }) do
				set("unitPartTarget" .. part, false)
			end
			set("combatShow", { unitPartTargetHealth = true, unitPartTargetAuras = true, unitPartTargetCastBar = true })
			set("cineShow", { target = true })
			set("targetQuestIcon", false)
		end },
	{ key = "quest-talk", name = "Quest talk", scope = { "Quest Vision/Talking to NPCs" },
		tip = "Custom dialogue frames: speech bubbles and a reply list instead of the game's gossip and " ..
		"quest windows.",
		apply = function(set)
			set("questTalk", true)
		end },
	{ key = "combat-vision", name = "Combat Vision", scope = { "Combat Vision" },
		tip = "Combat Vision on: a cue on the screen and sounds as you go into a fight and come out of it.",
		apply = function(set)
			set("combatVision", true)
		end },
	{ key = "no-visions", name = "No visions", scope = { "Heal Vision", "Quest Vision", "Vision", "Roll Vision",
		"Vitals Vision", "Combat Vision" },
		tip = "Every vision off: Heal, Quest, Duel, Roll, Vitals and Combat Vision.",
		apply = function(set)
			set("handleHealVision", false)
			set("questVision", false)
			set("duelPlates", false)
			set("rollWindow", false)
			set("lowHealth", false)
			set("combatVision", false)
		end },
	{ key = "pure-tooltips", name = "Pure: tooltips", scope = { "Tooltips" },
		tip = "The Tooltips page on: shown all through CineMode, fights too; no Mouse still.",
		apply = function(set)
			set("handleTooltips", true)
			set("tooltipHideCombatElse", false) -- (Always, as it goes over: ns.ConvertOffGrids)
			set("tooltipStillMode", "off")
			set("tooltipShowStill", 1)
		end },
	{ key = "heal-vision-everywhere", name = "Heal Vision everywhere", scope = { "Heal Vision" },
		tip = "Heal Vision in dungeons and raids too, and as a tank or damage dealer.",
		apply = function(set)
			set("healVisionInDungeons", true)
			set("healVisionInRaids", true)
			set("tankHide", { healVision = false })
			set("damageHide", { healVision = false })
		end },

	-- Cameras
	{ key = "walk-run-music", name = "Music on walks and runs", scope = { "Cameras/Triggers" },
		tip = "Auto-walking and auto-running can start music.",
		apply = function(set)
			set("musicCamWalk", true)
			set("musicCamRun", true)
		end },
	{ key = "lite-cameras", name = "Just a few cameras", scope = { "Cameras/Triggers" },
		tip = "Just flights (and fly-bys), AFK, and your Hearthstone and teleports: no cozy, vista, fish, " ..
		"RP walk, auto-run, death or quest cameras.",
		apply = function(set)
			CamsOff(set, { "cozy", "vista", "fish", "walk", "run", "death", "quest" })
		end },
	{ key = "no-cameras", name = "No cameras", scope = { "Cameras" },
		tip = "No camera moves on its own.",
		apply = function(set)
			CamsOff(set, { "flight", "idle", "cozy", "tele", "vista", "fish", "walk", "run", "death", "quest" })
		end },
	{ key = "cameras-bring-cinemode", name = "Cameras bring CineMode", scope = { "Cameras/Triggers",
		"Camera Settings/Death Cam" },
		tip = "Every camera brings CineMode on, standing still starts the AFK camera, every camera can start " ..
		"music, and no death screen.",
		apply = function(set)
			for _, event in ipairs(ns.EVENTS or {}) do
				if ns.DEFAULTS["event" .. event.key .. "Cine"] ~= nil then
					set("event" .. event.key .. "Cine", true)
				end
			end
			set("walkCine", true)
			set("runCine", true)
			set("deathCine", true)
			set("deathScreen", false)
			set("deathBannerStyle", "none")
			set("eventStillCamera", "afk")
			for _, event in ipairs(MUSIC_EVENTS) do set("event" .. event .. "Music", true) end
			set("musicCamWalk", true)
			set("musicCamRun", true)
		end },
	{ key = "pure-cameras", name = "Pure: cameras", scope = { "Cameras/Triggers", "Camera Settings/Chat Cam",
		"General/top" },
		tip = "Standing still starts the AFK camera and every event's camera can start music; the cameras " ..
		"don't wait for things to calm down after a fight, auto-run carries on in cities and instances (as RP " ..
		"walk always does), and the death camera runs in instances too. NPCs talking bring the chat camera, " ..
		"those chatting nearby straight away, and it doesn't look round for speakers off screen. The zoom " ..
		"resets on login and /reload.",
		apply = function(set)
			-- (Chat Cam: off to start with, on here.)
			if ns.DEFAULTS.chatCamSearch ~= nil then
				set("chatCamera", "chat")
				set("chatNearbyCamera", "chat")
				set("chatNearbyDelay", 0)
				set("chatCamSearch", false)
			end
			set("eventStillCamera", "afk")
			for _, event in ipairs(MUSIC_EVENTS) do set("event" .. event .. "Music", true) end
			for _, cam in ipairs({ "walk", "run", "tele", "quest" }) do
				set(cam .. "CalmWait", false)
			end
			set("runOffInCities", false)
			set("runOffInInstances", false)
			set("deathOffInInstances", false)
			set("loginZoom", true) -- (Quality of life > General)
		end },

	-- The look
	{ key = "no-letterbox", name = "No letterbox", scope = { "Effects/Show in" },
		tip = "No letterbox: the other effects show over the normal UI.",
		apply = function(set) set("letterbox", false) end },
	{ key = "effects-in-cameras", name = "Effects only in cameras", scope = { "Effects/Show in" },
		tip = "The letterbox, tint, vignette and weather only while a camera mode runs; no soft edges.",
		apply = function(set)
			for _, effect in ipairs(ns.EFFECT_GRID) do
				set(effect .. "OnlyInCameras", true)
			end
			set("depthOfField", false)
		end },
	{ key = "letterbox-in-fights", name = "Letterbox stays in fights", scope = { "Effects/Show in" },
		tip = "Fights don't bring the letterbox down.",
		apply = function(set) set("letterboxOffInCombat", false) end },
	{ key = "rain-view-distance", name = "Reduce View Distance in Rain", scope = { "Effects/Show in" },
		tip = "In CineMode, rain pulls the view distance in from yours, all the way in a downpour.",
		apply = function(set) set("rainViewScale", 1) end },
	{ key = "no-time-message", name = "No time of day message", scope = { "Tint/Time of day" },
		tip = "No time of day title under the zone name.",
		apply = function(set) set("timeOfDayMessage", false) end },
	{ key = "vitals-vision", name = "Vitals Vision on", scope = { "Vitals Vision" },
		tip = "Your health at the screen's edges, the picture drained toward grey and the personal resource " ..
		"display fading in as it drops.",
		apply = function(set)
			set("lowHealth", true)
			set("lowHealthPrd", true)
		end },

	-- Sound and chat
	{ key = "music-fatigue", name = "Music fatigue", scope = { "Audio/Fatigue" },
		tip = "No camera starts music again within half a minute of the last start.",
		apply = function(set) set("musicFatigue", 0.5) end },
	{ key = "no-cinemode-music", name = "No music in CineMode", scope = { "Audio/top" },
		tip = "No music in CineMode.",
		apply = function(set) set("musicInCinematic", false) end },
	{ key = "no-npc-chat", name = "No NPC chatter", scope = { "Chat/Other" },
		tip = "Chat doesn't peek for NPC speech (guards, vendors, ambient chatter).",
		apply = function(set) set("chatPeekTypes", { npc = false }) end },
	{ key = "lite-channels", name = "General and Trade chat", scope = { "Chat/Other" },
		tip = "Chat shows for General and Trade (others joined later stay off; LocalDefense attacks show " ..
		"on the screen instead).",
		apply = function(set)
			set("chatPeekChannelList", { General = true, Trade = true, LocalDefense = false, Services = false,
				TradeLocal = false })
		end },
	{ key = "pure-chat", name = "Pure: chat", scope = { "Chat/Other", "Chat bubbles/top", "Chat bubbles/Behind you" },
		tip = "Chat doesn't peek for General or LocalDefense, and speech from behind you shows low on the screen " ..
		"(the Chat bubbles page on, which it needs).",
		apply = function(set)
			set("chatPeekChannelList", { General = false, LocalDefense = false })
			set("handleBubbles", true)
			set("chatSpeechBehind", true)
		end },
}
local function CopyValue(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = CopyValue(v) end
	return copy
end

-- A module written as data (settings = { key = value, list = { row = value } }:
-- what the Module Editor exports) is applied as one: its lists by row
-- (hoverGroups whole), in the settings' new form, after the old grids'
-- settings have gone over (ns.ApplyModules).
local function DataModule(module)
	module.data = true
	module.apply = function(set)
		for key, value in pairs(module.settings) do set(key, CopyValue(value)) end
	end
	return module
end
local moduleByKey = {}
for _, module in ipairs(ns.PROFILE_MODULES) do
	if module.settings and not module.apply then DataModule(module) end
	moduleByKey[module.key] = module
end
ns.PROFILE_MODULE_BY_KEY = moduleByKey

-- The dev build's Module Editor changes (db.devEdits: modules[key] = a data
-- module, in place of the code's or new; choices[slot][part] = { modules };
-- profiles[name] = { picks, modules }), or nil. They take effect on a
-- profile when it's picked or reset.
function ns.DevEdits()
	return ns.isDev and ns.db and ns.db.devEdits or nil
end

-- A module by its key: the Editor's version of it, else the code's.
local editedModules = setmetatable({}, { __mode = "k" })
function ns.GetModule(key)
	local edits = ns.DevEdits()
	local edited = edits and edits.modules and edits.modules[key]
	if edited then
		-- (Made into a module once per saved table.)
		if not editedModules[edited] then
			local module = CopyValue(edited)
			module.key, module.edited = key, true
			module.scope = module.scope or {}
			editedModules[edited] = DataModule(module)
		end
		return editedModules[edited]
	end
	return moduleByKey[key]
end

-- Every module's key: the code's in order, then the Editor's new ones.
function ns.ModuleKeys()
	local keys, seen = {}, {}
	for _, module in ipairs(ns.PROFILE_MODULES) do
		keys[#keys + 1] = module.key
		seen[module.key] = true
	end
	local edits = ns.DevEdits()
	local extra = {}
	for key in pairs(edits and edits.modules or {}) do
		if not seen[key] then extra[#extra + 1] = key end
	end
	table.sort(extra)
	for _, key in ipairs(extra) do keys[#keys + 1] = key end
	return keys
end

-- A slot's choice by its part (with the Editor's modules for it), or nil.
function ns.GetChoice(slot, part)
	local info = ns.SLOT_CHOICES and ns.SLOT_CHOICES[slot]
	for _, choice in ipairs(info and info.choices or {}) do
		if choice.part == part then
			local edits = ns.DevEdits()
			local edited = edits and edits.choices and edits.choices[slot] and edits.choices[slot][part]
			if edited then
				local copy = {}
				for k, v in pairs(choice) do copy[k] = v end
				copy.modules, copy.edited = edited.modules, true
				return copy
			end
			return choice
		end
	end
end

-- Whether a choice is hidden on a client (hidden: true, or that client's name).
function ns.ChoiceHidden(choice, client)
	return choice.hidden == true or choice.hidden == client
end

-- A slot's choices players are offered on this client (not hidden), or nil
-- with fewer than two.
function ns.SlotChoices(slot)
	local list = {}
	local info = ns.SLOT_CHOICES and ns.SLOT_CHOICES[slot]
	for _, choice in ipairs(info and info.choices or {}) do
		if not ns.ChoiceHidden(choice, ns.CLIENT) and (not choice.client or choice.client == ns.CLIENT) then
			list[#list + 1] = ns.GetChoice(slot, choice.part)
		end
	end
	return #list > 1 and list or nil
end

-- A list of module entries (keys, { forever =, retail = }, "-key" taking an
-- earlier one out) added to list on a client: the other client's left out,
-- a later module of a group in place of the earlier. Each entry: key,
-- module (or missing), and what's in info (where it came from).
local function AddModules(list, entries, client, info)
	for _, entry in ipairs(entries or {}) do
		local key = type(entry) == "table" and entry[client] or entry
		if type(key) == "string" and key:sub(1, 1) == "-" then
			for i = #list, 1, -1 do
				if list[i].key == key:sub(2) then table.remove(list, i) end
			end
		elseif key then
			local module = ns.GetModule(key)
			if type(entry) == "string" and not module then
				local missing = { key = key, missing = true }
				for k, v in pairs(info) do missing[k] = v end
				list[#list + 1] = missing
			elseif module and not (module.client and module.client ~= client) then
				if module.group then
					for i = #list, 1, -1 do
						if list[i].module and list[i].module.group == module.group then table.remove(list, i) end
					end
				end
				local added = { key = key, module = module }
				for k, v in pairs(info) do added[k] = v end
				list[#list + 1] = added
			end
		end
	end
	return list
end

-- A choice's modules on a client, resolved (nil: no such choice).
function ns.ChoiceModules(slot, part, client)
	local choice = ns.GetChoice(slot, part)
	if not choice then return nil end
	return AddModules({}, choice.modules, client or ns.CLIENT, { slot = slot, part = part })
end

-- A profile's pick for each slot on a client, and which profile picked it:
-- its own, else the one it's from, else the slot's default ("default").
-- editOf(name): the Editor's { picks, modules } for a profile, in place of its own.
local function Picks(profile, client, byName, editOf)
	local picks, by = {}, {}
	local function Walk(p, depth)
		if depth > 10 then return end -- (a loop of froms)
		if p.from and byName[p.from] then Walk(byName[p.from], depth + 1) end
		local own = editOf and editOf(p.name) or p
		for slot, pick in pairs(own.picks or {}) do
			if type(pick) == "table" then pick = pick[client] end
			if pick then picks[slot], by[slot] = pick, p.name end
		end
	end
	Walk(profile, 0)
	return picks, by
end
ns.ProfilePicks = Picks

-- A built-in profile's modules on a client, in order: each slot's choice
-- (its picks), then the modules of its own (and of those it's from). Each
-- entry: key, module (or missing), slot and part (the choice it's from, if
-- any) and from (the profile that picked it or added it; "default": the
-- slot's default). A choice that isn't there: an entry with missing and
-- part. editOf: as for the picks.
function ns.ResolveModules(profile, client, byName, editOf)
	local list = {}
	local picks, by = Picks(profile, client, byName or {}, editOf)
	for _, slot in ipairs(ns.PROFILE_SLOTS or {}) do
		local info = ns.SLOT_CHOICES[slot.key]
		local part = picks[slot.key] or (info and info.default)
		if part then
			local choice = ns.GetChoice(slot.key, part)
			if choice then
				AddModules(list, choice.modules, client, { slot = slot.key, part = part, from = by[slot.key] or "default" })
			else
				list[#list + 1] = { key = slot.key .. ":" .. part, slot = slot.key, part = part, missing = true,
					from = by[slot.key] }
			end
		end
	end
	local function Extras(p, depth)
		if depth > 10 then return end
		if p.from and byName and byName[p.from] then Extras(byName[p.from], depth + 1) end
		local own = editOf and editOf(p.name) or p
		AddModules(list, own.modules, client, { from = p.name })
	end
	Extras(profile, 0)
	return list
end

-- The modules' settings on top of base, in order (resolved: ns.ResolveModules).
-- A list's rows from two modules go together. onSet(key, row, value, module):
-- each write, for the checks. Modules in code still set the old grids'
-- settings (Turn off in and the like): they go over as they're applied
-- (ns.ConvertOffGrids, Core.lua), unless keepOld; data modules (the
-- Editor's) go on after, in the new form.
function ns.ApplyModules(resolved, base, client, onSet, keepOld)
	local written = {}
	local function Pass(data)
		for _, entry in ipairs(resolved) do
			local module = entry.module
			if module and (module.data or false) == data then
				module.apply(function(key, value)
					if type(value) == "table" and key ~= "hoverGroups" then
						if not written[key] then
							-- (Data modules keep what's there, the old grids' rows gone over.)
							local old = base[key]
							base[key] = {}
							if data and type(old) == "table" then
								for row, rowValue in pairs(old) do base[key][row] = rowValue end
							end
							written[key] = true
						end
						for row, rowValue in pairs(value) do
							base[key][row] = rowValue
							if onSet then onSet(key, row, rowValue, module) end
						end
					else
						base[key] = value
						if onSet then onSet(key, nil, value, module) end
					end
				end, client)
			end
		end
	end
	Pass(false)
	if not keepOld and ns.ConvertOffGrids then
		ns.ConvertOffGrids(base, ns.OldGridDefault, { all = true })
	end
	Pass(true)
	return base
end

-- A value as text, the same for the same value (keys sorted), to compare.
local function Serial(value)
	if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
	local keys = {}
	for k in pairs(value) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) < type(b) end
		return a < b
	end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Serial(value[k]) end
	return "{" .. table.concat(parts, ",") .. "}"
end
ns.SerialValue = Serial

-- What modules change once applied (the old grids' settings gone over to
-- the new): each setting, or list row, that differs from the defaults
-- applied the same way, as { key, row (or nil), value }. hoverGroups as a whole.
-- before: ns.ModuleBase(client), when working out many (it's the same each time).
function ns.ModuleEffect(resolved, client, before)
	local function Defaults()
		local values = {}
		for k, v in pairs(ns.DEFAULTS) do values[k] = v end
		return values
	end
	before = before or ns.ApplyModules({}, Defaults(), client)
	local after = ns.ApplyModules(resolved, Defaults(), client)
	local keys, out = {}, {}
	for k in pairs(before) do keys[k] = true end
	for k in pairs(after) do keys[k] = true end
	for key in pairs(keys) do
		local a, b = before[key], after[key]
		-- (Most aren't touched: the same value, or the same table, both sides.)
		if a == b then
		elseif ns.IS_PROFILE_TABLE[key] and key ~= "hoverGroups" and (type(a) == "table" or type(b) == "table") then
			a, b = type(a) == "table" and a or {}, type(b) == "table" and b or {}
			local rows = {}
			for row in pairs(a) do rows[row] = true end
			for row in pairs(b) do rows[row] = true end
			for row in pairs(rows) do
				if Serial(a[row]) ~= Serial(b[row]) then out[#out + 1] = { key, row, b[row] } end
			end
		elseif Serial(a) ~= Serial(b) then
			out[#out + 1] = { key, nil, b }
		end
	end
	table.sort(out, function(x, y)
		return x[1] .. "." .. tostring(x[2]) < y[1] .. "." .. tostring(y[2])
	end)
	return out
end

-- The defaults with no modules applied (the old grids' settings gone over),
-- as ns.ModuleEffect compares against. Not to be changed.
function ns.ModuleBase(client)
	local values = {}
	for k, v in pairs(ns.DEFAULTS) do values[k] = v end
	return ns.ApplyModules({}, values, client)
end

-- The slot whose choices change a setting (or a list's row), on this
-- client; nil: none of them do. (Picking a choice puts just these back as
-- it has them: ns.ApplyPart.)
local slotOf
function ns.ForgetSlotSettings() slotOf = nil end
function ns.SettingSlot(key, row)
	if not slotOf then
		slotOf = { keys = {}, rows = {} }
		local before = ns.ModuleBase(ns.CLIENT)
		for _, slot in ipairs(ns.PROFILE_SLOTS) do
			for _, choice in ipairs(ns.SLOT_CHOICES[slot.key] and ns.SLOT_CHOICES[slot.key].choices or {}) do
				local modules = ns.ChoiceModules(slot.key, choice.part, ns.CLIENT)
				for _, change in ipairs(ns.ModuleEffect(modules, ns.CLIENT, before)) do
					if change[2] == nil then
						slotOf.keys[change[1]] = slotOf.keys[change[1]] or slot.key
					else
						slotOf.rows[change[1]] = slotOf.rows[change[1]] or {}
						slotOf.rows[change[1]][change[2]] = slotOf.rows[change[1]][change[2]] or slot.key
					end
				end
			end
		end
	end
	if row ~= nil and slotOf.rows[key] and slotOf.rows[key][row] then return slotOf.rows[key][row] end
	return slotOf.keys[key]
end

-- Where each setting is, made once the options pages are: keys[key] and
-- rows[list][row] = { "Page/Section"... } (English; most have one, a setting
-- on two pages two), and each page's addresses with settings in them, in
-- the page's order (sections[page] = { "Page/Section"... }).
local map
local function BuildMap()
	-- (Pages and headers are registered as shown: back to English.)
	local english = {}
	for en, shown in pairs(ns.LANGUAGES and ns.LANGUAGES[ns.locale] or {}) do
		if type(shown) == "string" then english[shown] = en end
	end
	local function En(text) return english[text] or text end
	local keys, rows = {}, {}
	local function Add(list, address)
		for _, each in ipairs(list) do
			if each == address then return end
		end
		list[#list + 1] = address
		table.sort(list)
	end
	local pages = ns.PageSettings and ns.PageSettings() or {}
	for shownPage, settings in pairs(pages) do
		local page = En(shownPage)
		local function Address(section) return page .. "/" .. (section and En(section) or "top") end
		for key, section in pairs(settings.keys) do
			if not settings.rows[key] then
				keys[key] = keys[key] or {}
				Add(keys[key], Address(section))
			end
		end
		for key, list in pairs(settings.rows) do
			rows[key] = rows[key] or {}
			for row, section in pairs(list) do
				rows[key][row] = rows[key][row] or {}
				Add(rows[key][row], Address(section))
			end
		end
	end
	local used = {}
	for key, address in pairs(KEY_ADDRESSES) do keys[key] = { address } end
	for _, list in pairs(keys) do
		for _, address in ipairs(list) do used[address] = true end
	end
	for _, list in pairs(rows) do
		for _, addresses in pairs(list) do
			for _, address in ipairs(addresses) do used[address] = true end
		end
	end
	-- Each page's addresses in its order: the top, its sections, then any
	-- only KEY_ADDRESSES names.
	local sections = {}
	for shownPage, settings in pairs(pages) do
		local page = En(shownPage)
		local list = {}
		local taken = {}
		local function Take(address)
			if used[address] and not taken[address] then
				taken[address] = true
				list[#list + 1] = address
			end
		end
		Take(page .. "/top")
		for _, section in ipairs(settings.sections or {}) do Take(page .. "/" .. En(section)) end
		for address in pairs(used) do
			if address:sub(1, #page + 1) == page .. "/" then Take(address) end
		end
		sections[page] = list
	end
	-- (Each row's addresses in any list, for the rules and roles.)
	local anyRow = {}
	for key, list in pairs(rows) do
		if not ROW_RULE_LISTS[key] then
			for row, addresses in pairs(list) do
				anyRow[row] = anyRow[row] or {}
				for _, address in ipairs(addresses) do Add(anyRow[row], address) end
			end
		end
	end
	map = { keys = keys, rows = rows, sections = sections, anyRow = anyRow }
	return map
end

-- A setting of a Nameplate Style row, or a row's rule (frameRules' <id>When):
-- the page shows only the rows in markOrder, so one added (Normal NPC, Any
-- unit past 40 yards) is where the Marks grid is, shown or not.
local function IsMarkRowSetting(key)
	if type(key) ~= "string" then return false end
	local id = key:match("^(%l[%a%d]-)Mark%u") or key:match("^(%l[%a%d]-)Color%u") or key:match("^(%l[%a%d]-)When")
	return id ~= nil and ns.MarkRowValid(id)
end

-- A setting's addresses, or a list row's ({ "Page/Section"... }); nil: on no page.
function ns.SettingAddresses(key, row)
	map = map or BuildMap()
	if (key == "frameRules" and IsMarkRowSetting(row)) or (row == nil and not map.keys[key] and IsMarkRowSetting(key)) then
		return map.keys.markOrder
	end
	if row ~= nil and ROW_RULE_LISTS[key] and map.anyRow[row] then
		local list = {}
		for _, address in ipairs(map.anyRow[row]) do list[#list + 1] = address end
		for _, address in ipairs(map.rows[key] and map.rows[key][row] or {}) do list[#list + 1] = address end
		return list
	end
	if row ~= nil and map.rows[key] and map.rows[key][row] then return map.rows[key][row] end
	return map.keys[key]
end

-- Its first address (for showing it).
function ns.SettingAddress(key, row)
	local list = ns.SettingAddresses(key, row)
	return list and list[1]
end

-- Every page's addresses, in its order (for the Module Editor and the checks).
function ns.PageSections()
	map = map or BuildMap()
	return map.sections
end

-- An address is in a scope: one of its addresses, or on one of its pages.
function ns.InScope(scope, address)
	if not address then return false end
	for _, entry in ipairs(scope) do
		if entry == address or (not entry:find("/") and address:sub(1, #entry + 1) == entry .. "/") then
			return true
		end
	end
	return false
end

-- A setting with any of its addresses in a scope.
local function AnyInScope(scope, addresses)
	for _, address in ipairs(addresses or {}) do
		if ns.InScope(scope, address) then return true end
	end
	return false
end

-- The checks: each module writing only inside its scope, no two of a
-- profile's modules setting the same thing, each choice's and built-in's
-- modules (and each built-in's picks) there, and no setting changed by the
-- choices of two slots. Problems as lines; also how many settings each
-- module changes (counts[key]), the scope entries not on this client's
-- options (absent[key] = { entry... }), the settings it changes that are on
-- no page here (nowhere[key] = { setting... }): a page or a row can be the
-- other client's only, so Tools/offline/check.lua makes those problems only
-- when they're on neither. And notes: things worth a look that aren't wrong
-- (two choices of a slot the same).
function ns.CheckModules(client, profiles)
	map = BuildMap()
	local problems, counts, absent, nowhere, notes = {}, {}, {}, {}, {}
	local function Problem(text) problems[#problems + 1] = text end
	local effects = {}
	local function Effect(module)
		effects[module] = effects[module] or ns.ModuleEffect({ { module = module } }, client)
		return effects[module]
	end
	local function Where(change) return change[1] .. (change[2] ~= nil and "." .. tostring(change[2]) or "") end
	local known = {}
	for _, list in pairs(map.sections) do
		for _, address in ipairs(list) do known[address] = true end
	end
	local pages = {}
	for page in pairs(map.sections) do pages[page] = true end
	for _, key in ipairs(ns.ModuleKeys()) do
		local module = ns.GetModule(key)
		if not module.client or module.client == client then
			for _, entry in ipairs(module.scope) do
				if not (known[entry] or pages[entry]) then
					absent[key] = absent[key] or {}
					table.insert(absent[key], entry)
				end
			end
			-- (Each setting it sets, the old grids' too.)
			ns.ApplyModules({ { module = module } }, {}, client, function(setting)
				if ns.DEFAULTS[setting] == nil and not ns.IS_PROFILE_TABLE[setting] and ns.MarkRowDefault(setting) == nil
					and not (ns.OldGridDefault and ns.OldGridDefault(setting) ~= nil) then
					Problem(("module %s: %s isn't a setting"):format(key, setting))
				end
			end, true)
			-- (What it changes, the old grids' gone over to the new.)
			local changes, said = Effect(module), {}
			for _, change in ipairs(changes) do
				local addresses = ns.SettingAddresses(change[1], change[2])
				if not addresses then
					nowhere[key] = nowhere[key] or {}
					table.insert(nowhere[key], Where(change))
				elseif not AnyInScope(module.scope, addresses) and not said[addresses[1]] then
					said[addresses[1]] = true
					Problem(("module %s: %s is in %s, outside its scope"):format(key, Where(change),
						table.concat(addresses, " and ")))
				end
			end
			counts[key] = #changes
		end
	end
	local byName = {}
	for _, profile in ipairs(profiles) do byName[profile.name] = profile end
	local edits = ns.DevEdits()
	local function EditOf(name) return edits and edits.profiles and edits.profiles[name] end
	for _, profile in ipairs(profiles) do
		if not profile.client or profile.client == client then
			if profile.from and not byName[profile.from] then
				Problem(("%s: from %s, which isn't a built-in profile"):format(profile.name, profile.from))
			end
			local own = EditOf(profile.name) or profile
			for slot in pairs(own.picks or {}) do
				if not ns.SLOT_CHOICES[slot] then Problem(("%s: picks for %s, which isn't a slot"):format(profile.name, slot)) end
			end
			local resolved = ns.ResolveModules(profile, client, byName, EditOf)
			local who = {}
			for _, entry in ipairs(resolved) do
				if entry.missing then
					Problem(entry.part and not entry.module and entry.key == entry.slot .. ":" .. entry.part
						and ("%s: %s has no choice %s"):format(profile.name, entry.slot, entry.part)
						or ("%s: no module called %s"):format(profile.name, entry.key))
				elseif entry.module.editMode and entry.module.editMode ~= ns.LAYOUT_PRESET and ns.EDIT_MODE_LAYOUTS
					and not ns.EDIT_MODE_LAYOUTS[entry.module.editMode] then
					Problem(("%s: layout %s isn't one of Cinematic's (Layouts.lua)"):format(profile.name,
						entry.module.editMode))
				else
					for _, change in ipairs(Effect(entry.module)) do
						local where = Where(change)
						if who[where] and who[where] ~= entry.key then
							Problem(("%s: %s and %s both set %s"):format(profile.name, who[where], entry.key, where))
						end
						who[where] = entry.key
					end
				end
			end
		end
	end
	-- The slots' choices: their modules there, no setting changed by the
	-- choices of two slots, and (a note) two choices that come out the same.
	local slotWho = {}
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		local info = ns.SLOT_CHOICES[slot.key]
		if not info then
			Problem(("slot %s has no choices (ns.SLOT_CHOICES)"):format(slot.key))
		else
			if info.default and not ns.GetChoice(slot.key, info.default) then
				Problem(("slot %s: its default, %s, isn't one of its choices"):format(slot.key, info.default))
			end
			local seen = {}
			for _, choice in ipairs(info.choices) do
				if not choice.client or choice.client == client then
					local modules = ns.ChoiceModules(slot.key, choice.part, client)
					local all = {}
					for _, entry in ipairs(modules) do
						if entry.missing then
							Problem(("choice %s.%s: no module called %s"):format(slot.key, choice.part, entry.key))
						else
							for _, change in ipairs(Effect(entry.module)) do
								local where = Where(change)
								all[#all + 1] = where .. "=" .. Serial(change[3])
								if slotWho[where] and slotWho[where] ~= slot.key then
									Problem(("%s is changed by choices of two slots, %s and %s"):format(where,
										slotWho[where], slot.key))
								end
								slotWho[where] = slot.key
							end
						end
					end
					table.sort(all)
					local same = table.concat(all, ";")
					if seen[same] and not ns.ChoiceHidden(choice, client) and not ns.ChoiceHidden(seen[same], client) then
						notes[#notes + 1] = ("choices %s.%s and %s.%s change the same settings"):format(slot.key,
							seen[same].part, slot.key, choice.part)
					end
					seen[same] = seen[same] or choice
				end
			end
		end
	end
	return problems, counts, absent, nowhere, notes
end

-- /cine debug modules: the checks on this client, details in the log.
function ns.ModulesDebug()
	local problems, counts, _, _, notes = ns.CheckModules(ns.CLIENT, ns.ALL_BUILTIN_PROFILES)
	for _, key in ipairs(ns.ModuleKeys()) do
		if counts[key] then
			ns.Log("modules", ("%s: %d settings in %s"):format(key, counts[key],
				table.concat(ns.GetModule(key).scope, ", ")))
		end
	end
	for _, line in ipairs(problems) do ns.Log("modules", line) end
	for _, line in ipairs(notes) do ns.Log("modules", "note: " .. line) end
	ns.Print(("modules: %d problems, %d notes (details in /cine log)"):format(#problems, #notes))
end
