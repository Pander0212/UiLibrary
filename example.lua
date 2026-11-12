--[[
	Nova UI - full feature example
	Shows: loader (+ key system), window, tabs, sidebar categories, pages, every
	component, ESP preview, quick toggles, appearance tab and config tab.
	The "game logic" here is only demo code - replace it with your own.
]]

local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Pander0212/UiLibrary/main/dist/NovaUI.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------------------------
-- Optional: register your own icons (rbxassetid) - glyphs are used otherwise
------------------------------------------------------------------------------
-- UI:RegisterIcon("eye", 1234567890)

------------------------------------------------------------------------------
-- 1) Loader (yields until finished). Steps can be real async functions.
------------------------------------------------------------------------------
UI:CreateLoader({
	Title = "Nova",
	Subtitle = "Premium script hub",
	-- Logo = "rbxassetid://...",
	MinDuration = 1.5,
	Steps = {
		{ Text = "Waiting for character", Weight = 1, Run = function(progress)
			local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
			progress(0.5)
			character:WaitForChild("Humanoid", 5)
			progress(1)
		end },
		{ Text = "Reading configs", Weight = 1, Run = function(progress)
			local list = UI.Config:List()
			for i = 1, #list do
				progress(i / #list)
				task.wait(0.03)
			end
		end },
		{ Text = "Preparing interface", Duration = 0.4 },
	},
	KeySystem = {
		Enabled = true,
		Title = "Key required",
		Note = "Demo key: NOVA-DEMO (it is remembered after the first use)",
		Keys = { "NOVA-DEMO" },
		-- Validate = function(key) return key == "..." , "message" end,
		Link = "https://example.com/get-key",
		Remember = true,
	},
})

------------------------------------------------------------------------------
-- 2) Window
------------------------------------------------------------------------------
local Win = UI:CreateWindow({
	Title = "Nova",
	Subtitle = "Script Hub",
	-- Logo = "rbxassetid://...",
	Theme = "Midnight", -- or { Preset = "Mint", CornerRadius = 12, Accent = Color3.fromRGB(0, 200, 140) }
	ToggleKey = Enum.KeyCode.RightShift,
	FloatingButton = "Auto", -- true = always, false = never, "Auto" = touch devices
	CloseBehavior = "Hide", -- "Destroy" asks to unload
})

------------------------------------------------------------------------------
-- 3) Home tab: dashboard widgets
------------------------------------------------------------------------------
local Home = Win:AddTab({
	Title = "Home",
	Icon = "home",
	Description = "Welcome back, " .. LocalPlayer.DisplayName,
	Tags = { { Text = "v1.0", Color = "Accent" }, { Text = "Undetected", Color = "Success", Icon = "shield" }, "Free" },
})

local Status = Home:AddSection({ Title = "Status", Icon = "activity", Side = "Left" })
local serverCard = Status:AddStatusCard({ Title = "Server", Subtitle = "Connected", Icon = "globe", Status = "Success" })
Status:AddStatusCard({ Title = "Updates", Subtitle = "Up to date", Icon = "download", Status = "Accent" })
Status:AddStatusCard({ Title = "Anti-cheat", Subtitle = "Not detected", Icon = "shield", Status = "Warning" })
Status:AddButton({ Title = "Launch", Style = "Primary", Size = "Large", Icon = "bolt", Callback = function()
	UI:Notify({ Title = "Launched", Content = "Everything is running.", Type = "Success" })
end })
Status:AddButton({ Title = "Add script", Style = "Dashed", Callback = function()
	local name = Win:Prompt("Add script", "Give it a name", "My script")
	if name then
		UI:Notify({ Title = "Added", Content = name, Type = "Info" })
	end
end })

local Perf = Home:AddSection({ Title = "Performance", Icon = "chart", Side = "Right" })
local fpsCard = Perf:AddStatCard({ Title = "FPS", Value = 60, Icon = "activity", Trend = "stable", TrendColor = "Success" })
local pingCard = Perf:AddStatCard({ Title = "Ping", Value = 0, Suffix = " ms", Icon = "globe" })
local fpsChart = Perf:AddChart({ Title = "FPS history", MaxPoints = 40, Min = 0, Suffix = " fps" })
local pingChart = Perf:AddChart({ Title = "Ping history", MaxPoints = 40, Color = "Accent2", Suffix = " ms" })

local Info = Home:AddSection({ Title = "About", Icon = "info", Side = "Right" })
Info:AddParagraph({ Title = "Nova UI", Content = "Fully themeable, animated and mobile friendly. Open the Appearance tab to customise everything." })
Info:AddTags({ Tags = { "Mobile", { Text = "Configs", Color = "Success" }, { Text = "Themes", Color = "Accent2" } } })
Info:AddDivider("Demo")
Info:AddButton({ Title = "Show notifications", Callback = function()
	UI:Notify({ Title = "Info", Content = "An info message.", Type = "Info" })
	UI:Notify({ Title = "Success", Content = "Saved successfully.", Type = "Success" })
	UI:Notify({ Title = "Warning", Content = "Something looks odd.", Type = "Warning" })
	UI:Notify({ Title = "Error", Content = "Something failed.", Type = "Error", Actions = {
		{ Title = "Retry", Callback = function() print("retry") end },
		{ Title = "Ignore" },
	} })
end })
Info:AddButton({ Title = "Open dialog", Callback = function()
	if Win:Confirm("Are you sure?", "This is a confirmation dialog.") then
		UI:Notify({ Title = "Dialog", Content = "Confirmed", Type = "Success" })
	end
end })
Home:SetBadge(true)

-- live stats (FPS / Ping) - updated twice per second
task.spawn(function()
	local frames, elapsed = 0, 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		frames += 1
		elapsed += dt
	end)
	while task.wait(0.5) do
		if not Win.Holder.Parent then
			connection:Disconnect()
			break
		end
		local fps = math.floor(frames / math.max(elapsed, 1e-3) + 0.5)
		frames, elapsed = 0, 0
		local ping = 0
		pcall(function()
			ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
		end)
		fpsCard:SetValue(fps)
		fpsCard:SetTrend(if fps >= 55 then "smooth" else "low", if fps >= 55 then "Success" else "Warning")
		pingCard:SetValue(ping)
		fpsChart:Push(fps)
		pingChart:Push(ping)
		serverCard:SetStatus(if ping < 150 then "Connected" else "High latency", if ping < 150 then "Success" else "Warning")
	end
end)

------------------------------------------------------------------------------
-- 4) Combat tab: sidebar categories + pages
------------------------------------------------------------------------------
local Combat = Win:AddTab({ Title = "Combat", Icon = "target" })
local Aim = Combat:AddCategory({ Title = "Aimbot", Icon = "target" })
local General = Aim:AddPage({ Title = "General", Icon = "settings", Description = "Core aim settings", Tags = { "Beta" } })

local AimMain = General:AddSection({ Title = "Aimbot", Icon = "target" })
AimMain:AddToggle({ Title = "Enabled", Flag = "Aim_Enabled", Default = false, Pinnable = true, Icon = "target", QuickTitle = "Aim",
	Tooltip = "Pin it to get a mobile quick toggle", Callback = function(v) print("Aim", v) end })
AimMain:AddKeybind({ Title = "Aim key", Flag = "Aim_Key", Default = Enum.KeyCode.E, Mode = "Hold",
	Callback = function(active) print("aiming:", active) end,
	ChangedCallback = function(key) print("new aim key:", key) end })
AimMain:AddSlider({ Title = "FOV", Flag = "Aim_FOV", Min = 10, Max = 500, Increment = 5, Default = 120, Suffix = "px",
	Description = "Click the value to type a number", Callback = function(v) print("FOV", v) end })
AimMain:AddSlider({ Title = "Smoothness", Flag = "Aim_Smooth", Min = 0, Max = 1, Increment = 0.05, Default = 0.35 })
AimMain:AddDropdown({ Title = "Hit part", Flag = "Aim_Part", Values = { "Head", "Torso", "Closest" }, Default = "Head" })

local AimTarget = General:AddSection({ Title = "Targeting", Icon = "users" })
AimTarget:AddCheckbox({ Title = "Team check", Flag = "Aim_TeamCheck", Default = true })
AimTarget:AddCheckbox({ Title = "Visible check", Flag = "Aim_VisibleCheck", Default = false })
local playerList = AimTarget:AddDropdown({ Title = "Whitelist", Flag = "Aim_Whitelist", Multi = true, Search = true,
	Values = {}, Placeholder = "Nobody" })
local function refreshPlayers()
	local names = {}
	for _, player in Players:GetPlayers() do
		if player ~= LocalPlayer then
			table.insert(names, player.Name)
		end
	end
	playerList:Refresh(names, true)
end
refreshPlayers()
Players.PlayerAdded:Connect(refreshPlayers)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshPlayers)
end)
AimTarget:AddButton({ Title = "Refresh players", Icon = "refresh", Callback = refreshPlayers })

local Misc = Aim:AddPage({ Title = "Prediction", Icon = "activity" })
local Pred = Misc:AddSection({ Title = "Prediction", Collapsible = true })
Pred:AddToggle({ Title = "Prediction", Flag = "Aim_Prediction", Default = false })
Pred:AddTextbox({ Title = "Multiplier", Flag = "Aim_PredMult", Numeric = true, Min = 0, Max = 5, Default = "0.135" })

local Other = Combat:AddCategory({ Title = "Other", Icon = "sword", Collapsed = false })
local Trigger = Other:AddPage({ Title = "Triggerbot", Icon = "bolt" })
local TrigSec = Trigger:AddSection("Triggerbot")
local trigToggle = TrigSec:AddToggle({ Title = "Triggerbot", Flag = "Trigger_Enabled", Pinnable = true, Icon = "bolt" })
local delaySlider = TrigSec:AddSlider({ Title = "Delay", Flag = "Trigger_Delay", Min = 0, Max = 500, Default = 50, Suffix = "ms" })
delaySlider:SetDisabled(not trigToggle:Get())
trigToggle:OnChanged(function(v)
	delaySlider:SetDisabled(not v)
end)

------------------------------------------------------------------------------
-- 5) Visuals tab: ESP preview + its controls (flags ESP_*)
------------------------------------------------------------------------------
local Visuals = Win:AddTab({ Title = "Visuals", Icon = "eye" })
local Esp = Visuals:AddCategory({ Title = "ESP", Icon = "eye" })
local EspPage = Esp:AddPage({ Title = "Players", Icon = "user", Description = "Live preview of your ESP settings", Tags = { { Text = "Preview", Color = "Accent2" } } })
local PreviewSec = EspPage:AddSection({ Title = "Preview", Icon = "eye", Side = "Left" })
local ControlSec = EspPage:AddSection({ Title = "Settings", Icon = "settings", Side = "Right" })
PreviewSec:AddESPPreview({ Height = 320, FlagPrefix = "ESP_", Controls = ControlSec })
PreviewSec:AddButton({ Title = "Print ESP settings", Icon = "code", Callback = function()
	local settings = UI:GetESPSettings()
	print("Box:", settings.Box.Enabled, settings.Box.Style, settings.Box.Color)
	print("Tracer:", settings.Tracer.Enabled, settings.Tracer.Origin)
end })

local World = Esp:AddPage({ Title = "World", Icon = "globe" })
local WorldSec = World:AddSection("World")
WorldSec:AddToggle({ Title = "Fullbright", Flag = "World_Fullbright", Pinnable = true, Icon = "sparkles" })
WorldSec:AddColorPicker({ Title = "Ambient", Flag = "World_Ambient", Default = Color3.fromRGB(140, 140, 160), Transparency = 0,
	Callback = function(color, transparency) print("ambient", color, transparency) end })
WorldSec:AddColorPicker({ Title = "Rainbow demo", Flag = "World_Rainbow", Default = Color3.fromRGB(255, 80, 80), Rainbow = true })

------------------------------------------------------------------------------
-- 6) Player tab: misc components
------------------------------------------------------------------------------
local PlayerTab = Win:AddTab({ Title = "Player", Icon = "user" })
local Movement = PlayerTab:AddSection({ Title = "Movement", Icon = "move" })
local function humanoid()
	local character = LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end
Movement:AddSlider({ Title = "WalkSpeed", Flag = "Player_WalkSpeed", Min = 16, Max = 100, Default = 16, Callback = function(v)
	local h = humanoid()
	if h then
		h.WalkSpeed = v
	end
end })
Movement:AddSlider({ Title = "JumpPower", Flag = "Player_JumpPower", Min = 50, Max = 200, Default = 50, Callback = function(v)
	local h = humanoid()
	if h then
		h.UseJumpPower = true
		h.JumpPower = v
	end
end })
Movement:AddToggle({ Title = "Infinite jump", Flag = "Player_InfJump", Pinnable = true, Icon = "upload", QuickTitle = "Jump" })
Movement:AddKeybind({ Title = "Fly", Flag = "Player_FlyKey", Default = "F", Mode = "Toggle",
	Callback = function(active) print("fly", active) end })

local Misc2 = PlayerTab:AddSection({ Title = "Misc", Icon = "sparkles" })
local nameLabel = Misc2:AddLabel({ Text = "Hello, " .. LocalPlayer.DisplayName, Icon = "user" })
Misc2:AddTextbox({ Title = "Chat tag", Flag = "Player_Tag", Placeholder = "[VIP]", Finished = true,
	Callback = function(text) nameLabel:Set("Tag: " .. text) end })
Misc2:AddDivider()
local locked = Misc2:AddToggle({ Title = "Locked feature", Description = "Disabled until premium", Tooltip = "Example of a disabled element" })
locked:SetDisabled(true)
Misc2:AddButton({ Title = "Rejoin", Style = "Danger", Icon = "refresh", Callback = function()
	if Win:Confirm("Rejoin?", "You will be reconnected to this server.", "Rejoin", "Danger") then
		game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
	end
end })

------------------------------------------------------------------------------
-- 7) Built-in tabs (one line each)
------------------------------------------------------------------------------
Win:AddThemeTab()
Win:AddConfigTab()

------------------------------------------------------------------------------
-- 8) Developer API examples
------------------------------------------------------------------------------
-- UI.Theme:Set("Accent", Color3.fromRGB(255, 90, 120))     -- animated, all bound instances update
-- UI.Theme:ApplyPreset("Glass")
-- UI.Config:Save("legit")  UI.Config:Load("legit")  UI.Config:SetAutoload("legit")
-- print(UI:GetFlag("Aim_FOV"))
-- UI:Destroy()
