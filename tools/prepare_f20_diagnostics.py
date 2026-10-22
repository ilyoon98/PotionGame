from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]; out=r/'.verification/f20-20261020/diagnostics';out.mkdir(exist_ok=True)
manifest={}
for name,path in [('original','baseline/metrics_state.gd'),('protected','initial-model/scripts/shop_state.gd')]:
 p=r/'.verification/f20-20261020'/path;s=p.read_text(encoding='utf-8')
 s=s.replace('var empty_sale_attempts := 0','var empty_sale_attempts := 0\n\tvar contract_activity := 0.0\n\tvar retail_activity := 0.0\n\tvar contract_material_wait := 0.0')
 s=s.replace('full_seconds += step if stock >= capacity() else 0.0','full_seconds += step if stock >= capacity() else 0.0\n\t\tcontract_activity += step if can_brew and contracts.batch.get("purpose") == "contract" else 0.0\n\t\tretail_activity += step if can_brew and contracts.batch.get("purpose") != "contract" else 0.0\n\t\tcontract_material_wait += step if not brew_active and contracts.unlocked(self) and (contracts.ordinary_batches >= 4 or stock >= capacity()) and contracts.candidate(self).is_empty() else 0.0')
 s=s.replace('"zero_stock_seconds": zero_stock_seconds}', '"zero_stock_seconds": zero_stock_seconds, "contract_activity": contract_activity, "retail_activity": retail_activity, "contract_material_wait": contract_material_wait}')
 # Initial F20 has further diagnostics after zero_stock_seconds in its return.
 s=s.replace('"zero_stock_seconds": zero_stock_seconds, "main_activity_seconds"', '"contract_activity": contract_activity, "retail_activity": retail_activity, "contract_material_wait": contract_material_wait, "zero_stock_seconds": zero_stock_seconds, "main_activity_seconds"')
 dest=out/(name+'.gd');assert not dest.exists();dest.write_text(s,encoding='utf-8')
 manifest[name]={'source':str(p.relative_to(r)),'source_hash':hashlib.sha256(p.read_bytes()).hexdigest(),'instrumented_hash':hashlib.sha256(dest.read_bytes()).hexdigest(),'changes':'only integrate occupation and idle material wait; no scheduling/economy/state changes'}
(out/'instrumentation.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
