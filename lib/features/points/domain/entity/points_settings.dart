import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

/// Everything the user can set about the points system, for one profile.
///
/// Null fields mean "use the default". Stored as JSON in its own per-profile
/// box (see `PointsSettingsDataSource`) so the fork's settings stay apart
/// from the upstream config.
class PointsSettings {
  /// Points are the main way of logging and planning. When false the app
  /// behaves like the original calorie-first app.
  final bool pointsModeEnabled;

  final PointsBudgetMethod budgetMethod;

  /// [PointsBudgetMethod.leanMass] settings. Null [calorieAdjustment] means
  /// "derive from the weight goal".
  final double? calorieAdjustment;
  final double proteinGramsPerKgLeanMass;
  final double carbShareOfRemainder;

  /// Activity multiplier for resting energy. Null means "derive from the
  /// activity level in the profile".
  final double? activityMultiplier;

  /// Optional body measurements for the body-fat estimate, in cm.
  final double? neckCm;
  final double? waistCm;
  final double? hipCm;

  /// Per-meal share of each macro's daily points. Null means
  /// [PointsBudgetCalc.defaultMealSplit].
  final Map<IntakeTypeEntity, MacroPoints>? mealSplit;

  /// The meals of the user's day, in order. Null means the four built-in
  /// meals with [effectiveMealSplit] as their shares.
  final List<MealSlot>? mealSlots;

  /// A daily budget the user typed in themselves. When set it replaces the
  /// suggested budget.
  final MacroPoints? dailyBudgetOverride;

  /// The user has seen and acknowledged that the suggested budget is a
  /// guide only.
  final bool budgetGuideAcknowledged;

  /// When a meal goes over its budget on a macro, take the excess off the
  /// meals still ahead that day. Applies to what is logged, never to the
  /// planned menu.
  final bool rebalanceOverspend;

  const PointsSettings({
    this.pointsModeEnabled = true,
    this.budgetMethod = PointsBudgetMethod.leanMass,
    this.calorieAdjustment,
    this.proteinGramsPerKgLeanMass = 1.5,
    this.carbShareOfRemainder = 0.65,
    this.activityMultiplier,
    this.neckCm,
    this.waistCm,
    this.hipCm,
    this.mealSplit,
    this.mealSlots,
    this.dailyBudgetOverride,
    this.budgetGuideAcknowledged = false,
    this.rebalanceOverspend = true,
  });

  static const defaults = PointsSettings();

  Map<IntakeTypeEntity, MacroPoints> get effectiveMealSplit =>
      mealSplit ?? PointsBudgetCalc.defaultMealSplit;

  /// The meals of the day: the user's own list, or the four built-in ones.
  List<MealSlot> get effectiveMealSlots {
    final slots = mealSlots;
    if (slots != null && slots.isNotEmpty) return slots;
    return MealSlot.builtIn(effectiveMealSplit);
  }

  PointsSettings copyWith({
    bool? pointsModeEnabled,
    PointsBudgetMethod? budgetMethod,
    double? Function()? calorieAdjustment,
    double? proteinGramsPerKgLeanMass,
    double? carbShareOfRemainder,
    double? Function()? activityMultiplier,
    double? Function()? neckCm,
    double? Function()? waistCm,
    double? Function()? hipCm,
    Map<IntakeTypeEntity, MacroPoints>? Function()? mealSplit,
    List<MealSlot>? Function()? mealSlots,
    MacroPoints? Function()? dailyBudgetOverride,
    bool? budgetGuideAcknowledged,
    bool? rebalanceOverspend,
  }) => PointsSettings(
    pointsModeEnabled: pointsModeEnabled ?? this.pointsModeEnabled,
    budgetMethod: budgetMethod ?? this.budgetMethod,
    calorieAdjustment: calorieAdjustment != null
        ? calorieAdjustment()
        : this.calorieAdjustment,
    proteinGramsPerKgLeanMass:
        proteinGramsPerKgLeanMass ?? this.proteinGramsPerKgLeanMass,
    carbShareOfRemainder: carbShareOfRemainder ?? this.carbShareOfRemainder,
    activityMultiplier: activityMultiplier != null
        ? activityMultiplier()
        : this.activityMultiplier,
    neckCm: neckCm != null ? neckCm() : this.neckCm,
    waistCm: waistCm != null ? waistCm() : this.waistCm,
    hipCm: hipCm != null ? hipCm() : this.hipCm,
    mealSplit: mealSplit != null ? mealSplit() : this.mealSplit,
    mealSlots: mealSlots != null ? mealSlots() : this.mealSlots,
    dailyBudgetOverride: dailyBudgetOverride != null
        ? dailyBudgetOverride()
        : this.dailyBudgetOverride,
    budgetGuideAcknowledged:
        budgetGuideAcknowledged ?? this.budgetGuideAcknowledged,
    rebalanceOverspend: rebalanceOverspend ?? this.rebalanceOverspend,
  );

  Map<String, dynamic> toJson() => {
    'pointsModeEnabled': pointsModeEnabled,
    'budgetMethod': budgetMethod.name,
    if (calorieAdjustment != null) 'calorieAdjustment': calorieAdjustment,
    'proteinGramsPerKgLeanMass': proteinGramsPerKgLeanMass,
    'carbShareOfRemainder': carbShareOfRemainder,
    if (activityMultiplier != null) 'activityMultiplier': activityMultiplier,
    if (neckCm != null) 'neckCm': neckCm,
    if (waistCm != null) 'waistCm': waistCm,
    if (hipCm != null) 'hipCm': hipCm,
    if (mealSplit != null)
      'mealSplit': {
        for (final e in mealSplit!.entries)
          e.key.name: _macroPointsToJson(e.value),
      },
    if (mealSlots != null)
      'mealSlots': [for (final slot in mealSlots!) slot.toJson()],
    if (dailyBudgetOverride != null)
      'dailyBudgetOverride': _macroPointsToJson(dailyBudgetOverride!),
    'budgetGuideAcknowledged': budgetGuideAcknowledged,
    'rebalanceOverspend': rebalanceOverspend,
  };

  /// Reads settings written by [toJson]. Unknown or malformed values fall
  /// back to the defaults instead of throwing, so a bad value never locks
  /// the user out of the app.
  factory PointsSettings.fromJson(Map<String, dynamic> json) {
    Map<IntakeTypeEntity, MacroPoints>? split;
    final rawSplit = json['mealSplit'];
    if (rawSplit is Map) {
      split = {};
      for (final type in IntakeTypeEntity.values) {
        final value = _macroPointsFromJson(rawSplit[type.name]);
        if (value != null) split[type] = value;
      }
      if (split.length != IntakeTypeEntity.values.length) split = null;
    }
    List<MealSlot>? slots;
    final rawSlots = json['mealSlots'];
    if (rawSlots is List) {
      final ids = <String>{};
      slots = [
        for (final raw in rawSlots)
          if (MealSlot.fromJson(raw) case final slot? when ids.add(slot.id))
            slot,
      ];
      if (slots.isEmpty) slots = null;
    }
    return PointsSettings(
      pointsModeEnabled: _toBool(json['pointsModeEnabled']) ?? true,
      budgetMethod: PointsBudgetMethod.values.firstWhere(
        (m) => m.name == json['budgetMethod'],
        orElse: () => PointsBudgetMethod.leanMass,
      ),
      calorieAdjustment: _toDouble(json['calorieAdjustment']),
      proteinGramsPerKgLeanMass:
          _toDouble(json['proteinGramsPerKgLeanMass']) ?? 1.5,
      carbShareOfRemainder: _toDouble(json['carbShareOfRemainder']) ?? 0.65,
      activityMultiplier: _toDouble(json['activityMultiplier']),
      neckCm: _toDouble(json['neckCm']),
      waistCm: _toDouble(json['waistCm']),
      hipCm: _toDouble(json['hipCm']),
      mealSplit: split,
      mealSlots: slots,
      dailyBudgetOverride: _macroPointsFromJson(json['dailyBudgetOverride']),
      budgetGuideAcknowledged:
          _toBool(json['budgetGuideAcknowledged']) ?? false,
      rebalanceOverspend: _toBool(json['rebalanceOverspend']) ?? true,
    );
  }

  static Map<String, double> _macroPointsToJson(MacroPoints p) => {
    'carbs': p.carbs,
    'protein': p.protein,
    'fat': p.fat,
  };

  static MacroPoints? _macroPointsFromJson(Object? raw) {
    if (raw is! Map) return null;
    final carbs = _toDouble(raw['carbs']);
    final protein = _toDouble(raw['protein']);
    final fat = _toDouble(raw['fat']);
    if (carbs == null || protein == null || fat == null) return null;
    return MacroPoints(carbs: carbs, protein: protein, fat: fat);
  }

  static bool? _toBool(Object? value) => value is bool ? value : null;

  static double? _toDouble(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;
}
