class_name L10n
extends RefCounted

const SETTINGS_PATH := "user://settings.json"

# lang_pref: "auto" | "zh" | "en"
static var lang_pref: String = "auto"
# Resolved active language: "zh" | "en"
static var lang: String = "zh"
static var _initialized: bool = false


static func detect_system_lang() -> String:
	var loc := ""
	if OS.has_method("get_locale"):
		loc = str(OS.get_locale()).to_lower()
	if loc.is_empty() and OS.has_method("get_locale_language"):
		loc = str(OS.get_locale_language()).to_lower()
	if loc.begins_with("zh"):
		return "zh"
	return "en"


static func init_from_settings() -> void:
	if _initialized:
		return
	_initialized = true
	var pref := "auto"
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var saved_p := str((parsed as Dictionary).get("lang", "auto")).to_lower()
				if saved_p in ["auto", "zh", "en"]:
					pref = saved_p
	lang_pref = pref
	lang = detect_system_lang() if pref == "auto" else pref


static func set_language(pref: String) -> void:
	_initialized = true
	var p := pref.to_lower()
	if not (p in ["auto", "zh", "en"]):
		p = "auto"
	lang_pref = p
	lang = detect_system_lang() if p == "auto" else p
	_save_settings()


static func _save_settings() -> void:
	var data := {}
	if FileAccess.file_exists(SETTINGS_PATH):
		var rf := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if rf != null:
			var parsed = JSON.parse_string(rf.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				data = parsed
	data["lang"] = lang_pref
	var wf := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if wf != null:
		wf.store_string(JSON.stringify(data, "\t"))


static func is_en() -> bool:
	if not _initialized:
		init_from_settings()
	return lang == "en"


static func t(zh: String, en: String) -> String:
	if not _initialized:
		init_from_settings()
	return en if lang == "en" else zh


static func model_name(spec: Dictionary) -> String:
	if is_en():
		var en_n := str(spec.get("name_en", ""))
		if not en_n.is_empty():
			return en_n
	return str(spec.get("name_zh", spec.get("name_en", spec.get("key", "Tram"))))


static func model_origin(spec: Dictionary) -> String:
	var orig := str(spec.get("origin", ""))
	if not is_en():
		return orig
	var map := {
		"美国 · 北美主力轻轨": "USA · North America LRV",
		"捷克/美国 · 西雅图街车": "Czechia/USA · Seattle Streetcar",
		"中国 · 100%低地板": "China · 100% Low-Floor",
		"中国 · 广州木棉号": "China · Guangzhou Kapok",
		"法国 · 欧洲全景电车": "France · European Panoramic",
		"德国 · 慕尼黑/多哈款": "Germany · Munich/Doha",
		"日本 · 现代黑金轻轨": "Japan · Modern Black-Gold LRV",
		"日本 · 路面低地板": "Japan · Low-Floor Streetcar",
		"美国 · 1936 传奇流线电车": "USA · 1936 Streamlined Classic",
		"中国 · 1935 历史木质老电车": "China · 1935 Historic Wooden Tram",
		"葡萄牙 · 1930 经典山城电车": "Portugal · 1930 Hilltop Classic",
		"美国 · 1923 圣查尔斯老电车": "USA · 1923 St. Charles Streetcar",
		"德国 · 1924 魏玛时代电车": "Germany · 1924 Weimar Era",
		"日本 · 1942 昭和古董电车": "Japan · 1942 Showa Vintage",
		"美国 · 1962 西雅图世博会 Alweg 跨座式单轨": "USA · 1962 World's Fair Alweg Monorail",
		"现代 · 无人驾驶跨座式单轨": "Modern · Automated Straddle Monorail",
	}
	if map.has(orig):
		return map[orig]
	return orig


static func station_display_name(raw_name: String) -> String:
	if not is_en():
		return raw_name
	var exact := {
		"西湖中心站（单轨）": "Westlake Center (Monorail)",
		"西雅图中心站（单轨）": "Seattle Center (Monorail)",
		"新路口 站": "New Junction Sta.",
		"新建道路 站": "New Road Sta.",
		"站台": "Platform",
		"无车站": "No Stations",
	}
	if exact.has(raw_name):
		return exact[raw_name]
	var s := raw_name
	s = s.replace("（单轨）", " (Monorail)").replace("(单轨)", " (Monorail)")
	s = s.replace("新路口", "New Junction").replace("新建道路", "New Road").replace("专用轨道", "Dedicated Track")
	if s.ends_with(" 站"):
		s = s.substr(0, s.length() - 2) + " Sta."
	elif s.ends_with("站") and s.length() > 1:
		s = s.substr(0, s.length() - 1) + " Sta."
	return s


static func line_display_name(raw_name: String) -> String:
	if not is_en():
		return raw_name
	if raw_name == "西雅图中心单轨":
		return "Seattle Center Monorail"
	if raw_name.ends_with("号线") and raw_name.length() > 2:
		var num_part := raw_name.substr(0, raw_name.length() - 2)
		if num_part.is_valid_int():
			return "Line " + num_part
	return raw_name


static func street_display_name(raw_name: String) -> String:
	if not is_en():
		return raw_name
	if raw_name == "新建道路":
		return "New Road"
	if raw_name == "专用轨道":
		return "Dedicated Track"
	if raw_name == "新路口":
		return "New Junction"
	return raw_name
