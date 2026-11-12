--[[
	ThemeRegistry
	Remembers which instance property depends on which theme key(s).

	  Registry.Bind(frame, "BackgroundColor3", "Card")
	  Registry.Bind(frame, "BackgroundTransparency", {"Card", "WindowTransparency"}, function(T) ... end)

	When Theme:Set/SetMany fires `Theme.Changed`, only the entries depending on the
	changed keys are recomputed and tweened (via Animations, respecting the speed
	multiplier and the "animations off" switch). Compute functions may also read
	component state (hover/pressed...) - call Registry.Refresh(inst) after a state change.
]]

local Theme = Import("Theme")
local Animations = Import("Animations")

type Entry = {
	Deps: { string },
	Compute: (any) -> any,
	NoTween: boolean?,
	Duration: number?,
}

local Registry = {}

-- inst -> { [property] = Entry }   (weak keys: destroyed instances are collected)
local entriesByInstance: { [Instance]: { [string]: Entry } } = setmetatable({}, { __mode = "k" }) :: any
-- theme key -> set of instances
local instancesByKey: { [string]: { [Instance]: boolean } } = {}

local TWEENABLE = {
	number = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	Vector2 = true,
	Rect = true,
}

local function apply(inst: Instance, property: string, entry: Entry, instant: boolean?)
	local ok, value = pcall(entry.Compute, Theme.Values)
	if not ok then
		warn("[NovaUI] theme binding error (" .. property .. "): " .. tostring(value))
		return
	end
	if value == nil then
		return
	end
	if instant or entry.NoTween or not TWEENABLE[typeof(value)] or not Animations.Enabled() then
		local current = (inst :: any)[property]
		if current ~= value then
			pcall(function()
				(inst :: any)[property] = value
			end)
		end
		return
	end
	Animations.Tween(inst, { [property] = value }, entry.Duration or 0.25)
end

function Registry.Bind(inst: Instance, property: string, deps: any, compute: ((any) -> any)?, options: any?): Instance
	local depList: { string } = if type(deps) == "string" then { deps } else deps
	local fn = compute
	if not fn then
		local key = depList[1]
		fn = function(T)
			return T[key]
		end
	end
	local entry: Entry = {
		Deps = depList,
		Compute = fn :: any,
		NoTween = options and options.NoTween,
		Duration = options and options.Duration,
	}
	local map = entriesByInstance[inst]
	if not map then
		map = {}
		entriesByInstance[inst] = map
	end
	map[property] = entry
	for _, key in depList do
		local set = instancesByKey[key]
		if not set then
			set = setmetatable({}, { __mode = "k" }) :: any
			instancesByKey[key] = set
		end
		set[inst] = true
	end
	apply(inst, property, entry, true)
	return inst
end

function Registry.Unbind(inst: Instance, property: string?)
	local map = entriesByInstance[inst]
	if not map then
		return
	end
	if property then
		map[property] = nil
	else
		entriesByInstance[inst] = nil
	end
end

-- Recomputes bindings of one instance (after a component state change)
function Registry.Refresh(inst: Instance, property: string?, instant: boolean?)
	local map = entriesByInstance[inst]
	if not map then
		return
	end
	if property then
		local entry = map[property]
		if entry then
			apply(inst, property, entry, instant)
		end
		return
	end
	for prop, entry in map do
		apply(inst, prop, entry, instant)
	end
end

function Registry.HandleChanged(changed: { [string]: boolean }, instant: boolean?)
	local done: { [Entry]: boolean } = {}
	for key in changed do
		local set = instancesByKey[key]
		if set then
			for inst in set do
				local map = entriesByInstance[inst]
				if map then
					for prop, entry in map do
						if not done[entry] then
							for _, dep in entry.Deps do
								if changed[dep] then
									done[entry] = true
									apply(inst, prop, entry, instant)
									break
								end
							end
						end
					end
				else
					set[inst] = nil
				end
			end
		end
	end
end

Theme.Changed:Connect(Registry.HandleChanged)

return Registry
