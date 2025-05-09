-- CustomRigNav v1.0 by @Sollal – Open Source
-- A modular movement framework for custom rigs (no Humanoid)
local CustomRigNav = {}

local PathfindingService     = game:GetService("PathfindingService")
local PhysicsService 		 = game:GetService("PhysicsService")
local RunService             = game:GetService("RunService")
local Players                = game:GetService("Players")

-- Utility: calculate horizontal (XZ) distance only
local function flatDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function applyPathfindingModifiers(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			local mod = Instance.new("PathfindingModifier")
			mod.PassThrough = true
			mod.Name = "IgnoreForPath"
			mod.Parent = part
		end
	end
end

-- Constructor
function CustomRigNav.new(model, config)
	local self = {}
	setmetatable(self, { __index = CustomRigNav })

	-- Core references
	self.Model               = model
	self.Config              = config or {}
	self.Config.moveSpeed    = self.Config.moveSpeed or 6
	self.Config.hipHeight    = self.Config.hipHeight or 3
	self.Config.stopDistance = self.Config.stopDistance or 1
	self.PathParams          = self.Config.PathParams or {}
	applyPathfindingModifiers(self.Model)

	-- Internal state
	self.AlignPosition      = nil
	self.AlignOrientation   = nil
	self.Animations         = {}
	self.CurrentTrack       = nil
	self._waypointConnection= nil
	self._isPaused          = false

	-- Events
	self._events = {
		MoveToFinished  = Instance.new("BindableEvent"),
		PathFinished    = Instance.new("BindableEvent"),
		WaypointReached = Instance.new("BindableEvent"),
		PathBlocked 	= Instance.new("BindableEvent")
	}
	self.MoveToFinished  = self._events.MoveToFinished.Event
	self.PathFinished    = self._events.PathFinished.Event
	self.WaypointReached = self._events.WaypointReached.Event
	self.PathBlocked	 = self._events.PathBlocked.Event
	-- Initialize
	self:_initAlign()
	self:_loadAnimations()
	self:_playState("Idle")
	
	print(self.Model.PrimaryPart.Position)
	print(self.AlignPosition.Position)

	-- Height adjustment loop
	task.delay(1, function()
		RunService.Heartbeat:Connect(function()
			self:_updateHeight()
		end)
	end)


	return self
end

-- Private: setup AlignPosition & AlignOrientation
function CustomRigNav:_initAlign()
	local root = self.Model.PrimaryPart
	local attachment = root:FindFirstChild("RootAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name   = "RootAttachment"
		attachment.Parent = root
	end

	self.AlignPosition 					= Instance.new("AlignPosition")
	self.AlignPosition.MaxForce         = 1e6
	self.AlignPosition.ApplyAtCenterOfMass = true
	self.AlignPosition.Responsiveness   = 200
	self.AlignPosition.Attachment0      = attachment
	self.AlignPosition.Mode             = Enum.PositionAlignmentMode.OneAttachment
	self.AlignPosition.Parent           = root
	self.AlignPosition.Position 		= root.Position

	self.AlignOrientation = Instance.new("AlignOrientation")
	self.AlignOrientation.MaxTorque     = 1e6
	self.AlignOrientation.Responsiveness= 200
	self.AlignOrientation.Attachment0   = attachment
	self.AlignOrientation.Mode          = Enum.OrientationAlignmentMode.OneAttachment
	self.AlignOrientation.Parent        = root
end

function CustomRigNav:_loadAnimations()
	local controller = self.Model:FindFirstChildWhichIsA("AnimationController")
	local folder     = self.Model:FindFirstChild("Animations")
	if not controller or not folder then return end

	for _, anim in ipairs(folder:GetChildren()) do
		if anim:IsA("Animation") then
			self.Animations[anim.Name] = controller:LoadAnimation(anim)
		end
	end
end

function CustomRigNav:_playState(state)
	-- Stop any non-idle track
	if self.CurrentTrack and self.CurrentTrack ~= self.Animations["Idle"] then
		self.CurrentTrack:Stop()
	end

	-- Handle Idle separately
	if state == "Idle" then
		local idle = self.Animations["Idle"]
		if idle and not idle.IsPlaying then
			idle:Play()
		end
		return
	end

	-- Play new state (Walk, Attack, etc.)
	local track = self.Animations[state]
	if track then
		track:Play()
		self.CurrentTrack = track
	end
end

function CustomRigNav:_updateHeight()
	if not self.AlignPosition then return end

	local origin = self.Model.PrimaryPart.Position
	local params = RaycastParams.new()
	local exclude = { self.Model }

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			table.insert(exclude, char)
		end
	end

	params.FilterDescendantsInstances = exclude
	params.FilterType                 = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(origin, Vector3.new(0, -100, 0), params)
	if result then
		local targetY = result.Position.Y + self.Config.hipHeight
		local currPos = self.AlignPosition.Position
		if math.abs(currPos.Y - targetY) > 0.05 then
			self.AlignPosition.Position = Vector3.new(currPos.X, targetY, currPos.Z)
		end
	end
end

local function findNearestReachable(self, targetPosition, searchRadius, attempts)
	searchRadius = searchRadius or 10
	attempts = attempts or 16

	local closest = nil
	local shortest = math.huge

	for i = 1, attempts do
		local offset = Vector3.new(
			math.random(-searchRadius, searchRadius),
			0,
			math.random(-searchRadius, searchRadius)
		)

		local testPos = targetPosition + offset
		local path = PathfindingService:CreatePath(self.PathParams)
		path:ComputeAsync(self.Model.PrimaryPart.Position, testPos)

		if path.Status == Enum.PathStatus.Success then
			local dist = (testPos - targetPosition).Magnitude
			if dist < shortest then
				closest = path:GetWaypoints()
				shortest = dist
			end
		end
	end

	return closest
end


-- Public: move in straight line to position
function CustomRigNav:MoveTo(position)
	if typeof(position) ~= "Vector3" then return end
	self:Stop()
	self:_playState("Walk")

	local speed = self.Config.moveSpeed
	local stopD = self.Config.stopDistance

	self._waypointConnection = RunService.Heartbeat:Connect(function(dt)
		if self._isPaused then return end
		local curr = self.Model.PrimaryPart.Position
		local dir  = Vector3.new(position.X - curr.X, 0, position.Z - curr.Z)
		if dir.Magnitude < stopD then
			self:_playState("Idle")
			self._events.MoveToFinished:Fire()
			self._waypointConnection:Disconnect()
			self._waypointConnection = nil
			return
		end
		local step = dir.Unit * speed * dt
		local nextPos = Vector3.new(curr.X + step.X, curr.Y, curr.Z + step.Z)
		self.AlignPosition.Position = nextPos
		local lookC = CFrame.lookAt(curr, curr + dir)
		local current = self.AlignOrientation.CFrame
		local target = CFrame.new(Vector3.zero, lookC.LookVector)
		self.AlignOrientation.CFrame = current:Lerp(target, 0.2)
	end)
end

-- Public: compute path to target part using PathParams
function CustomRigNav:computePathToTarget(targetPart)
	if not targetPart then return end

	print(self.AlignPosition.Position)
	print(self.Model.PrimaryPart.Position)
	
	local pp = self.PathParams
	local params = {
		AgentRadius     = pp.AgentRadius or 4.8,
		AgentHeight     = pp.AgentHeight or 5,
		AgentCanJump    = pp.AgentCanJump or false,
		AgentJumpHeight = pp.AgentJumpHeight or 10,
		AgentMaxSlope   = pp.AgentMaxSlope or 70,
		WaypointSpacing = pp.WaypointSpacing or 0.5,
		Costs           = pp.Costs,
	}

	local baseOrigin = self.Model.PrimaryPart.Position
	baseOrigin = self.AlignPosition.Position
	local toTarget = (targetPart.Position - baseOrigin).Unit
	local origin = baseOrigin + toTarget * 2

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { self.Model }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = workspace:Raycast(origin + Vector3.new(0, 2, 0), Vector3.new(0, -10, 0), rayParams)
	if rayResult then
		origin = Vector3.new(origin.X, rayResult.Position.Y + 0.1, origin.Z)
	end

	local maxRetries = self.Config.maxRetries or 2
	local retryEnabled = self.Config.retryIfNoPath ~= false

	for attempt = 1, maxRetries + 1 do
		local path = PathfindingService:CreatePath(params)
		print("Path Start Y =", origin.Y)
		path:ComputeAsync(origin, targetPart.Position)

		if path.Status == Enum.PathStatus.Success then
			return path:GetWaypoints()
		elseif retryEnabled and attempt <= maxRetries then
			warn(string.format("[CustomRigNav] Path attempt %d failed (%s), retrying...", attempt, path.Status.Name))
			task.wait(0.2)
		end
	end

	warn("[CustomRigNav] NoPath - searching for closest reachable point")
	local altWaypoints = findNearestReachable(self, targetPart.Position)
	if altWaypoints then
		return altWaypoints
	else
		warn("[CustomRigNav] No reachable alternative found.")
		self._events.PathBlocked:Fire()
	end

	return nil
end


-- Public: follow computed waypoints
function CustomRigNav:moveAlongPath(waypoints)
	self:Stop()
	self:_playState("Walk")

	local model = self.Model
	local speed = self.Config.moveSpeed
	local idx   = 1
	local total = #waypoints

	self._waypointConnection = RunService.Heartbeat:Connect(function(dt)
		if self._isPaused then return end
		if idx > total then
			self:_playState("Idle")
			self._events.PathFinished:Fire()
			self._waypointConnection:Disconnect()
			self._waypointConnection = nil
			return
		end
		local curr    = model.PrimaryPart.Position
		local targetP = waypoints[idx].Position
		local dir     = Vector3.new(targetP.X - curr.X, 0, targetP.Z - curr.Z).Unit
		local step    = dir * speed * dt
		local nextPos = Vector3.new(curr.X + step.X, curr.Y, curr.Z + step.Z)

		self.AlignPosition.Position       = nextPos
		local current = self.AlignOrientation.CFrame
		local target = CFrame.new(Vector3.zero, CFrame.lookAt(curr, curr + dir).LookVector)
		self.AlignOrientation.CFrame = current:Lerp(target, 0.2)

		if flatDistance(curr, targetP) < self.Config.stopDistance then
			self._events.WaypointReached:Fire(idx, #waypoints)
			idx += 1
		end
	end)
end

-- Public: pause/resume
function CustomRigNav:Pause()
	if not self._waypointConnection then return end
	self._isPaused = true
	self:_playState("Idle")
end

function CustomRigNav:Resume()
	if not self._waypointConnection then return end
	self._isPaused = false
	self:_playState("Walk")
end

-- Public: stop any motion immediately
function CustomRigNav:Stop()
	if self._waypointConnection then
		self._waypointConnection:Disconnect()
		self._waypointConnection = nil
	end
	self:_playState("Idle")
end

-- Public: destroy the mover and clean up everything
function CustomRigNav:Destroy()
	self:Stop()
	for _, track in pairs(self.Animations) do
		if track:IsA("AnimationTrack") then
			track:Stop()
			track:Destroy()
		end
	end
	self.Animations       = nil
	self.CurrentTrack     = nil

	if self.AlignPosition then
		self.AlignPosition:Destroy()
		self.AlignPosition = nil
	end
	if self.AlignOrientation then
		self.AlignOrientation:Destroy()
		self.AlignOrientation = nil
	end

	if self._events then
		for _, ev in pairs(self._events) do
			ev:Destroy()
		end
		self._events = nil
	end

	self.Model             = nil
	self.Config            = nil
	self._isPaused         = nil
	self._waypointConnection= nil
end

function CustomRigNav:VisualizeWaypoints(waypoints, duration)
	duration = duration or 5

	for i, wp in ipairs(waypoints) do
		local sphere = Instance.new("Part")
		sphere.Shape = Enum.PartType.Ball
		sphere.Material = Enum.Material.SmoothPlastic
		sphere.Color = Color3.fromRGB(150, 150, 150)
		sphere.Size = Vector3.new(0.5, 0.5, 0.5)
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.Transparency = 0.3
		sphere.Name = "Waypoint_" .. i
		sphere.Position = wp.Position
		sphere.Parent = workspace
		
		local mod = Instance.new("PathfindingModifier")
		mod.PassThrough = true
		mod.Name = "IgnoreForPath"
		mod.Parent = sphere

		-- Auto-remove after `duration` seconds
		task.delay(duration, function()
			if sphere and sphere.Parent then
				sphere:Destroy()
			end
		end)
	end
end

return CustomRigNav
