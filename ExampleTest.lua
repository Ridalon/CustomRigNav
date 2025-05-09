local CustomRigNav = require(game.ReplicatedStorage.Shared.CustomRigNav)

local rigModel = workspace:FindFirstChild("Huntsman")
if not rigModel then
	warn("Huntsman model not found.")
	return
end

-- Create the navigator instance
local navigator = CustomRigNav.new(rigModel, {
	moveSpeed = 16,
	hipHeight = 4.3,
	stopDistance = 2,
	PathParams = {
		AgentRadius     = 4,
		AgentHeight     = 8,
		AgentCanJump    = false,
		AgentMaxSlope   = 70,
		WaypointSpacing = 1,
	}
})

-- Setup all event listeners
navigator.MoveToFinished:Connect(function()
	print("[Event] MoveTo finished - reached Vector3 position.")
end)

navigator.PathFinished:Connect(function()
	print("[Event] Path finished - reached final waypoint.")
end)

navigator.WaypointReached:Connect(function(index, total)
	print(("[Event] Reached waypoint %d/%d"):format(index, total))
end)

navigator.PathBlocked:Connect(function()
	print("[Event] Path blocked - no path found.")
end)

-- Test 1: MoveTo (straight line)
task.delay(1, function()
	print("? Starting MoveTo to TargetPart.Position")
	local targetPart = workspace:FindFirstChild("TargetPart")
	if not targetPart then
		warn("TargetPart not found.")
		return
	end

	navigator:MoveTo(targetPart.Position)
end)

-- Test 2: Pause and Resume mid-move
task.delay(3, function()
	print("? Pausing movement...")
	navigator:Pause()
end)

task.delay(5, function()
	print("? Resuming movement...")
	navigator:Resume()
end)

-- Test 3: computePathToTarget + moveAlongPath
task.delay(8, function()
	print("? Computing path to TargetPart2")
	local target2 = workspace:FindFirstChild("TargetPart2")
	if not target2 then
		warn("TargetPart2 not found.")
		return
	end

	local waypoints = navigator:computePathToTarget(target2)
	if waypoints then
		print("? Path found with", #waypoints, "waypoints")
		navigator:moveAlongPath(waypoints)
		navigator:VisualizeWaypoints(waypoints, 15)
	else
		warn("? No path to TargetPart2")
	end
end)

-- Test 4: Stop mid-path
task.delay(11, function()
	print("? Stopping movement manually.")
	navigator:Stop()
end)

-- Test 5: Resume path after Stop (compute again)
task.delay(13, function()
	print("? Recomputing path to TargetPart2")
	local target2 = workspace:FindFirstChild("TargetPart2")
	if not target2 then return end

	local waypoints = navigator:computePathToTarget(target2)
	if waypoints then
		navigator:moveAlongPath(waypoints)
	end
end)

-- Final Test: Destroy after completion
task.delay(20, function()
	print("? Destroying navigator and cleaning up")
	navigator:Destroy()
end)
