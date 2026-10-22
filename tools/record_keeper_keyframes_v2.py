"""Record the complete keypose candidates and the independent all-character audit."""
import hashlib,json
from PIL import Image
from process_pixel_art import ROOT
import build_palette_catalog_v1 as catalog

OUT=ROOT/'art/characters/keyframes-v2/keeper'
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def save(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

user_quote='좋아 모든 캐릭터들이 팔레트와 동일한지 등 검사하고 다음작업을 해보자고'
rogue=ROOT/'art/characters/keyframes-v2/rogue'
save(rogue/'approval.json',{'status':'approved_keyposes_for_followup','approved_by_user':True,'date':'2026-10-14','user_quote':user_quote,'scope':'The eight reviewed rogue keyposes and identity; excludes unseen action animations and runtime integration.','frame_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((rogue/'frames').glob('*.png'))}})
rdata=read(rogue/'keyframes.json');rdata.update(approved_by_user=True,approval='approval.json',status='approved_keyposes_for_followup');save(rogue/'keyframes.json',rdata)

status_path=ROOT/'art/characters/keyframes-v1/production-status.json';status=read(status_path)
status.update(current_stage='character_keyframes_review',current_character='keeper',current_customer=None,next_character=None,next_stage='action_animations',remaining_keyframe_characters=[],completed_character_keyframe_candidates=['keeper','traveler','mage','elf','rogue'],all_character_audit='art/characters/audit-v1/validation.json',action_animations='not_generated',runtime_integrated=False)
status['rogue'].update(status='approved_keyposes_for_followup',approved_by_user=True,approval='art/characters/keyframes-v2/rogue/approval.json',latest_user_feedback=user_quote)
status['keeper']={'status':'keyframes_v2_candidate','approved_by_user':False,'frame_count':6,'review':'art/characters/keyframes-v2/keeper/review.html','validation':'art/characters/keyframes-v2/keeper/validation.json','contacts':'art/characters/keyframes-v2/keeper/contact-validation.json','native_canvas':[32,48],'palette_colors':5,'current_head_hat_preserved':True,'brew_contact_pairs':108,'handover_contact_pairs':72,'actions_status':'not_generated'}
save(status_path,status)

plan_path=ROOT/'art/palettes/v1/production-plan.json';plan=read(plan_path)
plan.update(current_stage='character_keyframes_review',current_character='keeper',current_customer=None,latest_keeper_keyframes='art/characters/keyframes-v2/keeper/review.html',remaining_keyframe_characters=[],next_character=None,next_stage='action_animations',keyframes_status='all_five_character_candidates_generated',animations_status='planned_not_generated',all_character_audit='art/characters/audit-v1/validation.json')
save(plan_path,plan)

for name in ('characters.json','catalog.json'):
    path=ROOT/'art/palettes/v1'/name;data=read(path)
    for row in data['characters']:
        if row['id']=='keeper':row.update(reference='art/characters/keyframes-v2/keeper/frames/idle.png',reference_status='candidate_keyframe',keyframe_review='art/characters/keyframes-v2/keeper/review.html',keyframe_status='candidate_keyframes',note='남자 주인공의 기존 모자·짧은 갈색 머리·크림 셔츠·앞이 열린 보라 망토·반바지/부츠를 유지한다. 제조/전달6키포즈 후보다.')
    save(path,data)
data=read(ROOT/'art/palettes/v1/catalog.json');catalog.write_html(data['characters'],data['potions'],data['materials']);catalog.boards(data['characters'],data['potions'])

generation=read(OUT/'generation.json');generation.update(final_native_outputs='frames/',validation='validation.json',contacts='contact-validation.json',props={'spoon_source':'source/generated-spoon.png','prompt_file':'source/prompt-spoon.txt','manifest':'props-manifest.json','native':'props/spoon-native.png'},head_and_hat='Current head/hat/collar retained; raised forearms add pixels only outside the original silhouette in [0,14,10,28]. Moving torso/arms/legs come from one coherent whole-body source for each pose.',old_face_hook_used=False,cross_pose_limb_splicing=False);save(OUT/'generation.json',generation)

mapping={'schema_version':1,'date':'2026-10-14','scale':3,'native_canvas':[32,48],'runtime_integrated':False,'characters':{}}
for name,row in status.items():
    if name not in ('keeper','traveler','mage','elf','rogue'):continue
    directory=row['review'].removesuffix('/review.html')
    mapping['characters'][name]={'palette':f'art/palettes/v1/characters/{name}.hex','keyframes':directory+'/keyframes.json','neutral':directory+'/frames/idle.png','review':row['review'],'validation':row['validation'],'status':row['status']}
save(ROOT/'art/characters/current-art.json',mapping)
print('Recorded five character keypose sets. Next: finished action animations; runtime not integrated.')
