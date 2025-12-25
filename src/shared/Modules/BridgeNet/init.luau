local RunService = game:GetService("RunService")

local SerdesLayer = require(script.SerdesLayer)
local ServerBridge = require(script.ServerBridge)
local ClientBridge = require(script.ClientBridge)
local CreateBridgeTree = require(script.CreateBridgeTree)
local Bridge = require(script.Bridge)

local isServer = RunService:IsServer()

--[=[
	@class BridgeNet
	
	The interface for the library.
]=]

--[=[
	@function GetQueue
	@within BridgeNet
	
	Returns the internal queue BridgeNet uses. Not intended for production purposes- use this to debug potential issues with the module, or your own code.
	
	@return SendQueue, ReceiveQueue
]=]

--[=[
	@function CreateBridgeTree
	@within BridgeNet
	
	This function creates a series of Bridges with a preset configuration. This function supports namespaces- it takes either a BridgeNet.Bridge() function, or a dictionary.
	```lua
	local MyBridgeTree = BridgeNet.CreateBridgeTree({
		BridgeNameHere = BridgeNet.Bridge()
		NamespaceHere = {
			BridgeHere = BridgeNet.Bridge({
				ReplicationRate = 20
			})
		}
	})
	```
	This allows you to create your Bridge objects in one centralized place, as it is runnable on both the client and server. This means that one module can contain all of your
	Bridge objects- which makes it much easier to access. Example usage:
	```lua
	-- shared/Bridges.luau
	local MyBridgeTree = BridgeNet.CreateBridgeTree({
		PrintOnServer = BridgeNet.Bridge()
	})
	
	return MyBridgeTree
	
	-- client
	local Bridges = require(path.to.Bridges)
	
	Bridges.PrintOnServer:Fire("Hello, world!")
	
	-- server
	local Bridges = require(path.to.Bridges)
	
	Bridges.PrintOnServer:Connect(function(player, text)
		print("Player " .. player.Name .. " has said " .. text) -- prints "Player SomeUsername has said Hello, world!
	end)
	```
	
	@param BridgeTree { [string]: thisType | BridgeConfig }
	@return { [string]: thisType | Bridge }
]=]

--[=[
	@function Bridge
	@within BridgeNet
	
	This function is only intended for usage within BridgeNet.CreateBridgeTree(). You are not supposed to use this anywhere else.
	This function lets you assign middleware, a replication rate, and in the future certain things like logging and typechecking.
	
	```lua
		local MyBridgeTree = BridgeNet.CreateBridgeTree({
			PrintOnServer = BridgeNet.Bridge({
				ReplicationRate = 20, -- twenty times per second
				OutboundMiddleware = {
					function(...)
						print("Sending from PrintOnServer")
						return ...
					end,
				},
				InboundMiddleware = {
					function(plr, ...)
						print("Player " .. plr .. " has fired PrintOnServer")
						return ...
					end,
				},
			})
		})
	```
	
	@return BridgeConfig
]=]

--[=[
	@function CreateBridge
	@within BridgeNet
	
	Creates a ServerBridge or a ClientBridge depending on if it's the server or client calling. If a Bridge of that name already exists, it'll return that Bridge object.
	This can be used to fetch bridges, but .WaitForBridge is recommended.
	
	```lua
	local Bridge = BridgeNet.CreateBridge("Remote")
	```
	
	@param remoteName string
	@return ServerBridge | ClientBridge
]=]

export type ServerBridge = ServerBridge.ServerObject
export type ClientBridge = ClientBridge.ClientObject

export type Bridge = ServerBridge | ClientBridge

script.Destroying:Connect(function()
	SerdesLayer._destroy()
	if isServer then
		ServerBridge._destroy()
	end
end)

SerdesLayer._start()
if isServer then
	ServerBridge._start()
else
	ClientBridge._start()
end

return {
	CreateBridgeTree = CreateBridgeTree,
	Bridge = Bridge,

	Identifiers = function(tbl: { string })
		local ReturnValue = {}

		for _, v in tbl do
			ReturnValue[v] = SerdesLayer.CreateIdentifier(v)
		end

		return ReturnValue :: { [string]: string }
	end,

	CreateIdentifier = SerdesLayer.CreateIdentifier,
	DestroyIdentifier = SerdesLayer.DestroyIdentifier,

	CreateUUID = SerdesLayer.CreateUUID,
	PackUUID = SerdesLayer.PackUUID,
	UnpackUUID = SerdesLayer.UnpackUUID,

	DictionaryToTable = SerdesLayer.DictionaryToTable,

	--[[LogNetTraffic = function(duration: number)
		if isServer then
			return ServerBridge._log(duration)
		else
			return ClientBridge._log(duration)
		end
	end,]]

	ReplicationStep = function(rate: number, func: () -> nil)
		if isServer then
			return ServerBridge._getReplicationStepSignal(rate, func)
		else
			return ClientBridge._getReplicationStepSignal(rate, func)
		end
	end,

	GetQueue = function()
		if isServer then
			local send, receive = ServerBridge._returnQueue()
			return send, receive
		else
			local send, receive = ClientBridge._returnQueue()
			return send, receive
		end
	end,

	CreateBridge = function(str)
		if isServer then
			return ServerBridge.new(str)
		else
			return ClientBridge.new(str)
		end
	end,
}
