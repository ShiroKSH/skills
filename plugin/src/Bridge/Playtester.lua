local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")
local InstanceSerializer = require(script.Parent.InstanceSerializer)
local Safety = require(script.Parent.Safety)

local Playtester = {}
local running = false

function Playtester.run(args)
	assert(args.confirmToken == "RUN_STUDIO_TEST", "Running trusted project code requires RUN_STUDIO_TEST confirmation")
	Safety.assertGeneratedPath(args.modulePath)
	local module = InstanceSerializer.resolve(args.modulePath)
	assert(module and module:IsA("ModuleScript"), "modulePath must resolve to a managed ModuleScript")
	assert(not running and not RunService:IsRunning(), "A Studio test is already running")
	local timeout = tonumber(args.timeoutSeconds) or 30
	assert(timeout >= 1 and timeout <= 120 and timeout % 1 == 0, "Test timeout must be an integer between 1 and 120 seconds")
	assert(args.mode == nil or args.mode == "run" or args.mode == "play", "Test mode must be run or play")
	local runner = Instance.new("Script")
	runner.Name = "BridgeTest_" .. HttpService:GenerateGUID(false)
	runner.Source = string.format([[
local tests = game:GetService("StudioTestService")
local finished = false
local function finish(value)
	if finished then return end
	finished = true
	tests:EndTest(value)
end
local input = tests:GetTestArgs()
if type(input) ~= "table" or input.bridgeTestId ~= %q then return end
task.delay(%f, function() finish({ ok = false, error = "Test deadline exceeded", timedOut = true }) end)
task.spawn(function()
	local ok, result = pcall(function()
		local current = game
		for segment in string.gmatch(%q, "[^/]+") do current = current:WaitForChild(segment, 5) end
		local test = require(current)
		assert(type(test) == "function", "Test module must return a function")
		return test(input.args)
	end)
	finish(ok and { ok = true, result = result } or { ok = false, error = tostring(result) })
end)
]], runner.Name, timeout, InstanceSerializer.pathOf(module))
	running = true
	local finished, timedOut, watchdog = false, false, nil
	local ok, result = pcall(function()
		runner.Parent = module.Parent
		-- Edit-side fallback remains outside the test server's scheduler.
		watchdog = task.delay(timeout + 2, function()
			if not finished then
				timedOut = true
				pcall(function() RunService:Stop() end)
			end
		end)
		local input = { bridgeTestId = runner.Name, args = args.args or {} }
		if args.mode == "play" then return StudioTestService:ExecutePlayModeAsync(input) end
		return StudioTestService:ExecuteRunModeAsync(input)
	end)
	finished = true
	if watchdog then pcall(task.cancel, watchdog) end
	runner:Destroy()
	running = false
	if timedOut then return { ok = false, timedOut = true, error = "Test stopped by the Studio watchdog" } end
	if not ok then error(result) end
	if type(result) ~= "table" or type(result.ok) ~= "boolean" then
		return { ok = false, error = "Studio test ended without a result" }
	end
	return result
end

return Playtester
