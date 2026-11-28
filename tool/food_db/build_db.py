"""Builds EatPoint's downloadable food database.

Sources, each credited in the database's manifest:
  * EatPoint's own list (tool/food_db/eatpoint_list.json): everyday Spanish
    foods with their macronutrients per 100 g.
  * USDA FoodData Central, SR Legacy (public domain, CC0 1.0): a curated
    set of basic foods, with Spanish names from usda_es.py.
  * Open Food Facts (Open Database License, ODbL 1.0): popular supermarket
    products sold in Spain, collected by off_es.py.

All values are per 100 g (or 100 ml): energy in kcal; carbohydrates are
the available ones (without fibre), as on European labels.

Usage:
  python3 tool/food_db/build_db.py <USDA SR Legacy CSV dir> [OFF dir]
Writes data/food_db/eatpoint-foods-v<N>.json.gz and data/food_db/manifest.json.
"""

import csv
import datetime
import gzip
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, "data", "food_db")
VERSION = 2

sys.path.insert(0, HERE)
try:
    import usda_es  # noqa: E402
except Exception:  # noqa: BLE001 - names stay English only
    usda_es = None

SOURCES = [
    {
        "id": "eatpoint",
        "name": "EatPoint",
        "license": "GPL-3.0",
        "url": "https://github.com/Grohle/EatPoint",
    },
    {
        "id": "usda",
        "name": "USDA FoodData Central (SR Legacy)",
        "license": "CC0 1.0 (public domain)",
        "url": "https://fdc.nal.usda.gov/",
    },
    {
        "id": "off",
        "name": "Open Food Facts",
        "license": "Open Database License (ODbL) 1.0",
        "url": "https://world.openfoodfacts.org/",
    },
]

# USDA nutrient ids.
KCAL, PROTEIN, FAT, CARBS, FIBRE, SUGARS, SATFAT, SODIUM = (
    1008, 1003, 1004, 1005, 1079, 2000, 1258, 1093)

EXCLUDED_CATEGORIES = {
    "Baby Foods", "American Indian/Alaska Native Foods", "Restaurant Foods",
    "Fast Foods",
}
EXCLUDED_WORDS = re.compile(
    r"separable lean and fat|trimmed to 1/8|trimmed to 1/4|new zealand|"
    r"australian|imported|infant formula|mead johnson|gerber|beech-nut|"
    r"lip-on|composite of trimmed retail cuts|all grades|choice|select|prime|"
    r"with added solution|by-products|usda commodity|school lunch|ns as to|"
    r"industrial|nfs|mixed species|game meat|alaska")

# US brands and chains: not useful for an EatPoint user in Spain.
BRANDS = re.compile(
    r"\b(pillsbury|kraft|george weston|kellogg'?s?|general mills|quaker|"
    r"nabisco|campbell'?s?|hormel|oscar mayer|kentucky fried|mcdonald'?s|"
    r"burger king|taco bell|wendy'?s|subway|domino'?s|pizza hut|"
    r"little caesars|papa john'?s|heinz|hershey'?s?|keebler|pepperidge farm|"
    r"sara lee|ocean spray|tropicana|minute maid|lipton|arnold|martha white|"
    r"betty crocker|duncan hines|jell-o|lay'?s|frito|tostitos|doritos|"
    r"cheetos|snickers|reese'?s|m&m'?s|nestle|ovaltine|carnation|gatorade|"
    r"powerade|coca-cola|pepsi|dr\. pepper|mountain dew|sunkist|"
    r"oreo|ritz|triscuit|wheat thins|goldfish|pringles|smucker'?s|"
    r"post|ralston|malt-o-meal|cheerios|wheaties|thomas'?|eggo|"
    r"stouffer'?s|banquet|swanson|lean cuisine|healthy choice|"
    r"shake n bake|rice-a-roni|hamburger helper|kool-aid|tang|"
    r"cracker barrel|denny'?s|applebee'?s|olive garden|chick-fil-a|"
    r"popeyes|arby'?s|dairy queen|carl'?s jr|jack in the box|sonic|"
    r"starbucks|dunkin|krispy kreme|hostess|little debbie|entenmann'?s|"
    r"kashi|special k|fiber one|nature valley|clif|luna|kind|"
    r"silk|so delicious|morningstar|boca|gardenburger|worthington|"
    r"van'?s|kemps|dannon|yoplait|chobani|stonyfield|breyers|"
    r"ben & jerry'?s|haagen-dazs|dreyer'?s|blue bell|turkey hill)\b")

CATEGORY_ES = {
    "Vegetables and Vegetable Products": "Verduras",
    "Baked Products": "Panadería y bollería",
    "Poultry Products": "Aves",
    "Fruits and Fruit Juices": "Frutas y zumos",
    "Beverages": "Bebidas",
    "Dairy and Egg Products": "Lácteos y huevos",
    "Sweets": "Dulces",
    "Legumes and Legume Products": "Legumbres",
    "Soups, Sauces, and Gravies": "Sopas y salsas",
    "Finfish and Shellfish Products": "Pescado y marisco",
    "Fats and Oils": "Grasas y aceites",
    "Sausages and Luncheon Meats": "Embutidos y fiambres",
    "Pork Products": "Cerdo",
    "Cereal Grains and Pasta": "Cereales y pasta",
    "Snacks": "Aperitivos",
    "Nut and Seed Products": "Frutos secos y semillas",
    "Meals, Entrees, and Side Dishes": "Platos preparados",
    "Spices and Herbs": "Especias y hierbas",
    "Beef Products": "Vacuno",
    "Lamb, Veal, and Game Products": "Cordero y ternera",
    "Breakfast Cereals": "Cereales de desayuno",
}

OFF_ALLERGENS = {
    "en:gluten": "gluten", "en:milk": "milk", "en:eggs": "egg",
    "en:fish": "fish", "en:crustaceans": "crustacean",
    "en:molluscs": "mollusc", "en:peanuts": "peanut", "en:nuts": "treeNut",
    "en:soybeans": "soy", "en:sesame-seeds": "sesame", "en:celery": "celery",
    "en:mustard": "mustard", "en:sulphur-dioxide-and-sulphites": "sulphites",
    "en:lupin": "lupin",
}
OFF_LABELS = {
    "en:vegan": "vegan", "en:vegetarian": "vegetarian",
    "en:gluten-free": "glutenFree", "en:no-gluten": "glutenFree",
    "en:lactose-free": "lactoseFree", "en:no-lactose": "lactoseFree",
    "en:halal": "halal", "en:kosher": "kosher",
}


def r1(v):
    return None if v is None else round(float(v), 1)


def food(i, src, es, en, kcal, carbs, protein, fat, **extra):
    row = {"i": i, "s": src, "es": es, "en": en, "k": round(kcal),
           "c": r1(carbs), "p": r1(protein), "f": r1(fat)}
    for key, value in extra.items():
        if value not in (None, [], "", 0) or key == "fi" and value == 0:
            row[key] = r1(value) if isinstance(value, float) else value
    return row


def plausible(kcal, carbs, protein, fat):
    if kcal is None or kcal < 0 or kcal > 950:
        return False
    if any(v is None or v < 0 or v > 100 for v in (carbs, protein, fat)):
        return False
    if carbs + protein + fat > 101:
        return False
    # The energy should roughly match the macros (alcohol and polyols aside).
    est = carbs * 4 + protein * 4 + fat * 9
    return est == 0 or abs(est - kcal) <= max(40, 0.35 * kcal)


def eatpoint_list():
    rows = []
    for n, item in enumerate(json.load(open(os.path.join(HERE, "eatpoint_list.json")))):
        rows.append(food(f"e:{n}", "eatpoint", item["name"], None,
                         item["kcal"], item["carbs"], item["protein"],
                         item["fat"], l=1 if item.get("liquid") else None))
    return rows


def usda(sr_dir):
    def read(name):
        return csv.DictReader(open(os.path.join(sr_dir, name), encoding="utf-8"))

    cats = {r["id"]: r["description"] for r in read("food_category.csv")}
    keep = {}
    for r in read("food.csv"):
        cat = cats.get(r["food_category_id"], "")
        desc = r["description"]
        if cat in EXCLUDED_CATEGORIES or EXCLUDED_WORDS.search(desc.lower()):
            continue
        if re.search(r"\b[A-Z]{3,}\b", desc):  # brand names in capitals
            continue
        if BRANDS.search(desc.lower()):
            continue
        keep[r["fdc_id"]] = (desc, cat)
    values = {}
    wanted = {KCAL, PROTEIN, FAT, CARBS, FIBRE, SUGARS, SATFAT, SODIUM}
    for r in read("food_nutrient.csv"):
        if r["fdc_id"] in keep and int(r["nutrient_id"]) in wanted:
            values.setdefault(r["fdc_id"], {})[int(r["nutrient_id"])] = float(r["amount"])
    serving = {}
    for r in read("food_portion.csv"):
        fid = r["fdc_id"]
        if fid in keep and fid not in serving:
            try:
                grams = float(r["gram_weight"])
            except ValueError:
                continue
            if 0 < grams <= 1000:
                serving[fid] = grams
    rows = []
    for fid, (desc, cat) in keep.items():
        v = values.get(fid, {})
        kcal, protein, fat = v.get(KCAL), v.get(PROTEIN), v.get(FAT)
        fibre = v.get(FIBRE, 0.0)
        carbs = v.get(CARBS)
        if carbs is not None:
            carbs = max(0.0, carbs - fibre)
        if not plausible(kcal, carbs, protein, fat):
            continue
        es = usda_es.translate(desc) if usda_es else None
        sodium = v.get(SODIUM)
        rows.append(food(
            f"u:{fid}", "usda", es, desc, kcal, carbs, protein, fat,
            fi=fibre, su=v.get(SUGARS), sf=v.get(SATFAT),
            sa=None if sodium is None else sodium * 2.5 / 1000,
            sv=serving.get(fid), cat=CATEGORY_ES.get(cat),
            l=1 if cat == "Beverages" else None))
    return rows


def open_food_facts(off_dir):
    if not off_dir:
        return []
    path = os.path.join(off_dir, "off_products.jsonl")
    if not os.path.exists(path):
        return []
    rows = []
    for line in open(path):
        rec = json.loads(line)
        p = rec.get("product")
        if not p:
            continue
        name = (p.get("product_name_es") or "").strip()
        n = p.get("nutriments") or {}
        kcal = n.get("energy-kcal_100g")
        carbs, protein, fat = (n.get("carbohydrates_100g"),
                               n.get("proteins_100g"), n.get("fat_100g"))
        try:
            kcal, carbs, protein, fat = (float(x) for x in (kcal, carbs, protein, fat))
        except (TypeError, ValueError):
            continue
        if not name or not plausible(kcal, carbs, protein, fat):
            continue
        brands = p.get("brands") or ""
        brand = brands.split(",")[0].strip() if isinstance(brands, str) else None
        def num(key):
            try:
                return float(n.get(key))
            except (TypeError, ValueError):
                return None
        serving = p.get("serving_quantity")
        try:
            serving = float(serving) if serving else None
        except (TypeError, ValueError):
            serving = None
        liquid = (p.get("serving_quantity_unit") or "").lower() == "ml"
        rows.append(food(
            f"o:{rec['code']}", "off", name, None, kcal, carbs, protein, fat,
            b=brand or None, fi=num("fiber_100g"), su=num("sugars_100g"),
            sf=num("saturated-fat_100g"), sa=num("salt_100g"),
            sv=serving if serving and 0 < serving <= 1000 else None,
            l=1 if liquid else None,
            a=sorted({OFF_ALLERGENS[t] for t in p.get("allergens_tags") or [] if t in OFF_ALLERGENS}),
            t=sorted({OFF_ALLERGENS[t] for t in p.get("traces_tags") or [] if t in OFF_ALLERGENS}),
            lb=sorted({OFF_LABELS[t] for t in (p.get("labels_tags") or []) + (p.get("ingredients_analysis_tags") or []) if t in OFF_LABELS}),
        ))
    return rows


def main():
    sr_dir = sys.argv[1]
    off_dir = sys.argv[2] if len(sys.argv) > 2 else None
    foods = eatpoint_list() + usda(sr_dir) + open_food_facts(off_dir)
    # Each food's own household unit, reviewed by name (apply_portions.py).
    from apply_portions import with_units
    with_units(foods)
    counts = {}
    for f in foods:
        counts[f["s"]] = counts.get(f["s"], 0) + 1
    payload = {
        "format": "eatpoint-foods",
        "version": VERSION,
        "generated": datetime.date.today().isoformat(),
        "sources": SOURCES,
        "foods": foods,
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    name = f"eatpoint-foods-v{VERSION}.json.gz"
    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
    data = gzip.compress(raw, compresslevel=9, mtime=0)
    open(os.path.join(OUT_DIR, name), "wb").write(data)
    manifest = {
        "format": "eatpoint-foods-manifest",
        "version": VERSION,
        "file": name,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "count": len(foods),
        "counts": counts,
        "generated": payload["generated"],
        "sources": SOURCES,
    }
    json.dump(manifest, open(os.path.join(OUT_DIR, "manifest.json"), "w"),
              ensure_ascii=False, indent=2)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
