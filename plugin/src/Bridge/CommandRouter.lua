local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")

local InstanceSerializer = require(script.Parent.InstanceSerializer)
local Safety = require(script.Parent.Safety)
local SceneApplier = require(script.Parent.SceneApplier)
local TerrainGenerator = require(script.Parent.TerrainGenerator)

local CommandRouter = {}
CommandRouter.__index = CommandRouter

local function withRecording(name, callback)
	local recording = nil
	local began = pcall(function()
		recording = ChangeHistoryService:TryBeginRecording(name)
	end)

	local ok, result = pcall(callback)

	if began and recording then
		pcall(function()
			ChangeHistoryService:FinishRecording(recording, ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel)
		end)
	else
		pcall(function()
			ChangeHistoryService:SetWaypoint(name)
		end)
	end

	if not ok then
		error(result)
	end

	return result
end

local function treeNode(instance, depth, includeProperties)
	local node = InstanceSerializer.serializeInstance(instance, includeProperties)
	if depth <= 0 then
		return node
	end

	node.children = {}
	for _, child in ipairs(instance:GetChildren()) do
		table.insert(node.children, treeNode(child, depth - 1, includeProperties))
	end
	return node
end

local function vectorFromArray(value, fallback)
	if typeof(value) == "Vector3" then
		return value
	end
	if typeof(value) == "table" and value.type then
		local deserialized = InstanceSerializer.deserialize(value)
		if typeof(deserialized) == "Vector3" then
			return deserialized
		end
	elseif typeof(value) == "table" and #value >= 3 then
		return Vector3.new(tonumber(value[1]) or 0, tonumber(value[2]) or 0, tonumber(value[3]) or 0)
	end
	return fallback
end

local function currentCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		camera = Instance.new("Camera")
		camera.Name = "CodexBridgeCamera"
		camera.Parent = workspace
		workspace.CurrentCamera = camera
	end
	return camera
end

local function cameraState(camera)
	return {
		cframe = InstanceSerializer.serialize(camera.CFrame),
		position = InstanceSerializer.serialize(camera.CFrame.Position),
		lookVector = InstanceSerializer.serialize(camera.CFrame.LookVector),
		focus = InstanceSerializer.serialize(camera.Focus),
		fieldOfView = camera.FieldOfView,
	}
end

local function instanceBounds(instance)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	elseif instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end
	local model = Instance.new("Model")
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local clone = descendant:Clone()
			clone.Parent = model
		end
	end
	if #model:GetChildren() == 0 then
		model:Destroy()
		return CFrame.new(), Vector3.new(8, 8, 8)
	end
	local cframe, size = model:GetBoundingBox()
	model:Destroy()
	return cframe, size
end

function CommandRouter.new(plugin, ui)
	local self = setmetatable({}, CommandRouter)
	self.plugin = plugin
	self.ui = ui
	self.lastBatchName = nil
	self.allowDangerousLuauExecution = plugin:GetSetting("allowDangerousLuauExecution") == true
	return self
end

function CommandRouter:handle(name, args)
	args = args or {}
	self.ui:log("Command: " .. tostring(name))

	if name == "studio_ping" then
		return {
			pluginVersion = "0.2.0",
			placeName = game.Name,
			placeId = game.PlaceId,
			status = "Connected",
		}
	elseif name == "studio_get_tree" then
		local root = InstanceSerializer.resolve(args.rootPath or "game")
		if not root then
			error("rootPath not found")
		end
		return treeNode(root, args.depth or 3, args.includeProperties == true)
	elseif name == "studio_find_instances" then
		return self:findInstances(args)
	elseif name == "studio_get_properties" then
		local instance = InstanceSerializer.resolve(args.instancePath)
		if not instance then
			error("instancePath not found")
		end
		return InstanceSerializer.readProperties(instance, args.propertyNames)
	elseif name == "studio_create_instance" then
		return withRecording("Roblox Studio Bridge Create Instance", function()
			return self:createInstance(args)
		end)
	elseif name == "studio_set_properties" then
		return withRecording("Roblox Studio Bridge Set Properties", function()
			return self:setProperties(args)
		end)
	elseif name == "studio_delete_instances" then
		return withRecording("Roblox Studio Bridge Delete Instances", function()
			return self:deleteInstances(args)
		end)
	elseif name == "studio_patch_instances" then
		return withRecording("Roblox Studio Bridge Patch Instances", function()
			return self:patchInstances(args)
		end)
	elseif name == "studio_execute_luau" then
		return self:executeLuau(args)
	elseif name == "studio_get_camera" then
		return cameraState(currentCamera())
	elseif name == "studio_set_camera" then
		return self:setCamera(args)
	elseif name == "studio_focus_instance" then
		return self:focusInstance(args)
	elseif name == "studio_visual_probe" then
		return self:visualProbe(args)
	elseif name == "map_apply_scene_spec" or name == "map_create_blockout" then
		return withRecording("Roblox Studio Bridge Apply SceneSpec", function()
			self.lastBatchName = "Roblox Studio Bridge Apply SceneSpec"
			return SceneApplier.apply(args.sceneSpec, args.dryRun == true)
		end)
	elseif name == "terrain_generate" then
		return withRecording("Roblox Studio Bridge Generate Terrain", function()
			self.lastBatchName = "Roblox Studio Bridge Generate Terrain"
			return TerrainGenerator.generate(args)
		end)
	elseif name == "map_refine_visuals" then
		return withRecording("Roblox Studio Bridge Refine Visuals", function()
			self.lastBatchName = "Roblox Studio Bridge Refine Visuals"
			return SceneApplier.refineVisuals(args)
		end)
	elseif name == "map_validate" then
		return SceneApplier.validate(args)
	elseif name == "map_readiness_check" then
		return SceneApplier.readiness(args)
	elseif name == "studio_read_output" then
		return { lines = self.ui:getLogs(args.lines or 100) }
	elseif name == "studio_start_playtest" then
		return {
			ok = false,
			manualAction = "Use Roblox Studio Play button. Plugin API cannot reliably start playtest in all Studio builds.",
		}
	elseif name == "studio_stop_playtest" then
		return {
			ok = false,
			manualAction = "Use Roblox Studio Stop button. Plugin API cannot reliably stop playtest in all Studio builds.",
		}
	end

	error("Unknown command: " .. tostring(name))
end

function CommandRouter:findInstances(args)
	local matches = {}
	local root = game
	if args.pathPrefix then
		root = InstanceSerializer.resolve(args.pathPrefix) or game
	end

	for _, instance in ipairs(root:GetDescendants()) do
		local ok = true
		if args.name and instance.Name ~= args.name then
			ok = false
		end
		if args.className and instance.ClassName ~= args.className then
			ok = false
		end
		if args.tags then
			for _, tag in ipairs(args.tags) do
				if not CollectionService:HasTag(instance, tag) then
					ok = false
					break
				end
			end
		end

		if ok then
			table.insert(matches, {
				path = InstanceSerializer.pathOf(instance),
				className = instance.ClassName,
				name = instance.Name,
				properties = InstanceSerializer.readProperties(instance, args.properties),
			})
		end
		if #matches >= (args.limit or 100) then
			break
		end
	end

	return matches
end

function CommandRouter:createInstance(args)
	Safety.assertAllowedClass(args.className)
	local parent = InstanceSerializer.resolve(args.parentPath)
	if not parent then
		error("parentPath not found")
	end
	Safety.assertGeneratedPath(InstanceSerializer.pathOf(parent))

	local instance = Instance.new(args.className)
	instance.Name = Safety.sanitizeName(args.name)
	InstanceSerializer.writeProperties(instance, args.properties or {})
	instance.Parent = parent
	return {
		path = InstanceSerializer.pathOf(instance),
		className = instance.ClassName,
	}
end

function CommandRouter:setProperties(args)
	local instance = InstanceSerializer.resolve(args.instancePath)
	if not instance then
		error("instancePath not found")
	end
	Safety.assertGeneratedPath(InstanceSerializer.pathOf(instance))
	InstanceSerializer.writeProperties(instance, args.properties or {})
	return {
		path = InstanceSerializer.pathOf(instance),
		properties = InstanceSerializer.readProperties(instance, nil),
	}
end

function CommandRouter:deleteInstances(args)
	local confirmToken = args.confirmToken or args.requireConfirmToken
	Safety.assertDeleteAllowed(args.paths or {}, confirmToken)
	local deleted = {}

	for _, path in ipairs(args.paths or {}) do
		local instance = InstanceSerializer.resolve(path)
		if instance then
			table.insert(deleted, InstanceSerializer.pathOf(instance))
			instance:Destroy()
		end
	end

	return { deleted = deleted }
end

function CommandRouter:patchInstances(args)
	local results = {}
	local confirmToken = args.confirmToken or args.requireConfirmToken

	for index, operation in ipairs(args.operations or {}) do
		local action = operation.action or "set"
		if action == "create" then
			local result = self:createInstance(operation)
			table.insert(results, { index = index, action = action, path = result.path })
		elseif action == "set" then
			local result = self:setProperties({
				instancePath = operation.instancePath or operation.path,
				properties = operation.properties or {},
			})
			table.insert(results, { index = index, action = action, path = result.path })
		elseif action == "ensure" then
			local instance = InstanceSerializer.resolve(operation.instancePath or operation.path or "")
			if instance then
				local result = self:setProperties({
					instancePath = InstanceSerializer.pathOf(instance),
					properties = operation.properties or {},
				})
				table.insert(results, { index = index, action = "set", path = result.path })
			else
				local result = self:createInstance(operation)
				table.insert(results, { index = index, action = "create", path = result.path })
			end
		elseif action == "delete" then
			Safety.assertDeleteAllowed({ operation.instancePath or operation.path }, confirmToken)
			local instance = InstanceSerializer.resolve(operation.instancePath or operation.path)
			if instance then
				local path = InstanceSerializer.pathOf(instance)
				instance:Destroy()
				table.insert(results, { index = index, action = action, path = path })
			end
		else
			error("Unknown patch action: " .. tostring(action))
		end
	end

	return { ok = true, results = results }
end

function CommandRouter:executeLuau(args)
	if not self.allowDangerousLuauExecution then
		error("Dangerous Luau execution is disabled in plugin settings")
	end

	local blocked = Safety.isDangerousLuau(args.code or "")
	if #blocked > 0 then
		error("Blocked dangerous Luau: " .. table.concat(blocked, ", "))
	end

	local fn, compileError = loadstring(args.code)
	if not fn then
		error(compileError)
	end

	local ok, result = pcall(fn)
	if not ok then
		error(result)
	end
	return { result = result }
end

function CommandRouter:setCamera(args)
	local camera = currentCamera()
	if args.cframe then
		camera.CFrame = InstanceSerializer.deserialize(args.cframe)
	else
		local position = vectorFromArray(args.position, camera.CFrame.Position)
		local lookAt = vectorFromArray(args.lookAt, position + camera.CFrame.LookVector)
		camera.CFrame = CFrame.lookAt(position, lookAt)
	end
	if args.focus then
		camera.Focus = InstanceSerializer.deserialize(args.focus)
	elseif args.lookAt then
		camera.Focus = CFrame.new(vectorFromArray(args.lookAt, camera.CFrame.Position + camera.CFrame.LookVector))
	end
	if args.fieldOfView then
		camera.FieldOfView = math.clamp(tonumber(args.fieldOfView) or camera.FieldOfView, 20, 100)
	end
	return cameraState(camera)
end

function CommandRouter:focusInstance(args)
	local instance = InstanceSerializer.resolve(args.instancePath)
	if not instance then
		error("instancePath not found")
	end
	local centerFrame, size = instanceBounds(instance)
	local center = centerFrame.Position
	local distance = tonumber(args.distance) or math.max(size.X, size.Y, size.Z) * 1.7
	local view = args.view or "iso"
	local direction = Vector3.new(1, 0.45, 1)
	if view == "front" then
		direction = Vector3.new(0, 0.15, -1)
	elseif view == "back" then
		direction = Vector3.new(0, 0.15, 1)
	elseif view == "left" then
		direction = Vector3.new(-1, 0.15, 0)
	elseif view == "right" then
		direction = Vector3.new(1, 0.15, 0)
	elseif view == "top" then
		direction = Vector3.new(0, 1, 0.01)
	end
	local position = center + direction.Unit * distance
	return self:setCamera({
		position = { position.X, position.Y, position.Z },
		lookAt = { center.X, center.Y, center.Z },
		fieldOfView = args.fieldOfView,
	})
end

function CommandRouter:visualProbe(args)
	if args.position or args.cframe then
		self:setCamera(args)
	end
	local camera = currentCamera()
	local rows = math.clamp(tonumber(args.rows) or 5, 1, 15)
	local columns = math.clamp(tonumber(args.columns) or 7, 1, 21)
	local maxDistance = tonumber(args.maxDistance) or 500
	local aspect = tonumber(args.aspect) or 16 / 9
	local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
	local tanX = tanY * aspect
	local origin = camera.CFrame.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}

	local hits = {}
	for row = 1, rows do
		for column = 1, columns do
			local x = columns == 1 and 0 or ((column - 1) / (columns - 1) * 2 - 1)
			local y = rows == 1 and 0 or ((row - 1) / (rows - 1) * 2 - 1)
			local direction = (camera.CFrame.LookVector + camera.CFrame.RightVector * x * tanX - camera.CFrame.UpVector * y * tanY).Unit
			local hit = workspace:Raycast(origin, direction * maxDistance, params)
			if hit and hit.Instance then
				table.insert(hits, {
					row = row,
					column = column,
					path = InstanceSerializer.pathOf(hit.Instance),
					name = hit.Instance.Name,
					className = hit.Instance.ClassName,
					position = InstanceSerializer.serialize(hit.Position),
					distance = (hit.Position - origin).Magnitude,
				})
			end
		end
	end

	return {
		camera = cameraState(camera),
		rows = rows,
		columns = columns,
		hits = hits,
	}
end

function CommandRouter:undoLastBatch()
	local ok, err = pcall(function()
		ChangeHistoryService:Undo()
	end)
	if ok then
		self.ui:log("Undo requested")
	else
		self.ui:log("Undo failed: " .. tostring(err))
	end
end

return CommandRouter
