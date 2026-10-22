"""Record the next-customer candidate without changing approved colors or runtime art."""
import json
from pathlib import Path
from PIL import Image
import build_rogue_keyframes_v2 as b

def read(path):return json.loads(path.read_text(encoding='utf-8'))
def save(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

status_path=b.ROOT/'art/characters/keyframes-v1/production-status.json'
status=read(status_path)
status.update(current_stage='character_keyframes',current_customer='rogue',next_customer=None,next_character='keeper',remaining_customers=[],remaining_keyframe_characters=['keeper'],action_animations='not_generated',runtime_integrated=False)
status['completed_keyframe_candidates']=list(dict.fromkeys(status['completed_keyframe_candidates']+['rogue']))
status['elf'].update(latest_user_feedback='다음 진행해',user_authorized_next_customer=True,continuation_date='2026-10-14',next_step='Rogue keyposes produced; next keeper brewing and handover keyposes, then actions.')
status['rogue']={'status':'keyframes_v2_candidate','approved_by_user':False,'frame_count':8,'review':'art/characters/keyframes-v2/rogue/review.html','validation':'art/characters/keyframes-v2/rogue/validation.json','native_canvas':[32,48],'palette_colors':5,'identity':'Current game v4 orange cat hair/ears/tail, red scarf, flat black cropped top, shorts/gloves/boots','generation_mode':'builtin','bottle_pose_recipe_pairs_tested':72,'actions_status':'not_generated','next_step':'Review the candidate; keeper brewing/handover keyposes, then all action animations.'}
save(status_path,status)

plan_path=b.ROOT/'art/palettes/v1/production-plan.json'
plan=read(plan_path)
plan.update(current_stage='character_keyframes',current_customer='rogue',latest_rogue_keyframes='art/characters/keyframes-v2/rogue/review.html',completed_keyframe_candidates=status['completed_keyframe_candidates'],remaining_customers=[],remaining_keyframe_characters=['keeper'],next_character='keeper',keyframes_status='all_customer_candidates_generated_keeper_keyposes_remaining',animations_status='planned_not_generated')
save(plan_path,plan)

for name in ('characters.json','catalog.json'):
    path=b.ROOT/'art/palettes/v1'/name;data=read(path)
    for row in data['characters']:
        if row['id']=='elf':
            row.update(reference='art/characters/keyframes-v2/elf/frames/idle.png',reference_status='candidate_keyframe',keyframe_review='art/characters/keyframes-v2/elf/review.html',keyframe_status='candidate_keyframes',note='승인된 새 엘프의 옆땋은 머리·잎 장식·한쪽 어깨 잎 상의·허리띠·반바지와 비대칭 허리 잎을 유지한다. 새 키포즈는 검토 후보다.')
        if row['id']=='rogue':
            row.update(reference='art/characters/keyframes-v2/rogue/frames/idle.png',reference_status='candidate_keyframe',keyframe_review='art/characters/keyframes-v2/rogue/review.html',keyframe_status='candidate_keyframes')
    save(path,data)

import build_palette_catalog_v1 as catalog
data=read(b.ROOT/'art/palettes/v1/catalog.json')
catalog.write_html(data['characters'],data['potions'],data['materials'])
catalog.boards(data['characters'],data['potions'])

generation=read(b.OUT/'generation.json')
generation.update(selected_source_status='postprocessed_candidate',native_outputs='frames/',validation='validation.json',pipeline_manifest='manifest.json',actual_eyes={'open':[[10,23,1,2],[14,23,1,2]],'closed':[[10,24,2,1],[13,24,2,1]]},native_corrections='semantic-masks.json',old_face_hook_used=False,cross_pose_limb_splicing=False)
save(b.OUT/'generation.json',generation)
b.board({n:Image.open(b.OUT/'frames'/f'{n}.png').convert('RGBA') for n in b.POSES})
print('Recorded rogue candidate, customer keyposes4/4; keeper keyposes and action animations remain.')
