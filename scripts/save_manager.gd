class_name SaveManager
extends RefCounted

const MANUAL_SLOT_COUNT := 10
const RUN_PER_PLAN_COUNT := 3
const AUTO_SLOT_COUNT := 5
const BASE_DIR := "user://saves"
const LEGACY_SEATTLE_SAVE := "user://seattle_rail_save.json"


static func ensure_map_dir(map_key: String) -> String:
	var dir_path := "%s/%s" % [BASE_DIR, map_key]
	var abs_path := ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(abs_path)
	return dir_path


static func now_timestamp_str() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(dt["year"]),
		int(dt["month"]),
		int(dt["day"]),
		int(dt["hour"]),
		int(dt["minute"]),
		int(dt["second"]),
	]


static func build_payload(
	map_key: String,
	slot_name: String,
	graph: NetworkGraph,
	pax_spawn_level: int,
	time_hours: float,
	total_delivered: int,
	weather_mode: int = 0
) -> Dictionary:
	return {
		"version": 2,
		"map_key": map_key,
		"name": slot_name,
		"saved_at": now_timestamp_str(),
		"unix_time": int(Time.get_unix_time_from_system()),
		"pax_spawn_level": pax_spawn_level,
		"time_hours": snappedf(time_hours, 0.05),
		"weather": clampi(weather_mode, 0, 2),
		"total_delivered": total_delivered,
		"network": graph.export_state(),
	}


static func current_file_path(map_key: String) -> String:
	return "%s/current.json" % ensure_map_dir(map_key)


static func slot_file_path(map_key: String, is_auto: bool, slot_idx: int) -> String:
	var prefix := "auto" if is_auto else "slot"
	return "%s/%s-%02d.json" % [ensure_map_dir(map_key), prefix, slot_idx + 1]


static func run_slot_file_path(map_key: String, plan_idx: int, sub_idx: int = 0) -> String:
	return "%s/run-slot-%02d-%d.json" % [ensure_map_dir(map_key), plan_idx + 1, sub_idx + 1]


static func _legacy_run_slot_path(map_key: String, plan_idx: int) -> String:
	return "%s/run-slot-%02d.json" % [ensure_map_dir(map_key), plan_idx + 1]


static func save_run_slot(map_key: String, plan_idx: int, run_payload: Dictionary, sub_idx: int = 0) -> bool:
	if plan_idx < 0 or plan_idx >= MANUAL_SLOT_COUNT or sub_idx < 0 or sub_idx >= RUN_PER_PLAN_COUNT:
		return false
	var copy := run_payload.duplicate(true)
	copy["plan_slot_idx"] = plan_idx
	copy["sub_idx"] = sub_idx
	copy["saved_at"] = now_timestamp_str()
	copy["unix_time"] = int(Time.get_unix_time_from_system())
	return _write_json(run_slot_file_path(map_key, plan_idx, sub_idx), copy)


static func load_run_slot(map_key: String, plan_idx: int, sub_idx: int = 0) -> Dictionary:
	if plan_idx < 0 or plan_idx >= MANUAL_SLOT_COUNT or sub_idx < 0 or sub_idx >= RUN_PER_PLAN_COUNT:
		return {}
	var p := run_slot_file_path(map_key, plan_idx, sub_idx)
	if FileAccess.file_exists(p):
		return _read_json(p)
	if sub_idx == 0:
		var lp := _legacy_run_slot_path(map_key, plan_idx)
		if FileAccess.file_exists(lp):
			return _read_json(lp)
	return {}


static func delete_run_slot(map_key: String, plan_idx: int, sub_idx: int = 0) -> void:
	if plan_idx < 0 or plan_idx >= MANUAL_SLOT_COUNT or sub_idx < 0 or sub_idx >= RUN_PER_PLAN_COUNT:
		return
	var p := run_slot_file_path(map_key, plan_idx, sub_idx)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if sub_idx == 0:
		var lp := _legacy_run_slot_path(map_key, plan_idx)
		if FileAccess.file_exists(lp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(lp))


static func get_latest_run_slot(map_key: String) -> Dictionary:
	var best_plan_idx := -1
	var best_sub_idx := 0
	var best_ts := -1
	var best_run := {}
	var best_plan := {}
	for pi in range(MANUAL_SLOT_COUNT):
		var bp := load_slot(map_key, false, pi)
		if bp.is_empty():
			continue
		for si in range(RUN_PER_PLAN_COUNT):
			var rd := load_run_slot(map_key, pi, si)
			if rd.is_empty():
				continue
			var ts := int(rd.get("unix_time", 0))
			if ts >= best_ts:
				best_ts = ts
				best_plan_idx = pi
				best_sub_idx = si
				best_run = rd
				best_plan = bp
	if best_plan_idx < 0:
		return {"exists": false}
	return {
		"exists": true,
		"slot_idx": best_plan_idx,
		"sub_idx": best_sub_idx,
		"run_data": best_run,
		"blueprint_data": best_plan,
	}


static func save_current(map_key: String, payload: Dictionary) -> bool:
	var copy := payload.duplicate(true)
	if str(copy.get("name", "")).is_empty():
		copy["name"] = L10n.t("当前进度", "Current Progress")
	copy["saved_at"] = now_timestamp_str()
	return _write_json(current_file_path(map_key), copy)


static func load_current(map_key: String) -> Dictionary:
	var p := current_file_path(map_key)
	if FileAccess.file_exists(p):
		return _normalize_loaded_data(_read_json(p), map_key)
	if map_key == "seattle" and FileAccess.file_exists(LEGACY_SEATTLE_SAVE):
		return _normalize_loaded_data(_read_json(LEGACY_SEATTLE_SAVE), map_key)
	return {}


static func delete_current(map_key: String) -> void:
	var p := current_file_path(map_key)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if map_key == "seattle" and FileAccess.file_exists(LEGACY_SEATTLE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_SEATTLE_SAVE))


static func get_current_summary(map_key: String) -> Dictionary:
	var data := load_current(map_key)
	if data.is_empty():
		return {"exists": false, "tracks": 0, "stations": 0, "lines": 0, "saved_at": ""}
	var net: Dictionary = data.get("network", {})
	var tr_cnt := (net.get("tracks", []) as Array).size()
	var st_cnt := (net.get("stations", []) as Array).size()
	var ln_cnt := (net.get("lines", []) as Array).size()
	return {
		"exists": true,
		"tracks": tr_cnt,
		"stations": st_cnt,
		"lines": ln_cnt,
		"saved_at": str(data.get("saved_at", L10n.t("最近保存", "Saved recently"))),
	}


static func save_manual_slot(map_key: String, slot_idx: int, slot_name: String, payload: Dictionary) -> bool:
	if slot_idx < 0 or slot_idx >= MANUAL_SLOT_COUNT:
		return false
	var copy := payload.duplicate(true)
	var clean_name := slot_name.strip_edges()
	if clean_name.is_empty():
		clean_name = L10n.t("手动存档 %02d", "Manual Save %02d") % (slot_idx + 1)
	copy["name"] = clean_name
	copy["saved_at"] = now_timestamp_str()
	return _write_json(slot_file_path(map_key, false, slot_idx), copy)


static func push_autosave(map_key: String, reason: String, payload: Dictionary) -> void:
	# Rotate auto-04 -> auto-05 ... auto-01 -> auto-02, newest in auto-01!
	for idx in range(AUTO_SLOT_COUNT - 1, 0, -1):
		var src := slot_file_path(map_key, true, idx - 1)
		var dst := slot_file_path(map_key, true, idx)
		if FileAccess.file_exists(src):
			var d := _read_json(src)
			if not d.is_empty():
				_write_json(dst, d)
	var copy := payload.duplicate(true)
	copy["name"] = reason if not reason.is_empty() else L10n.t("自动存档", "Autosave")
	copy["saved_at"] = now_timestamp_str()
	_write_json(slot_file_path(map_key, true, 0), copy)


static func load_slot(map_key: String, is_auto: bool, slot_idx: int) -> Dictionary:
	var max_n := AUTO_SLOT_COUNT if is_auto else MANUAL_SLOT_COUNT
	if slot_idx < 0 or slot_idx >= max_n:
		return {}
	var p := slot_file_path(map_key, is_auto, slot_idx)
	if not FileAccess.file_exists(p):
		return {}
	return _normalize_loaded_data(_read_json(p), map_key)


static func delete_slot(map_key: String, is_auto: bool, slot_idx: int) -> void:
	var p := slot_file_path(map_key, is_auto, slot_idx)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	# Cascade delete: removing a blueprint/planning save ALSO removes ALL 3 linked driving run saves!
	if not is_auto:
		for si in range(RUN_PER_PLAN_COUNT):
			delete_run_slot(map_key, slot_idx, si)


static func list_slots(map_key: String, is_auto: bool) -> Array[Dictionary]:
	var count := AUTO_SLOT_COUNT if is_auto else MANUAL_SLOT_COUNT
	var out: Array[Dictionary] = []
	for i in range(count):
		var p := slot_file_path(map_key, is_auto, i)
		if not FileAccess.file_exists(p):
			out.append({
				"index": i,
				"exists": false,
				"name": (L10n.t("自动槽位 %02d", "Auto Slot %02d") % (i + 1)) if is_auto else (L10n.t("规划槽位 %02d（空）", "Plan Slot %02d (Empty)") % (i + 1)),
				"saved_at": "",
				"tracks": 0,
				"stations": 0,
				"lines": 0,
				"has_run_save": false,
				"run_saved_at": "",
				"run_delivered": 0,
			})
		else:
			var d := _normalize_loaded_data(_read_json(p), map_key)
			var net: Dictionary = d.get("network", {})
			var default_nm := (L10n.t("自动存档 %02d", "Autosave %02d") % (i + 1)) if is_auto else (L10n.t("规划存档 %02d", "Plan Save %02d") % (i + 1))
			var run_list: Array[Dictionary] = []
			if not is_auto:
				for si in range(RUN_PER_PLAN_COUNT):
					var rd := load_run_slot(map_key, i, si)
					run_list.append({
						"sub_idx": si,
						"exists": not rd.is_empty(),
						"saved_at": str(rd.get("saved_at", "")),
						"delivered": int(rd.get("total_delivered", 0)),
					})
			out.append({
				"index": i,
				"exists": not d.is_empty(),
				"name": str(d.get("name", default_nm)),
				"saved_at": str(d.get("saved_at", "")),
				"tracks": (net.get("tracks", []) as Array).size(),
				"stations": (net.get("stations", []) as Array).size(),
				"lines": (net.get("lines", []) as Array).size(),
				"run_saves": run_list,
			})
	return out


static func _normalize_loaded_data(raw: Dictionary, map_key: String) -> Dictionary:
	if raw.is_empty():
		return {}
	if raw.has("network") and typeof(raw["network"]) == TYPE_DICTIONARY:
		return raw
	# Legacy v1 format where tracks/stations/lines were top-level keys
	if raw.has("tracks") or raw.has("stations") or raw.has("lines"):
		return {
			"version": 1,
			"map_key": map_key,
			"name": L10n.t("旧版存档", "Legacy Save"),
			"saved_at": L10n.t("旧版进度", "Legacy Progress"),
			"pax_spawn_level": 3,
			"time_hours": 13.5,
			"total_delivered": 0,
			"network": raw,
		}
	return {}


static func _write_json(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}
