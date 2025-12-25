local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SerdesLayer = require(script.Parent.SerdesLayer)

type queueSendPacket = {
	plrs: string | Player | { Player },
	remote: string,
	args: { any },
	replRate: number,
	invokeReply: any?,
	uuid: string?,
}
type queueReceivePacket = { plr: Player, remote: string, args: { any } }

local SendQueue: { queueSendPacket } = {}
local ReceiveQueue: { queueReceivePacket } = {}
local replTicksSignal = {}

local BridgeObjects = {}

local RemoteEvent
local Invoke
local InvokeReply

local function deepCopy<originalType>(tbl): originalType
	local result: originalType = {}
	for key: number, v in tbl do
		if typeof(v) == "table" then
			result[key] = deepCopy(v)
		elseif typeof(v) == "userdata" then
			warn("warning: copying userdata? you should never see this.")
			result[key] = v
		else
			result[key] = v
		end
	end
	return result
end

--[=[
	@class ServerBridge
	
	The general method of communicating from the server to the client.
]=]
local ServerBridge = {}
ServerBridge.__index = ServerBridge

--[=[
	Starts the internal processes for ServerBridge.
	
	@ignore
]=]
function ServerBridge._start(): nil
	RemoteEvent = Instance.new("RemoteEvent")
	RemoteEvent.Name = "SPH_BridgeNetEvent"
	RemoteEvent.Parent = ReplicatedStorage

	Invoke = SerdesLayer.CreateIdentifier("Invoke")
	InvokeReply = SerdesLayer.CreateIdentifier("InvokeReply")

	local replTicks = {}

	RunService.Heartbeat:Connect(function()
		debug.profilebegin("ServerBridge")
		local currentTime = os.clock()

		--[[if (time() - lastClear) > 60 then
			lastClear = time()

			for _, v in BridgeObjects do
				v._rateInThisMinute = 0
			end
		end]]

		for _, v in ReceiveQueue do
			for i = 1, #v.args do
				if v.args[i] == SerdesLayer.NilIdentifier then
					v.args[i] = nil
				end
			end

			local obj = BridgeObjects[SerdesLayer.FromCompressed(v.remote)]
			if obj == nil then
				--Don't warn here because that's a vulnerability. We don't want exploiters
				--lagging out the server over time with a pcall that warns every frame.
				continue
			end
			if v.args[1] == Invoke then
				if obj._onInvoke ~= nil then
					task.spawn(function()
						local args = v.args
						local uuid = args[2]

						table.remove(args, 1)
						table.remove(args, 1) -- Arg 2 becomes arg1 after arg1 is removed.
						table.insert(SendQueue, {
							plrs = v.plr,
							remote = obj._id,
							uuid = uuid,
							invokeReply = true,
							replRate = 60,
							args = { obj._onInvoke(v.plr, unpack(v.args)) },
						})
					end)
				else
					-- onInvoke is not set s	end an error to the client
					local args = v.args
					local uuid = args[2]

					table.remove(args, 1)
					table.remove(args, 1) -- Arg 2 becomes arg1 after arg1 is removed.
					table.insert(SendQueue, {
						plrs = v.plr,
						remote = obj._id,
						uuid = uuid,
						invokeReply = true,
						replRate = 60,
						args = { "err", "onInvoke has not yet been registered on the server for " .. obj._name },
					})
				end
			else
				debug.profilebegin(string.format("connections_%s", obj._name))

				for _, callback in obj._connections do
					-- Spawn a thread to be yield-safe. Potentially implement thread reusability for optimization later?
					-- also for error protection
					task.spawn(function()
						if #obj._inboundMiddleware ~= 0 then
							local result
							for _, func in obj._inboundMiddleware do
								if result then
									local potential = { func(table.unpack(result)) }
									if #potential == 0 then
										continue
									end
									result = potential
								else
									result = { func(table.unpack(v.args)) }
								end
							end

							if result == nil then
								result = v.args
							end

							callback(v.plr, table.unpack(result))
						else
							callback(v.plr, table.unpack(v.args))
						end
					end)
				end

				debug.profileend()
			end
		end

		table.clear(ReceiveQueue)

		local toSendAll = {}
		local toSendPlayers = {}
		local remainingQueue = {}
		local passingReplRates = {}

		for i, v in remainingQueue do
			if (currentTime - replTicks[v.replRate]) <= (1 / v.replRate - 0.003) then
				table.insert(SendQueue, v)
				continue
			else
				table.remove(remainingQueue, i)
			end
		end

		for _, v: queueSendPacket in SendQueue do
			if replTicks[v.replRate] then
				-- subtract 0.003 to make sure we don't accidentally skip any frames due to rounding errors
				if (currentTime - replTicks[v.replRate]) <= (1 / v.replRate - 0.003) then
					passingReplRates[v.replRate] = true
					if not passingReplRates[v.replRate] then
						table.insert(remainingQueue, v)
						continue
					end
				end
			end

			if replTicksSignal[v.replRate] == nil then
				replTicksSignal[v.replRate] = {}
			else
				for _, callback: () -> nil in replTicksSignal[v.replRate] do
					task.spawn(callback)
				end
			end

			for i = 1, #v.args do
				if v.args[i] == nil then
					v.args[i] = SerdesLayer.NilIdentifier
				end
			end

			if not v.invokeReply then
				local tbl = { v.remote }
				local bridgeObj = BridgeObjects[SerdesLayer.FromCompressed(v.remote)]

				if not (#bridgeObj._outboundMiddleware == 0) then
					local result
					for _, func in bridgeObj._outboundMiddleware do
						if result then
							local potential = { func(table.unpack(result)) }
							if #potential == 0 then
								continue
							end
							result = potential
						else
							result = { func(table.unpack(v.args)) }
						end
					end

					if result == nil then
						result = v.args
					end

					for _, k in result do
						table.insert(tbl, k)
					end
				else
					for _, k in v.args do
						table.insert(tbl, k)
					end
				end

				if v.plrs == "all" then
					table.insert(toSendAll, tbl)
				elseif typeof(v.plrs) == "table" then
					for _, l in v.plrs do
						if toSendPlayers[l] == nil then
							toSendPlayers[l] = {}
						end

						table.insert(toSendPlayers[l], tbl)
					end
				else
					if toSendPlayers[v.plrs] == nil then
						toSendPlayers[v.plrs] = { tbl }
					else
						table.insert(toSendPlayers[v.plrs], tbl)
					end
				end
			elseif v.invokeReply then
				if toSendPlayers[v.plrs] == nil then
					toSendPlayers[v.plrs] = {}
				end

				local tbl = { v.remote, InvokeReply, v.uuid }

				for _, k in v.args do
					table.insert(tbl, k)
				end

				table.insert(toSendAll, tbl)
			end
		end

		if #toSendAll ~= 0 then
			RemoteEvent:FireAllClients(toSendAll)
		end
		for l, k in toSendPlayers do
			RemoteEvent:FireClient(l, k)
		end
		table.clear(SendQueue)

		for key, _ in passingReplRates do
			passingReplRates[key] = false
		end

		debug.profileend()
	end)

	RemoteEvent.OnServerEvent:Connect(function(plr, tbl)
		for _, v in tbl do
			local args = v
			local remote = args[1]
			table.remove(args, 1)
			local toInsert = {
				remote = remote,
				plr = plr,
				args = args,
			}
			table.insert(ReceiveQueue, toInsert)
		end
	end)

	return nil
end

function ServerBridge._getReplicationStepSignal(rate: number, callback: () -> nil)
	if replTicksSignal[rate] == nil then
		replTicksSignal[rate] = {
			callback,
		}
	else
		table.insert(replTicksSignal[rate], callback)
	end
end

function ServerBridge._returnQueue()
	return SendQueue, ReceiveQueue
end

--[[function ServerBridge._log(duration)
	if activeLogger ~= nil then
		return warn("[BridgeNet] active logger already exists")
	else
		local returnValue = {}
		activeLogger = {}
		task.delay(duration, function()
			for _, v in activeLogger do
				table.insert(returnValue, {
					Name = v.Name,
				})
			end
			activeLogger = nil
		end)
	end
end]]

function ServerBridge._destroy()
	RemoteEvent:Destroy()
end

function ServerBridge.new(remoteName: string)
	assert(type(remoteName) == "string", "[BridgeNet] Remote name must be a string")

	local found = ServerBridge.from(remoteName)
	if found ~= nil then
		return found
	end

	local self = setmetatable({}, ServerBridge)

	self._name = remoteName

	self._onInvoke = nil
	self._connections = {}

	self._replRate = 60

	self._rateLimit = nil
	self._rateHandler = nil
	self._rateInThisMinute = {
		num = 0,
		min = 0,
	}

	self._id = SerdesLayer.CreateIdentifier(remoteName)

	self._outboundMiddleware = {}
	self._inboundMiddleware = {}

	BridgeObjects[self._name] = self
	return self
end

function ServerBridge.from(remoteName: string)
	return BridgeObjects[remoteName]
end

function ServerBridge.waitForBridge(remoteName: string)
	while true do
		local bridge = BridgeObjects[remoteName]
		if bridge then
			return bridge
		end
		task.wait()
	end
end

--[=[
	Sends data to a specific player.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	Bridge:FireTo(Players.Someone, "Hello", "World!")
	```
	
	@param plr Player
	@param ... ...any
	@return nil
]=]
function ServerBridge:FireTo(plr: Player, ...: any)
	local args: { any } = { ... }
	local toSend: queueSendPacket = {
		plrs = plr,
		remote = self._id,
		args = args,
		replRate = self._replRate,
	}
	table.insert(SendQueue, toSend)
end

--[=[
	Set the handler for when the server is invoked. By default, this is nil. The client will hang forever as of writing this right now.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	
	local data = Bridge:OnInvoke(function(data)
		if data == "whats 2+2?" then
			return "4"
		end
	end)
	```
	
	@param callback (...any) -> nil
	@return Promise
]=]
function ServerBridge:OnInvoke(callback: (...any) -> nil)
	local function wrappedCallback(...)
		local success, args = pcall(function(...)
			return table.pack(callback(...))
		end, ...)

		if success == true then
			return table.unpack(args)
		else
			return "err", args
		end
	end

	self._onInvoke = wrappedCallback --wrappedCallback
end

--[=[
	Sends data to every player except for one.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	Bridge:FireToAllExcept(Players.Someone, "Hello", "World!")
	Bridge:FireToAllExcept({Players.A, Players.B}, "Not to A or B, but to C.")
	```
	
	@param blacklistedPlrs Player | {Player}
	@param ... ...any
	@return nil
]=]
function ServerBridge:FireToAllExcept(blacklistedPlrs: Player | { Player }, ...: any): { Player }
	local toSend = {}
	for _, v: Player in Players:GetPlayers() do
		if typeof(blacklistedPlrs) == "table" then
			if table.find(blacklistedPlrs, v) then
				continue
			end
		else
			if blacklistedPlrs == v then
				continue
			end
		end
		table.insert(toSend, v)
	end

	local toSendPacket: queueSendPacket = {
		plrs = toSend,
		remote = self._id,
		args = { ... },
		replRate = self._replRate,
	}
	table.insert(SendQueue, toSendPacket)

	return toSend :: { Player }
end

--[=[
	Sends data to every single player within the range except certain blacklisted players. Returns the players affected, for usage later.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	local PlayersSent = Bridge:FireToAllInRangeExcept(
		Players.Someone,
		Vector3.new(50, 50, 50),
		10,
		"Hello",
		"World!"
	)
	
	task.wait(5)
	
	Bridge:FireToMultiple(PlayersSent, "Time for an update!")
	```
	
	@param blacklistedPlrs Player | {Player}
	@param point Vector3
	@param range number
	@param ... ...any
	@return {Player}
]=]
function ServerBridge:FireAllInRangeExcept(
	blacklistedPlrs: Player | { Player },
	point: Vector3,
	range: number,
	...: any
)
	local toSend = {}
	for _, v: Player in Players:GetPlayers() do
		if v:DistanceFromCharacter(point) <= range then
			if typeof(blacklistedPlrs) == "table" then
				if table.find(blacklistedPlrs, v) then
					continue
				end
			else
				if blacklistedPlrs == v then
					continue
				end
			end
			table.insert(toSend, v)
		end
	end

	local toSendPacket: queueSendPacket = {
		plrs = toSend,
		remote = self._id,
		args = { ... },
		replRate = self._replRate,
	}
	table.insert(SendQueue, toSendPacket)

	return toSend
end

--[=[
	Sends data to every single player within the range. Returns the players affected, for usage later.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	local PlayersSent = Bridge:FireAllInRange(
		Vector3.new(50, 50, 50),
		10,
		"Hello",
		"World!"
	)
	
	task.wait(5)
	
	Bridge:FireToMultiple(PlayersSent, "Time for an update!")
	```
	
	@param point Vector3
	@param range number
	@param ... ...any
	@return {Player}
]=]
function ServerBridge:FireAllInRange(point: Vector3, range: number, ...: any): { Player }
	assert(typeof(point) == "Vector3", "[BridgeNet] point must be a Vector3")
	assert(typeof(range) == "number", "[BridgeNet] range must be a number")

	local toSend = {}
	for _, v: Player in Players:GetPlayers() do
		if v:DistanceFromCharacter(point) <= range then
			table.insert(toSend, v)
		end
	end

	local toSendPacket: queueSendPacket = {
		plrs = toSend,
		remote = self._id,
		args = { ... },
		replRate = self._replRate,
	}
	table.insert(SendQueue, toSendPacket)

	return toSend :: { Player }
end

--[=[
	Sends data to every single player, with no exceptions.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	Bridge:FireAll("Hello, world!")
	```
	
	@param ... ...any
	@return nil
]=]
function ServerBridge:FireAll(...: any): nil
	local args: { any } = { ... }
	local toSend: queueSendPacket = {
		plrs = "all",
		remote = self._id,
		args = args,
		replRate = self._replRate,
	}
	table.insert(SendQueue, toSend)
	return nil
end

--[=[
	Sends data to multiple players.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	Bridge:FireToMultiple({Players.A, Players.B}, "Hi!", "Hello.")
	```
	
	@param plrs {Player}
	@param ... ...any
	@return nil
]=]
function ServerBridge:FireToMultiple(plrs: { Player }, ...: any): nil
	assert(type(plrs) == "table", "[BridgeNet] First argument must be a table!")

	local args: { any } = { ... }
	local toSend: queueSendPacket = {
		plrs = plrs,
		remote = self._id,
		args = args,
		replRate = self._replRate,
	}
	table.insert(SendQueue, toSend)
	return nil
end

--[=[
	Sets the Bridge's inbound middleware functions. Any function which returns nil will drop the remote request completely. Overrides existing middleware.
	
	Allows you to change arguments or drop remote calls.
	
	A more comprehensive guide on middleware will be coming soon.
	```lua
	Object:SetInboundMiddleware({
		function(plr, ...) -- Called first
			return ...
		end,
		function(plr, ...) -- Called second
			print("1")
			return ...
		end,
		function(plr, ...) -- Called third
			print("2")
			return ...
		end,
	})
	```
	
	@param middlewareTable { (...any) -> nil }
	@return nil
]=]
function ServerBridge:SetInboundMiddleware(middlewareTable: { (...any) -> nil })
	assert(typeof(middlewareTable) == "table", "[BridgeNet] middlewareTable must be a table")
	self._inboundMiddleware = middlewareTable or {}
end

--[=[
	Sets the Bridge's outbound middleware functions. Any function which returns nil will drop the sequence completely. Overrides existing middleware.
	
	A more comprehensive guide on middleware will be coming soon.
	```lua
	Object:SetOutboundMiddleware({
		function(plr, ...) -- Called first
			return ...
		end,
		function(plr, ...) -- Called second
			print("1")
			return ...
		end,
		function(plr, ...) -- Called third
			print("2")
			return ...
		end,
	})
	```
	
	@param middlewareTable { (...any) -> nil }
	@return nil
]=]
function ServerBridge:SetOutboundMiddleware(middlewareTable: { (...any) -> nil })
	assert(typeof(middlewareTable) == "table", "[BridgeNet] middlewareTable must be a table")
	self._outboundMiddleware = middlewareTable or {}
end

--[=[
	Creates a connection, when fired it will disconnect.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("ConstantlyFiringText")
	
	Bridge:Connect(function(text)
		print(text) -- Fires multiple times
	end)
	
	Bridge:Once(function(text)
		print(text) -- Fires once
	end)
	```
	
	@param func function
	@return nil
]=]
function ServerBridge:Once(func: (...any) -> nil)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		func(...)
	end)
end

--[=[
	Creates a connection.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	Bridge:Connect(function(plr, data)
		print(plr .. " has sent " .. data)
	end)
	```
	
	@param func (plr: Player, ...any) -> nil
	@return Connection
]=]
function ServerBridge:Connect(func: (...any) -> nil)
	assert(type(func) == "function", "[BridgeNet] attempt to connect non-function to a Bridge")
	local connectionUUID = SerdesLayer.CreateUUID()
	self._connections[connectionUUID] = func

	local connection = {}

	function connection.Disconnect()
		self._connections[connectionUUID] = nil
		connectionUUID = nil
	end

	return connection
end

--[[
	Gets the ServerBridge's name.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	
	print(Bridge:GetName()) -- Prints "Remote"
	```
	
	@return string
]]
function ServerBridge:GetName()
	return self._name
end

--[=[
	Sets the rate of which the Bridge sends and receives data.
	
	@return nil
]=]
function ServerBridge:SetReplicationRate(number)
	self._replRate = number
end

--[=[
	Destroys the identifier, and deletes the object reference.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	Bridge:Destroy()
	
	Bridge:FireTo(Players.A) -- Errors, the object is deleted.
	```
	
	@return nil
]=]
function ServerBridge:Destroy()
	BridgeObjects[self._name] = nil
	SerdesLayer.DestroyIdentifier(self.Name)
	for k, v in self do
		if v.Destroy ~= nil then
			v:Destroy()
		else
			self[k] = nil
		end
	end
	setmetatable(self, nil)
end

export type ServerObject = typeof(ServerBridge.new(""))

return ServerBridge
