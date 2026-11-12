--[[
	Nova UI - public library API

	  local UI = loadstring(game:HttpGet(".../dist/NovaUI.lua"))()
	  UI:CreateLoader({...})                        -- optional, yields until done
	  local Win = UI:CreateWindow({...})
	  local Tab = Win:AddTab({ Title = "Visuals", Icon = "eye" })
	  local Sec = Tab:AddSection("ESP")
	  Sec:AddToggle({ Title = "Box", Flag = "ESP_Box", Default = false, Pinnable = true, Callback = function(v) end })
	  Win:AddThemeTab()
	  Win:AddConfigTab()

	See README.md for the complete API.
]]

local Constants = Import("Constants")
local Utility = Import("Utility")
local State = Import("State")
local Theme = Import("Theme")
Import("ThemeRegistry") -- connects theme changes to bindings
local Gui = Import("Gui")
local Config = Import("Config")
local Icons = Import("Icons")
local Animations = Import("Animations")
local Notifications = Import("Components/Notifications")
local Window = Import("Components/Window")
local Device = Import("Mobile/Device")
local FloatingButton = Import("Mobile/FloatingButton")
local QuickToggles = Import("Mobile/QuickToggles")
local Loader = Import("Loader")
local ESPPreview = Import("ESPPreview")

local Library = {}
Library.__index = Library

Library.Name = Constants.Name
Library.Version = Constants.Version
Library.Constants = Constants
Library.Theme = Theme
Library.Config = Config
Library.Flags = Config.Flags
Library.Icons = Icons
Library.Animations = Animations
Library.QuickToggles = QuickToggles
Library.Utility = Utility
Library.Windows = State.Windows

------------------------------------------------------------------------------
-- Re-execution: destroy the previous instance completely (connections included)
------------------------------------------------------------------------------
local globalKey = Constants.Id .. "_Instance"
local env = (typeof(getgenv) == "function" and getgenv()) or shared
pcall(function()
	local previous = env[globalKey]
	if previous and type(previous.Destroy) == "function" then
		previous:Destroy()
	end
end)

local function setup()
	Gui.Ensure()
	Config:Init()
	Device.Init()
end

------------------------------------------------------------------------------
-- Loader
------------------------------------------------------------------------------
-- Shows the loader. Yields until finished unless options.Async = true.
-- Returns true when the loader (and the optional key system) was completed.
function Library:CreateLoader(options: { [string]: any }?): any
	setup()
	-- the loader is shown before the window exists: apply its theme (and the
	-- autoload config's theme) first so it already uses the final look
	local o = options or {}
	if type(o.Theme) == "string" then
		Theme:ApplyPreset(o.Theme, true)
	elseif type(o.Theme) == "table" then
		if type(o.Theme.Preset) == "string" then
			Theme:ApplyPreset(o.Theme.Preset, true)
		end
		local overrides = table.clone(o.Theme)
		overrides.Preset = nil
		Theme:SetDefaults(overrides)
	end
	pcall(function()
		local name = Config:GetAutoload()
		if name and o.Autoload ~= false then
			local text = Config.FS.Read(Config:Paths().Configs .. "/" .. name .. ".json")
			local ok, data = Utility.JSONDecode(text or "")
			if ok and type(data) == "table" and type(data.Theme) == "table" then
				Theme:ApplySerialized(data.Theme, true)
			end
		end
	end)
	local loader = Loader.new(options)
	if options and options.Async then
		task.spawn(loader.Run, loader)
		return loader
	end
	return loader:Run()
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------
function Library:CreateWindow(options: { [string]: any }?): any
	setup()
	local o = options or {}
	local window = Window.new(o)
	window.Library = self
	window.FloatingButton = FloatingButton.new(window, if o.FloatingButton == nil then "Auto" else o.FloatingButton)

	-- autoload: theme/window/mobile state apply now, element values are applied
	-- as soon as the elements with matching flags are created.
	if o.Autoload ~= false then
		Config:LoadAutoload()
	end
	if Config.Settings.AutoSave then
		Config:SetAutoSave(true)
	end

	task.spawn(function()
		if State.LoaderActive then
			State.LoaderFinished:Wait()
		end
		task.wait()
		if not window.Destroyed then
			window:SetVisible(true)
		end
	end)
	return window
end

------------------------------------------------------------------------------
-- Shortcuts
------------------------------------------------------------------------------
function Library:Notify(options: { [string]: any })
	setup()
	return Notifications.Notify(options)
end

function Library:GetFlag(flag: string): any
	return Config:GetFlag(flag)
end

function Library:SetFlag(flag: string, value: any)
	local element = Config.Flags[flag]
	if element then
		element:Set(value)
	end
end

-- Current ESP preview settings (see ESPPreview.lua for the table layout)
function Library:GetESPSettings(prefix: string?): { [string]: any }
	return ESPPreview.ReadSettings(prefix)
end

function Library:SetTheme(nameOrValues: any)
	if type(nameOrValues) == "string" then
		Theme:ApplyPreset(nameOrValues)
	elseif type(nameOrValues) == "table" then
		Theme:SetMany(nameOrValues)
	end
end

function Library:IsMobile(): boolean
	return State.IsMobile
end

-- "Auto" | "Mobile" | "Desktop"
function Library:SetDeviceMode(mode: string)
	Device.SetMode(mode)
end

function Library:RegisterIcon(name: string, asset: string | number)
	Icons.Register(name, asset)
end

------------------------------------------------------------------------------
-- Destroy: removes every instance, connection, blur and quick toggle
------------------------------------------------------------------------------
function Library:Destroy()
	if State.Destroyed then
		return
	end
	State.Destroyed = true
	pcall(function()
		Config:SaveOnClose()
	end)
	Config:Shutdown()
	pcall(QuickToggles.Destroy)
	for _, window in table.clone(State.Windows) do
		if window.FloatingButton then
			pcall(window.FloatingButton.Destroy, window.FloatingButton)
		end
		pcall(window.Destroy, window)
	end
	pcall(function()
		for _, child in Utility.Services.Lighting:GetChildren() do
			if child:IsA("BlurEffect") and string.sub(child.Name, 1, #Constants.Id) == Constants.Id then
				child:Destroy()
			end
		end
	end)
	State.Maid:Clean()
	State.Gui = nil
	pcall(function()
		if env[globalKey] == Library then
			env[globalKey] = nil
		end
	end)
end

State.Library = Library
pcall(function()
	env[globalKey] = Library
end)

return Library
