"""Recipe-aware traveler action cycle, local HTML and visual evidence."""
from __future__ import annotations
import hashlib,json,math
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import build_traveler_actions_v1 as b

ROOT,OUT=b.ROOT,b.OUT
GRIPS={'receive_extend':[4,30],'receive_hold':[13,33],**{n:[9,32] for n in b.CARRY}}
RECIPES=b.read(ROOT/'art/mockups/full-ingame-v7/potions/recipes.json')['recipes']
TIMELINE=[{'id':'arrive','name':'입장','start':0,'end':3.2},{'id':'wait','name':'대기','start':3.2,'end':7.2},{'id':'receive','name':'물약 받기','start':7.2,'end':10.2},{'id':'depart','name':'병을 든 퇴장','start':10.2,'end':13.4},{'id':'reset','name':'다음 방문 준비','start':13.4,'end':14.2}]

def hand_overlay(im,point):
    a=np.array(im);x,y=point;roi=np.zeros((48,32),bool);roi[max(0,y-3):min(48,y+4),max(0,x-3):min(32,x+4)]=True
    skin=np.all(a==b.RGBA['skin'],axis=2)&roi;near=np.zeros_like(skin)
    for dy,dx in ((-1,0),(1,0),(0,-1),(0,1)):near|=np.roll(np.roll(skin,dy,0),dx,1)
    keep=skin|(near&roi&np.all(a==b.RGBA['ink'],axis=2));o=np.zeros_like(a);o[keep]=a[keep];return Image.fromarray(o)

def contacts(frames):
    checks=[];bindings={};overlays={}
    for n,(gx,gy) in GRIPS.items():
        a=np.array(frames[n]);head=a[:,:,3]>0;head[27:]=False
        if tuple(a[gy,gx])!=b.RGBA['skin']:raise ValueError(f'Anchor is not on peach palm: {n}/{gx,gy}')
        overlay=hand_overlay(frames[n],[gx,gy]);overlays[n]=overlay;hand=np.array(overlay)[:,:,3]>0
        for r in RECIPES:
            bottle=Image.open(ROOT/'art/mockups/full-ingame-v7/potions'/r['bottle_path']).convert('RGBA');ba=np.array(bottle)
            preferred=8 if n=='receive_hold' and bottle.height==16 else 4 if n=='receive_extend' else 6
            choices=sorted(range(3,bottle.height-3),key=lambda y:abs(y-preferred));selected=None
            for ly in choices:
                lx=bottle.width//2;bx,by=gx-lx,gy-ly
                if min(bx,by)<0 or bx+bottle.width>32 or by+bottle.height>44 or not ba[ly,lx,3]:continue
                mask=np.zeros((48,32),bool);mask[by:by+bottle.height,bx:bx+bottle.width]=ba[:,:,3]>0
                if (mask&head).any():continue
                selected=(lx,ly,bx,by,mask);break
            if selected is None:raise ValueError(f'Bottle needs a new hand pose, not a hidden face: {n}/{r["id"]}')
            lx,ly,bx,by,mask=selected;visible=int((mask&~hand).sum());liquid=np.zeros((48,32),bool);liquid[by:by+bottle.height,bx:bx+bottle.width]=np.all(ba[:,:,:3]==b.rgb(r['liquid_color']),axis=2)&(ba[:,:,3]>0)
            binding={'origin':[bx,by],'local_grip':[lx,ly],'hand_grip':[gx,gy],'bottle_size':list(bottle.size)};bindings.setdefault(n,{})[r['id']]=binding
            for facing in ('left','right'):
                # A full-actor turn mirrors the character and palm; the separate
                # upright bottle is re-anchored, never turned upside down.
                mgx=gx if facing=='left' else 31-gx;mbx=mgx-lx
                mirror_hand=hand if facing=='left' else hand[:,::-1];mirror_head=head if facing=='left' else head[:,::-1]
                mm=np.zeros_like(mask);mm[by:by+bottle.height,mbx:mbx+bottle.width]=ba[:,:,3]>0
                contents=np.zeros_like(mask);contents[by:by+bottle.height,mbx:mbx+bottle.width]=liquid[by:by+bottle.height,bx:bx+bottle.width]
                clear=not bool((mm&mirror_head).any());visible=int((mm&~mirror_hand).sum());liquid_visible=int((contents&~mirror_hand).sum())
                checks.append({'pose':n,'recipe':r['id'],'facing':facing,'grip_on_actual_skin':True,'bottle_grip_opaque':True,'head_and_eyes_clear':clear,'bottle_inside32x48':0<=mbx and mbx+bottle.width<=32,'bottle_bottom_below_row44':False,'bottle_bottom_row':by+bottle.height-1,'visible_bottle_pixels':visible,'visible_contents_pixels':liquid_visible,'passed':bool(clear and visible>=12 and liquid_visible>0 and 0<=mbx and mbx+bottle.width<=32)})
    report={'status':'passed' if all(c['passed'] for c in checks) else 'failed','recipe_count':36,'poses':6,'facing_directions':2,'tested_combinations':len(checks),'hand_grips':GRIPS,'bindings':bindings,'checks':checks,'bottle_is_separate':True,'motion_palms_pinned_proof':'motion/validation.json','scope':'Customer action/potion contacts only. Simultaneous keeper handover is for the later whole-scene integration.'}
    b.dump(OUT/'contact-validation.json',report)
    if report['status']!='passed':raise ValueError('Traveler bottle visibility/facing checks failed')
    folder=OUT/'hand-overlays';folder.mkdir(exist_ok=True)
    for n,im in overlays.items():im.save(folder/f'{n}.png')
    return report

def state(seconds,action='cycle'):
    if action=='cycle':
        t=seconds%14.2;segment=next(row for row in TIMELINE if row['start']<=t<row['end']);name=segment['id'];p=(t-segment['start'])/(segment['end']-segment['start'])
    else:name=action;p=(seconds%3.2)/3.2;t=seconds
    x=48;facing='left';held=False
    if name=='arrive':x=132-84*p;pose=b.common.POSES[1+int(seconds*6)%4]
    elif name=='wait':pose='idle'
    elif name=='receive':
        rt=round(p*3,6) if action=='cycle' else round(seconds%3,6)
        pose='idle' if rt<.35 else 'receive_extend' if rt<1.65 else 'receive_hold'
        held=rt>=1.25
    elif name=='depart':x=48+84*p;pose=b.CARRY[int(seconds*6)%4];facing='right';held=True
    else:x=140;pose='idle'
    phase=int(seconds*8)%16;lifted=('_pass_' in pose) if pose.startswith(('walk_','carry_')) else seconds%3>=1.5
    index=phase+(16 if lifted else 0)+(32 if 3.6<=seconds%4.5<3.85 else 0)
    return {'action':name,'pose':pose,'x':round(x),'y':12,'facing':facing,'held':held,'index':index,'elapsed':round(seconds,3)}

def demo(frames,report):
    row=next(r for r in RECIPES if r['id']=='moon');bottle=Image.open(ROOT/'art/mockups/full-ingame-v7/potions'/row['bottle_path']).convert('RGBA');font=ImageFont.truetype(str(ROOT/'assets/fonts/pretendard/Pretendard-Regular.otf'),14)
    labels={r['id']:r['name'] for r in TIMELINE};gif=[]
    for sample in range(114):
        s=state(sample/8);n=s['pose'];im=Image.new('RGBA',(384,232),'#4A3C52');d=ImageDraw.Draw(im);d.line((0,205,383,205),fill='#C99463',width=3);d.text((12,7),labels[s['action']],font=font,fill='#FFF0BC')
        sprite=Image.open(OUT/f'motion/fine/{n}/frame-{s["index"]:02d}.png').convert('RGBA')
        if s['facing']=='right':sprite=sprite.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        pos=(s['x']*3,s['y']*3+28);im.alpha_composite(sprite,pos)
        if s['held'] and n in GRIPS:
            binding=report['bindings'][n][row['id']];gx,gy=GRIPS[n];gx=31-gx if s['facing']=='right' else gx;bx,by=gx-binding['local_grip'][0],gy-binding['local_grip'][1]
            im.alpha_composite(bottle.resize((bottle.width*3,bottle.height*3),Image.Resampling.NEAREST),((s['x']+bx)*3,(s['y']+by)*3+28))
            palm=Image.open(OUT/f'hand-overlays/{n}.png').convert('RGBA').resize((96,144),Image.Resampling.NEAREST)
            if s['facing']=='right':palm=palm.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            im.alpha_composite(palm,pos)
        gif.append(im.convert('RGB'))
    master=[b.rgb(c) for c in (ROOT/'art/palette.hex').read_text(encoding='utf-8').splitlines() if c.strip()];extra=sorted({tuple(p) for p in np.array(gif[0]).reshape(-1,3)}-set(master));palette=sum((list(c) for c in master+extra[:256-len(master)]),[]);palette+=[0]*(768-len(palette));pal=Image.new('P',(1,1));pal.putpalette(palette)
    quant=[im.quantize(palette=pal,dither=Image.Dither.NONE) for im in gif];quant[0].save(OUT/'action-cycle.gif',save_all=True,append_images=quant[1:],duration=[120,130]*57,loop=0,disposal=2,optimize=False)

def main():
    if b.read(OUT/'native-validation.json')['status']!='passed' or b.read(OUT/'motion/validation.json')['status']!='passed':raise ValueError('Never publish failed traveler motion')
    frames={n:Image.open(OUT/'frames'/f'{n}.png').convert('RGBA') for n in b.POSES};report=contacts(frames)
    metadata={'schema_version':1,'character':'traveler','status':'action_animation_candidate','approved_by_user':False,'date':'2026-10-15','native_size':[32,48],'scale':3,'palette':'art/palettes/v1/characters/traveler.hex','source_keyframes':'art/characters/keyframes-v1/traveler/keyframes.json','new_carry_poses':b.CARRY,'frame_count':len(frames),'timeline_seconds':14.2,'timeline':TIMELINE,'walk_pose_fps':6,'secondary_pose_fps':8,'receive_bottle_event_seconds':8.45,'full_actor_turn':'Horizontal mirror of whole character, hair/backpack/arms/feet together; upright bottle re-anchored to mirrored palm.','body_parts_reassembled':False,'motion':'motion/validation.json','contacts':'contact-validation.json','runtime_integrated':False,'remaining_feedback':'Female impression remains deferred at user request. Simultaneous keeper handover and runtime event integration remain.'}
    b.dump(OUT/'actions.json',metadata)
    rows=[{'id':n,'name':label,'path':f'frames/{n}.png','grip':GRIPS.get(n)} for n,label in zip(b.POSES,b.NAMES)];recipes=[{'id':r['id'],'name':r['name'],'liquid_color':r['liquid_color'],'path':'../../../mockups/full-ingame-v7/potions/'+r['bottle_path']} for r in RECIPES]
    page=(ROOT/'tools/traveler_actions_v1.template.html').read_text(encoding='utf-8')
    tokens={'__FRAMES__':json.dumps(rows,ensure_ascii=False),'__RECIPES__':json.dumps(recipes,ensure_ascii=False),'__TIMELINE__':json.dumps(TIMELINE,ensure_ascii=False),'__GRIPS__':json.dumps(GRIPS),'__BINDINGS__':json.dumps(report['bindings']),
        '__OPTIONS__':''.join(f'<option value="{r["id"]}">{r["name"]}</option>' for r in recipes),
        '__SWATCHES__':''.join(f'<span><i style="--color:{c}"></i>{label}</span>' for c,label in [(b.INK,'외곽선·눈'),(b.SKIN,'피부'),(b.SHIRT,'셔츠·침낭'),(b.BROWN,'갈색 재질'),(b.HONEY,'밝은 갈색')]),
        '__BUTTONS__':''.join(f'<button data-pose="{n}" aria-pressed="false">{label}</button>' for n,label in zip(b.POSES,b.NAMES))}
    for token,value in tokens.items():page=page.replace(token,value)
    (OUT/'review.html').write_text(page,encoding='utf-8')
    b.dump(OUT/'generation.json',{'mode':'built-in image_gen','source':'source/generated-carry-01.png','original_generated_path':'C:/Users/imtl/.codex/generated_images/01a13372-5c86-7f80-8239-24f6d4687d56/exec-7a38e2c4-1830-410c-8c2c-ba0fe278b431.png','source_sha256':hashlib.sha256((OUT/'source/generated-carry-01.png').read_bytes()).hexdigest(),'prompt':'source/prompt-carry.txt','references':['source/walk-edit-reference-10x.png','source/carry-reference-10x.png'],'whole_bodies':True,'new_palette_colors':0,'old_keypose_sha256':{n:hashlib.sha256((b.OLD/'frames'/f'{n}.png').read_bytes()).hexdigest() for n in b.common.POSES},'processing_order':['background_cleanup','native_grid','material_ramp_remap','validation']})
    registry_path=ROOT/'art/characters/current-art.json';registry=b.read(registry_path);registry['date']='2026-10-15';registry['characters']['traveler'].update(actions='art/characters/actions-v1/traveler/actions.json',motion_review='art/characters/actions-v1/traveler/review.html',motion_validation='art/characters/actions-v1/traveler/motion/validation.json',actions_status='candidate');b.dump(registry_path,registry)
    status_path=ROOT/'art/characters/keyframes-v1/production-status.json';status=b.read(status_path)
    status.update(current_stage='traveler_action_animation_review',current_character='traveler',current_customer='traveler',next_character='mage',next_customer='mage',next_stage='mage_action_animations',completed_customer_action_candidates=['traveler'],remaining_customer_actions=['mage','elf','rogue'])
    status['traveler'].update(actions='art/characters/actions-v1/traveler/actions.json',motion_review='art/characters/actions-v1/traveler/review.html',actions_status='candidate',carry_pose_count=4)
    status['action_animations']='keeper_and_traveler_candidates_other_customers_pending';b.dump(status_path,status)
    (OUT/'README.md').write_text('''# 여행자 행동 애니메이션 후보 v1\n\n2026-10-15 사용자의 “계속진행해” 지시에 따라 주인공 다음 여행자의 행동을 연결했다. 여성 인상 수정은 기존 요청대로 보류하며 디자인 승인으로 바꾸지 않는다.\n\n- 기존7키포즈는 그대로 복사하고, 내장 image_gen으로 빈손이 아닌 병 받침 자세의 걷기4전신을 새로 생성했다. 머리/몸통/다리를 다른 포즈에서 조립하지 않는다. 생성 원본·참고·프롬프트는 source/ 및 generation.json.\n- 원본32×48, 머리11..26/몸통27..39/다리40..46/발46. 공통3배, 각자 지정5색. 두 눈10/14,y22/23의1×2와 피부 여백1픽셀, 외곽선/불투명도를 검사한다.\n- IDLE 상하 호흡3초·깜빡임4.5초, 갈색 앞머리와 침낭 안쪽 가죽 끈 움직임2초를 합쳤다. 원본격자1픽셀과 표시1픽셀 부분 움직임을 비교한다. 손/허리/발과 외곽선은 각 포즈 안에서 고정한다.\n- 입장3.2초 → 대기4초 → 받기3초 → 병 든 퇴장3.2초 → 재방문 준비0.8초. 물약 부착 이벤트8.45초, 받기 전에는 빈손, 이후에는 퇴장 끝까지 유지한다. 퇴장은 전신 전체 방향을 함께 돌린다.\n- 물약36종×6손 포즈×양방향432조합에서 실제 피부 접점/병 불투명 접점/머리·눈 미가림/병·액체 노출/원본 내부와44행 위 병 끝을 확인한다. 병은 독립 에셋으로 레시피 색을 유지한다.\n- 11키포즈/1408부분움직임과 행동 타이밍을 검사하는 후보이다. 주인공과의 동시 전달 접점, 다른 손님 행동, 전체 목업/Godot 연동은 후속 단계다.\n\n재현: build_traveler_actions_v1.py → build_traveler_motion_v1.py → publish_traveler_actions_v1.py. 기존 키포즈/게임 저장/Windows자동실행/런타임 파일은 수정하지 않는다.\n''',encoding='utf-8')
    demo(frames,report);print('Traveler action review published:11poses,1408motion frames,432recipe/facing contacts')

if __name__=='__main__':main()
