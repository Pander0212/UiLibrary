--[[
	ESP Preview
	  local preview = Section:AddESPPreview({
	      Height = 300,              -- px (mobile: 240)
	      FlagPrefix = "ESP_",       -- flags read by the preview / UI:GetESPSettings()
	      Controls = true | Section, -- create the standard controls (true = same section)
	  })
	A ViewportFrame with a clone of your character (fallback: built-in block rig),
	well lit, drag/touch to rotate, scroll/pinch to zoom, slow idle rotation.
	Overlays: box (2D / Corner / Filled), name, distance, health bar (side, green->red,
	animated demo value), tracer, skeleton, chams (fill / outline + transparency).
	Everything is bound live to the flags below and saved in configs.

	Flags (prefix + name):
	  Enabled, Box, BoxStyle, BoxColor, Name, NameColor, Distance, Health, HealthSide,
	  Tracer, TracerOrigin, TracerColor, Skeleton, SkeletonColor, Chams, ChamsFill,
	  ChamsOutline, Thickness, TextSize, MaxDistance
	The preview only renders - the game ESP logic is yours: UI:GetESPSettings() / ESPPreview.ReadSettings(prefix).
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Maid = Import("Maid")
local Input = Import("Input")
local Config = Import("Config")
local State = Import("State")
local Element = Import("Components/Element")

local Create = Utility.Create
local RunService = Utility.Services.RunService
local UserInputService = Utility.Services.UserInputService

local ESPPreview = setmetatable({}, { __index = Element })
ESPPreview.__index = ESPPreview
ESPPreview.Instances = {} :: { any }

local R15_BONES = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" },
	{ "RightUpperArm", "RightLowerArm" },
	{ "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" },
	{ "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" },
	{ "RightUpperLeg", "RightLowerLeg" },
	{ "RightLowerLeg", "RightFoot" },
}
local CORNER_SIGNS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
}
local R6_BONES = {
	{ "Head", "Torso" },
	{ "Torso", "Left Arm" },
	{ "Torso", "Right Arm" },
	{ "Torso", "Left Leg" },
	{ "Torso", "Right Leg" },
}

------------------------------------------------------------------------------
-- Settings (flags with defaults)
------------------------------------------------------------------------------
local function defaults(): { [string]: any }
	local T = Theme.Values
	return {
		Enabled = true,
		Box = true,
		BoxStyle = "2D",
		BoxColor = { Color = T.Accent, Transparency = 0.85 },
		Name = true,
		NameColor = { Color = T.Text, Transparency = 0 },
		Distance = true,
		Health = true,
		HealthSide = "Left",
		Tracer = false,
		TracerOrigin = "Bottom",
		TracerColor = { Color = T.Accent2, Transparency = 0 },
		Skeleton = false,
		SkeletonColor = { Color = T.Text, Transparency = 0 },
		Chams = false,
		ChamsFill = { Color = T.Accent, Transparency = 0.5 },
		ChamsOutline = { Color = T.Text, Transparency = 0 },
		Thickness = 1.5,
		TextSize = 13,
		MaxDistance = 1000,
	}
end
ESPPreview.Defaults = defaults

local function flagValue(prefix: string, name: string, fallback: any): any
	local element = Config.Flags[prefix .. name]
	if not element then
		return fallback
	end
	if element.Type == "ColorPicker" then
		local color, transparency = element:Get()
		return { Color = color, Transparency = transparency }
	end
	local value = element:Get()
	if value == nil then
		return fallback
	end
	return value
end

-- Returns the current ESP settings as a plain table (used by UI:GetESPSettings)
function ESPPreview.ReadSettings(prefix: string?): { [string]: any }
	local p = prefix or "ESP_"
	local d = defaults()
	local s = {}
	for key, value in d do
		s[key] = flagValue(p, key, value)
	end
	return {
		Enabled = s.Enabled,
		MaxDistance = s.MaxDistance,
		TextSize = s.TextSize,
		Thickness = s.Thickness,
		Box = { Enabled = s.Box, Style = s.BoxStyle, Color = s.BoxColor.Color, FillTransparency = s.BoxColor.Transparency },
		Name = { Enabled = s.Name, Color = s.NameColor.Color, Transparency = s.NameColor.Transparency },
		Distance = { Enabled = s.Distance },
		Health = { Enabled = s.Health, Side = s.HealthSide },
		Tracer = {
			Enabled = s.Tracer,
			Origin = s.TracerOrigin,
			Color = s.TracerColor.Color,
			Transparency = s.TracerColor.Transparency,
		},
		Skeleton = { Enabled = s.Skeleton, Color = s.SkeletonColor.Color, Transparency = s.SkeletonColor.Transparency },
		Chams = {
			Enabled = s.Chams,
			FillColor = s.ChamsFill.Color,
			FillTransparency = s.ChamsFill.Transparency,
			OutlineColor = s.ChamsOutline.Color,
			OutlineTransparency = s.ChamsOutline.Transparency,
		},
	}
end

------------------------------------------------------------------------------
-- Controls (optional)
------------------------------------------------------------------------------
function ESPPreview.CreateControls(section: any, prefix: string?)
	local p = prefix or "ESP_"
	local d = defaults()
	section:AddToggle({ Title = "Enabled", Flag = p .. "Enabled", Default = d.Enabled, Pinnable = true, Icon = "eye", QuickTitle = "ESP" })
	section:AddDivider("Box")
	section:AddToggle({ Title = "Box", Flag = p .. "Box", Default = d.Box, Pinnable = true, Icon = "box" })
	section:AddDropdown({ Title = "Box style", Flag = p .. "BoxStyle", Values = { "2D", "Corner", "Filled" }, Default = d.BoxStyle })
	section:AddColorPicker({ Title = "Box color", Flag = p .. "BoxColor", Default = d.BoxColor.Color, Transparency = d.BoxColor.Transparency, Tooltip = "Alpha = fill transparency (Filled style)" })
	section:AddDivider("Info")
	section:AddToggle({ Title = "Name", Flag = p .. "Name", Default = d.Name })
	section:AddColorPicker({ Title = "Name color", Flag = p .. "NameColor", Default = d.NameColor.Color })
	section:AddToggle({ Title = "Distance", Flag = p .. "Distance", Default = d.Distance })
	section:AddToggle({ Title = "Health bar", Flag = p .. "Health", Default = d.Health })
	section:AddDropdown({ Title = "Health side", Flag = p .. "HealthSide", Values = { "Left", "Right", "Top", "Bottom" }, Default = d.HealthSide })
	section:AddDivider("Lines")
	section:AddToggle({ Title = "Tracer", Flag = p .. "Tracer", Default = d.Tracer, Pinnable = true, Icon = "link" })
	section:AddDropdown({ Title = "Tracer origin", Flag = p .. "TracerOrigin", Values = { "Bottom", "Center", "Top" }, Default = d.TracerOrigin })
	section:AddColorPicker({ Title = "Tracer color", Flag = p .. "TracerColor", Default = d.TracerColor.Color })
	section:AddToggle({ Title = "Skeleton", Flag = p .. "Skeleton", Default = d.Skeleton, Pinnable = true, Icon = "user" })
	section:AddColorPicker({ Title = "Skeleton color", Flag = p .. "SkeletonColor", Default = d.SkeletonColor.Color })
	section:AddDivider("Chams")
	section:AddToggle({ Title = "Chams", Flag = p .. "Chams", Default = d.Chams, Pinnable = true, Icon = "sparkles" })
	section:AddColorPicker({ Title = "Fill", Flag = p .. "ChamsFill", Default = d.ChamsFill.Color, Transparency = d.ChamsFill.Transparency })
	section:AddColorPicker({ Title = "Outline", Flag = p .. "ChamsOutline", Default = d.ChamsOutline.Color, Transparency = d.ChamsOutline.Transparency })
	section:AddDivider("Style")
	section:AddSlider({ Title = "Thickness", Flag = p .. "Thickness", Min = 1, Max = 4, Increment = 0.5, Default = d.Thickness, Suffix = "px" })
	section:AddSlider({ Title = "Text size", Flag = p .. "TextSize", Min = 9, Max = 22, Increment = 1, Default = d.TextSize, Suffix = "px" })
	section:AddSlider({ Title = "Max distance", Flag = p .. "MaxDistance", Min = 50, Max = 5000, Increment = 50, Default = d.MaxDistance, Suffix = "m" })
end

------------------------------------------------------------------------------
-- Model
------------------------------------------------------------------------------
local function buildBlockRig(): Model
	-- R15 shaped block dummy built from Parts (no external assets needed)
	local model = Instance.new("Model")
	model.Name = "PreviewRig"
	local partColor = Theme.Values.TextMuted
	local function part(name: string, size: Vector3, position: Vector3)
		local p = Create("Part", {
			Name = name,
			Size = size,
			CFrame = CFrame.new(position),
			Anchored = true,
			CanCollide = false,
			Color = partColor,
			Material = Enum.Material.SmoothPlastic,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
			Parent = model,
		})
		return p
	end
	local head = part("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.55, 0))
	Create("SpecialMesh", { MeshType = Enum.MeshType.Head, Scale = Vector3.new(1.25, 1.25, 1.25), Parent = head })
	part("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 3.15, 0))
	part("LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, 2.15, 0))
	part("LeftUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 3.35, 0))
	part("LeftLowerArm", Vector3.new(1, 1.1, 1), Vector3.new(-1.5, 2.2, 0))
	part("LeftHand", Vector3.new(1, 0.3, 1), Vector3.new(-1.5, 1.5, 0))
	part("RightUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(1.5, 3.35, 0))
	part("RightLowerArm", Vector3.new(1, 1.1, 1), Vector3.new(1.5, 2.2, 0))
	part("RightHand", Vector3.new(1, 0.3, 1), Vector3.new(1.5, 1.5, 0))
	part("LeftUpperLeg", Vector3.new(1, 1.2, 1), Vector3.new(-0.5, 1.35, 0))
	part("LeftLowerLeg", Vector3.new(1, 1.1, 1), Vector3.new(-0.5, 0.2, 0))
	part("LeftFoot", Vector3.new(1, 0.3, 1), Vector3.new(-0.5, -0.5, 0))
	part("RightUpperLeg", Vector3.new(1, 1.2, 1), Vector3.new(0.5, 1.35, 0))
	part("RightLowerLeg", Vector3.new(1, 1.1, 1), Vector3.new(0.5, 0.2, 0))
	part("RightFoot", Vector3.new(1, 0.3, 1), Vector3.new(0.5, -0.5, 0))
	model.PrimaryPart = model:FindFirstChild("LowerTorso") :: BasePart
	return model
end

local function cloneCharacter(): Model?
	local player = Utility.Services.Players.LocalPlayer
	local character = player and player.Character
	if not character then
		return nil
	end
	local ok, clone = pcall(function()
		local archivable = character.Archivable
		character.Archivable = true
		local c = character:Clone()
		character.Archivable = archivable
		return c
	end)
	if not ok or not clone then
		return nil
	end
	for _, item in clone:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("Sound") or item:IsA("ForceField") or item:IsA("Tool") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
		elseif item:IsA("Humanoid") then
			item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			item.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	return clone
end

------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------
function ESPPreview.new(section: any, options: any)
	local self = Element.new(section, options or {}, "ESPPreview", ESPPreview)
	local o = self.Options
	self.Prefix = o.FlagPrefix or "ESP_"
	self.Yaw = math.rad(25)
	self.Pitch = math.rad(-8)
	self.Zoom = 1
	self.LastInteraction = 0
	self.Pools = {} :: { [string]: { Frame } }
	self.RenderMaid = Maid.new()
	self.Maid:Give(self.RenderMaid)
	table.insert(ESPPreview.Instances, self)

	local root = Create("Frame", {
		Name = "ESPPreview",
		Size = UDim2.new(1, 0, 0, 300),
		ClipsDescendants = true,
		LayoutOrder = section:_NextOrder(),
	})
	self.Root = root
	self.Maid:Give(root)
	Kit.Bind(root, "Size", { "Spacing" }, function()
		return UDim2.new(1, 0, 0, o.Height or (if State.IsMobile then 240 else 300))
	end)
	Kit.Panel(root, "PreviewBackground", "Panel")
	Kit.Corner(root, 0.9)
	Kit.Stroke(root, "Border")

	local viewport = Create("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		Parent = root,
	})
	Kit.Bind(viewport, "LightColor", "PreviewLight")
	Kit.Bind(viewport, "Ambient", { "PreviewLight", "PreviewBackground" }, function(T)
		return Utility.Mix(T.PreviewBackground, T.PreviewLight, 0.65)
	end)
	self.Viewport = viewport
	local world = Create("WorldModel", { Parent = viewport })
	self.World = world
	local camera = Create("Camera", { FieldOfView = 38, Parent = viewport })
	viewport.CurrentCamera = camera
	self.Camera = camera

	local overlay = Create("Frame", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = root,
	})
	self.Overlay = overlay

	Kit.Label({
		Text = "Drag to rotate  ·  Scroll / pinch to zoom",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -20, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = root,
	}, "Tiny", "TextMuted")

	self:_LoadModel()
	self:_BindInput()

	-- per-frame updates only while visible on screen
	self.Maid:Give(Utility.WatchVisible(root, function(visible)
		self:_SetRendering(visible)
	end))

	root.Parent = section.Container

	-- optional standard controls
	if o.Controls then
		local target = if type(o.Controls) == "table" then o.Controls else section
		ESPPreview.CreateControls(target, self.Prefix)
	end
	-- re-apply chams whenever a related flag changes
	self.Maid:Give(Config.FlagChanged:Connect(function(flag)
		if type(flag) == "string" and string.sub(flag, 1, #self.Prefix) == self.Prefix then
			self._settingsDirty = true
		end
	end))
	self._settingsDirty = true
	return self
end

function ESPPreview:_LoadModel()
	if self.Model then
		self.Model:Destroy()
	end
	local model = cloneCharacter() or buildBlockRig()
	model.Parent = self.World
	self.Model = model
	self.IsR6 = model:FindFirstChild("Torso") ~= nil and model:FindFirstChild("UpperTorso") == nil
	-- normalise position: center at origin, facing +Z (towards the camera at yaw 0)
	local cf, size = model:GetBoundingBox()
	local target = CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)
	model:PivotTo(target * cf:Inverse() * model:GetPivot())
	local newCf, newSize = model:GetBoundingBox()
	self.Center = newCf.Position
	self.Size = newSize
	self.Parts = {} :: { BasePart }
	self.Original = {} :: { [BasePart]: { any } }
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(self.Parts, item)
			self.Original[item] = { item.Color, item.Material, item.Transparency }
		end
	end
	self.Highlight = Create("Highlight", {
		Enabled = false,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Parent = model,
	})
	self._chamsKey = nil
	self._settingsDirty = true
end

function ESPPreview:Reload()
	self:_LoadModel()
end

function ESPPreview:_BindInput()
	local hitbox = Kit.Hitbox(self.Root, 4)
	local scrollFrames: { ScrollingFrame } = {}
	self.Maid:Give(Input.Track(hitbox, {
		Threshold = 0,
		MoveBeforeThreshold = true,
		LockScroll = true,
		Moved = function(_, delta)
			self.LastInteraction = os.clock()
			self.Yaw -= delta.X * 0.012
			self.Pitch = math.clamp(self.Pitch - delta.Y * 0.008, math.rad(-60), math.rad(45))
		end,
	}))
	-- mouse wheel zoom (page scrolling is paused while hovering the preview)
	self.Maid:Give(hitbox.MouseEnter:Connect(function()
		local current = self.Root.Parent
		while current do
			if current:IsA("ScrollingFrame") and current.ScrollingEnabled then
				current.ScrollingEnabled = false
				table.insert(scrollFrames, current)
			end
			current = current.Parent
		end
	end))
	local function restore()
		for _, frame in scrollFrames do
			frame.ScrollingEnabled = true
		end
		table.clear(scrollFrames)
	end
	self.Maid:Give(hitbox.MouseLeave:Connect(restore))
	self.Maid:Give(restore)
	self.Maid:Give(hitbox.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self.LastInteraction = os.clock()
			self.Zoom = math.clamp(self.Zoom - input.Position.Z * 0.1, 0.55, 2)
		end
	end))
	-- pinch zoom (touch)
	local pinchStart = 1
	self.Maid:Give(UserInputService.TouchPinch:Connect(function(positions, scale, _, state)
		local first = positions[1]
		if not first then
			return
		end
		local pos = Utility.InputToGui(first)
		local absPos, absSize = self.Root.AbsolutePosition, self.Root.AbsoluteSize
		local inside = pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y
		if not inside or not self.Rendering then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStart = self.Zoom
		end
		self.LastInteraction = os.clock()
		self.Zoom = math.clamp(pinchStart / math.max(scale, 0.1), 0.55, 2)
	end))
end

------------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------------
function ESPPreview:_SetRendering(enabled: boolean)
	if enabled == self.Rendering then
		return
	end
	self.Rendering = enabled
	self.RenderMaid:Clean()
	if enabled then
		self.RenderMaid:Give(RunService.RenderStepped:Connect(function(dt)
			self:_Step(dt)
		end))
	end
end

function ESPPreview:_Pool(name: string, index: number, factory: () -> Frame): Frame
	local pool = self.Pools[name]
	if not pool then
		pool = {}
		self.Pools[name] = pool
	end
	local item = pool[index]
	if not item then
		item = factory()
		pool[index] = item
	end
	item.Visible = true
	return item
end

function ESPPreview:_HidePool(name: string, from: number?)
	local pool = self.Pools[name]
	if pool then
		for i = from or 1, #pool do
			pool[i].Visible = false
		end
	end
end

function ESPPreview:_Line(name: string, index: number, a: Vector2, b: Vector2, color: Color3, transparency: number, thickness: number)
	local line = self:_Pool(name, index, function()
		return Create("Frame", { BorderSizePixel = 0, ZIndex = 3, Parent = self.Overlay })
	end)
	line.BackgroundColor3 = color
	line.BackgroundTransparency = transparency
	Utility.SetLine(line, a, b, thickness)
	return line
end

function ESPPreview:_Label(name: string, text: string, color: Color3, size: number, position: Vector2, anchor: Vector2)
	local label = self:_Pool(name, 1, function()
		local l = Kit.Label({
			TextXAlignment = Enum.TextXAlignment.Center,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			ZIndex = 4,
			TextStrokeTransparency = 0.6,
			Parent = self.Overlay,
		}, "Small", nil)
		return l :: any
	end) :: any
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.AnchorPoint = anchor
	label.Position = UDim2.fromOffset(position.X, position.Y)
	return label
end

local function project(cf: CFrame, fov: number, size: Vector2, world: Vector3): (Vector2?, number)
	local rel = cf:PointToObjectSpace(world)
	local depth = -rel.Z
	if depth <= 0.05 then
		return nil, depth
	end
	local tanHalf = math.tan(math.rad(fov) / 2)
	local aspect = size.X / math.max(size.Y, 1)
	local x = rel.X / (depth * tanHalf * aspect)
	local y = rel.Y / (depth * tanHalf)
	return Vector2.new((x + 1) / 2 * size.X, (1 - y) / 2 * size.Y), depth
end

function ESPPreview:_ApplyChams(settings: any)
	local chams = settings.Chams
	local key = table.concat({
		tostring(settings.Enabled and chams.Enabled),
		Utility.ColorToHex(chams.FillColor),
		tostring(chams.FillTransparency),
		Utility.ColorToHex(chams.OutlineColor),
		tostring(chams.OutlineTransparency),
	}, "|")
	if key == self._chamsKey then
		return
	end
	self._chamsKey = key
	local on = settings.Enabled and chams.Enabled
	for part, original in self.Original do
		if part.Parent then
			if on then
				part.Color = chams.FillColor
				part.Material = Enum.Material.SmoothPlastic
				part.Transparency = if original[3] >= 1 then 1 else math.max(original[3], chams.FillTransparency * 0.85)
			else
				part.Color = original[1]
				part.Material = original[2]
				part.Transparency = original[3]
			end
		end
	end
	local highlight = self.Highlight
	if highlight then
		highlight.Enabled = on
		highlight.FillColor = chams.FillColor
		highlight.FillTransparency = chams.FillTransparency
		highlight.OutlineColor = chams.OutlineColor
		highlight.OutlineTransparency = chams.OutlineTransparency
	end
end

function ESPPreview:_Step(dt: number)
	local size = self.Viewport.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 or not self.Model then
		return
	end
	if self._settingsDirty or not self._settings then
		self._settings = ESPPreview.ReadSettings(self.Prefix)
		self._settingsDirty = false
	end
	local s = self._settings
	self:_ApplyChams(s)

	-- camera orbit
	if os.clock() - self.LastInteraction > 2.5 then
		self.Yaw += dt * 0.35
	end
	local center = self.Center
	local radius = math.max(self.Size.Y, self.Size.X) * 1.55 * self.Zoom
	local orbit = CFrame.new(center) * CFrame.Angles(0, self.Yaw, 0) * CFrame.Angles(self.Pitch, 0, 0)
	local camPos = (orbit * CFrame.new(0, 0, radius)).Position
	local camCf = CFrame.lookAt(camPos, center)
	self.Camera.CFrame = camCf
	local fov = self.Camera.FieldOfView

	local T = Theme.Values
	local thickness = s.Thickness or 1.5
	if not s.Enabled then
		for name in self.Pools do
			self:_HidePool(name)
		end
		return
	end

	-- 2D bounding box from part corners
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local points: { [string]: Vector2 } = {}
	for _, part in self.Parts do
		if part.Parent and part.Transparency < 1 then
			local half = part.Size / 2
			local cf = part.CFrame
			for _, sign in CORNER_SIGNS do
				local p = project(camCf, fov, size, cf:PointToWorldSpace(half * sign))
				if p then
					minX, minY = math.min(minX, p.X), math.min(minY, p.Y)
					maxX, maxY = math.max(maxX, p.X), math.max(maxY, p.Y)
				end
			end
			local center2d = project(camCf, fov, size, cf.Position)
			if center2d then
				points[part.Name] = center2d
			end
		end
	end
	if minX == math.huge then
		return
	end
	local boxPos = Vector2.new(minX, minY)
	local boxSize = Vector2.new(maxX - minX, maxY - minY)

	-- box
	local box = s.Box
	if box.Enabled then
		local frame = self:_Pool("Box", 1, function()
			local f = Create("Frame", { ZIndex = 3, Parent = self.Overlay })
			Create("UIStroke", { Name = "Stroke", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
			return f
		end)
		local stroke = frame:FindFirstChild("Stroke") :: UIStroke
		frame.Position = UDim2.fromOffset(boxPos.X, boxPos.Y)
		frame.Size = UDim2.fromOffset(boxSize.X, boxSize.Y)
		frame.BackgroundColor3 = box.Color
		frame.BackgroundTransparency = if box.Style == "Filled" then math.max(box.FillTransparency, 0.3) else 1
		stroke.Color = box.Color
		stroke.Thickness = thickness
		stroke.Enabled = box.Style ~= "Corner"
		if box.Style == "Corner" then
			local lx, ly = boxSize.X * 0.25, boxSize.Y * 0.2
			local tl, tr = boxPos, boxPos + Vector2.new(boxSize.X, 0)
			local bl, br = boxPos + Vector2.new(0, boxSize.Y), boxPos + boxSize
			local corners = {
				{ tl, tl + Vector2.new(lx, 0) },
				{ tl, tl + Vector2.new(0, ly) },
				{ tr, tr - Vector2.new(lx, 0) },
				{ tr, tr + Vector2.new(0, ly) },
				{ bl, bl + Vector2.new(lx, 0) },
				{ bl, bl - Vector2.new(0, ly) },
				{ br, br - Vector2.new(lx, 0) },
				{ br, br - Vector2.new(0, ly) },
			}
			for i, seg in corners do
				self:_Line("Corner", i, seg[1], seg[2], box.Color, 0, thickness)
			end
		else
			self:_HidePool("Corner")
		end
	else
		self:_HidePool("Box")
		self:_HidePool("Corner")
	end

	-- name / distance
	local textSize = s.TextSize or 13
	if s.Name.Enabled then
		local name = Utility.PlayerName()
		self:_Label("Name", name, s.Name.Color, textSize, Vector2.new(boxPos.X + boxSize.X / 2, boxPos.Y - 3), Vector2.new(0.5, 1))
	else
		self:_HidePool("Name")
	end
	if s.Distance.Enabled then
		local distance = math.floor(12 + (self.Zoom - 1) * 20 + 0.5)
		self:_Label("Distance", tostring(distance) .. "m", T.TextMuted, math.max(textSize - 2, 8), Vector2.new(boxPos.X + boxSize.X / 2, boxPos.Y + boxSize.Y + 3), Vector2.new(0.5, 0))
	else
		self:_HidePool("Distance")
	end

	-- health bar (animated demo value)
	if s.Health.Enabled then
		local health = 0.55 + math.sin(os.clock() * 0.8) * 0.45
		local color = T.Danger:Lerp(T.Success, health)
		local side = s.Health.Side
		local bg = self:_Pool("HealthBg", 1, function()
			local f = Create("Frame", { ZIndex = 3, Parent = self.Overlay })
			Kit.Bind(f, "BackgroundColor3", "Shadow")
			f.BackgroundTransparency = 0.35
			return f
		end)
		local fill = self:_Pool("HealthFill", 1, function()
			return Create("Frame", { ZIndex = 4, Parent = self.Overlay })
		end)
		fill.BackgroundColor3 = color
		local barThickness = 3
		local gap = 5
		if side == "Left" or side == "Right" then
			local x = if side == "Left" then boxPos.X - gap - barThickness else boxPos.X + boxSize.X + gap
			bg.Position = UDim2.fromOffset(x - 1, boxPos.Y - 1)
			bg.Size = UDim2.fromOffset(barThickness + 2, boxSize.Y + 2)
			local h = boxSize.Y * health
			fill.Position = UDim2.fromOffset(x, boxPos.Y + boxSize.Y - h)
			fill.Size = UDim2.fromOffset(barThickness, h)
		else
			local y = if side == "Top" then boxPos.Y - gap - barThickness - (if s.Name.Enabled then textSize + 2 else 0) else boxPos.Y + boxSize.Y + gap + (if s.Distance.Enabled then textSize + 2 else 0)
			bg.Position = UDim2.fromOffset(boxPos.X - 1, y - 1)
			bg.Size = UDim2.fromOffset(boxSize.X + 2, barThickness + 2)
			fill.Position = UDim2.fromOffset(boxPos.X, y)
			fill.Size = UDim2.fromOffset(boxSize.X * health, barThickness)
		end
	else
		self:_HidePool("HealthBg")
		self:_HidePool("HealthFill")
	end

	-- tracer
	if s.Tracer.Enabled then
		local origin = s.Tracer.Origin
		local from = if origin == "Top" then Vector2.new(size.X / 2, 0) elseif origin == "Center" then size / 2 else Vector2.new(size.X / 2, size.Y)
		local to = if origin == "Top" then Vector2.new(boxPos.X + boxSize.X / 2, boxPos.Y) else Vector2.new(boxPos.X + boxSize.X / 2, boxPos.Y + boxSize.Y)
		self:_Line("Tracer", 1, from, to, s.Tracer.Color, s.Tracer.Transparency, thickness)
	else
		self:_HidePool("Tracer")
	end

	-- skeleton
	if s.Skeleton.Enabled then
		local bones = if self.IsR6 then R6_BONES else R15_BONES
		local index = 0
		for _, bone in bones do
			local a, b = points[bone[1]], points[bone[2]]
			if a and b then
				index += 1
				self:_Line("Skeleton", index, a, b, s.Skeleton.Color, s.Skeleton.Transparency, thickness)
			end
		end
		self:_HidePool("Skeleton", index + 1)
	else
		self:_HidePool("Skeleton")
	end
end

function ESPPreview:GetSettings(): { [string]: any }
	return ESPPreview.ReadSettings(self.Prefix)
end

function ESPPreview:Get(): any
	return self:GetSettings()
end

function ESPPreview:Set(_value: any) end

function ESPPreview:Destroy()
	local index = table.find(ESPPreview.Instances, self)
	if index then
		table.remove(ESPPreview.Instances, index)
	end
	Element.Destroy(self)
end

return ESPPreview
