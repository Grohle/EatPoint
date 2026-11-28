import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_bmi_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/section_group.dart';
import 'package:opennutritracker/core/presentation/widgets/calories_profile_info_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/bounds/validator.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/goals/domain/body_goal.dart';
import 'package:opennutritracker/features/goals/presentation/body_goal_dialog.dart';
import 'package:opennutritracker/features/goals/presentation/body_goal_text.dart';
import 'package:opennutritracker/features/profile/domain/weekly_pace_for_goal.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_format.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/bmi_overview.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/profile_switcher_header.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_gender_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_height_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_weekly_weight_goal_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_pal_category_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_weight_dialog.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/water_goal_dialog.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/presentation/meal_slots_screen.dart';
import 'package:opennutritracker/features/points/presentation/points_settings_screen.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_screen.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_profile_screen.dart';
import 'package:opennutritracker/features/food_db/presentation/food_db_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/sync/presentation/household_edits_switch.dart';
import 'package:opennutritracker/features/food_db/presentation/my_foods_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// Room below the last row for the centre-docked Add button, which rides
  /// half of its 56 dp above the bottom bar and so over the end of this list.
  /// The old 32 dp left the last row 5 dp above the button, close enough that
  /// a tap meant for it could open the Add sheet instead (#1368).
  static const double _fabClearance = 56 / 2 + Dimens.spacing32;

  late ProfileBloc _profileBloc;

  /// EatPoint: whether the goal includes building muscle, from the points
  /// settings, and the user it was read for (re-read after a profile
  /// switch).
  bool _buildMuscle = false;
  UserEntity? _buildMuscleReadFor;

  @override
  void initState() {
    _profileBloc = locator<ProfileBloc>();
    super.initState();
  }

  void _readBuildMuscle(UserEntity user) {
    if (identical(_buildMuscleReadFor, user)) return;
    _buildMuscleReadFor = user;
    if (!locator.isRegistered<PointsSettingsDataSource>()) return;
    locator<PointsSettingsDataSource>().getSettings().then((settings) {
      if (mounted && settings.buildMuscle != _buildMuscle) {
        setState(() => _buildMuscle = settings.buildMuscle);
      }
    });
  }

  BodyGoal _bodyGoalOf(UserEntity user) => BodyGoal.of(
    user.goal,
    buildMuscle: _buildMuscle,
    weeklyPaceKg: user.weeklyWeightGoalKg,
  );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      bloc: _profileBloc,
      builder: (context, state) {
        if (state is ProfileInitial) {
          _profileBloc.add(LoadProfileEvent());
          return _getLoadingContent();
        } else if (state is ProfileLoadingState) {
          return _getLoadingContent();
        } else if (state is ProfileLoadedState) {
          return _getLoadedContent(
            context,
            state.userBMI,
            state.userEntity,
            state.bodyWeightUnit,
            state.usesImperialHeightUnits,
            state.effectiveWaterGoalMl,
            state.usesImperialFoodUnits,
          );
        } else {
          return _getLoadingContent();
        }
      },
    );
  }

  Widget _getLoadingContent() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _getLoadedContent(
    BuildContext context,
    UserBMIEntity userBMIEntity,
    UserEntity user,
    BodyWeightUnit bodyWeightUnit,
    bool usesImperialHeightUnits,
    int effectiveWaterGoalMl,
    bool usesImperialFoodUnits,
  ) {
    _readBuildMuscle(user);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing12,
        Dimens.spacing16,
        _fabClearance,
      ),
      children: [
        const ProfileSwitcherHeader(),
        const SizedBox(height: Dimens.spacing24),
        BMIOverview(
          bmiValue: userBMIEntity.bmiValue,
          nutritionalStatus: userBMIEntity.nutritionalStatus,
        ),
        const SizedBox(height: Dimens.spacing32),
        // EatPoint: settings get their own panel above the goal, each entry
        // opening its own screen.
        SectionHeader(label: S.of(context).settingsLabel, palette: palette),
        const SizedBox(height: Dimens.spacing12),
        SectionGroup(
          palette: palette,
          tiles: [
            _ProfileTile(
              identifier: 'profile-settings',
              palette: palette,
              icon: Icons.settings_rounded,
              title: S.of(context).profileAppSettingsLabel,
              subtitle: S.of(context).profileAppSettingsSubtitle,
              showChevron: true,
              onTap: () => Navigator.of(
                context,
              ).pushNamed(NavigationOptions.settingsRoute),
            ),
            if (locator.isRegistered<PointsSettingsDataSource>()) ...[
              _ProfileTile(
                identifier: 'profile-points',
                palette: palette,
                icon: Icons.donut_large_rounded,
                title: S.of(context).pointsSettingsTitle,
                subtitle: S.of(context).pointsSettingsSubtitle,
                showChevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PointsSettingsScreen()),
                ),
              ),
              _ProfileTile(
                identifier: 'profile-meals',
                palette: palette,
                icon: Icons.restaurant_menu_rounded,
                title: S.of(context).mealSlotsTitle,
                subtitle: S.of(context).mealSlotsEditSubtitle,
                showChevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MealSlotsScreen()),
                ),
              ),
              _ProfileTile(
                identifier: 'profile-diet',
                palette: palette,
                icon: Icons.no_food_outlined,
                title: S.of(context).dietTitle,
                subtitle: S.of(context).dietSubtitle,
                showChevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DietProfileScreen()),
                ),
              ),
              _ProfileTile(
                identifier: 'profile-food-db',
                palette: palette,
                icon: Icons.storage_rounded,
                title: S.of(context).foodDbTitle,
                subtitle: S.of(context).foodDbSubtitle,
                showChevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FoodDbScreen()),
                ),
              ),
              _ProfileTile(
                identifier: 'profile-my-foods',
                palette: palette,
                icon: Icons.edit_note_rounded,
                title: S.of(context).myFoodsTitle,
                subtitle: S.of(context).myFoodsSubtitle,
                showChevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyFoodsScreen()),
                ),
              ),
              _ProfileTile(
                identifier: 'profile-travel',
                palette: palette,
                icon: Icons.flight_takeoff_rounded,
                title: S.of(context).travelTitle,
                subtitle: S.of(context).travelSettingsSubtitle,
                showChevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TravelModeScreen()),
                ),
              ),
              const HouseholdEditsSwitch(),
            ],
          ],
        ),
        const SizedBox(height: Dimens.spacing24),
        SectionHeader(label: S.of(context).goalLabel, palette: palette),
        const SizedBox(height: Dimens.spacing12),
        SectionGroup(
          palette: palette,
          tiles: [
            _ProfileTile(
              identifier: 'profile-activity',
              palette: palette,
              icon: Icons.directions_walk_rounded,
              title: S.of(context).activityLabel,
              subtitle: user.pal.getName(context),
              onTap: () => _showSetPALCategoryDialog(context, user),
            ),
            _ProfileTile(
              identifier: 'profile-goal',
              palette: palette,
              icon: Icons.flag_rounded,
              title: S.of(context).goalLabel,
              subtitle: _bodyGoalOf(user).name(context),
              onTap: () => _showSetGoalDialog(context, user),
            ),
            _ProfileTile(
              identifier: 'profile-weekly-goal',
              palette: palette,
              icon: Icons.trending_down_rounded,
              title: S.of(context).weeklyWeightGoalLabel,
              subtitle: _weeklyGoalSubtitle(context, user, bodyWeightUnit),
              onTap: () => _showSetWeeklyWeightGoalDialog(
                context,
                user,
                bodyWeightUnit,
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimens.spacing24),
        SectionHeader(label: S.of(context).weightLabel, palette: palette),
        const SizedBox(height: Dimens.spacing12),
        SectionGroup(
          palette: palette,
          tiles: [
            _ProfileTile(
              identifier: 'profile-weight',
              palette: palette,
              icon: Icons.monitor_weight_rounded,
              title: S.of(context).weightLabel,
              subtitleWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatBodyWeight(
                      user.weightKG,
                      bodyWeightUnit,
                      kgLabel: S.of(context).kgLabel,
                      lbLabel: S.of(context).lbsLabel,
                      stLabel: S.of(context).stLabel,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                  ),
                  // #119: When the user has set a concrete target weight, surface
                  // the distance to it directly below the current weight. The
                  // delta is signed-agnostic — the message holds whether the
                  // target is above or below current (cut or gain).
                  if (user.targetWeightKg != null)
                    Text(
                      _targetWeightSubLabel(context, user, bodyWeightUnit),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                    ),
                ],
              ),
              onTap: () {
                _showSetWeightDialog(context, user, bodyWeightUnit);
              },
            ),
            _ProfileTile(
              identifier: 'profile-target-weight',
              palette: palette,
              icon: Icons.flag_rounded,
              title: S.of(context).profileTargetWeightLabel,
              subtitle: user.targetWeightKg == null
                  ? S.of(context).profileTargetWeightNotSetLabel
                  : formatBodyWeight(
                      user.targetWeightKg!,
                      bodyWeightUnit,
                      kgLabel: S.of(context).kgLabel,
                      lbLabel: S.of(context).lbsLabel,
                      stLabel: S.of(context).stLabel,
                    ),
              onTap: () =>
                  _showSetTargetWeightDialog(context, user, bodyWeightUnit),
            ),
            // The opt-in linear taper scales the daily kcal deficit down
            // as current weight approaches the target. Surfaced here only
            // once a target weight is set, since without one the toggle
            // has nothing to scale against.
            if (user.targetWeightKg != null)
              _ProfileSwitchTile(
                identifier: 'profile-calorie-taper',
                palette: palette,
                icon: Icons.trending_down_rounded,
                title: S.of(context).settingsCaloriesTaperLabel,
                subtitle: S.of(context).settingsCaloriesTaperDescription,
                value: user.caloriesTaperEnabled,
                onChanged: (v) => _profileBloc.setCaloriesTaperEnabled(v),
              ),
            _ProfileTile(
              identifier: 'profile-weight-history',
              palette: palette,
              icon: Icons.show_chart_rounded,
              title: S.of(context).profileWeightHistoryTitle,
              showChevron: true,
              onTap: () => Navigator.of(
                context,
              ).pushNamed(NavigationOptions.weightHistoryRoute),
            ),
            _ProfileTile(
              identifier: 'profile-fasting-entry',
              palette: palette,
              icon: Icons.timer_rounded,
              title: S.of(context).profileFastingEntry,
              showChevron: true,
              onTap: () =>
                  Navigator.of(context).pushNamed(NavigationOptions.fastingRoute),
            ),
          ],
        ),
        const SizedBox(height: Dimens.spacing24),
        SectionHeader(
          label: S.of(context).settingsWaterGoalLabel,
          palette: palette,
        ),
        const SizedBox(height: Dimens.spacing12),
        SectionGroup(
          palette: palette,
          tiles: [
            _ProfileTile(
              identifier: 'profile-water-goal',
              palette: palette,
              icon: Icons.water_drop_rounded,
              title: S.of(context).settingsWaterGoalLabel,
              subtitle: usesImperialFoodUnits
                  ? '${UnitCalc.mlToFlOz(effectiveWaterGoalMl.toDouble()).round()} ${S.of(context).flOzUnit}'
                  : '$effectiveWaterGoalMl ${S.of(context).mlLabel}',
              onTap: () => _showWaterGoalDialog(context, usesImperialFoodUnits),
            ),
          ],
        ),
        const SizedBox(height: Dimens.spacing24),
        SectionHeader(
          label: S.of(context).profileLabel,
          palette: palette,
        ),
        const SizedBox(height: Dimens.spacing12),
        SectionGroup(
          palette: palette,
          tiles: [
            _ProfileTile(
              identifier: 'profile-height',
              palette: palette,
              icon: Icons.height_rounded,
              title: S.of(context).heightLabel,
              subtitle: formatHeight(
                user.heightCM,
                usesImperialHeightUnits,
                cmLabel: S.of(context).cmLabel,
                ftLabel: S.of(context).ftLabel,
                inLabel: S.of(context).inLabel,
              ),
              onTap: () {
                _showSetHeightDialog(context, user, usesImperialHeightUnits);
              },
            ),
            _ProfileTile(
              identifier: 'profile-age',
              palette: palette,
              icon: Icons.cake_rounded,
              title: S.of(context).ageLabel,
              subtitle: S.of(context).yearsLabel(user.age),
              onTap: () {
                _showSetBirthdayDialog(context, user);
              },
            ),
            _ProfileTile(
              identifier: 'profile-gender',
              palette: palette,
              iconWidget: user.gender.getIcon(),
              title: S.of(context).genderLabel,
              subtitle: user.gender.getName(context),
              onTap: () {
                _showSetGenderDialog(context, user);
              },
            ),
            if (user.gender == UserGenderEntity.nonBinary)
              _ProfileTile(
                identifier: 'profile-calories-profile',
                palette: palette,
                icon: Icons.tune_rounded,
                title: S.of(context).caloriesProfileInfoTitle,
                subtitle: (user.caloriesProfile ?? CaloriesProfileEntity.averaged)
                    .getName(context),
                onTap: () {
                  _showCaloriesProfileDialog(context, user);
                },
              ),
          ],
        ),
        const SizedBox(height: Dimens.spacing24),
        SectionHeader(label: S.of(context).recipesLabel, palette: palette),
        const SizedBox(height: Dimens.spacing12),
        SectionGroup(
          palette: palette,
          tiles: [
            _ProfileTile(
              identifier: 'profile-recipes',
              palette: palette,
              icon: Icons.menu_book_rounded,
              title: S.of(context).recipesLabel,
              showChevron: true,
              onTap: () =>
                  Navigator.of(context).pushNamed(NavigationOptions.recipesRoute),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showSetPALCategoryDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    final selectedPalCategory = await showDialog<UserPALEntity>(
      context: context,
      builder: (BuildContext context) => const SetPALCategoryDialog(),
    );
    if (selectedPalCategory != null) {
      userEntity.pal = selectedPalCategory;
      _profileBloc.updateUser(userEntity);
    }
  }

  String _weeklyGoalSubtitle(
    BuildContext context,
    UserEntity user,
    BodyWeightUnit bodyWeightUnit,
  ) {
    final goal = user.weeklyWeightGoalKg;
    if (goal == null) return S.of(context).weeklyWeightGoalNoneLabel;
    if (goal == 0.0) return S.of(context).goalMaintainWeight;
    switch (bodyWeightUnit) {
      case BodyWeightUnit.kg:
        final sign = goal > 0 ? '+' : '';
        return S.of(context).weeklyWeightGoalKgPerWeek('$sign${goal.toStringAsFixed(2)}');
      case BodyWeightUnit.lb:
        final displayLb = goal * 2.20462;
        final sign = displayLb > 0 ? '+' : '';
        return S.of(context).weeklyWeightGoalLbsPerWeek('$sign${displayLb.toStringAsFixed(2)}');
      case BodyWeightUnit.st:
        final displaySt = goal * 2.20462 / 14;
        final sign = displaySt > 0 ? '+' : '';
        return '$sign${displaySt.toStringAsFixed(2)} ${S.of(context).stLabel}'
            '${S.of(context).trendsPerWeekSuffix}';
    }
  }

  Future<void> _showSetWeeklyWeightGoalDialog(
    BuildContext context,
    UserEntity userEntity,
    BodyWeightUnit bodyWeightUnit,
  ) async {
    final result = await showDialog<WeeklyWeightGoalResult>(
      context: context,
      builder: (context) => SetWeeklyWeightGoalDialog(
        currentGoalKg: userEntity.weeklyWeightGoalKg,
        bodyWeightUnit: bodyWeightUnit,
      ),
    );
    switch (result) {
      // null when the framework returns from a back-button pop, treated
      // as cancellation alongside the explicit Cancel case.
      case null:
      case WeeklyWeightGoalCancelled():
        return;
      case WeeklyWeightGoalCleared():
        userEntity.weeklyWeightGoalKg = null;
      case WeeklyWeightGoalSet(:final kgPerWeek):
        userEntity.weeklyWeightGoalKg = kgPerWeek;
    }
    await _profileBloc.updateUser(userEntity);
  }

  Future<void> _showSetGoalDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    // EatPoint: six goals (three of them with muscle), each explained.
    final previous = _bodyGoalOf(userEntity);
    final selected = await showDialog<BodyGoal>(
      context: context,
      builder: (BuildContext context) => BodyGoalDialog(current: previous),
    );
    if (selected == null) return;
    userEntity.goal = selected.weightGoal;
    // A pace pointing the other way would win over the goal, and the
    // muscle goals differ from the others in their pace.
    final oldPace = userEntity.weeklyWeightGoalKg;
    final newPace = WeeklyPaceForGoal.adjustBodyGoal(
      previous,
      selected,
      oldPace,
    );
    userEntity.weeklyWeightGoalKg = newPace;
    if (locator.isRegistered<PointsSettingsDataSource>()) {
      final source = locator<PointsSettingsDataSource>();
      final settings = await source.getSettings();
      await source.saveSettings(
        settings.copyWith(buildMuscle: selected.buildsMuscle),
      );
    }
    if (mounted) setState(() => _buildMuscle = selected.buildsMuscle);
    await _profileBloc.updateUser(userEntity);
    if (newPace != oldPace && newPace != null && context.mounted) {
      final pace = newPace == 0
          ? S.of(context).goalMaintainWeight
          : '${newPace > 0 ? '+' : ''}'
                '${newPace.toStringAsFixed(2)} kg';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).goalPaceSetTo(pace))),
      );
    }
  }

  Future<void> _showSetHeightDialog(
    BuildContext context,
    UserEntity userEntity,
    bool usesImperialUnits,
  ) async {
    final selectedHeightCm = await showDialog<double>(
      context: context,
      builder: (context) => SetHeightDialog(
        userHeightCm: userEntity.heightCM,
        usesImperialUnits: usesImperialUnits,
      ),
    );
    if (selectedHeightCm != null) {
      userEntity.heightCM = selectedHeightCm;
      _profileBloc.updateUser(userEntity);
    }
  }

  Future<void> _showSetWeightDialog(
    BuildContext context,
    UserEntity userEntity,
    BodyWeightUnit bodyWeightUnit,
  ) async {
    final newKg = await showDialog<double>(
      context: context,
      builder: (context) => SetWeightDialog(
        initialKg: userEntity.weightKG,
        unit: bodyWeightUnit,
      ),
    );
    if (newKg != null) {
      final now = DateTime.now();
      await locator<AddWeightLogUsecase>().addEntry(
        WeightLogEntity(
          date: DateTime(now.year, now.month, now.day),
          weightKg: newKg,
        ),
      );

      // addEntry already persisted today's weight onto the user record, so
      // reload it and route through ProfileBloc.updateUser purely so the
      // profile screen, diary, and home all refresh in one go — mirrors
      // QuickWeightWidget._showWeightDialog on the home screen.
      final updatedUser = await locator<GetUserUsecase>().getUserData();
      await _profileBloc.updateUser(updatedUser);
    }
  }

  Future<void> _showSetTargetWeightDialog(
    BuildContext context,
    UserEntity userEntity,
    BodyWeightUnit bodyWeightUnit,
  ) async {
    // Seed the picker from the existing target if set, otherwise from the
    // user's current weight so the wheel doesn't snap to a wildly different
    // value on first use. The dialog returns a TargetWeightDialogResult so
    // we can distinguish "user cancelled" (null) from "user picked a value"
    // (set) and from "user explicitly cleared the target" (clear flag).
    final seedKg = userEntity.targetWeightKg ?? userEntity.weightKG;
    final result = await showDialog<TargetWeightDialogResult>(
      context: context,
      builder: (context) => SetTargetWeightDialog(
        initialKg: seedKg,
        hasExistingTarget: userEntity.targetWeightKg != null,
        unit: bodyWeightUnit,
      ),
    );
    if (result == null) return;
    if (result.clear) {
      userEntity.targetWeightKg = null;
    } else if (result.value != null) {
      // The dialog now returns kg directly.
      userEntity.targetWeightKg = result.value;
    }
    _profileBloc.updateUser(userEntity);
  }

  Future<void> _showSetBirthdayDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDatePickerMode: DatePickerMode.year,
      // Same bounds as onboarding: without them this picker accepted a
      // birthday in 2099, which turns the age fed to the calorie
      // calculation negative. Existing values are clamped so a birthday
      // stored by an older build can still open the picker.
      initialDate: ValueValidator.clampBirthday(userEntity.birthday),
      firstDate: ValueValidator.getFirstDate(),
      lastDate: ValueValidator.getLastDate(),
    );
    if (selectedDate != null) {
      userEntity.birthday = selectedDate;
      _profileBloc.updateUser(userEntity);
    }
  }

  Future<void> _showSetGenderDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    final selectedGender = await showDialog<UserGenderEntity>(
      context: context,
      builder: (BuildContext context) => const SetGenderDialog(),
    );
    if (selectedGender == null) return;
    userEntity.gender = selectedGender;

    // Switching to non-binary: prompt for hormone profile and persist BOTH
    // fields in a single updateUser call. Issuing two saves (one for the
    // gender, one for the profile) used to race — by the time the home
    // recomputed kcal, only the gender write had landed and the profile
    // was still null, so every choice rendered as "averaged".
    if (selectedGender == UserGenderEntity.nonBinary) {
      if (context.mounted) {
        final selected = await showDialog<CaloriesProfileEntity>(
          context: context,
          builder: (BuildContext context) => CaloriesProfileInfoDialog(
            initialProfile:
                userEntity.caloriesProfile ?? CaloriesProfileEntity.averaged,
          ),
        );
        if (selected != null) {
          userEntity.caloriesProfile = selected;
        } else {
          // User cancelled the picker but is now non-binary — store the
          // implicit default explicitly so reads don't keep falling back.
          userEntity.caloriesProfile ??= CaloriesProfileEntity.averaged;
        }
      }
    } else {
      // Switching back to binary — drop any previously set hormone profile.
      // The field is meaningless outside of nonBinary.
      userEntity.caloriesProfile = null;
    }

    await _profileBloc.updateUser(userEntity);
  }

  void _showWaterGoalDialog(BuildContext context, bool usesImperialUnits) {
    showDialog(
      context: context,
      builder: (context) => WaterGoalDialog(
        settingsBloc: locator<SettingsBloc>(),
        homeBloc: locator<HomeBloc>(),
        usesImperialUnits: usesImperialUnits,
      ),
    );
  }

  Future<void> _showCaloriesProfileDialog(
    BuildContext context,
    UserEntity userEntity,
  ) async {
    final selected = await showDialog<CaloriesProfileEntity>(
      context: context,
      builder: (BuildContext context) => CaloriesProfileInfoDialog(
        initialProfile:
            userEntity.caloriesProfile ?? CaloriesProfileEntity.averaged,
      ),
    );
    if (selected == null) return;
    userEntity.caloriesProfile = selected;
    await _profileBloc.updateUser(userEntity);
  }

  String _targetWeightSubLabel(
    BuildContext context,
    UserEntity user,
    BodyWeightUnit bodyWeightUnit,
  ) {
    final target = user.targetWeightKg;
    if (target == null) return '';
    final deltaKg = (target - user.weightKG).abs();
    // Treat "close enough" as reached — under 0.1 kg the noise in body
    // weight measurements outweighs the difference and a "you've reached
    // your target" message lands better than "0.0 kg to go".
    if (deltaKg < 0.1) {
      return S.of(context).profileTargetWeightReached;
    }
    final String formatted;
    switch (bodyWeightUnit) {
      case BodyWeightUnit.kg:
        formatted = '${deltaKg.toStringAsFixed(1)} ${S.of(context).kgLabel}';
      case BodyWeightUnit.lb:
        formatted =
            '${(deltaKg * 2.20462).toStringAsFixed(1)} ${S.of(context).lbsLabel}';
      case BodyWeightUnit.st:
        // Split at the one decimal this line prints, so a remainder that
        // rounds to 14 lb lands as the next whole stone instead.
        final (stones, pounds) = UnitCalc.kgToStLb(deltaKg, poundsDecimals: 1);
        formatted =
            '$stones ${S.of(context).stLabel} ${pounds.toStringAsFixed(1)} ${S.of(context).lbsLabel}';
    }
    return S.of(context).profileTargetWeightToGo(formatted);
  }
}

/// A quiet section label that gives the grouped cards a consistent rhythm —
/// muted, lightly tracked, sitting just above the card it introduces.
/// A single tappable row inside a [_ProfileGroup]. Keeps the underlying
/// [ListTile] (so its role semantics carry through) but dresses the leading
/// icon as a soft, accent-tinted rounded chip in the friendly-flat style.
class _ProfileTile extends StatelessWidget {
  final String identifier;
  final AppPalette palette;
  final IconData? icon;
  final Widget? iconWidget;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final bool showChevron;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.identifier,
    required this.palette,
    required this.title,
    required this.onTap,
    this.icon,
    this.iconWidget,
    this.subtitle,
    this.subtitleWidget,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: identifier,
      child: ListTile(
        leading: _IconChip(palette: palette, icon: icon, iconWidget: iconWidget),
        title: Text(
          title,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: subtitleWidget ??
            (subtitle != null
                ? Text(
                    subtitle!,
                    style: text.bodyMedium?.copyWith(color: palette.textMuted),
                  )
                : null),
        trailing: showChevron
            ? Icon(Icons.chevron_right_rounded, color: accent)
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// Switch variant of [_ProfileTile] for the calorie-taper toggle.
class _ProfileSwitchTile extends StatelessWidget {
  final String identifier;
  final AppPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ProfileSwitchTile({
    required this.identifier,
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: identifier,
      child: SwitchListTile(
        secondary: _IconChip(palette: palette, icon: icon),
        title: Text(
          title,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitle,
          style: text.bodySmall?.copyWith(color: palette.textMuted),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// The soft rounded leading chip shared by every profile row — a tinted square
/// holding the row's icon in the active accent.
class _IconChip extends StatelessWidget {
  final AppPalette palette;
  final IconData? icon;
  final Widget? iconWidget;

  const _IconChip({required this.palette, this.icon, this.iconWidget});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: Dimens.borderRadiusS,
      ),
      child: IconTheme(
        data: IconThemeData(color: accent, size: 22),
        child: Center(child: iconWidget ?? Icon(icon, color: accent, size: 22)),
      ),
    );
  }
}
