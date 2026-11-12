--[[
	Tab, Sidebar category and Page

	  local Tab  = Win:AddTab({ Title = "Visuals", Icon = "eye", Description = "...", Tags = {...} })
	  local Sec  = Tab:AddSection("ESP")              -- sections on the tab's root page
	  local Cat  = Tab:AddCategory({ Title = "Players", Icon = "user", Collapsed = false })
	  local Page = Cat:AddPage({ Title = "ESP", Icon = "eye", Description = "...", Tags = {"Live"} })
	  local Page2 = Tab:AddPage({ Title = "Misc" })    -- sidebar entry without category
	  Page:AddSection({ Title = "Box", Side = "Right" })
	  Tab:SetBadge(true | 3 | false)

	Pages have a big title, optional tag chips and a 2-column card grid (1 column on
	mobile / narrow windows).
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Maid = Import("Maid")
local Section = Import("Components/Section")
local Display = Import("Components/Display")

local Create = Utility.Create

------------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------------
local Page = {}
Page.__index = Page

function Page.new(window: any, tab: any, options: { [string]: any })
	local self = setmetatable({}, Page)
	self.Window = window
	self.Tab = tab
	self.Options = options
	self.Sections = {} :: { any }
	self.Maid = Maid.new()
	self._alternate = 0

	local scroll = Kit.Scrolling({
		Name = "Page_" .. tostring(options.Title or "Page"),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = window.Content,
	})
	self.Scroll = scroll
	self.Maid:Give(scroll)
	Kit.Padding(scroll, "Padding")
	Kit.List(scroll, "Vertical", "Section")

	-- header
	local header = Create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = scroll,
	})
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = header })
	self.TitleLabel = Kit.Label({
		Text = tostring(options.Title or ""),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = header,
	}, "Display", "Text")
	self.DescriptionLabel = Kit.Label({
		Text = tostring(options.Description or ""),
		Visible = options.Description ~= nil,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 2,
		Parent = header,
	}, "Small", "TextMuted")
	local tagRow = Create("Frame", {
		Name = "Tags",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Visible = false,
		Parent = header,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Wraps = true,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = tagRow,
	})
	Create("UIPadding", { PaddingTop = UDim.new(0, 4), Parent = tagRow })
	self.TagRow = tagRow
	self.Header = header
	if options.Tags then
		self:SetTags(options.Tags)
	end

	-- columns
	local columns = Create("Frame", {
		Name = "Columns",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = scroll,
	})
	local function column(name: string): Frame
		local col = Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.new(0.5, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = columns,
		})
		Kit.List(col, "Vertical", "Section")
		return col
	end
	self.Columns = columns
	self.Left = column("Left")
	self.Right = column("Right")
	self.SingleColumn = false
	self:_Relayout(true)
	return self
end

function Page:SetTags(list: { any })
	for _, child in self.TagRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	Display.BuildChips(self.TagRow, list)
	self.TagRow.Visible = #list > 0
end

function Page:SetTitle(text: string)
	self.TitleLabel.Text = text
end

function Page:SetDescription(text: string?)
	self.DescriptionLabel.Text = text or ""
	self.DescriptionLabel.Visible = text ~= nil and text ~= ""
end

function Page:AddSection(options: any)
	local opts = if type(options) == "string" then { Title = options } else options or {}
	local section = Section.new(self, opts)
	local side = opts.Side
	if side ~= "Left" and side ~= "Right" then
		self._alternate += 1
		side = if self._alternate % 2 == 1 then "Left" else "Right"
	end
	section.Side = side
	table.insert(self.Sections, section)
	section.Root.LayoutOrder = #self.Sections
	section.Root.Parent = if self.SingleColumn or side == "Left" then self.Left else self.Right
	if self.Tab and self.Tab._OnRootContent and self == self.Tab.RootPage then
		self.Tab:_OnRootContent()
	end
	return section
end
Page.AddCard = Page.AddSection

function Page:_RemoveSection(section: any)
	local index = table.find(self.Sections, section)
	if index then
		table.remove(self.Sections, index)
	end
end

-- Switches between 1 and 2 columns. Sections keep their creation order.
function Page:_Relayout(force: boolean?)
	local single = self.Window:IsSingleColumn()
	if single == self.SingleColumn and not force then
		return
	end
	self.SingleColumn = single
	local gap = Theme:Metric("Section")
	if single then
		self.Left.Size = UDim2.new(1, 0, 0, 0)
		self.Right.Visible = false
		for index, section in self.Sections do
			section.Root.LayoutOrder = index
			section.Root.Parent = self.Left
		end
	else
		self.Left.Size = UDim2.new(0.5, -gap / 2, 0, 0)
		self.Right.Size = UDim2.new(0.5, -gap / 2, 0, 0)
		self.Right.Position = UDim2.new(0.5, gap / 2, 0, 0)
		self.Right.Visible = true
		for index, section in self.Sections do
			section.Root.LayoutOrder = index
			section.Root.Parent = if section.Side == "Right" then self.Right else self.Left
		end
	end
end

function Page:Show(animated: boolean?)
	local scroll = self.Scroll
	scroll.Visible = true
	self:_Relayout()
	if animated ~= false and Animations.Enabled() then
		scroll.Position = UDim2.fromOffset(0, 14)
		Animations.Tween(scroll, { Position = UDim2.new() }, 0.35)
	else
		scroll.Position = UDim2.new()
	end
end

function Page:Hide()
	self.Scroll.Visible = false
end

function Page:Select()
	self.Window:SelectTab(self.Tab)
	self.Tab:ShowPage(self)
end

function Page:Destroy()
	for _, section in table.clone(self.Sections) do
		section:Destroy()
	end
	self.Maid:Clean()
end

------------------------------------------------------------------------------
-- Sidebar entry button (shared by categories and loose pages)
------------------------------------------------------------------------------
local function entryButton(tab: any, page: any, options: { [string]: any }, parent: Instance, order: number)
	local button = Create("TextButton", {
		Name = "Entry_" .. tostring(options.Title),
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.Bind(button, "Size", { "Spacing" }, function(T)
		return UDim2.new(1, 0, 0, math.max(Theme:Metric("Row", T) - 4, 30))
	end)
	Kit.Corner(button, 0.7)
	local hovered = false
	local function isActive(): boolean
		return tab.ActivePage == page
	end
	Kit.Bind(button, "BackgroundColor3", { "Surface", "Text" }, function(T)
		return if hovered and not isActive() then Utility.Mix(T.Surface, T.Text, 0.03) else T.Surface
	end)
	Kit.Bind(button, "BackgroundTransparency", { "SurfaceTransparency", "PanelTransparency" }, function(T)
		if isActive() then
			return Theme:Alpha("Surface", "Panel", T)
		end
		return if hovered then 0.4 else 1
	end)
	local bar = Create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 0, 0),
		Parent = button,
	})
	Kit.AccentFill(bar, "Accent")
	Kit.Corner(bar, "pill")
	local icon = Kit.Icon(options.Icon or "chevron-right", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(15, 15),
		Parent = button,
	}, "TextMuted")
	local label = Kit.Label({
		Text = tostring(options.Title or "Page"),
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -44, 1, 0),
		Parent = button,
	}, "Body", "TextMuted")
	Kit.Bind(label, "TextColor3", { "Text", "TextMuted" }, function(T)
		return if isActive() or hovered then T.Text else T.TextMuted
	end)
	local entry = { Button = button, Bar = bar, Icon = icon, Label = label }
	function entry.Refresh(instant: boolean?)
		local active = isActive()
		Kit.Refresh(button, nil, instant)
		Kit.Refresh(label, nil, instant)
		Kit.SetIconColor(icon, if active then "Accent" else "TextMuted")
		local size = if active then UDim2.new(0, 3, 0.55, 0) else UDim2.new(0, 3, 0, 0)
		if instant then
			bar.Size = size
		else
			Animations.Tween(bar, { Size = size }, 0.3, Enum.EasingStyle.Back)
		end
	end
	button.MouseEnter:Connect(function()
		hovered = true
		entry.Refresh()
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		entry.Refresh()
	end)
	button.MouseButton1Click:Connect(function()
		Kit.Sound("Click")
		tab:ShowPage(page)
		tab.Window:CloseDrawer()
	end)
	Animations.AttachPress(button, button, 0.97)
	entry.Refresh(true)
	return entry
end

------------------------------------------------------------------------------
-- Category
------------------------------------------------------------------------------
local Category = {}
Category.__index = Category

function Category.new(tab: any, options: { [string]: any }, order: number)
	local self = setmetatable({}, Category)
	self.Tab = tab
	self.Window = tab.Window
	self.Options = options
	self.Pages = {} :: { any }
	self.Collapsed = false

	local root = Create("Frame", {
		Name = "Category_" .. tostring(options.Title),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = tab.SidebarList,
	})
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = root })
	self.Root = root

	local header = Create("TextButton", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		Parent = root,
	})
	local icon = Kit.Icon(options.Icon or "folder", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		Parent = header,
	}, "TextMuted")
	self.Icon = icon
	Kit.Label({
		Text = string.upper(tostring(options.Title or "Category")),
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -56, 1, 0),
		Parent = header,
	}, "Tiny", "TextMuted")
	local chevron = Kit.Icon("chevron-down", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(11, 11),
		Parent = header,
	}, "TextMuted")
	self.Chevron = chevron

	local entries = Create("Frame", {
		Name = "Entries",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		LayoutOrder = 2,
		Parent = root,
	})
	local list = Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = entries })
	self.Entries = entries
	self.List = list
	list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if not self.Collapsed and not self._animating then
			entries.Size = UDim2.new(1, 0, 0, list.AbsoluteContentSize.Y)
		end
	end)

	header.MouseButton1Click:Connect(function()
		self:SetCollapsed(not self.Collapsed)
	end)
	if options.Collapsed then
		self:SetCollapsed(true, true)
	end
	return self
end

function Category:AddPage(options: any)
	local opts = if type(options) == "string" then { Title = options } else options or {}
	local page = Page.new(self.Window, self.Tab, opts)
	page.Category = self
	page.Entry = entryButton(self.Tab, page, opts, self.Entries, #self.Pages + 1)
	table.insert(self.Pages, page)
	self.Tab:_RegisterPage(page)
	return page
end

function Category:SetCollapsed(collapsed: boolean, instant: boolean?)
	self.Collapsed = collapsed
	local target = if collapsed then 0 else self.List.AbsoluteContentSize.Y
	Animations.Tween(self.Chevron, { Rotation = if collapsed then -90 else 0 }, 0.2)
	if instant then
		self.Entries.Size = UDim2.new(1, 0, 0, target)
		return
	end
	self._animating = true
	local tween = Animations.Tween(self.Entries, { Size = UDim2.new(1, 0, 0, target) }, 0.3)
	local function done()
		self._animating = false
		if not self.Collapsed then
			self.Entries.Size = UDim2.new(1, 0, 0, self.List.AbsoluteContentSize.Y)
		end
	end
	if tween then
		tween.Completed:Once(done)
	else
		done()
	end
end

------------------------------------------------------------------------------
-- Tab
------------------------------------------------------------------------------
local Tab = {}
Tab.__index = Tab

function Tab.new(window: any, options: any)
	local opts = if type(options) == "string" then { Title = options } else options or {}
	local self = setmetatable({}, Tab)
	self.Window = window
	self.Options = opts
	self.Categories = {} :: { any }
	self.Pages = {} :: { any }
	self.LooseEntries = 0
	self.Maid = Maid.new()
	self.Badge = false

	-- tab button ---------------------------------------------------------------
	local button = Create("TextButton", {
		Name = "Tab_" .. tostring(opts.Title),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = #window.Tabs + 1,
		Parent = window.TabStrip,
	})
	self.Button = button
	self.Maid:Give(button)
	Kit.Corner(button, 0.7)
	local hovered = false
	Kit.Bind(button, "BackgroundColor3", { "Surface", "Text" }, function(T)
		return if hovered then Utility.Mix(T.Surface, T.Text, 0.03) else T.Surface
	end)
	Kit.Bind(button, "BackgroundTransparency", { "SurfaceTransparency", "PanelTransparency" }, function(T)
		if window.ActiveTab == self then
			return Theme:Alpha("Surface", "Panel", T)
		end
		return if hovered then 0.5 else 1
	end)
	local content = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = button,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 7),
		Parent = content,
	})
	Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = content })
	self.ContentHolder = content
	if opts.Icon then
		self.Icon = Kit.Icon(opts.Icon, { Size = UDim2.fromOffset(15, 15), LayoutOrder = 1, Parent = content }, "TextMuted")
	end
	self.Label = Kit.Label({
		Text = tostring(opts.Title or "Tab"),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = content,
	}, "Heading", "TextMuted")
	Kit.Bind(self.Label, "TextColor3", { "Text", "TextMuted" }, function(T)
		return if window.ActiveTab == self or hovered then T.Text else T.TextMuted
	end)
	local dot = Create("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(7, 7),
		LayoutOrder = 3,
		Visible = false,
		Parent = content,
	})
	Kit.Corner(dot, "pill")
	Kit.Bind(dot, "BackgroundColor3", "Danger")
	self.BadgeDot = dot
	local indicator = Create("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 0, 0, 2),
		ZIndex = 2,
		Parent = button,
	})
	Kit.AccentFill(indicator, "Accent")
	Kit.Corner(indicator, "pill")
	self.Indicator = indicator

	button.MouseEnter:Connect(function()
		hovered = true
		self:_RefreshButton()
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		self:_RefreshButton()
	end)
	button.MouseButton1Click:Connect(function()
		Kit.Sound("Click")
		window:SelectTab(self)
	end)
	Animations.AttachPress(button, button, 0.95)

	-- sidebar list -----------------------------------------------------------
	local sidebarList = Kit.Scrolling({
		Name = "Sidebar_" .. tostring(opts.Title),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = window.SidebarLists,
	})
	Kit.Padding(sidebarList, 8)
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = sidebarList })
	self.SidebarList = sidebarList
	self.Maid:Give(sidebarList)
	local loose = Create("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 0,
		Parent = sidebarList,
	})
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = loose })
	self.LooseList = loose

	-- root page --------------------------------------------------------------
	self.RootPage = Page.new(window, self, {
		Title = opts.PageTitle or opts.Title,
		Description = opts.Description,
		Tags = opts.Tags,
	})
	table.insert(self.Pages, self.RootPage)
	self.ActivePage = self.RootPage
	return self
end

function Tab:_ApplyMode(mode: string)
	-- "Top": horizontal strip with bottom indicator; "Sidebar": vertical list with left bar
	local window = self.Window
	if mode == "Sidebar" then
		self.Button.Parent = window.SidebarTabs
		self.Button.AutomaticSize = Enum.AutomaticSize.None
		self.Button.Size = UDim2.new(1, 0, 0, 34)
		self.Indicator.AnchorPoint = Vector2.new(0, 0.5)
		self.Indicator.Position = UDim2.new(0, 0, 0.5, 0)
	else
		self.Button.Parent = window.TabStrip
		self.Button.AutomaticSize = Enum.AutomaticSize.X
		self.Button.Size = UDim2.new(0, 0, 1, -12)
		self.Indicator.AnchorPoint = Vector2.new(0.5, 1)
		self.Indicator.Position = UDim2.new(0.5, 0, 1, 0)
	end
	self.Mode = mode
	self:_RefreshButton(true)
end

function Tab:_RefreshButton(instant: boolean?)
	local active = self.Window.ActiveTab == self
	Kit.Refresh(self.Button, nil, instant)
	Kit.Refresh(self.Label, nil, instant)
	if self.Icon then
		Kit.SetIconColor(self.Icon, if active then "Accent" else "TextMuted")
	end
	local target
	if self.Mode == "Sidebar" then
		target = if active then UDim2.new(0, 3, 0.55, 0) else UDim2.new(0, 3, 0, 0)
	else
		target = if active then UDim2.new(0.6, 0, 0, 2) else UDim2.new(0, 0, 0, 2)
	end
	if instant then
		self.Indicator.Size = target
	else
		Animations.Tween(self.Indicator, { Size = target }, 0.35, Enum.EasingStyle.Back)
	end
end

function Tab:_RegisterPage(page: any)
	table.insert(self.Pages, page)
	self:_OnRootContent()
	if self.ActivePage == self.RootPage and #self.RootPage.Sections == 0 then
		-- first real page becomes the default when the root page is empty
		self.ActivePage = page
	end
	if self.Window.ActiveTab == self then
		self.Window:_Layout()
		self:ShowPage(self.ActivePage, false)
	end
	self:_RefreshEntries(true)
end

-- Adds a sidebar entry for the root page once the tab uses a sidebar AND has root content
function Tab:_OnRootContent()
	if self.RootEntry or #self.Pages <= 1 or #self.RootPage.Sections == 0 then
		return
	end
	self.RootEntry = entryButton(self, self.RootPage, {
		Title = self.Options.OverviewTitle or self.Options.Title,
		Icon = self.Options.Icon or "home",
	}, self.LooseList, -1)
	self.RootPage.Entry = self.RootEntry
end

function Tab:HasSidebar(): boolean
	return #self.Pages > 1
end

function Tab:AddCategory(options: any)
	local opts = if type(options) == "string" then { Title = options } else options or {}
	local category = Category.new(self, opts, #self.Categories + 1)
	table.insert(self.Categories, category)
	return category
end

function Tab:AddPage(options: any)
	local opts = if type(options) == "string" then { Title = options } else options or {}
	local page = Page.new(self.Window, self, opts)
	self.LooseEntries += 1
	page.Entry = entryButton(self, page, opts, self.LooseList, self.LooseEntries)
	self:_RegisterPage(page)
	return page
end

function Tab:AddSection(options: any)
	return self.RootPage:AddSection(options)
end
Tab.AddCard = Tab.AddSection

function Tab:_RefreshEntries(instant: boolean?)
	for _, page in self.Pages do
		if page.Entry then
			page.Entry.Refresh(instant)
		end
	end
end

function Tab:ShowPage(page: any, animated: boolean?)
	if self.ActivePage and self.ActivePage ~= page then
		self.ActivePage:Hide()
	end
	self.ActivePage = page
	if self.Window.ActiveTab == self then
		page:Show(animated)
	end
	self:_RefreshEntries()
end

function Tab:_Show()
	self.SidebarList.Visible = true
	for _, page in self.Pages do
		if page ~= self.ActivePage then
			page:Hide()
		end
	end
	self.ActivePage:Show()
	self:_RefreshEntries(true)
	self:_RefreshButton()
end

function Tab:_Hide()
	self.SidebarList.Visible = false
	for _, page in self.Pages do
		page:Hide()
	end
	self:_RefreshButton()
end

function Tab:Select()
	self.Window:SelectTab(self)
end

function Tab:SetBadge(value: any)
	self.Badge = value
	self.BadgeDot.Visible = value ~= nil and value ~= false and value ~= 0
end

function Tab:SetTitle(text: string)
	self.Options.Title = text
	self.Label.Text = text
	self.RootPage:SetTitle(text)
end

function Tab:Destroy()
	for _, page in self.Pages do
		page:Destroy()
	end
	self.Maid:Clean()
end

return Tab
