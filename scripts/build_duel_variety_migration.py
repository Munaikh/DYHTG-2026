"""Package verified Swift-authored questions into an additive database migration.
Run only while authoring an UNDEPLOYED migration; never rewrite a deployed migration.
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parts = [(root / 'scripts/duel-variety/schema.sql').read_text()]
for source in sorted((root / 'content/duel/v2/server').glob('*.json')):
    for document in json.loads(source.read_text()):
        text = json.dumps(document, separators=(',', ':'), ensure_ascii=False).replace("'", "''")
        parts.append("insert into private.duel_content(id,algorithm,slot,document) values "
                     f"('{document['id']}','{document['algorithm']}',{document['slot']},'{text}'::jsonb);\n")
parts.append((root / 'scripts/duel-variety/functions.sql').read_text())
parts.append("notify pgrst, 'reload schema';\n")
(root / 'supabase/migrations/20261017220000_duel_variety.sql').write_text('\n'.join(parts))
print('Packaged 120 verified questions and five-algorithm duel rules.')
