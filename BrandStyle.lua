-- BrandStyle.lua
-- Xal's Quest Compass
--
-- Xal's shared visual brand. Background/accent/title treatment are from Xal's
-- Craft Courier's splash panel; the button style is from Xal's Compendium
-- (Courier's beveled "steel" buttons looked visually off - inconsistent
-- highlight/shadow read - once placed in a horizontal row, so Compendium's
-- flat button replaced it as the standard, confirmed 2026-08-09). Every
-- border/divider line is at least 2px - a 1px line can fail to render
-- reliably depending on UI scale, which is why Courier's border was already
-- 2px; dividers are brought up to match here too.
--
-- Use these helpers for the main window's chrome (background/border/title/
-- close button) and every button. This is the addon's BASE/DEFAULT look -
-- Quest Compass's own player-facing font/appearance customization system
-- (font/outline/size/shadow/class-color, in the Options panel) is a separate,
-- deliberate feature and is NOT touched by this file at all.
--
-- Uses the same plain-global-table convention already established by
-- MinimapButton.lua (XQC = XQC or {}) rather than the vararg addonTable
-- pattern other addons use, so every cross-file reference in this addon is
-- consistent with itself.
XQC = XQC or {}
XQC.BrandStyle = {}
local Brand = XQC.BrandStyle

-- ── Colours (r, g, b) ─────────────────────────────────────────
Brand.ACCENT = { 0.72, 0.55, 0.22 }   -- warm bronze-gold
Brand.GOLD   = { 0.60, 0.47, 0.30 }   -- secondary/body text tone
Brand.BG     = { 0.035, 0.035, 0.035, 1 } -- near-black, fully opaque
Brand.LINE_THICKNESS = 2 -- minimum for ANY border/divider - never go below this
Brand.SAFE_MARGIN = 14

-- ── T()  ─ solid-colour texture rectangle.
function Brand.T(parent, x, y, w, h, r, g, b, a, layer)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	PixelUtil.SetPoint(tex, "TOPLEFT", parent, "TOPLEFT", x, -y)
	PixelUtil.SetSize(tex, w, h)
	tex:SetColorTexture(r, g, b, a or 1)
	return tex
end

-- ── FS()  ─ a FontString with a specific font/size/colour.
function Brand.FS(parent, text, fontPath, size, flags, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(fontPath, size, flags or "")
	fs:SetText(text)
	fs:SetTextColor(r, g, b, 1)
	return fs
end

-- ── Title()  ─ the branded Morpheus-font title treatment, with its
-- drop-shadow layer, in one call. Used for the main window's own header
-- ("Quest Compass") - NOT applied to row/list content, which stays on
-- Quest Compass's own customizable font system.
function Brand.Title(parent, text, size, anchorPoint, relTo, relPoint, x, y)
	local shadow = Brand.FS(parent, text, "Fonts\\MORPHEUS.TTF", size, "OUTLINE", 0, 0, 0)
	PixelUtil.SetPoint(shadow, anchorPoint, relTo, relPoint, x + 4, y - 4)
	shadow:SetJustifyH("CENTER")

	local title = Brand.FS(parent, text, "Fonts\\MORPHEUS.TTF", size, "OUTLINE",
		Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
	PixelUtil.SetPoint(title, anchorPoint, relTo, relPoint, x, y)
	title:SetJustifyH("CENTER")
	return title
end

-- ── ElvUI skinning (opt-in, additive) ──────────────────────────
-- A runtime toggle, not a replacement - the hand-drawn brand style below is
-- untouched and stays the default. When the player turns "Enable ElvUI
-- Skinning" on AND has ElvUI installed, MakeButton/etc. branch to an
-- ElvUI-skinned rendering path instead; turning the setting off (or not
-- having ElvUI) returns to the exact same brand style as always. Checked
-- fresh on every call rather than cached, since ElvUI's own load state and
-- this addon's setting can each change between calls (e.g. before ElvUI has
-- finished loading, or after the player flips the checkbox and /reloads).
-- IsAddOnLoaded was deprecated in retail patch 11.0.2 and is nil as a
-- global there (moved to C_AddOns.IsAddOnLoaded) - Classic clients may not
-- have the C_AddOns namespace yet, so this picks whichever actually exists.
local IsAddOnLoadedCompat = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

function Brand.GetElvUISkins()
	if not (XalsQuestCompassDB and XalsQuestCompassDB.elvuiSkinning) then return nil end
	if not IsAddOnLoadedCompat or not IsAddOnLoadedCompat("ElvUI") then return nil end
	local E = unpack(ElvUI)
	if not E then return nil end
	return E:GetModule("Skins")
end

-- ── MakeButton()  ─ Xal's Compendium's flat button.
local BTN_BORDER = { Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1 }
local BTN_BORDER_SELECTED = { Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1 }
local BTN_LABEL_UNSELECTED = { 0.95, 0.60, 0.10 }

function Brand.MakeButton(parent, text, w, h, onClick)
	local S = Brand.GetElvUISkins()
	if S then
		return Brand.MakeButtonElvUI(S, parent, text, w, h, onClick)
	end

	local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
	PixelUtil.SetSize(btn, w, h)
	btn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
	})
	btn:SetBackdropColor(0.1, 0.1, 0.1, 0.6)

	local thick = Brand.LINE_THICKNESS
	local borderTop = btn:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderTop, "TOPLEFT", btn, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(borderTop, "TOPRIGHT", btn, "TOPRIGHT", 0, 0)
	PixelUtil.SetHeight(borderTop, thick)

	local borderBottom = btn:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderBottom, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
	PixelUtil.SetPoint(borderBottom, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	PixelUtil.SetHeight(borderBottom, thick)

	local borderLeft = btn:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderLeft, "TOPLEFT", btn, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(borderLeft, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
	PixelUtil.SetWidth(borderLeft, thick)

	local borderRight = btn:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderRight, "TOPRIGHT", btn, "TOPRIGHT", 0, 0)
	PixelUtil.SetPoint(borderRight, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	PixelUtil.SetWidth(borderRight, thick)

	local function SetBorderColor(r, g, b, a)
		borderTop:SetColorTexture(r, g, b, a)
		borderBottom:SetColorTexture(r, g, b, a)
		borderLeft:SetColorTexture(r, g, b, a)
		borderRight:SetColorTexture(r, g, b, a)
	end
	SetBorderColor(BTN_BORDER[1], BTN_BORDER[2], BTN_BORDER[3], BTN_BORDER[4])

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(text)
	label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
	btn.label = label

	btn:SetScript("OnEnter", function(self)
		if not self.selected then self:SetBackdropColor(0.18, 0.18, 0.18, 0.75) end
	end)
	btn:SetScript("OnLeave", function(self)
		if not self.selected then self:SetBackdropColor(0.1, 0.1, 0.1, 0.6) end
	end)
	if onClick then btn:SetScript("OnClick", onClick) end

	function btn:SetSelected(selected)
		self.selected = selected
		if selected then
			self:SetBackdropColor(0.22, 0.22, 0.22, 0.85)
			SetBorderColor(BTN_BORDER_SELECTED[1], BTN_BORDER_SELECTED[2], BTN_BORDER_SELECTED[3], BTN_BORDER_SELECTED[4])
			label:SetTextColor(1, 1, 1, 1)
		else
			self:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
			SetBorderColor(BTN_BORDER[1], BTN_BORDER[2], BTN_BORDER[3], BTN_BORDER[4])
			label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
		end
	end

	function btn:SetBorderColor(r, g, bC, a)
		SetBorderColor(r, g, bC, a)
	end

	return btn
end

-- ── MakeButtonElvUI()  ─ same button, ElvUI's own skin instead of the
-- hand-drawn border/fill above - border/backdrop color is then owned by
-- ElvUI's live theme (matches whatever the player has ElvUI configured to),
-- not this file. Same .label/:SetSelected()/:SetBorderColor() surface as
-- MakeButton so nothing calling it needs to know which path is active.
-- Selected/unselected is still carried by label color (white vs. amber),
-- same signal as the hand-drawn version, since ElvUI's HandleButton has no
-- "selected" concept of its own to hook into.
function Brand.MakeButtonElvUI(S, parent, text, w, h, onClick)
	local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
	PixelUtil.SetSize(btn, w, h)
	S:HandleButton(btn)

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(text)
	label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
	btn.label = label

	if onClick then btn:SetScript("OnClick", onClick) end

	function btn:SetSelected(selected)
		self.selected = selected
		if selected then
			label:SetTextColor(1, 1, 1, 1)
		else
			label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
		end
	end

	-- No-op under ElvUI skinning - border color belongs to ElvUI's theme
	-- here, not this addon - but callers may still call this expecting it
	-- to exist (e.g. hover/selection feedback elsewhere in the file).
	function btn:SetBorderColor(r, g, b, a) end

	return btn
end

-- ── DrawBorder()  ─ single clean accent-color line around a frame.
function Brand.DrawBorder(f, inset)
	inset = inset or 6
	local thick = Brand.LINE_THICKNESS
	local r, g, b = Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3]

	local top = f:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(top, "TOPLEFT", f, "TOPLEFT", inset, -inset)
	PixelUtil.SetPoint(top, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
	PixelUtil.SetHeight(top, thick)
	top:SetColorTexture(r, g, b, 1)

	local bottom = f:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(bottom, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
	PixelUtil.SetPoint(bottom, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
	PixelUtil.SetHeight(bottom, thick)
	bottom:SetColorTexture(r, g, b, 1)

	local left = f:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(left, "TOPLEFT", f, "TOPLEFT", inset, -inset)
	PixelUtil.SetPoint(left, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
	PixelUtil.SetWidth(left, thick)
	left:SetColorTexture(r, g, b, 1)

	local right = f:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(right, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
	PixelUtil.SetPoint(right, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
	PixelUtil.SetWidth(right, thick)
	right:SetColorTexture(r, g, b, 1)

	return top, bottom, left, right
end

-- ── DrawDivider()  ─ the thin section-separator line.
function Brand.DrawDivider(parent, x, y, width)
	return Brand.T(parent, x, y, width, Brand.LINE_THICKNESS, 0.16, 0.12, 0.05, 1)
end

-- ── ApplyBackground()  ─ the standard opaque near-black frame background.
function Brand.ApplyBackground(f)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(Brand.BG[1], Brand.BG[2], Brand.BG[3], Brand.BG[4])
	return bg
end
