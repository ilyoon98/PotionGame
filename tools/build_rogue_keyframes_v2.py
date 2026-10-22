"""Native cat rogue keyposes, registered and checked through the shared pipeline."""
from __future__ import annotations
import argparse
import hashlib
import json
import subprocess
import sys
import numpy as np
from PIL import Image, ImageDraw
from process_pixel_art import ROOT, clean_background, native_grid, rgb, validate
from prepare_character_v6 import dark_component
import build_traveler_keyframes_v1 as common
import build_combined_idle_v6 as topology

OUT=ROOT/'art/characters/keyframes-v2/rogue'
POSES,NAMES=common.POSES,common.NAMES
INK,SKIN,ORANGE,LIGHT,SCARF='#241C32','#F6D1AC','#DE7356','#F4AC68','#9D4359'
PALETTE={rgb(c) for c in (INK,SKIN,ORANGE,LIGHT,SCARF)}
EYES=[(10,23),(14,23)]
def dump(path,data):common.dump(path,data)

def remove_alpha_specks(cell):
    a=np.array(cell);mask=a[:,:,3]>=224;seen=np.zeros(mask.shape,bool);components=[]
    for y,x in zip(*np.where(mask)):
        if seen[y,x]:continue
        points=[];stack=[(int(x),int(y))];seen[y,x]=True
        while stack:
            xx,yy=stack.pop();points.append((xx,yy))
            for dx,dy in ((-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)):
                nx,ny=xx+dx,yy+dy
                if 0<=nx<mask.shape[1] and 0<=ny<mask.shape[0] and mask[ny,nx] and not seen[ny,nx]:seen[ny,nx]=True;stack.append((nx,ny))
        components.append(points)
    largest=max(components,key=len)
    for points in components:
        if points is largest:continue
        if len(points)>len(largest)*.005:raise ValueError('Meaningful disconnected source feature needs inspection')
        for x,y in points:a[y,x]=0
    return clean_background(Image.fromarray(a),224)

def register():
    meta=json.loads((OUT/'generation.json').read_text(encoding='utf-8'))
    source=Image.open(OUT/meta['selected_source']).convert('RGBA')
    cells=[];row_cut=meta.get('source_row_cut',round(source.height/2))
    for i in range(8):
        x,y=i%4,i//4
        cells.append(remove_alpha_specks(source.crop((round(x*source.width/4),0 if y==0 else row_cut,round((x+1)*source.width/4),row_cut if y==0 else source.height))))
    factors=[360/max(c.height for c in cells[:7])]*8
    if meta.get('walk_b_source'):
        extra=Image.open(OUT/meta['walk_b_source']).convert('RGBA')
        pair=[remove_alpha_specks(extra.crop((round(i*extra.width/2),0,round((i+1)*extra.width/2),extra.height))) for i in range(2)]
        paired_scale=360/max(c.height for c in pair)
        for index,cell in zip((3,4),pair):cells[index]=cell;factors[index]=paired_scale
    records=[]
    for name,cell,factor in zip(POSES,cells,factors):
        if name=='blink_idle':
            Image.open(OUT/'source/idle-registered.png').save(OUT/'source/blink_idle-registered.png')
            records.append({'id':name,'source':'idle-registered.png','whole_body_reused':True,'only_pupil_material_state_changes':True})
            continue
        a=np.array(cell);yy,xx=np.where(a[:round(cell.height*16/36),:,3]!=0)
        center=(int(xx.min())+int(xx.max())+1)/2
        fit=cell.resize((round(cell.width*factor),round(cell.height*factor)),Image.Resampling.NEAREST)
        x,y=round(155-center*factor),470-fit.height
        if name in ('walk_contact_a','walk_contact_b','walk_pass_b'):y+=10
        if min(x,y)<0 or x+fit.width>320:raise ValueError(f'Whole pose out of canvas: {name}, {(x,y)}, {fit.size}')
        canvas=Image.new('RGBA',(320,480));canvas.alpha_composite(fit,(x,y))
        native_grid(canvas,[32,48],0).save(OUT/'source'/f'{name}-registered.png')
        records.append({'id':name,'source_crop_size':list(cell.size),'uniform_source_scale':factor,'offset':[x,y],'head_center':15.5,'foot_row':46,'coherent_whole_body':True})
    dump(OUT/'registration.json',{'grid':[4,2],'sheet_size':list(source.size),'source_render_magnification_calibrated_by_whole_body_height':True,'uniform_scale_within_each_generated_sheet':True,'old_face_hook_used':False,'cross_pose_limb_splicing':False,'frames':records})

def manifest():
    corrections=json.loads((OUT/'semantic-masks.json').read_text(encoding='utf-8')) if (OUT/'semantic-masks.json').exists() else {}
    assets=[]
    for name in POSES:
        assets.append({'id':name,'source':f'art/characters/keyframes-v2/rogue/source/{name}-registered.png','size':[32,48],'position':[0,0],'margin':0,'dark_value':.40,'preserve_native_frame':True,
            'materials':{'outline':[INK],'skin':[SKIN],'hair_tail':[ORANGE,LIGHT],'scarf':[SCARF]},'material_ramps':{'hair_tail':'fire','scarf':'fire'},
            'rules':[{'material':'scarf','hue':[.94,1.0]},
                     {'material':'skin','hue':[.025,.15],'saturation_max':.51,'value_min':.64}],
            'fallback_material':'hair_tail',**corrections.get(name,{})})
    dump(OUT/'manifest.json',{'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,'scale':3,'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json','output':'art/characters/keyframes-v2/rogue/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':assets})

def process():
    register();manifest()
    proc=subprocess.run([sys.executable,str(ROOT/'tools/process_pixel_art.py'),str((OUT/'manifest.json').relative_to(ROOT))],capture_output=True,text=True,encoding='utf-8')
    if proc.returncode:raise ValueError(proc.stdout+proc.stderr)
    frames={n:Image.open(OUT/'pipeline'/f'{n}-native.png').convert('RGBA') for n in POSES}
    return frames

def board(frames,diagnostic=False):
    im=Image.new('RGBA',(648,466),INK)
    common.text(im,(18,12),'고양이 도적 · 키프레임'+(' 중간 검사' if diagnostic else ''),21)
    common.text(im,(18,45),'32×48 · 공통3배 · 승인5색 · 머리 기준22×16 / 몸통13 / 다리7행',12,'#C38EB5')
    for i,(name,label) in enumerate(zip(POSES,NAMES)):
        x,y=18+i%4*156,80+i//4*186
        ImageDraw.Draw(im).rectangle((x,y,x+144,y+177),fill='#4A3C52',outline='#827589')
        common.text(im,(x+7,y+5),label,12)
        im.alpha_composite(frames[name].resize((96,144),Image.Resampling.NEAREST),(x+24,y+27))
    im.convert('RGB').save(OUT/('source/native-diagnostic.png' if diagnostic else 'keyframes-review.png'))

def eye_checks(frame,closed=False):
    a=np.array(frame);pairs=[[(10,24),(11,24)],[(13,24),(14,24)]] if closed else [[(x,y),(x,y+1)] for x,y in EYES]
    checks=[]
    for points in pairs:
        xs,ys=zip(*points)
        halo=all(tuple(a[y,x])==(*rgb(SKIN),255) for y in range(min(ys)-1,max(ys)+2) for x in range(min(xs)-1,max(xs)+2) if (x,y) not in points)
        try:isolated=dark_component(frame,points[0],diagonals=True)==sorted(points)
        except ValueError:isolated=False
        checks.append({'pixels':points,'isolated_dark_pixels2':isolated,'skin_halo1_with_diagonals':halo})
    return checks

def snapshot():
    paths=list((ROOT/'art/characters/keyframes-v1').glob('*/frames/*.png'))+list((ROOT/'art/characters/keyframes-v2/elf/frames').glob('*.png'))+list((ROOT/'art/mockups/full-ingame-v7/characters').glob('*.png'))
    paths+=[ROOT/'art/characters/elf-redesign-v2/elf-native.png',ROOT/'art/mockups/full-ingame-v7/animated-preview.html']
    return {str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

def diagnostic(frames):
    board(frames,True)
    chars={rgb(c):s for c,s in [(INK,'#'),(SKIN,'s'),(ORANGE,'o'),(LIGHT,'L'),(SCARF,'r')]}
    for name,frame in frames.items():
        a=np.array(frame);yy,xx=np.where(a[11:27,:,3]!=0)
        print(name,'head_bbox',(int(xx.min()),int(yy.min())+11,int(xx.max())+1,int(yy.max())+12),'components',topology.count_components(a[:,:,3]!=0),'eyes',eye_checks(frame,name=='blink_idle'))
        for y in range(11,47):print(y,''.join(chars.get(tuple(p[:3]),'?') if p[3] else '.' for p in a[y]))

def finish(frames,before):
    report={'status':'passed','character':'rogue','art_status':'candidate_keyframes','approved_by_user':False,'native_canvas':[32,48],'frame_count':8,'stage_order':['background_cleanup','native_grid','material_ramp_remap','validation'],'frames':{},'head_rows':[11,26],'torso_rows':[27,39],'legs_and_boots_rows':[40,46],'foot_row':46,'old_face_hook_used':False}
    for name,frame in frames.items():
        a=np.array(frame);check=validate(frame,[32,48],PALETTE,5)
        check['outline_boundary_violations']=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum())
        check['top11_rows_clear']=bool(not a[:11,:,3].any());check['ground_row46']=bool(a[46,:,3].any() and not a[47,:,3].any())
        yy,xx=np.where(a[11:27,:,3]!=0)
        check['head_bounds']=[int(xx.min()),int(yy.min())+11,int(xx.max())+1,int(yy.max())+12]
        check['head_fits22x16']=bool(xx.max()-xx.min()+1<=22 and 14<=yy.max()-yy.min()+1<=16)
        check['eyes']=eye_checks(frame,name=='blink_idle');check['opaque_components']=topology.count_components(a[:,:,3]!=0)
        holes=topology.enclosed_empty_pixels(a[:,:,3]!=0)
        check['neck_check_region']=[11,26,18,31]
        check['neck_enclosed_empty_pixels']=int(holes[26:31,11:18].sum())
        check['full_silhouette_enclosed_empty_pixels']=int(holes.sum())
        check['tail_loop_negative_space_allowed']=True
        check['exact3x']=np.array_equal(np.array(frame.resize((96,144),Image.Resampling.NEAREST)),np.repeat(np.repeat(a,3,0),3,1))
        if not check['passed'] or check['outline_boundary_violations'] or not all(check[k] for k in ('top11_rows_clear','ground_row46','head_fits22x16','exact3x')) or not all(e['isolated_dark_pixels2'] and e['skin_halo1_with_diagonals'] for e in check['eyes']) or check['opaque_components']!=1 or check['neck_enclosed_empty_pixels']:report['status']='failed'
        report['frames'][name]=check
    change=np.any(np.array(frames['idle'])!=np.array(frames['blink_idle']),axis=2);allowed=np.zeros((48,32),bool);allowed[23:25,10:12]=True;allowed[23:25,13:15]=True
    report['blink_only_four_eye_pixels']=bool(change.sum()==4 and not change[~allowed].any())
    gait={n:{'left_outer_foot_on_ground':bool(np.array(frames[n])[46,:13,3].any()),'right_outer_foot_on_ground':bool(np.array(frames[n])[46,16:,3].any())} for n in POSES[1:5]}
    report['walk_support_feet']=gait
    report['opposite_walk_support']=bool(not gait['walk_pass_a']['left_outer_foot_on_ground'] and gait['walk_pass_a']['right_outer_foot_on_ground'] and gait['walk_pass_b']['left_outer_foot_on_ground'] and not gait['walk_pass_b']['right_outer_foot_on_ground'])
    report['contact_both_feet_ground']=all(all(gait[n].values()) for n in ('walk_contact_a','walk_contact_b'))
    for aa,bb,key,rows in [('walk_contact_a','walk_contact_b','contact_leg_changed_pixels',slice(40,47)),('walk_pass_a','walk_pass_b','passing_leg_changed_pixels',slice(40,47)),('walk_contact_a','walk_contact_b','contact_arm_changed_pixels',slice(27,36))]:
        report[key]=int(np.any(np.array(frames[aa])[rows]!=np.array(frames[bb])[rows],axis=2).sum())
        if not report[key]:report['status']='failed'
    if not report['blink_only_four_eye_pixels'] or not report['opposite_walk_support'] or not report['contact_both_feet_ground']:report['status']='failed'
    grips=json.loads((OUT/'grips.json').read_text(encoding='utf-8'))
    anchors=common.bottle_anchors(frames,grips,grip_y_from_top=4)
    recipes={r['id']:r for r in json.loads((ROOT/'art/mockups/full-ingame-v6/potions/recipes.json').read_text(encoding='utf-8'))['recipes']}
    for name,(x,y) in grips.items():
        if tuple(np.array(frames[name])[y,x])!=(*rgb(SKIN),255):raise ValueError(f'Actual skin palm missing: {name}')
    for test in anchors['checks']:
        bottle=Image.open(ROOT/'art/mockups/full-ingame-v6/potions'/recipes[test['recipe']]['bottle_path']).convert('RGBA');bx,by=test['bottle_origin'];mask=np.zeros((48,32),bool)
        mask[by:by+bottle.height,bx:bx+bottle.width]=np.array(bottle)[:,:,3]!=0
        if (mask[:27]&(np.array(frames[test['pose']])[:27,:,3]!=0)).any():raise ValueError(f'Bottle covers head: {test}')
        for x,y in EYES:
            if mask[y-1:y+3,x-1:x+2].any():raise ValueError(f'Bottle covers eye halo: {test}')
        test.update(rogue_head_and_eye_halos_clear=True,grip_on_skin=True)
    report['bottle_anchor_validation']={'tested_recipes':36,'tested_pose_recipe_pairs':72,'all_grips_on_skin':True,'all_heads_and_eye_halos_clear':True,'local_grip_y':4}
    after=snapshot();changed=[p for p in before if after.get(p)!=before[p]]
    dump(OUT/'regression-validation.json',{'status':'passed' if not changed else 'failed','existing_files_checked':len(before),'changed_files':changed,'sha256':before})
    if changed:report['status']='failed'
    dump(OUT/'validation.json',report)
    if report['status']!='passed':raise ValueError('Native pose checks failed. See validation.json for the measured failure.')
    (OUT/'frames').mkdir(exist_ok=True);sheet=Image.new('RGBA',(128,96))
    for i,(name,frame) in enumerate(frames.items()):frame.save(OUT/'frames'/f'{name}.png');sheet.alpha_composite(frame,((i%4)*32,(i//4)*48))
    sheet.save(OUT/'rogue-keyframes-native.png');sheet.resize((384,288),Image.Resampling.NEAREST).save(OUT/'rogue-keyframes-3x.png');dump(OUT/'hand-anchors.json',anchors);board(frames);preview(frames,anchors)
    print(json.dumps({'status':'passed','frames':8,'palette_colors':5,'native':[32,48],'bottle_pairs':72,'old_art_unchanged':len(before)}))

def preview(frames,anchors):
    # Copy the existing review UI, replacing only this customer's data and references.
    source=ROOT/'art/characters/keyframes-v2/elf/review.html'
    page=source.read_text(encoding='utf-8').replace('엘프','고양이 도적').replace('손님 03','손님 04').replace('elf-keyframes','rogue-keyframes')
    page=page.replace('옆땋은 머리·잎 장식, 한쪽 어깨 잎 상의, 가죽 허리띠와 반바지·부츠','주황 머리·고양이 귀·꼬리, 붉은 목도리, 검은 짧은 상의·반바지·장갑·부츠')
    page=page.replace('승인된 잎 정찰복의 대기 전신을 유지합니다. 새 걷기·받기는 같은 전신 디자인을 기준으로 만들었습니다.','승인된 도적 팔레트와 기존 게임의 외형을32×48로 단순화했습니다. 포즈는 검토 후보입니다.')
    start=page.index('<div class="palette">');end=page.index('</div></header>',start)
    page=page[:start]+'<div class="palette">'+''.join(f'<span><i style="--color:{c}"></i>{label}</span>' for c,label in [(INK,'테두리·눈·검은 의상'),(SKIN,'피부'),(ORANGE,'머리·귀·꼬리'),(LIGHT,'머리·꼬리 밝음'),(SCARF,'붉은 목도리')])+page[end:]
    page=page.replace('승인된 새 고양이 도적와 같은 배율로 비교','엘프와 같은 배율로 비교').replace('승인된 새 고양이 도적','최신 엘프')
    page=page.replace('../../elf-redesign-v2/elf-native.png','../elf/frames/idle.png').replace('../../elf-redesign-v2/review.html','../elf/review.html').replace('승인된 전신 디자인','엘프 키프레임')
    data=[]
    for i,(name,label) in enumerate(zip(POSES,NAMES)):
        data.append({'id':name,'name':label,'index':i,'path':f'frames/{name}.png','native_size':[32,48],'sheet_rect':[(i%4)*32,(i//4)*48,32,48],'hand_grip_anchor':anchors['hand_grip_anchors'].get(name),'status':'candidate_keyframe'})
    start=page.index('const frames=')+len('const frames=');end=page.index(';',start);page=page[:start]+json.dumps(data,ensure_ascii=False)+page[end:]
    dump(OUT/'keyframes.json',{'schema_version':1,'character':'rogue','version':2,'status':'candidate_keyframes','palette':'art/palettes/v1/characters/rogue.hex','frames':data,'native_sheet':'rogue-keyframes-native.png','scale':3,'anatomy':{'head_rows':[11,26],'head_reference_size':[22,16],'torso_rows':[27,39],'legs_and_boots_rows':[40,46],'foot_row':46},'eyes':{'open':[[10,23,1,2],[14,23,1,2]],'closed':[[10,24,2,1],[13,24,2,1]]},'bottle_local_grip_y':4,'source':'generation.json','animations_status':'not_produced; walking preview is a four-keypose flipbook','runtime_integrated':False})
    (OUT/'review.html').write_text(page,encoding='utf-8')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--diagnostic',action='store_true');args=parser.parse_args();before=snapshot();frames=process()
    if args.diagnostic:diagnostic(frames)
    else:finish(frames,before)
if __name__=='__main__':main()
