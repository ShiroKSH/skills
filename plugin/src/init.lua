local Ui = require(script.Bridge.Ui)
local CommandRouter = require(script.Bridge.CommandRouter)
local HttpTransport = require(script.Bridge.HttpTransport)

local toolbar = plugin:CreateToolbar("Roblox Studio Bridge")
local button = toolbar:CreateButton(
	"Roblox Studio Bridge",
	"Open Roblox Studio Bridge",
	"rbxasset://textures/StudioSharedUI/RobloxLogo.png"
)

local ui = Ui.new(plugin, button)
local router = CommandRouter.new(plugin, ui)
local transport = HttpTransport.new(plugin, router, ui)

button.Click:Connect(function()
	ui:toggle()
end)

ui:onConnect(function(options)
	return transport:start(options)
end)

ui:onDisconnect(function()
	transport:stop()
end)

ui:onUndo(function()
	router:undoLastBatch()
end)

plugin.Unloading:Connect(function()
	transport:stop()
	ui:destroy()
end)

ui:setStatus("Disconnected")
ui:log("Plugin loaded")
