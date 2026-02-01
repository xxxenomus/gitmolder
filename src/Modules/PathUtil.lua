local PathUtil = {}

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

local function getTopServiceName(inst)
	local cur = inst
	while cur and cur.Parent and cur.Parent ~= game do
		cur = cur.Parent
	end
	return cur and cur.Parent == game and cur.Name or nil
end

local function buildRepoPath(inst, prefix)
	local serviceName = getTopServiceName(inst)
	if not serviceName then return nil end

	local parts = {}
	table.insert(parts, serviceName)

	local stack = {}
	local cur = inst.Parent
	while cur and cur.Parent and cur.Parent ~= game do
		table.insert(stack, 1, cur.Name)
		cur = cur.Parent
	end

	for i = 1, #stack do
		table.insert(parts, stack[i])
	end

	table.insert(parts, inst.Name .. getScriptSuffix(inst))

	prefix = prefix or ""
	if prefix ~= "" and prefix:sub(-1) ~= "/" then prefix = prefix .. "/" end
	return prefix .. table.concat(parts, "/")
end

local function ensureFolder(parent, name)
	local ex = parent:FindFirstChild(name)
	if ex and ex:IsA("Folder") then return ex end
	if ex then
		ex:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function ensureScript(parent, name, className)
	local ex = parent:FindFirstChild(name)
	if ex and ex.ClassName == className then return ex end
	if ex then
		ex:Destroy()
	end
	local s = Instance.new(className)
	s.Name = name
	s.Parent = parent
	return s
end

local function getService(name)
	local ok, svc = pcall(function()
		return game:GetService(name)
	end)
	return ok and svc or nil
end

--im scanning only the usual script containers so i dont nuke perf with workspace parts
local defaultRoots = {
	"ServerScriptService",
	"ServerStorage",
	"ReplicatedStorage",
	"StarterPlayer",
	"StarterGui",
	"StarterPack",
	"Lighting",
	"SoundService",
}

local function getDefaultRoots()
	return defaultRoots
end

local function collectLuaSources(prefix, rootsOverride, onProgress, isCanceled)
	local roots = {}
	local list = rootsOverride or defaultRoots
	for _, svcName in ipairs(list) do
		local svc = getService(svcName)
		if svc then
			table.insert(roots, svc)
		end
	end

	local out = {}
	local scanned = 0
	for _, root in ipairs(roots) do
		if isCanceled and isCanceled() then
			return out, true
		end
		if root:IsA("LuaSourceContainer") then
			local ok, src = pcall(function() return root.Source end)
			if ok and type(src) == "string" then
				local path = buildRepoPath(root, prefix)
				if path then
					out[path] = { inst = root, source = src }
				end
			end
			scanned += 1
			if onProgress then onProgress(scanned) end
		end

		for _, inst in ipairs(root:GetDescendants()) do
			if isCanceled and isCanceled() then
				return out, true
			end
			if inst:IsA("LuaSourceContainer") then
				local ok, src = pcall(function() return inst.Source end)
				if ok and type(src) == "string" then
					local path = buildRepoPath(inst, prefix)
					if path then
						out[path] = { inst = inst, source = src }
					end
				end
				scanned += 1
				if onProgress then onProgress(scanned) end
			end
		end
	end

	return out, false
end

local function findScriptByPath(path, prefix)
	local pfx = prefix or ""
	if pfx ~= "" and pfx:sub(-1) ~= "/" then pfx = pfx .. "/" end
	if pfx ~= "" then
		if path:sub(1, #pfx) ~= pfx then return nil end
		path = path:sub(#pfx + 1)
	end

	local parts = {}
	for part in path:gmatch("[^/]+") do
		table.insert(parts, part)
	end

	if #parts < 2 then return nil end
	local svc = getService(parts[1])
	if not svc then return nil end

	local parent = svc
	for i = 2, #parts - 1 do
		local child = parent:FindFirstChild(parts[i])
		if not child or not child:IsA("Folder") then return nil end
		parent = child
	end

	local fileName = parts[#parts]
	local name, className = stripSuffix(fileName)
	if not name or not className then return nil end

	local inst = parent:FindFirstChild(name)
	if inst and inst.ClassName == className then
		return inst
	end
	return nil
end

return {
	buildRepoPath = buildRepoPath,
	stripSuffix = stripSuffix,
	getService = getService,
	ensureFolder = ensureFolder,
	ensureScript = ensureScript,
	collectLuaSources = collectLuaSources,
	findScriptByPath = findScriptByPath,
	getDefaultRoots = getDefaultRoots,
}
