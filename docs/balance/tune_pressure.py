"""Explore planning candidates without modifying runtime, art or the active data."""
from pathlib import Path
from copy import deepcopy
import argparse,json,time
import simulate
from simulate import Model

HERE=Path(__file__).resolve().parent

def candidate(base,name):
    d=deepcopy(base);d['revision']=name
    intervals={
        'counter_moderate':[3.,2.75,2.5,2.25,2.25,2.,2.,1.75,1.75,1.5],
        'moderate_compact':[3.,2.75,2.5,2.25,2.25,2.,2.,1.75,1.75,1.5],
        'counter_recovery':[3.,2.75,2.5,2.25,2.25,2.,2.,1.75,1.75,1.75],
        'counter_recovery_compact':[3.,2.75,2.5,2.25,2.25,2.,2.,1.75,1.75,1.75],
        'late_recovery':[3.05,2.8,2.5,2.3,2.2,2.05,1.95,1.8,1.7,1.6],
        'late_recovery_buffer':[3.05,2.8,2.5,2.3,2.2,2.05,1.95,1.8,1.7,1.6],
        'mid_recovery':[3.05,2.8,2.4,2.1,2.,1.85,1.8,1.7,1.65,1.6],
        'c_refined':[3.05,2.8,2.4,2.1,1.9,1.7,1.65,1.6,1.5,1.4],
        'c_target':[3.05,2.8,2.4,2.1,1.9,1.7,1.65,1.6,1.55,1.5],
        'counter_soft':[3.,2.75,2.5,2.5,2.5,2.25,2.25,2.,2.,1.75],
        'counter_step':[2.75,2.5,2.5,2.5,2.25,2.25,2.25,2.,2.,1.75],
        'counter_fast':[2.75,2.5,2.25,2.,1.75,1.5,1.25,1.,1.,.75],
        'counter_balanced':[2.75,2.5,2.25,2.,1.75,1.5,1.5,1.25,1.25,1.],
        'counter_compact':[2.75,2.5,2.25,2.,1.75,1.5,1.5,1.25,1.25,1.],
    }
    for u in d['upgrades']:
        if u['track']=='sales_counter':u['effect']['customer_seconds']=intervals[name][u['stage']-1]
        if name in ['counter_compact','moderate_compact','counter_recovery_compact'] and u['track']=='potion_cabinet':u['effect']['total_potion_capacity']=12+2*u['stage']
        if name.startswith('counter_recovery') and u['track']=='brewing_assistant':u['effect']['new_recipe_time_multiplier']=round(.95-.04*u['stage'],2)
        if (name.startswith('late_recovery') or name in ['mid_recovery','c_refined','c_target']) and u['track']=='brewing_assistant':u['effect']['new_recipe_time_multiplier']=[.94,.93,.92,.82,.72][u['stage']-1]
        if name=='late_recovery_buffer' and u['track']=='potion_cabinet':u['effect']['total_potion_capacity']=12+4*u['stage']
    return d

def summarize(r):
    summary={k:r[k] for k in ['policy','all_regions_min','all_recipes_min','all_investments_min']}
    summary['windows']=[]
    for start,end in [(0,30),(30,60),(60,120),(120,240),(240,480)]:
        windows=[w for w in r['pressure_windows'] if start<w['end_minute']<=end]
        total=sum(w['seconds'] for w in windows)
        if not total:continue
        summary['windows'].append(dict(start=start,end=end,**{k:round(100*sum(w[k] for w in windows)/total,2) for k in ['full_seconds','waiting_seconds','inventory_ratio_seconds']}))
    return summary

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',required=True);ap.add_argument('--minutes',type=int,default=240);ap.add_argument('--policy',default='expedition_first');ap.add_argument('--dt',type=float,default=.25);args=ap.parse_args()
    simulate.DT=args.dt
    base=json.loads((HERE/'content-data-candidate-b.json').read_text(encoding='utf-8'))
    d=candidate(base,args.candidate);m=Model(d,args.policy,73129);m.initial_seed=73129
    start=time.monotonic();r=m.run(args.minutes)
    r['revision']=args.candidate;r['dt_seconds']=args.dt
    (HERE/('explore-'+args.candidate+'-'+args.policy+'.json')).write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(candidate=args.candidate,elapsed_seconds=round(time.monotonic()-start,1),**summarize(r)),ensure_ascii=False),flush=True)

if __name__=='__main__':main()
