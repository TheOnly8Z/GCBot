local Player = FindMetaTable("Player")

function Player:GC_ClearGoals()
	if not self:IsBot() then return end
	self.NavPath = nil 
	self.LookGoal = nil 
	self.MoveGoal = nil
	self.Targets = nil
	self.NextPath = 0
	self.LastPos = nil
	self.StuckCount = 0
	self.EnemyMemory = {}
	self.NextBurst = nil
	self.BurstLeft = 0
end

function Player:GC_PathTo(target)
	if not self:IsBot() then return end
	self.PathTarget = GCBot.GetTargetVector(target, true) --GCBot.AstarVector( self:GetPos(), pos )
	self.NextPath = CurTime()
end

function Player:GC_SimpleChase(target)
	if not self:IsBot() then return end
	self.LookGoal = target 
	self.MoveGoal = target
	self.Targets = self.Targets or {}
	if not table.HasValue(self.Targets, target) then
		table.insert(self.Targets, target)
	end
end

function Player:GC_Initialize()
	if not self:IsBot() then return end
	self:GC_ClearGoals()
end

function Player:GC_Move()

	if not self:IsBot() then return end

	-- Check goal
	if GCBot.GetTargetVector(self.PathTarget, true) then

		local currentArea = navmesh.GetNearestNavArea( self:GetPos() )
		local targetArea = navmesh.GetNearestNavArea( GCBot.GetTargetVector(self.PathTarget, true) )

		if (self.NextPath or 0) >= CurTime() or not istable(self.NavPath) then
			self.NavPath = GCBot.BorrowPathing(self) or GCBot.Astar(currentArea, targetArea)
			if istable(self.NavPath) then
				self.NextPath = CurTime() + 10
				table.remove( self.NavPath ) -- remove first
			elseif self.NavPath == false then
				print(self:GetName() .. " Failed to path to target.")
				self.PathTarget = nil
				return
			elseif self.NavPath == true then
				--print(self:GetName() .. " Pathing successful")
				self.NavPath = nil
				self.PathTarget = nil
				return
			end
		end

		--drawThePath( self.NavPath, .1 ) 
		

		if (self.LastPos and self.LastPos:Distance(self:GetPos()) <= 24) then
			self.StuckCount = self.StuckCount + 1
			if self.StuckCount > 256 then
				print(self:GetName() .. " gave up pathing")
				self.StuckCount = 0
				self.PathTarget = nil
				return
			elseif self.StuckCount == 64 then
				print(self:GetName() .. " Seems to be stuck")
				self.MoveGoal = GCBot.GetTargetVector(self.PathTarget) + Vector(math.random(-20, 20), math.random(-20, 20), 0)
				self.PathTarget = nil
			end
		else
			self.StuckCount = 0
			self.LastPos = self:GetPos()
		end

		

		if ( !self.NavPath || #self.NavPath < 1 ) then
			self.NavPath = nil
			self.PathTarget = nil
			return
		end

		if ( not IsValid( self.MoveGoal ) ) then

			local t = #self.NavPath - 1
			while (t > 0) do -- Cut some corners
				local tr = util.TraceEntity({
					start = self:GetPos(),
					endpos = self.NavPath[ t ]:GetCenter(),
					filter = self
				}, self)--util.QuickTrace(self:GetPos() + Vector(0,0,32), self.NavPath[ t ]:GetCenter() - (self:GetPos() + Vector(0,0,32)), self)
				if tr.Fraction < 0.9 then
					break
				else
					t = t - 1
				end
			end

			self.MoveGoal = self.NavPath[ t + 1 ]:GetCenter() -- spread out
			-- Check for a jumpable obstacle
			if self.NavPath[ #self.NavPath ]:GetCenter().z - 32 > currentArea:GetCenter().z and self:OnGround() 
					and self.NavPath[ #self.NavPath ]:GetClosestPointOnArea(self:GetPos()):Distance(self:GetPos()) <= 48 then
				self.Buttons = bit.bor(self.Buttons, IN_JUMP + IN_DUCK)
			end
			if self.NavPath[ #self.NavPath ]:HasAttributes(NAV_MESH_JUMP) then
				self.Buttons = bit.bor(self.Buttons, IN_JUMP + IN_DUCK)
			end
			if self.NavPath[ #self.NavPath ]:HasAttributes(NAV_MESH_CROUCH) then
				self.Buttons = bit.bor(self.Buttons, IN_DUCK)
			end
			local tr = self:GetEyeTrace()
			if tr.Entity and tr.Entity:GetClass() == "prop_door_rotating" and tr.Entity:GetPos():Distance(self:EyePos()) <= 32 then -- and tr.Entity:GetInternalVariable("m_eDoorState") == 0
				self.Buttons = self.Buttons + IN_USE
			end
		end

		if ( !IsValid( self.MoveGoal ) || ( self.MoveGoal == currentArea && self.MoveGoal:GetCenter():Distance( self:GetPos() ) < 64 ) ) then
			table.remove( self.NavPath )
			return
		end
	end
end


local function get_targets(ply)
	ply.Targets = {}

	for i, enemy in pairs(player.GetAll()) do
		if enemy ~= ply and enemy:Team() ~= ply:Team() and enemy:Alive() then
			local tr = util.TraceLine({
				start = ply:EyePos(),
				endpos = enemy:GetPos(),
				filter = ply,
				--mask = MASK_BLOCKLOS
			})
			--print(ply:GetName() .. " trace to " .. enemy:GetName() .. ": " .. tostring(tr.Entity) .. " (" .. tr.Fraction ..")")
			if (tr.Entity == enemy and ply:GC_EyeDiff(enemy) <= 1)
					or ply:GetPos():Distance(enemy:GetPos()) <= 96 then
				table.insert(ply.Targets, enemy)
				ply.EnemyMemory[enemy] = CurTime() + math.random(6, 10)
			end
		end
	end

	for enemy, t in pairs(ply.EnemyMemory) do
		if t < CurTime() or not IsValid(enemy) or not enemy:Alive() then 
			ply.EnemyMemory[enemy] = nil
		else
			if not table.HasValue(ply.Targets) then
				table.insert(ply.Targets, enemy)
			end
		end
	end
end

function Player:GC_Think()
	if not self:IsBot() then return end
	self.CachedAngle = self:EyeAngles() -- Workaround for SetupCommand not getting eyeangles
	self.Buttons = 0 -- used to pass IN_ commands

	get_targets(self)

	if GCBot.GamemodeThink then GCBot.GamemodeThink(self) end
	if self.NoMove ~= true then self:GC_Move() end

end

function Player:GC_EyeDiff(pos)
	if not self:IsBot() then return end
	local v1 = self.CachedAngle:Forward()
	local v2 = (GCBot.GetTargetVector(pos) - self:EyePos()):GetNormalized()
	return 1 - v1:Dot(v2)
end

function Player:GC_Attack(cmd)

	if self.QueueReload then
		cmd:SetButtons(IN_RELOAD)
		self.QueueReload = false
		return
	end

	if self.Targets then
		for _, enemy in pairs(self.Targets) do
			local wep = self:GetActiveWeapon()

			local tr = util.TraceLine({
				start = self:EyePos(),
				endpos = enemy:EyePos(),
				filter = self})

			if IsValid(enemy) and tr.Entity == enemy and self:GC_EyeDiff(enemy) <= 0.05 and IsValid(wep) then
				-- TODO do some magic with this
				if wep:Clip1() == 0 then
					if self:GetAmmoCount(wep:GetPrimaryAmmoType()) <= 0 then
						local newWep = nil
						for _, w in pairs(self:GetWeapons()) do
							if w ~= wep and not w.isTertiaryWeapon and not w.isKnife and (w:Clip1() > 0 or self:GetAmmoCount(w:GetPrimaryAmmoType()) > 0) then
								newWep = w:GetClass()
								break
							end
						end
						self:SelectWeapon(newWep or "cw_extrema_ratio_official")
					else
						cmd:SetButtons(cmd:GetButtons() + IN_RELOAD)	
					end
				
				else

					local dist = enemy:GetPos():Distance(self:GetPos())

					if wep.CW20Weapon then
						
						local typ = GCBot_CW2Table[wep:GetClass()]
						local delay = 0.2 -- after a whole burst
						local burst = 1 -- 1 means click a lot
						local aim = false -- true forces crosshair

						if typ == "pistol" then
							delay = wep.FireDelay * (1 + math.random() * 0.3)
							burst = 1
							if dist > 1400 then aim = true end
							if dist < 700 then delay = wep.FireDelay end
						elseif typ == "pistol_heavy" then -- revolvers, deagle
							delay = wep.FireDelay * (1.5 + math.random() * 1)
							burst = 1
							if dist > 1000 then aim = true end
							if dist < 600 then delay = wep.FireDelay end
						elseif typ == "smg" then
							delay = 0 -- spraaaay and
							burst = math.Round(wep.Primary.ClipSize / 3) -- praaay
							if dist > 1000 then aim = true end
						elseif typ == "assault_rifle" then
							delay = wep.FireDelay * (1.5 + math.random() * 2)
							burst = math.random(4, 6)
							if dist > 1400 then aim = true end
							if dist < 400 then delay = 0 end
						elseif typ == "battle_rifle" then
							delay = wep.FireDelay * (3 + math.random() * 2)
							burst = math.random(1, 3)
							if dist > 2000 then aim = true end
							if dist < 400 then delay = wep.FireDelay end
						elseif typ == "sniper" then
							delay = wep.FireDelay * 3
							burst = 1
							if dist > 600 then aim = true end
						elseif typ == "shotgun" then
							delay = wep.FireDelay * 1.2
							burst = 1
							if dist > 800 then aim = true end
						elseif typ == "machine_gun" then
							delay = wep.FireDelay * 3
							burst = math.random(10, 20)
							if dist > 1500 then aim = true end
							if dist < 800 then delay = 0 end
						elseif typ == "melee" then
							delay = wep.FireDelay
							burst = 1
							aim = false
						end

						if delay == 0 or (self.BurstLeft > 0 and (self.NextBurst or 0) < CurTime()) then
							self.NextBurst = nil
							self.BurstLeft = self.BurstLeft - engine.TickInterval()
							cmd:SetButtons(cmd:GetButtons() + IN_ATTACK)
						else
							self.NextBurst = self.NextBurst or (CurTime() + delay)
							self.BurstLeft = burst * wep.FireDelay
						end

						if aim then
							cmd:SetButtons(cmd:GetButtons() + IN_ATTACK2)
						end
					end

					--[[
					if IsValid(self:GetActiveWeapon()) and self:GetActiveWeapon().Primary and self:GetActiveWeapon().Primary.Automatic ~= true then
						if (self.NextFireSemi or 0) < CurTime() then
							self.NextFireSemi = CurTime() + 0.2
							cmd:SetButtons(cmd:GetButtons() + IN_ATTACK)
						end
					else
						cmd:SetButtons(cmd:GetButtons() + IN_ATTACK)
					end
					]]
				end
				break
			end
		end
	end
end