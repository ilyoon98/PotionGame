"""Check the RGBA captures made by the visible, real Godot walkthrough."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / '.verification/pixel-runtime-v1/live'
catalog = json.loads((ROOT / 'assets/pixel_v1/catalog.json').read_text(encoding='utf-8'))
events = json.loads((FOLDER / 'live-review.json').read_text(encoding='utf-8'))
assert events['status'] == 'passed'
by_customer = {case['customer']: case for case in events['cases']}
results = []
for cid, kind in [('traveler', 'health'), ('mage', 'moon'), ('elf', 'purify'), ('rogue', 'agility')]:
    event = by_customer[cid]
    assert event['sold_potion'] == kind
    assert (event['stock_before'], event['stock_after_sale'], event['stock_after_brew']) == (8, 7, 8)
    for stage in ['stock', 'enter', 'wait', 'counter', 'flight', 'catch', 'exit', 'departed', 'restocked']:
        image = Image.open(FOLDER / f'{cid}-{stage}.png').convert('RGBA')
        assert image.size == (540, 300), (cid, stage, image.size)
        assert image.getpixel((200, 20))[3] == 0
        assert all(image.getpixel((x, 238))[3] == 255 for x in range(540))
    image = Image.open(FOLDER / f'{cid}-catch.png').convert('RGBA')
    potion = catalog['potions'][kind]
    rgba = (*bytes.fromhex(potion['liquid_color'].lstrip('#')), 255)
    hand = catalog['characters'][cid]['grips']['receive_extend']
    grip = catalog['characters'][cid]['bindings'][kind]['local_grip']
    x, y = 444 + (hand[0] - grip[0])*3, 96 + (hand[1] - grip[1])*3
    w, h = potion['bottle_size']
    bottle_pixels = sum(pixel == rgba for pixel in image.crop((x, y, x+w*3, y+h*3)).get_flattened_data())
    pot_pixels = sum(pixel == rgba for pixel in image.crop((123, 144, 219, 186)).get_flattened_data())
    assert bottle_pixels > 0 and pot_pixels > 0, (cid, bottle_pixels, pot_pixels)
    results.append({'customer': cid, 'potion': kind, 'liquid_color': potion['liquid_color'],
                    'visible_bottle_liquid_pixels': bottle_pixels, 'visible_pot_liquid_pixels': pot_pixels,
                    'stages': 9, 'inventory': [8, 7, 8], 'empty_alpha': 0})
proof = {'status': 'passed', 'source': 'visible Godot Shop RGBA captures', 'cases': results}
(FOLDER / 'live-pixel-proof.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2), encoding='utf-8')
print('LIVE PIXEL PROOF PASS: 4 customers / 36 stage captures / stock 8->7->8 / bottle-pot colors / alpha 0')
