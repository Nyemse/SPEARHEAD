type config = {
	maxRatePerMinute: number,
	Middleware: { (...any) -> ...any },
	ReplicationRate: number,
	InboundMiddleware: { (...any) -> ...any },
	OutboundMiddleware: { (...any) -> ...any },
}

return function(config: config?)
	if config == nil then
		return { _isBridge = true }
	end
	return {
		_isBridge = true,
		inbound = config["InboundMiddleware"],
		outbound = config["OutboundMiddleware"],
		rate = config["maxRatePerMinute"],
		replicationrate = config["ReplicationRate"],
	}
end
