--[[
	Statistic widgets built from plain Frames (no images)

	  Section:AddStatCard({ Title = "FPS", Value = 60, Suffix = "", Icon = "activity",
	                        Trend = "+2%", TrendColor = "Success" })
	      -> :SetValue(v) :SetTrend(text, colorKey)
	  Section:AddChart({ Title = "Ping", MaxPoints = 40, Min = nil, Max = nil, Suffix = "ms",
	                     Height = 110, Color = "Accent", Decimals = 0 })
	      -> :Push(value) :SetData(list) :Clear()
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Element = Import("Components/Element")

local Create = Utility.Create

local Chart = {}

------------------------------------------------------------------------------
-- Stat card
------------------------------------------------------------------------------
local StatCard = setmetatable({}, { __index = Element })
StatCard.__index = StatCard
Chart.StatCard = StatCard

function StatCard.new(section: any, options: any)
	local self = Element.new(section, options, "StatCard", StatCard)
	local o = self.Options
	local root = Create("Frame", {
		Name = "StatCard",
		Size = UDim2.new(1, 0, 0, 74),
		LayoutOrder = section:_NextOrder(),
	})
	self.Root = root
	self.Maid:Give(root)
	Kit.Panel(root, "Surface", "Panel")
	Kit.Corner(root, 0.8)
	Kit.Stroke(root, "Border")
	Kit.Padding(root, "Inner")

	Kit.Label({
		Text = tostring(o.Title or "Stat"),
		Size = UDim2.new(1, -26, 0, 16),
		Parent = root,
	}, "Small", "TextMuted")
	if o.Icon then
		Kit.Icon(o.Icon, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(16, 16),
			Parent = root,
		}, o.IconColor or "Accent")
	end
	self.ValueLabel = Kit.Label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.65, 0, 0, 30),
		Parent = root,
	}, "Display", "Text")
	self.TrendLabel = Kit.Label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -4),
		Size = UDim2.new(0.35, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = tostring(o.Trend or ""),
		Parent = root,
	}, "Small", o.TrendColor or "Success")
	self.Suffix = o.Suffix or ""
	self.Decimals = o.Decimals or 0
	self.Value = tonumber(o.Value) or 0
	self.Shown = self.Value
	self:_RenderValue(self.Value)
	root.Parent = section.Container
	return self
end

function StatCard:_RenderValue(value: number)
	self.ValueLabel.Text = Utility.FormatNumber(value, self.Decimals) .. self.Suffix
end

-- Counts smoothly to the new value
function StatCard:SetValue(value: any)
	local number = tonumber(value)
	if not number then
		self.ValueLabel.Text = tostring(value)
		return
	end
	local from = self.Shown
	self.Value = number
	if not Animations.Enabled() or math.abs(number - from) < 1e-6 then
		self.Shown = number
		self:_RenderValue(number)
		return
	end
	local holder = Instance.new("NumberValue")
	holder.Value = from
	holder.Changed:Connect(function(v)
		self.Shown = v
		self:_RenderValue(v)
	end)
	local tween = Animations.Tween(holder, { Value = number }, 0.45, Enum.EasingStyle.Quad)
	if tween then
		tween.Completed:Once(function()
			holder:Destroy()
		end)
	end
end
StatCard.Set = StatCard.SetValue

function StatCard:Get(): number
	return self.Value
end

function StatCard:SetTrend(text: string, colorKey: string?)
	self.TrendLabel.Text = text
	if colorKey then
		Kit.Bind(self.TrendLabel, "TextColor3", colorKey)
	end
end

------------------------------------------------------------------------------
-- Line chart
------------------------------------------------------------------------------
local LineChart = setmetatable({}, { __index = Element })
LineChart.__index = LineChart
Chart.LineChart = LineChart

function LineChart.new(section: any, options: any)
	local self = Element.new(section, options, "Chart", LineChart)
	local o = self.Options
	self.MaxPoints = o.MaxPoints or 40
	self.Data = {} :: { number }
	self.ColorKey = o.Color or "Accent"
	self.Suffix = o.Suffix or ""
	self.Decimals = o.Decimals or 0

	local root = Create("Frame", {
		Name = "Chart",
		Size = UDim2.new(1, 0, 0, (o.Height or 110) + 30),
		LayoutOrder = section:_NextOrder(),
	})
	self.Root = root
	self.Maid:Give(root)
	Kit.Panel(root, "Surface", "Panel")
	Kit.Corner(root, 0.8)
	Kit.Stroke(root, "Border")
	Kit.Padding(root, "Inner")

	Kit.Label({
		Text = tostring(o.Title or "Chart"),
		Size = UDim2.new(0.6, 0, 0, 18),
		Parent = root,
	}, "Small", "TextMuted")
	self.CurrentLabel = Kit.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	}, "Mono", self.ColorKey)

	local plot = Create("Frame", {
		Name = "Plot",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 1, -24),
		ClipsDescendants = true,
		Parent = root,
	})
	self.Plot = plot
	for i = 0, 3 do
		local grid = Create("Frame", {
			Position = UDim2.fromScale(0, i / 3),
			Size = UDim2.new(1, 0, 0, 1),
			Parent = plot,
		})
		Kit.Bind(grid, "BackgroundColor3", "Border")
		Kit.Bind(grid, "BackgroundTransparency", { "Border" }, function()
			return 0.4
		end)
	end
	self.Segments = {} :: { Frame }
	self.Dot = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(7, 7),
		ZIndex = 3,
		Visible = false,
		Parent = plot,
	})
	Kit.Corner(self.Dot, "pill")
	Kit.Bind(self.Dot, "BackgroundColor3", self.ColorKey)

	self.Maid:Give(plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_Render()
	end))
	root.Parent = section.Container
	if type(o.Data) == "table" then
		self:SetData(o.Data)
	end
	return self
end

function LineChart:_Segment(index: number): Frame
	local seg = self.Segments[index]
	if not seg then
		seg = Create("Frame", { ZIndex = 2, Parent = self.Plot })
		Kit.Bind(seg, "BackgroundColor3", self.ColorKey)
		Kit.Corner(seg, "pill")
		self.Segments[index] = seg
	end
	seg.Visible = true
	return seg
end

function LineChart:_Render()
	local data = self.Data
	local size = self.Plot.AbsoluteSize
	local count = #data
	for i = math.max(count, 1), #self.Segments do
		self.Segments[i].Visible = false
	end
	if count == 0 or size.X <= 0 then
		self.Dot.Visible = false
		return
	end
	local o = self.Options
	local minV, maxV = math.huge, -math.huge
	for _, v in data do
		minV = math.min(minV, v)
		maxV = math.max(maxV, v)
	end
	minV = if o.Min ~= nil then o.Min else minV
	maxV = if o.Max ~= nil then o.Max else maxV
	if maxV - minV < 1e-6 then
		maxV = minV + 1
	end
	local pad = 4
	local function point(i: number): Vector2
		local x = if self.MaxPoints > 1 then (i - 1) / (self.MaxPoints - 1) * size.X else 0
		local alpha = (data[i] - minV) / (maxV - minV)
		return Vector2.new(x, pad + (1 - math.clamp(alpha, 0, 1)) * (size.Y - pad * 2))
	end
	for i = 1, count - 1 do
		Utility.SetLine(self:_Segment(i), point(i), point(i + 1), 2)
	end
	local last = point(count)
	self.Dot.Visible = true
	self.Dot.Position = UDim2.fromOffset(last.X, last.Y)
	self.CurrentLabel.Text = Utility.FormatNumber(data[count], self.Decimals) .. self.Suffix
end

function LineChart:Push(value: number)
	local number = tonumber(value)
	if not number then
		return
	end
	table.insert(self.Data, number)
	while #self.Data > self.MaxPoints do
		table.remove(self.Data, 1)
	end
	self:_Render()
end
LineChart.Set = LineChart.Push

function LineChart:SetData(list: { number })
	self.Data = {}
	for _, v in list do
		local n = tonumber(v)
		if n then
			table.insert(self.Data, n)
		end
	end
	while #self.Data > self.MaxPoints do
		table.remove(self.Data, 1)
	end
	self:_Render()
end

function LineChart:Clear()
	self.Data = {}
	self:_Render()
end

function LineChart:Get(): { number }
	return table.clone(self.Data)
end

local _ = Theme

return Chart
