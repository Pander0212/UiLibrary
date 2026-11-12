--[[
	Utility
	Theme-independent helpers: services, instance creation, colour/hex, Base64, JSON,
	clipboard, GUI parenting, line drawing and visibility watching.
	NOTE: this module never decides colours - every visual value comes from Theme.
]]

local Constants = Import("Constants")

local Utility = {}

------------------------------------------------------------------------------
-- Services (lazy, cloneref'd when the executor offers it)
------------------------------------------------------------------------------
local serviceCache: { [string]: Instance } = {}
local cloneRef = (typeof(cloneref) == "function" and cloneref) or function(x)
	return x
end

Utility.Services = setmetatable({}, {
	__index = function(_, name: string)
		local service = serviceCache[name]
		if not service then
			service = cloneRef(game:GetService(name))
			serviceCache[name] = service
		end
		return service
	end,
}) :: any

local Services = Utility.Services

------------------------------------------------------------------------------
-- Instances
------------------------------------------------------------------------------

-- Creates an instance. `props.Parent` is applied last. Array entries of `props`
-- are treated as children. GuiObjects get sane defaults (no border, no auto colour).
function Utility.Create(className: string, props: { [any]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	if inst:IsA("GuiButton") then
		inst.AutoButtonColor = false
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.Text = ""
		inst.RichText = false
	end
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif type(key) == "number" then
				value.Parent = inst
			else
				inst[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Utility.IsAlive(inst: Instance?): boolean
	return inst ~= nil and inst.Parent ~= nil
end

------------------------------------------------------------------------------
-- Math
------------------------------------------------------------------------------
function Utility.Round(value: number, increment: number?): number
	local inc = increment or 1
	if inc <= 0 then
		return value
	end
	return math.floor(value / inc + 0.5) * inc
end

function Utility.DecimalsOf(increment: number): number
	local text = tostring(increment)
	local dot = string.find(text, ".", 1, true)
	if not dot then
		return 0
	end
	return #text - dot
end

function Utility.FormatNumber(value: number, decimals: number): string
	if decimals <= 0 then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%." .. decimals .. "f", value)
end

function Utility.Lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

------------------------------------------------------------------------------
-- Colour helpers (pure maths on theme supplied colours)
------------------------------------------------------------------------------
function Utility.Mix(a: Color3, b: Color3, alpha: number): Color3
	return a:Lerp(b, alpha)
end

function Utility.Luminance(color: Color3): number
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

function Utility.ColorToHex(color: Color3): string
	local r = math.clamp(math.floor(color.R * 255 + 0.5), 0, 255)
	local g = math.clamp(math.floor(color.G * 255 + 0.5), 0, 255)
	local b = math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
	return string.format("#%02X%02X%02X", r, g, b)
end

function Utility.HexToColor(hex: any): Color3?
	if type(hex) ~= "string" then
		return nil
	end
	local clean = string.gsub(hex, "#", "")
	if #clean == 3 then
		clean = string.gsub(clean, ".", "%0%0")
	end
	if #clean ~= 6 or string.find(clean, "[^%x]") then
		return nil
	end
	local r = tonumber(string.sub(clean, 1, 2), 16)
	local g = tonumber(string.sub(clean, 3, 4), 16)
	local b = tonumber(string.sub(clean, 5, 6), 16)
	if not (r and g and b) then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end

------------------------------------------------------------------------------
-- Tables
------------------------------------------------------------------------------
function Utility.DeepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[Utility.DeepCopy(k)] = Utility.DeepCopy(v)
	end
	return copy
end

-- Fills missing keys of `target` from `defaults` (non destructive)
function Utility.Defaults(target: { [any]: any }?, defaults: { [any]: any }): { [any]: any }
	local result = target or {}
	for k, v in defaults do
		if result[k] == nil then
			result[k] = v
		end
	end
	return result
end

function Utility.Count(tbl: { [any]: any }): number
	local n = 0
	for _ in tbl do
		n += 1
	end
	return n
end

------------------------------------------------------------------------------
-- JSON / Base64
------------------------------------------------------------------------------
function Utility.JSONEncode(value: any): (boolean, string)
	local ok, result = pcall(function()
		return Services.HttpService:JSONEncode(value)
	end)
	return ok, result
end

function Utility.JSONDecode(text: string): (boolean, any)
	if type(text) ~= "string" or text == "" then
		return false, "empty input"
	end
	local ok, result = pcall(function()
		return Services.HttpService:JSONDecode(text)
	end)
	return ok, result
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64Lookup: { [string]: number } = {}
for i = 1, #B64 do
	B64Lookup[string.sub(B64, i, i)] = i - 1
end

function Utility.Base64Encode(data: string): string
	local out = table.create(math.ceil(#data / 3) * 4)
	for i = 1, #data, 3 do
		local a, b, c = string.byte(data, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = bit32.extract(n, 18, 6)
		local c2 = bit32.extract(n, 12, 6)
		local c3 = bit32.extract(n, 6, 6)
		local c4 = bit32.extract(n, 0, 6)
		table.insert(out, string.sub(B64, c1 + 1, c1 + 1))
		table.insert(out, string.sub(B64, c2 + 1, c2 + 1))
		table.insert(out, if b then string.sub(B64, c3 + 1, c3 + 1) else "=")
		table.insert(out, if c then string.sub(B64, c4 + 1, c4 + 1) else "=")
	end
	return table.concat(out)
end

function Utility.Base64Decode(data: string): string?
	local clean = string.gsub(data, "[^%w%+/=]", "")
	if #clean % 4 ~= 0 then
		return nil
	end
	local out = {}
	for i = 1, #clean, 4 do
		local n, pad = 0, 0
		for j = 0, 3 do
			local ch = string.sub(clean, i + j, i + j)
			if ch == "=" then
				pad += 1
				n = n * 64
			else
				local v = B64Lookup[ch]
				if v == nil then
					return nil
				end
				n = n * 64 + v
			end
		end
		local b1 = bit32.extract(n, 16, 8)
		local b2 = bit32.extract(n, 8, 8)
		local b3 = bit32.extract(n, 0, 8)
		table.insert(out, string.char(b1))
		if pad < 2 then
			table.insert(out, string.char(b2))
		end
		if pad < 1 then
			table.insert(out, string.char(b3))
		end
	end
	return table.concat(out)
end

-- Encodes a table as "<PREFIX>:<base64(json)>" for clipboard sharing
function Utility.EncodeShare(prefix: string, value: any): string?
	local ok, json = Utility.JSONEncode(value)
	if not ok then
		return nil
	end
	return Constants.Id .. "-" .. prefix .. ":" .. Utility.Base64Encode(json)
end

-- Accepts the encoded share string, plain base64 or raw JSON
function Utility.DecodeShare(prefix: string, text: string): (boolean, any)
	if type(text) ~= "string" then
		return false, "no text"
	end
	local trimmed = string.match(text, "^%s*(.-)%s*$") or text
	local header = Constants.Id .. "-" .. prefix .. ":"
	if string.sub(trimmed, 1, #header) == header then
		trimmed = string.sub(trimmed, #header + 1)
	elseif string.find(trimmed, "^[%w%-]+%-[%u]+:") then
		return false, "wrong share type"
	end
	if string.sub(trimmed, 1, 1) ~= "{" then
		local decoded = Utility.Base64Decode(trimmed)
		if not decoded then
			return false, "invalid base64"
		end
		trimmed = decoded
	end
	local ok, data = Utility.JSONDecode(trimmed)
	if not ok or type(data) ~= "table" then
		return false, "invalid json"
	end
	return true, data
end

------------------------------------------------------------------------------
-- Executor helpers
------------------------------------------------------------------------------
function Utility.SetClipboard(text: string): boolean
	local fn = (typeof(setclipboard) == "function" and setclipboard)
		or (typeof(toclipboard) == "function" and toclipboard)
		or (typeof(set_clipboard) == "function" and set_clipboard)
	if not fn then
		return false
	end
	return (pcall(fn, text))
end

-- Runs a user callback safely in its own thread and reports errors without crashing
function Utility.SafeCallback(fn: any, ...: any)
	if type(fn) ~= "function" then
		return
	end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = xpcall(function()
			fn(table.unpack(args, 1, args.n))
		end, debug.traceback)
		if not ok then
			warn("[" .. Constants.Name .. "] callback error: " .. tostring(err))
		end
	end)
end

------------------------------------------------------------------------------
-- GUI parenting
------------------------------------------------------------------------------
function Utility.GetGuiParent(): Instance
	if typeof(gethui) == "function" then
		local ok, holder = pcall(gethui)
		if ok and typeof(holder) == "Instance" then
			return holder
		end
	end
	local ok = pcall(function()
		local probe = Instance.new("Folder")
		probe.Parent = Services.CoreGui
		probe:Destroy()
	end)
	if ok then
		return Services.CoreGui
	end
	local player = Services.Players.LocalPlayer
	return player:WaitForChild("PlayerGui")
end

-- Destroys an older instance of the library (re-execution)
function Utility.DestroyOld(name: string)
	local candidates = {}
	pcall(function()
		if typeof(gethui) == "function" then
			table.insert(candidates, gethui())
		end
	end)
	pcall(function()
		table.insert(candidates, Services.CoreGui)
	end)
	pcall(function()
		table.insert(candidates, Services.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"))
	end)
	for _, holder in candidates do
		pcall(function()
			for _, child in holder:GetChildren() do
				if child.Name == name and child:IsA("ScreenGui") then
					child:Destroy()
				end
			end
		end)
	end
end

function Utility.Viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- Top-left inset (InputObject positions are relative to the inset area)
function Utility.GuiInset(): Vector2
	local ok, topLeft = pcall(function()
		return (Services.GuiService:GetGuiInset())
	end)
	return if ok and typeof(topLeft) == "Vector2" then topLeft else Vector2.zero
end

-- Converts an InputObject position into absolute ScreenGui space (IgnoreGuiInset = true)
function Utility.InputToGui(position: Vector3 | Vector2): Vector2
	local inset = Utility.GuiInset()
	return Vector2.new(position.X + inset.X, position.Y + inset.Y)
end

------------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------------

-- Positions a Frame so that it renders a line from `a` to `b` (local pixel coords)
function Utility.SetLine(line: Frame, a: Vector2, b: Vector2, thickness: number)
	local delta = b - a
	local length = delta.Magnitude
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	line.Size = UDim2.fromOffset(length, thickness)
	line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
end

------------------------------------------------------------------------------
-- Visibility watching (used to pause per-frame work while hidden)
------------------------------------------------------------------------------

-- Calls `callback(isVisible)` whenever the effective visibility of `gui` changes.
-- Returns a cleanup function.
function Utility.WatchVisible(gui: GuiObject, callback: (boolean) -> ()): () -> ()
	local connections = {}
	local last: boolean? = nil

	local function compute(): boolean
		local current: Instance? = gui
		while current do
			if current:IsA("GuiObject") and not current.Visible then
				return false
			end
			if current:IsA("LayerCollector") then
				return (current :: any).Enabled
			end
			current = current.Parent
		end
		return false
	end

	local rebind
	local function update()
		local visible = compute()
		if visible ~= last then
			last = visible
			callback(visible)
		end
	end

	rebind = function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		local current: Instance? = gui
		while current do
			if current:IsA("GuiObject") then
				table.insert(connections, current:GetPropertyChangedSignal("Visible"):Connect(update))
			elseif current:IsA("LayerCollector") then
				table.insert(connections, current:GetPropertyChangedSignal("Enabled"):Connect(update))
			end
			table.insert(connections, current:GetPropertyChangedSignal("Parent"):Connect(function()
				task.defer(rebind)
			end))
			current = current.Parent
		end
		update()
	end

	rebind()
	return function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end
end

function Utility.PlayerName(): (string, string, number)
	local player = Services.Players.LocalPlayer
	if not player then
		return "Player", "Player", 0
	end
	return player.DisplayName, player.Name, player.UserId
end

function Utility.GameKey(): string
	local name = "Game"
	pcall(function()
		local info = Services.MarketplaceService:GetProductInfo(game.PlaceId)
		if info and type(info.Name) == "string" then
			name = info.Name
		end
	end)
	name = string.gsub(name, "[^%w%s%-_]", "")
	name = string.gsub(name, "%s+", "_")
	name = string.sub(name, 1, 40)
	if name == "" then
		name = "Game"
	end
	return name .. "_" .. tostring(game.PlaceId)
end

function Utility.SanitizeFileName(name: string): string
	local clean = string.gsub(name or "", "[^%w%s%-_%.]", "")
	clean = string.match(clean, "^%s*(.-)%s*$") or ""
	return string.sub(clean, 1, 48)
end

return Utility
