#!/usr/bin/env python3
"""Builds assets/data/food_knowledge.json from concepts.py and USDA
FoodData Central SR Legacy (public domain, CC0 1.0).

Usage:
  python3 tool/food_knowledge/build.py <path to the unzipped SR Legacy CSV folder>

Download the CSV archive from https://fdc.nal.usda.gov/download-datasets
("SR Legacy", April 2018). The output records, for every portion, the
fdc_id and modifier it comes from, so each weight can be checked.
"""
import csv
import json
import os
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(__file__))
from concepts import CONCEPTS, PIECE_NAMES, U  # noqa: E402
from foods import FOODS, NUTRIENTS  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'data',
                   'food_knowledge.json')


def fold(s):
    s = unicodedata.normalize('NFD', s.lower())
    return ''.join(c for c in s if unicodedata.category(c) != 'Mn').strip()


def main(sr_dir):
    portions = {}
    with open(os.path.join(sr_dir, 'food_portion.csv'), newline='') as f:
        for row in csv.DictReader(f):
            portions.setdefault(row['fdc_id'], []).append(row)
    descriptions = {}
    with open(os.path.join(sr_dir, 'food.csv'), newline='') as f:
        for row in csv.DictReader(f):
            descriptions[row['fdc_id']] = row['description']

    concepts = []
    for cid, es, en, plist, tags in CONCEPTS:
        out_portions = []
        for p in plist:
            if p['fdc'] is None:
                grams = p['grams']
                source = {'kind': 'estimate'}
            else:
                rows = [r for r in portions.get(str(p['fdc']), [])
                        if r['modifier'] == p['modifier']]
                if not rows:
                    raise SystemExit(f"{cid}: no portion '{p['modifier']}' "
                                     f"for fdc {p['fdc']}")
                row = rows[0]
                amount = float(row['amount'] or 1) or 1
                grams = float(row['gram_weight']) / amount * p['factor']
                source = {
                    'kind': 'usda_sr_legacy',
                    'fdc_id': p['fdc'],
                    'food': descriptions.get(str(p['fdc'])),
                    'portion': row['modifier'],
                    'factor': p['factor'],
                }
            es1, es2, en1, en2 = (
                PIECE_NAMES[cid]
                if p['unit'] == 'unit' and cid in PIECE_NAMES
                else U[p['unit']]
            )
            out_portions.append({
                'unit': p['unit'],
                'es': [es1, es2],
                'en': [en1, en2],
                'grams': round(grams, 1),
                'default': p['default'],
                'source': source,
            })
        concepts.append({
            'id': cid,
            'names': {
                'es': sorted({fold(n) for n in es}, key=len, reverse=True),
                'en': sorted({fold(n) for n in en}, key=len, reverse=True),
            },
            'tags': tags,
            'portions': out_portions,
        })
    wanted = {str(f[2]) for f in FOODS}
    values = {}
    with open(os.path.join(sr_dir, 'food_nutrient.csv'), newline='') as f:
        for row in csv.DictReader(f):
            if row['fdc_id'] not in wanted:
                continue
            key = NUTRIENTS.get(int(row['nutrient_id']))
            if key is None or row['amount'] == '':
                continue
            values.setdefault(row['fdc_id'], {})[key] = float(row['amount'])
    concept_ids = {c['id'] for c in concepts}
    foods = []
    for fid, concept, fdc, es, en, extra in FOODS:
        if concept not in concept_ids:
            raise SystemExit(f'{fid}: unknown concept {concept}')
        n = dict(values.get(str(fdc), {}))
        for key in ('kcal', 'carbs', 'protein', 'fat'):
            if key not in n:
                raise SystemExit(f'{fid}: fdc {fdc} has no {key}')
        # Plant omega-3: prefer the c,c,c 18:3 n-3 value; fall back to the
        # undifferentiated 18:3 total.
        # USDA carbohydrate is "by difference" and includes fibre; European
        # labels, which the points follow, give available carbohydrate.
        if 'fibre' in n:
            n['carbs'] = max(0.0, n['carbs'] - n['fibre'])
        if 'ala18_3G' in n:
            n.setdefault('alaG', n['ala18_3G'])
            del n['ala18_3G']
        foods.append({
            'id': fid,
            'concept': concept,
            'names': {'es': es, 'en': en},
            'tags': extra,
            'per100': {k: round(v, 3) for k, v in sorted(n.items())},
            'source': {'kind': 'usda_sr_legacy', 'fdc_id': fdc,
                       'food': descriptions.get(str(fdc))},
        })

    doc = {
        'format': 'eatpoint-food-knowledge',
        'version': 2,
        'sources': {
            'usda_sr_legacy': 'USDA FoodData Central, SR Legacy (April 2018), '
                              'public domain (CC0 1.0), '
                              'https://fdc.nal.usda.gov',
            'estimate': 'Typical European pack or household size, '
                        'rounded; not a measured value.',
        },
        'concepts': concepts,
        'foods': foods,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'{len(concepts)} concepts, '
          f'{sum(len(c["portions"]) for c in concepts)} portions, '
          f'{len(foods)} foods -> {OUT}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
