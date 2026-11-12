--[[
	Element
	Base class of every section element. Provides:
	  * row frame with themed background/border, hover & focus states
	  * Flag registration (Config), callback dispatch, Changed signal
	  * :Set / :Get (implemented by subclasses), :SetVisible, :SetDisabled,
	    :SetTooltip, :SetTitle, :SetDescription, :OnChanged, :Destroy
	  * tooltip (hover on desktop, long-press on touch)

	Subclass pattern:
	  local Toggle = setmetatable({}, { __index = Element })
	  Toggle.__index = Toggle
	  local self = Element.new(section, options, "Toggle", Toggle)
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Maid = Import("Maid")
local Signal = Import("Signal")
local Config = Import("Config")
local Tooltip = Import("Components/Tooltip")

local Create = Utility.Create

local Element = {}
Element.__index = Element

function Element.new(section: any, options: { [string]: any }?, kind: string, class: any?): any
	local opts = options or {}
	local self = setmetatable({}, class or Element)
	self.Section = section
	self.Window = section and section.Window
	self.Options = opts
	self.Type = kind
	self.Flag = opts.Flag
	self.Callback = opts.Callback
	self.IgnoreConfig = opts.IgnoreConfig == true
	self.NoCallbackOnLoad = opts.NoCallbackOnLoad == true
	self.Maid = Maid.new()
	self.Changed = Signal.new()
	self.Visible = true
	self.Disabled = false
	self.TooltipText = opts.Tooltip
	self.State = { Hover = false, Pressed = false, Focus = false, Disabled = false }
	self._stateful = {} :: { Instance }
	return self
end

------------------------------------------------------------------------------
-- Row construction
------------------------------------------------------------------------------

-- Builds the standard row: Root (auto height) > Main (Row metric height) with a
-- title/description block on the left and a `Control` holder on the right.
-- options.ControlWidth: width of the right control area (px)
-- options.Plain: no background
function Element:_BuildRow(options: { [string]: any }?)
	local opts = options or {}
	local o = self.Options
	local parent = if self.Section then self.Section.Container else nil

	local root = Create("Frame", {
		Name = self.Type .. (if o.Title then "_" .. tostring(o.Title) else ""),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = if self.Section then self.Section:_NextOrder() else 0,
		ClipsDescendants = opts.Clips == true,
	})
	self.Root = root
	self.Maid:Give(root)

	if not opts.Plain then
		self:_Stateful(root, "BackgroundColor3", { "Surface", "Text" }, function(T)
			if self.State.Hover and not self.State.Disabled then
				return Utility.Mix(T.Surface, T.Text, 0.035)
			end
			return T.Surface
		end)
		Kit.Bind(root, "BackgroundTransparency", Theme.AlphaDeps("Surface", "Panel"), function(T)
			return Theme:Alpha("Surface", "Panel", T)
		end)
		Kit.Corner(root, 0.7)
		local stroke = Kit.Stroke(root, "Border", {
			Deps = { "Border", "Accent", "Text" },
			Compute = function(T)
				if self.State.Focus then
					return T.Accent
				elseif self.State.Hover and not self.State.Disabled then
					return Utility.Mix(T.Border, T.Text, 0.12)
				end
				return T.Border
			end,
		})
		table.insert(self._stateful, stroke)
	end

	-- Stack: vertical list (Main + optional expandable panels like dropdown lists)
	local stack = Create("Frame", {
		Name = "Stack",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = stack })
	self.Stack = stack

	local main = Create("Frame", {
		Name = "Main",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = 1,
		Parent = stack,
	})
	self.Main = main
	local extra = opts.ExtraHeight or 0
	local hasDescription = o.Description ~= nil and o.Description ~= ""
	local rowBonus = opts.RowBonus or 0
	Kit.Bind(main, "Size", { "Spacing", "TextScale" }, function(T)
		local h = Theme:Metric("Row", T) + extra + rowBonus
		local description = self.Options.Description
		if description ~= nil and description ~= "" and not opts.NoText then
			h += Theme:TextSize("Small", T) + 2
		end
		return UDim2.new(1, 0, 0, h)
	end)

	local controlWidth = opts.ControlWidth or 0
	if not opts.NoText then
		local textHolder = Create("Frame", {
			Name = "Text",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -(controlWidth + 8), 1, -extra),
			Parent = main,
		})
		Kit.Padding(textHolder, "Inner", 0)
		local list = Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 1),
			Parent = textHolder,
		})
		list.Name = "List"
		self.TitleLabel = Kit.Label({
			Name = "Title",
			Text = tostring(o.Title or o.Text or ""),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = textHolder,
		}, "Body", "Text")
		self.DescriptionLabel = Kit.Label({
			Name = "Description",
			Text = tostring(o.Description or ""),
			Visible = hasDescription,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = textHolder,
		}, "Small", "TextMuted")
		self.TextHolder = textHolder
	end

	if controlWidth > 0 then
		local control = Create("Frame", {
			Name = "Control",
			BackgroundTransparency = 1,
			ZIndex = 3, -- above row hitboxes so buttons inside stay clickable
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.new(0, controlWidth, 1, -extra),
			Position = UDim2.new(1, 0, 0.5, -extra / 2),
			Parent = main,
		})
		Kit.Padding(control, "Inner", 0)
		self.Control = control
	end

	-- hover state
	self.Maid:Give(root.MouseEnter:Connect(function()
		self:_SetState("Hover", true)
	end))
	self.Maid:Give(root.MouseLeave:Connect(function()
		self:_SetState("Hover", false)
	end))

	-- tooltip
	self.Maid:Give(Tooltip.Attach(root, function()
		return self.TooltipText
	end))

	root.Parent = parent
	return root
end

-- Disabled cover (sinks input). Created lazily.
function Element:_Cover(): TextButton
	if self._cover then
		return self._cover
	end
	local cover = Create("TextButton", {
		Name = "DisabledCover",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Visible = false,
		Parent = self.Root,
	})
	Kit.Bind(cover, "BackgroundColor3", "Card")
	Kit.Bind(cover, "BackgroundTransparency", { "Card" }, function()
		return 0.45
	end)
	Kit.Corner(cover, 0.7)
	self._cover = cover
	return cover
end

------------------------------------------------------------------------------
-- State helpers
------------------------------------------------------------------------------

-- Binds a property whose value also depends on element state (hover, focus...)
function Element:_Stateful(inst: Instance, property: string, deps: { string }, compute: (any) -> any, options: any?)
	Kit.Bind(inst, property, deps, compute, options)
	if not table.find(self._stateful, inst) then
		table.insert(self._stateful, inst)
	end
end

function Element:_SetState(name: string, value: boolean)
	if self.State[name] == value then
		return
	end
	self.State[name] = value
	for _, inst in self._stateful do
		Kit.Refresh(inst)
	end
	if self._OnState then
		self:_OnState(name, value)
	end
end

------------------------------------------------------------------------------
-- Flag / callback
------------------------------------------------------------------------------
function Element:_Register()
	if self.Flag then
		Config:Register(self)
	end
end

-- Fires callback + Changed. `fromConfig` respects NoCallbackOnLoad.
function Element:_Fire(value: any, fromConfig: boolean?)
	self.Changed:Fire(value)
	if self.Flag then
		Config.FlagChanged:Fire(self.Flag, value)
	end
	if fromConfig and self.NoCallbackOnLoad then
		return
	end
	Utility.SafeCallback(self.Callback, value)
end

function Element:OnChanged(fn: (any) -> ())
	return self.Changed:Connect(fn)
end

-- Default serialisation: the raw value
function Element:Serialize(): any
	return self:Get()
end

function Element:Deserialize(value: any)
	self:Set(value, false, true)
end

function Element:Get(): any
	return self.Value
end

function Element:Set(value: any, _silent: boolean?, _fromConfig: boolean?)
	self.Value = value
end

------------------------------------------------------------------------------
-- Common API
------------------------------------------------------------------------------
function Element:SetVisible(visible: boolean)
	self.Visible = visible
	if self.Root then
		self.Root.Visible = visible
	end
end

function Element:SetDisabled(disabled: boolean)
	self.Disabled = disabled
	self:_SetState("Disabled", disabled)
	if self.Root then
		self:_Cover().Visible = disabled
	end
end

function Element:SetTooltip(text: string?)
	self.TooltipText = text
end

function Element:SetTitle(text: string)
	self.Options.Title = text
	if self.TitleLabel then
		self.TitleLabel.Text = text
	end
end

function Element:SetDescription(text: string?)
	self.Options.Description = text
	if self.DescriptionLabel then
		self.DescriptionLabel.Text = text or ""
		self.DescriptionLabel.Visible = text ~= nil and text ~= ""
		Kit.Refresh(self.Main, "Size")
	end
end

-- Shows the tooltip at a position (used for touch long-press)
function Element:_ShowTouchTooltip(position: Vector2)
	if self.TooltipText then
		Tooltip.ShowAt(self.TooltipText, position, 2.5)
	end
end

function Element:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	Config:Unregister(self)
	self.Changed:Destroy()
	self.Maid:Clean()
	if self.Section then
		self.Section:_RemoveElement(self)
	end
end

return Element
