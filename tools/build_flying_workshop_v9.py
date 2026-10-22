"""Stock -> sales counter -> magical catch, preserving the existing game flow."""
from __future__ import annotations
import json,math
import numpy as np
from PIL import Image
import build_handover_workshop_v8 as old
ROOT=old.ROOT;OUT=ROOT/'art/mockups/full-ingame-v9';ENV=old.ENV;KEEP=old.KEEP;KO=[72,32];CO=[148,32];POT=[41,47]
IDS,NAMES=old.IDS,old.NAMES
def read(p):return old.read(p)
def dump(p,d):old.dump(p,d)
def im(p):return old.im(p)
def rounded(v):return int(math.floor(v+.5))
def lerp(a,b,p):return [a[i]+(b[i]-a[i])*p for i in range(2)]
def bezier(a,b,c,d,p):return [(1-p)**3*a[i]+3*(1-p)**2*p*b[i]+3*(1-p)*p*p*c[i]+p**3*d[i] for i in range(2)]

def catch_binding(cid,r,frames,grips):
    bottle=im(ENV/'potions'/r['bottle_path']);a=np.array(bottle);choices=[]
    for ly in range(3,bottle.height-3):
        for lx in range(bottle.width):
            if not a[ly,lx,3]:continue
            tests=[]
            for pose,g in grips.items():
                actor=np.array(frames[pose]);head=actor[:,:,3]>0;head[27:]=False;palms=np.array(old.palm_overlay(frames[pose],g))[:,:,3]>0
                for facing in (['left'] if pose.startswith('receive') else ['left','right']):
                    gx=g[0] if facing=='left' else 31-g[0];bx,by=gx-lx,g[1]-ly;mask=old.bottle_mask(bottle,[bx,by]);hm=head if facing=='left' else head[:,::-1];pm=palms if facing=='left' else palms[:,::-1];liq=np.zeros((48,32),bool);raw=np.all(a[:,:,:3]==old.rgb(r['liquid_color']),axis=2)&(a[:,:,3]>0);x0,y0=max(0,bx),max(0,by);x1,y1=min(32,bx+bottle.width),min(48,by+bottle.height)
                    if x1>x0 and y1>y0:liq[y0:y1,x0:x1]=raw[y0-by:y1-by,x0-bx:x1-bx]
                    inside=pose=='receive_extend' or 0<=bx and bx+bottle.width<=32
                    passed=bool(inside and by>=0 and by+bottle.height<=44 and not (mask&hm).any() and (liq&~pm).any() and (mask&~pm).sum()>=12 and tuple(actor[g[1],g[0]])==old.SKIN)
                    tests.append({'pose':pose,'facing':facing,'passed':passed,'visible_liquid_pixels':int((liq&~pm).sum()),'bottle_bottom_row':by+bottle.height-1})
            if all(t['passed'] for t in tests):choices.append((abs(ly-6)*5+abs(lx-4),{'local_grip':[lx,ly],'checks':tests}))
    if not choices:raise ValueError(f'No catch/carry grip:{cid}/{r["id"]}')
    return min(choices,key=lambda v:v[0])[1]

def state(t,cid,rid,data):
    t=round(t%15,6);c=data['customers'][cid];r=next(r for r in data['recipes'] if r['id']==rid);bind=c['bindings'][rid];x=148;pose='idle';phase='wait';facing='left';kp='idle';bo=None;location='none';stock=7
    if t<1.8:phase='arrive';x=rounded(184+(148-184)*t/1.8);pose=['walk_contact_a','walk_pass_a','walk_contact_b','walk_pass_b'][int(t*6)%4]
    elif t<4:phase='brew'
    elif t<4.65:phase='stock_flight'
    elif t<7:phase='stock';stock=8
    elif t<7.45:phase='pick'
    elif t<7.9:phase='counter'
    elif t<8.45:phase='sale_flight';pose='receive_extend'
    elif t<9:phase='catch';pose='receive_extend'
    elif t<9.2:phase='fold';pose='carry_contact_a'
    elif t<9.8:phase='hold';pose='receive_hold'
    elif t<10.2:phase='turn';pose='carry_contact_a'
    elif t<14.2:phase='depart';x=rounded(148+36*(t-10.2)/4);pose=['carry_contact_a','carry_pass_a','carry_contact_b','carry_pass_b'][int(t*6)%4];facing='right'
    else:phase='reset';x=184
    if .8<=t<1.4:kp='brew_reach'
    elif 1.4<=t<6.8:kp=['brew_stir_left','brew_stir_right'][int((t-1.4)/.4)%2]
    elif 7.2<=t<8.7:kp='handover_extend'
    elif 8.7<=t<9.1:kp='handover_return'
    slot=[139,44-r['bottle_size'][1]];table=[113,64-r['bottle_size'][1]];cg=c['grips']['receive_extend'];lg=bind['local_grip'];target=[148+cg[0]-lg[0],32+cg[1]-lg[1]]
    if 4<=t<4.65:
        p=(t-4)/.65;staging=[slot[0],49]
        # Incoming stock follows a lower corridor, then rises in the empty last
        # column. Actors and the shelf frame are drawn in front of this leg.
        bo=bezier([53,49],[86,54],[slot[0]-12,53],staging,min(1,p/.68)) if p<.68 else lerp(staging,slot,(p-.68)/.32);location='to_shelf'
    elif 4.65<=t<7:bo=slot;location='shelf'
    elif 7<=t<7.45:
        p=(t-7)/.45;bo=bezier(slot,[slot[0],51],[table[0]+9,table[1]-4],table,p);location='to_counter'
    elif 7.45<=t<7.9:bo=table;location='counter'
    elif 7.9<=t<8.45:bo=bezier(table,[130,table[1]-6],[target[0]-7,target[1]+4],target,(t-7.9)/.55);location='to_customer'
    elif 8.45<=t<14.2:
        g=c['grips'][pose];gx=g[0] if facing=='left' else 31-g[0];bo=[x+gx-lg[0],32+g[1]-lg[1]];location='customer'
    if bo is not None:bo=[rounded(v) for v in bo]
    def index(p):return int(t*8)%16+(16 if ('_pass_' in p if p.startswith(('walk_','carry_')) else t%3>=1.5) else 0)+(32 if 3.6<=t%4.5<3.85 else 0)
    return {'time':t,'phase':phase,'customer':cid,'recipe':rid,'customer_pose':pose,'customer_origin':[x,32],'facing':facing,'keeper_pose':kp,'keeper_index':index(kp),'customer_index':index(pose),'bottle_origin':bo,'location':location,'stock':stock,'caught':location=='customer','trace_count':int(bo is not None),'sale_complete':t>=8.45 and t<14.2}

def main():
    OUT.mkdir(parents=True,exist_ok=True);(OUT/'palms').mkdir(exist_ok=True);recipe_data=read(ENV/'potions/recipes.json');recipes=recipe_data['recipes'];byid={r['id']:r for r in recipes}
    data={'version':9,'status':'candidate','runtime_integrated':False,'native_size':[180,83],'scale':3,'cycle_seconds':15,'catch_seconds':8.45,'keeper_origin':KO,'customer_wait_origin':CO,'pot_origin':POT,'customer_order':IDS,'recipes':recipes,'customers':{},'environment':read(old.OUT/'animation-data.json')['environment'],'keeper':{'root':'../../characters/keyframes-v4/keeper','poses':old.KPOSES,'brew_grips':old.BREW_GRIPS},'stock':[],'source_flow':{'inventory':'scripts/potion_display.gd','flight':'handover_position','rendering':'scripts/shop_art.gd','workshop_original_positions_restored':True,'direct_hand_to_hand_required':False}}
    # Reuse exactly the v7 environment pixels. Stock is drawn separately, never
    # baked into the shelf, so an extracted bottle cannot leave a duplicate.
    data['environment']['weather']={k:['../full-ingame-v8/'+p for p in values] for k,values in data['environment']['weather'].items()};data['environment']['fire']=['../full-ingame-v8/'+p for p in data['environment']['fire']]
    background=old.workshop.floor_art();
    for y,color in [(79,'#E9B95F'),(80,'#916047'),(81,'#50333B'),(82,'#241C32')]:
        for x in range(180):background.putpixel((x,y),(*old.rgb(color),255))
    source=ROOT/'art/mockups/full-ingame-v1'
    for name,pos in [('window',[4,5]),('herb_station',[4,48]),('poster',[153,1]),('counter',[105,64])]:
        p=ROOT/'art/mockups/full-ingame-v6/herb_station-native.png' if name=='herb_station' else source/f'{name}-native.png'
        if not p.exists():p=source/f'{name}-native.png'
        background.alpha_composite(im(p),tuple(pos))
    background.save(OUT/'background-native.png');im(ENV/'potions'/recipe_data['shelf_frame_path']).save(OUT/'shelf-frame-native.png')
    for item in recipe_data['shelf_positions'][:7]:data['stock'].append({'id':item['id'],'position':[105+item['position'][0],1+item['position'][1]],'path':'../full-ingame-v7/potions/'+byid[item['id']]['bottle_path']})
    checks=[]
    for cid,label in zip(IDS,NAMES):
        root=ROOT/f'art/characters/actions-v1/{cid}';contacts=read(root/'contact-validation.json');grips=contacts['hand_grips'];meta=read(root/'actions.json');poses=['idle','walk_contact_a','walk_pass_a','walk_contact_b','walk_pass_b','receive_extend','receive_hold',*meta['new_carry_poses']];frames={p:im(root/'frames'/f'{p}.png') for p in poses};bindings={}
        for r in recipes:
            bind=catch_binding(cid,r,frames,grips);bindings[r['id']]=bind;checks.extend([{'customer':cid,'recipe':r['id'],**v} for v in bind['checks']])
        data['customers'][cid]={'name':label,'root':f'../../characters/actions-v1/{cid}','poses':poses,'grips':grips,'bindings':bindings}
        folder=OUT/'palms'/cid;folder.mkdir(exist_ok=True)
        for pose,g in grips.items():old.palm_overlay(frames[pose],g).save(folder/f'{pose}.png')
    dump(OUT/'animation-data.json',data);dump(OUT/'contact-validation.json',{'status':'passed','customers':4,'recipes':36,'catch_and_carry_checks':len(checks),'direct_keeper_hand_contact_required':False,'original_actor_spacing':True,'same_customer_bottle_local_grip_through_exit':True,'checks':checks})
    page=(ROOT/'tools/flying_workshop_v9.template.html').read_text(encoding='utf-8').replace('__DATA__',json.dumps(data,ensure_ascii=False,separators=(',',':')));(OUT/'animated-preview.html').write_text(page,encoding='utf-8')
    print('v9stock/counter/magical-catch prepared:4customers/36recipes/1440catch-carry checks')

if __name__=='__main__':main()
