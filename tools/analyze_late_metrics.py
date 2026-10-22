"""Analyze workspace-only F19 measurements; never reads player data."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import mean


ROOT = Path(__file__).resolve().parents[1] / ".verification" / "late-investment-f19-20261019"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", default="double-supply")
    parser.add_argument("--complete", action="store_true", help="Require all180 effects and24 real-cost growth routes")
    args = parser.parse_args()
    assert args.tag and all(c.isalnum() or c in "_-" for c in args.tag)
    rows = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "effects" / args.tag).glob("*.json"))]
    receipt_checks = 0
    source_hashes: dict[str, set[str]] = {}
    for row in rows:
        assert row["passed"] and not row["failures"], (row["terms"], row["scenario"], row["seed"], row["combo"])
        assert isinstance(row["metadata"]["supply_view_at_start"], dict), "Prior typed-view failure is not clean evidence"
        for path, digest in row["metadata"]["source_sha256"].items():
            source_hashes.setdefault(path, set()).add(digest)
        assert row["actual_supplied_by_material"] == row["ending_late_state"]["totals"], "Actual support events equal cumulative support accounting"
        receipt_checks += 1
        cycle = row["metadata"]["supply_view_at_start"]
        max_quantity = row["metadata"]["supply_investment_view"]["current_quantity"]
        stamps = []
        for arrival in row["actual_supply_arrivals"]:
            timestamp = arrival["time_upper_bound"]
            assert timestamp > 0 and timestamp % cycle["duration"] == 0, "No early, offline, or off-boundary support grant"
            assert 0 < arrival["quantity"] <= arrival["reserved_quantity"]
            expected = cycle["reserved_quantity"] if timestamp == cycle["duration"] else max_quantity
            assert arrival["reserved_quantity"] == expected, "An immediate multi-stage purchase preserves the first-cycle reservation"
            stamps.append(timestamp)
            receipt_checks += 3
        assert len(set(stamps)) == len(stamps) and len(stamps) <= row["seconds"] / cycle["duration"], "One material at most per due period, no debt burst"
        receipt_checks += 1
        assert sum(row["contract_quantity_distribution"].values()) == row["batch_starts"]["contract"]
        assert sum(int(q) * n for q, n in row["contract_quantity_distribution"].items()) == row["reserved_bottles"]["contract"]
        receipt_checks += 2
    by_key = {(r["terms"], r["scenario"], r["seed"], r["combo"]): r for r in rows}
    comparisons = []
    monotonicity = []
    for (terms, scenario, seed, combo), row in by_key.items():
        control = by_key.get((terms, scenario, seed, "none"))
        if control is None:
            continue
        comparisons.append({
            "terms": terms, "scenario": scenario, "seed": seed, "combo": combo,
            "realized_cash_net": row["realized_net"], "exact_unpaid": row["exact_unpaid_contract_value"],
            "cash_plus_exact_unpaid_net": row["cash_plus_exact_unpaid_net"],
            "cash_delta_vs_none": row["realized_net"] - control["realized_net"],
            "value_delta_vs_none_percent": 100 * (row["cash_plus_exact_unpaid_net"] / control["cash_plus_exact_unpaid_net"] - 1),
            "supply_per_hour": sum(row["actual_supplied_by_material"].values()) * 3600 / row["seconds"],
            "average_contract_bottles": row["average_contract_bottles_per_started_batch"],
            "contract_shipped": row["actual_contract_shipped"], "customer_wait_seconds": row["waits"]["customer"],
        })
    for terms in ("standard", "final"):
        for scenario in ("normal", "scarce_upper", "inventory_full"):
            for seed in (73129, 19337, 9973):
                for track in ("support", "bulk", "both"):
                    for stage in range(1, 4):
                        old_combo = "none" if stage == 1 else f"{track}{stage - 1}"
                        old = by_key.get((terms, scenario, seed, old_combo))
                        new = by_key.get((terms, scenario, seed, f"{track}{stage}"))
                        if old and new:
                            monotonicity.append({"terms": terms, "scenario": scenario, "seed": seed, "track": track, "stage": stage,
                                                 "previous_cash": old["realized_net"], "current_cash": new["realized_net"],
                                                 "previous_exact_unpaid": old["exact_unpaid_contract_value"], "current_exact_unpaid": new["exact_unpaid_contract_value"],
                                                 "cash_delta": new["realized_net"] - old["realized_net"],
                                                 "cash_plus_unpaid_delta": new["cash_plus_exact_unpaid_net"] - old["cash_plus_exact_unpaid_net"],
                                                 "value_percent_vs_previous": 100 * (new["cash_plus_exact_unpaid_net"] / old["cash_plus_exact_unpaid_net"] - 1)})
    stage_groups = []
    for terms in ("standard", "final"):
        for scenario in ("normal", "scarce_upper", "inventory_full"):
            for track in ("support", "bulk", "both"):
                for stage in range(1, 4):
                    group = [r for r in monotonicity if (r["terms"], r["scenario"], r["track"], r["stage"]) == (terms, scenario, track, stage)]
                    if group:
                        stage_groups.append({"terms": terms, "scenario": scenario, "track": track, "stage": stage, "count": len(group),
                                             "mean_cash_delta": mean(r["cash_delta"] for r in group),
                                             "mean_value_delta": mean(r["cash_plus_unpaid_delta"] for r in group),
                                             "mean_value_percent": mean(r["value_percent_vs_previous"] for r in group),
                                             "minimum_value_percent": min(r["value_percent_vs_previous"] for r in group)})
    groups = []
    targets = []
    for terms in ("standard", "final"):
        for scenario in ("normal", "scarce_upper", "inventory_full"):
            for combo in ("none", "support1", "support2", "support3", "bulk1", "bulk2", "bulk3", "both1", "both2", "both3"):
                group = [r for r in comparisons if (r["terms"], r["scenario"], r["combo"]) == (terms, scenario, combo)]
                if not group:
                    continue
                groups.append({"terms": terms, "scenario": scenario, "combo": combo, "count": len(group), **{
                    name: mean(r[name] for r in group) for name in ("realized_cash_net", "exact_unpaid", "cash_plus_exact_unpaid_net", "cash_delta_vs_none", "value_delta_vs_none_percent", "supply_per_hour", "average_contract_bottles", "contract_shipped", "customer_wait_seconds")
                }})
                if scenario == "normal" and combo in ("both1", "both3"):
                    required = 10 if combo == "both1" else 25
                    targets.append({"terms": terms, "combo": combo, "count": len(group), "required_percent": required,
                                    "mean_percent": mean(r["value_delta_vs_none_percent"] for r in group),
                                    "minimum_percent": min(r["value_delta_vs_none_percent"] for r in group),
                                    "mean_target_pass": len(group) == 3 and mean(r["value_delta_vs_none_percent"] for r in group) >= required,
                                    "all_three_seeds_pass": len(group) == 3 and all(r["value_delta_vs_none_percent"] >= required for r in group)})
    growth_rows = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "growth" / args.tag).glob("*.json"))]
    growth = []
    growth_ledger_checks = 0
    content = json.loads((ROOT.parents[1] / "data" / "content_expansion.json").read_text(encoding="utf-8"))
    departure_costs = {region["id"]: region["departure_cost"] for region in content["regions"]}
    immediate_departure_fees = []
    for row in growth_rows:
        assert row["passed"] and not row["failures"]
        for path, digest in row["metadata"]["source_sha256"].items():
            source_hashes.setdefault(path, set()).add(digest)
        final = row["final"]
        assert final["gold"] == final["sales_income"] + final["contract_income"] - final["material_cost"] - final["expedition_cost"] - final["manual_spent"]
        assert sum(p["cost"] for p in row["purchases"]) == final["manual_spent"]
        growth_ledger_checks += 2
        for purchase in row["purchases"]:
            assert purchase["gold_before"] >= purchase["cost"] > 0 and purchase["gold_after"] >= 0
            extra = purchase["gold_before"] - purchase["gold_after"] - purchase["cost"]
            if purchase["action"] == "original_purchase" and (purchase["kind"] == "expedition" or purchase["kind"].startswith("region:")):
                region = "forest_edge" if purchase["kind"] == "expedition" else purchase["kind"].removeprefix("region:")
                assert extra in (0, departure_costs[region]), "Region unlock may immediately pay its existing departure fee, separately from its investment price"
                if extra:
                    immediate_departure_fees.append({"seed": row["seed"], "return_seconds": row["return_seconds"], "training_target": row["training_target"], "time": purchase["time"], "region": region, "investment_price": purchase["cost"], "departure_fee": extra})
            else:
                assert extra == 0, "Training and all six late investments deduct exactly their actual price"
            growth_ledger_checks += 2
        if row["all_late_completed"]:
            late_purchases = [p for p in row["purchases"] if p["action"] == "late_purchase"]
            assert len(late_purchases) == 6 and {(p["track"], p["stage"]) for p in late_purchases} == {
                (track, stage) for track in ("supply_support", "contract_batch") for stage in (1, 2, 3)}
            assert all(p["cost"] == (150_000, 300_000, 600_000)[p["stage"] - 1] for p in late_purchases)
            growth_ledger_checks += 2
        growth.append({"seed": row["seed"], "return_seconds": row["return_seconds"], "training_target": row["training_target"],
                       "actual_seconds": row["actual_seconds"], "all_late_completed": row["all_late_completed"],
                       "completion_time": row["milestones"].get("all_late_complete", {}).get("time"),
                       "nine_hour_gold": row["milestones"].get("nine_hour_actual_growth", {}).get("gold"),
                       "original_growth_time": row["milestones"].get("original_growth_complete_observed", {}).get("time"),
                       "actual_training": row["final"]["training_actual"], "final_gold": row["final"]["gold"],
                       "contract_unlock_time": row["milestones"].get("contracts_unlocked_observed", {}).get("time"),
                       "first_late_purchase": next((p for p in row["purchases"] if p["action"] == "late_purchase"), None),
                       "actual_late_cost_paid": sum(p["cost"] for p in row["purchases"] if p["action"] == "late_purchase"),
                       "training_cost_paid": sum(p["cost"] for p in row["purchases"] if p["action"] == "training")})
    growth_groups = []
    for return_seconds in (30, 900):
        for target_level in range(4):
            group = [r for r in growth if (r["return_seconds"], r["training_target"]) == (return_seconds, target_level)]
            if group:
                growth_groups.append({"return_seconds": return_seconds, "training_target": target_level, "count": len(group),
                                      "actual_training_levels": sorted({r["actual_training"] for r in group}),
                                      "actual_training_costs": sorted({r["training_cost_paid"] for r in group}),
                                      "actual_late_costs": sorted({r["actual_late_cost_paid"] for r in group}),
                                      "first_late_purchase_seconds_range": [min(r["first_late_purchase"]["time"] for r in group), max(r["first_late_purchase"]["time"] for r in group)],
                                      "first_late_purchase_gold_before_range": [min(r["first_late_purchase"]["gold_before"] for r in group), max(r["first_late_purchase"]["gold_before"] for r in group)],
                                      "first_late_purchase_gold_after_range": [min(r["first_late_purchase"]["gold_after"] for r in group), max(r["first_late_purchase"]["gold_after"] for r in group)],
                                      "completion_seconds_range": [min(r["completion_time"] for r in group), max(r["completion_time"] for r in group)],
                                      "final_gold_range": [min(r["final_gold"] for r in group), max(r["final_gold"] for r in group)],
                                      "actual_nine_hour_gold_range": [min(r["nine_hour_gold"] for r in group), max(r["nine_hour_gold"] for r in group)]})
    assert all(len(hashes) == 1 for hashes in source_hashes.values()), "Use one frozen source revision per measurement tag"
    if args.complete:
        expected_effects = {(terms, scenario, seed, combo)
                            for terms in ("standard", "final")
                            for scenario in ("normal", "scarce_upper", "inventory_full")
                            for seed in (73129, 19337, 9973)
                            for combo in ("none", "support1", "support2", "support3", "bulk1", "bulk2", "bulk3", "both1", "both2", "both3")}
        assert set(by_key) == expected_effects and len(rows) == 180
        assert {(r["seed"], r["return_seconds"], r["training_target"]) for r in growth} == {
            (seed, return_seconds, target) for seed in (73129, 19337, 9973) for return_seconds in (30, 900) for target in range(4)}
        assert len(growth) == 24 and all(r["all_late_completed"] and r["actual_late_cost_paid"] == 2_100_000 for r in growth)
        assert len(targets) == 4 and all(t["mean_target_pass"] for t in targets)
    output = {"tag": args.tag, "source_sha256": {path: next(iter(hashes)) for path, hashes in source_hashes.items()}, "method": "Completed-store effects use synthetic prepaid stages and one million starting gold, not a reached growth balance. Operating cash net excludes the setup cost. Exact unpaid contract value is shown separately and is not paid cash. Only separate zero-gold growth and9h returning fixtures substantiate real purchase affordability. No ROI or guaranteed human play time is inferred.",
              "effect_runs": len(rows), "expected_full_effect_runs": 180, "independent_receipt_and_batch_accounting_checks": receipt_checks, "independent_growth_purchase_ledger_checks": growth_ledger_checks, "existing_region_unlock_immediate_departure_fees": immediate_departure_fees, "comparisons": comparisons, "groups": groups,
              "targets": targets, "target_basis": "Three-seed mean per root's confirmed interpretation; individual minima remain visible and are not promised", "all_targets_pass": len(targets) == 4 and all(t["mean_target_pass"] for t in targets),
              "stage_monotonicity": monotonicity, "stage_group_trends": stage_groups, "cash_stage_decreases": [r for r in monotonicity if r["cash_delta"] < 0],
              "value_stage_decreases": [r for r in monotonicity if r["cash_plus_unpaid_delta"] < 0], "fresh_growth_runs": growth, "growth_groups": growth_groups}
    target = ROOT / f"analysis-{args.tag}.json"
    target.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    for group in groups:
        print(f"{group['terms']:8} {group['scenario']:15} {group['combo']:8} n={group['count']} cash={group['realized_cash_net']:.1f} wip={group['exact_unpaid']:.1f} valueDelta={group['value_delta_vs_none_percent']:+.3f}% supply/h={group['supply_per_hour']:.1f} avgBatch={group['average_contract_bottles']:.3f}")
    print("TARGETS", json.dumps(targets, ensure_ascii=False))
    print(f"ANALYSIS {len(rows)} effect runs, {len(growth)} zero-gold growth runs; {target}")


if __name__ == "__main__":
    main()
