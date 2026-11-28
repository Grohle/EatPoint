"""Step 1 of the portion pipeline: groups every food that shows a household
unit into research batches.

Foods are grouped by their unit and the first words of their Spanish name
("rebanada" + "pan integral"), so one sourced answer serves the whole group.

Input:  a TSV of the units the app shows (code, name_es, name_en, source,
        unit_es, grams), dumped by test/tool/dump_units_test.dart (see README.md).
Output: <out>/groups.json and <out>/batch_NN.json for the research agents.

    python3 tool/food_portions/prepare.py units.tsv out_dir [batch_size]
"""
import csv
import json
import os
import re
import sys
import unicodedata

STOP = {
    'de', 'del', 'la', 'el', 'los', 'las', 'con', 'sin', 'en', 'y', 'o', 'a',
    'al', 'para', 'tipo', 'estilo', 'crudo', 'cruda', 'crudos', 'crudas',
    'cocido', 'cocida', 'cocidos', 'cocidas', 'fresco', 'fresca', 'frescos',
    'frescas', 'congelado', 'congelada', 'congelados', 'natural', 'entero',
    'entera', 'enteros', 'enteras', 'bajo', 'baja', 'sal', 'azucar',
    'azucares', 'añadidos', 'anadidos', 'grasa', 'light', 'eco', 'bio',
    'ecologico', 'ecologica', 'mercadona', 'hacendado', 'carrefour', 'dia',
}


def fold(s):
    s = unicodedata.normalize('NFD', s.lower())
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9 ]+', ' ', s).strip()


def base(name):
    words = [w for w in fold(name).split() if w not in STOP and not w.isdigit()]
    return ' '.join(words[:2]) or fold(name)


def main(tsv, out_dir, batch_size=40):
    os.makedirs(out_dir, exist_ok=True)
    groups = {}
    with open(tsv, encoding='utf-8') as f:
        for row in csv.DictReader(f, delimiter='\t'):
            name = row['name_es'] or row['name_en']
            key = f"{fold(row['unit_es'])}|{base(name)}"
            g = groups.setdefault(key, {
                'key': key, 'unit_es': row['unit_es'], 'base': base(name),
                'current_grams': float(row['grams']), 'foods': [],
            })
            g['foods'].append({'code': row['code'], 'name_es': row['name_es'],
                               'name_en': row['name_en'],
                               'source': row['source'],
                               'grams': float(row['grams'])})
    ordered = sorted(groups.values(), key=lambda g: -len(g['foods']))
    for i, g in enumerate(ordered):
        g['id'] = f'g{i:04d}'
    json.dump(ordered, open(os.path.join(out_dir, 'groups.json'), 'w'),
              ensure_ascii=False, indent=1)
    batches = [ordered[i:i + batch_size]
               for i in range(0, len(ordered), batch_size)]
    for n, batch in enumerate(batches):
        slim = [{'id': g['id'], 'unit_es': g['unit_es'],
                 'current_grams': g['current_grams'],
                 'examples': [f['name_es'] or f['name_en']
                              for f in g['foods'][:5]],
                 'foods': len(g['foods'])} for g in batch]
        json.dump(slim, open(os.path.join(out_dir, f'batch_{n:02d}.json'), 'w'),
                  ensure_ascii=False, indent=1)
    print(f'{sum(len(g["foods"]) for g in ordered)} foods in {len(ordered)} '
          f'groups, {len(batches)} batches')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2],
         int(sys.argv[3]) if len(sys.argv) > 3 else 40)
