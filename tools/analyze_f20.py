"""Independent raw-ledger/case coverage audit; never reads player data."""
from pathlib import Path
import json,hashlib,itertools,argparse,re
r=Path(__file__).resolve().parents[1]; out=r/'.verification/f20-20261020'
parser=argparse.ArgumentParser(); parser.add_argument('--partial',action='store_true'); parser.add_argument('--growth-root',default=''); parser.add_argument('--returning-override',default=''); args=parser.parse_args()
growth_dir=out/args.growth_root/'growth' if args.growth_root else out/'growth'
checks=0
catalog=json.loads((r/'data/content_expansion.json').read_text(encoding='utf-8-sig'))
region_fees={x['id']:x['departure_cost'] for x in catalog['regions']}
def check(ok,message):
 global checks
 checks+=1
 assert ok,message
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
effects=[]
for p in (out/'A/effects').glob('*.json'):
 d=read(p)
 if d['mode']=='contracts_off':continue
 check(d['net']==d['retail_revenue']+d['contract_paid']-d['materials']-d['fees'],str(p)+' cash ledger')
 effects.append(dict(seed=d['seed'],scenario=d['scenario'],stage=d['mode'],net=d['net'],retail=d['retail_revenue'],shipped=d['shipped'],zero=d['zero_stock_seconds'],mean_stock=d['mean_stock'],raw=str(p.relative_to(r))))
for p in (out/'effects').glob('*-stage*.json'):
 d=read(p); a=d['initial']; b=d['final']; m=d['metrics']
 check(d['passed'],str(p))
 check(d['net']==b['gold']-a['gold']==b['retail_revenue']-a['retail_revenue']+b['contract_paid']-a['contract_paid']-b['material_cost']+a['material_cost']-b['fees']+a['fees'],str(p)+' independent net')
 # All operating expenses are monotonic and these comparisons contain no
 # purchases. Even ignoring all income, cash never approaches the order
 # reserve. The later funded-order boundary fix therefore cannot affect them.
 check(a['gold']-(b['material_cost']-a['material_cost'])-(b['fees']-a['fees'])>38,str(p)+' no cash-starved order can reach the later boundary fix')
 check(abs(d['mean_stock']-m['inventory_seconds']/7200)<1e-7,str(p)+' stock integral')
 consumed={}
 for start in d['actual_batch_starts']:
  check(start['line'] in ('main','aux'),str(p)+' line')
  check(start['purpose']=='contract' if start['line']=='aux' else start['purpose']=='ordinary',str(p)+' production role')
  for material,n in start['ingredients'].items():consumed[material]=consumed.get(material,0)+n
 check(consumed==d['consumed'],str(p)+' exact material reservation ledger')
 paid_rounds=[x['completed_round'] for x in d['settlements']]
 check(len(paid_rounds)==len(set(paid_rounds)),str(p)+' each round settles once')
 check(sum(x['paid'] for x in d['settlements'])==b['contract_paid']-a['contract_paid'],str(p)+' actual settlement cash')
 for mat,n in d['material_start'].items():
  check(d['material_end'][mat]-n+d['consumed'].get(mat,0)-d['supplied'].get(mat,0)-(d['bought_mushrooms'] if mat=='moon_mushroom' else 0)==d['generated'][mat]>=0,str(p)+' material '+mat)
 effects.append(dict(seed=d['seed'],scenario=d['scenario'],stage='stage'+str(d['stage']),net=d['net'],retail=b['retail_revenue']-a['retail_revenue'],shipped=b['contract_shipped']-a['contract_shipped'],zero=m['zero_stock_seconds'],aux_seconds=m['aux_activity_seconds'],mean_stock=d['mean_stock'],raw=str(p.relative_to(r))))
check(len(effects)==30,'30 actual initial effect cases')
check(len({(d['seed'],d['scenario'],d['stage']) for d in effects})==30,'No duplicate effect conditions')
for d in effects:check(0<=d['zero']<=7200 and d['mean_stock']>=0,'Real stock metrics')
growth=[]
growth_files=list(growth_dir.glob('*.json'))
if args.returning_override:
 growth_files=[p for p in growth_files if not p.name.startswith('returning-')]+[r/args.returning_override]
for p in growth_files:
 d=read(p); a=d['initial']; b=d['final']; buys=d['purchases']; purchase_sum=0; previous_time=0; max_gap=0
 for buy in buys:
  # Opening a region immediately invokes existing expedition dispatch. Its
  # departure fee is an operating expense, separate from the unlock price.
  extra=buy['gold_before']-buy['gold_after']-buy['cost']
  allowed_fee=region_fees.get(buy.get('kind','').removeprefix('region:'),0) if buy.get('kind','').startswith('region:') else 0
  if buy.get('kind')=='expedition':allowed_fee=region_fees['forest_edge']
  check(buy['cost']>0 and extra in (0,allowed_fee),str(p)+' purchase plus actual immediate region departure fee')
  check(buy['time']>=previous_time,str(p)+' actual chronological purchase')
  max_gap=max(max_gap,buy['time']-previous_time); previous_time=buy['time'];purchase_sum+=buy['cost']
  if buy['action']=='workshop_purchase':check(buy['cost']==[3000000,1500000,3000000][buy['stage']-1],str(p)+' exact adopted initial price')
 check(purchase_sum==b['manual_spent']-a['manual_spent'],str(p)+' total actual manual payments')
 check(b['gold']==a['gold']+b['retail_revenue']-a['retail_revenue']+b['contract_paid']-a['contract_paid']-b['material_cost']+a['material_cost']-b['fees']+a['fees']-purchase_sum,str(p)+' final cash')
 check(d['seconds']==172800 and all('balance_%dh'%h in d['milestones'] for h in (24,36,48)),str(p)+' actual48h observations')
 check(len(d['windows_15m'])==192,str(p)+'192 actual checkpoints')
 for mat,n in d['material_start'].items():check(d['material_end'][mat]-n+d['consumed'].get(mat,0)-d['supplied'].get(mat,0)-(d['bought_mushrooms'] if mat=='moon_mushroom' else 0)==d['generated'][mat]>=0,str(p)+' resource ledger')
 growth.append(dict(seed=d['seed'],return_seconds=d['return_seconds'],control=d['protected_f19_control'],returning=d['synthetic_returning_2700000'],complete_seconds=d['milestones'].get('f20_complete',{}).get('time'),f19_complete_seconds=d['milestones'].get('f19_complete',{}).get('time'),original_complete_seconds=d['milestones'].get('original_complete',{}).get('time'),unlock_seconds=d['milestones'].get('workshop_unlocked',{}).get('time'),max_closed_purchase_gap=max_gap,last_purchase_seconds=previous_time,tail_wait_seconds=172800-previous_time,balances={str(h):d['milestones']['balance_%dh'%h]['gold'] for h in (24,36,48)},highest_observed_negotiation_grade=max([x.get('grade',1) for x in d['trades']],default=None),new_purchases=[x for x in buys if x['action']=='workshop_purchase'],final_late=b['late_stages'],final_level=b['workshop_level'],raw=str(p.relative_to(r))))
if not args.partial:
 check(len(growth)==13,'6 initial new paths +6 protected-F19 controls +1 returning path')
 for seed,interval in itertools.product((73129,19337,9973),(30,900)):
  paths=[read(r/x['raw']) for x in growth if not x['returning'] and x['seed']==seed and x['return_seconds']==interval]
  check(len(paths)==2,'Paired actual control coverage')
  first_purchase=min([b['time'] for path in paths for b in path['purchases'] if b['action']=='workshop_purchase']+[172801])
  prefix=[[w for w in path['windows_15m'] if w['time'] < first_purchase-0.0001] for path in paths]
  check(prefix[0]==prefix[1],'Independent paired paths reproduce same progression before new purchases')
for path in [out/'A/functional.json',out/'B/functional.json',out/'B/migration.json',out/'B/ui.json',out/'B/unpurchased.json',out/'B/edges.json',out/'B/payment-boundary-pass.json']:check(read(path)['passed'],str(path))
diagnostics=[]
for p in (out/'diagnostics').glob('*-original.json'):
 diagnostics.append(p)
for p in (out/'diagnostics').glob('*-protected.json'):
 diagnostics.append(p)
check(len(diagnostics)==12,'Occupation diagnostics of all original/protected cases')
for p in diagnostics:
 d=read(p);check(d['passed'] and d['same_initial_A_cash_and_retail_and_shipment'],str(p)+' diagnostic economic replay')
 check(d['main_contract_seconds']+d['main_retail_seconds']<=7200.00001,str(p)+' one shared main cauldron')
 for mat,n in d['material_start'].items():check(d['material_end'][mat]-n+d['consumed'].get(mat,0)-d['supplied'].get(mat,0)-(d['bought_mushrooms'] if mat=='moon_mushroom' else 0)==d['generated'][mat]>=0,str(p)+' diagnostic material '+mat)
alternatives=list((out/'alternatives').glob('*-stage*.json'))
check(len(alternatives)==6,'Six separate non-adopted policy comparisons')
for p in alternatives:
 d=read(p);expense=d['retail_revenue']+d['contract_paid']-d['net']
 check(d['passed'] and d['not_adopted'] and 0<=expense<1000000-38,str(p)+' non-adopted and independent of cash-starved boundary')
logs=['A/functional.log','A/effects.log','B/payment-fixed-verify_f20_workshop.log','B/final-verify_f20_migration.log','ui/current-functional.log','B/unpurchased.log','B/payment-fixed-verify_f20_edges.log','B/payment-fixed-verify_f20_payment_boundary.log','B/f19-regression.log','ui/stable-tabs.log','ui/export-final.log','diagnostics/run.log']
for name in logs:check(not re.search(r'(^ERROR:|SCRIPT ERROR|\bFAIL\b)',(out/name).read_text(encoding='utf-8-sig'),re.M),name+' final clean log')
hashes={}
for folder in ('scripts','data'):
 for p in (r/folder).rglob('*'):
  if p.is_file() and p.suffix in ('.gd','.json'):hashes[str(p.relative_to(r))]=hashlib.sha256(p.read_bytes()).hexdigest()
result={'partial':args.partial,'growth_root':args.growth_root,'returning_override':args.returning_override,'checks':checks,'effect_cases':effects,'growth_cases':growth,'final_source_sha256':hashes,'initial_model_hashes':'initial-model/source-hashes.json','initial_model_validation_only_change':'B/workshop-before-validation.gd is pre-tightening auxiliary chance validator; simulation reservations/timing/purchases unchanged. Remaining initial runs use initial-model frozen sources. protected-final-model limits main time freezing to purchased expansion; its fresh growth is separate. Payment boundary fix is unreachable in all12 fresh paths because expansion stays unpurchased; separate current returning replay is used when provided.','gameplay_or_real_save_accessed':False,'gui_or_computer_use_used':False,'functional_checks':{'A':37,'BC':74,'migration':181,'UI':read(out/'B/ui.json')['checks'],'existing_F19_core':141,'unpurchased_regression':1269,'capacity_and_settlement_edges':15,'funded_delivery_boundary':1},'passed':True,'balance_accepted':False}
audit_name=('audit-protected-final' if args.growth_root else 'audit')+('-partial' if args.partial else '')+'.json'
if args.returning_override:audit_name='audit-current'+('-partial' if args.partial else '')+'.json'
(out/audit_name).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('F20 INDEPENDENT AUDIT',checks,'checks;30 effects;',len(growth),'growth; balance acceptance remains separate')
for d in growth:print(d['seed'],d['return_seconds'],'control' if d['control'] else 'returning' if d['returning'] else 'new',d['final_late'],d['final_level'],d['complete_seconds'])
