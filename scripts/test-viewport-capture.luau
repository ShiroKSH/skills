local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local source = fs.readFile("plugin/src/Bridge/ViewportCapture.lua")
local passed = 0
for _, scenario in ipairs({ "success", "denied", "read-error", "encode-error", "oversize", "capture-error", "timeout" }) do
	local destroyed, requested, clock = false, false, 0
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
		workspace = { CurrentCamera = { ViewportSize = roblox.Vector2.new(800, 600) } },
		Enum = { StudioCaptureBufferStatus = { Ready = "Ready", Error = "Error" }, ResamplerMode = { Default = "Default" },
			StudioCaptureScreenshotFormat = { PNG = "PNG" }, UICaptureMode = { None = "None" } },
		Vector2 = roblox.Vector2,
		task = { wait = function() end },
		os = { clock = function() clock += 8; return clock end },
		buffer = buffer,
	} })()
	local ok, result = pcall(module.capture, {})
	if scenario == "denied" then
		assert(ok and result.ok == false and not requested and not destroyed)
	elseif scenario == "success" then
		assert(ok and result.ok and destroyed)
		assert(result.width == 800 and result.height == 600 and result.byteLength == 42)
		assert(result.data == string.rep("A", 56))
	else
		assert(not ok and destroyed, "Capture leaked after " .. scenario)
	end
	passed += 1
	print("PASS viewport capture " .. scenario)
end
print(passed .. " viewport capture checks passed")
