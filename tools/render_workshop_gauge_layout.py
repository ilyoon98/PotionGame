"""File-only placement proof from headless-exported rectangles; no desktop capture."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / '.verification/workshop-followup-layout.json').read_text(encoding='utf-8'))
CONTENT = json.loads((ROOT / 'data/content_expansion.json').read_text(encoding='utf-8'))
ROWS = {r['id']: r for kind in ('materials', 'regions', 'potions') for r in CONTENT[kind]}
FONT = ImageFont.truetype(str(ROOT / 'assets/fonts/pretendard/Pretendard-Regular.otf'), 10)

def texture(path, region=None):
    im = Image.open(ROOT / path.removeprefix('res://')).convert('RGBA')
    if region:
        x, y, w, h = region
        im = im.crop((x, y, x+w, y+h))
    return im

def place(canvas, im, rect):
    x, y, w, h = map(int, rect)
    canvas.alpha_composite(im.resize((w, h), Image.Resampling.NEAREST), (x, y))

def backing(draw, rect):
    x, y, w, h = map(int, rect)
    draw.rectangle((x-1, y-1, x+w, y+h), fill='#281f33', outline='#766180')

def gauge(draw, rect, fraction, running, color):
    x, y, w, h = map(int, rect)
    draw.rectangle((x, y, x+w-1, y+h-1), fill='#49364f')
    filled = int(w * min(1, max(0, fraction)))
    if filled:
        draw.rectangle((x, y, x+filled-1, y+h-1), fill=color if running else '#81718a')
    if not running:
        for xx in (x+w-3, x+w-1): draw.line((xx, y-2, xx, y-1), fill='#efd7a2')

def proof(light, rainy):
    scene = Image.new('RGBA', (408, 288), '#eee9dc' if light else '#17121f')
    d = ImageDraw.Draw(scene)
    d.rectangle((30, 19, 97, 98), fill='#6589a4' if light else '#30364f')
    d.rectangle((107, 19, 175, 98), fill='#5e7993' if light else '#34334c')
    place(scene, texture('res://assets/weather/v1/sun_24x24.png' if light else 'res://assets/weather/v1/moon_24x32.png'), (43, 37, 48, 48 if light else 64))
    cloud = 'res://assets/weather/v1/cloud_rain_96x32.png' if rainy else 'res://assets/weather/v1/cloud_clear_64x24.png'
    place(scene, texture(cloud), (111, 40, 60, 20))
    if rainy:
        for x in range(117, 170, 10): d.line((x, 72, x-3, 79), fill='#a2c8ea', width=1)
    place(scene, texture('res://assets/workshop_v1/window-frame.png', (151, 173, 1156, 746)), (8, 4, 188, 116))
    for dst, src in [((190,105,210,80),(318,475,1140,325)),((217,16,17,96),(463,106,90,400)),((380,16,17,96),(1348,106,90,400)),((232,53,150,15),(555,259,390,60)),((232,93,150,14),(555,414,390,58))]:
        place(scene, texture('res://assets/workshop_v1/potion-counter.png', src), dst)
    place(scene, texture('res://assets/workshop_v1/moon-rug.png', (137,153,1748,495)), (136,198,94,26))
    place(scene, texture('res://.verification/workshop-followup-cauldron.png'), (33,140,96,96))
    place(scene, texture('res://assets/workshop_v1/moon-herb-pot.png', (326,189,648,832)), (204,52,62,80))
    for i in range(8):
        place(scene, texture('res://assets/potion_12x16.png' if i % 2 == 0 else 'res://assets/mana_12x16.png'), (268+i%4*32,26+i//4*40,20,28))
    place(scene, texture('res://assets/characters/animations_v1/keeper_animations_96x128.png', (0,0,48,64)), (110,80,96,128))
    place(scene, texture('res://assets/characters/animations_v1/traveler_animations_96x128.png', (0,0,48,64)), (302,117,96,128))
    d = ImageDraw.Draw(scene)
    x,y,w,h = DATA['pot_rect']
    backing(d, (x,y,w,h))
    place(scene, texture(ROWS[DATA['craft']['icon']]['icon_candidate']), (x,y,12,12))
    d.text((x+16,y), DATA['craft']['status'], font=FONT, fill='#efc77c')
    gauge(d, (x+16,y+13,54,2), DATA['craft']['progress'], DATA['craft']['running'], '#efc77c')
    for item, rect in zip(DATA['herbs'], DATA['herb_rects']):
        x,y,w,h = rect
        backing(d, rect)
        place(scene, texture('res://assets/content_expansion_v1/materials/herb_growth.png', DATA['growth_region']), (x,y,16,20))
        gauge(d, (x+1,y+23,14,2), item['progress'], item['running'], '#b5d7a0')
    for item, rect in zip(DATA['trips'], DATA['trip_rects']):
        x,y,w,h = rect
        backing(d, rect)
        place(scene, texture(ROWS[item['icon']]['icon_candidate']), (x,y,14,14))
        gauge(d, (x+18,y+6,40,3), item['display_progress'], item['running'], '#a2b5d5')
        d.text((x,y+15), DATA['region_summary'], font=FONT, fill='#efc77c')
        reason = '잠김' if not item['available'] else '출발비' if '출발비' in item['status'] else '보관' if '보관' in item['status'] else '재료' if '재료 충분' in item['status'] else '복귀' if '가져오는' in item['status'] else '탐색' if item['running'] else '대기'
        d.text((x,y+31), reason, font=FONT, fill='#efc77c')
    backing(d, (236,1,108,12))
    d.text((236,1), DATA['herb_summary'], font=FONT, fill='#efc77c')
    for rect in DATA['detail_rects']:
        x,y,w,h = rect
        backing(d, rect)
        d.ellipse((x+4,y+4,x+10,y+10), outline='#efc77c', width=1)
        d.line((x+10,y+10,x+14,y+14), fill='#efc77c', width=1)
    d.rectangle((0,248,407,287), fill='#302238', outline='#786080')
    d.text((12,260), '파일 기반 배치 검토 · 실제 화면 캡처 아님', font=FONT, fill='#f2dbb4')
    return scene.resize((816,576), Image.Resampling.NEAREST)

sheet = Image.new('RGB', (1632,1152), '#211b2d')
for i, args in enumerate(((False,False),(True,False),(False,True),(True,True))):
    sheet.paste(proof(*args).convert('RGB'), (i%2*816,i//2*576))
path = ROOT / '.verification/workshop-gauge-placement-proof.png'
sheet.save(path)
print(path)
