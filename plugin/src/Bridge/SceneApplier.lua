local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local InstanceSerializer = require(script.Parent.InstanceSerializer)
local Safety = require(script.Parent.Safety)
local TerrainGenerator = require(script.Parent.TerrainGenerator)

local SceneApplier = {}

local function timestamp()
	return os.date("!%Y%m%dT%H%M%SZ")
end

local function serviceFromScriptPath(path)
	local first = tostring(path):match("^([^/%.]+)")
	if first == "ServerScriptService" then
		return ServerScriptService
	elseif first == "ReplicatedStorage" then
		return game:GetService("ReplicatedStorage")
	elseif first == "StarterGui" then
		return game:GetService("StarterGui")
	elseif first == "StarterPack" then
		return game:GetService("StarterPack")
	end
	return ServerScriptService
end

local function scriptClassFromPath(path)
	if tostring(path):find("%.client%.lua$") then
		return "LocalScript"
	elseif tostring(path):find("%.module%.lua$") then
		return "ModuleScript"
	end
	return "Script"
end

local function scriptNameFromPath(path)
	local fileName = tostring(path):gsub("\\", "/"):match("([^/]+)$") or "GeneratedScript"
	fileName = fileName:gsub("%.server%.lua$", "")
	fileName = fileName:gsub("%.client%.lua$", "")
	fileName = fileName:gsub("%.module%.lua$", "")
	fileName = fileName:gsub("%.lua$", "")
	return Safety.sanitizeName(fileName)
end

local function applyLighting(lighting)
	if not lighting then
		return
	end

	if lighting.timeOfDay then
		Lighting.TimeOfDay = lighting.timeOfDay
	end
	if lighting.ambient then
		Lighting.Ambient = InstanceSerializer.deserialize(lighting.ambient)
	end
	if lighting.brightness then
		Lighting.Brightness = lighting.brightness
	end
end

local function createZone(zone, zonesFolder, createdPaths)
	local part
	if zone.kind == "spawn" then
		part = Instance.new("SpawnLocation")
		part.Neutral = true
	else
		part = Instance.new("Part")
		part.Transparency = 0.65
		part.CanCollide = false
	end

	part.Name = Safety.sanitizeName(zone.name)
	part.Anchored = true
	part.Size = InstanceSerializer.deserialize(zone.size)
	part.Position = InstanceSerializer.deserialize(zone.position)
	part.Parent = zonesFolder
	table.insert(createdPaths, InstanceSerializer.pathOf(part))
	return part
end

local function resolveParent(parentPath, mapRoot)
	if parentPath == "$MAP_ROOT" or parentPath == nil then
		return mapRoot
	end

	if tostring(parentPath):sub(1, 10) == "$MAP_ROOT/" then
		local current = mapRoot
		for _, segment in ipairs(string.split(parentPath:sub(11), "/")) do
			if segment == "" then
				return nil
			end
			current = current:FindFirstChild(segment)
			if not current then
				return nil
			end
		end
		return current
	end
	return InstanceSerializer.resolve(parentPath)
end

local function createSpecInstance(instanceSpec, parent, createdPaths)
	Safety.assertAllowedClass(instanceSpec.className)
	local instance = Instance.new(instanceSpec.className)
	instance.Name = Safety.sanitizeName(instanceSpec.name)
	local properties = table.clone(instanceSpec.properties or {})
	if properties.CFrame then
		properties.Position = nil
	end
	local ok, err = pcall(InstanceSerializer.writeProperties, instance, properties)
	if not ok then
		instance:Destroy()
		error(err, 0)
	end
	instance.Parent = parent
	table.insert(createdPaths, InstanceSerializer.pathOf(instance))
	return instance
end

local function createScript(scriptSpec, mapRootName, createdPaths)
	local service = serviceFromScriptPath(scriptSpec.path)
	local folder = service:FindFirstChild("MapDrafts")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MapDrafts"
		folder.Parent = service
	end

	local mapFolder = folder:FindFirstChild(mapRootName)
	if not mapFolder then
		mapFolder = Instance.new("Folder")
		mapFolder.Name = mapRootName
		mapFolder.Parent = folder
	end

	local scriptObject = Instance.new(scriptClassFromPath(scriptSpec.path))
	scriptObject.Name = scriptNameFromPath(scriptSpec.path)
	scriptObject.Source = scriptSpec.source or ""
	scriptObject.Parent = mapFolder
	table.insert(createdPaths, InstanceSerializer.pathOf(scriptObject))
	return scriptObject
end

local function vectorValue(value, fallback)
	if typeof(value) == "Vector3" then
		return value
	elseif typeof(value) == "table" and value.type then
		return InstanceSerializer.deserialize(value)
	elseif typeof(value) == "table" and #value >= 3 then
		return Vector3.new(value[1], value[2], value[3])
	end
	return fallback
end

local function colorValue(value, fallback)
	if typeof(value) == "Color3" then
		return value
	elseif typeof(value) == "table" and value.type then
		return InstanceSerializer.deserialize(value)
	elseif typeof(value) == "table" and #value >= 3 then
		return Color3.new(value[1], value[2], value[3])
	end
	return fallback
end

local function materialByName(name, fallback)
	if typeof(name) == "EnumItem" then
		return name
	elseif typeof(name) == "table" and name.type == "Enum" then
		return InstanceSerializer.deserialize(name)
	elseif typeof(name) == "string" then
		local ok, value = pcall(function()
			return InstanceSerializer.deserialize({ type = "Enum", value = name })
		end)
		if ok then
			return value
		end
	end
	return fallback
end

local function paletteFor(sceneSpec)
	local palette = (sceneSpec.theme and sceneSpec.theme.palette) or {}
	return {
		wall = colorValue(palette.wall, Color3.fromRGB(83, 89, 96)),
		accent = colorValue(palette.accent, Color3.fromRGB(32, 154, 175)),
		roof = colorValue(palette.roof, Color3.fromRGB(35, 38, 42)),
		floor = colorValue(palette.floor, Color3.fromRGB(112, 115, 112)),
		trim = colorValue(palette.trim, Color3.fromRGB(215, 218, 210)),
	}
end

local function makePart(parent, name, position, size, material, color, cframe, extra)
	local part = Instance.new("Part")
	part.Name = Safety.sanitizeName(name)
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Position = position
	part.Material = material or Enum.Material.Concrete
	part.Color = color
	if cframe then
		part.CFrame = cframe
	end
	if extra then
		if extra.canCollide ~= nil then
			part.CanCollide = extra.canCollide
		end
		if extra.transparency then
			part.Transparency = extra.transparency
		end
	end
	part.Parent = parent
	return part
end

local function addCreated(createdPaths, instance)
	table.insert(createdPaths, InstanceSerializer.pathOf(instance))
	return instance
end

local function addPrompt(part, actionText)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UsePrompt"
	prompt.ActionText = actionText or "Use"
	prompt.ObjectText = part.Name
	prompt.HoldDuration = 0.12
	prompt.MaxActivationDistance = 10
	prompt.Parent = part
	return prompt
end

local function markFunctionalPart(part, kind, promptText, options)
	part:SetAttribute("BridgeFunctionalKind", kind)
	part:SetAttribute("PromptText", promptText or "Use")
	if options then
		if options.openOffset then
			part:SetAttribute("OpenOffset", options.openOffset)
		end
		if options.targetName then
			part:SetAttribute("BridgeTargetName", options.targetName)
		end
		if options.targetPosition then
			part:SetAttribute("TargetPosition", options.targetPosition)
		end
		if options.startsOpen ~= nil then
			part:SetAttribute("StartsOpen", options.startsOpen == true)
		end
		if options.locked ~= nil then
			part:SetAttribute("Locked", options.locked == true)
		end
		if options.autoCloseSeconds ~= nil then
			part:SetAttribute("AutoCloseSeconds", options.autoCloseSeconds)
		end
	end
	addPrompt(part, promptText or "Use")
end

local function createFunctionalDoor(parent, name, position, size, palette, createdPaths, options)
	local door = addCreated(createdPaths, makePart(parent, name, position, size, Enum.Material.WoodPlanks, palette.accent))
	markFunctionalPart(door, "SlidingDoor", (options and options.promptText) or "Open", {
		openOffset = (options and options.openOffset) or Vector3.new(size.X + 0.5, 0, 0),
		startsOpen = options and options.startsOpen,
		locked = options and options.locked,
		autoCloseSeconds = (options and options.autoCloseSeconds) or 5,
	})
	return door
end

local function resolveFunctionalTarget(mapRoot, targetName)
	if not targetName or targetName == "" then
		return nil
	end
	local raw = tostring(targetName)
	local mapRootPath = InstanceSerializer.pathOf(mapRoot)
	local resolved
	if raw:sub(1, 10) == "$MAP_ROOT/" then
		resolved = InstanceSerializer.resolve(mapRootPath .. raw:sub(10))
	else
		resolved = InstanceSerializer.resolve(raw)
	end
	if resolved and resolved:IsDescendantOf(mapRoot) then
		return resolved
	end
	for _, descendant in ipairs(mapRoot:GetDescendants()) do
		if descendant.Name == raw then
			return descendant
		end
	end
	return nil
end

local function createFunctionalRuntimeSource(mapRootPath)
	return ([[local TweenService = game:GetService("TweenService")

local MAP_ROOT_PATH = %q

local function resolvePath(pathValue)
	local current = game
	for segment in string.gmatch(pathValue, "[^/]+") do
		if segment == "Workspace" then
			current = workspace
		elseif current == game then
			current = game:GetService(segment)
		else
			current = current:WaitForChild(segment, 10)
		end
		if not current then
			return nil
		end
	end
	return current
end

local mapRoot = resolvePath(MAP_ROOT_PATH)
if not mapRoot then
	warn("MapInteractions: map root not found", MAP_ROOT_PATH)
	return
end

local function vectorAttribute(part, name, fallback)
	local value = part:GetAttribute(name)
	if typeof(value) == "Vector3" then
		return value
	end
	return fallback
end

local function promptFor(part, actionText)
	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UsePrompt"
		prompt.Parent = part
	end
	prompt.ActionText = actionText
	prompt.ObjectText = part.Name
	prompt.HoldDuration = 0.12
	prompt.MaxActivationDistance = 10
	return prompt
end

local activeTweens = {}

local function tweenPart(part, prompt, closedCFrame, openOffset)
	local isOpen = part:GetAttribute("StartsOpen") == true
	local busy = false
	local openText = prompt.ActionText
	local autoCloseSeconds = tonumber(part:GetAttribute("AutoCloseSeconds")) or 5
	if isOpen then
		part.CFrame = closedCFrame + openOffset
	end
	part:SetAttribute("BridgeIsOpen", isOpen)

	local function setOpen(nextOpen)
		if busy or part:GetAttribute("Locked") == true then
			return
		end
		busy = true
		isOpen = nextOpen
		part:SetAttribute("BridgeIsOpen", isOpen)
		prompt.ActionText = isOpen and "Close" or openText
		if activeTweens[part] then
			activeTweens[part]:Cancel()
		end
		local goal = isOpen and (closedCFrame + openOffset) or closedCFrame
		local tween = TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal })
		activeTweens[part] = tween
		tween.Completed:Connect(function()
			if activeTweens[part] == tween then
				activeTweens[part] = nil
			end
			busy = false
		end)
		tween:Play()
		if isOpen and autoCloseSeconds > 0 then
			local closeToken = os.clock()
			part:SetAttribute("BridgeCloseToken", closeToken)
			task.delay(autoCloseSeconds, function()
				if part.Parent and isOpen and part:GetAttribute("BridgeCloseToken") == closeToken then
					setOpen(false)
				end
			end)
		end
	end

	return function()
		setOpen(not isOpen)
	end
end

local function findTarget(name)
	if not name or name == "" then
		return nil
	end
	for _, descendant in ipairs(mapRoot:GetDescendants()) do
		if descendant.Name == name then
			return descendant
		end
	end
	return nil
end

for _, descendant in ipairs(mapRoot:GetDescendants()) do
	if descendant:IsA("BasePart") then
		local kind = descendant:GetAttribute("BridgeFunctionalKind")
		if kind == "SlidingDoor" and descendant:GetAttribute("BridgeRuntimeBound") ~= true then
			descendant:SetAttribute("BridgeRuntimeBound", true)
			local prompt = promptFor(descendant, descendant:GetAttribute("PromptText") or "Open")
			prompt.Triggered:Connect(tweenPart(descendant, prompt, descendant.CFrame, vectorAttribute(descendant, "OpenOffset", Vector3.new(0, 0, 5))))
		elseif kind == "LiftPlatform" and descendant:GetAttribute("BridgeRuntimeBound") ~= true then
			descendant:SetAttribute("BridgeRuntimeBound", true)
			local prompt = promptFor(descendant, descendant:GetAttribute("PromptText") or "Move")
			prompt.Triggered:Connect(tweenPart(descendant, prompt, descendant.CFrame, vectorAttribute(descendant, "OpenOffset", Vector3.new(0, 16, 0))))
		elseif kind == "TeleporterPad" then
			local prompt = promptFor(descendant, descendant:GetAttribute("PromptText") or "Travel")
			prompt.Triggered:Connect(function(player)
				local target = vectorAttribute(descendant, "TargetPosition", descendant.Position + Vector3.new(0, 8, 0))
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					root.CFrame = CFrame.new(target + Vector3.new(0, 3, 0))
				end
			end)
		elseif kind == "ToggleButton" then
			local prompt = promptFor(descendant, descendant:GetAttribute("PromptText") or "Use")
			prompt.Triggered:Connect(function()
				local target = findTarget(descendant:GetAttribute("BridgeTargetName"))
				if target and target:IsA("BasePart") then
					local hidden = target.Transparency < 0.9
					target.Transparency = hidden and 1 or 0
					target.CanCollide = not hidden
				end
			end)
		end
	end
end
]]):format(mapRootPath)
end

local function createRuntimeScript(mapRootName, mapRootPath, createdPaths)
	local folder = ServerScriptService:FindFirstChild("MapDrafts")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MapDrafts"
		folder.Parent = ServerScriptService
	end

	local mapFolder = folder:FindFirstChild(mapRootName)
	if not mapFolder then
		mapFolder = Instance.new("Folder")
		mapFolder.Name = mapRootName
		mapFolder.Parent = folder
	end

	local scriptObject = Instance.new("Script")
	scriptObject.Name = "MapInteractions"
	scriptObject.Source = createFunctionalRuntimeSource(mapRootPath)
	scriptObject.Parent = mapFolder
	addCreated(createdPaths, scriptObject)
	return scriptObject
end

local function createFloor(parent, basePosition, y, footprint, palette, createdPaths, hasStairwell)
	if not hasStairwell then
		addCreated(createdPaths, makePart(parent, "Floor", Vector3.new(basePosition.X, y, basePosition.Z), Vector3.new(footprint.X, 1, footprint.Z), Enum.Material.Concrete, palette.floor))
		return
	end

	local minX = basePosition.X - footprint.X / 2
	local maxX = basePosition.X + footprint.X / 2
	local minZ = basePosition.Z - footprint.Z / 2
	local maxZ = basePosition.Z + footprint.Z / 2
	local holeWidth = math.min(10, footprint.X * 0.35)
	local holeDepth = math.min(13, footprint.Z * 0.45)
	local holeX = basePosition.X - footprint.X * 0.28
	local holeZ = basePosition.Z + footprint.Z * 0.16
	local holeMinX = holeX - holeWidth / 2
	local holeMaxX = holeX + holeWidth / 2
	local holeMinZ = holeZ - holeDepth / 2
	local holeMaxZ = holeZ + holeDepth / 2

	local function panel(name, centerX, centerZ, sizeX, sizeZ)
		if sizeX > 0.5 and sizeZ > 0.5 then
			addCreated(createdPaths, makePart(parent, name, Vector3.new(centerX, y, centerZ), Vector3.new(sizeX, 1, sizeZ), Enum.Material.Concrete, palette.floor))
		end
	end

	panel("Floor_West", (minX + holeMinX) / 2, basePosition.Z, holeMinX - minX, footprint.Z)
	panel("Floor_East", (holeMaxX + maxX) / 2, basePosition.Z, maxX - holeMaxX, footprint.Z)
	panel("Floor_North", holeX, (minZ + holeMinZ) / 2, holeWidth, holeMinZ - minZ)
	panel("Floor_South", holeX, (holeMaxZ + maxZ) / 2, holeWidth, maxZ - holeMaxZ)
	addCreated(createdPaths, makePart(parent, "StairwellTrim_N", Vector3.new(holeX, y + 0.45, holeMinZ), Vector3.new(holeWidth, 0.45, 0.45), Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, "StairwellTrim_S", Vector3.new(holeX, y + 0.45, holeMaxZ), Vector3.new(holeWidth, 0.45, 0.45), Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, "StairwellTrim_W", Vector3.new(holeMinX, y + 0.45, holeZ), Vector3.new(0.45, 0.45, holeDepth), Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, "StairwellTrim_E", Vector3.new(holeMaxX, y + 0.45, holeZ), Vector3.new(0.45, 0.45, holeDepth), Enum.Material.WoodPlanks, palette.trim))
end

local function makeWallSegment(parent, name, position, size, material, color, createdPaths)
	if size.X <= 0.1 or size.Y <= 0.1 or size.Z <= 0.1 then
		return
	end
	addCreated(createdPaths, makePart(parent, name, position, size, material, color))
end

local function createWindowAssembly(parent, name, position, width, height, thickness, axis, palette, createdPaths)
	local glassSize
	local frameHorizontalSize
	local frameVerticalSize
	local topBottomOffset
	local sideOffset
	local exteriorSillSize
	local exteriorSillOffset
	local frame = 0.34
	local frameDepth = math.max(0.18, thickness * 0.62)
	local paneDepth = 0.08
	if axis == "X" then
		glassSize = Vector3.new(paneDepth, math.max(0.5, height - frame * 2.2), math.max(0.5, width - frame * 2.2))
		frameHorizontalSize = Vector3.new(frameDepth, frame, width)
		frameVerticalSize = Vector3.new(frameDepth, height, frame)
		topBottomOffset = Vector3.new(0, height / 2 - frame / 2, 0)
		sideOffset = Vector3.new(0, 0, width / 2 - frame / 2)
		exteriorSillSize = Vector3.new(frameDepth, frame, width + 1.4)
		exteriorSillOffset = Vector3.new(thickness / 2 + frameDepth / 2 + 0.04, -height / 2 - frame * 0.7, 0)
	else
		glassSize = Vector3.new(math.max(0.5, width - frame * 2.2), math.max(0.5, height - frame * 2.2), paneDepth)
		frameHorizontalSize = Vector3.new(width, frame, frameDepth)
		frameVerticalSize = Vector3.new(frame, height, frameDepth)
		topBottomOffset = Vector3.new(0, height / 2 - frame / 2, 0)
		sideOffset = Vector3.new(width / 2 - frame / 2, 0, 0)
		exteriorSillSize = Vector3.new(width + 1.4, frame, frameDepth)
		exteriorSillOffset = Vector3.new(0, -height / 2 - frame * 0.7, thickness / 2 + frameDepth / 2 + 0.04)
	end

	addCreated(createdPaths, makePart(parent, name .. "_Glass", position, glassSize, Enum.Material.Glass, Color3.fromRGB(172, 225, 255), nil, {
		canCollide = false,
		transparency = 0.55,
	}))
	addCreated(createdPaths, makePart(parent, name .. "_FrameTop", position + topBottomOffset, frameHorizontalSize, Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, name .. "_FrameBottom", position - topBottomOffset, frameHorizontalSize, Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, name .. "_FrameA", position - sideOffset, frameVerticalSize, Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, name .. "_FrameB", position + sideOffset, frameVerticalSize, Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, name .. "_ExteriorSill", position + exteriorSillOffset, exteriorSillSize, Enum.Material.WoodPlanks, palette.accent))
end

local function createWallX(parent, name, basePosition, y, z, length, floorHeight, thickness, material, palette, openings, createdPaths)
	local startX = basePosition.X - length / 2
	local cursor = startX
	table.sort(openings, function(a, b)
		return a.offset < b.offset
	end)

	for _, opening in ipairs(openings) do
		local width = opening.width
		local openStart = basePosition.X + opening.offset - width / 2
		local openEnd = basePosition.X + opening.offset + width / 2
		makeWallSegment(parent, name .. "_Span_" .. opening.name, Vector3.new((cursor + openStart) / 2, y + floorHeight / 2, z), Vector3.new(openStart - cursor, floorHeight, thickness), material, palette.wall, createdPaths)
		local bottom = opening.bottom or floorHeight * 0.42
		local height = opening.height or floorHeight * 0.3
		local top = math.min(floorHeight, bottom + height)
		makeWallSegment(parent, name .. "_Below_" .. opening.name, Vector3.new((openStart + openEnd) / 2, y + bottom / 2, z), Vector3.new(width, bottom, thickness), material, palette.wall, createdPaths)
		makeWallSegment(parent, name .. "_Above_" .. opening.name, Vector3.new((openStart + openEnd) / 2, y + top + (floorHeight - top) / 2, z), Vector3.new(width, floorHeight - top, thickness), material, palette.wall, createdPaths)
		if opening.kind == "window" then
			createWindowAssembly(parent, name .. "_" .. opening.name, Vector3.new(basePosition.X + opening.offset, y + bottom + height / 2, z), width, height, thickness, "Z", palette, createdPaths)
		end
		cursor = openEnd
	end

	local endX = basePosition.X + length / 2
	makeWallSegment(parent, name .. "_Span_End", Vector3.new((cursor + endX) / 2, y + floorHeight / 2, z), Vector3.new(endX - cursor, floorHeight, thickness), material, palette.wall, createdPaths)
end

local function createWallZ(parent, name, basePosition, y, x, length, floorHeight, thickness, material, palette, openings, createdPaths)
	local startZ = basePosition.Z - length / 2
	local cursor = startZ
	table.sort(openings, function(a, b)
		return a.offset < b.offset
	end)

	for _, opening in ipairs(openings) do
		local width = opening.width
		local openStart = basePosition.Z + opening.offset - width / 2
		local openEnd = basePosition.Z + opening.offset + width / 2
		makeWallSegment(parent, name .. "_Span_" .. opening.name, Vector3.new(x, y + floorHeight / 2, (cursor + openStart) / 2), Vector3.new(thickness, floorHeight, openStart - cursor), material, palette.wall, createdPaths)
		local bottom = opening.bottom or floorHeight * 0.42
		local height = opening.height or floorHeight * 0.3
		local top = math.min(floorHeight, bottom + height)
		makeWallSegment(parent, name .. "_Below_" .. opening.name, Vector3.new(x, y + bottom / 2, (openStart + openEnd) / 2), Vector3.new(thickness, bottom, width), material, palette.wall, createdPaths)
		makeWallSegment(parent, name .. "_Above_" .. opening.name, Vector3.new(x, y + top + (floorHeight - top) / 2, (openStart + openEnd) / 2), Vector3.new(thickness, floorHeight - top, width), material, palette.wall, createdPaths)
		if opening.kind == "window" then
			createWindowAssembly(parent, name .. "_" .. opening.name, Vector3.new(x, y + bottom + height / 2, basePosition.Z + opening.offset), width, height, thickness, "X", palette, createdPaths)
		end
		cursor = openEnd
	end

	local endZ = basePosition.Z + length / 2
	makeWallSegment(parent, name .. "_Span_End", Vector3.new(x, y + floorHeight / 2, (cursor + endZ) / 2), Vector3.new(thickness, floorHeight, endZ - cursor), material, palette.wall, createdPaths)
end

local function createStairs(parent, basePosition, footprint, levels, floorHeight, palette, createdPaths)
	if levels < 2 then
		return
	end

	local stairFolder = Instance.new("Folder")
	stairFolder.Name = "InteriorStairwell"
	stairFolder.Parent = parent
	addCreated(createdPaths, stairFolder)

	local stairX = basePosition.X - footprint.X * 0.28
	local stairWidth = math.min(8, footprint.X * 0.25)
	local run = math.min(footprint.Z * 0.58, floorHeight * 1.9)
	local stepDepth = math.max(1.4, run / math.max(math.floor(floorHeight), 8))

	for level = 1, levels - 1 do
		local startY = basePosition.Y + (level - 1) * floorHeight + 0.75
		local endY = basePosition.Y + level * floorHeight + 0.75
		local startZ = basePosition.Z - footprint.Z * 0.28
		local endZ = startZ + run
		local stepCount = math.max(8, math.floor(floorHeight))

		addCreated(createdPaths, makePart(stairFolder, ("Landing_%02d_Lower"):format(level), Vector3.new(stairX, startY, startZ - 2.2), Vector3.new(stairWidth + 1.5, 0.65, 4.5), Enum.Material.WoodPlanks, palette.floor))
		addCreated(createdPaths, makePart(stairFolder, ("Landing_%02d_Upper"):format(level), Vector3.new(stairX, endY, endZ + 2.2), Vector3.new(stairWidth + 1.5, 0.65, 4.5), Enum.Material.WoodPlanks, palette.floor))
		for i = 1, stepCount do
			local t = (i - 0.5) / stepCount
			local y = startY + t * (endY - startY)
			local z = startZ + t * (endZ - startZ)
			addCreated(createdPaths, makePart(stairFolder, ("Stair_%02d_%02d"):format(level, i), Vector3.new(stairX, y, z), Vector3.new(stairWidth, 0.55, stepDepth + 0.15), Enum.Material.WoodPlanks, palette.trim))
			if i % 3 == 1 then
				addCreated(createdPaths, makePart(stairFolder, ("RailPost_%02d_%02d_L"):format(level, i), Vector3.new(stairX - stairWidth / 2 - 0.35, y + 1.6, z), Vector3.new(0.35, 3.2, 0.35), Enum.Material.WoodPlanks, palette.accent))
				addCreated(createdPaths, makePart(stairFolder, ("RailPost_%02d_%02d_R"):format(level, i), Vector3.new(stairX + stairWidth / 2 + 0.35, y + 1.6, z), Vector3.new(0.35, 3.2, 0.35), Enum.Material.WoodPlanks, palette.accent))
			end
		end
	end
end

local function createBalcony(parent, basePosition, y, footprint, palette, createdPaths)
	local deckWidth = math.min(math.max(footprint.X - 6, 10), 24)
	local deckDepth = 7
	local deckThickness = 0.8
	local wallZ = basePosition.Z + footprint.Z / 2
	local wallOverlap = 0.55
	local deckPosition = Vector3.new(basePosition.X, y + 0.15, wallZ + deckDepth / 2 - wallOverlap)
	addCreated(createdPaths, makePart(parent, "BalconyDeck", deckPosition, Vector3.new(deckWidth, deckThickness, deckDepth), Enum.Material.WoodPlanks, palette.accent))
	addCreated(createdPaths, makePart(parent, "BalconyLedger", Vector3.new(basePosition.X, y + 0.35, wallZ + 0.12), Vector3.new(deckWidth + 1.2, 0.65, 0.65), Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, "BalconyBackSeal", Vector3.new(basePosition.X, y - 0.3, wallZ + 0.08), Vector3.new(deckWidth + 1.2, 0.8, 0.65), Enum.Material.WoodPlanks, palette.accent))
	addCreated(createdPaths, makePart(parent, "BalconyRail_Front", deckPosition + Vector3.new(0, 2, deckDepth / 2 - 0.2), Vector3.new(deckWidth, 3, 0.45), Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, "BalconyRail_Left", deckPosition + Vector3.new(-deckWidth / 2 + 0.2, 2, 0), Vector3.new(0.45, 3, deckDepth), Enum.Material.WoodPlanks, palette.trim))
	addCreated(createdPaths, makePart(parent, "BalconyRail_Right", deckPosition + Vector3.new(deckWidth / 2 - 0.2, 2, 0), Vector3.new(0.45, 3, deckDepth), Enum.Material.WoodPlanks, palette.trim))

	local supportBottom = basePosition.Y - 0.5
	local supportTop = deckPosition.Y - deckThickness / 2
	local supportHeight = math.max(1, supportTop - supportBottom)
	for _, xOffset in ipairs({ -deckWidth / 2 + 1.2, deckWidth / 2 - 1.2 }) do
		addCreated(
			createdPaths,
			makePart(
				parent,
				xOffset < 0 and "BalconySupport_L" or "BalconySupport_R",
				Vector3.new(basePosition.X + xOffset, supportBottom + supportHeight / 2, deckPosition.Z + deckDepth / 2 - 0.9),
				Vector3.new(0.65, supportHeight, 0.65),
				Enum.Material.WoodPlanks,
				palette.trim
			)
		)
	end
end

local function createBuilding(mapRoot, building, palette, createdPaths)
	local model = Instance.new("Model")
	model.Name = Safety.sanitizeName(building.name or building.kind or "Structure")
	model.Parent = mapRoot
	addCreated(createdPaths, model)

	local position = vectorValue(building.position, Vector3.new(0, 8, 0))
	local footprint = vectorValue(building.size or building.footprint, Vector3.new(36, 20, 36))
	local levels = math.clamp(tonumber(building.levels or building.floorCount or 2) or 2, 1, 16)
	local floorHeight = math.clamp(tonumber(building.floorHeight) or 12, 6, 40)
	local material = materialByName(building.material, Enum.Material.Concrete)
	local balconyEvery = tonumber(building.balconyEvery) or 0
	local functionalCount = 0

	for level = 1, levels do
		local y = position.Y + (level - 1) * floorHeight
		local folder = Instance.new("Folder")
		folder.Name = ("Level_%02d"):format(level)
		folder.Parent = model
		addCreated(createdPaths, folder)
		createFloor(folder, position, y, footprint, palette, createdPaths, level > 1 and levels > 1)
		local windowHeight = math.min(4.6, floorHeight * 0.34)
		local windowBottom = math.max(3.8, floorHeight * 0.4)
		local windowWidth = math.min(5.8, footprint.X * 0.18)
		local northOpenings = {
			{ name = "WindowA", kind = "window", offset = -footprint.X * 0.24, width = windowWidth, bottom = windowBottom, height = windowHeight },
			{ name = "WindowB", kind = "window", offset = footprint.X * 0.24, width = windowWidth, bottom = windowBottom, height = windowHeight },
		}
		createWallX(folder, "NorthWall", position, y, position.Z - footprint.Z / 2, footprint.X, floorHeight, 1, material, palette, northOpenings, createdPaths)
		local hasBalcony = balconyEvery > 0 and level > 1 and level % balconyEvery == 0
		if level == 1 or hasBalcony then
			local doorWidth = math.min(8, footprint.X * 0.3)
			local doorHeight = math.min(7.5, floorHeight - 2)
			createWallX(folder, "SouthWall", position, y, position.Z + footprint.Z / 2, footprint.X, floorHeight, 1, material, palette, {
				{ name = "Door", kind = "door", offset = 0, width = doorWidth, bottom = 0, height = doorHeight },
				{ name = "WindowL", kind = "window", offset = -footprint.X * 0.32, width = math.min(4.8, windowWidth), bottom = windowBottom, height = windowHeight },
				{ name = "WindowR", kind = "window", offset = footprint.X * 0.32, width = math.min(4.8, windowWidth), bottom = windowBottom, height = windowHeight },
			}, createdPaths)
			addCreated(createdPaths, makePart(folder, hasBalcony and "BalconyDoorThreshold" or "DoorThreshold", Vector3.new(position.X, y + 0.15, position.Z + footprint.Z / 2 + 0.75), Vector3.new(doorWidth + 1, 0.3, 1.5), Enum.Material.WoodPlanks, palette.trim))
			createFunctionalDoor(
				folder,
				hasBalcony and "BalconyDoorPanel" or "FrontDoorPanel",
				Vector3.new(position.X, y + doorHeight / 2 + 0.05, position.Z + footprint.Z / 2),
				Vector3.new(doorWidth + 0.18, doorHeight + 0.1, 0.58),
				palette,
				createdPaths,
				{ promptText = hasBalcony and "Open Balcony" or "Open Door", openOffset = Vector3.new(doorWidth + 0.75, 0, 0), autoCloseSeconds = 5 }
			)
			functionalCount += 1
			if hasBalcony then
				createBalcony(folder, position, y, footprint, palette, createdPaths)
			end
		else
			createWallX(folder, "SouthWall", position, y, position.Z + footprint.Z / 2, footprint.X, floorHeight, 1, material, palette, northOpenings, createdPaths)
		end
		local sideWindowWidth = math.min(5.2, footprint.Z * 0.28)
		local sideOpenings = {
			{ name = "Window", kind = "window", offset = 0, width = sideWindowWidth, bottom = windowBottom, height = windowHeight },
		}
		createWallZ(folder, "WestWall", position, y, position.X - footprint.X / 2, footprint.Z, floorHeight, 1, material, palette, sideOpenings, createdPaths)
		createWallZ(folder, "EastWall", position, y, position.X + footprint.X / 2, footprint.Z, floorHeight, 1, material, palette, sideOpenings, createdPaths)
	end

	addCreated(createdPaths, makePart(model, "RoofDeck", Vector3.new(position.X, position.Y + levels * floorHeight + 1, position.Z), Vector3.new(footprint.X + 4, 1.2, footprint.Z + 4), Enum.Material.Concrete, palette.roof))
	createStairs(model, position, footprint, levels, floorHeight, palette, createdPaths)
	return functionalCount
end

local function anchorPosition(value, anchors, fallback)
	if typeof(value) == "string" and anchors[value] then
		return anchors[value]
	end
	return vectorValue(value, fallback)
end

local function createConnector(mapRoot, connector, palette, createdPaths, anchors)
	local from = anchorPosition(connector.from or connector.start, anchors, Vector3.new(0, 10, 0))
	local to = anchorPosition(connector.to or connector.finish, anchors, Vector3.new(24, 10, 0))
	local delta = to - from
	local length = math.max(delta.Magnitude, 1)
	local midpoint = from + delta / 2
	local cframe = CFrame.lookAt(midpoint, to) * CFrame.Angles(0, math.rad(90), 0)
	local width = tonumber(connector.width) or 8
	local kind = tostring(connector.kind or "bridge")
	local deck = addCreated(createdPaths, makePart(mapRoot, connector.name or kind or "Connector", midpoint, Vector3.new(length, 1, width), kind == "path" and Enum.Material.Cobblestone or Enum.Material.Metal, kind == "path" and palette.floor or palette.accent, cframe))
	local side = Vector3.new(-delta.Z, 0, delta.X)
	if side.Magnitude < 0.01 then
		side = Vector3.new(1, 0, 0)
	else
		side = side.Unit
	end
	for _, sign in ipairs({ -1, 1 }) do
		local offset = side * sign * (width / 2 + 0.35)
		local edgeMid = midpoint + offset + Vector3.new(0, 0.6, 0)
		local edgeTo = to + offset + Vector3.new(0, 0.6, 0)
		local edgeCFrame = CFrame.lookAt(edgeMid, edgeTo) * CFrame.Angles(0, math.rad(90), 0)
		addCreated(createdPaths, makePart(mapRoot, ("%s_Edge_%s"):format(deck.Name, sign < 0 and "L" or "R"), edgeMid, Vector3.new(length, kind == "path" and 0.55 or 2.2, 0.45), kind == "path" and Enum.Material.Slate or Enum.Material.WoodPlanks, kind == "path" and palette.trim or palette.roof, edgeCFrame))
	end
end

local function collectAnchors(sceneSpec)
	local anchors = {}
	for _, zone in ipairs(sceneSpec.zones or {}) do
		anchors[zone.name] = vectorValue(zone.position, Vector3.new(0, 8, 0))
	end
	for _, building in ipairs(sceneSpec.buildings or sceneSpec.structures or {}) do
		anchors[building.name] = vectorValue(building.position, Vector3.new(0, 8, 0))
	end
	for _, poi in ipairs(sceneSpec.pois or {}) do
		anchors[poi.name] = vectorValue(poi.position, Vector3.new(0, 12, 0))
	end
	return anchors
end

local function createPoi(mapRoot, poi, palette, createdPaths)
	local position = vectorValue(poi.position, Vector3.new(0, 12, 0))
	local size = vectorValue(poi.size, Vector3.new(14, 8, 14))
	if poi.kind == "spawn" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = Safety.sanitizeName(poi.name or "Spawn")
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Size = Vector3.new(size.X, 1, size.Z)
		spawn.Position = position
		spawn.Parent = mapRoot
		addCreated(createdPaths, spawn)
	else
		local folder = Instance.new("Folder")
		folder.Name = Safety.sanitizeName(poi.name or poi.kind or "PointOfInterest")
		folder.Parent = mapRoot
		addCreated(createdPaths, folder)
		local color = colorValue(poi.color, palette.accent)
		addCreated(createdPaths, makePart(folder, "LampPost", position + Vector3.new(0, -size.Y * 0.25, 0), Vector3.new(0.8, math.max(5, size.Y * 0.65), 0.8), Enum.Material.WoodPlanks, palette.roof))
		local glow = addCreated(createdPaths, makePart(folder, "GlowLamp", position + Vector3.new(0, size.Y * 0.18, 0), Vector3.new(math.min(3, size.X), math.min(3, size.Y), math.min(3, size.Z)), Enum.Material.Neon, color, nil, {
			canCollide = false,
			transparency = tonumber(poi.transparency) or 0.05,
		}))
		local light = Instance.new("PointLight")
		light.Name = "WarmPointLight"
		light.Brightness = tonumber(poi.brightness) or 1.8
		light.Range = tonumber(poi.range) or 22
		light.Color = color
		light.Parent = glow
		addCreated(createdPaths, light)
		addCreated(createdPaths, makePart(folder, "StoneBase", position + Vector3.new(0, -size.Y * 0.58, 0), Vector3.new(math.min(size.X, 5), 0.8, math.min(size.Z, 5)), Enum.Material.Slate, palette.trim))
	end
end

local function createFunctionalObject(mapRoot, objectSpec, palette, createdPaths)
	local folder = mapRoot:FindFirstChild("FunctionalObjects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "FunctionalObjects"
		folder.Parent = mapRoot
		addCreated(createdPaths, folder)
	end

	local kind = tostring(objectSpec.kind or "custom")
	local position = vectorValue(objectSpec.position, Vector3.new(0, 6, 0))
	local size = vectorValue(objectSpec.size, Vector3.new(6, 8, 1))
	local promptText = objectSpec.promptText or "Use"
	local openOffset = vectorValue(objectSpec.openOffset, kind == "elevator" and Vector3.new(0, 16, 0) or Vector3.new(size.X + 0.5, 0, 0))
	local part

	if kind == "door" then
		local target = resolveFunctionalTarget(mapRoot, objectSpec.target)
		if target and target:IsA("BasePart") then
			part = target
			markFunctionalPart(part, "SlidingDoor", promptText, {
				openOffset = openOffset,
				startsOpen = objectSpec.startsOpen,
				locked = objectSpec.locked,
				autoCloseSeconds = objectSpec.autoCloseSeconds,
			})
		else
			part = createFunctionalDoor(folder, objectSpec.name, position, size, palette, createdPaths, {
				promptText = promptText,
				openOffset = openOffset,
				startsOpen = objectSpec.startsOpen,
				locked = objectSpec.locked,
				autoCloseSeconds = objectSpec.autoCloseSeconds,
			})
		end
	elseif kind == "elevator" then
		part = addCreated(createdPaths, makePart(folder, objectSpec.name, position, size, Enum.Material.Metal, palette.accent))
		markFunctionalPart(part, "LiftPlatform", promptText, {
			openOffset = openOffset,
			startsOpen = objectSpec.startsOpen,
			locked = objectSpec.locked,
		})
	elseif kind == "teleporter" then
		part = addCreated(createdPaths, makePart(folder, objectSpec.name, position, size, Enum.Material.Neon, palette.accent, nil, {
			canCollide = false,
			transparency = 0.15,
		}))
		markFunctionalPart(part, "TeleporterPad", promptText, {
			targetPosition = vectorValue(objectSpec.targetPosition, position + Vector3.new(0, 8, 0)),
			locked = objectSpec.locked,
		})
	elseif kind == "button" or kind == "lever" then
		part = addCreated(createdPaths, makePart(folder, objectSpec.name, position, size, Enum.Material.Metal, palette.trim))
		markFunctionalPart(part, "ToggleButton", promptText, {
			targetName = objectSpec.target,
			locked = objectSpec.locked,
		})
	elseif kind == "checkpoint" then
		part = Instance.new("SpawnLocation")
		part.Name = Safety.sanitizeName(objectSpec.name)
		part.Anchored = true
		part.Neutral = true
		part.Size = Vector3.new(size.X, math.max(0.4, size.Y), size.Z)
		part.Position = position
		part.Color = palette.accent
		part.Parent = folder
		addCreated(createdPaths, part)
	else
		part = addCreated(createdPaths, makePart(folder, objectSpec.name, position, size, Enum.Material.SmoothPlastic, palette.accent))
		part:SetAttribute("BridgeFunctionalKind", "Custom")
	end

	return part and 1 or 0
end

local function vectorOrNil(value)
	if value == nil then
		return nil
	end
	if typeof(value) == "Vector3" then
		return value
	elseif typeof(value) == "table" and value.type == "Vector3" then
		return InstanceSerializer.deserialize(value)
	elseif typeof(value) == "table" and #value >= 3 then
		return Vector3.new(value[1], value[2], value[3])
	end
	return nil
end

local function writeVectorLike(original, vector)
	if typeof(original) == "table" and original.type == "Vector3" then
		original.value = { vector.X, vector.Y, vector.Z }
		return original
	elseif typeof(original) == "table" and #original >= 3 then
		original[1] = vector.X
		original[2] = vector.Y
		original[3] = vector.Z
		return original
	end
	return { type = "Vector3", value = { vector.X, vector.Y, vector.Z } }
end

local function shiftVectorField(container, field, deltaY)
	if not container or not container[field] then
		return
	end
	local vector = vectorOrNil(container[field])
	if not vector then
		return
	end
	container[field] = writeVectorLike(container[field], vector + Vector3.new(0, deltaY, 0))
end

local function instanceFrame(properties)
	local frame = properties.CFrame and InstanceSerializer.deserialize(properties.CFrame)
	local position = vectorOrNil(properties.Position)
	if typeof(frame) == "CFrame" then
		return frame
	end
	return position and CFrame.new(position) or nil
end

local function minSceneBottom(sceneSpec)
	local minimum = math.huge
	local function consider(bottom)
		if bottom and bottom < minimum then
			minimum = bottom
		end
	end

	for _, zone in ipairs(sceneSpec.zones or {}) do
		local position = vectorOrNil(zone.position)
		local size = vectorOrNil(zone.size)
		if position and size then
			consider(position.Y - size.Y / 2)
		end
	end
	for _, instanceSpec in ipairs(sceneSpec.instances or {}) do
		local properties = instanceSpec.properties or {}
		local frame = instanceFrame(properties)
		local size = vectorOrNil(properties.Size)
		if frame and size then
			local halfHeight = (math.abs(frame.RightVector.Y) * size.X
				+ math.abs(frame.UpVector.Y) * size.Y
				+ math.abs(frame.LookVector.Y) * size.Z) / 2
			consider(frame.Position.Y - halfHeight)
		end
	end
	for _, building in ipairs(sceneSpec.buildings or sceneSpec.structures or {}) do
		local position = vectorOrNil(building.position) or Vector3.new(0, 8, 0)
		consider(position.Y - 0.5)
	end
	for _, poi in ipairs(sceneSpec.pois or {}) do
		local position = vectorOrNil(poi.position)
		local size = vectorOrNil(poi.size) or Vector3.new(14, 8, 14)
		if position then
			consider(position.Y - size.Y / 2)
		end
	end
	for _, objectSpec in ipairs(sceneSpec.functionalObjects or {}) do
		local position = vectorOrNil(objectSpec.position)
		local size = vectorOrNil(objectSpec.size) or Vector3.new(6, 8, 1)
		if position then
			consider(position.Y - size.Y / 2)
		end
	end

	if minimum == math.huge then
		return nil
	end
	return minimum
end

local function sceneProbeCenter(sceneSpec)
	if sceneSpec.layout and sceneSpec.layout.origin then
		local origin = vectorOrNil(sceneSpec.layout.origin)
		if origin then
			return origin
		end
	end
	for _, building in ipairs(sceneSpec.buildings or sceneSpec.structures or {}) do
		local position = vectorOrNil(building.position)
		if position then
			return position
		end
	end
	for _, instanceSpec in ipairs(sceneSpec.instances or {}) do
		local frame = instanceFrame(instanceSpec.properties or {})
		if frame then
			return frame.Position
		end
	end
	for _, poi in ipairs(sceneSpec.pois or {}) do
		local position = vectorOrNil(poi.position)
		if position then
			return position
		end
	end
	return Vector3.new(0, 0, 0)
end

local function raycastGroundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored = {}
	for rootPath in pairs(Safety.SafeRoots) do
		local instance = InstanceSerializer.resolve(rootPath)
		if instance then
			table.insert(ignored, instance)
		end
	end
	params.FilterDescendantsInstances = ignored
	local result = Workspace:Raycast(Vector3.new(x, 2048, z), Vector3.new(0, -4096, 0), params)
	if result then
		return result.Position.Y
	end
	return nil
end

local function groundSceneSpec(sceneSpec)
	local layout = sceneSpec.layout or {}
	local grounding = layout.grounding or {}
	local mode = tostring(grounding.mode or "raycast")
	if mode == "none" then
		return nil
	end

	local bottom = minSceneBottom(sceneSpec)
	if not bottom then
		return nil
	end

	local probe = sceneProbeCenter(sceneSpec)
	local layoutSize = vectorOrNil(layout.size)
	local highestGround = nil
	local samples = { probe }
	if layoutSize then
		table.insert(samples, probe + Vector3.new(layoutSize.X / 2, 0, layoutSize.Z / 2))
		table.insert(samples, probe + Vector3.new(-layoutSize.X / 2, 0, layoutSize.Z / 2))
		table.insert(samples, probe + Vector3.new(layoutSize.X / 2, 0, -layoutSize.Z / 2))
		table.insert(samples, probe + Vector3.new(-layoutSize.X / 2, 0, -layoutSize.Z / 2))
	end
	for _, sample in ipairs(samples) do
		local groundY = tonumber(grounding.groundY) or raycastGroundY(sample.X, sample.Z)
		if groundY and (not highestGround or groundY > highestGround) then
			highestGround = groundY
		end
	end
	if not highestGround then
		highestGround = tonumber(grounding.groundY) or 0
	end

	local clearance = tonumber(grounding.clearance) or 0.05
	local deltaY = highestGround + clearance - bottom
	if math.abs(deltaY) < 0.001 then
		return { groundY = highestGround, deltaY = 0, bottomY = bottom }
	end

	for _, zone in ipairs(sceneSpec.zones or {}) do
		shiftVectorField(zone, "position", deltaY)
	end
	for _, instanceSpec in ipairs(sceneSpec.instances or {}) do
		if instanceSpec.properties then
			shiftVectorField(instanceSpec.properties, "Position", deltaY)
			if instanceSpec.properties.CFrame then
				local frame = InstanceSerializer.deserialize(instanceSpec.properties.CFrame)
				instanceSpec.properties.CFrame = InstanceSerializer.serialize(frame + Vector3.new(0, deltaY, 0))
			end
		end
	end
	for _, building in ipairs(sceneSpec.buildings or sceneSpec.structures or {}) do
		shiftVectorField(building, "position", deltaY)
	end
	for _, poi in ipairs(sceneSpec.pois or {}) do
		shiftVectorField(poi, "position", deltaY)
	end
	for _, objectSpec in ipairs(sceneSpec.functionalObjects or {}) do
		shiftVectorField(objectSpec, "position", deltaY)
		shiftVectorField(objectSpec, "targetPosition", deltaY)
	end
	for _, connector in ipairs(sceneSpec.connectors or sceneSpec.paths or {}) do
		shiftVectorField(connector, "from", deltaY)
		shiftVectorField(connector, "to", deltaY)
		shiftVectorField(connector, "start", deltaY)
		shiftVectorField(connector, "finish", deltaY)
	end
	if sceneSpec.layout then
		shiftVectorField(sceneSpec.layout, "origin", deltaY)
	end
	return { groundY = highestGround, deltaY = deltaY, bottomY = bottom + deltaY }
end

local function countHighLevel(sceneSpec)
	local count = 0
	for _, building in ipairs(sceneSpec.buildings or sceneSpec.structures or {}) do
		count += 8 + (tonumber(building.levels or building.floorCount or 2) or 2) * 7
	end
	count += #(sceneSpec.pois or {}) * 2
	count += #(sceneSpec.connectors or sceneSpec.paths or {}) * 4
	count += #(sceneSpec.functionalObjects or {}) * 4
	return count
end

function SceneApplier.plan(sceneSpec)
	local count = 2 + #(sceneSpec.zones or {}) + #(sceneSpec.instances or {}) + #(sceneSpec.scripts or {}) + countHighLevel(sceneSpec)
	if sceneSpec.terrain and sceneSpec.terrain.enabled then
		count += 1
	end

	return {
		mapName = sceneSpec.mapName,
		targetRoot = ("%s/%s_<timestamp>"):format(sceneSpec.rootPath or Safety.GeneratedRoot, sceneSpec.mapName),
		objectCount = count,
		servicesTouched = { "Workspace" },
	}
end

function SceneApplier.apply(sceneSpec, dryRun)
	if dryRun then
		return SceneApplier.plan(sceneSpec)
	end

	local generatedRoot = InstanceSerializer.ensureFolder(sceneSpec.rootPath or Safety.GeneratedRoot)
	local mapRootName = ("%s_%s"):format(Safety.safeMapName(sceneSpec.mapName), timestamp())
	local mapRoot = Instance.new("Folder")
	mapRoot.Name = mapRootName
	mapRoot:SetAttribute("BridgeManaged", true)
	mapRoot:SetAttribute("BridgeSchemaVersion", tonumber(sceneSpec.version) or 1)
	mapRoot:SetAttribute("BridgeRoot", sceneSpec.rootPath or Safety.GeneratedRoot)
	mapRoot.Parent = generatedRoot

	local createdPaths = { InstanceSerializer.pathOf(mapRoot) }
	local zonesFolder = Instance.new("Folder")
	zonesFolder.Name = "Zones"
	zonesFolder.Parent = mapRoot
	table.insert(createdPaths, InstanceSerializer.pathOf(zonesFolder))
	local createdInstances = {}
	local groundingInfo
	local instancesOk, instancesError = pcall(function()
		groundingInfo = groundSceneSpec(sceneSpec)
		for _, zone in ipairs(sceneSpec.zones or {}) do
			createZone(zone, zonesFolder, createdPaths)
		end
		local pendingInstances = sceneSpec.instances or {}
		while #pendingInstances > 0 do
			local unresolved = {}
			for _, instanceSpec in ipairs(pendingInstances) do
				local parent = resolveParent(instanceSpec.parentPath, mapRoot)
				if parent then
					if not sceneSpec.allowExistingEdit then
						Safety.assertGeneratedPath(InstanceSerializer.pathOf(parent))
					end
					table.insert(createdInstances, createSpecInstance(instanceSpec, parent, createdPaths))
				else
					table.insert(unresolved, instanceSpec)
				end
			end
			if #unresolved == #pendingInstances then
				error(("Missing or cyclic parent path: %s"):format(tostring(unresolved[1].parentPath)))
			end
			pendingInstances = unresolved
		end
	end)
	if not instancesOk then
		for _, instance in ipairs(createdInstances) do
			if instance.Parent then
				instance:Destroy()
			end
		end
		mapRoot:Destroy()
		error(instancesError, 0)
	end
	applyLighting(sceneSpec.lighting)

	local palette = paletteFor(sceneSpec)
	local anchors = collectAnchors(sceneSpec)
	local functionalCount = 0
	for _, building in ipairs(sceneSpec.buildings or sceneSpec.structures or {}) do
		functionalCount += createBuilding(mapRoot, building, palette, createdPaths)
	end
	for _, connector in ipairs(sceneSpec.connectors or sceneSpec.paths or {}) do
		createConnector(mapRoot, connector, palette, createdPaths, anchors)
	end
	for _, poi in ipairs(sceneSpec.pois or {}) do
		createPoi(mapRoot, poi, palette, createdPaths)
	end
	for _, objectSpec in ipairs(sceneSpec.functionalObjects or {}) do
		functionalCount += createFunctionalObject(mapRoot, objectSpec, palette, createdPaths)
	end

	local terrainResult = nil
	if sceneSpec.terrain and sceneSpec.terrain.enabled then
		terrainResult = TerrainGenerator.generate({
			parentFolder = InstanceSerializer.pathOf(mapRoot),
			size = sceneSpec.terrain.size,
			seed = sceneSpec.terrain.seed,
			biome = sceneSpec.terrain.biome,
			heightNoise = sceneSpec.terrain.heightNoise,
			water = sceneSpec.terrain.water,
			caves = sceneSpec.terrain.caves,
			paths = sceneSpec.terrain.paths,
		})
	end

	for _, scriptSpec in ipairs(sceneSpec.scripts or {}) do
		createScript(scriptSpec, mapRootName, createdPaths)
	end
	if functionalCount > 0 then
		createRuntimeScript(mapRootName, InstanceSerializer.pathOf(mapRoot), createdPaths)
	end

	local manifest = Instance.new("StringValue")
	manifest.Name = "SceneManifest"
	manifest.Value = HttpService:JSONEncode({
		createdAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		schemaVersion = tonumber(sceneSpec.version) or 1,
		mapRootPath = InstanceSerializer.pathOf(mapRoot),
		createdPaths = createdPaths,
		sceneSpec = sceneSpec,
		terrain = terrainResult,
		grounding = groundingInfo,
		functionalObjectCount = functionalCount,
	})
	manifest.Parent = mapRoot
	table.insert(createdPaths, InstanceSerializer.pathOf(manifest))

	return {
		ok = true,
		mapRootPath = InstanceSerializer.pathOf(mapRoot),
		createdPaths = createdPaths,
		terrain = terrainResult,
		functionalObjectCount = functionalCount,
	}
end

function SceneApplier.refineVisuals(args)
	local mapRoot = InstanceSerializer.resolve(args.mapRootPath)
	if not mapRoot then
		error("mapRootPath not found")
	end
	Safety.assertGeneratedPath(InstanceSerializer.pathOf(mapRoot))

	local style = args.style or "lowpoly"
	local changed = 0
	for _, descendant in ipairs(mapRoot:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if style == "lowpoly" or style == "obby" then
				descendant.Material = Enum.Material.SmoothPlastic
			elseif style == "medieval" then
				descendant.Material = Enum.Material.Slate
			elseif style == "sci-fi" then
				descendant.Material = Enum.Material.Neon
			else
				descendant.Material = Enum.Material.Concrete
			end
			changed += 1
		end
	end

	return {
		ok = true,
		changed = changed,
		layoutChanged = false,
	}
end

local function lowerName(instance)
	return string.lower(instance.Name)
end

local function partBottom(part)
	return part.Position.Y - part.Size.Y / 2
end

local function partTop(part)
	return part.Position.Y + part.Size.Y / 2
end

local function overlaps1D(aMin, aMax, bMin, bMax)
	return math.min(aMax, bMax) - math.max(aMin, bMin)
end

local function horizontalContains(part, point)
	local half = part.Size / 2
	return math.abs(part.Position.X - point.X) <= half.X and math.abs(part.Position.Z - point.Z) <= half.Z
end

local function isGroundAllowance(part)
	local name = lowerName(part)
	return name:find("lot", 1, true)
		or name:find("foundation", 1, true)
		or name:find("retaining", 1, true)
		or name:find("support", 1, true)
		or name:find("post", 1, true)
end

local function isPlayerSurface(part)
	local name = lowerName(part)
	return name:find("floor", 1, true)
		or name:find("deck", 1, true)
		or name:find("path", 1, true)
		or name:find("porch", 1, true)
		or name:find("balcony", 1, true)
		or name:find("stair", 1, true)
		or name:find("landing", 1, true)
		or name:find("door", 1, true)
end

local function isStairPart(part)
	local name = lowerName(part)
	return name:find("stair", 1, true) and not name:find("trim", 1, true) and not name:find("rail", 1, true)
end

local function isWalkableLanding(part)
	local name = lowerName(part)
	return name:find("landing", 1, true) or name:find("floor", 1, true) or name:find("deck", 1, true)
end

local function isOverlapAllowance(part)
	local name = lowerName(part)
	return name:find("seal", 1, true)
		or name:find("trim", 1, true)
		or name:find("frame", 1, true)
		or name:find("sill", 1, true)
		or name:find("rail", 1, true)
		or name:find("support", 1, true)
		or name:find("post", 1, true)
		or name:find("doorpanel", 1, true)
end

local function collectBaseParts(root)
	local parts = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function validateTerrainClearance(parts, errors, warnings, args)
	local clearance = tonumber(args.terrainClearance) or 0.2
	for _, part in ipairs(parts) do
		if not isGroundAllowance(part) then
			local groundY = raycastGroundY(part.Position.X, part.Position.Z)
			if groundY and groundY > partBottom(part) + clearance then
				local message = ("%s intersects terrain/ground by %.2f studs"):format(InstanceSerializer.pathOf(part), groundY - partBottom(part))
				if isPlayerSurface(part) then
					table.insert(errors, message)
				else
					table.insert(warnings, message)
				end
			end
		end
	end
end

local function validateStairRoute(parts, errors)
	local topStair = nil
	for _, part in ipairs(parts) do
		if isStairPart(part) and (not topStair or partTop(part) > partTop(topStair)) then
			topStair = part
		end
	end
	if not topStair then
		return
	end

	local stairTop = partTop(topStair)
	local hasLanding = false
	for _, part in ipairs(parts) do
		if part ~= topStair and isWalkableLanding(part) and math.abs(partTop(part) - stairTop) <= 1.3 then
			local dx = math.abs(part.Position.X - topStair.Position.X)
			local dz = math.abs(part.Position.Z - topStair.Position.Z)
			if dx <= math.max(part.Size.X, topStair.Size.X) and dz <= math.max(part.Size.Z, topStair.Size.Z) + 8 then
				hasLanding = true
				break
			end
		end
	end
	if not hasLanding then
		table.insert(errors, "Highest stair has no reachable upper landing near " .. InstanceSerializer.pathOf(topStair))
	end

	for _, part in ipairs(parts) do
		if part ~= topStair and not isStairPart(part) and horizontalContains(part, topStair.Position) then
			local clearance = partBottom(part) - stairTop
			if clearance > 0 and clearance < 5 then
				table.insert(errors, ("Stair headroom blocked by %s, clearance %.2f studs"):format(InstanceSerializer.pathOf(part), clearance))
			end
		end
	end
end

local function validateAllStairHeadroom(parts, errors)
	for _, stair in ipairs(parts) do
		if isStairPart(stair) then
			for _, part in ipairs(parts) do
				if part ~= stair and not isStairPart(part) and not isOverlapAllowance(part) and horizontalContains(part, stair.Position) then
					local clearance = partBottom(part) - partTop(stair)
					if clearance > 0 and clearance < 5 then
						table.insert(errors, ("Stair headroom blocked by %s above %s, clearance %.2f studs"):format(InstanceSerializer.pathOf(part), InstanceSerializer.pathOf(stair), clearance))
						break
					end
				end
			end
		end
	end
end

local function validatePartOverlap(parts, warnings, args)
	local maxWarnings = tonumber(args.maxOverlapWarnings) or 40
	for i = 1, #parts do
		local a = parts[i]
		if not isOverlapAllowance(a) then
			for j = i + 1, #parts do
				local b = parts[j]
				if not isOverlapAllowance(b) then
					local overlapX = overlaps1D(a.Position.X - a.Size.X / 2, a.Position.X + a.Size.X / 2, b.Position.X - b.Size.X / 2, b.Position.X + b.Size.X / 2)
					local overlapY = overlaps1D(a.Position.Y - a.Size.Y / 2, a.Position.Y + a.Size.Y / 2, b.Position.Y - b.Size.Y / 2, b.Position.Y + b.Size.Y / 2)
					local overlapZ = overlaps1D(a.Position.Z - a.Size.Z / 2, a.Position.Z + a.Size.Z / 2, b.Position.Z - b.Size.Z / 2, b.Position.Z + b.Size.Z / 2)
					if overlapX > 0.08 and overlapY > 0.08 and overlapZ > 0.08 then
						table.insert(warnings, ("Solid overlap may clip/z-fight: %s <-> %s"):format(InstanceSerializer.pathOf(a), InstanceSerializer.pathOf(b)))
						if #warnings >= maxWarnings then
							return
						end
					end
				end
			end
		end
	end
end

local function findPartByName(root, name)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == name and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function partOverlapX(a, b)
	return overlaps1D(a.Position.X - a.Size.X / 2, a.Position.X + a.Size.X / 2, b.Position.X - b.Size.X / 2, b.Position.X + b.Size.X / 2)
end

local function partOverlapY(a, b)
	return overlaps1D(a.Position.Y - a.Size.Y / 2, a.Position.Y + a.Size.Y / 2, b.Position.Y - b.Size.Y / 2, b.Position.Y + b.Size.Y / 2)
end

local function partOverlapZ(a, b)
	return overlaps1D(a.Position.Z - a.Size.Z / 2, a.Position.Z + a.Size.Z / 2, b.Position.Z - b.Size.Z / 2, b.Position.Z + b.Size.Z / 2)
end

local function isDoorBlocker(part)
	local name = lowerName(part)
	return not (
		name:find("trim", 1, true)
		or name:find("threshold", 1, true)
		or name:find("sill", 1, true)
		or name:find("frame", 1, true)
	)
end

local function blocksDoorOpening(door, part)
	if part == door or not isDoorBlocker(part) or part.Transparency >= 0.95 then
		return false
	end
	return partOverlapX(door, part) >= door.Size.X * 0.45
		and partOverlapY(door, part) >= door.Size.Y * 0.35
		and partOverlapZ(door, part) > 0.05
end

local function validateDoorReadiness(root, parts, doorName, errors)
	local door = findPartByName(root, doorName)
	if not door then
		table.insert(errors, "Missing house door part: " .. doorName)
		return nil
	end
	if door:GetAttribute("BridgeFunctionalKind") ~= "SlidingDoor" then
		table.insert(errors, doorName .. " is not bound as a SlidingDoor functional part")
	end
	if not door:FindFirstChildWhichIsA("ProximityPrompt", true) then
		table.insert(errors, doorName .. " has no ProximityPrompt")
	end
	local offset = door:GetAttribute("OpenOffset")
	if typeof(offset) ~= "Vector3" or offset.Magnitude < 2 then
		table.insert(errors, doorName .. " has no usable OpenOffset")
	end
	for _, part in ipairs(parts) do
		if blocksDoorOpening(door, part) then
			table.insert(errors, ("%s doorway is blocked by %s"):format(doorName, InstanceSerializer.pathOf(part)))
		end
	end
	return door
end

local function validateBalconyReadiness(root, parts, door, errors)
	if not door then
		return
	end
	local deck = findPartByName(root, "BalconyDeck_Supported")
	if not deck then
		table.insert(errors, "Missing BalconyDeck_Supported")
		return
	end
	if deck.Position.Z >= door.Position.Z - 0.5 then
		table.insert(errors, "Balcony deck is not outside the balcony door/front facade")
	end
	if partOverlapX(deck, door) < door.Size.X * 0.7 then
		table.insert(errors, "Balcony deck does not overlap the balcony doorway enough to be reachable")
	end
	if math.abs(partTop(deck) - partBottom(door)) > 1.2 then
		table.insert(errors, "Balcony deck height is not aligned with the balcony doorway")
	end
	for _, railName in ipairs({ "BalconyRail_Front", "BalconyRail_L", "BalconyRail_R" }) do
		local rail = findPartByName(root, railName)
		if not rail then
			table.insert(errors, "Missing balcony rail part: " .. railName)
		elseif blocksDoorOpening(door, rail) then
			table.insert(errors, railName .. " crosses the balcony doorway")
		end
	end
	local frontRail = findPartByName(root, "BalconyRail_Front")
	if frontRail and frontRail.Position.Z >= deck.Position.Z then
		table.insert(errors, "Balcony front rail is not on the outside edge of the balcony deck")
	end
	for _, supportName in ipairs({ "BalconySupport_L", "BalconySupport_R" }) do
		local support = findPartByName(root, supportName)
		if not support then
			table.insert(errors, "Missing balcony support: " .. supportName)
		elseif math.abs(partTop(support) - partBottom(deck)) > 1.1 then
			table.insert(errors, supportName .. " does not support the balcony deck")
		end
	end
end

local function validateRoofReadiness(root, parts, errors)
	local roof = findPartByName(root, "RoofDeck") or findPartByName(root, "RoofDeck_Front") or findPartByName(root, "RoofPanel_Front")
	if not roof then
		table.insert(errors, "Missing roof deck/panel")
		return
	end
	for _, part in ipairs(parts) do
		local name = lowerName(part)
		if name:find("roofcap", 1, true) and part.Size.X > roof.Size.X * 0.4 and part.Size.Z > roof.Size.Z * 0.4 then
			table.insert(errors, "Unexpected roof cap slab overlaps the main roof: " .. InstanceSerializer.pathOf(part))
		end
	end
	local ridge = findPartByName(root, "RoofRidge")
	if ridge and partBottom(ridge) < partTop(roof) - 0.15 then
		table.insert(errors, "RoofRidge clips into RoofDeck")
	end
	local chimney = findPartByName(root, "ChimneyStack")
	if chimney and partBottom(chimney) > partTop(roof) + 1.5 then
		table.insert(errors, "ChimneyStack floats above RoofDeck")
	end
end

local function isRoofClosureForSide(part, side)
	local name = lowerName(part)
	if not (name:find(side, 1, true) and (name:find("roofgap", 1, true) or name:find("gable", 1, true))) then
		return false
	end
	return part.Size.X >= 4 and part.Size.Y >= 0.2
end

local function validateRoofClosureReadiness(parts, side, errors)
	local found = 0
	local widest = 0
	local deepest = 0
	local tallest = 0
	for _, part in ipairs(parts) do
		if isRoofClosureForSide(part, side) then
			found += 1
			widest = math.max(widest, part.Size.X)
			deepest = math.max(deepest, part.Size.Z)
			tallest = math.max(tallest, part.Size.Y)
		end
	end

	if found == 0 then
		table.insert(errors, ("Missing %s roof/gable closure seal"):format(side))
	elseif widest < 18 then
		table.insert(errors, ("%s roof/gable closure seal is too narrow"):format(side))
	elseif deepest < 0.6 then
		table.insert(errors, ("%s roof/gable closure seal is too shallow and can leave a visible sky gap"):format(side))
	elseif tallest < 0.35 then
		table.insert(errors, ("%s roof/gable closure seal is too thin to hide the eave gap"):format(side))
	end
end

local function isFloorLike(part)
	local name = lowerName(part)
	return name:find("floor", 1, true) or name:find("landing", 1, true) or name:find("deck", 1, true)
end

local function isGroundOrFoundationLike(part)
	local name = lowerName(part)
	return name:find("lot", 1, true)
		or name:find("grass", 1, true)
		or name:find("ground", 1, true)
		or name:find("foundation", 1, true)
end

local function overlapAreaRatio(a, b)
	local overlapX = partOverlapX(a, b)
	local overlapZ = partOverlapZ(a, b)
	if overlapX <= 0 or overlapZ <= 0 then
		return 0
	end
	local area = math.min(a.Size.X * a.Size.Z, b.Size.X * b.Size.Z)
	if area <= 0 then
		return 0
	end
	return (overlapX * overlapZ) / area
end

local function validateFloorSeparation(parts, errors)
	for _, floor in ipairs(parts) do
		if isFloorLike(floor) then
			for _, base in ipairs(parts) do
				if base ~= floor and isGroundOrFoundationLike(base) and overlapAreaRatio(floor, base) > 0.35 then
					local gap = partBottom(floor) - partTop(base)
					if gap < 0.08 then
						table.insert(errors, ("%s is embedded in or coplanar with %s; raise finished floor or lower foundation"):format(InstanceSerializer.pathOf(floor), InstanceSerializer.pathOf(base)))
					end
				end
			end
		end
	end
end

local function partBounds(part)
	return {
		minX = part.Position.X - part.Size.X / 2,
		maxX = part.Position.X + part.Size.X / 2,
		minZ = part.Position.Z - part.Size.Z / 2,
		maxZ = part.Position.Z + part.Size.Z / 2,
	}
end

local function findLotPart(parts)
	local best = nil
	for _, part in ipairs(parts) do
		local name = lowerName(part)
		if name:find("lot", 1, true) or name:find("groundedgrass", 1, true) then
			if not best or part.Size.X * part.Size.Z > best.Size.X * best.Size.Z then
				best = part
			end
		end
	end
	return best
end

local function isPathLike(part)
	local name = lowerName(part)
	return name:find("path", 1, true)
		or name:find("walk", 1, true)
		or name:find("sidewalk", 1, true)
		or part:IsA("SpawnLocation")
end

local function validatePathWithinLotBounds(parts, errors)
	local lot = findLotPart(parts)
	if not lot then
		return
	end
	local lotBounds = partBounds(lot)
	local tolerance = 0.25
	for _, part in ipairs(parts) do
		if part ~= lot and isPathLike(part) then
			local bounds = partBounds(part)
			if bounds.minX < lotBounds.minX - tolerance
				or bounds.maxX > lotBounds.maxX + tolerance
				or bounds.minZ < lotBounds.minZ - tolerance
				or bounds.maxZ > lotBounds.maxZ + tolerance then
				table.insert(errors, ("%s extends outside lot bounds"):format(InstanceSerializer.pathOf(part)))
			end
		end
	end
end

local function validateVisibleMapVersion(root, args, errors)
	local expected = args.expectedMapVersion
	if not expected or expected == "" then
		expected = tostring(root.Name):match("(V%d+)")
	end
	if not expected or expected == "" or args.requireVisibleVersion == false then
		return
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		local ok, text = pcall(function()
			return descendant.Text
		end)
		if descendant.Name:find(expected, 1, true) or (ok and tostring(text):find(expected, 1, true)) then
			if descendant:IsA("BasePart") then
				if descendant.Transparency < 0.95 then
					return
				end
			else
				return
			end
		end
	end
	table.insert(errors, "Missing visible map version marker for " .. expected)
end

function SceneApplier.readiness(args)
	local root = InstanceSerializer.resolve(args.rootPath or Safety.GeneratedRoot)
	if not root then
		return {
			ok = false,
			errors = { "Root path not found" },
			warnings = {},
			checks = {},
		}
	end

	local errors = {}
	local warnings = {}
	local checks = {}
	local parts = collectBaseParts(root)
	validateAllStairHeadroom(parts, errors)
	validateFloorSeparation(parts, errors)
	validatePathWithinLotBounds(parts, errors)
	validateVisibleMapVersion(root, args, errors)
	table.insert(checks, "stair-headroom")
	table.insert(checks, "floor-separation")
	table.insert(checks, "path-lot-bounds")
	table.insert(checks, "visible-map-version")

	if (args.profile or "generic") == "house" then
		local frontDoor = validateDoorReadiness(root, parts, "FrontDoorPanel", errors)
		local balconyDoor = validateDoorReadiness(root, parts, "BalconyDoorPanel", errors)
		validateBalconyReadiness(root, parts, balconyDoor, errors)
		validateRoofReadiness(root, parts, errors)
		validateRoofClosureReadiness(parts, "front", errors)
		validateRoofClosureReadiness(parts, "back", errors)
		if frontDoor and balconyDoor and math.abs(frontDoor.Position.Z - balconyDoor.Position.Z) > 1.25 then
			table.insert(errors, "Front and balcony doors are not on the same facade plane")
		end
		table.insert(checks, "house-doors")
		table.insert(checks, "house-balcony")
		table.insert(checks, "house-roof")
	end

	return {
		ok = #errors == 0,
		errors = errors,
		warnings = warnings,
		checks = checks,
		objectCount = #parts,
	}
end

function SceneApplier.validate(args)
	local root = InstanceSerializer.resolve(args.rootPath or Safety.GeneratedRoot)
	if not root then
		return {
			ok = false,
			errors = { "Root path not found" },
			warnings = {},
		}
	end

	local warnings = {}
	local errors = {}
	local spawnCount = 0
	local objectCount = 0
	local parts = collectBaseParts(root)

	for _, descendant in ipairs(root:GetDescendants()) do
		objectCount += 1
		local path = InstanceSerializer.pathOf(descendant)
		if not Safety.isManagedPath(path) then
			table.insert(errors, "Managed object outside safe build roots: " .. path)
		end

		if descendant:IsA("SpawnLocation") then
			spawnCount += 1
		end
		if descendant:IsA("BasePart") and not descendant.Anchored and not descendant:GetAttribute("AllowUnanchored") then
			table.insert(warnings, "Unanchored part: " .. path)
		end
	end
	if args.strictGeometry ~= false then
		validateTerrainClearance(parts, errors, warnings, args)
		validateStairRoute(parts, errors)
		validateAllStairHeadroom(parts, errors)
		validatePartOverlap(parts, warnings, args)
	end

	if spawnCount == 0 then
		table.insert(errors, "No SpawnLocation found")
	end
	if (args.rootPath or Safety.GeneratedRoot) == Safety.LegacyRoot then
		table.insert(warnings, "Legacy root Workspace/AI_Generated is accepted; new maps use Workspace/MapDrafts")
	end

	local maxObjects = args.maxObjects or 1000
	if objectCount > maxObjects then
		table.insert(warnings, ("Object count %d exceeds %d"):format(objectCount, maxObjects))
	end

	return {
		ok = #errors == 0,
		errors = errors,
		warnings = warnings,
		objectCount = objectCount,
		spawnCount = spawnCount,
	}
end

return SceneApplier
