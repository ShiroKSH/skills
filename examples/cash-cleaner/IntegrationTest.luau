return function(args)
	local result = require(script.Parent.CleanerStateTests)(require(script.Parent.CleanerState))
	task.wait(0.5)
	local pads = script.Parent.Parent.GameplayV5.InteractionPads
	local prompts, countdowns = 0, 0
	for _, part in ipairs(pads:GetChildren()) do
		local prompt = part:FindFirstChildWhichIsA("ProximityPrompt")
		if prompt and prompt.Enabled then prompts += 1 end
		if part:FindFirstChild("StationProgress") then countdowns += 1 end
	end
	assert(prompts == 13, "Expected 13 active prompts")
	assert(countdowns == 4, "Expected four station countdowns")
	local door = script.Parent.Parent:FindFirstChild("FrontDoorPanel_GlassFunctional", true)
	assert(door and door.CanCollide, "Closed entrance must block traversal")
	result.closedDoorCollides = true
	result.activePrompts = prompts
	result.stationCountdowns = countdowns
	if args and args.verifyPlayer then
		local players = game:GetService("Players")
		local deadline = os.clock() + 12
		local player, panel, body
		repeat
			player = players:GetPlayers()[1]
			local gui = player and player:FindFirstChildOfClass("PlayerGui")
			local hud = gui and gui:FindFirstChild("CashCleanerHUD")
			panel = hud and hud:FindFirstChild("Panel")
			body = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not panel or not body then task.wait(0.1) end
		until (panel and body) or os.clock() >= deadline
		assert(panel and body, "Play mode must create a player, character, and HUD")
		assert(panel.Summary.Text ~= "" and panel.Inventory.Text ~= "" and panel.Status.Text ~= "", "HUD labels must be populated")
		local spawn = script.Parent.Parent:FindFirstChildWhichIsA("SpawnLocation", true)
		assert(spawn and (body.Position - spawn.Position).Magnitude < 15, "Player must spawn on the map")
		result.playerSpawnVerified = true
		result.populatedHudLabels = 3
	end
	return result
end
