local mod = get_mod("weapon_jam")
local UIRenderer = require("scripts/managers/ui/ui_renderer")

local function create_empty_slot_state()
	return {
		is_jammed = false,
		combo_sequence = {},
		current_step = 1,
		error_timer = 0,
		success_timer = 0,
	}
end

mod.slot_states = {
	slot_primary = create_empty_slot_state(),
	slot_secondary = create_empty_slot_state(),
}

mod.is_jammed = false
mod.last_dryfire_time = 0
mod.pulse_timer = 0
mod.dpad_grace_timer = 0
mod.waiting_for_dpad_release = false

local function get_local_player_unit()
	local player = Managers.player and Managers.player:local_player(1)
	return player and player.player_unit
end

local function get_wielded_slot()
	local unit = get_local_player_unit()
	if not unit or not Unit.alive(unit) then return nil end
	local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_ext then return nil end
	local inventory_component = unit_data_ext:read_component("inventory")
	return inventory_component and inventory_component.wielded_slot
end

local function get_slot_state(slot_name)
	if slot_name and mod.slot_states[slot_name] then
		return mod.slot_states[slot_name]
	end
	return nil
end

local function get_wielded_slot_state()
	local wielded = get_wielded_slot()
	if wielded and mod.slot_states[wielded] then
		return mod.slot_states[wielded], wielded
	end
	return nil, nil
end

local function is_any_weapon_jammed()
	return (mod.slot_states.slot_primary and mod.slot_states.slot_primary.is_jammed) or
	       (mod.slot_states.slot_secondary and mod.slot_states.slot_secondary.is_jammed)
end

local function is_any_dpad_held()
	local pad = Pad1
	if pad and pad.button and pad.button_index then
		local b_up = pad.button_index("d_up")
		local b_down = pad.button_index("d_down")
		local b_left = pad.button_index("d_left")
		local b_right = pad.button_index("d_right")
		local up = b_up and pad.button(b_up) or 0
		local down = b_down and pad.button(b_down) or 0
		local left = b_left and pad.button(b_left) or 0
		local right = b_right and pad.button(b_right) or 0
		if up > 0 or down > 0 or left > 0 or right > 0 then
			return true
		end
	end
	return false
end

local DIRECTIONS = { "up", "down", "left", "right" }

local ARROW_ANGLES = {
	right = 0,
	up = math.pi * 0.5,
	left = math.pi,
	down = -math.pi * 0.5,
}

local ARROW_MATERIAL = "content/ui/materials/buttons/arrow_01"

local SHOOT_ACTION_KINDS = {
	shoot_hit_scan = true,
	shoot_pellets = true,
	shoot_projectile = true,
	shoot_spray = true,
	spawn_projectile = true,
	flamer_gas = true,
	flamer_gas_burst = true,
	shoot = true,
	charge = true,
	charge_ammo = true,
	ranged_load_special = true,
}

local SPECIAL_ACTIVATION_KINDS = {
	activate_special = true,
	toggle_special = true,
	toggle_special_with_block = true,
	overload_charge_weapon_special = true,
	ranged_load_special = true,
}

local BLOCKED_GUN_ACTIONS = {
	action_one_pressed = true,
	action_one_hold = true,
	action_one_release = true,
	action_two_hold = true,
	action_two_pressed = true,
	action_two_release = true,
	weapon_extra_pressed = true,
	weapon_extra_hold = true,
	weapon_extra = true,
	weapon_extra_release = true,
}

local BLOCKED_DEFENSIVE_ACTIONS = {
	action_one_pressed = true,
	action_one_hold = true,
	action_one_release = true,
	weapon_extra_pressed = true,
	weapon_extra_hold = true,
	weapon_extra = true,
	weapon_extra_release = true,
}

local BLOCKED_SPECIAL_ACTIONS = {
	weapon_extra_pressed = true,
	weapon_extra_hold = true,
	weapon_extra = true,
	weapon_extra_release = true,
}

local BLOCKED_MELEE_ATTACK_KINDS = {
	sweep = true,
	windup = true,
	melee_explosive = true,
	lunge_start_and_wait_for_end = true,
}

local BLOCKED_CONTROLLER_DPAD_ACTIONS = {
	wield_3 = true,
	wield_3_gamepad = true,
	wield_4 = true,
	wield_4_gamepad = true,
	wield_5 = true,
	wield_5_gamepad = true,
	wield_grenade = true,
	wield_pocketable = true,
	wield_stimm = true,
	grenade_ability = true,
	grenade_ability_pressed = true,
	grenade_ability_hold = true,
	grenade_ability_release = true,
	weapon_inspect = true,
	weapon_inspect_hold = true,
	tactical_overlay_controller_scroll_down = true,
	tactical_overlay_controller_scroll_up = true,
}

local center_text_options = {
	horizontal_alignment = Gui.HorizontalAlignCenter,
	vertical_alignment = Gui.VerticalAlignCenter,
	shadow = true,
}

local function play_sound(event_name)
	if not mod:get("enable_sounds") then return end
	if Managers.ui and Managers.ui.play_2d_sound then
		Managers.ui:play_2d_sound(event_name)
	end
end

local function play_activation_jam_sfx()
	play_sound("wwise/events/ui/play_ui_character_loadout_weapon_mark_equip")
	play_sound("wwise/events/ui/play_ui_character_loadout_equip_weapon")
	play_sound("wwise/events/ui/play_ui_click")
end

local function play_gun_jam_sfx()
	play_sound("wwise/events/ui/play_ui_character_loadout_equip_weapon")
	play_sound("wwise/events/ui/play_ui_click")
	play_sound("wwise/events/ui/play_hud_notifications_warning")
end

local function is_local_player_blocking()
	local unit = get_local_player_unit()
	if not unit or not Unit.alive(unit) then return false end
	local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_ext then return false end
	local block_component = unit_data_ext:read_component("block")
	return block_component and block_component.is_blocking
end

local function deactivate_wielded_weapon_special()
	local unit = get_local_player_unit()
	if not unit or not Unit.alive(unit) then return end
	local weapon_ext = ScriptUnit.has_extension(unit, "weapon_system")
	if weapon_ext and weapon_ext.set_wielded_weapon_weapon_special_active then
		local t = Managers.time and Managers.time:has_timer("gameplay") and Managers.time:time("gameplay") or 0
		weapon_ext:set_wielded_weapon_weapon_special_active(t, false, "manual_toggle")
	end
end

local function is_wielded_weapon_special_jammable()
	local unit = get_local_player_unit()
	if not unit or not Unit.alive(unit) then return false end
	local weapon_ext = ScriptUnit.has_extension(unit, "weapon_system")
	if not weapon_ext or not weapon_ext.weapon_template then return false end
	local weapon_template = weapon_ext:weapon_template()
	if not weapon_template then return false end

	if weapon_template.weapon_special then
		return true
	end

	local actions = weapon_template.actions
	if actions then
		for _, action_settings in pairs(actions) do
			local kind = action_settings and action_settings.kind
			if kind and SPECIAL_ACTIVATION_KINDS[kind] then
				return true
			end
		end
	end

	return false
end

local function generate_combo(length)
	local seq = {}
	for i = 1, length do
		seq[i] = DIRECTIONS[math.random(1, #DIRECTIONS)]
	end
	return seq
end

mod.jam_weapon = function(slot)
	if not mod:get("enable_mod") then return end

	local current_slot = slot or get_wielded_slot() or "slot_secondary"
	local state = get_slot_state(current_slot)
	if not state or state.is_jammed then return end

	local length = math.floor(mod:get("combo_length") or 5)
	state.combo_sequence = generate_combo(length)
	state.current_step = 1
	state.is_jammed = true
	state.error_timer = 0
	state.success_timer = 0

	mod.is_jammed = is_any_weapon_jammed()

	local wielded = get_wielded_slot()
	if wielded == current_slot then
		deactivate_wielded_weapon_special()
	end

	if current_slot == "slot_secondary" then
		play_gun_jam_sfx()
	else
		play_activation_jam_sfx()
		play_sound("wwise/events/ui/play_hud_notifications_warning")
	end
end

mod.unjam_weapon = function(slot)
	local current_slot = slot or get_wielded_slot()
	local state = get_slot_state(current_slot)
	if not state or not state.is_jammed then return end

	state.is_jammed = false
	state.combo_sequence = {}
	state.current_step = 1
	state.success_timer = 1.2

	mod.is_jammed = is_any_weapon_jammed()
	mod.dpad_grace_timer = 0.5
	mod.waiting_for_dpad_release = true

	play_sound("wwise/events/ui/play_hud_ability_off_cooldown")
end

mod.on_force_jam_pressed = function()
	local wielded = get_wielded_slot()
	local state = get_slot_state(wielded)
	if state and state.is_jammed then
		mod.unjam_weapon(wielded)
	else
		mod.jam_weapon(wielded)
	end
end

mod.on_force_unjam_pressed = function()
	local wielded = get_wielded_slot()
	local state = get_slot_state(wielded)
	if state and state.is_jammed then
		mod.unjam_weapon(wielded)
	else
		if mod.slot_states.slot_primary.is_jammed then
			mod.unjam_weapon("slot_primary")
		elseif mod.slot_states.slot_secondary.is_jammed then
			mod.unjam_weapon("slot_secondary")
		end
	end
end

local function trigger_gun_jam_roll()
	if not mod:get("enable_mod") then return end
	local wielded = get_wielded_slot()
	if wielded ~= "slot_secondary" then return end
	local state = get_slot_state("slot_secondary")
	if not state or state.is_jammed then return end

	local jam_chance = mod:get("jam_chance")
	if jam_chance == nil then
		jam_chance = 5.0
	end
	local roll = math.random() * 100.0
	if roll < jam_chance then
		mod.jam_weapon("slot_secondary")
	end
end

mod:hook("PlayerUnitWeaponExtension", "set_wielded_weapon_weapon_special_active", function(func, self, t, want_active, optional_reason)
	if mod:get("enable_mod") then
		local unit = self._unit
		local local_unit = get_local_player_unit()
		if unit and unit == local_unit then
			local inventory_component = self._inventory_component
			local wielded = inventory_component and inventory_component.wielded_slot
			if wielded and (wielded == "slot_primary" or wielded == "slot_secondary") then
				local state = get_slot_state(wielded)
				if want_active and state and state.is_jammed then
					return
				end
			end
		end
	end

	return func(self, t, want_active, optional_reason)
end)

mod:hook_safe("ActionHandler", "start_action", function(self, id, action_objects, action_name, action_params, action_settings)
	local unit = self._unit
	local local_unit = get_local_player_unit()
	if unit and unit == local_unit then
		local kind = action_settings and action_settings.kind
		if kind and SHOOT_ACTION_KINDS[kind] then
			trigger_gun_jam_roll()
		end
	end
end)

local function clear_external_swap_queues()
	local gws = get_mod("guarantee_weapon_swap")
	if gws and gws.promises then
		table.clear(gws.promises)
		gws.promise_exist = false
	end
	local gaa = get_mod("guarantee_ability_activation")
	if gaa and gaa.promises then
		table.clear(gaa.promises)
		gaa.promise_exist = false
	end
	local gsa = get_mod("guarantee_special_action")
	if gsa and gsa.promises then
		gsa.promises.action_special = false
		gsa.promises.action_reload = false
		gsa.promise_exist = false
	end
end

local function handle_input_interception(func, self, action_name)
	local action_rule = self._actions and self._actions[action_name]
	if not action_rule then
		return func(self, action_name)
	end

	local out = func(self, action_name)

	if not mod:get("enable_mod") then
		return out
	end

	local wielded = get_wielded_slot()
	if not wielded or (wielded ~= "slot_primary" and wielded ~= "slot_secondary") then
		return out
	end

	local state = get_slot_state(wielded)
	if not state then
		return out
	end

	-- 1. Activation jam roll if currently wielded weapon is not jammed and weapon_extra_pressed fires
	if not state.is_jammed and action_name == "weapon_extra_pressed" and out then
		if mod:get("enable_activation_jam") and is_wielded_weapon_special_jammable() then
			local jam_chance = mod:get("activation_jam_chance")
			if jam_chance == nil then jam_chance = 5.0 end
			local roll = math.random() * 100.0
			if roll < jam_chance then
				clear_external_swap_queues()
				mod.jam_weapon(wielded)
				return false
			end
		end
	end

	-- 2. If the currently wielded weapon is jammed, block actions based on lockout mode
	if state.is_jammed then
		clear_external_swap_queues()
		local lockout_mode = mod:get("activation_lockout_mode") or "special_only"
		local blocked_actions = BLOCKED_GUN_ACTIONS

		if wielded == "slot_primary" then
			if lockout_mode == "special_only" then
				blocked_actions = BLOCKED_SPECIAL_ACTIONS
			elseif lockout_mode == "defensive_only" then
				blocked_actions = BLOCKED_DEFENSIVE_ACTIONS
			end
		end

		local is_special_jammable = is_wielded_weapon_special_jammable()
		local is_physical_special_action = not is_special_jammable and (action_name == "weapon_extra_pressed" or action_name == "weapon_extra_hold" or action_name == "weapon_extra" or action_name == "weapon_extra_release")

		local is_defensive_push = (lockout_mode == "defensive_only" and wielded == "slot_primary" and (action_name == "action_one_pressed" or action_name == "action_one_hold")) and (is_local_player_blocking() or (self.get and self:get("action_two_hold")))

		if blocked_actions[action_name] and not is_defensive_push and not is_physical_special_action then
			if (action_name == "action_one_pressed" or action_name == "action_one_hold" or action_name == "weapon_extra_pressed") and out then
				local t = Managers.time and Managers.time:has_timer("gameplay") and Managers.time:time("gameplay") or 0
				if t - (mod.last_dryfire_time or 0) > 0.25 then
					mod.last_dryfire_time = t
					if action_name == "weapon_extra_pressed" or action_name == "weapon_extra" then
						play_sound("wwise/events/ui/play_ui_character_loadout_weapon_mark_equip")
						play_sound("wwise/events/ui/play_ui_click")
					elseif wielded == "slot_primary" then
						play_sound("wwise/events/ui/play_ui_click")
						play_sound("wwise/events/ui/play_ui_character_loadout_equip_armor_small")
					else
						play_sound("wwise/events/ui/play_ui_click")
					end
				end
			end
			return false
		end

		if BLOCKED_CONTROLLER_DPAD_ACTIONS[action_name] then
			local is_gamepad = Managers.input and Managers.input.is_using_gamepad and Managers.input:is_using_gamepad()
			if is_gamepad then
				if is_any_weapon_jammed() or mod.waiting_for_dpad_release or ((mod.dpad_grace_timer or 0) > 0) then
					clear_external_swap_queues()
					if not is_any_weapon_jammed() and mod.waiting_for_dpad_release and not is_any_dpad_held() and ((mod.dpad_grace_timer or 0) <= 0) then
						mod.waiting_for_dpad_release = false
					else
						return false
					end
				end
			end
		end
	end

	return out
end

mod:hook("InputService", "_get", handle_input_interception)
mod:hook("InputService", "_get_simulate", handle_input_interception)

mod:hook("PlayerUnitAbilityExtension", "can_wield", function(func, self, slot_name, previous_check)
	local state, wielded = get_wielded_slot_state()
	if mod:get("enable_mod") and state and state.is_jammed then
		local is_gamepad = Managers.input and Managers.input.is_using_gamepad and Managers.input:is_using_gamepad()
		if is_gamepad and (state.is_jammed or mod.waiting_for_dpad_release or ((mod.dpad_grace_timer or 0) > 0)) then
			if slot_name == "slot_grenade_ability" or slot_name == "slot_pocketable" or slot_name == "slot_device" then
				clear_external_swap_queues()
				return false
			end
		end
	end
	return func(self, slot_name, previous_check)
end)

mod:hook("PlayerUnitWeaponExtension", "can_wield", function(func, self, slot_name)
	local state, wielded = get_wielded_slot_state()
	if mod:get("enable_mod") and state and state.is_jammed then
		local is_gamepad = Managers.input and Managers.input.is_using_gamepad and Managers.input:is_using_gamepad()
		if is_gamepad and (state.is_jammed or mod.waiting_for_dpad_release or ((mod.dpad_grace_timer or 0) > 0)) then
			if slot_name == "slot_grenade_ability" or slot_name == "slot_pocketable" or slot_name == "slot_device" then
				clear_external_swap_queues()
				return false
			end
		end
	end
	return func(self, slot_name)
end)

mod:hook("ActionHandler", "_validate_action", function(func, self, action_settings, condition_func_params, t, time_in_action, used_input)
	if mod:get("enable_mod") then
		local unit = self._unit
		local local_unit = get_local_player_unit()
		if unit and unit == local_unit then
			local inventory_component = self._inventory_component
			local wielded = inventory_component and inventory_component.wielded_slot
			local state = wielded and get_slot_state(wielded)
			local kind = action_settings and action_settings.kind

			if state and state.is_jammed and kind then
				local lockout_mode = mod:get("activation_lockout_mode") or "special_only"
				if wielded == "slot_primary" then
					if lockout_mode == "special_only" then
						if SPECIAL_ACTIVATION_KINDS[kind] then
							return false
						end
					elseif lockout_mode == "defensive_only" then
						if SPECIAL_ACTIVATION_KINDS[kind] or BLOCKED_MELEE_ATTACK_KINDS[kind] then
							return false
						end
					else
						if SHOOT_ACTION_KINDS[kind] or SPECIAL_ACTIVATION_KINDS[kind] or BLOCKED_MELEE_ATTACK_KINDS[kind] then
							return false
						end
					end
				else
					if SHOOT_ACTION_KINDS[kind] or SPECIAL_ACTIVATION_KINDS[kind] then
						return false
					end
				end
			end
		end
	end

	return func(self, action_settings, condition_func_params, t, time_in_action, used_input)
end)

local function poll_unjam_inputs()
	if not mod:get("enable_mod") then return end
	local state, wielded = get_wielded_slot_state()
	if not state or not state.is_jammed then return end

	local allow_wasd = mod:get("allow_wasd")
	local input_dir = nil

	local kb = Keyboard
	local pad = Pad1

	if (kb and kb.pressed(kb.button_index("up"))) or (allow_wasd and kb and kb.pressed(kb.button_index("w"))) or (pad and pad.pressed(pad.button_index("d_up"))) then
		input_dir = "up"
	elseif (kb and kb.pressed(kb.button_index("down"))) or (allow_wasd and kb and kb.pressed(kb.button_index("s"))) or (pad and pad.pressed(pad.button_index("d_down"))) then
		input_dir = "down"
	elseif (kb and kb.pressed(kb.button_index("left"))) or (allow_wasd and kb and kb.pressed(kb.button_index("a"))) or (pad and pad.pressed(pad.button_index("d_left"))) then
		input_dir = "left"
	elseif (kb and kb.pressed(kb.button_index("right"))) or (allow_wasd and kb and kb.pressed(kb.button_index("d"))) or (pad and pad.pressed(pad.button_index("d_right"))) then
		input_dir = "right"
	end

	if input_dir then
		local expected = state.combo_sequence[state.current_step]
		if input_dir == expected then
			state.current_step = state.current_step + 1
			play_sound("wwise/events/ui/play_ui_click")

			if state.current_step > #state.combo_sequence then
				mod.unjam_weapon(wielded)
			end
		else
			state.current_step = 1
			state.error_timer = 0.4
			play_sound("wwise/events/ui/play_ui_mission_request_declined")
		end
	end
end

local function draw_rect_border(ui_renderer, pos_x, pos_y, pos_z, width, height, thickness, border_color)
	UIRenderer.draw_rect(ui_renderer, Vector3(pos_x, pos_y, pos_z), Vector3(width, thickness, 0), border_color)
	UIRenderer.draw_rect(ui_renderer, Vector3(pos_x, pos_y + height - thickness, pos_z), Vector3(width, thickness, 0), border_color)
	UIRenderer.draw_rect(ui_renderer, Vector3(pos_x, pos_y + thickness, pos_z), Vector3(thickness, height - (thickness * 2), 0), border_color)
	UIRenderer.draw_rect(ui_renderer, Vector3(pos_x + width - thickness, pos_y + thickness, pos_z), Vector3(thickness, height - (thickness * 2), 0), border_color)
end

local function draw_unjam_hud(dt, t, ui_renderer, render_settings)
	if not mod:get("enable_mod") then return end

	local state, wielded = get_wielded_slot_state()
	if not state then return end

	local is_active_jam = state.is_jammed
	local is_showing_success = state.success_timer > 0

	if not is_active_jam and not is_showing_success then return end

	mod.pulse_timer = (mod.pulse_timer or 0) + dt

	if state.error_timer > 0 then
		state.error_timer = math.max(state.error_timer - dt, 0)
	end

	if state.success_timer > 0 then
		state.success_timer = math.max(state.success_timer - dt, 0)
	end

	if mod.dpad_grace_timer > 0 then
		mod.dpad_grace_timer = math.max(mod.dpad_grace_timer - dt, 0)
	end

	local screen_w = 1920
	local screen_h = 1080
	local hud_scale_setting = (mod:get("hud_scale") or 100) / 100
	local scale = hud_scale_setting

	local hud_pos = mod:get("hud_position") or "top"
	local center_x = screen_w * 0.5
	local center_y = 235 * scale

	if hud_pos == "crosshair" then
		center_y = screen_h * 0.5 + (130 * scale)
	elseif hud_pos == "bottom" then
		center_y = screen_h - (180 * scale)
	end

	if state.error_timer > 0 then
		local shake = math.sin(t * 60) * 8 * (state.error_timer / 0.4)
		center_x = center_x + shake
	end

	local seq = state.combo_sequence
	local num_arrows = #seq > 0 and #seq or 5
	local arrow_box_size = 40 * scale
	local arrow_spacing = 8 * scale
	local padding_x = 18 * scale
	local header_h = 24 * scale
	local body_h = 56 * scale
	local total_h = header_h + body_h
	local total_w = math.max(260 * scale, (num_arrows * arrow_box_size) + ((num_arrows - 1) * arrow_spacing) + (padding_x * 2))

	local box_x = center_x - (total_w * 0.5)
	local box_y = center_y - (total_h * 0.5)
	local z_layer = 800

	local pulse = 0.5 + 0.5 * math.sin(mod.pulse_timer * 8)
	local theme_color
	local bg_color = Color(235, 12, 14, 18)

	if is_showing_success then
		theme_color = Color(255, 60, 240, 100)
	elseif state.error_timer > 0 then
		theme_color = Color(255, 255, 40, 40)
	else
		local r = math.floor(255)
		local g = math.floor(180 + 40 * pulse)
		local b = math.floor(20)
		theme_color = Color(255, r, g, b)
	end

	UIRenderer.draw_rect(ui_renderer, Vector3(box_x, box_y + header_h, z_layer), Vector3(total_w, body_h, 0), bg_color)
	local header_bg = Color(240, math.floor(theme_color[2] * 0.25), math.floor(theme_color[3] * 0.25), math.floor(theme_color[4] * 0.25))
	UIRenderer.draw_rect(ui_renderer, Vector3(box_x, box_y, z_layer), Vector3(total_w, header_h, 0), header_bg)

	draw_rect_border(ui_renderer, box_x, box_y, z_layer + 1, total_w, total_h, 2 * scale, theme_color)
	UIRenderer.draw_rect(ui_renderer, Vector3(box_x, box_y + header_h, z_layer + 1), Vector3(total_w, 1 * scale, 0), theme_color)

	local is_special_only = (mod:get("activation_lockout_mode") or "special_only") == "special_only" and wielded == "slot_primary"
	local title_text
	if is_showing_success then
		title_text = "// " .. mod:localize("unjammed_title") .. " //"
	elseif is_special_only then
		title_text = "// " .. mod:localize("special_jammed_title") .. " //"
	else
		title_text = "// " .. mod:localize("jammed_title") .. " //"
	end
	UIRenderer.draw_text(ui_renderer, title_text, 15 * scale, "proxima_nova_bold", Vector3(box_x, box_y + (2 * scale), z_layer + 2), Vector3(total_w, header_h, 0), theme_color, center_text_options)

	local total_arrows_width = (num_arrows * arrow_box_size) + ((num_arrows - 1) * arrow_spacing)
	local start_arrows_x = center_x - (total_arrows_width * 0.5)
	local arrow_y = box_y + header_h + ((body_h - arrow_box_size) * 0.5)
	local icon_size = 22 * scale
	local icon_size_vec = Vector3(icon_size, icon_size, 0)
	local icon_pivot = { icon_size * 0.5, icon_size * 0.5 }

	if is_showing_success then
		local unjam_success_msg = "WEAPON OPERATIONAL"
		UIRenderer.draw_text(ui_renderer, unjam_success_msg, 18 * scale, "proxima_nova_bold", Vector3(box_x, box_y + header_h, z_layer + 2), Vector3(total_w, body_h, 0), Color(255, 120, 255, 150), center_text_options)
	else
		for i = 1, #seq do
			local dir = seq[i]
			local angle = ARROW_ANGLES[dir] or 0
			local arrow_x = start_arrows_x + ((i - 1) * (arrow_box_size + arrow_spacing))

			local btn_bg
			local btn_border
			local symbol_color

			if i < state.current_step then
				btn_bg = Color(240, 60, 45, 10)
				btn_border = Color(255, 255, 200, 0)
				symbol_color = Color(255, 255, 215, 0)
			elseif i == state.current_step then
				local active_pulse = 0.7 + 0.3 * math.sin(mod.pulse_timer * 12)
				btn_bg = Color(240, math.floor(80 * active_pulse), math.floor(70 * active_pulse), math.floor(20 * active_pulse))
				btn_border = Color(255, 255, 255, 255)
				symbol_color = Color(255, 255, 255, 255)
			else
				btn_bg = Color(200, 22, 26, 32)
				btn_border = Color(160, 60, 65, 75)
				symbol_color = Color(160, 95, 105, 115)
			end

			UIRenderer.draw_rect(ui_renderer, Vector3(arrow_x, arrow_y, z_layer + 2), Vector3(arrow_box_size, arrow_box_size, 0), btn_bg)
			draw_rect_border(ui_renderer, arrow_x, arrow_y, z_layer + 3, arrow_box_size, arrow_box_size, 1.5 * scale, btn_border)

			local icon_pos_x = arrow_x + ((arrow_box_size - icon_size) * 0.5)
			local icon_pos_y = arrow_y + ((arrow_box_size - icon_size) * 0.5)
			local icon_pos = Vector3(icon_pos_x, icon_pos_y, z_layer + 4)

			UIRenderer.draw_texture_rotated(ui_renderer, ARROW_MATERIAL, icon_size_vec, icon_pos, angle, icon_pivot, symbol_color)
		end
	end
end

mod:hook_safe("HudElementCrosshair", "_draw_widgets", function(self, dt, t, input_service, ui_renderer, render_settings)
	poll_unjam_inputs()
	draw_unjam_hud(dt, t, ui_renderer, render_settings)
end)

local function reset_state()
	mod.slot_states.slot_primary = create_empty_slot_state()
	mod.slot_states.slot_secondary = create_empty_slot_state()
	mod.is_jammed = false
	mod.pulse_timer = 0
	mod.dpad_grace_timer = 0
	mod.waiting_for_dpad_release = false
end

mod.on_game_state_changed = function(status, state_name)
	if state_name == "StateGameplay" then
		if status == "exit" then
			reset_state()
		end
	end
end

mod.on_disabled = function()
	reset_state()
end

mod.on_unload = function()
	reset_state()
end
