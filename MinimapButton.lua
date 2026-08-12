-- MinimapButton.lua
-- Xal's Quest Compass
--
-- The minimap launcher icon, via LibDataBroker + LibDBIcon - same
-- combination Routes/Courier use. Left-click opens Options, right-click
-- toggles the quest window - matches the left=menu/right=special-action
-- convention both of those addons use (Routes: left=Options, right=Gather
-- Tally; Courier: left=Options, right=Send Preview).
XQC = XQC or {}
XQC.MinimapButton = {}
local MB = XQC.MinimapButton

-- Full custom-shaped icon, not masked into Blizzard's standard circular
-- border - same technique Routes/Courier use (RemoveButtonBorder/
-- RemoveButtonBackground/SetButtonIcon, LibDBIcon rev 56+).
local MINIMAP_ICON = "Interface\\AddOns\\XalsQuestCompass\\Textures\\MinimapIcon_v3.png"
local MINIMAP_ICON_SIZE = 34

function MB:Register()
	local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("XalsQuestCompass", {
		type = "launcher",
		text = "Xal's Quest Compass",
		icon = MINIMAP_ICON,
		OnClick = function(_, button)
			if button == "RightButton" then
				if XQC.ToggleWindow then XQC.ToggleWindow() end
			else
				if XQC.OpenOptions then XQC.OpenOptions() end
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("Xal's Quest Compass")
			tooltip:AddLine("|cff999999Left-click|r to open settings", 1, 1, 1)
			tooltip:AddLine("|cff999999Right-click|r to toggle the quest list", 1, 1, 1)
		end,
	})

	XalsQuestCompassDB.minimap = XalsQuestCompassDB.minimap or { hide = false }
	local icon = LibStub("LibDBIcon-1.0")
	icon:Register("XalsQuestCompass", ldb, XalsQuestCompassDB.minimap)

	if icon.SetButtonSize then
		icon:SetButtonSize("XalsQuestCompass", MINIMAP_ICON_SIZE)
		icon:RemoveButtonBorder("XalsQuestCompass")
		icon:RemoveButtonBackground("XalsQuestCompass")
		icon:SetButtonIcon("XalsQuestCompass", MINIMAP_ICON, MINIMAP_ICON_SIZE, "CENTER", 0, 0)
	end
end

-- Backing the Options checkbox - LibDBIcon's own Show/Hide API, not a
-- manual texture toggle.
function MB:SetShown(shown)
	XalsQuestCompassDB.minimap = XalsQuestCompassDB.minimap or { hide = false }
	XalsQuestCompassDB.minimap.hide = not shown
	local icon = LibStub("LibDBIcon-1.0", true)
	if not icon then return end
	if shown then
		icon:Show("XalsQuestCompass")
	else
		icon:Hide("XalsQuestCompass")
	end
end
