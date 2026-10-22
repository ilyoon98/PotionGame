from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]; out=r/'.verification/f20-20261020/A/source'
assert not out.exists()
hashes={}
for folder in ('scripts','data'):
 for p in (r/folder).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(r); q=out/rel; q.parent.mkdir(parents=True,exist_ok=True)
  b=p.read_bytes(); hashes[str(rel)]=hashlib.sha256(b).hexdigest()
  if p.suffix=='.gd': b=b.decode('utf-8-sig').replace('res://scripts/','res://.verification/f20-20261020/A/source/scripts/').replace('res://data/','res://.verification/f20-20261020/A/source/data/').encode()
  q.write_bytes(b)
(out/'source-hashes.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
base=r/'.verification/f20-20261020/baseline/scripts/shop_state.gd'
s=base.read_text(encoding='utf-8')
s=s.replace('var empty_sale_attempts := 0','var empty_sale_attempts := 0\n\tvar zero_stock_seconds := 0.0')
s=s.replace('full_seconds += step if stock >= capacity() else 0.0','full_seconds += step if stock >= capacity() else 0.0\n\t\tzero_stock_seconds += step if stock == 0 else 0.0')
s=s.replace('"empty_sale_attempts": empty_sale_attempts}', '"empty_sale_attempts": empty_sale_attempts, "zero_stock_seconds": zero_stock_seconds}')
target=r/'.verification/f20-20261020/baseline/metrics_state.gd'; target.write_text(s,encoding='utf-8')
(target.parent/'instrumentation.json').write_text(json.dumps({'original':hashlib.sha256(base.read_bytes()).hexdigest(),'metrics':hashlib.sha256(target.read_bytes()).hexdigest(),'changes':'only accumulate and return zero-stock seconds; no simulation decisions changed'},indent=2),encoding='utf-8')
print('A source frozen; baseline measurement-only instrumentation created')
