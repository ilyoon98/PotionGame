"""Costume-only generated elf edit; retain the previous standing head exactly."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

import numpy as np
from PIL import Image

import build_elf_redesign_v1 as shared
from process_pixel_art import ROOT, clean_background, native_grid, rgb

OUT = ROOT / 'art/characters/elf-redesign-v2'
REFERENCE = ROOT / 'art/characters/elf-redesign-v1/elf-native.png'

def register():
    metadata=json.loads((OUT / 'generation.json').read_text(encoding='utf-8'))
    source=Image.open(OUT / metadata.get('selected_source','source/generated-v1.png')).convert('RGBA')
    clean=clean_background(source,224)
    # Uniform registration of the generated costume edit; head is protected.
    # The shorter generated torso is placed against the original neck and foot
    # anchors instead of stretching its torso or legs separately.
    fitted_height=200 if metadata.get('selected_source_mode')=='neck_down_costume' else 330
    factor=fitted_height/clean.height
    fit=clean.resize((round(clean.width*factor),fitted_height),Image.Resampling.NEAREST)
    canvas=Image.new('RGBA',(320,480))
    # Align the generated braid seam to the preserved braid's native x22 joint.
    # This one-native-pixel horizontal registration also centers the waist at15.5.
    origin=[round((320-fit.width)/2)+10,470-fitted_height]
    canvas.alpha_composite(fit,tuple(origin))
    grid=native_grid(canvas,[32,48],0)
    grid.save(OUT / 'source/whole-body-registered.png')
    # Protected edit region: this is the same standing pose, with a costume-only
    # user request. Preserve the head at its original native coordinates.
    # All torso and legs below row27 come from one coherent generated edit.
    reference=Image.open(REFERENCE).convert('RGBA')
    grid.paste(reference.crop((0,0,32,27)),(0,0))
    grid.save(OUT / 'source/registered.png')
    shared.dump(OUT / 'registration.json',{'whole_body_registration':True,'source_size':list(source.size),
        'clean_size':list(clean.size),'uniform_scale':factor,'registered_offset':origin,'native_canvas':[32,48],
        'head_top_row':11,'foot_row':46,'protected_edit_region':[0,0,32,27],
        'protected_reference':str(REFERENCE.relative_to(ROOT)).replace('\\','/'),
        'torso_and_legs_from_one_generated_source':True,'no_cross_pose_limb_splicing':True})

def manifest():
    asset={'id':'elf','source':'art/characters/elf-redesign-v2/source/registered.png',
        'size':[32,48],'position':[0,0],'margin':0,'preserve_native_frame':True,'dark_value':.27,
        'materials':{'outline':[shared.INK],'skin':[shared.SKIN],'wood':[shared.HAIR],'leaf':[shared.GREEN,shared.LIME]},
        'rules':[{'material':'skin','hue':[.025,.15],'saturation_min':.12,'saturation_max':.52,'value_min':.73},
                 {'material':'wood','hue':[.025,.16],'saturation_min':.05,'value_max':.90}],
        'fallback_material':'leaf',
        'material_pixels':[{'material':'skin','pixels':[[x,35] for x in range(13,19)]}],
        'background_alpha_rectangles':[
            {'rect':[10,35,11,36],'reason':'Remove one outer wrist pixel at the10-pixel standing waist.'},
            {'rect':[21,35,22,36],'reason':'Remove one outer wrist pixel at the10-pixel standing waist.'},
            {'rect':[16,44,17,47],'reason':'Restore the one-pixel transparent gap between the generated boots after native downsampling.'}]}
    shared.dump(OUT / 'manifest.json',{'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,
        'scale':3,'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json',
        'output':'art/characters/elf-redesign-v2/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':[asset]})

def diagnostic():
    register();manifest()
    subprocess.run([sys.executable,str(ROOT / 'tools/process_pixel_art.py'),str((OUT / 'manifest.json').relative_to(ROOT))],check=True)
    im=Image.open(OUT / 'pipeline/elf-native.png').convert('RGBA');a=np.array(im)
    im.resize((192,288),Image.Resampling.NEAREST).save(OUT / 'source/native-diagnostic-6x.png')
    chars={rgb(c):s for c,s in [(shared.INK,'#'),(shared.SKIN,'s'),(shared.HAIR,'h'),(shared.GREEN,'g'),(shared.LIME,'L')]}
    for y in range(27,48):
        line=''.join(chars.get(tuple(p[:3]),'?') if p[3] else '.' for p in a[y]);xx=np.where(a[y,:,3]!=0)[0]
        print(f'{y:02} {line} width={int(xx.max()-xx.min()+1) if len(xx) else 0}')
    print('protected_head_unchanged',np.array_equal(a[:27],np.array(Image.open(REFERENCE).convert('RGBA'))[:27]))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--diagnostic',action='store_true');args=parser.parse_args()
    if args.diagnostic:diagnostic();return
    shared.OUT=OUT;shared.BEFORE=REFERENCE
    shared.BEFORE_LABEL,shared.AFTER_LABEL='이전 의상 · 잎 망토','한쪽 어깨 · 잎 정찰복'
    shared.TEMPLATE='elf_redesign_v2.template.html';shared.register=register;shared.manifest=manifest
    shared.main()
    frame=np.array(Image.open(OUT / 'elf-native.png').convert('RGBA'))
    reference=np.array(Image.open(REFERENCE).convert('RGBA'))
    identical=bool(np.array_equal(frame[:27],reference[:27]))
    report=json.loads((OUT / 'validation.json').read_text(encoding='utf-8'))
    report['checks']['protected_head_unchanged']=identical
    import build_combined_idle_v6 as motion
    alpha=frame[:,:,3]!=0
    components=motion.count_components(alpha)
    neck_empty=int(motion.enclosed_empty_pixels(alpha)[24:32].sum())
    report['checks'].update(opaque_components=components,neck_enclosed_empty_pixels=neck_empty)
    report['costume_changed_pixels_rows27_to46']=int(np.any(frame[27:]!=reference[27:],axis=2).sum())
    if not identical or components!=1 or neck_empty:report['status']='failed'
    shared.dump(OUT / 'validation.json',report)
    if report['status']!='passed':raise ValueError('Costume edit changed the protected head or broke its body joint')

if __name__=='__main__':main()
