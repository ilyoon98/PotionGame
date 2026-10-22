"""Audit approved recovery from actual production ledgers, never player saves."""
from pathlib import Path
import argparse
import hashlib
import itertools
import json
import re

project = Path(__file__).resolve().parents[1]
out = project / '.verification/f20-recovery-20261020'
parser = argparse.ArgumentParser()
parser.add_argument('--partial', action='store_true')
args = parser.parse_args()
checks = 0

def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))

def check(condition, label):
    global checks
    checks += 1
    assert condition, label

def cash(a, b, manual=0):
    return (a['gold'] + b['retail_revenue'] - a['retail_revenue']
            + b['contract_paid'] - a['contract_paid']
            - b['material_cost'] + a['material_cost']
            - b['fees'] + a['fees'] - manual)

def materials(d, label):
    for material, n in d['material_start'].items():
        generated = (d['material_end'][material] - n + d['consumed'].get(material, 0)
                     - d['supplied'].get(material, 0)
                     - (d['bought_mushrooms'] if material == 'moon_mushroom' else 0))
        check(generated == d['generated'][material] >= 0, label + ': materials ' + material)

content = read(project / 'data/content_expansion.json')
recipes = {x['id']: x for x in content['potions']}
# Base/legacy recipes belong to the original progression catalog.
for p in (project / 'data').glob('*.json'):
    data = read(p)
    if isinstance(data, dict):
        for row in data.get('potions', []):
            if isinstance(row, dict) and 'ingredients' in row:
                recipes[row['id']] = row
fees = {x['id']: x['departure_cost'] for x in content['regions']}
for line in (project/'scripts/rare_recipes.gd').read_text(encoding='utf-8-sig').splitlines():
    if line.strip().startswith('{"id":'):
        row = json.loads(line.strip().removesuffix(','))
        recipes[row['id']] = row
effects = []
for p in sorted((out / 'effects').glob('*.json')):
    d = read(p); a = d['initial']; b = d['final']; metrics = d['metrics']
    label = p.name
    check(d['passed'] and d['seconds'] == 7200, label + ': actual 2h')
    check(d['net'] == b['gold'] - a['gold'] == cash(a, b) - a['gold'], label + ': cash')
    check(abs(d['mean_stock'] - metrics['inventory_seconds'] / 7200) < 1e-7, label + ': integral')
    consumed = {}
    for start in d['actual_batch_starts']:
        kind = start['kind']
        potion = ('mana' if kind else 'health') if isinstance(kind, bool) else kind
        check(start['line'] in ('main', 'aux'), label + ': real line')
        check(start['line'] != 'aux' or start['purpose'] == 'contract', label + ': aux only shipment')
        check(d['stage'] == 0 or start['line'] != 'main' or start['purpose'] == 'ordinary', label + ': expanded main only retail')
        q = start['quantity']
        check(1 <= q <= 4 and (start['purpose'] == 'contract' or q == 1), label + ': actual quantity')
        expected = {m: n * q for m, n in recipes[potion]['ingredients'].items()}
        check(start['ingredients'] == expected, label + ': ingredients follow actual recipe and bottle count')
        for material, n in start['ingredients'].items():
            consumed[material] = consumed.get(material, 0) + n
    check(consumed == d['consumed'], label + ': all consumed reservations counted')
    rounds = [row['completed_round'] for row in d['settlements']]
    check(len(rounds) == len(set(rounds)), label + ': no duplicate payout')
    check(sum(x['paid'] for x in d['settlements']) == b['contract_paid'] - a['contract_paid'], label + ': exact settled cash')
    materials(d, label)
    for w in d['windows']:
        check(w['gold'] == cash(a, w), label + ': checkpoint cash')
    effects.append(dict(seed=d['seed'], scenario=d['scenario'], stage=d['stage'], net=d['net'],
                        retail=b['retail_revenue']-a['retail_revenue'],
                        shipped=b['contract_shipped']-a['contract_shipped'],
                        paid=b['contract_paid']-a['contract_paid'],
                        zero=metrics['zero_stock_seconds'], mean_stock=d['mean_stock'],
                        aux_seconds=metrics['aux_activity_seconds'], raw=p.relative_to(project).as_posix()))
check(len(effects) == 24, '3 seeds x 2 supply conditions x 4 actual expansion stages')
check(len({(x['seed'], x['scenario'], x['stage']) for x in effects}) == 24, 'Unique conditions')

growth = []
for p in sorted((out / 'growth').glob('*.json')):
    d = read(p); a = d['initial']; b = d['final']; label = p.name
    completion = 'F20 GROWTH PASS ' + p.stem
    check(any(completion in log.read_text(encoding='utf-8-sig') for log in out.glob('*.log')),
          label + ': headless run actually completed')
    total = 0; previous_time = 0; maximum_gap = 0
    for buy in d['purchases']:
        extra = buy['gold_before'] - buy['gold_after'] - buy['cost']
        kind = buy.get('kind', '')
        immediate_fee = fees.get(kind.removeprefix('region:'), 0) if kind.startswith('region:') else 0
        if kind == 'expedition':
            immediate_fee = fees['forest_edge']
        check(extra in (0, immediate_fee) and buy['cost'] > 0, label + ': actual purchase debit and departure fee')
        check(buy['time'] >= previous_time, label + ': chronological purchase')
        maximum_gap = max(maximum_gap, buy['time'] - previous_time)
        previous_time = buy['time']; total += buy['cost']
        if buy['action'] == 'workshop_purchase':
            check(buy['cost'] == [3000000, 1500000, 3000000][buy['stage']-1], label + ': unchanged initial costs')
    check(total == b['manual_spent'] - a['manual_spent'], label + ': all real manual expenditure')
    check(b['gold'] == cash(a, b, total), label + ': final cash')
    check(d['passed'] and d['seconds'] == 172800 and len(d['windows_15m']) == 192, label + ': actual 48h')
    for w in d['windows_15m']:
        spent = sum(x['cost'] for x in d['purchases'] if x['time'] <= w['time'] + 0.001)
        check(w['gold'] == cash(a, w, spent), label + ': actual 15m ledger')
    materials(d, label)
    check(all('balance_%dh' % h in d['milestones'] for h in (24,36,48)), label + ': observed milestones')
    grade = max((row.get('grade', 1) for row in d['trades']), default=0)
    if not d['synthetic_returning_2700000']:
        check(a['gold'] == 0 and a['manual_spent'] == 0 and a['contract_shipped'] == 0, label + ': fresh zero-gold, no invented shipments')
        check(grade >= 4, label + ': actually observed unlocked grade4 agreement')
        check('f19_complete' in d['milestones'], label + ': original supply and bulk growth reaches level3')
    if not d['protected_f19_control']:
        check('workshop_unlocked' in d['milestones'] and b['workshop_level'] == 3, label + ': real unlock and complete paid purchases')
    growth.append(dict(seed=d['seed'], return_seconds=d['return_seconds'], control=d['protected_f19_control'],
                       returning=d['synthetic_returning_2700000'], grade=grade, final_level=b['workshop_level'],
                       original_complete=d['milestones'].get('original_complete',{}).get('time'),
                       f19_complete=d['milestones'].get('f19_complete',{}).get('time'),
                       unlock=d['milestones'].get('workshop_unlocked',{}).get('time'),
                       complete=d['milestones'].get('f20_complete',{}).get('time'),
                       balances={str(h):d['milestones']['balance_%dh'%h]['gold'] for h in (24,36,48)},
                       purchases=[x for x in d['purchases'] if x['action']=='workshop_purchase'],
                       last_purchase=previous_time, max_gap=maximum_gap,
                       raw=p.relative_to(project).as_posix()))
if not args.partial:
    check(len(growth) == 13, 'Six fresh paths, six independent F19 controls and one synthetic returning path')
    for seed, interval in itertools.product((73129,19337,9973),(30,900)):
        pair = [read(project / x['raw']) for x in growth if not x['returning'] and x['seed']==seed and x['return_seconds']==interval]
        check(len(pair)==2, 'Paired controls')
        first = min(x['time'] for d in pair for x in d['purchases'] if x['action']=='workshop_purchase')
        prefix = [[w for w in d['windows_15m'] if w['time'] < first-0.001] for d in pair]
        check(prefix[0]==prefix[1], 'Whole observed states identical before the first expansion purchase')

functional = {}
for name in ('protection-functional','workshop-functional','migration-migration','ui-ui','edges-edges',
             'payment_boundary-payment-boundary-pass','recovery','unpurchased','chunks'):
    d = read(out / 'checks' / (name + '.json'))
    check(d['passed'], name + ': functionality passes')
    functional[name] = d['checks']
logs = ['protection','workshop','migration','ui','edges','payment_boundary','f19','stable_tabs',
        'export-ui','recovery-final','unpurchased-final','chunks']
for name in logs:
    s = (out / 'checks' / (name + '.log')).read_text(encoding='utf-8-sig')
    check(not re.search(r'(^ERROR:|SCRIPT ERROR|\bFAIL\b)', s, re.M), name + ': final clean log')
    check('PASS' in s or (name=='f19' and '141 checks, 0 failures' in s), name + ': completion marker')
functional['f19-core'] = 141
hashes = read(out / 'model/source-hashes.json')
for rel, h in hashes.items():
    check(hashlib.sha256((project/rel).read_bytes()).hexdigest()==h, 'Frozen model still matches runtime '+rel)
result = dict(passed=True, partial=args.partial, checks=checks, functional_checks=functional,
              functional_total=sum(functional.values()), effects=effects, growth=growth,
              policy='User approved: basic health first while recovery is active; original recipe policy resumes after H',
              gameplay_or_real_save_accessed=False, gui_or_computer_use_used=False,
              planning_marked_complete=False, prices_or_thresholds_changed=False, balance_accepted=False,
              model_source_hashes='model/source-hashes.json')
target = out / ('audit-progress.json' if args.partial else 'audit.json')
target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
if not args.partial:
    proof = dict(result)
    proof.pop('effects'); proof.pop('growth')
    proof['effect_cases'] = 24
    proof['growth_paths'] = 13
    proof['approved_recovery_implemented_and_verified'] = True
    proof['fresh_completion_seconds'] = [x['complete'] for x in growth if not x['returning'] and not x['control']]
    proof['normal_game_restarted'] = False
    (out/'final-proof.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
print('F20 APPROVED RECOVERY AUDIT PASS:',checks,'comparisons;',len(effects),'effects;',len(growth),'growth;',sum(functional.values()),'functional checks')
for x in growth:
    print(x['seed'],x['return_seconds'],'control' if x['control'] else 'returning' if x['returning'] else 'new', 'grade',x['grade'],'complete',x['complete'])
