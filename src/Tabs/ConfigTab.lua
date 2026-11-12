--[[
	Config tab - Win:AddConfigTab({ Title = "Settings", Icon = "settings" })
	  * config list, name field, save / save as / load / overwrite (confirm) /
	    delete (confirm) / rename / duplicate / refresh
	  * autoload marker + last saved timestamp
	  * export / import (clipboard) + auto-save + save on close
	  * interface: toggle keybind, device mode override, quick toggle edit mode, unload
]]

local Config = Import("Config")
local Utility = Import("Utility")
local Theme = Import("Theme")
local State = Import("State")
local Constants = Import("Constants")
local Notifications = Import("Components/Notifications")

local ConfigTab = {}

local function notify(content: string, kind: string?)
	Notifications.Notify({ Title = "Config", Content = content, Type = kind or "Success", Duration = 3 })
end

local function formatTime(timestamp: number?): string
	if not timestamp then
		return "never"
	end
	local ok, text = pcall(os.date, "%d.%m.%Y %H:%M:%S", timestamp)
	return if ok then tostring(text) else tostring(timestamp)
end

function ConfigTab.Build(window: any, options: { [string]: any })
	Config:Init()
	local tab = window:AddTab({
		Title = options.Title or Constants.Strings.ConfigTab,
		Icon = options.Icon or "settings",
		Description = "Save, load and share your settings. Configs are stored per game.",
		Tags = {
			{ Text = if Config.FS.Available then "File storage" else "Session only", Color = if Config.FS.Available then "Success" else "Warning", Icon = "save" },
			{ Text = Config.GameKey, Color = "Accent" },
		},
	})

	-- configs ----------------------------------------------------------------
	local configs = tab:AddSection({ Title = "Configs", Icon = "folder", Side = "Left" })
	local list = configs:AddDropdown({ Title = "Config", Values = Config:List(), AllowNone = true, IgnoreConfig = true, Search = true })
	local nameBox = configs:AddTextbox({ Title = "Name", Placeholder = "config name", IgnoreConfig = true })
	local autoloadLabel = configs:AddStatusCard({ Title = "Autoload", Subtitle = "none", Icon = "bolt", Status = "TextMuted" })
	local savedLabel = configs:AddLabel({ Text = "Last saved: never", Role = "Small", Color = "TextMuted" })

	local function selected(): string?
		local name = list:Get()
		return if name and name ~= "" then name else nil
	end
	local function typed(): string?
		local name = Utility.SanitizeFileName(nameBox:Get() or "")
		return if name ~= "" then name else nil
	end
	local function refresh()
		local current = selected()
		list:Refresh(Config:List(), true)
		if current and Config:Exists(current) then
			list:Set(current, true)
		end
		local auto = Config:GetAutoload()
		autoloadLabel:SetStatus(if auto then auto else "none", if auto then "Success" else "TextMuted")
		savedLabel:Set("Last saved: " .. formatTime(Config.LastSaved) .. (if Config.Current then "  (" .. Config.Current .. ")" else ""))
	end
	tab.Maid:Give(Config.Changed:Connect(function()
		task.defer(refresh)
	end))
	refresh()

	configs:AddButton({
		Title = "Save",
		Style = "Primary",
		Icon = "save",
		Tooltip = "Saves to the selected config (or the typed name)",
		Callback = function()
			local name = selected() or typed() or Config.Current or "default"
			if Config:Save(name) then
				list:Set(name, true)
				notify("Saved '" .. name .. "'")
			end
		end,
	})
	configs:AddButton({
		Title = "Save as new",
		Icon = "plus",
		Style = "Dashed",
		Callback = function()
			local name = typed()
			if not name then
				name = window:Prompt("Save as", "Name of the new config", "config name")
				name = if name then Utility.SanitizeFileName(name) else nil
			end
			if not name or name == "" then
				return
			end
			if Config:Exists(name) and not window:Confirm("Overwrite '" .. name .. "'?", "A config with this name already exists.", "Overwrite", "Danger") then
				return
			end
			Config:Save(name)
			refresh()
			list:Set(name, true)
			notify("Saved '" .. name .. "'")
		end,
	})
	configs:AddButton({
		Title = "Load",
		Icon = "upload",
		Callback = function()
			local name = selected()
			if not name then
				notify("Select a config first.", "Warning")
				return
			end
			if Config:Load(name) then
				notify("Loaded '" .. name .. "'")
			end
		end,
	})
	configs:AddButton({
		Title = "Overwrite",
		Icon = "save",
		Callback = function()
			local name = selected()
			if not name then
				notify("Select a config first.", "Warning")
				return
			end
			if window:Confirm("Overwrite '" .. name .. "'?", "The saved values will be replaced by the current ones.", "Overwrite", "Danger") then
				Config:Save(name)
				notify("Overwrote '" .. name .. "'")
			end
		end,
	})
	configs:AddButton({
		Title = "Rename",
		Icon = "edit",
		Callback = function()
			local name = selected()
			if not name then
				notify("Select a config first.", "Warning")
				return
			end
			local newName = typed() or window:Prompt("Rename", "New name for '" .. name .. "'", "new name", name)
			if not newName or newName == "" then
				return
			end
			local ok, err = Config:Rename(name, newName)
			if ok then
				refresh()
				list:Set(Utility.SanitizeFileName(newName), true)
				notify("Renamed to '" .. newName .. "'")
			else
				notify("Rename failed: " .. tostring(err), "Error")
			end
		end,
	})
	configs:AddButton({
		Title = "Duplicate",
		Icon = "copy",
		Callback = function()
			local name = selected()
			if not name then
				notify("Select a config first.", "Warning")
				return
			end
			local ok, newName = Config:Duplicate(name, typed())
			if ok then
				refresh()
				list:Set(newName, true)
				notify("Duplicated to '" .. tostring(newName) .. "'")
			end
		end,
	})
	configs:AddButton({
		Title = "Delete",
		Style = "Danger",
		Icon = "trash",
		Callback = function()
			local name = selected()
			if not name then
				notify("Select a config first.", "Warning")
				return
			end
			if window:Confirm("Delete '" .. name .. "'?", "This cannot be undone.", "Delete", "Danger") then
				Config:Delete(name)
				list:Set(nil, true)
				refresh()
				notify("Deleted '" .. name .. "'")
			end
		end,
	})
	configs:AddButton({ Title = "Refresh list", Icon = "refresh", Callback = refresh })

	-- autoload -----------------------------------------------------------------
	local auto = tab:AddSection({ Title = "Autoload", Icon = "bolt", Side = "Right", Description = "Loaded automatically after the loader." })
	auto:AddButton({
		Title = "Set selected as autoload",
		Icon = "check",
		Callback = function()
			local name = selected()
			if not name then
				notify("Select a config first.", "Warning")
				return
			end
			Config:SetAutoload(name)
			notify("'" .. name .. "' will be loaded automatically.")
		end,
	})
	auto:AddButton({
		Title = "Clear autoload",
		Icon = "close",
		Callback = function()
			Config:SetAutoload(nil)
			notify("Autoload cleared.")
		end,
	})
	auto:AddToggle({
		Title = "Auto-save",
		Description = "Saves the current config periodically",
		Default = Config.Settings.AutoSave,
		IgnoreConfig = true,
		Callback = function(value)
			Config:SetAutoSave(value)
		end,
	})
	auto:AddSlider({
		Title = "Interval",
		Min = 10,
		Max = 600,
		Increment = 10,
		Suffix = "s",
		Default = Config.Settings.AutoSaveInterval,
		IgnoreConfig = true,
		Callback = function(value)
			Config.Settings.AutoSaveInterval = value
			Config:SaveSettings()
		end,
	})
	auto:AddToggle({
		Title = "Save on close",
		Default = Config.Settings.SaveOnClose,
		IgnoreConfig = true,
		Callback = function(value)
			Config.Settings.SaveOnClose = value
			Config:SaveSettings()
		end,
	})

	-- share ----------------------------------------------------------------------
	local share = tab:AddSection({ Title = "Share", Icon = "link", Side = "Right" })
	share:AddButton({
		Title = "Export to clipboard",
		Icon = "copy",
		Tooltip = "Exports the selected config, or the current settings",
		Callback = function()
			local text = Config:Export(selected())
			if not text then
				notify("Export failed.", "Error")
				return
			end
			if Utility.SetClipboard(text) then
				notify("Config copied to clipboard.")
			else
				window:Dialog({ Title = "Config export", Content = "Clipboard is not available - copy the text below.", Input = { Default = text } })
			end
		end,
	})
	local importBox = share:AddTextbox({ Title = "Import", Placeholder = "Paste config string...", IgnoreConfig = true })
	share:AddButton({
		Title = "Import",
		Icon = "download",
		Callback = function()
			local ok, err = Config:Import(importBox:Get(), typed())
			if ok then
				refresh()
				notify("Config imported" .. (if typed() then " and saved as '" .. tostring(typed()) .. "'" else "") .. ".")
			else
				notify("Import failed: " .. tostring(err), "Error")
			end
		end,
	})

	-- interface ------------------------------------------------------------------
	local ui = tab:AddSection({ Title = "Interface", Icon = "settings", Side = "Left" })
	ui:AddKeybind({
		Title = "Toggle UI",
		Default = window.ToggleKey,
		ChangeableMode = false,
		IgnoreConfig = true,
		ChangedCallback = function(key)
			if key ~= "None" then
				window:SetToggleKey(key)
			end
		end,
	})
	ui:AddDropdown({
		Title = "Device mode",
		Description = "Auto detects touch devices",
		Values = { "Auto", "Mobile", "Desktop" },
		Default = Config.Settings.DeviceMode,
		IgnoreConfig = true,
		Callback = function(value)
			Import("Mobile/Device").SetMode(value)
		end,
	})
	ui:AddButton({
		Title = Constants.Strings.EditQuickToggles,
		Icon = "move",
		Callback = function()
			Import("Mobile/QuickToggles").SetEditMode(true)
		end,
	})
	ui:AddButton({
		Title = "Unload " .. Theme.Values.Title,
		Style = "Danger",
		Icon = "close",
		Callback = function()
			if window:Confirm("Unload?", "The interface and all quick toggles will be removed.", "Unload", "Danger") then
				local library = State.Library
				if library then
					library:Destroy()
				else
					window:Destroy()
				end
			end
		end,
	})
	return tab
end

return ConfigTab
