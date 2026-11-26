#!/usr/bin/env python3
"""Harvest thousands of REAL Jiaxing street-front merchant names (真实沿街商户名) with exact GPS/game
coordinates across ALL urban avenues & commercial streets using Amap z=17 scale=2 map tiles +
macOS Apple Vision zh-Hans Neural Engine OCR!

Outputs: tools/osm_cache/jiaxing_real_shops_ocr.json
"""
import concurrent.futures
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA_PATH = os.path.join(ROOT, "data", "jiaxing.json")
CACHE_DIR = os.path.join(HERE, "osm_cache", "amap_z18_poi")
OUT_PATH = os.path.join(HERE, "osm_cache", "jiaxing_real_shops_ocr.json")
os.makedirs(CACHE_DIR, exist_ok=True)

LAT0, LON0 = 30.7550, 120.7520
KX = 111320.0 * math.cos(LAT0 * math.pi / 180.0)
KY = 110574.0


def _tlat(x, y):
    r = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(abs(x))
    r += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    r += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0
    r += (160.0 * math.sin(y / 12.0 * math.pi) + 320.0 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0
    return r


def _tlon(x, y):
    r = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(abs(x))
    r += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    r += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0
    r += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0
    return r


def wgs2gcj(lat, lon):
    a, ee = 6378245.0, 0.00669342162296594323
    rad = lat / 180.0 * math.pi
    m = 1.0 - ee * math.sin(rad) ** 2
    sm = math.sqrt(m)
    dlat = (_tlat(lon - 105.0, lat - 35.0) * 180.0) / ((a * (1.0 - ee)) / (m * sm) * math.pi)
    dlon = (_tlon(lon - 105.0, lat - 35.0) * 180.0) / (a / sm * math.cos(rad) * math.pi)
    return lat + dlat, lon + dlon


def gcj2wgs(lat, lon):
    glat, glon = lat, lon
    for _ in range(4):
        tlat, tlon = wgs2gcj(glat, glon)
        glat += lat - tlat
        glon += lon - tlon
    return glat, glon


def game_to_tile_gcj(gx, gy, z=17):
    lat = LAT0 - gy / KY
    lon = LON0 + gx / KX
    glat, glon = wgs2gcj(lat, lon)
    n = 2 ** z
    tx = int((glon + 180.0) / 360.0 * n)
    ty = int((1.0 - math.asinh(math.tan(math.radians(glat))) / math.pi) / 2.0 * n)
    return tx, ty


def tile_uv_to_game(tx, ty, u, v, z=17):
    n = 2 ** z
    glon = (tx + u) / n * 360.0 - 180.0
    glat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * (ty + v) / n))))
    wlat, wlon = gcj2wgs(glat, glon)
    return (round((wlon - LON0) * KX, 1), round((LAT0 - wlat) * KY, 1))


SWIFT_OCR = r"""
import Foundation
import Vision
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
if args.count < 3 { exit(1) }
let listFile = args[1]
let outFile = args[2]

let content = try String(contentsOfFile: listFile, encoding: .utf8)
let entries = content.split(separator: "\n").map { String($0) }

let lock = NSLock()
var results = [String]()
results.reserveCapacity(entries.count * 12)

let group = DispatchGroup()
let sem = DispatchSemaphore(value: 6)
let q = DispatchQueue.global(qos: .userInitiated)

for line in entries {
    let parts = line.split(separator: "\t")
    if parts.count < 3 { continue }
    let tx = String(parts[0])
    let ty = String(parts[1])
    let path = String(parts[2])
    sem.wait()
    group.enter()
    q.async {
        defer { sem.signal(); group.leave() }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        let req = VNRecognizeTextRequest()
        req.recognitionLanguages = ["zh-Hans", "en-US"]
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        do {
            try handler.perform([req])
            var local = [String]()
            for obs in req.results ?? [] {
                if let top = obs.topCandidates(1).first, top.confidence >= 0.45 {
                    let bb = obs.boundingBox
                    let txt = top.string.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "")
                    local.append(String(format: "%@\t%@\t%.4f\t%.4f\t%.4f\t%.4f\t%@", tx, ty, bb.midX, 1.0 - bb.midY, bb.width, bb.height, txt))
                }
            }
            if !local.isEmpty {
                lock.lock()
                results.append(contentsOf: local)
                lock.unlock()
            }
        } catch {}
    }
}
group.wait()
try results.joined(separator: "\n").write(toFile: outFile, atomically: true, encoding: .utf8)
"""

# Authentic Chinese merchant classification keywords (strong positive signals!)
SHOP_KIND_RULES = [
    ("pharmacy", ("药房", "大药房", "药店", "诊所", "口腔", "牙科", "中医", "门诊", "医药", "养生堂", "老百姓", "益丰", "海王星辰", "国大药房", "同仁堂", "一心堂", "医保")),
    ("bank", ("银行", "农商行", "支行", "营业厅", "ATM", "中国移动", "中国联通", "中国电信", "邮政", "证券", "保险")),
    ("cafe", ("咖啡", "奶茶", "茶饮", "茶社", "茶楼", "茶庄", "茶室", "瑞幸", "星巴克", "古茗", "蜜雪冰城", "霸王茶姬", "茶百道", "沪上阿姨", "一点点", "喜茶", "奈雪", "库迪", "CoCo", "甜品", "糖水")),
    ("bakery", ("烘焙", "蛋糕", "面包", "西点", "糕点", "酥", "好利来", "克莉丝汀", "85度", "元祖", "五芳斋", "真真老老", "粽子", "熟食", "卤味", "鸭脖", "绝味", "周黑鸭", "紫燕", "煌上煌", "良品铺子", "三只松鼠", "来伊份", "零食")),
    ("fast_food", ("面馆", "面店", "拉面", "米粉", "米线", "麻辣烫", "饺子", "水饺", "馄饨", "包子", "馒头", "早点", "早餐", "粥", "炸鸡", "汉堡", "披萨", "肯德基", "麦当劳", "华莱士", "必胜客", "沙县", "黄焖鸡", "快餐", "小吃", "臭豆腐", "烧麦", "生煎", "锅贴", "煎饼", "手抓饼", "盖浇饭", "煲仔饭", "杨国福", "张亮", "小笼", "汤包", "锅盔")),
    ("restaurant", ("饭店", "酒楼", "酒家", "菜馆", "餐厅", "餐饮", "火锅", "烧烤", "烤肉", "烤鱼", "龙虾", "海鲜", "土菜", "私房菜", "农家菜", "家常菜", "川菜", "湘菜", "东北菜", "本帮菜", "粤菜", "日料", "寿司", "料理", "烤鸭", "牛肉", "羊肉", "鱼馆", "鸡公煲", "酸菜鱼", "大排档", "夜宵", "食府", "小厨", "厨房", "美食", "海底捞", "外婆家", "绿茶", "煲", "鹅", "烧鹅", "烤串", "串串", "冒菜", "烤全羊", "牛排", "西餐", "小炒", "炒菜", "拾串", "肥牛", "牛蛙", "焖锅")),
    ("convenience", ("便利店", "十足", "罗森", "全家", "7-11", "美宜佳", "喜士多", "易捷", "昆仑好客", "烟酒", "名烟", "烟茶", "杂货", "小卖部", "食杂", "副食", "驿站", "菜鸟", "顺丰", "快递", "丰巢", "彩票", "体彩", "福彩", "商行", "百货", "渔具", "冷饮", "棒冰", "炒货", "干果")),
    ("supermarket", ("超市", "生鲜", "水果", "果业", "果园", "果蔬", "果匠", "百果园", "鲜丰", "卖场", "购物", "大润发", "沃尔玛", "永辉", "盒马", "联华", "华联", "世纪联华", "物美", "戴梦得", "农贸", "菜场", "水产", "肉铺", "粮油", "干货")),
    ("hairdresser", ("理发", "美发", "造型", "发艺", "美容", "美甲", "美睫", "护肤", "SPA", "养生", "足浴", "足道", "推拿", "盲人按摩", "采耳", "纹绣", "产康", "月子", "沙龙", "头疗", "护肤", "理疗")),
    ("clothes", ("服装", "服饰", "男装", "女装", "童装", "内衣", "鞋业", "鞋店", "皮具", "箱包", "干洗", "洗衣", "裁缝", "改衣", "丝绸", "家纺", "窗帘", "布艺", "母婴", "孕婴", "玩具", "珠宝", "金店", "老凤祥", "周大福", "周六福", "眼镜", "视光", "钟表", "名表", "衣橱", "定制", "婚纱")),
    ("hardware", ("五金", "建材", "机电", "水暖", "管业", "灯饰", "照明", "门窗", "铝业", "玻璃", "木业", "板材", "油漆", "涂料", "瓷砖", "卫浴", "洁具", "橱柜", "全屋定制", "家居", "家具", "木门", "地板", "墙布", "墙纸", "装饰", "装修", "设计", "汽修", "汽配", "洗车", "汽车", "轮胎", "电动车", "雅迪", "爱玛", "台铃", "小牛", "九号", "开锁", "配钥匙", "维修", "家电", "空调", "制冷")),
    ("mobile_phone", ("手机", "通讯", "数码", "电脑", "苹果", "华为", "小米", "OPPO", "vivo", "荣耀", "打印", "图文", "广告", "照相", "摄影", "影楼", "工作室")),
    ("books", ("书店", "文具", "办公", "晨光", "得力", "培训", "托管", "晚托", "琴行", "美术", "书法", "舞蹈", "围棋", "跆拳道", "健身", "瑜伽", "台球", "棋牌", "网咖", "网吧", "电竞", "花店", "花艺", "鲜花", "园艺", "宠物", "猫咖", "教育", "英语", "钢琴")),
    ("mall", ("酒店", "宾馆", "旅馆", "民宿", "如家", "汉庭", "全季", "亚朵", "维也纳", "桔子", "7天", "格林豪泰", "锦江", "尚客优", "KTV", "影城", "影院", "浴场", "房产", "地产", "中介", "不动产", "我爱我家", "链家", "贝壳", "德佑", "21世纪", "会所")),
]

# Explicit non-shop exclusions (roads, compounds, building numbers, transit, government)
NON_SHOP_RE = re.compile(
    r"(^[\dA-Za-z\-]+(号楼?|幢|栋|单元|室|座|期)?$|"
    r"(东|西|南|北|中)?(大门|出入口|入口|出口|门岗|停车场|地下车库|地上停车|充电站)$|"
    r"(路|街|大道|巷|弄|桥|河|港|湖|塘|浜|泾|高速公路|高架|立交|隧道)$|"
    r"(公交站|有轨电车|火车站|高铁站|客运中心)$|"
    r"(幼儿园|小学|中学|高中|实验学校|学院|大学|校区|教学楼|体育馆|体育场|游泳馆|图书馆|博物馆|纪念馆|美术馆|文化馆|科技馆|大剧院)$|"
    r"(人民政府|管委会|街道办事处|派出所|公安局|交警|法院|检察院|消防|税务|社保|社区服务中心|党群|居委会|村委会)$|"
    r"(人民医院|第一医院|第二医院|中医院|妇幼保健院)$|"
    r"(公园|湿地|景区|广场|绿地|花园|小区|新村|名苑|雅苑|嘉苑|华庭|名邸|公馆|公寓|世家|府邸|御府|天玺|庄园|水岸|半岛|国际社区)$)"
)


def classify_shop(raw_txt):
    txt = raw_txt.strip()
    txt = re.sub(r"[\s\(\)（）\[\]【】\"\'<>《》]+", "", txt)
    if len(txt) < 2 or len(txt) > 15:
        return None
    # Require at least 2 Chinese chars (or well-known English brand)
    zh_cnt = sum(1 for ch in txt if "\u4e00" <= ch <= "\u9fff")
    if zh_cnt < 2 and txt.upper() not in ("KFC", "OPPO", "VIVO", "KTV", "COCO", "STARBUCKS"):
        return None
    # Check strong merchant keywords first (overrides e.g. "XX路药房" or "XX花园超市")
    for kind, kws in SHOP_KIND_RULES:
        for kw in kws:
            if kw in txt:
                # Still reject pure civic/parking/road/compound names that accidentally hit a substring
                if any(bad in txt for bad in ("停车场", "出入口", "公交站", "号楼", "居委会", "派出所", "人民政府", "学校", "中学", "小学", "幼儿园")):
                    return None
                return kind
    # If ends in 店/馆/坊/铺/堂/行/社/阁/轩/斋/庄 and not in non-shop list
    if NON_SHOP_RE.search(txt):
        return None
    if txt[-1] in ("店", "馆", "坊", "铺", "堂", "行", "斋", "厨", "吧", "屋", "居", "阁", "轩"):
        if len(txt) >= 3:
            return "restaurant" if txt[-1] in ("馆", "厨", "居", "斋") else "convenience"
    return None


def fetch_poi_tile(tx, ty):
    path = os.path.join(CACHE_DIR, f"p18_{tx}_{ty}.png")
    if os.path.exists(path) and os.path.getsize(path) > 300:
        return path
    srv = ((tx + ty) % 4) + 1
    url = f"https://webrd0{srv}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=2&style=8&x={tx}&y={ty}&z=18"
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            data = urllib.request.urlopen(req, timeout=12).read()
            if len(data) > 200:
                with open(path, "wb") as f:
                    f.write(data)
                return path
        except Exception:
            time.sleep(0.25 * (attempt + 1))
    return None


def main():
    t0 = time.time()
    d = json.load(open(DATA_PATH, "r"))
    # Select z=18 tiles strictly along commercial & residential avenues that have street-front buildings!
    # That focuses all ~1,200-1,600 tiles on actual shop corridors (skipping empty parks/lakes/farmland)!
    road_tiles = set()
    for e in d["graph_edges"]:
        w = float(e.get("width", 8.0))
        if w < 10.5 or not e.get("pts"):
            continue
        pts = e["pts"]
        for a, b in zip(pts, pts[1:]):
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            steps = max(1, int(L / 65.0))
            for k in range(steps + 1):
                t = k / steps
                px = a[0] + (b[0] - a[0]) * t
                py = a[1] + (b[1] - a[1]) * t
                road_tiles.add(game_to_tile_gcj(px, py, 18))
    bldg_tiles = set()
    for b in d["buildings"]:
        if b.get("kind") == "industrial" or b.get("arch") == "rural_selfbuilt":
            continue
        pts = b.get("pts", [])
        if not pts:
            continue
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        bldg_tiles.add(game_to_tile_gcj(cx, cy, 18))
    # Intersect road tiles with tiles containing real buildings (plus 1-tile street-front overlap for Shot 1 & core!)
    tiles = sorted(road_tiles & bldg_tiles)
    raw_out = os.path.join(CACHE_DIR, "ocr_raw.tsv")
    if "--reparse" not in sys.argv:
        print(f"Harvesting real Jiaxing street-front merchants from {len(tiles)} z=18 commercial street tiles...")
        tile_paths = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=28) as ex:
            futs = {ex.submit(fetch_poi_tile, tx, ty): (tx, ty) for (tx, ty) in tiles}
            done = 0
            for fut in concurrent.futures.as_completed(futs):
                done += 1
                p = fut.result()
                if p:
                    tx, ty = futs[fut]
                    tile_paths.append((tx, ty, p))
                if done % 250 == 0 or done == len(tiles):
                    print(f"  Downloaded {done}/{len(tiles)} z=18 POI tiles in {time.time() - t0:.1f}s", flush=True)

        # Compile & run fast Apple Vision zh-Hans Neural Engine OCR binary across all tiles!
        swift_src = os.path.join(CACHE_DIR, "batch_ocr.swift")
        swift_bin = os.path.join(CACHE_DIR, "batch_ocr")
        with open(swift_src, "w") as f:
            f.write(SWIFT_OCR)
        if not os.path.exists(swift_bin) or os.path.getmtime(swift_src) > os.path.getmtime(swift_bin):
            subprocess.check_call(["swiftc", "-O", swift_src, "-o", swift_bin])

        list_file = os.path.join(CACHE_DIR, "ocr_list.tsv")
        with open(list_file, "w") as f:
            for tx, ty, p in tile_paths:
                f.write(f"{tx}\t{ty}\t{p}\n")
        print(f"Running Apple Vision zh-Hans OCR on {len(tile_paths)} z=18 tiles...", flush=True)
        subprocess.check_call([swift_bin, list_file, raw_out])
        print(f"OCR complete in {time.time() - t0:.1f}s!", flush=True)

    # Parse BOTH z=18 and z=17 cached Vision OCR TSVs & merge wrapped 2-line Chinese POI labels!
    merged_labels = []
    sources = [(18, raw_out), (17, os.path.join(HERE, "osm_cache", "amap_z17_poi", "ocr_raw.tsv"))]
    for zoom_lvl, src_tsv in sources:
        if not os.path.exists(src_tsv):
            continue
        per_tile = {}
        with open(src_tsv, "r", encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 7:
                    continue
                tx, ty = int(parts[0]), int(parts[1])
                mx, my, bw, bh = float(parts[2]), float(parts[3]), float(parts[4]), float(parts[5])
                txt = parts[6].strip()
                if mx - bw * 0.5 < 0.012 or mx + bw * 0.5 > 0.988 or my - bh * 0.5 < 0.012 or my + bh * 0.5 > 0.988:
                    continue
                per_tile.setdefault((tx, ty), []).append([mx, my, bw, bh, txt, False])

        for (tx, ty), obs in per_tile.items():
            obs.sort(key=lambda o: o[1])
            for i in range(len(obs)):
                if obs[i][5]:
                    continue
                mx, my, bw, bh, txt, _ = obs[i]
                obs[i][5] = True
                for j in range(i + 1, len(obs)):
                    if obs[j][5]:
                        continue
                    mx2, my2, bw2, bh2, txt2, _ = obs[j]
                    dy = my2 - my
                    if 0.015 <= dy <= 0.085 and abs(mx2 - mx) <= 0.075:
                        txt = txt + txt2
                        my = (my + my2) * 0.5
                        obs[j][5] = True
                        break
                txt = re.sub(r"^[•·●○oO&@\.\-\s]+", "", txt).strip()
                txt = re.sub(r"[=\s]+$", "", txt).strip()
                kind = classify_shop(txt)
                if kind is not None:
                    gx, gy = tile_uv_to_game(tx, ty, mx, my, zoom_lvl)
                    merged_labels.append({"name": txt, "kind": kind, "x": gx, "y": gy})

    # Merge any z=17 shops from earlier run too so nothing is lost
    seen = {}
    shops = []
    for it in merged_labels:
        nm = it["name"]
        x, y = it["x"], it["y"]
        prev = seen.get(nm)
        if prev is not None and any(math.hypot(x - px, y - py) < 35.0 for px, py in prev):
            continue
        seen.setdefault(nm, []).append((x, y))
        shops.append(it)

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(shops, f, ensure_ascii=False, separators=(",", ":"))
    print(f"Saved {len(shops)} REAL z=18 Jiaxing street-front merchants to {OUT_PATH} in {time.time() - t0:.1f}s!")
    print("Sample 30 real merchants:", [(s["name"], s["kind"], s["x"], s["y"]) for s in shops[:30]])


if __name__ == "__main__":
    main()
