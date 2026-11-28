"""Updates the published food database in place, without the USDA and
Open Food Facts dumps that build_db.py needs:

  * EatPoint's own foods are read again from eatpoint_list.json (new ones
    are appended there, so the ids of the others stay);
  * Open Food Facts products collected by off_es.py into [OFF dir] are
    added when the database doesn't have them yet; with --plant-based,
    only products labelled vegan or plainly plant-based by their name;
  * every food's household unit is applied again (portion_review.json).

It writes the next version, eatpoint-foods-v<N+1>.json.gz, and updates
the manifest, like apply_portions.py.

    python3 tool/food_db/extend_db.py [OFF dir] [--plant-based]
"""
import datetime
import gzip
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import build_db  # noqa: E402
from apply_portions import OUT_DIR, with_units  # noqa: E402

PLANT_WORDS = re.compile(
    r"\b(vegan[oa]s?|vegetal(es)?|veggie|plant[- ]based|tofu|seit[aá]n|"
    r"tempeh|heura|falafel|hummus|soja|avena|almendras?|edamame|"
    r"altramuz|altramuces|garbanzos?|lentejas?)\b",
    re.IGNORECASE,
)
# Plant words that don't make a product plant-based on their own.
ANIMAL_WORDS = re.compile(
    r"\b(pollo|pavo|cerdo|ternera|jam[oó]n|at[uú]n|salm[oó]n|huevos?|"
    r"leche|queso|yogur|mantequilla|nata|miel|anchoas?|gambas?|bacon|"
    r"chorizo|lomo|carne)\b",
    re.IGNORECASE,
)


def plant_based(row):
    labels = row.get("lb") or []
    if "vegan" in labels:
        return True
    name = row.get("es") or ""
    if not PLANT_WORDS.search(name):
        return False
    # "Salmón vegano" is plant-based; "Pollo con soja" is not.
    if ANIMAL_WORDS.search(name) and not re.search(
        r"vegan|vegetal|veggie|plant", name, re.IGNORECASE
    ):
        return False
    allergens = set(row.get("a") or [])
    return not allergens & {"milk", "egg", "fish", "crustacean", "mollusc"}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    plant_only = "--plant-based" in sys.argv
    manifest_path = os.path.join(OUT_DIR, "manifest.json")
    manifest = json.load(open(manifest_path, encoding="utf-8"))
    current = os.path.join(OUT_DIR, manifest["file"])
    payload = json.loads(gzip.decompress(open(current, "rb").read()))
    foods = [f for f in payload["foods"] if f.get("s") != "eatpoint"]
    foods = build_db.eatpoint_list() + foods
    added = 0
    if args:
        have = {f["i"] for f in foods}
        names = {(f.get("es") or "").lower() for f in foods}
        for row in build_db.open_food_facts(args[0]):
            name = (row.get("es") or "").lower()
            if row["i"] in have or name in names:
                continue
            if plant_only and not plant_based(row):
                continue
            foods.append(row)
            have.add(row["i"])
            names.add(name)
            added += 1
    with_units(foods)
    version = manifest["version"] + 1
    today = datetime.date.today().isoformat()
    payload.update({"version": version, "foods": foods, "generated": today})
    name = f"eatpoint-foods-v{version}.json.gz"
    raw = json.dumps(payload, ensure_ascii=False,
                     separators=(",", ":")).encode()
    data = gzip.compress(raw, compresslevel=9, mtime=0)
    open(os.path.join(OUT_DIR, name), "wb").write(data)
    if name != manifest["file"]:
        os.remove(current)
    counts = {}
    for f in foods:
        counts[f["s"]] = counts.get(f["s"], 0) + 1
    manifest.update({
        "version": version,
        "file": name,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "count": len(foods),
        "counts": counts,
        "generated": today,
    })
    json.dump(manifest, open(manifest_path, "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print(f"{len(foods)} foods ({added} new from Open Food Facts) -> {name}")


if __name__ == "__main__":
    main()
