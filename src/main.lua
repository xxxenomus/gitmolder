--github sync plugin (scripts only)
--requires: game settings -> security -> allow http requests

local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")

local toolbar = plugin:CreateToolbar("Gitmolder")
local openButton = toolbar:CreateButton("Gitmolder", "Open Gitmolder", "")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	true,
	false,
	520,
	360,
	420,
	280
)

--timeouts
local requestTimeoutSeconds = 25
local jobTimeoutSeconds = 180

--job control
local activeJobId = 0
local runningJobId = 0

local widget = plugin:CreateDockWidgetPluginGuiAsync("GitSyncWidget", widgetInfo)
widget.Title = "Gitmolder"
widget.Enabled = false

openButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

--ui
local root = Instance.new("Frame")
root.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = widget

local pad = 12
local y = pad


local function jobCanceled(jobId)
	return activeJobId ~= jobId
end

local function makeLabel(text, yPos)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0, 130, 0, 22)
	lbl.Position = UDim2.new(0, pad, 0, yPos)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Color3.fromRGB(220, 220, 230)
	lbl.Text = text
	lbl.Parent = root
	return lbl
end

local function makeBox(yPos, placeholder, isSecret)
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, -(pad * 2), 0, 26)
	box.Position = UDim2.new(0, pad, 0, yPos)
	box.Font = Enum.Font.Code
	box.TextSize = 12
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextColor3 = Color3.fromRGB(235, 235, 245)
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(140, 140, 155)
	box.ClearTextOnFocus = false
	box.Parent = root
	if isSecret then
		box.TextEditable = true
	end
	return box
end

local function makeSmallBox(xPos, yPos, width, placeholder)
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	box.BorderSizePixel = 0
	box.Size = UDim2.new(0, width, 0, 26)
	box.Position = UDim2.new(0, xPos, 0, yPos)
	box.Font = Enum.Font.Code
	box.TextSize = 12
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextColor3 = Color3.fromRGB(235, 235, 245)
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(140, 140, 155)
	box.ClearTextOnFocus = false
	box.Parent = root
	return box
end

local function makeButton(text, xPos, yPos, width)
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	btn.BorderSizePixel = 0
	btn.Size = UDim2.new(0, width, 0, 34)
	btn.Position = UDim2.new(0, xPos, 0, yPos)
	btn.Font = Enum.Font.GothamSemibold
	btn.TextSize = 13
	btn.TextColor3 = Color3.fromRGB(240, 240, 255)
	btn.Text = text
	btn.AutoButtonColor = true
	btn.Parent = root
	return btn
end

local function makeDivider(yPos)
	local line = Instance.new("Frame")
	line.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	line.BorderSizePixel = 0
	line.Size = UDim2.new(1, -(pad * 2), 0, 1)
	line.Position = UDim2.new(0, pad, 0, yPos)
	line.Parent = root
	return line
end

local ownerLabel = makeLabel("owner", y); y += 18
local ownerBox = makeSmallBox(pad, y, 160, "xenomus"); 
local repoBox = makeSmallBox(pad + 170, y, 200, "repo"); 
local branchBox = makeSmallBox(pad + 380, y, 116, "main"); 
y += 34

local prefixLabel = makeLabel("path prefix", y); y += 18
local prefixBox = makeBox(y, "src", false); y += 34

local tokenLabel = makeLabel("github token (pat)", y); y += 18
local tokenBox = makeBox(y, "ghp_...", true); y += 34

local msgLabel = makeLabel("commit msg", y); y += 18
local msgBox = makeBox(y, "studio sync", false); y += 34

makeDivider(y); y += 12

local commitPushButton = makeButton("commit + push", pad, y, 200)
local pullButton = makeButton("pull", pad + 212, y, 120)
local saveButton = makeButton("save cfg", pad + 344, y, 144)
y += 44

local statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Size = UDim2.new(1, -(pad * 2), 0, 80)
statusLabel.Position = UDim2.new(0, pad, 0, y)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
statusLabel.Text = "ready"
statusLabel.Parent = root

--settings
local function loadSettings()
	ownerBox.Text = tostring(plugin:GetSetting("gitOwner") or "")
	repoBox.Text = tostring(plugin:GetSetting("gitRepo") or "")
	branchBox.Text = tostring(plugin:GetSetting("gitBranch") or "main")
	prefixBox.Text = tostring(plugin:GetSetting("gitPrefix") or "src")
	msgBox.Text = tostring(plugin:GetSetting("gitCommitMsg") or "studio sync")
	tokenBox.Text = tostring(plugin:GetSetting("gitToken") or "")
end

local function saveSettings()
	plugin:SetSetting("gitOwner", ownerBox.Text)
	plugin:SetSetting("gitRepo", repoBox.Text)
	plugin:SetSetting("gitBranch", branchBox.Text)
	plugin:SetSetting("gitPrefix", prefixBox.Text)
	plugin:SetSetting("gitCommitMsg", msgBox.Text)
	plugin:SetSetting("gitToken", tokenBox.Text)
end

loadSettings()

saveButton.MouseButton1Click:Connect(function()
	saveSettings()
	statusLabel.Text = "saved cfg"
end)

--github api helpers
local function makeHeaders(token, hasBody)
	local headers = {
		["Accept"] = "application/vnd.github+json",
		["X-GitHub-Api-Version"] = "2022-11-28",
		["Authorization"] = "Bearer " .. token,
	}

	if hasBody then
		headers["Content-Type"] = "application/json"
	end

	return headers
end
local function requestJson(url, method, headers, bodyTable)
	local body
	if bodyTable then
		body = httpService:JSONEncode(bodyTable)
	end

	local ok, res = pcall(function()
		return httpService:RequestAsync({
			Url = url,
			Method = method,
			Headers = headers,
			Body = body,
		})
	end)

	if not ok then
		return { StatusCode = 0, Body = "" }, { message = tostring(res) }
	end

	local decoded
	if res.Body and #res.Body > 0 then
		local ok2, data = pcall(function()
			return httpService:JSONDecode(res.Body)
		end)
		if ok2 then
			decoded = data
		end
	end

	return res, decoded
end


local function getBranchRef(owner, repo, branch, token)
	local headers = makeHeaders(token, false)
	local url = ("https://api.github.com/repos/%s/%s/branches/%s"):format(owner, repo, branch)

	local res, data = requestJson(url, "GET", headers)
	if res.StatusCode ~= 200 then
		local msg = data and data.message or "bad response"
		return nil, ("cant read branch ref: %s (%d)"):format(msg, res.StatusCode)
	end

	if not data or not data.commit or not data.commit.sha then
		return nil, "cant read branch ref: missing commit sha"
	end

	return data.commit.sha
end


local function getCommitTreeSha(owner, repo, commitSha, token)
	local headers = makeHeaders(token, false)
	local url = ("https://api.github.com/repos/%s/%s/git/commits/%s"):format(owner, repo, commitSha)
	local res, data = requestJson(url, "GET", headers)
	if res.StatusCode ~= 200 then
		local msg = data and data.message or "bad response"
		return nil, ("cant read commit: %s (%d)"):format(msg, res.StatusCode)
	end
	return data.tree.sha
end

local function createBlob(owner, repo, token, content)
	local headers = makeHeaders(token, true)
	local url = ("https://api.github.com/repos/%s/%s/git/blobs"):format(owner, repo)

	local body = {
		content = httpService:Base64Encode(content),
		encoding = "base64",
	}

	local res, data = requestJson(url, "POST", headers, body)
	if res.StatusCode ~= 201 then
		local msg = data and data.message or "bad response"
		return nil, ("cant create blob: %s (%d)"):format(msg, res.StatusCode)
	end
	return data.sha
end

local function createTree(owner, repo, token, baseTreeSha, treeItems)
	local headers = makeHeaders(token, true)
	local url = ("https://api.github.com/repos/%s/%s/git/trees"):format(owner, repo)

	local body = {
		base_tree = baseTreeSha,
		tree = treeItems,
	}

	local res, data = requestJson(url, "POST", headers, body)
	if res.StatusCode ~= 201 then
		local msg = data and data.message or "bad response"
		return nil, ("cant create tree: %s (%d)"):format(msg, res.StatusCode)
	end
	return data.sha
end

local function createCommit(owner, repo, token, message, treeSha, parentCommitSha)
	local headers = makeHeaders(token, true)
	local url = ("https://api.github.com/repos/%s/%s/git/commits"):format(owner, repo)

	local body = {
		message = message,
		tree = treeSha,
		parents = { parentCommitSha },
	}

	local res, data = requestJson(url, "POST", headers, body)
	if res.StatusCode ~= 201 then
		local msg = data and data.message or "bad response"
		return nil, ("cant create commit: %s (%d)"):format(msg, res.StatusCode)
	end
	return data.sha
end

local function updateBranchRef(owner, repo, branch, token, newCommitSha)
	local headers = makeHeaders(token, true)
	local url = ("https://api.github.com/repos/%s/%s/git/refs/heads/%s"):format(owner, repo, branch)

	local body = {
		sha = newCommitSha,
		force = false,
	}

	local res, data = requestJson(url, "PATCH", headers, body)
	if res.StatusCode ~= 200 then
		local msg = data and data.message or "bad response"
		return false, ("cant update ref: %s (%d)"):format(msg, res.StatusCode)
	end
	return true
end

local function getRecursiveTree(owner, repo, token, treeSha)
	local headers = makeHeaders(token, false)
	local url = ("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1"):format(owner, repo, treeSha)
	local res, data = requestJson(url, "GET", headers)
	if res.StatusCode ~= 200 then
		local msg = data and data.message or "bad response"
		return nil, ("cant read tree: %s (%d)"):format(msg, res.StatusCode)
	end
	return data.tree
end

local function getBlobContent(owner, repo, token, blobSha)
	local headers = makeHeaders(token, false)
	local url = ("https://api.github.com/repos/%s/%s/git/blobs/%s"):format(owner, repo, blobSha)
	local res, data = requestJson(url, "GET", headers)
	if res.StatusCode ~= 200 then
		local msg = data and data.message or "bad response"
		return nil, ("cant read blob: %s (%d)"):format(msg, res.StatusCode)
	end

	local content = data.content or ""
	content = string.gsub(content, "%s+", "")
	local decoded = httpService:Base64Decode(content)
	return decoded
end

--export/import mapping
local function getScriptSuffix(inst)
	if inst:IsA("LocalScript") then
		return ".client.lua"
	end
	if inst:IsA("Script") then
		return ".server.lua"
	end
	return ".lua"
end

local function stripSuffix(fileName)
	if string.sub(fileName, -11) == ".server.lua" then
		return string.sub(fileName, 1, -12), "Script"
	end
	if string.sub(fileName, -11) == ".client.lua" then
		return string.sub(fileName, 1, -12), "LocalScript"
	end
	if string.sub(fileName, -4) == ".lua" then
		return string.sub(fileName, 1, -5), "ModuleScript"
	end
	return nil, nil
end

local function getTopServiceName(inst)
	--grab the ancestor whose parent is game (aka the service)
	local cur = inst
	while cur and cur.Parent ~= game do
		cur = cur.Parent
	end
	if cur and cur.Parent == game then
		return cur.Name
	end
	return nil
end

local function buildRepoPath(inst, pathPrefix)
	local parts = {}

	local topService = getTopServiceName(inst)
	if not topService then
		return nil
	end

	table.insert(parts, topService)

	local cur = inst.Parent
	while cur and cur.Parent and cur.Parent ~= game do
		table.insert(parts, 2, cur.Name)
		cur = cur.Parent
	end

	local fileName = inst.Name .. getScriptSuffix(inst)
	table.insert(parts, fileName)

	local prefix = pathPrefix or "src"
	if prefix ~= "" and string.sub(prefix, -1) ~= "/" then
		prefix = prefix .. "/"
	end

	return prefix .. table.concat(parts, "/")
end

local function collectLuaSources()
	local out = {}

	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("LuaSourceContainer") then
			local ok, src = pcall(function()
				return inst.Source
			end)
			if ok and src ~= nil then
				local path = buildRepoPath(inst, prefixBox.Text)
				if path then
					out[path] = {
						className = inst.ClassName,
						source = src,
					}
				end
			end
		end
	end

	return out
end

local function getServiceByName(serviceName)
	local ok, svc = pcall(function()
		return game:GetService(serviceName)
	end)
	if ok then
		return svc
	end
	return nil
end

local function ensureFolder(parent, folderName)
	local existing = parent:FindFirstChild(folderName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing and not existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = parent
	return folder
end

local function ensureScript(parent, scriptName, className)
	local existing = parent:FindFirstChild(scriptName)
	if existing and existing.ClassName == className then
		return existing
	end

	local inst = Instance.new(className)
	inst.Name = scriptName
	inst.Parent = parent
	return inst
end

local function splitPath(path)
	local parts = {}
	for part in string.gmatch(path, "([^/]+)") do
		table.insert(parts, part)
	end
	return parts
end

local function startsWith(str, prefix)
	return string.sub(str, 1, #prefix) == prefix
end

local function commitAndPush(config, jobId)
	local owner = config.owner
	local repo = config.repo
	local branch = config.branch
	local token = config.token
	local pathPrefix = config.pathPrefix
	local commitMessage = config.commitMessage

	if owner == "" or repo == "" or branch == "" or token == "" then
		return false, "fill owner/repo/branch/token first"
	end

	local scriptsMap = collectLuaSources()
	local fileCount = 0
	for _ in pairs(scriptsMap) do
		fileCount += 1
	end

	if fileCount == 0 then
		return false, "no scripts found"
	end

	statusLabel.Text = ("reading branch...\nfiles: %d"):format(fileCount)

	local branchCommitSha, err1 = getBranchRef(owner, repo, branch, token)
	if not branchCommitSha then
		return false, err1
	end
	if jobCanceled(jobId) then
		return false, "canceled"
	end

	local baseTreeSha, err2 = getCommitTreeSha(owner, repo, branchCommitSha, token)
	if not baseTreeSha then
		return false, err2
	end
	if jobCanceled(jobId) then
		return false, "canceled"
	end

	local treeItems = {}
	local done = 0

	for path, data in pairs(scriptsMap) do
		if jobCanceled(jobId) then
			return false, "canceled"
		end

		done += 1
		statusLabel.Text = ("pushing %d/%d\n%s"):format(done, fileCount, path)

		local blobSha, blobErr = createBlob(owner, repo, token, data.source)
		if not blobSha then
			return false, blobErr
		end

		table.insert(treeItems, {
			path = path,
			mode = "100644",
			type = "blob",
			sha = blobSha,
		})
	end

	if jobCanceled(jobId) then
		return false, "canceled"
	end

	statusLabel.Text = "building tree..."

	local newTreeSha, err3 = createTree(owner, repo, token, baseTreeSha, treeItems)
	if not newTreeSha then
		return false, err3
	end
	if jobCanceled(jobId) then
		return false, "canceled"
	end

	statusLabel.Text = "creating commit..."

	local newCommitSha, err4 = createCommit(owner, repo, token, commitMessage, newTreeSha, branchCommitSha)
	if not newCommitSha then
		return false, err4
	end
	if jobCanceled(jobId) then
		return false, "canceled"
	end

	statusLabel.Text = "updating branch ref..."

	local ok5, err5 = updateBranchRef(owner, repo, branch, token, newCommitSha)
	if not ok5 then
		return false, err5
	end

	return true, ("done. committed %d files to %s/%s (%s)"):format(fileCount, owner, repo, branch)
end

local function pullAndApply(config, jobId)
	local owner = config.owner
	local repo = config.repo
	local branch = config.branch
	local token = config.token
	local pathPrefix = config.pathPrefix

	if owner == "" or repo == "" or branch == "" or token == "" then
		return false, "fill owner/repo/branch/token first"
	end

	statusLabel.Text = "reading branch..."

	local branchCommitSha, err1 = getBranchRef(owner, repo, branch, token)
	if not branchCommitSha then
		return false, err1
	end
	if jobCanceled(jobId) then
		return false, "canceled"
	end

	local baseTreeSha, err2 = getCommitTreeSha(owner, repo, branchCommitSha, token)
	if not baseTreeSha then
		return false, err2
	end
	if jobCanceled(jobId) then
		return false, "canceled"
	end

	statusLabel.Text = "reading repo tree..."

	local treeList, err3 = getRecursiveTree(owner, repo, token, baseTreeSha)
	if not treeList then
		return false, err3
	end
	if jobCanceled(jobId) then
		return false, "canceled"
	end

	local prefix = pathPrefix or "src"
	if prefix ~= "" and string.sub(prefix, -1) ~= "/" then
		prefix = prefix .. "/"
	end

	local scriptEntries = {}
	for _, item in ipairs(treeList) do
		if item.type == "blob" and item.path then
			if startsWith(item.path, prefix) and string.sub(item.path, -4) == ".lua" then
				table.insert(scriptEntries, item)
			end
		end
	end

	if #scriptEntries == 0 then
		return false, "no lua files found under prefix"
	end

	local applied = 0

	for i, item in ipairs(scriptEntries) do
		if jobCanceled(jobId) then
			return false, "canceled"
		end

		statusLabel.Text = ("pulling %d/%d\n%s"):format(i, #scriptEntries, item.path)

		local content, blobErr = getBlobContent(owner, repo, token, item.sha)
		if not content then
			return false, blobErr
		end

		local relPath = string.sub(item.path, #prefix + 1)
		local parts = splitPath(relPath)

		if #parts < 2 then
			continue
		end

		local serviceName = parts[1]
		local svc = getServiceByName(serviceName)
		if not svc then
			continue
		end

		local fileName = parts[#parts]
		local baseName, className = stripSuffix(fileName)
		if not baseName or not className then
			continue
		end

		local parent = svc
		for p = 2, #parts - 1 do
			parent = ensureFolder(parent, parts[p])
		end

		local scriptInst = ensureScript(parent, baseName, className)

		local okSet = pcall(function()
			scriptInst.Source = content
		end)

		if okSet then
			applied += 1
		end
	end

	return true, ("done. applied %d scripts into studio"):format(applied)
end

local isBusy = false




local function setUiBusy(state)
	commitPushButton.AutoButtonColor = not state
	pullButton.AutoButtonColor = not state
	saveButton.AutoButtonColor = not state
end

local function runJob(jobFn)
	if isBusy then
		statusLabel.Text = "busy rn chill"
		return
	end

	activeJobId += 1
	local jobId = activeJobId
	runningJobId = jobId
	isBusy = true
	setUiBusy(true)

	--watchdog unlock if it drags too long
	task.delay(jobTimeoutSeconds, function()
		if isBusy and activeJobId == jobId then
			--invalidate this job so late http replies dont overwrite ui
			activeJobId += 1
			runningJobId = activeJobId
			isBusy = false
			setUiBusy(false)
			statusLabel.Text = ("timed out after %ds"):format(jobTimeoutSeconds)
		end
	end)

	task.spawn(function()
		local cfg = {
			owner = ownerBox.Text,
			repo = repoBox.Text,
			branch = branchBox.Text ~= "" and branchBox.Text or "main",
			pathPrefix = prefixBox.Text ~= "" and prefixBox.Text or "src",
			token = tokenBox.Text,
			commitMessage = msgBox.Text ~= "" and msgBox.Text or "studio sync",
		}

		saveSettings()

		local ok, resultOk, resultMsg = pcall(function()
			local a, b = jobFn(cfg, jobId)
			return a, b
		end)

		--if a newer job started or watchdog fired, ignore this result
		if activeJobId ~= jobId then
			return
		end

		if not ok then
			statusLabel.Text = "failed: " .. tostring(resultOk)
		else
			statusLabel.Text = (resultOk and resultMsg) or ("failed: " .. tostring(resultMsg))
		end

		isBusy = false
		setUiBusy(false)
	end)
end

commitPushButton.MouseButton1Click:Connect(function()
	runJob(function(cfg, jobId)
		return commitAndPush(cfg, jobId)
	end)
end)

pullButton.MouseButton1Click:Connect(function()
	runJob(function(cfg, jobId)
		return pullAndApply(cfg, jobId)
	end)
end)

--tiny hint for ppl who forget
if not runService:IsRunning() then
	statusLabel.Text = "ready\n(remember: enable http requests in game settings)"
end
