local HttpService = game:GetService("HttpService")

local HttpTransport = {}
HttpTransport.__index = HttpTransport

local function loopbackHost(value)
	local host = tostring(value or ""):lower():match("^%s*(.-)%s*$")
	if host == "127.0.0.1" or host == "localhost" or host == "::1" then
		return host
	end
	return nil
end

local function messageOf(err)
	return type(err) == "table" and err.message or tostring(err)
end

function HttpTransport.new(plugin, router, ui)
	local self = setmetatable({}, HttpTransport)
	self.plugin = plugin
	self.router = router
	self.ui = ui
	self.clientId = HttpService:GenerateGUID(false)
	return self
end

function HttpTransport:start(options)
	if self.session then
		return false
	end
	local host = loopbackHost(options.host or "127.0.0.1")
	local port = tonumber(options.port)
	local token = tostring(options.token or "")
	if not host then
		self.ui:setStatus("Invalid host")
		self.ui:log("Host must be 127.0.0.1, localhost, or ::1")
		return false
	end
	if not port or port ~= math.floor(port) or port < 1024 or port > 65535 then
		self.ui:setStatus("Invalid port")
		self.ui:log("Port must be an integer between 1024 and 65535")
		return false
	end
	if #token < 24 then
		self.ui:setStatus("Invalid token")
		self.ui:log("Token must be at least 24 characters")
		return false
	end
	local hostForUrl = host == "::1" and "[::1]" or host
	local session = { baseUrl = ("http://%s:%d"):format(hostForUrl, port), token = token }
	self.session = session
	self.ui:setStatus("Connecting")
	task.spawn(function()
		self:run(session)
	end)
	return true
end

function HttpTransport:stop()
	self.session = nil
	self.ui:setStatus("Disconnected")
end

function HttpTransport:request(session, path, body)
	body.token = session.token
	body.clientId = self.clientId
	local response = HttpService:RequestAsync({
		Url = session.baseUrl .. path,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode(body),
	})
	if not response.Success then
		error({
			statusCode = response.StatusCode,
			message = ("HTTP %d at %s: %s"):format(response.StatusCode, path, tostring(response.StatusMessage)),
		})
	end
	if response.Body == nil or response.Body == "" then
		return {}
	end
	return HttpService:JSONDecode(response.Body)
end

function HttpTransport:register(session)
	return self:request(session, "/plugin/register", {
		pluginVersion = "0.2.0",
		placeName = game.Name,
		placeId = game.PlaceId,
		status = "Connected",
	})
end

function HttpTransport:poll(session)
	return self:request(session, "/plugin/poll", {})
end

function HttpTransport:sendResult(session, commandId, ok, result, errorMessage)
	local payload = {
		commandId = commandId,
		ok = ok,
		error = errorMessage,
	}
	if ok then
		payload.result = result
	end
	return self:request(session, "/plugin/result", payload)
end

function HttpTransport:sendOutput(lines)
	if self.session then
		return self:request(self.session, "/plugin/output", { lines = lines })
	end
end

function HttpTransport:execute(session, command)
	local commandOk, result = pcall(function()
		if command.expiresAt then
			local expiry = DateTime.fromIsoDate(command.expiresAt)
			if not expiry or DateTime.now().UnixTimestampMillis >= expiry.UnixTimestampMillis then
				error("Command expired before execution")
			end
		end
		return self.router:handle(command.name, command.args)
	end)
	if self.session ~= session then
		return
	end
	self.ui:log((commandOk and "Completed: " or "Failed: ") .. tostring(command.name))
	local errorMessage = nil
	if not commandOk then
		errorMessage = messageOf(result)
	end
	for attempt = 1, 3 do
		local sent, err = pcall(function()
			self:sendResult(session, command.id, commandOk, result, errorMessage)
		end)
		if sent or self.session ~= session then
			return
		end
		if attempt == 3 then
			self.ui:log("Result delivery failed; command was not replayed. " .. messageOf(err))
		else
			task.wait(attempt * 0.5)
			if self.session ~= session then
				return
			end
		end
	end
end

function HttpTransport:run(session)
	local registered = false
	local failures = 0
	while self.session == session do
		local ok, result = pcall(function()
			if not registered then
				self:register(session)
				registered = true
				if self.session == session then
					self.ui:setStatus("Connected")
					self.ui:log("Connected to MCP server")
				end
			end
			if self.session ~= session then
				return {}
			end
			return self:poll(session)
		end)
		if self.session ~= session then
			return
		end
		if ok then
			failures = 0
			if result.command then
				self:execute(session, result.command)
			else
				task.wait(0.1)
			end
		else
			local status = type(result) == "table" and result.statusCode
			if status == 401 or status == 403 or (status == 409 and not registered) then
				self.session = nil
				self.ui:setStatus(status == 409 and "Connection rejected" or "Authentication failed")
				self.ui:log(status == 409 and "Another Studio session is connected" or "Check the bridge token and reconnect")
				return
			end
			registered = false
			failures += 1
			self.ui:setStatus("Reconnecting")
			if failures == 1 then
				self.ui:log("Connection interrupted. " .. messageOf(result))
			end
			task.wait(math.min(2 ^ math.min(failures - 1, 3), 8))
		end
	end
end

return HttpTransport
