--[[
	Window
	  local Win = UI:CreateWindow({
	      Title = "Nova", Subtitle = "Script Hub", Logo = "rbxassetid://...",
	      Theme = "Midnight" | { Preset = "Mint", Accent = Color3.fromRGB(...), CornerRadius = 12 },
	      Size = Vector2.new(780, 520), ToggleKey = Enum.KeyCode.RightShift,
	      FloatingButton = "Auto" | true | false, CloseBehavior = "Hide" | "Destroy",
	      Notifications = true,
	  })
	Layout: Topbar (logo/title | tabs | user, bell, minimize, close), Body (Sidebar |
	Content). Draggable via the topbar, resizable via the corner grip, minimizable,
	keybind to hide/show. On touch devices / narrow windows the sidebar becomes a drawer
	and pages use a single column.
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Input = Import("Input")
local Maid = Import("Maid")
local Signal = Import("Signal")
local State = Import("State")
local Gui = Import("Gui")
local Config = Import("Config")
local Constants = Import("Constants")
local Tab = Import("Components/Tab")
local Notifications = Import("Components/Notifications")
local Dialog = Import("Components/Dialog")

local Create = Utility.Create
local UserInputService = Utility.Services.UserInputService
local Players = Utility.Services.Players

local Window = {}
Window.__index = Window

local TOPBAR_HEIGHT = 54
local MOBILE_TOPBAR_HEIGHT = 50

local LAYOUT_KEYS = {
	"WindowWidth",
	"WindowHeight",
	"UIScale",
	"SidebarWidth",
	"SidebarPosition",
	"TabPosition",
	"ShowAvatar",
	"ShowUsername",
	"Spacing",
	"TextScale",
}

------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------
function Window.new(options: { [string]: any }?)
	local o = options or {}
	local self = setmetatable({}, Window)
	self.Options = o
	self.Maid = Maid.new()
	self.Tabs = {} :: { any }
	self.ActiveTab = nil :: any
	self.Visible = false
	self.Minimized = false
	self.DrawerOpen = false
	self.Opened = Signal.new()
	self.Closed = Signal.new()
	self.CloseBehavior = o.CloseBehavior or "Hide"
	self.ToggleKey = Window._KeyName(o.ToggleKey) or Constants.DefaultToggleKey

	self:_ApplyThemeOptions(o)

	local layer = Gui.Layer("Windows")

	-- holder (theme scale) > inner (open/close pop scale) > shadow + main
	local holder = Create("Frame", {
		Name = "Window",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.Values.WindowWidth, Theme.Values.WindowHeight),
		Visible = false,
		Parent = layer,
	})
	self.Holder = holder
	self.Maid:Give(holder)
	self.Scale = Create("UIScale", { Parent = holder })

	local inner = Create("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	self.PopScale = Create("UIScale", { Parent = inner })
	Kit.Shadow(inner)

	local main = Create("Frame", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = inner,
	})
	self.Main = main
	Kit.Bind(main, "BackgroundColor3", { "Background", "BackgroundMode" }, function(T)
		return if T.BackgroundMode == "Gradient" then Kit.IDENTITY else T.Background
	end)
	Kit.Bind(main, "BackgroundTransparency", Theme.AlphaDeps("Background", "Window"), function(T)
		return Theme:Alpha("Background", "Window", T)
	end)
	Kit.Corner(main, 1.3)
	Kit.Stroke(main, "Border")

	-- background gradient / image
	local bgGradient = Create("UIGradient", { Parent = main })
	Kit.Bind(bgGradient, "Enabled", { "BackgroundMode" }, function(T)
		return T.BackgroundMode == "Gradient"
	end, { NoTween = true })
	Kit.Bind(bgGradient, "Color", { "BackgroundGradientStart", "BackgroundGradientEnd" }, function(T)
		return ColorSequence.new(T.BackgroundGradientStart, T.BackgroundGradientEnd)
	end, { NoTween = true })
	Kit.Bind(bgGradient, "Rotation", { "BackgroundGradientRotation" }, nil, { NoTween = true })
	Kit.AnimatedGradients[bgGradient] = true

	local bgImage = Create("ImageLabel", {
		Name = "BackgroundImage",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = main,
	})
	Kit.Corner(bgImage, 1.3)
	Kit.Bind(bgImage, "Visible", { "BackgroundMode", "BackgroundImage" }, function(T)
		return T.BackgroundMode == "Image" and T.BackgroundImage ~= ""
	end, { NoTween = true })
	Kit.Bind(bgImage, "Image", { "BackgroundImage" }, nil, { NoTween = true })
	Kit.Bind(bgImage, "ImageTransparency", { "BackgroundImageTransparency", "WindowTransparency" }, function(T)
		return 1 - (1 - T.BackgroundImageTransparency) * (1 - T.WindowTransparency)
	end)
	Kit.Bind(bgImage, "ScaleType", { "BackgroundImageScale" }, function(T)
		return (Enum.ScaleType :: any)[T.BackgroundImageScale] or Enum.ScaleType.Crop
	end, { NoTween = true })
	Kit.Bind(bgImage, "TileSize", { "BackgroundImageTileSize" }, function(T)
		return UDim2.fromOffset(T.BackgroundImageTileSize, T.BackgroundImageTileSize)
	end, { NoTween = true })

	self:_BuildTopbar()
	self:_BuildBody()
	self:_BuildResize()

	-- dialog layer (inside the window, above everything)
	local dialogLayer = Create("Frame", {
		Name = "DialogLayer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Visible = false,
		Parent = main,
	})
	self.DialogLayer = dialogLayer

	self:_Connect()
	self:_Layout(true)

	-- config provider: window state
	Config:RegisterProvider("Window", function()
		local p = holder.Position
		return {
			Position = { p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset },
			Minimized = self.Minimized,
			ToggleKey = self.ToggleKey,
		}
	end, function(data)
		if type(data) ~= "table" then
			return
		end
		if type(data.Position) == "table" and #data.Position == 4 then
			local p = data.Position
			if type(p[1]) == "number" and type(p[2]) == "number" and type(p[3]) == "number" and type(p[4]) == "number" then
				holder.Position = UDim2.new(p[1], p[2], p[3], p[4])
				self:_ClampPosition()
			end
		end
		if type(data.ToggleKey) == "string" then
			self:SetToggleKey(data.ToggleKey)
		end
		if type(data.Minimized) == "boolean" then
			self:Minimize(data.Minimized)
		end
	end)

	table.insert(State.Windows, self)
	State.MainWindow = State.MainWindow or self
	return self
end

function Window._KeyName(value: any): string?
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	if type(value) == "string" and value ~= "" then
		local ok = pcall(function()
			return (Enum.KeyCode :: any)[value]
		end)
		return if ok then value else nil
	end
	return nil
end

function Window:_ApplyThemeOptions(o: { [string]: any })
	local themeOption = o.Theme
	if type(themeOption) == "string" then
		Theme:ApplyPreset(themeOption, true)
	elseif type(themeOption) == "table" then
		if type(themeOption.Preset) == "string" then
			Theme:ApplyPreset(themeOption.Preset, true)
		end
		local overrides = {}
		for key, value in themeOption do
			if key ~= "Preset" then
				overrides[key] = value
			end
		end
		Theme:SetDefaults(overrides)
	end
	local branding = {}
	if o.Title then
		branding.Title = o.Title
	end
	if o.Subtitle then
		branding.Subtitle = o.Subtitle
	end
	if o.Logo then
		branding.Logo = o.Logo
	end
	if typeof(o.Size) == "Vector2" then
		branding.WindowWidth = o.Size.X
		branding.WindowHeight = o.Size.Y
	end
	if next(branding) then
		Theme:SetDefaults(branding)
	end
end

------------------------------------------------------------------------------
-- Topbar
------------------------------------------------------------------------------
local function iconButton(name: string, icon: string, parent: Instance, order: number, colorKey: string?)
	local button = Create("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(30, 30),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.Corner(button, 0.7)
	local hovered = false
	Kit.Bind(button, "BackgroundColor3", { "Surface" }, nil)
	Kit.Bind(button, "BackgroundTransparency", { "Surface" }, function()
		return if hovered then 0 else 1
	end)
	local glyph = Kit.Icon(icon, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		Parent = button,
	}, colorKey or "TextMuted")
	button.MouseEnter:Connect(function()
		hovered = true
		Kit.Refresh(button)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		Kit.Refresh(button)
	end)
	Animations.AttachPress(button, button, 0.9)
	return button, glyph
end

function Window:_BuildTopbar()
	local main = self.Main
	local topbar = Create("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		ZIndex = 2,
		Parent = main,
	})
	Kit.Panel(topbar, "Topbar", "Panel")
	self.Topbar = topbar
	local line = Create("Frame", {
		Name = "Line",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = topbar,
	})
	Kit.Bind(line, "BackgroundColor3", "Border")
	Kit.Bind(line, "BackgroundTransparency", { "BorderEnabled", "BorderTransparency" }, function(T)
		return if T.BorderEnabled then T.BorderTransparency else 1
	end)

	-- left: menu, logo, title
	local left = Create("Frame", {
		Name = "Left",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = topbar,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = left,
	})
	Create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 8), Parent = left })
	self.TopLeft = left

	local menuButton = iconButton("Menu", "menu", left, 0, "Text")
	menuButton.Visible = false
	self.MenuButton = menuButton
	self.Maid:Give(menuButton.MouseButton1Click:Connect(function()
		self:ToggleDrawer()
	end))

	local logo = Create("Frame", {
		Name = "Logo",
		Size = UDim2.fromOffset(32, 32),
		LayoutOrder = 1,
		Parent = left,
	})
	Kit.AccentFill(logo, "Accent")
	Kit.Corner(logo, 0.8)
	local logoImage = Create("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -6, 1, -6),
		ScaleType = Enum.ScaleType.Fit,
		Parent = logo,
	})
	Kit.Corner(logoImage, 0.6)
	local logoGlyph = Kit.Label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = logo,
	}, "Title", "AccentText")
	Kit.Bind(logoImage, "Image", { "Logo" }, function(T)
		logoImage.Visible = T.Logo ~= ""
		logoGlyph.Visible = T.Logo == ""
		return T.Logo
	end, { NoTween = true })
	Kit.Bind(logoGlyph, "Text", { "Title" }, function(T)
		return string.upper(string.sub(T.Title, 1, 1))
	end, { NoTween = true })

	local titles = Create("Frame", {
		Name = "Titles",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = left,
	})
	Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = titles,
	})
	local title = Kit.Label({
		Size = UDim2.new(0, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = titles,
	}, "Title", "Text")
	Kit.Bind(title, "Text", { "Title" }, nil, { NoTween = true })
	local subtitle = Kit.Label({
		Size = UDim2.new(0, 0, 0, 13),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = titles,
	}, "Tiny", "TextMuted")
	Kit.Bind(subtitle, "Text", { "Subtitle" }, nil, { NoTween = true })
	Kit.Bind(subtitle, "Visible", { "Subtitle" }, function(T)
		return T.Subtitle ~= ""
	end, { NoTween = true })
	self.Titles = titles

	-- right: user, bell, minimize, close
	local right = Create("Frame", {
		Name = "Right",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = topbar,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = right,
	})
	Create("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingLeft = UDim.new(0, 8), Parent = right })
	self.TopRight = right

	local user = Create("Frame", {
		Name = "User",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = right,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = user,
	})
	Create("UIPadding", { PaddingRight = UDim.new(0, 6), Parent = user })
	local avatar = Create("ImageLabel", {
		Name = "Avatar",
		Size = UDim2.fromOffset(30, 30),
		LayoutOrder = 1,
		Parent = user,
	})
	Kit.Panel(avatar, "Surface", "Free")
	Kit.Corner(avatar, "pill")
	Kit.Stroke(avatar, "Accent", { Always = true })
	local onlineDot = Create("Frame", {
		Name = "Online",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 1, 1, 1),
		Size = UDim2.fromOffset(9, 9),
		ZIndex = 3,
		Parent = avatar,
	})
	Kit.Bind(onlineDot, "BackgroundColor3", "Success")
	Kit.Corner(onlineDot, "pill")
	local dotStroke = Create("UIStroke", { Thickness = 2, Parent = onlineDot })
	Kit.Bind(dotStroke, "Color", "Topbar")
	local displayName, userName, userId = Utility.PlayerName()
	local names = Create("Frame", {
		Name = "Names",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = user,
	})
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = names })
	Kit.Label({
		Text = displayName,
		Size = UDim2.new(0, 0, 0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = names,
	}, "Heading", "Text")
	Kit.Label({
		Text = "@" .. userName,
		Size = UDim2.new(0, 0, 0, 12),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = names,
	}, "Tiny", "TextMuted")
	self.Avatar, self.UserNames, self.UserBox = avatar, names, user
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and type(image) == "string" and avatar.Parent then
			avatar.Image = image
		end
	end)

	local bell, bellIcon = iconButton("Bell", "bell", right, 2)
	local bellDot = Create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -5, 0, 5),
		Size = UDim2.fromOffset(7, 7),
		Visible = false,
		ZIndex = 3,
		Parent = bell,
	})
	Kit.Bind(bellDot, "BackgroundColor3", "Danger")
	Kit.Corner(bellDot, "pill")
	self.Bell, self.BellDot, self.BellIcon = bell, bellDot, bellIcon
	self.Maid:Give(Notifications.Added:Connect(function(record)
		bellDot.Visible = record ~= nil and not (self.BellPanel and self.BellPanel.Visible)
	end))
	self.Maid:Give(bell.MouseButton1Click:Connect(function()
		self:ToggleNotificationPanel()
	end))

	local minimize = iconButton("Minimize", "minimize", right, 3)
	self.Maid:Give(minimize.MouseButton1Click:Connect(function()
		self:Minimize(not self.Minimized)
	end))
	local close = iconButton("Close", "close", right, 4)
	self.Maid:Give(close.MouseButton1Click:Connect(function()
		if self.CloseBehavior == "Destroy" then
			task.spawn(function()
				if Dialog.Confirm(self, "Close " .. Theme.Values.Title .. "?", "The interface will be unloaded.", "Unload", "Danger") then
					local library = State.Library
					if library then
						library:Destroy()
					else
						self:Destroy()
					end
				end
			end)
		else
			self:SetVisible(false)
			if not State.IsMobile then
				Notifications.Notify({
					Title = Theme.Values.Title,
					Content = string.format(Constants.Strings.Hidden, self.ToggleKey),
					Type = "Info",
					Duration = 4,
				})
			end
		end
	end))

	-- center: tab strip
	local strip = Create("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Size = UDim2.new(0, 100, 1, 0),
		Parent = topbar,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = strip,
	})
	self.TabStrip = strip

	-- drag by the topbar
	self.Maid:Give(Input.Track(topbar, {
		Threshold = 3,
		Began = function()
			self._dragStart = self.Holder.Position
		end,
		Moved = function(_, _, total)
			local start = self._dragStart
			if not start then
				return
			end
			self.Holder.Position = UDim2.new(start.X.Scale, start.X.Offset + total.X, start.Y.Scale, start.Y.Offset + total.Y)
		end,
		Ended = function(_, wasDrag)
			if wasDrag then
				self:_ClampPosition(true)
			end
		end,
	}))
end

------------------------------------------------------------------------------
-- Body: sidebar + content + drawer backdrop
------------------------------------------------------------------------------
function Window:_BuildBody()
	local body = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = self.Main,
	})
	self.Body = body

	local content = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = body,
	})
	self.Content = content

	local backdrop = Create("TextButton", {
		Name = "DrawerBackdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
		Parent = body,
	})
	Kit.Bind(backdrop, "BackgroundColor3", "Overlay")
	self.Backdrop = backdrop
	self.Maid:Give(backdrop.MouseButton1Click:Connect(function()
		self:CloseDrawer()
	end))

	local sidebar = Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, Theme.Values.SidebarWidth, 1, 0),
		ZIndex = 5,
		Parent = body,
	})
	Kit.Panel(sidebar, "Sidebar", "Panel")
	self.Sidebar = sidebar
	local edge = Create("Frame", {
		Name = "Edge",
		Size = UDim2.new(0, 1, 1, 0),
		Parent = sidebar,
	})
	Kit.Bind(edge, "BackgroundColor3", "Border")
	Kit.Bind(edge, "BackgroundTransparency", { "BorderEnabled", "BorderTransparency" }, function(T)
		return if T.BorderEnabled then T.BorderTransparency else 1
	end)
	self.SidebarEdge = edge

	local sidebarTabs = Create("Frame", {
		Name = "SidebarTabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = sidebar,
	})
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = sidebarTabs })
	Kit.Padding(sidebarTabs, 8)
	self.SidebarTabs = sidebarTabs

	local lists = Create("Frame", {
		Name = "Lists",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = sidebar,
	})
	self.SidebarLists = lists

	self.Maid:Give(sidebarTabs:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_LayoutSidebarInner()
	end))
end

function Window:_LayoutSidebarInner()
	local tabsVisible = self.SidebarTabs.Visible
	local offset = if tabsVisible then self.SidebarTabs.AbsoluteSize.Y / math.max(self.Scale.Scale, 0.01) else 0
	self.SidebarLists.Position = UDim2.fromOffset(0, offset)
	self.SidebarLists.Size = UDim2.new(1, 0, 1, -offset)
end

------------------------------------------------------------------------------
-- Resize grip
------------------------------------------------------------------------------
function Window:_BuildResize()
	local grip = Create("TextButton", {
		Name = "Resize",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(22, 22),
		ZIndex = 15,
		Parent = self.Main,
	})
	for i = 1, 3 do
		local dot = Create("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4 - (i - 1) * 4, 1, -4),
			Size = UDim2.fromOffset(2, 2 + (i - 1) * 4),
			ZIndex = 15,
			Parent = grip,
		})
		Kit.Bind(dot, "BackgroundColor3", "TextMuted")
		Kit.Bind(dot, "BackgroundTransparency", { "TextMuted" }, function()
			return 0.4
		end)
	end
	self.Grip = grip
	local startSize = Vector2.zero
	local startPos = UDim2.new()
	self.Maid:Give(Input.Track(grip, {
		Threshold = 1,
		Began = function()
			startSize = Vector2.new(Theme.Values.WindowWidth, Theme.Values.WindowHeight)
			startPos = self.Holder.Position
		end,
		Moved = function(_, _, total)
			local scale = math.max(self.Scale.Scale, 0.01)
			local minSize, maxSize = Constants.MinWindowSize, Constants.MaxWindowSize
			local w = math.clamp(startSize.X + total.X / scale, minSize.X, maxSize.X)
			local h = math.clamp(startSize.Y + total.Y / scale, minSize.Y, maxSize.Y)
			local dw, dh = (w - startSize.X) * scale, (h - startSize.Y) * scale
			-- anchor is centered: move by half the growth so the top-left corner stays
			self.Holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + dw / 2, startPos.Y.Scale, startPos.Y.Offset + dh / 2)
			self._resizing = true
			Theme:SetMany({ WindowWidth = math.floor(w), WindowHeight = math.floor(h) }, true)
		end,
		Ended = function()
			self._resizing = false
			self:_Layout(true)
		end,
	}))
end

------------------------------------------------------------------------------
-- Connections
------------------------------------------------------------------------------
function Window:_Connect()
	self.Maid:Give(Theme:OnChanged(LAYOUT_KEYS, function(_, instant)
		self:_Layout(instant or self._resizing)
	end))
	self.Maid:Give(State.ViewportChanged:Connect(function()
		self:_Layout(true)
		self:_ClampPosition()
	end))
	self.Maid:Give(State.DeviceChanged:Connect(function()
		self:_Layout(true)
	end))
	self.Maid:Give(Theme:OnChanged({ "Blur", "BlurSize" }, function()
		self:_UpdateBlur()
	end))
	self.Maid:Give(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if input.KeyCode.Name == self.ToggleKey then
			self:Toggle()
		end
	end))
	-- animated gradients: one Heartbeat while enabled and the window is visible
	self.Maid:Give(Theme:OnChanged({ "GradientAnimated" }, function()
		self:_UpdateGradientAnimation()
	end))
	self.Maid:Give(function()
		if self._gradientConnection then
			self._gradientConnection:Disconnect()
		end
	end)
end

function Window:_UpdateGradientAnimation()
	local shouldRun = Theme.Values.GradientAnimated and self.Visible
	if shouldRun and not self._gradientConnection then
		local rotation = 0
		self._gradientConnection = Utility.Services.RunService.Heartbeat:Connect(function(dt)
			rotation = (rotation + dt * 60 * Theme.Values.GradientSpeed) % 360
			local base = Theme.Values.AccentGradientRotation
			for gradient in Kit.AnimatedGradients do
				if gradient.Parent and gradient.Enabled then
					gradient.Rotation = base + rotation
				end
			end
		end)
	elseif not shouldRun and self._gradientConnection then
		self._gradientConnection:Disconnect()
		self._gradientConnection = nil
		local base = Theme.Values.AccentGradientRotation
		for gradient in Kit.AnimatedGradients do
			if gradient.Parent then
				gradient.Rotation = base
			end
		end
	end
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------
function Window:IsSingleColumn(): boolean
	if State.IsMobile then
		return true
	end
	local content = self.Content
	if content and content.AbsoluteSize.X > 0 then
		return content.AbsoluteSize.X / math.max(self.Scale.Scale, 0.01) < 520
	end
	return Theme.Values.WindowWidth - Theme.Values.SidebarWidth < 520
end

function Window:IsDrawerMode(): boolean
	return State.IsMobile or self.WindowSize.X < 600
end

function Window:_Layout(instant: boolean?)
	local T = Theme.Values
	local vp = Utility.Viewport()
	local inset = Utility.GuiInset()
	local mobile = State.IsMobile

	-- scale: theme scale x automatic fit (desktop only; mobile keeps 1:1 for touch sizes)
	local scale = T.UIScale
	if not mobile then
		scale *= math.min(1, (vp.X - 40) / T.WindowWidth, (vp.Y - inset.Y - 40) / T.WindowHeight)
	end
	scale = math.max(scale, 0.3)
	self.Scale.Scale = scale

	local width = T.WindowWidth
	local height = T.WindowHeight
	if mobile then
		width = math.min(width, (vp.X - 16) / scale)
		height = math.min(height, (vp.Y - inset.Y - 16) / scale)
	end
	self.WindowSize = Vector2.new(width, height)
	local topbarHeight = if mobile then MOBILE_TOPBAR_HEIGHT else TOPBAR_HEIGHT
	self.TopbarHeight = topbarHeight

	local holderSize = UDim2.fromOffset(width, if self.Minimized then topbarHeight else height)
	if instant then
		self.Holder.Size = holderSize
	else
		Animations.Tween(self.Holder, { Size = holderSize }, 0.3)
	end

	self.Topbar.Size = UDim2.new(1, 0, 0, topbarHeight)
	self.Body.Position = UDim2.fromOffset(0, topbarHeight)
	self.Body.Size = UDim2.new(1, 0, 1, -topbarHeight)

	-- tabs placement
	local drawer = self:IsDrawerMode()
	local tabsInSidebar = T.TabPosition == "Sidebar"
	local mode = if tabsInSidebar then "Sidebar" else "Top"
	if self.TabMode ~= mode then
		self.TabMode = mode
		for _, tab in self.Tabs do
			tab:_ApplyMode(mode)
		end
	end
	self.SidebarTabs.Visible = tabsInSidebar
	self.TabStrip.Visible = not tabsInSidebar

	-- topbar elements
	local narrow = width < 700
	self.UserBox.Visible = T.ShowAvatar or T.ShowUsername
	self.Avatar.Visible = T.ShowAvatar
	self.UserNames.Visible = T.ShowUsername and not narrow and not mobile
	self.Titles.Visible = not (mobile and width < 560)

	-- sidebar
	local hasSidebar = tabsInSidebar or (self.ActiveTab ~= nil and self.ActiveTab:HasSidebar())
	self.HasSidebar = hasSidebar
	self.MenuButton.Visible = drawer and hasSidebar
	local sidebarWidth = math.min(T.SidebarWidth, width * (if drawer then 0.82 else 0.45))
	local right = T.SidebarPosition == "Right"
	local sidebar = self.Sidebar
	sidebar.AnchorPoint = Vector2.new(if right then 1 else 0, 0)
	self.SidebarEdge.AnchorPoint = Vector2.new(if right then 0 else 1, 0)
	self.SidebarEdge.Position = UDim2.fromScale(if right then 0 else 1, 0)

	local sidebarPos, contentPos, contentSize
	if drawer or not hasSidebar then
		-- sidebar is an overlay drawer (or hidden)
		local open = drawer and hasSidebar and self.DrawerOpen
		local hiddenX = if right then UDim2.new(1, sidebarWidth + 2, 0, 0) else UDim2.new(0, -sidebarWidth - 2, 0, 0)
		local shownX = if right then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 0)
		sidebarPos = if open then shownX else hiddenX
		contentPos = UDim2.new()
		contentSize = UDim2.fromScale(1, 1)
		self.Backdrop.Visible = open
		Animations.Tween(self.Backdrop, { BackgroundTransparency = if open then Theme:Alpha("Overlay", "Free") else 1 }, 0.25)
		if not open and not (drawer and hasSidebar) then
			self.DrawerOpen = false
		end
	else
		self.DrawerOpen = false
		self.Backdrop.Visible = false
		sidebarPos = if right then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 0)
		contentPos = if right then UDim2.new() else UDim2.fromOffset(sidebarWidth, 0)
		contentSize = UDim2.new(1, -sidebarWidth, 1, 0)
	end
	local sidebarSize = UDim2.new(0, sidebarWidth, 1, 0)
	if instant then
		sidebar.Position, sidebar.Size = sidebarPos, sidebarSize
		self.Content.Position, self.Content.Size = contentPos, contentSize
	else
		Animations.Tween(sidebar, { Position = sidebarPos, Size = sidebarSize }, 0.35)
		Animations.Tween(self.Content, { Position = contentPos, Size = contentSize }, 0.35)
	end

	-- tab strip sits between the left and right topbar groups
	task.defer(function()
		self:_LayoutTopbar()
		self:_LayoutSidebarInner()
		for _, tab in self.Tabs do
			for _, page in tab.Pages do
				page:_Relayout()
			end
		end
	end)
end

function Window:_LayoutTopbar()
	local scale = math.max(self.Scale.Scale, 0.01)
	local leftWidth = self.TopLeft.AbsoluteSize.X / scale
	local rightWidth = self.TopRight.AbsoluteSize.X / scale
	self.TabStrip.Position = UDim2.fromOffset(leftWidth + 6, 0)
	self.TabStrip.Size = UDim2.new(1, -(leftWidth + rightWidth + 12), 1, 0)
end

-- Keeps at least part of the topbar on screen
function Window:_ClampPosition(animated: boolean?)
	local holder = self.Holder
	local vp = Utility.Viewport()
	local inset = Utility.GuiInset()
	local size = holder.AbsoluteSize
	local pos = holder.AbsolutePosition
	local minX, maxX = -size.X + 80, vp.X - 80
	local minY, maxY = inset.Y, vp.Y - 40
	local cx, cy = math.clamp(pos.X, minX, maxX), math.clamp(pos.Y, minY, maxY)
	if cx ~= pos.X or cy ~= pos.Y then
		local p = holder.Position
		local target = UDim2.new(p.X.Scale, p.X.Offset + (cx - pos.X), p.Y.Scale, p.Y.Offset + (cy - pos.Y))
		if animated then
			Animations.Tween(holder, { Position = target }, 0.3)
		else
			holder.Position = target
		end
	end
end

------------------------------------------------------------------------------
-- Drawer
------------------------------------------------------------------------------
function Window:OpenDrawer()
	if not self:IsDrawerMode() or not self.HasSidebar then
		return
	end
	self.DrawerOpen = true
	self:_Layout()
end

function Window:CloseDrawer()
	if not self.DrawerOpen then
		return
	end
	self.DrawerOpen = false
	self:_Layout()
end

function Window:ToggleDrawer()
	if self.DrawerOpen then
		self:CloseDrawer()
	else
		self:OpenDrawer()
	end
end

------------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------------
function Window:AddTab(options: any)
	local tab = Tab.new(self, options)
	table.insert(self.Tabs, tab)
	tab:_ApplyMode(self.TabMode or "Top")
	if not self.ActiveTab then
		self:SelectTab(tab)
	else
		tab:_Hide()
	end
	return tab
end

function Window:SelectTab(tab: any)
	if self.ActiveTab == tab then
		return
	end
	local previous = self.ActiveTab
	self.ActiveTab = tab
	if previous then
		previous:_Hide()
	end
	tab:_Show()
	self:_Layout()
end

------------------------------------------------------------------------------
-- Visibility
------------------------------------------------------------------------------
function Window:_UpdateBlur()
	local enabled = Theme.Values.Blur and self.Visible and not self.Minimized
	local lighting = Utility.Services.Lighting
	if enabled then
		if not self.BlurEffect or not self.BlurEffect.Parent then
			local ok, blur = pcall(function()
				return Create("BlurEffect", { Name = Constants.Id .. "Blur", Size = 0, Parent = lighting })
			end)
			if ok then
				self.BlurEffect = blur
				self.Maid:Give(blur)
			end
		end
		if self.BlurEffect then
			Animations.Tween(self.BlurEffect, { Size = Theme.Values.BlurSize }, 0.35)
		end
	elseif self.BlurEffect then
		local blur = self.BlurEffect
		local tween = Animations.Tween(blur, { Size = 0 }, 0.25)
		if tween then
			tween.Completed:Once(function()
				if blur.Size == 0 and not (Theme.Values.Blur and self.Visible) then
					blur:Destroy()
					if self.BlurEffect == blur then
						self.BlurEffect = nil
					end
				end
			end)
		else
			blur:Destroy()
			self.BlurEffect = nil
		end
	end
end

function Window:SetVisible(visible: boolean, instant: boolean?)
	if self.Visible == visible and not instant then
		return
	end
	self.Visible = visible
	self._visToken = (self._visToken or 0) + 1
	local token = self._visToken
	if visible then
		self.Holder.Visible = true
		if instant or not Animations.Enabled() then
			self.PopScale.Scale = 1
		else
			self.PopScale.Scale = 0.85
			Animations.Tween(self.PopScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Back)
		end
		self.Opened:Fire()
	else
		Import("Components/Tooltip").Hide()
		local tween = if instant then nil else Animations.Tween(self.PopScale, { Scale = 0.85 }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		local function hide()
			if self._visToken == token then
				self.Holder.Visible = false
			end
		end
		if tween then
			tween.Completed:Once(hide)
		else
			hide()
		end
		self.Closed:Fire()
		Config:SaveOnClose()
	end
	self:_UpdateBlur()
	self:_UpdateGradientAnimation()
end

function Window:Toggle()
	self:SetVisible(not self.Visible)
end

function Window:Minimize(state: boolean?)
	local minimized = if state == nil then not self.Minimized else state
	self.Minimized = minimized
	self.Body.Visible = true
	self.Grip.Visible = not minimized
	local height = if minimized then self.TopbarHeight or TOPBAR_HEIGHT else self.WindowSize.Y
	local tween = Animations.Tween(self.Holder, { Size = UDim2.fromOffset(self.WindowSize.X, height) }, 0.35)
	local function done()
		if self.Minimized then
			self.Body.Visible = false
		end
	end
	if tween then
		tween.Completed:Once(done)
	else
		done()
	end
	self:_UpdateBlur()
end

function Window:SetToggleKey(key: any)
	local name = Window._KeyName(key)
	if name then
		self.ToggleKey = name
	end
end

------------------------------------------------------------------------------
-- Notifications popover (bell)
------------------------------------------------------------------------------
function Window:ToggleNotificationPanel()
	if not self.BellPanel then
		local panel = Create("Frame", {
			Name = "NotificationPanel",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, (self.TopbarHeight or TOPBAR_HEIGHT) + 6),
			Size = UDim2.fromOffset(280, 260),
			Visible = false,
			ZIndex = 18,
			Parent = self.Main,
		})
		Kit.Panel(panel, "Card", "Free")
		Kit.Corner(panel, 1)
		Kit.Stroke(panel, "Border", { Always = true })
		Kit.Label({
			Text = "Notifications",
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -24, 0, 20),
			ZIndex = 18,
			Parent = panel,
		}, "Heading", "Text")
		local list = Kit.Scrolling({
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, 0, 1, -40),
			ZIndex = 18,
			Parent = panel,
		})
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = list })
		Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = list })
		self.BellPanel, self.BellList = panel, list
		self.BellScale = Create("UIScale", { Parent = panel })
	end
	local panel = self.BellPanel
	if panel.Visible then
		panel.Visible = false
		return
	end
	for _, child in self.BellList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local colors = { Info = "Accent", Success = "Success", Warning = "Warning", Error = "Danger" }
	if #Notifications.History == 0 then
		local empty = Create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = self.BellList })
		Kit.Label({ Text = "No notifications yet", Size = UDim2.fromScale(1, 1), ZIndex = 18, Parent = empty }, "Small", "TextMuted")
	end
	for index, record in Notifications.History do
		local item = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index,
			ZIndex = 18,
			Parent = self.BellList,
		})
		Kit.Panel(item, "Surface", "Free")
		Kit.Corner(item, 0.6)
		Kit.Padding(item, 8)
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = item })
		Kit.Label({
			Text = record.Title,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = 1,
			ZIndex = 18,
			Parent = item,
		}, "Small", colors[record.Type] or "Accent")
		if record.Content ~= "" then
			Kit.Label({
				Text = record.Content,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				LayoutOrder = 2,
				ZIndex = 18,
				Parent = item,
			}, "Tiny", "TextMuted")
		end
	end
	panel.Position = UDim2.new(1, -12, 0, (self.TopbarHeight or TOPBAR_HEIGHT) + 6)
	panel.Visible = true
	self.BellDot.Visible = false
	self.BellScale.Scale = 0.9
	Animations.Tween(self.BellScale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
end

------------------------------------------------------------------------------
-- Convenience API
------------------------------------------------------------------------------
function Window:Notify(options: { [string]: any })
	return Notifications.Notify(options)
end

function Window:Dialog(options: { [string]: any })
	return Dialog.new(self, options)
end

function Window:Confirm(title: string, content: string?, confirmText: string?, style: string?): boolean
	return Dialog.Confirm(self, title, content, confirmText, style)
end

function Window:Prompt(title: string, content: string?, placeholder: string?, default: string?): string?
	return Dialog.Prompt(self, title, content, placeholder, default)
end

function Window:AddThemeTab(options: { [string]: any }?)
	return Import("Tabs/AppearanceTab").Build(self, options or {})
end

function Window:AddConfigTab(options: { [string]: any }?)
	return Import("Tabs/ConfigTab").Build(self, options or {})
end

function Window:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	Config:SaveOnClose()
	for _, tab in self.Tabs do
		tab:Destroy()
	end
	self.Maid:Clean()
	local index = table.find(State.Windows, self)
	if index then
		table.remove(State.Windows, index)
	end
	if State.MainWindow == self then
		State.MainWindow = State.Windows[1]
	end
end

return Window
