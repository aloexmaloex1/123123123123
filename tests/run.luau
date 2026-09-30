-- Runs the pure-logic specs in src/server/Tests outside Roblox Studio (a terminal or CI):
--
--     lune run tests/run
--
-- It rebuilds the instance tree from default.project.json (folders and ModuleScripts only), gives
-- every module a `script`, `game` and a `require` that loads the file from disk, then runs
-- Tests/TestRunner exactly like the Studio command bar does. Exits with code 1 when a spec fails.
-- Only pure-logic modules work here: services are small stubs, and nothing touches DataStores.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

---------------------------------------------------------------- fake instances

local internals = setmetatable({}, { __mode = "k" })
local methods = {}
local NodeMeta = {}

local function newNode(name: string, className: string, path: string?)
	local node = setmetatable({}, NodeMeta)
	internals[node] = { Name = name, ClassName = className, Path = path, Children = {}, Parent = nil, Attributes = {} }
	return node
end

local function setParent(node, parent)
	local data = internals[node]
	if data.Parent then
		local siblings = internals[data.Parent].Children
		local index = table.find(siblings, node)
		if index then
			table.remove(siblings, index)
		end
	end
	data.Parent = parent
	if parent then
		table.insert(internals[parent].Children, node)
	end
end

NodeMeta.__index = function(node, key)
	local data = internals[node]
	if methods[key] then
		return methods[key]
	elseif key == "Name" or key == "ClassName" or key == "Parent" then
		return data[key]
	end
	for _, child in data.Children do
		if internals[child].Name == key then
			return child
		end
	end
	if data.Service and data.Service[key] ~= nil then
		return data.Service[key]
	end
	error(`{key} is not a valid member of {data.Name}`, 2)
end

NodeMeta.__newindex = function(node, key, value)
	local data = internals[node]
	if key == "Parent" then
		setParent(node, value)
	elseif key == "Name" then
		data.Name = value
	else
		error(`tests/run.luau: can't set {key} on {data.Name}`, 2)
	end
end

NodeMeta.__tostring = function(node)
	return internals[node].Name
end

function methods.GetChildren(node)
	return table.clone(internals[node].Children)
end

function methods.GetDescendants(node)
	local out = {}
	for _, child in internals[node].Children do
		table.insert(out, child)
		for _, d in methods.GetDescendants(child) do
			table.insert(out, d)
		end
	end
	return out
end

function methods.FindFirstChild(node, name, recursive)
	for _, child in internals[node].Children do
		if internals[child].Name == name then
			return child
		end
	end
	if recursive then
		for _, child in internals[node].Children do
			local found = methods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

-- Never waits: a missing child in a test is a bug, so fail loudly instead of hanging.
function methods.WaitForChild(node, name)
	return methods.FindFirstChild(node, name) or error(`{name} is not a child of {internals[node].Name}`, 2)
end

function methods.IsA(node, className)
	local own = internals[node].ClassName
	return own == className or className == "Instance" or (className == "LuaSourceContainer" and own:match("Script$") ~= nil)
end

function methods.GetFullName(node)
	local data = internals[node]
	if data.Parent and internals[data.Parent].ClassName ~= "DataModel" then
		return methods.GetFullName(data.Parent) .. "." .. data.Name
	end
	return data.Name
end

function methods.Clone(node)
	local data = internals[node]
	local copy = newNode(data.Name, data.ClassName, data.Path)
	for _, child in data.Children do
		setParent(methods.Clone(child), copy)
	end
	return copy
end

function methods.Destroy(node)
	setParent(node, nil)
end

function methods.GetAttribute(node, name)
	return internals[node].Attributes[name]
end

function methods.SetAttribute(node, name, value)
	internals[node].Attributes[name] = value
end

---------------------------------------------------------------- tree from default.project.json

local function scriptClass(fileName: string): (string?, string?)
	local base = fileName:match("^(.*)%.luau?$")
	if not base then
		return nil, nil
	end
	local serverName = base:match("^(.*)%.server$")
	if serverName then
		return serverName, "Script"
	end
	local clientName = base:match("^(.*)%.client$")
	if clientName then
		return clientName, "LocalScript"
	end
	return base, "ModuleScript"
end

local function fromPath(name: string, path: string)
	if fs.isFile(path) then
		local _, className = scriptClass(path)
		return newNode(name, className or "Folder", path)
	end
	local node = newNode(name, "Folder", nil)
	local entries = fs.readDir(path)
	table.sort(entries)
	for _, entry in entries do
		local full = path .. "/" .. entry
		local initName, initClass = scriptClass(entry)
		if initName == "init" then
			internals[node].ClassName = initClass
			internals[node].Path = full
		elseif fs.isDir(full) then
			setParent(fromPath(entry, full), node)
		elseif initName then
			setParent(newNode(initName, initClass, full), node)
		end
	end
	return node
end

local function fromProject(name: string, spec: { [string]: any })
	local node = spec["$path"] and fromPath(name, spec["$path"]) or newNode(name, spec["$className"] or name, nil)
	for key, child in spec do
		if key:sub(1, 1) ~= "$" then
			setParent(fromProject(key, child), node)
		end
	end
	return node
end

local project = serde.decode("json", fs.readFile("default.project.json"))
local game = fromProject("Game", project.tree)
internals[game].ClassName = "DataModel"

---------------------------------------------------------------- services and globals

local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end, Connected = true }
		end,
		Once = function()
			return { Disconnect = function() end, Connected = true }
		end,
		Wait = function() end,
	}
end

local serviceStubs = {
	Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function()
		return {}
	end },
	RunService = {
		Heartbeat = signal(),
		Stepped = signal(),
		RenderStepped = signal(),
		IsStudio = function()
			return false
		end,
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
	},
	-- Specs never load or save profiles; DataService only needs a store object to exist.
	DataStoreService = { GetDataStore = function()
		return {}
	end },
	CollectionService = {
		AddTag = function() end,
		GetTagged = function()
			return {}
		end,
		GetInstanceAddedSignal = signal,
		GetInstanceRemovedSignal = signal,
	},
}

local workspaceNode = newNode("Workspace", "Workspace", nil)
internals[workspaceNode].Service = {
	GetServerTimeNow = function()
		return os.clock()
	end,
}
setParent(workspaceNode, game)

function methods.GetService(node, name)
	local existing = methods.FindFirstChild(node, name)
	if existing then
		return existing
	end
	local stub = serviceStubs[name]
	if not stub then
		error(`tests/run.luau has no stub for {name}; add one to serviceStubs`, 2)
	end
	local service = newNode(name, name, nil)
	internals[service].Service = stub
	setParent(service, node)
	return service
end
internals[game].Service = { JobId = "", PlaceId = 0, CreatorId = 0, Workspace = workspaceNode }

-- Seeded Random with the NextNumber / NextInteger API the modules use.
local Random = {}
Random.__index = Random
function Random.new(seed: number?)
	local self = setmetatable({}, Random)
	self._state = math.floor(seed or os.clock() * 1e6) % 4294967296
	return self
end
function Random:_next(): number
	self._state = (self._state * 1664525 + 1013904223) % 4294967296
	return self._state / 4294967296
end
function Random:NextNumber(min: number?, max: number?): number
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * self:_next()
end
function Random:NextInteger(min: number, max: number): number
	return min + math.floor(self:_next() * (max - min + 1))
end

---------------------------------------------------------------- require

local loaded = {}

local function requireModule(target)
	local data = internals[target]
	if not data then
		error("tests/run.luau: require() expects a ModuleScript", 2)
	end
	if data.ClassName ~= "ModuleScript" or not data.Path then
		error(`{data.Name} is not a ModuleScript`, 2)
	end
	local cached = loaded[target]
	if cached then
		return cached.Value
	end
	local env = {
		game = game,
		workspace = workspaceNode,
		script = target,
		require = requireModule,
		task = task,
		Random = Random,
	}
	for key, value in roblox do
		if env[key] == nil and key:match("^%u") then
			env[key] = value
		end
	end
	local chunk = luau.load(fs.readFile(data.Path), { debugName = data.Path, environment = env })
	local value = chunk()
	loaded[target] = { Value = value }
	return value
end

---------------------------------------------------------------- run

local tests = methods.FindFirstChild(game, "ServerScriptService"):FindFirstChild("RelicRNG"):FindFirstChild("Tests")
local report = requireModule(tests:FindFirstChild("TestRunner")).run()
print(report)
local failed = tonumber(report:match("(%d+) failed")) or 1
process.exit(failed > 0 and 1 or 0)
