-- luacheck configuration: https://luacheck.readthedocs.io
std = "lua51"
max_line_length = false
self = false -- methods such as ShouldEnable don't need to use self
exclude_files = {
	"Libs/", -- LibEditMode, included unmodified
	".release/", -- the packager's output
	".lua/", ".luarocks/", ".install/", -- tools a CI run may install into the checkout
}

globals = {
	"SimplePetTargetDB", -- SavedVariables
}

-- The game's API, as used by SimplePetTarget.lua.
read_globals = {
	"AbbreviateLargeNumbers", "AuraContainerSortDirection", "AuraContainerSortMethod", "C_CurveUtil",
	"C_LFGInfo", "C_PartyInfo", "C_PlayerInfo", "C_Secrets", "C_StringUtil", "C_Timer", "Constants",
	"CopyTable", "CreateFrame", "EditModeManagerFrame", "Enum", "FormatPercentage", "GetCVar",
	"GetCVarBool", "GetClassAtlas", "GetScreenWidth", "HUD_EDIT_MODE_SETTING_UNIT_FRAME_FRAME_SIZE",
	"InCombatLockdown", "LFG_FOLLOWER_NAME_PREFIX", "NameUtil", "PetFrame", "PowerBarColor",
	"RegionalUniqueNamesEnabled", "RegisterStateDriver", "SHOW_CASTABLE_DEBUFFS",
	"STATUS_TEXT_DISPLAY_MODE", "SecureUnitButton_OnLoad", "SetPortraitTexture", "Settings", "UIParent",
	"UnitCanAssist", "UnitCanAttack", "UnitClass", "UnitExists", "UnitHasPowerType", "UnitHealth",
	"UnitHealthMax", "UnitHealthPercent", "UnitInPartyIsAI", "UnitIsConnected", "UnitIsDead",
	"UnitIsGhost", "UnitIsHumanPlayer", "UnitIsPlayer", "UnitIsUnconscious", "UnitIsUnit", "UnitName",
	"UnitPower", "UnitPowerMax", "UnitPowerPercent", "UnitPowerType", "UnregisterStateDriver",
	"geterrorhandler", "issecretvalue",
}

-- The tests and the WoW stand-in define the game's globals themselves.
files["tests/"] = {
	ignore = { "11.", "12.", "13.", "14.", "21.", "4.." },
}
