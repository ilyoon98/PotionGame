"""Candidate economy model. This is not the Godot runtime or a player-save test."""
from pathlib import Path
from collections import Counter
import json, math, argparse

HERE=Path(__file__).resolve().parent
DT=.25

class Model:
    def __init__(self,data,policy,seed):
        self.d=data;self.policy=policy;self.seed=seed
        self.ps={p['id']:p for p in data['potions']};self.rs={r['id']:r for r in data['regions']}
        self.ms={m['id']:m for m in data['materials']};self.es={e['id']:e for e in data['employees']}
        self.gold=0;self.fame=0;self.t=0;self.owned={'health','mana'};self.plants=set();self.stages=Counter();self.staff=set()
        self.materials=Counter(herb=6);self.growth=Counter();self.loot=Counter();self.stock=[];self.batch=None;self.brew_progress=0
        self.harvest_progress=0;self.delivery=0;self.customer_elapsed=0;self.customer=None;self.family_cursor=0;self.first=[]
        self.regions=set();self.returns=Counter();self.destination=None;self.trip_region=None;self.trip_progress=0;self.trip_duration=0
        self.sales=0;self.material_cost=0;self.invested=0;self.sale_count=0;self.failed=0;self.log=[];self.checkpoints=[];self.last_milestone=0
        self.all_regions_at=None;self.all_recipes_at=None;self.all_upgrades_at=None;self.last_trade=0;self.sold_by=Counter()
        self.next_decision=30;self.upgrade_map={}
        self.waiting=False;self.wait_start=0;self.wait_durations=[]
        self.pressure=Counter();self.window_pressure=Counter();self.pressure_windows=[];self.environment_pressure={}
        for u in data['upgrades']:self.upgrade_map[(u['track'],u['stage'])]=u

    def rng(self):
        self.seed=(self.seed*48271)%2147483647
        return self.seed/2147483647

    def environment(self):
        phase=(.45+self.t/240)%1
        return phase<.25 or phase>=.75,int(self.t/90)%3

    def favored(self,env):
        night,w=self.environment()
        return {'rain':w==2,'cloudy':w==1,'clear':w==0,'day':not night,'night':night,'night_clear':night and w==0}.get(env,False)

    def effect(self,track,key,default):
        s=self.stages[track]
        if s:return self.upgrade_map[(track,s)]['effect'].get(key,default)
        if track in self.staff:return self.es[track]['effect'].get(key,default)
        return default

    def completed(self):return sum(self.returns[r['id']]>=r['complete_returns'] for r in self.d['regions'])

    def unlock(self,p):
        u=p['unlock']
        if self.fame<u.get('reputation',0):return False
        if any(x not in self.owned for x in u.get('recipes',[])):return False
        if 'discovery'in u and self.returns[u['discovery']['region']]<u['discovery']['returns']:return False
        return True

    def base_time(self):return self.effect('cauldron','base_brew_seconds',max(.8,5*.88**min(self.stages['cauldron'],14)))

    def potion_time(self,p):
        factor=self.effect('brewing_assistant','new_recipe_time_multiplier',1) if not p['existing'] else 1
        return max(.8,self.base_time()*p['duration_multiplier']*factor)

    def chance(self,p):
        night,w=self.environment();env=0
        if p['id'] in ['moon','purify','agility']:env=(.07 if night else 0)+(.03 if w==2 else 0)
        elif not p['existing'] and self.favored(p['environment']):env=p['environment_bonus']
        return min(1,p['success']+env+(self.effect('precision_filter','success_bonus',0) if p['id'] not in ['health','mana'] else 0))

    def can_make(self,id):return all(self.materials[k]>=v for k,v in self.ps[id]['ingredients'].items())

    def select_batch(self):
        chosen=None
        for id in list(self.first):
            if self.can_make(id):chosen=id;self.first.remove(id);break
        families=self.d['rules']['family_order']
        if chosen is None:
            for offset in range(4):
                fi=(self.family_cursor+offset)%4;family=families[fi]
                options=sorted((p for p in self.ps.values() if p['id'] in self.owned and p['family']==family),key=lambda p:p['order'],reverse=True)
                for p in options:
                    if self.can_make(p['id']):chosen=p['id'];self.family_cursor=(fi+1)%4;break
                if chosen:break
        if chosen is None:return
        p=self.ps[chosen]
        for k,v in p['ingredients'].items():self.materials[k]-=v
        self.batch=(chosen,self.chance(p));self.brew_progress=0

    def customer_family(self):
        night,w=self.environment();weights=[5,2+(3 if night else 0)+(2 if w==1 else 0),2+(4 if w==2 else 0),1+(4 if night else 0)+(2 if w==0 else 0)]
        roll=self.rng()*sum(weights)
        for f,weight in zip(self.d['rules']['family_order'],weights):
            roll-=weight
            if roll<=0:return f
        return 'craft'

    def sale(self):
        if not self.stock:
            if not self.waiting:self.waiting=True;self.wait_start=self.t
            return
        preferred=[(i,self.ps[id]['order']) for i,id in enumerate(self.stock) if self.ps[id]['family']==self.customer]
        index=max(preferred,key=lambda p:p[1])[0] if preferred else 0
        id=self.stock.pop(index);p=self.ps[id];pref=p['family']==self.customer
        quality=self.effect('cauldron','quality_sale_bonus',0)+(self.effect('brewing_assistant','new_recipe_quality_bonus',0) if not p['existing'] else 0)
        family=self.effect('family_'+p['family'],'preferred_sale_bonus',0) if pref else 0
        staff=self.effect('sales_assistant','preferred_sale_flat',0) if pref else 0
        value=int(math.floor(p['sale_price']*(1+quality)*(1+family)+.5))+staff
        self.gold+=value;self.sales+=value;self.sale_count+=1;self.fame+=2 if pref else 1;self.sold_by[id]+=1;self.last_trade=self.t;self.customer=None
        if self.waiting:self.wait_durations.append(self.t-self.wait_start);self.waiting=False

    def trip_reduction(self):return min(.3,self.effect('expedition_path','trip_time_reduction',0)+self.effect('expedition_guide','trip_time_reduction',0))

    def trip_tick(self):
        if self.destination is None:return
        if self.trip_region is None:
            self.trip_region=self.destination;r=self.rs[self.trip_region]
            self.trip_duration=(r['explore_seconds']+r['return_seconds'])*(1-self.trip_reduction());self.trip_progress=0
        self.trip_progress+=DT
        if self.trip_progress+1e-9<self.trip_duration:return
        r=self.rs[self.trip_region];id=r['id'];self.returns[id]+=1
        thresholds=[3,6,10] if r['complete_returns']==10 else [2,4,6] if r['complete_returns']==6 else [1,3,5]
        if self.returns[id] in thresholds:
            self.log.append(dict(t=round(self.t,2),event='discovery',id=id,step=thresholds.index(self.returns[id])+1,gold=self.gold))
        if r['material'] in self.plants:self.loot[r['material']]+=r['repeat_material_quantity']
        if id=='forest_edge' and 'starleaf' in self.plants:self.loot['starleaf']+=2
        if self.returns[id]==r['complete_returns']:
            self.log.append(dict(t=round(self.t,2),event='region_complete',id=id,gold=self.gold))
        self.trip_region=None

    def buy(self,kind,id,cost):
        if self.gold<cost:return False
        self.gold-=cost;self.invested+=cost
        if kind=='recipe':
            self.owned.add(id);p=self.ps[id];self.first.append(id)
            if id in ['moon','purify','agility']:self.plants.add('starleaf')
            for material in p.get('grant_sources',[]):
                if material not in self.plants:self.plants.add(material);self.materials[material]+=2
        elif kind=='region':self.regions.add(id);self.destination=id
        elif kind=='employee':self.staff.add(id)
        else:self.stages[id]+=1
        self.log.append(dict(t=round(self.t,2),event=kind,id=id,stage=self.stages[id] if kind=='upgrade' else None,cost=cost,gold=self.gold))
        return True

    def purchase(self):
        # Proxy for user decisions, not a proposed automatic-purchase game mechanic.
        for _ in range(160):
            done=self.completed();candidates=[]
            def add(rank,kind,id,cost):
                if cost<=self.gold:candidates.append((rank,cost,kind,id))
            for p in self.ps.values():
                if p['id'] not in self.owned and self.unlock(p):
                    rank=5 if p['existing'] else 20-p['order']/100
                    add(rank,'recipe',p['id'],p['cost'])
            next_region=next((r for r in self.d['regions'] if r['id'] not in self.regions),None)
            if next_region and self.fame>=next_region['reputation'] and (not next_region['previous_region'] or self.returns[next_region['previous_region']]>=self.rs[next_region['previous_region']]['complete_returns']):
                add(8 if self.policy!='equipment_first' else 25,'region',next_region['id'],next_region['cost'])
            for e in self.d['employees']:
                if e['id'] not in self.staff and done>=e['completed_regions'] and self.fame>=e['reputation']:
                    add(23 if e['id']=='sales_assistant' else 34,'employee',e['id'],e['cost'])
            # Keep some cash for a visible newly discovered recipe / next region.
            goals=[p['cost'] for p in self.ps.values() if p['id'] not in self.owned and self.unlock(p) and not p['existing']]
            if next_region and (not next_region['previous_region'] or done>=self.d['regions'].index(next_region)):goals.append(next_region['cost'])
            reserve=min(goals) if goals else 0
            for u in self.d['upgrades']:
                track=u['track']
                if u['stage']!=self.stages[track]+1 or done<u['completed_regions'] or self.fame<u['reputation']:continue
                if u['kind']=='training' and track not in self.staff:continue
                essential=(track=='cauldron' and u['stage']<=min(14,4+done*2)) or (track=='herb_pot' and u['stage']<=min(11,2+done))
                if essential:rank=2 if u['stage']<=2 else 15
                elif track=='sales_counter' and u['stage']<=2+done:rank=27
                else:rank=40
                if self.policy=='equipment_first':rank-=12
                if not essential and self.gold-u['cost']<reserve and self.policy!='equipment_first':continue
                add(rank,'upgrade',track,u['cost'])
            if not candidates:break
            rank,cost,kind,id=min(candidates)
            self.buy(kind,id,cost)

    def snapshot(self):
        return dict(minute=round(self.t/60,1),gold=self.gold,recipes=len(self.owned),completed_regions=self.completed(),opened_regions=len(self.regions),destination=self.destination,investments=sum(self.stages.values()),employees=len(self.staff),sold=self.sale_count,gross=self.sales,materials=self.material_cost,net=self.sales-self.material_cost,spent=self.invested,loot=sum(self.loot.values()),stock=len(self.stock),stock_capacity=self.effect('potion_cabinet','total_potion_capacity',12),stages=dict(self.stages))

    def measure_pressure(self):
        cap=self.effect('potion_cabinet','total_potion_capacity',12)
        full=len(self.stock)>=cap
        shortage=self.batch is None and not full and not any(self.can_make(id) for id in self.owned)
        night,w=self.environment();env=('night' if night else 'day')+'_'+['clear','cloudy','rain'][w]
        bucket=self.environment_pressure.setdefault(env,Counter())
        values={'seconds':DT,'full_seconds':DT if full else 0,'waiting_seconds':DT if self.waiting else 0,'material_shortage_seconds':DT if shortage else 0,'inventory_ratio_seconds':DT*len(self.stock)/cap}
        for key,value in values.items():
            self.pressure[key]+=value;self.window_pressure[key]+=value;bucket[key]+=value
        if self.t%300==0:
            self.pressure_windows.append(dict(end_minute=self.t/60,**dict(self.window_pressure)))
            self.window_pressure=Counter()

    def run(self,minutes=480):
        checkpoints={10,30,60,120,180,240,300,480}
        for tick in range(round(self.t/DT)+1,round(minutes*60/DT)+1):
            self.t=tick*DT
            self.measure_pressure()
            special_capacity=self.effect('herb_storage','special_capacity',12)
            for material in self.plants:
                m=self.ms[material]
                space=special_capacity-self.materials[material]
                added=min(space,self.loot[material]);self.materials[material]+=added;self.loot[material]-=added
                if self.materials[material]>=special_capacity:continue
                rate=1
                if material=='starleaf':
                    night,w=self.environment();rate=(1.25 if night else 1)*(1.5 if w==2 else 1)
                else:
                    rate=(1.5 if self.favored(m['environment']) else 1)*self.effect('drying_rack','new_material_growth_multiplier',1)*self.effect('cultivation_assistant','new_material_growth_multiplier',1)
                self.growth[material]+=DT*rate
                if self.growth[material]>=m['growth_seconds']:
                    self.growth[material]-=m['growth_seconds'];self.materials[material]+=1
            herb_cap=self.effect('herb_pot','herb_capacity',24)
            if self.materials['herb']<herb_cap:
                self.harvest_progress+=DT/self.effect('herb_pot','harvest_seconds',4)
                if self.harvest_progress>=1:
                    self.harvest_progress-=1;self.materials['herb']=min(herb_cap,self.materials['herb']+self.effect('herb_pot','harvest_quantity',2))
            self.delivery=min(12,self.delivery+DT)
            quantity=min(2,6-self.materials['moon_mushroom'])
            if self.delivery>=12 and quantity>0 and self.gold>=30+4*quantity:
                self.gold-=4*quantity;self.material_cost+=4*quantity;self.materials['moon_mushroom']+=quantity;self.delivery=0
            cap=self.effect('potion_cabinet','total_potion_capacity',12)
            if self.batch is None and len(self.stock)<cap:self.select_batch()
            if self.batch is not None and len(self.stock)<cap:
                id,chance=self.batch;self.brew_progress+=DT/self.potion_time(self.ps[id])
                if self.brew_progress>=1:
                    if self.rng()<chance:self.stock.append(id)
                    else:self.failed+=1
                    self.batch=None;self.brew_progress=0
            self.customer_elapsed+=DT
            interval=self.effect('sales_counter','customer_seconds',3.2)
            if self.customer is None and self.customer_elapsed>=interval*.34:self.customer=self.customer_family()
            if self.customer_elapsed>=interval:
                self.customer_elapsed=0;self.sale()
            self.trip_tick()
            if self.t>=self.next_decision:
                self.purchase();self.next_decision+=900 if self.policy=='return_15m' else 30
            if self.completed()==8 and self.all_regions_at is None:self.all_regions_at=self.t/60
            if len(self.owned)==32 and self.all_recipes_at is None:self.all_recipes_at=self.t/60
            if sum(self.stages.values())==125 and len(self.staff)==4 and self.all_upgrades_at is None:self.all_upgrades_at=self.t/60
            if self.t%60==0 and int(self.t/60) in checkpoints:self.checkpoints.append(self.snapshot())
        if self.waiting:self.wait_durations.append(self.t-self.wait_start)
        return dict(policy=self.policy,seed_initial=self.initial_seed,checkpoints=self.checkpoints,all_regions_min=self.all_regions_at,all_recipes_min=self.all_recipes_at,all_investments_min=self.all_upgrades_at,final=self.snapshot(),events=self.log,sold_by=dict(self.sold_by),pressure=dict(self.pressure),pressure_windows=self.pressure_windows,environment_pressure={k:dict(v) for k,v in self.environment_pressure.items()},wait_durations=self.wait_durations)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--minutes',type=int,default=480);parser.add_argument('--seeds',type=int,default=3)
    parser.add_argument('--dt',type=float,default=.05);parser.add_argument('--data',default='content-data-v1.json');parser.add_argument('--output',default='simulation-results.json');args=parser.parse_args()
    global DT
    DT=args.dt
    data=json.loads((HERE/args.data).read_text(encoding='utf-8'))
    runs=[]
    for policy in ['expedition_first','equipment_first','return_15m']:
        for seed in [73129,19337,9973][:args.seeds]:
            model=Model(data,policy,seed);model.initial_seed=seed
            result=model.run(args.minutes);runs.append(result)
            print(json.dumps({k:result[k] for k in ['policy','seed_initial','all_regions_min','all_recipes_min','all_investments_min']},ensure_ascii=False),flush=True)
    result={'revision':data['revision'],'model':f'independent planning model, fixed {DT}s step; not Godot validation','dt_seconds':DT,'minutes':args.minutes,'runs':runs}
    (HERE/args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
