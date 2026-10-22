"""Keeper brewing/handover keyposes with the existing head, hat and palette."""
from __future__ import annotations
import argparse,hashlib,json,subprocess,sys
import numpy as np
from PIL import Image,ImageDraw
from process_pixel_art import ROOT,clean_background,native_grid,rgb,validate
import build_traveler_keyframes_v1 as common
import build_combined_idle_v6 as topology
from build_rogue_keyframes_v2 import remove_alpha_specks
import audit_character_art_v1 as audit

OUT=ROOT/'art/characters/keyframes-v2/keeper'
REFERENCE=ROOT/'art/mockups/full-ingame-v7/characters/witch-native.png'
POSES=['idle','brew_reach','brew_stir_left','brew_stir_right','handover_extend','handover_return']
NAMES=['대기','제조 · 손 뻗기','제조 · 젓기A','제조 · 젓기B','전달 · 손 내밀기','전달 · 손 회수']
INK,SKIN,BROWN,PURPLE,GOLD='#241C32','#F6D1AC','#916047','#86548E','#E9B95F'
PALETTE={rgb(c) for c in (INK,SKIN,BROWN,PURPLE,GOLD)}
def dump(path,data):common.dump(path,data)

def register():
    meta=json.loads((OUT/'generation.json').read_text(encoding='utf-8'))
    source=Image.open(OUT/meta['selected_source']).convert('RGBA')
    cells=[];cut=meta.get('source_row_cut',round(source.height/2));columns=meta.get('source_column_cuts',[round(i*source.width/3) for i in range(4)])
    for i in range(6):
        x,y=i%3,i//3
        cells.append(remove_alpha_specks(source.crop((columns[x],0 if y==0 else cut,columns[x+1],cut if y==0 else source.height))))
    factors=[460/max(c.height for c in cells)]*6
    if meta.get('brew_source'):
        new=Image.open(OUT/meta['brew_source']).convert('RGBA')
        brew=[remove_alpha_specks(new.crop((round(i*new.width/3),0,round((i+1)*new.width/3),new.height))) for i in range(3)]
        scale=min(460/max(c.height for c in brew),318/max(c.width for c in brew))
        for index,cell in zip((1,2,3),brew):cells[index]=cell;factors[index]=scale
    original=np.array(Image.open(REFERENCE).convert('RGBA'));records=[]
    for name,cell,factor in zip(POSES,cells,factors):
        if name=='idle':
            Image.fromarray(original).save(OUT/'source/idle-registered.png');records.append({'id':name,'approved_neutral_reused':True});continue
        a=np.array(cell);yy,xx=np.where(a[:round(cell.height*14/46),:,3]!=0);center=(int(xx.min())+int(xx.max())+1)/2
        fit=cell.resize((round(cell.width*factor),round(cell.height*factor)),Image.Resampling.NEAREST)
        x,y=round(155-center*factor),470-fit.height
        if name.startswith('brew_'):x=max(0,min(x,320-fit.width))
        if min(x,y)<0 or x+fit.width>320:raise ValueError(f'Whole-body registration leaves frame: {name},{x,y},{fit.size}')
        canvas=Image.new('RGBA',(320,480));canvas.alpha_composite(fit,(x,y));grid=np.array(native_grid(canvas,[32,48],0))
        # Preserve the entire original head/hat/collar, not a generic facial patch.
        # The moving arms, torso and legs below this join all come from this one pose.
        arm=np.zeros((48,32),bool)
        if name.startswith('brew_'):arm[14:28,:10]=True
        raised=(arm & (original[:,:,3]==0) & (grid[:,:,3]!=0))
        raised_pixels=grid[raised].copy();grid[:28]=original[:28];grid[raised]=raised_pixels
        Image.fromarray(grid).save(OUT/'source'/f'{name}-registered.png')
        records.append({'id':name,'source_crop_size':list(cell.size),'common_uniform_scale':factor,'offset':[x,y],'original_head_hat_collar_rows':[0,27],'whole_body_pose_source':name,'cross_pose_limbs':False})
    dump(OUT/'registration.json',{'grid':[3,2],'sheet_size':list(source.size),'row_cut':cut,'source_render_magnification_calibrated':True,'head_hat_collar_reference':str(REFERENCE.relative_to(ROOT)).replace('\\','/'),'raised_forearm_region':[0,14,10,28],'old_face_hook_used':False,'frames':records})

def manifest():
    edits=json.loads((OUT/'semantic-masks.json').read_text(encoding='utf-8')) if (OUT/'semantic-masks.json').exists() else {}
    assets=[]
    for name in POSES:
        assets.append({'id':name,'source':f'art/characters/keyframes-v2/keeper/source/{name}-registered.png','size':[32,48],'position':[0,0],'margin':0,'dark_value':.24,'preserve_native_frame':True,
            'materials':{'outline':[INK],'skin':[SKIN],'wood':[BROWN],'purple':[PURPLE],'gold':[GOLD]},
            'rules':[{'material':'skin','hue':[.025,.17],'saturation_max':.45,'value_min':.75},
                     {'material':'gold','hue':[.075,.17],'saturation_min':.42,'value_min':.82},
                     {'material':'wood','hue':[.025,.17],'saturation_min':.10,'value_max':.90}],
            'fallback_material':'purple',**edits.get(name,{})})
    dump(OUT/'manifest.json',{'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,'scale':3,'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json','output':'art/characters/keyframes-v2/keeper/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':assets})

def process():
    register();manifest();p=subprocess.run([sys.executable,str(ROOT/'tools/process_pixel_art.py'),str((OUT/'manifest.json').relative_to(ROOT))],capture_output=True,text=True,encoding='utf-8')
    if p.returncode:raise ValueError(p.stdout+p.stderr)
    return {n:Image.open(OUT/'pipeline'/f'{n}-native.png').convert('RGBA') for n in POSES}

def board(frames,diagnostic=False):
    im=Image.new('RGBA',(504,466),INK)
    common.text(im,(18,12),'남자 주인공 · 제조/전달 키프레임',22)
    common.text(im,(18,45),'32×48 · 공통3배 · 승인5색 · 기존 모자/얼굴 · 같은 부위 기준',12,'#C38EB5')
    for i,(name,label) in enumerate(zip(POSES,NAMES)):
        x,y=18+i%3*156,80+i//3*186;ImageDraw.Draw(im).rectangle((x,y,x+144,y+177),fill='#4A3C52',outline='#827589');common.text(im,(x+7,y+5),label,12)
        im.alpha_composite(frames[name].resize((96,144),Image.Resampling.NEAREST),(x+24,y+27))
    im.convert('RGB').save(OUT/('source/native-diagnostic.png' if diagnostic else 'keyframes-review.png'))

def snapshot():
    paths=[REFERENCE]+list((ROOT/'art/characters/keyframes-v1').glob('*/frames/*.png'))+list((ROOT/'art/characters/keyframes-v2/elf/frames').glob('*.png'))+list((ROOT/'art/characters/keyframes-v2/rogue/frames').glob('*.png'))+list((ROOT/'art/mockups/full-ingame-v7/motion').glob('*/witch/frame-*.png'))
    return {str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

def diagnostic(frames):
    board(frames,True);chars={rgb(c):s for c,s in [(INK,'#'),(SKIN,'s'),(BROWN,'h'),(PURPLE,'p'),(GOLD,'G')]}
    for n,im in frames.items():
        a=np.array(im);print(n,'components',topology.count_components(a[:,:,3]!=0))
        for y in range(26,47):print(y,''.join(chars.get(tuple(p[:3]),'?') if p[3] else '.' for p in a[y]))

def finish(frames,before):
    original=np.array(Image.open(REFERENCE).convert('RGBA'));report={'status':'passed','character':'keeper','frame_count':6,'native_canvas':[32,48],'art_status':'candidate_keyframes','approved_by_user':False,'stage_order':['background_cleanup','native_grid','material_ramp_remap','validation'],'frames':{}}
    for n,im in frames.items():
        a=np.array(im);v=validate(im,[32,48],PALETTE,5)
        fixed=np.ones((27,32),bool)
        if n.startswith('brew_'):fixed[14:27,:10]&=original[14:27,:10,3]!=0
        v.update(outline_boundary_violations=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum()),head_hat_exact_reference=bool(np.array_equal(a[:27][fixed],original[:27][fixed])),raised_arm_excluded_from_head_size=n.startswith('brew_'),foot_row46=bool(a[46,:,3].any() and not a[47,:,3].any()),eyes=audit.eye_checks(im,'keeper'),opaque_components=topology.count_components(a[:,:,3]!=0),neck_enclosed_empty_pixels=int(topology.enclosed_empty_pixels(a[:,:,3]!=0)[23:30,12:23].sum()),torso_rows=[27,39],legs_boots_rows=[40,46])
        v['passed']=bool(v['passed'] and not v['outline_boundary_violations'] and v['head_hat_exact_reference'] and v['foot_row46'] and v['opaque_components']==1 and not v['neck_enclosed_empty_pixels'] and all(e['isolated2'] and e['full_skin_halo1'] for e in v['eyes']))
        if not v['passed']:report['status']='failed'
        report['frames'][n]=v
    report['idle_exact_reference']=np.array_equal(np.array(frames['idle']),original)
    report['stir_arm_changed_pixels']=int(np.any(np.array(frames['brew_stir_left'])[28:40]!=np.array(frames['brew_stir_right'])[28:40],axis=2).sum())
    report['handover_arm_changed_pixels']=int(np.any(np.array(frames['handover_extend'])[28:40]!=np.array(frames['handover_return'])[28:40],axis=2).sum())
    if not report['idle_exact_reference'] or min(report['stir_arm_changed_pixels'],report['handover_arm_changed_pixels'])==0:report['status']='failed'
    after=snapshot();changed=[p for p in before if after.get(p)!=before[p]]
    dump(OUT/'regression-validation.json',{'status':'passed' if not changed else 'failed','existing_files_checked':len(before),'changed_files':changed,'sha256':before})
    if changed:report['status']='failed'
    dump(OUT/'validation.json',report)
    if report['status']!='passed':raise ValueError('Keeper keypose checks failed; see validation.json')
    (OUT/'frames').mkdir(exist_ok=True);sheet=Image.new('RGBA',(96,96))
    for i,(n,im) in enumerate(frames.items()):im.save(OUT/'frames'/f'{n}.png');sheet.alpha_composite(im,(i%3*32,i//3*48))
    sheet.save(OUT/'keeper-keyframes-native.png');sheet.resize((288,288),Image.Resampling.NEAREST).save(OUT/'keeper-keyframes-3x.png');board(frames)
    print(json.dumps({'status':'passed','frames':6,'palette_colors':5,'old_art_unchanged':len(before)}))

def main():
    p=argparse.ArgumentParser();p.add_argument('--diagnostic',action='store_true');args=p.parse_args();before=snapshot();frames=process()
    if args.diagnostic:diagnostic(frames)
    else:finish(frames,before)
if __name__=='__main__':main()
