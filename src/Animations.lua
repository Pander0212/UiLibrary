--[[
	Animations
	Central tween helper. Every animation in the library goes through here so the
	theme's AnimationSpeed multiplier, EasingStyle and the performance switch
	(AnimationsEnabled = false -> values are applied instantly) apply everywhere.
]]

local Theme = Import("Theme")
local Utility = Import("Utility")

local TweenService = Utility.Services.TweenService

local Animations = {}

function Animations.Enabled(): boolean
	return Theme.Values.AnimationsEnabled ~= false
end

function Animations.Speed(): number
	return math.max(Theme.Values.AnimationSpeed or 1, 0.05)
end

-- Resolves an easing style: nil/"Theme" -> theme easing, string -> Enum, Enum passthrough
function Animations.Style(style: any): Enum.EasingStyle
	if typeof(style) == "EnumItem" then
		return style
	end
	local name = if style == nil or style == "Theme" then Theme.Values.EasingStyle else style
	local ok, result = pcall(function()
		return (Enum.EasingStyle :: any)[name]
	end)
	return if ok and result then result else Enum.EasingStyle.Quint
end

function Animations.Info(duration: number?, style: any?, direction: Enum.EasingDirection?, repeatCount: number?, reverses: boolean?): TweenInfo
	return TweenInfo.new(
		(duration or 0.2) / Animations.Speed(),
		Animations.Style(style),
		direction or Enum.EasingDirection.Out,
		repeatCount or 0,
		reverses or false
	)
end

-- Tweens `props` on `inst`. Returns the Tween (or nil when animations are off).
function Animations.Tween(inst: Instance, props: { [string]: any }, duration: number?, style: any?, direction: Enum.EasingDirection?): Tween?
	if not Animations.Enabled() then
		for key, value in props do
			pcall(function()
				(inst :: any)[key] = value
			end)
		end
		return nil
	end
	local ok, tween = pcall(TweenService.Create, TweenService, inst, Animations.Info(duration, style, direction), props)
	if not ok then
		for key, value in props do
			pcall(function()
				(inst :: any)[key] = value
			end)
		end
		return nil
	end
	tween:Play()
	return tween
end

-- Tween and yield until completed (instant when animations are off)
function Animations.TweenWait(inst: Instance, props: { [string]: any }, duration: number?, style: any?, direction: Enum.EasingDirection?)
	local tween = Animations.Tween(inst, props, duration, style, direction)
	if tween then
		tween.Completed:Wait()
	end
end

-- Scaled wait helper
function Animations.Wait(duration: number)
	if Animations.Enabled() then
		task.wait(duration / Animations.Speed())
	end
end

-- Material-like ripple. `position` is absolute (ScreenGui space).
function Animations.Ripple(button: GuiObject, position: Vector2?, colorKey: string?)
	if not Animations.Enabled() then
		return
	end
	local size = button.AbsoluteSize
	local origin = if position then position - button.AbsolutePosition else size / 2
	local diameter = math.max(size.X, size.Y) * 2.2
	local circle = Utility.Create("Frame", {
		Name = "Ripple",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(origin.X, origin.Y),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Theme.Values[colorKey or "Text"],
		BackgroundTransparency = 0.82,
		ZIndex = button.ZIndex + 5,
		Parent = button,
	})
	Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = circle })
	local tween = Animations.Tween(circle, {
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundTransparency = 1,
	}, 0.55, Enum.EasingStyle.Quad)
	if tween then
		tween.Completed:Once(function()
			circle:Destroy()
		end)
	else
		circle:Destroy()
	end
end

-- Horizontal shake (wrong key etc.)
function Animations.Shake(gui: GuiObject, intensity: number?)
	local base = gui.Position
	local amount = intensity or 8
	if not Animations.Enabled() then
		return
	end
	task.spawn(function()
		for i = 1, 6 do
			local offset = (if i % 2 == 0 then -1 else 1) * amount * (1 - i / 7)
			Animations.TweenWait(gui, { Position = base + UDim2.fromOffset(offset, 0) }, 0.045, Enum.EasingStyle.Sine)
		end
		Animations.Tween(gui, { Position = base }, 0.08, Enum.EasingStyle.Sine)
	end)
end

-- Short bounce on a UIScale
function Animations.Bounce(scale: UIScale, amount: number?)
	if not Animations.Enabled() then
		return
	end
	scale.Scale = amount or 0.85
	Animations.Tween(scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
end

-- Adds press-scale behaviour (0.97 by default) to a GuiButton. Returns the UIScale.
function Animations.AttachPress(button: GuiButton, target: GuiObject?, pressedScale: number?): UIScale
	local holder = target or button
	local scale = holder:FindFirstChildOfClass("UIScale") or Utility.Create("UIScale", { Parent = holder })
	button.MouseButton1Down:Connect(function()
		Animations.Tween(scale, { Scale = pressedScale or 0.97 }, 0.1, Enum.EasingStyle.Quad)
	end)
	local function release()
		Animations.Tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	return scale
end

return Animations
