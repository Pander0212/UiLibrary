--[[
	Display elements: Label, Paragraph, Divider, Tags (chips), StatusCard

	  Section:AddLabel({ Text, Color = "Text", Role = "Body", Icon })      -> :Set(text)
	  Section:AddParagraph({ Title, Content })                             -> :Set({Title, Content})
	  Section:AddDivider({ Text = nil })
	  Section:AddTags({ Tags = { "Live", {Text = "Beta", Color = "Warning", Icon = "bolt"} } }) -> :SetTags(list)
	  Section:AddStatusCard({ Title, Subtitle, Icon, Status = "Success" }) -> :SetStatus(text, colorKey)
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Element = Import("Components/Element")
local Tooltip = Import("Components/Tooltip")

local Create = Utility.Create

local Display = {}

local function plainRoot(self: any, name: string): Frame
	local section = self.Section
	local root = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = section:_NextOrder(),
	})
	self.Root = root
	self.Maid:Give(root)
	self.Maid:Give(Tooltip.Attach(root, function()
		return self.TooltipText
	end))
	root.Parent = section.Container
	return root
end

------------------------------------------------------------------------------
-- Label
------------------------------------------------------------------------------
local Label = setmetatable({}, { __index = Element })
Label.__index = Label
Display.Label = Label

function Label.new(section: any, options: any)
	local opts = if type(options) == "string" then { Text = options } else options or {}
	local self = Element.new(section, opts, "Label", Label)
	local root = plainRoot(self, "Label")
	self.Value = tostring(opts.Text or opts.Title or "")
	local offset = 0
	if opts.Icon then
		Kit.Icon(opts.Icon, { Size = UDim2.fromOffset(15, 15), Position = UDim2.fromOffset(2, 2), Parent = root }, opts.Color or "TextMuted")
		offset = 22
	end
	self.Label = Kit.Label({
		Text = self.Value,
		Position = UDim2.fromOffset(offset, 0),
		Size = UDim2.new(1, -offset, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		RichText = opts.RichText == true,
		TextTruncate = Enum.TextTruncate.None,
		Parent = root,
	}, opts.Role or "Body", opts.Color or "Text")
	return self
end

function Label:Set(text: any)
	self.Value = tostring(text)
	self.Label.Text = self.Value
end

function Label:SetColor(colorKey: string)
	Kit.Bind(self.Label, "TextColor3", colorKey)
end

------------------------------------------------------------------------------
-- Paragraph
------------------------------------------------------------------------------
local Paragraph = setmetatable({}, { __index = Element })
Paragraph.__index = Paragraph
Display.Paragraph = Paragraph

function Paragraph.new(section: any, options: any)
	local self = Element.new(section, options, "Paragraph", Paragraph)
	local o = self.Options
	local root = plainRoot(self, "Paragraph")
	Kit.Panel(root, "Surface", "Panel")
	Kit.Corner(root, 0.7)
	Kit.Stroke(root, "Border")
	Kit.Padding(root, "Inner")
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = root })
	self.TitleLabel = Kit.Label({
		Text = tostring(o.Title or ""),
		Visible = o.Title ~= nil,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = root,
	}, "Heading", "Text")
	self.ContentLabel = Kit.Label({
		Text = tostring(o.Content or ""),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		RichText = o.RichText == true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
		Parent = root,
	}, "Small", "TextMuted")
	return self
end

function Paragraph:Set(value: any)
	if type(value) == "table" then
		if value.Title ~= nil then
			self.TitleLabel.Text = tostring(value.Title)
			self.TitleLabel.Visible = true
		end
		if value.Content ~= nil then
			self.ContentLabel.Text = tostring(value.Content)
		end
	else
		self.ContentLabel.Text = tostring(value)
	end
end

function Paragraph:SetContent(text: string)
	self.ContentLabel.Text = text
end

------------------------------------------------------------------------------
-- Divider
------------------------------------------------------------------------------
local Divider = setmetatable({}, { __index = Element })
Divider.__index = Divider
Display.Divider = Divider

function Divider.new(section: any, options: any)
	local opts = if type(options) == "string" then { Text = options } else options or {}
	local self = Element.new(section, opts, "Divider", Divider)
	local root = plainRoot(self, "Divider")
	root.AutomaticSize = Enum.AutomaticSize.None
	root.Size = UDim2.new(1, 0, 0, if opts.Text then 18 else 9)
	if opts.Text then
		local label = Kit.Label({
			Text = string.upper(tostring(opts.Text)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 2,
			Parent = root,
		}, "Tiny", "TextMuted")
		local function line(left: boolean)
			local l = Create("Frame", {
				AnchorPoint = Vector2.new(if left then 0 else 1, 0.5),
				Position = UDim2.fromScale(if left then 0 else 1, 0.5),
				Size = UDim2.new(0.5, -40, 0, 1),
				Parent = root,
			})
			Kit.Bind(l, "BackgroundColor3", "Border")
			return l
		end
		local left, right = line(true), line(false)
		local function fit()
			local w = label.AbsoluteSize.X / 2 + 8
			left.Size = UDim2.new(0.5, -w, 0, 1)
			right.Size = UDim2.new(0.5, -w, 0, 1)
		end
		self.Maid:Give(label:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
		task.defer(fit)
	else
		local l = Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 1),
			Parent = root,
		})
		Kit.Bind(l, "BackgroundColor3", "Border")
	end
	return self
end

------------------------------------------------------------------------------
-- Tags / chips
------------------------------------------------------------------------------
local Tags = setmetatable({}, { __index = Element })
Tags.__index = Tags
Display.Tags = Tags

-- Builds chips into `parent` (also used by page headers). Returns created chips.
function Display.BuildChips(parent: Instance, list: { any }): { Frame }
	local chips = {}
	for index, tag in list do
		local data = if type(tag) == "table" then tag else { Text = tostring(tag) }
		local colorKey = data.Color or "Accent"
		local chip = Create("Frame", {
			Name = "Chip",
			Size = UDim2.new(0, 0, 0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = index,
			Parent = parent,
		})
		Kit.Bind(chip, "BackgroundColor3", colorKey)
		Kit.Bind(chip, "BackgroundTransparency", { colorKey }, function()
			return 0.84
		end)
		Kit.Corner(chip, "pill")
		Create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), Parent = chip })
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 5),
			Parent = chip,
		})
		if data.Icon then
			Kit.Icon(data.Icon, { Size = UDim2.fromOffset(11, 11), LayoutOrder = 1, Parent = chip }, colorKey)
		end
		Kit.Label({
			Text = tostring(data.Text or ""),
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
			Parent = chip,
		}, "Tiny", colorKey)
		table.insert(chips, chip)
	end
	return chips
end

function Tags.new(section: any, options: any)
	local opts = if type(options) == "table" and options.Tags == nil and #options > 0 then { Tags = options } else options or {}
	local self = Element.new(section, opts, "Tags", Tags)
	local root = plainRoot(self, "Tags")
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Wraps = true,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = root,
	})
	self.Value = opts.Tags or {}
	self.Chips = Display.BuildChips(root, self.Value)
	return self
end

function Tags:SetTags(list: { any })
	for _, chip in self.Chips do
		chip:Destroy()
	end
	self.Value = list
	self.Chips = Display.BuildChips(self.Root, list)
end
Tags.Set = Tags.SetTags

------------------------------------------------------------------------------
-- Status card
------------------------------------------------------------------------------
local StatusCard = setmetatable({}, { __index = Element })
StatusCard.__index = StatusCard
Display.StatusCard = StatusCard

function StatusCard.new(section: any, options: any)
	local self = Element.new(section, options, "StatusCard", StatusCard)
	local o = self.Options
	self.StatusKey = o.Status or o.Color or "Success"
	local root = plainRoot(self, "StatusCard")
	root.AutomaticSize = Enum.AutomaticSize.None
	Kit.Bind(root, "Size", { "Spacing" }, function(T)
		return UDim2.new(1, 0, 0, Theme:Metric("Row", T) + 18)
	end)
	Kit.Panel(root, "Surface", "Panel")
	Kit.Corner(root, 0.8)
	Kit.Stroke(root, "Border")
	Kit.Padding(root, "Inner", 0)

	local badge = Create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(36, 36),
		Parent = root,
	})
	Kit.Corner(badge, 0.8)
	Kit.Bind(badge, "BackgroundColor3", { "Success", "Warning", "Danger", "Accent", "Accent2", "TextMuted" }, function(T)
		return T[self.StatusKey] or T.Accent
	end)
	Kit.Bind(badge, "BackgroundTransparency", { "Accent" }, function()
		return 0.84
	end)
	self.Badge = badge
	self.Icon = Kit.Icon(o.Icon or "activity", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		Parent = badge,
	}, self.StatusKey)

	local text = Create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -48, 1, 0),
		Parent = root,
	})
	Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2),
		Parent = text,
	})
	self.TitleLabel = Kit.Label({
		Text = tostring(o.Title or "Status"),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = text,
	}, "Heading", "Text")
	self.SubtitleLabel = Kit.Label({
		Text = tostring(o.Subtitle or ""),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = text,
	}, "Small", self.StatusKey)
	Kit.Bind(self.SubtitleLabel, "TextColor3", { "Success", "Warning", "Danger", "Accent", "Accent2", "TextMuted" }, function(T)
		return T[self.StatusKey] or T.Accent
	end)
	return self
end

function StatusCard:SetStatus(subtitle: string?, colorKey: string?)
	if subtitle then
		self.SubtitleLabel.Text = subtitle
	end
	if colorKey then
		self.StatusKey = colorKey
		Kit.Refresh(self.Badge, "BackgroundColor3")
		Kit.Refresh(self.SubtitleLabel, "TextColor3")
		Kit.SetIconColor(self.Icon, colorKey)
	end
end
StatusCard.Set = function(self, value: any)
	if type(value) == "table" then
		self:SetStatus(value.Subtitle, value.Status)
		if value.Title then
			self.TitleLabel.Text = value.Title
		end
	else
		self:SetStatus(tostring(value))
	end
end

function StatusCard:SetIcon(name: string)
	Kit.SetIcon(self.Icon, name)
end

return Display
