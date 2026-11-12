--[[
	Signal
	Minimal synchronous event implementation. Handlers run in order inside xpcall so
	a failing handler never breaks the others.
]]

type Handler = (...any) -> ()

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} :: { any } }, Signal)
end

function Signal:Connect(fn: Handler)
	local handler = { Fn = fn, Connected = true }
	table.insert(self._handlers, handler)
	local signal = self
	local connection = { Connected = true }
	function connection.Disconnect()
		if not handler.Connected then
			return
		end
		handler.Connected = false
		connection.Connected = false
		local index = table.find(signal._handlers, handler)
		if index then
			table.remove(signal._handlers, index)
		end
	end
	connection.Destroy = connection.Disconnect
	return connection
end

function Signal:Once(fn: Handler)
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	for _, handler in table.clone(self._handlers) do
		if handler.Connected then
			local ok, err = xpcall(handler.Fn, debug.traceback, ...)
			if not ok then
				warn("[NovaUI] signal handler error: " .. tostring(err))
			end
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	for _, handler in self._handlers do
		handler.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
