"""Street-level survey of the T1 tram corridor (Nov 2026), read by eye off the Amap standard map (merchants)
and satellite layer (road widths, land use) stop by stop. Positions are game metres (x east, y south) given as
an anchor (a graph junction or a tram stop as placed in data/jiaxing.json) plus the offset measured on the map
(Amap zoom 17.5: 100 m = 140 px), so they stay put if the map projection is regenerated.

Used by tools/build_jiaxing_map.py: T1_ROAD_WIDTHS when it widens the tram boulevards, the rest after the
storefronts are laid out."""

# Real cross-sections (kerb to kerb, tram median included) measured on the satellite layer
#   纺工路 ~45 m (3 + 3 lanes, planted tram median, 机非隔离带), 庆丰路 ~32 m, 由拳路 ~28 m
T1_ROAD_WIDTHS = {
    "纺工路": (40.0, 3, 1.5),   # width, motor lanes per direction, planted bike buffer
    "庆丰路": (32.0, 3, 0.0),
    "由拳路": (28.0, 2, 0.0),
}

_A = {
    "s4_jct": (3255.0, 2532.0),   # 双溪路 & 由拳路
    "s5_jct": (2342.0, 2540.0),   # 商务大道 & 由拳路
    "s6_jct": (1411.0, 2520.0),   # 纺工路 & 由拳路
    "s7_stop": (1433.0, 1532.0),  # 嘉兴一中站
    "s8_jct": (1268.0, 686.0),    # 烟雨路 & 纺工路
    "s9_jct": (1168.0, 119.0),    # 南溪西路 & 纺工路
    "s10_stop": (1129.0, -307.0), # 纺工路景湖路站
    "s11_jct": (977.0, -1040.0),  # 东方路 & 甪里街 (north bank of 平湖塘)
}


def _at(anchor, dx, dy):
    ax, ay = _A[anchor]
    return (round(ax + dx, 1), round(ay + dy, 1))


# (name, OSM-style kind, brand key for the sign palette or "", position)
REAL_SHOPS = [
    # 纺工路由拳路: low-rise row SE of the junction
    ("南门高老太土菜馆", "restaurant", "", _at("s6_jct", 39, 32)),
    ("音品汇汽车音响", "service", "", _at("s6_jct", 48, 66)),
    ("宏伟贴膜", "service", "", _at("s6_jct", 169, 34)),
    # 嘉兴一中站: 纺工路 west frontage (翰林府第 podium), north to south
    ("捷安特", "bicycle", "", _at("s7_stop", -83, -216)),
    ("顾小芒", "cafe", "", _at("s7_stop", -74, -168)),
    ("卡萨帝旗舰店", "electronics", "", _at("s7_stop", -67, -135)),
    ("罗森", "convenience", "罗森便利店", _at("s7_stop", -54, -56)),
    ("五芳斋", "restaurant", "五芳斋", _at("s7_stop", -45, -8)),
    ("雨露空间", "convenience", "", _at("s7_stop", -38, 35)),
    # 纺工路烟雨路站
    ("广寒宫足道", "beauty", "", _at("s8_jct", 60, 42)),
    ("中国农业银行", "bank", "农业银行", _at("s8_jct", 60, 82)),
    ("长盈阁", "restaurant", "", _at("s8_jct", 65, 107)),
    ("COLMO智感体验馆", "electronics", "", _at("s8_jct", 75, 177)),
    ("中国银行", "bank", "中国银行", _at("s8_jct", -27, 113)),
    ("元祖", "bakery", "", _at("s8_jct", -12, 185)),
    # 纺工路南溪西路站
    ("如家派柏·云酒店", "hotel", "", _at("s9_jct", 14, -45)),
    # 纺工路景湖路站: east frontage
    ("万家福超市", "supermarket", "", _at("s10_stop", 14, -40)),
    ("惠耳听力助听器", "service", "", _at("s10_stop", 46, 82)),
    ("嘉兴老百姓药房", "pharmacy", "", _at("s10_stop", 29, 114)),
    ("嘉兴自家宾馆", "hotel", "", _at("s10_stop", 31, 163)),
    # 纺工路滨河路站
    ("工会驿站", "service", "", _at("s11_jct", 46, 64)),
    ("世友房产", "office", "", _at("s11_jct", -18, 150)),
    ("好万家超市", "supermarket", "", _at("s11_jct", 40, 262)),
    # 由拳路商务大道站
    ("日立中央空调", "electronics", "", _at("s5_jct", 242, 45)),
    ("盛美口腔", "dentist", "", _at("s5_jct", 182, 105)),
    # 由拳路双溪路站: shops along the south side of 由拳路
    ("爱玛电动车", "bicycle", "", _at("s4_jct", -24, 44)),
    ("美俪家族", "beauty", "", _at("s4_jct", -231, 41)),
    ("忆味桐乡煲", "restaurant", "", _at("s4_jct", -188, 85)),
    ("雅迪电动车", "bicycle", "", _at("s4_jct", -183, 120)),
    ("久久五金店", "hardware", "", _at("s4_jct", -212, 161)),
    ("老仙配镜厂", "optician", "", _at("s4_jct", -250, -33)),
    ("华莱士·全鸡汉堡", "fast_food", "", _at("s4_jct", -39, -204)),
    ("罗数培训学校", "office", "", _at("s4_jct", -32, -177)),
]

# Frontages that are really campus walls, office parks, hospitals or gated-compound fences: no street shops
# (x0, y0, x1, y1) in game metres
NO_SHOP_BOXES = [
    (1432.0, 2290.0, 1620.0, 2508.0),   # 纺工路由拳路 NE: 浙江蓝洋电子 / 大都市装饰 office campus
    (1445.0, 1240.0, 1640.0, 1600.0),   # 嘉兴一中 campus east of 纺工路
    (1185.0, 180.0, 1330.0, 420.0),     # 浙江红船干部学院 SE of 南溪西路
    (780.0, -1010.0, 968.0, -620.0),    # 嘉兴市公安局监所支队 / 海警医院 west of 纺工路 at 滨河路
    (4120.0, 3380.0, 4360.0, 3700.0),   # 庆丰路长水路: four gated compounds (万科臻境雅园, 万科泊樾湾 ...)
]

# Office / institutional campuses the generator filled with residential towers: cap height and re-kind
# (x0, y0, x1, y1, max height m, kind, colour)
CAMPUS_BOXES = [
    (1432.0, 2290.0, 1620.0, 2508.0, 24.0, "office", "#c9cdd2"),
    (780.0, -1010.0, 968.0, -620.0, 30.0, "hospital", "#e9e6df"),
]
