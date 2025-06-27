---@diagnostic disable: undefined-global
---@class SpellAPI
local spellapi = {}

-- local spellbook = nil
-- for _, fileName in ipairs(listFiles('/')) do
-- 	if fileName == 'SpellBook' then spellbook = require(fileName) end
-- end

spellapi.projectiles = {} -- Contains all projectiles
local playerUUID = {}
local ticks = {}

local explosionsRadius = {} -- DB
explosionsRadius['minecraft:potion'] = vec(4.125,2.125,4.125)
explosionsRadius['minecraft:fireball'] = vec(0.75,0.75,0.75)
explosionsRadius['minecraft:wind_charge'] = vec(2.6,2.6,2.6)
explosionsRadius['minecraft:firework_rocket'] = vec(5,5,5) -- wind_charge mb not 2.6 but 1.3, firework mb not 5 but 2.5


---------------------- HELPFUL FUNCTIONS ----------------------------------------------------------------------------------

local function getDistance(pos1, pos2)
	return pos1:sub(pos2):length()
end

-- Define player UUID and convert it to 4 decimal numbers. It is needed to compare with projectile owner's UUID
local function convert_UUID(UUID)
	local UUIDtable = {}
	UUIDtable[1] = (tonumber(UUID:sub(1,8),16)+2^31)%2^32-2^31
	UUIDtable[2] = (tonumber(UUID:sub(10,13)..UUID:sub(15,18),16)+2^31)%2^32-2^31
	UUIDtable[3] = (tonumber(UUID:sub(20,23)..UUID:sub(25,28),16)+2^31)%2^32-2^31
	UUIDtable[4] = (tonumber(UUID:sub(29,36),16)+2^31)%2^32-2^31
	return(UUIDtable)
end

function events.ENTITY_INIT()
	playerUUID = convert_UUID(player:getUUID())
end

local function compareOwnerUUID(UUID)
	return UUID and (UUID[1] == playerUUID[1]) and (UUID[2] == playerUUID[2]) and (UUID[3] == playerUUID[3]) and (UUID[4] == playerUUID[4])
end

---`func` will run every tick for `duration` ticks
---@param func function -- may get self as a parameter. for example: self.timer = self.timer + 1 will make function run 1 tick longer 
---@param duration integer -- in ticks
---@param name string|nil -- key of the timer. May be used to prevent duplicating timers
local function setTimer(duration, func, name)
	local tt = setmetatable({timer = duration},{__call = func})
	if name then
		ticks[name] = tt
	else
		table.insert(ticks, tt)
	end
end

------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------- IMPORTANT FUNCTIONS -------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------

local function getLastPos(entity)
	local pos = entity:getPos()
	local pos2 = pos:copy():add(entity:getVelocity():mul(3,3,3))
	local block, hitPos = raycast:block(pos, pos2)
	-- setTimer(1000, function ()
	-- 	particles:newParticle("dust 1 1 1 1", hitPos)
	-- end)
	return hitPos, block
end
-- local function is_potion_affected(entity, potion_entity)
-- 	local potion_contents = potion_entity:getNbt().Item.components['minecraft:potion_contents']
-- 	if potion_contents.custom_effects then
-- 		potion_contents = potion_contents.custom_effects
-- 		for _, effect in pairs(potion_contents) do
-- 			local In = false
-- 			for _, active_effect in pairs(entity:getNbt().active_effects) do
-- 				if active_effect.id == effect.id then
-- 					In = true
-- 					break
-- 				end
-- 			end
-- 			if not In then
-- 				return false
-- 			end
-- 		end
-- 		return true
-- 	else
-- 		local effectId = string.gsub(string.gsub(potion_contents.potion, 'long_', ''), 'strong_', '') 
-- 		for _, active_effect in pairs(entity:getNbt().active_effects) do
-- 			if active_effect.id == effectId then
-- 				return true
-- 			end
-- 		end
-- 		return false
-- 	end
-- end

------------------------------- GET ENTITY HIT BY PROJECTILE --------------------------

local function raycastEntity(projectile, multiplier)
	multiplier = multiplier or 2.5
	local box = projectile.entity:getBoundingBox():add(0.3,0.3,0.3):div(2,2,2)
--db
	-- setTimer(1000, function ()
	-- 	particles:newParticle("dust 0 1 1 1", projectile.entity:getPos())
	-- end)

	local startPos = projectile.entity:getPos():copy()
	local vel = projectile.entity:getVelocity():sub(0, 0.15, 0)

	if not(projectile.entity:getType():find('arrow')) then
		local linVel = vel:length()
		if linVel == 0.15 then
			vel = player:getLookDir():mul(3,3,3)
		elseif linVel < 2 then
			vel:mul(multiplier,multiplier,multiplier)
		end
	end

	for i = 1, 9 do
		local endPos = startPos:copy():add(vel)
--db
		-- setTimer(1000, function ()
		-- 	particles:newParticle("dust 1 0 1 1", endPos)
		-- end)

		local entityHit, hitPos = raycast:entity(startPos, endPos, function(x)  -- x is the entity hit by the raycast
			return not(x:getType() == projectile.entity:getType() or --[[x:getNbt().HasBeenShot or]] x:getType() == projectile.exception)         -- if the entity hit is the player or projectile don't include the player or projectile in the results
		end)
		if entityHit and ((entityHit:getNbt().HurtTime >= 8) or projectile.entity:getType() == 'minecraft:potion') then
			return entityHit, hitPos
		end

		if i==1 then startPos:sub(box)
		elseif i==2 then box:mul(2,2,2) startPos:add(box.x, 0, 0)
		elseif i==3 then startPos.y = startPos.y + box.y--:add(0, box.y, 0)
		elseif i==4 then startPos.x = startPos.x - box.x--:sub(box.x, 0, 0)
		elseif i==5 then startPos.z = startPos.z + box.z--:add(0, 0, box.z)
		elseif i==6 then startPos.y = startPos.y - box.y--:sub(0, box.y, 0)
		elseif i==7 then startPos.x = startPos.x + box.x--:add(box.x, 0, 0)
		elseif i==8 then startPos.y = startPos.y + box.y--:add(0, box.y, 0)
		else return nil
		end

	end
end

------------------------------- GET ENTITIES AFFECTED/HITTED BY PROJECTILE ------------
---
local function cloudAffected(cloud)
    local bb = cloud.entity:getBoundingBox():div(2, 2, 2)
	local entities = {}
	for _, entity in pairs(world.getEntities(cloud.lastPos:copy():sub(bb), cloud.lastPos:copy():add(bb))) do
		if (entity:getPos() - cloud.getPos()):length() <= bb[1] then
			table.insert(entities, entity)
		end
	end
	return entities
end
local function explosionAffected(projectile, radius)
	radius = radius or explosionsRadius[projectile.entity:getType()]--[[ or 4.125]]
	local entities = {}
	for _, entity in pairs(world.getEntities(projectile.lastPos:copy():sub(radius), projectile.lastPos:copy():add(radius))) do
		if (entity:getPos() - projectile.lastPos):length() <= radius[1] then
			table.insert(entities, entity)
		end
	end
	return entities 
end

--------------------------------- DIFFERENT PROJs TYPE RELATED FUNCs -------------------

local function projectile_else(projectile)
	local hitBlockPos, block = getLastPos(projectile.entity)
	if block.id ~= 'minecraft:air' then
		projectile.lastPos = hitBlockPos
		projectile.justGotStuck = true
		projectile.isStuck = true
	else
		projectile.exists = false
	end
end
local function arrow_else(projectile)
	projectile.exists = false
end

local function excl_arrow(projectile)
	if (not projectile.isStuck) and (projectile.entity:getNbt().inGround == 1) then
		projectile.justGotStuck = true
		projectile.isStuck = true
	end
end
local function excl_trident(projectile)
	if projectile.inEntity then
		projectile.inEntity = false
		projectile.isStuck = false
	end
	if (not projectile.isStuck) and (projectile.entity:getNbt().inGround == 1) then
		projectile.justGotStuck = true
		projectile.isStuck = true
	end

	local norm = projectile.entity:getVelocity():normalized()
	local prevnorm = (projectile.prevVelocity or vec(0,0,0)):normalized()

	if not(projectile.isNew or projectile.isStuck) and 
	(norm.x * prevnorm.x <= 0) and
	(norm.z * prevnorm.z <= 0) then
		local entity  = raycastEntity(projectile, -2)
		projectile.hitEntity = entity
		projectile.inEntity = true
		projectile.justGotStuck = true
		projectile.isStuck = true
	end

	projectile.prevVelocity = projectile.entity:getVelocity()

end
local function excl_pierce(projectile)
	excl_arrow(projectile)
	if not projectile.isStuck or projectile.justGotStuck then
		local vel = projectile.entity:getVelocity()
		local bb = projectile.entity:getBoundingBox():copy() / 2
		local pos = projectile.entity:getPos()
		local pos1 = pos - bb
		local pos2 = (pos - vel) + bb
		for _, entity in ipairs(world.getEntities(pos1, pos2)) do
			if entity:getNbt().HurtTime == 9 then
				projectile.affectedEntities[entity:getUUID()] = entity
			end
		end
	end
end
local function excl_explosive(projectile)
	if projectile.justGotStuck then
		if projectile.entity:getType() == 'minecraft:wind_charge' then
			projectile.affectedEntities = explosionAffected(projectile)
		else
			for _, entity in pairs(explosionAffected(projectile)) do
				if entity:getNbt().HurtTime == 9 then
					projectile.affectedEntities[entity:getUUID()] = entity
				end
			end
		end
	end
end
local function excl_splash(projectile)
	if projectile.justGotStuck then
		projectile.affectedEntities = explosionAffected(projectile)
		-- for _, entity in pairs(explosionAffected(projectile)) do
		-- 	if is_potion_affected(entity, projectile.entity) then
		-- 		projectile.affectedEntities[entity:getUUID()] = entity
		-- 	end
		-- end
	end
end
local function changeToCloud(projectile)
	local startPos = projectile.entity:getPos():copy()
	local vel = projectile.entity:getVelocity()
	local cloud = raycast:entity(startPos, startPos + vel, function(x) 
		return x:getType() == 'minecraft:area_effect_cloud'
	end)

    if cloud then
        projectile.entity = cloud
    end
end
local function excl_lingering(projectile)
	if projectile.justGotStuck then
		changeToCloud(projectile)
	end
	if projectile.isStuck then
		for _, entity in ipairs(cloudAffected(projectile)) do
			-- if is_potion_affected(entity, projectile.entity) then
			if entity:getType() ~= 'minecraft:area_effect_cloud' then
				projectile.affectedEntities[entity:getUUID()] = entity				
			end
			-- end
		end
	end
end
------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------- SPELL CLASS ----------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------
spellapi.spells = {} -- Contains all spells

---Create your own new spell!
---All functions have projectile object (`self`) as first argument
---@param spellName string|nil Name your spell. For example "Lumus", "Zoltraak" or "EXPLOSION" or leave it empty, it doesn't really matter.
---@param conditions function|nil gets entity, which is projectile, as a parameter. Using "conditions", SpellApi determines which spell this projectile is. Have to return True or False 
---@param projectile_init function|nil Runs when projectile initializes
---@param projectile_in_air function|nil Runs every tick while projectile in midair
---@param projectile_stuck function|nil Runs every tick while projectile stuck in ground or runs once when hit the entity and disappeared. To run once use condition: self.justGotStuck
---@param projectile_disappeared function|nil Runs once projectile disappeared(no longer loaded), for example when picked up, went out of render distance, despawned, hit mob etc.
---@param render function|nil This function runs in events.RENDER. First arg is `projectile` object, second is `delta`.
---@param tick function|nil This function runs every TICK
---@return table
function spellapi:newSpell(spellName, conditions, projectile_init, projectile_in_air, projectile_stuck, projectile_disappeared, render, tick)
	local newspell = {
		spellName = spellName,
		conditions = conditions or function () return false end,
		projectile_init = projectile_init,
		projectile_in_air = projectile_in_air,
		projectile_stuck = projectile_stuck,
		projectile_disappeared = projectile_disappeared,
		render = render,
		tick = tick
	}
	function newspell:newProjectile(entity)
		local projectileData = {
			entity = entity,
			justGotStuck = false,
			isStuck = false,
			inEntity = false,
			isNew = true,
			exists = true,
			hitEntity = nil,
			affectedEntities = {},
			lastPos = nil,	
			isPotion = false
		}

		newspell.excl_else = projectile_else
		newspell.excl = function() end
		if entity:getType():find('arrow') then
			newspell.excl_else = arrow_else
			if entity:getNbt().PierceLevel == 0 then
				newspell.excl = excl_arrow
			else
				newspell.excl = excl_pierce
			end

		elseif entity:getType() == 'minecraft:trident' then
			newspell.excl_else = arrow_else
			newspell.excl = excl_trident

		elseif entity:getType() == 'minecraft:potion' then
			local id = entity:getNbt().Item.id
			if id == 'minecraft:splash_potion' then
				newspell.excl = excl_splash
			elseif id == 'minecraft:lingering_potion' then
				newspell.excl = excl_lingering
				newspell.exception = 'minecraft:area_effect_cloud'
			end

		elseif entity:getType() == 'minecraft:firework_rocket'
		or entity:getType() == 'minecraft:fireball'
		or entity:getType() == 'minecraft:wind_charge' then
			newspell.excl = excl_explosive
		end

		local function search(table, key)
			if self[key] then
				return self[key]
			elseif entity[key] then
				return function () return entity[key](entity) end
			else
				return nil
			end
		end

		setmetatable(projectileData, {__index = search})
		return projectileData
	end

	function newspell:getEntity()
		return self.entity
	end

	function newspell:getLastPos()
		return self.lastPos or self.entity:getPos()
	end

	if spellName then
		self.spells[spellName] = newspell
	else
		table.insert(self.spells, newspell)
	end
	return newspell
end

local noSpell = spellapi:newSpell('NoSpell')
spellapi.spells.NoSpell = nil

local function define_spell(projectileEntity)
	for _, spell in pairs(spellapi.spells) do
		if spell.conditions(projectileEntity) then
			return spell
		end
	end
	return noSpell
end


------------------------------ DETECT NEW PROJECTILES FUNCTIONS -------------------------

local function detect_new_arrow(arrow)
	local UUID = arrow:getUUID()
	if spellapi.projectiles[UUID] == nil and arrow:isLoaded() and player:isLoaded() then
		local UUID = arrow:getUUID()
		local distance = getDistance(player:getPos(), arrow:getPos())
		if distance < 10 then spellapi.projectiles[UUID] = define_spell(arrow):newProjectile(arrow)
		elseif distance >= 10 then spellapi.projectiles[UUID] = noSpell:newProjectile(arrow)
		end
	end
end

local function detect_new_projectile()
	local playerPos = player:getPos():add(0, player:getEyeHeight(), 0)
	local pos1 = playerPos:copy():sub(3, 3, 3)
	local pos2 = playerPos:copy():add(3, 3, 3)

	local entities = world.getEntities(pos1, pos2)

	for _, entity in pairs(entities) do
		if entity:getNbt().HasBeenShot and compareOwnerUUID(entity:getNbt().Owner) then
			local UUID = entity:getUUID()
			if spellapi.projectiles[UUID] == nil then
				spellapi.projectiles[UUID] = define_spell(entity):newProjectile(entity)
			end
		end
	end
end

------------------------------- DETECT NEW PROJECTILES ----------------------------------
-- detect arrow and trident --
function events.ARROW_RENDER(_, arrow)
	detect_new_arrow(arrow)

end

function events.TRIDENT_RENDER(_, trident)
	detect_new_arrow(trident)
end

-- detect projectile --
local useItemKey = keybinds:fromVanilla("key.use")

function pings.useItemKeyPressed()
	setTimer(2, function(self)
			if useItemKey:isPressed() then
				self.timer = 1
			end
			detect_new_projectile()
		end, 'pressed')
end

useItemKey.press =
	function()
		pings.useItemKeyPressed()
	end


------------------------------ MAIN PROJECTILE FUNCTIONS ---------------------------------

local function update_projectile_data(projectile)
	projectile.justGotStuck = false
	if not (projectile.entity:isLoaded()--[[ or world.getEntity(UUID)]]) and projectile.exists then                -- I should try with   not projectile.entity:isLoaded()  and compare
		if projectile.isStuck then
			projectile.exists = false
		elseif not projectile.inEntity then
			local hitEntity, hitPos = raycastEntity(projectile)

			if hitEntity then
				projectile.justGotStuck = true
				projectile.isStuck = true
				projectile.inEntity = true
				projectile.lastPos = hitPos
				projectile.hitEntity = hitEntity
			else
				projectile:excl_else()
			end
		end
	end
	projectile:excl()
end

local function projectile_main(projectile, UUID)
	if projectile.exists then
		if projectile.isNew then
			projectile.isNew = false
			if projectile.projectile_init then projectile:projectile_init() end
		end
		if projectile.isStuck then
			if projectile.projectile_stuck then projectile:projectile_stuck() end
		elseif projectile.projectile_in_air then projectile:projectile_in_air() end
	else
		if projectile.projectile_disappeared then projectile:projectile_disappeared() end
		spellapi.projectiles[UUID] = nil
	end
end

--------------------------------- TICK UPDATE -------------------------------------------

function events.TICK()
	-- timer update
	for key, func in pairs(ticks) do
		if func.timer == 0 then
			ticks[key] = nil
		else
			func.timer = func.timer - 1
			func()
		end
	end

	-- projectiles tick
	for UUID, projectile in pairs(spellapi.projectiles) do
		update_projectile_data(projectile)
		projectile_main(projectile, UUID)
		if projectile.tick then projectile:tick() end
	end

end

------------------------------- RENDER PROJECTILES ---------------------------------------

function events.RENDER(delta)
	for _, projectile in pairs(spellapi.projectiles) do
		if projectile.render then projectile:render(delta) end
	end
end


------------------------------- SOME FUNCTIONS YOU MIGHT NEED ----------------------------
---@return table spellapi.spells A table that contains all the spells. You might need it, so here it is.
function spellapi:getSpells()
	return self.spells
end

---@return table spellapi.projectiles A table that contains all the projectiles' objects. Projectiles are values, their entity UUIDs are keys.
function spellapi:getProjectiles()
	return self.projectiles
end


return spellapi
-- made by l_Rocka_l