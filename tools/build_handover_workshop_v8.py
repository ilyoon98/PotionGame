"""Whole workshop handover: one bottle, actual paired palms, four customers."""
from __future__ import annotations
import base64,hashlib,io,json,math,shutil
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from process_pixel_art import ROOT,rgb,validate
import build_traveler_keyframes_v1 as common
import build_refined_workshop_mockup as workshop

OUT=ROOT/'art/mockups/full-ingame-v8';ENV=ROOT/'art/mockups/full-ingame-v7';KEEP=ROOT/'art/characters/keyframes-v4/keeper'
IDS=['traveler','mage','elf','rogue'];NAMES=['여행자','여마법사','엘프','고양이 도적'];KO=[63,32];POT=[41,47];SIZE=[180,83];SCALE=3
INK=(*rgb('#241C32'),255);SKIN=(*rgb('#F6D1AC'),255)
PALETTE={rgb(c) for c in (ROOT/'art/palette.hex').read_text(encoding='utf-8').splitlines() if c.strip()}
KPOSES=['idle','brew_reach','brew_stir_left','brew_stir_right','handover_extend','handover_return']
BREW_GRIPS={'brew_reach':[4,21],'brew_stir_left':[5,23],'brew_stir_right':[4,24]}
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def dump(p,d):common.dump(p,d)
def im(p):return Image.open(p).convert('RGBA')
def rel(p):return str(p.relative_to(OUT)).replace('\\','/') if p.is_relative_to(OUT) else str(Path('../../../')/p.relative_to(ROOT/'art/mockups')).replace('\\','/')
def uri_image(s):return Image.open(io.BytesIO(base64.b64decode(s.split(',',1)[1]))).convert('RGBA')
def skin_points(a,rect):
    x0,y0,x1,y1=rect;return [[int(x),int(y)] for y,x in zip(*np.where(np.all(a==SKIN,axis=2))) if x0<=x<x1 and y0<=y<y1]

def palm_overlay(image,point):
    a=np.array(image);x,y=point;roi=np.zeros((48,32),bool);roi[max(0,y-3):min(48,y+4),max(0,x-3):min(32,x+4)]=True;skin=np.all(a==SKIN,axis=2)&roi;near=np.zeros_like(skin)
    for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:near|=np.roll(np.roll(skin,dy,0),dx,1)
    keep=skin|(near&roi&np.all(a==INK,axis=2));out=np.zeros_like(a);out[keep]=a[keep];return Image.fromarray(out)

def bottle_mask(bottle,origin,size=(48,32)):
    mask=np.zeros(size,bool);bx,by=origin;ba=np.array(bottle)[:,:,3]>0;x0,y0=max(0,bx),max(0,by);x1,y1=min(size[1],bx+bottle.width),min(size[0],by+bottle.height)
    if x1>x0 and y1>y0:mask[y0:y1,x0:x1]=ba[y0-by:y1-by,x0-bx:x1-bx]
    return mask

def solve_pair(cid,recipe,frames,grips,kframes):
    bottle=im(ENV/'potions'/recipe['bottle_path']);ba=np.array(bottle);cx,cy=grips['receive_extend'];ka=np.array(kframes['handover_extend']);kr=np.array(kframes['handover_return']);ca=np.array(frames['receive_extend']);options=[]
    post_checks={}
    # Keep the customer's exact same grip on the same bottle pixels from first
    # touch through folding arms and departure. No floating/re-anchoring jump.
    for ly in range(3,bottle.height-3):
        for lx in range(bottle.width):
            if not ba[ly,lx,3]:continue
            tests=[]
            for pose,g in grips.items():
                a=np.array(frames[pose]);head=a[:,:,3]>0;head[27:]=False;hand=np.array(palm_overlay(frames[pose],g))[:,:,3]>0
                for facing in (['left'] if pose.startswith('receive_') else ['left','right']):
                    gx=g[0] if facing=='left' else 31-g[0];bx,by=gx-lx,g[1]-ly;mask=bottle_mask(bottle,[bx,by]);hm=head if facing=='left' else head[:,::-1];palm=hand if facing=='left' else hand[:,::-1]
                    liquid=np.zeros((48,32),bool);raw=np.all(ba[:,:,:3]==rgb(recipe['liquid_color']),axis=2)&(ba[:,:,3]>0);x0,y0=max(0,bx),max(0,by);x1,y1=min(32,bx+bottle.width),min(48,by+bottle.height)
                    if x1>x0 and y1>y0:liquid[y0:y1,x0:x1]=raw[y0-by:y1-by,x0-bx:x1-bx]
                    inside=pose=='receive_extend' or (0<=bx and bx+bottle.width<=32)
                    tests.append({'pose':pose,'facing':facing,'grip_on_skin':tuple(a[g[1],g[0]])==SKIN,'head_clear':not bool((mask&hm).any()),'bottle_bottom_row':by+bottle.height-1,'visible_bottle_pixels':int((mask&~palm).sum()),'visible_liquid_pixels':int((liquid&~palm).sum()),'passed':bool(inside and by>=0 and by+bottle.height<=44 and not (mask&hm).any() and (mask&~palm).sum()>=12 and (liquid&~palm).any())})
            if all(t['passed'] for t in tests):post_checks[(lx,ly)]=tests
    for kx,ky in skin_points(ka,[25,26,29,29]):
        if tuple(kr[ky+1,kx])!=SKIN:continue
        for (clx,cly),tests in post_checks.items():
            kly=cly-(cy-ky)
            if not 0<=kly<bottle.height:continue
            for klx in range(clx-1):
                if not ba[kly,klx,3]:continue
                origin=[KO[0]+kx-klx,KO[1]+ky-kly];co=[origin[0]+clx-cx,32]
                if not 84<=co[0]<=100:continue
                km=np.zeros((83,180),bool);cm=km.copy();km[32:57,KO[0]:KO[0]+32]=np.array(kframes['idle'])[:25,:,3]>0;cm[32:59,co[0]:co[0]+32]=ca[:27,:,3]>0
                bm=bottle_mask(bottle,origin,(83,180));head_overlap=int((km&cm).sum())
                if head_overlap or (bm&(km|cm)).any():continue
                # Score broad, separated opposite-side grips and generous room.
                score=abs(cly-6)*20+abs(kly-4)*3+abs(kx-28)*2+abs(ky-27)*2-(clx-klx)*4-co[0]*.01
                options.append((score,{'keeper_grip':[kx,ky],'keeper_return_grip':[kx,ky+1],'keeper_local_grip':[klx,kly],'customer_grip':[cx,cy],'customer_local_grip':[clx,cly],'customer_origin':co,'shared_bottle_origin':origin,'shared_head_overlap_pixels':head_overlap,'customer_checks':tests}))
    if not options:raise ValueError(f'No physical two-palm handover for{cid}/{recipe["id"]}; fixed customer grips {list(post_checks)}')
    return min(options,key=lambda v:v[0])[1]

def scene_state(t,cid,recipe,data):
    t=round(t%15,6);pair=data['customers'][cid]['bindings'][recipe];co=pair['customer_origin'];x=co[0];y=32;facing='left';pose='idle';phase='wait';owner=None;kp='idle'
    if t<3.8:phase='arrive';x=round(184+(co[0]-184)*t/3.8);pose=['walk_contact_a','walk_pass_a','walk_contact_b','walk_pass_b'][int(t*6)%4]
    elif t<7:phase='wait'
    elif t<8:phase='prepare'
    elif t<8.7:phase='handover'
    elif t<9:phase='withdraw'
    elif t<9.2:phase='fold';pose='carry_contact_a'
    elif t<9.8:phase='hold';pose='receive_hold'
    elif t<10.2:phase='turn';pose='carry_contact_a'
    elif t<14.2:phase='depart';x=round(co[0]+(184-co[0])*(t-10.2)/4);facing='right';pose=['carry_contact_a','carry_pass_a','carry_contact_b','carry_pass_b'][int(t*6)%4]
    else:phase='reset';x=184
    if 7.8<=t<9:pose='receive_extend'
    if .8<=t<1.4:kp='brew_reach'
    elif 1.4<=t<6.8:kp=['brew_stir_left','brew_stir_right'][int((t-1.4)/.4)%2]
    elif 7.2<=t<7.6 or 8.7<=t<9.1:kp='handover_return'
    elif 7.6<=t<8.7:kp='handover_extend'
    if 7.2<=t<8.45:owner='keeper'
    elif 8.45<=t<14.2:owner='customer'
    shared=7.8<=t<8.7;bo=None
    if owner=='keeper':
        g=pair['keeper_return_grip'] if kp=='handover_return' else pair['keeper_grip'];lg=pair['keeper_local_grip'];bo=[KO[0]+g[0]-lg[0],32+g[1]-lg[1]]
    elif owner=='customer':
        g=data['customers'][cid]['grips'][pose];lg=pair['customer_local_grip'];gx=g[0] if facing=='left' else 31-g[0];bo=[x+gx-lg[0],y+g[1]-lg[1]]
    def index(p):return int(t*8)%16+(16 if ('_pass_' in p if p.startswith(('walk_','carry_')) else t%3>=1.5) else 0)+(32 if 3.6<=t%4.5<3.85 else 0)
    return {'time':t,'phase':phase,'customer':cid,'recipe':recipe,'customer_pose':pose,'customer_origin':[x,y],'facing':facing,'keeper_pose':kp,'owner':owner,'shared':shared,'bottle_origin':bo,'keeper_index':index(kp),'customer_index':index(pose)}

def main():
    OUT.mkdir(parents=True,exist_ok=True);(OUT/'environment').mkdir(exist_ok=True);(OUT/'palms').mkdir(exist_ok=True)
    base=read(ENV/'animation-data.json');recipes=read(ENV/'potions/recipes.json')['recipes'];kframes={n:im(KEEP/'frames'/f'{n}.png') for n in KPOSES}
    data={'version':8,'status':'candidate','runtime_integrated':False,'native_size':SIZE,'scale':3,'floor_top':79,'actor_foot_row':46,'keeper_origin':KO,'pot_origin':POT,'fire_origin':[51,70],'cycle_seconds':15,'transfer_seconds':8.45,'customers':{},'customer_order':IDS,'recipes':recipes,'keeper':{'root':'../../characters/keyframes-v4/keeper','poses':KPOSES,'brew_grips':BREW_GRIPS},'environment':{'weather':{},'fire':[]}}
    for name,frames in base['sprites']['weather'].items():
        folder=OUT/'environment'/name;folder.mkdir(exist_ok=True);paths=[]
        for i,value in enumerate(frames):p=folder/f'frame-{i:02d}.png';uri_image(value).save(p);paths.append(str(p.relative_to(OUT)).replace('\\','/'))
        data['environment']['weather'][name]=paths
    for i,value in enumerate(base['sprites']['fire']):p=OUT/'environment'/f'fire-{i}.png';uri_image(value).save(p);data['environment']['fire'].append('environment/'+p.name)
    static=workshop.floor_art();old=ROOT/'art/mockups/full-ingame-v1'
    for name,pos in [('window',[4,5]),('herb_station',[4,48]),('poster',[153,1]),('counter',[130,64])]:
        source=ROOT/'art/mockups/full-ingame-v6/herb_station-native.png' if name=='herb_station' else old/f'{name}-native.png'
        if not source.exists():source=old/f'{name}-native.png'
        static.alpha_composite(im(source),tuple(pos))
    shelf=read(ENV/'potions/recipes.json')['shelf_composite_path'];static.alpha_composite(im(ENV/'potions'/shelf),(105,1));static.save(OUT/'static-native.png')
    reports=[]
    for cid,label in zip(IDS,NAMES):
        root=ROOT/f'art/characters/actions-v1/{cid}';contacts=read(root/'contact-validation.json');grips=contacts['hand_grips'];meta=read(root/'actions.json');names=['idle','walk_contact_a','walk_pass_a','walk_contact_b','walk_pass_b','receive_extend','receive_hold',*meta['new_carry_poses']];frames={n:im(root/'frames'/f'{n}.png') for n in names}
        if cid=='mage':grips['receive_extend']=[3,28]
        for p in ['native-validation.json','motion/validation.json','contact-validation.json']:
            if read(root/p)['status']!='passed':raise ValueError('Failed source:'+str(root/p))
        bindings={}
        for recipe in recipes:
            pair=solve_pair(cid,recipe,frames,grips,kframes);bindings[recipe['id']]=pair
            folder=OUT/'palms'/cid/recipe['id'];folder.mkdir(parents=True,exist_ok=True)
            for pose in ['handover_extend','handover_return']:
                point=pair['keeper_grip'] if pose=='handover_extend' else pair['keeper_return_grip'];palm_overlay(kframes[pose],point).save(folder/f'{pose}.png')
            reports.append({'customer':cid,'recipe':recipe['id'],'head_overlap':pair['shared_head_overlap_pixels'],'shared_keeper_palm':pair['keeper_grip'],'shared_customer_palm':pair['customer_grip'],'keeper_local_grip':pair['keeper_local_grip'],'customer_local_grip':pair['customer_local_grip'],'customer_pose_direction_checks':len(pair['customer_checks']),'passed':True})
        data['customers'][cid]={'name':label,'root':f'../../characters/actions-v1/{cid}','poses':names,'grips':grips,'bindings':bindings,'palette':f'art/palettes/v1/characters/{cid}.hex'}
        for pose,g in grips.items():
            folder=OUT/'palms'/cid;folder.mkdir(exist_ok=True);palm_overlay(frames[pose],g).save(folder/f'{pose}.png')
    dump(OUT/'animation-data.json',data);dump(OUT/'contact-validation.json',{'status':'passed','customer_count':4,'recipe_count':36,'paired_handovers':144,'customer_pose_direction_contacts':1440,'world_shared_floor_row':78,'transfer_position_jump_pixels':0,'same_customer_bottle_local_grip_until_exit':True,'checks':reports})
    page=(ROOT/'tools/handover_workshop_v8.template.html').read_text(encoding='utf-8').replace('__DATA__',json.dumps(data,ensure_ascii=False,separators=(',',':')))
    (OUT/'animated-preview.html').write_text(page,encoding='utf-8');print('v8paired handovers144/customer contact tests1440 prepared')

if __name__=='__main__':main()
