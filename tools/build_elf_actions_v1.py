"""Approved leaf-scout whole-body carry gait and native material validation."""
from __future__ import annotations
import argparse,subprocess,sys
import numpy as np
from PIL import Image,ImageDraw
from process_pixel_art import ROOT,native_grid,rgb,validate
from build_rogue_keyframes_v2 import remove_alpha_specks
import build_traveler_keyframes_v1 as common
import build_elf_keyframes_v2 as elf
import build_combined_idle_v6 as topology
OUT=ROOT/'art/characters/actions-v1/elf';OLD=ROOT/'art/characters/keyframes-v2/elf'
CARRY=['carry_contact_a','carry_pass_a','carry_contact_b','carry_pass_b'];POSES=common.POSES[:7]+CARRY
NAMES=common.NAMES[:7]+['병 들고 · 접지A','병 들고 · 통과A','병 들고 · 접지B','병 들고 · 통과B']
INK,SKIN,BROWN,GREEN,LIME=elf.INK,elf.SKIN,elf.BROWN,elf.GREEN,elf.LIME
RGBA={k:(*rgb(c),255) for k,c in [('ink',INK),('skin',SKIN),('brown',BROWN),('green',GREEN),('lime',LIME)]}
PALETTE={rgb(c) for c in (ROOT/'art/palettes/v1/characters/elf.hex').read_text(encoding='utf-8').splitlines() if c.strip()}
EYES=[(11,22),(16,22)]
def read(p):return elf.json.loads(p.read_text(encoding='utf-8'))
def dump(p,d):common.dump(p,d)

def register():
    sources={};factors={}
    for name,count in [('generated-carry-01.png',4),('generated-opposite-gait-01.png',2),('generated-passing-b-01.png',1)]:
        im=Image.open(OUT/'source'/name).convert('RGBA');cells=[remove_alpha_specks(im.crop((round(i*im.width/count),0,round((i+1)*im.width/count),im.height))) for i in range(count)]
        sources[name]=cells;factors[name]=360/max(c.height for c in cells)
    selection=[('generated-carry-01.png',0),('generated-opposite-gait-01.png',1),('generated-opposite-gait-01.png',0),('generated-passing-b-01.png',0)];records=[]
    for n,(source,cell_id) in zip(CARRY,selection):
        cell=sources[source][cell_id];scale=factors[source];a=np.array(cell);_,xx=np.where(a[:round(cell.height*16/36),:,3]>0);center=(int(xx.min())+int(xx.max())+1)/2
        fit=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST);x,y=round(155-center*scale),110
        if n=='carry_pass_b':x+=4;y+=1
        if x<0 or x+fit.width>320 or y+fit.height>475:raise ValueError('Whole-body carry pose leaves32x48')
        canvas=Image.new('RGBA',(320,480));canvas.alpha_composite(fit,(x,y));native_grid(canvas,[32,48],0).save(OUT/'source'/f'{n}-registered.png')
        records.append({'id':n,'source':source,'cell':cell_id,'uniform_scale_for_source_sheet':scale,'offset':[x,y],'whole_body':True,'cross_pose_body_splicing':False})
    dump(OUT/'registration.json',{'head_top_row':11,'sole_target_row':46,'head_center':15.5,'normalization':'Uniform whole-body scale per generated source sheet; no separate head/torso/leg scaling.','frames':records})

def process(edits=True):
    masks=read(OUT/'semantic-masks.json') if edits and (OUT/'semantic-masks.json').exists() else {};assets=[]
    for n in CARRY:
        assets.append({'id':n,'source':f'art/characters/actions-v1/elf/source/{n}-registered.png','size':[32,48],'position':[0,0],'margin':0,'dark_value':.27,'preserve_native_frame':True,
            'materials':{'outline':[INK],'skin':[SKIN],'hair_leather':[BROWN],'leaf':[GREEN,LIME]},'material_ramps':{'hair_leather':'wood'},
            'rules':[{'material':'skin','hue':[.025,.15],'saturation_min':.12,'saturation_max':.52,'value_min':.73},{'material':'hair_leather','hue':[.025,.16],'saturation_min':.05,'value_max':.90}],
            'fallback_material':'leaf',**masks.get(n,{})})
    dump(OUT/'manifest.json',{'schema_version':1,'status':'candidate','approved_by_user':False,'compose':False,'scale':3,'alpha_threshold':224,'max_colors':5,'palette':'art/palette.hex','ramps':'art/ramps.json','output':'art/characters/actions-v1/elf/pipeline','scene':{'size':[32,48],'background':'#4A3C52'},'assets':assets})
    p=subprocess.run([sys.executable,str(ROOT/'tools/process_pixel_art.py'),str((OUT/'manifest.json').relative_to(ROOT))],capture_output=True,text=True,encoding='utf-8')
    if p.returncode:raise ValueError(p.stdout+p.stderr)
    return {**{n:Image.open(OLD/'frames'/f'{n}.png').convert('RGBA') for n in common.POSES[:7]},**{n:Image.open(OUT/'pipeline'/f'{n}-native.png').convert('RGBA') for n in CARRY}}

def semantic_masks(frames):
    masks={}
    for n in CARRY:
        a=np.array(frames[n]);border=common.boundary(a);skin=[];pupils=[]
        for x,y in EYES:
            pupils.extend([[x,y],[x,y+1]])
            for yy in range(y-1,y+3):
                for xx in range(x-1,x+2):
                    if border[yy,xx] or not a[yy,xx,3]:raise ValueError(f'Eye halo outside face:{n}/{xx,yy}')
                    skin.append([xx,yy])
        masks[n]={'material_pixels':[{'material':'skin','pixels':skin,'reason':'Preserve two equal eyes and1px skin halo at approved elf landmarks.'},{'material':'outline','pixels':pupils,'reason':'Two isolated1x2 pupils on the same row.'}]}
        if n in ('carry_pass_a','carry_contact_b'):
            masks[n]['background_alpha_rectangles']=[{'rect':[23,37,24,38],'reason':'Trim one hanging-wrist boundary excess at shorts height; preserve the actual palm and rebuild its one-pixel outline in the material pipeline.'}]
    dump(OUT/'semantic-masks.json',masks)

def board(frames,path):
    im=Image.new('RGBA',(648,648),INK);common.text(im,(18,12),'엘프 · 잎 정찰복 행동 애니메이션',22);common.text(im,(18,45),'원본32×48 · 공통3배 · 지정5색 · 승인된 새 의상 유지',12,'#C38EB5')
    for i,n in enumerate(POSES):
        x,y=18+i%4*156,80+i//4*186;ImageDraw.Draw(im).rectangle((x,y,x+144,y+177),fill='#4A3C52',outline='#827589');common.text(im,(x+6,y+5),NAMES[i],12);im.alpha_composite(frames[n].resize((96,144),Image.Resampling.NEAREST),(x+24,y+27))
    im.convert('RGB').save(path)

def checks(frames):
    report={'status':'passed','native_size':[32,48],'palette_file':'art/palettes/v1/characters/elf.hex','approved_design':'art/characters/elf-redesign-v2/approval.json','frame_count':len(frames),'whole_body_sources':True,'runtime_integrated':False,'frames':{}}
    for n,im in frames.items():
        a=np.array(im);v=validate(im,[32,48],PALETTE,5);yy,xx=np.where(a[11:27,:,3]>0)
        widths=[int(np.ptp(np.where(a[y,:,3]>0)[0])+1) for y in range(37,40)]
        v.update(eyes=elf.eyes(im),outline_boundary_violations=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum()),sole_row46=bool(a[46,:,3].any() and not a[47,:,3].any()),opaque_components=topology.count_components(a[:,:,3]>0),top11_rows_clear=not bool(a[:11,:,3].any()),head_fits22x16=bool(np.ptp(xx)+1<=22 and np.ptp(yy)+1==16),shorts_hem_widths=widths,shorts_width10_to12=all(10<=w<=12 for w in widths),torso_all13_rows_present=bool(a[27:40,:,3].any(axis=1).all()),legs_all7_rows_present=bool(a[40:47,:,3].any(axis=1).all()))
        if n in CARRY:
            skin=np.all(a==RGBA['skin'],axis=2);parts={};assigned=np.zeros((48,32),bool)
            palm=[9,31,12,33] if n=='carry_contact_a' else [8,32,11,34] if n!='carry_pass_b' else [9,33,12,35]
            other=[21,35,24,37] if n=='carry_contact_a' else [21,36,24,38] if n!='carry_pass_b' else [20,35,23,38]
            for label,rect in [('carrying_palm',palm),('other_palm',other),('head_neck_shoulder',[3,11,28,31]),('bare_arms',[10,29,22,35]),('midriff',[10,34,22,36]),('knees',[7,39,25,45])]:
                x0,y0,x1,y1=rect;m=np.zeros((48,32),bool);m[y0:y1,x0:x1]=True;m&=skin&~assigned;assigned|=m;parts[label]={'region':rect,'skin_pixels':int(m.sum()),'groups':topology.count_components(m)}
            v.update(skin_parts=parts,unassigned_skin_pixels=int((skin&~assigned).sum()),exactly_two_palm_regions=all(parts[p]['skin_pixels']>=3 and parts[p]['groups']==1 for p in ('carrying_palm','other_palm')) and not bool((skin&~assigned).any()))
        v['passed']=bool(v['passed'] and not v['outline_boundary_violations'] and v['sole_row46'] and v['opaque_components']==1 and v['top11_rows_clear'] and v['head_fits22x16'] and v['shorts_width10_to12'] and v['torso_all13_rows_present'] and v['legs_all7_rows_present'] and v.get('exactly_two_palm_regions',True) and all(e['isolated_dark_pixels2'] and e['skin_halo1_with_diagonals'] for e in v['eyes']))
        if not v['passed']:report['status']='failed'
        report['frames'][n]=v
    gait={}
    for n in CARRY:
        a=np.array(frames[n]);gait[n]={'left_ground':bool(a[46,7:15,3].any()),'right_ground':bool(a[46,18:27,3].any())}
    report['carry_support_feet']=gait
    report['opposite_passing_support']=gait['carry_pass_a']['right_ground'] and not gait['carry_pass_a']['left_ground'] and gait['carry_pass_b']['left_ground'] and not gait['carry_pass_b']['right_ground']
    if not report['opposite_passing_support']:report['status']='failed'
    for aa,bb in [(CARRY[0],CARRY[2]),(CARRY[1],CARRY[3])]:
        if np.array_equal(np.array(frames[aa])[37:],np.array(frames[bb])[37:]):raise ValueError('Duplicate opposite leg phases')
    dump(OUT/'native-validation.json',report)
    if report['status']!='passed':print({n:v for n,v in report['frames'].items() if not v['passed']});print(gait);raise ValueError('Elf native validation failed')
    (OUT/'frames').mkdir(exist_ok=True);sheet=Image.new('RGBA',(128,144))
    for i,n in enumerate(POSES):frames[n].save(OUT/'frames'/f'{n}.png');sheet.alpha_composite(frames[n],(i%4*32,i//4*48))
    sheet.save(OUT/'elf-actions-native.png');board(frames,OUT/'keyframes-review.png')

def main():
    p=argparse.ArgumentParser();p.add_argument('--diagnostic',action='store_true');args=p.parse_args();register();frames=process(False)
    if args.diagnostic:
        board(frames,OUT/'source/native-diagnostic.png');symbols={v:s for v,s in [(RGBA['ink'],'#'),(RGBA['skin'],'s'),(RGBA['brown'],'b'),(RGBA['green'],'g'),(RGBA['lime'],'L')]}
        for n in CARRY:
            print(n);a=np.array(frames[n])
            for y in range(19,48):print(y,''.join(symbols.get(tuple(p),'?') if p[3] else '.' for p in a[y]))
        return
    semantic_masks(frames);frames=process();checks(frames);print('Elf11native poses passed')

if __name__=='__main__':main()
