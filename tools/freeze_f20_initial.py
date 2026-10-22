from pathlib import Path
import json,hashlib
r=Path(__file__).resolve().parents[1]; out=r/'.verification/f20-20261020/initial-model'
assert not out.exists()
hashes={}
for folder in ('scripts','data','tests'):
 for p in (r/folder).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(r); q=out/rel; q.parent.mkdir(parents=True,exist_ok=True)
  b=p.read_bytes(); hashes[str(rel)]=hashlib.sha256(b).hexdigest()
  if p.suffix=='.gd':
   s=b.decode('utf-8-sig')
   for f in ('scripts','data','tests'):s=s.replace('res://'+f+'/', 'res://.verification/f20-20261020/initial-model/'+f+'/')
   b=s.encode()
  q.write_bytes(b)
(out/'source-hashes.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
p=r/'tools/measure_f20.gd'; s=p.read_text(encoding='utf-8')
(out/'measurement-before-freeze.gd').write_text(s,encoding='utf-8')
for f in ('scripts','tests'):s=s.replace('res://'+f+'/', 'res://.verification/f20-20261020/initial-model/'+f+'/')
s=s.replace('## Actual production advancement;', '## Frozen initial F20 production advancement;')
p.write_text(s,encoding='utf-8')
print('Initial F20 production/fixtures frozen; remaining initial measurements use this exact model')
