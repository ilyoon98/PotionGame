"""Build and evaluate the paid parallel expedition planning input only."""
from pathlib import Path
from copy import deepcopy
from collections import Counter
import json
import simulate
from simulate import Model

HERE=Path(__file__).resolve().parent

def build():
    d=deepcopy(json.loads((HERE/'content-data-v1.json').read_text(encoding='utf-8')))
    assert d['revision']=='candidate-c'
    d['revision']='candidate-d-multi-expedition'
    d['status']='implementation_initial_values_not_runtime'
    d['rules'].update(expedition_mode='parallel_one_trip_per_region',expedition_reserve_gold=30,completed_region_refill_fraction=.5)
    for r,fee,qty in zip(d['regions'],[8,12,20,30,45,60,80,100],[2,2,3,3,4,4,5,6]):
        r['departure_cost']=fee;r['repeat_material_quantity']=qty;r['rewards']={r['material']:qty}
        if r['id']=='forest_edge':r['rewards']['starleaf']=2
    (HERE/'content-data-multi-expedition-v1.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return d

class MultiModel(Model):
    def __init__(self,*args):
        super().__init__(*args)
        self.trips={};self.ready_at={};self.expedition_cost=0;self.departures=Counter();self.max_parallel=0

    def eligible(self,r):
        if self.returns[r['id']]<r['complete_returns']:return True
        cap=self.effect('herb_storage','special_capacity',12)
        totals={k:self.materials[k]+self.loot[k] for k in r['rewards']}
        return all(totals[k]+qty<=cap for k,qty in r['rewards'].items()) and any(totals[k]<=cap*.5 for k in totals)

    def trip_tick(self):
        # Receive queued expedition rewards even before cultivation is purchased.
        cap=self.effect('herb_storage','special_capacity',12)
        for material in self.loot:
            amount=min(max(0,cap-self.materials[material]),self.loot[material])
            self.materials[material]+=amount;self.loot[material]-=amount
        for id,trip in list(self.trips.items()):
            trip['progress']+=simulate.DT
            if trip['progress']+1e-9<trip['duration']:continue
            r=self.rs[id];self.returns[id]+=1
            thresholds=[3,6,10] if r['complete_returns']==10 else [2,4,6] if r['complete_returns']==6 else [1,3,5]
            if self.returns[id] in thresholds:self.log.append(dict(t=round(self.t,2),event='discovery',id=id,step=thresholds.index(self.returns[id])+1,gold=self.gold))
            for material,qty in trip['rewards'].items():self.loot[material]+=qty
            if self.returns[id]==r['complete_returns']:self.log.append(dict(t=round(self.t,2),event='region_complete',id=id,gold=self.gold))
            del self.trips[id];self.ready_at[id]=self.t
        queue=[self.rs[id] for id in self.regions if id not in self.trips and self.eligible(self.rs[id])]
        queue.sort(key=lambda r:(self.returns[r['id']]>=r['complete_returns'],self.ready_at.get(r['id'],self.t),self.d['regions'].index(r)))
        reserve=self.d['rules']['expedition_reserve_gold']
        research=[r for r in queue if self.returns[r['id']]<r['complete_returns']]
        for r in queue:
            protect=reserve
            if self.returns[r['id']]>=r['complete_returns']:
                pending=next((x for x in research if x['id'] not in self.trips),None)
                if pending:protect+=pending['departure_cost']
            fee=r['departure_cost']
            if self.gold-fee<protect:continue
            self.gold-=fee;self.expedition_cost+=fee;self.departures[r['id']]+=1
            self.trips[r['id']]={'progress':0,'duration':(r['explore_seconds']+r['return_seconds'])*(1-self.trip_reduction()),'rewards':dict(r['rewards'])}
            self.log.append(dict(t=round(self.t,2),event='expedition_departure',id=r['id'],cost=fee,gold=self.gold))
        self.max_parallel=max(self.max_parallel,len(self.trips))

    def snapshot(self):
        s=super().snapshot();s.update(expedition_spent=self.expedition_cost,net=self.sales-self.material_cost-self.expedition_cost,active_expeditions=len(self.trips),departures=dict(self.departures),max_parallel=self.max_parallel)
        return s

def check_boundaries(d):
    first,second=d['regions'][:2];reserve=d['rules']['expedition_reserve_gold']
    def model(gold,ids):
        m=MultiModel(d,'expedition_first',73129);m.initial_seed=73129;m.gold=gold;m.regions=set(ids);return m
    m=model(reserve+first['departure_cost']-1,[first['id']]);m.trip_tick()
    assert not m.trips and m.expedition_cost==0
    m.gold+=1;m.trip_tick();assert len(m.trips)==1 and m.gold==reserve
    cost=m.expedition_cost;m.trip_tick();assert m.expedition_cost==cost
    m=model(reserve+sum(r['departure_cost'] for r in d['regions']),[r['id'] for r in d['regions']]);m.trip_tick()
    assert len(m.trips)==8 and m.gold==reserve
    m.trip_tick();assert len(m.trips)==8 and all(t['progress']>0 for t in m.trips.values())
    m=model(1000,[first['id']]);m.returns[first['id']]=first['complete_returns']
    for key in first['rewards']:m.materials[key]=12
    m.trip_tick();assert not m.trips
    for key in first['rewards']:m.materials[key]=4
    m.trip_tick();assert len(m.trips)==1
    m=model(reserve+first['departure_cost']+1,[first['id'],second['id']]);m.returns[first['id']]=first['complete_returns'];m.trip_tick()
    assert not m.trips
    m.gold=reserve+second['departure_cost'];m.trip_tick()
    assert set(m.trips)=={second['id']} and m.gold==reserve
    print('PASS: reserve boundary, auto-resume, single departure charge, eight simultaneous trips, full-store wait, research budget protection',flush=True)

def main():
    simulate.DT=.05;d=build();runs=[]
    check_boundaries(d)
    for policy in ['expedition_first','equipment_first','return_15m']:
        for seed in [73129,19337,9973]:
            m=MultiModel(d,policy,seed);m.initial_seed=seed;r=m.run(480)
            for c in r['checkpoints']:
                assert c['gold']==c['gross']-c['materials']-c['expedition_spent']-c['spent']
                assert 0<=c['stock']<=c['stock_capacity'] and c['gold']>=0
                if c['minute']==120:assert c['recipes']<32 and c['completed_regions']<8 and c['investments']<125
            assert r['all_regions_min']>=141+52/60 and r['all_recipes_min']>120
            departures=[e for e in r['events'] if e['event']=='expedition_departure']
            assert sum(e['cost'] for e in departures)==r['final']['expedition_spent']
            assert sum(r['final']['departures'].values())==len(departures)
            runs.append(r)
            print(json.dumps(dict(policy=policy,seed=seed,all_regions=r['all_regions_min'],all_recipes=r['all_recipes_min'],all_investments=r['all_investments_min'],expedition_spent=r['final']['expedition_spent'],max_parallel=r['final']['max_parallel']),ensure_ascii=False),flush=True)
    out=dict(revision=d['revision'],dt_seconds=.05,minutes=480,model='Independent planning model; paid parallel trips and protected procurement reserve; not Godot or Computer Use validation',runs=runs)
    (HERE/'simulation-multi-expedition-v1.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
