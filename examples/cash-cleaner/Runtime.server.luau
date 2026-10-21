local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CleanerState = require(script.Parent.CleanerState)
local cleaner = CleanerState.new()
local root = script.Parent.Parent
local pads = root:WaitForChild("GameplayV5"):WaitForChild("InteractionPads")
local statusBoard = root:FindFirstChild("RuntimeStatusBoard", true)
local statusLabel = statusBoard and statusBoard:FindFirstChild("StatusLabel", true)
local messages, lastActionAt, stationViews = {}, {}, {}
local stationNames = { wash = "WASHER", dry = "DRYER", count = "COUNTER", bundle = "BUNDLE PRESS" }
local padStations = { WasherPadV5 = "wash", DryerPadV5 = "dry", CounterPadV5 = "count", BundlePadV5 = "bundle" }
local nextStation = { wash = "dryer", dry = "counter", count = "bundle press", bundle = "shipping dock" }

local function textLabel(parent, name, y, height, size, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, y)
	label.Size = UDim2.new(1, -24, 0, height)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	return label
end

local function ensureHud(player)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end
	local old = playerGui:FindFirstChild("CashCleanerHUDV5")
	if old then old:Destroy() end
	local screen = playerGui:FindFirstChild("CashCleanerHUD")
	if screen then return screen.Panel end
	screen = Instance.new("ScreenGui")
	screen.Name = "CashCleanerHUD"
	screen.ResetOnSpawn = false
	screen.Parent = playerGui
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 12)
	panel.Size = UDim2.new(1, -32, 0, 128)
	panel.BackgroundColor3 = Color3.fromRGB(18, 23, 25)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = screen
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(620, 128)
	constraint.Parent = panel
	textLabel(panel, "Summary", 8, 24, 18, Color3.fromRGB(110, 242, 194))
	textLabel(panel, "Inventory", 32, 40, 14, Color3.fromRGB(238, 242, 244))
	textLabel(panel, "Status", 76, 44, 15, Color3.fromRGB(255, 219, 139))
	return panel
end

local function feedback(player, text)
	if player.Parent ~= Players then return end
	messages[player.UserId] = { text = text, untilAt = os.clock() + 3.2 }
	player:SetAttribute("CashCleanerStatus", text)
end

local function refreshPlayer(player, now)
	local userId = player.UserId
	local state = cleaner:state(userId)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local cash = stats:FindFirstChild("Cash")
	if not cash then
		cash = Instance.new("IntValue")
		cash.Name = "Cash"
		cash.Parent = stats
	end
	cash.Value = state.cash
	for _, key in ipairs({ "cash", "dirty", "inspected", "wet", "dry", "counted", "bundled" }) do
		player:SetAttribute("Cleaner" .. key:sub(1, 1):upper() .. key:sub(2), state[key])
	end
	player:SetAttribute("CleanerHeld", cleaner:held(userId))
	player:SetAttribute("CleanerCapacity", cleaner:capacity(userId))
	local panel = ensureHud(player)
	if not panel then return end
	panel.Summary.Text = string.format("$%d   BILLS %d/%d", state.cash, cleaner:held(userId), cleaner:capacity(userId))
	panel.Inventory.Text = string.format("RAW %d   CHECKED %d   WET %d\nDRY %d   COUNTED %d   PACKED %d",
		state.dirty, state.inspected, state.wet, state.dry, state.counted, state.bundled)
	local message = messages[userId]
	panel.Status.Text = message and message.untilAt > now and message.text or cleaner:nextStep(userId)
end

local function ensurePrompt(part, action, object)
	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	prompt.Parent = part
	return prompt
end

local function canInteract(player, part)
	if Players:GetPlayerByUserId(player.UserId) ~= player then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local body = character and character:FindFirstChild("HumanoidRootPart")
	if not body or not humanoid or humanoid.Health <= 0 then return false end
	if (body.Position - part.Position).Magnitude > 14 then return false end
	local now = os.clock()
	if now - (lastActionAt[player.UserId] or -math.huge) < 0.3 then return false end
	lastActionAt[player.UserId] = now
	return true
end

local actions = {
	ClaimBusinessPadV5 = function(id) return cleaner:claim(id) end,
	DirtyCashTrimPadV5 = function(id) return cleaner:take(id) end,
	InspectPadV5 = function(id) return cleaner:inspect(id) end,
	SellPadV5 = function(id) return cleaner:sell(id) end,
}
for pad, key in pairs({ UpgradeDryerPadV5 = "dryer", UpgradeCounterPadV5 = "counter", UpgradeAutoPadV5 = "auto", UpgradeVaultPadV5 = "vault", UpgradeDockPadV5 = "dock" }) do
	actions[pad] = function(id) return cleaner:upgrade(id, key) end
end

for _, part in ipairs(pads:GetChildren()) do
	if not part:IsA("BasePart") then continue end
	local station = padStations[part.Name]
	local action = actions[part.Name]
	if not station and not action then continue end
	local prompt = ensurePrompt(part, part:GetAttribute("ActionText") or "Use", part:GetAttribute("ObjectText") or part.Name)
	if station then
		local display = Instance.new("BillboardGui")
		display.Name = "StationProgress"
		display.Size = UDim2.fromOffset(200, 64)
		display.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		display.MaxDistance = 65
		display.AlwaysOnTop = false
		display.Parent = part
		local panel = Instance.new("Frame")
		panel.Size = UDim2.fromScale(1, 1)
		panel.BackgroundColor3 = Color3.fromRGB(18, 23, 25)
		panel.BackgroundTransparency = 0.12
		panel.BorderSizePixel = 0
		panel.Parent = display
		local label = textLabel(panel, "Status", 4, 48, 14, Color3.fromRGB(110, 242, 194))
		local rail = Instance.new("Frame")
		rail.Position = UDim2.new(0, 8, 1, -8)
		rail.Size = UDim2.new(1, -16, 0, 4)
		rail.BackgroundColor3 = Color3.fromRGB(61, 68, 71)
		rail.BorderSizePixel = 0
		rail.Parent = panel
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = Color3.fromRGB(255, 203, 103)
		fill.BorderSizePixel = 0
		fill.Parent = rail
		stationViews[station] = { label = label, fill = fill, prompt = prompt, action = prompt.ActionText }
	end
	prompt.Triggered:Connect(function(player)
		if not canInteract(player, part) then return end
		local _, message
		if station then
			_, message = cleaner:start(player.UserId, station, os.clock())
		else
			_, message = action(player.UserId)
		end
		feedback(player, message)
	end)
end

local door = root:FindFirstChild("FrontDoorPanel_GlassFunctional", true)
if door and door:IsA("BasePart") then
	door.CanCollide = false
	local closed = door.CFrame
	local opened = false
	local moving = false
	local generation = 0
	local prompt = ensurePrompt(door, "Open", "Entrance")
	local function move(open)
		generation += 1
		local token = generation
		opened, moving = open, true
		prompt.ActionText = open and "Close" or "Open"
		local tween = TweenService:Create(door, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = open and closed * CFrame.new(7.1, 0, 0) or closed,
		})
		tween.Completed:Once(function() moving = false end)
		tween:Play()
		if open then
			task.delay(4.5, function()
				if door.Parent and generation == token and opened and not moving then move(false) end
			end)
		end
	end
	prompt.Triggered:Connect(function(player)
		if not moving and canInteract(player, door) then move(not opened) end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	cleaner:release(player.UserId)
	messages[player.UserId] = nil
	lastActionAt[player.UserId] = nil
end)

while script.Parent do
	local now = os.clock()
	for station, job in pairs(cleaner.jobs) do
		local completed = cleaner:complete(station, job.id, now)
		if completed then
			local player = Players:GetPlayerByUserId(job.userId)
			if player then feedback(player, job.amount .. " bills ready. Next stop, " .. nextStation[station]) end
		end
	end
	for station, view in pairs(stationViews) do
		local job = cleaner.jobs[station]
		if job then
			local remaining = math.max(0, job.endsAt - now)
			view.label.Text = string.format("%s\n%d BILLS   %.1fs", stationNames[station], job.amount, remaining)
			view.fill.Size = UDim2.fromScale(math.clamp((now - job.startedAt) / (job.endsAt - job.startedAt), 0, 1), 1)
			view.prompt.ActionText = string.format("Processing %.1fs", remaining)
		else
			view.label.Text = stationNames[station] .. "\nREADY"
			view.fill.Size = UDim2.fromScale(0, 1)
			view.prompt.ActionText = view.action
		end
	end
	if statusLabel then
		local owner = cleaner.owner
		if owner then
			local state = cleaner:state(owner)
			statusLabel.Text = string.format("CASH CLEANER\nBUSINESS ACTIVE\n$%d   CAPACITY %d/%d\n%s",
				state.cash, cleaner:held(owner), cleaner:capacity(owner), cleaner:nextStep(owner):upper())
		else
			statusLabel.Text = "CASH CLEANER\nBUSINESS AVAILABLE\nCLAIM AT THE ENTRANCE"
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do refreshPlayer(player, now) end
	task.wait(0.2)
end
