"""Register a generated whole-body elf design through the fixed art pipeline."""
from __future__ import annotations

import base64
import hashlib
import io
import json
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

from process_pixel_art import ROOT, clean_background, native_grid, rgb, validate
import build_traveler_keyframes_v1 as common
from prepare_character_v6 import dark_component

OUT = ROOT / 'art/characters/elf-redesign-v1'
BEFORE = ROOT / 'art/mockups/full-ingame-v7/characters/elf-native.png'
BEFORE_LABEL, AFTER_LABEL = '기존 엘프', '옆땋은 머리 · 잎 망토'
TEMPLATE = 'elf_redesign_v1.template.html'
INK, SKIN, HAIR, GREEN, LIME = '#241C32', '#F6D1AC', '#916047', '#718C59', '#B5C77D'

def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def register():
    source = Image.open(OUT / 'source/generated-v1.png').convert('RGBA')
    clean = clean_background(source, 224)
    scale = 360 / clean.height
    fit = clean.resize((round(clean.width*scale),360),Image.Resampling.NEAREST)
    canvas = Image.new('RGBA',(320,480))
    origin = [round((320-fit.width)/2),110]
    canvas.alpha_composite(fit,tuple(origin))
    grid = native_grid(canvas,[32,48],0)
    grid.save(OUT / 'source/registered.png')
    dump(OUT / 'registration.json',{'whole_body_registration':True,'source_size':list(source.size),
        'clean_bounds':list(clean.size),'uniform_scale':scale,'registered_offset':origin,
        'native_canvas':[32,48],'head_top_row':11,'foot_row':46,
        'no_body_part_splicing':True})

def manifest():
    asset={'id':'elf','source':'art/characters/elf-redesign-v1/source/registered.png',
        'size':[32,48],'position':[0,0],'margin':0,'preserve_native_frame':True,'dark_value':.27,
        'materials':{'outline':[INK],'skin':[SKIN],'wood':[HAIR],'leaf':[GREEN,LIME]},
        'rules':[{'material':'skin','hue':[.025,.15],'saturation_min':.12,'saturation_max':.52,'value_min':.73},
                 {'material':'wood','hue':[.025,.16],'saturation_min':.05,'value_max':.90}],
        'fallback_material':'leaf',
        'material_pixels':[
            {'material':'skin','pixels':[[16,21],[17,21]]},
            {'material':'outline','pixels':[[11,22],[11,23],[16,22],[16,23]]}],
        'background_alpha_rectangles':[
            {'rect':[10,35,11,36],'reason':'Remove one downsampled hand-edge excess at the standing waist.'},
            {'rect':[22,35,24,36],'reason':'End the braid above the waist rather than widening the waist.'},
            {'rect':[9,37,10,38],'reason':'Trim one hand-edge excess to the shared12-pixel lower silhouette.'}]}
    dump(OUT / 'manifest.json',{'schema_version':1,'status':'candidate','approved_by_user':False,
        'compose':False,'scale':3,'alpha_threshold':224,'max_colors':5,
        'palette':'art/palette.hex','ramps':'art/ramps.json','output':'art/characters/elf-redesign-v1/pipeline',
        'scene':{'size':[32,48],'background':'#4A3C52'},'assets':[asset]})

def existing_art_snapshot():
    paths=list((ROOT / 'art/characters/keyframes-v1').glob('*/frames/*.png'))
    paths+=list((ROOT / 'art/mockups/full-ingame-v7/characters').glob('*.png'))
    paths+=[ROOT / 'art/mockups/full-ingame-v7/animated-preview.html']
    return {str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

def preview(frame):
    before=Image.open(BEFORE).convert('RGBA')
    before.save(OUT / 'source/before-elf.png')
    board=Image.new('RGBA',(560,386),'#4A3C52')
    common.text(board,(24,15),'엘프 전신 재디자인 · 같은 원본32×48 / 공통6배',21)
    for x,sprite,label in [(52,before,BEFORE_LABEL),(314,frame,AFTER_LABEL)]:
        board.alpha_composite(sprite.resize((192,288),Image.Resampling.NEAREST),(x,49))
        common.text(board,(x,344),label,17)
    board.convert('RGB').save(OUT / 'before-after.png')
    company=Image.new('RGBA',(588,224),'#4A3C52')
    refs=[('주인공',ROOT / 'art/mockups/full-ingame-v7/characters/witch-native.png'),
        ('여행자',ROOT / 'art/characters/keyframes-v1/traveler/frames/idle.png'),
        ('여마법사',ROOT / 'art/characters/keyframes-v1/mage/frames/idle.png'),('새 엘프',OUT / 'elf-native.png')]
    for i,(label,path) in enumerate(refs):
        x=30+i*142
        sprite=Image.open(path).convert('RGBA')
        company.alpha_composite(sprite.resize((96,144),Image.Resampling.NEAREST),(x,28))
        common.text(company,(x,187),label,16)
    company.convert('RGB').save(OUT / 'common-scale-3x.png')

    # Compose a stationary design review from the existing mockup layers.
    data=json.loads((ROOT / 'art/mockups/full-ingame-v7/animation-data.json').read_text(encoding='utf-8'))
    def uri_image(uri):return Image.open(io.BytesIO(base64.b64decode(uri.split(',',1)[1]))).convert('RGBA')
    scene=Image.new('RGBA',tuple(data['artSize']),'#4A3C52')
    def place(sprite,position):
        scene.alpha_composite(sprite.resize((sprite.width*3,sprite.height*3),Image.Resampling.NEAREST),tuple(n*3 for n in position))
    pos=data['positions']
    place(uri_image(data['sprites']['weather']['night_clear'][0]),pos['window'])
    scene.alpha_composite(uri_image(data['staticArt']))
    place(uri_image(data['sprites']['fire'][0]),pos['fire'])
    place(uri_image(data['sprites']['pot'][0]),pos['pot'])
    place(Image.open(refs[0][1]).convert('RGBA'),pos['witch'])
    place(frame,pos['elf'])
    scene.save(OUT / 'workshop-preview-3x.png')
    (OUT / 'review.html').write_text((ROOT / 'tools' / TEMPLATE).read_text(encoding='utf-8'),encoding='utf-8')

def main():
    snapshot=existing_art_snapshot()
    register();manifest()
    subprocess.run([sys.executable,str(ROOT / 'tools/process_pixel_art.py'),
        str((OUT / 'manifest.json').relative_to(ROOT))],check=True)
    im=Image.open(OUT / 'pipeline/elf-native.png').convert('RGBA')
    im.resize((192,288),Image.Resampling.NEAREST).save(OUT / 'source/native-diagnostic-6x.png')
    a=np.array(im)
    chars={rgb(c):s for c,s in [(INK,'#'),(SKIN,'s'),(HAIR,'h'),(GREEN,'g'),(LIME,'L')]}
    check=validate(im,[32,48],{rgb(c) for c in (INK,SKIN,HAIR,GREEN,LIME)},5)
    check['outline_boundary_violations']=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum())
    check['top11_rows_clear']=bool(not a[:11,:,3].any())
    check['foot_row46']=bool(a[46,:,3].any() and not a[47,:,3].any())
    yy,xx=np.where(a[11:27,:,3]!=0)
    check['head_bounds']=[int(xx.min()),int(yy.min())+11,int(xx.max())+1,int(yy.max())+12]
    check['head_fits22x16']=bool(xx.max()-xx.min()+1<=22 and yy.max()-yy.min()+1==16)
    widths={}
    for y in [35,37,38,39]:
        xx=np.where(a[y,:,3]!=0)[0];widths[str(y)]=int(xx.max()-xx.min()+1)
    check['waist_and_hem_widths']=widths
    check['waist10_hem10to12']=widths['35']==10 and all(10<=widths[str(y)]<=12 for y in [37,38,39])
    eye_checks=[]
    for x in [11,16]:
        points=[(x,22),(x,23)]
        isolated=dark_component(im,points[0],diagonals=True)==sorted(points)
        halo=all(tuple(a[y,xx])==(*rgb(SKIN),255) for y in range(21,25) for xx in range(x-1,x+2) if (xx,y) not in points)
        eye_checks.append({'pixels':points,'isolated2_pixels':isolated,'full1_pixel_skin_halo':halo})
    check['eyes']=eye_checks
    check['exact3x']=np.array_equal(np.array(im.resize((96,144),Image.Resampling.NEAREST)),np.repeat(np.repeat(a,3,0),3,1))
    passed=check['passed'] and check['outline_boundary_violations']==0 and all(check[k] for k in ['top11_rows_clear','foot_row46','head_fits22x16','waist10_hem10to12','exact3x']) and all(e['isolated2_pixels'] and e['full1_pixel_skin_halo'] for e in eye_checks)
    report={'status':'passed' if passed else 'failed','art_status':'candidate','approved_by_user':False,
        'character':'elf','native_canvas':[32,48],'body_rows':[27,39],'legs_and_boots_rows':[40,46],
        'stage_order':['background_cleanup','native_grid','material_ramp_remap','validation'],'checks':check,
        'existing_keyframes_replaced':False,'runtime_integrated':False}
    dump(OUT / 'validation.json',report)
    if not passed:raise ValueError(f'Elf design validation failed: {check}')
    im.save(OUT / 'elf-native.png');im.resize((96,144),Image.Resampling.NEAREST).save(OUT / 'elf-3x.png')
    preview(im)
    after=existing_art_snapshot()
    changed=[p for p in snapshot if snapshot[p]!=after.get(p)]
    dump(OUT / 'regression-validation.json',{'status':'passed' if not changed else 'failed',
        'existing_art_files_checked':len(snapshot),'changed_existing_art_files':changed,'sha256':snapshot})
    if changed:raise ValueError(f'Unexpected change to old art: {changed}')
    print(json.dumps({'status':report['status'],'native_canvas':[32,48],'colors':check['color_count'],
        'two_eyes_verified':True,'head_bounds':check['head_bounds'],'waist_and_hem_widths':widths,
        'existing_art_files_unchanged':len(snapshot),'review':str(OUT / 'review.html')},ensure_ascii=False))

if __name__=='__main__':main()
