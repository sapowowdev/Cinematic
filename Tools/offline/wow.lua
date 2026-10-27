-- A stand-in for the game, enough for the addon's files to load outside WoW
-- (Lua 5.1): every frame is a table that keeps its parent, scripts, events
-- and text, and any other API call or global hands back a do-nothing stub.
-- For the offline tools (Tools/offline/run.lua), not the addon.
--
-- client: "forever" or "retail" (which client the files think they're on).

local M = {}

-- The do-anything stub: indexing or calling it gives it back, arithmetic
-- gives 0, joining gives "".
local Stub = {}
local stubMeta = {}
stubMeta.__index = function() return Stub end
stubMeta.__call = function() return Stub end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do
	stubMeta[op] = function() return 0 end
end
stubMeta.__concat = function(a, b)
	return (type(a) == "string" and a or "") .. (type(b) == "string" and b or "")
end
stubMeta.__len = function() return 0 end
stubMeta.__lt = function() return false end
stubMeta.__le = function() return true end
stubMeta.__tostring = function() return "stub" end
setmetatable(Stub, stubMeta)
M.Stub = Stub

-- Frames: methods named in Methods work; any other Capitalised one is a
-- stub; other fields are the frame's own (nil until set).
local frames = {}
M.frames = frames
local Methods = {}
local frameMeta = {
	__index = function(self, key)
		if Methods[key] then return Methods[key] end
		-- (a template's own regions, made by the code when missing)
		if key == "Text" then return nil end
		if type(key) == "string" and key:find("^%u") then return Stub end
		return nil
	end,
}
local function NewObject(kind, name, parent)
	local object = setmetatable({ _kind = kind, _name = name, _parent = parent, _scripts = {}, _events = {},
		_children = {}, _regions = {}, _shown = true }, frameMeta)
	if parent and type(parent) == "table" and rawget(parent, "_children") then
		table.insert(parent._children, object)
	end
	return object
end
function Methods:GetParent() return self._parent end
function Methods:SetParent(parent) self._parent = parent end
function Methods:GetName() return self._name end
function Methods:SetScript(script, fn) self._scripts[script] = fn end
function Methods:GetScript(script) return self._scripts[script] end
function Methods:HookScript(script, fn)
	local old = self._scripts[script]
	self._scripts[script] = function(...)
		if old then old(...) end
		return fn(...)
	end
end
function Methods:HasScript() return true end
function Methods:RegisterEvent(event) self._events[event] = true end
function Methods:RegisterUnitEvent(event) self._events[event] = true end
function Methods:UnregisterEvent(event) self._events[event] = nil end
function Methods:UnregisterAllEvents() self._events = {} end
function Methods:IsEventRegistered(event) return self._events[event] == true end
function Methods:SetText(text) self._text = text end
function Methods:GetText() return self._text end
function Methods:SetFormattedText(fmt, ...) self._text = fmt:format(...) end
function Methods:CreateTexture() local r = NewObject("Texture", nil, self) table.insert(self._regions, r) return r end
function Methods:CreateFontString() local r = NewObject("FontString", nil, self) table.insert(self._regions, r) return r end
function Methods:CreateMaskTexture() return self:CreateTexture() end
function Methods:CreateLine() return self:CreateTexture() end
function Methods:CreateAnimationGroup() return NewObject("AnimationGroup", nil, self) end
function Methods:CreateAnimation() return NewObject("Animation", nil, self) end
function Methods:GetChildren() return unpack(self._children) end
function Methods:GetRegions() return unpack(self._regions) end
function Methods:GetNumChildren() return #self._children end
function Methods:IsShown() return self._shown end
function Methods:IsVisible() return self._shown end
function Methods:Show() self._shown = true end
function Methods:Hide() self._shown = false end
function Methods:SetShown(shown) self._shown = shown and true or false end
function Methods:GetObjectType() return self._kind end
function Methods:IsObjectType(kind) return self._kind == kind end
function Methods:IsForbidden() return false end
function Methods:IsProtected() return false end
function Methods:GetAlpha() return 1 end
function Methods:GetEffectiveAlpha() return 1 end
function Methods:GetScale() return 1 end
function Methods:GetEffectiveScale() return 1 end
function Methods:GetWidth() return 100 end
function Methods:GetHeight() return 20 end
function Methods:GetSize() return 100, 20 end
function Methods:GetLeft() return 0 end
function Methods:GetRight() return 100 end
function Methods:GetTop() return 20 end
function Methods:GetBottom() return 0 end
function Methods:GetCenter() return 50, 10 end
function Methods:GetNumPoints() return 0 end
function Methods:GetFrameLevel() return 1 end
function Methods:GetFrameStrata() return "MEDIUM" end
function Methods:GetID() return 0 end
function Methods:GetChecked() return self._checked end
function Methods:SetChecked(on) self._checked = on end
function Methods:GetValue() return self._value or 0 end
function Methods:SetValue(value) self._value = value end
function Methods:GetMinMaxValues() return 0, 1 end
function Methods:GetStringWidth() return 50 end
function Methods:GetStringHeight() return 12 end
function Methods:GetLineHeight() return 12 end
function Methods:GetNumLines() return 1 end
function Methods:IsMouseOver() return false end
function Methods:IsMouseEnabled() return false end
function Methods:GetAttribute() return nil end
function Methods:GetFont() return "font", 12, "" end
function Methods:GetTextColor() return 1, 1, 1, 1 end
function Methods:GetVertexColor() return 1, 1, 1, 1 end
function Methods:GetTexture() return nil end
function Methods:GetCursorPosition() return 0 end
function Methods:GetVerticalScroll() return 0 end
function Methods:GetVerticalScrollRange() return 0 end
function Methods:IsEnabled() return true end
function Methods:IsPlaying() return false end
function Methods:GetDuration() return 0 end
function Methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end

function M.CreateFrame(kind, name, parent, template)
	local frame = NewObject(kind or "Frame", name, parent)
	if type(template) == "string" and template:find("Check") then frame.Text = frame:CreateFontString() end
	frames[#frames + 1] = frame
	if type(name) == "string" then _G[name] = frame end
	return frame
end

-- Sends an event to every frame registered for it.
function M.Fire(event, ...)
	for _, frame in ipairs(frames) do
		local handler = frame._events[event] and frame._scripts.OnEvent
		if handler then
			local ok, err = pcall(handler, frame, event, ...)
			if not ok then M.Warn(event .. ": " .. tostring(err)) end
		end
	end
end

M.warnings = {}
function M.Warn(text)
	M.warnings[#M.warnings + 1] = text
end

-- Puts the game's globals in place (unknown ones: the stub).
function M.Install(client)
	local env = {
		CreateFrame = M.CreateFrame,
		UIParent = M.CreateFrame("Frame", "UIParent"),
		WorldFrame = M.CreateFrame("Frame", "WorldFrame"),
		GameTooltip = M.CreateFrame("GameTooltip", "GameTooltip"),
		WOW_PROJECT_MAINLINE = 1,
		WOW_PROJECT_ID = client == "retail" and 1 or 2,
		GetTime = function() return 0 end,
		time = os.time, date = os.date,
		GetServerTime = os.time,
		debugprofilestop = function() return 0 end,
		GetLocale = function() return "enUS" end,
		GetCVar = function() return "0" end,
		geterrorhandler = function() return function() end end,
		seterrorhandler = function() end,
		GetCVarBool = function() return false end,
		SetCVar = function() end,
		InCombatLockdown = function() return false end,
		IsInInstance = function() return false, "none" end,
		IsInGroup = function() return false end,
		IsInRaid = function() return false end,
		UnitClass = function() return "Warrior", "WARRIOR", 1 end,
		UnitRace = function() return "Human", "Human", 1 end,
		UnitName = function() return "Player", nil end,
		UnitLevel = function() return 60 end,
		UnitFactionGroup = function() return "Alliance", "Alliance" end,
		UnitGUID = function() return nil end,
		UnitExists = function() return false end,
		GetBuildInfo = function() return client == "retail" and "11.2.0" or "1.15.7", "0", "", client == "retail" and 110200 or 11507 end,
		GetRealmName = function() return "Realm" end,
		GetAddOnMetadata = function() return nil end,
		IsAddOnLoaded = function() return false end,
		hooksecurefunc = function() end,
		issecretvalue = nil,
		tinsert = table.insert, tremove = table.remove, wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
		strsplit = function(sep, text)
			local parts = {}
			for part in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do parts[#parts + 1] = part end
			return unpack(parts)
		end,
		strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
		strjoin = function(sep, ...) return table.concat({ ... }, sep) end,
		strlower = string.lower, strupper = string.upper, strfind = string.find, strsub = string.sub,
		format = string.format, gsub = string.gsub, strlen = string.len, strmatch = string.match,
		floor = math.floor, ceil = math.ceil, abs = math.abs, max = math.max, min = math.min, sqrt = math.sqrt,
		random = math.random, fastrandom = math.random,
		C_Timer = { After = function() end, NewTicker = function() return Stub end, NewTimer = function() return Stub end },
		C_AddOns = {
			IsAddOnLoaded = function() return false end,
			GetAddOnEnableState = function() return 0 end,
			GetAddOnInfo = function() return nil end,
			DoesAddOnExist = function() return false end,
			GetAddOnMetadata = function() return nil end,
		},
		StaticPopupDialogs = {},
		SlashCmdList = {},
		Settings = Stub,
		C_GamePad = client ~= "retail" and Stub or nil,
		MenuUtil = Stub,
		BackdropTemplateMixin = Stub,
		CinematicPersonalPower = nil,
	}
	for k, v in pairs(env) do _G[k] = v end
	-- (the saved settings: none yet, a fresh install)
	local unset = { CinematicDB = true, CinematicCharDB = true }
	setmetatable(_G, { __index = function(_, key)
		if unset[key] then return nil end
		-- (CamelCase: the API's functions and frames; ALL_CAPS constants: none.)
		if type(key) == "string" and key:find("^%u") and key:find("%l") then return Stub end
		return nil
	end })
end

return M
