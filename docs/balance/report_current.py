"""Generate current planning report with matched-timestep B/C comparisons."""
from pathlib import Path
from collections import Counter
import json

HERE=Path(__file__).resolve().parent
NAMES={'expedition_first':'원정·레시피 우선','equipment_first':'설비 우선','return_15m':'15분마다 복귀 구매'}

def band(values,decimals=1):
    lo,hi=min(values),max(values)
    return f'{lo:.{decimals}f}' if lo==hi else f'{lo:.{decimals}f}~{hi:.{decimals}f}'

def pressure(run,start,end):
    ws=[w for w in run['pressure_windows'] if start<w['end_minute']<=end]
    total=sum(w['seconds'] for w in ws)
    assert abs(total-(end-start)*60)<1e-5
    return {k:100*sum(w[k] for w in ws)/total for k in ['full_seconds','waiting_seconds','inventory_ratio_seconds']}

def longest_full(run):
    longest=streak=0
    for w in run['pressure_windows']:
        is_full=w['inventory_ratio_seconds']/w['seconds']>=.9 and w['waiting_seconds']==0
        streak=streak+5 if is_full else 0
        longest=max(longest,streak)
    return longest

def main():
    d=json.loads((HERE/'content-data-v1.json').read_text(encoding='utf-8'))
    r=json.loads((HERE/'simulation-results.json').read_text(encoding='utf-8'))
    b=json.loads((HERE/'simulation-candidate-b-refined.json').read_text(encoding='utf-8'))
    bd=json.loads((HERE/'content-data-candidate-b.json').read_text(encoding='utf-8'))
    effects=json.loads((HERE/'upgrade-effect-results.json').read_text(encoding='utf-8'))
    fine=json.loads((HERE/'simulation-candidate-c-refinement-025.json').read_text(encoding='utf-8'))
    assert r['revision']==d['revision']==effects['revision']=='candidate-c'
    assert b['revision']=='candidate-b' and r['dt_seconds']==b['dt_seconds']==.05
    assert len(r['runs'])==len(b['runs'])==9
    for key,count in [('potions',32),('materials',11),('regions',8),('upgrades',125),('employees',4)]:
        assert len(d[key])==count and len({x['id'] for x in d[key]})==count
    assert Counter(u['kind'] for u in d['upgrades'])=={'equipment':85,'family':20,'training':20}
    mids={m['id'] for m in d['materials']};rids={x['id'] for x in d['regions']}
    for p in d['potions']:
        assert set(p['ingredients'])<=mids
        if not p['existing']:assert set(p['grant_sources'])==set(p['ingredients'])-{'herb','moon_mushroom'}
        if 'discovery' in p['unlock']:assert p['unlock']['discovery']['region'] in rids
    for key in ['potions','materials','regions','employees','families']:assert d[key]==bd[key]
    assert d['rules']==bd['rules']
    for u,old in zip(d['upgrades'],bd['upgrades']):
        assert u['id']==old['id'] and u['cost']==old['cost']
        assert {k:v for k,v in u.items() if k!='effect'}=={k:v for k,v in old.items() if k!='effect'}
        if u['track'] not in ['sales_counter','brewing_assistant']:assert u==old
    for run in r['runs']+b['runs']:
        assert run['all_regions_min']>=141+52/60 and run['all_recipes_min']>120
        for c in run['checkpoints']:
            assert c['gold']==c['gross']-c['materials']-c['spent'] and c['gold']>=0
            assert 0<=c['stock']<=c['stock_capacity']
            if c['minute']==120:assert c['recipes']<32 and c['completed_regions']<8 and c['investments']<125
    for case in effects['cases']:
        before,after=case['before'],case['after']
        if case['track']=='sales_counter':assert after['sold']>before['sold'] and after['full_pct']<before['full_pct']
        else:assert after['waiting_pct']<before['waiting_pct']
    assert fine['dt_seconds']==.025 and fine['revision']==d['revision']
    active=[x for x in r['runs'] if x['policy']=='expedition_first']
    lines=['# 성장 속도 계산 결과','',
        '작성일: 2026년 10월 8일 · 후보: candidate-c · **기획용 독립 모델, 실제 Godot 검증 전**','',
        f"**9회 모두 2시간에 남은 레시피·지역·강화가 있다.** 원정·레시피 우선의 전체 레시피는 {band([x['all_recipes_min'] for x in active])}분, 전체 투자와 고용은 {band([x['all_investments_min'] for x in active])}분이다. 중반 적체는 감소했고 강화 효과도 별도 비교했으나, 모든 전략에서 반복적인 품절과 적체가 확보된 최종 밸런스는 아니다.",'',
        '[콘텐츠 연결표](콘텐츠-연결표와-가격표.md) · [조정안과 개발 연결 기준](제작과-판매-밸런스-조정안.md) · [계산 기록](balance/simulation-results.json)','',
        '## 계산 조건','',
        '- 32물약·11재료·8지역·125투자·4직원, 골드 0·기본 약초 6·체력과 마나 보유에서 시작한다. 데이터는 게임에 연결하지 않았다.',
        '- 기본 구매·제조·판매·원정은 자동이다. 투자 구매는 30초 또는 15분마다 플레이어가 판단하는 상황을 대리하는 정책이며, 실제 게임의 자동 강화 결제를 제안하지 않는다.',
        '- 하루 240초·날씨 90초, 환경 성장과 성공률, 선호 손님, 자동 버섯 구매비·30 G 예비금, 보관 한도, 실패, 재료 부족 시 하위 물약 복귀를 계산한다. 환경별 전체 방문 간격은 추가하지 않았다.',
        '- 초기 난수값 73129·19337·9973 × 3구매 전략 × 각 8시간이다. 손님 대기는 구매 시도 때 완성품이 없어서 같은 손님이 다음 거래까지 기다리는 시간이다.',
        '- B와 C를 모두 0.05초 간격으로 다시 계산했다. 이전 0.25초 B 결과와 직접 비교하지 않는다. 재료 수확·제조·판매는 틱 끝에 처리하므로 실제 엔진과 완전히 같지는 않다.',
        '- 5분 창의 재고 가득·품절 대기·평균 재고를 기록한다. 평균 재고는 전체 보관 한도 기준이며 화면에 그려진 병 슬롯과 구분한다.',
        '- 장기 원정 이론 하한 141분 52초는 원정 시간 단축 30%를 처음부터 모두 가진 가정이다. 실제 구매 비용·진행 조건이 추가되며 종료 중 정산과 저장 이전은 모델 범위 밖이다.','',
        '## 30분·1시간·2시간 진행','',
        '| 전략 | 시점 | 보유 물약 | 개방 지역 | 완료 지역 | 투자 단계 |','| --- | --- | --- | --- | --- | --- |']
    for policy,name in NAMES.items():
        runs=[x for x in r['runs'] if x['policy']==policy]
        for minute in [30,60,120]:
            cs=[c for x in runs for c in x['checkpoints'] if c['minute']==minute]
            lines.append(f"| {name} | {minute}분 | {band([c['recipes'] for c in cs],0)}/32 | {band([c['opened_regions'] for c in cs],0)}/8 | {band([c['completed_regions'] for c in cs],0)}/8 | {band([c['investments'] for c in cs],0)}/125 |")
    lines+=['','## 재고와 손님 대기','',
        '| 전략 | 구간 | 재고 가득 시간 | 품절 대기 시간 | 평균 재고 / 한도 |','| --- | --- | --- | --- | --- |']
    for policy,name in NAMES.items():
        runs=[x for x in r['runs'] if x['policy']==policy]
        for start,end in [(0,30),(30,60),(60,120),(120,240),(240,480)]:
            vs=[pressure(x,start,end) for x in runs]
            lines.append(f"| {name} | {start}~{end}분 | {band([v['full_seconds'] for v in vs])}% | {band([v['waiting_seconds'] for v in vs])}% | {band([v['inventory_ratio_seconds'] for v in vs])}% |")
    lines+=['','## 같은 계산 간격의 B와 C 비교','',
        '| 전략 | 120~240분 B 평균 재고 | C 평균 재고 | B 품절 대기 | C 품절 대기 |','| --- | --- | --- | --- | --- |']
    for policy,name in NAMES.items():
        old=[pressure(x,120,240) for x in b['runs'] if x['policy']==policy];new=[pressure(x,120,240) for x in r['runs'] if x['policy']==policy]
        lines.append(f"| {name} | {band([x['inventory_ratio_seconds'] for x in old])}% | {band([x['inventory_ratio_seconds'] for x in new])}% | {band([x['waiting_seconds'] for x in old])}% | {band([x['waiting_seconds'] for x in new])}% |")
    lines+=['','평균만으로 병목 교대를 단정하지 않고 5분별 기록도 남긴다.','',
        '| 전략 | C의 재고 90% 이상·품절 없음 최장 연속 구간 |','| --- | --- |']
    for policy,name in NAMES.items():lines.append(f"| {name} | {band([longest_full(x) for x in r['runs'] if x['policy']==policy],0)}분 |")
    lines+=['','30분 넘는 적체 구간은 후속 조정 대상으로 남긴다. 강화 하나만으로 품절과 적체가 반드시 역전되는 규칙을 강제하지 않는다. 설비 우선은 새 레시피보다 제작 강화를 먼저 사서 초기·중반 적체가 오래 유지될 수 있다.','',
        '## 강화 효과 분리 비교','',
        '90·150·300분의 진행 상태에서 지정한 두 단계만 바꾸고 다른 구매를 10분 동안 멈췄다. 일부 기준 단계는 비교를 위해 치환했다. 실제 골드를 지불하는 플레이 테스트가 아니라 효과 분리 실험이다. 같은 재고·재료·환경·난수 상태에서 출발하며 이후 사건 순서에 따라 난수 소비가 달라질 수 있다. [실험 원본](balance/upgrade-effect-results.json)','',
        '| 비교 | 기준 | 강화 후 |','| --- | --- | --- |']
    for track,label,metric in [('cauldron','90분 솥 10→11: 품절 대기 시간','waiting_pct'),('sales_counter','150분 판매대 5→6: 재고 가득 시간','full_pct'),('brewing_assistant','300분 조제 훈련 4→5: 품절 대기 시간','waiting_pct')]:
        cases=[x for x in effects['cases'] if x['track']==track]
        lines.append(f"| {label} | {band([x['before'][metric] for x in cases])}% | {band([x['after'][metric] for x in cases])}% |")
    lines+=['','판매대 5→6은 10분 판매 병 수를 늘리고 제조 정지 시간을 줄였지만 해당 비교 상태의 재고를 완전히 비우지는 않았다. 조제 훈련 5는 품절을 줄인 뒤 다시 재고가 쌓이는 방향으로 작용했다.','',
        '## 주요 콘텐츠와 투자 완료 시점','',
        '| 전략 | 8지역 조사 | 32레시피 구매 | 125투자·4직원 |','| --- | --- | --- | --- |']
    for policy,name in NAMES.items():
        runs=[x for x in r['runs'] if x['policy']==policy]
        lines.append(f"| {name} | {band([x['all_regions_min'] for x in runs])}분 | {band([x['all_recipes_min'] for x in runs])}분 | {band([x['all_investments_min'] for x in runs])}분 |")
    coarse=next(x for x in active if x['seed_initial']==73129)
    cp=pressure(coarse,120,240);fp=pressure(fine,120,240)
    max_delta=max(abs(coarse[k]-fine[k]) for k in ['all_regions_min','all_recipes_min','all_investments_min'])
    lines+=['','레시피 구매 완료는 모든 첫 제조·도감·장식·단골 이야기를 끝냈다는 뜻이 아니다. 3~5시간 주요 콘텐츠 목표는 모든 구매 전략에서 충족한 상태가 아니며, 강제 구매 순서로 맞추지 않는다.','',
        '## 계산 간격 민감도','',
        f"원정·레시피 우선, 초기 난수 73129만 0.025초 간격으로 한 번 더 계산했다. 120~240분 평균 재고는 0.05초에서 {cp['inventory_ratio_seconds']:.1f}%, 0.025초에서 {fp['inventory_ratio_seconds']:.1f}%였다. 지역·레시피·전체 투자 완료 시점의 차이는 최대 {max_delta:.1f}분이었다. 적체 감소 방향과 2시간 미완료는 유지되지만 재고 비율은 계산 간격에 민감하므로 정확한 엔진 수치로 약속하지 않는다. [정밀 계산 기록](balance/simulation-candidate-c-refinement-025.json)",'',
        '## 검증 범위와 다음 단계','',
        '- 데이터 수·고유 ID·재료와 지역 참조·공급원, B 대비 가격과 원정 시간 보존, 18회 매출 장부·재고 한도·2시간 미완료, 9건 강화 효과 분리 비교를 확인했다.',
        '- 실제 게임 연결 후 제조·판매 시간과 재고를 다시 측정한다. 무구매 방치·일부 레시피 구매·옛 저장 복원·앱 재실행·개별 약초 부족·손님별 대기 길이는 개발 검증에 포함한다.',
        '- 후보 C는 개발 비교용 조정안이다. 화면 시안 선택, 경제 수치 승인, 저장 이전 구현과 최종 플레이 밸런스 확정은 별개다.','']
    (HERE.parent/'성장-속도-검증.md').write_text('\n'.join(lines),encoding='utf-8')
    print('PASS: content integrity, unchanged costs/regions, 18 ledgers and 2h goals, 9 paired upgrade effects; report generated.')

if __name__=='__main__':main()
