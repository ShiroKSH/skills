local CleanerState = {}
CleanerState.__index = CleanerState

local stages = { "dirty", "inspected", "wet", "dry", "counted", "bundled" }
local stations = {
	wash = { input = "inspected", output = "wet", amount = 12, seconds = 4.5 },
	dry = { input = "wet", output = "dry", amount = 12, seconds = 5.2 },
	count = { input = "dry", output = "counted", amount = 14, seconds = 3.8 },
	bundle = { input = "counted", output = "bundled", amount = 18, seconds = 2.4 },
}
CleanerState.upgrades = {
	dryer = { cost = 50, title = "Dryer speed" },
	counter = { cost = 75, title = "Counter sorter" },
	auto = { cost = 125, title = "Auto washer" },
	vault = { cost = 250, title = "Vault capacity" },
	dock = { cost = 400, title = "Shipping dock" },
}

function CleanerState.new()
	return setmetatable({ owner = nil, states = {}, jobs = {}, nextJobId = 0 }, CleanerState)
end

function CleanerState:state(userId)
	if not self.states[userId] then
		local state = { cash = 0, upgrades = {} }
		for _, stage in ipairs(stages) do state[stage] = 0 end
		self.states[userId] = state
	end
	return self.states[userId]
end

function CleanerState:held(userId)
	local state = self:state(userId)
	local total = 0
	for _, stage in ipairs(stages) do total += state[stage] end
	for _, job in pairs(self.jobs) do
		if job.userId == userId then total += job.amount end
	end
	return total
end

function CleanerState:capacity(userId)
	return self:state(userId).upgrades.vault and 190 or 70
end

function CleanerState:value(userId)
	local upgrades = self:state(userId).upgrades
	return 3 + (upgrades.counter and 1 or 0) + (upgrades.dock and 2 or 0)
end

function CleanerState:claim(userId)
	if self.owner and self.owner ~= userId then return false, "Business already claimed" end
	self.owner = userId
	self:state(userId)
	return true, "Business claimed"
end

function CleanerState:release(userId)
	if self.owner ~= userId then return end
	-- Refund before releasing ownership. Old job IDs cannot complete a new owner's work.
	for station, job in pairs(self.jobs) do
		if job.userId == userId then
			self:state(userId)[job.input] += job.amount
			self.jobs[station] = nil
		end
	end
	self.owner = nil
end

function CleanerState:requireOwner(userId)
	if self.owner == nil then return false, "Claim the business first" end
	if self.owner ~= userId then return false, "This business belongs to another player" end
	return true
end

function CleanerState:take(userId)
	local allowed, message = self:requireOwner(userId)
	if not allowed then return false, message end
	local state = self:state(userId)
	local amount = math.min(self:capacity(userId) - self:held(userId), state.upgrades.vault and 28 or 16)
	if amount <= 0 then return false, "Capacity full. Process and ship a batch" end
	state.dirty += amount
	return true, "Collected " .. amount .. " dirty bills"
end

function CleanerState:inspect(userId)
	local allowed, message = self:requireOwner(userId)
	if not allowed then return false, message end
	local state = self:state(userId)
	local amount = math.min(state.dirty, state.upgrades.counter and 24 or 12)
	if amount == 0 then return false, "Collect dirty bills first" end
	state.dirty -= amount
	state.inspected += amount
	return true, "Inspected " .. amount .. " bills"
end

function CleanerState:start(userId, station, now)
	local allowed, message = self:requireOwner(userId)
	if not allowed then return false, message end
	local definition = stations[station]
	if not definition then return false, "Unknown station" end
	if self.jobs[station] then return false, "Station is already running" end
	local state = self:state(userId)
	if station == "wash" and state.upgrades.auto and state.inspected == 0 then
		local amount = math.min(state.dirty, 20)
		state.dirty -= amount
		state.inspected += amount
	end
	local amount, seconds = definition.amount, definition.seconds
	if station == "wash" and state.upgrades.auto then amount, seconds = 24, 2.2 end
	if station == "dry" and state.upgrades.dryer then amount, seconds = 26, 2.4 end
	if station == "count" and state.upgrades.counter then amount, seconds = 28, 1.6 end
	if station == "bundle" and state.upgrades.dock then amount, seconds = 35, 1.2 end
	amount = math.min(state[definition.input], amount)
	if amount == 0 then return false, "No " .. definition.input .. " bills ready" end
	state[definition.input] -= amount
	self.nextJobId += 1
	local job = {
		id = self.nextJobId, userId = userId, input = definition.input, output = definition.output,
		amount = amount, startedAt = now, endsAt = now + seconds,
	}
	self.jobs[station] = job
	return true, "Processing " .. amount .. " bills", job
end

function CleanerState:complete(station, jobId, now)
	local job = self.jobs[station]
	if not job or job.id ~= jobId or now < job.endsAt then return false end
	if self.owner ~= job.userId then return false end
	self:state(job.userId)[job.output] += job.amount
	self.jobs[station] = nil
	return true, job
end

function CleanerState:sell(userId)
	local allowed, message = self:requireOwner(userId)
	if not allowed then return false, message end
	local state = self:state(userId)
	if state.bundled == 0 then return false, "Bundle counted bills before shipping" end
	local payout = state.bundled * self:value(userId)
	state.bundled = 0
	state.cash += payout
	return true, "Shipped for $" .. payout
end

function CleanerState:upgrade(userId, key)
	local allowed, message = self:requireOwner(userId)
	if not allowed then return false, message end
	local definition = self.upgrades[key]
	if not definition then return false, "Unknown upgrade" end
	local state = self:state(userId)
	if state.upgrades[key] then return false, "Upgrade already purchased" end
	if state.cash < definition.cost then return false, "Need $" .. definition.cost end
	state.cash -= definition.cost
	state.upgrades[key] = true
	return true, definition.title .. " purchased"
end

function CleanerState:nextStep(userId)
	if self.owner == nil then return "Claim the business at the entrance" end
	if self.owner ~= userId then return "Business claimed by another player" end
	local state = self:state(userId)
	if state.bundled > 0 then return "Ship bundles at the loading dock" end
	if state.counted > 0 and not self.jobs.bundle then return "Bundle counted bills at the press" end
	if state.dry > 0 and not self.jobs.count then return "Count dry bills at the sorter" end
	if state.wet > 0 and not self.jobs.dry then return "Move wet bills to the dryer" end
	if (state.inspected > 0 or (state.upgrades.auto and state.dirty > 0)) and not self.jobs.wash then
		return "Load bills into the washer"
	end
	if state.dirty > 0 then return "Inspect dirty bills at the table" end
	if next(self.jobs) then return "Batch processing. Check the station countdown" end
	return "Collect a batch of dirty bills"
end

return CleanerState
