-- .luacheckrc
-- Xal's Quest Compass
--
-- Scoped to the actual WoW API calls and globals this addon uses (not a
-- copy-pasted full addon's config) - add to `globals`/`read_globals` as new
-- API calls get added, rather than pulling in a giant generic list.
std = "lua51"

-- This addon's own cross-file globals.
globals = {
    "XQC",
    "XalsQuestCompassDB",
    "SlashCmdList",
    "StaticPopupDialogs",
}

-- Read-only: real WoW client API/globals + the bundled libs' own globals.
read_globals = {
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "GameFontHighlightSmall",
    "GameFontDisableLarge",
    "GameFontDisableSmall",
    "GameFontNormal",
    "PixelUtil",
    "LibStub",
    "CreateFont",
    "CreateVector2D",
    "C_Map",
    "C_QuestLog",
    "C_TaskQuest",
    "C_DateAndTime",
    "Enum",
    "GetQuestResetTime",
    "C_GossipInfo",
    "C_Timer",
    "C_AddOns",
    "C_ChatInfo",
    "C_Container",
    "GetQuestLogTitle",
    "GetNumQuestLogEntries",
    "GetQuestGreenRange",
    "GetQuestObjectiveInfo",
    "IsQuestWatched",
    "AddQuestWatch",
    "RemoveQuestWatch",
    "GetQuestLogSpecialItemInfo",
    "GetQuestLogQuestText",
    "GetSuperTrackedQuestID",
    "SetSuperTrackedQuestID",
    "QuestUtils_GetQuestName",
    "GetQuestDifficultyColor",
    "UnitClass",
    "UnitName",
    "CUSTOM_CLASS_COLORS",
    "RAID_CLASS_COLORS",
    "PlaySound",
    "SOUNDKIT",
    "IsAddOnLoaded",
    "GetAddOnMetadata",
    "InterfaceOptions_AddCategory",
    "InterfaceOptionsFrame_OpenToCategory",
    "Settings",
    "hooksecurefunc",
    "UIDropDownMenu_SetWidth",
    "UIDropDownMenu_SetText",
    "UIDropDownMenu_Initialize",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton",
    "ToggleDropDownMenu",
    "CloseDropDownMenus",
    "ColorPickerFrame",
    "OpacitySliderFrame",
    "ColorPicker_GetPreviousValues",
    "UISpecialFrames",
    "GameTooltip_AddNormalLine",
    "IsShiftKeyDown",
    "print",
}

-- Textures/backdrop tables and long chained SetPoint calls read as "unused
-- variable"/line-length noise in generated UI code like this - not real bugs.
max_line_length = false
unused_args = false
