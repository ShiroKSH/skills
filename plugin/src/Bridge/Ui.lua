local Studio = settings().Studio

local Ui = {}
Ui.__index = Ui

local function makeText(parent, name, text, position, size)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.SourceSans
	label.TextSize = 14
	label.Parent = parent
	return label
end

local function makeBox(parent, name, text, position, size)
	local box = Instance.new("TextBox")
	box.Name = name
	box.Text = text
	box.Position = position
	box.Size = size
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Code
	box.TextSize = 13
	box.BorderSizePixel = 0
	box.Parent = parent
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = box
	return box
end

local function makeButton(parent, name, text, position, size)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Position = position
	button.Size = size
	button.Font = Enum.Font.SourceSansSemibold
	button.TextSize = 14
	button.BorderSizePixel = 0
	button.Parent = parent
	return button
end

function Ui.new(plugin, toolbarButton)
	local self = setmetatable({}, Ui)
	self.plugin = plugin
	self.toolbarButton = toolbarButton
	self.logs = {}
	self.connectCallbacks = {}
	self.disconnectCallbacks = {}
	self.undoCallbacks = {}
	local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 360, 460, 280, 360)
	self.widget = plugin:CreateDockWidgetPluginGui("RobloxStudioBridge", info)
	self.widget.Title = "Roblox Studio Bridge 0.2.3"

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BorderSizePixel = 0
	root.Parent = self.widget
	self.root = root
	self.statusLabel = makeText(root, "Status", "Disconnected", UDim2.fromOffset(12, 10), UDim2.new(1, -24, 0, 26))
	makeText(root, "HostLabel", "Host", UDim2.fromOffset(12, 44), UDim2.new(1, -112, 0, 20))
	makeText(root, "PortLabel", "Port", UDim2.new(1, -82, 0, 44), UDim2.fromOffset(70, 20))
	self.hostBox = makeBox(root, "HostBox", plugin:GetSetting("host") or "127.0.0.1", UDim2.fromOffset(12, 68), UDim2.new(1, -104, 0, 28))
	self.portBox = makeBox(root, "PortBox", tostring(plugin:GetSetting("port") or 3765), UDim2.new(1, -82, 0, 68), UDim2.fromOffset(70, 28))
	makeText(root, "TokenLabel", "Token", UDim2.fromOffset(12, 104), UDim2.new(1, -24, 0, 20))
	self.tokenBox = makeBox(root, "TokenBox", "", UDim2.fromOffset(12, 128), UDim2.new(1, -24, 0, 28))
	self.connectionButton = makeButton(root, "Connection", "Connect", UDim2.fromOffset(12, 168), UDim2.new(0.5, -18, 0, 30))
	self.undoButton = makeButton(root, "Undo", "Undo", UDim2.new(0.5, 6, 0, 168), UDim2.new(0.5, -18, 0, 30))
	self.capturePermissionButton = makeButton(root, "CapturePermission", "Allow viewport capture", UDim2.fromOffset(12, 206), UDim2.new(1, -24, 0, 30))
	makeText(root, "Activity", "Activity", UDim2.fromOffset(12, 248), UDim2.new(1, -24, 0, 20))
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "LogScroll"
	scroll.Position = UDim2.fromOffset(12, 274)
	scroll.Size = UDim2.new(1, -24, 1, -286)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = root
	self.logScroll = scroll
	self.logBox = makeText(scroll, "LogBox", "", UDim2.new(), UDim2.new(1, -10, 0, 0))
	self.logBox.AutomaticSize = Enum.AutomaticSize.Y
	self.logBox.TextYAlignment = Enum.TextYAlignment.Top
	self.logBox.TextWrapped = true
	self.logBox.Font = Enum.Font.Code
	self.logBox.TextSize = 12

	self.connectionButton.MouseButton1Click:Connect(function()
		if self.connectionActive then
			for _, callback in ipairs(self.disconnectCallbacks) do
				callback()
			end
			return
		end
		local options = self:getConnectionOptions()
		for _, callback in ipairs(self.connectCallbacks) do
			if callback(options) then
				plugin:SetSetting("host", options.host)
				plugin:SetSetting("port", tonumber(options.port))
				self.tokenBox.Text = ""
			end
		end
	end)
	self.undoButton.MouseButton1Click:Connect(function()
		for _, callback in ipairs(self.undoCallbacks) do
			callback()
		end
	end)
	self.capturePermissionButton.MouseButton1Click:Connect(function()
		if self.requestingCapturePermission then return end
		self.requestingCapturePermission = true
		local ok, allowed = pcall(function()
			return game:GetService("StudioCaptureService"):RequestScreenshotPermissionAsync()
		end)
		self.requestingCapturePermission = false
		if self.destroyed then return end
		self:log(ok and (allowed and "Viewport capture permission granted" or "Viewport capture permission unavailable") or tostring(allowed))
	end)
	self.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		toolbarButton:SetActive(self.widget.Enabled)
	end)
	self.themeConnection = Studio.ThemeChanged:Connect(function()
		self:applyTheme()
	end)
	self:applyTheme()
	return self
end

function Ui:applyTheme()
	local theme = Studio.Theme
	self.root.BackgroundColor3 = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
	for _, child in ipairs(self.root:GetDescendants()) do
		if child:IsA("TextLabel") then
			child.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.MainText)
		elseif child:IsA("TextBox") then
			child.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.MainText)
			child.BackgroundColor3 = theme:GetColor(Enum.StudioStyleGuideColor.InputFieldBackground)
		elseif child:IsA("TextButton") then
			child.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.MainText)
			child.BackgroundColor3 = theme:GetColor(Enum.StudioStyleGuideColor.Button)
		end
	end
end

function Ui:toggle()
	self.widget.Enabled = not self.widget.Enabled
end

function Ui:setStatus(status)
	self.statusLabel.Text = tostring(status)
	self.connectionActive = status == "Connected" or status == "Connecting" or status == "Reconnecting"
	self.connectionButton.Text = self.connectionActive and "Disconnect" or "Connect"
	for _, box in ipairs({ self.hostBox, self.portBox, self.tokenBox }) do
		box.TextEditable = not self.connectionActive
	end
end

function Ui:log(line)
	local scroll = self.logScroll
	local atBottom = scroll.CanvasPosition.Y + scroll.AbsoluteWindowSize.Y >= scroll.AbsoluteCanvasSize.Y - 20
	table.insert(self.logs, os.date("%H:%M:%S") .. " " .. tostring(line))
	while #self.logs > 100 do
		table.remove(self.logs, 1)
	end
	self.logBox.Text = table.concat(self.logs, "\n")
	if atBottom then
		task.defer(function()
			if not self.destroyed then
				scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y))
			end
		end)
	end
end

function Ui:getLogs(lines)
	local count = math.clamp(math.floor(tonumber(lines) or 100), 0, #self.logs)
	local output = {}
	for index = #self.logs - count + 1, #self.logs do
		table.insert(output, self.logs[index])
	end
	return output
end

function Ui:getConnectionOptions()
	return { host = self.hostBox.Text, port = self.portBox.Text, token = self.tokenBox.Text }
end

function Ui:onConnect(callback)
	table.insert(self.connectCallbacks, callback)
end

function Ui:onDisconnect(callback)
	table.insert(self.disconnectCallbacks, callback)
end

function Ui:onUndo(callback)
	table.insert(self.undoCallbacks, callback)
end

function Ui:destroy()
	self.destroyed = true
	self.themeConnection:Disconnect()
	self.widget:Destroy()
end

return Ui
