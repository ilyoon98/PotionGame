"""Cat rogue coherent carry gait, approved five-color material pipeline."""
from __future__ import annotations
import argparse,subprocess,sys
import numpy as np
from PIL import Image,ImageDraw
from process_pixel_art import ROOT,native_grid,rgb,validate
import build_rogue_keyframes_v2 as rogue
import build_traveler_keyframes_v1 as common
import build_combined_idle_v6 as topology
OUT=ROOT/'art/characters/actions-v1/rogue';OLD=ROOT/'art/characters/keyframes-v2/rogue'
CARRY=['carry_contact_a','carry_pass_a','carry_contact_b','carry_pass_b'];POSES=common.POSES[:7]+CARRY
NAMES=common.NAMES[:7]+['병 들고 · 접지A','병 들고 · 통과A','병 들고 · 접지B','병 들고 · 통과B']
INK,SKIN,ORANGE,LIGHT,SCARF=rogue.INK,rogue.SKIN,rogue.ORANGE,rogue.LIGHT,rogue.SCARF
RGBA={k:(*rgb(c),255) for k,c in [('ink',INK),('skin',SKIN),('orange',ORANGE),('light',LIGHT),('scarf',SCARF)]}
PALETTE={rgb(c) for c in (ROOT/'art/palettes/v1/characters/rogue.hex').read_text(encoding='utf-8').splitlines() if c.strip()}
EYES=rogue.EYES
def read(p):return rogue.json.loads(p.read_text(encoding='utf-8'))
def dump(p,d):common.dump(p,d)

def register():
    records=[]
    for side,names in [('a',CARRY[:2]),('b',CARRY[2:])]:
        path=OUT/'source'/f'generated-carry-{side}-01.png';im=Image.open(path).convert('RGBA');cells=[rogue.remove_alpha_specks(im.crop((round(i*im.width/2),0,round((i+1)*im.width/2),im.height))) for i in range(2)];scale=(350 if side=='b' else 360)/max(c.height for c in cells)
        for n,c in zip(names,cells):
            a=np.array(c);_,xx=np.where(a[:round(c.height*16/36),:,3]>0);center=(int(xx.min())+int(xx.max())+1)/2;fit=c.resize((round(c.width*scale),round(c.height*scale)),Image.Resampling.NEAREST);x,y=round(155-center*scale),470-fit.height
            if x<0 or x+fit.width>320 or y<0:raise ValueError(f'Whole body leaves32x48:{n}')
            canvas=Image.new('RGBA',(320,480));canvas.alpha_composite(fit,(x,y));native_grid(canvas,[32,48],0).save(OUT/'source'/f'{n}-registered.png')
            records.append({'id':n,'source':'source/'+path.name,'cell':names.index(n),'uniform_source_sheet_scale':scale,'offset':[x,y],'whole_body':True,'cross_pose_limb_or_head_splicing':False})
    dump(OUT/'registration.json',{'head_center':15.5,'head_reference':[22,16],'foot_target_row':46,'frames':records})

def process(edits=True):
    masks=read(OUT/'semantic-masks.json') if edits and (OUT/'semantic-masks.json').exists() else {};assets=[]
    for n in CARRY:
        assets.append({'id':n,'source':f'art/characters/actions-v1/rogue/source/{n}-registered.png','size':[32,48],'position':[0,0],'margin':0,'dark_value':.40,'preserve_native_frame':True,
            'materials':{'outline':[INK],'skin':[SKIN],'hair_tail':[ORANGE,LIGHT],'scarf':[SCARF]},'material_ramps':{'hair_tail':'fire','scarf':'fire'},
            'rules':[{'material':'scarf','hue':[.94,1.0]},{'material':'skin','hue':[.025,.15],'saturation_max':.51,'value_min':.64}],
            'fallback_material':'hair_tail',**masks.get(n,{})})
    dump(OUT/'manifest.json',{'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,'scale':3,'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json','output':'art/characters/actions-v1/rogue/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':assets})
    p=subprocess.run([sys.executable,str(ROOT/'tools/process_pixel_art.py'),str((OUT/'manifest.json').relative_to(ROOT))],capture_output=True,text=True,encoding='utf-8')
    if p.returncode:raise ValueError(p.stdout+p.stderr)
    return {**{n:Image.open(OLD/'frames'/f'{n}.png').convert('RGBA') for n in common.POSES[:7]},**{n:Image.open(OUT/'pipeline'/f'{n}-native.png').convert('RGBA') for n in CARRY}}

def semantic_masks(frames):
    masks={}
    for n in CARRY:
        a=np.array(frames[n]);edge=common.boundary(a);skin=[];eyes=[]
        for x,y in EYES:
            eyes.extend([[x,y],[x,y+1]])
            for yy in range(y-1,y+3):
                for xx in range(x-1,x+2):
                    if edge[yy,xx] or not a[yy,xx,3]:raise ValueError(f'Eye halo outside face:{n}/{xx,yy}')
                    skin.append([xx,yy])
        masks[n]={'material_pixels':[{'material':'skin','pixels':skin,'reason':'Same two eyes and diagonal1px peach halo at approved rogue landmarks.'},{'material':'outline','pixels':eyes,'reason':'Same-height isolated1x2 pupils.'}]}
    dump(OUT/'semantic-masks.json',masks)

def board(frames,path):
    im=Image.new('RGBA',(648,648),INK);common.text(im,(18,12),'고양이 도적 · 입장부터 병 든 퇴장까지',22);common.text(im,(18,45),'원본32×48 · 공통3배 · 승인5색 · 주황 귀·꼬리 / 붉은 목도리 / 검은 옷',12,'#C38EB5')
    for i,n in enumerate(POSES):
        x,y=18+i%4*156,80+i//4*186;ImageDraw.Draw(im).rectangle((x,y,x+144,y+177),fill='#4A3C52',outline='#827589');common.text(im,(x+6,y+5),NAMES[i],12);im.alpha_composite(frames[n].resize((96,144),Image.Resampling.NEAREST),(x+24,y+27))
    im.convert('RGB').save(path)

def checks(frames):
    report={'status':'passed','native_size':[32,48],'palette_file':'art/palettes/v1/characters/rogue.hex','design_approval':'art/characters/keyframes-v2/rogue/approval.json','frame_count':11,'whole_body_sources':True,'runtime_integrated':False,'frames':{}}
    for n,im in frames.items():
        a=np.array(im);v=validate(im,[32,48],PALETTE,5);yy,xx=np.where(a[11:27,:,3]>0);holes=topology.enclosed_empty_pixels(a[:,:,3]>0)
        v.update(eyes=rogue.eye_checks(im),outline_boundary_violations=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum()),sole_row46=bool(a[46,:,3].any() and not a[47,:,3].any()),opaque_components=topology.count_components(a[:,:,3]>0),top11_rows_clear=not bool(a[:11,:,3].any()),head_fits22x16=bool(np.ptp(xx)+1<=22 and 14<=np.ptp(yy)+1<=16),neck_empty_pixels=int(holes[26:31,11:18].sum()),tail_loop_negative_space_allowed=True,torso_all13_rows_present=bool(a[27:40,:,3].any(axis=1).all()),legs_all7_rows_present=bool(a[40:47,:,3].any(axis=1).all()))
        if n in CARRY:
            skin=np.all(a==RGBA['skin'],axis=2);assigned=np.zeros((48,32),bool);parts={}
            for label,rect in [('carrying_glove_fingers',[5,31,10 if n=='carry_pass_b' else 9,34]),('other_glove_fingers',[15,35,21,39]),('head_and_inner_ears',[3,11,25,27]),('exposed_shoulders_arms',[8,27,21,35]),('midriff',[10,33,16,36]),('thighs',[7,39,23,44])]:
                x0,y0,x1,y1=rect;m=np.zeros((48,32),bool);m[y0:y1,x0:x1]=True;m&=skin&~assigned;assigned|=m;parts[label]={'region':rect,'skin_pixels':int(m.sum())}
            v.update(skin_parts=parts,unassigned_skin_pixels=int((skin&~assigned).sum()),two_gloved_hand_regions=all(parts[p]['skin_pixels']>=1 for p in ('carrying_glove_fingers','other_glove_fingers')) and not bool((skin&~assigned).any()))
        v['passed']=bool(v['passed'] and not v['outline_boundary_violations'] and v['sole_row46'] and v['opaque_components']==1 and v['top11_rows_clear'] and v['head_fits22x16'] and not v['neck_empty_pixels'] and v['torso_all13_rows_present'] and v['legs_all7_rows_present'] and v.get('two_gloved_hand_regions',True) and all(e['isolated_dark_pixels2'] and e['skin_halo1_with_diagonals'] for e in v['eyes']))
        if not v['passed']:report['status']='failed'
        report['frames'][n]=v
    gait={}
    for n in CARRY:
        a=np.array(frames[n]);gait[n]={'left_ground':bool(a[46,:13,3].any()),'right_ground':bool(a[46,16:,3].any())}
    report['carry_support_feet']=gait;report['opposite_passing_support']=not gait[CARRY[1]]['left_ground'] and gait[CARRY[1]]['right_ground'] and gait[CARRY[3]]['left_ground'] and not gait[CARRY[3]]['right_ground']
    report['both_contact_feet_ground']=all(all(gait[n].values()) for n in (CARRY[0],CARRY[2]))
    if not report['opposite_passing_support'] or not report['both_contact_feet_ground']:report['status']='failed'
    for aa,bb in [(CARRY[0],CARRY[2]),(CARRY[1],CARRY[3])]:
        if np.array_equal(np.array(frames[aa])[40:],np.array(frames[bb])[40:]):raise ValueError('Opposite gait duplicated')
    dump(OUT/'native-validation.json',report)
    if report['status']!='passed':print({n:v for n,v in report['frames'].items() if not v['passed']});print(gait);raise ValueError('Rogue native validation failed')
    (OUT/'frames').mkdir(exist_ok=True);sheet=Image.new('RGBA',(128,144))
    for i,n in enumerate(POSES):frames[n].save(OUT/'frames'/f'{n}.png');sheet.alpha_composite(frames[n],(i%4*32,i//4*48))
    sheet.save(OUT/'rogue-actions-native.png');board(frames,OUT/'keyframes-review.png')

def main():
    p=argparse.ArgumentParser();p.add_argument('--diagnostic',action='store_true');args=p.parse_args();register();frames=process(False)
    if args.diagnostic:
        board(frames,OUT/'source/native-diagnostic.png');symbols={v:s for v,s in [(RGBA['ink'],'#'),(RGBA['skin'],'s'),(RGBA['orange'],'o'),(RGBA['light'],'L'),(RGBA['scarf'],'r')]}
        for n in CARRY:
            print(n);a=np.array(frames[n])
            for y in range(11,48):print(y,''.join(symbols.get(tuple(p),'?') if p[3] else '.' for p in a[y]))
        return
    semantic_masks(frames);frames=process();checks(frames);print('Rogue11native poses passed')

if __name__=='__main__':main()
