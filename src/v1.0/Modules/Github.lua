--//script by xenomus
--//discord: xxxenomus

local HttpService = game:GetService("HttpService")

local GitHub = {}

local REQUEST_TIMEOUT = 30

local function requestAsync(req)
	local done = false
	local res = nil
	local err = nil

	task.spawn(function()
		local ok, result = pcall(function()
			return HttpService:RequestAsync(req)
		end)
		if ok then
			res = result
		else
			err = result
		end
		done = true
	end)

	local start = os.clock()
	while not done do
		if (os.clock() - start) > REQUEST_TIMEOUT then
			return nil, "timeout"
		end
		task.wait(0.05)
	end

	if not res then
		return nil, tostring(err)
	end

	return res, nil
end

local function requestJson(method, url, token, bodyTable)
	local headers = {
		["Accept"] = "application/vnd.github+json",
		["X-GitHub-Api-Version"] = "2022-11-28",
	}

	if token and token ~= "" then
		headers["Authorization"] = "Bearer " .. token
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
	local headers = {}

	if token and token ~= "" then
		headers["Authorization"] = "Bearer " .. token
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
	local treeUrl = ("https://api.github.com/repos/%s/%s/git/trees"):format(owner, repo)
	local treeData, treeErr = requestJson("POST", treeUrl, token, {
		base_tree = baseTreeSha,
		tree = treeEntries,
	})
	if not treeData then return nil, treeErr end

	local newTreeSha = treeData.sha
	if not newTreeSha then return nil, "no tree sha from github" end

	--if nothing changed, github can return same tree sha
	if newTreeSha == baseTreeSha then
		return false, "no changes"
	end

	local commitUrl = ("https://api.github.com/repos/%s/%s/git/commits"):format(owner, repo)
	local commitData, commitErr = requestJson("POST", commitUrl, token, {
		message = message,
		tree = newTreeSha,
		parents = { parentCommitSha },
	})
	if not commitData then return nil, commitErr end

	local newCommitSha = commitData.sha
	if not newCommitSha then return nil, "no commit sha from github" end

	local refUrl = ("https://api.github.com/repos/%s/%s/git/refs/heads/%s"):format(owner, repo, branch)
	local _, refErr = requestJson("PATCH", refUrl, token, {
		sha = newCommitSha,
		force = false,
	})
	if refErr then return nil, refErr end

	return true, ("commit %s"):format(newCommitSha:sub(1, 7))
end

function GitHub.downloadRaw(owner, repo, branch, path, token)
	local url = ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(owner, repo, branch, path)
	return requestRaw(url, token)
end

return GitHub
