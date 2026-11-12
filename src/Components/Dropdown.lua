--[[
	Dropdown (single / multi, optional search)
	  Section:AddDropdown({
	      Title, Description, Flag, Values = {"A", "B"}, Default = "A" | {"A"},
	      Multi = false, Search = nil (auto when > 8 values), Placeholder = "Select...",
	      AllowNone = false, MaxHeight = 190, Callback = function(value) end,
	  })
	  Dropdown:Set(value) :Get() :Refresh(values, keepSelection?) :Open() :Close()
	Single -> string | nil, Multi -> { string } (in list order).
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Input = Import("Input")
local Constants = Import("Constants")
local Element = Import("Components/Element")

local Create = Utility.Create

local Dropdown = setmetatable({}, { __index = Element })
Dropdown.__index = Dropdown

local function toStringList(values: any): { string }
	local list = {}
	if type(values) == "table" then
		for _, v in values do
			table.insert(list, tostring(v))
		end
	end
	return list
end

function Dropdown.new(section: any, options: { [string]: any })
	local self = Element.new(section, options, "Dropdown", Dropdown)
	local o = self.Options
	self.Multi = o.Multi == true
	self.Values = toStringList(o.Values)
	self.AllowNone = o.AllowNone == true or self.Multi
	self.Placeholder = o.Placeholder or "Select..."
	self.MaxHeight = o.MaxHeight or 190
	self.Opened = false
	self.Items = {} :: { [string]: any }
	if self.Multi then
		self.Value = {}
		if type(o.Default) == "table" then
			self.Value = self:_FilterMulti(o.Default)
		elseif o.Default ~= nil then
			self.Value = self:_FilterMulti({ o.Default })
		end
	else
		local default = if o.Default ~= nil then tostring(o.Default) else nil
		self.Value = if default and table.find(self.Values, default) then default else nil
		if self.Value == nil and not self.AllowNone then
			self.Value = self.Values[1]
		end
	end

	self:_BuildRow({ ControlWidth = 168 })

	-- selection box
	local box = Create("TextButton", {
		Name = "Box",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = self.Control,
	})
	Kit.Bind(box, "Size", { "Spacing" }, function(T)
		return UDim2.new(1, 0, 0, math.max(Theme:Metric("Row", T) - 12, 26))
	end)
	self:_Stateful(box, "BackgroundColor3", { "Input", "Text" }, function(T)
		return if self.State.Hover then Utility.Mix(T.Input, T.Text, 0.04) else T.Input
	end)
	Kit.Bind(box, "BackgroundTransparency", Theme.AlphaDeps("Input", "Panel"), function(T)
		return Theme:Alpha("Input", "Panel", T)
	end)
	Kit.Corner(box, 0.6)
	local boxStroke = Kit.Stroke(box, "Border", {
		Deps = { "Border", "Accent" },
		Compute = function(T)
			return if self.Opened then T.Accent else T.Border
		end,
	})
	table.insert(self._stateful, boxStroke)
	self.SelectedLabel = Kit.Label({
		Name = "Selected",
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -34, 1, 0),
		Parent = box,
	}, "Small", "Text")
	Kit.Bind(self.SelectedLabel, "TextColor3", { "Text", "TextMuted" }, function(T)
		local empty = if self.Multi then #self.Value == 0 else self.Value == nil
		return if empty then T.TextMuted else T.Text
	end)
	local chevron = Kit.Icon("chevron-down", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -9, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		Parent = box,
	}, "TextMuted")
	self.Chevron = chevron
	self.Box = box
	Animations.AttachPress(box, box, 0.97)

	-- expandable list (inside the row's stack)
	local listHolder = Create("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		LayoutOrder = 2,
		Visible = false,
		Parent = self.Stack,
	})
	self.ListHolder = listHolder
	local inner = Create("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = listHolder,
	})
	Kit.Padding(inner, "Inner", 0)
	local innerList = Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = inner,
	})
	self.Inner = inner
	self._innerList = innerList

	local useSearch = if o.Search == nil then #self.Values > 8 else o.Search == true
	if useSearch then
		local searchBox = Kit.TextBox({
			Name = "Search",
			Size = UDim2.new(1, 0, 0, 28),
			PlaceholderText = Constants.Strings.Search,
			LayoutOrder = 1,
			Parent = inner,
		}, "Small")
		Kit.Panel(searchBox, "Input", "Panel")
		Kit.Corner(searchBox, 0.6)
		Kit.Stroke(searchBox, "Border")
		Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = searchBox })
		self.Maid:Give(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			self:_Filter(searchBox.Text)
		end))
		self.SearchBox = searchBox
	end

	local scroll = Kit.Scrolling({
		Name = "Items",
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 2,
		Parent = inner,
	})
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = scroll })
	self.Scroll = scroll

	self.Maid:Give(Input.Track(box, {
		LongPress = if o.Tooltip then 0.5 else nil,
		LongPressed = function(pos)
			self:_ShowTouchTooltip(pos)
		end,
		Tap = function()
			if not self.Disabled then
				Kit.Sound("Click")
				if self.Opened then
					self:Close()
				else
					self:Open()
				end
			end
		end,
	}))

	self:_BuildItems()
	self:_RenderText()
	self:_Register()
	return self
end

------------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------------
function Dropdown:_ItemHeight(): number
	return if Theme.TouchMode then 40 else math.max(Theme:Metric("Row") - 8, 28)
end

function Dropdown:_IsSelected(value: string): boolean
	if self.Multi then
		return table.find(self.Value, value) ~= nil
	end
	return self.Value == value
end

function Dropdown:_BuildItems()
	for _, item in self.Items do
		item.Button:Destroy()
	end
	table.clear(self.Items)
	for index, value in self.Values do
		local button = Create("TextButton", {
			Name = "Item",
			Size = UDim2.new(1, -4, 0, self:_ItemHeight()),
			LayoutOrder = index,
			Parent = self.Scroll,
		})
		Kit.Corner(button, 0.5)
		local hovered = false
		Kit.Bind(button, "BackgroundColor3", { "Accent", "Surface", "Text" }, function(T)
			if self:_IsSelected(value) then
				return T.Accent
			end
			return if hovered then Utility.Mix(T.Surface, T.Text, 0.06) else T.Surface
		end)
		Kit.Bind(button, "BackgroundTransparency", { "Accent" }, function()
			if self:_IsSelected(value) then
				return 0.82
			end
			return if hovered then 0.2 else 1
		end)
		local label = Kit.Label({
			Text = value,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -36, 1, 0),
			Parent = button,
		}, "Small", "Text")
		Kit.Bind(label, "TextColor3", { "Text", "Accent" }, function(T)
			return if self:_IsSelected(value) then T.Accent else T.Text
		end)
		local check = Kit.Icon("check", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			Parent = button,
		}, "Accent")
		local item = { Button = button, Label = label, Check = check, Value = value }
		local function refresh()
			Kit.Refresh(button)
			Kit.Refresh(label)
			check.Visible = self:_IsSelected(value)
		end
		item.Refresh = refresh
		button.MouseEnter:Connect(function()
			hovered = true
			refresh()
		end)
		button.MouseLeave:Connect(function()
			hovered = false
			refresh()
		end)
		button.MouseButton1Click:Connect(function()
			self:_Choose(value)
		end)
		refresh()
		self.Items[value] = item
	end
	if self.SearchBox then
		self:_Filter(self.SearchBox.Text)
	end
	self:_Resize()
end

function Dropdown:_Filter(query: string)
	local q = string.lower(query or "")
	for value, item in self.Items do
		item.Button.Visible = q == "" or string.find(string.lower(value), q, 1, true) ~= nil
	end
	self:_Resize()
end

function Dropdown:_ContentHeight(): number
	local count = 0
	for _, item in self.Items do
		if item.Button.Visible then
			count += 1
		end
	end
	local itemsHeight = count * (self:_ItemHeight() + 2)
	return math.min(itemsHeight, self.MaxHeight)
end

function Dropdown:_Resize()
	local listHeight = self:_ContentHeight()
	self.Scroll.Size = UDim2.new(1, 0, 0, listHeight)
	if self.Opened then
		local searchHeight = if self.SearchBox then 32 else 0
		local target = listHeight + searchHeight + Theme:Metric("Inner") + 2
		Animations.Tween(self.ListHolder, { Size = UDim2.new(1, 0, 0, target) }, 0.25)
	end
end

function Dropdown:_Choose(value: string)
	if self.Disabled then
		return
	end
	Kit.Sound("Click")
	if self.Multi then
		local list = table.clone(self.Value)
		local index = table.find(list, value)
		if index then
			table.remove(list, index)
		else
			table.insert(list, value)
		end
		self:Set(list)
	else
		if self.Value == value and self.AllowNone then
			self:Set(nil)
		else
			self:Set(value)
		end
		self:Close()
	end
end

------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------
function Dropdown:Open()
	if self.Opened then
		return
	end
	self.Opened = true
	self.ListHolder.Visible = true
	self:_SetState("Focus", true)
	Animations.Tween(self.Chevron, { Rotation = 180 }, 0.25)
	self:_Resize()
	for _, inst in self._stateful do
		Kit.Refresh(inst)
	end
end

function Dropdown:Close()
	if not self.Opened then
		return
	end
	self.Opened = false
	self:_SetState("Focus", false)
	Animations.Tween(self.Chevron, { Rotation = 0 }, 0.25)
	local tween = Animations.Tween(self.ListHolder, { Size = UDim2.new(1, 0, 0, 0) }, 0.2)
	local function hide()
		if not self.Opened then
			self.ListHolder.Visible = false
		end
	end
	if tween then
		tween.Completed:Once(hide)
	else
		hide()
	end
	for _, inst in self._stateful do
		Kit.Refresh(inst)
	end
end

------------------------------------------------------------------------------
-- Value
------------------------------------------------------------------------------
function Dropdown:_FilterMulti(list: any): { string }
	local result = {}
	if type(list) ~= "table" then
		return result
	end
	local wanted = {}
	for _, v in list do
		wanted[tostring(v)] = true
	end
	for _, value in self.Values do
		if wanted[value] then
			table.insert(result, value)
		end
	end
	return result
end

function Dropdown:_RenderText()
	local text
	if self.Multi then
		text = if #self.Value > 0 then table.concat(self.Value, ", ") else Constants.Strings.None
	else
		text = if self.Value ~= nil then self.Value else self.Placeholder
	end
	self.SelectedLabel.Text = text
	Kit.Refresh(self.SelectedLabel, "TextColor3")
	for _, item in self.Items do
		item.Refresh()
	end
end

function Dropdown:Set(value: any, silent: boolean?, fromConfig: boolean?)
	local newValue
	if self.Multi then
		newValue = self:_FilterMulti(if type(value) == "table" then value elseif value ~= nil then { value } else {})
	else
		newValue = if value ~= nil then tostring(value) else nil
		if newValue ~= nil and not table.find(self.Values, newValue) then
			return
		end
		if newValue == nil and not self.AllowNone then
			return
		end
		if newValue == self.Value then
			return
		end
	end
	self.Value = newValue
	self:_RenderText()
	local out = if self.Multi then table.clone(newValue) else newValue
	if silent then
		self.Changed:Fire(out)
	else
		self:_Fire(out, fromConfig)
	end
end

function Dropdown:Get(): any
	if self.Multi then
		return table.clone(self.Value)
	end
	return self.Value
end

-- Replaces the option list. keepSelection keeps still-valid selected values.
function Dropdown:Refresh(values: { any }, keepSelection: boolean?)
	self.Values = toStringList(values)
	if self.Multi then
		self.Value = if keepSelection ~= false then self:_FilterMulti(self.Value) else {}
	elseif keepSelection == false or (self.Value and not table.find(self.Values, self.Value)) then
		self.Value = if self.AllowNone then nil else self.Values[1]
	end
	self:_BuildItems()
	self:_RenderText()
end

function Dropdown:Serialize(): any
	return self:Get()
end

function Dropdown:Deserialize(value: any)
	if self.Multi then
		if type(value) == "table" then
			self:Set(value, false, true)
		end
	elseif type(value) == "string" or value == nil then
		if value == nil and not self.AllowNone then
			return
		end
		self:Set(value, false, true)
	end
end

return Dropdown
