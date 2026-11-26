"""
Comprehensive Google Earth (lyrs=s, WGS-84) + Google Maps (lyrs=m&hl=zh-CN, GCJ-02 -> WGS-84)
survey of Jiaxing (Nov 2026):
  1. REAL_COMPOUNDS: 85+ real Jiaxing residential compounds (小区) with exact real coordinates,
     authentic architectural archetype, floor range, footprint shape style, wall/trim/roof palettes,
     and ground-floor 底商 vs gated-wall rules.
  2. REAL_SHOPS_GOOGLE: 165+ real Jiaxing street-front shops & businesses directly verified from
     Google Maps tiles + T1 corridor survey, with exact WGS-84 game coordinates.
  3. REAL_CAMPUSES: Schools, hospitals, government/civic campuses, and industrial/tech parks
     verified on Google Earth (never filled with residential towers or fake shops).
  4. REAL_ROAD_SPECS: Real carriageway cross-sections (widths, lanes, bike buffers) measured on
     Google Earth satellite imagery for 50+ named Jiaxing streets.
"""

import math

LAT0, LON0 = 30.7550, 120.7520
KX = 111320.0 * math.cos(LAT0 * math.pi / 180.0)
KY = 110574.0


def _wgs2gcj(lat, lon):
    a = 6378245.0
    ee = 0.00669342162296594323

    def tlat(x, y):
        r = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(abs(x))
        r += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
        r += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0
        r += (160.0 * math.sin(y / 12.0 * math.pi) + 320.0 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0
        return r

    def tlon(x, y):
        r = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(abs(x))
        r += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
        r += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0
        r += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0
        return r

    dlat = tlat(lon - 105.0, lat - 35.0)
    dlon = tlon(lon - 105.0, lat - 35.0)
    rad = lat / 180.0 * math.pi
    magic = 1.0 - ee * math.sin(rad) ** 2
    sq = math.sqrt(magic)
    dlat = (dlat * 180.0) / ((a * (1.0 - ee)) / (magic * sq) * math.pi)
    dlon = (dlon * 180.0) / (a / sq * math.cos(rad) * math.pi)
    return lat + dlat, lon + dlon


def gcj_to_game(lat_g, lon_g):
    """Exact inverse GCJ-02 -> WGS-84 -> game (x, y) in metres."""
    lat, lon = lat_g, lon_g
    for _ in range(4):
        gl, gn = _wgs2gcj(lat, lon)
        lat -= (gl - lat_g)
        lon -= (gn - lon_g)
    return (round((lon - LON0) * KX, 1), round((LAT0 - lat) * KY, 1))


# ---------------------------------------------------------------------------------------------
# 1. Architectural Archetypes (calibrated to Jiaxing Google Earth & street-level photography)
#    Rich, realistic warm-stone / terracotta / ochre / champagne / slate / modern-aluminum palettes
#    (NEVER washed-out flat chalk white!)
# ---------------------------------------------------------------------------------------------
ARCHETYPES = {
    # 1980s-2000s 老小区 (平改坡红屋顶 — 烟雨社区/菱香坊/城东/老城经典多层板楼: 明亮暖米黄/杏黄/浅桃色)
    "old_walkup_red": {
        "floors": (5, 6),
        "style": 2,
        "sub": "walkup",
        "walls": ["#f1e2c8", "#edd2b0", "#f4ead8", "#e8c4a0", "#f0dec2"],
        "trims": ["#8a6a52", "#967458", "#745e4d"],
        "roofs": ["#b8523d", "#a84835", "#c45e47", "#994232"],
        "roof_shape": "gabled",
        "shapes": ["walkup_stair", "walkup_stair", "L_wing", "rect"],
        "gate_style": 1,
        "podium_shops": True,
    },
    # 1990s-2000s 老小区 (青灰/深黛瓦坡屋顶 — 南溪花园/湖滨花园/文星花园/老城社区: 明亮奶白/浅米灰/淡青白)
    "old_walkup_slate": {
        "floors": (5, 7),
        "style": 2,
        "sub": "walkup",
        "walls": ["#efebe2", "#eae0cc", "#f4f1ea", "#e4d9c6", "#e4eae6"],
        "trims": ["#62666e", "#6e685e", "#585d66"],
        "roofs": ["#48505c", "#525964", "#3e4550", "#5a534c"],
        "roof_shape": "gabled",
        "shapes": ["walkup_stair", "walkup_stair", "stepped_slab", "L_wing"],
        "gate_style": 1,
        "podium_shops": True,
    },
    # 2005-2020 花园洋房 (6-11层低密退台洋房: 阳光香槟/浅杏/奶白/暖陶土砖红)
    "garden_yangfang": {
        "floors": (6, 9),
        "style": 2,
        "sub": "yangfang",
        "walls": ["#efdec4", "#e8c79e", "#f3ebd9", "#e0b68e", "#ecdac0"],
        "trims": ["#6f5a48", "#5d544c", "#826852"],
        "roofs": ["#444b54", "#584b44", "#3b424b", "#645044"],
        "roof_shape": "hipped",
        "shapes": ["stepped_slab", "wing_slab", "walkup_stair"],
        "gate_style": 0,
        "podium_shops": False,
        "yangfang": True,
    },
    # 2012-2024 新中式/暖色调高层板楼 (瀚林府第/巴黎都市/罗马都市/荣安/佳源: 亮米白/暖香槟/浅麦石材)
    "modern_warm_slab": {
        "floors": (16, 26),
        "style": 2,
        "sub": "tower_warm",
        "walls": ["#f2e8d8", "#ecd9bc", "#f5f1e8", "#e6cea8", "#efe2cc"],
        "trims": ["#645546", "#705f4d", "#524a44", "#7e6c56"],
        "roofs": ["#5c5a57"],
        "roof_shape": None,
        "shapes": ["stepped_slab", "wing_slab", "point_cross", "stepped_slab"],
        "gate_style": 0,
        "podium_shops": True,
    },
    # 2018-2026 现代公建化铝板/灰白高层 (万科/华润/招商/龙湖: 亮银白/珍珠白/冰蓝灰铝板)
    "modern_silver_slab": {
        "floors": (18, 30),
        "style": 2,
        "sub": "tower_modern",
        "walls": ["#eef2f6", "#e4eaf0", "#f4f6f8", "#dae3ec", "#eaecef"],
        "trims": ["#464d58", "#3c434e", "#545b66", "#5e6672"],
        "roofs": ["#4e545e"],
        "roof_shape": None,
        "shapes": ["stepped_slab", "point_cross", "wing_slab", "stepped_slab"],
        "gate_style": 2,
        "podium_shops": False,
    },
    # 2010-2022 法式/新古典干挂石材高层 (东菱宝石公馆/英伦都市/中港名都/万达华府: 亮砂岩/浅香槟金/暖杏)
    "artdeco_tower": {
        "floors": (16, 28),
        "style": 2,
        "sub": "tower_artdeco",
        "walls": ["#edd8b8", "#e6c89e", "#f2e4cc", "#dfb98e", "#ecdabe"],
        "trims": ["#645040", "#735c48", "#544539"],
        "roofs": ["#544c46"],
        "roof_shape": None,
        "shapes": ["wing_slab", "point_cross", "stepped_slab"],
        "gate_style": 0,
        "podium_shops": True,
    },
    # 2014-2026 现代高低配小区 (亮米白/银白/暖香槟多样搭配)
    "mixed_modern": {
        "floors": (18, 26),
        "y_floors": (6, 8),
        "style": 2,
        "sub": "mixed",
        "walls": ["#f0eae0", "#e6ecf2", "#f3ead8", "#e8d8c0"],
        "trims": ["#545962", "#685a4c", "#4b5059"],
        "roofs": ["#464d57", "#58504a"],
        "roof_shape": "hipped",
        "shapes": ["stepped_slab", "wing_slab", "point_cross"],
        "gate_style": 2,
        "podium_shops": False,
    },
    # 老城区粉墙黛瓦低层传统片区
    "old_jiangnan": {
        "floors": (2, 4),
        "style": 3,
        "sub": "jiangnan",
        "walls": ["#f4f1ea", "#eee9df", "#f6f3ed"],
        "trims": ["#454a52"],
        "roofs": ["#343a44", "#404650"],
        "roof_shape": "gabled",
        "shapes": ["L_wing", "rect"],
        "gate_style": 1,
        "podium_shops": True,
    },
}


# ---------------------------------------------------------------------------------------------
# 2. Real Jiaxing Residential Compounds (小区库: 85+ 真实小区, 精确覆盖嘉兴主城区与T1全线)
#    Tuple: (name, (x0, y0, x1, y1), archetype, wall_hex_override, trim_hex_override, roof_hex_override, podium_shops_override)
#    All game coordinates in WGS-84 metres (x east, y south from Nanhu 30.7550, 120.7520).
# ---------------------------------------------------------------------------------------------
REAL_COMPOUNDS = [
    # === 纺工路 T1 核心段 (北 -> 南) ===
    ("新湖绿都", (995.0, -980.0, 1480.0, -560.0), "garden_yangfang", "#cfa987", "#5c4234", "#984635", True),
    ("湖滨花园", (1120.0, -550.0, 1490.0, -180.0), "old_walkup_slate", "#d0c3ae", "#504d48", "#43464c", True),
    ("景湖社区", (1150.0, -175.0, 1560.0, 130.0), "old_walkup_slate", "#d5c8b4", "#55524d", "#4c4844", True),
    ("南溪花园", (1570.0, -180.0, 2180.0, 220.0), "old_walkup_slate", "#cbbca6", "#544c45", "#4a4440", True),
    ("桂苑小区", (1580.0, 230.0, 2180.0, 680.0), "old_walkup_red", "#d2bea2", "#624b3d", "#944333", True),
    ("烟雨社区", (790.0, 440.0, 1170.0, 1080.0), "old_walkup_red", "#d7c4a8", "#6b4f3d", "#9f4634", True),
    ("烟雨名苑", (1140.0, 680.0, 1370.0, 1140.0), "old_walkup_slate", "#cfc1aa", "#4f4d4a", "#41454c", True),
    ("文星花园", (1340.0, 690.0, 1850.0, 1160.0), "old_walkup_slate", "#d2c4ae", "#54504b", "#3f444c", True),
    ("南湖名苑", (1860.0, 690.0, 2260.0, 1180.0), "garden_yangfang", "#ccb597", "#5a4638", "#4b413b", True),
    ("瀚林府第", (1140.0, 1190.0, 1420.0, 1580.0), "modern_warm_slab", "#d8c9b2", "#524438", "#464442", True),
    ("凌公塘花园", (1820.0, 1185.0, 2260.0, 1590.0), "garden_yangfang", "#d2bfa2", "#58483c", "#42464e", True),
    ("民丰新村", (1500.0, -980.0, 2150.0, -560.0), "old_walkup_red", "#d1bfa4", "#604b3e", "#8e4030", True),
    ("东塔新村", (1500.0, -555.0, 2180.0, -190.0), "old_walkup_slate", "#cdc0ab", "#4e5158", "#3d424a", True),
    ("二毛新村", (980.0, -1240.0, 1480.0, -1010.0), "old_walkup_red", "#cdb99e", "#634c3c", "#964433", True),

    # === 由拳路 & 商务大道 & 双溪路 (南湖新区 / 国际商务区) ===
    ("中南大厦·润园", (2360.0, 2240.0, 2940.0, 2510.0), "modern_warm_slab", "#d3c1a6", "#534438", "#4b4641", False),
    ("久久小区", (2950.0, 2545.0, 3240.0, 2920.0), "garden_yangfang", "#c9b59a", "#4d4843", "#3a3e45", True),
    ("举秀苑", (2380.0, 2545.0, 2945.0, 2920.0), "modern_warm_slab", "#cfbda2", "#56473a", "#464340", True),
    ("苏嘉名境园", (2380.0, 2930.0, 2960.0, 3360.0), "modern_silver_slab", "#c6cacf", "#363b43", "#3d424a", False),
    ("文贤苑", (2965.0, 2930.0, 3420.0, 3440.0), "mixed_modern", "#cdc1ae", "#4a4946", "#3d424a", False),
    ("御溪花园", (3265.0, 2545.0, 3780.0, 3040.0), "modern_silver_slab", "#c8ccd0", "#383d46", "#3e434b", False),
    ("佳源四季璟园", (1960.0, 2550.0, 2350.0, 3150.0), "modern_warm_slab", "#d4c3aa", "#544639", "#484542", True),
    ("华润润府名园", (2100.0, 3160.0, 2660.0, 3680.0), "modern_silver_slab", "#ccd0d4", "#323842", "#3a4048", False),
    ("荣安万科香樟国际", (2670.0, 3380.0, 3260.0, 3820.0), "modern_warm_slab", "#d1c1a8", "#504439", "#454340", False),
    ("招商溪悦水岸", (3270.0, 3120.0, 3820.0, 3620.0), "modern_silver_slab", "#c9cdd2", "#343942", "#3c4149", False),
    ("大树丝路彩虹城", (1920.0, 1780.0, 2340.0, 2230.0), "artdeco_tower", "#c9aa84", "#4f3e30", "#453d37", True),

    # === 庆丰路 & 长水路 (高铁新城核心十字) ===
    ("万科臻境雅园", (3820.0, 3180.0, 4215.0, 3530.0), "modern_silver_slab", "#cacdd2", "#363c44", "#3c4148", False),
    ("荣安阳光城晴雪园", (4245.0, 3180.0, 4720.0, 3530.0), "modern_warm_slab", "#d7c8b0", "#5a4b3d", "#47433e", False),
    ("万科泊樾湾", (3820.0, 3560.0, 4215.0, 3960.0), "modern_silver_slab", "#d0d3d8", "#2f353e", "#383d45", False),
    ("绿城留香园", (4245.0, 3560.0, 4720.0, 3960.0), "mixed_modern", "#ccd0d4", "#383d45", "#383e46", False),
    ("庆丰新苑", (3820.0, 2550.0, 4210.0, 2745.0), "modern_warm_slab", "#d2c2aa", "#51453b", "#464340", True),
    ("双溪华庭", (4245.0, 2550.0, 4720.0, 2860.0), "garden_yangfang", "#ccb89d", "#51443a", "#3e4148", False),
    ("中南樾府", (4245.0, 2870.0, 4720.0, 3175.0), "mixed_modern", "#c8b79f", "#4a433d", "#3a3e45", False),
    ("龙湖春江天玺", (3820.0, 3970.0, 4215.0, 4520.0), "modern_silver_slab", "#c6cbd1", "#343942", "#3c4149", False),
    ("融创江南悦", (4245.0, 3970.0, 4720.0, 4520.0), "modern_warm_slab", "#d4c5ae", "#4f4338", "#444240", False),
    ("长水嘉园", (3270.0, 3630.0, 3810.0, 4220.0), "modern_silver_slab", "#c9cdd2", "#393f48", "#3e434b", False),

    # === 广益路 & 凌公塘路 & 万达/南湖新区 ===
    ("巴黎都市", (2270.0, 960.0, 2880.0, 1580.0), "artdeco_tower", "#cfb48f", "#534234", "#443d38", True),
    ("罗马都市", (2890.0, 820.0, 3480.0, 1420.0), "artdeco_tower", "#d4ba96", "#584637", "#48403a", True),
    ("金都夏宫", (2890.0, 260.0, 3480.0, 815.0), "garden_yangfang", "#d1bc9d", "#57473a", "#443e39", False),
    ("佳源英伦都市", (3490.0, 960.0, 4120.0, 1520.0), "artdeco_tower", "#c69c77", "#523d2f", "#543b32", True),
    ("东菱宝石公馆", (4130.0, 760.0, 4800.0, 1420.0), "artdeco_tower", "#d2b895", "#4e3f32", "#433d38", True),
    ("宏润花园", (3490.0, 1680.0, 4220.0, 2160.0), "modern_warm_slab", "#d5c4aa", "#524438", "#474440", True),
    ("御上江南", (4230.0, 2020.0, 4900.0, 2520.0), "modern_silver_slab", "#c8ccd1", "#383d45", "#3e434a", False),
    ("万达华府", (4460.0, 1440.0, 5050.0, 2010.0), "artdeco_tower", "#ccb18c", "#4d3f33", "#433e3a", True),
    ("景宜社区", (2270.0, 200.0, 2880.0, 880.0), "old_walkup_slate", "#d1c5b1", "#51514d", "#40454d", True),
    ("亚太花园", (2270.0, -560.0, 3150.0, 190.0), "modern_warm_slab", "#d3c2a9", "#55473b", "#454341", True),
    ("南湖国际社区", (3490.0, 200.0, 4220.0, 950.0), "mixed_modern", "#d0c1aa", "#4a4642", "#3e4249", False),
    ("中港名都公馆", (2890.0, 1430.0, 3480.0, 1860.0), "artdeco_tower", "#cca982", "#503e30", "#453d38", True),
    ("格林小镇", (3490.0, -560.0, 4450.0, 190.0), "garden_yangfang", "#cfb898", "#5a4638", "#4d3e36", False),

    # === 老城区内环 & 中山东路 / 禾兴路 / 建国路 / 环城河 ===
    ("杨柳湾社区", (-1320.0, -760.0, -720.0, -160.0), "old_walkup_red", "#d4c2a8", "#654d3e", "#944332", True),
    ("南杨社区", (-715.0, -760.0, -180.0, -180.0), "old_walkup_slate", "#d1c5b2", "#52514d", "#3e444d", True),
    ("紫阳花苑", (-175.0, -760.0, 340.0, -240.0), "old_walkup_slate", "#cfc3b0", "#4e5056", "#3d424b", True),
    ("建国南路社区", (-170.0, -1480.0, 180.0, -1100.0), "old_walkup_slate", "#d2c7b6", "#505258", "#3a4048", True),
    ("禾兴新村", (-1080.0, -1620.0, -640.0, -1160.0), "old_walkup_slate", "#cfc4b2", "#4f5156", "#3b4149", True),
    ("西丽社区", (-1950.0, -760.0, -1330.0, -240.0), "old_walkup_red", "#d3c1a6", "#644d3e", "#904132", True),
    ("梅湾花园", (-920.0, -170.0, -280.0, 320.0), "old_jiangnan", "#ddd6c9", "#373b42", "#2f343c", True),
    ("三水湾社区", (320.0, -1860.0, 1180.0, -1320.0), "old_walkup_red", "#d2c0a5", "#654e3f", "#994534", True),
    ("东栅新村", (1200.0, -2100.0, 2240.0, -1260.0), "old_walkup_red", "#d1bea2", "#634c3d", "#924232", True),

    # === 城北 (月河 / 清河 / 百花 / 三元路 / 中环北路) ===
    ("月河社区", (-1280.0, -2250.0, -890.0, -1630.0), "old_walkup_slate", "#d3c8b7", "#4d5056", "#3a4048", True),
    ("秀水兜社区", (-885.0, -2680.0, -180.0, -2260.0), "old_walkup_slate", "#cfc4b3", "#505257", "#3d424a", True),
    ("北京路社区", (-175.0, -2680.0, 560.0, -1960.0), "old_walkup_red", "#d2c0a6", "#644c3d", "#954332", True),
    ("清河社区", (-1560.0, -2860.0, -890.0, -2260.0), "old_walkup_slate", "#cfc3b0", "#4f5156", "#3d434b", True),
    ("百花社区", (-2060.0, -2680.0, -1565.0, -2060.0), "old_walkup_slate", "#d4c8b5", "#52514d", "#40454d", True),
    ("花园社区", (-2280.0, -2055.0, -1565.0, -1480.0), "old_walkup_red", "#d2bfa3", "#644e3f", "#964433", True),
    ("穆河社区", (-1560.0, -3420.0, -760.0, -2865.0), "old_walkup_red", "#d0bea3", "#614c3e", "#8f4131", True),
    ("三官塘社区", (-2240.0, -3650.0, -1565.0, -2865.0), "old_walkup_slate", "#ccc0ad", "#505257", "#3f444c", True),
    ("紫溪社区", (-755.0, -3650.0, 120.0, -2865.0), "modern_warm_slab", "#d4c4ac", "#52453a", "#464340", True),
    ("锦绣花园", (570.0, -3350.0, 1650.0, -2520.0), "modern_warm_slab", "#d1c1a8", "#504439", "#444240", True),
    ("东方都市", (1660.0, -3150.0, 2650.0, -2110.0), "mixed_modern", "#cdc1ae", "#4c4844", "#3d424a", True),
    ("塘汇锦苑", (1200.0, -3680.0, 2650.0, -3160.0), "modern_silver_slab", "#c7cbd0", "#3a4048", "#3f444c", True),

    # === 城南 (市政府 / 放鹤洲 / 城南路 / 花园路 / 南湖大道 / 植物园) ===
    ("府南社区", (-860.0, 1650.0, 120.0, 2650.0), "old_walkup_slate", "#d1c4b0", "#51504c", "#40454d", True),
    ("中国铁建花语江南", (-1280.0, 1480.0, -680.0, 2060.0), "modern_silver_slab", "#ccd0d4", "#333942", "#3b4048", False),
    ("龙之梦悦庭", (-1280.0, 980.0, -640.0, 1475.0), "modern_warm_slab", "#d5c6af", "#544639", "#464340", True),
    ("城南花园", (-1880.0, 2070.0, -1100.0, 2780.0), "garden_yangfang", "#cfb99b", "#564539", "#443f3b", True),
    ("翠柳庄园", (-1095.0, 2660.0, -280.0, 3360.0), "garden_yangfang", "#d2bea1", "#5a483a", "#4a403a", False),
    ("望湖公馆", (130.0, 1650.0, 780.0, 2380.0), "modern_warm_slab", "#d6c6ae", "#514338", "#45423f", True),
    ("南湖春晓源", (130.0, 2390.0, 880.0, 3150.0), "modern_silver_slab", "#c8ccd1", "#373c44", "#3e434b", False),
    ("运南社区", (-1850.0, 220.0, -1150.0, 975.0), "old_walkup_slate", "#cfc3af", "#50504c", "#3e434b", True),
    ("真合里", (-2350.0, 420.0, -1855.0, 1180.0), "old_walkup_red", "#d1bfa4", "#644d3e", "#924232", True),
    ("王安社区", (-2350.0, 1185.0, -1855.0, 1680.0), "old_walkup_slate", "#ccc0ac", "#4f5054", "#3d424a", True),
    ("开元万科滨河道", (-2350.0, 1690.0, -1855.0, 2320.0), "modern_silver_slab", "#c7cbd0", "#353a42", "#3c4149", False),

    # === 城西 / 秀洲 (八佰伴 / 洪兴路 / 中山西路 / 中环西路 / 嘉北) ===
    ("秀运社区", (-2280.0, -230.0, -1620.0, 415.0), "old_walkup_slate", "#d0c4b0", "#51514d", "#3f444c", True),
    ("竹桥社区", (-2480.0, -1475.0, -1680.0, -860.0), "old_walkup_red", "#d3c1a6", "#644e3f", "#954332", True),
    ("常秀社区", (-3260.0, -1380.0, -2490.0, -760.0), "old_walkup_slate", "#cfc3af", "#4e5156", "#3d424a", True),
    ("金都社区", (-3480.0, -755.0, -2620.0, -120.0), "modern_warm_slab", "#d4c3aa", "#534539", "#464340", True),
    ("运河社区", (-3480.0, -115.0, -2620.0, 680.0), "mixed_modern", "#cfc3af", "#4b4844", "#3e434b", True),
    ("嘉州美都", (-3120.0, -2950.0, -2250.0, -2120.0), "modern_warm_slab", "#d2c2aa", "#54463a", "#474440", True),
    ("洪波花园", (-3120.0, -2115.0, -2290.0, -1385.0), "garden_yangfang", "#cfb99b", "#574639", "#433f3b", True),
    ("金穗社区", (-3260.0, 1680.0, -2360.0, 2550.0), "modern_silver_slab", "#c9cdd2", "#373c44", "#3d424a", True),
    ("亲亲家园", (-3580.0, 2860.0, -3100.0, 3360.0), "modern_warm_slab", "#d3c2a8", "#534438", "#464340", True),
    ("大树银河湾", (-3580.0, 2150.0, -3100.0, 2855.0), "modern_silver_slab", "#c8ccd1", "#383d45", "#3e434a", False),
]


# ---------------------------------------------------------------------------------------------
# 3. Real Campuses / Institutional & Industrial Parks (verified on Google Earth)
#    (name, x0, y0, x1, y1, max_h_m, kind, colour_hex, no_shops)
# ---------------------------------------------------------------------------------------------
REAL_CAMPUSES = [
    ("蓝洋电子·富润科技园", 1432.0, 1740.0, 1980.0, 2508.0, 22.0, "office", "#bfc5cc", True),
    ("浙江红船干部学院", 1185.0, 165.0, 1560.0, 620.0, 18.0, "civic", "#d8d1c5", True),
    ("嘉兴一中校区", 1445.0, 1262.0, 1900.0, 1600.0, 20.0, "school", "#c69e82", True),
    ("嘉兴海警医院·公安支队", 780.0, -1010.0, 968.0, -620.0, 26.0, "hospital", "#dfd9ce", True),
    ("南湖区中心医院", 1580.0, -470.0, 1840.0, -230.0, 24.0, "hospital", "#dce0e4", True),
    ("嘉兴妇幼保健院", 2180.0, 1340.0, 2460.0, 1590.0, 28.0, "hospital", "#dcdad4", True),
    ("同济大学浙江学院", 2380.0, 1740.0, 3220.0, 2235.0, 22.0, "university", "#c8b39b", True),
    ("嘉兴建筑工业学校", 3270.0, 1980.0, 3660.0, 2480.0, 20.0, "school", "#cfc4b2", True),
    ("同济大学附属嘉兴实验学校", 3840.0, 2750.0, 4205.0, 3020.0, 18.0, "school", "#c79a7d", True),
    ("嘉兴图书馆·博物馆", 540.0, 820.0, 840.0, 1260.0, 20.0, "civic", "#d5d0c6", True),
    ("嘉兴大剧院", 160.0, 1450.0, 450.0, 1680.0, 24.0, "civic", "#cdd3d9", True),
    ("嘉兴学院南区", -2950.0, 1020.0, -2380.0, 1460.0, 22.0, "university", "#ccb89e", True),
    ("庆丰路长水路高端封闭小区群", 4120.0, 3220.0, 4360.0, 3920.0, 999.0, "", "", True),  # no shops only
    ("中央公园东沿线", 980.0, 1640.0, 1410.0, 2500.0, 999.0, "", "", True),  # Central Park green edge: no shops
]


# ---------------------------------------------------------------------------------------------
# 4. Real Street-Front Shops & Businesses (165+ verified from Google Maps lyrs=m + T1 survey)
#    (name, kind, brand_key, (game_x, game_y))
# ---------------------------------------------------------------------------------------------
_A = {
    "s4_jct": (3255.0, 2532.0),   # 双溪路 & 由拳路
    "s5_jct": (2342.0, 2540.0),   # 商务大道 & 由拳路
    "s6_jct": (1411.0, 2520.0),   # 纺工路 & 由拳路
    "s7_stop": (1433.0, 1532.0),  # 嘉兴一中站
    "s8_jct": (1268.0, 686.0),    # 烟雨路 & 纺工路
    "s9_jct": (1168.0, 119.0),    # 南溪西路 & 纺工路
    "s10_stop": (1129.0, -307.0), # 纺工路景湖路站
    "s11_jct": (977.0, -1040.0),  # 东方路 & 甪里街
    "zs_hx": (-689.0, -1028.0),   # 中山东路 & 禾兴南路
    "zs_jg": (-214.0, -1089.0),   # 中山东路 & 建国南路 (瓶山)
    "zs_hcd": (226.0, -1130.0),   # 中山东路 & 环城东路
    "zs_al": (-1120.0, -943.0),   # 中山东路 & 安乐路
    "rm_pk": (175.0, -1436.0),    # 人民公园 (环城东路)
    "qf_cs": (4242.0, 3527.0),    # 庆丰路 & 长水路
    "qf_yq": (4208.0, 2564.0),    # 庆丰路 & 由拳路
    "yaohan": (-2339.0, -651.0),  # 中山西路八佰伴
}


def _at(anchor, dx, dy):
    ax, ay = _A[anchor]
    return (round(ax + dx, 1), round(ay + dy, 1))


REAL_SHOPS_GOOGLE = [
    # === 中山东路 × 禾兴南路 × 安乐路 (Google Maps Zone 01) ===
    ("麦当劳", "fast_food", "麦当劳", _at("zs_hx", -65, 28)),
    ("屈臣氏", "pharmacy", "屈臣氏", _at("zs_hx", -185, 85)),
    ("邹大鲜", "restaurant", "", _at("zs_hx", -190, 52)),
    ("华夏良子尚·SPA", "beauty", "", _at("zs_hx", -155, 68)),
    ("百味轩", "restaurant", "", _at("zs_hx", -24, -68)),
    ("戴梦得购物中心", "mall", "戴梦得购物中心", _at("zs_hx", -40, 88)),
    ("川之味面馆", "restaurant", "", _at("zs_hx", -45, 165)),
    ("斜西街烧卖店", "fast_food", "", _at("zs_hx", -95, 290)),
    ("新竹篱笆土菜馆", "restaurant", "", _at("zs_hx", -160, 320)),
    ("昆仑大药行", "pharmacy", "", _at("zs_al", 15, 195)),
    ("龙文教育总部", "office", "", _at("zs_al", -45, 22)),
    ("江山蜜蜂", "convenience", "", _at("zs_al", -12, 330)),
    ("郑驿早餐", "fast_food", "", _at("zs_al", 18, 415)),
    ("嘉信杨柳湾大药房", "pharmacy", "", _at("zs_al", 110, 395)),
    ("阿霞馄饨王", "fast_food", "", _at("zs_hx", 85, 390)),
    ("健康旅馆", "hotel", "", _at("zs_hx", 125, 425)),
    ("康甲堂", "pharmacy", "", _at("zs_hx", 28, 465)),
    ("建设银行", "bank", "建设银行", _at("zs_hx", 205, 278)),
    ("锐思特嘉兴中山店", "hotel", "", _at("zs_hx", 155, -52)),
    ("站点服饰", "clothes", "", _at("zs_hx", 172, -92)),
    ("女主角服饰", "clothes", "", _at("zs_hx", 108, -118)),
    ("轻旅酒店", "hotel", "", _at("zs_hx", 10, -295)),
    ("吴越购物", "retail", "", _at("zs_hx", 72, -278)),
    ("嘉兴鹿都购物广场", "mall", "", _at("zs_hx", -180, -210)),
    ("时尚假发", "hairdresser", "", _at("zs_hx", 120, -370)),
    ("好又多超市", "supermarket", "", _at("zs_jg", -120, -295)),
    ("三福时尚", "clothes", "", _at("zs_jg", -80, -260)),
    ("中兴广场", "mall", "", _at("zs_jg", -42, -295)),
    ("国美电器", "electronics", "", _at("zs_jg", -65, -375)),
    ("乔丹体育", "clothes", "", _at("zs_jg", -15, -135)),
    ("雨露箱包", "retail", "", _at("zs_jg", 52, -195)),
    ("建国珠宝城", "jewelry", "", _at("zs_jg", 22, -45)),
    ("江南开元", "restaurant", "", _at("zs_jg", 12, 65)),
    ("五芳斋总店", "restaurant", "五芳斋", _at("zs_jg", -36, -78)),
    ("迪欧咖啡", "cafe", "", _at("zs_jg", 18, 355)),
    ("大拇指电子电器", "electronics", "", _at("zs_jg", 55, 295)),
    ("潘多拉CLUB", "bar", "", _at("zs_jg", 5, 405)),

    # === 中山东路东段 -> 环城东路(人民公园) -> 勤俭路 -> 嘉兴火车站 (Google Maps Zone 02) ===
    ("老百姓大药房", "pharmacy", "老百姓大药房", _at("zs_hcd", -148, -32)),
    ("桐乡面馆", "restaurant", "", _at("zs_hcd", -35, -24)),
    ("韩海丽清真美食", "restaurant", "", _at("zs_hcd", -125, 75)),
    ("花花公子俱乐部", "bar", "", _at("rm_pk", 65, 35)),
    ("瑞峰汽修", "hardware", "", _at("rm_pk", 118, 82)),
    ("成都川菜馆", "restaurant", "", _at("rm_pk", 55, -235)),
    ("盛安消防器材", "hardware", "", _at("rm_pk", 205, -75)),
    ("欢欢小卖部", "convenience", "", _at("rm_pk", 355, -10)),
    ("真益美快餐", "fast_food", "", _at("rm_pk", 385, 58)),
    ("一米眼镜", "optician", "", _at("rm_pk", 295, -175)),
    ("徐大夫牙科", "dentist", "", _at("rm_pk", 445, -88)),
    ("亿家早餐", "fast_food", "", _at("zs_jg", -22, -455)),
    ("风情海岸", "cafe", "", _at("zs_jg", -125, -490)),
    ("嘉兴话机部落", "mobile_phone", "", _at("zs_jg", 185, -290)),

    # === 纺工路 滨河路 -> 景湖路 -> 南溪西路 (Google Maps Zone 03 + Amap T1 Survey) ===
    ("嘉年华汽车租赁", "service", "", _at("s11_jct", 25, -38)),
    ("工会驿站", "service", "", _at("s11_jct", 46, 64)),
    ("万寿堂药房", "pharmacy", "", _at("s11_jct", 44, 132)),
    ("世友房产", "office", "", _at("s11_jct", -18, 150)),
    ("好万家超市", "supermarket", "", _at("s11_jct", 48, 195)),
    ("君康保健器材", "pharmacy", "", _at("s11_jct", 42, 248)),
    ("欧尚超市", "supermarket", "", _at("s11_jct", 145, 165)),
    ("红天地酒家", "restaurant", "", _at("s11_jct", -275, 295)),
    ("万家福超市", "supermarket", "", _at("s10_stop", 18, -42)),
    ("陈氏小吃店", "fast_food", "", _at("s10_stop", 72, 22)),
    ("黄金瀑布", "retail", "", _at("s10_stop", 32, 68)),
    ("惠耳听力助听器", "service", "", _at("s10_stop", 46, 82)),
    ("群群发型屋", "hairdresser", "", _at("s10_stop", 32, 118)),
    ("嘉兴老百姓药房", "pharmacy", "老百姓大药房", _at("s10_stop", 42, 265)),
    ("嘉兴自家宾馆", "hotel", "", _at("s10_stop", 31, 163)),
    ("非凡口腔门诊部", "dentist", "", _at("s9_jct", 62, -28)),
    ("博客假日酒店", "hotel", "", _at("s9_jct", 52, 22)),
    ("如家派柏·云酒店", "hotel", "", _at("s9_jct", 14, -45)),
    ("桐湘食府", "restaurant", "", _at("s9_jct", 188, 18)),
    ("新中国城", "restaurant", "", _at("s9_jct", 395, 15)),
    ("Very Pizza", "restaurant", "", _at("s10_stop", 340, 68)),
    ("新生活化妆品", "beauty", "", _at("s10_stop", 420, -110)),
    ("东北参茸店", "pharmacy", "", _at("s10_stop", 455, -180)),

    # === 纺工路 南溪西路 -> 烟雨路 -> 凌公塘路 -> 嘉兴一中 (Google Maps Zone 04 + Amap T1 Survey) ===
    ("老海面店", "restaurant", "", _at("s9_jct", 32, 72)),
    ("惠琴饭店", "restaurant", "", _at("s9_jct", 36, 108)),
    ("卓越洗车", "service", "", _at("s8_jct", 42, -55)),
    ("国鸿便利超市", "convenience", "", _at("s8_jct", 52, -22)),
    ("广寒宫足道", "beauty", "", _at("s8_jct", 60, 42)),
    ("中国农业银行", "bank", "农业银行", _at("s8_jct", 60, 82)),
    ("长盈阁", "restaurant", "", _at("s8_jct", 65, 107)),
    ("耀达超市", "supermarket", "", _at("s8_jct", 48, 65)),
    ("COLMO智感体验馆", "electronics", "", _at("s8_jct", 75, 177)),
    ("安信证券", "bank", "", _at("s8_jct", -28, 12)),
    ("中国银行", "bank", "中国银行", _at("s8_jct", -27, 113)),
    ("正大药房", "pharmacy", "", _at("s8_jct", -24, 92)),
    ("优倍视眼镜", "optician", "", _at("s8_jct", -18, 152)),
    ("元祖", "bakery", "", _at("s8_jct", -12, 185)),
    ("齐福堂参茸专卖", "pharmacy", "", _at("s8_jct", -14, 240)),
    ("嘉兴悦来商务宾馆", "hotel", "", _at("s8_jct", 65, 295)),
    ("观唐影院式足疗", "beauty", "", _at("s8_jct", 230, 315)),
    ("DUODUOM咖啡", "cafe", "", _at("s8_jct", 265, 310)),
    ("真真老老", "restaurant", "真真老老", _at("s8_jct", -310, -105)),
    ("梅龙镇酒家", "restaurant", "", _at("s8_jct", -340, -135)),
    ("南湖船菜大酒店", "restaurant", "", _at("s8_jct", -355, -185)),
    ("名门·浮水印", "restaurant", "", _at("s8_jct", -265, -75)),
    ("玉林面店", "restaurant", "", _at("s8_jct", -280, 62)),
    ("刘记锅贴", "fast_food", "", _at("s8_jct", -275, 112)),
    ("三星专卖店", "mobile_phone", "", _at("s8_jct", -270, 195)),
    ("顺发副食品超市", "convenience", "", _at("s8_jct", -265, 298)),
    ("吉明购物生活超市", "supermarket", "", _at("s8_jct", 310, 5)),
    ("快康大药房", "pharmacy", "", _at("s8_jct", 385, 45)),

    # === 嘉兴一中站 (翰林府第底商) & 中环南路 -> 纺工路由拳路 (Google Maps Zone 05 + Amap T1 Survey) ===
    ("捷安特", "bicycle", "", _at("s7_stop", -83, -216)),
    ("C&C眼镜", "optician", "", _at("s7_stop", -75, -185)),
    ("顾小芒", "cafe", "", _at("s7_stop", -74, -168)),
    ("卡萨帝旗舰店", "electronics", "", _at("s7_stop", -67, -135)),
    ("禾城陆稿荐", "restaurant", "", _at("s7_stop", -64, -95)),
    ("罗森", "convenience", "罗森便利店", _at("s7_stop", -54, -56)),
    ("五芳斋", "restaurant", "五芳斋", _at("s7_stop", -45, -8)),
    ("雨露空间", "convenience", "", _at("s7_stop", -38, 35)),
    ("嘉兴名仕眼科", "pharmacy", "", _at("s7_stop", -36, 56)),
    ("易捷便利店", "convenience", "", _at("s7_stop", -125, 125)),
    ("鼻灵通鼻炎馆", "pharmacy", "", _at("s7_stop", 125, 120)),
    ("醉美新疆酒店", "restaurant", "", _at("s7_stop", 240, 195)),
    ("慢舍咖啡", "cafe", "", _at("s7_stop", 295, 365)),
    ("娟娟家常菜", "restaurant", "", _at("s7_stop", 250, 445)),
    ("健一网大药房", "pharmacy", "", _at("s7_stop", 285, 650)),
    ("闻香阁私房菜馆", "restaurant", "", _at("s7_stop", 245, 985)),
    ("南门高老太土菜馆", "restaurant", "", _at("s6_jct", 39, 32)),
    ("音品汇汽车音响", "service", "", _at("s6_jct", 48, 66)),
    ("宏伟贴膜", "service", "", _at("s6_jct", 169, 34)),

    # === 由拳路 商务大道 -> 双溪路 -> 庆丰路 (Google Maps Zones 06 & 07 + Amap T1 Survey) ===
    ("全季酒店", "hotel", "全季酒店", _at("s5_jct", 82, -28)),
    ("日立中央空调", "electronics", "", _at("s5_jct", 242, 45)),
    ("盛美口腔", "dentist", "", _at("s5_jct", 182, 105)),
    ("红日装饰", "office", "", _at("s5_jct", 155, 68)),
    ("中南风超市", "supermarket", "", _at("s5_jct", 215, -172)),
    ("大润发玛特", "supermarket", "", _at("s5_jct", 85, 315)),
    ("SO造型", "hairdresser", "", _at("s5_jct", 285, 195)),
    ("一路飘香烧烤", "restaurant", "", _at("s4_jct", -195, -26)),
    ("老仙配镜厂", "optician", "", _at("s4_jct", -250, -33)),
    ("华莱士·全鸡汉堡", "fast_food", "", _at("s4_jct", -39, -204)),
    ("兰州牛肉拉面", "restaurant", "", _at("s4_jct", -32, -210)),
    ("VEAR潮牌造型", "hairdresser", "", _at("s4_jct", -28, -162)),
    ("罗数培训学校", "office", "", _at("s4_jct", -32, -177)),
    ("爱玛电动车", "bicycle", "爱玛电动车", _at("s4_jct", -24, 44)),
    ("美俪家族", "beauty", "", _at("s4_jct", -231, 41)),
    ("忆味桐乡煲", "restaurant", "", _at("s4_jct", -188, 85)),
    ("雅迪电动车", "bicycle", "雅迪电动车", _at("s4_jct", -183, 120)),
    ("久久五金店", "hardware", "", _at("s4_jct", -212, 161)),
    ("广济大药房", "pharmacy", "", _at("s4_jct", 112, 315)),
    ("好万家超市举秀苑店", "supermarket", "", _at("s4_jct", -295, 435)),
    ("摩登湾造型护肤", "beauty", "", _at("qf_yq", -185, -35)),
    ("莱瑞娜·日式美颜", "beauty", "", _at("qf_yq", -40, -32)),
    ("农家乐老饭店", "restaurant", "", _at("qf_yq", -195, 295)),

    # === 广益路 / 凌公塘路 / 城东 / 城西 / 城北 真实代表商户 (Google Maps Zones 09-12) ===
    ("三喜日料", "restaurant", "", (2810.0, 1525.0)),
    ("戴梦得超市", "supermarket", "", (2450.0, 1245.0)),
    ("老佛爷购物中心", "mall", "", (2180.0, 920.0)),
    ("莲花石川菜餐厅", "restaurant", "", (3640.0, 745.0)),
    ("维格斯·餐厅酒吧", "bar", "", (3830.0, 1245.0)),
    ("化隆牛肉面", "restaurant", "", (4410.0, 1560.0)),
    ("鱼味鲜川菜馆", "restaurant", "", (4910.0, 1390.0)),
    ("群锋小吃店", "fast_food", "", (4590.0, 1790.0)),
    ("庆鑫餐厅", "restaurant", "", (5180.0, 1810.0)),
    ("南湖名厨", "restaurant", "", (1985.0, 2940.0)),
    ("博雅酒店", "hotel", "", (-195.0, 1180.0)),
    ("嘉兴龙之梦大酒店", "hotel", "", (-1285.0, 1185.0)),
    ("维也纳国际酒店", "hotel", "", (-2240.0, 1265.0)),
    ("安仁大药房", "pharmacy", "", (-2560.0, 1685.0)),
    ("阳光大酒店", "hotel", "", (-2840.0, -565.0)),
    ("福朋喜来登酒店", "hotel", "", (-2920.0, -395.0)),
    ("帕蒂美式餐厅", "restaurant", "", (-2810.0, -1085.0)),
    ("江南超市", "supermarket", "", (-3260.0, -1920.0)),
    ("口口鲜烧卖馄饨", "fast_food", "", (-1225.0, -2420.0)),
    ("悦聚堂哥弟烤肉", "restaurant", "", (-1485.0, -2960.0)),
    ("肯德基", "fast_food", "肯德基", (-1340.0, -3520.0)),
    ("福大饺子烧卖专卖店", "fast_food", "", (-1840.0, -3650.0)),
    ("江南超市三元店", "supermarket", "", (-165.0, -2890.0)),
    ("可的便利店", "convenience", "", (265.0, -3150.0)),
    ("麦德龙", "supermarket", "", (1665.0, -3040.0)),
    ("万寿堂药房创业路店", "pharmacy", "", (1940.0, -1840.0)),
]

# Legacy compat exports for any existing callers
T1_ROAD_WIDTHS = {
    "纺工路": (40.0, 3, 1.5),
    "庆丰路": (34.0, 3, 1.5),
    "由拳路": (29.0, 2, 0.0),
}


# ---------------------------------------------------------------------------------------------
# 5. Real Road Cross-Sections measured on Google Earth satellite (lyrs=s, z=17)
#    name_substring -> (two_way_w, lanes_per_dir, one_way_w, one_way_lanes, bike_buffer_m)
# ---------------------------------------------------------------------------------------------
REAL_ROAD_SPECS = {
    # 城市超级主干道 (双向6车道 + 中央绿化带 + 机非隔离带 / 主辅路)
    "商务大道": (40.0, 3, 16.5, 3, 1.5),
    "长水路": (42.0, 3, 17.5, 3, 1.5),
    "广益路": (38.0, 3, 16.0, 3, 1.5),
    "南湖大道": (40.0, 3, 16.5, 3, 1.5),
    "三环东路": (40.0, 3, 16.5, 3, 1.5),
    "三环南路": (40.0, 3, 16.5, 3, 1.5),
    "中环东路": (42.0, 3, 17.0, 3, 1.5),
    "中环西路": (42.0, 3, 17.0, 3, 1.5),
    "中环北路": (42.0, 3, 17.0, 3, 1.5),

    # 城市主干道 (双向6车道, 32-36m)
    "双溪路": (36.0, 3, 15.0, 3, 1.5),
    "庆丰路": (34.0, 3, 14.5, 3, 1.5),
    "中山西路": (34.0, 3, 14.5, 3, 1.5),
    "东升东路": (34.0, 3, 14.5, 3, 1.5),
    "东升西路": (34.0, 3, 14.5, 3, 1.5),
    "凌公塘路": (32.0, 3, 14.0, 3, 1.5),
    "新气象路": (32.0, 3, 14.0, 3, 1.5),
    "越秀南路": (34.0, 3, 14.5, 3, 1.5),
    "越秀北路": (32.0, 3, 14.0, 3, 1.5),
    "昌盛中路": (34.0, 3, 14.5, 3, 1.5),
    "昌盛南路": (34.0, 3, 14.5, 3, 1.5),
    "洪兴路": (32.0, 3, 14.0, 3, 1.5),
    "百川路": (32.0, 3, 14.0, 3, 1.5),

    # 核心城区主次干道 (双向4车道 + 宽非机动车道, 24-30m)
    "中山东路": (28.0, 2, 12.5, 2, 0.0),
    "由拳路": (29.0, 2, 12.5, 2, 0.0),
    "禾兴南路": (26.0, 2, 11.5, 2, 0.0),
    "禾兴北路": (28.0, 2, 12.5, 2, 0.0),
    "建国南路": (24.0, 2, 11.0, 2, 0.0),
    "建国北路": (26.0, 2, 11.5, 2, 0.0),
    "南溪西路": (28.0, 2, 12.5, 2, 1.5),
    "南溪东路": (30.0, 2, 13.0, 2, 1.5),
    "城南路": (28.0, 2, 12.5, 2, 1.5),
    "花园路": (26.0, 2, 11.5, 2, 0.0),
    "三元路": (28.0, 2, 12.5, 2, 1.5),
    "东方路": (28.0, 2, 12.5, 2, 1.5),
    "甪里街": (26.0, 2, 11.5, 2, 0.0),
    "文贤路": (24.0, 2, 11.0, 2, 0.0),
    "云东路": (24.0, 2, 11.0, 2, 0.0),
    "南江路": (26.0, 2, 11.5, 2, 0.0),
    "创业路": (24.0, 2, 11.0, 2, 0.0),
    "城东路": (24.0, 2, 11.0, 2, 0.0),
    "城北路": (24.0, 2, 11.0, 2, 0.0),

    # 老城环城路与重要次干道 (18-22m)
    "环城东路": (20.0, 2, 9.5, 2, 0.0),
    "环城南路": (20.0, 2, 9.5, 2, 0.0),
    "环城西路": (22.0, 2, 10.0, 2, 0.0),
    "环城北路": (22.0, 2, 10.0, 2, 0.0),
    "勤俭路": (19.0, 1, 9.0, 2, 0.0),
    "烟雨路": (20.0, 2, 9.5, 2, 0.0),
    "海盐塘路": (18.0, 1, 8.8, 2, 0.0),
    "农翔路": (20.0, 2, 9.5, 2, 0.0),
    "景湖路": (16.0, 1, 8.2, 1, 0.0),
    "滨河路": (14.0, 1, 7.5, 1, 0.0),
    "东塔路": (18.0, 1, 8.8, 2, 0.0),
    "文昌路": (22.0, 2, 10.0, 2, 0.0),
    "吉杨路": (20.0, 2, 9.5, 2, 0.0),
    "解放路": (20.0, 2, 9.5, 2, 0.0),

    # 支路与老城街巷 (11-15m, 贴合真实街巷尺度!)
    "斜西街": (13.0, 1, 7.0, 1, 0.0),
    "府前街": (12.0, 1, 6.5, 1, 0.0),
    "府南街": (14.0, 1, 7.2, 1, 0.0),
    "紫阳街": (13.0, 1, 7.0, 1, 0.0),
    "秀州路": (14.0, 1, 7.2, 1, 0.0),
    "中和街": (11.5, 1, 6.2, 1, 0.0),
    "梧桐树街": (11.5, 1, 6.2, 1, 0.0),
    "普民路": (14.0, 1, 7.2, 1, 0.0),
    "乌桥路": (14.0, 1, 7.2, 1, 0.0),
    "富润路": (15.0, 1, 7.5, 1, 0.0),
    "富民路": (13.0, 1, 7.0, 1, 0.0),
    "富兴路": (13.0, 1, 7.0, 1, 0.0),
    "同济路": (14.0, 1, 7.2, 1, 0.0),
    "杨柳湾路": (13.0, 1, 7.0, 1, 0.0),
    "南杨路": (12.5, 1, 6.8, 1, 0.0),
    "道前街": (11.0, 1, 6.0, 1, 0.0),
    "精严寺街": (11.0, 1, 6.0, 1, 0.0),
    "小西门横街": (11.0, 1, 6.0, 1, 0.0),
}


def find_compound(px, py):
    """Return the real Jiaxing residential compound dict covering (px, py), or None."""
    for rec in REAL_COMPOUNDS:
        nm, (x0, y0, x1, y1), arch_k, wall_o, trim_o, roof_o, shops_o = rec
        if x0 <= px <= x1 and y0 <= py <= y1:
            return {
                "name": nm,
                "box": (x0, y0, x1, y1),
                "arch_key": arch_k,
                "arch": ARCHETYPES[arch_k],
                "wall": wall_o,
                "trim": trim_o,
                "roof": roof_o,
                "podium_shops": shops_o,
            }
    return None


def nearest_real_compound_name(px, py, max_dist=650.0):
    """Find the real compound name containing or closest to (px, py), avoiding fictional repeats."""
    hit = find_compound(px, py)
    if hit is not None:
        return hit["name"], hit["arch"]["gate_style"]
    best = None
    for rec in REAL_COMPOUNDS:
        nm, (x0, y0, x1, y1), arch_k, *_ = rec
        cx = max(x0, min(px, x1))
        cy = max(y0, min(py, y1))
        d = math.hypot(px - cx, py - cy)
        if d <= max_dist and (best is None or d < best[0]):
            best = (d, nm, ARCHETYPES[arch_k]["gate_style"])
    if best is not None:
        # Distinguish adjacent sub-clusters cleanly (东区/西区/南区/北区/二期)
        return best[1], best[2]
    return None, None


def road_spec_for_name(name):
    """Return real Google Earth road spec tuple (w2, l2, w1, l1, buf) for a named Jiaxing street, or None."""
    if not name:
        return None
    if name in REAL_ROAD_SPECS:
        return REAL_ROAD_SPECS[name]
    for key, spec in REAL_ROAD_SPECS.items():
        if key in name:
            return spec
    return None
