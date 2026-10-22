"""Reuse the proven customer event/contact renderer for the mage candidate."""
from __future__ import annotations
import hashlib,json
from PIL import Image
import build_mage_actions_v1 as b
import publish_traveler_actions_v1 as cycle

ROOT,OUT=b.ROOT,b.OUT
GRIPS={'receive_extend':[4,29],'receive_hold':[12,32],**{n:[9,32] for n in b.CARRY}}
# Only the reusable functions are invoked; the traveler publisher's main and
# its traveler-specific registry writes are never called.
cycle.b=b;cycle.OUT=OUT;cycle.GRIPS=GRIPS
state=cycle.state

def main():
    for path in ['native-validation.json','motion/validation.json']:
        if b.read(OUT/path)['status']!='passed':raise ValueError('Never publish failed mage motion')
    frames={n:Image.open(OUT/'frames'/f'{n}.png').convert('RGBA') for n in b.POSES};report=cycle.contacts(frames)
    meta={'schema_version':1,'character':'mage','status':'action_animation_candidate','approved_by_user':False,'date':'2026-10-15','native_size':[32,48],'scale':3,'palette':'art/palettes/v1/characters/mage.hex','source_keyframes':'art/characters/keyframes-v1/mage/keyframes.json','new_carry_poses':b.CARRY,'frame_count':11,'timeline_seconds':14.2,'timeline':cycle.TIMELINE,'walk_pose_fps':6,'secondary_pose_fps':8,'receive_bottle_event_seconds':8.45,'full_actor_turn':'Horizontal mirror of whole hat/head/hair/robe/arms/feet together; upright bottle re-anchored to mirrored actual palm.','hat_origin':[0,4],'hat_head_seat':[14,14],'hat_local_seat':[14,10],'hat_seat_moves_with_head_breath':True,'body_parts_reassembled':False,'approved_hat_layer_reused':True,'motion':'motion/validation.json','contacts':'contact-validation.json','runtime_integrated':False,'remaining_work':'Simultaneous keeper handover, remaining customer actions, full-scene and Godot integration.'}
    b.dump(OUT/'actions.json',meta)
    rows=[{'id':n,'name':label,'path':f'frames/{n}.png','grip':GRIPS.get(n)} for n,label in zip(b.POSES,b.NAMES)]
    recipes=[{'id':r['id'],'name':r['name'],'liquid_color':r['liquid_color'],'path':'../../../mockups/full-ingame-v7/potions/'+r['bottle_path']} for r in cycle.RECIPES]
    page=(ROOT/'tools/traveler_actions_v1.template.html').read_text(encoding='utf-8')
    page=page.replace('여행자','여마법사').replace('traveler-actions-native','mage-actions-native').replace('머리·몸·배낭','모자·머리·몸·로브').replace('갈색 앞머리·침낭 끈의 작은 움직임','정수리에 붙은 모자 챙·움직이는 모자 끝과 긴 머리카락').replace('다른 손님 행동','엘프·도적 행동')
    page=page.replace('모자·머리·몸·로브을','모자·머리·몸·로브를').replace('정수리에 붙은 모자 챙·움직이는 모자 끝과 긴 머리카락과 두 눈, 병의 잡는 위치를 확인합니다.','모자 챙의 착용점과 모자 끝·긴 머리의 움직임, 두 눈과 병을 잡는 위치를 확인합니다.')
    page=page.replace('../../keyframes-v1/mage/frames/idle.png','../../keyframes-v1/traveler/frames/idle.png').replace('alt="여마법사 공통3배"><figcaption>여마법사','alt="여행자 공통3배"><figcaption>여행자')
    tokens={'__FRAMES__':json.dumps(rows,ensure_ascii=False),'__RECIPES__':json.dumps(recipes,ensure_ascii=False),'__TIMELINE__':json.dumps(cycle.TIMELINE,ensure_ascii=False),'__GRIPS__':json.dumps(GRIPS),'__BINDINGS__':json.dumps(report['bindings']),
        '__OPTIONS__':''.join(f'<option value="{r["id"]}">{r["name"]}</option>' for r in recipes),
        '__SWATCHES__':''.join(f'<span><i style="--color:{c}"></i>{label}</span>' for c,label in [(b.INK,'외곽선·눈'),(b.SKIN,'피부'),(b.DARK,'짙은 보라'),(b.PURPLE,'머리·모자·로브'),(b.BROWN,'띠·책·부츠')]),
        '__BUTTONS__':''.join(f'<button data-pose="{n}" aria-pressed="false">{label}</button>' for n,label in zip(b.POSES,b.NAMES))}
    for token,value in tokens.items():page=page.replace(token,value)
    (OUT/'review.html').write_text(page,encoding='utf-8')
    b.dump(OUT/'generation.json',{'mode':'built-in image_gen','source':'source/generated-carry-01.png','original_generated_path':'C:/Users/imtl/.codex/generated_images/01a13372-5c86-7f80-8239-24f6d4687d56/exec-5aa781f2-ece0-4d3c-91f6-540f32d88d2b.png','source_sha256':hashlib.sha256((OUT/'source/generated-carry-01.png').read_bytes()).hexdigest(),'prompt':'source/prompt-carry.txt','references':['source/body-walk-reference-10x.png','source/identity-reference-10x.png'],'whole_body_carry_sources':True,'hat_layer':'layers/hat.png','hat_sha256':hashlib.sha256((b.OLD/'layers/hat.png').read_bytes()).hexdigest(),'hat_origin':[0,4],'new_palette_colors':0,'old_keypose_sha256':{n:hashlib.sha256((b.OLD/'frames'/f'{n}.png').read_bytes()).hexdigest() for n in b.common.POSES},'processing_order':['background_cleanup','native_grid','material_ramp_remap','validation']})
    registry_path=ROOT/'art/characters/current-art.json';registry=b.read(registry_path)
    registry['date']='2026-10-15';registry['characters']['mage'].update(actions='art/characters/actions-v1/mage/actions.json',motion_review='art/characters/actions-v1/mage/review.html',motion_validation='art/characters/actions-v1/mage/motion/validation.json',actions_status='candidate')
    registry['characters']['traveler']['actions_status']='accepted_for_followup';b.dump(registry_path,registry)
    status_path=ROOT/'art/characters/keyframes-v1/production-status.json';status=b.read(status_path)
    status.update(current_stage='mage_action_animation_review',current_character='mage',current_customer='mage',next_character='elf',next_customer='elf',next_stage='elf_action_animations',completed_customer_action_candidates=['traveler','mage'],remaining_customer_actions=['elf','rogue'],action_animations='keeper_traveler_mage_candidates_elf_rogue_pending')
    status['mage'].update(actions='art/characters/actions-v1/mage/actions.json',motion_review='art/characters/actions-v1/mage/review.html',actions_status='candidate',carry_pose_count=4)
    status['traveler'].update(actions_status='accepted_for_followup',actions_followup_authorized_by='좋아 다음 여마법사도 진행해. 팔레트랑32×48규격 지키고 모자 안 뜨게, 두 눈이랑 외곽선도 확인해서 입장·대기·물약 받기·병 들고 퇴장까지 연결해줘',actions_acceptance_scope='Action cycle accepted for followup; deferred feminine appearance feedback remains deferred.')
    b.dump(status_path,status)
    (OUT/'README.md').write_text('''# 여마법사 행동 애니메이션 후보 v1

2026-10-15 사용자가 다음 여마법사의 팔레트/32×48/모자/두 눈/외곽선과 입장·대기·물약 받기·병 든 퇴장 연결을 요청했다.

- 기존7전신 키포즈는 픽셀/파일 그대로 보존했다. 병 든 걷기4전신을 내장 image_gen으로 생성하고 같은 배율로 등록했다. 다른 포즈의 머리/몸통/다리를 조립하지 않았다. 원본/프롬프트/참조와 처리 기록은source/ 및generation.json.
- 지정5색,32×48, 머리 기준22×16/11..26행, 몸통27..39행, 다리·부츠40..46행, 발46행. 긴 머리와 별도32×14 모자는 부착물이다.
- 기존 승인 모자를 원점[0,4]에 합성해 모자 내부 착용점[14,10]과 머리[14,14]를 맞춘다. 정수리 중첩40픽셀 이상과 착용점을 검사한다. 호흡 시 모자와 머리가 함께1원본픽셀 상승하며 챙/착용점은 같이 붙어 있다. 끝부분만 흔들리고 브리지 행을 고정한다.
- 호흡3초·깜빡임4.5초·모자 끝/긴 머리 움직임2초를 동시에 재생한다. 표시1픽셀/원본격자1픽셀 모드를 비교한다. 각 포즈 안에서 실제 피부 손/허리/발을 고정한다.
- 입장3.2 → 대기4 → 받기3 → 병 든 퇴장3.2 → 재방문0.8초.8.45초에 병이 붙고 퇴장 끝까지 유지한다. 퇴장은 모자부터 부츠까지 전신을 함께 반전하며 독립 병을 실제 손에 다시 붙인다.
- 11키포즈/1408움직임에서5색·반투명0·두 눈1×2와 피부 여백1·끊기지 않는 외곽선·모자착용·발/손을 검사한다.36물약×6포즈×양방향432조합에서 실제 손/병 불투명 접점·머리/눈 미가림·병/내용물 노출·프레임 안쪽/병 끝43행 이하를 검사한다.
- 새 행동은 검토 후보. 주인공과의 동시 전달·엘프/도적·전체 목업·Godot 적용은 남았다. 게임 런타임이나 저장/자동실행은 수정하지 않는다.

재현:build_mage_actions_v1.py → build_mage_motion_v1.py → publish_mage_actions_v1.py → verify_mage_actions_v1.py.
''',encoding='utf-8')
    cycle.demo(frames,report);print('Mage action review published:11poses/1408motion/432recipe contacts')

if __name__=='__main__':main()
