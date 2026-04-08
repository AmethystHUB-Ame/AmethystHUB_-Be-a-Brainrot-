--[[
  Amethyst Core Engine (Stripped) + Be a Brainrot Script
  Full UI Migration: Amethyst UI Framework with Brainrot Features
  Frosted Amethyst Theme - No Universal Features
]]

-- DOUBLE EXECUTION GUARD + PREVIOUS INSTANCE CLEANUP
if _G.__AmethystCleanup then
    pcall(_G.__AmethystCleanup)
end
if _G.__AmethystBrainrot then
    warn("[Amethyst Brainrot] Already running.")
    return
end
_G.__AmethystBrainrot = true
local _alive = true

-- ROBUST ERROR HANDLER
local function _safeCall(fn, ...)
    return xpcall(fn, function(err)
        warn("[Amethyst Error]: " .. tostring(err) .. "\n" .. debug.traceback())
    end, ...)
end

-- Feature connection tracking
local _featureConns = {}
local function trackFeatureConn(name, conn)
    if _featureConns[name] then
        pcall(function() _featureConns[name]:Disconnect() end)
    end
    _featureConns[name] = conn
end

-- Constants
local CONST = {
    NOTIFICATION_MAX_QUEUE = 10,
    CONFIG_AUTOSAVE_INTERVAL = 30,
}

-- SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Brainrot specific modules (from original script)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerState = require(ReplicatedStorage.Libraries.PlayerState.PlayerStateClient)
local BrainrotsData = require(ReplicatedStorage.Database.BrainrotsData)
local RaritiesData = require(ReplicatedStorage.Database.RaritiesData)
local MutationsData = require(ReplicatedStorage.Database.MutationsData)

repeat task.wait() until PlayerState.IsReady()
local function GetData(path)
    return PlayerState.GetPath(path)
end

-- ============================================================
-- CENTRAL STATE TABLE S (Brainrot features)
-- ============================================================
local S = {
    -- Farm tab
    AutoCollect = false,
    CollectInterval = 1,
    FarmBrainrot = false,
    FarmRarityFilters = {},
    FarmMutationFilters = {},
    
    -- Upgrades tab
    AutoRebirth = false,
    RebirthInterval = 1,
    AutoSpeedUpgrade = false,
    SpeedUpgradeInterval = 1,
    SpeedUpgradeAmount = 1,
    AutoUpgradeBase = false,
    UpgradeBaseInterval = 3,
    AutoUpgradeBrainrots = false,
    MaxUpgradeLevel = 10,
    
    -- Automation tab
    AutoEquipBest = false,
    EquipBestInterval = 4,
    AutoClaimGifts = false,
    ClaimGiftsInterval = 1,
    AutoSell = false,
    SellInterval = 3,
    SellMode = "Exclude", -- "Exclude" or "Include"
    ExcludedRarities = {},
    ExcludedMutations = {},
    ExcludedNames = {},
    
    -- Misc tab
    LasersRemove = false,
    AntiShake = false,
    FreezeChasingBosses = false,
    FreezeBadBosses = false,
}

-- Categories for save/load
local _S_categories = { Brainrot = S }
setmetatable(S, {
    __newindex = function(t, k, v)
        rawset(t, k, v)
        for _, cat in pairs(_S_categories) do
            if rawget(cat, k) ~= nil then
                cat[k] = v
                return
            end
        end
    end,
})

-- ============================================================
-- CONNECTION TRACKING + DRAWING CLEANUP (minimal for Brainrot)
-- ============================================================
local _connections = {}
local _drawingCleanup = {}

local function track(conn)
    _connections[#_connections + 1] = conn
    return conn
end

local function cleanupAll()
    _alive = false
    for name, conn in pairs(_featureConns) do
        pcall(function() conn:Disconnect() end)
    end
    _featureConns = {}
    for _, c in ipairs(_connections) do
        _safeCall(function() c:Disconnect() end)
    end
    _connections = {}
    for _, d in ipairs(_drawingCleanup) do
        _safeCall(function() d:Remove() end)
    end
    _drawingCleanup = {}
    _safeCall(function()
        for _, gui in ipairs(CoreGui:GetChildren()) do
            if gui:GetAttribute("__AmethystV4") or gui.Name:find("Amethyst") then
                gui:Destroy()
            end
        end
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, gui in ipairs(pg:GetChildren()) do
                if gui.Name:find("Amethyst") then
                    gui:Destroy()
                end
            end
        end
    end)
    _G.__AmethystBrainrot = nil
end

-- ============================================================
-- SAVE/LOAD SYSTEM (JSON)
-- ============================================================
local CONFIG_FILE = "AmethystBrainrot_Config.json"

local function saveConfig()
    _safeCall(function()
        if not writefile then return end
        local data = {}
        for cat, tbl in pairs(_S_categories) do
            data[cat] = {}
            for k, v in pairs(tbl) do
                if type(v) ~= "function" and type(v) ~= "table" then
                    data[cat][k] = v
                elseif type(v) == "table" then
                    -- serialize simple tables (filters)
                    data[cat][k] = v
                end
            end
        end
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadConfig()
    _safeCall(function()
        if not readfile or not isfile then return end
        if not isfile(CONFIG_FILE) then return end
        local raw = readfile(CONFIG_FILE)
        if not raw or raw == "" then return end
        local ok, data = _safeCall(function() return HttpService:JSONDecode(raw) end)
        if not ok or not data then return end
        for cat, tbl in pairs(data) do
            local target = _S_categories[cat]
            if target then
                for k, v in pairs(tbl) do
                    if rawget(target, k) ~= nil then
                        target[k] = v
                        S[k] = v
                    end
                end
            end
        end
    end)
end

task.spawn(function()
    while _alive do
        task.wait(CONST.CONFIG_AUTOSAVE_INTERVAL)
        pcall(saveConfig)
    end
end)

-- ============================================================
-- THEME CONSTANTS (Frosted Amethyst)
-- ============================================================
local THEME = {
    Background         = Color3.fromRGB(13, 11, 20),
    Surface            = Color3.fromRGB(22, 18, 31),
    SurfaceElevated    = Color3.fromRGB(30, 26, 42),
    Border             = Color3.fromRGB(42, 36, 64),
    Accent             = Color3.fromRGB(155, 89, 240),
    AccentGlow         = Color3.fromRGB(180, 122, 255),
    AccentSecondary    = Color3.fromRGB(108, 61, 207),
    TextPrimary        = Color3.fromRGB(238, 234, 245),
    TextSecondary      = Color3.fromRGB(139, 131, 158),
    Success            = Color3.fromRGB(74, 222, 128),
    Danger             = Color3.fromRGB(248, 113, 113),
    Warning            = Color3.fromRGB(251, 191, 36),
    White              = Color3.fromRGB(255, 255, 255),
    ElementBackground  = Color3.fromRGB(22, 18, 31),
    ElementBackgroundHover = Color3.fromRGB(30, 26, 42),
    ElementStroke      = Color3.fromRGB(42, 36, 64),
    SliderBackground   = Color3.fromRGB(22, 18, 31),
    SliderProgress     = Color3.fromRGB(155, 89, 240),
    ToggleEnabled      = Color3.fromRGB(155, 89, 240),
    ToggleDisabled     = Color3.fromRGB(30, 26, 42),
    InputBackground    = Color3.fromRGB(18, 15, 26),
    InputStroke        = Color3.fromRGB(42, 36, 64),
    PlaceholderColor   = Color3.fromRGB(100, 90, 130),
    WindowBackground   = Color3.fromRGB(13, 11, 20),
    Topbar             = Color3.fromRGB(18, 15, 26),
    SidebarBackground  = Color3.fromRGB(16, 13, 24),
    SidebarHover       = Color3.fromRGB(25, 22, 36),
    ContentBackground  = Color3.fromRGB(13, 11, 20),
    LoadingBackground  = Color3.fromRGB(8, 6, 14),
    LoadingBarBackground = Color3.fromRGB(30, 26, 42),
    LoadingBarFill     = Color3.fromRGB(155, 89, 240),
}

-- Tween presets
local TI_SMOOTH  = TweenInfo.new(0.30, Enum.EasingStyle.Quint,  Enum.EasingDirection.Out)
local TI_FAST    = TweenInfo.new(0.10, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)
local TI_PULSE   = TweenInfo.new(1.50, Enum.EasingStyle.Sine,   Enum.EasingDirection.InOut, -1, true)
local TI_BOUNCE  = TweenInfo.new(0.20, Enum.EasingStyle.Back,   Enum.EasingDirection.Out)
local TI_NOTIF   = TweenInfo.new(0.25, Enum.EasingStyle.Cubic,  Enum.EasingDirection.Out)
local TI_TAB     = TweenInfo.new(0.15, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)
local TI_DROP    = TweenInfo.new(0.15, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)

local function tweenProp(obj, props, tweenInfo)
    _safeCall(function()
        TweenService:Create(obj, tweenInfo or TI_SMOOTH, props):Play()
    end)
end

-- ============================================================
-- NOTIFICATION SYSTEM
-- ============================================================
local notifGui = Instance.new("ScreenGui")
notifGui.Name = "AmethystNotifs"
notifGui:SetAttribute("__AmethystV4", true)
notifGui.ResetOnSpawn = false
pcall(function() notifGui.Parent = CoreGui end)

local notifContainer = Instance.new("Frame")
notifContainer.Size = UDim2.new(0, 280, 1, -20)
notifContainer.Position = UDim2.new(1, -290, 0, 10)
notifContainer.BackgroundTransparency = 1
notifContainer.Parent = notifGui

local notifLayout = Instance.new("UIListLayout")
notifLayout.Padding = UDim.new(0, 6)
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.Parent = notifContainer

local notifQueue = {}
local MAX_VISIBLE_NOTIFS = 4

local function processNotifQueue()
    local visible = 0
    for _, child in ipairs(notifContainer:GetChildren()) do
        if child:IsA("Frame") and child.Name == "Notification" then
            visible = visible + 1
        end
    end
    while visible < MAX_VISIBLE_NOTIFS and #notifQueue > 0 do
        local data = table.remove(notifQueue, 1)
        data.show()
        visible = visible + 1
    end
end

local function notify(title, content, dur, severity)
    dur = dur or 4
    local severityColor = THEME.Accent
    if severity == "success" then severityColor = THEME.Success
    elseif severity == "danger" then severityColor = THEME.Danger
    elseif severity == "warning" then severityColor = THEME.Warning end

    local function doShow()
        local contentHeight = content and (math.ceil(#content / 34) * 16) or 0
        local totalHeight = 12 + 18 + (contentHeight > 0 and (4 + contentHeight) or 0) + 10 + 2
        local notifFrame = Instance.new("Frame")
        notifFrame.Name = "Notification"
        notifFrame.Size = UDim2.new(0, 270, 0, math.max(totalHeight, 50))
        notifFrame.BackgroundColor3 = THEME.Surface
        notifFrame.BackgroundTransparency = 0.2
        notifFrame.BorderSizePixel = 0
        notifFrame.ClipsDescendants = true
        notifFrame.Parent = notifContainer
        Instance.new("UICorner", notifFrame).CornerRadius = UDim.new(0, 8)
        local strip = Instance.new("Frame")
        strip.Size = UDim2.new(0, 4, 1, -8)
        strip.Position = UDim2.new(0, 0, 0, 4)
        strip.BackgroundColor3 = severityColor
        strip.BorderSizePixel = 0
        strip.Parent = notifFrame
        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -20, 0, 18)
        titleLabel.Position = UDim2.new(0, 14, 0, 8)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextSize = 13
        titleLabel.Text = "◆ " .. (title or "Amethyst")
        titleLabel.TextColor3 = THEME.TextPrimary
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Parent = notifFrame
        if content and content ~= "" then
            local contentLabel = Instance.new("TextLabel")
            contentLabel.Size = UDim2.new(1, -20, 0, contentHeight)
            contentLabel.Position = UDim2.new(0, 14, 0, 28)
            contentLabel.BackgroundTransparency = 1
            contentLabel.Font = Enum.Font.Gotham
            contentLabel.TextSize = 12
            contentLabel.Text = content
            contentLabel.TextColor3 = THEME.TextSecondary
            contentLabel.TextWrapped = true
            contentLabel.Parent = notifFrame
        end
        local progressBar = Instance.new("Frame")
        progressBar.Size = UDim2.new(1, -16, 0, 2)
        progressBar.Position = UDim2.new(0, 8, 1, -6)
        progressBar.BackgroundColor3 = severityColor
        progressBar.BorderSizePixel = 0
        progressBar.Parent = notifFrame
        notifFrame.Position = UDim2.new(0, 290, 0, 0)
        tweenProp(notifFrame, {Position = UDim2.new(0, 0, 0, 0)}, TI_NOTIF)
        local durationTI = TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
        tweenProp(progressBar, {Size = UDim2.new(0, 0, 0, 2)}, durationTI)
        task.delay(dur, function()
            tweenProp(notifFrame, {Position = UDim2.new(0, 290, 0, 0), BackgroundTransparency = 1}, TweenInfo.new(0.3))
            task.delay(0.35, function() _safeCall(function() notifFrame:Destroy(); processNotifQueue() end) end)
        end)
    end

    local visible = 0
    for _, child in ipairs(notifContainer:GetChildren()) do
        if child:IsA("Frame") and child.Name == "Notification" then visible = visible + 1 end
    end
    if visible < MAX_VISIBLE_NOTIFS then doShow()
    else
        if #notifQueue >= CONST.NOTIFICATION_MAX_QUEUE then table.remove(notifQueue, 1) end
        table.insert(notifQueue, {show = doShow})
    end
end

local function notifyToggle(name, state)
    notify(name .. (state and " ON" or " OFF"), state and "Enabled" or "Disabled", 3)
end

-- ============================================================
-- UI FRAMEWORK (Amethyst Core)
-- ============================================================
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function createScreenGui(name, displayOrder)
    local gui = Instance.new("ScreenGui")
    gui.Name = "SG_" .. HttpService:GenerateGUID(false)
    gui:SetAttribute("__AmethystV4", true)
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
glowRing.BorderSizePixel = 0
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
loadingSubtitle.Text = "Powered by Amethyst Core"
loadingSubtitle.TextColor3 = THEME.TextSecondary
loadingSubtitle.Parent = loadingFrame
local progressBg = Instance.new("Frame")
progressBg.Size = UDim2.new(0, 220, 0, 3)
progressBg.Position = UDim2.new(0.5, 0, 0.5, 40)
progressBg.AnchorPoint = Vector2.new(0.5, 0.5)
progressBg.BackgroundColor3 = THEME.LoadingBarBackground
progressBg.BorderSizePixel = 0
progressBg.Parent = loadingFrame
local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = THEME.LoadingBarFill
progressFill.BorderSizePixel = 0
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

task.spawn(function()
    local loadStart = os.clock()
    while _alive do
        local elapsed = os.clock() - loadStart
        local pct = math.clamp(elapsed / 2, 0, 1)
        progressFill.Size = UDim2.new(pct, 0, 1, 0)
        percentLabel.Text = math.floor(pct * 100) .. "%"
        if pct >= 1 then break end
        task.wait()
    end
    task.wait(0.2)
    tweenProp(loadingTitle, {TextTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(loadingSubtitle, {TextTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(progressBg, {BackgroundTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(progressFill, {BackgroundTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(percentLabel, {TextTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(glowRing, {BackgroundTransparency = 1}, TweenInfo.new(0.5))
    tweenProp(loadingFrame, {BackgroundTransparency = 1}, TweenInfo.new(0.5))
    task.wait(0.55)
    loadingGui:Destroy()
    mainFrame.Visible = true
    tweenProp(mainFrame, {Size = mainFrame.Size}, TI_BOUNCE)
end)

-- Main Hub Window
local hubGui = createScreenGui("AmethystHub", 10)
local panelWidth = IS_MOBILE and UDim2.new(0.92, 0, 0.7, 0) or UDim2.new(0, 520, 0, 380)
local sidebarWidth = IS_MOBILE and 110 or 130
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
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
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame
local topBarTitle = Instance.new("TextLabel")
topBarTitle.Size = UDim2.new(1, -80, 1, 0)
topBarTitle.Position = UDim2.new(0, 12, 0, 0)
topBarTitle.BackgroundTransparency = 1
topBarTitle.Font = Enum.Font.GothamBold
topBarTitle.TextSize = 13
topBarTitle.Text = "◆ Be a Brainrot  |  Amethyst"
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
    tweenProp(mainFrame, {Size = isMinimized and UDim2.new(mainFrame.Size.X.Scale, mainFrame.Size.X.Offset, 0, 36) or panelWidth}, TI_SMOOTH)
end))

-- Dragging
local dragging = false
local dragInput, dragStart, startPos
track(topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end))
track(UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end))

-- Sidebar
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, sidebarWidth, 1, -36)
sidebar.Position = UDim2.new(0, 0, 0, 36)
sidebar.BackgroundColor3 = THEME.SidebarBackground
sidebar.BorderSizePixel = 0
sidebar.Parent = mainFrame
local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.Padding = UDim.new(0, 3)
sidebarLayout.Parent = sidebar

-- Content area
local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -sidebarWidth, 1, -36)
contentArea.Position = UDim2.new(0, sidebarWidth, 0, 36)
contentArea.BackgroundColor3 = THEME.ContentBackground
contentArea.BorderSizePixel = 0
contentArea.ClipsDescendants = true
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
    pagePadding.PaddingTop = UDim.new(0, 8)
    pagePadding.PaddingBottom = UDim.new(0, 8)
    pagePadding.PaddingLeft = UDim.new(0, 8)
    pagePadding.PaddingRight = UDim.new(0, 8)
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
        tweenProp(btnData.button, {BackgroundColor3 = isSelected and THEME.SurfaceElevated or THEME.SidebarBackground}, TI_TAB)
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
    pill.BorderSizePixel = 0
    pill.Visible = (i == 1)
    pill.Parent = tabBtn
    tabButtons[tabName] = {button = tabBtn, pill = pill}
    track(tabBtn.MouseButton1Click:Connect(function() switchTab(tabName) end))
end

-- Component factories
local function createSection(parent, text)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 28)
    container.BackgroundTransparency = 1
    container.Parent = parent
    local leftLine = Instance.new("Frame")
    leftLine.Size = UDim2.new(0.35, 0, 0, 1)
    leftLine.Position = UDim2.new(0, 0, 0.5, 0)
    leftLine.AnchorPoint = Vector2.new(0, 0.5)
    leftLine.BackgroundColor3 = THEME.Border
    leftLine.Parent = container
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.3, 0, 1, 0)
    label.Position = UDim2.new(0.35, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.Text = text
    label.TextColor3 = THEME.Accent
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Parent = container
    local rightLine = Instance.new("Frame")
    rightLine.Size = UDim2.new(0.35, 0, 0, 1)
    rightLine.Position = UDim2.new(0.65, 0, 0.5, 0)
    rightLine.AnchorPoint = Vector2.new(0, 0.5)
    rightLine.BackgroundColor3 = THEME.Border
    rightLine.Parent = container
    return container
end

local function createToggle(parent, config)
    local toggled = config.CurrentValue or false
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = THEME.ElementBackground
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.Text = config.Name or "Toggle"
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
    local clickBtn = Instance.new("TextButton")
    clickBtn.Size = UDim2.new(1, 0, 1, 0)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text = ""
    clickBtn.Parent = row
    local function updateVisual()
        tweenProp(trackFrame, {BackgroundColor3 = toggled and THEME.ToggleEnabled or THEME.ToggleDisabled}, TI_BOUNCE)
        tweenProp(knob, {Position = toggled and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)}, TI_BOUNCE)
    end
    track(clickBtn.MouseButton1Click:Connect(function()
        toggled = not toggled
        updateVisual()
        _safeCall(config.Callback, toggled)
    end))
    return {Set = function(v) toggled = v; updateVisual() end, Get = function() return toggled end}
end

local function createSlider(parent, config)
    local minVal = config.Range[1] or 0
    local maxVal = config.Range[2] or 100
    local inc = config.Increment or 1
    local currentValue = config.CurrentValue or minVal
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3 = THEME.ElementBackground
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 0, 20)
    label.Position = UDim2.new(0, 12, 0, 6)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.Text = config.Name or "Slider"
    label.TextColor3 = THEME.TextPrimary
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(0.3, -12, 0, 20)
    valueLabel.Position = UDim2.new(0.7, 0, 0, 6)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextSize = 12
    valueLabel.Text = tostring(currentValue)
    valueLabel.TextColor3 = THEME.Accent
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = row
    local sliderTrack = Instance.new("Frame")
    sliderTrack.Size = UDim2.new(1, -24, 0, 4)
    sliderTrack.Position = UDim2.new(0, 12, 0, 36)
    sliderTrack.BackgroundColor3 = THEME.SliderBackground
    sliderTrack.BorderSizePixel = 0
    sliderTrack.Parent = row
    Instance.new("UICorner", sliderTrack).CornerRadius = UDim.new(1, 0)
    local fillPercent = (currentValue - minVal) / math.max(maxVal - minVal, 0.001)
    local sliderFill = Instance.new("Frame")
    sliderFill.Size = UDim2.new(fillPercent, 0, 1, 0)
    sliderFill.BackgroundColor3 = THEME.Accent
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderTrack
    local thumb = Instance.new("Frame")
    thumb.Size = UDim2.new(0, 12, 0, 12)
    thumb.Position = UDim2.new(fillPercent, -6, 0.5, 0)
    thumb.AnchorPoint = Vector2.new(0, 0.5)
    thumb.BackgroundColor3 = THEME.Accent
    thumb.BorderSizePixel = 0
    thumb.Parent = sliderTrack
    Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)
    local sliderInput = Instance.new("TextButton")
    sliderInput.Size = UDim2.new(1, 0, 0, 20)
    sliderInput.Position = UDim2.new(0, 0, 0.5, 0)
    sliderInput.AnchorPoint = Vector2.new(0, 0.5)
    sliderInput.BackgroundTransparency = 1
    sliderInput.Text = ""
    sliderInput.Parent = sliderTrack
    local function updateSlider(pct)
        pct = math.clamp(pct, 0, 1)
        local range = maxVal - minVal
        local raw = minVal + (range * pct)
        if inc >= 1 then currentValue = math.floor(raw / inc + 0.5) * inc
        else currentValue = tonumber(string.format("%." .. math.max(0, math.ceil(-math.log10(inc))) .. "f", raw)) end
        currentValue = math.clamp(currentValue, minVal, maxVal)
        local newPct = (currentValue - minVal) / math.max(range, 0.001)
        sliderFill.Size = UDim2.new(newPct, 0, 1, 0)
        thumb.Position = UDim2.new(newPct, -6, 0.5, 0)
        valueLabel.Text = tostring(currentValue)
    end
    local dragging = false
    track(sliderInput.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local trackAbsPos = sliderTrack.AbsolutePosition.X
            local trackAbsSize = sliderTrack.AbsoluteSize.X
            local pct = math.clamp((input.Position.X - trackAbsPos) / trackAbsSize, 0, 1)
            updateSlider(pct)
            _safeCall(config.Callback, currentValue)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local trackAbsPos = sliderTrack.AbsolutePosition.X
            local trackAbsSize = sliderTrack.AbsoluteSize.X
            local pct = math.clamp((input.Position.X - trackAbsPos) / trackAbsSize, 0, 1)
            updateSlider(pct)
            _safeCall(config.Callback, currentValue)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    return {Set = function(val) currentValue = math.clamp(val, minVal, maxVal); updateSlider((currentValue - minVal) / math.max(maxVal - minVal, 0.001)) end, Get = function() return currentValue end}
end

local function createButton(parent, config)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = THEME.ElementBackground
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Text = config.Name or "Button"
    btn.TextColor3 = THEME.Accent
    btn.AutoButtonColor = false
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    track(btn.MouseButton1Click:Connect(function()
        tweenProp(btn, {Size = UDim2.new(1, -4, 0, 34)}, TweenInfo.new(0.08))
        task.delay(0.08, function() tweenProp(btn, {Size = UDim2.new(1, 0, 0, 36)}, TI_FAST) end)
        _safeCall(config.Callback)
    end))
    return btn
end

local function createDropdown(parent, config)
    local options = config.Options or {}
    local multi = config.MultipleOptions or false
    local selected = {}
    if multi and type(config.CurrentOption) == "table" then for _, v in ipairs(config.CurrentOption) do selected[v] = true end
    elseif config.CurrentOption then selected[config.CurrentOption] = true end
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
    local optionsContainer = Instance.new("Frame")
    optionsContainer.Size = UDim2.new(1, 0, 0, 0)
    optionsContainer.Position = UDim2.new(0, 0, 0, 40)
    optionsContainer.BackgroundColor3 = THEME.Surface
    optionsContainer.BorderSizePixel = 0
    optionsContainer.ClipsDescendants = true
    optionsContainer.Visible = false
    optionsContainer.Parent = container
    Instance.new("UICorner", optionsContainer).CornerRadius = UDim.new(0, 6)
    local optionsLayout = Instance.new("UIListLayout")
    optionsLayout.Padding = UDim.new(0, 1)
    optionsLayout.Parent = optionsContainer
    local function getSelectedText()
        local sel = {}
        for _, opt in ipairs(options) do if selected[opt] then table.insert(sel, opt) end end
        if #sel == 0 then return config.Name or "Select..." end
        return config.Name .. ": " .. table.concat(sel, ", ")
    end
    header.Text = getSelectedText()
    local optionButtons = {}
    local function refreshOptions()
        for _, btn in ipairs(optionButtons) do btn:Destroy() end
        optionButtons = {}
        for i, opt in ipairs(options) do
            local optBtn = Instance.new("TextButton")
            optBtn.Size = UDim2.new(1, -8, 0, 28)
            optBtn.Position = UDim2.new(0, 4, 0, 0)
            optBtn.BackgroundColor3 = selected[opt] and THEME.SurfaceElevated or THEME.Surface
            optBtn.BackgroundTransparency = selected[opt] and 0 or 0.5
            optBtn.Font = Enum.Font.Gotham
            optBtn.TextSize = 11
            optBtn.Text = (selected[opt] and "  ● " or "    ") .. opt
            optBtn.TextColor3 = selected[opt] and THEME.TextPrimary or THEME.TextSecondary
            optBtn.TextXAlignment = Enum.TextXAlignment.Left
            optBtn.AutoButtonColor = false
            optBtn.LayoutOrder = i
            optBtn.Parent = optionsContainer
            Instance.new("UICorner", optBtn).CornerRadius = UDim.new(0, 4)
            track(optBtn.MouseButton1Click:Connect(function()
                if multi then
                    selected[opt] = not selected[opt]
                else
                    selected = {}; selected[opt] = true
                end
                header.Text = getSelectedText()
                refreshOptions()
                if multi then
                    local result = {}
                    for _, o in ipairs(options) do if selected[o] then table.insert(result, o) end end
                    _safeCall(config.Callback, result)
                else
                    _safeCall(config.Callback, opt)
                    if not multi then
                        optionsContainer.Visible = false
                        container.Size = UDim2.new(1, 0, 0, 38)
                        arrow.Text = "▼"
                    end
                end
            end))
            table.insert(optionButtons, optBtn)
        end
    end
    refreshOptions()
    local isOpen = false
    track(header.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        if isOpen then
            arrow.Text = "▲"
            optionsContainer.Visible = true
            local totalHeight = (#options * 29) + 8
            tweenProp(optionsContainer, {Size = UDim2.new(1, 0, 0, totalHeight)}, TI_DROP)
            container.Size = UDim2.new(1, 0, 0, 38 + 2 + totalHeight)
        else
            arrow.Text = "▼"
            tweenProp(optionsContainer, {Size = UDim2.new(1, 0, 0, 0)}, TI_DROP)
            task.delay(0.15, function() optionsContainer.Visible = false; container.Size = UDim2.new(1, 0, 0, 38) end)
        end
    end))
    return {Set = function(val)
        if multi and type(val) == "table" then selected = {}; for _, v in ipairs(val) do selected[v] = true end
        elseif type(val) == "string" then selected = {[val] = true} end
        header.Text = getSelectedText()
        refreshOptions()
    end, Get = function()
        if multi then local r = {}; for _, o in ipairs(options) do if selected[o] then table.insert(r, o) end end; return r
        else for _, o in ipairs(options) do if selected[o] then return o end end; return nil end
    end}
end

local function createInput(parent, config)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = THEME.ElementBackground
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.4, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.Text = config.Name or "Input"
    label.TextColor3 = THEME.TextPrimary
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row
    local inputBox = Instance.new("TextBox")
    inputBox.Size = UDim2.new(0.55, -12, 0, 26)
    inputBox.Position = UDim2.new(0.45, 0, 0.5, 0)
    inputBox.AnchorPoint = Vector2.new(0, 0.5)
    inputBox.BackgroundColor3 = THEME.InputBackground
    inputBox.Font = Enum.Font.Gotham
    inputBox.TextSize = 12
    inputBox.Text = ""
    inputBox.PlaceholderText = config.PlaceholderText or "Type..."
    inputBox.PlaceholderColor3 = THEME.PlaceholderColor
    inputBox.TextColor3 = THEME.TextPrimary
    inputBox.ClearTextOnFocus = false
    inputBox.Parent = row
    Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 4)
    track(inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            _safeCall(config.Callback, inputBox.Text)
            if config.RemoveTextAfterFocusLost then inputBox.Text = "" end
        end
    end))
    return {Set = function(val) inputBox.Text = tostring(val or "") end, Get = function() return inputBox.Text end}
end

local function createParagraph(parent, config)
    local title = config.Title or "Info"
    local content = config.Content or ""
    local contentLines = math.ceil(#content / 50)
    local height = 28 + math.max(contentLines * 16, 20) + 12
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, height)
    frame.BackgroundColor3 = THEME.ElementBackground
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -16, 0, 22)
    titleLabel.Position = UDim2.new(0, 8, 0, 6)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 13
    titleLabel.Text = title
    titleLabel.TextColor3 = THEME.Accent
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = frame
    local contentLabel = Instance.new("TextLabel")
    contentLabel.Size = UDim2.new(1, -16, 0, height - 34)
    contentLabel.Position = UDim2.new(0, 8, 0, 28)
    contentLabel.BackgroundTransparency = 1
    contentLabel.Font = Enum.Font.Gotham
    contentLabel.TextSize = 12
    contentLabel.Text = content
    contentLabel.TextColor3 = THEME.TextSecondary
    contentLabel.TextWrapped = true
    contentLabel.Parent = frame
    return frame
end

-- Watermark
local watermarkGui = createScreenGui("AmethystWatermark", 999)
local wmPill = Instance.new("Frame")
wmPill.Size = UDim2.new(0, 250, 0, 28)
wmPill.Position = UDim2.new(0, 10, 1, -38)
wmPill.BackgroundColor3 = THEME.Surface
wmPill.BackgroundTransparency = 0.25
wmPill.BorderSizePixel = 0
wmPill.Parent = watermarkGui
Instance.new("UICorner", wmPill).CornerRadius = UDim.new(0, 14)
local wmText = Instance.new("TextLabel")
wmText.Size = UDim2.new(1, -20, 1, 0)
wmText.Position = UDim2.new(0, 18, 0, 0)
wmText.BackgroundTransparency = 1
wmText.Font = Enum.Font.Gotham
wmText.TextSize = 12
wmText.TextColor3 = THEME.TextPrimary
wmText.Text = "Be a Brainrot  |  Amethyst Core"
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
toggleGlow.BorderSizePixel = 0
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

-- Original functions from Brainrot script
local function CollectCash()
    for slot = 1, 20 do
        task.spawn(function() _safeCall(function() Remotes.CollectCash:Fire(slot) end) end)
        task.wait(0.1)
    end
end

local function Rebirth()
    _safeCall(function() Remotes.RequestRebirth:Fire() end)
end

local function SpeedUpgrade(amount)
    _safeCall(function() Remotes.SpeedUpgrade:Fire(amount) end)
end

local function EquipBestBrainrots()
    _safeCall(function() Remotes.EquipBestBrainrots:Fire() end)
end

local function ClaimGifts()
    for i = 1, 9 do
        task.spawn(function() _safeCall(function() Remotes.ClaimGift:Fire(i) end) end)
        task.wait(0.5)
    end
end

local function UpgradeBase()
    _safeCall(function() Remotes.UpgradeBase:Fire() end)
end

local function SellBrainrots()
    local stored = GetData("StoredBrainrots") or {}
    for slotKey, brainrot in pairs(stored) do
        local index = brainrot.Index
        local mutation = brainrot.Mutation or "Default"
        local data = BrainrotsData[index]
        if data then
            local name = index
            local rarity = data.Rarity
            local isExcluded = false
            if S.ExcludedRarities[rarity] then isExcluded = true end
            if not isExcluded and S.ExcludedMutations[mutation] then isExcluded = true end
            if not isExcluded and S.ExcludedNames[name] then isExcluded = true end
            if (S.SellMode == "Exclude" and not isExcluded) or (S.SellMode == "Include" and isExcluded) then
                task.spawn(function() _safeCall(function() Remotes.SellThis:Fire(slotKey) end) end)
                task.wait(0.1)
            end
        end
    end
end

-- Auto loops
task.spawn(function()
    while _alive do
        if S.AutoCollect then _safeCall(CollectCash) end
        task.wait(S.CollectInterval)
    end
end)

task.spawn(function()
    while _alive do
        if S.AutoRebirth then
            local speed = GetData("Speed") or 0
            local rebirths = GetData("Rebirths") or 0
            local nextCost = 40 + rebirths * 10
            if speed >= nextCost then _safeCall(Rebirth) end
        end
        task.wait(S.RebirthInterval)
    end
end)

task.spawn(function()
    while _alive do
        if S.AutoSpeedUpgrade then _safeCall(function() SpeedUpgrade(S.SpeedUpgradeAmount) end) end
        task.wait(S.SpeedUpgradeInterval)
    end
end)

task.spawn(function()
    while _alive do
        if S.AutoEquipBest then _safeCall(EquipBestBrainrots) end
        task.wait(S.EquipBestInterval)
    end
end)

task.spawn(function()
    while _alive do
        if S.AutoClaimGifts then _safeCall(ClaimGifts) end
        task.wait(S.ClaimGiftsInterval)
    end
end)

task.spawn(function()
    while _alive do
        if S.AutoUpgradeBase then _safeCall(UpgradeBase) end
        task.wait(S.UpgradeBaseInterval)
    end
end)

task.spawn(function()
    while _alive do
        if S.AutoSell then _safeCall(SellBrainrots) end
        task.wait(S.SellInterval)
    end
end)

-- Farm Brainrots (teleport and steal)
local function getSelectedFilters(optValue)
    local t = {}
    for v, state in pairs(optValue) do
        if state then table.insert(t, v) end
    end
    return t
end

local function slotRefIsAllowed(model)
    local slotRef = model:GetAttribute("SlotRef")
    if slotRef == nil then return true end
    local slotNum = tonumber(slotRef:match("Slot(%d+)$"))
    if slotNum == nil then return true end
    local hasVIP = false
    pcall(function()
        local MarketplaceService = game:GetService("MarketplaceService")
        hasVIP = MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 1760093100)
    end)
    return slotNum < 9 or hasVIP
end

local function modelMatchesFilters(model)
    if not slotRefIsAllowed(model) then return false end
    local selectedRarities = getSelectedFilters(S.FarmRarityFilters)
    local selectedMutations = getSelectedFilters(S.FarmMutationFilters)
    if #selectedRarities == 0 and #selectedMutations == 0 then return true end
    local rarity = model:GetAttribute("Rarity")
    local mutation = model:GetAttribute("Mutation")
    for _, r in ipairs(selectedRarities) do
        if rarity == r then return true end
    end
    for _, m in ipairs(selectedMutations) do
        if m == "Normal" then
            if mutation == nil then return true end
        else
            if mutation == m then return true end
        end
    end
    return false
end

local function findCarryPrompt(model)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Name == "Carry" and desc.Parent:IsA("BasePart") and desc.ActionText == "Steal" then
            return desc
        end
    end
    return nil
end

local farmLoopToken = 0
local function farmLoop(token)
    local character = LocalPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    while _alive and farmLoopToken == token do
        _safeCall(function()
            rootPart.CFrame = CFrame.new(708, 39, -2123)
            task.wait(0.5)
            if farmLoopToken ~= token then return end
            local validModels = {}
            for _, model in ipairs(workspace.Brainrots:GetChildren()) do
                if model:IsA("Model") and modelMatchesFilters(model) then
                    table.insert(validModels, model)
                end
            end
            if #validModels == 0 then
                task.wait(0.9)
                return
            end
            local target = validModels[math.random(1, #validModels)]
            if not target or not target.Parent then
                task.wait(0.2)
                return
            end
            local pivot = target:GetPivot()
            rootPart.CFrame = pivot * CFrame.new(0, 3, 0)
            task.wait(0.3)
            if farmLoopToken ~= token then return end
            local prompt = findCarryPrompt(target)
            if prompt then
                fireproximityprompt(prompt)
            end
            task.wait(0.3)
            if farmLoopToken ~= token then return end
            rootPart.CFrame = CFrame.new(739, 39, -2122)
            task.wait(0.9)
        end)
    end
end

-- Auto Upgrade Brainrots (plot based)
local function getMyPlot()
    for i = 1, 5 do
        local plot = workspace.Plots[tostring(i)]
        if plot and plot:FindFirstChild("YourBase") then
            return tostring(i)
        end
    end
    return nil
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
    if ok then return result end
    return nil
end

local upgradeBrainrotActive = false
local function upgradeBrainrotLoop()
    while _alive and upgradeBrainrotActive do
        _safeCall(function()
            local maxLevel = S.MaxUpgradeLevel or 10
            local plotId = getMyPlot()
            if not plotId then task.wait(0.05) return end
            for slot = 1, 30 do
                if not upgradeBrainrotActive then break end
                local currentLevel = getSlotInfo(plotId, slot)
                if currentLevel and currentLevel < maxLevel then
                    Remotes.UpgradeBrainrot:Fire(slot)
                    task.wait(0.05)
                end
                task.wait(0.05)
            end
            task.wait(0.05)
        end)
    end
end

-- Lasers removal
local storedLasers = {}
local function findLasers()
    local found = {}
    for _, base in ipairs(workspace.Map.Bases:GetChildren()) do
        local lasers = base:FindFirstChild("LasersModel")
        if lasers then table.insert(found, lasers) end
    end
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

-- Freeze Chasing Bosses (shake detection)
local freezeChaseActive = false
local chaseStoredSpeeds = {}
local chaseSpeedConn = nil
local chaseStopTimer = nil
local chaseIsShaking = false
local chaseCameraCF = Camera.CFrame
local function freezeChaseBosses()
    if chaseSpeedConn then return end
    for _, boss in ipairs(workspace.Bosses:GetChildren()) do
        local humanoid = boss:FindFirstChildOfClass("Humanoid")
        if humanoid and not chaseStoredSpeeds[boss] then
            chaseStoredSpeeds[boss] = humanoid.WalkSpeed
            humanoid.WalkSpeed = 0
        end
    end
    chaseSpeedConn = RunService.Heartbeat:Connect(function()
        for _, boss in ipairs(workspace.Bosses:GetChildren()) do
            local humanoid = boss:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.WalkSpeed = 0 end
        end
    end)
end
local function restoreChaseBosses()
    if chaseSpeedConn then chaseSpeedConn:Disconnect(); chaseSpeedConn = nil end
    for _, boss in ipairs(workspace.Bosses:GetChildren()) do
        local humanoid = boss:FindFirstChildOfClass("Humanoid")
        if humanoid and chaseStoredSpeeds[boss] then
            humanoid.WalkSpeed = chaseStoredSpeeds[boss]
        end
    end
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

-- Freeze Bad Bosses (protect last base)
local badBossStored = {}
local badBossConn = nil
local function getHighestBaseNumber()
    local highest = -1
    for _, boss in ipairs(workspace.Bosses:GetChildren()) do
        local num = tonumber(boss.Name:match("^base(%d+)$"))
        if num and num > highest then highest = num end
    end
    return highest
end
local function isProtectedModel(boss)
    local highest = getHighestBaseNumber()
    if highest == -1 then return false end
    return boss.Name == "base" .. highest
end
local function freezeBadBosses()
    for _, boss in ipairs(workspace.Bosses:GetChildren()) do
        if isProtectedModel(boss) then continue end
        local humanoid = boss:FindFirstChildOfClass("Humanoid")
        if humanoid and not badBossStored[boss] then
            badBossStored[boss] = humanoid.WalkSpeed
            humanoid.WalkSpeed = 0
        end
    end
end
local function forceBadBossSpeeds()
    badBossConn = RunService.Heartbeat:Connect(function()
        for _, boss in ipairs(workspace.Bosses:GetChildren()) do
            if isProtectedModel(boss) then continue end
            local humanoid = boss:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.WalkSpeed ~= 0 then humanoid.WalkSpeed = 0 end
        end
    end)
end
local function restoreBadBosses()
    if badBossConn then badBossConn:Disconnect(); badBossConn = nil end
    for _, boss in ipairs(workspace.Bosses:GetChildren()) do
        local humanoid = boss:FindFirstChildOfClass("Humanoid")
        if humanoid and badBossStored[boss] then
            humanoid.WalkSpeed = badBossStored[boss]
        end
    end
    badBossStored = {}
end

-- ============================================================
-- TAB UI BUILDING (Using Amethyst Components)
-- ============================================================

-- FARM TAB
createSection(tabPages.Farm, "Collection")
local collectToggle = createToggle(tabPages.Farm, {Name = "Auto Collect Cash", CurrentValue = S.AutoCollect, Callback = function(v) S.AutoCollect = v; notifyToggle("Auto Collect", v) end})
local collectSlider = createSlider(tabPages.Farm, {Name = "Collect Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.CollectInterval, Callback = function(v) S.CollectInterval = v end})

createSection(tabPages.Farm, "Brainrot Farming")
local farmToggle = createToggle(tabPages.Farm, {Name = "Farm Selected Brainrots", CurrentValue = S.FarmBrainrot, Callback = function(v)
    S.FarmBrainrot = v
    if v then
        farmLoopToken = farmLoopToken + 1
        local token = farmLoopToken
        task.spawn(function() farmLoop(token) end)
        notifyToggle("Farm Brainrots", v)
    else
        farmLoopToken = farmLoopToken + 1
        notifyToggle("Farm Brainrots", v)
    end
end})

local rarityOptions = {"Common", "Rare", "Epic", "Legendary", "Mythic", "Brainrot God", "Secret", "Divine", "MEME", "OG"}
local rarityDropdown = createDropdown(tabPages.Farm, {Name = "Rarity Filter", Options = rarityOptions, MultipleOptions = true, CurrentOption = {}, Callback = function(v) S.FarmRarityFilters = v end})
local mutationOptions = {"Normal", "Gold", "Diamond", "Rainbow", "Candy"}
local mutationDropdown = createDropdown(tabPages.Farm, {Name = "Mutation Filter", Options = mutationOptions, MultipleOptions = true, CurrentOption = {}, Callback = function(v) S.FarmMutationFilters = v end})

-- UPGRADES TAB
createSection(tabPages.Upgrades, "Rebirth")
local rebirthToggle = createToggle(tabPages.Upgrades, {Name = "Auto Rebirth", CurrentValue = S.AutoRebirth, Callback = function(v) S.AutoRebirth = v; notifyToggle("Auto Rebirth", v) end})
local rebirthSlider = createSlider(tabPages.Upgrades, {Name = "Rebirth Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.RebirthInterval, Callback = function(v) S.RebirthInterval = v end})
createButton(tabPages.Upgrades, {Name = "Rebirth Once", Callback = function() _safeCall(Rebirth) end})

createSection(tabPages.Upgrades, "Speed Upgrades")
local speedUpgradeToggle = createToggle(tabPages.Upgrades, {Name = "Auto Upgrade Speed", CurrentValue = S.AutoSpeedUpgrade, Callback = function(v) S.AutoSpeedUpgrade = v; notifyToggle("Auto Speed Upgrade", v) end})
local speedIntervalSlider = createSlider(tabPages.Upgrades, {Name = "Upgrade Speed Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.SpeedUpgradeInterval, Callback = function(v) S.SpeedUpgradeInterval = v end})
local speedAmountDropdown = createDropdown(tabPages.Upgrades, {Name = "Upgrade Speed Amount", Options = {"1", "5", "10"}, CurrentOption = tostring(S.SpeedUpgradeAmount), Callback = function(v) S.SpeedUpgradeAmount = tonumber(v) end})

createSection(tabPages.Upgrades, "Base Upgrades")
local upgradeBaseToggle = createToggle(tabPages.Upgrades, {Name = "Auto Upgrade Base", CurrentValue = S.AutoUpgradeBase, Callback = function(v) S.AutoUpgradeBase = v; notifyToggle("Auto Upgrade Base", v) end})
local baseIntervalSlider = createSlider(tabPages.Upgrades, {Name = "Upgrade Base Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.UpgradeBaseInterval, Callback = function(v) S.UpgradeBaseInterval = v end})
createButton(tabPages.Upgrades, {Name = "Upgrade Base Once", Callback = function() _safeCall(UpgradeBase) end})

createSection(tabPages.Upgrades, "Brainrot Upgrades")
local upgradeBrainrotToggle = createToggle(tabPages.Upgrades, {Name = "Auto Upgrade Brainrots", CurrentValue = S.AutoUpgradeBrainrots, Callback = function(v)
    S.AutoUpgradeBrainrots = v
    upgradeBrainrotActive = v
    if v then task.spawn(upgradeBrainrotLoop) end
    notifyToggle("Auto Upgrade Brainrots", v)
end})
local maxLevelInput = createInput(tabPages.Upgrades, {Name = "Max Upgrade Level", PlaceholderText = "Enter max level...", Callback = function(v) local num = tonumber(v); if num then S.MaxUpgradeLevel = num end end, RemoveTextAfterFocusLost = false})

-- AUTOMATION TAB
createSection(tabPages.Automation, "Best Brainrots")
local equipBestToggle = createToggle(tabPages.Automation, {Name = "Auto Equip Best Brainrots", CurrentValue = S.AutoEquipBest, Callback = function(v) S.AutoEquipBest = v; notifyToggle("Auto Equip Best", v) end})
local equipBestSlider = createSlider(tabPages.Automation, {Name = "Equip Best Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.EquipBestInterval, Callback = function(v) S.EquipBestInterval = v end})

createSection(tabPages.Automation, "Gifts / Rewards")
local claimGiftsToggle = createToggle(tabPages.Automation, {Name = "Auto Claim Free Gifts", CurrentValue = S.AutoClaimGifts, Callback = function(v) S.AutoClaimGifts = v; notifyToggle("Auto Claim Gifts", v) end})
local claimSlider = createSlider(tabPages.Automation, {Name = "Claim Gifts Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.ClaimGiftsInterval, Callback = function(v) S.ClaimGiftsInterval = v end})

createSection(tabPages.Automation, "Auto Sell")
local sellToggle = createToggle(tabPages.Automation, {Name = "Enable Auto Sell", CurrentValue = S.AutoSell, Callback = function(v) S.AutoSell = v; notifyToggle("Auto Sell", v) end})
local sellIntervalSlider = createSlider(tabPages.Automation, {Name = "Sell Interval", Range = {0.5, 10}, Increment = 0.5, CurrentValue = S.SellInterval, Callback = function(v) S.SellInterval = v end})
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
createButton(tabPages.Automation, {Name = "Sell All (Filters Apply)", Callback = function() _safeCall(SellBrainrots) end})

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
local freezeChaseToggle = createToggle(tabPages.Misc, {Name = "Freeze Chasing Bosses", CurrentValue = S.FreezeChasingBosses, Callback = function(v)
    S.FreezeChasingBosses = v
    freezeChaseActive = v
    if v then startShakeDetection() else stopShakeDetection() end
    notifyToggle("Freeze Chasing Bosses", v)
end})
local freezeBadToggle = createToggle(tabPages.Misc, {Name = "Freeze Bad Bosses", CurrentValue = S.FreezeBadBosses, Callback = function(v)
    S.FreezeBadBosses = v
    if v then freezeBadBosses(); forceBadBossSpeeds() else restoreBadBosses() end
    notifyToggle("Freeze Bad Bosses", v)
end})

-- SETTINGS TAB (simple)
createSection(tabPages.Settings, "Configuration")
createButton(tabPages.Settings, {Name = "Save Config", Callback = function() saveConfig(); notify("Config Saved", "Settings saved to file.", 3, "success") end})
createButton(tabPages.Settings, {Name = "Load Config", Callback = function() loadConfig(); notify("Config Loaded", "Settings loaded from file.", 3, "success") end})
createButton(tabPages.Settings, {Name = "Reset All Settings", Callback = function()
    S.AutoCollect = false; S.AutoRebirth = false; S.AutoSpeedUpgrade = false; S.AutoEquipBest = false
    S.AutoClaimGifts = false; S.AutoUpgradeBase = false; S.AutoSell = false; S.FarmBrainrot = false
    S.AutoUpgradeBrainrots = false; S.LasersRemove = false; S.AntiShake = false
    S.FreezeChasingBosses = false; S.FreezeBadBosses = false
    S.CollectInterval = 1; S.RebirthInterval = 1; S.SpeedUpgradeInterval = 1
    S.EquipBestInterval = 4; S.ClaimGiftsInterval = 1; S.UpgradeBaseInterval = 3
    S.SellInterval = 3; S.SpeedUpgradeAmount = 1; S.MaxUpgradeLevel = 10
    S.SellMode = "Exclude"; S.ExcludedRarities = {}; S.ExcludedMutations = {}; S.ExcludedNames = {}
    S.FarmRarityFilters = {}; S.FarmMutationFilters = {}
    notify("Reset", "All settings reset to default.", 3, "warning")
end})
createParagraph(tabPages.Settings, {Title = "Amethyst Core", Content = "UI Framework v4.1 | Brainrot Script Integration\nFrosted Amethyst Theme\nAll settings auto-save every 30 seconds."})

-- Sync UI to current S values after loading
collectToggle.Set(S.AutoCollect)
collectSlider.Set(S.CollectInterval)
farmToggle.Set(S.FarmBrainrot)
rarityDropdown.Set(S.FarmRarityFilters)
mutationDropdown.Set(S.FarmMutationFilters)
rebirthToggle.Set(S.AutoRebirth)
rebirthSlider.Set(S.RebirthInterval)
speedUpgradeToggle.Set(S.AutoSpeedUpgrade)
speedIntervalSlider.Set(S.SpeedUpgradeInterval)
speedAmountDropdown.Set(tostring(S.SpeedUpgradeAmount))
upgradeBaseToggle.Set(S.AutoUpgradeBase)
baseIntervalSlider.Set(S.UpgradeBaseInterval)
upgradeBrainrotToggle.Set(S.AutoUpgradeBrainrots)
maxLevelInput.Set(tostring(S.MaxUpgradeLevel))
equipBestToggle.Set(S.AutoEquipBest)
equipBestSlider.Set(S.EquipBestInterval)
claimGiftsToggle.Set(S.AutoClaimGifts)
claimSlider.Set(S.ClaimGiftsInterval)
sellToggle.Set(S.AutoSell)
sellIntervalSlider.Set(S.SellInterval)
modeDropdown.Set(S.SellMode == "Exclude" and "Exclude Selected" or "Exclude Non Selected")
rarityExclude.Set(S.ExcludedRarities)
mutationExclude.Set(S.ExcludedMutations)
nameExclude.Set(S.ExcludedNames)
lasersToggle.Set(S.LasersRemove)
antiShakeToggle.Set(S.AntiShake)
freezeChaseToggle.Set(S.FreezeChasingBosses)
freezeBadToggle.Set(S.FreezeBadBosses)

-- Finalize
_G.__AmethystCleanup = cleanupAll
notify("Be a Brainrot Loaded", "Amethyst Core + Brainrot Features\nAll systems ready.", 5, "success")