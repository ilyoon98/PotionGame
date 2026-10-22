"""Combined keeper breathing/blink and anchored hat/cape/hair motion.

Native keyposes stay32x48. Fine mode only displaces specified attachments by
one display pixel at3x; no filtering, new colors, or fractional alpha.
"""
from __future__ import annotations
import json, math
import numpy as np
from PIL import Image
import build_keeper_actions_v4 as b
import build_secondary_motion_v5 as s
import build_combined_idle_v6 as topology
from prepare_character_v6 import dark_component

OUT=b.OUT/'motion';SCALE=3;PHASES=16
RGBA={n:(*b.rgb(c),255) for n,c in [('ink',b.INK),('skin',b.SKIN),('brown',b.BROWN),('purple',b.PURPLE),('gold',b.GOLD)]}
def dump(path,data):b.dump(path,data)
def color_mask(a,color):return np.all(a==RGBA[color],axis=2)

def outline(a,reference,mode):
    # A full one-native-pixel perimeter, even in the fractional display mode.
    if mode=='grid':
        native=a[::3,::3].copy();native[b.common.boundary(native)]=RGBA['ink'];return s.zoom(native)
    alpha=a[:,:,3]>0;inside=alpha.copy()
    for _ in range(3):
        pad=np.pad(inside,1);inside=pad[1:-1,:-2]&pad[1:-1,2:]&pad[:-2,1:-1]&pad[2:,1:-1]
    changed=alpha!=(reference[:,:,3]>0);near=changed.copy()
    for _ in range(3):near=s.grow(near)
    # Repair only the moved appendage perimeter. Never thicken unchanged face,
    # hands, waist or boots by re-eroding the complete sprite.
    a[alpha&~inside&near]=RGBA['ink'];return a

def make_pose(base,eyes,phase,blink,lifted,mode,name):
    source=base.copy()
    if blink:
        for x,y in eyes:
            source[y:y+2,x]=RGBA['skin'];source[y+1,x]=RGBA['ink']
    # Move the upper body in IDLE, only head/collar during tool contact actions.
    cut=30 if name=='idle' else 26
    if lifted:
        source[:cut]=source[1:cut+1]
        if name.startswith('brew'):
            source[19:24,:8]=base[19:24,:8];source[24:32,:14]=base[24:32,:14]
    source[b.common.boundary(source)]=RGBA['ink']
    a=s.zoom(source);reference=a.copy();wave=math.sin(phase);step=1 if wave>.45 else -1 if wave<-.45 else 0
    amount=step*(3 if mode=='grid' else 1)
    # Hat cone only: brim/hat seat and eyes stay attached to the head.
    hat_end=(10-int(lifted))*3
    if amount:
        old=a[:hat_end].copy();a[:hat_end]=0
        if amount>0:a[:hat_end,amount:]=old[:,:-amount]
        else:a[:hat_end,:amount]=old[:,-amount:]
    # Cloak tails move outside the stationary hips, knees, hands and boots.
    left=name.startswith('brew');regions=[(0,37,11 if left else 8,43),(23 if left else 22,37,32,43)]
    cape_wave=math.sin(phase+1.1);cape_step=1 if cape_wave>.45 else -1 if cape_wave<-.45 else 0
    cape_shift=abs(cape_step)*(3 if mode=='grid' else 1)
    for x0,y0,x1,y1 in regions:
        if not cape_shift:continue
        block=a[y0*3:y1*3,x0*3:x1*3].copy();moved=np.zeros_like(block)
        outward=-cape_shift if x0==0 else cape_shift
        if outward>0:moved[:,outward:]=block[:,:-outward]
        else:moved[:,:outward]=block[:,-outward:]
        # The crop is outside the core. Reject unexpected core material there.
        if np.any(color_mask(block,'brown')|color_mask(block,'skin')|color_mask(block,'gold')):raise ValueError(f'Cape crop intersects body core: {name}/{x0,y0,x1,y1}')
        old_alpha=block[:,:,3]>0;new_alpha=moved[:,:,3]>0
        combined=block.copy();combined[new_alpha&~old_alpha]=moved[new_alpha&~old_alpha]
        # Preserve the core-side seam. Old outer ink becoming cloth interior is
        # filled with purple; the new outside perimeter is repaired afterwards.
        combined_alpha=combined[:,:,3]>0;pad=np.pad(combined_alpha,1)
        interior=pad[1:-1,:-2]&pad[1:-1,2:]&pad[:-2,1:-1]&pad[2:,1:-1]
        combined[interior&color_mask(block,'ink')&new_alpha]=RGBA['purple']
        a[y0*3:y1*3,x0*3:x1*3]=combined
    # A native brown/ink hair strand moves strictly inside the hair cluster.
    protected=s.grow(b.common.boundary(source))|s.grow(color_mask(source,'skin'),diagonal=True)|(source[:,:,3]==0)
    spec=s.choose_motion(source,protected,[8,14-int(lifted),23,19-int(lifted)],RGBA['brown'],[15,16-int(lifted)],[1,0],2.2)
    strand_step=1 if math.sin(phase+2.2)>.45 else -1 if math.sin(phase+2.2)<-.45 else 0
    x,y=spec['center'];a[y*3:(y+1)*3,x*3:(x+1)*3]=RGBA['brown']
    xx=x*3+strand_step*(3 if mode=='grid' else 1);a[y*3:(y+1)*3,xx:xx+3]=RGBA['ink']
    a=outline(a,reference,mode)
    return a,reference,cut,spec,regions

def check(a,reference,base,eyes,blink,lifted,mode,name,index,cut,regions):
    im=Image.fromarray(a);v=b.validate(im,[96,144],b.PALETTE,5);native=a[::3,::3]
    boundaries=int((b.common.boundary(a)&np.any(a[:,:,:3]!=b.rgb(b.INK),axis=2)).sum())
    checks=[]
    for x,y in eyes:
        y-=int(lifted);points=[(x,y+1)] if blink else [(x,y),(x,y+1)]
        xs,ys=zip(*points)
        halo=all(tuple(native[yy,xx])==RGBA['skin'] for yy in range(min(ys)-1,max(ys)+2) for xx in range(min(xs)-1,max(xs)+2) if (xx,yy) not in points)
        isolated=dark_component(Image.fromarray(native),points[0],diagonals=True)==sorted(points)
        checks.append({'points':points,'full_skin_halo1':halo,'isolated2':isolated})
    fixed=s.zoom(base);core=(color_mask(fixed,'brown')|color_mask(fixed,'skin'))
    core[:32*3]=False
    core_fixed=bool(np.array_equal(a[core],fixed[core]));feet_fixed=bool(np.array_equal(a[43*3:],fixed[43*3:]))
    # Hands include all original palm pixels, including the fingers above32.
    hand_mask=color_mask(fixed,'skin')
    hand_mask[:25*3]=False
    if name.startswith('brew'):
        hand_mask[:25*3]=color_mask(fixed,'skin')[:25*3]
        hand_mask[:25*3,8*3:]=False
    if name=='idle':hand_mask[:32*3]=False
    else:
        shirt_x=(13,20) if name.startswith('brew') else (11,19)
        hand_mask[25*3:33*3,shirt_x[0]*3:shirt_x[1]*3]=False
    hands_fixed=bool(np.array_equal(a[hand_mask],fixed[hand_mask]))
    components=topology.count_components(a[:,:,3]>0)
    hair_points=[(int(x),int(y)-int(lifted)) for y,x in zip(*np.where(color_mask(base,'brown'))) if 14<=y<25]
    purple_hair=sum(tuple(native[y,x,:3])==b.rgb(b.PURPLE) for x,y in hair_points)
    hat_seat=bool(np.array_equal(a[11*3:14*3],reference[11*3:14*3]))
    v.update(pose=name,mode=mode,index=index,blink=blink,breath_lifted=lifted,eyes=checks,outline_boundary_violations=boundaries,waist_hips_legs_core_fixed=core_fixed,feet_fixed=feet_fixed,hands_fixed=hands_fixed,opaque_components=components,purple_hair_pixels=purple_hair,hat_seat_fixed_to_head=hat_seat,native_grid_exact=bool(np.array_equal(a,s.zoom(native))))
    v['passed']=bool(v['passed'] and not boundaries and core_fixed and feet_fixed and hands_fixed and components==1 and not purple_hair and hat_seat and all(c['full_skin_halo1'] and c['isolated2'] for c in checks) and (mode!='grid' or v['native_grid_exact']))
    return v

def main():
    OUT.mkdir(parents=True,exist_ok=True);report={'status':'passed','fps':8,'phases':16,'frames_per_pose_mode':64,'total_frames':768,'native_keypose_size':[32,48],'motion_display_size':[96,144],'breath_period_seconds':3,'blink_period_seconds':4.5,'hat_period_seconds':2,'hat_seat_fixed':True,'fine_max_attachment_shift_display_pixels':1,'waist_translation':0,'runtime_integrated':False,'checks':[],'atlases':{},'profiles':{}}
    for n in b.POSES:
        base=np.array(Image.open(b.OUT/'frames'/f'{n}.png').convert('RGBA'));eyes=[(11,19),(13,19)] if n.startswith('brew') else [(17,19),(19,19)]
        for mode in ('grid','fine'):
            target=OUT/mode/n;target.mkdir(parents=True,exist_ok=True);atlas=Image.new('RGBA',(1536,576));samples=[]
            for blink in (False,True):
                for lifted in (False,True):
                    for phase_index in range(16):
                        index=phase_index+int(lifted)*16+int(blink)*32
                        a,ref,cut,spec,regions=make_pose(base,eyes,phase_index*2*math.pi/16,blink,lifted,mode,n)
                        v=check(a,ref,base,eyes,blink,lifted,mode,n,index,cut,regions);report['checks'].append(v)
                        if not v['passed']:report['status']='failed'
                        im=Image.fromarray(a);im.save(target/f'frame-{index:02d}.png');atlas.alpha_composite(im,(phase_index*96,(index//16)*144))
                        if index<16:samples.append(a)
            atlas.save(OUT/mode/f'{n}-atlas.png');report['atlases'][f'{mode}/{n}']=f'motion/{mode}/{n}-atlas.png'
            report['profiles'][n]={'breath_cut':cut,'hair_strand':spec,'cape_regions':regions,'eye_points':eyes,'hat_cone_last_row':9,'hat_brim_seat_pinned':True}
            hat_changes=max(int(np.any(a[:10*3]!=samples[0][:10*3],axis=2).sum()) for a in samples)
            cape_changes=max(int(np.any(a[37*3:43*3]!=samples[0][37*3:43*3],axis=2).sum()) for a in samples)
            if not hat_changes or not cape_changes:raise ValueError(f'Frozen attachment: {n}/{mode}')
    dump(OUT/'validation.json',report)
    failures=[v for v in report['checks'] if not v['passed']]
    if failures:
        print([{k:v for k,v in f.items() if k not in ('colors','opaque_pixels')} for f in failures[:5]])
        raise ValueError(f'Motion checks failed: {len(failures)}/768')
    print('Combined keeper motion passed768frames: both eyes, outlines, fixed palms/waist/feet, moving hat/cape')

if __name__=='__main__':main()
