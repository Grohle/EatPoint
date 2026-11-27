import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/label_scan/data/remote_nutrition_extractor.dart';
import 'package:opennutritracker/features/menu_import/data/remote_menu_extractor.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_text_parser.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_review_screen.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Imports a menu or a set of recipes into the weekly menu: pasted text, a
/// table copied from a spreadsheet, a text or CSV file, or a photo.
///
/// Reading happens on the phone (text parsing, on-device text recognition
/// for photos). With AI assistance configured, the user can choose to have
/// the AI read it instead; that sends only this text or photo, after asking.
/// Returns the number of days written to the menu.
class MenuImportScreen extends StatefulWidget {
  final DateTime? initialWeek;

  /// Text to start with, e.g. shared to the app from another one.
  final String? initialText;

  const MenuImportScreen({super.key, this.initialWeek, this.initialText});

  @override
  State<MenuImportScreen> createState() => _MenuImportScreenState();
}

class _MenuImportScreenState extends State<MenuImportScreen> {
  late final _text = TextEditingController(text: widget.initialText);
  bool _aiAvailable = false;
  bool _useAi = false;
  bool _busy = false;
  String? _photoPath;
  String? _error;
  List<MealSlot> _slots = MealSlot.builtIn();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (locator.isRegistered<PointsSettingsDataSource>()) {
      final settings = await locator<PointsSettingsDataSource>().getSettings();
      _slots = settings.effectiveMealSlots;
    }
    if (locator.isRegistered<AiCredentialStorage>()) {
      try {
        final available =
            await locator<AiCredentialStorage>().readSelection() != null;
        if (mounted) setState(() => _aiAvailable = available);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<String> _mealNames(BuildContext context) => [
    for (final slot in _slots) mealSlotLabel(context, slot),
  ];

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _text.text = text;
      _photoPath = null;
    });
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'tsv', 'md'],
    );
    final file = files.isEmpty ? null : files.first;
    if (file == null) return;
    final bytes = await file.xFile.readAsBytes();
    setState(() {
      _text.text = utf8.decode(bytes, allowMalformed: true);
      _photoPath = null;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2400,
      imageQuality: 90,
    );
    if (picked == null) return;
    setState(() {
      _photoPath = picked.path;
      _error = null;
    });
    if (!_useAi) await _readPhotoOnDevice(picked.path);
  }

  /// On-device text recognition; the text then goes through the same
  /// parser as typed text, and the user can correct it before reading.
  Future<void> _readPhotoOnDevice(String path) async {
    setState(() => _busy = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      final lines = [
        for (final block in result.blocks)
          for (final line in block.lines) line.text,
      ];
      if (mounted) setState(() => _text.text = lines.join('\n'));
    } catch (_) {
      if (mounted) {
        setState(() => _error = S.of(context).menuImportPhotoUnreadable);
      }
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmAi() async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.menuImportAiConfirmTitle),
        content: Text(s.menuImportAiConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.dialogCancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.menuImportAiConfirmSend),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _read() async {
    final s = S.of(context);
    final names = _mealNames(context);
    final text = _text.text.trim();
    if (text.isEmpty && _photoPath == null) return;
    setState(() {
      _error = null;
    });
    ImportedMenu menu;
    if (_useAi && _aiAvailable) {
      if (!await _confirmAi() || !mounted) return;
      setState(() => _busy = true);
      try {
        final extractor = RemoteMenuExtractor(
          http.Client(),
          locator<AiCredentialStorage>(),
        );
        menu = _photoPath != null && text.isEmpty
            ? await extractor.fromPhoto(_photoPath!, names)
            : await extractor.fromText(text, names);
      } on RemoteExtractionException catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = e.failure == RemoteExtractionFailure.network
                ? s.menuImportAiNetworkError
                : s.menuImportAiBadAnswer;
          });
        }
        return;
      }
    } else {
      menu = MenuTextParser.parse(text, mealNames: names);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (menu.isEmpty) {
      setState(() => _error = s.menuImportNothingFound);
      return;
    }
    final saved = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => MenuImportReviewScreen(
          menu: menu,
          slots: _slots,
          initialWeek: widget.initialWeek,
        ),
      ),
    );
    if (saved != null && mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final hasInput = _text.text.trim().isNotEmpty || _photoPath != null;

    return Scaffold(
      appBar: AppBar(title: Text(s.menuImportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(Dimens.spacing16),
        children: [
          Text(
            s.menuImportIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Dimens.spacing12),
          Wrap(
            spacing: Dimens.spacing8,
            runSpacing: Dimens.spacing8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.content_paste_rounded, size: 18),
                label: Text(s.menuImportPaste),
                onPressed: _busy ? null : _paste,
              ),
              ActionChip(
                avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(s.menuImportCamera),
                onPressed: _busy ? null : () => _pickPhoto(ImageSource.camera),
              ),
              ActionChip(
                avatar: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(s.menuImportGallery),
                onPressed: _busy ? null : () => _pickPhoto(ImageSource.gallery),
              ),
              ActionChip(
                avatar: const Icon(Icons.description_outlined, size: 18),
                label: Text(s.menuImportFile),
                onPressed: _busy ? null : _pickFile,
              ),
            ],
          ),
          if (_photoPath != null) ...[
            const SizedBox(height: Dimens.spacing12),
            ClipRRect(
              borderRadius: Dimens.borderRadiusM,
              child: Image.file(
                File(_photoPath!),
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: Dimens.spacing12),
          Semantics(
            identifier: 'menu-import-text',
            child: TextField(
              controller: _text,
              minLines: 8,
              maxLines: 18,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s.menuImportHint,
                hintMaxLines: 8,
                border: const OutlineInputBorder(
                  borderRadius: Dimens.borderRadiusM,
                ),
              ),
            ),
          ),
          if (_aiAvailable)
            Semantics(
              identifier: 'menu-import-use-ai',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: Text(s.menuImportUseAi),
                subtitle: Text(s.menuImportUseAiHelp),
                value: _useAi,
                onChanged: (v) => setState(() => _useAi = v),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing8),
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: Dimens.spacing16),
          Semantics(
            identifier: 'menu-import-read',
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Dimens.minTouchTarget),
              ),
              onPressed: !hasInput || _busy ? null : _read,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_rounded),
              label: Text(s.menuImportRead),
            ),
          ),
        ],
      ),
    );
  }
}
