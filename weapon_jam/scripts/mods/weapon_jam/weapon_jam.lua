local mod = get_mod("weapon_jam")
local UIRenderer = require("scripts/managers/ui/ui_renderer")

mod.is_jammed = false
mod.combo_sequence = {}
mod.current_step = 1
mod.last_dryfire_time = 0
mod.error_timer = 0
mod.success_timer = 0
mod.pulse_timer = 0

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

local function get_local_player_unit()
	local player = Managers.player and Managers.player:local_player(1)
	return player and player.player_unit
end

local function is_local_player_wielding_ranged()
	local unit = get_local_player_unit()
	if not unit or not Unit.alive(unit) then return false end
	local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data_ext then return false end
	local inventory_component = unit_data_ext:read_component("inventory")
	return inventory_component and inventory_component.wielded_slot == "slot_secondary"
end

local function generate_combo(length)
	local seq = {}
	for i = 1, length do
		seq[i] = DIRECTIONS[math.random(1, #DIRECTIONS)]
	end
	return seq
end

mod.jam_weapon = function()
	if not mod:get("enable_mod") then return end
	if mod.is_jammed then return end

	local length = math.floor(mod:get("combo_length") or 5)
	mod.combo_sequence = generate_combo(length)
	mod.current_step = 1
	mod.is_jammed = true
	mod.error_timer = 0
	mod.success_timer = 0

	play_sound("wwise/events/ui/play_hud_notifications_warning")
end

mod.unjam_weapon = function()
	mod.is_jammed = false
	mod.combo_sequence = {}
	mod.current_step = 1
	mod.success_timer = 1.2

	play_sound("wwise/events/ui/play_hud_ability_off_cooldown")
end

mod.on_force_jam_pressed = function()
	if mod.is_jammed then
		mod.unjam_weapon()
	else
		mod.jam_weapon()
	end
end

local function check_jam_on_shoot(action_instance)
	if not mod:get("enable_mod") or mod.is_jammed then return end

	local player_unit = action_instance._player_unit
	local local_unit = get_local_player_unit()
	if not player_unit or player_unit ~= local_unit then return end

	if not is_local_player_wielding_ranged() then return end

	local jam_chance = mod:get("jam_chance")
	if jam_chance == nil then
		jam_chance = 5.0
	end
	local roll = math.random() * 100.0
	if roll < jam_chance then
		mod.jam_weapon()
	end
end

mod:hook_safe("ActionShoot", "start", function(self)
	check_jam_on_shoot(self)
end)

mod:hook_safe("ActionSpawnProjectile", "start", function(self)
	check_jam_on_shoot(self)
end)

mod:hook("ActionHandler", "_validate_action", function(func, self, action_settings, condition_func_params, t, time_in_action, used_input)
	if mod.is_jammed and mod:get("enable_mod") then
		local unit = self._unit
		local local_unit = get_local_player_unit()
		if unit and unit == local_unit then
			local inventory_component = self._inventory_component
			if inventory_component and inventory_component.wielded_slot == "slot_secondary" then
				local kind = action_settings and action_settings.kind
				if kind and SHOOT_ACTION_KINDS[kind] then
					if t and (t - mod.last_dryfire_time > 0.25) then
						mod.last_dryfire_time = t
						play_sound("wwise/events/ui/play_ui_click")
					end
					return false
				end
			end
		end
	end

	return func(self, action_settings, condition_func_params, t, time_in_action, used_input)
end)

local function poll_unjam_inputs()
	if not mod.is_jammed or not mod:get("enable_mod") then return end
	if not is_local_player_wielding_ranged() then return end

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
		local expected = mod.combo_sequence[mod.current_step]
		if input_dir == expected then
			mod.current_step = mod.current_step + 1
			play_sound("wwise/events/ui/play_ui_click")

			if mod.current_step > #mod.combo_sequence then
				mod.unjam_weapon()
			end
		else
			mod.current_step = 1
			mod.error_timer = 0.4
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

	local is_active_jam = mod.is_jammed and is_local_player_wielding_ranged()
	local is_showing_success = mod.success_timer > 0

	if not is_active_jam and not is_showing_success then return end

	mod.pulse_timer = (mod.pulse_timer or 0) + dt

	if mod.error_timer > 0 then
		mod.error_timer = math.max(mod.error_timer - dt, 0)
	end

	if mod.success_timer > 0 then
		mod.success_timer = math.max(mod.success_timer - dt, 0)
	end

	local screen_w = 1920
	local screen_h = 1080
	local hud_scale_setting = (mod:get("hud_scale") or 100) / 100
	local scale = hud_scale_setting

	local hud_pos = mod:get("hud_position") or "top"
	local center_x = screen_w * 0.5
	local center_y = 150 * scale

	if hud_pos == "crosshair" then
		center_y = screen_h * 0.5 + (130 * scale)
	elseif hud_pos == "bottom" then
		center_y = screen_h - (180 * scale)
	end

	if mod.error_timer > 0 then
		local shake = math.sin(t * 60) * 8 * (mod.error_timer / 0.4)
		center_x = center_x + shake
	end

	local seq = mod.combo_sequence
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
	elseif mod.error_timer > 0 then
		theme_color = Color(255, 255, 40, 40)
	else
		local r = math.floor(255)
		local g = math.floor(180 + 40 * pulse)
		local b = math.floor(20)
		theme_color = Color(255, r, g, b)
	end

	-- 1. Main Background and Header Background
	UIRenderer.draw_rect(ui_renderer, Vector3(box_x, box_y + header_h, z_layer), Vector3(total_w, body_h, 0), bg_color)
	local header_bg = Color(240, math.floor(theme_color[2] * 0.25), math.floor(theme_color[3] * 0.25), math.floor(theme_color[4] * 0.25))
	UIRenderer.draw_rect(ui_renderer, Vector3(box_x, box_y, z_layer), Vector3(total_w, header_h, 0), header_bg)

	-- 2. Border
	draw_rect_border(ui_renderer, box_x, box_y, z_layer + 1, total_w, total_h, 2 * scale, theme_color)
	UIRenderer.draw_rect(ui_renderer, Vector3(box_x, box_y + header_h, z_layer + 1), Vector3(total_w, 1 * scale, 0), theme_color)

	-- 3. Header Text
	local title_text = is_showing_success and "// " .. mod:localize("unjammed_title") .. " //" or "// " .. mod:localize("jammed_title") .. " //"
	UIRenderer.draw_text(ui_renderer, title_text, 15 * scale, "proxima_nova_bold", Vector3(box_x, box_y + (2 * scale), z_layer + 2), Vector3(total_w, header_h, 0), theme_color, center_text_options)

	-- 4. Arrow Sequence Buttons (Helldivers Stratagem Style)
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

			if i < mod.current_step then
				-- Completed Arrow: Glowing Helldivers Gold
				btn_bg = Color(240, 60, 45, 10)
				btn_border = Color(255, 255, 200, 0)
				symbol_color = Color(255, 255, 215, 0)
			elseif i == mod.current_step then
				-- Active Arrow: Flashing White / Highlighted
				local active_pulse = 0.7 + 0.3 * math.sin(mod.pulse_timer * 12)
				btn_bg = Color(240, math.floor(80 * active_pulse), math.floor(70 * active_pulse), math.floor(20 * active_pulse))
				btn_border = Color(255, 255, 255, 255)
				symbol_color = Color(255, 255, 255, 255)
			else
				-- Remaining Arrow: Dimmed Steel Grey
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
	mod.is_jammed = false
	mod.combo_sequence = {}
	mod.current_step = 1
	mod.error_timer = 0
	mod.success_timer = 0
	mod.pulse_timer = 0
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
