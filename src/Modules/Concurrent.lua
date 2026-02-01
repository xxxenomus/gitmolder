local HttpService = game:GetService("HttpService")
local minInterval = 0.04 --25 req/sec
local lastReq = 0

local function throttle()
	local now = tick()
	local waitTime = minInterval - (now - lastReq)
	if waitTime > 0 then task.wait(waitTime) end
	lastReq = tick()
end

local function run(items, maxWorkers, fn, onProgress, isCanceled)
	local total = #items
	if total == 0 then return {}, {} end

	local nextIdx = 1
	local completed = 0
	local errors = {}
	local results = table.create(total)

	local function worker()
		while true do
			local idx = nextIdx
			nextIdx += 1
			if idx > total then break end

			--throttle before request
			local ok, res = pcall(fn, items[idx], idx, throttle)
			if ok then
				results[idx] = res
			else
				table.insert(errors, {idx=idx, err=res})
			end

			completed += 1
			if onProgress and (completed % math.max(1, math.floor(total/20)) == 0 or completed == total) then
				onProgress(completed, total)
			end
		end
	end

	for i = 1, math.min(maxWorkers, total) do
		task.spawn(worker)
	end

	local start = tick()
	while completed < total and (tick() - start) < 1800 do
		if isCanceled and isCanceled() then break end
		task.wait(0.05)
	end

	return errors, results
end

return {run = run, throttle = throttle}