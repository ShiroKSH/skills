local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local source = fs.readFile("plugin/src/Bridge/ViewportCapture.lua")
local passed = 0
for _, scenario in ipairs({ "success", "denied", "read-error", "encode-error", "oversize", "capture-error", "timeout", "width-only", "height-only", "wide-default", "explicit" }) do
	local destroyed, requested, clock = false, false, 0
	local size, args = roblox.Vector2.new(800, 600), {}
	local expected = size
	if scenario == "width-only" then size, args, expected = roblox.Vector2.new(1600, 900), { width = 800 }, roblox.Vector2.new(800, 450) end
	if scenario == "height-only" then size, args, expected = roblox.Vector2.new(1600, 900), { height = 450 }, roblox.Vector2.new(800, 450) end
	if scenario == "wide-default" then size, expected = roblox.Vector2.new(2560, 1000), roblox.Vector2.new(1920, 750) end
	if scenario == "explicit" then args, expected = { width = 640, height = 480 }, roblox.Vector2.new(640, 480) end
	local capture = { BufferStatus = "Ready", Resolution = roblox.Vector2.new(800, 600) }
	if scenario == "capture-error" then capture.BufferStatus = "Error" end
	if scenario == "timeout" then capture.BufferStatus = "Pending" end
	function capture:Destroy() destroyed = true end
	function capture:GetErrors() return { "Expected capture failure" } end
	function capture:GetBuffer()
		if scenario == "read-error" then error("Expected read failure") end
		return buffer.create(scenario == "oversize" and (8 * 1024 * 1024 + 1) or 42)
	end
	local services = {
		StudioCaptureService = {
			CanCaptureScreenshot = function() return scenario ~= "denied" end,
			CaptureScreenshot = function(_, options)
				requested = true
				assert(options.UICaptureMode == "None" and options.Format == "PNG")
				assert(options.OutputSize == expected)
				capture.Resolution = options.OutputSize
				return capture
			end,
		},
		EncodingService = { Base64Encode = function(_, value)
			if scenario == "encode-error" then error("Expected encode failure") end
			assert(buffer.len(value) == 42)
			return buffer.fromstring(string.rep("A", 56))
		end },
	}
	local module = luau.load(source, { environment = {
		game = { GetService = function(_, name) return services[name] end },
		workspace = { CurrentCamera = { ViewportSize = size } },
		Enum = { StudioCaptureBufferStatus = { Ready = "Ready", Error = "Error" }, ResamplerMode = { Default = "Default" },
			StudioCaptureScreenshotFormat = { PNG = "PNG" }, UICaptureMode = { None = "None" } },
		Vector2 = roblox.Vector2,
		task = { wait = function() end },
		os = { clock = function() clock += 8; return clock end },
		buffer = buffer,
	} })()
	local ok, result = pcall(module.capture, args)
	if scenario == "denied" then
		assert(ok and result.ok == false and not requested and not destroyed)
	elseif scenario == "success" or scenario == "width-only" or scenario == "height-only" or scenario == "wide-default" or scenario == "explicit" then
		assert(ok and result.ok and destroyed)
		assert(result.width == expected.X and result.height == expected.Y and result.byteLength == 42)
		assert(result.data == string.rep("A", 56))
	else
		assert(not ok and destroyed, "Capture leaked after " .. scenario)
	end
	passed += 1
	print("PASS viewport capture " .. scenario)
end
print(passed .. " viewport capture checks passed")
