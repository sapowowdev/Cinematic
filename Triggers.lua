-- Cinematic: which standing-still trigger wins when several are on at once.
-- Each source names the trigger it has on now (from the state Camera.lua's
-- CurrentEvent works out each time, its side effects done first), and the
-- first in order whose trigger has a camera here picks it. One trigger can
-- come from two sources at different places (a campfire buff while sitting
-- by the fire comes before the emotes; standing by it, after them).
local _, ns = ...

-- The sources in order: { id, order, Key(state) -> trigger key or nil }.
ns.TRIGGER_SOURCES = {}

-- Adds a source (or replaces one with the same id), kept in order; a tie
-- goes after the ones already there.
function ns.RegisterTriggerSource(source)
	local list = ns.TRIGGER_SOURCES
	for i = #list, 1, -1 do
		if list[i].id == source.id then table.remove(list, i) end
	end
	local at = #list + 1
	for i, each in ipairs(list) do
		if each.order > source.order then
			at = i
			break
		end
	end
	table.insert(list, at, source)
end

function ns.UnregisterTriggerSource(id)
	local list = ns.TRIGGER_SOURCES
	for i = #list, 1, -1 do
		if list[i].id == id then table.remove(list, i) end
	end
end

-- The first source's trigger that has a camera (cameraOf(key): its camera
-- here and now, or nil), and that camera; nil for none.
function ns.PickTrigger(state, cameraOf)
	for _, source in ipairs(ns.TRIGGER_SOURCES) do
		local key = source.Key(state)
		local camera = key and cameraOf(key)
		if camera then
			return key, camera
		end
	end
	return nil
end

-- The built-in ones. A Hearthstone or teleport cast first (it calls a logout
-- off anyway), then logging out, then going AFK (it comes after whatever you
-- were doing: AFK while sitting is the AFK camera), then the rest, and
-- standing still last. The state's fields: departing ("Hearth", "Teleport"
-- or false), logout, afk, byFire (sitting by a campfire), emote (the emote
-- or seat's event, or nil), weapon, campfire, still.
local BUILT_IN = {
	{ id = "depart", order = 100, Key = function(state) return state.departing or nil end },
	{ id = "logout", order = 200, Key = function(state) return state.logout and "Logout" or nil end },
	{ id = "afk", order = 300, Key = function(state) return state.afk and "AFK" or nil end },
	{ id = "byFire", order = 400, Key = function(state) return state.byFire and "Campfire" or nil end },
	{ id = "emote", order = 500, Key = function(state) return state.emote end },
	{ id = "weapon", order = 600, Key = function(state) return state.weapon and "Weapon" or nil end },
	{ id = "campfire", order = 700, Key = function(state) return state.campfire and "Campfire" or nil end },
	{ id = "still", order = 800, Key = function(state) return state.still and "Still" or nil end },
}
for _, source in ipairs(BUILT_IN) do ns.RegisterTriggerSource(source) end
