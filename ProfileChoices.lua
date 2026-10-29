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
	{ key = "chat", name = "Chat" },
	{ key = "sound", name = "Sound" },
}

-- Each slot as players see it: its name (label), the options page with its
-- settings, a question, its default (the choice a profile that picks none
-- has), and its choices. A choice: part (its key, what profiles pick it
-- by), label and line (what players read), client (only there),
-- hidden (only for profiles, not offered; a client's name: not offered
-- there), made (a layout Cinematic makes
-- and adds to Edit Mode for you, tagged so in Customize), and modules (each a module's key,
-- or { forever = key, retail = key }).
ns.SLOT_CHOICES = {
	layout = { label = "Layout", page = "Profiles", question = "Where should your bars and menus sit?",
		default = "own", choices = {
		-- (Cinematic's own layouts first, then the player's and the game's)
		{ part = "retail", client = "forever", label = "Retail Inspired", made = true,
			line = "Action bars centered along the bottom, menus in the corner", modules = { "layout-retail" } },
		{ part = "forever", client = "retail", hidden = true, label = "Like WoW Forever",
			line = "Laid out like WoW Forever's default", modules = { "layout-forever" } },
		{ part = "pure", client = "retail", label = "Personal Resource Centered", made = true,
			line = "Your resources in the middle, the Cooldown Manager above", modules = { "layout-pure" } },
		{ part = "own", label = "Your own", line = "Cinematic leaves your Edit Mode layout as it is",
			modules = {} },
		{ part = "preset", client = "forever", label = "WoW Forever's", line = "The game's own layout",
			modules = { "layout-preset" } },
	} },
	frames = { label = "Interface", page = "Standard Frames", question = "When does your UI fade?",
		default = "standard", choices = {
		{ part = "immersive", label = "Between fights", line = "Fights and opening windows bring it back",
			modules = { "recovering", "minimap-off-in-fights", "fewer-group-plates" } },
		{ part = "solo", label = "Only when solo", line = "Out in the world on your own; normal in groups",
			modules = { "recovering", "solo-only" } },
		{ part = "pure", label = "Almost always", line = "As little UI as possible, even in fights",
			modules = { "pure-frames", "minimal-target", "pure-plates", "ultra-plates", "pure-tooltips",
				"heal-vision-everywhere", "quest-talk", "combat-vision" } },
		{ part = "nofade", label = "Never", line = "Your UI stays as the game has it",
			modules = { "recovering", "no-fading" } },
		{ part = "standard", label = "Softly", line = "Between fights, with the minimap and group plates as usual",
			modules = { "recovering" } },
	} },
	bars = { label = "Action bars", page = "Mouseover groups", question = "Hide/Show Action Bars in Combat",
		default = "standard", choices = {
		{ part = "always", label = "Always Show", line = "Your action bars stay up all through CineMode",
			modules = { "bars-always" } },
		{ part = "grouped", label = "Action Bars (Classic Group)",
			line = "Point at one and the bars, menus and XP bar come up", modules = {} },
		-- (Retail Group: on retail the client's own, standard, which is the
		-- default there; on Forever, whose own is Classic Group, split.)
		{ part = "split", hidden = "retail", label = "Action Bars (Retail Group)",
			line = "Point at the bars, the menus or the XP bar", modules = { "retail-groups", "micro-off-in-fights" } },
		{ part = "standard", client = "retail", label = "Action Bars (Retail Group)",
			line = "Point at the bars, the menus or the XP bar", modules = { { retail = "retail-groups" } } },
		{ part = "pure", label = "Cooldown Manager", line = "In fights just the Cooldown Manager: no bars or menus",
			modules = { { retail = "retail-groups" }, "pure-cdm" } },
		-- (Only the retired CDM profiles'.)
		{ part = "cdm", hidden = true, label = "Cooldown Manager, pet and stance bars",
			line = "The Cooldown Manager in fights, pet and stance bars too",
			modules = { { retail = "retail-groups" }, "cdm", "micro-off-in-fights" } },
	} },
	camera = { label = "Camera", page = "Cameras", question = "When does the camera move on its own?",
		default = "standard", choices = {
		{ part = "pure", label = "All the time", line = "Every camera, standing still too, and none waits after a fight",
			modules = { "pure-cameras" } },
		{ part = "immersive", label = "Often", line = "Flights, campfires, vistas, fishing, quests, going AFK and more",
			modules = { "walk-run-music" } },
		{ part = "lite", label = "Sometimes", line = "Flights, going AFK, and your Hearthstone and teleports",
			modules = { "lite-cameras" } },
		{ part = "off", label = "Never", line = "The camera is all yours", modules = { "no-cameras" } },
		-- (Only the retired Camera Only profile's, and the plain defaults: not offered.)
		{ part = "cinemode", hidden = true, label = "Cameras bring CineMode",
			line = "Every camera brings CineMode on, and can start music", modules = { "cameras-bring-cinemode" } },
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
	chat = { label = "Chat", page = "Chat", question = "How much chatter?", default = "standard", choices = {
		{ part = "standard", label = "As the game has it", line = "NPC speech and every channel as usual",
			modules = {} },
		{ part = "quietnpcs", label = "No NPC chatter", line = "Chat doesn't peek for NPC speech",
			modules = { "no-npc-chat" } },
		{ part = "lite", label = "Quieter chat", line = "Only General and Trade",
			modules = { "lite-channels" } },
		{ part = "pure", label = "Quietest",
			line = "No General or LocalDefense chat, speech from behind you low on the screen",
			modules = { "pure-chat" } },
	} },
	sound = { label = "Sound", page = "Audio", question = "How much music?", default = "standard", choices = {
		{ part = "standard", label = "Music on cameras", line = "A camera can bring music in, as the defaults have it",
			modules = {} },
		{ part = "spaced", label = "Spaced out", line = "Music on cameras, with half a minute between starts",
			modules = { "music-fatigue" } },
		{ part = "nomusic", label = "No music", line = "No music in CineMode", modules = { "no-cinemode-music" } },
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
-- default: the one a new player's settings start from until they pick one,
-- and that deleting your own goes back to (else the first).
ns.BUILTIN_PROFILES = {
	-- The welcome window's three levels, the same on both clients.
	{
		name = "Subtle",
		label = "Subtle", -- (shown in your language)
		oldNames = { "VFX Only" },
		icon = "Interface\\Icons\\Spell_Nature_Lightning",
		tip = L["Just the visual effects (tint, vignette, weather) over your normal UI: nothing fades, no " ..
			"letterbox, and the camera's left to you."],
		picks = { layout = { forever = "preset" }, frames = "nofade", camera = "off", vfx = "noletterbox",
			sound = "nomusic" },
		modules = { "no-visions" },
	},
	{
		name = "Balanced",
		label = "Balanced", -- (shown in your language)
		oldNames = { "Lite" },
		default = true,
		icon = "Interface\\Icons\\Spell_Holy_HolyBolt",
		tip = L["The UI fades and the look stays, with just a few cameras: flights, AFK, " ..
			"and your Hearthstone and teleports. No cozy, vista, fish, RP walk, auto-run, death or quest cameras."],
		picks = { layout = { forever = "preset" }, camera = "lite", chat = "lite" },
		preview = "bars",
	},
	{
		name = "Cinema",
		label = "Cinema", -- (shown in your language)
		oldNames = { "Pure Cinema", "Full" }, -- (Full: on main for a day, not released)
		icon = "Interface\\Icons\\Ability_Stealth",
		tip = L["As little UI as possible: nameplates show only for enemies in fights, and fights don't bring " ..
			"the letterbox down. Fights bring up only your resource bar and the Cooldown Manager, the cast bar " ..
			"shows all through CineMode, your health shows at the screen's edges and " ..
			"your personal resource display fades in as it drops (Vitals Vision), and every " ..
			"camera can start music."],
		picks = { layout = { forever = "preset", retail = "pure" }, frames = "pure", bars = "pure", camera = "pure",
			vfx = "pure", chat = "pure" },
	},
}

-- Built-ins no longer offered, as they were: one you were on or had saved
-- becomes a profile of your own at login, its settings as they were
-- (ns.InitProfiles). Their picks and modules stay so that comes out right.
ns.RETIRED_PROFILES = {
	{ name = "Forever Default", label = "Default", client = "forever", icon = "Interface\\Icons\\Spell_Holy_MindVision",
		picks = { layout = "preset", frames = "immersive", camera = "immersive", chat = "quietnpcs",
			sound = "spaced" } },
	{ name = "Forever CDM", label = "CDM", client = "forever", icon = "Interface\\Icons\\Spell_Shadow_AntiShadow",
		from = "Forever Default", picks = { bars = "cdm" } },
	{ name = "Forever Retail", label = "Retail", client = "forever", icon = "Interface\\Icons\\INV_Misc_Wrench_01",
		from = "Forever Default", picks = { layout = "retail", bars = "split" } },
	{ name = "Retail Default", label = "Default", client = "retail", icon = "Interface\\Icons\\Spell_Holy_PowerInfusion",
		picks = { frames = "immersive", bars = "split", camera = "immersive", chat = "quietnpcs",
			sound = "spaced" } },
	{ name = "Retail CDM", label = "CDM", client = "retail", icon = "Interface\\Icons\\Ability_Rogue_Preparation",
		from = "Retail Default", picks = { bars = "cdm" } },
	{ name = "Retail Forever", label = "Forever", client = "retail", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
		picks = { layout = "forever", frames = "immersive", bars = "grouped", camera = "immersive",
			chat = "quietnpcs", sound = "spaced" } },
	{ name = "Camera Only", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
		picks = { layout = { forever = "preset" }, frames = "nofade", camera = "cinemode", vfx = "cameras",
			chat = "quietnpcs" } },
	{ name = "Solo Explorer", icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
		picks = { layout = { forever = "preset" }, frames = "solo" } },
}

-- The welcome window's levels (Welcome.lua), and the profile each picks,
-- with their own descriptions (simpler than the profiles', true on both
-- clients).
ns.WELCOME_LEVELS = {
	{ label = "Subtle", profile = "Subtle", line = "A softer look. Your UI and camera stay yours.",
		tip = "A color tint, a vignette and weather over your normal UI. No camera moves on its own and " ..
			"nothing hides, but every camera, fade and the rest of Cinematic are there in Customize and " ..
			"Settings whenever you want them." },
	{ label = "Balanced", profile = "Balanced", line = "Clears your screen between fights.",
		tip = "The clutter clears between fights: your UI fades away for the letterbox and tint, and comes " ..
			"straight back for a fight, a window or a look with the mouse. The camera takes over now and then: " ..
			"on flights, when you go AFK, and for your Hearthstone and teleports." },
	-- (flash: something shown for a moment when it's picked, besides the
	-- profile's preview: "vitals", Vitals Vision's screen edges.)
	{ label = "Cinema", profile = "Cinema", flash = "vitals", line = "Full immersion: just you and the world.",
		tip = "Lose yourself in the world. The game's UI stays away even in fights, and Cinematic shows " ..
			"what you need its own way: your health at the screen's edges, an arrow over your target, your " ..
			"resources and the Cooldown Manager in fights. The letterbox stays up, and the camera comes alive " ..
			"on flights, by campfires, at vistas and more." },
}

-- In your language once it's set (Locales.lua): the levels' text, and each
-- slot's name, question and choices.
ns.OnLanguage(function()
	ns.TranslateFields(ns.WELCOME_LEVELS, "label", "line", "tip")
	for _, info in pairs(ns.SLOT_CHOICES) do
		ns.TranslateFields({ info }, "label", "question")
		ns.TranslateFields(info.choices, "label", "line")
	end
end)
