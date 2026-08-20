return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`weapon_jam` mod must be lower than DMF in load order.")

		new_mod("weapon_jam", {
			mod_script       = "weapon_jam/scripts/mods/weapon_jam/weapon_jam",
			mod_data         = "weapon_jam/scripts/mods/weapon_jam/weapon_jam_data",
			mod_localization = "weapon_jam/scripts/mods/weapon_jam/weapon_jam_localization",
		})
	end,
	packages = {},
}
