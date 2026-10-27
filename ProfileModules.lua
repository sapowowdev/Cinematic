-- Profile modules: the pieces the built-in profiles (Profiles.lua) are made
-- of. A module is a set of settings for the pages, or the sections of pages,
-- it names (its scope), and changes nothing outside them: the CDM module is
-- just the Standard Frames page's action bar sections and the Cooldown
-- Manager page, so a profile with the Cooldown Manager is another profile
-- plus that module, not a whole Standard Frames setup of its own.
--
-- Where a setting is: its address, "Page/Section" by the English names the
-- options show (Options.lua records each setting's page and the header or
-- section band it's under; "Page/top" above the first). A scope entry is an
-- address, or a page's name for all of it. A list a page shows as a grid
-- (the Standard Frames columns) has an address per row: the CDM module can
-- have the In combat column's action bar rows without its unit frame rows.
--
-- A built-in profile's modules go on top of the defaults in its order, each
-- writing only its own settings: two modules of one profile never write the
-- same setting or row, except that a module of the same group replaces the
-- one before (the Edit Mode layout: a profile's own replacing the one it
-- started from). /cine debug modules checks all of this, and so does
-- Tools/offline/check.lua outside the game, on both clients.

local _, ns = ...

-- This client, as modules and profiles name it.
ns.CLIENT = ns.isRetail and "retail" or "forever"

-- Settings whose address isn't where Options.lua records them: on no page,
-- or on one that's somewhere else's.
local KEY_ADDRESSES = {
	editModeLayout = "Profiles/Edit Mode layout", -- (its dropdown sits under the profiles)
	cooldownManagerOn = "Cooldown Manager/top", -- (the game's own switch: no box of ours)
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
-- event starts) its row of the Camera Modes page's "Turn off in" grid.
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
local BAR_ROWS = { cooldowns = true, cooldownsutility = true, micro = true, bags = true, xp = true, gamepadbars = true, gamepadxp = true,
	["addon:bt4Bars"] = true, ["addon:euiBars"] = true, ["addon:euiCooldowns"] = true,
	["addon:euiEssentials"] = true, ["addon:euiDataBars"] = true }
local function IsBarRow(item)
	return item.page == "bars" or item.page == "extrabars" or BAR_ROWS[item.key] == true
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
local function Layout(key, name, layout, client, tip)
	return { key = key, name = name, client = client, group = "layout", editMode = layout,
		scope = { "Profiles/Edit Mode layout" }, tip = tip,
		apply = function(set) set("editModeLayout", layout) end }
end

-- Every module, in the order the Profile Builder lists them. key: what
-- profiles name it by. client: only on that one ("forever" or "retail";
-- skipped on the other). group: one of a group per profile (a later one
-- replaces the earlier). apply(set, client): set(key, value) writes a
-- setting, or a list's rows (just the ones given).
ns.PROFILE_MODULES = {
	-- Edit Mode layouts
	Layout("layout-preset", "Game's own layout", ns.LAYOUT_PRESET, "forever",
		"The game's own layout (Modern or Classic), which the fades and mouseover groups are made for, " ..
		"not one the player's moved things in."),
	Layout("layout-retail", "Retail-style layout", "CINE_FOREVER_RETAIL_LAYOUT", "forever",
		"Action bars centred along the bottom, the micro menu and bags in the corner, the XP bars under them, " ..
		"as on retail."),
	Layout("layout-forever", "Forever-style layout", "CINE_RETAIL_FOREVER_LAYOUT", "retail",
		"Retail laid out like WoW Forever's default."),
	Layout("layout-pure", "Pure Cinema layout", "CINE_PURE_CINEMA_LAYOUT", "retail",
		"The personal resource display in the middle, the Cooldown Manager above it."),

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
		scope = { "Cooldown Manager", "Standard Frames/Combat", "Standard Frames/Action bars",
			"Standard Frames/Extra action bars" },
		tip = "The Cooldown Manager in place of action bars 1 to 8 in fights and with an enemy targeted (the " ..
		"pet, stance and totem bars still come up). After a fight it stays up until its cooldowns are ready, " ..
		"within the Calm Timer. Turns the game's Cooldown Manager on if it's off.",
		apply = function(set)
			set("cooldownManagerOn", true)
			set("cooldownWhileRecharging", true)
			for _, list in ipairs({ "combatShow", "enemyShow" }) do
				local rows = All(MAIN_BARS, false)
				for row in pairs(All(EXTRA_BARS, false)) do rows[row] = false end
				for _, row in ipairs({ "cooldowns", "pet", "stance", "totems" }) do rows[row] = true end
				set(list, rows)
			end
		end },

	-- Pure Cinema's, page by page
	{ key = "pure-frames", name = "Pure: frames",
		scope = { "Standard Frames", "Personal Resources", "Advanced Frames/Supported addons", "Gamepad/top" },
		tip = "Fights bring up only your resource bar: no portrait, target, buffs, minimap or swing timer, " ..
		"nothing for an enemy or friend targeted, nothing in dungeons and raids, and the cast bar shows all " ..
		"through CineMode. The player frame and resource display don't stay up until full; no focus's target of target.",
		apply = function(set)
			set("portraitWhenNotFull", false)
			set("prdWhenNotFull", false)
			set("unitPartsFocusToT", false)
			set("cineShow", { castbar = true })
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
			"Standard Frames/Extra action bars", "Standard Frames/Interface", "Advanced Frames/Supported addons",
			"Gamepad/top" },
		tip = "No action bars, micro menu, bags or XP bar in fights, with an enemy targeted or in instances; " ..
		"the Cooldown Manager in fights, not just after them, and up after a fight until its cooldowns are ready.",
		apply = function(set)
			set("cooldownManagerOn", true)
			set("cooldownWhileRecharging", true)
			set("cooldownAfterCombat", false)
			local fights = All({ "mainbar", "art", "bottomleft", "bottomright", "pet", "stance", "totems", "micro",
				"bags", "xp" }, false)
			local combat = {}
			for row, value in pairs(fights) do combat[row] = value end
			combat.cooldowns = true
			set("combatShow", combat)
			set("enemyShow", fights)
			set("instanceShow", EveryRow(true, false))
		end },
	{ key = "pure-plates", name = "Pure: nameplates", scope = { "Nameplates" },
		tip = "Enemies' nameplates (and their minions') in fights, not kept up otherwise; in PvP and " ..
		"battlegrounds, none; in instances, friendly players' and NPCs' hidden; no group members' or friendly " ..
		"targets'; an arrow over your target's plate all through CineMode.",
		apply = function(set)
			for _, key in ipairs({ "plateAlwaysGroupMembers", "plateAlwaysGroupMinions", "plateGroupFriends",
				"plateGroupFriendlyMinions", "plateAlwaysMyFriendlyNPCTarget", "plateAlwaysMyFriendlyPlayerTarget",
				"plateCinematicEnemies", "plateInCitiesEnemies", "plateCombatPvPEnemies", "plateCombatPvPEnemyMinions", "plateCombatPvPFriends",
				"plateInBGsEnemies", "plateInBGsFriends", "plateInPvPEnemies", "plateAlwaysPartClassEnemy",
				"plateAlwaysPartRoleHealer", "plateAlwaysPartRoleTank" }) do
				set(key, false)
			end
			set("plateCombatEnemies", true)
			set("plateCombatEnemyMinions", true)
			-- An arrow over your target's plate all through CineMode, with no
			-- target frame to show what you've targeted.
			for _, prefix in ipairs({ "plateCinematic", "plateCombat", "plateInPvP", "plateInBGs", "plateInInstances" }) do
				set(prefix .. "PartTargetArrow", true)
			end
			set("plateInstanceFriends", "hide")
			set("plateInstanceFriendlyNPCs", "hide")
		end },
	{ key = "pure-tooltips", name = "Pure: tooltips", scope = { "Tooltips" },
		tip = "The Tooltips page on: hidden in RP walk and the quest camera, friendlies' shown, nothing hidden " ..
		"just for a fight; the border on first hover, no health bar later; no Mouse still.",
		apply = function(set)
			set("handleTooltips", true)
			set("tooltipHideFriendly", false)
			for _, kind in ipairs({ "Friendly", "Gather", "Quest", "Else" }) do
				set("tooltipHideCombat" .. kind, false)
			end
			set("tooltipHideInWalk", true)
			set("tooltipHideInQuest", true)
			set("tooltipShowBorderFirst", true)
			set("tooltipShowHealthLater", false)
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
	{ key = "walk-run-music", name = "Music on walks and runs", scope = { "Camera Triggers/Event" },
		tip = "Auto-walking and auto-running can start music.",
		apply = function(set)
			set("musicCamWalk", true)
			set("musicCamRun", true)
		end },
	{ key = "lite-cameras", name = "Just a few cameras", scope = { "Camera Triggers/Event", "Camera Modes/Runs in" },
		tip = "Just flights (and fly-bys), AFK, and your Hearthstone and teleports: no cozy, vista, fish, " ..
		"RP walk, auto-run, death or quest cameras.",
		apply = function(set)
			CamsOff(set, { "cozy", "vista", "fish", "walk", "run", "death", "quest" })
		end },
	{ key = "no-cameras", name = "No cameras", scope = { "Camera Triggers/Event", "Camera Modes" },
		tip = "No camera moves on its own.",
		apply = function(set)
			CamsOff(set, { "flight", "idle", "cozy", "tele", "vista", "fish", "walk", "run", "death", "quest" })
		end },
	{ key = "cameras-bring-cinemode", name = "Cameras bring CineMode", scope = { "Camera Triggers/Event",
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
			set("deathBanner", false)
			set("eventStillCamera", "afk")
			for _, event in ipairs(MUSIC_EVENTS) do set("event" .. event .. "Music", true) end
			set("musicCamWalk", true)
			set("musicCamRun", true)
		end },
	{ key = "pure-cameras", name = "Pure: cameras", scope = { "Camera Triggers/Event", "Camera Modes/Runs in" },
		tip = "Standing still starts the AFK camera and every event's camera can start music; the cameras " ..
		"don't wait for things to calm down after a fight, auto-run carries on in cities and instances (as RP " ..
		"walk always does), and the death camera runs in instances too.",
		apply = function(set)
			set("eventStillCamera", "afk")
			for _, event in ipairs(MUSIC_EVENTS) do set("event" .. event .. "Music", true) end
			for _, cam in ipairs({ "walk", "run", "tele", "quest" }) do
				set(cam .. "CalmWait", false)
			end
			set("runOffInCities", false)
			set("runOffInInstances", false)
			set("deathOffInInstances", false)
		end },

	-- The look
	{ key = "no-letterbox", name = "No letterbox", scope = { "Effects/Show in" },
		tip = "No letterbox: the other effects show over the normal UI.",
		apply = function(set) set("letterbox", false) end },
	{ key = "effects-in-cameras", name = "Effects only in cameras", scope = { "Effects/Show in",
		"Effects/Depth of field" },
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
	{ key = "no-time-message", name = "No time of day message", scope = { "Tint/Time of day" },
		tip = "No time of day title under the zone name.",
		apply = function(set) set("timeOfDayMessage", false) end },
	{ key = "vitals-vision", name = "Vitals Vision on", scope = { "Vitals Vision" },
		tip = "Your health at the screen's edges, and the personal resource display fading in as it drops.",
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
	{ key = "pure-chat", name = "Pure: chat", scope = { "Chat/Other", "Chat/top" },
		tip = "Chat doesn't peek for General or LocalDefense, and speech from behind you shows low on the screen.",
		apply = function(set)
			set("chatPeekChannelList", { General = false, LocalDefense = false })
			set("chatSpeechBehind", true)
		end },
}
local moduleByKey = {}
for _, module in ipairs(ns.PROFILE_MODULES) do moduleByKey[module.key] = module end
ns.PROFILE_MODULE_BY_KEY = moduleByKey

-- A built-in profile's modules on a client, in order: the ones of the
-- profile it's from (its from, by name), then its own (each a key, or
-- { forever = key, retail = key }; "-key" takes one it's from out), the
-- other client's left out and a later module of a group in place of the
-- earlier. modules: in place of the profile's own (the Profile Builder's
-- changes). Also each one's key and where it came from (the profile's name).
function ns.ResolveModules(profile, client, byName, modules)
	local list = {}
	local function Add(entry, from)
		local key = type(entry) == "table" and entry[client] or entry
		if type(key) == "string" and key:sub(1, 1) == "-" then
			for i = #list, 1, -1 do
				if list[i].key == key:sub(2) then table.remove(list, i) end
			end
			return
		end
		local module = key and moduleByKey[key]
		if type(entry) == "string" and not module then
			list[#list + 1] = { key = key, from = from, missing = true }
			return
		end
		if not module or (module.client and module.client ~= client) then return end
		if module.group then
			for i = #list, 1, -1 do
				if list[i].module and list[i].module.group == module.group then table.remove(list, i) end
			end
		end
		list[#list + 1] = { key = key, module = module, from = from }
	end
	local parent = profile.from and byName[profile.from]
	if parent then
		for _, entry in ipairs(ns.ResolveModules(parent, client, byName)) do
			if entry.module then Add(entry.key, entry.from) else list[#list + 1] = entry end
		end
	end
	for _, entry in ipairs(modules or profile.modules or {}) do Add(entry, profile.name) end
	return list
end

-- The modules' settings on top of base, in order (resolved: ns.ResolveModules).
-- A list's rows from two modules go together. onSet(key, row, value, module):
-- each write, for the checks. Modules still set the old grids' settings
-- (Turn off in and the like): they go over as they're applied
-- (ns.ConvertOffGrids, Core.lua), unless keepOld.
function ns.ApplyModules(resolved, base, client, onSet, keepOld)
	local written = {}
	for _, entry in ipairs(resolved) do
		if entry.module then
			entry.module.apply(function(key, value)
				if type(value) == "table" and key ~= "hoverGroups" then
					if not written[key] then
						base[key] = {}
						written[key] = true
					end
					for row, rowValue in pairs(value) do
						base[key][row] = rowValue
						if onSet then onSet(key, row, rowValue, entry.module) end
					end
				else
					base[key] = value
					if onSet then onSet(key, nil, value, entry.module) end
				end
			end, client)
		end
	end
	if not keepOld and ns.ConvertOffGrids then
		ns.ConvertOffGrids(base, ns.OldGridDefault, { all = true })
	end
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

-- What modules change once applied (the old grids' settings gone over to
-- the new): each setting, or list row, that differs from the defaults
-- applied the same way, as { key, row (or nil), value }. hoverGroups as a whole.
function ns.ModuleEffect(resolved, client)
	local function Defaults()
		local values = {}
		for k, v in pairs(ns.DEFAULTS) do values[k] = v end
		return values
	end
	local before = ns.ApplyModules({}, Defaults(), client)
	local after = ns.ApplyModules(resolved, Defaults(), client)
	local keys, out = {}, {}
	for k in pairs(before) do keys[k] = true end
	for k in pairs(after) do keys[k] = true end
	for key in pairs(keys) do
		local a, b = before[key], after[key]
		if ns.IS_PROFILE_TABLE[key] and key ~= "hoverGroups" and (type(a) == "table" or type(b) == "table") then
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
	return out
end

-- Slots and parts: the choices the welcome window's Customise pages and
-- the Profiles demo offer (ns.SLOT_CHOICES, WelcomeDemo.lua), a part per
-- slot, each part some modules. A slot's settings are the ones any of its
-- parts change (ns.SettingSlot), so picking a part (ns.ApplyPart) puts those
-- as it has them and leaves every other setting as it is.
ns.PROFILE_SLOTS = {
	{ key = "layout", name = "Edit Mode layout" },
	{ key = "frames", name = "UI manager" },
	{ key = "bars", name = "Action bars" },
	{ key = "camera", name = "Camera" },
	{ key = "vfx", name = "Visual effects" },
	{ key = "misc", name = "Chat & misc" },
}
-- Each slot's parts: their modules ({ forever =, retail = } for one that
-- differs by client). "standard": a slot's part for a profile that names none.
local SLOT_PARTS = {
	layout = {
		retail = { "layout-retail" }, forever = { "layout-forever" }, pure = { "layout-pure" },
		preset = { "layout-preset" },
	},
	frames = {
		standard = { "recovering" },
		immersive = { "recovering", "minimap-off-in-fights", "fewer-group-plates" },
		nofade = { "recovering", "no-fading" },
		solo = { "recovering", "solo-only" },
		pure = { "pure-frames", "pure-plates", "pure-tooltips", "heal-vision-everywhere" },
	},
	bars = {
		standard = { { retail = "retail-groups" } },
		grouped = {},
		split = { "retail-groups", "micro-off-in-fights" },
		cdm = { { retail = "retail-groups" }, "cdm", "micro-off-in-fights" },
		pure = { { retail = "retail-groups" }, "pure-cdm" },
	},
	camera = {
		immersive = { "walk-run-music" }, lite = { "lite-cameras" }, off = { "no-cameras" },
		cinemode = { "cameras-bring-cinemode" }, pure = { "pure-cameras" },
	},
	vfx = {
		noletterbox = { "no-letterbox" }, cameras = { "effects-in-cameras" },
		pure = { "letterbox-in-fights", "no-time-message", "vitals-vision" },
	},
	misc = {
		quietnpcs = { "no-npc-chat" }, immersive = { "music-fatigue", "no-npc-chat" },
		lite = { "lite-channels", "no-npc-chat" }, nomusic = { "no-cinemode-music" },
		pure = { "pure-chat", "no-npc-chat" },
	},
}
ns.SLOT_PARTS = SLOT_PARTS
-- A part's modules on a client, resolved.
local function PartModules(list, client)
	return ns.ResolveModules({ modules = list }, client, {})
end
-- ns.PROFILE_PARTS[slot][name] = { modules =, client =, editMode =, apply(set, client) }.
ns.PROFILE_PARTS = {}
for slot, parts in pairs(SLOT_PARTS) do
	ns.PROFILE_PARTS[slot] = {}
	for name, list in pairs(parts) do
		local part = { modules = list }
		-- (Just one client's when all its modules are: the layouts.)
		local only = moduleByKey[type(list[1]) == "string" and list[1] or ""]
		if #list == 1 and only and only.client then
			part.client, part.editMode = only.client, only.editMode
		end
		part.apply = function(set, client)
			for _, entry in ipairs(PartModules(list, client)) do entry.module.apply(set, client) end
		end
		ns.PROFILE_PARTS[slot][name] = part
	end
end

-- The parts named ({ slot = part name }, a slot not named: its standard),
-- in slot order, on top of base.
function ns.ApplyParts(parts, base, client, keepOld)
	local list = {}
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		local part = ns.PROFILE_PARTS[slot.key][parts[slot.key] or "standard"]
		if part then
			for _, entry in ipairs(PartModules(part.modules, client)) do list[#list + 1] = entry end
		end
	end
	return ns.ApplyModules(list, base, client, nil, keepOld)
end

-- The slot whose parts change a setting (or a list's row), on this client;
-- nil: none of them do.
local slotOf
function ns.SettingSlot(key, row)
	if not slotOf then
		slotOf = { keys = {}, rows = {} }
		for _, slot in ipairs(ns.PROFILE_SLOTS) do
			for _, part in pairs(ns.PROFILE_PARTS[slot.key]) do
				for _, change in ipairs(ns.ModuleEffect(PartModules(part.modules, ns.CLIENT), ns.CLIENT)) do
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

-- A setting's addresses, or a list row's ({ "Page/Section"... }); nil: on no page.
function ns.SettingAddresses(key, row)
	map = map or BuildMap()
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

-- Every page's addresses, in its order (for the Profile Builder and the checks).
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
-- profile's modules writing the same setting, and each built-in's modules
-- there. Problems as lines; also how many settings each module writes
-- (counts[key]), the scope entries not on this client's options (absent[key]
-- = { entry... }) and the settings it writes that are on no page here
-- (nowhere[key] = { setting... }): a page or a row can be the other
-- client's only, so Tools/offline/check.lua makes those problems only when
-- they're on neither.
function ns.CheckModules(client, profiles)
	map = BuildMap()
	local effects = {}
	local function Effect(module)
		effects[module] = effects[module] or ns.ModuleEffect({ { module = module } }, client)
		return effects[module]
	end
	local problems, counts, absent, nowhere = {}, {}, {}, {}
	local function Problem(text) problems[#problems + 1] = text end
	local known = {}
	for _, list in pairs(map.sections) do
		for _, address in ipairs(list) do known[address] = true end
	end
	local pages = {}
	for page in pairs(map.sections) do pages[page] = true end
	for _, module in ipairs(ns.PROFILE_MODULES) do
		if not module.client or module.client == client then
			for _, entry in ipairs(module.scope) do
				if not (known[entry] or pages[entry]) then
					absent[module.key] = absent[module.key] or {}
					table.insert(absent[module.key], entry)
				end
			end
			-- (Each setting it sets, the old grids' too.)
			ns.ApplyModules({ { module = module } }, {}, client, function(key)
				if ns.DEFAULTS[key] == nil and not ns.IS_PROFILE_TABLE[key]
					and not (ns.OldGridDefault and ns.OldGridDefault(key) ~= nil) then
					Problem(("module %s: %s isn't a setting"):format(module.key, key))
				end
			end, true)
			-- (What it changes, the old grids' gone over to the new.)
			local changes, said = Effect(module), {}
			for _, change in ipairs(changes) do
				local key, row = change[1], change[2]
				local addresses = ns.SettingAddresses(key, row)
				local where = key .. (row ~= nil and "." .. tostring(row) or "")
				if not addresses then
					nowhere[module.key] = nowhere[module.key] or {}
					table.insert(nowhere[module.key], where)
				elseif not AnyInScope(module.scope, addresses) and not said[addresses[1]] then
					said[addresses[1]] = true
					Problem(("module %s: %s is in %s, outside its scope"):format(module.key, where,
						table.concat(addresses, " and ")))
				end
			end
			counts[module.key] = #changes
		end
	end
	local byName = {}
	for _, profile in ipairs(profiles) do byName[profile.name] = profile end
	for _, profile in ipairs(profiles) do
		if not profile.client or profile.client == client then
			if profile.from and not byName[profile.from] then
				Problem(("%s: from %s, which isn't a built-in profile"):format(profile.name, profile.from))
			end
			local resolved = ns.ResolveModules(profile, client, byName)
			local who = {}
			for _, entry in ipairs(resolved) do
				if entry.missing then
					Problem(("%s: no module called %s"):format(profile.name, entry.key))
				elseif entry.module.editMode and entry.module.editMode ~= ns.LAYOUT_PRESET and ns.EDIT_MODE_LAYOUTS
					and not ns.EDIT_MODE_LAYOUTS[entry.module.editMode] then
					Problem(("%s: layout %s isn't one of Cinematic's (Layouts.lua)"):format(profile.name,
						entry.module.editMode))
				end
			end
			for _, entry in ipairs(resolved) do
				if entry.module then
					for _, change in ipairs(Effect(entry.module)) do
						local where = change[1] .. (change[2] ~= nil and "." .. tostring(change[2]) or "")
						if who[where] and who[where] ~= entry.key then
							Problem(("%s: %s and %s both set %s"):format(profile.name, who[where], entry.key, where))
						end
						who[where] = entry.key
					end
				end
			end
		end
	end
	-- The slots' parts: their modules there, and no setting changed by the
	-- parts of two slots.
	local slotWho = {}
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		for name, part in pairs(ns.PROFILE_PARTS[slot.key]) do
			for _, entry in ipairs(ns.ResolveModules({ modules = part.modules }, client, {})) do
				if entry.missing then
					Problem(("part %s.%s: no module called %s"):format(slot.key, name, entry.key))
				else
					for _, change in ipairs(Effect(entry.module)) do
						local where = change[1] .. (change[2] ~= nil and "." .. tostring(change[2]) or "")
						if slotWho[where] and slotWho[where] ~= slot.key then
							Problem(("%s is changed by parts of two slots, %s and %s"):format(where, slotWho[where],
								slot.key))
						end
						slotWho[where] = slot.key
					end
				end
			end
		end
	end
	return problems, counts, absent, nowhere
end

-- /cine debug modules: the checks on this client, details in the log.
function ns.ModulesDebug()
	local problems, counts = ns.CheckModules(ns.CLIENT, ns.ALL_BUILTIN_PROFILES)
	for _, module in ipairs(ns.PROFILE_MODULES) do
		if counts[module.key] then
			ns.Log("modules", ("%s: %d settings in %s"):format(module.key, counts[module.key],
				table.concat(module.scope, ", ")))
		end
	end
	for _, line in ipairs(problems) do ns.Log("modules", line) end
	ns.Print(("modules: %d problems (details in /cine log)"):format(#problems))
end
