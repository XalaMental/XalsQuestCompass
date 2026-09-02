-- Xal's Quest Compass
-- Shows a toggleable window listing every quest in your log that is
-- complete and ready to turn in, styled to sit comfortably next to the
-- native Blizzard Objective Tracker. Includes live distances and
-- one-click navigation using WoW's built-in SuperTrack arrow.

local ADDON_NAME = ...

-- Shared global table so MinimapButton.lua (LibDataBroker/LibDBIcon-based,
-- same pattern as Routes/Courier) can call back into this file without a
-- full addonTable restructure - same simple-global-table approach Craft
-- Courier already uses (XC = XC or {}).
XQC = XQC or {}

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
	return info.questID, info.title, info.isHeader, info.isHidden, info.frequency
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
	{ key = "FIRASANS", name = "Fira Sans Medium", path = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf" },
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
	autoShow = true,
	autoNavigateNearest = false,
	currentZoneOnly = false,
	fontKey = "CUSTOM",
	fontSize = 13,
	outlineKey = "OUTLINE",
	fontShadow = true,
	shadowColor = { 0, 0, 0 },
	useClassColor = false,
	customFontColor = { 1, 0.82, 0 },
	elvuiSkinning = false,
	fadeWhenEmpty = true,
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
local optionsPanel
local rows = {}
local ROW_WIDTH = 328 -- fallback used before the frame exists
local lastReadyCount = 0
local currentNavQuestID = nil -- which quest we're currently pointing the player toward
local currentDisplayIndex = 1 -- which ready quest (1 = closest) is currently shown in the single-quest display
local UpdateRouteFooter -- forward-declared; assigned in the Route planning section, called from RefreshList
local RefreshList -- forward-declared; assigned below, called from XQC.ToggleMinimized (defined earlier in the file)

-- Row width tracks the actual visible quest display area, so resizing the
-- window never clips row content again.
local function GetRowWidth()
	if QTT and QTT.questArea then
		return QTT.questArea:GetWidth()
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

	local sc = XalsQuestCompassDB.shadowColor or { 0, 0, 0 }
	titleFontObj:SetShadowOffset(XalsQuestCompassDB.fontShadow and 1 or 0, XalsQuestCompassDB.fontShadow and -1 or 0)
	titleFontObj:SetShadowColor(sc[1], sc[2], sc[3], XalsQuestCompassDB.fontShadow and 1 or 0)
	smallFontObj:SetShadowOffset(XalsQuestCompassDB.fontShadow and 1 or 0, XalsQuestCompassDB.fontShadow and -1 or 0)
	smallFontObj:SetShadowColor(sc[1], sc[2], sc[3], XalsQuestCompassDB.fontShadow and 1 or 0)

	if QTT then
		QTT:SetScale(XalsQuestCompassDB.windowScale or 1.0)
	end
end

local function GetDefaultTitleColor()
	if XalsQuestCompassDB.useClassColor then
		return GetPlayerClassColor()
	end
	local c = XalsQuestCompassDB.customFontColor or GOLD
	return c[1], c[2], c[3]
end

-------------------------------------------------
-- Small UI helpers
-------------------------------------------------

-- Brand.DrawDivider takes a fixed x/y/width, but call sites here each anchor
-- their own divider differently (TOPLEFT/TOPRIGHT, BOTTOMLEFT/BOTTOMRIGHT) -
-- so this keeps the flexible "return a texture, caller anchors it" shape
-- while matching Brand's actual color/thickness.
local function CreateDivider(parent)
	local Brand = XQC.BrandStyle
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.16, 0.12, 0.05, 1)
	PixelUtil.SetHeight(line, Brand.LINE_THICKNESS)
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
	-- No distance data at all (some quests, e.g. campaign/story quests,
	-- don't expose one) - "Nearby" beats leaving the line blank.
	return "Nearby"
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
		local itemName, itemTexture, numItems = GetQuestLogRewardInfo(i, questID)
		if itemName then
			local icon = itemTexture and ("|T" .. itemTexture .. ":16|t ") or ""
			tooltip:AddLine(icon .. (numItems and numItems > 1 and (itemName .. " x" .. numItems) or itemName), 1, 1, 1)
			addedAny = true
		end
	end

	local numChoices = GetNumQuestLogChoices(questID) or 0
	if numChoices > 1 then
		tooltip:AddLine(string.format("Choose one of %d rewards", numChoices), 0.9, 0.9, 0.4)
		addedAny = true
	elseif numChoices == 1 then
		local itemName, itemTexture = GetQuestLogChoiceInfo(1, questID)
		if itemName then
			local icon = itemTexture and ("|T" .. itemTexture .. ":16|t ") or ""
			tooltip:AddLine(icon .. itemName, 1, 1, 1)
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
	if not (SlashCmdList and SlashCmdList["TOMTOM_WAY"]) then
		print("|cff33ff99Xal's Quest Compass (debug):|r TomTom's /way command isn't registered - SlashCmdList[\"TOMTOM_WAY\"] is nil.")
		return false
	end
	local uiMapID, x, y = GetQuestWaypointCoords(questID)
	if not uiMapID then
		print("|cff33ff99Xal's Quest Compass (debug):|r GetQuestWaypointCoords found no waypoint for this quest (questID " .. tostring(questID) .. ") - falling back to the built-in arrow.")
		return false
	end
	local command = string.format("#%d %.1f %.1f %s", uiMapID, x * 100, y * 100, title or "Quest")
	print("|cff33ff99Xal's Quest Compass (debug):|r Sending to TomTom: " .. command)
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
local function GetTurnInQuests(forceAllZones)
	local quests = {}
	local numEntries = Compat_GetNumEntries()
	local zoneOnly = not forceAllZones and XalsQuestCompassDB.currentZoneOnly
	local playerMapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")

	-- The quest log itself groups every entry under a zone/category header
	-- row (isHeader = true, title = the zone/category name) - usually a more
	-- reliable zone source than GetQuestWaypointCoords (which can come back
	-- nil for quests with no on-map turn-in location). Some quests (campaign/
	-- story quests especially) don't sit under a normal zone header at all
	-- though, so fall back to the player's own current zone - a ready-to-
	-- turn-in quest is almost always right where you're already standing.
	local currentHeaderName = nil
	local playerZoneName = nil
	if playerMapID then
		local playerMapInfo = C_Map.GetMapInfo(playerMapID)
		playerZoneName = playerMapInfo and playerMapInfo.name
	end

	for i = 1, numEntries do
		local questID, title, isHeader, isHidden, frequency = Compat_GetQuestEntry(i)
		if isHeader then
			currentHeaderName = title
		end
		if questID and not isHeader and not isHidden and questID > 0 and Compat_IsComplete(questID) then
			local info = { questID = questID, title = title, zoneName = currentHeaderName or playerZoneName }

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

				-- Expiration warning - daily/weekly quests still reset even
				-- once ready to turn in, so a stale one can reset out from
				-- under you before you get to it. (World Quests deliberately
				-- excluded - they auto-complete on their own the moment the
				-- objective is done, so they never actually sit in the
				-- ready-to-turn-in list the way a normal quest does.)
				if frequency == Enum.QuestFrequency.Daily then
					local rOk, secondsLeft = pcall(GetQuestResetTime)
					if rOk and secondsLeft and secondsLeft > 0 then
						info.minutesLeft = math.floor(secondsLeft / 60)
					end
				elseif frequency == Enum.QuestFrequency.Weekly then
					local rOk, secondsLeft = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
					if rOk and secondsLeft and secondsLeft > 0 then
						info.minutesLeft = math.floor(secondsLeft / 60)
					end
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

-------------------------------------------------
-- Rows
-------------------------------------------------

local TOP_PADDING = 5
local CONTROL_GAP = 4
local CONTROL_LINE_HEIGHT = 16
local BOTTOM_PADDING = 6
local MIN_ROW_HEIGHT = 36
local QUEST_AREA_TOP = 76 -- distance from QTT's top to questArea's top
local QUEST_AREA_BOTTOM = 44 -- distance from QTT's bottom to questArea's bottom (room for the chevron/route status strip)
local MINIMIZED_HEIGHT = 40 -- small footprint is the whole point of the minimized bar

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

	-- Track/Navigate sit on the title's own line, top right - not their own
	-- line further down. No ready-check icon; the confirmed mockup has none.
	local navBtn = XQC.BrandStyle.MakeLinkButton(row)
	navBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)
	navBtn:SetScript("OnClick", function(self)
		local parentRow = self:GetParent()
		if not parentRow.questID then return end
		NavigateToQuest(parentRow.questID, parentRow.title:GetText())
	end)
	row.navBtn = navBtn

	local trackBtn = XQC.BrandStyle.MakeLinkButton(row)
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

	-- Quest title -- wraps onto a second line instead of clipping, stopping
	-- short of Track/Navigate so long titles don't run under them.
	local title = row:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(titleFontObj)
	title:SetPoint("TOPLEFT", 0, -2)
	title:SetPoint("RIGHT", trackBtn, "LEFT", -8, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(true)
	title:SetMaxLines(2)
	title:SetTextColor(GetDefaultTitleColor())
	row.title = title

	-- Zone name, bracketed, directly under the title - its own line, left
	-- only, nothing anchored off its right edge anymore.
	local zoneText = row:CreateFontString(nil, "OVERLAY")
	zoneText:SetFontObject(smallFontObj)
	zoneText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
	zoneText:SetJustifyH("LEFT")
	zoneText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	row.zoneText = zoneText

	-- Distance -- its own line below the zone name.
	local distText = row:CreateFontString(nil, "OVERLAY")
	distText:SetFontObject(smallFontObj)
	distText:SetPoint("TOPLEFT", zoneText, "BOTTOMLEFT", 0, -CONTROL_GAP)
	distText:SetTextColor(LIGHT_BLUE[1], LIGHT_BLUE[2], LIGHT_BLUE[3])
	row.distText = distText

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
	row.zoneText:SetText(info.zoneName and ("[" .. info.zoneName .. "]") or "")

	-- Daily/weekly quests still reset even once ready to turn in - warn
	-- inline once under an hour left so a stale one doesn't reset on you.
	local distLine = FormatDistance(info)
	if info.minutesLeft and info.minutesLeft <= 60 then
		distLine = distLine .. string.format("  |cffff5555(resets in %dm)|r", info.minutesLeft)
	end
	row.distText:SetText(distLine)

	local watchType = Compat_GetQuestWatchType(info.questID)
	local isTracked = watchType and true or false
	if isTracked then
		row.trackBtn:SetLabel("Tracking", GREEN)
	else
		row.trackBtn:SetLabel("Track", GREY)
	end

	local isNavigating = currentNavQuestID and currentNavQuestID == info.questID
	if isNavigating then
		row.navBtn:SetLabel("Navigating", GREEN)
	else
		row.navBtn:SetLabel("Navigate", GOLD)
	end

	-- Title turns green whenever the quest is tracked or being navigated to
	-- - either one counts as "you're actively on this quest."
	if isTracked or isNavigating then
		row.title:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
	else
		row.title:SetTextColor(GetDefaultTitleColor())
	end

	local titleHeight = row.title:GetStringHeight() or 16
	local zoneHeight = row.zoneText:GetStringHeight() or 12
	local rowHeight = TOP_PADDING + titleHeight + 2 + zoneHeight + CONTROL_GAP + CONTROL_LINE_HEIGHT + BOTTOM_PADDING
	row:SetHeight(rowHeight)

	row:Show()
	return rowHeight
end

-------------------------------------------------
-- Minimize
-------------------------------------------------
-- Collapses the main window down to just a thin title bar, same pattern as
-- Xal's Compendium. Exists mainly so Auto-Show can pop up something
-- unobtrusive instead of the full window taking over the screen at a bad
-- moment - Auto-Show always minimizes on its own (see RefreshList), a
-- manual open (minimap button, slash command) respects whatever state was
-- last left.
function XQC.ApplyMinimizedState()
	if not QTT then return end
	local minimized = XalsQuestCompassDB.minimized

	local fullElements = { QTT.title, QTT.countText, QTT.questArea, QTT.headerDivider, QTT.chevronBtn }
	for _, el in ipairs(fullElements) do
		if el then
			if minimized then el:Hide() else el:Show() end
		end
	end

	local SAFE_MARGIN = XQC.BrandStyle.SAFE_MARGIN
	if minimized then
		QTT.minimizedLabel:Show()
		QTT.minimizeBtn:SetLabel("+", GOLD)
		-- The compact bar has no room for a top-anchored button with a full
		-- top+bottom buffer both - vertically centered instead, same small
		-- footprint, no border-crowding.
		QTT.closeBtn:ClearAllPoints()
		PixelUtil.SetPoint(QTT.closeBtn, "RIGHT", QTT, "RIGHT", -SAFE_MARGIN, 0)
		QTT.minimizeBtn:ClearAllPoints()
		PixelUtil.SetPoint(QTT.minimizeBtn, "RIGHT", QTT.closeBtn, "LEFT", -10, 0)
		QTT:SetHeight(MINIMIZED_HEIGHT)
	else
		QTT.minimizedLabel:Hide()
		QTT.minimizeBtn:SetLabel("-", GOLD)
		QTT.closeBtn:ClearAllPoints()
		PixelUtil.SetPoint(QTT.closeBtn, "TOPRIGHT", QTT, "TOPRIGHT", -SAFE_MARGIN, -SAFE_MARGIN)
		QTT.minimizeBtn:ClearAllPoints()
		PixelUtil.SetPoint(QTT.minimizeBtn, "TOPRIGHT", QTT.closeBtn, "TOPLEFT", -10, 0)
	end
end

function XQC.ToggleMinimized()
	XalsQuestCompassDB.minimized = not XalsQuestCompassDB.minimized
	XQC.ApplyMinimizedState()
	if not XalsQuestCompassDB.minimized then
		RefreshList()
	end
end

-------------------------------------------------
-- Refresh
-------------------------------------------------

function RefreshList()
	-- questArea is one of the last elements built in CreateMainFrame,
	-- so checking for it confirms the window actually finished
	-- constructing -- guards against any code path that fires this
	-- mid-build (e.g. a size-recalculation triggered by SetBackdrop).
	if not QTT or not QTT.questArea then return end

	if UpdateRouteFooter then UpdateRouteFooter() end

	local quests = GetTurnInQuests()

	-- Auto-show if a new quest became ready in the current zone (or
	-- anywhere, if the "current zone only" filter is off) while the
	-- window was closed. Uses the same zone-filtered list the window
	-- itself displays, so the alert can never fire over a quest the
	-- window wouldn't actually show.
	if XalsQuestCompassDB.readySound and #quests > lastReadyCount then
		pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master")
	end
	if XalsQuestCompassDB.autoShow and (#quests > lastReadyCount) and not QTT:IsShown() then
		-- Auto-Show always minimizes on its own, regardless of whatever
		-- state was last left in - the whole point is popping up something
		-- unobtrusive instead of the full window taking over at a random
		-- moment. A manual open (minimap button, slash command) is
		-- unaffected by this and just respects whatever's already set.
		XalsQuestCompassDB.minimized = true
		QTT:Show()
		XQC.ApplyMinimizedState()
	end

	-- Optionally auto-navigate to the nearest one when the set of ready
	-- quests changes and nothing is currently being navigated to.
	if XalsQuestCompassDB.autoNavigateNearest and #quests > 0 and (#quests ~= lastReadyCount) then
		if not currentNavQuestID then
			NavigateToQuest(quests[1].questID, quests[1].title)
		end
	end

	-- New quests re-sort by distance every refresh, so clamp the display
	-- cursor back onto the list instead of carrying over a stale index.
	if #quests ~= lastReadyCount then
		currentDisplayIndex = 1
	end
	lastReadyCount = #quests

	if not QTT:IsShown() then return end

	if XalsQuestCompassDB.minimized then
		QTT.minimizedLabel:SetText(
			string.format("%d quest%s ready to turn in", #quests, (#quests == 1) and "" or "s")
		)
		return
	end

	-- Fade When Empty: window goes fully invisible and click-through when
	-- there's nothing ready, snapping back the instant a quest becomes
	-- ready - not just dimmed, genuinely gone, per explicit request.
	-- EnableMouse(false) matters here too: SetAlpha(0) alone still leaves
	-- an invisible clickable dead zone over that part of the screen.
	if XalsQuestCompassDB.fadeWhenEmpty and #quests == 0 then
		QTT:SetAlpha(0)
		QTT:EnableMouse(false)
	else
		QTT:SetAlpha(1)
		QTT:EnableMouse(true)
	end

	QTT.noQuestsText:SetShown(#quests == 0)

	if #quests == 0 then
		QTT.countText:SetText("")
		if rows[1] then rows[1]:Hide() end
		QTT:SetHeight(QUEST_AREA_TOP + 70 + QUEST_AREA_BOTTOM)
		return
	end

	if currentDisplayIndex > #quests then currentDisplayIndex = #quests end
	if currentDisplayIndex < 1 then currentDisplayIndex = 1 end

	-- Merged "1 / 5 ready to turn in" line, with a dimmer scroll hint
	-- tacked on only when there's actually something else to scroll to.
	local headerText = string.format("%d / %d ready to turn in", currentDisplayIndex, #quests)
	if #quests > 1 then
		headerText = headerText .. "  |cffaaaaaa(scroll to browse)|r"
	end
	QTT.countText:SetText(headerText)

	local rowWidth = GetRowWidth()
	local row = rows[1]
	if not row then
		row = CreateRow(QTT.questArea, 1)
		row:SetScript("OnMouseWheel", function(self, delta)
			if delta < 0 then
				currentDisplayIndex = currentDisplayIndex + 1
			else
				currentDisplayIndex = currentDisplayIndex - 1
			end
			RefreshList()
		end)
		rows[1] = row
	end
	row:SetWidth(rowWidth)
	local rowHeight = UpdateRow(row, quests[currentDisplayIndex])
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 0, 0)

	-- Window hugs its content - one quest is a fixed, small shape, so there's
	-- no reason to leave it sized for a scrolling list that no longer exists.
	QTT:SetHeight(QUEST_AREA_TOP + rowHeight + QUEST_AREA_BOTTOM)
end

-- Keeps existing rows and the scroll child in sync with the window's
-- current width while the user is actively dragging the resize handle
-- (word-wrapped titles need a full reflow when the width changes, not
-- just a width update, so this just re-runs the layout).
local function OnWindowResized()
	RefreshList()
end

-------------------------------------------------
-- Route planning ("Route All")
-------------------------------------------------
-- Computes an ordered, multi-stop route through every ready-to-turn-in quest
-- (across all zones, ignoring the "This Zone Only" filter - that's the whole
-- point of this feature) and walks the player through it stop by stop.
--
-- Quests are converted to "world" points via C_Map.GetWorldPosFromMapPos,
-- which returns a per-continent yard-space position and is present and
-- unrestricted on Retail, MoP Classic, and Classic Era alike - so this
-- doesn't need HereBeDragons or any other optional library the way Xal's
-- Xpedited Routes' gathering routes do (that addon's routes are actually
-- single-zone only; HereBeDragons there is just a more accurate same-zone
-- distance formula, not cross-zone stitching). On Classic,
-- GetQuestWaypointCoords only has coordinates for quests in the player's
-- CURRENT zone (see its comment above), so Route All there covers what's
-- locatable right now; clicking it again after traveling picks up newly-
-- locatable quests. Retail covers every quest regardless of zone or
-- continent in one pass.

local STOP_CLUSTER_YARDS = 20 -- quests within this distance of each other are treated as one stop
local CROSS_CONTINENT_DISTANCE = 1e9 -- world positions from different continents aren't directly comparable; this just keeps greedy ordering from jumping continents until it has to
local MAX_TWO_OPT_STOPS = 60
local MAX_TWO_OPT_PASSES = 8

local activeRoute = nil -- { stops = { {continentID, wx, wy, quests = {{questID,title},...}}, ... }, cursor = 1 }

-- Converts a quest's normalized map position into a comparable world-space
-- point (continentID + yards), pcall-guarded since GetWorldPosFromMapPos is
-- documented as able to return nothing for a handful of edge-case zones.
local function GetWorldPoint(uiMapID, x, y)
	if not uiMapID or not x or not y then return nil end
	local ok, continentID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(x, y))
	if not ok or not continentID or not worldPos then return nil end
	local wx, wy = worldPos:GetXY()
	if not wx then return nil end
	return continentID, wx, wy
end

local function GetPlayerWorldPoint()
	local uiMapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not uiMapID then return nil end
	local pos = C_Map.GetPlayerMapPosition(uiMapID, "player")
	if not pos then return nil end
	local px, py = pos:GetXY()
	if not px then return nil end
	return GetWorldPoint(uiMapID, px, py)
end

local function WorldDistance(a, b)
	if not a or not b or a.continentID ~= b.continentID then return CROSS_CONTINENT_DISTANCE end
	local dx, dy = a.wx - b.wx, a.wy - b.wy
	return math.sqrt(dx * dx + dy * dy)
end

-- Same greedy-nearest-then-2-opt shape already proven in Xal's Xpedited
-- Routes' PathPlanner.lua, adapted to work on world-space stops instead of
-- single-zone node coordinates.
local function BuildGreedyOrder(startPoint, stops)
	local pool = {}
	for i, s in ipairs(stops) do pool[i] = s end
	local order = {}
	local at = startPoint
	while #pool > 0 do
		local nearestSlot, nearestDist = 1, math.huge
		for slot, candidate in ipairs(pool) do
			local d = WorldDistance(at, candidate)
			if d < nearestDist then
				nearestDist, nearestSlot = d, slot
			end
		end
		local chosen = table.remove(pool, nearestSlot)
		table.insert(order, chosen)
		at = chosen
	end
	return order
end

local function ImproveWithTwoOpt(startPoint, order)
	local n = #order
	if n < 3 or n > MAX_TWO_OPT_STOPS then return order end

	local function pointAt(index)
		if index == 0 then return startPoint end
		return order[index]
	end

	for pass = 1, MAX_TWO_OPT_PASSES do
		local changed = false
		for i = 1, n - 1 do
			local prev = pointAt(i - 1)
			for j = i + 1, n do
				local nextIndex = j + 1
				if nextIndex <= n then
					local a, b, after = pointAt(i), pointAt(j), pointAt(nextIndex)
					local currentCost = WorldDistance(prev, a) + WorldDistance(b, after)
					local swappedCost = WorldDistance(prev, b) + WorldDistance(a, after)
					if swappedCost < currentCost - 0.01 then
						local lo, hi = i, j
						while lo < hi do
							order[lo], order[hi] = order[hi], order[lo]
							lo, hi = lo + 1, hi - 1
						end
						changed = true
					end
				end
			end
		end
		if not changed then break end
	end
	return order
end

-- Gathers every ready-to-turn-in quest with a resolvable world position, and
-- separates out the ones that don't have one (e.g. no map POI at all) so
-- they can be surfaced separately rather than silently dropped.
local function BuildRouteStops()
	local located, unlocated = {}, {}

	for _, info in ipairs(GetTurnInQuests(true)) do
		local uiMapID, x, y = GetQuestWaypointCoords(info.questID)
		local continentID, wx, wy = uiMapID and GetWorldPoint(uiMapID, x, y)
		if continentID and wx and wy then
			table.insert(located, { questID = info.questID, title = info.title, continentID = continentID, wx = wx, wy = wy })
		else
			table.insert(unlocated, info)
		end
	end

	-- Cluster quests that are close together (same NPC, or a hub of several
	-- quest-givers a few steps apart) into a single stop, so the route
	-- doesn't send the player back and forth between adjacent quest-givers.
	local stops = {}
	for _, q in ipairs(located) do
		local placed = false
		for _, stop in ipairs(stops) do
			if stop.continentID == q.continentID then
				local dx, dy = q.wx - stop.wx, q.wy - stop.wy
				if math.sqrt(dx * dx + dy * dy) <= STOP_CLUSTER_YARDS then
					table.insert(stop.quests, { questID = q.questID, title = q.title })
					placed = true
					break
				end
			end
		end
		if not placed then
			table.insert(stops, {
				continentID = q.continentID, wx = q.wx, wy = q.wy,
				quests = { { questID = q.questID, title = q.title } },
			})
		end
	end

	return stops, unlocated
end

local function CurrentStop()
	if not activeRoute then return nil end
	return activeRoute.stops[activeRoute.cursor]
end

local function QuestIDInCurrentStop(questID)
	local stop = CurrentStop()
	if not stop then return false end
	for _, q in ipairs(stop.quests) do
		if q.questID == questID then return true end
	end
	return false
end

function UpdateRouteFooter()
	if not QTT or not QTT.routeAllBtn then return end
	if activeRoute then
		local stop = CurrentStop()
		local n = stop and #stop.quests or 0
		QTT.routeStatusText:SetText(string.format("Stop %d/%d (%d quest%s)", activeRoute.cursor, #activeRoute.stops, n, n == 1 and "" or "s"))
		QTT.routeStatusText:Show()
		QTT.routeAllBtn:Hide()
		QTT.routeSkipBtn:Show()
		QTT.routeCancelBtn:Show()
	else
		QTT.routeStatusText:Hide()
		QTT.routeSkipBtn:Hide()
		QTT.routeCancelBtn:Hide()
		QTT.routeAllBtn:Show()
	end
end

local function NavigateToCurrentStop()
	local stop = CurrentStop()
	if not stop then return end
	local title = stop.quests[1].title
	if #stop.quests > 1 then
		title = string.format("%s (+%d more)", title, #stop.quests - 1)
	end
	NavigateToQuest(stop.quests[1].questID, title)
end

local function StopRoute(silent)
	if not activeRoute then return end
	activeRoute = nil
	if not silent then
		print("|cff33ff99Xal's Quest Compass:|r Route cancelled.")
	end
	UpdateRouteFooter()
end

local function AdvanceRoute()
	if not activeRoute then return end
	activeRoute.cursor = activeRoute.cursor + 1
	if activeRoute.cursor > #activeRoute.stops then
		print("|cff33ff99Xal's Quest Compass:|r Route complete!")
		StopRoute(true)
		return
	end
	print(string.format("|cff33ff99Xal's Quest Compass:|r Next stop: |cffffff00%d/%d|r", activeRoute.cursor, #activeRoute.stops))
	NavigateToCurrentStop()
	UpdateRouteFooter()
end

local function SkipStop()
	if not activeRoute then return end
	print("|cff33ff99Xal's Quest Compass:|r Stop skipped.")
	AdvanceRoute()
end

-- Drops a quest from the route wherever it currently sits (normally the
-- current stop) without treating it as a success - used both for a
-- confirmed turn-in (see HandleQuestTurnedIn) and for a quest just
-- disappearing some other way (abandoned, expired, reset). If that empties
-- the current stop, the route advances on its own.
local function RemoveQuestFromRoute(questID)
	if not activeRoute or not questID then return end
	local stop = CurrentStop()
	if not stop then return end
	local removed = false
	for i = #stop.quests, 1, -1 do
		if stop.quests[i].questID == questID then
			table.remove(stop.quests, i)
			removed = true
		end
	end
	if removed then
		if #stop.quests == 0 then
			AdvanceRoute()
		else
			UpdateRouteFooter()
		end
	end
end

-- QUEST_TURNED_IN fires synchronously, before the quest log itself has been
-- rebuilt (it's flagged SynchronousEvent in Blizzard's own API docs), so the
-- actual route-state change is deferred one frame rather than trusting
-- anything about quest-log state inside this handler.
local function HandleQuestTurnedIn(questID)
	if not activeRoute or not questID then return end
	if not QuestIDInCurrentStop(questID) then return end
	C_Timer.After(0, function()
		RemoveQuestFromRoute(questID)
	end)
end

-- Self-heal backstop: if a quest silently left the log some other way (no
-- QUEST_TURNED_IN, no QUEST_REMOVED caught for some reason), this notices on
-- the next general quest-log update and drops it, so the route can never get
-- permanently stuck waiting on a quest that's already gone.
local function ValidateRouteAgainstLog()
	if not activeRoute then return end
	local stop = CurrentStop()
	if not stop then return end

	local stillInLog = {}
	local numEntries = Compat_GetNumEntries()
	for i = 1, numEntries do
		local questID = Compat_GetQuestEntry(i)
		if questID then stillInLog[questID] = true end
	end

	local anyGone = false
	for i = #stop.quests, 1, -1 do
		if not stillInLog[stop.quests[i].questID] then
			table.remove(stop.quests, i)
			anyGone = true
		end
	end
	if anyGone then
		if #stop.quests == 0 then
			AdvanceRoute()
		else
			UpdateRouteFooter()
		end
	end
end

-- When the player interacts with an NPC that turns out to also hold a
-- LATER stop's quest(s), pull those into the current stop so one visit
-- resolves everything that NPC can give right now instead of the route
-- sending the player back a second time. Uses the same GetActiveQuests
-- call already relied on for auto turn-in above.
local function MergeGossipQuestsIntoCurrentStop()
	if not activeRoute then return end
	if not (C_GossipInfo and C_GossipInfo.GetActiveQuests) then return end
	local stop = CurrentStop()
	if not stop then return end

	local ok, list = pcall(C_GossipInfo.GetActiveQuests)
	if not ok or not list then return end

	local hereIDs = {}
	for _, q in ipairs(list) do
		if q.questID then hereIDs[q.questID] = true end
	end
	if not next(hereIDs) then return end

	local mergedAny = false
	for laterIdx = activeRoute.cursor + 1, #activeRoute.stops do
		local laterStop = activeRoute.stops[laterIdx]
		for i = #laterStop.quests, 1, -1 do
			if hereIDs[laterStop.quests[i].questID] then
				table.insert(stop.quests, laterStop.quests[i])
				table.remove(laterStop.quests, i)
				mergedAny = true
			end
		end
	end
	if mergedAny then
		for laterIdx = #activeRoute.stops, activeRoute.cursor + 1, -1 do
			if #activeRoute.stops[laterIdx].quests == 0 then
				table.remove(activeRoute.stops, laterIdx)
			end
		end
		UpdateRouteFooter()
	end
end

local function StartRoute()
	local stops, unlocated = BuildRouteStops()
	if #stops == 0 then
		if #unlocated > 0 then
			print("|cffff9900Xal's Quest Compass:|r Couldn't find a location for any ready quest right now - use Navigate on individual quests instead.")
		else
			print("|cff33ff99Xal's Quest Compass:|r No quests are ready to turn in.")
		end
		return
	end

	local startPoint = GetPlayerWorldPoint()
	local order = stops
	if startPoint then
		order = BuildGreedyOrder(startPoint, stops)
		order = ImproveWithTwoOpt(startPoint, order)
	end

	activeRoute = { stops = order, cursor = 1 }
	NavigateToCurrentStop()

	local msg = string.format("|cff33ff99Xal's Quest Compass:|r Route started - |cff00ff00%d|r stop%s.", #order, #order == 1 and "" or "s")
	if #unlocated > 0 then
		msg = msg .. string.format(" (%d quest%s couldn't be routed - use Navigate individually.)", #unlocated, #unlocated == 1 and "" or "s")
	end
	print(msg)

	UpdateRouteFooter()
end

-------------------------------------------------
-- Options panel
-------------------------------------------------

-- Settings panel typography standard (confirmed 2026-08-09, applies to every
-- panel in every addon): Blizzard's template default (~10px) is too small
-- against busy WoW terrain. Description/help text bumps to 13px, brighter
-- label text (slider labels, Low/High endpoints, checkbox labels) bumps to
-- 14px. Read the current font via :GetFont() and re-apply at the new size
-- rather than assuming a starting size.
local PANEL_DESC_FONT_SIZE = 15 -- baseline bumped from 13 -> 15, matching the Home page body text
local PANEL_LABEL_FONT_SIZE = 14
-- The left margin for the first element in any card chain (a header or a
-- leading button like Behavior's "Open Window"). NEVER anchor a first
-- element at x=0 - a panel can end up wrapped in a scrollable ScrollFrame
-- (see CreateScrollableSection) at any point, now or later, and x=0 sits
-- exactly flush against that frame's clip edge, silently clipping the left
-- edge off every line of text chained beneath it. This bit Font's Size
-- slider, then Behavior's entire card list, both from the same root cause
-- - a shared named constant instead of a bare "8"/"0" typed by hand at
-- each call site is what actually stops it from recurring a third time.
local CARD_LEFT_MARGIN = 8
local function BumpFont(fs, size)
	local font, _, flags = fs:GetFont()
	fs:SetFont(font, size, flags)
end

local function CreateOptionsPanel()
	local Brand = XQC.BrandStyle
	local panel = CreateFrame("Frame")
	panel.name = "Xal's Quest Compass"

	-- Bare content only - NO title/border/background of its own. This exact
	-- frame gets reused in two different contexts (Blizzard's native Settings
	-- canvas, and the standalone window's content area below), and each of
	-- those already provides its own chrome - matching Routes' actual
	-- rootPanel, which has no Brand.Title/border either for the same reason.
	-- Giving this panel its own header too just stacked a second title/button
	-- row on top of the standalone window's, overlapping visibly.

	-- Everything scrolls, so settings can never
	-- get cut off no matter how tall this panel grows -- Blizzard's Settings
	-- canvas does NOT auto-scroll custom content on its own, which is exactly
	-- why the Window Scale slider was invisible/unreachable once this panel
	-- grew past the visible area (fixed 2026-08-07).
	local scrollFrame = CreateFrame("ScrollFrame", "XalsQuestCompassOptionsScrollFrame", panel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	-- Right: safe margin PLUS room for the scrollbar itself (~20px), not just
	-- the margin alone. Bottom: was hardcoded to 4px - nowhere close to the
	-- 14px safe margin, so scrolled content could sit flush against/behind
	-- the border instead of clear of it.
	scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(Brand.SAFE_MARGIN + 20), Brand.SAFE_MARGIN)

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetSize(340, 700) -- generously tall; scrolling handles the rest, so this never needs to be exact
	scrollFrame:SetScrollChild(scrollChild)

	-- Right-edge anchor is relative to the actual PANEL, not scrollChild's
	-- fixed 340px width - scrollChild is just a scroll-region placeholder,
	-- the real available width is the panel's (native Settings frame vs a
	-- narrower context can differ). A fixed-width-relative anchor here was
	-- the root cause of text overflowing/misaligning depending on context.
	local function AnchorRight(fs, x)
		fs:SetPoint("RIGHT", panel, "RIGHT", x, 0)
	end

	-- Brand.MakeCheckbox has no built-in .Text region (unlike native
	-- UICheckButtonTemplate), so this centralizes the label-creation
	-- boilerplate that would otherwise get retyped at every checkbox in
	-- this panel. Anchoring is left to the caller (offsets vary per site),
	-- this only builds the checkbox + its label and wires state/toggle.
	local function MakeCheckboxWithLabel(text, isChecked, onToggle)
		local cb = Brand.MakeCheckbox(scrollChild, 22)
		local label = scrollChild:CreateFontString(nil, "OVERLAY")
		label:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", PANEL_LABEL_FONT_SIZE, "")
		label:SetTextColor(0.85, 0.85, 0.85)
		label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
		AnchorRight(label, -30)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(true)
		label:SetText(text)
		cb:SetChecked(isChecked)
		cb.OnToggle = onToggle
		return cb
	end

	-- In-content button (not header chrome - Routes' header is title + close
	-- only) since this panel is reused both natively and in the standalone
	-- window, and only Quest Compass needs this control at all.
	local openBtn = Brand.MakeButton(scrollChild, "Open Window", 140, 24, function()
		if QTT then
			QTT:Show()
		else
			print("|cffff4444Xal's Quest Compass:|r the window didn't initialize. Try /reload.")
		end
	end)
	openBtn:SetPoint("TOPLEFT", 2, 0)
	panel.openBtn = openBtn

	local subtitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -16)
	AnchorRight(subtitle, -30)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetWordWrap(true)
	BumpFont(subtitle, PANEL_DESC_FONT_SIZE)
	subtitle:SetText("Toggle the quest window with /xqc or the minimap button. Click Navigate on any quest for an on-screen arrow.")

	local autoShowCB = MakeCheckboxWithLabel(
		"Automatically open the window when a quest becomes ready to turn in",
		XalsQuestCompassDB.autoShow,
		function(self) XalsQuestCompassDB.autoShow = self:GetChecked() and true or false end)
	autoShowCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -24)
	panel.autoShowCB = autoShowCB

	local autoNavCB = MakeCheckboxWithLabel(
		"Automatically point the arrow at the nearest turn-in when none is selected",
		XalsQuestCompassDB.autoNavigateNearest,
		function(self) XalsQuestCompassDB.autoNavigateNearest = self:GetChecked() and true or false end)
	autoNavCB:SetPoint("TOPLEFT", autoShowCB, "BOTTOMLEFT", 0, -8)
	panel.autoNavCB = autoNavCB

	local zoneOnlyCB = MakeCheckboxWithLabel(
		"Only show quests ready to turn in within my current zone",
		XalsQuestCompassDB.currentZoneOnly,
		function(self)
			XalsQuestCompassDB.currentZoneOnly = self:GetChecked() and true or false
			if QTT and QTT.zoneToggleBtn then QTT.zoneToggleBtn:UpdateText() end
			RefreshList()
		end)
	zoneOnlyCB:SetPoint("TOPLEFT", autoNavCB, "BOTTOMLEFT", 0, -8)
	panel.zoneOnlyCB = zoneOnlyCB

	local minimapCB = MakeCheckboxWithLabel(
		"Show minimap button",
		not (XalsQuestCompassDB.minimap and XalsQuestCompassDB.minimap.hide),
		function(self)
			if XQC.MinimapButton and XQC.MinimapButton.SetShown then
				XQC.MinimapButton:SetShown(self:GetChecked())
			end
		end)
	minimapCB:SetPoint("TOPLEFT", zoneOnlyCB, "BOTTOMLEFT", 0, -8)
	panel.minimapCB = minimapCB

	local fadeCB = MakeCheckboxWithLabel(
		"Fade window when nothing's ready to turn in",
		XalsQuestCompassDB.fadeWhenEmpty,
		function(self)
			XalsQuestCompassDB.fadeWhenEmpty = self:GetChecked() and true or false
			RefreshList()
		end)
	fadeCB:SetPoint("TOPLEFT", minimapCB, "BOTTOMLEFT", 0, -8)
	panel.fadeCB = fadeCB

	-- Automation section
	local automationTitle = Brand.FS(scrollChild, "Automation", "Fonts\\FRIZQT__.TTF", 16, "",
		Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
	automationTitle:SetPoint("TOPLEFT", minimapCB, "BOTTOMLEFT", 2, -22)
	local automationDivider = CreateDivider(scrollChild)
	automationDivider:SetPoint("TOPLEFT", automationTitle, "BOTTOMLEFT", 0, -6)
	automationDivider:SetPoint("RIGHT", scrollChild, "RIGHT", -2, 0)

	local autoTurnInCB = MakeCheckboxWithLabel(
		"Automatically turn in quests with no reward choice to make",
		XalsQuestCompassDB.autoTurnIn,
		function(self) XalsQuestCompassDB.autoTurnIn = self:GetChecked() and true or false end)
	autoTurnInCB:SetPoint("TOPLEFT", automationTitle, "BOTTOMLEFT", -2, -22)
	panel.autoTurnInCB = autoTurnInCB

	local autoAcceptCB = MakeCheckboxWithLabel(
		"Automatically accept new quests offered by NPCs",
		XalsQuestCompassDB.autoAccept,
		function(self) XalsQuestCompassDB.autoAccept = self:GetChecked() and true or false end)
	autoAcceptCB:SetPoint("TOPLEFT", autoTurnInCB, "BOTTOMLEFT", 0, -8)
	panel.autoAcceptCB = autoAcceptCB

	local automationNote = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	automationNote:SetPoint("TOPLEFT", autoAcceptCB, "BOTTOMLEFT", 24, -4)
	AnchorRight(automationNote, -30)
	automationNote:SetJustifyH("LEFT")
	automationNote:SetWordWrap(true)
	BumpFont(automationNote, PANEL_DESC_FONT_SIZE)
	automationNote:SetText("Skips quests with more than one reward to choose from, quests that cost money to turn in, and a few quest types known to behave oddly (escort, item-start, PvP-flagged) - those still open normally so you can handle them yourself. Hold Shift to pause automation at any time.")

	local readySoundCB = MakeCheckboxWithLabel(
		"Play a sound when a quest becomes ready to turn in",
		XalsQuestCompassDB.readySound,
		function(self) XalsQuestCompassDB.readySound = self:GetChecked() and true or false end)
	readySoundCB:SetPoint("TOPLEFT", automationNote, "BOTTOMLEFT", -24, -10)
	panel.readySoundCB = readySoundCB

	-- Appearance section
	local appearanceTitle = Brand.FS(scrollChild, "Appearance", "Fonts\\FRIZQT__.TTF", 16, "",
		Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
	appearanceTitle:SetPoint("TOPLEFT", readySoundCB, "BOTTOMLEFT", 2, -22)
	local appearanceDivider = CreateDivider(scrollChild)
	appearanceDivider:SetPoint("TOPLEFT", appearanceTitle, "BOTTOMLEFT", 0, -6)
	appearanceDivider:SetPoint("RIGHT", scrollChild, "RIGHT", -2, 0)

	local fontLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fontLabel:SetPoint("TOPLEFT", appearanceTitle, "BOTTOMLEFT", 0, -22)
	BumpFont(fontLabel, PANEL_LABEL_FONT_SIZE)
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
	BumpFont(outlineLabel, PANEL_LABEL_FONT_SIZE)
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
	BumpFont(_G[sizeSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
	BumpFont(_G[sizeSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
	_G[sizeSlider:GetName() .. "Low"]:SetText("10")
	_G[sizeSlider:GetName() .. "High"]:SetText("22")
	-- Own FontString for the live value, NOT the template's built-in "Text"
	-- region - that region did not reliably render here (stayed invisible
	-- across two attempts at repositioning it), and OptionsSliderTemplate's
	-- internals have a documented history of shifting/being altered across
	-- WoW versions. A FontString this code creates and owns directly is
	-- guaranteed to render regardless of what the template does internally.
	local sizeValueText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sizeValueText:SetPoint("BOTTOM", sizeSlider, "TOP", 0, 4)
	BumpFont(sizeValueText, PANEL_LABEL_FONT_SIZE)
	sizeValueText:SetTextColor(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
	local function UpdateSizeSliderText()
		sizeValueText:SetText("Font Size: " .. (XalsQuestCompassDB.fontSize or 13))
	end
	sizeSlider:SetValue(XalsQuestCompassDB.fontSize or 13)
	UpdateSizeSliderText()
	sizeSlider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value + 0.5)
		XalsQuestCompassDB.fontSize = value
		ApplyFontSettings()
		UpdateSizeSliderText()
	end)
	panel.sizeSlider = sizeSlider
	panel.UpdateSizeSliderText = UpdateSizeSliderText

	local shadowCB = MakeCheckboxWithLabel(
		"Text shadow",
		XalsQuestCompassDB.fontShadow,
		function(self)
			XalsQuestCompassDB.fontShadow = self:GetChecked() and true or false
			ApplyFontSettings()
		end)
	shadowCB:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", -16, -30)
	panel.shadowCB = shadowCB

	local classColorCB = MakeCheckboxWithLabel(
		"Use my class color for quest titles",
		XalsQuestCompassDB.useClassColor,
		function(self)
			XalsQuestCompassDB.useClassColor = self:GetChecked() and true or false
			RefreshList()
		end)
	classColorCB:SetPoint("TOPLEFT", shadowCB, "BOTTOMLEFT", 0, -8)
	panel.classColorCB = classColorCB

	local scaleSlider = CreateFrame("Slider", "XalsQuestCompassScaleSlider", scrollChild, "OptionsSliderTemplate")
	scaleSlider:SetPoint("TOPLEFT", classColorCB, "BOTTOMLEFT", 16, -30)
	scaleSlider:SetMinMaxValues(0.7, 1.5)
	scaleSlider:SetValueStep(0.05)
	scaleSlider:SetObeyStepOnDrag(true)
	scaleSlider:SetWidth(190)
	BumpFont(_G[scaleSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
	BumpFont(_G[scaleSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
	_G[scaleSlider:GetName() .. "Low"]:SetText("0.7")
	_G[scaleSlider:GetName() .. "High"]:SetText("1.5")
	-- Own FontString, not the template's built-in "Text" region - see the
	-- matching comment on sizeSlider above for why.
	local scaleValueText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scaleValueText:SetPoint("BOTTOM", scaleSlider, "TOP", 0, 4)
	BumpFont(scaleValueText, PANEL_LABEL_FONT_SIZE)
	scaleValueText:SetTextColor(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
	local function UpdateScaleSliderText()
		scaleValueText:SetText(string.format("Window Scale: %.2f", XalsQuestCompassDB.windowScale or 1.0))
	end
	scaleSlider:SetValue(XalsQuestCompassDB.windowScale or 1.0)
	UpdateScaleSliderText()
	scaleSlider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value * 20 + 0.5) / 20
		XalsQuestCompassDB.windowScale = value
		ApplyFontSettings()
		UpdateScaleSliderText()
	end)
	panel.scaleSlider = scaleSlider
	panel.UpdateScaleSliderText = UpdateScaleSliderText

	panel:SetScript("OnShow", function()
		-- Blizzard's ScrollFrame does not reset to the top on its own - without
		-- this, reopening the panel can land mid-scroll, making the top few
		-- settings (subtitle, auto-show, auto-navigate, zone-only, minimap
		-- button, the "Automation" header) look like they've vanished when
		-- they're just scrolled out of view above the visible area.
		scrollFrame:SetVerticalScroll(0)
		autoShowCB:SetChecked(XalsQuestCompassDB.autoShow)
		autoNavCB:SetChecked(XalsQuestCompassDB.autoNavigateNearest)
		zoneOnlyCB:SetChecked(XalsQuestCompassDB.currentZoneOnly)
		minimapCB:SetChecked(not (XalsQuestCompassDB.minimap and XalsQuestCompassDB.minimap.hide))
		autoTurnInCB:SetChecked(XalsQuestCompassDB.autoTurnIn)
		autoAcceptCB:SetChecked(XalsQuestCompassDB.autoAccept)
		readySoundCB:SetChecked(XalsQuestCompassDB.readySound)
		shadowCB:SetChecked(XalsQuestCompassDB.fontShadow)
		classColorCB:SetChecked(XalsQuestCompassDB.useClassColor)
		sizeSlider:SetValue(XalsQuestCompassDB.fontSize or 13)
		scaleSlider:SetValue(XalsQuestCompassDB.windowScale or 1.0)
		UpdateSizeSliderText()
		UpdateScaleSliderText()
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

--------------------------------------------------------------------------------
-- Standalone floating window: the PRIMARY way into settings now, matching
-- Xal's Xpedited Routes' SettingsPanel.lua BuildStandaloneWindow exactly
-- (the confirmed reference - branded background/border/centered title/close
-- button/full-width divider, UISpecialFrames so Escape closes it). The
-- native Esc -> Options list entry stays too, as a secondary path - same
-- split as every other addon per project_addon_settings_pattern.
--
-- This REUSES the exact same `optionsPanel` frame built above by reparenting
-- it into this window's content area, rather than rebuilding its controls a
-- second time. Every widget inside it is positioned relative to that panel's
-- OWN frame, so moving the frame doesn't disturb anything inside it. When the
-- player later opens the native Esc -> Options entry, Blizzard's Settings
-- system re-parents the panel back into its own canvas automatically the way
-- it always does for any RegisterCanvasLayoutCategory panel - nothing here
-- needs to undo the reparenting itself.
--------------------------------------------------------------------------------
local standaloneFrame

local function BuildStandaloneOptionsWindow()
	if standaloneFrame then return standaloneFrame end
	local Brand = XQC.BrandStyle
	-- Width = left margin(14) + sidebar(132) + gap-to-divider(10) +
	-- divider(2) + gap-to-content(12) + content(540) + right margin(14).
	-- Widened from 480 to 540 (2026-08-11) - the tight fit was forcing
	-- individual widgets (the Font Size slider's Low label) right up against
	-- the scroll area's clip edge instead of leaving real breathing room.
	local FW, FH = 724, 820

	local f = CreateFrame("Frame", "XalsQuestCompassStandaloneOptions", UIParent, "BackdropTemplate")
	tinsert(UISpecialFrames, "XalsQuestCompassStandaloneOptions")
	f:SetSize(FW, FH)
	-- Default offset from true dead-center, not (0,0) - a plain CENTER
	-- default is exactly where other addons' windows tend to land too
	-- (confirmed 2026-08-13: this window was caught stacked directly on top
	-- of Roster Roundup's Guild Roster). Only used the FIRST time this opens
	-- though - once dragged, its real position is remembered permanently
	-- (XalsQuestCompassDB.optionsWindowPoint), same as every mature addon's
	-- window (ElvUI, Zygor, etc.) - a collision can only ever happen once
	-- before the player moves it and it's fixed for good.
	-- This window is 724x820 - too large for a small offset from CENTER to
	-- meaningfully separate it from another addon's similarly large window
	-- (confirmed 2026-08-13: it was still overlapping Craft Courier's
	-- 840x700 Options canvas with only ~170px of offset between them).
	-- Anchors to a screen CORNER instead - genuine separation regardless of
	-- window size, not offset math these dimensions defeat.
	local savedPoint = XalsQuestCompassDB.optionsWindowPoint
	if savedPoint then
		f:SetPoint(savedPoint[1], UIParent, savedPoint[2], savedPoint[3], savedPoint[4])
	else
		f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -40)
	end
	f:SetFrameStrata("DIALOG")
	-- Raises itself above other frames sharing this strata the instant it's
	-- shown/clicked - the real, standard Blizzard API every established
	-- addon (confirmed against Zygor's own windows) uses for this.
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		XalsQuestCompassDB.optionsWindowPoint = { point, relPoint, x, y }
	end)
	f:SetClampedToScreen(true)

	Brand.ApplyBackground(f)
	Brand.ApplyBackgroundImage(f)
	Brand.DrawBorder(f)
	-- Roughly centered between the top border (~8px) and the header divider
	-- (now 80px) - best estimate accounting for the title+shadow's visual
	-- height, not a precise measurement, may need a small nudge once seen live.
	Brand.Title(f, "Xal's Quest Compass", 40, "TOP", f, "TOP", 0, -20)

	-- Header is title + close button ONLY, matching Routes' actual standalone
	-- window exactly - no other controls up there. Plain text link, not a
	-- bordered X - text-link buttons are the addon-wide default now (see
	-- Xal's Reins), bordered stays only for the rare single prominent CTA.
	local closeBtn = Brand.MakeLinkButton(f)
	closeBtn:SetLabel("Close", GOLD)
	closeBtn:SetScript("OnClick", function() f:Hide() end)
	PixelUtil.SetPoint(closeBtn, "TOPRIGHT", f, "TOPRIGHT", -Brand.SAFE_MARGIN, -Brand.SAFE_MARGIN)

	-- Pushed down from 66 to 80 - the bigger title + stronger shadow (32pt,
	-- 4px offset) was reaching far enough down to visually cut into the
	-- divider at the old position.
	Brand.DrawDivider(f, Brand.SAFE_MARGIN, 80, FW - Brand.SAFE_MARGIN * 2)

	-- STEP 2: sidebar shell - section buttons + vertical divider, matching
	-- Routes' sidebar exactly (132px sidebar, 116px buttons, 8px side pad,
	-- -4 gap between buttons, vDivider 10px off the sidebar's right edge).
	-- Buttons don't do anything yet - content comes one section at a time.
	-- Back to sitting right below the header divider (80) - this frame's
	-- own position also defines vDivider's top via the anchor below, so
	-- moving IT down was what shortened/dragged the vertical divider last
	-- time. The actual button buffer is added on the buttons themselves
	-- further down, not here.
	local sidebar = CreateFrame("Frame", nil, f)
	sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", Brand.SAFE_MARGIN, -88)
	sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", Brand.SAFE_MARGIN, Brand.SAFE_MARGIN)
	sidebar:SetWidth(132)

	local vDivider = f:CreateTexture(nil, "ARTWORK")
	vDivider:SetWidth(Brand.LINE_THICKNESS)
	vDivider:SetColorTexture(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1)
	vDivider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
	vDivider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 10, 0)

	-- Bottom leaves extra clearance above SAFE_MARGIN so content never
	-- collides with the footer version line anchored at the true bottom.
	local contentArea = CreateFrame("Frame", nil, f)
	contentArea:SetPoint("TOPLEFT", vDivider, "TOPRIGHT", 26, 0)
	-- This is a stopgap, not a real fix - content that's taller than the
	-- panel will still run into the footer regardless of this margin. The
	-- real fix is the scroll frame noted as future work (task: draggable-
	-- thumb scrollbar, not Blizzard's arrow-button style).
	contentArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Brand.SAFE_MARGIN, Brand.SAFE_MARGIN + 36)

	----------------------------------------------------------------
	-- Home panel - icon-anchored hero moment into detail, not a flat
	-- stacked paragraph block. Icon centered at top, a bold pull-quote
	-- lead line, a short decorative rule, then centered body copy with
	-- key phrases highlighted in accent gold inline.
	----------------------------------------------------------------
	local ACCENT_HEX = string.format("ff%02x%02x%02x",
		Brand.ACCENT[1] * 255, Brand.ACCENT[2] * 255, Brand.ACCENT[3] * 255)
	local function Highlight(text) return "|c" .. ACCENT_HEX .. text .. "|r" end
	-- WoW's own epic-item purple - a one-off accent just for Jo's name in the
	-- dedication, not a general brand color.
	local function PurpleHighlight(text) return "|cffa335ee" .. text .. "|r" end

	local homePanel = CreateFrame("Frame", nil, contentArea)
	homePanel:SetAllPoints(contentArea)

	local BODY_WIDTH = 360 -- narrower than the full content area, centered

	local homeIcon = homePanel:CreateTexture(nil, "ARTWORK")
	homeIcon:SetSize(144, 144)
	homeIcon:SetPoint("TOP", homePanel, "TOP", 0, 0)
	homeIcon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Icon.png")
	homeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local homeLead = Brand.FS(homePanel, "Thanks for using Xal's Quest Compass.", "Fonts\\FRIZQT__.TTF", 26, "",
		Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
	homeLead:SetPoint("TOP", homeIcon, "BOTTOM", 0, -14)
	homeLead:SetWidth(BODY_WIDTH)
	homeLead:SetJustifyH("CENTER")
	homeLead:SetWordWrap(true)

	local homeRule = Brand.T(homePanel, 0, 0, 60, Brand.LINE_THICKNESS,
		Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1)
	homeRule:ClearAllPoints()
	homeRule:SetPoint("TOP", homeLead, "BOTTOM", 0, -14)

	local homeBody1 = Brand.FS(homePanel,
		"Quests pile up complete in your log and it's easy to lose track of which ones are actually ready to hand in. I built this addon to fix exactly that - a clean list of what's ready, sorted by distance, with one click to "
			.. Highlight("navigate") .. " and one click to " .. Highlight("track") .. ".",
		"Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", 15, "", 0.85, 0.85, 0.85)
	homeBody1:SetPoint("TOP", homeRule, "BOTTOM", 0, -18)
	homeBody1:SetWidth(BODY_WIDTH)
	homeBody1:SetJustifyH("CENTER")
	homeBody1:SetWordWrap(true)

	local homeBody2 = Brand.FS(homePanel,
		Highlight("Route All") .. " takes it further: one button plans a route through everything you're ready to turn in and walks you through it, stop by stop.",
		"Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", 15, "", 0.85, 0.85, 0.85)
	homeBody2:SetPoint("TOP", homeBody1, "BOTTOM", 0, -14)
	homeBody2:SetWidth(BODY_WIDTH)
	homeBody2:SetJustifyH("CENTER")
	homeBody2:SetWordWrap(true)

	local homeBody3 = Brand.FS(homePanel,
		"Everything else in this window is where you make it yours.",
		"Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", 15, "", 0.85, 0.85, 0.85)
	homeBody3:SetPoint("TOP", homeBody2, "BOTTOM", 0, -14)
	homeBody3:SetWidth(BODY_WIDTH)
	homeBody3:SetJustifyH("CENTER")
	homeBody3:SetWordWrap(true)

	-- Dropped to the bottom of the panel, separate from the body-paragraph
	-- chain above, and styled to stand out (accent gold, not the flat body
	-- gray) so it reads as a distinct, noticeable callout, not just another
	-- paragraph in the stack.
	local homeDedication = Brand.FS(homePanel,
		"This one's for " .. PurpleHighlight('"Jo"')
			.. " \194\183 my go-to traveling companion, dungeons and everything else. \"Oops, dang it, didn't turn that in\" one too many times, so I built this to help you out in-game the way you make my adventuring a whole lot more pleasant.\nHere you go, friend.",
		"Fonts\\FRIZQT__.TTF", 13, "", Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
	homeDedication:SetPoint("BOTTOM", homePanel, "BOTTOM", 0, 22)
	homeDedication:SetWidth(BODY_WIDTH)
	homeDedication:SetJustifyH("CENTER")
	homeDedication:SetWordWrap(true)

	----------------------------------------------------------------
	-- Behavior panel - each setting is its own card: Morpheus header, a
	-- divider under it, a brief description, then the checkbox line. Not a
	-- flat checkbox-plus-long-label list.
	----------------------------------------------------------------
	local behaviorPanel = CreateFrame("Frame", nil, contentArea)
	behaviorPanel:SetAllPoints(contentArea)
	behaviorPanel:Hide()

	-- Shared card head (header + shadow, divider, description) - the part
	-- that's identical no matter what kind of control the card ends with.
	-- Returns the description FontString so the caller anchors whatever
	-- control fits (checkbox, dropdown, slider) below it.
	local function AddCardHeader(parent, anchorTo, gap, name, description)
		-- Shadow layer first (same duplicate-offset technique Brand.Title
		-- uses), then the real header on top - left-justified, confirmed
		-- 2026-08-11 after an A/B test against centered.
		local headerShadow = Brand.FS(parent, name, "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\CustomFont.ttf", 24, "OUTLINE", 0, 0, 0)
		local header = Brand.FS(parent, name, "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\CustomFont.ttf", 24, "OUTLINE",
			Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
		if anchorTo then
			header:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, gap)
		else
			-- gap doubles as the top-of-panel buffer here (Behavior's first
			-- card gets this for free via openWindowBtn sitting above it;
			-- a panel with no leading button needs it passed explicitly).
			header:SetPoint("TOPLEFT", parent, "TOPLEFT", CARD_LEFT_MARGIN, gap)
		end
		headerShadow:SetPoint("TOPLEFT", header, "TOPLEFT", 4, -4)

		local divider = CreateDivider(parent)
		divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
		divider:SetPoint("RIGHT", parent, "RIGHT", -20, 0)

		local desc = Brand.FS(parent, description, "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", PANEL_DESC_FONT_SIZE, "", 0.85, 0.85, 0.85)
		desc:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -16)
		desc:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
		desc:SetJustifyH("LEFT")
		desc:SetWordWrap(true)

		return desc
	end

	-- Checkbox-ending card (Behavior/Automation) - built on AddCardHeader.
	-- Returns {checkbox, bottomAnchor} so the caller can chain the next
	-- card off bottomAnchor.
	local function AddSettingCard(parent, anchorTo, gap, name, description, isChecked, onClick)
		local desc = AddCardHeader(parent, anchorTo, gap, name, description)

		local cb = Brand.MakeCheckbox(parent, 22)
		cb:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -12)
		local label = parent:CreateFontString(nil, "OVERLAY")
		label:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", PANEL_LABEL_FONT_SIZE, "")
		label:SetTextColor(0.95, 0.60, 0.10)
		label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
		label:SetText("Enabled")
		cb:SetChecked(isChecked)
		cb.OnToggle = onClick

		return cb, cb
	end

	-- Wraps a content-building region in a scrollable area with a custom
	-- thin scrollbar in the addon's own flat brand style - a native Slider
	-- drives the actual scroll position (reliable drag physics for free),
	-- restyled to a thin accent-gold thumb instead of Blizzard's default
	-- slider art. NOT Blizzard's default arrow-button scrollbar (explicitly
	-- disliked) and NOT an attempt to reuse the character-select screen's
	-- scrollbar, which is rendered by the separate pre-login Glue UI and
	-- isn't reachable from an in-game addon at all. Auto-hides when content
	-- fits without scrolling. Returns the scrollChild to build content into,
	-- and an UpdateScrollRange() function to call once content is built (and
	-- sized) so the scrollbar knows whether it's actually needed. Defined
	-- here (before ANY panel is built) so every section can use it, not
	-- just whichever one happened to need it first - a card added later to
	-- a panel that was never wrapped in this is exactly what overflowed
	-- Behavior's footer buffer (caught 2026-08-11).
	local function CreateScrollableSection(parent)
		local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
		scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
		scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 0)

		-- Derived from the panel's own real width (minus the 18px just
		-- reserved for the scrollbar track above), not a hardcoded guess -
		-- a hardcoded content width previously drifted wider than the actual
		-- viewport (540 vs. the real ~508px available), which silently
		-- clipped anything word-wrapped near the right edge (caught
		-- 2026-08-11: "Text Shadow"'s description cut "swatch" mid-word).
		local contentWidth = parent:GetWidth() - 18

		local scrollChild = CreateFrame("Frame", nil, scrollFrame)
		scrollChild:SetSize(contentWidth, 1)
		scrollFrame:SetScrollChild(scrollChild)

		local track = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		track:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
		track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
		track:SetWidth(8)
		track:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
		track:SetBackdropColor(1, 1, 1, 0.08)
		track:Hide()

		local thumbSlider = CreateFrame("Slider", nil, track)
		thumbSlider:SetOrientation("VERTICAL")
		thumbSlider:SetPoint("TOP", track, "TOP", 0, 0)
		thumbSlider:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
		thumbSlider:SetWidth(8)
		thumbSlider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
		local thumbTex = thumbSlider:GetThumbTexture()
		thumbTex:SetVertexColor(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1)
		thumbTex:SetWidth(8)

		local suppressCallback = false
		thumbSlider:SetScript("OnValueChanged", function(self, value)
			if suppressCallback then return end
			scrollFrame:SetVerticalScroll(value)
		end)

		scrollFrame:EnableMouseWheel(true)
		scrollFrame:SetScript("OnMouseWheel", function(self, delta)
			thumbSlider:SetValue(thumbSlider:GetValue() - delta * 40)
		end)

		local function UpdateScrollRange()
			local visibleHeight = scrollFrame:GetHeight()
			local contentHeight = scrollChild:GetHeight()
			local maxScroll = math.max(0, contentHeight - visibleHeight)
			suppressCallback = true
			thumbSlider:SetMinMaxValues(0, maxScroll)
			thumbSlider:SetValue(0)
			suppressCallback = false
			scrollFrame:SetVerticalScroll(0)
			if maxScroll > 0 then
				track:Show()
				local ratio = math.min(1, visibleHeight / contentHeight)
				thumbTex:SetHeight(math.max(20, visibleHeight * ratio))
			else
				track:Hide()
			end
		end

		return scrollChild, UpdateScrollRange
	end

	-- Behavior now has 5 cards - outgrew the visible area the moment Fade
	-- When Empty was added, so it's wrapped in the same scrollable pattern
	-- Font already uses (caught live 2026-08-11: the 5th card ran straight
	-- into the footer buffer with no scrollbar to catch it).
	local behaviorScrollChild, UpdateBehaviorScroll = CreateScrollableSection(behaviorPanel)

	local openWindowBtn = Brand.MakeButton(behaviorScrollChild, "Open Window", 140, 24, function()
		if QTT then
			QTT:Show()
		else
			print("|cffff4444Xal's Quest Compass:|r the window didn't initialize. Try /reload.")
		end
	end)
	-- Every card below chains its x-position off this button, so it needs
	-- the same CARD_LEFT_MARGIN baseline AddCardHeader uses - leaving it at
	-- x=0 cut the left edge off every single card's text underneath it
	-- (caught 2026-08-11 via screenshot: "pens the window..." missing its
	-- leading "O", etc.).
	openWindowBtn:SetPoint("TOPLEFT", behaviorScrollChild, "TOPLEFT", CARD_LEFT_MARGIN, -32)

	local CARD_GAP = -28

	local autoShowCB, anchor1 = AddSettingCard(behaviorScrollChild, openWindowBtn, CARD_GAP,
		"Auto-Show", "Opens the window automatically the moment a quest becomes ready.",
		XalsQuestCompassDB.autoShow,
		function(self) XalsQuestCompassDB.autoShow = self:GetChecked() and true or false end)

	local autoNavCB, anchor2 = AddSettingCard(behaviorScrollChild, anchor1, CARD_GAP,
		"Auto-Navigate", "Points the arrow at the nearest turn-in when nothing else is selected.",
		XalsQuestCompassDB.autoNavigateNearest,
		function(self) XalsQuestCompassDB.autoNavigateNearest = self:GetChecked() and true or false end)

	local zoneOnlyCB, anchor3 = AddSettingCard(behaviorScrollChild, anchor2, CARD_GAP,
		"Zone Filter", "Only shows quests ready to turn in within your current zone.",
		XalsQuestCompassDB.currentZoneOnly,
		function(self)
			XalsQuestCompassDB.currentZoneOnly = self:GetChecked() and true or false
			if QTT and QTT.zoneToggleBtn then QTT.zoneToggleBtn:UpdateText() end
			RefreshList()
		end)

	local minimapCB, anchor4 = AddSettingCard(behaviorScrollChild, anchor3, CARD_GAP,
		"Minimap Button", "Shows the clickable icon on your minimap.",
		not (XalsQuestCompassDB.minimap and XalsQuestCompassDB.minimap.hide),
		function(self)
			if XQC.MinimapButton and XQC.MinimapButton.SetShown then
				XQC.MinimapButton:SetShown(self:GetChecked())
			end
		end)

	local fadeCB, anchor5 = AddSettingCard(behaviorScrollChild, anchor4, CARD_GAP,
		"Fade When Empty", "Makes the window fully invisible and click-through whenever nothing's ready to turn in, instead of sitting there empty. Snaps back the instant a quest becomes ready.",
		XalsQuestCompassDB.fadeWhenEmpty,
		function(self)
			XalsQuestCompassDB.fadeWhenEmpty = self:GetChecked() and true or false
			RefreshList()
		end)

	behaviorPanel:SetScript("OnShow", function()
		autoShowCB:SetChecked(XalsQuestCompassDB.autoShow)
		autoNavCB:SetChecked(XalsQuestCompassDB.autoNavigateNearest)
		zoneOnlyCB:SetChecked(XalsQuestCompassDB.currentZoneOnly)
		minimapCB:SetChecked(not (XalsQuestCompassDB.minimap and XalsQuestCompassDB.minimap.hide))
		fadeCB:SetChecked(XalsQuestCompassDB.fadeWhenEmpty)
		C_Timer.After(0, function()
			local top = behaviorScrollChild:GetTop()
			local bottom = fadeCB:GetBottom()
			if top and bottom then
				behaviorScrollChild:SetHeight(math.max(top - bottom + 24, 1))
			end
			UpdateBehaviorScroll()
		end)
	end)

	----------------------------------------------------------------
	-- Automation panel - every safety guarantee stated explicitly and
	-- completely in each card's own description, not summarized away or
	-- left to a shared footnote, so there's no way to misread what either
	-- toggle will or won't do. Both automation cards independently restate
	-- the Shift-to-pause behavior for the same reason.
	----------------------------------------------------------------
	local automationPanel = CreateFrame("Frame", nil, contentArea)
	automationPanel:SetAllPoints(contentArea)
	automationPanel:Hide()

	local autoTurnInCB, autoTurnInAnchor = AddSettingCard(automationPanel, nil, -32,
		"Auto Turn-In",
		"Completes quests automatically, but only when there's nothing to choose - any quest with more than one reward option, or one that costs you money, is always left for you to finish yourself. Hold Shift at any time to pause it instantly.",
		XalsQuestCompassDB.autoTurnIn,
		function(self) XalsQuestCompassDB.autoTurnIn = self:GetChecked() and true or false end)

	local autoAcceptCB, autoAcceptAnchor = AddSettingCard(automationPanel, autoTurnInAnchor, CARD_GAP,
		"Auto Accept",
		"Accepts new quests from NPCs automatically. Escort, item-start, and PvP-flagged quests are always skipped and left for you, since they need special handling. Hold Shift at any time to pause it instantly.",
		XalsQuestCompassDB.autoAccept,
		function(self) XalsQuestCompassDB.autoAccept = self:GetChecked() and true or false end)

	local readySoundCB, readySoundAnchor = AddSettingCard(automationPanel, autoAcceptAnchor, CARD_GAP,
		"Ready Sound",
		"Plays a short chime the moment a quest becomes ready to turn in.",
		XalsQuestCompassDB.readySound,
		function(self) XalsQuestCompassDB.readySound = self:GetChecked() and true or false end)

	automationPanel:SetScript("OnShow", function()
		autoTurnInCB:SetChecked(XalsQuestCompassDB.autoTurnIn)
		autoAcceptCB:SetChecked(XalsQuestCompassDB.autoAccept)
		readySoundCB:SetChecked(XalsQuestCompassDB.readySound)
	end)

	-- Opens Blizzard's color picker with a live-preview callback. Modern
	-- Retail API confirmed as SetupColorPickerAndShow; falls back to the
	-- older .func/.previousValues pattern (confirmed still correct as of
	-- pre-SetupColorPickerAndShow clients) for Classic, where the modern
	-- method may not exist - same defensive dual-path shape as the rest of
	-- this addon's Retail/Classic compat layer.
	local function OpenColorPicker(r, g, b, onChange)
		if ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:SetupColorPickerAndShow({
				r = r, g = g, b = b,
				swatchFunc = function()
					onChange(ColorPickerFrame:GetColorRGB())
				end,
				cancelFunc = function(previousValues)
					if previousValues then
						onChange(previousValues.r, previousValues.g, previousValues.b)
					end
				end,
			})
		else
			ColorPickerFrame.hasOpacity = false
			ColorPickerFrame.previousValues = { r, g, b }
			ColorPickerFrame.func = function()
				onChange(ColorPickerFrame:GetColorRGB())
			end
			ColorPickerFrame.cancelFunc = function(prev)
				if prev then onChange(prev[1], prev[2], prev[3]) end
			end
			ColorPickerFrame:SetColorRGB(r, g, b)
			ColorPickerFrame:Hide()
			ColorPickerFrame:Show()
		end
	end

	-- A small swatch button showing the current color; click opens the
	-- picker. dbColorTable is the actual {r,g,b} table in XalsQuestCompassDB
	-- - mutated in place so callers don't need to re-fetch it.
	local function AddColorSwatch(parent, anchorTo, dbColorTable, onPicked)
		local swatch = CreateFrame("Button", nil, parent)
		PixelUtil.SetSize(swatch, 24, 24)
		-- Below the checkbox, not beside it - beside it collided with the
		-- checkbox's own label text (labels run well past the checkbox's
		-- narrow clickable box), which was breaking the swatch's border.
		swatch:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 4, -10)

		local fill = swatch:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetColorTexture(dbColorTable[1], dbColorTable[2], dbColorTable[3], 1)

		-- Hand-drawn border, same technique as Brand.MakeButton/Brand.DrawBorder -
		-- SetBackdrop's 1px edgeFile is the same "renders incomplete/asymmetric
		-- at non-integer UI scale" bug already fixed for buttons; this swatch
		-- never got that fix.
		local thick = Brand.LINE_THICKNESS
		local top = swatch:CreateTexture(nil, "ARTWORK")
		PixelUtil.SetPoint(top, "TOPLEFT", swatch, "TOPLEFT", 0, 0)
		PixelUtil.SetPoint(top, "TOPRIGHT", swatch, "TOPRIGHT", 0, 0)
		PixelUtil.SetHeight(top, thick)
		top:SetColorTexture(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1)

		local bottom = swatch:CreateTexture(nil, "ARTWORK")
		PixelUtil.SetPoint(bottom, "BOTTOMLEFT", swatch, "BOTTOMLEFT", 0, 0)
		PixelUtil.SetPoint(bottom, "BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 0, 0)
		PixelUtil.SetHeight(bottom, thick)
		bottom:SetColorTexture(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1)

		local left = swatch:CreateTexture(nil, "ARTWORK")
		PixelUtil.SetPoint(left, "TOPLEFT", swatch, "TOPLEFT", 0, 0)
		PixelUtil.SetPoint(left, "BOTTOMLEFT", swatch, "BOTTOMLEFT", 0, 0)
		PixelUtil.SetWidth(left, thick)
		left:SetColorTexture(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1)

		local right = swatch:CreateTexture(nil, "ARTWORK")
		PixelUtil.SetPoint(right, "TOPRIGHT", swatch, "TOPRIGHT", 0, 0)
		PixelUtil.SetPoint(right, "BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 0, 0)
		PixelUtil.SetWidth(right, thick)
		right:SetColorTexture(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1)

		swatch:SetScript("OnClick", function()
			OpenColorPicker(dbColorTable[1], dbColorTable[2], dbColorTable[3], function(r, g, b)
				dbColorTable[1], dbColorTable[2], dbColorTable[3] = r, g, b
				fill:SetColorTexture(r, g, b, 1)
				if onPicked then onPicked() end
			end)
		end)

		-- The swatch alone doesn't explain itself - a plain colored square
		-- with no label reads as decoration, not a control (caught
		-- 2026-08-13 via screenshot).
		local swatchLabel = parent:CreateFontString(nil, "OVERLAY")
		swatchLabel:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", PANEL_LABEL_FONT_SIZE, "")
		swatchLabel:SetTextColor(0.85, 0.85, 0.85)
		swatchLabel:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
		swatchLabel:SetText("Current color - click to change")

		return swatch
	end

	----------------------------------------------------------------
	-- Font panel - same card head (header/shadow/divider/description) as
	-- the checkbox sections, but the control at the bottom is whatever
	-- actually fits the setting: dropdown, slider, or checkbox.
	----------------------------------------------------------------
	local fontPanel = CreateFrame("Frame", nil, contentArea)
	fontPanel:SetAllPoints(contentArea)
	fontPanel:Hide()

	-- Font has enough cards (5, two with color swatches) to run past the
	-- visible area, so its content is built into a scrollChild instead of
	-- directly into fontPanel. The other sections fit without scrolling for
	-- now and are left as plain frames - this pattern is here for reuse the
	-- moment any of them grow past their own space too.
	local fontScrollChild, UpdateFontScroll = CreateScrollableSection(fontPanel)

	-- Card 1: Font (dropdown)
	local fontDesc = AddCardHeader(fontScrollChild, nil, -32, "Font", "Choose the typeface used throughout the quest window.")
	local fontDropdown = CreateFrame("Frame", "XalsQuestCompassFontDropdown", fontScrollChild, "UIDropDownMenuTemplate")
	fontDropdown:SetPoint("TOPLEFT", fontDesc, "BOTTOMLEFT", 0, -8)
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

	-- Card 2: Font Outline (dropdown)
	local outlineDesc = AddCardHeader(fontScrollChild, fontDropdown, CARD_GAP, "Font Outline", "Choose how the text is outlined, for readability against busy backgrounds.")
	local outlineDropdown = CreateFrame("Frame", "XalsQuestCompassOutlineDropdown", fontScrollChild, "UIDropDownMenuTemplate")
	outlineDropdown:SetPoint("TOPLEFT", outlineDesc, "BOTTOMLEFT", 0, -8)
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

	-- Card 3: Font Size (slider)
	local sizeDesc = AddCardHeader(fontScrollChild, outlineDropdown, CARD_GAP, "Font Size", "Adjust the size of the text used throughout the quest window.")
	local sizeSlider = CreateFrame("Slider", "XalsQuestCompassFontSizeSlider", fontScrollChild, "OptionsSliderTemplate")
	-- OptionsSliderTemplate's own title/value text renders ABOVE the slider's
	-- top edge, not below - the old -16 gap left no room for it, so it sat
	-- directly overlapping the description text above and never actually
	-- appeared (caught 2026-08-11: it was invisible even before this text
	-- became the live "Font Size: 13" readout, back when it was still the
	-- static "Font Size" label).
	sizeSlider:SetPoint("TOPLEFT", sizeDesc, "BOTTOMLEFT", 16, -32)
	sizeSlider:SetMinMaxValues(10, 22)
	sizeSlider:SetValueStep(1)
	sizeSlider:SetObeyStepOnDrag(true)
	sizeSlider:SetWidth(190)
	BumpFont(_G[sizeSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
	BumpFont(_G[sizeSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
	_G[sizeSlider:GetName() .. "Low"]:SetText("10")
	_G[sizeSlider:GetName() .. "High"]:SetText("22")
	-- Own FontString, not the template's built-in "Text" region - that region
	-- never actually rendered here across two attempts at repositioning it,
	-- and OptionsSliderTemplate's internals have a documented history of
	-- shifting/being altered across WoW versions. This one is guaranteed to
	-- show regardless of what the template does internally.
	local sizeValueText = fontScrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sizeValueText:SetPoint("BOTTOM", sizeSlider, "TOP", 0, 4)
	BumpFont(sizeValueText, PANEL_LABEL_FONT_SIZE)
	sizeValueText:SetTextColor(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
	local function UpdateSizeSliderText()
		sizeValueText:SetText("Font Size: " .. (XalsQuestCompassDB.fontSize or 13))
	end
	sizeSlider:SetValue(XalsQuestCompassDB.fontSize or 13)
	UpdateSizeSliderText()
	sizeSlider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value + 0.5)
		XalsQuestCompassDB.fontSize = value
		ApplyFontSettings()
		UpdateSizeSliderText()
	end)

	-- Card 4: Text Shadow (checkbox + color swatch)
	local shadowCB, shadowAnchor = AddSettingCard(fontScrollChild, sizeSlider, -36,
		"Text Shadow", "Adds a subtle drop shadow behind the text for better contrast. Click the swatch to pick a custom shadow color.",
		XalsQuestCompassDB.fontShadow,
		function(self)
			XalsQuestCompassDB.fontShadow = self:GetChecked() and true or false
			ApplyFontSettings()
		end)
	local shadowSwatch = AddColorSwatch(fontScrollChild, shadowCB, XalsQuestCompassDB.shadowColor, ApplyFontSettings)

	-- Card 5: Font Color - a custom color swatch, plus a separate "use
	-- class color instead" checkbox as an override. Anchored off the swatch
	-- (not the checkbox) since the swatch now sits below the checkbox and
	-- is the true bottom of card 4.
	local fontColorDesc = AddCardHeader(fontScrollChild, shadowSwatch, CARD_GAP, "Font Color",
		"Pick a custom color for quest titles, or use your own class color instead.")

	local classColorCB = Brand.MakeCheckbox(fontScrollChild, 22)
	classColorCB:SetPoint("TOPLEFT", fontColorDesc, "BOTTOMLEFT", -2, -12)
	local classColorLabel = fontScrollChild:CreateFontString(nil, "OVERLAY")
	classColorLabel:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", PANEL_LABEL_FONT_SIZE, "")
	classColorLabel:SetTextColor(0.95, 0.60, 0.10)
	classColorLabel:SetPoint("LEFT", classColorCB, "RIGHT", 6, 0)
	classColorLabel:SetText("Use my class color instead")
	classColorCB:SetChecked(XalsQuestCompassDB.useClassColor)
	classColorCB.OnToggle = function(self)
		XalsQuestCompassDB.useClassColor = self:GetChecked() and true or false
		RefreshList()
	end
	local fontColorSwatch = AddColorSwatch(fontScrollChild, classColorCB, XalsQuestCompassDB.customFontColor, RefreshList)

	-- Deferred one frame so GetTop()/GetBottom() reflect real, rendered
	-- positions rather than being measured before layout has actually run -
	-- this is what makes the scrollbar's overflow detection genuinely
	-- accurate instead of a guessed content height.
	fontPanel:SetScript("OnShow", function()
		shadowCB:SetChecked(XalsQuestCompassDB.fontShadow)
		classColorCB:SetChecked(XalsQuestCompassDB.useClassColor)
		sizeSlider:SetValue(XalsQuestCompassDB.fontSize or 13)
		RefreshFontDropdownText()
		RefreshOutlineDropdownText()
		C_Timer.After(0, function()
			local top = fontScrollChild:GetTop()
			local bottom = fontColorSwatch:GetBottom()
			if top and bottom then
				fontScrollChild:SetHeight(math.max(top - bottom + 24, 1))
			end
			UpdateFontScroll()
		end)
	end)

	----------------------------------------------------------------
	-- Display panel - UI Scaling (the "Window Scale" slider, migrated here
	-- from the old flat native-settings panel) plus ElvUI Skinning (an
	-- opt-in runtime toggle - see BrandStyle.lua's Brand.GetElvUISkins).
	-- More cards TBD as they're named.
	----------------------------------------------------------------
	local displayPanel = CreateFrame("Frame", nil, contentArea)
	displayPanel:SetAllPoints(contentArea)
	displayPanel:Hide()

	local scaleDesc = AddCardHeader(displayPanel, nil, -32, "UI Scaling", "Adjust the size of the whole quest window.")
	local scaleSlider = CreateFrame("Slider", "XalsQuestCompassDisplayScaleSlider", displayPanel, "OptionsSliderTemplate")
	scaleSlider:SetPoint("TOPLEFT", scaleDesc, "BOTTOMLEFT", 16, -32)
	scaleSlider:SetMinMaxValues(0.7, 1.5)
	scaleSlider:SetValueStep(0.05)
	scaleSlider:SetObeyStepOnDrag(true)
	scaleSlider:SetWidth(190)
	BumpFont(_G[scaleSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
	BumpFont(_G[scaleSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
	_G[scaleSlider:GetName() .. "Low"]:SetText("0.7")
	_G[scaleSlider:GetName() .. "High"]:SetText("1.5")
	-- Own FontString, not the template's built-in "Text" region - see the
	-- matching comment on the Font Size slider for why.
	local scaleValueText = displayPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scaleValueText:SetPoint("BOTTOM", scaleSlider, "TOP", 0, 4)
	BumpFont(scaleValueText, PANEL_LABEL_FONT_SIZE)
	scaleValueText:SetTextColor(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
	local function UpdateDisplayScaleText()
		scaleValueText:SetText(string.format("Window Scale: %.2f", XalsQuestCompassDB.windowScale or 1.0))
	end
	scaleSlider:SetValue(XalsQuestCompassDB.windowScale or 1.0)
	UpdateDisplayScaleText()
	scaleSlider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value * 20 + 0.5) / 20
		XalsQuestCompassDB.windowScale = value
		ApplyFontSettings()
		UpdateDisplayScaleText()
	end)

	local elvDesc = AddCardHeader(displayPanel, scaleSlider, CARD_GAP, "ElvUI Skinning (Experimental)",
		"If you use ElvUI, the main quest window can defer to ElvUI's own look instead of Xal's default style. Requires ElvUI to be installed. Changes apply after /reload. This is new and not widely tested yet - if something looks off with it on, let Xal know.")
	local elvCB = Brand.MakeCheckbox(displayPanel, 22)
	elvCB:SetPoint("TOPLEFT", elvDesc, "BOTTOMLEFT", -2, -12)
	local elvLabel = displayPanel:CreateFontString(nil, "OVERLAY")
	elvLabel:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", PANEL_LABEL_FONT_SIZE, "")
	elvLabel:SetTextColor(0.95, 0.60, 0.10)
	elvLabel:SetPoint("LEFT", elvCB, "RIGHT", 6, 0)
	elvLabel:SetText("Enable ElvUI Skinning (Experimental)")
	elvCB:SetChecked(XalsQuestCompassDB.elvuiSkinning)
	elvCB.OnToggle = function(self)
		XalsQuestCompassDB.elvuiSkinning = self:GetChecked() and true or false
		print("|cff33ff99Xal's Quest Compass:|r ElvUI Skinning " .. (XalsQuestCompassDB.elvuiSkinning and "enabled" or "disabled") .. " - /reload to apply.")
	end

	local ELV_DESC_BASE = "If you use ElvUI, the main quest window can defer to ElvUI's own look instead of Xal's default style. Requires ElvUI to be installed. Changes apply after /reload. This is new and not widely tested yet - if something looks off with it on, let Xal know."
	-- Grayed out and unclickable when ElvUI isn't actually installed - a
	-- normal-looking, clickable toggle that silently does nothing reads as
	-- broken rather than inert (caught 2026-08-13).
	local function UpdateElvCBAvailability()
		if Brand.IsElvUIAvailable() then
			elvCB:EnableMouse(true)
			elvCB:SetAlpha(1)
			elvLabel:SetAlpha(1)
			elvDesc:SetText(ELV_DESC_BASE)
		else
			elvCB:EnableMouse(false)
			elvCB:SetAlpha(0.4)
			elvLabel:SetAlpha(0.4)
			elvDesc:SetText(ELV_DESC_BASE .. " |cffff4444ElvUI not detected.|r")
		end
	end
	UpdateElvCBAvailability()

	displayPanel:SetScript("OnShow", function()
		scaleSlider:SetValue(XalsQuestCompassDB.windowScale or 1.0)
		UpdateDisplayScaleText()
		elvCB:SetChecked(XalsQuestCompassDB.elvuiSkinning)
		UpdateElvCBAvailability()
	end)

	----------------------------------------------------------------
	-- Sidebar tabs - every section has real content now.
	----------------------------------------------------------------
	local SECTION_NAMES = { "Home", "Behavior", "Automation", "Font", "Display" }
	local sectionPanels = { homePanel, behaviorPanel, automationPanel, fontPanel, displayPanel }
	local tabs = {}

	local function ShowSection(index)
		for i, tab in ipairs(tabs) do
			tab:SetSelected(i == index)
		end
		for i, p in ipairs(sectionPanels) do
			if p then
				if i == index then p:Show() else p:Hide() end
			end
		end
	end

	local TAB_SIDE_PAD = 8
	local anchorTab = nil
	for i, name in ipairs(SECTION_NAMES) do
		local tab = Brand.MakeLinkButton(sidebar)
		tab:SetLabel(name, GOLD)
		tab:SetScript("OnClick", function() ShowSection(i) end)
		tab:ClearAllPoints()
		if anchorTab then
			PixelUtil.SetPoint(tab, "TOPLEFT", anchorTab, "BOTTOMLEFT", 0, -10)
		else
			-- Buffer below the sidebar frame's own top (which sits right at
			-- the header divider) - only the button moves, not the divider
			-- or the sidebar frame itself.
			PixelUtil.SetPoint(tab, "TOPLEFT", sidebar, "TOPLEFT", TAB_SIDE_PAD, -32)
		end
		tabs[i] = tab
		anchorTab = tab
	end
	ShowSection(1)

	----------------------------------------------------------------
	-- Footer: version + branding, fixed at the bottom of the whole window
	-- regardless of which section is showing.
	----------------------------------------------------------------
	local function GetInstalledVersion()
		local v
		if C_AddOns and C_AddOns.GetAddOnMetadata then
			v = C_AddOns.GetAddOnMetadata("XalsQuestCompass", "Version")
		elseif _G.GetAddOnMetadata then
			v = _G.GetAddOnMetadata("XalsQuestCompass", "Version")
		end
		if v == "@project-version@" then return "dev" end
		return v or "dev"
	end

	local installedVersion = GetInstalledVersion()
	local versionLabel = (installedVersion == "dev") and "dev build" or ("v" .. installedVersion)
	local footerText = Brand.FS(f, versionLabel .. "  \194\183  by Xal  \194\183  A Xal's Creation",
		"Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", 11, "", Brand.GOLD[1], Brand.GOLD[2], Brand.GOLD[3])
	-- Centered within the CONTENT area's span (divider to right border), not
	-- the whole window - centering across the full width read off-center
	-- once the sidebar was added, since the sidebar isn't part of this span.
	footerText:SetPoint("BOTTOMLEFT", vDivider, "BOTTOMRIGHT", 12, Brand.SAFE_MARGIN)
	footerText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Brand.SAFE_MARGIN, Brand.SAFE_MARGIN)
	footerText:SetJustifyH("CENTER")

	f:Hide()
	standaloneFrame = f
	return f
end

local function OpenOptionsPanel()
	local f = BuildStandaloneOptionsWindow()
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
	end
end
XQC.OpenOptions = OpenOptionsPanel

-- Exposed for MinimapButton.lua's left-click (LibDataBroker has no direct
-- access to the QTT local, same reason OpenOptions is exposed above).
function XQC.ToggleWindow()
	if not QTT then return end
	if QTT:IsShown() then
		QTT:Hide()
	else
		QTT:Show()
	end
end

-------------------------------------------------
-- Main frame
-------------------------------------------------

local function CreateMainFrame()
	-- Height is computed by RefreshList to fit content (one quest is a
	-- fixed, small shape) - width is still player-adjustable via the resize
	-- grip, for long quest titles / long zone names.
	QTT = CreateFrame("Frame", "XalsQuestCompassFrame", UIParent, "BackdropTemplate")
	QTT:SetSize(XalsQuestCompassDB.width or defaults.width, defaults.height)
	QTT:SetResizable(true)
	if QTT.SetResizeBounds then
		QTT:SetResizeBounds(280, 140, 700, 400)
	else
		QTT:SetMinResize(280, 140)
		QTT:SetMaxResize(700, 400)
	end

	local p = XalsQuestCompassDB.point
	QTT:SetPoint(p[1], UIParent, p[2], p[3], p[4])

	QTT:SetMovable(true)
	QTT:EnableMouse(true)
	QTT:SetClampedToScreen(true)
	QTT:RegisterForDrag("LeftButton")
	-- Shift+drag to move, not a plain drag - a plain drag on the window body
	-- would otherwise fight with scrolling the mouse wheel over the quest
	-- area or clicking Track/Navigate/Close/the actions menu.
	QTT:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() then
			self:StartMoving()
		end
	end)
	QTT:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		XalsQuestCompassDB.point = { point, relPoint, x, y }
	end)
	-- Shift+drag isn't discoverable on its own - a hover hint on the window
	-- itself, not just a changelog line, so a player actually has a way to
	-- find out how to move it.
	QTT:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetText("Hold Shift and drag to move this window", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	QTT:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Branded chrome: opaque near-black background, pixel-snapped accent-gold
	-- border - same look as every other Xal's addon. If ElvUI Skinning is on
	-- and ElvUI is installed, defer to ElvUI's own template instead - a
	-- runtime toggle, not a replacement: the brand chrome above is what
	-- still renders the instant the setting is off or ElvUI isn't present.
	local Brand = XQC.BrandStyle
	local elvS = Brand.GetElvUISkins()
	if elvS then
		QTT:SetTemplate("Transparent")
	else
		Brand.ApplyBackground(QTT)
		Brand.ApplyBackgroundImage(QTT)
		Brand.DrawBorder(QTT)
	end

	QTT:SetFrameStrata("MEDIUM")
	-- Raises itself above other frames sharing this strata the instant it's
	-- shown/clicked - the real, standard Blizzard API every established
	-- addon (confirmed against Zygor's own windows) uses so an overlapping
	-- window never feels "stuck behind" another one.
	QTT:SetToplevel(true)
	QTT:Hide()

	-- Title -- no icon, no gear button. Neither was in the confirmed mockup.
	-- Fixed Simply Sans Bold, not tied to titleFontObj (the user's quest-
	-- title Font picker) - this is chrome, not customizable quest content.
	QTT.title = QTT:CreateFontString(nil, "OVERLAY")
	QTT.title:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\CustomFont.ttf", 20, "OUTLINE")
	QTT.title:SetPoint("TOPLEFT", Brand.SAFE_MARGIN, -Brand.SAFE_MARGIN)
	QTT.title:SetText("Quest Compass")
	QTT.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	-- Close -- plain text link, not a bordered X.
	QTT.closeBtn = Brand.MakeLinkButton(QTT)
	QTT.closeBtn:SetLabel("Close", GOLD)
	QTT.closeBtn:SetScript("OnClick", function() QTT:Hide() end)
	PixelUtil.SetPoint(QTT.closeBtn, "TOPRIGHT", QTT, "TOPRIGHT", -Brand.SAFE_MARGIN, -Brand.SAFE_MARGIN)

	-- Minimize/expand toggle - collapses the window down to just a thin
	-- title bar showing the ready count, same pattern as Xal's Compendium.
	-- Mainly exists so Auto-Show can pop up something unobtrusive instead of
	-- the full window taking over the screen at an inconvenient moment.
	QTT.minimizeBtn = Brand.MakeLinkButton(QTT)
	-- A single "-"/"+" character is tiny both to see and to click with
	-- MakeLinkButton's default small font + auto-width-to-text sizing
	-- (confirmed via screenshot). Bigger font AND a real hitbox, both
	-- re-applied every time the label changes since SetLabel resets the
	-- font/width on its own each call.
	QTT.minimizeBtn.label:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", 20, "")
	local minimizeBtnSetLabel = QTT.minimizeBtn.SetLabel
	function QTT.minimizeBtn:SetLabel(text, color)
		minimizeBtnSetLabel(self, text, color)
		self.label:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", 20, "")
		PixelUtil.SetSize(self, 26, 26)
	end
	QTT.minimizeBtn:SetScript("OnClick", function() XQC.ToggleMinimized() end)
	PixelUtil.SetPoint(QTT.minimizeBtn, "TOPRIGHT", QTT.closeBtn, "TOPLEFT", -10, 0)

	-- Minimized-state label ("3 ready to turn in") - only shown while
	-- minimized, replacing the title/count/quest area entirely.
	QTT.minimizedLabel = QTT:CreateFontString(nil, "OVERLAY")
	QTT.minimizedLabel:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", 13, "")
	QTT.minimizedLabel:SetPoint("LEFT", QTT, "LEFT", Brand.SAFE_MARGIN, 0)
	QTT.minimizedLabel:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	QTT.minimizedLabel:Hide()

	-- Count text -- the merged "1 / 5 ready to turn in (scroll to see other
	-- quests in area)" line, filled in by RefreshList. Body text, so Fira
	-- Sans - not tied to the user's quest-title Font picker.
	QTT.countText = QTT:CreateFontString(nil, "OVERLAY")
	QTT.countText:SetFont("Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\FiraSans-Medium.ttf", 12, "")
	QTT.countText:SetPoint("TOPLEFT", QTT.title, "BOTTOMLEFT", 0, -6)
	QTT.countText:SetTextColor(WHITE[1], WHITE[2], WHITE[3])

	-- Header divider
	local headerDivider = CreateDivider(QTT)
	headerDivider:SetPoint("TOPLEFT", 14, -64)
	headerDivider:SetPoint("TOPRIGHT", -14, -64)
	QTT.headerDivider = headerDivider

	-- Empty-state text
	QTT.noQuestsText = QTT:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
	QTT.noQuestsText:SetPoint("CENTER", 0, 20)
	QTT.noQuestsText:SetText("No quests ready to turn in")
	QTT.noQuestsText:Hide()

	-- Single-quest display area -- only the closest ready quest renders
	-- here; hovering it and scrolling the mouse wheel cycles through the
	-- others (see RefreshList/CreateRow's OnMouseWheel handler). No scroll
	-- frame needed since only one quest is ever shown at a time.
	local questArea = CreateFrame("Frame", nil, QTT)
	questArea:SetPoint("TOPLEFT", Brand.SAFE_MARGIN, -QUEST_AREA_TOP)
	questArea:SetPoint("BOTTOMRIGHT", -Brand.SAFE_MARGIN, QUEST_AREA_BOTTOM)
	QTT.questArea = questArea

	-- Resize grip -- width only matters in practice (height is recomputed
	-- by RefreshList right after, to fit the single quest row), but drags
	-- from the corner like any normal resize handle.
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
		RefreshList()
	end)
	resizeHandle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Drag to resize")
		GameTooltip:Show()
	end)
	resizeHandle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	QTT.resizeHandle = resizeHandle

	-- Active-route status (Stop X/Y + Skip/Cancel) -- live progress state,
	-- so it stays on the window itself rather than living in the actions
	-- menu below. Only shown while a route is in progress (UpdateRouteFooter).
	local routeStatusText = QTT:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	routeStatusText:SetPoint("BOTTOMLEFT", Brand.SAFE_MARGIN, Brand.SAFE_MARGIN + 5)
	routeStatusText:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
	routeStatusText:Hide()
	QTT.routeStatusText = routeStatusText

	local routeSkipBtn = Brand.MakeLinkButton(QTT)
	routeSkipBtn:SetPoint("LEFT", routeStatusText, "RIGHT", 8, 0)
	routeSkipBtn:SetLabel("Skip", GREY)
	routeSkipBtn:SetScript("OnClick", function()
		SkipStop()
	end)
	routeSkipBtn:Hide()
	QTT.routeSkipBtn = routeSkipBtn

	local routeCancelBtn = Brand.MakeLinkButton(QTT)
	routeCancelBtn:SetPoint("LEFT", routeSkipBtn, "RIGHT", 6, 0)
	routeCancelBtn:SetLabel("Cancel", GREY)
	routeCancelBtn:SetScript("OnClick", function()
		StopRoute()
	end)
	routeCancelBtn:Hide()
	QTT.routeCancelBtn = routeCancelBtn

	-------------------------------------------------
	-- Actions menu -- everything that used to be a row of footer buttons
	-- now lives in a flyout triggered by the chevron button in the bottom
	-- right corner. It drops BELOW the window's own border, not inside it.
	-------------------------------------------------
	-- Height is computed, not guessed - FLYOUT_ITEM_COUNT items, each
	-- FLYOUT_ITEM_HEIGHT tall (Brand.MakeLinkButton's fixed height) with
	-- FLYOUT_ITEM_GAP between them and FLYOUT_PAD above/below. Adding or
	-- removing an item below just means updating FLYOUT_ITEM_COUNT instead
	-- of re-guessing a pixel total that silently clips the last item.
	local FLYOUT_ITEM_HEIGHT = 20
	local FLYOUT_ITEM_GAP = 14
	local FLYOUT_PAD = 14
	local FLYOUT_ITEM_COUNT = 5 -- zone toggle, Navigate to Nearest, Track All, Route All, Untrack All
	local flyoutHeight = FLYOUT_PAD * 2 + FLYOUT_ITEM_COUNT * FLYOUT_ITEM_HEIGHT + (FLYOUT_ITEM_COUNT - 1) * FLYOUT_ITEM_GAP

	local flyoutMenu = CreateFrame("Frame", nil, QTT, "BackdropTemplate")
	flyoutMenu:SetSize(200, flyoutHeight)
	flyoutMenu:SetPoint("TOP", QTT, "BOTTOM", 0, -6)
	Brand.ApplyBackground(flyoutMenu)
	Brand.DrawBorder(flyoutMenu)
	flyoutMenu:SetFrameStrata("MEDIUM")
	flyoutMenu:SetFrameLevel(QTT:GetFrameLevel() + 5)
	flyoutMenu:Hide()
	QTT.flyoutMenu = flyoutMenu

	-- Zone filter toggle
	local zoneToggleBtn = Brand.MakeLinkButton(flyoutMenu)
	zoneToggleBtn:SetPoint("TOPLEFT", FLYOUT_PAD, -FLYOUT_PAD)
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
		flyoutMenu:Hide()
	end)
	zoneToggleBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Click to switch between showing only\nthis zone's turn-ins or all of them.", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	zoneToggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	zoneToggleBtn:UpdateText()
	QTT.zoneToggleBtn = zoneToggleBtn

	local navNearestBtn = Brand.MakeLinkButton(flyoutMenu)
	navNearestBtn:SetPoint("TOPLEFT", zoneToggleBtn, "BOTTOMLEFT", 0, -FLYOUT_ITEM_GAP)
	navNearestBtn:SetLabel("Navigate to Nearest", GOLD)
	navNearestBtn:SetScript("OnClick", function()
		local quests = GetTurnInQuests()
		if quests[1] then
			NavigateToQuest(quests[1].questID, quests[1].title)
			RefreshList()
		else
			print("|cff33ff99Xal's Quest Compass:|r No quests are ready to turn in.")
		end
		flyoutMenu:Hide()
	end)

	local trackAllBtn = Brand.MakeLinkButton(flyoutMenu)
	trackAllBtn:SetPoint("TOPLEFT", navNearestBtn, "BOTTOMLEFT", 0, -FLYOUT_ITEM_GAP)
	trackAllBtn:SetLabel("Track All", LIGHT_BLUE)
	trackAllBtn:SetScript("OnClick", function()
		for _, info in ipairs(GetTurnInQuests()) do
			Compat_AddQuestWatch(info.questID)
		end
		RefreshList()
		flyoutMenu:Hide()
	end)
	QTT.trackAllBtn = trackAllBtn

	-- Route All -- computes a multi-stop route through every ready quest and
	-- starts walking it. Hides while a route is already active (the status
	-- readout + Skip/Cancel on the window itself takes over - see
	-- UpdateRouteFooter).
	local routeAllBtn = Brand.MakeLinkButton(flyoutMenu)
	routeAllBtn:SetPoint("TOPLEFT", trackAllBtn, "BOTTOMLEFT", 0, -FLYOUT_ITEM_GAP)
	routeAllBtn:SetLabel("Route All", GOLD)
	routeAllBtn:SetScript("OnClick", function()
		StartRoute()
		flyoutMenu:Hide()
	end)
	QTT.routeAllBtn = routeAllBtn

	local untrackAllBtn = Brand.MakeLinkButton(flyoutMenu)
	untrackAllBtn:SetPoint("TOPLEFT", routeAllBtn, "BOTTOMLEFT", 0, -FLYOUT_ITEM_GAP)
	untrackAllBtn:SetLabel("Untrack All", GREY)
	untrackAllBtn:SetScript("OnClick", function()
		for _, info in ipairs(GetTurnInQuests()) do
			Compat_RemoveQuestWatch(info.questID)
		end
		RefreshList()
		flyoutMenu:Hide()
	end)
	QTT.untrackAllBtn = untrackAllBtn

	-- Chevron trigger -- double down-chevron, bottom right corner, opens
	-- the actions menu below the window. Built from plain text (not a
	-- texture) so it renders in whatever font is active, with zero risk
	-- of a missing/blank icon asset.
	local chevronBtn = CreateFrame("Button", nil, QTT)
	chevronBtn:SetSize(24, 24)
	chevronBtn:SetPoint("BOTTOMRIGHT", QTT, "BOTTOMRIGHT", -30, Brand.SAFE_MARGIN)
	local chevronText = chevronBtn:CreateFontString(nil, "OVERLAY")
	chevronText:SetFontObject(smallFontObj)
	chevronText:SetText("v\nv")
	chevronText:SetSpacing(-6)
	chevronText:SetJustifyH("CENTER")
	chevronText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	chevronText:SetAllPoints()
	chevronBtn.text = chevronText
	chevronBtn:SetScript("OnClick", function()
		flyoutMenu:SetShown(not flyoutMenu:IsShown())
	end)
	chevronBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("More actions")
		GameTooltip:Show()
	end)
	chevronBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	QTT.chevronBtn = chevronBtn

	QTT:SetScript("OnShow", function()
		XQC.ApplyMinimizedState()
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
		QTT.flyoutMenu:Hide()
	end)

	-- Deliberately NOT registered in UISpecialFrames -- Escape should
	-- not close this window (e.g. while adjusting your camera or
	-- backing out of a menu mid-navigation).

	-- Safe to attach now -- everything RefreshList/OnWindowResized touches
	-- (scrollChild, noQuestsText, countText, footer buttons) exists at this point.
	QTT:SetScript("OnSizeChanged", OnWindowResized)
end

-- Minimap button now lives in MinimapButton.lua (LibDataBroker + LibDBIcon,
-- same pattern as Routes/Courier) - see that file. XQC.ToggleWindow/
-- XQC.OpenOptions above are what it calls back into.

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
-- Route All advance signals - QUEST_TURNED_IN is the authoritative "a quest
-- in the route just got turned in" event (identical on all three flavors -
-- see the Route planning section above), QUEST_REMOVED covers a quest
-- leaving the route some other way (abandoned, expired, reset).
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_REMOVED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			-- Each step runs even if an earlier one fails, so one broken
			-- piece can never silently stop the rest (or the login message)
			-- from happening.
			local function RegisterMinimapButton()
				if XQC.MinimapButton and XQC.MinimapButton.Register then
					XQC.MinimapButton:Register()
				end
			end
			local function ShowWhatsNew()
				if XQC.WhatsNew and XQC.WhatsNew.CheckAndShow then
					XQC.WhatsNew:CheckAndShow()
				end
			end
			local steps = { InitDB, ApplyFontSettings, CreateMainFrame, RegisterMinimapButton, CreateOptionsPanel, ShowWhatsNew }
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
		MergeGossipQuestsIntoCurrentStop()
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
	elseif event == "QUEST_TURNED_IN" then
		HandleQuestTurnedIn(arg1)
		RefreshList()
	elseif event == "QUEST_REMOVED" then
		RemoveQuestFromRoute(arg1)
		RefreshList()
	elseif event == "QUEST_LOG_UPDATE" then
		ValidateRouteAgainstLog()
		RefreshList()
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
