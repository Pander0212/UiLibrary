--[[
	Tooltip
	One shared tooltip bubble. Desktop: hover delay, follows the mouse.
	Mobile: Tooltip.ShowAt(text, position) is triggered by a long-press.
	Disabled globally through the theme key TooltipsEnabled.
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local Kit = Import("Kit")
local Animations = Import("Animations")
local Gui = Import("Gui")

local Create = Utility.Create
local UserInputService = Utility.Services.UserInputService

local Tooltip = {}

local bubble: Frame? = nil
local label: TextLabel? = nil
local scale: UIScale? = nil
local followConnection: RBXScriptConnection? = nil
local token = 0

local function ensure(): Frame
	if bubble and bubble.Parent then
		return bubble
	end
	bubble = Create("Frame", {
		Name = "Tooltip",
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Parent = Gui.Layer("Tooltip"),
	})
	local b = bubble :: Frame
	Kit.Panel(b, "Tooltip", "Free")
	Kit.Corner(b, 0.6)
	Kit.Stroke(b, "Border", { Always = true })
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, 9),
		PaddingRight = UDim.new(0, 9),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = b,
	})
	scale = Create("UIScale", { Parent = b })
	label = Kit.Label({
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Parent = b,
	}, "Small", "Text")
	Create("UISizeConstraint", { MaxSize = Vector2.new(260, math.huge), Parent = label })
	return b
end

local function place(position: Vector2)
	local b = ensure()
	local viewport = Utility.Viewport()
	local size = b.AbsoluteSize
	local x = math.clamp(position.X + 14, 6, viewport.X - size.X - 6)
	local y = position.Y + 18
	if y + size.Y > viewport.Y - 6 then
		y = position.Y - size.Y - 10
	end
	b.Position = UDim2.fromOffset(x, y)
end

function Tooltip.ShowAt(text: string, position: Vector2, autoHide: number?)
	if not Theme.Values.TooltipsEnabled or text == nil or text == "" then
		return
	end
	local b = ensure()
	token += 1
	local my = token;
	(label :: TextLabel).Text = text
	b.Visible = true
	place(position)
	if scale then
		scale.Scale = 0.9
		Animations.Tween(scale, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
	end
	if autoHide then
		task.delay(autoHide, function()
			if token == my then
				Tooltip.Hide()
			end
		end)
	end
end

function Tooltip.Hide()
	token += 1
	if followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end
	if bubble then
		bubble.Visible = false
	end
end

-- Attaches hover behaviour. `text` may be a string or a function returning one.
function Tooltip.Attach(gui: GuiObject, text: any): () -> ()
	local connections = {}
	local hovering = false
	local function resolve(): string?
		if type(text) == "function" then
			return text()
		end
		return text
	end
	table.insert(connections, gui.MouseEnter:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			return
		end
		hovering = true
		token += 1
		local my = token
		task.delay(0.4, function()
			if hovering and token == my then
				local value = resolve()
				if value and value ~= "" then
					Tooltip.ShowAt(value, UserInputService:GetMouseLocation())
					local showToken = token
					if followConnection then
						followConnection:Disconnect()
					end
					followConnection = UserInputService.InputChanged:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement and token == showToken then
							place(UserInputService:GetMouseLocation())
						end
					end)
				end
			end
		end)
	end))
	table.insert(connections, gui.MouseLeave:Connect(function()
		hovering = false
		Tooltip.Hide()
	end))
	return function()
		hovering = false
		for _, c in connections do
			c:Disconnect()
		end
	end
end

return Tooltip
