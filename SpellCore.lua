---@diagnostic disable: undefined-global, undefined-doc-name, undefined-field
---@class SpellCore
local spellcore = {}

-- check version --
local function check_version()
	local _, _, major, minor, patch = string.find(client:getFiguraVersion(), "(%d)%p(%d)%p(%d)")
	if tonumber(minor) < 1 then
		return false
	elseif tonumber(patch) < 5 then
		return false
	end
	return true
end

assert(check_version(), '\n \n SpellCore requires Figura v0.1.5+.\n Your version: '..client:getFiguraVersion()..'\n Update required. \n')

spellcore.projectiles = {} -- Contains all projectiles
local playerUUID = {}
local timers = {}
local playerReachDistance = 6

local explosionsRadius = {} -- DB
explosionsRadius['minecraft:potion'] = vec(4.125,2.125,4.125)
explosionsRadius['minecraft:fireball'] = vec(0.75,0.75,0.75)
explosionsRadius['minecraft:wind_charge'] = vec(2.6,2.6,2.6)
explosionsRadius['minecraft:firework_rocket'] = vec(5,5,5) -- wind_charge mb not 2.6 but 1.3, firework mb not 5 but 2.5

---------------------- HELPFUL FUNCTIONS ----------------------------------------------------------------------------------

---Converts a UUID string into a table of 4 decimal numbers for comparison
---@param UUID string
---@return table
local function convert_UUID(UUID)
	local UUIDtable = {}
	UUIDtable[1] = (tonumber(UUID:sub(1,8),16)+2^31)%2^32-2^31
	UUIDtable[2] = (tonumber(UUID:sub(10,13)..UUID:sub(15,18),16)+2^31)%2^32-2^31
	UUIDtable[3] = (tonumber(UUID:sub(20,23)..UUID:sub(25,28),16)+2^31)%2^32-2^31
	UUIDtable[4] = (tonumber(UUID:sub(29,36),16)+2^31)%2^32-2^31
	return(UUIDtable)
end

function pings.setReachDistance(v)
	playerReachDistance = math.max(v, 6)
end
pings.setReachDistance(host:getReachDistance())

---Initializes player UUID on entity initialization
function events.ENTITY_INIT()
	playerUUID = convert_UUID(player:getUUID())
end

---Compares UUID with player's UUID to determine ownership
---@param UUID table
---@return boolean
local function compareOwnerUUID(UUID)
	return UUID and (UUID[1] == playerUUID[1]) and (UUID[2] == playerUUID[2]) and (UUID[3] == playerUUID[3]) and (UUID[4] == playerUUID[4])
end

---Expands a zone defined by two vectors by a specified amount in all directions
---@param vec1 Vector3
---@param vec2 Vector3
---@param vecE Vector3
---@return Vector3, Vector3
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

---Creates a timer that runs a `func` every tick for the specified `duration`
---@param duration integer -- number of ticks the timer should run
---@param func function -- function to execute every tick. Receives the timer `table` as a parameter. Use `timer.time_left` to check how many ticks remain.
---@param name string|nil -- (optional) string key for the timer. Useful to prevent creating duplicate timers.
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

---Gets the last position of an entity by raycasting its velocity
---@param entity EntityAPI
---@return Vector3, Block
local function getLastPos(entity)
	local pos = entity:getPos()
	local pos2 = pos:copy():add(entity:getVelocity():mul(3,3,3))
	local block, hitPos = raycast:block(pos, pos2)
	return hitPos, block
end

------------------------------- GET ENTITY HIT BY PROJECTILE --------------------------

---Performs raycast to detect entities hit by projectile
---@param data table
---@param multiplier number|nil
---@return EntityAPI|nil, Vector3|nil
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
		elseif i==3 then startPos.y = startPos.y + box.y
		elseif i==4 then startPos.x = startPos.x - box.x
		elseif i==5 then startPos.z = startPos.z + box.z
		elseif i==6 then startPos.y = startPos.y - box.y
		elseif i==7 then startPos.x = startPos.x + box.x
		elseif i==8 then startPos.y = startPos.y + box.y
		else return nil
		end

	end
end

------------------------------- PROJECTILE CLASS ---------------------------------------

local Projectile = {}
Projectile.__index = Projectile

-- Permanent info

---Returns the name of the spell this projectile belongs to
---@return string
function Projectile:getSpellName()
	return self.__data.spellName
end

---Returns the EntityAPI object of the projectile
---@return EntityAPI
function Projectile:getEntity()
	return self.__data.entity
end

-- Status

---Returns true if the projectile has just been created/initialized
---@return boolean
function Projectile:isNew()
	return self.__data.isNew
end

---Returns true only on the first tick when the projectile becomes stuck
---@return boolean
function Projectile:isJustStuck()
	return self.__data.isJustStuck
end

---Returns true if the projectile is currently stuck in a block or entity
---@return boolean
function Projectile:isStuck()
	return self.__data.isStuck
end

---Returns true if the projectile is stuck in an entity
---@return boolean
function Projectile:hasHitEntity()
	return self.__data.inEntity
end

-- Miscellaneous

---Returns the last known impact position of the projectile
---@param delta number|nil
---@return Vector3
function Projectile:getLastPos(delta)
	if delta and self.__data.lastPos then
		return math.lerp(self.__data.entity:getPos(), self.__data.lastPos, delta)
	end
	return self.__data.lastPos or self.__data.entity:getPos(delta)
end

---Returns the entity this projectile is stuck in, or nil if it didn't hit an entity
---@return EntityAPI|nil
function Projectile:getHitEntity()
	return self.__data.hitEntity
end

---Returns a table of all entities affected by this projectile
---@return table
function Projectile:getAffectedEntities()
	return self.__data.affectedEntities
end

---Returns a table containing the world time when each affected entity was last affected
---@return table
function Projectile:getAffectedEntitiesTimes()
	return self.__data.affectedEntitiesTimes
end

---Double inheritance metatable function to access both Projectile and EntityAPI methods
---@param table table
---@param key string
---@return any
local function double_inheritance(table, key)
	if Projectile[key] then return Projectile[key]
	elseif table.__data.entity[key] then return function (_, ...) return table.__data.entity[key](table.__data.entity, ...) end
	else return nil
	end
end

------------------------------- GET ENTITIES AFFECTED/HIT BY PROJECTILE ---------------

---Gets entities affected by area effect cloud
---@param cloud table
---@return table
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

---Gets entities affected by explosion
---@param data table
---@param radius Vector3|nil
---@return table
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

---Default behavior for projectiles when they hit a block
---@param data table
local function projectile_else(data)
	local hitBlockPos, block = getLastPos(data.entity)
	if block.id ~= 'minecraft:air' then
		data.lastPos = hitBlockPos
		data.isJustStuck = true
		data.isStuck = true
	else
		data.exists = false
	end
end

---Behavior for arrows when they hit something
---@param data table
local function arrow_else(data)
	data.exists = false
end

---Exclusive behavior for regular arrows
---@param data table
local function excl_arrow(data)
	if (not data.isStuck) and (data.entity:getNbt().inGround == 1) then
		data.isJustStuck = true
		data.isStuck = true
	end
end

---Exclusive behavior for tridents (Work in Progress)
---@param data table
local function excl_trident(data)
	if data.inEntity then
		data.inEntity = false
		data.isStuck = false
	end

	excl_arrow(data)

	if not data.isStuck or data.isJustStuck then
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
			data.isJustStuck = true
			data.isStuck = true
		end
	end
end

---Exclusive behavior for piercing arrows
---@param data table
local function excl_pierce(data)
	excl_arrow(data)
	if not data.isStuck or data.isJustStuck then
		local vel = data.entity:getVelocity()
		local pos = data.entity:getPos()
		local bb = data.entity:getBoundingBox() / 2
		local pos1, pos2 = expandZone(pos, pos - vel, bb)
		for _, entity in ipairs(world.getEntities(pos1, pos2)) do
			if entity:getNbt().HurtTime and ((entity:getNbt().HurtTime >= 9) or (entity:getNbt().DeathTime > 0)) then
				data.affectedEntities[entity:getUUID()] = entity
				data.affectedEntitiesTimes[entity:getUUID()] = world.getTime()
			end
		end
	end
end

---Exclusive behavior for explosive projectiles
---@param data table
local function excl_explosive(data)
	if data.isJustStuck then
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

---Exclusive behavior for splash potions
---@param data table
local function excl_splash(data)
	if data.isJustStuck then
		data.affectedEntities = explosionAffected(data)
	end
end

---Changes projectile to area effect cloud for lingering potions
---@param data table
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

---Exclusive behavior for lingering potions
---@param data table
local function excl_lingering(data)
	if data.isJustStuck then
		changeToCloud(projectile)
	end
	if data.isStuck then
		for _, entity in ipairs(cloudAffected(projectile)) do
			data.affectedEntities[entity:getUUID()] = entity
			data.affectedEntitiesTimes[entity:getUUID()] = world.getTime()
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

Spell.__newindex = function (t, key, value)
	if key == 'conditions' and type(value) == 'string' then
		rawset(t, 'conditions', load('local entity = ... return '..value, 'conditions', 't'))
	else rawset(t, key, value)
	end
end

---Creates a new projectile object with the specified entity
---@param entity EntityAPI
---@return table
function Spell:newProjectile(entity)
	local projectile = setmetatable({}, {__index = double_inheritance})
	projectile.__data = {
		entity = entity,
		exists = true,
		isNew = true,
		isJustStuck = false,
		isStuck = false,
		inEntity = false,
		lastPos = nil,
		hitEntity = nil
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
			data.affectedEntitiesTimes = {}
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
			data.affectedEntitiesTimes = {}
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
---You can add functions after creating a spell. 
---Every lifecycle function receives the Projectile object as its first parameter.
---@param spellName string|nil A string name for your spell (e.g. `"Lumus"`, `"Zoltraak"`, `"Explosion"`). If omitted, a sequence number is used instead.
---@param conditions function|string|nil Determines whether a given projectile belongs to this spell. Can be a function (must return truthy or falsy value) or a string that evaluates to a truthy or falsy value. Recieves projectile entity as its first parameter.
---@param init function|nil Runs once when the projectile is initialized.
---@param inAir function|nil Runs every tick while the projectile is in midair.
---@param stuck function|nil Runs every tick while stuck in a block, or once if it hit an entity and disappeared. Use `projectile:isJustStuck()` to detect only the first tick.
---@param disappeared function|nil Runs once after the projectile has disappeared (picked up, despawned, unloaded, etc.).
---@param tick function|nil Runs every tick. Note: it runs after other lifecycle functions.
---@param render function|nil Runs before every frame in `events.RENDER`. Arguments: `projectile`, `delta`, `context`, `matrix` (right from events.RENDER).
---@return table
function spellcore.newSpell(spellName, conditions, init, inAir, stuck, disappeared, render, tick)
	if type(conditions) == 'string' then conditions = load('local entity = ... return '..conditions, 'conditions', 't') end
	local spell = setmetatable({
		spellName = spellName,
		conditions = conditions,
		init = init,
		inAir = inAir,
		stuck = stuck,
		disappeared = disappeared,
		tick = tick,
		render = render
	}, Spell)
	spell.__index = spell

	if spellName then spellcore.spells[spellName] = spell
	else table.insert(spellcore.spells, spell)
	end

	return spell
end

-- Default spell for projectiles that don't match any conditions
local noSpell = {spellName = 'no_spell'}
noSpell.__index = noSpell

---Creates a basic projectile object for entities that don't match any spell conditions
---@param entity EntityAPI
---@return table
function noSpell:newProjectile(entity)
	local projectile = setmetatable({__data = setmetatable({entity = entity}, noSpell)}, Projectile)
	return projectile
end

---Determines which spell applies to a given projectile entity
---@param projectileEntity EntityAPI
---@return table
local function define_spell(projectileEntity)
	for _, spell in pairs(spellcore.spells) do
		if spell.conditions(projectileEntity) then
			return spell
		end
	end
	return noSpell
end

------------------------------ DETECT NEW PROJECTILES FUNCTIONS -------------------------

---Detects new projectiles and adds them to the projectiles table
local function detect_new_projectile()
	local playerPos = player:getPos():add(0, 1.8, 0)
	local pos1 = playerPos - playerReachDistance
	local pos2 = playerPos + playerReachDistance
	local entities = world.getEntities(pos1, pos2)

	for _, entity in pairs(entities) do
		if entity:getNbt().HasBeenShot then
			local UUID = entity:getUUID()
			if (spellcore.projectiles[UUID] == nil) and compareOwnerUUID(entity:getNbt().Owner) then
				spellcore.projectiles[UUID] = define_spell(entity):newProjectile(entity)
			end
		end
	end
end

------------------------------ MAIN PROJECTILE FUNCTIONS ---------------------------------

---Updates projectile data including stuck status and entity hits
---@param projectile table
local function update_projectile_data(projectile)
	projectile.__data.isJustStuck = false
	if not projectile.__data.entity:isLoaded() and projectile.__data.exists then
		if projectile.__data.isStuck then
			projectile.__data.exists = false
		elseif not projectile.__data.inEntity then
			local hitEntity, hitPos = raycastEntity(projectile.__data)

			if hitEntity then
				projectile.__data.isJustStuck = true
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

---Main function for processing projectiles each tick
---@param projectile table
---@param UUID string
local function projectile_main(projectile, UUID)
	if projectile.__data.exists then
		if projectile.__data.isNew and projectile.__data.init then projectile.__data.init(projectile) end
		if projectile.__data.isStuck and projectile.__data.stuck then projectile.__data.stuck(projectile)
		elseif projectile.__data.inAir then projectile.__data.inAir(projectile) end
	else
		if projectile.__data.disappeared then projectile.__data.disappeared(projectile) end
		spellcore.projectiles[UUID] = nil
	end
	if projectile.__data.tick then projectile.__data.tick(projectile) end
	projectile.__data.isNew = false
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

	detect_new_projectile()

	-- projectiles tick
	for UUID, projectile in pairs(spellcore.projectiles) do
		if projectile.__data.spellName ~= 'no_spell' then
			update_projectile_data(projectile)
			projectile_main(projectile, UUID)
		elseif not projectile.__data.entity:isLoaded() then
			spellcore.projectiles[UUID] = nil
		end
	end
end

------------------------------- RENDER PROJECTILES ---------------------------------------

function events.RENDER(delta, context, matrix)
	for _, projectile in pairs(spellcore.projectiles) do
		if projectile.__data.render then projectile.__data.render(projectile, delta, context, matrix) end
	end
end

------------------------------- SOME FUNCTIONS YOU MIGHT NEED ----------------------------

---Returns a table of all currently registered spells
---@return table spellcore.spells A table of all currently registered spells. Keys are spell names (or sequence numbers if no name was given). Values are the corresponding `Spell` objects.
function spellcore.getSpells()
	return spellcore.spells
end

---Returns a table of all active projectiles
---@return table spellcore.projectiles A table of all active projectiles. Keys are projectile entity UUIDs. Values are the corresponding `Projectile` objects.
function spellcore.getProjectiles()
	return spellcore.projectiles
end

return spellcore

-- made by l_Rocka_l