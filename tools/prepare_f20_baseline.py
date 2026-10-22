from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
dest=root/'.verification/f20-20261020/baseline'
assert not dest.exists(), 'Never overwrite baseline evidence'
files={}
for folder in ('scripts','data'):
    for src in (root/folder).rglob('*'):
        if not src.is_file(): continue
        rel=src.relative_to(root)
        target=dest/rel
        target.parent.mkdir(parents=True,exist_ok=True)
        raw=src.read_bytes()
        files[str(rel)]=hashlib.sha256(raw).hexdigest()
        if src.suffix=='.gd':
            raw=raw.decode('utf-8-sig').replace('res://scripts/','res://.verification/f20-20261020/baseline/scripts/').replace('res://data/','res://.verification/f20-20261020/baseline/data/').encode()
        target.write_bytes(raw)
(dest/'source-hashes.json').write_text(json.dumps(files,indent=2),encoding='utf-8')
print('F20 v11 baseline frozen',len(files))
