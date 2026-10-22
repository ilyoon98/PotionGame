"""Traveler breathing, blinking and protected brown-hair/bedroll motion."""
from __future__ import annotations
import math
import numpy as np
from PIL import Image
import build_traveler_actions_v1 as b
import build_secondary_motion_v5 as s
import build_combined_idle_v6 as topology
from prepare_character_v6 import dark_component

def cm(a,name):return np.all(a==b.RGBA[name],axis=2)

def landmark(a,region,material,wanted,axes):
    protected=s.grow(b.common.boundary(a))|s.grow(cm(a,'skin'),diagonal=True)|(a[:,:,3]==0)
    x0,y0,x1,y1=region;candidates=[]
    for y in range(y0,y1):
        for x in range(x0,x1):
            if protected[y,x] or tuple(a[y,x]) not in (b.RGBA[material],b.RGBA['brown']):continue
            for dx,dy in axes:
                if any(protected[y+sign*dy,x+sign*dx] or tuple(a[y+sign*dy,x+sign*dx])!=b.RGBA[material] for sign in (-1,1)):continue
                score=abs(x-wanted[0])+abs(y-wanted[1])+(0 if tuple(a[y,x])==b.RGBA['brown'] else 80)
                candidates.append((score,x,y,dx,dy))
    if not candidates:raise ValueError(f'No safe interior motion landmark in{region}')
    _,x,y,dx,dy=min(candidates);return {'center':[x,y],'axis':[dx,dy],'fill_material':material,'shadow_material':'brown','region':region}

def specs(base):
    hair=landmark(base,[6,13,21,21],'honey',[13,17],[(1,0),(0,1)])
    try:pack=landmark(base,[21,21,28,28],'shirt',[24,24],[(0,1),(1,0)])
    except ValueError:pack=landmark(base,[21,27,29,36],'honey',[24,31],[(0,1),(1,0)])
    return {'brown_bangs':hair,'bedroll_strap':pack}

def pose(base,profile,index,mode):
    source=base.copy();closed=index>=32;lifted=(index//16)%2==1
    if closed:
        for x,y in b.EYES:
            source[y:y+2,x]=b.RGBA['skin'];source[y+1,x:x+2]=b.RGBA['ink']
    if lifted:source[:27]=source[1:28]
    source[b.common.boundary(source)]=b.RGBA['ink'];a=s.zoom(source);reference=a.copy()
    phase=(index%16)*2*math.pi/16
    for i,spec in enumerate(profile.values()):
        x,y=spec['center'];y-=int(lifted and y<27);dx,dy=spec['axis']
        wave=math.sin(phase+i*1.8);step=1 if wave>.45 else -1 if wave<-.45 else 0
        shift=step*(3 if mode=='grid' else 1)
        a[y*3:(y+1)*3,x*3:(x+1)*3]=b.RGBA[spec['fill_material']]
        xx,yy=x*3+dx*shift,y*3+dy*shift;a[yy:yy+3,xx:xx+3]=b.RGBA['brown']
    return a,reference,closed,lifted

def check(a,ref,base,n,index,mode):
    v=b.validate(Image.fromarray(a),[96,144],b.PALETTE,5);native=a[::3,::3];closed=index>=32;lifted=(index//16)%2==1
    border=b.common.boundary(a);v['outline_boundary_violations']=int((border&np.any(a[:,:,:3]!=b.rgb(b.INK),axis=2)).sum())
    eyes=[]
    for x,y in b.EYES:
        y-=int(lifted);points=[(x,y+1),(x+1,y+1)] if closed else [(x,y),(x,y+1)]
        xx,yy=zip(*points);halo=all(tuple(native[j,i])==b.RGBA['skin'] for j in range(min(yy)-1,max(yy)+2) for i in range(min(xx)-1,max(xx)+2) if (i,j) not in points)
        comp=dark_component(Image.fromarray(native),points[0],diagonals=True)
        eyes.append({'points':points,'isolated2':comp==sorted(points),'skin_halo1':halo})
    fixed=s.zoom(base);hand=cm(fixed,'skin');hand[:27*3]=False
    waist=np.zeros(a.shape[:2],bool);waist[35*3:40*3,:21*3]=True
    alpha_equal=bool(np.array_equal(a[:,:,3],ref[:,:,3]));feet=bool(np.array_equal(a[40*3:],fixed[40*3:]));palms=bool(np.array_equal(a[hand],fixed[hand]));hips=bool(np.array_equal(a[waist],fixed[waist]))
    components=topology.count_components(a[:,:,3]>0);on_grid=bool(np.array_equal(a,s.zoom(native)))
    hair_mask=cm(base,'honey');hair_mask[:11]=False;hair_mask[21:]=False
    if lifted:hair_mask[:27]=hair_mask[1:28]
    forbidden_hair=int((hair_mask&(cm(native,'skin')|cm(native,'shirt'))).sum())
    v.update(pose=n,mode=mode,index=index,eyes=eyes,blink=closed,breath_lifted=lifted,silhouette_fixed_within_breath=alpha_equal,palms_fixed=palms,waist_fixed_within_keypose=hips,feet_fixed=feet,ground_row46=bool(native[46,:,3].any() and not native[47,:,3].any()),opaque_components=components,native_grid_exact=on_grid,foreign_material_in_hair=forbidden_hair)
    v['passed']=bool(v['passed'] and not v['outline_boundary_violations'] and alpha_equal and palms and hips and feet and v['ground_row46'] and components==1 and not forbidden_hair and all(e['isolated2'] and e['skin_halo1'] for e in eyes) and (mode!='grid' or on_grid))
    return v

def main():
    if b.read(b.OUT/'native-validation.json')['status']!='passed':raise ValueError('Native poses failed')
    target=b.OUT/'motion';target.mkdir(exist_ok=True);report={'status':'passed','native_size':[32,48],'display_size':[96,144],'scale':3,'phases':16,'fps':8,'frame_count':len(b.POSES)*128,'palette_file':'art/palettes/v1/characters/traveler.hex','breath_cut':27,'breath_period_seconds':3,'blink_period_seconds':4.5,'motion_period_seconds':2,'fine_shift_display_pixels':1,'native_shift_pixels':1,'feet_and_actual_palms_fixed':True,'runtime_integrated':False,'profiles':{},'checks':[]}
    for n in b.POSES:
        base=np.array(Image.open(b.OUT/'frames'/f'{n}.png').convert('RGBA'));profile=specs(base);report['profiles'][n]=profile
        for mode in ('grid','fine'):
            atlas=Image.new('RGBA',(1536,576));folder=target/mode/n;folder.mkdir(parents=True,exist_ok=True)
            for index in range(64):
                a,ref,closed,lifted=pose(base,profile,index,mode);v=check(a,ref,base,n,index,mode);report['checks'].append(v)
                if not v['passed']:report['status']='failed'
                im=Image.fromarray(a);im.save(folder/f'frame-{index:02d}.png');atlas.alpha_composite(im,((index%16)*96,(index//16)*144))
            atlas.save(target/mode/f'{n}-atlas.png')
    b.dump(target/'validation.json',report)
    failed=[c for c in report['checks'] if not c['passed']]
    if failed:print(failed[:2]);raise ValueError(f'Traveler motion failed{len(failed)}/{len(report["checks"])}')
    print('traveler combined motion passed1408frames')

if __name__=='__main__':main()
