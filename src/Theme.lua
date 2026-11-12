--[[
	Theme
	Single source of truth for every visual value of the library.

	* `Theme.Schema` describes every key (type, default, range, category, label).
	  The Appearance tab is generated from it, so adding a key here automatically
	  makes it editable in the menu.
	* Every colour key `X` automatically gets a companion `XTransparency` key.
	* Components never hardcode colours/sizes/fonts: they bind instance properties
	  to keys via `Theme:Bind(...)` (see ThemeRegistry) and read metrics through
	  `Theme:Metric(...)` / `Theme:TextSize(...)`.
]]

local Utility = Import("Utility")
local Signal = Import("Signal")
local Constants = Import("Constants")

type SchemaEntry = {
	Key: string,
	Type: string, -- "Color" | "Number" | "Boolean" | "Enum" | "Font" | "String" | "Asset"
	Default: any,
	Category: string,
	Section: string,
	Label: string,
	Min: number?,
	Max: number?,
	Step: number?,
	Suffix: string?,
	Options: { string }?,
	Hidden: boolean?,
	ColorOf: string?,
	Description: string?,
}

local Theme = {}

Theme.Schema = {} :: { SchemaEntry }
Theme.ByKey = {} :: { [string]: SchemaEntry }
Theme.Defaults = {} :: { [string]: any } -- schema defaults (+ developer overrides)
Theme.Values = {} :: { [string]: any } -- live values
Theme.Changed = Signal.new() -- (changedKeys: {[string]: true}, instant: boolean)
Theme.CurrentPreset = "Midnight"
Theme.TouchMode = false

-- Order of categories in the Appearance tab
Theme.Categories = {
	"Colors",
	"Gradients",
	"Background",
	"Fonts",
	"Shape",
	"Layout",
	"Transparency",
	"Animations",
	"Branding",
	"Elements",
	"Mobile",
}

-- Font families shipped with the Roblox client (rbxasset://fonts/families/<Name>.json)
Theme.FontFamilies = {
	"BuilderSans",
	"GothamSSm",
	"Montserrat",
	"Roboto",
	"RobotoCondensed",
	"Ubuntu",
	"SourceSansPro",
	"Nunito",
	"Oswald",
	"TitilliumWeb",
	"Michroma",
	"Jura",
	"Merriweather",
	"FredokaOne",
	"PressStart2P",
	"RobotoMono",
	"Inconsolata",
	"Arial",
}
Theme.FontWeights = { "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold" }
Theme.EasingStyles = { "Quint", "Quart", "Quad", "Cubic", "Sine", "Exponential", "Circular", "Back", "Linear" }

------------------------------------------------------------------------------
-- Schema definition
------------------------------------------------------------------------------
local function add(entry: SchemaEntry)
	table.insert(Theme.Schema, entry)
	Theme.ByKey[entry.Key] = entry
end

local function color(key: string, hex: string, category: string, section: string, label: string, transparency: number?)
	add({
		Key = key,
		Type = "Color",
		Default = Color3.fromHex(hex),
		Category = category,
		Section = section,
		Label = label,
	})
	add({
		Key = key .. "Transparency",
		Type = "Number",
		Default = transparency or 0,
		Min = 0,
		Max = 1,
		Step = 0.01,
		Category = category,
		Section = section,
		Label = label .. " transparency",
		Hidden = true, -- edited through the colour picker's alpha bar
		ColorOf = key,
	})
end

local function number(key, default, category, section, label, min, max, step, suffix)
	add({
		Key = key,
		Type = "Number",
		Default = default,
		Category = category,
		Section = section,
		Label = label,
		Min = min,
		Max = max,
		Step = step,
		Suffix = suffix,
	})
end

local function bool(key, default, category, section, label)
	add({ Key = key, Type = "Boolean", Default = default, Category = category, Section = section, Label = label })
end

local function enum(key, default, category, section, label, options)
	add({
		Key = key,
		Type = "Enum",
		Default = default,
		Category = category,
		Section = section,
		Label = label,
		Options = options,
	})
end

local function str(key, default, category, section, label, kind)
	add({ Key = key, Type = kind or "String", Default = default, Category = category, Section = section, Label = label })
end

-- Colours ---------------------------------------------------------------------
color("Background", "0B0D14", "Colors", "Surfaces", "Background")
color("Topbar", "10131C", "Colors", "Surfaces", "Topbar")
color("Sidebar", "0E1119", "Colors", "Surfaces", "Sidebar")
color("Surface", "171B27", "Colors", "Surfaces", "Surface (rows)")
color("Card", "121621", "Colors", "Surfaces", "Card")
color("Input", "0E1119", "Colors", "Surfaces", "Input fields")
color("Border", "232A3B", "Colors", "Surfaces", "Border")

color("Text", "E8EAF2", "Colors", "Text", "Text")
color("TextMuted", "8A91A6", "Colors", "Text", "Muted text")
color("Placeholder", "5D6479", "Colors", "Text", "Placeholder")
color("AccentText", "FFFFFF", "Colors", "Text", "Text on accent")

color("Accent", "5B7CFA", "Colors", "Accent & status", "Accent")
color("Accent2", "8B5CF6", "Colors", "Accent & status", "Accent 2")
color("Success", "22C55E", "Colors", "Accent & status", "Success")
color("Warning", "F59E0B", "Colors", "Accent & status", "Warning")
color("Danger", "EF4444", "Colors", "Accent & status", "Danger")

color("ToggleOn", "5B7CFA", "Colors", "Controls", "Toggle on")
color("ToggleOff", "2A3042", "Colors", "Controls", "Toggle off")
color("ToggleKnob", "F5F7FF", "Colors", "Controls", "Toggle knob")
color("SliderFill", "5B7CFA", "Colors", "Controls", "Slider fill")
color("SliderTrack", "232A3B", "Colors", "Controls", "Slider track")
color("Scrollbar", "2C3347", "Colors", "Controls", "Scrollbar")

color("Shadow", "000000", "Colors", "Overlays", "Shadow")
color("Overlay", "05060A", "Colors", "Overlays", "Modal backdrop", 0.35)
color("Tooltip", "1B2030", "Colors", "Overlays", "Tooltip")
color("NotificationBackground", "141824", "Colors", "Overlays", "Notification background")
color("NotificationBorder", "262D40", "Colors", "Overlays", "Notification border")
color("PreviewBackground", "0E1119", "Colors", "Overlays", "ESP preview background")
color("PreviewLight", "DCE3FF", "Colors", "Overlays", "ESP preview light")

-- Gradients -------------------------------------------------------------------
bool("AccentGradient", true, "Gradients", "Gradients", "Accent gradient (Accent -> Accent 2)")
bool("ButtonGradient", true, "Gradients", "Gradients", "Primary buttons use gradient")
bool("ProgressGradient", true, "Gradients", "Gradients", "Progress bars / sliders use gradient")
number("AccentGradientRotation", 25, "Gradients", "Gradients", "Gradient rotation", 0, 360, 1, "°")
bool("GradientAnimated", false, "Gradients", "Animation", "Animated gradient")
number("GradientSpeed", 1, "Gradients", "Animation", "Gradient animation speed", 0.1, 5, 0.1, "x")

-- Background ------------------------------------------------------------------
enum("BackgroundMode", "Solid", "Background", "Window background", "Mode", { "Solid", "Gradient", "Image" })
color("BackgroundGradientStart", "0B0D14", "Background", "Window background", "Gradient start")
color("BackgroundGradientEnd", "17123A", "Background", "Window background", "Gradient end")
number("BackgroundGradientRotation", 90, "Background", "Window background", "Gradient rotation", 0, 360, 1, "°")
str("BackgroundImage", "", "Background", "Image", "Image (rbxassetid)", "Asset")
number("BackgroundImageTransparency", 0.6, "Background", "Image", "Image transparency", 0, 1, 0.01)
enum("BackgroundImageScale", "Crop", "Background", "Image", "Scale type", { "Crop", "Fit", "Stretch", "Tile" })
number("BackgroundImageTileSize", 128, "Background", "Image", "Tile size", 16, 512, 1, "px")
bool("Blur", false, "Background", "Blur", "Blur game behind window")
number("BlurSize", 14, "Background", "Blur", "Blur strength", 1, 56, 1)

-- Fonts -----------------------------------------------------------------------
str("FontTitle", "BuilderSans", "Fonts", "Fonts", "Title font", "Font")
str("FontBody", "BuilderSans", "Fonts", "Fonts", "Body font", "Font")
str("FontMono", "RobotoMono", "Fonts", "Fonts", "Mono font", "Font")
enum("TitleWeight", "Bold", "Fonts", "Weights", "Title weight", Theme.FontWeights)
enum("BodyWeight", "Medium", "Fonts", "Weights", "Body weight", Theme.FontWeights)
number("TextScale", 1, "Fonts", "Weights", "Text size multiplier", 0.8, 1.4, 0.05, "x")

-- Shape -----------------------------------------------------------------------
number("CornerRadius", 10, "Shape", "Shape", "Corner radius", 0, 20, 1, "px")
bool("BorderEnabled", true, "Shape", "Shape", "Borders")
number("BorderThickness", 1, "Shape", "Shape", "Border thickness", 0.5, 4, 0.5, "px")
bool("ShadowEnabled", true, "Shape", "Shadow", "Window shadow")
number("ShadowStrength", 0.55, "Shape", "Shadow", "Shadow strength", 0, 1, 0.05)

-- Layout ----------------------------------------------------------------------
number("WindowWidth", 780, "Layout", "Size", "Window width", 480, 1400, 1, "px")
number("WindowHeight", 520, "Layout", "Size", "Window height", 320, 900, 1, "px")
number("UIScale", 1, "Layout", "Size", "UI scale", 0.6, 1.5, 0.05, "x")
number("SidebarWidth", 190, "Layout", "Layout", "Sidebar width", 140, 320, 1, "px")
enum("SidebarPosition", "Left", "Layout", "Layout", "Sidebar side", { "Left", "Right" })
enum("Spacing", "Normal", "Layout", "Layout", "Spacing", { "Compact", "Normal", "Large" })
enum("TabPosition", "Top", "Layout", "Layout", "Tabs position", { "Top", "Sidebar" })

-- Transparency ----------------------------------------------------------------
number("WindowTransparency", 0, "Transparency", "Transparency", "Window transparency", 0, 0.95, 0.01)
number("PanelTransparency", 0, "Transparency", "Transparency", "Panel transparency", 0, 0.95, 0.01)

-- Animations ------------------------------------------------------------------
bool("AnimationsEnabled", true, "Animations", "Animations", "Animations (off = performance mode)")
number("AnimationSpeed", 1, "Animations", "Animations", "Animation speed", 0.25, 3, 0.05, "x")
enum("EasingStyle", "Quint", "Animations", "Animations", "Easing style", Theme.EasingStyles)

-- Branding --------------------------------------------------------------------
str("Title", Constants.Name, "Branding", "Branding", "Title")
str("Subtitle", "Script Hub", "Branding", "Branding", "Subtitle")
str("Logo", "", "Branding", "Branding", "Logo (rbxassetid)", "Asset")
enum("IconSet", "Default", "Branding", "Branding", "Icon set", { "Default", "Minimal", "Letters" })
str("LoaderTitle", "", "Branding", "Loader", "Loader title (empty = Title)")
str("LoaderSubtitle", "", "Branding", "Loader", "Loader subtitle (empty = Subtitle)")
str("LoaderStatusText", "Initializing...", "Branding", "Loader", "Loader start text")

-- Elements --------------------------------------------------------------------
bool("ShowAvatar", true, "Elements", "Topbar", "Show avatar")
bool("ShowUsername", true, "Elements", "Topbar", "Show username")
enum(
	"NotificationPosition",
	"BottomRight",
	"Elements",
	"Notifications",
	"Notification position",
	{ "TopLeft", "TopRight", "BottomLeft", "BottomRight" }
)
bool("TooltipsEnabled", true, "Elements", "Feedback", "Tooltips")
bool("SoundsEnabled", false, "Elements", "Feedback", "Sound effects")
number("SoundVolume", 0.5, "Elements", "Feedback", "Volume", 0, 1, 0.05)

-- Mobile ----------------------------------------------------------------------
color("MobileButton", "171B27", "Mobile", "Colors", "Floating button")
color("QuickToggleOn", "5B7CFA", "Mobile", "Colors", "Quick toggle on")
color("QuickToggleOff", "171B27", "Mobile", "Colors", "Quick toggle off")
number("MobileButtonSize", 56, "Mobile", "Buttons", "Floating button size", 40, 90, 1, "px")
number("QuickToggleSize", 52, "Mobile", "Buttons", "Quick toggle size (M)", 36, 90, 1, "px")
enum("MobileButtonShape", "Round", "Mobile", "Buttons", "Shape", { "Round", "Square" })
number("MobileTransparency", 0.05, "Mobile", "Buttons", "Button transparency", 0, 0.9, 0.01)

for _, entry in Theme.Schema do
	Theme.Defaults[entry.Key] = entry.Default
	Theme.Values[entry.Key] = entry.Default
end

------------------------------------------------------------------------------
-- Presets (only visual categories; layout/branding/elements are kept)
------------------------------------------------------------------------------
Theme.PresetCategories = { Colors = true, Gradients = true, Background = true, Transparency = true, Mobile = true }
Theme.PresetOrder = { "Midnight", "Light", "Crimson", "Mint", "Purple", "Mono", "Glass" }

local function palette(p: { [string]: any }): { [string]: any }
	-- Mirror commonly shared colours so presets stay short
	p.ToggleOn = p.ToggleOn or p.Accent
	p.SliderFill = p.SliderFill or p.Accent
	p.QuickToggleOn = p.QuickToggleOn or p.Accent
	p.QuickToggleOff = p.QuickToggleOff or p.Surface
	p.MobileButton = p.MobileButton or p.Surface
	p.SliderTrack = p.SliderTrack or p.Border
	p.NotificationBackground = p.NotificationBackground or p.Card
	p.NotificationBorder = p.NotificationBorder or p.Border
	p.PreviewBackground = p.PreviewBackground or p.Sidebar
	p.Input = p.Input or p.Sidebar
	p.BackgroundGradientStart = p.BackgroundGradientStart or p.Background
	return p
end

Theme.Presets = {
	Midnight = {},
	Light = palette({
		Background = "F4F6FB",
		Topbar = "FFFFFF",
		Sidebar = "F8F9FC",
		Surface = "EEF1F7",
		Card = "FFFFFF",
		Input = "F3F5F9",
		Border = "DCE1EB",
		Text = "1A1F2E",
		TextMuted = "6B7287",
		Placeholder = "9AA1B3",
		AccentText = "FFFFFF",
		Accent = "4F6BF6",
		Accent2 = "8B5CF6",
		Success = "16A34A",
		Warning = "D97706",
		Danger = "DC2626",
		ToggleOff = "CBD2E0",
		ToggleKnob = "FFFFFF",
		Scrollbar = "C3CAD8",
		Shadow = "1A1F2E",
		Overlay = "1A1F2E",
		Tooltip = "FFFFFF",
		PreviewLight = "FFFFFF",
		QuickToggleOff = "FFFFFF",
		MobileButton = "FFFFFF",
		BackgroundGradientEnd = "E3E7FF",
		ShadowStrength = 0.3,
	}),
	Crimson = palette({
		Background = "0E0A0C",
		Topbar = "150F12",
		Sidebar = "120D10",
		Surface = "1E151A",
		Card = "171114",
		Border = "33212A",
		Text = "F5ECEF",
		TextMuted = "A68F98",
		Placeholder = "715D66",
		Accent = "E11D48",
		Accent2 = "F97316",
		ToggleOff = "3A262D",
		ToggleKnob = "FFF4F6",
		Scrollbar = "3A262D",
		Tooltip = "22171C",
		PreviewLight = "FFE1E8",
		BackgroundGradientEnd = "2E0B17",
	}),
	Mint = palette({
		Background = "0A100F",
		Topbar = "0E1614",
		Sidebar = "0C1412",
		Surface = "14221E",
		Card = "101B18",
		Border = "1F332D",
		Text = "E6F4EF",
		TextMuted = "86A39A",
		Placeholder = "577068",
		AccentText = "04130F",
		Accent = "10B981",
		Accent2 = "06B6D4",
		ToggleOff = "21372F",
		ToggleKnob = "F0FFF9",
		Scrollbar = "24403A",
		Tooltip = "16241F",
		PreviewLight = "DFFFF3",
		BackgroundGradientEnd = "06302B",
	}),
	Purple = palette({
		Background = "0D0A14",
		Topbar = "120E1C",
		Sidebar = "100C19",
		Surface = "1B152A",
		Card = "151022",
		Border = "2C2343",
		Text = "EEE9F8",
		TextMuted = "9A8FB5",
		Placeholder = "645A80",
		Accent = "8B5CF6",
		Accent2 = "EC4899",
		ToggleOff = "2E2545",
		ToggleKnob = "F8F4FF",
		Scrollbar = "342A4E",
		Tooltip = "1E1730",
		PreviewLight = "EDE2FF",
		BackgroundGradientEnd = "2A1050",
	}),
	Mono = palette({
		Background = "0A0A0A",
		Topbar = "111111",
		Sidebar = "0E0E0E",
		Surface = "1A1A1A",
		Card = "141414",
		Border = "2A2A2A",
		Text = "F2F2F2",
		TextMuted = "8C8C8C",
		Placeholder = "5C5C5C",
		AccentText = "0A0A0A",
		Accent = "F2F2F2",
		Accent2 = "9A9A9A",
		Success = "D4D4D4",
		Warning = "A3A3A3",
		Danger = "737373",
		ToggleOff = "3A3A3A",
		ToggleKnob = "0A0A0A",
		Scrollbar = "333333",
		Tooltip = "1C1C1C",
		PreviewLight = "FFFFFF",
		QuickToggleOn = "F2F2F2",
		BackgroundGradientEnd = "202020",
		AccentGradient = false,
		ButtonGradient = false,
		ProgressGradient = false,
	}),
	Glass = palette({
		Background = "0B1020",
		Topbar = "141B33",
		Sidebar = "121931",
		Surface = "26304F",
		Card = "1A2240",
		Border = "3A4670",
		Text = "F1F4FF",
		TextMuted = "A3ADCF",
		Placeholder = "7480A8",
		Accent = "60A5FA",
		Accent2 = "C084FC",
		ToggleOff = "3A4670",
		ToggleKnob = "FFFFFF",
		Scrollbar = "4A578A",
		Tooltip = "1A2240",
		PreviewLight = "E6EEFF",
		BackgroundGradientEnd = "2A1F5C",
		BackgroundMode = "Gradient",
		BackgroundTransparency = 0.25,
		TopbarTransparency = 0.35,
		SidebarTransparency = 0.4,
		CardTransparency = 0.35,
		SurfaceTransparency = 0.45,
		InputTransparency = 0.4,
		PanelTransparency = 0.1,
		Blur = true,
		BlurSize = 18,
	}),
}

------------------------------------------------------------------------------
-- Validation
------------------------------------------------------------------------------

-- Returns the sanitised value or nil when the value is not valid for the key
function Theme:Validate(key: string, value: any): any
	local entry = Theme.ByKey[key]
	if not entry or value == nil then
		return nil
	end
	local kind = entry.Type
	if kind == "Color" then
		if typeof(value) == "Color3" then
			return value
		end
		return Utility.HexToColor(value)
	elseif kind == "Number" then
		local n = tonumber(value)
		if not n or n ~= n then
			return nil
		end
		if entry.Min and entry.Max then
			n = math.clamp(n, entry.Min, entry.Max)
		end
		return n
	elseif kind == "Boolean" then
		return if type(value) == "boolean" then value else nil
	elseif kind == "Enum" then
		if typeof(value) == "EnumItem" then
			value = value.Name
		end
		for _, option in entry.Options :: { string } do
			if option == value then
				return value
			end
		end
		return nil
	elseif kind == "Font" then
		if typeof(value) == "EnumItem" then
			return value.Name
		end
		return if type(value) == "string" and value ~= "" then value else nil
	elseif kind == "Asset" then
		if type(value) == "number" then
			return "rbxassetid://" .. tostring(value)
		end
		if type(value) == "string" then
			if string.match(value, "^%d+$") then
				return "rbxassetid://" .. value
			end
			return value
		end
		return nil
	else
		return if type(value) == "string" then value else nil
	end
end

------------------------------------------------------------------------------
-- Get / Set
------------------------------------------------------------------------------
function Theme:Get(key: string): any
	return Theme.Values[key]
end

-- Sets one key; every bound instance animates to the new value.
function Theme:Set(key: string, value: any, instant: boolean?): boolean
	local valid = Theme:Validate(key, value)
	if valid == nil then
		warn(string.format("[%s] invalid theme value for %s: %s", Constants.Name, tostring(key), tostring(value)))
		return false
	end
	if Theme.Values[key] == valid then
		return true
	end
	Theme.Values[key] = valid
	Theme.Changed:Fire({ [key] = true }, instant == true)
	return true
end

-- Sets several keys and refreshes bindings once.
function Theme:SetMany(values: { [string]: any }, instant: boolean?): { [string]: boolean }
	local changed = {}
	for key, value in values do
		local valid = Theme:Validate(key, value)
		if valid ~= nil and Theme.Values[key] ~= valid then
			Theme.Values[key] = valid
			changed[key] = true
		end
	end
	if next(changed) then
		Theme.Changed:Fire(changed, instant == true)
	end
	return changed
end

-- Re-applies bindings for keys without changing values (e.g. device switch)
function Theme:Touch(keys: { string })
	local set = {}
	for _, key in keys do
		set[key] = true
	end
	Theme.Changed:Fire(set, false)
end

-- Developer overrides: become the new defaults (used by "reset") and live values
function Theme:SetDefaults(values: { [string]: any })
	for key, value in values do
		local valid = Theme:Validate(key, value)
		if valid ~= nil then
			Theme.Defaults[key] = valid
		end
	end
	Theme:SetMany(values, true)
end

-- Resets given keys (or everything) to defaults
function Theme:Reset(keys: { string }?, instant: boolean?)
	local values = {}
	if keys then
		for _, key in keys do
			values[key] = Theme.Defaults[key]
		end
	else
		for key, value in Theme.Defaults do
			values[key] = value
		end
		Theme.CurrentPreset = "Midnight"
	end
	Theme:SetMany(values, instant)
end

-- Returns all keys of a category / section (schema order)
function Theme:GetKeys(category: string?, section: string?): { string }
	local keys = {}
	for _, entry in Theme.Schema do
		if (category == nil or entry.Category == category) and (section == nil or entry.Section == section) then
			table.insert(keys, entry.Key)
		end
	end
	return keys
end

------------------------------------------------------------------------------
-- Presets
------------------------------------------------------------------------------
function Theme:RegisterPreset(name: string, values: { [string]: any })
	Theme.Presets[name] = values
	if not table.find(Theme.PresetOrder, name) then
		table.insert(Theme.PresetOrder, name)
	end
end

function Theme:ApplyPreset(name: string, instant: boolean?): boolean
	local preset = Theme.Presets[name]
	if not preset then
		warn(string.format("[%s] unknown theme preset '%s'", Constants.Name, tostring(name)))
		return false
	end
	local values = {}
	for _, entry in Theme.Schema do
		if Theme.PresetCategories[entry.Category] then
			local value = preset[entry.Key]
			if value == nil then
				value = entry.Default
			end
			values[entry.Key] = value
		end
	end
	-- presets may also carry non-category keys (e.g. ShadowStrength)
	for key, value in preset do
		if values[key] == nil then
			values[key] = value
		end
	end
	Theme.CurrentPreset = name
	Theme:SetMany(values, instant)
	return true
end

------------------------------------------------------------------------------
-- Serialisation
------------------------------------------------------------------------------
local function encodeValue(entry: SchemaEntry, value: any): any
	if entry.Type == "Color" then
		return Utility.ColorToHex(value)
	end
	return value
end

function Theme:Serialize(): { [string]: any }
	local values = {}
	for _, entry in Theme.Schema do
		values[entry.Key] = encodeValue(entry, Theme.Values[entry.Key])
	end
	return { Version = Constants.ThemeVersion, Preset = Theme.CurrentPreset, Values = values }
end

-- Converts a serialised theme into validated values. Unknown keys are ignored,
-- invalid or missing keys fall back to the defaults.
function Theme:Deserialize(data: any): ({ [string]: any }?, string?)
	if type(data) ~= "table" then
		return nil, "theme data is not a table"
	end
	local source = if type(data.Values) == "table" then data.Values else data
	local values = {}
	for _, entry in Theme.Schema do
		local valid = Theme:Validate(entry.Key, source[entry.Key])
		values[entry.Key] = if valid ~= nil then valid else Theme.Defaults[entry.Key]
	end
	return values
end

function Theme:ApplySerialized(data: any, instant: boolean?): boolean
	local values, err = Theme:Deserialize(data)
	if not values then
		warn("[" .. Constants.Name .. "] " .. tostring(err))
		return false
	end
	if type(data) == "table" and type(data.Preset) == "string" then
		Theme.CurrentPreset = data.Preset
	end
	Theme:SetMany(values, instant)
	return true
end

function Theme:Export(): string
	return Utility.EncodeShare("THEME", Theme:Serialize()) or ""
end

function Theme:Import(text: string): (boolean, string?)
	local ok, data = Utility.DecodeShare("THEME", text)
	if not ok then
		return false, data
	end
	if Theme:ApplySerialized(data, false) then
		return true, nil
	end
	return false, "invalid theme"
end

------------------------------------------------------------------------------
-- Derived values used by components
------------------------------------------------------------------------------
Theme.SpacingPresets = {
	Compact = { Padding = 10, Gap = 6, Row = 34, Section = 10, Inner = 8 },
	Normal = { Padding = 14, Gap = 8, Row = 38, Section = 12, Inner = 10 },
	Large = { Padding = 18, Gap = 10, Row = 44, Section = 16, Inner = 12 },
}

-- Spacing metric ("Padding" | "Gap" | "Row" | "Section" | "Inner").
-- Rows are at least 44px on touch devices.
function Theme:Metric(name: string, values: { [string]: any }?): number
	local t = values or Theme.Values
	local preset = Theme.SpacingPresets[t.Spacing] or Theme.SpacingPresets.Normal
	local value = preset[name] or 0
	if name == "Row" and Theme.TouchMode then
		value = math.max(value, 44)
	end
	return value
end

Theme.TextRoles = {
	Display = { Size = 22, Font = "Title" },
	Title = { Size = 16, Font = "Title" },
	Heading = { Size = 14, Font = "Title" },
	Body = { Size = 14, Font = "Body" },
	Small = { Size = 12, Font = "Body" },
	Tiny = { Size = 10, Font = "Body" },
	Mono = { Size = 13, Font = "Mono" },
}

function Theme:TextSize(role: string, values: { [string]: any }?): number
	local t = values or Theme.Values
	local def = Theme.TextRoles[role] or Theme.TextRoles.Body
	return math.floor(def.Size * (t.TextScale or 1) + 0.5)
end

local fontCache: { [string]: Font } = {}
function Theme.ResolveFont(family: string, weightName: string?): Font
	local cacheKey = family .. "/" .. tostring(weightName)
	local cached = fontCache[cacheKey]
	if cached then
		return cached
	end
	local weight = Enum.FontWeight.Regular
	pcall(function()
		weight = (Enum.FontWeight :: any)[weightName or "Regular"]
	end)
	local font
	if string.find(family, "^rbxasset") then
		font = Font.new(family, weight)
	elseif table.find(Theme.FontFamilies, family) then
		font = Font.new("rbxasset://fonts/families/" .. family .. ".json", weight)
	else
		local ok, result = pcall(function()
			local fromEnum = Font.fromEnum((Enum.Font :: any)[family])
			return Font.new(fromEnum.Family, weight)
		end)
		font = if ok then result else Font.new("rbxasset://fonts/families/" .. family .. ".json", weight)
	end
	fontCache[cacheKey] = font
	return font
end

function Theme:FontFor(role: string, values: { [string]: any }?): Font
	local t = values or Theme.Values
	local def = Theme.TextRoles[role] or Theme.TextRoles.Body
	if def.Font == "Title" then
		return Theme.ResolveFont(t.FontTitle, t.TitleWeight)
	elseif def.Font == "Mono" then
		return Theme.ResolveFont(t.FontMono, "Regular")
	end
	return Theme.ResolveFont(t.FontBody, if role == "Small" or role == "Tiny" then "Regular" else t.BodyWeight)
end

-- Effective transparency of a colour key on a given layer:
--   "Window"  -> colour transparency x window transparency
--   "Panel"   -> colour x window x panel transparency
--   "Free"    -> colour transparency only (overlays, notifications)
function Theme:Alpha(colorKey: string, layer: string?, values: { [string]: any }?): number
	local t = values or Theme.Values
	local own = t[colorKey .. "Transparency"] or 0
	if layer == "Free" then
		return own
	end
	local window = t.WindowTransparency or 0
	local panel = if layer == "Panel" then (t.PanelTransparency or 0) else 0
	return 1 - (1 - own) * (1 - window) * (1 - panel)
end

-- Dependencies for Theme:Alpha bindings
function Theme.AlphaDeps(colorKey: string, layer: string?): { string }
	local deps = { colorKey, colorKey .. "Transparency" }
	if layer ~= "Free" then
		table.insert(deps, "WindowTransparency")
		if layer == "Panel" then
			table.insert(deps, "PanelTransparency")
		end
	end
	return deps
end

------------------------------------------------------------------------------
-- Bindings (delegated to ThemeRegistry)
------------------------------------------------------------------------------

-- Theme:Bind(inst, "BackgroundColor3", "Card")
-- Theme:Bind(inst, "Size", {"Spacing"}, function(T) return ... end)
function Theme:Bind(inst: Instance, property: string, deps: any, compute: ((any) -> any)?, options: any?): Instance
	return Import("ThemeRegistry").Bind(inst, property, deps, compute, options)
end

-- Calls fn(changedKeys, instant) when any of `keys` changes (nil = any key)
function Theme:OnChanged(keys: any, fn: (changed: { [string]: boolean }, instant: boolean) -> ())
	local list: { string }? = if type(keys) == "string" then { keys } else keys
	return Theme.Changed:Connect(function(changed, instant)
		if list == nil then
			fn(changed, instant)
			return
		end
		for _, key in list do
			if changed[key] then
				fn(changed, instant)
				return
			end
		end
	end)
end

return Theme
