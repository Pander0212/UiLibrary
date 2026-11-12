--[[
	Notifications
	Toasts with type colour, icon, remaining-time bar and smooth stacking. The
	screen corner comes from the theme key NotificationPosition. A short history is
	kept for the bell popover in the topbar.

	  Notifications.Notify({Title, Content, Type = "Info"|"Success"|"Warning"|"Error",
	                        Duration = 5, Icon = "bell", Actions = {{Title, Callback}}})
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Gui = Import("Gui")
local Signal = Import("Signal")
local State = Import("State")

local Create = Utility.Create

local Notifications = {}
Notifications.History = {} :: { { [string]: any } }
Notifications.Added = Signal.new()
Notifications.MaxHistory = 25
Notifications.MaxVisible = 6

local TYPE_COLOR = { Info = "Accent", Success = "Success", Warning = "Warning", Error = "Danger" }
local TYPE_ICON = { Info = "info", Success = "success", Warning = "warning", Error = "error" }

local container: Frame? = nil
local layout: UIListLayout? = nil
local active: { any } = {}

local function width(): number
	return math.min(330, Utility.Viewport().X - 24)
end

local function anchor()
	if not container or not layout then
		return
	end
	local pos = Theme.Values.NotificationPosition
	local top = string.find(pos, "Top") ~= nil
	local left = string.find(pos, "Left") ~= nil
	local inset = Utility.GuiInset()
	container.AnchorPoint = Vector2.new(if left then 0 else 1, if top then 0 else 1)
	container.Position = UDim2.new(if left then 0 else 1, if left then 12 else -12, if top then 0 else 1, if top then inset.Y + 12 else -12)
	container.Size = UDim2.new(0, width(), 1, -(inset.Y + 24))
	layout.VerticalAlignment = if top then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = if left then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right
end

local function ensureContainer(): Frame
	if container and container.Parent then
		return container
	end
	container = Create("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		Parent = Gui.Layer("Notifications"),
	})
	layout = Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = container,
	})
	anchor()
	State.Maid:Give(Theme:OnChanged("NotificationPosition", anchor))
	State.Maid:Give(State.ViewportChanged:Connect(anchor))
	return container :: Frame
end

local order = 0

function Notifications.Notify(options: { [string]: any }): { [string]: any }
	local opts = options or {}
	local kind = if TYPE_COLOR[opts.Type] then opts.Type else "Info"
	local colorKey = TYPE_COLOR[kind]
	local duration = tonumber(opts.Duration) or 5
	local parent = ensureContainer()
	local top = string.find(Theme.Values.NotificationPosition, "Top") ~= nil
	local left = string.find(Theme.Values.NotificationPosition, "Left") ~= nil
	order += 1

	local record = {
		Title = tostring(opts.Title or "Notification"),
		Content = tostring(opts.Content or ""),
		Type = kind,
		Time = os.time(),
	}
	table.insert(Notifications.History, 1, record)
	if #Notifications.History > Notifications.MaxHistory then
		table.remove(Notifications.History)
	end
	Notifications.Added:Fire(record)
	Kit.Sound(if kind == "Error" then "Error" else "Notify")

	-- holder animates its height so the stack moves smoothly
	local holder = Create("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = if top then order else -order,
		ClipsDescendants = false,
		Parent = parent,
	})
	local card = Create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(if left then -1.2 else 1.2, 0, 0, 0),
		Parent = holder,
	})
	Kit.Panel(card, "NotificationBackground", "Free")
	Kit.Corner(card, 1)
	Kit.Stroke(card, "NotificationBorder", { Always = true })

	local accentBar = Create("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 3, 1, -16),
		Position = UDim2.fromOffset(0, 8),
		Parent = card,
	})
	Kit.Bind(accentBar, "BackgroundColor3", colorKey)
	Kit.Corner(accentBar, "pill")

	local body = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 34),
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 14),
		Parent = body,
	})
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3), Parent = body })

	local header = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = body,
	})
	Kit.Icon(opts.Icon or TYPE_ICON[kind], { Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(0, 1), Parent = header }, colorKey)
	Kit.Label({
		Text = record.Title,
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(24, 0),
		Parent = header,
	}, "Heading", "Text")

	if record.Content ~= "" then
		Kit.Label({
			Text = record.Content,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 2,
			Parent = body,
		}, "Small", "TextMuted")
	end

	local closeButton = Create("TextButton", {
		Name = "Close",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(20, 20),
		Parent = card,
	})
	Kit.Icon("close", { Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = closeButton }, "TextMuted")

	local bar = Create("Frame", {
		Name = "Time",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -5),
		Size = UDim2.new(1, -20, 0, 2),
		Parent = card,
	})
	Kit.Bind(bar, "BackgroundColor3", colorKey)
	Kit.Bind(bar, "BackgroundTransparency", { colorKey }, function()
		return 0.4
	end)
	Kit.Corner(bar, "pill")

	local closed = false
	local object = {}

	local function close()
		if closed then
			return
		end
		closed = true
		local index = table.find(active, object)
		if index then
			table.remove(active, index)
		end
		Animations.Tween(card, { Position = UDim2.new(if left then -1.2 else 1.2, 0, 0, 0) }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.22 / Animations.Speed(), function()
			Animations.Tween(holder, { Size = UDim2.new(1, 0, 0, 0) }, 0.25)
			task.delay(0.3 / Animations.Speed(), function()
				holder:Destroy()
			end)
		end)
	end
	object.Close = close
	object.Destroy = close

	closeButton.MouseButton1Click:Connect(close)

	-- actions (optional buttons)
	if type(opts.Actions) == "table" and #opts.Actions > 0 then
		local actions = Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 3,
			Parent = body,
		})
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = actions,
		})
		for i, action in opts.Actions do
			local button = Create("TextButton", {
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = i,
				Text = tostring(action.Title or "OK"),
				Parent = actions,
			})
			Kit.Text(button, "Small", if i == 1 then "AccentText" else "Text")
			if i == 1 then
				Kit.AccentFill(button, "Button")
			else
				Kit.Panel(button, "Surface", "Free")
			end
			Kit.Corner(button, 0.6)
			Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = button })
			button.MouseButton1Click:Connect(function()
				Utility.SafeCallback(action.Callback)
				close()
			end)
		end
	end

	table.insert(active, object)
	if #active > Notifications.MaxVisible then
		active[1].Close()
	end

	-- animate in once the card has measured its height
	task.defer(function()
		local height = card.AbsoluteSize.Y
		if height <= 0 then
			task.wait()
			height = card.AbsoluteSize.Y
		end
		Animations.Tween(holder, { Size = UDim2.new(1, 0, 0, height) }, 0.3)
		Animations.Tween(card, { Position = UDim2.new() }, 0.45, Enum.EasingStyle.Quint)
		card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if not closed then
				holder.Size = UDim2.new(1, 0, 0, card.AbsoluteSize.Y)
			end
		end)
		if duration > 0 then
			local tween = Utility.Services.TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })
			tween:Play()
			task.delay(duration, close)
		else
			bar.Visible = false
		end
	end)

	return object
end

function Notifications.ClearHistory()
	table.clear(Notifications.History)
	Notifications.Added:Fire(nil)
end

return Notifications
