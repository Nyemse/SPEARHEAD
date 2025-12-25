-- Constants

local ITERATIONS = 8

-- Module

local SPRING = {}

-- Functions

function SPRING.new(self, mass, force, damping, speed)
	local spring = {
		Target = Vector3.new(),
		Position = Vector3.new(),
		Velocity = Vector3.new(),

		Mass = mass or 5,
		Force = force or 50,
		Damping = damping or 4,
		Speed = speed or 4,
	}

	function spring.getstats(self)
		return self.Mass, self.Force, self.Damping, self.Speed
	end

	function spring.changestats(self, mass, force, damping, speed)
		self.Mass = mass or self.Mass
		self.Force = force or self.Force
		self.Damping = damping or self.Damping
		self.Speed = speed or self.Speed
	end

	function spring.shove(self, force: Vector3)
		local x, y, z = force.X, force.Y, force.Z
		if force.Magnitude == 0 then
			return
		end
		if x ~= x or x == math.huge or x == -math.huge then
			x = 0
		end
		if y ~= y or y == math.huge or y == -math.huge then
			y = 0
		end
		if z ~= z or z == math.huge or z == -math.huge then
			z = 0
		end
		self.Velocity = self.Velocity + Vector3.new(x, y, z)
	end

	function spring.update(self, dt)
		local scaledDeltaTime = dt * self.Speed / ITERATIONS
		for i = 1, ITERATIONS do
			local iterationForce = self.Target - self.Position
			local acceleration = (iterationForce * self.Force) / self.Mass

			acceleration = acceleration - self.Velocity * self.Damping

			self.Velocity = self.Velocity + acceleration * scaledDeltaTime
			self.Position = self.Position + self.Velocity * scaledDeltaTime
		end

		return self.Position
	end

	return spring
end

-- Return

return SPRING
