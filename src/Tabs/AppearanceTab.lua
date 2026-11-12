--[[
	Appearance tab - Win:AddThemeTab({ Title = "Appearance", Icon = "palette" })

	Generated from Theme.Schema, so every theme key is editable without extra code:
	  Color   -> ColorPicker (with transparency)    Number -> Slider
	  Boolean -> Toggle                             Enum   -> Dropdown
	  Font    -> Dropdown (font families)           String/Asset -> Textbox
	Root page: presets, live preview, share (export/import), saved themes, global reset.
	Sidebar categories group the schema categories; every section has a reset button.
	Controls stay in sync when the theme changes from anywhere (presets, configs...).
]]

local Theme = Import("Theme")
local Utility = Import("Utility")
local Config = Import("Config")
local Constants = Import("Constants")
local Notifications = Import("Components/Notifications")

local AppearanceTab = {}

local GROUPS = {
	{ Title = "Style", Icon = "palette", Categories = { "Colors", "Gradients", "Background", "Transparency" } },
	{ Title = "Interface", Icon = "layout", Categories = { "Fonts", "Shape", "Layout", "Animations" } },
	{ Title = "Extras", Icon = "sparkles", Categories = { "Branding", "Elements", "Mobile" } },
}

local CATEGORY_ICON = {
	Colors = "droplet",
	Gradients = "gradient",
	Background = "image",
	Transparency = "transparency",
	Fonts = "font",
	Shape = "shape",
	Layout = "layout",
	Animations = "animation",
	Branding = "brand",
	Elements = "elements",
	Mobile = "mobile",
}

local function sectionsOf(category: string): ({ string }, { [string]: { any } })
	local order, map = {}, {}
	for _, entry in Theme.Schema do
		if entry.Category == category and not entry.Hidden then
			if not map[entry.Section] then
				map[entry.Section] = {}
				table.insert(order, entry.Section)
			end
			table.insert(map[entry.Section], entry)
		end
	end
	return order, map
end

-- Creates the control for one schema entry. Returns a sync function(values).
local function control(section: any, entry: any): ((any) -> ())?
	local key = entry.Key
	local T = Theme.Values
	if entry.Type == "Color" then
		local picker = section:AddColorPicker({
			Title = entry.Label,
			Default = T[key],
			Transparency = T[key .. "Transparency"] or 0,
			IgnoreConfig = true,
			Callback = function(color, transparency)
				Theme:SetMany({ [key] = color, [key .. "Transparency"] = transparency })
			end,
		})
		return function(values)
			picker:SetSilent(values[key], values[key .. "Transparency"])
		end
	elseif entry.Type == "Number" then
		local slider = section:AddSlider({
			Title = entry.Label,
			Min = entry.Min or 0,
			Max = entry.Max or 1,
			Increment = entry.Step or 0.01,
			Suffix = entry.Suffix,
			Default = T[key],
			IgnoreConfig = true,
			Callback = function(value)
				Theme:Set(key, value)
			end,
		})
		return function(values)
			slider:Set(values[key], true)
		end
	elseif entry.Type == "Boolean" then
		local toggle = section:AddToggle({
			Title = entry.Label,
			Default = T[key],
			IgnoreConfig = true,
			Callback = function(value)
				Theme:Set(key, value)
			end,
		})
		return function(values)
			toggle:Set(values[key], true)
		end
	elseif entry.Type == "Enum" or entry.Type == "Font" then
		local list = if entry.Type == "Font" then table.clone(Theme.FontFamilies) else entry.Options
		if entry.Type == "Font" and not table.find(list, T[key]) then
			table.insert(list, T[key])
		end
		local dropdown = section:AddDropdown({
			Title = entry.Label,
			Values = list,
			Default = T[key],
			IgnoreConfig = true,
			Search = entry.Type == "Font",
			Callback = function(value)
				if value then
					Theme:Set(key, value)
				end
			end,
		})
		return function(values)
			dropdown:Set(values[key], true)
		end
	else
		local textbox = section:AddTextbox({
			Title = entry.Label,
			Default = T[key],
			Placeholder = if entry.Type == "Asset" then "rbxassetid://..." else "",
			IgnoreConfig = true,
			Callback = function(value)
				Theme:Set(key, value)
			end,
		})
		return function(values)
			textbox:Set(values[key], true)
		end
	end
end

function AppearanceTab.Build(window: any, options: { [string]: any })
	local strings = Constants.Strings
	local tab = window:AddTab({
		Title = options.Title or strings.AppearanceTab,
		Icon = options.Icon or "palette",
		Description = "Every color, font, size and animation - applied live and saved with your config.",
		Tags = { { Text = "Live", Color = "Success", Icon = "bolt" }, { Text = Theme.CurrentPreset, Color = "Accent" } },
		OverviewTitle = "Presets",
	})

	local syncers: { [string]: { (any) -> () } } = {}
	local function track(key: string, fn: ((any) -> ())?)
		if not fn then
			return
		end
		syncers[key] = syncers[key] or {}
		table.insert(syncers[key], fn)
	end

	-- root page --------------------------------------------------------------
	local presets = tab:AddSection({ Title = "Presets", Icon = "palette", Description = "One click themes. Layout and branding are kept.", Side = "Left" })
	for _, name in Theme.PresetOrder do
		presets:AddButton({
			Title = name,
			Icon = "droplet",
			Align = "Left",
			Callback = function()
				Theme:ApplyPreset(name)
				tab.RootPage:SetTags({ { Text = "Live", Color = "Success", Icon = "bolt" }, { Text = name, Color = "Accent" } })
				Notifications.Notify({ Title = "Theme", Content = "Applied preset '" .. name .. "'", Type = "Success", Duration = 2.5 })
			end,
		})
	end

	local preview = tab:AddSection({ Title = "Live preview", Icon = "eye", Side = "Right" })
	preview:AddStatusCard({ Title = "Status card", Subtitle = "Everything is up to date", Icon = "success", Status = "Success" })
	preview:AddButton({ Title = "Primary button", Style = "Primary", Size = "Large", Icon = "bolt", Callback = function()
		Notifications.Notify({ Title = "Preview", Content = "This is how notifications look.", Type = "Info" })
	end })
	preview:AddToggle({ Title = "Toggle", Description = "With description", Default = true, IgnoreConfig = true })
	preview:AddCheckbox({ Title = "Checkbox", Default = true, IgnoreConfig = true })
	preview:AddSlider({ Title = "Slider", Min = 0, Max = 100, Default = 64, Suffix = "%", IgnoreConfig = true })
	preview:AddButton({ Title = "Add item", Style = "Dashed" })

	local share = tab:AddSection({ Title = "Share theme", Icon = "link", Side = "Right" })
	share:AddButton({
		Title = "Export to clipboard",
		Icon = "copy",
		Callback = function()
			local text = Theme:Export()
			if Utility.SetClipboard(text) then
				Notifications.Notify({ Title = "Theme", Content = "Theme copied to clipboard.", Type = "Success" })
			else
				window:Dialog({ Title = "Theme export", Content = "Clipboard is not available - copy the text below.", Input = { Default = text } })
			end
		end,
	})
	local importBox = share:AddTextbox({ Title = "Import", Placeholder = "Paste theme string...", IgnoreConfig = true })
	share:AddButton({
		Title = "Import theme",
		Icon = "download",
		Callback = function()
			local ok, err = Theme:Import(importBox:Get())
			Notifications.Notify({
				Title = "Theme",
				Content = if ok then "Theme imported." else "Import failed: " .. tostring(err),
				Type = if ok then "Success" else "Error",
			})
		end,
	})

	local saved = tab:AddSection({ Title = "Saved themes", Icon = "folder", Side = "Left" })
	local themeList = saved:AddDropdown({ Title = "Theme", Values = Config:ListThemes(), AllowNone = true, IgnoreConfig = true })
	local themeName = saved:AddTextbox({ Title = "Name", Placeholder = "my theme", IgnoreConfig = true })
	saved:AddButton({
		Title = "Save theme",
		Style = "Primary",
		Icon = "save",
		Callback = function()
			local name = themeName:Get()
			if name == "" then
				name = themeList:Get() or ""
			end
			if name == "" then
				Notifications.Notify({ Title = "Theme", Content = "Enter a name first.", Type = "Warning" })
				return
			end
			Config:SaveTheme(name)
			themeList:Refresh(Config:ListThemes(), true)
			themeList:Set(Utility.SanitizeFileName(name), true)
			Notifications.Notify({ Title = "Theme", Content = "Saved theme '" .. name .. "'", Type = "Success" })
		end,
	})
	saved:AddButton({
		Title = "Load theme",
		Icon = "upload",
		Callback = function()
			local name = themeList:Get()
			if name and Config:LoadTheme(name) then
				Notifications.Notify({ Title = "Theme", Content = "Loaded theme '" .. name .. "'", Type = "Success" })
			end
		end,
	})
	saved:AddButton({
		Title = "Delete theme",
		Style = "Danger",
		Icon = "trash",
		Callback = function()
			local name = themeList:Get()
			if name and window:Confirm("Delete theme?", "'" .. name .. "' will be removed.", "Delete", "Danger") then
				Config:DeleteTheme(name)
				themeList:Refresh(Config:ListThemes(), false)
			end
		end,
	})

	local reset = tab:AddSection({ Title = "Reset", Icon = "refresh", Side = "Right" })
	reset:AddButton({
		Title = strings.ResetAll,
		Style = "Danger",
		Icon = "refresh",
		Callback = function()
			if window:Confirm(strings.ResetAll .. "?", "All appearance settings return to their defaults.", "Reset", "Danger") then
				Theme:Reset()
				Notifications.Notify({ Title = "Theme", Content = "Theme reset to defaults.", Type = "Success" })
			end
		end,
	})

	-- generated category pages ---------------------------------------------------
	for _, group in GROUPS do
		local category = tab:AddCategory({ Title = group.Title, Icon = group.Icon })
		for _, categoryName in group.Categories do
			local order, map = sectionsOf(categoryName)
			if #order > 0 then
				local page = category:AddPage({
					Title = categoryName,
					Icon = CATEGORY_ICON[categoryName],
					Description = "Changes are applied instantly.",
				})
				for index, sectionName in order do
					local section = page:AddSection({
						Title = sectionName,
						Side = if #order == 1 then "Left" elseif index % 2 == 1 then "Left" else "Right",
					})
					local keys = {}
					for _, entry in map[sectionName] do
						track(entry.Key, control(section, entry))
						if entry.Type == "Color" then
							track(entry.Key .. "Transparency", syncers[entry.Key] and syncers[entry.Key][#syncers[entry.Key]])
							table.insert(keys, entry.Key .. "Transparency")
						end
						table.insert(keys, entry.Key)
					end
					section:AddButton({
						Title = strings.ResetSection,
						Icon = "refresh",
						Style = "Dashed",
						Callback = function()
							Theme:Reset(keys)
						end,
					})
				end
				if categoryName == "Fonts" then
					local sample = page:AddSection({ Title = "Sample", Side = "Right" })
					sample:AddLabel({ Text = "The quick brown fox jumps over the lazy dog", Role = "Title" })
					sample:AddLabel({ Text = "Body text - 0123456789", Role = "Body", Color = "TextMuted" })
					sample:AddLabel({ Text = "local mono = true -- code", Role = "Mono", Color = "Accent" })
				elseif categoryName == "Mobile" then
					local quick = page:AddSection({ Title = "Quick toggles", Side = "Right" })
					quick:AddButton({
						Title = strings.EditQuickToggles,
						Icon = "move",
						Callback = function()
							Import("Mobile/QuickToggles").SetEditMode(true)
						end,
					})
					quick:AddButton({
						Title = "Unpin all",
						Icon = "pin",
						Style = "Danger",
						Callback = function()
							Import("Mobile/QuickToggles").UnpinAll()
						end,
					})
				end
			end
		end
	end

	-- keep controls in sync with the theme ---------------------------------------
	local connection = Theme:OnChanged(nil, function(changed)
		local done = {}
		for key in changed do
			local list = syncers[key]
			if list then
				for _, fn in list do
					if not done[fn] then
						done[fn] = true
						pcall(fn, Theme.Values)
					end
				end
			end
		end
	end)
	tab.Maid:Give(connection)
	return tab
end

return AppearanceTab
