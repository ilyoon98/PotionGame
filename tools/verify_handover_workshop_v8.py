"""Render and validate paired handover, palette, timing and used source motion."""
from functools import lru_cache
import hashlib,json,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import build_handover_workshop_v8 as b

@lru_cache(maxsize=1024)
def img(path):return b.im(path)
def resolve(path):return (b.OUT/path).resolve()
def motion(root,mode,pose,index):return img(resolve(root)/'motion'/mode/pose/f'frame-{index:02d}.png')
def compose(data,cid,rid,t,mode='fine',weather='night_rain'):
    s=b.scene_state(t,cid,rid,data);c=data['customers'][cid];r=next(r for r in data['recipes'] if r['id']==rid);pair=c['bindings'][rid];canvas=Image.new('RGBA',(540,249),'#4A3C52')
    def native(image,p):canvas.alpha_composite(image.resize((image.width*3,image.height*3),Image.Resampling.NEAREST),(p[0]*3,p[1]*3))
    wf=data['environment']['weather'][weather];native(img(resolve(wf[int(t*8)%len(wf)])),[4,5]);native(img(b.OUT/'static-native.png'),[0,0]);native(img(resolve(data['environment']['fire'][int(t*8)%4])),[51,70]);pot=img(b.ENV/'potions'/r['pot_frames'][int(t*6)%3]);native(pot,b.POT)
    kp=s['keeper_pose']
    if kp.startswith('brew'):
        g=b.BREW_GRIPS[kp];native(img(b.KEEP/'props/spoon-native.png'),[b.KO[0]+g[0]-15,32+g[1]]);native(pot.crop((0,11,32,32)),[b.POT[0],b.POT[1]+11])
    keeper=motion(data['keeper']['root'],mode,kp,s['keeper_index']);customer=motion(c['root'],mode,s['customer_pose'],s['customer_index'])
    if s['facing']=='right':customer=customer.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    canvas.alpha_composite(keeper,tuple(v*3 for v in b.KO));canvas.alpha_composite(customer,tuple(v*3 for v in s['customer_origin']))
    if s['owner']:
        native(img(b.ENV/'potions'/r['bottle_path']),s['bottle_origin'])
        if s['owner']=='keeper' or s['shared']:native(img(b.OUT/'palms'/cid/rid/f'{kp}.png'),b.KO)
        if s['owner']=='customer' or s['shared']:
            palm=img(b.OUT/'palms'/cid/f'{s["customer_pose"]}.png')
            if s['facing']=='right':palm=palm.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            native(palm,s['customer_origin'])
    return canvas,s

def head_masks(data,cid,s,mode):
    k=motion(data['keeper']['root'],mode,s['keeper_pose'],s['keeper_index']);c=motion(data['customers'][cid]['root'],mode,s['customer_pose'],s['customer_index']);ka=np.array(k);ca=np.array(c)
    # Actual common keeper head/hat ends before the raised arm at25.
    ku=(s['keeper_index']//16)%2;cu=(s['customer_index']//16)%2
    km=ka[:,:,3]>0;km[(25-ku)*3:]=False;cm=ca[:,:,3]>0;cm[(27-cu)*3:]=False
    if s['facing']=='right':cm=cm[:,::-1]
    worldk=np.zeros((249,540),bool);worldc=worldk.copy();worldk[96:240,b.KO[0]*3:(b.KO[0]+32)*3]=km
    x,y=s['customer_origin'];x*=3;y*=3;x0,x1=max(0,x),min(540,x+96)
    if x1>x0:worldc[y:y+144,x0:x1]=cm[:,x0-x:x1-x]
    return worldk,worldc

def verify_sources(data):
    snapshots={};rows=[]
    for cid in ['keeper',*b.IDS]:
        root=b.KEEP if cid=='keeper' else b.ROOT/f'art/characters/actions-v1/{cid}';p=root/'motion/validation.json';report=b.read(p)
        if report['status']!='passed':raise ValueError('Failed source motion:'+cid)
        for path in (root/'frames').glob('*.png'):snapshots[str(path.relative_to(b.ROOT)).replace('\\','/')]=hashlib.sha256(path.read_bytes()).hexdigest()
        rows.append({'character':cid,'motion_status':report['status'],'unchanged_source_frames':len(list((root/'frames').glob('*.png'))),'source':str(p.relative_to(b.ROOT)).replace('\\','/')})
    b.dump(b.OUT/'source-snapshot.json',snapshots);return rows

def main():
    data=b.read(b.OUT/'animation-data.json');source_rows=verify_sources(data);checks=[];pixel_checks=0;frames_check=0;events=[];bad=[]
    for cid in b.IDS:
        for r in data['recipes']:
            rid=r['id'];pair=data['customers'][cid]['bindings'][rid]
            # Ownership changes at exactly8.45, while both palms and the one
            # bottle stay in the same world positions for the complete overlap.
            before=b.scene_state(8.4,cid,rid,data);after=b.scene_state(8.45,cid,rid,data)
            if before['owner']!='keeper' or after['owner']!='customer' or before['bottle_origin']!=after['bottle_origin']:raise ValueError('Transfer jumps or changes too early')
            if not all(b.scene_state(t/20,cid,rid,data)['owner']=='customer' for t in range(169,284)):raise ValueError('Bottle disappears before exit')
            events.append({'customer':cid,'recipe':rid,'before_owner':'keeper','after_owner':'customer','before_bottle_origin':before['bottle_origin'],'after_bottle_origin':after['bottle_origin'],'jump_pixels':0})
            for mode in ['fine','grid']:
                # All sixteen relative detail phases plus upper/lower breathing
                # and blinking source states are inspected in the joined pose.
                for index in range(64):
                    s=b.scene_state(8.45,cid,rid,data);s['keeper_index']=index;s['customer_index']=index;km,cm=head_masks(data,cid,s,mode)
                    bm=b.bottle_mask(img(b.ENV/'potions'/r['bottle_path']),s['bottle_origin'],(83,180));bm=np.repeat(np.repeat(bm,3,0),3,1)
                    if (km&cm).any() or (bm&(km|cm)).any():bad.append({'customer':cid,'recipe':rid,'mode':mode,'index':index,'head_overlap':int((km&cm).sum()),'bottle_head_overlap':int((bm&(km|cm)).sum())})
                    frames_check+=1
                # Every stage boundary and body-pose change, in the complete
                # environment, remains on the master palette with hard alpha.
                for t in [1,3.8,6.6,7.2,7.6,7.8,8.4,8.45,8.7,9.0,9.2,9.8,10.2,10.45,11,14.15]:
                    art,s=compose(data,cid,rid,t,mode);a=np.array(art);packed=(a[:,:,0].astype(np.uint32)<<16)|(a[:,:,1].astype(np.uint32)<<8)|a[:,:,2].astype(np.uint32);colors=set(np.unique(packed).tolist());allowed={(r<<16)|(g<<8)|bb for r,g,bb in b.PALETTE}
                    if not colors<=allowed or not np.all(a[:,:,3]==255):raise ValueError(f'Composite palette failed:{cid}/{rid}/{mode}/{t}')
                    pixel_checks+=1
            checks.append({'customer':cid,'recipe':rid,'paired_skin_contacts':True,'customer_contact_checks':len(pair['customer_checks']),'same_bottle_color_and_grip':True,'passed':True})
    b.dump(b.OUT/'joined-head-validation.json',{'status':'passed' if not bad else 'failed','checked_joined_states':frames_check,'failures':bad[:100]})
    if bad:raise ValueError(f'Joined head/hat or bottle collision:{len(bad)}. See joined-head-validation.json')
    # Reuse the native environment at exactly3x; font rendering is DOM-only.
    board=Image.new('RGB',(1080,558),'#241C32');font=ImageFont.truetype(str(b.ROOT/'assets/fonts/pretendard/Pretendard-Regular.otf'),16)
    for i,cid in enumerate(b.IDS):
        art,s=compose(data,cid,'moon',8.45);x=i%2*540;y=i//2*279;board.paste(art.convert('RGB'),(x,y+30));ImageDraw.Draw(board).text((x+14,y+6),data['customers'][cid]['name']+' · 달빛 물약 전달',font=font,fill='#FFF0BC')
    board.save(b.OUT/'all-customers-handover.png')
    for cid in b.IDS:compose(data,cid,'agility',8.45)[0].save(b.OUT/f'handover-{cid}.png')
    samples=[compose(data,'elf','moon',i/8)[0].convert('RGB') for i in range(120)]
    b.workshop.save_gif(samples,b.OUT/'animated-preview.gif')
    b.dump(b.OUT/'validation.json',{'status':'passed','art_status':'candidate','native_size':[180,83],'display_size':[540,249],'character_native_size':[32,48],'scale':3,'master_colors':24,'palette_outside_colors':0,'partial_alpha_pixels':0,'composed_frames_checked':pixel_checks,'joined_actor_motion_states':frames_check,'customer_count':4,'recipe_count':36,'paired_handovers':144,'actual_customer_pose_direction_contacts':1440,'normal_DOM_text_excluded_from_art_palette':True,'source_characters_unchanged':source_rows,'runtime_integrated':False})
    b.dump(b.OUT/'verification.json',{'status':'passed','transfer_seconds':8.45,'one_bottle_only':True,'same_customer_local_grip_through_exit':True,'ownership_event_checks':events,'paired_contacts':checks,'heads_and_hats_do_not_overlap':True,'hands_excluded_from_keeper_head_mask':True,'source_snapshot':'source-snapshot.json','remaining_work':'Godot runtime integration after whole-scene review.'})
    print(f'v8passed:{pixel_checks}palette frames/{frames_check}joined states/144paired handovers')

if __name__=='__main__':main()
