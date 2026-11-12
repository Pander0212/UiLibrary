--[[
	Config
	Flag registry + persistence.

	Every element created with a `Flag` registers itself here. Elements implement
	  element.Type                 ("Toggle", "Slider", ...)
	  element:Serialize()   -> JSON-safe value
	  element:Deserialize(v)       (applies the value and fires the callback unless
	                                element.NoCallbackOnLoad is set)
	Elements with `IgnoreConfig = true` are reachable through UI:GetFlag but never
	saved or loaded.

	Additional state (theme, window, mobile buttons...) is stored through
	"providers": Config:RegisterProvider(name, saveFn, loadFn).

	Storage: writefile/readfile/... (all wrapped in pcall) with an in-memory
	fallback so everything keeps working for the session when the executor has no
	file API.

	Layout on disk:
	  <Id>/settings.json
	  <Id>/themes/<name>.json
	  <Id>/<GameName_PlaceId>/configs/<name>.json
]]

local Utility = Import("Utility")
local Constants = Import("Constants")
local Signal = Import("Signal")
local Theme = Import("Theme")

local Config = {}

Config.Flags = {} :: { [string]: any } -- flag -> element
Config.Pending = {} :: { [string]: any } -- flag -> {Type, Value} waiting for its element
Config.Providers = {} :: { [string]: { Save: () -> any, Load: (any) -> () } }
Config.PendingProviders = {} :: { [string]: any }
Config.ReservedKeys = { Version = true, Library = true, Name = true, SavedAt = true, Game = true, Flags = true, Theme = true }
Config.Changed = Signal.new() -- config list / autoload changed
Config.Saved = Signal.new() -- (name, timestamp)
Config.Loaded = Signal.new() -- (name)
Config.FlagChanged = Signal.new() -- (flag, value) - fired by elements
Config.Current = nil :: string?
Config.LastSaved = nil :: number?
Config.Initialized = false
Config.Loading = false

Config.Settings = {
	Version = Constants.ConfigVersion,
	Autoload = {} :: { [string]: string },
	AutoSave = false,
	AutoSaveInterval = 60,
	SaveOnClose = true,
	DeviceMode = "Auto",
	RememberedKey = nil :: string?,
	LastThemes = {} :: { [string]: any },
}

------------------------------------------------------------------------------
-- File system abstraction (pcall everywhere + session fallback)
------------------------------------------------------------------------------
local FS = {}
Config.FS = FS
FS.Memory = {} :: { [string]: string }

local function fn(name: string): any
	local env = (typeof(getgenv) == "function" and getgenv()) or nil
	local value = env and env[name]
	if type(value) ~= "function" then
		if name == "writefile" then
			value = writefile
		elseif name == "readfile" then
			value = readfile
		elseif name == "isfile" then
			value = isfile
		elseif name == "isfolder" then
			value = isfolder
		elseif name == "makefolder" then
			value = makefolder
		elseif name == "listfiles" then
			value = listfiles
		elseif name == "delfile" then
			value = delfile
		end
	end
	return if type(value) == "function" then value else nil
end

FS.Available = fn("writefile") ~= nil and fn("readfile") ~= nil and fn("isfile") ~= nil

function FS.MakeFolder(path: string)
	if not FS.Available then
		return
	end
	local isfolderFn, makefolderFn = fn("isfolder"), fn("makefolder")
	if not makefolderFn then
		return
	end
	pcall(function()
		if not isfolderFn or not isfolderFn(path) then
			makefolderFn(path)
		end
	end)
end

function FS.Write(path: string, content: string): boolean
	if FS.Available then
		local ok = pcall(fn("writefile"), path, content)
		if ok then
			FS.Memory[path] = nil
			return true
		end
	end
	FS.Memory[path] = content
	return true
end

function FS.Read(path: string): string?
	if FS.Memory[path] then
		return FS.Memory[path]
	end
	if FS.Available then
		local ok, result = pcall(function()
			if fn("isfile")(path) then
				return fn("readfile")(path)
			end
			return nil
		end)
		if ok and type(result) == "string" then
			return result
		end
	end
	return nil
end

function FS.Exists(path: string): boolean
	if FS.Memory[path] then
		return true
	end
	if FS.Available then
		local ok, result = pcall(fn("isfile"), path)
		return ok and result == true
	end
	return false
end

function FS.Delete(path: string)
	FS.Memory[path] = nil
	local delfileFn = fn("delfile")
	if FS.Available and delfileFn then
		pcall(delfileFn, path)
	end
end

-- Lists "*.json" file names (without extension) inside a folder
function FS.List(folder: string): { string }
	local names: { string } = {}
	local seen: { [string]: boolean } = {}
	local listfilesFn = fn("listfiles")
	if FS.Available and listfilesFn then
		local ok, files = pcall(listfilesFn, folder)
		if ok and type(files) == "table" then
			for _, file in files do
				local name = string.match(tostring(file), "([^/\\]+)%.json$")
				if name and not seen[name] then
					seen[name] = true
					table.insert(names, name)
				end
			end
		end
	end
	local prefix = folder .. "/"
	for path in FS.Memory do
		if string.sub(path, 1, #prefix) == prefix then
			local name = string.match(string.sub(path, #prefix + 1), "^([^/\\]+)%.json$")
			if name and not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
	end
	table.sort(names, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	return names
end

------------------------------------------------------------------------------
-- Paths / init
------------------------------------------------------------------------------
Config.Root = Constants.Id
Config.GameKey = "Game"

function Config:Paths()
	local root = Config.Root
	local gameFolder = root .. "/" .. Config.GameKey
	return {
		Root = root,
		Game = gameFolder,
		Configs = gameFolder .. "/configs",
		Themes = root .. "/themes",
		Settings = root .. "/settings.json",
	}
end

function Config:Init()
	if Config.Initialized then
		return
	end
	Config.Initialized = true
	Config.GameKey = Utility.GameKey()
	local paths = Config:Paths()
	FS.MakeFolder(paths.Root)
	FS.MakeFolder(paths.Game)
	FS.MakeFolder(paths.Configs)
	FS.MakeFolder(paths.Themes)
	Config:LoadSettings()
end

local function notify(title: string, content: string, kind: string?)
	pcall(function()
		Import("Components/Notifications").Notify({ Title = title, Content = content, Type = kind or "Info", Duration = 5 })
	end)
end
Config._notify = notify

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------
function Config:LoadSettings()
	local text = FS.Read(Config:Paths().Settings)
	if not text then
		return
	end
	local ok, data = Utility.JSONDecode(text)
	if not ok or type(data) ~= "table" then
		notify("Settings", "settings.json is damaged and was reset.", "Warning")
		return
	end
	local s = Config.Settings
	if type(data.Autoload) == "table" then
		for k, v in data.Autoload do
			if type(k) == "string" and type(v) == "string" then
				s.Autoload[k] = v
			end
		end
	end
	if type(data.AutoSave) == "boolean" then
		s.AutoSave = data.AutoSave
	end
	if type(data.AutoSaveInterval) == "number" then
		s.AutoSaveInterval = math.clamp(data.AutoSaveInterval, 10, 3600)
	end
	if type(data.SaveOnClose) == "boolean" then
		s.SaveOnClose = data.SaveOnClose
	end
	if data.DeviceMode == "Auto" or data.DeviceMode == "Mobile" or data.DeviceMode == "Desktop" then
		s.DeviceMode = data.DeviceMode
	end
	if type(data.RememberedKey) == "string" then
		s.RememberedKey = data.RememberedKey
	end
end

function Config:SaveSettings()
	local ok, json = Utility.JSONEncode(Config.Settings)
	if ok then
		FS.Write(Config:Paths().Settings, json)
	end
end

------------------------------------------------------------------------------
-- Flags
------------------------------------------------------------------------------
function Config:Register(element: any)
	local flag = element.Flag
	if type(flag) ~= "string" or flag == "" then
		return
	end
	if Config.Flags[flag] and Config.Flags[flag] ~= element then
		warn(string.format("[%s] duplicate flag '%s' - the newer element wins", Constants.Name, flag))
	end
	Config.Flags[flag] = element
	if element.IgnoreConfig then
		return
	end
	local pending = Config.Pending[flag]
	if pending ~= nil then
		Config.Pending[flag] = nil
		if pending.Type == nil or pending.Type == element.Type then
			local ok, err = pcall(element.Deserialize, element, pending.Value)
			if not ok then
				warn("[" .. Constants.Name .. "] failed to apply flag " .. flag .. ": " .. tostring(err))
			end
		end
	end
end

function Config:Unregister(element: any)
	local flag = element.Flag
	if flag and Config.Flags[flag] == element then
		Config.Flags[flag] = nil
	end
end

function Config:GetFlag(flag: string): any
	local element = Config.Flags[flag]
	if element then
		return element:Get()
	end
	return nil
end

function Config:RegisterProvider(name: string, save: () -> any, load: (any) -> ())
	Config.Providers[name] = { Save = save, Load = load }
	-- data loaded before the provider existed (e.g. autoload) is applied now
	local pending = Config.PendingProviders[name]
	if pending ~= nil then
		Config.PendingProviders[name] = nil
		local ok, err = pcall(load, pending)
		if not ok then
			warn("[" .. Constants.Name .. "] " .. name .. ": " .. tostring(err))
		end
	end
end

------------------------------------------------------------------------------
-- Collect / apply
------------------------------------------------------------------------------
function Config:Collect(name: string?): { [string]: any }
	local flags = {}
	for flag, element in Config.Flags do
		if not element.IgnoreConfig then
			local ok, value = pcall(element.Serialize, element)
			if ok and value ~= nil then
				flags[flag] = { Type = element.Type, Value = value }
			end
		end
	end
	-- keep values of flags whose elements are not created (yet)
	for flag, entry in Config.Pending do
		if flags[flag] == nil then
			flags[flag] = entry
		end
	end
	local data: { [string]: any } = {
		Version = Constants.ConfigVersion,
		Library = Constants.Id,
		Name = name or Config.Current or "default",
		SavedAt = os.time(),
		Game = { PlaceId = game.PlaceId, Key = Config.GameKey },
		Flags = flags,
		Theme = Theme:Serialize(),
	}
	for providerName, value in Config.PendingProviders do
		data[providerName] = value
	end
	for providerName, provider in Config.Providers do
		local ok, value = pcall(provider.Save)
		if ok and value ~= nil then
			data[providerName] = value
		end
	end
	return data
end

-- Upgrades older formats in place. Unknown keys are left alone (ignored later).
function Config.Migrate(data: { [string]: any }): { [string]: any }
	local version = tonumber(data.Version) or 0
	if version < 1 then
		-- v0: flat { flag = value } table without metadata
		if type(data.Flags) ~= "table" then
			local flags = {}
			for key, value in data do
				if type(key) == "string" and key ~= "Theme" and key ~= "Version" then
					flags[key] = { Value = value }
				end
			end
			data = { Flags = flags, Theme = data.Theme }
		end
		data.Version = 1
	end
	return data
end

function Config:Apply(raw: any, options: { [string]: any }?): (boolean, string?)
	if type(raw) ~= "table" then
		return false, "config is not a table"
	end
	local data = Config.Migrate(raw)
	if (tonumber(data.Version) or 0) > Constants.ConfigVersion then
		notify("Config", "This config was made with a newer version - loading what is compatible.", "Warning")
	end
	local opts = options or {}
	Config.Loading = true
	if opts.Theme ~= false and type(data.Theme) == "table" then
		Theme:ApplySerialized(data.Theme, opts.Instant)
	end
	if type(data.Flags) == "table" then
		for flag, entry in data.Flags do
			if type(flag) == "string" then
				local value = if type(entry) == "table" and entry.Value ~= nil then entry.Value else entry
				local entryType = if type(entry) == "table" then entry.Type else nil
				local element = Config.Flags[flag]
				if element then
					if not element.IgnoreConfig and (entryType == nil or entryType == element.Type) then
						local ok, err = pcall(element.Deserialize, element, value)
						if not ok then
							warn("[" .. Constants.Name .. "] flag " .. flag .. ": " .. tostring(err))
						end
					end
				else
					Config.Pending[flag] = { Type = entryType, Value = value }
				end
			end
		end
	end
	for key, value in data do
		if type(key) == "string" and not Config.ReservedKeys[key] then
			local provider = Config.Providers[key]
			if provider then
				local ok, err = pcall(provider.Load, value)
				if not ok then
					warn("[" .. Constants.Name .. "] " .. key .. ": " .. tostring(err))
				end
			else
				Config.PendingProviders[key] = value
			end
		end
	end
	Config.Loading = false
	return true
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------
local function configPath(name: string): string
	return Config:Paths().Configs .. "/" .. name .. ".json"
end

function Config:List(): { string }
	Config:Init()
	return FS.List(Config:Paths().Configs)
end

function Config:Exists(name: string): boolean
	return FS.Exists(configPath(Utility.SanitizeFileName(name)))
end

function Config:Save(name: string?): (boolean, string?)
	Config:Init()
	local clean = Utility.SanitizeFileName(name or Config.Current or "default")
	if clean == "" then
		return false, "invalid name"
	end
	local ok, json = Utility.JSONEncode(Config:Collect(clean))
	if not ok then
		notify("Config", "Could not encode config: " .. tostring(json), "Error")
		return false, json
	end
	FS.Write(configPath(clean), json)
	Config.Current = clean
	Config.LastSaved = os.time()
	Config.Saved:Fire(clean, Config.LastSaved)
	Config.Changed:Fire()
	return true, nil
end

function Config:Load(name: string, options: { [string]: any }?): (boolean, string?)
	Config:Init()
	local clean = Utility.SanitizeFileName(name or "")
	local text = FS.Read(configPath(clean))
	if not text then
		notify("Config", "Config '" .. clean .. "' does not exist.", "Error")
		return false, "missing"
	end
	local ok, data = Utility.JSONDecode(text)
	if not ok or type(data) ~= "table" then
		notify("Config", "Config '" .. clean .. "' is damaged and was not loaded.", "Error")
		return false, "corrupted"
	end
	local applied, err = Config:Apply(data, options)
	if not applied then
		notify("Config", "Config '" .. clean .. "' could not be applied: " .. tostring(err), "Error")
		return false, err
	end
	Config.Current = clean
	Config.Loaded:Fire(clean)
	Config.Changed:Fire()
	return true, nil
end

function Config:Delete(name: string): boolean
	local clean = Utility.SanitizeFileName(name)
	FS.Delete(configPath(clean))
	if Config:GetAutoload() == clean then
		Config:SetAutoload(nil)
	end
	if Config.Current == clean then
		Config.Current = nil
	end
	Config.Changed:Fire()
	return true
end

function Config:Rename(old: string, new: string): (boolean, string?)
	local from, to = Utility.SanitizeFileName(old), Utility.SanitizeFileName(new)
	if to == "" then
		return false, "invalid name"
	end
	if Config:Exists(to) then
		return false, "exists"
	end
	local text = FS.Read(configPath(from))
	if not text then
		return false, "missing"
	end
	FS.Write(configPath(to), text)
	FS.Delete(configPath(from))
	if Config:GetAutoload() == from then
		Config:SetAutoload(to)
	end
	if Config.Current == from then
		Config.Current = to
	end
	Config.Changed:Fire()
	return true, nil
end

function Config:Duplicate(name: string, newName: string?): (boolean, string?)
	local from = Utility.SanitizeFileName(name)
	local text = FS.Read(configPath(from))
	if not text then
		return false, "missing"
	end
	local target = Utility.SanitizeFileName(newName or "")
	if target == "" then
		local index = 1
		repeat
			target = from .. " copy" .. (if index > 1 then " " .. index else "")
			index += 1
		until not Config:Exists(target)
	end
	FS.Write(configPath(target), text)
	Config.Changed:Fire()
	return true, target
end

function Config:GetInfo(name: string): { [string]: any }?
	local text = FS.Read(configPath(Utility.SanitizeFileName(name)))
	if not text then
		return nil
	end
	local ok, data = Utility.JSONDecode(text)
	if not ok or type(data) ~= "table" then
		return { Corrupted = true }
	end
	return { SavedAt = data.SavedAt, Version = data.Version }
end

-- Autoload ------------------------------------------------------------------
function Config:SetAutoload(name: string?)
	Config:Init()
	Config.Settings.Autoload[Config.GameKey] = if name then Utility.SanitizeFileName(name) else nil
	Config:SaveSettings()
	Config.Changed:Fire()
end

function Config:GetAutoload(): string?
	return Config.Settings.Autoload[Config.GameKey]
end

function Config:LoadAutoload(): boolean
	Config:Init()
	local name = Config:GetAutoload()
	if not name then
		return false
	end
	if not Config:Exists(name) then
		notify("Config", "Autoload config '" .. name .. "' was not found.", "Warning")
		return false
	end
	local ok = Config:Load(name, { Instant = true })
	if ok then
		notify("Config", "Autoloaded '" .. name .. "'", "Success")
	end
	return ok
end

-- Sharing -------------------------------------------------------------------
function Config:Export(name: string?): string?
	local data
	if name then
		local text = FS.Read(configPath(Utility.SanitizeFileName(name)))
		if not text then
			return nil
		end
		local ok, decoded = Utility.JSONDecode(text)
		if not ok then
			return nil
		end
		data = decoded
	else
		data = Config:Collect()
	end
	return Utility.EncodeShare("CFG", data)
end

function Config:Import(text: string, saveAs: string?): (boolean, string?)
	local ok, data = Utility.DecodeShare("CFG", text)
	if not ok then
		notify("Config", "Import failed: " .. tostring(data), "Error")
		return false, data
	end
	local applied, err = Config:Apply(data)
	if not applied then
		return false, err
	end
	if saveAs and saveAs ~= "" then
		Config:Save(saveAs)
	end
	return true, nil
end

-- Auto-save -----------------------------------------------------------------
local autoSaveThread: thread? = nil

function Config:SetAutoSave(enabled: boolean, interval: number?)
	Config.Settings.AutoSave = enabled
	if interval then
		Config.Settings.AutoSaveInterval = math.clamp(interval, 10, 3600)
	end
	Config:SaveSettings()
	if autoSaveThread then
		pcall(task.cancel, autoSaveThread)
		autoSaveThread = nil
	end
	if enabled then
		autoSaveThread = task.spawn(function()
			while Config.Settings.AutoSave do
				task.wait(Config.Settings.AutoSaveInterval)
				if Config.Settings.AutoSave then
					Config:Save(Config.Current or "autosave")
				end
			end
		end)
	end
end

function Config:SaveOnClose()
	if Config.Settings.SaveOnClose and Config.Current then
		Config:Save(Config.Current)
	end
end

function Config:Shutdown()
	if autoSaveThread then
		pcall(task.cancel, autoSaveThread)
		autoSaveThread = nil
	end
end

-- Themes (NovaUI/themes/*.json) ----------------------------------------------
function Config:SaveTheme(name: string): boolean
	Config:Init()
	local clean = Utility.SanitizeFileName(name)
	if clean == "" then
		return false
	end
	local ok, json = Utility.JSONEncode(Theme:Serialize())
	if not ok then
		return false
	end
	FS.Write(Config:Paths().Themes .. "/" .. clean .. ".json", json)
	Config.Changed:Fire()
	return true
end

function Config:LoadTheme(name: string): boolean
	local text = FS.Read(Config:Paths().Themes .. "/" .. Utility.SanitizeFileName(name) .. ".json")
	local ok, data = Utility.JSONDecode(text or "")
	if not ok or type(data) ~= "table" then
		notify("Theme", "Theme '" .. tostring(name) .. "' is damaged.", "Error")
		return false
	end
	return Theme:ApplySerialized(data, false)
end

function Config:DeleteTheme(name: string)
	FS.Delete(Config:Paths().Themes .. "/" .. Utility.SanitizeFileName(name) .. ".json")
	Config.Changed:Fire()
end

function Config:ListThemes(): { string }
	Config:Init()
	return FS.List(Config:Paths().Themes)
end

return Config
