# Nova UI – Architekturplan

## 1. Dateistruktur

```
src/
  Constants.lua          Name, Version, Ordnername, Sounds, Strings (zentral änderbar)
  Utility.lua            Services, Create, Farben/Hex, Base64, JSON, Clipboard, GUI-Parenting, Linien
  Signal.lua             Leichtgewichtiges Event-Objekt
  Maid.lua               Connection-/Instance-Manager
  State.lua              Geteilter Laufzeit-Zustand (ScreenGui, Layer, Maid, Fenster)
  Theme.lua              Schema aller Theme-Keys, Presets, Set/Get/Reset, Serialisierung, Import/Export
  ThemeRegistry.lua      Bindings Instanz-Eigenschaft ⇄ Theme-Key(s), animierte Aktualisierung
  Animations.lua         Zentraler Tween-Helper (Speed-Multiplikator, Easing, Aus-Schalter), Ripple, Shake
  Kit.lua                Theme-gebundene Bausteine (Label, Panel, Corner, Stroke, Gradient, Shadow, Icon, Dashed)
  Icons.lua              Icon-Sets (Glyphen) + Registrierung eigener rbxassetids
  Input.lua              Einheitliches Maus/Touch-Tracking: Drag, Tap, Long-Press, Threshold
  Config.lua             Flags, Dateisystem-Abstraktion, Save/Load/…, Autoload, Auto-Save, Migration
  Loader.lua             Loader-Overlay inkl. Key-System
  ESPPreview.lua         ViewportFrame-Vorschau + Overlays, GetESPSettings()
  Components/
    Element.lua          Basisklasse (Flag, Callback, Set/Get, SetVisible, SetDisabled, Tooltip, Zustände)
    Window.lua           Fenster, Topbar, Sidebar/Drawer, Content, Drag/Resize/Minimize/Keybind
    Tab.lua              Tab + Sidebar-Kategorie + Page
    Section.lua          Section/Card + Factory-Methoden für alle Elemente
    Button.lua Toggle.lua Slider.lua Dropdown.lua Textbox.lua Keybind.lua ColorPicker.lua
    Display.lua          Label, Paragraph, Divider, Tags, StatusCard
    Chart.lua            StatCard + LineChart
    Notifications.lua    Toasts (Typen, Restzeit-Bar, Stacking, Position aus Theme) + Verlauf
    Dialog.lua           Modal/Confirm/Prompt
    Tooltip.lua          Hover-Tooltips (Mobile: Long-Press)
  Mobile/
    Device.lua           Erkennung + Override, Safe-Zones (Joystick/Jump), Inset
    FloatingButton.lua   Runder Open-Button mit Edge-Snap
    QuickToggles.lua     Angepinnte Toggles, Edit-Modus mit Raster
  Tabs/
    AppearanceTab.lua    Win:AddThemeTab() – generiert aus dem Theme-Schema
    ConfigTab.lua        Win:AddConfigTab()
  init.lua               Öffentliche Library-API
tools/
  build.py               Bündelt src/ → dist/NovaUI.lua
  luau_check.py          Eigener Luau-Syntaxprüfer (Fallback, wenn luau-analyze nicht läuft)
dist/NovaUI.lua          Bundle (loadstring-fähig)
example.lua  README.md
```

Modulsystem: Jede Datei wird im Bundle in `__modules["Name"] = function() … end` gekapselt und über `Import("Name")`
(lazy, gecacht) geladen. Zyklen werden durch Lazy-Imports innerhalb von Funktionen vermieden.

## 2. Öffentliche API (Kurzfassung)

```lua
local UI = loadstring(game:HttpGet(URL))()
UI:CreateLoader({Title, Subtitle, Logo, Steps = {{Text, Run = function(progress) end, Weight}}, KeySystem = {...}})
local Win = UI:CreateWindow({Title, Subtitle, Logo, Theme = "Midnight" | {Preset = "Mint", Accent = Color3...},
                             ToggleKey = Enum.KeyCode.RightShift, FloatingButton = "Auto"})
local Tab = Win:AddTab({Title, Icon})              Tab:SetBadge(n|true|false)
local Cat = Tab:AddCategory({Title, Icon})         local Page = Cat:AddPage({Title, Icon, Description, Tags})
local Sec = Tab:AddSection("ESP") | Page:AddSection({Title, Icon, Side})   Page:AddCard(...)
Sec:AddButton / AddToggle / AddCheckbox / AddSlider / AddDropdown / AddTextbox / AddKeybind / AddColorPicker
Sec:AddLabel / AddParagraph / AddDivider / AddTags / AddStatusCard / AddStatCard / AddChart / AddESPPreview
Element: :Set(v) :Get() :SetVisible(b) :SetDisabled(b) :SetTooltip(s) :OnChanged(fn) :Destroy()
UI:Notify({Title, Content, Type, Duration})   Win:Dialog({...})   Win:Confirm(title, text) -> boolean
Win:AddThemeTab()  Win:AddConfigTab()
UI:CreateLoader({Theme = "Mint", ...})   -- Loader nutzt bereits Theme + Autoload-Theme
UI.Theme:Set(key, value)  :Get  :ApplyPreset  :Reset  :Export  :Import  :Bind
UI.Config:Save(name) :Load :Delete :Rename :Duplicate :List :SetAutoload :Export :Import
UI:GetESPSettings()   UI:GetFlag(flag)   UI:Destroy()
```

## 3. Theme-Keys

Jeder Farb-Key `X` besitzt automatisch `XTransparency` (0–1).

| Kategorie | Keys |
|---|---|
| Farben | Background, Topbar, Sidebar, Surface, Card, Input, Border, Text, TextMuted, Placeholder, AccentText, Accent, Accent2, Success, Warning, Danger, ToggleOn, ToggleOff, ToggleKnob, SliderFill, SliderTrack, Scrollbar, Shadow, Overlay, Tooltip, NotificationBackground, NotificationBorder, PreviewBackground, PreviewLight |
| Gradients | AccentGradient, ButtonGradient, ProgressGradient, AccentGradientRotation, GradientAnimated, GradientSpeed |
| Hintergrund | BackgroundMode (Solid/Gradient/Image), BackgroundGradientStart, BackgroundGradientEnd, BackgroundGradientRotation, BackgroundImage, BackgroundImageTransparency, BackgroundImageScale, BackgroundImageTileSize, Blur, BlurSize |
| Fonts | FontTitle, FontBody, FontMono, TitleWeight, BodyWeight, TextScale |
| Formen | CornerRadius, BorderEnabled, BorderThickness, ShadowEnabled, ShadowStrength |
| Layout | WindowWidth, WindowHeight, UIScale, SidebarWidth, SidebarPosition, Spacing, TabPosition |
| Transparenz | WindowTransparency, PanelTransparency |
| Animation | AnimationsEnabled, AnimationSpeed, EasingStyle |
| Branding | Title, Subtitle, Logo, IconSet, LoaderTitle, LoaderSubtitle, LoaderStatusText |
| Elemente | ShowAvatar, ShowUsername, NotificationPosition, TooltipsEnabled, SoundsEnabled, SoundVolume |
| Mobile | MobileButton, QuickToggleOn, QuickToggleOff (Farben), MobileButtonSize, QuickToggleSize, MobileButtonShape, MobileTransparency |

## 4. Config-Dateiformat

Ordner: `NovaUI/<Spielname>_<PlaceId>/configs/*.json`, `NovaUI/themes/*.json`, `NovaUI/settings.json`

```json
{
  "Version": 1,
  "Library": "NovaUI",
  "Name": "Legit",
  "SavedAt": 1731430000,
  "Game": { "PlaceId": 123, "Name": "My Game" },
  "Flags": {
    "ESP_Box":      { "Type": "Toggle", "Value": true },
    "Aim_FOV":      { "Type": "Slider", "Value": 120 },
    "ESP_BoxColor": { "Type": "ColorPicker", "Value": { "Color": "#FF4040", "Transparency": 0, "Rainbow": false } },
    "AimKey":       { "Type": "Keybind", "Value": { "Key": "E", "Mode": "Hold" } }
  },
  "Theme":  { "Version": 1, "Preset": "Midnight", "Values": { "Accent": "#5B7CFA", "CornerRadius": 10 } },
  "Window": { "Position": [0.5, 0, 0.5, 0], "Minimized": false, "ToggleKey": "RightShift" },
  "FloatingButton": { "Side": "Right", "Y": 0.4 },
  "QuickToggles": { "ESP_Box": { "X": 0.5, "Y": 0.2, "Size": "M", "Transparency": 0 } }
}
```

`settings.json`: `{ "Version":1, "Autoload": {"<GameKey>": "Legit"}, "AutoSave": false, "AutoSaveInterval": 60,
"SaveOnClose": true, "DeviceMode": "Auto", "RememberedKey": "..." }`

Migration: Version wird geprüft, unbekannte Keys ignoriert, fehlende → Default, Typfehler → Default, defekte Dateien → Notification statt Crash.
