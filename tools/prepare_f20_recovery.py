"""Freeze the user-approved recovery model without replacing previous evidence."""
from pathlib import Path
import hashlib
import json

r = Path(__file__).resolve().parents[1]
root = r / '.verification/f20-recovery-20261020'
model = root / 'model'
assert not model.exists(), 'Keep completed measurements immutable'
hashes = {}
for folder in ('scripts', 'data', 'tests'):
    for p in (r / folder).rglob('*'):
        if not p.is_file():
            continue
        rel = p.relative_to(r)
        q = model / rel
        q.parent.mkdir(parents=True, exist_ok=True)
        raw = p.read_bytes()
        hashes[rel.as_posix()] = hashlib.sha256(raw).hexdigest()
        if p.suffix == '.gd':
            s = raw.decode('utf-8-sig')
            for f in ('scripts', 'data', 'tests'):
                s = s.replace('res://' + f + '/', 'res://.verification/f20-recovery-20261020/model/' + f + '/')
            raw = s.encode()
        q.write_bytes(raw)
(model / 'source-hashes.json').write_text(json.dumps(hashes, indent=2), encoding='utf-8')
s = (r / '.verification/f20-20261020/initial-model/measurement-before-freeze.gd').read_text(encoding='utf-8')
for f in ('scripts', 'tests'):
    s = s.replace('res://' + f + '/', 'res://.verification/f20-recovery-20261020/model/' + f + '/')
s = s.replace('const ROOT := "res://.verification/f20-20261020"', 'const ROOT := "res://.verification/f20-recovery-20261020"')
s = s.replace('for stage in range(1, 4):', 'for stage in range(0, 4):')
(r / 'tools/measure_f20_recovery.gd').write_text(s, encoding='utf-8')
checks = root / 'checks'
checks.mkdir()
for name in ('protection', 'workshop', 'migration', 'ui', 'edges', 'payment_boundary'):
    s = (r / f'tools/verify_f20_{name}.gd').read_text(encoding='utf-8')
    s = s.replace('res://.verification/f20-20261020/A/', 'res://.verification/f20-recovery-20261020/checks/protection-')
    s = s.replace('res://.verification/f20-20261020/B/', 'res://.verification/f20-recovery-20261020/checks/' + name + '-')
    (checks / f'verify_{name}.gd').write_text(s, encoding='utf-8')
for original, target in [('tools/verify_stable_management_tabs.gd', 'stable_tabs.gd'), ('.verification/f20-20261020/B/f19-core-regression.gd', 'f19.gd')]:
    s = (r / original).read_text(encoding='utf-8').replace('f20-20261020', 'f20-recovery-20261020')
    (checks / target).write_text(s, encoding='utf-8')
print('Frozen approved recovery model, measurement harness and isolated check outputs')
