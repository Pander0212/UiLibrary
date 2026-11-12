--[[
	Dialog / Modal
	  local d = Window:Dialog({
	      Title = "Delete config?", Content = "This cannot be undone.", Icon = "warning",
	      Input = { Placeholder = "Name", Default = "" },          -- optional prompt field
	      Buttons = {
	          { Title = "Cancel" },
	          { Title = "Delete", Style = "Danger", Callback = function(inputText) end },
	      },
	  })
	  d:Close()
	  Window:Confirm(title, content [, confirmText, style]) -> boolean   (yields)
	  Window:Prompt(title, content, placeholder, default) -> string?    (yields)
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Gui = Import("Gui")
local Constants = Import("Constants")

local Create = Utility.Create

local Dialog = {}
Dialog.__index = Dialog

function Dialog.new(window: any?, options: { [string]: any })
	local self = setmetatable({}, Dialog)
	local o = options or {}
	self.Closed = false
	local layer: GuiObject = if window and window.DialogLayer then window.DialogLayer else Gui.Layer("Popups")
	layer.Visible = true

	local root = Create("Frame", {
		Name = "Dialog",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = layer,
	})
	self.Root = root

	local backdrop = Create("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = root,
	})
	Kit.Bind(backdrop, "BackgroundColor3", "Overlay")
	Animations.Tween(backdrop, { BackgroundTransparency = Theme:Alpha("Overlay", "Free") }, 0.25)
	self.Backdrop = backdrop

	local card = Create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 11,
		Parent = root,
	})
	Create("UISizeConstraint", { MaxSize = Vector2.new(o.Width or 380, math.huge), Parent = card })
	Kit.Panel(card, "Card", "Free")
	Kit.Corner(card, 1.2)
	Kit.Stroke(card, "Border", { Always = true })
	Kit.Padding(card, 18)
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = card })
	local scale = Create("UIScale", { Scale = 0.85, Parent = card })
	Animations.Tween(scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
	self.Card, self.Scale = card, scale

	local header = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 1,
		ZIndex = 11,
		Parent = card,
	})
	local offset = 0
	if o.Icon then
		Kit.Icon(o.Icon, { Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(0, 2), ZIndex = 11, Parent = header }, o.IconColor or "Accent")
		offset = 28
	end
	Kit.Label({
		Text = tostring(o.Title or "Dialog"),
		Position = UDim2.fromOffset(offset, 0),
		Size = UDim2.new(1, -offset, 1, 0),
		ZIndex = 11,
		Parent = header,
	}, "Title", "Text")

	if o.Content then
		Kit.Label({
			Text = tostring(o.Content),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			RichText = o.RichText == true,
			LayoutOrder = 2,
			ZIndex = 11,
			Parent = card,
		}, "Body", "TextMuted")
	end

	if o.Input then
		local field = Create("Frame", { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 3, ZIndex = 11, Parent = card })
		Kit.Panel(field, "Input", "Free")
		Kit.Corner(field, 0.6)
		Kit.Stroke(field, "Accent", { Always = true })
		self.Input = Kit.TextBox({
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			PlaceholderText = o.Input.Placeholder or "",
			Text = o.Input.Default or "",
			ZIndex = 11,
			Parent = field,
		}, "Body")
		task.defer(function()
			if self.Input and not self.Closed then
				self.Input:CaptureFocus()
			end
		end)
	end

	local buttons = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 4,
		ZIndex = 11,
		Parent = card,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = buttons,
	})
	local list = o.Buttons or { { Title = Constants.Strings.Ok, Style = "Primary" } }
	for index, data in list do
		local style = data.Style or "Default"
		local button = Create("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = index,
			ClipsDescendants = true,
			ZIndex = 11,
			Parent = buttons,
		})
		Create("UISizeConstraint", { MinSize = Vector2.new(84, 0), Parent = button })
		Create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = button })
		Kit.Corner(button, 0.7)
		local textKey = "Text"
		if style == "Primary" then
			Kit.AccentFill(button, "Button")
			textKey = "AccentText"
		elseif style == "Danger" then
			Kit.Panel(button, "Danger", "Free")
			textKey = "AccentText"
		else
			Kit.Panel(button, "Surface", "Free")
			Kit.Stroke(button, "Border")
		end
		local label = Kit.Label({
			Text = tostring(data.Title or "OK"),
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 11,
			Parent = button,
		}, "Heading", textKey)
		label.Name = "Label"
		Animations.AttachPress(button, button, 0.95)
		button.MouseButton1Click:Connect(function()
			Animations.Ripple(button, nil, textKey)
			local text = if self.Input then self.Input.Text else nil
			if data.Callback then
				Utility.SafeCallback(data.Callback, text)
			end
			if data.Close ~= false then
				self:Close()
			end
		end)
	end

	if o.Dismissible ~= false then
		backdrop.MouseButton1Click:Connect(function()
			if o.OnDismiss then
				Utility.SafeCallback(o.OnDismiss)
			end
			self:Close()
		end)
	end
	return self
end

function Dialog:Close()
	if self.Closed then
		return
	end
	self.Closed = true
	Animations.Tween(self.Backdrop, { BackgroundTransparency = 1 }, 0.2)
	local tween = Animations.Tween(self.Scale, { Scale = 0.85 }, 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	local root = self.Root
	local function done()
		local layer = root.Parent
		root:Destroy()
		if layer and #layer:GetChildren() == 0 and layer:IsA("GuiObject") and layer.Name == "DialogLayer" then
			layer.Visible = false
		end
	end
	if tween then
		self.Card.Visible = true
		task.delay(0.2 / Animations.Speed(), done)
	else
		done()
	end
end
Dialog.Destroy = Dialog.Close

-- Yields until the user decides. Returns true when confirmed.
function Dialog.Confirm(window: any?, title: string, content: string?, confirmText: string?, style: string?): boolean
	local thread = coroutine.running()
	local resolved = false
	local function resolve(value: boolean)
		if resolved then
			return
		end
		resolved = true
		task.spawn(thread, value)
	end
	Dialog.new(window, {
		Title = title,
		Content = content,
		Icon = if style == "Danger" then "warning" else "info",
		IconColor = if style == "Danger" then "Danger" else "Accent",
		OnDismiss = function()
			resolve(false)
		end,
		Buttons = {
			{
				Title = Constants.Strings.Cancel,
				Callback = function()
					resolve(false)
				end,
			},
			{
				Title = confirmText or Constants.Strings.Confirm,
				Style = style or "Primary",
				Callback = function()
					resolve(true)
				end,
			},
		},
	})
	return coroutine.yield()
end

function Dialog.Prompt(window: any?, title: string, content: string?, placeholder: string?, default: string?): string?
	local thread = coroutine.running()
	local resolved = false
	local function resolve(value: string?)
		if resolved then
			return
		end
		resolved = true
		task.spawn(thread, value)
	end
	Dialog.new(window, {
		Title = title,
		Content = content,
		Input = { Placeholder = placeholder, Default = default },
		OnDismiss = function()
			resolve(nil)
		end,
		Buttons = {
			{
				Title = Constants.Strings.Cancel,
				Callback = function()
					resolve(nil)
				end,
			},
			{
				Title = Constants.Strings.Ok,
				Style = "Primary",
				Callback = function(text)
					resolve(text)
				end,
			},
		},
	})
	return coroutine.yield()
end

return Dialog
