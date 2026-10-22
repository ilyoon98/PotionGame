from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]; b=r/'.verification/f20-20261020'; doc=r/'docs/판매-재고-보호와-작업실-운영-확장-개발결과.md'
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def stamp(t):
 if t is None:return '48시간 내 미도달'
 t=round(t);return f'{t//3600}시간 {t//60%60}분 {t%60}초'
a=load(b/'audit.json'); assert a['passed'] and not a['partial']
text=doc.read_text(encoding='utf-8').split('\n<!-- GENERATED F20 MEASUREMENTS -->')[0]
text=text.replace('개발 진행 중 · 최종 기획 검수 전','기능 구현·검사 완료 · 운영 보완 선택 및 최종 기획 검수 대기')
text=text.replace('17개 통과','18개 통과').replace('B/ui.json · ui/functional.log','B/ui.json · ui/current-functional.log').replace('1,719개','1,736개')
text=text.replace('48시간까지 실제 진행하고 있다. 먼저 완료한 경로에서는','48시간까지 모두 실제 진행했다. 초기안의6경로 모두')
if '| 대금·발주 동일 시각 경계 |' not in text:
 text=text.replace('| 확장 미구매의 무료 보호 모델과 전체 상태 동일·중간 구매 | B/unpurchased.json · unpurchased.log | 1,269개 통과 |','| 확장 미구매의 무료 보호 모델과 전체 상태 동일·중간 구매 | B/unpurchased.json · unpurchased.log | 1,269개 통과 |\n| 창고 변경·동시 완료·중복 정산 방지 | B/edges.json | 15개·실제5회차 통과 |\n| 대금·발주 동일 시각 경계 | B/payment-boundary-pass.json | 전체 상태 분할 진행1개 통과 |')
lines=['','<!-- GENERATED F20 MEASUREMENTS -->','## 최초안의 실제 측정표','','확장 전 제작 시간까지 동결했던 초기 후보의 자연 성장은 아래 이력이며, 그 회귀를 수정한 최종 모델의 측정은 별도 표로 구분한다. 기존 최대 성장 가게의2시간 효과 비교는 중간 강화가 없어 이 수정의 영향을 받지 않는다. 초기 가격/배율은 유지했다.','','| 시드 / 공급 | 보호 없음 순수입 | 무료 보호 | 확장 기본 | 개선1 | 개선2 |','| --- | ---: | ---: | ---: | ---: | ---: |']
for seed in (73129,19337,9973):
 for scenario in ('normal','scarce_upper'):
  cases={x['stage']:x for x in a['effect_cases'] if x['seed']==seed and x['scenario']==scenario}
  lines.append('| '+str(seed)+' / '+('정상' if scenario=='normal' else '상위 부족')+' | '+' | '.join(f"{cases[key]['net']:,}" for key in ('original','protected','stage1','stage2','stage3'))+' |')
lines+=['','각 효과 경로의 현금/미정산·판매/납품·재료/원정비·재고0/손님 대기/평균 재고·선별 가동은 A/effects/, effects/, diagnostics/에 있다. 진단12재생은 처음 A의 현금·판매·납품을 그대로 재현하면서 솥 점유/재료 대기를 계측했다. 기존 납품 점유는1,492~1,506초/2시간이다. 보호의 판매 제작은7,174~7,200초이며 일반 재료 대기는0초였다. 납품 없음 대조군도 회복하지 못하는 사례는 판매 수요 대비 일반 생산의 한계로 남긴다.','','| 시드 / 복귀 | 24h 잔고 | 36h 잔고 | 48h 잔고 | 최종 F19 | 신규 완료 |','| --- | ---: | ---: | ---: | --- | --- |']
for x in a['growth_cases']:
 if x['returning'] or x['control']:continue
 lines.append(f"| {x['seed']} / {x['return_seconds']}초 | {x['balances']['24']:,} | {x['balances']['36']:,} | {x['balances']['48']:,} | 보급1·일괄1 | {stamp(x['complete_seconds'])} |")
lines+=['','동일한 보호-F19 대조6경로는 각15분 체크포인트와 구매 이력이 일치했다. 모두 마지막 관찰 협의가2등급이었다. 완료된 구매 사이 최대 간격은90~120분, 마지막 구매 후 남은 무구매 구간은약39.5~40.4시간이다.36~48시간 완료 목표 및 큰 기능1~3시간 대기 방향을 충족하지 못했다. 가격이 충분해도 등급 조건에 막혔으므로 가격 인하만으로 해결된다고 결론 내리지 않는다.']
ret=next(x for x in a['growth_cases'] if x['returning'])
lines+=['','### 합성270만 복귀 · 최초안','','실제 사용자 저장/24시간 수입 추정이 아니다. 보유 골드270만·기존 성장/F19 완료를 합성한 시작 상태다. 자동 구매는 시뮬레이션의 사용자 복귀 판단에서만 수행하며 생산 게임에 강화 자동 구매를 추가하지 않았다.','','| 신규 구매 | 관찰 시각 | 직전 잔고 | 실제 지불 | 직후 잔고 |','| --- | --- | ---: | ---: | ---: |']
for p in ret['new_purchases']:lines.append(f"| {['확장','개선1','개선2'][p['stage']-1]} | {stamp(p['time'])} | {p['gold_before']:,} | {p['cost']:,} | {p['gold_after']:,} |")
lines+=['',f"최대 신규 구매 간격은{stamp(ret['max_closed_purchase_gap'])}이다. 첫 구매까지30만을 실제 영업으로 모았으며 총750만을 즉시 지급하지 않았다.24/36/48h 실제 잔고는{ret['balances']['24']:,}/{ret['balances']['36']:,}/{ret['balances']['48']:,}이다. 새로 시작한 가게의 완료 시간으로 일반화하지 않는다."]
final=b/'audit-current.json' if (b/'audit-current.json').exists() else b/'audit-protected-final.json'
if final.exists():
 z=load(final); assert z['passed'] and not z['partial']
 lines+=['','## 최종 미구매 회귀 수정 모델의 자연 성장','','확장 구매 전의 기존 진행률/강화 시간 계산을 복구한 protected-final-model의 새로운12경로와 합성 복귀1경로다. 초기 이력을 덮지 않았다.','','| 시드 / 복귀 | 24h 잔고 | 36h 잔고 | 48h 잔고 | F19 완료 | 신규 완료 |','| --- | ---: | ---: | ---: | --- | --- |']
 for x in z['growth_cases']:
  if x['returning'] or x['control']:continue
  lines.append(f"| {x['seed']} / {x['return_seconds']}초 | {x['balances']['24']:,} | {x['balances']['36']:,} | {x['balances']['48']:,} | {stamp(x['f19_complete_seconds'])} | {stamp(x['complete_seconds'])} |")
 lines+=['',f"독립 감사는{z['checks']:,}개 대조를 통과했다. 원자료와 보완안 선택 대기는 별개이며 F20 최종 검수 완료를 의미하지 않는다."]
 if z.get('returning_override'):
  q=next(x for x in z['growth_cases'] if x['returning'])
  lines+=['','### 대금 경계 수정과 최종 복귀 재생','','대금 정산과 약초 수확/발주가 동시에 일어날 때0.2초 진행과0.1+0.1초 진행이 각각 마나/체력으로 갈리던 실제 문제를 별도 fixture에서 재현했다. 보조 대금 직후 새 예약보다 먼저 준비된 발주를 처리해 전체 상태가 같아지는 것을 확인했다. B/payment-before.log와 B/payment-boundary-before.json은 재현 이력이며, 최종 payment-fixed 로그/JSON과 구분한다.','',f"현재 코드의 payment-fixed-model로 합성270만 복귀를48시간 다시 진행했다. 최종 완료는{stamp(q['complete_seconds'])},24/36/48h 잔고는{q['balances']['24']:,}/{q['balances']['36']:,}/{q['balances']['48']:,}이다.12개의 자연 성장 경로는 확장을 사지 않아 이 추가 보조 정산 분기에 들어가지 않는다.2시간 효과/후보 비교는 초기 현금에서 전체 비용을 빼도 발주 예비금보다 많으므로 정산이 없어 발주를 못 사는 경계가 발생할 수 없음을 독립 감사로 확인했다. 이전 원자료를 덮지 않고 실제 변경이 영향을 줄 수 있는 복귀 경로만 재생했다."]
else:lines+=['','최종 미구매 회귀 수정 모델의13경로는 protected-final/에서 별도로 진행 중이다. 초기 표를 수정 모델의 결과로 표시하지 않는다.']
lines+=['','## 변경 파일과 소스 해시','','- 기존 런타임 수정: scripts/shop_state.gd, shop_contracts.gd, shop.gd, management_panel.gd, management_status.gd.','- 새 모듈: scripts/shop_stock_protection.gd, shop_workshop_operations.gd.','- 검증 공통 도구: tools/export_management_layout.gd에 특정 행으로 스크롤하는 파일 미리보기 옵션만 추가.','- F19 가격/보급 모듈과 원래 콘텐츠 데이터/아트는 바꾸지 않았다.','', '| 파일 | 현재 SHA256 |','| --- | --- |']
for name in ['shop_state.gd','shop_contracts.gd','shop_stock_protection.gd','shop_workshop_operations.gd','management_panel.gd','management_status.gd','shop.gd','shop_late_investments.gd']:
 p=r/'scripts'/name;lines.append(f'| scripts/{name} | {hashlib.sha256(p.read_bytes()).hexdigest()} |')
lines+=['','전체 해시/검증 도구 해시는 change-manifest.json과 audit*.json을 참조한다. 최초 모델 initial-model/, 미구매 타이밍 수정 모델 protected-final-model/, 대금 경계 수정 모델 payment-fixed-model/, 무료 보호만의 A/source/, 변경 전 baseline/의 해시를 혼용하지 않는다.','',f"최초안 독립 감사: {a['checks']:,}개 대조 통과. 30효과·13성장/복귀·진단12·미채택 대안6과 최종 기능 검사1,736개를 구분한다. 구매 직후 시작하는 원정의 출발비는 해금 가격과 분리해 현금 장부에 대조했다.",'','**현재 상태:** F20 기능/UI/저장 구현과 관련 검사는 마쳤지만, 초기 보호 정책이 자연 성장의 납품 등급을 막는다. 보완 후보의 적용 선택 및 적용 후 전체 경제 검수가 남아 있어 최종 완료로 표시하지 않는다.']
doc.write_text(text+'\n'.join(lines)+'\n',encoding='utf-8')
print('Updated developer results with actual raw tables; main planning acceptance unchanged')
