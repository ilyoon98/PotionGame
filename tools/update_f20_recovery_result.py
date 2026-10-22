"""Publish completed approved-policy evidence, retaining pre-approval history."""
from pathlib import Path
import json

r = Path(__file__).resolve().parents[1]
out = r / '.verification/f20-recovery-20261020'
audit = json.loads((out/'audit.json').read_text(encoding='utf-8'))
assert audit['passed'] and not audit['partial'] and len(audit['growth']) == 13
target = r / 'docs/판매-재고-보호와-작업실-운영-확장-개발결과.md'
text = target.read_text(encoding='utf-8')
marker = '<!-- APPROVED RECOVERY RESULTS -->'
end = '<!-- PRE-APPROVAL HISTORY -->'
if marker in text:
    title = text.split(marker)[0]
    history = text.split(end,1)[1]
else:
    title, history = text.split('\n',1)
    title += '\n\n'
    history = history.replace('2026-10-20 · 기능 구현·검사 완료 · 운영 보완 선택 및 최종 기획 검수 대기', '')
    history = '\n\n## 승인 전 구현·측정 이력\n\n아래 내용은 보완 승인 전 실패 원인과 초기 후보의 보존 기록이다. 현재 구현·검증 상태는 위 최신 승인 기록을 따른다.\n'+history
history = history.replace('**수정 후보는 별도이며 아직 적용하지 않았다.**', '**승인 전 별도 후보 측정 기록이다.**')
history = history.replace('기존 제조 후보 정책을 유지하라는 명세와 충돌하므로, 회복 중 기본 물약 우선 후보는 사용자에게 선택을 요청한 상태다. 답변 전에는 생산 코드에 적용하지 않는다.', '당시 기존 제조 후보 정책을 유지하는 명세와 충돌해 사용자 선택을 요청했고, 승인 전에는 생산 코드에 적용하지 않았다. 이후 사용자가 기본 물약 우선을 승인한 결과는 위 최신 기록을 따른다.')
history = history.replace('**현재 상태:**', '**승인 전 상태:**')

def clock(value):
    if value is None:
        return '—'
    seconds = int(round(value))
    return f'{seconds//3600}시간 {(seconds%3600)//60}분'

lines = [marker,
    '2026-10-20 · **사용자 승인 보완 구현·검증 완료** · 초기 가격의 최종 밸런스 채택은 별도', '',
    '## 최신 승인 반영 · 회복 중 기본 물약 우선 — 완료', '',
    '사용자 답변 “회복 중 기본 물약 우선 적용”을 반영했다. 재고 보호가 켜진 동안 약초2개가 있으면 빠른 기본 체력 물약을 먼저 만든다. 회복선 H에 도달하면 기존 첫 제조·고급/특별 물약 선택과 납품으로 돌아간다. 약초가 없을 때는 만들 수 있는 기존 대체 레시피를 그대로 사용한다. L/H 기준·판매 속도·물약 가격·재료 수급·확장 비용·개선 배율은 바꾸지 않았다.', '',
    '실제 예약과 미리보기는 같은 순수 조건을 사용한다. 기본 물약은 기존 성공률100%와 약초2개만 사용하며, 기존 제조/특별/납품 난수와 레시피 순환 커서를 바꾸지 않는다. 진행 중 메인·보조 배치는 취소하거나 다시 결제하지 않는다. 확장 구매 시 진행 중 기본 물약의 시간도 그대로 이어간다. 저장 버전12의 기존 필드만 사용하므로 추가 이관은 필요 없다.', '',
    f"추가 정책·미구매 회귀·기존 F19·UI·저장·경계 검사의 **{audit['functional_total']:,}개 검사**와 독립 원자료 감사 **{audit['checks']:,}개 대조**를 통과했다. 실제 영업 상태의601초 일괄 진행과1초씩601회 진행도 확장0~3단계/공급2조건에서 전체 상태가 일치했다. 초기 테스트 작성 중 수치 Dictionary의float/int 직접 비교와 ‘항상 일반 배치’ 가정 오류는 검사 쪽에서 수정했고 실패 로그도 보존했다. 최종 통과 로그는 checks/recovery-final.log, unpurchased-final.log를 따른다.", '',
    '## 승인 보완 후 실제2시간 효과 · 24조건', '',
    '아래는 기존 성장·F19를 끝낸 합성 초기 상태에서 기존 영업·자동 구매·원정·실제 납품/정산을2시간 진행한 결과다. 세팅 골드는 측정 수입에서 제외했다. 순수입은 판매+실제 납품 대금−재료비−원정비이며 미정산/WIP는 현금에 더하지 않았다.', '',
    '| 시드 / 공급 | 무료 보호만 | 확장 기본형 | 개선1 | 개선2 |',
    '| --- | ---: | ---: | ---: | ---: |']
for seed in (73129,19337,9973):
    for scenario, label in [('normal','정상'),('scarce_upper','상위 재료 부족')]:
        cases = sorted((x for x in audit['effects'] if x['seed']==seed and x['scenario']==scenario),key=lambda x:x['stage'])
        lines.append(f'| {seed} / {label} | ' + ' | '.join(f"{x['net']:,}" for x in cases)+' |')
zeros = [x['zero'] for x in audit['effects']]
aux = [x['aux_seconds'] for x in audit['effects'] if x['stage']>0]
lines += ['', f"24조건 모두 재고0 시간은 {min(zeros):.1f}초~{max(zeros):.1f}초였다. 유료18조건의 보조 실제 가동은 {min(aux):,.1f}초~{max(aux):,.1f}초/2시간이다. 보호 때문에2시간 내내 납품·보조 가동이0이던 초기안과 구분한다. 모든 실제 배치의 물약/병수/소비 재료와 중복 없는 회차 정산을 원자료로 대조했다.", '',
    '## 새 게임0골드 실제48시간 성장 · 시드3개×복귀2종', '',
    '골드·등급·납품 실적을 주입하지 않고 새 State에서 시작했다. 복귀할 때 기존/후반 투자/확장을 실제 가격으로 구매하는 합성 사용자만 사용한다. 다음 시간은 실제 이벤트를 진행해 기록한 시점이며 가격÷예상 수입으로 계산하지 않았다.', '',
    '| 시드 / 복귀 | F19 완료·확장 해금 | 확장 구매 | 개선1 구매 | 개선2 완료 | 24h 잔고 | 36h 잔고 | 48h 잔고 |',
    '| --- | --- | --- | --- | --- | ---: | ---: | ---: |']
fresh = [x for x in audit['growth'] if not x['control'] and not x['returning']]
for x in sorted(fresh,key=lambda x:(x['seed'],x['return_seconds'])):
    purchases = x['purchases']
    lines.append(f"| {x['seed']} / {x['return_seconds']}초 | {clock(x['unlock'])} | {clock(purchases[0]['time'])} | {clock(purchases[1]['time'])} | {clock(x['complete'])} | " + ' | '.join(f"{x['balances'][str(h)]:,}" for h in (24,36,48))+' |')
lines += ['', '확장 구매를 하지 않는 보호-F19 대조6경로도 별도로48시간 진행했다. 새 경로와 대조 경로는 첫 확장 구매 전15분 체크포인트 전체 상태가 일치하며, 둘 다 실제 거래4등급과 F19 양쪽3단계에 도달했다. 기존48시간 내내 등급2/F19 양쪽1단계에 머물던 해금 정체는 해소됐다.', '',
    '| 시드 / 복귀 | 보호-F19만 48h 잔고 | 확장·개선 구매 후 48h 잔고 |',
    '| --- | ---: | ---: |']
for x in sorted(fresh,key=lambda x:(x['seed'],x['return_seconds'])):
    control = next(y for y in audit['growth'] if y['control'] and y['seed']==x['seed'] and y['return_seconds']==x['return_seconds'])
    lines.append(f"| {x['seed']} / {x['return_seconds']}초 | {control['balances']['48']:,} | {x['balances']['48']:,} |")
returning = next(x for x in audit['growth'] if x['returning'])
lines += ['', f"별도의 기존 성장/F19 완료·270만 골드 합성 복귀 경로는 확장 {clock(returning['purchases'][0]['time'])}, 개선1 {clock(returning['purchases'][1]['time'])}, 개선2 {clock(returning['complete'])}에 실제 구매했다. 이것을 실제 사용자의 현재 저장이나 신규 성장 시간으로 취급하지 않는다.", '',
    '## 완료 범위와 남은 밸런스 검수', '',
    f"회복 기본 물약/고급 제조 복귀/실제 납품 재개/등급 상승/확장 해금/실제 유료 개선과 UI·저장 검증은 완료했다. 현재 초기 비용300만→150만→300만에서 신규6경로의 개선2 완료는 **{clock(min(x['complete'] for x in fresh))}~{clock(max(x['complete'] for x in fresh))}**다. 원래36~48시간 완료 목표보다 빠르므로 비용·진행 속도를 최종 균형으로 채택했다고 표시하지 않는다. 가격이나 해금 조건을 임의 조정하지 않았으며 기획 소유 명세/메인 F20 최종 검수 표시는 변경하지 않았다.", '',
    f"완료된 구매 사이 가장 긴 실제 무구매 간격은 신규 경로별 {clock(min(x['max_gap'] for x in fresh))}~{clock(max(x['max_gap'] for x in fresh))}이다. 큰 기능 대기1~3시간 방향도 아직 충족하지 못했다. 또한 위48시간 잔고 비교는 총750만 투자 비용을 실제 반영한 결과이므로, 제작선의 시간당 수입 개선만으로 단기 투자 회수가 끝났다고 판단하지 않는다.", '',
    '## 최신 재현·근거', '',
    '- `.verification/f20-recovery-20261020/model/`: 이번 승인 모델과 원본 SHA256. 이전 .verification/f20-20261020의 모든 원자료는 보존했다.',
    '- `tools/verify_f20_recovery.gd`, `verify_f20_recovery_chunks.gd`, `verify_f20_unpurchased.gd`: 승인 정책·진행 중 배치·무료 정책과의 차등 회귀.',
    '- `tools/measure_f20_recovery.gd`: 별도 동결 모델의 실제24효과/13성장·대조·복귀 경로. 기존 결과 파일을 덮지 않는다.',
    '- `tools/analyze_f20_recovery.py`: 레시피/병수/현금/재료 보존·실제 구매·회차/전후 상태·소스 해시 독립 감사. `audit.json`이 최종 근거다.',
    '- `checks/`: 최종 기능 로그/JSON. `ui/`: 실제 Control/TextServer 파일 미리보기6종. 새 정책에서 체력 물약 실제 제조/시간/게이지가 표시되는 것을 확인했다.',
    '- `tools/update_f20_recovery_result.py`: 최종 audit 완료 이후에만 이 최신 기록을 갱신한다.', '',
    '검증은 프로젝트 내부 격리 AppData와 합성 상태의 headless 진행만 사용했다. 정상 게임·에디터 실행, 실제 플레이어 저장 접근, 실행 중 게임 조작, Computer Use는 하지 않았다. 새 동작은 게임이 다음에 소스를 읽을 때 적용된다.', '', end, '']
target.write_text(title+'\n'.join(lines).rstrip()+'\n\n'+history.lstrip('\n'),encoding='utf-8')
print('Updated approved recovery completion evidence; pre-approval history retained')
