import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/core/utils/plaintext_destination_guard.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/features/label_scan/domain/nutrition_label_parser.dart';

/// Why a remote read did not produce values.
enum RemoteExtractionFailure { notConfigured, network, badResponse }

class RemoteExtractionException implements Exception {
  final RemoteExtractionFailure failure;
  final String? detail;

  RemoteExtractionException(this.failure, [this.detail]);

  @override
  String toString() => 'RemoteExtractionException($failure, $detail)';
}

/// Reads a nutrition label photo with the vision model the user configured
/// for AI assistance, as a fallback when the on-device reading does not add
/// up.
///
/// This is a separate path from meal photo logging on purpose: there the
/// model only names foods and every number comes from the food databases.
/// Here the numbers are read off the product's own label, the user starts
/// the request explicitly, and every value is shown in an editable form
/// before anything is saved.
class RemoteNutritionExtractor {
  static const _anthropicEndpoint = 'https://api.anthropic.com/v1/messages';
  static const _openAiEndpoint = 'https://api.openai.com/v1/chat/completions';
  static const _openRouterEndpoint =
      'https://openrouter.ai/api/v1/chat/completions';
  static const timeout = Duration(seconds: 90);

  static const prompt =
      'This photo shows the nutrition facts table of a food product. '
      'Read ONLY the values per 100 g or per 100 ml (never per serving). '
      'Answer with a single JSON object and nothing else, with these keys: '
      '"kcal", "fat", "saturated_fat", "carbs", "sugars", "fiber", '
      '"protein", "salt" (numbers in kcal or grams, null when the label '
      'does not show it; use kcal, not kJ) and "per" ("100g" or "100ml").';

  final _log = Logger('RemoteNutritionExtractor');
  final http.Client _client;
  final AiCredentialStorage _credentials;

  RemoteNutritionExtractor(this._client, this._credentials);

  /// Whether a provider is configured and AI assistance is switched on.
  Future<bool> isAvailable() async =>
      (await _credentials.readSelection()) != null;

  Future<NutritionLabelValues> extract(String imagePath) async {
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
    final data = base64Encode(photo.bytes);

    final String text;
    try {
      text = switch (selection.provider) {
        AiProvider.anthropic => await _anthropic(
          selection.apiKey ?? '',
          model,
          photo.mediaType,
          data,
        ),
        AiProvider.openai => await _chatCompletions(
          _client,
          Uri.parse(_openAiEndpoint),
          selection.apiKey,
          model,
          photo.mediaType,
          data,
        ),
        AiProvider.openrouter => await _chatCompletions(
          _client,
          Uri.parse(_openRouterEndpoint),
          selection.apiKey,
          model,
          photo.mediaType,
          data,
        ),
        AiProvider.ownServer => await _chatCompletions(
          GuardedPlaintextClient(_client),
          Uri.parse(selection.endpoint!),
          selection.apiKey,
          model,
          photo.mediaType,
          data,
          jsonMode: false,
        ),
      };
    } on RemoteExtractionException {
      rethrow;
    } catch (e) {
      _log.warning('Label extraction request failed: $e');
      throw RemoteExtractionException(
        RemoteExtractionFailure.network,
        e.toString(),
      );
    }
    return parseResponse(text);
  }

  Future<String> _anthropic(
    String key,
    String model,
    String mediaType,
    String data,
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
            'max_tokens': 400,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': mediaType,
                      'data': data,
                    },
                  },
                  {'type': 'text', 'text': prompt},
                ],
              },
            ],
          }),
        )
        .timeout(timeout);
    _checkStatus(response);
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final content = (body is Map ? body['content'] : null);
    if (content is List) {
      for (final part in content) {
        if (part is Map && part['type'] == 'text') {
          return part['text'] as String? ?? '';
        }
      }
    }
    throw RemoteExtractionException(RemoteExtractionFailure.badResponse);
  }

  Future<String> _chatCompletions(
    http.Client client,
    Uri endpoint,
    String? key,
    String model,
    String mediaType,
    String data, {
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
            'max_tokens': 400,
            if (jsonMode) 'response_format': {'type': 'json_object'},
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': prompt},
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:$mediaType;base64,$data'},
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

  /// Reads the model's JSON answer. Tolerates a code fence or text around
  /// the object, and rejects values outside what a label can say.
  static NutritionLabelValues parseResponse(String text) {
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
    if (decoded is! Map) {
      throw RemoteExtractionException(RemoteExtractionFailure.badResponse);
    }
    final map = decoded;
    double? read(String key, double max) {
      final raw = map[key];
      final value = raw is num
          ? raw.toDouble()
          : raw is String
          ? double.tryParse(raw.replaceAll(',', '.'))
          : null;
      if (value == null || !value.isFinite || value < 0 || value > max) {
        return null;
      }
      return value;
    }

    return NutritionLabelValues(
      kcal: read('kcal', 900),
      fat: read('fat', 100),
      saturatedFat: read('saturated_fat', 100),
      carbs: read('carbs', 100),
      sugars: read('sugars', 100),
      fiber: read('fiber', 100),
      protein: read('protein', 100),
      salt: read('salt', 100),
      perMl: map['per'] == '100ml',
    );
  }
}
