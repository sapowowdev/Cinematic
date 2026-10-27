-- Profile choices: what players pick, and what each pick is made of. The
-- one file to change to shape the experience; the settings themselves are
-- in modules (ProfileModules.lua), and the welcome window, the Profiles
-- page and the dev build's Module Editor all read from here.
--
-- Three layers, each built from the one below:
--   Modules (ProfileModules.lua): a set of settings for the pages, or
--     sections of pages, it names.
--   Choices (ns.SLOT_CHOICES, here): each slot (an area of your setup:
--     the interface, action bars, camera...) has a few choices, and a
--     choice is a list of modules. Picking one swaps the slot's settings
--     for the choice's and leaves the rest as they are (ns.ApplyPart).
--   Profiles (ns.BUILTIN_PROFILES, here): a pick per slot (picks), on top
--     of the profile it's from (from), plus any modules of its own
--     (modules). A slot it doesn't pick has its default choice.
-- The welcome window's levels (ns.WELCOME_LEVELS, here) each pick a profile.
--
-- To change what a choice does, change its modules. To add one, add it to
-- its slot's choices (with hidden = true it's only for profiles, not offered
-- to players). To add a slot, add it to ns.PROFILE_SLOTS and ns.SLOT_CHOICES.
-- The dev build's Module Editor does all of this in the game and gives the
-- Lua to paste back here. lua5.1 Tools/offline/check.lua (and /cine debug
-- modules) checks that it all fits together.

local _, ns = ...
local L = ns.L

-- The slots, in the order a profile's choices go on (a later one's
-- modules after the earlier's).
ns.PROFILE_SLOTS = {
	{ key = "layout", name = "Edit Mode layout" },
	{ key = "frames", name = "UI manager" },
	{ key = "bars", name = "Action bars" },
	{ key = "camera", name = "Camera" },
	{ key = "vfx", name = "Visual effects" },
	{ key = "misc", name = "Chat & misc" },
}

-- Each slot as players see it: its name (label), the options page with its
-- settings, a question, its default (the choice a profile that picks none
-- has), and its choices. A choice: part (its key, what profiles pick it
-- by), label and line (what players read), icon, client (only there),
-- hidden (only for profiles, not offered), and modules (each a module's key,
-- or { forever = key, retail = key }).
ns.SLOT_CHOICES = {
	layout = { label = "Layout", page = "Profiles", question = "Where should your bars and menus sit?",
		default = "own", choices = {
		{ part = "preset", client = "forever", label = "WoW Forever's", line = "The game's own layout",
			modules = { "layout-preset" } },
		{ part = "retail", client = "forever", label = "Like retail",
			line = "Action bars centered along the bottom, menus in the corner", modules = { "layout-retail" } },
		{ part = "forever", client = "retail", hidden = true, label = "Like WoW Forever",
			line = "Laid out like WoW Forever's default", modules = { "layout-forever" } },
		{ part = "pure", client = "retail", hidden = true, label = "Pure Cinema's",
			line = "The resource display in the middle, the Cooldown Manager above it", modules = { "layout-pure" } },
		{ part = "own", hidden = true, label = "Your own", line = "Cinematic leaves your Edit Mode layout as it is",
			modules = {} },
	} },
	frames = { label = "Interface", page = "Standard Frames", question = "When does your UI fade?",
		default = "standard", choices = {
		{ part = "immersive", label = "Between fights", line = "Fights and opening windows bring it back",
			modules = { "recovering", "minimap-off-in-fights", "fewer-group-plates" } },
		-- (The same settings as Between fights since the CDM part's own frames
		-- turned out no different: give it modules of its own, or drop it.)
		{ part = "cdm", label = "Frames in fights", line = "Between fights; your frames and buffs show in fights",
			modules = { "recovering", "minimap-off-in-fights", "fewer-group-plates" } },
		{ part = "solo", label = "Only when solo", line = "Out in the world on your own; normal in groups",
			modules = { "recovering", "solo-only" } },
		{ part = "pure", label = "Almost always", line = "As little UI as possible, even in fights",
			modules = { "pure-frames", "pure-plates", "pure-tooltips", "heal-vision-everywhere" } },
		{ part = "nofade", label = "Never", line = "Your UI stays as the game has it",
			modules = { "recovering", "no-fading" } },
		{ part = "standard", hidden = true, label = "Fades", line = "The UI fades, as the defaults have it",
			modules = { "recovering" } },
	} },
	bars = { label = "Action bars", page = "Mouseover groups", question = "How do your action bars come back?",
		default = "standard", choices = {
		{ part = "grouped", label = "All together", line = "Point at one and the bars, menus and XP bar come up",
			modules = {} },
		{ part = "split", label = "Each on its own", line = "Point at the bars, the menus or the XP bar",
			modules = { "retail-groups", "micro-off-in-fights" } },
		{ part = "cdm", label = "Cooldown Manager", line = "The Cooldown Manager shows in fights instead",
			modules = { { retail = "retail-groups" }, "cdm", "micro-off-in-fights" } },
		{ part = "pure", label = "Not in fights", line = "No bars in fights or with an enemy targeted",
			modules = { { retail = "retail-groups" }, "pure-cdm" } },
		-- (The client's own: retail's bars each on their own, Forever's together.)
		{ part = "standard", hidden = true, label = "As this client has them",
			line = "Retail's bars each on their own, WoW Forever's together", modules = { { retail = "retail-groups" } } },
	} },
	camera = { label = "Camera", page = "Camera Modes", question = "When does the camera move on its own?",
		default = "standard", choices = {
		{ part = "immersive", label = "Often", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
			line = "Flights, campfires, vistas, fishing, quests, going AFK and more", modules = { "walk-run-music" } },
		{ part = "lite", label = "Sometimes", icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
			line = "Flights, going AFK, and your Hearthstone and teleports", modules = { "lite-cameras" } },
		{ part = "off", label = "Never", icon = "Interface\\Icons\\Spell_Nature_Sleep",
			line = "The camera is all yours", modules = { "no-cameras" } },
		{ part = "cinemode", hidden = true, label = "Cameras bring CineMode",
			line = "Every camera brings CineMode on, and can start music", modules = { "cameras-bring-cinemode" } },
		{ part = "pure", hidden = true, label = "Pure Cinema's",
			line = "Standing still starts the AFK camera, and the cameras don't wait after a fight",
			modules = { "pure-cameras" } },
		{ part = "standard", hidden = true, label = "Every camera", line = "Every camera, as the defaults have them",
			modules = {} },
	} },
	vfx = { label = "Look", page = "Effects", question = "How should the world look?", default = "standard", choices = {
		{ part = "standard", label = "Letterbox and tint", line = "Bars top and bottom, a color tint, vignette and weather",
			modules = {} },
		{ part = "noletterbox", label = "Tint only", line = "The tint, vignette and weather, no letterbox",
			modules = { "no-letterbox" } },
		{ part = "cameras", label = "During cameras", line = "The effects only while a camera mode runs",
			modules = { "effects-in-cameras" } },
		{ part = "pure", label = "Through fights", line = "Fights don't bring the letterbox down",
			modules = { "letterbox-in-fights", "no-time-message", "vitals-vision" } },
	} },
	misc = { label = "Sound and chat", page = "Audio", question = "How much music and chatter?", default = "standard",
		choices = {
		{ part = "standard", label = "As the game has it", line = "Music on cameras, NPC chat as usual", modules = {} },
		{ part = "immersive", label = "Quieter", line = "Less NPC chatter, music spaced out",
			modules = { "music-fatigue", "no-npc-chat" } },
		{ part = "lite", label = "Quieter chat", line = "Less NPC chatter, chat only for General and Trade",
			modules = { "lite-channels", "no-npc-chat" } },
		{ part = "nomusic", label = "No music", line = "No music in CineMode", modules = { "no-cinemode-music" } },
		{ part = "quietnpcs", hidden = true, label = "No NPC chatter", line = "Chat doesn't peek for NPC speech",
			modules = { "no-npc-chat" } },
		{ part = "pure", hidden = true, label = "Pure Cinema's",
			line = "No General or LocalDefense chat, speech from behind you low on the screen",
			modules = { "pure-chat", "no-npc-chat" } },
	} },
}

-- The built-in profiles, in the order they're listed. picks: the choice
-- per slot (a choice's part, or { forever = part, retail = part } where it
-- differs by client; a slot not picked: the one it's from picks, else the
-- slot's default). from: the built-in it starts from. modules: any of its
-- own on top ("-key" takes one of the choices' out). client: only on that
-- one ("forever" or "retail"). label: the name shown, when it isn't the
-- saved name (two clients' profiles can't share a name in this list).
-- oldNames: what it was called before: settings and picks saved under
-- those move to it at login. dev: only in the dev build (one being made).
-- hidden: in no list, the dev build's too (only the Module Editor shows it).
-- preview: the mouseover group (its preset) shown for a moment when it's
-- picked on the Profiles page, the rest faded (ns.PreviewProfile).
ns.BUILTIN_PROFILES = {
	-- Forever's own three: its default, with the Cooldown Manager, and on a
	-- layout like retail's.
	{
		name = "Forever Default",
		label = "Default",
		client = "forever",
		oldNames = { "Immersive", "Cinematic Strong" }, -- (Cinematic Strong: test builds)
		icon = "Interface\\Icons\\Spell_Holy_MindVision",
		tip = L["Everything on: the UI fades, the letterbox and tint, and every camera mode, with the action " ..
			"bars, micro menu, bags and XP bar coming up together when you point at one. WoW Forever's default, " ..
			"and how the developer plays every day."],
		picks = { layout = "preset", frames = "immersive", camera = "immersive", misc = "immersive" },
		preview = "bars",
	},
	{
		name = "Forever CDM",
		label = "CDM",
		client = "forever",
		oldNames = { "Immersive (CDM)" },
		icon = "Interface\\Icons\\Spell_Shadow_AntiShadow", -- (Preparation)
		tip = L["Default, with the Cooldown Manager in place of action bars 1 to 3, the micro menu and the " ..
			"XP bar in fights and with an enemy targeted. After a fight it stays up until its cooldowns are ready."],
		from = "Forever Default",
		picks = { frames = "cdm", bars = "cdm" },
		preview = "cooldowns",
	},
	{
		name = "Forever Retail",
		label = "Retail",
		client = "forever",
		icon = "Interface\\Icons\\INV_Misc_Wrench_01",
		tip = L["Default, looking like retail: Cinematic's own Edit Mode layout (the action bars centered along " ..
			"the bottom, the micro menu and bags in the corner, the XP bar under them), with action bars 1 to 3, " ..
			"the micro menu and bags, and the XP bar each coming up on its own when you point at it. Picking it " ..
			"adds the layout to Edit Mode if you haven't got it; the other profiles go back to the game's own layout " ..
			"(Classic if you were on it, otherwise Modern)."],
		from = "Forever Default",
		picks = { layout = "retail", bars = "split" },
		preview = "bars",
	},
	-- Retail's own three, the same way round.
	{
		name = "Retail Default",
		label = "Default",
		client = "retail",
		oldNames = { "Immersive" },
		icon = "Interface\\Icons\\Spell_Holy_PowerInfusion",
		tip = L["Everything on: the UI fades, the letterbox and tint, and every camera mode, with your main " ..
			"action bars, the micro menu and bags, and the XP bar each coming up on its own when you point at it. " ..
			"Retail's default."],
		picks = { frames = "immersive", bars = "split", camera = "immersive", misc = "immersive" },
		preview = "bars",
	},
	{
		name = "Retail CDM",
		label = "CDM",
		client = "retail",
		oldNames = { "Immersive (CDM)" },
		icon = "Interface\\Icons\\Ability_Rogue_Preparation",
		tip = L["Default, with the Cooldown Manager in place of action bars 1 to 3, the micro menu and the " ..
			"XP bar in fights and with an enemy targeted. After a fight it stays up until its cooldowns are ready."],
		from = "Retail Default",
		picks = { frames = "cdm", bars = "cdm" },
		preview = "cooldowns",
	},
	{
		-- (hidden until its layout's designed: Layouts.lua)
		name = "Retail Forever",
		label = "Forever",
		client = "retail",
		hidden = true,
		icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
		tip = "Default, looking like WoW Forever: its layout (CINE_RETAIL_FOREVER_LAYOUT, not designed yet: " ..
			"a copy of Modern), with the action bars, micro menu, bags and XP bar coming up together.",
		picks = { layout = "forever", frames = "immersive", bars = "grouped", camera = "immersive", misc = "immersive" },
		preview = "bars",
	},
	-- Both clients'.
	{
		name = "Pure Cinema",
		icon = "Interface\\Icons\\Ability_Stealth",
		tip = L["As little UI as possible: nameplates show only for enemies in fights, and fights don't bring " ..
			"the letterbox down. Fights bring up only your resource bar and the Cooldown Manager, the cast bar " ..
			"shows all through CineMode, your health shows at the screen's edges and " ..
			"your personal resource display fades in as it drops (Vitals Vision), and every " ..
			"camera can start music."],
		picks = { layout = { forever = "preset", retail = "pure" }, frames = "pure", bars = "pure", camera = "pure",
			vfx = "pure", misc = "pure" },
	},
	{
		name = "Lite",
		icon = "Interface\\Icons\\Spell_Holy_HolyBolt",
		tip = L["The UI fades and the look stays, with just a few cameras: flights, AFK, " ..
			"and your Hearthstone and teleports. No cozy, vista, fish, RP walk, auto-run, death or quest cameras."],
		picks = { layout = { forever = "preset" }, camera = "lite", misc = "lite" },
		preview = "bars",
	},
	{
		name = "VFX Only",
		icon = "Interface\\Icons\\Spell_Nature_Lightning",
		tip = L["Just the visual effects (tint, vignette, weather) over your normal UI: nothing fades, no " ..
			"letterbox, and the camera's left to you."],
		picks = { layout = { forever = "preset" }, frames = "nofade", vfx = "noletterbox", misc = "nomusic" },
	},
	{
		name = "Camera Only",
		icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
		tip = L["The normal UI until a camera starts (standing still, going AFK, a flight, an emote...), " ..
			"then CineMode until it ends. The letterbox, tint, vignette and weather show only while a " ..
			"camera mode runs; no soft edges. Standing still starts the AFK camera, and every camera can start music."],
		picks = { layout = { forever = "preset" }, frames = "nofade", camera = "cinemode", vfx = "cameras", misc = "quietnpcs" },
	},
	{
		name = "Solo Explorer",
		icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
		tip = L["Everything on while you're out in the world on your own; the normal UI in a group, " ..
			"in dungeons, raids and PvP."],
		picks = { layout = { forever = "preset" }, frames = "solo" },
	},
}

-- The welcome window's levels (WelcomeDemo.lua), and the profile each picks
-- (none: this client's default), with their own descriptions (simpler than
-- the profiles', true on both clients).
ns.WELCOME_LEVELS = {
	{ label = "Subtle", profile = "VFX Only", line = "A softer look. Your UI stays put.",
		tip = "A color tint, a vignette and weather over your normal UI. Nothing fades, " ..
			"there's no letterbox, and the camera's left to you." },
	{ label = "Balanced", profile = "Lite", line = "The UI fades between fights, a few cameras.",
		tip = "Your UI fades between fights, with the letterbox and tint. The camera moves " ..
			"on its own only on flights, when you go AFK, and for your Hearthstone and teleports." },
	-- (flash: something shown for a moment when it's picked, besides the
	-- profile's preview: "vitals", Vitals Vision's screen edges.)
	{ label = "Full", flash = "vitals", line = "Everything on: letterbox, tint, every camera.",
		tip = "Your UI fades between fights, with the letterbox and tint, and the camera comes " ..
			"alive on flights, by campfires, at vistas, fishing and more. Point at your main action " ..
			"bars to bring them back." },
}
