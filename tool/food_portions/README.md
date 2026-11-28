# Portion pipeline

Checks the weight of every household unit the app shows ("1 rebanada",
"2 tortillas") against real sources, and writes the result into the food
database. The rule throughout: **the medium size, edible or drained weight,
as eaten or bought in Spain.**

1. **Dump** what the app shows today:

       DUMP_UNITS=/tmp/portions/units.tsv flutter test test/tool/dump_units_test.dart

2. **Group** the foods by unit and name, so one answer serves a whole group:

       python3 tool/food_portions/prepare.py /tmp/portions/units.tsv /tmp/portions/run 60

3. **Research.** Give each `batch_NN.json` to an agent with web search,
   briefed with [AGENT.md](AGENT.md). Each writes `answers_NN.json` next to
   its batch: a verdict, weight, range, unit names, sources and confidence
   per group.

4. **Merge** the answers into `tool/food_db/portion_review.json`:

       python3 tool/food_portions/merge.py /tmp/portions/run

   A change needs a source, and a change of more than 50 % needs high
   confidence. Everything else lands in `run/doubtful.json`.

5. **Decide** the doubtful groups (and overrule any answer) in
   [decisions.json](decisions.json): `"accept"`, `"reject"`, `"none"`, or
   `{"grams": …, "unit_es": […], "unit_en": […]}`. Run step 4 again until
   `doubtful.json` is empty.

6. **Publish** a new database version with the units:

       python3 tool/food_db/apply_portions.py

   It writes `data/food_db/eatpoint-foods-vN.json.gz` and updates the
   manifest; the app downloads it from `main`.

The generic weights of the catalogue (`assets/data/food_knowledge.json`)
are audited separately in `tool/food_knowledge/portion_audit.json`.
