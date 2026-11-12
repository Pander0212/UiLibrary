--[[
	Loader
	  UI:CreateLoader({
	      Title = "Nova", Subtitle = "Loading...", Logo = "rbxassetid://...",
	      Steps = {
	          { Text = "Loading assets", Weight = 1, Run = function(progress) ... progress(0.5) ... end },
	          { Text = "Checking game", Duration = 0.4 },
	      },
	      MinDuration = 1.5, Blur = true, Async = false,
	      KeySystem = {
	          Enabled = true, Title = "Key required", Note = "Get a key on our Discord",
	          Keys = { "KEY-123" } | Validate = function(key) return ok, message end,
	          Link = "https://...", Remember = true,
	      },
	  }) -> boolean (key valid / loader finished)

	Fullscreen overlay with blur, logo pop (Back easing) + glow pulse, typewriter
	title, gradient progress bar with shimmer and counting percentage. Steps can be
	real async functions (they receive a `progress(alpha)` reporter).
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local State = Import("State")
local Gui = Import("Gui")
local Config = Import("Config")
local Constants = Import("Constants")

local Create = Utility.Create
local RunService = Utility.Services.RunService

local Loader = {}
Loader.__index = Loader

function Loader.new(options: { [string]: any }?)
	local o = options or {}
	local self = setmetatable({}, Loader)
	self.Options = o
	self.Progress = 0
	self.Shown = 0
	self.Connections = {}

	if o.Title then
		Theme:SetDefaults({ Title = o.Title })
	end
	if o.Logo then
		Theme:SetDefaults({ Logo = o.Logo })
	end

	local layer = Gui.Layer("Loader")
	local root = Create("CanvasGroup", {
		Name = "Loader",
		Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1,
		Parent = layer,
	})
	Kit.Bind(root, "BackgroundColor3", "Overlay")
	Kit.Bind(root, "BackgroundTransparency", { "Overlay", "OverlayTransparency" }, function(T)
		return math.clamp(T.OverlayTransparency + 0.1, 0, 1)
	end)
	self.Root = root

	-- blur behind
	if o.Blur ~= false then
		pcall(function()
			self.Blur = Create("BlurEffect", { Name = Constants.Id .. "LoaderBlur", Size = 0, Parent = Utility.Services.Lighting })
			Animations.Tween(self.Blur, { Size = 20 }, 0.5)
		end)
	end

	local center = Create("Frame", {
		Name = "Center",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 300),
		Parent = root,
	})
	self.Center = center

	-- logo with glow
	local logoHolder = Create("Frame", {
		Name = "LogoHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(84, 84),
		Parent = center,
	})
	local glow = Create("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.5, 1.5),
		Parent = logoHolder,
	})
	Kit.Corner(glow, "pill")
	Kit.Bind(glow, "BackgroundColor3", "Accent")
	glow.BackgroundTransparency = 0.85
	self.Glow = glow
	local logo = Create("Frame", {
		Name = "Logo",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = logoHolder,
	})
	Kit.AccentFill(logo, "Accent")
	Kit.Corner(logo, 2)
	local logoScale = Create("UIScale", { Scale = 0.6, Parent = logoHolder })
	self.LogoScale = logoScale
	local logoImage = Create("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 3,
		Parent = logo,
	})
	local logoGlyph = Kit.Label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = logo,
	}, "Display", "AccentText")
	Kit.Bind(logoGlyph, "TextSize", { "TextScale" }, function(T)
		return math.floor(36 * T.TextScale)
	end)
	Kit.Bind(logoImage, "Image", { "Logo" }, function(T)
		logoImage.Visible = T.Logo ~= ""
		logoGlyph.Visible = T.Logo == ""
		return T.Logo
	end, { NoTween = true })
	Kit.Bind(logoGlyph, "Text", { "Title" }, function(T)
		return string.upper(string.sub(T.Title, 1, 1))
	end, { NoTween = true })

	-- titles
	local titleText = o.Title or (if Theme.Values.LoaderTitle ~= "" then Theme.Values.LoaderTitle else Theme.Values.Title)
	local subtitleText = o.Subtitle or (if Theme.Values.LoaderSubtitle ~= "" then Theme.Values.LoaderSubtitle else Theme.Values.Subtitle)
	self.TitleText = titleText
	self.TitleLabel = Kit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = center,
	}, "Display", "Text")
	self.SubtitleLabel = Kit.Label({
		Text = subtitleText,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 144),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		Parent = center,
	}, "Small", "TextMuted")

	-- progress
	local bar = Create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 196),
		Size = UDim2.new(0.86, 0, 0, 8),
		ClipsDescendants = true,
		Parent = center,
	})
	Kit.Panel(bar, "SliderTrack", "Free")
	Kit.Corner(bar, "pill")
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		ClipsDescendants = true,
		Parent = bar,
	})
	Kit.AccentFill(fill, "Progress", "SliderFill")
	Kit.Corner(fill, "pill")
	local shimmer = Create("Frame", {
		Name = "Shimmer",
		Size = UDim2.new(0.35, 0, 1, 0),
		Position = UDim2.fromScale(-0.4, 0),
		ZIndex = 2,
		Parent = fill,
	})
	Kit.Bind(shimmer, "BackgroundColor3", "AccentText")
	Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = shimmer,
	})
	self.Fill, self.Shimmer = fill, shimmer

	self.StatusLabel = Kit.Label({
		Text = Theme.Values.LoaderStatusText,
		Position = UDim2.new(0.07, 0, 0, 212),
		Size = UDim2.new(0.66, 0, 0, 18),
		Parent = center,
	}, "Small", "TextMuted")
	self.PercentLabel = Kit.Label({
		Text = "0%",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.93, 0, 0, 212),
		Size = UDim2.new(0.2, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = center,
	}, "Mono", "Accent")

	-- per-frame: glow pulse, shimmer and percentage counter (loader only, removed afterwards)
	local started = os.clock()
	table.insert(self.Connections, RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - started
		glow.Size = UDim2.fromScale(1.4 + math.sin(t * 2.4) * 0.12, 1.4 + math.sin(t * 2.4) * 0.12)
		glow.BackgroundTransparency = 0.82 + math.sin(t * 2.4) * 0.06
		shimmer.Position = UDim2.fromScale(((t * 0.7) % 1.6) - 0.4, 0)
		self.Shown += (self.Progress - self.Shown) * math.clamp(dt * 8, 0, 1)
		self.PercentLabel.Text = tostring(math.floor(self.Shown * 100 + 0.5)) .. "%"
		fill.Size = UDim2.fromScale(self.Shown, 1)
	end))

	return self
end

function Loader:_Intro()
	Animations.Tween(self.Root, { GroupTransparency = 0 }, 0.35)
	Animations.Tween(self.LogoScale, { Scale = 1 }, 0.7, Enum.EasingStyle.Back)
	Animations.Wait(0.25)
	-- typewriter title
	local text = self.TitleText
	local length = utf8.len(text) or #text
	for i = 1, length do
		local ok, cut = pcall(function()
			return string.sub(text, 1, (utf8.offset(text, i + 1) or (#text + 1)) - 1)
		end)
		self.TitleLabel.Text = if ok then cut else text
		if Animations.Enabled() then
			task.wait(0.035 / Animations.Speed())
		end
	end
	self.TitleLabel.Text = text
	Animations.Tween(self.SubtitleLabel, { TextTransparency = 0 }, 0.4)
end

function Loader:SetStatus(text: string)
	self.StatusLabel.Text = text
end

function Loader:SetProgress(alpha: number)
	self.Progress = math.clamp(alpha, 0, 1)
end

function Loader:_RunSteps()
	local steps = self.Options.Steps or {
		{ Text = "Loading interface", Duration = 0.35 },
		{ Text = "Applying theme", Duration = 0.3 },
		{ Text = "Reading configs", Duration = 0.3 },
	}
	local totalWeight = 0
	for _, step in steps do
		totalWeight += step.Weight or 1
	end
	local done = 0
	for _, step in steps do
		local weight = step.Weight or 1
		self:SetStatus(tostring(step.Text or "Loading..."))
		local base = done / totalWeight
		local span = weight / totalWeight
		local report = function(alpha: number)
			self:SetProgress(base + math.clamp(alpha, 0, 1) * span)
		end
		if type(step.Run) == "function" then
			local ok, err = pcall(step.Run, report, self)
			if not ok then
				warn("[" .. Constants.Name .. "] loader step failed: " .. tostring(err))
			end
		elseif step.Duration then
			local elapsed = 0
			while elapsed < step.Duration do
				elapsed += task.wait()
				report(elapsed / step.Duration)
			end
		end
		done += weight
		self:SetProgress(done / totalWeight)
	end
	-- let the counter catch up
	local timeout = os.clock() + 1.5
	while self.Shown < 0.995 and os.clock() < timeout do
		task.wait()
	end
end

------------------------------------------------------------------------------
-- Key system
------------------------------------------------------------------------------
function Loader:_Validate(key: string): (boolean, string?)
	local ks = self.Options.KeySystem
	if type(ks.Validate) == "function" then
		local ok, result, message = pcall(ks.Validate, key)
		if not ok then
			return false, "Validation error"
		end
		return result == true, message
	end
	if type(ks.Keys) == "table" then
		for _, valid in ks.Keys do
			if key == valid then
				return true, nil
			end
		end
	end
	return false, "Invalid key"
end

function Loader:_KeyScreen(): boolean
	local ks = self.Options.KeySystem
	Config:Init()
	if ks.Remember ~= false and Config.Settings.RememberedKey then
		local ok = self:_Validate(Config.Settings.RememberedKey)
		if ok then
			return true
		end
	end

	local center = self.Center
	Animations.Tween(center, { Position = UDim2.fromScale(0.5, 0.36) }, 0.45)

	local card = Create("Frame", {
		Name = "KeyCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 30),
		Size = UDim2.fromOffset(360, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self.Root,
	})
	Create("UISizeConstraint", { MaxSize = Vector2.new(360, math.huge), Parent = card })
	card.Size = UDim2.new(0.9, 0, 0, 0)
	Kit.Panel(card, "Card", "Free")
	Kit.Corner(card, 1.2)
	Kit.Stroke(card, "Border", { Always = true })
	Kit.Padding(card, 16)
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = card })
	Animations.Tween(card, { Position = UDim2.new(0.5, 0, 0.62, 0) }, 0.45, Enum.EasingStyle.Back)

	Kit.Label({
		Text = ks.Title or "Key required",
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1,
		Parent = card,
	}, "Title", "Text")
	if ks.Note then
		Kit.Label({
			Text = ks.Note,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			LayoutOrder = 2,
			Parent = card,
		}, "Small", "TextMuted")
	end
	local field = Create("Frame", { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3, Parent = card })
	Kit.Panel(field, "Input", "Free")
	Kit.Corner(field, 0.7)
	local fieldStroke = Kit.Stroke(field, "Border", { Always = true })
	local box = Kit.TextBox({
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		PlaceholderText = "Enter key...",
		Parent = field,
	}, "Mono")
	local message = Kit.Label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 4,
		Parent = card,
	}, "Small", "Danger")

	local remember = ks.Remember ~= false
	local buttons = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = 5,
		Parent = card,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = buttons,
	})
	local function makeButton(order: number, text: string, primary: boolean, width: number): TextButton
		local b = Create("TextButton", {
			Size = UDim2.new(width, if order == 1 then 0 else -8, 1, 0),
			LayoutOrder = order,
			ClipsDescendants = true,
			Parent = buttons,
		})
		Kit.Corner(b, 0.7)
		if primary then
			Kit.AccentFill(b, "Button")
		else
			Kit.Panel(b, "Surface", "Free")
			Kit.Stroke(b, "Border")
		end
		Kit.Label({
			Text = text,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = b,
		}, "Heading", if primary then "AccentText" else "Text")
		Animations.AttachPress(b, b, 0.95)
		return b
	end
	local hasLink = type(ks.Link) == "string"
	local submit = makeButton(1, "Continue", true, if hasLink then 0.5 else 1)
	if hasLink then
		local getKey = makeButton(2, "Get key", false, 0.5)
		getKey.MouseButton1Click:Connect(function()
			if Utility.SetClipboard(ks.Link) then
				message.Text = "Link copied to clipboard"
				Kit.Bind(message, "TextColor3", "Success")
			else
				message.Text = ks.Link
				Kit.Bind(message, "TextColor3", "TextMuted")
			end
		end)
	end

	local thread = coroutine.running()
	local finished = false
	local function attempt()
		if finished then
			return
		end
		local key = string.match(box.Text, "^%s*(.-)%s*$") or ""
		local ok, msg = self:_Validate(key)
		if ok then
			finished = true
			Kit.Bind(fieldStroke, "Color", "Success")
			message.Text = msg or "Key accepted"
			Kit.Bind(message, "TextColor3", "Success")
			if remember then
				Config.Settings.RememberedKey = key
				Config:SaveSettings()
			end
			task.delay(0.35, function()
				Animations.Tween(card, { Position = UDim2.new(0.5, 0, 1.2, 0) }, 0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				Animations.Tween(center, { Position = UDim2.fromScale(0.5, 0.5) }, 0.45)
				task.wait(0.4 / Animations.Speed())
				card:Destroy()
				task.spawn(thread, true)
			end)
		else
			Kit.Bind(fieldStroke, "Color", "Danger")
			message.Text = msg or "Invalid key"
			Kit.Bind(message, "TextColor3", "Danger")
			Animations.Shake(card, 10)
			Kit.Sound("Error")
		end
	end
	submit.MouseButton1Click:Connect(attempt)
	box.FocusLost:Connect(function(enter)
		if enter then
			attempt()
		end
	end)
	return coroutine.yield()
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------
function Loader:_Outro()
	Animations.Tween(self.LogoScale, { Scale = 1.15 }, 0.3)
	local tween = Animations.Tween(self.Root, { GroupTransparency = 1 }, 0.45)
	if self.Blur then
		Animations.Tween(self.Blur, { Size = 0 }, 0.45)
	end
	if tween then
		tween.Completed:Wait()
	end
	self:Destroy()
end

function Loader:Destroy()
	for _, c in self.Connections do
		c:Disconnect()
	end
	table.clear(self.Connections)
	if self.Blur then
		self.Blur:Destroy()
		self.Blur = nil
	end
	if self.Root then
		self.Root:Destroy()
	end
end

-- Runs the whole sequence. Returns false if the key system was not passed.
function Loader:Run(): boolean
	State.LoaderActive = true
	local started = os.clock()
	self:_Intro()
	local passed = true
	local ks = self.Options.KeySystem
	if type(ks) == "table" and ks.Enabled ~= false then
		self:SetStatus("Waiting for key...")
		passed = self:_KeyScreen()
	end
	if passed then
		self:_RunSteps()
		local minDuration = self.Options.MinDuration or 1.2
		local remaining = minDuration - (os.clock() - started)
		if remaining > 0 and Animations.Enabled() then
			task.wait(remaining)
		end
	end
	self:_Outro()
	State.LoaderActive = false
	State.LoaderFinished:Fire(passed)
	return passed
end

return Loader
