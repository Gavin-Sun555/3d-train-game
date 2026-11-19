import xml.etree.ElementTree as ET, json, math, glob, collections
n0, w0, s0 = 47.645, -122.370, 47.592
mid = (s0 + n0) / 2
kx, ky = 111320 * math.cos(mid * math.pi / 180), 110574
def proj(lat, lon): return [round((lon - w0) * kx - 2420.0, 2), round((n0 - lat) * ky - 2960.0, 2)]
nodes = {}; pois = {}; ways = {}
for f in sorted(glob.glob('tile_*.osm')):
    root = ET.parse(f).getroot()
    for n in root.iter('node'):
        nid = n.get('id'); lat, lon = float(n.get('lat')), float(n.get('lon'))
        nodes[nid] = (lat, lon)
        tags = {t.get('k'): t.get('v') for t in n.iter('tag')}
        if tags: pois[nid] = (lat, lon, tags)
    for w in root.iter('way'):
        tags = {t.get('k'): t.get('v') for t in w.iter('tag')}
        if tags: ways[w.get('id')] = ([nd.get('ref') for nd in w.iter('nd')], tags)
out_pois = []
KEYS = ('shop', 'amenity', 'tourism', 'leisure', 'craft', 'office')
AMEN = {'restaurant','cafe','fast_food','bar','pub','bank','pharmacy','cinema','theatre','ice_cream','food_court','nightclub','post_office','library','marketplace','clinic','dentist'}
def keep(t):
    if 'name' not in t: return False
    if 'shop' in t: return True
    if t.get('amenity') in AMEN: return True
    if t.get('tourism') in ('hotel','museum','gallery'): return True
    return False
for nid, (lat, lon, t) in pois.items():
    if keep(t):
        out_pois.append({'name': t['name'], 'kind': t.get('shop') or t.get('amenity') or t.get('tourism'), 'cat': 'shop' if 'shop' in t else ('amenity' if 'amenity' in t else 'tourism'), 'brand': t.get('brand', ''), 'pos': proj(lat, lon), 'level': t.get('level', ''), 'addr': (t.get('addr:housenumber','') + ' ' + t.get('addr:street','')).strip()})
named_bld = []; parks = []; piers = []
for wid, (refs, t) in ways.items():
    pts = [nodes[r] for r in refs if r in nodes]
    if len(pts) < 3: continue
    poly = [proj(*p) for p in pts]
    c = [sum(p[0] for p in poly)/len(poly), sum(p[1] for p in poly)/len(poly)]
    if keep(t) and 'building' not in t:
        out_pois.append({'name': t['name'], 'kind': t.get('shop') or t.get('amenity') or t.get('tourism'), 'cat': 'shop' if 'shop' in t else 'amenity', 'brand': t.get('brand',''), 'pos': c, 'level': t.get('level',''), 'addr': ''})
    if 'building' in t and ('name' in t or 'shop' in t or 'building:colour' in t or 'building:material' in t):
        named_bld.append({'name': t.get('name',''), 'building': t['building'], 'shop': t.get('shop',''), 'amenity': t.get('amenity',''), 'brand': t.get('brand',''),
            'levels': t.get('building:levels',''), 'height': t.get('height',''), 'colour': t.get('building:colour',''), 'material': t.get('building:material',''),
            'roof_colour': t.get('roof:colour',''), 'start': t.get('start_date',''), 'center': [round(c[0],2), round(c[1],2)], 'poly': poly})
    if t.get('man_made') == 'pier':
        piers.append({'name': t.get('name',''), 'closed': refs[0] == refs[-1], 'width': t.get('width',''), 'poly': poly})
    if t.get('leisure') in ('park','garden','playground') or t.get('place') == 'square' or t.get('highway') == 'pedestrian' and t.get('area') == 'yes':
        parks.append({'name': t.get('name',''), 'kind': t.get('leisure') or t.get('place') or 'pedestrian', 'poly': poly})
# dedupe pois by name+pos
seen = set(); dd = []
for p in out_pois:
    k = (p['name'], round(p['pos'][0]), round(p['pos'][1]))
    if k in seen: continue
    seen.add(k)
    if -1430 <= p['pos'][0] <= 530 and -1020 <= p['pos'][1] <= 1550: dd.append(p)
bl = [b for b in named_bld if -1430 <= b['center'][0] <= 530 and -1020 <= b['center'][1] <= 1550]
pk = [p for p in parks if any(-1430 <= q[0] <= 530 and -1020 <= q[1] <= 1550 for q in p['poly'])]
piers = [p for p in piers if any(-1430 <= q[0] <= 530 and -1020 <= q[1] <= 1550 for q in p['poly'])]
json.dump({'pois': dd, 'buildings': bl, 'parks': pk, 'piers': piers}, open('seattle_osm_extra.json', 'w'))
print(len(piers), 'piers', sorted(set(p['name'] for p in piers if p['name']))[:30])
print(len(dd), 'pois', len(bl), 'named/tagged buildings', len(pk), 'parks')
print(collections.Counter(p['kind'] for p in dd).most_common(25))
for b in sorted(bl, key=lambda b: -len(b['name']))[:80]:
    if b['name']: print(b['name'], '|', b['building'], b['levels'], b['height'], b['colour'], b['material'], b['center'])
