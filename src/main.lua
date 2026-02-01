local plugin = script:FindFirstAncestorOfClass("Plugin") or getfenv().plugin
local RunService = game:GetService("RunService")

local modules = script.Parent:WaitForChild("Modules")
local GitHub = require(modules.Github)
local PathUtil = require(modules.PathUtil)
local WorkerPool = require(modules.WorkerPool)
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

--im updating status on heartbeat so parallel tasks dont fight each other
RunService.Heartbeat:Connect(function()
	if statusLbl.Text ~= wantedStatus then
		statusLbl.Text = wantedStatus
	end
end)

local function trim(s)
	return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1"))
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
end

cancelBtn.MouseButton1Click:Connect(cancelJob)

local function isCanceled(jobId)
	return currentJob ~= jobId
end

local function doPush(cfg, jobId)
	if cfg.owner == "" or cfg.repo == "" or cfg.branch == "" then
		return false, "fill owner/repo/branch"
	end
	if cfg.token == "" then
		return false, "token missing"
	end

	saveUi(cfg)

	wantedStatus = "scanning studio..."
	local sources = PathUtil.collectLuaSources(cfg.prefix)

	if isCanceled(jobId) then return false, "canceled" end

	local cache = loadCache(cfg)
	local changed = {}
	local cacheNext = {}

	local totalLocal = 0
	local changedCount = 0

	for path, item in pairs(sources) do
		totalLocal += 1
		local h = Hash.fnv1a32(item.source)
		cacheNext[path] = h
		if cache[path] ~= h then
			changedCount += 1
			table.insert(changed, {
				path = path,
				mode = "100644",
				type = "blob",
				content = item.source,
			})
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
				table.insert(files, item.path)
			end
		end
	end

	if #files == 0 then
		return false, "no lua files found"
	end

	wantedStatus = ("downloading %d files (raw github)..."):format(#files)

	local cache = loadCache(cfg)
	local cacheNext = {}

	local function dl(path, idx)
		if isCanceled(jobId) then return nil end
		local body = nil

		local rawBody = GitHub.downloadRaw(cfg.owner, cfg.repo, cfg.branch, path, cfg.token)
		if rawBody then
			body = rawBody
		else
			--if raw fails (private weirdness), i bail with error so i notice fast
			error("download failed: " .. path)
		end

		return { path = path, content = body }
	end

	local lastProgAt = 0
	local function onProgress(done, total)
		local now = os.clock()
		if (now - lastProgAt) > 0.12 or done == total then
			lastProgAt = now
			wantedStatus = ("downloading %d/%d..."):format(done, total)
		end
	end

	local errors, results = WorkerPool.run(files, 10, dl, onProgress, function()
		return isCanceled(jobId)
	end)

	if isCanceled(jobId) then return false, "canceled" end
	if #errors > 0 then
		return false, tostring(errors[1].err)
	end

	wantedStatus = "applying to studio..."

	local applied = 0
	for _, item in ipairs(results) do
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
						scr.Source = item.content
						applied += 1
						cacheNext[item.path] = Hash.fnv1a32(item.content)
					end
				end
			end
		end
	end

	saveCache(cfg, cacheNext)
	return true, ("pulled %d files"):format(applied)
end

local function runJob(fn)
	if isBusy then return end
	setBusy(true)
	wantedStatus = "starting..."
	currentJob += 1
	local jobId = currentJob

	local cfg = readCfg()

	task.spawn(function()
		local ok, success, msg = pcall(fn, cfg, jobId)
		if not isCanceled(jobId) then
			if not ok then
				wantedStatus = "error: " .. tostring(success)
			elseif not success then
				wantedStatus = "fail: " .. tostring(msg)
			else
				wantedStatus = tostring(msg)
			end
			setBusy(false)
		end
	end)

	task.delay(300, function()
		if not isCanceled(jobId) and isBusy then
			cancelJob()
			wantedStatus = "timeout"
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
