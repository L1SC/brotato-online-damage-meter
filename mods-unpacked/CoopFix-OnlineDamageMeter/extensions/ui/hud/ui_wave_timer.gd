extends "res://ui/hud/ui_wave_timer.gd"

var _online_damage_meter_wave_active = false
var _online_damage_meter_hide_pending = false


func dmgmeter_update() -> void:
	var containers = get("dmg_meter_containers")
	var hide_timer = get("hide_dmg_meter_timer")
	var meter_timer = get("dmg_meter_timer")
	if typeof(containers) != TYPE_ARRAY:
		return

	var apis = get_tree().get_nodes_in_group("brotato_online_api")
	var is_client = not apis.empty() and apis[0].is_client()
	var actual_timer = get("wave_timer")
	if is_client:
		var main = get_tree().current_scene
		if main == null or main.filename != "res://main.tscn":
			return
		# Main's onready members are not initialized during its children's _ready.
		actual_timer = main.get("_wave_timer")
		if actual_timer == null or not is_instance_valid(actual_timer):
			return
	if actual_timer == null or not is_instance_valid(actual_timer):
		return

	# Online deliberately clears this label's wave_timer. Never reattach it:
	# the label must continue displaying Online's Host-synchronized countdown.
	if actual_timer.time_left > 0.0:
		_online_damage_meter_wave_active = true
		_online_damage_meter_hide_pending = false
		if hide_timer != null:
			hide_timer.stop()
		for container in containers:
			if is_instance_valid(container):
				container.visible = true
				container.trigger_element_updates()
	elif _online_damage_meter_wave_active:
		_online_damage_meter_wave_active = false
		_online_damage_meter_hide_pending = true
		if hide_timer != null:
			hide_timer.start()
		if not is_client and meter_timer != null:
			meter_timer.stop()
	if _online_damage_meter_hide_pending and hide_timer != null and hide_timer.is_stopped():
		for container in containers:
			if is_instance_valid(container):
				container.visible = false
		_online_damage_meter_hide_pending = false
	# Keep the client's existing half-second polling alive so a same-scene
	# timer restart can resume the meter and cancel a pending hide.
