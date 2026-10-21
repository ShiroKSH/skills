local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local datetime = require("@lune/datetime")

local requestHandler
local guid = 0
roblox.implementMethod("HttpService", "JSONEncode", function(_, value)
	return serde.encode("json", value)
end)
roblox.implementMethod("HttpService", "JSONDecode", function(_, value)
	return serde.decode("json", value)
end)
roblox.implementMethod("HttpService", "GenerateGUID", function()
	guid += 1
	return "test-session-" .. guid
end)
roblox.implementMethod("HttpService", "RequestAsync", function(_, options)
	return requestHandler(options)
end)

local pluginModel = roblox.deserializeModel(fs.readFile("dist/RobloxStudioBridge.rbxm"))[1]
local pluginSources = pluginModel:GetDescendants()
table.insert(pluginSources, pluginModel)
for _, object in ipairs(pluginSources) do
	if object:IsA("LuaSourceContainer") then
		luau.compile(object.Source)
	end
end

local function fixture()
	local game = roblox.Instance.new("DataModel")
	game.PlaceId = 0
	local modules = {}
	local threads = {}
	local waits = {}
	local tasks = {
		spawn = function(callback)
			local thread = coroutine.create(callback)
			table.insert(threads, thread)
			local ok, err = coroutine.resume(thread)
			assert(ok, err)
		end,
		wait = function(delay)
			table.insert(waits, delay)
			coroutine.yield()
		end,
	}
	local function loadModule(module)
		if not modules[module] then
			modules[module] = luau.load(module.Source, {
				debugName = module.Name,
				environment = {
					game = game,
					workspace = game:GetService("Workspace"),
					script = module,
					require = loadModule,
					task = tasks,
					settings = function() return { Studio = {} } end,
					DateTime = {
						now = function() return { UnixTimestampMillis = datetime.now().unixTimestampMillis } end,
						fromIsoDate = function(value)
							return { UnixTimestampMillis = datetime.fromRfc3339(value).unixTimestampMillis }
						end,
					},
					Instance = roblox.Instance,
					Vector3 = roblox.Vector3,
					Vector2 = roblox.Vector2,
					CFrame = roblox.CFrame,
					Color3 = roblox.Color3,
					Enum = roblox.Enum,
					UDim2 = roblox.UDim2,
					UDim = roblox.UDim,
				},
			})()
		end
		return modules[module]
	end
	return {
		game = game,
		threads = threads,
		waits = waits,
		load = function(name) return loadModule(pluginModel.Bridge[name]) end,
	}
end

local passed = 0
local function test(name, callback)
	callback()
	passed += 1
	print("PASS " .. name)
end

local function scene(name, instances)
	return {
		mapName = name,
		style = "modern",
		layout = { grounding = { mode = "manual", groundY = 17, clearance = 0.1 } },
		instances = instances,
	}
end

test("nested parents resolve even when children are declared first", function()
	local f = fixture()
	local result = f.load("SceneApplier").apply(scene("Nested", {
		{ className = "Part", name = "Wall", parentPath = "$MAP_ROOT/Buildings/Cabin", properties = {} },
		{ className = "Model", name = "Cabin", parentPath = "$MAP_ROOT/Buildings", properties = {} },
		{ className = "Folder", name = "Buildings", properties = {} },
	}), false)
	local root = f.load("InstanceSerializer").resolve(result.mapRootPath)
	assert(root.Buildings.Cabin.Wall:IsA("Part"))
end)

test("missing and cyclic parents fail explicitly", function()
	local f = fixture()
	local ok, err = pcall(f.load("SceneApplier").apply, scene("Cycle", {
		{ className = "Part", name = "EarlierPart" },
		{ className = "Folder", name = "A", parentPath = "$MAP_ROOT/B" },
		{ className = "Folder", name = "B", parentPath = "$MAP_ROOT/A" },
	}), false)
	assert(not ok and string.find(tostring(err), "Missing or cyclic parent path", 1, true))
	assert(#f.game:GetService("Workspace").MapDrafts:GetChildren() == 0)
end)

test("CFrame wins over conflicting Position in grounded and ungrounded scenes", function()
	for _, mode in ipairs({ "manual", "none" }) do
		local f = fixture()
		local spec = scene("ConflictingPosition", {
			{ className = "Part", name = "Floor", properties = {
				Size = { type = "Vector3", value = { 4, 2, 4 } },
				Position = { type = "Vector3", value = { -100, -100, -100 } },
				CFrame = { type = "CFrame", value = { 9, -8, 4 } },
			} },
		})
		spec.layout.grounding.mode = mode
		local result = f.load("SceneApplier").apply(spec, false)
		local floor = f.load("InstanceSerializer").resolve(result.mapRootPath).Floor
		assert(math.abs(floor.CFrame.Position.X - 9) < 0.001)
		assert(math.abs(floor.CFrame.Position.Y - (mode == "manual" and 18.1 or -8)) < 0.001)
	end
end)

test("grounding CFrame parts preserves rotation and oriented bottom height", function()
	local f = fixture()
	local rotation = roblox.CFrame.Angles(0, 0, math.rad(30))
	local frame = roblox.CFrame.new(9, -8, 4) * rotation
	local result = f.load("SceneApplier").apply(scene("Rotated", {
		{ className = "Part", name = "Ramp", properties = {
			Anchored = true,
			Size = { type = "Vector3", value = { 12, 2, 4 } },
			CFrame = { type = "CFrame", value = { frame:GetComponents() } },
		} },
	}), false)
	local root = f.load("InstanceSerializer").resolve(result.mapRootPath)
	local ramp = root.Ramp
	local halfHeight = (math.abs(ramp.CFrame.RightVector.Y) * 12 + math.abs(ramp.CFrame.UpVector.Y) * 2) / 2
	assert(math.abs(ramp.CFrame.Position.Y - halfHeight - 17.1) < 0.001)
	assert((ramp.CFrame.RightVector - rotation.RightVector).Magnitude < 0.001)
	assert(math.abs(ramp.CFrame.Position.X - 9) < 0.001)
end)

local function transportFixture()
	local f = fixture()
	local ui = { logs = {}, status = "Disconnected" }
	function ui:setStatus(value) self.status = value end
	function ui:log(value) table.insert(self.logs, value) end
	local router = { calls = 0 }
	function router:handle()
		self.calls += 1
		return false
	end
	local transport = f.load("HttpTransport").new({}, router, ui)
	return f, transport, ui, router
end

local token = "test-only-token-not-a-credential"
local function success(body)
	return { Success = true, StatusCode = 200, Body = serde.encode("json", body or {}) }
end

test("transport validates hosts and integer ports without starting requests", function()
	local f, transport = transportFixture()
	for _, host in ipairs({ "example.com", "127.0.0.1.evil", "0.0.0.0" }) do
		assert(not transport:start({ host = host, port = 3765, token = token }))
	end
	for _, port in ipairs({ "bad", "3765.5", "65536" }) do
		assert(not transport:start({ host = "127.0.0.1", port = port, token = token }))
	end
	assert(#f.threads == 0)
end)

test("disconnect discards an in-flight poll before it can edit Studio", function()
	local f, transport, ui, router = transportFixture()
	requestHandler = function(options)
		assert(options.Method == "POST" and not string.find(options.Url, token, 1, true))
		local body = serde.decode("json", options.Body)
		assert(body.token == token)
		if string.find(options.Url, "/plugin/poll", 1, true) then
			coroutine.yield()
			return success({ command = { id = "late", name = "studio_create_instance" } })
		end
		return success()
	end
	assert(transport:start({ host = "127.0.0.1", port = 3765, token = token }))
	assert(ui.status == "Connected")
	transport:stop()
	assert(coroutine.resume(f.threads[1]))
	assert(router.calls == 0 and ui.status == "Disconnected")
end)

test("result delivery retries without re-executing an edit", function()
	local f, transport, ui, router = transportFixture()
	local polls, results = 0, 0
	requestHandler = function(options)
		if string.find(options.Url, "/plugin/poll", 1, true) then
			polls += 1
			if polls > 1 then coroutine.yield() end
			return success({ command = { id = "once", name = "studio_ping" } })
		elseif string.find(options.Url, "/plugin/result", 1, true) then
			results += 1
			local body = serde.decode("json", options.Body)
			assert(body.ok == true and body.result == false and body.error == nil)
			if results <= 4 then return { Success = false, StatusCode = 503, StatusMessage = "Unavailable" } end
		end
		return success()
	end
	transport:start({ host = "localhost", port = 3765, token = token })
	assert(router.calls == 1 and results == 1, tostring(router.calls) .. "/" .. tostring(results) .. " " .. table.concat(ui.logs, "; "))
	for _ = 1, 4 do assert(coroutine.resume(f.threads[1])) end
	assert(router.calls == 1 and results == 5)
	transport:stop()
	assert(coroutine.resume(f.threads[1]))
end)

test("place changes discard commands returned by an in-flight poll", function()
	local f, transport, ui, router = transportFixture()
	local originalClientId = transport.clientId
	requestHandler = function(options)
		if string.find(options.Url, "/plugin/poll", 1, true) then
			f.game.PlaceId = 123
			return success({ command = { id = "wrong-place", name = "studio_create_instance" } })
		end
		return success()
	end
	transport:start({ host = "127.0.0.1", port = 3765, token = token })
	assert(router.calls == 0 and transport.session == nil and ui.status == "Place changed")
	assert(transport.clientId ~= originalClientId)
	local registeredClientId
	requestHandler = function(options)
		if string.find(options.Url, "/plugin/register", 1, true) then
			registeredClientId = serde.decode("json", options.Body).clientId
		else
			transport:stop()
		end
		return success()
	end
	transport:start({ host = "127.0.0.1", port = 3765, token = token })
	assert(registeredClientId ~= originalClientId and registeredClientId == transport.clientId)
end)

test("grounding and zone failures leave no partial draft", function()
	for _, failure in ipairs({ "grounding", "zone" }) do
		local f = fixture()
		local spec = scene("BadInput", {})
		if failure == "grounding" then
			spec.instances = { { className = "Part", name = "BadFrame", properties = { CFrame = { type = "Unsupported", value = {} } } } }
		else
			spec.layout.grounding.mode = "none"
			spec.zones = { { name = "BadZone", kind = "spawn", position = { type = "Unsupported", value = {} }, size = { type = "Vector3", value = { 4, 1, 4 } } } }
		end
		local ok = pcall(f.load("SceneApplier").apply, spec, false)
		assert(not ok)
		assert(#f.game:GetService("Workspace").MapDrafts:GetChildren() == 0)
	end
end)

test("retrying the same spec after failed apply does not ground it twice", function()
	local f = fixture()
	local spec = scene("RetryGrounding", {
		{ className = "Part", name = "Floor", properties = {
			Size = { type = "Vector3", value = { 4, 2, 4 } },
			CFrame = { type = "CFrame", value = { 9, -8, 4 } },
		} },
		{ className = "Part", name = "Blocked", parentPath = "$MAP_ROOT/Missing" },
	})
	assert(not pcall(f.load("SceneApplier").apply, spec, false))
	table.remove(spec.instances, 2)
	local result = f.load("SceneApplier").apply(spec, false)
	local floor = f.load("InstanceSerializer").resolve(result.mapRootPath).Floor
	assert(math.abs(floor.CFrame.Position.Y - 18.1) < 0.001)
end)

test("a place changed while disconnected gets a new identity on reconnect", function()
	local f, transport, _, router = transportFixture()
	requestHandler = function(options)
		if string.find(options.Url, "/plugin/poll", 1, true) then coroutine.yield() end
		return success()
	end
	transport:start({ host = "127.0.0.1", port = 3765, token = token })
	local previousClientId = transport.clientId
	transport:stop()
	f.game.PlaceId = 456
	local registeredClientId
	requestHandler = function(options)
		if string.find(options.Url, "/plugin/register", 1, true) then
			registeredClientId = serde.decode("json", options.Body).clientId
		else
			transport:stop()
		end
		return success()
	end
	transport:start({ host = "127.0.0.1", port = 3765, token = token })
	assert(registeredClientId ~= previousClientId and registeredClientId == transport.clientId)
	assert(transport.clientPlaceId == 456)
	assert(coroutine.resume(f.threads[1]))
	assert(router.calls == 0)
end)

test("expired commands never reach the router", function()
	local _, transport, _, router = transportFixture()
	local sent
	requestHandler = function(options)
		if string.find(options.Url, "/plugin/poll", 1, true) then
			return success({ command = { id = "old", name = "studio_create_instance", expiresAt = "2020-01-01T00:00:00Z" } })
		elseif string.find(options.Url, "/plugin/result", 1, true) then
			sent = serde.decode("json", options.Body)
			transport:stop()
		end
		return success()
	end
	transport:start({ host = "127.0.0.1", port = 3765, token = token })
	assert(router.calls == 0 and sent.ok == false and string.find(sent.error, "expired"))
end)

test("a restarted bridge causes re-registration before polling again", function()
	local f, transport, ui = transportFixture()
	local registrations = 0
	requestHandler = function(options)
		if string.find(options.Url, "/plugin/register", 1, true) then
			registrations += 1
		elseif registrations == 1 then
			return { Success = false, StatusCode = 409, StatusMessage = "Register first" }
		else
			transport:stop()
		end
		return success()
	end
	transport:start({ host = "127.0.0.1", port = 3765, token = token })
	assert(ui.status == "Reconnecting" and registrations == 1)
	assert(coroutine.resume(f.threads[1]))
	assert(registrations == 2 and ui.status == "Disconnected")
end)

print(string.format("%d plugin behavior tests passed", passed))
