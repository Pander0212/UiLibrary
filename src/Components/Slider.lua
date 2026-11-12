--[[
	Slider
	  Section:AddSlider({
	      Title, Description, Flag, Min = 0, Max = 100, Increment = 1, Default = 50,
	      Suffix = "%", Decimals = nil (derived from Increment), Callback = function(v) end,
	      Tooltip, IgnoreConfig, NoCallbackOnLoad,
	  })
	Drag with mouse or touch (ancestor scrolling is locked while dragging), click the
	value to type an exact number.
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Input = Import("Input")
local Element = Import("Components/Element")

local Create = Utility.Create

local Slider = setmetatable({}, { __index = Element })
Slider.__index = Slider

local TRACK_ZONE = 18 -- vertical space reserved for the track below the title

function Slider.new(section: any, options: { [string]: any })
	local self = Element.new(section, options, "Slider", Slider)
	local o = self.Options
	self.Min = tonumber(o.Min) or 0
	self.Max = tonumber(o.Max) or 100
	if self.Max < self.Min then
		self.Min, self.Max = self.Max, self.Min
	end
	self.Increment = math.max(tonumber(o.Increment) or 1, 0)
	self.Decimals = o.Decimals or (if self.Increment > 0 then Utility.DecimalsOf(self.Increment) else 2)
	self.Suffix = o.Suffix or ""
	self.Value = self:_Clean(tonumber(o.Default) or self.Min)

	self:_BuildRow({ ControlWidth = 86, ExtraHeight = TRACK_ZONE })

	-- value box (click to edit)
	local valueBox = Kit.TextBox({
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = self.Control,
	}, "Mono")
	self.ValueBox = valueBox

	-- track
	local trackHolder = Create("Frame", {
		Name = "TrackHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, TRACK_ZONE),
		Parent = self.Main,
	})
	Kit.Padding(trackHolder, "Inner", 0)
	local track = Create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6),
		Parent = trackHolder,
	})
	Kit.Panel(track, "SliderTrack", "Free")
	Kit.Corner(track, "pill")
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	Kit.AccentFill(fill, "Progress", "SliderFill")
	Kit.Corner(fill, "pill")
	local knob = Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		ZIndex = 3,
		Parent = track,
	})
	Kit.Corner(knob, "pill")
	Kit.Bind(knob, "BackgroundColor3", "ToggleKnob")
	local knobStroke = Kit.Stroke(knob, "SliderFill", { Always = true })
	knobStroke.Thickness = 2
	Kit.Bind(knobStroke, "Thickness", { "BorderThickness" }, function()
		return 2
	end)
	local knobScale = Create("UIScale", { Parent = knob })
	self.Track, self.Fill, self.Knob, self.KnobScale = track, fill, knob, knobScale

	-- generous touch hitbox around the track
	local hitbox = Create("TextButton", {
		Name = "Hitbox",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.new(1, 12, 0, 30),
		ZIndex = 4,
		Parent = track,
	})

	local function fromPosition(pos: Vector2)
		local absPos, absSize = track.AbsolutePosition, track.AbsoluteSize
		if absSize.X <= 0 then
			return
		end
		local alpha = math.clamp((pos.X - absPos.X) / absSize.X, 0, 1)
		self:Set(self.Min + (self.Max - self.Min) * alpha, false, false, true)
	end

	self.Maid:Give(Input.Track(hitbox, {
		Threshold = 0,
		MoveBeforeThreshold = true,
		LockScroll = true,
		Began = function(pos)
			if self.Disabled then
				return
			end
			self.Dragging = true
			self:_SetState("Focus", true)
			Animations.Tween(knobScale, { Scale = 1.3 }, 0.2, Enum.EasingStyle.Back)
			fromPosition(pos)
		end,
		Moved = function(pos)
			if self.Dragging then
				fromPosition(pos)
			end
		end,
		Ended = function()
			self.Dragging = false
			self:_SetState("Focus", false)
			Animations.Tween(knobScale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
		end,
	}))
	self.Maid:Give(hitbox.MouseEnter:Connect(function()
		if not self.Dragging then
			Animations.Tween(knobScale, { Scale = 1.15 }, 0.15)
		end
	end))
	self.Maid:Give(hitbox.MouseLeave:Connect(function()
		if not self.Dragging then
			Animations.Tween(knobScale, { Scale = 1 }, 0.15)
		end
	end))

	-- typed input
	self.Maid:Give(valueBox.Focused:Connect(function()
		valueBox.Text = Utility.FormatNumber(self.Value, self.Decimals)
		self:_SetState("Focus", true)
	end))
	self.Maid:Give(valueBox.FocusLost:Connect(function()
		self:_SetState("Focus", false)
		local number = tonumber((string.gsub(valueBox.Text, "[^%d%.%-]", "")))
		if number and not self.Disabled then
			self:Set(number)
		end
		self:_RenderText()
	end))

	self:_Render(true)
	self:_Register()
	return self
end

function Slider:_Clean(value: number): number
	local v = math.clamp(value, self.Min, self.Max)
	if self.Increment > 0 then
		v = self.Min + Utility.Round(v - self.Min, self.Increment)
		v = math.clamp(v, self.Min, self.Max)
	end
	return tonumber(Utility.FormatNumber(v, self.Decimals)) or v
end

function Slider:_RenderText()
	if self.ValueBox:IsFocused() then
		return
	end
	self.ValueBox.Text = Utility.FormatNumber(self.Value, self.Decimals) .. self.Suffix
end

function Slider:_Render(instant: boolean?, fast: boolean?)
	local range = self.Max - self.Min
	local alpha = if range > 0 then (self.Value - self.Min) / range else 0
	local fillSize = UDim2.fromScale(alpha, 1)
	local knobPos = UDim2.fromScale(alpha, 0.5)
	if instant then
		self.Fill.Size = fillSize
		self.Knob.Position = knobPos
	else
		local duration = if fast then 0.08 else 0.25
		Animations.Tween(self.Fill, { Size = fillSize }, duration)
		Animations.Tween(self.Knob, { Position = knobPos }, duration)
	end
	self:_RenderText()
end

function Slider:Set(value: any, silent: boolean?, fromConfig: boolean?, dragging: boolean?)
	local number = tonumber(value)
	if not number then
		return
	end
	local clean = self:_Clean(number)
	if clean == self.Value then
		self:_RenderText()
		return
	end
	self.Value = clean
	self:_Render(false, dragging)
	if silent then
		self.Changed:Fire(clean)
	else
		self:_Fire(clean, fromConfig)
	end
end

function Slider:Get(): number
	return self.Value
end

function Slider:SetRange(min: number, max: number, increment: number?)
	self.Min, self.Max = min, max
	if increment then
		self.Increment = increment
		self.Decimals = Utility.DecimalsOf(increment)
	end
	self.Value = self:_Clean(self.Value)
	self:_Render(false)
end

function Slider:Deserialize(value: any)
	if type(value) == "number" then
		self:Set(value, false, true)
	end
end

local _ = Theme

return Slider
