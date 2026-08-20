local mod = get_mod("weapon_jam")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "group_general",
				type = "group",
				tab = mod:localize("tab_general"),
				sub_widgets = {
					{
						setting_id = "enable_mod",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "jam_chance",
						type = "numeric",
						default_value = 5.0,
						range = { 0.0, 100.0 },
						decimals_number = 1,
						step_size_value = 1.0,
					},
					{
						setting_id = "combo_length",
						type = "numeric",
						default_value = 5,
						range = { 1, 20 },
						decimals_number = 0,
						step_size_value = 1,
					},
					{
						setting_id = "allow_wasd",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "enable_sounds",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "force_jam_key",
						type = "keybind",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "on_force_jam_pressed",
					},
					{
						setting_id = "force_unjam_key",
						type = "keybind",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "on_force_unjam_pressed",
					},
				},
			},
			{
				setting_id = "group_hud",
				type = "group",
				tab = mod:localize("tab_hud"),
				sub_widgets = {
					{
						setting_id = "hud_position",
						type = "dropdown",
						default_value = "top",
						options = {
							{ text = "hud_pos_top", value = "top" },
							{ text = "hud_pos_crosshair", value = "crosshair" },
							{ text = "hud_pos_bottom", value = "bottom" },
						},
					},
					{
						setting_id = "hud_scale",
						type = "numeric",
						default_value = 100,
						range = { 50, 150 },
						decimals_number = 0,
						step_size_value = 5,
					},
				},
			},
		},
	},
}
