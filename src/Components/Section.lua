--[[
	Section / Card
	A titled card inside a page column. All element factory methods live here.

	  local Sec = Tab:AddSection("ESP")
	  local Sec = Page:AddSection({ Title = "Aimbot", Icon = "target", Description = "...",
	                                Side = "Left" | "Right", Collapsible = false })
	  Page:AddCard({...})  -- same as AddSection (title optional)
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Maid = Import("Maid")
local Animations = Import("Animations")

local Create = Utility.Create

local Section = {}
Section.__index = Section

function Section.new(page: any, options: any)
	local opts = if type(options) == "string" then { Title = options } else options or {}
	local self = setmetatable({}, Section)
	self.Page = page
	self.Window = page.Window
	self.Options = opts
	self.Elements = {} :: { any }
	self.Maid = Maid.new()
	self._order = 0
	self.Collapsed = false

	local root = Create("Frame", {
		Name = "Section_" .. tostring(opts.Title or "Card"),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	self.Root = root
	self.Maid:Give(root)
	Kit.Panel(root, "Card", "Panel")
	Kit.Corner(root, 1)
	Kit.Stroke(root, "Border")
	Kit.Padding(root, "Section")
	Kit.List(root, "Vertical", "Gap")

	if opts.Title or opts.Icon then
		local header = Create("TextButton", {
			Name = "Header",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 0,
			Parent = root,
		})
		local offset = 0
		if opts.Icon then
			local badge = Create("Frame", {
				Size = UDim2.fromOffset(26, 26),
				Parent = header,
			})
			Kit.Bind(badge, "BackgroundColor3", opts.IconColor or "Accent")
			Kit.Bind(badge, "BackgroundTransparency", { "Accent" }, function()
				return 0.85
			end)
			Kit.Corner(badge, 0.6)
			Kit.Icon(opts.Icon, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(14, 14),
				Parent = badge,
			}, opts.IconColor or "Accent")
			offset = 34
		end
		local texts = Create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(offset, 0),
			Size = UDim2.new(1, -offset - (if opts.Collapsible then 20 else 0), 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = header,
		})
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1), Parent = texts })
		Create("UISizeConstraint", { MinSize = Vector2.new(0, 26), Parent = texts })
		self.TitleLabel = Kit.Label({
			Text = tostring(opts.Title or ""),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = texts,
		}, "Heading", "Text")
		if opts.Description then
			Kit.Label({
				Text = tostring(opts.Description),
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				LayoutOrder = 2,
				Parent = texts,
			}, "Small", "TextMuted")
		end
		if opts.Collapsible then
			local chevron = Kit.Icon("chevron-down", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 6),
				Size = UDim2.fromOffset(12, 12),
				Parent = header,
			}, "TextMuted")
			self.Chevron = chevron
			self.Maid:Give(header.MouseButton1Click:Connect(function()
				self:SetCollapsed(not self.Collapsed)
			end))
		end
		self.Header = header
	end

	local container = Create("Frame", {
		Name = "Container",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = root,
	})
	Kit.List(container, "Vertical", "Gap")
	self.Container = container

	if opts.Collapsed then
		self:SetCollapsed(true)
	end
	return self
end

function Section:_NextOrder(): number
	self._order += 1
	return self._order
end

function Section:_Add(element: any): any
	table.insert(self.Elements, element)
	return element
end

function Section:_RemoveElement(element: any)
	local index = table.find(self.Elements, element)
	if index then
		table.remove(self.Elements, index)
	end
end

function Section:SetCollapsed(collapsed: boolean)
	self.Collapsed = collapsed
	self.Container.Visible = not collapsed
	if self.Chevron then
		Animations.Tween(self.Chevron, { Rotation = if collapsed then -90 else 0 }, 0.2)
	end
end

function Section:SetTitle(text: string)
	if self.TitleLabel then
		self.TitleLabel.Text = text
	end
end

function Section:SetVisible(visible: boolean)
	self.Root.Visible = visible
end

function Section:Destroy()
	for _, element in table.clone(self.Elements) do
		element:Destroy()
	end
	self.Maid:Clean()
	if self.Page then
		self.Page:_RemoveSection(self)
	end
end

------------------------------------------------------------------------------
-- Element factories
------------------------------------------------------------------------------
local function factory(moduleName: string, member: string?, defaults: { [string]: any }?)
	return function(self, options: any)
		local opts = options
		if defaults then
			opts = if type(options) == "table" then table.clone(options) else { Title = options }
			for k, v in defaults do
				if opts[k] == nil then
					opts[k] = v
				end
			end
		end
		local module = Import(moduleName)
		local class = if member then module[member] else module
		return self:_Add(class.new(self, opts))
	end
end

Section.AddButton = factory("Components/Button")
Section.AddToggle = factory("Components/Toggle")
Section.AddCheckbox = factory("Components/Toggle", nil, { Style = "Checkbox" })
Section.AddSlider = factory("Components/Slider")
Section.AddDropdown = factory("Components/Dropdown")
Section.AddTextbox = factory("Components/Textbox")
Section.AddInput = Section.AddTextbox
Section.AddKeybind = factory("Components/Keybind")
Section.AddColorPicker = factory("Components/ColorPicker")
Section.AddColorpicker = Section.AddColorPicker
Section.AddLabel = factory("Components/Display", "Label")
Section.AddParagraph = factory("Components/Display", "Paragraph")
Section.AddDivider = factory("Components/Display", "Divider")
Section.AddTags = factory("Components/Display", "Tags")
Section.AddStatusCard = factory("Components/Display", "StatusCard")
Section.AddStatCard = factory("Components/Chart", "StatCard")
Section.AddChart = factory("Components/Chart", "LineChart")

function Section:AddESPPreview(options: any)
	return self:_Add(Import("ESPPreview").new(self, options))
end

local _ = Theme

return Section
