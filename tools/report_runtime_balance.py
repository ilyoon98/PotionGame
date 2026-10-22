"""Summarize the Godot economy output without re-simulating it."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
data = json.loads((root / "docs/balance/runtime-candidate-c.json").read_text(encoding="utf-8"))
lines = [
    "# 후보 C 실제 게임 적용과 측정",
    "",
    "2026-10-08 · Godot 4.6 · **판매대 적용·검사 완료, 전체 콘텐츠 확장은 미구현**",
    "",
    "현재 게임의 물약 5종·기본 약초/버섯/별잎·숲 원정 1곳을 그대로 사용했다. "
    "판매대 10단계의 비용·최종 거래 간격·지역 조건은 후보 C와 일치한다. "
    "실제로 구매 가능한 단계는 1~3이며 숲 10회 귀환을 조사 완료 1곳으로 인정한다. "
    "기존 저장의 귀환 횟수도 인정하고 별도의 보상이나 비용을 추가하지 않는다. "
    "4단계부터는 아직 없는 다음 지역 조사가 필요하므로 잠긴 상태다.",
    "",
    "관리의 가게 운영 탭에 판매대 아이콘·현재/다음 거래 간격·비용·조사 조건을 추가했다. "
    "재고 가득, 손님의 완성품 대기, 약초 부족, 별잎 부족을 짧게 설명하고 관련 항목으로 이동한다. "
    "이동으로 결제하지 않으며 최대 단계 설비의 추가 강화를 추천하지 않는다. "
    "현재 손님·거래 진행률·제조 예약 재료·고정된 성공 판정을 유지한다. "
    "저장 버전 6은 이전 버전 1~5를 읽고 판매대 단계가 없으면 0으로 시작한다.",
    "",
    "## 측정 방법",
    "",
    "독립 Python 기획 모델을 실행한 결과가 아니다. 실제 `shop_state.gd.advance()`를 "
    "1초씩 호출하고 각 이벤트 사이의 시간으로 재고량·재고 가득으로 인한 제조 정지·손님 대기를 적분했다. "
    "손님 대기는 구매 시도 실패부터 같은 손님이 실제 거래를 마칠 때까지다. "
    "30·60·120분 누적값과 각 5분 구간을 따로 저장했다. "
    "앱을 종료한 동안의 수익이나 OS 마우스 조작 검증은 포함하지 않는다.",
    "",
    "새 게임은 난수 73129·19337·9973과 3가지 구매 정책을 조합한 9회, "
    "기존 높은 솥 단계 저장의 복사본은 1회 측정했다. "
    "30초마다 또는 15분마다 한 번 직접 구매하는 상황을 대리하며, 실제 게임에는 자동 강화가 없다. "
    "매번 현재 재고가 가득 차고 판매대 구매 조건을 만족하면 판매대를 먼저 살펴보는 정책이다. "
    "나머지는 레시피/원정 또는 설비 우선 순서를 사용한다. 실제 저장은 측정에 쓰지 않고 복사본만 사용했다.",
    "",
    "## 대표 진행 기록",
    "",
    "난수 73129와 기존 저장의 누적값이다. 다른 난수와 5분 구간은 원본 JSON에 있다.",
    "",
    "| 시작/구매 정책 | 분 | 제조 성공 | 판매 | 평균 재고/한도 | 제조 정지 | 손님 대기 | 솥/화분/판매대 |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
]
names = {"recipe_first": "새 게임·레시피 우선", "equipment_first": "새 게임·설비 우선", "return_15m": "새 게임·15분 복귀"}
for run in data["runs"]:
    if not run["label"].endswith("73129") and run["label"] != "existing_save":
        continue
    name = "기존 높은 솥 저장" if run["label"] == "existing_save" else names[run["policy"]]
    for point in run["checkpoints"]:
        lines.append(
            f"| {name} | {point['minutes']:.0f} | {point['brewed']} | {point['sold']} | "
            f"{point['average_stock_percent']:.1f}% | {point['full_percent']:.1f}% | "
            f"{point['waiting_percent']:.1f}% | {point['cauldron']}/{point['garden']}/{point['sales_counter']} |"
        )
lines += ["", "## 같은 상태의 강화 1회 비교", "", "다른 구매를 10분간 하지 않고 실제 비용을 결제한 복사본과 강화 전 상태를 비교했다.", "", "| 항목 | 판매 전→후 | 제조 정지 전→후 | 손님 대기 전→후 |", "| --- | ---: | ---: | ---: |"]
for effect in data["isolated_upgrade_effects"]:
    a, b = effect["before"]["final"], effect["after"]["final"]
    label = "솥 2→3" if effect["kind"] == "cauldron" else "판매대 2→3"
    lines.append(f"| {label} | {a['sold']}→{b['sold']} | {a['full_percent']:.1f}%→{b['full_percent']:.1f}% | {a['waiting_percent']:.1f}%→{b['waiting_percent']:.1f}% |")
lines += [
    "",
    "## 2시간 후 남은 목표와 한계",
    "",
    "30초마다 투자하는 레시피/설비 우선의 6회와 기존 저장 1회는 120분에 현재 구현한 "
    "레시피·숲 조사·솥·화분·구매 가능한 판매대·여과기·판매 보조를 모두 마쳤다. "
    "**현재 소규모 게임만으로 2시간 뒤에도 성장 목표가 남는다는 조건을 만족하지 않는다.** "
    "15분 복귀의 3회는 솥 14회·화분 7회·판매대 3회·여과기·판매 보조가 남았다.",
    "",
    "기존 높은 솥 저장의 120분 평균 재고는 96.3%, 제조 정지는 55.6%, 손님 대기는 0%였다. "
    "판매대는 정지를 줄이지만 현재 도달 가능한 3단계만으로 빠른 제조를 모두 소화하지 못한다. "
    "병을 버리거나 손님을 강제로 내보내는 방식으로 이를 숨기지 않았다.",
    "",
    "| 정책 | 재고 평균 90% 이상·품절 대기 없음의 최장 연속 구간 |",
    "| --- | ---: |",
]
for policy, name in names.items():
    values = [r["longest_backlog_minutes"] for r in data["runs"] if r["policy"] == policy and r["label"] != "existing_save"]
    lines.append(f"| {name} | {min(values)}~{max(values)}분 |")
existing = next(r for r in data["runs"] if r["label"] == "existing_save")
lines += [
    f"| 기존 높은 솥 저장 | {existing['longest_backlog_minutes']}분 |",
    "",
    "30분을 넘는 적체는 후속 조정 대상으로 남긴다. 신규 물약 27종·지역 7곳과 그 생산·성장 "
    "연결이 없으므로 32종·8지역 독립 모델의 재고 42~45% 결과를 현재 게임에서 재현한 것으로 처리하지 않는다.",
    "",
    "조제 보조는 신규 레시피에만 적용하는 직원이며 기존 체력·마나·달빛·정화·민첩의 시간을 "
    "변경하지 않는다. 현재 신규 레시피와 4지역 조사 조건이 없어 고용·훈련 구현은 전체 확장 범위에 남긴다. "
    "고용 3,830 G / 조사 4곳 / 시간 ×0.95 / 품질 +0.02, 훈련 비용 "
    "1,760·3,520·7,040·14,080·28,160 G, 조사 4·5·6·7·8곳, 최종 시간 "
    "×0.94·0.93·0.92·0.82·0.72, 품질 +0.03·0.04·0.05·0.06·0.07을 연결할 때 사용한다.",
    "",
    "## 자동 검사 완료",
    "",
    "판매대 후보 데이터 일치·조건 잠금·단일 결제·거래/예약 재료/판정 보존·버전 5 이전·"
    "잘못된 데이터의 원자적 거부·프레임 간격 독립성·정확한 대기 측정 검사 통과. "
    "기존 경제·공급·성장·FIFO 검사도 통과했다. 관리 UI 연결 검사에서는 아이콘·조건 갱신·"
    "결제 없는 이동·최대 단계 안내·작은 진행 화면 전환을 확인했다. 실제 마우스 체감 확인은 사용자에게 남긴다.",
    "",
    "[측정 원본과 5분 기록](balance/runtime-candidate-c.json) · "
    "[측정 스크립트](../tools/measure_runtime_balance.gd) · "
    "[판매대 검사](../tests/test_sales_counter.gd)",
]
(root / "docs/후보-C-실제게임-적용결과.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("Runtime report written.")
