"""Check purchase-event boundaries, carry persistence and preserved source art."""
import hashlib
from PIL import Image
import build_traveler_actions_v1 as b
import publish_traveler_actions_v1 as p

def main():
    report={'status':'passed','date':'2026-10-15','checks':{}}
    for name in ('native-validation.json','motion/validation.json','contact-validation.json'):
        data=b.read(b.OUT/name)
        if data['status']!='passed':raise ValueError(f'Failed report: {name}')
    expected=[(8.4,False,'receive','left'),(8.45,True,'receive','left'),(10.2,True,'depart','right'),(13.35,True,'depart','right'),(14.2,False,'arrive','left')]
    samples=[]
    for time,held,action,facing in expected:
        state=p.state(time)
        if (state['held'],state['action'],state['facing'])!=(held,action,facing):raise ValueError(f'Wrong bottle event boundary at{time}: {state}')
        samples.append(state)
    for tick in range(169,268):
        if not p.state(tick/20)['held']:raise ValueError('Bottle disappears before leaving')
    original=[]
    for name in b.common.POSES[:7]:
        old=b.OLD/'frames'/f'{name}.png';new=b.OUT/'frames'/f'{name}.png'
        if old.read_bytes()!=new.read_bytes():raise ValueError('Existing keypose was changed')
        original.append({'id':name,'sha256':hashlib.sha256(old.read_bytes()).hexdigest(),'unchanged':True})
    poses={name:Image.open(b.OUT/'frames'/f'{name}.png').convert('RGBA') for name in b.POSES}
    images=list((b.OUT/'motion').glob('*/*/frame-*.png'))
    if len(images)!=1408:raise ValueError('Incomplete motion bank')
    for name,point in p.GRIPS.items():
        x,y=point
        if poses[name].getpixel((x,y))!=b.RGBA['skin']:raise ValueError('Actual hand grip lost')
    report['checks'].update(event_boundaries=samples,held_through_exit=True,original7poses=original,motion_frame_count=1408,actual_skin_grips=True,character_palette_colors=len(b.PALETTE),native_pose_count=len(poses),recipe_facing_contacts=432)
    b.dump(b.OUT/'verification.json',report);print('Traveler event boundaries/carry persistence/original7poses/1408frame bank verified')

if __name__=='__main__':main()
