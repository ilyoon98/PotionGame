"""Whole-body elf keyposes from the approved leaf outfit, without old face hooks."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

from process_pixel_art import ROOT,clean_background,native_grid,rgb,validate,material_remap
from prepare_character_v6 import dark_component
import build_traveler_keyframes_v1 as common
import build_combined_idle_v6 as topology

OUT=ROOT / 'art/characters/keyframes-v2/elf'
REFERENCE=ROOT / 'art/characters/elf-redesign-v2/elf-native.png'
POSES,NAMES=common.POSES,common.NAMES
INK,SKIN,BROWN,GREEN,LIME='#241C32','#F6D1AC','#916047','#718C59','#B5C77D'
PALETTE={rgb(c) for c in (INK,SKIN,BROWN,GREEN,LIME)}

def dump(path,data):common.dump(path,data)

def blink(frame):
    a=np.array(frame)
    for x in (11,16):a[22:24,x]=(*rgb(SKIN),255)
    # Move each eyelid inward, retaining its existing complete skin margin.
    a[23,11:13]=(*rgb(INK),255);a[23,15:17]=(*rgb(INK),255)
    return Image.fromarray(a)

def register():
    metadata=json.loads((OUT / 'generation.json').read_text(encoding='utf-8'))
    source=Image.open(OUT / metadata['selected_source']).convert('RGBA')
    cells=[]
    for i in range(8):
        x,y=i%4,i//4
        cell=source.crop((round(x*source.width/4),round(y*source.height/2),round((x+1)*source.width/4),round((y+1)*source.height/2)))
        cells.append(clean_background(cell,224))
    factor=360/max(cell.height for cell in cells)
    records=[]
    for name,cell in zip(POSES,cells):
        if name in ('idle','blink_idle'):
            reference=Image.open(REFERENCE).convert('RGBA')
            frame=reference if name=='idle' else blink(reference)
            frame.save(OUT / 'source' / f'{name}-registered.png')
            records.append({'id':name,'source':'approved_idle' if name=='idle' else 'approved_idle_pupil_state',
                'whole_body_reused':True,'native_size':[32,48]})
            continue
        a=np.array(cell);yy,xx=np.where(a[:round(cell.height*16/36),:,3]!=0)
        center=(int(xx.min())+int(xx.max())+1)/2
        fit=cell.resize((round(cell.width*factor),round(cell.height*factor)),Image.Resampling.NEAREST)
        x,y=round(155-center*factor),470-fit.height
        if min(x,y)<0 or x+fit.width>320:raise ValueError(f'Whole-body pose leaves native frame: {name}')
        canvas=Image.new('RGBA',(320,480));canvas.alpha_composite(fit,(x,y))
        native_grid(canvas,[32,48],0).save(OUT / 'source' / f'{name}-registered.png')
        records.append({'id':name,'source_crop_size':list(cell.size),'uniform_source_scale':factor,'registered_offset':[x,y],
            'head_center_anchor':15.5,'foot_target_row':46,'coherent_whole_body':True})
    dump(OUT / 'registration.json',{'sheet_size':list(source.size),'grid':[4,2],'uniform_scale_all_generated_poses':factor,
        'whole_body_registration':True,'old_face_hook_used':False,'no_cross_pose_limb_splicing':True,'frames':records})

def manifest():
    assets=[]
    for name in POSES:
        assets.append({'id':name,'source':f'art/characters/keyframes-v2/elf/source/{name}-registered.png',
            'size':[32,48],'position':[0,0],'margin':0,'dark_value':.27,'preserve_native_frame':True,
            'materials':{'outline':[INK],'skin':[SKIN],'hair_leather':[BROWN],'leaf':[GREEN,LIME]},
            'material_ramps':{'hair_leather':'wood'},
            'rules':[{'material':'skin','hue':[.025,.15],'saturation_min':.12,'saturation_max':.52,'value_min':.73},
                     {'material':'hair_leather','hue':[.025,.16],'saturation_min':.05,'value_max':.90}],
            'fallback_material':'leaf'})
        if name in ('walk_pass_a','walk_pass_b'):
            assets[-1]['materials']['shorts']=[GREEN]
            assets[-1]['material_ramps']['shorts']='leaf'
            rect=[11,37,14,40] if name=='walk_pass_a' else [14,37,20,40]
            ramps=json.loads((ROOT / 'art/ramps.json').read_text(encoding='utf-8'))
            baseline,_,_=material_remap(Image.open(OUT / 'source' / f'{name}-registered.png').convert('RGBA'),assets[-1],ramps)
            a=np.array(baseline);edge=common.boundary(a);points=[]
            for y in range(rect[1],rect[3]):
                for x in range(rect[0],rect[2]):
                    if not edge[y,x] and tuple(a[y,x,:3]) in (rgb(SKIN),rgb(BROWN)) and a[y,x,3]:points.append([x,y])
            assets[-1]['material_pixels']=[{'material':'shorts','pixels':points,
                'reason':'The bent upper thigh/cuff stays clothed above row40. Preserve the original pale leaf panel.'}]
        if name=='receive_hold':
            assets[-1]['background_alpha_rectangles']=[{'rect':[9,35,10,36],
                'reason':'Trim one wrist-outline excess so the standing waist is10pixels, retaining the arm and palm.'}]
    dump(OUT / 'manifest.json',{'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,'scale':3,
        'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json',
        'output':'art/characters/keyframes-v2/elf/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':assets})

def process():
    register();manifest()
    proc=subprocess.run([sys.executable,str(ROOT / 'tools/process_pixel_art.py'),str((OUT / 'manifest.json').relative_to(ROOT))],capture_output=True,text=True,encoding='utf-8')
    if proc.returncode:raise ValueError(proc.stdout+proc.stderr)
    return {name:Image.open(OUT / 'pipeline' / f'{name}-native.png').convert('RGBA') for name in POSES}

def board(frames,diagnostic=False):
    im=Image.new('RGBA',(648,466),'#241C32')
    common.text(im,(18,12),'엘프 · 잎 정찰복 키프레임'+(' 중간 검사' if diagnostic else ''),21)
    common.text(im,(18,45),'32×48 · 공통3배 · 같은 팔레트5색 · 머리16 / 몸통13 / 다리7행',12,'#C38EB5')
    for i,(name,label) in enumerate(zip(POSES,NAMES)):
        x,y=18+i%4*156,80+i//4*186
        ImageDraw.Draw(im).rectangle((x,y,x+144,y+177),fill='#4A3C52',outline='#827589')
        common.text(im,(x+7,y+5),label,12)
        im.alpha_composite(frames[name].resize((96,144),Image.Resampling.NEAREST),(x+24,y+27))
    im.convert('RGB').save(OUT / ('source/native-diagnostic.png' if diagnostic else 'keyframes-review.png'))

def diagnostic(frames):
    board(frames,True)
    chars={rgb(c):s for c,s in [(INK,'#'),(SKIN,'s'),(BROWN,'h'),(GREEN,'g'),(LIME,'L')]}
    for name,frame in frames.items():
        a=np.array(frame);head_y,head_x=np.where(a[11:27,:,3]!=0)
        print(name,'head',int(head_x.max()-head_x.min()+1),int(head_y.max()-head_y.min()+1),
            'first_row',int(np.where(a[:,:,3]!=0)[0].min()),'last_row',int(np.where(a[:,:,3]!=0)[0].max()))
        for y in (21,22,23,24,35,37,38,39):
            xx=np.where(a[y,:,3]!=0)[0]
            print(y,''.join(chars.get(tuple(p[:3]),'?') if p[3] else '.' for p in a[y]),'width',int(xx.max()-xx.min()+1) if len(xx) else 0)

def eyes(frame,closed=False):
    a=np.array(frame);result=[]
    pairs=[[(11,23),(12,23)],[(15,23),(16,23)]] if closed else [[(11,22),(11,23)],[(16,22),(16,23)]]
    for points in pairs:
        isolated=dark_component(frame,points[0],diagonals=True)==sorted(points)
        xs,ys=zip(*points)
        halo=all(tuple(a[y,x])==(*rgb(SKIN),255) for y in range(min(ys)-1,max(ys)+2)
            for x in range(min(xs)-1,max(xs)+2) if (x,y) not in points)
        result.append({'pixels':points,'isolated_dark_pixels2':isolated,'skin_halo1_with_diagonals':halo})
    return result

def snapshot():
    paths=list((ROOT / 'art/characters/keyframes-v1').glob('*/frames/*.png'))
    paths+=list((ROOT / 'art/mockups/full-ingame-v7/characters').glob('*.png'))
    paths+=[REFERENCE,ROOT / 'art/mockups/full-ingame-v7/animated-preview.html']
    return {str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

def finish(frames,before):
    report={'status':'passed','character':'elf','art_status':'candidate_keyframes','approved_by_user':False,
        'approved_design':'art/characters/elf-redesign-v2/approval.json','native_canvas':[32,48],'scale':3,'frame_count':8,
        'stage_order':['background_cleanup','native_grid','material_ramp_remap','validation'],'frames':{},
        'head_rows':[11,26],'torso_rows':[27,39],'legs_and_boots_rows':[40,46],'foot_row':46,'old_face_hook_used':False}
    for name,frame in frames.items():
        a=np.array(frame);check=validate(frame,[32,48],PALETTE,5)
        check['outline_boundary_violations']=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum())
        check['top11_rows_clear']=bool(not a[:11,:,3].any())
        check['ground_row46']=bool(a[46,:,3].any() and not a[47,:,3].any())
        yy,xx=np.where(a[11:27,:,3]!=0)
        check['head_bounds']=[int(xx.min()),int(yy.min())+11,int(xx.max())+1,int(yy.max())+12]
        check['head_fits22x16']=bool(xx.max()-xx.min()+1<=22 and yy.max()-yy.min()+1==16)
        widths=[]
        for y in range(37,40):
            xx=np.where(a[y,:,3]!=0)[0];widths.append(int(xx.max()-xx.min()+1))
        check['shorts_hem_widths']=widths;check['shorts_width10_to12']=all(10<=w<=12 for w in widths)
        if name in ('idle','receive_extend','receive_hold','blink_idle'):
            xx=np.where(a[35,:,3]!=0)[0]
            check['standing_waist_width']=int(xx.max()-xx.min()+1);check['standing_waist10']=check['standing_waist_width']==10
        check['eyes']=eyes(frame,name=='blink_idle')
        check['opaque_components']=topology.count_components(a[:,:,3]!=0)
        check['neck_enclosed_empty_pixels']=int(topology.enclosed_empty_pixels(a[:,:,3]!=0)[24:32].sum())
        check['exact3x']=np.array_equal(np.array(frame.resize((96,144),Image.Resampling.NEAREST)),np.repeat(np.repeat(a,3,0),3,1))
        if not check['passed'] or check['outline_boundary_violations'] or not all(check[k] for k in ('top11_rows_clear','ground_row46','head_fits22x16','shorts_width10_to12','exact3x')) or not check.get('standing_waist10',True) or not all(e['isolated_dark_pixels2'] and e['skin_halo1_with_diagonals'] for e in check['eyes']) or check['opaque_components']!=1 or check['neck_enclosed_empty_pixels']:
            report['status']='failed'
        report['frames'][name]=check
    report['idle_matches_approved_design']=bool(np.array_equal(np.array(frames['idle']),np.array(Image.open(REFERENCE).convert('RGBA'))))
    changed=np.any(np.array(frames['idle'])!=np.array(frames['blink_idle']),axis=2)
    allowed=np.zeros((48,32),bool);allowed[22:24,11:13]=True;allowed[22:24,15:17]=True
    report['blink_only_four_eye_pixels']=bool(changed.sum()==4 and not changed[~allowed].any())
    gait={}
    for name in ('walk_contact_a','walk_pass_a','walk_contact_b','walk_pass_b'):
        a=np.array(frames[name]);gait[name]={'left_outer_foot_on_ground':bool(a[46,8:15,3].any()),'right_outer_foot_on_ground':bool(a[46,18:26,3].any())}
    report['walk_support_feet']=gait
    report['opposite_walk_support']=bool(not gait['walk_pass_a']['left_outer_foot_on_ground'] and gait['walk_pass_a']['right_outer_foot_on_ground'] and gait['walk_pass_b']['left_outer_foot_on_ground'] and not gait['walk_pass_b']['right_outer_foot_on_ground'])
    for aa,bb,key,rows in [('walk_contact_a','walk_contact_b','contact_leg_changed_pixels',slice(40,47)),
        ('walk_pass_a','walk_pass_b','passing_leg_changed_pixels',slice(40,47)),
        ('walk_contact_a','walk_contact_b','contact_arm_changed_pixels',slice(27,36))]:
        report[key]=int(np.any(np.array(frames[aa])[rows]!=np.array(frames[bb])[rows],axis=2).sum())
        if not report[key]:report['status']='failed'
    if not all(report[k] for k in ('idle_matches_approved_design','blink_only_four_eye_pixels','opposite_walk_support')):report['status']='failed'
    grips={'receive_extend':[6,29],'receive_hold':[16,34]}
    anchors=common.bottle_anchors(frames,grips,grip_y_from_top=4)
    recipes=json.loads((ROOT / 'art/mockups/full-ingame-v6/potions/recipes.json').read_text(encoding='utf-8'))['recipes']
    recipe_by_id={r['id']:r for r in recipes}
    for name,(x,y) in grips.items():
        if tuple(np.array(frames[name])[y,x])!=(*rgb(SKIN),255):raise ValueError(f'Bottle grip misses the actual palm: {name}')
    for test in anchors['checks']:
        bottle=Image.open(ROOT / 'art/mockups/full-ingame-v6/potions' / recipe_by_id[test['recipe']]['bottle_path']).convert('RGBA')
        bx,by=test['bottle_origin'];mask=np.zeros((48,32),bool)
        mask[by:by+bottle.height,bx:bx+bottle.width]=np.array(bottle)[:,:,3]!=0
        for x in (11,16):
            if mask[21:25,x-1:x+2].any():raise ValueError(f'Bottle covers eye halo: {test}')
        if (mask[:27]& (np.array(frames[test['pose']])[:27,:,3]!=0)).any():raise ValueError(f'Bottle covers the head: {test}')
        test.update(elf_eye_skin_halos_clear=True,head_clear=True,grip_on_skin=True)
    report['bottle_anchor_validation']={'tested_recipes':36,'tested_pose_recipe_pairs':72,'grips_on_skin':True,'all_heads_and_eye_halos_clear':True,'local_grip_y':4}
    after=snapshot();changed_files=[p for p in before if after.get(p)!=before[p]]
    dump(OUT / 'regression-validation.json',{'status':'passed' if not changed_files else 'failed','existing_files_checked':len(before),'changed_files':changed_files,'sha256':before})
    if changed_files:report['status']='failed'
    dump(OUT / 'validation.json',report)
    if report['status']!='passed':raise ValueError(json.dumps(report,ensure_ascii=False))
    (OUT / 'frames').mkdir(exist_ok=True);sheet=Image.new('RGBA',(128,96))
    for i,(name,frame) in enumerate(frames.items()):
        frame.save(OUT / 'frames' / f'{name}.png');sheet.alpha_composite(frame,((i%4)*32,(i//4)*48))
    sheet.save(OUT / 'elf-keyframes-native.png');sheet.resize((384,288),Image.Resampling.NEAREST).save(OUT / 'elf-keyframes-3x.png')
    dump(OUT / 'hand-anchors.json',anchors);board(frames);preview(frames,anchors)
    print(json.dumps({'status':'passed','frames':8,'native':[32,48],'palette_colors':5,'bottle_pairs':72,'old_art_unchanged':len(before)},ensure_ascii=False))

def preview(frames,anchors):
    old=common.OUT;common.OUT=OUT
    try:common.write_preview(frames,anchors)
    finally:common.OUT=old
    data=json.loads((OUT / 'keyframes.json').read_text(encoding='utf-8'))
    data.update(character='elf',version=2,palette='art/palettes/v1/characters/elf.hex',native_sheet='elf-keyframes-native.png',
        approved_design='art/characters/elf-redesign-v2/approval.json',identity_reference='art/characters/elf-redesign-v2/elf-native.png',
        eyes={'open':[[11,22,1,2],[16,22,1,2]],'closed':[[11,23,2,1],[15,23,2,1]]},
        facing='left',bottle_local_grip_y=4,old_face_hook_used=False)
    dump(OUT / 'keyframes.json',data)
    page=(OUT / 'review.html').read_text(encoding='utf-8').replace('여행자','엘프').replace('손님 01','손님 03').replace('키프레임 v1','키프레임 v2').replace('traveler-keyframes','elf-keyframes')
    page=page.replace('갈색 머리와 배낭, 밝은 셔츠, 짧은 바지·부츠','옆땋은 머리·잎 장식, 한쪽 어깨 잎 상의, 가죽 허리띠와 반바지·부츠')
    page=page.replace('모자·배낭 같은 부착물은 머리 크기에 포함하지 않습니다.','승인된 잎 정찰복의 대기 전신을 유지합니다. 새 걷기·받기는 같은 전신 디자인을 기준으로 만들었습니다.')
    page=page.replace('같은 크기의 얼굴 수정 캐릭터와 비교','승인된 새 엘프와 같은 배율로 비교')
    page=page.replace('../../../mockups/full-ingame-v7/characters/elf-native.png','../../elf-redesign-v2/elf-native.png').replace('엘프 v7','승인된 새 엘프').replace('얼굴을 수정한 엘프','승인된 새 엘프')
    page=page.replace('frame.hand_grip_anchor[1]-6','frame.hand_grip_anchor[1]-4')
    start=page.index('<div class="palette">');end=page.index('</div></header>',start)
    swatches=[(INK,'테두리·눈·부츠'),(SKIN,'피부'),(BROWN,'머리·가죽'),(GREEN,'초록 상의·반바지'),(LIME,'잎 장식·허리 잎')]
    page=page[:start]+'<div class="palette">'+''.join(f'<span><i style="--color:{c}"></i>{label}</span>' for c,label in swatches)+page[end:]
    page=page.replace('id="guides" type="checkbox" checked','id="guides" type="checkbox"').replace('<body>','<body class="no-guide">')
    page=page.replace('@media(max-width:760px)','@media(max-width:580px)').replace('</style>','@media(max-width:900px){.review{grid-template-columns:1fr}.refs{flex-wrap:wrap}}</style>')
    page=page.replace('</style>','.compact-sheet{display:none}.compact-sheet h2{font-size:15px;margin:12px 0 8px}.compact-sheet .overflow{max-width:100%;overflow-x:auto;background:#4a3c52}.compact-sheet img{width:384px;height:288px;max-width:none;margin:0;image-rendering:pixelated}@media(max-width:580px){.compact-sheet{display:block;margin:12px 0 20px}}</style>')
    page=page.replace('</header><div class="controls">','</header><section class="compact-sheet"><h2>전체8포즈 · 공통3배</h2><div class="overflow"><img src="elf-keyframes-native.png" width="384" height="288" alt="엘프8키프레임 전체 시트 · 모두3배"></div></section><div class="controls">')
    page=page.replace('<span class="tag">5색','<label><input id="walk-loop" type="checkbox"> 걷기 키포즈 반복</label><span class="tag">5색')
    recipe_rows=json.loads((ROOT / 'art/mockups/full-ingame-v6/potions/recipes.json').read_text(encoding='utf-8'))['recipes']
    choices=[]
    for recipe_id,label in [('health','체력 · 둥근 병'),('moon','달빛 · 둥근 병'),('agility','민첩 · 긴 병')]:
        recipe=next(r for r in recipe_rows if r['id']==recipe_id)
        image=Image.open(ROOT / 'art/mockups/full-ingame-v6/potions' / recipe['bottle_path'])
        choices.append({'id':recipe_id,'name':label,'path':'../../../mockups/full-ingame-v6/potions/'+recipe['bottle_path'],'width':image.width,'height':image.height})
    options=''.join(f'<option value="{r["id"]}">{r["name"]}</option>' for r in choices)
    page=page.replace('<span class="tag">5색',f'<label>접점 물약 <select id="bottle-recipe">{options}</select></label><span class="tag">5색')
    page=page.replace('선택한 받기 포즈에 물약 접점 표시','받기 포즈에 물약 붙이기')
    page=page.replace('const frames=',f'const recipes={json.dumps(choices,ensure_ascii=False)};const frames=',1)
    page=page.replace("if(show){bottle.style.left=", "if(show){const recipe=recipes.find(r=>r.id===document.getElementById('bottle-recipe').value);bottle.src=recipe.path;bottle.alt=recipe.name;bottle.width=recipe.width*3;bottle.height=recipe.height*3;bottle.style.left=")
    page=page.replace("'별도 체력 물약 · 손 접점과 눈의 피부 여백을 확인하세요.'", "recipe.name+' · 원본'+recipe.width+'×'+recipe.height+' / 공통3배 · 손과 얼굴 가림을 확인하세요.'")
    page=page.replace("document.getElementById('show-bottle').addEventListener('change',update);update();", "document.getElementById('show-bottle').addEventListener('change',update);let walkTimer=null;document.getElementById('walk-loop').addEventListener('change',event=>{clearInterval(walkTimer);if(event.target.checked){current=1;update();walkTimer=setInterval(()=>{current=current===4?1:current+1;update();},250);}});document.querySelectorAll('.pose').forEach(button=>button.addEventListener('click',()=>{clearInterval(walkTimer);document.getElementById('walk-loop').checked=false;}));update();")
    page=page.replace("document.getElementById('show-bottle').addEventListener('change',update);let walkTimer", "document.getElementById('show-bottle').addEventListener('change',update);document.getElementById('bottle-recipe').addEventListener('change',update);let walkTimer")
    page=page.replace('현재는 키프레임 검토 단계입니다.','현재는 키프레임 검토 단계입니다. 걷기 반복은4개 주요 포즈를 확인하는 재생입니다.')
    page=page.replace('<a href="anatomy-comparison.png">부위·크기 비교</a>','<a href="../../elf-redesign-v2/review.html">승인된 전신 디자인</a>')
    page=page.replace('<a href="validation.json">검사 기록</a>','<a href="validation.json">검사 기록</a> · <a href="generation.json">생성·프롬프트 기록</a>')
    (OUT / 'review.html').write_text(page,encoding='utf-8')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--diagnostic',action='store_true');args=parser.parse_args()
    before=snapshot();frames=process()
    if args.diagnostic:diagnostic(frames)
    else:finish(frames,before)

if __name__=='__main__':main()
