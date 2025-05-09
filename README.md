# 🧭 CustomRigNav

**A lightweight, modular pathfinding system for custom NPC rigs (no Humanoid) on Roblox.**  
Built to give you full control over movement, orientation, and animation of AI characters using `AlignPosition` and `AlignOrientation`.

---

## ✨ Features

-  Works with any rig that has a `PrimaryPart`
-  No `Humanoid` or `Motor6D` required
-  Uses `AlignPosition` and `AlignOrientation` for smooth physics-based movement
-  Clean, readable codebase (~400 LOC)
-  Built-in events: `PathFinished`, `WaypointReached`, `PathBlocked`, `MoveToFinished`
-  Fallback system if pathfinding fails
-  Supports animations via `AnimationController`
-  Utility method to visualize waypoints

---

## 📦 Installation

1. Download or clone this repository.
2. Place the `CustomRigNav` module in `ReplicatedStorage.Modules` or any module folder you prefer.
3. Require it in your scripts and start moving rigs!

---

## 🚀 Quick Start
You can check this simple template, or the full example in the repository !

```lua
local CustomRigNav = require(game.ReplicatedStorage.Modules.CustomRigNav)
local npc = workspace.Enemy

local mover = CustomRigNav.new(npc, {
	moveSpeed = 6,
	hipHeight = 2.5,
	PathParams = {
		AgentRadius = 4,
		AgentCanJump = false,
	}
})

local goal = workspace.TargetPart
local path = mover:computePathToTarget(goal)
if path then
	mover:moveAlongPath(path)
end

mover.PathFinished:Connect(function()
	print("Arrived at destination!")
end)
