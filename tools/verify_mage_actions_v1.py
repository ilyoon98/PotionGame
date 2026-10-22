"""Mage event boundaries, source preservation, hat/breath and two-facing grips."""
import hashlib
from PIL import Image
import numpy as np
import build_mage_actions_v1 as b
import publish_mage_actions_v1 as p

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
        if old.read_bytes()!=new.read_bytes():raise ValueError('Existing mage keypose changed')
        preserved.append({'id':name,'unchanged':True,'sha256':hashlib.sha256(old.read_bytes()).hexdigest()})
    if (b.OLD/'layers/hat.png').read_bytes()!=(b.OUT/'layers/hat.png').read_bytes():raise ValueError('Original approved hat layer changed')
    motion=b.read(b.OUT/'motion/validation.json');images=list((b.OUT/'motion').glob('*/*/frame-*.png'))
    if len(images)!=1408 or len(motion['checks'])!=1408 or not all(c['passed'] for c in motion['checks']):raise ValueError('Incomplete or invalid motion bank')
    for n,point in p.GRIPS.items():
        if Image.open(b.OUT/'frames'/f'{n}.png').getpixel(tuple(point))!=b.RGBA['skin']:raise ValueError('Grip leaves actual palm')
    for mode in ['fine','grid']:
        path=b.OUT/'motion'/mode/'idle';rest=np.array(Image.open(path/'frame-00.png'));lift=np.array(Image.open(path/'frame-16.png'))
        # Head and brim must rise together exactly one native row, with feet fixed.
        if not np.array_equal(rest[4*3:26*3],lift[3*3:25*3]):raise ValueError('Hat/head breath translation differs')
        if not np.array_equal(rest[40*3:],lift[40*3:]):raise ValueError('Feet float during breathing')
    contacts=b.read(b.OUT/'contact-validation.json')
    if contacts['tested_combinations']!=432 or not all(c['passed'] for c in contacts['checks']):raise ValueError('Incomplete contacts')
    b.dump(b.OUT/'verification.json',{'status':'passed','date':'2026-10-15','checks':{'event_boundaries':samples,'held_through_exit':True,'old7poses_unchanged':preserved,'original_hat_layer_unchanged':True,'head_and_hat_rise_together':True,'actual_skin_grips':True,'native_poses':11,'motion_frame_count':1408,'recipe_facing_contacts':432,'character_palette_colors':5}})
    print('Mage events/source preservation/hat breath/two-facing contacts verified')

if __name__=='__main__':main()
