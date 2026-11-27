import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';

/// Diets some religions follow, as far as food goes.
enum ReligiousDiet {
  none,

  /// No pork, alcohol or gelatine of pork; meat ideally halal.
  halal,

  /// No pork, shellfish or molluscs; meat kosher and not served with dairy.
  kosher,

  /// No beef.
  hindu,
}

/// The 14 allergens EU law requires to be declared.
enum Allergen {
  gluten,
  crustaceans,
  eggs,
  fish,
  peanuts,
  soy,
  milk,
  treeNuts,
  celery,
  mustard,
  sesame,
  sulphites,
  lupin,
  molluscs,
}

/// Intolerances where a "free-from" version of the food is fine.
enum Intolerance { lactose, gluten }

/// What the user eats and avoids, for one profile: the menu generator
/// follows it and adding a food warns when the food goes against it.
class DietProfile {
  final DietStyle diet;
  final ReligiousDiet religion;
  final Set<Allergen> allergies;
  final Set<Intolerance> intolerances;

  /// Foods the user does not want, as words ("coliflor", "hígado").
  final List<String> dislikes;

  /// Foods the user likes and wants suggested in menus.
  final List<String> likes;

  const DietProfile({
    this.diet = DietStyle.omnivore,
    this.religion = ReligiousDiet.none,
    this.allergies = const {},
    this.intolerances = const {},
    this.dislikes = const [],
    this.likes = const [],
  });

  static const empty = DietProfile();

  /// Nothing set: no restrictions and no likes.
  bool get isEmpty =>
      diet == DietStyle.omnivore &&
      religion == ReligiousDiet.none &&
      allergies.isEmpty &&
      intolerances.isEmpty &&
      dislikes.isEmpty &&
      likes.isEmpty;

  DietProfile copyWith({
    DietStyle? diet,
    ReligiousDiet? religion,
    Set<Allergen>? allergies,
    Set<Intolerance>? intolerances,
    List<String>? dislikes,
    List<String>? likes,
  }) => DietProfile(
    diet: diet ?? this.diet,
    religion: religion ?? this.religion,
    allergies: allergies ?? this.allergies,
    intolerances: intolerances ?? this.intolerances,
    dislikes: dislikes ?? this.dislikes,
    likes: likes ?? this.likes,
  );

  Map<String, dynamic> toJson() => {
    'diet': diet.name,
    'religion': religion.name,
    'allergies': [for (final a in allergies) a.name],
    'intolerances': [for (final i in intolerances) i.name],
    'dislikes': dislikes,
    'likes': likes,
  };

  /// Reads [toJson]; unknown values are skipped, never thrown on.
  factory DietProfile.fromJson(Object? json) {
    if (json is! Map) return empty;
    T byName<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    Set<T> names<T extends Enum>(List<T> values, Object? list) => {
      if (list is List)
        for (final n in list) ?values.where((v) => v.name == n).firstOrNull,
    };
    List<String> words(Object? list) => [
      if (list is List)
        for (final w in list)
          if (w is String && w.trim().isNotEmpty) w.trim(),
    ];
    return DietProfile(
      diet: byName(DietStyle.values, json['diet'], DietStyle.omnivore),
      religion: byName(
        ReligiousDiet.values,
        json['religion'],
        ReligiousDiet.none,
      ),
      allergies: names(Allergen.values, json['allergies']),
      intolerances: names(Intolerance.values, json['intolerances']),
      dislikes: words(json['dislikes']),
      likes: words(json['likes']),
    );
  }
}
