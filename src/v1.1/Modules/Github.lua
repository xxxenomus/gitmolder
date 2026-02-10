--//script by xenomus
--//discord: xxxenomus

local HttpService = game:GetService("HttpService")
local Base64 = require(script.Parent.Base64)

local GitHub = {}
local REQUEST_TIMEOUT = 25
local REQUEST_POLL_INTERVAL = 0.05

local function requestAsync(req)
	local done = false
	local res = nil
	local reqErr = nil

	task.spawn(function()
		local ok, response = pcall(function()
			return HttpService:RequestAsync(req)
		end)
		if ok then
			res = response
		else
			reqErr = response
		end
		done = true
	end)

	local startedAt = os.clock()
	while not done do
		if (os.clock() - startedAt) > REQUEST_TIMEOUT then
			return nil, "timeout"
		end
		task.wait(REQUEST_POLL_INTERVAL)
	end

	if not res then
		return nil, tostring(reqErr)
	end
	return res, nil
end

local function requestJson(method, url, token, bodyTable)
	local headers = {
		["Accept"] = "application/vnd.github+json",
		["X-GitHub-Api-Version"] = "2022-11-28",
		["Cache-Control"] = "no-cache",
	}

	if token and token ~= "" then
		headers["Authorization"] = "Bearer " .. token
	end

	if url:find("?", 1, true) then
		url = url .. "&_t=" .. HttpService:GenerateGUID(false)
	else
		url = url .. "?_t=" .. HttpService:GenerateGUID(false)
	end

	local req = {
		Url = url,
		Method = method,
		Headers = headers,
	}

	if bodyTable ~= nil then
		req.Body = HttpService:JSONEncode(bodyTable)
		req.Headers["Content-Type"] = "application/json"
	end

	local res, reqErr = requestAsync(req)
	if not res then
		return nil, reqErr
	end
	if not res.Success then
		return nil, ("http %d: %s"):format(res.StatusCode, tostring(res.Body))
	end

	if res.Body == nil or res.Body == "" then
		return {}, nil
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(res.Body)
	end)

	if not ok then
		return nil, "bad json from github"
	end

	return decoded, nil
end

local function requestRaw(url, token)
	local headers = {
		["Cache-Control"] = "no-cache",
	}

	if token and token ~= "" then
		headers["Authorization"] = "Bearer " .. token
	end

	if url:find("?", 1, true) then
		url = url .. "&_t=" .. HttpService:GenerateGUID(false)
	else
		url = url .. "?_t=" .. HttpService:GenerateGUID(false)
	end

	local res, reqErr = requestAsync({
		Url = url,
		Method = "GET",
		Headers = headers,
	})

	if not res then
		return nil, reqErr
	end
	if not res.Success then
		return nil, ("http %d"):format(res.StatusCode)
	end

	return res.Body, nil
end

local function encodePath(path)
	local parts = {}
	for part in path:gmatch("[^/]+") do
		table.insert(parts, HttpService:UrlEncode(part))
	end
	return table.concat(parts, "/")
end

function GitHub.getRefCommitSha(owner, repo, branch, token)
	local url = ("https://api.github.com/repos/%s/%s/git/ref/heads/%s"):format(owner, repo, branch)
	local data, err = requestJson("GET", url, token, nil)
	if not data then return nil, err end
	return data.object and data.object.sha or nil, nil
end

function GitHub.getCommitTreeSha(owner, repo, commitSha, token)
	local url = ("https://api.github.com/repos/%s/%s/git/commits/%s"):format(owner, repo, commitSha)
	local data, err = requestJson("GET", url, token, nil)
	if not data then return nil, err end
	return data.tree and data.tree.sha or nil, nil
end

function GitHub.getTreeRecursive(owner, repo, treeSha, token)
	local url = ("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1"):format(owner, repo, treeSha)
	local data, err = requestJson("GET", url, token, nil)
	if not data then return nil, err end
	return data.tree or nil, nil
end

--big speed win: batch all changed files into a single tree, then 1 commit, then update ref
function GitHub.batchCommit(owner, repo, branch, token, message, baseTreeSha, parentCommitSha, treeEntries)
	local timing = {}

	local t0 = os.clock()
	local treeUrl = ("https://api.github.com/repos/%s/%s/git/trees"):format(owner, repo)
	local treeData, treeErr = requestJson("POST", treeUrl, token, {
		base_tree = baseTreeSha,
		tree = treeEntries,
	})
	timing.tree = os.clock() - t0
	if not treeData then return nil, treeErr end

	local newTreeSha = treeData.sha
	if not newTreeSha then return nil, "no tree sha from github" end

	--if nothing changed, github can return same tree sha
	if newTreeSha == baseTreeSha then
		return false, "no changes"
	end

	local t1 = os.clock()
	local commitUrl = ("https://api.github.com/repos/%s/%s/git/commits"):format(owner, repo)
	local commitData, commitErr = requestJson("POST", commitUrl, token, {
		message = message,
		tree = newTreeSha,
		parents = { parentCommitSha },
	})
	timing.commit = os.clock() - t1
	if not commitData then return nil, commitErr end

	local newCommitSha = commitData.sha
	if not newCommitSha then return nil, "no commit sha from github" end

	local t2 = os.clock()
	local refUrl = ("https://api.github.com/repos/%s/%s/git/refs/heads/%s"):format(owner, repo, branch)
	local _, refErr = requestJson("PATCH", refUrl, token, {
		sha = newCommitSha,
		force = false,
	})
	timing.ref = os.clock() - t2
	if refErr then return nil, refErr end

	return true, ("commit %s"):format(newCommitSha:sub(1, 7)), newCommitSha, newTreeSha, timing
end

function GitHub.downloadRaw(owner, repo, branch, path, token)
	local url = ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(owner, repo, branch, path)
	return requestRaw(url, token)
end

function GitHub.getFileSha(owner, repo, branch, path, token)
	local encPath = encodePath(path)
	local url = ("https://api.github.com/repos/%s/%s/contents/%s?ref=%s"):format(owner, repo, encPath, HttpService:UrlEncode(branch))
	local t0 = os.clock()
	local data, err = requestJson("GET", url, token, nil)
	local dt = os.clock() - t0
	if not data then return nil, err end
	return data.sha or nil, nil, dt
end

function GitHub.putFile(owner, repo, branch, token, path, message, content, sha)
	local encPath = encodePath(path)
	local url = ("https://api.github.com/repos/%s/%s/contents/%s"):format(owner, repo, encPath)
	local body = {
		message = message,
		content = Base64.encode(content),
		branch = branch,
	}
	if sha then
		body.sha = sha
	end

	local t0 = os.clock()
	local data, err = requestJson("PUT", url, token, body)
	local dt = os.clock() - t0
	if not data then return nil, nil, err end
	local newFileSha = data.content and data.content.sha or nil
	local commitSha = data.commit and data.commit.sha or nil
	return newFileSha, commitSha, nil, dt
end

return GitHub
