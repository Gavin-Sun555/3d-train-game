class_name StorefrontBuilder
extends RefCounted

# Real ground-floor shopfronts placed from OpenStreetMap POIs (see tools/osm_storefronts.py):
# pilasters, granite bulkhead, framed display glazing with a lit parallax shop interior, entrance
# doors, a fascia sign carrying the real shop name, plus awnings / blade signs / planters by type.
# All frames are batched into one vertex-coloured mesh; all glazing into one shader mesh.

const WALK_Y := 0.192 # sidewalk top (kerb height)
const INTERIOR_CAFE := 0
const INTERIOR_RETAIL := 1
const INTERIOR_OFFICE := 2
const INTERIOR_GROCERY := 3
const INTERIOR_BAR := 4

# Brand sign treatments (approximate real colour schemes). Keys are lower-case brand / name.
#   bg: fascia board, fg: lettering, frame: shopfront framing, letters: raised letters on stone (no board)
const BRANDS := {
	"starbucks": {"bg": Color(0.0, 0.38, 0.25), "fg": Color(1, 1, 1), "frame": Color(0.16, 0.12, 0.09), "awning": Color(0.0, 0.32, 0.21)},
	"mcdonald's": {"bg": Color(0.80, 0.08, 0.08), "fg": Color(1.0, 0.78, 0.05), "frame": Color(0.2, 0.2, 0.2)},
	"walgreens": {"bg": Color(0.93, 0.93, 0.92), "fg": Color(0.86, 0.08, 0.14), "frame": Color(0.25, 0.25, 0.27)},
	"cvs pharmacy": {"bg": Color(0.93, 0.93, 0.92), "fg": Color(0.80, 0.0, 0.0), "frame": Color(0.25, 0.25, 0.27)},
	"7-eleven": {"bg": Color(0.95, 0.95, 0.95), "fg": Color(0.0, 0.5, 0.3), "frame": Color(0.9, 0.4, 0.1)},
	"zara": {"letters": true, "fg": Color(0.05, 0.05, 0.05), "frame": Color(0.08, 0.08, 0.08)},
	"uniqlo": {"bg": Color(0.86, 0.0, 0.07), "fg": Color(1, 1, 1), "frame": Color(0.9, 0.9, 0.9)},
	"sephora": {"bg": Color(0.04, 0.04, 0.04), "fg": Color(1, 1, 1), "frame": Color(0.06, 0.06, 0.06)},
	"old navy": {"bg": Color(0.06, 0.16, 0.36), "fg": Color(1, 1, 1), "frame": Color(0.85, 0.85, 0.85)},
	"nordstrom rack": {"bg": Color(0.97, 0.97, 0.97), "fg": Color(0.05, 0.05, 0.05), "frame": Color(0.1, 0.1, 0.1)},
	"barnes & noble": {"bg": Color(0.08, 0.25, 0.17), "fg": Color(0.95, 0.91, 0.80), "frame": Color(0.10, 0.20, 0.14)},
	"urban outfitters": {"letters": true, "fg": Color(0.05, 0.05, 0.05), "frame": Color(0.12, 0.12, 0.12)},
	"allsaints": {"bg": Color(0.06, 0.06, 0.06), "fg": Color(0.95, 0.95, 0.95), "frame": Color(0.08, 0.08, 0.08)},
	"dr. martens": {"bg": Color(0.05, 0.05, 0.05), "fg": Color(1.0, 0.85, 0.1), "frame": Color(0.05, 0.05, 0.05)},
	"patagonia": {"letters": true, "fg": Color(0.08, 0.08, 0.1), "frame": Color(0.30, 0.22, 0.15)},
	"carhartt": {"bg": Color(0.10, 0.10, 0.10), "fg": Color(0.95, 0.66, 0.10), "frame": Color(0.12, 0.12, 0.12)},
	"pandora": {"bg": Color(0.97, 0.96, 0.95), "fg": Color(0.05, 0.05, 0.05), "frame": Color(0.85, 0.80, 0.78)},
	"ben bridge": {"bg": Color(0.07, 0.12, 0.26), "fg": Color(0.95, 0.90, 0.75), "frame": Color(0.07, 0.12, 0.26)},
	"cartier": {"bg": Color(0.45, 0.06, 0.08), "fg": Color(0.95, 0.85, 0.55), "frame": Color(0.75, 0.68, 0.55)},
	"eileen fisher": {"letters": true, "fg": Color(0.1, 0.1, 0.1), "frame": Color(0.75, 0.72, 0.68)},
	"men's wearhouse": {"bg": Color(0.10, 0.12, 0.18), "fg": Color(1, 1, 1), "frame": Color(0.1, 0.1, 0.12)},
	"t-mobile": {"bg": Color(0.89, 0.0, 0.45), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"metro by t-mobile": {"bg": Color(0.36, 0.12, 0.62), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"verizon": {"bg": Color(0.03, 0.03, 0.03), "fg": Color(1, 1, 1), "frame": Color(0.1, 0.1, 0.1)},
	"at&t": {"bg": Color(0.0, 0.62, 0.86), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"chase": {"bg": Color(0.07, 0.36, 0.67), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.27, 0.30)},
	"wells fargo": {"bg": Color(0.80, 0.05, 0.12), "fg": Color(1.0, 0.80, 0.15), "frame": Color(0.30, 0.25, 0.22)},
	"bank of america": {"bg": Color(0.0, 0.18, 0.45), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.27, 0.30)},
	"u.s. bank": {"bg": Color(0.05, 0.18, 0.45), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.27, 0.30)},
	"hsbc": {"bg": Color(0.95, 0.95, 0.95), "fg": Color(0.86, 0.0, 0.07), "frame": Color(0.25, 0.25, 0.27)},
	"keybank": {"bg": Color(0.80, 0.08, 0.15), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.25, 0.27)},
	"wafd bank": {"bg": Color(0.0, 0.25, 0.45), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.25, 0.27)},
	"umpqua bank": {"bg": Color(0.10, 0.30, 0.22), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.25, 0.27)},
	"becu": {"bg": Color(0.0, 0.32, 0.60), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.25, 0.27)},
	"chipotle": {"bg": Color(0.27, 0.10, 0.07), "fg": Color(0.95, 0.90, 0.82), "frame": Color(0.45, 0.36, 0.28)},
	"subway": {"bg": Color(0.0, 0.50, 0.25), "fg": Color(1.0, 0.80, 0.0), "frame": Color(0.2, 0.2, 0.2)},
	"jimmy john's": {"bg": Color(0.95, 0.95, 0.95), "fg": Color(0.75, 0.05, 0.05), "frame": Color(0.1, 0.1, 0.1)},
	"mod pizza": {"bg": Color(0.10, 0.10, 0.10), "fg": Color(0.95, 0.95, 0.95), "frame": Color(0.3, 0.3, 0.3)},
	"taco del mar": {"bg": Color(0.95, 0.45, 0.05), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"veggie grill": {"bg": Color(0.30, 0.55, 0.15), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"evergreens": {"bg": Color(0.20, 0.42, 0.20), "fg": Color(1, 1, 1), "frame": Color(0.35, 0.28, 0.20)},
	"sweetgreen": {"bg": Color(0.85, 0.92, 0.82), "fg": Color(0.10, 0.30, 0.15), "frame": Color(0.75, 0.75, 0.72)},
	"shake shack": {"bg": Color(0.10, 0.10, 0.10), "fg": Color(0.55, 0.80, 0.30), "frame": Color(0.3, 0.3, 0.3)},
	"potbelly": {"bg": Color(0.45, 0.10, 0.10), "fg": Color(1.0, 0.85, 0.5), "frame": Color(0.35, 0.22, 0.12)},
	"einstein bros. bagels": {"bg": Color(0.10, 0.25, 0.55), "fg": Color(1, 1, 1), "frame": Color(0.3, 0.3, 0.3)},
	"yard house": {"bg": Color(0.15, 0.12, 0.10), "fg": Color(0.95, 0.80, 0.50), "frame": Color(0.25, 0.18, 0.12)},
	"regal cinemas": {"bg": Color(0.70, 0.05, 0.08), "fg": Color(1, 1, 1), "frame": Color(0.15, 0.15, 0.15)},
	"ace hardware": {"bg": Color(0.82, 0.08, 0.08), "fg": Color(1, 1, 1), "frame": Color(0.2, 0.2, 0.2)},
	"amazon fresh": {"bg": Color(0.10, 0.10, 0.10), "fg": Color(0.55, 0.80, 0.20), "frame": Color(0.2, 0.2, 0.2)},
	"west elm": {"letters": true, "fg": Color(0.1, 0.1, 0.1), "frame": Color(0.15, 0.15, 0.15)},
	"aveda": {"letters": true, "fg": Color(0.1, 0.1, 0.1), "frame": Color(0.6, 0.55, 0.45)},
	"indochino": {"bg": Color(0.08, 0.08, 0.08), "fg": Color(1, 1, 1), "frame": Color(0.1, 0.1, 0.1)},
	"tous les jours": {"bg": Color(0.95, 0.95, 0.93), "fg": Color(0.10, 0.30, 0.25), "frame": Color(0.2, 0.3, 0.25)},
	# Authentic Jiaxing & Chinese urban commercial brands
	"五芳斋粽子": {"bg": Color(0.68, 0.10, 0.10), "fg": Color(0.98, 0.85, 0.36), "frame": Color(0.32, 0.16, 0.10), "awning": Color(0.62, 0.11, 0.11)},
	"五芳斋": {"bg": Color(0.68, 0.10, 0.10), "fg": Color(0.98, 0.85, 0.36), "frame": Color(0.32, 0.16, 0.10), "awning": Color(0.62, 0.11, 0.11)},
	"文虎酱鸭": {"bg": Color(0.42, 0.16, 0.08), "fg": Color(0.98, 0.86, 0.44), "frame": Color(0.26, 0.14, 0.08)},
	"真真老老": {"bg": Color(0.58, 0.12, 0.12), "fg": Color(0.97, 0.90, 0.65), "frame": Color(0.28, 0.14, 0.10)},
	"瑞幸咖啡": {"bg": Color(0.05, 0.17, 0.48), "fg": Color(1, 1, 1), "frame": Color(0.08, 0.16, 0.36), "awning": Color(0.05, 0.17, 0.48)},
	"星巴克咖啡": {"bg": Color(0.0, 0.38, 0.25), "fg": Color(1, 1, 1), "frame": Color(0.16, 0.12, 0.09), "awning": Color(0.0, 0.32, 0.21)},
	"霸王茶姬": {"bg": Color(0.66, 0.14, 0.16), "fg": Color(0.98, 0.94, 0.84), "frame": Color(0.24, 0.12, 0.10), "awning": Color(0.62, 0.14, 0.15)},
	"喜茶": {"bg": Color(0.08, 0.08, 0.09), "fg": Color(1, 1, 1), "frame": Color(0.14, 0.14, 0.15)},
	"蜜雪冰城": {"bg": Color(0.86, 0.12, 0.14), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.94, 0.94)},
	"肯德基": {"bg": Color(0.78, 0.08, 0.12), "fg": Color(1, 1, 1), "frame": Color(0.16, 0.16, 0.18)},
	"麦当劳": {"bg": Color(0.80, 0.08, 0.08), "fg": Color(1.0, 0.80, 0.08), "frame": Color(0.18, 0.18, 0.18)},
	"老娘舅": {"bg": Color(0.76, 0.18, 0.12), "fg": Color(1.0, 0.95, 0.82), "frame": Color(0.24, 0.16, 0.12)},
	"外婆家": {"bg": Color(0.18, 0.16, 0.14), "fg": Color(0.96, 0.88, 0.68), "frame": Color(0.22, 0.18, 0.15)},
	"海底捞火锅": {"bg": Color(0.74, 0.08, 0.10), "fg": Color(1, 1, 1), "frame": Color(0.18, 0.14, 0.14)},
	"全家便利店": {"bg": Color(0.96, 0.96, 0.96), "fg": Color(0.0, 0.56, 0.28), "frame": Color(0.0, 0.48, 0.78)},
	"罗森便利店": {"bg": Color(0.04, 0.42, 0.76), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.93, 0.95)},
	"盒马鲜生": {"bg": Color(0.02, 0.52, 0.84), "fg": Color(1, 1, 1), "frame": Color(0.12, 0.26, 0.40)},
	"新华书店": {"bg": Color(0.76, 0.10, 0.12), "fg": Color(1, 1, 1), "frame": Color(0.24, 0.22, 0.22)},
	"工商银行": {"bg": Color(0.76, 0.06, 0.12), "fg": Color(1, 1, 1), "frame": Color(0.26, 0.26, 0.28)},
	"建设银行": {"bg": Color(0.04, 0.24, 0.58), "fg": Color(1, 1, 1), "frame": Color(0.24, 0.26, 0.30)},
	"中国银行": {"bg": Color(0.66, 0.08, 0.14), "fg": Color(1, 1, 1), "frame": Color(0.26, 0.25, 0.26)},
	"农业银行": {"bg": Color(0.02, 0.48, 0.36), "fg": Color(1, 1, 1), "frame": Color(0.20, 0.28, 0.25)},
	"招商银行": {"bg": Color(0.82, 0.12, 0.14), "fg": Color(1, 1, 1), "frame": Color(0.25, 0.25, 0.27)},
	"嘉兴银行": {"bg": Color(0.06, 0.32, 0.62), "fg": Color(0.98, 0.90, 0.50), "frame": Color(0.22, 0.25, 0.30)},
	"华为授权体验店": {"bg": Color(0.10, 0.10, 0.11), "fg": Color(1, 1, 1), "frame": Color(0.76, 0.10, 0.12)},
	"小米之家": {"bg": Color(0.96, 0.42, 0.06), "fg": Color(1, 1, 1), "frame": Color(0.22, 0.22, 0.24)},
	"中国移动": {"bg": Color(0.02, 0.50, 0.80), "fg": Color(1, 1, 1), "frame": Color(0.20, 0.24, 0.28)},
	"中国电信": {"bg": Color(0.06, 0.32, 0.68), "fg": Color(1, 1, 1), "frame": Color(0.22, 0.24, 0.28)},
	"老百姓大药房": {"bg": Color(0.08, 0.54, 0.26), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.93, 0.92)},
	"海王星辰药房": {"bg": Color(0.06, 0.44, 0.68), "fg": Color(1, 1, 1), "frame": Color(0.90, 0.92, 0.94)},
	"戴梦得购物中心": {"bg": Color(0.14, 0.16, 0.24), "fg": Color(0.96, 0.84, 0.42), "frame": Color(0.24, 0.24, 0.28)},
	"八佰伴购物中心": {"bg": Color(0.12, 0.20, 0.36), "fg": Color(0.98, 0.92, 0.72), "frame": Color(0.20, 0.22, 0.26)},
	"万达广场": {"bg": Color(0.06, 0.28, 0.58), "fg": Color(1, 1, 1), "frame": Color(0.20, 0.24, 0.30)},
	"旭辉广场": {"bg": Color(0.74, 0.24, 0.12), "fg": Color(1, 1, 1), "frame": Color(0.24, 0.22, 0.22)},
	"南湖茶楼": {"bg": Color(0.20, 0.14, 0.10), "fg": Color(0.96, 0.86, 0.52), "frame": Color(0.28, 0.18, 0.12), "awning": Color(0.46, 0.16, 0.12)},
	"月河茶馆": {"bg": Color(0.18, 0.14, 0.11), "fg": Color(0.95, 0.86, 0.56), "frame": Color(0.26, 0.18, 0.12), "awning": Color(0.42, 0.16, 0.12)},
	"禾城老面馆": {"bg": Color(0.32, 0.16, 0.10), "fg": Color(0.98, 0.90, 0.64), "frame": Color(0.24, 0.15, 0.10), "awning": Color(0.52, 0.18, 0.12)},
	# Extended national & regional Chinese chain brands (standardized corporate fascia signboards)
	"奈雪的茶": {"bg": Color(0.54, 0.78, 0.24), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.92, 0.90), "awning": Color(0.46, 0.70, 0.20)},
	"古茗奶茶": {"bg": Color(0.94, 0.94, 0.92), "fg": Color(0.10, 0.10, 0.12), "frame": Color(0.18, 0.18, 0.20)},
	"沪上阿姨": {"bg": Color(0.68, 0.16, 0.24), "fg": Color(1.0, 0.95, 0.86), "frame": Color(0.22, 0.14, 0.16)},
	"coco都可": {"bg": Color(0.94, 0.46, 0.08), "fg": Color(1, 1, 1), "frame": Color(0.24, 0.20, 0.18)},
	"一点点": {"bg": Color(0.06, 0.44, 0.34), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.92, 0.90)},
	"塔斯汀汉堡": {"bg": Color(0.82, 0.12, 0.14), "fg": Color(1.0, 0.88, 0.38), "frame": Color(0.18, 0.14, 0.14)},
	"杨国福麻辣烫": {"bg": Color(0.92, 0.42, 0.06), "fg": Color(1, 1, 1), "frame": Color(0.24, 0.16, 0.12)},
	"绝味鸭脖": {"bg": Color(0.84, 0.08, 0.12), "fg": Color(1.0, 0.92, 0.20), "frame": Color(0.20, 0.12, 0.12)},
	"紫燕百味鸡": {"bg": Color(0.76, 0.10, 0.14), "fg": Color(1, 1, 1), "frame": Color(0.24, 0.16, 0.14)},
	"小菜园": {"bg": Color(0.16, 0.26, 0.18), "fg": Color(0.98, 0.94, 0.82), "frame": Color(0.24, 0.18, 0.14)},
	"十足便利店": {"bg": Color(0.88, 0.12, 0.14), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.94, 0.92)},
	"良品铺子": {"bg": Color(0.82, 0.10, 0.14), "fg": Color(1.0, 0.92, 0.68), "frame": Color(0.26, 0.18, 0.16)},
	"名创优品": {"bg": Color(0.88, 0.08, 0.16), "fg": Color(1, 1, 1), "frame": Color(0.95, 0.95, 0.95)},
	"屈臣氏": {"bg": Color(0.02, 0.60, 0.58), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.94, 0.94)},
	"邮政储蓄": {"bg": Color(0.02, 0.46, 0.22), "fg": Color(1, 1, 1), "frame": Color(0.22, 0.28, 0.24)},
	"中国联通": {"bg": Color(0.84, 0.08, 0.14), "fg": Color(1, 1, 1), "frame": Color(0.24, 0.24, 0.26)},
	"益丰大药房": {"bg": Color(0.04, 0.56, 0.26), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.94, 0.92)},
	"顺丰速运": {"bg": Color(0.10, 0.10, 0.12), "fg": Color(1, 1, 1), "frame": Color(0.80, 0.12, 0.14)},
	"菜鸟驿站": {"bg": Color(0.04, 0.46, 0.88), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.94, 0.96)},
	"链家房产": {"bg": Color(0.02, 0.60, 0.40), "fg": Color(1, 1, 1), "frame": Color(0.90, 0.92, 0.90)},
	"汉庭酒店": {"bg": Color(0.10, 0.34, 0.68), "fg": Color(1, 1, 1), "frame": Color(0.22, 0.24, 0.28)},
	"全季酒店": {"bg": Color(0.32, 0.26, 0.20), "fg": Color(0.96, 0.93, 0.86), "frame": Color(0.26, 0.22, 0.18)},
	"亚朵酒店": {"bg": Color(0.14, 0.16, 0.20), "fg": Color(0.96, 0.95, 0.92), "frame": Color(0.20, 0.22, 0.26)},
	"库迪咖啡": {"bg": Color(0.76, 0.12, 0.14), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.92, 0.88), "awning": Color(0.72, 0.14, 0.14)},
	"茶百道": {"bg": Color(0.06, 0.34, 0.72), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.95, 0.96)},
	"书亦烧仙草": {"bg": Color(0.78, 0.18, 0.16), "fg": Color(0.98, 0.95, 0.86), "frame": Color(0.26, 0.18, 0.14)},
	"美宜佳": {"bg": Color(0.86, 0.12, 0.12), "fg": Color(1.0, 0.88, 0.14), "frame": Color(0.94, 0.94, 0.92)},
	"赵一鸣零食": {"bg": Color(0.92, 0.14, 0.12), "fg": Color(1.0, 0.92, 0.16), "frame": Color(0.96, 0.94, 0.86)},
	"好特卖": {"bg": Color(0.95, 0.76, 0.08), "fg": Color(0.12, 0.12, 0.14), "frame": Color(0.16, 0.16, 0.18)},
	"百果园": {"bg": Color(0.10, 0.56, 0.22), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.95, 0.90), "awning": Color(0.14, 0.52, 0.22)},
	"鲜丰水果": {"bg": Color(0.16, 0.54, 0.18), "fg": Color(1.0, 0.94, 0.24), "frame": Color(0.92, 0.94, 0.90), "awning": Color(0.18, 0.50, 0.20)},
	"钱大妈": {"bg": Color(0.82, 0.14, 0.14), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.92, 0.90)},
	"来伊份": {"bg": Color(0.94, 0.44, 0.06), "fg": Color(1, 1, 1), "frame": Color(0.96, 0.92, 0.86)},
	"周黑鸭": {"bg": Color(0.95, 0.78, 0.06), "fg": Color(0.12, 0.10, 0.08), "frame": Color(0.16, 0.14, 0.12)},
	"巴比馒头": {"bg": Color(0.86, 0.34, 0.08), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.92, 0.86)},
	"张亮麻辣烫": {"bg": Color(0.88, 0.22, 0.10), "fg": Color(1, 1, 1), "frame": Color(0.24, 0.18, 0.16)},
	"袁记云饺": {"bg": Color(0.74, 0.16, 0.12), "fg": Color(0.98, 0.92, 0.70), "frame": Color(0.32, 0.22, 0.16)},
	"老盛昌": {"bg": Color(0.64, 0.14, 0.12), "fg": Color(0.98, 0.88, 0.44), "frame": Color(0.28, 0.18, 0.14)},
	"好利来": {"bg": Color(0.94, 0.92, 0.90), "fg": Color(0.16, 0.14, 0.14), "frame": Color(0.78, 0.74, 0.70), "awning": Color(0.84, 0.72, 0.68)},
	"必胜客": {"bg": Color(0.74, 0.10, 0.12), "fg": Color(1, 1, 1), "frame": Color(0.22, 0.18, 0.16)},
	"德克士": {"bg": Color(0.10, 0.50, 0.24), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.94, 0.92)},
	"一心堂药房": {"bg": Color(0.04, 0.56, 0.30), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.95, 0.94)},
	"博士眼镜": {"bg": Color(0.08, 0.22, 0.48), "fg": Color(1, 1, 1), "frame": Color(0.88, 0.90, 0.92)},
	"中通快递": {"bg": Color(0.04, 0.44, 0.84), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.94, 0.96)},
	"圆通快递": {"bg": Color(0.38, 0.14, 0.56), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.92, 0.94)},
	"雅迪电动车": {"bg": Color(0.92, 0.42, 0.06), "fg": Color(1, 1, 1), "frame": Color(0.22, 0.24, 0.28)},
	"爱玛电动车": {"bg": Color(0.84, 0.10, 0.24), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.92, 0.94)},
	# Real Jiaxing Google Maps surveyed merchants & chains
	"捷安特": {"bg": Color(0.05, 0.28, 0.64), "fg": Color(1, 1, 1), "frame": Color(0.16, 0.18, 0.22)},
	"卡萨帝旗舰店": {"bg": Color(0.10, 0.10, 0.12), "fg": Color(0.88, 0.78, 0.56), "frame": Color(0.18, 0.18, 0.20)},
	"colmo智感体验馆": {"bg": Color(0.12, 0.13, 0.15), "fg": Color(0.94, 0.95, 0.97), "frame": Color(0.20, 0.22, 0.25)},
	"禾城陆稿荐": {"bg": Color(0.56, 0.10, 0.10), "fg": Color(0.98, 0.88, 0.44), "frame": Color(0.28, 0.16, 0.10)},
	"元祖": {"bg": Color(0.68, 0.14, 0.28), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.92, 0.90)},
	"欧尚超市": {"bg": Color(0.84, 0.10, 0.14), "fg": Color(1, 1, 1), "frame": Color(0.08, 0.54, 0.24)},
	"大润发玛特": {"bg": Color(0.82, 0.08, 0.12), "fg": Color(1.0, 0.94, 0.22), "frame": Color(0.92, 0.92, 0.90)},
	"麦德龙": {"bg": Color(0.04, 0.24, 0.58), "fg": Color(1.0, 0.84, 0.08), "frame": Color(0.12, 0.22, 0.40)},
	"国美电器": {"bg": Color(0.84, 0.08, 0.16), "fg": Color(1, 1, 1), "frame": Color(0.20, 0.20, 0.22)},
	"三福时尚": {"bg": Color(0.10, 0.10, 0.12), "fg": Color(1, 1, 1), "frame": Color(0.90, 0.90, 0.90)},
	"乔丹体育": {"bg": Color(0.78, 0.08, 0.12), "fg": Color(1, 1, 1), "frame": Color(0.18, 0.18, 0.20)},
	"易捷便利店": {"bg": Color(0.06, 0.54, 0.26), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.94, 0.92)},
	"可的便利店": {"bg": Color(0.92, 0.42, 0.06), "fg": Color(1, 1, 1), "frame": Color(0.04, 0.36, 0.68)},
	"华莱士·全鸡汉堡": {"bg": Color(0.84, 0.12, 0.10), "fg": Color(1.0, 0.88, 0.16), "frame": Color(0.92, 0.92, 0.90)},
	"安信证券": {"bg": Color(0.04, 0.24, 0.56), "fg": Color(1, 1, 1), "frame": Color(0.24, 0.26, 0.30)},
	"万家福超市": {"bg": Color(0.86, 0.12, 0.14), "fg": Color(1.0, 0.92, 0.22), "frame": Color(0.92, 0.92, 0.90)},
	"好万家超市": {"bg": Color(0.10, 0.52, 0.24), "fg": Color(1, 1, 1), "frame": Color(0.94, 0.94, 0.92)},
	"如家派柏·云酒店": {"bg": Color(0.06, 0.44, 0.76), "fg": Color(1.0, 0.90, 0.20), "frame": Color(0.20, 0.24, 0.28)},
	"维也纳国际酒店": {"bg": Color(0.14, 0.12, 0.10), "fg": Color(0.94, 0.78, 0.36), "frame": Color(0.24, 0.20, 0.16)},
	"迪欧咖啡": {"bg": Color(0.32, 0.18, 0.12), "fg": Color(0.96, 0.88, 0.66), "frame": Color(0.24, 0.16, 0.12), "awning": Color(0.38, 0.20, 0.14)},
	"戴梦得超市": {"bg": Color(0.12, 0.24, 0.46), "fg": Color(0.98, 0.86, 0.40), "frame": Color(0.22, 0.24, 0.28)},
	"中国农业银行": {"bg": Color(0.02, 0.48, 0.36), "fg": Color(1, 1, 1), "frame": Color(0.20, 0.28, 0.25)},
	"嘉兴老百姓药房": {"bg": Color(0.08, 0.54, 0.26), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.93, 0.92)},
	"万寿堂药房": {"bg": Color(0.08, 0.48, 0.24), "fg": Color(0.98, 0.92, 0.60), "frame": Color(0.24, 0.28, 0.24)},
	"正大药房": {"bg": Color(0.06, 0.52, 0.26), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.94, 0.92)},
	"广济大药房": {"bg": Color(0.06, 0.50, 0.28), "fg": Color(1, 1, 1), "frame": Color(0.92, 0.94, 0.92)},
	"五芳斋总店": {"bg": Color(0.68, 0.10, 0.10), "fg": Color(0.98, 0.85, 0.36), "frame": Color(0.32, 0.16, 0.10), "awning": Color(0.62, 0.11, 0.11)},
}

# Authentic earthy local Chinese street-shop PVC/acrylic lightbox palettes (接地气非连锁底商招牌):
# [bg, fg, frame, awning] — 14 rich varied boards & storefront treatments!
const LOCAL_CHINESE_STYLES := [
	[Color(0.84, 0.10, 0.10), Color(1.0, 1.0, 1.0), Color(0.32, 0.30, 0.30), Color(0.76, 0.14, 0.14)],    # 经典大红底白字 (小吃/副食/五金)
	[Color(0.80, 0.08, 0.08), Color(1.0, 0.90, 0.16), Color(0.30, 0.24, 0.20), Color(0.72, 0.12, 0.10)],  # 经典大红底黄字 (牛肉面/足浴/宾馆)
	[Color(0.05, 0.32, 0.78), Color(1.0, 1.0, 1.0), Color(0.34, 0.36, 0.40), Color(0.08, 0.36, 0.72)],    # 经典蓝底白字 (电动车维修/打印/手机快修)
	[Color(0.06, 0.54, 0.24), Color(1.0, 1.0, 1.0), Color(0.28, 0.34, 0.30), Color(0.08, 0.48, 0.22)],    # 经典绿底白字 (生鲜果蔬/药房/早点)
	[Color(0.95, 0.78, 0.08), Color(0.82, 0.06, 0.08), Color(0.36, 0.32, 0.24), Color(0.86, 0.16, 0.12)], # 亮黄底大红字 (臭豆腐/鸡排/百货特卖)
	[Color(0.92, 0.38, 0.06), Color(1.0, 1.0, 1.0), Color(0.32, 0.26, 0.22), Color(0.84, 0.34, 0.08)],    # 亮橙底白字 (理发/烟酒/快递)
	[Color(0.56, 0.08, 0.14), Color(1.0, 0.92, 0.56), Color(0.28, 0.20, 0.18), Color(0.52, 0.12, 0.14)],  # 枣红底金字 (老面馆/茶庄/糕点)
	[Color(0.04, 0.48, 0.56), Color(1.0, 1.0, 1.0), Color(0.30, 0.34, 0.36), Color(0.08, 0.42, 0.48)],    # 蓝绿底白字 (干洗/眼镜/社区服务)
	[Color(0.16, 0.17, 0.20), Color(0.98, 0.86, 0.40), Color(0.24, 0.24, 0.26), Color(0.22, 0.22, 0.26)], # 哑光黑金 (烧烤/咖啡/文创/理发)
	[Color(0.92, 0.90, 0.85), Color(0.24, 0.16, 0.12), Color(0.46, 0.34, 0.24), Color(0.56, 0.36, 0.22)], # 原木米白 (烘焙/茶室/花店)
	[Color(0.22, 0.38, 0.26), Color(0.98, 0.95, 0.84), Color(0.34, 0.28, 0.22), Color(0.20, 0.36, 0.24)], # 墨绿暖白 (茶叶/中药/私房菜)
	[Color(0.54, 0.14, 0.44), Color(1.0, 0.96, 0.92), Color(0.30, 0.24, 0.28), Color(0.50, 0.16, 0.40)],  # 玫紫亮白 (美容美甲/母婴/女装)
	[Color(0.10, 0.20, 0.42), Color(0.98, 0.88, 0.34), Color(0.24, 0.28, 0.34), Color(0.14, 0.24, 0.46)], # 藏青金字 (房产/律所/五金机电)
	[Color(0.76, 0.28, 0.18), Color(1.0, 0.96, 0.88), Color(0.36, 0.24, 0.18), Color(0.68, 0.24, 0.16)],  # 砖红暖白 (卤味/火锅/家常菜)
]

# Fallback palettes by shop category: [bg, fg, frame, awning]
const CAT_STYLES := {
	"food": [[Color(0.12, 0.10, 0.09), Color(0.96, 0.90, 0.78), Color(0.20, 0.14, 0.10), Color(0.48, 0.12, 0.10)],
		[Color(0.08, 0.20, 0.16), Color(0.95, 0.92, 0.84), Color(0.10, 0.18, 0.14), Color(0.10, 0.28, 0.20)],
		[Color(0.55, 0.12, 0.10), Color(1.0, 0.95, 0.85), Color(0.18, 0.18, 0.18), Color(0.62, 0.14, 0.12)],
		[Color(0.90, 0.86, 0.78), Color(0.20, 0.14, 0.10), Color(0.32, 0.22, 0.14), Color(0.20, 0.30, 0.45)]],
	"retail": [[Color(0.06, 0.06, 0.06), Color(1, 1, 1), Color(0.08, 0.08, 0.08), Color(0.1, 0.1, 0.1)],
		[Color(0.95, 0.95, 0.94), Color(0.08, 0.08, 0.08), Color(0.70, 0.70, 0.70), Color(0.2, 0.2, 0.2)],
		[Color(0.14, 0.18, 0.26), Color(0.95, 0.92, 0.84), Color(0.16, 0.18, 0.22), Color(0.14, 0.18, 0.26)],
		[Color(0.40, 0.32, 0.24), Color(1, 1, 1), Color(0.30, 0.22, 0.15), Color(0.40, 0.32, 0.24)]],
	"service": [[Color(0.12, 0.14, 0.18), Color(1, 1, 1), Color(0.22, 0.24, 0.27), Color(0.12, 0.14, 0.18)],
		[Color(0.92, 0.90, 0.88), Color(0.30, 0.20, 0.25), Color(0.60, 0.58, 0.56), Color(0.70, 0.45, 0.50)]],
	"bar": [[Color(0.08, 0.06, 0.05), Color(0.95, 0.75, 0.40), Color(0.12, 0.08, 0.05), Color(0.25, 0.10, 0.08)],
		[Color(0.10, 0.12, 0.10), Color(0.92, 0.88, 0.70), Color(0.10, 0.12, 0.10), Color(0.12, 0.22, 0.14)]],
}

const FOOD := ["cafe", "restaurant", "fast_food", "bakery", "deli", "ice_cream", "food_court", "confectionery", "chocolate", "cheese", "butcher", "greengrocer", "beverages"]
const BARS := ["bar", "pub", "nightclub", "alcohol"]
const GROCERY := ["convenience", "supermarket", "pharmacy", "chemist", "grocery", "doityourself", "hardware"]
const OFFICE := ["bank", "hotel", "optician", "hairdresser", "beauty", "tattoo", "dry_cleaning", "storage_rental", "telecommunication", "mobile_phone", "ticket"]


const CELL := 200.0
const FRAME_RANGE := 420.0 # mullions, awnings, signs' boxes
const GLASS_RANGE := 650.0 # lit shop windows read further at night

static var _frame_mat_cache: StandardMaterial3D = null
static var _glass_mat_cache: ShaderMaterial = null


static func build_storefronts(parent: Node3D, storefronts: Array, buildings: Array) -> ShaderMaterial:
	if storefronts.is_empty():
		return null
	var labels := Node3D.new()
	labels.name = "StorefrontSigns"
	if Terrain.active:
		labels.set_meta("on_terrain", true)
	parent.add_child(labels)

	# One frame + one glazing mesh per CELL so distant blocks are culled and far ones drop out by range; a single
	# map-wide mesh (1.7M triangles on the Jiaxing core) was otherwise drawn whole whenever any shop was in view
	var cells := {} # Vector2i -> [frame SurfaceTool, glass SurfaceTool]
	for sf: Dictionary in storefronts:
		var bi := int(sf.get("b", -1))
		var bh := 12.0
		if bi >= 0 and bi < buildings.size():
			bh = float((buildings[bi] as Dictionary).get("h", 12.0))
		var p0a: Array = sf["p0"]
		var ck := Vector2i(floori(float(p0a[0]) / CELL), floori(float(p0a[1]) / CELL))
		if not cells.has(ck):
			var a1 := SurfaceTool.new()
			a1.begin(Mesh.PRIMITIVE_TRIANGLES)
			var a2 := SurfaceTool.new()
			a2.begin(Mesh.PRIMITIVE_TRIANGLES)
			cells[ck] = [a1, a2]
		_build_one(cells[ck][0], cells[ck][1], labels, sf, bh)

	if _frame_mat_cache == null:
		_frame_mat_cache = StandardMaterial3D.new()
		_frame_mat_cache.vertex_color_use_as_albedo = true
		_frame_mat_cache.roughness = 0.55
		_frame_mat_cache.metallic = 0.25
		_frame_mat_cache.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _glass_mat_cache == null:
		_glass_mat_cache = ShaderMaterial.new()
		_glass_mat_cache.shader = load("res://shaders/shopfront_glass.gdshader") as Shader
	var f_grp := Node3D.new()
	f_grp.name = "StorefrontFrames"
	parent.add_child(f_grp)
	var g_grp := Node3D.new()
	g_grp.name = "StorefrontGlazing"
	parent.add_child(g_grp)
	for ck: Vector2i in cells.keys():
		var f_mi := MeshInstance3D.new()
		f_mi.name = "StorefrontFrames_%d_%d" % [ck.x, ck.y]
		f_mi.mesh = Terrain.commit_draped(cells[ck][0], f_mi)
		f_mi.material_override = _frame_mat_cache
		f_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f_mi.visibility_range_end = FRAME_RANGE
		f_mi.visibility_range_end_margin = 30.0
		f_grp.add_child(f_mi)
		var g_mi := MeshInstance3D.new()
		g_mi.name = "StorefrontGlazing_%d_%d" % [ck.x, ck.y]
		g_mi.mesh = Terrain.commit_draped(cells[ck][1], g_mi)
		g_mi.material_override = _glass_mat_cache
		g_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g_mi.visibility_range_end = GLASS_RANGE
		g_mi.visibility_range_end_margin = 40.0
		g_grp.add_child(g_mi)
	return _glass_mat_cache


static func _style_for(sf: Dictionary) -> Dictionary:
	var kind := str(sf.get("kind", ""))
	var name := str(sf.get("name", ""))
	var tier := str(sf.get("tier", ""))
	var key := str(sf.get("brand", "")).to_lower()
	if not BRANDS.has(key):
		key = name.to_lower()
	var h := absi(hash(name))
	var interior := INTERIOR_RETAIL
	var cat := "retail"
	if kind in FOOD:
		interior = INTERIOR_CAFE
		cat = "food"
	elif kind in BARS:
		interior = INTERIOR_BAR
		cat = "bar"
	elif kind in GROCERY:
		interior = INTERIOR_GROCERY
		cat = "service"
	elif kind in OFFICE:
		interior = INTERIOR_OFFICE
		cat = "service"
	var pal: Array = CAT_STYLES[cat][h % (CAT_STYLES[cat] as Array).size()]
	var is_local_zh := (tier == "local") and not BRANDS.has(key)
	if is_local_zh:
		# Pick characteristic earthy Chinese street signboard colors by business type!
		var l_idx := h % LOCAL_CHINESE_STYLES.size()
		if kind in ["hardware", "mobile_phone", "office", "dry_cleaning"]:
			l_idx = 2 if (h % 3 != 0) else 0  # Blue-white or Red-white
		elif kind in ["greengrocer", "pharmacy"]:
			l_idx = 3 if (h % 3 != 0) else 0  # Green-white or Red-white
		elif kind in ["fast_food", "restaurant"]:
			var f_picks := [0, 1, 4, 5, 6]
			l_idx = f_picks[h % f_picks.size()]
		pal = LOCAL_CHINESE_STYLES[l_idx]
	var st := {
		"bg": pal[0], "fg": pal[1], "frame": pal[2], "awning": pal[3], "letters": false,
		"is_local_zh": is_local_zh,
		"interior": interior, "accent": (pal[3] as Color).lerp(Color(0.8, 0.7, 0.5), 0.3),
		"has_awning": (is_local_zh and h % 2 == 0) or (cat == "food" and h % 3 != 0) or (cat == "bar" and h % 2 == 0) or kind == "florist",
		"has_blade": (is_local_zh and h % 4 == 0) or ((cat == "food" or cat == "bar") and h % 4 < 2),
		"planters": kind == "restaurant" and h % 3 == 0,
		"cafe_tables": kind == "cafe" and h % 2 == 0,
		"striped": (is_local_zh and h % 3 == 0) or (cat == "food" and h % 5 == 0),
	}
	if BRANDS.has(key):
		var b: Dictionary = BRANDS[key]
		for k in b.keys():
			st[k] = b[k]
		st["accent"] = (st["bg"] as Color) if not bool(st["letters"]) else (st["frame"] as Color).lightened(0.4)
		st["has_awning"] = b.has("awning")
		st["has_blade"] = false
		st["striped"] = false
		st["is_local_zh"] = false
	if (st["bg"] as Color).get_luminance() < 0.05 and not bool(st["letters"]):
		st["accent"] = Color(0.75, 0.70, 0.62)
	return st


static func _build_one(fst: SurfaceTool, gst: SurfaceTool, labels: Node3D, sf: Dictionary, bh: float) -> void:
	var p0a: Array = sf["p0"]
	var p1a: Array = sf["p1"]
	var na: Array = sf["n"]
	var o := Vector3(float(p0a[0]), 0.0, float(p0a[1]))
	var e := Vector3(float(p1a[0]), 0.0, float(p1a[1])) - o
	var w := e.length()
	if w < 2.5:
		return
	var U := e / w
	var N := Vector3(float(na[0]), 0.0, float(na[1])).normalized()
	var st := _style_for(sf)
	var gh := 4.4 if bh >= 7.0 else clampf(bh - 0.8, 3.2, 4.0)
	var tier_s := str(sf.get("tier", ""))
	var is_zh_shop := tier_s == "chain" or tier_s == "local"
	var frame_c: Color = st["frame"]
	var name_txt := str(sf.get("name", ""))
	var nh := absi(hash(name_txt))
	var bulk_c: Color = Color(0.28, 0.29, 0.31) if is_zh_shop else (Color(0.20, 0.20, 0.21) if (nh % 2 == 0) else frame_c.darkened(0.25))
	var is_local_zh := bool(st.get("is_local_zh", false))
	# Diversify signboard heights, depths, and pilaster claddings across neighboring bays so street rows look genuinely distinct!
	var pos_h := absi(hash(Vector2i(int(round(o.x * 2.0)), int(round(o.z * 2.0)))))
	var v_var := (nh ^ pos_h)
	var sign_h_delta: float = 0.0 if not is_zh_shop else float([-0.14, -0.05, 0.06, 0.16][v_var % 4])
	var sign_y0 := ((gh - 1.20) if is_local_zh else (gh - 1.04)) - sign_h_delta
	var sign_y1 := ((gh - 0.14) if is_local_zh else (gh - 0.16)) + clampf(sign_h_delta * 0.25, -0.04, 0.06)
	var sign_d := (0.42 if is_local_zh else 0.34) + (0.08 if (v_var % 5 == 0) else (-0.05 if (v_var % 5 == 3) else 0.0))
	var glass_top := sign_y0 - 0.06
	var has_awning := bool(st["has_awning"]) or (is_zh_shop and (v_var % 7 < 2))
	if has_awning:
		glass_top = sign_y0 - 0.10
	var pil := 0.24 if is_zh_shop else 0.32
	var ctx := {"o": o, "u": U, "n": N, "st": fst}

	# Varied Pilaster Claddings (granite / dark slate / warm wood / brick / charcoal) + Unified Podium Cornice
	var zh_pil_pal := [
		Color(0.68, 0.66, 0.62), Color(0.32, 0.34, 0.37), Color(0.56, 0.40, 0.26),
		Color(0.62, 0.34, 0.26), Color(0.76, 0.72, 0.65), Color(0.24, 0.25, 0.28),
	]
	var pil_c: Color = zh_pil_pal[v_var % zh_pil_pal.size()] if is_zh_shop else frame_c
	_box(ctx, 0.0, pil, 0.0, sign_y0, 0.0, 0.32, pil_c)
	_box(ctx, w - pil, w, 0.0, sign_y0, 0.0, 0.32, pil_c)
	if is_zh_shop:
		# Continuous architectural granite podium coping & dark plinth kickplate connecting adjacent shops!
		_box(ctx, 0.0, w, gh - 0.12, gh + 0.06, 0.0, 0.44, Color(0.74, 0.72, 0.68))
		_box(ctx, 0.0, pil, 0.0, 0.44, 0.0, 0.35, Color(0.32, 0.33, 0.35))
		_box(ctx, w - pil, w, 0.0, 0.44, 0.0, 0.35, Color(0.32, 0.33, 0.35))
		# Distinctive business-type storefront accents: pharmacy green cross / barber pole / decorative neon frame!
		var k_zh := str(sf.get("kind", ""))
		if k_zh == "pharmacy":
			var gx_c := w - 0.55 if (v_var % 2 == 0) else 0.55
			_box(ctx, gx_c - 0.26, gx_c + 0.26, sign_y0 + 0.32, sign_y0 + 0.52, sign_d, sign_d + 0.08, Color(0.06, 0.78, 0.28))
			_box(ctx, gx_c - 0.10, gx_c + 0.10, sign_y0 + 0.16, sign_y0 + 0.68, sign_d, sign_d + 0.08, Color(0.06, 0.78, 0.28))
		elif k_zh == "hairdresser":
			var bx_p := 0.28 if (v_var % 2 == 0) else (w - 0.28)
			_box(ctx, bx_p - 0.09, bx_p + 0.09, 1.55, 2.35, 0.32, 0.50, Color(0.92, 0.94, 0.96))
			_box(ctx, bx_p - 0.095, bx_p + 0.095, 1.72, 1.92, 0.33, 0.51, Color(0.86, 0.12, 0.14))
			_box(ctx, bx_p - 0.095, bx_p + 0.095, 2.02, 2.22, 0.33, 0.51, Color(0.10, 0.32, 0.82))
		elif k_zh in ["cafe", "bakery"] and v_var % 3 == 0:
			# Warm slatted timber shopfront accent header & flower planter box
			_box(ctx, pil, w - pil, sign_y0 - 0.08, sign_y0, 0.04, 0.30, Color(0.56, 0.38, 0.22))
	if bool(st["letters"]):
		# Stone fascia band with raised individual letters
		_box(ctx, 0.0, w, sign_y0, sign_y1, 0.0, 0.22, Color(0.80, 0.77, 0.72))
	else:
		_box(ctx, 0.05, w - 0.05, sign_y0, sign_y1, 0.0, sign_d, st["bg"])
		var trim_c := Color(0.88, 0.88, 0.86) if is_local_zh else frame_c.darkened(0.3)
		_box(ctx, 0.03, w - 0.03, sign_y1, sign_y1 + 0.045, 0.0, sign_d + 0.035, trim_c)
		_box(ctx, 0.03, w - 0.03, sign_y0 - 0.04, sign_y0, 0.0, sign_d + 0.035, trim_c)
		if is_zh_shop:
			# Subtle under-fascia warm LED diffuser bar (门头底部暖白灯带)
			_box(ctx, 0.14, w - 0.14, sign_y0 - 0.065, sign_y0 - 0.035, 0.12, sign_d - 0.04, Color(0.98, 0.94, 0.82))

	# Entrance door position (recessed double door for wide shops, single otherwise)
	var door_w := 1.95 if w >= 6.4 else 1.15
	var door_c := w * 0.5 if w < 6.2 else (w * 0.34 if nh % 2 == 0 else w * 0.66)
	var d0 := door_c - door_w * 0.5
	var d1 := door_c + door_w * 0.5
	var sill := 0.44 if is_zh_shop else 0.48
	# Bulkhead (skip under the door)
	_box(ctx, pil, d0, 0.0, sill, 0.0, 0.22, bulk_c)
	_box(ctx, d1, w - pil, 0.0, sill, 0.0, 0.22, bulk_c)
	_box(ctx, pil, d0, sill, sill + 0.05, 0.0, 0.26, frame_c.lightened(0.1))
	_box(ctx, d1, w - pil, sill, sill + 0.05, 0.0, 0.26, frame_c.lightened(0.1))
	# Glazing (shop windows + door glass), interior shader. Code: interior | 8 door | 16 posters | 32 local shop
	var acc_c: Color = st["accent"]
	var code := int(st["interior"]) + (32 if is_local_zh else 0)
	var win_code := code + (16 if (is_zh_shop and nh % 5 < 3) or (not is_zh_shop and nh % 4 == 0) else 0)
	var col := Color(acc_c.r, acc_c.g, acc_c.b, float(win_code) / 255.0)
	var door_col := Color(acc_c.r, acc_c.g, acc_c.b, float(code + 8) / 255.0)
	_glass(gst, o, U, N, pil, d0, sill, glass_top, 0.10, col)
	_glass(gst, o, U, N, d1, w - pil, sill, glass_top, 0.10, col)
	_glass(gst, o, U, N, d0, d1, 0.02, glass_top, -0.22, door_col) # door set back into a shallow vestibule
	# Scrolling red LED text board over the door (LED走字屏) on many local shops
	if is_local_zh and nh % 3 == 0 and glass_top > 2.9:
		var lb0 := maxf(pil + 0.05, d0 - 0.35)
		var lb1 := minf(w - pil - 0.05, d1 + 0.35)
		_box(ctx, lb0 - 0.04, lb1 + 0.04, glass_top - 0.66, glass_top - 0.30, 0.10, 0.20, Color(0.08, 0.08, 0.09))
		_panel(gst, o, U, N, lb0, lb1, glass_top - 0.62, glass_top - 0.34, 0.205, Color(0.0, 0.0, 0.0, 5.0 / 255.0))
	# Door vestibule: reveals, granite step threshold, welcome mat, aluminum door stiles, frosted stripe & stainless handles!
	_box(ctx, d0 - 0.06, d0, 0.0, glass_top, -0.26, 0.28, frame_c)
	_box(ctx, d1, d1 + 0.06, 0.0, glass_top, -0.26, 0.28, frame_c)
	_box(ctx, d0 - 0.08, d1 + 0.08, 0.0, 0.06, -0.26, 0.34, Color(0.60, 0.59, 0.56))
	if is_zh_shop:
		_box(ctx, d0 + 0.12, d1 - 0.12, 0.06, 0.085, 0.02, 0.32, Color(0.58, 0.14, 0.14) if is_local_zh else Color(0.22, 0.24, 0.26))
		# Frosted anti-collision safety strip across Chinese glass entrance door (玻璃门防撞腰线)
		_box(ctx, d0 + 0.04, d1 - 0.04, 1.06, 1.13, -0.21, -0.19, Color(0.88, 0.90, 0.92))
	_box(ctx, d0, d1, 2.28, 2.36, -0.26, -0.18, frame_c)
	if door_w > 1.5:
		_box(ctx, door_c - 0.04, door_c + 0.04, 0.02, 2.28, -0.26, -0.17, frame_c)
	for hx: float in ([door_c - 0.22, door_c + 0.22] if door_w > 1.5 else [d1 - 0.18]):
		_box(ctx, hx - 0.022, hx + 0.022, 0.78, 1.42, -0.18, -0.11, Color(0.84, 0.85, 0.86))
	# Rolled-up galvanized metal security shutter hood box (卷帘门盒 — authentic Chinese street shop detail!)
	if is_local_zh or (is_zh_shop and str(sf.get("kind", "")) in ["convenience", "hardware", "greengrocer", "pharmacy"]):
		_box(ctx, pil, w - pil, glass_top - 0.24, glass_top, 0.0, 0.32, Color(0.70, 0.72, 0.74))
		_box(ctx, pil, w - pil, glass_top - 0.26, glass_top - 0.24, 0.26, 0.33, Color(0.45, 0.47, 0.50))
		# A few shutters are part-way down (opening / closing up) or shut (closed today), with guide rails
		var sh_k := nh % 17
		if is_local_zh and sh_k < 3:
			var sh_bot := 0.02 if sh_k == 0 else glass_top - 0.95 - 0.35 * float(sh_k)
			_panel(gst, o, U, N, pil, w - pil, sh_bot, glass_top - 0.26, 0.29, Color(0.0, 0.0, 0.0, 6.0 / 255.0))
			_box(ctx, pil, pil + 0.06, 0.0, glass_top - 0.26, 0.10, 0.31, Color(0.55, 0.57, 0.60))
			_box(ctx, w - pil - 0.06, w - pil, 0.0, glass_top - 0.26, 0.10, 0.31, Color(0.55, 0.57, 0.60))
			_box(ctx, pil, w - pil, sh_bot - 0.05, sh_bot, 0.24, 0.32, Color(0.40, 0.42, 0.45))
	# Window mullions and transom bar
	var spans: Array = [[pil, d0], [d1, w - pil]]
	for sp: Array in spans:
		var a := float(sp[0])
		var b := float(sp[1])
		if b - a < 0.4:
			continue
		var n_m := maxi(1, int(round((b - a) / 2.0)))
		for k in range(1, n_m):
			var mu := lerpf(a, b, float(k) / float(n_m))
			_box(ctx, mu - 0.032, mu + 0.032, sill, glass_top, 0.0, 0.16, frame_c)
		_box(ctx, a, b, glass_top - 0.72, glass_top - 0.67, 0.0, 0.15, frame_c)
	_box(ctx, pil, w - pil, glass_top - 0.02, sign_y0, 0.0, 0.18, frame_c.darkened(0.15))

	# Authentic Chinese Shopfront Street Props:
	# 1) Air-Conditioner Outdoor Unit (空调外机) mounted beside fascia on ~40% of local shops
	if is_local_zh and nh % 5 < 2 and w >= 4.2:
		var acu := w - 0.58 if door_c < w * 0.5 else 0.58
		_box(ctx, acu - 0.34, acu + 0.34, glass_top - 0.56, glass_top - 0.04, 0.18, 0.50, Color(0.84, 0.85, 0.83))
		_box(ctx, acu - 0.24, acu + 0.08, glass_top - 0.48, glass_top - 0.12, 0.50, 0.52, Color(0.22, 0.24, 0.26))
	# 2) Hanging Chinese Red Lanterns (传统红灯笼) on traditional food/noodle/zongzi/tea shops!
	if is_zh_shop and (name_txt.contains("粽") or name_txt.contains("面") or name_txt.contains("茶") or name_txt.contains("火锅") or name_txt.contains("烧烤") or name_txt.contains("小炒") or name_txt.contains("酱鸭") or name_txt.contains("老字号")):
		for lu: float in [maxf(0.45, d0 - 0.38), minf(w - 0.45, d1 + 0.38)]:
			_box(ctx, lu - 0.16, lu + 0.16, 2.58, 2.98, 0.38, 0.70, Color(0.86, 0.10, 0.10))
			_box(ctx, lu - 0.11, lu + 0.11, 2.98, 3.04, 0.43, 0.65, Color(0.94, 0.78, 0.22))
			_box(ctx, lu - 0.11, lu + 0.11, 2.52, 2.58, 0.43, 0.65, Color(0.94, 0.78, 0.22))
	# 3) Neat Sidewalk Produce / Fruit Display Crates (生鲜水果展示筐) on greengrocers & fruit shops!
	if str(sf.get("kind", "")) == "greengrocer" and w >= 4.2:
		var r_u0 := d1 + 0.25 if (w - d1) >= 1.5 else pil + 0.18
		var r_u1 := (w - pil - 0.18) if (w - d1) >= 1.5 else (d0 - 0.25)
		if r_u1 - r_u0 >= 1.0:
			_box(ctx, r_u0, r_u1, WALK_Y, WALK_Y + 0.58, 0.26, 0.88, Color(0.24, 0.46, 0.22))
			_box(ctx, r_u0 + 0.08, (r_u0 + r_u1) * 0.5 - 0.04, WALK_Y + 0.58, WALK_Y + 0.74, 0.30, 0.84, Color(0.92, 0.52, 0.12))
			_box(ctx, (r_u0 + r_u1) * 0.5 + 0.04, r_u1 - 0.08, WALK_Y + 0.58, WALK_Y + 0.74, 0.30, 0.84, Color(0.84, 0.20, 0.16))

	# 4) Out-front seating of small eateries (外摆): folding tables with red plastic stools
	var kind_s := str(sf.get("kind", ""))
	if is_local_zh and kind_s in ["restaurant", "fast_food"] and nh % 10 < 3 and w >= 5.0:
		for tu: float in [w * 0.25, w * 0.75]:
			if absf(tu - door_c) < door_w * 0.8:
				continue
			_box(ctx, tu - 0.42, tu + 0.42, WALK_Y + 0.70, WALK_Y + 0.74, 1.10, 1.80, Color(0.90, 0.88, 0.84))
			for lu: float in [-0.36, 0.36]:
				for ld: float in [1.16, 1.74]:
					_box(ctx, tu + lu - 0.02, tu + lu + 0.02, WALK_Y, WALK_Y + 0.70, ld - 0.02, ld + 0.02, Color(0.55, 0.56, 0.58))
			for su: Vector2 in [Vector2(-0.62, 1.45), Vector2(0.62, 1.45), Vector2(0.0, 2.15)]:
				_box(ctx, tu + su.x - 0.15, tu + su.x + 0.15, WALK_Y, WALK_Y + 0.45, su.y - 0.15, su.y + 0.15, Color(0.78, 0.14, 0.12))
	# 5) Convenience / snack shops: ice-cream chest freezer and a drinks cooler out on the pavement
	if is_zh_shop and kind_s in ["convenience", "supermarket", "beverages"] and nh % 5 < 2 and w >= 4.0:
		var fu := pil + 0.75 if door_c > w * 0.5 else w - pil - 0.75
		_box(ctx, fu - 0.62, fu + 0.62, WALK_Y, WALK_Y + 0.82, 0.25, 0.95, Color(0.93, 0.93, 0.92))
		_box(ctx, fu - 0.58, fu + 0.58, WALK_Y + 0.82, WALK_Y + 0.86, 0.29, 0.91, Color(0.70, 0.82, 0.90))
		_box(ctx, fu - 0.62, fu + 0.62, WALK_Y + 0.55, WALK_Y + 0.70, 0.95, 0.96, acc_c)

	# Sign lettering
	var letters := bool(st["letters"])
	var txt := name_txt.to_upper() if (letters or name_txt.length() <= 12) else name_txt
	var depth := 0.235 if letters else (sign_d + 0.018)
	_sign_label(labels, o + U * (w * 0.5) + N * depth + Vector3.UP * ((sign_y0 + sign_y1) * 0.5), N, txt, w * 0.86, (sign_y1 - sign_y0) * (0.68 if is_local_zh else 0.62), st["fg"], letters)

	# Awning (sloped fabric with valance; striped for some cafes)
	if has_awning:
		var aw_c: Color = st["awning"]
		var y_top := sign_y0 - 0.02
		var proj := 1.35
		var drop := 0.55
		var n_str := int(ceil((w - 0.2) / 0.55)) if bool(st["striped"]) else 1
		for k in range(n_str):
			var a0 := lerpf(0.1, w - 0.1, float(k) / float(n_str))
			var a1 := lerpf(0.1, w - 0.1, float(k + 1) / float(n_str))
			var c := aw_c if k % 2 == 0 else Color(0.94, 0.92, 0.86)
			_quad(fst, o + U * a0 + N * 0.3 + Vector3.UP * y_top, o + U * a1 + N * 0.3 + Vector3.UP * y_top,
				o + U * a1 + N * proj + Vector3.UP * (y_top - drop), o + U * a0 + N * proj + Vector3.UP * (y_top - drop), c)
			_quad(fst, o + U * a0 + N * proj + Vector3.UP * (y_top - drop), o + U * a1 + N * proj + Vector3.UP * (y_top - drop),
				o + U * a1 + N * proj + Vector3.UP * (y_top - drop - 0.26), o + U * a0 + N * proj + Vector3.UP * (y_top - drop - 0.26), c.darkened(0.12))
		for end_u: float in [0.1, w - 0.1]:
			_tri(fst, o + U * end_u + N * 0.3 + Vector3.UP * y_top, o + U * end_u + N * proj + Vector3.UP * (y_top - drop),
				o + U * end_u + N * 0.3 + Vector3.UP * (y_top - drop), aw_c.darkened(0.1))

	# Projecting blade sign
	if bool(st["has_blade"]) and bh >= 6.0:
		var bu := 0.16
		var by0 := gh + 0.25
		var by1 := gh + 1.35
		_box(ctx, bu - 0.04, bu + 0.04, by0, by1, 0.25, 1.15, st["bg"])
		_box(ctx, bu - 0.025, bu + 0.025, by1, by1 + 0.05, 0.0, 1.2, Color(0.1, 0.1, 0.1))
		if not is_zh_shop or nh % 6 == 0:
			var short := name_txt.split(" ")[0] if name_txt.length() > 10 else name_txt
			for sd: float in [-1.0, 1.0]:
				var lp := o + U * (bu + sd * 0.045) + N * 0.70 + Vector3.UP * ((by0 + by1) * 0.5)
				if Terrain.active:
					lp.y += Terrain.surface(lp.x, lp.z)
				var lbl := _make_label(short, st["fg"], false)
				lbl.transform = Transform3D(_face_basis(U * sd), lp)
				_fit_label(lbl, short, 0.80, 0.5)
				labels.add_child(lbl)

	# Street furniture: planters / cafe tables / A-frame menu board
	if bool(st["planters"]):
		for pu: float in [d0 - 0.55, d1 + 0.55]:
			_box(ctx, pu - 0.4, pu + 0.4, 0.0 + WALK_Y, 0.55 + WALK_Y, 0.35, 0.85, Color(0.22, 0.22, 0.23))
			_box(ctx, pu - 0.36, pu + 0.36, 0.55 + WALK_Y, 0.85 + WALK_Y, 0.39, 0.81, Color(0.18, 0.36, 0.16))
	if bool(st["cafe_tables"]):
		for tu: float in [w * 0.22, w * 0.78]:
			if absf(tu - door_c) < door_w:
				continue
			_box(ctx, tu - 0.03, tu + 0.03, 0.0 + WALK_Y, 0.72 + WALK_Y, 0.95, 1.01, Color(0.12, 0.12, 0.12))
			_box(ctx, tu - 0.32, tu + 0.32, 0.72 + WALK_Y, 0.75 + WALK_Y, 0.66, 1.30, Color(0.80, 0.78, 0.74))
			for cu: float in [-0.55, 0.55]:
				_box(ctx, tu + cu - 0.2, tu + cu + 0.2, 0.44 + WALK_Y, 0.47 + WALK_Y, 0.80, 1.18, Color(0.15, 0.15, 0.15))
				_box(ctx, tu + cu + (0.18 if cu > 0.0 else -0.2), tu + cu + (0.2 if cu > 0.0 else -0.18), 0.44 + WALK_Y, 0.85 + WALK_Y, 0.80, 1.18, Color(0.15, 0.15, 0.15))
	if str(sf.get("kind", "")) in ["cafe", "bakery", "restaurant"] and absi(hash(name_txt)) % 4 == 1:
		var au := clampf(door_c + door_w * 0.5 + 0.6, 0.4, w - 0.4)
		_box(ctx, au - 0.3, au + 0.3, 0.0 + WALK_Y, 1.0 + WALK_Y, 0.95, 1.0, Color(0.10, 0.10, 0.10))
		_box(ctx, au - 0.26, au + 0.26, 0.1 + WALK_Y, 0.92 + WALK_Y, 1.0, 1.005, Color(0.18, 0.20, 0.18))


static func _face_basis(f: Vector3) -> Basis:
	var right := (-f).cross(Vector3.UP).normalized()
	return Basis(right, Vector3.UP, f.normalized())


static func _make_label(txt: String, col: Color, letters: bool) -> Label3D:
	var l := Label3D.new()
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		# On a tile worker: setting the text here queues its glyph shaping onto the main thread, where every sign
		# of the tile was then shaped in one frame (a 50-90 ms hitch); CityTiles applies it a few labels per frame
		l.set_meta("pending_text", txt)
	else:
		l.text = txt
	l.font_size = 64
	l.outline_size = 0
	l.modulate = col
	l.double_sided = false
	l.shaded = letters
	l.visibility_range_end = 110.0
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.render_priority = 1
	return l


static func _fit_label(l: Label3D, txt: String, max_w: float, max_h: float) -> void:
	var eff_chars := 0.0
	for i in range(txt.length()):
		eff_chars += 1.05 if txt.unicode_at(i) >= 0x2E80 else 0.60
	eff_chars = maxf(2.2, eff_chars)
	var px_w := max_w / (eff_chars * float(l.font_size))
	var px_h := max_h / (float(l.font_size) * 1.05)
	l.pixel_size = minf(px_w, px_h)


static func _sign_label(parent: Node3D, pos: Vector3, n: Vector3, txt: String, max_w: float, max_h: float, col: Color, letters: bool) -> void:
	var l := _make_label(txt, col, letters)
	var p := pos
	if Terrain.active:
		p.y += Terrain.surface(p.x, p.z)
	l.transform = Transform3D(_face_basis(n), p)
	_fit_label(l, txt, max_w, max_h)
	parent.add_child(l)


# Axis-aligned (facade-local) box: u along the facade, y up, d outward from the wall.
static func _box(ctx: Dictionary, u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, col: Color) -> void:
	if u1 - u0 < 0.005 or y1 - y0 < 0.005:
		return
	var o: Vector3 = ctx["o"]
	var U: Vector3 = ctx["u"]
	var N: Vector3 = ctx["n"]
	var st: SurfaceTool = ctx["st"]
	var c := func(u: float, y: float, d: float) -> Vector3: return o + U * u + N * d + Vector3.UP * y
	# front, top, bottom, two ends
	_quad(st, c.call(u0, y0, d1), c.call(u1, y0, d1), c.call(u1, y1, d1), c.call(u0, y1, d1), col)
	_quad(st, c.call(u0, y1, d1), c.call(u1, y1, d1), c.call(u1, y1, d0), c.call(u0, y1, d0), col.lightened(0.05))
	_quad(st, c.call(u0, y0, d0), c.call(u1, y0, d0), c.call(u1, y0, d1), c.call(u0, y0, d1), col.darkened(0.2))
	_quad(st, c.call(u0, y0, d0), c.call(u0, y0, d1), c.call(u0, y1, d1), c.call(u0, y1, d0), col.darkened(0.08))
	_quad(st, c.call(u1, y0, d1), c.call(u1, y0, d0), c.call(u1, y1, d0), c.call(u1, y1, d1), col.darkened(0.08))
	if d0 < -0.01:
		_quad(st, c.call(u1, y0, d0), c.call(u0, y0, d0), c.call(u0, y1, d0), c.call(u1, y1, d0), col.darkened(0.1))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(d - a).normalized()
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(nrm)
		st.add_vertex(v)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_normal(nrm)
		st.add_vertex(v)


# A flat panel in the glazing mesh with its own 0..w, 0..h UVs (LED board, roller shutter)
static func _panel(st: SurfaceTool, o: Vector3, U: Vector3, N: Vector3, u0: float, u1: float, y0: float, y1: float, d: float, col: Color) -> void:
	if u1 - u0 < 0.1 or y1 - y0 < 0.05:
		return
	var vs := [
		[o + U * u0 + N * d + Vector3.UP * y0, Vector2(0.0, 0.0)],
		[o + U * u1 + N * d + Vector3.UP * y0, Vector2(u1 - u0, 0.0)],
		[o + U * u1 + N * d + Vector3.UP * y1, Vector2(u1 - u0, y1 - y0)],
		[o + U * u0 + N * d + Vector3.UP * y1, Vector2(0.0, y1 - y0)],
	]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(N)
		st.set_uv(vs[idx][1])
		st.add_vertex(vs[idx][0])


static func _glass(st: SurfaceTool, o: Vector3, U: Vector3, N: Vector3, u0: float, u1: float, y0: float, y1: float, d: float, col: Color) -> void:
	if u1 - u0 < 0.1 or y1 - y0 < 0.1:
		return
	var vs := [
		[o + U * u0 + N * d + Vector3.UP * y0, Vector2(u0, y0 - 0.48)],
		[o + U * u1 + N * d + Vector3.UP * y0, Vector2(u1, y0 - 0.48)],
		[o + U * u1 + N * d + Vector3.UP * y1, Vector2(u1, y1 - 0.48)],
		[o + U * u0 + N * d + Vector3.UP * y1, Vector2(u0, y1 - 0.48)],
	]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(N)
		st.set_uv(vs[idx][1])
		st.add_vertex(vs[idx][0])
