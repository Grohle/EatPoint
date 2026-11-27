import 'package:flutter/widgets.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The localized name of a meal, e.g. "Breakfast".
String mealTypeLabel(BuildContext context, IntakeTypeEntity type) {
  final s = S.of(context);
  switch (type) {
    case IntakeTypeEntity.breakfast:
      return s.breakfastLabel;
    case IntakeTypeEntity.lunch:
      return s.lunchLabel;
    case IntakeTypeEntity.dinner:
      return s.dinnerLabel;
    case IntakeTypeEntity.snack:
      return s.snackLabel;
  }
}

/// The name of one of the user's meals: the name they gave it, or the
/// translated name of a built-in meal.
String mealSlotLabel(BuildContext context, MealSlot slot) =>
    slot.name ?? mealTypeLabel(context, slot.baseType);

/// The icon of one of the user's meals: the icon of the type it is stored
/// as.
IconData mealSlotIcon(MealSlot slot) => slot.baseType.getIconData();
