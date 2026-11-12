--[[
	Icons
	Icons are referenced by name ("eye", "settings"...). The active icon set comes
	from the theme key `IconSet`. A value can be
	  * a glyph / short text (rendered with a TextLabel, tinted by the theme), or
	  * an image ("rbxassetid://123") rendered with an ImageLabel (ImageColor3 tinted).
	Register your own icons (e.g. a Lucide sprite) with Icons.Register / RegisterSet.
	A raw "rbxassetid://..." passed as icon name is used directly.
]]

local Icons = {}

Icons.Sets = {
	Default = {
		home = "⌂",
		eye = "◉",
		visuals = "◉",
		target = "⊕",
		aim = "⊕",
		combat = "⚔",
		sword = "⚔",
		player = "☺",
		user = "☺",
		users = "☺",
		settings = "⚙",
		gear = "⚙",
		palette = "◐",
		brush = "✎",
		edit = "✎",
		save = "▣",
		folder = "▤",
		file = "▢",
		star = "★",
		heart = "♥",
		bell = "✉",
		info = "ℹ",
		warning = "⚠",
		error = "✕",
		success = "✓",
		check = "✓",
		close = "✕",
		x = "✕",
		minimize = "—",
		maximize = "□",
		plus = "+",
		minus = "−",
		chevron = "›",
		["chevron-down"] = "⌄",
		["chevron-right"] = "›",
		menu = "☰",
		search = "⌕",
		pin = "⚲",
		lock = "⚿",
		key = "⚿",
		globe = "◍",
		world = "◍",
		bolt = "ϟ",
		zap = "ϟ",
		flag = "⚑",
		music = "♫",
		chart = "▤",
		stats = "▥",
		activity = "∿",
		layers = "≡",
		list = "≡",
		grid = "▦",
		move = "✥",
		copy = "⧉",
		trash = "⌫",
		refresh = "↻",
		upload = "⇪",
		download = "⇩",
		link = "∞",
		clock = "◷",
		cpu = "▩",
		shield = "⛨",
		box = "▢",
		car = "◭",
		map = "▧",
		sparkles = "✦",
		magic = "✦",
		crown = "♛",
		code = "⌘",
		keyboard = "⌨",
		mobile = "▯",
		image = "▨",
		font = "Aa",
		text = "Aa",
		layout = "▤",
		shape = "◇",
		droplet = "◒",
		gradient = "◑",
		transparency = "◌",
		animation = "≋",
		brand = "◆",
		elements = "▦",
	},
	Minimal = {
		close = "×",
		minimize = "–",
		chevron = "›",
		["chevron-down"] = "⌄",
		["chevron-right"] = "›",
		menu = "≡",
		check = "✓",
		plus = "+",
		minus = "–",
		search = "⌕",
		pin = "•",
	},
	Letters = {},
}

Icons.Custom = {} :: { [string]: string }

local function isImage(value: string): boolean
	return string.find(value, "^rbxasset") ~= nil or string.find(value, "^rbxthumb") ~= nil or string.find(value, "^http") ~= nil
end

-- Registers a single icon for every set (custom icons win over set icons)
function Icons.Register(name: string, value: string | number)
	if type(value) == "number" then
		value = "rbxassetid://" .. tostring(value)
	end
	Icons.Custom[string.lower(name)] = value :: string
end

-- Registers a whole set that can be selected with the theme key IconSet
function Icons.RegisterSet(setName: string, icons: { [string]: string | number })
	local set = {}
	for name, value in icons do
		set[string.lower(name)] = if type(value) == "number" then "rbxassetid://" .. tostring(value) else value
	end
	Icons.Sets[setName] = set
end

-- Resolves an icon name for the given set. Returns ("image" | "text", value)
function Icons.Resolve(name: string?, setName: string?): (string, string)
	if name == nil or name == "" then
		return "text", ""
	end
	local raw = name :: string
	if isImage(raw) then
		return "image", raw
	end
	if string.match(raw, "^%d+$") then
		return "image", "rbxassetid://" .. raw
	end
	local key = string.lower(raw)
	local value = Icons.Custom[key]
	if value == nil then
		local set = Icons.Sets[setName or "Default"] or Icons.Sets.Default
		value = set[key]
		if value == nil and setName ~= "Letters" then
			value = Icons.Sets.Default[key]
		end
	end
	if value == nil then
		-- unknown icon / "Letters" set: first letter of the name
		value = string.upper(string.sub(raw, 1, 1))
	end
	if isImage(value) then
		return "image", value
	end
	return "text", value
end

return Icons
