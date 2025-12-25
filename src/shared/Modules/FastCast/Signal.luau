--!nocheck
-- ^ change to strict to crash studio c:

-- A new implementation of RBXScriptSignal that uses proper Lua OOP.
-- This was explicitly made to transport other OOP objects.
-- I would be using BindableEvents, but they don't like cyclic tables (part of OOP objects with __index)

-- Inject types
local TypeDefs = require(script.Parent.TypeDefinitions)
type CanPierceFunction = TypeDefs.CanPierceFunction
type GenericTable = TypeDefs.GenericTable
type Caster = TypeDefs.Caster
type FastCastBehavior = TypeDefs.FastCastBehavior
type CastTrajectory = TypeDefs.CastTrajectory
type CastStateInfo = TypeDefs.CastStateInfo
type CastRayInfo = TypeDefs.CastRayInfo
type ActiveCast = TypeDefs.ActiveCast

local TestService = game:GetService("TestService")
local table = require(script.Parent.Table)

local SignalStatic = {}
SignalStatic.__index = SignalStatic
SignalStatic.__type = "Signal" -- For compatibility with TypeMarshaller
local ConnectionStatic = {}
ConnectionStatic.__index = ConnectionStatic
ConnectionStatic.__type = "SignalConnection" -- For compatibility with TypeMarshaller

export type Signal = {
	Name: string,
	Connections: { [number]: Connection },
	YieldingThreads: { [number]: BindableEvent },
}

export type Connection = {
	Signal: Signal?,
	Delegate: any,
	Index: number,
}

-- Format params: methodName, ctorName
local ERR_NOT_INSTANCE =
	"Cannot statically invoke method '%s' - It is an instance method. Call it on an instance of this class created via %s"

function SignalStatic.new(signalName: string): Signal
	local signalObj: Signal = {
		Name = signalName,
		Connections = {},
		YieldingThreads = {},
	}
	return setmetatable(signalObj, SignalStatic)
end

local function NewConnection(sig: Signal, func: any): Connection
	local connectionObj: Connection = {
		Signal = sig,
		Delegate = func,
		Index = -1,
	}
	return setmetatable(connectionObj, ConnectionStatic)
end

local function ThreadAndReportError(delegate: any, args: GenericTable, handlerName: string)
	local thread = coroutine.create(function()
		delegate(unpack(args))
	end)
	local success, msg = coroutine.resume(thread)
	if not success then
		-- For the love of god roblox PLEASE add the ability to customize message type in output statements.
		-- This "testservice" garbage at the start of my message is annoying as all hell.
		TestService:Error(string.format("Exception thrown in your %s event handler: %s", handlerName, msg))
		TestService:Checkpoint(debug.traceback(thread))
	end
end

function SignalStatic:Connect(func)
	assert(getmetatable(self) == SignalStatic, ERR_NOT_INSTANCE:format("Connect", "Signal.new()"))
	local connection = NewConnection(self, func)
	connection.Index = #self.Connections + 1
	table.insert(self.Connections, connection.Index, connection)
	return connection
end

function SignalStatic:Fire(...)
	assert(getmetatable(self) == SignalStatic, ERR_NOT_INSTANCE:format("Fire", "Signal.new()"))
	local args = table.pack(...)
	local allCons = self.Connections
	local yieldingThreads = self.YieldingThreads
	for index = 1, #allCons do
		local connection = allCons[index]
		if connection.Delegate ~= nil then
			-- Catch case for disposed signals.
			ThreadAndReportError(connection.Delegate, args, connection.Signal.Name)
		end
	end
	for index = 1, #yieldingThreads do
		local thread = yieldingThreads[index]
		if thread ~= nil then
			coroutine.resume(thread, ...)
		end
	end
end

function SignalStatic:FireSync(...)
	assert(getmetatable(self) == SignalStatic, ERR_NOT_INSTANCE:format("FireSync", "Signal.new()"))
	local args = table.pack(...)
	local allCons = self.Connections
	local yieldingThreads = self.YieldingThreads
	for index = 1, #allCons do
		local connection = allCons[index]
		if connection.Delegate ~= nil then
			-- Catch case for disposed signals.
			connection.Delegate(unpack(args))
		end
	end
	for index = 1, #yieldingThreads do
		local thread = yieldingThreads[index]
		if thread ~= nil then
			coroutine.resume(thread, ...)
		end
	end
end

function SignalStatic:Wait()
	assert(getmetatable(self) == SignalStatic, ERR_NOT_INSTANCE:format("Wait", "Signal.new()"))
	local args = {}
	local thread = coroutine.running()
	table.insert(self.YieldingThreads, thread)
	args = { coroutine.yield() }
	table.removeObject(self.YieldingThreads, thread)
	return unpack(args)
end

function SignalStatic:Dispose()
	assert(getmetatable(self) == SignalStatic, ERR_NOT_INSTANCE:format("Dispose", "Signal.new()"))
	local allCons = self.Connections
	for index = 1, #allCons do
		allCons[index]:Disconnect()
	end
	self.Connections = {}
	setmetatable(self, nil)
end

function ConnectionStatic:Disconnect()
	assert(
		getmetatable(self) == ConnectionStatic,
		ERR_NOT_INSTANCE:format("Disconnect", "private function NewConnection()")
	)
	table.remove(self.Signal.Connections, self.Index)
	self.SignalStatic = nil
	self.Delegate = nil
	self.YieldingThreads = {}
	self.Index = -1
	setmetatable(self, nil)
end

return SignalStatic
