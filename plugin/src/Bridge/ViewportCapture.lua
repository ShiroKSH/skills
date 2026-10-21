local EncodingService = game:GetService("EncodingService")
local StudioCaptureService = game:GetService("StudioCaptureService")

local ViewportCapture = {}

function ViewportCapture.capture(args)
	if not StudioCaptureService:CanCaptureScreenshot() then
		return { ok = false, error = "Viewport capture is unavailable. The plugin needs screenshot permission and an active Studio place.", permissionRequired = true }
	end
	local camera = workspace.CurrentCamera
	assert(camera, "Studio has no viewport camera")
	local size = camera.ViewportSize
	assert(size.X > 0 and size.Y > 0, "Studio viewport is not rendered")
	local width = math.floor(tonumber(args.width) or math.min(size.X, 1920))
	local height = math.floor(tonumber(args.height) or math.min(size.Y, 1080))
	assert(width > 0 and height > 0 and width <= 4096 and height <= 4096, "Capture dimensions must be between 1 and 4096")
	local capture = StudioCaptureService:CaptureScreenshot({
		Position = Vector2.zero,
		CaptureSize = size,
		OutputSize = Vector2.new(width, height),
		ResampleMode = Enum.ResamplerMode.Default,
		Format = Enum.StudioCaptureScreenshotFormat.PNG,
		UICaptureMode = Enum.UICaptureMode.None,
	})
	local ok, result = pcall(function()
		local deadline = os.clock() + 15
		while capture.BufferStatus ~= Enum.StudioCaptureBufferStatus.Ready do
			if capture.BufferStatus == Enum.StudioCaptureBufferStatus.Error then
				error("Viewport capture failed: " .. table.concat(capture:GetErrors(), "; "))
			end
			if os.clock() >= deadline then error("Viewport capture timed out") end
			task.wait(0.05)
		end
		local data = capture:GetBuffer()
		assert(buffer.len(data) <= 8 * 1024 * 1024, "Screenshot exceeds the 8 MiB transfer limit")
		return {
			ok = true, width = capture.Resolution.X, height = capture.Resolution.Y,
			byteLength = buffer.len(data), data = buffer.tostring(EncodingService:Base64Encode(data)),
		}
	end)
	capture:Destroy()
	if not ok then error(result) end
	return result
end

return ViewportCapture
