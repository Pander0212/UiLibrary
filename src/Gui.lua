--[[
	Gui
	Creates the single ScreenGui (gethui -> CoreGui -> PlayerGui), destroys a previous
	instance on re-execution and provides ordered layers:
	  Windows < Mobile < Popups < Notifications < Tooltip < Loader
]]

local Utility = Import("Utility")
local Constants = Import("Constants")
local State = Import("State")

local Gui = {}

local LAYERS = { "Windows", "Mobile", "Popups", "Notifications", "Tooltip", "Loader" }

function Gui.Ensure(): ScreenGui
	if State.Gui and State.Gui.Parent then
		return State.Gui
	end
	Utility.DestroyOld(Constants.Id)

	local gui = Utility.Create("ScreenGui", {
		Name = Constants.Id,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
	})
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		elseif typeof(protectgui) == "function" then
			protectgui(gui)
		end
	end)
	gui.Parent = Utility.GetGuiParent()
	State.Gui = gui

	for index, name in LAYERS do
		State.Layers[name] = Utility.Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = index,
			Parent = gui,
		})
	end

	local camera = workspace.CurrentCamera
	if camera then
		State.Maid:Give(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			State.ViewportChanged:Fire(camera.ViewportSize)
		end))
	end
	State.Maid:Give(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = workspace.CurrentCamera
		if cam then
			State.Maid:Give(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				State.ViewportChanged:Fire(cam.ViewportSize)
			end))
			State.ViewportChanged:Fire(cam.ViewportSize)
		end
	end))
	State.Maid:Give(gui)
	return gui
end

function Gui.Layer(name: string): Frame
	Gui.Ensure()
	return State.Layers[name]
end

return Gui
