"""Elf breath/blink and rooted brown-hair motion without face/outline damage."""
import math
import numpy as np
from PIL import Image
import build_elf_actions_v1 as b
import build_secondary_motion_v5 as s
import build_combined_idle_v6 as topology
from prepare_character_v6 import dark_component
from build_keeper_motion_v4 import outline
def cm(a,k):return np.all(a==b.RGBA[k],axis=2)

def profile(base):
    protected=s.grow(b.common.boundary(base))|s.grow(cm(base,'skin'),diagonal=True)|s.grow(cm(base,'lime'),diagonal=True)|(base[:,:,3]==0)
    spec=s.choose_motion(base,protected,[8,14,23,21],b.RGBA['brown'],[14,17],[1,0],1.8)
    return {'hair_strand':spec,'hair_crown_sway_rows':[11,15],'leaf_clip_root_pinned':True,'breath_cut':27}

def pose(base,spec,index,mode):
    closed=index>=32;lifted=(index//16)%2==1;source=base.copy()
    if closed:
        for x,y in b.EYES:source[y:y+2,x]=b.RGBA['skin']
        source[23,11:13]=b.RGBA['ink'];source[23,15:17]=b.RGBA['ink']
    if lifted:source[:27]=source[1:28]
    source[b.common.boundary(source)]=b.RGBA['ink'];a=s.zoom(source);ref=a.copy();phase=index%16*2*math.pi/16
    wave=math.sin(phase);step=1 if wave>.45 else -1 if wave<-.45 else 0;amount=step*(3 if mode=='grid' else 1)
    # Root row16 and the leaf/face below it stay seated on the breathing head.
    end=(16-int(lifted))*3
    if amount:
        old=a[:end].copy();a[:end]=0
        if amount>0:a[:end,amount:]=old[:,:-amount]
        else:a[:end,:amount]=old[:,-amount:]
    x,y=spec['hair_strand']['center'];y-=int(lifted);wave=math.sin(phase+1.8);step=1 if wave>.45 else -1 if wave<-.45 else 0;shift=step*(3 if mode=='grid' else 1)
    a[y*3:(y+1)*3,x*3:(x+1)*3]=b.RGBA['brown'];a[y*3:(y+1)*3,x*3+shift:x*3+shift+3]=b.RGBA['ink']
    return outline(a,ref,mode),ref

def check(a,ref,base,index,mode,name):
    native=a[::3,::3];closed=index>=32;lifted=(index//16)%2==1;v=b.validate(Image.fromarray(a),[96,144],b.PALETTE,5);eyes=[]
    pairs=[[(11,23),(12,23)],[(15,23),(16,23)]] if closed else [[(11,22),(11,23)],[(16,22),(16,23)]]
    for pair in pairs:
        pts=[(x,y-int(lifted)) for x,y in pair];xs,ys=zip(*pts)
        halo=all(tuple(native[y,x])==b.RGBA['skin'] for y in range(min(ys)-1,max(ys)+2) for x in range(min(xs)-1,max(xs)+2) if (x,y) not in pts)
        eyes.append({'points':pts,'isolated2':dark_component(Image.fromarray(native),pts[0],diagonals=True)==sorted(pts),'skin_halo1':halo})
    fixed=s.zoom(base);skin=cm(fixed,'skin');skin[:27*3]=False;palms=np.array_equal(a[skin],fixed[skin]);waist=np.array_equal(a[35*3:40*3],fixed[35*3:40*3]);feet=np.array_equal(a[40*3:],fixed[40*3:]);boundary=int((b.common.boundary(a)&np.any(a[:,:,:3]!=b.rgb(b.INK),axis=2)).sum());components=topology.count_components(a[:,:,3]>0);grid=np.array_equal(a,s.zoom(native))
    clip=cm(ref,'lime');clip[23*3:]=False;clip_pinned=np.array_equal(a[clip],ref[clip]);face=np.array_equal(a[(20-int(lifted))*3:27*3],ref[(20-int(lifted))*3:27*3])
    v.update(pose=name,mode=mode,index=index,blink=closed,breath_lifted=lifted,eyes=eyes,outline_boundary_violations=boundary,palms_and_exposed_body_fixed=bool(palms),waist_fixed=bool(waist),feet_fixed=bool(feet),ground_row46=bool(native[46,:,3].any() and not native[47,:,3].any()),leaf_clip_pinned_to_head=bool(clip_pinned),face_unchanged_by_hair=bool(face),opaque_components=components,native_grid_exact=bool(grid))
    v['passed']=bool(v['passed'] and not boundary and palms and waist and feet and clip_pinned and face and components==1 and v['ground_row46'] and all(e['isolated2'] and e['skin_halo1'] for e in eyes) and (mode!='grid' or grid))
    return v

def main():
    if b.read(b.OUT/'native-validation.json')['status']!='passed':raise ValueError('Native elf poses failed')
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
            atlas.save(target/mode/f'{n}-atlas.png');changes=max(int(np.any(a[:20*3]!=samples[0][:20*3],axis=2).sum()) for a in samples)
            if not changes:raise ValueError(f'Frozen hair:{n}/{mode}')
            report['moving_parts'][f'{mode}/{n}']={'hair_changed_display_pixels':changes}
    b.dump(target/'validation.json',report);failed=[v for v in report['checks'] if not v['passed']]
    if failed:print(failed[:2]);raise ValueError(f'Elf motion failed {len(failed)}/1408')
    print('Elf1408motion frames passed: eyes/outlines/rooted hair/breath/palms/waist/feet')

if __name__=='__main__':main()
