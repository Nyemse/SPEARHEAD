local playerServer = game:GetService("Players")
local starterGui = game:GetService("StarterGui")
local replicatedStorage = game:GetService("ReplicatedStorage")

local bridgeNet = require(replicatedStorage.SPH_Assets.Modules.BridgeNet)
local sysMessage = bridgeNet.CreateBridge("SystemMessage")

local textChatService = game:GetService("TextChatService")
local legacyChat = textChatService.ChatVersion == Enum.ChatVersion.LegacyChatService

local config = require(replicatedStorage.SPH_Assets.GameConfig)

task.wait(2)

if config.systemChat then
	if legacyChat then
		sysMessage:Connect(function(message, color)
			if legacyChat then
				starterGui:SetCore("ChatMakeSystemMessage", {
					Text = message,
					Color = color,
				})
			else
			end
		end)
	end
end
