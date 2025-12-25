local module = {}

module.Messages = {
	Killed = {
		"was killed by",
		"was neutralized by",
		"was made a casualty by",
		"was oof'd by",
		"died of wounds inflicted by",
	},
	Falling = {
		"fell from a deadly height",
		"shattered their legs",
		"hit the ground too fast",
	},
	Death = {
		"died under mysterious circumstances",
		"inexplicably died",
		"suddenly fainted",
		"slipped into a coma",
		"entered a vegetative state",
	},
}

module.GetMessage = function(msgType)
	local messageList = module.Messages[msgType]
	return messageList[math.random(#messageList)]
end

return module
