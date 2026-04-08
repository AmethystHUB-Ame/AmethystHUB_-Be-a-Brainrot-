--[[
  Amethyst Brainrot V3 - Full Optimized Script (FIXED)
  Fixes applied:
  [1] connections = {} & track() moved to top of script
  [2] createSlider: renamed inner 'track' Frame to 'sliderTrack' (shadow bug fixed)
  [3] TI_TAB defined alongside other TweenInfo constants
  [4] Attribute renamed "__AmethystV3" -> "__AmethystBrainrotV3" everywhere; notifGui tagged
  [5] createParagraph returns {Set=fn} object; statsPara.Set() used in stats loop
  [6] getSelectedFilters() fixed to handle arrays from multi-select dropdowns
  [7] SellBrainrots / sellLoop: exclusion checks use tableContains() instead of dict lookup
  [8] Players.PlayerAdded/Removing wrapped with track() for proper cleanup
  [9] workspace.Bosses / Map.Bases / Plots wrapped in pcall for safety
]]

-- ============================================================
-- [FIX 1] connections table & track() MUST be at the very top
-- ============================================================
local connections = {}
local function track(conn) connections[#connections+1] = conn; return conn end

--[[ SANDBOX & GUARD ]]--------------------------------------------------------
if _G.__AmethystBrainrotV3 then
    pcall(_G.__AmethystBrainrotV3.cleanup)
end
local Amethyst = {_version = "3.0.0", _alive = true}
_G.__AmethystBrainrotV3 = Amethyst

--[[ SAFE CALL & UTILITIES ]]-------------------------------------------------
local function safeCall(fn, ...)
    return xpcall(fn, function(err)
        warn("[Amethyst Error]: " .. tostring(err) .. "\n" .. debug.traceback())
    end, ...)
end

-- Randomised delay (human-like jitter)
local function jitter(value, percent)
    percent = percent or 0.25
    return value * (1 + (math.random() - 0.5) * percent)
end

-- Dynamic wait based on server ping
local lastPing = 0
local function getServerPing()
    local ok, ping = pcall(function()
        local stats = game:GetService("Stats")
        return stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and ping then lastPing = ping; return ping end
    return lastPing
end

local function adaptiveWait(baseDelay)
    local ping = getServerPing()
    local extra = math.min(0.5, math.max(0, (ping - 150) / 1000))
    local waitTime = jitter(baseDelay + extra, 0.2)
    task.wait(waitTime)
end

-- [FIX 7] Helper: check if array table contains a value
local function tableContains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

--[[ SERVICES & MODULES ]]----------------------------------------------------
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local UserInputService= game:GetService("UserInputService")
local CoreGui         = game:GetService("CoreGui")
local HttpService     = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera          = workspace.CurrentCamera
local LocalPlayer     = Players.LocalPlayer

local Remotes       = require(ReplicatedStorage.Shared.Remotes)
local PlayerState   = require(ReplicatedStorage.Libraries.PlayerState.PlayerStateClient)
local BrainrotsData = require(ReplicatedStorage.Database.BrainrotsData)
local RaritiesData  = require(ReplicatedStorage.Database.RaritiesData)
local MutationsData = require(ReplicatedStorage.Database.MutationsData)

repeat task.wait() until PlayerState.IsReady()
local function GetData(path) return PlayerState.GetPath(path) end

-- Remote call with safety
local function safeFireRemote(remoteName, ...)
    if not Amethyst._alive then return end
    local remote = Remotes[remoteName]
    if remote and type(remote.Fire) == "function" then
        safeCall(remote.Fire, remote, ...)
    end
end

--[[ STATE TABLE (S) — defined BEFORE any UI or function accesses it ]]-------
local S = {
    -- Farm tab
    AutoCollect          = false,
    CollectInterval      = 1,
    FarmBrainrot         = false,
    FarmRarityFilters    = {},   -- array of selected rarity strings
    FarmMutationFilters  = {},   -- array of selected mutation strings

    -- Upgrades tab
    AutoRebirth          = false,
    RebirthInterval      = 1,
    AutoSpeedUpgrade     = false,
    SpeedUpgradeInterval = 1,
    SpeedUpgradeAmount   = 1,
    AutoUpgradeBase      = false,
    UpgradeBaseInterval  = 3,
    AutoUpgradeBrainrots = false,
    MaxUpgradeLevel      = 10,

    -- Automation tab
    AutoEquipBest        = false,
    EquipBestInterval    = 4,
    AutoClaimGifts       = false,
    ClaimGiftsInterval   = 1,
    AutoSell             = false,
    SellInterval         = 3,
    SellThreshold        = 90,
    SellMode             = "Exclude",
    ExcludedRarities     = {},   -- array of excluded rarity strings
    ExcludedMutations    = {},   -- array of excluded mutation strings
    ExcludedNames        = {},   -- array of excluded brainrot name strings

    -- Misc tab
    LasersRemove         = false,
    AntiShake            = false,
    FreezeChasingBosses  = false,
    FreezeBadBosses      = false,

    -- Security
    AntiStaff            = false,
}

--[[ SAVE / LOAD with config profiles ]]--------------------------------------
local CONFIG_FILE = "AmethystBrainrotV3.json"
local HAS_FILE_ACCESS = pcall(function() return writefile and readfile and isfile end)

local function saveConfig()
    if not HAS_FILE_ACCESS then return end
    safeCall(function()
        local data = { S = S, version = Amethyst._version }
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadConfig()
    if not HAS_FILE_ACCESS then return end
    safeCall(function()
        if isfile(CONFIG_FILE) then
            local raw = readfile(CONFIG_FILE)
            if raw and raw ~= "" then
                local data = HttpService:JSONDecode(raw)
                if data and data.S then
                    for k, v in pairs(data.S) do
                        if S[k] ~= nil then S[k] = v end
                    end
                end
            end
        end
    end)
end

local function copyConfigToClipboard()
    local export = { S = S, version = Amethyst._version }
    local json = HttpService:JSONEncode(export)
    safeCall(function()
        if setclipboard then setclipboard(json)
        elseif toclipboard then toclipboard(json)
        else notify("Error", "Clipboard not supported", 3, "danger") end
        notify("Config Copied", "JSON config saved to clipboard", 3, "success")
    end)
end

local function loadConfigFromClipboard()
    safeCall(function()
        local content = nil
        if getclipboard then content = getclipboard()
        elseif fromclipboard then content = fromclipboard() end
        if not content then notify("Error", "Clipboard read not supported", 3, "danger") return end
        local data = HttpService:JSONDecode(content)
        if data and data.S then
            for k, v in pairs(data.S) do
                if S[k] ~= nil then S[k] = v end
            end
            notify("Config Loaded", "Settings restored from clipboard", 3, "success")
        else
            notify("Invalid Config", "Clipboard content is not valid", 3, "danger")
        end
    end)
end

-- Auto-save every 30 seconds
task.spawn(function()
    while Amethyst._alive do
        task.wait(30)
        saveConfig()
    end
end)

--[[ THEME CONSTANTS (Frosted Amethyst) ]]------------------------------------
local THEME = {
    Background          = Color3.fromRGB(13,11,20),
    Surface             = Color3.fromRGB(22,18,31),
    SurfaceElevated     = Color3.fromRGB(30,26,42),
    Border              = Color3.fromRGB(42,36,64),
    Accent              = Color3.fromRGB(155,89,240),
    AccentGlow          = Color3.fromRGB(180,122,255),
    AccentSecondary     = Color3.fromRGB(108,61,207),
    TextPrimary         = Color3.fromRGB(238,234,245),
    TextSecondary       = Color3.fromRGB(139,131,158),
    Success             = Color3.fromRGB(74,222,128),
    Danger              = Color3.fromRGB(248,113,113),
    Warning             = Color3.fromRGB(251,191,36),
    White               = Color3.fromRGB(255,255,255),
    ElementBackground   = Color3.fromRGB(22,18,31),
    ElementBackgroundHover = Color3.fromRGB(30,26,42),
    ElementStroke       = Color3.fromRGB(42,36,64),
    SliderBackground    = Color3.fromRGB(22,18,31),
    SliderProgress      = Color3.fromRGB(155,89,240),
    ToggleEnabled       = Color3.fromRGB(155,89,240),
    ToggleDisabled      = Color3.fromRGB(30,26,42),
    InputBackground     = Color3.fromRGB(18,15,26),
    InputStroke         = Color3.fromRGB(42,36,64),
    PlaceholderColor    = Color3.fromRGB(100,90,130),
    WindowBackground    = Color3.fromRGB(13,11,20),
    Topbar              = Color3.fromRGB(18,15,26),
    SidebarBackground   = Color3.fromRGB(16,13,24),
    SidebarHover        = Color3.fromRGB(25,22,36),
    ContentBackground   = Color3.fromRGB(13,11,20),
    LoadingBackground   = Color3.fromRGB(8,6,14),
    LoadingBarBackground= Color3.fromRGB(30,26,42),
    LoadingBarFill      = Color3.fromRGB(155,89,240),
}

local TI_SMOOTH = TweenInfo.new(0.3,  Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_FAST   = TweenInfo.new(0.1,  Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local TI_BOUNCE = TweenInfo.new(0.2,  Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local TI_DROP   = TweenInfo.new(0.15, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
-- [FIX 3] TI_TAB was used at switchTab() but never defined
local TI_TAB    = TweenInfo.new(0.15, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)

local function tweenProp(obj, props, tweenInfo)
    safeCall(function() TweenService:Create(obj, tweenInfo or TI_SMOOTH, props):Play() end)
end

--[[ NOTIFICATION SYSTEM ]]---------------------------------------------------
local notifGui = Instance.new("ScreenGui")
notifGui.Name = "AmethystNotifsV3"
notifGui.ResetOnSpawn = false
-- [FIX 4] Tag notifGui so cleanup handler can destroy it
notifGui:SetAttribute("__AmethystBrainrotV3", true)
pcall(function() notifGui.Parent = CoreGui end)

local notifContainer = Instance.new("Frame")
notifContainer.Size = UDim2.new(0, 280, 1, -20)
notifContainer.Position = UDim2.new(1, -290, 0, 10)
notifContainer.BackgroundTransparency = 1
notifContainer.Parent = notifGui

local notifQueue = {}
local MAX_VISIBLE = 4

local function processQueue()
    local visible = 0
    for _, child in ipairs(notifContainer:GetChildren()) do
        if child:IsA("Frame") and child.Name == "Notification" then visible += 1 end
    end
    while visible < MAX_VISIBLE and #notifQueue > 0 do
        table.remove(notifQueue, 1).show()
        visible += 1
    end
end

local function notify(title, content, dur, severity)
    dur = dur or 4
    local severityColor = severity == "success" and THEME.Success
        or severity == "danger"  and THEME.Danger
        or severity == "warning" and THEME.Warning
        or THEME.Accent
    local function doShow()
        local contentHeight = content and (math.ceil(#content / 34) * 16) or 0
        local totalHeight = 12 + 18 + (contentHeight > 0 and (4 + contentHeight) or 0) + 10 + 2
        local frame = Instance.new("Frame")
        frame.Name = "Notification"
        frame.Size = UDim2.new(0, 270, 0, math.max(totalHeight, 50))
        frame.BackgroundColor3 = THEME.Surface
        frame.BackgroundTransparency = 0.2
        frame.ClipsDescendants = true
        frame.Parent = notifContainer
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
        local strip = Instance.new("Frame")
        strip.Size = UDim2.new(0, 4, 1, -8)
        strip.Position = UDim2.new(0, 0, 0, 4)
        strip.BackgroundColor3 = severityColor
        strip.Parent = frame
        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(1, -20, 0, 18)
        titleLbl.Position = UDim2.new(0, 14, 0, 8)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.TextSize = 13
        titleLbl.Text = "◆ " .. (title or "Amethyst")
        titleLbl.TextColor3 = THEME.TextPrimary
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.Parent = frame
        if content and content ~= "" then
            local contentLbl = Instance.new("TextLabel")
            contentLbl.Size = UDim2.new(1, -20, 0, contentHeight)
            contentLbl.Position = UDim2.new(0, 14, 0, 28)
            contentLbl.BackgroundTransparency = 1
            contentLbl.Font = Enum.Font.Gotham
            contentLbl.TextSize = 12
            contentLbl.Text = content
            contentLbl.TextColor3 = THEME.TextSecondary
            contentLbl.TextWrapped = true
            contentLbl.Parent = frame
        end
        local progress = Instance.new("Frame")
        progress.Size = UDim2.new(1, -16, 0, 2)
        progress.Position = UDim2.new(0, 8, 1, -6)
        progress.BackgroundColor3 = severityColor
        progress.Parent = frame
        frame.Position = UDim2.new(0, 290, 0, 0)
        tweenProp(frame, {Position = UDim2.new(0, 0, 0, 0)}, TweenInfo.new(0.25))
        tweenProp(progress, {Size = UDim2.new(0, 0, 0, 2)}, TweenInfo.new(dur))
        task.delay(dur, function()
            tweenProp(frame, {Position = UDim2.new(0, 290, 0, 0), BackgroundTransparency = 1}, TweenInfo.new(0.3))
            task.delay(0.35, function() safeCall(function() frame:Destroy(); processQueue() end) end)
        end)
    end
    local visible = 0
    for _, child in ipairs(notifContainer:GetChildren()) do
        if child:IsA("Frame") and child.Name == "Notification" then visible += 1 end
    end
    if visible < MAX_VISIBLE then doShow() else
        if #notifQueue >= 10 then table.remove(notifQueue, 1) end
        table.insert(notifQueue, {show = doShow})
    end
end

local function notifyToggle(name, state)
    notify(name .. (state and " ON" or " OFF"), state and "Enabled" or "Disabled", 3)
end

--[[ UI FRAMEWORK (Amethyst Core) ]]------------------------------------------
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- [FIX 4] Use consistent attribute name __AmethystBrainrotV3
local function createScreenGui(name, displayOrder)
    local gui = Instance.new("ScreenGui")
    gui.Name = "SG_" .. HttpService:GenerateGUID(false)
    gui:SetAttribute("__AmethystBrainrotV3", true)
    gui.DisplayOrder = displayOrder or 1
    gui.ResetOnSpawn = false
    pcall(function() gui.Parent = CoreGui end)
    return gui
end

-- Loading Screen
local loadingGui = createScreenGui("AmethystLoading", 100)
local loadingFrame = Instance.new("Frame")
loadingFrame.Size = UDim2.new(1, 0, 1, 0)
loadingFrame.BackgroundColor3 = THEME.LoadingBackground
loadingFrame.BorderSizePixel = 0
loadingFrame.Parent = loadingGui

local glowRing = Instance.new("Frame")
glowRing.Size = UDim2.new(0, 80, 0, 80)
glowRing.Position = UDim2.new(0.5, 0, 0.5, -80)
glowRing.AnchorPoint = Vector2.new(0.5, 0.5)
glowRing.BackgroundColor3 = THEME.Accent
glowRing.BackgroundTransparency = 0.3
glowRing.Parent = loadingFrame
Instance.new("UICorner", glowRing).CornerRadius = UDim.new(1, 0)

local loadingTitle = Instance.new("TextLabel")
loadingTitle.Size = UDim2.new(1, 0, 0, 36)
loadingTitle.Position = UDim2.new(0.5, 0, 0.5, -16)
loadingTitle.AnchorPoint = Vector2.new(0.5, 0.5)
loadingTitle.BackgroundTransparency = 1
loadingTitle.Font = Enum.Font.GothamBold
loadingTitle.TextSize = 28
loadingTitle.Text = "BE A BRAINROT"
loadingTitle.TextColor3 = THEME.Accent
loadingTitle.Parent = loadingFrame

local loadingSubtitle = Instance.new("TextLabel")
loadingSubtitle.Size = UDim2.new(1, 0, 0, 20)
loadingSubtitle.Position = UDim2.new(0.5, 0, 0.5, 14)
loadingSubtitle.AnchorPoint = Vector2.new(0.5, 0.5)
loadingSubtitle.BackgroundTransparency = 1
loadingSubtitle.Font = Enum.Font.Gotham
loadingSubtitle.TextSize = 14
loadingSubtitle.Text = "Amethyst Core V3 | Optimized"
loadingSubtitle.TextColor3 = THEME.TextSecondary
loadingSubtitle.Parent = loadingFrame

local progressBg = Instance.new("Frame")
progressBg.Size = UDim2.new(0, 220, 0, 3)
progressBg.Position = UDim2.new(0.5, 0, 0.5, 40)
progressBg.AnchorPoint = Vector2.new(0.5, 0.5)
progressBg.BackgroundColor3 = THEME.LoadingBarBackground
progressBg.Parent = loadingFrame

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = THEME.LoadingBarFill
progressFill.Parent = progressBg

local percentLabel = Instance.new("TextLabel")
percentLabel.Size = UDim2.new(0, 220, 0, 18)
percentLabel.Position = UDim2.new(0.5, 0, 0.5, 56)
percentLabel.AnchorPoint = Vector2.new(0.5, 0.5)
percentLabel.BackgroundTransparency = 1
percentLabel.Font = Enum.Font.Gotham
percentLabel.TextSize = 11
percentLabel.Text = "0%"
percentLabel.TextColor3 = THEME.TextSecondary
percentLabel.Parent = loadingFrame

-- Main Hub Window
local hubGui = createScreenGui("AmethystHub", 10)
local panelWidth = IS_MOBILE and UDim2.new(0.92, 0, 0.7, 0) or UDim2.new(0, 520, 0, 380)
local sidebarWidth = IS_MOBILE and 110 or 130
local mainFrame = Instance.new("Frame")
mainFrame.Size = panelWidth
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = THEME.WindowBackground
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Visible = false
mainFrame.Parent = hubGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 6)

local accentLine = Instance.new("Frame")
accentLine.Size = UDim2.new(1, 0, 0, 2)
accentLine.BackgroundColor3 = THEME.Accent
accentLine.Parent = mainFrame

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 34)
topBar.Position = UDim2.new(0, 0, 0, 2)
topBar.BackgroundColor3 = THEME.Topbar
topBar.Parent = mainFrame

local topBarTitle = Instance.new("TextLabel")
topBarTitle.Size = UDim2.new(1, -80, 1, 0)
topBarTitle.Position = UDim2.new(0, 12, 0, 0)
topBarTitle.BackgroundTransparency = 1
topBarTitle.Font = Enum.Font.GothamBold
topBarTitle.TextSize = 13
topBarTitle.Text = "◆ Be a Brainrot  |  Amethyst V3"
topBarTitle.TextColor3 = THEME.TextPrimary
topBarTitle.TextXAlignment = Enum.TextXAlignment.Left
topBarTitle.Parent = topBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 34, 0, 34)
closeBtn.Position = UDim2.new(1, -34, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = THEME.TextSecondary
closeBtn.Parent = topBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 34, 0, 34)
minimizeBtn.Position = UDim2.new(1, -68, 0, 0)
minimizeBtn.BackgroundTransparency = 1
minimizeBtn.Text = "—"
minimizeBtn.TextColor3 = THEME.TextSecondary
minimizeBtn.Parent = topBar

track(closeBtn.MouseButton1Click:Connect(function()
    tweenProp(mainFrame, {Size = UDim2.new(mainFrame.Size.X.Scale, mainFrame.Size.X.Offset, 0, 0)}, TweenInfo.new(0.3))
    task.delay(0.3, function() mainFrame.Visible = false; mainFrame.Size = panelWidth end)
end))

local isMinimized = false
track(minimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    tweenProp(mainFrame, {
        Size = isMinimized
            and UDim2.new(mainFrame.Size.X.Scale, mainFrame.Size.X.Offset, 0, 36)
            or panelWidth
    }, TI_SMOOTH)
end))

-- Dragging
local dragging = false
local dragStart, startPos
track(topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end))
track(UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end))

-- Sidebar
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, sidebarWidth, 1, -36)
sidebar.Position = UDim2.new(0, 0, 0, 36)
sidebar.BackgroundColor3 = THEME.SidebarBackground
sidebar.Parent = mainFrame
local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.Padding = UDim.new(0, 3)
sidebarLayout.Parent = sidebar

-- Content area
local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -sidebarWidth, 1, -36)
contentArea.Position = UDim2.new(0, sidebarWidth, 0, 36)
contentArea.BackgroundColor3 = THEME.ContentBackground
contentArea.Parent = mainFrame

-- Tabs
local TAB_NAMES = {"Farm", "Upgrades", "Automation", "Misc", "Settings"}
local tabPages = {}
for i, tabName in ipairs(TAB_NAMES) do
    local page = Instance.new("ScrollingFrame")
    page.Name = tabName .. "Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.ScrollBarThickness = 3
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Visible = (i == 1)
    page.Parent = contentArea
    local pageLayout = Instance.new("UIListLayout")
    pageLayout.Padding = UDim.new(0, 8)
    pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pageLayout.Parent = page
    local pagePadding = Instance.new("UIPadding")
    pagePadding.PaddingTop    = UDim.new(0, 8)
    pagePadding.PaddingBottom = UDim.new(0, 8)
    pagePadding.PaddingLeft   = UDim.new(0, 8)
    pagePadding.PaddingRight  = UDim.new(0, 8)
    pagePadding.Parent = page
    tabPages[tabName] = page
end

-- Tab switching
local currentTab = "Farm"
local tabButtons = {}
local function switchTab(tabName)
    if currentTab == tabName then return end
    currentTab = tabName
    for name, page in pairs(tabPages) do page.Visible = (name == tabName) end
    for name, btnData in pairs(tabButtons) do
        local isSelected = (name == tabName)
        -- [FIX 3] TI_TAB is now defined above
        tweenProp(btnData.button, {
            BackgroundColor3 = isSelected and THEME.SurfaceElevated or THEME.SidebarBackground
        }, TI_TAB)
        btnData.pill.Visible = isSelected
    end
end

for i, tabName in ipairs(TAB_NAMES) do
    local tabBtn = Instance.new("TextButton")
    tabBtn.Size = UDim2.new(1, -8, 0, 30)
    tabBtn.BackgroundColor3 = (i == 1) and THEME.SurfaceElevated or THEME.SidebarBackground
    tabBtn.Font = Enum.Font.GothamBold
    tabBtn.TextSize = 11
    tabBtn.Text = "    " .. tabName
    tabBtn.TextColor3 = (i == 1) and THEME.TextPrimary or THEME.TextSecondary
    tabBtn.TextXAlignment = Enum.TextXAlignment.Left
    tabBtn.AutoButtonColor = false
    tabBtn.LayoutOrder = i
    tabBtn.Parent = sidebar
    Instance.new("UICorner", tabBtn).CornerRadius = UDim.new(0, 4)
    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 3, 0.6, 0)
    pill.Position = UDim2.new(0, -4, 0.2, 0)
    pill.BackgroundColor3 = THEME.Accent
    pill.Visible = (i == 1)
    pill.Parent = tabBtn
    tabButtons[tabName] = {button = tabBtn, pill = pill}
    track(tabBtn.MouseButton1Click:Connect(function() switchTab(tabName) end))
end

-- ============================================================
-- Component Factories
-- ============================================================
local function createSection(parent, text)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 28)
    container.BackgroundTransparency = 1
    container.Parent = parent
    local left = Instance.new("Frame")
    left.Size = UDim2.new(0.35, 0, 0, 1)
    left.Position = UDim2.new(0, 0, 0.5, 0)
    left.AnchorPoint = Vector2.new(0, 0.5)
    left.BackgroundColor3 = THEME.Border
    left.Parent = container
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.3, 0, 1, 0)
    lbl.Position = UDim2.new(0.35, 0, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 12
    lbl.Text = text
    lbl.TextColor3 = THEME.Accent
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.Parent = container
    local right = Instance.new("Frame")
    right.Size = UDim2.new(0.35, 0, 0, 1)
    right.Position = UDim2.new(0.65, 0, 0.5, 0)
    right.AnchorPoint = Vector2.new(0, 0.5)
    right.BackgroundColor3 = THEME.Border
    right.Parent = container
    return container
end

local function createToggle(parent, config)
    local toggled = config.CurrentValue or false
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = THEME.ElementBackground
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.Text = config.Name
    label.TextColor3 = THEME.TextPrimary
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row
    local trackFrame = Instance.new("Frame")
    trackFrame.Size = UDim2.new(0, 38, 0, 20)
    trackFrame.Position = UDim2.new(1, -48, 0.5, 0)
    trackFrame.AnchorPoint = Vector2.new(0, 0.5)
    trackFrame.BackgroundColor3 = toggled and THEME.ToggleEnabled or THEME.ToggleDisabled
    trackFrame.BorderSizePixel = 0
    trackFrame.Parent = row
    Instance.new("UICorner", trackFrame).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = toggled and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.BackgroundColor3 = THEME.White
    knob.BorderSizePixel = 0
    knob.Parent = trackFrame
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local click = Instance.new("TextButton")
    click.Size = UDim2.new(1, 0, 1, 0)
    click.BackgroundTransparency = 1
    click.Text = ""
    click.Parent = row
    local function update()
        tweenProp(trackFrame, {BackgroundColor3 = toggled and THEME.ToggleEnabled or THEME.ToggleDisabled}, TI_BOUNCE)
        tweenProp(knob, {Position = toggled and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)}, TI_BOUNCE)
    end
    track(click.MouseButton1Click:Connect(function()
        toggled = not toggled
        update()
        safeCall(config.Callback, toggled)
    end))
    return {
        Set = function(v) toggled = v; update() end,
        Get = function() return toggled end
    }
end

-- [FIX 2] createSlider: renamed inner 'track' Frame variable to 'sliderTrack'
-- to prevent shadowing the outer track() connection-tracking function
local function createSlider(parent, config)
    local minVal, maxVal, inc = config.Range[1], config.Range[2], config.Increment or 1
    local cur = config.CurrentValue or minVal
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3 = THEME.ElementBackground
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 0, 20)
    label.Position = UDim2.new(0, 12, 0, 6)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.Text = config.Name
    label.TextColor3 = THEME.TextPrimary
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row
    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0.3, -12, 0, 20)
    valLbl.Position = UDim2.new(0.7, 0, 0, 6)
    valLbl.BackgroundTransparency = 1
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextSize = 12
    valLbl.Text = tostring(cur)
    valLbl.TextColor3 = THEME.Accent
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = row
    -- [FIX 2] Was "local track = Instance.new("Frame")" — now "sliderTrack"
    local sliderTrack = Instance.new("Frame")
    sliderTrack.Size = UDim2.new(1, -24, 0, 4)
    sliderTrack.Position = UDim2.new(0, 12, 0, 36)
    sliderTrack.BackgroundColor3 = THEME.SliderBackground
    sliderTrack.Parent = row
    Instance.new("UICorner", sliderTrack).CornerRadius = UDim.new(1, 0)
    local fillPct = (cur - minVal) / math.max(maxVal - minVal, 0.001)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(fillPct, 0, 1, 0)
    fill.BackgroundColor3 = THEME.Accent
    fill.Parent = sliderTrack
    local thumb = Instance.new("Frame")
    thumb.Size = UDim2.new(0, 12, 0, 12)
    thumb.Position = UDim2.new(fillPct, -6, 0.5, 0)
    thumb.AnchorPoint = Vector2.new(0, 0.5)
    thumb.BackgroundColor3 = THEME.Accent
    thumb.Parent = sliderTrack
    Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)
    local inputArea = Instance.new("TextButton")
    inputArea.Size = UDim2.new(1, 0, 0, 20)
    inputArea.Position = UDim2.new(0, 0, 0.5, 0)
    inputArea.AnchorPoint = Vector2.new(0, 0.5)
    inputArea.BackgroundTransparency = 1
    inputArea.Text = ""
    inputArea.Parent = sliderTrack
    local dragging = false
    local function update(pct)
        pct = math.clamp(pct, 0, 1)
        local raw = minVal + (maxVal - minVal) * pct
        cur = math.floor(raw / inc + 0.5) * inc
        cur = math.clamp(cur, minVal, maxVal)
        local newPct = (cur - minVal) / math.max(maxVal - minVal, 0.001)
        fill.Size = UDim2.new(newPct, 0, 1, 0)
        thumb.Position = UDim2.new(newPct, -6, 0.5, 0)
        valLbl.Text = tostring(cur)
    end
    -- [FIX 2] Now correctly calls the outer track() function (not the sliderTrack Frame)
    track(inputArea.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local pos = input.Position.X
            local absPos = sliderTrack.AbsolutePosition.X
            local absSize = sliderTrack.AbsoluteSize.X
            update((pos - absPos) / absSize)
            safeCall(config.Callback, cur)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local pos = input.Position.X
            local absPos = sliderTrack.AbsolutePosition.X
            local absSize = sliderTrack.AbsoluteSize.X
            update((pos - absPos) / absSize)
            safeCall(config.Callback, cur)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    return {
        Set = function(v)
            cur = math.clamp(v, minVal, maxVal)
            update((cur - minVal) / math.max(maxVal - minVal, 0.001))
        end,
        Get = function() return cur end
    }
end

local function createButton(parent, config)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = THEME.ElementBackground
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Text = config.Name
    btn.TextColor3 = THEME.Accent
    btn.AutoButtonColor = false
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    track(btn.MouseButton1Click:Connect(function()
        tweenProp(btn, {Size = UDim2.new(1, -4, 0, 34)}, TweenInfo.new(0.08))
        task.delay(0.08, function() tweenProp(btn, {Size = UDim2.new(1, 0, 0, 36)}, TI_FAST) end)
        safeCall(config.Callback)
    end))
    return btn
end

local function createDropdown(parent, config)
    local options = config.Options or {}
    local multi = config.MultipleOptions or false
    local selected = {}
    if multi and type(config.CurrentOption) == "table" then
        for _, v in ipairs(config.CurrentOption) do selected[v] = true end
    elseif config.CurrentOption then
        selected[config.CurrentOption] = true
    end
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 38)
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false
    container.Parent = parent
    local header = Instance.new("TextButton")
    header.Size = UDim2.new(1, 0, 0, 38)
    header.BackgroundColor3 = THEME.ElementBackground
    header.Font = Enum.Font.Gotham
    header.TextSize = 12
    header.TextColor3 = THEME.TextPrimary
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.AutoButtonColor = false
    header.Parent = container
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 6)
    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 20, 1, 0)
    arrow.Position = UDim2.new(1, -20, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Font = Enum.Font.Gotham
    arrow.TextSize = 12
    arrow.Text = "▼"
    arrow.TextColor3 = THEME.TextSecondary
    arrow.Parent = header
    local optContainer = Instance.new("Frame")
    optContainer.Size = UDim2.new(1, 0, 0, 0)
    optContainer.Position = UDim2.new(0, 0, 0, 40)
    optContainer.BackgroundColor3 = THEME.Surface
    optContainer.ClipsDescendants = true
    optContainer.Visible = false
    optContainer.Parent = container
    Instance.new("UICorner", optContainer).CornerRadius = UDim.new(0, 6)
    local optLayout = Instance.new("UIListLayout")
    optLayout.Padding = UDim.new(0, 1)
    optLayout.Parent = optContainer
    local function getSelectedText()
        local sel = {}
        for _, opt in ipairs(options) do if selected[opt] then table.insert(sel, opt) end end
        if #sel == 0 then return config.Name or "Select..." end
        return config.Name .. ": " .. table.concat(sel, ", ")
    end
    header.Text = getSelectedText()
    local optButtons = {}
    local function refresh()
        for _, btn in ipairs(optButtons) do btn:Destroy() end
        optButtons = {}
        for i, opt in ipairs(options) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -8, 0, 28)
            btn.Position = UDim2.new(0, 4, 0, 0)
            btn.BackgroundColor3 = selected[opt] and THEME.SurfaceElevated or THEME.Surface
            btn.BackgroundTransparency = selected[opt] and 0 or 0.5
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 11
            btn.Text = (selected[opt] and "  ● " or "    ") .. opt
            btn.TextColor3 = selected[opt] and THEME.TextPrimary or THEME.TextSecondary
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.AutoButtonColor = false
            btn.LayoutOrder = i
            btn.Parent = optContainer
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
            track(btn.MouseButton1Click:Connect(function()
                if multi then
                    selected[opt] = not selected[opt]
                else
                    selected = {}; selected[opt] = true
                end
                header.Text = getSelectedText()
                refresh()
                if multi then
                    local result = {}
                    for _, o in ipairs(options) do if selected[o] then table.insert(result, o) end end
                    safeCall(config.Callback, result)
                else
                    safeCall(config.Callback, opt)
                    optContainer.Visible = false
                    container.Size = UDim2.new(1, 0, 0, 38)
                    arrow.Text = "▼"
                end
            end))
            table.insert(optButtons, btn)
        end
    end
    refresh()
    local open = false
    track(header.MouseButton1Click:Connect(function()
        open = not open
        if open then
            arrow.Text = "▲"
            optContainer.Visible = true
            local totalH = (#options * 29) + 8
            tweenProp(optContainer, {Size = UDim2.new(1, 0, 0, totalH)}, TI_DROP)
            container.Size = UDim2.new(1, 0, 0, 38 + 2 + totalH)
        else
            arrow.Text = "▼"
            tweenProp(optContainer, {Size = UDim2.new(1, 0, 0, 0)}, TI_DROP)
            task.delay(0.15, function()
                optContainer.Visible = false
                container.Size = UDim2.new(1, 0, 0, 38)
            end)
        end
    end))
    return {
        Set = function(val)
            if multi and type(val) == "table" then
                selected = {}
                for _, v in ipairs(val) do selected[v] = true end
            elseif type(val) == "string" then
                selected = {[val] = true}
            end
            header.Text = getSelectedText()
            refresh()
        end,
        Get = function()
            if multi then
                local r = {}
                for _, o in ipairs(options) do if selected[o] then table.insert(r, o) end end
                return r
            else
                for _, o in ipairs(options) do if selected[o] then return o end end
                return nil
            end
        end
    }
end

local function createInput(parent, config)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = THEME.ElementBackground
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.4, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.Text = config.Name
    label.TextColor3 = THEME.TextPrimary
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.55, -12, 0, 26)
    box.Position = UDim2.new(0.45, 0, 0.5, 0)
    box.AnchorPoint = Vector2.new(0, 0.5)
    box.BackgroundColor3 = THEME.InputBackground
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.Text = ""
    box.PlaceholderText = config.PlaceholderText or "Type..."
    box.PlaceholderColor3 = THEME.PlaceholderColor
    box.TextColor3 = THEME.TextPrimary
    box.ClearTextOnFocus = false
    box.Parent = row
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    track(box.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            safeCall(config.Callback, box.Text)
            if config.RemoveTextAfterFocusLost then box.Text = "" end
        end
    end))
    return {
        Set = function(v) box.Text = tostring(v or "") end,
        Get = function() return box.Text end
    }
end

-- [FIX 5] createParagraph now returns a table with .Set(text) method
-- so that statsPara content can be updated at runtime
local function createParagraph(parent, config)
    local title   = config.Title   or "Info"
    local content = config.Content or ""
    local lines  = math.ceil(#content / 50)
    local height = 28 + math.max(lines * 16, 20) + 12
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, height)
    frame.BackgroundColor3 = THEME.ElementBackground
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -16, 0, 22)
    titleLbl.Position = UDim2.new(0, 8, 0, 6)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 13
    titleLbl.Text = title
    titleLbl.TextColor3 = THEME.Accent
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = frame
    local contentLbl = Instance.new("TextLabel")
    contentLbl.Size = UDim2.new(1, -16, 0, height - 34)
    contentLbl.Position = UDim2.new(0, 8, 0, 28)
    contentLbl.BackgroundTransparency = 1
    contentLbl.Font = Enum.Font.Gotham
    contentLbl.TextSize = 12
    contentLbl.Text = content
    contentLbl.TextColor3 = THEME.TextSecondary
    contentLbl.TextWrapped = true
    contentLbl.Parent = frame
    -- Return object with Set() method so callers can update content
    return {
        Instance = frame,
        Set = function(newText)
            contentLbl.Text = tostring(newText or "")
        end,
        Get = function()
            return contentLbl.Text
        end
    }
end

-- Watermark
local watermarkGui = createScreenGui("AmethystWatermark", 999)
local wmPill = Instance.new("Frame")
wmPill.Size = UDim2.new(0, 250, 0, 28)
wmPill.Position = UDim2.new(0, 10, 1, -38)
wmPill.BackgroundColor3 = THEME.Surface
wmPill.BackgroundTransparency = 0.25
wmPill.Parent = watermarkGui
Instance.new("UICorner", wmPill).CornerRadius = UDim.new(0, 14)
local wmText = Instance.new("TextLabel")
wmText.Size = UDim2.new(1, -20, 1, 0)
wmText.Position = UDim2.new(0, 18, 0, 0)
wmText.BackgroundTransparency = 1
wmText.Font = Enum.Font.Gotham
wmText.TextSize = 12
wmText.Text = "Be a Brainrot  |  Amethyst V3"
wmText.TextColor3 = THEME.TextPrimary
wmText.TextXAlignment = Enum.TextXAlignment.Left
wmText.Parent = wmPill

-- Floating Toggle Button
local toggleGui = createScreenGui("AmethystToggle", 1000)
local btnSize = IS_MOBILE and 54 or 42
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, btnSize, 0, btnSize)
toggleBtn.Position = UDim2.new(0.5, -(btnSize/2), 1, -(btnSize+20))
toggleBtn.BackgroundColor3 = THEME.Surface
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Text = "◆"
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = IS_MOBILE and 20 or 16
toggleBtn.TextColor3 = THEME.TextPrimary
toggleBtn.Parent = toggleGui
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0.5, 0)
local toggleGlow = Instance.new("Frame")
toggleGlow.Size = UDim2.new(0, btnSize+10, 0, btnSize+10)
toggleGlow.Position = UDim2.new(0.5, -(btnSize+10)/2, 1, -(btnSize+20)-5)
toggleGlow.BackgroundColor3 = THEME.Accent
toggleGlow.BackgroundTransparency = 0.75
toggleGlow.Parent = toggleGui
Instance.new("UICorner", toggleGlow).CornerRadius = UDim.new(0.5, 0)
local menuVisible = true
local function toggleHubVisibility()
    menuVisible = not mainFrame.Visible
    mainFrame.Visible = menuVisible
    tweenProp(toggleBtn, {Size = UDim2.new(0, btnSize-6, 0, btnSize-6)}, TI_FAST)
    task.delay(0.1, function() tweenProp(toggleBtn, {Size = UDim2.new(0, btnSize, 0, btnSize)}, TI_BOUNCE) end)
    tweenProp(toggleBtn, {Rotation = menuVisible and 0 or 180}, TI_SMOOTH)
    tweenProp(toggleGlow, {BackgroundTransparency = menuVisible and 0.75 or 0.95}, TI_SMOOTH)
end
track(toggleBtn.Activated:Connect(toggleHubVisibility))

-- Load config after UI built
loadConfig()

-- ============================================================
-- BRAINROT BACKEND LOGIC
-- ============================================================

-- Stats tracking
local sessionRebirths  = 0
local lastMoneyCheck   = 0
local lastMoneyValue   = 0
local moneyPerMinute   = 0

local function updateStats()
    local now = os.clock()
    local currentMoney = GetData("Money") or 0
    if lastMoneyCheck > 0 then
        local delta = now - lastMoneyCheck
        if delta > 0 then
            moneyPerMinute = (currentMoney - lastMoneyValue) / delta * 60
            if moneyPerMinute < 0 then moneyPerMinute = 0 end
        end
    end
    lastMoneyCheck = now
    lastMoneyValue = currentMoney
end

-- Remote helper functions
local function CollectCash()
    for slot = 1, 20 do
        task.spawn(function() safeFireRemote("CollectCash", slot) end)
        adaptiveWait(0.1)
    end
end
local function Rebirth()
    safeFireRemote("RequestRebirth")
    sessionRebirths += 1
end
local function SpeedUpgrade(amount) safeFireRemote("SpeedUpgrade", amount) end
local function EquipBestBrainrots() safeFireRemote("EquipBestBrainrots") end
local function UpgradeBase() safeFireRemote("UpgradeBase") end
local function ClaimGifts()
    for i = 1, 9 do
        task.spawn(function() safeFireRemote("ClaimGift", i) end)
        adaptiveWait(0.5)
    end
end

-- Inventory percentage
local function getInventoryFillPercentage()
    local stored = GetData("StoredBrainrots") or {}
    local total = 0
    for _ in pairs(stored) do total += 1 end
    local maxSlots = 30
    pcall(function()
        local vip = game:GetService("MarketplaceService"):UserOwnsGamePassAsync(LocalPlayer.UserId, 1760093100)
        if vip then maxSlots = 40 end
    end)
    return (total / maxSlots) * 100
end

-- [FIX 7] Shared helper: build a set from an exclusion array for O(1) lookup
local function buildExclusionSet(arr)
    local set = {}
    for _, v in ipairs(arr) do set[v] = true end
    return set
end

-- [FIX 7] Shared sell decision function — uses array exclusion lists correctly
local function shouldSellEntry(brainrot)
    local index    = brainrot.Index
    local mutation = brainrot.Mutation or "Default"
    local data     = BrainrotsData[index]
    if not data then return false end
    local rarity   = data.Rarity
    local excluded = false
    if tableContains(S.ExcludedRarities,   rarity)   then excluded = true end
    if not excluded and tableContains(S.ExcludedMutations, mutation) then excluded = true end
    if not excluded and tableContains(S.ExcludedNames,    index)    then excluded = true end
    return (S.SellMode == "Exclude" and not excluded)
        or (S.SellMode == "Include" and excluded)
end

local function SellBrainrots()
    local stored = GetData("StoredBrainrots") or {}
    for slotKey, brainrot in pairs(stored) do
        if shouldSellEntry(brainrot) then
            task.spawn(function() safeFireRemote("SellThis", slotKey) end)
            adaptiveWait(0.1)
        end
    end
end

-- ============================================================
-- AUTO LOOPS
-- ============================================================
local collectActive = false; local collectTask = nil
local function collectLoop()
    while Amethyst._alive and collectActive do
        for slot = 1, 20 do
            safeFireRemote("CollectCash", slot)
            adaptiveWait(0.1)
        end
        adaptiveWait(S.CollectInterval)
    end
    collectTask = nil
end

local rebirthActive = false; local rebirthTask = nil
local function rebirthLoop()
    while Amethyst._alive and rebirthActive do
        local speed    = GetData("Speed") or 0
        local rebirths = GetData("Rebirths") or 0
        local nextCost = 40 + rebirths * 10
        if speed >= nextCost then
            safeFireRemote("RequestRebirth")
            sessionRebirths += 1
            adaptiveWait(2 + math.random() * 1.5)
        end
        adaptiveWait(S.RebirthInterval)
    end
    rebirthTask = nil
end

local speedUpActive = false; local speedUpTask = nil
local function speedUpLoop()
    while Amethyst._alive and speedUpActive do
        safeFireRemote("SpeedUpgrade", S.SpeedUpgradeAmount)
        adaptiveWait(S.SpeedUpgradeInterval)
    end
    speedUpTask = nil
end

local equipActive = false; local equipTask = nil
local function equipLoop()
    while Amethyst._alive and equipActive do
        safeFireRemote("EquipBestBrainrots")
        adaptiveWait(S.EquipBestInterval)
    end
    equipTask = nil
end

local claimActive = false; local claimTask = nil
local function claimLoop()
    while Amethyst._alive and claimActive do
        for i = 1, 9 do
            safeFireRemote("ClaimGift", i)
            adaptiveWait(0.5)
        end
        adaptiveWait(S.ClaimGiftsInterval)
    end
    claimTask = nil
end

local baseActive = false; local baseTask = nil
local function baseLoop()
    while Amethyst._alive and baseActive do
        safeFireRemote("UpgradeBase")
        adaptiveWait(S.UpgradeBaseInterval)
    end
    baseTask = nil
end

local sellActive = false; local sellTask = nil
local function sellLoop()
    while Amethyst._alive and sellActive do
        local fillPercent = getInventoryFillPercentage()
        if fillPercent >= S.SellThreshold then
            local stored = GetData("StoredBrainrots") or {}
            for slotKey, brainrot in pairs(stored) do
                -- [FIX 7] Using shared shouldSellEntry() which handles arrays
                if shouldSellEntry(brainrot) then
                    safeFireRemote("SellThis", slotKey)
                    adaptiveWait(0.1)
                end
            end
        end
        adaptiveWait(S.SellInterval)
    end
    sellTask = nil
end

-- ============================================================
-- FARM BRAINROTS
-- ============================================================

-- [FIX 6] getSelectedFilters: dropdowns return arrays, so just return the array
local function getSelectedFilters(arr)
    if type(arr) == "table" then return arr end
    return {}
end

local function slotRefIsAllowed(model)
    local slotRef = model:GetAttribute("SlotRef")
    if not slotRef then return true end
    local slotNum = tonumber(slotRef:match("Slot(%d+)$"))
    if not slotNum then return true end
    local hasVIP = false
    pcall(function()
        hasVIP = game:GetService("MarketplaceService"):UserOwnsGamePassAsync(LocalPlayer.UserId, 1760093100)
    end)
    return slotNum < 9 or hasVIP
end

local function modelMatchesFilters(model)
    if not slotRefIsAllowed(model) then return false end
    -- [FIX 6] FarmRarityFilters/FarmMutationFilters are arrays; getSelectedFilters returns them as-is
    local selRarities  = getSelectedFilters(S.FarmRarityFilters)
    local selMutations = getSelectedFilters(S.FarmMutationFilters)
    if #selRarities == 0 and #selMutations == 0 then return true end
    local rarity   = model:GetAttribute("Rarity")
    local mutation = model:GetAttribute("Mutation")
    for _, r in ipairs(selRarities)  do if rarity   == r then return true end end
    for _, m in ipairs(selMutations) do
        if m == "Normal" then if mutation == nil then return true end
        elseif mutation == m then return true end
    end
    return false
end

local function findCarryPrompt(model)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Name == "Carry"
        and desc.Parent:IsA("BasePart") and desc.ActionText == "Steal" then
            return desc
        end
    end
    return nil
end

local farmActive = false; local farmTask = nil
local function farmLoop()
    while Amethyst._alive and farmActive do
        safeCall(function()
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not root then adaptiveWait(1) return end

            root.CFrame = CFrame.new(708, 39, -2123)
            adaptiveWait(0.5)

            local valid = {}
            local brainrotFolder = workspace:FindFirstChild("Brainrots")
            if brainrotFolder then
                for _, model in ipairs(brainrotFolder:GetChildren()) do
                    if model:IsA("Model") and modelMatchesFilters(model) then
                        table.insert(valid, model)
                    end
                end
            end

            if #valid == 0 then adaptiveWait(0.9) return end

            local target = valid[math.random(1, #valid)]
            if not target or not target.Parent then adaptiveWait(0.2) return end

            local pivot = target:GetPivot()
            root.CFrame = pivot * CFrame.new(0, 3, 0)
            adaptiveWait(0.3)

            local prompt = findCarryPrompt(target)
            if prompt then
                fireproximityprompt(prompt)
            end
            adaptiveWait(0.3)
            root.CFrame = CFrame.new(739, 39, -2122)
            adaptiveWait(0.9)
        end)
    end
    farmTask = nil
end

-- ============================================================
-- SMART AUTO UPGRADE BRAINROTS (with slot cache)
-- ============================================================
local upgradeBrainrotActive = false; local upgradeBrainTask = nil
local upgradedSlotsCache = {}

local function getMyPlot()
    local plotId = nil
    -- [FIX 9] pcall for safety in case Plots doesn't exist
    pcall(function()
        for i = 1, 5 do
            local plot = workspace.Plots[tostring(i)]
            if plot and plot:FindFirstChild("YourBase") then
                plotId = tostring(i)
                return
            end
        end
    end)
    return plotId
end

local function getSlotInfo(plotId, slot)
    local ok, result = pcall(function()
        local podium = workspace.Plots[plotId].Podiums[tostring(slot)]
        if not podium then return nil end
        local upgradePart = podium:FindFirstChild("Upgrade")
        if not upgradePart then return nil end
        local gui = upgradePart:FindFirstChild("SurfaceGui")
        if not gui then return nil end
        local frame = gui:FindFirstChild("Frame")
        if not frame then return nil end
        local levelChange = frame:FindFirstChild("LevelChange")
        if not levelChange then return nil end
        return tonumber(levelChange.Text:match("Level (%d+)%s*>"))
    end)
    return ok and result or nil
end

local function isSlotFullyUpgraded(plotId, slot, currentLevel, maxLevel)
    if upgradedSlotsCache[plotId] and upgradedSlotsCache[plotId][slot] then return true end
    if currentLevel >= maxLevel then
        if not upgradedSlotsCache[plotId] then upgradedSlotsCache[plotId] = {} end
        upgradedSlotsCache[plotId][slot] = true
        return true
    end
    return false
end

local function upgradeBrainrotLoop()
    while Amethyst._alive and upgradeBrainrotActive do
        safeCall(function()
            local maxLevel = S.MaxUpgradeLevel or 10
            local plotId = getMyPlot()
            if not plotId then adaptiveWait(0.5) return end
            for slot = 1, 30 do
                if not upgradeBrainrotActive then break end
                if upgradedSlotsCache[plotId] and upgradedSlotsCache[plotId][slot] then
                    continue
                end
                local currentLevel = getSlotInfo(plotId, slot)
                if currentLevel then
                    if isSlotFullyUpgraded(plotId, slot, currentLevel, maxLevel) then
                        -- cached, skip
                    elseif currentLevel < maxLevel then
                        safeFireRemote("UpgradeBrainrot", slot)
                        adaptiveWait(0.05)
                    else
                        if not upgradedSlotsCache[plotId] then upgradedSlotsCache[plotId] = {} end
                        upgradedSlotsCache[plotId][slot] = true
                    end
                end
                adaptiveWait(0.05)
            end
            adaptiveWait(0.05)
        end)
    end
    upgradeBrainTask = nil
end

-- ============================================================
-- MISC FEATURES
-- ============================================================

-- Lasers removal
local storedLasers = {}
local function findLasers()
    local found = {}
    -- [FIX 9] pcall for safety if Map.Bases doesn't exist
    pcall(function()
        for _, base in ipairs(workspace.Map.Bases:GetChildren()) do
            local lasers = base:FindFirstChild("LasersModel")
            if lasers then table.insert(found, lasers) end
        end
    end)
    return found
end
local function deleteLasers()
    for _, model in ipairs(findLasers()) do
        if not storedLasers[model] then
            local clone = model:Clone()
            clone.Parent = nil
            storedLasers[model] = {Clone = clone, Parent = model.Parent}
            model:Destroy()
        end
    end
end
local function restoreLasers()
    for _, data in pairs(storedLasers) do
        if data.Clone then data.Clone.Parent = data.Parent end
    end
    storedLasers = {}
end

-- Anti Camera Shake
local savedCFrame = Camera.CFrame
local antiShakeEnabled = false
RunService:BindToRenderStep("AntiShake_Pre", Enum.RenderPriority.Camera.Value, function()
    if antiShakeEnabled then savedCFrame = Camera.CFrame end
end)
RunService:BindToRenderStep("AntiShake_Post", Enum.RenderPriority.Camera.Value + 2, function()
    if antiShakeEnabled then Camera.CFrame = savedCFrame end
end)

-- Freeze Chasing Bosses
local freezeChaseActive = false
local chaseStoredSpeeds = {}
local chaseSpeedConn    = nil
local chaseStopTimer    = nil
local chaseIsShaking    = false
local chaseCameraCF     = Camera.CFrame

local function freezeChaseBosses()
    if chaseSpeedConn then return end
    -- [FIX 9] pcall for safety if Bosses folder doesn't exist
    pcall(function()
        for _, boss in ipairs(workspace.Bosses:GetChildren()) do
            local humanoid = boss:FindFirstChildOfClass("Humanoid")
            if humanoid and not chaseStoredSpeeds[boss] then
                chaseStoredSpeeds[boss] = humanoid.WalkSpeed
                humanoid.WalkSpeed = 0
            end
        end
    end)
    chaseSpeedConn = RunService.Heartbeat:Connect(function()
        pcall(function()
            for _, boss in ipairs(workspace.Bosses:GetChildren()) do
                local humanoid = boss:FindFirstChildOfClass("Humanoid")
                if humanoid then humanoid.WalkSpeed = 0 end
            end
        end)
    end)
end

local function restoreChaseBosses()
    if chaseSpeedConn then chaseSpeedConn:Disconnect(); chaseSpeedConn = nil end
    pcall(function()
        for _, boss in ipairs(workspace.Bosses:GetChildren()) do
            local humanoid = boss:FindFirstChildOfClass("Humanoid")
            if humanoid and chaseStoredSpeeds[boss] then
                humanoid.WalkSpeed = chaseStoredSpeeds[boss]
            end
        end
    end)
    chaseStoredSpeeds = {}
end

local function startShakeDetection()
    RunService:BindToRenderStep("ShakeDetect_Pre", Enum.RenderPriority.Camera.Value, function()
        chaseCameraCF = Camera.CFrame
    end)
    RunService:BindToRenderStep("ShakeDetect_Post", Enum.RenderPriority.Camera.Value + 2, function()
        if not freezeChaseActive then return end
        local posDiff = (Camera.CFrame.Position - chaseCameraCF.Position).Magnitude
        local prevShaking = chaseIsShaking
        chaseIsShaking = posDiff > 0.01
        if chaseIsShaking and not prevShaking then
            if chaseStopTimer then task.cancel(chaseStopTimer); chaseStopTimer = nil end
            freezeChaseBosses()
        elseif not chaseIsShaking and prevShaking then
            if chaseStopTimer then task.cancel(chaseStopTimer) end
            chaseStopTimer = task.delay(3, function() chaseStopTimer = nil; restoreChaseBosses() end)
        end
    end)
end

local function stopShakeDetection()
    RunService:UnbindFromRenderStep("ShakeDetect_Pre")
    RunService:UnbindFromRenderStep("ShakeDetect_Post")
    chaseIsShaking = false
    if chaseStopTimer then task.cancel(chaseStopTimer); chaseStopTimer = nil end
    restoreChaseBosses()
end

-- Freeze Bad Bosses
local badBossStored = {}
local badBossConn   = nil

local function getHighestBaseNumber()
    local highest = -1
    pcall(function()
        for _, boss in ipairs(workspace.Bosses:GetChildren()) do
            local num = tonumber(boss.Name:match("^base(%d+)$"))
            if num and num > highest then highest = num end
        end
    end)
    return highest
end

local function isProtectedModel(boss)
    local highest = getHighestBaseNumber()
    if highest == -1 then return false end
    return boss.Name == "base" .. highest
end

local function freezeBadBosses()
    pcall(function()
        for _, boss in ipairs(workspace.Bosses:GetChildren()) do
            if isProtectedModel(boss) then continue end
            local humanoid = boss:FindFirstChildOfClass("Humanoid")
            if humanoid and not badBossStored[boss] then
                badBossStored[boss] = humanoid.WalkSpeed
                humanoid.WalkSpeed = 0
            end
        end
    end)
end

local function forceBadBossSpeeds()
    badBossConn = RunService.Heartbeat:Connect(function()
        pcall(function()
            for _, boss in ipairs(workspace.Bosses:GetChildren()) do
                if isProtectedModel(boss) then continue end
                local humanoid = boss:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.WalkSpeed ~= 0 then humanoid.WalkSpeed = 0 end
            end
        end)
    end)
end

local function restoreBadBosses()
    if badBossConn then badBossConn:Disconnect(); badBossConn = nil end
    pcall(function()
        for _, boss in ipairs(workspace.Bosses:GetChildren()) do
            local humanoid = boss:FindFirstChildOfClass("Humanoid")
            if humanoid and badBossStored[boss] then
                humanoid.WalkSpeed = badBossStored[boss]
            end
        end
    end)
    badBossStored = {}
end

-- Anti-Staff Detection
local isStaffPresent = false
local function checkForStaff()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if player.MembershipType == Enum.MembershipType.Admin then return true end
        end
    end
    return false
end

local function onStaffJoined()
    if not S.AntiStaff then return end
    isStaffPresent = true
    S.AutoCollect = false; S.AutoRebirth = false; S.AutoSpeedUpgrade = false
    S.AutoEquipBest = false; S.AutoClaimGifts = false; S.AutoUpgradeBase = false
    S.AutoSell = false; S.FarmBrainrot = false; S.AutoUpgradeBrainrots = false
    notify("⚠️ STAFF DETECTED", "All auto features disabled for safety.", 6, "danger")
end

local function onStaffLeft()
    isStaffPresent = false
    notify("Staff Left", "Auto features can be re-enabled manually.", 4, "warning")
end

-- [FIX 8] Track Players connections so they disconnect on cleanup
track(Players.PlayerAdded:Connect(function(player)
    task.wait(2)
    if checkForStaff() then onStaffJoined() end
end))
track(Players.PlayerRemoving:Connect(function()
    if not checkForStaff() and isStaffPresent then onStaffLeft() end
end))
if checkForStaff() then onStaffJoined() end

-- ============================================================
-- LOADING SCREEN ANIMATION
-- ============================================================
task.spawn(function()
    local start = os.clock()
    while Amethyst._alive do
        local elapsed = os.clock() - start
        local pct = math.clamp(elapsed / 2, 0, 1)
        progressFill.Size = UDim2.new(pct, 0, 1, 0)
        percentLabel.Text = math.floor(pct * 100) .. "%"
        if pct >= 1 then break end
        task.wait()
    end
    task.wait(0.2)
    tweenProp(loadingTitle,    {TextTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(loadingSubtitle, {TextTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(progressBg,      {BackgroundTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(progressFill,    {BackgroundTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(percentLabel,    {TextTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(glowRing,        {BackgroundTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(loadingFrame,    {BackgroundTransparency = 1}, TweenInfo.new(0.5))
    task.wait(0.55)
    loadingGui:Destroy()
    mainFrame.Visible = true
    tweenProp(mainFrame, {Size = mainFrame.Size}, TI_BOUNCE)
end)

-- ============================================================
-- TAB UI BUILDING
-- ============================================================

-- FARM TAB
createSection(tabPages.Farm, "Collection")
local collectToggle = createToggle(tabPages.Farm, {Name = "Auto Collect Cash", CurrentValue = S.AutoCollect, Callback = function(v)
    S.AutoCollect = v
    collectActive = v
    if v then if not collectTask then collectTask = task.spawn(collectLoop) end
    else collectTask = nil end
    notifyToggle("Auto Collect", v)
end})
local collectSlider = createSlider(tabPages.Farm, {Name = "Collect Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.CollectInterval, Callback = function(v) S.CollectInterval = v end})

createSection(tabPages.Farm, "Brainrot Farming")
local farmToggle = createToggle(tabPages.Farm, {Name = "Farm Selected Brainrots", CurrentValue = S.FarmBrainrot, Callback = function(v)
    S.FarmBrainrot = v
    farmActive = v
    if v then if not farmTask then farmTask = task.spawn(farmLoop) end
    else farmTask = nil end
    notifyToggle("Farm Brainrots", v)
end})
local rarityOptions = {"Common","Rare","Epic","Legendary","Mythic","Brainrot God","Secret","Divine","MEME","OG"}
local rarityDropdown = createDropdown(tabPages.Farm, {Name = "Rarity Filter", Options = rarityOptions, MultipleOptions = true, CurrentOption = {}, Callback = function(v) S.FarmRarityFilters = v end})
local mutationOptions = {"Normal","Gold","Diamond","Rainbow","Candy"}
local mutationDropdown = createDropdown(tabPages.Farm, {Name = "Mutation Filter", Options = mutationOptions, MultipleOptions = true, CurrentOption = {}, Callback = function(v) S.FarmMutationFilters = v end})

-- UPGRADES TAB
createSection(tabPages.Upgrades, "Rebirth")
local rebirthToggle = createToggle(tabPages.Upgrades, {Name = "Auto Rebirth", CurrentValue = S.AutoRebirth, Callback = function(v)
    S.AutoRebirth = v
    rebirthActive = v
    if v then if not rebirthTask then rebirthTask = task.spawn(rebirthLoop) end
    else rebirthTask = nil end
    notifyToggle("Auto Rebirth", v)
end})
local rebirthSlider = createSlider(tabPages.Upgrades, {Name = "Rebirth Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.RebirthInterval, Callback = function(v) S.RebirthInterval = v end})
createButton(tabPages.Upgrades, {Name = "Rebirth Once", Callback = function() safeFireRemote("RequestRebirth") end})

createSection(tabPages.Upgrades, "Speed Upgrades")
local speedToggle = createToggle(tabPages.Upgrades, {Name = "Auto Upgrade Speed", CurrentValue = S.AutoSpeedUpgrade, Callback = function(v)
    S.AutoSpeedUpgrade = v
    speedUpActive = v
    if v then if not speedUpTask then speedUpTask = task.spawn(speedUpLoop) end
    else speedUpTask = nil end
    notifyToggle("Auto Speed Upgrade", v)
end})
local speedInterval = createSlider(tabPages.Upgrades, {Name = "Upgrade Speed Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.SpeedUpgradeInterval, Callback = function(v) S.SpeedUpgradeInterval = v end})
local speedAmount = createDropdown(tabPages.Upgrades, {Name = "Upgrade Speed Amount", Options = {"1","5","10"}, CurrentOption = tostring(S.SpeedUpgradeAmount), Callback = function(v) S.SpeedUpgradeAmount = tonumber(v) end})

createSection(tabPages.Upgrades, "Base Upgrades")
local baseToggle = createToggle(tabPages.Upgrades, {Name = "Auto Upgrade Base", CurrentValue = S.AutoUpgradeBase, Callback = function(v)
    S.AutoUpgradeBase = v
    baseActive = v
    if v then if not baseTask then baseTask = task.spawn(baseLoop) end
    else baseTask = nil end
    notifyToggle("Auto Upgrade Base", v)
end})
local baseInterval = createSlider(tabPages.Upgrades, {Name = "Upgrade Base Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.UpgradeBaseInterval, Callback = function(v) S.UpgradeBaseInterval = v end})
createButton(tabPages.Upgrades, {Name = "Upgrade Base Once", Callback = function() safeFireRemote("UpgradeBase") end})

createSection(tabPages.Upgrades, "Brainrot Upgrades")
local upgradeToggle = createToggle(tabPages.Upgrades, {Name = "Auto Upgrade Brainrots", CurrentValue = S.AutoUpgradeBrainrots, Callback = function(v)
    S.AutoUpgradeBrainrots = v
    upgradeBrainrotActive = v
    if v then if not upgradeBrainTask then upgradeBrainTask = task.spawn(upgradeBrainrotLoop) end
    else upgradeBrainTask = nil end
    notifyToggle("Auto Upgrade Brainrots", v)
end})
local maxLevelInput = createInput(tabPages.Upgrades, {Name = "Max Upgrade Level", PlaceholderText = "Enter max level...", Callback = function(v) local num = tonumber(v); if num then S.MaxUpgradeLevel = num end end, RemoveTextAfterFocusLost = false})

-- AUTOMATION TAB
createSection(tabPages.Automation, "Best Brainrots")
local equipToggle = createToggle(tabPages.Automation, {Name = "Auto Equip Best Brainrots", CurrentValue = S.AutoEquipBest, Callback = function(v)
    S.AutoEquipBest = v
    equipActive = v
    if v then if not equipTask then equipTask = task.spawn(equipLoop) end
    else equipTask = nil end
    notifyToggle("Auto Equip Best", v)
end})
local equipInterval = createSlider(tabPages.Automation, {Name = "Equip Best Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.EquipBestInterval, Callback = function(v) S.EquipBestInterval = v end})

createSection(tabPages.Automation, "Gifts / Rewards")
local claimToggle = createToggle(tabPages.Automation, {Name = "Auto Claim Free Gifts", CurrentValue = S.AutoClaimGifts, Callback = function(v)
    S.AutoClaimGifts = v
    claimActive = v
    if v then if not claimTask then claimTask = task.spawn(claimLoop) end
    else claimTask = nil end
    notifyToggle("Auto Claim Gifts", v)
end})
local claimInterval = createSlider(tabPages.Automation, {Name = "Claim Gifts Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.ClaimGiftsInterval, Callback = function(v) S.ClaimGiftsInterval = v end})

createSection(tabPages.Automation, "Auto Sell")
local sellToggle = createToggle(tabPages.Automation, {Name = "Enable Auto Sell", CurrentValue = S.AutoSell, Callback = function(v)
    S.AutoSell = v
    sellActive = v
    if v then if not sellTask then sellTask = task.spawn(sellLoop) end
    else sellTask = nil end
    notifyToggle("Auto Sell", v)
end})
local sellIntervalSlider  = createSlider(tabPages.Automation, {Name = "Sell Interval",      Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.SellInterval,  Callback = function(v) S.SellInterval = v end})
local sellThresholdSlider = createSlider(tabPages.Automation, {Name = "Sell Threshold (%)", Range = {0, 100},  Increment = 5,   CurrentValue = S.SellThreshold, Callback = function(v) S.SellThreshold = v end})
local modeDropdown = createDropdown(tabPages.Automation, {Name = "Sell Mode", Options = {"Exclude Selected", "Exclude Non Selected"}, CurrentOption = (S.SellMode == "Exclude" and "Exclude Selected" or "Exclude Non Selected"), Callback = function(v) S.SellMode = (v == "Exclude Selected" and "Exclude" or "Include") end})

local rarityList = {}
for rarity in pairs(RaritiesData) do table.insert(rarityList, rarity) end
table.sort(rarityList)
local rarityExclude = createDropdown(tabPages.Automation, {Name = "Filter Rarities", Options = rarityList, MultipleOptions = true, CurrentOption = {}, Callback = function(v) S.ExcludedRarities = v end})

local mutationList = {"Default"}
for mutation in pairs(MutationsData) do table.insert(mutationList, mutation) end
table.sort(mutationList)
local mutationExclude = createDropdown(tabPages.Automation, {Name = "Filter Mutations", Options = mutationList, MultipleOptions = true, CurrentOption = {}, Callback = function(v) S.ExcludedMutations = v end})

local nameList = {}
for name in pairs(BrainrotsData) do table.insert(nameList, name) end
table.sort(nameList)
if #nameList > 50 then nameList = {table.unpack(nameList, 1, 50)} end
local nameExclude = createDropdown(tabPages.Automation, {Name = "Filter Names", Options = nameList, MultipleOptions = true, CurrentOption = {}, Callback = function(v) S.ExcludedNames = v end})
createButton(tabPages.Automation, {Name = "Sell All (Filters Apply)", Callback = function() safeCall(SellBrainrots) end})

-- MISC TAB
createSection(tabPages.Misc, "Useful")
local lasersToggle = createToggle(tabPages.Misc, {Name = "Remove Laser Doors", CurrentValue = S.LasersRemove, Callback = function(v)
    S.LasersRemove = v
    if v then deleteLasers() else restoreLasers() end
    notifyToggle("Remove Lasers", v)
end})
local antiShakeToggle = createToggle(tabPages.Misc, {Name = "Anti Camera Shake", CurrentValue = S.AntiShake, Callback = function(v)
    S.AntiShake = v
    antiShakeEnabled = v
    notifyToggle("Anti Shake", v)
end})
local chaseToggle = createToggle(tabPages.Misc, {Name = "Freeze Chasing Bosses", CurrentValue = S.FreezeChasingBosses, Callback = function(v)
    S.FreezeChasingBosses = v
    freezeChaseActive = v
    if v then startShakeDetection() else stopShakeDetection() end
    notifyToggle("Freeze Chasing Bosses", v)
end})
local badToggle = createToggle(tabPages.Misc, {Name = "Freeze Bad Bosses", CurrentValue = S.FreezeBadBosses, Callback = function(v)
    S.FreezeBadBosses = v
    if v then freezeBadBosses(); forceBadBossSpeeds() else restoreBadBosses() end
    notifyToggle("Freeze Bad Bosses", v)
end})

-- SETTINGS TAB
createSection(tabPages.Settings, "Configuration")
createButton(tabPages.Settings, {Name = "Save Config",   Callback = function() saveConfig();   notify("Config Saved",   "Settings saved to file.",          3, "success") end})
createButton(tabPages.Settings, {Name = "Load Config",   Callback = function() loadConfig();   notify("Config Loaded",  "Settings loaded from file.",        3, "success") end})
createButton(tabPages.Settings, {Name = "Copy Config to Clipboard",   Callback = copyConfigToClipboard})
createButton(tabPages.Settings, {Name = "Load Config from Clipboard", Callback = loadConfigFromClipboard})
local antiStaffToggle = createToggle(tabPages.Settings, {Name = "Anti-Staff Detection", CurrentValue = S.AntiStaff, Callback = function(v)
    S.AntiStaff = v
    if v and checkForStaff() then onStaffJoined() end
    notifyToggle("Anti-Staff", v)
end})
createButton(tabPages.Settings, {Name = "Reset All Settings", Callback = function()
    for k, v in pairs({
        AutoCollect=false, AutoRebirth=false, AutoSpeedUpgrade=false, AutoEquipBest=false,
        AutoClaimGifts=false, AutoUpgradeBase=false, AutoSell=false, FarmBrainrot=false,
        AutoUpgradeBrainrots=false, LasersRemove=false, AntiShake=false,
        FreezeChasingBosses=false, FreezeBadBosses=false, AntiStaff=false,
        CollectInterval=1, RebirthInterval=1, SpeedUpgradeInterval=1, EquipBestInterval=4,
        ClaimGiftsInterval=1, UpgradeBaseInterval=3, SellInterval=3, SpeedUpgradeAmount=1,
        MaxUpgradeLevel=10, SellThreshold=90, SellMode="Exclude",
        ExcludedRarities={}, ExcludedMutations={}, ExcludedNames={},
        FarmRarityFilters={}, FarmMutationFilters={}
    }) do S[k] = v end
    notify("Reset", "All settings reset to default.", 3, "warning")
end})
createParagraph(tabPages.Settings, {Title = "Amethyst Core V3", Content = "UI Framework v3.0 | Brainrot Script Integration\nFrosted Amethyst Theme\nOptimized: Smart upgrade caching, sell threshold, anti-staff, adaptive delays.\nAll settings auto-save every 30 seconds."})

-- HOME TAB (Live stats)
local homePage = Instance.new("ScrollingFrame")
homePage.Name = "HomePage"
homePage.Size = UDim2.new(1, 0, 1, 0)
homePage.BackgroundTransparency = 1
homePage.ScrollBarThickness = 3
homePage.AutomaticCanvasSize = Enum.AutomaticSize.Y
homePage.CanvasSize = UDim2.new(0, 0, 0, 0)
homePage.Parent = contentArea
local homeLayout = Instance.new("UIListLayout")
homeLayout.Padding = UDim.new(0, 8)
homeLayout.SortOrder = Enum.SortOrder.LayoutOrder
homeLayout.Parent = homePage
local homePadding = Instance.new("UIPadding")
homePadding.PaddingTop    = UDim.new(0, 8)
homePadding.PaddingBottom = UDim.new(0, 8)
homePadding.PaddingLeft   = UDim.new(0, 8)
homePadding.PaddingRight  = UDim.new(0, 8)
homePadding.Parent = homePage
tabPages["Home"] = homePage
table.insert(TAB_NAMES, 1, "Home")

local homeTabBtn = Instance.new("TextButton")
homeTabBtn.Size = UDim2.new(1, -8, 0, 30)
homeTabBtn.BackgroundColor3 = THEME.SidebarBackground
homeTabBtn.Font = Enum.Font.GothamBold
homeTabBtn.TextSize = 11
homeTabBtn.Text = "    Home"
homeTabBtn.TextColor3 = THEME.TextSecondary
homeTabBtn.TextXAlignment = Enum.TextXAlignment.Left
homeTabBtn.AutoButtonColor = false
homeTabBtn.LayoutOrder = 1
homeTabBtn.Parent = sidebar
Instance.new("UICorner", homeTabBtn).CornerRadius = UDim.new(0, 4)
local homePill = Instance.new("Frame")
homePill.Size = UDim2.new(0, 3, 0.6, 0)
homePill.Position = UDim2.new(0, -4, 0.2, 0)
homePill.BackgroundColor3 = THEME.Accent
homePill.Visible = false
homePill.Parent = homeTabBtn
tabButtons["Home"] = {button = homeTabBtn, pill = homePill}
track(homeTabBtn.MouseButton1Click:Connect(function() switchTab("Home") end))
switchTab("Home")

-- Home tab content
createSection(homePage, "Live Stats")
-- [FIX 5] statsPara is now an object with .Set() method
local statsPara = createParagraph(homePage, {Title = "Session Statistics", Content = "Rebirths: 0\nMoney/min: 0\nInventory: 0%"})
createSection(homePage, "Welcome")
createParagraph(homePage, {Title = "Amethyst Brainrot V3", Content = "Optimized auto-farm script with:\n- Smart Auto-Upgrade (caches max slots)\n- Sell threshold (sell only when inventory > X%)\n- Adaptive delays (slows down on lag)\n- Anti-staff detection\n- Config profiles (copy/load JSON)\n- Live stats"})

-- Stats update loop
task.spawn(function()
    while Amethyst._alive do
        updateStats()
        local fillPercent = getInventoryFillPercentage()
        local content = string.format(
            "Rebirths this session: %d\nMoney per minute: %.0f\nInventory fill: %.1f%%",
            sessionRebirths, moneyPerMinute, fillPercent
        )
        -- [FIX 5] Use .Set() method instead of .Content.Text (which was nil)
        if statsPara then
            statsPara.Set(content)
        end
        adaptiveWait(2)
    end
end)

-- ============================================================
-- Sync UI to current S values (after loadConfig)
-- ============================================================
collectToggle.Set(S.AutoCollect);      collectSlider.Set(S.CollectInterval)
farmToggle.Set(S.FarmBrainrot);        rarityDropdown.Set(S.FarmRarityFilters);  mutationDropdown.Set(S.FarmMutationFilters)
rebirthToggle.Set(S.AutoRebirth);      rebirthSlider.Set(S.RebirthInterval)
speedToggle.Set(S.AutoSpeedUpgrade);   speedInterval.Set(S.SpeedUpgradeInterval); speedAmount.Set(tostring(S.SpeedUpgradeAmount))
baseToggle.Set(S.AutoUpgradeBase);     baseInterval.Set(S.UpgradeBaseInterval)
upgradeToggle.Set(S.AutoUpgradeBrainrots); maxLevelInput.Set(tostring(S.MaxUpgradeLevel))
equipToggle.Set(S.AutoEquipBest);      equipInterval.Set(S.EquipBestInterval)
claimToggle.Set(S.AutoClaimGifts);     claimInterval.Set(S.ClaimGiftsInterval)
sellToggle.Set(S.AutoSell);            sellIntervalSlider.Set(S.SellInterval);    sellThresholdSlider.Set(S.SellThreshold)
modeDropdown.Set(S.SellMode == "Exclude" and "Exclude Selected" or "Exclude Non Selected")
rarityExclude.Set(S.ExcludedRarities); mutationExclude.Set(S.ExcludedMutations); nameExclude.Set(S.ExcludedNames)
lasersToggle.Set(S.LasersRemove);      antiShakeToggle.Set(S.AntiShake)
chaseToggle.Set(S.FreezeChasingBosses); badToggle.Set(S.FreezeBadBosses)
antiStaffToggle.Set(S.AntiStaff)

-- Start active features based on loaded state
if S.AutoCollect        then collectActive = true;           collectTask     = task.spawn(collectLoop)          end
if S.AutoRebirth        then rebirthActive = true;           rebirthTask     = task.spawn(rebirthLoop)          end
if S.AutoSpeedUpgrade   then speedUpActive = true;           speedUpTask     = task.spawn(speedUpLoop)          end
if S.AutoEquipBest      then equipActive   = true;           equipTask       = task.spawn(equipLoop)            end
if S.AutoClaimGifts     then claimActive   = true;           claimTask       = task.spawn(claimLoop)            end
if S.AutoUpgradeBase    then baseActive    = true;           baseTask        = task.spawn(baseLoop)             end
if S.AutoSell           then sellActive    = true;           sellTask        = task.spawn(sellLoop)             end
if S.FarmBrainrot       then farmActive    = true;           farmTask        = task.spawn(farmLoop)             end
if S.AutoUpgradeBrainrots then upgradeBrainrotActive = true; upgradeBrainTask = task.spawn(upgradeBrainrotLoop) end
if S.LasersRemove       then deleteLasers() end
if S.AntiShake          then antiShakeEnabled = true end
if S.FreezeChasingBosses then freezeChaseActive = true; startShakeDetection() end
if S.FreezeBadBosses    then freezeBadBosses(); forceBadBossSpeeds() end

-- ============================================================
-- CLEANUP HANDLER
-- ============================================================
Amethyst.cleanup = function()
    Amethyst._alive = false
    -- Stop all active flags
    farmActive = false; collectActive = false; rebirthActive = false; speedUpActive = false
    equipActive = false; claimActive = false; baseActive = false; sellActive = false
    upgradeBrainrotActive = false; freezeChaseActive = false
    -- Cleanup render steps and restore world state
    pcall(function() RunService:UnbindFromRenderStep("AntiShake_Pre") end)
    pcall(function() RunService:UnbindFromRenderStep("AntiShake_Post") end)
    stopShakeDetection()
    restoreBadBosses()
    restoreLasers()
    saveConfig()
    -- [FIX 1] Disconnect all tracked connections
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    -- [FIX 4] Destroy GUIs tagged with __AmethystBrainrotV3 (consistent attribute name)
    for _, gui in ipairs(CoreGui:GetChildren()) do
        if gui:GetAttribute("__AmethystBrainrotV3") then gui:Destroy() end
    end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, gui in ipairs(pg:GetChildren()) do
            if gui:GetAttribute("__AmethystBrainrotV3") then gui:Destroy() end
        end
    end
    _G.__AmethystBrainrotV3 = nil
end

notify("Amethyst Brainrot V3", "Optimized script loaded.\nSmart features: upgrade caching, sell threshold, anti-staff, adaptive delays.", 6, "success")
