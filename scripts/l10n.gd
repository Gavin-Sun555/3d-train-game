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
		"中国 · 嘉兴T1线南湖号(5模块)": "China · Jiaxing T1 Nanhu (5-Car)",
	}
	if map.has(orig):
		return map[orig]
	return orig


# Always returns an authentic, natural English station name for English UI & English/Bilingual TTS
# so English voice synthesis NEVER skips Chinese Unicode station names!
static func station_en_name(raw_name: String) -> String:
	var key := raw_name.strip_edges()
	var exact := {
		"西湖中心站（单轨）": "Westlake Center (Monorail)",
		"西雅图中心站（单轨）": "Seattle Center (Monorail)",
		"新路口 站": "New Junction Station",
		"新建道路 站": "New Road Station",
		"站台": "Platform",
		"无车站": "No Stations",
		# Authentic Jiaxing Tram Line T1 (all 15 operational stations matching official Amap names!)
		"嘉兴南站": "Jiaxing South Railway Station",
		"有轨电车庆丰路基地站": "Qingfeng Road Tram Depot",
		"庆丰路基地": "Qingfeng Road Tram Depot",
		"庆丰路基地站": "Qingfeng Road Tram Depot",
		"庆丰路长水路站": "Qingfeng Road and Changshui Road",
		"庆丰路长水路": "Qingfeng Road and Changshui Road",
		"由拳路双溪路站": "Youquan Road and Shuangxi Road",
		"由拳路双溪路": "Youquan Road and Shuangxi Road",
		"由拳路商务大道站": "Youquan Road and Shangwu Avenue",
		"由拳路商务大道": "Youquan Road and Shangwu Avenue",
		"纺工路由拳路站": "Fanggong Road and Youquan Road",
		"纺工路由拳路": "Fanggong Road and Youquan Road",
		"纺工路由拳路（中央公园）": "Fanggong Road and Youquan Road, Central Park",
		"嘉兴一中站": "Jiaxing Number One High School",
		"嘉兴一中": "Jiaxing Number One High School",
		"纺工路烟雨路站": "Fanggong Road and Yanyu Road",
		"纺工路烟雨路": "Fanggong Road and Yanyu Road",
		"纺工路南溪西路站": "Fanggong Road and Nanxi West Road",
		"纺工路南溪西路": "Fanggong Road and Nanxi West Road",
		"纺工路南溪西路（南湖湖滨）": "Fanggong Road and Nanxi West Road, Nanhu Lakeside",
		"纺工路景湖路站": "Fanggong Road and Jinghu Road",
		"纺工路景湖路": "Fanggong Road and Jinghu Road",
		"纺工路滨河路站": "Fanggong Road and Binhe Road",
		"纺工路滨河路": "Fanggong Road and Binhe Road",
		"嘉兴火车站": "Jiaxing Railway Station",
		"人民公园": "People's Park",
		"人民公园站": "People's Park",
		"中山东路建国南路(瓶山)": "Zhongshan East Road and Jianguo South Road, Pingshan",
		"中山东路建国南路（瓶山）": "Zhongshan East Road and Jianguo South Road, Pingshan",
		"中山东路建国南路站": "Zhongshan East Road and Jianguo South Road",
		"中山东路禾兴南路": "Zhongshan East Road and Hexing South Road",
		"中山东路禾兴南路站": "Zhongshan East Road and Hexing South Road",
		"中山东路安乐路": "Zhongshan East Road and Anle Road",
		"中山东路安乐路站": "Zhongshan East Road and Anle Road",
		"中山东路安乐路（旭辉广场）": "Zhongshan East Road and Anle Road, CIFI Plaza",
	}
	if exact.has(key):
		return exact[key]

	var s := key
	s = s.replace("（单轨）", " (Monorail)").replace("(单轨)", " (Monorail)")
	s = s.replace("新路口", "New Junction").replace("新建道路", "New Road").replace("专用轨道", "Dedicated Track")
	# Common Jiaxing road & landmark terms for player-built stations on Jiaxing map
	var terms := [
		["中山东路", "Zhongshan East Road"], ["中山西路", "Zhongshan West Road"],
		["南溪西路", "Nanxi West Road"], ["南溪东路", "Nanxi East Road"],
		["建国南路", "Jianguo South Road"], ["建国北路", "Jianguo North Road"],
		["禾兴南路", "Hexing South Road"], ["禾兴北路", "Hexing North Road"],
		["环城东路", "Huancheng East Road"], ["环城西路", "Huancheng West Road"],
		["环城南路", "Huancheng South Road"], ["环城北路", "Huancheng North Road"],
		["中环南路", "Zhonghuan South Road"], ["中环东路", "Zhonghuan East Road"],
		["中环西路", "Zhonghuan West Road"], ["中环北路", "Zhonghuan North Road"],
		["三环南路", "Sanhuan South Road"], ["三环东路", "Sanhuan East Road"],
		["庆丰路", "Qingfeng Road"], ["由拳路", "Youquan Road"], ["纺工路", "Fanggong Road"],
		["长水路", "Changshui Road"], ["双溪路", "Shuangxi Road"], ["商务大道", "Shangwu Avenue"],
		["烟雨路", "Yanyu Road"], ["景湖路", "Jinghu Road"], ["滨河路", "Binhe Road"],
		["勤俭路", "Qinjian Road"], ["安乐路", "Anle Road"], ["百川路", "Baichuan Road"],
		["五环洞路", "Wuhuandong Road"], ["富润路", "Furun Road"], ["广益路", "Guangyi Road"],
		["东方路", "Dongfang Road"], ["甪里街", "Luli Street"], ["南湖大道", "Nanhu Avenue"],
		["越秀南路", "Yuexiu South Road"], ["越秀北路", "Yuexiu North Road"], ["城东路", "Chengdong Road"],
		["嘉兴支路", "Jiaxing Street"], ["嘉兴路口", "Jiaxing Junction"],
		["南湖景区", "Nanhu Scenic Area"], ["月河历史街区", "Yuehe Historic Quarter"],
		["月河", "Yuehe"], ["子城", "Zicheng"], ["湘家荡", "Xiangjiadang"],
		["人民公园", "People's Park"], ["中央公园", "Central Park"], ["植物园", "Botanical Garden"],
		["嘉兴南站", "Jiaxing South Station"], ["嘉兴火车站", "Jiaxing Railway Station"],
		["嘉兴站", "Jiaxing Station"], ["嘉兴一中", "Jiaxing No.1 High School"],
		["嘉兴", "Jiaxing"], ["南湖", "Nanhu"], ["八佰伴", "Yaohan"], ["万达广场", "Wanda Plaza"],
		["希尔顿", "Hilton"], ["山姆", "Sam's Club"], ["天主教堂", "Catholic Church"],
		["第一医院", "First Hospital"], ["第二医院", "Second Hospital"], ["中医院", "TCM Hospital"],
		["瓶山", "Pingshan"], ["旭辉广场", "CIFI Plaza"], ["高铁", "High-Speed Rail"],
		["有轨电车", "Tram"], ["基地", "Depot"], ["大道", "Avenue"], ["支路", "Branch Road"],
		["辅路", "Frontage Road"], ["辅道", "Frontage Road"], ["隧道", "Tunnel"],
		["路", " Road"], ["街", " Street"], ["桥", " Bridge"], ["站", " Station"],
		["（", " ("], ["）", ")"], ["&", "and"],
	]
	for pair in terms:
		if s.find(pair[0]) >= 0:
			s = s.replace(pair[0], " " + pair[1] + " ")
	# Collapse repeated spaces cleanly
	while s.find("  ") >= 0:
		s = s.replace("  ", " ")
	s = s.strip_edges()
	# Strip any remaining untranslated CJK characters so English TTS never stutters or goes silent
	var ascii_buf := ""
	var had_cjk := false
	for ci in range(s.length()):
		var code := s.unicode_at(ci)
		if code >= 0x4E00 and code <= 0x9FFF:
			had_cjk = true
		else:
			ascii_buf += s[ci]
	if had_cjk:
		ascii_buf = ascii_buf.strip_edges()
		if ascii_buf.length() < 3:
			return "Next Station"
		return ascii_buf
	return s


static func station_display_name(raw_name: String) -> String:
	if not is_en():
		return raw_name
	return station_en_name(raw_name)


static func line_display_name(raw_name: String) -> String:
	if not is_en():
		return raw_name
	if raw_name == "西雅图中心单轨":
		return "Seattle Center Monorail"
	if raw_name.begins_with("T1线"):
		return "Line T1 · Jiaxing South Sta. — Anle Rd"
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
