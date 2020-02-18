
GCBot = {}

local function botNoRecoil(wep, mod)
	return wep.Owner:IsBot() and 0 or mod
end
CustomizableWeaponry.callbacks:addNew("calculateRecoil", "botNoRecoil", botNoRecoil)


local function heuristic_cost_estimate( start, goal )
	// Perhaps play with some calculations on which corner is closest/farthest or whatever
	return start:GetCenter():Distance( goal:GetCenter() )
end

local function reconstruct_path( cameFrom, current )
	local total_path = { current }

	current = current:GetID()
	while ( cameFrom[ current ] ) do
		current = cameFrom[ current ]
		table.insert( total_path, navmesh.GetNavAreaByID( current ) )
	end
	return total_path
end

function GCBot.GetTargetVector(target, no_offset)
	if type(target) == "CNavArea" then
		return target:GetCenter()
	elseif IsValid(target) and target:IsPlayer() then
		if no_offset then
			return target:GetPos()
		elseif target:Crouching() then
			return target:GetPos() + Vector(0,0,30)
		else
			return target:GetPos() + Vector(0,0,60)
		end
	elseif IsValid(target) and target.GetPos then
		return target:GetPos()
	elseif isvector(target) then
		return target
	end
end

function drawThePath( path, time ) -- debug
	local prevArea
	for _, area in pairs( path ) do
		debugoverlay.Sphere( area:GetCenter(), 8, time or 9, color_white, true  )
		if ( prevArea ) then
			debugoverlay.Line( area:GetCenter(), prevArea:GetCenter(), time or 9, color_white, true )
		end

		area:Draw()
		prevArea = area
	end
end

hook.Add("PlayerSpawn", "GCBot", function(ply)
	if ply:IsBot() then
		ply:GC_Initialize()
	end
end)

hook.Add("StartCommand", "GCBot", function(ply, cmd)

	if not ply:IsBot() then return end -- or not engine.ActiveGamemode() == "groundcontrol" 

	cmd:ClearButtons()
	cmd:ClearMovement()

	if ply.Buttons then
		cmd:SetButtons(ply.Buttons)
	end

	if ply.LookGoal then
		cmd:SetViewAngles(LerpAngle(0.1, ply.CachedAngle, (GCBot.GetTargetVector(ply.LookGoal) - ply:EyePos()):Angle()))

		ply:GC_Attack(cmd)
	end

	if ply.MoveGoal then

		if not ply.LookGoal then
			cmd:SetViewAngles(LerpAngle(0.1, ply.CachedAngle, (GCBot.GetTargetVector(ply.MoveGoal) + Vector(0,0,72) - ply:EyePos()):Angle()))
		end

		local target = GCBot.GetTargetVector(ply.MoveGoal)
		local spd = ply:GetWalkSpeed()
		local ang = ply.CachedAngle or ply:EyeAngles()
		local forward = ang:Forward()
		forward.z = 0
		local right = forward:Cross(ang:Up())
		local vec = (target - ply:GetPos())
		cmd:SetForwardMove( spd * forward:Dot(vec) )
		cmd:SetSideMove( spd * right:Dot(vec) )
		if ply:GetPos():Distance(target) <= 16 then
			ply.MoveGoal = nil
			cmd:SetForwardMove( 0 ) 
			cmd:SetSideMove( 0 )
		end
	else
		cmd:SetForwardMove( 0 ) 
		cmd:SetSideMove( 0 )
	end

end)

hook.Add("Think", "GCBot", function()
	for _, ply in pairs(player.GetAll()) do
		if ply:IsBot() and ply:Alive() then
			ply:GC_Think()
		end
	end
end)

-- From wiki
function GCBot.Astar( start, goal )
	if ( !IsValid( start ) || !IsValid( goal ) ) then return false end
	if ( start == goal ) then return true end

	start:ClearSearchLists()

	start:AddToOpenList()

	local cameFrom = {}

	start:SetCostSoFar( 0 )

	start:SetTotalCost( heuristic_cost_estimate( start, goal ) )
	start:UpdateOnOpenList()

	while ( !start:IsOpenListEmpty() ) do
		local current = start:PopOpenList() // Remove the area with lowest cost in the open list and return it
		if ( current == goal ) then
			return reconstruct_path( cameFrom, current )
		end

		current:AddToClosedList()

		for k, neighbor in pairs( current:GetAdjacentAreas() ) do
			local newCostSoFar = current:GetCostSoFar() + heuristic_cost_estimate( current, neighbor )

			if ( neighbor:IsUnderwater() ) then // Add your own area filters or whatever here
				continue
			end
			
			if ( ( neighbor:IsOpen() || neighbor:IsClosed() ) && neighbor:GetCostSoFar() <= newCostSoFar ) then
				continue
			else
				neighbor:SetCostSoFar( newCostSoFar );
				neighbor:SetTotalCost( newCostSoFar + heuristic_cost_estimate( neighbor, goal ) )

				if ( neighbor:IsClosed() ) then
				
					neighbor:RemoveFromClosedList()
				end

				if ( neighbor:IsOpen() ) then
					// This area is already on the open list, update its position in the list to keep costs sorted
					neighbor:UpdateOnOpenList()
				else
					neighbor:AddToOpenList()
				end

				cameFrom[ neighbor:GetID() ] = current:GetID()
			end
		end
	end

	return false
end

-- From wiki
function GCBot.AstarVector( start, goal )
	local startArea = navmesh.GetNearestNavArea( start )
	local goalArea = navmesh.GetNearestNavArea( goal )
	return GCBot.Astar( startArea, goalArea )
end

function GCBot.BorrowPathing(ply) -- We can steal the navpath of a player with same goals
	for _, pl in pairs(player.GetAll()) do
		if pl.PathTarget and pl.NavPath and pl:GetPos():Distance(ply:GetPos()) <= 512 and navmesh.GetNearestNavArea( GCBot.GetTargetVector(pl.PathTarget, true) ) == navmesh.GetNearestNavArea( GCBot.GetTargetVector(ply.PathTarget, true) ) then
			local path = table.Copy(pl.NavPath)
			local secondpath = GCBot.Astar(navmesh.GetNearestNavArea(ply:GetPos()), path[#path])
			if istable(secondpath) then
				table.remove(path) -- take out a duplicate last entry
				table.Merge(path, secondpath)
				return path
			end
		end
	end
	return false
end