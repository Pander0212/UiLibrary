--[[
	QuickToggles
	Every Toggle created with `Pinnable = true` can be pinned (pin icon, or long-press
	on touch) to the screen as a small floating button:
	  * Tap  -> toggles (accent glow when on, grey when off, bounce)
	  * Drag -> move (threshold separates tap from drag)
	  * Long-press -> menu: size S/M/L, transparency, unpin
	  * Global edit mode with grid snapping (QuickToggles.SetEditMode(true))
	State is synchronised with the menu toggle in both directions, positions/sizes/
	pins are stored in the config ("QuickToggles" provider).
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
local Device = Import("Mobile/Device")

local Create = Utility.Create

local QuickToggles = {}
QuickToggles.Registered = {} :: { [string]: any } -- key -> toggle
QuickToggles.Pins = {} :: { [string]: any } -- key -> pin object
QuickToggles.Saved = {} :: { [string]: any } -- key -> saved data (pending)
QuickToggles.EditMode = false
QuickToggles.GridSize = 12
QuickToggles.EditModeChanged = Signal.new()
QuickToggles.SizeScale = { S = 0.78, M = 1, L = 1.3 }

local providerRegistered = false
local hintShown = false

local function keyOf(toggle: any): string
	if toggle.Flag then
		return toggle.Flag
	end
	if not toggle._quickKey then
		toggle._quickKey = "Toggle_" .. tostring(toggle.Options.Title or "") .. "_" .. tostring(math.random(1, 1e6))
	end
	return toggle._quickKey
end

local function registerProvider()
	if providerRegistered then
		return
	end
	providerRegistered = true
	Config:RegisterProvider("QuickToggles", function()
		local data = {}
		for key, pin in QuickToggles.Pins do
			data[key] = table.clone(pin.Data)
		end
		-- keep pins of toggles that do not exist (yet)
		for key, saved in QuickToggles.Saved do
			if data[key] == nil and not QuickToggles.Registered[key] then
				data[key] = saved
			end
		end
		return data
	end, function(data)
		if type(data) ~= "table" then
			return
		end
		QuickToggles.Saved = {}
		for key, entry in data do
			if type(key) == "string" and type(entry) == "table" then
				QuickToggles.Saved[key] = entry
			end
		end
		for key, toggle in QuickToggles.Registered do
			local saved = QuickToggles.Saved[key]
			if saved then
				QuickToggles.SetPinned(toggle, true, saved)
			elseif QuickToggles.Pins[key] then
				QuickToggles.SetPinned(toggle, false)
			end
		end
	end)
end

------------------------------------------------------------------------------
-- Registration
------------------------------------------------------------------------------
function QuickToggles.Attach(toggle: any)
	registerProvider()
	local key = keyOf(toggle)
	QuickToggles.Registered[key] = toggle
	toggle.Maid:Give(function()
		if QuickToggles.Registered[key] == toggle then
			QuickToggles.Registered[key] = nil
		end
		local pin = QuickToggles.Pins[key]
		if pin and pin.Toggle == toggle then
			pin.Maid:Clean()
			QuickToggles.Pins[key] = nil
		end
	end)
	local saved = QuickToggles.Saved[key]
	if saved then
		QuickToggles.SetPinned(toggle, true, saved)
	end
end

function QuickToggles.IsPinned(toggle: any): boolean
	return QuickToggles.Pins[keyOf(toggle)] ~= nil
end

------------------------------------------------------------------------------
-- Pin object
------------------------------------------------------------------------------
local function pixelSize(data: any): number
	return math.floor(Theme.Values.QuickToggleSize * (QuickToggles.SizeScale[data.Size] or 1) + 0.5)
end

local function savePosition(pin: any)
	local vp = Utility.Viewport()
	local pos = pin.Button.AbsolutePosition
	pin.Data.X = math.clamp(pos.X / math.max(vp.X, 1), 0, 1)
	pin.Data.Y = math.clamp(pos.Y / math.max(vp.Y, 1), 0, 1)
	QuickToggles.Saved[pin.Key] = table.clone(pin.Data)
end

local function applyPosition(pin: any, animated: boolean?)
	local vp = Utility.Viewport()
	local s = pixelSize(pin.Data)
	local size = Vector2.new(s, s)
	local pos = Device.AvoidZones(Vector2.new(pin.Data.X * vp.X, pin.Data.Y * vp.Y), size)
	local udim = UDim2.fromOffset(pos.X, pos.Y)
	if animated then
		Animations.Tween(pin.Button, { Position = udim }, 0.3, Enum.EasingStyle.Back)
	else
		pin.Button.Position = udim
	end
end

local function defaultPosition(): { [string]: any }
	-- spread new pins along the upper middle area (away from thumbstick & jump)
	local count = Utility.Count(QuickToggles.Pins)
	return {
		X = 0.32 + (count % 6) * 0.07,
		Y = 0.2 + math.floor(count / 6) * 0.13,
		Size = "M",
		Transparency = 0,
	}
end

local function closeMenu()
	if QuickToggles._menu then
		QuickToggles._menu:Destroy()
		QuickToggles._menu = nil
	end
end

local function openMenu(pin: any)
	closeMenu()
	local layer = Gui.Layer("Popups")
	local root = Create("TextButton", {
		Name = "QuickToggleMenu",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = layer,
	})
	QuickToggles._menu = root
	root.MouseButton1Click:Connect(closeMenu)

	local card = Create("Frame", {
		Size = UDim2.fromOffset(210, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 31,
		Parent = root,
	})
	Kit.Panel(card, "Card", "Free")
	Kit.Corner(card, 1)
	Kit.Stroke(card, "Border", { Always = true })
	Kit.Padding(card, 10)
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = card })
	local scale = Create("UIScale", { Scale = 0.85, Parent = card })
	Animations.Tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)

	Kit.Label({
		Text = tostring(pin.Toggle.Options.Title or "Quick toggle"),
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		ZIndex = 31,
		Parent = card,
	}, "Heading", "Text")

	local function row(order: number, title: string, options: { any }, current: any, apply: (any) -> ())
		Kit.Label({
			Text = title,
			Size = UDim2.new(1, 0, 0, 14),
			LayoutOrder = order,
			ZIndex = 31,
			Parent = card,
		}, "Tiny", "TextMuted")
		local holder = Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = order + 1,
			ZIndex = 31,
			Parent = card,
		})
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
			Parent = holder,
		})
		for i, option in options do
			local selected = option.Value == current
			local b = Create("TextButton", {
				Size = UDim2.new(1 / #options, -6, 1, 0),
				LayoutOrder = i,
				ZIndex = 31,
				Parent = holder,
			})
			Kit.Corner(b, 0.6)
			Kit.Panel(b, if selected then "Accent" else "Surface", "Free")
			Kit.Label({
				Text = option.Text,
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 31,
				Parent = b,
			}, "Small", if selected then "AccentText" else "Text")
			b.MouseButton1Click:Connect(function()
				apply(option.Value)
				openMenu(pin)
			end)
		end
	end

	row(2, "Size", {
		{ Text = "S", Value = "S" },
		{ Text = "M", Value = "M" },
		{ Text = "L", Value = "L" },
	}, pin.Data.Size, function(value)
		pin.Data.Size = value
		pin:Render()
		applyPosition(pin, true)
		savePosition(pin)
	end)
	row(4, "Transparency", {
		{ Text = "0%", Value = 0 },
		{ Text = "25%", Value = 0.25 },
		{ Text = "50%", Value = 0.5 },
		{ Text = "75%", Value = 0.75 },
	}, pin.Data.Transparency, function(value)
		pin.Data.Transparency = value
		pin:Render()
		savePosition(pin)
	end)

	local actions = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 6,
		ZIndex = 31,
		Parent = card,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = actions,
	})
	local function action(order: number, text: string, colorKey: string, fn: () -> ())
		local b = Create("TextButton", { Size = UDim2.new(0.5, -3, 1, 0), LayoutOrder = order, ZIndex = 31, Parent = actions })
		Kit.Corner(b, 0.6)
		Kit.Panel(b, colorKey, "Free")
		Kit.Label({
			Text = text,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 31,
			Parent = b,
		}, "Small", if colorKey == "Surface" then "Text" else "AccentText")
		b.MouseButton1Click:Connect(function()
			closeMenu()
			fn()
		end)
	end
	action(1, "Edit layout", "Surface", function()
		QuickToggles.SetEditMode(true)
	end)
	action(2, Constants.Strings.Unpin, "Danger", function()
		QuickToggles.SetPinned(pin.Toggle, false)
	end)

	-- place the menu next to the button, on screen
	task.defer(function()
		local vp = Utility.Viewport()
		local bpos, bsize = pin.Button.AbsolutePosition, pin.Button.AbsoluteSize
		local csize = card.AbsoluteSize
		local x = bpos.X + bsize.X + 8
		if x + csize.X > vp.X - 8 then
			x = bpos.X - csize.X - 8
		end
		local y = math.clamp(bpos.Y, Utility.GuiInset().Y + 8, vp.Y - csize.Y - 8)
		card.Position = UDim2.fromOffset(math.max(x, 8), y)
	end)
end

local function createPin(toggle: any, key: string, data: any)
	local pin = { Toggle = toggle, Key = key, Data = data, Maid = Maid.new() }
	local button = Create("TextButton", {
		Name = "Quick_" .. key,
		Size = UDim2.fromOffset(52, 52),
		ZIndex = 4,
		Parent = Gui.Layer("Mobile"),
	})
	pin.Button = button
	pin.Maid:Give(button)
	local corner = Create("UICorner", { Parent = button })
	Kit.Bind(corner, "CornerRadius", { "MobileButtonShape", "CornerRadius" }, function(T)
		return if T.MobileButtonShape == "Round" then UDim.new(1, 0) else UDim.new(0, T.CornerRadius)
	end, { NoTween = true })
	Kit.Bind(button, "BackgroundColor3", { "QuickToggleOn", "QuickToggleOff" }, function(T)
		return if toggle.Value then T.QuickToggleOn else T.QuickToggleOff
	end)
	Kit.Bind(button, "BackgroundTransparency", { "QuickToggleOnTransparency", "QuickToggleOffTransparency", "MobileTransparency" }, function(T)
		local own = if toggle.Value then T.QuickToggleOnTransparency else T.QuickToggleOffTransparency
		return 1 - (1 - own) * (1 - T.MobileTransparency) * (1 - (pin.Data.Transparency or 0))
	end)
	local glow = Kit.Stroke(button, "Accent", {
		Always = true,
		Deps = { "Accent", "Border" },
		Compute = function(T)
			return if toggle.Value or QuickToggles.EditMode then T.Accent else T.Border
		end,
	})
	Kit.Bind(glow, "Thickness", { "BorderThickness" }, function()
		return if toggle.Value then 2.5 else 1
	end)
	Kit.Bind(glow, "Transparency", { "AccentTransparency" }, function()
		local base = if toggle.Value then 0.15 else 0.4
		return 1 - (1 - base) * (1 - (pin.Data.Transparency or 0))
	end)
	pin.Glow = glow

	local content = Create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = button })
	Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 1),
		Parent = content,
	})
	local o = toggle.Options
	local icon = Kit.Icon(o.Icon or o.Title or "bolt", { Size = UDim2.fromScale(0.36, 0.36), LayoutOrder = 1, Parent = content }, "Text")
	local title = Kit.Label({
		Text = tostring(o.QuickTitle or o.Title or ""),
		Size = UDim2.new(0.92, 0, 0.24, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		LayoutOrder = 2,
		Parent = content,
	}, "Tiny", "Text")
	Create("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 7, Parent = title })
	Kit.Bind(title, "TextColor3", { "AccentText", "Text" }, function(T)
		return if toggle.Value then T.AccentText else T.Text
	end)
	pin.Icon, pin.Title = icon, title
	local scale = Create("UIScale", { Parent = button })
	pin.Scale = scale

	function pin:Render(animated: boolean?)
		local s = pixelSize(self.Data)
		button.Size = UDim2.fromOffset(s, s)
		Kit.Refresh(button, nil, not animated)
		Kit.Refresh(glow, nil, not animated)
		Kit.Refresh(title)
		Kit.SetIconColor(icon, if toggle.Value then "AccentText" else "Text")
	end

	-- input: tap toggles, drag moves (grid snap in edit mode), long press = menu
	local startPos = Vector2.zero
	pin.Maid:Give(Input.Track(button, {
		Threshold = Constants.DragThreshold,
		LongPress = Constants.LongPressTime,
		Began = function()
			startPos = button.AbsolutePosition
			Animations.Tween(scale, { Scale = 0.92 }, 0.1)
		end,
		Moved = function(_, _, total)
			local s = button.AbsoluteSize
			local pos = Device.ClampToScreen(startPos + total, s, 4)
			if QuickToggles.EditMode then
				local g = QuickToggles.GridSize
				pos = Vector2.new(math.floor(pos.X / g + 0.5) * g, math.floor(pos.Y / g + 0.5) * g)
			end
			button.Position = UDim2.fromOffset(pos.X, pos.Y)
		end,
		Ended = function(_, wasDrag)
			Animations.Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
			if wasDrag then
				savePosition(pin)
				applyPosition(pin, true)
				savePosition(pin)
			end
		end,
		Tap = function()
			if QuickToggles.EditMode or toggle.Disabled then
				Animations.Bounce(scale, 0.9)
				return
			end
			Kit.Sound("Toggle")
			toggle:Toggle()
			Animations.Bounce(scale, 0.8)
		end,
		LongPressed = function()
			Animations.Bounce(scale, 1.1)
			openMenu(pin)
		end,
	}))

	pin.Maid:Give(toggle.Changed:Connect(function()
		pin:Render(true)
	end))
	pin.Maid:Give(Theme:OnChanged({ "QuickToggleSize" }, function()
		pin:Render()
		applyPosition(pin, false)
	end))
	pin.Maid:Give(State.ViewportChanged:Connect(function()
		applyPosition(pin, false)
	end))
	pin.Maid:Give(QuickToggles.EditModeChanged:Connect(function()
		pin:Render(true)
	end))

	pin:Render()
	applyPosition(pin, false)
	scale.Scale = 0
	Animations.Tween(scale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
	return pin
end

function QuickToggles.SetPinned(toggle: any, pinned: boolean, data: any?)
	local key = keyOf(toggle)
	local existing = QuickToggles.Pins[key]
	if pinned then
		local d = data or QuickToggles.Saved[key] or defaultPosition()
		local clean = {
			X = math.clamp(tonumber(d.X) or 0.4, 0, 1),
			Y = math.clamp(tonumber(d.Y) or 0.25, 0, 1),
			Size = if QuickToggles.SizeScale[d.Size] then d.Size else "M",
			Transparency = math.clamp(tonumber(d.Transparency) or 0, 0, 0.9),
		}
		if existing then
			existing.Data = clean
			existing:Render(true)
			applyPosition(existing, true)
		else
			QuickToggles.Pins[key] = createPin(toggle, key, clean)
			if not hintShown and not data then
				hintShown = true
				Import("Components/Notifications").Notify({
					Title = "Pinned to screen",
					Content = "Tap to toggle, drag to move, long-press for size, transparency and unpin.",
					Type = "Info",
					Duration = 4,
				})
			end
		end
		QuickToggles.Saved[key] = table.clone(clean)
	else
		if existing then
			local button = existing.Button
			local tween = Animations.Tween(existing.Scale, { Scale = 0 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			if tween then
				tween.Completed:Once(function()
					existing.Maid:Clean()
				end)
			else
				existing.Maid:Clean()
			end
			local _ = button
		end
		QuickToggles.Pins[key] = nil
		QuickToggles.Saved[key] = nil
	end
	if toggle._PinChanged then
		toggle:_PinChanged(pinned)
	end
end

------------------------------------------------------------------------------
-- Edit mode (grid overlay + done button)
------------------------------------------------------------------------------
function QuickToggles.SetEditMode(enabled: boolean)
	if QuickToggles.EditMode == enabled then
		return
	end
	QuickToggles.EditMode = enabled
	closeMenu()
	if QuickToggles._overlay then
		QuickToggles._overlay:Destroy()
		QuickToggles._overlay = nil
	end
	if enabled then
		local layer = Gui.Layer("Mobile")
		local overlay = Create("Frame", {
			Name = "EditGrid",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = layer,
		})
		QuickToggles._overlay = overlay
		local vp = Utility.Viewport()
		local step = QuickToggles.GridSize * 4
		for x = 0, vp.X, step do
			local line = Create("Frame", { Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, 1, 1, 0), Parent = overlay })
			Kit.Bind(line, "BackgroundColor3", "Accent")
			line.BackgroundTransparency = 0.9
		end
		for y = 0, vp.Y, step do
			local line = Create("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), Parent = overlay })
			Kit.Bind(line, "BackgroundColor3", "Accent")
			line.BackgroundTransparency = 0.9
		end
		local done = Create("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, Utility.GuiInset().Y + 10),
			Size = UDim2.fromOffset(170, 44),
			ZIndex = 6,
			Parent = overlay,
		})
		Kit.AccentFill(done, "Button")
		Kit.Corner(done, "pill")
		Kit.Label({
			Text = Constants.Strings.Done .. "  ✓",
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6,
			Parent = done,
		}, "Heading", "AccentText")
		done.MouseButton1Click:Connect(function()
			QuickToggles.SetEditMode(false)
		end)
	end
	QuickToggles.EditModeChanged:Fire(enabled)
end

function QuickToggles.UnpinAll()
	for _, pin in table.clone(QuickToggles.Pins) do
		QuickToggles.SetPinned(pin.Toggle, false)
	end
end

function QuickToggles.Destroy()
	closeMenu()
	QuickToggles.SetEditMode(false)
	for _, pin in QuickToggles.Pins do
		pin.Maid:Clean()
	end
	table.clear(QuickToggles.Pins)
end

return QuickToggles
