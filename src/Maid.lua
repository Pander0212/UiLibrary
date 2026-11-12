--[[
	Maid
	Collects connections, instances, callbacks and objects with Destroy/Disconnect
	and cleans all of them in one call. Every component owns a Maid.
]]

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} :: { any } }, Maid)
end

-- Adds a task and returns it (handy for inline usage)
function Maid:Give(item: any): any
	if item ~= nil then
		table.insert(self._tasks, item)
	end
	return item
end

local function cleanTask(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Cancel) == "function" then
			item:Cancel()
		end
	end
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for index = #tasks, 1, -1 do
		local ok, err = pcall(cleanTask, tasks[index])
		if not ok then
			warn("[NovaUI] cleanup error: " .. tostring(err))
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid
