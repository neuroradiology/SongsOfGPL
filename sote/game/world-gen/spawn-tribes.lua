local realm = require "game.entities.realm"
local cult = require "game.entities.culture"
local rel = require "game.entities.religion"
local pop = require "game.entities.pop"
local tabb = require "engine.table"

local TRAIT = require "game.raws.traits.generic"
local ranks = require "game.raws.ranks.character_ranks"

local pe = require "game.raws.effects.political"

local st = {}


---Makes a new realm, one province large.
---@param race Race
---@param capitol Province
---@param culture Culture
---@param faith Faith
local function make_new_realm(capitol, race, culture, faith)
	local r = realm.Realm:new()
	r.capitol = capitol
	r:add_province(capitol)
	r:explore(capitol)
	r.primary_race = race
	r.primary_culture = culture
	r.primary_faith = faith

	-- Initialize realm colors
	r.r = math.max(0, math.min(1, (culture.r + (love.math.random() * 0.4 - 0.2))))
	r.g = math.max(0, math.min(1, (culture.g + (love.math.random() * 0.4 - 0.2))))
	r.b = math.max(0, math.min(1, (culture.b + (love.math.random() * 0.4 - 0.2))))

	r.name = culture.language:get_random_realm_name()
	for _, neigh in pairs(capitol.neighbors) do
		r:explore(neigh)
	end

	-- Mark the province as settled for processing...
	WORLD:set_settled_province(capitol)

	-- We also need to spawn in some population...
	local pop_to_spawn = math.max(5, capitol.foragers_limit)
	for _ = 1, pop_to_spawn do
		local p = pop.POP:new(
			race,
			faith,
			culture,
			love.math.random() > race.males_per_hundred_females / (100 + race.males_per_hundred_females),
			love.math.random(race.max_age)
		)
		capitol:add_pop(p)
	end

	-- spawn leader
	local elite_character = pe.generate_new_noble(r, capitol, race, faith, culture)
	elite_character.popularity[r] = elite_character.age / 10
	r.leader = elite_character
	r.leader.rank = ranks.CHIEF

	-- spawn nobles
	for i = 1, pop_to_spawn / 5 + 1 do
		local contender = pe.generate_new_noble(r, capitol, race, faith, culture)
		contender.popularity[r] = contender.age / 15
	end

	-- set up capitol
	capitol.name = culture.language:get_random_province_name()
	capitol:research(RAWS_MANAGER.technologies_by_name['paleolithic-knowledge']) -- initialize technology...

	-- give some stuff to capitol
	capitol.infrastructure = love.math.random() * 10 + 10
	capitol.local_wealth = love.math.random() * 10 + 10
	capitol.trade_wealth = love.math.random() * 10 + 10

	-- give initial research budget
	r.budget.education.budget = 1

	-- starting treasury
	r.budget.treasury = love.math.random() * 20 + 100

	-- give some realms early tech advantage to reduce waiting:
	for i = 0, 2 do
		local n = tabb.size(capitol.technologies_researchable)
		if n > 0 then
			r.budget.education.budget = r.budget.education.budget + 1
			local i = love.math.random(n)
			---@type Technology
			local tech = tabb.nth(capitol.technologies_researchable, i)
			local probability = 0.1
			if love.math.random() < probability then
				capitol:research(tech)
			end
		end
	end


	-- print("test battle")
	-- local size_1, size_2 = love.math.random(50) + 10, love.math.random(50) + 10
	-- local army_1 = generate_test_army(size_1, race, faith, culture, capitol)
	-- local army_2 = generate_test_army(size_2, race, faith, culture, capitol)

	-- print(size_2, size_1)
	-- local victory, losses, def_losses = army_2:attack(capitol, true, army_1)
	-- print(victory, losses, def_losses)
end


---Checks if province is eligible for spawn
---@param race Race
---@param province Province
function ProvinceCheck(race, province)
	if not province.center.is_land then return false end
	if province.realm ~= nil then return false end
	if (not province.on_a_river) and race.requires_large_river then return false end
	if (not province.on_a_forest) and race.requires_large_forest then return false end
	local ja_r, ja_t, ju_r, ju_t = province.center:get_climate_data()
	if race.minimum_comfortable_temperature > (ja_t + ju_t) / 2 then return false end
	if race.minimum_absolute_temperature > ja_r then return false end
	local elev = province.center.elevation
	if race.minimum_comfortable_elevation > elev then return false end

	return true
end

---Spawns initial tribes and initializes their data (such as characters, cultures, religions, races, etc)
function st.run()
	---@type Queue<Province>
	local queue = require "engine.queue":new()
	local civs = 500 / tabb.size(RAWS_MANAGER.races_by_name) -- one per race...
	for _ = 1, civs do
		for _, r in pairs(RAWS_MANAGER.races_by_name) do
			-- First, find a land province that isn't owned by any realm...
			local prov = WORLD:random_tile().province
			while not ProvinceCheck(r, prov) do prov = WORLD:random_tile().province end

			-- An unowned province -- it means we can spawn a new realm here!
			local cg = cult.CultureGroup:new()
			local culture = cult.Culture:new(cg)

			local max_unit_weight = 0
			---@type table<string, number>
			local weights = {}
			for unit_name, unit in pairs(RAWS_MANAGER.unit_types_by_name) do
				if unit.unlocked_by == RAWS_MANAGER.technologies_by_name['paleolithic-knowledge'] then
					local v = love.math.random()
					max_unit_weight = max_unit_weight + v
					weights[unit_name] = v
				end
			end
			for unit, weight in pairs(weights) do
				culture.traditional_units[unit] = weight / max_unit_weight
			end
			culture.traditional_militarization = 0.05 + 0.1 * love.math.random()

			local rg = rel.Religion:new(culture)
			local faith = rel.Faith:new(rg, culture)
			faith.burial_rites = tabb.select_one(love.math.random(), {
				{
					weight = 1,
					entry = 'burial'
				},
				{
					weight = 0.8,
					entry = 'cremation'
				},
				{
					weight = 0.2,
					entry = 'none'
				}
			})
			make_new_realm(prov, r, culture, faith)
			queue:enqueue(prov)
		end
	end
	-- Loop through all entries in the queue and flood fill out
	while queue:length() > 0 do
		---@type Province
		local prov = queue:dequeue()
		-- First, check for rng based on movement cost.
		-- This will make it so culture "expand" slowly through mountains and such.
		if (love.math.random() > 0.001 + prov.movement_cost / 1000.0) or prov.on_a_river then
			for _, neigh in pairs(prov.neighbors) do
				local river_bonus = 1
				if prov.on_a_river and neigh.on_a_river then
					river_bonus = 0.25
				end
				if prov.realm.primary_race.requires_large_river then
					if neigh.on_a_river then
						river_bonus = 0.001
					else
						river_bonus = 1000
					end
				end
				if (love.math.random() > 0.001 + neigh.movement_cost / 1000.0 * river_bonus) then
					if neigh.center.is_land == prov.center.is_land and neigh.realm == nil and neigh.foragers_limit > 5.5 then
						-- We can spawn a new realm in this province! It's unused!
						make_new_realm(neigh, prov.realm.primary_race, prov.realm.primary_culture, prov.realm.primary_faith)
						queue:enqueue(neigh)
					end
				end
			end
		else
			-- queue:enqueue(prov)
		end
	end

	-- At the end, print the amount of spawned tribes
	print("Spawned tribes:", tabb.size(WORLD.realms))
	local pp = 0
	for _, prov in pairs(WORLD.provinces) do
		pp = pp + prov:population()
	end
	print("Spawned population: " .. tostring(pp))
end

return st
