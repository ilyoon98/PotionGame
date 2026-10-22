"""Analyze only frozen, workspace-only F19 price experiments. No player data."""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT / ".verification" / "f19-supplement-20261019" / "pricing"
VARIANTS = {"current210": [150000, 300000, 600000], "candidate180": [150000, 300000, 450000]}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def close(a, b) -> bool:
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(a - b) < 1e-4
    if isinstance(a, dict) and isinstance(b, dict):
        return set(a) == set(b) and all(close(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(close(x, y) for x, y in zip(a, b))
    return a == b


def normalized(source: str, variant: str) -> str:
    prefix = f".verification/f19-supplement-20261019/pricing/{variant}/model/"
    return source.replace(prefix, "").replace(
        f"res://.verification/f19-supplement-20261019/pricing/{variant}",
        "res://.verification/late-investment-f19-20261019")


def manifest() -> dict:
    original = json.loads((ROOT / "frozen" / "source-hashes.json").read_text(encoding="utf-8-sig"))
    result = {"scope": "Private model copies only. Production prices are not changed. Path/output rewrites are normalized before comparing model logic.", "original_sha256": original, "variants": {}, "normalized_logic_differences": {}}
    for path, sha in original.items():
        assert digest(ROOT / "frozen" / path) == sha
    for variant in VARIANTS:
        hashes = {}
        for path in original:
            model = ROOT / variant / "model" / path
            hashes[path] = digest(model)
            text = model.read_text(encoding="utf-8")
            frozen = (ROOT / "frozen" / path).read_text(encoding="utf-8")
            restored = normalized(text, variant)
            if variant == "candidate180" and path == "scripts/shop_late_investments.gd":
                assert restored.count("const COSTS := [150000, 300000, 450000]") == 1
                assert restored.replace("const COSTS := [150000, 300000, 450000]", "const COSTS := [150000, 300000, 600000]") == frozen
                result["normalized_logic_differences"][path] = list(difflib.unified_diff(frozen.splitlines(), restored.splitlines(), fromfile="frozen", tofile="candidate180", lineterm=""))
            else:
                assert restored == frozen, f"Unexpected model/harness change: {variant}/{path}"
        result["variants"][variant] = {"stage_prices": VARIANTS[variant], "six_stage_total": 2 * sum(VARIANTS[variant]), "unapplied_candidate": variant == "candidate180", "private_sha256": hashes}
    target = ROOT / "model-manifest.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


def analyze() -> None:
    rules = manifest()
    rows = []
    checks = 0
    baseline_checks = 0
    reports = {}
    for variant, costs in VARIANTS.items():
        files = sorted((ROOT / variant / "growth" / "comparison").glob("*.json"))
        assert len(files) == 6, f"Expected six fresh zero-gold routes for {variant}"
        for file in files:
            report = json.loads(file.read_text(encoding="utf-8"))
            assert report["passed"] and not report["failures"] and report["all_late_completed"]
            assert report["training_target"] == 0 and report["final"]["training_actual"] == 0
            for path, sha in report["metadata"]["source_sha256"].items():
                assert digest(PROJECT / path) == sha, "Frozen loaded model and recorded source hash must match"
                checks += 1
            final = report["final"]
            assert final["gold"] == final["sales_income"] + final["contract_income"] - final["material_cost"] - final["expedition_cost"] - final["manual_spent"]
            assert sum(p["cost"] for p in report["purchases"]) == final["manual_spent"]
            purchases = [p.copy() for p in report["purchases"] if p["action"] == "late_purchase"]
            assert len(purchases) == 6 and sum(p["cost"] for p in purchases) == 2 * sum(costs)
            previous = None
            previous_by_track = {}
            for purchase in purchases:
                assert purchase["cost"] == costs[purchase["stage"] - 1]
                assert purchase["gold_before"] - purchase["gold_after"] == purchase["cost"] and purchase["gold_after"] >= 0
                purchase["gap_from_previous_late_purchase_seconds"] = None if previous is None else purchase["time"] - previous
                purchase["gap_from_previous_same_track_seconds"] = None if purchase["track"] not in previous_by_track else purchase["time"] - previous_by_track[purchase["track"]]
                previous = purchase["time"]
                previous_by_track[purchase["track"]] = purchase["time"]
                checks += 2
            original_time = report["milestones"]["original_growth_complete_observed"]["time"]
            gaps = [p["gap_from_previous_late_purchase_seconds"] for p in purchases[1:]]
            row = {"variant": variant, "seed": report["seed"], "return_seconds": report["return_seconds"], "actual_training": final["training_actual"], "actual_late_price_paid": sum(p["cost"] for p in purchases), "purchases": purchases, "original_growth_complete_seconds": original_time, "first_purchase_seconds": purchases[0]["time"], "first_wait_after_original_growth_seconds": purchases[0]["time"] - original_time, "completion_seconds": report["milestones"]["all_late_complete"]["time"], "elapsed_after_original_growth_seconds": final["time"] - original_time, "elapsed_after_first_late_purchase_seconds": final["time"] - purchases[0]["time"], "maximum_gap_between_late_purchases_seconds": max(gaps), "final_gold": final["gold"], "actual_nine_hour_gold": report["milestones"]["nine_hour_actual_growth"]["gold"], "raw_checks": report["checks"], "raw_file": file.relative_to(PROJECT).as_posix()}
            rows.append(row)
            key = (variant, report["return_seconds"], report["seed"])
            reports[key] = report
            checks += 3
            if variant == "current210":
                old = PROJECT / ".verification" / "late-investment-f19-20261019" / "growth" / "supply7" / file.name
                old_report = json.loads(old.read_text(encoding="utf-8"))
                for field in ["purchases", "contract_decisions", "starting_materials", "ending_materials", "actual_reserved_consumption_including_failures", "actual_late_supplies", "purchased_materials", "other_generated_materials", "milestones", "final"]:
                    assert close(report[field], old_report[field]), f"Fresh current-price run diverged from prior completed run: {file.name} {field}"
                    baseline_checks += 1
    comparisons = []
    for return_seconds in (30, 900):
        for seed in (73129, 19337, 9973):
            current = next(r for r in rows if (r["variant"], r["return_seconds"], r["seed"]) == ("current210", return_seconds, seed))
            candidate = next(r for r in rows if (r["variant"], r["return_seconds"], r["seed"]) == ("candidate180", return_seconds, seed))
            for field in ["original_growth_complete_seconds", "first_purchase_seconds", "first_wait_after_original_growth_seconds"]:
                assert close(current[field], candidate[field]), "Third-stage-only price changes cannot affect earlier growth"
            assert close(current["purchases"][:4], candidate["purchases"][:4]), "The first four purchases must be identical"
            comparisons.append({"return_seconds": return_seconds, "seed": seed, "current_completion_seconds": current["completion_seconds"], "candidate_completion_seconds": candidate["completion_seconds"], "completion_earlier_seconds": current["completion_seconds"] - candidate["completion_seconds"], "current_maximum_late_gap_seconds": current["maximum_gap_between_late_purchases_seconds"], "candidate_maximum_late_gap_seconds": candidate["maximum_gap_between_late_purchases_seconds"], "current_final_gold": current["final_gold"], "candidate_final_gold": candidate["final_gold"]})
            checks += 4
    returning = json.loads((ROOT / "returning-comparison.json").read_text(encoding="utf-8"))
    assert returning["passed"] and not returning["failures"] and returning["checks"] == 108 and len(returning["cases"]) == 18
    logs = list(ROOT.glob("*/logs/*.log")) + [ROOT / "returning-comparison.log"]
    assert len(logs) == 13
    for log in logs:
        text = log.read_text(encoding="utf-8")
        assert "SCRIPT ERROR" not in text and not any(line.startswith(("ERROR:", "FAIL ")) for line in text.splitlines())
    purchase_groups = []
    for variant in VARIANTS:
        for return_seconds in (30, 900):
            group = [r for r in rows if (r["variant"], r["return_seconds"]) == (variant, return_seconds)]
            for index in range(6):
                purchases = [r["purchases"][index] for r in group]
                item = {"variant": variant, "return_seconds": return_seconds, "purchase_index": index + 1, "track": purchases[0]["track"], "stage": purchases[0]["stage"], "actual_price": purchases[0]["cost"]}
                for field in ("time", "gold_before", "gold_after", "gap_from_previous_late_purchase_seconds", "gap_from_previous_same_track_seconds"):
                    values = [p[field] for p in purchases if p[field] is not None]
                    item[field + "_range"] = [min(values), max(values)] if values else None
                purchase_groups.append(item)
    output = {"scope": "Unapplied third-stage450k price experiment versus current600k. Twelve fresh zero-gold growth routes only; no training3 remeasurement or new effect tuning.", "rules": rules["variants"], "rows": rows, "purchase_groups": purchase_groups, "comparisons": comparisons, "checks": checks, "fresh_current_baseline_comparison_checks": baseline_checks, "returning_checks": returning["checks"], "returning_cases": returning["cases"], "clean_log_files": len(logs), "limitations": "Fixed recipe-first purchasing and manual return-time relationship then final-payment negotiation; seeded simulation, not optimal play or human timing. Observation resolution30sec and purchases only at30sec/15min returns. Synthetic700k/775k/850k returning fixtures are not naturally reached balances. Third-stage candidate is not applied to production.", "passed": True}
    target = ROOT / "pricing-analysis.json"
    target.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    for row in comparisons:
        print(f"return={row['return_seconds']} seed={row['seed']} completion={row['current_completion_seconds']/3600:.3f}h -> {row['candidate_completion_seconds']/3600:.3f}h earlier={row['completion_earlier_seconds']/60:.1f}m maxgap={row['current_maximum_late_gap_seconds']/60:.1f} -> {row['candidate_maximum_late_gap_seconds']/60:.1f}m")
    print(f"PASS F19 pricing12 routes, {checks} independent checks, {baseline_checks} current baseline comparisons, 108 returning checks, 13 clean logs; {target}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare", action="store_true")
    args = parser.parse_args()
    if args.prepare:
        manifest()
        print("PASS frozen pricing models differ only in third-stage600000->450000")
    else:
        analyze()
