-- Personal Resources: your player frame and personal resource display, kept
-- up while you recover after a fight (Frames.lua's PORTRAIT_FRAMES), and
-- held back at the start of a fight until there's something to see. A fight
-- you go into with your power at rest (rage or runic power at 0, mana or
-- energy full...) brings up the bars only once it changes; the same for
-- health. Shown or not, the bars' rows on the Standard Frames page say when
-- they come up: this only holds back the fight's.
-- Health and power can be secret (WoW Forever, even out of combat), so rest
-- goes by their change events: they keep firing while either regenerates or
-- drains, and stop once it's back at rest.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.fightWaitPower = true      -- the resource bar waits for your power to change at a fight's start
DEFAULTS.fightWaitHealth = false    -- ...the health bar for your health
DEFAULTS.fightWaitPortrait = false  -- ...the player frame for either
DEFAULTS.drainWhenNotEmpty = true   -- "until full" also waits for rage, runic power and the like to drain to 0
DEFAULTS.petWhenNotFull = true      -- the pet frame stays up after a fight until its health is full
DEFAULTS.lowManaShare = 0           -- the resource bar shows whenever mana is under this share (0: off)
DEFAULTS.lowManaPortrait = false    -- ...and the player frame too

-- The resource bar's stand-in (Frames.lua; none: no personal resource display).
local personalPower = _G.CinematicPersonalPower

-- No change for this long: at rest. (Regeneration ticks every 2 seconds.)
local REST_WINDOW = 3

local lastChange = { health = -math.huge, power = -math.huge, mana = -math.huge }
-- In a fight: whether each is still at rest since it started (nil: not in one).
local waiting

local watcher = CreateFrame("Frame")
watcher:RegisterUnitEvent("UNIT_HEALTH", "player")
watcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
watcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player") -- (a druid's form: a power of its own)
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event, _, powerToken)
	-- (Each fight looks afresh, on the first check in it.)
	if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		waiting = nil
		return
	end
	local kind = event == "UNIT_HEALTH" and "health" or "power"
	lastChange[kind] = GetTime()
	if waiting then
		waiting[kind] = false
	end
	-- (Mana apart, for the mana bar's row. A secret token: maybe mana.)
	if event == "UNIT_POWER_UPDATE" and (issecretvalue and issecretvalue(powerToken) or powerToken == "MANA") then
		lastChange.mana = GetTime()
		if waiting then
			waiting.mana = false
		end
	end
end)

local function RestedNow(kind, now)
	return now - lastChange[kind] >= REST_WINDOW
end

-- A row (Standard Frames' player, prd, prdpower) to hold back from the fight
-- now: its setting is on and what it shows has been at rest since the fight
-- started. Out of a fight (casting at an enemy, the pull), while it's at rest now.
local ROW_WAIT = {
	player = { "fightWaitPortrait", "health", "power" },
	prd = { "fightWaitHealth", "health" },
	prdpower = { "fightWaitPower", "power" },
	prdmana = { "fightWaitPower", "mana" },
}
function ns.FightHold(row)
	local wait = ROW_WAIT[row]
	if not wait or not ns.db[wait[1]] then
		return false
	end
	local now = GetTime()
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		if not waiting then
			waiting = { health = RestedNow("health", now), power = RestedNow("power", now), mana = RestedNow("mana", now) }
		end
		return waiting[wait[2]] and (not wait[3] or waiting[wait[3]])
	end
	waiting = nil
	return RestedNow(wait[2], now) and (not wait[3] or RestedNow(wait[3], now))
end

local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- Rage, runic power and the others that rest at 0 (Frames.lua's
-- EMPTY_AT_REST) not drained yet. Secret: still changing.
local function PowerDraining()
	local _, token = UnitPowerType("player")
	if type(token) ~= "string" or (issecretvalue and issecretvalue(token)) or not ns.EMPTY_AT_REST[token] then
		return false
	end
	local power = UnitPower("player")
	if Readable(power) then
		return power > 0
	end
	return not RestedNow("power", GetTime())
end

-- Mana (while it's the power you're showing, or any: with a mana bar of
-- its own) under the Low mana share. Secret: can't tell, so no.
local function LowMana(any)
	local share = ns.db.lowManaShare or 0
	local powerType = UnitPowerType("player")
	if share <= 0 or not any and (not Readable(powerType) or powerType ~= 0) then
		return false
	end
	local mana, maxMana = UnitPower("player", 0), UnitPowerMax("player", 0)
	return Readable(mana) and Readable(maxMana) and maxMana > 0 and mana / maxMana < share
end

-- Mana not full, for the mana bar's row. Secret: still changing.
local function ManaRecovering()
	local mana, maxMana = UnitPower("player", 0), UnitPowerMax("player", 0)
	if Readable(mana) and Readable(maxMana) then
		return maxMana > 0 and mana < maxMana
	end
	return not RestedNow("mana", GetTime())
end

-- Whether your player frame, personal resource display or pet frame stays up
-- now in CineMode, shown like a fight's frames. setting: the frame's "until
-- full" one (Frames.lua's PORTRAIT_FRAMES; nil for the pet frame); afterFight:
-- within the Calm Timer of a fight or fall, or coming back to life.
function ns.KeepYourFrameUp(setting, entry, afterFight, fighting)
	local db = ns.db
	if entry.name == "PetFrame" then
		return db.petWhenNotFull and afterFight and ns.IsPetRecovering() or false
	end
	if not setting then
		return false
	end
	local row = setting == "prdWhenNotFull" and entry.group or "player"
	-- (No resource display: low mana is the player frame's. With the mana bar
	-- of ours up, it's that bar's row, not the power bar's.)
	local manaBar = ns.PersonalManaShown and ns.PersonalManaShown()
	if (row == (manaBar and "prdmana" or "prdpower") or row == "player" and (db.lowManaPortrait or not personalPower))
		and LowMana(manaBar) then
		return true
	end
	if not (db[setting] and afterFight) or fighting and ns.FightHold(row) then
		return false
	end
	-- (The mana bar's row: until your mana's full.)
	if row == "prdmana" then
		return manaBar and ManaRecovering() or false
	end
	return ns.IsPlayerRecovering() or db.drainWhenNotEmpty and PowerDraining() or false
end

-- The page.
function ns.CreatePersonalResourcesPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Personal Resources"])
	title:SetPoint("TOPLEFT", 16, -16)
	local hasDisplay = _G.CinematicPersonalPower ~= nil
	local intro = kit.PageIntro(content, title,
		L["Your player frame, pet frame and personal resource display in CineMode: kept up while you recover " ..
		"after a fight or run low on mana, and held back at the start of a fight until there's something to " ..
		"see. When they come up at all (always, in fights, in places) is their rows' on the Standard Frames page."])
	-- Their look: the Style hub's Personal resources page (PersonalStyle.lua).
	ns.StyleLink(content, title, "Personal Style", L["Opens the Style hub's Personal resources page: how the " ..
		"bars look."], kit.Tooltip)
	local stack = kit.Stack(intro, "label")
	local function Tick(key, label, tip, enabledBy)
		local check = stack:Add(kit.Check(content, key, label, tip), "check")
		if enabledBy then kit.GreyUnless(check, enabledBy) end
		return check
	end

	stack:Header(content, L["After a fight"])
	Tick("portraitWhenNotFull", L["Show your player frame until health and power are full"],
		L["Keeps your player frame up after a fight, a fall or resurrecting, until your health and " ..
		"power are full. Rage and runic power don't count."])
	if hasDisplay then
		Tick("prdWhenNotFull", L["Show your personal resource display until health and power are full"],
			L["The same for your personal resource display."])
	end
	Tick("drainWhenNotEmpty", L["Rage, runic power and the like count until drained"],
		L["Rage, runic power and the other resources that drain away out of combat count too: the frames " ..
		"ticked above stay up until they're back to 0, within the Calm Timer."],
		function(db) return db.portraitWhenNotFull or hasDisplay and db.prdWhenNotFull end)
	if _G.PetFrame then
		Tick("petWhenNotFull", L["Show your pet frame until its health is full"],
			L["Keeps your pet frame up after a fight or a fall, within the Calm Timer, until your pet's " ..
			"health is full."])
	end

	-- Low mana: the resource bar (and the player frame, ticked) whenever mana is low.
	stack:Header(content, L["Low mana"])
	local function Percent(value) return value == 0 and L["Off"] or ("%d%%"):format(value) end
	local lowMana = stack:Add(kit.Slider(content, "lowManaShare", L["Show below this much mana"], 0, 90, 5,
		Percent, 100, function() kit.Refresh() end), "slider")
	kit.Tooltip(lowMana, hasDisplay
		and L["In CineMode, your resource bar shows whenever your mana is under this share, in a fight or " ..
		"not: drinking, or saving mana for the pull. Off: 0."]
		or L["In CineMode, your player frame shows whenever your mana is under this share, in a fight or " ..
		"not: drinking, or saving mana for the pull. Off: 0."])
	if hasDisplay then
		Tick("lowManaPortrait", L["Your player frame too"],
			L["Low mana brings up your player frame as well as your resource bar."],
			function(db) return (db.lowManaShare or 0) > 0 end)
	end

	-- (Only while fights bring up frames: the Combat switch on the main page.)
	local function Fights(db) return db.stayInCombat end
	stack:Header(content, L["At the start of a fight"])
	if hasDisplay then
		Tick("fightWaitPower", L["Resource bar waits for your power to change"],
			L["A fight you go into with your mana, rage, energy or the like at rest (rage at 0, mana full...) " ..
			"brings up your resource bar only once it changes: your first cast, your first hit. Going in " ..
			"with it still filling or draining, it comes up straight away. It stays up for the rest of the fight."],
			Fights)
		Tick("fightWaitHealth", L["Health bar waits for your health to change"],
			L["The same for your personal health bar: it comes up with the first hit or heal you take."], Fights)
	end
	Tick("fightWaitPortrait", L["Player frame waits for your health or power to change"],
		L["The same for your player frame: it comes up once your health or your power changes."], Fights)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Personal Resources")
end
