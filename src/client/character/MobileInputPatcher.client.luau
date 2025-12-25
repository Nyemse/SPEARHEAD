-- The default mobile input modules are able to hide the jump button and thumbstick, but do not always make them visible again.
-- This script prevents the jump button and dynamic thumbstick from disappearing.

if game:GetService("UserInputService").TouchEnabled then
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui", 100)
	local touchControlFrame = playerGui:WaitForChild("TouchGui", 100):WaitForChild("TouchControlFrame", 100)
	local jumpButton: Frame = touchControlFrame:WaitForChild("JumpButton", 100)
	local thumbstickFrame: Frame = touchControlFrame:WaitForChild("DynamicThumbstickFrame", 100)

	jumpButton.Visible = true
	thumbstickFrame.Visible = true

	jumpButton:GetPropertyChangedSignal("Visible"):Connect(function()
		jumpButton.Visible = true
	end)

	thumbstickFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		thumbstickFrame.Visible = true
	end)
end
