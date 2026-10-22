"""Traveler action candidate, preserving existing keyposes and whole-body carry variants."""
from __future__ import annotations
import argparse,hashlib,json,math,shutil,subprocess,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from process_pixel_art import ROOT,native_grid,rgb,validate
from build_rogue_keyframes_v2 import remove_alpha_specks
import build_traveler_keyframes_v1 as common
import build_secondary_motion_v5 as secondary
import build_combined_idle_v6 as topology
from prepare_character_v6 import dark_component

OUT=ROOT/'art/characters/actions-v1/traveler';OLD=ROOT/'art/characters/keyframes-v1/traveler'
CARRY=['carry_contact_a','carry_pass_a','carry_contact_b','carry_pass_b']
POSES=common.POSES[:7]+CARRY
NAMES=common.NAMES[:7]+['병 들고 · 접지A','병 들고 · 통과A','병 들고 · 접지B','병 들고 · 통과B']
INK,SKIN,SHIRT,BROWN,HONEY=common.INK,common.SKIN,common.SHIRT,common.BROWN,common.HONEY
PALETTE={rgb(c) for c in (ROOT/'art/palettes/v1/characters/traveler.hex').read_text(encoding='utf-8').splitlines() if c.strip()}
EYES=[(10,22),(14,22)]
RGBA={key:(*rgb(c),255) for key,c in [('ink',INK),('skin',SKIN),('shirt',SHIRT),('brown',BROWN),('honey',HONEY)]}
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def dump(p,d):common.dump(p,d)

def register():
    source=Image.open(OUT/'source/generated-carry-01.png').convert('RGBA')
    cells=[remove_alpha_specks(source.crop((round(i*source.width/4),0,round((i+1)*source.width/4),source.height))) for i in range(4)]
    scale=360/max(c.height for c in cells);records=[]
    for n,cell in zip(CARRY,cells):
        a=np.array(cell);_,xx=np.where(a[:round(cell.height*.24),:,3]>0);center=(int(xx.min())+int(xx.max())+1)/2
        fit=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
        x,y=round(140-center*scale),110
        if x<0 or x+fit.width>320 or y+fit.height>470:raise ValueError('Coherent carry body leaves32x48')
        canvas=Image.new('RGBA',(320,480));canvas.alpha_composite(fit,(x,y));native_grid(canvas,[32,48],0).save(OUT/'source'/f'{n}-registered.png')
        records.append({'id':n,'whole_body':True,'uniform_scale':scale,'offset':[x,y],'crop_size':list(cell.size),'cross_pose_body_splicing':False})
    dump(OUT/'registration.json',{'source_grid':[4,1],'head_top_row':11,'sole_target_row':46,'frames':records})

def process(edits=True):
    masks=read(OUT/'semantic-masks.json') if edits and (OUT/'semantic-masks.json').exists() else {}
    assets=[]
    for n in CARRY:
        assets.append({'id':n,'source':f'art/characters/actions-v1/traveler/source/{n}-registered.png','size':[32,48],'position':[0,0],'margin':0,'dark_value':.27,'preserve_native_frame':True,
            'materials':{'outline':[INK],'skin':[SKIN],'shirt':[SHIRT],'hair_leather':[BROWN],'wood_light':[HONEY]},
            'material_ramps':{'shirt':'gold','hair_leather':'wood','wood_light':'wood'},
            'rules':[{'material':'shirt','hue':[.105,.22],'value_min':.80,'saturation_max':.44},
                     {'material':'skin','hue':[.025,.105],'value_min':.76,'saturation_min':.15,'saturation_max':.40},
                     {'material':'wood_light','hue':[.025,.16],'value_min':.65,'saturation_min':.40}],
            'fallback_material':'hair_leather',**masks.get(n,{})})
    manifest={'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,'scale':3,'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json','output':'art/characters/actions-v1/traveler/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':assets}
    dump(OUT/'manifest.json',manifest)
    p=subprocess.run([sys.executable,str(ROOT/'tools/process_pixel_art.py'),str((OUT/'manifest.json').relative_to(ROOT))],capture_output=True,text=True,encoding='utf-8')
    if p.returncode:raise ValueError(p.stdout+p.stderr)
    frames={n:Image.open(OLD/'frames'/f'{n}.png').convert('RGBA') for n in common.POSES[:7]}
    frames.update({n:Image.open(OUT/'pipeline'/f'{n}-native.png').convert('RGBA') for n in CARRY});return frames

def eye_masks(frames):
    masks={}
    for n in CARRY:
        a=np.array(frames[n]);border=common.boundary(a);skin=[];pupils=[]
        for x,y in EYES:
            pupils.extend([[x,y],[x,y+1]])
            for yy in range(y-1,y+3):
                for xx in range(x-1,x+2):
                    if border[yy,xx] or not a[yy,xx,3]:raise ValueError(f'Carry eye halo out of face: {n}/{xx,yy}')
                    skin.append([xx,yy])
        masks[n]={'material_pixels':[{'material':'skin','pixels':skin,'reason':'Retain two equal eyes with one-pixel skin halo on the existing approved native eye landmarks.'},{'material':'outline','pixels':pupils,'reason':'Two1x2eyes on same row; no hair-connected third pixel.'}]}
    dump(OUT/'semantic-masks.json',masks)

def board(frames,path):
    im=Image.new('RGBA',(648,648),INK);common.text(im,(18,12),'여행자 · 입장부터 병 든 퇴장까지',22);common.text(im,(18,45),'원본32×48 · 공통3배 · 지정5색 · 기존 전신 + 새 병 들기4포즈',12,'#C38EB5')
    for i,n in enumerate(POSES):
        x,y=18+i%4*156,80+i//4*186;ImageDraw.Draw(im).rectangle((x,y,x+144,y+177),fill='#4A3C52',outline='#827589');common.text(im,(x+6,y+5),NAMES[i],12);im.alpha_composite(frames[n].resize((96,144),Image.Resampling.NEAREST),(x+24,y+27))
    im.convert('RGB').save(path)

def diagnostic(frames):
    board(frames,OUT/'source/native-diagnostic.png');chars={rgb(c):s for c,s in [(INK,'#'),(SKIN,'s'),(SHIRT,'c'),(BROWN,'h'),(HONEY,'w')]}
    for n in CARRY:
        a=np.array(frames[n]);print(n)
        for y in range(19,48):print(y,''.join(chars.get(tuple(p[:3]),'?') if p[3] else '.' for p in a[y]))

def native_checks(frames):
    report={'status':'passed','date':'2026-10-15','native_size':[32,48],'palette_file':'art/palettes/v1/characters/traveler.hex','frame_count':len(frames),'whole_body_sources':True,'runtime_integrated':False,'frames':{}}
    for n,im in frames.items():
        a=np.array(im);v=validate(im,[32,48],PALETTE,5)
        eyes=common.eyes(im)
        v.update(eyes=eyes,outline_boundary_violations=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum()),top11_rows_clear=not bool(a[:11,:,3].any()),sole_row46=bool(a[46,:,3].any() and not a[47,:,3].any()),opaque_components=topology.count_components(a[:,:,3]>0))
        head=(a[:,:,3]>0).copy();head[:11]=False;head[27:]=False;head[21:27,23:]=False
        yy,xx=np.where(head);width=int(xx.max()-xx.min()+1);height=int(yy.max()-yy.min()+1)
        v['anatomy']={'head_reference':[22,16],'head_without_backpack_bbox':[int(xx.min()),int(yy.min()),int(xx.max()+1),int(yy.max()+1)],'head_width':width,'head_height':height,'torso_rows':[27,39],'torso_all13_rows_present':bool(a[27:40,:,3].any(axis=1).all()),'leg_boot_rows':[40,46],'legs_all7_rows_present':bool(a[40:47,:,3].any(axis=1).all()),'lifted_walking_knee_in_torso_band_allowed':n.startswith(('walk_','carry_'))}
        if n in CARRY:
            skin=np.all(a==RGBA['skin'],axis=2);assigned=np.zeros((48,32),bool);parts={}
            for name,rect in [('carrying_palm',[6,29,13,35]),('other_palm',[19,31,27,38]),('head_neck',[3,11,25,28]),('knees',[6,36,23,44])]:
                x0,y0,x1,y1=rect;m=np.zeros((48,32),bool);m[y0:y1,x0:x1]=True;m&=skin&~assigned;assigned|=m;parts[name]={'region':rect,'skin_pixels':int(m.sum())}
                if name in ('carrying_palm','other_palm'):
                    remaining=set(zip(*np.where(m)));groups=0
                    while remaining:
                        groups+=1;stack=[remaining.pop()]
                        while stack:
                            yy,xx=stack.pop()
                            for dy in (-1,0,1):
                                for dx in (-1,0,1):
                                    point=(yy+dy,xx+dx)
                                    if point in remaining:remaining.remove(point);stack.append(point)
                    parts[name]['connected_palm_groups8']=groups
            v['skin_parts']=parts;v['unassigned_skin_pixels']=int((skin&~assigned).sum());v['exactly_two_palm_regions']=bool(all(parts[p]['skin_pixels']>=4 and parts[p]['connected_palm_groups8']==1 for p in ('carrying_palm','other_palm')) and not v['unassigned_skin_pixels'])
        v['passed']=bool(v['passed'] and not v['outline_boundary_violations'] and v['top11_rows_clear'] and v['sole_row46'] and v['opaque_components']==1 and width<=22 and height<=16 and v['anatomy']['torso_all13_rows_present'] and v['anatomy']['legs_all7_rows_present'] and v.get('exactly_two_palm_regions',True))
        if not v['passed']:report['status']='failed'
        report['frames'][n]=v
    for a,p,bb,q in [('walk_contact_a','walk_pass_a','walk_contact_b','walk_pass_b'),*[(CARRY[0],CARRY[1],CARRY[2],CARRY[3])]]:
        if np.array_equal(np.array(frames[a])[35:],np.array(frames[bb])[35:]):raise ValueError('Opposite contact phases cannot be the same lower body')
        if np.array_equal(np.array(frames[p])[35:],np.array(frames[q])[35:]):raise ValueError('Opposite passing phases cannot be the same lower body')
    dump(OUT/'native-validation.json',report)
    if report['status']!='passed':raise ValueError('Native traveler validation failed')
    (OUT/'frames').mkdir(exist_ok=True);sheet=Image.new('RGBA',(128,144))
    for i,n in enumerate(POSES):frames[n].save(OUT/'frames'/f'{n}.png');sheet.alpha_composite(frames[n],(i%4*32,i//4*48))
    sheet.save(OUT/'traveler-actions-native.png');board(frames,OUT/'keyframes-review.png')
    return report

def main():
    p=argparse.ArgumentParser();p.add_argument('--diagnostic',action='store_true');args=p.parse_args()
    register();frames=process(False)
    if args.diagnostic:diagnostic(frames);return
    eye_masks(frames);frames=process();native_checks(frames)
    print('traveler action native11poses passed')

if __name__=='__main__':main()
