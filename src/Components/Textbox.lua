--[[
	Textbox
	  Section:AddTextbox({
	      Title, Description, Flag, Default = "", Placeholder = "Type...",
	      Numeric = false, Min = nil, Max = nil, MaxLength = nil,
	      Finished = true,          -- callback only on focus lost (false = every change)
	      ClearOnFocus = false, Callback = function(text) end,
	  })
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Element = Import("Components/Element")

local Create = Utility.Create

local Textbox = setmetatable({}, { __index = Element })
Textbox.__index = Textbox

function Textbox.new(section: any, options: { [string]: any })
	local self = Element.new(section, options, "Textbox", Textbox)
	local o = self.Options
	self.Numeric = o.Numeric == true
	self.Finished = o.Finished ~= false
	self.Value = self:_Clean(o.Default)

	self:_BuildRow({ ControlWidth = o.Width or 160 })

	local field = Create("Frame", {
		Name = "Field",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = self.Control,
	})
	Kit.Bind(field, "Size", { "Spacing" }, function(T)
		return UDim2.new(1, 0, 0, math.max(Theme:Metric("Row", T) - 12, 26))
	end)
	Kit.Panel(field, "Input", "Panel")
	Kit.Corner(field, 0.6)
	local stroke = Kit.Stroke(field, "Border", {
		Deps = { "Border", "Accent" },
		Compute = function(T)
			return if self.State.Focus then T.Accent else T.Border
		end,
	})
	table.insert(self._stateful, stroke)

	local box = Kit.TextBox({
		Name = "Input",
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		PlaceholderText = o.Placeholder or "Type...",
		Text = self.Value,
		ClearTextOnFocus = o.ClearOnFocus == true,
		Parent = field,
	}, if self.Numeric then "Mono" else "Small")
	self.Input = box

	self.Maid:Give(box.Focused:Connect(function()
		self:_SetState("Focus", true)
	end))
	self.Maid:Give(box.FocusLost:Connect(function(enterPressed)
		self:_SetState("Focus", false)
		if self.Disabled then
			box.Text = self.Value
			return
		end
		self:Set(box.Text)
		if enterPressed and o.OnEnter then
			Utility.SafeCallback(o.OnEnter, self.Value)
		end
	end))
	self.Maid:Give(box:GetPropertyChangedSignal("Text"):Connect(function()
		local text = box.Text
		if o.MaxLength and #text > o.MaxLength then
			box.Text = string.sub(text, 1, o.MaxLength)
			return
		end
		if self.Numeric then
			local filtered = string.gsub(text, "[^%d%.%-]", "")
			if filtered ~= text then
				box.Text = filtered
				return
			end
		end
		if not self.Finished and box:IsFocused() then
			self:Set(text)
		end
	end))

	self:_Register()
	return self
end

function Textbox:_Clean(value: any): string
	local text = if value == nil then "" else tostring(value)
	if self.Numeric then
		local number = tonumber(text)
		if not number then
			return if text == "" then "" else self.Value or ""
		end
		local o = self.Options
		if o.Min then
			number = math.max(number, o.Min)
		end
		if o.Max then
			number = math.min(number, o.Max)
		end
		return tostring(number)
	end
	return text
end

function Textbox:Set(value: any, silent: boolean?, fromConfig: boolean?)
	local clean = self:_Clean(value)
	if not self.Input:IsFocused() or self.Finished then
		self.Input.Text = clean
	end
	if clean == self.Value then
		return
	end
	self.Value = clean
	local out: any = if self.Numeric then tonumber(clean) else clean
	if silent then
		self.Changed:Fire(out)
	else
		self:_Fire(out, fromConfig)
	end
end

function Textbox:Get(): any
	if self.Numeric then
		return tonumber(self.Value)
	end
	return self.Value
end

function Textbox:Serialize(): any
	return self.Value
end

function Textbox:Deserialize(value: any)
	if type(value) == "string" or type(value) == "number" then
		self:Set(value, false, true)
	end
end

function Textbox:Focus()
	self.Input:CaptureFocus()
end

return Textbox
