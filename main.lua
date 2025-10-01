--[[ 
    ⚡ Diddy Gui Startup Config ⚡
    "Harmless Exploits. Tactical Insight. Chaos Elegance."
]] if not game:IsLoaded() then
    game.Loaded:Wait()
end

function profile(name, fn)
    local start = tick()
    local ok, result_or_err = pcall(fn)
    local elapsed = (tick() - start) * 1000

    if elapsed > 1 then
        print(string.format("[PROFILING WARNING] %s took %.2f ms", name, elapsed))
    end

    if not ok then
        warn(string.format("[ERROR] %s error: %s", name, result_or_err))
    end

    return result_or_err
end

DiddyConfig = {
    __NAME__ = "Diddy Gui",
    __VERSION__ = "0.1.1-alpha",
    __DESCRIPTION__ = "Universal Roblox Command Bar for harmless exploits, player analysis, and other cool shit.",
    __AUTHOR__ = "ephemeral8997",
    __SAFE_MODE__ = true, -- Restrict destructive features by default
    __DETECT_CHEATS__ = true, -- Enables in-game player behavior scanning
    __DEV_MODE__ = true, -- Extra logging, performance stats, etc
    -- __UI_THEME__ = "BubblegumMatrix", -- Your upcoming vibe
    __COMMAND_PREFIX__ = {"!"}, -- Command bar input prefix
    __HOOK_LEVEL__ = 0, -- How deep into Roblox APIs this baby sinks (0, 1, 2) (def, warn, err)
    __MEMO__ = [[
        Diddy Gui isn’t here to grief. It’s here to observe, test, reveal.
        It’s the scalpel, not the nuke. It’s sugar and paranoia.
    ]]
}

function dev_log(level, ...)
    level = tonumber(level) or 0

    if not DiddyConfig or not DiddyConfig.__DEV_MODE__ then
        return
    end

    if level < (DiddyConfig.__HOOK_LEVEL__ or 0) then
        return
    end

    local todo, prefix
    if level == 0 then
        todo = print
        prefix = "[INFO]"
    elseif level == 1 then
        todo = warn
        prefix = "[WARNING]"
    elseif level == 2 then
        todo = error
        prefix = "[ERROR]"
    else
        warn("[DEV LOG] Invalid numeric log level: " .. tostring(level))
        return
    end

    local args = {...}
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    local msg = table.concat(args, " ")
    todo("[DEV MODE ENABLED] " .. prefix .. " " .. msg)
end

-- getgenv().DiddyConfig = DiddyConfig
-- getgenv().dev_log = dev_log

-- Optional Debug Output
dev_log(0, "[Diddy Gui Booting]")
dev_log(0, "Name:", DiddyConfig.__NAME__)
dev_log(0, "Version:", DiddyConfig.__VERSION__)
dev_log(0, "Safe Mode:", DiddyConfig.__SAFE_MODE__)

if not isfolder("DiddyPlugins") then
    makefolder("DiddyPlugins")
    dev_log(1, "Created diddy plugins folder, wasnt created!")
end

-- 🌐 Service Manager
Services = setmetatable({}, {
    __index = function(self, key)
        local service = game:GetService(key)
        if service then
            rawset(self, key, service)
            return service
        end
        error("Service '" .. key .. "' not found", 2)
    end
})

-- Player Setup
LocalPlayer = Services.Players.LocalPlayer
PlayerGui = LocalPlayer:WaitForChild("PlayerGui") -- takes some time!
Camera = workspace.CurrentCamera

function import(libName)
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/ephemeral8997/RBXCoreModules/refs/heads/main/" ..
                                       libName .. ".lua"))()
end

-- Core Packages
StringMatchUtils = import("StringUtils")
Dragger = import("Dragger")
SelfOpsCore = import("SelfManager")

-- Local Packages

-- PlayerOpsCore: Player Search & Reference
PlayerOpsCore = {
    GetServerPlayersByFuzzyPrefix = function(self, prefix)
        local scored = {}
        prefix = prefix:lower()

        for _, player in ipairs(Services.Players:GetPlayers()) do
            local name = player.Name:lower()
            local displayName = player.DisplayName:lower()

            local namePrefix = name:sub(1, #prefix)
            local displayPrefix = displayName:sub(1, #prefix)

            local nameScore = StringMatchUtils.Levenshtein(prefix, namePrefix)
            local displayScore = StringMatchUtils.Levenshtein(prefix, displayPrefix)
            local bestScore = math.min(nameScore, displayScore)

            table.insert(scored, {
                player = player,
                score = bestScore
            })
        end

        table.sort(scored, function(a, b)
            return a.score < b.score
        end)

        local results = {}
        for _, item in ipairs(scored) do
            table.insert(results, item.player)
        end

        return results
    end
}

-- CommandManager: Registers, resolves, and executes text-based commands.
CommandManager = {
    Commands = {},

    Register = function(self, args, func)
        assert(type(args) == "table", "Expected table for args")
        assert(type(args.Name) == "string", "args.Name must be a string")
        assert(type(func) == "function", "func must be a function")

        local cmdName = args.Name:lower()

        self.Commands[cmdName] = {
            Info = args,
            Execute = func
        }

        if args.Aliases and type(args.Aliases) == "table" then
            for _, alias in ipairs(args.Aliases) do
                local aliasName = alias:lower()
                self.Commands[aliasName] = self.Commands[cmdName]
            end
        end
    end,

    FindMatchingCommand = function(self, rawCmd, threshold)
        rawCmd = rawCmd:lower()
        threshold = threshold or 2

        local exact = self.Commands[rawCmd]
        if exact then
            return exact
        end

        for name, entry in pairs(self.Commands) do
            if StringMatchUtils.IsFuzzyPrefixMatch(rawCmd, name, threshold) then
                return entry
            end
            if entry.Aliases then
                for _, alias in ipairs(entry.Aliases) do
                    if StringMatchUtils.IsFuzzyPrefixMatch(rawCmd, alias, threshold) then
                        return entry
                    end
                end
            end
        end

        return nil
    end,

    Execute = function(self, input)
        local commands = input:split("\\")
        for _, commandStr in ipairs(commands) do
            commandStr = commandStr:match("^%s*(.-)%s*$")

            local args = commandStr:split(" ")
            local rawCmd = args[1] and args[1]:lower() or nil
            table.remove(args, 1)

            local entry = self:FindMatchingCommand(rawCmd)

            if entry and entry.Execute then
                local ok, err = pcall(function()
                    entry.Execute(unpack(args))
                end)
                if not ok then
                    dev_log(2, "DiddyGui Error executing command '" .. tostring(rawCmd) .. "':", err)
                end
            else
                dev_log(1, "Unknown or unmatched command:", tostring(rawCmd))
            end
        end
    end
}

local function CreateCommandBar(screen)
    local container = Instance.new("Frame", screen)
    container.Size = UDim2.new(0.5, 0, 0, 36)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Position = UDim2.new(0.5, 0, 0.5, 0)
    container.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    container.BorderSizePixel = 0
    container.Visible = false

    local edges = {}

    local function edge(name, size, position)
        local e = Instance.new("Frame", container)
        e.Name = name
        e.Size = size
        e.Position = position
        e.BackgroundTransparency = 1
        e.BorderSizePixel = 0
        e.Active = true
        e.ZIndex = 2
        table.insert(edges, e)
        return e
    end

    edge("TopEdge", UDim2.new(1, 0, 0, 6), UDim2.new(0, 0, 0, 0))
    edge("LeftEdge", UDim2.new(0, 6, 1, 0), UDim2.new(0, 0, 0, 0))
    edge("RightEdge", UDim2.new(0, 6, 1, 0), UDim2.new(1, -6, 0, 0))
    edge("BottomEdge", UDim2.new(1, 0, 0, 6), UDim2.new(0, 0, 1, -6))

    local shadow = Instance.new("ImageLabel", container)
    shadow.Image = "rbxassetid://1316045217"
    shadow.Size = UDim2.new(1, 12, 1, 12)
    shadow.Position = UDim2.new(0, -6, 0, -6)
    shadow.BackgroundTransparency = 1
    shadow.ImageTransparency = 0.5
    shadow.ZIndex = 0

    local CommandBar = Instance.new("TextBox", container)
    CommandBar.Size = UDim2.new(1, -40, 1, 0)
    CommandBar.Position = UDim2.new(0, 0, 0, 0)
    CommandBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    CommandBar.BorderSizePixel = 0
    CommandBar.TextColor3 = Color3.fromRGB(200, 200, 200)
    CommandBar.Font = Enum.Font.Code
    CommandBar.PlaceholderText = "Enter command..."
    CommandBar.TextSize = 16
    CommandBar.Text = ""
    CommandBar.ClearTextOnFocus = false
    CommandBar.ZIndex = 1

    local Close = Instance.new("TextButton", container)
    Close.Size = UDim2.new(0, 36, 1, 0)
    Close.Position = UDim2.new(1, -36, 0, 0)
    Close.BackgroundColor3 = Color3.fromRGB(50, 0, 0)
    Close.Text = "X"
    Close.TextColor3 = Color3.fromRGB(255, 80, 80)
    Close.Font = Enum.Font.SourceSansBold
    Close.TextSize = 18
    Close.ZIndex = 1
    Close.AutoButtonColor = true

    return {
        Container = container,
        CommandBar = CommandBar,
        Close = Close,
        Anchors = edges
    }
end

local function CreateSmallIcon(screen)
    local Icon = Instance.new("Frame", screen)
    Icon.Name = "SmallIcon"
    Icon.Size = UDim2.new(0, 50, 0, 50)
    Icon.AnchorPoint = Vector2.new(0.5, 0.5)
    Icon.Position = UDim2.new(0.5, 0, 0.5, 0)
    Icon.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    Icon.Visible = true

    local stroke = Instance.new("UIStroke", Icon)
    stroke.Color = Color3.fromRGB(100, 100, 100)
    stroke.Thickness = 2

    local corner = Instance.new("UICorner", Icon)
    corner.CornerRadius = UDim.new(0, 6)

    return Icon
end

local function CreateCommandUI(screen)
    local barParts = CreateCommandBar(screen)
    local icon = CreateSmallIcon(screen)

    local container = barParts.Container
    local CommandBar = barParts.CommandBar
    local Close = barParts.Close
    local DraggerAnchors = barParts.Anchors

    local function syncFromIcon()
        container.Position = icon.Position
    end

    local function syncFromContainer()
        icon.Position = container.Position
    end

    Close.MouseButton1Click:Connect(function()
        dev_log(0, "Close Button was clicked!")
        container.Visible = false
        icon.Visible = true
        CommandBar:ReleaseFocus()
        syncFromContainer()
    end)

    local MIN_DIST = 12
    local wasDragged = false
    icon.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            wasDragged = false
            local startPos = input.Position
            local movedConn, endedConn

            movedConn = Services.UserInputService.InputChanged:Connect(function(moveInput)
                if moveInput == input then
                    local delta = moveInput.Position - startPos
                    if delta.Magnitude > MIN_DIST then
                        wasDragged = true
                        movedConn:Disconnect()
                    end
                end
            end)

            endedConn = Services.UserInputService.InputEnded:Connect(function(endInput)
                if endInput == input then
                    endedConn:Disconnect()
                    if movedConn then
                        movedConn:Disconnect()
                    end

                    if not wasDragged then
                        dev_log(0, "Icon clicked!")
                        container.Position = icon.Position
                        container.Visible = true
                        icon.Visible = false
                        CommandBar:CaptureFocus()
                    end
                end
            end)
        end
    end)

    Services.UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then
            return
        end
        if input.KeyCode == Enum.KeyCode.Semicolon then
            local showing = not container.Visible
            container.Visible = showing
            icon.Visible = not showing

            if showing then
                container.Position = icon.Position
                CommandBar:CaptureFocus()
            else
                icon.Position = container.Position
                CommandBar:ReleaseFocus()
            end
        end
    end)

    CommandBar.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local input = CommandBar.Text
            CommandBar.Text = ""
            dev_log(1, "Executing command:", input)
            CommandManager:Execute(input)
        end
    end)

    return DraggerAnchors, container, icon
end

profile("Main Script", function()
    local MainScreen = Instance.new("ScreenGui", PlayerGui)
    MainScreen.Name = "DiddyGui"
    MainScreen.ResetOnSpawn = false

    local BarAnchors, container, Icon = CreateCommandUI(MainScreen)

    local allDraggables = {}
    for _, anchor in ipairs(BarAnchors) do
        table.insert(allDraggables, anchor)
    end
    table.insert(allDraggables, Icon)

    Dragger:Do(allDraggables, {container, Icon})
end)

-- Commands
--[[
CommandManager:Register({
}, function() end)
]]
CommandManager:Register({
    Name = "greet",
    Description = "Greets the user",
    Usage = "greet <name>",
    Aliases = {"hello", "hi", "yo"}
}, function(name)
    print("Hello, " .. (name or "stranger") .. "!")
end)

CommandManager:Register({
    Name = "goto",
    Description = "Teleports you directly to the given player's position.",
    Usage = "goto <playerNamePrefix>",
    Aliases = {"to"}
}, function(player_name)
    local targets = PlayerOpsCore:GetServerPlayersByFuzzyPrefix(player_name)

    if #targets == 0 then
        dev_log(1, "No players found matching:", player_name)
    elseif #targets > 1 then
        local names = {}
        for _, p in ipairs(targets) do
            table.insert(names, p.Name)
        end
        dev_log(1, "Multiple players matched:", table.concat(names, ", "))
        -- return
    end
    SelfOpsCore:TeleportToPlayer(targets[1])
    dev_log(0, "Teleported to", targets[1].Name)
end)
