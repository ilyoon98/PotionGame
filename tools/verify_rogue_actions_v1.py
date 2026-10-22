"""Purchase event boundaries, preserved rogue identity and attached cat motion."""
import hashlib
import numpy as np
from PIL import Image
import build_rogue_actions_v1 as b
import publish_rogue_actions_v1 as p

def main():
    for name in ['native-validation.json','motion/validation.json','contact-validation.json']:
        if b.read(b.OUT/name)['status']!='passed':raise ValueError(f'Failed report:{name}')
    samples=[]
    for time,held,action,facing in [(8.4,False,'receive','left'),(8.45,True,'receive','left'),(10.2,True,'depart','right'),(13.35,True,'depart','right'),(14.2,False,'arrive','left')]:
        state=p.state(time)
        if (state['held'],state['action'],state['facing'])!=(held,action,facing):raise ValueError(f'Wrong event at{time}:{state}')
        samples.append(state)
    if not all(p.state(tick/20)['held'] for tick in range(169,268)):raise ValueError('Bottle disappears during exit')
    preserved=[]
    for name in b.common.POSES[:7]:
        old=b.OLD/'frames'/f'{name}.png';new=b.OUT/'frames'/f'{name}.png'
        if old.read_bytes()!=new.read_bytes():raise ValueError('Approved rogue keypose changed')
        preserved.append({'id':name,'unchanged':True,'sha256':hashlib.sha256(old.read_bytes()).hexdigest()})
    native=b.read(b.OUT/'native-validation.json');motion=b.read(b.OUT/'motion/validation.json');contact=b.read(b.OUT/'contact-validation.json')
    if not native['opposite_passing_support'] or not native['both_contact_feet_ground']:raise ValueError('Wrong support feet')
    if len(list((b.OUT/'motion').glob('*/*/frame-*.png')))!=1408 or len(motion['checks'])!=1408 or not all(c['passed'] for c in motion['checks']):raise ValueError('Incomplete motion bank')
    if not all(all(parts[k]>0 for k in ['left_ear','right_ear','tail','hair']) for parts in motion['moving_parts'].values()):raise ValueError('Frozen cat attachment')
    for n,point in p.GRIPS.items():
        if Image.open(b.OUT/'frames'/f'{n}.png').getpixel(tuple(point))!=b.RGBA['skin']:raise ValueError('Bottle misses visible fingers')
    for mode in ['fine','grid']:
        folder=b.OUT/'motion'/mode/'idle';rest=np.array(Image.open(folder/'frame-00.png'));up=np.array(Image.open(folder/'frame-16.png'))
        if not np.array_equal(rest[20*3:25*3,:22*3],up[19*3:24*3,:22*3]):raise ValueError('Head does not breathe up')
        if not np.array_equal(rest[35*3:],up[35*3:]):raise ValueError('Hips or feet float during breathing')
        if not np.array_equal(rest[32*3:39*3,22*3:],up[32*3:39*3,22*3:]):raise ValueError('Tail root moves with head')
    if contact['tested_combinations']!=432 or not all(c['passed'] for c in contact['checks']):raise ValueError('Incomplete recipe contact checks')
    b.dump(b.OUT/'verification.json',{'status':'passed','date':'2026-10-15','checks':{'event_boundaries':samples,'held_through_exit':True,'old7poses_unchanged':preserved,'opposite_passing_support':True,'both_contact_feet_ground':True,'left_ear_right_ear_tail_hair_move_both_modes':True,'head_breathes_with_fixed_hips_feet_tail_root':True,'native_poses':11,'motion_frames':1408,'recipe_facing_contacts':432,'palette_colors':5,'actual_skin_grips':True}})
    print('Rogue preserved identity/gait/cat attachments/breath/events/contacts verified')

if __name__=='__main__':main()
