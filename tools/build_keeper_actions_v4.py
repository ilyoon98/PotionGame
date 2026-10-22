"""Register one generated keeper sheet and build a fixed-stance pixel animation rig."""
from __future__ import annotations
import argparse, hashlib, json, shutil, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from process_pixel_art import ROOT, native_grid, rgb, validate
from build_rogue_keyframes_v2 import remove_alpha_specks
import build_traveler_keyframes_v1 as common
import build_combined_idle_v6 as topology
import audit_character_art_v1 as audit

OUT=ROOT/'art/characters/keyframes-v4/keeper'
POSES=['idle','brew_reach','brew_stir_left','brew_stir_right','handover_extend','handover_return']
NAMES=['대기','제조 · 손 뻗기','제조 · 젓기A','제조 · 젓기B','전달 · 손 내밀기','전달 · 손 낮추기']
SOURCE_ORDER=POSES[1:4]+[POSES[0]]+POSES[4:]
INK,SKIN,BROWN,PURPLE,GOLD='#241C32','#F6D1AC','#916047','#86548E','#E9B95F'
PALETTE={rgb(c) for c in (INK,SKIN,BROWN,PURPLE,GOLD)}
def dump(path,data):common.dump(path,data)

def register():
    source=Image.open(OUT/'source/generated-01.png').convert('RGBA')
    cells=[]
    for i in range(6):
        col,row=i%3,i//3
        cells.append(remove_alpha_specks(source.crop((round(col*source.width/3),round(row*source.height/2),round((col+1)*source.width/3),round((row+1)*source.height/2)))))
    factor=min(450/max(c.height for c in cells),310/max(c.width for c in cells))
    records=[]
    for name,cell in zip(SOURCE_ORDER,cells):
        a=np.array(cell);_,xx=np.where(a[:round(cell.height*.43),:,3]>0)
        center=(int(xx.min())+int(xx.max())+1)/2
        fit=cell.resize((round(cell.width*factor),round(cell.height*factor)),Image.Resampling.NEAREST)
        x,y=round(155-center*factor),470-fit.height
        if x<0 or x+fit.width>320:raise ValueError('Whole-body source out of bounds')
        canvas=Image.new('RGBA',(320,480));canvas.alpha_composite(fit,(x,y))
        native_grid(canvas,[32,48],0).save(OUT/'source'/f'{name}-registered.png')
        records.append({'id':name,'uniform_scale':factor,'crop_size':list(cell.size),'offset':[x,y],'old_head_overlay':False,'whole_body_source':True})
    dump(OUT/'registration.json',{'source_grid':[3,2],'uniform_source_scale':factor,'frames':records})

def pipeline(apply_edits=True):
    edits=json.loads((OUT/'semantic-masks.json').read_text(encoding='utf-8')) if apply_edits and (OUT/'semantic-masks.json').exists() else {}
    assets=[]
    for name in POSES:
        assets.append({'id':name,'source':f'art/characters/keyframes-v4/keeper/source/{name}-registered.png','size':[32,48],'position':[0,0],'margin':0,'dark_value':.24,'preserve_native_frame':True,
            'materials':{'outline':[INK],'skin':[SKIN],'wood':[BROWN],'purple':[PURPLE],'gold':[GOLD]},
            'rules':[{'material':'skin','hue':[.025,.17],'saturation_max':.46,'value_min':.75},
                     {'material':'gold','hue':[.075,.17],'saturation_min':.42,'value_min':.82},
                     {'material':'wood','hue':[.025,.17],'saturation_min':.10,'value_max':.90}],
            'fallback_material':'purple',**edits.get(name,{})})
    manifest={'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,'scale':3,'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json','output':'art/characters/keyframes-v4/keeper/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':assets}
    dump(OUT/'manifest.json',manifest)
    result=subprocess.run([sys.executable,str(ROOT/'tools/process_pixel_art.py'),str((OUT/'manifest.json').relative_to(ROOT))],capture_output=True,text=True,encoding='utf-8')
    if result.returncode:raise ValueError(result.stdout+result.stderr)
    return {n:Image.open(OUT/'pipeline'/f'{n}-native.png').convert('RGBA') for n in POSES}

def board(frames,path,title='남자 주인공 · 방향과 행동 수정'):
    im=Image.new('RGBA',(504,466),INK);common.text(im,(18,12),title,22)
    common.text(im,(18,45),'32×48 · 승인5색 · 전신 방향 통일 · 허리/발 고정',12,'#C38EB5')
    for i,n in enumerate(POSES):
        x,y=18+i%3*156,80+i//3*186
        ImageDraw.Draw(im).rectangle((x,y,x+144,y+177),fill='#4A3C52',outline='#827589')
        common.text(im,(x+7,y+5),NAMES[i],12);im.alpha_composite(frames[n].resize((96,144),Image.Resampling.NEAREST),(x+24,y+27))
    im.convert('RGB').save(path)

def diagnostic(frames):
    board(frames,OUT/'source/native-diagnostic.png')
    chars={rgb(c):s for c,s in [(INK,'#'),(SKIN,'s'),(BROWN,'h'),(PURPLE,'p'),(GOLD,'G')]}
    for n,im in frames.items():
        a=np.array(im);print(n)
        for y in range(13,42):print(y,''.join(chars.get(tuple(p[:3]),'?') if p[3] else '.' for p in a[y]))

def semantic_masks(frames):
    corrections={}
    for n,im in frames.items():
        a=np.array(im);edge=common.boundary(a);points=[];pupils=[]
        eyes=[(11,19),(13,19)] if n.startswith('brew') else [(17,19),(19,19)]
        for x,y in eyes:
            pupils.extend([[x,y],[x,y+1]])
            for yy in range(y-1,y+3):
                for xx in range(x-1,x+2):
                    if not a[yy,xx,3] or edge[yy,xx]:
                        # Normalization uses a single coherent head per direction.
                        # Only the selected base heads must contain the complete halo.
                        if n in ('idle','brew_stir_left'):raise ValueError(f'Eye halo outside face: {n}/{xx,yy}')
                        continue
                    points.append([xx,yy])
        pants=[[int(x),int(y)] for y,x in zip(*np.where(np.all(a[:,:,:3]==rgb(SKIN),axis=2)&(a[:,:,3]>0)&~edge)) if 38<=y<40]
        hair=[[int(x),int(y)] for y,x in zip(*np.where(np.all(a[:,:,:3]==rgb(SKIN),axis=2)&(a[:,:,3]>0)&~edge)) if 15<=y<18]
        corrections[n]={'material_pixels':[
            {'material':'skin','pixels':points,'reason':'Both eyes have a full one-pixel skin halo without changing silhouette.'},
            {'material':'outline','pixels':pupils,'reason':'Two equal 1x2 pupils on one row; no hair-connected third eye pixel.'},
            {'material':'wood','pixels':pants,'reason':'Shorts cover upper thighs in rows38/39; knees begin in row40.'},
            {'material':'wood','pixels':hair,'reason':'Brown bangs cannot acquire skin-coloured highlights; purple belongs to hat and cloak.'}]}
    dump(OUT/'semantic-masks.json',corrections)

def fixed_rig(frames):
    """Lock generated whole-body variants to their common stance, not the old head.

    Each arm window replaces its own entire positive and negative space. It
    cannot retain the old palm underneath. Both direction bases are from the
    same new full-body sheet; no historical head or detached limb donor is used.
    """
    arrays={n:np.array(im) for n,im in frames.items()};out={}
    left=arrays['brew_stir_left'];right=arrays['idle'];handover=arrays['handover_extend'].copy()
    handover[:25]=right[:25];handover[36:]=right[36:]
    left_window=np.zeros((48,32),bool);left_window[19:24,:8]=True;left_window[24:32,:14]=True
    right_window=np.zeros((48,32),bool);right_window[25:32,18:]=True
    for n in POSES:
        if n.startswith('brew'):
            a=left.copy();a[left_window]=arrays[n][left_window]
        elif n.startswith('handover'):
            a=handover.copy();a[right_window]=arrays[n][right_window]
        else:a=right.copy()
        a[common.boundary(a)]=(*rgb(INK),255)
        out[n]=Image.fromarray(a)
    masks={}
    for name,mask in [('brew_working_arm',left_window),('handover_working_arm',right_window)]:
        masks[name]=[[int(x),int(y)] for y,x in zip(*np.where(mask))]
    dump(OUT/'rig-registration.json',{'method':'One new whole-body source sheet. Fixed head/waist/feet per facing; complete working-arm windows include their transparent space. No old head or isolated limb donor.',
         'user_reason':'Whole orientation and two hands; handover waist must not sway.', 'same_generated_sheet':True,'old_head_overlay':False,'windows':masks,'handover_stationary_hip_rows':[36,47]})
    return out

def finish(frames):
    report={'status':'passed','version':4,'frame_count':6,'runtime_integrated':False,'frames':{}}
    arrays={n:np.array(im) for n,im in frames.items()}
    hair_masks={}
    for direction,name in [('left','brew_stir_left'),('right','idle')]:
        a=arrays[name];hair_masks[direction]=[[int(x),int(y)] for y,x in zip(*np.where(np.all(a[:,:,:3]==rgb(BROWN),axis=2)&(a[:,:,3]>0))) if 14<=y<25]
    dump(OUT/'hair-material-mask.json',{'allowed_hair_colors':[BROWN,INK],'forbidden_hair_color':PURPLE,'directions':hair_masks,'note':'Explicit native hair landmarks inspected in the new full-body sheet. Palette membership alone does not validate material identity.'})
    for n,im in frames.items():
        a=arrays[n];left=n.startswith('brew');eyes=[(11,19),(13,19)] if left else [(17,19),(19,19)]
        v=validate(im,[32,48],PALETTE,5);v.update(eyes=audit.eye_checks(im,'keeper',positions=eyes),outline_boundary_violations=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum()),foot_row46=bool(a[46,:,3].any() and not a[47,:,3].any()),opaque_components=topology.count_components(a[:,:,3]>0),facing='left' if left else 'right')
        points=hair_masks['left' if left else 'right'];v['purple_hair_pixels']=sum(tuple(a[y,x,:3])==rgb(PURPLE) for x,y in points)
        parts=({'hand_active':[2,19,8,29],'hand_rest':[19,32,24,36]} if left else {'hand_active':[18,32,24,36] if n=='idle' else [24,25,30,31],'hand_rest':[6,32,12,36]})
        parts.update(head=[8,14,23,25],shirt=[13,25,20,33] if left else [11,25,20,33],knees=[7,40,24,43])
        skin=np.all(a[:,:,:3]==rgb(SKIN),axis=2)&(a[:,:,3]>0);assigned=np.zeros((48,32),bool);part_report={}
        for part,(x0,y0,x1,y1) in parts.items():
            mask=np.zeros((48,32),bool);mask[y0:y1,x0:x1]=True;mask&=skin&~assigned;assigned|=mask
            part_report[part]={'region':[x0,y0,x1,y1],'skin_pixels':int(mask.sum())}
        v['skin_parts']=part_report;v['unassigned_skin_pixels']=int((skin&~assigned).sum());v['two_hands']=bool(all(part_report[p]['skin_pixels']>=4 for p in ('hand_active','hand_rest')) and not v['unassigned_skin_pixels'])
        sections={'brew_reach':[(8,23,28),(10,24,29)],'brew_stir_left':[(8,24,29),(10,24,29)],'brew_stir_right':[(8,26,31),(10,26,31)],'handover_extend':[(22,26,31),(23,26,31)],'handover_return':[(22,26,31),(23,26,31)]}
        samples=[]
        for x,y0,y1 in sections.get(n,[]):
            col=a[y0:y1,x];opaque=int((col[:,3]>0).sum());purple=int(np.all(col[:,:3]==rgb(PURPLE),axis=1).sum());samples.append({'column':x,'rows':[y0,y1],'opaque_width':opaque,'purple_interior':purple,'passed':opaque>=4 and purple>=2})
        v['sleeve_sections']=samples;v['sleeves_filled']=all(s['passed'] for s in samples)
        if n.startswith('handover'):
            v['waist_hips_legs_fixed']=bool(np.array_equal(a[32:],arrays['handover_extend'][32:]))
            v['head_hat_fixed_between_keyposes']=bool(np.array_equal(a[:25],arrays['idle'][:25]))
        if left:v['body_outside_working_arm_fixed']=bool(np.array_equal(a[32:],arrays['brew_stir_left'][32:]))
        v['passed']=bool(v['passed'] and not v['outline_boundary_violations'] and v['foot_row46'] and v['opaque_components']==1 and not v['purple_hair_pixels'] and v['two_hands'] and v['sleeves_filled'] and all(e['isolated2'] and e['full_skin_halo1'] for e in v['eyes']) and v.get('waist_hips_legs_fixed',True) and v.get('body_outside_working_arm_fixed',True))
        if not v['passed']:report['status']='failed'
        report['frames'][n]=v
    dump(OUT/'validation.json',report)
    if report['status']!='passed':raise ValueError('Native rig validation failed; inspect validation.json')
    (OUT/'frames').mkdir(exist_ok=True);sheet=Image.new('RGBA',(96,96))
    for i,n in enumerate(POSES):frames[n].save(OUT/'frames'/f'{n}.png');sheet.alpha_composite(frames[n],(i%3*32,i//3*48))
    sheet.save(OUT/'keeper-keyframes-native.png');board(frames,OUT/'keyframes-review.png')
    print('keeper v4 six frames: native palette, eyes, hair materials, fixed handover waist/legs passed')

def main():
    p=argparse.ArgumentParser();p.add_argument('--diagnostic',action='store_true');args=p.parse_args()
    register();frames=pipeline(False)
    if args.diagnostic:diagnostic(frames);return
    semantic_masks(frames);frames=pipeline();frames=fixed_rig(frames);finish(frames)

if __name__=='__main__':main()
