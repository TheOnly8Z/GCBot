print("GCBot Ground Control loaded")

GCBot = GCBot or {}
local Player = FindMetaTable("Player")

hook.Add("PlayerInitialSpawn", "GCBot_GroundControl", function(ply)
	if not ply:IsBot() then return end
	timer.Simple(1, function()
		ply:joinTeam((#team.GetPlayers(TEAM_RED) >= #team.GetPlayers(TEAM_BLUE)) and TEAM_BLUE or TEAM_RED)
	end)
end)

hook.Add("PlayerSpawn", "GCBot_GroundControl", function(ply)
	if not ply:IsBot() then return end
	ply.BotState = nil
	ply.Objective = nil 
	ply.NextLook = 0
	ply.LastEngage = 0
end)

hook.Add("PostEntityTakedamage", "GCBot_GroundControl", function(ply, dmginfo)
	if not ply:IsBot() then return end
	if (dmginfo:GetAttacker():IsPlayer() or dmginfo:GetAttacker():IsBot()) and dmginfo:GetAttacker():Team() ~= ply:Team() then
		ply.BotState = 3
		ply.LookGoal = dmginfo:GetAttacker():GetPos()
	end
end)

local machine = include('gcbot/statemachine.lua')

local rush_statemachine = machine.create({
	initial = 'idle',
	events = {
		{ name = 'approach',  from = {'idle', 'camping', 'engaging'},  to = 'approach_point' },
		{ name = 'engage', from = {'idle', 'approach_point'}, to = 'engaging' },
		{ name = 'camp',  from = {'approach_point', 'engaging'},    to = 'camping' }},
})

local function get_camppos(ply, pos, radius)
	local spots = {}
	for _, nav in pairs(navmesh.Find( GCBot.GetTargetVector(pos), radius or ply.Objective.captureDistance, 32, 32 )) do
		local tbl2 = nav:GetHidingSpots(1)
		for i, vec in pairs(tbl2) do
			for _, e in pairs(ents.FindInSphere(vec, 32)) do
				if e:IsPlayer() and e ~= ply then table.remove(tbl2, i) break end
			end
		end
		table.Merge(spots, tbl2)
	end
	ply.CampPos = table.Random(spots)
	if not ply.CampPos then
		ply.CampPos = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetAdjacentAreas()):GetRandomPoint()
	end
	ply.MoveGoal = ply.CampPos
	debugoverlay.Sphere( ply.CampPos, 8, 5, Color(255,255,0), false )
	debugoverlay.Line(ply.CampPos, ply:GetPos(), 5, false)
	print(ply:GetName() .. " Found a camp spot")
end

local function enemy_on_point(ply)
	for _, enemy in pairs(player.GetAll()) do
		if enemy:Alive() and enemy:Team() ~= ply:Team() and enemy:GetPos():Distance(ply.Objective:GetPos()) < ply.Objective.captureDistance then
			return true
		end
	end
	return false
end

local function AI_Rush(ply)
	-- States: 0 - idle; 1 - camping; 2 - contesting; 3 - firing
	if ply.BotState == nil then
		ply.BotState = 1
		ply.Objective = table.Random(ents.FindByClass("gc_capture_point"))
	end

	-- Handle state switch
	--get_targets(ply)

	if #ply.Targets > 0 then
		ply.BotState = 3
		ply.CampPos = nil
		ply.LastEngage = CurTime()
	elseif ply.BotState == 3 and ply.LastEngage + 5 < CurTime() then
		ply.BotState = 1
	elseif ply.BotState == 1 and ply.Objective:GetPos():Distance(ply:GetPos()) <= ply.Objective.captureDistance then
		ply.BotState = 2
		ply.CampPos = nil
		timer.Simple(8, function() if IsValid(ply) and ply.CampPos then ply.MoveGoal = nil end end)
	elseif ply.BotState == 2 and ply:Team() == GAMEMODE.curGametype.realDefenderTeam then
		for _, ent in pairs(ents.FindByClass("gc_capture_point")) do
			if ent ~= ply.Objective and ent.dt.CaptureProgress > ply.Objective.dt.CaptureProgress then
				ply.Objective = ent 
				ply.BotState = 1
				ply.LookGoal = nil
			end
		end
	end

	-- Handle logic
	if ply.BotState == 1 then
		if !IsValid(ply.PathTarget) then
			--ply.PathTarget = ply.Objective
			local navs
			if ply:Team() == GAMEMODE.curGametype.realDefenderTeam then
				navs = navmesh.Find( GCBot.GetTargetVector(ply.Objective), ply.Objective.captureDistance * 2, 64, 64 )
			else
				navs = navmesh.Find( GCBot.GetTargetVector(ply.Objective), ply.Objective.captureDistance * 0.8, 64, 64 )
			end
			ply.PathTarget = table.Random(navs)
		end
		if ply.Objective:GetPos():Distance(ply:GetPos()) >= 600 and #ply.Targets == 0 then
			ply.Buttons = ply.Buttons + IN_SPEED
		end

	elseif ply.BotState == 2 then

		if not IsValid(ply.CampPos) then
			--get_camppos(ply, ply.Objective)
			ply.CampPos = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetHidingSpots(1))
		elseif enemy_on_point(ply) then -- Look for enemies
			if ply.NextLook < CurTime() then
				ply.NextLook = CurTime() + math.random() * 1 + 2
				ply.LookGoal = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetAdjacentAreas()):GetRandomPoint() + Vector(math.random(-20, 20),math.random(-20, 20),60)
				ply.MoveGoal = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetAdjacentAreas()):GetRandomPoint() + Vector(math.random(-20, 20),math.random(-20, 20),60)
			end
		elseif ply.CampPos and ply.CampPos:Distance(ply:GetPos()) <= 32 then
			if ply.NextLook < CurTime() then
				ply.NextLook = CurTime() + math.random() * 1.5 + 0.5
				local tr_x = util.QuickTrace(ply:EyePos(), Vector(5000, 0, 0), ply)
				local tr_y = util.QuickTrace(ply:EyePos(), Vector(0, 5000, 0), ply)
				local tr_nx = util.QuickTrace(ply:EyePos(), Vector(-5000, 0, 0), ply)
				local tr_ny = util.QuickTrace(ply:EyePos(), Vector(5000, -5000, 0), ply)
				local tbl = {tr_x, tr_y, tr_nx, tr_ny}
				local cur = nil
				for _, tr in pairs(tbl) do
					if not cur or tr.Fraction * (math.random()*0.6+0.7) > cur.Fraction then
						cur = tr
					end
				end
				ply.LookGoal = cur.HitPos
				--ply.LookGoal = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetAdjacentAreas()):GetRandomPoint() + Vector(math.random(-20, 20),math.random(-20, 20),60)
			end
		end

	elseif ply.BotState == 3 then
		if ply.LookGoal == nil or not table.HasValue(ply.Targets, ply.LookGoal) or not IsValid(ply.LookGoal) or (ply.LookGoal:IsPlayer() and not ply.LookGoal:Alive()) then
			ply.LookGoal = table.Random(ply.Targets)
		end
		if ply:GetActiveWeapon():GetClass() == "cw_extrema_ratio_official" then
			ply.MoveGoal = ply.LookGoal
		elseif ply.NextLook < CurTime() then
			ply.NextLook = CurTime() + math.random() * 1 + 0.5
			ply.MoveGoal = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetAdjacentAreas()):GetRandomPoint()
		end
	end
end

/*
local function AI_Rush_Attack(ply)
	-- States: 0 - idle; 1 - approaching; 2 - taking; 3 - shooting
	if ply.BotState == nil then
		ply.BotState = 1
		ply.Objective = table.Random(ents.FindByClass("gc_capture_point"))
	end

	-- Handle state switch
	--get_targets(ply)

	if #ply.Targets > 0 then
		ply.BotState = 3
		ply.CampPos = nil
		ply.NextLook = CurTime() + math.random() * 0.5 + 0.2
	elseif #ply.Targets == 0 and ply.BotState == 3 then
		ply.BotState = 1
	elseif ply.BotState == 1 and ply.Objective:GetPos():Distance(ply:GetPos()) <= ply.Objective.captureDistance then
		ply.BotState = 2
		ply.CampPos = nil
	end

	-- Handle logic
	if ply.BotState == 1 then
		if !IsValid(ply.PathTarget) then
			ply.PathTarget = ply.Objective
		end
		ply.Buttons = ply.Buttons + IN_SPEED
	elseif ply.BotState == 2 then
		if not ply.CampPos then
			get_camppos(ply, ply.Objective)
		elseif enemy_on_point(ply) then -- Look for enemies
			if ply.NextLook < CurTime() then
				ply.NextLook = CurTime() + math.random() * 1 + 2
				ply.LookGoal = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetAdjacentAreas()):GetRandomPoint() + Vector(math.random(-20, 20),math.random(-20, 20),60)
				ply.MoveGoal = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetAdjacentAreas()):GetRandomPoint() + Vector(math.random(-20, 20),math.random(-20, 20),60)
			end
		elseif ply.CampPos and ply.CampPos:Distance(ply:GetPos()) <= 32 then
			if ply.NextLook < CurTime() then
				ply.NextLook = CurTime() + math.random() * 1.5 + 0.5
				local tr_x = util.QuickTrace(ply:EyePos(), Vector(5000, 0, 0), ply)
				local tr_y = util.QuickTrace(ply:EyePos(), Vector(0, 5000, 0), ply)
				local tr_nx = util.QuickTrace(ply:EyePos(), Vector(-5000, 0, 0), ply)
				local tr_ny = util.QuickTrace(ply:EyePos(), Vector(5000, -5000, 0), ply)
				local tbl = {tr_x, tr_y, tr_nx, tr_ny}
				local cur = nil
				for _, tr in pairs(tbl) do
					if not cur or tr.Fraction * (math.random()*0.6+0.7) > cur.Fraction then
						cur = tr
					end
				end
				ply.LookGoal = cur.HitPos
				--ply.LookGoal = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetAdjacentAreas()):GetRandomPoint() + Vector(math.random(-20, 20),math.random(-20, 20),60)
			end
		end
	elseif ply.BotState == 3 then
		if ply.LookGoal == nil or not IsValid(ply.LookGoal) or ply.LookGoal:IsPlayer() and not ply.LookGoal:Alive() then
			ply.LookGoal = table.Random(ply.Targets)
		end
		if ply.NextLook < CurTime() then
			ply.NextLook = CurTime() + math.random() * 1.5 + 0.5
			ply.MoveGoal = table.Random(navmesh.GetNearestNavArea( ply:GetPos() ):GetAdjacentAreas()):GetRandomPoint()
		end
	end

end
*/

local function AI_Ghetto_Red(ply)

end

local function AI_Ghetto_Blue(ply)

end

function GCBot.GamemodeThink(ply)
	local curType = GAMEMODE.curGametype

	if GAMEMODE.RoundOver or CurTime() < GAMEMODE.PreparationTime + 1 then return end

	if curType.name == "ghettodrugbust" then
		if ply:Team() == TEAM_RED then
			AI_Ghetto_Red(ply)
		elseif ply:Team() == TEAM_BLUE then
			AI_Ghetto_Blue(ply)
		end
	elseif curType.name == "onesiderush" then

		AI_Rush(ply)
		/*
		if ply:Team() == curType.realDefenderTeam then
			AI_Rush_Defend(ply)
		elseif ply:Team() == curType.realAttackerTeam then
			AI_Rush_Attack(ply)
		end
		*/
	end
end

hook.Add("GroundControlPostInitEntity", "GCBot_GroundControl", function()

	-- Override Ground Control meta functions to work with bots

	function Player:getDesiredPrimaryMags()
		if self:IsBot() then return GAMEMODE.MaxPrimaryMags end
		return math.Clamp(self:GetInfoNum("gc_primary_mags", GAMEMODE.DefaultPrimaryIndex), 1, GAMEMODE.MaxPrimaryMags)
	end

	function Player:getDesiredSecondaryMags()
		if self:IsBot() then return GAMEMODE.MaxSecondaryMags end
		return math.Clamp(self:GetInfoNum("gc_secondary_mags", GAMEMODE.DefaultPrimaryIndex), 1, GAMEMODE.MaxSecondaryMags)
	end

	function Player:getDesiredPrimaryWeapon()
		local primary = math.Clamp(self:GetInfoNum("gc_primary_weapon", GAMEMODE.DefaultPrimaryIndex), 0, #GAMEMODE.PrimaryWeapons) -- don't go out of bounds
		if self:IsBot() then primary = math.random(#GAMEMODE.PrimaryWeapons) end
		return GAMEMODE.PrimaryWeapons[primary], primary
	end

	function Player:getDesiredSecondaryWeapon()
		local secondary = math.Clamp(self:GetInfoNum("gc_secondary_weapon", GAMEMODE.DefaultSecondaryIndex), 0, #GAMEMODE.SecondaryWeapons)
		if self:IsBot() then secondary = math.random(#GAMEMODE.SecondaryWeapons) end
		return GAMEMODE.SecondaryWeapons[secondary], secondary
	end

	function Player:getDesiredTertiaryWeapon()
		local tertiary = math.Clamp(self:GetInfoNum("gc_tertiary_weapon", GAMEMODE.DefaultTertiaryIndex), 0, #GAMEMODE.TertiaryWeapons)
		if self:IsBot() then tertiary = math.random(#GAMEMODE.TertiaryWeapons) end
		return GAMEMODE.TertiaryWeapons[tertiary], tertiary
	end

	print("GroundControlPostInitEntity complete")

end)