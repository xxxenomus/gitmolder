--gitmolder (scripts only)
--enable: game settings -> security -> allow http requests
--note: i rolled my own base64 cuz some studio builds dont have httpservice:base64encode

local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")

local toolbar = plugin:CreateToolbar("Gitmolder")
local openButton = toolbar:CreateButton("Gitmolder", "open gitmolder", "")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	true,
	false,
	520,
	340,
	420,
	280
)

--config ur timeouts here
local requestTimeoutSeconds = 60
local jobTimeoutSeconds = 300

--job state
local activeJobId = 0
local isBusy = false

--tiny helpers
local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sanitizeToken(token)
	--kill whitespace/hidden chars from textbox, keep a-z 0-9 and _
	return tostring(token or ""):gsub("[^%w_]+", "")
end

local function jobCanceled(jobId)
	return activeJobId ~= jobId
end

--base64 (pure lua)
--base64 (chunk-safe, no huge string.byte ranges)
local base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local base64Index = {}
for i = 1, #base64Chars do
	base64Index[base64Chars:sub(i, i)] = i - 1
end
base64Index["="] = 0

local function base64Encode(data)
	if data == nil or data == "" then
		return ""
	end

	local out = table.create(math.ceil(#data * 4 / 3))
	local outN = 0
	local len = #data

	for i = 1, len, 3 do
		local b1 = string.byte(data, i) or 0
		local b2 = string.byte(data, i + 1)
		local b3 = string.byte(data, i + 2)

		local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)

		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64

		outN += 1; out[outN] = base64Chars:sub(c1 + 1, c1 + 1)
		outN += 1; out[outN] = base64Chars:sub(c2 + 1, c2 + 1)

		if b2 ~= nil then
			outN += 1; out[outN] = base64Chars:sub(c3 + 1, c3 + 1)
		else
			outN += 1; out[outN] = "="
		end

		if b3 ~= nil then
			outN += 1; out[outN] = base64Chars:sub(c4 + 1, c4 + 1)
		else
			outN += 1; out[outN] = "="
		end
	end

	return table.concat(out)
end

local function base64Decode(data)
	if data == nil or data == "" then
		return ""
	end

	data = tostring(data):gsub("%s+", "")

	local out = table.create(math.floor(#data * 3 / 4))
	local outN = 0
	local len = #data
	local i = 1

	while i <= len do
		local s1 = data:sub(i, i); i += 1
		local s2 = data:sub(i, i); i += 1
		local s3 = data:sub(i, i); i += 1
		local s4 = data:sub(i, i); i += 1

		local c1 = base64Index[s1]
		local c2 = base64Index[s2]
		local c3 = base64Index[s3]
		local c4 = base64Index[s4]

		if c1 == nil or c2 == nil or c3 == nil or c4 == nil then
			break
		end

		local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4

		local b1 = math.floor(n / 65536) % 256
		local b2 = math.floor(n / 256) % 256
		local b3 = n % 256

		outN += 1; out[outN] = string.char(b1)
		if s3 ~= "=" then
			outN += 1; out[outN] = string.char(b2)
		end
		if s4 ~= "=" then
			outN += 1; out[outN] = string.char(b3)
		end
	end

	return table.concat(out)
end


--dock widget
local widget
do
	local ok, w = pcall(function()
		return plugin:CreateDockWidgetPluginGuiAsync("GitmolderWidget", widgetInfo)
	end)
	if ok then
		widget = w
	else
		widget = plugin:CreateDockWidgetPluginGui("GitmolderWidget", widgetInfo)
	end
end

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

local function makeLabel(text, yPos)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0, 180, 0, 18)
	lbl.Position = UDim2.new(0, pad, 0, yPos)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Color3.fromRGB(220, 220, 230)
	lbl.Text = text
	lbl.Parent = root
	return lbl
end

local function makeBox(yPos, placeholder)
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

makeLabel("owner / repo / branch", y); y += 16
local ownerBox = makeSmallBox(pad, y, 160, "owner")
local repoBox = makeSmallBox(pad + 170, y, 200, "repo")
local branchBox = makeSmallBox(pad + 380, y, 116, "main")
y += 36

makeLabel("path prefix", y); y += 16
local prefixBox = makeBox(y, "src")
y += 36

makeLabel("github token (fine-grained pat)", y); y += 16
local tokenBox = makeBox(y, "github_pat_...")
y += 36

makeLabel("commit message", y); y += 16
local msgBox = makeBox(y, "studio sync")
y += 36

makeDivider(y); y += 12

local commitPushButton = makeButton("commit + push", pad, y, 220)
local pullButton = makeButton("pull", pad + 232, y, 120)
y += 46

local statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Size = UDim2.new(1, -(pad * 2), 0, 90)
statusLabel.Position = UDim2.new(0, pad, 0, y)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
statusLabel.Text = "ready"
statusLabel.Parent = root

local function setUiBusy(state)
	commitPushButton.AutoButtonColor = not state
	pullButton.AutoButtonColor = not state
end

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
	plugin:SetSetting("gitOwner", trim(ownerBox.Text))
	plugin:SetSetting("gitRepo", trim(repoBox.Text))
	plugin:SetSetting("gitBranch", trim(branchBox.Text))
	plugin:SetSetting("gitPrefix", trim(prefixBox.Text))
	plugin:SetSetting("gitCommitMsg", trim(msgBox.Text))
	plugin:SetSetting("gitToken", trim(tokenBox.Text))
end

loadSettings()

for _, box in ipairs({ ownerBox, repoBox, branchBox, prefixBox, msgBox, tokenBox }) do
	box.FocusLost:Connect(function()
		saveSettings()
	end)
end

--github http
local function makeHeaders(token, hasBody)
	token = sanitizeToken(token)

	local headers = {
		["Accept"] = "application/vnd.github+json",
		["X-GitHub-Api-Version"] = "2022-11-28",
		["Authorization"] = "token " .. token,
	}

	if hasBody then
		headers["Content-Type"] = "application/json"
	end

	return headers
end

local function requestJson(url, method, headers, bodyTable)
	local req = {
		Url = url,
		Method = method,
		Headers = headers,
		Timeout = requestTimeoutSeconds,
	}

	if bodyTable and method ~= "GET" and method ~= "HEAD" then
		req.Body = httpService:JSONEncode(bodyTable)
	end

	local ok, res = pcall(function()
		return httpService:RequestAsync(req)
	end)

	if not ok then
		return { Success = false, StatusCode = 0, Body = "" }, { message = tostring(res) }
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

local function requestJsonRetry(url, method, headers, bodyTable, tries)
	local lastRes, lastData
	for attempt = 1, tries do
		lastRes, lastData = requestJson(url, method, headers, bodyTable)

		local code = lastRes and lastRes.StatusCode or 0
		if code ~= 0 and code ~= 408 and code ~= 502 and code ~= 503 and code ~= 504 then
			return lastRes, lastData
		end

		task.wait(0.5 * attempt)
	end
	return lastRes, lastData
end

--github endpoints
local function getBranchRef(owner, repo, branch, token)
	local headers = makeHeaders(token, false)
	local url = ("https://api.github.com/repos/%s/%s/branches/%s"):format(owner, repo, branch)

	local res, data = requestJsonRetry(url, "GET", headers, nil, 3)
	if not res.Success or res.StatusCode ~= 200 then
		local msg = (data and data.message) or "http failed"
		return nil, ("cant read branch ref: %s (%d)"):format(msg, res.StatusCode or 0)
	end

	local sha = data and data.commit and data.commit.sha
	if not sha then
		return nil, "cant read branch ref: missing commit sha"
	end

	return sha
end

local function getCommitTreeSha(owner, repo, commitSha, token)
	local headers = makeHeaders(token, false)
	local url = ("https://api.github.com/repos/%s/%s/git/commits/%s"):format(owner, repo, commitSha)

	local res, data = requestJsonRetry(url, "GET", headers, nil, 3)
	if not res.Success or res.StatusCode ~= 200 then
		local msg = (data and data.message) or "http failed"
		return nil, ("cant read commit: %s (%d)"):format(msg, res.StatusCode or 0)
	end

	local treeSha = data and data.tree and data.tree.sha
	if not treeSha then
		return nil, "cant read commit: missing tree sha"
	end

	return treeSha
end

local function createBlob(owner, repo, token, content)
	local headers = makeHeaders(token, true)
	local url = ("https://api.github.com/repos/%s/%s/git/blobs"):format(owner, repo)

	local body = {
		content = base64Encode(content),
		encoding = "base64",
	}

	local res, data = requestJsonRetry(url, "POST", headers, body, 3)
	if not res.Success or res.StatusCode ~= 201 then
		local msg = (data and data.message) or "http failed"
		return nil, ("cant create blob: %s (%d)"):format(msg, res.StatusCode or 0)
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

	local res, data = requestJsonRetry(url, "POST", headers, body, 3)
	if not res.Success or res.StatusCode ~= 201 then
		local msg = (data and data.message) or "http failed"
		return nil, ("cant create tree: %s (%d)"):format(msg, res.StatusCode or 0)
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

	local res, data = requestJsonRetry(url, "POST", headers, body, 3)
	if not res.Success or res.StatusCode ~= 201 then
		local msg = (data and data.message) or "http failed"
		return nil, ("cant create commit: %s (%d)"):format(msg, res.StatusCode or 0)
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

	local res, data = requestJsonRetry(url, "PATCH", headers, body, 3)
	if not res.Success or res.StatusCode ~= 200 then
		local msg = (data and data.message) or "http failed"
		return false, ("cant update ref: %s (%d)"):format(msg, res.StatusCode or 0)
	end

	return true
end

local function getRecursiveTree(owner, repo, token, treeSha)
	local headers = makeHeaders(token, false)
	local url = ("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1"):format(owner, repo, treeSha)

	local res, data = requestJsonRetry(url, "GET", headers, nil, 3)
	if not res.Success or res.StatusCode ~= 200 then
		local msg = (data and data.message) or "http failed"
		return nil, ("cant read tree: %s (%d)"):format(msg, res.StatusCode or 0)
	end

	return data.tree
end

local function getBlobContent(owner, repo, token, blobSha)
	local headers = makeHeaders(token, false)
	local url = ("https://api.github.com/repos/%s/%s/git/blobs/%s"):format(owner, repo, blobSha)

	local res, data = requestJsonRetry(url, "GET", headers, nil, 3)
	if not res.Success or res.StatusCode ~= 200 then
		local msg = (data and data.message) or "http failed"
		return nil, ("cant read blob: %s (%d)"):format(msg, res.StatusCode or 0)
	end

	local content = data and data.content or ""
	return base64Decode(content)
end

--export paths
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

local function collectLuaSources(pathPrefix)
	local out = {}

	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("LuaSourceContainer") then
			local ok, src = pcall(function()
				return inst.Source
			end)
			if ok and src ~= nil then
				local path = buildRepoPath(inst, pathPrefix)
				if path then
					out[path] = src
				end
			end
		end
	end

	return out
end

--import helpers
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
	if existing then
		if existing:IsA("Folder") then
			return existing
		end
		return nil
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
	if existing then
		return nil
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

--jobs
local function commitAndPush(cfg, jobId)
	local owner = trim(cfg.owner)
	local repo = trim(cfg.repo)
	local branch = trim(cfg.branch)
	local token = sanitizeToken(trim(cfg.token))
	local pathPrefix = trim(cfg.pathPrefix)
	local commitMessage = trim(cfg.commitMessage)

	if owner == "" or repo == "" or branch == "" or token == "" then
		return false, "fill owner/repo/branch/token first"
	end

	local scriptsMap = collectLuaSources(pathPrefix)
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

	for path, src in pairs(scriptsMap) do
		if jobCanceled(jobId) then
			return false, "canceled"
		end

		done += 1
		statusLabel.Text = ("pushing %d/%d\n%s"):format(done, fileCount, path)

		local blobSha, blobErr = createBlob(owner, repo, token, src)
		if not blobSha then
			return false, blobErr
		end

		treeItems[#treeItems + 1] = {
			path = path,
			mode = "100644",
			type = "blob",
			sha = blobSha,
		}
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

local function pullAndApply(cfg, jobId)
	local owner = trim(cfg.owner)
	local repo = trim(cfg.repo)
	local branch = trim(cfg.branch)
	local token = sanitizeToken(trim(cfg.token))
	local pathPrefix = trim(cfg.pathPrefix)

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

	local prefix = pathPrefix ~= "" and pathPrefix or "src"
	if string.sub(prefix, -1) ~= "/" then
		prefix = prefix .. "/"
	end

	local scriptEntries = {}
	for _, item in ipairs(treeList) do
		if item.type == "blob" and item.path then
			if startsWith(item.path, prefix) and string.sub(item.path, -4) == ".lua" then
				scriptEntries[#scriptEntries + 1] = item
			end
		end
	end

	if #scriptEntries == 0 then
		return false, "no lua files found under prefix"
	end

	local applied = 0
	local skipped = 0

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
			skipped += 1
			continue
		end

		local svc = getServiceByName(parts[1])
		if not svc then
			skipped += 1
			continue
		end

		local fileName = parts[#parts]
		local baseName, className = stripSuffix(fileName)
		if not baseName or not className then
			skipped += 1
			continue
		end

		local parent = svc
		local okPath = true

		for p = 2, #parts - 1 do
			local folder = ensureFolder(parent, parts[p])
			if not folder then
				okPath = false
				break
			end
			parent = folder
		end

		if not okPath then
			skipped += 1
			continue
		end

		local scriptInst = ensureScript(parent, baseName, className)
		if not scriptInst then
			skipped += 1
			continue
		end

		local okSet = pcall(function()
			scriptInst.Source = content
		end)

		if okSet then
			applied += 1
		else
			skipped += 1
		end
	end

	return true, ("done. applied %d scripts (skipped %d)"):format(applied, skipped)
end

local function runJob(jobFn)
	if isBusy then
		statusLabel.Text = "busy rn chill"
		return
	end

	saveSettings()

	activeJobId += 1
	local jobId = activeJobId

	isBusy = true
	setUiBusy(true)

	task.delay(jobTimeoutSeconds, function()
		if isBusy and activeJobId == jobId then
			activeJobId += 1
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

		local ok, resultOk, resultMsg = pcall(function()
			return jobFn(cfg, jobId)
		end)

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
	runJob(commitAndPush)
end)

pullButton.MouseButton1Click:Connect(function()
	runJob(pullAndApply)
end)

if not runService:IsRunning() then
	statusLabel.Text = "ready\n(enable http requests in game settings)"
end
