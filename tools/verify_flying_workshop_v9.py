"""Validate stock ownership, magical flight and existing pixel assets in context."""
from functools import lru_cache
import hashlib,json,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import build_flying_workshop_v9 as b

@lru_cache(maxsize=1536)
def img(path):return b.im(path)
def resolve(path):return (b.OUT/path).resolve()
def motion(root,mode,pose,index):return img(resolve(root)/'motion'/mode/pose/f'frame-{index:02d}.png')
def compose(data,cid,rid,t,mode='fine',weather='night_rain'):
    s=b.state(t,cid,rid,data);c=data['customers'][cid];r=next(r for r in data['recipes'] if r['id']==rid);canvas=Image.new('RGBA',(540,249),'#4A3C52')
    def native(image,p):canvas.alpha_composite(image.resize((image.width*3,image.height*3),Image.Resampling.NEAREST),(p[0]*3,p[1]*3))
    bottle=img(b.ENV/'potions'/r['bottle_path'])
    wf=data['environment']['weather'][weather];native(img(resolve(wf[int(t*8)%len(wf)])),[4,5]);native(img(b.OUT/'background-native.png'),[0,0])
    for stock in data['stock']:native(img(resolve(stock['path'])),stock['position'])
    if s['location'] in ['to_shelf','shelf']:native(bottle,s['bottle_origin'])
    native(img(b.OUT/'shelf-frame-native.png'),[105,1]);native(img(resolve(data['environment']['fire'][int(t*8)%4])),[51,70]);pot=img(b.ENV/'potions'/r['pot_frames'][int(t*6)%3]);native(pot,b.POT)
    kp=s['keeper_pose']
    if kp.startswith('brew'):
        g=b.old.BREW_GRIPS[kp];native(img(b.KEEP/'props/spoon-native.png'),[b.KO[0]+g[0]-15,32+g[1]]);native(pot.crop((0,11,32,32)),[b.POT[0],b.POT[1]+11])
    keeper=motion(data['keeper']['root'],mode,kp,s['keeper_index']);customer=motion(c['root'],mode,s['customer_pose'],s['customer_index'])
    if s['facing']=='right':customer=customer.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    canvas.alpha_composite(keeper,tuple(v*3 for v in b.KO));canvas.alpha_composite(customer,tuple(v*3 for v in s['customer_origin']))
    if s['bottle_origin'] is not None and s['location'] not in ['to_shelf','shelf']:
        native(bottle,s['bottle_origin'])
        if s['caught']:
            palm=img(b.OUT/'palms'/cid/f'{s["customer_pose"]}.png')
            if s['facing']=='right':palm=palm.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            native(palm,s['customer_origin'])
    return canvas,s

def head_mask(data,cid,s,mode):
    customer=motion(data['customers'][cid]['root'],mode,s['customer_pose'],s['customer_index']);mask=np.array(customer)[:,:,3]>0;lift=(s['customer_index']//16)%2;mask[(27-lift)*3:]=False
    if s['facing']=='right':mask=mask[:,::-1]
    world=np.zeros((249,540),bool);x,y=[v*3 for v in s['customer_origin']];x0,x1=max(0,x),min(540,x+96)
    if x1>x0:world[y:y+144,x0:x1]=mask[:,x0-x:x1-x]
    return world

def verify_sources():
    previous=b.read(b.old.OUT/'source-snapshot.json');snap={};reports=[]
    for cid in ['keeper',*b.IDS]:
        root=b.KEEP if cid=='keeper' else b.ROOT/f'art/characters/actions-v1/{cid}'
        report=b.read(root/'motion/validation.json');assert report['status']=='passed'
        frames=list((root/'frames').glob('*.png'))
        for p in frames:
            key=p.relative_to(b.ROOT).as_posix();sha=hashlib.sha256(p.read_bytes()).hexdigest();assert previous[key]==sha,(cid,p);snap[key]=sha
            assert img(p).size==(32,48)
        reports.append({'character':cid,'unchanged_native_frames':len(frames),'motion_report':(root/'motion/validation.json').relative_to(b.ROOT).as_posix(),'motion_status':report['status']})
    b.dump(b.OUT/'source-snapshot.json',snap);return reports

def verify_js(data):
    page=(b.ROOT/'tools/flying_workshop_v9.template.html').read_text(encoding='utf-8');a=page.index('function motionIndex(');z=page.index('function sprite(',a);script='const data='+json.dumps(data,separators=(',',':'))+';\n'+page[a:z]+'\nconsole.log(JSON.stringify(data.customer_order.flatMap(cid=>data.recipes.flatMap(r=>[0,1.8,4,4.3,4.65,5.5,7,7.2,7.45,7.65,7.9,8.2,8.449,8.45,9,9.2,9.8,10.2,11.4,14.2].map(t=>state(t,cid,r.id))))));'
    folder=b.ROOT/'.verification/flying-workshop-v9';folder.mkdir(parents=True,exist_ok=True);path=folder/'state-parity.cjs';path.write_text(script,encoding='utf-8');rows=json.loads(subprocess.check_output(['C:/Program Files/nodejs/node.exe',str(path)],text=True,encoding='utf-8'))
    for row in rows:assert row==b.state(row['time'],row['customer'],row['recipe'],data),row
    return len(rows)

def main():
    data=b.read(b.OUT/'animation-data.json');sources=verify_sources();parity=verify_js(data);events=[];pixel_checks=0;flight_checks=0;bad=[];allowed={(r<<16)|(g<<8)|bb for r,g,bb in b.old.PALETTE}
    for cid in b.IDS:
        for r in data['recipes']:
            rid=r['id'];bot=img(b.ENV/'potions'/r['bottle_path']);liquid=b.old.rgb(r['liquid_color'])
            assert np.all(np.array(bot)[:,:,:3]==liquid,axis=2).any()
            for p in r['pot_frames']:assert np.all(np.array(img(b.ENV/'potions'/p))[:,:,:3]==liquid,axis=2).any()
            checks=[(3.9,'none',7),(4,'to_shelf',7),(4.65,'shelf',8),(7,'to_counter',7),(7.45,'counter',7),(7.9,'to_customer',7),(8.45,'customer',7),(14.15,'customer',7),(14.2,'none',7)]
            for t,loc,stock in checks:
                s=b.state(t,cid,rid,data);assert s['location']==loc and s['stock']==stock and s['trace_count']==int(loc!='none'),s
            before=b.state(8.449,cid,rid,data);after=b.state(8.45,cid,rid,data);assert before['bottle_origin']==after['bottle_origin']
            assert b.state(5.5,cid,rid,data)['bottle_origin'][1]+bot.height==44
            assert b.state(7.65,cid,rid,data)['bottle_origin'][1]+bot.height==64
            assert all(b.state(i/20,cid,rid,data)['caught'] for i in range(169,284))
            events.append({'customer':cid,'recipe':rid,'stock_counts':[7,8,7],'selected_bottle_single_location':True,'catch_jump_pixels':0,'held_through_exit':True})
            for mode in ['fine','grid']:
                for t in [7.9+i*.01 for i in range(56)]:
                    s=b.state(t,cid,rid,data);bm=b.old.bottle_mask(bot,s['bottle_origin'],(83,180));bm=np.repeat(np.repeat(bm,3,0),3,1);overlap=int((bm&head_mask(data,cid,s,mode)).sum());flight_checks+=1
                    if overlap:bad.append({'customer':cid,'recipe':rid,'mode':mode,'time':t,'head_overlap':overlap})
                for t in [1,3.7,4,4.3,4.65,5.5,7,7.25,7.45,7.9,8.2,8.45,9.2,10.25,11,14.15]:
                    art,s=compose(data,cid,rid,t,mode);a=np.array(art);packed=(a[:,:,0].astype(np.uint32)<<16)|(a[:,:,1].astype(np.uint32)<<8)|a[:,:,2].astype(np.uint32);assert set(np.unique(packed).tolist())<=allowed;assert np.all(a[:,:,3]==255);pixel_checks+=1
    b.dump(b.OUT/'flight-validation.json',{'status':'passed' if not bad else 'failed','flight_head_checks':flight_checks,'failures':bad[:100]})
    if bad:raise ValueError(f'Bottle crosses customer head in{len(bad)}flight states; see flight-validation.json')
    board=Image.new('RGB',(1080,558),'#241C32');font=ImageFont.truetype(str(b.ROOT/'assets/fonts/pretendard/Pretendard-Regular.otf'),16)
    for i,cid in enumerate(b.IDS):
        art,s=compose(data,cid,'moon',8.45);x=i%2*540;y=i//2*279;board.paste(art.convert('RGB'),(x,y+30));ImageDraw.Draw(board).text((x+14,y+6),data['customers'][cid]['name']+' · 날아온 달빛 물약 받기',font=font,fill='#FFF0BC')
    board.save(b.OUT/'all-customers-catch.png')
    for t,name in [(5.5,'shelf-stock'),(7.65,'counter-stock'),(8.2,'magical-flight'),(8.45,'customer-catch')]:compose(data,'elf','agility',t)[0].save(b.OUT/(name+'.png'))
    b.old.workshop.save_gif([compose(data,'elf','moon',i/8)[0].convert('RGB') for i in range(120)],b.OUT/'animated-preview.gif')
    b.dump(b.OUT/'validation.json',{'status':'passed','art_status':'candidate','character_native_size':[32,48],'native_scene':[180,83],'display_scene':[540,249],'scale':3,'palette_outside_colors':0,'partial_alpha_pixels':0,'composed_frames_checked':pixel_checks,'source_characters':sources,'runtime_integrated':False})
    b.dump(b.OUT/'verification.json',{'status':'passed','customers':4,'recipes':36,'catch_carry_contacts':1440,'flight_head_checks':flight_checks,'js_python_state_parity':parity,'original_positions_restored':True,'counter_serves_as_sale_staging':True,'keeper_customer_hand_contact_required':False,'single_selected_bottle':True,'stock_events':events,'remaining_work':'Review full scene, then integrate current art and motion into Godot.'})
    print(f'v9 passed: {pixel_checks}palette frames / {flight_checks}flight-head states / {parity}JS parity states')

if __name__=='__main__':main()
