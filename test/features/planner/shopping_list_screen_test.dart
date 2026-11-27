import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/presentation/shopping_list_screen.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/features/sync/presentation/member_avatar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../helpers/fake_hive_db_provider.dart';
import 'planner_test_support.dart';

class _KeyedBox extends MemoryStringBox {
  @override
  Iterable<dynamic> get keys => data.keys;
}

class _NoSecrets extends Fake implements FlutterSecureStorage {}

class _NoRecipes extends Fake implements RecipeDataSource {
  @override
  RecipeDBO? getRecipeById(String id) => null;
}

void main() {
  final monday = DateTime(2026, 11, 23);
  late PlannerDataSource source;

  setUp(() {
    source = PlannerDataSource(
      FakeHiveDBProvider(pointsSettingsBox: MemoryStringBox()),
    );
    locator.registerSingleton<PlannerDataSource>(source);
    locator.registerSingleton<RecipeDataSource>(_NoRecipes());
  });

  tearDown(() async => locator.reset());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(ShoppingListScreen(weekOf: DateTime(2026, 11, 25))),
    );
    await tester.pumpAndSettle();
  }

  Future<void> plan() async {
    await source.saveDay(
      dayPlan(monday, {
        IntakeTypeEntity.lunch: [
          plannedItem('Arroz', 600),
          plannedItem('Tomate', 200),
        ],
        IntakeTypeEntity.dinner: [plannedItem('Arroz', 700)],
      }),
    );
  }

  testWidgets('shows the empty state', (tester) async {
    await pump(tester);
    expect(
      find.text('Plan some meals for this week and the list fills itself.'),
      findsOneWidget,
    );
  });

  testWidgets('groups by aisle, sums amounts and persists ticks', (
    tester,
  ) async {
    await plan();
    await pump(tester);

    expect(find.text('Shopping list'), findsOneWidget);
    expect(find.text('Week of Nov 23'), findsOneWidget);
    expect(find.text('Fruit and veg'), findsOneWidget);
    expect(find.text('Pantry'), findsOneWidget);
    expect(find.text('1.3 kg'), findsOneWidget); // 1300 g of rice
    expect(find.text('200 g'), findsOneWidget);
    expect(find.text('0 of 2 picked'), findsOneWidget);

    await tester.tap(find.text('Tomate'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 picked'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Tomate'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
    expect(source.getShopping(monday).checked, {'tomate|g'});
  });

  testWidgets('a circle per member who needs each item', (tester) async {
    await plan();
    final box = _KeyedBox();
    final household = HouseholdStore(
      FakeHiveDBProvider(pointsSettingsBox: box),
      _NoSecrets(),
    );
    await household.saveHousehold(
      const Household(
        householdId: '0123456789abcdef0123456789abcdef',
        memberId: 'aaaaaaaaaaaaaaaa',
        memberName: 'Ann',
        backend: SyncBackendConfig(
          kind: SyncBackendKind.webdav,
          url: 'https://example.org/dav',
        ),
      ),
    );
    await household.saveMember(
      MemberSnapshot(
        memberId: 'bbbbbbbbbbbbbbbb',
        name: 'Bo',
        updatedAt: monday,
        days: [
          dayPlan(monday, {
            IntakeTypeEntity.lunch: [plannedItem('Arroz', 300)],
          }),
        ],
      ),
    );
    locator.registerSingleton<HouseholdStore>(household);
    await pump(tester);

    final rice = find.ancestor(
      of: find.text('Arroz'),
      matching: find.byType(CheckboxListTile),
    );
    final tomato = find.ancestor(
      of: find.text('Tomate'),
      matching: find.byType(CheckboxListTile),
    );
    expect(
      find.descendant(of: rice, matching: find.byType(MemberAvatar)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: tomato, matching: find.byType(MemberAvatar)),
      findsOneWidget,
    );
  });

  testWidgets('shows who ticked an item', (tester) async {
    await plan();
    await source.saveShopping(
      monday,
      const ShoppingListState(
        checked: {'tomate|g'},
        checkedBy: {'tomate|g': 'Marta'},
      ),
    );
    await pump(tester);
    expect(find.text('Ticked by Marta'), findsOneWidget);
  });

  testWidgets('adds a manual item and removes it with a long press', (
    tester,
  ) async {
    await plan();
    await pump(tester);

    await tester.tap(bySemanticsId('shopping-add-item'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: bySemanticsId('shopping-add-name'),
        matching: find.byType(TextField),
      ),
      'Leche',
    );
    await tester.enterText(
      find.descendant(
        of: bySemanticsId('shopping-add-amount'),
        matching: find.byType(TextField),
      ),
      '2 l',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Dairy and eggs'), findsOneWidget);
    expect(find.text('2 l'), findsOneWidget);
    expect(source.getShopping(monday).manualItems.single.key, 'manual|leche');

    await tester.longPress(find.text('Leche'));
    await tester.pumpAndSettle();
    expect(find.text('Leche'), findsNothing);
    expect(source.getShopping(monday).manualItems, isEmpty);
  });

  testWidgets('reloads when the plan changes', (tester) async {
    await pump(tester);
    expect(find.text('Arroz'), findsNothing);
    await plan();
    await tester.pumpAndSettle();
    expect(find.text('Arroz'), findsOneWidget);
  });
}
