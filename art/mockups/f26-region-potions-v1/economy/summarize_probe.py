import json, sys, glob, os, statistics as st
d = sys.argv[1]; out = sys.argv[2]
variants = {}
for path in sorted(glob.glob(os.path.join(d, '*.json'))):
    name = os.path.basename(path)[:-5]
    variant, seed = name.rsplit('-', 1)
    r = json.load(open(path, encoding='utf-8'))
    w = r['windows']; s, e = w[0], w[-1]; h = r['hours']
    net = (e['gold'] + e['manual_spent']) - (s['gold'] + s['manual_spent'])
    hourly = [int((b['gold'] + b['manual_spent']) - (a['gold'] + a['manual_spent'])) for a, b in zip(w[0::2], w[2::2])]
    row = {'seed': int(seed), 'net_per_hour': net / h, 'retail_per_hour': (e['retail'] - s['retail']) / h,
           'contract_per_hour': (e['contract_paid'] - s['contract_paid']) / h, 'aging_per_hour': (e['aging_revenue'] - s['aging_revenue']) / h,
           'material_cost_per_hour': (e['materials'] - s['materials']) / h, 'fees_per_hour': (e['fees'] - s['fees']) / h,
           'sold_per_hour': (e['retail_sold'] - s['retail_sold']) / h,
           'new_sold': {k: e['new_sold'][k] - s['new_sold'][k] for k in e['new_sold']}, 'hourly_net': hourly,
           'events': [{'minute': round(x['time'] / 60, 1), 'event': x['event'], 'id': x.get('id', ''), 'cost': x.get('cost', 0)} for x in r['events']],
           'region_returns': e['returns'], 'region_rewards': r.get('region_rewards', {}), 'spent_on_content': e['manual_spent'] - s['manual_spent'],
           'price_scale': r['price_scale'], 'check_every': r['check_every']}
    variants.setdefault(variant, []).append(row)
summary = {}
for v, rows in variants.items():
    mean = lambda k: round(st.mean(r[k] for r in rows))
    summary[v] = {'seeds': [r['seed'] for r in rows], 'net_per_hour': mean('net_per_hour'), 'retail_per_hour': mean('retail_per_hour'),
                  'contract_per_hour': mean('contract_per_hour'), 'aging_per_hour': mean('aging_per_hour'),
                  'material_cost_per_hour': mean('material_cost_per_hour'), 'fees_per_hour': mean('fees_per_hour'), 'sold_per_hour': mean('sold_per_hour'),
                  'new_sold_6h': {k: round(st.mean(r['new_sold'][k] for r in rows)) for k in rows[0]['new_sold']},
                  'hourly_net': [round(st.mean(r['hourly_net'][i] for r in rows)) for i in range(len(rows[0]['hourly_net']))],
                  'net_per_hour_by_seed': [round(r['net_per_hour']) for r in rows],
                  'events_by_seed': {r['seed']: r['events'] for r in rows}, 'spent_on_content': rows[0]['spent_on_content'],
                  'region_rewards_6h_mean': {k: round(st.mean(r['region_rewards'].get(k, 0) for r in rows)) for k in set().union(*[r['region_rewards'] for r in rows])}}
base = summary['baseline']['net_per_hour']
for v in summary:
    summary[v]['gain_vs_baseline_per_hour'] = summary[v]['net_per_hour'] - base
    summary[v]['gain_pct'] = round(100 * (summary[v]['net_per_hour'] - base) / base, 1)
json.dump(summary, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
for v, s in summary.items():
    print(v, s['net_per_hour'], s['gain_vs_baseline_per_hour'], s['gain_pct'], 'retail', s['retail_per_hour'], 'contract', s['contract_per_hour'], 'aging', s['aging_per_hour'], 'fees', s['fees_per_hour'], 'sold/h', s['sold_per_hour'])
    print('   new6h', s['new_sold_6h'], 'hourly', s['hourly_net'], 'rewards', s['region_rewards_6h_mean'])
    for seed, ev in s['events_by_seed'].items():
        if ev: print('   ', seed, [(e['minute'], e['id'] or e['event']) for e in ev])
