--[[
	Constants
	Central place for branding / naming. Change `Name` and `Id` here to rebrand the
	whole library (folder names, ScreenGui names, export prefixes, default texts).
]]

local Constants = {
	-- Display name of the library (used as default window title / loader title)
	Name = "Nova UI",
	-- Technical id: ScreenGui name, root folder for configs, export prefix
	Id = "NovaUI",
	Version = "1.0.0",

	-- Bumped when the on-disk format changes (see Config migration)
	ConfigVersion = 1,
	ThemeVersion = 1,

	DefaultToggleKey = "RightShift",

	-- Window limits used by the resize handle and the appearance sliders
	MinWindowSize = Vector2.new(480, 320),
	MaxWindowSize = Vector2.new(1400, 900),

	-- Drag threshold in pixels (tap vs. drag)
	DragThreshold = 8,
	LongPressTime = 0.5,

	-- Built-in Roblox content sounds (rbxasset:// is shipped with every client)
	Sounds = {
		Click = "rbxasset://sounds/clickfast.wav",
		Toggle = "rbxasset://sounds/clickfast.wav",
		Notify = "rbxasset://sounds/electronicpingshort.wav",
		Error = "rbxasset://sounds/electronicpingshort.wav",
	},

	-- User facing strings of the built-in tabs / dialogs (override for localisation)
	Strings = {
		AppearanceTab = "Appearance",
		ConfigTab = "Settings",
		ResetSection = "Reset section",
		ResetAll = "Reset everything",
		Confirm = "Confirm",
		Cancel = "Cancel",
		Ok = "OK",
		Search = "Search...",
		None = "None",
		Hidden = "UI hidden - press %s to open it again",
		Unpin = "Unpin",
		Done = "Done",
		EditQuickToggles = "Edit quick toggles",
	},
}

return Constants
