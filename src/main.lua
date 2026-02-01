local plugin = script:FindFirstAncestorOfClass("Plugin") or getfenv().plugin
local RunService = game:GetService("RunService")

local modules = script.Parent:WaitForChild("Modules")
local GitHub = require(modules.Github)
local PathUtil = require(modules.PathUtil)
local Concurrent = require(modules.Concurrent)
local Hash = require(modules.Hash)

local isBusy = false
local currentJob = 0
local wantedStatus = "ready"

--ui
local toolbar = plugin:CreateToolbar("Gitmolder")
local openBtn = toolbar:CreateButton("Gitmolder", "open", "")
local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, false, 520, 360, 420, 320)
local widget = plugin:CreateDockWidgetPluginGui("GitmolderWidget", widgetInfo)
widget.Title = "Gitmolder"
widget.Enabled = false
openBtn.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

local root = Instance.new("Frame")
root.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = widget

local pad = 12
local y = 12

local function mkLabel(text)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, -pad * 2, 0, 18)
	lbl.Position = UDim2.fromOffset(pad, y)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
	lbl.Text = text
	lbl.Parent = root
	y += 18
	return lbl
end

local function mkBox(placeholder, isPassword)
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, -pad * 2, 0, 26)
	box.Position = UDim2.fromOffset(pad, y)
	box.Font = Enum.Font.Gotham
	box.TextSize = 12
	box.TextColor3 = Color3.fromRGB(235, 235, 240)
	box.PlaceholderText = placeholder
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Text = ""
	box.Parent = root
	if isPassword then
		box.TextEditable = true
	end
	y += 30
	return box
end

local function mkBtn(text, w)
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = Color3.fromRGB(44, 44, 54)
	btn.BorderSizePixel = 0
	btn.Size = UDim2.fromOffset(w or 120, 28)
	btn.Position = UDim2.fromOffset(pad, y)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(245, 245, 250)
	btn.Text = text
	btn.AutoButtonColor = true
	btn.Parent = root
	return btn
end

mkLabel("owner")
local ownerBox = mkBox("xenomus", false)

mkLabel("repo")
local repoBox = mkBox("xenomus-dev", false)

mkLabel("branch")
local branchBox = mkBox("main", false)

mkLabel("prefix (optional)")
local prefixBox = mkBox("portfolio/", false)

mkLabel("token (needs repo access)")
local tokenBox = mkBox("ghp_...", true)

mkLabel("commit msg")
local msgBox = mkBox("sync from studio", false)

local pushBtn = mkBtn("push", 120)
pushBtn.Position = UDim2.fromOffset(pad, y)

local pullBtn = mkBtn("pull", 120)
pullBtn.Position = UDim2.fromOffset(pad + 130, y)

local cancelBtn = mkBtn("cancel", 120)
cancelBtn.Position = UDim2.fromOffset(pad + 260, y)

y += 38

local statusLbl = Instance.new("TextLabel")
statusLbl.BackgroundTransparency = 1
statusLbl.Size = UDim2.new(1, -pad * 2, 0, 22)
statusLbl.Position = UDim2.fromOffset(pad, y)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextColor3 = Color3.fromRGB(170, 170, 180)
statusLbl.Text = "ready"
statusLbl.Parent = root

y += 24

local progressBack = Instance.new("Frame")
progressBack.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
progressBack.BorderSizePixel = 0
progressBack.Size = UDim2.new(1, -pad * 2, 0, 6)
progressBack.Position = UDim2.fromOffset(pad, y)
progressBack.Parent = root

local progressFill = Instance.new("Frame")
progressFill.BackgroundColor3 = Color3.fromRGB(80, 170, 255)
progressFill.BorderSizePixel = 0
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.Parent = progressBack

y += 12

local logFrame = Instance.new("ScrollingFrame")
logFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
logFrame.BorderSizePixel = 0
logFrame.Position = UDim2.fromOffset(pad, y)
logFrame.Size = UDim2.new(1, -pad * 2, 1, -(y + pad))
logFrame.ScrollBarThickness = 6
logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
logFrame.Parent = root

local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 2)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent = logFrame

--im updating status on heartbeat so parallel tasks dont fight each other
RunService.Heartbeat:Connect(function()
	if statusLbl.Text ~= wantedStatus then
		statusLbl.Text = wantedStatus
	end
end)

local function trim(s)
	return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local logLines = {}
local maxLogLines = 200

local function setProgress(done, total)
	if total == nil or total <= 0 then
		progressFill.Size = UDim2.new(0, 0, 1, 0)
		return
	end
	local pct = math.clamp(done / total, 0, 1)
	progressFill.Size = UDim2.new(pct, 0, 1, 0)
end

local function logLine(text, isError)
	local ts = ""
	local ok, stamp = pcall(function()
		return os.date("%H:%M:%S")
	end)
	if ok and stamp then
		ts = "[" .. stamp .. "] "
	end

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, -6, 0, 16)
	lbl.Font = Enum.Font.GothamMono
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = isError and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(190, 190, 200)
	lbl.Text = ts .. text
	lbl.Parent = logFrame

	table.insert(logLines, lbl)
	if #logLines > maxLogLines then
		logLines[1]:Destroy()
		table.remove(logLines, 1)
	end

	logFrame.CanvasSize = UDim2.new(0, 0, 0, logLayout.AbsoluteContentSize.Y + 4)
	logFrame.CanvasPosition = Vector2.new(0, math.max(0, logLayout.AbsoluteContentSize.Y - logFrame.AbsoluteSize.Y))

	if isError then
		warn(text)
	else
		print(text)
	end
end

local function getCacheEntry(cache, path)
	local v = cache[path]
	if type(v) == "table" then return v end
	if type(v) == "number" then return { hash = v } end
	return nil
end

local function setCacheEntry(cache, path, hash, sha)
	cache[path] = { hash = hash, sha = sha }
end

local function settingsKey(cfg)
	local p = cfg.prefix or ""
	return ("gitmolder:%s/%s:%s:%s"):format(cfg.owner, cfg.repo, cfg.branch, p)
end

local function loadCache(cfg)
	local key = settingsKey(cfg)
	local ok, data = pcall(function()
		return plugin:GetSetting(key)
	end)
	if ok and type(data) == "table" then
		return data
	end
	return {}
end

local function saveCache(cfg, cache)
	local key = settingsKey(cfg)
	pcall(function()
		plugin:SetSetting(key, cache)
	end)
end

local function saveUi(cfg)
	pcall(function()
		plugin:SetSetting("gitmolderUi", cfg)
	end)
end

local function loadUi()
	local ok, data = pcall(function()
		return plugin:GetSetting("gitmolderUi")
	end)
	return ok and type(data) == "table" and data or nil
end

local function setUiEnabled(guiObj, enabled)
	if guiObj:IsA("TextButton") then
		guiObj.Active = enabled
		guiObj.AutoButtonColor = enabled
		guiObj.BackgroundColor3 = enabled and Color3.fromRGB(44, 44, 54) or Color3.fromRGB(32, 32, 38)
		guiObj.TextColor3 = enabled and Color3.fromRGB(245, 245, 250) or Color3.fromRGB(140, 140, 150)
	elseif guiObj:IsA("TextBox") then
		guiObj.TextEditable = enabled
		guiObj.ClearTextOnFocus = false
		guiObj.BackgroundColor3 = enabled and Color3.fromRGB(28, 28, 34) or Color3.fromRGB(22, 22, 26)
		guiObj.TextColor3 = enabled and Color3.fromRGB(235, 235, 240) or Color3.fromRGB(150, 150, 160)
	end
end

local function setBusy(state)
	isBusy = state

	setUiEnabled(pushBtn, not state)
	setUiEnabled(pullBtn, not state)
	setUiEnabled(cancelBtn, state)

	setUiEnabled(ownerBox, not state)
	setUiEnabled(repoBox, not state)
	setUiEnabled(branchBox, not state)
	setUiEnabled(prefixBox, not state)
	setUiEnabled(tokenBox, not state)
	setUiEnabled(msgBox, not state)
end

local function readCfg()
	local cfg = {
		owner = trim(ownerBox.Text),
		repo = trim(repoBox.Text),
		branch = trim(branchBox.Text),
		prefix = trim(prefixBox.Text),
		token = trim(tokenBox.Text),
		msg = trim(msgBox.Text),
	}
	if cfg.branch == "" then cfg.branch = "main" end
	if cfg.msg == "" then cfg.msg = "sync from studio" end
	return cfg
end

local function cancelJob()
	currentJob += 1
	isBusy = false
	setBusy(false)
	wantedStatus = "canceled"
	setProgress(0, 0)
	logLine("job: canceled", true)
end

cancelBtn.MouseButton1Click:Connect(cancelJob)

local function isCanceled(jobId)
	return currentJob ~= jobId
end

local sourceIndex = {
	prefix = nil,
	byInst = {},
	byPath = {},
	dirty = {},
	conns = {},
	rootConns = {},
	initialized = false,
}

local function disconnectInst(inst)
	local conns = sourceIndex.conns[inst]
	if conns then
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end
	sourceIndex.conns[inst] = nil
end

local function removeInst(inst)
	local data = sourceIndex.byInst[inst]
	if data then
		if data.path then
			sourceIndex.byPath[data.path] = nil
		end
		sourceIndex.byInst[inst] = nil
	end
	sourceIndex.dirty[inst] = nil
	disconnectInst(inst)
end

local function updatePath(inst)
	local data = sourceIndex.byInst[inst]
	if not data then return end
	local newPath = PathUtil.buildRepoPath(inst, sourceIndex.prefix)
	if data.path ~= newPath then
		if data.path then
			sourceIndex.byPath[data.path] = nil
		end
		data.path = newPath
		if newPath then
			sourceIndex.byPath[newPath] = inst
		end
	end
end

local function markDirty(inst)
	sourceIndex.dirty[inst] = true
end

local function trackInst(inst, sourceOpt)
	if not inst:IsA("LuaSourceContainer") then return end
	if sourceIndex.byInst[inst] then
		if sourceOpt ~= nil then
			local data = sourceIndex.byInst[inst]
			data.source = sourceOpt
			data.hash = Hash.fnv1a32(sourceOpt)
		end
		return
	end

	local src = sourceOpt
	if src == nil then
		local ok, s = pcall(function() return inst.Source end)
		if ok and type(s) == "string" then
			src = s
		end
	end
	if src == nil then return end

	local path = PathUtil.buildRepoPath(inst, sourceIndex.prefix)
	sourceIndex.byInst[inst] = { inst = inst, source = src, hash = Hash.fnv1a32(src), path = path }
	if path then
		sourceIndex.byPath[path] = inst
	end

	local conns = {}
	table.insert(conns, inst:GetPropertyChangedSignal("Source"):Connect(function()
		markDirty(inst)
	end))
	table.insert(conns, inst:GetPropertyChangedSignal("Name"):Connect(function()
		updatePath(inst)
		markDirty(inst)
	end))
	table.insert(conns, inst.AncestryChanged:Connect(function()
		if inst:IsDescendantOf(game) then
			updatePath(inst)
		else
			removeInst(inst)
		end
	end))
	sourceIndex.conns[inst] = conns
end

local function ensureRootWatchers()
	if sourceIndex.rootConns and #sourceIndex.rootConns > 0 then return end
	local roots = PathUtil.getDefaultRoots()
	for _, svcName in ipairs(roots) do
		local svc = PathUtil.getService(svcName)
		if svc then
			table.insert(sourceIndex.rootConns, svc.DescendantAdded:Connect(function(inst)
				trackInst(inst)
			end))
			table.insert(sourceIndex.rootConns, svc.DescendantRemoving:Connect(function(inst)
				removeInst(inst)
			end))
		end
	end
end

local function rebuildIndex(prefix, jobId)
	sourceIndex.prefix = prefix or ""
	sourceIndex.byInst = {}
	sourceIndex.byPath = {}
	sourceIndex.dirty = {}

	ensureRootWatchers()

	wantedStatus = "scanning studio..."
	setProgress(0, 0)
	logLine("scan: start")
	local t0 = os.clock()
	local scanned = 0

	local function onProgress(count)
		scanned = count
		if (count % 25) == 0 then
			wantedStatus = ("scanning studio... (%d)"):format(count)
		end
	end

	local sources, canceled = PathUtil.collectLuaSources(sourceIndex.prefix, nil, onProgress, function()
		return isCanceled(jobId)
	end)
	if canceled then
		return false, "canceled"
	end

	for _, item in pairs(sources) do
		trackInst(item.inst, item.source)
	end

	sourceIndex.initialized = true
	logLine(("scan: %d scripts in %.2fs"):format(scanned, os.clock() - t0))
	return true
end

local function refreshDirty(jobId)
	if next(sourceIndex.dirty) == nil then return true end
	wantedStatus = "updating changed scripts..."
	local t0 = os.clock()
	local refreshed = 0
	for inst, _ in pairs(sourceIndex.dirty) do
		if isCanceled(jobId) then return false, "canceled" end
		if inst and inst:IsDescendantOf(game) and inst:IsA("LuaSourceContainer") then
			local ok, src = pcall(function() return inst.Source end)
			if ok and type(src) == "string" then
				local data = sourceIndex.byInst[inst]
				if data then
					data.source = src
					data.hash = Hash.fnv1a32(src)
					updatePath(inst)
					refreshed += 1
				else
					trackInst(inst, src)
				end
			else
				removeInst(inst)
			end
		else
			removeInst(inst)
		end
	end
	sourceIndex.dirty = {}
	logLine(("dirty refresh: %d in %.2fs"):format(refreshed, os.clock() - t0))
	return true
end

local function doPush(cfg, jobId)
	if cfg.owner == "" or cfg.repo == "" or cfg.branch == "" then
		return false, "fill owner/repo/branch"
	end
	if cfg.token == "" then
		return false, "token missing"
	end

	saveUi(cfg)

	if (not sourceIndex.initialized) or (sourceIndex.prefix ~= (cfg.prefix or "")) then
		local ok, err = rebuildIndex(cfg.prefix, jobId)
		if not ok then return false, err end
	end

	local okDirty, errDirty = refreshDirty(jobId)
	if not okDirty then return false, errDirty end

	local cache = loadCache(cfg)
	local changed = {}
	local cacheNext = {}

	local totalLocal = 0
	local changedCount = 0

	for _, data in pairs(sourceIndex.byInst) do
		if data.path and data.source then
			totalLocal += 1
			local h = data.hash or Hash.fnv1a32(data.source)
			local cached = getCacheEntry(cache, data.path)
			local cachedHash = cached and cached.hash or nil
			if cached and cachedHash == h then
				setCacheEntry(cacheNext, data.path, h, cached.sha)
			else
				setCacheEntry(cacheNext, data.path, h, nil)
			end
			if cachedHash ~= h then
			changedCount += 1
			table.insert(changed, {
				path = data.path,
				mode = "100644",
				type = "blob",
				content = data.source,
			})
			end
		end
	end

	--drop cache entries for stuff i deleted locally
	for path, _ in pairs(cache) do
		if cacheNext[path] == nil then
			cacheNext[path] = nil
		end
	end

	if changedCount == 0 then
		return true, ("no changes (%d scripts scanned)"):format(totalLocal)
	end

	wantedStatus = ("getting head commit (%d changed)..."):format(changedCount)
	logLine(("push: %d changed, %d total"):format(changedCount, totalLocal))

	local headCommitSha, err1 = GitHub.getRefCommitSha(cfg.owner, cfg.repo, cfg.branch, cfg.token)
	if not headCommitSha then return false, err1 end
	if isCanceled(jobId) then return false, "canceled" end

	local baseTreeSha, err2 = GitHub.getCommitTreeSha(cfg.owner, cfg.repo, headCommitSha, cfg.token)
	if not baseTreeSha then return false, err2 end
	if isCanceled(jobId) then return false, "canceled" end

	wantedStatus = "batch committing..."
	local ok, msgOrErr = GitHub.batchCommit(
		cfg.owner,
		cfg.repo,
		cfg.branch,
		cfg.token,
		cfg.msg,
		baseTreeSha,
		headCommitSha,
		changed
	)

	if ok == nil then
		return false, msgOrErr
	end

	if ok == false then
		return true, msgOrErr
	end

	saveCache(cfg, cacheNext)
	return true, ("pushed %d files (%s)"):format(changedCount, tostring(msgOrErr))
end

local function doPull(cfg, jobId)
	if cfg.owner == "" or cfg.repo == "" or cfg.branch == "" then
		return false, "fill owner/repo/branch"
	end
	if cfg.token == "" then
		return false, "token missing"
	end

	saveUi(cfg)

	wantedStatus = "getting head commit..."
	local headCommitSha, err1 = GitHub.getRefCommitSha(cfg.owner, cfg.repo, cfg.branch, cfg.token)
	if not headCommitSha then return false, err1 end
	if isCanceled(jobId) then return false, "canceled" end

	local treeSha, err2 = GitHub.getCommitTreeSha(cfg.owner, cfg.repo, headCommitSha, cfg.token)
	if not treeSha then return false, err2 end
	if isCanceled(jobId) then return false, "canceled" end

	wantedStatus = "listing files..."
	local tree, err3 = GitHub.getTreeRecursive(cfg.owner, cfg.repo, treeSha, cfg.token)
	if not tree then return false, err3 end
	if isCanceled(jobId) then return false, "canceled" end

	local prefix = cfg.prefix or ""
	if prefix ~= "" and prefix:sub(-1) ~= "/" then prefix = prefix .. "/" end

	local files = {}
	for _, item in ipairs(tree) do
		if item.type == "blob" and item.path:sub(-4) == ".lua" then
			if prefix == "" or item.path:sub(1, #prefix) == prefix then
				table.insert(files, { path = item.path, sha = item.sha })
			end
		end
	end

	if #files == 0 then
		return false, "no lua files found"
	end

	local cache = loadCache(cfg)
	local cacheNext = {}

	local toDownload = {}
	local skipped = 0
	for _, item in ipairs(files) do
		local cached = getCacheEntry(cache, item.path)
		if cached and cached.sha and cached.sha == item.sha then
			local inst = PathUtil.findScriptByPath(item.path, prefix)
			if inst then
				local ok, src = pcall(function() return inst.Source end)
				if ok and type(src) == "string" and cached.hash and Hash.fnv1a32(src) == cached.hash then
					setCacheEntry(cacheNext, item.path, cached.hash, cached.sha)
					skipped += 1
				else
					table.insert(toDownload, item)
				end
			else
				table.insert(toDownload, item)
			end
		else
			table.insert(toDownload, item)
		end
	end

	if skipped > 0 then
		logLine(("pull: skipping %d unchanged files"):format(skipped))
	end

	wantedStatus = ("downloading %d files (raw github)..."):format(#toDownload)
	logLine(("pull: downloading %d files"):format(#toDownload))
	setProgress(0, #toDownload)
	local tDownload = os.clock()

	local function dl(item, idx, throttle)
		if isCanceled(jobId) then return nil end
		local body = nil
		local lastErr = nil
		for attempt = 1, 3 do
			if throttle then throttle() end
			local rawBody, err = GitHub.downloadRaw(cfg.owner, cfg.repo, cfg.branch, item.path, cfg.token)
			if rawBody then
				body = rawBody
				lastErr = nil
				break
			end
			lastErr = err or "download failed"
			task.wait(0.15 * attempt)
		end

		if not body then
			error(("download failed: %s (%s)"):format(item.path, tostring(lastErr)))
		end

		return { path = item.path, content = body, sha = item.sha }
	end

	local lastProgAt = 0
	local function onProgress(done, total)
		local now = os.clock()
		if (now - lastProgAt) > 0.12 or done == total then
			lastProgAt = now
			wantedStatus = ("downloading %d/%d..."):format(done, total)
			setProgress(done, total)
		end
	end

	local errors, results = Concurrent.run(toDownload, 6, dl, onProgress, function()
		return isCanceled(jobId)
	end)

	if isCanceled(jobId) then return false, "canceled" end
	if #errors > 0 then
		return false, tostring(errors[1].err)
	end
	logLine(("download: %d files in %.2fs"):format(#results, os.clock() - tDownload))

	wantedStatus = "applying to studio..."
	setProgress(0, #results)

	local applied = 0
	local tApply = os.clock()
	for i, item in ipairs(results) do
		if isCanceled(jobId) then return false, "canceled" end
		if item and item.path and item.content then
			local rel = item.path
			if prefix ~= "" then
				rel = rel:sub(#prefix + 1)
			end

			local parts = {}
			for p in rel:gmatch("[^/]+") do
				table.insert(parts, p)
			end

			if #parts >= 2 then
				local svc = PathUtil.getService(parts[1])
				if svc then
					local parent = svc
					for i = 2, #parts - 1 do
						parent = PathUtil.ensureFolder(parent, parts[i])
					end

					local fileName = parts[#parts]
					local name, className = PathUtil.stripSuffix(fileName)
					if name and className then
						local scr = PathUtil.ensureScript(parent, name, className)
						local newHash = Hash.fnv1a32(item.content)
						local needsWrite = true
						local ok, cur = pcall(function() return scr.Source end)
						if ok and type(cur) == "string" then
							if Hash.fnv1a32(cur) == newHash then
								needsWrite = false
							end
						end
						if needsWrite then
							scr.Source = item.content
						end
						applied += 1
						setCacheEntry(cacheNext, item.path, newHash, item.sha)
					end
				end
			end
		end
		if i % 10 == 0 or i == #results then
			setProgress(i, #results)
		end
	end

	saveCache(cfg, cacheNext)
	logLine(("apply: %d files in %.2fs"):format(applied, os.clock() - tApply))
	return true, ("pulled %d files"):format(applied)
end

local function runJob(fn)
	if isBusy then return end
	setBusy(true)
	wantedStatus = "starting..."
	currentJob += 1
	local jobId = currentJob

	local cfg = readCfg()
	logLine("job: start")

	task.spawn(function()
		local ok, success, msg = pcall(fn, cfg, jobId)
		if not isCanceled(jobId) then
			if not ok then
				wantedStatus = "error: " .. tostring(success)
				logLine("job: error - " .. tostring(success), true)
			elseif not success then
				wantedStatus = "fail: " .. tostring(msg)
				logLine("job: fail - " .. tostring(msg), true)
			else
				wantedStatus = tostring(msg)
				logLine("job: done - " .. tostring(msg))
			end
			setBusy(false)
			setProgress(0, 0)
		end
	end)

	task.delay(300, function()
		if not isCanceled(jobId) and isBusy then
			cancelJob()
			wantedStatus = "timeout"
			logLine("job: timeout", true)
		end
	end)
end

pushBtn.MouseButton1Click:Connect(function()
	runJob(doPush)
end)

pullBtn.MouseButton1Click:Connect(function()
	runJob(doPull)
end)

--restore ui
do
	local saved = loadUi()
	if saved then
		ownerBox.Text = saved.owner or ""
		repoBox.Text = saved.repo or ""
		branchBox.Text = saved.branch or "main"
		prefixBox.Text = saved.prefix or ""
		tokenBox.Text = saved.token or ""
		msgBox.Text = saved.msg or "sync from studio"
	end
end

setBusy(false)
wantedStatus = "ready (fast batch mode)"
