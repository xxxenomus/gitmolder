--//script by xenomus
--//discord: xxxenomus

local WorkerPool = {}

--im keeping this simple, raw github is fast so i just cap concurrency
function WorkerPool.run(items, maxWorkers, fn, onProgress, isCanceled)
	local total = #items
	if total == 0 then return {}, {} end

	local nextIdx = 1
	local completed = 0
	local errors = {}
	local results = table.create(total)

	local function worker()
		while true do
			if isCanceled and isCanceled() then break end

			local idx = nextIdx
			nextIdx += 1
			if idx > total then break end

			local ok, res = pcall(fn, items[idx], idx)
			if ok then
				results[idx] = res
			else
				table.insert(errors, { idx = idx, err = res })
			end

			completed += 1
			if onProgress then
				onProgress(completed, total)
			end
		end
	end

	local workers = math.min(maxWorkers or 8, total)
	for _ = 1, workers do
		task.spawn(worker)
	end

	local start = os.clock()
	while completed < total do
		if isCanceled and isCanceled() then break end
		if (os.clock() - start) > 1800 then break end
		task.wait(0.05)
	end

	return errors, results
end

return WorkerPool
