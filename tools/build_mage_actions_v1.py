"""Mage whole-body carry poses, material pipeline, and seated original hat."""
from __future__ import annotations
import argparse,subprocess,sys
import numpy as np
from PIL import Image,ImageDraw
from process_pixel_art import ROOT,native_grid,rgb,validate
from build_rogue_keyframes_v2 import remove_alpha_specks
import build_traveler_keyframes_v1 as common
import build_combined_idle_v6 as topology
import build_mage_keyframes_v1 as mage

OUT=ROOT/'art/characters/actions-v1/mage';OLD=ROOT/'art/characters/keyframes-v1/mage'
CARRY=['carry_contact_a','carry_pass_a','carry_contact_b','carry_pass_b']
POSES=common.POSES[:7]+CARRY
NAMES=common.NAMES[:7]+['병 들고 · 접지A','병 들고 · 통과A','병 들고 · 접지B','병 들고 · 통과B']
INK,SKIN,DARK,PURPLE,BROWN=mage.INK,mage.SKIN,mage.DARK,mage.PURPLE,mage.BROWN
RGBA={key:(*rgb(c),255) for key,c in [('ink',INK),('skin',SKIN),('dark',DARK),('purple',PURPLE),('brown',BROWN)]}
PALETTE={rgb(c) for c in (ROOT/'art/palettes/v1/characters/mage.hex').read_text(encoding='utf-8').splitlines() if c.strip()}
EYES=[(10,22),(14,22)]
def read(p):return common.json.loads(p.read_text(encoding='utf-8'))
def dump(p,d):common.dump(p,d)

def register():
    source=Image.open(OUT/'source/generated-carry-01.png').convert('RGBA')
    cells=[remove_alpha_specks(source.crop((round(i*source.width/4),0,round((i+1)*source.width/4),source.height))) for i in range(4)]
    scale=360/max(c.height for c in cells);records=[]
    for n,cell in zip(CARRY,cells):
        a=np.array(cell);_,xx=np.where(a[:round(cell.height*.24),:,3]>0);center=(int(xx.min())+int(xx.max())+1)/2
        fit=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST);x,y=round(140-center*scale),110
        if x<0 or x+fit.width>320 or y+fit.height>470:raise ValueError('Coherent carry body leaves32x48')
        canvas=Image.new('RGBA',(320,480));canvas.alpha_composite(fit,(x,y));native_grid(canvas,[32,48],0).save(OUT/'source'/f'{n}-registered.png')
        records.append({'id':n,'whole_body':True,'uniform_scale':scale,'offset':[x,y],'crop_size':list(cell.size),'cross_pose_body_splicing':False})
    dump(OUT/'registration.json',{'source_grid':[4,1],'head_top_row':11,'sole_target_row':46,'hat_origin':[0,4],'hat_head_anchor':[14,14],'hat_local_seat':[14,10],'frames':records})

def process(edits=True):
    masks=read(OUT/'semantic-masks.json') if edits and (OUT/'semantic-masks.json').exists() else {};assets=[]
    for n in CARRY:
        assets.append({'id':n,'source':f'art/characters/actions-v1/mage/source/{n}-registered.png','size':[32,48],'position':[0,0],'margin':0,'dark_value':.20,'preserve_native_frame':True,
            'materials':{'outline':[INK],'skin':[SKIN],'purple':[DARK,PURPLE],'wood':[BROWN]},
            'rules':[{'material':'skin','hue':[.025,.16],'value_min':.76,'saturation_max':.5},{'material':'wood','hue':[.025,.18],'saturation_min':.22,'value_max':.88}],
            'fallback_material':'purple',**masks.get(n,{})})
    dump(OUT/'manifest.json',{'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,'scale':3,'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json','output':'art/characters/actions-v1/mage/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':assets})
    p=subprocess.run([sys.executable,str(ROOT/'tools/process_pixel_art.py'),str((OUT/'manifest.json').relative_to(ROOT))],capture_output=True,text=True,encoding='utf-8')
    if p.returncode:raise ValueError(p.stdout+p.stderr)
    return {n:Image.open(OUT/'pipeline'/f'{n}-native.png').convert('RGBA') for n in CARRY}

def eye_masks(frames):
    masks={}
    for n in CARRY:
        a=np.array(frames[n]);border=common.boundary(a);skin=[];pupils=[]
        for x,y in EYES:
            pupils.extend([[x,y],[x,y+1]])
            for yy in range(y-1,y+3):
                for xx in range(x-1,x+2):
                    if border[yy,xx] or not a[yy,xx,3]:raise ValueError(f'Eye halo outside face:{n}/{xx,yy}')
                    skin.append([xx,yy])
        masks[n]={'material_pixels':[{'material':'skin','pixels':skin,'reason':'Equal eyes and full1px skin halo at existing mage landmarks.'},{'material':'outline','pixels':pupils,'reason':'Two equal isolated1x2 pupils.'}]}
    dump(OUT/'semantic-masks.json',masks)

def board(frames,path):
    im=Image.new('RGBA',(648,648),INK);common.text(im,(18,12),'여마법사 · 입장부터 병 든 퇴장까지',22);common.text(im,(18,45),'원본32×48 · 공통3배 · 지정5색 · 모자 착용점[14,14] 유지',12,'#C38EB5')
    for i,n in enumerate(POSES):
        x,y=18+i%4*156,80+i//4*186;ImageDraw.Draw(im).rectangle((x,y,x+144,y+177),fill='#4A3C52',outline='#827589');common.text(im,(x+6,y+5),NAMES[i],12);im.alpha_composite(frames[n].resize((96,144),Image.Resampling.NEAREST),(x+24,y+27))
    im.convert('RGB').save(path)

def checks(frames,bodies,hat):
    hm=np.zeros((48,32),bool);hm[4:18]=np.array(hat)[:,:,3]>0
    report={'status':'passed','native_size':[32,48],'palette_file':'art/palettes/v1/characters/mage.hex','frame_count':len(frames),'whole_body_sources':True,'hat_original_unchanged':True,'hat_origin':[0,4],'hat_head_seat':[14,14],'runtime_integrated':False,'frames':{}}
    for n,im in frames.items():
        a=np.array(im);body=np.array(bodies[n]);v=validate(im,[32,48],PALETTE,5)
        overlap=hm&(body[:,:,3]>0);crown=int(overlap[11:18,8:20].sum())
        v.update(eyes=common.eyes(im),outline_boundary_violations=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum()),sole_row46=bool(a[46,:,3].any() and not a[47,:,3].any()),opaque_components=topology.count_components(a[:,:,3]>0),hat_seat_touches_crown=bool(overlap[14,14]),hat_crown_overlap_pixels=crown,hat_crown_overlap_sufficient=crown>=40,body_top11_clear=not bool(body[:11,:,3].any()),head_crown_fits22=not bool(body[11:21,:3,3].any() or body[11:21,25:,3].any()),torso_all13_rows_present=bool(a[27:40,:,3].any(axis=1).all()),legs_all7_rows_present=bool(a[40:47,:,3].any(axis=1).all()))
        if n in CARRY:
            skin=np.all(a==RGBA['skin'],axis=2);assigned=np.zeros((48,32),bool);parts={}
            for label,rect in [('carrying_palm',[5,28,13,35]),('other_palm',[18,31,25,38]),('head_neck',[3,11,25,28]),('knees',[6,35,24,44])]:
                x0,y0,x1,y1=rect;m=np.zeros((48,32),bool);m[y0:y1,x0:x1]=True;m&=skin&~assigned;assigned|=m;parts[label]={'region':rect,'skin_pixels':int(m.sum()),'groups':topology.count_components(m)}
            v.update(skin_parts=parts,unassigned_skin_pixels=int((skin&~assigned).sum()),exactly_two_palm_regions=all(parts[p]['skin_pixels']>=4 and parts[p]['groups']==1 for p in ('carrying_palm','other_palm')) and not bool((skin&~assigned).any()))
        v['passed']=bool(v['passed'] and not v['outline_boundary_violations'] and v['sole_row46'] and v['opaque_components']==1 and v['hat_seat_touches_crown'] and v['hat_crown_overlap_sufficient'] and v['body_top11_clear'] and v['head_crown_fits22'] and v['torso_all13_rows_present'] and v['legs_all7_rows_present'] and v.get('exactly_two_palm_regions',True))
        if not v['passed']:report['status']='failed'
        report['frames'][n]=v
    for a,p,bb,q in [('walk_contact_a','walk_pass_a','walk_contact_b','walk_pass_b'),CARRY]:
        for x,y in [(a,bb),(p,q)]:
            if np.array_equal(np.array(frames[x])[35:],np.array(frames[y])[35:]):raise ValueError('Opposite walk phases must differ')
    dump(OUT/'native-validation.json',report)
    if report['status']!='passed':
        print({n:v for n,v in report['frames'].items() if not v['passed']});raise ValueError('Mage native validation failed')
    for folder in ['frames','body-frames','layers']:(OUT/folder).mkdir(exist_ok=True)
    hat.save(OUT/'layers/hat.png');sheet=Image.new('RGBA',(128,144))
    for i,n in enumerate(POSES):frames[n].save(OUT/'frames'/f'{n}.png');bodies[n].save(OUT/'body-frames'/f'{n}.png');sheet.alpha_composite(frames[n],(i%4*32,i//4*48))
    sheet.save(OUT/'mage-actions-native.png');board(frames,OUT/'keyframes-review.png')

def main():
    p=argparse.ArgumentParser();p.add_argument('--diagnostic',action='store_true');args=p.parse_args()
    register();bodies=process(False)
    if not args.diagnostic:eye_masks(bodies);bodies=process()
    bodies={**{n:Image.open(OLD/'body-frames'/f'{n}.png').convert('RGBA') for n in common.POSES[:7]},**bodies}
    hat=Image.open(OLD/'layers/hat.png').convert('RGBA');frames={}
    for n,body in bodies.items():frames[n]=body.copy();frames[n].alpha_composite(hat,(0,4))
    if args.diagnostic:
        board(frames,OUT/'source/native-diagnostic.png');symbols={v:s for v,s in [(RGBA['ink'],'#'),(RGBA['skin'],'s'),(RGBA['purple'],'p'),(RGBA['dark'],'d'),(RGBA['brown'],'b')]}
        for n in CARRY:
            print(n);a=np.array(frames[n])
            for y in range(18,48):print(y,''.join(symbols.get(tuple(p),'?') if p[3] else '.' for p in a[y]))
        return
    checks(frames,bodies,hat);print('Mage11native poses passed with original seated hat')

if __name__=='__main__':main()
