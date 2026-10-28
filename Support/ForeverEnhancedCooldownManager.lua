-- Cinematic: Forever Enhanced Cooldown Manager.
local _, ns = ...
local L = ns.L

-- Its bars are unnamed: told apart by the parts each bar is made with.
local function Bars(kind)
	return function(frame)
		return frame.kind == kind and type(frame.icons) == "table" and type(frame.mover) == "table"
	end
end

table.insert(ns.ADDON_FRAMES, {
	key = "fecm", addon = "ForeverEnhancedCooldownManager", suite = "Forever Enhanced Cooldown Manager",
	label = "Forever Enhanced Cooldown Manager Cooldowns",
	short = "Enhanced CDM cooldowns", -- (the Standard Frames page's label column is narrow)
	about = L["its cooldown bars, and the pulse when a cooldown is ready"],
	names = { "FECMPulse" },
	match = Bars("cooldown"),
})

-- Its buff bars, a row of their own like the game's Tracked Buffs (following
-- the row above until set: ns.ROW_FALLBACK).
table.insert(ns.ADDON_FRAMES, {
	key = "fecmAuras", addon = "ForeverEnhancedCooldownManager", suite = "Forever Enhanced Cooldown Manager",
	label = "Forever Enhanced Cooldown Manager Buffs", short = "Enhanced CDM buffs",
	about = L["its buff bars"],
	match = Bars("aura"),
})
