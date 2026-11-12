--[[
	FloatingButton
	Round (or square) draggable button with the logo that opens/closes the window.
	Tap = toggle window, drag = move; on release it snaps animated to the nearest
	screen edge (avoiding thumbstick / jump button). Position is stored in the config.
	Shown when CreateWindow({FloatingButton = true}) or "Auto" on touch devices.
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Input = Import("Input")
local Maid = Import("Maid")
local State = Import("State")
local Gui = Import("Gui")
local Config = Import("Config")
local Device = Import("Mobile/Device")

local Create = Utility.Create

local FloatingButton = {}
FloatingButton.__index = FloatingButton

function FloatingButton.new(window: any, mode: any)
	local self = setmetatable({}, FloatingButton)
	self.Window = window
	self.Mode = if mode == nil then "Auto" else mode
	self.Maid = Maid.new()
	self.Side = "Right"
	self.YScale = 0.35

	local button = Create("TextButton", {
		Name = "FloatingButton",
		Size = UDim2.fromOffset(56, 56),
		Visible = false,
		ZIndex = 5,
		Parent = Gui.Layer("Mobile"),
	})
	self.Button = button
	self.Maid:Give(button)
	Kit.Bind(button, "Size", { "MobileButtonSize" }, function(T)
		return UDim2.fromOffset(T.MobileButtonSize, T.MobileButtonSize)
	end)
	Kit.Bind(button, "BackgroundColor3", "MobileButton")
	Kit.Bind(button, "BackgroundTransparency", { "MobileButtonTransparency", "MobileTransparency" }, function(T)
		return 1 - (1 - T.MobileButtonTransparency) * (1 - T.MobileTransparency)
	end)
	local corner = Create("UICorner", { Parent = button })
	Kit.Bind(corner, "CornerRadius", { "MobileButtonShape", "CornerRadius" }, function(T)
		return if T.MobileButtonShape == "Round" then UDim.new(1, 0) else UDim.new(0, T.CornerRadius + 4)
	end, { NoTween = true })
	local stroke = Kit.Stroke(button, "Accent", {
		Always = true,
		Deps = { "Accent", "Border" },
		Compute = function(T)
			return if window.Visible then T.Accent else T.Border
		end,
	})
	stroke.Thickness = 2
	Kit.Bind(stroke, "Thickness", { "BorderThickness" }, function()
		return 2
	end)
	self.Stroke = stroke

	local logo = Create("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.55, 0.55),
		ScaleType = Enum.ScaleType.Fit,
		Parent = button,
	})
	local glyph = Kit.Label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = button,
	}, "Title", "Accent")
	Kit.Bind(logo, "Image", { "Logo" }, function(T)
		logo.Visible = T.Logo ~= ""
		glyph.Visible = T.Logo == ""
		return T.Logo
	end, { NoTween = true })
	Kit.Bind(glyph, "Text", { "Title" }, function(T)
		return string.upper(string.sub(T.Title, 1, 1))
	end, { NoTween = true })

	local scale = Create("UIScale", { Parent = button })
	self.Scale = scale

	self.Maid:Give(Input.Track(button, {
		Threshold = 10,
		Began = function()
			self._start = button.AbsolutePosition
			Animations.Tween(scale, { Scale = 0.92 }, 0.1)
		end,
		Moved = function(_, _, total)
			local pos = Device.ClampToScreen(self._start + total, button.AbsoluteSize, 4)
			button.Position = UDim2.fromOffset(pos.X, pos.Y)
		end,
		Ended = function(_, wasDrag)
			Animations.Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
			if wasDrag then
				self:_Snap(true)
			end
		end,
		Tap = function()
			Kit.Sound("Click")
			Animations.Bounce(scale, 0.85)
			window:Toggle()
		end,
	}))

	self.Maid:Give(window.Opened:Connect(function()
		Kit.Refresh(stroke)
	end))
	self.Maid:Give(window.Closed:Connect(function()
		Kit.Refresh(stroke)
	end))
	self.Maid:Give(State.DeviceChanged:Connect(function()
		self:_UpdateVisibility()
	end))
	self.Maid:Give(State.ViewportChanged:Connect(function()
		self:_Snap(false)
	end))
	self.Maid:Give(Theme:OnChanged({ "MobileButtonSize" }, function()
		task.defer(function()
			self:_Snap(false)
		end)
	end))

	Config:RegisterProvider("FloatingButton", function()
		return { Side = self.Side, Y = self.YScale }
	end, function(data)
		if type(data) == "table" then
			if data.Side == "Left" or data.Side == "Right" then
				self.Side = data.Side
			end
			if type(data.Y) == "number" then
				self.YScale = math.clamp(data.Y, 0, 1)
			end
			self:_Snap(false)
		end
	end)

	self:_UpdateVisibility()
	task.defer(function()
		self:_Snap(false)
	end)
	return self
end

function FloatingButton:IsEnabled(): boolean
	if self.Mode == true then
		return true
	elseif self.Mode == false then
		return false
	end
	return State.IsMobile
end

function FloatingButton:_UpdateVisibility()
	local enabled = self:IsEnabled()
	self.Button.Visible = enabled
	if enabled then
		self:_Snap(false)
	end
end

function FloatingButton:SetMode(mode: any)
	self.Mode = mode
	self:_UpdateVisibility()
end

-- Snaps to the nearest horizontal edge. `fromDrag` recalculates side/Y from the
-- current position, otherwise the stored side/Y are applied.
function FloatingButton:_Snap(fromDrag: boolean)
	local button = self.Button
	local size = Vector2.new(Theme.Values.MobileButtonSize, Theme.Values.MobileButtonSize)
	local vp = Utility.Viewport()
	local inset = Utility.GuiInset()
	local margin = 12
	if fromDrag then
		local center = button.AbsolutePosition + size / 2
		self.Side = if center.X < vp.X / 2 then "Left" else "Right"
		local usable = math.max(vp.Y - inset.Y - size.Y, 1)
		self.YScale = math.clamp((button.AbsolutePosition.Y - inset.Y) / usable, 0, 1)
	end
	local x = if self.Side == "Left" then margin else vp.X - size.X - margin
	local y = inset.Y + self.YScale * math.max(vp.Y - inset.Y - size.Y, 0)
	local target = Device.AvoidZones(Vector2.new(x, y), size)
	local udim = UDim2.fromOffset(target.X, target.Y)
	if fromDrag then
		Animations.Tween(button, { Position = udim }, 0.4, Enum.EasingStyle.Back)
	else
		button.Position = udim
	end
end

function FloatingButton:Destroy()
	self.Maid:Clean()
end

return FloatingButton
