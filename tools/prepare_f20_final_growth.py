from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]; base=r/'.verification/f20-20261020'; dest=base/'protected-final-model'
assert not dest.exists()
hashes={}
for folder in ('scripts','data','tests'):
 for p in (r/folder).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(r); q=dest/rel;q.parent.mkdir(parents=True,exist_ok=True)
  b=p.read_bytes();hashes[str(rel)]=hashlib.sha256(b).hexdigest()
  if p.suffix=='.gd':
   s=b.decode('utf-8-sig')
   for f in ('scripts','data','tests'):s=s.replace('res://'+f+'/', 'res://.verification/f20-20261020/protected-final-model/'+f+'/')
   b=s.encode()
  q.write_bytes(b)
(dest/'source-hashes.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
s=(base/'initial-model/measurement-before-freeze.gd').read_text(encoding='utf-8')
for f in ('scripts','tests'):s=s.replace('res://'+f+'/', 'res://.verification/f20-20261020/protected-final-model/'+f+'/')
s=s.replace('const ROOT := "res://.verification/f20-20261020"', 'const ROOT := "res://.verification/f20-20261020/protected-final"')
(r/'tools/measure_f20_final.gd').write_text(s,encoding='utf-8')
print('Final unpurchased-regression model frozen. Candidate recovery policy still NOT adopted.')
