--//script by xenomus
--//discord: xxxenomus

local plugin = script:FindFirstAncestorOfClass("Plugin") or getfenv().plugin
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local modules = script.Parent:WaitForChild("Modules")
local GitHub = require(modules.Github)
local PathUtil = require(modules.PathUtil)
local Hash = require(modules.Hash)

local isBusy = false
local currentJob = 0
local wantedStatus = "ready"
local wantedStatusColor = Color3.fromRGB(170, 170, 180)
local lastPushDuration = 0
local TOKEN_MASK = "*****"
local tokenValue = ""
local TOKEN_STORE_KEY = "gitmolderTokenProfiles"
local tokenProfiles = {}
local tokenProfileOrder = {}
local selectedTokenName = nil

--ui
local toolbar = plugin:CreateToolbar("Gitmolder")
local settingsBtn = toolbar:CreateButton("GM settings", "open settings", "")
local gitBtn = toolbar:CreateButton("Gitmolder", "open gitmolder", "")

local settingsInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, false, 420, 360, 360, 320)
local settingsWidget = plugin:CreateDockWidgetPluginGui("GitmolderSettingsWidget", settingsInfo)
settingsWidget.Title = "GM settings"
settingsWidget.Enabled = false
settingsBtn.Click:Connect(function()
	settingsWidget.Enabled = not settingsWidget.Enabled
end)

local gitInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, true, 420, 220, 360, 200)
local gitWidget = plugin:CreateDockWidgetPluginGui("GitmolderMainWidget", gitInfo)
gitWidget.Title = "Gitmolder"
gitWidget.Enabled = false
gitBtn.Click:Connect(function()
	gitWidget.Enabled = not gitWidget.Enabled
end)

local pad = 12

local function mkRoot(parent)
	local root = Instance.new("Frame")
	root.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent
	return root
end

local function mkScroller(parent)
	local frame = Instance.new("ScrollingFrame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.ScrollBarThickness = 6
	frame.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, pad)
	padding.PaddingRight = UDim.new(0, pad)
	padding.PaddingTop = UDim.new(0, pad)
	padding.PaddingBottom = UDim.new(0, pad)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		frame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + pad)
	end)

	return frame
end

local settingsRoot = mkRoot(settingsWidget)
local settingsFrame = mkScroller(settingsRoot)

local gitRoot = mkRoot(gitWidget)
local gitFrame = mkScroller(gitRoot)

local function mkLabeledBox(parent, label, placeholder, isPassword)
	local wrap = Instance.new("Frame")
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.Parent = parent
	wrap.AutomaticSize = Enum.AutomaticSize.Y

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, 0, 0, 16)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
	lbl.Text = label
	lbl.Parent = wrap

	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, 26)
	box.Position = UDim2.fromOffset(0, 18)
	box.Font = Enum.Font.Gotham
	box.TextSize = 12
	box.TextColor3 = Color3.fromRGB(235, 235, 240)
	box.PlaceholderText = placeholder
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Text = ""
	box.Parent = wrap
	if isPassword then
		box.TextEditable = true
	end

	return box
end

local ownerBox = mkLabeledBox(settingsFrame, "owner", "xenomus", false)
local repoBox = mkLabeledBox(settingsFrame, "repo", "xenomus-dev", false)
local branchBox = mkLabeledBox(settingsFrame, "branch", "main", false)
local prefixBox = mkLabeledBox(settingsFrame, "prefix (optional)", "portfolio/", false)
local tokenBox = mkLabeledBox(settingsFrame, "token (needs repo access)", "ghp_...", true)
local tokenNameBox = mkLabeledBox(settingsFrame, "token name", "main-account", false)

local msgBox = mkLabeledBox(gitFrame, "commit msg", "sync from studio", false)

local tokenSelectRow = Instance.new("Frame")
tokenSelectRow.BackgroundTransparency = 1
tokenSelectRow.Size = UDim2.new(1, 0, 0, 28)
tokenSelectRow.Parent = gitFrame

local primaryRow = Instance.new("Frame")
primaryRow.BackgroundTransparency = 1
primaryRow.Size = UDim2.new(1, 0, 0, 0)
primaryRow.Parent = gitFrame
primaryRow.AutomaticSize = Enum.AutomaticSize.Y

local grid = Instance.new("UIGridLayout")
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.CellSize = UDim2.new(1, 0, 0, 28)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = primaryRow

local cancelRow = Instance.new("Frame")
cancelRow.BackgroundTransparency = 1
cancelRow.Size = UDim2.new(1, 0, 0, 28)
cancelRow.Parent = gitFrame

local function mkBtn(parent, text)
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = Color3.fromRGB(44, 44, 54)
	btn.BorderSizePixel = 0
	btn.Size = UDim2.fromOffset(120, 28)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(245, 245, 250)
	btn.Text = text
	btn.AutoButtonColor = true
	btn.Parent = parent
	return btn
end

local saveTokenBtn = mkBtn(settingsFrame, "save named token")
saveTokenBtn.Size = UDim2.new(1, 0, 0, 28)
saveTokenBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 170)

local tokenSelectBtn = mkBtn(tokenSelectRow, "token: manual")
tokenSelectBtn.Size = UDim2.new(1, 0, 0, 28)

local pushBtn = mkBtn(primaryRow, "push")
local cancelBtn = mkBtn(cancelRow, "cancel")

pushBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 85)

local statusLbl = Instance.new("TextLabel")
statusLbl.BackgroundTransparency = 1
statusLbl.Size = UDim2.new(1, 0, 0, 18)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextColor3 = Color3.fromRGB(170, 170, 180)
statusLbl.Text = "ready"
statusLbl.Parent = gitFrame

--im updating status on heartbeat so parallel tasks dont fight each other
RunService.Heartbeat:Connect(function()
	if statusLbl.Text ~= wantedStatus then
		statusLbl.Text = wantedStatus
	end
	if statusLbl.TextColor3 ~= wantedStatusColor then
		statusLbl.TextColor3 = wantedStatusColor
	end
end)

local function trim(s)
	return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function hasTokenProfileName(name)
	for _, n in ipairs(tokenProfileOrder) do
		if n == name then
			return true
		end
	end
	return false
end

local function saveTokenProfiles()
	local payload = {
		order = {},
		items = {},
	}

	for _, name in ipairs(tokenProfileOrder) do
		local tok = tokenProfiles[name]
		if type(name) == "string" and name ~= "" and type(tok) == "string" and tok ~= "" then
			table.insert(payload.order, name)
			payload.items[name] = tok
		end
	end

	pcall(function()
		plugin:SetSetting(TOKEN_STORE_KEY, payload)
	end)
end

local function loadTokenProfiles()
	tokenProfiles = {}
	tokenProfileOrder = {}

	local ok, data = pcall(function()
		return plugin:GetSetting(TOKEN_STORE_KEY)
	end)
	if not ok or type(data) ~= "table" then
		return
	end

	local items = type(data.items) == "table" and data.items or {}
	if type(data.order) == "table" then
		for _, name in ipairs(data.order) do
			local tok = items[name]
			if type(name) == "string" and name ~= "" and type(tok) == "string" and tok ~= "" then
				tokenProfiles[name] = tok
				table.insert(tokenProfileOrder, name)
			end
		end
	end

	for name, tok in pairs(items) do
		if type(name) == "string" and name ~= "" and type(tok) == "string" and tok ~= "" and not hasTokenProfileName(name) then
			tokenProfiles[name] = tok
			table.insert(tokenProfileOrder, name)
		end
	end
end

local function updateTokenSelectButton()
	if selectedTokenName and tokenProfiles[selectedTokenName] then
		tokenSelectBtn.Text = ("token: %s"):format(selectedTokenName)
	else
		tokenSelectBtn.Text = "token: manual"
	end
end

local function persistSelectedTokenName()
	pcall(function()
		local existing = plugin:GetSetting("gitmolderUi")
		local ui = type(existing) == "table" and existing or {}
		ui.selectedToken = selectedTokenName
		plugin:SetSetting("gitmolderUi", ui)
	end)
end

local setStatus

local function refreshTokenBox()
	if tokenValue ~= "" then
		tokenBox.Text = TOKEN_MASK
	else
		tokenBox.Text = ""
	end
end

tokenBox.Focused:Connect(function()
	if isBusy then return end
	tokenBox.Text = ""
end)

tokenBox.FocusLost:Connect(function()
	local typed = trim(tokenBox.Text)
	if typed ~= "" and typed ~= TOKEN_MASK then
		tokenValue = typed
	end
	refreshTokenBox()
end)

saveTokenBtn.MouseButton1Click:Connect(function()
	if isBusy then return end

	local typed = trim(tokenBox.Text)
	if typed ~= "" and typed ~= TOKEN_MASK then
		tokenValue = typed
	end

	local profileName = trim(tokenNameBox.Text)
	local tok = trim(tokenValue)
	if profileName == "" then
		setStatus("enter token name first", "error")
		return
	end
	if tok == "" then
		setStatus("enter token first", "error")
		return
	end

	if not hasTokenProfileName(profileName) then
		table.insert(tokenProfileOrder, profileName)
	end
	tokenProfiles[profileName] = tok
	selectedTokenName = profileName
	saveTokenProfiles()
	updateTokenSelectButton()
	persistSelectedTokenName()
	refreshTokenBox()
	setStatus(("saved token '%s'"):format(profileName), "success")
end)

tokenSelectBtn.MouseButton1Click:Connect(function()
	if isBusy then return end

	if #tokenProfileOrder == 0 then
		selectedTokenName = nil
		updateTokenSelectButton()
		setStatus("no saved tokens (using manual)", "error")
		return
	end

	if selectedTokenName == nil then
		selectedTokenName = tokenProfileOrder[1]
	else
		local idx = nil
		for i, name in ipairs(tokenProfileOrder) do
			if name == selectedTokenName then
				idx = i
				break
			end
		end

		if idx == nil then
			selectedTokenName = tokenProfileOrder[1]
		elseif idx < #tokenProfileOrder then
			selectedTokenName = tokenProfileOrder[idx + 1]
		else
			selectedTokenName = nil
		end
	end

	updateTokenSelectButton()
	persistSelectedTokenName()
	if selectedTokenName then
		setStatus(("selected token '%s'"):format(selectedTokenName), "progress")
	else
		setStatus("selected manual token", "progress")
	end
end)

setStatus = function(text, kind)
	wantedStatus = text
	if kind == "success" then
		wantedStatusColor = Color3.fromRGB(120, 220, 140)
	elseif kind == "error" then
		wantedStatusColor = Color3.fromRGB(230, 120, 120)
	else
		wantedStatusColor = Color3.fromRGB(170, 170, 180)
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
		if enabled then
			if guiObj == pushBtn then
				guiObj.BackgroundColor3 = Color3.fromRGB(60, 140, 85)
			else
				guiObj.BackgroundColor3 = Color3.fromRGB(44, 44, 54)
			end
		else
			guiObj.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
		end
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
	setUiEnabled(tokenSelectBtn, not state)
	setUiEnabled(cancelBtn, state)
	setUiEnabled(ownerBox, not state)
	setUiEnabled(repoBox, not state)
	setUiEnabled(branchBox, not state)
	setUiEnabled(prefixBox, not state)
	setUiEnabled(tokenBox, not state)
	setUiEnabled(tokenNameBox, not state)
	setUiEnabled(saveTokenBtn, not state)
	setUiEnabled(msgBox, not state)
end

local function readCfg()
	local visibleToken = trim(tokenBox.Text)
	if visibleToken ~= "" and visibleToken ~= TOKEN_MASK then
		tokenValue = visibleToken
	end

	local selectedTokenValue = nil
	if selectedTokenName and tokenProfiles[selectedTokenName] then
		selectedTokenValue = trim(tokenProfiles[selectedTokenName])
	end

	local resolvedToken = selectedTokenValue or trim(tokenValue)

	local cfg = {
		owner = trim(ownerBox.Text),
		repo = trim(repoBox.Text),
		branch = trim(branchBox.Text),
		prefix = trim(prefixBox.Text),
		token = resolvedToken,
		msg = trim(msgBox.Text),
		selectedToken = selectedTokenName,
	}
	if cfg.branch == "" then cfg.branch = "main" end
	if cfg.msg == "" then cfg.msg = "sync from studio" end
	return cfg
end

local function cancelJob()
	currentJob += 1
	isBusy = false
	setBusy(false)
	setStatus("canceled", "error")
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
	removed = {},
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
			sourceIndex.removed[data.path] = true
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

local function trackInst(inst, sourceOpt, markDirtyOnAdd)
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
	if markDirtyOnAdd then
		markDirty(inst)
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
				trackInst(inst, nil, true)
			end))
			table.insert(sourceIndex.rootConns, svc.DescendantRemoving:Connect(function(inst)
				removeInst(inst)
			end))
		end
	end
end

local function rebuildIndex(prefix, jobId)
	--cleanup existing connections to prevent leaks
	for _, conns in pairs(sourceIndex.conns) do
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end
	sourceIndex.conns = {}

	sourceIndex.prefix = prefix or ""
	sourceIndex.byInst = {}
	sourceIndex.byPath = {}
	sourceIndex.dirty = {}
	sourceIndex.removed = {}

	ensureRootWatchers()

	setStatus("scanning studio...", "progress")
	local scanned = 0

	local function onProgress(count)
		scanned = count
		if (count % 25) == 0 then
			setStatus(("scanning studio... (%d)"):format(count), "progress")
		end
	end

	local sources, canceled = PathUtil.collectLuaSources(sourceIndex.prefix, nil, onProgress, function()
		return isCanceled(jobId)
	end)
	if canceled then
		return false, "canceled"
	end

	for _, item in pairs(sources) do
		trackInst(item.inst, item.source, false)
	end

	sourceIndex.initialized = true
	return true
end

local function refreshDirty(jobId)
	if next(sourceIndex.dirty) == nil then return true end
	setStatus("updating changed scripts...", "progress")
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
	return true
end

local function doPush(cfg, jobId)
	local tStart = os.clock()
	if cfg.owner == "" or cfg.repo == "" or cfg.branch == "" then
		return false, "fill owner/repo/branch"
	end
	if cfg.token == "" then
		return false, "token missing"
	end
	if not HttpService.HttpEnabled then
		return false, "http disabled"
	end

	saveUi(cfg)

	if (not sourceIndex.initialized) or (sourceIndex.prefix ~= (cfg.prefix or "")) then
		local ok, err = rebuildIndex(cfg.prefix, jobId)
		if not ok then return false, err end
	end

	local cache = loadCache(cfg)
	if next(sourceIndex.dirty) == nil and next(sourceIndex.removed) == nil then
		return true, "no changes (cached)"
	end
	local okDirty, errDirty = refreshDirty(jobId)
	if not okDirty then return false, errDirty end

	local changed = {}
	local cacheNext = cache

	local changedCount = 0

	local meta = cache.__meta or {}
	cacheNext.__meta = meta

	for path, _ in pairs(sourceIndex.removed) do
		cacheNext[path] = nil
	end

	for inst, _ in pairs(sourceIndex.dirty) do
		if inst and inst:IsDescendantOf(game) and inst:IsA("LuaSourceContainer") then
			local data = sourceIndex.byInst[inst]
			if data and data.path and data.source then
				local h = data.hash or Hash.fnv1a32(data.source)
				local cached = getCacheEntry(cache, data.path)
				local cachedHash = cached and cached.hash or nil
				if cachedHash ~= h then
					changedCount += 1
					table.insert(changed, {
						path = data.path,
						mode = "100644",
						type = "blob",
						content = data.source,
					})
					setCacheEntry(cacheNext, data.path, h, nil)
				else
					setCacheEntry(cacheNext, data.path, h, cached.sha)
				end
			end
		end
	end
	if changedCount == 0 then
		sourceIndex.dirty = {}
		sourceIndex.removed = {}
		return true, "no changes"
	end

	local function retry(attempts, fn)
		local lastErr = nil
		for i = 1, attempts do
			if isCanceled(jobId) then return nil, "canceled" end
			local res = {fn()}
			if res[1] ~= nil then
				return table.unpack(res)
			end
			lastErr = nil
			for _, v in pairs(res) do
				if type(v) == "string" then
					lastErr = v
					break
				end
			end
			if lastErr and tostring(lastErr):find("timeout") then
				task.wait(2)
			else
				task.wait(0.2 * i)
			end
		end
		return nil, lastErr
	end

	if changedCount == 1 and next(sourceIndex.removed) == nil then
		local only = changed[1]
		setStatus("pushing 1 file...", "progress")
		local cached = getCacheEntry(cache, only.path)
		local fileSha = cached and cached.sha or nil
		if not fileSha then
			local sha, shaErr = retry(3, function()
				return GitHub.getFileSha(cfg.owner, cfg.repo, cfg.branch, only.path, cfg.token)
			end)
			if sha then
				fileSha = sha
			elseif shaErr and not tostring(shaErr):find("http 404", 1, true) then
				return false, shaErr
			end
		end
		local newFileSha, commitSha, err, putDt = retry(3, function()
			return GitHub.putFile(
				cfg.owner,
				cfg.repo,
				cfg.branch,
				cfg.token,
				only.path,
				cfg.msg,
				only.content,
				fileSha
			)
		end)
		if not newFileSha then
			if err and (err:find("http 409", 1, true) or err:find("http 422", 1, true) or err:find("sha", 1, true)) then
				local sha, shaErr = retry(3, function()
					return GitHub.getFileSha(cfg.owner, cfg.repo, cfg.branch, only.path, cfg.token)
				end)
				if not sha then
					return false, shaErr or "failed to get file sha"
				end
				newFileSha, commitSha, err, putDt = retry(3, function()
					return GitHub.putFile(
						cfg.owner,
						cfg.repo,
						cfg.branch,
						cfg.token,
						only.path,
						cfg.msg,
						only.content,
						sha
					)
				end)
			else
				setStatus("single-file push failed, trying batch...", "progress")
			end
		end
		if newFileSha then
			setCacheEntry(cacheNext, only.path, Hash.fnv1a32(only.content), newFileSha)
			meta.head = commitSha or meta.head
			meta.tree = nil
			cacheNext.__meta = meta
			saveCache(cfg, cacheNext)
			sourceIndex.dirty = {}
			sourceIndex.removed = {}
			local dt = os.clock() - tStart
			local perf = ""
			if putDt and putDt > 5 then
				perf = (" [put %.1fs]"):format(putDt)
			end
			lastPushDuration = dt
			return true, ("pushed %d files (commit %s) (%.1fs)%s"):format(changedCount, tostring(commitSha and commitSha:sub(1, 7) or "unknown"), dt, perf)
		elseif err then
			setStatus("single-file push failed, trying batch...", "progress")
		end
	end

	if meta.head and meta.tree then
		setStatus(("batch committing (%d changed, cached head)..."):format(changedCount), "progress")
		local okFast, msgFast, newHead, newTree, timingFast = GitHub.batchCommit(
			cfg.owner,
			cfg.repo,
			cfg.branch,
			cfg.token,
			cfg.msg,
			meta.tree,
			meta.head,
			changed
		)
		if okFast == true then
			meta.head = newHead or meta.head
			meta.tree = newTree or meta.tree
			cacheNext.__meta = meta
			saveCache(cfg, cacheNext)
			sourceIndex.dirty = {}
			sourceIndex.removed = {}
			local dt = os.clock() - tStart
			local perf = ""
			if timingFast and ((timingFast.tree or 0) + (timingFast.commit or 0) + (timingFast.ref or 0)) > 5 then
				perf = (" [tree %.1fs, commit %.1fs, ref %.1fs]"):format(timingFast.tree or 0, timingFast.commit or 0, timingFast.ref or 0)
			end
			lastPushDuration = dt
			return true, ("pushed %d files (%s) (%.1fs)%s"):format(changedCount, tostring(msgFast), dt, perf)
		elseif okFast == false then
			return true, msgFast
		elseif okFast == nil then
			if tostring(msgFast):find("timeout", 1, true) then
				return false, msgFast
			end
		end
	end

	setStatus(("getting head commit (%d changed)..."):format(changedCount), "progress")
	local headCommitSha, err1 = retry(3, function()
		return GitHub.getRefCommitSha(cfg.owner, cfg.repo, cfg.branch, cfg.token)
	end)
	if not headCommitSha then return false, err1 end
	if isCanceled(jobId) then return false, "canceled" end

	local baseTreeSha, err2 = retry(3, function()
		return GitHub.getCommitTreeSha(cfg.owner, cfg.repo, headCommitSha, cfg.token)
	end)
	if not baseTreeSha then return false, err2 end
	if isCanceled(jobId) then return false, "canceled" end

	setStatus("batch committing...", "progress")
	local ok, msgOrErr, newHead, newTree, timing = nil, nil, nil, nil, nil
	for i = 1, 3 do
		ok, msgOrErr, newHead, newTree, timing = GitHub.batchCommit(
			cfg.owner,
			cfg.repo,
			cfg.branch,
			cfg.token,
			cfg.msg,
			baseTreeSha,
			headCommitSha,
			changed
		)
		if ok ~= nil then
			break
		end
	end

	if ok == nil then
		return false, msgOrErr
	end

	if ok == false then
		return true, msgOrErr
	end

	meta.head = newHead or headCommitSha
	meta.tree = newTree or baseTreeSha
	cacheNext.__meta = meta
	saveCache(cfg, cacheNext)
	sourceIndex.dirty = {}
	sourceIndex.removed = {}
	local dt = os.clock() - tStart
	local perf = ""
	if timing and ((timing.tree or 0) + (timing.commit or 0) + (timing.ref or 0)) > 5 then
		perf = (" [tree %.1fs, commit %.1fs, ref %.1fs]"):format(timing.tree or 0, timing.commit or 0, timing.ref or 0)
	end
	lastPushDuration = dt
	return true, ("pushed %d files (%s) (%.1fs)%s"):format(changedCount, tostring(msgOrErr), dt, perf)
end

local function runJob(fn)
	if isBusy then return end
	setBusy(true)
	setStatus("starting...", "progress")
	currentJob += 1
	local jobId = currentJob

	local cfg = readCfg()
	task.spawn(function()
		local ok, success, msg = pcall(fn, cfg, jobId)
		if not isCanceled(jobId) then
			if not ok then
				setStatus("error: " .. tostring(success), "error")
				warn(tostring(success))
			elseif not success then
				setStatus("fail: " .. tostring(msg), "error")
				warn(tostring(msg))
			else
				setStatus(tostring(msg), "success")
			end
			setBusy(false)
		end
	end)

	task.delay(300, function()
		if not isCanceled(jobId) and isBusy then
			cancelJob()
			setStatus("timeout", "error")
			warn("timeout")
		end
	end)
end

pushBtn.MouseButton1Click:Connect(function()
	runJob(doPush)
end)


--restore ui
do
	loadTokenProfiles()

	local saved = loadUi()
	if saved then
		ownerBox.Text = saved.owner or ""
		repoBox.Text = saved.repo or ""
		branchBox.Text = saved.branch or "main"
		prefixBox.Text = saved.prefix or ""
		tokenValue = trim(saved.token or "")
		selectedTokenName = trim(saved.selectedToken or "")
		if selectedTokenName == "" or not tokenProfiles[selectedTokenName] then
			selectedTokenName = nil
		end
		refreshTokenBox()
		msgBox.Text = saved.msg or "sync from studio"
	end

	updateTokenSelectButton()
	refreshTokenBox()
end

setBusy(false)
gitWidget.Enabled = true
setStatus("ready (fast batch mode)", "progress")
