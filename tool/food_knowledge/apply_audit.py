"""Applies portion_audit.json to assets/data/food_knowledge.json.

build.py runs it after writing the catalogue; it can also be run on its own:
    python3 tool/food_knowledge/apply_audit.py
It is idempotent: running it twice gives the same file.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ASSET = os.path.join(ROOT, 'assets', 'data', 'food_knowledge.json')
AUDIT = os.path.join(HERE, 'portion_audit.json')


def apply(doc, audit):
    concepts = {c['id']: c for c in doc['concepts']}
    for fix in audit.get('portions', []):
        c = concepts[fix['concept']]
        for p in c.get('portions', []):
            if p['unit'] != fix['unit']:
                continue
            p['grams'] = fix['grams']
            if 'es' in fix:
                p['es'] = fix['es']
            if 'en' in fix:
                p['en'] = fix['en']
            p['source'] = {'kind': 'audit', 'note': fix.get('note', '')}
    for rm in audit.get('remove_portions', []):
        c = concepts[rm['concept']]
        c['portions'] = [p for p in c.get('portions', [])
                         if p['unit'] != rm['unit']]
    for cid, change in audit.get('names', {}).items():
        names = concepts[cid]['names']
        for lang in ('es', 'en'):
            names[lang] = [n for n in names.get(lang, [])
                           if n not in change.get('remove', [])]
            for n in change.get(f'add_{lang}', []):
                if n not in names[lang]:
                    names[lang].append(n)
    for cid, words in audit.get('exclude', {}).items():
        concepts[cid]['exclude'] = sorted(set(words))
    group = audit.get('exclude_groups', {})
    for cid in group.get('concepts', []):
        concepts[cid]['exclude'] = sorted(
            set(concepts[cid].get('exclude', [])) | set(group['words']))
    for new in audit.get('new', []):
        concept = {k: v for k, v in new.items()}
        for p in concept.get('portions', []):
            p.setdefault('source', {'kind': 'audit'})
        if new['id'] in concepts:
            concepts[new['id']].update(concept)
        else:
            doc['concepts'].append(concept)
            concepts[new['id']] = concept
    return doc


def main():
    with open(ASSET, encoding='utf-8') as f:
        doc = json.load(f)
    with open(AUDIT, encoding='utf-8') as f:
        audit = json.load(f)
    apply(doc, audit)
    with open(ASSET, 'w', encoding='utf-8') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'{len(doc["concepts"])} concepts after the audit -> {ASSET}')


if __name__ == '__main__':
    main()
