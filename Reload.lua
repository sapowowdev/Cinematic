local _, ns = ...
local L = ns.L

-- Reloading the UI (Quality of life > General). A Reload button on the
-- screen (reloadButton, off to start with), up even with the UI hidden, and
-- a key for it (Bindings.xml: CINEMATIC_RELOAD). After a reload, what was open
-- comes back (reloadKeepWindows): the settings window at the page you were on
-- (scrolled where it was), the game's windows and bags, and Cinematic's own
-- windows. A /reload of your own does the same. Drag the button to move it
-- (db.reloadPoint, for the account).

local STALE = 120 -- seconds: what was open, saved longer ago than this, isn't reopened

-- Windows by frame name: the addon they're in when it isn't loaded at start,
-- and how to open them (else ShowUIPanel).
local WINDOWS = {
	{ "CharacterFrame", open = function() ToggleCharacter("PaperDollFrame") end },
	{ "WorldMapFrame", open = function() ToggleWorldMap() end },
	{ "QuestLogFrame", open = function() ToggleQuestLog() end },
	{ "SpellBookFrame", open = function() ToggleSpellBook(BOOKTYPE_SPELL) end },
	{ "PlayerSpellsFrame", addon = "Blizzard_PlayerSpells" },
	{ "PlayerTalentFrame", addon = "Blizzard_TalentUI" },
	{ "TalentFrame", addon = "Blizzard_TalentUI" },
	{ "FriendsFrame", open = function() ToggleFriendsFrame() end },
	{ "CommunitiesFrame", addon = "Blizzard_Communities" },
	{ "CollectionsJournal", addon = "Blizzard_Collections" },
	{ "EncounterJournal", addon = "Blizzard_EncounterJournal" },
	{ "AchievementFrame", addon = "Blizzard_AchievementUI" },
	{ "PVEFrame", open = function() PVEFrame_ToggleFrame() end },
	{ "MacroFrame", addon = "Blizzard_MacroUI" },
	{ "AddonList" },
	-- Cinematic's own
	{ "CinematicWelcome", open = function() ns.ShowWelcome() end },
	{ "CinematicLogWindow", open = function() ns.ShowLog() end },
	{ "CinematicTalentCalc", open = function() ns.ToggleTalentCalc() end },
	{ "CinematicRolls", open = function() ns.ToggleRollWindow() end },
}

local function Shown(frame)
	return frame and frame.IsShown and ns.Flag(frame:IsShown()) or false
end

local function BagsOpen()
	if Shown(_G.ContainerFrameCombinedBags) then return true end
	for i = 1, 13 do
		if Shown(_G["ContainerFrame" .. i]) then return true end
	end
	return false
end

-- What's open now, into db.reloadState (for the account: the profile may
-- not be the same one after).
local function Save()
	if not ns.db or not ns.Setting("reloadKeepWindows") then return end
	local state = { at = time(), windows = {}, bags = BagsOpen() }
	for _, window in ipairs(WINDOWS) do
		if Shown(_G[window[1]]) then state.windows[#state.windows + 1] = window[1] end
	end
	local panel = SettingsPanel or InterfaceOptionsFrame
	if Shown(panel) then
		local page, scroll = ns.ShownOptionsPage()
		if page then
			state.page, state.scroll = page, scroll and scroll:GetVerticalScroll() or nil
		elseif SettingsPanel and SettingsPanel.GetCurrentCategory then
			-- (a page of the game's own, or another addon's)
			local category = SettingsPanel:GetCurrentCategory()
			state.category = category and category.GetID and category:GetID() or true
		else
			state.category = true
		end
	end
	ns.db.reloadState = state
end

-- (A window that won't open: the rest still do. Said in the dev copy only.)
local function Try(what, fn)
	local ok, err = pcall(fn)
	if not ok and ns.isDev then ns.Print(("reload: couldn't open %s again (%s)"):format(what, tostring(err))) end
end

local LoadAddOn = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn

-- Opens again what was open, if it was saved just now (this reload's).
local function Restore()
	if not ns.db then return end
	local state = ns.db.reloadState
	ns.db.reloadState = nil
	if not state or not state.at or time() - state.at > STALE or not ns.Setting("reloadKeepWindows") then return end
	local byName = {}
	for _, window in ipairs(WINDOWS) do byName[window[1]] = window end
	for _, name in ipairs(state.windows or {}) do
		local window = byName[name]
		if window then
			Try(name, function()
				if window.addon then LoadAddOn(window.addon) end
				if window.open then
					window.open()
				elseif _G[name] and not Shown(_G[name]) then
					ShowUIPanel(_G[name])
				end
			end)
		end
	end
	if state.bags then Try("bags", OpenAllBags) end
	if state.page then
		Try("the settings", function() ns.OpenOptions(state.page ~= "" and state.page or nil) end)
		-- (Scrolled once the page has laid itself out: tried again a moment later.)
		if state.scroll and state.scroll > 0 then
			local function Scroll()
				local _, scroll = ns.ShownOptionsPage()
				if scroll then
					scroll:SetVerticalScroll(math.min(state.scroll, scroll:GetVerticalScrollRange()))
				end
			end
			C_Timer.After(0.1, Scroll)
			C_Timer.After(0.5, Scroll)
		end
	elseif state.category then
		Try("the settings", function()
			if type(state.category) == "number" and Settings and Settings.OpenToCategory then
				Settings.OpenToCategory(state.category)
			elseif SettingsPanel then
				ShowUIPanel(SettingsPanel)
			elseif InterfaceOptionsFrame then
				ShowUIPanel(InterfaceOptionsFrame)
			end
		end)
	end
end

-- The key (Bindings.xml) and the button.
function Cinematic_Reload()
	Save()
	ReloadUI()
end
-- (Your own /reload too. Saved again by the key's own call: no harm.)
if ReloadUI then hooksecurefunc("ReloadUI", Save) end
if C_UI and C_UI.Reload then hooksecurefunc(C_UI, "Reload", Save) end

-- The button. No parent, so hiding the UI (Alt+Z, CineMode) leaves it up;
-- scaled as UIParent is so it's the size of the rest.
local button = CreateFrame("Button", "CinematicReloadButton", nil, "UIPanelButtonTemplate")
button:SetSize(64, 20)
button:SetFrameStrata("FULLSCREEN_DIALOG")
button:SetMovable(true)
button:SetClampedToScreen(true)
button:RegisterForDrag("LeftButton")
button:Hide()
button:SetScript("OnClick", Cinematic_Reload)
button:SetScript("OnDragStart", button.StartMoving)
button:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relativePoint, x, y = self:GetPoint()
	ns.db.reloadPoint = { point, relativePoint, x, y }
end)
button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:SetText(L["Reload the UI"])
	if ns.Setting("reloadKeepWindows") then
		GameTooltip:AddLine(L["The windows you have open open again after."], 1, 1, 1, true)
	end
	GameTooltip:AddLine(L["Drag to move it."], 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function Place()
	button:SetText(L["Reload"])
	button:SetScale(UIParent:GetEffectiveScale())
	button:ClearAllPoints()
	local saved = ns.db and ns.db.reloadPoint
	if saved then
		button:SetPoint(saved[1], nil, saved[2], saved[3], saved[4])
	else
		button:SetPoint("TOP", nil, "TOP", 300, -4)
	end
end

-- Shown while ticked (and its page on), checked now and then: the tick, the
-- page's switch and a profile change all come round to it.
local function Update()
	local on = ns.Setting("reloadButton") and true or false
	if on ~= button:IsShown() then button:SetShown(on) end
end

button:RegisterEvent("PLAYER_ENTERING_WORLD")
button:RegisterEvent("UI_SCALE_CHANGED")
button:RegisterEvent("DISPLAY_SIZE_CHANGED")
button:SetScript("OnEvent", function(_, event, _, isReload)
	Place()
	if event == "PLAYER_ENTERING_WORLD" then
		Update()
		if isReload then
			-- (A moment for the settings pages and the rest to be made.)
			C_Timer.After(0.5, Restore)
		elseif ns.db then
			ns.db.reloadState = nil
		end
	end
end)
C_Timer.NewTicker(0.5, Update)
