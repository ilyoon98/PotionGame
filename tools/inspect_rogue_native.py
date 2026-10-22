"""Inspect registered whole-body native samples before semantic feature masks."""
import json
import numpy as np
from PIL import Image
import build_rogue_keyframes_v2 as b
from process_pixel_art import material_remap
cfg=json.loads((b.OUT/'manifest.json').read_text(encoding='utf-8'))
ramps=json.loads((b.ROOT/'art/ramps.json').read_text(encoding='utf-8'))
chars={b.rgb(c):s for c,s in [(b.INK,'#'),(b.SKIN,'s'),(b.ORANGE,'o'),(b.LIGHT,'L'),(b.SCARF,'r')]}
for v in cfg['assets']:
    if v['id'] not in ('walk_contact_b','walk_pass_b'):continue
    v.pop('material_pixels',None)
    im,_,_=material_remap(Image.open(b.ROOT/v['source']).convert('RGBA'),v,ramps)
    im.resize((320,480),Image.Resampling.NEAREST).save(b.OUT/'source'/(v['id']+'-baseline.png'))
    a=np.array(im);print(v['id'])
    for y in range(18,27):print(y,''.join(chars.get(tuple(p[:3]),'?') if p[3] else '.' for p in a[y]))
