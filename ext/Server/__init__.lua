require "Settings"
require "Enums"
require "Vehicles"
local m_Timer = require "VehicleRestrictorTimer"

function shortVehicleName(longName)
	return longName:gsub(".+/.+/","")
end

class 'vehicleRestrictor'

function vehicleRestrictor:__init()
	print("Initializing VehicleRestrictor")
	self:RegisterHooks()
	self:RegisterEvents()
	print("Initialized VehicleRestrictor")
end


-- Setup hooks
function vehicleRestrictor:RegisterHooks()
	if Settings.TRIGGER == 2 then-- don't need to listen for damage events if we punish on entering
		Hooks:Install("Soldier:Damage", 999, self, self.OnPlayerDamage)	
	end
end

-- Setup event subscriptions
function vehicleRestrictor:RegisterEvents()
	Events:Subscribe('Player:Killed', self, self.OnPlayerKilled)
	Events:Subscribe('Player:Left', self, self.OnPlayerleft)
	
	if Settings.TRIGGER == 1 then
		Events:Subscribe("Vehicle:Enter", self, self.OnEnterVehicle)
	end

	Events:Subscribe("Vehicle:Exit", self, self.OnExitVehicle) 

	if Settings.TRIGGER == 2 then -- don't need to listen for damage events if we punish on entering
		Events:Subscribe("Vehicle:Damage", self, self.OnDamageVehicle)
	end
end


-- Enter vehicle event (ServerVehicleEntity, Player)
function vehicleRestrictor:OnEnterVehicle(vehicle, player)
	if Settings.DEBUG_LEVEL >= 3 then
		print("EnterVehicle Type: " .. vehicle.typeInfo.name)
	end
	
	local cVehicleData = VehicleEntityData(vehicle.data)
	local vehicleName = shortVehicleName(cVehicleData.controllableType)
	if Vehicles[vehicleName] == nil then
		print("MISSING VEHICLE INFO: '" .. vehicleName .."'")
		return
	end
	if Settings.DEBUG_LEVEL >= 2 then
		print("Player " .. player.name .. " (".. TeamNames[player.teamId] .. ") entered vehicle " .. vehicleName .. " (".. TeamNames[Vehicles[vehicleName].Team] ..")")
	end
	if Settings.TRIGGER == 1 and Vehicles[vehicleName].Team ~= 0 and Vehicles[vehicleName].Team ~= player.teamId then	
		vehicleRestrictor:handleSteal(player, vehicle)
	end
end

-- Exit vehicle event (ServerVehicleEntity, Player)
function vehicleRestrictor:OnExitVehicle(vehicle, player)
	if(vehicle == nil) then 
		return
	end	
	
	if vehicle.typeInfo.name ~= "ServerVehicleEntity" then
		if Settings.DEBUG_LEVEL >= 3 then
			print("ExitVehicle Type: " .. vehicle.typeInfo.name)
		end
		return
	end
	
	local cVehicleData = VehicleEntityData(vehicle.data)
	local vehicleName = shortVehicleName(cVehicleData.controllableType)
	if Settings.DEBUG_LEVEL >= 2 then
		print("Player " .. player.name .. " (".. TeamNames[player.teamId] .. ") left vehicle " .. vehicleName .. " (".. TeamNames[Vehicles[vehicleName].Team] ..")")
	end
	m_Timer:Delete(player.guid:ToString("D")) -- remove possibly existing punishment timer
end

-- Player killed event (Player, player, Vec3, string, bool, bool, bool)
function vehicleRestrictor:OnPlayerKilled(player, inflictor, position, weapon, roadKill, headShot, victimInReviveState)
	if Settings.DEBUG_LEVEL >= 2 then
		print((inflictor and inflictor.name or player.name) .. " killed " .. player.name .. " with " .. weapon .. " (" .. (roadKill and "roadkill " or "") .. (headShot and "headshot" or "") .. ")")
	end
	m_Timer:Delete(player.guid:ToString("D")) 
end

-- player left, remove any potential timer
function vehicleRestrictor:OnPlayerleft(player)
	m_Timer:Delete(player.guid:ToString("D")) 
end


-- Event when vehicle health changes
function vehicleRestrictor:OnDamageVehicle(vehicle, damage, giverInfo)
	if damage < 0 or giverInfo == nil then -- negative damage = repair, or world damage
		return
	end
	local cGiverInfo = DamageGiverInfo(giverInfo)	
	if cGiverInfo.giverControllable ~= nil then -- check if damage source is controllable
		if Settings.DEBUG_LEVEL >= 3 then
			print("cGiverInfo.giverControllable: " .. Entity(cGiverInfo.giverControllable).typeInfo.name)
		end
		
		if Entity(cGiverInfo.giverControllable).typeInfo.name == "ServerVehicleEntity" then -- check if damage source is a vehicle
			local controllableVehicle = VehicleEntityData(cGiverInfo.giverControllable.data) 
			local vehicleName = shortVehicleName(controllableVehicle.controllableType)
			if Vehicles[vehicleName].Team ~= 0 and Vehicles[vehicleName].Team ~= cGiverInfo.giver.teamId then	
				vehicleRestrictor:handleSteal(cGiverInfo.giver, cGiverInfo.giverControllable)
				if Settings.DEBUG_LEVEL >= 1 then
					print("Player " .. cGiverInfo.giver.name .. " dealt damage with forbidden vehicle " .. vehicleName) 
				end
			end
		end
	end
end	
	


-- hook gets called when soldier HP changes
function vehicleRestrictor:OnPlayerDamage(hook, soldier, info, giverInfo)
	if info.damage < 0 or soldier.alive == false then -- negative damage = heal or player already dead
		return
	end
	
	local giverName = "world" 
	if giverInfo.giver ~= nil then -- If giver not set, damage source is world
		giverName = giverInfo.giver.name
	else -- return if world damage
		return
	end
		
	local cGiverInfo = DamageGiverInfo(giverInfo)
	
	if cGiverInfo.giverControllable ~= nil then -- check if damage source is controllable
		if Settings.DEBUG_LEVEL >= 3 then
			print("cGiverInfo.giverControllable: " .. Entity(cGiverInfo.giverControllable).typeInfo.name)
		end
		
		if Entity(cGiverInfo.giverControllable).typeInfo.name == "ServerVehicleEntity" then -- check if damage source is a vehicle
			local controllableVehicle = VehicleEntityData(cGiverInfo.giverControllable.data) 
			local vehicleName = shortVehicleName(controllableVehicle.controllableType)
			if Vehicles[vehicleName].Team ~= 0 and Vehicles[vehicleName].Team ~= cGiverInfo.giver.teamId then	
				vehicleRestrictor:handleSteal(cGiverInfo.giver, cGiverInfo.giverControllable)
				if Settings.DEBUG_LEVEL >= 1 then
					print("Player " .. cGiverInfo.giver.name .. " dealt damage with forbidden vehicle " .. vehicleName) 
				end
			end
		end
	end
end

-- Do punishment if a forbidden vehicle was detected
function vehicleRestrictor:handleSteal(player, vehicle)
	if Settings.DEBUG_LEVEL >= 3 then
		print("HandleSteal VehicleType: " .. vehicle.typeInfo.name)
	end

	local cVehicleData = VehicleEntityData(vehicle.data)
	local vehicleName = shortVehicleName(cVehicleData.controllableType)
	if Settings.DEBUG_LEVEL >= 1 then
		print("Player " .. player.name .. " used forbidden vehicle " .. vehicleName) 
	end
	
	-- Kill the player
	if Settings.PUNISHMENT_TYPE == 1 then
		local function killWrapper() return self:killPlayer(player) end
		local result = m_Timer:CreateDelay(player.guid:ToString("D"), Settings.DELAY, killWrapper)
		if result then
			if Settings.SHOW_WARNING then
				ChatManager:Yell("RESTRICTED VEHICLE: Get out or die in " .. string.format("%.0f",Settings.DELAY), Settings.DELAY, player)
			end
		end
	end
	
	-- Destroy Vehicle (and player in it)
	if Settings.PUNISHMENT_TYPE == 2 then
		local function destroyWrapper() return self:destroyVehicle(vehicle, player) end	
		local result = m_Timer:CreateDelay(player.guid:ToString("D"), Settings.DELAY, destroyWrapper)
		if result then
			if Settings.SHOW_WARNING then
				ChatManager:Yell("RESTRICTED VEHICLE: Get out or die in " .. string.format("%.0f",Settings.DELAY), Settings.DELAY, player)
			end
		end
	end

	-- Damage player over time
	if Settings.PUNISHMENT_TYPE == 3 then
		local function damageWrapper() return self:damagePlayer(player.soldier) end	
		local result = m_Timer:CreateInterval(player.guid:ToString("D"), Settings.DELAY, Settings.INTERVAL, damageWrapper)
		if result then
			if Settings.SHOW_WARNING then
				ChatManager:Yell("RESTRICTED VEHICLE: Get out or die", 100, player)
			end
		end
	end

	-- Damage Vehicle over time
	if Settings.PUNISHMENT_TYPE == 4 then
		local function damageWrapper() return self:damageVehicle(vehicle) end	
		local result = m_Timer:CreateInterval(player.guid:ToString("D"), Settings.DELAY, Settings.INTERVAL, damageWrapper)
		if result then
			if Settings.SHOW_WARNING then
				ChatManager:Yell("RESTRICTED VEHICLE: Get out or die", 100, player)
			end
		end
	end

	-- Kick player out of the vehicle
	if Settings.PUNISHMENT_TYPE == 5 then
		local function exitWrapper() return self:kickFromVehicle(player) end	
		m_Timer:CreateDelay(player.guid:ToString("D"), Settings.DELAY, exitWrapper)
	end
end

-- Kill a player by applying damage to it (much of it)
function vehicleRestrictor:killPlayer(player)
	if Settings.DEBUG_LEVEL >= 1 then
		print("Killing player " .. player.name)
	end
	
	local soldier = SoldierEntity(player.soldier)
	
	local damageInfo = DamageInfo()
    damageInfo.damage = soldier.maxHealth * 2 -- use twice the maximum health, just to be sure
    damageInfo.position = soldier.transform.trans
    damageInfo.direction = Vec3(0, 1, 0)
	damageInfo.shouldForceDamage = true
	damageInfo.isExplosionDamage = true
	soldier:ApplyDamage(damageInfo)
	
	print("Killed player " .. player.name .. " for using a restricted vehicle ")
	if(Settings.ANNOUNCE_IN_CHAT) then
		ChatManager:SendMessage("Killed " .. player.name .. " for using a restricted vehicle")
	end	
	return
end

-- destroy a vehicle by firing the "Destroy" event and destroying it if neccesary
function vehicleRestrictor:destroyVehicle(vehicle, player)
	local cVehicleData = VehicleEntityData(vehicle.data)
	local vehicleName = shortVehicleName(cVehicleData.controllableType)

	if Settings.DEBUG_LEVEL >= 2 then
		print("Destroying vehicle " .. vehicleName .." ("..vehicle.typeInfo.name..")")
	end
	
	vehicle:FireEvent("Destroy")
	if Settings.DEBUG_LEVEL >= 2 then
		print("Fired destroy event")
	end
	if vehicle ~= nil then -- In case vehicle is still alive after firing "Destroy" (like stationary AA), despawn it
		vehicle:Destroy()
		if Settings.DEBUG_LEVEL >= 2 then
			print("Distroyed entity")
		end
	end
	if player.hasSoldier and player.soldier ~= nil then -- kill player if he is still alive
		self:killPlayer(player)
	end
	print("Killed player " .. player.name .. " for using a restricted vehicle (" ..vehicleName .. "), destroyed vehicle")
	
	if(Settings.ANNOUNCE_IN_CHAT) then
		ChatManager:SendMessage("Killed " .. player.name .. " for using a restricted vehicle")
	end	
	return
end

-- apply damage to a vehicle
function vehicleRestrictor:damageVehicle(vehicle)
	if vehicle ~= nil and vehicle.typeInfo.name == "ServerVehicleEntity" then
		local cVehicleData = VehicleEntityData(vehicle.data)
		local damageInfo = DamageInfo()
		damageInfo.damage = cVehicleData.frontHealthZone.maxHealth * Settings.DAMAGE / 100
		damageInfo.direction = Vec3(0, 1, 0)
		damageInfo.shouldForceDamage = true
		damageInfo.isExplosionDamage = true
		PhysicsEntity(vehicle):ApplyDamage(damageInfo)
		if Settings.DEBUG_LEVEL >= 2 then
			print("Damaged vehicle")
		end
	end
end

-- apply damage to a player
function vehicleRestrictor:damagePlayer(soldier)
	if soldier ~= nil and soldier.isAlive then
		local damageInfo = DamageInfo()
		damageInfo.damage = soldier.maxHealth * Settings.DAMAGE / 100
		damageInfo.position = soldier.transform.trans
		damageInfo.direction = Vec3(0, 1, 0)
		damageInfo.shouldForceDamage = true
		damageInfo.isExplosionDamage = true
		soldier:ApplyDamage(damageInfo)
		if Settings.DEBUG_LEVEL >= 2 then
			print("Damaged player")
		end
	end

end

-- force a player to leave the current vehicle
function vehicleRestrictor:kickFromVehicle(player)
	if player.soldier ~= nil and player.soldier.isAlive then
		player:ExitVehicle(true, true)
		if Settings.DEBUG_LEVEL >= 1 then
			print("Kicked player out of vehicle")
		end
	end
end



g_vehicleRestrictor = vehicleRestrictor()

