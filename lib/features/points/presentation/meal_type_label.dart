import 'package:flutter/widgets.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
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
