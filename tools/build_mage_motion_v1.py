"""Mage breath/blink, moving hat cone and long-hair crease with seated brim."""
from __future__ import annotations
import math
import numpy as np
from PIL import Image
import build_mage_actions_v1 as b
import build_secondary_motion_v5 as s
import build_combined_idle_v6 as topology
from prepare_character_v6 import dark_component
from build_keeper_motion_v4 import outline

def cm(a,key):return np.all(a==b.RGBA[key],axis=2)

def profile(base):
    protect=s.grow(b.common.boundary(base))|s.grow(cm(base,'skin'),diagonal=True)|s.grow(cm(base,'brown'))|(base[:,:,3]==0)
    options=[]
    for y in range(24,34):
        for x in range(19,28):
            for dx,dy in [(0,1),(1,0)]:
                if any(protect[y+k*dy,x+k*dx] or tuple(base[y+k*dy,x+k*dx]) not in (b.RGBA['purple'],b.RGBA['dark']) for k in (-1,0,1)):continue
                options.append((abs(x-24)+abs(y-29),x,y,dx,dy))
    if not options:raise ValueError('No protected long-hair cluster')
    _,x,y,dx,dy=min(options);return {'long_hair':{'center':[x,y],'axis':[dx,dy]},'hat_cone_rows':[4,9],'hat_brim_seat_pinned_rows':[11,18],'breath_cut':27}

def pose(base,spec,index,mode):
    closed=index>=32;lifted=(index//16)%2==1;source=base.copy()
    if closed:
        for x,y in b.EYES:source[y:y+2,x]=b.RGBA['skin'];source[y+1,x:x+2]=b.RGBA['ink']
    if lifted:source[:27]=source[1:28]
    source[b.common.boundary(source)]=b.RGBA['ink'];a=s.zoom(source);ref=a.copy()
    phase=index%16*2*math.pi/16;wave=math.sin(phase);step=1 if wave>.45 else -1 if wave<-.45 else 0;amount=step*(3 if mode=='grid' else 1)
    # Leave a complete cone-to-brim bridge row before the pinned seat band.
    end=(10-int(lifted))*3
    if amount:
        block=a[:end].copy();a[:end]=0
        if amount>0:a[:end,amount:]=block[:,:-amount]
        else:a[:end,:amount]=block[:,-amount:]
    x,y=spec['long_hair']['center'];y-=int(lifted and y<27);dx,dy=spec['long_hair']['axis'];wave=math.sin(phase+1.8);step=1 if wave>.45 else -1 if wave<-.45 else 0;shift=step*(3 if mode=='grid' else 1)
    a[y*3:(y+1)*3,x*3:(x+1)*3]=b.RGBA['purple'];xx,yy=x*3+dx*shift,y*3+dy*shift;a[yy:yy+3,xx:xx+3]=b.RGBA['dark']
    a=outline(a,ref,mode)
    return a,ref

def check(a,ref,base,index,mode,name,body,hat_mask):
    v=b.validate(Image.fromarray(a),[96,144],b.PALETTE,5);native=a[::3,::3];lifted=(index//16)%2==1;closed=index>=32
    eyes=[]
    for x,y in b.EYES:
        y-=int(lifted);points=[(x,y+1),(x+1,y+1)] if closed else [(x,y),(x,y+1)];xx,yy=zip(*points)
        halo=all(tuple(native[j,i])==b.RGBA['skin'] for j in range(min(yy)-1,max(yy)+2) for i in range(min(xx)-1,max(xx)+2) if (i,j) not in points)
        eyes.append({'points':points,'isolated2':dark_component(Image.fromarray(native),points[0],diagonals=True)==sorted(points),'skin_halo1':halo})
    fixed=s.zoom(base);hand=cm(fixed,'skin');hand[:27*3]=False
    y0=(11-int(lifted))*3;y1=(18-int(lifted))*3
    seat=np.array_equal(a[y0:y1],ref[y0:y1]);outline_bad=int((b.common.boundary(a)&np.any(a[:,:,:3]!=b.rgb(b.INK),axis=2)).sum())
    overlap=int((hat_mask& (body[:,:,3]>0))[11:18,8:20].sum())
    palms=np.array_equal(a[hand],fixed[hand]);waist=np.array_equal(a[35*3:40*3,:21*3],fixed[35*3:40*3,:21*3]);feet=np.array_equal(a[40*3:],fixed[40*3:]);components=topology.count_components(a[:,:,3]>0)
    on_grid=np.array_equal(a,s.zoom(native));hair=cm(base,'purple')|cm(base,'dark');hair[:18]=False;hair[34:]=False;hair[:,:19]=False
    if lifted:hair[:27]=hair[1:28]
    foreign=int((hair&(cm(native,'brown')|cm(native,'skin'))).sum())
    v.update(pose=name,mode=mode,index=index,blink=closed,breath_lifted=lifted,eyes=eyes,outline_boundary_violations=outline_bad,hat_seat_fixed_to_head=bool(seat),hat_crown_overlap_pixels=overlap,hat_crown_overlap_sufficient=overlap>=40,palms_fixed=bool(palms),waist_fixed_within_keypose=bool(waist),feet_fixed=bool(feet),ground_row46=bool(native[46,:,3].any() and not native[47,:,3].any()),opaque_components=components,native_grid_exact=bool(on_grid),foreign_material_in_hair=foreign)
    v['passed']=bool(v['passed'] and not outline_bad and seat and overlap>=40 and palms and waist and feet and components==1 and not foreign and v['ground_row46'] and all(e['isolated2'] and e['skin_halo1'] for e in eyes) and (mode!='grid' or on_grid))
    return v

def main():
    if b.read(b.OUT/'native-validation.json')['status']!='passed':raise ValueError('Native mage poses failed')
    target=b.OUT/'motion';target.mkdir(exist_ok=True);hat_mask=np.zeros((48,32),bool);hat_mask[4:18]=np.array(Image.open(b.OUT/'layers/hat.png'))[:,:,3]>0
    report={'status':'passed','frame_count':1408,'native_size':[32,48],'display_size':[96,144],'scale':3,'fps':8,'phases':16,'breath_period_seconds':3,'blink_period_seconds':4.5,'motion_period_seconds':2,'fine_shift_display_pixels':1,'native_shift_pixels':1,'hat_origin':[0,4],'hat_head_seat':[14,14],'runtime_integrated':False,'profiles':{},'checks':[],'moving_parts':{}}
    for n in b.POSES:
        base=np.array(Image.open(b.OUT/'frames'/f'{n}.png').convert('RGBA'));body=np.array(Image.open(b.OUT/'body-frames'/f'{n}.png').convert('RGBA'));spec=profile(base);report['profiles'][n]=spec
        for mode in ('grid','fine'):
            folder=target/mode/n;folder.mkdir(parents=True,exist_ok=True);atlas=Image.new('RGBA',(1536,576));samples=[]
            for index in range(64):
                a,ref=pose(base,spec,index,mode);v=check(a,ref,base,index,mode,n,body,hat_mask);report['checks'].append(v)
                if not v['passed']:report['status']='failed'
                im=Image.fromarray(a);im.save(folder/f'frame-{index:02d}.png');atlas.alpha_composite(im,(index%16*96,index//16*144))
                if index<16:samples.append(a)
            atlas.save(target/mode/f'{n}-atlas.png')
            changes={'hat_cone':max(int(np.any(a[:33]!=samples[0][:33],axis=2).sum()) for a in samples),'long_hair':max(int(np.any(a[24*3:34*3]!=samples[0][24*3:34*3],axis=2).sum()) for a in samples)}
            if not all(changes.values()):raise ValueError(f'Frozen secondary motion:{n}/{mode}')
            report['moving_parts'][f'{mode}/{n}']=changes
    b.dump(target/'validation.json',report);failures=[v for v in report['checks'] if not v['passed']]
    if failures:print(failures[:2]);raise ValueError(f'Mage motion failed {len(failures)}/1408')
    print('Mage1408motion frames passed: eyes/outlines/hat seat/skin grips/waist/feet')

if __name__=='__main__':main()
