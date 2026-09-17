extends SceneTree

const ONLINE_PATH = "ModLoader/six666-BrotatoOnline"
const PATCH_PATH = "ModLoader/CoopFix-OnlineDamageMeter"
const TIMEOUT_MSEC = 75000

var _role = ""
var _output = ""
var _expect_patch = false
var _lifecycle = false
var _player_count = 2
var _started = 0
var _done = false
var _online = null
var _session = null
var _api = null
var _run_data = null
var _menu = null
var _result = {"checks": 0, "failures": [], "stages": [], "damage_samples": []}


func _init() -> void:
	_started = OS.get_ticks_msec()
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--dm-test-role="):
			_role = arg.substr("--dm-test-role=".length())
		elif arg.begins_with("--dm-test-output="):
			_output = arg.substr("--dm-test-output=".length())
		elif arg.begins_with("--dm-test-patch="):
			_expect_patch = arg.substr("--dm-test-patch=".length()) == "installed"
		elif arg.begins_with("--dm-test-players="):
			_player_count = int(arg.substr("--dm-test-players=".length()))
		elif arg.begins_with("--dm-test-lifecycle="):
			_lifecycle = arg.substr("--dm-test-lifecycle=".length()) == "yes"
	_result["role"] = _role
	call_deferred("_run")


func _idle(_delta: float) -> bool:
	if not _done and OS.get_ticks_msec() - _started >= TIMEOUT_MSEC:
		_check(false, "75 second test timeout")
		_finish()
	return false


func _check(condition: bool, message: String) -> bool:
	_result["checks"] += 1
	if not condition:
		_result["failures"].append(message)
		printerr("DM_TEST_FAIL: ", message)
	return condition


func _stage(name: String) -> void:
	_result["stages"].append({"name": name, "elapsed_msec": OS.get_ticks_msec() - _started})
	print("DM_TEST_STAGE=", _role, ":", name)


func _barrier(name: String):
	# These isolated harness files coordinate test timing, never game state.
	yield(self, "idle_frame")
	var file = File.new()
	_check(file.open(_output.get_base_dir().plus_file(_role + "." + name), File.WRITE) == OK, "write isolated test barrier")
	file.store_string("ready")
	file.close()
	var roles = ["host"]
	for index in range(1, _player_count):
		roles.append("client" + str(index))
	while not _done:
		var ready = true
		for role in roles:
			ready = ready and file.file_exists(_output.get_base_dir().plus_file(role + "." + name))
		if ready:
			return
		yield(create_timer(0.05), "timeout")


func _run() -> void:
	yield(self, "idle_frame")
	_result["user_dir"] = OS.get_user_data_dir()
	if not _check(str(ProjectSettings.get_setting("application/config/name")).begins_with("BrotatoDamageMeterTests-"), "isolated project name"):
		_finish()
		return
	if not _check("BrotatoDamageMeterTests-" in OS.get_user_data_dir(), "isolated user data"):
		_finish()
		return
	if not _check(_output.is_abs_path() and _player_count in [2, 4] and (_role == "host" or _role.begins_with("client")), "valid test arguments"):
		_finish()
		return
	_online = get_root().get_node_or_null(ONLINE_PATH)
	if not _check(_online != null and get_root().has_node("ModLoader/lrueckert-DmgMeter"), "both real prerequisite ZIPs loaded"):
		_finish()
		return
	_result["patch_installed"] = get_root().has_node(PATCH_PATH)
	_check(_result["patch_installed"] == _expect_patch, "patch presence matches local ZIP installation")
	_session = _online.get_node("BrotatoOnlineSessionManager")
	_api = _online.get_node("BrotatoOnlineAPI")
	var steam = _online.get_node("BrotatoOnlineSteamTransport")
	steam.set("_steam", null)
	steam.set("_ready", false)
	_session.set("_steam", null)
	_session.set("_steam_ready", false)
	_check(not steam.call("is_available"), "Steam transport disabled before session creation")
	_run_data = get_root().get_node("RunData")
	_menu = get_root().get_node("MenuData")
	_run_data.call("reset")
	get_root().get_node("ProgressData").get("settings").set("retry_wave", true)
	if _role == "host":
		change_scene(str(_menu.get("character_selection_scene")))
		yield(create_timer(0.3), "timeout")
		_session.call("create_session", false)
	else:
		change_scene(str(_menu.get("title_screen_scene")))
		yield(create_timer(0.8), "timeout")
		_session.call("join_lan", "127.0.0.1", 27462)
	while not _done and (not bool(_session.call("has_active_online_session")) or int(_session.call("get_session_member_count")) < _player_count):
		yield(create_timer(0.1), "timeout")
	if _done:
		return
	_result["session_id"] = str(_session.call("get_session_id"))
	_check(bool(_session.call("is_game_host")) == (_role == "host"), "actual LAN role")
	_stage("lan_connected")
	if _role == "host":
		while int(_run_data.call("get_player_count")) < _player_count and not _done:
			yield(create_timer(0.1), "timeout")
		_run_data.call("set_player_count", _player_count, true)
		_run_data.call("set_coop_run", true)
		_run_data.set("play_mode", 1)
		_run_data.set("invulnerable", true)
		_run_data.set("current_wave", 1)
		for index in range(_player_count):
			_run_data.call("add_character", load("res://items/characters/well_rounded/well_rounded_data.tres").duplicate(), index)
			_run_data.call("add_weapon", load("res://weapons/melee/knife/1/knife_data.tres").duplicate(), index, true)
		change_scene(str(_menu.get("difficulty_selection_scene")))
		yield(create_timer(0.6), "timeout")
		var element = null
		for child in current_scene.call("_get_inventories")[0].get_children():
			var item = child.get("item")
			if item != null and item.get("value") == 0:
				element = child
				break
		if not _check(element != null, "vanilla danger 0 inventory element"):
			_finish()
			return
		_session.call("_on_host_difficulty_element_pressed", element, current_scene, 0)
	yield(_wait_battle(-1), "completed")
	if _done:
		return
	_result["local_player_indices"] = _api.call("get_local_player_indices")
	_check(_result["local_player_indices"].size() == 1, "one locally owned player")
	var start_id = int(_session.get("_pending_host_game_start_id")) if _role == "host" else int(_session.get("_last_client_game_start_commit_id"))
	_result["normal_prepare_commit"] = start_id > 0 and int(_api.call("get_context").get("battle_id", 0)) > 0
	_check(_result["normal_prepare_commit"], "normal Online prepare/ack/commit and battle generation")
	yield(_verify_damage("first-wave"), "completed")
	if _done:
		return
	yield(_barrier("first-damage"), "completed")
	if _lifecycle:
		if _role != "host" and _expect_patch:
			yield(_verify_timer_boundaries(), "completed")
		yield(_barrier("timer-boundaries"), "completed")
		var old_scene_id = current_scene.get_instance_id()
		if _role == "host":
			# Accelerate the real Timer timeout; retain vanilla/Online cleanup.
			current_scene.get("_wave_timer").start(1.5)
		while not _done and (current_scene == null or not "/shop" in str(current_scene.filename).to_lower()):
			yield(create_timer(0.1), "timeout")
		if _done:
			return
		_stage("real_shop_loaded")
		yield(_barrier("shop"), "completed")
		var menu_sync = _online.get_node("BrotatoOnlineMenuSyncManager")
		if _role == "host":
			menu_sync.call("_on_host_shop_go_pressed", 0)
		else:
			menu_sync.call("_on_client_shop_go_pressed", int(_result["local_player_indices"][0]))
		yield(_wait_battle(old_scene_id), "completed")
		if _done:
			return
		_result["next_wave_verified"] = int(_run_data.get("current_wave")) == 2
		_check(_result["next_wave_verified"], "real next wave reached")
		yield(_verify_damage("next-wave"), "completed")
		yield(_barrier("second-damage"), "completed")
		old_scene_id = current_scene.get_instance_id()
		if _role == "host":
			# Actual player deaths exercise the game's retry UI and Online votes.
			for player in current_scene.get("_players").duplicate():
				if is_instance_valid(player) and not player.get("dead"):
					player.call("die")
		while not _done:
			var retry = current_scene.get_node_or_null("UI/RetryWave") if current_scene != null else null
			if retry != null and retry.visible:
				break
			yield(create_timer(0.1), "timeout")
		if _done:
			return
		_stage("real_retry_ui_loaded")
		yield(_barrier("retry-ui"), "completed")
		_session.call("_on_online_retry_wave_confirm_pressed")
		yield(_wait_battle(old_scene_id), "completed")
		if _done:
			return
		_result["retry_verified"] = int(_run_data.get("retries")) > 0 and int(_run_data.get("current_wave")) == 2
		_check(_result["retry_verified"], "real synchronized retry reloaded this wave")
		yield(_verify_damage("retry-wave"), "completed")
		yield(_barrier("retry-damage"), "completed")
	yield(VisualServer, "frame_post_draw")
	var screenshot = get_root().get_texture().get_data()
	screenshot.flip_y()
	_result["screenshot"] = _output.get_basename() + ".png"
	_check(screenshot.save_png(_result["screenshot"]) == OK, "actual battle screenshot saved")
	_check(not _session.get("_last_battle_snapshot_sent_tick_by_steam_id").empty() if _role == "host" else int(_session.get("_last_client_battle_snapshot_rx_tick")) >= 0, "real LAN battle snapshots exchanged")
	yield(_barrier("finished"), "completed")
	_finish()


func _wait_battle(previous_scene_id: int):
	# Always yield once so callers can await the function even if already ready.
	yield(self, "idle_frame")
	while not _done:
		if current_scene != null and current_scene.filename == "res://main.tscn" and current_scene.get_instance_id() != previous_scene_id:
			var label = current_scene.get("_wave_timer_label")
			var timer = current_scene.get("_wave_timer")
			if label != null and timer != null and timer.time_left > 1.0 and (_role == "host" or label.get("wave_timer") == null):
				return
		yield(create_timer(0.1), "timeout")


func _verify_damage(name: String):
	yield(self, "idle_frame")
	var owned = _api.call("get_local_player_indices")
	if not _check(owned.size() == 1, name + " one owned player slot"):
		_finish()
		return
	var player = current_scene.get("_players")[int(owned[0])]
	# Disable automatic weapon attacks so the exact damage delta is observable.
	for p in current_scene.get("_players"):
		p.get("current_stats").set("health", 1000)
		for weapon in p.get("current_weapons"):
			weapon.set_process(false)
			weapon.set_physics_process(false)
	var weapon = player.get("current_weapons")[0]
	var label = current_scene.get("_wave_timer_label")
	var containers = label.get("dmg_meter_containers")
	var container = containers[int(owned[0])]
	var meter_item = container.get_child(0)
	var enemy = null
	while not _done and enemy == null:
		for candidate in current_scene.get("_entity_spawner").get("enemies"):
			if is_instance_valid(candidate) and not candidate.get("dead") and not candidate.get("_pending_die"):
				enemy = candidate
				break
		if enemy == null:
			yield(create_timer(0.1), "timeout")
	if _done:
		return
	var counter_before = int(meter_item.call("get_dmg_dealt"))
	_check(meter_item.get("item") == _run_data.call("get_player_weapons", int(owned[0]))[0], name + " HUD uses this wave's actual weapon resource")
	if name != "first-wave":
		_check(counter_before == 0, name + " fresh scene reset per-wave weapon damage before test hit")
	enemy.get("current_stats").set("health", 1000)
	var health_before = int(enemy.get("current_stats").get("health"))
	var hitbox = weapon.get("_hitbox")
	hitbox.set("active", true)
	hitbox.set("crit_chance", 0.0)
	hitbox.get("ignored_objects").clear()
	# Real hurtbox entry calls take_damage and the real weapon's hit signal.
	enemy.call("hurt_area_entered_deferred", hitbox)
	var health_loss = health_before - int(enemy.get("current_stats").get("health"))
	var counter_after_hit = int(meter_item.call("get_dmg_dealt"))
	_check(health_loss > 0, name + " actual enemy HP decreased")
	_check(counter_after_hit - counter_before == health_loss, name + " real weapon damage counter equals HP loss")
	yield(create_timer(0.8), "timeout")
	if _done:
		return
	var counter = int(meter_item.call("get_dmg_dealt"))
	var displayed = str(meter_item.get("dmg_label").text)
	var expected = str(get_root().get_node("Text").call("get_formatted_number", counter))
	var should_refresh = _role == "host" or _expect_patch
	_check(counter > 0, name + " local get_dmg_dealt is nonzero")
	_check(displayed == expected if should_refresh else displayed != expected, name + (" original HUD refreshed correctly" if should_refresh else " unpatched client HUD bug reproduced"))
	if should_refresh:
		_check(container.visible and meter_item.is_visible_in_tree(), name + " original local damage HUD is visible")
	if _role != "host":
		_check(label.get("wave_timer") == null, name + " Online label remains detached from local timer")
	_result["damage_samples"].append({"stage": name, "player_index": int(owned[0]), "health_loss": health_loss, "counter_before": counter_before, "counter_after_hit": counter_after_hit, "get_dmg_dealt": counter, "displayed": displayed, "expected": expected, "should_refresh": should_refresh, "container_visible": container.visible})
	_stage(name + "_damage_verified")


func _verify_timer_boundaries():
	var label = current_scene.get("_wave_timer_label")
	var timer = current_scene.get("_wave_timer")
	var countdown = label.text
	var remaining = timer.time_left
	var nodes = [_online] + _online.get_children()
	var processes = []
	# Suspend only this isolated client's networking during synthetic edge cases.
	for node in nodes:
		processes.append(node.is_processing())
		node.set_process(false)
	current_scene.set("_wave_timer", null)
	label.call("dmgmeter_update")
	_check(not label.get("dmg_meter_containers").empty(), "null Main timer safely leaves original containers intact")
	current_scene.set("_wave_timer", timer)
	timer.paused = true
	var paused_left = timer.time_left
	label.call("dmgmeter_update")
	yield(create_timer(0.3), "timeout")
	_check(abs(timer.time_left - paused_left) < 0.01, "patch preserves paused countdown")
	_check(label.text == countdown and label.get("wave_timer") == null, "patch never overwrites host countdown label or reattaches timer")
	timer.paused = false
	timer.stop()
	label.call("dmgmeter_update")
	var hide_timer = label.get("hide_dmg_meter_timer")
	var first_hide_left = hide_timer.time_left
	yield(create_timer(0.6), "timeout")
	label.call("dmgmeter_update")
	_check(hide_timer.time_left < first_hide_left - 0.3, "ended-wave polling does not repeatedly restart hide timer")
	yield(create_timer(1.6), "timeout")
	for container in label.get("dmg_meter_containers"):
		_check(not container.visible, "ended wave hides original container after delay")
	timer.start(15.0)
	label.call("dmgmeter_update")
	for container in label.get("dmg_meter_containers"):
		_check(container.visible, "same-scene timer restart resumes original container")
	timer.stop()
	label.call("dmgmeter_update")
	yield(create_timer(0.1), "timeout")
	timer.start(15.0)
	label.call("dmgmeter_update")
	_check(hide_timer.is_stopped(), "same-scene restart cancels pending hide")
	yield(create_timer(2.1), "timeout")
	for container in label.get("dmg_meter_containers"):
		_check(container.visible, "cancelled delayed hide cannot hide restarted wave")
	_check(not label.get("dmg_meter_timer").is_stopped(), "client's original half-second polling remains active")
	timer.start(max(remaining - 5.0, 3.0))
	for index in range(nodes.size()):
		nodes[index].set_process(processes[index])
	_result["timer_boundaries_verified"] = true
	_stage("timer_boundaries_verified")


func _finish() -> void:
	if _done:
		return
	_done = true
	_result["elapsed_msec"] = OS.get_ticks_msec() - _started
	_result["passed"] = _result["failures"].empty()
	if _output.is_abs_path():
		var file = File.new()
		if file.open(_output, File.WRITE) == OK:
			file.store_string(JSON.print(_result, "\t"))
			file.close()
		else:
			_result["passed"] = false
	print("DAMAGE_METER_TEST_RESULT=", JSON.print(_result))
	if _role == "host" and bool(_result["passed"]):
		yield(create_timer(0.5), "timeout")
	quit(0 if bool(_result["passed"]) else 1)
