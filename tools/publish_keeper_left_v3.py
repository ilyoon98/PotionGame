"""Publish the repaired left-facing brewing candidate and refresh current art pointers."""
import hashlib,json
import numpy as np
from PIL import Image
from process_pixel_art import ROOT
import build_keeper_left_v3 as b
import build_keeper_review_v2 as review
import build_palette_catalog_v1 as catalog

OUT=b.OUT
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def save(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
frames={n:Image.open(OUT/'frames'/f'{n}.png').convert('RGBA') for n in b.POSES}
review.OUT=OUT;review.GRIPS={'brew_reach':[5,16],'brew_stir_left':[3,24],'brew_stir_right':[3,19],'handover_extend':[28,30],'handover_return':[22,34]};review.POT_ORIGIN=[30,28]
report=review.contacts(frames)
if report['status']!='passed':raise ValueError([(t['pose'],t['recipe'],t.get('liquid_surface_intersection_pixels')) for t in report['checks']+report['bottle_checks'] if not t['passed']])
(OUT/'hand-overlays').mkdir(exist_ok=True)
for name in ('handover_extend','handover_return'):review.palm_overlay(frames[name],name).save(OUT/'hand-overlays'/f'{name}.png')
recipe=next(r for r in review.RECIPES if r['id']=='health')
for n in b.POSES:review.scene(frames[n],n,recipe).resize((384,204),Image.Resampling.NEAREST).save(OUT/f'contact-{n}-3x.png')
review.preview(frames,report)
page=(OUT/'review.html').read_text(encoding='utf-8')
page=page.replace('現在','현재').replace('현재 모자·얼굴과 승인된5색을 유지했습니다.','제조3포즈는 왼쪽을 보는 새 전신입니다. 두 손과 두꺼운 소매를 확인했습니다. 지정5색은 유지했습니다.')
page=page.replace('let current=0,timer=null','let current=1,timer=null').replace("po=[26,28]","po=[30,28]")
page=page.replace('../elf/frames/idle.png','../../keyframes-v2/elf/frames/idle.png').replace('../rogue/frames/idle.png','../../keyframes-v2/rogue/frames/idle.png')
page=page.replace('<title>남자 주인공 · 제조/전달 키프레임</title>','<title>남자 주인공 · 왼쪽 제조 전신 v3</title>').replace('남자 주인공 · 제조/전달6키프레임','남자 주인공 · 왼쪽 제조 전신 v3')
page=page.replace('머리/모자는 현재 기준을 유지하고 발은46행에 닿습니다.','대기와 전달은 기존 오른쪽 전신, 제조는 새 왼쪽 전신입니다. 발은46행입니다.')
page=page.replace('</style>','.inspection{padding:16px;margin:18px 0;background:#4a3c52;border:1px solid #827589}.inspection img{display:block;width:192px;height:288px;image-rendering:pixelated;margin:auto}.inspection p{font-size:12px}</style>')
page=page.replace('<h2 id="pose-name">','<section class="inspection"><h2>손·팔 확대6배</h2><img id="inspect-figure" src="frames/brew_reach.png" width="192" height="288" alt="선택 포즈의 손과 팔6배 확대"><p>제조3포즈: 두 손 · 추가 피부 조각0 · 채워진 소매 단면4~6픽셀</p></section><h2 id="pose-name">')
page=page.replace("document.getElementById('pose-name').textContent=f.name;","document.getElementById('inspect-figure').src=f.path;document.getElementById('pose-name').textContent=f.name;")
(OUT/'review.html').write_text(page,encoding='utf-8')
data=read(OUT/'keyframes.json');data.update(version=3,identity_reference='art/characters/keyframes-v2/keeper/frames/idle.png',head_hat_current_reference_retained=False,head_attachment='Brewing uses a new coherent whole body; no old head layer. Hat width is excluded from head size.',old_head_overlay_used=False,body_redrawn_for_brewing=True,anatomy_validation='validation.json')
for frame in data['frames']:
    brew=frame['id'].startswith('brew');frame.update(facing='left' if brew else 'right',eye_points=b.LEFT_EYES if brew else [[15,21],[18,21]])
save(OUT/'keyframes.json',data)

prior=read(ROOT/'art/characters/audit-v1/validation.json');hashes={f['path']:f['sha256'] for r in prior['characters'].values() for f in r['frames']};hashes.update({f['path']:f['sha256'] for f in prior['keeper_existing_idle_motion']['frames']})
changed=[p for p,h in hashes.items() if hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h]
retained={n:bool(np.array_equal(np.array(frames[n]),np.array(Image.open(b.OLD/'frames'/f'{n}.png').convert('RGBA')))) for n in ('idle','handover_extend','handover_return')}
save(OUT/'regression-validation.json',{'status':'passed' if not changed and all(retained.values()) else 'failed','existing_art_files_checked':len(hashes),'changed_existing_art':changed,'retained_right_facing_frames_identical':retained})
if changed or not all(retained.values()):raise ValueError('Existing art changed')

old=b.OLD/'keyframes.json';olddata=read(old);olddata.update(status='superseded_brewing_anatomy_rejected',user_feedback='손3개와 겨드랑이의 가는 팔 지적. 왼쪽 전신으로 재제작.',replacement='art/characters/keyframes-v3/keeper/review.html');save(old,olddata)
status_path=ROOT/'art/characters/keyframes-v1/production-status.json';status=read(status_path);status['keeper'].update(status='keyframes_v3_candidate',review='art/characters/keyframes-v3/keeper/review.html',validation='art/characters/keyframes-v3/keeper/validation.json',contacts='art/characters/keyframes-v3/keeper/contact-validation.json',current_head_hat_preserved=False,brew_redrawn_facing='left',visible_hands_per_brew_pose=2,minimum_tested_sleeve_width=4,old_head_overlay_used=False);save(status_path,status)
current_path=ROOT/'art/characters/current-art.json';current=read(current_path);current['characters']['keeper'].update(keyframes='art/characters/keyframes-v3/keeper/keyframes.json',neutral='art/characters/keyframes-v3/keeper/frames/idle.png',review='art/characters/keyframes-v3/keeper/review.html',validation='art/characters/keyframes-v3/keeper/validation.json',status='keyframes_v3_candidate');save(current_path,current)
plan_path=ROOT/'art/palettes/v1/production-plan.json';plan=read(plan_path);plan['latest_keeper_keyframes']='art/characters/keyframes-v3/keeper/review.html';save(plan_path,plan)
for name in ('characters.json','catalog.json'):
    path=ROOT/'art/palettes/v1'/name;data=read(path)
    for row in data['characters']:
        if row['id']=='keeper':row.update(reference='art/characters/keyframes-v3/keeper/frames/idle.png',keyframe_review='art/characters/keyframes-v3/keeper/review.html',note='남캐의 지정5색과 기존 대기/전달을 유지한다. 제조3포즈는 두 손과 두꺼운 소매를 갖춘 왼쪽 전신으로 새로 만들었다.')
    save(path,data)
data=read(ROOT/'art/palettes/v1/catalog.json');catalog.write_html(data['characters'],data['potions'],data['materials'])
print('Published v3:2hands, solid sleeves, LEFT-facing brewing;108brew and72handover contacts passed.')
