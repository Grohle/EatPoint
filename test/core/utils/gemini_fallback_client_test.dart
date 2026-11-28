import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/gemini_fallback_client.dart';

final _gemini = Uri.parse(
  'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
);

Future<http.Response> _post(http.Client client, Uri url, Map body) =>
    client.post(
      url,
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    );

void main() {
  test('a busy model falls back to the next, thinking kept minimal', () async {
    final seen = <Map>[];
    final client = GeminiFallbackClient(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        seen.add(body);
        return body['model'] == 'gemini-flash-latest'
            ? http.Response('high demand', 503)
            : http.Response('{"ok":true}', 200);
      }),
    );
    final response = await _post(client, _gemini, {
      'model': 'gemini-flash-latest',
      'max_tokens': 400,
    });
    expect(response.statusCode, 200);
    expect(seen.map((b) => b['model']), [
      'gemini-flash-latest',
      'gemini-3.5-flash',
    ]);
    expect(seen.last['max_tokens'], GeminiFallbackClient.minTokens);
    expect(seen.last['reasoning_effort'], 'minimal');
  });

  test('a model that gives no answer is left for the next', () async {
    final client = GeminiFallbackClient(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        if (body['model'] == 'gemini-3.8-flash') {
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        return http.Response(jsonEncode({'model': body['model']}), 200);
      }),
      attemptTimeout: const Duration(milliseconds: 50),
    );
    final response = await _post(client, _gemini, {
      'model': 'gemini-3.8-flash',
    });
    expect(jsonDecode(response.body)['model'], 'gemini-flash-latest');
  });

  test('a model that refuses the thinking setting is asked without it', () async {
    final seen = <Map>[];
    final client = GeminiFallbackClient(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        seen.add(body);
        return body.containsKey('reasoning_effort')
            ? http.Response('invalid argument', 400)
            : http.Response('{}', 200);
      }),
    );
    final response = await _post(client, _gemini, {'model': 'gemini-x'});
    expect(response.statusCode, 200);
    expect(seen, hasLength(2));
    expect(seen.last['model'], 'gemini-x');
  });

  test('the last model\'s answer is returned, whatever it is', () async {
    final client = GeminiFallbackClient(
      MockClient((_) async => http.Response('busy', 503)),
    );
    final response = await _post(client, _gemini, {
      'model': 'gemini-flash-latest',
    });
    expect(response.statusCode, 503);
  });

  test('requests to anyone else pass through untouched', () async {
    final other = Uri.parse('https://api.example.org/v1/chat/completions');
    late Map body;
    final client = withGeminiFallback(
      MockClient((request) async {
        body = jsonDecode(request.body) as Map;
        return http.Response('busy', 503);
      }),
      other,
    );
    expect(client, isNot(isA<GeminiFallbackClient>()));
    final response = await _post(client, other, {
      'model': 'x',
      'max_tokens': 10,
    });
    expect(response.statusCode, 503);
    expect(body, {'model': 'x', 'max_tokens': 10});
  });
}
