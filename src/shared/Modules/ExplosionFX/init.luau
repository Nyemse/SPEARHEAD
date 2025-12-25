local debris = game:GetService("Debris")
local players = game:GetService("Players")

local config = require(game:GetService("ReplicatedStorage").SPH_Assets.GameConfig)

local explosionOverlapParams = OverlapParams.new()
explosionOverlapParams.MaxParts = 500
explosionOverlapParams.RespectCanCollide = true

local explosionRayParams = RaycastParams.new()
explosionRayParams.IgnoreWater = true
explosionRayParams.RespectCanCollide = true

local explosionSounds = { 287390459, 287390954, 287391087, 287391197, 287391361, 287391499, 287391567, 8226406520 }

local function Explode(
	explosionOrigin: Vector3,
	blastRadius: number,
	explosionType: string,
	playerResponsible: Player,
	soundOverride
)
	local effects = script:FindFirstChild(explosionType)
	if effects then
		local removeTime = 10
		effects = effects:GetChildren()
		local explosion = Instance.new("Attachment", workspace.Terrain)
		explosion.Name = "Explosion"
		explosion.WorldPosition = explosionOrigin

		-- VFX
		for _, effect in ipairs(effects) do
			local newEffect = effect:Clone()
			newEffect.Parent = explosion
			if newEffect:IsA("ParticleEmitter") then
				if newEffect:FindFirstChild("Count") then
					newEffect:Emit(newEffect.Count.Value)
				else
					newEffect:Emit(1)
				end
				if newEffect.Lifetime.Max > removeTime then
					removeTime = newEffect.Lifetime.Max
				end
			elseif newEffect:IsA("Light") then
				newEffect.Enabled = true
				debris:AddItem(newEffect, 0.1)
			end
		end

		if not soundOverride then
			-- Sound
			local explosionSound = Instance.new("Sound", explosion)
			explosionSound.SoundId = "rbxassetid://" .. explosionSounds[math.random(#explosionSounds)]
			explosionSound.Volume = 4
			explosionSound.RollOffMode = Enum.RollOffMode.InverseTapered
			explosionSound.RollOffMaxDistance = 10000
			explosionSound.PlayOnRemove = true
			explosionSound:Destroy()
		end

		-- Damage
		local humanoidsHit = {}
		local partsInRange = workspace:GetPartBoundsInRadius(explosionOrigin, blastRadius * 2, explosionOverlapParams)

		for _, hitPart in ipairs(partsInRange) do -- Loop through all parts found in range
			local humanoid = hitPart.Parent:FindFirstChild("Humanoid")
			local hrp = hitPart.Parent:FindFirstChild("HumanoidRootPart")
			local canHit = hrp and humanoid and not table.find(humanoidsHit, humanoid)
			local playerHit = humanoid and players:GetPlayerFromCharacter(humanoid.Parent)

			-- Prevent teamkill if it's enabled
			if
				playerHit
				and playerResponsible
				and playerHit ~= playerResponsible
				and playerHit.Team == playerResponsible.Team
				and not config.teamKill
			then
				canHit = false
			end

			if canHit then -- If a humanoid was hit and hasn't been hit yet
				local result = workspace:Raycast(
					explosionOrigin + Vector3.new(0, 1, 0),
					(hrp.Position - explosionOrigin).Unit * blastRadius,
					explosionRayParams
				)

				if
					not config.explosionRaycast
					or (result and result.Instance and result.Instance:IsDescendantOf(humanoid.Parent))
				then
					table.insert(humanoidsHit, humanoid)
					local dist = (explosionOrigin - hitPart.Position).Magnitude

					local wasAlive = humanoid.Health > 0
					humanoid:TakeDamage(blastRadius / 1.5 / dist * 100) -- Deal damage based on range, kill if too close

					if humanoid.Health <= 0 and wasAlive and playerResponsible and playerResponsible ~= playerHit then
						-- Player was killed!
						if config.leaderboard then
							playerResponsible.leaderstats.K.Value += 1
						end
					end
				end
			end

			if not hitPart.Anchored then -- Apply a force to unanchored parts
				local tempAtt = Instance.new("Attachment", hitPart)
				tempAtt.Name = "ExplosionForce"
				local force = Instance.new("VectorForce", tempAtt)
				force.Attachment0 = tempAtt
				force.Force = (explosionOrigin - hitPart.Position).Unit * -2000
				debris:AddItem(tempAtt, 0.1)
			end
		end

		-- Destroy after removeTime
		debris:AddItem(explosion, removeTime)
	end
end

return Explode
