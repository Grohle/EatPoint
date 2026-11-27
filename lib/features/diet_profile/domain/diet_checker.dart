import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/diet_profile/domain/food_facts.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';

/// Something a food contains that a diet may rule out.
enum DietTrait {
  gluten,
  milk,

  /// Lactose in amounts that matter (milk, yogurt, fresh cheese, cream).
  lactose,

  /// Dairy with very little lactose (aged cheese, butter).
  lowLactose,
  egg,
  fish,
  crustacean,
  mollusc,
  peanut,
  treeNut,
  soy,
  sesame,
  celery,
  mustard,
  sulphites,
  lupin,
  meat,
  pork,
  beef,
  alcohol,
  honey,
  gelatin,
}

/// Why a food clashes with the profile.
enum DietReason { allergy, intolerance, diet, religion, dislike }

enum ConflictSeverity {
  /// Leave it out.
  avoid,

  /// Fine in a free-from version (lactose-free milk, gluten-free bread).
  adapt,

  /// Worth knowing, not a reason to leave it out.
  note,
}

/// A version of the food that fits.
enum DietAlternative {
  lactoseFree,
  glutenFree,

  /// Gluten-free and certified as such, for coeliac disease.
  certifiedGlutenFree,

  /// A plant drink or yogurt instead of milk (lactose-free is not enough
  /// for a milk allergy).
  plantBased,

  /// Meat from a halal butcher.
  halalMeat,

  /// Kosher meat, not served with dairy.
  kosherMeat,

  /// Aged cheese has almost no lactose.
  agedCheeseOk,
}

class DietConflict {
  final DietReason reason;
  final DietTrait? trait;
  final ConflictSeverity severity;
  final DietAlternative? alternative;

  /// For [DietReason.allergy]: which one.
  final Allergen? allergen;

  /// For [DietReason.dislike]: the word that matched.
  final String? word;

  /// The label says it may contain traces of [trait].
  final bool traces;

  const DietConflict(
    this.reason,
    this.severity, {
    this.trait,
    this.alternative,
    this.allergen,
    this.word,
    this.traces = false,
  });
}

/// Tells what a food contains, from EatPoint's food list and from words in
/// its name (in Spanish and English), and checks it against a
/// [DietProfile].
///
/// Names can only tell so much: packaged foods may carry traces the name
/// does not show, so the screens say to check the label.
class DietChecker {
  final DietProfile profile;

  const DietChecker(this.profile);

  static const _conceptTraits = <String, Set<DietTrait>>{
    'egg': {DietTrait.egg},
    'chicken_breast': {DietTrait.meat},
    'chicken_thigh': {DietTrait.meat},
    'turkey_breast': {DietTrait.meat},
    'pork_loin': {DietTrait.meat, DietTrait.pork},
    'beef_steak': {DietTrait.meat, DietTrait.beef},
    'minced_meat': {DietTrait.meat, DietTrait.beef},
    'salmon': {DietTrait.fish},
    'white_fish': {DietTrait.fish},
    'tuna_can': {DietTrait.fish},
    'sardines_can': {DietTrait.fish},
    'mackerel': {DietTrait.fish},
    'ham': {DietTrait.meat, DietTrait.pork},
    'chorizo': {DietTrait.meat, DietTrait.pork},
    'tofu': {DietTrait.soy},
    'milk': {DietTrait.milk, DietTrait.lactose},
    'yogurt': {DietTrait.milk, DietTrait.lactose},
    'cheese_slice': {DietTrait.milk, DietTrait.lactose},
    'fresh_cheese': {DietTrait.milk, DietTrait.lactose},
    'parmesan': {DietTrait.milk, DietTrait.lowLactose},
    'butter': {DietTrait.milk, DietTrait.lowLactose},
    'bread_slice': {DietTrait.gluten},
    'baguette': {DietTrait.gluten},
    'tortilla_wrap': {DietTrait.gluten},
    'pasta': {DietTrait.gluten},
    'oats': {DietTrait.gluten},
    'biscuit': {DietTrait.gluten, DietTrait.milk, DietTrait.lactose},
    'almonds': {DietTrait.treeNut},
    'walnuts': {DietTrait.treeNut},
    'pistachios': {DietTrait.treeNut},
    'peanuts': {DietTrait.peanut},
    'peanut_butter': {DietTrait.peanut},
    'honey': {DietTrait.honey},
  };

  static RegExp _words(List<String> words) =>
      RegExp('(?<![a-z])(?:${words.join('|')})(?:s|es)?(?![a-z])');

  static final _rules = <DietTrait, RegExp>{
    DietTrait.gluten: _words([
      'trigo',
      'wheat',
      'pan',
      'panes',
      'bread',
      'baguette',
      'barra de pan',
      'pasta',
      'macarron',
      'espagueti',
      'spaghetti',
      'tallarin',
      'fideo',
      'noodle',
      'lasana',
      'lasagna',
      'canelon',
      'cuscus',
      'couscous',
      'bulgur',
      'cebada',
      'barley',
      'centeno',
      'rye',
      'espelta',
      'spelt',
      'seitan',
      'harina',
      'flour',
      'galleta',
      'biscuit',
      'cookie',
      'cracker',
      'bizcocho',
      'cake',
      'pizza',
      'empanada',
      'empanadilla',
      'rebozad[oa]',
      'empanad[oa]',
      'breaded',
      'pan rallado',
      'breadcrumb',
      'croissant',
      'cruasan',
      'magdalena',
      'muffin',
      'tostada',
      'toast',
      'biscote',
      'tortilla de trigo',
      'wrap',
      'cerveza',
      'beer',
      'avena',
      'oat',
      'oatmeal',
      'porridge',
      'semola',
      'semolina',
      'croqueta',
      'bocadillo',
      'sandwich',
      'sandwiches',
      'hamburguesa',
      'burger',
    ]),
    DietTrait.milk: _words([
      'leche',
      'milk',
      'yogur',
      'yogurt',
      'yoghurt',
      'queso',
      'cheese',
      'nata',
      'cream',
      'mantequilla',
      'butter',
      'kefir',
      'requeson',
      'cuajada',
      'batido',
      'milkshake',
      'latte',
      'bechamel',
      'helado',
      'ice cream',
      'mozzarella',
      'parmesano',
      'parmesan',
      'ricotta',
      'burrata',
      'ghee',
      'whey',
      'suero de leche',
      'lactosa',
      'lactose',
      'flan',
      'natillas',
      'custard',
    ]),
    DietTrait.egg: _words([
      'huevo',
      'egg',
      'tortilla',
      'omelette',
      'omelet',
      'revuelto',
      'mayonesa',
      'mayonnaise',
      'mayo',
      'merengue',
      'meringue',
      'frittata',
      'flan',
      'alioli',
    ]),
    DietTrait.fish: _words([
      'pescado',
      'fish',
      'salmon',
      'atun',
      'tuna',
      'merluza',
      'hake',
      'bacalao',
      'cod',
      'sardina',
      'sardine',
      'caballa',
      'mackerel',
      'anchoa',
      'anchovy',
      'anchovies',
      'boqueron',
      'trucha',
      'trout',
      'lubina',
      'sea bass',
      'dorada',
      'bream',
      'rape',
      'monkfish',
      'lenguado',
      'sole',
      'rodaballo',
      'surimi',
      'emperador',
      'swordfish',
      'pez espada',
      'bonito',
      'arenque',
      'herring',
    ]),
    DietTrait.crustacean: _words([
      'gamba',
      'langostino',
      'shrimp',
      'prawn',
      'cangrejo',
      'crab',
      'langosta',
      'lobster',
      'cigala',
      'bogavante',
      'necora',
      'marisco',
      'seafood',
    ]),
    DietTrait.mollusc: _words([
      'mejillon',
      'mussel',
      'almeja',
      'clam',
      'calamar',
      'calamares',
      'squid',
      'pulpo',
      'octopus',
      'sepia',
      'cuttlefish',
      'ostra',
      'oyster',
      'berberecho',
      'cockle',
      'vieira',
      'scallop',
      'caracol',
      'snail',
      'chipiron',
      'marisco',
      'seafood',
    ]),
    DietTrait.peanut: _words(['cacahuete', 'peanut', 'mani']),
    DietTrait.treeNut: _words([
      'almendra',
      'almond',
      'nuez',
      'nueces',
      'walnut',
      'avellana',
      'hazelnut',
      'pistacho',
      'pistachio',
      'anacardo',
      'cashew',
      'pecana',
      'pecan',
      'macadamia',
      'pinon',
      'pine nut',
      'frutos secos',
      'frutos de cascara',
      'fruto de cascara',
      'tree nut',
      'nuts',
      'mazapan',
      'marzipan',
      'praline',
      'turron',
      'nutella',
    ]),
    DietTrait.soy: _words([
      'soja',
      'soy',
      'soya',
      'tofu',
      'tempeh',
      'edamame',
      'miso',
      'tamari',
    ]),
    DietTrait.sesame: _words([
      'sesamo',
      'sesame',
      'tahini',
      'tahin',
      'hummus',
      'humus',
      'ajonjoli',
    ]),
    DietTrait.celery: _words(['apio', 'celery', 'celeriac']),
    DietTrait.mustard: _words(['mostaza', 'mustard']),
    DietTrait.sulphites: _words([
      'vino',
      'wine',
      'vinagre',
      'vinegar',
      'orejon',
      'sidra',
      'cider',
    ]),
    DietTrait.lupin: _words(['altramuz', 'lupin', 'lupine', 'lupini']),
    DietTrait.pork: _words([
      'cerdo',
      'pork',
      'jamon',
      'ham',
      'bacon',
      'beicon',
      'panceta',
      'chorizo',
      'salchichon',
      'salami',
      'sobrasada',
      'morcilla',
      'butifarra',
      'fuet',
      'mortadela',
      'longaniza',
      'cochinillo',
      'lard',
      'manteca de cerdo',
      'chicharron',
      'prosciutto',
      'pepperoni',
    ]),
    DietTrait.beef: _words([
      'ternera',
      'vacuno',
      'beef',
      'buey',
      'vaca',
      'entrecot',
      'chuleton',
      'rabo de toro',
      'veal',
      'cecina',
      'carne picada',
      'minced meat',
      'hamburguesa',
      'burger',
    ]),
    DietTrait.meat: _words([
      'pollo',
      'chicken',
      'pavo',
      'turkey',
      'cordero',
      'lamb',
      'conejo',
      'rabbit',
      'pato',
      'duck',
      'carne',
      'meat',
      'codorniz',
      'quail',
      'venado',
      'jabali',
      'higado',
      'liver',
      'embutido',
      'albondiga',
      'meatball',
      'salchicha',
      'sausage',
      'kebab',
      'gyros',
      'lomo',
      'solomillo',
      'chuleta',
      'costilla',
      'filete',
      'steak',
      'contramuslo',
      'pechuga',
      'muslo',
      'alita',
      'nugget',
    ]),
    DietTrait.alcohol: _words([
      'vino',
      'wine',
      'cerveza',
      'beer',
      'ron',
      'rum',
      'whisky',
      'vodka',
      'ginebra',
      'gin',
      'licor',
      'liqueur',
      'sidra',
      'cider',
      'cava',
      'champagne',
      'vermut',
      'brandy',
      'conac',
      'tequila',
      'sake',
      'sangria',
    ]),
    DietTrait.honey: _words(['miel', 'honey']),
    DietTrait.gelatin: _words([
      'gelatina',
      'gelatin',
      'gelatine',
      'gominola',
      'gummy',
      'gummies',
    ]),
  };

  /// "Lomo de salmón", "filete de merluza", "pechuga de pavo": cuts named
  /// after meat that are fish or poultry; and "hamburguesa de pollo".
  static final _cutOfFish = RegExp(
    r'(?<![a-z])(lomo|filete|steak|hamburguesa|burger)s? de (salmon|atun|merluza|bacalao|pescado|pollo|pavo|bonito|emperador|lubina|dorada|tofu|soja|garbanzo|lenteja|quinoa|verdura)',
  );
  static final _plantDrink = RegExp(
    r'(leche|bebida|yogur|yogurt|postre|nata|queso) (vegetal|de (soja|avena|almendra|arroz|coco|avellana|anacardo|nuez|guisante))|(soy|oat|almond|rice|coconut|plant|cashew|hazelnut|pea) (milk|drink|yogurt|yoghurt|cream|cheese)',
  );
  static final _plantMeat = RegExp(
    r'(?<![a-z])(vegetal|vegana?|vegan|veggie|plant based|plant-based|heura|beyond|de soja|de tofu|de seitan|texturizad)',
  );
  static final _glutenFree = RegExp(r'sin gluten|gluten[ -]?free|\bsg\b');
  static final _lactoseFree = RegExp(
    r'sin lactosa|lactose[ -]?free|0 ?% lactosa|deslactosad',
  );
  static final _alcoholFree = RegExp(r'sin alcohol|alcohol[ -]?free|0[.,]0');
  static final _peanutButter = RegExp(
    r'peanut butter|crema de cacahuete|mantequilla de cacahuete|cocoa butter|manteca de cacao|nut butter',
  );
  static final _agedCheese = RegExp(
    r'curad[oa]|viejo|anejo|parmesan|grana padano|pecorino|manchego|emmental|gruyere|gouda|cheddar|aged|mantequilla|butter|ghee',
  );
  static final _wheatTortilla = RegExp(
    r'tortilla(s)? (de (trigo|maiz|harina)|mexicana)|(flour|wheat|corn) tortilla|wrap',
  );

  /// What [name] (and the food list's [conceptId], when known) contains.
  static Set<DietTrait> traitsOf(String name, {String? conceptId}) {
    final text = FoodKnowledge.fold(name);
    final concept = conceptId ?? FoodKnowledge.instance?.match(name)?.id ?? '';
    final traits = <DietTrait>{...?_conceptTraits[concept]};
    for (final e in _rules.entries) {
      if (e.value.hasMatch(text)) traits.add(e.key);
    }
    // What words alone get wrong.
    final cut = _cutOfFish.firstMatch(text);
    if (cut != null) {
      const meats = {DietTrait.meat, DietTrait.pork, DietTrait.beef};
      traits.removeAll(meats);
      final rest = text.replaceAll(_cutOfFish, ' ');
      for (final t in meats) {
        if (_rules[t]!.hasMatch(rest)) traits.add(t);
      }
      if (cut.group(2) == 'pollo' || cut.group(2) == 'pavo') {
        traits.add(DietTrait.meat);
      }
    }
    if (_plantMeat.hasMatch(text)) {
      traits.removeAll({
        DietTrait.meat,
        DietTrait.pork,
        DietTrait.beef,
        DietTrait.fish,
      });
    }
    if (_plantDrink.hasMatch(text) || concept == 'plant_milk') {
      traits.removeAll({
        DietTrait.milk,
        DietTrait.lactose,
        DietTrait.lowLactose,
      });
    }
    if (_peanutButter.hasMatch(text)) {
      traits.removeAll({
        DietTrait.milk,
        DietTrait.lactose,
        DietTrait.lowLactose,
      });
    }
    if (_wheatTortilla.hasMatch(text)) {
      traits.remove(DietTrait.egg);
      if (!text.contains('maiz')) traits.add(DietTrait.gluten);
    } else if (text.contains('tortilla')) {
      // A Spanish tortilla is an omelette.
      traits
        ..remove(DietTrait.gluten)
        ..add(DietTrait.egg);
    }
    if (traits.contains(DietTrait.pork) || traits.contains(DietTrait.beef)) {
      traits.add(DietTrait.meat);
    }
    if (traits.contains(DietTrait.milk) &&
        !traits.contains(DietTrait.lowLactose) &&
        !traits.contains(DietTrait.lactose)) {
      traits.add(
        _agedCheese.hasMatch(text) ? DietTrait.lowLactose : DietTrait.lactose,
      );
    } else if (traits.contains(DietTrait.lactose) &&
        _agedCheese.hasMatch(text)) {
      traits
        ..remove(DietTrait.lactose)
        ..add(DietTrait.lowLactose);
    }
    if (_glutenFree.hasMatch(text)) traits.remove(DietTrait.gluten);
    if (_lactoseFree.hasMatch(text)) {
      traits.removeAll({DietTrait.lactose, DietTrait.lowLactose});
    }
    if (_alcoholFree.hasMatch(text)) traits.remove(DietTrait.alcohol);
    return traits;
  }

  /// Whether [name] says it is a gluten-free version.
  static bool isGlutenFree(String name) =>
      _glutenFree.hasMatch(FoodKnowledge.fold(name));

  static const _allergenTraits = <Allergen, Set<DietTrait>>{
    Allergen.gluten: {DietTrait.gluten},
    Allergen.crustaceans: {DietTrait.crustacean},
    Allergen.eggs: {DietTrait.egg},
    Allergen.fish: {DietTrait.fish},
    Allergen.peanuts: {DietTrait.peanut},
    Allergen.soy: {DietTrait.soy},
    Allergen.milk: {DietTrait.milk},
    Allergen.treeNuts: {DietTrait.treeNut},
    Allergen.celery: {DietTrait.celery},
    Allergen.mustard: {DietTrait.mustard},
    Allergen.sesame: {DietTrait.sesame},
    Allergen.sulphites: {DietTrait.sulphites},
    Allergen.lupin: {DietTrait.lupin},
    Allergen.molluscs: {DietTrait.mollusc},
  };

  /// Where [name] clashes with the profile, most serious first. [facts]
  /// from the food's label or Open Food Facts add what it contains, may
  /// contain and claims.
  List<DietConflict> check(String name, {String? conceptId, FoodFacts? facts}) {
    final traits = traitsOf(name, conceptId: conceptId);
    final labels = facts?.labels ?? const <FoodLabel>{};
    if (facts != null) {
      traits.addAll(facts.contains);
      if (facts.contains.contains(DietTrait.milk) &&
          !traits.contains(DietTrait.lowLactose)) {
        traits.add(DietTrait.lactose);
      }
    }
    // What the pack claims wins over what the name suggested.
    if (labels.contains(FoodLabel.vegan)) {
      traits.removeAll(const {
        DietTrait.meat,
        DietTrait.pork,
        DietTrait.beef,
        DietTrait.fish,
        DietTrait.crustacean,
        DietTrait.mollusc,
        DietTrait.egg,
        DietTrait.milk,
        DietTrait.lactose,
        DietTrait.lowLactose,
        DietTrait.honey,
        DietTrait.gelatin,
      });
    } else if (labels.contains(FoodLabel.vegetarian)) {
      traits.removeAll(const {
        DietTrait.meat,
        DietTrait.pork,
        DietTrait.beef,
        DietTrait.fish,
        DietTrait.crustacean,
        DietTrait.mollusc,
        DietTrait.gelatin,
      });
    }
    if (labels.contains(FoodLabel.glutenFree)) traits.remove(DietTrait.gluten);
    if (labels.contains(FoodLabel.lactoseFree)) {
      traits.removeAll({DietTrait.lactose, DietTrait.lowLactose});
    }
    // A milk allergy also forbids lactose-free milk, which is still milk.
    final milkInName = _rules[DietTrait.milk]!.hasMatch(
      FoodKnowledge.fold(name),
    );
    if (milkInName && !_plantDrink.hasMatch(FoodKnowledge.fold(name))) {
      traits.add(DietTrait.milk);
    }
    final out = <DietConflict>[];

    for (final allergen in profile.allergies) {
      final hit = _allergenTraits[allergen]!.intersection(traits);
      if (hit.isEmpty) continue;
      final gluten = allergen == Allergen.gluten;
      out.add(
        DietConflict(
          DietReason.allergy,
          gluten ? ConflictSeverity.adapt : ConflictSeverity.avoid,
          trait: hit.first,
          allergen: allergen,
          alternative: gluten
              ? DietAlternative.certifiedGlutenFree
              : allergen == Allergen.milk
              ? DietAlternative.plantBased
              : null,
        ),
      );
    }

    // Traces matter only for allergies.
    for (final allergen in profile.allergies) {
      final hit = _allergenTraits[allergen]!
          .intersection(facts?.traces ?? const {})
          .difference(traits);
      if (hit.isEmpty) continue;
      out.add(
        DietConflict(
          DietReason.allergy,
          ConflictSeverity.avoid,
          trait: hit.first,
          allergen: allergen,
          traces: true,
        ),
      );
    }

    if (profile.intolerances.contains(Intolerance.lactose) &&
        !profile.allergies.contains(Allergen.milk)) {
      if (traits.contains(DietTrait.lactose)) {
        out.add(
          const DietConflict(
            DietReason.intolerance,
            ConflictSeverity.adapt,
            trait: DietTrait.lactose,
            alternative: DietAlternative.lactoseFree,
          ),
        );
      } else if (traits.contains(DietTrait.lowLactose)) {
        out.add(
          const DietConflict(
            DietReason.intolerance,
            ConflictSeverity.note,
            trait: DietTrait.lowLactose,
            alternative: DietAlternative.agedCheeseOk,
          ),
        );
      }
    }
    if (profile.intolerances.contains(Intolerance.gluten) &&
        !profile.allergies.contains(Allergen.gluten) &&
        traits.contains(DietTrait.gluten)) {
      out.add(
        const DietConflict(
          DietReason.intolerance,
          ConflictSeverity.adapt,
          trait: DietTrait.gluten,
          alternative: DietAlternative.glutenFree,
        ),
      );
    }

    void avoid(DietReason reason, DietTrait trait) {
      if (traits.contains(trait) &&
          !out.any((c) => c.reason == reason && c.trait == trait)) {
        out.add(DietConflict(reason, ConflictSeverity.avoid, trait: trait));
      }
    }

    switch (profile.diet) {
      case DietStyle.omnivore:
        break;
      case DietStyle.pescatarian:
        avoid(DietReason.diet, DietTrait.meat);
        avoid(DietReason.diet, DietTrait.gelatin);
      case DietStyle.vegetarian:
        for (final t in const [
          DietTrait.meat,
          DietTrait.fish,
          DietTrait.crustacean,
          DietTrait.mollusc,
          DietTrait.gelatin,
        ]) {
          avoid(DietReason.diet, t);
        }
      case DietStyle.vegan:
        for (final t in const [
          DietTrait.meat,
          DietTrait.fish,
          DietTrait.crustacean,
          DietTrait.mollusc,
          DietTrait.gelatin,
          DietTrait.egg,
          DietTrait.honey,
        ]) {
          avoid(DietReason.diet, t);
        }
        if (traits.contains(DietTrait.milk)) {
          out.add(
            const DietConflict(
              DietReason.diet,
              ConflictSeverity.avoid,
              trait: DietTrait.milk,
              alternative: DietAlternative.plantBased,
            ),
          );
        }
    }

    switch (profile.religion) {
      case ReligiousDiet.none:
        break;
      case ReligiousDiet.halal:
        avoid(DietReason.religion, DietTrait.pork);
        avoid(DietReason.religion, DietTrait.alcohol);
        avoid(DietReason.religion, DietTrait.gelatin);
        if (traits.contains(DietTrait.meat) &&
            !traits.contains(DietTrait.pork) &&
            !labels.contains(FoodLabel.halal)) {
          out.add(
            const DietConflict(
              DietReason.religion,
              ConflictSeverity.note,
              trait: DietTrait.meat,
              alternative: DietAlternative.halalMeat,
            ),
          );
        }
      case ReligiousDiet.kosher:
        avoid(DietReason.religion, DietTrait.pork);
        avoid(DietReason.religion, DietTrait.crustacean);
        avoid(DietReason.religion, DietTrait.mollusc);
        avoid(DietReason.religion, DietTrait.gelatin);
        if (traits.contains(DietTrait.meat) &&
            !traits.contains(DietTrait.pork) &&
            !labels.contains(FoodLabel.kosher)) {
          out.add(
            const DietConflict(
              DietReason.religion,
              ConflictSeverity.note,
              trait: DietTrait.meat,
              alternative: DietAlternative.kosherMeat,
            ),
          );
        }
      case ReligiousDiet.hindu:
        avoid(DietReason.religion, DietTrait.beef);
    }

    final folded = FoodKnowledge.fold(name);
    for (final word in profile.dislikes) {
      final w = FoodKnowledge.fold(word).trim();
      if (w.isNotEmpty && folded.contains(w)) {
        out.add(
          DietConflict(DietReason.dislike, ConflictSeverity.avoid, word: word),
        );
      }
    }

    out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return out;
  }

  /// Whether the food must be left out (some conflict cannot be adapted).
  bool blocks(String name, {String? conceptId, FoodFacts? facts}) => check(
    name,
    conceptId: conceptId,
    facts: facts,
  ).any((c) => c.severity == ConflictSeverity.avoid);

  /// Whether [name] matches one of the foods the user likes.
  bool isLiked(String name) {
    final folded = FoodKnowledge.fold(name);
    return profile.likes.any((w) {
      final f = FoodKnowledge.fold(w).trim();
      return f.isNotEmpty && (folded.contains(f) || f.contains(folded));
    });
  }

  /// The free-from version of [name] when the profile needs one and it
  /// exists ("Leche sin lactosa", "Gluten-free bread"); [name] otherwise.
  String adaptedName(String name, String languageCode, {String? conceptId}) {
    final conflicts = check(name, conceptId: conceptId);
    if (conflicts.any((c) => c.severity == ConflictSeverity.avoid)) {
      return name;
    }
    final alts = {for (final c in conflicts) c.alternative};
    var adapted = name;
    final es = languageCode == 'es';
    if (alts.contains(DietAlternative.lactoseFree)) {
      adapted = es ? '$adapted sin lactosa' : 'Lactose-free ${_lower(adapted)}';
    }
    if (alts.contains(DietAlternative.glutenFree) ||
        alts.contains(DietAlternative.certifiedGlutenFree)) {
      adapted = es ? '$adapted sin gluten' : 'Gluten-free ${_lower(adapted)}';
    }
    return adapted;
  }

  static String _lower(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}
