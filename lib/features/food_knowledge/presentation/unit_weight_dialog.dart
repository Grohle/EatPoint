import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/food_knowledge/data/portion_override_store.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Lets the user say what one unit of a food weighs ("my tortillas are
/// 40 g"), or go back to the app's weight. Returns true when it changed.
Future<bool> showUnitWeightDialog(
  BuildContext context, {
  required String name,
  String? code,
  PortionOverrideStore? store,
}) async {
  final overrides =
      store ??
      (locator.isRegistered<PortionOverrideStore>()
          ? locator<PortionOverrideStore>()
          : null);
  if (overrides == null) return false;
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _UnitWeightDialog(name: name, code: code, store: overrides),
  );
  return changed == true;
}

class _UnitWeightDialog extends StatefulWidget {
  final String name;
  final String? code;
  final PortionOverrideStore store;

  const _UnitWeightDialog({
    required this.name,
    required this.code,
    required this.store,
  });

  @override
  State<_UnitWeightDialog> createState() => _UnitWeightDialogState();
}

class _UnitWeightDialogState extends State<_UnitWeightDialog> {
  final _grams = TextEditingController();
  final _one = TextEditingController();
  final _other = TextEditingController();
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final lang = Localizations.localeOf(context).languageCode;
    final current = FoodPortions.of(widget.name, code: widget.code);
    if (current != null) {
      _grams.text = PointsFormat.of(context).grams(current.grams);
      final names = lang == 'es' ? current.es : current.en;
      _one.text = names.one;
      _other.text = names.other;
    }
  }

  @override
  void dispose() {
    _grams.dispose();
    _one.dispose();
    _other.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_grams.text.replaceAll(',', '.'));

  Future<void> _save() async {
    final grams = _value;
    if (grams == null || grams <= 0) return;
    final s = S.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final one = _one.text.trim().isEmpty ? s.unitWeightDefaultOne : _one.text;
    final other = _other.text.trim().isEmpty
        ? (_one.text.trim().isEmpty ? s.unitWeightDefaultOther : one)
        : _other.text;
    await widget.store.save(
      name: widget.name,
      code: widget.code,
      grams: grams,
      one: one.trim(),
      other: other.trim(),
      languageCode: lang,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    await widget.store.reset(widget.name, widget.code);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final mine = widget.store.hasOverride(widget.name, widget.code);
    return AlertDialog(
      title: Text(s.unitWeightTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Dimens.spacing8),
            Text(s.unitWeightHelp),
            const SizedBox(height: Dimens.spacing12),
            Semantics(
              identifier: 'unit-weight-grams',
              child: TextField(
                controller: _grams,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: s.unitWeightGrams,
                  suffixText: 'g',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Dimens.spacing12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _one,
                    decoration: InputDecoration(
                      labelText: s.unitWeightOne,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: Dimens.spacing8),
                Expanded(
                  child: TextField(
                    controller: _other,
                    decoration: InputDecoration(
                      labelText: s.unitWeightOther,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (mine) TextButton(onPressed: _reset, child: Text(s.unitWeightReset)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        Semantics(
          identifier: 'unit-weight-save',
          child: FilledButton(
            onPressed: (_value ?? 0) > 0 ? _save : null,
            child: Text(s.mealEditorSave),
          ),
        ),
      ],
    );
  }
}
