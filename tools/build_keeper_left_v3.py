"""New left-facing whole-body brewing poses; no old head or limb overlays."""
import argparse,hashlib,json,subprocess,sys
import numpy as np
from PIL import Image,ImageDraw
from process_pixel_art import ROOT,native_grid,rgb,validate
from build_rogue_keyframes_v2 import remove_alpha_specks
import build_keeper_keyframes_v2 as base
import build_traveler_keyframes_v1 as common
import build_combined_idle_v6 as topology
import audit_character_art_v1 as audit

OUT=ROOT/'art/characters/keyframes-v3/keeper'
OLD=ROOT/'art/characters/keyframes-v2/keeper'
POSES=base.POSES;NAMES=base.NAMES
LEFT_EYES=[(12,18),(15,18)]
def dump(path,data):common.dump(path,data)

def register():
    source=Image.open(OUT/'source/generated-02.png').convert('RGBA')
    cells=[remove_alpha_specks(source.crop((round(i*source.width/3),0,round((i+1)*source.width/3),source.height))) for i in range(3)]
    factor=min(460/max(c.height for c in cells),318/max(c.width for c in cells));records=[]
    for name,cell in zip(POSES[1:4],cells):
        a=np.array(cell);_,xx=np.where(a[:round(cell.height*14/46),:,3]!=0);center=(int(xx.min())+int(xx.max())+1)/2
        fit=cell.resize((round(cell.width*factor),round(cell.height*factor)),Image.Resampling.NEAREST)
        x=max(0,min(round(155-center*factor),320-fit.width));y=470-fit.height
        canvas=Image.new('RGBA',(320,480));canvas.alpha_composite(fit,(x,y));native_grid(canvas,[32,48],0).save(OUT/'source'/f'{name}-registered.png')
        records.append({'id':name,'source_crop_size':list(cell.size),'uniform_scale':factor,'offset':[x,y],'entire_generated_body_used':True,'head_overlay':False,'facing':'left'})
    for name in ('idle','handover_extend','handover_return'):
        Image.open(OLD/'frames'/f'{name}.png').save(OUT/'source'/f'{name}-registered.png');records.append({'id':name,'source':f'art/characters/keyframes-v2/keeper/frames/{name}.png','entire_frame_retained':True,'facing':'right'})
    dump(OUT/'registration.json',{'uniform_scale_all_new_poses':factor,'old_face_hook_used':False,'old_head_overlay_used':False,'cross_pose_limb_splicing':False,'frames':records})

def manifest():
    edits=json.loads((OUT/'semantic-masks.json').read_text(encoding='utf-8')) if (OUT/'semantic-masks.json').exists() else {}
    assets=[]
    for name in POSES:
        assets.append({'id':name,'source':f'art/characters/keyframes-v3/keeper/source/{name}-registered.png','size':[32,48],'position':[0,0],'margin':0,'dark_value':.24,'preserve_native_frame':True,
            'materials':{'outline':[base.INK],'skin':[base.SKIN],'wood':[base.BROWN],'purple':[base.PURPLE],'gold':[base.GOLD]},
            'rules':[{'material':'skin','hue':[.025,.17],'saturation_max':.45,'value_min':.75},{'material':'gold','hue':[.075,.17],'saturation_min':.42,'value_min':.82},{'material':'wood','hue':[.025,.17],'saturation_min':.10,'value_max':.90}],
            'fallback_material':'purple',**edits.get(name,{})})
        if name.startswith('brew'):
            from process_pixel_art import material_remap
            ramp=json.loads((ROOT/'art/ramps.json').read_text(encoding='utf-8'));plain=dict(assets[-1]);plain.pop('material_pixels',None)
            im,_,_=material_remap(Image.open(OUT/'source'/f'{name}-registered.png').convert('RGBA'),plain,ramp);a=np.array(im);edge=common.boundary(a)
            pants=[[int(x),int(y)] for y,x in zip(*np.where(np.all(a[:,:,:3]==rgb(base.SKIN),axis=2)&(a[:,:,3]>0)&~edge)) if 38<=y<40]
            assets[-1].setdefault('material_pixels',[]).append({'material':'wood','pixels':pants,'reason':'The upper thigh38/39remains covered by brown shorts; knees begin in the shared leg band40.'})
    dump(OUT/'manifest.json',{'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,'scale':3,'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json','output':'art/characters/keyframes-v3/keeper/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':assets})

def process():
    register();manifest();p=subprocess.run([sys.executable,str(ROOT/'tools/process_pixel_art.py'),str((OUT/'manifest.json').relative_to(ROOT))],capture_output=True,text=True,encoding='utf-8')
    if p.returncode:raise ValueError(p.stdout+p.stderr)
    return {n:Image.open(OUT/'pipeline'/f'{n}-native.png').convert('RGBA') for n in POSES}

def board(frames,diagnostic=False):
    im=Image.new('RGBA',(504,466),base.INK);common.text(im,(18,12),'남자 주인공 · 왼쪽 제조 전신',22);common.text(im,(18,45),'32×48 · 승인5색 · 새 전신 · 기존 머리/팔 덧붙임 없음',12,'#C38EB5')
    for i,(n,label) in enumerate(zip(POSES,NAMES)):
        x,y=18+i%3*156,80+i//3*186;ImageDraw.Draw(im).rectangle((x,y,x+144,y+177),fill='#4A3C52',outline='#827589');common.text(im,(x+7,y+5),label,12);im.alpha_composite(frames[n].resize((96,144),Image.Resampling.NEAREST),(x+24,y+27))
    im.convert('RGB').save(OUT/('source/native-diagnostic.png' if diagnostic else 'keyframes-review.png'))

def skin_groups(im):
    a=np.array(im);mask=np.all(a[:,:,:3]==rgb(base.SKIN),axis=2)&(a[:,:,3]!=0);remaining=set(zip(*np.where(mask)));groups=[]
    while remaining:
        stack=[remaining.pop()];points=[]
        while stack:
            y,x=stack.pop();points.append((int(x),int(y)))
            for dy in (-1,0,1):
                for dx in (-1,0,1):
                    p=(y+dy,x+dx)
                    if p in remaining:remaining.remove(p);stack.append(p)
        xs,ys=zip(*points);groups.append({'pixels':points,'bounds':[min(xs),min(ys),max(xs)+1,max(ys)+1]})
    return sorted(groups,key=lambda g:(g['bounds'][1],g['bounds'][0]))

def diagnostic(frames):
    board(frames,True);chars={rgb(c):s for c,s in [(base.INK,'#'),(base.SKIN,'s'),(base.BROWN,'h'),(base.PURPLE,'p'),(base.GOLD,'G')]}
    for n in POSES[1:4]:
        a=np.array(frames[n]);print(n,[(g['bounds'],len(g['pixels'])) for g in skin_groups(frames[n])])
        for y in range(14,40):print(y,''.join(chars.get(tuple(p[:3]),'?') if p[3] else '.' for p in a[y]))

def finish(frames):
    anatomy=json.loads((OUT/'anatomy-masks.json').read_text(encoding='utf-8'));report={'status':'passed','character':'keeper','version':3,'frame_count':6,'old_head_overlay_used':False,'old_face_hook_used':False,'frames':{}}
    for n,im in frames.items():
        a=np.array(im);v=validate(im,[32,48],base.PALETTE,5);eyes=LEFT_EYES if n.startswith('brew') else audit.EYES['keeper']
        v.update(eyes=audit.eye_checks(im,'keeper',positions=eyes),outline_boundary_violations=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(base.INK),axis=2)).sum()),foot_row46=bool(a[46,:,3].any() and not a[47,:,3].any()),opaque_components=topology.count_components(a[:,:,3]!=0),facing='left' if n.startswith('brew') else 'right')
        if n.startswith('brew'):
            skin=np.all(a[:,:,:3]==rgb(base.SKIN),axis=2)&(a[:,:,3]>0);parts=[];assigned=np.zeros((48,32),bool)
            for part,rect in anatomy[n]['skin_regions'].items():
                x0,y0,x1,y1=rect;area=np.zeros((48,32),bool);area[y0:y1,x0:x1]=True;mask=skin&area&~assigned;assigned|=mask
                parts.append({'part':part,'region':rect,'skin_pixels':int(mask.sum()),'components8':len(skin_groups(Image.fromarray(np.where(mask[:,:,None],a,0).astype('uint8'))))})
            v['skin_parts']=parts;v['unassigned_skin_pixels']=int((skin&~assigned).sum())
            hands=[p for p in parts if p['part'].startswith('hand_')]
            v['two_hand_groups']=bool(len(hands)==2 and all(p['skin_pixels']>=4 and p['components8']==1 for p in hands) and not v['unassigned_skin_pixels'])
            samples=[]
            for y,x0,x1 in anatomy[n]['sleeve_sections']:
                row=a[y,x0:x1];opaque=int((row[:,3]>0).sum());purple=int((np.all(row[:,:3]==rgb(base.PURPLE),axis=1)&(row[:,3]>0)).sum());samples.append({'row':y,'columns':[x0,x1],'opaque_width':opaque,'purple_interior_pixels':purple,'passed':opaque>=4 and purple>=2})
            v['filled_sleeve_sections']=samples;v['sleeves_not_needlethin']=all(s['passed'] for s in samples)
        v['passed']=bool(v['passed'] and not v['outline_boundary_violations'] and v['foot_row46'] and v['opaque_components']==1 and all(e['isolated2'] and e['full_skin_halo1'] for e in v['eyes']) and v.get('two_hand_groups',True) and v.get('sleeves_not_needlethin',True))
        if not v['passed']:report['status']='failed'
        report['frames'][n]=v
    dump(OUT/'validation.json',report)
    if report['status']!='passed':raise ValueError('Anatomy/native checks failed; see validation.json')
    (OUT/'frames').mkdir(exist_ok=True);sheet=Image.new('RGBA',(96,96))
    for i,(n,im) in enumerate(frames.items()):im.save(OUT/'frames'/f'{n}.png');sheet.alpha_composite(im,(i%3*32,i//3*48))
    sheet.save(OUT/'keeper-keyframes-native.png');board(frames);print('keeper v3 passed6, two hand groups and filled sleeves')

def main():
    p=argparse.ArgumentParser();p.add_argument('--diagnostic',action='store_true');args=p.parse_args();frames=process()
    if args.diagnostic:diagnostic(frames)
    else:finish(frames)
if __name__=='__main__':main()
