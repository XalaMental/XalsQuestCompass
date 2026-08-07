-- Xal's Quest Compass
-- Shows a toggleable window listing every quest in your log that is
-- complete and ready to turn in, styled to sit comfortably next to the
-- native Blizzard Objective Tracker. Includes live distances and
-- one-click navigation using WoW's built-in SuperTrack arrow.

local ADDON_NAME = ...

-------------------------------------------------
-- Colors
-------------------------------------------------
local GOLD = { 1, 0.82, 0 }
local GREEN = { 0.4, 1, 0.4 }
local LIGHT_BLUE = { 0.55, 0.8, 1 }
local GREY = { 0.6, 0.6, 0.6 }
local WHITE = { 1, 1, 1 }

-------------------------------------------------
-- Compat (Retail vs Classic)
-------------------------------------------------
-- MoP Classic and Classic Era share one codebase under the hood (confirmed by
-- diffing the client UI trees - only ~80 files differ out of ~3000), so
-- "Classic" below covers both flavors at once; there's no need to tell them
-- apart any further than this.
--
-- Retail's C_QuestLog has 90 members; Classic has 11 - quest-log traversal,
-- distance, and waypoint functions are simply absent there, replaced by older
-- plain-global functions with different shapes (index-based instead of
-- questID-based in a couple of spots). C_QuestLog.GetInfo is retail-only in
-- every form and never present on Classic, so it doubles as a one-time flavor
-- check.
local IS_CLASSIC = C_QuestLog.GetInfo == nil

-- Returns questID, title, isHeader, isHidden for quest-log entry `index`
-- (1-based), or nil if there's nothing there. isHidden covers entries the
-- game itself keeps out of the player's visible quest log (e.g. Renown
-- reward-track notifications) but that still show up in raw traversal -
-- callers must skip these or things that were never real quests show up
-- as if they were.
local function Compat_GetQuestEntry(index)
	if IS_CLASSIC then
		-- GetQuestLogTitle returns positionally, not as a table; questID is
		-- return #8, isHidden is return #16 (verified against live Classic
		-- source, both flavors).
		local title, _, _, isHeader, _, _, _, questID, _, _, _, _, _, _, _, isHidden = GetQuestLogTitle(index)
		if not title then return nil end
		return questID, title, isHeader, isHidden
	end
	local info = C_QuestLog.GetInfo(index)
	if not info then return nil end
	return info.questID, info.title, info.isHeader, info.isHidden
end

local function Compat_GetNumEntries()
	if IS_CLASSIC then
		return (GetNumQuestLogEntries())
	end
	return C_QuestLog.GetNumQuestLogEntries()
end

local function Compat_IsComplete(questID)
	if IS_CLASSIC then
		return IsQuestComplete(questID) and true or false
	end
	local ok, isComplete = pcall(C_QuestLog.IsComplete, questID)
	return ok and isComplete and true or false
end

-- Classic has no cross-zone distance/waypoint API at all (GetDistanceSqToQuest,
-- GetNextWaypoint and friends don't exist there) - the closest equivalent is
-- C_QuestLog.GetQuestsOnMap(uiMapID), which only reports quests whose turn-in
-- is ON that specific map. So on Classic, location data is only ever available
-- for quests in the player's CURRENT zone; anything elsewhere gets no location
-- data (same bucket retail already uses for off-continent quests). Navigate
-- still works regardless of zone though, via the SuperTrack-equivalent arrow
-- (Compat_SetSuperTracked below), which only needs a questID, not coordinates.
local function Compat_GetQuestMapXY(questID, uiMapID)
	if not uiMapID then return nil end
	local pois = C_QuestLog.GetQuestsOnMap(uiMapID)
	if not pois then return nil end
	for _, poi in ipairs(pois) do
		if poi.questID == questID and poi.x and poi.y then
			return poi.x, poi.y
		end
	end
	return nil
end

-- Track/watch functions take a questID on retail but a quest-LOG-INDEX on
-- Classic - GetQuestLogIndexByID converts between the two.
local function Compat_GetQuestWatchType(questID)
	if IS_CLASSIC then
		local index = GetQuestLogIndexByID(questID)
		return index and index > 0 and IsQuestWatched(index)
	end
	return C_QuestLog.GetQuestWatchType(questID)
end

local function Compat_AddQuestWatch(questID)
	if IS_CLASSIC then
		local index = GetQuestLogIndexByID(questID)
		if index and index > 0 then AddQuestWatch(index) end
		return
	end
	C_QuestLog.AddQuestWatch(questID)
end

local function Compat_RemoveQuestWatch(questID)
	if IS_CLASSIC then
		local index = GetQuestLogIndexByID(questID)
		if index and index > 0 then RemoveQuestWatch(index) end
		return
	end
	C_QuestLog.RemoveQuestWatch(questID)
end

-- Points WoW's own on-screen tracking arrow at a quest. C_SuperTrack doesn't
-- exist on Classic at all; the equivalent there is a couple of plain globals.
local function Compat_SetSuperTracked(questID)
	if IS_CLASSIC then
		if SetSuperTrackedQuestID then SetSuperTrackedQuestID(questID) end
		return
	end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		C_SuperTrack.SetSuperTrackedQuestID(questID)
	end
end

-------------------------------------------------
-- Fonts
-------------------------------------------------
-- Stock font files that ship with every WoW client (no extra files
-- needed). "Custom" points at Fonts/CustomFont.ttf inside this addon's
-- own folder -- drop a .ttf you own there with that exact name and pick
-- "Custom" from the dropdown to use it.
local FONT_OPTIONS = {
	{ key = "FRIZQT", name = "Friz Quadrata (default)", path = "Fonts\\FRIZQT__.TTF" },
	{ key = "ARIALN", name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ key = "SKURRI", name = "Skurri", path = "Fonts\\SKURRI.TTF" },
	{ key = "MORPHEUS", name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
	{ key = "CUSTOM", name = "Simply Sans Bold", path = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\CustomFont.ttf" },
}

local OUTLINE_OPTIONS = {
	{ key = "NONE", name = "None", flag = "" },
	{ key = "OUTLINE", name = "Outline", flag = "OUTLINE" },
	{ key = "THICKOUTLINE", name = "Thick Outline", flag = "THICKOUTLINE" },
}

local function GetFontOption(key)
	for _, opt in ipairs(FONT_OPTIONS) do
		if opt.key == key then return opt end
	end
	return FONT_OPTIONS[1]
end

local function GetOutlineOption(key)
	for _, opt in ipairs(OUTLINE_OPTIONS) do
		if opt.key == key then return opt end
	end
	return OUTLINE_OPTIONS[1]
end

local function GetPlayerClassColor()
	local classFile = select(2, UnitClass("player"))
	local c = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
	if c then return c.r, c.g, c.b end
	return GOLD[1], GOLD[2], GOLD[3]
end

-------------------------------------------------
-- Saved variables / defaults
-------------------------------------------------
local defaults = {
	point = { "CENTER", "CENTER", 0, 100 },
	width = 370,
	height = 420,
	minimapAngle = 200,
	minimapHidden = false,
	autoShow = true,
	autoNavigateNearest = false,
	currentZoneOnly = false,
	fontKey = "CUSTOM",
	fontSize = 13,
	outlineKey = "OUTLINE",
	fontShadow = true,
	useClassColor = false,
	windowScale = 0.7,
	autoTurnIn = false,
	autoAccept = false,
	readySound = false,
}

local function InitDB()
	XalsQuestCompassDB = XalsQuestCompassDB or {}
	for k, v in pairs(defaults) do
		if XalsQuestCompassDB[k] == nil then
			XalsQuestCompassDB[k] = v
		end
	end
end

-------------------------------------------------
-- State
-------------------------------------------------
local QTT -- main frame
local minimapButton
local optionsPanel
local rows = {}
local ROW_WIDTH = 328 -- fallback used before the frame exists
local lastReadyCount = 0
local lastReadyCountAll = 0
local currentNavQuestID = nil -- which quest we're currently pointing the player toward

-- Row width tracks the actual visible scroll area, so resizing the
-- window never clips row content again.
local function GetRowWidth()
	if QTT and QTT.scrollFrame then
		return QTT.scrollFrame:GetWidth()
	end
	return ROW_WIDTH
end

-------------------------------------------------
-- Custom font objects
-------------------------------------------------
-- Every quest row (and the window header) draws from these two shared
-- font objects, so changing a setting updates everything at once.
local titleFontObj = CreateFont("XalsQuestCompassTitleFont")
local smallFontObj = CreateFont("XalsQuestCompassSmallFont")
-- Seed both with a guaranteed-valid stock font immediately, so any
-- FontString that uses them before ApplyFontSettings() runs (or if a
-- custom font ever fails to load) never hits a "Font not set" error.
titleFontObj:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
smallFontObj:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")

local function ApplyFontSettings()
	local opt = GetFontOption(XalsQuestCompassDB.fontKey)
	local outline = GetOutlineOption(XalsQuestCompassDB.outlineKey)
	local size = XalsQuestCompassDB.fontSize or 13

	local ok = pcall(function()
		titleFontObj:SetFont(opt.path, size + 2, outline.flag)
		smallFontObj:SetFont(opt.path, math.max(8, size - 3), outline.flag)
	end)
	if not ok then
		-- Fall back to the default stock font if a custom/missing file was picked
		titleFontObj:SetFont(FONT_OPTIONS[1].path, size + 2, outline.flag)
		smallFontObj:SetFont(FONT_OPTIONS[1].path, math.max(8, size - 3), outline.flag)
	end

	titleFontObj:SetShadowOffset(XalsQuestCompassDB.fontShadow and 1 or 0, XalsQuestCompassDB.fontShadow and -1 or 0)
	titleFontObj:SetShadowColor(0, 0, 0, XalsQuestCompassDB.fontShadow and 1 or 0)
	smallFontObj:SetShadowOffset(XalsQuestCompassDB.fontShadow and 1 or 0, XalsQuestCompassDB.fontShadow and -1 or 0)
	smallFontObj:SetShadowColor(0, 0, 0, XalsQuestCompassDB.fontShadow and 1 or 0)

	if QTT then
		if QTT.title then QTT.title:SetFontObject(titleFontObj) end
		QTT:SetScale(XalsQuestCompassDB.windowScale or 1.0)
	end
end

local function GetDefaultTitleColor()
	if XalsQuestCompassDB.useClassColor then
		return GetPlayerClassColor()
	end
	return GOLD[1], GOLD[2], GOLD[3]
end

-------------------------------------------------
-- Small UI helpers
-------------------------------------------------

-- A real visible button (background + gold border), not just plain clickable
-- text -- used everywhere in the addon (Track/Navigate on each row, the
-- footer actions, the zone toggle), so this one change makes every button in
-- the addon easier to spot at a glance.
local function CreateTextButton(parent)
	local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
	btn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	btn:SetBackdropColor(1, 1, 1, 0.08)
	btn:SetBackdropBorderColor(1, 0.82, 0, 0.55)
	btn:SetHeight(20)

	local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("CENTER")
	btn.fs = fs

	local hl = btn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetColorTexture(1, 1, 1, 0.15)
	hl:SetAllPoints()

	function btn:SetLabel(text, color)
		color = color or WHITE
		fs:SetText(text)
		fs:SetTextColor(color[1], color[2], color[3])
		btn:SetWidth(math.max(fs:GetStringWidth() + 20, 28))
	end

	return btn
end

local function CreateDivider(parent)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.35)
	line:SetHeight(1)
	return line
end

-------------------------------------------------
-- Helpers
-------------------------------------------------

local function FormatDistance(info)
	if IS_CLASSIC then
		-- No real yard distance available on Classic (see Compat_GetQuestMapXY) -
		-- "nearby" is honest about what we actually know: same zone, sorted
		-- nearest-first among same-zone quests, but not a precise number.
		if info.ttt_classicSameZone then return "nearby" end
		return ""
	end
	if info.ttt_distSq and info.ttt_onContinent then
		local yards = math.sqrt(info.ttt_distSq)
		return string.format("%.0f yd away", yards)
	elseif info.ttt_distSq ~= nil and not info.ttt_onContinent then
		return "far away"
	end
	return ""
end

-- Appends "what you'll get" lines to a tooltip for a quest sitting in the log,
-- using the quest-log reward query functions (these work by questID alone --
-- no need to actually be at the quest-giver). GetQuestLogRewardXP is pcall'd
-- since it's known to have been pulled from at least one WoW version in the
-- past (Classic) with no official replacement -- if it's ever unavailable here
-- too, XP just quietly drops off the tooltip instead of breaking it.
local function AddRewardPreviewLines(tooltip, questID)
	local addedAny = false

	local money = GetQuestLogRewardMoney(questID)
	if money and money > 0 then
		tooltip:AddLine(GetCoinTextureString(money), 1, 0.82, 0)
		addedAny = true
	end

	local xpOk, xp = pcall(GetQuestLogRewardXP, questID)
	if xpOk and xp and xp > 0 then
		tooltip:AddLine(string.format("%d XP", xp), 0.6, 0.6, 1)
		addedAny = true
	end

	local numRewards = GetNumQuestLogRewards(questID) or 0
	for i = 1, numRewards do
		local itemName, _, numItems = GetQuestLogRewardInfo(i, questID)
		if itemName then
			tooltip:AddLine(numItems and numItems > 1 and (itemName .. " x" .. numItems) or itemName, 1, 1, 1)
			addedAny = true
		end
	end

	local numChoices = GetNumQuestLogChoices(questID) or 0
	if numChoices > 1 then
		tooltip:AddLine(string.format("Choose one of %d rewards", numChoices), 0.9, 0.9, 0.4)
		addedAny = true
	elseif numChoices == 1 then
		local itemName = GetQuestLogChoiceInfo(1, questID)
		if itemName then
			tooltip:AddLine(itemName, 1, 1, 1)
			addedAny = true
		end
	end

	if addedAny then
		tooltip:AddLine(" ")
	end
end

-- Gets the map and normalized (0-1) coordinates of a quest's next
-- waypoint (its turn-in location once it's ready), for building a
-- TomTom-style waypoint command.
local function GetQuestWaypointCoords(questID)
	if IS_CLASSIC then
		-- Only works for quests in the player's current zone - see
		-- Compat_GetQuestMapXY. A quest elsewhere returns nil here and
		-- NavigateToQuest below falls back to the SuperTrack-equivalent arrow,
		-- which needs no coordinates and works regardless of zone.
		local uiMapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		local x, y = Compat_GetQuestMapXY(questID, uiMapID)
		if not uiMapID or not x then return nil end
		return uiMapID, x, y
	end
	local ok, uiMapID = pcall(C_QuestLog.GetNextWaypoint, questID)
	if not ok or not uiMapID then return nil end
	local ok2, x, y = pcall(C_QuestLog.GetNextWaypointForMap, questID, uiMapID)
	if not ok2 or not x or not y then return nil end
	return uiMapID, x, y
end

-- If TomTom is installed, this fires its actual /way chat command
-- (via the same handler the game calls when you type it yourself --
-- no direct use of TomTom's Lua API) so TomTom's own arrow/waypoint UI
-- takes over, since that's generally the better navigation experience.
-- Returns true if a TomTom waypoint was sent.
local function SendTomTomWaypoint(questID, title)
	if not (SlashCmdList and SlashCmdList["TOMTOM_WAY"]) then return false end
	local uiMapID, x, y = GetQuestWaypointCoords(questID)
	if not uiMapID then return false end
	local command = string.format("#%d %.1f %.1f %s", uiMapID, x * 100, y * 100, title or "Quest")
	SlashCmdList["TOMTOM_WAY"](command)
	return true
end

-- Points the player toward the given quest's turn-in. Prefers TomTom's
-- own waypoint (if TomTom is installed) since it's the better nav
-- experience; otherwise falls back to WoW's built-in SuperTrack arrow
-- (appears near the minimap, shows live distance, rotates to point the
-- way -- the same system used for world quests/treasures).
local function NavigateToQuest(questID, title)
	if not questID then return end

	local usedTomTom = SendTomTomWaypoint(questID, title)
	if not usedTomTom then
		Compat_SetSuperTracked(questID)
	end
	currentNavQuestID = questID

	if usedTomTom then
		print(string.format("|cff33ff99Xal's Quest Compass:|r Sent a TomTom waypoint for |cffffff00%s|r.", title or "quest"))
	else
		print(string.format("|cff33ff99Xal's Quest Compass:|r Navigating to |cffffff00%s|r. Look for the arrow next to your minimap.", title or "quest"))
	end
end

-------------------------------------------------
-- Data
-------------------------------------------------

-- Returns a sorted list (nearest first) of quest-info tables for every
-- quest in the quest log that is currently complete (ready to hand in).
-- Uses Compat_IsComplete(questID) (C_QuestLog.IsComplete on retail, the
-- reliable documented way to check turn-in status there -- the isComplete
-- field on GetInfo() is not always populated correctly).
local function GetTurnInQuests()
	local quests = {}
	local numEntries = Compat_GetNumEntries()
	local zoneOnly = XalsQuestCompassDB.currentZoneOnly
	local playerMapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")

	for i = 1, numEntries do
		local questID, title, isHeader, isHidden = Compat_GetQuestEntry(i)
		if questID and not isHeader and not isHidden and questID > 0 and Compat_IsComplete(questID) then
			local info = { questID = questID, title = title }

			if IS_CLASSIC then
				-- Only quests in the player's current zone get location data at
				-- all on Classic (see Compat_GetQuestMapXY) - everything else
				-- falls into the same "no data" bucket as retail's off-continent
				-- case, both here and in the sort below.
				local x, y = playerMapID and Compat_GetQuestMapXY(questID, playerMapID)
				if x and y then
					local pos = C_Map.GetPlayerMapPosition(playerMapID, "player")
					local px, py = pos and pos:GetXY()
					if px and py then
						local dx, dy = x - px, y - py
						info.ttt_classicSameZone = true
						info.ttt_classicSortDist = dx * dx + dy * dy
					end
				end

				local include = true
				if zoneOnly and playerMapID and questID ~= currentNavQuestID and not info.ttt_classicSameZone then
					include = false
				end
				if include then table.insert(quests, info) end
			else
				local dOk, distSq, onContinent = pcall(C_QuestLog.GetDistanceSqToQuest, questID)
				if dOk then
					info.ttt_distSq = distSq
					info.ttt_onContinent = onContinent
				end

				local include = true
				if zoneOnly and playerMapID and questID ~= currentNavQuestID then
					local wOk, waypointMapID = pcall(C_QuestLog.GetNextWaypoint, questID)
					-- If we can't determine a location, show it anyway rather than
					-- risk hiding a quest that's actually ready right here.
					if wOk and waypointMapID and waypointMapID ~= playerMapID then
						include = false
					end
				end

				if include then table.insert(quests, info) end
			end
		end
	end

	table.sort(quests, function(a, b)
		if IS_CLASSIC then
			local aHas = a.ttt_classicSameZone and a.ttt_classicSortDist
			local bHas = b.ttt_classicSameZone and b.ttt_classicSortDist
			if aHas and bHas then
				return a.ttt_classicSortDist < b.ttt_classicSortDist
			elseif aHas and not bHas then
				return true
			elseif bHas and not aHas then
				return false
			end
			return (a.title or "") < (b.title or "")
		end
		local aHas = a.ttt_distSq and a.ttt_onContinent
		local bHas = b.ttt_distSq and b.ttt_onContinent
		if aHas and bHas then
			return a.ttt_distSq < b.ttt_distSq
		elseif aHas and not bHas then
			return true
		elseif bHas and not aHas then
			return false
		end
		return (a.title or "") < (b.title or "")
	end)

	return quests
end

-- A lightweight, zone-independent count used only to decide whether to
-- auto-show the window. This deliberately ignores the "current zone
-- only" display filter -- a quest becoming ready in a different zone
-- should still alert you, even though it won't be listed until you
-- either travel there or switch the window to "All Zones".
local function CountAllReadyQuests()
	local count = 0
	local numEntries = Compat_GetNumEntries()
	for i = 1, numEntries do
		local questID, _, isHeader, isHidden = Compat_GetQuestEntry(i)
		if questID and not isHeader and not isHidden and questID > 0 and Compat_IsComplete(questID) then
			count = count + 1
		end
	end
	return count
end

-------------------------------------------------
-- Rows
-------------------------------------------------

local TOP_PADDING = 5
local CONTROL_GAP = 4
local CONTROL_LINE_HEIGHT = 16
local BOTTOM_PADDING = 6
local MIN_ROW_HEIGHT = 36

local function CreateRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(GetRowWidth(), MIN_ROW_HEIGHT)
	row:SetClipsChildren(false)
	row:EnableMouse(true)

	-- subtle zebra striping, like many quest/achievement lists
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, (index % 2 == 0) and 0.035 or 0)
	row.bg = bg

	local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	hoverBg:SetAllPoints()
	hoverBg:SetColorTexture(1, 0.82, 0, 0.06)
	hoverBg:Hide()
	row.hoverBg = hoverBg

	-- Ready indicator
	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("TOPLEFT", 2, -5)
	icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	row.icon = icon

	-- Quest title -- now wraps onto a second line instead of clipping
	local title = row:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(titleFontObj)
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, 2)
	title:SetPoint("RIGHT", -4, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(true)
	title:SetMaxLines(2)
	title:SetTextColor(GetDefaultTitleColor())
	row.title = title

	-- Distance -- anchored below the title so it follows it whether the
	-- title took one line or two
	local distText = row:CreateFontString(nil, "OVERLAY")
	distText:SetFontObject(smallFontObj)
	distText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -CONTROL_GAP)
	distText:SetTextColor(LIGHT_BLUE[1], LIGHT_BLUE[2], LIGHT_BLUE[3])
	row.distText = distText

	-- Navigate control -- same line as distance, right-aligned
	local navBtn = CreateTextButton(row)
	navBtn:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -CONTROL_GAP)
	navBtn:SetScript("OnClick", function(self)
		local parentRow = self:GetParent()
		if not parentRow.questID then return end
		NavigateToQuest(parentRow.questID, parentRow.title:GetText())
	end)
	row.navBtn = navBtn

	-- Track (objective-tracker watch) control, just left of Navigate
	local trackBtn = CreateTextButton(row)
	trackBtn:SetPoint("TOPRIGHT", navBtn, "TOPLEFT", -8, 0)
	trackBtn:SetScript("OnClick", function(self)
		local parentRow = self:GetParent()
		if not parentRow.questID then return end
		local watchType = Compat_GetQuestWatchType(parentRow.questID)
		if watchType then
			Compat_RemoveQuestWatch(parentRow.questID)
		else
			Compat_AddQuestWatch(parentRow.questID)
		end
	end)
	row.trackBtn = trackBtn

	-- Divider under the row
	local divider = CreateDivider(row)
	divider:SetPoint("BOTTOMLEFT", 2, 0)
	divider:SetPoint("BOTTOMRIGHT", -2, 0)
	divider:SetColorTexture(1, 1, 1, 0.06)

	row:SetScript("OnEnter", function(self)
		self.hoverBg:Show()
		if not self.questID then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.title:GetText() or "", 1, 1, 1)
		AddRewardPreviewLines(GameTooltip, self.questID)
		GameTooltip:AddLine("Track adds it to your objective tracker.", 0.7, 0.7, 0.7, true)
		GameTooltip:AddLine("Navigate points the on-screen arrow at it.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.hoverBg:Hide()
		GameTooltip:Hide()
	end)

	return row
end

-- Updates row content and returns the row's required height, so the
-- caller can stack rows with variable heights when a title wraps.
local function UpdateRow(row, info)
	row.questID = info.questID
	row.title:SetText(info.title or "Unknown Quest")
	row.distText:SetText(FormatDistance(info))

	local watchType = Compat_GetQuestWatchType(info.questID)
	if watchType then
		row.trackBtn:SetLabel("Tracking", GREEN)
	else
		row.trackBtn:SetLabel("Track", GREY)
	end

	if currentNavQuestID and currentNavQuestID == info.questID then
		row.title:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
		row.navBtn:SetLabel("Navigating", GREEN)
	else
		row.title:SetTextColor(GetDefaultTitleColor())
		row.navBtn:SetLabel("Navigate", GOLD)
	end

	local titleHeight = row.title:GetStringHeight() or 16
	local rowHeight = math.max(MIN_ROW_HEIGHT, TOP_PADDING + titleHeight + CONTROL_GAP + CONTROL_LINE_HEIGHT + BOTTOM_PADDING)
	row:SetHeight(rowHeight)

	row:Show()
	return rowHeight
end

-------------------------------------------------
-- Refresh
-------------------------------------------------

local function RefreshList()
	-- scrollChild is one of the last elements built in CreateMainFrame,
	-- so checking for it confirms the window actually finished
	-- constructing -- guards against any code path that fires this
	-- mid-build (e.g. a size-recalculation triggered by SetBackdrop).
	if not QTT or not QTT.scrollChild then return end

	local quests = GetTurnInQuests()

	-- Auto-show if a new quest became ready anywhere, regardless of the
	-- zone filter -- while the window was closed.
	local allReadyCount = CountAllReadyQuests()
	if XalsQuestCompassDB.readySound and allReadyCount > lastReadyCountAll then
		pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master")
	end
	if XalsQuestCompassDB.autoShow and (allReadyCount > lastReadyCountAll) and not QTT:IsShown() then
		QTT:Show()
	end
	lastReadyCountAll = allReadyCount

	-- Optionally auto-navigate to the nearest one when the set of ready
	-- quests changes and nothing is currently being navigated to.
	if XalsQuestCompassDB.autoNavigateNearest and #quests > 0 and (#quests ~= lastReadyCount) then
		if not currentNavQuestID then
			NavigateToQuest(quests[1].questID, quests[1].title)
		end
	end

	lastReadyCount = #quests

	if not QTT:IsShown() then return end

	QTT.noQuestsText:SetShown(#quests == 0)
	QTT.countText:SetText(
		string.format("%d quest%s ready to turn in", #quests, (#quests == 1) and "" or "s")
	)

	local yOffset = 0
	local rowWidth = GetRowWidth()
	for i, info in ipairs(quests) do
		local row = rows[i]
		if not row then
			row = CreateRow(QTT.scrollChild, i)
			rows[i] = row
		end
		row:SetWidth(rowWidth)
		local rowHeight = UpdateRow(row, info)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -yOffset)
		yOffset = yOffset + rowHeight
	end

	for i = #quests + 1, #rows do
		rows[i]:Hide()
		rows[i].questID = nil
	end

	QTT.scrollChild:SetSize(rowWidth, math.max(1, yOffset))
end

-- Keeps existing rows and the scroll child in sync with the window's
-- current width while the user is actively dragging the resize handle
-- (word-wrapped titles need a full reflow when the width changes, not
-- just a width update, so this just re-runs the layout).
local function OnWindowResized()
	RefreshList()
end

-------------------------------------------------
-- Options panel
-------------------------------------------------

local function CreateOptionsPanel()
	local panel = CreateFrame("Frame")
	panel.name = "Xal's Quest Compass"

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Xal's Quest Compass")

	local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	openBtn:SetSize(140, 24)
	openBtn:SetPoint("TOPRIGHT", -16, -14)
	openBtn:SetText("Open Window")
	openBtn:SetScript("OnClick", function()
		if QTT then
			QTT:Show()
		else
			print("|cffff4444Xal's Quest Compass:|r the window didn't initialize. Try /reload.")
		end
	end)

	-- Everything below the title/button header scrolls, so settings can never
	-- get cut off no matter how tall this panel grows -- Blizzard's Settings
	-- canvas does NOT auto-scroll custom content on its own, which is exactly
	-- why the Window Scale slider was invisible/unreachable once this panel
	-- grew past the visible area (fixed 2026-08-07).
	local scrollFrame = CreateFrame("ScrollFrame", "XalsQuestCompassOptionsScrollFrame", panel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -12)
	scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 4)

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetSize(340, 700) -- generously tall; scrolling handles the rest, so this never needs to be exact
	scrollFrame:SetScrollChild(scrollChild)

	local subtitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", 2, 0)
	subtitle:SetPoint("RIGHT", -20, 0)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Toggle the quest window with /xqc or the minimap button. Click Navigate on any quest for an on-screen arrow.")

	local autoShowCB = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
	autoShowCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -24)
	autoShowCB.Text:SetText("Automatically open the window when a quest becomes ready to turn in")
	autoShowCB:SetChecked(XalsQuestCompassDB.autoShow)
	autoShowCB:SetScript("OnClick", function(self)
		XalsQuestCompassDB.autoShow = self:GetChecked() and true or false
	end)
	panel.autoShowCB = autoShowCB

	local autoNavCB = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
	autoNavCB:SetPoint("TOPLEFT", autoShowCB, "BOTTOMLEFT", 0, -8)
	autoNavCB.Text:SetText("Automatically point the arrow at the nearest turn-in when none is selected")
	autoNavCB:SetChecked(XalsQuestCompassDB.autoNavigateNearest)
	autoNavCB:SetScript("OnClick", function(self)
		XalsQuestCompassDB.autoNavigateNearest = self:GetChecked() and true or false
	end)
	panel.autoNavCB = autoNavCB

	local zoneOnlyCB = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
	zoneOnlyCB:SetPoint("TOPLEFT", autoNavCB, "BOTTOMLEFT", 0, -8)
	zoneOnlyCB.Text:SetText("Only show quests ready to turn in within my current zone")
	zoneOnlyCB:SetChecked(XalsQuestCompassDB.currentZoneOnly)
	zoneOnlyCB:SetScript("OnClick", function(self)
		XalsQuestCompassDB.currentZoneOnly = self:GetChecked() and true or false
		if QTT and QTT.zoneToggleBtn then QTT.zoneToggleBtn:UpdateText() end
		RefreshList()
	end)
	panel.zoneOnlyCB = zoneOnlyCB

	local minimapCB = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
	minimapCB:SetPoint("TOPLEFT", zoneOnlyCB, "BOTTOMLEFT", 0, -8)
	minimapCB.Text:SetText("Show minimap button")
	minimapCB:SetChecked(not XalsQuestCompassDB.minimapHidden)
	minimapCB:SetScript("OnClick", function(self)
		XalsQuestCompassDB.minimapHidden = not self:GetChecked()
		if minimapButton then
			minimapButton:SetShown(self:GetChecked())
		end
	end)
	panel.minimapCB = minimapCB

	-- Automation section
	local automationTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	automationTitle:SetPoint("TOPLEFT", minimapCB, "BOTTOMLEFT", 2, -20)
	automationTitle:SetText("Automation")

	local autoTurnInCB = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
	autoTurnInCB:SetPoint("TOPLEFT", automationTitle, "BOTTOMLEFT", -2, -12)
	autoTurnInCB.Text:SetText("Automatically turn in quests with no reward choice to make")
	autoTurnInCB:SetChecked(XalsQuestCompassDB.autoTurnIn)
	autoTurnInCB:SetScript("OnClick", function(self)
		XalsQuestCompassDB.autoTurnIn = self:GetChecked() and true or false
	end)
	panel.autoTurnInCB = autoTurnInCB

	local autoAcceptCB = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
	autoAcceptCB:SetPoint("TOPLEFT", autoTurnInCB, "BOTTOMLEFT", 0, -8)
	autoAcceptCB.Text:SetText("Automatically accept new quests offered by NPCs")
	autoAcceptCB:SetChecked(XalsQuestCompassDB.autoAccept)
	autoAcceptCB:SetScript("OnClick", function(self)
		XalsQuestCompassDB.autoAccept = self:GetChecked() and true or false
	end)
	panel.autoAcceptCB = autoAcceptCB

	local automationNote = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	automationNote:SetPoint("TOPLEFT", autoAcceptCB, "BOTTOMLEFT", 24, -4)
	automationNote:SetPoint("RIGHT", -16, 0)
	automationNote:SetJustifyH("LEFT")
	automationNote:SetText("Skips quests with more than one reward to choose from, quests that cost money to turn in, and a few quest types known to behave oddly (escort, item-start, PvP-flagged) - those still open normally so you can handle them yourself. Hold Shift to pause automation at any time.")

	local readySoundCB = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
	readySoundCB:SetPoint("TOPLEFT", automationNote, "BOTTOMLEFT", -24, -10)
	readySoundCB.Text:SetText("Play a sound when a quest becomes ready to turn in")
	readySoundCB:SetChecked(XalsQuestCompassDB.readySound)
	readySoundCB:SetScript("OnClick", function(self)
		XalsQuestCompassDB.readySound = self:GetChecked() and true or false
	end)
	panel.readySoundCB = readySoundCB

	-- Appearance section
	local appearanceTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	appearanceTitle:SetPoint("TOPLEFT", readySoundCB, "BOTTOMLEFT", 2, -20)
	appearanceTitle:SetText("Appearance")

	local fontLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fontLabel:SetPoint("TOPLEFT", appearanceTitle, "BOTTOMLEFT", 0, -12)
	fontLabel:SetText("Font")

	local fontDropdown = CreateFrame("Frame", "XalsQuestCompassFontDropdown", scrollChild, "UIDropDownMenuTemplate")
	fontDropdown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -4)
	UIDropDownMenu_SetWidth(fontDropdown, 190)
	local function RefreshFontDropdownText()
		UIDropDownMenu_SetText(fontDropdown, GetFontOption(XalsQuestCompassDB.fontKey).name)
	end
	UIDropDownMenu_Initialize(fontDropdown, function(self, level)
		for _, opt in ipairs(FONT_OPTIONS) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = opt.name
			info.checked = (XalsQuestCompassDB.fontKey == opt.key)
			info.func = function()
				XalsQuestCompassDB.fontKey = opt.key
				RefreshFontDropdownText()
				ApplyFontSettings()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	panel.fontDropdown = fontDropdown
	panel.RefreshFontDropdownText = RefreshFontDropdownText

	local outlineLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	outlineLabel:SetPoint("TOPLEFT", fontDropdown, "BOTTOMLEFT", 16, -4)
	outlineLabel:SetText("Font Outline")

	local outlineDropdown = CreateFrame("Frame", "XalsQuestCompassOutlineDropdown", scrollChild, "UIDropDownMenuTemplate")
	outlineDropdown:SetPoint("TOPLEFT", outlineLabel, "BOTTOMLEFT", -16, -4)
	UIDropDownMenu_SetWidth(outlineDropdown, 190)
	local function RefreshOutlineDropdownText()
		UIDropDownMenu_SetText(outlineDropdown, GetOutlineOption(XalsQuestCompassDB.outlineKey).name)
	end
	UIDropDownMenu_Initialize(outlineDropdown, function(self, level)
		for _, opt in ipairs(OUTLINE_OPTIONS) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = opt.name
			info.checked = (XalsQuestCompassDB.outlineKey == opt.key)
			info.func = function()
				XalsQuestCompassDB.outlineKey = opt.key
				RefreshOutlineDropdownText()
				ApplyFontSettings()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	panel.outlineDropdown = outlineDropdown
	panel.RefreshOutlineDropdownText = RefreshOutlineDropdownText

	local sizeSlider = CreateFrame("Slider", "XalsQuestCompassFontSizeSlider", scrollChild, "OptionsSliderTemplate")
	sizeSlider:SetPoint("TOPLEFT", outlineDropdown, "BOTTOMLEFT", 16, -20)
	sizeSlider:SetMinMaxValues(10, 22)
	sizeSlider:SetValueStep(1)
	sizeSlider:SetObeyStepOnDrag(true)
	sizeSlider:SetWidth(190)
	_G[sizeSlider:GetName() .. "Low"]:SetText("10")
	_G[sizeSlider:GetName() .. "High"]:SetText("22")
	_G[sizeSlider:GetName() .. "Text"]:SetText("Font Size")
	sizeSlider:SetValue(XalsQuestCompassDB.fontSize or 13)
	sizeSlider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value + 0.5)
		XalsQuestCompassDB.fontSize = value
		ApplyFontSettings()
	end)
	panel.sizeSlider = sizeSlider

	local shadowCB = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
	shadowCB:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", -16, -28)
	shadowCB.Text:SetText("Text shadow")
	shadowCB:SetChecked(XalsQuestCompassDB.fontShadow)
	shadowCB:SetScript("OnClick", function(self)
		XalsQuestCompassDB.fontShadow = self:GetChecked() and true or false
		ApplyFontSettings()
	end)
	panel.shadowCB = shadowCB

	local classColorCB = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
	classColorCB:SetPoint("TOPLEFT", shadowCB, "BOTTOMLEFT", 0, -8)
	classColorCB.Text:SetText("Use my class color for quest titles")
	classColorCB:SetChecked(XalsQuestCompassDB.useClassColor)
	classColorCB:SetScript("OnClick", function(self)
		XalsQuestCompassDB.useClassColor = self:GetChecked() and true or false
		RefreshList()
	end)
	panel.classColorCB = classColorCB

	local scaleSlider = CreateFrame("Slider", "XalsQuestCompassScaleSlider", scrollChild, "OptionsSliderTemplate")
	scaleSlider:SetPoint("TOPLEFT", classColorCB, "BOTTOMLEFT", 16, -24)
	scaleSlider:SetMinMaxValues(0.7, 1.5)
	scaleSlider:SetValueStep(0.05)
	scaleSlider:SetObeyStepOnDrag(true)
	scaleSlider:SetWidth(190)
	_G[scaleSlider:GetName() .. "Low"]:SetText("0.7")
	_G[scaleSlider:GetName() .. "High"]:SetText("1.5")
	_G[scaleSlider:GetName() .. "Text"]:SetText("Window Scale")
	scaleSlider:SetValue(XalsQuestCompassDB.windowScale or 1.0)
	scaleSlider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value * 20 + 0.5) / 20
		XalsQuestCompassDB.windowScale = value
		ApplyFontSettings()
	end)
	panel.scaleSlider = scaleSlider

	panel:SetScript("OnShow", function()
		autoShowCB:SetChecked(XalsQuestCompassDB.autoShow)
		autoNavCB:SetChecked(XalsQuestCompassDB.autoNavigateNearest)
		zoneOnlyCB:SetChecked(XalsQuestCompassDB.currentZoneOnly)
		minimapCB:SetChecked(not XalsQuestCompassDB.minimapHidden)
		autoTurnInCB:SetChecked(XalsQuestCompassDB.autoTurnIn)
		autoAcceptCB:SetChecked(XalsQuestCompassDB.autoAccept)
		readySoundCB:SetChecked(XalsQuestCompassDB.readySound)
		shadowCB:SetChecked(XalsQuestCompassDB.fontShadow)
		classColorCB:SetChecked(XalsQuestCompassDB.useClassColor)
		sizeSlider:SetValue(XalsQuestCompassDB.fontSize or 13)
		scaleSlider:SetValue(XalsQuestCompassDB.windowScale or 1.0)
		RefreshFontDropdownText()
		RefreshOutlineDropdownText()
	end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
		Settings.RegisterAddOnCategory(category)
		panel.settingsCategoryID = category:GetID()
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end

	optionsPanel = panel
end

local function OpenOptionsPanel()
	if Settings and Settings.OpenToCategory and optionsPanel and optionsPanel.settingsCategoryID then
		Settings.OpenToCategory(optionsPanel.settingsCategoryID)
		Settings.OpenToCategory(optionsPanel.settingsCategoryID)
	elseif InterfaceOptionsFrame_OpenToCategory and optionsPanel then
		InterfaceOptionsFrame_OpenToCategory(optionsPanel)
		InterfaceOptionsFrame_OpenToCategory(optionsPanel)
	end
end

-------------------------------------------------
-- Main frame
-------------------------------------------------

local function CreateMainFrame()
	QTT = CreateFrame("Frame", "XalsQuestCompassFrame", UIParent, "BackdropTemplate")
	QTT:SetSize(XalsQuestCompassDB.width or defaults.width, XalsQuestCompassDB.height or defaults.height)
	QTT:SetResizable(true)
	if QTT.SetResizeBounds then
		QTT:SetResizeBounds(300, 220, 700, 900)
	else
		QTT:SetMinResize(300, 220)
		QTT:SetMaxResize(700, 900)
	end
	-- OnSizeChanged handler is attached at the very end of this function,
	-- once every element it might touch (scrollChild, noQuestsText, etc.)
	-- actually exists -- SetBackdrop() below can itself trigger a size
	-- recalculation, and attaching too early caused it to fire mid-build.

	local p = XalsQuestCompassDB.point
	QTT:SetPoint(p[1], UIParent, p[2], p[3], p[4])

	QTT:SetMovable(true)
	QTT:EnableMouse(true)
	QTT:SetClampedToScreen(true)
	QTT:RegisterForDrag("LeftButton")
	QTT:SetScript("OnDragStart", QTT.StartMoving)
	QTT:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		XalsQuestCompassDB.point = { point, relPoint, x, y }
	end)

	-- Clean, semi-transparent dark panel with a thin gold border --
	-- closer to the native tracker's feel than a stone dialog frame.
	QTT:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	QTT:SetBackdropColor(0.04, 0.04, 0.06, 0.85)
	QTT:SetBackdropBorderColor(1, 0.82, 0, 0.6)

	QTT:SetFrameStrata("MEDIUM")
	QTT:Hide()

	-- Header icon + title
	QTT.icon = QTT:CreateTexture(nil, "ARTWORK")
	QTT.icon:SetSize(20, 20)
	QTT.icon:SetPoint("TOPLEFT", 14, -12)
	QTT.icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Icon.png")
	QTT.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	QTT.title = QTT:CreateFontString(nil, "OVERLAY")
	QTT.title:SetFontObject(titleFontObj)
	QTT.title:SetPoint("LEFT", QTT.icon, "RIGHT", 6, 0)
	QTT.title:SetText("Quest Compass")
	QTT.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	-- Close button
	QTT.closeBtn = CreateFrame("Button", nil, QTT, "UIPanelCloseButton")
	QTT.closeBtn:SetSize(24, 24)
	QTT.closeBtn:SetPoint("TOPRIGHT", -2, -2)
	QTT.closeBtn:SetScript("OnClick", function() QTT:Hide() end)

	-- Options (gear) button
	QTT.optionsBtn = CreateFrame("Button", nil, QTT)
	QTT.optionsBtn:SetSize(16, 16)
	QTT.optionsBtn:SetPoint("RIGHT", QTT.closeBtn, "LEFT", -2, 0)
	QTT.optionsBtn:SetNormalTexture("Interface\\GossipFrame\\GossipGossipIcon")
	QTT.optionsBtn:GetNormalTexture():SetTexCoord(0.05, 0.95, 0.05, 0.95)
	QTT.optionsBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	QTT.optionsBtn:SetScript("OnClick", OpenOptionsPanel)
	QTT.optionsBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Open Settings")
		GameTooltip:Show()
	end)
	QTT.optionsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Count text
	QTT.countText = QTT:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	QTT.countText:SetPoint("TOPLEFT", QTT.icon, "BOTTOMLEFT", 0, -6)
	QTT.countText:SetTextColor(WHITE[1], WHITE[2], WHITE[3])

	-- Zone filter quick-toggle (styled like a clickable link)
	local zoneToggleBtn = CreateTextButton(QTT)
	zoneToggleBtn:SetPoint("LEFT", QTT.countText, "RIGHT", 6, 0)
	function zoneToggleBtn:UpdateText()
		if XalsQuestCompassDB.currentZoneOnly then
			self:SetLabel("[This Zone Only]", GOLD)
		else
			self:SetLabel("[All Zones]", GOLD)
		end
	end
	zoneToggleBtn:SetScript("OnClick", function(self)
		XalsQuestCompassDB.currentZoneOnly = not XalsQuestCompassDB.currentZoneOnly
		self:UpdateText()
		if optionsPanel and optionsPanel.zoneOnlyCB then
			optionsPanel.zoneOnlyCB:SetChecked(XalsQuestCompassDB.currentZoneOnly)
		end
		RefreshList()
	end)
	zoneToggleBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Click to switch between showing only\nthis zone's turn-ins or all of them.", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	zoneToggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	zoneToggleBtn:UpdateText()
	QTT.zoneToggleBtn = zoneToggleBtn

	-- Header divider
	local headerDivider = CreateDivider(QTT)
	headerDivider:SetPoint("TOPLEFT", 14, -58)
	headerDivider:SetPoint("TOPRIGHT", -14, -58)

	-- Empty-state text
	QTT.noQuestsText = QTT:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
	QTT.noQuestsText:SetPoint("CENTER", 0, 20)
	QTT.noQuestsText:SetText("No quests ready to turn in")
	QTT.noQuestsText:Hide()

	-- Scroll frame + child
	local scrollFrame = CreateFrame("ScrollFrame", "XalsQuestCompassScrollFrame", QTT, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 12, -66)
	scrollFrame:SetPoint("BOTTOMRIGHT", -30, 46)
	QTT.scrollFrame = scrollFrame

	-- Resize grip -- always available, drag it directly to resize
	local resizeHandle = CreateFrame("Button", nil, QTT)
	resizeHandle:SetSize(16, 16)
	resizeHandle:SetPoint("BOTTOMRIGHT", -3, 3)
	resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizeHandle:SetScript("OnMouseDown", function()
		QTT:StartSizing("BOTTOMRIGHT")
	end)
	resizeHandle:SetScript("OnMouseUp", function()
		QTT:StopMovingOrSizing()
		XalsQuestCompassDB.width = QTT:GetWidth()
		XalsQuestCompassDB.height = QTT:GetHeight()
		RefreshList()
	end)
	resizeHandle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Drag to resize")
		GameTooltip:Show()
	end)
	resizeHandle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	QTT.resizeHandle = resizeHandle

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetSize(GetRowWidth(), 1)
	scrollFrame:SetScrollChild(scrollChild)
	QTT.scrollChild = scrollChild

	-- Footer divider
	local footerDivider = CreateDivider(QTT)
	footerDivider:SetPoint("BOTTOMLEFT", 14, 38)
	footerDivider:SetPoint("BOTTOMRIGHT", -14, 38)

	-- Footer actions, styled as clickable text links
	local navNearestBtn = CreateTextButton(QTT)
	navNearestBtn:SetPoint("BOTTOM", 0, 18)
	navNearestBtn:SetLabel("Navigate to Nearest", GOLD)
	navNearestBtn:SetScript("OnClick", function()
		local quests = GetTurnInQuests()
		if quests[1] then
			NavigateToQuest(quests[1].questID, quests[1].title)
			RefreshList()
		else
			print("|cff33ff99Xal's Quest Compass:|r No quests are ready to turn in.")
		end
	end)

	local trackAllBtn = CreateTextButton(QTT)
	trackAllBtn:SetPoint("BOTTOMLEFT", 16, 6)
	trackAllBtn:SetLabel("Track All", LIGHT_BLUE)
	trackAllBtn:SetScript("OnClick", function()
		for _, info in ipairs(GetTurnInQuests()) do
			Compat_AddQuestWatch(info.questID)
		end
		RefreshList()
	end)

	local untrackAllBtn = CreateTextButton(QTT)
	untrackAllBtn:SetPoint("BOTTOMRIGHT", -22, 6)
	untrackAllBtn:SetLabel("Untrack All", GREY)
	untrackAllBtn:SetScript("OnClick", function()
		for _, info in ipairs(GetTurnInQuests()) do
			Compat_RemoveQuestWatch(info.questID)
		end
		RefreshList()
	end)

	QTT:SetScript("OnShow", function()
		RefreshList()
		if not QTT.ticker then
			QTT.ticker = C_Timer.NewTicker(1, RefreshList)
		end
	end)
	QTT:SetScript("OnHide", function()
		if QTT.ticker then
			QTT.ticker:Cancel()
			QTT.ticker = nil
		end
	end)

	-- Deliberately NOT registered in UISpecialFrames -- Escape should
	-- not close this window (e.g. while adjusting your camera or
	-- backing out of a menu mid-navigation).

	-- Safe to attach now -- everything RefreshList/OnWindowResized touches
	-- (scrollChild, noQuestsText, countText, footer buttons) exists at this point.
	QTT:SetScript("OnSizeChanged", OnWindowResized)
end

-------------------------------------------------
-- Minimap button
-------------------------------------------------

local function CreateMinimapButton()
	local btn = CreateFrame("Button", "XalsQuestCompassMinimapButton", Minimap)
	minimapButton = btn
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")

	local icon = btn:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Icon.png")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT")

	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local function UpdatePosition()
		local angle = math.rad(XalsQuestCompassDB.minimapAngle or 200)
		local x, y = math.cos(angle) * 80, math.sin(angle) * 80
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
	end

	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			px, py = px / scale, py / scale
			local angle = math.deg(math.atan2(py - my, px - mx))
			XalsQuestCompassDB.minimapAngle = angle
			UpdatePosition()
		end)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	btn:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			OpenOptionsPanel()
			return
		end
		if QTT:IsShown() then
			QTT:Hide()
		else
			QTT:Show()
		end
	end)

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Xal's Quest Compass")
		GameTooltip:AddLine("Left-click: toggle the quest list", 1, 1, 1)
		GameTooltip:AddLine("Right-click: open settings", 1, 1, 1)
		GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	UpdatePosition()
	btn:SetShown(not XalsQuestCompassDB.minimapHidden)
end

-------------------------------------------------
-- Automation (auto turn-in / auto accept)
-------------------------------------------------
-- Both OFF by default -- opt-in only, never decided for the player.
--
-- Auto turn-in only completes a quest when there's nothing to actually decide:
-- zero or one possible reward means there's no real choice, so it's handed in
-- automatically. Two or more reward choices means a real decision, so it's left
-- alone and the normal reward window opens for the player to pick themselves.
-- Quests that cost money to turn in are also left alone, so this never spends
-- the player's gold without asking.
--
-- Auto accept skips a few quest types known to behave oddly under automation
-- (escort/item-start/area-trigger/adventure-map/PvP-flagged quests) and leaves
-- those for the player to accept normally, rather than risk mishandling them.
--
-- Holding Shift pauses both, at any time, so the player can always step in.

local function AutomationPaused()
	return IsShiftKeyDown()
end

-- Turn-in side: NPCs with a Gossip frame (most modern quest-givers)
local function HandleGossipShow()
	if AutomationPaused() then return end

	if XalsQuestCompassDB.autoTurnIn and C_GossipInfo.GetActiveQuests then
		for _, questInfo in ipairs(C_GossipInfo.GetActiveQuests()) do
			if questInfo.isComplete then
				pcall(C_GossipInfo.SelectActiveQuest, questInfo.questID)
				return
			end
		end
	end

	if XalsQuestCompassDB.autoAccept and C_GossipInfo.GetAvailableQuests then
		for _, questInfo in ipairs(C_GossipInfo.GetAvailableQuests()) do
			pcall(C_GossipInfo.SelectAvailableQuest, questInfo.questID)
			return
		end
	end
end

-- Turn-in side: NPCs with a plain quest list and no Gossip frame (index-based, not questID-based)
local function HandleQuestGreeting()
	if AutomationPaused() then return end

	if XalsQuestCompassDB.autoTurnIn then
		for index = 1, GetNumActiveQuests() do
			local _, isComplete = GetActiveTitle(index)
			if isComplete then
				pcall(SelectActiveQuest, index)
				return
			end
		end
	end

	if XalsQuestCompassDB.autoAccept then
		if GetNumAvailableQuests() > 0 then
			pcall(SelectAvailableQuest, 1)
			return
		end
	end
end

-- Accept side: the quest-detail panel just opened for an offered quest
local function HandleQuestDetail(questStartItemID)
	if not XalsQuestCompassDB.autoAccept then return end
	if AutomationPaused() then return end

	-- Already auto-accepted by the game (e.g. certain scripted/story beats) --
	-- this is just a notification popup, not a real accept decision.
	if QuestGetAutoAccept and QuestGetAutoAccept() then
		AcknowledgeAutoAcceptQuest()
		local questID = GetQuestID and GetQuestID()
		if questID and questID > 0 and RemoveAutoQuestPopUp then
			RemoveAutoQuestPopUp(questID)
		end
		return
	end

	-- Skip quest types known to behave oddly under automation -- leave these
	-- for the player to accept normally rather than risk mishandling them.
	if questStartItemID and questStartItemID > 0 then return end
	if QuestIsFromAreaTrigger and QuestIsFromAreaTrigger() then return end
	if QuestIsFromAdventureMap and QuestIsFromAdventureMap() then return end
	if QuestFlagsPVP and QuestFlagsPVP() then return end

	pcall(AcceptQuest)
end

-- Accept side: party-shared / escort-style quests ask for a separate confirm
local function HandleQuestAcceptConfirm()
	if not XalsQuestCompassDB.autoAccept then return end
	if AutomationPaused() then return end
	pcall(ConfirmAcceptQuest)
end

-- Turn-in side: the progress panel just opened -- advance to the reward panel
-- if every objective is actually done (a quest can be "in progress" here
-- without being complete yet).
local function HandleQuestProgress()
	if not XalsQuestCompassDB.autoTurnIn then return end
	if AutomationPaused() then return end
	if IsQuestCompletable and IsQuestCompletable() then
		pcall(CompleteQuest)
	end
end

-- Turn-in side: the reward panel just opened -- complete it only when there's
-- nothing to actually choose, and never when it costs the player money.
local function HandleQuestComplete()
	if not XalsQuestCompassDB.autoTurnIn then return end
	if AutomationPaused() then return end

	local numChoices = GetNumQuestChoices()
	if numChoices > 1 then return end -- a real choice -- leave it for the player

	local money = GetQuestMoneyToGet()
	if money and money > 0 then return end -- never auto-spend the player's gold

	pcall(GetQuestReward, numChoices == 1 and 1 or 0)
end

-------------------------------------------------
-- Events
-------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
-- SUPER_TRACKING_CHANGED belongs to the retail-only C_SuperTrack system and
-- doesn't exist on Classic at all - registering it there throws "Attempt to
-- register unknown event" immediately, which stops this ENTIRE file from
-- ever finishing (nothing after this point would ever run, including the
-- ADDON_LOADED handler - this was a total, silent addon failure on Classic
-- until fixed). Classic has its own equivalently-named event instead.
if IS_CLASSIC then
	eventFrame:RegisterEvent("SUPER_TRACKED_QUEST_CHANGED")
else
	eventFrame:RegisterEvent("SUPER_TRACKING_CHANGED")
end
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("QUEST_GREETING")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_ACCEPT_CONFIRM")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			-- Each step runs even if an earlier one fails, so one broken
			-- piece can never silently stop the rest (or the login message)
			-- from happening.
			local steps = { InitDB, ApplyFontSettings, CreateMainFrame, CreateMinimapButton, CreateOptionsPanel }
			for _, step in ipairs(steps) do
				local ok, err = pcall(step)
				if not ok then
					print("|cffff4444Xal's Quest Compass:|r a startup step failed - |cffffff00" .. tostring(err) .. "|r")
				end
			end
			print("|cff33ff99Xal's Quest Compass|r loaded. Type |cffffff00/xqc|r to toggle the window, or click the minimap button.")
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "GOSSIP_SHOW" then
		HandleGossipShow()
	elseif event == "QUEST_GREETING" then
		HandleQuestGreeting()
	elseif event == "QUEST_DETAIL" then
		HandleQuestDetail(arg1)
	elseif event == "QUEST_ACCEPT_CONFIRM" then
		HandleQuestAcceptConfirm()
	elseif event == "QUEST_PROGRESS" then
		HandleQuestProgress()
	elseif event == "QUEST_COMPLETE" then
		HandleQuestComplete()
	else
		RefreshList()
	end
end)

-------------------------------------------------
-- Slash commands
-------------------------------------------------

SLASH_XALSQC1 = "/xqc"
SLASH_XALSQC2 = "/questcompass"
SLASH_XALSQC3 = "/qtt" -- legacy alias from the old name, kept so old habits still work
SLASH_XALSQC4 = "/questturnin" -- legacy alias
SlashCmdList["XALSQC"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")

	if not QTT then
		print("|cffff4444Xal's Quest Compass:|r the window didn't initialize. Try /reload, and if that doesn't help, check for Lua errors (type /console scriptErrors 1 then reload).")
		return
	end

	if msg == "show" then
		QTT:Show()
	elseif msg == "hide" then
		QTT:Hide()
	elseif msg == "options" or msg == "config" or msg == "settings" then
		OpenOptionsPanel()
	elseif msg == "nav" or msg == "navigate" or msg == "go" then
		local quests = GetTurnInQuests()
		if quests[1] then
			NavigateToQuest(quests[1].questID, quests[1].title)
		else
			print("|cff33ff99Xal's Quest Compass:|r No quests are ready to turn in.")
		end
	else
		if QTT:IsShown() then
			QTT:Hide()
		else
			QTT:Show()
		end
	end
end
