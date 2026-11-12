--[[
	Keybind picker
	  Section:AddKeybind({
	      Title, Description, Flag, Default = Enum.KeyCode.E | "E",
	      Mode = "Toggle" | "Hold" | "Always", ChangeableMode = true,
	      Callback = function(active: boolean) end,     -- key pressed (toggle/hold state)
	      ChangedCallback = function(keyName: string) end, -- rebinding
	      Blacklist = { "Escape" },
	  })
	Click the key box and press a key (Backspace/Delete clears, Escape cancels).
	Mouse buttons: MouseButton1/2/3 are supported as binds.
	Keybind:Set({Key = "E", Mode = "Hold"}) | Keybind:Set("E")  :Get() -> {Key, Mode}
	Keybind:GetState() -> boolean (current toggle/hold state)
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Element = Import("Components/Element")

local Create = Utility.Create
local UserInputService = Utility.Services.UserInputService

local Keybind = setmetatable({}, { __index = Element })
Keybind.__index = Keybind

local MODES = { "Toggle", "Hold", "Always" }
local MOUSE = {
	MouseButton1 = Enum.UserInputType.MouseButton1,
	MouseButton2 = Enum.UserInputType.MouseButton2,
	MouseButton3 = Enum.UserInputType.MouseButton3,
}
local SHORT = {
	LeftShift = "LShift",
	RightShift = "RShift",
	LeftControl = "LCtrl",
	RightControl = "RCtrl",
	LeftAlt = "LAlt",
	RightAlt = "RAlt",
	MouseButton1 = "MB1",
	MouseButton2 = "MB2",
	MouseButton3 = "MB3",
	Backquote = "`",
	Space = "Space",
}

local function keyName(value: any): string?
	if value == nil then
		return nil
	end
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	if type(value) == "string" then
		if value == "" or value == "None" then
			return nil
		end
		if MOUSE[value] then
			return value
		end
		local ok = pcall(function()
			return (Enum.KeyCode :: any)[value]
		end)
		return if ok then value else nil
	end
	return nil
end

function Keybind.new(section: any, options: { [string]: any })
	local self = Element.new(section, options, "Keybind", Keybind)
	local o = self.Options
	self.Key = keyName(o.Default)
	self.Mode = if table.find(MODES, o.Mode) then o.Mode else "Toggle"
	self.ChangeableMode = o.ChangeableMode ~= false
	self.Active = self.Mode == "Always"
	self.Listening = false
	self.Blacklist = o.Blacklist or {}

	self:_BuildRow({ ControlWidth = if self.ChangeableMode then 150 else 100 })

	local control = self.Control
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = control,
	})

	if self.ChangeableMode then
		local modeButton = Create("TextButton", {
			Name = "Mode",
			Size = UDim2.fromOffset(52, 26),
			LayoutOrder = 1,
			Parent = control,
		})
		Kit.Panel(modeButton, "Input", "Panel")
		Kit.Corner(modeButton, 0.6)
		Kit.Stroke(modeButton, "Border")
		self.ModeLabel = Kit.Label({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = self.Mode,
			Parent = modeButton,
		}, "Tiny", "TextMuted")
		Animations.AttachPress(modeButton, modeButton, 0.93)
		self.Maid:Give(modeButton.MouseButton1Click:Connect(function()
			if self.Disabled then
				return
			end
			local index = table.find(MODES, self.Mode) or 1
			self:SetMode(MODES[index % #MODES + 1])
		end))
	end

	local keyButton = Create("TextButton", {
		Name = "Key",
		Size = UDim2.fromOffset(78, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = control,
	})
	Kit.Panel(keyButton, "Input", "Panel")
	Kit.Corner(keyButton, 0.6)
	local stroke = Kit.Stroke(keyButton, "Border", {
		Deps = { "Border", "Accent" },
		Compute = function(T)
			return if self.Listening then T.Accent else T.Border
		end,
	})
	table.insert(self._stateful, stroke)
	Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = keyButton })
	Create("UISizeConstraint", { MinSize = Vector2.new(60, 0), Parent = keyButton })
	self.KeyLabel = Kit.Label({
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = keyButton,
	}, "Mono", "Text")
	self:_Stateful(self.KeyLabel, "TextColor3", { "Text", "Accent" }, function(T)
		return if self.Listening or self.Active then T.Accent else T.Text
	end)
	Animations.AttachPress(keyButton, keyButton, 0.95)
	self.KeyButton = keyButton

	self.Maid:Give(keyButton.MouseButton1Click:Connect(function()
		if self.Disabled or self.Listening then
			return
		end
		self:_Listen()
	end))

	-- runtime handling
	self.Maid:Give(UserInputService.InputBegan:Connect(function(input, processed)
		if self.Listening or not self.Key or self.Mode == "Always" then
			return
		end
		if processed and not MOUSE[self.Key] then
			return
		end
		if self:_Matches(input) then
			if self.Mode == "Toggle" then
				self:_SetActive(not self.Active)
			else
				self:_SetActive(true)
			end
		end
	end))
	self.Maid:Give(UserInputService.InputEnded:Connect(function(input)
		if self.Mode == "Hold" and self.Key and self:_Matches(input) then
			self:_SetActive(false)
		end
	end))

	self:_RenderKey()
	self:_Register()
	return self
end

function Keybind:_Matches(input: InputObject): boolean
	local key = self.Key
	if not key then
		return false
	end
	if MOUSE[key] then
		return input.UserInputType == MOUSE[key]
	end
	return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == key
end

function Keybind:_SetActive(active: boolean)
	if self.Active == active then
		return
	end
	self.Active = active
	for _, inst in self._stateful do
		Kit.Refresh(inst)
	end
	Utility.SafeCallback(self.Callback, active)
end

function Keybind:_RenderKey()
	if self.Listening then
		self.KeyLabel.Text = "..."
	else
		local key = self.Key
		self.KeyLabel.Text = if key then (SHORT[key] or key) else "None"
	end
	if self.ModeLabel then
		self.ModeLabel.Text = self.Mode
	end
	for _, inst in self._stateful do
		Kit.Refresh(inst)
	end
end

function Keybind:_Listen()
	self.Listening = true
	self:_SetState("Focus", true)
	self:_RenderKey()
	local connection
	connection = UserInputService.InputBegan:Connect(function(input)
		local name: string? = nil
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape then
				name = self.Key or "None"
			elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				name = "None"
			else
				name = input.KeyCode.Name
			end
		else
			for mouseName, inputType in MOUSE do
				if input.UserInputType == inputType then
					name = mouseName
				end
			end
		end
		if not name then
			return
		end
		if table.find(self.Blacklist, name) then
			Animations.Shake(self.KeyButton, 4)
			return
		end
		connection:Disconnect()
		-- let the click that started listening pass
		task.defer(function()
			self.Listening = false
			self:_SetState("Focus", false)
			self:Set({ Key = name, Mode = self.Mode })
			self:_RenderKey()
		end)
	end)
	self.Maid:Give(connection)
end

function Keybind:SetMode(mode: string)
	if not table.find(MODES, mode) or mode == self.Mode then
		return
	end
	self.Mode = mode
	if mode == "Always" then
		self:_SetActive(true)
	elseif mode == "Hold" then
		self:_SetActive(false)
	end
	self:_RenderKey()
	self.Changed:Fire(self:Get())
	if self.Flag then
		Import("Config").FlagChanged:Fire(self.Flag, self:Get())
	end
end

-- Set accepts a key name / KeyCode or a table {Key, Mode}
function Keybind:Set(value: any, silent: boolean?, fromConfig: boolean?)
	local key, mode = nil, self.Mode
	if type(value) == "table" then
		key = keyName(value.Key)
		if table.find(MODES, value.Mode) then
			mode = value.Mode
		end
	else
		key = keyName(value)
	end
	local changed = key ~= self.Key or mode ~= self.Mode
	self.Key = key
	self.Mode = mode
	if mode == "Always" then
		self.Active = true
	end
	self:_RenderKey()
	if not changed then
		return
	end
	local out = self:Get()
	self.Changed:Fire(out)
	if self.Flag then
		Import("Config").FlagChanged:Fire(self.Flag, out)
	end
	if not silent and not (fromConfig and self.NoCallbackOnLoad) then
		Utility.SafeCallback(self.Options.ChangedCallback, key or "None")
	end
end

function Keybind:Get(): { Key: string?, Mode: string }
	return { Key = self.Key, Mode = self.Mode }
end

function Keybind:GetState(): boolean
	return self.Active
end

function Keybind:Serialize(): any
	return { Key = self.Key or "None", Mode = self.Mode }
end

function Keybind:Deserialize(value: any)
	if type(value) == "table" or type(value) == "string" then
		self:Set(value, false, true)
	end
end

local _ = Theme

return Keybind
