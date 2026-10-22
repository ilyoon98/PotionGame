from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]; base=r/'.verification/f20-20261020'; out=base/'payment-fixed-model'
assert not out.exists()
hashes={}
for folder in ('scripts','data','tests'):
 for p in (r/folder).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(r); q=out/rel;q.parent.mkdir(parents=True,exist_ok=True)
  raw=p.read_bytes();hashes[str(rel)]=hashlib.sha256(raw).hexdigest()
  if p.suffix=='.gd':
   s=raw.decode('utf-8-sig')
   for f in ('scripts','data','tests'):s=s.replace('res://'+f+'/', 'res://.verification/f20-20261020/payment-fixed-model/'+f+'/')
   raw=s.encode()
  q.write_bytes(raw)
(out/'source-hashes.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
s=(base/'initial-model/measurement-before-freeze.gd').read_text(encoding='utf-8')
for f in ('scripts','tests'):s=s.replace('res://'+f+'/', 'res://.verification/f20-20261020/payment-fixed-model/'+f+'/')
s=s.replace('const ROOT := "res://.verification/f20-20261020"','const ROOT := "res://.verification/f20-20261020/payment-fixed"')
(r/'tools/measure_f20_payment.gd').write_text(s,encoding='utf-8')
print('Frozen current payment boundary model for actual returning-case replay')
