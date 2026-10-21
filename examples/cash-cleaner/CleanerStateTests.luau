return function(CleanerState)
	local passed = {}
	local function test(name, callback)
		callback()
		table.insert(passed, name)
	end
	local function prepared(stage)
		local cleaner = CleanerState.new()
		cleaner:claim(101)
		cleaner:state(101)[stage] = 12
		return cleaner
	end
	local cases = {
		{ "wash", "inspected", "wet" }, { "dry", "wet", "dry" },
		{ "count", "dry", "counted" }, { "bundle", "counted", "bundled" },
	}
	test("owner leaving releases the business", function()
		local cleaner = prepared("dirty")
		cleaner:release(101)
		assert(cleaner:claim(202))
		assert(cleaner.owner == 202 and cleaner:state(101).dirty == 12)
	end)
	for _, values in ipairs(cases) do
		local station, input, output = table.unpack(values)
		test(station .. " preserves capacity and refunds cancelled work", function()
			local cleaner = prepared(input)
			cleaner:state(101).dirty = 58
			local ok, _, job = cleaner:start(101, station, 0)
			assert(ok and cleaner:held(101) == 70)
			assert(not cleaner:take(101))
			assert(not cleaner:complete(station, job.id, job.endsAt - 0.01))
			cleaner:release(101)
			assert(cleaner:held(101) == 70 and cleaner:state(101)[input] == 12)
			cleaner:claim(202)
			cleaner:state(202)[input] = 12
			local started, _, nextJob = cleaner:start(202, station, 10)
			assert(started and nextJob.id ~= job.id)
			assert(not cleaner:complete(station, job.id, 100))
			assert(cleaner.jobs[station] == nextJob and cleaner:state(202)[output] == 0)
			assert(cleaner:complete(station, nextJob.id, nextJob.endsAt))
			assert(cleaner:state(202)[output] == 12 and cleaner:held(202) == 12)
			assert(not cleaner:complete(station, nextJob.id, 100))
		end)
	end
	test("complete production loop pays only once", function()
		local cleaner = CleanerState.new()
		cleaner:claim(101)
		assert(cleaner:take(101))
		assert(cleaner:inspect(101))
		local now = 0
		for _, values in ipairs(cases) do
			local ok, _, job = cleaner:start(101, values[1], now)
			assert(ok)
			now = job.endsAt
			assert(cleaner:complete(values[1], job.id, now))
		end
		assert(cleaner:sell(101))
		assert(cleaner:state(101).cash == 36 and cleaner:held(101) == 4)
		assert(not cleaner:sell(101) and cleaner:state(101).cash == 36)
	end)
	test("foreign players cannot change owner inventory or upgrades", function()
		local cleaner = prepared("bundled")
		cleaner:state(101).cash = 500
		assert(not cleaner:claim(202))
		assert(not cleaner:take(202))
		assert(not cleaner:inspect(202))
		assert(not cleaner:start(202, "wash", 0))
		assert(not cleaner:sell(202))
		assert(not cleaner:upgrade(202, "dryer"))
		cleaner:release(202)
		assert(cleaner.owner == 101 and cleaner:state(101).cash == 500)
		assert(cleaner:state(101).bundled == 12)
	end)
	test("upgrades charge once and alter a real station", function()
		local callbacks = {}
		for key in pairs(CleanerState.upgrades) do callbacks[key] = function() return key end end
		for key, callback in pairs(callbacks) do assert(callback() == key, "Luau closures must retain each loop binding") end
		local cleaner = prepared("wet")
		cleaner:state(101).cash = 100
		assert(cleaner:upgrade(101, "dryer"))
		assert(not cleaner:upgrade(101, "dryer"))
		assert(cleaner:state(101).cash == 50)
		local ok, _, job = cleaner:start(101, "dry", 20)
		assert(ok and math.abs(job.endsAt - 22.4) < 0.001)
	end)
	return { passed = #passed, checks = passed }
end
