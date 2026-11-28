"""Step 3 of the portion pipeline: checks the agents' answers and folds them
into the database's per-food units (tool/food_db/portion_review.json).

Rules:
  * a weight needs a source (a URL, or the pack in the product name), or it
    is left out and listed as doubtful;
  * a change of more than 50 % from the current weight with only medium or
    low confidence is listed as doubtful, not applied;
  * "none" removes the unit, except for household measures (glass, cup,
    spoon, can, jar, yogurt pot), which stay.
Doubtful groups go to <run>/doubtful.json for a person to decide. Their
decisions live in tool/food_portions/decisions.json and come first:
"accept" applies the answer anyway, "reject" keeps the current weight,
"none" removes the unit, and {"grams", "unit_es", "unit_en"} sets it by hand.

    python3 tool/food_portions/merge.py run_dir
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REVIEW = os.path.join(os.path.dirname(HERE), 'food_db', 'portion_review.json')
DECISIONS = os.path.join(HERE, 'decisions.json')
MEASURES = {'vaso', 'taza', 'cucharada', 'cucharadita', 'lata', 'bote',
            'yogur'}


def main(run):
    groups = {g['id']: g for g in json.load(open(os.path.join(run, 'groups.json')))}
    answers = {}
    for path in sorted(glob.glob(os.path.join(run, 'answers_*.json'))):
        for a in json.load(open(path, encoding='utf-8')):
            if isinstance(a, dict) and a.get('id') in groups:
                answers[a['id']] = a
    decisions = {}
    if os.path.exists(DECISIONS):
        decisions = json.load(open(DECISIONS, encoding='utf-8'))['groups']
    review = json.load(open(REVIEW, encoding='utf-8'))
    foods = review['foods']
    doubtful, applied, missing = [], 0, 0
    for gid, g in groups.items():
        a = answers.get(gid)
        if a is None:
            missing += 1
            continue
        decision = decisions.get(gid)
        if decision == 'reject':
            continue
        if decision == 'none':
            a = {**a, 'verdict': 'none'}
        elif isinstance(decision, dict):
            a = {**a, 'verdict': 'fix', 'confidence': 'high',
                 'sources': a.get('sources') or ['reviewed by hand'],
                 **decision}
        elif decision == 'accept':
            a = {**a, 'confidence': 'high',
                 'sources': a.get('sources') or ['reviewed by hand']}
        verdict = a.get('verdict')
        if verdict == 'ok':
            continue
        if verdict == 'none':
            if g['unit_es'] in MEASURES and decision != 'none':
                continue
            for f in g['foods']:
                if f['name_es']:
                    foods[f['name_es']] = {'none': True}
            applied += 1
            continue
        grams = a.get('grams')
        sources = a.get('sources') or []
        unit_es = a.get('unit_es') or [g['unit_es'], g['unit_es']]
        unit_en = a.get('unit_en') or unit_es
        big = (isinstance(grams, (int, float)) and g['current_grams'] > 0 and
               abs(grams - g['current_grams']) / g['current_grams'] > 0.5)
        if (not isinstance(grams, (int, float)) or not 0.5 <= grams <= 2000
                or not sources
                or (big and a.get('confidence') != 'high')):
            doubtful.append({**a, 'unit_now': g['unit_es'],
                             'current_grams': g['current_grams'],
                             'examples': [f['name_es'] for f in g['foods'][:5]]})
            continue
        for f in g['foods']:
            if f['name_es'] and not f['code'].startswith('concept:'):
                foods[f['name_es']] = {'g': round(float(grams), 1),
                                       'es': unit_es[:2], 'en': unit_en[:2],
                                       'src': sources[:2]}
        applied += 1
    review['foods'] = dict(sorted(foods.items()))
    json.dump(review, open(REVIEW, 'w', encoding='utf-8'), ensure_ascii=False,
              indent=1)
    json.dump(doubtful, open(os.path.join(run, 'doubtful.json'), 'w'),
              ensure_ascii=False, indent=1)
    print(f'{applied} groups applied, {len(doubtful)} doubtful, '
          f'{missing} without an answer')


if __name__ == '__main__':
    main(sys.argv[1])
