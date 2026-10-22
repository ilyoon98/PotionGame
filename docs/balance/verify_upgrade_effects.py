"""Paired, isolated planning experiments; no runtime or player saves."""
from pathlib import Path
from copy import deepcopy
import json
import simulate
from simulate import Model

HERE=Path(__file__).resolve().parent

def measure(m,end):
    m.next_decision=float('inf');m.pressure.clear();m.window_pressure.clear();m.pressure_windows=[];m.wait_durations=[]
    old_sales=m.sale_count;old_money=m.sales;start=m.t
    m.run(end)
    total=m.pressure['seconds']
    return dict(start_minute=start/60,end_minute=end,sold=m.sale_count-old_sales,gross=m.sales-old_money,stock_end=len(m.stock),full_pct=100*m.pressure['full_seconds']/total,waiting_pct=100*m.pressure['waiting_seconds']/total,inventory_pct=100*m.pressure['inventory_ratio_seconds']/total)

def main():
    simulate.DT=.05
    d=json.loads((HERE/'content-data-v1.json').read_text(encoding='utf-8'));cases=[]
    for seed in [73129,19337,9973]:
        warm=Model(d,'expedition_first',seed);warm.initial_seed=seed
        for minute,track,base_stage,new_stage in [(90,'cauldron',None,None),(150,'sales_counter',5,6),(300,'brewing_assistant',4,5)]:
            warm.run(minute)
            stage=warm.stages[track] if base_stage is None else base_stage
            target=stage+1 if new_stage is None else new_stage
            u=warm.upgrade_map[(track,target)]
            assert warm.completed()>=u['completed_regions']
            if u['kind']=='training':assert track in warm.staff
            before=deepcopy(warm);after=deepcopy(warm)
            before.stages[track]=stage;after.stages[track]=target
            cases.append(dict(seed=seed,track=track,base_stage=stage,new_stage=target,recipes=len(warm.owned),regions_completed=warm.completed(),stock_start=len(warm.stock),stock_capacity=warm.effect('potion_cabinet','total_potion_capacity',12),before=measure(before,minute+10),after=measure(after,minute+10)))
    out=dict(revision=d['revision'],dt_seconds=.05,method='Same warmed state; compare two specified upgrade stages over 10 minutes, freeze all other purchases. Stage substitution isolates effects, not a paid live-game test. RNG initial state is shared; later event schedules can diverge.',cases=cases)
    (HERE/'upgrade-effect-results.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for c in cases:print(json.dumps(c,ensure_ascii=False),flush=True)

if __name__=='__main__':main()
