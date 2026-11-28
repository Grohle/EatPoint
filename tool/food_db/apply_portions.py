"""Gives each food of the database its own household unit, from
portion_review.json: a unit and its average weight ("u": {"g", "es", "en"}),
or "u": 0 when the food has no natural unit (drinks, sauces, flours, loose
foods). The app prefers this over the generic catalogue match.

build_db.py applies it to every build. Run on its own, it updates the
current database file in place of rebuilding it from the sources:
    python3 tool/food_db/apply_portions.py
"""
import gzip
import hashlib
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, 'data', 'food_db')
REVIEW = os.path.join(HERE, 'portion_review.json')


def with_units(foods):
    review = json.load(open(REVIEW, encoding='utf-8'))['foods']
    for f in foods:
        entry = review.get(f.get('es') or '')
        if entry is None:
            f.pop('u', None)
        elif entry.get('none'):
            f['u'] = 0
        else:
            f['u'] = {'g': entry['g'], 'es': entry['es'], 'en': entry['en']}
    return foods


def main():
    manifest_path = os.path.join(OUT_DIR, 'manifest.json')
    manifest = json.load(open(manifest_path, encoding='utf-8'))
    current = os.path.join(OUT_DIR, manifest['file'])
    payload = json.loads(gzip.decompress(open(current, 'rb').read()))
    with_units(payload['foods'])
    version = manifest['version'] + 1
    payload['version'] = version
    name = f'eatpoint-foods-v{version}.json.gz'
    raw = json.dumps(payload, ensure_ascii=False,
                     separators=(',', ':')).encode()
    data = gzip.compress(raw, compresslevel=9, mtime=0)
    open(os.path.join(OUT_DIR, name), 'wb').write(data)
    if name != manifest['file']:
        os.remove(current)
    manifest.update({
        'version': version,
        'file': name,
        'bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
    })
    json.dump(manifest, open(manifest_path, 'w', encoding='utf-8'),
              ensure_ascii=False, indent=2)
    with_unit = sum(1 for f in payload['foods'] if 'u' in f)
    print(f'{with_unit} of {len(payload["foods"])} foods carry their own '
          f'unit -> {name}')


if __name__ == '__main__':
    main()
