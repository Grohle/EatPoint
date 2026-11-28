"""Collects popular supermarket products sold in Spain from Open Food Facts
for EatPoint's downloadable food database.

Open Food Facts data is under the Open Database License (ODbL): the
database built from it says so and credits Open Food Facts.

Two steps, both resumable (results are cached in the output directory):
  1. Search for common grocery terms and keep products sold in Spain with a
     Spanish name (Search-a-licious, which returns names but not nutrition).
  2. Fetch each product's nutrition, allergens and labels from the v2
     product endpoint, politely throttled.

Usage: python3 tool/food_db/off_es.py <output dir> [max products] [terms]
  terms: "general" (the default, single words), "vegan" (plant-based
  products) or "world" (dishes and breads from other cuisines, sushi and
  ready meals), the last two searched by whole phrases.
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

UA = "EatPoint food database builder (github.com/Grohle/EatPoint)"
SEARCH = "https://search.openfoodfacts.org/search"
PRODUCT = "https://world.openfoodfacts.org/api/v2/product/{code}"
FIELDS = ",".join([
    "code", "product_name_es", "product_name", "brands", "quantity",
    "serving_quantity", "serving_quantity_unit", "nutriments",
    "allergens_tags", "traces_tags", "labels_tags",
    "ingredients_analysis_tags", "categories_tags", "countries_tags",
])

TERMS = """leche yogur queso mantequilla nata kefir bebida vegetal
pan pan de molde tostadas biscotes galletas cereales avena muesli
pasta macarrones espaguetis arroz quinoa cuscus harina
lentejas garbanzos alubias legumbres hummus
atun sardinas caballa salmon bonito mejillones anchoas surimi
jamon pavo pechuga de pollo chorizo salchichas fiambre lomo embutido
huevos tortilla gazpacho salmorejo crema de verduras sopa caldo
tomate frito pisto pimientos aceitunas encurtidos
aceite de oliva aceite de girasol mayonesa ketchup mostaza
chocolate cacao crema de cacao mermelada miel azucar edulcorante
zumo refresco agua con gas bebida isotonica cafe te infusion
patatas fritas snacks frutos secos almendras nueces cacahuetes
barrita proteica proteina whey batido de proteinas
helado postre natillas flan gelatina
pizza lasaña croquetas empanadillas nuggets hamburguesa
verduras congeladas ensalada guacamole tofu heura seitan
bolleria magdalenas croissant bizcocho
yogur griego queso fresco requeson skyr cuajada
tortitas de arroz tortitas de maiz palomitas""".split("\n")


# Plant-based products, searched as whole phrases.
VEGAN_TERMS = [
    "tofu", "tofu sedoso", "tofu ahumado", "tofu firme", "tofu marinado",
    "tofu albahaca", "tofu frito", "soja texturizada", "proteina de soja",
    "proteina de guisante", "seitan", "tempeh", "heura", "falafel", "hummus",
    "salmon vegano", "atun vegano", "gambas veganas", "pescado vegetal",
    "hamburguesa vegetal", "hamburguesa vegana", "burger vegana",
    "salchichas veganas", "salchicha vegetal", "nuggets veganos",
    "nuggets vegetales", "albondigas veganas", "albondigas vegetales",
    "carne picada vegetal", "picada vegetal", "pollo vegetal", "pollo vegano",
    "chorizo vegano", "chorizo vegetal", "embutido vegetal", "lonchas veganas",
    "fiambre vegano", "bacon vegano", "kebab vegano", "croquetas veganas",
    "queso vegano", "queso vegetal", "alternativa vegetal al queso",
    "yogur de soja", "yogur vegetal", "postre de soja", "yogur de coco",
    "bebida de avena", "bebida de almendra", "bebida de arroz",
    "bebida de soja", "bebida de coco", "nata vegetal", "nata de soja",
    "nata de avena", "mantequilla vegana", "margarina vegetal",
    "mayonesa vegana", "levadura nutricional", "edamame", "altramuces",
    "lentejas rojas", "pate vegetal", "untable vegetal", "helado vegano",
    "plant based", "vegano", "vegana", "veggie",
]


# Dishes and breads from other cuisines, sushi and ready meals.
WORLD_TERMS = [
    "arepa", "harina de maiz precocida", "tortilla de trigo", "tortillas de maiz",
    "wrap", "fajitas", "burrito", "tacos", "nachos", "quesadilla",
    "pan de pita", "naan", "pan bao", "sushi", "maki", "nigiri", "uramaki",
    "california roll", "sashimi", "arroz para sushi", "alga nori", "wakame",
    "gyoza", "dumplings", "rollitos de primavera", "noodles", "fideos de arroz",
    "ramen", "udon", "pad thai", "arroz tres delicias", "curry", "tikka masala",
    "kebab", "shawarma", "falafel", "cuscus", "tabule", "baba ganoush",
    "paella", "lentejas cocinadas", "fabada", "cocido", "pisto",
    "crema de verduras", "albondigas", "croquetas de jamon", "lasaña",
    "canelones", "empanada", "empanadillas", "ensalada preparada",
    "plato preparado", "poke", "ceviche", "salmon ahumado", "gulas",
]


def get(url, retries=4):
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001 - retry anything transient
            wait = 5 * (attempt + 1)
            print(f"  retry in {wait}s: {e}", file=sys.stderr)
            time.sleep(wait)
    return None


def collect(out_dir, limit, terms="general"):
    path = os.path.join(out_dir, "off_candidates.json")
    if os.path.exists(path):
        return json.load(open(path))
    found = {}
    words = ({"vegan": VEGAN_TERMS, "world": WORLD_TERMS}.get(terms) or
             [w for line in TERMS for w in line.split() if len(w) > 2])
    seen_q = set()
    for q in words:
        if q in seen_q:
            continue
        seen_q.add(q)
        for page in (1, 2):
            url = SEARCH + "?" + urllib.parse.urlencode({
                "q": q, "page": page, "page_size": 100, "langs": "es",
                "sort_by": "-popularity_key",
                "fields": "code,product_name_es,countries,popularity_key",
            })
            data = get(url)
            if not data:
                break
            for h in data.get("hits", []):
                raw = h.get("countries") or ""
                countries = (" ".join(raw) if isinstance(raw, list) else raw).lower()
                name = (h.get("product_name_es") or "").strip()
                if not name or not ("spain" in countries or "españa" in countries or "espagne" in countries):
                    continue
                code = h.get("code")
                if code and code not in found:
                    found[code] = h.get("popularity_key") or 0
            time.sleep(0.3)
        print(f"{q}: {len(found)} candidates", file=sys.stderr)
    ranked = sorted(found, key=lambda c: -found[c])[:limit]
    json.dump(ranked, open(path, "w"))
    return ranked


def fetch(out_dir, codes):
    path = os.path.join(out_dir, "off_products.jsonl")
    done = set()
    if os.path.exists(path):
        for line in open(path):
            try:
                done.add(json.loads(line)["code"])
            except Exception:  # noqa: BLE001
                pass
    with open(path, "a") as out:
        for i, code in enumerate(codes):
            if code in done:
                continue
            data = get(PRODUCT.format(code=code) + "?fields=" + FIELDS)
            product = (data or {}).get("product")
            out.write(json.dumps({"code": code, "product": product}) + "\n")
            out.flush()
            if i % 50 == 0:
                print(f"fetched {i}/{len(codes)}", file=sys.stderr)
            time.sleep(0.7)  # under the 100 product reads a minute limit


def main():
    out_dir = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
    terms = sys.argv[3] if len(sys.argv) > 3 else "general"
    os.makedirs(out_dir, exist_ok=True)
    codes = collect(out_dir, limit, terms)
    print(f"{len(codes)} products to fetch", file=sys.stderr)
    fetch(out_dir, codes)


if __name__ == "__main__":
    main()
