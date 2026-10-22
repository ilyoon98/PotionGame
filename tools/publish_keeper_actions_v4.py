"""Publish the corrected keeper review without touching Godot runtime assets."""
from __future__ import annotations
import hashlib,json
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import build_keeper_actions_v4 as b
import build_keeper_review_v2 as contacts

ROOT,OUT=b.ROOT,b.OUT
GRIPS={'brew_reach':[4,21],'brew_stir_left':[5,23],'brew_stir_right':[4,24],'handover_extend':[27,27],'handover_return':[27,28]}
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def save(p,d):b.dump(p,d)

def demo_gif(frames,recipes):
    recipe=next(r for r in recipes if r['id']=='moon');pot=Image.open(ROOT/'art/mockups/full-ingame-v7/potions'/recipe['pot_frames'][0]).convert('RGBA')
    bottle=Image.open(ROOT/'art/mockups/full-ingame-v7/potions'/recipe['bottle_path']).convert('RGBA');spoon=Image.open(OUT/'props/spoon-native.png').convert('RGBA')
    font=ImageFont.truetype(str(ROOT/'assets/fonts/pretendard/Pretendard-Regular.otf'),14)
    boards=[]
    for step in range(120):
        seconds=step/8
        if seconds<5:n='idle';label='IDLE · 호흡 + 모자·망토·앞머리'
        elif seconds<10:
            t=seconds-5;n='brew_reach' if t<.8 else ['brew_stir_left','brew_stir_right'][int((t-.8)/.4)%2];label='제조 · 왼쪽 전신 / 손 접점 고정'
        else:n=['handover_return','handover_extend','handover_extend','handover_extend','handover_return','handover_return'][int((seconds-10)/.45)%6];label='전달 · 허리·다리 고정'
        index=int(seconds*8)%16+(16 if seconds%3>=1.5 else 0)+(32 if 3.6<=seconds%4.5<3.85 else 0)
        im=Image.new('RGBA',(384,232),'#4A3C52');ImageDraw.Draw(im).text((12,7),label,font=font,fill='#FFF0BC')
        off=28;im.alpha_composite(pot.resize((96,96),Image.Resampling.NEAREST),(90,84+off))
        if n.startswith('brew'):
            x,y=GRIPS[n];im.alpha_composite(spoon.resize((54,36),Image.Resampling.NEAREST),((52+x-15)*3,(12+y)*3+off))
            im.alpha_composite(pot.crop((0,11,32,32)).resize((96,63),Image.Resampling.NEAREST),(90,117+off))
        char=Image.open(OUT/f'motion/fine/{n}/frame-{index:02d}.png').convert('RGBA');im.alpha_composite(char,(156,36+off))
        if n.startswith('handover'):
            x,y=GRIPS[n];im.alpha_composite(bottle.resize((bottle.width*3,bottle.height*3),Image.Resampling.NEAREST),((52+x-bottle.width//2)*3,(12+y-4)*3+off))
            palm=Image.open(OUT/f'hand-overlays/{n}.png').convert('RGBA');im.alpha_composite(palm.resize((96,144),Image.Resampling.NEAREST),(156,36+off))
        boards.append(im.convert('RGB'))
    master=[b.rgb(c) for c in (ROOT/'art/palette.hex').read_text().splitlines() if c.strip()]
    # DOM text is the live review; normal-font captions in this separate GIF are
    # permitted review text. Reserve their anti-aliased colors in the GIF palette.
    extra=sorted({tuple(p) for p in np.array(boards[0]).reshape(-1,3)}-set(master))
    palette=sum((list(c) for c in master+extra[:256-len(master)]),[]);palette += [0]*(768-len(palette))
    pal=Image.new('P',(1,1));pal.putpalette(palette)
    gifs=[im.quantize(palette=pal,dither=Image.Dither.NONE) for im in boards]
    gifs[0].save(OUT/'action-preview.gif',save_all=True,append_images=gifs[1:],duration=[120,130]*60,loop=0,disposal=2,optimize=False)

def main():
    if read(OUT/'validation.json')['status']!='passed' or read(OUT/'motion/validation.json')['status']!='passed':raise ValueError('Do not publish failed art')
    frames={n:Image.open(OUT/'frames'/f'{n}.png').convert('RGBA') for n in b.POSES};contacts.OUT=OUT;contacts.GRIPS=GRIPS;contacts.POT_ORIGIN=[30,28]
    head=np.array(frames['idle'])[:,:,3]>0;head[25:]=False
    report=contacts.contacts(frames,head)
    report['head_collision_mask']='The shared idle head/hat silhouette rows0..24; raised working arms are attachments, not head pixels.'
    save(OUT/'contact-validation.json',report)
    if report['status']!='passed':raise ValueError('New hand/prop contacts failed')
    (OUT/'hand-overlays').mkdir(exist_ok=True)
    for n in b.POSES[4:]:contacts.palm_overlay(frames[n],n).save(OUT/'hand-overlays'/f'{n}.png')
    recipe=next(r for r in contacts.RECIPES if r['id']=='moon')
    for n in b.POSES:contacts.scene(frames[n],n,recipe).resize((384,204),Image.Resampling.NEAREST).save(OUT/f'contact-{n}-3x.png')
    rows=[{'id':n,'name':label,'path':f'frames/{n}.png','grip':GRIPS.get(n),'native_size':[32,48],'sheet_rect':[i%3*32,i//3*48,32,48],'facing':'left' if n.startswith('brew') else 'right','eye_points':[[11,19],[13,19]] if n.startswith('brew') else [[17,19],[19,19]]} for i,(n,label) in enumerate(zip(b.POSES,b.NAMES))]
    save(OUT/'keyframes.json',{'schema_version':1,'character':'keeper','version':4,'status':'corrected_keyframes_and_combined_motion_candidate','approved_by_user':False,'frames':rows,'palette':'art/palettes/v1/characters/keeper.hex','scale':3,'native_sheet':'keeper-keyframes-native.png','old_head_overlay_used':False,'whole_body_orientation':'Brewing hat brim/cheeks/collar/torso faceleft; mirrored floppy cone direction. Other arm hangs down.','rig_registration':'rig-registration.json','hair_material_mask':'hair-material-mask.json','contacts':'contact-validation.json','animations_status':'IDLE/brew/handover combined motion preview candidate; customer action animations and game integration remain','motion':'motion/validation.json','runtime_integrated':False})
    recipes=[]
    for r in contacts.RECIPES:
        recipes.append({'id':r['id'],'name':r['name'],'pot':'../../../mockups/full-ingame-v7/potions/'+r['pot_frames'][0],'bottle':'../../../mockups/full-ingame-v7/potions/'+r['bottle_path']})
    refs=[('../../keyframes-v1/traveler/frames/idle.png','여행자'),('../../keyframes-v1/mage/frames/idle.png','여마법사'),('../../keyframes-v2/elf/frames/idle.png','엘프'),('../../keyframes-v2/rogue/frames/idle.png','도적')]
    tokens={'__SWATCHES__':''.join(f'<span><i style="--color:{c}"></i>{name}</span>' for c,name in [(b.INK,'외곽선·눈'),(b.SKIN,'피부·셔츠'),(b.BROWN,'머리·반바지·부츠'),(b.PURPLE,'모자·망토'),(b.GOLD,'장식')]),'__OPTIONS__':''.join(f'<option value="{r["id"]}">{r["name"]}</option>' for r in recipes),'__BUTTONS__':''.join(f'<button data-pose="{i}" aria-pressed="{str(i==0).lower()}">{label}</button>' for i,label in enumerate(b.NAMES)),'__FRAMES__':json.dumps(rows,ensure_ascii=False),'__RECIPES__':json.dumps(recipes,ensure_ascii=False),'__GRIPS__':json.dumps(GRIPS),'__REFS__':''.join(f'<figure><img src="{path}" alt="{label} 공통3배"><figcaption>{label}</figcaption></figure>' for path,label in refs)}
    page=(ROOT/'tools/keeper_actions_v4.template.html').read_text(encoding='utf-8')
    for token,value in tokens.items():page=page.replace(token,value)
    (OUT/'review.html').write_text(page,encoding='utf-8')
    save(OUT/'generation.json',{'mode':'built-in image_gen','use_case':'identity-preserve','selected_source':'source/generated-01.png','original_generated_path':'C:/Users/imtl/.codex/generated_images/01a13372-5c86-7f80-8239-24f6d4687d56/exec-ddb3360a-f800-4831-a771-1efa6fd76b0f.png','source_sha256':hashlib.sha256((OUT/'source/generated-01.png').read_bytes()).hexdigest(),'prompt':'source/prompt-01.txt','references':['art/characters/keyframes-v2/keeper/source/identity-reference-10x.png','art/characters/keyframes-v3/keeper/source/generated-02.png'],'corrections':['Whole left orientation includes hat and collar/torso','Twohands: nonworking arm hangs atside, no handonhip','Brown-only hair material','Shared fixed head/hip/boots per action, registered active-arm negative space','Combined breathing/blink and attached hat/cape/hair motions'],'postprocess':['background_cleanup','native_grid','material_ramp_remap','validation'],'new_palette_colors':0,'runtime_integrated':False})
    registry=read(ROOT/'art/characters/current-art.json');row=registry['characters']['keeper']
    for key in ('neutral','keyframes','review','validation'):
        if key in row:row[key]=row[key].replace('keyframes-v3/keeper','keyframes-v4/keeper')
    row['status']='corrected_keyframes_and_combined_motion_candidate';row['motion']='art/characters/keyframes-v4/keeper/motion/validation.json'
    save(ROOT/'art/characters/current-art.json',registry)
    status=read(ROOT/'art/characters/keyframes-v1/production-status.json');status['current_stage']='keeper_combined_action_preview_review';status['current_character']='keeper';status['next_stage']='customer_action_animations';status['runtime_integrated']=False
    status.setdefault('keeper',{}).update(status=row['status'],keyframes='art/characters/keyframes-v4/keeper/keyframes.json',review='art/characters/keyframes-v4/keeper/review.html',validation='art/characters/keyframes-v4/keeper/validation.json',contacts='art/characters/keyframes-v4/keeper/contact-validation.json',motion='art/characters/keyframes-v4/keeper/motion/validation.json',actions_status='IDLE/brew/handover combined candidate motion',user_feedback_resolved=['Whole facing includes hat/body','Nonworking arm hangs down','Brown hair materials','Stationary handover waist and feet','Combined IDLE/hat/cape/hair preview'])
    status['action_animations']='keeper_combined_candidate_customers_pending'
    status['latest_keeper']='art/characters/keyframes-v4/keeper/review.html';status['keeper_action_animations']='combined_motion_candidate';save(ROOT/'art/characters/keyframes-v1/production-status.json',status)
    plan_path=ROOT/'art/palettes/v1/production-plan.json';plan=read(plan_path);plan['latest_keeper_keyframes']='art/characters/keyframes-v4/keeper/keyframes.json';plan['latest_keeper_motion']='art/characters/keyframes-v4/keeper/motion/validation.json';plan['next_stage']='customer_action_animations';save(plan_path,plan)
    old=ROOT/'art/characters/keyframes-v3/keeper/keyframes.json';meta=read(old);meta['status']='superseded_whole_orientation_material_and_motion_rejected';meta['replacement']='art/characters/keyframes-v4/keeper/review.html';save(old,meta)
    (OUT/'README.md').write_text('''# 남자 주인공 행동 수정 v4\n\n사용자 지적: 제조는 얼굴만 왼쪽, 모자는 이전 방향 / 반대손이 허리에 올라감 / 전달 머리에 보라색 / 전달 중 허리가 앞뒤로 움직임 / 모자가 정지 / IDLE 누락.\n\n- 새 전신 시트로 제조의 모자·얼굴·목·몸 방향을 함께 맞췄다. 기존 v3 머리 방향만 수정하는 방식을 폐기했다. 반대팔은 옆으로 내려둔다.\n- 팔레트5색뿐 아니라 머리 재질을 별도로 검사한다. 새 갈색 머리에는 보라색이 없다.\n- 전달은 같은 머리/허리/반바지/다리/발을 쓰며 완전한 작업 팔 영역(투명 공간 포함)만 등록한다. 이전 다른 포즈의 독립 팔/머리 덧붙임을 쓰지 않는다.\n- 기존 IDLE 방식(위아래 호흡3초, 깜빡임4.5초)을 새 전신으로 다시 만들고 검토 화면에 직접 연결했다. 키포즈만 반복하는 화면에서 끝내지 않는다.\n- 모자 끝의 실루엣과 망토 끝, 갈색 앞머리 결을 같은 루프에서 움직인다. 모자 착용점과 손 접점, 허리, 발을 고정한다.\n- 원본32×48/3배. 각6포즈×2모드×64상태=768움직임 검사. 표시1픽셀 부분 움직임은1/3원본픽셀, 원본 격자는1원본픽셀. 색 보간/반투명 없음. 눈은 열림1×2 / 감김1×1 두개다.\n- 36물약 제조108/전달72조합 검사. 머리 충돌에는 팔 부착물을 제외한 실제 머리/모자 마스크를 쓴다. 병과 국자는 별도 에셋이며 물약별 색을 유지한다.\n- 새 키포즈/움직임은 검토 후보. 다른 손님 행동 애니메이션과 Godot 통합은 남았다. 기존 저장/자동실행/런타임 에셋은 수정하지 않았다.\n\n재현: build_keeper_actions_v4.py → build_keeper_motion_v4.py → publish_keeper_actions_v4.py → audit_character_art_v1.py → build_palette_catalog_v1.py. 최초 생성 원본과 builtin image_gen 프롬프트는 source/ 및 generation.json.\n''',encoding='utf-8')
    demo_gif(frames,contacts.RECIPES)
    print('Published keeper v4: IDLE + brew + handover, contacts108/72 passed; runtime untouched')

if __name__=='__main__':main()
