--[[
	Kit
	Theme-bound building blocks. Every helper wires the created instance to theme
	keys through the registry, so components never contain colour/font/size literals.
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Registry = Import("ThemeRegistry")
local Icons = Import("Icons")
local Constants = Import("Constants")

local Create = Utility.Create

local Kit = {}

Kit.Create = Create

function Kit.Bind(inst: Instance, property: string, deps: any, compute: ((any) -> any)?, options: any?): Instance
	return Registry.Bind(inst, property, deps, compute, options)
end

function Kit.Refresh(inst: Instance, property: string?, instant: boolean?)
	Registry.Refresh(inst, property, instant)
end

------------------------------------------------------------------------------
-- Surfaces
------------------------------------------------------------------------------

-- Binds BackgroundColor3 + BackgroundTransparency of `inst` to a colour key.
-- layer: "Window" | "Panel" | "Free" (see Theme:Alpha)
function Kit.Panel(inst: GuiObject, colorKey: string, layer: string?): GuiObject
	Registry.Bind(inst, "BackgroundColor3", colorKey)
	Registry.Bind(inst, "BackgroundTransparency", Theme.AlphaDeps(colorKey, layer), function(T)
		return Theme:Alpha(colorKey, layer, T)
	end)
	return inst
end

-- Rounded corners bound to CornerRadius. factor scales the radius ("pill" = full round)
function Kit.Corner(inst: GuiObject, factor: any?): UICorner
	local corner = Create("UICorner", { Parent = inst })
	if factor == "pill" then
		corner.CornerRadius = UDim.new(1, 0)
	else
		local f = (factor or 1) :: number
		Registry.Bind(corner, "CornerRadius", "CornerRadius", function(T)
			return UDim.new(0, math.floor(T.CornerRadius * f + 0.5))
		end)
	end
	return corner
end

-- Border stroke bound to Border/BorderEnabled/BorderThickness.
-- options.Always: ignore BorderEnabled (focus rings), options.Compute: custom colour fn
function Kit.Stroke(inst: GuiObject, colorKey: string?, options: any?): UIStroke
	local key = colorKey or "Border"
	local stroke = Create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = inst,
	})
	local deps = options and options.Deps or { key }
	Registry.Bind(stroke, "Color", deps, options and options.Compute or function(T)
		return T[key]
	end)
	Registry.Bind(stroke, "Transparency", { key .. "Transparency", "WindowTransparency" }, function(T)
		return Theme:Alpha(key, "Window", T)
	end)
	Registry.Bind(stroke, "Thickness", { "BorderEnabled", "BorderThickness" }, function(T)
		if options and options.Always then
			return math.max(T.BorderThickness, 1)
		end
		return if T.BorderEnabled then T.BorderThickness else 0
	end)
	return stroke
end

------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------

-- Binds font, size and colour of a text instance to a text role.
function Kit.Text(inst: Instance, role: string?, colorKey: string?): Instance
	local r = role or "Body"
	Registry.Bind(inst, "FontFace", { "FontTitle", "FontBody", "FontMono", "TitleWeight", "BodyWeight" }, function(T)
		return Theme:FontFor(r, T)
	end)
	Registry.Bind(inst, "TextSize", { "TextScale" }, function(T)
		return Theme:TextSize(r, T)
	end)
	if colorKey then
		Registry.Bind(inst, "TextColor3", colorKey)
	end
	return inst
end

-- Creates a transparent TextLabel bound to a role/colour.
function Kit.Label(props: { [string]: any }, role: string?, colorKey: string?): TextLabel
	local label = Create("TextLabel", {
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for key, value in props do
		if key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	Kit.Text(label, role, colorKey or "Text")
	label.Parent = props.Parent
	return label
end

-- Same for a TextBox (input fields)
function Kit.TextBox(props: { [string]: any }, role: string?): TextBox
	local box = Create("TextBox", {
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for key, value in props do
		if key ~= "Parent" then
			(box :: any)[key] = value
		end
	end
	Kit.Text(box, role, "Text")
	Registry.Bind(box, "PlaceholderColor3", "Placeholder")
	box.Parent = props.Parent
	return box
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

-- UIPadding bound to a spacing metric (or fixed numbers when a number is passed)
function Kit.Padding(inst: Instance, metric: any, vertical: any?): UIPadding
	local padding = Create("UIPadding", { Parent = inst })
	local function resolve(m: any, T: any): number
		if type(m) == "number" then
			return m
		end
		return Theme:Metric(m, T)
	end
	local v = if vertical == nil then metric else vertical
	Registry.Bind(padding, "PaddingLeft", { "Spacing" }, function(T)
		return UDim.new(0, resolve(metric, T))
	end)
	Registry.Bind(padding, "PaddingRight", { "Spacing" }, function(T)
		return UDim.new(0, resolve(metric, T))
	end)
	Registry.Bind(padding, "PaddingTop", { "Spacing" }, function(T)
		return UDim.new(0, resolve(v, T))
	end)
	Registry.Bind(padding, "PaddingBottom", { "Spacing" }, function(T)
		return UDim.new(0, resolve(v, T))
	end)
	return padding
end

-- UIListLayout whose padding follows a spacing metric
function Kit.List(inst: Instance, direction: string?, gap: any?, props: { [string]: any }?): UIListLayout
	local layout = Create("UIListLayout", {
		FillDirection = if direction == "Horizontal" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inst,
	})
	if props then
		for key, value in props do
			(layout :: any)[key] = value
		end
	end
	local g = gap or "Gap"
	if type(g) == "number" then
		layout.Padding = UDim.new(0, g)
	else
		Registry.Bind(layout, "Padding", { "Spacing" }, function(T)
			return UDim.new(0, Theme:Metric(g, T))
		end)
	end
	return layout
end

-- ScrollingFrame with themed scrollbar
function Kit.Scrolling(props: { [string]: any }): ScrollingFrame
	local frame = Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
	})
	for key, value in props do
		if key ~= "Parent" then
			(frame :: any)[key] = value
		end
	end
	Registry.Bind(frame, "ScrollBarImageColor3", "Scrollbar")
	Registry.Bind(frame, "ScrollBarImageTransparency", "ScrollbarTransparency")
	frame.Parent = props.Parent
	return frame
end

------------------------------------------------------------------------------
-- Icons
------------------------------------------------------------------------------

-- Colour keys an icon may switch to at runtime (so theme edits refresh them)
local ICON_COLOR_KEYS = { "Text", "TextMuted", "Accent", "Accent2", "AccentText", "Success", "Warning", "Danger" }

-- Creates an icon holder (TextLabel glyph + ImageLabel) that follows IconSet.
-- Returns the holder; use Kit.SetIcon(holder, name) to change it.
function Kit.Icon(name: string?, props: { [string]: any }?, colorKey: string?): Frame
	local p = props or {}
	local holder = Create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = p.Size or UDim2.fromOffset(18, 18),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		LayoutOrder = p.LayoutOrder or 0,
		ZIndex = p.ZIndex or 1,
	})
	local glyph = Create("TextLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		ZIndex = holder.ZIndex,
		Parent = holder,
	})
	Create("UITextSizeConstraint", { MaxTextSize = 64, Parent = glyph })
	local image = Create("ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = holder.ZIndex,
		Parent = holder,
	})
	local key = colorKey or "Text"
	holder:SetAttribute("IconName", name or "")
	holder:SetAttribute("ColorKey", key)
	Registry.Bind(glyph, "FontFace", { "FontBody" }, function(T)
		return Theme.ResolveFont(T.FontBody, "Bold")
	end)
	local colorDeps = { key }
	for _, extra in ICON_COLOR_KEYS do
		table.insert(colorDeps, extra)
	end
	Registry.Bind(glyph, "TextColor3", colorDeps, function(T)
		return T[holder:GetAttribute("ColorKey") or key]
	end)
	Registry.Bind(image, "ImageColor3", colorDeps, function(T)
		return T[holder:GetAttribute("ColorKey") or key]
	end)
	Registry.Bind(glyph, "Text", { "IconSet" }, function(T)
		local kind, value = Icons.Resolve(holder:GetAttribute("IconName"), T.IconSet)
		glyph.Visible = kind == "text"
		image.Visible = kind == "image"
		if kind == "image" then
			image.Image = value
			return ""
		end
		return value
	end, { NoTween = true })
	holder.Parent = p.Parent
	return holder
end

function Kit.SetIcon(holder: Frame, name: string?)
	holder:SetAttribute("IconName", name or "")
	local glyph = holder:FindFirstChild("Glyph")
	if glyph then
		Registry.Refresh(glyph, "Text", true)
	end
end

-- Changes the colour key of an icon (e.g. active state)
function Kit.SetIconColor(holder: Frame, colorKey: string)
	holder:SetAttribute("ColorKey", colorKey)
	local glyph = holder:FindFirstChild("Glyph")
	local image = holder:FindFirstChild("Image")
	if glyph then
		Registry.Refresh(glyph, "TextColor3")
	end
	if image then
		Registry.Refresh(image, "ImageColor3")
	end
end

------------------------------------------------------------------------------
-- Gradients
------------------------------------------------------------------------------
local animatedGradients: { [UIGradient]: boolean } = setmetatable({}, { __mode = "k" }) :: any
Kit.AnimatedGradients = animatedGradients

-- Neutral multiplier: UIGradient multiplies the base colour, so a gradient-enabled
-- surface uses an identity (white) base and lets the gradient carry the theme colours.
local IDENTITY = Color3.new(1, 1, 1)

local GRADIENT_FLAG = {
	Accent = "AccentGradient",
	Button = "ButtonGradient",
	Progress = "ProgressGradient",
}

Kit.IDENTITY = IDENTITY

-- Is the gradient of a given kind active for theme values T?
function Kit.GradientOn(T: any, kind: string): boolean
	local flag = GRADIENT_FLAG[kind] or "AccentGradient"
	return T.AccentGradient == true and T[flag] == true
end

-- Adds only the UIGradient (Accent-kind colours from baseKey -> Accent2).
-- `condition()` can additionally gate it (e.g. toggle is on). Caller manages the
-- base colour (use Kit.IDENTITY while the gradient is active).
function Kit.Gradient(inst: GuiObject, kind: string, baseKey: string?, condition: (() -> boolean)?): UIGradient
	local flag = GRADIENT_FLAG[kind] or "AccentGradient"
	local base = baseKey or "Accent"
	local gradient = Create("UIGradient", { Parent = inst })
	animatedGradients[gradient] = true
	Registry.Bind(gradient, "Enabled", { flag, "AccentGradient" }, function(T)
		return Kit.GradientOn(T, kind) and (condition == nil or condition())
	end, { NoTween = true })
	Registry.Bind(gradient, "Color", { base, "Accent2" }, function(T)
		return ColorSequence.new(T[base], T.Accent2)
	end, { NoTween = true })
	Registry.Bind(gradient, "Rotation", { "AccentGradientRotation" }, function(T)
		return T.AccentGradientRotation
	end, { NoTween = true })
	return gradient
end

-- Applies an accent gradient to `inst` and manages its BackgroundColor3.
-- kind: "Accent" | "Button" | "Progress"; baseKey: solid colour when gradient is off
function Kit.AccentFill(inst: GuiObject, kind: string, baseKey: string?, layer: string?): UIGradient
	local flag = GRADIENT_FLAG[kind] or "AccentGradient"
	local base = baseKey or "Accent"
	local gradient = Kit.Gradient(inst, kind, base)
	Registry.Bind(inst, "BackgroundColor3", { base, flag, "AccentGradient" }, function(T)
		if Kit.GradientOn(T, kind) then
			return IDENTITY
		end
		return T[base]
	end)
	Registry.Bind(inst, "BackgroundTransparency", Theme.AlphaDeps(base, layer or "Free"), function(T)
		return Theme:Alpha(base, layer or "Free", T)
	end)
	return gradient
end

------------------------------------------------------------------------------
-- Shadow (layered frames, no image assets required)
------------------------------------------------------------------------------

-- Creates shadow layers inside `holder` (a transparent container that has the same
-- size as the visible panel). The panel itself must have a higher ZIndex.
function Kit.Shadow(holder: GuiObject, layers: number?, spread: number?): Frame
	local count = layers or 6
	local size = spread or 3
	local container = Create("Frame", {
		Name = "Shadow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = holder,
	})
	Registry.Bind(container, "Visible", { "ShadowEnabled" }, nil, { NoTween = true })
	for i = 1, count do
		local grow = i * size
		local layer = Create("Frame", {
			Name = "Layer" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, math.floor(i * 0.8)),
			Size = UDim2.new(1, grow * 2, 1, grow * 2),
			ZIndex = 0,
			Parent = container,
		})
		Registry.Bind(layer, "BackgroundColor3", "Shadow")
		Registry.Bind(layer, "BackgroundTransparency", { "ShadowStrength", "ShadowTransparency", "WindowTransparency" }, function(T)
			local strength = T.ShadowStrength * (1 - T.ShadowTransparency) * (1 - T.WindowTransparency)
			local falloff = (1 - (i - 1) / count) ^ 1.6
			return 1 - math.clamp(strength * 0.16 * falloff, 0, 1)
		end)
		local corner = Create("UICorner", { Parent = layer })
		Registry.Bind(corner, "CornerRadius", { "CornerRadius" }, function(T)
			return UDim.new(0, T.CornerRadius + grow)
		end)
	end
	return container
end

------------------------------------------------------------------------------
-- Dashed border (no native dashed stroke in Roblox -> small frames)
------------------------------------------------------------------------------
function Kit.Dashed(frame: GuiObject, colorKey: string?, dash: number?, gap: number?): Frame
	local key = colorKey or "Border"
	local d = dash or 6
	local g = gap or 4
	local holder = Create("Frame", {
		Name = "Dashes",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = frame.ZIndex + 1,
		Parent = frame,
	})
	local pool: { Frame } = {}
	local function dashAt(index: number): Frame
		local item = pool[index]
		if not item then
			item = Create("Frame", { ZIndex = holder.ZIndex, Parent = holder })
			Registry.Bind(item, "BackgroundColor3", key)
			Registry.Bind(item, "BackgroundTransparency", { key .. "Transparency" }, function(T)
				return T[key .. "Transparency"] or 0
			end)
			pool[index] = item
		end
		item.Visible = true
		return item
	end
	local function rebuild()
		local size = frame.AbsoluteSize
		local thickness = 1
		local index = 0
		local inset = math.min(Theme.Values.CornerRadius * 0.6, 8)
		local function run(horizontal: boolean, fixed: number, length: number)
			local pos = inset
			while pos < length - inset do
				index += 1
				local len = math.min(d, length - inset - pos)
				local item = dashAt(index)
				if horizontal then
					item.Position = UDim2.fromOffset(pos, fixed)
					item.Size = UDim2.fromOffset(len, thickness)
				else
					item.Position = UDim2.fromOffset(fixed, pos)
					item.Size = UDim2.fromOffset(thickness, len)
				end
				pos += d + g
			end
		end
		run(true, 0, size.X)
		run(true, size.Y - thickness, size.X)
		run(false, 0, size.Y)
		run(false, size.X - thickness, size.Y)
		for i = index + 1, #pool do
			pool[i].Visible = false
		end
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(rebuild)
	Registry.Bind(holder, "Name", { "CornerRadius" }, function()
		task.defer(rebuild)
		return "Dashes"
	end, { NoTween = true })
	return holder
end

------------------------------------------------------------------------------
-- Misc
------------------------------------------------------------------------------

-- Transparent full-size click catcher button
function Kit.Hitbox(parent: Instance, zIndex: number?): TextButton
	return Create("TextButton", {
		Name = "Hitbox",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex or 5,
		Parent = parent,
	})
end

local soundCache: { [string]: Sound } = {}
function Kit.Sound(name: string)
	local T = Theme.Values
	if not T.SoundsEnabled then
		return
	end
	local id = Constants.Sounds[name]
	if not id then
		return
	end
	pcall(function()
		local sound = soundCache[name]
		if not sound then
			sound = Create("Sound", { SoundId = id })
			soundCache[name] = sound
		end
		sound.Volume = T.SoundVolume
		Utility.Services.SoundService:PlayLocalSound(sound)
	end)
end

return Kit
