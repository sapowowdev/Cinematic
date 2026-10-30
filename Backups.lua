-- Backups of profiles: a few copies of each kept in the saved settings, to
-- go back to. A copy is taken once a day at login when a profile of your own
-- has changed (db.profileBackupsDaily, on unless unticked), and always just
-- before Delete or Reset profile. db.profileBackups[name] is a profile's,
-- newest first, at most db.profileBackupsKeep of them. Each is stored as
-- sharing stores a profile (ns.ProfileForSharing: changes from the
-- defaults), so one from an older version still restores. Restoring adds it
-- as a new profile; the one it came from stays as it is. A deleted profile's
-- go to db.deletedProfiles for DELETED_DAYS, to bring it back.
--
-- Addons can only keep what the game saves for them, so these live in the
-- same saved file as the profiles: written on /reload and logout, and gone
-- with Reset addon.

local _, ns = ...
local L = ns.L

local KEEP_DEFAULT, KEEP_MAX = 10, 20
local DELETED_DAYS = 30
local DAY = 24 * 60 * 60
local DAILY_DELAY = 10 -- seconds after login (out of the way of loading)

local function CopyTable(source)
	if type(source) ~= "table" then return source end
	local result = {}
	for k, v in pairs(source) do result[k] = CopyTable(v) end
	return result
end

local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not Same(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function Version()
	return ns.Version and ns.Version() or "?"
end

function ns.BackupKeep()
	local keep = ns.db and tonumber(ns.db.profileBackupsKeep) or KEEP_DEFAULT
	return math.max(1, math.min(KEEP_MAX, math.floor(keep)))
end

function ns.BackupDaily()
	return not ns.db or ns.db.profileBackupsDaily ~= false
end

-- Every profile's list down to the number kept.
local function TrimAll()
	local keep = ns.BackupKeep()
	for _, list in pairs(ns.db.profileBackups or {}) do
		for i = #list, keep + 1, -1 do list[i] = nil end
	end
end

-- A copy of the profile's settings as they are now (why: "daily", "reset"
-- or "delete"). None when they're the same as its newest.
function ns.BackupProfile(name, why)
	local db = ns.db
	if not (db and db.profiles and name and ns.ProfileExists(name)) then return end
	db.profileBackups = db.profileBackups or {}
	local list = db.profileBackups[name] or {}
	local settings = CopyTable(ns.ProfileForSharing(name))
	if list[1] and Same(list[1].settings, settings) then return end
	table.insert(list, 1, { time = time(), version = Version(), why = why, settings = settings,
		note = db.profileNotes and db.profileNotes[name], icon = ns.ProfileIcon(name) })
	db.profileBackups[name] = list
	TrimAll()
	ns.Log("state", "profile backed up (" .. why .. "): " .. name)
end

-- Just before Delete: its last copy, and the lot kept as a deleted profile's.
function ns.BackupDeleted(name)
	ns.BackupProfile(name, "delete")
	local db = ns.db
	local list = db.profileBackups and db.profileBackups[name]
	if not list or not list[1] then return end
	db.profileBackups[name] = nil
	db.deletedProfiles = db.deletedProfiles or {}
	table.insert(db.deletedProfiles, 1, { name = name, time = time(), backups = list })
end

-- After Rename: its backups go with it.
function ns.RenameBackups(old, new)
	local backups = ns.db.profileBackups
	if backups and backups[old] then backups[new], backups[old] = backups[old], nil end
end

-- name, or name with a number after it, whichever is free.
local function FreeName(name)
	local free, n = name, 1
	while ns.FindProfile(free) do
		n = n + 1
		free = name .. " " .. n
	end
	return free
end

-- A backup's settings this version has, of the right kind (as import keeps).
local function Known(settings)
	local known = {}
	for k, v in pairs(settings or {}) do
		if ns.KnownProfileSetting(k, v) then known[k] = CopyTable(v) end
	end
	return known
end

-- A backup as a new profile, switched to. Its name: the profile's, with the day.
function ns.RestoreBackup(name, i)
	local list = ns.db.profileBackups and ns.db.profileBackups[name]
	local backup = list and list[i]
	if not backup then return end
	local day = date("%Y-%m-%d", backup.time)
	local new = FreeName(L["%s (%s)"]:format(ns.ProfileLabel(name), day))
	local note = L["Restored from a backup of %s from %s."]:format(ns.ProfileLabel(name), day)
	if ns.AddSharedProfile(new, Known(backup.settings), note, backup.icon) then
		ns.Print(L["backup restored as a new profile: %s"]:format(new))
		return new
	end
end

-- A deleted profile back, as it was when deleted, with its backups.
function ns.RestoreDeleted(i)
	local deleted = ns.db.deletedProfiles
	local entry = deleted and deleted[i]
	local backup = entry and entry.backups and entry.backups[1]
	if not backup then return end
	local new = FreeName(entry.name)
	if ns.AddSharedProfile(new, Known(backup.settings), backup.note, backup.icon) then
		table.remove(deleted, i)
		ns.db.profileBackups = ns.db.profileBackups or {}
		ns.db.profileBackups[new] = entry.backups
		ns.Print(L["profile restored: %s"]:format(new))
		return new
	end
end

-- At login: deleted ones past their time go, and each of your own profiles
-- gets the day's copy if it's changed since its newest.
local function Daily()
	local db = ns.db
	if not (db and db.profiles) then return end
	local deleted = db.deletedProfiles
	if deleted then
		for i = #deleted, 1, -1 do
			if time() - (deleted[i].time or 0) > DELETED_DAYS * DAY then table.remove(deleted, i) end
		end
	end
	TrimAll()
	if not ns.BackupDaily() then return end
	local today = date("%Y-%m-%d")
	for _, name in ipairs(ns.ProfileNames()) do
		if not ns.IsBuiltinProfile(name) then
			local list = db.profileBackups and db.profileBackups[name]
			local newest = list and list[1]
			if not newest or date("%Y-%m-%d", newest.time) ~= today then
				ns.BackupProfile(name, "daily")
			end
		end
	end
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
	C_Timer.After(DAILY_DELAY, Daily)
end)

-- The Backups window (the Profiles page's Backups button): the active
-- profile's backups, deleted profiles, and how many to keep.

local window
local ROW_H = 36

local function When(t)
	local day = date("%Y-%m-%d", t)
	local clock = date("%H:%M", t)
	if day == date("%Y-%m-%d") then return L["Today, %s"]:format(clock) end
	if day == date("%Y-%m-%d", time() - DAY) then return L["Yesterday, %s"]:format(clock) end
	return day .. ", " .. clock
end

local function Row(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row.line = row:CreateTexture(nil, "BACKGROUND")
	row.line:SetPoint("TOPLEFT")
	row.line:SetPoint("TOPRIGHT")
	row.line:SetHeight(1)
	row.line:SetColorTexture(1, 1, 1, 0.08)
	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.title:SetPoint("TOPLEFT", 4, -4)
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.sub:SetTextColor(0.6, 0.6, 0.6)
	row.restore = ns.PanelButton(row)
	row.restore:SetSize(84, 22)
	row.restore:SetPoint("RIGHT", -2, 0)
	row.restore:SetText(L["Restore"])
	row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.tag:SetPoint("RIGHT", row.restore, "LEFT", -10, 0)
	return row
end

local Fill -- (below)

local function CreateWindow()
	window = CreateFrame("Frame", "CinematicBackupsWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetSize(520, 460)
	window:SetPoint("CENTER", 0, 40)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	ns.SkinWindow(window) -- (the menu look: Skin.lua)
	tinsert(UISpecialFrames, "CinematicBackupsWindow") -- Escape closes it

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	window.title = title
	local close = ns.SkinClose(CreateFrame("Button", nil, window, "UIPanelCloseButton"))
	close:SetPoint("TOPRIGHT", -2, -2)
	local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	hint:SetPoint("RIGHT", window, "RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText(L["Newest first. Restoring one adds it as a new profile and switches to it; " ..
		"the profile it came from stays as it is."])

	-- The list: a box with a scroll bar.
	local holder = CreateFrame("Frame", nil, window, BackdropTemplateMixin and "BackdropTemplate")
	holder:SetPoint("TOPLEFT", 14, -64)
	holder:SetPoint("RIGHT", window, "RIGHT", -14, 0)
	holder:SetHeight(270)
	holder:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	holder:SetBackdropColor(0, 0, 0, 0.6)
	ns.SkinWindow(holder, true)
	local scroll = ns.SkinScroll(CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate"))
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local list = CreateFrame("Frame", nil, scroll)
	list:SetSize(1, 1)
	scroll:SetScrollChild(list)
	-- (The rows as wide as the box, the scroll bar only when they don't all fit.)
	scroll:SetScript("OnSizeChanged", function(_, width) list:SetWidth(width) end)
	window.scroll = scroll
	window.list, window.rows = list, {}
	window.empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.empty:SetJustifyH("LEFT")
	window.deletedHeader = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.deletedHeader:SetText(L["Recently deleted"])

	-- How many to keep.
	local ok, keep = pcall(CreateFrame, "Slider", "CinematicBackupsKeep", window, "OptionsSliderTemplate")
	if not ok then
		keep = CreateFrame("Slider", "CinematicBackupsKeep", window)
		keep:SetOrientation("HORIZONTAL")
		keep:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	end
	for _, suffix in ipairs({ "Low", "High", "Text" }) do
		local fs = keep[suffix] or _G["CinematicBackupsKeep" .. suffix]
		if fs then fs:Hide() end
	end
	keep:SetSize(200, 16)
	keep:SetPoint("BOTTOMLEFT", 18, 66)
	keep:SetMinMaxValues(1, KEEP_MAX)
	keep:SetValueStep(1)
	if keep.SetObeyStepOnDrag then keep:SetObeyStepOnDrag(true) end
	ns.SkinSlider(keep)
	local keepLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	keepLabel:SetPoint("BOTTOMLEFT", keep, "TOPLEFT", 0, 4)
	function window:KeepLabel(value)
		keepLabel:SetText(L["Backups kept per profile: %s"]:format("|cffffd100" .. value .. "|r"))
	end
	keep:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value + 0.5)
		window:KeepLabel(value)
		if window.refreshing then return end
		ns.db.profileBackupsKeep = value
		TrimAll()
		Fill()
	end)
	window.keep = keep

	local daily = ns.SkinCheck(CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate"))
	daily:SetSize(26, 26)
	daily:SetPoint("BOTTOMLEFT", 12, 30)
	local dailyText = daily.Text or daily.text
	if not dailyText then
		dailyText = daily:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		dailyText:SetPoint("LEFT", daily, "RIGHT", 2, 0)
	end
	dailyText:SetFontObject("GameFontHighlight")
	dailyText:SetText(L["Back up once a day when a profile has changed"])
	daily:SetScript("OnClick", function(self)
		ns.db.profileBackupsDaily = self:GetChecked() and true or false
	end)
	window.daily = daily
	local always = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	always:SetPoint("BOTTOMLEFT", 18, 16)
	always:SetJustifyH("LEFT")
	always:SetTextColor(0.6, 0.6, 0.6)
	always:SetText(L["Always backed up just before Delete and Reset profile."])
end

local function GetRow(i)
	local row = window.rows[i]
	if not row then
		row = Row(window.list)
		window.rows[i] = row
	end
	return row
end

-- The list as it is now: the active profile's backups, then deleted profiles.
function Fill()
	local db = ns.db
	local name = window.profile
	window.title:SetText(L["Backups of %s"]:format(ns.ProfileLabel(name)))
	local backups = db.profileBackups and db.profileBackups[name] or {}
	local deleted = db.deletedProfiles or {}
	local y, n = 0, 0
	local function Next(title, sub, tag, color, onClick)
		n = n + 1
		local row = GetRow(n)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("TOPRIGHT", 0, -y)
		row.title:SetText(title)
		row.sub:SetText(sub)
		row.tag:SetText(tag)
		row.tag:SetTextColor(unpack(color))
		row.restore:SetScript("OnClick", onClick)
		row:Show()
		y = y + ROW_H
	end
	for i, backup in ipairs(backups) do
		local tag = backup.why == "reset" and L["Before reset"] or backup.why == "delete" and L["Before delete"]
			or L["Daily"]
		Next(When(backup.time), L["Version %s, %d settings changed"]:format(backup.version or "?", Count(backup.settings or {})),
			tag, backup.why == "daily" and { 0.6, 0.6, 0.6 } or { 1, 0.65, 0.2 }, function()
				local new = ns.RestoreBackup(name, i)
				if new then window:Hide() end
			end)
	end
	window.empty:ClearAllPoints()
	window.empty:SetPoint("TOPLEFT", 4, -y - 6)
	window.empty:SetPoint("RIGHT", -4, 0)
	if #backups == 0 then
		window.empty:SetText(ns.IsBuiltinProfile(name)
			and L["None yet. A built-in profile is backed up just before Reset profile."]
			or L["None yet. One's taken the first day this profile changes, and just before Delete."])
		window.empty:Show()
		y = y + window.empty:GetStringHeight() + 14
	else
		window.empty:Hide()
	end
	window.deletedHeader:SetShown(#deleted > 0)
	if #deleted > 0 then
		window.deletedHeader:ClearAllPoints()
		window.deletedHeader:SetPoint("TOPLEFT", 4, -y - 10)
		y = y + 30
		for i, entry in ipairs(deleted) do
			local gone = date("%Y-%m-%d", (entry.time or 0) + DELETED_DAYS * DAY)
			Next(entry.name, L["Deleted %s, kept until %s"]:format(date("%Y-%m-%d", entry.time or 0), gone),
				L["Deleted"], { 1, 0.3, 0.3 }, function()
					local new = ns.RestoreDeleted(i)
					if new then window:Hide() end
				end)
		end
	end
	for i = n + 1, #window.rows do window.rows[i]:Hide() end
	window.list:SetHeight(math.max(1, y))
	local scroll = window.scroll
	if (scroll:GetWidth() or 0) > 0 then window.list:SetWidth(scroll:GetWidth()) end
	local bar = scroll.ScrollBar or _G[(scroll:GetName() or "") .. "ScrollBar"]
	if bar then
		local fits = y <= (scroll:GetHeight() or 0)
		bar:SetShown(not fits)
		if fits then scroll:SetVerticalScroll(0) end
	end
end

-- name: whose (the active profile's if none).
function ns.ShowBackups(name)
	if not ns.db then return end
	if not window then CreateWindow() end
	window.profile = name or ns.ActiveProfile()
	window.refreshing = true
	window.keep:SetValue(ns.BackupKeep())
	window:KeepLabel(ns.BackupKeep())
	window.refreshing = nil
	window.daily:SetChecked(ns.BackupDaily())
	Fill()
	window:Show()
end
