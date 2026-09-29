-- BrandStyle.lua
-- Xal's Quest Compass
--
-- Xal's shared visual brand. Every border/divider line is at least 2px - a
-- 1px line can fail to render reliably depending on UI scale.
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
Brand.ACCENT = { 0.72, 0.30, 0.0 }    -- deep, dark, burnt orange - superseded by Brand.HEADER_COLOR below as of 2026-09-25 ("everything the same dark red, no exceptions"); kept only for an explicit Classic-style option, which this addon doesn't have
Brand.GOLD   = { 0.60, 0.47, 0.30 }   -- secondary/body text tone (unchanged)
Brand.BG     = { 0.03, 0.028, 0.06, 1 } -- dark indigo leaning purple, #08070f

-- Family-wide rollout, confirmed 2026-09-20 (worked out on Xal's Roster
-- Roundup, then confirmed as the standard for EVERY addon). Narrow, specific
-- scope for each - do not spread these to anything else without asking first:
Brand.HEADER_COLOR = { 0.4078, 0.0784, 0.0902 } -- #681417, dark brick red.
	-- ONLY for: a window's main title text (Brand.Title()'s front layer /
	-- QTT's own hand-built title), the ONE header divider directly under
	-- that title (DrawHeaderDivider), and a selected/active link in a
	-- standalone window's own sidebar.
Brand.DIVIDER_COLOR = { 0.0627, 0.0627, 0.1255 } -- #101020, near-black indigo.
	-- Every OTHER divider (section/list/sidebar dividers), plus panel/card
	-- edges (DrawBorder()'s default color) and the outer window border.
Brand.SIDEBAR_UNSELECTED = { 0.196, 0.196, 0.392 } -- #323264, muted blue-gray.
	-- An UNselected link in a standalone window's own sidebar. Selected uses
	-- Brand.HEADER_COLOR above, not white and not accent-orange.
Brand.LINE_THICKNESS = 2 -- minimum for ANY border/divider - never go below this
Brand.SAFE_MARGIN = 14

-- ── Font paths ────────────────────────────────────────────────
-- Header/title: Cinzel Bold. Body/label: Inter Regular/SemiBold. Already
-- bundled in this addon's own Fonts/ folder from the V1.7.0 redesign.
Brand.TITLE_FONT_PATH = "Interface\\AddOns\\XalsQuestCompass\\Fonts\\Cinzel-Bold.ttf"
Brand.BODY_FONT_PATH = "Interface\\AddOns\\XalsQuestCompass\\Fonts\\Inter-Regular.ttf"
Brand.BODY_FONT_PATH_SEMIBOLD = "Interface\\AddOns\\XalsQuestCompass\\Fonts\\Inter-SemiBold.ttf"

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
	fs:SetJustifyH("LEFT")
	return fs
end

-- ── BodyFS()  ─ Brand.FS pre-wired to the body font, with a subtle drop
-- shadow so small body text stays legible over busy backgrounds.
function Brand.BodyFS(parent, text, size, r, g, b)
	local fs = Brand.FS(parent, text, Brand.BODY_FONT_PATH, size, "", r or 0.85, g or 0.85, b or 0.85)
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	return fs
end

-- ── Title()  ─ the branded title treatment, with its drop-shadow layer, in
-- one call. Used for the settings windows' own header ("Xal's Quest
-- Compass") - NOT applied to row/list content, which stays on Quest
-- Compass's own customizable font system.
function Brand.Title(parent, text, size, anchorPoint, relTo, relPoint, x, y)
	local shadow = Brand.FS(parent, text, Brand.TITLE_FONT_PATH, size, "OUTLINE", 0, 0, 0)
	PixelUtil.SetPoint(shadow, anchorPoint, relTo, relPoint, x + 4, y - 4)
	shadow:SetJustifyH("CENTER")

	local title = Brand.FS(parent, text, Brand.TITLE_FONT_PATH, size, "OUTLINE",
		Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])
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

-- Whether ElvUI is actually installed, independent of the player's own
-- elvuiSkinning setting - lets the Options UI gray out the toggle instead
-- of showing a normal-looking control that silently does nothing.
function Brand.IsElvUIAvailable()
	return (IsAddOnLoadedCompat and IsAddOnLoadedCompat("ElvUI")) and true or false
end

function Brand.GetElvUISkins()
	if not (XalsQuestCompassDB and XalsQuestCompassDB.elvuiSkinning) then return nil end
	if not Brand.IsElvUIAvailable() then return nil end
	local E = unpack(ElvUI)
	if not E then return nil end
	return E:GetModule("Skins")
end

-- ── MakeButton()  ─ text-link style (confirmed 2026-08-17/18 family-wide -
-- supersedes the earlier boxed/bordered version entirely). Plain text, no
-- fill, no border. Selected vs. normal state is carried entirely by label
-- color/brightness. Call btn:SetSelected(true/false) to toggle.
-- Confirmed 2026-09-25 (Xpedited Routes, "everything the same dark red, no
-- exceptions") - this used to be Brand.ACCENT (orange); there is no separate
-- accent color anymore for action links/buttons/checkboxes/sliders, all of
-- that is Brand.HEADER_COLOR now, same as titles.
local BTN_LABEL_UNSELECTED = Brand.HEADER_COLOR

function Brand.MakeButton(parent, text, w, h, onClick)
	local S = Brand.GetElvUISkins()
	if S then
		return Brand.MakeButtonElvUI(S, parent, text, w, h, onClick)
	end

	local btn = CreateFrame("Button", nil, parent)
	PixelUtil.SetSize(btn, w, h)

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(text)
	label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
	btn.label = label

	-- Default selected/unselected colors are the standard white/orange pair.
	-- A standalone window's own SIDEBAR nav buttons override both to the
	-- family-wide sidebar link colors instead (narrowly scoped to sidebar
	-- links only): btn:SetSelectedColor(unpack(Brand.HEADER_COLOR)) /
	-- btn:SetUnselectedColor(unpack(Brand.SIDEBAR_UNSELECTED)).
	btn.selectedColor = { 1, 1, 1 }
	btn.unselectedColor = BTN_LABEL_UNSELECTED

	btn:SetScript("OnEnter", function(self)
		if not self.selected then label:SetTextColor(1, 1, 1, 1) end
	end)
	btn:SetScript("OnLeave", function(self)
		if not self.selected then
			local c = self.unselectedColor
			label:SetTextColor(c[1], c[2], c[3], 1)
		end
	end)
	if onClick then btn:SetScript("OnClick", onClick) end

	function btn:SetSelected(selected)
		self.selected = selected
		local c = selected and self.selectedColor or self.unselectedColor
		label:SetTextColor(c[1], c[2], c[3], 1)
	end

	function btn:SetSelectedColor(r, g, b)
		self.selectedColor = { r, g, b }
		if self.selected then label:SetTextColor(r, g, b, 1) end
	end

	function btn:SetUnselectedColor(r, g, b)
		self.unselectedColor = { r, g, b }
		if not self.selected then label:SetTextColor(r, g, b, 1) end
	end

	-- Was a border-color hook before the box existed - kept as the same
	-- method name/signature so call sites don't need touching, just now
	-- tints the label itself instead of a border that no longer exists.
	function btn:SetBorderColor(r, g, bC, a)
		label:SetTextColor(r, g, bC, a)
	end

	return btn
end

-- ── MakeButtonElvUI()  ─ same button, ElvUI's own skin instead of the
-- hand-drawn text-link above - border/backdrop color is then owned by
-- ElvUI's live theme (matches whatever the player has ElvUI configured to),
-- not this file. Same .label/:SetSelected()/:SetBorderColor() surface as
-- MakeButton so nothing calling it needs to know which path is active.
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

-- ── MakeCloseButton()  ─ text-link style close ("Close" in accent gold,
-- brightens to white on hover) - replaces a boxed "X" button. Doesn't set
-- its own anchor point; call sites position it themselves.
function Brand.MakeCloseButton(parent, onClick)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(50, 20)

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText("Close")
	label:SetTextColor(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3], 1)
	btn.label = label

	btn:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1, 1) end)
	btn:SetScript("OnLeave", function()
		label:SetTextColor(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3], 1)
	end)
	btn:SetScript("OnClick", onClick or function() parent:Hide() end)

	return btn
end

-- ── MakeLinkButton()  ─ plain clickable text, no border/fill. For spots
-- where the bordered MakeButton look reads as too heavy/boxy - e.g. a
-- quick-toggle sitting inline next to other text, or a standalone window's
-- sidebar nav links. Same .label/:SetLabel() surface as MakeButton so call
-- sites don't need special-case handling for which style a given button
-- uses.
function Brand.MakeLinkButton(parent)
	local btn = CreateFrame("Button", nil, parent)
	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	btn.label = label
	PixelUtil.SetHeight(btn, 20)

	function btn:SetLabel(text, color)
		color = color or { 1, 1, 1 }
		self.baseColor = color
		self.label:SetText(text)
		if not self.selected then
			self.label:SetTextColor(color[1], color[2], color[3])
		end
		PixelUtil.SetWidth(self, math.max(self.label:GetStringWidth(), 4))
	end

	-- For link buttons used as tabs (e.g. a sidebar) - selected reads
	-- Brand.HEADER_COLOR (the family-wide "selected sidebar link" color,
	-- confirmed 2026-09-20), unselected drops back to the button's own base
	-- color (a plain one-shot link button never calls this at all).
	function btn:SetSelected(selected)
		self.selected = selected
		local c = selected and Brand.HEADER_COLOR or (self.baseColor or { 1, 1, 1 })
		self.label:SetTextColor(c[1], c[2], c[3])
	end

	-- HookScript, not SetScript - call sites often need their own OnEnter/
	-- OnLeave too (e.g. a tooltip), and HookScript lets both run instead of
	-- whichever is set second silently replacing this one.
	btn:HookScript("OnEnter", function(self)
		self.label:SetTextColor(1, 1, 1, 1)
	end)
	btn:HookScript("OnLeave", function(self)
		local c = self.selected and Brand.HEADER_COLOR or (self.baseColor or { 1, 1, 1 })
		self.label:SetTextColor(c[1], c[2], c[3])
	end)

	return btn
end

-- ── MakeDiscordLink()  ─ the standing Discord text-link. Takes only the
-- parent - it does NOT position itself, same as MakeButton/MakeCloseButton;
-- the call site sets its own point (usually TOPRIGHT near the title).
Brand.DISCORD_URL = "https://discord.gg/9SwrQDJeCe"

StaticPopupDialogs["XALQC_COPY_URL"] = {
	text = "Copy this link:",
	button1 = "Close",
	hasEditBox = true,
	editBoxWidth = 260,
	OnShow = function(self, data)
		self.editBox:SetText(data)
		self.editBox:HighlightText()
		self.editBox:SetFocus()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Icon-only Discord mark (official brand asset, white symbol variant), used
-- next to the text link so it pops instead of reading as plain text. Ship
-- Textures/DiscordIcon.png in this addon's own folder, copied from
-- D:\WoW_Addons\Dev\Assets\Icons\Discord-Symbol-White_64.png.
Brand.DISCORD_ICON = "Interface\\AddOns\\XalsQuestCompass\\Textures\\DiscordIcon.png"

function Brand.MakeDiscordLink(parent)
	local btn = Brand.MakeLinkButton(parent)
	btn:SetSize(92, 20)

	-- Icon sits left of the label - real aspect ratio (84x64 source)
	-- preserved so the mark doesn't look squashed at this size.
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(21, 16)
	icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
	icon:SetTexture(Brand.DISCORD_ICON)
	btn.icon = icon

	btn.label:ClearAllPoints()
	btn.label:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	btn:SetLabel("Discord", { 0.45, 0.55, 0.95 })

	btn:HookScript("OnEnter", function() icon:SetVertexColor(1, 1, 1, 1) end)
	btn:HookScript("OnLeave", function() icon:SetVertexColor(0.45, 0.55, 0.95, 1) end)
	icon:SetVertexColor(0.45, 0.55, 0.95, 1)

	btn:SetScript("OnClick", function()
		StaticPopup_Show("XALQC_COPY_URL", nil, nil, Brand.DISCORD_URL)
	end)
	return btn
end

-- ── MakeCheckbox()  ─ hand-drawn checkbox, same reason/technique as
-- MakeButton's hand-drawn border: Blizzard's native UICheckButtonTemplate
-- was found rendering incomplete (missing its bottom edge entirely, not
-- just uneven thickness) in a real in-game screenshot on Xal's Roster
-- Roundup (confirmed 2026-08-12) - ported here verbatim so Quest Compass's
-- checkboxes match the same brand standard instead of staying native
-- Blizzard while everything else (buttons, swatches, links) is custom.
-- This is now the brand standard for checkboxes - stop using
-- UICheckButtonTemplate in new code.
--
-- Usage differs slightly from a native CheckButton: set `cb.OnToggle =
-- function(self) ... end` instead of `cb:SetScript("OnClick", ...)`, since
-- OnClick is used internally to flip the checked state before your handler
-- runs (matching the native behavior where GetChecked() already reflects
-- the NEW state inside OnClick). There's also no built-in `.Text` region -
-- build a separate FontString and anchor it `"LEFT", cb, "RIGHT", 6, 0`.
function Brand.MakeCheckbox(parent, size)
	size = size or 22
	local cb = CreateFrame("Button", nil, parent)
	PixelUtil.SetSize(cb, size, size)

	local bg = cb:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

	local thick = Brand.LINE_THICKNESS
	local r, g, b = Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3]

	local borderTop = cb:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderTop, "TOPLEFT", cb, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(borderTop, "TOPRIGHT", cb, "TOPRIGHT", 0, 0)
	PixelUtil.SetHeight(borderTop, thick)
	borderTop:SetColorTexture(r, g, b, 1)

	local borderBottom = cb:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderBottom, "BOTTOMLEFT", cb, "BOTTOMLEFT", 0, 0)
	PixelUtil.SetPoint(borderBottom, "BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
	PixelUtil.SetHeight(borderBottom, thick)
	borderBottom:SetColorTexture(r, g, b, 1)

	local borderLeft = cb:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderLeft, "TOPLEFT", cb, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(borderLeft, "BOTTOMLEFT", cb, "BOTTOMLEFT", 0, 0)
	PixelUtil.SetWidth(borderLeft, thick)
	borderLeft:SetColorTexture(r, g, b, 1)

	local borderRight = cb:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderRight, "TOPRIGHT", cb, "TOPRIGHT", 0, 0)
	PixelUtil.SetPoint(borderRight, "BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
	PixelUtil.SetWidth(borderRight, thick)
	borderRight:SetColorTexture(r, g, b, 1)

	-- Texture, not a FontString "X" - a font glyph's CENTER anchor centers
	-- against the font's full line-height box (ascender/descender padding
	-- included), not the glyph's actual ink, so it visually drifts off-true-
	-- center (caught 2026-08-13 via screenshot). Blizzard's own checkmark
	-- texture centers exactly where told, no font-metrics guesswork.
	local check = cb:CreateTexture(nil, "OVERLAY")
	check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	check:SetVertexColor(r, g, b, 1)
	PixelUtil.SetSize(check, size - 4, size - 4)
	check:SetPoint("CENTER", cb, "CENTER", 0, 0)
	check:Hide()

	cb.checked = false
	function cb:SetChecked(state)
		self.checked = state and true or false
		if self.checked then check:Show() else check:Hide() end
	end
	function cb:GetChecked()
		return self.checked
	end

	cb:SetScript("OnEnter", function() bg:SetColorTexture(0.18, 0.18, 0.18, 0.75) end)
	cb:SetScript("OnLeave", function() bg:SetColorTexture(0.1, 0.1, 0.1, 0.6) end)
	cb:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		if self.OnToggle then self.OnToggle(self) end
	end)

	return cb
end

-- ── MakeEditBox()  ─ hand-drawn text input, same 4-texture border technique
-- as MakeButton/MakeCheckbox.
function Brand.MakeEditBox(parent, w, h)
	h = h or 22
	local box = CreateFrame("EditBox", nil, parent)
	PixelUtil.SetSize(box, w, h)

	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

	local thick = Brand.LINE_THICKNESS
	local r, g, b = Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3]

	local borderTop = box:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderTop, "TOPLEFT", box, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(borderTop, "TOPRIGHT", box, "TOPRIGHT", 0, 0)
	PixelUtil.SetHeight(borderTop, thick)
	borderTop:SetColorTexture(r, g, b, 1)

	local borderBottom = box:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderBottom, "BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
	PixelUtil.SetPoint(borderBottom, "BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
	PixelUtil.SetHeight(borderBottom, thick)
	borderBottom:SetColorTexture(r, g, b, 1)

	local borderLeft = box:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderLeft, "TOPLEFT", box, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(borderLeft, "BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
	PixelUtil.SetWidth(borderLeft, thick)
	borderLeft:SetColorTexture(r, g, b, 1)

	local borderRight = box:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderRight, "TOPRIGHT", box, "TOPRIGHT", 0, 0)
	PixelUtil.SetPoint(borderRight, "BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
	PixelUtil.SetWidth(borderRight, thick)
	borderRight:SetColorTexture(r, g, b, 1)

	box:SetFont(Brand.BODY_FONT_PATH, 13, "")
	box:SetTextColor(0.9, 0.9, 0.9, 1)
	box:SetTextInsets(6, 6, 0, 0)
	box:SetAutoFocus(false)

	return box
end

-- ── DrawBorder()  ─ single clean line around a frame, in Brand.DIVIDER_COLOR
-- (was Brand.ACCENT/bright orange before the 2026-09-20 rollout). Use inset 1
-- for a standalone window's true outer edge, inset 0 (or the default 6) for
-- a panel/card edge within a page.
function Brand.DrawBorder(f, inset)
	inset = inset or 6
	local thick = Brand.LINE_THICKNESS
	local r, g, b = Brand.DIVIDER_COLOR[1], Brand.DIVIDER_COLOR[2], Brand.DIVIDER_COLOR[3]

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

-- ── DrawDivider()  ─ the thin section-separator line - Brand.DIVIDER_COLOR
-- (was a hardcoded muted brown before the 2026-09-20 rollout).
function Brand.DrawDivider(parent, x, y, width)
	return Brand.T(parent, x, y, width, Brand.LINE_THICKNESS,
		Brand.DIVIDER_COLOR[1], Brand.DIVIDER_COLOR[2], Brand.DIVIDER_COLOR[3], 1)
end

-- ── DrawHeaderDivider()  ─ the ONE divider directly under a window's main
-- title, in Brand.HEADER_COLOR - its own distinct color, separate from every
-- other divider (which uses DrawDivider above). Do not spread HEADER_COLOR
-- to any other divider without asking first.
function Brand.DrawHeaderDivider(parent, x, y, width)
	return Brand.T(parent, x, y, width, Brand.LINE_THICKNESS,
		Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3], 1)
end

-- ── ApplyBackground()  ─ the standard opaque near-black frame background.
function Brand.ApplyBackground(f)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(Brand.BG[1], Brand.BG[2], Brand.BG[3], Brand.BG[4])
	return bg
end

-- The shared dark-swirl texture art, sitting on top of the flat background
-- color (BORDER layer, below everything else - border/dividers/text all
-- draw at ARTWORK/OVERLAY, above this). NOT called by default anymore
-- (2026-09-02) - kept only for an explicit "Classic" style option, which
-- this addon does not currently offer.
function Brand.ApplyBackgroundImage(f)
	local img = f:CreateTexture(nil, "BORDER")
	img:SetAllPoints(f)
	img:SetTexture("Interface\\AddOns\\XalsQuestCompass\\Textures\\PanelBackground.jpg")
	return img
end

-- ── MakeDropdown()  ─ brand-styled dropdown, replaces Blizzard's native
-- UIDropDownMenuTemplate everywhere in this addon (Font/Outline pickers) -
-- the stock grey menu was the one remaining unstyled control against an
-- otherwise fully custom panel, confirmed a bad clash via screenshot.
-- Usage: dd = Brand.MakeDropdown(parent, width); dd:SetOptions({{key=,
-- name=}, ...}); dd:SetValue(key); dd.OnSelect = function(key) ... end.
-- The option list is its own top-level frame (not a child of the dropdown
-- button) so it can draw above the settings panel's own scroll clipping,
-- same reason Blizzard's native dropdowns also float above everything.
function Brand.MakeDropdown(parent, width)
	local height = 26
	local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
	PixelUtil.SetSize(dd, width, height)
	dd:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	dd:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
	Brand.DrawBorder(dd, 0)

	local label = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", 10, 0)
	label:SetPoint("RIGHT", -22, 0)
	label:SetJustifyH("LEFT")
	label:SetTextColor(0.9, 0.9, 0.9)
	dd.label = label

	local arrow = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrow:SetPoint("RIGHT", -8, 0)
	arrow:SetText("v")
	arrow:SetTextColor(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])

	dd:SetScript("OnEnter", function(self) self:SetBackdropColor(0.18, 0.18, 0.18, 0.75) end)
	dd:SetScript("OnLeave", function(self) self:SetBackdropColor(0.1, 0.1, 0.1, 0.6) end)

	-- List panel: sized to exactly fit its own rows (no fixed height that
	-- could either clip a long list or leave dead space on a short one -
	-- the "stuff overflowing" complaint against the native menu). Built
	-- once, rows added/reused as SetOptions is called.
	local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	Brand.ApplyBackground(list)
	Brand.DrawBorder(list, 0)
	list:Hide()

	-- Invisible full-screen catcher so clicking anywhere outside the list
	-- closes it - the standard way an addon fakes a native dropdown's
	-- click-away-to-close behavior.
	local catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN")
	catcher:EnableMouse(true)
	catcher:Hide()

	local function CloseList()
		list:Hide()
		catcher:Hide()
	end
	catcher:SetScript("OnMouseDown", CloseList)

	dd.options = {}
	dd.rows = {}

	local ROW_HEIGHT = 22
	function dd:SetOptions(options)
		self.options = options
		for _, row in ipairs(self.rows) do row:Hide() end
		for i, opt in ipairs(options) do
			local row = self.rows[i]
			if not row then
				row = CreateFrame("Button", nil, list)
				row:SetHeight(ROW_HEIGHT)
				local hl = row:CreateTexture(nil, "HIGHLIGHT")
				hl:SetAllPoints()
				hl:SetColorTexture(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3], 0.25)
				local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				text:SetPoint("LEFT", 8, 0)
				text:SetPoint("RIGHT", -8, 0)
				text:SetJustifyH("LEFT")
				row.text = text
				self.rows[i] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_HEIGHT)
			row:SetPoint("RIGHT", -2, 0)
			row.text:SetText(opt.name)
			row:SetScript("OnClick", function()
				dd:SetValue(opt.key)
				CloseList()
				if dd.OnSelect then dd.OnSelect(opt.key) end
			end)
			row:Show()
		end
		list:SetHeight(#options * ROW_HEIGHT + 4)
	end

	function dd:SetValue(key)
		self.value = key
		for _, opt in ipairs(self.options) do
			if opt.key == key then
				label:SetText(opt.name)
				return
			end
		end
	end

	function dd:GetValue()
		return self.value
	end

	dd:SetScript("OnClick", function(self)
		if list:IsShown() then
			CloseList()
			return
		end
		list:ClearAllPoints()
		list:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
		list:SetWidth(width)
		list:Show()
		catcher:Show()
	end)

	return dd
end

-- ── ShowContextMenu()  ─ a right-click/flyout menu built entirely from
-- brand widgets (bordered background, text-link entries) - NOT Blizzard's
-- UIDropDownMenu/EasyMenu. options is an array of { label, r, g, b, onClick }
-- - r/g/b optional (defaults to Brand.ACCENT).
local contextMenu, clickCatcher

function Brand.ShowContextMenu(options)
	if not clickCatcher then
		clickCatcher = CreateFrame("Button", nil, UIParent)
		clickCatcher:SetAllPoints(UIParent)
		clickCatcher:SetFrameStrata("FULLSCREEN")
		clickCatcher:Hide()
	end

	if not contextMenu then
		contextMenu = CreateFrame("Frame", nil, UIParent)
		contextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
		Brand.ApplyBackground(contextMenu)
		Brand.DrawBorder(contextMenu, 4)
		contextMenu.buttons = {}
		contextMenu:Hide()
	end

	local ROW_H, PAD = 22, 10
	local width = 90
	for i, opt in ipairs(options) do
		local btn = contextMenu.buttons[i]
		if not btn then
			btn = Brand.MakeLinkButton(contextMenu)
			btn:SetHeight(ROW_H)
			contextMenu.buttons[i] = btn
		end
		btn:SetLabel(opt.label, { opt.r or Brand.HEADER_COLOR[1], opt.g or Brand.HEADER_COLOR[2], opt.b or Brand.HEADER_COLOR[3] })
		btn:SetPoint("TOPLEFT", contextMenu, "TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
		btn:SetScript("OnClick", function()
			clickCatcher:Hide()
			contextMenu:Hide()
			if opt.onClick then opt.onClick() end
		end)
		btn:Show()
		local w = btn.label:GetStringWidth() + 4
		if w > width then width = w end
	end
	for i = #options + 1, #contextMenu.buttons do
		contextMenu.buttons[i]:Hide()
	end
	for _, btn in ipairs(contextMenu.buttons) do btn:SetWidth(width) end

	contextMenu:SetSize(width + PAD * 2, #options * ROW_H + PAD * 2)

	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	contextMenu:ClearAllPoints()
	contextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)

	clickCatcher:Show()
	clickCatcher:SetScript("OnClick", function()
		clickCatcher:Hide()
		contextMenu:Hide()
	end)
	contextMenu:Show()
end
