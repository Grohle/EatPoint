import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_bmi_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/goals/presentation/budget_info.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/profile_page.dart';

import '../features/points/points_test_support.dart';
import '../fixture/user_entity_fixtures.dart';
import 'screenshot_support.dart';

class _FakeProfileBloc extends Bloc<ProfileEvent, ProfileState>
    implements ProfileBloc {
  _FakeProfileBloc(super.initialState) {
    on<LoadProfileEvent>((event, emit) => emit(state));
  }

  @override
  Future<UserEntity> getUser() async =>
      (state as ProfileLoadedState).userEntity;

  @override
  Future<void> setCaloriesTaperEnabled(bool enabled) async {}

  @override
  Future<void> updateUser(UserEntity userEntity) async {}
}

class _OneProfile implements GetProfilesUsecase {
  static final _profile = ProfileEntity(
    id: 'p1',
    name: 'Me',
    createdAt: DateTime(2026, 1, 1),
    boxSuffix: '',
  );

  @override
  List<ProfileEntity> getProfiles() => [_profile];

  @override
  String get activeProfileId => 'p1';

  @override
  ProfileEntity? getActiveProfile() => _profile;
}

/// The You tab: settings in their own panel above the goal.
void main() {
  setUp(() async {
    await locator.reset();
    registerPointsLocator(box: MemoryStringBox());
    final user = UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight
      ..goal = UserWeightGoalEntity.loseWeight
      ..weeklyWeightGoalKg = -0.5;
    locator.registerSingleton<ProfileBloc>(
      _FakeProfileBloc(
        ProfileLoadedState(
          userBMI: const UserBMIEntity(
            bmiValue: 24.7,
            nutritionalStatus: UserNutritionalStatus.normalWeight,
          ),
          userEntity: user,
          bodyWeightUnit: BodyWeightUnit.kg,
          usesImperialHeightUnits: false,
          effectiveWaterGoalMl: 2000,
        ),
      ),
    );
    locator.registerSingleton<GetProfilesUsecase>(_OneProfile());
  });

  tearDown(() => locator.reset());

  for (final locale in const [Locale('en'), Locale('es')]) {
    final tag = locale.languageCode;
    testWidgets('profile tab ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: const Scaffold(body: ProfilePage()),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(list).position;
      position.jumpTo(260);
      await tester.pumpAndSettle();
      await settleAssets(tester);
      await capture(tester, '$tag/profile_tab');
    }, skip: !screenshotsEnabled);

    testWidgets('goal picker ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: const Scaffold(body: ProfilePage()),
        ),
      );
      await tester.pumpAndSettle();
      final goal = find.bySemanticsIdentifier('profile-goal');
      await tester.ensureVisible(goal);
      await tester.pumpAndSettle();
      await tester.tap(goal);
      await tester.pumpAndSettle();
      await capture(tester, '$tag/goal_picker');
    }, skip: !screenshotsEnabled);

    for (final topic in BudgetInfoTopic.values) {
      testWidgets('budget info ${topic.name} ($tag)', (tester) async {
        await loadAppFonts();
        usePhone(tester);
        await tester.pumpWidget(
          screenshotApp(
            locale: locale,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showBudgetInfo(context, topic),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await capture(tester, '$tag/budget_info_${topic.name}');
      }, skip: !screenshotsEnabled);
    }
  }
}
