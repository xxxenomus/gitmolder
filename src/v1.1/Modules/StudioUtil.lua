--//script by xenomus
--//discord: xxxenomus

local function getScriptSuffix(inst)
	if inst:IsA("LocalScript") then return ".client.lua" end
	if inst:IsA("Script") then return ".server.lua" end
	return ".lua"
end

local function stripSuffix(fileName)
	if fileName:sub(-11) == ".server.lua" then return fileName:sub(1, -12), "Script" end
	if fileName:sub(-11) == ".client.lua" then return fileName:sub(1, -12), "LocalScript" end
	if fileName:sub(-4) == ".lua" then return fileName:sub(1, -5), "ModuleScript" end
	return nil, nil
end

local function getTopService(inst)
	while inst and inst.Parent ~= game do inst = inst.Parent end
	return inst and inst.Parent == game and inst.Name or nil
end

local function buildRepoPath(inst, prefix)
	local parts = {}
	local svc = getTopService(inst)
	if not svc then return nil end

	table.insert(parts, svc)
	local cur = inst.Parent
	while cur and cur.Parent and cur.Parent ~= game do
		table.insert(parts, 2, cur.Name)
		cur = cur.Parent
	end

	table.insert(parts, inst.Name .. getScriptSuffix(inst))

	prefix = prefix or ""
	if prefix ~= "" and prefix:sub(-1) ~= "/" then prefix = prefix .. "/" end
	return prefix .. table.concat(parts, "/")
end

local function collectScripts(prefix)
	local sources = {}
	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("LuaSourceContainer") then
			local ok, src = pcall(function() return inst.Source end)
			if ok and src then
				local path = buildRepoPath(inst, prefix)
				if path then
					sources[path] = {
						source = src,
						hash = 0, --compute if needed
						inst = inst
					}
				end
			end
		end
	end
	return sources
end

local function ensureFolder(parent, name)
	local ex = parent:FindFirstChild(name)
	if ex and ex:IsA("Folder") then return ex end
	if ex then return nil end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function ensureScript(parent, name, class)
	local ex = parent:FindFirstChild(name)
	if ex and ex.ClassName == class then return ex end
	if ex then return nil end
	local s = Instance.new(class)
	s.Name = name
	s.Parent = parent
	return s
end

return {
	collectScripts = collectScripts,
	stripSuffix = stripSuffix,
	ensureFolder = ensureFolder,
	ensureScript = ensureScript,
	getService = function(name) 
		local ok, s = pcall(function() return game:GetService(name) end) 
		return ok and s or nil 
	end
}