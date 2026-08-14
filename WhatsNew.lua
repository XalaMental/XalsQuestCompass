-- WhatsNew.lua
-- Xal's Quest Compass
--
-- Shows a "what's new" splash automatically the FIRST time a player logs in
-- after the addon has been updated to a new version - never during normal,
-- unchanged play. Compares the addon's real installed version (read from the
-- .toc at runtime) against the last version this player actually saw, and
-- only pops up when they differ.
--
-- Update WHATS_NEW below every release to match CHANGELOG.md - one more file
-- touched during normal release prep. The version NUMBER shown does NOT need
-- updating here - it's read live from the real installed .toc version.
XQC = XQC or {}
XQC.WhatsNew = {}
local W = XQC.WhatsNew
local Brand = XQC.BrandStyle

-- ── Update this block every release to match CHANGELOG.md ──────
W.WHATS_NEW = {
	date = "August 8, 2026",
	intro = "Route All: one click plans and walks you through every quest you have ready to turn in.",
	sections = {
		{ heading = "New", items = {
			"Route All - computes an efficient multi-stop route through every quest ready to turn in, across every zone, and walks you through it. Auto-advances as you turn quests in, and folds in extra quests an NPC turns out to have.",
			"On Retail, Route All covers every zone and continent. On Classic, it routes what's locatable in your current zone right now - click it again after traveling to pick up more.",
		} },
	},
}

-- ── Version check ────────────────────────────────────────────
local function GetInstalledVersion()
	local v
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		v = C_AddOns.GetAddOnMetadata("XalsQuestCompass", "Version")
	elseif _G.GetAddOnMetadata then
		v = _G.GetAddOnMetadata("XalsQuestCompass", "Version")
	end
	if v == "@project-version@" then
		return "dev"
	end
	return v
end

local FW = 460
local MAX_FH = 560

local function BuildFrame(installedVersion)
	local f = CreateFrame("Frame", "XalsQuestCompassWhatsNewFrame", UIParent)
	f:SetSize(FW, 360)
	-- Default offset from dead-center, same reasoning as the standalone
	-- options window - only used the first time; once dragged, its real
	-- position is remembered permanently (XalsQuestCompassDB.whatsNewPoint).
	local savedPoint = XalsQuestCompassDB.whatsNewPoint
	if savedPoint then
		f:SetPoint(savedPoint[1], UIParent, savedPoint[2], savedPoint[3], savedPoint[4])
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 220, 40)
	end
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		XalsQuestCompassDB.whatsNewPoint = { point, relPoint, x, y }
	end)
	f:SetClampedToScreen(true)

	Brand.ApplyBackground(f)
	Brand.DrawBorder(f)

	local data = W.WHATS_NEW
	Brand.Title(f, "What's New", 26, "TOP", f, "TOP", 0, -24)

	local verLine = Brand.FS(f, "Version " .. installedVersion .. (data.date and ("  ·  " .. data.date) or ""),
		"Fonts\\ARIALN.TTF", 12, "", Brand.GOLD[1], Brand.GOLD[2], Brand.GOLD[3])
	verLine:SetPoint("TOP", f, "TOP", 0, -58)
	verLine:SetJustifyH("CENTER")

	Brand.DrawDivider(f, 30, 78, FW - 60)

	local y = 92
	if data.intro and data.intro ~= "" then
		local intro = Brand.FS(f, data.intro, "Fonts\\ARIALN.TTF", 12, "", 0.85, 0.85, 0.85)
		intro:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -y)
		intro:SetWidth(FW - 60)
		intro:SetJustifyH("LEFT")
		intro:SetWordWrap(true)
		y = y + (intro:GetStringHeight() or 14) + 14
	end

	for _, section in ipairs(data.sections or {}) do
		local head = Brand.FS(f, section.heading, "Fonts\\ARIALN.TTF", 13, "OUTLINE",
			Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
		head:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -y)
		y = y + 20

		for _, item in ipairs(section.items or {}) do
			local bullet = Brand.FS(f, "-  " .. item, "Fonts\\ARIALN.TTF", 12, "",
				Brand.GOLD[1], Brand.GOLD[2], Brand.GOLD[3])
			bullet:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -y)
			bullet:SetWidth(FW - 76)
			bullet:SetJustifyH("LEFT")
			bullet:SetWordWrap(true)
			y = y + (bullet:GetStringHeight() or 14) + 6
		end
		y = y + 10
	end

	local closeBtn = Brand.MakeButton(f, "Got it", 110, 28, function()
		f:Hide()
	end)
	closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)

	f:SetHeight(math.min(y + 56, MAX_FH))

	return f
end

-- Called from ADDON_LOADED - checks the version and shows the splash only
-- when it's genuinely changed since this player last saw it.
function W:CheckAndShow()
	local installed = GetInstalledVersion()
	if not installed then return end

	local db = XalsQuestCompassDB
	if not db then return end

	if db.lastSeenVersion ~= installed then
		db.lastSeenVersion = installed
		local ok, frame = pcall(BuildFrame, installed)
		if ok and frame then frame:Show() end
	end
end
