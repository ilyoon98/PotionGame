import json,sys
from pathlib import Path
from render_expedition_cards import render_commands
r=Path(__file__).resolve().parents[1]/(sys.argv[1] if len(sys.argv)>1 else '.verification/f20-20261020/ui')
d=json.loads((r/'management.json').read_text(encoding='utf-8'))
for c in d['cases']:
 render_commands(c['size'],c['commands']).save(r/(c['id']+'.png'))
print('Rendered',len(d['cases']),'actual Control/TextServer previews')
