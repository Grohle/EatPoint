import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/food_facts.dart';
import 'package:opennutritracker/features/food_db/data/food_db_service.dart';
import 'package:opennutritracker/features/food_db/domain/food_database.dart';

Map<String, dynamic> _payload() => {
  'format': 'eatpoint-foods',
  'version': 3,
  'generated': '2026-11-27',
  'sources': [
    {'id': 'usda', 'name': 'USDA', 'license': 'CC0', 'url': 'https://x'},
  ],
  'foods': [
    {'i': 'e:0', 's': 'eatpoint', 'es': 'Pechuga de pollo', 'k': 110, 'c': 0, 'p': 23, 'f': 1.5},
    {'i': 'u:1', 's': 'usda', 'es': 'Pollo, muslo, asado', 'en': 'Chicken, thigh, roasted', 'k': 200, 'c': 0, 'p': 25, 'f': 10, 'fi': 0, 'sv': 85},
    {'i': 'u:2', 's': 'usda', 'en': 'Grits, cooked', 'k': 60, 'c': 12, 'p': 1.5, 'f': 0.4},
    {'i': 'o:8412345678901', 's': 'off', 'es': 'Galletas María', 'b': 'Marca', 'k': 440, 'c': 72, 'p': 7, 'f': 12, 'a': ['gluten', 'milk'], 't': ['treeNut'], 'lb': ['vegetarian'], 'l': 0},
    {'i': 'bad', 'k': 1},
  ],
};

List<int> _gzipped() => gzip.encode(utf8.encode(jsonEncode(_payload())));

Future<String> _sha(List<int> bytes) async => (await Sha256().hash(bytes))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

void main() {
  group('FoodDatabase', () {
    final db = FoodDatabase.parseGzip(_gzipped());

    test('reads the foods, skipping broken rows', () {
      expect(db.version, 3);
      expect(db.foods, hasLength(4));
      expect(db.sources.single.license, 'CC0');
    });

    test('searches by word starts in either language', () {
      final es = db.search('poll', languageCode: 'es');
      // A name that starts with the query comes first.
      expect(es.map((f) => f.id), ['u:1', 'e:0']);
      expect(db.search('pechuga pollo', languageCode: 'es').single.id, 'e:0');
      final en = db.search('chicken thigh', languageCode: 'en');
      expect(en.single.id, 'u:1');
      // Accents and brand count; a food only named in English still shows.
      expect(db.search('maria marca', languageCode: 'es').single.id,
          'o:8412345678901');
      expect(db.search('grits', languageCode: 'es').single.name('es'),
          'Grits, cooked');
      expect(db.search('x'), isEmpty);
    });

    test('becomes a meal with its code, source and serving', () {
      final thigh = db.byCode('eatpoint-db:u:1')!;
      final meal = thigh.toMealEntity('es');
      expect(meal.name, 'Pollo, muslo, asado');
      expect(meal.source, MealSourceEntity.fdc);
      expect(meal.servingQuantity, 85);
      expect(meal.nutriments.proteins100, 25);
      final biscuits = db.byCode('8412345678901')!;
      expect(biscuits.toMealEntity('es').source, MealSourceEntity.off);
    });

    test('a product carries its allergens for the diet check', () {
      final facts = db.byCode('8412345678901')!.facts!;
      expect(facts.contains, containsAll([DietTrait.gluten, DietTrait.milk]));
      expect(facts.traces, {DietTrait.treeNut});
      expect(facts.labels, {FoodLabel.vegetarian});
      expect(db.byCode('eatpoint-db:e:0')!.facts, isNull);
    });
  });

  group('FoodDbService', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('food_db'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<FoodDbService> service({bool damaged = false}) async {
      final data = _gzipped();
      final manifest = {
        'version': 3,
        'file': 'eatpoint-foods-v3.json.gz',
        'bytes': data.length,
        'sha256': damaged ? 'abc' : await _sha(data),
        'count': 4,
        'generated': '2026-11-27',
        'sources': _payload()['sources'],
      };
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('manifest.json')) {
          return http.Response(jsonEncode(manifest), 200);
        }
        if (path.endsWith('eatpoint-foods-v3.json.gz')) {
          return http.Response.bytes(data, 200);
        }
        return http.Response('', 404);
      });
      return FoodDbService(client: client, directory: () async => dir);
    }

    test('downloads, checks, installs and loads again', () async {
      final s = await service();
      expect(await s.hasUpdate(), isTrue);
      await s.download();
      expect(s.state.value, FoodDbState.ready);
      expect(FoodDatabase.instance!.foods, hasLength(4));
      expect(await s.hasUpdate(), isFalse);

      FoodDatabase.setInstance(null);
      final again = await service();
      await again.load();
      expect(again.state.value, FoodDbState.ready);
      expect(again.installed!.version, 3);
      expect(FoodDatabase.instance!.foods, hasLength(4));

      await again.delete();
      expect(FoodDatabase.instance, isNull);
      expect(dir.listSync(), isEmpty);
    });

    test('a damaged download is refused and nothing is installed', () async {
      FoodDatabase.setInstance(null);
      final s = await service(damaged: true);
      await expectLater(s.download(), throwsFormatException);
      expect(s.state.value, FoodDbState.failed);
      expect(FoodDatabase.instance, isNull);
      expect(dir.listSync(), isEmpty);
    });

    test('on opening, an installed database updates only when newer', () async {
      // Nothing installed: nothing is downloaded.
      FoodDatabase.setInstance(null);
      final none = await service();
      await none.load();
      expect(await none.updateIfNewer(), isNull);
      expect(dir.listSync(), isEmpty);

      // An older version installed: the newer one replaces it.
      final s = await service();
      await s.download();
      final installed = File('${dir.path}/installed.json');
      final info = jsonDecode(installed.readAsStringSync()) as Map;
      installed.writeAsStringSync(
        jsonEncode({...info, 'version': 2, 'sha256': 'old'}),
      );
      final opened = await service();
      await opened.load();
      expect(opened.installed!.version, 2);
      expect(await opened.updateIfNewer(), 3);
      expect(opened.installed!.version, 3);

      // Up to date: nothing happens.
      expect(await opened.updateIfNewer(), isNull);
    });

    test('a manifest naming a path is rejected', () {
      expect(
        FoodDbInfo.fromJson({
          'version': 1,
          'file': '../evil',
          'sha256': 'x',
        }),
        isNull,
      );
    });
  });
}
