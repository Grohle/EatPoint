import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diet_profile/data/diet_profile_store.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_text.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// "Your diet": diet style, religion, allergies, intolerances, and foods
/// the user does or does not want. Saved as it changes.
class DietProfileScreen extends StatefulWidget {
  const DietProfileScreen({super.key});

  @override
  State<DietProfileScreen> createState() => _DietProfileScreenState();
}

class _DietProfileScreenState extends State<DietProfileScreen> {
  final _store = locator<DietProfileStore>();
  late DietProfile _profile = _store.get();

  void _set(DietProfile next) {
    setState(() => _profile = next);
    _store.save(next);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(
        top: Dimens.spacing24,
        bottom: Dimens.spacing8,
      ),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget help(String text) => Padding(
      padding: const EdgeInsets.only(top: Dimens.spacing8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    final religionHelp = _profile.religion.help(s);
    return Scaffold(
      appBar: AppBar(title: Text(s.dietTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing8,
          Dimens.spacing16,
          Dimens.spacing32,
        ),
        children: [
          Text(s.dietIntro, style: theme.textTheme.bodyMedium),
          title(s.dietStyleTitle),
          Semantics(
            identifier: 'diet-style',
            child: Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing8,
              children: [
                for (final style in DietStyle.values)
                  ChoiceChip(
                    label: Text(style.label(s)),
                    selected: _profile.diet == style,
                    onSelected: (_) => _set(_profile.copyWith(diet: style)),
                  ),
              ],
            ),
          ),
          help(_profile.diet.help(s)),
          title(s.dietReligionTitle),
          Semantics(
            identifier: 'diet-religion',
            child: Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing8,
              children: [
                for (final religion in ReligiousDiet.values)
                  ChoiceChip(
                    label: Text(religion.label(s)),
                    selected: _profile.religion == religion,
                    onSelected: (_) =>
                        _set(_profile.copyWith(religion: religion)),
                  ),
              ],
            ),
          ),
          if (religionHelp != null) help(religionHelp),
          title(s.dietAllergiesTitle),
          Semantics(
            identifier: 'diet-allergies',
            child: Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing8,
              children: [
                for (final allergen in Allergen.values)
                  FilterChip(
                    label: Text(allergen.label(s)),
                    selected: _profile.allergies.contains(allergen),
                    onSelected: (on) => _set(
                      _profile.copyWith(
                        allergies: on
                            ? {..._profile.allergies, allergen}
                            : ({..._profile.allergies}..remove(allergen)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          help(s.dietAllergiesHelp),
          title(s.dietIntolerancesTitle),
          Semantics(
            identifier: 'diet-intolerances',
            child: Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing8,
              children: [
                for (final intolerance in Intolerance.values)
                  FilterChip(
                    label: Text(intolerance.label(s)),
                    selected: _profile.intolerances.contains(intolerance),
                    onSelected: (on) => _set(
                      _profile.copyWith(
                        intolerances: on
                            ? {..._profile.intolerances, intolerance}
                            : ({..._profile.intolerances}..remove(intolerance)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          help(s.dietIntolerancesHelp),
          title(s.dietLikesTitle),
          _WordList(
            identifier: 'diet-likes',
            words: _profile.likes,
            icon: Icons.favorite_rounded,
            onChanged: (w) => _set(_profile.copyWith(likes: w)),
          ),
          help(s.dietLikesHelp),
          title(s.dietDislikesTitle),
          _WordList(
            identifier: 'diet-dislikes',
            words: _profile.dislikes,
            icon: Icons.not_interested_rounded,
            onChanged: (w) => _set(_profile.copyWith(dislikes: w)),
          ),
          help(s.dietDislikesHelp),
        ],
      ),
    );
  }
}

/// Words as removable chips, and a field that adds one, suggesting
/// EatPoint's basic foods as the user types.
class _WordList extends StatelessWidget {
  final String identifier;
  final List<String> words;
  final IconData icon;
  final ValueChanged<List<String>> onChanged;

  const _WordList({
    required this.identifier,
    required this.words,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final names = <String>[
      for (final f in FoodKnowledge.instance?.foods ?? const <CoreFood>[])
        f.name(lang),
    ];
    void add(String raw) {
      final word = raw.trim();
      if (word.isEmpty) return;
      final folded = FoodKnowledge.fold(word);
      if (words.any((w) => FoodKnowledge.fold(w) == folded)) return;
      onChanged([...words, word]);
    }

    return Semantics(
      identifier: identifier,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (words.isNotEmpty)
            Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing8,
              children: [
                for (final word in words)
                  InputChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(word),
                    onDeleted: () => onChanged([...words]..remove(word)),
                  ),
              ],
            ),
          const SizedBox(height: Dimens.spacing8),
          Autocomplete<String>(
            optionsBuilder: (value) {
              final q = FoodKnowledge.fold(value.text.trim());
              if (q.length < 2) return const Iterable<String>.empty();
              return names
                  .where((n) => FoodKnowledge.fold(n).contains(q))
                  .take(8);
            },
            onSelected: (value) => add(value),
            fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: s.dietAddWordHint,
                    prefixIcon: const Icon(Icons.add_rounded),
                    border: const OutlineInputBorder(
                      borderRadius: Dimens.borderRadiusM,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    add(value);
                    controller.clear();
                  },
                ),
          ),
        ],
      ),
    );
  }
}
