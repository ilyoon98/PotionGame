"""Recipe-aware elf action cycle using shared customer contact/event functions."""
import hashlib,json
from PIL import Image
import build_elf_actions_v1 as b
import publish_traveler_actions_v1 as cycle
ROOT,OUT=b.ROOT,b.OUT
GRIPS={'receive_extend':[6,29],'receive_hold':[16,34],'carry_contact_a':[10,32],'carry_pass_a':[9,33],'carry_contact_b':[9,33],'carry_pass_b':[10,34]}
cycle.b=b;cycle.OUT=OUT;cycle.GRIPS=GRIPS
state=cycle.state

def main():
    for name in ['native-validation.json','motion/validation.json']:
        if b.read(OUT/name)['status']!='passed':raise ValueError('Never publish failed elf art')
    frames={n:Image.open(OUT/'frames'/f'{n}.png').convert('RGBA') for n in b.POSES};report=cycle.contacts(frames)
    b.dump(OUT/'actions.json',{'schema_version':1,'character':'elf','status':'action_animation_candidate','approved_by_user':False,'date':'2026-10-15','native_size':[32,48],'scale':3,'palette':'art/palettes/v1/characters/elf.hex','approved_design':'art/characters/elf-redesign-v2/approval.json','source_keyframes':'art/characters/keyframes-v2/elf/keyframes.json','new_carry_poses':b.CARRY,'frame_count':11,'timeline_seconds':14.2,'timeline':cycle.TIMELINE,'walk_pose_fps':6,'secondary_pose_fps':8,'receive_bottle_event_seconds':8.45,'full_actor_turn':'Whole head/leaf clip/braid/body/arms/legs mirror together; upright independent bottle re-anchors to the mirrored actual skin palm.','body_parts_reassembled':False,'old_face_hook_used':False,'motion':'motion/validation.json','contacts':'contact-validation.json','runtime_integrated':False,'remaining_work':'Simultaneous keeper handover, rogue actions, full mockup and Godot integration.'})
    rows=[{'id':n,'name':label,'path':f'frames/{n}.png','grip':GRIPS.get(n)} for n,label in zip(b.POSES,b.NAMES)];recipes=[{'id':r['id'],'name':r['name'],'liquid_color':r['liquid_color'],'path':'../../../mockups/full-ingame-v7/potions/'+r['bottle_path']} for r in cycle.RECIPES]
    page=(ROOT/'tools/traveler_actions_v1.template.html').read_text(encoding='utf-8').replace('여행자','엘프').replace('traveler-actions-native','elf-actions-native')
    page=page.replace('머리·몸·배낭을','머리·잎 장식·땋은 머리·몸을').replace('갈색 앞머리·침낭 끈의 작은 움직임과 두 눈, 병의 잡는 위치를 확인합니다.','새 잎 정찰복을 유지했습니다. 호흡·깜빡임과 갈색 머리의 움직임, 두 눈과 병 접점을 확인합니다.').replace('다른 손님 행동','고양이 도적 행동')
    page=page.replace('같은32×48과 지정5색. 기존 외형을 유지하고 병을 받치는 걷기4포즈를 추가했습니다.','같은32×48과 지정5색. 승인한 한쪽 어깨 잎 상의·반바지·비대칭 허리 잎을 유지했습니다.')
    page=page.replace('../../keyframes-v2/elf/frames/idle.png','../../keyframes-v1/traveler/frames/idle.png').replace('alt="최신 엘프 공통3배"><figcaption>엘프','alt="여행자 공통3배"><figcaption>여행자')
    tokens={'__FRAMES__':json.dumps(rows,ensure_ascii=False),'__RECIPES__':json.dumps(recipes,ensure_ascii=False),'__TIMELINE__':json.dumps(cycle.TIMELINE,ensure_ascii=False),'__GRIPS__':json.dumps(GRIPS),'__BINDINGS__':json.dumps(report['bindings']),
        '__OPTIONS__':''.join(f'<option value="{r["id"]}">{r["name"]}</option>' for r in recipes),
        '__SWATCHES__':''.join(f'<span><i style="--color:{c}"></i>{name}</span>' for c,name in [(b.INK,'외곽선·눈·부츠'),(b.SKIN,'피부'),(b.BROWN,'머리·가죽'),(b.GREEN,'잎 상의·반바지'),(b.LIME,'잎 장식·허리 잎')]),
        '__BUTTONS__':''.join(f'<button data-pose="{n}" aria-pressed="false">{label}</button>' for n,label in zip(b.POSES,b.NAMES))}
    for key,val in tokens.items():page=page.replace(key,val)
    (OUT/'review.html').write_text(page,encoding='utf-8')
    selected=['generated-carry-01.png','generated-opposite-gait-01.png','generated-passing-b-01.png'];b.dump(OUT/'generation.json',{'mode':'built-in image_gen','selected_sources':[{ 'path':'source/'+n,'sha256':hashlib.sha256((OUT/'source'/n).read_bytes()).hexdigest()} for n in selected],'original_generated_paths':['C:/Users/imtl/.codex/generated_images/01a13372-5c86-7f80-8239-24f6d4687d56/exec-057ac4f9-0848-409d-af33-2db71360df11.png','C:/Users/imtl/.codex/generated_images/01a13372-5c86-7f80-8239-24f6d4687d56/exec-361a543f-5730-48c8-8c2f-5fd5ba087fdf.png','C:/Users/imtl/.codex/generated_images/01a13372-5c86-7f80-8239-24f6d4687d56/exec-da61c2a5-1fbf-4b0b-adae-878b3da6f89e.png'],'prompts':['source/prompt-carry.txt','source/prompt-opposite-gait.txt','source/prompt-passing-b.txt'],'rejected_variant':{'source':'source/generated-carry-02-rejected.png','prompt':'source/prompt-carry-correction.txt','reason':'Opposite gait remained duplicated.'},'whole_body_sources':True,'cross_pose_head_or_limb_splicing':False,'new_palette_colors':0,'registration':'registration.json','semantic_material_masks':'semantic-masks.json','old_keypose_sha256':{n:hashlib.sha256((b.OLD/'frames'/f'{n}.png').read_bytes()).hexdigest() for n in b.common.POSES},'processing_order':['background_cleanup','native_grid','material_ramp_remap','validation']})
    generation=b.read(OUT/'generation.json');generation['reference_inputs']={'generated-carry-01.png':['source/walk-reference-10x.png','source/identity-reference-10x.png'],'generated-opposite-gait-01.png':['source/opposite-gait-reference-10x.png','source/generated-carry-01.png'],'generated-passing-b-01.png':['source/passing-b-reference-10x.png','source/generated-opposite-gait-01.png']};b.dump(OUT/'generation.json',generation)
    rp=ROOT/'art/characters/current-art.json';registry=b.read(rp);registry['date']='2026-10-15';registry['characters']['elf'].update(actions='art/characters/actions-v1/elf/actions.json',motion_review='art/characters/actions-v1/elf/review.html',motion_validation='art/characters/actions-v1/elf/motion/validation.json',actions_status='candidate');registry['characters']['mage']['actions_status']='accepted_for_followup';b.dump(rp,registry)
    sp=ROOT/'art/characters/keyframes-v1/production-status.json';status=b.read(sp);status.update(current_stage='elf_action_animation_review',current_character='elf',current_customer='elf',next_character='rogue',next_customer='rogue',next_stage='rogue_action_animations',completed_customer_action_candidates=['traveler','mage','elf'],remaining_customer_actions=['rogue'],action_animations='keeper_traveler_mage_elf_candidates_rogue_pending')
    status['elf'].update(actions='art/characters/actions-v1/elf/actions.json',motion_review='art/characters/actions-v1/elf/review.html',actions_status='candidate',carry_pose_count=4)
    status['mage'].update(actions_status='accepted_for_followup',actions_acceptance_scope='User accepted mage action preview and requested next elf actions on2026-10-15. Existing unrelated face approval flags are unchanged.');b.dump(sp,status)
    (OUT/'README.md').write_text('''# 엘프 행동 애니메이션 후보 v1

2026-10-15 사용자가 승인된 새 옷·팔레트·32×48을 유지하고 입장/대기/물약 받기/병 든 퇴장, 두 눈/외곽선, 호흡/머리 움직임을 요청했다.

- 기존keyframes-v2/elf의7전신 키포즈는 그대로 보존했다. 병을 든 걷기4전신을 내장image_gen으로 생성하고 통째로 균일 배율 등록했다. 팔/머리/다리를 다른 포즈에서 조립하거나 예전 얼굴 훅으로 덮지 않는다. 소스별 생성 해상도 차이는 전신36행 높이로 정규화한다.
- 처음 생성 시트에서 접지A를 선택하고, 반대 지지발은 별도2전신 시트에서 선택했다. 통과B는 원본 통과B를 참고해 새 전신을 생성했다. 중간4칸 수정본은 반대 다리가 중복되어 제외했다. 모든 원본/프롬프트/참고 및 선택은generation.json과registration.json.
- 승인된 한쪽 어깨 잎 상의·짧은 허리 노출·가죽 띠·반바지·비대칭 허리 잎·부츠, 옆땋은 갈색 머리·잎 장식·뾰족 귀를 유지한다.5색·32×48, 머리 기준22×16/11..26행, 몸통27..39행, 다리40..46행, 발46, 반바지 높이37..39행의 폭10..12를 검사한다. 손2영역과 노출된 어깨/팔/허리/다리의 피부를 구분해 추가 피부 조각을 검사한다.2개 포즈의37행 손목 외곽선 초과1픽셀은 배경 단계에서 정리하고 외곽선을 재생성했다.
- 대기3초 호흡/4.5초 깜빡임과2초 갈색 머리 실루엣/머릿결 움직임을 함께 재생한다. 잎 장식·얼굴·눈 주위를 보존하고, 실제 피부 손·허리·다리·발은 포즈 안에서 고정한다. 표시1픽셀/원본격자1픽셀 모드를 비교한다.
- 입장3.2→대기4→받기3→병 든 퇴장3.2→재방문0.8초.8.45초에 병이 붙고 퇴장 끝까지 유지한다. 퇴장은 머리/장식/땋은 머리/전신을 함께 반전하고 별도 병은 반전된 실제 손에 다시 붙인다.
- 11키포즈/1408움직임의 지정5색·반투명0·두 눈1×2와 대각선 피부 여백1·외곽선/발/손을 검사한다.36물약×6포즈×양방향432접점에서 실제 피부 접점·머리/눈 미가림·병/내용물 노출·원본 내부/병 끝43행 이하를 검사한다.
- 새 행동은 검토 후보이며 고양이 도적·주인공과의 동시 전달·전체 목업/Godot 연동은 후속 단계다.

재현:build_elf_actions_v1.py → build_elf_motion_v1.py → publish_elf_actions_v1.py → verify_elf_actions_v1.py.
''',encoding='utf-8')
    cycle.demo(frames,report);print('Elf review published:11poses/1408motion/432recipe contacts')

if __name__=='__main__':main()
