"""Cat rogue purchase cycle with recipe-specific separate held bottles."""
import hashlib,json
from PIL import Image
import build_rogue_actions_v1 as b
import publish_traveler_actions_v1 as cycle
ROOT,OUT=b.ROOT,b.OUT
GRIPS={'receive_extend':[4,30],'receive_hold':[12,34],'carry_contact_a':[7,33],'carry_pass_a':[7,33],'carry_contact_b':[8,33],'carry_pass_b':[9,33]}
cycle.b=b;cycle.OUT=OUT;cycle.GRIPS=GRIPS
state=cycle.state

def main():
    for path in ['native-validation.json','motion/validation.json']:
        if b.read(OUT/path)['status']!='passed':raise ValueError('Never publish failed rogue motion')
    frames={n:Image.open(OUT/'frames'/f'{n}.png').convert('RGBA') for n in b.POSES};report=cycle.contacts(frames)
    b.dump(OUT/'actions.json',{'schema_version':1,'character':'rogue','status':'action_animation_candidate','approved_by_user':False,'date':'2026-10-15','native_size':[32,48],'scale':3,'palette':'art/palettes/v1/characters/rogue.hex','approved_identity':'art/characters/keyframes-v2/rogue/approval.json','source_keyframes':'art/characters/keyframes-v2/rogue/keyframes.json','new_carry_poses':b.CARRY,'frame_count':11,'timeline_seconds':14.2,'timeline':cycle.TIMELINE,'walk_pose_fps':6,'secondary_pose_fps':8,'receive_bottle_event_seconds':8.45,'full_actor_turn':'Whole head/hair/both ears/scarf/body/tail/legs mirror together; independent upright bottle re-anchors to mirrored actual palm.','body_parts_reassembled':False,'motion':'motion/validation.json','contacts':'contact-validation.json','runtime_integrated':False,'remaining_work':'Simultaneous keeper handover, whole-scene mockup and Godot integration.'})
    rows=[{'id':n,'name':label,'path':f'frames/{n}.png','grip':GRIPS.get(n)} for n,label in zip(b.POSES,b.NAMES)];recipes=[{'id':r['id'],'name':r['name'],'liquid_color':r['liquid_color'],'path':'../../../mockups/full-ingame-v7/potions/'+r['bottle_path']} for r in cycle.RECIPES]
    page=(ROOT/'tools/traveler_actions_v1.template.html').read_text(encoding='utf-8').replace('여행자','고양이 도적').replace('traveler-actions-native','rogue-actions-native').replace('고양이 도적와','고양이 도적과')
    page=page.replace('머리·몸·배낭을','머리·귀·목도리·몸·꼬리를').replace('갈색 앞머리·침낭 끈의 작은 움직임과 두 눈, 병의 잡는 위치를 확인합니다.','호흡·깜빡임과 주황 머리·양쪽 귀·꼬리 움직임을 함께 확인합니다. 귀와 꼬리의 연결부, 두 눈과 병 접점을 유지합니다.').replace('다른 손님 행동·','')
    page=page.replace('같은32×48과 지정5색. 기존 외형을 유지하고 병을 받치는 걷기4포즈를 추가했습니다.','같은32×48과 지정5색. 주황 머리·고양이 귀·꼬리, 붉은 목도리와 검은 의상을 유지했습니다.')
    page=page.replace('../../keyframes-v2/rogue/frames/idle.png','../../keyframes-v1/traveler/frames/idle.png').replace('alt="도적 공통3배"><figcaption>도적','alt="여행자 공통3배"><figcaption>여행자')
    tokens={'__FRAMES__':json.dumps(rows,ensure_ascii=False),'__RECIPES__':json.dumps(recipes,ensure_ascii=False),'__TIMELINE__':json.dumps(cycle.TIMELINE,ensure_ascii=False),'__GRIPS__':json.dumps(GRIPS),'__BINDINGS__':json.dumps(report['bindings']),
        '__OPTIONS__':''.join(f'<option value="{r["id"]}">{r["name"]}</option>' for r in recipes),
        '__SWATCHES__':''.join(f'<span><i style="--color:{c}"></i>{name}</span>' for c,name in [(b.INK,'테두리·눈·검은 의상'),(b.SKIN,'피부'),(b.ORANGE,'주황 머리·귀·꼬리'),(b.LIGHT,'밝은 주황'),(b.SCARF,'붉은 목도리')]),
        '__BUTTONS__':''.join(f'<button data-pose="{n}" aria-pressed="false">{label}</button>' for n,label in zip(b.POSES,b.NAMES))}
    for key,val in tokens.items():page=page.replace(key,val)
    (OUT/'review.html').write_text(page,encoding='utf-8')
    sources=['generated-carry-a-01.png','generated-carry-b-01.png'];b.dump(OUT/'generation.json',{'mode':'built-in image_gen','selected_sources':[{'path':'source/'+n,'sha256':hashlib.sha256((OUT/'source'/n).read_bytes()).hexdigest()} for n in sources],'original_generated_paths':['C:/Users/imtl/.codex/generated_images/01a13372-5c86-7f80-8239-24f6d4687d56/exec-28469d2c-6ab2-4e58-8094-fff59a8fa428.png','C:/Users/imtl/.codex/generated_images/01a13372-5c86-7f80-8239-24f6d4687d56/exec-42763a10-b381-490a-a486-89990dd102b3.png'],'prompts':['source/prompt-carry-a.txt','source/prompt-carry-b.txt'],'references':{'a':['source/gait-a-reference-10x.png','source/identity-reference-10x.png'],'b':['source/gait-b-reference-10x.png','source/identity-reference-10x.png']},'whole_body_sources':True,'cross_pose_head_or_limb_splicing':False,'new_palette_colors':0,'registration':'registration.json','old_keypose_sha256':{n:hashlib.sha256((b.OLD/'frames'/f'{n}.png').read_bytes()).hexdigest() for n in b.common.POSES},'processing_order':['background_cleanup','native_grid','material_ramp_remap','validation']})
    path=ROOT/'art/characters/current-art.json';registry=b.read(path);registry['date']='2026-10-15';registry['characters']['rogue'].update(actions='art/characters/actions-v1/rogue/actions.json',motion_review='art/characters/actions-v1/rogue/review.html',motion_validation='art/characters/actions-v1/rogue/motion/validation.json',actions_status='candidate');registry['characters']['elf']['actions_status']='accepted_for_followup';b.dump(path,registry)
    path=ROOT/'art/characters/keyframes-v1/production-status.json';status=b.read(path);status.update(current_stage='rogue_action_animation_review',current_character='rogue',current_customer='rogue',next_character=None,next_customer=None,next_stage='whole_scene_handover_mockup',completed_customer_action_candidates=['traveler','mage','elf','rogue'],remaining_customer_actions=[],action_animations='keeper_and_all_four_customer_candidates_ready_for_scene_review')
    status['rogue'].update(actions='art/characters/actions-v1/rogue/actions.json',motion_review='art/characters/actions-v1/rogue/review.html',actions_status='candidate',carry_pose_count=4);status['elf'].update(actions_status='accepted_for_followup',actions_acceptance_scope='User accepted elf action preview and requested cat rogue actions on2026-10-15.');b.dump(path,status)
    (OUT/'README.md').write_text('''# 고양이 도적 행동 애니메이션 후보 v1

2026-10-15 사용자가 기존 디자인/팔레트/32×48과 입장·대기·받기·병 든 퇴장, 두 눈/외곽선 및 호흡·머리카락·귀·꼬리 움직임을 요청했다.

- 승인된keyframes-v2/rogue의7전신은 그대로 보존했다. 기존A/B지지 발을 참고해 내장image_gen으로 병 든 걷기4전신을 생성했다. 다른 그림의 머리/팔/다리를 조립하지 않는다. 각 생성 시트의 전신을 균일 배율로 등록한다. B시트는 눈/턱 여백을 유지하는 전신35행 높이, A시트는36행 높이로 정규화하며 머리 기준22×16(실제14..16행)과 발46행을 검사한다.
- 주황 머리/귀/꼬리, 붉은 목도리, 검은 짧은 상의/반바지/장갑/부츠를 유지한다. 지정5색,32×48, 공통3배. 두 눈x10/x14,y23/24의1×2와 대각선 피부 여백1, 외곽선/목/부위 행/반대 지지 발/접지 양발을 확인한다. 피부 손가락이 드러난 장갑2영역과 머리·귀 안쪽/어깨·팔/허리/허벅지를 분류해 추가 피부를 검사한다.
- 호흡3초/깜빡임4.5초와 머리/양쪽 귀/꼬리2초 움직임을 함께 재생한다. 귀 끝은 서로 다른 박자로 움직이고 밑부분은 호흡하는 머리에 고정한다. 꼬리의 말린 끝만 움직이며 엉덩이의 뿌리를 고정한다. 손/허리/발은 각 포즈 안에서 고정한다. 표시1픽셀/원본격자1픽셀 모드가 있다.
- 입장3.2→대기4→받기3→병 든 퇴장3.2→재방문0.8초.8.45초에 병이 붙고 퇴장 끝까지 유지한다. 퇴장은 머리/귀/몸/꼬리를 함께 반전하고 별도 병을 반전된 실제 손에 다시 붙인다.
- 11키포즈/1408움직임에서 지정5색/반투명0/두 눈/피부 여백/외곽선/부착물 연결/손/발을 검사한다.36물약×6손 포즈×양방향432접점에서 실제 피부/병 불투명점·머리 미가림·병과 내용물 노출·프레임 내부/병 끝43행 이하를 검사한다.
- 새 행동은 검토 후보. 손님4명의 개별 행동 후보가 마련됐고, 다음은 주인공과 동시 전달하는 전체 목업 및Godot연동이다. 실제 게임 런타임/저장/자동실행은 수정하지 않는다.

원본/프롬프트/참고:source/와generation.json. 재현:build_rogue_actions_v1.py → build_rogue_motion_v1.py → publish_rogue_actions_v1.py → verify_rogue_actions_v1.py.
''',encoding='utf-8')
    cycle.demo(frames,report);print('Rogue review published:11poses/1408motion/432recipe contacts')

if __name__=='__main__':main()
