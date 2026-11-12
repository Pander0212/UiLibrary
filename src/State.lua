--[[
	State
	Shared runtime state of one library instance (there is only one per execution).
	Holds the ScreenGui, its layers and global lifecycle objects.
]]

local Maid = Import("Maid")
local Signal = Import("Signal")

local State = {
	Library = nil :: any,
	Gui = nil :: ScreenGui?,
	Layers = {} :: { [string]: Frame },
	Maid = Maid.new(),
	Windows = {} :: { any },
	MainWindow = nil :: any,
	Destroyed = false,

	-- Touch-first layout (set by Mobile/Device)
	IsMobile = false,
	DeviceChanged = Signal.new(),

	-- Fired when the ScreenGui viewport changes size
	ViewportChanged = Signal.new(),

	-- Loader gate: windows wait until the loader finished before popping in
	LoaderActive = false,
	LoaderFinished = Signal.new(),
}

return State
