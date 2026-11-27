import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/food_facts.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_text.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_warning.dart';
import 'package:opennutritracker/features/label_scan/data/label_text_reader.dart';
import 'package:opennutritracker/features/label_scan/data/remote_nutrition_extractor.dart';
import 'package:opennutritracker/features/label_scan/domain/nutrition_label_parser.dart';
import 'package:opennutritracker/features/label_scan/presentation/label_scan_settings_screen.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/features/settings/settings_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Starts a label scan: asks for camera or gallery, then opens the review
/// screen. Returns the reviewed values, or null when the user backs out.
class LabelScanFlow {
  static Future<NutritionLabelValues?> start(BuildContext context) async {
    final s = S.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              identifier: 'label-scan-camera',
              child: ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(s.labelScanTakePhoto),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ),
            Semantics(
              identifier: 'label-scan-gallery',
              child: ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(s.labelScanChooseGallery),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final photo = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 90,
    );
    if (photo == null || !context.mounted) return null;
    return Navigator.of(context).push<NutritionLabelValues>(
      MaterialPageRoute(builder: (_) => LabelScanScreen(imagePath: photo.path)),
    );
  }
}

/// Review screen: the photo on top, the values read from it below, all
/// editable, with a check that the energy adds up.
class LabelScanScreen extends StatefulWidget {
  final String imagePath;

  /// Injectable for tests.
  final LabelTextReader? reader;
  final RemoteNutritionExtractor? extractor;

  const LabelScanScreen({
    super.key,
    required this.imagePath,
    this.reader,
    this.extractor,
  });

  @override
  State<LabelScanScreen> createState() => _LabelScanScreenState();
}

enum _Field { kcal, fat, saturatedFat, carbs, sugars, fiber, protein, salt }

class _LabelScanScreenState extends State<LabelScanScreen> {
  late String _imagePath = widget.imagePath;
  late final LabelTextReader _reader = widget.reader ?? MlKitLabelTextReader();
  late final RemoteNutritionExtractor _extractor =
      widget.extractor ??
      RemoteNutritionExtractor(http.Client(), locator<AiCredentialStorage>());

  final Map<_Field, TextEditingController> _controllers = {
    for (final f in _Field.values) f: TextEditingController(),
  };

  bool _reading = true;
  bool _aiBusy = false;
  bool _perMl = false;
  String? _readBy;

  @override
  void initState() {
    super.initState();
    _readOnDevice();
  }

  @override
  void dispose() {
    _ingredients.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _reader.close();
    super.dispose();
  }

  Future<void> _readOnDevice() async {
    setState(() => _reading = true);
    NutritionLabelValues values = NutritionLabelValues.empty;
    try {
      final rows = await _reader.readRows(_imagePath);
      values = NutritionLabelParser.parse(rows);
    } catch (_) {
      // Leave the fields empty for the user to fill in.
    }
    if (!mounted) return;
    _fill(values);
    setState(() {
      _reading = false;
      _readBy = null;
    });
  }

  void _fill(NutritionLabelValues v) {
    final format = PointsFormat.of(context);
    String text(double? x) => x == null ? '' : format.grams(x);
    _controllers[_Field.kcal]!.text = text(v.kcal);
    _controllers[_Field.fat]!.text = text(v.fat);
    _controllers[_Field.saturatedFat]!.text = text(v.saturatedFat);
    _controllers[_Field.carbs]!.text = text(v.carbs);
    _controllers[_Field.sugars]!.text = text(v.sugars);
    _controllers[_Field.fiber]!.text = text(v.fiber);
    _controllers[_Field.protein]!.text = text(v.protein);
    _controllers[_Field.salt]!.text = text(v.salt);
    _perMl = v.perMl;
  }

  NutritionLabelValues get _values {
    double? read(_Field f) => PointsFormat.parse(_controllers[f]!.text);
    return NutritionLabelValues(
      kcal: read(_Field.kcal),
      fat: read(_Field.fat),
      saturatedFat: read(_Field.saturatedFat),
      carbs: read(_Field.carbs),
      sugars: read(_Field.sugars),
      fiber: read(_Field.fiber),
      protein: read(_Field.protein),
      salt: read(_Field.salt),
      perMl: _perMl,
      facts: _facts,
    );
  }

  // EatPoint: the ingredients list, for allergens and the diet check.
  final _ingredients = TextEditingController();
  bool _readingIngredients = false;
  bool _ingredientsTried = false;

  /// What the ingredients text says; null when there is none.
  FoodFacts? get _facts {
    final text = _ingredients.text.trim();
    if (text.isEmpty) return null;
    var facts = IngredientLabelParser.parse(text);
    // Typed or read without its heading: all of it is the list.
    if (facts.ingredients == null) {
      final whole = IngredientLabelParser.parse('Ingredientes: $text');
      facts = FoodFacts(
        contains: {...facts.contains, ...whole.contains},
        traces: whole.traces,
        labels: {...facts.labels, ...whole.labels},
        ingredients: whole.ingredients,
      );
    }
    return facts.isEmpty ? null : facts;
  }

  Future<void> _photographIngredients() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final s = S.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(s.labelScanTakePhoto),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(s.labelScanChooseGallery),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;
    final photo = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 90,
    );
    if (photo == null || !mounted) return;
    setState(() => _readingIngredients = true);
    var text = '';
    try {
      text = (await _reader.readRows(photo.path)).join('\n');
    } catch (_) {
      // Leave it for the user to type.
    }
    if (!mounted) return;
    setState(() {
      _readingIngredients = false;
      _ingredientsTried = true;
      if (text.trim().isNotEmpty) _ingredients.text = text.trim();
    });
  }

  Widget _ingredientsSection(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final facts = _facts;
    String list(Iterable<String> items) => items.join(', ');
    return Semantics(
      identifier: 'label-scan-ingredients',
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: Dimens.spacing32),
          Text(s.labelScanIngredientsTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: Dimens.spacing4),
          Text(
            s.labelScanIngredientsHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          Semantics(
            identifier: 'label-scan-ingredients-photo',
            child: OutlinedButton.icon(
              icon: _readingIngredients
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(
                _readingIngredients
                    ? s.labelScanReadingIngredients
                    : _ingredientsTried
                    ? s.labelScanIngredientsRetake
                    : s.labelScanIngredientsPhoto,
              ),
              onPressed: _readingIngredients ? null : _photographIngredients,
            ),
          ),
          if (_ingredientsTried && _ingredients.text.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing8),
              child: Text(
                s.labelScanNoIngredients,
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: Dimens.spacing8),
          Semantics(
            identifier: 'label-scan-ingredients-field',
            child: TextField(
              controller: _ingredients,
              minLines: 2,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: s.labelScanIngredientsField,
                helperText: s.labelScanIngredientsFieldHelp,
                border: const OutlineInputBorder(
                  borderRadius: Dimens.borderRadiusM,
                ),
              ),
            ),
          ),
          if (facts != null) ...[
            const SizedBox(height: Dimens.spacing8),
            if (facts.contains.isNotEmpty)
              Text(
                s.labelScanContains(list(_traitNames(s, facts.contains))),
                style: theme.textTheme.bodySmall,
              ),
            if (facts.traces.isNotEmpty)
              Text(
                s.labelScanTraces(list(_traitNames(s, facts.traces))),
                style: theme.textTheme.bodySmall,
              ),
            if (facts.labels.isNotEmpty)
              Text(
                s.labelScanClaims(list(facts.labels.map((l) => l.label(s)))),
                style: theme.textTheme.bodySmall,
              ),
            DietWarning(
              '',
              facts: facts,
              margin: const EdgeInsets.only(top: Dimens.spacing8),
            ),
          ],
        ],
      ),
    );
  }

  /// Trait names without repeats (milk and lactose read as one).
  static List<String> _traitNames(S s, Set<DietTrait> traits) => {
    for (final t in traits)
      if (t != DietTrait.lowLactose &&
          !(t == DietTrait.lactose && traits.contains(DietTrait.milk)) &&
          !(t == DietTrait.meat &&
              (traits.contains(DietTrait.pork) ||
                  traits.contains(DietTrait.beef))))
        t.label(s),
  }.toList();

  Future<void> _retake() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 90,
    );
    if (photo == null || !mounted) return;
    setState(() => _imagePath = photo.path);
    await _readOnDevice();
  }

  Future<void> _retryWithAi() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final selection = await locator<AiCredentialStorage>().readSelection();
    if (!mounted) return;
    if (selection == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(s.labelScanAiNotConfigured),
          action: SnackBarAction(
            label: s.labelScanSettingsTitle,
            onPressed: () => Navigator.of(context).pushNamed(
              NavigationOptions.settingsRoute,
              arguments: const SettingsScreenArguments(openAiAssist: true),
            ),
          ),
        ),
      );
      return;
    }
    final provider = labelScanProviderName(selection);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.labelScanAiConfirmTitle),
        content: Text(s.labelScanAiConfirmBody(provider)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.labelScanAiConfirmSend),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _aiBusy = true);
    try {
      final values = await _extractor.extract(_imagePath);
      if (!mounted) return;
      _fill(values);
      setState(() => _readBy = provider);
    } on RemoteExtractionException {
      messenger.showSnackBar(SnackBar(content: Text(s.labelScanAiFailed)));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final values = _values;
    final check = NutritionLabelParser.checkEnergy(values);
    final suspects = _suspectFields(values, check);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.labelScanTitle),
        actions: [
          Semantics(
            identifier: 'label-scan-settings',
            child: IconButton(
              tooltip: s.labelScanSettingsTitle,
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LabelScanSettingsScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _photo(context),
            Expanded(
              child: _reading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: Dimens.spacing12),
                          Text(s.labelScanReading),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(Dimens.spacing16),
                      children: [
                        _banner(context, values, check),
                        const SizedBox(height: Dimens.spacing12),
                        Text(
                          _perMl ? s.labelScanPer100ml : s.labelScanPer100g,
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: Dimens.spacing8),
                        _grid(context, suspects),
                        const SizedBox(height: Dimens.spacing12),
                        _pointsResult(context, values),
                        _ingredientsSection(context),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing16,
                Dimens.spacing8,
                Dimens.spacing16,
                Dimens.spacing16,
              ),
              child: Row(
                children: [
                  Semantics(
                    identifier: 'label-scan-retry-ai',
                    child: OutlinedButton.icon(
                      onPressed: _reading || _aiBusy ? null : _retryWithAi,
                      icon: _aiBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined),
                      label: Text(s.labelScanRetryAi),
                    ),
                  ),
                  const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: Semantics(
                      identifier: 'label-scan-use-values',
                      child: FilledButton(
                        onPressed: _reading || _aiBusy
                            ? null
                            : () => Navigator.of(context).pop(_values),
                        child: Text(s.labelScanUseValues),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(BuildContext context) {
    final s = S.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.32;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: Semantics(
              image: true,
              label: s.labelScanTitle,
              child: Image.file(File(_imagePath), fit: BoxFit.contain),
            ),
          ),
          Positioned(
            left: Dimens.spacing12,
            bottom: Dimens.spacing12,
            child: Text(
              _readBy == null
                  ? s.labelScanReadOnDevice
                  : s.labelScanReadByAi(_readBy!),
              style: const TextStyle(
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
          Positioned(
            right: Dimens.spacing12,
            bottom: Dimens.spacing8,
            child: Semantics(
              identifier: 'label-scan-retake',
              child: FilledButton.tonal(
                onPressed: _reading || _aiBusy ? null : _retake,
                child: Text(s.labelScanRetakePhoto),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(
    BuildContext context,
    NutritionLabelValues values,
    LabelEnergyCheck? check,
  ) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ok = check != null && check.passes;
    final String text;
    if (check == null) {
      text = s.labelScanIncomplete;
    } else if (ok) {
      text = s.labelScanMatches(
        check.labelKcal.round().toString(),
        check.computedKcal.round().toString(),
      );
    } else {
      text = s.labelScanMismatch(
        check.labelKcal.round().toString(),
        check.computedKcal.round().toString(),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Dimens.spacing12),
        decoration: BoxDecoration(
          color: ok ? scheme.primaryContainer : scheme.errorContainer,
          borderRadius: Dimens.borderRadiusM,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              color: ok ? scheme.onPrimaryContainer : scheme.onErrorContainer,
            ),
            const SizedBox(width: Dimens.spacing8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: ok
                      ? scheme.onPrimaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fields to highlight: a missing core value, or — when the energy does
  /// not add up — the macro whose reading most plausibly lost a decimal or
  /// a digit.
  Set<_Field> _suspectFields(NutritionLabelValues v, LabelEnergyCheck? check) {
    final suspects = <_Field>{
      if (v.kcal == null) _Field.kcal,
      if (v.fat == null) _Field.fat,
      if (v.carbs == null) _Field.carbs,
      if (v.protein == null) _Field.protein,
    };
    if (check != null && !check.passes) {
      final missing = check.labelKcal - check.computedKcal;
      // Which single macro, multiplied by 10 or divided by 10, closes the
      // gap best?
      _Field? best;
      double bestGap = missing.abs();
      for (final (field, value, density) in [
        (_Field.fat, v.fat!, NutritionLabelParser.kcalPerGramFat),
        (_Field.carbs, v.carbs!, NutritionLabelParser.kcalPerGramCarbs),
        (_Field.protein, v.protein!, NutritionLabelParser.kcalPerGramProtein),
      ]) {
        for (final factor in [10.0, 0.1]) {
          final gap = (missing - (value * factor - value) * density).abs();
          if (gap < bestGap) {
            bestGap = gap;
            best = field;
          }
        }
      }
      suspects.add(best ?? _Field.kcal);
    }
    return suspects;
  }

  Widget _grid(BuildContext context, Set<_Field> suspects) {
    final s = S.of(context);
    final labels = {
      _Field.kcal: s.labelScanKcal,
      _Field.carbs: s.labelScanCarbs,
      _Field.sugars: s.labelScanSugars,
      _Field.fiber: s.labelScanFiber,
      _Field.fat: s.labelScanFat,
      _Field.saturatedFat: s.labelScanSaturated,
      _Field.protein: s.labelScanProtein,
      _Field.salt: s.labelScanSalt,
    };
    final fields = labels.keys.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - Dimens.spacing8) / 2;
        return Wrap(
          spacing: Dimens.spacing8,
          runSpacing: Dimens.spacing8,
          children: [
            for (final f in fields)
              SizedBox(
                width: width,
                child: Semantics(
                  identifier: 'label-scan-field-${f.name}',
                  child: TextField(
                    controller: _controllers[f],
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,4}([.,]\d{0,2})?$'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: suspects.contains(f)
                          ? '${labels[f]} · ${s.labelScanCheck}'
                          : labels[f],
                      filled: suspects.contains(f),
                      border: const OutlineInputBorder(
                        borderRadius: Dimens.borderRadiusM,
                      ),
                      enabledBorder: suspects.contains(f)
                          ? OutlineInputBorder(
                              borderRadius: Dimens.borderRadiusM,
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.tertiary,
                                width: 2,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _pointsResult(BuildContext context, NutritionLabelValues values) {
    final kcal = values.kcal;
    if (kcal == null || kcal <= 0) return const SizedBox.shrink();
    final format = PointsFormat.of(context);
    final per100 = PointsCalc.pointsPer100g(kcal);
    final grams = PointsCalc.gramsPerPoint(per100)!;
    return Container(
      padding: const EdgeInsets.all(Dimens.spacing12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: Dimens.borderRadiusM,
      ),
      child: Text(
        S
            .of(context)
            .labelScanPointsResult(
              format.points(per100),
              format.grams(PointsCalc.roundPracticalGrams(grams)),
            ),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

/// The name of the destination a label photo would be sent to.
String labelScanProviderName(AiSelection selection) =>
    switch (selection.provider) {
      AiProvider.anthropic => 'Anthropic',
      AiProvider.openrouter => 'OpenRouter',
      AiProvider.openai => 'OpenAI',
      AiProvider.ownServer =>
        AiCredentialStorage.displayHost(selection.endpoint ?? '') ?? '',
    };
