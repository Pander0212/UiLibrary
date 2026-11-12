--[[
	Button
	  Section:AddButton({
	      Title = "Execute", Description = nil, Icon = "bolt",
	      Style = "Default" | "Primary" | "Danger" | "Dashed",
	      Size = "Normal" | "Large",
	      Tooltip = "...", Callback = function() end,
	  })
	Ripple + press scale (0.97) + hover overlay + disabled state.
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Input = Import("Input")
local Element = Import("Components/Element")

local Create = Utility.Create

local Button = setmetatable({}, { __index = Element })
Button.__index = Button

local TEXT_COLOR = { Default = "Text", Primary = "AccentText", Danger = "AccentText", Dashed = "TextMuted" }

function Button.new(section: any, options: { [string]: any })
	local self = Element.new(section, options, "Button", Button)
	local o = self.Options
	local style = if TEXT_COLOR[o.Style] then o.Style else "Default"
	local large = o.Size == "Large"
	self.Style = style

	self:_BuildRow({ Plain = true, NoText = true, RowBonus = if large then 10 else 0 })

	local body = Create("TextButton", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = self.Main,
	})
	self.Body = body
	Kit.Corner(body, 0.7)

	if style == "Primary" then
		Kit.AccentFill(body, "Button", "Accent", "Panel")
	elseif style == "Danger" then
		Kit.Panel(body, "Danger", "Panel")
	elseif style == "Dashed" then
		body.BackgroundTransparency = 1
		Kit.Dashed(body, "Border")
	else
		Kit.Panel(body, "Surface", "Panel")
		local stroke = Kit.Stroke(body, "Border", {
			Deps = { "Border", "Accent" },
			Compute = function(T)
				return if self.State.Hover then Utility.Mix(T.Border, T.Accent, 0.45) else T.Border
			end,
		})
		table.insert(self._stateful, stroke)
	end

	-- hover overlay (works on solid, gradient and dashed bodies)
	local overlay = Create("Frame", {
		Name = "Hover",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = body,
	})
	Kit.Corner(overlay, 0.7)
	self:_Stateful(overlay, "BackgroundColor3", { "Text", "AccentText" }, function(T)
		return if style == "Default" or style == "Dashed" then T.Text else T.AccentText
	end)
	self:_Stateful(overlay, "BackgroundTransparency", { "Text" }, function()
		if self.State.Pressed then
			return 0.86
		elseif self.State.Hover then
			return 0.93
		end
		return 1
	end)

	local content = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = body,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = if o.Align == "Left" then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = content,
	})
	Kit.Padding(content, "Inner", 0)

	local textKey = TEXT_COLOR[style]
	local icon = o.Icon or (if style == "Dashed" then "plus" else nil)
	if icon then
		self.Icon = Kit.Icon(icon, {
			Size = UDim2.fromOffset(if large then 18 else 15, if large then 18 else 15),
			LayoutOrder = 1,
			ZIndex = 3,
			Parent = content,
		}, textKey)
	end
	self.TitleLabel = Kit.Label({
		Name = "Title",
		Text = tostring(o.Title or "Button"),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = content,
	}, if large then "Title" else "Heading", textKey)
	if style == "Dashed" then
		-- dashed "add" buttons light up in the accent colour on hover
		self:_Stateful(self.TitleLabel, "TextColor3", { "TextMuted", "Accent" }, function(T)
			return if self.State.Hover then T.Accent else T.TextMuted
		end)
	end

	Animations.AttachPress(body, self.Root, 0.97)

	self.Maid:Give(body.MouseEnter:Connect(function()
		self:_SetState("Hover", true)
	end))
	self.Maid:Give(body.MouseLeave:Connect(function()
		self:_SetState("Hover", false)
		self:_SetState("Pressed", false)
	end))
	self.Maid:Give(Input.Track(body, {
		LongPress = if o.Tooltip then 0.5 else nil,
		LongPressed = function(pos)
			self:_ShowTouchTooltip(pos)
		end,
		Began = function()
			self:_SetState("Pressed", true)
		end,
		Ended = function()
			self:_SetState("Pressed", false)
		end,
		Tap = function(pos)
			if self.Disabled then
				return
			end
			Animations.Ripple(body, pos, textKey)
			Kit.Sound("Click")
			self:Fire()
		end,
	}))

	return self
end

function Button:Fire()
	Utility.SafeCallback(self.Callback)
	self.Changed:Fire()
end

function Button:SetTitle(text: string)
	self.Options.Title = text
	self.TitleLabel.Text = text
end

function Button:SetIcon(name: string?)
	if self.Icon then
		Kit.SetIcon(self.Icon, name)
	end
end

function Button:SetCallback(fn: () -> ())
	self.Callback = fn
end

function Button:Get(): any
	return nil
end

function Button:Set(_value: any) end

-- unused reference keeps Theme import intentional for future style keys
local _ = Theme

return Button
