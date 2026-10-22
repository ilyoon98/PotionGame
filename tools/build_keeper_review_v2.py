"""Contact checks and an integer-scale review of the keeper's six keyposes."""
from __future__ import annotations
import json,subprocess,sys
import numpy as np
from PIL import Image
from process_pixel_art import ROOT,rgb,validate
import build_keeper_keyframes_v2 as b
import build_traveler_keyframes_v1 as common

OUT=b.OUT
GRIPS={'brew_reach':[2,17],'brew_stir_left':[2,21],'brew_stir_right':[3,17],'handover_extend':[28,30],'handover_return':[22,34]}
SPOON_GRIP=[15,0]
KEEPER_ORIGIN=[52,12]
POT_ORIGIN=[26,28]
RECIPES=json.loads((ROOT/'art/mockups/full-ingame-v7/potions/recipes.json').read_text(encoding='utf-8'))['recipes']
def dump(path,data):common.dump(path,data)

def palm_overlay(frame,name):
    a=np.array(frame);x,y=GRIPS[name]
    roi=np.zeros((48,32),bool);roi[max(0,y-2):min(48,y+3),max(0,x-2):min(32,x+3)]=True
    skin=np.all(a[:,:,:3]==rgb(b.SKIN),axis=2)&(a[:,:,3]!=0)&roi
    adjacent=np.zeros_like(skin)
    for dy,dx in ((-1,0),(1,0),(0,-1),(0,1)):
        adjacent|=np.roll(np.roll(skin,dy,0),dx,1)
    keep=skin|(adjacent&np.all(a[:,:,:3]==rgb(b.INK),axis=2)&(a[:,:,3]!=0)&roi)
    output=np.zeros_like(a);output[keep]=a[keep]
    return Image.fromarray(output)

def contacts(frames,head_mask=None):
    spoon=Image.open(OUT/'props/spoon-native.png').convert('RGBA');sa=np.array(spoon)
    checks=[]
    for name,(x,y) in GRIPS.items():
        if tuple(np.array(frames[name])[y,x])!=(*rgb(b.SKIN),255):raise ValueError(f'Grip is not on actual peach palm: {name}/{x,y}')
        if name.startswith('brew'):
            if not sa[SPOON_GRIP[1],SPOON_GRIP[0],3]:raise ValueError('Spoon grip has no pixel')
            tool_origin=[KEEPER_ORIGIN[0]+x-SPOON_GRIP[0],KEEPER_ORIGIN[1]+y-SPOON_GRIP[1]]
            sm=np.zeros((68,128),bool);sx,sy=tool_origin;sm[sy:sy+spoon.height,sx:sx+spoon.width]=sa[:,:,3]!=0
            for recipe in RECIPES:
                pot=np.array(Image.open(ROOT/'art/mockups/full-ingame-v7/potions'/recipe['pot_frames'][0]).convert('RGBA'))
                liquid=(np.all(pot[:,:,:3]==rgb(recipe['liquid_color']),axis=2)&(pot[:,:,3]!=0));lm=np.zeros((68,128),bool)
                px,py=POT_ORIGIN;lm[py:py+32,px:px+32]=liquid
                hits=int((sm&lm).sum())
                checks.append({'pose':name,'recipe':recipe['id'],'grip_on_skin':True,'spoon_grip_opaque':True,'tool_origin':tool_origin,'liquid_surface_intersection_pixels':hits,'passed':hits>0})
    bottle_checks=[]
    for name in ('handover_extend','handover_return'):
        x,y=GRIPS[name]
        for recipe in RECIPES:
            image=Image.open(ROOT/'art/mockups/full-ingame-v7/potions'/recipe['bottle_path']).convert('RGBA');a=np.array(image);bx,by=x-image.width//2,y-4
            inside=min(bx,by)>=0 and bx+image.width<=32 and by+image.height<=48
            head_clear=True
            if inside:
                mask=np.zeros((48,32),bool);mask[by:by+image.height,bx:bx+image.width]=a[:,:,3]!=0
                head_alpha=(np.array(frames[name])[:27,:,3]!=0) if head_mask is None else head_mask[:27]
                head_clear=not bool((mask[:27]&head_alpha).any())
            hand=np.array(palm_overlay(frames[name],name));visible=int((mask&(hand[:,:,3]==0)).sum()) if inside else 0
            contents=np.zeros((48,32),bool)
            if inside:contents[by:by+image.height,bx:bx+image.width]=np.all(a[:,:,:3]==rgb(recipe['liquid_color']),axis=2)&(a[:,:,3]!=0)
            visible_contents=int((contents&(hand[:,:,3]==0)).sum())
            bottle_checks.append({'pose':name,'recipe':recipe['id'],'grip_on_skin':True,'inside32x48':inside,'local_grip_opaque':bool(a[4,image.width//2,3]),'head_and_eyes_clear':head_clear,'origin':[bx,by],'visible_bottle_pixels':visible,'visible_contents_pixels':visible_contents,'passed':bool(inside and head_clear and a[4,image.width//2,3] and visible>=12 and visible_contents>0)})
    report={'status':'passed' if all(r['passed'] for r in checks+bottle_checks) else 'failed','recipe_count':36,'brew_contact_pairs':len(checks),'handover_contact_pairs':len(bottle_checks),'grips':GRIPS,'spoon_local_grip':SPOON_GRIP,'bottle_local_grip':'[width/2,4]','scene_native_size':[128,68],'keeper_origin':KEEPER_ORIGIN,'cauldron_origin':POT_ORIGIN,'checks':checks,'bottle_checks':bottle_checks}
    dump(OUT/'contact-validation.json',report);dump(OUT/'hand-anchors.json',{'hand_grip_anchors':GRIPS,'spoon_local_grip':SPOON_GRIP,'bottle_local_grip':'[width/2,4]'})
    return report

def scene(frame,name,recipe):
    im=Image.new('RGBA',(128,68),'#4A3C52')
    pot=Image.open(ROOT/'art/mockups/full-ingame-v7/potions'/recipe['pot_frames'][0]).convert('RGBA');im.alpha_composite(pot,tuple(POT_ORIGIN))
    if name.startswith('brew'):
        spoon=Image.open(OUT/'props/spoon-native.png').convert('RGBA');x,y=GRIPS[name];im.alpha_composite(spoon,(KEEPER_ORIGIN[0]+x-SPOON_GRIP[0],KEEPER_ORIGIN[1]+y-SPOON_GRIP[1]))
        # The cauldron front wall occludes the submerged portion of the spoon.
        im.alpha_composite(pot.crop((0,11,32,32)),(POT_ORIGIN[0],POT_ORIGIN[1]+11))
    im.alpha_composite(frame,tuple(KEEPER_ORIGIN))
    if name.startswith('handover'):
        bottle=Image.open(ROOT/'art/mockups/full-ingame-v7/potions'/recipe['bottle_path']).convert('RGBA');x,y=GRIPS[name];im.alpha_composite(bottle,(KEEPER_ORIGIN[0]+x-bottle.width//2,KEEPER_ORIGIN[1]+y-4))
        im.alpha_composite(palm_overlay(frame,name),tuple(KEEPER_ORIGIN))
    return im

def preview(frames,report):
    frame_rows=[{'id':name,'name':label,'path':f'frames/{name}.png','grip':GRIPS.get(name),'native_size':[32,48],'sheet_rect':[i%3*32,i//3*48,32,48]} for i,(name,label) in enumerate(zip(b.POSES,b.NAMES))]
    dump(OUT/'keyframes.json',{'schema_version':1,'character':'keeper','status':'candidate_keyframes','approved_by_user':False,'frames':frame_rows,'palette':'art/palettes/v1/characters/keeper.hex','scale':3,'native_sheet':'keeper-keyframes-native.png','identity_reference':'art/mockups/full-ingame-v7/characters/witch-native.png','head_hat_current_reference_retained':True,'head_attachment':'Raised forearm is outside the approved head silhouette.','contacts':'contact-validation.json','animations_status':'keypose flipbooks only; finished action animations remain','runtime_integrated':False})
    recipes=[]
    for r in RECIPES:
        bottle=Image.open(ROOT/'art/mockups/full-ingame-v7/potions'/r['bottle_path'])
        recipes.append({'id':r['id'],'name':r['name'],'liquid_color':r['liquid_color'],'pot':'../../../mockups/full-ingame-v7/potions/'+r['pot_frames'][0],'bottle':'../../../mockups/full-ingame-v7/potions/'+r['bottle_path'],'bottle_size':list(bottle.size)})
    options=''.join(f'<option value="{r["id"]}">{r["name"]}</option>' for r in recipes)
    buttons=''.join(f'<button data-pose="{i}" aria-pressed="{str(i==0).lower()}">{label}</button>' for i,label in enumerate(b.NAMES))
    page='''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>남자 주인공 · 제조/전달 키프레임</title><style>
@font-face{font-family:Pretendard;src:url('../../../../assets/fonts/pretendard/Pretendard-Regular.otf')}*{box-sizing:border-box}body{margin:0;background:#241c32;color:#fff0bc;font:15px/1.5 Pretendard,system-ui,sans-serif}main{max-width:1000px;margin:auto;padding:20px 16px}h1{font-size:24px;margin:0 0 8px}h2{font-size:17px}p{color:#c38eb5;margin:8px 0 14px}a{color:#e9b95f}button,select{font:inherit;color:#fff0bc;background:#4a3c52;border:1px solid #827589;padding:7px 10px;cursor:pointer}button[aria-pressed=true]{border-color:#e9b95f}.controls{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:14px 0}.palette{display:flex;flex-wrap:wrap;gap:8px;font-size:12px}.palette span{display:flex;gap:4px;align-items:center}.palette i{width:18px;height:18px;background:var(--color)}.sheet{background:#4a3c52;margin-top:16px;overflow:auto}.sheet img{width:288px;height:288px;display:block;margin:auto;image-rendering:pixelated;max-width:none}.caption{font-size:12px}.stage{background:#4a3c52;border:1px solid #827589;overflow:auto}canvas{display:block;width:384px;height:204px;image-rendering:pixelated;max-width:none;margin:auto}.notice{padding:12px;border:1px solid #718c59;background:#30263f;margin:18px 0}.refs{display:flex;gap:16px;overflow:auto}.refs figure{margin:0;text-align:center;flex:none}.refs img{width:96px;height:144px;image-rendering:pixelated}.refs figcaption{font-size:12px}.footer{margin-top:22px}
</style></head><body><main><h1>남자 주인공 · 제조/전달6키프레임</h1><p>같은32×48 원본과 공통3배입니다. 현재 모자·얼굴과 승인된5색을 유지했습니다.</p><div class="palette">__SWATCHES__</div><div class="sheet"><img src="keeper-keyframes-native.png" width="288" height="288" alt="주인공6키프레임 전체 시트 · 공통3배"></div><p class="caption">위: 대기 · 손 뻗기 · 젓기A<br>아래: 젓기B · 전달 · 손 회수</p><div class="controls">__BUTTONS__</div><div class="controls"><label>키포즈 반복 <select id="mode"><option value="stop">멈춤</option><option value="brew">제조</option><option value="handover">전달</option></select></label><label>물약 <select id="recipe">__OPTIONS__</select></label><label><input type="checkbox" id="props" checked>국자·물약 붙이기</label></div><h2 id="pose-name">대기</h2><div class="stage"><canvas id="scene" width="128" height="68" aria-label="같은 배율의 솥과 주인공 접점 확인"></canvas></div><p id="contact-note"></p><div class="notice">전체 캐릭터의 지정 팔레트·두 눈·외곽선 검사: 통과. <a href="../../audit-v1/review.html">5명 전체 검사표</a><br>제조108조합 · 전달72조합의 손/소품 접점을 검사했습니다.</div><h2>손님들과 같은 배율</h2><div class="refs">__REFS__</div><p>반복 재생은 주요 키포즈를 확인하는 기능입니다. 호흡·깜빡임·머리/모자/망토 움직임과 중간 프레임을 합친 행동 애니메이션은 다음 단계입니다.</p><p class="footer"><a href="keyframes-review.png">6포즈 확인표</a> · <a href="validation.json">원본 검사</a> · <a href="contact-validation.json">접점 검사</a> · <a href="generation.json">원본·프롬프트</a> · <a href="../../audit-v1/validation.json">전체 검사 기록</a></p></main><script>
const frames=__FRAMES__,recipes=__RECIPES__,grips=__GRIPS__,ko=[52,12],po=[26,28],sg=[15,0];let current=0,timer=null;const loaded=new Map();const paths=[...frames.map(f=>f.path),...recipes.flatMap(r=>[r.pot,r.bottle]),'props/spoon-native.png'];Promise.all([...new Set(paths)].map(path=>new Promise((resolve,reject)=>{let i=new Image();i.onload=()=>{loaded.set(path,i);resolve()};i.onerror=()=>reject(new Error('Asset did not load: '+path));i.src=path}))).then(()=>{document.body.dataset.loaded='true';update()});
function update(){const f=frames[current],r=recipes.find(r=>r.id===document.getElementById('recipe').value),show=document.getElementById('props').checked,c=document.getElementById('scene').getContext('2d');c.imageSmoothingEnabled=false;c.clearRect(0,0,128,68);const pot=loaded.get(r.pot),character=loaded.get(f.path);if(!pot||!character)return;c.drawImage(pot,po[0],po[1]);if(show&&f.id.startsWith('brew')){let p=grips[f.id],tool=loaded.get('props/spoon-native.png');c.drawImage(tool,ko[0]+p[0]-sg[0],ko[1]+p[1]-sg[1]);c.drawImage(pot,0,11,32,21,po[0],po[1]+11,32,21)}if(show&&f.id.startsWith('handover')){let p=grips[f.id],bottle=loaded.get(r.bottle);c.drawImage(bottle,ko[0]+p[0]-Math.floor(bottle.width/2),ko[1]+p[1]-4)}c.drawImage(character,ko[0],ko[1]);document.getElementById('pose-name').textContent=f.name;document.getElementById('scene').dataset.pose=f.id;document.getElementById('scene').dataset.recipe=r.id;document.getElementById('contact-note').textContent=f.id.startsWith('brew')?'솥과 같은 발 높이에서 국자가 내용물 표면에 닿는지 확인합니다.':f.id.startsWith('handover')?'병은 손 접점에 붙인 별도 에셋입니다. 얼굴과 눈을 가리지 않습니다.':'머리/모자는 현재 기준을 유지하고 발은46행에 닿습니다.';document.querySelectorAll('[data-pose]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.pose)===current)))}
function stop(){clearInterval(timer);document.getElementById('mode').value='stop'}document.querySelectorAll('[data-pose]').forEach(b=>b.addEventListener('click',()=>{stop();current=Number(b.dataset.pose);update()}));document.getElementById('mode').addEventListener('change',e=>{clearInterval(timer);const sequence=e.target.value==='brew'?[1,2,3,2]:e.target.value==='handover'?[4,5]:null;if(sequence){let index=0;current=sequence[index];update();timer=setInterval(()=>{index=(index+1)%sequence.length;current=sequence[index];update()},400)}});document.getElementById('recipe').addEventListener('change',update);document.getElementById('props').addEventListener('change',update);
</script></body></html>'''
    swatches=''.join(f'<span><i style="--color:{c}"></i>{name}</span>' for c,name in [(b.INK,'테두리·눈'),(b.SKIN,'피부·셔츠'),(b.BROWN,'머리·반바지·부츠'),(b.PURPLE,'모자·망토'),(b.GOLD,'장식')])
    refs=[('../traveler/frames/idle.png','여행자')] # Version1 and2 have different sibling locations.
    refs=[('../../keyframes-v1/traveler/frames/idle.png','여행자'),('../../keyframes-v1/mage/frames/idle.png','여마법사'),('../elf/frames/idle.png','엘프'),('../rogue/frames/idle.png','도적')]
    for token,value in [('__SWATCHES__',swatches),('__BUTTONS__',buttons),('__OPTIONS__',options),('__FRAMES__',json.dumps(frame_rows,ensure_ascii=False)),('__RECIPES__',json.dumps(recipes,ensure_ascii=False)),('__GRIPS__',json.dumps(GRIPS)),('__REFS__',''.join(f'<figure><img src="{path}" alt="{label} 같은3배"><figcaption>{label}</figcaption></figure>' for path,label in refs))]:page=page.replace(token,value)
    page=page.replace("querySelectorAll('[data-pose]')","querySelectorAll('button[data-pose]')")
    page=page.replace("'props/spoon-native.png'];","'props/spoon-native.png','hand-overlays/handover_extend.png','hand-overlays/handover_return.png'];")
    old="if(show&&f.id.startsWith('handover')){let p=grips[f.id],bottle=loaded.get(r.bottle);c.drawImage(bottle,ko[0]+p[0]-Math.floor(bottle.width/2),ko[1]+p[1]-4)}c.drawImage(character,ko[0],ko[1]);"
    new="c.drawImage(character,ko[0],ko[1]);if(show&&f.id.startsWith('handover')){let p=grips[f.id],bottle=loaded.get(r.bottle);c.drawImage(bottle,ko[0]+p[0]-Math.floor(bottle.width/2),ko[1]+p[1]-4);c.drawImage(loaded.get('hand-overlays/'+f.id+'.png'),ko[0],ko[1])}"
    if old not in page:raise ValueError('Review compositor source changed; update its hand occlusion explicitly')
    page=page.replace(old,new)
    (OUT/'review.html').write_text(page,encoding='utf-8')

def main():
    frames={n:Image.open(OUT/'frames'/f'{n}.png').convert('RGBA') for n in b.POSES}
    (OUT/'hand-overlays').mkdir(exist_ok=True)
    for name in ('handover_extend','handover_return'):palm_overlay(frames[name],name).save(OUT/'hand-overlays'/f'{name}.png')
    report=contacts(frames)
    if report['status']!='passed':
        print([(t['pose'],t['recipe'],t.get('liquid_surface_intersection_pixels'),t.get('head_and_eyes_clear')) for t in report['checks']+report['bottle_checks'] if not t['passed']]);raise ValueError('Tool contact checks failed')
    recipe=next(r for r in RECIPES if r['id']=='health')
    for n in b.POSES:scene(frames[n],n,recipe).resize((384,204),Image.Resampling.NEAREST).save(OUT/f'contact-{n}-3x.png')
    preview(frames,report);print(json.dumps({'contacts':report['status'],'brew_pairs':report['brew_contact_pairs'],'handover_pairs':report['handover_contact_pairs']}))
if __name__=='__main__':main()
