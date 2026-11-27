import 'package:opennutritracker/features/add_meal/data/dto/off/off_product_dto.dart';
import 'package:opennutritracker/features/diet_profile/data/food_facts_store.dart';
import 'package:opennutritracker/features/diet_profile/domain/food_facts.dart';

/// What an Open Food Facts product says about allergens, traces, claims
/// and ingredients.
FoodFacts foodFactsFromOff(OFFProductDTO product) =>
    FoodFacts.fromOpenFoodFacts(
      allergens: product.allergens_tags,
      traces: product.traces_tags,
      labels: product.labels_tags,
      analysis: product.ingredients_analysis_tags,
      ingredients: [
        product.ingredients_text_es,
        product.ingredients_text_en,
        product.ingredients_text,
      ].where((t) => t != null && t.trim().isNotEmpty).firstOrNull,
    );

/// Stores the product's facts under its barcode, when it has any.
Future<void> recordOffFoodFacts(String? code, OFFProductDTO product) async {
  final facts = foodFactsFromOff(product);
  if (!facts.isEmpty) await FoodFactsStore.record(code, facts);
}
