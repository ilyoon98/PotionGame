"""Anchored cat ears/tail, protected hair, breathing and equal-eye blink."""
import math
import numpy as np
from PIL import Image
import build_rogue_actions_v1 as b
import build_secondary_motion_v5 as s
import build_combined_idle_v6 as topology
from prepare_character_v6 import dark_component
from build_keeper_motion_v4 import outline
def cm(a,k):return np.all(a==b.RGBA[k],axis=2)
def step(phase):return 1 if math.sin(phase)>.45 else -1 if math.sin(phase)<-.45 else 0

def profile(base):
    protect=s.grow(b.common.boundary(base))|s.grow(cm(base,'skin'),diagonal=True)|(base[:,:,3]==0);options=[]
    for y in range(19,23):
        for x in range(8,22):
            if any(protect[y,x+k] or tuple(base[y,x+k]) not in (b.RGBA['light'],b.RGBA['orange']) for k in (-1,0,1)):continue
            options.append((abs(x-14)+abs(y-20),x,y))
    if not options:raise ValueError('No protected orange-hair cluster')
    _,x,y=min(options)
    remaining={(int(xx),int(yy)) for yy,xx in zip(*np.where(base[:,:,3]>0)) if xx>=22 and 25<=yy<39};groups=[]
    while remaining:
        group=[];stack=[remaining.pop()]
        while stack:
            xx,yy=stack.pop();group.append([xx,yy])
            for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                p=(xx+dx,yy+dy)
                if p in remaining:remaining.remove(p);stack.append(p)
        groups.append(group)
    tail=max(groups,key=len)
    return {'hair_strand_center':[x,y],'ear_tip_last_row':14,'ear_root_rows':[16,18],'tail_tip_region':[22,26,32,31],'tail_root_region':[22,32,32,39],'tail_pixels':tail,'breath_cut':27}

def shift_x(block,amount):
    out=np.zeros_like(block)
    if amount>0:out[:,amount:]=block[:,:-amount]
    elif amount<0:out[:,:amount]=block[:,-amount:]
    else:out=block.copy()
    return out

def pose(base,spec,index,mode):
    closed=index>=32;lifted=(index//16)%2==1;source=base.copy()
    if closed:
        for x,y in b.EYES:source[y:y+2,x]=b.RGBA['skin']
        source[24,10:12]=b.RGBA['ink'];source[24,13:15]=b.RGBA['ink']
    if lifted:
        # The tail belongs to the anchored hips, not to the breathing head.
        tail=np.zeros(source.shape[:2],bool)
        for xx,yy in spec['tail_pixels']:tail[yy,xx]=True
        source[tail]=0;source[:27]=source[1:28];source[tail]=base[tail]
    source[b.common.boundary(source)]=b.RGBA['ink'];a=s.zoom(source);ref=a.copy();phase=index%16*2*math.pi/16;unit=3 if mode=='grid' else 1
    end=(15-int(lifted))*3
    # Each ear tip folds independently; the root band is pinned to the head.
    for x0,x1,offset in [(3,13,0),(13,23,2.1)]:
        amount=step(phase+offset)*unit
        if amount:a[:end,x0*3:x1*3]=shift_x(a[:end,x0*3:x1*3],amount)
    # Only the distal curl moves; row31 is the bridge, root32..38 stays fixed.
    x0,y0,x1,y1=spec['tail_tip_region'];tail=a[y0*3:y1*3,x0*3:x1*3].copy()
    if np.any(cm(tail,'skin')|cm(tail,'scarf')):raise ValueError('Tail movement crop crosses a face or scarf')
    a[y0*3:y1*3,x0*3:x1*3]=shift_x(tail,step(phase+1.0)*unit)
    x,y=spec['hair_strand_center'];y-=int(lifted);amount=step(phase+2.7)*unit
    a[y*3:(y+1)*3,x*3:(x+1)*3]=b.RGBA['light'];a[y*3:(y+1)*3,x*3+amount:x*3+amount+3]=b.RGBA['orange']
    return outline(a,ref,mode),ref

def check(a,ref,base,index,mode,name):
    v=b.validate(Image.fromarray(a),[96,144],b.PALETTE,5);native=a[::3,::3];closed=index>=32;lifted=(index//16)%2==1;eyes=[]
    pairs=[[(10,24),(11,24)],[(13,24),(14,24)]] if closed else [[(10,23),(10,24)],[(14,23),(14,24)]]
    for points in pairs:
        pts=[(x,y-int(lifted)) for x,y in points];xs,ys=zip(*pts);halo=all(tuple(native[y,x])==b.RGBA['skin'] for y in range(min(ys)-1,max(ys)+2) for x in range(min(xs)-1,max(xs)+2) if (x,y) not in pts)
        eyes.append({'points':pts,'isolated2':dark_component(Image.fromarray(native),pts[0],diagonals=True)==sorted(pts),'skin_halo1':halo})
    fixed=s.zoom(base);hand=cm(fixed,'skin');hand[:27*3]=False;palms=np.array_equal(a[hand],fixed[hand]);waist=np.array_equal(a[35*3:40*3,:20*3],fixed[35*3:40*3,:20*3]);feet=np.array_equal(a[40*3:],fixed[40*3:]);boundary=int((b.common.boundary(a)&np.any(a[:,:,:3]!=b.rgb(b.INK),axis=2)).sum());components=topology.count_components(a[:,:,3]>0);grid=np.array_equal(a,s.zoom(native));ear_root=np.array_equal(a[(16-int(lifted))*3:(19-int(lifted))*3],ref[(16-int(lifted))*3:(19-int(lifted))*3]);tail_root=np.array_equal(a[32*3:39*3,22*3:],ref[32*3:39*3,22*3:]);face=np.array_equal(a[(23-int(lifted))*3:26*3,:22*3],ref[(23-int(lifted))*3:26*3,:22*3])
    v.update(pose=name,mode=mode,index=index,blink=closed,breath_lifted=lifted,eyes=eyes,outline_boundary_violations=boundary,ear_roots_fixed_to_head=bool(ear_root),tail_root_fixed_to_hips=bool(tail_root),face_unchanged_by_secondary_motion=bool(face),actual_palms_fixed=bool(palms),waist_fixed=bool(waist),feet_fixed=bool(feet),ground_row46=bool(native[46,:,3].any() and not native[47,:,3].any()),opaque_components=components,native_grid_exact=bool(grid))
    v['passed']=bool(v['passed'] and not boundary and palms and waist and feet and ear_root and tail_root and face and components==1 and v['ground_row46'] and all(e['isolated2'] and e['skin_halo1'] for e in eyes) and (mode!='grid' or grid))
    return v

def main():
    if b.read(b.OUT/'native-validation.json')['status']!='passed':raise ValueError('Native rogue poses failed')
    target=b.OUT/'motion';target.mkdir(exist_ok=True);report={'status':'passed','frame_count':1408,'native_size':[32,48],'display_size':[96,144],'scale':3,'fps':8,'phases':16,'breath_period_seconds':3,'blink_period_seconds':4.5,'motion_period_seconds':2,'fine_shift_display_pixels':1,'native_shift_pixels':1,'runtime_integrated':False,'profiles':{},'checks':[],'moving_parts':{}}
    for n in b.POSES:
        base=np.array(Image.open(b.OUT/'frames'/f'{n}.png').convert('RGBA'));spec=profile(base);report['profiles'][n]=spec
        for mode in ('grid','fine'):
            folder=target/mode/n;folder.mkdir(parents=True,exist_ok=True);atlas=Image.new('RGBA',(1536,576));samples=[]
            for index in range(64):
                a,ref=pose(base,spec,index,mode);v=check(a,ref,base,index,mode,n);report['checks'].append(v)
                if not v['passed']:report['status']='failed'
                im=Image.fromarray(a);im.save(folder/f'frame-{index:02d}.png');atlas.alpha_composite(im,(index%16*96,index//16*144))
                if index<16:samples.append(a)
            atlas.save(target/mode/f'{n}-atlas.png');x,y=spec['hair_strand_center'];regions={'left_ear':(3,11,13,15),'right_ear':(13,11,23,15),'tail':(22,26,32,31),'hair':(x-1,y,x+2,y+1)};changes={}
            for k,(x0,y0,x1,y1) in regions.items():changes[k]=max(int(np.any(a[y0*3:y1*3,x0*3:x1*3]!=samples[0][y0*3:y1*3,x0*3:x1*3],axis=2).sum()) for a in samples)
            if not all(changes.values()):raise ValueError(f'Frozen attachment:{n}/{mode}/{changes}')
            report['moving_parts'][f'{mode}/{n}']=changes
    b.dump(target/'validation.json',report);failures=[v for v in report['checks'] if not v['passed']]
    if failures:print(failures[:2]);raise ValueError(f'Rogue motion failed{len(failures)}/1408')
    print('Rogue1408motions passed: two eyes/outlines/rooted ears and tail/hair/breath/palms/feet')

if __name__=='__main__':main()
