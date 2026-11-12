--[[
	Input
	Unified pointer tracking for mouse AND touch.

	  Input.Track(guiObject, {
	      Threshold = 8,              -- px before a press becomes a drag
	      LongPress = 0.5,            -- seconds (nil = disabled)
	      Began = function(pos) end,  -- absolute ScreenGui positions (Vector2)
	      DragStart = function(pos) end,
	      Moved = function(pos, delta, total) end,
	      Ended = function(pos, wasDrag) end,
	      Tap = function(pos) end,
	      LongPressed = function(pos) end,
	      LockScroll = true,          -- disable ancestor ScrollingFrames while dragging
	  }) -> cleanup()

	Positions are converted to ScreenGui space (IgnoreGuiInset = true) so they can be
	compared with AbsolutePosition directly.
]]

local Utility = Import("Utility")
local Constants = Import("Constants")

local UserInputService = Utility.Services.UserInputService

local Input = {}

local function isPointerDown(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function scrollingAncestors(gui: Instance): { ScrollingFrame }
	local list = {}
	local current = gui.Parent
	while current do
		if current:IsA("ScrollingFrame") then
			table.insert(list, current)
		end
		current = current.Parent
	end
	return list
end

function Input.Track(gui: GuiObject, handlers: { [string]: any }): () -> ()
	local threshold = handlers.Threshold or Constants.DragThreshold
	local connections: { RBXScriptConnection } = {}
	local active: InputObject? = nil
	local startPos = Vector2.zero
	local lastPos = Vector2.zero
	local dragging = false
	local longPressed = false
	local pressId = 0
	local lockedScrolls: { ScrollingFrame } = {}

	local function unlockScroll()
		for _, frame in lockedScrolls do
			frame.ScrollingEnabled = true
		end
		table.clear(lockedScrolls)
	end

	local function finish(position: Vector2?)
		if not active then
			return
		end
		local pos = position or lastPos
		local wasDrag = dragging
		active = nil
		dragging = false
		pressId += 1
		unlockScroll()
		if handlers.Ended then
			handlers.Ended(pos, wasDrag)
		end
		if not wasDrag and not longPressed and handlers.Tap then
			handlers.Tap(pos)
		end
	end

	table.insert(connections, gui.InputBegan:Connect(function(input: InputObject)
		if not isPointerDown(input) or active then
			return
		end
		active = input
		startPos = Utility.InputToGui(input.Position)
		lastPos = startPos
		dragging = false
		longPressed = false
		pressId += 1
		local myId = pressId
		if handlers.LockScroll then
			for _, frame in scrollingAncestors(gui) do
				if frame.ScrollingEnabled then
					frame.ScrollingEnabled = false
					table.insert(lockedScrolls, frame)
				end
			end
		end
		if handlers.Began then
			handlers.Began(startPos)
		end
		if handlers.LongPress and handlers.LongPressed then
			task.delay(handlers.LongPress, function()
				if active and pressId == myId and not dragging then
					longPressed = true
					handlers.LongPressed(lastPos)
				end
			end)
		end
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		local current = active
		if not current then
			return
		end
		local matches = (current.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
			or (current.UserInputType == Enum.UserInputType.Touch and input == current)
		if not matches then
			return
		end
		local pos = Utility.InputToGui(input.Position)
		local delta = pos - lastPos
		lastPos = pos
		if not dragging then
			if (pos - startPos).Magnitude >= threshold and not longPressed then
				dragging = true
				if handlers.DragStart then
					handlers.DragStart(startPos)
				end
			elseif not handlers.MoveBeforeThreshold then
				return
			end
		end
		if handlers.Moved then
			handlers.Moved(pos, delta, pos - startPos)
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		local current = active
		if not current then
			return
		end
		if input == current or (current.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
			finish(Utility.InputToGui(input.Position))
		end
	end))

	return function()
		unlockScroll()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end
end

-- Makes `target` draggable by `handle`. options.OnMoved(pos), options.OnEnded(), options.Clamp
function Input.Draggable(handle: GuiObject, target: GuiObject, options: { [string]: any }?): () -> ()
	local opts = options or {}
	local startPosition: UDim2 = target.Position
	return Input.Track(handle, {
		Threshold = opts.Threshold or 2,
		Began = function()
			startPosition = target.Position
		end,
		Moved = function(_, _, total: Vector2)
			local newPos = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + total.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + total.Y
			)
			if opts.Clamp then
				newPos = opts.Clamp(newPos)
			end
			target.Position = newPos
			if opts.OnMoved then
				opts.OnMoved(newPos)
			end
		end,
		Ended = function(_, wasDrag: boolean)
			if wasDrag and opts.OnEnded then
				opts.OnEnded(target.Position)
			end
		end,
		Tap = opts.OnTap,
	})
end

-- Mouse location in ScreenGui space
function Input.MousePosition(): Vector2
	return UserInputService:GetMouseLocation()
end

return Input
