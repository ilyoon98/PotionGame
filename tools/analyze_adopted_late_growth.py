"""Analyze adopted180 production growth without touching previous F19 evidence."""
from __future__ import annotations

import argparse
import copy
import difflib
import hashlib
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT / ".verification" / "f19-adopted180-20261019" / "growth"
BASE = PROJECT / ".verification" / "late-investment-f19-20261019"
TAG = "adopted180-20261019"
CANDIDATE = PROJECT / ".verification" / "f19-supplement-20261019" / "pricing" / "candidate180"


def close(a, b) -> bool:
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(a - b) < 1e-4
    if isinstance(a, dict) and isinstance(b, dict):
        return set(a) == set(b) and all(close(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(close(x, y) for x, y in zip(a, b))
    return a == b


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def range_of(values):
    return [min(values), max(values)]


def normalize_save(saved: dict) -> tuple[dict, dict]:
    # The new report baseline and the independently initialized wall-clock
    # caption are not production/contract state. Record each removed value.
    result = copy.deepcopy(saved)
    excluded = {"report_supply": result.pop("report_supply", "ABSENT"), "progression.report_started": result["progression"].pop("report_started")}
    return result, excluded


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--complete", action="store_true")
    args = parser.parse_args()
    files = sorted((BASE / "growth" / TAG).glob("*.json"))
    if args.complete:
        assert len(files) == 24
    rows = []
    source_hashes: dict[str, set[str]] = {}
    checks = 0
    candidate_checks = 0
    candidate_comparisons = []
    content = read(PROJECT / "data" / "content_expansion.json")
    departure_fees = {r["id"]: r["departure_cost"] for r in content["regions"]}
    for file in files:
        report = read(file)
        assert report["passed"] and not report["failures"] and report["all_late_completed"]
        for path, sha in report["metadata"]["source_sha256"].items():
            source_hashes.setdefault(path, set()).add(sha)
        final = report["final"]
        assert final["gold"] == final["sales_income"] + final["contract_income"] - final["material_cost"] - final["expedition_cost"] - final["manual_spent"]
        assert sum(p["cost"] for p in report["purchases"]) == final["manual_spent"]
        for window in report["windows_15m"]:
            assert window["gold"] == window["sales_income"] + window["contract_income"] - window["material_cost"] - window["expedition_cost"] - window["manual_spent"]
            checks += 1
        purchases = [p.copy() for p in report["purchases"] if p["action"] == "late_purchase"]
        assert len(purchases) == 6 and sum(p["cost"] for p in purchases) == 1_800_000
        assert {(p["track"], p["stage"]) for p in purchases} == {(track, stage) for track in ("supply_support", "contract_batch") for stage in (1, 2, 3)}
        previous = None
        per_track = {}
        for purchase in purchases:
            assert purchase["cost"] == (150000, 300000, 450000)[purchase["stage"] - 1]
            assert purchase["gold_before"] - purchase["gold_after"] == purchase["cost"] and purchase["gold_after"] >= 0
            purchase["gap_from_previous_purchase_seconds"] = None if previous is None else purchase["time"] - previous
            purchase["gap_from_previous_same_track_seconds"] = None if purchase["track"] not in per_track else purchase["time"] - per_track[purchase["track"]]
            previous = purchase["time"]
            per_track[purchase["track"]] = purchase["time"]
            checks += 2
        for purchase in report["purchases"]:
            extra = purchase["gold_before"] - purchase["gold_after"] - purchase["cost"]
            assert purchase["gold_before"] >= purchase["cost"] > 0 and purchase["gold_after"] >= 0
            kind = purchase.get("kind", "")
            if purchase["action"] == "original_purchase" and (kind == "expedition" or kind.startswith("region:")):
                region = "forest_edge" if kind == "expedition" else kind.removeprefix("region:")
                assert extra in (0, departure_fees[region])
            else:
                assert extra == 0
            checks += 2
        for material, start in report["starting_materials"].items():
            assert start + report["actual_late_supplies"].get(material, 0) + report["purchased_materials"].get(material, 0) + report["other_generated_materials"].get(material, 0) - report["actual_reserved_consumption_including_failures"].get(material, 0) == report["ending_materials"][material]
            assert report["other_generated_materials"][material] >= 0
            checks += 2
        training_cost = sum(p["cost"] for p in report["purchases"] if p["action"] == "training")
        assert training_cost == (0, 8000, 28000, 78000)[final["training_actual"]]
        assert final["training_actual"] <= report["training_target"]
        old = read(BASE / "growth" / "supply7" / file.name)
        assert close([p for p in old["purchases"] if p["action"] == "late_purchase"][:4], [p for p in report["purchases"] if p["action"] == "late_purchase"][:4])
        original = report["milestones"]["original_growth_complete_observed"]["time"]
        completion = report["milestones"]["all_late_complete"]["time"]
        row = {"seed": report["seed"], "return_seconds": report["return_seconds"], "training_target": report["training_target"], "actual_training": final["training_actual"], "training_cost": training_cost, "actual_late_price_paid": sum(p["cost"] for p in purchases), "contract_unlock_seconds": report["milestones"]["contracts_unlocked_observed"]["time"], "original_growth_complete_seconds": original, "first_purchase_seconds": purchases[0]["time"], "first_wait_after_original_growth_seconds": purchases[0]["time"] - original, "completion_seconds": completion, "after_original_growth_seconds": completion - original, "after_first_purchase_seconds": completion - purchases[0]["time"], "maximum_gap_between_late_purchases_seconds": max(p["gap_from_previous_purchase_seconds"] for p in purchases[1:]), "maximum_gap_between_same_track_purchases_seconds": max(p["gap_from_previous_same_track_seconds"] for p in purchases if p["gap_from_previous_same_track_seconds"] is not None), "final_gold": final["gold"], "actual_nine_hour_gold": report["milestones"]["nine_hour_actual_growth"]["gold"], "completion_earlier_than210_seconds": old["milestones"]["all_late_complete"]["time"] - completion, "purchases": purchases, "raw_checks": report["checks"], "raw_file": file.relative_to(PROJECT).as_posix()}
        rows.append(row)
        checks += 8
        if report["training_target"] == 0:
            candidate = read(CANDIDATE / "growth" / "comparison" / file.name)
            compared = ["actual_seconds", "purchases", "contract_decisions", "starting_materials", "ending_materials", "actual_reserved_consumption_including_failures", "actual_late_supplies", "purchased_materials", "other_generated_materials", "milestones", "windows_15m", "final", "all_late_completed"]
            for field in compared:
                assert close(report[field], candidate[field]), f"Production/candidate difference {file.name}: {field}"
                candidate_checks += 1
            state_name = f"{report['seed']}-return{report['return_seconds']}-training0-9h.json"
            adopted_save = read(BASE / "growth-fixtures" / TAG / state_name)
            candidate_save = read(CANDIDATE / "growth-fixtures" / "comparison" / state_name)
            current_normalized, current_excluded = normalize_save(adopted_save)
            prior_normalized, prior_excluded = normalize_save(candidate_save)
            assert close(current_normalized, prior_normalized), "Nine-hour entire production/round/RNG state differs after explicit reporting-only normalization"
            assert close(adopted_save["contracts"], candidate_save["contracts"]), "Whole actual contract round history, batch, cursor and RNG must reproduce"
            candidate_checks += 2
            candidate_comparisons.append({"seed": report["seed"], "return_seconds": report["return_seconds"], "compared_fields": compared, "nine_hour_entire_economic_save_match": True, "nine_hour_entire_contract_round_and_rng_match": True, "reporting_only_fields_excluded": {"production": current_excluded, "frozen_candidate": prior_excluded}})
    expected = {(seed, ret, training) for seed in (73129, 19337, 9973) for ret in (30, 900) for training in range(4)}
    if args.complete:
        assert {(r["seed"], r["return_seconds"], r["training_target"]) for r in rows} == expected and len(candidate_comparisons) == 6
    for path, hashes in source_hashes.items():
        assert len(hashes) == 1 and hashlib.sha256((PROJECT / path).read_bytes()).hexdigest() in hashes
    groups = []
    for ret in (30, 900):
        for target in range(4):
            group = [r for r in rows if (r["return_seconds"], r["training_target"]) == (ret, target)]
            if group:
                item = {"return_seconds": ret, "training_target": target, "count": len(group), "actual_training": sorted({r["actual_training"] for r in group}), "training_cost": sorted({r["training_cost"] for r in group})}
                for field in ("original_growth_complete_seconds", "first_purchase_seconds", "first_wait_after_original_growth_seconds", "completion_seconds", "after_original_growth_seconds", "maximum_gap_between_late_purchases_seconds", "maximum_gap_between_same_track_purchases_seconds", "actual_nine_hour_gold", "final_gold", "completion_earlier_than210_seconds"):
                    item[field + "_range"] = range_of([r[field] for r in group])
                groups.append(item)
    purchase_groups = []
    for ret in (30, 900):
        for target in range(4):
            group = [r for r in rows if (r["return_seconds"], r["training_target"]) == (ret, target)]
            if not group:
                continue
            for index in range(6):
                purchases = [r["purchases"][index] for r in group]
                item = {"return_seconds": ret, "training_target": target, "count": len(group), "purchase_index": index + 1, "track": purchases[0]["track"], "stage": purchases[0]["stage"], "actual_cost": purchases[0]["cost"]}
                for field in ("time", "gold_before", "gold_after", "gap_from_previous_purchase_seconds", "gap_from_previous_same_track_seconds"):
                    values = [p[field] for p in purchases if p[field] is not None]
                    item[field + "_range"] = range_of(values) if values else None
                purchase_groups.append(item)
    before = read(ROOT.parent / "before" / "source-hashes.json")
    production_changes = [path for path, sha in before.items() if hashlib.sha256((PROJECT / path).read_bytes()).hexdigest() != sha]
    assert production_changes == ["scripts/shop_late_investments.gd"]
    old_late = (ROOT.parent / "before" / "shop_late_investments.gd").read_text(encoding="utf-8-sig")
    new_late = (PROJECT / "scripts" / "shop_late_investments.gd").read_text(encoding="utf-8-sig")
    assert old_late.replace("const COSTS := [150000, 300000, 600000]", "const COSTS := [150000, 300000, 450000]") == new_late
    logs = list((ROOT / "logs").glob("*.log"))
    if args.complete:
        assert len(logs) == 24
    for log in logs:
        text = log.read_text(encoding="utf-8")
        assert "SCRIPT ERROR" not in text and not any(line.startswith(("ERROR:", "FAIL ")) for line in text.splitlines())
    output = {"scope": "Adopted180 actual production references; fresh zero-gold24-route growth only, not a rerun of180 effect conditions", "tag": TAG, "production_stage_prices": [150000, 300000, 450000], "six_stage_cost": 1800000, "source_sha256": {path: next(iter(hashes)) for path, hashes in source_hashes.items()}, "production_changes_since_adoption_snapshot": production_changes, "production_price_diff": list(difflib.unified_diff(old_late.splitlines(), new_late.splitlines(), fromfile="before210", tofile="adopted180", lineterm="")), "routes": len(rows), "all_routes_completed": all(r["completion_seconds"] is not None for r in rows), "independent_checks": checks, "candidate_reproduction_checks": candidate_checks, "candidate_reproduction": candidate_comparisons, "raw_headless_checks": sum(r["raw_checks"] for r in rows), "clean_logs": len(logs), "rows": rows, "groups": groups, "purchase_groups": purchase_groups, "limitations": "Fixed recipe-first purchases and manual return-time relationship then final-payment negotiations, not optimized or human play. All new investments cost real operating gold; no million-gold completed-shop fixture. Observation resolution30sec. Materials other_generated is the conservation residual from actual cultivation/expedition deposits; no unmeasured offline income is inferred.", "passed": True}
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / "analysis.json").write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    for group in groups:
        first, last = group["completion_seconds_range"]
        print(f"return={group['return_seconds']} training={group['training_target']} actual={group['actual_training']} cost={group['training_cost']} completion={first/3600:.3f}..{last/3600:.3f}h maxgap={group['maximum_gap_between_late_purchases_seconds_range']}")
    print(f"PASS adopted180 {len(rows)} routes, {checks} independent checks, {candidate_checks} candidate reproduction checks, {len(logs)} clean logs")


if __name__ == "__main__":
    main()
