extends Node

const MOD_DIR = "CoopFix-OnlineDamageMeter"


func _init() -> void:
	var mod_path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_DIR)
	ModLoaderMod.install_script_extension(mod_path.plus_file("extensions/ui/hud/ui_wave_timer.gd"))
