-- We actually want draw the glass in the client because doing it on the server causes that delay because of network ownership
-- This module still works on the client so we will just call the module again just on the client this time
local module = require(script.Parent)
local renderGlass = script.Parent:WaitForChild("RenderGlass")

renderGlass.OnClientEvent:Connect(function(part, origin, force)
	module(part, origin, force, true)
end)
