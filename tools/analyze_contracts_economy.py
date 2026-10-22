"""Read synthetic F18 evidence and add exact unrounded WIP comparisons.

Only reads the dedicated workspace evidence directory; never opens a player save.
Original measurement JSON/logs remain untouched.
"""
from __future__ import annotations

import json
from pathlib import Path
from statistics import mean


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / ".verification" / "contracts-f18-20261015"


def multiplier(terms: dict, rules: dict) -> float:
    matrix = rules.get("multipliers", {})
    if str(int(terms["grade"])) in matrix:
        return matrix[str(int(terms["grade"]))][terms["option"]]
    # Original immutable measurements predate embedded rule metadata.
    return 1.15 + 0.10 * (int(terms["grade"]) - 1) + (0.20 if terms["option"] == "payment" else 0)


def analyze(path: Path) -> dict:
    evidence = json.loads(path.read_text(encoding="utf-8"))
    assert evidence["passed"] and not evidence["failures"], path
    controls = {(row["scenario"], row["seed"]): row for row in evidence["runs"] if row["policy"] == "none"}
    records = []
    for row in evidence["runs"]:
        control = controls[row["scenario"], row["seed"]]
        parts = []
        for partner, data in row["final_contracts"]["partners"].items():
            active = data["round"]
            parts.append({
                "partner": partner,
                "achieved_grade": 1 + sum(data["points"] >= point for point in (60, 240, 600)),
                "points": data["points"],
                "round_id": active.get("id", ""),
                "round_grade": active.get("terms", {}).get("grade", 0),
                "round_option": active.get("terms", {}).get("option", ""),
                "base_total": active.get("base_total", 0),
                "wip_exact": active.get("base_total", 0) * multiplier(active["terms"], evidence.get("actual_rules", {})) if active else 0.0,
            })
        wip = sum(part["wip_exact"] for part in parts)
        accrued = row["net_income"] + wip
        starts = row["batch_starts_including_failures"]
        records.append({
            "scenario": row["scenario"], "seed": row["seed"], "policy": row["policy"],
            "realized_net": row["net_income"], "unpaid_contract_value_exact": wip,
            "net_plus_unpaid_contract_value": accrued,
            "delta_realized_vs_no_contract": row["net_income"] - control["net_income"],
            "delta_with_unpaid_vs_no_contract": accrued - control["net_income"],
            "delta_percent_with_unpaid_vs_no_contract": 100 * (accrued / control["net_income"] - 1),
            "contract_start_share": starts["contract"] / max(1, starts["ordinary"] + starts["contract"]),
            "retail_income": row["retail_income"], "contract_income": row["contract_income"],
            "contract_shipped": row["contract_shipped"], "completed_rounds": row["rounds_completed"],
            "first_paid_round_time_upper_bound": min((item["time_upper_bound"] for item in row["round_completions"]), default=None),
            "customer_wait_seconds": row["customer_wait_seconds"],
            "final_partner_values": parts,
        })
    groups = []
    for scenario in evidence["scenarios"]:
        for policy in evidence["policies"]:
            group = [r for r in records if r["scenario"] == scenario and r["policy"] == policy]
            groups.append({"scenario": scenario, "policy": policy, "count": len(group), **{
                name: mean(r[name] for r in group) for name in (
                    "realized_net", "unpaid_contract_value_exact", "net_plus_unpaid_contract_value",
                    "delta_realized_vs_no_contract", "delta_with_unpaid_vs_no_contract",
                    "delta_percent_with_unpaid_vs_no_contract", "contract_start_share",
                    "retail_income", "contract_income", "contract_shipped", "completed_rounds",
                    "customer_wait_seconds",
                )
            }})
    return {"source": path.relative_to(EVIDENCE).as_posix(), "seconds": evidence["seconds_per_run"], "mature_grade4": evidence.get("mature_grade4", False), "actual_rules": evidence.get("actual_rules", {"note": "Original immutable initial rules: basic115/125/135/145%, payment135/145/155/165%; source initial-contract-rules.gd is preserved"}), "groups": groups, "runs": records}


def main() -> None:
    paths = [EVIDENCE / "economy.json", EVIDENCE / "economy-mature.json"]
    if (EVIDENCE / "economy-mature-hour.json").exists():
        paths.append(EVIDENCE / "economy-mature-hour.json")
    if (EVIDENCE / "economy-mature-long.json").exists():
        paths.append(EVIDENCE / "economy-mature-long.json")
    for name in ("economy.json", "economy-mature-long.json"):
        if (EVIDENCE / "margin45" / name).exists():
            paths.append(EVIDENCE / "margin45" / name)
    reports = [analyze(path) for path in paths if path.exists()]
    comparisons = []
    stable_fields = (
        "starting_materials", "ending_materials", "generated_materials_excluding_purchases",
        "purchased_materials", "consumed_materials_actual_reservations", "batch_starts_including_failures",
        "retail_sales", "retail_income", "retail_sold_by_kind", "contract_shipped",
        "contract_shipped_by_kind", "contract_shipped_by_family", "rounds_completed",
        "customer_wait_seconds", "material_wait_seconds", "inventory_full_seconds",
        "empty_sale_attempts", "material_cost", "expedition_fees", "failed_batches",
    )
    for name in ("economy.json", "economy-mature-long.json"):
        old_path, new_path = EVIDENCE / name, EVIDENCE / "margin45" / name
        if not new_path.exists():
            continue
        old = json.loads(old_path.read_text(encoding="utf-8"))
        new = json.loads(new_path.read_text(encoding="utf-8"))
        indexed = {(r["scenario"], r["seed"], r["policy"]): r for r in old["runs"]}
        checked = 0
        for row in new["runs"]:
            original_row = indexed[row["scenario"], row["seed"], row["policy"]]
            for field in stable_fields:
                assert row[field] == original_row[field], (name, row["scenario"], row["seed"], row["policy"], field)
                checked += 1
            for a, b in zip(row["round_completions"], original_row["round_completions"]):
                assert {k: v for k, v in a.items() if k != "payout"} == {k: v for k, v in b.items() if k != "payout"}
                checked += 1
        comparisons.append({"original": name, "adjusted": "margin45/" + name, "matched_runs": len(new["runs"]), "exact_unchanged_production_materials_retail_checks": checked, "passed": True})
    output = {
        "method": "Exact float unpaid WIP = sum(active round.base_total * that round's grade/option multiplier), without per-partner integer rounding or actual payment. Realized cash and value-plus-unpaid are separate. This is a development comparison, not final balance approval.",
        "policy": "Entry policies accept each new current-grade condition and keep old agreements until the current round completes. Mature grade4 relationship switches to payment because no relationship improvement exists at grade4. No automatic acceptance behavior is added to production.",
        "reports": reports,
        "original_vs_adjusted_invariants": comparisons,
    }
    target = EVIDENCE / "economy-analysis.json"
    original = EVIDENCE / "economy-analysis-original66.json"
    if not original.exists() and len([r for r in reports if not r["source"].startswith("margin45/")]) == 4:
        original.write_text(json.dumps({**output, "reports": [r for r in reports if not r["source"].startswith("margin45/")]}, ensure_ascii=False, indent=2), encoding="utf-8")
    target.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    for report in reports:
        print(f"{report['source']} ({report['seconds']}s)")
        for group in report["groups"]:
            print(f"  {group['scenario']:16} {group['policy']:12} cash={group['realized_net']:9.1f} wip={group['unpaid_contract_value_exact']:8.1f} accrued={group['net_plus_unpaid_contract_value']:9.1f} delta={group['delta_percent_with_unpaid_vs_no_contract']:+.2f}%")
    print(f"PASS F18 exact unpaid-WIP analysis: {target}")


if __name__ == "__main__":
    main()
