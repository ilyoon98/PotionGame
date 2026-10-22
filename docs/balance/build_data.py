"""Build proposed planning data and human-readable tables; never edits runtime or art."""
from pathlib import Path
import json, math

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
POTION_IDS = ['health','mana','moon','purify','agility','vigor','antidote','fortune','focus','restoration','growth','clarity','ward','spirit','arcane_amplification','iron_skin','stealth','poison_resistance','illusion','soul_purification','wisdom','reflection','haste','nightwalk','moonradiance','regeneration','starlight','wish','eternity','sage_elixir','worldtree_elixir','shadow_elixir']
REGION_IDS = ['forest_edge','abandoned_greenhouse','mist_valley','crystal_mine','fog_marsh','forgotten_tower','moon_ruins','star_garden']
MATERIAL_IDS = ['dewgrass','silver_moss','blue_reed','crystal_herb','mist_mushroom','ash_sage','moonflower','star_seed']
FAMILIES = {'활력':'vitality','비술':'arcane','자연':'nature','기교':'craft'}
CUSTOMERS = {'vitality':'traveler','arcane':'mage','nature':'elf','craft':'rogue'}
ENV = ['rain','cloudy','rain','clear','cloudy','day','night','night_clear']

def round_g(value):
    return int(math.floor(value + .5))

def build():
    text=(ROOT/'docs/장기-콘텐츠-확장-기획안.md').read_text(encoding='utf-8')
    rows=[]
    for line in text.splitlines():
        cells=[x.strip() for x in line.strip('|').split('|')]
        if line.startswith('| ') and len(cells)==7 and cells[0].isdigit(): rows.append(cells)
    assert len(rows)==32
    material_names=['이슬풀','은빛 이끼','푸른 갈대','수정초','안개버섯','잿빛 세이지','달꽃','별씨']
    name_to_mat=dict(zip(material_names,MATERIAL_IDS))|{'별잎':'starleaf','달빛 버섯':'moon_mushroom'}
    materials=[dict(id='herb',name='기본 약초',source='base_garden',capacity=24),dict(id='moon_mushroom',name='달빛 버섯',source='supplier',capacity=6,cost=4,delivery_seconds=12,delivery_quantity=2,reserve_gold=30),dict(id='starleaf',name='별잎',source='recipe_granted_garden',capacity=12,growth_seconds=12,environment='legacy_night_rain')]
    for i,(id,name) in enumerate(zip(MATERIAL_IDS,material_names)):
        materials.append(dict(id=id,name=name,source='recipe_granted_garden',region=REGION_IDS[i],growth_seconds=[12,14,16,18,20,20,22,24][i],capacity=12,environment=ENV[i],favored_growth_multiplier=1.5,seed_quantity=2))
    potions=[]
    for i,row in enumerate(rows):
        id=POTION_IDS[i]; region_index=(i-5)//3 if 5<=i<29 else None
        legacy=i<5
        ingredients={'herb':2}
        if row[4]!='없음':
            for material in row[4].split(' + '): ingredients[name_to_mat[material]]=1
        price=int(''.join(x for x in row[5] if x.isdigit()) or 0)
        sale=int(''.join(x for x in row[6] if x.isdigit()))
        unlock={'reputation': [0,0,0,10,20][i]} if legacy else {}
        if region_index is not None:
            counts=([3,6,10] if region_index==0 else [2,4,6] if region_index in [1,2,7] else [1,3,5])
            unlock['discovery']={'region':REGION_IDS[region_index],'returns':counts[(i-5)%3]}
        if i>=29:
            unlock={'discovery':{'region':'star_garden','returns':6},'recipes':[['wisdom','moonradiance'],['spirit','growth'],['stealth','nightwalk']][i-29]}
        if legacy:
            duration=[1,1.25,1.5,1.4,1.6][i]; success=[1,1,.86,.88,.84][i];environment='legacy_night_rain' if i>=2 else 'none'
        elif region_index is not None:
            duration=round([1.4,1.6,1.8,2.0,2.2,2.4,2.6,2.8][region_index]+.1*((i-5)%3),2)
            success=[.92,.9,.88,.86,.84,.84,.82,.82][region_index]; environment=ENV[region_index]
        else: duration=3.2;success=.8;environment='night_clear'
        potions.append(dict(id=id,name=row[1],family=FAMILIES[row[2]],preferred_customer=CUSTOMERS[FAMILIES[row[2]]],order=i,existing=legacy,owned_at_start=i<2,unlock=unlock,cost=price,sale_price=sale,ingredients=ingredients,duration_multiplier=duration,success=success,environment=environment,environment_bonus=.08 if not legacy else None,grant_material=MATERIAL_IDS[region_index] if region_index is not None else None))
    region_names=['숲 가장자리','버려진 온실','물안개 계곡','수정 광산','안개 늪','잊힌 탑','달빛 유적','별의 정원']
    regions=[]
    for i,id in enumerate(REGION_IDS):
        regions.append(dict(id=id,name=region_names[i],cost=[400,1200,2400,4500,7500,12000,18000,28000][i],explore_seconds=[60,120,150,200,250,300,350,400][i],return_seconds=[10,30,30,40,50,60,70,80][i],complete_returns=[10,6,6,5,5,5,5,6][i],previous_region=REGION_IDS[i-1] if i else None,reputation=10 if i==0 else 0,material=MATERIAL_IDS[i],repeat_material_quantity=1 if i<6 else 2,legacy_starleaf_quantity=2 if i==0 else 0))
    upgrades=[]
    def series(id,name,costs,gates,effects,kind='equipment',reputation=0):
        for i,(cost,gate,effect) in enumerate(zip(costs,gates,effects),1):
            upgrades.append(dict(id=f'{id}_{i:02}',track=id,name=name,kind=kind,stage=i,cost=cost,completed_regions=gate,reputation=reputation,effect=effect))
    # Existing 14 cauldron / 11 garden purchases retain their exact formulas.
    series('cauldron','솥',[round_g(30*1.55**i) for i in range(14)]+[8000,11000,15000,20000,26000,34000],[0]*14+[4,5,6,7,8,8],[{'base_brew_seconds':max(.8,5*.88**i)} for i in range(1,15)]+[{'quality_sale_bonus':round(.02*i,2)} for i in range(1,7)])
    series('herb_pot','기본 화분',[round_g(24*1.55**i) for i in range(11)]+[4000,7000,11000,16000],[0]*11+[2,3,5,7],[{'harvest_seconds':max(.8,4*.86**i),'herb_capacity':24+8*i,'harvest_quantity':2} for i in range(1,12)]+[{'harvest_seconds':.8,'herb_capacity':112+16*i,'harvest_quantity':2+i} for i in range(1,5)])
    series('sales_counter','판매대',[300,600,1000,1600,2400,3600,5400,8000,12000,18000],[0,0,1,2,3,4,5,6,7,8],[{'customer_seconds':round(3.2-.12*i,2)} for i in range(1,11)])
    series('precision_filter','정밀 여과기',[300,900,2100,4500,9000,18000],[0,2,3,5,6,8],[{'success_bonus':round(.04+.01*i,2)} for i in range(1,7)])
    series('herb_storage','약초 보관 선반',[200,350,600,1000,1700,2800,4600,7600,12000,20000],[1,1,2,2,3,4,5,6,7,8],[{'special_capacity':12+3*i} for i in range(1,11)])
    series('potion_cabinet','물약 보관장',[400,700,1200,2200,4000,7000,12000,20000],list(range(1,9)),[{'total_potion_capacity':12+6*i,'visible_capacity':12} for i in range(1,9)])
    series('drying_rack','건조대',[500,900,1600,2800,5000,9000,16000,28000],list(range(1,9)),[{'new_material_growth_multiplier':round(1+.05*i,2)} for i in range(1,9)])
    series('expedition_path','원정 길 정비',[600,1100,2000,3600,6500,12000,22000,40000],list(range(1,9)),[{'trip_time_reduction':round(.02*i,2)} for i in range(1,9)])
    families=[dict(id=id,name=name,customer=CUSTOMERS[id]) for name,id in FAMILIES.items()]
    for f in families:
        series('family_'+f['id'],f['name']+' 계열',[450,1300,3500,8000,18000],[1,2,4,6,8],[{'preferred_sale_bonus':round(.03*i,2)} for i in range(1,6)],'family')
    employees=[dict(id='sales_assistant',name='판매 보조',cost=360,completed_regions=0,reputation=20,effect={'preferred_sale_flat':2}),dict(id='cultivation_assistant',name='재배 보조',cost=1800,completed_regions=2,reputation=0,effect={'new_material_growth_multiplier':1.1}),dict(id='brewing_assistant',name='조제 보조',cost=4500,completed_regions=4,reputation=0,effect={'new_recipe_time_multiplier':.95,'new_recipe_quality_bonus':.02}),dict(id='expedition_guide',name='원정 길잡이',cost=2400,completed_regions=3,reputation=0,effect={'trip_time_reduction':.04})]
    series('sales_assistant','판매 보조 훈련',[300,600,1700,4000,9000],[0,1,3,5,7],[{'preferred_sale_flat':2+i} for i in range(1,6)],'training',20)
    series('cultivation_assistant','재배 보조 훈련',[900,1800,3600,7200,14400],[2,3,4,6,8],[{'new_material_growth_multiplier':round(1.1+.03*i,2)} for i in range(1,6)],'training')
    series('brewing_assistant','조제 보조 훈련',[2200,4400,8800,17600,35200],[4,5,6,7,8],[{'new_recipe_time_multiplier':round(.95-.01*i,2),'new_recipe_quality_bonus':round(.02+.01*i,2)} for i in range(1,6)],'training')
    series('expedition_guide','원정 길잡이 훈련',[1200,2400,4800,9600,19200],[3,4,5,6,8],[{'trip_time_reduction':round(.04+.02*i,2)} for i in range(1,6)],'training')
    assert len(upgrades)==125
    for cat,items in [('potions',potions),('materials',materials),('regions',regions),('employees',employees),('families',families)]:
        for item in items:
            item['icon_candidate']=f"res://assets/content_expansion_v1/{cat}/{item['id']}_icon.png"
            if cat=='potions':item['bottle_candidate']=f"res://assets/content_expansion_v1/potions/{item['id']}_12x16.png"
    catalog=json.loads((ROOT/'assets/content_expansion_v1/catalog.json').read_text(encoding='utf-8-sig'))
    for cat,items in [('potions',potions),('materials',materials),('regions',regions),('employees',employees),('families',families)]:
        existing={a['id'] for a in catalog['assets'] if a['category']==cat}
        assert {x['id'] for x in items}<=existing,(cat,'asset IDs not aligned')
    # Candidate B retains legacy costs, reduces later expansion spending.
    for p in potions:
        p['grant_sources']=[] if p['existing'] else [m for m in p['ingredients'] if m not in ['herb','moon_mushroom']]
        if p['order']>=14:p['cost']=round_g(p['cost']*(.9 if p['order']>=29 else .85)/10)*10
    for i,r in enumerate(regions):
        if i>=3:r['cost']=round_g(r['cost']*.85/10)*10
    for u in upgrades:
        existing=(u['track']=='cauldron' and u['stage']<=14) or (u['track']=='herb_pot' and u['stage']<=11) or (u['track']=='precision_filter' and u['stage']==1)
        if not existing:u['cost']=round_g(u['cost']*.8/10)*10
    for e in employees:
        if e['id']!='sales_assistant':e['cost']=round_g(e['cost']*.85/10)*10
    data=dict(schema_version=1,status='proposal_not_runtime',date='2026-10-08',revision='candidate-b',rules=dict(day_seconds=240,weather_seconds=90,brew_floor=.8,trip_reduction_cap=.30,base_brew_seconds=5,base_harvest_seconds=4,base_herb_capacity=24,base_potion_capacity=12,base_customer_seconds=3.2,first_material_grant_quantity=2,grant_existing_starleaf=False,sale_formula='round(base*(1+cauldron_quality+new_recipe_quality)*(1+preferred_family_bonus))+preferred_employee_flat',family_order=list(FAMILIES.values()),supplier=dict(interval=12,quantity=2,cost=4,reserve=30,capacity=6)),materials=materials,potions=potions,regions=regions,upgrades=upgrades,employees=employees,families=families)
    # Candidate C changes only sales throughput and the final two brewing trainings.
    data['revision']='candidate-c'
    data['changes_from_b']={'sales_counter_customer_seconds':[3.05,2.8,2.4,2.1,1.9,1.7,1.65,1.6,1.55,1.5], 'brewing_training_new_recipe_time_multiplier':[.94,.93,.92,.82,.72], 'costs_changed':False,'storage_changed':False,'environment_demand_changed':False}
    for u in upgrades:
        if u['track']=='sales_counter':u['effect']['customer_seconds']=data['changes_from_b']['sales_counter_customer_seconds'][u['stage']-1]
        if u['track']=='brewing_assistant':u['effect']['new_recipe_time_multiplier']=data['changes_from_b']['brewing_training_new_recipe_time_multiplier'][u['stage']-1]
    HERE.mkdir(parents=True,exist_ok=True)
    (HERE/'content-data-v1.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    render_tables(data)
    print(f"Created {len(potions)} recipes, {len(materials)} materials, {len(regions)} regions, {len(upgrades)} investments; art IDs aligned.")
    return data

def render_tables(data):
    out=['# 콘텐츠 연결표와 가격표','',f"작성일: {data['date']} · 데이터 버전: {data['revision']} · **밸런스 후보, 게임 미적용**",'',
         '물약 32종·재료 11종·지역 8곳·설비와 계열 및 직원 훈련 125행·직원 고용 4행을 하나의 데이터로 연결한다. 영문 ID는 제작 중인 디자인 목록과 대조했다. 아래 가격과 효과는 테스트 후보이며 기존 5종과 기존 솥·화분·최초 여과기·판매 보조·숲 가격은 유지한다.','',
         '[원본 JSON](balance/content-data-v1.json) · [성장 계산 결과](성장-속도-검증.md) · [장기 기획](장기-콘텐츠-확장-기획안.md)','',
         '## 데이터 적용 규칙','',
         '- `id`는 저장·레시피·아이콘 연결에 사용한다. 기존 체력·마나의 bool 저장값은 각각 health·mana로 읽는 호환 계층을 개발할 때 추가한다. 이번 데이터 작성은 저장을 변환하지 않는다.',
         '- `completed_regions`는 지역 조사를 끝낸 개수다. 원정으로 시간을 기다리기만 하면 비용이 자동 결제되는 규칙은 없다.',
         '- 강화 `effect`는 해당 단계의 **최종값**이며 이전 단계 값을 다시 누적하지 않는다. 단계 구매는 반드시 앞 단계를 보유해야 한다. 훈련은 해당 직원 고용이 선행 조건이다.',
         '- 원정 시간 단축은 길 정비와 원정 직원의 최종값을 더하고 30%에서 제한한다. 회차 시작에 시간·지역·보상을 고정한다.',
         '- 신규 레시피 구매 때 grant_sources에 있는 재료의 미보유 재배 공급원과 시작 재료 2개를 품종별 한 번 지급한다. 이전 지역의 품종이 필요한 복합 레시피도 포함한다. 이미 연 공급원은 중복 지급하지 않는다. 기존 5종은 기존 공급 규칙을 유지한다.',
         '- 재료 부족 시 해당 레시피를 건너뛰고 같은 계열 하위 품목, 이어 다른 계열로 진행한다. 기본 체력·마나 제조는 유지한다.',
         '- 신규 전리품의 대기 수량은 종류별로 합산한다. 조사와 입고를 분리하며 이미 입고한 수량은 재실행 때 재지급하지 않는다.',
         '- 에셋 경로는 연결 후보다. ID 대조가 해당 에셋의 제작 완료·실사용 적합성을 의미하지 않는다. 공용 디자인 폴더는 이 작업에서 수정하지 않는다.', '',
         '## 기존 저장을 읽을 때의 연결','',
         '| 기존 값 | 신규 데이터 연결 | 보존할 것 |',
         '| --- | --- | --- |',
         '| 체력 false / 마나 true | health / mana | 재고 종류·순서, 진행 중 제조 |',
         '| moon / purify / agility | 동일 ID | 보유와 구매 완료, 별잎 공급 |',
         '| 솥 level / 화분 garden_level | 해당 track의 stage = level − 1 | 14회·11회 기존 강화와 진행률 |',
         '| filter_owned = true | precision_filter 1단계 보유 | 기존 성공률 +5%p, 설치비 재결제 금지 |',
         '| employee = true | sales_assistant 고용 완료 | 기존 선호 거래 +2 G, 고용비 재결제 금지 |',
         '| expedition_unlocked | forest_edge 소유 | 진행·누적 귀환·미입고 보상, 해금비 재결제 금지 |',
         '| 기존 mushroom 수량 | moon_mushroom 수량 | 기존 구매 비용·예비금·발주 진행 |','',
         '기존 숲 귀환을 해당 지역 조사 기록으로 인정하는 이행안을 제안한다. 발견은 도입 후 한 번만 기록하고 과거 귀환 재료를 소급 지급하지 않는다. 소유한 공급원에 시작 재료도 다시 주지 않는다. 실제 저장 버전 이행과 백업 복구는 개발 단계에서 검증한다.','',
         '## 물약과 레시피','', '| ID | 이름 | 계열 | 구매비 G | 판매가 G | 재료 | 시간 배율 | 기본 성공률 | 해금 |','| --- | --- | --- | --- | --- | --- | --- | --- | --- |']
    for p in data['potions']:
        u=p['unlock']; gate='기본 보유' if p['owned_at_start'] else ', '.join(([f"{u['discovery']['region']} {u['discovery']['returns']}회"] if 'discovery'in u else [])+([f"명성 {u['reputation']}"] if u.get('reputation') else [])+u.get('recipes',[])) or '구매 가능'
        out.append(f"| {p['id']} | {p['name']} | {p['family']} | {p['cost']:,} | {p['sale_price']} | {' + '.join(f'{k} {v}' for k,v in p['ingredients'].items())} | ×{p['duration_multiplier']:g} | {p['success']*100:g}% | {gate} |")
    out += ['','## 재료','', '| ID | 이름 | 기본 자동 공급 | 환경 | 초기 보관 |','| --- | --- | --- | --- | --- |']
    for m in data['materials']:
        supply= f"{m['growth_seconds']}초/1개" if 'growth_seconds'in m else '12초마다 최대 2개, 개당 4 G' if m['id']=='moon_mushroom' else '4초/2개, 화분 강화 적용'
        out.append(f"| {m['id']} | {m['name']} | {supply} | {m.get('environment','없음')} | {m['capacity']} |")
    out += ['','## 원정','', '| ID | 지역 | 개방비 G | 탐색+귀환 초 | 조사 완료 | 선행 |','| --- | --- | --- | --- | --- | --- |']
    for r in data['regions']:out.append(f"| {r['id']} | {r['name']} | {r['cost']:,} | {r['explore_seconds']}+{r['return_seconds']} | {r['complete_returns']}회 | {r['previous_region'] or '명성 10'} |")
    out += ['','## 설비 계열 훈련 단계표','', '| 단계 ID | 항목 | 비용 G | 완료 지역 수 | 명성 | 최종 효과 |','| --- | --- | --- | --- | --- | --- |']
    for u in data['upgrades']:out.append(f"| {u['id']} | {u['name']} {u['stage']} | {u['cost']:,} | {u['completed_regions']} | {u['reputation']} | {' / '.join(f'{k}={v:g}' for k,v in u['effect'].items())} |")
    out += ['','## 직원 고용','', '| ID | 직원 | 비용 G | 완료 지역 수 | 명성 | 고용 효과 |','| --- | --- | --- | --- | --- | --- |']
    for e in data['employees']:out.append(f"| {e['id']} | {e['name']} | {e['cost']:,} | {e['completed_regions']} | {e['reputation']} | {' / '.join(f'{k}={v:g}' for k,v in e['effect'].items())} |")
    sums={k:sum(x['cost'] for x in data[k]) for k in ['potions','regions','upgrades','employees']}
    out+=['','## 전체 구매 예산','', '| 종류 | 전체 비용 G |','| --- | --- |']
    for k,title in [('potions','레시피'),('regions','지역'),('upgrades','설비·계열·훈련'),('employees','직원 고용')]:out.append(f"| {title} | {sums[k]:,} |")
    out.append(f"| 합계 | {sum(sums.values()):,} |")
    out+=['','자동 버섯 구매비는 위 영구 투자 예산에 포함하지 않는다. 실제 매출·재료비·구매 시점·대기 결과는 성장 계산 결과에서 확인한다.','']
    (ROOT/'docs/콘텐츠-연결표와-가격표.md').write_text('\n'.join(out),encoding='utf-8')

if __name__=='__main__':build()
