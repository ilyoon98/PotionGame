"""Summarise the F21 bed/herb-tea growth measurements (tools/measure_f21_aux.gd --root=f21-keeper-upgrades-20261021).

Compares, per seed, the regression run (--aging) with the earlier F21 aging result,
then the buy-everything (--keeper) and auto-policy (--keeper --policy=auto) runs.
"""
import json
import pathlib
import statistics
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / ".verification"
NEW = ROOT / "f21-keeper-upgrades-20261021" / "growth"
OLD = ROOT / "f21-aux-speed-20261020" / "growth"
SEEDS = [73129, 19337, 9973]
CASES = {"aging": "-aging", "keeper": "-aging-keeper", "auto": "-aging-keeper-policy-auto"}


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def net(snapshot, initial):
    keys = ["retail_revenue", "contract_paid"]
    costs = ["material_cost", "fees"]
    return sum(snapshot[k] - initial[k] for k in keys) - sum(snapshot[k] - initial[k] for k in costs)


def at(run, seconds):
    for window in run["windows_15m"]:
        if window["time"] >= seconds:
            return window
    return run["final"]


def hours(run, key):
    milestone = run["milestones"].get(key)
    return milestone["time"] / 3600 if milestone else None


def summary(run):
    initial = run["initial"]
    keeper = [p for p in run["purchases"] if p["action"] == "keeper_purchase"]
    policies = [p for p in run["purchases"] if p["action"] == "keeper_policy"]
    final = run["final"]
    return {
        "net_30m": net(at(run, 1800), initial), "net_2h": net(at(run, 7200), initial), "net_4h": net(at(run, 14400), initial),
        "net_8h": net(at(run, 28800), initial), "net_16h": net(at(run, 57600), initial),
        "contracts_h": hours(run, "contracts_unlocked"), "original_h": hours(run, "original_complete"),
        "f19_h": hours(run, "f19_complete"), "f20_h": hours(run, "f20_complete"),
        "balance_48h": run["milestones"]["balance_48h"]["gold"], "aging_revenue": final["aging_revenue"],
        "keeper_spent": sum(p["cost"] for p in keeper), "keeper_first_h": keeper[0]["time"] / 3600 if keeper else None,
        "keeper_last_h": keeper[-1]["time"] / 3600 if keeper else None,
        "policies": [(p["policy"], round(p["time"] / 3600, 2)) for p in policies],
        "sleeps": final.get("keeper_totals", {}).get("sleeps"), "faints": final.get("keeper_totals", {}).get("faints"),
        "fatigue_failed": final.get("keeper_totals", {}).get("fatigue_failed"), "failed": final.get("failed"),
        "purchases_2h": sum(1 for p in run["purchases"] if p["time"] <= 7200),
    }


def mean(values):
    values = [v for v in values if v is not None]
    return statistics.mean(values) if values else None


def main():
    report = {"regression": {}, "cases": {}, "means": {}}
    for seed in SEEDS:
        new = load(NEW / f"growth-seed{seed}-return30-aging.json")
        old = load(OLD / f"growth-seed{seed}-return30-aging.json")
        common = [k for k in old["final"] if k in new["final"]]
        same_final = all(old["final"][k] == new["final"][k] for k in common)
        same_purchases = old["purchases"] == new["purchases"]
        report["regression"][seed] = {"same_final": same_final, "same_purchases": same_purchases, "fields": len(common)}
        for case, suffix in CASES.items():
            report["cases"].setdefault(case, {})[seed] = summary(load(NEW / f"growth-seed{seed}-return30{suffix}.json"))
    for case, rows in report["cases"].items():
        keys = [k for k, v in next(iter(rows.values())).items() if isinstance(v, (int, float)) or v is None]
        report["means"][case] = {k: mean([rows[s][k] for s in SEEDS]) for k in keys}
    out = NEW.parent / "growth-summary.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    json.dump(report, sys.stdout, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
