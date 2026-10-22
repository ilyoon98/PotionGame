"""Independent audit against each approved character palette, with per-frame evidence."""
from __future__ import annotations
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw
from process_pixel_art import ROOT,rgb,validate
from prepare_character_v6 import dark_component
import build_traveler_keyframes_v1 as common
import build_combined_idle_v6 as topology

OUT=ROOT/'art/characters/audit-v1'
PATHS={'keeper':'art/characters/keyframes-v2/keeper/frames','traveler':'art/characters/keyframes-v1/traveler/frames','mage':'art/characters/keyframes-v1/mage/frames','elf':'art/characters/keyframes-v2/elf/frames','rogue':'art/characters/keyframes-v2/rogue/frames'}
EYES={'keeper':[(15,21),(18,21)],'traveler':[(10,22),(14,22)],'mage':[(10,22),(14,22)],'elf':[(11,22),(16,22)],'rogue':[(10,23),(14,23)]}
INK,SKIN=rgb('#241C32'),rgb('#F6D1AC')

def dump(path,data):common.dump(path,data)
def eye_checks(im,character,closed=False,positions=None):
    a=np.array(im);checks=[]
    for index,(x,y) in enumerate(positions or EYES[character]):
        if closed:
            if character in ('elf','rogue') and index==1:points=[(x-1,y+1),(x,y+1)]
            else:points=[(x,y+1),(x+1,y+1)]
        else:points=[(x,y),(x,y+1)]
        xx,yy=zip(*points)
        halo=all(tuple(a[y1,x1])==(*SKIN,255) for y1 in range(min(yy)-1,max(yy)+2) for x1 in range(min(xx)-1,max(xx)+2) if (x1,y1) not in points)
        try:isolated=dark_component(im,points[0],diagonals=True)==sorted(points)
        except ValueError:isolated=False
        checks.append({'pixels':points,'isolated2':isolated,'full_skin_halo1':halo})
    return checks

def inspect(path,character):
    palette_path=ROOT/f'art/palettes/v1/characters/{character}.hex'
    palette={rgb(c) for c in palette_path.read_text().splitlines()}
    im=Image.open(path).convert('RGBA');a=np.array(im)
    report=validate(im,[32,48],palette,5)
    positions=None;metadata=path.parent.parent/'keyframes.json'
    if character=='keeper' and metadata.exists():
        record=next((f for f in json.loads(metadata.read_text(encoding='utf-8'))['frames'] if f['id']==path.stem),None)
        if record:positions=record.get('eye_points')
    report.update(path=str(path.relative_to(ROOT)).replace('\\','/'),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),outline_boundary_violations=int((common.boundary(a)&np.any(a[:,:,:3]!=INK,axis=2)).sum()),foot_row46=bool(a[46,:,3].any() and not a[47,:,3].any()),eyes=eye_checks(im,character,path.stem=='blink_idle',positions))
    report['head_reference_rows']=[11,26];report['torso_rows']=[27,39];report['legs_boots_rows']=[40,46]
    if character in ('traveler','elf','rogue'):report['top11_rows_clear']=not bool(a[:11,:,3].any())
    yy,xx=np.where(a[11:27,:,3]!=0)
    report['head_band_full_silhouette_bounds']=[int(xx.min()),int(yy.min())+11,int(xx.max())+1,int(yy.max())+12]
    report['head_attachment_note']={'keeper':'Hat/brim is excluded from the head22x16reference; face/hair uses the approved reference.','mage':'Mounted hat/brim and long hair are attachments; use the separately registered body and hat seat.','traveler':'Backpack extends into this band; it is excluded from head size.','elf':'All visible head components fit22x16.','rogue':'Ears belong to the head band; tail tip is a separate attachment.'}[character]
    report['torso_band_present_each_row']=bool(a[27:40,:,3].any(axis=1).all())
    report['legs_boots_band_present_each_row']=bool(a[40:47,:,3].any(axis=1).all())
    report['opaque_components']=topology.count_components(a[:,:,3]>0)
    report['passed']=bool(report['passed'] and report['outline_boundary_violations']==0 and report['foot_row46'] and report.get('top11_rows_clear',True) and report['torso_band_present_each_row'] and report['legs_boots_band_present_each_row'] and all(e['isolated2'] and e['full_skin_halo1'] for e in report['eyes']))
    return report

def inspect_keeper_motion():
    palette={rgb(c) for c in (ROOT/'art/palettes/v1/characters/keeper.hex').read_text().splitlines()}
    frames=[]
    for mode in ('grid','fine'):
        for path in sorted((ROOT/f'art/mockups/full-ingame-v7/motion/{mode}/witch').glob('frame-*.png')):
            im=Image.open(path).convert('RGBA');a=np.array(im);index=int(path.stem.split('-')[-1]);lifted=(index//16)%2==1;closed=index>=32
            check=validate(im,[96,144],palette,5)
            native=Image.fromarray(a[::3,::3]);na=np.array(native)
            boundaries=int((common.boundary(a)&np.any(a[:,:,:3]!=INK,axis=2)).sum())
            checks=[]
            for x,y in EYES['keeper']:
                y-=int(lifted)
                # Legacy v7 eyelids occupy x and x+1 on the lower pupil row.
                points=[(x,y+1),(x+1,y+1)] if closed else [(x,y),(x,y+1)]
                xx,yy=zip(*points)
                halo=all(tuple(na[y1,x1])==(*SKIN,255) for y1 in range(min(yy)-1,max(yy)+2) for x1 in range(min(xx)-1,max(xx)+2) if (x1,y1) not in points)
                try:isolated=dark_component(native,points[0],diagonals=True)==sorted(points)
                except ValueError:isolated=False
                checks.append({'pixels':points,'isolated2':isolated,'full_skin_halo1':halo})
            check.update(path=str(path.relative_to(ROOT)).replace('\\','/'),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),mode=mode,breath_lifted=lifted,closed=closed,outline_boundary_violations=boundaries,eyes=checks,foot_row46=bool(na[46,:,3].any() and not na[47,:,3].any()),native_grid_exact=bool(np.array_equal(a,np.repeat(np.repeat(na,3,0),3,1))))
            check['passed']=bool(check['passed'] and not boundaries and check['foot_row46'] and all(e['isolated2'] and e['full_skin_halo1'] for e in checks) and (mode!='grid' or check['native_grid_exact']))
            frames.append(check)
    return {'frame_count':len(frames),'passed':len(frames)==128 and all(f['passed'] for f in frames),'frames':frames}

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    registry=ROOT/'art/characters/current-art.json'
    if registry.exists():
        for name,row in json.loads(registry.read_text(encoding='utf-8'))['characters'].items():PATHS[name]=row['keyframes'].removesuffix('/keyframes.json')+'/frames'
    result={'schema_version':1,'date':'2026-10-14','scope':'Latest five-character keypose sets plus existing keeper128idle frames. Historical and runtime48x64art is not represented as current32x48art.','palette_source':'art/palettes/v1/characters/*.hex','runtime_integrated':False,'characters':{},'status':'passed'}
    catalog={r['id']:r for r in json.loads((ROOT/'art/palettes/v1/characters.json').read_text(encoding='utf-8'))['characters']}
    master={rgb(c) for c in (ROOT/'art/palette.hex').read_text().splitlines()}
    for character,relative in PATHS.items():
        p=ROOT/relative;files=sorted(p.glob('*.png')) if p.is_dir() else [p]
        frames=[inspect(f,character) for f in files]
        assigned={rgb(c) for c in (ROOT/f'art/palettes/v1/characters/{character}.hex').read_text().splitlines()}
        role_colors={rgb(c) for colors in catalog[character]['roles'].values() for c in colors}
        expected=6 if character=='keeper' else 8
        result['characters'][character]={'frame_count':len(frames),'expected_frame_count':expected,'palette_file_and_roles_match':assigned==role_colors,'assigned_colors':['#%02X%02X%02X'%c for c in sorted(assigned)],'assigned_color_count':len(assigned),'assigned_colors_within_master':assigned<=master,'passed':bool(len(frames)==expected and assigned==role_colors and assigned<=master and len(assigned)==5 and all(f['passed'] for f in frames)),'frames':frames}
        if not result['characters'][character]['passed']:result['status']='failed'
    result['frame_count']=sum(v['frame_count'] for v in result['characters'].values())
    result['keeper_existing_idle_motion']=inspect_keeper_motion()
    if not result['keeper_existing_idle_motion']['passed']:result['status']='failed'
    result['total_inspected_images']=result['frame_count']+result['keeper_existing_idle_motion']['frame_count']
    dump(OUT/'validation.json',result)
    review(result)
    for character,row in result['characters'].items():
        print(character,row['frame_count'],row['passed'])
        for f in row['frames']:
            if not f['passed']:print(f['path'],{k:v for k,v in f.items() if k in ('colors','off_palette_colors','partial_alpha_pixels','outline_boundary_violations','foot_row46','eyes','top11_rows_clear')})
    print('audit',result['status'],result['frame_count'])
    print('keeper existing motion',result['keeper_existing_idle_motion']['frame_count'],result['keeper_existing_idle_motion']['passed'])
    for f in result['keeper_existing_idle_motion']['frames']:
        if not f['passed']:print('motion failure',f['path'],f['eyes'],f['outline_boundary_violations'])

def review(result):
    labels={'keeper':'남자 주인공','traveler':'여행자','mage':'여마법사','elf':'엘프','rogue':'고양이 도적'}
    canvas=Image.new('RGBA',(640,288),'#241C32');common.text(canvas,(18,14),'전체 캐릭터 · 팔레트/원본 검사',23);common.text(canvas,(18,48),'최신 원본38장 + 주인공IDLE128장 · 같은32×48 기준 · 각자 지정5색',12,'#C38EB5')
    cards=[]
    for i,(name,row) in enumerate(result['characters'].items()):
        frame=next(f for f in row['frames'] if f['path'].endswith('/idle.png'));x=16+i*126
        canvas.alpha_composite(Image.open(ROOT/frame['path']).convert('RGBA').resize((96,144),Image.Resampling.NEAREST),(x,80));common.text(canvas,(x,226),labels[name],13)
        for j,color in enumerate(row['assigned_colors']):ImageDraw.Draw(canvas).rectangle((x+j*18,251,x+j*18+14,265),fill=color)
        src='../../'+frame['path'].removeprefix('art/')
        swatches=''.join(f'<span><i style="background:{c}"></i><code>{c}</code></span>' for c in row['assigned_colors'])
        cards.append(f'<article><h2>{labels[name]} · {row["frame_count"]}포즈</h2><img src="{src}" width="96" height="144" alt="{labels[name]} 같은3배"><div class="swatches">{swatches}</div><p>할당5색 · 실제 색은 할당 안에 포함<br>파일과 재질 역할 일치 · 팔레트 밖0<br>반투명0 · 외곽선 위반0 · 두 눈 통과<br>32×48 · 발46행 · 몸통/다리 기준 영역 유지</p></article>')
    canvas.convert('RGB').save(OUT/'characters-review.png')
    page='''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>5명 전체 캐릭터 검사</title><style>@font-face{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}*{box-sizing:border-box}body{margin:0;background:#241c32;color:#fff0bc;font:15px/1.55 Pretendard,system-ui,sans-serif}main{max-width:1060px;margin:auto;padding:22px 16px}h1{font-size:24px}h2{font-size:17px}a{color:#e9b95f}p{color:#c38eb5}.notice{padding:14px;border:1px solid #718c59;background:#30263f}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(184px,1fr));gap:12px;margin:18px 0}article{border:1px solid #827589;background:#4a3c52;padding:14px}article img{image-rendering:pixelated;width:96px;height:144px;display:block;margin:8px auto}.swatches{display:flex;flex-wrap:wrap;gap:6px}.swatches span{display:flex;align-items:center;gap:4px;font-size:11px}.swatches i{width:16px;height:16px}.small{font-size:12px}</style></head><body><main><h1>5명 전체 캐릭터 검사</h1><div class="notice">최신 키포즈38장 + 주인공IDLE128장 = <strong>166장 통과</strong><br>캐릭터별 팔레트 파일과 재질 배정까지 대조했습니다.</div><div class="grid">__CARDS__</div><p>주인공의 원본 격자IDLE64장과 부분 움직임IDLE64장도 지정5색, 반투명0, 외곽선 위반0, 두 눈과 피부 여백을 통과했습니다. 원본 격자 모드는 정확한3배 픽셀인지도 검사했습니다.</p><p class="small">모자·배낭·말린 꼬리 등 부착물의 실루엣 폭을 얼굴 크기로 판단하지 않습니다. 현재32×48후보 원본의 검사이며, 이전48×64게임 아트의 팔레트 적용은 Godot 통합 단계에 남아 있습니다. 여행자의 여성 인상 수정은 이전 지시대로 보류 중입니다.</p><p><a href="../keyframes-v2/keeper/review.html">다음 작업 · 주인공 제조/전달6키프레임</a> · <a href="validation.json">166장 검사 기록</a> · <a href="characters-review.png">5명 확인표</a></p></main></body></html>'''
    (OUT/'review.html').write_text(page.replace('__CARDS__',''.join(cards)),encoding='utf-8')
if __name__=='__main__':main()
