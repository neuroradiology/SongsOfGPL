local re = {}
local trade_good = require "game.raws.raws-utils".trade_good
local tabb = require "engine.table"
local ui = require "engine.ui"
local uit = require "game.ui-utils"

local ef = require "game.raws.effects.economic"
local ev = require "game.raws.values.economical"

---@return Rect
local function get_main_panel()
	local fs = ui.fullscreen()
	local panel = fs:subrect(uit.BASE_HEIGHT * 2, uit.BASE_HEIGHT * 2, 700, 500, "left", "up")
	return panel
end

---Returns whether or not clicks on the planet can be registered.
---@return boolean
function re.mask()
	if ui.trigger(get_main_panel()) then
		return false
	else
		return true
	end
end

local TREASURY_GIFT_AMOUNT = 1

---@param gam GameScene
function re.draw(gam)

	if ui.is_key_held("lshift") or ui.is_key_held("rshift") then
		TREASURY_GIFT_AMOUNT = 5
	elseif ui.is_key_held("lctrl") or ui.is_key_held("rctrl") then
		TREASURY_GIFT_AMOUNT = 50
	else
		TREASURY_GIFT_AMOUNT = 1
	end

	---@diagnostic disable-next-line: assign-type-mismatch
	local rrealm = gam.selected.realm
	if rrealm ~= nil then
		---@type Realm
		local realm = rrealm
		local panel = get_main_panel()
		ui.panel(panel)

		if uit.icon_button(ASSETS.icons["cancel.png"], panel:subrect(0, 0, uit.BASE_HEIGHT, uit.BASE_HEIGHT, "right", "up")) then
			gam.click_tile(-1)
			gam.selected.realm = nil
			gam.inspector = nil
		end

		-- COA
		uit.coa(realm, panel:subrect(0, 0, uit.BASE_HEIGHT, uit.BASE_HEIGHT, "left", "up"))
		ui.left_text(realm.name,
			panel:subrect(uit.BASE_HEIGHT + 5, 0, 10 * uit.BASE_HEIGHT, uit.BASE_HEIGHT, "left", "up"))

		local ui_panel = panel:subrect(5, uit.BASE_HEIGHT * 2, panel.width - 10, panel.height - 10 - uit.BASE_HEIGHT * 2,
			"left", "up")
		gam.realm_inspector_tab = gam.realm_inspector_tab or "GEN"

		local treasury_tab = nil
		if WORLD.player_character == realm.leader then
			treasury_tab = {
				text = "TRE",
				tooltip = "Realm treasury",
				closure = require "game.scenes.game.inspectors.treasury"(ui_panel, realm)
			}
		end

		local tabs = {
			{
				text = "GEN",
				tooltip = "General",
				closure = require "game.scenes.game.inspectors.realm-general"(ui_panel, realm, gam)
			},
			treasury_tab,
			{
				text = "STO",
				tooltip = "Stockpiles",
				closure = function()
					local goods = {}
					for good, amount in pairs(realm.resources) do
						local resource = trade_good(good)
						if resource.category == "good" then
							goods[good] = amount
						end
					end
					gam.realm_stockpile_scrollbar = gam.realm_stockpile_scrollbar or 0
					gam.realm_stockpile_scrollbar = uit.scrollview(ui_panel, function(entry, rect)
						if entry > 0 then
							---@type TradeGoodReference
							local good, amount = tabb.nth(goods, entry)
							local delta = realm.production[good] or 0
							local resource = trade_good(good)

							local w = rect.width
							rect.width = rect.height
							ui.image(ASSETS.get_icon(resource.icon), rect)

							rect.width = w
							rect.x = rect.x + rect.height
							rect.width = rect.width - rect.height
							uit.sqrt_number_entry(
								good,
								amount or 0,
								rect
							)
						end
					end, uit.BASE_HEIGHT, tabb.size(goods), uit.BASE_HEIGHT, gam.realm_stockpile_scrollbar)
				end
			},
			{
				text = "ADM",
				tooltip = "Administration",
				closure = function()
					local goods = {}
					for good, amount in pairs(realm.production) do
						local resource = trade_good(good)
						if resource.category == "capacity" then
							goods[good] = amount
						end
					end
					gam.realm_capacities_scrollbar = gam.realm_capacities_scrollbar or 0
					gam.realm_capacities_scrollbar = uit.scrollview(ui_panel, function(entry, rect)
						if entry > 0 then
							---@type TradeGoodReference
							local good, amount = tabb.nth(goods, entry)
							local resource = trade_good(good)

							local w = rect.width
							rect.width = rect.height
							ui.image(ASSETS.get_icon(resource.icon), rect)

							rect.width = w
							rect.x = rect.x + rect.height
							rect.width = rect.width - rect.height
							ui.left_text(good, rect)
							ui.right_text(tostring(math.floor(100 * amount) / 100), rect)
						end
					end, uit.BASE_HEIGHT, tabb.size(goods), uit.BASE_HEIGHT, gam.realm_capacities_scrollbar)
				end
			},
			{
				text = "COU",
				tooltip = "Court",
				closure = function()
					local a = ui_panel:subrect(0, 0, uit.BASE_HEIGHT * 12, uit.BASE_HEIGHT, "left", "up")
					uit.money_entry("Court wealth: ", realm.budget.court.budget, a,
						"Investment.")
					a.y = a.y + uit.BASE_HEIGHT

					uit.money_entry("Court wealth. needed: ", realm.budget.court.target
						, a,
						"Needed court wealth.")
					a.y = a.y + uit.BASE_HEIGHT

					if WORLD:does_player_control_realm(realm) then
						local p = a:copy()
						p.width = p.height * 4

						local possible = realm.budget.treasury > TREASURY_GIFT_AMOUNT
						if uit.money_button(
							"Invest ",
							TREASURY_GIFT_AMOUNT,
							p,
							"Invest money into court. Press Ctrl or Shift to modify invested amount.",
							possible
						) then
							ef.direct_investment(
								realm,
								realm.budget.court,
								TREASURY_GIFT_AMOUNT,
								EconomicEffects.reasons.Court
							)
						end
					end
					a.y = a.y + uit.BASE_HEIGHT
				end
			},
			-- {
			-- 	text = "MAR",
			-- 	tooltip = "Market",
			-- 	closure = function()
			-- 		---@type table<TradeGoodReference, number>
			-- 		local goods = {}
			-- 		for good, _ in pairs(realm.bought) do
			-- 			goods[good] = ev.get_realm_price(realm, good)
			-- 		end
			-- 		for good, _ in pairs(realm.sold) do
			-- 			goods[good] = ev.get_realm_price(realm, good)
			-- 		end
			-- 		gam.realm_market_scrollbar = gam.realm_market_scrollbar or 0
			-- 		gam.realm_market_scrollbar = uit.scrollview(ui_panel, function(entry, rect)
			-- 			if entry > 0 then
			-- 				---@type TradeGoodReference
			-- 				local good, price = tabb.nth(goods, entry)
			-- 				local resource = trade_good(good)

			-- 				local w = rect.width
			-- 				rect.width = rect.height
			-- 				ui.image(ASSETS.get_icon(resource.icon), rect)

			-- 				rect.width = w
			-- 				rect.x = rect.x + rect.height
			-- 				rect.width = rect.width - rect.height
			-- 				uit.money_entry(good, price, rect, "price")
			-- 			end
			-- 		end, uit.BASE_HEIGHT, tabb.size(goods), uit.BASE_HEIGHT, gam.realm_market_scrollbar)
			-- 	end
			-- },
			{
				text = "EDU",
				tooltip = "Education and research",
				closure = function()
					local a = ui_panel:subrect(0, 0, uit.BASE_HEIGHT * 12, uit.BASE_HEIGHT, "left", "up")
					uit.money_entry(
						"Endowment: ",
						realm.budget.education.budget,
						a,
						"Investment."
					)
					a.y = a.y + uit.BASE_HEIGHT


					uit.money_entry(
						"Endwm. needed: ",
						realm.budget.education.target
						,
						a,
						"Needed endowment to support current technologies."
					)
					a.y = a.y + uit.BASE_HEIGHT


					if WORLD:does_player_control_realm(realm) then
						local p = a:copy()
						p.width = p.height * 4

						local possible = realm.budget.treasury > TREASURY_GIFT_AMOUNT
						if uit.money_button(
							"Invest ",
							TREASURY_GIFT_AMOUNT,
							p,
							"Invest money into education. Press Ctrl or Shift to modify invested amount.",
							possible
						) then
							ef.direct_investment(
								realm,
								realm.budget.education,
								TREASURY_GIFT_AMOUNT,
								EconomicEffects.reasons.Education
							)
						end
					end
					a.y = a.y + uit.BASE_HEIGHT
					uit.data_entry_percentage("Education efficiency: ",
						realm:get_education_efficiency()
						, a,
						"A percentage value. Endowment present over endowment needed")
					a.y = a.y + uit.BASE_HEIGHT
				end
			},
			{
				text = "DEM",
				tooltip = "Demographics",
				closure = require "game.scenes.game.widgets.demography"(realm.provinces, ui_panel)
			},
			{
				text = "DIP",
				tooltip = "Diplomacy",
				closure = require "game.scenes.game.inspectors.diplomacy"(gam, realm, ui_panel)
			},
			{
				text = "RDC",
				tooltip = "Realm decisions",
				on_select = function()
					gam.reset_decision_selection()
				end,
				closure = function()
					require "game.scenes.game.widgets.decision-tab" (ui_panel, realm, "realm", gam)
				end
			},
			{
				text = "WAR",
				tooltip = "Warfare",
				closure = function()
					--ui_panel
					ui.panel(ui_panel)
					local sl = gam.wars_slider_level or 0
					gam.wars_slider_level = uit.scrollview(ui_panel, function(i, rect)
						if i > 0 then
							---@type Rect
							local r = rect
							---@type War
							local war = tabb.nth(realm.wars, i)
							local w = r.width
							r.width = r.height
							if uit.icon_button(ASSETS.get_icon("guards.png"), r) then
								-- Select the war
								gam.inspector = "war"
								gam.selected.war = war
							end
							r.width = w - r.height
							r.x = r.x + r.height
							ui.panel(r)
							r.x = r.x + 5
							r.width = r.width - 5
							---@type Realm
							local att = tabb.nth(war.attackers, 1)
							---@type Realm
							local def = tabb.nth(war.defenders, 1)
							ui.left_text(att.name .. " vs " .. def.name, r)
						end
					end, uit.BASE_HEIGHT, tabb.size(realm.wars), uit.BASE_HEIGHT, sl)
				end
			},
		}
		local layout = ui.layout_builder()
			:position(panel.x, panel.y + uit.BASE_HEIGHT)
			:spacing(2)
			:horizontal()
			:build()
		gam.realm_inspector_tab = uit.tabs(gam.realm_inspector_tab, layout, tabs, 1)
	end
end

return re
