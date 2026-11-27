import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/label_scan/data/remote_nutrition_extractor.dart';

import 'label_scan_test_support.dart';

class _FakeCredentials implements AiCredentialStorage {
  final AiSelection? selection;
  _FakeCredentials(this.selection);

  @override
  Future<AiSelection?> readSelection() async => selection;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Matcher _failure(RemoteExtractionFailure f) => throwsA(
  isA<RemoteExtractionException>().having((e) => e.failure, 'failure', f),
);

const _json =
    '{"kcal": 247, "fat": 3.4, "saturated_fat": 0.6, "carbs": 41, '
    '"sugars": 4.1, "fiber": 6.8, "protein": 9.6, "salt": 1.1, '
    '"per": "100g"}';

void main() {
  group('parseResponse', () {
    test('reads a plain JSON object', () {
      final v = RemoteNutritionExtractor.parseResponse(_json);
      expect(v.kcal, 247);
      expect(v.fat, 3.4);
      expect(v.saturatedFat, 0.6);
      expect(v.carbs, 41);
      expect(v.sugars, 4.1);
      expect(v.fiber, 6.8);
      expect(v.protein, 9.6);
      expect(v.salt, 1.1);
      expect(v.perMl, isFalse);
    });

    test('tolerates a code fence and surrounding text', () {
      final v = RemoteNutritionExtractor.parseResponse(
        'Here you go:\n```json\n$_json\n```\nHope it helps.',
      );
      expect(v.kcal, 247);
    });

    test('per 100ml sets perMl', () {
      final v = RemoteNutritionExtractor.parseResponse(
        '{"kcal": 43, "per": "100ml"}',
      );
      expect(v.perMl, isTrue);
      expect(v.kcal, 43);
    });

    test('nulls and missing keys stay null', () {
      final v = RemoteNutritionExtractor.parseResponse(
        '{"kcal": 43, "fat": null}',
      );
      expect(v.fat, isNull);
      expect(v.carbs, isNull);
    });

    test('numeric strings, including comma decimals, are read', () {
      final v = RemoteNutritionExtractor.parseResponse(
        '{"fat": "3,4", "carbs": "41", "protein": "abc"}',
      );
      expect(v.fat, 3.4);
      expect(v.carbs, 41);
      expect(v.protein, isNull);
    });

    test('out-of-range values are rejected', () {
      final v = RemoteNutritionExtractor.parseResponse(
        '{"kcal": 901, "fat": 101, "carbs": -1, "protein": 100, "salt": 0}',
      );
      expect(v.kcal, isNull);
      expect(v.fat, isNull);
      expect(v.carbs, isNull);
      expect(v.protein, 100);
      expect(v.salt, 0);
    });

    test('rejects text without an object', () {
      for (final bad in ['', 'no json here', '[1,2]', '{', '}{']) {
        expect(
          () => RemoteNutritionExtractor.parseResponse(bad),
          _failure(RemoteExtractionFailure.badResponse),
          reason: bad,
        );
      }
    });

    test('rejects malformed JSON', () {
      expect(
        () => RemoteNutritionExtractor.parseResponse('{"kcal": }'),
        _failure(RemoteExtractionFailure.badResponse),
      );
    });
  });

  group('extract', () {
    late Directory dir;
    late String photo;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('label_extract');
      photo = '${dir.path}/label.png';
      File(photo).writeAsBytesSync(tinyPng);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('not configured when no selection', () async {
      final x = RemoteNutritionExtractor(
        MockClient((_) async => fail('no request expected')),
        _FakeCredentials(null),
      );
      expect(await x.isAvailable(), isFalse);
      await expectLater(
        x.extract(photo),
        _failure(RemoteExtractionFailure.notConfigured),
      );
    });

    test('Anthropic request and response', () async {
      late http.Request seen;
      final x = RemoteNutritionExtractor(
        MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': _json},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        _FakeCredentials(
          const AiSelection(
            provider: AiProvider.anthropic,
            apiKey: 'sk-test',
            modelId: 'some-model',
          ),
        ),
      );
      expect(await x.isAvailable(), isTrue);
      final v = await x.extract(photo);
      expect(v.kcal, 247);
      expect(v.carbs, 41);
      expect(seen.url.host, 'api.anthropic.com');
      expect(seen.headers['x-api-key'], 'sk-test');
      final body = jsonDecode(seen.body) as Map;
      final content = (body['messages'] as List).first['content'] as List;
      expect(content.map((p) => p['type']), containsAll(['image', 'text']));
    });

    test('OpenAI chat completions response', () async {
      late http.Request seen;
      final x = RemoteNutritionExtractor(
        MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': _json},
                },
              ],
            }),
            200,
          );
        }),
        _FakeCredentials(
          const AiSelection(
            provider: AiProvider.openai,
            apiKey: 'sk-openai',
            modelId: 'some-model',
          ),
        ),
      );
      final v = await x.extract(photo);
      expect(v.protein, 9.6);
      expect(seen.url.host, 'api.openai.com');
      expect(seen.headers['authorization'], 'Bearer sk-openai');
    });

    test('OpenRouter goes to its own endpoint', () async {
      late Uri url;
      final x = RemoteNutritionExtractor(
        MockClient((request) async {
          url = request.url;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': _json},
                },
              ],
            }),
            200,
          );
        }),
        _FakeCredentials(
          const AiSelection(
            provider: AiProvider.openrouter,
            apiKey: 'k',
            modelId: 'some-model',
          ),
        ),
      );
      await x.extract(photo);
      expect(url.host, 'openrouter.ai');
    });

    test('HTTP error is a network failure', () async {
      final x = RemoteNutritionExtractor(
        MockClient((_) async => http.Response('nope', 500)),
        _FakeCredentials(
          const AiSelection(
            provider: AiProvider.openai,
            apiKey: 'k',
            modelId: 'some-model',
          ),
        ),
      );
      await expectLater(
        x.extract(photo),
        _failure(RemoteExtractionFailure.network),
      );
    });

    test('transport exception is a network failure', () async {
      final x = RemoteNutritionExtractor(
        MockClient((_) async => throw const SocketException('down')),
        _FakeCredentials(
          const AiSelection(
            provider: AiProvider.anthropic,
            apiKey: 'k',
            modelId: 'some-model',
          ),
        ),
      );
      await expectLater(
        x.extract(photo),
        _failure(RemoteExtractionFailure.network),
      );
    });

    test('unexpected response shape is a bad response', () async {
      final x = RemoteNutritionExtractor(
        MockClient((_) async => http.Response('{"choices": []}', 200)),
        _FakeCredentials(
          const AiSelection(
            provider: AiProvider.openai,
            apiKey: 'k',
            modelId: 'some-model',
          ),
        ),
      );
      await expectLater(
        x.extract(photo),
        _failure(RemoteExtractionFailure.badResponse),
      );
    });

    test('unreadable photo is a bad response', () async {
      final x = RemoteNutritionExtractor(
        MockClient((_) async => fail('no request expected')),
        _FakeCredentials(
          const AiSelection(
            provider: AiProvider.openai,
            apiKey: 'k',
            modelId: 'some-model',
          ),
        ),
      );
      await expectLater(
        x.extract('${dir.path}/missing.png'),
        _failure(RemoteExtractionFailure.badResponse),
      );
    });
  });
}
