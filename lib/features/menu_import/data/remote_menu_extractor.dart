import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/core/utils/plaintext_destination_guard.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/features/label_scan/data/remote_nutrition_extractor.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_text_parser.dart';

/// Reads a menu with the AI provider the user configured for AI
/// assistance: from pasted text, or from a photo of a printed or
/// handwritten menu. Only the text or the photo is sent, never the diary or
/// the profile, and the caller asks the user first.
class RemoteMenuExtractor {
  static const _anthropicEndpoint = 'https://api.anthropic.com/v1/messages';
  static const _openAiEndpoint = 'https://api.openai.com/v1/chat/completions';
  static const _openRouterEndpoint =
      'https://openrouter.ai/api/v1/chat/completions';
  static const timeout = Duration(seconds: 120);
  static const _maxTokens = 4000;

  static String prompt(List<String> mealNames) =>
      'Below is a meal plan or a list of recipes (a text, a table or a '
      'photo). Extract every day, meal and food. Answer with one JSON '
      'object and nothing else: {"days":[{"day": weekday in English '
      '("monday".."sunday") or a date "YYYY-MM-DD" or a number for "Day N" '
      'or null, "meals":[{"meal": the meal name as written, or one of '
      '${mealNames.map((n) => '"$n"').join(', ')} when it clearly is one, '
      '"dish": dish name or null, "foods":[{"name": food name in the '
      'language of the source, "grams": number or null (convert kg, ml and '
      'household measures to grams when stated), "count": pieces or null, '
      '"points": number or null when the source gives points, "kcal100", '
      '"carbs100", "protein100", "fat100": your best estimate per 100 g '
      '}]}]}]}. Do not invent foods or amounts that are not in the source; '
      'use null for missing amounts.';

  final _log = Logger('RemoteMenuExtractor');
  final http.Client _client;
  final AiCredentialStorage _credentials;

  RemoteMenuExtractor(this._client, this._credentials);

  Future<bool> isAvailable() async =>
      (await _credentials.readSelection()) != null;

  Future<ImportedMenu> fromText(String text, List<String> mealNames) =>
      _extract(mealNames, text: text);

  Future<ImportedMenu> fromPhoto(String imagePath, List<String> mealNames) =>
      _extract(mealNames, imagePath: imagePath);

  Future<ImportedMenu> _extract(
    List<String> mealNames, {
    String? text,
    String? imagePath,
  }) async {
    final selection = await _credentials.readSelection();
    if (selection == null) {
      throw RemoteExtractionException(RemoteExtractionFailure.notConfigured);
    }
    final model =
        AiModelCatalogue.resolve(selection.provider, selection.modelId)?.id ??
        selection.modelId;
    if (model == null) {
      throw RemoteExtractionException(RemoteExtractionFailure.notConfigured);
    }
    ({String mediaType, String data})? image;
    if (imagePath != null) {
      final photo = await MealPhotoEncoder.encode(
        imagePath,
        format: MealPhotoFormat.forProvider(selection.provider),
      );
      if (photo == null) {
        throw RemoteExtractionException(
          RemoteExtractionFailure.badResponse,
          'photo could not be encoded',
        );
      }
      image = (mediaType: photo.mediaType, data: base64Encode(photo.bytes));
    }
    final instruction = [
      prompt(mealNames),
      if (text != null) '\n\nSOURCE:\n$text',
    ].join();
    final String answer;
    try {
      answer = switch (selection.provider) {
        AiProvider.anthropic => await _anthropic(
          selection.apiKey ?? '',
          model,
          instruction,
          image,
        ),
        AiProvider.openai => await _chat(
          _client,
          Uri.parse(_openAiEndpoint),
          selection.apiKey,
          model,
          instruction,
          image,
        ),
        AiProvider.openrouter => await _chat(
          _client,
          Uri.parse(_openRouterEndpoint),
          selection.apiKey,
          model,
          instruction,
          image,
        ),
        AiProvider.ownServer => await _chat(
          GuardedPlaintextClient(_client),
          Uri.parse(selection.endpoint!),
          selection.apiKey,
          model,
          instruction,
          image,
          jsonMode: false,
        ),
      };
    } on RemoteExtractionException {
      rethrow;
    } catch (e) {
      _log.warning('Menu extraction request failed: $e');
      throw RemoteExtractionException(
        RemoteExtractionFailure.network,
        e.toString(),
      );
    }
    return parseResponse(answer);
  }

  Future<String> _anthropic(
    String key,
    String model,
    String instruction,
    ({String mediaType, String data})? image,
  ) async {
    final response = await _client
        .post(
          Uri.parse(_anthropicEndpoint),
          headers: {
            'x-api-key': key,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': _maxTokens,
            'messages': [
              {
                'role': 'user',
                'content': [
                  if (image != null)
                    {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': image.mediaType,
                        'data': image.data,
                      },
                    },
                  {'type': 'text', 'text': instruction},
                ],
              },
            ],
          }),
        )
        .timeout(timeout);
    _checkStatus(response);
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final content = body is Map ? body['content'] : null;
    if (content is List) {
      for (final part in content) {
        if (part is Map && part['type'] == 'text') {
          return part['text'] as String? ?? '';
        }
      }
    }
    throw RemoteExtractionException(RemoteExtractionFailure.badResponse);
  }

  Future<String> _chat(
    http.Client client,
    Uri endpoint,
    String? key,
    String model,
    String instruction,
    ({String mediaType, String data})? image, {
    bool jsonMode = true,
  }) async {
    final response = await client
        .post(
          endpoint,
          headers: {
            if (key != null && key.isNotEmpty) 'authorization': 'Bearer $key',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': _maxTokens,
            if (jsonMode) 'response_format': {'type': 'json_object'},
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': instruction},
                  if (image != null)
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:${image.mediaType};base64,${image.data}',
                      },
                    },
                ],
              },
            ],
          }),
        )
        .timeout(timeout);
    _checkStatus(response);
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = body is Map ? body['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final message = choices.first is Map ? choices.first['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is String) return content;
    }
    throw RemoteExtractionException(RemoteExtractionFailure.badResponse);
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemoteExtractionException(
        RemoteExtractionFailure.network,
        'HTTP ${response.statusCode}',
      );
    }
  }

  /// Reads the model's JSON. Tolerates text around the object and drops
  /// values that cannot be right (negative grams, energy above pure fat).
  static ImportedMenu parseResponse(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw RemoteExtractionException(RemoteExtractionFailure.badResponse);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } on FormatException {
      throw RemoteExtractionException(RemoteExtractionFailure.badResponse);
    }
    final rawDays = decoded is Map ? decoded['days'] : null;
    if (rawDays is! List) {
      throw RemoteExtractionException(RemoteExtractionFailure.badResponse);
    }
    double? num_(Object? v, double max) {
      final d = v is num
          ? v.toDouble()
          : v is String
          ? double.tryParse(v.replaceAll(',', '.'))
          : null;
      return d == null || !d.isFinite || d < 0 || d > max ? null : d;
    }

    final days = <ImportedDay>[];
    for (final rawDay in rawDays) {
      if (rawDay is! Map) continue;
      final dayValue = rawDay['day'];
      int? weekday;
      DateTime? date;
      int? index;
      if (dayValue is String) {
        weekday = MenuTextParser.weekdayOf(dayValue);
        date = weekday == null ? MenuTextParser.dateOf(dayValue) : null;
        index = weekday == null && date == null ? int.tryParse(dayValue) : null;
      } else if (dayValue is num) {
        index = dayValue.toInt();
      }
      final meals = <ImportedMeal>[];
      final rawMeals = rawDay['meals'];
      if (rawMeals is List) {
        for (final rawMeal in rawMeals) {
          if (rawMeal is! Map) continue;
          final foods = <ImportedFood>[];
          final rawFoods = rawMeal['foods'];
          if (rawFoods is List) {
            for (final f in rawFoods) {
              if (f is! Map) continue;
              final name = (f['name'] as Object?)?.toString().trim() ?? '';
              if (name.isEmpty || name.length > 120) continue;
              final kcal = num_(f['kcal100'], 900);
              final carbs = num_(f['carbs100'], 100);
              final protein = num_(f['protein100'], 100);
              final fat = num_(f['fat100'], 100);
              foods.add(
                ImportedFood(
                  name: name,
                  amount: num_(f['grams'], 5000),
                  unit: num_(f['grams'], 5000) == null ? null : 'g',
                  count: num_(f['count'], 50),
                  points: num_(f['points'], 50),
                  per100:
                      kcal != null &&
                          carbs != null &&
                          protein != null &&
                          fat != null
                      ? ImportedNutrients(
                          kcal: kcal,
                          carbs: carbs,
                          protein: protein,
                          fat: fat,
                        )
                      : null,
                ),
              );
            }
          }
          if (foods.isEmpty) continue;
          final label = rawMeal['meal'];
          final dish = rawMeal['dish'];
          meals.add(
            ImportedMeal(
              label: label is String && label.trim().isNotEmpty
                  ? label.trim()
                  : null,
              dish: dish is String && dish.trim().isNotEmpty
                  ? dish.trim()
                  : null,
              foods: foods,
            ),
          );
        }
      }
      if (meals.isEmpty) continue;
      days.add(
        ImportedDay(weekday: weekday, date: date, index: index, meals: meals),
      );
    }
    return ImportedMenu(days);
  }
}
