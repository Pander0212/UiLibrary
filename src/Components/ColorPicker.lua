--[[
	ColorPicker
	  Section:AddColorPicker({
	      Title, Description, Flag, Default = Color3, Transparency = 0 (nil = no alpha bar),
	      Rainbow = false, RainbowSpeed = 0.2, Callback = function(color, transparency) end,
	  })
	  :Set(color, transparency?) | :Set({Color = Color3|"#hex", Transparency, Rainbow})
	  :Get() -> color, transparency    :SetRainbow(bool)
	Inline panel with HSV square, hue bar, alpha bar, hex input and rainbow toggle.
	Note: the HSV square's white/black overlays are mathematically derived
	(Color3.fromHSV) - they are part of the colour model, not theme colours.
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Input = Import("Input")
local Element = Import("Components/Element")

local Create = Utility.Create
local RunService = Utility.Services.RunService

local ColorPicker = setmetatable({}, { __index = Element })
ColorPicker.__index = ColorPicker

-- HSV model constants (derived, not design colours)
local HSV_WHITE = Color3.fromHSV(0, 0, 1)
local HSV_BLACK = Color3.fromHSV(0, 0, 0)

local function hueSequence(): ColorSequence
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 % 1, 1, 1)))
	end
	return ColorSequence.new(keys)
end

------------------------------------------------------------------------------
-- Shared rainbow ticker (only runs while at least one picker uses rainbow)
------------------------------------------------------------------------------
local rainbowPickers: { [any]: boolean } = {}
local rainbowConnection: RBXScriptConnection? = nil
local lastRainbowTick = 0

local function updateRainbowTicker()
	local any = next(rainbowPickers) ~= nil
	if any and not rainbowConnection then
		rainbowConnection = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - lastRainbowTick < 1 / 30 then
				return
			end
			lastRainbowTick = now
			for picker in rainbowPickers do
				if picker.Destroyed then
					rainbowPickers[picker] = nil
				else
					local hue = (now * (picker.Options.RainbowSpeed or 0.2)) % 1
					picker:_ApplyHSV(hue, math.max(picker.S, 0.6), math.max(picker.V, 0.8), true)
				end
			end
		end)
	elseif not any and rainbowConnection then
		rainbowConnection:Disconnect()
		rainbowConnection = nil
	end
end

------------------------------------------------------------------------------
function ColorPicker.new(section: any, options: { [string]: any })
	local self = Element.new(section, options, "ColorPicker", ColorPicker)
	local o = self.Options
	local default: Color3 = if typeof(o.Default) == "Color3" then o.Default else (Utility.HexToColor(o.Default) or Theme.Values.Accent)
	self.Color = default
	self.H, self.S, self.V = default:ToHSV()
	self.HasAlpha = o.Transparency ~= nil or o.Alpha == true
	self.Transparency = math.clamp(tonumber(o.Transparency) or 0, 0, 1)
	self.Rainbow = false
	self.Opened = false

	self:_BuildRow({ ControlWidth = 64 })

	-- swatch
	local swatch = Create("TextButton", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(42, 24),
		Parent = self.Control,
	})
	Kit.Corner(swatch, 0.6)
	local swatchStroke = Kit.Stroke(swatch, "Border", {
		Always = true,
		Deps = { "Border", "Accent" },
		Compute = function(T)
			return if self.Opened then T.Accent else T.Border
		end,
	})
	table.insert(self._stateful, swatchStroke)
	self.Swatch = swatch
	Animations.AttachPress(swatch, swatch, 0.92)

	-- panel
	local panel = Create("Frame", {
		Name = "Panel",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		Visible = false,
		LayoutOrder = 2,
		Parent = self.Stack,
	})
	self.Panel = panel
	local inner = Create("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = panel,
	})
	Kit.Padding(inner, "Inner", 0)
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = inner })
	self.Inner = inner

	-- SV + hue row
	local pickRow = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 130),
		LayoutOrder = 1,
		Parent = inner,
	})
	local sv = Create("Frame", {
		Name = "SV",
		Size = UDim2.new(1, -26, 1, 0),
		Parent = pickRow,
	})
	Kit.Corner(sv, 0.5)
	local sat = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = HSV_WHITE, Parent = sv })
	Kit.Corner(sat, 0.5)
	Create("UIGradient", {
		Transparency = NumberSequence.new(0, 1),
		Parent = sat,
	})
	local val = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = HSV_BLACK, ZIndex = 2, Parent = sv })
	Kit.Corner(val, 0.5)
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(1, 0),
		Parent = val,
	})
	local svCursor = Create("Frame", {
		Name = "Cursor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = sv,
	})
	Kit.Corner(svCursor, "pill")
	local cursorStroke = Kit.Stroke(svCursor, "ToggleKnob", { Always = true })
	Kit.Bind(cursorStroke, "Thickness", { "BorderThickness" }, function()
		return 2
	end)
	local hue = Create("Frame", {
		Name = "Hue",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 16, 1, 0),
		BackgroundColor3 = HSV_WHITE,
		Parent = pickRow,
	})
	Kit.Corner(hue, "pill")
	Create("UIGradient", { Rotation = 90, Color = hueSequence(), Parent = hue })
	local hueCursor = Create("Frame", {
		Name = "Cursor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 4, 0, 6),
		ZIndex = 3,
		Parent = hue,
	})
	Kit.Corner(hueCursor, "pill")
	Kit.Bind(hueCursor, "BackgroundColor3", "ToggleKnob")
	Kit.Stroke(hueCursor, "Border", { Always = true })
	self.SV, self.SVCursor, self.Hue, self.HueCursor = sv, svCursor, hue, hueCursor

	-- alpha bar
	if self.HasAlpha then
		local alpha = Create("Frame", {
			Name = "Alpha",
			Size = UDim2.new(1, -26, 0, 12),
			LayoutOrder = 2,
			Parent = inner,
		})
		Kit.Corner(alpha, "pill")
		Kit.Stroke(alpha, "Border", { Always = true })
		local alphaGradient = Create("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = alpha })
		local alphaCursor = Create("Frame", {
			Name = "Cursor",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(6, 16),
			ZIndex = 3,
			Parent = alpha,
		})
		Kit.Corner(alphaCursor, "pill")
		Kit.Bind(alphaCursor, "BackgroundColor3", "ToggleKnob")
		Kit.Stroke(alphaCursor, "Border", { Always = true })
		self.Alpha, self.AlphaCursor, self.AlphaGradient = alpha, alphaCursor, alphaGradient
	end

	-- hex + rainbow row
	local bottom = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 3,
		Parent = inner,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = bottom,
	})
	local hexField = Create("Frame", { Size = UDim2.new(0.5, -3, 1, 0), LayoutOrder = 1, Parent = bottom })
	Kit.Panel(hexField, "Input", "Panel")
	Kit.Corner(hexField, 0.6)
	Kit.Stroke(hexField, "Border")
	local hexBox = Kit.TextBox({
		Name = "Hex",
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, 0),
		PlaceholderText = "#RRGGBB",
		Parent = hexField,
	}, "Mono")
	self.HexBox = hexBox

	local rainbowButton = Create("TextButton", { Size = UDim2.new(0.5, -3, 1, 0), LayoutOrder = 2, Parent = bottom })
	Kit.Corner(rainbowButton, 0.6)
	self:_Stateful(rainbowButton, "BackgroundColor3", { "Accent", "Input" }, function(T)
		return if self.Rainbow then T.Accent else T.Input
	end)
	self:_Stateful(rainbowButton, "BackgroundTransparency", { "Accent" }, function()
		return if self.Rainbow then 0.75 else 0
	end)
	local rainbowStroke = Kit.Stroke(rainbowButton, "Border", {
		Deps = { "Border", "Accent" },
		Compute = function(T)
			return if self.Rainbow then T.Accent else T.Border
		end,
	})
	table.insert(self._stateful, rainbowStroke)
	local rainbowLabel = Kit.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "Rainbow",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = rainbowButton,
	}, "Small", "Text")
	self:_Stateful(rainbowLabel, "TextColor3", { "Text", "Accent" }, function(T)
		return if self.Rainbow then T.Accent else T.Text
	end)
	Animations.AttachPress(rainbowButton, rainbowButton, 0.95)

	-- interactions -----------------------------------------------------------
	self.Maid:Give(swatch.MouseButton1Click:Connect(function()
		if self.Disabled then
			return
		end
		if self.Opened then
			self:Close()
		else
			self:Open()
		end
	end))

	local function svFrom(pos: Vector2)
		local p, s = sv.AbsolutePosition, sv.AbsoluteSize
		local x = math.clamp((pos.X - p.X) / math.max(s.X, 1), 0, 1)
		local y = math.clamp((pos.Y - p.Y) / math.max(s.Y, 1), 0, 1)
		self:SetRainbow(false)
		self:_ApplyHSV(self.H, x, 1 - y)
	end
	local function hueFrom(pos: Vector2)
		local p, s = hue.AbsolutePosition, hue.AbsoluteSize
		local y = math.clamp((pos.Y - p.Y) / math.max(s.Y, 1), 0, 0.999)
		self:SetRainbow(false)
		self:_ApplyHSV(y, self.S, self.V)
	end
	local svHit = Kit.Hitbox(sv, 5)
	local hueHit = Kit.Hitbox(hue, 5)
	self.Maid:Give(Input.Track(svHit, {
		Threshold = 0,
		MoveBeforeThreshold = true,
		LockScroll = true,
		Began = svFrom,
		Moved = svFrom,
	}))
	self.Maid:Give(Input.Track(hueHit, {
		Threshold = 0,
		MoveBeforeThreshold = true,
		LockScroll = true,
		Began = hueFrom,
		Moved = hueFrom,
	}))
	if self.Alpha then
		local alphaHit = Kit.Hitbox(self.Alpha, 5)
		alphaHit.Size = UDim2.new(1, 0, 1, 12)
		alphaHit.Position = UDim2.fromOffset(0, -6)
		local function alphaFrom(pos: Vector2)
			local p, s = self.Alpha.AbsolutePosition, self.Alpha.AbsoluteSize
			local x = math.clamp((pos.X - p.X) / math.max(s.X, 1), 0, 1)
			self:_SetTransparency(math.floor(x * 100 + 0.5) / 100)
		end
		self.Maid:Give(Input.Track(alphaHit, {
			Threshold = 0,
			MoveBeforeThreshold = true,
			LockScroll = true,
			Began = alphaFrom,
			Moved = alphaFrom,
		}))
	end
	self.Maid:Give(hexBox.FocusLost:Connect(function()
		local color = Utility.HexToColor(hexBox.Text)
		if color and not self.Disabled then
			self:SetRainbow(false)
			local h, s, v = color:ToHSV()
			self:_ApplyHSV(h, s, v)
		else
			self:_Render()
		end
	end))
	self.Maid:Give(rainbowButton.MouseButton1Click:Connect(function()
		if not self.Disabled then
			self:SetRainbow(not self.Rainbow)
		end
	end))

	if o.Rainbow then
		self:SetRainbow(true)
	end
	self:_Render()
	self:_Register()
	return self
end

------------------------------------------------------------------------------
function ColorPicker:_Render()
	local color = self.Color
	self.Swatch.BackgroundColor3 = color
	self.Swatch.BackgroundTransparency = self.Transparency * 0.85
	self.SV.BackgroundColor3 = Color3.fromHSV(self.H, 1, 1)
	self.SVCursor.Position = UDim2.fromScale(self.S, 1 - self.V)
	self.HueCursor.Position = UDim2.fromScale(0.5, self.H)
	if self.Alpha then
		self.Alpha.BackgroundColor3 = color
		self.AlphaCursor.Position = UDim2.fromScale(self.Transparency, 0.5)
	end
	if not self.HexBox:IsFocused() then
		self.HexBox.Text = Utility.ColorToHex(color)
	end
end

function ColorPicker:_Emit(silent: boolean?, fromConfig: boolean?)
	if silent then
		self.Changed:Fire(self.Color, self.Transparency)
		return
	end
	self.Changed:Fire(self.Color, self.Transparency)
	if self.Flag then
		Import("Config").FlagChanged:Fire(self.Flag, self.Color)
	end
	if fromConfig and self.NoCallbackOnLoad then
		return
	end
	Utility.SafeCallback(self.Callback, self.Color, self.Transparency)
end

function ColorPicker:_ApplyHSV(h: number, s: number, v: number, fromRainbow: boolean?)
	self.H, self.S, self.V = h, s, v
	local color = Color3.fromHSV(h, s, v)
	if not fromRainbow and color == self.Color then
		self:_Render()
		return
	end
	self.Color = color
	self:_Render()
	self:_Emit()
end

function ColorPicker:_SetTransparency(value: number)
	local t = math.clamp(value, 0, 1)
	if t == self.Transparency then
		return
	end
	self.Transparency = t
	self:_Render()
	self:_Emit()
end

function ColorPicker:SetRainbow(enabled: boolean)
	if self.Rainbow == enabled then
		return
	end
	self.Rainbow = enabled
	rainbowPickers[self] = if enabled then true else nil
	updateRainbowTicker()
	for _, inst in self._stateful do
		Kit.Refresh(inst)
	end
end

function ColorPicker:Open()
	if self.Opened then
		return
	end
	self.Opened = true
	self.Panel.Visible = true
	self:_SetState("Focus", true)
	task.defer(function()
		Animations.Tween(self.Panel, { Size = UDim2.new(1, 0, 0, self.Inner.AbsoluteSize.Y) }, 0.28)
	end)
end

function ColorPicker:Close()
	if not self.Opened then
		return
	end
	self.Opened = false
	self:_SetState("Focus", false)
	local tween = Animations.Tween(self.Panel, { Size = UDim2.new(1, 0, 0, 0) }, 0.22)
	local function hide()
		if not self.Opened then
			self.Panel.Visible = false
		end
	end
	if tween then
		tween.Completed:Once(hide)
	else
		hide()
	end
end

-- :Set(Color3, transparency?) or :Set({Color, Transparency, Rainbow})
function ColorPicker:Set(value: any, transparency: any?, fromConfig: boolean?)
	local color: Color3? = nil
	local t: number? = if type(transparency) == "number" then transparency else nil
	local rainbow: boolean? = nil
	if typeof(value) == "Color3" then
		color = value
	elseif type(value) == "string" then
		color = Utility.HexToColor(value)
	elseif type(value) == "table" then
		color = if typeof(value.Color) == "Color3" then value.Color else Utility.HexToColor(value.Color)
		t = tonumber(value.Transparency)
		if type(value.Rainbow) == "boolean" then
			rainbow = value.Rainbow
		end
	end
	if color then
		self.Color = color
		self.H, self.S, self.V = color:ToHSV()
	end
	if t then
		self.Transparency = math.clamp(t, 0, 1)
	end
	if rainbow ~= nil then
		self:SetRainbow(rainbow)
	end
	self:_Render()
	self:_Emit(transparency == true, fromConfig)
end

-- silent update used by the Appearance tab
function ColorPicker:SetSilent(color: Color3, transparency: number?)
	self.Color = color
	self.H, self.S, self.V = color:ToHSV()
	if transparency then
		self.Transparency = transparency
	end
	self:_Render()
end

function ColorPicker:Get(): (Color3, number)
	return self.Color, self.Transparency
end

function ColorPicker:Serialize(): any
	return { Color = Utility.ColorToHex(self.Color), Transparency = self.Transparency, Rainbow = self.Rainbow }
end

function ColorPicker:Deserialize(value: any)
	if type(value) == "table" or type(value) == "string" then
		self:Set(value, nil, true)
	end
end

function ColorPicker:Destroy()
	rainbowPickers[self] = nil
	updateRainbowTicker()
	Element.Destroy(self)
end

return ColorPicker
