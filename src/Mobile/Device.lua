--[[
	Device
	  * Auto detection: TouchEnabled and not KeyboardEnabled -> touch layout
	  * Manual override "Auto" | "Mobile" | "Desktop" (stored in settings.json)
	  * Safe zones: rectangles of the Roblox thumbstick and jump button so floating
	    buttons never cover them (read from PlayerGui.TouchGui when available,
	    otherwise estimated).
	  * Screen clamping that respects GuiService:GetGuiInset()
]]

local Utility = Import("Utility")
local Theme = Import("Theme")
local State = Import("State")
local Config = Import("Config")

local UserInputService = Utility.Services.UserInputService

local Device = {}
Device.Initialized = false

function Device.Detect(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Device.GetMode(): string
	return Config.Settings.DeviceMode or "Auto"
end

function Device.Update()
	local mode = Device.GetMode()
	local mobile
	if mode == "Mobile" then
		mobile = true
	elseif mode == "Desktop" then
		mobile = false
	else
		mobile = Device.Detect()
	end
	if mobile ~= State.IsMobile then
		State.IsMobile = mobile
		Theme.TouchMode = mobile
		Theme:Touch({ "Spacing" })
		State.DeviceChanged:Fire(mobile)
	end
end

function Device.SetMode(mode: string)
	if mode ~= "Auto" and mode ~= "Mobile" and mode ~= "Desktop" then
		return
	end
	Config.Settings.DeviceMode = mode
	Config:SaveSettings()
	Device.Update()
end

function Device.Init()
	if Device.Initialized then
		Device.Update()
		return
	end
	Device.Initialized = true
	-- force a first evaluation
	State.IsMobile = not Device.Detect()
	Device.Update()
	State.Maid:Give(UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(Device.Update))
	State.Maid:Give(UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(Device.Update))
end

------------------------------------------------------------------------------
-- Safe zones
------------------------------------------------------------------------------
type Zone = { Min: Vector2, Max: Vector2 }

local function zoneOf(gui: GuiObject, offsetY: number, margin: number): Zone
	local pos = gui.AbsolutePosition + Vector2.new(0, offsetY)
	return {
		Min = pos - Vector2.new(margin, margin),
		Max = pos + gui.AbsoluteSize + Vector2.new(margin, margin),
	}
end

function Device.SafeZones(): { Zone }
	local zones: { Zone } = {}
	if not UserInputService.TouchEnabled then
		return zones
	end
	local found = false
	pcall(function()
		local player = Utility.Services.Players.LocalPlayer
		local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
		if not touchGui or not touchGui.Enabled then
			return
		end
		local offsetY = if touchGui.IgnoreGuiInset then 0 else Utility.GuiInset().Y
		local frame = touchGui:FindFirstChild("TouchControlFrame")
		if not frame then
			return
		end
		for _, name in { "JumpButton", "ThumbstickFrame", "DynamicThumbstickFrame" } do
			local control = frame:FindFirstChild(name)
			if control and control:IsA("GuiObject") and control.Visible and control.AbsoluteSize.X > 0 then
				table.insert(zones, zoneOf(control, offsetY, 12))
				found = true
			end
		end
	end)
	if not found then
		-- estimates for the default touch controls
		local vp = Utility.Viewport()
		local small = math.min(vp.X, vp.Y) <= 500
		local jump = if small then 70 else 120
		table.insert(zones, {
			Min = Vector2.new(vp.X - jump - (if small then 95 else 170), vp.Y - jump - (if small then 90 else 160)),
			Max = vp,
		})
		table.insert(zones, { Min = Vector2.new(0, vp.Y * 0.5), Max = Vector2.new(vp.X * 0.38, vp.Y) })
	end
	return zones
end

local function overlaps(aMin: Vector2, aMax: Vector2, zone: Zone): boolean
	return aMin.X < zone.Max.X and aMax.X > zone.Min.X and aMin.Y < zone.Max.Y and aMax.Y > zone.Min.Y
end

-- Clamps a top-left position so the element stays on screen (below the topbar inset)
function Device.ClampToScreen(position: Vector2, size: Vector2, margin: number?): Vector2
	local m = margin or 8
	local vp = Utility.Viewport()
	local inset = Utility.GuiInset()
	return Vector2.new(
		math.clamp(position.X, m, math.max(m, vp.X - size.X - m)),
		math.clamp(position.Y, inset.Y + m, math.max(inset.Y + m, vp.Y - size.Y - m))
	)
end

-- Moves an element out of thumbstick/jump zones (pushes it upwards)
function Device.AvoidZones(position: Vector2, size: Vector2): Vector2
	local pos = position
	for _ = 1, 3 do
		local moved = false
		for _, zone in Device.SafeZones() do
			if overlaps(pos, pos + size, zone) then
				pos = Vector2.new(pos.X, zone.Min.Y - size.Y - 6)
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	return Device.ClampToScreen(pos, size)
end

return Device
