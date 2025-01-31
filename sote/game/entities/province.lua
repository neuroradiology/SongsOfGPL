local tabb = require "engine.table"
local wb = require "game.entities.warband"

local EconomicValues = require "game.raws.values.economical"

---@alias Character POP

local prov = {}

---@class Province
---@field name string
---@field r number
---@field g number
---@field b number
---@field is_land boolean
---@field province_id number
---@field add_tile fun(self: Province, tile: Tile)
---@field size number
---@field tiles table<Tile, Tile>
---@field hydration number Number of humans that can live of off this provinces innate water
---@field neighbors table<Province, Province>
---@field movement_cost number
---@field center Tile The tile which contains this province's settlement, if there is any.
---@field infrastructure_needed number
---@field infrastructure number
---@field infrastructure_investment number
---@field get_infrastructure_efficiency fun(self:Province):number
---@field realm Realm?
---@field buildings table<Building, Building>
---@field all_pops table<POP, POP> -- all pops
---@field characters table<Character, Character>
---@field home_to table<Character, Character> Set of characters which think of this province as their home
---@field military fun(self:Province):number
---@field military_target fun(self:Province):number
---@field population fun(self:Province):number
---@field population_weight fun(self:Province):number
---@field unregister_military_pop fun(self:Province, pop:POP) The "fire" routine for soldiers. Also used in some other contexts?
---@field employ_pop fun(self:Province, pop:POP, building:Building)
---@field potential_job fun(self:Province, building:Building):Job?
---@field technologies_present table<Technology, Technology>
---@field technologies_researchable table<Technology, Technology>
---@field buildable_buildings table<BuildingType, BuildingType>
---@field research fun(self:Province, technology:Technology)
---@field local_production table<TradeGoodReference, number>
---@field local_consumption table<TradeGoodReference, number>
---@field local_demand table<TradeGoodReference, number>
---@field local_storage table<TradeGoodReference, number>
---@field local_prices table<TradeGoodReference, number|nil>
---@field local_wealth number
---@field trade_wealth number
---@field local_income number
---@field local_building_upkeep number
---@field foragers number Keeps track of the number of foragers in the province. Used to calculate yields of independent foraging.
---@field foragers_limit number
---@field building_type_present fun(self:Province, building:BuildingType):boolean Returns true when a building of a given type has been built in a province
---@field local_resources table<Resource, Resource> A hashset containing all resources present on tiles of this province
---@field local_resources_location {[1]: Tile, [2]: Resource}[] An array of local resources and their positions
---@field mood number how local population thinks about the state
---@field outlaws table<POP, POP>
---@field outlaw_pop fun(self:Province, pop:POP) Marks a pop as an outlaw
---@field get_dominant_culture fun(self:Province):Culture|nil
---@field get_dominant_faith fun(self:Province):Faith|nil
---@field get_dominant_race fun(self:Province):Race|nil
---@field soldiers table<POP, UnitType>
---@field unit_types table<UnitType, UnitType>
---@field warbands table<Warband, Warband>
---@field vacant_warbands fun(self: Province): Warband[]
---@field new_warband fun(self: Province): Warband
---@field num_of_warbands fun(self: Province): number
---@field get_spotting fun(self:Province):number Returns the local "spotting" power
---@field get_hiding fun(self:Province):number Returns the local "hiding" space
---@field spot_chance fun(self:Province, visibility: number): number Returns a chance to spot an army with given visibility.
---@field army_spot_test fun(self:Province, army:Army, stealth_penalty: number?):boolean Performs an army spotting test in this province.
---@field get_job_ratios fun(self:Province):table<Job, number> Returns a table containing jobs mapped to fractions of population. Used for, among other things, research.
---@field throughput_boosts table<ProductionMethod, number>
---@field input_efficiency_boosts table<ProductionMethod, number>
---@field output_efficiency_boosts table<ProductionMethod, number>
---@field on_a_river boolean
---@field on_a_forest boolean
---@field return_pop_from_army fun(self:Province, pop:POP, unit_type:UnitType): POP
---@field local_army_size fun(self:Province):number
---@field get_random_neighbor fun(self:Province):Province | nil

local col = require "game.color"

---@class Province
prov.Province = {}
prov.Province.__index = prov.Province

---Returns a new province. Remember to assign 'center' tile!
---@param fake_flag boolean? do not register province if true
---@return Province
function prov.Province:new(fake_flag)
	---@type Province
	local o = {}

	o.name = "<uninhabited>"

	local r, g, b = col.hsv_to_rgb(
		love.math.random(),
		0.9 + 0.1 * love.math.random(),
		0.9 + 0.1 * love.math.random()
	)
	o.r = r
	o.g = g
	o.b = b

	o.outlaws = {}
	o.mood = 0
	o.province_id = WORLD.entity_counter
	o.tiles = {}
	o.size = 0
	o.neighbors = {}
	o.movement_cost = 1
	o.foragers_limit = 0
	o.is_land = false
	o.buildings = {}
	o.all_pops = {}
	o.characters = {}
	o.home_to = {}
	o.technologies_present = {}
	o.technologies_researchable = {}
	o.buildable_buildings = {}
	o.hydration = 5
	o.local_resources = {}
	o.local_resources_location = {}
	o.local_production = {}
	o.local_consumption = {}
	o.local_demand = {}
	o.local_storage = {}
	o.local_prices = {}
	o.local_wealth = 0
	o.trade_wealth = 0
	o.local_income = 0
	o.local_building_upkeep = 0
	o.foragers = 0
	o.infrastructure_needed = 0
	o.infrastructure = 0
	o.infrastructure_investment = 0
	o.unit_types = {}
	o.soldiers = {}
	o.throughput_boosts = {}
	o.input_efficiency_boosts = {}
	o.output_efficiency_boosts = {}
	o.on_a_river = false
	o.on_a_forest = false
	o.warbands = {}

	if not fake_flag then
		WORLD.entity_counter = WORLD.entity_counter + 1
		WORLD.provinces[o.province_id] = o
	end

	setmetatable(o, prov.Province)
	return o
end

function prov.Province:get_random_neighbor()
	local s = tabb.size(self.neighbors)
	return tabb.nth(self.neighbors, love.math.random(s))
end

---Adds a tile to the province. Handles removal from the previous province, if necessary.
---@param tile Tile
function prov.Province:add_tile(tile)
	if tile.province ~= nil then
		tile.province.size = tile.province.size - 1
		tile.province.tiles[tile] = nil
	end
	self.tiles[tile] = tile
	self.size = self.size + 1
	tile.province = self
end

---Returns the total military size of the province.
---@return number
function prov.Province:military()
	local tabb = require "engine.table"
	return tabb.size(self.soldiers)
end

---Returns the total target military size of the province.
---@return number
function prov.Province:military_target()
	local sum = 0
	for _, warband in pairs(self.warbands) do
		for _, u in pairs(warband.units_target) do
			sum = sum + u
		end
	end
	return sum
end

---Returns the total population of the province.
---Doesn't include outlaws and active armies.
---@return number
function prov.Province:population()
	local tabb = require "engine.table"
	return tabb.size(self.all_pops)
end

---Returns the total population of the province.
---@return number
function prov.Province:population_weight()
	local total = 0
	for _, pop in pairs(self.all_pops) do
		total = total + pop.race.carrying_capacity_weight
	end
	return total
end

---Adds a pop to the province
---@param pop POP
function prov.Province:add_pop(pop)
	self.all_pops[pop] = pop
	pop.home_province = self
	pop.province = self
end

---Adds a character to the province
---@param character Character
function prov.Province:add_character(character)
	self.characters[character] = character
	character.province = self
end

---Sets province as character's home
---@param character Character
function prov.Province:set_home(character)
	self.home_to[character] = character
	character.home_province = self
end

--- Removes a character from the province
---@param character Character
function prov.Province:remove_character(character)
	self.characters[character] = nil
	character.province = nil
end

--- Character stops thinking of this province as a home
---@param character Character
function prov.Province:unset_home(character)
	self.home_to[character] = nil
	character.home_province = nil
end

---Kills a single pop and removes it from all relevant references.
---@param pop POP
function prov.Province:kill_pop(pop)
	self:fire_pop(pop)
	self:unregister_military_pop(pop)
	self.all_pops[pop] = nil
	self.home_to[pop] = nil

	self.outlaws[pop] = nil
	pop.province = nil

	if pop.home_province then
		pop.home_province.home_to[pop] = nil
		pop.home_province = nil
	end
end

function prov.Province:local_army_size()
	local total = 0
	for _, w in pairs(self.warbands) do
		if w.status == 'idle' or w.status == 'patrol' then
			total = total + w:size()
		end
	end
	return total
end

---Unregisters a pop as a military pop.
---@param pop POP
function prov.Province:unregister_military_pop(pop)
	if self.soldiers[pop] then
		pop.drafted = false
	end
	for _, warband in pairs(self.warbands) do
		if warband.units[pop] then
			warband:fire_unit(pop)
		end
	end
	self.soldiers[pop] = nil
end

---Removes the pop from the province without killing it
function prov.Province:take_away_pop(pop)
	self.soldiers[pop] = nil
	self.all_pops[pop] = nil
	return pop
end

function prov.Province:return_pop_from_army(pop, unit_type)
	self.soldiers[pop] = unit_type
	self.all_pops[pop] = pop
	return pop
end

---Fires an employed pop and adds it to the unemployed pops list.
---It leaves the "job" set so that inference of social class can be performed.
---@param pop POP
function prov.Province:fire_pop(pop)
	if pop.employer then
		pop.employer.workers[pop] = nil
		if tabb.size(pop.employer.workers) == 0 then
			pop.employer.last_income = 0
			pop.employer.last_donation_to_owner = 0
			pop.employer.subsidy_last = 0
		end
		pop.employer = nil
		pop.job = nil -- clear the job!
	end
end

---Employs a pop and handles its removal from relevant data structures...
---@param pop POP
---@param building Building
function prov.Province:employ_pop(pop, building)
	if pop.employer ~= building then
		local potential_job = self:potential_job(building)
		if potential_job then
			-- Now that we know that the job is needed, employ the pop!
			-- ... but fire them first to update the previous building
			if pop.employer ~= nil then
				self:fire_pop(pop)
			end
			building.workers[pop] = pop
			pop.employer = building
			pop.job = potential_job
		end
	end
end

---Returns a potential job, if a pop was to be employed by this building.
---@param building Building
---@return Job?
function prov.Province:potential_job(building)
	for job, amount in pairs(building.type.production_method.jobs) do
		-- Make sure that the building doesn't have this job filled out...
		local actually_employed = 0
		for _, worker in pairs(building.workers) do
			if worker.job == job then
				actually_employed = actually_employed + 1
			end
		end
		if actually_employed < amount then
			return job
		end
	end
	return nil
end

---@param technology Technology
function prov.Province:research(technology)
	self.technologies_present[technology] = technology
	self.technologies_researchable[technology] = nil

	for _, t in pairs(technology.potentially_unlocks) do
		if self.technologies_present[t] == nil then
			--print(t.name)
			local ok = true
			if #t.required_resource > 0 then
				--print(t.name .. " -- --!")
				local new_ok = false
				for _, resource in pairs(t.required_resource) do
					if self.local_resources[resource] then
						new_ok = true
						break
					end
				end
				if not new_ok then
					ok = false
				else
					--print("notok")
				end
			end
			if #t.required_race > 0 then
				local new_ok = false
				for _, race in pairs(t.required_race) do
					if race == self.realm.primary_race then
						new_ok = true
						break
					end
				end
				if not new_ok then
					ok = false
				end
			end
			if #t.required_biome > 0 then
				local new_ok = false
				for _, biome in pairs(t.required_biome) do
					if biome == self.center.biome then
						new_ok = true
						break
					end
				end
				if not new_ok then
					ok = false
				end
			end
			if #t.unlocked_by > 0 then
				local new_ok = true
				for _, te in pairs(t.unlocked_by) do
					if self.technologies_present[te] then
						-- nothing to do, tech present
					else
						-- tech missing, this tech cannot be unlocked...
						new_ok = false
						break
					end
				end
				if not new_ok then
					ok = false
				end
			end
			if ok then
				self.technologies_researchable[t] = t
			end
		end
	end
	for _, b in pairs(technology.unlocked_buildings) do
		local ok = true
		if #b.required_biome > 0 then
			ok = false
			for _, biome in b.required_biome do
				if biome == self.center.biome then
					ok = true
					break
				end
			end
		end
		if ok then
			self.buildable_buildings[b] = b
		end
	end
	for _, u in pairs(technology.unlocked_unit_types) do
		self.unit_types[u] = u
	end
	for prod, am in pairs(technology.throughput_boosts) do
		local old = self.throughput_boosts[prod] or 0
		self.throughput_boosts[prod] = old + am
	end
	for prod, am in pairs(technology.input_efficiency_boosts) do
		local old = self.input_efficiency_boosts[prod] or 0
		self.input_efficiency_boosts[prod] = old + am
	end
	for prod, am in pairs(technology.output_efficiency_boosts) do
		local old = self.output_efficiency_boosts[prod] or 0
		self.output_efficiency_boosts[prod] = old + am
	end

	if WORLD:does_player_see_realm_news(self.realm) then
		WORLD:emit_notification("Technology unlocked: " .. technology.name)
	end
end

---Forget technology
---@param technology Technology
function prov.Province:forget(technology)
	self.technologies_present[technology] = nil
	self.technologies_researchable[technology] = technology

	-- temporary forget all buildings and bonuses
	self.buildable_buildings = {}
	self.unit_types = {}
	self.throughput_boosts = {}
	self.input_efficiency_boosts = {}
	self.output_efficiency_boosts = {}

	-- relearn everything
	-- sounds like a horrible solution
	-- but after some thinking,
	-- you would need to do all these checks
	-- for all techs anyway
	-- because there are no assumptions for a graph of technologies
	for _, old_technology in pairs(self.technologies_present) do
		self:research(old_technology)
	end
end

---@param building_type BuildingType
---@return boolean
function prov.Province:building_type_present(building_type)
	for bld in pairs(self.buildings) do
		if bld.type == building_type then
			return true
		end
	end
	return false
end

---@alias BuildingAttemptFailureReason 'not_enough_funds' | 'unique_duplicate' | 'tile_improvement' | 'missing_local_resources'


---comment
---@param funds number
---@param building BuildingType
---@param location Tile?
---@param overseer POP?
---@param public boolean
---@return boolean
---@return string
function prov.Province:can_build(funds, building, location, overseer, public)
	local resource_check_passed = true
	if #building.required_resource > 0 then
		resource_check_passed = false
		if building.tile_improvement then
			if location then
				if location.resource then
					for _, res in pairs(building.required_resource) do
						if location.resource == res then
							resource_check_passed = true
							goto RESOURCE_CHECK_ENDED
						end
					end
				end
			end
		else
			for _, tile in pairs(self.tiles) do
				if tile.resource then
					for _, res in pairs(building.required_resource) do
						if tile.resource == res then
							resource_check_passed = true
							goto RESOURCE_CHECK_ENDED
						end
					end
				end
			end
		end
		::RESOURCE_CHECK_ENDED::
	end

	local construction_cost = EconomicValues.building_cost(building, overseer, public)

	if building.unique and self:building_type_present(building) then
		return false, 'unique_duplicate'
	elseif building.tile_improvement and location == nil then
		return false, 'tile_improvement'
	elseif not resource_check_passed then
		return false, 'missing_local_resources'
	elseif construction_cost <= funds then
		return true, nil
	else
		return false, 'not_enough_funds'
	end
end

---@return number
function prov.Province:get_infrastructure_efficiency()
	local inf = 0
	if self.infrastructure_needed > 0 then
		inf = self.infrastructure / self.infrastructure_needed
	end
	return inf
end

---@param pop POP
function prov.Province:outlaw_pop(pop)
	self:fire_pop(pop)
	self:unregister_military_pop(pop)
	self.all_pops[pop] = nil
	self.outlaws[pop] = pop
end

---Marks a pop as a soldier of a given type in a given warband.
---@param pop POP
---@param unit_type UnitType
---@param warband Warband
function prov.Province:recruit(pop, unit_type, warband)
	-- if pop is already drafted, do nothing
	if pop.drafted then
		return
	end

	-- clean pop and set his unit type
	self:fire_pop(pop)
	self:unregister_military_pop(pop)
	pop.drafted = true
	self.soldiers[pop] = unit_type

	-- set warband
	warband:hire_unit(self, pop, unit_type)
end

---@return Culture|nil
function prov.Province:get_dominant_culture()
	local e = {}
	for _, p in pairs(self.all_pops) do
		local old = e[p.culture] or 0
		e[p.culture] = old + 1
	end
	local best = nil
	local max = 0
	for k, v in pairs(e) do
		if v > max then
			best = k
			max = v
		end
	end
	return best
end

---@return Faith|nil
function prov.Province:get_dominant_faith()
	local e = {}
	for _, p in pairs(self.all_pops) do
		local old = e[p.faith] or 0
		e[p.faith] = old + 1
	end
	local best = nil
	local max = 0
	for k, v in pairs(e) do
		if v > max then
			best = k
			max = v
		end
	end
	return best
end

---@return Race|nil
function prov.Province:get_dominant_race()
	local e = {}
	for _, p in pairs(self.all_pops) do
		local old = e[p.race] or 0
		e[p.race] = old + 1
	end
	local best = nil
	local max = 0
	for k, v in pairs(e) do
		if v > max then
			best = k
			max = v
		end
	end
	return best
end

---Returns whether or not a province borders a given realm
---@param realm Realm
---@return boolean
function prov.Province:neighbors_realm(realm)
	for _, n in pairs(self.neighbors) do
		if n.realm == realm then
			return true
		end
	end
	return false
end

---Returns whether or not a province borders a given realm
---@param realm Realm
---@return boolean
function prov.Province:neighbors_realm_tributary(realm)
	for _, n in pairs(self.neighbors) do
		if n.realm and n.realm:is_realm_in_hierarchy(realm) then
			return true
		end
	end
	return false
end

---@return number
function prov.Province:get_spotting()
	local s = 0

	for p, _ in pairs(self.all_pops) do
		s = s + p.race.spotting
	end
	for b, _ in pairs(self.buildings) do
		s = s + b.type.spotting
	end

	for _, w in pairs(self.warbands) do
		if w.status == 'idle' or w.status == 'patrol' then
			s = s + w:spotting()
		end
	end

	return s
end

---@return number
function prov.Province:get_hiding()
	local hide = 1
	for t, _ in pairs(self.tiles) do
		hide = hide + 1 + t.grass + t.shrub * 2 + t.conifer * 3 + t.broadleaf * 5
	end
	return hide
end

function prov.Province:spot_chance(visibility)
	local spot = self:get_spotting()
	local hiding = self:get_hiding()
	local actual_hiding = hiding - visibility
	local size = spot + visibility + hiding
	-- If spot == hide, we should get 50:50 odds.
	-- If spot > hide, we should get higher odds of spotting
	-- If spot < hide, we should get lower odds of spotting
	local odds = 0.5
	local delta = spot - actual_hiding
	if delta == 0 then
		-- nothing to do
	else
		delta = delta / size
	end
	odds = math.max(0, math.min(1, odds + 0.5 * delta))
	return odds
end

---@param army Army Attacking army
---@param stealth_penalty number? Multiplicative penalty, multiplies army visibility score.
---@return boolean True if the army was spotted.
function prov.Province:army_spot_test(army, stealth_penalty)
	-- To resolve this event we need to perform some checks.
	-- First, we should have a "scouting" check.
	-- Them, a potential battle ought to take place.`
	if stealth_penalty == nil then
		stealth_penalty = 1
	end

	local visib = (army:get_visibility() + love.math.random(20)) * stealth_penalty
	local odds = self:spot_chance(visib)
	if love.math.random() < odds then
		-- Spot!
		return true
	else
		-- Hide!
		return false
	end
end

function prov.Province:get_job_ratios()
	local r = {}

	local pop = 0
	for p, _ in pairs(self.all_pops) do
		if p.job then
			local old = r[p.job] or 0
			r[p.job] = old + 1
		end
		pop = pop + 1
	end
	for job, am in pairs(r) do
		r[job] = am / pop
	end

	return r
end

---Returns the number of unemployed people in the province.
---@return integer
function prov.Province:get_unemployment()
	local u = 0

	for _, p in pairs(self.all_pops) do
		if not p.drafted and p.job == nil then
			u = u + 1
		end
	end

	return u
end

function prov.Province:new_warband()
	local warband = wb:new()
	self.warbands[warband] = warband
	return warband
end

function prov.Province:num_of_warbands()
	return tabb.size(self.warbands)
end

function prov.Province:vacant_warbands()
	local res = {}

	for k, v in pairs(self.warbands) do
		if v:vacant() then
			table.insert(res, k)
		end
	end

	return res
end

return prov
