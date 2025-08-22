---@diagnostic disable: undefined-global
---@class SpellCore
local spellcore = {}

spellcore.projectiles = {} -- Contains all projectiles
local playerUUID = {}
local timers = {}

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

local function expandZone(vec1, vec2, vecE)
	vec1 = vec1:copy()
	vec2 = vec2:copy()
	for _, c in ipairs({'x','y','z'}) do
		if vec1[c] > vec2[c] then
			vec1[c] = vec1[c] + vecE[c]
			vec2[c] = vec2[c] - vecE[c]
		else
			vec1[c] = vec1[c] - vecE[c]
			vec2[c] = vec2[c] + vecE[c]
		end
	end
	return vec1, vec2
end

---`func` will run every tick for `duration` timers
---@param duration integer -- in timers
---@param func function -- gets timer table as a parameter. for example: `timer.time_left = timer.time_left + 1` to control remaining time 
---@param name string|nil -- key of the timer. May be used to prevent duplicating timers
function spellcore.setTimer(duration, func, name)
	local tt = setmetatable({time_left = duration},{__call = func})
	if name then
		timers[name] = tt
	else
		table.insert(timers, tt)
	end
end

------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------- IMPORTANT FUNCTIONS -------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------

local function getLastPos(entity)
	local pos = entity:getPos()
	local pos2 = pos:copy():add(entity:getVelocity():mul(3,3,3))
	local block, hitPos = raycast:block(pos, pos2)
	return hitPos, block
end

------------------------------- GET ENTITY HIT BY PROJECTILE --------------------------

local function raycastEntity(data, multiplier)
	local entity = data.entity
	multiplier = multiplier or 2.5
	local box = entity:getBoundingBox():add(0.3,0.3,0.3):div(2,2,2)
	local startPos = entity:getPos():copy()
	local vel = entity:getVelocity():sub(0, 0.15, 0)

	if not(entity:getType():find('arrow')) then
		local linVel = vel:length()
		if linVel == 0.15 then
			vel = player:getLookDir():mul(3,3,3)
		elseif linVel < 2 then
			vel:mul(multiplier,multiplier,multiplier)
		end
	end

	for i = 1, 9 do
		local endPos = startPos:copy():add(vel)
		local entityHit, hitPos = raycast:entity(startPos, endPos, function(x)  -- x is the entity hit by the raycast
			local nbt = x:getNbt()
			return (nbt.HurtTime and ((nbt.HurtTime >= 9) or (nbt.DeathTime > 0))) or
					(entity:getType() == 'minecraft:potion' and x:getType() ~= 'minecraft:potion' and x:getType() ~='minecraft:area_effect_cloud')
		end)

		if entityHit then
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
------------------------------- PROJECTILE CLASS ---------------------------------------

local Projectile = {}
Projectile.__index = Projectile

function Projectile:getEntity()
	return self.__data.entity
end

function Projectile:getLastPos()
	return self.__data.lastPos or self.__data.entity:getPos()
end

function Projectile:justGotStuck()
	return self.__data.justGotStuck
end

function Projectile:getStuck()
	return self.__data.isStuck
end

function Projectile:isHitEntity()
	return self.__data.inEntity
end

function Projectile:isNew()
	return self.__data.isNew
end

function Projectile:getHitEntity()
	return self.__data.hitEntity
end

function Projectile:getAffectedEntities()
	return self.__data.affectedEntities
end

function Projectile:getAffectedTimePoints()
	return self.__data.affectedTimePoints
end

function Projectile:getSpellName()
	return self.__data.spellName
end

local function double_inheritance(table, key)
	if Projectile[key] then return Projectile[key]
	elseif table.__data.entity[key] then return function () return table.__data.entity[key](table.__data.entity) end
	else return nil
	end
end
------------------------------- GET ENTITIES AFFECTED/HIT BY PROJECTILE ---------------

local function cloudAffected(cloud)
    local bb = cloud.__data.entity:getBoundingBox() / 2
	local entities = {}
	for _, entity in pairs(world.getEntities(cloud.__data.lastPos - bb, cloud.__data.lastPos + bb)) do
		if ((entity:getPos() - cloud.__data.entity:getPos()):length() <= bb[1]) and (entity:getType() ~= 'minecraft:area_effect_cloud') then
			table.insert(entities, entity)
		end
	end
	return entities
end
local function explosionAffected(data, radius)
	radius = radius or explosionsRadius[data.entity:getType()]
	local entities = {}
	local lastPos = data.lastPos
	for _, entity in pairs(world.getEntities(lastPos:copy():sub(radius), lastPos:copy():add(radius))) do
		if (entity:getPos() - lastPos):length() <= radius[1] then
			table.insert(entities, entity)
		end
	end
	return entities
end

--------------------------------- DIFFERENT PROJs TYPE RELATED FUNCs -------------------

local function projectile_else(data)
	local hitBlockPos, block = getLastPos(data.entity)
	if block.id ~= 'minecraft:air' then
		data.lastPos = hitBlockPos
		data.justGotStuck = true
		data.isStuck = true
	else
		data.exists = false
	end
end
local function arrow_else(data)
	data.exists = false
end

local function excl_arrow(data)
	if (not data.isStuck) and (data.entity:getNbt().inGround == 1) then
		data.justGotStuck = true
		data.isStuck = true
	end
end
local function excl_trident(data) -- WIP
	if data.inEntity then
		data.inEntity = false
		data.isStuck = false
	end

	excl_arrow(data)

	if not data.isStuck or data.justGotStuck then
		local hitEntity = nil
		local vel = data.entity:getVelocity()
		local pos = data.entity:getPos()
		local bb = data.entity:getBoundingBox() / 2
		local pos1, pos2 = expandZone(pos, pos - vel, bb)
		for _, entity in ipairs(world.getEntities(pos1, pos2)) do
			if entity:getNbt().HurtTime and ((entity:getNbt().HurtTime >= 9) or (entity:getNbt().DeathTime > 0)) then
				hitEntity = entity
				break
			end
		end
		if hitEntity then
			data.hitEntity = hitEntity
			data.inEntity = true
			data.justGotStuck = true
			data.isStuck = true
		end
	end
end

local function excl_pierce(data)
	excl_arrow(data)
	if not data.isStuck or data.justGotStuck then

		local vel = data.entity:getVelocity()
		local pos = data.entity:getPos()
		local bb = data.entity:getBoundingBox() / 2
		local pos1, pos2 = expandZone(pos, pos - vel, bb)
		for _, entity in ipairs(world.getEntities(pos1, pos2)) do
			if entity:getNbt().HurtTime and ((entity:getNbt().HurtTime >= 9) or (entity:getNbt().DeathTime > 0)) then
				data.affectedEntities[entity:getUUID()] = entity
				data.affectedTimePoints[entity:getUUID()] = world.getTime()
			end
		end
	end
end
local function excl_explosive(data)
	if data.justGotStuck then
		if data.entity:getType() == 'minecraft:wind_charge' then
			data.affectedEntities = explosionAffected(data)
		else
			for _, entity in pairs(explosionAffected(data)) do
				if entity:getNbt().HurtTime >= 9 then
					data.affectedEntities[entity:getUUID()] = entity
				end
			end
		end
	end
end
local function excl_splash(data)
	if data.justGotStuck then
		data.affectedEntities = explosionAffected(data)
	end
end
local function changeToCloud(data)
	local startPos = data.entity:getPos():copy()
	local vel = data.entity:getVelocity()
	local cloud = raycast:entity(startPos, startPos + vel, function(x) 
		return x:getType() == 'minecraft:area_effect_cloud'
	end)

    if cloud then
        data.entity = cloud
    end
end
local function excl_lingering(data)
	if data.justGotStuck then
		changeToCloud(projectile)
	end
	if data.isStuck then
		for _, entity in ipairs(cloudAffected(projectile)) do
			data.affectedEntities[entity:getUUID()] = entity
			data.affectedTimePoints[entity:getUUID()] = world.getTime()
		end
	end
end
------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------- SPELL CLASS ----------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------

spellcore.spells = {} -- Contains all spells

local Spell = {}
Spell.__index = Spell

Spell.conditions = function () return false end

function Spell:newProjectile(entity)
	local projectile = setmetatable({}, {__index = double_inheritance})
	projectile.__data = {
		entity = entity,
		justGotStuck = false,
		isStuck = false,
		inEntity = false,
		isNew = true,
		exists = true,
		hitEntity = nil,
		lastPos = nil
	}
	local data = setmetatable(projectile.__data, self)

	-- Determining projectile type and behavior scenario --
	data.excl_else = projectile_else
	data.excl = function() end
	if entity:getType():find('arrow') then
		data.excl_else = arrow_else
		if entity:getNbt().PierceLevel == 0 then
			data.excl = excl_arrow
		else
			data.excl = excl_pierce
			data.affectedEntities = {}
			data.affectedTimePoints = {}
		end

	elseif entity:getType() == 'minecraft:trident' then
		data.excl_else = arrow_else
		data.excl = excl_trident

	elseif entity:getType() == 'minecraft:potion' then
		local id = entity:getNbt().Item.id
		if id == 'minecraft:splash_potion' then
			data.excl = excl_splash
			data.affectedEntities = {}
		elseif id == 'minecraft:lingering_potion' then
			data.excl = excl_lingering
			data.affectedEntities = {}
			data.affectedTimePoints = {}
		end

	elseif entity:getType() == 'minecraft:firework_rocket'
	or entity:getType() == 'minecraft:fireball'
	or entity:getType() == 'minecraft:wind_charge' then
		data.excl = excl_explosive
		data.affectedEntities = {}
	end

	return projectile
end



---Create your own new spell!
---All functions have projectile object (`self`) as first argument
---@param spellName string|nil Name your spell. For example "Lumus", "Zoltraak" or "EXPLOSION" or leave it empty, it doesn't really matter.
---@param conditions function|string|nil gets entity, which is projectile, as a parameter. Using "conditions", SpellCore determines which spell this projectile is. Have to return `true` or `false`(when function). Or if it is a string, it have to be the boolean, for example `'player:isCrouching() and (world.getMoonPhase() == 1)'`
---@param projectile_init function|nil Runs when projectile initializes
---@param projectile_in_air function|nil Runs every tick while projectile in midair
---@param projectile_stuck function|nil Runs every tick while projectile stuck in ground or runs once when hit the entity and disappeared. To run once use condition: self.justGotStuck
---@param projectile_disappeared function|nil Runs once projectile disappeared(no longer loaded), for example when picked up, went out of render distance, despawned, hit mob etc.
---@param render function|nil This function runs in events.RENDER. First arg is `projectile` object, second is `delta`.
---@param tick function|nil This function runs every TICK
---@return table
function spellcore:newSpell(spellName, conditions, projectile_init, projectile_in_air, projectile_stuck, projectile_disappeared, render, tick)
	if type(conditions) == 'string' then conditions = load('local entity = ... return '..conditions) end
	local spell = setmetatable({
		spellName = spellName,
		conditions = conditions,
		projectile_init = projectile_init,
		projectile_in_air = projectile_in_air,
		projectile_stuck = projectile_stuck,
		projectile_disappeared = projectile_disappeared,
		render = render,
		tick = tick
	}, Spell)
	spell.__index = spell

	if spellName then self.spells[spellName] = spell
	else table.insert(self.spells, spell)
	end

	return spell
end

local noSpell = {spellName = 'no_spell'}
noSpell.__index = noSpell
function noSpell:newProjectile(entity)
	local projectile = setmetatable({__data = setmetatable({entity = entity}, noSpell)}, Projectile)
	return projectile
end

local function define_spell(projectileEntity)
	for _, spell in pairs(spellcore.spells) do
		if spell.conditions(projectileEntity) then
			return spell
		end
	end
	return noSpell
end


------------------------------ DETECT NEW PROJECTILES FUNCTIONS -------------------------

local function detect_new_arrow(arrow)
	local UUID = arrow:getUUID()
	if spellcore.projectiles[UUID] == nil and arrow:isLoaded() and player:isLoaded() then
		local UUID = arrow:getUUID()
		local distance = getDistance(player:getPos(), arrow:getPos())
		if distance < 10 and arrow:getNbt().inGround == 0 then spellcore.projectiles[UUID] = define_spell(arrow):newProjectile(arrow)
		else spellcore.projectiles[UUID] = NoSpell:newProjectile(arrow)
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
			if spellcore.projectiles[UUID] == nil then
				spellcore.projectiles[UUID] = define_spell(entity):newProjectile(entity)
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
	spellcore.setTimer(2, function(timer)
			if useItemKey:isPressed() then
				timer.time_left = 1
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
	projectile.__data.justGotStuck = false
	if not projectile.__data.entity:isLoaded() and projectile.__data.exists then
		if projectile.__data.isStuck then
			projectile.__data.exists = false
		elseif not projectile.__data.inEntity then
			local hitEntity, hitPos = raycastEntity(projectile.__data)

			if hitEntity then
				projectile.__data.justGotStuck = true
				projectile.__data.isStuck = true
				projectile.__data.inEntity = true
				projectile.__data.lastPos = hitPos
				projectile.__data.hitEntity = hitEntity
			else
				projectile.__data:excl_else()
			end
		end
	end
	projectile.__data:excl()
end

local function projectile_main(projectile, UUID)
	if projectile.__data.exists then
		if projectile.__data.isNew then
			projectile.__data.isNew = false
			if projectile.__data.projectile_init then projectile.__data.projectile_init(projectile) end
		end
		if projectile.__data.isStuck then
			if projectile.__data.projectile_stuck then projectile.__data.projectile_stuck(projectile) end
		elseif projectile.__data.projectile_in_air then projectile.__data.projectile_in_air(projectile) end
	else
		if projectile.__data.projectile_disappeared then projectile.__data.projectile_disappeared(projectile) end
		spellcore.projectiles[UUID] = nil
	end
end

--------------------------------- TICK UPDATE -------------------------------------------

function events.TICK()
	-- timer update
	for key, func in pairs(timers) do
		if func.time_left == 0 then
			timers[key] = nil
		else
			func.time_left = func.time_left - 1
			func()
		end
	end

	-- projectiles tick
	for UUID, projectile in pairs(spellcore.projectiles) do
		if projectile.__data.spellName ~= 'no_spell' then
			update_projectile_data(projectile)
			projectile_main(projectile, UUID)
			if projectile.__data.tick then projectile.__data.tick(projectile) end
		elseif not projectile.__data.entity:isLoaded() then
			spellcore.projectiles[UUID] = nil
		end
	end

end

------------------------------- RENDER PROJECTILES ---------------------------------------

function events.RENDER(delta)
	for _, projectile in pairs(spellcore.projectiles) do
		if projectile.__data.render then projectile.__data.render(projectile, delta) end
	end
end

------------------------------- SOME FUNCTIONS YOU MIGHT NEED ----------------------------
---@return table spellcore.spells A table that contains all the spells. You might need it, so here it is.
function spellcore:getSpells()
	return self.spells
end

---@return table spellcore.projectiles A table that contains all the projectiles' objects. Projectiles are values, their entity UUIDs are keys.
function spellcore:getProjectiles()
	return self.projectiles
end


return spellcore
-- made by l_Rocka_l