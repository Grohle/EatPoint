// Step 0 of the portion pipeline (tool/food_portions/README.md): writes the
// household unit the app shows for every food, as a TSV for prepare.py.
// Skipped unless DUMP_UNITS names the output file:
//   DUMP_UNITS=/tmp/units.tsv flutter test test/tool/dump_units_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/food_db/domain/food_database.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';

void main() {
  final out = Platform.environment['DUMP_UNITS'];
  test('dump the units the app shows', () {
    final knowledge = FoodKnowledge.parse(
      File(FoodKnowledge.assetPath).readAsStringSync(),
    );
    final manifest =
        jsonDecode(File('data/food_db/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final db = FoodDatabase.parseGzip(
      File('data/food_db/${manifest['file']}').readAsBytesSync(),
    );
    String clean(String? s) => (s ?? '').replaceAll(RegExp(r'[\t\n]'), ' ');
    final rows = <String>['code\tname_es\tname_en\tsource\tunit_es\tgrams'];
    for (final c in knowledge.concepts) {
      final p = c.mainPortion;
      if (p == null) continue;
      rows.add(
        'concept:${c.id}\t${c.namesEs.join('|')}\t${c.namesEn.join('|')}'
        '\tconcept\t${p.es.one}\t${p.grams}',
      );
    }
    for (final f in db.foods) {
      final name = f.nameEs ?? f.nameEn ?? '';
      String source;
      FoodPortion? p;
      if (f.unit.known) {
        p = f.unit.portion;
        source = 'db';
      } else {
        final concept = knowledge.match(name);
        p = concept?.mainPortion;
        source = 'catalogue:${concept?.id}';
      }
      if (p == null) continue;
      rows.add(
        '${f.id}\t${clean(f.nameEs)}\t${clean(f.nameEn)}\t$source'
        '\t${p.es.one}\t${p.grams}',
      );
    }
    File(out!).writeAsStringSync('${rows.join('\n')}\n');
  }, skip: out == null ? 'set DUMP_UNITS to write the dump' : false);
}
