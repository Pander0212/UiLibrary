--[[
	Toggle (switch) + Checkbox variant
	  Section:AddToggle({
	      Title, Description, Flag, Default = false, Callback = function(state) end,
	      Style = "Switch" | "Checkbox",
	      Pinnable = true,          -- pin icon / long-press -> mobile quick toggle
	      QuickTitle = "Box",       -- short label for the quick toggle
	      Icon = "eye",             -- icon on the quick toggle
	      Tooltip, IgnoreConfig, NoCallbackOnLoad,
	  })
	  Toggle:Set(bool) :Get() :Toggle() :SetPinned(bool)
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Input = Import("Input")
local Element = Import("Components/Element")

local Create = Utility.Create

local Toggle = setmetatable({}, { __index = Element })
Toggle.__index = Toggle

function Toggle.new(section: any, options: { [string]: any })
	local self = Element.new(section, options, "Toggle", Toggle)
	local o = self.Options
	self.Value = o.Default == true
	self.Style = if o.Style == "Checkbox" then "Checkbox" else "Switch"
	self.Pinnable = o.Pinnable == true

	local controlWidth = (if self.Style == "Checkbox" then 30 else 50) + (if self.Pinnable then 30 else 0) + 12
	self:_BuildRow({ ControlWidth = controlWidth })

	-- the whole row is clickable
	local hitbox = Kit.Hitbox(self.Main, 2)
	self.Hitbox = hitbox

	local control = self.Control
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = control,
	})

	if self.Pinnable then
		local pin = Create("TextButton", {
			Name = "Pin",
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			ZIndex = 3,
			Parent = control,
		})
		self.PinIcon = Kit.Icon("pin", {
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 3,
			Parent = pin,
		}, "TextMuted")
		self.Maid:Give(pin.MouseButton1Click:Connect(function()
			if not self.Disabled then
				self:SetPinned(not self:IsPinned())
			end
		end))
		Animations.AttachPress(pin, pin, 0.85)
	end

	if self.Style == "Switch" then
		local track = Create("Frame", {
			Name = "Track",
			Size = UDim2.fromOffset(40, 22),
			LayoutOrder = 2,
			ZIndex = 2,
			Parent = control,
		})
		Kit.Corner(track, "pill")
		self:_Stateful(track, "BackgroundColor3", { "ToggleOn", "ToggleOff", "ProgressGradient", "AccentGradient" }, function(T)
			if not self.Value then
				return T.ToggleOff
			end
			return if Kit.GradientOn(T, "Progress") then Kit.IDENTITY else T.ToggleOn
		end)
		self:_Stateful(track, "BackgroundTransparency", { "ToggleOnTransparency", "ToggleOffTransparency" }, function(T)
			return if self.Value then T.ToggleOnTransparency else T.ToggleOffTransparency
		end)
		local gradient = Kit.Gradient(track, "Progress", "ToggleOn", function()
			return self.Value
		end)
		table.insert(self._stateful, gradient)
		local knob = Create("Frame", {
			Name = "Knob",
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(0, 3, 0.5, 0),
			ZIndex = 3,
			Parent = track,
		})
		Kit.Corner(knob, "pill")
		Kit.Bind(knob, "BackgroundColor3", "ToggleKnob")
		self.Track = track
		self.Knob = knob
	else
		local box = Create("Frame", {
			Name = "Box",
			Size = UDim2.fromOffset(22, 22),
			LayoutOrder = 2,
			ZIndex = 2,
			Parent = control,
		})
		Kit.Corner(box, 0.5)
		self:_Stateful(box, "BackgroundColor3", { "ToggleOn", "Input" }, function(T)
			return if self.Value then T.ToggleOn else T.Input
		end)
		local stroke = Kit.Stroke(box, "Border", {
			Always = true,
			Deps = { "Border", "ToggleOn" },
			Compute = function(T)
				return if self.Value then T.ToggleOn else T.Border
			end,
		})
		table.insert(self._stateful, stroke)
		local check = Kit.Icon("check", {
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 3,
			Parent = box,
		}, "AccentText")
		self.CheckScale = Create("UIScale", { Scale = if self.Value then 1 else 0, Parent = check })
		self.Box = box
	end

	Animations.AttachPress(hitbox, self.Root, 0.97)
	self.Maid:Give(Input.Track(hitbox, {
		LongPress = 0.5,
		LongPressed = function(pos)
			if self.Pinnable and Theme.TouchMode then
				self:SetPinned(not self:IsPinned())
			else
				self:_ShowTouchTooltip(pos)
			end
		end,
		Tap = function()
			if not self.Disabled then
				Kit.Sound("Toggle")
				self:Toggle()
			end
		end,
	}))

	self:_Render(true)
	self:_Register()
	if self.Pinnable then
		Import("Mobile/QuickToggles").Attach(self)
	end
	return self
end

function Toggle:_Render(instant: boolean?)
	for _, inst in self._stateful do
		Kit.Refresh(inst, nil, instant)
	end
	if self.Knob then
		local target = if self.Value then UDim2.new(1, -19, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		if instant then
			self.Knob.Position = target
		else
			Animations.Tween(self.Knob, { Position = target }, 0.3, Enum.EasingStyle.Back)
			-- squash & stretch while moving
			self.Knob.Size = UDim2.fromOffset(20, 16)
			Animations.Tween(self.Knob, { Size = UDim2.fromOffset(16, 16) }, 0.3)
		end
	end
	if self.CheckScale then
		if instant then
			self.CheckScale.Scale = if self.Value then 1 else 0
		else
			Animations.Tween(self.CheckScale, { Scale = if self.Value then 1 else 0 }, 0.25, Enum.EasingStyle.Back)
		end
	end
end

function Toggle:Set(value: any, silent: boolean?, fromConfig: boolean?)
	local state = value == true
	if state == self.Value then
		return
	end
	self.Value = state
	self:_Render(false)
	if not silent then
		self:_Fire(state, fromConfig)
	else
		self.Changed:Fire(state)
	end
end

function Toggle:Get(): boolean
	return self.Value
end

function Toggle:Toggle()
	self:Set(not self.Value)
end

function Toggle:Deserialize(value: any)
	if type(value) == "boolean" then
		self:Set(value, false, true)
	end
end

------------------------------------------------------------------------------
-- Pinning (mobile quick toggles)
------------------------------------------------------------------------------
function Toggle:IsPinned(): boolean
	return Import("Mobile/QuickToggles").IsPinned(self)
end

function Toggle:SetPinned(pinned: boolean)
	if not self.Pinnable then
		return
	end
	Import("Mobile/QuickToggles").SetPinned(self, pinned)
end

-- called by QuickToggles when the pin state changes
function Toggle:_PinChanged(pinned: boolean)
	if self.PinIcon then
		Kit.SetIconColor(self.PinIcon, if pinned then "Accent" else "TextMuted")
	end
end

return Toggle
